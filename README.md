# Lid Less

Keep your MacBook working with the lid closed. A tiny native menu bar app with no `sudo`, no privileged helper, and no dependencies.

**[Download the latest release](https://github.com/Koodattu/lid-less/releases/latest)** · macOS 14+ · Apple Silicon

## Get started

1. Download the ZIP from [Releases](https://github.com/Koodattu/lid-less/releases/latest), unzip it, and move **Lid Less.app** to Applications.
2. Open the app and click the laptop icon in the menu bar.
3. Choose **Arm for Next Close**, then close the lid within 60 seconds. On Macs with a readable lid-angle sensor, you can also hold **⌥ Option** while slowly lowering the lid.

Reopen the lid to end the session, or choose **Disarm / Restore Sleep**. Quitting also restores normal lid handling. Sessions stop after eight hours, at 15% battery while unplugged, or at critical temperature. Screen-lock settings stay unchanged.

Enable **Launch at Login** in the menu to start Lid Less automatically when you sign in. It starts disarmed. If the menu shows **Approval Required**, choose **Open Login Settings…** to allow it in macOS. Click the toggle again to turn automatic launching off.

The download is ad-hoc signed, **not Apple-notarized**. If macOS blocks it, see [Apple's instructions for opening an app you trust](https://support.apple.com/en-us/102445), or build from source below.

## Compatibility

Closed-lid operation has been confirmed by the maintainer on one Apple Silicon Mac. This is an early release using an undocumented IOKit control; other hardware and macOS versions still need testing. Option-close requires a readable lid-angle sensor; manual arming does not.

Use on a ventilated surface, not inside a bag. Avoid running alongside other lid-sleep utilities: the override is shared system state. If restoration fails, quit the app and follow the [recovery instructions](docs/technical-notes.md#recovery), or restart your Mac.

## Build from source

Requires Xcode or Swift command-line tools with Swift 5.9+.

```sh
git clone https://github.com/Koodattu/lid-less.git
cd lid-less
bash scripts/build-app.sh
open ".build/Lid Less.app"
```

Run `swift test` for the lifecycle tests. Run `bash scripts/package-release.sh` to create a ZIP and SHA-256 checksum in `dist/` for your Mac's architecture. Release builds are attached to GitHub Releases.

[Implementation, diagnostics, and hardware tests](docs/technical-notes.md) · [Apache 2.0 license](LICENSE)

Inspired by [Clamshell](https://clamshell.dev/). Independently implemented using Apple's IOKit APIs.
