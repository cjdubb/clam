#!/bin/bash
# Table-driven functional tests for burn-theme.sh: the presentation layer for
# the burnrate line -- the per-model hue family, the frame-drifting rainbow,
# the reasoning-effort colour, the four meter colour scales (plan, today,
# pace, ctx-state), and the reset countdown string. Every function is a pure
# mapping from value to appearance (Contract: B03 burn-theme, plan
# 001-statusline-burnrate-uplift, amended by B08 burn-theme-deemoji, plan
# 002-statusline-emoji-removal), so these tests are table-driven and pin the
# contract's exact literal colour codes and hue arrays -- not a paraphrase.
#
# What B08 changed, and what it deliberately did not:
#
#   GONE.  burn_pet, with its four mood tiers, its 8-frame face arrays and
#          its effect-character arrays. burn_model_style's BURN_MASCOT.
#          Nothing replaces either. The tests for them are not relaxed, they
#          are inverted: absence is asserted as sharply as the old presence
#          was, because "the emoji is removed, not relocated" is the contract.
#
#   HELD.  burn_frame_advance and burn_rainbow, unchanged and fully tested.
#          These matter more than the deletions. The frame counter drove the
#          pet AND drives the model name's rainbow drift, so an implementer
#          who deletes it alongside burn_pet silently freezes the colour and
#          breaks nothing loudly. The burn_frame_advance and burn_rainbow
#          sections below are the guard against exactly that; they pass today
#          and must still pass afterwards.
#
#   NEW.   One file-wide invariant, checked three independent ways (source
#          text, parsed function bodies, runtime output): no function in this
#          file emits a non-ASCII character. That is what keeps a mascot or a
#          mood glyph from creeping back in, and it holds regardless of which
#          function anyone tries to hide one in.
#
# Two behaviours in the contract (burn_rainbow's per-frame hue offset, and
# the exact drift formula) have no byte-exact formula written down, so those
# sections assert the documented BEHAVIOUR (drift, ordering, reset-
# termination, text preservation) via structural checks rather than guessing
# an exact output string.
#
# Run: bash plugins/statusline/lib/burn-theme.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/burn-theme.sh"
. "$THEME"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

ESC=$(printf '\033')
FAILED=0

# "Non-ASCII" means a byte at or above 0x80 -- which is exactly what every
# byte of a multi-byte UTF-8 glyph is, and what nothing in a pure-ASCII file
# ever is. Deliberately NOT "outside printable ASCII": ESC (0x1b) is an ASCII
# character and it opens every SGR sequence this file emits, so a
# printable-only formulation would flag every colour escape and make the
# whole invariant unfalsifiable. Built with printf so the pattern stays
# readable, and always used under LC_ALL=C so grep compares bytes rather than
# decoding them in the ambient locale.
NONASCII_RE=$(printf '[\200-\377]')

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# check_clean(label, offenders): passes when a non-ASCII scan found nothing,
# and prints the offending lines (not just a count) when it did.
check_clean() { # label offenders
  if [[ -z "$2" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> non-ASCII found:"; printf '%s\n' "$2" | sed 's/^/        /'; FAILED=1
  fi
}

REAL_BASH=$(command -v bash)

# Source the theme into a pristine shell (env -i: nothing inherited, no
# exported functions, no test-harness helpers) and run BASH_CODE there. Used
# wherever an assertion must see the theme's functions and ONLY the theme's
# functions.
pristine() { # bash_code
  local code="$1"
  env -i "$REAL_BASH" -c ". \"\$1\"
$code" _ "$THEME" 2>/dev/null
}

# ============================================================================
# B08: the SHAPE of the file after de-emojification.
#
# The function inventory is the single sharpest statement of B08: burn_pet is
# absent, every other function survives, and nothing new appeared. Asserted
# against bash's own parse of the file in a pristine shell, so it cannot be
# fooled by a comment, a stale copy, or the test harness's own helpers.
# ============================================================================

DOCUMENTED_FUNCTIONS="burn_ctx_state burn_effort_color burn_frame_advance burn_model_style burn_pace_color burn_plan_color burn_rainbow burn_reset_str burn_today_color"

# `declare -F` prints "declare -f NAME" per line; read the third field with
# builtins only so this works with PATH stripped as well.
actual_functions=$(pristine 'while read -r _ _ fn; do echo "$fn"; done < <(declare -F)' | LC_ALL=C sort | tr '\n' ' ')
actual_functions="${actual_functions% }"
check "burn-theme.sh defines exactly the documented functions, and burn_pet is not among them" \
  "$actual_functions" "$DOCUMENTED_FUNCTIONS"

# burn_pet is gone outright: the contract's own wording is that
# `declare -f burn_pet` must find nothing. Pinned on both output and status,
# since a stub returning empty output would still be a defined function.
pet_decl=$(pristine 'declare -f burn_pet')
check "declare -f burn_pet finds nothing (no body)" "$pet_decl" ""
check "declare -f burn_pet reports not-a-function (exit 1)" \
  "$(pristine 'declare -f burn_pet >/dev/null 2>&1; echo $?')" "1"
check "declare -F burn_pet reports not-a-function (exit 1)" \
  "$(pristine 'declare -F burn_pet >/dev/null 2>&1; echo $?')" "1"
check "type -t burn_pet resolves to nothing after sourcing" \
  "$(pristine 'type -t burn_pet 2>/dev/null; echo "|end"')" "|end"

# The pet's face and effect arrays were function locals. Deleting the
# function must delete them with it -- hoisting them to file scope (or to any
# other function) would keep the glyphs in the file while still passing the
# declare -f check above.
check "sourcing burn-theme.sh defines no 'faces' or 'effects' array at file scope" \
  "$(pristine 'echo "faces=${faces[*]-unset} effects=${effects[*]-unset}"')" \
  "faces=unset effects=unset"

# Sourcing sets NO global at all: BURN_HUES appears only once
# burn_model_style is called, and BURN_MASCOT never appears again.
check "sourcing burn-theme.sh sets no BURN_* variable (BURN_HUES is set by the call, not the source)" \
  "$(pristine 'for v in ${!BURN@}; do echo "LEAK:$v"; done; echo "(none)"')" \
  "(none)"

# ============================================================================
# B08 file-wide invariant: NO function in this file emits a non-ASCII
# character.
#
# Checked three independent ways, because each misses something the others
# catch:
#   1. source text  -- catches a glyph in a branch no test happens to call,
#                      and a glyph in data (an array) rather than in output.
#   2. parsed bodies -- bash strips comments when it parses a function, so
#                      this is exactly "the code", with the prose docblock
#                      (which legitimately contains em-dashes and (c)) out of
#                      scope by construction rather than by pattern-matching.
#   3. runtime output -- the literal reading of the invariant, over every
#                      documented branch of every function.
# ============================================================================

# 1. Source text, comment lines excluded. The header docblock is English
#    prose and contains em-dashes and a copyright sign; those are exempt. Any
#    line that is not wholly a comment must be pure ASCII -- including a
#    trailing comment on a code line, which is deliberate: prose belongs in
#    the docblock, and the exemption is not a place to park a glyph.
static_offenders=$(LC_ALL=C grep -vn '^[[:space:]]*#' "$THEME" | LC_ALL=C grep "$NONASCII_RE")
check_clean "no non-ASCII byte on any non-comment line of burn-theme.sh (source text)" \
  "$static_offenders"

# 2. Every function body, as bash itself parsed it.
parsed_bodies=$(pristine 'while read -r _ _ fn; do declare -f "$fn"; done < <(declare -F)')
parsed_offenders=$(printf '%s\n' "$parsed_bodies" | LC_ALL=C grep -n "$NONASCII_RE")
check_clean "no non-ASCII character in any parsed function body (bash's own parse, comments already stripped)" \
  "$parsed_offenders"

# Controls for check 2: the scan saw real content covering every function, the
# pattern really does fire on a glyph, and it really does NOT fire on a colour
# escape. Without all three, "no offenders" could mean "nothing was scanned"
# or "the pattern matches nothing" -- and a pattern that flagged ESC would
# make the invariant unfalsifiable in the other direction.
check "the parsed-body scan covers exactly the documented functions (scan is not vacuous)" \
  "$(printf '%s\n' "$parsed_bodies" | LC_ALL=C grep -c '^burn_[a-z_]* ()')" "9"
check "the non-ASCII pattern fires on a known non-ASCII byte" \
  "$(printf 'ok\nbad \xe2\x80\x94 here\n' | LC_ALL=C grep -c "$NONASCII_RE")" "1"
check "the non-ASCII pattern does NOT fire on an SGR escape (ESC is ASCII)" \
  "$(printf '%s[38;5;196mX%s[0m\n' "$ESC" "$ESC" | LC_ALL=C grep -c "$NONASCII_RE")" "0"

# 3. Runtime output over every documented branch. emit_every_branch calls
#    each function across its whole documented input space with ASCII-only
#    arguments, so anything non-ASCII on stdout came from this file, not from
#    the caller's text. (burn_rainbow's contract requires it to pass a
#    caller's multi-byte text through untouched -- that is tested separately
#    below, and is why this sweep feeds it ASCII.)
EMIT_FRAME_FRESH="$TMPROOT/emit-frame-fresh"
EMIT_FRAME_SEEDED="$TMPROOT/emit-frame-seeded"; printf '41' > "$EMIT_FRAME_SEEDED"
EMIT_FRAME_BAD="$TMPROOT/emit-frame-bad-dir"; mkdir -p "$EMIT_FRAME_BAD"

emit_every_branch() {
  burn_frame_advance "$EMIT_FRAME_FRESH"
  burn_frame_advance "$EMIT_FRAME_SEEDED"
  burn_frame_advance "$EMIT_FRAME_BAD"

  local m f
  for m in opus sonnet fable haiku gpt-4 "" "Claude Opus Haiku"; do
    burn_model_style "$m"
    for f in 0 1 5 7 8; do
      burn_rainbow "Claude Model 4.7" "$f"
    done
  done

  for f in low medium high xhigh max critical ""; do burn_effort_color "$f"; done
  for f in 100 70 69 50 49 30 29 0 -5 abc ""; do burn_plan_color "$f"; done
  for f in 100 50 49 25 24 10 9 0 -5 abc ""; do burn_today_color "$f"; done
  for f in 20 12 11 8 7 5 4 0 12.9 7.9 -3 abc ""; do burn_pace_color "$f"; done
  burn_ctx_state 350000 300000 0
  burn_ctx_state 300000 300000 99999
  burn_ctx_state 60000 100000 2700
  burn_ctx_state 60000 100000 1800
  burn_ctx_state 60000 100000 0
  burn_ctx_state 45000 100000 999999
  burn_ctx_state 100 0 0
  burn_ctx_state 100 -10 0
  burn_ctx_state abc abc abc
  burn_reset_str 17640 0
  burn_reset_str 3600 0
  burn_reset_str 720 0
  burn_reset_str 1000 5000
  burn_reset_str "" 0
  burn_reset_str abc 0
}

emitted=$(emit_every_branch 2>/dev/null)
emitted_offenders=$(printf '%s\n' "$emitted" | LC_ALL=C grep -n "$NONASCII_RE")
check_clean "no function emits a non-ASCII character on stdout, across every documented branch" \
  "$emitted_offenders"

# Positive control for check 3: the sweep produced real output, so a clean
# scan means "no glyphs", not "nothing ran".
check "the runtime sweep produced output (scan is not vacuous)" \
  "$([ -n "$emitted" ] && echo produced || echo empty)" "produced"

# The rainbow is where a mascot would most plausibly be re-attached, so it
# gets its own narrower assertion: coloured ASCII text in, pure ASCII out.
reset_style() { unset BURN_MASCOT; unset BURN_HUES; }
reset_style; burn_model_style "opus"
rainbow_offenders=$(burn_rainbow "Claude Opus 4.7" 3 | LC_ALL=C grep -n "$NONASCII_RE")
check_clean "burn_rainbow over ASCII text emits pure ASCII (no mascot re-attached)" \
  "$rainbow_offenders"

# ============================================================================
# burn_frame_advance FRAME_FILE -- HELD INVARIANT by B08. Advances and
# persists; absent/empty/non-numeric content restarts at 1; unwritable path
# echoes 1, returns 0. The pet is gone but the rainbow still consumes this
# counter, so every one of these must still pass.
# ============================================================================

check "burn_frame_advance survives B08 (still defined after sourcing)" \
  "$(pristine 'type -t burn_frame_advance')" "function"

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

# The counter and the rainbow are wired together: the value burn_frame_advance
# returns must actually move burn_rainbow's colours. This is the coupling that
# makes the counter load-bearing after the pet's removal, so it is asserted
# end-to-end rather than left implied by the two functions' separate sections.
DRIFT_FRAME="$TMPROOT/drift-frame"
reset_style; burn_model_style "opus"
d1=$(burn_rainbow "Opus" "$(burn_frame_advance "$DRIFT_FRAME")")
d2=$(burn_rainbow "Opus" "$(burn_frame_advance "$DRIFT_FRAME")")
check "the frame counter still drives the rainbow: consecutive renders differ" \
  "$([ "$d1" != "$d2" ] && echo differs || echo frozen)" "differs"

# ============================================================================
# burn_model_style MODEL -> sets BURN_HUES ONLY (case-insensitive substring
# match; first match in documented order wins; echoes nothing).
#
# B08: BURN_MASCOT is NOT set. Asserted with a sentinel rather than by
# comparing against "", because BURN_MASCOT="" would be a relocation of the
# decision into the caller, and the contract says removed, not relocated:
# no caller may rely on the variable at all.
# ============================================================================

MASCOT_SENTINEL="__untouched__"

reset_style
out=$(burn_model_style "opus")
check "burn_model_style echoes nothing" "$out" ""

reset_style; burn_model_style "opus"
check "opus hues" "${BURN_HUES[*]}" "196 202 208 214 220 226 214 208"

reset_style; burn_model_style "sonnet"
check "sonnet hues" "${BURN_HUES[*]}" "21 27 33 39 45 51 45 39"

reset_style; burn_model_style "fable"
check "fable hues" "${BURN_HUES[*]}" "93 99 135 141 177 201 171 135"

reset_style; burn_model_style "haiku"
check "haiku hues" "${BURN_HUES[*]}" "22 28 34 40 46 82 118 46"

reset_style; burn_model_style "gpt-4"
check "unrecognised model falls back to the rainbow hues" "${BURN_HUES[*]}" "196 208 226 46 51 33 201 129"

reset_style; burn_model_style ""
check "empty model falls back to the rainbow hues" "${BURN_HUES[*]}" "196 208 226 46 51 33 201 129"

# Every hue family still has exactly 8 entries -- burn_rainbow indexes modulo
# 8 unconditionally, so a short palette would emit an empty colour code.
for m in opus sonnet fable haiku gpt-4; do
  reset_style; burn_model_style "$m"
  check "'$m' hue family has 8 entries (burn_rainbow indexes modulo 8)" "${#BURN_HUES[@]}" "8"
done

# B08: BURN_MASCOT is never written. With the variable already holding a
# sentinel, any assignment at all -- glyph, text label or empty string --
# fails this.
for m in opus sonnet fable haiku gpt-4 "" "Claude Opus Haiku"; do
  BURN_MASCOT="$MASCOT_SENTINEL"; unset BURN_HUES
  burn_model_style "$m"
  check "burn_model_style '$m' leaves a pre-existing BURN_MASCOT untouched (does not set it)" \
    "$BURN_MASCOT" "$MASCOT_SENTINEL"
done

# ...and with BURN_MASCOT unset going in, it stays unset going out -- the
# `+set` form distinguishes "unset" from "set to the empty string".
for m in opus sonnet fable haiku gpt-4; do
  unset BURN_MASCOT BURN_HUES
  burn_model_style "$m"
  check "burn_model_style '$m' leaves BURN_MASCOT unset (not set-to-empty)" \
    "${BURN_MASCOT+set}" ""
done

# The same, from a pristine shell, so the harness cannot be the thing keeping
# it unset.
check "pristine shell: burn_model_style sets BURN_HUES and not BURN_MASCOT" \
  "$(pristine 'burn_model_style opus; echo "hues=${BURN_HUES[*]-unset} mascot=${BURN_MASCOT-unset}"')" \
  "hues=196 202 208 214 220 226 214 208 mascot=unset"

# BURN_HUES is the ONE global the contract allows this function to set, so
# nothing else may appear alongside it.
check "burn_model_style sets exactly one BURN_* global, BURN_HUES" \
  "$(pristine 'burn_model_style sonnet; for v in ${!BURN@}; do echo "$v"; done')" \
  "BURN_HUES"

# Case-insensitive substring matching -- now observed through BURN_HUES,
# since the mascot that used to witness it is gone.
reset_style; burn_model_style "Claude Opus 4.7"
check "case-insensitive substring match: 'Claude Opus 4.7' -> opus hues" \
  "${BURN_HUES[*]}" "196 202 208 214 220 226 214 208"

reset_style; burn_model_style "SONNET"
check "case-insensitive substring match: 'SONNET' -> sonnet hues" \
  "${BURN_HUES[*]}" "21 27 33 39 45 51 45 39"

reset_style; burn_model_style "the fable model"
check "case-insensitive substring match: 'the fable model' -> fable hues" \
  "${BURN_HUES[*]}" "93 99 135 141 177 201 171 135"

reset_style; burn_model_style "Claude Haiku 4.5"
check "case-insensitive substring match: 'Claude Haiku 4.5' -> haiku hues" \
  "${BURN_HUES[*]}" "22 28 34 40 46 82 118 46"

# Deterministic first-match-wins ordering when several patterns match.
reset_style; burn_model_style "Claude Opus Haiku"
check "multiple matches ('Claude Opus Haiku') resolve to the first documented pattern (opus hues)" \
  "${BURN_HUES[*]}" "196 202 208 214 220 226 214 208"

reset_style; burn_model_style "Sonnet Fable"
check "multiple matches ('Sonnet Fable') resolve to the first documented pattern (sonnet hues)" \
  "${BURN_HUES[*]}" "21 27 33 39 45 51 45 39"

# nocasematch is borrowed, not appropriated: the shell option must be left as
# it was found, in both directions.
check "burn_model_style restores nocasematch=off when it was off" \
  "$(pristine 'shopt -u nocasematch; burn_model_style opus; shopt -q nocasematch && echo on || echo off')" \
  "off"
check "burn_model_style leaves nocasematch=on when the caller had it on" \
  "$(pristine 'shopt -s nocasematch; burn_model_style opus; shopt -q nocasematch && echo on || echo off')" \
  "on"

# ============================================================================
# burn_rainbow TEXT FRAME -- HELD INVARIANT by B08. Per-character colour from
# BURN_HUES, offset by FRAME; ends with a reset; empty TEXT echoes nothing.
# No exact hue-per-char formula is documented, so these assert the documented
# BEHAVIOUR only.
# ============================================================================

check "burn_rainbow survives B08 (still defined after sourcing)" \
  "$(pristine 'type -t burn_rainbow')" "function"

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

# The drift is a rotation of one fixed palette, not a repaint: frame 8 lands
# back on frame 0 because the palette has 8 entries.
check "the drift is a rotation: FRAME=8 returns to FRAME=0's colours" \
  "$(burn_rainbow "ABC" 8)" "$frame0"

# Palette follows the model: the same text under a different model's hues
# must actually change colour, which is the whole reason BURN_HUES survived
# B08 while BURN_MASCOT did not.
reset_style; burn_model_style "sonnet"
sonnet_render=$(burn_rainbow "ABC" 0)
reset_style; burn_model_style "opus"
check "the same text renders differently under a different model's palette" \
  "$([ "$sonnet_render" != "$frame0" ] && echo differs || echo same)" "differs"

emoji_text="A🎉B"
out_emoji=$(burn_rainbow "$emoji_text" 0)
stripped_emoji=$(printf '%s' "$out_emoji" | sed -E "s/${ESC}\\[[0-9;]*m//g")
check "multi-byte/emoji TEXT is never truncated or reordered" "$stripped_emoji" "$emoji_text"

# The B08 invariant is about what this FILE emits, not about what a caller
# hands it: text passed in comes back out byte-for-byte, glyphs included.
accented_text=$(printf 'Ren\xc3\xa9')
out_accented=$(burn_rainbow "$accented_text" 2)
stripped_accented=$(printf '%s' "$out_accented" | sed -E "s/${ESC}\\[[0-9;]*m//g")
check "multi-byte non-emoji TEXT is preserved byte-for-byte" "$stripped_accented" "$accented_text"

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
# Invariant: no function writes to stderr in normal operation -- output lands
# directly in the user's statusline, so a stray diagnostic would corrupt the
# render rather than surface anywhere useful. Swept over the same
# every-branch matrix used for the ASCII check above, including the
# unwritable frame file, whose failure the contract requires to be silent.
# ============================================================================

emit_every_branch >/dev/null 2>"$TMPROOT/stderr.log"
check "no function writes to stderr across every documented branch" \
  "$(LC_ALL=C tr -d '\n' < "$TMPROOT/stderr.log")" ""

# ============================================================================
# Invariant: bash 3.2 compatible -- no associative arrays, no ${var^^}. Both
# are bash 4 syntax that a 3.2 host (stock macOS) fails to PARSE, so the
# whole file dies at source time rather than at the call. Checked statically
# because a bash 5 test run cannot otherwise observe it, and checked here
# rather than left to a lint because an associative array is precisely what a
# rewrite of burn_model_style's model-to-hues mapping would reach for.
# ============================================================================

# Comment lines are excluded for the same reason the ASCII scan excludes
# them: the docblock NAMES both constructs in order to forbid them, and a
# check that fired on the prose banning a thing would be a check on the
# wrong text.
theme_code=$(LC_ALL=C grep -v '^[[:space:]]*#' "$THEME")

check "burn-theme.sh declares no associative array (declare/local/typeset -A is bash 4)" \
  "$(printf '%s\n' "$theme_code" | LC_ALL=C grep -cE '(declare|local|typeset)[[:space:]]+-[A-Za-z]*A')" "0"
check "burn-theme.sh uses no case-modification expansion (\${var^^} / \${var,,} are bash 4)" \
  "$(printf '%s\n' "$theme_code" | LC_ALL=C grep -cE '\$\{[A-Za-z_0-9]+(\[[^]]*\])?(\^|,)')" "0"

# ============================================================================
# Invariant: forks NO external process -- every function (including
# burn_frame_advance's read/write) is pure bash builtins. Re-run a
# representative call per function with PATH cleared: if a real
# implementation shelled out to date/expr/sed/bc/cat/etc., the call would
# fail (or silently misbehave) with only builtins on offer.
# ============================================================================

no_fork() { # bash_code
  PATH= "$REAL_BASH" -c ". '$THEME'; $1" 2>/dev/null
}

NF_FRAME="$TMPROOT/no-fork-frame"
nf_frame_code="burn_frame_advance '$NF_FRAME'"
nf_out=$(no_fork "$nf_frame_code")
check "no-fork: burn_frame_advance still advances (absent file -> 1)" "$nf_out" "1"

nf_out=$(no_fork 'burn_model_style opus; printf "%s" "${BURN_HUES[*]}"')
check "no-fork: burn_model_style still sets BURN_HUES for opus" \
  "$nf_out" "196 202 208 214 220 226 214 208"

nf_out=$(no_fork 'burn_model_style opus; printf "%s" "${BURN_MASCOT-unset}"')
check "no-fork: burn_model_style still sets no BURN_MASCOT" "$nf_out" "unset"

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

ei_out=$(env_isolated 'burn_model_style opus; printf "%s" "${BURN_HUES[*]}"')
check "env-isolated: burn_model_style still sets the opus hue family" \
  "$ei_out" "196 202 208 214 220 226 214 208"

ei_frame_code="burn_frame_advance '$TMPROOT/env-isolated-frame'"
ei_out=$(env_isolated "$ei_frame_code")
check "env-isolated: burn_frame_advance still starts a fresh file at 1" "$ei_out" "1"

# Decoy threshold-shaped env vars must not change a locked-constant mapping.
check "thresholds are locked constants: decoy env vars do not change burn_plan_color" \
  "$(BURN_PLAN_RED=999 BURN_PLAN_COLOR_THRESHOLD=1 CLAUDE_BURN_RED=0 burn_plan_color 80)" \
  "${ESC}[38;5;196m"

# A decoy BURN_MASCOT EXPORTED into the shell must not be honoured either --
# the emoji is removed, not made configurable. (env_isolated is not usable
# here: env -i would wipe the very variable under test, so this exports into
# an otherwise-normal child shell.)
check "an exported BURN_MASCOT is ignored, not rendered" \
  "$(BURN_MASCOT="🎭" "$REAL_BASH" -c ". '$THEME'; burn_model_style opus; burn_rainbow 'Opus' 0" 2>/dev/null | LC_ALL=C grep -c "$NONASCII_RE")" \
  "0"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
