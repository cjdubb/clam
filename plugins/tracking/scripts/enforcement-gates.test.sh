#!/bin/bash
# Tests for the round-3 enforcement additions to keep-working.sh:
#   1. Creation-gate evidence: a TODO.md Current Task citing a graph node id
#      (N<NN>) counts as decomposition evidence even with no plan artifact
#      on disk (F07 — "N01" cited, no WORKGRAPH.md, no plan yet).
#   2. check_workgraph_live_view: once per epoch, a park with WORKGRAPH.md
#      present but no "Live view:" line in TODO.md blocks with a
#      capability-phrased serve-and-record instruction (F08).
#   3. check_summons_presentation: once per epoch, a summons park (Waiting
#      For Decision / Awaiting User Review) whose TODO Status section holds
#      no URL while rendered HTML exists under .local/ blocks (F09).
#
# Black-box: drives the WHOLE Stop hook via stdin JSON, matching
# workgraph-creation-gate.test.sh's style and helpers.
#
# Run: bash plugins/tracking/scripts/enforcement-gates.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/keep-working.sh"
SESSION_CONTEXT="$SCRIPT_DIR/session-context.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

FAILED=0
OUT=""
EXIT=0
LOG=""
LOG_SEQ=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }

make_wt() {
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

write_todo() { # wt state current-task [extra-status-lines]
    {
        printf 'State: %s\nCurrent Task: %s\n' "$2" "$3"
        [[ -n "${4:-}" ]] && printf '%s\n' "$4"
        printf 'Last Updated: 2026-01-01 00:00\n'
    } > "$1/.local/TODO.md"
}

write_workgraph() { # wt
    printf '# Work Graph\n\nFocus: none\n' > "$1/.local/WORKGRAPH.md"
}

run_raw() {
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
        -u CLAM_SUMMONS_URL_GATE \
        CLAUDE_STOP_LOG="$LOG" \
        "$@" bash "$HOOK" 2>"$TMPROOT/stderr-last")
    EXIT=$?
}
run() {
    local wt="$1"; shift
    run_raw "$(jq -n --arg cwd "$wt" '{cwd:$cwd, transcript_path:"", session_id:"s1", stop_hook_active:false}')" "$@"
}

assert_allow() { if [[ -z "$OUT" ]]; then pass "$1"; else fail "$1: expected allow (empty stdout), got: $OUT"; fi; }
assert_block() {
    if [[ -n "$OUT" ]] && printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass "$1"
    else
        fail "$1: expected block decision JSON, got: $OUT"
    fi
}
reason_of() { printf '%s' "$OUT" | jq -r '.reason // empty' 2>/dev/null; }
assert_reason_matches() {
    if printf '%s' "$(reason_of)" | grep -qiE "$2"; then
        pass "$1"
    else
        fail "$1: reason missing pattern '$2' (got: $(reason_of))"
    fi
}
assert_log_disposition() {
    local log="$1" expected="$2" label="$3" got=""
    [[ -f "$log" ]] && got=$(jq -rs 'map(.decision) | last // empty' "$log" 2>/dev/null)
    if [[ "$got" == "$expected" ]]; then pass "$label"; else fail "$label: expected disposition '$expected', got '$got' (log: $log)"; fi
}

# =============================================================================
echo "--- Creation gate: Current Task citing N<NN> is evidence on its own ---"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent" "N01 — set up the thing" "Live view: none"
run "$wt"
assert_block "parked + Current Task 'N01' without WORKGRAPH.md blocks"
assert_reason_matches "reason names the cited node id" 'N01'
assert_reason_matches "reason names Current Task as the evidence" 'Current Task'
assert_log_disposition "$LOG" "block_workgraph_missing" "log disposition is block_workgraph_missing"

echo "--- Creation gate: N-like text inside a word is NOT evidence ---"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent" "reviewing PLAN1 draft" "Live view: none"
run "$wt"
assert_allow "'PLAN1' does not read as a node citation"

# =============================================================================
echo "--- Live-view nudge: graph present, no Live view line -> BLOCK once ---"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent" "doing the thing"
write_workgraph "$wt"
run "$wt"
assert_block "graph without a Live view line blocks"
assert_reason_matches "reason names WORKGRAPH.md" 'WORKGRAPH\.md'
assert_reason_matches "reason is capability-phrased (skill catalog)" 'skill catalog'
assert_reason_matches "reason gives the recorded-line anchor" 'Live view: <url>'
assert_reason_matches "reason gives the no-capability anchor" 'Live view: none'
assert_reason_matches "reason states the once-per-epoch bound" 'once per session epoch'
assert_log_disposition "$LOG" "block_live_view_missing" "log disposition is block_live_view_missing"
run "$wt"
assert_allow "second stop of the epoch passes through (marker)"
rm -f "$wt/.local/.live-view-nudge-fired"
run "$wt"
assert_block "new epoch (marker cleared) blocks again"

echo "--- Live-view nudge: recorded line satisfies it, either form ---"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent" "doing the thing" "Live view: http://127.0.0.1:1234/doc/x.md"
write_workgraph "$wt"
run "$wt"
assert_allow "Live view: <url> passes"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent" "doing the thing" "Live view: none"
write_workgraph "$wt"
run "$wt"
assert_allow "Live view: none passes"

echo "--- Live-view nudge: no graph, or gate disabled -> pass ---"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent" "doing the thing"
run "$wt"
assert_allow "no WORKGRAPH.md, no nudge"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent" "doing the thing"
write_workgraph "$wt"
run "$wt" CLAM_WORKGRAPH_GATE=disabled
assert_allow "CLAM_WORKGRAPH_GATE=disabled silences the nudge"

# =============================================================================
echo "--- Summons gate: WFD + rendered HTML + no URL in Status -> BLOCK once ---"
wt=$(make_wt)
write_todo "$wt" "Waiting For Decision" "doing the thing" "Live view: none"
printf '## Status\nState: Waiting For Decision\nCurrent Task: doing the thing\nLive view: none\nDecision Needed: approve the plan at .local/PLAN.md\nLast Updated: 2026-01-01 00:00\n' > "$wt/.local/TODO.md"
printf '<html></html>' > "$wt/.local/PLAN.html"
: > "$wt/.local/.decision-nudge-fired"
run "$wt"
assert_block "summons with rendered HTML but no URL blocks"
assert_reason_matches "reason names the summons obligation" 'summons'
assert_reason_matches "reason instructs a URL in the Status section" 'URL.{0,120}Status|Status.{0,120}URL'
assert_reason_matches "reason names the rendered evidence" 'PLAN\.html'
assert_log_disposition "$LOG" "block_summons_url_missing" "log disposition is block_summons_url_missing"
run "$wt"
assert_allow "second stop of the epoch passes through (marker)"

echo "--- Summons gate: URL present, no HTML, non-summons state, disabled -> pass ---"
wt=$(make_wt)
printf '## Status\nState: Waiting For Decision\nCurrent Task: review http://127.0.0.1:1234/doc/x.md\nLive view: none\nLast Updated: 2026-01-01 00:00\n' > "$wt/.local/TODO.md"
printf '<html></html>' > "$wt/.local/PLAN.html"
: > "$wt/.local/.decision-nudge-fired"
run "$wt"
assert_allow "URL in the Status section passes"
wt=$(make_wt)
write_todo "$wt" "Waiting For Decision" "doing the thing" "Live view: none"
: > "$wt/.local/.decision-nudge-fired"
run "$wt"
assert_allow "no rendered HTML under .local, no gate"
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent" "doing the thing" "Live view: none"
printf '<html></html>' > "$wt/.local/PLAN.html"
: > "$wt/.local/.decision-nudge-fired"
run "$wt"
assert_allow "non-summons state unaffected"
wt=$(make_wt)
write_todo "$wt" "Waiting For Decision" "doing the thing" "Live view: none"
printf '<html></html>' > "$wt/.local/PLAN.html"
: > "$wt/.local/.decision-nudge-fired"
: > "$wt/.local/.decision-nudge-fired"
run "$wt" CLAM_SUMMONS_URL_GATE=disabled
assert_allow "CLAM_SUMMONS_URL_GATE=disabled silences the gate"

# =============================================================================
echo "--- Marker clearing: session-context.sh clears both new markers ---"
if grep -q '.live-view-nudge-fired' "$SESSION_CONTEXT" && grep -q '.summons-url-nudge-fired' "$SESSION_CONTEXT"; then
    pass "both markers are in session-context.sh's epoch-clear list"
else
    fail "both markers are in session-context.sh's epoch-clear list"
fi

if [[ "$FAILED" -ne 0 ]]; then echo "enforcement-gates.test.sh: FAILURES"; exit 1; fi
echo "enforcement-gates.test.sh: all passed"
