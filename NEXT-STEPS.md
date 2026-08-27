# Next steps

Decision (2026-08-27): package for this machine via mac-nix + launchd first,
then offer the feature upstream to Vorssaint. Not in conflict - a working local
install stands on its own if the PR stalls.

## 0. Confirm the tuning, then bake it in

Currently launched with `--min-overshoot 6`, UNCONFIRMED. `15` was confirmed
smooth; `6` was an attempt to let slower movements cross too and was never
verified against the thing it risks - being able to park at the edge (scrollbars,
window close buttons, dragging a window to the edge). Settle this first, since
the launchd agent will hard-code it.

`40` needed too much force. Expect the usable floor somewhere around 3-10.

## 1. Stable code signing identity (do before packaging)

The reason to do this first: ad-hoc signing has no stable designated requirement,
so **every rebuild invalidates the Accessibility grant** (new cdhash reads as a
different app). Under nix this is worse than it was today - every update produces
a new store path and binary, so a re-approval per update.

Fix: create a one-time self-signed code-signing certificate, trust it (needs
sudo), and sign with it in `build.sh` instead of `--sign -`. Grants then survive
rebuilds.

## 2. mac-nix packaging

Config repo is `~/.config/nix` (github:a-grasso/mac-nix). **Read its AGENTS.md
first.** Never install imperatively.

Existing launchd agent definitions to follow as the pattern: `cloudcli`,
`portbook`, `paseo`, `claude-telemetry`.

Specific to this one:
- It is a GUI-session agent needing Accessibility, so it must run as a user
  launchd agent, not a daemon.
- It must be launched such that TCC attributes the permission to the `.app`
  bundle, not to a parent process. Today that meant `open -a`, not exec'ing the
  inner binary - verify how that interacts with launchd, as this is the most
  likely thing to break.
- `LSUIElement` is already set, so no dock icon.

## 3. Vorssaint contribution

**Verify before investing.** The claims that Vorssaint exists, is actively
maintained, supports macOS 14+/Apple Silicon, and has no cursor-wrap feature all
came from a session prior to this work and were never checked against the repo.
Confirm the feature is genuinely absent from the source, not just from the README.

Why upstream is attractive: it already has signing/notarization, a settings UI,
and app-exclusion infrastructure. That last one answers our hardest open item
(pointer-capturing apps) rather than making us reimplement it.

Lead with the working prototype and the mechanism findings in README.md - the
four failed approaches are the valuable part of the contribution, not the ~200
lines of Swift.

## Still unresolved

- Pointer-capturing apps (games, VMs, screen sharing) need excluding.
- Absolute-mode devices (tablets) have no meaningful delta accumulation.
- Vertical wrap (`--vertical`) implemented, untested.
- The 323px band where the ultrawide extends above the MacBook: pushing right
  there wraps to the ultrawide's own left edge. Untested by feel.
- A single frame at the wall is unavoidable: macOS clamps the pointer before
  handing over the event. Reduced from 150-350ms to one event; cannot reach zero
  with an event-tap approach.
