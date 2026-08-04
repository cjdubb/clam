#!/bin/bash
#
# Sub-tick interpolation for the statusline's weekly-limit percentage.
#
# Ported from claude-statusline-burnrate — MIT © Gui-Gou
# https://github.com/Gui-Gou/claude-statusline-burnrate
#
# Contract: B02 burn-tick (plan 001-statusline-burnrate-uplift)
#
# Behavior:
#   The statusLine payload reports weekly usage as an INTEGER percentage, and
#   one weekly point is roughly 7 points of the today's-share figure B01
#   derives from it. Left raw, `%t` would sit still and then jump 7 points at
#   a time. This block estimates how far into the CURRENT integer point the
#   session already is, so `%t` moves smoothly between ticks.
#
#   The estimate is this session's spend since the last tick, divided by a
#   dollars-per-weekly-point rate. That rate self-calibrates: whenever a
#   clean +1 tick is observed inside one session, the dollars consumed across
#   it is a measured sample, folded into the running rate by an
#   equally-weighted EMA (new = 0.5*old + 0.5*sample).
#
#   Ground truth re-anchors the estimate at EVERY real tick, so error can
#   never accumulate past a single point. The known blind spots — parallel
#   sessions, other machines, claude.ai usage — all make the session's own
#   cost UNDER-count the true burn, so the figure errs toward showing
#   slightly more headroom than exists, never less. That asymmetry is
#   deliberate; do not "fix" it by inflating the estimate.
#
# Inputs:
#   burn_tick_frac USED SESSION_ID COST_USD STATE_FILE
#     USED        weekly used percentage from the payload, integer 0..100
#     SESSION_ID  the payload's session_id; identifies the cost baseline
#     COST_USD    the payload's cost.total_cost_usd for this session, decimal
#     STATE_FILE  path to the persistent anchor file (caller supplies it;
#                 this file never chooses a location of its own)
#
#   State file format: ONE line, four space-separated fields —
#     "<anchored_used> <session_id> <anchored_cost> <rate>"
#   Written only on an anchor, read on every call.
#
# Outputs:
#   Echoes one decimal in [0, 0.95] — the fraction of the current weekly
#   point estimated as already spent — and returns 0.
#
#   Echoes 0 (and returns 0) on every path where no estimate is possible:
#   first run, a missing/unreadable/malformed state file, a session switch, a
#   weekly reset, or a fresh tick. Zero is the correct degraded value, not an
#   error: it means "no sub-tick information", which returns the display to
#   plain integer steps.
#
#   Side effect: on an anchor the state file is REPLACED with the new
#   four-field line. On a non-anchor call the file is not written at all.
#
# Errors:
#   An unwritable state file is not an error: the estimate degrades to 0 on
#   subsequent calls and rendering continues. Nothing is ever printed to
#   stdout but the number, and nothing to stderr in normal operation — this
#   feeds a statusline that must never break or leak diagnostics.
#
# Invariants:
#   - Anchors on ANY of: no prior state, USED differs from the anchored
#     value (a tick in either direction — a weekly reset moves it DOWN), or
#     SESSION_ID differs from the anchored one.
#   - Calibration is strictly guarded. The rate updates ONLY when all hold:
#     same session, USED is exactly the anchored value + 1, and the cost
#     delta is in (0.5, 40) dollars. Anything else anchors without touching
#     the rate. This rejects resets, multi-point jumps, and absurd samples.
#   - The rate is used as-is on read when it falls in [1, 20] dollars per
#     point; when absent or outside that range it is REPLACED by the 4.5
#     seed on read, never clamped to the nearest bound.
#   - The returned fraction is clamped to [0, 0.95] — never 1.0, which would
#     assert a tick the server has not reported.
#   - Forks awk at most ONCE per call (the warm-render budget in
#     scripts/context.sh allows at most two awk in total, one here and one in
#     burn-math.sh). Never forks `date`, `cat`, or a subshell pipeline.
#   - The state file is written whole, never appended to or edited in place.
#   - bash 3.2 compatible; POSIX-portable awk.
#
# Edge cases:
#   - Weekly reset (USED drops, e.g. 87 -> 0): anchors, no calibration, and
#     returns 0. It must never read as a huge negative or clamp to 0.95.
#   - Session switch mid-week: anchors against the new session's cost
#     baseline and returns 0; the previous session's rate is retained.
#   - COST_USD going backwards within a session (should not happen, but a
#     restarted session reports a fresh, smaller total): the fraction floors
#     at 0 rather than going negative.
#   - Cost delta exceeding the rate: clamps at 0.95.
#   - A state file with the wrong field count, or non-numeric fields: treated
#     as absent — anchor and return 0. Never a partial parse.
#   - USED empty or non-numeric (rate_limits absent from the payload): return
#     0 and do not write the state file at all.
#   - Concurrent sessions racing on one state file: last writer wins. The
#     next tick re-anchors either way, so a lost write costs at most one
#     point of precision and needs no locking.

# burn_tick_frac USED SESSION_ID COST_USD STATE_FILE
burn_tick_frac() {
  local used="$1" sess="$2" cost="$3" state_file="$4"

  # USED must be present and integer; otherwise degrade to 0 and touch
  # nothing (not even a read of the state file).
  local usedre='^[0-9]+$'
  if [[ -z "$used" ]] || ! [[ "$used" =~ $usedre ]]; then
    echo 0
    return 0
  fi

  # Read the prior anchor, if any, with a builtin (no fork). `read` with
  # more variables than fields leaves the trailing ones empty; with more
  # fields than variables it folds the remainder (with its separating
  # space) into the last one -- both shapes fail the numeric check below,
  # so a wrong field count is caught for free alongside non-numeric fields.
  local a_used="" a_sess="" a_cost="" a_rate=""
  if [[ -r "$state_file" ]]; then
    read -r a_used a_sess a_cost a_rate < "$state_file" 2>/dev/null
  fi

  local numre='^[0-9]+(\.[0-9]+)?$'
  local prior_valid=0
  if [[ -n "$a_used" && -n "$a_sess" && -n "$a_cost" && -n "$a_rate" \
      && "$a_used" =~ $numre && "$a_cost" =~ $numre && "$a_rate" =~ $numre ]]; then
    prior_valid=1
  fi

  # One awk call does all the arithmetic and decides anchor vs. read: it
  # prints "ANCHOR used sess cost rate" (shell then writes the state file
  # whole) or "FRAC value" (shell just echoes it). This keeps the fork
  # budget at exactly one awk per call on every path.
  local line
  line=$(awk -v used="$used" -v sess="$sess" -v cost="$cost" \
      -v prior_valid="$prior_valid" -v a_used="$a_used" -v a_sess="$a_sess" \
      -v a_cost="$a_cost" -v a_rate="$a_rate" '
    BEGIN {
      eff_rate = 4.5
      if (prior_valid == 1 && a_rate + 0 >= 1 && a_rate + 0 <= 20) {
        eff_rate = a_rate + 0
      }

      anchor = (prior_valid != 1)
      if (!anchor && sess != a_sess) anchor = 1
      if (!anchor && used + 0 != a_used + 0) anchor = 1

      if (anchor) {
        new_rate = eff_rate
        if (prior_valid == 1 && sess == a_sess) {
          delta = cost - a_cost
          if ((used + 0) == (a_used + 0) + 1 && delta > 0.5 && delta < 40) {
            new_rate = 0.5 * eff_rate + 0.5 * delta
          }
        }
        printf "ANCHOR %s %s %s %.6f\n", used, sess, cost, new_rate
      } else {
        delta = cost - a_cost
        frac = delta / eff_rate
        if (frac < 0) frac = 0
        if (frac > 0.95) frac = 0.95
        printf "FRAC %.6f\n", frac
      }
    }
  ' 2>/dev/null)

  local tag f1 f2 f3 f4
  read -r tag f1 f2 f3 f4 <<< "$line"

  if [[ "$tag" == "ANCHOR" ]]; then
    # Atomic write: build the whole line in a per-process temp file, then
    # rename it over the target. A bare truncating `>` has a real
    # interleaving window under concurrent writers; `mv` does not.
    { printf '%s %s %s %s\n' "$f1" "$f2" "$f3" "$f4" > "$state_file.$$"; } 2>/dev/null \
      && mv -f "$state_file.$$" "$state_file" 2>/dev/null
    echo 0
  else
    echo "$f1"
  fi
  return 0
}
