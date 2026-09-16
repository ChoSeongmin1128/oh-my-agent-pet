#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/build}"

case "$CONFIGURATION" in
    debug|release) ;;
    *)
        echo "configuration must be debug or release" >&2
        exit 64
        ;;
esac

swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --product OhMyAgentPet
swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --product omapet
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --show-bin-path)"

APP_DIR="$OUTPUT_ROOT/Oh My Agent Pet.app"
CONTENTS_DIR="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

cp "$BIN_DIR/OhMyAgentPet" "$CONTENTS_DIR/MacOS/OhMyAgentPet"
cp "$BIN_DIR/omapet" "$CONTENTS_DIR/MacOS/omapet"
cp "$ROOT_DIR/LICENSE" "$CONTENTS_DIR/Resources/LICENSE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$CONTENTS_DIR/Resources/THIRD_PARTY_NOTICES.md"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Oh My Agent Pet</string>
    <key>CFBundleExecutable</key>
    <string>OhMyAgentPet</string>
    <key>CFBundleIdentifier</key>
    <string>com.seongmin.OhMyAgentPet</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Oh My Agent Pet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
echo "$APP_DIR"
