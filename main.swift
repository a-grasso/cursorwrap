import Cocoa

let VERSION = "cursorwrap-proto 0.2 (continuous)"

// MARK: - config

struct Config {
    var minOvershoot: Double = 40   // intended travel past the edge before crossing
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

var logFH: FileHandle? = nil

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
    case "--log":           openLog(nextArg("--log"))
    case "-h", "--help":
        print("""
        \(VERSION)

          --displays          print display geometry and exit
          --log PATH          mirror output to PATH (truncated each run)
          --min-overshoot N   intended travel past the edge before crossing (default 40)
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

func refreshDisplays() {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return }
    displays = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    displaysDirty = false
}

func reconfigCB(_ d: CGDirectDisplayID, _ f: CGDisplayChangeSummaryFlags, _ u: UnsafeMutableRawPointer?) {
    displaysDirty = true
}

let tol: CGFloat = 2.0

// The desktop is not necessarily a rectangle, so the reachable extent depends
// on where you are along the other axis.
func rowSpan(atY y: CGFloat) -> (minX: CGFloat, maxX: CGFloat)? {
    let row = displays.filter { y >= $0.minY - tol && y <= $0.maxY + tol }
    guard let lo = row.map({ $0.minX }).min(), let hi = row.map({ $0.maxX }).max() else { return nil }
    return (lo, hi)
}

func colSpan(atX x: CGFloat) -> (minY: CGFloat, maxY: CGFloat)? {
    let col = displays.filter { x >= $0.minX - tol && x <= $0.maxX + tol }
    guard let lo = col.map({ $0.minY }).min(), let hi = col.map({ $0.maxY }).max() else { return nil }
    return (lo, hi)
}

func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

refreshDisplays()
CGDisplayRegisterReconfigurationCallback(reconfigCB, nil)

if showDisplaysAndExit {
    log(VERSION)
    for (i, r) in displays.enumerated() {
        log(String(format: "display %d: x %.0f..%.0f  y %.0f..%.0f  (%.0f x %.0f)",
                   i, r.minX, r.maxX, r.minY, r.maxY, r.width, r.height))
    }
    exit(0)
}

// MARK: - state

var lastLoc: CGPoint? = nil
var cooldownUntil: CFAbsoluteTime = 0
var buttonsDown = 0
var crossings = 0
var tapRef: CFMachPort? = nil

// Our own synthetic moves come back through the tap; tag them so we ignore them.
let CW_MAGIC: Int64 = 0x4357_5250
let evSource = CGEventSource(stateID: .hidSystemState)

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

    if event.getIntegerValueField(.eventSourceUserData) == CW_MAGIC { return pass }

    if displaysDirty { refreshDisplays() }

    let loc = event.location
    let prev = lastLoc ?? loc
    lastLoc = loc

    let now = CFAbsoluteTimeGetCurrent()
    if now < cooldownUntil { return pass }
    if buttonsDown > 0 && !cfg.wrapWhileDragging { return pass }

    let dx = Double(event.getIntegerValueField(.mouseEventDeltaX))
    let dy = Double(event.getIntegerValueField(.mouseEventDeltaY))

    // Relocate on the very event that would have clamped, so the pointer never
    // renders at the wall. Rewriting the event's location keeps the motion
    // continuous; CGWarp would first commit the clamped position and then jump.
    func cross(_ target: CGPoint, _ label: String, _ overshoot: Double) -> Unmanaged<CGEvent>? {
        crossings += 1
        cooldownUntil = now + cfg.cooldown
        if cfg.verbose || cfg.dryRun {
            log(String(format: "cross #%d %@ overshoot=%.0f -> (%.0f, %.0f)%@",
                       crossings, label, overshoot, target.x, target.y,
                       cfg.dryRun ? "  [dry-run]" : ""))
        }
        guard !cfg.dryRun else { return pass }
        lastLoc = target

        if cfg.useWarp {
            CGWarpMouseCursorPosition(target)
            _ = CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            return pass
        }

        // Relocate through the event stream rather than by warping: the cursor
        // is never dissociated, so the deltas carrying the user's motion are not
        // dropped and the pointer arrives still moving. The original clamped
        // event is swallowed so nothing ever sees the pointer at the wall.
        guard let src = evSource,
              let moved = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                                  mouseCursorPosition: target, mouseButton: .left) else {
            CGWarpMouseCursorPosition(target)
            _ = CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            return pass
        }
        moved.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        moved.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        moved.setIntegerValueField(.eventSourceUserData, value: CW_MAGIC)
        moved.post(tap: .cghidEventTap)
        return nil
    }

    // --- horizontal ---
    if let span = rowSpan(atY: loc.y) {
        // Where this movement wanted to put the pointer, had the desktop continued.
        let intended = Double(prev.x) + dx

        if dx > 0 && loc.x >= span.maxX - tol {
            let overshoot = intended - Double(span.maxX)
            if overshoot >= cfg.minOvershoot, let dst = displays.min(by: { $0.minX < $1.minX }) {
                let carry = CGFloat(min(overshoot, cfg.carryMax))
                return cross(CGPoint(x: clamp(dst.minX + carry, dst.minX, dst.maxX - 1),
                                     y: clamp(loc.y, dst.minY + 1, dst.maxY - 2)),
                             "right -> left", overshoot)
            }
        }
        if dx < 0 && loc.x <= span.minX + tol {
            let overshoot = Double(span.minX) - intended
            if overshoot >= cfg.minOvershoot, let dst = displays.max(by: { $0.maxX < $1.maxX }) {
                let carry = CGFloat(min(overshoot, cfg.carryMax))
                return cross(CGPoint(x: clamp(dst.maxX - 1 - carry, dst.minX, dst.maxX - 1),
                                     y: clamp(loc.y, dst.minY + 1, dst.maxY - 2)),
                             "left -> right", overshoot)
            }
        }
    }

    // --- vertical ---
    if cfg.vertical, let span = colSpan(atX: loc.x) {
        let intended = Double(prev.y) + dy

        if dy > 0 && loc.y >= span.maxY - tol {
            let overshoot = intended - Double(span.maxY)
            if overshoot >= cfg.minOvershoot, let dst = displays.min(by: { $0.minY < $1.minY }) {
                let carry = CGFloat(min(overshoot, cfg.carryMax))
                return cross(CGPoint(x: clamp(loc.x, dst.minX + 1, dst.maxX - 2),
                                     y: clamp(dst.minY + carry, dst.minY, dst.maxY - 1)),
                             "bottom -> top", overshoot)
            }
        }
        if dy < 0 && loc.y <= span.minY + tol {
            let overshoot = Double(span.minY) - intended
            if overshoot >= cfg.minOvershoot, let dst = displays.max(by: { $0.maxY < $1.maxY }) {
                let carry = CGFloat(min(overshoot, cfg.carryMax))
                return cross(CGPoint(x: clamp(loc.x, dst.minX + 1, dst.maxX - 2),
                                     y: clamp(dst.maxY - 1 - carry, dst.minY, dst.maxY - 1)),
                             "top -> bottom", overshoot)
            }
        }
    }

    return pass
}

// MARK: - main

log(VERSION)
for (i, r) in displays.enumerated() {
    log(String(format: "display %d: x %.0f..%.0f  y %.0f..%.0f", i, r.minX, r.maxX, r.minY, r.maxY))
}
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
