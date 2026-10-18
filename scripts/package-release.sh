#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build dist
staging_dir="$(mktemp -d "$PWD/.build/package.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

# Build a separate bundle so packaging does not overwrite the running app.
bash scripts/build-app.sh "$staging_dir/Lid Less.app"
cp LICENSE "$staging_dir/LICENSE"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
architecture="$(lipo -archs "$staging_dir/Lid Less.app/Contents/MacOS/LidLess" | tr ' ' '-')"
archive_name="Lid-Less-${version}-macos-${architecture}.zip"
archive_path="$PWD/dist/$archive_name"
ditto -c -k --keepParent "$staging_dir/Lid Less.app" "$archive_path"
# Include the project license alongside the app.
(cd "$staging_dir" && zip -q "$archive_path" LICENSE)
(cd dist && shasum -a 256 "$archive_name" > "$archive_name.sha256")
printf 'Packaged %s/dist/%s\n' "$PWD" "$archive_name"
