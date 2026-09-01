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
brew install a-grasso/tap/cursorwrap
open -a "$(brew --prefix cursorwrap)/CursorWrap.app"
```

The formula builds from source: the app is signed ad-hoc, and a downloaded
ad-hoc bundle arrives quarantined and Gatekeeper-blocked.

From source instead:

```sh
git clone https://github.com/a-grasso/cursorwrap
cd cursorwrap
./build.sh
open -a "$PWD/CursorWrap.app"
```

Grant Accessibility when prompted, then relaunch - substituting your own
checkout for the brew path if you built from source:

```sh
pkill -f CursorWrap.app
open -a "$(brew --prefix cursorwrap)/CursorWrap.app"
```

The relaunch is required: a process denied at launch caches that answer and
cannot pick up the grant.

`brew install` also puts a `cursorwrap` command on `PATH`. It runs the same
binary in the foreground, which is what `--displays` and `--dry-run` are for;
there the Accessibility grant belongs to your terminal, not to the app bundle.

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
    <string>/opt/homebrew/opt/cursorwrap/CursorWrap.app</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
```

```sh
launchctl load ~/Library/LaunchAgents/dev.agrasso.cursorwrap.plist
```

Launch via `open`, not the inner binary - macOS must attribute the Accessibility
grant to the app bundle. Point it at your own checkout if you built from source.

## Options

| Flag | Default | |
|---|---|---|
| `--min-overshoot N` | 6 | travel past the edge needed to cross |
| `--carry-max N` | 0 | land N px past the far edge |
| `--cooldown S` | 0.05 | ignore edges for S after a crossing |
| `--vertical` | off | also wrap top ↔ bottom |
| `--wrap-drag` | off | cross while a button is held |
| `--warp` | off | relocate via `CGWarp` instead of a synthetic move |
| `--displays` | | print display geometry, exit |
| `--version` | | print the version, exit |
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
- Ad-hoc signed, so **every rebuild - including a `brew upgrade` - invalidates
  the Accessibility grant**. Run `tccutil reset Accessibility
  dev.agrasso.cursorwrap` and re-approve. A real signing identity removes this.

## Contributing

Issues and pull requests welcome - see [CONTRIBUTING.md](CONTRIBUTING.md)
for the build loop, what CI enforces, and the open problems worth taking.

## License

MIT
