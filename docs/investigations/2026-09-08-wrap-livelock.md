# cursorwrap froze the pointer - investigation (2026-09-08)

Status: **ROOT CAUSE FOUND AND FIXED** in v0.2.2 by refusing to wrap a wall the
pointer is still standing on (`wrappedWall` in `decide()`).

## The report

"The laptop is deadlocked again." Input felt frozen: the pointer would not
leave the right-hand edge of the desktop. It had happened before and had always
been cleared by restarting or waiting it out, so nothing was ever captured.

## What the flight recorder caught

The always-on trail at `~/Library/Logs/cursorwrap/flight.log` recorded the whole
episode, 12:45:47 to 12:51:34, on a v0.2.0 agent up since 10:14.

```
12:48:37.869 wrap -> (0, 758)   overshoot=75
12:48:37.928 wrap -> (0, 1014)  overshoot=170
12:48:38.122 wrap -> (0, 1028)  overshoot=9
12:48:38.177 wrap -> (0, 980)   overshoot=111
12:48:38.234 wrap -> (0, 1122)  overshoot=36
12:48:38.452 wrap -> (0, 1122)  overshoot=12
12:48:38.510 wrap -> (0, 1130)  overshoot=150
12:48:38.563 wrap -> (0, 1200)  overshoot=19
```

Eight wraps in 700 ms, every one of them to the same edge, spaced 53-58 ms
apart - the 50 ms `cooldown` floor. Healthy operation in the same log alternates
between the two edges seconds apart. Alongside them, 12
`TAP DISABLED type=4294967294` (`kCGEventTapDisabledByTimeout`) in six minutes,
against zero in the preceding five days of trail.

## It is a livelock, not a deadlock

Worth stating plainly, because the name it was reported under sends you looking
for the wrong thing:

- The heartbeat thread ticked every 60.4 s straight through the episode. It
  never missed a beat.
- A `sample` of the process shows two threads: the main thread parked in
  `CFRunLoopRun` / `mach_msg2_trap`, and the recorder in `usleep`. Nothing was
  blocked and nothing held a lock.
- CPU time over the whole 2 h 37 min life of the process was 34 seconds.

## Root cause

A wrap is a promise that the pointer will turn up at the target. When the
relocation is dropped instead - refused, or posted while the tap happened to be
disabled - the pointer is still pinned against the wall it just crossed. The
next event therefore describes exactly the same crossing: location at the wall,
delta still pushing past it, `overshoot == dx`, which clears `minOvershoot` (6)
trivially. So the wrap fires again, and the one after that, once per cooldown,
for as long as the user keeps pushing.

The pointer never moves. From the outside that is indistinguishable from frozen
input, which is why it was always reported as a deadlock.

That the cross-axis coordinate kept changing (`758, 1014, 1028, 980, 1122...`)
while the travel axis stayed welded to the wall is the tell: the mouse was
moving, and the relocation was landing on neither axis.

### What it was not

cursorwrap's own callback being slow. The recorder writes any callback at or
over 20 ms; in the entire episode exactly one record appears, at 21.18 ms, and
its `type` is 4294967294 - the `CGEvent.tapEnable` re-enable path, not geometry.
Geometry never crossed 20 ms once.

## The fix

`tapCB` is split into `decide()` - the whole per-event decision, in terms of
numbers rather than CGEvents - and a thin adapter that turns the answer into
motion. `decide()` remembers the wall each wrap crossed and refuses to wrap that
wall again until an event shows the pointer off it. After a relocation that
worked, that is the very next event, since the far side of the desktop is not
within `tol` of the wall it came from. After one that was dropped, the wall is
held and wrapping simply stops until the pointer moves by itself.

Wrapping degrading to not working beats the pointer degrading to not moving.

An earlier reading of this blamed `lastLoc = loc` running before the cooldown
check, which discards the wrap's target as the origin of the next movement.
Moving it below the check does slow the loop, but only to one wrap per two
events - the pointer is still pinned. The wall guard is what actually closes it,
and with the guard in place the ordering no longer matters, so it was left alone.

## Regression test

`tests/spans.swift` drives `decide()` over a run of events with a
`relocationLands` switch, rather than driving `crossing()` over a single event:
every individual crossing in this freeze was judged correctly, and the bug lives
entirely in what one event's state does to the next. With the relocation dropped
over 200 events (1.6 s of pushing), the unguarded code wraps 29 times and the
guarded code wraps once.

## Still open

Why the relocation is dropped in the first place is not established. The tap
being disabled by timeout at that moment is the obvious suspect and the two are
interleaved in the trail, but the ordering does not prove direction. The fix
makes the freeze impossible either way, and `RELOCATION LOST` now appears in the
trail with the wall and a running count, so the next occurrence will say so
directly. Decide on a `CGWarpMouseCursorPosition` fallback once there is data,
not before.
