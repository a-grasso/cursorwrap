import Cocoa

// Single source of truth for the shipped version: build.sh reads it out of
// here for Info.plist, and the release workflow refuses a tag that disagrees.
let version = "0.1.2"

// MARK: - config

struct Config {
    var minOvershoot: Double = 6    // intended travel past the edge before crossing
    var carryMax: Double = 0        // how far past the far edge to land (0 = on the edge)
    var cooldown: Double = 0.05     // seconds after a crossing during which edges are ignored
    var vertical = false
    var wrapWhileDragging = false
    var useWarp = false             // relocate with CGWarp instead of rewriting the event
    var dryRun = false
    var verbose = false
}

var cfg = Config()
var showDisplaysAndExit = false

func fail(_ m: String) -> Never {
    FileHandle.standardError.write((m + "\n").data(using: .utf8)!)
    exit(1)
}

var logFH: FileHandle?

func openLog(_ path: String) {
    try? Data().write(to: URL(fileURLWithPath: path))
    guard let fh = FileHandle(forWritingAtPath: path) else { fail("cannot open log: \(path)") }
    logFH = fh
}

// Never called from inside the tap callback on the hot path unless --verbose:
// this does blocking I/O and the callback gates every system mouse event.
func log(_ m: String) {
    guard let d = (m + "\n").data(using: .utf8) else { return }
    FileHandle.standardOutput.write(d)
    logFH?.write(d)
}

var argv = Array(CommandLine.arguments.dropFirst())
var ai = 0
func nextArg(_ name: String) -> String {
    ai += 1
    guard ai < argv.count else { fail("\(name) needs a value") }
    return argv[ai]
}
while ai < argv.count {
    switch argv[ai] {
    case "--min-overshoot": cfg.minOvershoot = Double(nextArg("--min-overshoot")) ?? cfg.minOvershoot
    case "--carry-max":     cfg.carryMax = Double(nextArg("--carry-max")) ?? cfg.carryMax
    case "--cooldown":      cfg.cooldown = Double(nextArg("--cooldown")) ?? cfg.cooldown
    case "--vertical":      cfg.vertical = true
    case "--wrap-drag":     cfg.wrapWhileDragging = true
    case "--warp":          cfg.useWarp = true
    case "--dry-run":       cfg.dryRun = true
    case "-v", "--verbose": cfg.verbose = true
    case "--displays":      showDisplaysAndExit = true
    case "--version":
        print("cursorwrap \(version)")
        exit(0)
    case "--log":           openLog(nextArg("--log"))
    case "-h", "--help":
        print("""
        cursorwrap \(version)

          --displays          print display geometry and exit
          --version           print the version and exit
          --log PATH          mirror output to PATH (truncated each run)
          --min-overshoot N   intended travel past the edge before crossing (default 6)
          --carry-max N       land N px past the far edge (default 0 = on the edge)
          --cooldown S        seconds to ignore edges after a crossing (default 0.05)
          --vertical          also wrap top <-> bottom
          --wrap-drag         cross even while a mouse button is held (default: no)
          --warp              relocate via CGWarpMouseCursorPosition instead of
                              posting a synthetic move (for comparison; CGWarp
                              briefly dissociates the cursor and drops deltas)
          --dry-run           log crossings without moving the pointer
          -v, --verbose       trace edge events (adds I/O to the pointer hot path)
        """)
        exit(0)
    default: fail("unknown argument: \(argv[ai])")
    }
    ai += 1
}

// MARK: - display geometry (CG global space: top-left origin, y down)

var displays: [CGRect] = []
var displaysDirty = true

@discardableResult
func refreshDisplays() -> Bool {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return false }
    displays = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    displaysDirty = false
    return true
}

func reconfigCB(_ d: CGDirectDisplayID, _ f: CGDisplayChangeSummaryFlags, _ u: UnsafeMutableRawPointer?) {
    displaysDirty = true
}

let tol: CGFloat = 2.0

// The two axes are mirror images of one another, so the geometry below is
// written once against whichever one the pointer is travelling along.
enum Axis {
    case horizontal, vertical
    var cross: Axis { self == .horizontal ? .vertical : .horizontal }
}

extension CGRect {
    func low(_ a: Axis) -> CGFloat { a == .horizontal ? minX : minY }
    func high(_ a: Axis) -> CGFloat { a == .horizontal ? maxX : maxY }
    func mid(_ a: Axis) -> CGFloat { a == .horizontal ? midX : midY }
}

extension CGPoint {
    func on(_ a: Axis) -> CGFloat { a == .horizontal ? x : y }
}

func point(_ axis: Axis, travel: CGFloat, cross: CGFloat) -> CGPoint {
    axis == .horizontal ? CGPoint(x: travel, y: cross) : CGPoint(x: cross, y: travel)
}

func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

// How far the pointer can travel along one axis from where it currently is,
// and which displays own the two ends.
struct Span {
    var low: CGFloat
    var high: CGFloat
    var lowDisplay: CGRect
    var highDisplay: CGRect
}

// The desktop is not a rectangle, and along a single axis it need not even be
// gap-free: displays sit at different offsets, get stacked, or touch only
// through a third screen. So the reachable extent is not the whole desktop's -
// it is the contiguous run of displays covering the pointer's position on the
// other axis. macOS walls the pointer at the end of that run, and that wall is
// the one worth wrapping, whether or not it is also the desktop's outer edge.
//
// Both ends have to come from the same run. Measuring the wall per row but
// picking the destination from the whole desktop is what fired the pointer at
// a far display's clamped corner as soon as an arrangement stopped being a
// simple rectangle - and what made the bug appear on one side only, then swap
// sides when the displays were rearranged.
func span(along axis: Axis, at loc: CGPoint) -> Span? {
    let cross = axis.cross
    let c = loc.on(cross)
    // Half-open, so a shared edge belongs to exactly one display. The tolerant
    // retry only covers a pointer resting a hair outside every display, which
    // clamping should prevent but rounding can still produce.
    var band = displays.filter { c >= $0.low(cross) && c < $0.high(cross) }
    if band.isEmpty {
        band = displays.filter { c >= $0.low(cross) - tol && c <= $0.high(cross) + tol }
    }
    guard !band.isEmpty else { return nil }
    band.sort { $0.low(axis) < $1.low(axis) }

    let p = loc.on(axis)
    var i = 0
    while i < band.count {
        let lowDisplay = band[i]           // sorted, so the run starts here
        var highDisplay = band[i]          // running far end, not necessarily the last
        var j = i
        while j + 1 < band.count, band[j + 1].low(axis) <= highDisplay.high(axis) + tol {
            j += 1
            if band[j].high(axis) > highDisplay.high(axis) { highDisplay = band[j] }
        }
        if p >= lowDisplay.low(axis) - tol && p <= highDisplay.high(axis) + tol {
            return Span(low: lowDisplay.low(axis), high: highDisplay.high(axis),
                        lowDisplay: lowDisplay, highDisplay: highDisplay)
        }
        i = j + 1
    }
    return nil
}

// Every distinct reachable span across one display's extent, for --displays.
// The answer changes with position whenever the desktop is not a rectangle,
// and the bands where it changes are exactly where a wrap surprises you.
func bands(along axis: Axis, of r: CGRect) -> [(from: CGFloat, to: CGFloat, span: Span)] {
    let cross = axis.cross
    var cuts: Set<CGFloat> = [r.low(cross), r.high(cross)]
    for d in displays {
        for v in [d.low(cross), d.high(cross)] where v > r.low(cross) && v < r.high(cross) {
            cuts.insert(v)
        }
    }
    let edges = cuts.sorted()
    var out: [(from: CGFloat, to: CGFloat, span: Span)] = []
    for k in 0 ..< max(0, edges.count - 1) {
        let mid = (edges[k] + edges[k + 1]) / 2
        guard let s = span(along: axis, at: point(axis, travel: r.mid(axis), cross: mid)) else { continue }
        if let last = out.last, last.span.low == s.low, last.span.high == s.high {
            out[out.count - 1].to = edges[k + 1]
        } else {
            out.append((from: edges[k], to: edges[k + 1], span: s))
        }
    }
    return out
}

#if CURSORWRAP_TESTS
// tests/spans.swift takes over from here and exits with the result.
runGeometryTests()
#endif

refreshDisplays()
CGDisplayRegisterReconfigurationCallback(reconfigCB, nil)

func reportDisplays() {
    let main = CGDisplayBounds(CGMainDisplayID())
    for (i, r) in displays.enumerated() {
        log(String(format: "display %d: x %.0f..%.0f  y %.0f..%.0f  (%.0f x %.0f)%@",
                   i, r.minX, r.maxX, r.minY, r.maxY, r.width, r.height,
                   r == main ? "  [main]" : ""))
        for b in bands(along: .horizontal, of: r) {
            log(String(format: "    y %.0f..%.0f wraps x %.0f..%.0f%@",
                       b.from, b.to, b.span.low, b.span.high,
                       b.span.lowDisplay == b.span.highDisplay ? "  (within this display)" : ""))
        }
        for b in bands(along: .vertical, of: r) {
            log(String(format: "    x %.0f..%.0f wraps y %.0f..%.0f%@",
                       b.from, b.to, b.span.low, b.span.high,
                       b.span.lowDisplay == b.span.highDisplay ? "  (within this display)" : ""))
        }
    }
}

if showDisplaysAndExit {
    log("cursorwrap \(version)")
    reportDisplays()
    exit(0)
}

// MARK: - state

var lastLoc: CGPoint?
var cooldownUntil: CFAbsoluteTime = 0
var buttonsDown = 0
var crossings = 0
var tapRef: CFMachPort?

// Our own synthetic moves come back through the tap; tag them so we ignore them.
let cwMagic: Int64 = 0x4357_5250
let evSource = CGEventSource(stateID: .hidSystemState)

// MARK: - crossing decision

struct Crossing {
    var target: CGPoint
    var label: String
    var overshoot: Double
}

// Where a movement that just ran into a wall should land, or nil if it did not
// run into one. Pure geometry, so the whole policy is exercisable without a
// pointer; the tap only turns the answer into motion.
func crossing(prev: CGPoint, loc: CGPoint, dx: Double, dy: Double) -> Crossing? {
    if let c = crossing(along: .horizontal, prev: prev, loc: loc, delta: dx) { return c }
    if cfg.vertical, let c = crossing(along: .vertical, prev: prev, loc: loc, delta: dy) { return c }
    return nil
}

func crossing(along axis: Axis, prev: CGPoint, loc: CGPoint, delta: Double) -> Crossing? {
    guard delta != 0, let s = span(along: axis, at: loc) else { return nil }

    let forward = delta > 0
    let wall = forward ? s.high : s.low
    // The pointer has to be pinned against that wall already: this is the event
    // macOS clamped, whose location stopped moving but whose delta still says
    // where the movement was going.
    guard forward ? loc.on(axis) >= wall - tol : loc.on(axis) <= wall + tol else { return nil }

    // Overshoot as intent: reaching for a target at the edge means decelerating
    // into it, heading for the far display does not.
    let intended = Double(prev.on(axis)) + delta
    let overshoot = forward ? intended - Double(wall) : Double(wall) - intended
    guard overshoot >= cfg.minOvershoot else { return nil }

    // The landing point is pinned inside the destination display: the travel
    // axis to its last addressable pixel, the cross axis one further in,
    // because the pointer's cross coordinate came from a display whose extent
    // need not match this one's. The destination is the far end of the same run
    // the wall came from, which for a lone display in its band is that display
    // itself - a stacked arrangement wraps each row within itself.
    let dst = forward ? s.lowDisplay : s.highDisplay
    let carry = CGFloat(min(overshoot, cfg.carryMax))
    let travel = forward
        ? clamp(dst.low(axis) + carry, dst.low(axis), dst.high(axis) - 1)
        : clamp(dst.high(axis) - 1 - carry, dst.low(axis), dst.high(axis) - 1)
    let cross = clamp(loc.on(axis.cross), dst.low(axis.cross) + 1, dst.high(axis.cross) - 2)

    let label: String
    switch (axis, forward) {
    case (.horizontal, true):  label = "right -> left"
    case (.horizontal, false): label = "left -> right"
    case (.vertical, true):    label = "bottom -> top"
    case (.vertical, false):   label = "top -> bottom"
    }
    return Crossing(target: point(axis, travel: travel, cross: cross),
                    label: label, overshoot: overshoot)
}

// MARK: - event tap

func tapCB(proxy: CGEventTapProxy,
           type: CGEventType,
           event: CGEvent,
           refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = tapRef { CGEvent.tapEnable(tap: t, enable: true) }
        return pass
    }

    switch type {
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
        buttonsDown += 1
        return pass
    case .leftMouseUp, .rightMouseUp, .otherMouseUp:
        buttonsDown = max(0, buttonsDown - 1)
        return pass
    default:
        break
    }

    if event.getIntegerValueField(.eventSourceUserData) == cwMagic { return pass }

    // A reconfiguration relocates the pointer as well as the geometry, so the
    // remembered position is no longer this movement's origin. Dropping it
    // costs one event's worth of overshoot instead of inventing one.
    if displaysDirty, refreshDisplays() { lastLoc = nil }

    let loc = event.location
    let prev = lastLoc ?? loc
    lastLoc = loc

    let now = CFAbsoluteTimeGetCurrent()
    if now < cooldownUntil { return pass }
    if buttonsDown > 0 && !cfg.wrapWhileDragging { return pass }

    let dx = Double(event.getIntegerValueField(.mouseEventDeltaX))
    let dy = Double(event.getIntegerValueField(.mouseEventDeltaY))

    guard let c = crossing(prev: prev, loc: loc, dx: dx, dy: dy) else { return pass }

    crossings += 1
    cooldownUntil = now + cfg.cooldown
    if cfg.verbose || cfg.dryRun {
        log(String(format: "cross #%d %@ overshoot=%.0f -> (%.0f, %.0f)%@",
                   crossings, c.label, c.overshoot, c.target.x, c.target.y,
                   cfg.dryRun ? "  [dry-run]" : ""))
    }
    guard !cfg.dryRun else { return pass }
    lastLoc = c.target

    if cfg.useWarp {
        CGWarpMouseCursorPosition(c.target)
        _ = CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        return pass
    }

    // Relocate on the very event that would have clamped, so the pointer never
    // renders at the wall, and do it through the event stream rather than by
    // warping: the cursor is never dissociated, so the deltas carrying the
    // user's motion are not dropped and the pointer arrives still moving. The
    // original clamped event is swallowed so nothing ever sees the pointer at
    // the wall.
    guard let src = evSource,
          let moved = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                              mouseCursorPosition: c.target, mouseButton: .left) else {
        CGWarpMouseCursorPosition(c.target)
        _ = CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        return pass
    }
    moved.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
    moved.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
    moved.setIntegerValueField(.eventSourceUserData, value: cwMagic)
    moved.post(tap: .cghidEventTap)
    return nil
}

// MARK: - main

log("cursorwrap \(version)")
reportDisplays()
log("min-overshoot=\(cfg.minOvershoot) carry-max=\(cfg.carryMax) cooldown=\(cfg.cooldown)s "
    + "vertical=\(cfg.vertical) warp=\(cfg.useWarp) dry-run=\(cfg.dryRun)")

if !AXIsProcessTrusted() {
    log("Accessibility not granted - prompting. Approve CursorWrap, then relaunch")
    log("(a process denied at launch caches that answer and cannot pick up the grant).")
    _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    exit(2)
}
log("Accessibility granted")

let types: [CGEventType] = [.mouseMoved,
                            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                            .leftMouseDown, .leftMouseUp,
                            .rightMouseDown, .rightMouseUp,
                            .otherMouseDown, .otherMouseUp]
let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

// Must be a modifying tap: rewriting the event location is how the crossing
// stays continuous, and a listen-only tap's edits are discarded.
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                  place: .headInsertEventTap,
                                  options: .defaultTap,
                                  eventsOfInterest: mask,
                                  callback: tapCB,
                                  userInfo: nil) else {
    fail("could not create the event tap - check Accessibility permission")
}
tapRef = tap

CFRunLoopAddSource(CFRunLoopGetCurrent(),
                   CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0),
                   .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
log("tap active (modifying). push the pointer past an outer edge. ctrl-c to stop.")
CFRunLoopRun()
