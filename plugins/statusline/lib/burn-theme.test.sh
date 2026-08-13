#!/bin/bash
# Table-driven functional tests for burn-theme.sh: the presentation layer for
# the burnrate line -- the flat per-model colour, the reasoning-effort colour,
# the meter colour scales (plan, today, pace, ctx-state, ctx-fullness, trend),
# the fixed countdown colour and the reset countdown string. Every function is
# a pure mapping from value to appearance (Contract: B03 burn-theme, plan
# 001-statusline-burnrate-uplift, amended by B08 burn-theme-deemoji, plan
# 002-statusline-emoji-removal, extended by B13/B14/B15, plan
# 003-statusline-meter-colour, and narrowed by B05 line2-groups, plan
# 001-statusline-glance-uplift), so these tests are table-driven and pin the
# contract's exact literal colour codes -- not a paraphrase.
#
# What B08 changed, and what it deliberately did not:
#
#   GONE.  burn_pet, with its four mood tiers, its 8-frame face arrays and
#          its effect-character arrays. burn_model_style's BURN_MASCOT.
#          Nothing replaces either. The tests for them are not relaxed, they
#          are inverted: absence is asserted as sharply as the old presence
#          was, because "the emoji is removed, not relocated" is the contract.
#
#   NEW.   One file-wide invariant, checked three independent ways (source
#          text, parsed function bodies, runtime output): no function in this
#          file emits a non-ASCII character. That is what keeps a mascot or a
#          mood glyph from creeping back in, and it holds regardless of which
#          function anyone tries to hide one in.
#
# What plan 003 adds, and why it leans on that same invariant: three more
# colour mappings (ctx fullness, weekly trend, and the fixed diff/countdown
# colours). B14's +/-3 dead band exists BECAUSE the upstream's on-track check
# mark cannot be adopted under the no-non-ASCII invariant, so the invariant is
# load-bearing for the new behaviour rather than merely inherited by it. All
# three of the file-wide scans reach the new functions: two enumerate from
# `declare -F` and pick them up automatically, and emit_every_branch -- which
# enumerates by hand -- lists them explicitly.
#
# What B05 line2-groups RETIRES, and how this file records it. B03 replaced the
# drifting per-character model palette with one flat colour per family, and
# B05's new line 2 carries no +added/-removed segment at all, so four functions
# now have no call site anywhere: burn_frame_advance, burn_model_style,
# burn_rainbow and burn_diff_color. They are deleted from burn-theme.sh, and
# their sections here are deleted with them rather than relaxed -- a test for a
# function that no longer exists cannot be made to pass honestly. What replaced
# each one still has its own section: burn_model_color for the first three,
# and nothing at all for the diff colour, which answered none of the seven
# glance-items. The two roster assertions (DOCUMENTED_FUNCTIONS and the
# parsed-body count) are re-pointed to the ten functions that survive and stay
# EXACT equalities, so the retirement is asserted, not merely tolerated.
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

# check_silent(label, bash_code): pins the Errors clause that every colour
# function shares -- exit 0 and an empty stderr -- in ONE assertion, because
# the two halves are one requirement: this output lands directly in the user's
# statusline, where a diagnostic corrupts the render and a non-zero return
# aborts it. Reported together so a failure shows which half broke.
check_silent() { # label bash_code
  local log="$TMPROOT/silent.log" rc
  eval "$2" >/dev/null 2>"$log"; rc=$?
  check "$1: exits 0 and writes nothing to stderr" \
    "rc=$rc stderr=$(LC_ALL=C tr -d '\n' < "$log")" "rc=0 stderr="
}

# sgr(CODE): the exact byte sequence the contract names for a colour token.
# "dim" is the bare SGR attribute \033[2m -- NOT colour 2 -- and every other
# token is a 256-colour opener. Openers only: none of these functions emits a
# reset, because the caller closes the sequence, and a test that tolerated a
# trailing reset would pass an implementation that breaks the renderer.
sgr() { # code
  case "$1" in
    dim) printf '%s[2m' "$ESC" ;;
    *) printf '%s[38;5;%sm' "$ESC" "$1" ;;
  esac
}

# tbl_arg(TOKEN): the argument a table row's INPUT token stands for. The
# tables below are whitespace-separated, which cannot carry an empty field, so
# the literal token <empty> stands for the empty-string argument that several
# of these contracts call out by name.
tbl_arg() { # token
  if [[ "$1" == "<empty>" ]]; then printf ''; else printf '%s' "$1"; fi
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

# B03 (plan 001) added burn_model_color to this roster. B05 line2-groups (same
# plan) is the "later block" B03's note pointed at: burn_model_color and the
# glance-item groups have taken over every call site, so burn_model_style,
# burn_rainbow, burn_frame_advance and burn_diff_color are RETIRED from
# burn-theme.sh and drop off this roster, leaving ten. burn_today_color and
# burn_pace_color stay: the contract does not retire them.
#
# The roster is still the EXACT inventory, not a subset: it is sorted and it is
# compared for EQUALITY, never "contains". That is what makes this list a real
# check in both directions after the shrink -- a retired function that survives
# in the file fails just as loudly as a surviving function that goes missing,
# and a new undocumented function still fails too.
DOCUMENTED_FUNCTIONS="burn_countdown_color burn_ctx_color burn_ctx_state burn_effort_color burn_model_color burn_pace_color burn_plan_color burn_reset_str burn_today_color burn_trend_color"

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

# Sourcing sets NO global at all. Since B05 no function in this file sets one
# either -- burn_model_style, the last one that did, is retired -- so this is
# now the stricter statement it always read as.
check "sourcing burn-theme.sh sets no BURN_* variable" \
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
# 10, not 14, since B05 retires four functions: the count moves in lockstep
# with DOCUMENTED_FUNCTIONS above and stays an exact equality (never >=), so a
# body that is not parsed -- or an extra one that is, including a retired
# function left behind -- still fails the scan-is-not-vacuous control.
check "the parsed-body scan covers exactly the documented functions (scan is not vacuous)" \
  "$(printf '%s\n' "$parsed_bodies" | LC_ALL=C grep -c '^burn_[a-z_]* ()')" "10"
check "the non-ASCII pattern fires on a known non-ASCII byte" \
  "$(printf 'ok\nbad \xe2\x80\x94 here\n' | LC_ALL=C grep -c "$NONASCII_RE")" "1"
check "the non-ASCII pattern does NOT fire on an SGR escape (ESC is ASCII)" \
  "$(printf '%s[38;5;196mX%s[0m\n' "$ESC" "$ESC" | LC_ALL=C grep -c "$NONASCII_RE")" "0"

# 3. Runtime output over every documented branch. emit_every_branch calls
#    each function across its whole documented input space with ASCII-only
#    arguments, so anything non-ASCII on stdout came from this file, not from
#    the caller's text. (Every function left after B05 emits a bare colour
#    opener and never echoes caller text at all, so ASCII-only arguments make
#    the sweep unambiguous rather than merely convenient.)
emit_every_branch() {
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

  # This enumeration is by HAND, so a function added to burn-theme.sh and not
  # added here is silently exempt from both sweeps that use it (non-ASCII on
  # stdout, and the no-stderr invariant below). Every surviving function is
  # therefore listed across its whole documented input space. B05's four
  # retired functions are struck from here rather than left calling into a
  # file that no longer defines them.
  for f in 200 100 61 60 59 40 39 20 19 0 -5 abc ""; do burn_ctx_color "$f"; done
  for f in 99 15 14 8 7 4 3 0 -3 -4 -8 -15 -99 abc ""; do burn_trend_color "$f"; done
  # B03, plan 001: the same by-hand enumeration duty applies to burn_model_color
  # -- listed across its whole documented input space (every family, a stray
  # name, an empty name, a multi-match name, a parenthesised suffix) so both
  # sweeps that use this function reach it.
  for f in haiku sonnet opus fable HAIKU "Claude Sonnet 4.6" "Opus 5 (1M context)" \
           "Claude Opus Haiku" gpt-4 "" "-"; do
    burn_model_color "$f"
  done
  burn_model_color
  burn_countdown_color
  burn_countdown_color stray

  burn_reset_str 604800 0
  burn_reset_str 187200 0
  burn_reset_str 86400 0
  burn_reset_str 187200 abc
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

# ============================================================================
# burn_model_color MODEL  [B03, plan 001-statusline-glance-uplift] -- ONE flat
# 256-colour opener per model family, replacing the drifting per-character
# palette of burn_model_style + burn_rainbow. Blue DEEPENS with capability
# (haiku 117 light, sonnet 75 mid, opus 33 blue) and purple sits outside that
# ramp (fable 141); anything unrecognised, empty included, is dim grey 245.
#
# The flatness is the feature, so it is asserted as such: the same name gives
# the same code on every call, with no frame, time or other input in the
# mapping. That invariance IS what "remove the fancy colouring" means, which is
# why it is pinned here rather than left implied by the per-family rows.
#
# B05 line2-groups is the later block B03 anticipated: burn_model_style and
# burn_rainbow have no call sites left, so they are retired and their sections
# are deleted from this file. This function is now the model name's ENTIRE
# appearance, which is why the flatness and no-glyph assertions below matter
# more after the retirement than before it.
# ============================================================================

while read -r model code note; do
  [[ -z "$model" ]] && continue
  check "model '$model' -> $code ($note)" \
    "$(burn_model_color "$(tbl_arg "$model")")" "$(sgr "$code")"
done <<'MODEL_ROWS'
haiku      117 light blue: the shallow end of the capability ramp
sonnet     75  mid blue
opus       33  blue: the deep end of the ramp
fable      141 purple, deliberately outside the blue ramp
gpt-4      245 an unrecognised family takes dim grey
claude     245 a bare vendor name names no family
<empty>    245 an empty display name takes dim grey, never nothing
-          245 a stray token is just unrecognised
MODEL_ROWS

# Case-insensitive SUBSTRING matching, over the real display-name shapes the
# payload supplies -- the mapping never sees a bare family token in practice.
while read -r code model; do
  [[ -z "$code" ]] && continue
  check "case-insensitive substring match: '$model' -> $code" \
    "$(burn_model_color "$model")" "$(sgr "$code")"
done <<'MODEL_NAME_ROWS'
117 Claude Haiku 4.5
75 Claude Sonnet 4.6
33 Claude Opus 4.7
141 the fable model
117 HAIKU
75 SONNET
33 OPUS
141 FABLE
33 oPuS
MODEL_NAME_ROWS

# A parenthesised suffix still matches: trimming the display name is the
# renderer's job, not this function's.
check "parenthesised suffix still matches: 'Opus 5 (1M context)' -> blue 33" \
  "$(burn_model_color "Opus 5 (1M context)")" "$(sgr 33)"
check "parenthesised suffix still matches: 'Haiku 4.5 (fast)' -> light blue 117" \
  "$(burn_model_color "Haiku 4.5 (fast)")" "$(sgr 117)"

# Multi-match names resolve deterministically to the FIRST family in the
# contract's documented order -- haiku, sonnet, opus, fable -- regardless of
# where each token appears in the name. Order-of-appearance in the STRING is
# the plausible wrong reading, so both orderings of the same pair are pinned to
# the same colour.
check "multiple matches ('Claude Opus Haiku') resolve to the first documented family (haiku 117)" \
  "$(burn_model_color "Claude Opus Haiku")" "$(sgr 117)"
check "multiple matches ('Claude Haiku Opus') resolve identically (haiku 117, not string order)" \
  "$(burn_model_color "Claude Haiku Opus")" "$(sgr 117)"
check "multiple matches ('Sonnet Fable') resolve to the first documented family (sonnet 75)" \
  "$(burn_model_color "Sonnet Fable")" "$(sgr 75)"
check "multiple matches ('Fable Opus') resolve to the first documented family (opus 33)" \
  "$(burn_model_color "Fable Opus")" "$(sgr 33)"

# Blue deepens with capability: the three blue tiers are three DISTINCT codes,
# and purple is none of them. A single blue reused across families would pass
# every "is it a colour" check and lose the whole point of the ramp.
check "the three blue tiers are distinct codes, and purple is outside the ramp" \
  "$(burn_model_color haiku)$(burn_model_color sonnet)$(burn_model_color opus)$(burn_model_color fable)" \
  "$(sgr 117)$(sgr 75)$(sgr 33)$(sgr 141)"

# Flatness: the colour does not vary with time, call count or any other input.
# Ten consecutive calls with the same name -- interleaved with calls for OTHER
# models, which would perturb a drifting palette -- give one identical code
# every time. (Before B05 this loop also interleaved burn_frame_advance calls;
# B05 retires the frame counter outright, so the perturbation that remains is
# the interleaved other-model call, and the assertion is unchanged.)
flat_out=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  burn_model_color sonnet >/dev/null
  flat_out="$flat_out$(burn_model_color "Claude Opus 4.7")"
done
flat_want=""
for _ in 1 2 3 4 5 6 7 8 9 10; do flat_want="$flat_want$(sgr 33)"; done
check "burn_model_color is flat: the same name gives the same code on every call" \
  "$flat_out" "$flat_want"

# One colour per name, not one per character: the whole render is a single
# opener, so the code appears exactly once no matter how long the name is.
check "burn_model_color emits exactly one colour escape for a long name (not one per character)" \
  "$(burn_model_color "Claude Sonnet 4.6" | grep -oE "${ESC}\\[38;5;[0-9]+m" | wc -l | tr -d ' ')" "1"

# A missing argument is not a third state: $1 is empty either way.
check "burn_model_color with no argument at all -> dim grey 245 (identical to an empty name)" \
  "$(burn_model_color)" "$(sgr 245)"

# Never nothing. An empty echo would leave the model name uncoloured while the
# caller still emits its reset, which is exactly how colour leaks into the next
# segment -- the failure mode the contract's Errors clause names.
check "burn_model_color on an unrecognised name emits something, never an empty string" \
  "$([ -n "$(burn_model_color junk)" ] && echo emitted || echo empty)" "emitted"
check "burn_model_color on an empty name emits something, never an empty string" \
  "$([ -n "$(burn_model_color "")" ] && echo emitted || echo empty)" "emitted"

# Grey 245 is a 256-COLOUR opener, not the dim SGR 2 attribute: the two are
# different tiers elsewhere in this file and conflating them is the plausible
# mis-reading of "dim grey".
check "burn_model_color's dim grey is 256-colour 245, not the SGR 2 attribute" \
  "$(burn_model_color junk | LC_ALL=C grep -c '\[2m')" "0"

# Bare opener, no reset: the caller closes it, as every burn_*_color here does.
check "burn_model_color emits only the bare colour prefix (no embedded reset)" \
  "$(burn_model_color opus | grep -c "${ESC}\\[0m")" "0"

model_want=$(sgr 117)
check "burn_model_color emits exactly the opener, with no trailing newline" \
  "$(burn_model_color haiku | wc -c | tr -d ' ')" "${#model_want}"

# Errors clause: none. Every input, documented or not, exits 0 silently.
check_silent "burn_model_color opus (a documented family)" 'burn_model_color opus'
check_silent "burn_model_color junk (unrecognised)" 'burn_model_color junk'
check_silent "burn_model_color with an empty name" 'burn_model_color ""'
check_silent "burn_model_color with no argument" 'burn_model_color'

# Sets no global and echoes only its colour: this function communicates through
# stdout alone, so nothing may leak into the caller's shell. (The one function
# in this file that ever set a global, burn_model_style, is retired by B05, so
# no exception to that rule survives.)
check "burn_model_color sets no BURN_* global (it communicates through stdout alone)" \
  "$(pristine 'burn_model_color opus >/dev/null; for v in ${!BURN@}; do echo "LEAK:$v"; done; echo "(none)"')" \
  "(none)"

# nocasematch is borrowed, not appropriated -- saved and restored in BOTH
# directions.
check "burn_model_color restores nocasematch=off when it was off" \
  "$(pristine 'shopt -u nocasematch; burn_model_color Opus >/dev/null; shopt -q nocasematch && echo on || echo off')" \
  "off"
check "burn_model_color leaves nocasematch=on when the caller had it on" \
  "$(pristine 'shopt -s nocasematch; burn_model_color Opus >/dev/null; shopt -q nocasematch && echo on || echo off')" \
  "on"

# The file-wide no-non-ASCII invariant, restated where a mascot would most
# plausibly come back: this function is the model name's whole appearance now,
# so a glyph re-attached to a family would land here first.
model_glyph_offenders=$(
  for m in haiku sonnet opus fable HAIKU "Claude Opus 4.7" "Claude Opus Haiku" gpt-4 ""; do
    burn_model_color "$m"
  done 2>/dev/null | LC_ALL=C grep -n "$NONASCII_RE"
)
check_clean "burn_model_color emits no glyph for any family (no mascot re-attached)" \
  "$model_glyph_offenders"

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
# burn_ctx_color PCT  [B13, plan 003] -- HOW FULL the context is, which is a
# different question from burn_ctx_state's "how stale is the session". The two
# coexist on purpose: the section above must keep passing unchanged alongside
# this one, because burn_ctx_state's LEVEL is what .local/.ctx-status.json
# publishes (decision 002) and B13 does not touch it.
#
# Four descending bands (the upstream ctxcol scale), every threshold >= and so
# boundary-inclusive, tested at the boundary and one below it. Nothing clamps
# at 100: the occupancy math feeding this is deliberately non-saturating.
# ============================================================================

while read -r pct code note; do
  [[ -z "$pct" ]] && continue
  check "ctx $pct -> $code ($note)" \
    "$(burn_ctx_color "$(tbl_arg "$pct")")" "$(sgr "$code")"
done <<'CTX_ROWS'
200     196 far above 100, an overrun -- nothing clamps
101     196 just above 100
100     196 exactly at compaction
61      196 inside the red band
60      196 exact boundary 60, inclusive
59      208 just under 60
41      208 inside the orange band
40      208 exact boundary 40, inclusive
39      214 just under 40
21      214 inside the yellow band
20      214 exact boundary 20, inclusive
19      40  just under 20, else branch
0       40  an empty context
-1      40  negative after a clock step
-100    40  far negative
abc     40  non-numeric takes the safest tier
<empty> 40  empty takes the safest tier
CTX_ROWS

# A missing argument is not a third state: $1 is empty either way, and the
# contract's "may be empty" covers both.
check "ctx with no argument at all -> green 40 (identical to an empty one)" \
  "$(burn_ctx_color)" "$(sgr 40)"

# The safest tier is the GREEN end, not the red one -- the Errors clause is
# explicit that a statusline which cannot parse a figure must never be the
# thing that raises an alarm about it. Pinned as agreement between the three
# unparseable forms and an empty context, because "fall back to the loudest
# tier" is the plausible wrong reading and it would break all four together.
check "ctx unparseable input takes the same tier as an empty context, never the alarm tier" \
  "$(burn_ctx_color abc)$(burn_ctx_color '')$(burn_ctx_color -1)$(burn_ctx_color 0)" \
  "$(sgr 40)$(sgr 40)$(sgr 40)$(sgr 40)"

check "burn_ctx_color emits only the bare colour prefix (no embedded reset)" \
  "$(burn_ctx_color 80 | grep -c "${ESC}\\[0m")" "0"

# Byte-exact: the opener and nothing else. Equality checks above cannot see a
# trailing newline (command substitution strips it), and a newline emitted
# into the middle of the statusline breaks the render.
ctx_want=$(sgr 196)
check "burn_ctx_color emits exactly the opener, with no trailing newline" \
  "$(burn_ctx_color 60 | wc -c | tr -d ' ')" "${#ctx_want}"

check_silent "burn_ctx_color 60 (in-band)" 'burn_ctx_color 60'
check_silent "burn_ctx_color abc (non-numeric)" 'burn_ctx_color abc'
check_silent "burn_ctx_color with no argument" 'burn_ctx_color'

# A decimal is outside the documented input space (PCT is an integer percent;
# only burn_pace_color documents decimal handling), so no band is asserted for
# it -- only that it cannot break the render. Whichever tier an implementation
# picks, it must still be a bare opener, silently.
check_silent "burn_ctx_color 60.5 (decimal, outside the documented input space)" 'burn_ctx_color 60.5'
check "burn_ctx_color on a decimal still emits a single bare colour opener" \
  "$(burn_ctx_color 60.5 2>/dev/null | grep -cE "^${ESC}\\[(38;5;)?[0-9]+m$")" "1"

# ============================================================================
# burn_trend_color TREND  [B14, plan 003] -- the weekly trend's magnitude,
# with a +/-3 DEAD BAND that reads as on-track. The dead band IS the feature:
# it is this plugin's substitute for the upstream's green check-mark glyph,
# which plan 003 declines to adopt so that the file-wide no-non-ASCII
# invariant stands unamended.
#
# The scale is deliberately ASYMMETRIC, off burn_metrics' fixed sign
# convention (POSITIVE = ahead of the glide = burning too fast): three tiers
# above the band, ONE below it, because under-use is not a hazard. A mirrored
# implementation is the plausible wrong reading, so every tier below -3 is
# pinned to grey individually rather than sampled once.
# ============================================================================

while read -r trend code note; do
  [[ -z "$trend" ]] && continue
  check "trend $trend -> $code ($note)" \
    "$(burn_trend_color "$(tbl_arg "$trend")")" "$(sgr "$code")"
done <<'TREND_ROWS'
0       40  dead centre: exactly on the glide
1       40  inside the dead band
3       40  exact upper edge of the dead band, inclusive
-1      40  inside the dead band, marginally behind
-3      40  exact lower edge of the dead band, inclusive
4       214 the smallest coloured magnitude ahead of the line
7       214 just under 8
8       208 exact boundary 8, inclusive
14      208 just under 15
15      196 exact boundary 15, inclusive
99      196 far ahead of the line
-4      245 the smallest coloured magnitude behind the line
-8      245 asymmetry: no orange tier below the band
-15     245 asymmetry: no red tier below the band
-99     245 far behind the line is still only grey
abc     40  non-numeric takes the on-track tier
<empty> 40  empty takes the on-track tier
-       40  a bare sign is not a number, so the non-numeric tier
TREND_ROWS

check "trend with no argument at all -> green 40 (identical to an empty one)" \
  "$(burn_trend_color)" "$(sgr 40)"

# Behind the line must not be warned about: grey is the tier that says
# "nothing to act on". The failure mode this guards is an implementation that
# mirrors the three positive tiers onto negative magnitudes, so the three
# magnitudes that WOULD differ under a mirror are asserted to agree.
check "the tiers are not mirrored: -8, -15 and -40 all emit the same grey 245" \
  "$(burn_trend_color -8)$(burn_trend_color -15)$(burn_trend_color -40)" \
  "$(sgr 245)$(sgr 245)$(sgr 245)"

# The dead band's two edges resolve to the SAME colour as dead centre -- the
# band is one tier, not three that happen to look alike.
check "the dead band is one tier: -3, 0 and 3 all emit the same colour" \
  "$(burn_trend_color -3)$(burn_trend_color 0)$(burn_trend_color 3)" \
  "$(sgr 40)$(sgr 40)$(sgr 40)"

check "burn_trend_color emits only the bare colour prefix (no embedded reset)" \
  "$(burn_trend_color 20 | grep -c "${ESC}\\[0m")" "0"

trend_want=$(sgr 245)
check "burn_trend_color emits exactly the opener, with no trailing newline" \
  "$(burn_trend_color -9 | wc -c | tr -d ' ')" "${#trend_want}"

check_silent "burn_trend_color 8 (in-band)" 'burn_trend_color 8'
check_silent "burn_trend_color -12 (signed input is normal)" 'burn_trend_color -12'
check_silent "burn_trend_color abc (non-numeric)" 'burn_trend_color abc'
check_silent "burn_trend_color with no argument" 'burn_trend_color'

# B14's own restatement of the file-wide invariant: the on-track tier is a
# COLOUR, never a glyph. Swept over the whole documented input space, because
# the check mark would most plausibly be re-attached to exactly one band.
trend_glyph_offenders=$(
  for t in 0 1 3 -1 -3 4 7 8 14 15 99 -4 -8 -15 -99 abc ""; do
    burn_trend_color "$t"
  done 2>/dev/null | LC_ALL=C grep -n "$NONASCII_RE"
)
check_clean "burn_trend_color emits no glyph in any band (the upstream's on-track check mark is not adopted)" \
  "$trend_glyph_offenders"

# ============================================================================
# burn_countdown_color  [B15, plan 003] -- the fixed dim colour for the reset
# countdown that sits BESIDE a meter rather than being one. No thresholds, no
# severity: this is not a scale.
#
# Contract: B05 line2-groups (plan 001-statusline-glance-uplift) RETIRES
# burn_diff_color along with the +added/-removed segment it coloured -- the one
# value on line 2 that answered none of the seven glance-items. Its rows are
# deleted with it rather than relaxed. burn_countdown_color is NOT retired: B05
# keeps the countdown in both limit groups, wrapped in dimmed parens, so every
# assertion below stays exactly as sharp as it was.
# ============================================================================

check "countdown -> dim (subordinate to the meter it follows)" \
  "$(burn_countdown_color)" "$(sgr dim)"

# Takes NO argument, and the contract says a stray one is ignored ENTIRELY --
# the output never varies, so this is pinned against the same expected value
# rather than merely against itself.
for a in 5h 0 "" "3h27m" --help -1; do
  check "countdown with a stray argument '$a' -> dim (the argument is ignored entirely)" \
    "$(burn_countdown_color "$a")" "$(sgr dim)"
done

check "countdown output does not vary with its (ignored) argument" \
  "$(burn_countdown_color)$(burn_countdown_color anything)" "$(sgr dim)$(sgr dim)"

check "burn_countdown_color's dim is the bare SGR 2 attribute, not 256-colour 2" \
  "$(burn_countdown_color | LC_ALL=C grep -c '38;5;2m')" "0"

check "burn_countdown_color emits only the bare colour prefix (no embedded reset)" \
  "$(burn_countdown_color | grep -c "${ESC}\\[0m")" "0"

countdown_want=$(sgr dim)
check "burn_countdown_color emits exactly the dim sequence, with no trailing newline" \
  "$(burn_countdown_color | wc -c | tr -d ' ')" "${#countdown_want}"

check_silent "burn_countdown_color (no argument)" 'burn_countdown_color'
check_silent "burn_countdown_color with a stray argument" 'burn_countdown_color stray'

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
# burn_reset_str RESET_EPOCH NOW  [B04, plan 001-statusline-glance-uplift] --
# the DAY band. At 24 hours or more the countdown reads "2d4h" rather than
# "52h0m": three bands checked in order (>=24h -> "<D>d<H>h", >=1h ->
# "<H>h<M>m", below -> "<M>m"). The two existing bands are BYTE-IDENTICAL and
# are pinned unchanged in the section above -- this block adds a band, it does
# not re-derive them, so the rows above are as much a part of B04's contract as
# the rows below.
#
# In the day band the minutes are dropped, not rounded: the unit pair is
# always the two LARGEST non-zero-order units, which is what makes the segment
# a glance rather than a reading.
# ============================================================================

while read -r secs want note; do
  [[ -z "$secs" ]] && continue
  check "reset_str ${secs}s -> $want ($note)" "$(burn_reset_str "$secs" 0)" "$want"
done <<'RESET_ROWS'
86400    1d0h   exactly 24 hours: the band boundary, inclusive
86399    23h59m one second under 24 hours: still the hours band
90000    1d1h   25 hours
187200   2d4h   the contract's own example
190740   2d4h   2d4h59m: the minutes are dropped, never rounded up
604800   7d0h   a weekly reset, dead on
587520   6d19h  163h12m, the form this band replaces
863999   9d23h  just under ten days
864000   10d0h  ten days: a two-digit day count, nothing clamps
8640000  100d0h a malformed payload's far-future reset renders as-is
RESET_ROWS

# The day band is reached by the DIFFERENCE, not by the raw epoch: the same
# span measured from a non-zero NOW renders identically.
check "reset_str day band is computed from the difference (NOW=1000000)" \
  "$(burn_reset_str 1187200 1000000)" "2d4h"

# NOW's existing treatment is unchanged: a non-integer NOW is 0, as today.
check "reset_str non-integer NOW is treated as 0 in the day band" \
  "$(burn_reset_str 187200 abc)" "2d4h"
check "reset_str missing NOW is treated as 0 in the day band" \
  "$(burn_reset_str 187200)" "2d4h"

# The day band is a normal success: rc 0 and nothing on stderr, like every
# other band. Only an unparseable RESET_EPOCH returns non-zero.
out=$(burn_reset_str 187200 0); rc=$?
check "reset_str returns 0 in the day band" "$rc" "0"
check_silent "burn_reset_str 187200 0 (day band)" 'burn_reset_str 187200 0'
check_silent "burn_reset_str 86400 0 (band boundary)" 'burn_reset_str 86400 0'

# One line, no colour: the caller wraps it in parens and dims it, so a colour
# escape emitted here would be dimmed twice and could not be un-nested.
check "reset_str day band emits no colour escape" \
  "$(burn_reset_str 187200 0 | LC_ALL=C grep -c "${ESC}")" "0"
check "reset_str day band emits exactly one line" \
  "$(burn_reset_str 187200 0 | wc -l | tr -d ' ')" "1"

# The band is exclusive at its lower edge in BOTH directions: one second either
# side of 24 hours picks different bands, and the hours band never emits a
# day-count of its own.
check "reset_str at 86401s -> 1d0h (just over the boundary)" \
  "$(burn_reset_str 86401 0)" "1d0h"
check "reset_str below 24h never emits a 'd' unit" \
  "$(burn_reset_str 86399 0 | LC_ALL=C grep -c 'd')" "0"
check "reset_str at or above 24h never emits an 'm' unit" \
  "$(burn_reset_str 187200 0 | LC_ALL=C grep -c 'm')" "0"

# ============================================================================
# Invariant: no function writes to stderr in normal operation -- output lands
# directly in the user's statusline, so a stray diagnostic would corrupt the
# render rather than surface anywhere useful. Swept over the same
# every-branch matrix used for the ASCII check above. (Before B05 this sweep
# also covered burn_frame_advance's unwritable frame file; that function is
# retired with the frame counter, and no surviving function touches the
# filesystem at all, so there is no silent-failure path left to cover.)
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
# rewrite of burn_model_color's name-to-family mapping would reach for.
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
# Invariant: forks NO external process -- every function is pure bash
# builtins. Re-run a
# representative call per function with PATH cleared: if a real
# implementation shelled out to date/expr/sed/bc/cat/etc., the call would
# fail (or silently misbehave) with only builtins on offer.
# ============================================================================

no_fork() { # bash_code
  PATH= "$REAL_BASH" -c ". '$THEME'; $1" 2>/dev/null
}

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

# B04: the day band is arithmetic too -- date(1) is exactly what a
# day/hour split would reach for, and it is not available here.
nf_out=$(no_fork 'burn_reset_str 187200 0')
check "no-fork: burn_reset_str still formats 187200s as 2d4h" "$nf_out" "2d4h"

# B03: the model mapping is a pure case match, no tr/awk/sed for the fold.
nf_out=$(no_fork 'burn_model_color "Claude Opus 4.7"')
check "no-fork: burn_model_color still maps an opus name -> blue 33" "$nf_out" "$(sgr 33)"

nf_out=$(no_fork 'burn_model_color gpt-4')
check "no-fork: burn_model_color still maps an unrecognised name -> grey 245" "$nf_out" "$(sgr 245)"

nf_out=$(no_fork 'burn_ctx_color 60')
check "no-fork: burn_ctx_color still maps 60 -> red 196" "$nf_out" "$(sgr 196)"

nf_out=$(no_fork 'burn_trend_color -9')
check "no-fork: burn_trend_color still maps -9 -> grey 245" "$nf_out" "$(sgr 245)"

nf_out=$(no_fork 'burn_countdown_color')
check "no-fork: burn_countdown_color still emits the dim sequence" "$nf_out" "$(sgr dim)"

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

ei_out=$(env_isolated 'burn_reset_str 187200 0')
check "env-isolated: burn_reset_str still formats 187200s as 2d4h (no TZ or clock read)" "$ei_out" "2d4h"

ei_out=$(env_isolated 'burn_model_color sonnet')
check "env-isolated: burn_model_color still maps sonnet -> mid blue 75" "$ei_out" "$(sgr 75)"

ei_out=$(env_isolated 'burn_ctx_color 60')
check "env-isolated: burn_ctx_color still maps 60 -> red 196" "$ei_out" "$(sgr 196)"

ei_out=$(env_isolated 'burn_trend_color 15')
check "env-isolated: burn_trend_color still maps 15 -> red 196" "$ei_out" "$(sgr 196)"

ei_out=$(env_isolated 'burn_countdown_color')
check "env-isolated: burn_countdown_color still emits the dim sequence" "$ei_out" "$(sgr dim)"

# Decoy threshold-shaped env vars must not change a locked-constant mapping.
check "thresholds are locked constants: decoy env vars do not change burn_plan_color" \
  "$(BURN_PLAN_RED=999 BURN_PLAN_COLOR_THRESHOLD=1 CLAUDE_BURN_RED=0 burn_plan_color 80)" \
  "${ESC}[38;5;196m"

check "thresholds are locked constants: decoy env vars do not change burn_ctx_color" \
  "$(BURN_CTX_RED=999 BURN_CTX_COLOR_THRESHOLD=1 CLAUDE_CTX_RED=0 burn_ctx_color 60)" \
  "$(sgr 196)"

# The dead band in particular: "+/-3, locked" is the kind of number a later
# change would be tempted to make tunable, and the contract forbids it.
check "the trend dead band is a locked constant: decoy env vars do not widen or narrow it" \
  "$(BURN_TREND_DEADBAND=0 BURN_TREND_BAND=99 BURN_TREND_RED=1 burn_trend_color 3)" \
  "$(sgr 40)"

# B03: the per-family codes are constants, not a palette a user can retint.
check "burn_model_color's family colours are not env-configurable" \
  "$(BURN_MODEL_OPUS=99 BURN_MODEL_COLOR=99 CLAUDE_MODEL_COLOR=1 burn_model_color opus)" "$(sgr 33)"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
