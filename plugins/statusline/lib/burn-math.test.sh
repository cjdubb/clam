#!/bin/bash
# Behavioral test for burn-math.sh's awake-hours burn pacing: the day-start
# resolver (burn_day_start_epoch), the shared awake-seconds primitive
# (burn_awake_seconds), and the renderer-facing metrics function
# (burn_metrics) that inlines the same awake-walk to produce TODAY/PACE/
# TREND. Covers the half-open [A,B) day-boundary invariant, the
# SLEEP_SECONDS={0,86399} extremes, the TODAY 100/0/negative/capped/NA fixed
# points, PACE's clamp-to-1-day and below-10/at-10 print-format rule,
# TREND's sign convention, the DAY_START_EPOCH mod-86400 phasing invariant,
# and every documented "cannot compute" error.
#
# Contract: B01 burn-math (plan 001-statusline-burnrate-uplift), docblock in
# burn-math.sh. All expected numbers are hardcoded, derived by hand from the
# docblock's own $_BURN_AWK_AWAKE algorithm and its prose formulas for
# TODAY/PACE/TREND -- never from calling `date`, so every case is exactly
# reproducible on any machine.
#
# Run: bash plugins/statusline/lib/burn-math.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BURN_MATH="$SCRIPT_DIR/burn-math.sh"
. "$BURN_MATH"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# No numeric-tolerant check_num here (unlike burn-tick.test.sh's): every
# expected value below is engineered to be exactly representable in binary
# float (power-of-two decimal fractions, or values landing on a discrete
# cap/NA branch), because all three of burn_metrics's outputs have a
# contract-FIXED print format (TODAY: integer or NA; PACE: an explicit
# decimal-place rule; TREND: integer) -- unlike burn-tick's cost/rate
# fields, which have no stated format and so need tolerance. burn-theme's
# accepted suite likewise has no check_num, for the same reason: it is
# sibling-shape when the contract has no free-floating decimal, not a
# fixed requirement of every suite.

# run(func, arg...): invokes the named function, capturing stdout in $OUT,
# the return code in $RC, and stderr in $ERR. Generic over all three
# functions under test (unlike a single-function suite's `call`).
run() { # func arg1 arg2 ...
  local fn="$1"; shift
  local errfile="$TMPROOT/.err-$$-$RANDOM"
  OUT=$("$fn" "$@" 2>"$errfile")
  RC=$?
  ERR=$(cat "$errfile" 2>/dev/null)
  rm -f "$errfile"
}

# field_of(value, idx): the idx'th space-separated field of a captured
# "TODAY PACE TREND" stdout string.
field_of() { # value idx
  printf '%s\n' "$1" | awk -v i="$2" '{print $i}'
}

# ============================================================================
# 1. burn_day_start_epoch NOW SECS_INTO_LOCAL_DAY DAY_START_HOUR
#
# day-start-hour-seconds = DAY_START_HOUR*3600; midnight = NOW -
# SECS_INTO_LOCAL_DAY; candidate = midnight + day-start-hour-seconds.
# SECS_INTO_LOCAL_DAY >= threshold -> today's candidate; otherwise ->
# candidate - 86400 (yesterday's). All hand-verified against this arithmetic.
# ============================================================================

# 1a. Ordinary case: NOW is well after today's 2am day-start.
run burn_day_start_epoch 1000000 36000 2
check "ordinary (after 2am threshold): returns rc 0" "$RC" "0"
check "ordinary (after 2am threshold): today's day-start" "$OUT" "971200"

# 1b. NOW is before today's 2am day-start -- yesterday's day-start, and it
#     must not be a future instant relative to NOW.
run burn_day_start_epoch 1000000 3600 2
check "before threshold (1am, hour=2): yesterday's day-start" "$OUT" "917200"

# 1c. Exact boundary: SECS_INTO_LOCAL_DAY == DAY_START_HOUR*3600. The
#     half-open convention means the boundary second belongs to the NEW
#     day, so this must resolve to TODAY's day-start (== NOW itself here),
#     not yesterday's.
run burn_day_start_epoch 1000000 7200 2
check "exact boundary (secs-into-day == hour*3600): today's day-start, not yesterday's" "$OUT" "1000000"

# 1d. DAY_START_HOUR = 0: local midnight is always the day-start, and
#     SECS_INTO_LOCAL_DAY (always >= 0) is always "at or after" the
#     threshold, so it is always today's midnight, never yesterday's.
run burn_day_start_epoch 1000000 50000 0
check "DAY_START_HOUR=0: today's local midnight" "$OUT" "950000"

# 1e/1f. DAY_START_HOUR = 23: the last second of the day (86399) is at/after
#     the threshold (today); the first second (0) is before it (yesterday).
#     The two results are exactly one second apart, as they must be.
run burn_day_start_epoch 1000000 86399 23
check "DAY_START_HOUR=23, secs=86399 (last sec of day): today's day-start" "$OUT" "996401"
run burn_day_start_epoch 1000000 0 23
check "DAY_START_HOUR=23, secs=0 (midnight): yesterday's day-start" "$OUT" "996400"

# 1g. Errors: non-numeric arguments are "cannot compute" -- echo nothing,
#     return 1, regardless of which argument is bad.
run burn_day_start_epoch abc 36000 2
check "non-numeric NOW: rc 1" "$RC" "1"
check "non-numeric NOW: echoes nothing" "$OUT" ""
run burn_day_start_epoch 1000000 abc 2
check "non-numeric SECS_INTO_LOCAL_DAY: rc 1" "$RC" "1"
check "non-numeric SECS_INTO_LOCAL_DAY: echoes nothing" "$OUT" ""
run burn_day_start_epoch 1000000 36000 abc
check "non-numeric DAY_START_HOUR: rc 1" "$RC" "1"
check "non-numeric DAY_START_HOUR: echoes nothing" "$OUT" ""

echo "--- section 1 (burn_day_start_epoch) done: FAILED=$FAILED ---"

# ============================================================================
# 2. burn_awake_seconds A B DAY_START_EPOCH SLEEP_SECONDS
#
# Every expected value below is hand-walked against $_BURN_AWK_AWAKE (the
# docblock's own authoritative algorithm), verified independently with a
# scratch awk run before being hardcoded here.
# ============================================================================

# 2a/2b. Output: "Zero when B <= A" -- a normal (non-error) result, rc 0.
run burn_awake_seconds 50000 50000 86400 1000
check "B == A: echoes 0" "$OUT" "0"
check "B == A: rc 0 (not an error)" "$RC" "0"
run burn_awake_seconds 50000 40000 86400 1000
check "B < A: echoes 0" "$OUT" "0"

# 2c. SLEEP_SECONDS = 0: degenerates to plain calendar time -- awake is
#     exactly B-A regardless of DAY_START_EPOCH's phase. Must not divide by
#     zero or misbehave (the edge case the contract calls out by name).
run burn_awake_seconds 0 86400 1 0
check "SLEEP_SECONDS=0, one day: awake = full 86400" "$OUT" "86400"
run burn_awake_seconds 12345 999999 555 0
check "SLEEP_SECONDS=0, arbitrary span: awake = B-A exactly" "$OUT" "987654"

# 2d. SLEEP_SECONDS = 86399: one awake second per day; must stay finite,
#     never divide by zero. Two independent phases confirm the DAY_START_EPOCH
#     value only phases the grid (86400 vs 3600 offsets, same structure).
run burn_awake_seconds 0 86400 86400 86399
check "SLEEP_SECONDS=86399, one day, phase 0: exactly 1 awake second" "$OUT" "1"
run burn_awake_seconds 3600 90000 3600 86399
check "SLEEP_SECONDS=86399, one day, phase 3600: exactly 1 awake second" "$OUT" "1"
run burn_awake_seconds 500000 604800 86400 86399
check "SLEEP_SECONDS=86399, multi-day span: 2 awake seconds (one per day boundary crossed)" "$OUT" "2"

# 2e. Half-open [A,B) at a day-start boundary, WITH sleep in effect so the
#     boundary second's awake/asleep status actually differs day to day:
#     [86399,86400) is the last (awake) second of day 0; [86400,86401) is
#     the first (asleep, sleep=1000) second of day 1. Spanning exactly this
#     boundary must count the awake second once, never twice or zero times.
run burn_awake_seconds 86399 86401 86400 1000
check "half-open day-start boundary: awake second counted exactly once" "$OUT" "1"

# 2f. A starting inside the sleep window: awake starts counts from the end
#     of sleep, same total as starting exactly at day-start (sleep is a
#     fixed clock-time window, not relative to A).
run burn_awake_seconds 1000 86400 86400 28800
check "A starts inside sleep window: skips forward to end of sleep" "$OUT" "57600"

# 2g. Multi-day span where B lands inside the NEXT day's sleep window:
#     that day's segment contributes 0 -- the degenerate-slice shape.
run burn_awake_seconds 0 100000 86400 28800
check "B lands inside next day's sleep window: that day contributes 0" "$OUT" "57600"

# 2h. Two full days, sleep aligned: two full awake segments.
run burn_awake_seconds 0 172800 86400 28800
check "two full days: awake = 2 * (86400-28800)" "$OUT" "115200"

# 2i. A exactly at a day-start (x=0 case), one full aligned day.
run burn_awake_seconds 86400 172800 86400 1000
check "A exactly at day-start, one aligned day: awake = 86400-1000" "$OUT" "85400"

# 2j. Invariant: DAY_START_EPOCH's absolute value is irrelevant -- only its
#     value mod 86400 (the phase) matters. Two DAY_START_EPOCH values with
#     the same phase must give identical results, at phase 0 and at a
#     non-zero phase.
run burn_awake_seconds 0 200000 86400 20000
r1="$OUT"
run burn_awake_seconds 0 200000 864000 20000
check "DAY_START_EPOCH phase invariant (phase 0, two multiples of 86400 apart)" "$OUT" "$r1"
run burn_awake_seconds 0 200000 3600 20000
r2="$OUT"
run burn_awake_seconds 0 200000 867600 20000
check "DAY_START_EPOCH phase invariant (phase 3600, two multiples of 86400 apart)" "$OUT" "$r2"

# 2k. Errors: DAY_START_EPOCH <= 0 is "cannot compute" -- echo nothing,
#     return 1. Tested at the boundary (0) and clearly below it.
run burn_awake_seconds 0 86400 0 1000
check "DAY_START_EPOCH == 0: rc 1" "$RC" "1"
check "DAY_START_EPOCH == 0: echoes nothing" "$OUT" ""
run burn_awake_seconds 0 86400 -100 1000
check "DAY_START_EPOCH < 0: rc 1" "$RC" "1"
check "DAY_START_EPOCH < 0: echoes nothing" "$OUT" ""

# 2l. Errors: non-numeric arguments are "cannot compute" regardless of
#     position.
run burn_awake_seconds abc 86400 86400 1000
check "non-numeric A: rc 1" "$RC" "1"
check "non-numeric A: echoes nothing" "$OUT" ""
run burn_awake_seconds 0 86400 86400 abc
check "non-numeric SLEEP_SECONDS: rc 1" "$RC" "1"
check "non-numeric SLEEP_SECONDS: echoes nothing" "$OUT" ""

echo "--- section 2 (burn_awake_seconds) done: FAILED=$FAILED ---"

# ============================================================================
# 3. burn_metrics USED FRAC NOW RESET DAY_START_EPOCH SLEEP_SECONDS
#
# Baseline scenario reused across most cases below (SLEEP_SECONDS=0, so the
# "line" reduces to a plain proportion of wall-clock seconds and the
# awake-walk complexity is isolated to section 2):
#   RESET = 604800 (a bare 7-day week; week_start = RESET-604800 = 0)
#   DAY_START_EPOCH = 189000 -> checkpoint(t) = 100*t/604800 is EXACTLY
#     0.03125*(t/189) whenever t is a multiple of 189 (604800 = 189*3200,
#     and 0.03125 = 1/32 is exactly representable in binary float), so
#     checkpoint_start = 31.25 exactly, with zero floating residue.
#   A full, uncapped day-slice is always exactly 100/7 weekly points wide,
#   so TODAY (for that shape) reduces algebraically to
#     TODAY = 7*(checkpoint_start - (USED+FRAC)) + 100
#   -- every case below picks USED so that (checkpoint_start-(USED+FRAC))
#   is a whole number, making TODAY an exact integer with no rounding-mode
#   ambiguity at all.
# ============================================================================

# --- 3a. Errors -------------------------------------------------------------

# Non-numeric arguments, at three different positions.
run burn_metrics abc 0 189000 604800 189000 0
check "non-numeric USED: rc 1" "$RC" "1"
check "non-numeric USED: echoes nothing" "$OUT" ""
run burn_metrics 50 0 abc 604800 189000 0
check "non-numeric NOW: rc 1" "$RC" "1"
check "non-numeric NOW: echoes nothing" "$OUT" ""
run burn_metrics 50 0 189000 604800 189000 abc
check "non-numeric SLEEP_SECONDS: rc 1" "$RC" "1"
check "non-numeric SLEEP_SECONDS: echoes nothing" "$OUT" ""

# RESET <= NOW: tested at the boundary (equal) and clearly below it.
run burn_metrics 50 0 604800 604800 189000 0
check "RESET == NOW: rc 1" "$RC" "1"
check "RESET == NOW: echoes nothing" "$OUT" ""
run burn_metrics 50 0 604800 604700 189000 0
check "RESET < NOW: rc 1" "$RC" "1"
check "RESET < NOW: echoes nothing" "$OUT" ""

# DAY_START_EPOCH <= 0: tested at the boundary (0) and clearly below it.
run burn_metrics 50 0 189000 604800 0 0
check "DAY_START_EPOCH == 0: rc 1" "$RC" "1"
check "DAY_START_EPOCH == 0: echoes nothing" "$OUT" ""
run burn_metrics 50 0 189000 604800 -1 0
check "DAY_START_EPOCH < 0: rc 1" "$RC" "1"
check "DAY_START_EPOCH < 0: echoes nothing" "$OUT" ""

# --- 3b. PACE ----------------------------------------------------------------

# USED >= 100 (limit reached): PACE is 0, never negative. Exact regardless
# of days-left since the numerator (100-USED) is 0. Rendered as "0.0": the
# format rule's below-10 branch applies to zero the same as any other value.
run burn_metrics 100 0 189000 604800 189000 0
check "USED==100: PACE is 0" "$(field_of "$OUT" 2)" "0.0"

# Under one awake-day to the reset: days-left clamps to 1, so PACE is
# exactly the remainder (100-USED). RESET is 3600s (1hr) after NOW.
run burn_metrics 63 0 601200 604800 189000 0
check "under a day to reset: days-left clamps to 1, PACE = 100-USED = 37" "$(field_of "$OUT" 2)" "37"

# Format rule, below-10 branch (clamped-day case): one decimal, "7.0" not "7".
run burn_metrics 93 0 601200 604800 189000 0
check "PACE below 10 (clamped day): one-decimal format '7.0'" "$(field_of "$OUT" 2)" "7.0"

# Format rule, a genuinely fractional below-10 value: "9.5", not "9.50" or "10".
run burn_metrics 90.5 0 601200 604800 189000 0
check "PACE below 10, fractional (clamped day): '9.5'" "$(field_of "$OUT" 2)" "9.5"

# Format rule, exactly at the 10 boundary (clamped-day case): integer "10",
# not "10.0".
run burn_metrics 90 0 601200 604800 189000 0
check "PACE exactly 10 (clamped day): integer format '10', not '10.0'" "$(field_of "$OUT" 2)" "10"

# Format rule, exactly at the 10 boundary via the GENERAL (non-clamped)
# formula: days-left = (604800-189000)/86400 = 4.8125 (not clamped, >1);
# (100-51.875)/4.8125 = 10 exactly.
run burn_metrics 51.875 0 189000 604800 189000 0
check "PACE exactly 10 (non-clamped days-left=4.8125): integer '10'" "$(field_of "$OUT" 2)" "10"

# SLEEP_SECONDS = 86399 (one awake second per day): PACE must stay finite,
# never divide by zero. NOW=500000, RESET=604800, DAY_START_EPOCH=86400 ->
# awake_seconds(NOW,RESET)=2 (verified in section 2), one awake-day = 1
# second, so days-left = 2/1 = 2 (not clamped). PACE = (100-60)/2 = 20.
run burn_metrics 60 0 500000 604800 86400 86399
check "SLEEP_SECONDS=86399: PACE stays finite (20)" "$(field_of "$OUT" 2)" "20"

echo "--- section 3a/3b (burn_metrics errors, PACE) done: FAILED=$FAILED ---"

# --- 3c. TODAY -----------------------------------------------------------
# All of these use DAY_START_EPOCH=189000 (checkpoint_start = 31.25 exactly,
# see the section-3 preamble) with an uncapped full-day slice, so
# TODAY = 7*(31.25 - (USED+FRAC)) + 100 exactly, no rounding ambiguity.

# 100 = the whole slice is still ahead: USED+FRAC == checkpoint_start
# exactly (nothing spent yet within today's slice).
run burn_metrics 31.25 0 189000 604800 189000 0
check "TODAY: USED == checkpoint_start exactly -> 100 (whole slice ahead)" "$(field_of "$OUT" 1)" "100"

# CAPPED at 100, never above: USED+FRAC well BELOW checkpoint_start (running
# behind the line) would put the raw ratio at 240% -- must clamp to 100.
run burn_metrics 11.25 0 189000 604800 189000 0
check "TODAY: running far behind checkpoint_start -> capped at 100, not 240" "$(field_of "$OUT" 1)" "100"

# Negative, NOT capped below: USED+FRAC well past checkpoint_end (eating
# tomorrow's slice) -> exactly -250 by the formula above.
run burn_metrics 81.25 0 189000 604800 189000 0
check "TODAY: well past tonight's checkpoint -> -250, not capped" "$(field_of "$OUT" 1)" "-250"

# 0 = exactly on tonight's checkpoint, using the RESET-capped-slice shape
# (DAY_START_EPOCH=529200, DAY_START_EPOCH+86400=615600 > RESET=604800, so
# checkpoint_end is the reset itself: L(RESET)=100 exactly, clean by
# construction). USED=100 hits this AND the USED>=100 PACE=0 rule at once.
run burn_metrics 100 0 529200 604800 529200 0
check "TODAY: USED == checkpoint_end (reset-capped slice) -> exactly 0" "$(field_of "$OUT" 1)" "0"
check "TODAY: same call, PACE also 0 (USED>=100 rule)" "$(field_of "$OUT" 2)" "0.0"

# NA: today's slice is degenerate (<=0.1 weekly points). slice = 604
# seconds = 100*604/604800 = 0.09987%, just under the 0.1 threshold.
run burn_metrics 50 0 604196 604800 604196 0
check "TODAY: slice = 604s (0.0999%, <= 0.1 threshold) -> NA" "$(field_of "$OUT" 1)" "NA"

# Just OVER the threshold: slice = 605 seconds = 0.10003%, must NOT be NA --
# a numeric TODAY comes back instead. (0.1% of a week = 604.8s, not an
# integer, so 604/605 straddle the threshold as closely as integer epoch
# seconds allow.)
run burn_metrics 50 0 604195 604800 604195 0
today605=$(field_of "$OUT" 1)
check "TODAY: slice = 605s (0.10003%, just over threshold) -> numeric, not NA" \
  "$([[ "$today605" =~ ^-?[0-9]+$ ]] && echo yes || echo no)" "yes"

# FRAC participates in TODAY only -- PACE and TREND must be BYTE-IDENTICAL
# between two calls that differ solely in FRAC, while TODAY must actually
# change (the 0.5 FRAC delta is a 3.5-weekly-point swing in TODAY's
# formula, far too large to coincidentally round to the same integer).
run burn_metrics 50 0 189000 604800 189000 0
today_f0="$(field_of "$OUT" 1)"; pace_f0="$(field_of "$OUT" 2)"; trend_f0="$(field_of "$OUT" 3)"
run burn_metrics 50 0.5 189000 604800 189000 0
today_f5="$(field_of "$OUT" 1)"; pace_f5="$(field_of "$OUT" 2)"; trend_f5="$(field_of "$OUT" 3)"
check "FRAC isolation: PACE identical across FRAC=0 vs FRAC=0.5" "$pace_f5" "$pace_f0"
check "FRAC isolation: TREND identical across FRAC=0 vs FRAC=0.5" "$trend_f5" "$trend_f0"
if [[ "$today_f5" != "$today_f0" ]]; then
  echo "PASS  FRAC isolation: TODAY differs when FRAC differs"
else
  echo "FAIL  FRAC isolation: TODAY differs when FRAC differs -> both '$today_f0'"; FAILED=1
fi

# --- 3d. TREND -------------------------------------------------------------
# L(NOW) = 100*NOW/604800 with week_start=0, RESET=604800, SLEEP=0.
# NOW=189000 -> L(NOW) = 31.25 exactly (same clean value as checkpoint_start
# above, same construction). TREND = USED - L(NOW).

# Positive = ahead of the glide (will cap before reset): USED > line.
run burn_metrics 41.25 0 189000 604800 189000 0
check "TREND: USED(41.25) > line(31.25) -> +10, positive (ahead)" "$(field_of "$OUT" 3)" "10"

# Negative = behind it (will leave subscription unused): USED < line.
run burn_metrics 21.25 0 189000 604800 189000 0
check "TREND: USED(21.25) < line(31.25) -> -10, negative (behind)" "$(field_of "$OUT" 3)" "-10"

# Exactly on the line: TREND is exactly 0.
run burn_metrics 31.25 0 189000 604800 189000 0
check "TREND: USED == line exactly -> 0" "$(field_of "$OUT" 3)" "0"

# NOW before the week start (clock skew): the line clamps to 0, not
# negative, so TREND == USED exactly (USED - 0).
run burn_metrics 25 0 -1000 604800 189000 0
check "TREND: NOW before week start -> line clamps to 0, TREND = USED = 25" "$(field_of "$OUT" 3)" "25"

echo "--- section 3c/3d (burn_metrics TODAY, TREND) done: FAILED=$FAILED ---"

# --- 3e. Clean I/O -----------------------------------------------------------

# Success: stdout is exactly three space-separated fields, nothing else;
# stderr is empty.
run burn_metrics 41.25 0 189000 604800 189000 0
check "clean I/O: stdout is exactly three whitespace-separated fields" \
  "$([[ "$OUT" =~ ^-?[A-Za-z0-9.]+\ -?[A-Za-z0-9.]+\ -?[A-Za-z0-9.]+$ ]] && echo yes || echo no)" "yes"
check "clean I/O: stderr is empty in normal operation" "$ERR" ""

# Errors: no diagnostics on stdout ever, and stdout is completely empty (not
# even a partial field) on a cannot-compute input.
run burn_metrics abc 0 189000 604800 189000 0
check "error path: stdout is completely empty, not a partial result" "$OUT" ""
check "error path: no diagnostic text on stdout" "$([[ "$OUT" == "" ]] && echo yes || echo no)" "yes"

# --- 3f. Invariant: burn_metrics forks awk EXACTLY ONCE per call, and never
#     shells out to burn_awake_seconds or forks date/cat (PATH-shim harness,
#     mirroring burn-tick.test.sh's own fork-budget pattern). -----------------
SHIM_DIR="$TMPROOT/fork-shim"; mkdir -p "$SHIM_DIR"
for _tool in awk date cat; do
  _real=$(command -v "$_tool" 2>/dev/null) || continue
  printf '#!/bin/bash\necho "%s" >> "${FORK_LOG:-/dev/null}"\nexec "%s" "$@"\n' \
    "$_tool" "$_real" > "$SHIM_DIR/$_tool"
  chmod +x "$SHIM_DIR/$_tool"
done

# run_forkcheck(...): sources burn-math.sh fresh in a subshell with the shim
# tools first on PATH, calls burn_metrics once, and echoes the fork log path.
run_forkcheck() { # used frac now reset day_start_epoch sleep_seconds
  local log="$TMPROOT/fork-$$-$RANDOM.log"
  : > "$log"
  PATH="$SHIM_DIR:$PATH" FORK_LOG="$log" \
    bash -c '. "$1"; burn_metrics "$2" "$3" "$4" "$5" "$6" "$7"' _ \
    "$BURN_MATH" "$1" "$2" "$3" "$4" "$5" "$6" >/dev/null 2>&1
  echo "$log"
}

log=$(run_forkcheck 41.25 0 189000 604800 189000 0)
check "burn_metrics forks awk at most once per call" \
  "$([ "$(grep -cxF awk "$log")" -le 1 ] && echo yes || echo no)" "yes"
check "burn_metrics never forks date" "$(grep -cxF date "$log")" "0"
check "burn_metrics never forks cat" "$(grep -cxF cat "$log")" "0"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
