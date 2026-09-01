---
kind: project-index
title: cursorwrap
topology: monorepo
ref:
  - { at: icon/AGENTS.md, hint: "the app icon - HTML source rendered and packed into AppIcon.icns" }
  - { at: packaging/AGENTS.md, hint: "the Homebrew formula template the release workflow renders into the tap" }
dep:
  - { id: quartz-event-services, at: https://developer.apple.com/documentation/coregraphics/quartz_event_services, kind: external-doc, hint: "CGEventTap and CGEvent deltas - the API whose edge clamping the whole design works around" }
docs: ./docs
updated: 2026-09-01
---

# cursorwrap

## Purpose

A macOS `LSUIElement` agent that wraps the mouse pointer around the outer edges
of a multi-display desktop: push past the rightmost edge, arrive at the
leftmost one. The whole program is `main.swift`; there is no package manifest
and no framework beyond Cocoa.

## Working here

- **Build:** `./build.sh` - compiles `main.swift` into `CursorWrap.app` and
  signs it ad-hoc.
- **Run the bundle:** `open -a "$PWD/CursorWrap.app"`. Never launch the inner
  binary as the app; macOS attributes the Accessibility grant to the bundle.
- **Dev loop:** `./CursorWrap.app/Contents/MacOS/cursorwrap --verbose --dry-run`.
  In the foreground the grant belongs to your terminal, which is the only
  comfortable way to work on the detection logic.
- **Test:** there is no test suite. `.github/workflows/ci.yml` is the gate on
  every push to `main` and every PR: the bundle builds, `main.swift` /
  `--version` / `Info.plist` agree on the version, the bundle is signed,
  `--help` and `--displays` exit clean, an unknown flag fails, and the formula
  template still renders to valid Ruby.
- **Release:** bump `version` in `main.swift`, commit, then
  `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`.
- **Conventions:** release notes are generated from commits, so write commit
  subjects that read well in a changelog. Longer guidance is in
  [CONTRIBUTING.md](CONTRIBUTING.md).

## Constraints

- `let version` in `main.swift` is the single source of truth. `build.sh` reads
  it into `Info.plist` and `release.yml` refuses a tag that disagrees with it.
  Never write the version anywhere else.
- Wrapping is driven by the mouse delta on the event macOS clamps to the screen
  edge. Accumulating push after the pointer is clamped, rewriting
  `event.location` in the tap, using a dwell timer, and carrying momentum onto
  the far display have all been tried and none of them work. Read "How it
  works" in the [README](README.md) before changing the detection.
- Every build is signed ad-hoc, so each rebuild produces a new cdhash and
  invalidates the Accessibility grant. Recover with
  `tccutil reset Accessibility dev.agrasso.cursorwrap`, then re-approve.
- The two committed binaries, `icon/AppIcon.icns` and
  `.social/social-preview.png`, are rendered from HTML pages in the repo. Never
  hand-edit either one, and commit the rebuilt output: a Homebrew install
  compiles from the release tarball with no browser available.
- Documentation layout follows the Agent Docs Standard - see
  [ADR-0001](docs/adr/0001-adopt-agent-docs-standard.md).
