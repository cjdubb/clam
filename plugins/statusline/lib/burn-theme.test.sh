#!/bin/bash
# Table-driven functional tests for burn-theme.sh: the presentation layer for
# the burnrate line -- per-model mascot and hue family, the frame-drifting
# rainbow, the reasoning-effort colour, the four meter colour scales (plan,
# today, pace, ctx-state), the reset countdown string, and the 8-frame
# companion pet. Every function is a pure mapping from value to appearance
# (Contract: B03 burn-theme, plan 001-statusline-burnrate-uplift), so these
# tests are table-driven and pin the contract's exact literal colour codes,
# mascots, hue arrays and pet frames -- not a paraphrase of them.
#
# Two functions in the contract (burn_rainbow's per-frame hue offset,
# burn_pet's face/effect separator) do not have a byte-exact formula written
# down, so those sections assert the documented BEHAVIOUR (drift, ordering,
# reset-termination, text preservation) via structural checks rather than
# guessing an exact output string.
#
# Run: bash plugins/statusline/lib/burn-theme.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/burn-theme.sh"
. "$THEME"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

ESC=$(printf '\033')
FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ============================================================================
# burn_frame_advance FRAME_FILE -- advances and persists; absent/empty/
# non-numeric content restarts at 1; unwritable path echoes 1, returns 0.
# ============================================================================

# Absent file: first call starts the sequence at 1, then advances and
# persists across repeated calls on the same file (behaviour + outputs).
SEQ_FRAME="$TMPROOT/seq-frame"   # deliberately not pre-created
r1=$(burn_frame_advance "$SEQ_FRAME"); c1=$?
r2=$(burn_frame_advance "$SEQ_FRAME")
r3=$(burn_frame_advance "$SEQ_FRAME")
check "burn_frame_advance on an absent file starts the sequence at 1" "$r1" "1"
check "burn_frame_advance exit code 0 on the first (absent-file) call" "$c1" "0"
check "burn_frame_advance advances to 2 on the second call" "$r2" "2"
check "burn_frame_advance advances to 3 on the third call" "$r3" "3"
check "burn_frame_advance persists 3 in the frame file" "$(cat "$SEQ_FRAME")" "3"

# Positive control: valid existing numeric content is read and incremented
# (not just always reset to 1).
PRESET_FRAME="$TMPROOT/preset-frame"
printf '5' > "$PRESET_FRAME"
out=$(burn_frame_advance "$PRESET_FRAME")
check "burn_frame_advance increments existing valid content (5 -> 6)" "$out" "6"
check "burn_frame_advance persists the incremented value" "$(cat "$PRESET_FRAME")" "6"

# Absent / empty / non-numeric content all restart at 1 (edge cases).
EMPTY_FRAME="$TMPROOT/empty-frame"
: > "$EMPTY_FRAME"
check "burn_frame_advance on an empty file restarts at 1" \
  "$(burn_frame_advance "$EMPTY_FRAME")" "1"

NONNUM_FRAME="$TMPROOT/nonnum-frame"
printf 'abc' > "$NONNUM_FRAME"
check "burn_frame_advance on non-numeric content restarts at 1" \
  "$(burn_frame_advance "$NONNUM_FRAME")" "1"

DECIMAL_FRAME="$TMPROOT/decimal-frame"
printf '3.5' > "$DECIMAL_FRAME"
check "burn_frame_advance on decimal (non-integer) content restarts at 1" \
  "$(burn_frame_advance "$DECIMAL_FRAME")" "1"

# Unwritable path: a directory occupying the target path can never be opened
# for write as a regular file (true even for root), so this reliably forces
# the unwritable branch without relying on permission bits.
UNWRITABLE_TARGET="$TMPROOT/unwritable-target"; mkdir -p "$UNWRITABLE_TARGET"
out=$(burn_frame_advance "$UNWRITABLE_TARGET"); rc=$?
check "burn_frame_advance echoes 1 when the path is unwritable" "$out" "1"
check "burn_frame_advance returns 0 (not an error) when the path is unwritable" "$rc" "0"

# Integer overflow: contract says the counter "may wrap or reset freely", so
# only the non-crashing, still-a-bare-integer shape is pinned, not a value.
OVERFLOW_FRAME="$TMPROOT/overflow-frame"
printf '99999999999999999999999999999999' > "$OVERFLOW_FRAME"
out=$(burn_frame_advance "$OVERFLOW_FRAME"); rc=$?
check "burn_frame_advance at integer overflow does not error (exit 0)" "$rc" "0"
check "burn_frame_advance at integer overflow still echoes a bare integer" \
  "$(printf '%s' "$out" | grep -qE '^[0-9]+$' && echo yes || echo no)" "yes"

# ============================================================================
# burn_model_style MODEL -> BURN_MASCOT, BURN_HUES (case-insensitive
# substring match; first match in documented order wins; echoes nothing).
# ============================================================================

reset_style() { unset BURN_MASCOT; BURN_HUES=(); }

reset_style
out=$(burn_model_style "opus")
check "burn_model_style echoes nothing" "$out" ""

reset_style; burn_model_style "opus"
check "opus mascot" "$BURN_MASCOT" "🎭"
check "opus hues" "${BURN_HUES[*]}" "196 202 208 214 220 226 214 208"

reset_style; burn_model_style "sonnet"
check "sonnet mascot" "$BURN_MASCOT" "🪶"
check "sonnet hues" "${BURN_HUES[*]}" "21 27 33 39 45 51 45 39"

reset_style; burn_model_style "fable"
check "fable mascot" "$BURN_MASCOT" "🦄"
check "fable hues" "${BURN_HUES[*]}" "93 99 135 141 177 201 171 135"

reset_style; burn_model_style "haiku"
check "haiku mascot" "$BURN_MASCOT" "🌸"
check "haiku hues" "${BURN_HUES[*]}" "22 28 34 40 46 82 118 46"

reset_style; burn_model_style "gpt-4"
check "unrecognised model falls back to the rainbow mascot" "$BURN_MASCOT" "🤖"
check "unrecognised model falls back to the rainbow hues" "${BURN_HUES[*]}" "196 208 226 46 51 33 201 129"

reset_style; burn_model_style ""
check "empty model falls back to the rainbow mascot" "$BURN_MASCOT" "🤖"

# Case-insensitive substring matching.
reset_style; burn_model_style "Claude Opus 4.7"
check "case-insensitive substring match: 'Claude Opus 4.7' -> opus mascot" "$BURN_MASCOT" "🎭"

reset_style; burn_model_style "SONNET"
check "case-insensitive substring match: 'SONNET' -> sonnet mascot" "$BURN_MASCOT" "🪶"

reset_style; burn_model_style "the fable model"
check "case-insensitive substring match: 'the fable model' -> fable mascot" "$BURN_MASCOT" "🦄"

# Deterministic first-match-wins ordering when several patterns match.
reset_style; burn_model_style "Claude Opus Haiku"
check "multiple matches ('Claude Opus Haiku') resolve to the first documented pattern (opus)" \
  "$BURN_MASCOT" "🎭"

reset_style; burn_model_style "Sonnet Fable"
check "multiple matches ('Sonnet Fable') resolve to the first documented pattern (sonnet)" \
  "$BURN_MASCOT" "🪶"

# ============================================================================
# burn_rainbow TEXT FRAME -- per-character colour from BURN_HUES, offset by
# FRAME; ends with a reset; empty TEXT echoes nothing. No exact hue-per-char
# formula is documented, so these assert the documented BEHAVIOUR only.
# ============================================================================

reset_style; burn_model_style "opus"   # BURN_HUES is opus's palette below

check "burn_rainbow on empty TEXT echoes nothing (not a bare reset)" \
  "$(burn_rainbow "" 0)" ""

out_ascii=$(burn_rainbow "ABC" 0)
stripped=$(printf '%s' "$out_ascii" | sed -E "s/${ESC}\\[[0-9;]*m//g")
check "non-empty TEXT round-trips intact once ANSI is stripped" "$stripped" "ABC"
check "non-empty TEXT ends with a reset sequence" \
  "$(printf '%s' "$out_ascii" | tail -c 4)" "${ESC}[0m"

color_count=$(printf '%s' "$out_ascii" | grep -oE "${ESC}\\[38;5;[0-9]+m" | wc -l | tr -d ' ')
check "one colour escape per character ('ABC' -> 3)" "$color_count" "3"

used_colors=$(printf '%s' "$out_ascii" | grep -oE "${ESC}\\[38;5;[0-9]+m" | sed -E 's/.*;([0-9]+)m/\1/')
all_in_hues="yes"
for c in $used_colors; do
  case " ${BURN_HUES[*]} " in
    *" $c "*) ;;
    *) all_in_hues="no" ;;
  esac
done
check "every colour used is drawn from the current model's BURN_HUES palette" "$all_in_hues" "yes"

frame0=$(burn_rainbow "ABC" 0)
frame1=$(burn_rainbow "ABC" 1)
check "colours drift with FRAME (same text differs across frames)" \
  "$([ "$frame0" != "$frame1" ] && echo differs || echo same)" "differs"

emoji_text="A🎉B"
out_emoji=$(burn_rainbow "$emoji_text" 0)
stripped_emoji=$(printf '%s' "$out_emoji" | sed -E "s/${ESC}\\[[0-9;]*m//g")
check "multi-byte/emoji TEXT is never truncated or reordered" "$stripped_emoji" "$emoji_text"

# ============================================================================
# burn_effort_color EFFORT -- bare SGR sequence per tier; anything else
# (including empty) is the dim sequence. No trailing reset: this is a colour
# PREFIX for the caller to compose with text, not "coloured text" itself.
# ============================================================================

check "effort low -> grey 245" "$(burn_effort_color low)" "${ESC}[38;5;245m"
check "effort medium -> blue 39" "$(burn_effort_color medium)" "${ESC}[38;5;39m"
check "effort high -> amber 214" "$(burn_effort_color high)" "${ESC}[38;5;214m"
check "effort xhigh -> red 196" "$(burn_effort_color xhigh)" "${ESC}[38;5;196m"
check "effort max -> red 196" "$(burn_effort_color max)" "${ESC}[38;5;196m"
check "unrecognised effort -> dim" "$(burn_effort_color critical)" "${ESC}[2m"
check "empty effort -> dim" "$(burn_effort_color "")" "${ESC}[2m"
check "burn_effort_color emits only the bare colour prefix (no embedded reset)" \
  "$(burn_effort_color high | grep -c "${ESC}\\[0m")" "0"

# ============================================================================
# burn_plan_color PCT -- weekly/5-hour meter scale (high pct = hot = red).
# Thresholds are boundary-inclusive (>=); each boundary tested at, above and
# below.
# ============================================================================

check "plan >=70 -> red 196 (exact boundary 70)" "$(burn_plan_color 70)" "${ESC}[38;5;196m"
check "plan 69 -> orange 208 (just under 70)" "$(burn_plan_color 69)" "${ESC}[38;5;208m"
check "plan >=50 -> orange 208 (exact boundary 50)" "$(burn_plan_color 50)" "${ESC}[38;5;208m"
check "plan 49 -> yellow 214 (just under 50)" "$(burn_plan_color 49)" "${ESC}[38;5;214m"
check "plan >=30 -> yellow 214 (exact boundary 30)" "$(burn_plan_color 30)" "${ESC}[38;5;214m"
check "plan 29 -> green 40 (just under 30, else branch)" "$(burn_plan_color 29)" "${ESC}[38;5;40m"
check "burn_plan_color emits only the bare colour prefix (no embedded reset)" \
  "$(burn_plan_color 80 | grep -c "${ESC}\\[0m")" "0"

# ============================================================================
# burn_today_color PCT -- today's remaining share (high pct = healthy =
# green, matching the direction of the value itself). Negative -> red.
# ============================================================================

check "today >=50 -> green 40 (exact boundary 50)" "$(burn_today_color 50)" "${ESC}[38;5;40m"
check "today 49 -> yellow 214 (just under 50)" "$(burn_today_color 49)" "${ESC}[38;5;214m"
check "today >=25 -> yellow 214 (exact boundary 25)" "$(burn_today_color 25)" "${ESC}[38;5;214m"
check "today 24 -> orange 208 (just under 25)" "$(burn_today_color 24)" "${ESC}[38;5;208m"
check "today >=10 -> orange 208 (exact boundary 10)" "$(burn_today_color 10)" "${ESC}[38;5;208m"
check "today 9 -> red 196 (just under 10, else branch)" "$(burn_today_color 9)" "${ESC}[38;5;196m"
check "today 0 -> red 196" "$(burn_today_color 0)" "${ESC}[38;5;196m"
check "today negative -> red 196 (past tonight's checkpoint)" "$(burn_today_color -5)" "${ESC}[38;5;196m"
check "burn_today_color emits only the bare colour prefix (no embedded reset)" \
  "$(burn_today_color 60 | grep -c "${ESC}\\[0m")" "0"

# ============================================================================
# burn_pace_color PACE -- sustainable %/day. Scale runs the OPPOSITE way to
# the meters above: HIGH pace is healthy, so high -> green, low -> red.
# Accepts a decimal and compares on its INTEGER PART (truncation, not
# rounding).
# ============================================================================

check "pace >=12 -> green 40 (exact boundary 12)" "$(burn_pace_color 12)" "${ESC}[38;5;40m"
check "pace 11 -> yellow 214 (just under 12)" "$(burn_pace_color 11)" "${ESC}[38;5;214m"
check "pace >=8 -> yellow 214 (exact boundary 8)" "$(burn_pace_color 8)" "${ESC}[38;5;214m"
check "pace 7 -> orange 208 (just under 8)" "$(burn_pace_color 7)" "${ESC}[38;5;208m"
check "pace >=5 -> orange 208 (exact boundary 5)" "$(burn_pace_color 5)" "${ESC}[38;5;208m"
check "pace 4 -> red 196 (just under 5, else branch)" "$(burn_pace_color 4)" "${ESC}[38;5;196m"
check "pace 0 -> red 196" "$(burn_pace_color 0)" "${ESC}[38;5;196m"
check "pace decimal 12.9 truncates to 12 -> green 40" "$(burn_pace_color 12.9)" "${ESC}[38;5;40m"
check "pace decimal 11.9 truncates to 11 -> yellow 214 (NOT rounded up to 12/green)" \
  "$(burn_pace_color 11.9)" "${ESC}[38;5;214m"
check "pace decimal 7.9 truncates to 7 -> orange 208 (NOT rounded up to 8/yellow)" \
  "$(burn_pace_color 7.9)" "${ESC}[38;5;208m"
check "burn_pace_color emits only the bare colour prefix (no embedded reset)" \
  "$(burn_pace_color 3 | grep -c "${ESC}\\[0m")" "0"

# ============================================================================
# burn_ctx_state USED_TOKENS BUDGET IDLE_SECONDS -> "LEVEL COLOR" (COLOR is
# the bare 256-colour number, matching context.sh's existing ctx_color
# convention that this function extracts -- not a full SGR sequence).
# Tri-state on occupancy (floor(100*USED/BUDGET)) AND idle together.
# ============================================================================

check "ctx: over budget at zero idle -> cold 196" \
  "$(burn_ctx_state 350000 300000 0)" "cold 196"
check "ctx: exact USED==BUDGET boundary -> cold 196 (idle=0)" \
  "$(burn_ctx_state 300000 300000 0)" "cold 196"
check "ctx: exact USED==BUDGET boundary -> cold 196 regardless of idle (idle=99999)" \
  "$(burn_ctx_state 300000 300000 99999)" "cold 196"
check "ctx: occupancy exactly 60%, idle exactly 1800s -> warn 208" \
  "$(burn_ctx_state 60000 100000 1800)" "warn 208"
check "ctx: occupancy exactly 60%, idle exactly 2700s -> cold 196" \
  "$(burn_ctx_state 60000 100000 2700)" "cold 196"
check "ctx: occupancy exactly 60%, idle 1799s (just under warn floor) -> ok 40" \
  "$(burn_ctx_state 60000 100000 1799)" "ok 40"
check "ctx: occupancy 45% (<60%) at very high idle -> ok 40" \
  "$(burn_ctx_state 45000 100000 999999)" "ok 40"
check "ctx: occupancy 59% (<60% floor) at idle 5000s stays ok (floor gates staleness)" \
  "$(burn_ctx_state 59000 100000 5000)" "ok 40"
check "ctx: BUDGET==0 -> ok 40, no division by zero" \
  "$(burn_ctx_state 100 0 0)" "ok 40"
check "ctx: BUDGET negative -> ok 40, no division by zero" \
  "$(burn_ctx_state 100 -10 0)" "ok 40"

# ============================================================================
# burn_reset_str RESET_EPOCH NOW -- "4h54m" at an hour+, "12m" below; past or
# equal is "0m" (never negative); exactly 60 minutes is "1h0m", not "60m";
# empty/non-numeric RESET_EPOCH echoes nothing and returns 1.
# ============================================================================

check "reset_str 4h54m (NOW=0)" "$(burn_reset_str 17640 0)" "4h54m"
check "reset_str exactly 60 minutes -> 1h0m, not 60m" "$(burn_reset_str 3600 0)" "1h0m"
check "reset_str 59m59s truncates to 59m (just under an hour)" "$(burn_reset_str 3599 0)" "59m"
check "reset_str 12m (under an hour)" "$(burn_reset_str 720 0)" "12m"
check "reset_str past RESET_EPOCH -> 0m, never negative" "$(burn_reset_str 1000 5000)" "0m"
check "reset_str RESET_EPOCH == NOW exactly -> 0m" "$(burn_reset_str 5000 5000)" "0m"
check "reset_str one second in the past -> 0m" "$(burn_reset_str 999 1000)" "0m"

out=$(burn_reset_str "" 0); rc=$?
check "reset_str empty RESET_EPOCH echoes nothing" "$out" ""
check "reset_str empty RESET_EPOCH returns 1" "$rc" "1"

out=$(burn_reset_str "abc" 0); rc=$?
check "reset_str non-numeric RESET_EPOCH echoes nothing" "$out" ""
check "reset_str non-numeric RESET_EPOCH returns 1" "$rc" "1"

# ============================================================================
# burn_pet STRESS FRAME -- face + dimmed effect character, indexed by FRAME
# modulo 8 within the tier STRESS falls in (>=70 panic, >=50 nervous,
# >=30 alert, else happy). Both face and effect vary within every tier.
# Exact literal frame tables, extracted byte-for-byte from the contract:
# ============================================================================

PANIC_FACES=(😾 🙀 😾 😿 😾 🙀 😾 🙀);      PANIC_EFFECTS=(🔥 💢 💥 🔥 💢 💥 🔥 💢)
NERVOUS_FACES=(🙀 😿 🙀 😿 🙀 😾 🙀 😿);     NERVOUS_EFFECTS=(💦 ° 💦 ∘ 💦 ° 💦 ∘)
ALERT_FACES=(😼 🐱 😼 😽 😼 🐱 😼 🐱);       ALERT_EFFECTS=(· ‥ … ‥ · ‥ … ‥)
HAPPY_FACES=(😺 😸 😺 😹 😺 😸 😻 😸);       HAPPY_EFFECTS=(♪ ♫ ♬ ♪ ♫ ♬ ♫ ♪)

# check_pet(label, stress, frame, face, effect): the face is plain, the
# effect is dimmed (\033[2m) and the whole thing is reset-terminated. The
# contract does not pin whether a separator sits between face and effect, so
# an optional single space is allowed -- everything else about the structure
# (order, dim wrapping, terminal reset, nothing extra) is pinned exactly via
# the ^...$ anchors.
check_pet() { # label stress frame face effect
  local lbl="$1" stress="$2" frame="$3" face="$4" effect="$5" out pat
  out=$(burn_pet "$stress" "$frame")
  pat="^${face}[[:space:]]?${ESC}\\[2m${effect}${ESC}\\[0m\$"
  if printf '%s' "$out" | grep -qE "$pat"; then
    echo "PASS  $lbl"
  else
    echo "FAIL  $lbl -> got '$out', expected face='$face' dimmed effect='$effect' (optional space, reset-terminated)"; FAILED=1
  fi
}

check_pet "pet: STRESS=70 (panic boundary), FRAME=0" 70 0 "${PANIC_FACES[0]}" "${PANIC_EFFECTS[0]}"
check_pet "pet: STRESS=69 (just under panic, nervous), FRAME=0" 69 0 "${NERVOUS_FACES[0]}" "${NERVOUS_EFFECTS[0]}"
check_pet "pet: STRESS=50 (nervous boundary), FRAME=0" 50 0 "${NERVOUS_FACES[0]}" "${NERVOUS_EFFECTS[0]}"
check_pet "pet: STRESS=49 (just under nervous, alert), FRAME=0" 49 0 "${ALERT_FACES[0]}" "${ALERT_EFFECTS[0]}"
check_pet "pet: STRESS=30 (alert boundary), FRAME=0" 30 0 "${ALERT_FACES[0]}" "${ALERT_EFFECTS[0]}"
check_pet "pet: STRESS=29 (just under alert, happy/else)" 29 0 "${HAPPY_FACES[0]}" "${HAPPY_EFFECTS[0]}"

check_pet "pet: panic tier, FRAME=3 (mid-cycle index)" 100 3 "${PANIC_FACES[3]}" "${PANIC_EFFECTS[3]}"
check_pet "pet: panic tier, FRAME=7 (last index)" 100 7 "${PANIC_FACES[7]}" "${PANIC_EFFECTS[7]}"
check_pet "pet: panic tier, FRAME=8 wraps modulo 8 back to index 0" 100 8 "${PANIC_FACES[0]}" "${PANIC_EFFECTS[0]}"

check_pet "pet: empty STRESS defaults to the happy tier" "" 2 "${HAPPY_FACES[2]}" "${HAPPY_EFFECTS[2]}"
check_pet "pet: non-numeric STRESS defaults to the happy tier" "abc" 5 "${HAPPY_FACES[5]}" "${HAPPY_EFFECTS[5]}"

out_f0=$(burn_pet 100 0)
out_f1=$(burn_pet 100 1)
check "pet: consecutive frames visibly differ (panic FRAME=0 vs FRAME=1)" \
  "$([ "$out_f0" != "$out_f1" ] && echo differs || echo same)" "differs"

# ============================================================================
# Invariant: forks NO external process -- every function (including
# burn_frame_advance's read/write) is pure bash builtins. Re-run a
# representative call per function with PATH cleared: if a real
# implementation shelled out to date/expr/sed/bc/cat/etc., the call would
# fail (or silently misbehave) with only builtins on offer.
# ============================================================================

REAL_BASH=$(command -v bash)

no_fork() { # bash_code
  PATH= "$REAL_BASH" -c ". '$THEME'; $1" 2>/dev/null
}

NF_FRAME="$TMPROOT/no-fork-frame"
nf_frame_code="burn_frame_advance '$NF_FRAME'"
nf_out=$(no_fork "$nf_frame_code")
check "no-fork: burn_frame_advance still advances (absent file -> 1)" "$nf_out" "1"

nf_out=$(no_fork 'burn_model_style opus; printf "%s" "$BURN_MASCOT"')
check "no-fork: burn_model_style still sets BURN_MASCOT for opus" "$nf_out" "🎭"

nf_out=$(no_fork 'burn_model_style opus; burn_rainbow "Hi" 0' | tail -c 4)
check "no-fork: burn_rainbow still ends its output with a reset" "$nf_out" "${ESC}[0m"

nf_out=$(no_fork 'burn_effort_color high')
check "no-fork: burn_effort_color still maps high -> amber 214" "$nf_out" "${ESC}[38;5;214m"

nf_out=$(no_fork 'burn_plan_color 80')
check "no-fork: burn_plan_color still maps 80 -> red 196" "$nf_out" "${ESC}[38;5;196m"

nf_out=$(no_fork 'burn_today_color 5')
check "no-fork: burn_today_color still maps 5 -> red 196" "$nf_out" "${ESC}[38;5;196m"

nf_out=$(no_fork 'burn_pace_color 3')
check "no-fork: burn_pace_color still maps 3 -> red 196" "$nf_out" "${ESC}[38;5;196m"

nf_out=$(no_fork 'burn_ctx_state 400000 300000 0')
check "no-fork: burn_ctx_state still maps over-budget -> cold 196" "$nf_out" "cold 196"

nf_out=$(no_fork 'burn_reset_str 3600 0')
check "no-fork: burn_reset_str still formats 3600s as 1h0m" "$nf_out" "1h0m"

nf_out=$(no_fork 'burn_pet 10 0')
check "no-fork: burn_pet (happy tier, FRAME=0) still matches the documented frame" \
  "$(printf '%s' "$nf_out" | grep -qE "^${HAPPY_FACES[0]}[[:space:]]?${ESC}\\[2m${HAPPY_EFFECTS[0]}${ESC}\\[0m\$" && echo match || echo no-match)" \
  "match"

# ============================================================================
# Invariant: no function reads the environment or any file except
# FRAME_FILE, and thresholds are locked constants (not env-configurable).
# Re-run representative calls under a fully wiped environment (env -i: no
# $HOME, no $PATH, nothing inherited) and, separately, with decoy
# threshold-shaped env vars set, confirming neither perturbs the mapping.
# ============================================================================

env_isolated() { # bash_code
  env -i "$REAL_BASH" -c ". '$THEME'; $1" 2>/dev/null
}

ei_out=$(env_isolated 'burn_plan_color 80')
check "env-isolated: burn_plan_color still maps 80 -> red 196" "$ei_out" "${ESC}[38;5;196m"

ei_out=$(env_isolated 'burn_effort_color high')
check "env-isolated: burn_effort_color still maps high -> amber 214" "$ei_out" "${ESC}[38;5;214m"

ei_out=$(env_isolated 'burn_pace_color 3')
check "env-isolated: burn_pace_color still maps 3 -> red 196 (opposite scale intact)" "$ei_out" "${ESC}[38;5;196m"

ei_out=$(env_isolated 'burn_today_color 5')
check "env-isolated: burn_today_color still maps 5 -> red 196" "$ei_out" "${ESC}[38;5;196m"

ei_out=$(env_isolated 'burn_ctx_state 400000 300000 0')
check "env-isolated: burn_ctx_state still maps over-budget -> cold 196" "$ei_out" "cold 196"

ei_out=$(env_isolated 'burn_reset_str 3600 0')
check "env-isolated: burn_reset_str still formats 3600s as 1h0m" "$ei_out" "1h0m"

ei_out=$(env_isolated 'burn_model_style opus; printf "%s" "$BURN_MASCOT"')
check "env-isolated: burn_model_style still sets the opus mascot" "$ei_out" "🎭"

ei_frame_code="burn_frame_advance '$TMPROOT/env-isolated-frame'"
ei_out=$(env_isolated "$ei_frame_code")
check "env-isolated: burn_frame_advance still starts a fresh file at 1" "$ei_out" "1"

# Decoy threshold-shaped env vars must not change a locked-constant mapping.
check "thresholds are locked constants: decoy env vars do not change burn_plan_color" \
  "$(BURN_PLAN_RED=999 BURN_PLAN_COLOR_THRESHOLD=1 CLAUDE_BURN_RED=0 burn_plan_color 80)" \
  "${ESC}[38;5;196m"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
