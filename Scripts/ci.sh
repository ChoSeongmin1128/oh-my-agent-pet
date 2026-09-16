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

CLI_HOME="$TEMP_ROOT/home"
CLAUDE_ROOT="$TEMP_ROOT/Claude Config"
mkdir -p "$CLAUDE_ROOT"
printf '%s\n' '{"theme":"dark"}' > "$CLAUDE_ROOT/settings.json"
HOME="$CLI_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_ROOT" \
    "$BIN_DIR/omapet" setup connect claude --json >/dev/null
printf '%s\n' '{"hook_event_name":"Stop","session_id":"ci-session","cwd":"/tmp/project","prompt":"must-not-be-stored"}' \
    | HOME="$CLI_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_ROOT" "$BIN_DIR/omapet" hook claude
HOME="$CLI_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_ROOT" \
    "$BIN_DIR/omapet" setup status --json \
    | python3 -c 'import json, sys; assert json.load(sys.stdin)["status"] == "connected"'
python3 - "$CLI_HOME" <<'PY'
import json, pathlib, sys
events = pathlib.Path(sys.argv[1]) / "Library/Application Support/Oh My Agent Pet/events.ndjson"
lines = events.read_text().splitlines()
assert len(lines) == 1
event = json.loads(lines[0])
assert event["session_id"] == "ci-session"
assert "must-not-be-stored" not in lines[0]
PY
HOME="$CLI_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_ROOT" \
    "$BIN_DIR/omapet" setup disconnect claude --json >/dev/null

OUTPUT_ROOT="$TEMP_ROOT" "$ROOT_DIR/Scripts/build-app.sh" debug >/dev/null
APP_DIR="$TEMP_ROOT/Oh My Agent Pet.app"

test -x "$APP_DIR/Contents/MacOS/OhMyAgentPet"
test -x "$APP_DIR/Contents/MacOS/omapet"
test -f "$APP_DIR/Contents/Resources/LICENSE"
test -f "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")" = "com.seongmin.OhMyAgentPet"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_DIR/Contents/Info.plist")" = "14.0"
