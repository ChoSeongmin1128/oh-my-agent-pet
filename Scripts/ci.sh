#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/Config/product.env"
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
expected_version, expected_name = sys.argv[1:3]
assert value == {"name": expected_name, "version": expected_version}
' "$PRODUCT_DEV_VERSION" "$PRODUCT_NAME"

CLI_HOME="$TEMP_ROOT/home"
CLAUDE_ROOT="$TEMP_ROOT/Claude Config"
mkdir -p "$CLAUDE_ROOT"
printf '%s\n' '{"theme":"dark"}' > "$CLAUDE_ROOT/settings.json"
HOME="$CLI_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_ROOT" \
    "$BIN_DIR/omapet" setup connect claude --json >/dev/null
printf '%s\n' '{"hook_event_name":"Stop","session_id":"ci-session","cwd":"/tmp/project","prompt":"must-not-be-stored"}' \
    | HOME="$CLI_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_ROOT" "$BIN_DIR/omapet" hook claude
printf '%s\n' '{"hook_event_name":"PermissionRequest","session_id":"11111111-1111-1111-1111-111111111111","turn_id":"ci-turn","cwd":"/tmp/project","tool_name":"Bash"}' \
    | HOME="$CLI_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_ROOT" "$BIN_DIR/omapet" hook codex
HOME="$CLI_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_ROOT" \
    "$BIN_DIR/omapet" setup status --json \
    | python3 -c 'import json, sys; assert json.load(sys.stdin)["status"] == "connected"'
python3 - "$CLI_HOME" <<'PY'
import json, pathlib, sys
events = pathlib.Path(sys.argv[1]) / "Library/Application Support/Oh My Agent Pet/events.ndjson"
lines = events.read_text().splitlines()
assert len(lines) == 2
claude = json.loads(lines[0])
codex = json.loads(lines[1])
assert claude["provider"] == "claude"
assert claude["session_id"] == "ci-session"
assert codex["provider"] == "codex"
assert codex["session_id"] == "11111111-1111-1111-1111-111111111111"
assert codex["turn_id"] == "ci-turn"
assert "must-not-be-stored" not in lines[0]
PY
HOME="$CLI_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_ROOT" \
    "$BIN_DIR/omapet" setup disconnect claude --json >/dev/null
HOME="$CLI_HOME" "$BIN_DIR/omapet" pet list --json | python3 -c '
import json, sys
value = json.load(sys.stdin)
assert value["ok"] is True
assert value["pets"] == []
assert value["selection"] == {"kind": "original"}
'
test ! -e "$CLI_HOME/Library/Application Support/Oh My Agent Pet/Pets"
PET_ERROR_OUTPUT="$(HOME="$CLI_HOME" "$BIN_DIR/omapet" pet install "$TEMP_ROOT/does-not-exist" --json || true)"
printf '%s' "$PET_ERROR_OUTPUT" \
    | python3 -c 'import json, sys; assert json.load(sys.stdin)["code"] == "source_unavailable"'

OUTPUT_ROOT="$TEMP_ROOT" "$ROOT_DIR/Scripts/build-app.sh" debug >/dev/null
APP_DIR="$TEMP_ROOT/$PRODUCT_NAME.app"

test -x "$APP_DIR/Contents/MacOS/OhMyAgentPet"
test -x "$APP_DIR/Contents/MacOS/omapet"
test -f "$APP_DIR/Contents/Resources/LICENSE"
test -f "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")" = "$PRODUCT_BUNDLE_ID"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_DIR/Contents/Info.plist")" = "$PRODUCT_MIN_MACOS"
test -n "$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$APP_DIR/Contents/Info.plist")"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.automation.apple-events' "$ROOT_DIR/Config/OhMyAgentPet.entitlements")" = "true"
