# cursorwrap

Wraps the mouse pointer around the outer edges of a multi-display macOS desktop.
Push past the rightmost edge, arrive at the leftmost one.

Built for wide setups where reaching the far display means dragging the pointer
the whole way back.

```
        ultrawide                 laptop
 ┌──────────────────────────┬─────────────┐
 │                          │             │
 │            ────────────────────────►   │
 │  ◄───┐                   │        ┌────┼──►
 └──────┼───────────────────┴────────┼────┘
        └────────── wraps ───────────┘
```

Motion carries through the crossing - the pointer arrives still moving, not
parked on the edge.

## Requirements

- macOS 14+
- Xcode Command Line Tools

## Install

```sh
git clone https://github.com/a-grasso/cursorwrap
cd cursorwrap
./build.sh
open -a "$PWD/CursorWrap.app"
```

Grant Accessibility when prompted, then relaunch:

```sh
pkill -f CursorWrap.app
open -a "$PWD/CursorWrap.app"
```

The relaunch is required: a process denied at launch caches that answer and
cannot pick up the grant.

## Run at login

`~/Library/LaunchAgents/dev.agrasso.cursorwrap.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>dev.agrasso.cursorwrap</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>/ABSOLUTE/PATH/TO/CursorWrap.app</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
```

```sh
launchctl load ~/Library/LaunchAgents/dev.agrasso.cursorwrap.plist
```

Launch via `open`, not the inner binary - macOS must attribute the Accessibility
grant to the app bundle.

## Options

| Flag | Default | |
|---|---|---|
| `--min-overshoot N` | 6 | travel past the edge needed to cross |
| `--carry-max N` | 0 | land N px past the far edge |
| `--cooldown S` | 0.05 | ignore edges for S after a crossing |
| `--vertical` | off | also wrap top ↔ bottom |
| `--wrap-drag` | off | cross while a button is held |
| `--displays` | | print display geometry, exit |
| `--dry-run` | | log crossings without moving |
| `--verbose` | | trace crossings |
| `--log PATH` | | mirror output to a file |

Raise `--min-overshoot` if it crosses when you meant to reach something at the
edge; lower it if crossing takes too much force.

## How it works

macOS clamps the pointer to the union of display bounds, so there is no
coordinate space past an outer edge and position simply stops changing. But
mouse events keep delivering deltas.

1. **Detect on the clamping event.** Its location is already pinned to the edge,
   but its delta still gives the position you were heading for. One event, no
   dwell, no accumulator.
2. **Overshoot as intent.** Reaching for a target at the edge means decelerating
   into it, so overshoot is a few px. Heading for the far display overshoots by
   100+. No timer needed.
3. **Relocate by posting a move event** carrying the original deltas, and swallow
   the clamped one. `CGWarpMouseCursorPosition` briefly dissociates the cursor
   and drops those deltas, so the pointer arrives dead.
4. **Reachable span per row.** The desktop is not a rectangle - displays can be
   offset vertically, so the furthest edge depends on where you are.

Things that do not work, in case you try them: accumulating push after the
pointer is clamped (it sits motionless at the wall for 150-350ms while you
measure); rewriting `event.location` in a tap (changes only what apps read, the
pointer does not move); carrying momentum onto the far display (changes where you
land, not whether you stop).

## Limitations

- One frame at the wall is unavoidable. macOS clamps before handing over the
  event. Reduced to a single event, not zero.
- Apps that capture the pointer (games, VMs, screen sharing) are not excluded.
- Absolute-mode devices (tablets) have no usable delta accumulation.
- Vertical wrap is implemented but lightly tested.
- Ad-hoc signed, so **every rebuild invalidates the Accessibility grant**. Run
  `tccutil reset Accessibility dev.agrasso.cursorwrap` and re-approve. A real
  signing identity removes this.

## License

MIT
