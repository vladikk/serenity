#!/bin/bash
# Builds Serenity.app (menu bar app, universal binary) with the sounds bundled in Resources.
#
# Signs ad-hoc by default. Set SIGN_IDENTITY (e.g. "Developer ID Application") to sign for
# distribution with the hardened runtime and a secure timestamp; scripts/release.sh does this.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f Sounds/credits.json ]; then
    echo "Sounds/ is missing. Build the sound loops first: python3 tools/build_sounds.py" >&2
    exit 1
fi

VERSION="${VERSION:-$(cat VERSION)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Serenity"

APP="build/Serenity.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Serenity"
cp -R Sounds "$APP/Contents/Resources/Sounds"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Serenity</string>
    <key>CFBundleDisplayName</key><string>Serenity</string>
    <key>CFBundleIdentifier</key><string>com.vladikk.Serenity</string>
    <key>CFBundleExecutable</key><string>Serenity</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.lifestyle</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Vlad Khononov. Sounds: see Settings → Credits.</string>
</dict>
</plist>
PLIST

if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
echo "Built $APP ($VERSION)"
