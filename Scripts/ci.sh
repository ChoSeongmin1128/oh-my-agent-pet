#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omapet-ci.XXXXXX")"

cleanup() {
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM HUP

cd "$ROOT_DIR"

swift format lint --strict --recursive Package.swift Sources Tests
swift test --parallel
swift build --product OhMyAgentPet
swift build --product omapet

BIN_DIR="$(swift build --show-bin-path)"
"$BIN_DIR/omapet" version --json | python3 -c '
import json, sys
value = json.load(sys.stdin)
assert value == {"name": "Oh My Agent Pet", "version": "0.0.0-dev"}
'

OUTPUT_ROOT="$TEMP_ROOT" "$ROOT_DIR/Scripts/build-app.sh" debug >/dev/null
APP_DIR="$TEMP_ROOT/Oh My Agent Pet.app"

test -x "$APP_DIR/Contents/MacOS/OhMyAgentPet"
test -x "$APP_DIR/Contents/MacOS/omapet"
test -f "$APP_DIR/Contents/Resources/LICENSE"
test -f "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")" = "com.seongmin.OhMyAgentPet"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_DIR/Contents/Info.plist")" = "14.0"
