#!/bin/bash
# Tests for keep-working.sh's check_workgraph_closeout function (B04 —
# workgraph-closeout-gate): the "Contract: B04" docblock above the function,
# plus the (not-yet-written) wiring comment that composes it into the
# Complete branch, AFTER check_followups_disposition and BEFORE
# check_independent_review. Format reference: docs/protocols/work-graph.md
# and plugins/tracking/templates/WORKGRAPH.md.
#
# Black-box: drives the WHOLE Stop hook via stdin JSON
# ({"cwd":...,"transcript_path":...,"session_id":...,"stop_hook_active":...}),
# matching followups-gate.test.sh's style (this contract composes with the
# rest of keep-working.sh's Complete-state handling, so it can't be extracted
# and eval'd in isolation). Asserts on stdout (empty = allow;
# {"decision":"block",...} = block), exit code, the
# .local/.workgraph-nudge-fired marker, and the $CLAUDE_STOP_LOG disposition.
#
# Hermetic: mktemp worktrees with a committed baseline. transcript_path is
# always passed as "" so the freshness gate (B02, composes in FRONT of the
# state case) no-ops on its very first check without needing a real
# transcript. CLAM_PR_CRONS and CLAM_INDEPENDENT_REVIEW are left unset (their
# documented defaults: disabled), so the PR-cron and independent-review
# backstops that also compose in the Complete branch stay no-ops and never
# touch gh/network. No .local/PLAN.md is ever created, so the plan gate
# (composes in front of everything) stays quiet too. Every fixture writes
# .local/TODO.md directly, which also short-circuits the no-todo nudge.
# .local/FOLLOWUPS.md is left absent except in the one composition test
# below, so check_followups_disposition (which runs immediately before this
# gate in the Complete branch) stays a quiet pass-through everywhere else.
#
# RED-WAVE NOTE: check_workgraph_closeout is a stub (always returns 0,
# "NotImplemented: B04" to stderr) and — unlike the follow-ups gate at this
# same wave — is not called from the Complete branch AT ALL yet (no call
# site exists). Every test that expects a BLOCK is therefore expected to
# FAIL against today's code (no block JSON is emitted where the contract
# demands one) — that is the correct red-for-the-right-reason failure mode
# for this wave. Tests that expect ALLOW (absent file, disabled gate, marker
# present, non-Complete states, fully-dispositioned file, malformed/zero-byte
# file, dangling/none Focus, unreadable file, unwritable marker) pass against
# today's code already, since an uncalled check is an unconditional pass.
# The follow-ups-vs-workgraph composition test also passes already: with
# check_workgraph_closeout never invoked, the already-wired follow-ups gate
# is the only thing that can block, which is exactly the outcome the
# ordering clause requires ("workgraph runs AFTER follow-ups").
#
# SCOPE LIMIT: the contract's "... BEFORE check_independent_review" ordering
# half can only be exercised end-to-end against a live gh + open PR, which is
# out of reach for a hermetic test (no network). Coverage here is the
# achievable half (workgraph runs AFTER follow-ups, proven by the composition
# test) plus, with independent-review left in its default no-op state, an
# assertion that the emitted block reason is recognizably the workgraph
# reason and NOT the independent-review or PR-cron reason text.
#
# Run: bash plugins/tracking/scripts/workgraph-gate.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/keep-working.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Unreadable-file / unwritable-marker cases are meaningless under a uid that
# ignores permission bits (mirrors followups-gate.test.sh's IS_ROOT guard).
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

# A fresh worktree with one baseline commit and a .local/ dir.
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

write_workgraph() { # wt content
    printf '%s' "$2" > "$1/.local/WORKGRAPH.md"
}

write_followups() { # wt content
    printf '%s' "$2" > "$1/.local/FOLLOWUPS.md"
}

# One OPEN node block in the documented template shape.
open_node() { # num title -> echoes block text
    printf '## N%s — %s\n- Goal: %s needs doing.\n- Status: open\n- Parent: none\n- Deps: none\n\n' "$1" "$2" "$2"
}

# One dispositioned node block ($3 is the full Status value, e.g. "done",
# "dropped (superseded)").
disposed_node() { # num title status -> echoes block text
    printf '## N%s — %s\n- Goal: %s needs doing.\n- Status: %s\n- Parent: none\n- Deps: none\n\n' "$1" "$2" "$2" "$3"
}

# One OPEN follow-up block, for the composition test only (mirrors
# followups-gate.test.sh's open_entry).
open_followup() { # num title -> echoes block text
    printf '## F%s — %s\n- Status: open\n- Captured: 2026-01-01\n- Source: test\n- Refs: none\n- Statement: %s needs follow-up.\n\n' "$1" "$2" "$2"
}

marker_of() { printf '%s/.local/.workgraph-nudge-fired' "$1"; }

checksum_of() { # path -> echoes a checksum, or ABSENT if the file is missing
    if [[ -f "$1" ]]; then cksum "$1" 2>/dev/null; else echo ABSENT; fi
}

# --- Hook driver --------------------------------------------------------------

# Runs the hook with a clean env (the freshness/PR/independent-review/gate
# tunables it reads are unset first so nothing leaks in from the surrounding
# session) and a fresh per-call $CLAUDE_STOP_LOG so the log disposition of
# THIS run can be read back unambiguously. Extra "$@" env assignments
# (CLAM_WORKGRAPH_GATE=disabled, etc.) come from the caller.
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
# transcript_path is always "" — see the file header for why that's enough
# to neutralize the freshness gate hermetically.
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
assert_reason_not_matches() { # label regex(extended, case-insensitive)
    if printf '%s' "$(reason_of)" | grep -qiE "$2"; then
        fail "$1: reason unexpectedly matches '$2' (got: $(reason_of))"
    else
        pass "$1"
    fi
}
assert_exit0() { if [[ "$EXIT" -eq 0 ]]; then pass "$1"; else fail "$1: exit code $EXIT"; fi; }
assert_present() { if [[ -e "$1" ]]; then pass "$2"; else fail "$2: expected present: $1"; fi; }
assert_absent()  { if [[ ! -e "$1" ]]; then pass "$2"; else fail "$2: expected absent: $1"; fi; }
assert_eq() { # label got expected
    if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1: expected '$3', got '$2'"; fi
}
# Reads the LAST log line's "decision" field (the disposition string log_stop
# was called with, e.g. "block_workgraph_open" — distinct from the hook's own
# stdout {"decision":"block",...} JSON) out of $1 and compares to $2.
assert_log_disposition() { # log expected_disposition label
    local log="$1" expected="$2" label="$3" got=""
    [[ -f "$log" ]] && got=$(jq -rs 'map(.decision) | last // empty' "$log" 2>/dev/null)
    if [[ "$got" == "$expected" ]]; then pass "$label"; else fail "$label: expected disposition '$expected', got '$got' (log: $log)"; fi
}

echo "--- Behavior: Complete + one open node -> BLOCK, reason + JSON + log tag ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(open_node 01 "Fix login flow")$(disposed_node 02 "Old idea" "done")"
run "$wt"
assert_block "Complete + 1 open node (default gate): BLOCK"
assert_exit0 "Complete + 1 open node: exit 0"
assert_reason_matches "block reason names the open node id (N01)" "\\bN01\\b"
assert_reason_matches "block reason includes the open node's title" "Fix login flow"
assert_reason_matches "block reason lists the 'done' disposition" "\\bdone\\b"
assert_reason_matches "block reason lists the 'dropped' disposition" "\\bdropped\\b"
assert_reason_not_matches "block reason does not surface the dispositioned node's title" "Old idea"
assert_present "$(marker_of "$wt")" "block creates the .local/.workgraph-nudge-fired marker"
assert_log_disposition "$LOG" "block_workgraph_open" "log disposition is block_workgraph_open"

echo "--- Behavior: block reason lists EACH open node, by number and title ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(open_node 01 "Fix login flow")$(open_node 02 "Improve cache eviction")$(disposed_node 03 "Retired idea" "dropped (superseded)")"
run "$wt"
assert_block "Complete + 2 open nodes: BLOCK"
assert_reason_matches "reason names N01" "\\bN01\\b"
assert_reason_matches "reason names N01's title" "Fix login flow"
assert_reason_matches "reason names N02" "\\bN02\\b"
assert_reason_matches "reason names N02's title" "Improve cache eviction"
assert_reason_not_matches "reason does not surface the dropped node's title" "Retired idea"

echo "--- Behavior: composition — workgraph runs AFTER follow-ups (ordering) ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(open_followup 01 "Fix login flow")"
write_workgraph "$wt" "$(open_node 01 "Improve cache eviction")"
run "$wt"
assert_block "Complete + open follow-up AND open node: BLOCK"
assert_reason_matches "reason is recognizably the follow-ups reason (F01)" "\\bF01\\b"
assert_reason_not_matches "reason does not surface the workgraph node (N01), proving follow-ups wins the ordering" "\\bN01\\b"
assert_log_disposition "$LOG" "block_followups_open" "both open: log disposition is block_followups_open, not block_workgraph_open"

echo "--- Behavior: open node only -> reason is not the independent-review/PR-cron text (scope limit, see header) ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(open_node 01 "Fix login flow")"
run "$wt"
assert_reason_not_matches "block reason is not the independent-review reason (ordering scope limit, see header)" "independent review"
assert_reason_not_matches "block reason is not the PR-cron reason (ordering scope limit, see header)" "monitoring cron"

echo "--- Inputs: marker already present -> pass through to today's Complete allow ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(open_node 01 "Fix login flow")"
: > "$(marker_of "$wt")"
run "$wt"
assert_allow "marker already present: allow despite open node"
assert_log_disposition "$LOG" "allow_state_complete" "marker present: falls through to today's Complete allow"

echo "--- Invariant: at most one block per epoch ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(open_node 01 "Fix login flow")"
run "$wt"
assert_block "first stop this epoch: BLOCK"
run "$wt"
assert_allow "second stop, same epoch (marker now present): allow"
assert_log_disposition "$LOG" "allow_state_complete" "second stop: falls through to today's Complete allow"

echo "--- Inputs: CLAM_WORKGRAPH_GATE explicit 'enabled' behaves like the default ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(open_node 01 "Fix login flow")"
run "$wt" CLAM_WORKGRAPH_GATE=enabled
assert_block "CLAM_WORKGRAPH_GATE=enabled: BLOCK, same as default"

echo "--- Inputs: CLAM_WORKGRAPH_GATE any non-'enabled' value disables the gate ---"

for val in disabled off nonsense; do
    wt=$(make_wt)
    write_todo "$wt" "Complete"
    write_workgraph "$wt" "$(open_node 01 "Fix login flow")"
    run "$wt" CLAM_WORKGRAPH_GATE="$val"
    assert_allow "CLAM_WORKGRAPH_GATE=$val: gate disabled, allow despite an open node"
done

echo "--- Inputs: open := '^- Status: open[[:space:]]*\$' — regex anchoring ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(printf '## N01 — Trailing whitespace\n- Goal: g\n- Status: open   \n- Parent: none\n- Deps: none\n')"
run "$wt"
assert_block "'- Status: open   ' (trailing whitespace) still counts as open"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(printf '## N01 — Not actually open\n- Goal: g\n- Status: opened\n- Parent: none\n- Deps: none\n')"
run "$wt"
assert_allow "'- Status: opened' does not match the open regex: allow"

echo "--- Inputs: dispositioned nodes ('done' / 'dropped (<reason>)') are not open ---"

for status_word in "done" "dropped (not needed)"; do
    wt=$(make_wt)
    write_todo "$wt" "Complete"
    write_workgraph "$wt" "$(disposed_node 01 "Something" "$status_word")"
    run "$wt"
    assert_allow "'- Status: $status_word' is not open: allow"
done

echo "--- Inputs: heading attribution — glued heading (no separating newline) still attributes correctly ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(printf '## N01 — First node\n- Goal: g\n- Status: done\n- Parent: none\n- Deps: none\n- Notes: ends here## N02 — Second node\n- Goal: g2\n- Status: open\n- Parent: none\n- Deps: none\n')"
run "$wt"
assert_block "glued heading: the open Status line after the glued ## N02 heading still blocks"
assert_reason_matches "glued heading: reason attributes the open node to N02" "\\bN02\\b"
assert_reason_matches "glued heading: reason includes N02's title" "Second node"
assert_reason_not_matches "glued heading: N01 (done, not glued) is not listed" "First node"

echo "--- Edge case: an open Status line with no preceding node heading lists as (untitled) ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(printf 'Focus: none\n\n- Goal: orphan\n- Status: open\n- Parent: none\n- Deps: none\n')"
run "$wt"
assert_block "open Status line with no preceding heading: still blocks"
assert_reason_matches "reason lists the orphaned node as (untitled)" "\\(untitled\\)"

echo "--- Edge case: a heading that does not match '## N<NN>' is not a node heading ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(printf '## Not a node heading\n- Goal: g\n- Status: open\n- Parent: none\n- Deps: none\n')"
run "$wt"
assert_block "open Status line under a non-N<NN> heading: still blocks"
assert_reason_matches "non-N<NN> heading: attributed as (untitled), not the bogus heading text" "\\(untitled\\)"
assert_reason_not_matches "non-N<NN> heading: the bogus heading text is not surfaced as a node title" "Not a node heading"

echo "--- Invariant: the Focus pointer is NOT checked ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(printf 'Focus: N99\n\n')$(disposed_node 01 "Done thing" "done")"
run "$wt"
assert_allow "dangling Focus (N99, no such node) with no open nodes: allow — Focus is not gated"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(printf 'Focus: none\n\n')$(open_node 01 "Fix login flow")"
run "$wt"
assert_block "Focus: none with an open node present: still BLOCK — only open nodes gate, not Focus"

echo "--- Invariant: Complete with a fully-dispositioned file behaves exactly as today ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(disposed_node 01 "Done one" "done")$(disposed_node 02 "Dropped one" "dropped (not needed)")"
run "$wt"
assert_allow "fully-dispositioned WORKGRAPH.md: allow"
assert_log_disposition "$LOG" "allow_state_complete" "fully-dispositioned: log disposition is allow_state_complete"

echo "--- Invariant: Complete with WORKGRAPH.md absent behaves exactly as today ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
run "$wt"
assert_allow "WORKGRAPH.md absent: allow"
assert_log_disposition "$LOG" "allow_state_complete" "WORKGRAPH.md absent: log disposition is allow_state_complete"

echo "--- Edge case: zero-byte / malformed WORKGRAPH.md -> pass ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" ""
run "$wt"
assert_allow "zero-byte WORKGRAPH.md: allow"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(printf 'not a real entry\njust some garbage text\n')"
run "$wt"
assert_allow "malformed WORKGRAPH.md (no Status lines at all): allow"

echo "--- Errors: fail-open on an unreadable WORKGRAPH.md ---"

if [[ "$IS_ROOT" == "0" ]]; then
    wt=$(make_wt)
    write_todo "$wt" "Complete"
    write_workgraph "$wt" "$(open_node 01 "Fix login flow")"
    chmod 000 "$wt/.local/WORKGRAPH.md"
    run "$wt"
    assert_allow "unreadable WORKGRAPH.md: fail-open allow despite an (unseeable) open node"
    assert_exit0 "unreadable WORKGRAPH.md: exit 0"
    chmod 644 "$wt/.local/WORKGRAPH.md"
else
    echo "SKIP  unreadable-file case: running as root, permission bits ignored"
fi

echo "--- Errors: fail-open on an unwritable marker ---"

if [[ "$IS_ROOT" == "0" ]]; then
    wt=$(make_wt)
    write_todo "$wt" "Complete"
    write_workgraph "$wt" "$(open_node 01 "Fix login flow")"
    chmod 555 "$wt/.local"
    run "$wt"
    assert_allow "unwritable .local/ (marker cannot be written): fail-open allow despite an open node"
    assert_exit0 "unwritable .local/: exit 0"
    chmod 755 "$wt/.local"
else
    echo "SKIP  unwritable-marker case: running as root, permission bits ignored"
fi

echo "--- Invariant: non-Complete states are unaffected, even with open nodes ---"

wt=$(make_wt)
write_todo "$wt" "Blocked"
write_workgraph "$wt" "$(open_node 01 "Fix login flow")"
run "$wt"
assert_allow "Blocked + open node: gate does not apply outside Complete"
assert_log_disposition "$LOG" "allow_state_blocked" "Blocked + open node: log disposition is allow_state_blocked"
assert_absent "$(marker_of "$wt")" "Blocked + open node: workgraph marker is never created"

wt=$(make_wt)
write_todo "$wt" "Awaiting User Review"
write_workgraph "$wt" "$(open_node 01 "Fix login flow")"
run "$wt"
assert_allow "Awaiting User Review + open node: gate does not apply outside Complete"
assert_log_disposition "$LOG" "allow_state_awaiting_user_review" "Awaiting User Review + open node: log disposition unaffected"
assert_absent "$(marker_of "$wt")" "Awaiting User Review + open node: workgraph marker is never created"

echo "--- Invariant: read-only wrt WORKGRAPH.md ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_workgraph "$wt" "$(open_node 01 "Fix login flow")"
before=$(checksum_of "$wt/.local/WORKGRAPH.md")
run "$wt"
after=$(checksum_of "$wt/.local/WORKGRAPH.md")
assert_eq "WORKGRAPH.md is left byte-for-byte untouched (read-only invariant)" "$after" "$before"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "ALL PASS"
else
    echo "FAILURES"
fi
exit "$FAILED"
