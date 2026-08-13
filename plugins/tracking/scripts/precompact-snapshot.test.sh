#!/bin/bash
# Tests for precompact-snapshot.sh (B03): the PreCompact hook that snapshots
# .local/ tracking docs to .local/snapshots/<ts>/ before auto-compaction and
# appends an HTML-comment marker to TODO.md recording where the snapshot
# lives.
#
# Contract differences from the clam-code predecessor
# (~/github/clam-code-trees/master/general/hooks/precompact-snapshot.sh):
#   - Gated on .local/TODO.md existing (NOT .local/MODE).
#   - No $CLAM_SESSION gate (plugin enablement is the opt-in).
#
# Hermetic: builds synthetic worktrees under a temp dir, feeds PreCompact
# hook JSON on stdin, and asserts on filesystem side effects — the hook
# produces no stdout (PreCompact hooks cannot inject context) so there is
# nothing to assert there except that it stays empty. A PATH shim (borrowed
# from capture.test.sh's build_path_without) simulates "jq missing"; chmod
# is used to force cp/mkdir/write failures for the fail-open paths.
#
# Run: bash plugins/tracking/scripts/precompact-snapshot.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/precompact-snapshot.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck disable=SC1091  # sourced at runtime from the repo root
. "$REPO_ROOT/scripts/lib/test-portability.sh"

# Absolute bash: a shim PATH may not contain the platform's bash directory
# (bash lives in /bin on macOS), so a bare `bash` there would exit 127.
BASH_BIN="${BASH:-/bin/bash}"

TMPROOT=$(mktemp -d)
# chmod back to writable first: several tests deliberately strip write/read
# bits to force failures, and rm -rf can't clean those up otherwise.
trap 'chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"' EXIT

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

# --- helper: build a PATH dir that has everything EXCEPT one named command --
# Farms the whole real PATH (not just /usr/bin — bash lives in /bin on macOS
# and jq typically under Homebrew) minus $1. Used to simulate "jq not on
# PATH" without touching real permissions.
build_path_without() { # cmd -> prints new PATH dir
    local cmd="$1"
    local out="$TMPROOT/bin-no-$cmd"
    mkdir -p "$out"
    tp_shim_path "$out" --remove "$cmd" > /dev/null
    echo "$out"
}
NOJQBIN=$(build_path_without jq)

# Build a PreCompact hook JSON payload.
hook_json() { # cwd
    printf '{"cwd":"%s","hook_event_name":"PreCompact","trigger":"auto","session_id":"test-sid"}' "$1"
}

# Same, but with the cwd key omitted entirely (tests the "cwd missing" gate).
hook_json_no_cwd() {
    printf '{"hook_event_name":"PreCompact","trigger":"auto","session_id":"test-sid"}'
}

# Run the hook with a normal cwd payload. Sets $HOOK_STDOUT and $RC.
run_hook() { # cwd [extra_path]
    local wd="$1" extra_path="${2:-}"
    if [ -n "$extra_path" ]; then
        HOOK_STDOUT=$(printf '%s' "$(hook_json "$wd")" | PATH="$extra_path" "$BASH_BIN" "$HOOK" 2>/dev/null)
    else
        HOOK_STDOUT=$(printf '%s' "$(hook_json "$wd")" | bash "$HOOK" 2>/dev/null)
    fi
    RC=$?
}

# Run the hook with a cwd-less payload.
run_hook_no_cwd() {
    HOOK_STDOUT=$(printf '%s' "$(hook_json_no_cwd)" | bash "$HOOK" 2>/dev/null)
    RC=$?
}

# Lists snapshot subdirectory names under wd/.local/snapshots, one per line.
find_snapshot_dirs() { # wd
    find "$1/.local/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
}

# Asserts the hook exited 0 and created no snapshot directory anywhere
# under wd/.local/snapshots.
assert_skipped() { # label wd rc
    local label="$1" wd="$2" rc="$3" dirs
    if [ "$rc" -ne 0 ]; then
        fail "$label" "expected exit 0, got $rc"
        return
    fi
    dirs=$(find_snapshot_dirs "$wd")
    if [ -n "$dirs" ]; then
        fail "$label" "expected no snapshot dir, found: $dirs"
        return
    fi
    pass "$label"
}

# --- Gate tests (contract Edge cases) -----------------------------------

# Edge case: .local/TODO.md does not exist -> skip (nothing to protect).
test_gate_no_todo() {
    local wd="$TMPROOT/gate-no-todo"
    mkdir -p "$wd/.local"
    # A sibling tracking file exists, proving the gate is specifically on
    # TODO.md, not on .local/ having any content at all.
    printf 'plan content\n' > "$wd/.local/PLAN.md"
    run_hook "$wd"
    assert_skipped "gate: no TODO.md -> skip" "$wd" "$RC"
}

# Edge case: .local/ directory does not exist -> skip.
test_gate_no_local() {
    local wd="$TMPROOT/gate-no-local"
    mkdir -p "$wd"
    run_hook "$wd"
    assert_skipped "gate: no .local/ -> skip" "$wd" "$RC"
}

# Edge case: cwd missing from input JSON -> skip. Uses a wd that would
# otherwise pass every other gate, to prove the hook doesn't fall back to
# some other notion of cwd (e.g. $PWD) when the JSON field is absent.
test_gate_missing_cwd() {
    local wd="$TMPROOT/gate-missing-cwd"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    run_hook_no_cwd
    assert_skipped "gate: cwd missing from JSON -> skip" "$wd" "$RC"
}

# Edge case: jq not available -> skip silently.
test_gate_no_jq() {
    local wd="$TMPROOT/gate-no-jq"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    run_hook "$wd" "$NOJQBIN"
    assert_skipped "gate: jq unavailable -> skip" "$wd" "$RC"
}

# --- Snapshot content tests ----------------------------------------------

# Copies TODO.md into the snapshot dir.
test_copies_todo() {
    local wd="$TMPROOT/copy-todo"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\nCurrent Task: thing\n' > "$wd/.local/TODO.md"
    run_hook "$wd"
    local dir
    dir=$(find_snapshot_dirs "$wd")
    if [ -z "$dir" ]; then
        fail "copies TODO.md" "no snapshot dir created"
        return
    fi
    if [ -f "$dir/TODO.md" ] && grep -q "Current Task: thing" "$dir/TODO.md"; then
        pass "copies TODO.md"
    else
        fail "copies TODO.md" "TODO.md missing or content mismatch in $dir"
    fi
}

# Copies PLAN.md when present.
test_copies_plan() {
    local wd="$TMPROOT/copy-plan"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    printf 'the plan\n' > "$wd/.local/PLAN.md"
    run_hook "$wd"
    local dir
    dir=$(find_snapshot_dirs "$wd")
    if [ -n "$dir" ] && [ -f "$dir/PLAN.md" ] && grep -q "the plan" "$dir/PLAN.md"; then
        pass "copies PLAN.md when present"
    else
        fail "copies PLAN.md when present" "PLAN.md missing or content mismatch in snapshot dir '$dir'"
    fi
}

# Copies IMPLEMENTATION-PLAN.md when present.
test_copies_implementation_plan() {
    local wd="$TMPROOT/copy-impl-plan"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    printf 'impl details\n' > "$wd/.local/IMPLEMENTATION-PLAN.md"
    run_hook "$wd"
    local dir
    dir=$(find_snapshot_dirs "$wd")
    if [ -n "$dir" ] && [ -f "$dir/IMPLEMENTATION-PLAN.md" ] && grep -q "impl details" "$dir/IMPLEMENTATION-PLAN.md"; then
        pass "copies IMPLEMENTATION-PLAN.md when present"
    else
        fail "copies IMPLEMENTATION-PLAN.md when present" "missing or content mismatch in snapshot dir '$dir'"
    fi
}

# Copies TROUBLESHOOTING.md when present.
test_copies_troubleshooting() {
    local wd="$TMPROOT/copy-trouble"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    printf 'known issue\n' > "$wd/.local/TROUBLESHOOTING.md"
    run_hook "$wd"
    local dir
    dir=$(find_snapshot_dirs "$wd")
    if [ -n "$dir" ] && [ -f "$dir/TROUBLESHOOTING.md" ] && grep -q "known issue" "$dir/TROUBLESHOOTING.md"; then
        pass "copies TROUBLESHOOTING.md when present"
    else
        fail "copies TROUBLESHOOTING.md when present" "missing or content mismatch in snapshot dir '$dir'"
    fi
}

# Copies all SUBAGENT-LOG-*.md files (glob match), including multiple.
test_copies_subagent_logs() {
    local wd="$TMPROOT/copy-subagent-logs"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    printf 'alpha log\n' > "$wd/.local/SUBAGENT-LOG-alpha.md"
    printf 'beta log\n' > "$wd/.local/SUBAGENT-LOG-beta.md"
    run_hook "$wd"
    local dir
    dir=$(find_snapshot_dirs "$wd")
    if [ -n "$dir" ] \
        && [ -f "$dir/SUBAGENT-LOG-alpha.md" ] && grep -q "alpha log" "$dir/SUBAGENT-LOG-alpha.md" \
        && [ -f "$dir/SUBAGENT-LOG-beta.md" ] && grep -q "beta log" "$dir/SUBAGENT-LOG-beta.md"; then
        pass "copies all SUBAGENT-LOG-*.md (glob)"
    else
        fail "copies all SUBAGENT-LOG-*.md (glob)" "one or both logs missing/mismatched in snapshot dir '$dir'"
    fi
}

# Only copies files that exist; missing ones are not errors.
test_only_copies_existing() {
    local wd="$TMPROOT/only-existing"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    printf 'the plan\n' > "$wd/.local/PLAN.md"
    # Deliberately no IMPLEMENTATION-PLAN.md, TROUBLESHOOTING.md, or
    # SUBAGENT-LOG-*.md.
    run_hook "$wd"
    if [ "$RC" -ne 0 ]; then
        fail "only copies files that exist (no error on missing)" "expected exit 0, got $RC"
        return
    fi
    local dir entries
    dir=$(find_snapshot_dirs "$wd")
    if [ -z "$dir" ]; then
        fail "only copies files that exist (no error on missing)" "no snapshot dir created"
        return
    fi
    entries=$(find "$dir" -mindepth 1 -maxdepth 1 -type f | sed 's#.*/##' | sort | tr '\n' ' ')
    check "only copies files that exist (no error on missing)" "$entries" "PLAN.md TODO.md "
}

# Snapshot directory name matches YYYYMMDD-HHMMSS.
test_snapshot_dir_naming() {
    local wd="$TMPROOT/dir-naming"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    run_hook "$wd"
    local dir base
    dir=$(find_snapshot_dirs "$wd")
    base=$(basename "$dir" 2>/dev/null)
    if [[ "$base" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
        pass "snapshot dir naming is YYYYMMDD-HHMMSS"
    else
        fail "snapshot dir naming is YYYYMMDD-HHMMSS" "got '$base'"
    fi
}

# Empty snapshot cleanup: TODO.md exists (gate passes) but cp of it fails
# (permission denied) -> the created-but-empty snapshot dir is rmdir'd.
test_empty_snapshot_cleanup() {
    local wd="$TMPROOT/empty-cleanup"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    chmod 000 "$wd/.local/TODO.md"
    run_hook "$wd"
    local rc="$RC" dirs
    chmod 644 "$wd/.local/TODO.md"
    if [ "$rc" -ne 0 ]; then
        fail "empty snapshot dir is cleaned up (rmdir)" "expected exit 0, got $rc"
        return
    fi
    dirs=$(find_snapshot_dirs "$wd")
    if [ -n "$dirs" ]; then
        fail "empty snapshot dir is cleaned up (rmdir)" "leftover snapshot dir(s): $dirs"
    else
        pass "empty snapshot dir is cleaned up (rmdir)"
    fi
}

# --- Marker tests ----------------------------------------------------------

# HTML-comment marker is appended to the end of TODO.md.
test_marker_appended() {
    local wd="$TMPROOT/marker-appended"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    run_hook "$wd"
    if grep -q '<!-- AUTO-COMPACTION' "$wd/.local/TODO.md"; then
        pass "HTML-comment marker appended to TODO.md"
    else
        fail "HTML-comment marker appended to TODO.md" "no marker found"
    fi
}

# Marker format matches the contract exactly, and its embedded snapshot
# path matches the snapshot dir actually created on disk.
test_marker_format() {
    local wd="$TMPROOT/marker-format"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    run_hook "$wd"
    local dir base marker_line matched_ts
    dir=$(find_snapshot_dirs "$wd")
    base=$(basename "$dir" 2>/dev/null)
    marker_line=$(grep '^<!-- AUTO-COMPACTION' "$wd/.local/TODO.md" | tail -n1)
    if [[ "$marker_line" =~ ^\<!--\ AUTO-COMPACTION\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ —\ pre-compact\ snapshot\ at\ \.local/snapshots/([0-9]{8}-[0-9]{6})/\ --\>$ ]]; then
        matched_ts="${BASH_REMATCH[1]}"
        check "marker format matches contract and references actual snapshot dir" "$matched_ts" "$base"
    else
        fail "marker format matches contract and references actual snapshot dir" "marker line '$marker_line' did not match expected format"
    fi
}

# Original TODO.md content is unchanged (the marker is only appended after
# it, never rewriting or reordering existing content).
test_marker_preserves_original_content() {
    local wd="$TMPROOT/marker-preserve"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\nCurrent Task: doing the thing\nNotes: keep this\n' > "$wd/.local/TODO.md"
    local original
    original=$(cat "$wd/.local/TODO.md")
    run_hook "$wd"
    local prefix
    prefix=$(head -c "${#original}" "$wd/.local/TODO.md")
    check "marker append preserves original TODO.md content" "$prefix" "$original"
}

# TODO.md is not writable -> marker append is skipped, but the hook still
# exits 0 and TODO.md is left untouched (contract Edge cases).
test_readonly_todo_skips_marker() {
    local wd="$TMPROOT/readonly-todo"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    chmod 444 "$wd/.local/TODO.md"
    run_hook "$wd"
    local rc="$RC" content
    content=$(cat "$wd/.local/TODO.md")
    chmod 644 "$wd/.local/TODO.md"
    if [ "$rc" -ne 0 ]; then
        fail "read-only TODO.md skips marker append, exits 0" "expected exit 0, got $rc"
        return
    fi
    if printf '%s' "$content" | grep -q 'AUTO-COMPACTION'; then
        fail "read-only TODO.md skips marker append, exits 0" "marker was appended despite read-only TODO.md"
    else
        pass "read-only TODO.md skips marker append, exits 0"
    fi
}

# --- Source-file integrity tests -------------------------------------------

# Source files (other than the TODO.md marker append) are never modified.
test_source_files_unmodified() {
    local wd="$TMPROOT/source-unmodified"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    printf 'the plan\n' > "$wd/.local/PLAN.md"
    printf 'impl details\n' > "$wd/.local/TROUBLESHOOTING.md"
    printf 'log entry\n' > "$wd/.local/SUBAGENT-LOG-alpha.md"
    local plan_before trouble_before log_before
    plan_before=$(md5sum "$wd/.local/PLAN.md" | awk '{print $1}')
    trouble_before=$(md5sum "$wd/.local/TROUBLESHOOTING.md" | awk '{print $1}')
    log_before=$(md5sum "$wd/.local/SUBAGENT-LOG-alpha.md" | awk '{print $1}')
    run_hook "$wd"
    local plan_after trouble_after log_after
    plan_after=$(md5sum "$wd/.local/PLAN.md" | awk '{print $1}')
    trouble_after=$(md5sum "$wd/.local/TROUBLESHOOTING.md" | awk '{print $1}')
    log_after=$(md5sum "$wd/.local/SUBAGENT-LOG-alpha.md" | awk '{print $1}')
    if [ "$plan_before" = "$plan_after" ] && [ "$trouble_before" = "$trouble_after" ] && [ "$log_before" = "$log_after" ]; then
        pass "source files other than TODO.md are never modified"
    else
        fail "source files other than TODO.md are never modified" "one or more source files changed"
    fi
}

# --- Exit code / fail-open tests --------------------------------------------

# Fail-open: snapshot directory creation fails (parent .local/ not writable)
# -> the hook still exits 0.
test_failopen_unwritable_snapshot_dir() {
    local wd="$TMPROOT/failopen-unwritable"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    chmod 555 "$wd/.local"
    run_hook "$wd"
    local rc="$RC"
    chmod 755 "$wd/.local"
    check "fail-open: unwritable snapshot dir still exits 0" "$rc" "0"
}

# Exit code is 0 across every path exercised above: success, every gate
# skip, and the fail-open paths.
test_always_exits_zero() {
    local all_zero=1

    local wd
    wd="$TMPROOT/exit0-success"; mkdir -p "$wd/.local"; printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    run_hook "$wd"; [ "$RC" -eq 0 ] || all_zero=0

    wd="$TMPROOT/exit0-no-todo"; mkdir -p "$wd/.local"
    run_hook "$wd"; [ "$RC" -eq 0 ] || all_zero=0

    wd="$TMPROOT/exit0-no-local"; mkdir -p "$wd"
    run_hook "$wd"; [ "$RC" -eq 0 ] || all_zero=0

    wd="$TMPROOT/exit0-no-jq"; mkdir -p "$wd/.local"; printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    run_hook "$wd" "$NOJQBIN"; [ "$RC" -eq 0 ] || all_zero=0

    wd="$TMPROOT/exit0-cwd-missing"; mkdir -p "$wd/.local"; printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    run_hook_no_cwd; [ "$RC" -eq 0 ] || all_zero=0

    wd="$TMPROOT/exit0-unwritable"; mkdir -p "$wd/.local"; printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    chmod 555 "$wd/.local"
    run_hook "$wd"; [ "$RC" -eq 0 ] || all_zero=0
    chmod 755 "$wd/.local"

    check "always exits 0 across success, gate-skip, and fail-open paths" "$all_zero" "1"
}

# stdout is always empty: PreCompact hooks cannot inject context.
test_stdout_always_empty() {
    local all_empty=1

    local wd
    wd="$TMPROOT/stdout-success"; mkdir -p "$wd/.local"; printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    run_hook "$wd"; [ -z "$HOOK_STDOUT" ] || all_empty=0

    wd="$TMPROOT/stdout-skip"; mkdir -p "$wd"
    run_hook "$wd"; [ -z "$HOOK_STDOUT" ] || all_empty=0

    check "stdout is always empty" "$all_empty" "1"
}

# --- Run all tests ---
test_gate_no_todo
test_gate_no_local
test_gate_missing_cwd
test_gate_no_jq
test_copies_todo
test_copies_plan
test_copies_implementation_plan
test_copies_troubleshooting
test_copies_subagent_logs
test_only_copies_existing
test_snapshot_dir_naming
test_empty_snapshot_cleanup
test_marker_appended
test_marker_format
test_marker_preserves_original_content
test_readonly_todo_skips_marker
test_source_files_unmodified
test_failopen_unwritable_snapshot_dir
test_always_exits_zero
test_stdout_always_empty

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
