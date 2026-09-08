# cursorwrap wrapped on the wrong edge - investigation (2026-09-08)

Status: **ROOT CAUSE FOUND AND FIXED** in v0.2.1 by polling the display list
(`startDisplayWatchdog()` in `main.swift`). The notification channels this app
relied on are dead on this machine and polling is the only reliable path.

## The report

Two external monitors were attached to a running v0.2.0 agent and the wrap
started firing on the wrong edge.

## What was actually happening

The agent had been up since 2026-09-03, when the laptop was the only display,
and it never noticed the attach. Its own flight trail, five days apart:

```
2026-09-03 00:33:46.749 display refresh ok count=1     <- launch, one display
2026-09-08 10:12:08.827 wrap -> (1727, 513)  displays=1  <- five days later, still one
2026-09-08 10:12:29.485 heartbeat crossings=136 displays=1 dirty=no
```

So every wrap landed at x=1727, the right edge of the laptop panel, while the
pointer was being pushed at the outer edge of a 5896px-wide desktop. A fresh
process read the arrangement correctly, which is what made "restart it" a fix
and hid the bug for five days.

The `dirty=no` in the heartbeat is the load-bearing detail: `displaysDirty` was
never set, so this was not `refreshDisplays()` failing. Nothing ever told the
process the desk had changed. `flightNotable()` passes every non-callback
record, so a `reconfig` record would have been written had one been made.

## Measurements

A three-channel probe (poll thread + `CGDisplayRegisterReconfigurationCallback`
+ `didChangeScreenParameters`) under `CFRunLoopRun()`, against a real display
change produced by switching the main display's mode and back:

- **`CGDisplayRegisterReconfigurationCallback` never fires.** Not on a mode
  change, in a freshly launched process, with the callback registered before
  the run loop starts. Zero callbacks in five days of the real agent, too.
- **`NSApplication.didChangeScreenParametersNotification` never fires**, on
  either the workspace or the default notification center.
- **The four `NSWorkspace` wake/sleep observers never fire** either - zero
  `wake` and zero `sleeping` records across five days including sleeps.
- **Bootstrapping AppKit does not help.** Touching `NSApplication.shared`
  before registering changes nothing; the callback stays silent. This refutes
  the obvious "it is not a real GUI app" explanation, so do not ship
  `NSApplicationLoad()`/`NSApplication.shared` as a fix.
- **Polling works.** `CGGetActiveDisplayList` + `CGDisplayBounds` report the
  new geometry within a second, both directions. They are *not* per-process
  stale, which was the worry that would have sunk this approach.

Why the notifications are dead was not established. The fix does not depend on
knowing.

## The fix

`startDisplayWatchdog()` re-reads the display list once a second on its own
thread and sets `displaysDirty` on any change. It compares **bounds, not
display IDs**: dragging displays in System Settings and changing a resolution
both leave the ID list identical while moving every rect the wrap is measured
against. An ID-comparing first draft passed the geometry tests and silently
failed this exact test.

Only the flag is written from that thread; `displays` stays owned by the tap
thread, preserving the existing single-writer discipline. The reconfiguration
callback is kept - it costs nothing and would only make the refresh prompter.

Verified end to end by flipping the main display's mode under the shipped
build:

```
11:02:37.385 watchdog saw the display list change to 3, cache marked stale
11:02:39.963 display refresh ok count=3
11:02:41.914 watchdog saw the display list change to 3, cache marked stale
11:02:42.236 display refresh ok count=3
```

## Left undone

- `refreshDisplays()` runs on the tap hot path, and the trail above caught it
  costing **42 ms** in one callback right after a change. Harmless at this rate
  (a tap is disabled around 1s) and it only happens when the arrangement
  actually changes, but the geometry read still belongs off the callback -
  see item 2 of the latent-bug list in the 2026-09-02 investigation.
- Why both notification mechanisms are silent for this process.
