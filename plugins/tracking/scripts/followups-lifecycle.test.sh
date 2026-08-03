#!/bin/bash
# Tests for the followups-lifecycle contract (B04): FOLLOWUPS.md joins the
# fixed .local/ tracking-doc list across all three compaction-lifecycle legs
# — precompact-snapshot.sh (snapshot), post-compact-recovery.sh (recovery),
# and flush-nudge.sh (flush-nudge) — per the "Contract: B04 —
# followups-lifecycle (<leg> leg)" comment blocks inline in each script.
#
# Hermetic: mirrors the fixture/invocation patterns of the sibling test
# files (precompact-snapshot.test.sh, post-compact-recovery.test.sh,
# flush-nudge.test.sh) for each respective leg. This file does not re-test
# the full gate/edge-case surface already covered there — only the
# FOLLOWUPS.md clauses B04 adds on top.
#
# Run: bash plugins/tracking/scripts/followups-lifecycle.test.sh
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
# line. This deliberately excludes the inline "# Contract: B04 —
# followups-lifecycle (<leg> leg)" blocks placed mid-script above each leg's
# loop/heredoc — those already name FOLLOWUPS.md by design. What's under
# test is whether the FILE HEADER's file-enumeration prose (the "Files
# copied:"/"Files dumped:"/"Nudge text enumerates" lines near the top) was
# updated to match.
header_comment() { # script_path
    awk '/^#/{print; next} {exit}' "$1"
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

# Clause: fixture .local/ with FOLLOWUPS.md -> the snapshot dir contains it
# (copy-if-present).
test_snapshot_copies_followups() {
    local wd="$TMPROOT/snap-copies-followups"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    printf 'followup entry\n' > "$wd/.local/FOLLOWUPS.md"
    snap_run "$wd"
    local dir
    dir=$(snap_dir "$wd")
    if [ -n "$dir" ] && [ -f "$dir/FOLLOWUPS.md" ] && grep -q "followup entry" "$dir/FOLLOWUPS.md"; then
        pass "snapshot: copies FOLLOWUPS.md into snapshot dir when present"
    else
        fail "snapshot: copies FOLLOWUPS.md into snapshot dir when present" "missing or content mismatch in snapshot dir '$dir'"
    fi
}

# Clause: absent -> silent no-op (no error, nothing copied for it).
test_snapshot_followups_absent_is_noop() {
    local wd="$TMPROOT/snap-followups-absent"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\n' > "$wd/.local/TODO.md"
    # Deliberately no FOLLOWUPS.md.
    snap_run "$wd"
    if [ "$SNAP_RC" -ne 0 ]; then
        fail "snapshot: absent FOLLOWUPS.md is a silent no-op" "expected exit 0, got $SNAP_RC"
        return
    fi
    local dir
    dir=$(snap_dir "$wd")
    if [ -n "$dir" ] && [ ! -e "$dir/FOLLOWUPS.md" ]; then
        pass "snapshot: absent FOLLOWUPS.md is a silent no-op"
    else
        fail "snapshot: absent FOLLOWUPS.md is a silent no-op" "unexpected snapshot dir state: '$dir'"
    fi
}

# Clause: list order otherwise preserved -- TODO/PLAN/IMPLEMENTATION-PLAN/
# TROUBLESHOOTING are still all copied alongside FOLLOWUPS.md.
test_snapshot_list_order_preserved() {
    local wd="$TMPROOT/snap-list-order"
    mkdir -p "$wd/.local"
    printf 'todo body\n' > "$wd/.local/TODO.md"
    printf 'plan body\n' > "$wd/.local/PLAN.md"
    printf 'impl body\n' > "$wd/.local/IMPLEMENTATION-PLAN.md"
    printf 'trouble body\n' > "$wd/.local/TROUBLESHOOTING.md"
    printf 'followup body\n' > "$wd/.local/FOLLOWUPS.md"
    snap_run "$wd"
    local dir entries
    dir=$(snap_dir "$wd")
    entries=$(find "$dir" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort | tr '\n' ' ')
    if [ "$entries" = "FOLLOWUPS.md IMPLEMENTATION-PLAN.md PLAN.md TODO.md TROUBLESHOOTING.md " ]; then
        pass "snapshot: TODO/PLAN/IMPLEMENTATION-PLAN/TROUBLESHOOTING still all copied alongside FOLLOWUPS.md"
    else
        fail "snapshot: TODO/PLAN/IMPLEMENTATION-PLAN/TROUBLESHOOTING still all copied alongside FOLLOWUPS.md" "got '$entries'"
    fi
}

# Clause: the script's header comment names FOLLOWUPS.md among copied files.
test_snapshot_header_names_followups() {
    if header_comment "$SNAPSHOT_HOOK" | grep -q "FOLLOWUPS.md"; then
        pass "snapshot: header comment names FOLLOWUPS.md among copied files"
    else
        fail "snapshot: header comment names FOLLOWUPS.md among copied files" "not found in header of $SNAPSHOT_HOOK"
    fi
}

# =============================================================================
# Recovery leg (post-compact-recovery.sh)
# =============================================================================

rec_hook_json() { printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$1"; }

rec_context() { # wd -> prints additionalContext
    printf '%s' "$(rec_hook_json "$1")" | bash "$RECOVERY_HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null
}

# Clause: state dir with FOLLOWUPS.md -> output includes a
# "--- .local/FOLLOWUPS.md ---" framed dump (dump-if-present).
test_recovery_dumps_followups_content() {
    local wd="$TMPROOT/rec-dumps-followups"
    mkdir -p "$wd/.local"
    printf 'x\n' > "$wd/.local/TODO.md"
    printf 'F01 — fix the thing\n' > "$wd/.local/FOLLOWUPS.md"
    local ctx
    ctx=$(rec_context "$wd")
    if printf '%s' "$ctx" | grep -qF -- "--- .local/FOLLOWUPS.md ---" && printf '%s' "$ctx" | grep -qF "F01 — fix the thing"; then
        pass "recovery: dumps FOLLOWUPS.md content behind its own framed separator when present"
    else
        fail "recovery: dumps FOLLOWUPS.md content behind its own framed separator when present" "not found in '$ctx'"
    fi
}

# Clause: the FOLLOWUPS.md dump is framed after TROUBLESHOOTING.md's.
test_recovery_followups_after_troubleshooting() {
    local wd="$TMPROOT/rec-order"
    mkdir -p "$wd/.local"
    printf 'x\n' > "$wd/.local/TODO.md"
    printf 'trouble body\n' > "$wd/.local/TROUBLESHOOTING.md"
    printf 'followup body\n' > "$wd/.local/FOLLOWUPS.md"
    local ctx trouble_pos followups_pos
    ctx=$(rec_context "$wd")
    trouble_pos=$(printf '%s' "$ctx" | grep -n -- "--- .local/TROUBLESHOOTING.md ---" | head -1 | cut -d: -f1)
    followups_pos=$(printf '%s' "$ctx" | grep -n -- "--- .local/FOLLOWUPS.md ---" | head -1 | cut -d: -f1)
    if [ -n "$trouble_pos" ] && [ -n "$followups_pos" ] && [ "$followups_pos" -gt "$trouble_pos" ]; then
        pass "recovery: FOLLOWUPS.md separator appears after TROUBLESHOOTING.md's"
    else
        fail "recovery: FOLLOWUPS.md separator appears after TROUBLESHOOTING.md's" "trouble_pos='$trouble_pos' followups_pos='$followups_pos'"
    fi
}

# Clause: absent -> dump-if-present means no separator/content for it, no error.
test_recovery_followups_absent_is_noop() {
    local wd="$TMPROOT/rec-followups-absent"
    mkdir -p "$wd/.local"
    printf 'x\n' > "$wd/.local/TODO.md"
    local ctx
    ctx=$(rec_context "$wd")
    if printf '%s' "$ctx" | grep -qF -- "--- .local/FOLLOWUPS.md ---"; then
        fail "recovery: absent FOLLOWUPS.md produces no separator (dump-if-present)" "unexpected separator found in '$ctx'"
    else
        pass "recovery: absent FOLLOWUPS.md produces no separator (dump-if-present)"
    fi
}

# Clause: framing lines unchanged -- the pre-existing "--- .local/<file> ---"
# separators for the other docs keep their exact format when FOLLOWUPS.md is
# also present.
test_recovery_framing_lines_unchanged() {
    local wd="$TMPROOT/rec-framing"
    mkdir -p "$wd/.local"
    printf 'x\n' > "$wd/.local/TODO.md"
    printf 'plan body\n' > "$wd/.local/PLAN.md"
    printf 'followup body\n' > "$wd/.local/FOLLOWUPS.md"
    local ctx ok
    ctx=$(rec_context "$wd")
    ok=yes
    printf '%s' "$ctx" | grep -qF -- "--- .local/TODO.md ---" || ok=no
    printf '%s' "$ctx" | grep -qF -- "--- .local/PLAN.md ---" || ok=no
    if [ "$ok" = "yes" ]; then
        pass "recovery: TODO.md/PLAN.md separators keep their exact framing when FOLLOWUPS.md is also present"
    else
        fail "recovery: TODO.md/PLAN.md separators keep their exact framing when FOLLOWUPS.md is also present" "one or more separators missing/changed in '$ctx'"
    fi
}

# Clause: header comment updated to name FOLLOWUPS.md among dumped files.
test_recovery_header_names_followups() {
    if header_comment "$RECOVERY_HOOK" | grep -q "FOLLOWUPS.md"; then
        pass "recovery: header comment names FOLLOWUPS.md among dumped files"
    else
        fail "recovery: header comment names FOLLOWUPS.md among dumped files" "not found in header of $RECOVERY_HOOK"
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

# Clause: when the nudge fires, its numbered list has a 7th item naming
# .local/FOLLOWUPS.md.
test_nudge_seventh_item_names_followups() {
    nudge_fire
    if printf '%s' "$NUDGE_OUT" | grep -qF '7. `.local/FOLLOWUPS.md`'; then
        pass "flush-nudge: item 7 names .local/FOLLOWUPS.md"
    else
        fail "flush-nudge: item 7 names .local/FOLLOWUPS.md" "no matching item 7 line in: $NUDGE_OUT"
    fi
}

# Clause: item 7 carries the capture-and-verify-open-entries instruction
# (capture any follow-up mentioned but not yet recorded; verify open entries
# are still genuinely open).
test_nudge_item7_instruction_content() {
    nudge_fire
    local line ok
    line=$(printf '%s' "$NUDGE_OUT" | grep '^7\. ')
    ok=yes
    printf '%s' "$line" | grep -qi 'captur' || ok=no
    printf '%s' "$line" | grep -qi 'open' || ok=no
    if [ "$ok" = "yes" ]; then
        pass "flush-nudge: item 7 instructs to capture new follow-ups and verify open entries"
    else
        fail "flush-nudge: item 7 instructs to capture new follow-ups and verify open entries" "instruction text missing capture/open language: '$line'"
    fi
}

# Clause: numbering stays sequential (1-7, no gaps or stray items).
test_nudge_numbering_sequential() {
    nudge_fire
    local ok=yes n
    for n in 1 2 3 4 5 6 7; do
        printf '%s' "$NUDGE_OUT" | grep -qE "^${n}\. " || ok=no
    done
    if [ "$ok" = "yes" ]; then
        pass "flush-nudge: numbered list runs sequentially 1-7 with FOLLOWUPS.md added"
    else
        fail "flush-nudge: numbered list runs sequentially 1-7 with FOLLOWUPS.md added" "missing one or more sequential items in: $NUDGE_OUT"
    fi
    # The list's upper bound is not this item's concern: item 7 owns
    # only its own presence and position (checked above); the newest
    # item owns the boundary, asserted as "no item 9" in
    # workgraph-lifecycle.test.sh.
}

# Clause: the "If every doc above is already current" closing line stays
# last, after item 7.
test_nudge_closing_line_last() {
    nudge_fire
    local item7_pos closing_pos
    item7_pos=$(printf '%s' "$NUDGE_OUT" | grep -n '^7\. ' | head -1 | cut -d: -f1)
    closing_pos=$(printf '%s' "$NUDGE_OUT" | grep -n 'If every doc above is already current' | head -1 | cut -d: -f1)
    if [ -n "$item7_pos" ] && [ -n "$closing_pos" ] && [ "$closing_pos" -gt "$item7_pos" ]; then
        pass "flush-nudge: 'If every doc above is already current' line stays last, after item 7"
    else
        fail "flush-nudge: 'If every doc above is already current' line stays last, after item 7" "item7_pos='$item7_pos' closing_pos='$closing_pos'"
    fi
}

# Clause: header comment updated to name FOLLOWUPS.md among enumerated files.
test_nudge_header_names_followups() {
    if header_comment "$NUDGE_HOOK" | grep -q "FOLLOWUPS.md"; then
        pass "flush-nudge: header comment names FOLLOWUPS.md among enumerated files"
    else
        fail "flush-nudge: header comment names FOLLOWUPS.md among enumerated files" "not found in header of $NUDGE_HOOK"
    fi
}

# --- Run all tests ---
test_snapshot_copies_followups
test_snapshot_followups_absent_is_noop
test_snapshot_list_order_preserved
test_snapshot_header_names_followups

test_recovery_dumps_followups_content
test_recovery_followups_after_troubleshooting
test_recovery_followups_absent_is_noop
test_recovery_framing_lines_unchanged
test_recovery_header_names_followups

test_nudge_seventh_item_names_followups
test_nudge_item7_instruction_content
test_nudge_numbering_sequential
test_nudge_closing_line_last
test_nudge_header_names_followups

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
