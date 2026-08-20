#!/bin/bash
#
# Working-week burn pacing for the statusline's limit meters.
#
# Ported from claude-statusline-burnrate — MIT © Gui-Gou
# https://github.com/Gui-Gou/claude-statusline-burnrate
#
# The AWAKE-HOURS model this file used to open with (burn_day_start_epoch,
# burn_awake_seconds, burn_metrics; contract B01 burn-math, plan
# 001-statusline-burnrate-uplift) is RETIRED by B05 line2-groups (plan
# 001-statusline-glance-uplift): the %t and %/d figures it computed answer none
# of the seven glance-items and leave line 2 with them, so the three functions
# go with their call sites rather than surviving uncalled. What replaces it is
# the working-week model below, which was already answering the same question
# with a schedule the user states rather than a sleep window inferred for them.
#
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

# ---------------------------------------------------------------------------
# Working-week pacing model (plan 001-statusline-glance-uplift).
#
# Replaces the awake-hours model this file used to carry, which B05 deleted at
# the moment its call sites moved -- the landing order the plan's invariant
# asks for, so every intermediate integration-branch state still renders.
# ---------------------------------------------------------------------------

# Contract: B01 work-window-seconds (plan 001-statusline-glance-uplift)
#
# Behavior:
#   burn_work_parse normalizes a user-supplied working-week schedule — a
#   weekday set written as ISO-8601 weekday numbers with commas and ranges
#   ("1-5", "1,3,5", "1-4,6"; 1=Mon, 7=Sun), a work start hour and a work end
#   hour — into a canonical 7-bit day mask and two second-of-day offsets.
#
#   burn_work_seconds counts the seconds falling inside working windows within
#   the half-open interval [A, B), walking local day by local day. The local
#   day grid is phased by ANCHOR_MIDNIGHT (the epoch of local midnight on the
#   day containing "now") and ANCHOR_WEEKDAY (the ISO weekday of that day),
#   both supplied by the caller, so this file never forks `date` and stays
#   pure.
#
# Inputs:
#   burn_work_parse DAYS START END
#     DAYS   weekday-set string; ISO weekday numbers 1..7, commas and ranges.
#            Spaces and tabs are stripped before parsing (B13), so "1, 3" and
#            "1,3" are the same schedule — the value is hand-typed into a shell
#            profile, and a stray space there would otherwise fail silently.
#     START  integer hour 0..23, the hour the working day starts
#     END    integer hour 1..24, the hour the working day ends; > START
#
#   burn_work_seconds A B ANCHOR_MIDNIGHT ANCHOR_WEEKDAY DAYMASK START_SEC END_SEC
#     A, B             integer epoch seconds bounding a half-open [A, B)
#     ANCHOR_MIDNIGHT  integer epoch of local midnight on the day containing
#                      "now"; phases the day grid
#     ANCHOR_WEEKDAY   integer 1..7, the ISO weekday of that anchor day
#     DAYMASK          integer 0..127, bit (weekday-1) set = that day worked
#     START_SEC        integer 0..86399, seconds-of-day the window opens
#     END_SEC          integer 1..86400, seconds-of-day the window closes
#
#   The caller derives the anchor pair from the render's existing plain `date`
#   call — machine local time, nothing scoping it — so these functions need no
#   notion of a zone at all and stay pure and testable.
#
# Outputs:
#   burn_work_parse    echoes three space-separated integers,
#                      "DAYMASK START_SEC END_SEC".
#   burn_work_seconds  echoes one integer: working seconds in [A, B). Zero
#                      when B <= A or the mask is empty.
#
# Errors:
#   Non-numeric or out-of-range input, END <= START, an unparseable day list,
#   or an empty resulting mask: echo nothing, return 1. Nothing is EVER
#   written to stderr — this file's output reaches the user's terminal.
#   Whitespace stripping (B13) does not soften any of these: a DAYS value that
#   is empty or entirely whitespace is unparseable, and stripping cannot rescue
#   a malformed list — "1, ,3" still fails on its empty token, and "1 2" strips
#   to "12", which is out of range.
#
# Invariants:
#   - Pure: no file I/O, no environment reads, no `date`, no globals mutated.
#     Identical arguments give identical output on any machine.
#   - Forks awk at most once per call.
#   - bash 3.2 compatible; POSIX awk only (macOS ships BWK awk — no gawk
#     extensions, no strftime).
#   - [A, B) is half-open, so a boundary second is counted exactly once.
#
# Edge cases:
#   - Every day in the mask and a full 0-24 window degenerates to plain
#     calendar seconds and must not divide by zero.
#   - A single working day per week must work.
#   - A and B inside the same working window.
#   - A and B both inside non-working time, yielding 0.
#   - A DST shift inside [A, B) moves the local grid by an hour; the
#     anchor-plus-multiple-of-86400 day walk absorbs it as a one-hour error
#     over a week rather than failing. This is ACCEPTED imprecision, recorded
#     rather than silently ignored: correcting it needs a `date` per day,
#     which blows the render's process budget.
#   - An interval spanning a full week counts each working day exactly once.
#   - DAYS carrying spaces or tabs anywhere — "1, 3", " 1-5 ", "1 - 5",
#     "\t1,5" — parses as if they were absent (B13). DAYS that is only
#     whitespace is unparseable, exactly like the empty string.

# burn_work_parse DAYS START END
burn_work_parse() {
  local days="$1" start="$2" end="$3"

  # B13: DAYS is hand-typed into a shell profile, so spaces (0x20) and tabs
  # (0x09) are removed at any position before any validation runs -- "1, 3" is
  # the same schedule as "1,3". Pure parameter expansion, so no fork and bash
  # 3.2 is fine. Scoped to DAYS alone: START and END keep their strict numeric
  # error path, and stripping softens no validation -- an all-whitespace DAYS
  # strips to "" and is unparseable, "1 2" strips to the out-of-range "12".
  local _burn_tab
  _burn_tab=$'\t'
  days="${days// /}"
  days="${days//$_burn_tab/}"

  _burn_is_int "$start" || return 1
  _burn_is_int "$end" || return 1
  [ "$start" -ge 0 ] && [ "$start" -le 23 ] || return 1
  [ "$end" -ge 1 ] && [ "$end" -le 24 ] || return 1
  [ "$end" -gt "$start" ] || return 1
  [ -n "$days" ] || return 1

  # Walk the comma-separated list by parameter expansion (no fork, no arrays,
  # so bash 3.2 is fine). The trailing sentinel comma makes every element --
  # including an empty trailing one -- surface as its own token, so ",1,3",
  # "1,,3" and "1,3," are all caught as the same unparseable defect.
  local mask=0 rest="$days," tok lo hi d
  while [ -n "$rest" ]; do
    tok="${rest%%,*}"
    rest="${rest#*,}"
    [ -n "$tok" ] || return 1
    case "$tok" in
      *-*)
        lo="${tok%%-*}"
        hi="${tok#*-}"
        _burn_is_int "$lo" || return 1
        _burn_is_int "$hi" || return 1
        [ "$lo" -ge 1 ] && [ "$lo" -le 7 ] || return 1
        [ "$hi" -ge 1 ] && [ "$hi" -le 7 ] || return 1
        [ "$hi" -ge "$lo" ] || return 1
        d=$(( 10#$lo ))
        while [ "$d" -le "$hi" ]; do
          mask=$(( mask | (1 << (d - 1)) ))
          d=$(( d + 1 ))
        done
        ;;
      *)
        _burn_is_int "$tok" || return 1
        [ "$tok" -ge 1 ] && [ "$tok" -le 7 ] || return 1
        mask=$(( mask | (1 << (10#$tok - 1)) ))
        ;;
    esac
  done
  [ "$mask" -gt 0 ] || return 1

  echo "$mask $(( 10#$start * 3600 )) $(( 10#$end * 3600 ))"
}

# burn_work_seconds A B ANCHOR_MIDNIGHT ANCHOR_WEEKDAY DAYMASK START_SEC END_SEC
burn_work_seconds() {
  local a="$1" b="$2" am="$3" aw="$4" mask="$5" ss="$6" es="$7"
  _burn_is_int "$a" || return 1
  _burn_is_int "$b" || return 1
  _burn_is_int "$am" || return 1
  _burn_is_int "$aw" || return 1
  _burn_is_int "$mask" || return 1
  _burn_is_int "$ss" || return 1
  _burn_is_int "$es" || return 1
  [ "$aw" -ge 1 ] && [ "$aw" -le 7 ] || return 1
  [ "$mask" -ge 0 ] && [ "$mask" -le 127 ] || return 1
  [ "$ss" -ge 0 ] && [ "$ss" -le 86399 ] || return 1
  [ "$es" -ge 1 ] && [ "$es" -le 86400 ] || return 1
  [ "$es" -gt "$ss" ] || return 1

  # One awk, walking the local-day grid phased by the anchor pair: day k
  # begins at AM + 86400*k and carries ISO weekday ((AW-1+k) mod 7) + 1, so
  # bit (AW-1+k) mod 7 of the mask decides whether that day is worked. Each
  # day contributes its window clipped to the half-open [a, b).
  awk -v a="$a" -v b="$b" -v AM="$am" -v AW="$aw" -v mask="$mask" \
      -v ss="$ss" -v es="$es" '
BEGIN {
  s = 0
  if (b > a && mask > 0) {
    k = int((a - AM) / 86400)
    if (AM + k * 86400 > a) k--
    t = AM + k * 86400
    while (t < b) {
      bit = (AW - 1 + k) % 7
      if (bit < 0) bit += 7
      if (int(mask / (2 ^ bit)) % 2 == 1) {
        o = t + ss; if (o < a) o = a
        c = t + es; if (c > b) c = b
        if (c > o) s += c - o
      }
      t += 86400
      k++
    }
  }
  printf "%d\n", s
}'
}

# Contract: B02 window-trend (plan 001-statusline-glance-uplift)
#
# Behavior:
#   Both functions echo `used% - expected%`, in percentage points of their own
#   window, where expected% is the fraction of the window's USABLE time already
#   elapsed. This one number answers the engineer's glance-items 6 and 7: its
#   sign says over or under the even-burn line, its magnitude says by how much.
#
#   burn_week_trend's usable time is WORKING seconds (B01's model) between the
#   window start (RESET - 604800) and NOW, over working seconds across the
#   whole window. This is the entire point of item 7: a weekly window whose
#   reset lands on a Thursday must not count the weekend as burnable, or a
#   Friday reading trends "over" for no reason connected to the user.
#
#   burn_linear_trend's usable time is plain wall clock over WINDOW_SECONDS.
#   Over a five-hour window "which days do you work" cannot apply, and a window
#   you are not working through is a window you are not burning.
#
#   Positive means ahead of the line — will cap before the reset. Negative
#   means behind it — will leave allowance unused.
#
# Inputs:
#   burn_week_trend USED NOW RESET ANCHOR_MIDNIGHT ANCHOR_WEEKDAY DAYMASK START_SEC END_SEC
#   burn_linear_trend USED NOW RESET WINDOW_SECONDS
#     USED            weekly/5-hour used percentage, integer or decimal 0..100
#     NOW, RESET      integer epoch seconds
#     WINDOW_SECONDS  positive integer (18000 for the 5-hour window)
#     The schedule arguments are exactly as B01 defines them.
#
# Outputs:
#   One signed integer, rounded to the nearest whole percentage point. The
#   sign convention is FIXED -- it is the one the retired burn_metrics TREND
#   field used -- so burn_trend_color's asymmetric scale keeps its meaning
#   without amendment.
#
# Errors:
#   Non-numeric input, RESET <= NOW, or B01 failing: echo nothing, return 1.
#   The caller then omits the trend and
#   still renders the used percentage — quota state must survive a pacing
#   failure. Nothing is ever written to stderr.
#
# Invariants:
#   - Pure, as B01.
#   - burn_week_trend forks awk EXACTLY ONCE, inlining B01's walk rather than
#     shelling out to it, so the render's two-awk budget holds.
#   - burn_linear_trend forks NOTHING — bash integer arithmetic suffices.
#   - bash 3.2 compatible; POSIX awk only.
#
# Edge cases:
#   - USED >= 100: the trend is still reported, however large.
#   - NOW before the window start (clock skew): expected clamps to 0, never
#     negative.
#   - NOW inside non-working time: expected does not advance. This is the
#     entire point of item 7, not an incidental property.
#   - A weekly window containing no working seconds at all (a schedule the
#     user has emptied): return 1 rather than divide by zero.
#   - A 5-hour window where RESET - NOW > WINDOW_SECONDS (a server-side window
#     longer than the assumed 18000): expected clamps to 0 rather than going
#     negative.

# burn_week_trend USED NOW RESET ANCHOR_MIDNIGHT ANCHOR_WEEKDAY DAYMASK START_SEC END_SEC
burn_week_trend() {
  local used="$1" now="$2" reset="$3" am="$4" aw="$5" mask="$6" ss="$7" es="$8"
  _burn_is_num "$used" || return 1
  _burn_is_int "$now" || return 1
  _burn_is_int "$reset" || return 1
  _burn_is_int "$am" || return 1
  _burn_is_int "$aw" || return 1
  _burn_is_int "$mask" || return 1
  _burn_is_int "$ss" || return 1
  _burn_is_int "$es" || return 1
  [ "$aw" -ge 1 ] && [ "$aw" -le 7 ] || return 1
  [ "$mask" -ge 0 ] && [ "$mask" -le 127 ] || return 1
  [ "$ss" -ge 0 ] && [ "$ss" -le 86399 ] || return 1
  [ "$es" -ge 1 ] && [ "$es" -le 86400 ] || return 1
  [ "$es" -gt "$ss" ] || return 1
  [ "$reset" -gt "$now" ] || return 1

  # One awk: B01's day walk is INLINED as work(), never shelled out to, so
  # the render's two-awk budget holds. A window with no working seconds at
  # all exits 1 rather than dividing by zero.
  awk -v used="$used" -v now="$now" -v reset="$reset" -v AM="$am" -v AW="$aw" \
      -v mask="$mask" -v ss="$ss" -v es="$es" '
function work(a, b,   s, k, t, bit, o, c) {
  s = 0
  if (b <= a || mask <= 0) return 0
  k = int((a - AM) / 86400)
  if (AM + k * 86400 > a) k--
  t = AM + k * 86400
  while (t < b) {
    bit = (AW - 1 + k) % 7
    if (bit < 0) bit += 7
    if (int(mask / (2 ^ bit)) % 2 == 1) {
      o = t + ss; if (o < a) o = a
      c = t + es; if (c > b) c = b
      if (c > o) s += c - o
    }
    t += 86400
    k++
  }
  return s
}
BEGIN {
  ws = reset - 604800
  total = work(ws, reset)
  if (total <= 0) exit 1
  el = work(ws, now)
  if (el < 0) el = 0
  e = 100 * el / total
  r = used - e
  if (r >= 0) printf "%d\n", int(r + 0.5)
  else printf "%d\n", -int(-r + 0.5)
}'
}

# burn_linear_trend USED NOW RESET WINDOW_SECONDS
burn_linear_trend() {
  local used="$1" now="$2" reset="$3" win="$4"
  _burn_is_num "$used" || return 1
  _burn_is_int "$now" || return 1
  _burn_is_int "$reset" || return 1
  _burn_is_int "$win" || return 1
  [ "$win" -gt 0 ] || return 1
  [ "$reset" -gt "$now" ] || return 1

  # Forks NOTHING: fixed-point bash integer arithmetic at 1/10000 of a
  # percentage point, which is far finer than the whole-point output.
  local sign=1 v="$used" ip fp
  case "$v" in
    -*) sign=-1; v="${v#-}" ;;
  esac
  ip="${v%%.*}"
  fp=""
  case "$v" in
    *.*) fp="${v#*.}" ;;
  esac
  [ -n "$ip" ] || ip=0
  fp="${fp}0000"
  fp="${fp:0:4}"
  local us=$(( sign * (10#$ip * 10000 + 10#$fp) ))

  local elapsed=$(( win - (reset - now) ))
  [ "$elapsed" -gt 0 ] || elapsed=0
  local es_=$(( elapsed * 1000000 / win ))
  local d=$(( us - es_ )) mag
  if [ "$d" -ge 0 ]; then
    echo "$(( (d + 5000) / 10000 ))"
  else
    mag=$(( (-d + 5000) / 10000 ))
    if [ "$mag" -eq 0 ]; then echo 0; else echo "-$mag"; fi
  fi
}
