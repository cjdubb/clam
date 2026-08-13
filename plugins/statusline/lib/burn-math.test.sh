#!/bin/bash
# Behavioral test for burn-math.sh's WORKING-WEEK burn pacing: the schedule
# normalizer (burn_work_parse), the working-seconds primitive
# (burn_work_seconds), and the two trend functions built on them
# (burn_week_trend, burn_linear_trend). Covers the half-open [A,B) day-boundary
# invariant, the anchor-phased day walk, the day-mask notations and every
# documented "cannot compute" error.
#
# Contract: B01 work-window-seconds and B02 window-trend (plan
# 001-statusline-glance-uplift), docblocks in burn-math.sh. Every expected
# number is hand-derived from those docblocks -- never from calling `date` --
# so each case is exactly reproducible on any machine.
#
# The awake-hours model this file used to cover as well (burn_day_start_epoch,
# burn_awake_seconds, burn_metrics; contract B01 burn-math, plan
# 001-statusline-burnrate-uplift) is RETIRED by B05 line2-groups: the %t and
# %/d figures those functions computed answer none of the seven glance-items
# and leave line 2 with the burnrate line, so the functions go and their three
# sections go with them. They are deleted rather than relaxed -- there is no
# call site left, and a suite pinning a deleted function is a collection error,
# not coverage. Section numbering is left at 4-6 so the surviving sections keep
# the identities the other suites' comments cite them by.
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
# Shared fork-budget shim.
#
# Contract: B05 line2-groups (plan 001-statusline-glance-uplift) RETIRES the
# awake-hours model outright -- burn_day_start_epoch, burn_awake_seconds and
# burn_metrics are deleted from burn-math.sh along with the %t and %/d figures
# they fed, so the three sections that covered them are deleted with them
# rather than relaxed. What replaces them is the working-week model in
# sections 4-6 below, which was already covering the same glance-items.
#
# The PATH-shim directory those sections use for their own fork budgets was
# built inside the retired section 3f; it is hoisted here so it outlives them.
# ============================================================================
SHIM_DIR="$TMPROOT/fork-shim"; mkdir -p "$SHIM_DIR"
for _tool in awk date cat; do
  _real=$(command -v "$_tool" 2>/dev/null) || continue
  printf '#!/bin/bash\necho "%s" >> "${FORK_LOG:-/dev/null}"\nexec "%s" "$@"\n' \
    "$_tool" "$_real" > "$SHIM_DIR/$_tool"
  chmod +x "$SHIM_DIR/$_tool"
done

# ============================================================================
# Working-week pacing model (plan 001-statusline-glance-uplift).
#
# Sections 4-6 cover B01 (burn_work_parse, burn_work_seconds) and B02
# (burn_week_trend, burn_linear_trend). Every expected number below is
# hand-derived from the contract docblocks in burn-math.sh -- never from
# `date`, so each case is exactly reproducible on any machine.
#
# Shared fixture grid used throughout: ANCHOR_MIDNIGHT=0 with
# ANCHOR_WEEKDAY=1, i.e. epoch 0 is local midnight on a Monday. Day k then
# begins at 86400*k and has ISO weekday ((k mod 7) + 1):
#   k=0 Mon, k=1 Tue, k=2 Wed, k=3 Thu, k=4 Fri, k=5 Sat, k=6 Sun.
# The default schedule is Mon-Fri 09:00-17:00 -> DAYMASK=31,
# START_SEC=32400, END_SEC=61200, a 28800-second window on each of five
# days, so a full week holds exactly 5*28800 = 144000 working seconds.
# ============================================================================

# generic fork-budget harness, shaped like run_forkcheck above but taking the
# function name and its arguments, so all four new functions can share it.
run_forkcheck_fn() { # func arg...
  local log="$TMPROOT/fork-$$-$RANDOM.log"
  : > "$log"
  PATH="$SHIM_DIR:$PATH" FORK_LOG="$log" \
    bash -c 'f="$2"; . "$1"; shift 2; "$f" "$@"' _ "$BURN_MATH" "$@" \
    >/dev/null 2>&1
  echo "$log"
}

# ============================================================================
# 4. burn_work_parse DAYS START END
#
# Output is "DAYMASK START_SEC END_SEC": the mask sets bit (weekday-1) for
# each listed ISO weekday, and the two offsets are the hours expressed as
# seconds-of-day (START*3600, END*3600).
# ============================================================================

# 4a. Ranges, lists, and mixed forms -- the three notations the contract
#     names by example.
run burn_work_parse 1-5 9 17
check "parse 1-5 9 17: rc 0" "$RC" "0"
check "parse range '1-5' (Mon-Fri) -> mask 31, 09:00, 17:00" "$OUT" "31 32400 61200"
run burn_work_parse 1,3,5 9 17
check "parse list '1,3,5' (Mon/Wed/Fri) -> bits 0,2,4 = 21" "$OUT" "21 32400 61200"
run burn_work_parse 1-4,6 9 17
check "parse mixed '1-4,6' -> bits 0,1,2,3,5 = 47" "$OUT" "47 32400 61200"

# 4b. Boundary weekdays: 1 (Mon, lowest bit) and 7 (Sun, highest bit), each
#     alone -- "a single working day per week must work".
run burn_work_parse 1 9 17
check "parse single day '1' (Monday) -> mask 1" "$(field_of "$OUT" 1)" "1"
run burn_work_parse 7 9 17
check "parse single day '7' (Sunday) -> mask 64 (top bit)" "$(field_of "$OUT" 1)" "64"
run burn_work_parse 1-7 9 17
check "parse whole week '1-7' -> mask 127 (all seven bits)" "$(field_of "$OUT" 1)" "127"

# 4c. A mask is a SET: a repeated day, and overlapping ranges, contribute
#     their bit once and cannot double-count.
run burn_work_parse 1,1 9 17
check "parse repeated day '1,1': set semantics -> mask 1, not 2" "$(field_of "$OUT" 1)" "1"
run burn_work_parse 1-3,2-5 9 17
check "parse overlapping ranges '1-3,2-5' -> union mask 31" "$(field_of "$OUT" 1)" "31"

# 4d. Hour boundaries: START at its floor (0), END at its ceiling (24). The
#     full 0-24 window is the degenerate "whole day" case the contract
#     requires to work.
run burn_work_parse 1-7 0 24
check "parse full 0-24 window: rc 0" "$RC" "0"
check "parse full 0-24 window -> '127 0 86400'" "$OUT" "127 0 86400"
run burn_work_parse 1-5 23 24
check "parse minimal one-hour window at end of day -> '31 82800 86400'" "$OUT" "31 82800 86400"

# 4e. Errors: unparseable or out-of-range day lists. Echo nothing, return 1.
run burn_work_parse "" 9 17
check "parse empty DAYS: rc 1" "$RC" "1"
check "parse empty DAYS: echoes nothing" "$OUT" ""
run burn_work_parse abc 9 17
check "parse non-numeric DAYS: rc 1" "$RC" "1"
check "parse non-numeric DAYS: echoes nothing" "$OUT" ""
run burn_work_parse 1- 9 17
check "parse truncated range '1-': rc 1" "$RC" "1"
check "parse truncated range '1-': echoes nothing" "$OUT" ""
run burn_work_parse 0 9 17
check "parse weekday 0 (below ISO range): rc 1" "$RC" "1"
check "parse weekday 0: echoes nothing" "$OUT" ""
run burn_work_parse 8 9 17
check "parse weekday 8 (above ISO range): rc 1" "$RC" "1"
run burn_work_parse 0-5 9 17
check "parse range starting below ISO range '0-5': rc 1" "$RC" "1"
run burn_work_parse 5-8 9 17
check "parse range ending above ISO range '5-8': rc 1" "$RC" "1"

# 4e2. Errors: malformed day lists that reach this function straight from
#      user config (CLAM_STATUSLINE_WORK_DAYS is an environment variable, so
#      nothing validates these first). Each is unparseable under the Errors
#      clause -- it names no weekday set at all, as opposed to naming an
#      empty one -- so each must echo nothing, return 1, and stay silent on
#      stderr.
#
#      A descending range names no days: its end precedes its start.
run burn_work_parse 5-1 9 17
check "parse descending range '5-1': rc 1" "$RC" "1"
check "parse descending range '5-1': echoes nothing" "$OUT" ""
check "parse descending range '5-1': stderr empty" "$ERR" ""

#      An empty list element is not a weekday and cannot be normalised into
#      one -- interior, trailing, and leading are the same defect.
run burn_work_parse 1,,3 9 17
check "parse empty element '1,,3': rc 1" "$RC" "1"
check "parse empty element '1,,3': echoes nothing" "$OUT" ""
check "parse empty element '1,,3': stderr empty" "$ERR" ""
run burn_work_parse 1,3, 9 17
check "parse trailing comma '1,3,': rc 1" "$RC" "1"
check "parse trailing comma '1,3,': echoes nothing" "$OUT" ""
run burn_work_parse ,1,3 9 17
check "parse leading comma ',1,3': rc 1" "$RC" "1"
check "parse leading comma ',1,3': echoes nothing" "$OUT" ""

#      A range bound that is not a weekday number is unparseable for the
#      same reason a bare non-numeric DAYS is, at either end of the range.
run burn_work_parse a-5 9 17
check "parse non-numeric range start 'a-5': rc 1" "$RC" "1"
check "parse non-numeric range start 'a-5': echoes nothing" "$OUT" ""
run burn_work_parse 1-b 9 17
check "parse non-numeric range end '1-b': rc 1" "$RC" "1"
check "parse non-numeric range end '1-b': echoes nothing" "$OUT" ""

# 4f. Errors: hour arguments. Non-numeric, out of range, and END <= START.
run burn_work_parse 1-5 abc 17
check "parse non-numeric START: rc 1" "$RC" "1"
check "parse non-numeric START: echoes nothing" "$OUT" ""
run burn_work_parse 1-5 9 abc
check "parse non-numeric END: rc 1" "$RC" "1"
run burn_work_parse 1-5 -1 17
check "parse START below 0: rc 1" "$RC" "1"
run burn_work_parse 1-5 24 24
check "parse START above 23: rc 1" "$RC" "1"
run burn_work_parse 1-5 9 0
check "parse END below 1: rc 1" "$RC" "1"
run burn_work_parse 1-5 9 25
check "parse END above 24: rc 1" "$RC" "1"
run burn_work_parse 1-5 9 9
check "parse END == START: rc 1" "$RC" "1"
check "parse END == START: echoes nothing" "$OUT" ""
run burn_work_parse 1-5 17 9
check "parse END < START: rc 1" "$RC" "1"

# 4g. Clean I/O: nothing is EVER written to stderr, on the success path or
#     any error path -- this file's output reaches the user's terminal.
run burn_work_parse 1-5 9 17
check "parse success: stderr empty" "$ERR" ""
run burn_work_parse 9 9 17
check "parse error: stderr empty" "$ERR" ""

# 4h. Purity: identical arguments give identical output.
run burn_work_parse 1-4,6 8 18
p1="$OUT"
run burn_work_parse 1-4,6 8 18
check "parse purity: identical arguments -> identical output" "$OUT" "$p1"

# 4i. Fork budget: at most one awk, and never `date`.
log=$(run_forkcheck_fn burn_work_parse 1-5 9 17)
check "burn_work_parse forks awk at most once" \
  "$([ "$(grep -cxF awk "$log")" -le 1 ] && echo yes || echo no)" "yes"
check "burn_work_parse never forks date" "$(grep -cxF date "$log")" "0"

echo "--- section 4 (burn_work_parse) done: FAILED=$FAILED ---"

# ============================================================================
# 4W. burn_work_parse DAYS whitespace tolerance (B13 work-days-whitespace)
#
# CLAM_STATUSLINE_WORK_DAYS is hand-typed into a shell profile, so the
# contract's Inputs clause requires spaces (0x20) and tabs (0x09) to be
# stripped from DAYS at ANY position before any validation runs: "1, 3" is
# the same schedule as "1,3". The Errors and Edge-cases clauses bound that
# tolerance in the other direction -- stripping softens nothing, so an empty
# or all-whitespace DAYS is still unparseable, "1, ,3" still fails on its
# empty token, and "1 2" strips to "12", which is out of ISO range.
#
# Expected masks are the same hand-derived ones section 4 uses: bit
# (weekday-1) per listed day, offsets START*3600 / END*3600.
# ============================================================================

TAB=$'\t'

# 4W-a. Inputs: the motivating case -- a stray space after a comma parses as
#       if it were absent, and the FULL three-field output is unchanged.
run burn_work_parse "1, 3" 9 17
check "ws: '1, 3' rc 0" "$RC" "0"
check "ws: '1, 3' -> same schedule as '1,3' (mask 5), offsets unchanged" \
  "$OUT" "5 32400 61200"
ws_spaced="$OUT"
run burn_work_parse "1,3" 9 17
check "ws: '1, 3' output is identical to the unspaced '1,3' output" "$ws_spaced" "$OUT"

# 4W-b. Edge cases: spaces and tabs at ANY position -- interior, leading,
#       trailing, around a range hyphen, and tab in place of space. Each of
#       the four forms the contract names by example.
run burn_work_parse " 1-5 " 9 17
check "ws: leading+trailing spaces ' 1-5 ' -> mask 31" "$OUT" "31 32400 61200"
run burn_work_parse "1 - 5" 9 17
check "ws: spaces around the range hyphen '1 - 5' -> mask 31" "$OUT" "31 32400 61200"
run burn_work_parse "1,${TAB}3" 9 17
check "ws: tab after comma '1,<TAB>3' -> mask 5" "$OUT" "5 32400 61200"
run burn_work_parse "${TAB}1,5" 9 17
check "ws: leading tab '<TAB>1,5' -> mask 17" "$OUT" "17 32400 61200"
run burn_work_parse "  1 ,  4 - 6 ,${TAB}7  " 9 17
check "ws: spaces and tabs scattered everywhere '1,4-6,7' -> mask 121" \
  "$OUT" "121 32400 61200"
run burn_work_parse "1${TAB} - ${TAB}7" 0 24
check "ws: mixed space/tab range with the full 0-24 window -> '127 0 86400'" \
  "$OUT" "127 0 86400"

# 4W-c. Errors: stripping is not a validator. An all-whitespace DAYS names no
#       weekday set at all -- exactly like the empty string, which section 4e
#       already pins -- so it stays rc 1 with nothing echoed.
run burn_work_parse " " 9 17
check "ws: single-space DAYS: rc 1" "$RC" "1"
check "ws: single-space DAYS: echoes nothing" "$OUT" ""
run burn_work_parse "$TAB" 9 17
check "ws: single-tab DAYS: rc 1" "$RC" "1"
check "ws: single-tab DAYS: echoes nothing" "$OUT" ""
run burn_work_parse "  ${TAB} ${TAB} " 9 17
check "ws: all-whitespace DAYS: rc 1" "$RC" "1"
check "ws: all-whitespace DAYS: echoes nothing" "$OUT" ""

# 4W-d. Errors: stripping cannot RESCUE a malformed list. The two cases the
#       Errors clause names by name, plus the leading/trailing-comma and
#       descending-range defects surviving with whitespace present.
run burn_work_parse "1, ,3" 9 17
check "ws: '1, ,3' still fails on its empty token: rc 1" "$RC" "1"
check "ws: '1, ,3' echoes nothing" "$OUT" ""
run burn_work_parse "1 2" 9 17
check "ws: '1 2' strips to '12', out of ISO range: rc 1" "$RC" "1"
check "ws: '1 2' echoes nothing" "$OUT" ""
run burn_work_parse " , 1 , 3 " 9 17
check "ws: leading comma survives stripping ', 1 , 3': rc 1" "$RC" "1"
check "ws: leading comma survives stripping: echoes nothing" "$OUT" ""
run burn_work_parse "1 , 3 , " 9 17
check "ws: trailing comma survives stripping '1 , 3 ,': rc 1" "$RC" "1"
run burn_work_parse " 5 - 1 " 9 17
check "ws: descending range survives stripping ' 5 - 1 ': rc 1" "$RC" "1"
run burn_work_parse " a b c " 9 17
check "ws: non-numeric DAYS survives stripping ' a b c ': rc 1" "$RC" "1"
run burn_work_parse " 8 " 9 17
check "ws: out-of-range weekday survives stripping ' 8 ': rc 1" "$RC" "1"
run burn_work_parse "1 -" 9 17
check "ws: truncated range survives stripping '1 -': rc 1" "$RC" "1"

# 4W-e. Errors: the stripping clause is scoped to DAYS. START and END keep
#       their existing "non-numeric input -> rc 1" error path unchanged; a
#       spaced hour is not rescued.
run burn_work_parse 1-5 " 9" 17
check "ws: spaced START ' 9' is NOT stripped -- existing error path: rc 1" "$RC" "1"
check "ws: spaced START ' 9': echoes nothing" "$OUT" ""
run burn_work_parse 1-5 9 "17 "
check "ws: spaced END '17 ' is NOT stripped -- existing error path: rc 1" "$RC" "1"
check "ws: spaced END '17 ': echoes nothing" "$OUT" ""

# 4W-f. Invariant: nothing is EVER written to stderr on the new path, success
#       or failure -- this file's output reaches the user's terminal.
run burn_work_parse "1, 3" 9 17
check "ws: stderr empty on the whitespace success path" "$ERR" ""
run burn_work_parse "  " 9 17
check "ws: stderr empty on the all-whitespace error path" "$ERR" ""
run burn_work_parse "1 2" 9 17
check "ws: stderr empty on the strips-to-out-of-range error path" "$ERR" ""

# 4W-g. Invariant: pure -- identical arguments give identical output.
run burn_work_parse " 1 - 4 , 6 " 8 18
w1="$OUT"
run burn_work_parse " 1 - 4 , 6 " 8 18
check "ws: purity -- identical whitespace arguments -> identical output" "$OUT" "$w1"
check "ws: purity case is a real parse (rc 0), not two identical failures" "$RC" "0"
check "ws: purity case parses to '1-4,6' 8-18 -> '47 28800 64800'" "$OUT" "47 28800 64800"

# 4W-h. Invariant: no fork. The strip must be a bash parameter expansion, so
#       the whitespace path must not reach for `tr` or `sed`, and must keep
#       B01's at-most-one-awk / never-date budget. Own shim dir so the
#       shared SHIM_DIR fixture above is left exactly as section 3 built it.
WS_SHIM_DIR="$TMPROOT/ws-fork-shim"; mkdir -p "$WS_SHIM_DIR"
for _tool in awk date cat tr sed; do
  _real=$(command -v "$_tool" 2>/dev/null) || continue
  printf '#!/bin/bash\necho "%s" >> "${FORK_LOG:-/dev/null}"\nexec "%s" "$@"\n' \
    "$_tool" "$_real" > "$WS_SHIM_DIR/$_tool"
  chmod +x "$WS_SHIM_DIR/$_tool"
done

run_ws_forkcheck() { # arg...
  local log="$TMPROOT/ws-fork-$$-$RANDOM.log"
  : > "$log"
  PATH="$WS_SHIM_DIR:$PATH" FORK_LOG="$log" \
    bash -c '. "$1"; shift; burn_work_parse "$@"' _ "$BURN_MATH" "$@" \
    >/dev/null 2>&1
  echo "$log"
}

log=$(run_ws_forkcheck " 1 , 3 - 5 " 9 17)
check "ws: whitespace parse never forks tr" "$(grep -cxF tr "$log")" "0"
check "ws: whitespace parse never forks sed" "$(grep -cxF sed "$log")" "0"
check "ws: whitespace parse never forks date" "$(grep -cxF date "$log")" "0"
check "ws: whitespace parse forks awk at most once" \
  "$([ "$(grep -cxF awk "$log")" -le 1 ] && echo yes || echo no)" "yes"

echo "--- section 4W (burn_work_parse whitespace, B13) done: FAILED=$FAILED ---"

# ============================================================================
# 5. burn_work_seconds A B ANCHOR_MIDNIGHT ANCHOR_WEEKDAY DAYMASK START_SEC END_SEC
#
# All values hand-walked on the Monday-epoch-0 grid described above.
# ============================================================================

# 5a. A whole calendar week holds exactly the five Mon-Fri windows.
run burn_work_seconds 0 604800 0 1 31 32400 61200
check "one calendar week, Mon-Fri 9-17: rc 0" "$RC" "0"
check "one calendar week, Mon-Fri 9-17: 5 * 28800 = 144000" "$OUT" "144000"

# 5b. "An interval spanning a full week counts each working day exactly
#     once" -- a week-long interval OFFSET into the middle of a working day
#     still totals exactly one week of working seconds (18000 of Monday's
#     window at the front, 10800 of the next Monday's at the back, plus four
#     whole Tue-Fri windows).
run burn_work_seconds 43200 648000 0 1 31 32400 61200
check "week-long interval offset to Monday noon: still exactly 144000" "$OUT" "144000"

# 5c. Eight days from Monday midnight span six working days, not five.
run burn_work_seconds 0 691200 0 1 31 32400 61200
check "eight-day interval: six working days = 172800" "$OUT" "172800"

# 5d. Outputs: zero when B <= A -- a normal result, rc 0, not an error.
run burn_work_seconds 100000 100000 0 1 31 32400 61200
check "B == A: echoes 0" "$OUT" "0"
check "B == A: rc 0 (not an error)" "$RC" "0"
run burn_work_seconds 100000 50000 0 1 31 32400 61200
check "B < A: echoes 0" "$OUT" "0"
check "B < A: rc 0 (not an error)" "$RC" "0"

# 5e. Outputs: zero when the mask is empty. (The Errors clause's "empty
#     resulting mask" is the PARSE failure; burn_work_seconds's Outputs
#     clause states this case explicitly as a zero.)
run burn_work_seconds 0 604800 0 1 0 32400 61200
check "empty DAYMASK: echoes 0" "$OUT" "0"
check "empty DAYMASK: rc 0" "$RC" "0"

# 5f. A single working day per week must work -- Sunday only (top bit).
run burn_work_seconds 0 604800 0 1 64 32400 61200
check "single working day (Sunday only): one window = 28800" "$OUT" "28800"

# 5g. Every day plus a full 0-24 window degenerates to plain calendar
#     seconds, and must not divide by zero.
run burn_work_seconds 0 604800 0 1 127 0 86400
check "all days, full 0-24 window: degenerates to calendar seconds 604800" "$OUT" "604800"
run burn_work_seconds 1000 5000 0 1 127 0 86400
check "all days, full window, sub-day interval: B-A exactly" "$OUT" "4000"

# 5h. A and B inside the same working window: the plain difference.
run burn_work_seconds 36000 39600 0 1 31 32400 61200
check "A and B inside one working window (Mon 10:00-11:00): 3600" "$OUT" "3600"

# 5i. A and B both in non-working time: zero. Once before the window opens
#     on a working day, once on a weekend day the mask excludes.
run burn_work_seconds 0 3600 0 1 31 32400 61200
check "interval before the window opens (Mon 00:00-01:00): 0" "$OUT" "0"
run burn_work_seconds 464400 468000 0 1 31 32400 61200
check "interval inside Saturday's working hours but Sat unmasked: 0" "$OUT" "0"

# 5j. Partial overlap: A inside Monday's window, B in Tuesday's non-working
#     small hours -- only Monday's tail counts.
run burn_work_seconds 36000 100000 0 1 31 32400 61200
check "A inside Mon window, B in Tue small hours: 61200-36000 = 25200" "$OUT" "25200"

# 5k. Half-open [A, B): a boundary second is counted exactly once. The last
#     second of a window is inside it; the closing second is not; the
#     opening second is.
run burn_work_seconds 61199 61200 0 1 31 32400 61200
check "half-open: last second of the window counts once" "$OUT" "1"
run burn_work_seconds 61200 61201 0 1 31 32400 61200
check "half-open: the closing second is outside the window" "$OUT" "0"
run burn_work_seconds 32399 32400 0 1 31 32400 61200
check "half-open: the second before opening is outside" "$OUT" "0"
run burn_work_seconds 32400 32401 0 1 31 32400 61200
check "half-open: the opening second is inside" "$OUT" "1"
run burn_work_seconds 86399 86401 0 1 127 0 86400
check "half-open at a local-day boundary: two seconds, each counted once" "$OUT" "2"

# 5l. The anchor pair only PHASES the grid: any (midnight, weekday) pair
#     describing the same grid must give the same answer, whether the anchor
#     day is inside the interval or entirely after it.
run burn_work_seconds 0 604800 259200 4 31 32400 61200
check "anchor on Thursday of the same grid: identical 144000" "$OUT" "144000"
run burn_work_seconds 0 604800 604800 1 31 32400 61200
check "anchor day after the interval (walks backwards): identical 144000" "$OUT" "144000"

# 5m. Errors: non-numeric arguments, at several positions.
run burn_work_seconds abc 604800 0 1 31 32400 61200
check "seconds non-numeric A: rc 1" "$RC" "1"
check "seconds non-numeric A: echoes nothing" "$OUT" ""
run burn_work_seconds 0 abc 0 1 31 32400 61200
check "seconds non-numeric B: rc 1" "$RC" "1"
run burn_work_seconds 0 604800 abc 1 31 32400 61200
check "seconds non-numeric ANCHOR_MIDNIGHT: rc 1" "$RC" "1"
run burn_work_seconds 0 604800 0 1 31 32400 abc
check "seconds non-numeric END_SEC: rc 1" "$RC" "1"
check "seconds non-numeric END_SEC: echoes nothing" "$OUT" ""

# 5n. Errors: out-of-range arguments at each documented bound.
run burn_work_seconds 0 604800 0 0 31 32400 61200
check "seconds ANCHOR_WEEKDAY below 1: rc 1" "$RC" "1"
run burn_work_seconds 0 604800 0 8 31 32400 61200
check "seconds ANCHOR_WEEKDAY above 7: rc 1" "$RC" "1"
run burn_work_seconds 0 604800 0 1 -1 32400 61200
check "seconds DAYMASK below 0: rc 1" "$RC" "1"
run burn_work_seconds 0 604800 0 1 128 32400 61200
check "seconds DAYMASK above 127: rc 1" "$RC" "1"
run burn_work_seconds 0 604800 0 1 31 -1 61200
check "seconds START_SEC below 0: rc 1" "$RC" "1"
run burn_work_seconds 0 604800 0 1 31 86400 86400
check "seconds START_SEC above 86399: rc 1" "$RC" "1"
run burn_work_seconds 0 604800 0 1 31 32400 0
check "seconds END_SEC below 1: rc 1" "$RC" "1"
run burn_work_seconds 0 604800 0 1 31 32400 86401
check "seconds END_SEC above 86400: rc 1" "$RC" "1"
run burn_work_seconds 0 604800 0 1 31 32400 32400
check "seconds END_SEC == START_SEC: rc 1" "$RC" "1"
check "seconds END_SEC == START_SEC: echoes nothing" "$OUT" ""
run burn_work_seconds 0 604800 0 1 31 61200 32400
check "seconds END_SEC < START_SEC: rc 1" "$RC" "1"

# 5o. Clean I/O: never anything on stderr, success or failure.
run burn_work_seconds 0 604800 0 1 31 32400 61200
check "seconds success: stderr empty" "$ERR" ""
run burn_work_seconds 0 604800 0 1 128 32400 61200
check "seconds error: stderr empty" "$ERR" ""

# 5p. Purity: identical arguments give identical output.
run burn_work_seconds 43200 648000 0 1 31 32400 61200
s1="$OUT"
run burn_work_seconds 43200 648000 0 1 31 32400 61200
check "seconds purity: identical arguments -> identical output" "$OUT" "$s1"

# 5q. Fork budget: at most one awk per call, and never `date`.
log=$(run_forkcheck_fn burn_work_seconds 0 604800 0 1 31 32400 61200)
check "burn_work_seconds forks awk at most once" \
  "$([ "$(grep -cxF awk "$log")" -le 1 ] && echo yes || echo no)" "yes"
check "burn_work_seconds never forks date" "$(grep -cxF date "$log")" "0"

echo "--- section 5 (burn_work_seconds) done: FAILED=$FAILED ---"

# ============================================================================
# 6. B02 window-trend
#
# 6A. burn_week_trend USED NOW RESET ANCHOR_MIDNIGHT ANCHOR_WEEKDAY DAYMASK START_SEC END_SEC
#
# trend = USED - expected, expected = 100 * working-seconds(window_start,
# NOW) / working-seconds(window_start, RESET), window_start = RESET-604800.
# Fixture: RESET=604800 so window_start=0, on the Monday grid with Mon-Fri
# 9-17 -> 144000 working seconds in the window. NOW=172800 (Wednesday
# 00:00) has Mon+Tue = 57600 working seconds behind it, so expected = 40
# exactly -- 57600/144000 = 0.4 is exactly representable in binary float.
# ============================================================================

# 6a. Sign convention, fixed: ahead of the line is POSITIVE, behind is
#     NEGATIVE, exactly on it is 0.
run burn_week_trend 55 172800 604800 0 1 31 32400 61200
check "week trend: USED 55 vs expected 40 -> +15 (ahead)" "$OUT" "15"
check "week trend: rc 0" "$RC" "0"
run burn_week_trend 25 172800 604800 0 1 31 32400 61200
check "week trend: USED 25 vs expected 40 -> -15 (behind)" "$OUT" "-15"
run burn_week_trend 40 172800 604800 0 1 31 32400 61200
check "week trend: USED exactly on the line -> 0" "$OUT" "0"

# 6b. Rounded to the nearest whole percentage point, in both directions.
run burn_week_trend 40.6 172800 604800 0 1 31 32400 61200
check "week trend: +0.6 rounds to 1" "$OUT" "1"
run burn_week_trend 40.4 172800 604800 0 1 31 32400 61200
check "week trend: +0.4 rounds to 0" "$OUT" "0"
run burn_week_trend 39.4 172800 604800 0 1 31 32400 61200
check "week trend: -0.6 rounds to -1" "$OUT" "-1"

# 6c. USED >= 100: the trend is still reported, however large.
run burn_week_trend 100 172800 604800 0 1 31 32400 61200
check "week trend: USED 100 mid-window -> +60, still reported" "$OUT" "60"

# 6d. NOW inside non-working time: expected does not advance. Wednesday
#     00:00, 04:46 and 09:00 all have exactly Mon+Tue behind them, so all
#     three give the same trend.
run burn_week_trend 55 172800 604800 0 1 31 32400 61200
w_midnight="$OUT"
run burn_week_trend 55 190000 604800 0 1 31 32400 61200
check "week trend: expected does not advance overnight (Wed 04:46 == Wed 00:00)" "$OUT" "$w_midnight"
run burn_week_trend 55 205200 604800 0 1 31 32400 61200
check "week trend: expected does not advance until the window opens (Wed 09:00 == Wed 00:00)" "$OUT" "$w_midnight"

# 6e. The weekend is not burnable: Friday 17:00 (the last working second
#     spent) and Saturday noon both stand at the full 144000 working
#     seconds, so a Saturday reading does not trend "over" for a reason
#     unconnected to the user.
run burn_week_trend 90 406800 604800 0 1 31 32400 61200
check "week trend: Friday 17:00, whole schedule elapsed -> USED-100 = -10" "$OUT" "-10"
run burn_week_trend 90 475200 604800 0 1 31 32400 61200
check "week trend: Saturday noon reads the same -10 (weekend is not burnable)" "$OUT" "-10"

# 6f. NOW before the window start (clock skew): expected clamps to 0, never
#     negative, so the trend is exactly USED.
run burn_week_trend 25 -1000 604800 0 1 31 32400 61200
check "week trend: NOW before window start -> expected clamps to 0, trend = USED = 25" "$OUT" "25"

# 6g. Errors: a window with no working seconds at all (the user emptied the
#     schedule) returns 1 rather than dividing by zero.
run burn_week_trend 50 172800 604800 0 1 0 32400 61200
check "week trend: empty schedule -> rc 1, not a division by zero" "$RC" "1"
check "week trend: empty schedule -> echoes nothing" "$OUT" ""

# 6h. Errors: RESET <= NOW, at the boundary and below it.
run burn_week_trend 50 604800 604800 0 1 31 32400 61200
check "week trend: RESET == NOW -> rc 1" "$RC" "1"
check "week trend: RESET == NOW -> echoes nothing" "$OUT" ""
run burn_week_trend 50 604900 604800 0 1 31 32400 61200
check "week trend: RESET < NOW -> rc 1" "$RC" "1"

# 6i. Errors: non-numeric input, and B01 failing on a bad schedule argument.
run burn_week_trend abc 172800 604800 0 1 31 32400 61200
check "week trend: non-numeric USED -> rc 1" "$RC" "1"
check "week trend: non-numeric USED -> echoes nothing" "$OUT" ""
run burn_week_trend 50 abc 604800 0 1 31 32400 61200
check "week trend: non-numeric NOW -> rc 1" "$RC" "1"
run burn_week_trend 50 172800 604800 0 8 31 32400 61200
check "week trend: B01 fails (ANCHOR_WEEKDAY out of range) -> rc 1" "$RC" "1"
check "week trend: B01 fails -> echoes nothing" "$OUT" ""
run burn_week_trend 50 172800 604800 0 1 128 32400 61200
check "week trend: B01 fails (DAYMASK out of range) -> rc 1" "$RC" "1"
run burn_week_trend 50 172800 604800 0 1 31 61200 32400
check "week trend: B01 fails (END_SEC <= START_SEC) -> rc 1" "$RC" "1"

# 6j. Clean I/O: one field on stdout, nothing on stderr ever.
run burn_week_trend 55 172800 604800 0 1 31 32400 61200
check "week trend: stdout is exactly one signed integer" \
  "$([[ "$OUT" =~ ^-?[0-9]+$ ]] && echo yes || echo no)" "yes"
check "week trend: stderr empty on success" "$ERR" ""
run burn_week_trend 50 604800 604800 0 1 31 32400 61200
check "week trend: stderr empty on the error path" "$ERR" ""

# 6k. Purity: identical arguments give identical output.
run burn_week_trend 55 172800 604800 0 1 31 32400 61200
t1="$OUT"
run burn_week_trend 55 172800 604800 0 1 31 32400 61200
check "week trend purity: identical arguments -> identical output" "$OUT" "$t1"

# 6l. Fork budget: awk at most once per call (it inlines B01's walk rather
#     than shelling out), and never `date` or `cat`.
log=$(run_forkcheck_fn burn_week_trend 55 172800 604800 0 1 31 32400 61200)
check "burn_week_trend forks awk at most once per call" \
  "$([ "$(grep -cxF awk "$log")" -le 1 ] && echo yes || echo no)" "yes"
check "burn_week_trend never forks date" "$(grep -cxF date "$log")" "0"
check "burn_week_trend never forks cat" "$(grep -cxF cat "$log")" "0"

echo "--- section 6a (burn_week_trend) done: FAILED=$FAILED ---"

# ============================================================================
# 6B. burn_linear_trend USED NOW RESET WINDOW_SECONDS
#
# Plain wall clock: expected = 100 * (WINDOW_SECONDS - (RESET - NOW)) /
# WINDOW_SECONDS, clamped at 0 below. Fixture: the 5-hour window,
# WINDOW_SECONDS=18000 and RESET=18000, so NOW=9000 is exactly halfway ->
# expected = 50.
# ============================================================================

# 6m. Sign convention, fixed and matching burn_week_trend's.
run burn_linear_trend 70 9000 18000 18000
check "linear trend: USED 70 at the halfway point -> +20 (ahead)" "$OUT" "20"
check "linear trend: rc 0" "$RC" "0"
run burn_linear_trend 30 9000 18000 18000
check "linear trend: USED 30 at the halfway point -> -20 (behind)" "$OUT" "-20"
run burn_linear_trend 50 9000 18000 18000
check "linear trend: USED exactly on the line -> 0" "$OUT" "0"

# 6n. Rounded to the nearest whole percentage point, both directions.
run burn_linear_trend 50.6 9000 18000 18000
check "linear trend: +0.6 rounds to 1" "$OUT" "1"
run burn_linear_trend 50.4 9000 18000 18000
check "linear trend: +0.4 rounds to 0" "$OUT" "0"
run burn_linear_trend 49.4 9000 18000 18000
check "linear trend: -0.6 rounds to -1" "$OUT" "-1"

# 6o. Quarter and three-quarter points, to pin the proportion itself rather
#     than just its midpoint.
run burn_linear_trend 25 4500 18000 18000
check "linear trend: quarter elapsed, USED 25 -> 0" "$OUT" "0"
run burn_linear_trend 50 13500 18000 18000
check "linear trend: three-quarters elapsed, USED 50 -> -25" "$OUT" "-25"

# 6p. USED >= 100: still reported, however large.
run burn_linear_trend 100 9000 18000 18000
check "linear trend: USED 100 at halfway -> +50, still reported" "$OUT" "50"

# 6q. A server-side window longer than the assumed 18000 (RESET - NOW >
#     WINDOW_SECONDS): expected clamps to 0 rather than going negative, so
#     the trend is exactly USED.
run burn_linear_trend 25 0 20000 18000
check "linear trend: RESET-NOW > WINDOW_SECONDS -> expected clamps to 0, trend = USED = 25" "$OUT" "25"

# 6r. Errors: RESET <= NOW, at the boundary and below it.
run burn_linear_trend 50 18000 18000 18000
check "linear trend: RESET == NOW -> rc 1" "$RC" "1"
check "linear trend: RESET == NOW -> echoes nothing" "$OUT" ""
run burn_linear_trend 50 18001 18000 18000
check "linear trend: RESET < NOW -> rc 1" "$RC" "1"

# 6s. Errors: a non-positive window of usable seconds, at the boundary and
#     below it.
run burn_linear_trend 50 9000 18000 0
check "linear trend: WINDOW_SECONDS == 0 -> rc 1" "$RC" "1"
check "linear trend: WINDOW_SECONDS == 0 -> echoes nothing" "$OUT" ""
run burn_linear_trend 50 9000 18000 -1
check "linear trend: WINDOW_SECONDS < 0 -> rc 1" "$RC" "1"

# 6t. Errors: non-numeric input at each position.
run burn_linear_trend abc 9000 18000 18000
check "linear trend: non-numeric USED -> rc 1" "$RC" "1"
check "linear trend: non-numeric USED -> echoes nothing" "$OUT" ""
run burn_linear_trend 50 abc 18000 18000
check "linear trend: non-numeric NOW -> rc 1" "$RC" "1"
run burn_linear_trend 50 9000 abc 18000
check "linear trend: non-numeric RESET -> rc 1" "$RC" "1"
run burn_linear_trend 50 9000 18000 abc
check "linear trend: non-numeric WINDOW_SECONDS -> rc 1" "$RC" "1"

# 6u. Clean I/O: one signed integer on stdout, nothing on stderr ever.
run burn_linear_trend 70 9000 18000 18000
check "linear trend: stdout is exactly one signed integer" \
  "$([[ "$OUT" =~ ^-?[0-9]+$ ]] && echo yes || echo no)" "yes"
check "linear trend: stderr empty on success" "$ERR" ""
run burn_linear_trend 50 18000 18000 18000
check "linear trend: stderr empty on the error path" "$ERR" ""

# 6v. Purity: identical arguments give identical output.
run burn_linear_trend 70 9000 18000 18000
l1="$OUT"
run burn_linear_trend 70 9000 18000 18000
check "linear trend purity: identical arguments -> identical output" "$OUT" "$l1"

# 6w. Invariant: burn_linear_trend forks NOTHING -- bash integer arithmetic
#     suffices, so not even one awk.
log=$(run_forkcheck_fn burn_linear_trend 70 9000 18000 18000)
check "burn_linear_trend forks no awk at all" "$(grep -cxF awk "$log")" "0"
check "burn_linear_trend forks no date" "$(grep -cxF date "$log")" "0"
check "burn_linear_trend forks no cat" "$(grep -cxF cat "$log")" "0"

echo "--- section 6b (burn_linear_trend) done: FAILED=$FAILED ---"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
