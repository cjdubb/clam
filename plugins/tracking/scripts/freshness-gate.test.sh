#!/bin/bash
# Tests for keep-working.sh's check_tracking_freshness function (B02 —
# freshness-stop-gate): the "Contract: B02" docblock above the function, plus
# the call-site comment wiring it in front of the State case for every State
# other than Not Started / In Progress.
#
# Black-box: drives the WHOLE Stop hook via stdin JSON
# ({"cwd":...,"transcript_path":...,"session_id":...,"stop_hook_active":...}),
# matching awaiting-user.test.sh's style (this contract composes with the
# rest of keep-working.sh's State handling, so it can't be extracted and
# eval'd in isolation the way no-todo-nudge.test.sh does). Asserts on stdout
# (empty = allow; {"decision":"block",...} = block), exit code, the
# .local/.freshness-nudge-fired marker, and the $CLAUDE_STOP_LOG disposition.
#
# Hermetic: mktemp worktrees with a committed baseline (keeps the no-todo
# nudge's substantive-work check quiet), but every case ALSO writes
# .local/TODO.md directly — which skips that check entirely (it returns as
# soon as TODO.md exists) — so the baseline commit is redundant belt-and-
# braces, not load-bearing. No .local/PLAN.md is ever created, so the plan
# gate (which composes in front of the freshness gate) stays quiet. No
# network; lib/activity.sh (B01) is real here and does the actual transcript
# counting.
#
# Run: bash plugins/tracking/scripts/freshness-gate.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/keep-working.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Unwritable-marker case is meaningless under a uid that ignores permission
# bits (mirrors activity.test.sh's IS_ROOT guard).
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

# Pins $1's mtime to a fixed point via touch -t, then echoes back the epoch
# actually recorded (read back from the filesystem via `date -r`, not
# computed from the touch -t spec) so nothing downstream has to reason about
# touch -t's local-timezone interpretation — only the resulting epoch does.
set_todo_epoch() { # todo_path -> echoes epoch
    touch -t 202601010000 "$1"
    date -r "$1" +%s
}

# Writes $3 qualifying human-prompt JSONL lines to $1: type=user, string
# content, ISO-8601 UTC timestamp at ref_epoch + base_offset + i*60 seconds.
# A positive base_offset (default 60) makes every line strictly newer than
# ref_epoch (qualifies per activity_prompts_since); a negative one (e.g.
# -600) makes every line strictly older (does not qualify) — used for the
# "docs are genuinely fresh" fixtures.
write_transcript() { # path ref_epoch count [base_offset=60]
    local path="$1" ref="$2" count="$3" base="${4:-60}"
    : > "$path"
    local i ts
    for ((i = 0; i < count; i++)); do
        ts=$(date -u -d "@$((ref + base + i * 60))" +"%Y-%m-%dT%H:%M:%SZ")
        printf '{"type":"user","message":{"content":"plain text turn %d"},"timestamp":"%s"}\n' "$i" "$ts" >> "$path"
    done
}

# Common stale/fresh scenario builder: a fresh worktree with State=$1,
# TODO.md mtime pinned to a controlled epoch, and a transcript with $2
# qualifying (or, with a negative base, non-qualifying) prompts relative to
# it. Echoes "wt_path transcript_path" (both always under $TMPROOT, no
# embedded spaces, so a plain `read -r wt tp <<<` split is safe).
setup_scenario() { # state prompt_count [base_offset=60] -> echoes "$wt $tp"
    local state="$1" count="$2" base="${3:-60}"
    local wt todo ref tp
    wt=$(make_wt)
    write_todo "$wt" "$state"
    todo="$wt/.local/TODO.md"
    ref=$(set_todo_epoch "$todo")
    tp="$wt/transcript.jsonl"
    write_transcript "$tp" "$ref" "$count" "$base"
    printf '%s %s' "$wt" "$tp"
}

# --- Hook driver --------------------------------------------------------------

# Runs the hook with a clean env (the freshness/PR/independent-review/gate
# tunables it reads are unset first so nothing leaks in from the surrounding
# session) and a fresh per-call $CLAUDE_STOP_LOG so the log disposition of
# THIS run can be read back unambiguously. Extra "$@" env assignments
# (CLAM_TRACKING_FRESHNESS_THRESHOLD=1, etc.) come from the caller.
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
        CLAUDE_STOP_LOG="$LOG" \
        "$@" bash "$HOOK" 2>"$TMPROOT/stderr-last")
    EXIT=$?
}
run() { # wt transcript_path [env assignments...]
    local wt="$1" tp="$2"; shift 2
    run_raw "$(jq -n --arg cwd "$wt" --arg tp "$tp" '{cwd:$cwd, transcript_path:$tp, session_id:"s1", stop_hook_active:false}')" "$@"
}
run_stop_hook_active() { # wt transcript_path [env assignments...]
    local wt="$1" tp="$2"; shift 2
    run_raw "$(jq -n --arg cwd "$wt" --arg tp "$tp" '{cwd:$cwd, transcript_path:$tp, session_id:"s1", stop_hook_active:true}')" "$@"
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
# Reads the LAST log line's "decision" field (the disposition string log_stop
# was called with, e.g. "block_freshness" — distinct from the hook's own
# stdout {"decision":"block",...} JSON) out of $1 and compares to $2.
assert_log_disposition() { # log expected_disposition label
    local log="$1" expected="$2" label="$3" got=""
    [[ -f "$log" ]] && got=$(jq -rs 'map(.decision) | last // empty' "$log" 2>/dev/null)
    if [[ "$got" == "$expected" ]]; then pass "$label"; else fail "$label: expected disposition '$expected', got '$got' (log: $log)"; fi
}

marker_of() { printf '%s/.local/.freshness-nudge-fired' "$1"; }

echo "--- Parked state + stale docs: BLOCK once, with full reason detail ---"

# 5 qualifying prompts against the default threshold (2) — a count clearly
# distinct from the threshold digit, so pattern assertions below can't
# accidentally match the wrong number.
read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 5)"
run "$wt" "$tp"
assert_block "parked state ('Awaiting User Review') + 5 stale prompts (default threshold 2): BLOCK"
assert_exit0 "parked state + stale: exit 0"
assert_reason_matches "block reason names the State verbatim" "Awaiting User Review"
assert_reason_matches "block reason names the prompt count (5)" "\\b5\\b"
assert_reason_matches "block reason names the threshold (2, default)" "\\b2\\b"
assert_reason_matches "block reason mentions TODO.md" "TODO(\\.md)?"
assert_reason_matches "block reason gives an update-or-touch instruction" "update|touch"
assert_reason_matches "block reason states the once-per-epoch nature" "once per|epoch"
assert_present "$(marker_of "$wt")" "block creates the .local/.freshness-nudge-fired marker"
assert_log_disposition "$LOG" "block_freshness" "log disposition is block_freshness"

echo "--- Once per epoch: marker already present -> allow ---"

read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 5)"
: > "$(marker_of "$wt")"
run "$wt" "$tp"
assert_allow "marker already present: allow despite stale docs (once-per-epoch)"
assert_exit0 "marker present: exit 0"

echo "--- Fresh docs: TODO.md touched AFTER the newest prompt -> allow ---"

read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 5)"
touch "$wt/.local/TODO.md"
run "$wt" "$tp"
assert_allow "TODO.md touched after the newest prompt: allow (docs fresh)"
assert_exit0 "fresh docs: exit 0"

echo "--- Threshold boundary: default 2 ---"

read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 1)"
run "$wt" "$tp"
assert_allow "1 prompt (threshold-1 at the default threshold 2): allow"

read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 2)"
run "$wt" "$tp"
assert_block "2 prompts (== default threshold 2): block"

echo "--- CLAM_TRACKING_FRESHNESS_THRESHOLD override ---"

read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 1)"
run "$wt" "$tp" CLAM_TRACKING_FRESHNESS_THRESHOLD=1
assert_block "CLAM_TRACKING_FRESHNESS_THRESHOLD=1: a single prompt blocks"

echo "--- Invalid threshold falls back to default (2) ---"

for bad_threshold in abc 0; do
    read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 1)"
    run "$wt" "$tp" CLAM_TRACKING_FRESHNESS_THRESHOLD="$bad_threshold"
    assert_allow "invalid threshold '$bad_threshold': falls back to default 2, 1 prompt allows"

    read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 2)"
    run "$wt" "$tp" CLAM_TRACKING_FRESHNESS_THRESHOLD="$bad_threshold"
    assert_block "invalid threshold '$bad_threshold': falls back to default 2, 2 prompts block"
done

echo "--- CLAM_TRACKING_FRESHNESS_GATE=disabled: allow even when very stale ---"

read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 10)"
run "$wt" "$tp" CLAM_TRACKING_FRESHNESS_GATE=disabled
assert_allow "gate disabled: allow despite 10 stale prompts"
assert_exit0 "gate disabled: exit 0"

echo "--- Composition: every turn-end-permitting State is gated, not just parked ones ---"

# Blocked normally allows unconditionally (log_stop allow_state_blocked) —
# proving the freshness gate composes IN FRONT of that, not after it.
read -r wt tp <<< "$(setup_scenario "Blocked" 5)"
run "$wt" "$tp"
assert_block "Blocked + stale: freshness gate blocks ahead of Blocked's own instant-allow"
assert_reason_matches "Blocked + stale: reason still names the State" "Blocked"
assert_log_disposition "$LOG" "block_freshness" "Blocked + stale: log disposition is block_freshness"

# Same State, but with docs genuinely fresh (prompts all before the mtime,
# not merely an empty-transcript fail-open) -> falls through cleanly to
# Blocked's ordinary allow. Proves the gate doesn't over-block.
read -r wt tp <<< "$(setup_scenario "Blocked" 3 "-600")"
run "$wt" "$tp"
assert_allow "Blocked + fresh docs: allow via Blocked's normal (unconditional) path"
assert_log_disposition "$LOG" "allow_state_blocked" "Blocked + fresh docs: log disposition is allow_state_blocked"

# Waiting For Decision deliberately has NO Decision Needed / .local/decisions
# pointer, so — if freshness did not win — the decision-file nudge would
# block instead, with a distinct reason and its OWN marker
# (.local/.decision-nudge-fired). Asserting freshness's reason (not the
# decision-file one) AND the decision-nudge marker's absence together prove
# the decision-file check was never even reached.
read -r wt tp <<< "$(setup_scenario "Waiting For Decision" 5)"
run "$wt" "$tp"
assert_block "Waiting For Decision + stale (no decision file either): freshness still wins"
assert_reason_not_matches "reason is NOT the decision-file nudge (no '.local/decisions/' mention)" "\\.local/decisions"
assert_absent "$wt/.local/.decision-nudge-fired" "decision-nudge marker NOT created: freshness ran first"
assert_log_disposition "$LOG" "block_freshness" "Waiting For Decision + stale: log disposition is block_freshness"

# Complete's PR-cron / independent-review backstops are both no-ops here
# (CLAM_PR_CRONS / CLAM_INDEPENDENT_REVIEW left unset/disabled per the
# brief), so Complete would otherwise allow unconditionally — a block here
# can only be the freshness gate.
read -r wt tp <<< "$(setup_scenario "Complete" 5)"
run "$wt" "$tp"
assert_block "Complete + stale: freshness gate blocks even though PR/IR backstops are no-ops"
assert_log_disposition "$LOG" "block_freshness" "Complete + stale: log disposition is block_freshness"

read -r wt tp <<< "$(setup_scenario "Complete" 3 "-600")"
run "$wt" "$tp"
assert_allow "Complete + fresh docs: allow via Complete's normal path"
assert_log_disposition "$LOG" "allow_state_complete" "Complete + fresh docs: log disposition is allow_state_complete"

echo "--- Not Started / In Progress: freshness NEVER fires ---"

for active_state in "Not Started" "In Progress"; do
    read -r wt tp <<< "$(setup_scenario "$active_state" 10)"
    run "$wt" "$tp"
    assert_block "$active_state + stale: still blocks, but via the normal keep-working state block"
    assert_reason_matches "$active_state: reason is the normal state-block wording" "not a State that permits ending the turn"
    assert_reason_not_matches "$active_state: reason does NOT carry the freshness once-per-epoch wording" "epoch"
    assert_absent "$(marker_of "$wt")" "$active_state: no freshness marker is ever created"
done

echo "--- Fail-open: transcript_path empty or missing ---"

wt=$(make_wt)
write_todo "$wt" "Awaiting User Review"
set_todo_epoch "$wt/.local/TODO.md" >/dev/null
run "$wt" ""
assert_allow "empty transcript_path: allow (fail-open)"
assert_exit0 "empty transcript_path: exit 0"

run "$wt" "$wt/.local/does-not-exist.jsonl"
assert_allow "missing (nonexistent) transcript_path: allow (fail-open)"
assert_exit0 "missing transcript_path: exit 0"

echo "--- Fail-open: marker unwritable ---"

if [[ "$IS_ROOT" == "0" ]]; then
    read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 5)"
    chmod 555 "$wt/.local"
    run "$wt" "$tp"
    assert_allow "unwritable .local/ (marker cannot be written): fail-open allow despite stale docs"
    assert_exit0 "unwritable .local/: exit 0"
    chmod 755 "$wt/.local"
else
    echo "SKIP  unwritable marker case: running as root, permission bits ignored"
fi

echo "--- stop_hook_active=true: loop guard runs before everything, including freshness ---"

read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 10)"
run_stop_hook_active "$wt" "$tp"
assert_allow "stop_hook_active=true: allow, even with 10 stale prompts on a parked State"
assert_exit0 "stop_hook_active=true: exit 0"
assert_log_disposition "$LOG" "allow_loop_guard" "stop_hook_active=true: log disposition is allow_loop_guard"

echo "--- A same-turn TODO.md touch satisfies the gate on the re-stop ---"

read -r wt tp <<< "$(setup_scenario "Awaiting User Review" 5)"
run "$wt" "$tp"
assert_block "initial stale turn: BLOCK"
# Isolate from the once-per-epoch marker path per the brief: remove the
# marker so a subsequent allow can only be explained by the docs now being
# fresh, not by the marker suppressing a re-fire.
rm -f "$(marker_of "$wt")"
touch "$wt/.local/TODO.md"
run "$wt" "$tp"
assert_allow "same stale transcript, but TODO.md touched after the block: allow (docs now fresh)"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "ALL PASS"
else
    echo "FAILURES"
fi
exit "$FAILED"
