#!/bin/bash
#
# Presentation layer for the statusline's burnrate line: mascots, hue
# families, meter colour scales, reset countdowns, and the companion pet.
#
# Ported from claude-statusline-burnrate — MIT © Gui-Gou
# https://github.com/Gui-Gou/claude-statusline-burnrate
#
# Contract: B03 burn-theme (plan 001-statusline-burnrate-uplift)
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
#     at 1. Drives both the rainbow drift and the pet, so a render advances
#     the animation exactly one frame. Echoes 1 and returns 0 when the file
#     cannot be written — the animation freezes, nothing breaks.
#
#   burn_model_style MODEL
#     Sets two globals from the model's display name, matched
#     case-insensitively on a substring: BURN_MASCOT (one emoji) and
#     BURN_HUES (an 8-element array of 256-colour codes). Echoes nothing.
#       *opus*   -> 🎭  warm reds and golds   (196 202 208 214 220 226 214 208)
#       *sonnet* -> 🪶  blues                 (21 27 33 39 45 51 45 39)
#       *fable*  -> 🦄  purples and magentas  (93 99 135 141 177 201 171 135)
#       *haiku*  -> 🌸  greens                (22 28 34 40 46 82 118 46)
#       anything else -> 🤖 full rainbow      (196 208 226 46 51 33 201 129)
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
#     Echoes the colour for a plan-usage meter (weekly 🎯 and 5-hour 🔥):
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
#     Echoes two space-separated fields, "LEVEL COLOR", for the 🧠 meter.
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
#   burn_pet STRESS FRAME
#     Echoes the companion pet: a face plus a dimmed effect character,
#     selected by FRAME modulo 8 from the mood tier STRESS falls in:
#       >=70 panic    faces 😾🙀😾😿😾🙀😾🙀   effects 🔥💢💥🔥💢💥🔥💢
#       >=50 nervous  faces 🙀😿🙀😿🙀😾🙀😿   effects 💦°💦∘💦°💦∘
#       >=30 alert    faces 😼🐱😼😽😼🐱😼🐱   effects ·‥…‥·‥…‥
#       else happy    faces 😺😸😺😹😺😸😻😸   effects ♪♫♬♪♫♬♫♪
#     Both the face and the effect vary within every tier, so each render
#     visibly moves. STRESS is the WORST of the three meters (context, 5-hour,
#     weekly); the caller computes it, this function does not.
#
# Errors:
#   No function in this file writes to stdout except its documented value,
#   and none writes to stderr in normal operation — output lands directly in
#   the user's statusline. Unparseable numeric input takes the safest tier
#   (the dim or green end) rather than failing, except where documented above
#   as a non-zero return.
#
# Invariants:
#   - Forks NO external process. Every function is pure bash builtins,
#     including burn_frame_advance's read and write (`read < file`, not
#     `cat`) — the warm-render budget in scripts/context.sh has no room for
#     a fork here.
#   - No function reads the environment or any file except FRAME_FILE.
#   - Every emitted colour sequence is closed: any function returning
#     coloured text ends it with \033[0m, so no colour leaks into the next
#     segment.
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
#   - burn_pet with an empty or non-numeric STRESS: the happy tier.
#   - burn_reset_str at exactly 60 minutes remaining: "1h0m", not "60m".

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

# burn_model_style MODEL  -> sets BURN_MASCOT, BURN_HUES
burn_model_style() {
  local model="$1" restore_nocasematch=0
  if ! shopt -q nocasematch; then
    shopt -s nocasematch
    restore_nocasematch=1
  fi
  case "$model" in
    *opus*)
      BURN_MASCOT="🎭"
      BURN_HUES=(196 202 208 214 220 226 214 208)
      ;;
    *sonnet*)
      BURN_MASCOT="🪶"
      BURN_HUES=(21 27 33 39 45 51 45 39)
      ;;
    *fable*)
      BURN_MASCOT="🦄"
      BURN_HUES=(93 99 135 141 177 201 171 135)
      ;;
    *haiku*)
      BURN_MASCOT="🌸"
      BURN_HUES=(22 28 34 40 46 82 118 46)
      ;;
    *)
      BURN_MASCOT="🤖"
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

# burn_pet STRESS FRAME
burn_pet() {
  local stress="$1" frame="$2" idx faces effects
  [[ "$stress" =~ ^-?[0-9]+$ ]] || stress=0
  [[ "$frame" =~ ^-?[0-9]+$ ]] || frame=0
  idx=$(( frame % 8 ))
  (( idx < 0 )) && idx=$(( idx + 8 ))
  if (( stress >= 70 )); then
    faces=("😾" "🙀" "😾" "😿" "😾" "🙀" "😾" "🙀")
    effects=("🔥" "💢" "💥" "🔥" "💢" "💥" "🔥" "💢")
  elif (( stress >= 50 )); then
    faces=("🙀" "😿" "🙀" "😿" "🙀" "😾" "🙀" "😿")
    effects=("💦" "°" "💦" "∘" "💦" "°" "💦" "∘")
  elif (( stress >= 30 )); then
    faces=("😼" "🐱" "😼" "😽" "😼" "🐱" "😼" "🐱")
    effects=("·" "‥" "…" "‥" "·" "‥" "…" "‥")
  else
    faces=("😺" "😸" "😺" "😹" "😺" "😸" "😻" "😸")
    effects=("♪" "♫" "♬" "♪" "♫" "♬" "♫" "♪")
  fi
  printf '%s\033[2m%s\033[0m' "${faces[$idx]}" "${effects[$idx]}"
  return 0
}
