#!/bin/bash
# Tests for plugins/tracking/hooks/hooks.json — the merge-hooks contract
# (B01): make-progress's UserPromptSubmit capture hook must be absorbed into
# tracking's hooks.json using the correct event-keyed record format, not the
# broken top-level array-of-{event,command} format the original
# make-progress hooks.json used.
#
# Run: bash plugins/tracking/scripts/merge-hooks.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }

check() { # label got expected
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1" "got '$2', expected '$3'"
    fi
}

if [ ! -f "$HOOKS_JSON" ]; then
    fail "hooks.json exists" "not found at $HOOKS_JSON"
    echo ""
    echo "Some tests FAILED."
    exit 1
fi

# --- Test 1: valid JSON structure ---
if jq -e . "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "hooks.json parses as valid JSON"
else
    fail "hooks.json parses as valid JSON" "jq failed to parse"
fi

# --- Test 2: event-keyed record format (top-level 'hooks' is an object,
# with each named event holding an array of matcher entries) ---
hooks_type=$(jq -r '.hooks | type' "$HOOKS_JSON" 2>/dev/null)
check "top-level hooks is an object, not an array" "$hooks_type" "object"

for event in SessionStart Stop UserPromptSubmit PreToolUse; do
    event_type=$(jq -r --arg e "$event" '.hooks[$e] | type' "$HOOKS_JSON" 2>/dev/null)
    check "hooks.$event is present (array of matchers)" "$event_type" "array"
done

# --- Test 3: capture hook registered under UserPromptSubmit ---
capture_count=$(jq -r \
  '[.hooks.UserPromptSubmit[]?.hooks[]?.command | select(test("capture\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${capture_count:-0}" -ge 1 ]; then
    pass "UserPromptSubmit registers a hook whose command includes capture.sh"
else
    fail "UserPromptSubmit registers a hook whose command includes capture.sh" \
        "no matching command found"
fi

# --- Test 4: existing hooks preserved alongside the new capture hook ---
awaiting_count=$(jq -r \
  '[.hooks.UserPromptSubmit[]?.hooks[]?.command | select(test("awaiting-user\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${awaiting_count:-0}" -ge 1 ]; then
    pass "UserPromptSubmit still registers awaiting-user.sh"
else
    fail "UserPromptSubmit still registers awaiting-user.sh" "not found"
fi

session_start_count=$(jq -r \
  '[.hooks.SessionStart[]?.hooks[]?.command | select(test("session-context\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${session_start_count:-0}" -ge 1 ]; then
    pass "SessionStart still registers session-context.sh"
else
    fail "SessionStart still registers session-context.sh" "not found"
fi

stop_count=$(jq -r \
  '[.hooks.Stop[]?.hooks[]?.command | select(test("keep-working\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${stop_count:-0}" -ge 1 ]; then
    pass "Stop still registers keep-working.sh"
else
    fail "Stop still registers keep-working.sh" "not found"
fi

pretooluse_count=$(jq -r \
  '[.hooks.PreToolUse[]?.hooks[]?.command | select(test("block-task-tools\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${pretooluse_count:-0}" -ge 1 ]; then
    pass "PreToolUse still registers block-task-tools.sh"
else
    fail "PreToolUse still registers block-task-tools.sh" "not found"
fi

# --- Test 5: does NOT match the broken make-progress array format, i.e.
# a top-level array of {event, command} objects such as:
#   { "hooks": [ { "event": "UserPromptSubmit", "command": "..." } ] }
is_broken_array=$(jq -r '(.hooks | type) == "array"' "$HOOKS_JSON" 2>/dev/null)
check "hooks.json does NOT use the broken top-level array format" "$is_broken_array" "false"

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
