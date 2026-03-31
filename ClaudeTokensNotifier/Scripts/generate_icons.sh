#!/bin/bash
# Generate app icons from AppIcon.png source
# Usage: ./generate_icons.sh [source_icon.png]
# Requires: sips (built into macOS)

set -e

SOURCE="${1:-AppIcon.png}"
ICONSET_DIR="ClaudeTokensNotifier/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE" ]; then
    echo "Error: Source icon '$SOURCE' not found."
    echo "Please place a 1024x1024 PNG named AppIcon.png in the project root."
    exit 1
fi

echo "Generating icons from: $SOURCE"

generate_icon() {
    local size=$1
    local output="$ICONSET_DIR/AppIcon-${size}.png"
    sips -z $size $size "$SOURCE" --out "$output" >/dev/null 2>&1
    echo "  ✓ ${size}x${size} → $output"
}

generate_icon 16
generate_icon 32
generate_icon 64
generate_icon 128
generate_icon 256
generate_icon 512
generate_icon 1024

# Generate menu bar icons
MENUBAR_DIR="ClaudeTokensNotifier/Assets.xcassets/MenuBarIcon.imageset"
sips -z 18 18 "$SOURCE" --out "$MENUBAR_DIR/MenuBarIcon.png" >/dev/null 2>&1
sips -z 36 36 "$SOURCE" --out "$MENUBAR_DIR/MenuBarIcon@2x.png" >/dev/null 2>&1
echo "  ✓ Menu bar icons generated"

echo ""
echo "All icons generated successfully!"
