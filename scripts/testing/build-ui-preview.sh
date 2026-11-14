#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
preview="$PWD/.build/ui-preview/LidLessPreview.app"
mkdir -p "$preview/Contents/MacOS" "$preview/Contents/Resources"
swiftc -parse-as-library -I "$binary_dir" \
    Sources/LidLess/AppModel.swift Sources/LidLess/PopoverView.swift \
    scripts/testing/UIPreview.swift "$binary_dir/LidLessCore.o" \
    -o "$preview/Contents/MacOS/LidLessPreview"
cp Resources/AppIcon.icns "$preview/Contents/Resources/"
python3 - "$preview" <<'PY'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1]) / 'Contents/Info.plist'
p.write_bytes(plistlib.dumps(dict(CFBundleIdentifier='dev.lid-less.ui-preview', CFBundleName='LidLessPreview',
    CFBundleExecutable='LidLessPreview', CFBundlePackageType='APPL', CFBundleIconFile='AppIcon', CFBundleShortVersionString='0.2.0')))
PY
codesign --force --sign - "$preview"
printf 'Preview (synthetic state only): %s\n' "$preview"
