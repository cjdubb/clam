#!/bin/bash
# Tests for the workgraph-lifecycle contract (B05, plan 001-tracking-work-graph):
# WORKGRAPH.md joins the fixed .local/ tracking-doc list across all three
# compaction-lifecycle legs — precompact-snapshot.sh (snapshot),
# post-compact-recovery.sh (recovery), and flush-nudge.sh (flush-nudge) — per
# the "Contract: B05 — workgraph-lifecycle (<leg> leg, plan
# 001-tracking-work-graph)" comment blocks inline in each script. Note:
# flush-nudge.sh also carries an unrelated "Contract: B05 —
# flush-nudge-default-window" block from a different plan; that block is out
# of scope here and is not exercised by this file.
#
# Hermetic: mirrors the fixture/invocation patterns of the sibling test files
# (precompact-snapshot.test.sh, post-compact-recovery.test.sh,
# flush-nudge.test.sh) for each respective leg, and the analogous
# followups-lifecycle.test.sh (B04) for the cross-script harness shape. This
# file does not re-test the full gate/edge-case surface already covered
# there — only the WORKGRAPH.md clauses B05 adds on top.
#
# Run: bash plugins/tracking/scripts/workgraph-lifecycle.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_HOOK="$SCRIPT_DIR/precompact-snapshot.sh"
RECOVERY_HOOK="$SCRIPT_DIR/post-compact-recovery.sh"
NUDGE_HOOK="$SCRIPT_DIR/flush-nudge.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }

# Prints a script's top-of-file doc-comment header: the contiguous run of
# '#'-prefixed lines starting at line 1, stopping at the first non-comment
# line. This deliberately excludes the inline "# Contract: B05 —
# workgraph-lifecycle (<leg> leg, ...)" blocks placed mid-script above each
# leg's loop/heredoc — those already name WORKGRAPH.md by design. What's
# under test is whether the FILE HEADER's file-enumeration prose (the "Files
# copied:"/"Files dumped:"/"Nudge text enumerates" lines near the top) was
# updated to match.
header_comment() { # script_path
    awk '/^#/{print; next} {exit}' "$1"
}

# Position (1-based line number) of the first line in a header comment
# containing a given literal string, or empty if not found.
header_pos() { # script_path needle
    header_comment "$1" | grep -n -F "$2" | head -1 | cut -d: -f1
}

# =============================================================================
# Snapshot leg (precompact-snapshot.sh)
# =============================================================================

snap_hook_json() { printf '{"cwd":"%s","hook_event_name":"PreCompact","trigger":"auto","session_id":"test-sid"}' "$1"; }

snap_run() { # wd -> sets SNAP_RC
    printf '%s' "$(snap_hook_json "$1")" | bash "$SNAPSHOT_HOOK" >/dev/null 2>&1
    SNAP_RC=$?
}

snap_dir() { find "$1/.local/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null; }

# Clause: fixture .local/ with WORKGRAPH.md -> the snapshot dir contains it
# (copy-if-present semantics unchanged).
test_snapshot_copies_workgraph() {
    local wd="$TMPROOT/snap-copies-workgraph"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    printf 'Focus: none\n\n## N01 — test node\n- Status: open\n' > "$wd/.local/WORKGRAPH.md"
    snap_run "$wd"
    local dir
    dir=$(snap_dir "$wd")
    if [ -n "$dir" ] && [ -f "$dir/WORKGRAPH.md" ] && grep -q "N01 — test node" "$dir/WORKGRAPH.md"; then
        pass "snapshot: copies WORKGRAPH.md into snapshot dir when present"
    else
        fail "snapshot: copies WORKGRAPH.md into snapshot dir when present" "missing or content mismatch in snapshot dir '$dir'"
    fi
}

# Clause: absent -> silent no-op (no error, nothing copied for it).
test_snapshot_workgraph_absent_is_noop() {
    local wd="$TMPROOT/snap-workgraph-absent"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    # Deliberately no WORKGRAPH.md.
    snap_run "$wd"
    if [ "$SNAP_RC" -ne 0 ]; then
        fail "snapshot: absent WORKGRAPH.md is a silent no-op" "expected exit 0, got $SNAP_RC"
        return
    fi
    local dir
    dir=$(snap_dir "$wd")
    if [ -n "$dir" ] && [ ! -e "$dir/WORKGRAPH.md" ]; then
        pass "snapshot: absent WORKGRAPH.md is a silent no-op"
    else
        fail "snapshot: absent WORKGRAPH.md is a silent no-op" "unexpected snapshot dir state: '$dir'"
    fi
}

# Clause: list order otherwise preserved -- TODO/PLAN/IMPLEMENTATION-PLAN/
# TROUBLESHOOTING/FOLLOWUPS are still all copied alongside WORKGRAPH.md.
test_snapshot_list_order_preserved() {
    local wd="$TMPROOT/snap-list-order"
    mkdir -p "$wd/.local"
    printf 'todo body\n' > "$wd/.local/TODO.md"
    printf 'plan body\n' > "$wd/.local/PLAN.md"
    printf 'impl body\n' > "$wd/.local/IMPLEMENTATION-PLAN.md"
    printf 'trouble body\n' > "$wd/.local/TROUBLESHOOTING.md"
    printf 'followup body\n' > "$wd/.local/FOLLOWUPS.md"
    printf 'Focus: none\n' > "$wd/.local/WORKGRAPH.md"
    snap_run "$wd"
    local dir entries
    dir=$(snap_dir "$wd")
    entries=$(find "$dir" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | sed 's#.*/##' | sort | tr '\n' ' ')
    if [ "$entries" = "FOLLOWUPS.md IMPLEMENTATION-PLAN.md PLAN.md TODO.md TROUBLESHOOTING.md WORKGRAPH.md " ]; then
        pass "snapshot: TODO/PLAN/IMPLEMENTATION-PLAN/TROUBLESHOOTING/FOLLOWUPS still all copied alongside WORKGRAPH.md"
    else
        fail "snapshot: TODO/PLAN/IMPLEMENTATION-PLAN/TROUBLESHOOTING/FOLLOWUPS still all copied alongside WORKGRAPH.md" "got '$entries'"
    fi
}

# Clause: the script's header comment names WORKGRAPH.md among copied files.
test_snapshot_header_names_workgraph() {
    if header_comment "$SNAPSHOT_HOOK" | grep -q "WORKGRAPH.md"; then
        pass "snapshot: header comment names WORKGRAPH.md among copied files"
    else
        fail "snapshot: header comment names WORKGRAPH.md among copied files" "not found in header of $SNAPSHOT_HOOK"
    fi
}

# Clause: WORKGRAPH.md is appended after FOLLOWUPS.md -- the header's
# file-enumeration prose reflects that ordering too.
test_snapshot_header_workgraph_after_followups() {
    local followups_pos workgraph_pos
    followups_pos=$(header_pos "$SNAPSHOT_HOOK" "FOLLOWUPS.md")
    workgraph_pos=$(header_pos "$SNAPSHOT_HOOK" "WORKGRAPH.md")
    if [ -n "$followups_pos" ] && [ -n "$workgraph_pos" ] && [ "$workgraph_pos" -ge "$followups_pos" ]; then
        pass "snapshot: header names WORKGRAPH.md at or after FOLLOWUPS.md"
    else
        fail "snapshot: header names WORKGRAPH.md at or after FOLLOWUPS.md" "followups_pos='$followups_pos' workgraph_pos='$workgraph_pos'"
    fi
}

# =============================================================================
# Recovery leg (post-compact-recovery.sh)
# =============================================================================

rec_hook_json() { printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$1"; }

rec_context() { # wd -> prints additionalContext
    printf '%s' "$(rec_hook_json "$1")" | bash "$RECOVERY_HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null
}

# Clause: state dir with WORKGRAPH.md -> output includes a
# "--- .local/WORKGRAPH.md ---" framed dump (dump-if-present).
test_recovery_dumps_workgraph_content() {
    local wd="$TMPROOT/rec-dumps-workgraph"
    mkdir -p "$wd/.local"
    printf 'x\n' > "$wd/.local/TODO.md"
    printf 'Focus: N01\n\n## N01 — build the graph\n- Status: open\n' > "$wd/.local/WORKGRAPH.md"
    local ctx
    ctx=$(rec_context "$wd")
    if printf '%s' "$ctx" | grep -qF -- "--- .local/WORKGRAPH.md ---" && printf '%s' "$ctx" | grep -qF "N01 — build the graph"; then
        pass "recovery: dumps WORKGRAPH.md content behind its own framed separator when present"
    else
        fail "recovery: dumps WORKGRAPH.md content behind its own framed separator when present" "not found in '$ctx'"
    fi
}

# Clause: the WORKGRAPH.md dump is framed after FOLLOWUPS.md's.
test_recovery_workgraph_after_followups() {
    local wd="$TMPROOT/rec-order"
    mkdir -p "$wd/.local"
    printf 'x\n' > "$wd/.local/TODO.md"
    printf 'followup body\n' > "$wd/.local/FOLLOWUPS.md"
    printf 'Focus: none\n' > "$wd/.local/WORKGRAPH.md"
    local ctx followups_pos workgraph_pos
    ctx=$(rec_context "$wd")
    followups_pos=$(printf '%s' "$ctx" | grep -n -- "--- .local/FOLLOWUPS.md ---" | head -1 | cut -d: -f1)
    workgraph_pos=$(printf '%s' "$ctx" | grep -n -- "--- .local/WORKGRAPH.md ---" | head -1 | cut -d: -f1)
    if [ -n "$followups_pos" ] && [ -n "$workgraph_pos" ] && [ "$workgraph_pos" -gt "$followups_pos" ]; then
        pass "recovery: WORKGRAPH.md separator appears after FOLLOWUPS.md's"
    else
        fail "recovery: WORKGRAPH.md separator appears after FOLLOWUPS.md's" "followups_pos='$followups_pos' workgraph_pos='$workgraph_pos'"
    fi
}

# Clause: absent -> dump-if-present means no separator/content for it, no error.
test_recovery_workgraph_absent_is_noop() {
    local wd="$TMPROOT/rec-workgraph-absent"
    mkdir -p "$wd/.local"
    printf 'x\n' > "$wd/.local/TODO.md"
    local ctx
    ctx=$(rec_context "$wd")
    if printf '%s' "$ctx" | grep -qF -- "--- .local/WORKGRAPH.md ---"; then
        fail "recovery: absent WORKGRAPH.md produces no separator (dump-if-present)" "unexpected separator found in '$ctx'"
    else
        pass "recovery: absent WORKGRAPH.md produces no separator (dump-if-present)"
    fi
}

# Clause: framing lines unchanged -- the pre-existing "--- .local/<file> ---"
# separators for the other docs (including FOLLOWUPS.md) keep their exact
# format when WORKGRAPH.md is also present.
test_recovery_framing_lines_unchanged() {
    local wd="$TMPROOT/rec-framing"
    mkdir -p "$wd/.local"
    printf 'x\n' > "$wd/.local/TODO.md"
    printf 'plan body\n' > "$wd/.local/PLAN.md"
    printf 'followup body\n' > "$wd/.local/FOLLOWUPS.md"
    printf 'Focus: none\n' > "$wd/.local/WORKGRAPH.md"
    local ctx ok
    ctx=$(rec_context "$wd")
    ok=yes
    printf '%s' "$ctx" | grep -qF -- "--- .local/TODO.md ---" || ok=no
    printf '%s' "$ctx" | grep -qF -- "--- .local/PLAN.md ---" || ok=no
    printf '%s' "$ctx" | grep -qF -- "--- .local/FOLLOWUPS.md ---" || ok=no
    if [ "$ok" = "yes" ]; then
        pass "recovery: TODO.md/PLAN.md/FOLLOWUPS.md separators keep their exact framing when WORKGRAPH.md is also present"
    else
        fail "recovery: TODO.md/PLAN.md/FOLLOWUPS.md separators keep their exact framing when WORKGRAPH.md is also present" "one or more separators missing/changed in '$ctx'"
    fi
}

# Clause: header comment updated to name WORKGRAPH.md among dumped files.
test_recovery_header_names_workgraph() {
    if header_comment "$RECOVERY_HOOK" | grep -q "WORKGRAPH.md"; then
        pass "recovery: header comment names WORKGRAPH.md among dumped files"
    else
        fail "recovery: header comment names WORKGRAPH.md among dumped files" "not found in header of $RECOVERY_HOOK"
    fi
}

# Clause: WORKGRAPH.md is appended after FOLLOWUPS.md -- the header's
# file-enumeration prose reflects that ordering too.
test_recovery_header_workgraph_after_followups() {
    local followups_pos workgraph_pos
    followups_pos=$(header_pos "$RECOVERY_HOOK" "FOLLOWUPS.md")
    workgraph_pos=$(header_pos "$RECOVERY_HOOK" "WORKGRAPH.md")
    if [ -n "$followups_pos" ] && [ -n "$workgraph_pos" ] && [ "$workgraph_pos" -ge "$followups_pos" ]; then
        pass "recovery: header names WORKGRAPH.md at or after FOLLOWUPS.md"
    else
        fail "recovery: header names WORKGRAPH.md at or after FOLLOWUPS.md" "followups_pos='$followups_pos' workgraph_pos='$workgraph_pos'"
    fi
}

# =============================================================================
# Flush-nudge leg (flush-nudge.sh)
# =============================================================================

NUDGE_WT="$TMPROOT/nudge-wt"
mkdir -p "$NUDGE_WT/.local"
NUDGE_TRANSCRIPT="$TMPROOT/nudge-transcript.jsonl"
NUDGE_HOME_NO_SETTINGS="$TMPROOT/nudge-home-no-settings"
mkdir -p "$NUDGE_HOME_NO_SETTINGS"

nudge_set_fill() { printf '{"type":"assistant","message":{"usage":{"input_tokens":%s}}}\n' "$1" > "$NUDGE_TRANSCRIPT"; }
nudge_reset_markers() { rm -f "$NUDGE_WT/.local/.flush-nudge-fired" "$NUDGE_WT/.local/.flush-nudge-skip-next"; }
nudge_touch_todo() { : > "$NUDGE_WT/.local/TODO.md"; }

# Drives the hook into its firing path (fill well above threshold, window
# explicitly configured) and captures stdout in $NUDGE_OUT. A clean explicit
# environment mirrors flush-nudge.test.sh's run_raw so nothing from the
# surrounding session/machine leaks in.
nudge_fire() { # -> sets NUDGE_OUT
    nudge_touch_todo
    nudge_reset_markers
    nudge_set_fill 200000
    NUDGE_OUT=$(printf '%s' "$(jq -n --arg cwd "$NUDGE_WT" --arg tp "$NUDGE_TRANSCRIPT" '{cwd:$cwd, transcript_path:$tp}')" \
        | env -u CLAM_TRACKING_FLUSH_GATE -u CLAM_FLUSH_CONTEXT_WINDOW -u CLAM_FLUSH_NUDGE_THRESHOLD \
            HOME="$NUDGE_HOME_NO_SETTINGS" CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 \
            bash "$NUDGE_HOOK" 2>/dev/null)
}

# Clause: when the nudge fires, its numbered list has an 8th item naming
# .local/WORKGRAPH.md.
test_nudge_eighth_item_names_workgraph() {
    nudge_fire
    if printf '%s' "$NUDGE_OUT" | grep -qF '8. `.local/WORKGRAPH.md`'; then
        pass "flush-nudge: item 8 names .local/WORKGRAPH.md"
    else
        fail "flush-nudge: item 8 names .local/WORKGRAPH.md" "no matching item 8 line in: $NUDGE_OUT"
    fi
}

# Clause: item 8 carries the add-node / verify-Focus / disposition-resolved
# instruction (add any subproblem surfaced but not yet recorded as a node;
# verify the Focus: pointer names the node actually being worked; disposition
# any node resolved in-conversation).
test_nudge_item8_instruction_content() {
    nudge_fire
    local line ok
    line=$(printf '%s' "$NUDGE_OUT" | grep '^8\. ')
    ok=yes
    printf '%s' "$line" | grep -qi 'node' || ok=no
    printf '%s' "$line" | grep -qi 'focus' || ok=no
    printf '%s' "$line" | grep -qi 'dropped' || ok=no
    if [ "$ok" = "yes" ]; then
        pass "flush-nudge: item 8 instructs to add nodes, verify Focus, and disposition resolved nodes"
    else
        fail "flush-nudge: item 8 instructs to add nodes, verify Focus, and disposition resolved nodes" "instruction text missing node/Focus/dropped language: '$line'"
    fi
}

# Clause: numbering stays sequential (1-8, no gaps or stray items).
test_nudge_numbering_sequential() {
    nudge_fire
    local ok=yes n
    for n in 1 2 3 4 5 6 7 8; do
        printf '%s' "$NUDGE_OUT" | grep -qE "^${n}\. " || ok=no
    done
    if [ "$ok" = "yes" ]; then
        pass "flush-nudge: numbered list runs sequentially 1-8 with WORKGRAPH.md added"
    else
        fail "flush-nudge: numbered list runs sequentially 1-8 with WORKGRAPH.md added" "missing one or more sequential items in: $NUDGE_OUT"
    fi
    if printf '%s' "$NUDGE_OUT" | grep -qE '^9\. '; then
        fail "flush-nudge: list has exactly 8 items (no item 9)" "unexpected item 9 found"
    else
        pass "flush-nudge: list has exactly 8 items (no item 9)"
    fi
}

# Clause: the "If every doc above is already current" closing line stays
# last, after item 8.
test_nudge_closing_line_last() {
    nudge_fire
    local item8_pos closing_pos
    item8_pos=$(printf '%s' "$NUDGE_OUT" | grep -n '^8\. ' | head -1 | cut -d: -f1)
    closing_pos=$(printf '%s' "$NUDGE_OUT" | grep -n 'If every doc above is already current' | head -1 | cut -d: -f1)
    if [ -n "$item8_pos" ] && [ -n "$closing_pos" ] && [ "$closing_pos" -gt "$item8_pos" ]; then
        pass "flush-nudge: 'If every doc above is already current' line stays last, after item 8"
    else
        fail "flush-nudge: 'If every doc above is already current' line stays last, after item 8" "item8_pos='$item8_pos' closing_pos='$closing_pos'"
    fi
}

# Clause: header comment updated to name WORKGRAPH.md among enumerated files.
test_nudge_header_names_workgraph() {
    if header_comment "$NUDGE_HOOK" | grep -q "WORKGRAPH.md"; then
        pass "flush-nudge: header comment names WORKGRAPH.md among enumerated files"
    else
        fail "flush-nudge: header comment names WORKGRAPH.md among enumerated files" "not found in header of $NUDGE_HOOK"
    fi
}

# Clause: WORKGRAPH.md is appended after FOLLOWUPS.md -- the header's
# file-enumeration prose reflects that ordering too.
test_nudge_header_workgraph_after_followups() {
    local followups_pos workgraph_pos
    followups_pos=$(header_pos "$NUDGE_HOOK" "FOLLOWUPS.md")
    workgraph_pos=$(header_pos "$NUDGE_HOOK" "WORKGRAPH.md")
    if [ -n "$followups_pos" ] && [ -n "$workgraph_pos" ] && [ "$workgraph_pos" -ge "$followups_pos" ]; then
        pass "flush-nudge: header names WORKGRAPH.md at or after FOLLOWUPS.md"
    else
        fail "flush-nudge: header names WORKGRAPH.md at or after FOLLOWUPS.md" "followups_pos='$followups_pos' workgraph_pos='$workgraph_pos'"
    fi
}

# --- Run all tests ---
test_snapshot_copies_workgraph
test_snapshot_workgraph_absent_is_noop
test_snapshot_list_order_preserved
test_snapshot_header_names_workgraph
test_snapshot_header_workgraph_after_followups

test_recovery_dumps_workgraph_content
test_recovery_workgraph_after_followups
test_recovery_workgraph_absent_is_noop
test_recovery_framing_lines_unchanged
test_recovery_header_names_workgraph
test_recovery_header_workgraph_after_followups

test_nudge_eighth_item_names_workgraph
test_nudge_item8_instruction_content
test_nudge_numbering_sequential
test_nudge_closing_line_last
test_nudge_header_names_workgraph
test_nudge_header_workgraph_after_followups

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
