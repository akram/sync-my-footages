#!/bin/bash
set -e

APP_NAME="Sync My Footages"
BUNDLE_ID="com.akram.sync-my-footages"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app"
DMG_NAME="Sync-My-Footages-${VERSION}.dmg"

echo "=== Building release ==="
swift build -c release

echo "=== Creating app bundle ==="
rm -rf "dist"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy executable
cp "${BUILD_DIR}/SyncMyFootages" "${APP_DIR}/Contents/MacOS/"

# Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>SyncMyFootages</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Sync My Footages needs to refresh Finder after syncing files.</string>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# Ad-hoc code sign
echo "=== Code signing ==="
codesign --force --deep --sign - "${APP_DIR}"

echo "=== Creating DMG ==="
# Create a temporary DMG folder
DMG_DIR="dist/dmg"
mkdir -p "${DMG_DIR}"
cp -R "${APP_DIR}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "dist/${DMG_NAME}"

rm -rf "${DMG_DIR}"

echo ""
echo "=== Done ==="
echo "App bundle: ${APP_DIR}"
echo "DMG:        dist/${DMG_NAME}"
echo "Size:       $(du -sh "${APP_DIR}" | cut -f1)"
