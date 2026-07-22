#!/bin/bash
# Functional test for flush-nudge.sh: the UserPromptSubmit context-fill nudge.
# Run: bash plugins/tracking/scripts/flush-nudge.test.sh   (exits non-zero on failure)
#
# This is a from-scratch contract (see the comment block atop flush-nudge.sh),
# not a line-for-line port of the clam-code predecessor at
# ~/github/clam-code-trees/master/general/hooks/flush-nudge.sh. Key contract
# differences exercised below:
#   - Gated on .local/TODO.md existing, not .local/MODE.
#   - No CLAM_SESSION gate — plugin enablement is the opt-in.
#   - Escape hatch is CLAM_TRACKING_FLUSH_GATE=disabled.
#   - Window resolution: CLAM_FLUSH_CONTEXT_WINDOW (test override) ->
#     CLAUDE_CODE_AUTO_COMPACT_WINDOW (process env) -> ~/.claude/settings.json
#     -> skip.
#
# Self-contained: a temp worktree, a synthetic JSONL transcript, no network.
# The hook reads .cwd + .transcript_path from stdin JSON and prints the nudge
# (or nothing) to stdout; each case asserts on that stdout, the exit code, and
# the marker files.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/flush-nudge.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

WT="$TMPROOT/wt"
mkdir -p "$WT/.local"
TRANSCRIPT="$TMPROOT/transcript.jsonl"
TODO="$WT/.local/TODO.md"
FIRED="$WT/.local/.flush-nudge-fired"
SKIP="$WT/.local/.flush-nudge-skip-next"

# Fixture HOMEs for the window-resolution fallback tiers. HOME_WITH_SETTINGS
# carries a deployed ~/.claude/settings.json whose env block sets the window
# (the source the hook reads when the env var is unset); HOME_NO_SETTINGS has
# no .claude/ at all, so the hook can resolve no window and must skip.
HOME_WITH_SETTINGS="$TMPROOT/home-with-settings"
mkdir -p "$HOME_WITH_SETTINGS/.claude"
printf '{"env":{"CLAUDE_CODE_AUTO_COMPACT_WINDOW":"250000"}}\n' > "$HOME_WITH_SETTINGS/.claude/settings.json"
HOME_NO_SETTINGS="$TMPROOT/home-no-settings"
mkdir -p "$HOME_NO_SETTINGS"

# A PATH with common coreutils (including bash itself) but deliberately
# excluding jq, so the "jq not available" gate can be exercised without
# touching the real system PATH. Best-effort: if the hook's implementation
# needs a tool not listed here, that one "jq missing" case will fail loudly
# rather than silently mis-assert, which is an acceptable trade for coverage.
NOJQ_BIN="$TMPROOT/no-jq-bin"
mkdir -p "$NOJQ_BIN"
for tool in bash sh cat rm tr mkdir printf sed grep basename dirname wc head tail cp mv touch date ls sort mktemp readlink realpath env; do
    src=$(command -v "$tool" 2>/dev/null) || continue
    ln -sf "$src" "$NOJQ_BIN/$tool" 2>/dev/null
done

FAILED=0
OUT=""
EXIT=0

# Writes a transcript whose last assistant usage block sums to $1 tokens via
# input_tokens alone; the other summed fields default to 0 in the hook.
set_fill() {
    printf '{"type":"assistant","message":{"usage":{"input_tokens":%s}}}\n' "$1" > "$TRANSCRIPT"
}

# Writes a transcript whose last assistant usage block spreads its total
# across all four summed fields, so a fill computation that forgets one of
# them (e.g. only reads input_tokens) would under-count and fail to fire.
set_fill_components() {
    jq -c -n --argjson it "$1" --argjson cr "$2" --argjson e5 "$3" --argjson e1 "$4" \
        '{type:"assistant", message:{usage:{input_tokens:$it, cache_read_input_tokens:$cr, cache_creation:{ephemeral_5m_input_tokens:$e5, ephemeral_1h_input_tokens:$e1}}}}' \
        > "$TRANSCRIPT"
}

# Two assistant usage blocks; the fill must come from the LAST one, not the
# first and not their sum.
set_fill_last_of_two() {
    {
        printf '{"type":"assistant","message":{"usage":{"input_tokens":%s}}}\n' "$1"
        printf '{"type":"user","message":{"content":"hi"}}\n'
        printf '{"type":"assistant","message":{"usage":{"input_tokens":%s}}}\n' "$2"
    } > "$TRANSCRIPT"
}

set_fill_no_usage() {
    printf '{"type":"user","message":{"content":"hello"}}\n' > "$TRANSCRIPT"
}

set_fill_empty_transcript() {
    : > "$TRANSCRIPT"
}

# A valid usage line followed by a garbage (non-JSON) trailing line: the
# garbage line must be dropped, not crash the parse or blank out the fill.
set_fill_with_trailing_garbage() {
    printf '{"type":"assistant","message":{"usage":{"input_tokens":%s}}}\n' "$1" > "$TRANSCRIPT"
    printf 'this is not json at all\n' >> "$TRANSCRIPT"
}

touch_todo() { : > "$TODO"; }
rm_todo() { rm -f "$TODO"; }
reset_markers() { rm -f "$FIRED" "$SKIP"; }

# Runs the hook with a clean, explicit environment: the tunables it reads are
# unset first so a value inherited from the surrounding session (this test
# may run inside a clam session) cannot leak into a case. HOME defaults to a
# settings-less fixture so the window resolution's settings.json fallback
# can't read the real machine's ~/.claude. Extra assignments/overrides
# (including PATH= for the no-jq cases) come via "$@".
run_raw() {
    local json="$1"; shift
    OUT=$(printf '%s' "$json" | env \
        -u CLAM_TRACKING_FLUSH_GATE \
        -u CLAUDE_CODE_AUTO_COMPACT_WINDOW \
        -u CLAM_FLUSH_CONTEXT_WINDOW \
        -u CLAM_FLUSH_NUDGE_THRESHOLD \
        HOME="$HOME_NO_SETTINGS" \
        "$@" bash "$HOOK" 2>/dev/null)
    EXIT=$?
}

run() { run_raw "$(jq -n --arg cwd "$WT" --arg tp "$TRANSCRIPT" '{cwd:$cwd, transcript_path:$tp}')" "$@"; }
run_missing_transcript() { run_raw "$(jq -n --arg cwd "$WT" --arg tp "$TMPROOT/does-not-exist.jsonl" '{cwd:$cwd, transcript_path:$tp}')" "$@"; }
run_cwd() { local cwd_val="$1"; shift; run_raw "$(jq -n --arg cwd "$cwd_val" --arg tp "$TRANSCRIPT" '{cwd:$cwd, transcript_path:$tp}')" "$@"; }
run_no_cwd_field() { run_raw "$(jq -n --arg tp "$TRANSCRIPT" '{transcript_path:$tp}')" "$@"; }
run_no_transcript_field() { run_raw "$(jq -n --arg cwd "$WT" '{cwd:$cwd}')" "$@"; }

nudged() { [[ -n "$OUT" ]]; }
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }
assert_nudge()   { if nudged; then pass "$1"; else fail "$1: expected nudge, got silence"; fi; }
assert_silent()  { if nudged; then fail "$1: expected silence, got: $OUT"; else pass "$1"; fi; }
assert_contains(){ if [[ "$OUT" == *"$2"* ]]; then pass "$1"; else fail "$1: output missing: $2"; fi; }
assert_absent()  { if [[ ! -e "$1" ]]; then pass "$2"; else fail "$2: expected absent: $1"; fi; }
assert_present() { if [[ -e "$1" ]]; then pass "$2"; else fail "$2: expected present: $1"; fi; }
assert_exit0()   { if [[ "$EXIT" -eq 0 ]]; then pass "$1"; else fail "$1: exit code $EXIT"; fi; }

# Default fixture state most cases build on: TODO.md present, no markers.
touch_todo

echo "--- Gate: CLAM_TRACKING_FLUSH_GATE=disabled ---"

# Would otherwise fire (TODO.md present, fill well above threshold, window
# configured) but the escape hatch must win regardless.
reset_markers; set_fill 200000
run CLAM_TRACKING_FLUSH_GATE=disabled CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "CLAM_TRACKING_FLUSH_GATE=disabled: no nudge"
assert_exit0 "CLAM_TRACKING_FLUSH_GATE=disabled: exit 0"

echo "--- Gate: jq not available ---"

reset_markers; set_fill 200000
run PATH="$NOJQ_BIN" CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "jq missing: no nudge even though every other condition would fire"
assert_exit0 "jq missing: exit 0"

echo "--- Gate: .local/TODO.md must exist ---"

rm_todo
reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "TODO.md absent: no nudge"
assert_exit0 "TODO.md absent: exit 0"
touch_todo

# No .local/ directory at all is the same code path, checked directly too.
NOLOCAL="$TMPROOT/no-local-wt"
mkdir -p "$NOLOCAL"
reset_markers; set_fill 200000
run_cwd "$NOLOCAL" CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "no .local/ directory at all: no nudge"

echo "--- Gate: skip-next marker (post-compaction recovery) ---"

# Marker present + a fill that would otherwise nudge -> suppressed, marker
# consumed, and the one-shot .flush-nudge-fired must NOT be created (this
# prompt doesn't count as the epoch's fire).
reset_markers; : > "$SKIP"; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "skip-next present: no nudge on first post-compaction prompt"
assert_absent "$SKIP" "skip-next consumed (deleted)"
assert_absent "$FIRED" "one-shot marker not created while skipping"

# Immediately after (marker gone), metering resumes and the nudge fires.
set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_nudge "metering resumes on the next prompt once skip-next is consumed"

# skip-next must be consumed even when TODO.md is absent — it is placed
# ahead of the TODO.md gate so it's never left to suppress a future epoch.
rm_todo
reset_markers; : > "$SKIP"; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "skip-next + no TODO.md: still silent"
assert_absent "$SKIP" "skip-next consumed even though TODO.md is absent"
touch_todo

echo "--- Gate: cwd / transcript_path required in input ---"

reset_markers; set_fill 200000
run_no_cwd_field CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "cwd missing from input JSON: no nudge"
assert_exit0 "cwd missing: exit 0"

reset_markers; set_fill 200000
run_no_transcript_field CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "transcript_path missing from input JSON: no nudge"
assert_exit0 "transcript_path missing: exit 0"

echo "--- Gate: transcript must exist and be readable ---"

reset_markers; set_fill 200000
run_missing_transcript CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "missing transcript file: no nudge"
assert_exit0 "missing transcript file: exit 0"

echo "--- Gate: transcript must contain an assistant usage block ---"

reset_markers; set_fill_no_usage
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "transcript has no assistant usage blocks (all user turns): no nudge"

reset_markers; set_fill_empty_transcript
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "empty transcript file: no nudge"

echo "--- Window resolution ---"

# No window anywhere (no env var, no settings.json) -> skip even at a fill
# that would otherwise nudge.
reset_markers; set_fill 200000
run
assert_silent "no window configured anywhere: no nudge"

# Window present but not a positive integer.
reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=notanumber
assert_silent "window is not a positive integer (non-numeric): no nudge"
reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=0
assert_silent "window is not a positive integer (zero): no nudge"

# CLAM_FLUSH_CONTEXT_WINDOW takes precedence over CLAUDE_CODE_AUTO_COMPACT_WINDOW.
# 190000/200000 = 95% (fires); 190000/1000000 = 19% (would not fire) — only
# the override value explains a fire here.
reset_markers; set_fill 190000
run CLAM_FLUSH_CONTEXT_WINDOW=200000 CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000
assert_nudge "CLAM_FLUSH_CONTEXT_WINDOW overrides CLAUDE_CODE_AUTO_COMPACT_WINDOW"

# CLAUDE_CODE_AUTO_COMPACT_WINDOW alone (no override) resolves the window.
reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_nudge "CLAUDE_CODE_AUTO_COMPACT_WINDOW from env resolves the window"

# Env var unset -> fall back to the deployed ~/.claude/settings.json.
reset_markers; set_fill 100000
run HOME="$HOME_WITH_SETTINGS"
assert_silent "settings.json fallback: 100000/250000=40%: no nudge"
reset_markers; set_fill 200000
run HOME="$HOME_WITH_SETTINGS"
assert_nudge "settings.json fallback: 200000/250000=80%: nudge"

# Neither the env var nor a settings.json -> skip silently, no hardcoded window.
reset_markers; set_fill 200000
run HOME="$HOME_NO_SETTINGS"
assert_silent "no env var and no settings.json: silent, no hardcoded fallback"

echo "--- Fill computation ---"

# Last assistant usage block wins: first block alone would fire (96%), last
# block alone would not (20%). Fill must come from the last one.
reset_markers; set_fill_last_of_two 240000 50000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "fill comes from the LAST assistant usage block, not the first"

# All four summed fields contribute: each alone is 18.75% (below threshold)
# but their sum is 75%, at the default threshold.
reset_markers; set_fill_components 46875 46875 46875 46875
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_nudge "fill sums input_tokens + cache_read_input_tokens + both cache_creation fields"

# A trailing malformed (non-JSON) line is dropped, not fatal, and doesn't
# blank out the previously-read valid fill.
reset_markers; set_fill_with_trailing_garbage 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_nudge "malformed trailing transcript line is dropped, valid fill still used"
assert_exit0 "malformed trailing transcript line: exit 0"

echo "--- Threshold gate + firing ---"

# Below threshold.
reset_markers; set_fill 100000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "100000/250000=40%: below default threshold, no nudge"

# Boundary: 74% does not fire, 75% (exactly at threshold) does — fill >= threshold.
reset_markers; set_fill 187499
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "187499/250000=74%: just below threshold, no nudge"
reset_markers; set_fill 187500
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_nudge "187500/250000=75%: exactly at threshold, nudge fires"

# Above threshold.
reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_nudge "200000/250000=80%: above threshold, nudge fires"

# Custom threshold plumbs through.
reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 CLAM_FLUSH_NUDGE_THRESHOLD=90
assert_silent "custom threshold 90: 200000/250000=80%: no nudge"
reset_markers; set_fill 230000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 CLAM_FLUSH_NUDGE_THRESHOLD=90
assert_nudge "custom threshold 90: 230000/250000=92%: nudge"

# Invalid thresholds fall back to the default of 75, proven with a fill pair
# that only agrees with "default 75" and not with a degenerate value (0
# always fires, a crash always stays silent, etc).
for bad_threshold in abc 0 -10; do
    reset_markers; set_fill 100000
    run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 CLAM_FLUSH_NUDGE_THRESHOLD="$bad_threshold"
    assert_silent "invalid threshold '$bad_threshold': falls back to 75, 40% does not fire"
    reset_markers; set_fill 200000
    run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 CLAM_FLUSH_NUDGE_THRESHOLD="$bad_threshold"
    assert_nudge "invalid threshold '$bad_threshold': falls back to 75, 80% fires"
done

# Threshold > 100 is used as-is (effectively never fires), not defaulted.
reset_markers; set_fill 240000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 CLAM_FLUSH_NUDGE_THRESHOLD=150
assert_silent "threshold 150: 240000/250000=96% is still below 150%: no nudge"

echo "--- One-shot per epoch (fired marker) ---"

reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_nudge "one-shot: first crossing nudges"
assert_present "$FIRED" "one-shot: marker created on fire"
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_silent "one-shot: second prompt in the same epoch is suppressed"
assert_present "$FIRED" "one-shot: marker still present, untouched"

echo "--- Nudge content ---"

reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_nudge "fire scenario for content checks"
assert_contains "nudge mentions TODO.md" "TODO.md"
assert_contains "nudge mentions PLAN.md" "PLAN.md"
assert_contains "nudge mentions IMPLEMENTATION-PLAN.md" "IMPLEMENTATION-PLAN.md"
assert_contains "nudge mentions TROUBLESHOOTING.md" "TROUBLESHOOTING.md"
assert_contains "nudge mentions SUBAGENT-LOG" "SUBAGENT-LOG"
assert_contains "nudge mentions decisions/" "decisions/"

echo "--- No CLAM_SESSION gate (removed vs. predecessor) ---"

# The predecessor gated on CLAM_SESSION=1; this contract has no such gate.
# Every case above already runs without it, but assert it explicitly so a
# regression that re-adds the gate is caught here.
reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_nudge "nudge fires without CLAM_SESSION being set at all"

echo "--- Always exits 0 ---"

reset_markers; set_fill 200000
run CLAM_TRACKING_FLUSH_GATE=disabled CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_exit0 "exit 0 on disabled path"

rm_todo; reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_exit0 "exit 0 on TODO.md-absent path"
touch_todo

reset_markers; set_fill 100000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_exit0 "exit 0 on below-threshold (silent) path"

reset_markers; set_fill 200000
run CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000
assert_exit0 "exit 0 on fire path"
assert_exit0 "exit 0 confirmed after fire"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "ALL PASS"
else
    echo "FAILURES"
fi
exit $FAILED
