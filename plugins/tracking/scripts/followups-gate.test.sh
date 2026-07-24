#!/bin/bash
# Tests for keep-working.sh's check_followups_disposition function (B03 —
# followups-closeout-gate): the "Contract: B03" docblock above the function,
# plus the (not-yet-written) wiring comment that composes it into the
# Complete branch, FIRST, ahead of check_independent_review.
#
# Black-box: drives the WHOLE Stop hook via stdin JSON
# ({"cwd":...,"transcript_path":...,"session_id":...,"stop_hook_active":...}),
# matching freshness-gate.test.sh's style (this contract composes with the
# rest of keep-working.sh's Complete-state handling, so it can't be extracted
# and eval'd in isolation the way no-todo-nudge.test.sh does). Asserts on
# stdout (empty = allow; {"decision":"block",...} = block), exit code, the
# .local/.followups-nudge-fired marker, and the $CLAUDE_STOP_LOG disposition.
#
# Hermetic: mktemp worktrees with a committed baseline. transcript_path is
# always passed as "" so the freshness gate (B02, composes in FRONT of the
# state case) no-ops on its very first check (`[[ -n "$transcript_path" && -f
# "$transcript_path" ]] || return 0`) without needing a real transcript.
# CLAM_PR_CRONS and CLAM_INDEPENDENT_REVIEW are left unset (their documented
# defaults: disabled), per the brief, so the PR-cron and independent-review
# backstops that also compose in the Complete branch stay no-ops and never
# touch gh/network. No .local/PLAN.md is ever created, so the plan gate
# (composes in front of everything) stays quiet too. Every fixture writes
# .local/TODO.md directly, which also short-circuits the no-todo nudge.
#
# RED-WAVE NOTE: check_followups_disposition is a stub (always returns 0,
# "NotImplemented" to stderr) and is not yet wired into the Complete branch
# at all. Every test that expects a BLOCK is therefore expected to FAIL
# against today's code (no block JSON is emitted where the contract demands
# one) — that is the correct red-for-the-right-reason failure mode for this
# wave. Tests that expect ALLOW (absent file, disabled gate, marker present,
# non-Complete states, fully-dispositioned file, malformed/zero-byte file)
# pass against the stub already, since Complete's unwired behavior today is
# unconditional allow whenever the PR-cron/independent-review backstops are
# no-ops (true throughout this file). A few "reason does NOT match" assertions
# also trivially pass pre-implementation (empty stdout matches no pattern);
# they gain teeth once the gate is wired and gain a real reason string.
#
# SCOPE LIMIT: the contract's "runs FIRST in the Complete branch, before
# check_independent_review" ordering clause can only be exercised end-to-end
# against a live gh + open PR, which is out of reach for a hermetic test (no
# network). Coverage here is the achievable half: with both other backstops
# left in their default no-op state, the emitted block reason is asserted to
# be recognizably the follow-ups reason and NOT the independent-review or
# PR-cron reason text.
#
# Run: bash plugins/tracking/scripts/followups-gate.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/keep-working.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Unreadable-file / unwritable-marker cases are meaningless under a uid that
# ignores permission bits (mirrors freshness-gate.test.sh's IS_ROOT guard).
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

write_followups() { # wt content
    printf '%s' "$2" > "$1/.local/FOLLOWUPS.md"
}

# One OPEN entry block in the documented template shape.
open_entry() { # num title -> echoes block text
    printf '## F%s — %s\n- Status: open\n- Captured: 2026-01-01\n- Source: test\n- Refs: none\n- Statement: %s needs follow-up.\n\n' "$1" "$2" "$2"
}

# One dispositioned entry block ($3 is the full Status value, e.g.
# "filed #42", "resolved", "dropped (not needed)").
disposed_entry() { # num title status -> echoes block text
    printf '## F%s — %s\n- Status: %s\n- Captured: 2026-01-01\n- Source: test\n- Refs: none\n- Statement: %s.\n\n' "$1" "$2" "$3" "$2"
}

marker_of() { printf '%s/.local/.followups-nudge-fired' "$1"; }

checksum_of() { # path -> echoes a checksum, or ABSENT if the file is missing
    if [[ -f "$1" ]]; then cksum "$1" 2>/dev/null; else echo ABSENT; fi
}

# --- Hook driver --------------------------------------------------------------

# Runs the hook with a clean env (the freshness/PR/independent-review/gate
# tunables it reads are unset first so nothing leaks in from the surrounding
# session) and a fresh per-call $CLAUDE_STOP_LOG so the log disposition of
# THIS run can be read back unambiguously. Extra "$@" env assignments
# (CLAM_FOLLOWUPS_GATE=disabled, etc.) come from the caller.
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
# was called with, e.g. "block_followups_open" — distinct from the hook's own
# stdout {"decision":"block",...} JSON) out of $1 and compares to $2.
assert_log_disposition() { # log expected_disposition label
    local log="$1" expected="$2" label="$3" got=""
    [[ -f "$log" ]] && got=$(jq -rs 'map(.decision) | last // empty' "$log" 2>/dev/null)
    if [[ "$got" == "$expected" ]]; then pass "$label"; else fail "$label: expected disposition '$expected', got '$got' (log: $log)"; fi
}

echo "--- Behavior: Complete + one open follow-up -> BLOCK, reason + JSON + log tag ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(open_entry 01 "Fix login flow")$(disposed_entry 02 "Old idea" "resolved")"
run "$wt"
assert_block "Complete + 1 open follow-up (default gate): BLOCK"
assert_exit0 "Complete + 1 open follow-up: exit 0"
assert_reason_matches "block reason names the open entry number (F01)" "\\bF01\\b"
assert_reason_matches "block reason includes the open entry's title" "Fix login flow"
assert_reason_matches "block reason lists the 'filed' disposition" "filed"
assert_reason_matches "block reason lists the 'resolved' disposition" "resolved"
assert_reason_matches "block reason lists the 'dropped' disposition" "dropped"
assert_reason_not_matches "block reason does not surface the dispositioned entry's title" "Old idea"
assert_reason_not_matches "block reason is not the independent-review reason (ordering scope limit, see header)" "independent review"
assert_reason_not_matches "block reason is not the PR-cron reason (ordering scope limit, see header)" "monitoring cron"
assert_present "$(marker_of "$wt")" "block creates the .local/.followups-nudge-fired marker"
assert_log_disposition "$LOG" "block_followups_open" "log disposition is block_followups_open"

echo "--- Behavior: block reason lists EACH open entry, by number and title ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(open_entry 01 "Fix login flow")$(open_entry 02 "Improve cache eviction")$(disposed_entry 03 "Retired idea" "dropped (superseded)")"
run "$wt"
assert_block "Complete + 2 open follow-ups: BLOCK"
assert_reason_matches "reason names F01" "\\bF01\\b"
assert_reason_matches "reason names F01's title" "Fix login flow"
assert_reason_matches "reason names F02" "\\bF02\\b"
assert_reason_matches "reason names F02's title" "Improve cache eviction"
assert_reason_not_matches "reason does not surface the dropped entry's title" "Retired idea"

echo "--- Inputs: marker already present -> pass through to today's Complete allow ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(open_entry 01 "Fix login flow")"
: > "$(marker_of "$wt")"
run "$wt"
assert_allow "marker already present: allow despite open follow-ups (once-per-epoch)"
assert_log_disposition "$LOG" "allow_state_complete" "marker present: falls through to today's Complete allow"

echo "--- Invariant: at most one block per epoch ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(open_entry 01 "Fix login flow")"
run "$wt"
assert_block "first stop this epoch: BLOCK"
run "$wt"
assert_allow "second stop, same epoch (marker now present): allow"
assert_log_disposition "$LOG" "allow_state_complete" "second stop: falls through to today's Complete allow"

echo "--- Inputs: CLAM_FOLLOWUPS_GATE explicit 'enabled' behaves like the default ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(open_entry 01 "Fix login flow")"
run "$wt" CLAM_FOLLOWUPS_GATE=enabled
assert_block "CLAM_FOLLOWUPS_GATE=enabled: BLOCK, same as default"

echo "--- Inputs: CLAM_FOLLOWUPS_GATE any non-'enabled' value disables the gate ---"

for val in disabled off nonsense; do
    wt=$(make_wt)
    write_todo "$wt" "Complete"
    write_followups "$wt" "$(open_entry 01 "Fix login flow")"
    run "$wt" CLAM_FOLLOWUPS_GATE="$val"
    assert_allow "CLAM_FOLLOWUPS_GATE=$val: gate disabled, allow despite an open entry"
done

echo "--- Inputs: open := '^- Status: open[[:space:]]*\$' — regex anchoring ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(printf '## F01 — Trailing whitespace\n- Status: open   \n- Captured: 2026-01-01\n- Source: test\n- Refs: none\n- Statement: x.\n')"
run "$wt"
assert_block "'- Status: open   ' (trailing whitespace) still counts as open"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(printf '## F01 — Not actually open\n- Status: opened\n- Captured: 2026-01-01\n- Source: test\n- Refs: none\n- Statement: x.\n')"
run "$wt"
assert_allow "'- Status: opened' does not match the open regex: allow"

for status_word in "filed #42" "resolved" "dropped (not needed)"; do
    wt=$(make_wt)
    write_todo "$wt" "Complete"
    write_followups "$wt" "$(disposed_entry 01 "Something" "$status_word")"
    run "$wt"
    assert_allow "'- Status: $status_word' is not open: allow"
done

echo "--- Invariant: Complete with a fully-dispositioned file behaves exactly as today ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(disposed_entry 01 "Filed one" "filed #7")$(disposed_entry 02 "Resolved one" "resolved")$(disposed_entry 03 "Dropped one" "dropped (not needed)")"
run "$wt"
assert_allow "fully-dispositioned FOLLOWUPS.md: allow"
assert_log_disposition "$LOG" "allow_state_complete" "fully-dispositioned: log disposition is allow_state_complete"

echo "--- Invariant: Complete with FOLLOWUPS.md absent behaves exactly as today ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
run "$wt"
assert_allow "FOLLOWUPS.md absent: allow"
assert_log_disposition "$LOG" "allow_state_complete" "FOLLOWUPS.md absent: log disposition is allow_state_complete"

echo "--- Edge case: zero-byte / malformed FOLLOWUPS.md -> pass ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" ""
run "$wt"
assert_allow "zero-byte FOLLOWUPS.md: allow"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(printf 'not a real entry\njust some garbage text\n')"
run "$wt"
assert_allow "malformed FOLLOWUPS.md (no Status lines at all): allow"

echo "--- Errors: fail-open on an unreadable FOLLOWUPS.md ---"

if [[ "$IS_ROOT" == "0" ]]; then
    wt=$(make_wt)
    write_todo "$wt" "Complete"
    write_followups "$wt" "$(open_entry 01 "Fix login flow")"
    chmod 000 "$wt/.local/FOLLOWUPS.md"
    run "$wt"
    assert_allow "unreadable FOLLOWUPS.md: fail-open allow despite an (unseeable) open entry"
    assert_exit0 "unreadable FOLLOWUPS.md: exit 0"
    chmod 644 "$wt/.local/FOLLOWUPS.md"
else
    echo "SKIP  unreadable-file case: running as root, permission bits ignored"
fi

echo "--- Errors: fail-open on an unwritable marker ---"

if [[ "$IS_ROOT" == "0" ]]; then
    wt=$(make_wt)
    write_todo "$wt" "Complete"
    write_followups "$wt" "$(open_entry 01 "Fix login flow")"
    chmod 555 "$wt/.local"
    run "$wt"
    assert_allow "unwritable .local/ (marker cannot be written): fail-open allow despite an open entry"
    assert_exit0 "unwritable .local/: exit 0"
    chmod 755 "$wt/.local"
else
    echo "SKIP  unwritable-marker case: running as root, permission bits ignored"
fi

echo "--- Invariant: non-Complete states are unaffected, even with open follow-ups ---"

wt=$(make_wt)
write_todo "$wt" "Blocked"
write_followups "$wt" "$(open_entry 01 "Fix login flow")"
run "$wt"
assert_allow "Blocked + open follow-ups: gate does not apply outside Complete"
assert_log_disposition "$LOG" "allow_state_blocked" "Blocked + open follow-ups: log disposition is allow_state_blocked"
assert_absent "$(marker_of "$wt")" "Blocked + open follow-ups: followups marker is never created"

wt=$(make_wt)
write_todo "$wt" "Awaiting User Review"
write_followups "$wt" "$(open_entry 01 "Fix login flow")"
run "$wt"
assert_allow "Awaiting User Review + open follow-ups: gate does not apply outside Complete"
assert_log_disposition "$LOG" "allow_state_awaiting_user_review" "Awaiting User Review + open follow-ups: log disposition unaffected"
assert_absent "$(marker_of "$wt")" "Awaiting User Review + open follow-ups: followups marker is never created"

echo "--- Invariant: read-only wrt FOLLOWUPS.md ---"

wt=$(make_wt)
write_todo "$wt" "Complete"
write_followups "$wt" "$(open_entry 01 "Fix login flow")"
before=$(checksum_of "$wt/.local/FOLLOWUPS.md")
run "$wt"
after=$(checksum_of "$wt/.local/FOLLOWUPS.md")
assert_eq "FOLLOWUPS.md is left byte-for-byte untouched (read-only invariant)" "$after" "$before"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "ALL PASS"
else
    echo "FAILURES"
fi
exit "$FAILED"
