#!/bin/bash
# Tests for the compaction-lifecycle wiring (B05: tracking-compaction-wiring):
# hooks.json must register the three compaction-lifecycle hooks (B02
# flush-nudge, B03 precompact-snapshot, B04 post-compact-recovery) with the
# correct events/matchers, session-context.sh must clear the flush-nudge
# epoch marker on every SessionStart, and plugin.json must be bumped to
# v0.5.1.
#
# Structural/integration tests only — do not execute the hook scripts
# themselves (those have their own dedicated test files).
#
# Run: bash plugins/tracking/scripts/compaction-wiring.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"
SESSION_CONTEXT_SH="$SCRIPT_DIR/session-context.sh"
PLUGIN_JSON="$SCRIPT_DIR/../.claude-plugin/plugin.json"

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

for f in "$HOOKS_JSON" "$SESSION_CONTEXT_SH" "$PLUGIN_JSON"; do
    if [ ! -f "$f" ]; then
        fail "required file exists" "not found at $f"
        echo ""
        echo "Some tests FAILED."
        exit 1
    fi
done

# --- Test 1: hooks.json is valid JSON ---
if jq -e . "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "hooks.json parses as valid JSON"
else
    fail "hooks.json parses as valid JSON" "jq failed to parse"
fi

# --- Test 2: UserPromptSubmit contains flush-nudge.sh ---
flush_nudge_count=$(jq -r \
  '[.hooks.UserPromptSubmit[]?.hooks[]?.command | select(test("flush-nudge\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${flush_nudge_count:-0}" -ge 1 ]; then
    pass "UserPromptSubmit registers a hook whose command includes flush-nudge.sh"
else
    fail "UserPromptSubmit registers a hook whose command includes flush-nudge.sh" \
        "no matching command found"
fi

# --- Test 3: PreCompact entry with matcher "auto" containing
# precompact-snapshot.sh ---
precompact_matcher_count=$(jq -r \
  '[.hooks.PreCompact[]? | select(.matcher == "auto") | .hooks[]?.command | select(test("precompact-snapshot\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${precompact_matcher_count:-0}" -ge 1 ]; then
    pass "PreCompact registers precompact-snapshot.sh under matcher \"auto\""
else
    fail "PreCompact registers precompact-snapshot.sh under matcher \"auto\"" \
        "no matching entry found"
fi

precompact_any_count=$(jq -r \
  '[.hooks.PreCompact[]?.hooks[]?.command | select(test("precompact-snapshot\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${precompact_any_count:-0}" -ge 1 ]; then
    pass "PreCompact registers precompact-snapshot.sh (any matcher)"
else
    fail "PreCompact registers precompact-snapshot.sh (any matcher)" "not found"
fi

# --- Test 4: SessionStart entry with matcher "compact" containing
# post-compact-recovery.sh ---
sessionstart_matcher_count=$(jq -r \
  '[.hooks.SessionStart[]? | select(.matcher == "compact") | .hooks[]?.command | select(test("post-compact-recovery\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${sessionstart_matcher_count:-0}" -ge 1 ]; then
    pass "SessionStart registers post-compact-recovery.sh under matcher \"compact\""
else
    fail "SessionStart registers post-compact-recovery.sh under matcher \"compact\"" \
        "no matching entry found"
fi

sessionstart_any_count=$(jq -r \
  '[.hooks.SessionStart[]?.hooks[]?.command | select(test("post-compact-recovery\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${sessionstart_any_count:-0}" -ge 1 ]; then
    pass "SessionStart registers post-compact-recovery.sh (any matcher)"
else
    fail "SessionStart registers post-compact-recovery.sh (any matcher)" "not found"
fi

# --- Test 5: hooks.json preserves all original hooks ---
session_context_count=$(jq -r \
  '[.hooks.SessionStart[]?.hooks[]?.command | select(test("session-context\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${session_context_count:-0}" -ge 1 ]; then
    pass "SessionStart still registers session-context.sh"
else
    fail "SessionStart still registers session-context.sh" "not found"
fi

keep_working_count=$(jq -r \
  '[.hooks.Stop[]?.hooks[]?.command | select(test("keep-working\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${keep_working_count:-0}" -ge 1 ]; then
    pass "Stop still registers keep-working.sh"
else
    fail "Stop still registers keep-working.sh" "not found"
fi

awaiting_stop_count=$(jq -r \
  '[.hooks.Stop[]?.hooks[]?.command | select(test("awaiting-user\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${awaiting_stop_count:-0}" -ge 1 ]; then
    pass "Stop still registers awaiting-user.sh"
else
    fail "Stop still registers awaiting-user.sh" "not found"
fi

awaiting_ups_count=$(jq -r \
  '[.hooks.UserPromptSubmit[]?.hooks[]?.command | select(test("awaiting-user\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${awaiting_ups_count:-0}" -ge 1 ]; then
    pass "UserPromptSubmit still registers awaiting-user.sh"
else
    fail "UserPromptSubmit still registers awaiting-user.sh" "not found"
fi

capture_count=$(jq -r \
  '[.hooks.UserPromptSubmit[]?.hooks[]?.command | select(test("capture\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${capture_count:-0}" -ge 1 ]; then
    pass "UserPromptSubmit still registers capture.sh"
else
    fail "UserPromptSubmit still registers capture.sh" "not found"
fi

block_task_tools_count=$(jq -r \
  '[.hooks.PreToolUse[]?.hooks[]?.command | select(test("block-task-tools\\.sh"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${block_task_tools_count:-0}" -ge 1 ]; then
    pass "PreToolUse still registers block-task-tools.sh"
else
    fail "PreToolUse still registers block-task-tools.sh" "not found"
fi

# --- Test 6: session-context.sh clears .flush-nudge-fired marker ---
rm_line=$(grep -n '^\[ -n "\$cwd" \] && rm -f' "$SESSION_CONTEXT_SH" | head -1)
if printf '%s' "$rm_line" | grep -q '\.flush-nudge-fired'; then
    pass "session-context.sh clears .flush-nudge-fired in the epoch-marker cleanup"
else
    fail "session-context.sh clears .flush-nudge-fired in the epoch-marker cleanup" \
        "marker not found in rm -f line: '$rm_line'"
fi

# The pre-existing markers must still be cleared alongside the new one.
for marker in ".decision-nudge-fired" ".no-todo-nudge-fired"; do
    if printf '%s' "$rm_line" | grep -q -- "$marker"; then
        pass "session-context.sh still clears $marker"
    else
        fail "session-context.sh still clears $marker" "marker not found in rm -f line: '$rm_line'"
    fi
done

# --- Test 7: plugin.json version is non-empty and well-formed semver ---
plugin_version=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json version is non-empty and well-formed semver (X.Y.Z)" \
  "$([[ "$plugin_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" "yes"

# --- Test 8: all three new scripts exist and are executable ---
for script in flush-nudge.sh precompact-snapshot.sh post-compact-recovery.sh; do
    script_path="$SCRIPT_DIR/$script"
    if [ -x "$script_path" ]; then
        pass "$script exists and is executable"
    else
        fail "$script exists and is executable" "not found or not executable at $script_path"
    fi
done

# --- Test 9: new hook entries reference scripts via ${CLAUDE_PLUGIN_ROOT} ---
flush_nudge_root_count=$(jq -r \
  '[.hooks.UserPromptSubmit[]?.hooks[]?.command | select(test("flush-nudge\\.sh")) | select(startswith("${CLAUDE_PLUGIN_ROOT}"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${flush_nudge_root_count:-0}" -ge 1 ]; then
    pass "flush-nudge.sh command uses \${CLAUDE_PLUGIN_ROOT}"
else
    fail "flush-nudge.sh command uses \${CLAUDE_PLUGIN_ROOT}" "not found"
fi

precompact_root_count=$(jq -r \
  '[.hooks.PreCompact[]?.hooks[]?.command | select(test("precompact-snapshot\\.sh")) | select(startswith("${CLAUDE_PLUGIN_ROOT}"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${precompact_root_count:-0}" -ge 1 ]; then
    pass "precompact-snapshot.sh command uses \${CLAUDE_PLUGIN_ROOT}"
else
    fail "precompact-snapshot.sh command uses \${CLAUDE_PLUGIN_ROOT}" "not found"
fi

post_compact_root_count=$(jq -r \
  '[.hooks.SessionStart[]?.hooks[]?.command | select(test("post-compact-recovery\\.sh")) | select(startswith("${CLAUDE_PLUGIN_ROOT}"))] | length' \
  "$HOOKS_JSON" 2>/dev/null)
if [ "${post_compact_root_count:-0}" -ge 1 ]; then
    pass "post-compact-recovery.sh command uses \${CLAUDE_PLUGIN_ROOT}"
else
    fail "post-compact-recovery.sh command uses \${CLAUDE_PLUGIN_ROOT}" "not found"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
