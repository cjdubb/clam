#!/usr/bin/env bash
# workgraph-graph.test.sh — verifies two contract docblocks clause by
# clause, both from plan 001-render-doc-graph-view:
#   - "Contract: 229-B01 vendored-graph-libs-and-splice" in
#     plugins/render-doc/scripts/render.sh (the splice mechanism, the
#     asset stubs, and the slot-location comment in template.html).
#   - "Contract: 229-B02 graph-view-mode" in
#     plugins/render-doc/assets/template.html (the renderWorkGraphGraphView
#     stub and its topbar/updateChrome wiring).
#
# There is no DOM/browser harness in this repo (render.test.sh's own
# header), so these are structural/string assertions over source text, not
# execution of the graph — the contracts' visible commitments (marker
# shape/order, config literals, color/style tokens, function reuse), never
# implementation micro-structure such as helper names or DOM shape, which
# are the implementer's choice. render.sh's *execution* behavior (splice
# output, missing-asset death) is covered in render.test.sh instead, per
# brief; this file covers everything else.
#
# This plan reuses the same block-letter scheme as an EARLIER, already
# merged plan (001-render-doc-workgraph-transform, #222), which committed
# its own absence checks for the bare (unprefixed) block-letter contract
# literals (workgraph-docs.test.sh, workgraph-render.test.sh). This plan's
# markers use the disambiguated "229-" prefixed form throughout — every
# check below greps for that prefixed form, never the bare one.
#
# Docblocks quote the very strings several of these checks look for
# (marker names, color hexes, "dagre"/"rankDir"/"TB", "(dropped)",
# "dotted", "bezier"/"triangle"/"vee", "graph-toggle" itself). Every
# code-facing check below therefore runs against the relevant file with
# its OWN contract docblock comment stripped first, so contract prose can
# never satisfy a check meant for real content — verified empirically
# while writing this suite: every substring this file greps for appears,
# right now, ONLY inside the two docblocks and nowhere else in the repo.

set -uo pipefail  # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER="$PLUGIN_DIR/scripts/render.sh"
TEMPLATE="$PLUGIN_DIR/assets/template.html"
CYTOSCAPE="$PLUGIN_DIR/assets/cytoscape.min.js"
CYTOSCAPE_DAGRE="$PLUGIN_DIR/assets/cytoscape-dagre.min.js"

CYTOSCAPE_SHA256='9c2a3bf2592e0b14a1f7bec07c03a54f16dedf32af9cd0af155c716aa6c87bc3'
CYTOSCAPE_DAGRE_SHA256='b9e9d704119970f4255c035baa98d778e94af4b2efd2bdba20a601a869417223'

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

# macOS has no sha256sum; shasum -a 256 is the equivalent (base64 -d/-D
# precedent in render.test.sh).
sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

# Strip a leading `/*! ... */` provenance-header block (marked.min.js's own
# convention, and the one the 229-B01 docblock specifies for these two
# files) so a hash can be taken of the real content below it. The CURRENT
# stub files do not start with `/*!` at all (they start with a plain `/*
# Contract: ...` stub comment), so this strips nothing at scaffold state
# and hashes the whole stub — which is exactly why the hash check below is
# red right now.
strip_provenance_header() { # <file>
  awk '
    NR==1 && /^\/\*!/ { instrip=1; next }
    instrip && /^[[:space:]]*\*\/[[:space:]]*$/ { instrip=0; next }
    instrip { next }
    { print }
  ' "$1"
}

strip_comments() { sed '/<!--/,/-->/d' "$1"; }  # HTML comments

# =============================================================================
# B01 — plugins/render-doc/scripts/render.sh (splice mechanism)
# =============================================================================

RENDER_CODE="$WORK/render.no-docblock.sh"
sed '/^# Contract: 229-B01 vendored-graph-libs-and-splice/,/^die() {/ { /^die() {/!d; }' "$RENDER" > "$RENDER_CODE"

if grep -qF 'Contract: 229-B01' "$RENDER_CODE"; then
  fail "sanity: 229-B01 docblock strip did not remove the marker — the sed range needs adjusting"
else
  pass "sanity: 229-B01 docblock stripped from render.sh"
fi

# --- Clause: the self-check's grep is extended with both new marker names --
selfcheck_line="$(grep -F "grep -q '__MARKED_SPLICE__" "$RENDER_CODE" || true)"
if [ -z "$selfcheck_line" ]; then
  fail "render.sh: could not find the splice self-check line (anchor moved?)"
else
  pass "render.sh: splice self-check line found"
  if printf '%s' "$selfcheck_line" | grep -qF '__CYTOSCAPE_SPLICE__' \
     && printf '%s' "$selfcheck_line" | grep -qF '__CYTOSCAPE_DAGRE_SPLICE__'; then
    pass "render.sh: self-check extended with both new marker names"
  else
    fail "render.sh: self-check does not grep for both __CYTOSCAPE_SPLICE__ and __CYTOSCAPE_DAGRE_SPLICE__"
  fi
  # The original three marker names must still be checked too (additive only).
  if printf '%s' "$selfcheck_line" | grep -qF '__MARKED_SPLICE__' \
     && printf '%s' "$selfcheck_line" | grep -qF '__DOC_B64_SPLICE__' \
     && printf '%s' "$selfcheck_line" | grep -qF '__SOURCE_PATH_SPLICE__'; then
    pass "render.sh: self-check still checks the three original marker names"
  else
    fail "render.sh: self-check lost one of the three original marker names"
  fi
fi

# --- Clause: the awk program gains a distinct ENVIRON-backed block per marker,
# exactly as the marked splice does (each marker name is its own awk pattern).
if grep -qE '/__CYTOSCAPE_SPLICE__/' "$RENDER_CODE"; then
  pass "render.sh: awk program has a pattern rule for __CYTOSCAPE_SPLICE__"
else
  fail "render.sh: awk program has no pattern rule for __CYTOSCAPE_SPLICE__"
fi
if grep -qE '/__CYTOSCAPE_DAGRE_SPLICE__/' "$RENDER_CODE"; then
  pass "render.sh: awk program has a pattern rule for __CYTOSCAPE_DAGRE_SPLICE__"
else
  fail "render.sh: awk program has no pattern rule for __CYTOSCAPE_DAGRE_SPLICE__"
fi

# ENVIRON-backed (each block reads its asset path from an env var, like the
# marked/b64/source-path blocks do) — grown past the 3-marker baseline.
ENVIRON_BASELINE=3
environ_count="$(grep -c 'ENVIRON\[' "$RENDER_CODE")"
if [ "$environ_count" -gt "$ENVIRON_BASELINE" ]; then
  pass "render.sh: ENVIRON[ usages grew past the $ENVIRON_BASELINE-marker baseline ($environ_count)"
else
  fail "render.sh: ENVIRON[ usages did not grow past the $ENVIRON_BASELINE-marker baseline (found $environ_count)"
fi

# =============================================================================
# B01 — plugins/render-doc/assets/template.html (slot markers)
# =============================================================================

TEMPLATE_NOCOMMENTS="$WORK/template.no-comments.html"
strip_comments "$TEMPLATE" > "$TEMPLATE_NOCOMMENTS"

# --- Clause: each marker lives alone on its own line, wrapped in its own
# <script>...</script> pair, exactly like the __MARKED_SPLICE__ slot. HTML
# comments are stripped first: at scaffold state the marker names are only
# mentioned in the slot-location comment's prose, never as a live line, so
# this is legitimately absent (red) until that comment is replaced.
assert_marker_in_script_tag() { # <marker>
  marker="$1"
  line_no="$(grep -nx "$marker" "$TEMPLATE_NOCOMMENTS" | head -1 | cut -d: -f1)"
  if [ -z "$line_no" ]; then
    fail "template.html: no line is exactly '$marker' (outside comments)"
    return
  fi
  pass "template.html: '$marker' appears alone on its own line (outside comments)"
  prev="$(sed -n "$((line_no - 1))p" "$TEMPLATE_NOCOMMENTS" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  next="$(sed -n "$((line_no + 1))p" "$TEMPLATE_NOCOMMENTS" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [ "$prev" = "<script>" ] && [ "$next" = "</script>" ]; then
    pass "template.html: '$marker' is wrapped in its own <script></script> pair"
  else
    fail "template.html: '$marker' is not immediately wrapped by <script>/</script> (prev='$prev' next='$next')"
  fi
}
assert_marker_in_script_tag '__CYTOSCAPE_SPLICE__'
assert_marker_in_script_tag '__CYTOSCAPE_DAGRE_SPLICE__'

# --- Clause: cytoscape precedes cytoscape-dagre precedes the app script.
cyto_line="$(grep -nx '__CYTOSCAPE_SPLICE__' "$TEMPLATE_NOCOMMENTS" | head -1 | cut -d: -f1)"
dagre_line="$(grep -nx '__CYTOSCAPE_DAGRE_SPLICE__' "$TEMPLATE_NOCOMMENTS" | head -1 | cut -d: -f1)"
app_line="$(grep -n '"use strict";' "$TEMPLATE_NOCOMMENTS" | head -1 | cut -d: -f1)"

if [ -n "$cyto_line" ] && [ -n "$dagre_line" ] && [ -n "$app_line" ] \
   && [ "$cyto_line" -lt "$dagre_line" ] && [ "$dagre_line" -lt "$app_line" ]; then
  pass "template.html: cytoscape marker precedes dagre marker precedes the app script"
else
  fail "template.html: marker order is not cytoscape < dagre < app script (cyto=$cyto_line dagre=$dagre_line app=$app_line)"
fi

# =============================================================================
# B01 — the two vendored asset files themselves
# =============================================================================

check_vendored_asset() { # <file> <label> <pinned-sha256>
  file="$1"; label="$2"; pin="$3"
  if [ ! -s "$file" ]; then
    fail "$label: file missing or empty"
    return
  fi
  stripped="$WORK/$label.stripped"
  strip_provenance_header "$file" > "$stripped"

  actual_hash="$(sha256_of < "$stripped")"
  if [ "$actual_hash" = "$pin" ]; then
    pass "$label: sha256(content below the /*! header) matches the pinned original ($pin)"
  else
    fail "$label: sha256 mismatch — expected $pin, got $actual_hash"
  fi

  # Invariants: no closing script tag, no HTML comment opener, no
  # external-resource form, below the header.
  if grep -qF '</script' "$stripped"; then
    fail "$label: content contains a closing script tag"
  else
    pass "$label: no closing script tag in content"
  fi
  if grep -qF '<!--' "$stripped"; then
    fail "$label: content contains an HTML comment opener"
  else
    pass "$label: no HTML comment opener in content"
  fi
  if grep -qE 'href="https?:|src="https?:|src='"'"'https?:|url\(https?:|@import|fonts\.googleapis' "$stripped"; then
    fail "$label: content references an external resource"
  else
    pass "$label: no external-resource reference in content"
  fi
}

check_vendored_asset "$CYTOSCAPE" "cytoscape.min.js" "$CYTOSCAPE_SHA256"
check_vendored_asset "$CYTOSCAPE_DAGRE" "cytoscape-dagre.min.js" "$CYTOSCAPE_DAGRE_SHA256"

# =============================================================================
# B02 — plugins/render-doc/assets/template.html (graph-view-mode)
# =============================================================================

TEMPLATE_NOB02="$WORK/template.no-B02-docblock.html"
sed '/^    \/\* Contract: 229-B02 graph-view-mode/,/^    \*\/$/d' "$TEMPLATE" > "$TEMPLATE_NOB02"

if grep -qF 'Contract: 229-B02' "$TEMPLATE_NOB02"; then
  fail "sanity: 229-B02 docblock strip did not remove the marker — the sed range needs adjusting"
else
  pass "sanity: 229-B02 docblock stripped from template.html"
fi

# The app IIFE script, extracted by content (not line number, which shifts
# as the implementation grows): the first bare <script> block whose body
# contains "use strict". Robust to lines added anywhere else in the file.
extract_app_script() { # <file>
  awk '
    /^  <script>$/ { buf = $0 "\n"; instag = 1; next }
    instag && /"use strict";/ { isapp = 1 }
    instag { buf = buf $0 "\n" }
    instag && /^  <\/script>$/ {
      if (isapp) { printf "%s", buf; exit }
      instag = 0; buf = ""; isapp = 0
    }
  ' "$1"
}
APP_JS="$WORK/app-script.no-B02-docblock.js"
extract_app_script "$TEMPLATE_NOB02" > "$APP_JS"

if [ -s "$APP_JS" ]; then
  pass "template.html: app script extracted (docblock stripped)"
else
  fail "template.html: could not extract the app script (\"use strict\" anchor moved?)"
fi

# --- Clause: renderWorkGraphGraphView exists; NotImplemented marker gone ---
if grep -q 'function renderWorkGraphGraphView' "$TEMPLATE"; then
  pass "renderWorkGraphGraphView: function still present"
else
  fail "renderWorkGraphGraphView: function definition missing"
fi
if grep -qF 'NotImplemented: 229-B02 graph-view-mode' "$TEMPLATE_NOB02"; then
  fail "renderWorkGraphGraphView: NotImplemented marker still present in code (docblock-stripped)"
else
  pass "renderWorkGraphGraphView: NotImplemented marker gone"
fi

# --- Clause: a topbar "Graph" toggle button beside the schema toggle -------
TOPBAR="$(awk '/<header class="topbar">/{p=1} p{print} /<\/header>/{if(p) exit}' "$TEMPLATE_NOB02")"
if printf '%s' "$TOPBAR" | grep -qF 'id="graph-toggle"'; then
  pass "topbar: a button with id=\"graph-toggle\" is present"
else
  fail "topbar: no id=\"graph-toggle\" button found"
fi
if printf '%s' "$TOPBAR" | grep -qF 'id="schema-toggle"'; then
  pass "topbar: schema-toggle still present (graph-toggle sits beside it, not instead of it)"
else
  fail "topbar: schema-toggle is missing"
fi

# --- Clause: the button is actually wired up in the app script -------------
if grep -qE 'getElementById\(["'"'"']graph-toggle["'"'"']\)' "$APP_JS"; then
  pass "app script: graph-toggle is looked up via getElementById"
else
  fail "app script: no getElementById(\"graph-toggle\") reference found"
fi

# --- Clause: visible only for work-graph docType, hidden otherwise ---------
# updateChrome is the codebase's established extension point for docType-
# conditional chrome (it already gates schema-toggle this way).
UPDATE_CHROME="$(sed -n '/function updateChrome() {/,/document.getElementById("schema-toggle").addEventListener/p' "$APP_JS")"
if [ -z "$UPDATE_CHROME" ]; then
  fail "app script: could not extract updateChrome (anchor moved?)"
elif printf '%s' "$UPDATE_CHROME" | grep -qF 'graph-toggle'; then
  pass "updateChrome: references graph-toggle (docType-conditional visibility)"
else
  fail "updateChrome: does not reference graph-toggle — visibility gating not found at the established extension point"
fi

# --- Clause: renders with cytoscape + cytoscape-dagre, layout "dagre" rankDir "TB"
if grep -qF 'cytoscape(' "$APP_JS"; then
  pass "app script: cytoscape( is invoked (a cytoscape instance is constructed)"
else
  fail "app script: no cytoscape( invocation found"
fi
if grep -qF 'dagre' "$APP_JS"; then
  pass "app script: 'dagre' layout name referenced"
else
  fail "app script: no 'dagre' layout reference found"
fi
if grep -qE "rankDir.{0,20}TB|TB.{0,20}rankDir" "$APP_JS"; then
  pass "app script: rankDir \"TB\" configured"
else
  fail "app script: no rankDir/\"TB\" pairing found"
fi

# --- Clause: visual language — status fill/border colors -------------------
for hex in f6c177 4ade80 ff8a6b 2dd4bf; do
  if grep -qi "$hex" "$APP_JS"; then
    pass "app script: color #$hex referenced"
  else
    fail "app script: color #$hex not referenced"
  fi
done

# --- Clause: dropped nodes get a dotted border and a " (dropped)" suffix ---
if grep -qi 'dotted' "$APP_JS"; then
  pass "app script: 'dotted' border style referenced (dropped node)"
else
  fail "app script: no 'dotted' border style found"
fi
if grep -qF '(dropped)' "$APP_JS"; then
  pass "app script: \" (dropped)\" label suffix referenced"
else
  fail "app script: no \" (dropped)\" label suffix found"
fi

# --- Clause: decomposition as containment (F22), deps the only edges ------
if grep -qi 'c4a7e7' "$APP_JS"; then
  pass "app script: dep edge color #c4a7e7 referenced"
else
  fail "app script: dep edge color #c4a7e7 not referenced"
fi
if grep -qi 'triangle' "$APP_JS"; then
  fail "app script: 'triangle' arrow shape still present (parent renders as containment, never an edge)"
else
  pass "app script: no parent arrow shape (containment replaced the parent edge)"
fi
if grep -qF '":parent"' "$APP_JS"; then
  pass "app script: compound :parent scope-box style present"
else
  fail "app script: no :parent compound style found"
fi
if grep -qF 'data.parent = parentOf[node.id]' "$APP_JS"; then
  pass "app script: children carry the cycle-broken parent as compound data.parent"
else
  fail "app script: no compound data.parent wiring found"
fi
if grep -qiE '\bvee\b' "$APP_JS"; then
  pass "app script: 'vee' arrow shape referenced (dep edge)"
else
  fail "app script: no 'vee' arrow shape found"
fi
if grep -qi 'bezier' "$APP_JS"; then
  pass "app script: 'bezier' curve style referenced (double-edge case)"
else
  fail "app script: no 'bezier' curve style found"
fi

# --- Clause: click-to-card (tap a node -> switch to card view + scroll) ----
if grep -qF 'scrollIntoView' "$APP_JS"; then
  pass "app script: scrollIntoView referenced (click-to-card)"
else
  fail "app script: no scrollIntoView reference found"
fi
if grep -qE "\\.on\\(.tap.|addListener\\(.tap.|'tap'|\"tap\"" "$APP_JS"; then
  pass "app script: a 'tap' interaction is wired"
else
  fail "app script: no 'tap' interaction found"
fi

# --- Clause: Errors — building/laying out the graph is try/catch-guarded ---
# Narrow terms only (cytoscape / the render function name): a loose "graph"
# substring false-positives on identifiers like parseWorkGraphNode.
tap_try_catch="$(awk '
  /try[[:space:]]*\{/ { buf = $0; intry = 1; next }
  intry { buf = buf "\n" $0 }
  intry && /catch/ {
    if (buf ~ /cytoscape|renderWorkGraphGraphView/) found = 1
    intry = 0
  }
  END { if (found) print "FOUND"; else print "NOTFOUND" }
' "$APP_JS")"
if [ "$tap_try_catch" = "FOUND" ]; then
  pass "app script: graph building/layout is wrapped in try/catch"
else
  fail "app script: no try/catch found around graph building/layout"
fi

# --- Clause (Inputs): reuses parseWorkGraphNode/decorateWorkGraphNode/
# breakWorkGraphCycles from the card transform rather than re-parsing —
# each currently appears exactly twice (its own def + its one call site in
# transformWorkGraph); reuse from the graph view must grow that past 2.
REUSE_BASELINE=2
for fn in parseWorkGraphNode decorateWorkGraphNode breakWorkGraphCycles; do
  count="$(grep -c "${fn}(" "$TEMPLATE_NOB02")"
  if [ "$count" -gt "$REUSE_BASELINE" ]; then
    pass "$fn: referenced more than the def+existing-call baseline ($count call sites) — reused by the graph view"
  else
    fail "$fn: still only referenced $count time(s) (baseline $REUSE_BASELINE) — graph view does not appear to reuse it"
  fi
done

# --- Invariants: card view untouched, additive only ------------------------
if grep -q 'function transformWorkGraph(doc)' "$TEMPLATE"; then
  pass "invariant: transformWorkGraph (card view) still defined"
else
  fail "invariant: transformWorkGraph (card view) is missing"
fi
if grep -q 'function buildWorkGraphNodeTree' "$TEMPLATE"; then
  pass "invariant: buildWorkGraphNodeTree (card view) still defined"
else
  fail "invariant: buildWorkGraphNodeTree (card view) is missing"
fi
if grep -qF 'state.schemaOn = !state.schemaOn;' "$TEMPLATE"; then
  pass "invariant: schema-toggle's two-state semantics are untouched"
else
  fail "invariant: schema-toggle's toggle logic is missing or changed"
fi

# --- Invariant: the graph container never becomes block-annotatable — B02
# must not grow BLOCK_SEL/SYNTH_SEL at all (pinned to the value as of this
# test wave; canvas content is not block-annotatable per contract).
BLOCK_SEL_BASELINE='p, li, blockquote, tr, .tl-entry, .wg-summary'
SYNTH_SEL_BASELINE='.rec-flag, .opt-num, .crit-badge, .edge-arrow, .pros-lbl, .cons-lbl, .dq-rec-lbl, .block-annotate, .composer, .wg-status-pill, .wg-delivery-pill, .wg-dep-badge, .wg-focus-banner'
current_block_sel="$(sed -nE 's/.*var BLOCK_SEL = "([^"]*)".*/\1/p' "$TEMPLATE" | head -1)"
current_synth_sel="$(sed -nE 's/.*var SYNTH_SEL = "([^"]*)".*/\1/p' "$TEMPLATE" | head -1)"
if [ "$current_block_sel" = "$BLOCK_SEL_BASELINE" ]; then
  pass "invariant: BLOCK_SEL unchanged (graph container is not block-annotatable)"
else
  fail "invariant: BLOCK_SEL changed from the pre-B02 baseline ('$BLOCK_SEL_BASELINE' -> '$current_block_sel')"
fi
if [ "$current_synth_sel" = "$SYNTH_SEL_BASELINE" ]; then
  pass "invariant: SYNTH_SEL unchanged"
else
  fail "invariant: SYNTH_SEL changed from the pre-B02 baseline ('$SYNTH_SEL_BASELINE' -> '$current_synth_sel')"
fi

# --- F14: always-visible legend and label badges ------------------------------
# The legend names both edge kinds and the status colours; badges surface
# Unit/Block/PR-group ids from Notes/Goal prose on the graph label.
for needle in 'wg-graph-legend' 'contains (Parent)' 'depends on (Deps)' 'buildGraphLegend' 'wgNodeBadge'; do
  if grep -qF "$needle" "$APP_JS"; then
    pass "F14: app script carries '$needle'"
  else
    fail "F14: app script missing '$needle'"
  fi
done
if grep -qF 'pointer-events: none' "$TEMPLATE"; then
  pass "F14: legend never intercepts pointer input (pointer-events: none pinned)"
else
  fail "F14: legend pointer-events: none missing from template CSS"
fi

# --- F15: optional Delivery field rendered as a second badge ------------------
# The protocol's Delivery: field (local | pr <ref> | merged | deployed) shows
# as a second pill on cards and the panel and a second bracket on graph labels;
# a node without the field renders exactly as before.
for needle in 'wgDeliveryPill' 'wg-delivery-pill' 'deliveryKind'; do
  if grep -qF "$needle" "$APP_JS"; then
    pass "F15: app script carries '$needle'"
  else
    fail "F15: app script missing '$needle'"
  fi
done
if grep -qF 'wg-delivery-merged' "$TEMPLATE"; then
  pass "F15: per-kind delivery pill CSS present in template"
else
  fail "F15: per-kind delivery pill CSS missing from template"
fi
if grep -qE 'Goal\|Status\|Parent\|Deps\|Delivery\|Notes' "$APP_JS"; then
  pass "F15: field label parser recognizes Delivery"
else
  fail "F15: field label parser does not recognize Delivery"
fi

# --- F22: legend speaks the containment language ------------------------------
if grep -qF 'lg-box' "$APP_JS" && grep -qF '.lg-box' "$TEMPLATE"; then
  pass "F22: legend shows a scope box for contains (Parent)"
else
  fail "F22: legend scope-box marker (lg-box) missing"
fi

# --- F24: canvas grows with the layout; fit never magnifies past 1:1 ----------
for needle in 'container.style.height' 'cy.zoom() > 1' 'cy.fit(cy.elements()' ; do
  if grep -qF "$needle" "$APP_JS"; then
    pass "F24: app script carries '$needle'"
  else
    fail "F24: app script missing '$needle'"
  fi
done

# --- F19: #<node-id> fragment deep-links a node's panel on first load ---------
for needle in 'applyWorkGraphDeepLink' 'location.hash' 'wgHashDismissed'; do
  if grep -qF "$needle" "$APP_JS"; then
    pass "F19: app script carries '$needle'"
  else
    fail "F19: app script missing '$needle'"
  fi
done

# --- Invariant: no new external resources -----------------------------------
if grep -E '<link[^>]+href="https?:|src="https?:|src='"'"'https?:|url\(https?:|@import|fonts\.googleapis' "$APP_JS" > /dev/null; then
  fail "invariant: app script references an external URL/CDN"
else
  pass "invariant: no external URL/CDN reference in app script"
fi

# --- Edge cases: not mechanically checkable without a DOM/cytoscape harness.
# Zero parseable nodes (button hidden), a single node, multiple roots, dep
# cycles (dagre's acyclic handling), dropped nodes staying visible, and a
# dual parent+dep edge pair all require executing the graph build against a
# live DOM, which this repo has no harness for (same limitation
# render.test.sh documents for --open/annotation-server behavior). These
# are acceptance-verified by the orchestrator instead.

# --- Summary -----------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'workgraph-graph.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'workgraph-graph.test.sh: all assertions passed\n'
