#!/bin/bash
# Tests for awaiting-user.sh's unpark_nudge function (B03 — unpark-nudge):
# the UserPromptSubmit turn-START nudge that fires when a prompt reopens a
# session parked on a manifest "parked" State, reminding the agent to set
# State: In Progress and record any direction change before proceeding (or
# that the State may stand for a mere acknowledgement).
#
# Also covers the script's pre-existing marker lifecycle (Stop writes
# .local/.awaiting-user, UserPromptSubmit removes it), which B03's contract
# names as an unchanged Invariant — those clauses are regression coverage,
# not new B03 behavior, and pass against today's NotImplemented stub.
#
# Black-box: drives the whole script via stdin JSON
# ({"cwd":..., "hook_event_name":...}), asserting on stdout, exit code, and
# the marker file. Self-contained: hermetic mktemp worktrees, no network.
#
# Run: bash plugins/tracking/scripts/awaiting-user.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/awaiting-user.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$PLUGIN_ROOT/lib/states.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# A PATH with common coreutils (including bash itself) but deliberately
# excluding jq, for the "jq not available" gate (mirrors flush-nudge.test.sh).
NOJQ_BIN="$TMPROOT/no-jq-bin"
mkdir -p "$NOJQ_BIN"
for tool in bash sh cat rm tr mkdir printf sed grep basename dirname wc head tail cp mv touch date ls sort mktemp readlink realpath env; do
    src=$(command -v "$tool" 2>/dev/null) || continue
    ln -sf "$src" "$NOJQ_BIN/$tool" 2>/dev/null
done

# A copy of the hook with no ../lib/states.sh reachable from it, for the
# "states lib not sourceable" fail-open gate: the contract says
# unpark_nudge sources lib/states.sh lazily and must keep working (no
# nudge) if that lib is missing, relative to the SCRIPT's own location.
ISOLATED_DIR="$TMPROOT/isolated/scripts"
mkdir -p "$ISOLATED_DIR"
cp "$HOOK" "$ISOLATED_DIR/awaiting-user.sh"

FAILED=0
OUT=""
EXIT=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }
nudged() { [[ -n "$OUT" ]]; }
assert_nudge()    { if nudged; then pass "$1"; else fail "$1: expected nudge, got silence"; fi; }
assert_silent()   { if nudged; then fail "$1: expected silence, got: $OUT"; else pass "$1"; fi; }
assert_contains() { if [[ "$OUT" == *"$2"* ]]; then pass "$1"; else fail "$1: output missing: $2 (got: $OUT)"; fi; }
assert_matches_any() { # label pattern(extended regex, case-insensitive)
    if printf '%s' "$OUT" | grep -qiE "$2"; then pass "$1"; else fail "$1: output missing pattern: $2 (got: $OUT)"; fi
}
assert_absent()   { if [[ ! -e "$1" ]]; then pass "$2"; else fail "$2: expected absent: $1"; fi; }
assert_present()  { if [[ -e "$1" ]]; then pass "$2"; else fail "$2: expected present: $1"; fi; }
assert_exit0()    { if [[ "$EXIT" -eq 0 ]]; then pass "$1"; else fail "$1: exit code $EXIT"; fi; }

# Builds a hermetic worktree: a fresh mktemp dir under $TMPROOT with a
# baseline git repo and a .local/ dir (the outer script's own
# [[ -d "$cwd/.local" ]] gate needs it). Uses mktemp rather than a counter
# because this is always called as `wt=$(make_wt)`, a command substitution
# subshell in which a counter increment can't propagate back to the caller.
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

marker_of() { printf '%s/.local/.awaiting-user' "$1"; }

# Realistic fixture: plain "State: X" line plus a couple of the template's
# neighboring fields, matching how session TODO.md files actually look.
write_todo_plain() { # wt state
    printf 'State: %s\nCurrent Task: doing the thing\nLast Updated: 2026-07-23 12:00\n' "$2" > "$1/.local/TODO.md"
}

# Bold "**State:**" variant — todo_field's documented bold-tolerance path.
write_todo_bold() { # wt state
    printf '**State:** %s\nCurrent Task: doing the thing\n' "$2" > "$1/.local/TODO.md"
}

set_marker() { : > "$(marker_of "$1")"; }
rm_todo() { rm -f "$1/.local/TODO.md"; }

# Runs the hook (or an isolated copy) with a clean env: CLAM_TRACKING_UNPARK_NUDGE
# unset first so nothing leaks in from the surrounding session, overridable via "$@".
run_raw() { # json hook_path [env/PATH overrides...]
    local json="$1" hook="$2"; shift 2
    OUT=$(printf '%s' "$json" | env -u CLAM_TRACKING_UNPARK_NUDGE "$@" bash "$hook" 2>/dev/null)
    EXIT=$?
}
run() { # wt event [env overrides...]
    local wt="$1" event="$2"; shift 2
    run_raw "$(jq -n --arg cwd "$wt" --arg he "$event" '{cwd:$cwd, hook_event_name:$he}')" "$HOOK" "$@"
}
run_isolated() { # wt event [env overrides...]
    local wt="$1" event="$2"; shift 2
    run_raw "$(jq -n --arg cwd "$wt" --arg he "$event" '{cwd:$cwd, hook_event_name:$he}')" "$ISOLATED_DIR/awaiting-user.sh" "$@"
}

echo "--- Data-driven: every manifest State gets the category-correct treatment ---"

# Sourced from lib/states.sh / states.tsv rather than hardcoded, so this
# matrix stays in lockstep with the manifest. Marker is present in every
# case here — only the State's category should decide nudge vs silence.
# IFS/read (not `for state in $(state_names)`) to preserve multi-word
# State names like "Awaiting User Review" intact.
while IFS= read -r state; do
    [ -n "$state" ] || continue
    category=$(state_category "$state")
    wt=$(make_wt)
    write_todo_plain "$wt" "$state"
    set_marker "$wt"
    run "$wt" UserPromptSubmit

    case "$category" in
        parked)
            assert_nudge "State '$state' (parked): nudge fires"
            assert_contains "State '$state' (parked): nudge names the State verbatim" "$state"
            ;;
        needs_user)
            assert_silent "State '$state' (needs_user): no nudge — summons is the designed flow"
            ;;
        active|terminal|"")
            assert_silent "State '$state' (category '$category'): no nudge"
            ;;
    esac
    assert_exit0 "State '$state': always exits 0"
    assert_absent "$(marker_of "$wt")" "State '$state': marker removed after the prompt"
done < <(state_names)

echo "--- Nudge content: both instructions, on a flagship parked State ---"

wt=$(make_wt)
write_todo_plain "$wt" "Awaiting User Review"
set_marker "$wt"
run "$wt" UserPromptSubmit
assert_nudge "flagship parked State: nudge fires"
assert_contains "nudge names the State verbatim" "Awaiting User Review"
assert_contains "nudge instructs setting In Progress" "In Progress"
assert_contains "nudge instructs recording the direction change in TODO.md" "TODO.md"
assert_matches_any "nudge covers the mere-acknowledgement alternative (State may stand)" "may stand|acknowledg"
assert_exit0 "flagship parked State: exit 0"

echo "--- Bold **State:** variant (todo_field bold tolerance) ---"

wt=$(make_wt)
write_todo_bold "$wt" "Awaiting CI"
set_marker "$wt"
run "$wt" UserPromptSubmit
assert_nudge "bold **State:** parked variant: nudge fires"
assert_contains "bold **State:** parked variant: names the State verbatim (no stray asterisks)" "Awaiting CI"
assert_exit0 "bold **State:** parked variant: exit 0"

wt=$(make_wt)
write_todo_bold "$wt" "Blocked"
set_marker "$wt"
run "$wt" UserPromptSubmit
assert_silent "bold **State:** needs_user variant: no nudge"
assert_exit0 "bold **State:** needs_user variant: exit 0"

echo "--- Marker absent -> silent, regardless of State ---"

wt=$(make_wt)
write_todo_plain "$wt" "Awaiting User Review"
# no set_marker: marker never existed
run "$wt" UserPromptSubmit
assert_silent "marker absent (parked State otherwise nudge-worthy): no nudge"
assert_exit0 "marker absent: exit 0"
assert_absent "$(marker_of "$wt")" "marker absent: still absent afterward"

echo "--- No TODO.md -> silent (marker present, distinct from marker-absent path) ---"

wt=$(make_wt)
set_marker "$wt"
# no TODO.md ever written for this worktree
run "$wt" UserPromptSubmit
assert_silent "no TODO.md, marker present: no nudge"
assert_exit0 "no TODO.md: exit 0"
assert_absent "$(marker_of "$wt")" "no TODO.md: marker still removed by the caller"

# Marker present, TODO.md existed then was deleted mid-session (contract's
# explicit edge case) -> same fail-open silence.
wt=$(make_wt)
write_todo_plain "$wt" "Awaiting User Review"
set_marker "$wt"
rm_todo "$wt"
run "$wt" UserPromptSubmit
assert_silent "TODO.md deleted mid-session, marker present: no nudge"
assert_exit0 "TODO.md deleted mid-session: exit 0"

echo "--- CLAM_TRACKING_UNPARK_NUDGE=disabled -> silent ---"

wt=$(make_wt)
write_todo_plain "$wt" "Awaiting User Review"
set_marker "$wt"
run "$wt" UserPromptSubmit CLAM_TRACKING_UNPARK_NUDGE=disabled
assert_silent "CLAM_TRACKING_UNPARK_NUDGE=disabled: no nudge even though every other condition would fire"
assert_exit0 "CLAM_TRACKING_UNPARK_NUDGE=disabled: exit 0"
assert_absent "$(marker_of "$wt")" "CLAM_TRACKING_UNPARK_NUDGE=disabled: marker still removed"

# Default (unset) must behave as enabled — proven by a fire that only
# succeeds if the default resolves to "on".
wt=$(make_wt)
write_todo_plain "$wt" "Awaiting User Review"
set_marker "$wt"
run "$wt" UserPromptSubmit
assert_nudge "CLAM_TRACKING_UNPARK_NUDGE unset: default is enabled, nudge fires"

echo "--- Fail-open: jq unavailable ---"

wt=$(make_wt)
write_todo_plain "$wt" "Awaiting User Review"
set_marker "$wt"
run "$wt" UserPromptSubmit PATH="$NOJQ_BIN"
assert_silent "jq missing: no nudge even though every other condition would fire"
assert_exit0 "jq missing: exit 0"

echo "--- Fail-open: states lib not sourceable ---"

wt=$(make_wt)
write_todo_plain "$wt" "Awaiting User Review"
set_marker "$wt"
run_isolated "$wt" UserPromptSubmit
assert_silent "states lib unreachable from the script's own location: no nudge"
assert_exit0 "states lib unreachable: exit 0"
assert_absent "$(marker_of "$wt")" "states lib unreachable: marker still removed by the caller"

echo "--- Two prompts in succession -> single fire ---"

wt=$(make_wt)
write_todo_plain "$wt" "Awaiting User Review"
set_marker "$wt"
run "$wt" UserPromptSubmit
assert_nudge "first prompt after park: nudge fires"
assert_absent "$(marker_of "$wt")" "first prompt: marker removed"
run "$wt" UserPromptSubmit
assert_silent "second prompt, same session, marker already consumed: no re-fire"
assert_exit0 "second prompt: exit 0"

echo "--- Invariant: never blocks/denies the prompt ---"

# The contract requires plain stdout context only — never JSON decision
# output nor a non-zero (blocking) exit code, even on the fire path.
wt=$(make_wt)
write_todo_plain "$wt" "Awaiting User Review"
set_marker "$wt"
run "$wt" UserPromptSubmit
assert_exit0 "fire path: exit 0 (never blocks the prompt)"
if [[ "$OUT" == *'"decision"'* ]]; then
    fail "fire path: stdout must not be a decision-JSON block, got: $OUT"
else
    pass "fire path: stdout is plain nudge text, not decision JSON"
fi

echo "--- Regression: pre-existing marker lifecycle (Invariants: unchanged by B03) ---"

# Stop event writes the marker, unconditionally of State or TODO.md.
wt=$(make_wt)
write_todo_plain "$wt" "In Progress"
run "$wt" Stop
assert_present "$(marker_of "$wt")" "Stop event: marker created"
assert_exit0 "Stop event: exit 0"
if [[ "$(cat "$(marker_of "$wt")" 2>/dev/null)" =~ ^[0-9]+$ ]]; then
    pass "Stop event: marker content is a timestamp"
else
    fail "Stop event: marker content is a timestamp: got '$(cat "$(marker_of "$wt")" 2>/dev/null)'"
fi

# Stop event writes the marker even with no TODO.md at all (Stop doesn't
# consult State/TODO.md — only UserPromptSubmit's nudge does).
wt=$(make_wt)
run "$wt" Stop
assert_present "$(marker_of "$wt")" "Stop event, no TODO.md: marker still created"

# UserPromptSubmit removes an existing marker even on an event/State
# combination where no nudge fires (marker lifecycle is independent of the
# nudge outcome).
wt=$(make_wt)
write_todo_plain "$wt" "In Progress"
set_marker "$wt"
run "$wt" UserPromptSubmit
assert_absent "$(marker_of "$wt")" "UserPromptSubmit removes marker even on a non-nudging State"
assert_silent "UserPromptSubmit on In Progress: no nudge"

# UserPromptSubmit with no marker and no TODO.md is a pure no-op, still exit 0.
wt=$(make_wt)
run "$wt" UserPromptSubmit
assert_silent "UserPromptSubmit, no marker, no TODO.md: silent"
assert_exit0 "UserPromptSubmit, no marker, no TODO.md: exit 0"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "ALL PASS"
else
    echo "FAILURES"
fi
exit $FAILED
