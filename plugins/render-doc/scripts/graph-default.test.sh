#!/usr/bin/env bash
# graph-default.test.sh — verifies the docblock "Contract: B06
# graph-view-default" (plan 001-render-graph-always) in
# plugins/render-doc/assets/template.html clause by clause: a work-graph
# document first-paints the node-and-edge graph view instead of the card tree,
# every other docType is untouched, and the graph-build failure fallback still
# lands on the card view.
#
# There is no DOM/browser harness in this repo (render.test.sh's own header
# says so, and workgraph-graph.test.sh repeats it for the graph view), so these
# are structural/string assertions over template.html's source: the state
# initializer, the render()/activateGraphView() branches the contract points
# at, and the updateChrome() labeling it declares unchanged. Whether the first
# paint actually shows the graph is acceptance-verified by the orchestrator in
# a browser — the same split the graph-view suite already documents.
#
# The contract also rewrites part of an EARLIER contract's prose: the
# "Contract: 229-B02 graph-view-mode" docblock (plan 001-render-doc-graph-view)
# in the same file describes the card layout as "the default on load", which
# this block makes false. That rewrite is a Behavior clause of B06, so the
# 229-B02 docblock is asserted here as prose — deliberately, and only for the
# two sentences B06 names.
#
# Block-letter collision warning: an earlier, already-merged plan
# (001-render-doc-workgraph-transform) used bare block letters too, so
# "Contract: B06" appears in the *header prose* of other test files in this
# directory meaning something else entirely. The only live B06 for this plan is
# the template.html docblock this file greps by its full marker text,
# "Contract: B06 graph-view-default".
#
# Every code-facing check runs against a copy of template.html with ALL
# "/* Contract: ... */" docblocks removed, so contract prose (which quotes the
# very identifiers being checked — graphOn, work-graph, activateGraphView) can
# never satisfy a check meant for real code. Precedent: workgraph-graph.test.sh.

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

# --- Source extraction helpers ------------------------------------------------

# Remove every "/* Contract: ... */" block comment. Each one starts on a line
# whose first non-space text is "/* Contract:" and ends on the first line
# containing "*/" (which may be the tail of a prose line, as these docblocks
# are written).
strip_contract_docblocks() { # <file>
  awk '
    /^[[:space:]]*\/\* Contract:/ { instrip = 1 }
    instrip { if ($0 ~ /\*\//) { instrip = 0 } ; next }
    { print }
  ' "$1"
}

# The full text of one docblock, marker line through its closing "*/".
extract_docblock() { # <file> <marker substring>
  awk -v m="$2" '
    !started && index($0, m) { started = 1 }
    started { print; if (index($0, "*/")) exit }
  ' "$1"
}

# A whole function body, from its "function <name>(" line to the closing brace
# at the same indent. Indent-based rather than brace-counting: this file's
# functions are uniformly indented, and a mis-indented rewrite should be seen,
# not silently tolerated.
extract_function() { # <file> <function name>
  awk -v fn="$2" '
    !started && index($0, "function " fn "(") {
      match($0, /^[[:space:]]*/)
      close_line = substr($0, 1, RLENGTH) "}"
      started = 1
      print
      next
    }
    started { print; if ($0 == close_line) exit }
  ' "$1"
}

# One line, single-spaced, no leading/trailing space, so a check can span the
# source's line wrapping.
flatten() { tr '\n' ' ' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'; }

# Deliberately NOT `grep -q`: with `set -o pipefail`, grep -q exiting on the
# first match closes the pipe under a still-writing printf, and the resulting
# SIGPIPE (141) becomes the pipeline's status — a false FAIL on any haystack
# larger than the pipe buffer, which template.html comfortably is. Letting grep
# consume all of stdin and discarding its output costs a few milliseconds and
# removes the race entirely.
matches() { # <haystack> <ERE>
  printf '%s\n' "$1" | grep -E -- "$2" > /dev/null 2>&1
}
matches_f() { # <haystack> <literal>
  printf '%s\n' "$1" | grep -F -- "$2" > /dev/null 2>&1
}
has() { # <haystack> <ERE> <label>
  if matches "$1" "$2"; then pass "$3"; else fail "$3"; fi
}
has_f() { # <haystack> <literal> <label>
  if matches_f "$1" "$2"; then pass "$3"; else fail "$3"; fi
}
lacks_f() { # <haystack> <literal> <label>
  if matches_f "$1" "$2"; then fail "$3"; else pass "$3"; fi
}

TEMPLATE_CODE="$WORK/template.no-docblocks.html"
strip_contract_docblocks "$TEMPLATE" > "$TEMPLATE_CODE"

# --- Sanity: the docblock strip actually worked -------------------------------
# Every negative and every "is it in real code" check below depends on it, so a
# strip that silently stopped matching must be loud, not quietly permissive.
if grep -qF 'Contract:' "$TEMPLATE_CODE"; then
  fail "sanity: contract docblocks were not stripped from template.html (strip helper needs adjusting)"
else
  pass "sanity: contract docblocks stripped from template.html"
fi
if grep -qF 'Contract: B06 graph-view-default' "$TEMPLATE"; then
  pass "sanity: the B06 contract docblock is present to be stripped"
else
  fail "sanity: no 'Contract: B06 graph-view-default' docblock in template.html — nothing proves the strip ran"
fi

# =============================================================================
# Behavior / Inputs: state.graphOn initializes from docType, true for work-graph
# =============================================================================

STATE_BLOCK="$(awk '/^    var state = \{/ { p = 1 } p { print } p && /^    \};/ { exit }' "$TEMPLATE_CODE")"

if [ -z "$STATE_BLOCK" ]; then
  fail "state initializer: 'var state = {' block could not be located — the graphOn clauses cannot be checked"
else
  pass "state initializer: 'var state = {' block located"

  if matches "$STATE_BLOCK" 'graphOn:[[:space:]]*false'; then
    fail "state initializer: graphOn is still the scaffold literal 'false' (work-graph docs must start in graph view)"
  else
    pass "state initializer: graphOn is no longer the scaffold literal 'false'"
  fi

  has "$STATE_BLOCK" 'graphOn:' "state initializer: still has a graphOn field"

  # Invariant: only this one field changes; the rest of the initializer is
  # asserted byte-exact so a rewrite of the object is visible.
  has_f "$STATE_BLOCK" 'schemaOn: docType !== "generic",' "state initializer: schemaOn initializer byte-unchanged"
  has_f "$STATE_BLOCK" 'feedback: [],' "state initializer: feedback initializer byte-unchanged"
  has_f "$STATE_BLOCK" 'nextId: 1,' "state initializer: nextId initializer byte-unchanged"

  # Edge case: the default is not server-dependent — a file:// page starts in
  # graph view exactly like an http: one, so the initializer may not consult
  # the protocol or the annotation-server flag.
  if matches "$STATE_BLOCK" 'SAVE_ENABLED|location\.protocol|http'; then
    fail "state initializer: keys on the page's protocol/server (the graph default must be identical on file://)"
  else
    pass "state initializer: does not key on the page's protocol/server (identical on file://)"
  fi
fi

# Inputs: the initial value comes from docType. Scoped to the region between
# detectDocType's CALL and the end of the initializer so detectDocType's own
# body (which necessarily contains the "work-graph" literal) cannot satisfy it,
# while still allowing the implementation to compute the value into a local
# above the object literal rather than inline.
DOCTYPE_TO_STATE="$(awk '/^    var docType = detectDocType\(/ { p = 1 } p { print } p && /^    \};/ { exit }' "$TEMPLATE_CODE")"

if [ -z "$DOCTYPE_TO_STATE" ]; then
  fail "docType-to-state region: could not be located (the 'var docType = detectDocType(' anchor moved?)"
else
  has_f "$DOCTYPE_TO_STATE" 'work-graph' "state initializer: the initial view keys on the work-graph docType"
fi

# Invariant: one state object, so there is no second initializer to disagree.
state_objects="$(grep -c 'var state = {' "$TEMPLATE_CODE")"
if [ "$state_objects" = "1" ]; then
  pass "state initializer: exactly one state object literal"
else
  fail "state initializer: expected exactly 1 state object literal, found $state_objects"
fi

# =============================================================================
# Behavior / Edge case: the first paint runs through render()'s existing
# graphOn branch, including its no-parseable-nodes fallback
# =============================================================================

RENDER_FN="$(extract_function "$TEMPLATE_CODE" render)"

if [ -z "$RENDER_FN" ]; then
  fail "render(): function body could not be extracted — the first-paint clauses cannot be checked"
else
  pass "render(): function body extracted"
  has_f "$RENDER_FN" 'if (state.graphOn) {' "render(): still branches on state.graphOn (the first paint's graph path)"
  has_f "$RENDER_FN" 'activateGraphView();' "render(): graphOn branch still activates the graph view"
  has_f "$RENDER_FN" 'deactivateGraphView();' "render(): graphOn branch still has the no-parseable-nodes fallback"
  has_f "$RENDER_FN" 'state.graphOn = false;' "render(): the fallback still clears state.graphOn (zero-node edge case)"
  has_f "$RENDER_FN" 'workGraphModel = (docType === "work-graph") ? captureWorkGraphModel(doc) : null;' \
    "render(): the model capture that gates the fallback is byte-unchanged"
  has_f "$RENDER_FN" 'updateChrome();' "render(): still refreshes the chrome after the branch (toggle label/visibility)"
fi

# =============================================================================
# Errors: a throw while building the first graph degrades to the card view
# =============================================================================

ACTIVATE_FN="$(extract_function "$TEMPLATE_CODE" activateGraphView)"

if [ -z "$ACTIVATE_FN" ]; then
  fail "activateGraphView(): function body could not be extracted — the error-fallback clause cannot be checked"
else
  pass "activateGraphView(): function body extracted"
  has "$ACTIVATE_FN" 'catch' "activateGraphView(): still catches a build/layout throw"
  has_f "$ACTIVATE_FN" 'deactivateGraphView();' "activateGraphView(): the catch still falls back to the card view"
  has_f "$ACTIVATE_FN" 'state.graphOn = false;' "activateGraphView(): the catch still clears state.graphOn"
  # Outputs: graph container shown, card content hidden — the observable shape
  # of "first paint shows #graph-view active and #doc hidden".
  has_f "$ACTIVATE_FN" 'docEl.style.display = "none";' "activateGraphView(): still hides #doc when the graph is active"
  has_f "$ACTIVATE_FN" 'container.hidden = false;' "activateGraphView(): still reveals #graph-view when the graph is active"
fi

DEACTIVATE_FN="$(extract_function "$TEMPLATE_CODE" deactivateGraphView)"
if [ -z "$DEACTIVATE_FN" ]; then
  fail "deactivateGraphView(): function body could not be extracted"
else
  has_f "$DEACTIVATE_FN" 'document.getElementById("graph-view").hidden = true;' \
    "deactivateGraphView(): still hides #graph-view"
  has_f "$DEACTIVATE_FN" 'document.getElementById("doc").style.display = "";' \
    "deactivateGraphView(): still restores #doc"
fi

# =============================================================================
# Outputs / Invariants: the toggle's labeling and two-way switching are
# untouched — this block changes which view is painted first, nothing else
# =============================================================================

UPDATE_CHROME="$(extract_function "$TEMPLATE_CODE" updateChrome)"
if [ -z "$UPDATE_CHROME" ]; then
  fail "updateChrome(): function body could not be extracted"
else
  has_f "$UPDATE_CHROME" 'graphToggle.textContent = state.graphOn ? "Card view" : "Graph";' \
    "updateChrome(): active-view labeling byte-unchanged (graph active reads \"Card view\")"
  has_f "$UPDATE_CHROME" 'var graphAvailable = docType === "work-graph" && !!workGraphModel;' \
    "updateChrome(): toggle visibility gating byte-unchanged (hidden with zero parseable nodes)"
fi

TOGGLE_HANDLER="$(awk '/document.getElementById\("graph-toggle"\).addEventListener/ { p = 1 } p { print } p && /^    \}\);$/ { exit }' "$TEMPLATE_CODE")"
if [ -z "$TOGGLE_HANDLER" ]; then
  fail "graph-toggle handler: could not be located — the free-switching invariant cannot be checked"
else
  pass "graph-toggle handler: located"
  has_f "$TOGGLE_HANDLER" 'deactivateGraphView();' "graph-toggle: still switches graph -> card"
  has_f "$TOGGLE_HANDLER" 'activateGraphView();' "graph-toggle: still switches card -> graph"
fi

# Invariant: card rendering itself is untouched by this block.
TEMPLATE_CODE_TEXT="$(cat "$TEMPLATE_CODE")"
has "$TEMPLATE_CODE_TEXT" 'function transformWorkGraph\(doc\)' "invariant: transformWorkGraph (card tree) still defined"
has "$TEMPLATE_CODE_TEXT" 'function buildWorkGraphNodeTree' "invariant: buildWorkGraphNodeTree (card tree) still defined"
has_f "$TEMPLATE_CODE_TEXT" 'state.schemaOn = !state.schemaOn;' "invariant: the schema toggle's two-state semantics are untouched"

# =============================================================================
# Behavior: the scaffold note is gone but the contract docblock stays
# =============================================================================

B06_DOCBLOCK="$(extract_docblock "$TEMPLATE" 'Contract: B06 graph-view-default')"

if [ -z "$B06_DOCBLOCK" ]; then
  fail "B06 docblock: not found in template.html (the contract must survive implementation)"
else
  pass "B06 docblock: still present in template.html"
  lacks_f "$B06_DOCBLOCK" 'DELIBERATELY UNIMPLEMENTED' \
    "B06 docblock: the scaffold's DELIBERATELY UNIMPLEMENTED note is removed"
  has_f "$B06_DOCBLOCK" 'Behavior:' "B06 docblock: the contract clauses are retained"
fi

# =============================================================================
# Behavior: 229-B02's now-superseded prose is rewritten to graph-as-default
# =============================================================================

B02_DOCBLOCK="$(extract_docblock "$TEMPLATE" 'Contract: 229-B02 graph-view-mode' | flatten)"

if [ -z "$B02_DOCBLOCK" ]; then
  fail "229-B02 docblock: not found in template.html — the prose-rewrite clause cannot be checked"
else
  pass "229-B02 docblock: located"

  # The two sentences B06 names, in their current wording. Both are false once
  # the graph view paints first.
  lacks_f "$B02_DOCBLOCK" 'card layout (the default on load' \
    "229-B02 docblock: no longer calls the card layout the default on load"
  lacks_f "$B02_DOCBLOCK" "card layout's rendering and behavior are unchanged while the graph is off" \
    "229-B02 docblock: the Invariants line no longer frames the card layout as the graph-off state"

  # ...and says the graph is the default instead. Proximity, not a fixed
  # sentence: the wording is the implementer's.
  if matches "$(printf '%s' "$B02_DOCBLOCK" | tr '[:upper:]' '[:lower:]')" 'graph[^.]{0,40}\b(is|as|becomes)\b[^.]{0,20}default|graph view[^.]{0,25}default|default[^.]{0,25}graph view|graph-as-default|graph[- ]first'; then
    pass "229-B02 docblock: describes the graph view as the default"
  else
    fail "229-B02 docblock: does not describe the graph view as the default"
  fi

  # "every other 229-B02 clause stands unchanged" — spot-checked on clauses
  # this block has no business touching.
  for lit in \
    'round-rectangle' \
    'click-to-card' \
    'rankDir "TB"' \
    "The schema toggle's two-state semantics are untouched" \
    'No new external resources' \
    'v1 excludes search/filter'; do
    if matches_f "$B02_DOCBLOCK" "$lit"; then
      pass "229-B02 docblock: unrelated clause intact — $lit"
    else
      fail "229-B02 docblock: unrelated clause lost — $lit"
    fi
  done
fi

# =============================================================================
# Not mechanically checkable here — verified by the orchestrator at acceptance
# =============================================================================
# That the first paint of a parseable work-graph document actually shows the
# node-and-edge view with #doc hidden, that the toggle round-trips from that
# starting state, that a zero-node document still lands on the card/baseline
# view with the toggle hidden, and that a throw during the first graph build
# degrades rather than breaking the page all require executing the template
# against a live DOM with cytoscape loaded. This repo has no such harness
# (render.test.sh and workgraph-graph.test.sh document the same limit), so
# those are acceptance-verified in a browser instead of asserted here.

# --- Summary -----------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'graph-default.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'graph-default.test.sh: all assertions passed\n'
