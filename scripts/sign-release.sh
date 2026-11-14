#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Run after package-release.sh. The private key never leaves the login Keychain.
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
archive="$PWD/dist/Lid-Less-${version}-macos-arm64.zip"
if [[ ! -f "$archive" ]]; then printf 'Build the arm64 release archive first.\n' >&2; exit 1; fi
staging="$(mktemp -d "$PWD/.build/appcast.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
cp "$archive" "$staging/"
if [[ -f "docs/releases/$version.html" ]]; then
    cp "docs/releases/$version.html" "$staging/$(basename "$archive" .zip).html"
fi
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --account dev.lid-less.app --maximum-deltas 0 \
    --download-url-prefix "https://github.com/Koodattu/lid-less/releases/download/v$version/" \
    --link https://github.com/Koodattu/lid-less \
    "$staging"
cp "$staging/appcast.xml" dist/appcast.xml
printf 'Signed feed: %s/dist/appcast.xml\n' "$PWD"
