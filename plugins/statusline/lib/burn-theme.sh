#!/bin/bash
#
# Presentation layer for the statusline's burnrate line: hue families, meter
# colour scales, and reset countdowns.
#
# Ported from claude-statusline-burnrate — MIT © Gui-Gou
# https://github.com/Gui-Gou/claude-statusline-burnrate
#
# Contract: B03 burn-theme (plan 001-statusline-burnrate-uplift),
#           amended by B08 burn-theme-deemoji (plan 002-statusline-emoji-removal),
#           extended by B13 ctx-fullness-colour, B14 trend-colour and
#           B15 subordinate-colours (plan 003-statusline-meter-colour),
#           rescaled by B16 trend-colour-rescale (plan 003-angry-pace-colours)
#
# B08 amendment: this file emits NO emoji. The two that lived here — the
# per-model mascot and the companion pet — are gone, because the render they
# fed depends on colour-emoji font coverage the terminal may not have. What
# replaced them is nothing: the model name already names the model, and the
# pet's mood only ever restated the worst of three meters printed beside it.
#
# B05 amendment (line2-groups, plan 001-statusline-glance-uplift): the drifting
# per-character rainbow is retired along with the animation counter and the hue
# families that fed it, and the +added/-removed pair's fixed colours with the
# segment they coloured. burn_frame_advance, burn_model_style, burn_rainbow and
# burn_diff_color are deleted outright; burn_model_color's one flat colour per
# family is what the model name takes now.
#
# Behavior:
#   Every visual decision the burnrate line makes lives here, so the
#   renderer in scripts/context.sh assembles already-coloured strings and
#   holds no colour logic of its own. Nothing in this file computes a
#   metric; it only maps values to appearance.
#
#   Colours are emitted as 256-colour SGR sequences (\033[38;5;Nm), matching
#   the convention the rest of context.sh already uses for the State and
#   git-sync segments. This is a deliberate deviation from the upstream,
#   which mixes basic ANSI (\033[32m) with 256-colour; the tiers and their
#   thresholds are unchanged, only their expression.
#
# Inputs / Outputs:
#   burn_effort_color EFFORT
#     Echoes the SGR sequence for a reasoning-effort tier, cool to hot:
#     low -> 245 grey, medium -> 39 blue, high -> 214 amber,
#     xhigh and max -> 196 red. Any other value, including empty, echoes the
#     dim sequence (\033[2m).
#
#   burn_today_color PCT
#     Echoes the colour for today's remaining share. The displayed value IS
#     the fraction still unspent, so thresholds read directly off it:
#     >=50 green 40, >=25 yellow 214, >=10 orange 208, else red 196.
#     Negative values (past tonight's checkpoint) fall to red.
#
#   burn_pace_color PACE
#     Echoes the colour for sustainable %/day against the ~14%/day even-burn
#     baseline. A HIGH pace is healthy — more runway per day — so the scale
#     runs the opposite way to the meters above: >=12 green 40, >=8 yellow
#     214, >=5 orange 208, else red 196. Accepts a decimal and compares on
#     its integer part.
#
#   burn_ctx_state USED_TOKENS BUDGET IDLE_SECONDS
#     Echoes two space-separated fields, "LEVEL COLOR", for the `ctx` meter.
#     This keeps the plugin's existing idle-aware tri-state rather than the
#     upstream's four-tier percentage scale, per decision 002
#     (.local/decisions/002-context-meter-source.md) — LEVEL is also what
#     .local/.ctx-status.json publishes, so the two can never disagree.
#       "cold 196"  USED_TOKENS >= BUDGET, or occupancy >=60% and idle >=2700s
#       "warn 208"  occupancy >=60% and idle >=1800s
#       "ok 40"     otherwise
#     Occupancy is the integer floor of 100*USED_TOKENS/BUDGET. The 2700s
#     threshold sits 15 minutes inside the ~1h prompt-cache TTL, so red means
#     "compact now, still time", not "too late". These thresholds are locked,
#     never environment-configurable.
#
#   burn_reset_str RESET_EPOCH NOW
#     Echoes the time remaining until RESET_EPOCH as "4h54m" at an hour or
#     more, "12m" below that. A past or equal RESET_EPOCH echoes "0m", never
#     a negative. An empty or non-numeric RESET_EPOCH echoes nothing and
#     returns 1, so the caller omits the segment.
#
#   burn_ctx_color PCT                                  [B13, plan 003]
#     Echoes the colour for the `ctx` meter as a function of HOW FULL the
#     context is — the fix for #306, where the meter was green at every
#     occupancy because its colour came from burn_ctx_state's session
#     FRESHNESS tier instead:
#       >=60 red 196, >=40 orange 208, >=20 yellow 214, else green 40.
#     These are the upstream reference's ctxcol bands, expressed descending
#     like every other meter scale here. The denominator behind PCT is the
#     auto-compaction window, so 100 IS compaction and red deliberately
#     covers the last 40% of a session.
#     burn_ctx_state is NOT changed and NOT replaced: its LEVEL is what
#     .local/.ctx-status.json publishes and has a second consumer, so the two
#     now answer different questions on purpose — this one "how full", that
#     one "how stale". A caller wanting the staleness tier still calls it.
#     PCT's domain is a bare optionally-signed INTEGER; the caller computes
#     it with integer arithmetic. A decimal is outside that domain, and the
#     only promise made for one is the same promise made for any unparseable
#     input: a single bare opener, silently, rc 0. No band is specified for
#     it and none should be relied on. (burn_pace_color documents decimal
#     handling because its caller genuinely passes decimals; this one's
#     does not.)
#
#   burn_trend_color TREND               [B14, rescaled by B16, plan 003]
#     Echoes the colour for the weekly trend arrow's magnitude. Only the
#     over-pace side carries a colour, because a warning colour means the
#     user needs to change their behaviour; the calm side is colourless
#     rather than differently coloured.
#     Reads off burn_metrics' FIXED sign convention — POSITIVE means ahead of
#     the awake even-burn line, i.e. burning fast enough to cap before the
#     reset — so the scale is deliberately asymmetric, and since B16 the
#     asymmetry is total: three tiers above zero and none at or below it.
#       TREND > 10     red 196    far ahead of the line
#       TREND >= 6     orange 208
#       TREND >= 1     yellow 214 the smallest coloured magnitude
#       TREND <= 0     nothing    the empty string. B14's green +/-3 dead
#                                 band and its grey behind-pace tier are
#                                 both retired: being on or behind the line
#                                 asks nothing of the user, so it says
#                                 nothing.
#     The empty calm side is also why the upstream's green check-mark glyph
#     stays unadopted (plan 003 constraint 2): glyph coverage on the user's
#     terminal is not assumable, and the file-wide no-non-ASCII invariant
#     below is what enforces it.
#     The arrow character itself stays in the renderer; this function emits
#     colour only.
#     TREND's domain is a bare optionally-signed INTEGER, which is what
#     burn_metrics produces; a leading `-` is normal input, and a bare `-` is
#     not a number. A decimal is outside the domain, and unparseable input of
#     any form takes the same path as the calm side: nothing emitted, rc 0.
#
#   burn_countdown_color                                [B15, plan 003]
#     Takes NO argument and echoes the dim sequence (\033[2m) for the
#     parenthesised reset countdown. Dim is the decision, not a fallback:
#     the countdown is subordinate to the meter it follows, and dimming it
#     is what makes the eye reach `5h 20%` before `(3h27m)`. It exists as a
#     function rather than a literal in the renderer for the same reason
#     every other colour here does — so no colour decision lives in
#     scripts/context.sh.
#
#   burn_pet — REMOVED by B08. The function, its four mood tiers, its
#     8-frame face arrays and its effect-character arrays are deleted
#     outright; nothing replaces it. Callers must not reference it, and
#     `declare -f burn_pet` must find nothing. The mood it expressed was the
#     worst of the three meters, each of which is printed on the same line
#     with its own colour scale, so no information leaves with it.
#
#   burn_plan_color — REMOVED by B16 (plan 003-angry-pace-colours), on the
#     burn_pet pattern: the function and its four bands are deleted outright
#     and nothing replaces them. Callers must not reference it, and
#     `declare -f burn_plan_color` must find nothing. The weekly and 5-hour
#     used% figures it coloured now render plain, because a high figure late
#     in the window is information rather than an alarm.
#
# Errors:
#   No function in this file writes to stdout except its documented value,
#   and none writes to stderr in normal operation — output lands directly in
#   the user's statusline. Unparseable numeric input takes the safest tier
#   (the dim or green end) rather than failing, except where documented above
#   as a non-zero return. A statusline that cannot parse a figure must never
#   be the thing that raises an alarm about it: for burn_ctx_color the safest
#   tier is green 40, and for burn_trend_color since B16 it is no colour at
#   all.
#
# Invariants:
#   - Forks NO external process. Every function is pure bash builtins — the
#     warm-render budget in scripts/context.sh has no room for a fork here.
#   - No function reads the environment or any file at all. Since B05 retired
#     burn_frame_advance, the animation counter it read and wrote is gone with
#     it, so nothing here touches the filesystem.
#   - Every emitted colour sequence is closed BY WHOEVER OPENED IT. Every
#     burn_*_color function returns a bare OPENER with no reset and its caller
#     closes the segment — that is the contract for all of them, not an
#     exception to this clause, so no colour leaks into the next segment.
#   - Thresholds are boundary-inclusive exactly as written (>=), and are
#     locked constants, not configurable.
#   - bash 3.2 compatible — no associative arrays, no ${var^^}.
#
# Edge cases:
#   - A model name with several matches ("Claude Opus Haiku"): the first
#     match in the documented order wins, deterministically.
#   - burn_ctx_state with BUDGET <= 0: occupancy is undefined, so return
#     "ok 40" rather than dividing by zero.
#   - burn_ctx_state at exactly USED_TOKENS == BUDGET: cold, regardless of
#     idle — the existing suite pins this boundary.
#   - burn_reset_str at exactly 60 minutes remaining: "1h0m", not "60m".
#   - burn_ctx_color above 100 (an overrun — the occupancy math in
#     scripts/context.sh is deliberately non-saturating): red 196, the same
#     as any other value at or above 60. Nothing clamps.
#   - burn_ctx_color at exactly 20, 40 and 60: the higher tier, since every
#     threshold in this file is >= and boundary-inclusive.
#   - burn_ctx_color on a negative percent (possible after a clock step):
#     green 40, via the same path as any value below 20.
#   - burn_trend_color at exactly 1, 6 and 11: each opens its tier, while
#     exactly 0, 5 and 10 take the tier below. 1 is therefore the smallest
#     coloured magnitude, and 0 is colourless.
#   - burn_trend_color on any negative, and on any unparseable input: the
#     empty string, byte-exactly — no newline, no space, no fallback colour.
#     A negative trend has NO tier at all, not a mirror of the three above
#     zero; asymmetry is the point, not an omission.
#   - burn_countdown_color called WITH an argument: ignored entirely; the
#     function takes none and its output never varies.
#   - NO function in this file emits a non-ASCII character. That is the
#     B08 invariant a test can check mechanically over the whole file, and
#     it is what keeps a mascot or a mood glyph from creeping back in. It is
#     also what the trend scale relies on: the upstream's on-track ✓ cannot
#     be adopted here without amending this invariant, and since B16 the
#     on-track state emits nothing at all rather than a glyph.

# Contract: B03 model-colour
#
# Behavior:
#   Maps a model display name to ONE flat 256-colour SGR opener, matched
#   case-insensitively on a substring in this fixed order:
#     haiku  -> 117 (light blue)
#     sonnet ->  75 (mid blue)
#     opus   ->  33 (blue)
#     fable  -> 141 (purple)
#     anything else -> 245 (dim grey)
#   Blue deepens with capability; purple sits outside the ramp. This replaces
#   the retired burn_model_style + burn_rainbow pair, whose drifting
#   per-character palette is the "fancy colouring" this plan removes.
#
# Inputs:
#   MODEL  one string, the payload's model.display_name, possibly empty.
#
# Outputs:
#   A bare SGR opener with NO reset; the caller closes it, which is the
#   contract every burn_*_color function in this file already follows.
#
# Errors:
#   None. An empty or unrecognised name takes the dim grey tier rather than
#   failing or echoing nothing -- an empty echo would leave the text uncoloured
#   while the caller still emits its reset, which is how colour leaks into the
#   next segment.
#
# Invariants:
#   - Forks no external process. Reads no environment and no file.
#   - bash 3.2 compatible -- no associative arrays, no ${var^^}.
#   - Emits no non-ASCII character, preserving the file-wide invariant a test
#     checks mechanically.
#   - nocasematch is saved and restored around the match, as the retired
#     burn_model_style did.
#
# Edge cases:
#   - A name matching two families ("Claude Opus Haiku"): the FIRST match in
#     the documented order wins, deterministically.
#   - A parenthesised suffix ("Opus 5 (1M context)") still matches -- trimming
#     is the renderer's job, not this function's.
#   - Colour choice does not vary with frame, time, or any other input: the
#     same name always gives the same code. That invariance IS what "remove
#     the fancy colouring" means, so it is a contract clause, not a detail.
#
# SCAFFOLD NOTE (B03): this stub could not be written at scaffold time --
# burn-theme.test.sh pinned the file's exact function roster and count, so any
# new function turned the suite red and blocked worktree creation. The test wave
# has now updated the roster, so the stub lands here, in this unit worktree,
# added by the orchestrator. Without it the red run reads as a
# "command not found" collection error rather than a right-reason red.
#
# burn_model_color MODEL
burn_model_color() {
  local model="$1" restore_nocasematch=0 code
  if ! shopt -q nocasematch; then
    shopt -s nocasematch
    restore_nocasematch=1
  fi
  case "$model" in
    *haiku*) code=117 ;;
    *sonnet*) code=75 ;;
    *opus*) code=33 ;;
    *fable*) code=141 ;;
    *) code=245 ;;
  esac
  (( restore_nocasematch )) && shopt -u nocasematch
  printf '\033[38;5;%sm' "$code"
  return 0
}

# burn_effort_color EFFORT
burn_effort_color() {
  local effort="$1"
  case "$effort" in
    low) printf '\033[38;5;245m' ;;
    medium) printf '\033[38;5;39m' ;;
    high) printf '\033[38;5;214m' ;;
    xhigh|max) printf '\033[38;5;196m' ;;
    *) printf '\033[2m' ;;
  esac
  return 0
}

# burn_today_color PCT
burn_today_color() {
  local pct="$1"
  if [[ "$pct" =~ ^-?[0-9]+$ ]]; then
    if (( pct >= 50 )); then printf '\033[38;5;40m'; return 0; fi
    if (( pct >= 25 )); then printf '\033[38;5;214m'; return 0; fi
    if (( pct >= 10 )); then printf '\033[38;5;208m'; return 0; fi
    printf '\033[38;5;196m'
    return 0
  fi
  printf '\033[38;5;40m'
  return 0
}

# burn_pace_color PACE
burn_pace_color() {
  local int="${1%%.*}"
  if [[ "$int" =~ ^-?[0-9]+$ ]]; then
    if (( int >= 12 )); then printf '\033[38;5;40m'; return 0; fi
    if (( int >= 8 )); then printf '\033[38;5;214m'; return 0; fi
    if (( int >= 5 )); then printf '\033[38;5;208m'; return 0; fi
    printf '\033[38;5;196m'
    return 0
  fi
  printf '\033[38;5;40m'
  return 0
}

# burn_ctx_state USED_TOKENS BUDGET IDLE_SECONDS
burn_ctx_state() {
  local used="$1" budget="$2" idle="$3" pct
  [[ "$used" =~ ^-?[0-9]+$ ]] || used=0
  [[ "$budget" =~ ^-?[0-9]+$ ]] || budget=0
  [[ "$idle" =~ ^-?[0-9]+$ ]] || idle=0
  if (( budget <= 0 )); then
    echo "ok 40"
    return 0
  fi
  if (( used >= budget )); then
    echo "cold 196"
    return 0
  fi
  pct=$(( 100 * used / budget ))
  if (( pct >= 60 && idle >= 2700 )); then
    echo "cold 196"
  elif (( pct >= 60 && idle >= 1800 )); then
    echo "warn 208"
  else
    echo "ok 40"
  fi
  return 0
}

# burn_ctx_color PCT
burn_ctx_color() {
  local pct="$1"
  if [[ "$pct" =~ ^-?[0-9]+$ ]]; then
    if (( pct >= 60 )); then printf '\033[38;5;196m'; return 0; fi
    if (( pct >= 40 )); then printf '\033[38;5;208m'; return 0; fi
    if (( pct >= 20 )); then printf '\033[38;5;214m'; return 0; fi
  fi
  printf '\033[38;5;40m'
  return 0
}

# Contract: B16 trend-colour-rescale (plan 003-angry-pace-colours)
#
# Behavior:
#   Colour states over-pace magnitude ONLY — "warning colours mean you need
#   to change your behaviour". Two changes land together:
#   1. burn_plan_color is DELETED outright, the burn_pet pattern: the
#      function and its bands go, nothing replaces them, callers must not
#      reference it, and `declare -f burn_plan_color` must find nothing.
#      The used% figures it coloured render plain (see B17 in
#      scripts/context.sh) — a high figure late in the window is
#      information, not an alarm.
#   2. burn_trend_color is RESCALED:
#        TREND >  10          red 196
#        6  <= TREND <= 10    orange 208
#        1  <= TREND <= 5     yellow 214
#        TREND <= 0           NOTHING — the empty string. The green dead
#                             band and the grey behind-pace tier are both
#                             retired; the calm side is colourless.
# Inputs:
#   TREND — bare optionally-signed integer (burn_metrics' fixed sign
#   convention, positive = ahead of the even-burn line). Unparseable input
#   (bare `-`, decimal, empty) emits nothing, rc 0: the safest tier is now
#   "no alarm", i.e. no colour.
# Outputs:
#   Exactly one bare SGR opener for TREND >= 1; the empty string otherwise.
#   Never a reset, never anything else, never stderr.
# Errors:
#   None; rc 0 always.
# Invariants:
#   Pure builtins, no fork, no file/env reads, no non-ASCII, thresholds
#   boundary-inclusive as written, bash 3.2. The caller-closes contract is
#   unchanged: the renderer's reset after an empty opener is a harmless
#   no-op. The file header's trend-scale and plan-colour paragraphs are
#   updated/removed as part of this block's implementation.
# Edge cases:
#   Exactly 1, 6 and 11 open their tier; exactly 0, 5 and 10 take the tier
#   below (0 = colourless); all negatives colourless; unparseable
#   colourless.
#
# burn_trend_color TREND
burn_trend_color() {
  local trend="$1"
  if [[ "$trend" =~ ^-?[0-9]+$ ]]; then
    if (( trend > 10 )); then printf '\033[38;5;196m'; return 0; fi
    if (( trend >= 6 )); then printf '\033[38;5;208m'; return 0; fi
    if (( trend >= 1 )); then printf '\033[38;5;214m'; return 0; fi
  fi
  return 0
}

# burn_countdown_color
burn_countdown_color() {
  printf '\033[2m'
  return 0
}

# Contract: B04 reset-str-days (plan 001-statusline-glance-uplift)
#
# Behavior:
#   Extends the existing countdown with a DAY unit, so a weekly reset reads
#   "2d4h" rather than "163h12m". Three bands, checked in order:
#     >= 24 hours  ->  "<D>d<H>h"
#     >= 1 hour    ->  "<H>h<M>m"   (the existing form, unchanged)
#     below that   ->  "<M>m"       (the existing form, unchanged)
#
# Inputs:
#   RESET_EPOCH  integer epoch seconds of the next reset
#   NOW          integer epoch seconds; a non-integer is treated as 0, as
#                today
#
# Outputs:
#   One string, no colour. The caller wraps it in parens and dims it.
#
# Errors:
#   Unchanged: an empty or non-numeric RESET_EPOCH echoes nothing and returns
#   1, so the caller omits the countdown AND its parens together — never an
#   empty "()".
#
# Invariants:
#   - Forks no external process. Pure.
#   - Existing behaviour below 24 hours is BYTE-IDENTICAL, including the
#     pinned "1h0m" at exactly 60 minutes. This block adds a band; it does not
#     re-derive the two that exist.
#   - bash 3.2 compatible.
#
# Edge cases:
#   - Exactly 24 hours: "1d0h", not "24h0m".
#   - Exactly 60 minutes: "1h0m", unchanged.
#   - A past or equal RESET_EPOCH: "0m", never a negative.
#   - A reset more than 9 days out (reachable only from a malformed payload):
#     renders the day count as-is rather than clamping.
#
# SCAFFOLD NOTE (B04): the body below is the PREVIOUS contract's implementation,
# left in place deliberately — same reason as B05 in scripts/context.sh. Stubbing
# it out would leave the suite red, and `worktree.sh add` refuses to create a unit
# worktree on a red baseline. It does not satisfy the contract above (it renders
# 24 hours as "24h0m", not "1d0h"), which is what makes U02's tests red for the
# right reason; the implementation wave adds the day band.
#
# burn_reset_str RESET_EPOCH NOW
burn_reset_str() {
  local reset_epoch="$1" now="$2" remaining days hours minutes
  [[ "$reset_epoch" =~ ^-?[0-9]+$ ]] || return 1
  [[ "$now" =~ ^-?[0-9]+$ ]] || now=0
  remaining=$(( reset_epoch - now ))
  if (( remaining <= 0 )); then
    echo "0m"
    return 0
  fi
  hours=$(( remaining / 3600 ))
  minutes=$(( (remaining % 3600) / 60 ))
  if (( hours >= 24 )); then
    days=$(( hours / 24 ))
    echo "${days}d$(( hours % 24 ))h"
  elif (( hours >= 1 )); then
    echo "${hours}h${minutes}m"
  else
    echo "${minutes}m"
  fi
  return 0
}

