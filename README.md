<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo/tuck-logo-inverse.svg">
    <img src="assets/logo/tuck-logo.svg" alt="Tuck" width="200">
  </picture>
</h1>

To-dos tucked into your MacBook's notch. Rest the pointer on the notch for a moment and a short list slides out: type, press Return, tick things off, move on. Native macOS app (SwiftUI + AppKit, macOS 14+).

Tuck has no window, no Dock icon and no menu bar item. It sits in the notch and stays out of the way until you hover. On Macs without a notch it lives, invisible, at the top center of the screen.

Tuck is open source and free. No accounts, no telemetry, no network calls except the daily update check against GitHub releases.

## Install

Download `Tuck-<version>.zip` from [Releases](https://github.com/techtheoryio/tuck/releases), unzip, and move `Tuck.app` to Applications. Builds are signed and notarized. Tuck opens at login by default. Updates come through [Sparkle](https://sparkle-project.org): Tuck checks the latest GitHub release once a day and installs new versions on its own.

Or build it yourself (needs Xcode 26 / Swift 6):

```bash
git clone https://github.com/techtheoryio/tuck.git && cd tuck
scripts/build-app.sh 0.0.0 && open .build/Tuck.app
```

For development:

```bash
swift run Tuck        # build and launch (no updates or login item outside the .app)
swift test            # to-do list tests
```

## Using it

- Rest the pointer on the notch: it grows a little and a thin bar below it fills up; when it is full the list opens (1.8 s by default, adjustable in Settings).
- Type and press Return to add a to-do. Click one to tick it off. Right-click to delete it.
- **Clear done** removes ticked-off items. Esc or moving the pointer away closes the list (it stays open while you have unsent text).
- Click **Tuck** in the open panel for Settings (hover delay, open at login, updates) and Quit.

## Contributing

Bug fixes and polish are always welcome — just open a PR. For a new feature, open an issue first. Tuck is supposed to stay tiny.

- Keep the diff focused. One change per PR.
- No new dependencies (Sparkle for updates is the only one).
- Logic goes in `Sources/TuckCore` with a test in `Tests/TuckCoreTests`; `swift test` must pass.

## Notes

- `Sources/TuckCore` — the to-do list and its storage, no UI. `Sources/Tuck` — the notch panel (`NotchController`: window, hover and positioning; `NotchView`: SwiftUI).
- To-dos live in `~/Library/Application Support/Tuck/todos.json`, saved on every change. A file that can't be read is moved to `todos.json.broken` rather than overwritten.
- Debug: `TUCK_OPEN=1 swift run Tuck` starts with the list open and keeps it open. Add `TUCK_SNAPSHOT=out.png` to write a PNG of the panel and quit.
- App icon: put it at `Sources/Tuck/Resources/AppIcon.icns`; `scripts/build-app.sh` picks it up.
- Releasing: push a `v1.2.0`-style tag; `.github/workflows/release.yaml` runs the tests, builds a universal `.app` with `scripts/build-app.sh`, signs and notarizes it, and attaches the zip to a GitHub release. It also signs the zip with Sparkle's EdDSA key and attaches an `appcast.xml`; the app's feed URL is `releases/latest/download/appcast.xml`. Secrets: `DEVELOPER_ID_P12` (base64 `.p12`), `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY` (base64 App Store Connect `.p8`), `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `SPARKLE_ED_KEY` (`.build/artifacts/sparkle/Sparkle/bin/generate_keys --account tuck -x key.txt`; the public key is in `scripts/build-app.sh`).

## License

[MIT](LICENSE).
