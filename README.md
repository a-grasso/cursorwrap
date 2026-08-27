# cursorwrap

Prototype: when the pointer reaches an outer edge of the multi-display desktop,
continue onto the opposite outer edge. Built to answer whether this can feel
like crossing a native display boundary before porting it into a real app.

## Build / run

    ./build.sh
    open -a "$PWD/CursorWrap.app" --args --log "$PWD/run.log"

Tuning is all CLI args, so trying new numbers needs no rebuild (and so keeps the
Accessibility grant). `--help` lists them. `--dry-run` logs wraps without moving
the pointer; `--verbose` traces edge state - but see the latency note below.

## What the spike established

**Deltas keep arriving while the pointer is clamped.** This was the load-bearing
unknown: macOS clamps the pointer to the union of display bounds, so at an outer
edge `location` stops changing and there is no coordinate space beyond it. But
`mouseMoved` events keep delivering `kCGMouseEventDeltaX`. So "user wants to keep
going" is detectable by accumulating deltas while pinned, not by watching
position. Everything else depends on this.

**The desktop is not a rectangle.** Displays can be offset vertically, so the
furthest-right x the pointer can reach depends on y. Edge tests must use the
reachable span at the current y (`rowSpan`), not the union bounds.

**Arrival momentum must not count.** Counting the delta of the event that lands
you at the edge means a single fast flick toward a scrollbar wraps you across the
whole desktop. Measured arrival deltas were +126, +150, +189 in one event -
enough to clear any usable threshold instantly. Restarting the accumulator on
entering the pinned state, and gating on a short dwell, fixes it. With `--dwell 0`
the arrival delta counts again, which is what makes crossing feel immediate; that
is a deliberate tradeoff, not an oversight.

**The stop is in the detection method, not the thresholds.** Accumulating push
*after* the pointer is clamped means it necessarily sits motionless at the wall
while you measure - 150-350ms in practice. No threshold removes that. Instead,
act on the single event that would have clamped: its location is already pinned to
the edge, but its delta still tells you the position you were heading for, so
overshoot is known immediately. One event, no dwell, no accumulator. This deleted
the dwell/threshold machinery entirely.

**Overshoot magnitude is a better intent signal than time.** Reaching for a target
at the edge means decelerating into it (Fitts' law), so overshoot is a few px.
Heading for the other display overshoots by 100+. `--min-overshoot` separates
them without any timer. ~15 felt about right; 40 needed too much force.

**Rewriting `event.location` in a tap does NOT move the pointer.** It changes only
what applications read. The window server owns cursor position. This looked like
a total failure ("nothing moves") while the log showed 106 correct crossings -
detection and relocation fail independently, so check both.

**`CGWarpMouseCursorPosition` briefly dissociates the cursor** and drops the
deltas carrying the user's motion, so the pointer arrives dead even when it lands
in the right place. `CGAssociateMouseAndMouseCursorPosition(true)` afterwards does
not fully fix it. Posting a synthetic `.mouseMoved` at the target that carries the
original event's deltas, and swallowing the clamped event, relocates through the
normal event stream with no dissociation. Tag synthetic events
(`.eventSourceUserData`) and ignore them on re-entry or they feed back.

**Landing position and arriving-in-motion are independent.** Carrying momentum
into the far display just teleports you further in; it does not make the crossing
continuous. Land on the edge (`--carry-max 0`) and preserve the motion instead.

## macOS permission notes (cost real time)

- The event tap needs Accessibility. Run from a terminal and the permission is
  attributed to the *terminal*, not the tool - hence the `.app` bundle, so TCC
  can identify it as itself. Launch via `open`, not by exec'ing the inner binary,
  or LaunchServices is not the responsible process.
- Bundles under `/private/tmp` do not reliably register with TCC at all. A real
  path fixed it.
- Ad-hoc signing has no stable identity, so **every rebuild invalidates the
  grant** (new cdhash reads as a different app). Toggling the existing checkbox
  does not help - it grants the old hash. `tccutil reset Accessibility
  dev.agrasso.cursorwrap` then re-approve. A real signing identity would remove
  this entirely.
- `AXIsProcessTrusted()` is cached for the lifetime of a process that was denied
  at launch, so polling for the grant never succeeds. The process must be
  restarted after approval.

## Open questions

- The ultrawide extends 323px above the MacBook's top edge. In that band the
  desktop's right-hand outer edge is x=0, so pushing right there wraps to the
  ultrawide's own left edge rather than crossing to the MacBook. Consistent with
  "the outer edge is the outer edge", but unverified by feel.
- Apps that capture the pointer (games, VMs, screen sharing) need excluding.
- Absolute-mode devices (tablets) have no meaningful delta accumulation.
- Vertical wrap (`--vertical`) is implemented but untested.
