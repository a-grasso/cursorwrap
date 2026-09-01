# Social preview

`social-preview.png` is GitHub's social preview card (Settings -> General ->
Social preview), which also becomes the `og:image` LinkedIn and friends show.

Do not hand-edit the PNG. Edit `card.html` and re-render:

```sh
"/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1280,640 --screenshot=card@2x.png .social/card.html
sips -Z 1280 card@2x.png --out .social/social-preview.png
```

Any Chromium will do. The 2x render then downsample is what keeps the text
crisp at GitHub's recommended 1280x640.

Font note: the install line is Monaco deliberately. Menlo and SF Mono both draw
a hyphen wide enough to read as an en dash, which matters on a line people
retype.
