# Mosaico

Hide the sensitive parts of a photo in seconds. Pick a picture, drag boxes over what you want covered, and Mosaico pixelates those areas instantly — then saves the result as a **new** photo, leaving your original untouched.

## Features

- **Draw to mosaic** — drag a rectangle and the mosaic applies the moment you lift your finger
- **Smart text detection** — one tap finds all text in the photo (on-device Vision, no network); tap the highlighted regions you want masked
- **Live, editable boxes** — every box stays on screen: move it, resize it by its corner handles, or delete it with the × badge; the mosaic re-renders live while you drag
- **Pinch to zoom** — zoom up to 8× for precise masking; the same two-finger gesture pans, and boxes never leave the photo
- **Two styles** — Polygon (crystallize, the default) or Square (pixelate), with an adjustable tile-size slider
- **Undo / redo** — every edit is reversible, including the discard-all button
- **Non-destructive** — edits render from the original at full resolution; saving adds a new photo and never modifies the original
- **Private by design** — no photo-library read permission needed (the system picker shares only the photo you choose), add-only permission to save, no network access at all

## Requirements

- iOS 17+ (iPhone)
- Xcode with the iOS platform installed
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [just](https://github.com/casey/just) (`brew install xcodegen just`)
- [uv](https://github.com/astral-sh/uv) (only for regenerating the app icon)

## Development

The Xcode project is generated — edit `project.yml`, not the `.xcodeproj`.

```sh
just run          # build + launch on the iOS simulator
just run-device   # build + install on a connected iPhone
just icon         # regenerate the app icon (scripts/make_icon.py)
just clean        # remove build products and the generated project
```

### Running on your iPhone

One-time setup: add your (free) Apple ID in Xcode → Settings → Accounts, put your Team ID in `DEVELOPMENT_TEAM` in `project.yml`, enable Developer Mode on the phone, then `just run-device`. With free-tier signing the app's signature expires after 7 days — just run it again to refresh.
