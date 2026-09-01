---
id: ADR-0001
title: Adopt the Agent Docs Standard
status: accepted
date: 2026-09-01
supersedes: -
superseded-by: -
---

# ADR-0001: Adopt the Agent Docs Standard

## Context

cursorwrap is small - one 325-line `main.swift` - but the knowledge around it
is not. Most of what a contributor or an agent needs to avoid breaking things
is invariant rather than code: the version lives in exactly one place, four
plausible approaches to edge detection have already been tried and failed, the
two committed binaries are generated and must never be hand-edited, and the
formula template has a two-placeholder contract with the release workflow.

That knowledge was spread across `README.md`, `CONTRIBUTING.md`,
`icon/README.md` and `.social/README.md`, all written for humans arriving at
the top of the repo. An agent editing `packaging/homebrew/cursorwrap.rb.tmpl`
has no reason to read the root README first, and nothing sitting next to the
file tells it that `release.yml` substitutes exactly two placeholders.

The Agent Docs Standard answers this with `AGENTS.md` context files placed at
each node, linked by `up` / `ref` / `dep` pointers, plus a `docs/` taxonomy
that separates durable records from feature-scoped ones.

## Decision

We will adopt ADS with `topology: monorepo`: a `project-index` at the repo
root, `module` nodes at `icon/` and `packaging/`, `CLAUDE.md` symlinked to
`AGENTS.md` at each node, and a `docs/` tree holding `adr/` and `decisions/`.

Human-facing prose stays where it is. `AGENTS.md` carries only what cannot be
derived from the tree - commands, invariants, and pointers - and links to the
READMEs rather than restating them.

## Consequences

- **Positive:** the invariant that governs a file now sits in its own
  directory. Cross-boundary upstreams (the Homebrew tap, Quartz Event Services,
  the Apple icon grid) are declared rather than implied. `ads-lint` can check
  the result mechanically.
- **Negative / cost:** two more files to keep current, and a second place where
  build commands appear. Drift between `AGENTS.md` and the READMEs is now
  possible and nothing detects it.
- **Follow-ups:** `.social/` and `.github/` cannot be nodes because `ads-lint`
  skips dot-directories, so the artwork invariant for `.social/` lives in the
  root context file instead. Wiring `ads-lint` into `.github/workflows/ci.yml`
  is worthwhile but not done here.

## Alternatives considered

- **Leave the READMEs as the only context.** They are good, and this is a small
  repo. Rejected because they are organised for a human reading top-down, and
  give an agent editing a leaf directory nothing local to go on.
- **A single root `AGENTS.md`, no modules.** Simpler and enough for L2.
  Rejected because the two invariants most likely to be broken by an
  unsuspecting edit - hand-editing `AppIcon.icns`, adding a third placeholder
  to the formula template - belong next to the files they govern.
- **Duplicate the README content into `AGENTS.md`.** Rejected: two copies of
  the same prose drift, and ADS explicitly asks for the non-derivable subset.
