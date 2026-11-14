#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_path="${1:-$PWD/.build/Lid Less.app}"
framework_source="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks"
cp "$binary_dir/LidLess" "$app_path/Contents/MacOS/LidLess"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns LICENSE "$app_path/Contents/Resources/"
install -m 644 .build/checkouts/Sparkle/LICENSE "$app_path/Contents/Resources/Sparkle-LICENSE"
# Preserve the framework's symlinks and executable permissions.
ditto "$framework_source" "$app_path/Contents/Frameworks/Sparkle.framework"

# All embedded executables must use the same identity, including for ad-hoc
# builds. Keeping Sparkle's vendor signatures breaks its XPC identity checks.
identity="${LID_LESS_SIGNING_IDENTITY:--}"
signing_options=(--force --sign "$identity")
if [[ "$identity" != "-" ]]; then signing_options+=(--options runtime --timestamp); fi
framework="$app_path/Contents/Frameworks/Sparkle.framework"
for nested in "$framework"/Versions/B/XPCServices/*.xpc "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app"; do
    codesign "${signing_options[@]}" "$nested"
done
codesign "${signing_options[@]}" "$framework"
codesign "${signing_options[@]}" "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'Built %s\n' "$app_path"
