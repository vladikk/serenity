#!/bin/bash
# Builds Serenity.app (menu bar app) with the sounds bundled in Resources.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f Sounds/credits.json ]; then
    echo "Sounds/ is missing. Build the sound loops first: python3 tools/build_sounds.py" >&2
    exit 1
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Serenity"

APP="build/Serenity.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Serenity"
cp -R Sounds "$APP/Contents/Resources/Sounds"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Serenity</string>
    <key>CFBundleDisplayName</key><string>Serenity</string>
    <key>CFBundleIdentifier</key><string>local.serenity.app</string>
    <key>CFBundleExecutable</key><string>Serenity</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"
echo "Install with: cp -R $APP /Applications/"
