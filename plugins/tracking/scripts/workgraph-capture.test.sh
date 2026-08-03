#!/bin/bash
# Tests for session-context.sh's B03 contract (workgraph-rules-and-surfacing):
#   (1) the injected rules gain a work-graph discipline paragraph (lazy
#       creation of .local/WORKGRAPH.md, per-node Goal/Parent/Deps, real-time
#       Focus movement, Current Task citation, disposition not delete, and
#       the ASCII-tree render-on-request clause);
#   (2) _workgraph_surfacing prints a "Work graph" block, wired into
#       additionalContext as
#       printf '%s%s%s%s' "$rules" "$resume" "$followups_block" "<surfacing>";
#   (3) .local/.workgraph-nudge-fired joins the epoch-marker clear list.
#
# See the "Contract: B03 — workgraph-rules-and-surfacing" docblock directly
# above _workgraph_surfacing() in session-context.sh for the authoritative
# spec this file verifies. See also docs/protocols/work-graph.md (the
# normative artifact spec) and plugins/tracking/templates/WORKGRAPH.md (the
# instantiation template).
#
# Hermetic: creates a temp directory tree simulating a worktree with .local/,
# feeds synthetic hook JSON to session-context.sh, and asserts on the
# resulting hook JSON output (and, for the read-only/no-create invariants,
# on WORKGRAPH.md's presence/content on disk).
#
# Run: bash plugins/tracking/scripts/workgraph-capture.test.sh
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

# assert_no_line_matches_re <label> <haystack> <ERE> (case-sensitive,
# per-line anchor match; used to assert a specific standalone line is ABSENT
# without false-positiving on substrings that legitimately appear elsewhere).
assert_no_line_matches_re() {
    if printf '%s' "$2" | grep -qE -- "$3"; then
        fail "$1" "context unexpectedly matched regex: $3"
    else
        pass "$1"
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

# Primary fixture: 4 nodes, 2 open (N01, N04), Focus on N01 (open, has a
# Goal) — exercises header count+Focus id, the Focus/Goal detail lines, open
# node listing, and done/dropped exclusion together.
_write_main_fixture() { # path
    cat > "$1" <<'EOF'
# Work Graph

Focus: N01

## N01 — Set up scaffolding
- Goal: Get the harness building
- Status: open
- Parent: none
- Deps: none
- Notes: none

## N02 — Old node already done
- Goal: Ship the older piece
- Status: done
- Parent: N01
- Deps: none

## N03 — Dropped node
- Goal: Not needed after all
- Status: dropped (out of scope)
- Parent: N01
- Deps: none

## N04 — Second open item
- Goal: Wire up surfacing
- Status: open
- Parent: none
- Deps: N01
EOF
}

# A one-open-entry FOLLOWUPS.md fixture, for wiring-order tests that need all
# four assembled blocks present at once (B03 does not own this file's shape;
# only the minimum needed for _followups_surfacing to fire).
_write_followups_fixture() { # path
    cat > "$1" <<'EOF'
## F01 — Something worth tracking
- Status: open
- Captured: 2026-07-20
- Source: wiring-order test
- Refs: none
- Statement: exists only so the follow-ups block renders.
EOF
}

# ============================================================================
# Behavior (1): capture rule present in the injected rules
# ============================================================================

# Test: the rules heredoc names the load-bearing tokens the B03 contract
# requires — file name, template path, lazy creation, per-node fields,
# real-time Focus movement, Current Task citation, disposition not delete.
# Uses a wd with no .local/ at all, since the rules heredoc is unconditional
# (fires on any SessionStart).
test_b03_capture_rule_present_in_rules() {
    local wd="$TMPROOT/b03-rules"
    mkdir -p "$wd"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")

    assert_contains "B03 capture rule: names .local/WORKGRAPH.md" "$ctx" ".local/WORKGRAPH.md"
    assert_contains "B03 capture rule: names the template path to create from" "$ctx" "$PLUGIN_ROOT/templates/WORKGRAPH.md"
    assert_contains_re_i "B03 capture rule: lazy creation, never ahead of need" "$ctx" "never ahead of need"

    # These three checks combine a B03-specific anchor ("subproblem"/"Focus")
    # with the shared vocabulary word, since "moment"/"real time"/"Current
    # Task" alone already appear in the pre-existing B01/B02 rules text and
    # would pass vacuously without the anchor.
    local ok_moment=no
    if printf '%s' "$ctx" | grep -qi 'subproblem' \
        && printf '%s' "$ctx" | grep -qi 'moment'; then
        ok_moment=yes
    fi
    if [ "$ok_moment" = yes ]; then
        pass "B03 capture rule: node added at the moment it surfaces"
    else
        fail "B03 capture rule: node added at the moment it surfaces" "context: $ctx"
    fi

    local ok_focus_rt=no
    if printf '%s' "$ctx" | grep -qi 'Focus' \
        && printf '%s' "$ctx" | grep -qiE 'real[- ]time'; then
        ok_focus_rt=yes
    fi
    if [ "$ok_focus_rt" = yes ]; then
        pass "B03 capture rule: Focus pointer moves in real time"
    else
        fail "B03 capture rule: Focus pointer moves in real time" "context: $ctx"
    fi

    local ok_focus_ct=no
    if printf '%s' "$ctx" | grep -qi 'Focus' \
        && printf '%s' "$ctx" | grep -q 'Current Task'; then
        ok_focus_ct=yes
    fi
    if [ "$ok_focus_ct" = yes ]; then
        pass "B03 capture rule: cites Current Task for the Focus node"
    else
        fail "B03 capture rule: cites Current Task for the Focus node" "context: $ctx"
    fi

    local ok=no
    if printf '%s' "$ctx" | grep -qi 'Goal' \
        && printf '%s' "$ctx" | grep -qi 'Parent' \
        && printf '%s' "$ctx" | grep -qi 'Deps'; then
        ok=yes
    fi
    if [ "$ok" = yes ]; then
        pass "B03 capture rule: names per-node fields (Goal/Parent/Deps)"
    else
        fail "B03 capture rule: names per-node fields (Goal/Parent/Deps)" "context: $ctx"
    fi

    local ok2=no
    if printf '%s' "$ctx" | grep -qi 'done' \
        && printf '%s' "$ctx" | grep -qi 'dropped' \
        && printf '%s' "$ctx" | grep -qiE '(rather than|never|not).{0,30}delet'; then
        ok2=yes
    fi
    if [ "$ok2" = yes ]; then
        pass "B03 capture rule: disposition (done/dropped), not delete"
    else
        fail "B03 capture rule: disposition (done/dropped), not delete" "context: $ctx"
    fi
}

# Test: the ASCII-tree render-on-request clause — children under parents,
# [needs: N<NN>] dep annotations, status glyphs, an arrow at the Focus node,
# rendered whenever the engineer asks to see the graph.
test_b03_capture_rule_ascii_tree_clause() {
    local wd="$TMPROOT/b03-ascii-tree"
    mkdir -p "$wd"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")

    local ok=no
    if printf '%s' "$ctx" | grep -qi 'ascii' \
        && printf '%s' "$ctx" | grep -qi 'tree'; then
        ok=yes
    fi
    if [ "$ok" = yes ]; then
        pass "B03 ASCII-tree clause: names an ASCII tree render"
    else
        fail "B03 ASCII-tree clause: names an ASCII tree render" "context: $ctx"
    fi

    local ok2=no
    if printf '%s' "$ctx" | grep -qi 'child' \
        && printf '%s' "$ctx" | grep -qi 'parent'; then
        ok2=yes
    fi
    if [ "$ok2" = yes ]; then
        pass "B03 ASCII-tree clause: children nested under parents"
    else
        fail "B03 ASCII-tree clause: children nested under parents" "context: $ctx"
    fi

    assert_contains "B03 ASCII-tree clause: [needs: N<NN>] dep annotation format" "$ctx" "[needs:"
    assert_contains_re_i "B03 ASCII-tree clause: status glyph per node" "$ctx" "glyph"
    assert_contains_re_i "B03 ASCII-tree clause: arrow marks the Focus node" "$ctx" "arrow"

    local ok3=no
    if printf '%s' "$ctx" | grep -qiE 'on request|when.{0,20}ask|ask.{0,20}see|show the work graph'; then
        ok3=yes
    fi
    if [ "$ok3" = yes ]; then
        pass "B03 ASCII-tree clause: rendered on request, not proactively"
    else
        fail "B03 ASCII-tree clause: rendered on request, not proactively" "context: $ctx"
    fi
}

# Test: the new paragraph is placed after the FOLLOWUPS capture paragraph,
# per the contract's "(1) Capture rule ... placed directly after the
# FOLLOWUPS capture paragraph" clause. Ordering-only (not strict adjacency).
test_b03_capture_rule_placed_after_followups_paragraph() {
    local wd="$TMPROOT/b03-rule-order"
    mkdir -p "$wd"
    local ctx idx_fu idx_wg
    ctx=$(ctx_of "$(run_hook "$wd")")
    idx_fu=$(str_index "$ctx" ".local/FOLLOWUPS.md")
    idx_wg=$(str_index "$ctx" ".local/WORKGRAPH.md")
    if [ "$idx_fu" != "-1" ] && [ "$idx_wg" != "-1" ] && [ "$idx_fu" -lt "$idx_wg" ]; then
        pass "B03 capture rule: appears after the FOLLOWUPS capture paragraph"
    else
        fail "B03 capture rule: appears after the FOLLOWUPS capture paragraph" "idx_fu=$idx_fu idx_wg=$idx_wg"
    fi
}

# ============================================================================
# Behavior (2): surfacing + wiring into additionalContext
# ============================================================================

# Test: surfacing fires from WORKGRAPH.md alone, on a fixture with no
# pre-existing TODO.md or FOLLOWUPS.md.
test_b03_surfacing_appears_independent_of_resume_and_followups() {
    local wd="$TMPROOT/b03-surfacing-standalone"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/WORKGRAPH.md"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains "B03 surfacing: appears with no pre-existing TODO.md/FOLLOWUPS.md" "$ctx" "# Work graph (2 open node(s); Focus: N01)"
}

# Test: wiring order is rules, then resume, then follow-ups, then work
# graph — per the contract's
# printf '%s%s%s%s' "$rules" "$resume" "$followups_block" "<surfacing>" clause,
# and "the work-graph block renders after the open-follow-ups block".
test_b03_wiring_order_all_four_blocks() {
    local wd="$TMPROOT/b03-wiring-order"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\nCurrent Task: wiring order test\n' > "$wd/.local/TODO.md"
    _write_followups_fixture "$wd/.local/FOLLOWUPS.md"
    _write_main_fixture "$wd/.local/WORKGRAPH.md"
    local ctx idx_rules idx_resume idx_followups idx_workgraph
    ctx=$(ctx_of "$(run_hook "$wd")")
    idx_rules=$(str_index "$ctx" "Tracking (clam tracking plugin)")
    idx_resume=$(str_index "$ctx" "Tracking document present")
    idx_followups=$(str_index "$ctx" "# Open follow-ups")
    idx_workgraph=$(str_index "$ctx" "# Work graph")
    if [ "$idx_rules" != "-1" ] && [ "$idx_resume" != "-1" ] && [ "$idx_followups" != "-1" ] && [ "$idx_workgraph" != "-1" ] \
        && [ "$idx_rules" -lt "$idx_resume" ] && [ "$idx_resume" -lt "$idx_followups" ] && [ "$idx_followups" -lt "$idx_workgraph" ]; then
        pass "B03 wiring: assembly order is rules, then resume, then follow-ups, then work graph"
    else
        fail "B03 wiring: assembly order is rules, then resume, then follow-ups, then work graph" \
            "idx_rules=$idx_rules idx_resume=$idx_resume idx_followups=$idx_followups idx_workgraph=$idx_workgraph"
    fi
}

# ============================================================================
# Behavior (3): epoch marker
# ============================================================================

# Test: epoch marker — .local/.workgraph-nudge-fired is cleared on every
# SessionStart, same scheme as the other nudge markers.
test_b03_epoch_marker_cleared() {
    local wd="$TMPROOT/b03-marker"
    mkdir -p "$wd/.local"
    touch "$wd/.local/.workgraph-nudge-fired"
    run_hook "$wd" >/dev/null
    if [ ! -f "$wd/.local/.workgraph-nudge-fired" ]; then
        pass "B03: clears .local/.workgraph-nudge-fired on SessionStart"
    else
        fail "B03: clears .local/.workgraph-nudge-fired on SessionStart" "marker still exists"
    fi
}

# ============================================================================
# Outputs
# ============================================================================

# Test: exact header format (count + raw Focus id), the Focus detail line and
# indented Goal line, open nodes listed, done/dropped nodes excluded.
test_output_header_focus_goal_and_entries() {
    local wd="$TMPROOT/output-main"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/WORKGRAPH.md"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains_re "Outputs: exact header '# Work graph (N open node(s); Focus: <id>)'" "$ctx" '^# Work graph \(2 open node\(s\); Focus: N01\)$'
    assert_contains_re "Outputs: Focus detail line (heading text)" "$ctx" '^Focus: N01 — Set up scaffolding$'
    assert_contains_re "Outputs: indented Goal line for the Focus node" "$ctx" '^  Goal: Get the harness building$'
    assert_contains "Outputs: open node listed (N01)" "$ctx" "N01 — Set up scaffolding"
    assert_contains "Outputs: open node listed (N04)" "$ctx" "N04 — Second open item"
    assert_not_contains "Outputs: done node (N02) excluded from listing" "$ctx" "N02 — Old node already done"
    assert_not_contains "Outputs: dropped node (N03) excluded from listing" "$ctx" "N03 — Dropped node"
}

# Test: (untitled) fallback when a Status: open line has no preceding node
# heading at all.
test_output_untitled_fallback() {
    local wd="$TMPROOT/output-untitled"
    mkdir -p "$wd/.local"
    cat > "$wd/.local/WORKGRAPH.md" <<'EOF'
Focus: none

- Status: open
- Goal: An orphan entry appearing before any heading in the file.

## N01 — A Real Entry
- Goal: dispositioned, should not appear
- Status: done
- Parent: none
- Deps: none
EOF
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains_re "Outputs: header counts the orphan open node" "$ctx" '^# Work graph \(1 open node\(s\); Focus: none\)$'
    assert_contains "Outputs: (untitled) fallback for a heading-less Status: open line" "$ctx" "(untitled)"
}

# Test: Focus is "none" -> the Focus/Goal detail lines are omitted (there is
# still an open node elsewhere so the block itself renders).
test_output_focus_none_omits_focus_and_goal_lines() {
    local wd="$TMPROOT/output-focus-none"
    mkdir -p "$wd/.local"
    cat > "$wd/.local/WORKGRAPH.md" <<'EOF'
Focus: none

## N01 — Some open node
- Goal: Present but unfocused
- Status: open
- Parent: none
- Deps: none
EOF
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains_re "Outputs (Focus: none): header still reports Focus: none" "$ctx" '^# Work graph \(1 open node\(s\); Focus: none\)$'
    assert_no_line_matches_re "Outputs (Focus: none): no standalone 'Focus: <heading>' detail line" "$ctx" '^Focus: N01'
}

# Test: Focus names an id with no matching node entry (dangling pointer) ->
# the Focus/Goal detail lines are omitted, fail-open, other open nodes still
# listed. Per work-graph.md: a dangling Focus is a defect in the pointer, not
# an error condition.
test_output_focus_dangling_omits_focus_and_goal_lines() {
    local wd="$TMPROOT/output-focus-dangling"
    mkdir -p "$wd/.local"
    cat > "$wd/.local/WORKGRAPH.md" <<'EOF'
Focus: N99

## N01 — Reachable open node
- Goal: Should still be listed
- Status: open
- Parent: none
- Deps: none
EOF
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains_re "Outputs (dangling Focus): header echoes the raw dangling id" "$ctx" '^# Work graph \(1 open node\(s\); Focus: N99\)$'
    assert_no_line_matches_re "Outputs (dangling Focus): no standalone 'Focus: <heading>' detail line" "$ctx" '^Focus: N01'
    assert_contains "Outputs (dangling Focus): the reachable open node is still listed" "$ctx" "N01 — Reachable open node"
}

# Test: Focus names a node that exists but has no Goal field -> per the
# contract, BOTH the Focus and Goal detail lines are omitted together (not
# just Goal), fail-open; the open-node listing is unaffected.
test_output_focus_node_without_goal_omits_both_lines() {
    local wd="$TMPROOT/output-focus-no-goal"
    mkdir -p "$wd/.local"
    cat > "$wd/.local/WORKGRAPH.md" <<'EOF'
Focus: N01

## N01 — Node missing a Goal field
- Status: open
- Parent: none
- Deps: none

## N02 — Another open node
- Goal: Present for completeness
- Status: open
- Parent: none
- Deps: none
EOF
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains_re "Outputs (Focus node has no Goal): header still shows the Focus id" "$ctx" '^# Work graph \(2 open node\(s\); Focus: N01\)$'
    assert_no_line_matches_re "Outputs (Focus node has no Goal): no standalone Focus detail line" "$ctx" '^Focus: N01 —'
    assert_no_line_matches_re "Outputs (Focus node has no Goal): no indented Goal detail line" "$ctx" '^  Goal: '
    assert_contains "Outputs (Focus node has no Goal): open-node listing unaffected (N01)" "$ctx" "N01 — Node missing a Goal field"
    assert_contains "Outputs (Focus node has no Goal): open-node listing unaffected (N02)" "$ctx" "N02 — Another open node"
}

# Test: closing line instructs Focus/Status kept current, disposition
# (done/dropped) not delete, and ASCII-tree rendering on request — isolated
# to the surfacing block's own text (from the "# Work graph" header onward)
# so it cannot be satisfied by the earlier rules-heredoc ASCII-tree mention.
test_output_closing_line() {
    local wd="$TMPROOT/output-closing-line"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/WORKGRAPH.md"
    local ctx workgraph_part line
    ctx=$(ctx_of "$(run_hook "$wd")")
    workgraph_part=$(printf '%s\n' "$ctx" | sed -n '/^# Work graph /,$p')
    line=$(printf '%s' "$workgraph_part" | grep -i 'ascii')
    local ok=no
    if [ -n "$line" ] \
        && printf '%s' "$line" | grep -qi 'current' \
        && printf '%s' "$line" | grep -qi 'done' \
        && printf '%s' "$line" | grep -qi 'dropped' \
        && printf '%s' "$line" | grep -qiE '(rather than|never|not).{0,30}delet' \
        && printf '%s' "$line" | grep -qi 'tree'; then
        ok=yes
    fi
    if [ "$ok" = yes ]; then
        pass "Outputs: closing line instructs Focus/Status current, disposition not delete, ASCII tree on request"
    else
        fail "Outputs: closing line instructs Focus/Status current, disposition not delete, ASCII tree on request" "line: $line; workgraph_part: $workgraph_part"
    fi
}

# Test: empty output when cwd is empty.
test_output_empty_when_cwd_empty() {
    local output ctx
    output=$(printf '{"hook_event_name":"SessionStart"}' | bash "$HOOK" 2>/dev/null)
    ctx=$(ctx_of "$output")
    assert_not_contains "Outputs: empty when cwd is empty" "$ctx" "Work graph"
    if printf '%s' "$output" | jq -e . >/dev/null 2>&1; then
        pass "Outputs: still emits valid JSON when cwd is empty"
    else
        fail "Outputs: still emits valid JSON when cwd is empty" "invalid JSON: $output"
    fi
}

# Test: empty output when WORKGRAPH.md is absent.
test_output_empty_when_file_absent() {
    local wd="$TMPROOT/output-absent"
    mkdir -p "$wd/.local"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_not_contains "Outputs: empty when WORKGRAPH.md is absent" "$ctx" "Work graph"
}

# Test: empty output when the WORKGRAPH.md path is a directory (not a
# regular file) — fail-open, not a crash.
test_output_empty_when_file_is_directory() {
    local wd="$TMPROOT/output-is-dir"
    mkdir -p "$wd/.local/WORKGRAPH.md"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_not_contains "Outputs: empty when WORKGRAPH.md path is a directory" "$ctx" "Work graph"
}

# ============================================================================
# Errors: fail-open
# ============================================================================

# Test: zero-byte WORKGRAPH.md -> empty output, hook still exits 0.
test_errors_zero_byte_file() {
    local wd="$TMPROOT/errors-zero-byte"
    mkdir -p "$wd/.local"
    : > "$wd/.local/WORKGRAPH.md"
    run_hook_rc "$wd"
    local rc=$?
    check "Errors: zero-byte WORKGRAPH.md -> hook exits 0" "$rc" "0"
    assert_not_contains "Errors: zero-byte WORKGRAPH.md -> empty output" "$(ctx_of "$REPLY")" "Work graph"
}

# Test: malformed (binary garbage) WORKGRAPH.md -> empty output, hook exits
# 0, and the hook still emits valid JSON (not broken by the malformed file).
test_errors_malformed_binary_file() {
    local wd="$TMPROOT/errors-malformed"
    mkdir -p "$wd/.local"
    head -c 200 /dev/urandom > "$wd/.local/WORKGRAPH.md" 2>/dev/null
    run_hook_rc "$wd"
    local rc=$?
    check "Errors: malformed WORKGRAPH.md -> hook exits 0 (fail-open)" "$rc" "0"
    assert_not_contains "Errors: malformed WORKGRAPH.md -> empty output" "$(ctx_of "$REPLY")" "Work graph"
    if printf '%s' "$REPLY" | jq -e . >/dev/null 2>&1; then
        pass "Errors: malformed WORKGRAPH.md -> hook still emits valid JSON"
    else
        fail "Errors: malformed WORKGRAPH.md -> hook still emits valid JSON" "invalid JSON: $REPLY"
    fi
}

# Test: unreadable (chmod 000) WORKGRAPH.md -> empty output. Best-effort:
# skipped (reported as a pass with a note) if the current user can still
# read a chmod 000 file (e.g. running as root).
test_errors_unreadable_file() {
    local wd="$TMPROOT/errors-unreadable"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/WORKGRAPH.md"
    chmod 000 "$wd/.local/WORKGRAPH.md"
    if [ -r "$wd/.local/WORKGRAPH.md" ]; then
        pass "Errors: unreadable WORKGRAPH.md -> empty output (skipped: current user can still read chmod 000 files)"
        chmod 644 "$wd/.local/WORKGRAPH.md"
        return
    fi
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    chmod 644 "$wd/.local/WORKGRAPH.md"
    assert_not_contains "Errors: unreadable WORKGRAPH.md -> empty output" "$ctx" "Work graph"
}

# ============================================================================
# Invariants
# ============================================================================

# Test: WORKGRAPH.md content is never modified by the hook.
test_invariant_readonly_never_modifies_workgraph_md() {
    local wd="$TMPROOT/invariant-readonly"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/WORKGRAPH.md"
    local before after
    before=$(cat "$wd/.local/WORKGRAPH.md")
    run_hook "$wd" >/dev/null
    after=$(cat "$wd/.local/WORKGRAPH.md")
    check "Invariants: WORKGRAPH.md content unchanged after SessionStart" "$after" "$before"
}

# Test: the hook never creates WORKGRAPH.md when it is absent (only the
# injected rule tells the agent to create it, when a problem decomposes).
test_invariant_never_creates_workgraph_md() {
    local wd="$TMPROOT/invariant-no-create"
    mkdir -p "$wd/.local"
    run_hook "$wd" >/dev/null
    if [ ! -f "$wd/.local/WORKGRAPH.md" ]; then
        pass "Invariants: hook never creates WORKGRAPH.md"
    else
        fail "Invariants: hook never creates WORKGRAPH.md" "WORKGRAPH.md was created"
    fi
}

# Test: pre-existing auto-create-TODO.md behavior (B01) still functions
# alongside the B03 wiring.
test_invariant_existing_auto_create_still_works() {
    local wd="$TMPROOT/invariant-autocreate"
    mkdir -p "$wd/.local"
    _write_main_fixture "$wd/.local/WORKGRAPH.md"
    run_hook "$wd" >/dev/null
    if [ -f "$wd/.local/TODO.md" ]; then
        pass "Invariants: existing auto-create-TODO.md behavior unchanged"
    else
        fail "Invariants: existing auto-create-TODO.md behavior unchanged" "TODO.md was not created"
    fi
}

# Test: pre-existing resume behavior still surfaces the correct State when
# WORKGRAPH.md is also present with an open node.
test_invariant_existing_resume_still_works() {
    local wd="$TMPROOT/invariant-resume"
    mkdir -p "$wd/.local"
    printf 'State: Blocked\nCurrent Task: waiting for deploy\n' > "$wd/.local/TODO.md"
    _write_main_fixture "$wd/.local/WORKGRAPH.md"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains "Invariants: existing resume behavior surfaces correct State" "$ctx" "State: Blocked"
}

# Test: pre-existing follow-ups surfacing (B02) still fires unchanged when
# WORKGRAPH.md is also present.
test_invariant_existing_followups_surfacing_still_works() {
    local wd="$TMPROOT/invariant-followups"
    mkdir -p "$wd/.local"
    _write_followups_fixture "$wd/.local/FOLLOWUPS.md"
    _write_main_fixture "$wd/.local/WORKGRAPH.md"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_contains "Invariants: existing follow-ups surfacing unchanged (B02) alongside B03" "$ctx" "# Open follow-ups (1)"
}

# ============================================================================
# Edge cases
# ============================================================================

# Test: every node done/dropped -> empty output (a finished graph is not
# resurfaced).
test_edge_all_done_dropped_empty() {
    local wd="$TMPROOT/edge-all-done-dropped"
    mkdir -p "$wd/.local"
    cat > "$wd/.local/WORKGRAPH.md" <<'EOF'
Focus: N01

## N01 — Done thing
- Goal: Finished
- Status: done
- Parent: none
- Deps: none

## N02 — Dropped thing
- Goal: Not needed
- Status: dropped (not needed)
- Parent: none
- Deps: none
EOF
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_not_contains "Edge case: every node done/dropped -> empty output" "$ctx" "Work graph"
}

# Test: a freshly instantiated template (Focus: none, no real nodes — the
# template's own example entry's "Status: open | done | dropped ([reason])"
# placeholder line does not match the machine-read open marker) -> empty
# output. Uses the real template file verbatim.
test_edge_freshly_instantiated_template_empty() {
    local wd="$TMPROOT/edge-fresh-template"
    mkdir -p "$wd/.local"
    cp "$PLUGIN_ROOT/templates/WORKGRAPH.md" "$wd/.local/WORKGRAPH.md"
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    assert_not_contains "Edge case: freshly instantiated template (no real nodes) -> empty output" "$ctx" "Work graph"
}

# Test: open-node count N is derived from Status lines, not from the heading
# count — a heading with no Status line at all does not add to N.
test_edge_open_count_counts_status_lines_not_headings() {
    local wd="$TMPROOT/edge-status-not-headings"
    mkdir -p "$wd/.local"
    cat > "$wd/.local/WORKGRAPH.md" <<'EOF'
Focus: none

## N01 — Has Status
- Goal: has an actual status line
- Status: open
- Parent: none
- Deps: none

## N02 — No Status Line At All
- Goal: malformed entry missing a Status line entirely
- Parent: none
- Deps: none

## N03 — Also Has Status
- Goal: also has a status line
- Status: open
- Parent: none
- Deps: none
EOF
    local ctx
    ctx=$(ctx_of "$(run_hook "$wd")")
    # 3 headings, but only 2 "- Status: open" lines.
    assert_contains_re "Edge case: N counts Status lines (2), not headings (3)" "$ctx" '^# Work graph \(2 open node\(s\); Focus: none\)$'
}

# --- Run all tests ---

# Behavior (1): capture rule
test_b03_capture_rule_present_in_rules
test_b03_capture_rule_ascii_tree_clause
test_b03_capture_rule_placed_after_followups_paragraph

# Behavior (2): surfacing + wiring
test_b03_surfacing_appears_independent_of_resume_and_followups
test_b03_wiring_order_all_four_blocks

# Behavior (3): epoch marker
test_b03_epoch_marker_cleared

# Outputs
test_output_header_focus_goal_and_entries
test_output_untitled_fallback
test_output_focus_none_omits_focus_and_goal_lines
test_output_focus_dangling_omits_focus_and_goal_lines
test_output_focus_node_without_goal_omits_both_lines
test_output_closing_line
test_output_empty_when_cwd_empty
test_output_empty_when_file_absent
test_output_empty_when_file_is_directory

# Errors
test_errors_zero_byte_file
test_errors_malformed_binary_file
test_errors_unreadable_file

# Invariants
test_invariant_readonly_never_modifies_workgraph_md
test_invariant_never_creates_workgraph_md
test_invariant_existing_auto_create_still_works
test_invariant_existing_resume_still_works
test_invariant_existing_followups_surfacing_still_works

# Edge cases
test_edge_all_done_dropped_empty
test_edge_freshly_instantiated_template_empty
test_edge_open_count_counts_status_lines_not_headings

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
