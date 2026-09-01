---
kind: module
title: cursorwrap packaging
up: ../AGENTS.md
dep:
  - { id: homebrew-tap, at: https://github.com/a-grasso/homebrew-tap, kind: repo, hint: "release.yml renders the formula template into Formula/cursorwrap.rb in this tap" }
updated: 2026-09-01
---

# cursorwrap packaging

## Purpose

Distribution. `homebrew/cursorwrap.rb.tmpl` is the Homebrew formula, held here
as a template and rendered into the tap at release time.

## Working here

- **Check a change:** `sed -e 's/@@VERSION@@/0.0.0/' -e 's/@@SHA256@@/0/'
  homebrew/cursorwrap.rb.tmpl | ruby -c` - the same thing CI does.
- **Publish:** never by hand. `.github/workflows/release.yml` substitutes the
  placeholders and commits to the tap when a `v*` tag is pushed.

## Constraints

- `@@VERSION@@` and `@@SHA256@@` are the only placeholders, and `release.yml`
  substitutes exactly those two with `sed`. Introducing a third means editing
  the workflow in the same change.
- The formula builds from source rather than shipping a cask. A downloaded
  ad-hoc signed bundle arrives quarantined and Gatekeeper-blocked; compiling on
  the user's machine avoids that and needs only the command line tools Homebrew
  already requires. Do not convert this to a binary artifact without a real
  signing identity.
- The rendered formula must parse as Ruby. CI checks it on every PR, long
  before any tag exists.
- Publishing needs the `HOMEBREW_TAP_TOKEN` repo secret - a PAT with
  `contents:write` on the tap. The publish step skips rather than fails when it
  is absent, so a fork still gets its GitHub release.
