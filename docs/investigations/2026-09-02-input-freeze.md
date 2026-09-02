# cursorwrap system-wide input freeze - investigation state (2026-09-02)

Status: **ROOT CAUSE NOT FOUND.** Two hypotheses refuted with measurements.
Do not re-run these. The probe tooling lived in /tmp/cwprobe (probe.swift,
wsping.swift, oob.swift, restore.swift, run*.sh) and is ephemeral: rebuild it
from the descriptions below if the work resumes.

The outcome of this investigation is the flight recorder in `main.swift`, which
exists so the next occurrence leaves evidence behind. See "Reading the flight
recorder" at the end.

## Established facts

- Frozen build: v0.1.0, launched by ~/Library/LaunchAgents/org.nixos.cursorwrap.plist
  via `open -a`, so NO flags: `useWarp=false`, not verbose. Hot path is the
  `post(tap: .cghidEventTap)` branch. v0.1.0 has the same callback shape as the
  0.1.2 working tree (post at :223, refreshDisplays in callback at :176,
  unconditional re-enable).
- Symptoms (from the user): cursor moved NORMALLY, screen alive, clicks +
  keyboard + cmd-tab all dead, killing the process fixed it instantly, 0% CPU,
  happened twice, both correlated with lid reopen / wake from sleep.
- Incident window 2026-09-02: display off 13:08:17 -> on 13:11:36.
- No hang/spindump reports exist. Unified log has no event-tap timeout messages
  (macOS does not routinely log them, so this is NOT exculpatory).
- Accessibility grant: TCC keyed it to the PATH /tmp/cwprobe/cwprobe when the
  user first approved it, and it SURVIVES recompilation at that path. That is
  why the probe can be rebuilt and re-run freely.

## REFUTED #1: blocking / re-entrant tap callback

The whole "modifying tap round-trips events, so a slow callback stalls the
ordered session stream including the keyboard" premise is WRONG.

| test | result |
|---|---|
| `CGEventPost(.cghidEventTap)` inside callback | 1.0 ms max, 0 timeouts |
| `CGGetActiveDisplayList` inside callback | 0.29 ms avg, 14.2 ms max |
| `CGWarpMouseCursorPosition` inside callback | 0.17 ms avg, 10.6 ms max |
| `CGEvent.tapPostEvent` inside callback | 0.00 ms avg |
| callback blocked 600ms x8; stream measured from a SECOND process | 12.4 ms avg / 111 ms max (control: 1.65 / 21.9) |
| callback blocked 3045ms -> tap timeout at ~3s, re-enabled 3x | 1.65 ms avg / 31 ms max = IDENTICAL TO CONTROL |
| independent process WindowServer round trips during 500ms blocks | zero spikes >100ms |

Conclusions: the default tap timeout is ~3 s. A blocked mouse-only modifying
tap degrades the session stream by at most ~100 ms, then the timeout disables
it and everything flows again. The unconditional re-enable does NOT produce a
sustained stall. This family cannot cause a persistent freeze.

## REFUTED #2: pointer parked outside every display

- CONFIRMED: the WindowServer ACCEPTS a modest off-screen absolute move
  verbatim. Posting (-5420, 655) with displays [0..1728] and [-5120..0] left the
  pointer at (-5420, 655), outside every display. Only wild coordinates
  (-13120, 5117) get clamped.
- BUT parking the pointer there does not break input: user typed 59 keys and 7
  clicks normally during the off-screen phase, front app switched fine.
- CAVEAT / only untested variant: real mouse motion pulled the pointer back
  inside within ms (phase ended with inDisplay=yes), so a SUSTAINED off-screen
  pointer with no user motion was never actually held. Weak gap, probably not
  worth chasing.

## Real bugs found, independent of the freeze (not yet fixed)

1. `refreshDisplays()` returns false without clearing `displaysDirty` when
   `CGGetActiveDisplayList` gives count==0, so the cache stays stale and every
   later event retries. Transiently true during lid/wake reconfiguration.
2. The wrap target is clamped only to the CACHED `dst` rect, never validated
   against a live display, so a stale cache can aim the pointer off-screen.
3. `buttonsDown` is a counter that desyncs permanently if a mouseUp is missed
   (happens whenever the tap is disabled between down and up - measured 3
   timeouts in 12 s). Sticks >0 and wrapping silently stops forever. This is
   very likely the "cursorwrap just stopped working" failure mode.
4. Unconditional re-enable on `.tapDisabledByTimeout` with no backoff/ceiling.
5. `log()` does blocking write() on the hot path under --verbose/--dry-run.

## Next step (the only remaining path to proof)

Reproduce for real: relaunch installed 0.1.0 under a hard watchdog, force a
display sleep/wake cycle (`pmset displaysleepnow`, wake by posting input),
and capture `sample <cursorwrap-pid>` + `spindump` DURING the freeze. That is
the one thing that will show who is blocked on whom. Everything cheaper has
been tried.

## Reading the flight recorder

Always on, at `~/Library/Logs/cursorwrap/flight.log`, self-bounding at 8 MB.
A fixed 8192-slot ring in memory holds the fine detail; only notable records
reach the disk trail, so it stays quiet during normal use.

Design constraint: the tap callback only stamps a ring slot. No allocation, no
lock, no I/O on the pointer's thread, because the recorder must never become
the thing that wedges input. A background thread performs every write. Under a
burst the reader falls behind and the oldest records are dropped, which is the
right trade.

What lands on disk:

- callbacks at or above `--flight-slow-ms` (default 20 ms)
- `TAP DISABLED type=N total=N, re-enabling` on every timeout or user disable
- `display reconfiguration flags=0x...` and every refresh, including
  `display refresh FAILED, cache left dirty and stale` which is bug 1 above
  caught in the act
- every `wrap -> (x, y) overshoot=N displays=N`
- `WAKE` and `sleep`, so the trail is anchored to the trigger that correlates
- a 60 s heartbeat with crossings, tap-disables, display count, dirty flag

**When it freezes again:**

```sh
kill -USR1 $(pgrep cursorwrap)     # spill the whole ring for fine detail
kill $(pgrep cursorwrap)           # then recover input as before
tail -200 ~/Library/Logs/cursorwrap/flight.log
```

The seconds immediately before the freeze are what this whole investigation
lacked. `--flight-slow-ms 0` records every callback, which is useful when
reproducing deliberately but far too noisy to leave on.
