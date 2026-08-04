#!/bin/bash
#
# Awake-hours burn pacing for the statusline's weekly-limit segment.
#
# Ported from claude-statusline-burnrate — MIT © Gui-Gou
# https://github.com/Gui-Gou/claude-statusline-burnrate
#
# Contract: B01 burn-math (plan 001-statusline-burnrate-uplift)
#
# Behavior:
#   Computes the three derived weekly-limit figures the burnrate line shows
#   beside the raw `🎯 wk%`, under an AWAKE-HOURS model of time. A "day" runs
#   from day-start to day-start (default 02:00 local), and the first
#   SLEEP_SECONDS after each day-start count for nothing. All budget math
#   counts awake seconds only, so the trend does not drift "behind" every
#   night while the user sleeps — the defect that motivates the whole model.
#
#   The ideal burn is a straight LINE over the week's awake seconds: 0% at
#   the last weekly reset, 100% at the next. The three figures read off it:
#     - today's share (%t)  = how much of TODAY's slice of that line is still
#                             unspent, as a percentage of the slice
#     - pace (%/d)          = sustainable weekly points per awake-day from now
#     - trend               = used% minus the line's value at NOW, in weekly
#                             points (signed)
#
#   Three functions make up the surface. `burn_awake_seconds` is the shared
#   primitive; `burn_metrics` is what the renderer calls. Both evaluate the
#   SAME awake-walk algorithm, defined exactly once as awk source in
#   $_BURN_AWK_AWAKE and prepended to each function's awk program — the
#   duplication that would otherwise drift between them is structural, not
#   copied.
#
# Inputs:
#   burn_day_start_epoch NOW SECS_INTO_LOCAL_DAY DAY_START_HOUR
#     NOW                 integer epoch seconds
#     SECS_INTO_LOCAL_DAY integer 0..86399 — seconds elapsed since local
#                         midnight at NOW (the caller derives this from its
#                         own single `date` invocation; this file never forks
#                         `date`, so it stays pure and testable)
#     DAY_START_HOUR      integer 0..23
#
#   burn_awake_seconds A B DAY_START_EPOCH SLEEP_SECONDS
#     A, B                integer epoch seconds bounding a half-open [A,B)
#     DAY_START_EPOCH     integer epoch of any day-start (only its value
#                         mod 86400 matters — it phases the day grid)
#     SLEEP_SECONDS       integer 0..86399 — sleep length after each day-start
#
#   burn_metrics USED FRAC NOW RESET DAY_START_EPOCH SLEEP_SECONDS
#     USED                weekly used percentage, integer or decimal 0..100
#     FRAC                sub-tick fraction 0..0.95 from B02 (0 when absent),
#                         added to USED before the %t computation only
#     NOW                 integer epoch seconds
#     RESET               integer epoch seconds of the next weekly reset
#     DAY_START_EPOCH     as above — the CURRENT day's start
#     SLEEP_SECONDS       as above
#
# Outputs:
#   burn_day_start_epoch  echoes one integer: the epoch of the current day's
#     start. When NOW is before today's DAY_START_HOUR, this is YESTERDAY's
#     day-start (the day has not flipped yet), never a future instant.
#
#   burn_awake_seconds    echoes one integer: awake seconds in [A,B). Zero
#     when B <= A.
#
#   burn_metrics          echoes exactly three space-separated fields,
#     "TODAY PACE TREND":
#       TODAY  integer, or the literal NA when today's slice is degenerate
#              (<= 0.1 weekly points, e.g. a reset landing inside sleep).
#              100 = the whole slice is still ahead; 0 = exactly on tonight's
#              checkpoint; negative = past it, eating tomorrow's slice.
#              CAPPED at 100 when running behind the line; NOT capped below.
#       PACE   sustainable weekly points per awake-day: (100-USED)/days-left,
#              where days-left is clamped to a minimum of 1 (with under a day
#              remaining, everything left is spendable today). One decimal
#              below 10, integer at 10 and above — rounding error matters
#              most where the number is smallest.
#       TREND  signed integer weekly points: USED minus the line at NOW.
#              Positive = ahead of the glide (will cap before the reset);
#              negative = behind it (will leave subscription unused).
#     FRAC participates in TODAY only. PACE and TREND are computed from the
#     server's integer USED alone, so neither inherits the interpolator's
#     estimation error.
#
# Errors:
#   Non-numeric arguments, RESET <= NOW, a non-positive week of awake
#   seconds, or a DAY_START_EPOCH <= 0 are all "cannot compute": echo
#   nothing and return 1. No diagnostics on stdout ever — this file's output
#   is consumed by a statusline that must never print an error into the
#   user's terminal. Callers render the segment only on a zero return.
#
# Invariants:
#   - Pure: no file I/O, no environment reads, no globals mutated, no `date`.
#     Identical arguments always produce identical output, on any machine.
#   - burn_metrics forks awk EXACTLY ONCE per call (the warm-render process
#     budget in scripts/context.sh allows at most two awk in total, one here
#     and one in burn-tick.sh). It never shells out to burn_awake_seconds;
#     it inlines the same algorithm from $_BURN_AWK_AWAKE.
#   - bash 3.2 compatible; awk must be POSIX-portable (no gawk extensions,
#     no strftime — macOS ships BWK awk).
#   - TREND's sign convention is fixed: ahead of the line is POSITIVE.
#
# Edge cases:
#   - USED >= 100 (limit reached): PACE is 0, never negative.
#   - Under one awake-day to the reset: days-left clamps to 1, so PACE is
#     exactly the remainder.
#   - A weekly reset landing inside sleep hours: the line ends at the
#     surrounding day-start; today's slice may be degenerate, giving NA.
#   - SLEEP_SECONDS = 0: degenerates to plain calendar time, all 86400
#     seconds of every day awake. This must work, not divide by zero.
#   - SLEEP_SECONDS = 86399: one awake second per day; PACE stays finite.
#   - NOW before the week start (clock skew): the line clamps to 0, not
#     negative.
#   - NOW exactly at a day-start boundary: [A,B) is half-open, so the
#     boundary second belongs to the NEW day, counted once and only once.

# Shared awk source for the awake-seconds walk, so burn_awake_seconds and
# burn_metrics evaluate one definition rather than two copies. Walks day by
# day from a to b, skipping the first `slp` seconds after each day-start.
# A = any day-start epoch (phases the grid), slp = sleep seconds per day.
_BURN_AWK_AWAKE='
function awake(a, b,   s, t, x, de, se, as) {
  s = 0; t = a
  while (t < b) {
    x = (t - A) % 86400; if (x < 0) x += 86400
    de = t + (86400 - x)
    se = (b < de) ? b : de
    as = t + ((x < slp) ? slp - x : 0)
    if (as < se) s += se - as
    t = de
  }
  return s
}
'

# _burn_is_int VALUE -- true (rc 0) iff VALUE is an optionally-signed
# integer, e.g. "5", "-5", but not "", "-", "5.5", "5-5", "abc". Plain
# case-pattern matching only, so it works under bash 3.2.
_burn_is_int() {
  local v="$1"
  case "$v" in
    -*) v="${v#-}" ;;
  esac
  case "$v" in
    ''|*[!0-9]*) return 1 ;;
  esac
  return 0
}

# _burn_is_num VALUE -- true (rc 0) iff VALUE is an optionally-signed
# integer or decimal, e.g. "5", "-5", "41.25", "0.5", but not "", ".",
# "5.5.5", "abc".
_burn_is_num() {
  local v="$1"
  case "$v" in
    -*) v="${v#-}" ;;
  esac
  case "$v" in
    ''|.) return 1 ;;
  esac
  case "$v" in
    *[!0-9.]*) return 1 ;;
  esac
  case "$v" in
    *.*.*) return 1 ;;
  esac
  return 0
}

# burn_day_start_epoch NOW SECS_INTO_LOCAL_DAY DAY_START_HOUR
burn_day_start_epoch() {
  local now="$1" secs="$2" hour="$3"
  _burn_is_int "$now" || return 1
  _burn_is_int "$secs" || return 1
  _burn_is_int "$hour" || return 1

  local midnight=$((now - secs))
  local candidate=$((midnight + hour * 3600))
  if [ "$secs" -ge $((hour * 3600)) ]; then
    echo "$candidate"
  else
    echo "$((candidate - 86400))"
  fi
}

# burn_awake_seconds A B DAY_START_EPOCH SLEEP_SECONDS
burn_awake_seconds() {
  local a="$1" b="$2" ds="$3" slp="$4"
  _burn_is_int "$a" || return 1
  _burn_is_int "$b" || return 1
  _burn_is_int "$ds" || return 1
  _burn_is_int "$slp" || return 1
  [ "$ds" -gt 0 ] || return 1

  awk -v A="$ds" -v a="$a" -v b="$b" -v slp="$slp" "$_BURN_AWK_AWAKE"'
BEGIN { print awake(a, b) }'
}

# burn_metrics USED FRAC NOW RESET DAY_START_EPOCH SLEEP_SECONDS
burn_metrics() {
  local used="$1" fr="$2" now="$3" reset="$4" ds="$5" slp="$6"
  _burn_is_num "$used" || return 1
  _burn_is_num "$fr" || return 1
  _burn_is_int "$now" || return 1
  _burn_is_int "$reset" || return 1
  _burn_is_int "$ds" || return 1
  _burn_is_int "$slp" || return 1

  awk -v used="$used" -v fr="$fr" -v now="$now" -v reset="$reset" \
      -v ds="$ds" -v A="$ds" -v slp="$slp" -v aday="$((86400 - slp))" \
      "$_BURN_AWK_AWAKE"'
BEGIN{
  if (reset <= now || A <= 0) exit 1
  rem = 100 - used; if (rem < 0) rem = 0
  d = awake(now, reset) / aday; if (d < 1) d = 1     # awake-days left
  pr = rem / d
  pv = (pr < 10) ? sprintf("%.1f", pr) : sprintf("%.0f", pr)
  ws = reset - 604800
  aw = awake(ws, reset)
  if (aw <= 0) exit 1
  fv = "NA"
  de = ds + 86400; if (de > reset) de = reset
  d0 = ds; if (d0 < ws) d0 = ws
  ckpt  = awake(ws, de) / aw * 100
  share = ckpt - awake(ws, d0) / aw * 100
  if (share > 0.1) {
    f = (ckpt - (used + fr)) / share * 100
    if (f > 100) f = 100
    fv = sprintf("%.0f", f)
  }
  e = awake(ws, now) / aw * 100
  if (e < 0) e = 0; if (e > 100) e = 100
  dfv = sprintf("%.0f", used - e)
  print fv, pv, dfv
}'
}
