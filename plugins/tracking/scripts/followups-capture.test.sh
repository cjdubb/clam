#!/bin/bash
# Tests for session-context.sh's B02 contract (followups-capture-and-surfacing):
#   (1) the injected rules gain a real-time follow-up capture instruction;
#   (2) _followups_surfacing prints an "Open follow-ups" block, wired into
#       additionalContext as printf '%s%s%s' "$rules" "$resume" "<surfacing>";
#   (3) .local/.followups-nudge-fired joins the epoch-marker clear list.
#
# See the "Contract: B02 — followups-capture-and-surfacing" docblock directly
# above _followups_surfacing() in session-context.sh for the authoritative
# spec this file verifies.
#
# Hermetic: creates a temp directory tree simulating a worktree with .local/,
# feeds synthetic hook JSON to session-context.sh, and asserts on the
# resulting hook JSON output (and, for the read-only/no-create invariants,
# on FOLLOWUPS.md's presence/content on disk).
#
# Run: bash plugins/tracking/scripts/followups-capture.test.sh
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

# Run the hook and return its exit code; raw stdout is left in REPLY.
run_hook_rc() { # cwd
    REPLY=$(printf '%s' "$(hook_json "$1")" | bash "$HOOK" 2>/dev/null)
    return $?
}

# Decode a hook JSON blob's additionalContext.
ctx_of() { # hook-json-output
    printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null
}

# assert_contains <label> <haystack> <literal-needle>
assert_contains() {
    if printf '%s' "$2" | grep -qF -- "$3"; then
        pass "$1"
    else
        fail "$1" "context did not contain: $3"
    fi
}

# assert_not_contains <label> <haystack> <literal-needle>
assert_not_contains() {
    if printf '%s' "$2" | grep -qF -- "$3"; then
        fail "$1" "context unexpectedly contained: $3"
    else
        pass "$1"
    fi
}

# assert_contains_re <label> <haystack> <ERE> (case-sensitive)
assert_contains_re() {
    if printf '%s' "$2" | grep -qE -- "$3"; then
        pass "$1"
    else
        fail "$1" "context did not match regex: $3"
    fi
}

# assert_contains_re_i <label> <haystack> <ERE> (case-insensitive)
assert_contains_re_i() {
    if printf '%s' "$2" | grep -qiE -- "$3"; then
        pass "$1"
    else
        fail "$1" "context did not match regex (case-insensitive): $3"
    fi
}

# str_index <haystack> <needle> -> byte offset of the first match, or -1.
str_index() {
    local h="$1" n="$2"
    case "$h" in
        *"$n"*)
            local before="${h%%"$n"*}"
            echo "${#before}"
            ;;
        *) echo "-1" ;;
    esac
}

# ============================================================================
# Fixtures
# ============================================================================

# Primary fixture: 5 headings, 2 open (F01, F05), 3 dispositioned
# (filed/resolved/dropped) — exercises the header count, entry listing,
# dispositioned-exclusion, and closing-line clauses together.
_write_main_fixture() { # path
    cat > "$1" <<'EOF'
# Follow-ups

One entry per follow-up, appended at mention time.

## F01 — Nudge marker naming inconsistent
- Status: open
- Captured: 2026-07-20
- Source: verifying U02
- Refs: none
- Statement: the marker filename differs from the others; worth a follow-up cleanup.

## F02 — Old defect already handled
- Status: filed CLAM-99
- Captured: 2026-07-18
- Source: code review
- Refs: none
- Statement: filed as a separate issue.

## F03 — Resolved item
- Status: resolved
- Captured: 2026-07-15
- Source: code review
- Refs: none
- Statement: fixed in a later commit.

## F04 — Dropped item
- Status: dropped (out of scope)
- Captured: 2026-07-10
- Source: code review
- Refs: none
- Statement: decided not worth doing.

## F05 — Second open item
- Status: open
- Captured: 2026-07-22
- Source: verifying U02
- Refs: none
- Statement: another thing worth tracking.
EOF
}

# ============================================================================
# Behavior (1): capture rule present in the injected rules
# ============================================================================

# Test: the rules heredoc names the load-bearing tokens the B02 contract
# requires — not incidental prose. Uses a wd with no .local/ at all, since
# the rules heredoc is unconditional (fires on any SessionStart).
test_b02_capture_rule_present_in_rules() {
    local wd="$TMPROOT/b02-rules"
    mkdir -p "$wd"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")

    assert_contains "B02 capture rule: names .local/FOLLOWUPS.md" "$ctx" ".local/FOLLOWUPS.md"
    assert_contains_re_i "B02 capture rule: instructs real-time capture" "$ctx" "real[- ]time"
    assert_contains_re_i "B02 capture rule: names first-capture (lazy creation)" "$ctx" "first capture"
    assert_contains "B02 capture rule: names the template path to create from" "$ctx" "$PLUGIN_ROOT/templates/FOLLOWUPS.md"

    local ok=no
    if printf '%s' "$ctx" | grep -qi 'filed' \
        && printf '%s' "$ctx" | grep -qi 'resolved' \
        && printf '%s' "$ctx" | grep -qi 'dropped' \
        && printf '%s' "$ctx" | grep -qiE '(rather than|never|not).{0,30}delet'; then
        ok=yes
    fi
    if [ "$ok" = yes ]; then
        pass "B02 capture rule: disposition (filed/resolved/dropped), not delete"
    else
        fail "B02 capture rule: disposition (filed/resolved/dropped), not delete" "context: $ctx"
    fi
}

# Test: the new rule is placed after the existing Open Questions rule, per
# the contract's "(1) Capture rule ... placed directly after the Open
# Questions rule" clause. Ordering-only (not strict adjacency).
test_b02_capture_rule_placed_after_open_questions() {
    local wd="$TMPROOT/b02-rule-order"
    mkdir -p "$wd"
    local ctx idx_oq idx_fu
    ctx=$(ctx_of "$(run_hook "$wd")")
    idx_oq=$(str_index "$ctx" "Open Questions")
    idx_fu=$(str_index "$ctx" ".local/FOLLOWUPS.md")
    if [ "$idx_oq" != "-1" ] && [ "$idx_fu" != "-1" ] && [ "$idx_oq" -lt "$idx_fu" ]; then
        pass "B02 capture rule: appears after the Open Questions rule"
    else
        fail "B02 capture rule: appears after the Open Questions rule" "idx_oq=$idx_oq idx_fu=$idx_fu"
    fi
}

# ============================================================================
# Behavior (2): surfacing + wiring into additionalContext
# ============================================================================

# Test: surfacing fires from FOLLOWUPS.md alone, on a fixture with no
# pre-existing TODO.md (auto-create will populate one, per B01 — that is
# independent, pre-existing behavior this test does not assert on).
test_b02_surfacing_appears_independent_of_resume() {
    local wd="$TMPROOT/b02-surfacing-standalone"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/FOLLOWUPS.md"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains "B02 surfacing: appears with no pre-existing TODO.md" "$ctx" "# Open follow-ups (2)"
}

# Test: wiring order is rules, then resume, then surfacing — per the
# contract's printf '%s%s%s' "$rules" "$resume" "<surfacing>" clause.
test_b02_wiring_order_rules_resume_surfacing() {
    local wd="$TMPROOT/b02-wiring-order"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\nCurrent Task: wiring order test\n' > "$wd/.local/TODO.md"
    _write_main_fixture "$wd/.local/FOLLOWUPS.md"
    local ctx idx_rules idx_resume idx_surfacing
    ctx=$(ctx_of "$(run_hook "$wd")")
    idx_rules=$(str_index "$ctx" "Tracking (clam tracking plugin)")
    idx_resume=$(str_index "$ctx" "Tracking document present")
    idx_surfacing=$(str_index "$ctx" "# Open follow-ups")
    if [ "$idx_rules" != "-1" ] && [ "$idx_resume" != "-1" ] && [ "$idx_surfacing" != "-1" ] \
        && [ "$idx_rules" -lt "$idx_resume" ] && [ "$idx_resume" -lt "$idx_surfacing" ]; then
        pass "B02 wiring: assembly order is rules, then resume, then surfacing"
    else
        fail "B02 wiring: assembly order is rules, then resume, then surfacing" \
            "idx_rules=$idx_rules idx_resume=$idx_resume idx_surfacing=$idx_surfacing"
    fi
}

# Test: epoch marker — .local/.followups-nudge-fired is cleared on every
# SessionStart, same scheme as the other nudge markers.
test_b02_epoch_marker_cleared() {
    local wd="$TMPROOT/b02-marker"
    mkdir -p "$wd/.local"
    touch "$wd/.local/.followups-nudge-fired"
    run_hook "$wd" >/dev/null
    if [ ! -f "$wd/.local/.followups-nudge-fired" ]; then
        pass "B02: clears .local/.followups-nudge-fired on SessionStart"
    else
        fail "B02: clears .local/.followups-nudge-fired on SessionStart" "marker still exists"
    fi
}

# ============================================================================
# Outputs
# ============================================================================

# Test: exact header format, correct N, dispositioned entries excluded, and
# open entries listed with the leading '## ' stripped.
test_output_header_and_entries() {
    local wd="$TMPROOT/output-main"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/FOLLOWUPS.md"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains_re "Outputs: exact header '# Open follow-ups (N)'" "$ctx" '^# Open follow-ups \(2\)$'
    assert_contains "Outputs: open entry heading with leading '## ' stripped (F01)" "$ctx" "F01 — Nudge marker naming inconsistent"
    assert_contains "Outputs: open entry heading with leading '## ' stripped (F05)" "$ctx" "F05 — Second open item"
    assert_not_contains "Outputs: dispositioned entry (filed) excluded from listing" "$ctx" "F02 — Old defect already handled"
    assert_not_contains "Outputs: dispositioned entry (resolved) excluded from listing" "$ctx" "F03 — Resolved item"
    assert_not_contains "Outputs: dispositioned entry (dropped) excluded from listing" "$ctx" "F04 — Dropped item"
}

# Test: (untitled) fallback when a Status: open line has no preceding
# F-heading at all.
test_output_untitled_fallback() {
    local wd="$TMPROOT/output-untitled"
    mkdir -p "$wd/.local"
    cat > "$wd/.local/FOLLOWUPS.md" <<'EOF'
- Status: open
- Captured: 2026-07-01
- Statement: an orphan entry appearing before any heading in the file.

## F01 — A Real Entry
- Status: resolved
- Captured: 2026-07-02
- Statement: dispositioned, should not appear.
EOF
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains_re "Outputs: header counts the orphan open entry" "$ctx" '^# Open follow-ups \(1\)$'
    assert_contains "Outputs: (untitled) fallback for a heading-less Status: open line" "$ctx" "(untitled)"
}

# Test: closing line instructs disposition (filed/resolved/dropped) before
# close-out, as its own identifiable line.
test_output_closing_disposition_line() {
    local wd="$TMPROOT/output-closing-line"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/FOLLOWUPS.md"
    local ctx line
    ctx=$(ctx_of "$(run_hook "$wd")")
    line=$(printf '%s\n' "$ctx" | grep -i 'disposition' | head -1)
    if [ -n "$line" ] \
        && printf '%s' "$line" | grep -qi 'filed' \
        && printf '%s' "$line" | grep -qi 'resolved' \
        && printf '%s' "$line" | grep -qi 'dropped'; then
        pass "Outputs: closing line instructs disposition (filed/resolved/dropped)"
    else
        fail "Outputs: closing line instructs disposition (filed/resolved/dropped)" "no matching line; ctx: $ctx"
    fi
}

# Test: empty output when cwd is empty.
test_output_empty_when_cwd_empty() {
    local output ctx
    output=$(printf '{"hook_event_name":"SessionStart"}' | bash "$HOOK" 2>/dev/null)
    ctx=$(ctx_of "$output")
    assert_not_contains "Outputs: empty when cwd is empty" "$ctx" "Open follow-ups"
    if printf '%s' "$output" | jq -e . >/dev/null 2>&1; then
        pass "Outputs: still emits valid JSON when cwd is empty"
    else
        fail "Outputs: still emits valid JSON when cwd is empty" "invalid JSON: $output"
    fi
}

# Test: empty output when FOLLOWUPS.md is absent.
test_output_empty_when_file_absent() {
    local wd="$TMPROOT/output-absent"
    mkdir -p "$wd/.local"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_not_contains "Outputs: empty when FOLLOWUPS.md is absent" "$ctx" "Open follow-ups"
}

# Test: empty output when the FOLLOWUPS.md path is a directory (not a
# regular file) — fail-open, not a crash.
test_output_empty_when_file_is_directory() {
    local wd="$TMPROOT/output-is-dir"
    mkdir -p "$wd/.local/FOLLOWUPS.md"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_not_contains "Outputs: empty when FOLLOWUPS.md path is a directory" "$ctx" "Open follow-ups"
}

# ============================================================================
# Errors: fail-open
# ============================================================================

# Test: zero-byte FOLLOWUPS.md -> empty output, hook still exits 0.
test_errors_zero_byte_file() {
    local wd="$TMPROOT/errors-zero-byte"
    mkdir -p "$wd/.local"
    : > "$wd/.local/FOLLOWUPS.md"
    run_hook_rc "$wd"
    local rc=$?
    check "Errors: zero-byte FOLLOWUPS.md -> hook exits 0" "$rc" "0"
    assert_not_contains "Errors: zero-byte FOLLOWUPS.md -> empty output" "$(ctx_of "$REPLY")" "Open follow-ups"
}

# Test: malformed (binary garbage) FOLLOWUPS.md -> empty output, hook exits
# 0, and the hook still emits valid JSON (not broken by the malformed file).
test_errors_malformed_binary_file() {
    local wd="$TMPROOT/errors-malformed"
    mkdir -p "$wd/.local"
    head -c 200 /dev/urandom > "$wd/.local/FOLLOWUPS.md" 2>/dev/null
    run_hook_rc "$wd"
    local rc=$?
    check "Errors: malformed FOLLOWUPS.md -> hook exits 0 (fail-open)" "$rc" "0"
    assert_not_contains "Errors: malformed FOLLOWUPS.md -> empty output" "$(ctx_of "$REPLY")" "Open follow-ups"
    if printf '%s' "$REPLY" | jq -e . >/dev/null 2>&1; then
        pass "Errors: malformed FOLLOWUPS.md -> hook still emits valid JSON"
    else
        fail "Errors: malformed FOLLOWUPS.md -> hook still emits valid JSON" "invalid JSON: $REPLY"
    fi
}

# Test: unreadable (chmod 000) FOLLOWUPS.md -> empty output. Best-effort:
# skipped (reported as a pass with a note) if the current user can still
# read a chmod 000 file (e.g. running as root).
test_errors_unreadable_file() {
    local wd="$TMPROOT/errors-unreadable"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/FOLLOWUPS.md"
    chmod 000 "$wd/.local/FOLLOWUPS.md"
    if [ -r "$wd/.local/FOLLOWUPS.md" ]; then
        pass "Errors: unreadable FOLLOWUPS.md -> empty output (skipped: current user can still read chmod 000 files)"
        chmod 644 "$wd/.local/FOLLOWUPS.md"
        return
    fi
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    chmod 644 "$wd/.local/FOLLOWUPS.md"
    assert_not_contains "Errors: unreadable FOLLOWUPS.md -> empty output" "$ctx" "Open follow-ups"
}

# ============================================================================
# Invariants
# ============================================================================

# Test: FOLLOWUPS.md content is never modified by the hook.
test_invariant_readonly_never_modifies_followups_md() {
    local wd="$TMPROOT/invariant-readonly"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/FOLLOWUPS.md"
    local before after
    before=$(cat "$wd/.local/FOLLOWUPS.md")
    run_hook "$wd" >/dev/null
    after=$(cat "$wd/.local/FOLLOWUPS.md")
    check "Invariants: FOLLOWUPS.md content unchanged after SessionStart" "$after" "$before"
}

# Test: the hook never creates FOLLOWUPS.md when it is absent (only the
# injected rule tells the agent to create it, on first capture).
test_invariant_never_creates_followups_md() {
    local wd="$TMPROOT/invariant-no-create"
    mkdir -p "$wd/.local"
    run_hook "$wd" >/dev/null
    if [ ! -f "$wd/.local/FOLLOWUPS.md" ]; then
        pass "Invariants: hook never creates FOLLOWUPS.md"
    else
        fail "Invariants: hook never creates FOLLOWUPS.md" "FOLLOWUPS.md was created"
    fi
}

# Test: pre-existing auto-create-TODO.md behavior (B01) still functions
# alongside the B02 wiring.
test_invariant_existing_auto_create_still_works() {
    local wd="$TMPROOT/invariant-autocreate"
    mkdir -p "$wd/.local"
    run_hook "$wd" >/dev/null
    if [ -f "$wd/.local/TODO.md" ]; then
        pass "Invariants: existing auto-create-TODO.md behavior unchanged"
    else
        fail "Invariants: existing auto-create-TODO.md behavior unchanged" "TODO.md was not created"
    fi
}

# Test: pre-existing resume behavior still surfaces the correct State when
# FOLLOWUPS.md is also present with open entries.
test_invariant_existing_resume_still_works() {
    local wd="$TMPROOT/invariant-resume"
    mkdir -p "$wd/.local"
    printf 'State: Blocked\nCurrent Task: waiting for deploy\n' > "$wd/.local/TODO.md"
    _write_main_fixture "$wd/.local/FOLLOWUPS.md"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains "Invariants: existing resume behavior surfaces correct State" "$ctx" "State: Blocked"
}

# ============================================================================
# Edge cases
# ============================================================================

# Test: all entries dispositioned (no open entries) -> empty output.
test_edge_all_dispositioned_empty() {
    local wd="$TMPROOT/edge-all-dispositioned"
    mkdir -p "$wd/.local"
    cat > "$wd/.local/FOLLOWUPS.md" <<'EOF'
## F01 — Filed
- Status: filed CLAM-1
- Captured: 2026-07-01
- Statement: filed elsewhere.

## F02 — Resolved
- Status: resolved
- Captured: 2026-07-02
- Statement: fixed already.

## F03 — Dropped
- Status: dropped (not needed)
- Captured: 2026-07-03
- Statement: decided against it.
EOF
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_not_contains "Edge case: all entries dispositioned -> empty output" "$ctx" "Open follow-ups"
}

# Test: open-entry count N is derived from Status lines, not from the
# heading count — a heading with no Status line at all does not add to N.
test_edge_open_count_counts_status_lines_not_headings() {
    local wd="$TMPROOT/edge-status-not-headings"
    mkdir -p "$wd/.local"
    cat > "$wd/.local/FOLLOWUPS.md" <<'EOF'
## F01 — Has Status
- Status: open
- Captured: 2026-07-01
- Statement: has an actual status line.

## F02 — No Status Line At All
- Captured: 2026-07-02
- Statement: malformed entry missing a Status line entirely.

## F03 — Also Has Status
- Status: open
- Captured: 2026-07-03
- Statement: also has a status line.
EOF
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    # 3 headings, but only 2 "- Status: open" lines.
    assert_contains_re "Edge case: N counts Status lines (2), not headings (3)" "$ctx" '^# Open follow-ups \(2\)$'
}

# --- Run all tests ---

# Behavior (1): capture rule
test_b02_capture_rule_present_in_rules
test_b02_capture_rule_placed_after_open_questions

# Behavior (2): surfacing + wiring
test_b02_surfacing_appears_independent_of_resume
test_b02_wiring_order_rules_resume_surfacing

# Behavior (3): epoch marker
test_b02_epoch_marker_cleared

# Outputs
test_output_header_and_entries
test_output_untitled_fallback
test_output_closing_disposition_line
test_output_empty_when_cwd_empty
test_output_empty_when_file_absent
test_output_empty_when_file_is_directory

# Errors
test_errors_zero_byte_file
test_errors_malformed_binary_file
test_errors_unreadable_file

# Invariants
test_invariant_readonly_never_modifies_followups_md
test_invariant_never_creates_followups_md
test_invariant_existing_auto_create_still_works
test_invariant_existing_resume_still_works

# Edge cases
test_edge_all_dispositioned_empty
test_edge_open_count_counts_status_lines_not_headings

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
