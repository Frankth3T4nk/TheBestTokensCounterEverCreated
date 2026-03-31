#!/bin/bash
# Package Claude Tokens Notifier into a DMG
# Usage: ./package_dmg.sh
# Requires: create-dmg (brew install create-dmg)

set -e

APP_NAME="Claude Tokens Notifier"
BUNDLE_ID="com.frankleurs.ClaudeTokensNotifier"
VERSION="1.0.0"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
DMG_NAME="${APP_NAME// /-}-${VERSION}.dmg"

echo "=== Building $APP_NAME v$VERSION ==="

# Step 1: Archive
echo "→ Archiving..."
xcodebuild archive \
    -project "ClaudeTokensNotifier.xcodeproj" \
    -scheme "ClaudeTokensNotifier" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "platform=macOS" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="-" \
    DEVELOPMENT_TEAM="" \
    | tail -5

# Step 2: Export
echo "→ Exporting..."
mkdir -p "$EXPORT_DIR"

cat > /tmp/ExportOptions.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist /tmp/ExportOptions.plist \
    | tail -5

# Step 3: Create DMG
echo "→ Creating DMG..."
mkdir -p "$DMG_DIR"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 185 \
        --app-drop-link 450 185 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_DIR/$DMG_NAME" \
        "$EXPORT_DIR/$APP_NAME.app"
else
    # Fallback: basic DMG without create-dmg
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$EXPORT_DIR/$APP_NAME.app" \
        -ov \
        -format UDZO \
        "$DMG_DIR/$DMG_NAME"
fi

echo ""
echo "=== Done! ==="
echo "DMG: $DMG_DIR/$DMG_NAME"
