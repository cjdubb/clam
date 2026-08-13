#!/usr/bin/env bash
# graph-layout-width.test.sh — pins the graph-view width fix in
# plugins/render-doc/assets/template.html. The page layout is a two-column
# grid (`.layout { grid-template-columns: 250px minmax(0, 1fr) }`) whose
# first column exists for the #toc nav. The graph lifecycle hides that nav
# (004-B25), and with the nav display:none, grid auto-placement drops #main
# into the 250px first column — so the cytoscape canvas rendered in a strip
# at the left edge of the page. The fix collapses the grid to a single
# full-width column for the graph's lifetime via a "graph-active" class on
# the .layout element, added in activateGraphView() before cytoscape reads
# the container's size and removed in deactivateGraphView().
#
# There is no DOM/browser harness in this repo (render.test.sh's header says
# so), so these are structural/string assertions over template.html's source,
# run against a copy with all "/* Contract: ... */" docblocks removed so
# contract prose can never satisfy a check meant for real code. Precedent:
# graph-default.test.sh, workgraph-graph.test.sh.

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$PLUGIN_DIR/assets/template.html"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

FAILURES=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'PASS  %s\n' "$*"
}

# Strip every "/* Contract: ... */" docblock: starts on a line whose first
# non-space text is "/* Contract:" and ends on the first line containing "*/".
CODE="$WORK/template.stripped.html"
awk '
  /^[[:space:]]*\/\* Contract:/ { skipping = 1 }
  skipping { if (index($0, "*/") > 0) { skipping = 0 }; next }
  { print }
' "$TEMPLATE" > "$CODE"

if grep -qF 'Contract:' "$CODE"; then
  fail "sanity: contract docblocks were not stripped from template.html"
else
  pass "sanity: contract docblocks stripped from template.html"
fi

# Extract a named function body by brace counting, for confinement checks.
extract_function() { # <file> <name>
  awk -v fn="$2" '
    index($0, "function " fn "(") > 0 { found = 1 }
    found {
      print
      n = gsub(/\{/, "{"); depth += n
      n = gsub(/\}/, "}"); depth -= n
      if (depth <= 0 && seen_open) { exit }
      if (n || depth > 0) { seen_open = 1 }
    }
  ' "$1"
}

# --- The CSS rule -------------------------------------------------------------

if grep -qE '\.layout\.graph-active[[:space:]]*\{[[:space:]]*grid-template-columns:[[:space:]]*minmax\(0,[[:space:]]*1fr\)' "$CODE"; then
  pass "css: .layout.graph-active collapses the grid to a single minmax(0, 1fr) column"
else
  fail "css: no .layout.graph-active rule setting grid-template-columns to a single column"
fi

# The base two-column layout is untouched: the TOC column is still 250px wide
# when the graph view is off.
if grep -qE 'grid-template-columns:[[:space:]]*250px[[:space:]]+minmax\(0,[[:space:]]*1fr\)' "$CODE"; then
  pass "css: the base .layout grid keeps its 250px TOC column for the card view"
else
  fail "css: the base two-column .layout grid (250px minmax(0, 1fr)) is gone"
fi

# --- The lifecycle toggle -----------------------------------------------------

ACTIVATE="$WORK/activate.js"
extract_function "$CODE" activateGraphView > "$ACTIVATE"
DEACTIVATE="$WORK/deactivate.js"
extract_function "$CODE" deactivateGraphView > "$DEACTIVATE"

if [ -s "$ACTIVATE" ] && [ -s "$DEACTIVATE" ]; then
  pass "sanity: activateGraphView and deactivateGraphView extracted"
else
  fail "sanity: could not extract the graph lifecycle functions — no clause below can be checked"
fi

if grep -qF 'classList.add("graph-active")' "$ACTIVATE"; then
  pass "activate: activateGraphView adds the graph-active class to the layout"
else
  fail "activate: activateGraphView does not add the graph-active class"
fi

# The class must be applied BEFORE the cytoscape instance is built, or the
# canvas is sized against the squeezed 250px column.
if awk '/classList\.add\("graph-active"\)/ { seen = 1 } /renderWorkGraphGraphView\(\)/ { if (!seen) exit 1 }' "$ACTIVATE"; then
  pass "activate: the class is added before renderWorkGraphGraphView() sizes the canvas"
else
  fail "activate: renderWorkGraphGraphView() runs before the graph-active class is added — cytoscape sizes against the squeezed column"
fi

if grep -qF 'classList.remove("graph-active")' "$DEACTIVATE"; then
  pass "deactivate: deactivateGraphView removes the graph-active class"
else
  fail "deactivate: deactivateGraphView does not remove the graph-active class"
fi

# Null-guarded lookups: a missing .layout element must not throw mid-lifecycle
# (the degrade posture the rest of the graph lifecycle already keeps).
for body in "$ACTIVATE" "$DEACTIVATE"; do
  if grep -qE 'if[[:space:]]*\([[:space:]]*layoutEl[[:space:]]*\)' "$body"; then
    pass "guard: $(basename "$body" .js): the .layout lookup is null-guarded before the class toggle"
  else
    fail "guard: $(basename "$body" .js): the .layout class toggle is not null-guarded"
  fi
done

# Confinement: the class is toggled nowhere else, so no other code path can
# leave the layout collapsed while the card view is showing.
toggles="$(grep -cF 'graph-active' "$CODE" 2> /dev/null)" || toggles=0
lifecycle_toggles=0
for body in "$ACTIVATE" "$DEACTIVATE"; do
  n="$(grep -cF 'graph-active' "$body" 2> /dev/null)" || n=0
  lifecycle_toggles=$((lifecycle_toggles + n))
done
css_uses="$(grep -cF '.layout.graph-active' "$CODE" 2> /dev/null)" || css_uses=0
if [ "$((lifecycle_toggles + css_uses))" -eq "$toggles" ] && [ "$lifecycle_toggles" -ge 2 ]; then
  pass "confinement: every graph-active toggle lives in the graph lifecycle (plus the CSS rule)"
else
  fail "confinement: $toggles graph-active reference(s) but only $lifecycle_toggles in the lifecycle and $css_uses in CSS — something else toggles the layout"
fi

# --- Verdict ------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'graph-layout-width.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'graph-layout-width.test.sh: all assertions passed\n'
