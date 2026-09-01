# App icon

`AppIcon.icns` is the bundle icon `build.sh` copies into
`CursorWrap.app/Contents/Resources`. CursorWrap is an `LSUIElement` agent, so
this is not a Dock icon - it is what shows up in `/Applications`, in Login
Items, and in the System Settings > Privacy & Security > Accessibility row
people have to recognise before granting the grant the app cannot work without.

Do not hand-edit the `.icns`. Edit `icon.html` and repack:

```sh
./icon/make.sh
```

That renders the page headless at 1024x1024 on a transparent background, sips
it down through every size `iconutil` asks for, and writes `AppIcon.icns`.
Commit the result: a Homebrew install runs `build.sh` with a compiler and no
browser, so the packed icon has to already be in the tarball.

The artwork is the social card's motif at icon scale (see `../.social/`): the
pointer leaves through the right edge, runs under the desktop, and arrives back
on the left. Everything is clipped to the 824x824 rounded square inside the
1024 canvas, which is Apple's grid - the trail can run off the edge without
staining the corners the system rounds away.
