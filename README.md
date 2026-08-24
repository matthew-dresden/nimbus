# Nimbus

The Lightshot experience, reborn for modern macOS. Native Swift. Apple Silicon.
Open source. No Electron, no Rosetta, no accounts.

Lightshot was pulled from the Mac App Store and its Intel-only binary breaks
on Apple Silicon Macs. Nimbus restores that workflow natively: press a hotkey,
drag a region, annotate, and save or share - all in under two seconds.

Upstream origin: [wpraiz/nimbus](https://github.com/wpraiz/nimbus) (MIT),
continued here with fixes and packaging.

## Features

| | Feature | Details |
| --- | --- | --- |
| 📸 | Region capture | Dimmed overlay, crosshair, live size badge, corner handles |
| ✏️ | Annotation tools | Arrow, rectangle, ellipse, line, pencil, marker + color picker |
| 💾 | Save | Auto-named PNGs into a configurable folder |
| 📋 | Copy | One click to clipboard |
| ⬆️ | Upload | Anonymous Imgur upload, link auto-copied to clipboard |
| ⌨️ | Global hotkey | Cmd+4 by default, works from any app |
| 🍎 | Native Apple Silicon | AppKit, zero Electron, universal-ready |

## Install

Download the latest prerelease zip from
[Releases](https://github.com/matthew-dresden/nimbus/releases), unzip, drag
`Nimbus.app` into `/Applications`, and launch it. A camera icon appears in the
menu bar; press **Cmd+4** anywhere to capture.

Ad-hoc signed build: if Gatekeeper complains on first launch, right-click the
app and choose **Open**.

### Upload setup

Uploads use Imgur's anonymous API. Register a free client ID at
[api.imgur.com](https://api.imgur.com/oauth2/addclient) (select "OAuth 2
authorization without a callback URL"), then paste it into Nimbus Preferences.

## Build from source

Requires Xcode 15+ and macOS 13+:

```bash
git clone git@github.com:matthew-dresden/nimbus.git && cd nimbus
swift build
scripts/build-app.sh          # -> dist/Nimbus.app + release zip
```

Run tests:

```bash
xcode-select -s /Applications/Xcode.app/Contents/Developer   # once, needs sudo
swift test
```

## CI/CD

- **CI**: every push/PR builds release, runs tests, and packages the app as an
  artifact
- **Release**: pushing a `v*` tag runs tests, packages, and publishes a GitHub
  prerelease automatically

## Privacy

No account. Nothing phones home except screenshots YOU explicitly upload to
Imgur. Unlike prnt.sc/Lightshot, uploads are not guessable short URLs exposed
to scrapers - Imgur anonymous links are unlisted.

## Credits

- Original concept: [Skillbrains Lightshot](https://app.prntscr.com)
- Upstream implementation: [wpraiz/nimbus](https://github.com/wpraiz/nimbus) (MIT)
- This fork: fixes, packaging, CI/CD, distribution

## License

MIT - see [LICENSE](LICENSE).
