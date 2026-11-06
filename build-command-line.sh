#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'This project must be built on macOS.' >&2
    exit 1
fi
xcrun --find swift >/dev/null
swift package resolve
# These are design-time Xcode previews, not needed for the standalone app.
preview_file=".build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift"
chmod u+w "$preview_file"
python3 - "$preview_file" <<'PYCODE'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = re.sub(r"#Preview \{\n[^}]*\n\}\n", "", s)
p.write_text(s)
PYCODE
swift build -c release --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
binary_dir="$(swift build -c release --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk --show-bin-path)"
app="$PWD/build/Framelet.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Framelet" "$app/Contents/MacOS/Framelet"
cp "Framelet/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "Framelet/PrivacyInfo.xcprivacy" "$app/Contents/Resources/PrivacyInfo.xcprivacy"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Framelet</string>
<key>CFBundleIdentifier</key><string>app.framelet.recorder</string>
<key>CFBundleName</key><string>Framelet</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDisplayName</key><string>Framelet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Framelet records your microphone alongside the selected window.</string>
<key>NSAudioCaptureUsageDescription</key><string>Framelet records system audio alongside the selected window.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
bundle_path="$(find .build -type d -name 'KeyboardShortcuts_KeyboardShortcuts.bundle' -print -quit)"
if [[ -z "$bundle_path" ]]; then
    echo 'KeyboardShortcuts resource bundle not found.' >&2
    exit 1
fi
ditto "$bundle_path" "$app/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle"
ditto "$bundle_path" "$app/KeyboardShortcuts_KeyboardShortcuts.bundle"
codesign --force --sign - --entitlements Framelet/Framelet.entitlements "$app"
# Apply the same custom Finder icon as dragging AppIcon.icns onto Get Info.
if ! xcrun swift tools/apply-finder-icon.swift "$app" "$app/Contents/Resources/AppIcon.icns"; then
    echo 'Warning: could not apply the custom Finder icon; the bundled icon is still available.' >&2
elif [[ -e "$app/"$'Icon\r' ]]; then
    echo 'Finder custom icon file is present.'
else
    echo 'Finder custom icon was accepted but its marker was not found; the app will retry at launch.' >&2
fi
if ! codesign --verify --deep --strict "$app"; then
    echo 'Warning: macOS did not validate the app signature after setting its Finder icon.' >&2
fi
echo "Built: $app"
echo "Launch with: open \"$app\""
