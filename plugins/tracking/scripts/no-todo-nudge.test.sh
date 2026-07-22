#!/bin/bash
# Tests for keep-working.sh's check_no_todo_nudge function (B08): the
# generic "substantive work but no TODO.md" backstop.
#
# Hermetic: extracts just the check_no_todo_nudge function body from
# keep-working.sh (the script itself can't be sourced in isolation — it
# consumes stdin and runs a whole Stop-hook decision with `set -e`) and
# evals it into this shell. Each test builds a synthetic worktree under a
# temp dir, sets the $cwd global the function reads, and asserts on its
# return code and the $NO_TODO_BLOCK_REASON / marker file it produces.
#
# Run: bash plugins/tracking/scripts/no-todo-nudge.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/keep-working.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$PLUGIN_ROOT/lib/states.sh"

# Extract just check_no_todo_nudge. The closing brace at column 0 is unique
# to the function boundary (nested if/case blocks in keep-working.sh never
# open a brace of their own), so this pulls today's stub, and the real
# implementation once B08 lands, without running the rest of the hook.
FUNC_SRC=$(sed -n '/^check_no_todo_nudge() {/,/^}/p' "$SCRIPT")
if [ -z "$FUNC_SRC" ]; then
    echo "FAIL  could not extract check_no_todo_nudge from $SCRIPT" >&2
    exit 1
fi
eval "$FUNC_SRC"

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

# Builds a worktree with one baseline commit and no uncommitted changes —
# the "no substantive work" starting point every test extends from.
make_committed_wd() { # name -> echoes path
    local wd="$TMPROOT/$1"
    mkdir -p "$wd"
    git init -q "$wd"
    git -C "$wd" config user.email test@example.com
    git -C "$wd" config user.name test
    printf 'baseline\n' > "$wd/baseline.txt"
    git -C "$wd" add -A
    git -C "$wd" commit -q -m init
    printf '%s' "$wd"
}

# Adds an uncommitted edit: the unambiguous "substantive work" signal. (The
# contract's other signal, commits ahead of a base branch, needs a second
# branch to be meaningful and isn't exercised here.)
add_uncommitted_edit() { # wd
    printf 'edit\n' >> "$1/baseline.txt"
}

# Calls check_no_todo_nudge with $cwd=$wd, capturing its return code in $RC.
run_check() { # wd
    cwd="$1"
    NO_TODO_BLOCK_REASON=""
    check_no_todo_nudge
    RC=$?
}

# --- Tests ---

# No .local/ directory at all -> no nudge, even with substantive git work
# (Go Commando is preserved regardless of git state).
test_no_local_no_nudge() {
    local wd
    wd=$(make_committed_wd "no-local")
    add_uncommitted_edit "$wd"
    run_check "$wd"
    check "no .local/ -> no nudge (rc)" "$RC" "0"
}

# .local/TODO.md present -> no nudge, even with substantive git work (the
# TODO.md-absent check gates ahead of the git check).
test_todo_present_no_nudge() {
    local wd
    wd=$(make_committed_wd "todo-present")
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    add_uncommitted_edit "$wd"
    run_check "$wd"
    check "TODO.md present -> no nudge (rc)" "$RC" "0"
}

# .local/ exists, TODO.md absent, but no substantive git work -> no nudge
# (a pure-conversation session with an empty .local/ isn't nagged).
test_no_git_work_no_nudge() {
    local wd
    wd=$(make_committed_wd "no-git-work")
    mkdir -p "$wd/.local"
    run_check "$wd"
    check "no git work -> no nudge (rc)" "$RC" "0"
}

# All conditions met (.local/ exists, TODO.md absent, edits present, marker
# absent) -> nudge: rc=1 and NO_TODO_BLOCK_REASON populated, instructing the
# session to create TODO.md.
test_all_conditions_nudge() {
    local wd
    wd=$(make_committed_wd "all-conditions")
    mkdir -p "$wd/.local"
    add_uncommitted_edit "$wd"
    run_check "$wd"
    check "all conditions met -> nudge (rc)" "$RC" "1"
    if printf '%s' "$NO_TODO_BLOCK_REASON" | grep -qi "TODO.md"; then
        pass "nudge reason instructs creating TODO.md"
    else
        fail "nudge reason instructs creating TODO.md" "got '$NO_TODO_BLOCK_REASON'"
    fi
}

# Once-per-epoch marker present -> no nudge even though every other
# condition is met (prevents repeated blocking within the same epoch).
test_marker_prevents_refire() {
    local wd
    wd=$(make_committed_wd "marker-present")
    mkdir -p "$wd/.local"
    add_uncommitted_edit "$wd"
    touch "$wd/.local/.no-todo-nudge-fired"
    run_check "$wd"
    check "marker present -> no nudge (rc)" "$RC" "0"
}

# First fire creates the once-per-epoch marker file.
test_marker_created_on_fire() {
    local wd
    wd=$(make_committed_wd "marker-created")
    mkdir -p "$wd/.local"
    add_uncommitted_edit "$wd"
    run_check "$wd"
    if [ -f "$wd/.local/.no-todo-nudge-fired" ]; then
        pass "marker created on first fire"
    else
        fail "marker created on first fire" "marker file not found after nudge"
    fi
}

# --- Run all tests ---
test_no_local_no_nudge
test_todo_present_no_nudge
test_no_git_work_no_nudge
test_all_conditions_nudge
test_marker_prevents_refire
test_marker_created_on_fire

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
