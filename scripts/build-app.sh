#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_path="${1:-$PWD/.build/Lid Less.app}"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/LidLess" "$app_path/Contents/MacOS/LidLess"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'Built %s\n' "$app_path"
