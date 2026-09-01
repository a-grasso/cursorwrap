---
kind: module
title: cursorwrap icon
up: ../AGENTS.md
dep:
  - { id: apple-icon-hig, at: https://developer.apple.com/design/human-interface-guidelines/app-icons, kind: external-doc, hint: "the 824x824-inside-1024 grid icon.html clips its artwork to" }
updated: 2026-09-01
---

# cursorwrap icon

## Purpose

The bundle icon. `icon.html` is the source of the artwork; `AppIcon.icns` is
the packed output that `build.sh` copies into
`CursorWrap.app/Contents/Resources`.

## Working here

- **Rebuild:** `./icon/make.sh` - renders `icon.html` headless at 1024x1024 on
  a transparent background, sips it down through every size `iconutil` asks
  for, and writes `AppIcon.icns`.
- **Entry point:** `icon.html`. `README.md` carries the artwork rationale.

## Constraints

- Never hand-edit `AppIcon.icns`. Edit `icon.html` and repack.
- Commit the rebuilt `.icns`. A Homebrew install runs `build.sh` with a
  compiler and no browser, so the packed icon has to already be in the tarball,
  and `build.sh` fails outright without it.
- CursorWrap is `LSUIElement`, so this is not a Dock icon. It is the row people
  have to recognise in System Settings > Privacy & Security > Accessibility
  before granting the permission the app cannot work without, which is what
  legibility at small sizes is for.
- The artwork is the social card's motif at icon scale (`../.social/card.html`).
  The two are meant to read as the same mark; do not let them drift.
