#!/usr/bin/env bash
# save-status.test.sh — verifies the docblock "Contract: B03 save-failure page
# status" in plugins/render-doc/assets/template.html, clause by clause.
#
# There is no browser/DOM harness in this repo (see render.test.sh's own
# header), so every clause here is structural: render a fixture with render.sh
# and assert over the RENDERED .html. That location is deliberate — it proves
# both that the template carries the behaviour and that the behaviour survives
# the splice, and the splice is what a regression would break. Only the two
# pinned-baseline checks (the script-element count and the "unchanged"
# saveAnnotationToFile body) also read the template directly, because those are
# statements about the source itself.
#
# The B03 docblock quotes the very strings these checks look for (the failure
# message, the "error" class, .btn.error, SAVE_ENABLED). Every code-facing
# check therefore runs against the rendered output with that docblock deleted —
# the workgraph-render.test.sh precedent, a sed range delete — so contract
# prose can never satisfy a check meant for real code.
#
# Deliberately NOT asserted, as implementer's choice rather than contract:
# the exact statement spelling of the failure arm (a 1-line window is allowed
# so the call may wrap), whether the error class is set by one toggle or by an
# add/remove pair, and the .btn.error background property. What is pinned is
# what the docblock names: the message text, the SAVE_ENABLED guard, the
# error-class polarity, the single shared timeout, the coral colour, and the
# three invariants.

set -uo pipefail  # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER="$PLUGIN_DIR/scripts/render.sh"
TEMPLATE="$PLUGIN_DIR/assets/template.html"
FIXTURES_DIR="$PLUGIN_DIR/fixtures"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

FAILURES=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'ok: %s\n' "$*"
}
summary() {
  if [ "$FAILURES" -gt 0 ]; then
    printf 'save-status.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
    exit 1
  fi
  printf 'save-status.test.sh: all assertions passed\n'
  exit 0
}

# The template writes JS strings with double quotes throughout; accept either
# quote style rather than pinning the implementer to one.
Q="[\"']"
# The not-ok polarity, in the spellings a reasonable implementation might use.
NOTOK='(!ok|ok[[:space:]]*===[[:space:]]*false|ok[[:space:]]*==[[:space:]]*false|ok[[:space:]]*!==[[:space:]]*true)'
# The contract's exact status text. Note the em dash: it is part of the string.
MSG='Save failed — use Copy all feedback'

# --- Helpers -----------------------------------------------------------------

# extract_block <file> <start-ere> — print the brace-balanced block that starts
# at the first line matching <start-ere>. Used instead of a fixed-indent sed
# range so a reformatted body still extracts cleanly.
#
# NB: awk -v processes escape sequences, so a backslash meant for the regex
# must be doubled in the shell string ('\\(' here becomes '\(' in awk).
extract_block() {
  awk -v START="$2" '
    !grab && $0 ~ START { grab = 1 }
    grab {
      print
      line = $0
      o = gsub(/\{/, "{", line)
      c = gsub(/\}/, "}", line)
      depth += o - c
      if (o > 0) started = 1
      if (started && depth <= 0) exit
    }
  ' "$1"
}

# window_has <file> <anchor-ere> <needle-ere> <radius> — true when some line
# matching <anchor-ere> has <needle-ere> within +/- <radius> lines. Keeps the
# "these two things belong together" checks from pinning one exact line layout.
window_has() {
  wh_file="$1"; wh_anchor="$2"; wh_needle="$3"; wh_radius="$4"
  while IFS= read -r wh_n; do
    [ -n "$wh_n" ] || continue
    wh_lo=$((wh_n - wh_radius))
    [ "$wh_lo" -lt 1 ] && wh_lo=1
    wh_hi=$((wh_n + wh_radius))
    if sed -n "${wh_lo},${wh_hi}p" "$wh_file" | grep -qE "$wh_needle"; then
      return 0
    fi
  done < <(grep -nE "$wh_anchor" "$wh_file" | cut -d: -f1)
  return 1
}

# --- Render ------------------------------------------------------------------
# One fixture is enough: every B03 clause lives in the template's own CSS/JS and
# is fixture-independent. plan.md carries a literal </script> in a fenced block,
# which is what makes the script-count invariant below a real check rather than
# a tautology. (render.test.sh covers the pipeline across all four fixtures.)

SRC="$WORK/plan.md"
OUT="$WORK/plan.html"
cp "$FIXTURES_DIR/plan.md" "$SRC"

if ! "$RENDER" "$SRC" > /dev/null 2>"$WORK/render.stderr"; then
  fail "setup: render.sh exited non-zero on fixtures/plan.md — no clause could be checked"
  summary
fi
if [ ! -s "$OUT" ]; then
  fail "setup: render.sh wrote no output for fixtures/plan.md — no clause could be checked"
  summary
fi
pass "setup: fixture rendered"

# The B03 docblock is one contiguous /* ... */ block whose prose quotes the
# failure message, the "error" class and .btn.error verbatim; delete it so it
# cannot satisfy a check meant for real code. Harmless once an implementation
# removes the docblock: the range start simply never matches.
CODE="$WORK/rendered.no-docblock.html"
sed '/\/\* Contract: B03 save-failure page status/,/\*\//d' "$OUT" > "$CODE"

if grep -qF 'Contract: B03' "$CODE"; then
  fail "sanity: B03 docblock strip did not remove the marker — the sed range needs adjusting"
else
  pass "sanity: B03 docblock stripped from the rendered output"
fi

# =============================================================================
# Clause: the failure arm exists
# =============================================================================

THEN="$WORK/then-block.js"
extract_block "$CODE" 'saveAnnotationToFile\\(item\\)\\.then\\(' > "$THEN"

if [ -s "$THEN" ] && grep -qF 'showSaveStatus' "$THEN"; then
  pass "save callback: .then block extracted"
else
  fail "save callback: could not extract the saveAnnotationToFile(item).then(...) block (anchor moved?)"
fi

# The success arm's call is untouched by this block.
if grep -qF 'showSaveStatus("Saved to " + (sourceFileName || "file"), true)' "$CODE"; then
  pass "save callback: success arm unchanged"
else
  fail "save callback: the success-arm showSaveStatus call is missing or altered"
fi

if grep -qF "$MSG" "$THEN"; then
  pass "failure arm: status text \"$MSG\" present in the save callback"
else
  fail "failure arm: status text \"$MSG\" not found in the save callback"
fi

# ...shown via showSaveStatus, in the not-ok style (ok argument false).
if window_has "$THEN" "$MSG" 'showSaveStatus' 1; then
  pass "failure arm: the status text is passed to showSaveStatus"
else
  fail "failure arm: the status text is not passed to showSaveStatus"
fi
if window_has "$THEN" "$MSG" '(^|[^[:alnum:]_])false([^[:alnum:]_]|$)' 1; then
  pass "failure arm: shown in the not-ok style (ok argument false)"
else
  fail "failure arm: not shown in the not-ok style (no false ok argument beside the status text)"
fi

# =============================================================================
# Clause: SAVE_ENABLED false shows NOTHING — a file:// reader never sees it.
# Assert the guard, not merely the message.
# =============================================================================

if window_has "$THEN" "$MSG" 'SAVE_ENABLED' 1; then
  pass "file:// guard: the failure arm is gated on SAVE_ENABLED"
else
  fail "file:// guard: the failure arm is NOT gated on SAVE_ENABLED — a file:// reader would see the message"
fi

# One occurrence only: no second, ungated copy of the message anywhere else.
msg_count="$(grep -cF "$MSG" "$CODE")"
: "${msg_count:=0}"
if [ "$msg_count" -eq 1 ]; then
  pass "file:// guard: the status text occurs exactly once (no ungated duplicate)"
else
  fail "file:// guard: expected exactly 1 occurrence of the status text, found $msg_count"
fi

# The falsy-on-file:// half of the guard: unchanged early return, unchanged
# protocol test. Without these, SAVE_ENABLED would stop meaning "http:".
if grep -qF 'if (!SAVE_ENABLED) return Promise.resolve(false);' "$CODE"; then
  pass "file:// guard: saveAnnotationToFile still resolves falsy when saving is disabled"
else
  fail "file:// guard: saveAnnotationToFile's !SAVE_ENABLED early return is missing or altered"
fi
if grep -qF 'var SAVE_ENABLED = window.location.protocol === "http:";' "$CODE"; then
  pass "file:// guard: SAVE_ENABLED is still derived from the http: protocol"
else
  fail "file:// guard: the SAVE_ENABLED definition is missing or altered"
fi

# =============================================================================
# Clause: showSaveStatus adds "error" when ok is false, removes it when true;
# the same timeout that clears "active" also clears "error".
# =============================================================================

SSS="$WORK/showSaveStatus.body"
SSS_HEAD="$WORK/showSaveStatus.head"
SSS_TAIL="$WORK/showSaveStatus.tail"
: > "$SSS_HEAD"
: > "$SSS_TAIL"
extract_block "$CODE" 'function showSaveStatus' > "$SSS"

if [ -s "$SSS" ] && grep -qF 'feedback-btn' "$SSS"; then
  pass "showSaveStatus: body extracted"
else
  fail "showSaveStatus: could not extract the function body (anchor moved?)"
fi

# "the SAME timeout": exactly one, so the reset cannot have been forked into a
# second timer with its own lifetime.
sto_count="$(grep -c 'setTimeout' "$SSS")"
: "${sto_count:=0}"
if [ "$sto_count" -eq 1 ]; then
  pass "showSaveStatus: exactly one setTimeout (the reset is still shared)"
else
  fail "showSaveStatus: expected exactly 1 setTimeout, found $sto_count"
fi

# Split at that timeout: what runs immediately vs what the reset defers.
sto_line="$(grep -n 'setTimeout' "$SSS" | head -1 | cut -d: -f1)"
if [ -n "$sto_line" ] && [ "$sto_line" -gt 1 ]; then
  sed -n "1,$((sto_line - 1))p" "$SSS" > "$SSS_HEAD"
  sed -n "${sto_line},\$p" "$SSS" > "$SSS_TAIL"
fi

# Immediate half: the error class is both set and cleared off the ok argument —
# one toggle, or an add/remove pair. Either satisfies "gains it when ok is
# false and loses it when ok is true" (the failure-then-success edge case).
if grep -qE "classList\.toggle\([^)]*${Q}error${Q}" "$SSS_HEAD"; then
  pass "showSaveStatus: error class toggled (set and cleared in one call)"
elif grep -qE "classList\.add\([^)]*${Q}error${Q}" "$SSS_HEAD" \
  && grep -qE "classList\.remove\([^)]*${Q}error${Q}" "$SSS_HEAD"; then
  pass "showSaveStatus: error class added and removed on the ok branches"
else
  fail "showSaveStatus: the error class is never both set and cleared before the timeout"
fi

if window_has "$SSS_HEAD" "${Q}error${Q}" "$NOTOK" 2; then
  pass "showSaveStatus: the error class is keyed to ok being false"
else
  fail "showSaveStatus: the error class is not keyed to ok being false (wrong or missing polarity)"
fi

# The pre-existing active/ok treatment is unchanged beside it.
if grep -qE "classList\.toggle\([^)]*${Q}active${Q},[[:space:]]*ok" "$SSS_HEAD"; then
  pass "showSaveStatus: the active class is still toggled on ok"
else
  fail "showSaveStatus: the active/ok toggle is missing or altered"
fi

# Deferred half: the one timeout clears both classes.
if grep -qE "classList\.remove\([^)]*${Q}error${Q}" "$SSS_TAIL" \
  || grep -qE "classList\.toggle\([^)]*${Q}error${Q}[^)]*false" "$SSS_TAIL"; then
  pass "showSaveStatus: the timeout clears the error class"
else
  fail "showSaveStatus: the timeout does not clear the error class"
fi
if grep -qE "classList\.remove\([^)]*${Q}active${Q}" "$SSS_TAIL" \
  || grep -qE "classList\.toggle\([^)]*${Q}active${Q}[^)]*false" "$SSS_TAIL"; then
  pass "showSaveStatus: the timeout still clears the active class"
else
  fail "showSaveStatus: the timeout no longer clears the active class"
fi

# Edge case "several failures in a row: no stacking, no duplicate nodes" — the
# status is written into the one existing button, never into new DOM.
if grep -qE 'createElement|appendChild|insertAdjacent|innerHTML' "$SSS"; then
  fail "showSaveStatus: creates or appends DOM — repeated failures would stack nodes"
else
  pass "showSaveStatus: creates no DOM (repeated failures cannot stack)"
fi

# =============================================================================
# Clause: a .btn.error CSS rule in the coral warning colour, consistent with
# the existing .btn.active treatment.
# =============================================================================

CSSRULE="$WORK/btn-error.css"
extract_block "$CODE" '\\.btn\\.error' > "$CSSRULE"

if [ -s "$CSSRULE" ]; then
  pass ".btn.error: rule present in the rendered output"
else
  fail ".btn.error: no such CSS rule in the rendered output"
fi

# It must be a real rule inside the stylesheet, not a string in the script.
btn_error_line="$(grep -nE '\.btn\.error' "$CODE" | head -1 | cut -d: -f1)"
style_close_line="$(grep -n '</style>' "$CODE" | head -1 | cut -d: -f1)"
if [ -n "$btn_error_line" ] && [ -n "$style_close_line" ] && [ "$btn_error_line" -lt "$style_close_line" ]; then
  pass ".btn.error: declared inside the stylesheet"
else
  fail ".btn.error: not declared inside the stylesheet (before </style>)"
fi

# Consistent with .btn.active: a foreground colour and a border colour. The
# leading class excludes 'border-color' from satisfying the 'color' check.
if grep -qE "(^|[{;[:space:]])color:" "$CSSRULE"; then
  pass ".btn.error: sets a foreground color"
else
  fail ".btn.error: sets no foreground color (.btn.active sets one)"
fi
if grep -qE "border-color:" "$CSSRULE"; then
  pass ".btn.error: sets a border-color"
else
  fail ".btn.error: sets no border-color (.btn.active sets one)"
fi

# Coral, by token or by the value the token holds.
if grep -qiE 'var\(--coral\)|#ff8a6b|255,[[:space:]]*138,[[:space:]]*107' "$CSSRULE"; then
  pass ".btn.error: uses the coral warning colour"
else
  fail ".btn.error: does not use the coral warning colour (--coral / #ff8a6b)"
fi

# The neighbouring button states are untouched.
for cls in 'active' 'attention'; do
  if grep -qE "\.btn\.${cls}[[:space:]]*\{" "$CODE"; then
    pass ".btn.${cls}: rule still present"
  else
    fail ".btn.${cls}: rule went missing"
  fi
done

# =============================================================================
# Invariants: script count, no external resource, payload untouched
# =============================================================================

# How many script elements the current template closes, read not guessed —
# including the cytoscape and cytoscape-dagre splices #246 added. Comparing
# rendered against template alone would not catch a new element, because both
# counts rise together; the pin is what catches a <script> nobody intended. It
# is expected to move when a script element is added on purpose, and such an
# addition re-baselines this number in the same commit.
EXPECTED_SCRIPT_CLOSES=6

TEMPLATE_SCRIPT_CLOSES="$(grep -c '</script>' "$TEMPLATE")"
: "${TEMPLATE_SCRIPT_CLOSES:=0}"
if [ "$TEMPLATE_SCRIPT_CLOSES" -eq "$EXPECTED_SCRIPT_CLOSES" ]; then
  pass "script-count invariant: template still closes $EXPECTED_SCRIPT_CLOSES script elements (no new <script>)"
else
  fail "script-count invariant: template closes $TEMPLATE_SCRIPT_CLOSES script elements, expected $EXPECTED_SCRIPT_CLOSES"
fi

rendered_closes="$(grep -c '</script>' "$OUT")"
: "${rendered_closes:=0}"
if [ "$rendered_closes" -eq "$TEMPLATE_SCRIPT_CLOSES" ]; then
  pass "script-count invariant: rendered output matches the template ($rendered_closes)"
else
  fail "script-count invariant: rendered output closes $rendered_closes script elements, template closes $TEMPLATE_SCRIPT_CLOSES"
fi

# Self-contained at view time (same probe render.test.sh uses).
if grep -E '<link[^>]+href="https?:|src="https?:|src='"'"'https?:|url\(https?:|@import|fonts\.googleapis' "$OUT" > /dev/null; then
  fail "no external resource: rendered output references an external URL/CDN"
else
  pass "no external resource: rendered output references no external URL/CDN"
fi

# The template is hand-written and carries no URL at all today (only the
# "http:" protocol literal), so it takes the stricter probe: any http(s):// at
# all would be new, and a web font or CDN is exactly how one would arrive.
if grep -qE 'https?://' "$TEMPLATE"; then
  fail "no external resource: template now contains an http(s):// URL"
else
  pass "no external resource: template contains no http(s):// URL"
fi

# The annotation payload is untouched: the item literal built at Add time...
if grep -qF 'var item = { id: state.nextId++, section: anchor, excerpt: excerpt, tag: selected, note: note };' "$CODE"; then
  pass "payload invariant: the annotation item literal is unchanged"
else
  fail "payload invariant: the annotation item literal is missing or altered"
fi

# ...and saveAnnotationToFile itself, byte for byte. The contract says this
# function does not change, so any edit — including a reformat — trips this.
SAVE_FN="$WORK/saveAnnotationToFile.body"
SAVE_FN_BASELINE="$WORK/saveAnnotationToFile.baseline"
extract_block "$CODE" 'function saveAnnotationToFile' > "$SAVE_FN"
cat > "$SAVE_FN_BASELINE" <<'BASELINE'
    function saveAnnotationToFile(item) {
      if (!SAVE_ENABLED) return Promise.resolve(false);
      return fetch("/annotate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          md: sourcePath,
          section: item.section,
          excerpt: item.excerpt,
          tag: item.tag,
          note: item.note
        })
      }).then(function (res) {
        return res.ok;
      })["catch"](function () {
        return false;
      });
    }
BASELINE

if cmp -s "$SAVE_FN" "$SAVE_FN_BASELINE"; then
  pass "payload invariant: saveAnnotationToFile is byte-for-byte unchanged"
else
  fail "payload invariant: saveAnnotationToFile differs from the scaffold baseline (contract says it does not change)"
fi

# --- Summary -----------------------------------------------------------------
summary
