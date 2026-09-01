import Cocoa

// Compiled in only by tests/run.sh, which builds main.swift with
// -DCURSORWRAP_TESTS so `runTests()` replaces the event tap as the entry point.
// It drives the real span() and crossing() code over synthetic arrangements:
// pointer geometry is what breaks when a display is moved, and it is the one
// part that cannot be exercised by pushing a real pointer on a CI runner.

private var checks = 0
private var failures: [String] = []
private var arrangement = ""

private func arrange(_ name: String, _ rects: [CGRect], _ body: () -> Void) {
    arrangement = name
    displays = rects
    displaysDirty = false
    body()
}

private func rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: w, height: h)
}

private func inside(_ p: CGPoint) -> Bool {
    displays.contains { p.x >= $0.minX && p.x < $0.maxX && p.y >= $0.minY && p.y < $0.maxY }
}

// What macOS does to a movement that leaves the desktop: the pointer cannot
// leave the union of display bounds and does not jump a gap, so travel stops at
// the first boundary it cannot pass. Stepped a pixel at a time and deliberately
// not written in terms of span(), so a bug in span() cannot hide behind the
// test's own idea of where the wall is.
private func clampedMove(from p: CGPoint, dx: Double, dy: Double) -> CGPoint {
    var out = p
    for (delta, horizontal) in [(dx, true), (dy, false)] where delta != 0 {
        let step: CGFloat = delta > 0 ? 1 : -1
        for _ in 0 ..< Int(abs(delta)) {
            let next = horizontal ? CGPoint(x: out.x + step, y: out.y)
                                  : CGPoint(x: out.x, y: out.y + step)
            if !inside(next) { break }
            out = next
        }
    }
    return out
}

private func push(from p: CGPoint, dx: Double, dy: Double) -> Crossing? {
    crossing(prev: p, loc: clampedMove(from: p, dx: dx, dy: dy), dx: dx, dy: dy)
}

private func fail(_ what: String, _ detail: String) {
    failures.append("\(arrangement): \(what)\n    \(detail)")
}

private func expect(_ what: String, from p: CGPoint, dx: Double = 0, dy: Double = 0,
                    lands: CGPoint) {
    checks += 1
    guard let c = push(from: p, dx: dx, dy: dy) else {
        return fail(what, "expected a crossing to (\(lands.x), \(lands.y)), got none")
    }
    if c.target != lands {
        return fail(what, "landed at (\(c.target.x), \(c.target.y)), "
                        + "expected (\(lands.x), \(lands.y))")
    }
    // Holds for every crossing: a target outside the desktop is one macOS
    // would clamp somewhere else entirely.
    if !inside(c.target) {
        fail(what, "landed at (\(c.target.x), \(c.target.y)), which is outside every display")
    }
}

private func expectNothing(_ what: String, from p: CGPoint, dx: Double = 0, dy: Double = 0) {
    checks += 1
    if let c = push(from: p, dx: dx, dy: dy) {
        fail(what, "expected no crossing, got \(c.label) -> (\(c.target.x), \(c.target.y))")
    }
}

// Terminates the process rather than returning a status, so the rest of
// main.swift stays reachable code as far as the compiler is concerned.
func runGeometryTests() {
    let laptop = rect(x: 0, y: 0, w: 1728, h: 1117)

    // The reporter's own arrangement: the ultrawide is bottom-aligned with the
    // laptop, so its top 321px is a band the laptop does not cover at all.
    arrange("ultrawide left of laptop", [laptop, rect(x: -5120, y: -323, w: 5120, h: 1440)]) {
        expect("shared band, right edge wraps to the far left",
               from: CGPoint(x: 1600, y: 500), dx: 200, lands: CGPoint(x: -5120, y: 500))
        expect("shared band, left edge wraps to the far right",
               from: CGPoint(x: -5000, y: 500), dx: -200, lands: CGPoint(x: 1727, y: 500))

        // Regression: the row here is the ultrawide alone, so both ends of the
        // wrap belong to it. Picking the destination from the whole desktop
        // sent this to the laptop's clamped top-right corner instead.
        expect("ultrawide-only band, left edge wraps within the ultrawide",
               from: CGPoint(x: -5000, y: -100), dx: -200, lands: CGPoint(x: -1, y: -100))
        expect("ultrawide-only band, right edge wraps within the ultrawide",
               from: CGPoint(x: -200, y: -100), dx: 400, lands: CGPoint(x: -5120, y: -100))

        expectNothing("reaching for a target at the edge does not cross",
                      from: CGPoint(x: 1725, y: 500), dx: 3)
        expectNothing("moving away from a wall does not cross",
                      from: CGPoint(x: 1727, y: 500), dx: -200)
        expectNothing("vertical is off by default",
                      from: CGPoint(x: 500, y: 1000), dy: 200)

        cfg.vertical = true
        expect("--vertical wraps within the laptop's own column",
               from: CGPoint(x: 500, y: 1000), dy: 200, lands: CGPoint(x: 500, y: 0))
        cfg.vertical = false
    }

    // Same two displays, arrangement mirrored: every expectation flips sides.
    arrange("ultrawide right of laptop", [laptop, rect(x: 1728, y: -323, w: 5120, h: 1440)]) {
        expect("shared band, right edge wraps to the far left",
               from: CGPoint(x: 6700, y: 500), dx: 200, lands: CGPoint(x: 0, y: 500))
        expect("shared band, left edge wraps to the far right",
               from: CGPoint(x: 100, y: 500), dx: -200, lands: CGPoint(x: 6847, y: 500))
        expect("ultrawide-only band, right edge wraps within the ultrawide",
               from: CGPoint(x: 6600, y: -100), dx: 400, lands: CGPoint(x: 1728, y: -100))
        expect("ultrawide-only band, left edge wraps within the ultrawide",
               from: CGPoint(x: 1900, y: -100), dx: -400, lands: CGPoint(x: 6847, y: -100))
        expectNothing("crossing the seam between two displays is not a wrap",
                      from: CGPoint(x: 1700, y: 500), dx: 100)
    }

    // Stacked in Display Settings. Each row is one display wide, so left and
    // right have to wrap within the row the pointer is on.
    arrange("ultrawide stacked above laptop",
            [rect(x: 0, y: 0, w: 5120, h: 1440), rect(x: 1696, y: 1440, w: 1728, h: 1117)]) {
        expect("the laptop row wraps within the laptop",
               from: CGPoint(x: 3300, y: 2000), dx: 200, lands: CGPoint(x: 1696, y: 2000))
        expect("the ultrawide row wraps within the ultrawide",
               from: CGPoint(x: 5000, y: 700), dx: 200, lands: CGPoint(x: 0, y: 700))

        cfg.vertical = true
        expect("--vertical crosses between the stacked displays",
               from: CGPoint(x: 2500, y: 2400), dy: 200, lands: CGPoint(x: 2500, y: 0))
        expect("--vertical wraps within the ultrawide where the laptop is absent",
               from: CGPoint(x: 500, y: 1300), dy: 200, lands: CGPoint(x: 500, y: 0))
        cfg.vertical = false
    }

    // Two displays joined only through a third, leaving a hole in the top row:
    // the desktop's extent there is 0..3000 but the pointer cannot cross the gap.
    arrange("two displays bridged by a third below",
            [rect(x: 0, y: 0, w: 1000, h: 1000),
             rect(x: 2000, y: 0, w: 1000, h: 1000),
             rect(x: 0, y: 1000, w: 3000, h: 1000)]) {
        expect("a wall at a hole wraps to the near end of its own run",
               from: CGPoint(x: 900, y: 500), dx: 200, lands: CGPoint(x: 0, y: 500))
        expect("the run on the far side of the hole wraps within itself",
               from: CGPoint(x: 2100, y: 500), dx: -200, lands: CGPoint(x: 2999, y: 500))
        expect("the bridging display spans the whole width",
               from: CGPoint(x: 2900, y: 1500), dx: 200, lands: CGPoint(x: 0, y: 1500))
    }

    arrange("single display", [laptop]) {
        expect("right edge wraps to the left edge",
               from: CGPoint(x: 1600, y: 500), dx: 200, lands: CGPoint(x: 0, y: 500))
        expect("left edge wraps to the right edge",
               from: CGPoint(x: 100, y: 500), dx: -200, lands: CGPoint(x: 1727, y: 500))

        cfg.carryMax = 20
        expect("--carry-max lands that far past the far edge",
               from: CGPoint(x: 1600, y: 500), dx: 200, lands: CGPoint(x: 20, y: 500))
        cfg.carryMax = 0
    }

    // What a CI runner looks like.
    arrange("no displays", []) {
        expectNothing("an empty display list never crosses",
                      from: CGPoint(x: 0, y: 0), dx: 200)
        expectNothing("an empty display list has no bands",
                      from: CGPoint(x: 0, y: 0), dy: 200)
    }

    for f in failures { log("FAIL \(f)") }
    log("\(checks - failures.count)/\(checks) geometry checks passed")
    exit(failures.isEmpty ? 0 : 1)
}
