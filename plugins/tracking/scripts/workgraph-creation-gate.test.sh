#!/bin/bash
# Tests for keep-working.sh's check_workgraph_creation function — the
# work-graph CREATION gate. Once per session epoch, a stop in any state that
# permits ending the turn is blocked when a decomposition artifact exists
# under .local/ (PLAN.md, blocks.md, IMPLEMENTATION-PLAN.md, or plans/*.md)
# but .local/WORKGRAPH.md does not. Creation-side sibling of the closeout
# gate covered by workgraph-gate.test.sh.
#
# Black-box: drives the WHOLE Stop hook via stdin JSON, matching
# workgraph-gate.test.sh's style. Asserts on stdout (empty = allow;
# {"decision":"block",...} = block), exit code, the
# .local/.workgraph-create-nudge-fired marker, and the $CLAUDE_STOP_LOG
# disposition.
#
# Hermetic: mktemp worktrees with a committed baseline. transcript_path is
# always "" so the freshness gate no-ops. CLAM_PR_CRONS and
# CLAM_INDEPENDENT_REVIEW stay at their disabled defaults. Fixtures that
# create .local/PLAN.md always give it a '## Block Design' section so the
# (recurring, composes-in-front) plan gate stays quiet. Every fixture writes
# .local/TODO.md directly, which also short-circuits the no-todo nudge.
#
# Run: bash plugins/tracking/scripts/workgraph-creation-gate.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/keep-working.sh"
SESSION_CONTEXT="$SCRIPT_DIR/session-context.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

IS_ROOT=0
[[ "$(id -u)" == "0" ]] && IS_ROOT=1

FAILED=0
OUT=""
EXIT=0
LOG=""
LOG_SEQ=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }

# --- Worktree / fixture builders ---------------------------------------------

make_wt() { # -> echoes path
    local wt
    wt=$(mktemp -d "$TMPROOT/wt-XXXXXX")
    mkdir -p "$wt/.local"
    git init -q "$wt" >/dev/null 2>&1
    git -C "$wt" config user.email test@example.com
    git -C "$wt" config user.name test
    printf 'baseline\n' > "$wt/baseline.txt"
    git -C "$wt" -c commit.gpgsign=false add -A >/dev/null 2>&1
    git -C "$wt" -c commit.gpgsign=false commit -q -m init >/dev/null 2>&1
    printf '%s' "$wt"
}

write_todo() { # wt state
    printf 'State: %s\nCurrent Task: doing the thing\nLast Updated: 2026-01-01 00:00\n' "$2" > "$1/.local/TODO.md"
}

# A plan that satisfies the (recurring) Block Design plan gate.
write_plan() { # wt
    printf '# Plan: test\n\n## Block Design\n\nN/A — test fixture.\n' > "$1/.local/PLAN.md"
}

write_workgraph() { # wt
    printf '# Work Graph\n\nFocus: none\n' > "$1/.local/WORKGRAPH.md"
}

marker_of() { printf '%s/.local/.workgraph-create-nudge-fired' "$1"; }

# --- Hook driver (mirrors workgraph-gate.test.sh) -----------------------------

run_raw() { # json [env assignments...]
    local json="$1"; shift
    LOG="$TMPROOT/logs/log-$((LOG_SEQ++)).jsonl"
    mkdir -p "$(dirname "$LOG")"
    OUT=$(printf '%s' "$json" | env \
        -u CLAM_TRACKING_STOP_GATE \
        -u CLAM_TRACKING_FRESHNESS_GATE \
        -u CLAM_TRACKING_FRESHNESS_THRESHOLD \
        -u CLAM_PR_CRONS \
        -u CLAM_INDEPENDENT_REVIEW \
        -u CLAM_FOLLOWUPS_GATE \
        -u CLAM_WORKGRAPH_GATE \
        CLAUDE_STOP_LOG="$LOG" \
        "$@" bash "$HOOK" 2>"$TMPROOT/stderr-last")
    EXIT=$?
}
run() { # wt [env assignments...]
    local wt="$1"; shift
    run_raw "$(jq -n --arg cwd "$wt" '{cwd:$cwd, transcript_path:"", session_id:"s1", stop_hook_active:false}')" "$@"
}

# --- Assertions ---------------------------------------------------------------

assert_allow() { # label
    if [[ -z "$OUT" ]]; then pass "$1"; else fail "$1: expected allow (empty stdout), got: $OUT"; fi
}
assert_block() { # label
    if [[ -n "$OUT" ]] && printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass "$1"
    else
        fail "$1: expected block decision JSON, got: $OUT"
    fi
}
reason_of() { printf '%s' "$OUT" | jq -r '.reason // empty' 2>/dev/null; }
assert_reason_matches() { # label regex(extended, case-insensitive)
    if printf '%s' "$(reason_of)" | grep -qiE "$2"; then
        pass "$1"
    else
        fail "$1: reason missing pattern '$2' (got: $(reason_of))"
    fi
}
assert_exit0() { if [[ "$EXIT" -eq 0 ]]; then pass "$1"; else fail "$1: exit code $EXIT"; fi; }
assert_present() { if [[ -e "$1" ]]; then pass "$2"; else fail "$2: expected present: $1"; fi; }
assert_absent()  { if [[ ! -e "$1" ]]; then pass "$2"; else fail "$2: expected absent: $1"; fi; }
assert_log_disposition() { # log expected_disposition label
    local log="$1" expected="$2" label="$3" got=""
    [[ -f "$log" ]] && got=$(jq -rs 'map(.decision) | last // empty' "$log" 2>/dev/null)
    if [[ "$got" == "$expected" ]]; then pass "$label"; else fail "$label: expected disposition '$expected', got '$got' (log: $log)"; fi
}

echo "--- Behavior: parked state + PLAN.md, no graph -> BLOCK once, reason + marker + log ---"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent"
write_plan "$wt"
run "$wt"
assert_exit0 "exit 0 on block"
assert_block "parked + PLAN.md without WORKGRAPH.md blocks"
assert_reason_matches "reason names WORKGRAPH.md" 'WORKGRAPH\.md'
assert_reason_matches "reason names the evidence artifact" 'PLAN\.md'
assert_reason_matches "reason instructs Parent edges / one root" 'Parent edge'
assert_reason_matches "reason states the once-per-epoch bound" 'once per session epoch'
assert_present "$(marker_of "$wt")" "marker written on first block"
assert_log_disposition "$LOG" "block_workgraph_missing" "log disposition is block_workgraph_missing"

echo "--- Behavior: re-stop with marker present -> ALLOW ---"
run "$wt"
assert_allow "second stop of the epoch passes through"

echo "--- Behavior: WORKGRAPH.md present -> ALLOW, no marker ---"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent"
write_plan "$wt"
write_workgraph "$wt"
run "$wt"
assert_allow "graph present: no block"
assert_absent "$(marker_of "$wt")" "graph present: marker not written"

echo "--- Behavior: no decomposition artifact -> ALLOW ---"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent"
run "$wt"
assert_allow "no plan/blocks/plans evidence: no block"
assert_absent "$(marker_of "$wt")" "no evidence: marker not written"

echo "--- Inputs: each artifact kind counts as evidence ---"
for artifact in blocks.md IMPLEMENTATION-PLAN.md; do
    wt=$(make_wt)
    write_todo "$wt" "Awaiting Agent"
    printf 'decomposition fixture\n' > "$wt/.local/$artifact"
    run "$wt"
    assert_block "evidence via .local/$artifact blocks"
done
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent"
mkdir -p "$wt/.local/plans"
printf 'plan fixture\n' > "$wt/.local/plans/001-test.md"
run "$wt"
assert_block "evidence via .local/plans/*.md blocks"
assert_reason_matches "plans/ evidence is listed by name" 'plans/001-test\.md'

echo "--- Inputs: gate disabled -> ALLOW ---"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent"
write_plan "$wt"
run "$wt" CLAM_WORKGRAPH_GATE=disabled
assert_allow "CLAM_WORKGRAPH_GATE=disabled passes through"
assert_absent "$(marker_of "$wt")" "disabled gate writes no marker"

echo "--- Invariant: In Progress never consults this gate (state blocks on its own) ---"
wt=$(make_wt)
write_todo "$wt" "In Progress"
write_plan "$wt"
run "$wt"
assert_block "In Progress still blocks (state rule)"
if printf '%s' "$(reason_of)" | grep -qiE 'WORKGRAPH\.md'; then
    fail "In Progress block reason is the state reason, not the workgraph one"
else
    pass "In Progress block reason is the state reason, not the workgraph one"
fi
assert_absent "$(marker_of "$wt")" "In Progress: creation marker not written"

echo "--- Composition: Complete + evidence, no graph -> creation gate fires (closeout no-ops on absent file) ---"
wt=$(make_wt)
write_todo "$wt" "Complete"
write_plan "$wt"
run "$wt"
assert_block "Complete + evidence without graph blocks"
assert_log_disposition "$LOG" "block_workgraph_missing" "the creation gate, not closeout, produced the block"

echo "--- Errors: unwritable marker -> fail-open ALLOW ---"
if [[ "$IS_ROOT" -eq 1 ]]; then
    pass "SKIP (root ignores permission bits): unwritable marker fail-open"
else
    wt=$(make_wt)
    write_todo "$wt" "Awaiting Agent"
    write_plan "$wt"
    chmod a-w "$wt/.local"
    run "$wt"
    chmod u+w "$wt/.local"
    assert_allow "unwritable marker: stop allowed (fail-open)"
fi

echo "--- Epoch wiring: session-context.sh clears the creation marker ---"
if grep -q '\.workgraph-create-nudge-fired' "$SESSION_CONTEXT"; then
    pass "session-context.sh clears .workgraph-create-nudge-fired each SessionStart"
else
    fail "session-context.sh does not clear .workgraph-create-nudge-fired"
fi

if [[ "$FAILED" -ne 0 ]]; then
    echo "workgraph-creation-gate.test.sh: FAILURES" >&2
    exit 1
fi
echo "workgraph-creation-gate.test.sh: all tests passed"
