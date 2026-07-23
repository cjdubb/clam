#!/bin/bash
# Tests for session-context.sh: the SessionStart hook's auto-create-TODO.md
# behavior (B01), resume injection, and epoch marker clearing.
#
# Hermetic: creates a temp directory tree simulating a worktree with .local/,
# feeds synthetic hook JSON to session-context.sh, and asserts on the resulting
# TODO.md (or absence thereof) and the hook's JSON output.
#
# Run: bash plugins/tracking/scripts/session-context.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-context.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

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

# Build a minimal SessionStart hook JSON payload.
hook_json() { # cwd
    printf '{"cwd":"%s","hook_event_name":"SessionStart","session_id":"test-sid"}' "$1"
}

# Run the hook and capture stdout (the JSON output).
run_hook() { # cwd
    printf '%s' "$(hook_json "$1")" | bash "$HOOK" 2>/dev/null
}

# --- Auto-create TODO.md tests (B01 contract) ---

# Test: auto-creates TODO.md when .local/ exists without TODO.md
test_auto_create_when_local_exists() {
    local wd="$TMPROOT/auto-create"
    mkdir -p "$wd/.local"
    run_hook "$wd" >/dev/null
    if [ -f "$wd/.local/TODO.md" ]; then
        pass "auto-creates TODO.md when .local/ exists"
    else
        fail "auto-creates TODO.md when .local/ exists" "TODO.md not created"
    fi
}

# Test: auto-created TODO.md has State: Not Started
test_auto_create_has_state() {
    local wd="$TMPROOT/auto-state"
    mkdir -p "$wd/.local"
    run_hook "$wd" >/dev/null
    local state
    state=$(grep -m1 '^State:' "$wd/.local/TODO.md" 2>/dev/null | sed 's/^State:[[:space:]]*//')
    check "auto-created TODO.md has State: Not Started" "$state" "Not Started"
}

# Test: does NOT overwrite existing TODO.md
test_no_overwrite() {
    local wd="$TMPROOT/no-overwrite"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\nCurrent Task: doing stuff\n' > "$wd/.local/TODO.md"
    run_hook "$wd" >/dev/null
    local state
    state=$(grep -m1 '^State:' "$wd/.local/TODO.md" 2>/dev/null | sed 's/^State:[[:space:]]*//')
    check "does not overwrite existing TODO.md" "$state" "In Progress"
}

# Test: no-op when .local/ does not exist
test_noop_without_local() {
    local wd="$TMPROOT/no-local"
    mkdir -p "$wd"
    run_hook "$wd" >/dev/null
    if [ ! -f "$wd/.local/TODO.md" ]; then
        pass "no-op when .local/ does not exist"
    else
        fail "no-op when .local/ does not exist" "TODO.md was created"
    fi
}

# Test: no-op when template is missing
test_noop_without_template() {
    local wd="$TMPROOT/no-template"
    mkdir -p "$wd/.local"
    local real_template="$PLUGIN_ROOT/templates/TODO.md"
    local backup="$TMPROOT/TODO.md.bak"
    # Temporarily move the template away
    if [ -f "$real_template" ]; then
        mv "$real_template" "$backup"
    fi
    run_hook "$wd" >/dev/null
    local created=no
    [ -f "$wd/.local/TODO.md" ] && created=yes
    # Restore template
    if [ -f "$backup" ]; then
        mv "$backup" "$real_template"
    fi
    check "no-op when template is missing" "$created" "no"
}

# Test: substitutes [YYYY-MM-DD] with current date
test_date_substitution() {
    local wd="$TMPROOT/date-sub"
    mkdir -p "$wd/.local"
    run_hook "$wd" >/dev/null
    local today
    today=$(date +%Y-%m-%d)
    if grep -q "$today" "$wd/.local/TODO.md" 2>/dev/null; then
        pass "substitutes [YYYY-MM-DD] with current date"
    else
        fail "substitutes [YYYY-MM-DD] with current date" "date $today not found in TODO.md"
    fi
}

# Test: substitutes [branch-name] with git branch (when in a git repo)
test_branch_substitution() {
    local wd="$TMPROOT/branch-sub"
    mkdir -p "$wd/.local"
    # Init a git repo so there's a branch to detect
    git init -q "$wd" 2>/dev/null
    git -C "$wd" checkout -q -b test-branch 2>/dev/null
    # Need at least one commit for branch to exist
    git -C "$wd" commit -q --allow-empty -m "init" 2>/dev/null
    run_hook "$wd" >/dev/null
    if grep -q "test-branch" "$wd/.local/TODO.md" 2>/dev/null; then
        pass "substitutes [branch-name] with git branch"
    else
        fail "substitutes [branch-name] with git branch" "branch name not found in TODO.md"
    fi
}

# --- Resume injection tests ---

# Test: freshly auto-created TODO.md triggers resume context
test_auto_create_triggers_resume() {
    local wd="$TMPROOT/resume-trigger"
    mkdir -p "$wd/.local"
    local output
    output=$(run_hook "$wd")
    if printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q "Tracking document present"; then
        pass "auto-created TODO.md triggers resume context"
    else
        fail "auto-created TODO.md triggers resume context" "resume context not in output"
    fi
}

# Test: existing TODO.md produces resume context with correct state
test_resume_existing_todo() {
    local wd="$TMPROOT/resume-existing"
    mkdir -p "$wd/.local"
    printf 'State: Blocked\nCurrent Task: waiting for deploy\n' > "$wd/.local/TODO.md"
    local output
    output=$(run_hook "$wd")
    local ctx
    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
    if printf '%s' "$ctx" | grep -q "State: Blocked"; then
        pass "resume context shows correct state"
    else
        fail "resume context shows correct state" "State: Blocked not in resume context"
    fi
}

# --- Epoch marker tests ---

# Test: clears .decision-nudge-fired on SessionStart
test_clears_epoch_markers() {
    local wd="$TMPROOT/epoch"
    mkdir -p "$wd/.local"
    touch "$wd/.local/.decision-nudge-fired"
    run_hook "$wd" >/dev/null
    if [ ! -f "$wd/.local/.decision-nudge-fired" ]; then
        pass "clears .decision-nudge-fired on SessionStart"
    else
        fail "clears .decision-nudge-fired on SessionStart" "marker still exists"
    fi
}

# --- Run all tests ---
test_auto_create_when_local_exists
test_auto_create_has_state
test_no_overwrite
test_noop_without_local
test_noop_without_template
test_date_substitution
test_branch_substitution
test_auto_create_triggers_resume
test_resume_existing_todo
test_clears_epoch_markers

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
