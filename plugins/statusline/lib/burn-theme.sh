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
#           B15 subordinate-colours (plan 003-statusline-meter-colour)
#
# B08 amendment: this file emits NO emoji. The two that lived here — the
# per-model mascot and the companion pet — are gone, because the render they
# fed depends on colour-emoji font coverage the terminal may not have. What
# replaced them is nothing: the model name already names the model, and the
# pet's mood only ever restated the worst of three meters printed beside it.
# Colour is untouched; the rainbow still drifts.
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
#   burn_frame_advance FRAME_FILE
#     Reads the integer in FRAME_FILE, increments it, writes it back, and
#     echoes the new value. Absent, empty, or non-numeric content restarts
#     at 1. Drives the rainbow drift, so a render advances the animation
#     exactly one frame. Echoes 1 and returns 0 when the file cannot be
#     written — the animation freezes, nothing breaks. SURVIVES the pet's
#     removal: the rainbow is its other consumer, so deleting the counter
#     alongside burn_pet would silently freeze the model name's colour.
#
#   burn_model_style MODEL
#     Sets ONE global from the model's display name, matched
#     case-insensitively on a substring: BURN_HUES, an 8-element array of
#     256-colour codes. Echoes nothing.
#       *opus*   -> warm reds and golds   (196 202 208 214 220 226 214 208)
#       *sonnet* -> blues                 (21 27 33 39 45 51 45 39)
#       *fable*  -> purples and magentas  (93 99 135 141 177 201 171 135)
#       *haiku*  -> greens                (22 28 34 40 46 82 118 46)
#       anything else -> full rainbow     (196 208 226 46 51 33 201 129)
#     BURN_MASCOT is NOT set, and no caller may rely on it: the emoji it
#     carried is removed, not relocated. The hue families and their match
#     order are unchanged, so the model name colours exactly as before.
#
#   burn_rainbow TEXT FRAME
#     Echoes TEXT with each character coloured from BURN_HUES, the palette
#     offset by FRAME so the colours drift one step per render. Ends with a
#     reset sequence. Empty TEXT echoes nothing (not a bare reset).
#
#   burn_effort_color EFFORT
#     Echoes the SGR sequence for a reasoning-effort tier, cool to hot:
#     low -> 245 grey, medium -> 39 blue, high -> 214 amber,
#     xhigh and max -> 196 red. Any other value, including empty, echoes the
#     dim sequence (\033[2m).
#
#   burn_plan_color PCT
#     Echoes the colour for a plan-usage meter (weekly `wk` and 5-hour `5h`):
#     >=70 red 196, >=50 orange 208, >=30 yellow 214, else green 40.
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
#     to match burn_plan_color's shape. The denominator behind PCT is the
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
#   burn_trend_color TREND                              [B14, plan 003]
#     Echoes the colour for the weekly trend arrow's magnitude, with a +/-3
#     DEAD BAND that reads as on-track. The dead band is this plugin's
#     substitute for the upstream's green ✓ glyph, which is deliberately not
#     adopted (plan 003 constraint 2): the whole point of plan 002 was that
#     glyph coverage on the user's terminal is not assumable, and the
#     file-wide no-non-ASCII invariant below is what enforces it.
#     Reads off burn_metrics' FIXED sign convention — POSITIVE means ahead of
#     the awake even-burn line, i.e. burning fast enough to cap before the
#     reset — so the scale is deliberately asymmetric:
#       |TREND| <= 3   green 40   on track; the dead band
#       TREND >= 15    red 196    far ahead of the line
#       TREND >= 8     orange 208
#       TREND > 3      yellow 214
#       TREND < -3     grey 245   behind the line: subscription going unused,
#                                 which is not a hazard, so the tier that
#                                 says "nothing to act on" rather than a
#                                 warning colour.
#     The arrow character itself stays in the renderer; this function emits
#     colour only.
#     TREND's domain is a bare optionally-signed INTEGER, which is what
#     burn_metrics produces; a leading `-` is normal input, and a bare `-` is
#     not a number. A decimal is outside the domain on the same terms as
#     burn_ctx_color above: a single bare opener, silently, rc 0, with no
#     band specified.
#
#   burn_diff_color KIND                                [B15, plan 003]
#     Echoes the colour for one half of the session's +added/-removed pair:
#     "add" -> green 40, "del" -> red 196. The diffstat convention, chosen
#     because it is the one every reader already knows. This is a FIXED
#     colour, not a scale: the counts have no thresholds and no severity.
#     KIND is matched CASE-SENSITIVELY: "add" and "del" are the only two
#     recognised tokens, and "ADD" is an unrecognised kind like any other.
#     (burn_model_style case-folds because it matches a model name a payload
#     supplies; this one matches a literal the renderer itself passes, so
#     there is nothing to fold.)
#     Any other KIND, empty included, echoes the dim sequence (\033[2m) —
#     never nothing, because an empty echo leaves the text uncoloured while
#     the caller still emits its reset, which is exactly how colour leaks
#     into the next segment.
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
# Errors:
#   No function in this file writes to stdout except its documented value,
#   and none writes to stderr in normal operation — output lands directly in
#   the user's statusline. Unparseable numeric input takes the safest tier
#   (the dim or green end) rather than failing, except where documented above
#   as a non-zero return. For the functions plan 003 adds, "safest tier" is
#   green 40 for burn_ctx_color and burn_trend_color and the dim sequence for
#   burn_diff_color: a statusline that cannot parse a figure must never be the
#   thing that raises an alarm about it.
#
# Invariants:
#   - Forks NO external process. Every function is pure bash builtins,
#     including burn_frame_advance's read and write (`read < file`, not
#     `cat`) — the warm-render budget in scripts/context.sh has no room for
#     a fork here.
#   - No function reads the environment or any file except FRAME_FILE.
#   - Every emitted colour sequence is closed BY WHOEVER OPENED IT. Only
#     burn_rainbow returns coloured TEXT, and it closes that text with
#     \033[0m itself. Every burn_*_color function returns a bare OPENER with
#     no reset and its caller closes the segment — that is the contract for
#     all eight of them, not an exception to this clause. Either way, no
#     colour leaks into the next segment.
#   - Thresholds are boundary-inclusive exactly as written (>=), and are
#     locked constants, not configurable.
#   - bash 3.2 compatible — no associative arrays, no ${var^^}.
#
# Edge cases:
#   - burn_frame_advance at integer overflow: the counter is only ever used
#     modulo 8 and modulo the hue count, so it may wrap or reset freely.
#   - A model name with several matches ("Claude Opus Haiku"): the first
#     match in the documented order wins, deterministically.
#   - burn_rainbow on multi-byte or emoji text: colours are applied per
#     character as bash counts them; the text must never be truncated or
#     reordered, even if the colouring lands oddly.
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
#   - burn_trend_color at exactly 3 and exactly -3: green 40. The dead band
#     is inclusive at BOTH ends, so the smallest coloured magnitude is 4.
#   - burn_trend_color at exactly 8 and exactly 15: the higher tier, as
#     above. A negative trend has ONE tier below -3, not a mirror of the
#     three above it — asymmetry is the point, not an omission.
#   - burn_diff_color with no argument at all, as opposed to an unrecognised
#     one: identical handling, the dim sequence. There is no third state.
#   - burn_countdown_color called WITH an argument: ignored entirely; the
#     function takes none and its output never varies.
#   - NO function in this file emits a non-ASCII character. That is the
#     B08 invariant a test can check mechanically over the whole file, and
#     it is what keeps a mascot or a mood glyph from creeping back in. It is
#     also what B14 relies on: the upstream's on-track ✓ cannot be adopted
#     here without amending this invariant, and plan 003 chose the dead-band
#     colour instead precisely so it does not have to be.

# burn_frame_advance FRAME_FILE
burn_frame_advance() {
  local file="$1" val="" next
  if [[ -f "$file" ]]; then
    { read -r val < "$file"; } 2>/dev/null
  fi
  if [[ "$val" =~ ^[0-9]+$ ]]; then
    next=$(( val + 1 ))
    (( next < 0 )) && next=1
  else
    next=1
  fi
  if { printf '%s' "$next" > "$file"; } 2>/dev/null; then
    echo "$next"
    return 0
  fi
  echo 1
  return 0
}

# burn_model_style MODEL  -> sets BURN_HUES
burn_model_style() {
  local model="$1" restore_nocasematch=0
  if ! shopt -q nocasematch; then
    shopt -s nocasematch
    restore_nocasematch=1
  fi
  case "$model" in
    *opus*)
      BURN_HUES=(196 202 208 214 220 226 214 208)
      ;;
    *sonnet*)
      BURN_HUES=(21 27 33 39 45 51 45 39)
      ;;
    *fable*)
      BURN_HUES=(93 99 135 141 177 201 171 135)
      ;;
    *haiku*)
      BURN_HUES=(22 28 34 40 46 82 118 46)
      ;;
    *)
      BURN_HUES=(196 208 226 46 51 33 201 129)
      ;;
  esac
  (( restore_nocasematch )) && shopt -u nocasematch
  return 0
}

# burn_rainbow TEXT FRAME
burn_rainbow() {
  local text="$1" frame="$2" len i hue
  len=${#text}
  (( len == 0 )) && return 0
  for (( i = 0; i < len; i++ )); do
    hue="${BURN_HUES[(i + frame) % 8]}"
    printf '\033[38;5;%sm%s' "$hue" "${text:i:1}"
  done
  printf '\033[0m'
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

# burn_plan_color PCT
burn_plan_color() {
  local pct="$1"
  if [[ "$pct" =~ ^-?[0-9]+$ ]]; then
    if (( pct >= 70 )); then printf '\033[38;5;196m'; return 0; fi
    if (( pct >= 50 )); then printf '\033[38;5;208m'; return 0; fi
    if (( pct >= 30 )); then printf '\033[38;5;214m'; return 0; fi
  fi
  printf '\033[38;5;40m'
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

# burn_trend_color TREND
burn_trend_color() {
  local trend="$1" abs
  if [[ "$trend" =~ ^-?[0-9]+$ ]]; then
    if (( trend < 0 )); then abs=$(( -trend )); else abs=$trend; fi
    if (( abs <= 3 )); then printf '\033[38;5;40m'; return 0; fi
    if (( trend >= 15 )); then printf '\033[38;5;196m'; return 0; fi
    if (( trend >= 8 )); then printf '\033[38;5;208m'; return 0; fi
    if (( trend > 3 )); then printf '\033[38;5;214m'; return 0; fi
    printf '\033[38;5;245m'
    return 0
  fi
  printf '\033[38;5;40m'
  return 0
}

# burn_diff_color KIND
burn_diff_color() {
  local kind="$1"
  case "$kind" in
    add) printf '\033[38;5;40m' ;;
    del) printf '\033[38;5;196m' ;;
    *) printf '\033[2m' ;;
  esac
  return 0
}

# burn_countdown_color
burn_countdown_color() {
  printf '\033[2m'
  return 0
}

# burn_reset_str RESET_EPOCH NOW
burn_reset_str() {
  local reset_epoch="$1" now="$2" remaining hours minutes
  [[ "$reset_epoch" =~ ^-?[0-9]+$ ]] || return 1
  [[ "$now" =~ ^-?[0-9]+$ ]] || now=0
  remaining=$(( reset_epoch - now ))
  if (( remaining <= 0 )); then
    echo "0m"
    return 0
  fi
  hours=$(( remaining / 3600 ))
  minutes=$(( (remaining % 3600) / 60 ))
  if (( hours >= 1 )); then
    echo "${hours}h${minutes}m"
  else
    echo "${minutes}m"
  fi
  return 0
}
