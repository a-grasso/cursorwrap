# Contributing

Small tool. Issues and pull requests both welcome.

## Build and run

```sh
./build.sh                          # compiles main.swift into CursorWrap.app
open -a "$PWD/CursorWrap.app"       # launch the bundle, not the inner binary
```

`build.sh` keeps `Info.plist` in step with the `version` constant in
`main.swift`, so change the version in one place only.

For anything you can observe from a terminal, run the binary in the foreground
instead - the Accessibility grant then belongs to your terminal, which is far
less painful than re-approving a bundle:

```sh
./CursorWrap.app/Contents/MacOS/cursorwrap --verbose --dry-run
```

`--dry-run` logs crossings without moving the pointer, which is the only
comfortable way to work on the detection logic.

### The Accessibility grant will fight you

The bundle is signed ad-hoc, so it has no stable designated requirement: every
rebuild produces a new cdhash and reads to macOS as a different app, which
invalidates the grant. While iterating:

```sh
tccutil reset Accessibility dev.agrasso.cursorwrap
```

then re-approve. So `--dry-run` in a terminal is the preferred loop.

## What CI enforces

`.github/workflows/ci.yml` runs on every push to `main` and every pull request:

- the app bundle builds
- the geometry tests pass (`./tests/run.sh`)
- `main.swift`, the binary's `--version`, and `Info.plist` agree on the version
- the bundle is signed
- `--help` and `--displays` exit clean, and an unknown flag fails
- the Homebrew formula template still parses as Ruby once rendered

`--displays` is checked because CI runners have no displays - the flag has to
exit cleanly on an empty display list rather than trap.

## Testing the geometry

`./tests/run.sh` rebuilds `main.swift` with `-DCURSORWRAP_TESTS`, which swaps the
event tap for [tests/spans.swift](tests/spans.swift) as the entry point, and
drives the real `span()` and `crossing()` over synthetic arrangements. It needs
no display, no pointer and no Accessibility grant, which is why it is the one
part of the behaviour that runs on a CI box.

The arrangements are the point: side by side in both orders, stacked, and two
displays joined only through a third. A wrap that is correct on your own desk
can still be wrong on the mirror image of it, so **add the arrangement before
you change the geometry**. The tests deliberately model macOS's clamping
themselves, one pixel at a time, rather than asking `span()` where the wall is -
otherwise a bug in `span()` would hide behind the test's own idea of the answer.

To see how a real desk is being read, run `--displays`: it prints, per display,
which span each band of the other axis wraps within.

## Changing behaviour

Wrapping is driven by mouse deltas on the event that macOS clamps to the screen
edge. The reasoning, and four approaches that do not work, are in the README's
"How it works". Read it before reaching for an accumulator or a timer - those
are among the four.

If you change a default (`--min-overshoot` especially), say in the pull request
what you tested it against. The tension is always the same: crossing must be
easy enough to feel effortless, without making it impossible to park the pointer
on something that lives at the screen edge - a scrollbar, a window close button,
or a window being dragged to the edge.

## Artwork

Both images in the repository are HTML rendered headless by a Chromium, so the
source of each is a page you can open in a browser and edit:

| Source | Output | Rebuild with |
| --- | --- | --- |
| `icon/icon.html` | `icon/AppIcon.icns`, the bundle icon | `./icon/make.sh` |
| `.social/card.html` | `.social/social-preview.png` | see `.social/README.md` |

Never hand-edit the `.icns` or the `.png`. Commit the rebuilt output alongside
the page: a Homebrew install compiles from the release tarball and has no
browser to render either one.

## Cutting a release

Maintainers only. Bump `version` in `main.swift`, commit, then:

```sh
git tag -a v0.1.1 -m v0.1.1 && git push origin v0.1.1
```

`.github/workflows/release.yml` refuses a tag that disagrees with `version`,
creates the GitHub release, and commits the rendered formula to
`a-grasso/homebrew-tap`. Release notes are generated from commits, so write
commit subjects that read well in a changelog.

## Known open problems

Listed under "Limitations" in the README, chiefly:

- Apps that capture the pointer (games, VMs, screen sharing) are not excluded.
- A real signing identity would stop rebuilds invalidating the Accessibility
  grant, for developers and for `brew upgrade` alike.
