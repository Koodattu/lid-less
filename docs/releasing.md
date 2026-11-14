# Release and update operations

Lid Less uses Sparkle 2.10.1, pinned through SwiftPM. GitHub Releases hosts the ZIP and `appcast.xml`. The feed URL is `https://github.com/Koodattu/lid-less/releases/latest/download/appcast.xml`, so publishing a release as **Latest** switches the feed and binary together. Version ordering uses the increasing `CFBundleVersion`, not a Git commit SHA.

## Keys and signing

The dedicated Ed25519 key is stored in the maintainer's login Keychain under Sparkle account `dev.lid-less.app`. Only its public key is in `Resources/Info.plist`. Never commit/export the private key into the repository. Back it up through a secure process before replacing the signing Mac or its Keychain; losing it would prevent updates to existing ad-hoc-signed installations.

For a new checkout on the same signing Mac, run `swift package resolve` to obtain Sparkle's tools. Check the public key with:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.lid-less.app -p
```

It must match `SUPublicEDKey` in the plist. Do not generate a replacement key for an existing release line.

Both the feed and ZIP are signed. `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are enabled. The SHA-256 file is also published for manual verification; Sparkle relies on Ed25519 for authenticity and integrity. Do not change a signed feed, embedded release notes, or archive after signing.

Apple Developer ID signing/notarization is a separate step. Without an available identity, builds are ad-hoc signed. If a Developer ID identity is configured, pass `LID_LESS_SIGNING_IDENTITY` to the build/package scripts, then notarize and staple the app **before** creating and signing the final archive. Do not label an ad-hoc build notarized. All nested Sparkle executables must be signed consistently with the app; mixing vendor-signed helpers with an ad-hoc host can break IPC identity checks.

## Publish

1. Bump `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist`.
2. Add concise HTML release notes at `docs/releases/<version>.html`.
3. Run `swift test`, the native UI review, and the isolated updater tests below. Complete relevant hardware tests from [technical notes](technical-notes.md#verification).
4. On Apple Silicon, run:

```sh
bash scripts/package-release.sh
bash scripts/sign-release.sh
```

5. Verify the ZIP, deep code signature, SHA-256, and feed signature. `sign-release.sh` stages only the current archive and creates `dist/appcast.xml`; it does not publish anything.
6. Commit the source, tag that commit, and push. Create the GitHub release with the versioned ZIP, its `.sha256`, and `appcast.xml` attached, then publish it as **Latest**. Never change an already published archive in place.
7. Verify the public Latest feed and assets match the files just signed. Older v0.1.x apps need one manual upgrade because they have no updater.

The app asks before installation. Automatic checking is opt-in, and the app does not send a system profile. Checks and available-update notices do not block arming. Starting a download or installation requires an idle session and blocks new arming until the update finishes or cancellation completes. Cancel Arming, End Session, and Retry Restore Sleep remain available. The custom Sparkle user driver renders progress and errors in the popover and immediately acknowledges errors, so a hidden dialog cannot keep controls locked. Normal termination still restores sleep before allowing the process to exit.

## Tests without power changes

`swift test` covers the session policy, preference persistence, countdown presentation, and the update/session gate. It never calls the actual power backend.

The UI preview uses the real SwiftUI views with simulated battery/session values. It doesn't run IOKit, the login service, or Sparkle:

```sh
bash scripts/testing/build-ui-preview.sh
open ".build/ui-preview/LidLessPreview.app"
```

Its main button toggles idle and armed for layout inspection. Pass `--update-ready` to preview the restart controls. Real application actions retain their normal behavior. Review light/dark appearance, focus, controls, scrolling, and accessible labels.

The integration fixture proves that ad-hoc-signed apps can be replaced and relaunched through this Sparkle distribution. It uses a unique bundle identifier, disposable copies under `.build`, a loopback HTTP server, and the signing account in Keychain. It never replaces `/Applications/Lid Less.app`. The local HTTP exception exists only in the fixture; production uses HTTPS.

```sh
bash scripts/build-app.sh "$PWD/.build/preview/Lid Less.app"
swiftc -parse-as-library scripts/testing/UpdateFixture.swift \
  Sources/LidLess/AppModel.swift Sources/LidLess/UpdateController.swift \
  -I "$(swift build -c release --show-bin-path)" \
  "$(swift build -c release --show-bin-path)/LidLessCore.o" \
  -F '.build/preview/Lid Less.app/Contents/Frameworks' -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o .build/update-fixture
python3 scripts/testing/test-update.py
python3 scripts/testing/test-update.py bad-feed
python3 scripts/testing/test-update.py bad-archive
python3 scripts/testing/test-update.py cancel-check
python3 scripts/testing/test-update.py cancel-ready
```

The success case checks that version 2 replaces version 1 and actually relaunches. The tamper cases require a Sparkle error and verify the original version remains installed. Logs and fixtures remain in the printed `.build/update-test.*` directory for diagnosis. Real hardware lid-close behavior and Apple notarization are outside these tests.
