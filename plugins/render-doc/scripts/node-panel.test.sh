#!/usr/bin/env bash
# node-panel.test.sh — the U07 suite. It verifies two contract docblocks in
# plugins/render-doc/assets/template.html, clause by clause, both from plan
# 003-followup-fixes:
#
#   - "Contract: 003-B19 graph node side panel" — tapping a graph node opens
#     a side panel carrying that node's full information without leaving the
#     graph; a panel control jumps to the node's card; close control, empty-
#     background tap and another node's tap all close it; the captured model
#     is extended with goal/notes text and generalized to a docType-agnostic
#     {nodes, edges, focus} shape.
#   - "Contract: 003-B22 cross-doc auto-linking" — on http(s)-served pages,
#     bare or backticked .md path tokens in prose become links to the
#     referenced file's /doc view; author-written links are held invariant;
#     file:// pages are unchanged; no client-side existence check is
#     attempted, so a bad reference clicks through to the server's own JSON
#     error.
#
# There is no DOM/browser harness in this repo (render.test.sh's own header
# says so; workgraph-graph.test.sh, graph-default.test.sh and live-update.
# test.sh each repeat it for their own surface), so everything below is a
# structural/string assertion over template.html's source — the observable
# commitments the contracts pin (element ids, route strings, the model shape,
# the functions the new code must reuse and the ones it must leave alone),
# never implementation micro-structure such as helper names. Whether a panel
# actually opens on a tap, and whether a linkified reference actually
# navigates, is acceptance-verified by the orchestrator in a browser; the
# clauses left to acceptance are listed explicitly at the foot of each part.
#
# The one clause that CAN be executed here is B22's Errors clause — that a
# reference to a missing file yields the server's normal JSON error rather
# than anything special-cased — so part C starts a real server on a
# kernel-drawn throwaway port and asks for a /doc view of a file that does
# not exist. That assertion is green today by construction: the clause is an
# "unchanged" commitment about the server, and B22's client-side half must
# not perturb it.
#
# Docblock stripping: both contracts quote nearly every string checked below
# ("node-panel" is the exception; "/doc", ".md", "goal", "notes", "nodes",
# "edges", "focus" are not), so every code-facing check runs against a copy
# of template.html with ALL "/* Contract: ... */" docblocks removed. Contract
# prose can then never satisfy a check meant for real code. Precedent:
# workgraph-graph.test.sh, graph-default.test.sh, live-update.test.sh.
#
# Baseline-growth idiom: identifiers that already appear in the app script
# are pinned to a pre-B19/pre-B22 count that the new code must push past
# (grew), rather than asserted merely present — the same device as
# workgraph-graph.test.sh's REUSE_BASELINE and live-update.test.sh's grew().
# Every baseline below was measured against the app script AS OF THIS TEST
# WAVE, with docblocks stripped.

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
TEMPLATE="$PLUGIN_DIR/assets/template.html"
SERVE="$PLUGIN_DIR/scripts/serve.py"

WORK="$(mktemp -d)"

# Port hygiene (the 003-B10 teardown contract server.test.sh carries): every
# port this suite serves on is kernel-drawn and never 27183, and both the
# pidfile and the registry file the server there writes are removed on exit.
# Nothing foreign is ever deleted.
SERVER_PIDS=()
PID_PATHS=()
cleanup() {
  for p in ${SERVER_PIDS[@]+"${SERVER_PIDS[@]}"}; do
    [ -n "$p" ] && kill "$p" 2> /dev/null
  done
  sleep 0.2
  for p in ${SERVER_PIDS[@]+"${SERVER_PIDS[@]}"}; do
    [ -n "$p" ] && kill -9 "$p" 2> /dev/null
  done
  for f in ${PID_PATHS[@]+"${PID_PATHS[@]}"}; do
    [ -n "$f" ] || continue
    rm -f "$f"
    port="${f##*/render-doc-serve-}"
    port="${port%.pid}"
    case "$port" in
      '' | *[![:digit:]]* | 27183) continue ;;
      *) rm -f "/tmp/render-doc-registry-$port.json" ;;
    esac
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

FAILURES=0
SKIPPED=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'PASS  %s\n' "$*"
}
skip() {
  printf 'skip: %s\n' "$*"
  SKIPPED=$((SKIPPED + 1))
}

# --- Source extraction --------------------------------------------------------

# Remove every "/* Contract: ... */" block comment: each starts on a line whose
# first non-space text is "/* Contract:" and ends on the first line containing
# "*/". Borrowed verbatim from graph-default.test.sh.
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

# The app IIFE script, located by content rather than line number (it moves as
# the implementation grows): the first bare <script> block containing
# "use strict". Borrowed from workgraph-graph.test.sh.
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

# A whole function body, from its "function <name>(" line to the closing brace
# at the same indent.
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

flatten() { tr '\n' ' ' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'; }

TEMPLATE_CODE="$WORK/template.no-docblocks.html"
strip_contract_docblocks "$TEMPLATE" > "$TEMPLATE_CODE"

APP_JS="$WORK/app-script.js"
extract_app_script "$TEMPLATE_CODE" > "$APP_JS"

# --- Assertion helpers --------------------------------------------------------
# All of them grep a FILE, never a piped string: under `set -o pipefail` a
# `grep -q` exiting on its first match can SIGPIPE a still-writing printf and
# turn a pass into a spurious FAIL (the hazard live-update.test.sh documents).

count() { # <ERE> -> matching line count in the app script
  grep -cE -- "$1" "$APP_JS" 2> /dev/null || true
}

present() { # <ERE> <label>   (for strings absent from the app script today)
  if grep -qE -- "$1" "$APP_JS"; then pass "$2"; else fail "$2"; fi
}

absent() { # <ERE> <label>
  if grep -qE -- "$1" "$APP_JS"; then fail "$2"; else pass "$2"; fi
}

grew() { # <ERE> <baseline> <label>
  local n
  n="$(count "$1")"
  if [ "${n:-0}" -gt "$2" ]; then
    pass "$3 (now $n line(s), baseline $2)"
  else
    fail "$3 — still $n line(s), unchanged from the baseline of $2"
  fi
}

pinned() { # <ERE> <pinned count> <label>
  local n
  n="$(count "$1")"
  if [ "${n:-0}" = "$2" ]; then
    pass "$3"
  else
    fail "$3 — expected $2 line(s) (pinned as of this test wave), found $n"
  fi
}

has_f() { # <file> <literal> <label>
  if grep -qF -- "$2" "$1"; then pass "$3"; else fail "$3"; fi
}

lacks_f() { # <file> <literal> <label>
  if grep -qF -- "$2" "$1"; then fail "$3"; else pass "$3"; fi
}

# --- Sanity: the strip and the extraction actually worked ---------------------
if grep -qF 'Contract:' "$TEMPLATE_CODE"; then
  fail "sanity: contract docblocks were not stripped from template.html"
else
  pass "sanity: contract docblocks stripped from template.html"
fi
if [ -s "$APP_JS" ]; then
  pass "sanity: app script extracted from template.html"
else
  fail "sanity: app script could not be extracted (the \"use strict\" anchor moved?) — no clause below can be checked"
fi

# =============================================================================
# PART A — Contract: 003-B19 graph node side panel
# =============================================================================

B19_DOCBLOCK="$WORK/b19.docblock"
extract_docblock "$TEMPLATE" 'Contract: 003-B19 graph node side panel' > "$B19_DOCBLOCK"
if [ ! -s "$B19_DOCBLOCK" ]; then
  fail "B19 docblock: not found in template.html (the contract must survive implementation)"
else
  pass "B19 docblock: present in template.html"
  lacks_f "$B19_DOCBLOCK" 'DELIBERATELY UNIMPLEMENTED' \
    "B19 docblock: the scaffold's DELIBERATELY UNIMPLEMENTED note is removed"
  has_f "$B19_DOCBLOCK" 'Behavior:' "B19 docblock: the contract clauses are retained"
fi

# --- Behavior: a side panel element exists, exactly one of it ----------------
# "node-panel" appears nowhere in template.html today — neither in code nor in
# either contract docblock — so its presence is new by construction. One
# element, not one per tap: the same-node-twice edge case forbids duplicates,
# and a single container in the markup is what makes that structural.
panel_markup="$(grep -cF 'id="node-panel"' "$TEMPLATE_CODE" 2> /dev/null || true)"
if [ "${panel_markup:-0}" = "1" ]; then
  pass "panel markup: exactly one element carries id=\"node-panel\""
elif [ "${panel_markup:-0}" = "0" ]; then
  fail "panel markup: no element with id=\"node-panel\" in template.html"
else
  fail "panel markup: $panel_markup elements carry id=\"node-panel\" — a second panel container makes duplicate panels possible"
fi
present 'getElementById\((["'"'"'])node-panel\1\)' \
  "panel wiring: the app script looks the panel up by id"

# --- Behavior: the tap handler opens the panel INSTEAD of leaving the graph --
# The pre-B19 node-tap handler unconditionally deactivates the graph and
# switches to the card view (click-to-card, 229-B02). B19 replaces that with
# opening the panel "WITHOUT leaving the graph or altering the current view
# mode", so the node-tap handler must no longer deactivate the graph.
NODE_TAP="$WORK/node-tap.js"
awk '
  index($0, "cy.on(") && (index($0, "\"node\"") || index($0, "'"'"'node'"'"'")) { intap = 1 }
  intap { print; if ($0 ~ /^[[:space:]]*\}\);[[:space:]]*$/) exit }
' "$APP_JS" > "$NODE_TAP"
if [ ! -s "$NODE_TAP" ]; then
  fail "node tap: the cytoscape node-tap handler could not be located (anchor moved?)"
else
  pass "node tap: the cytoscape node-tap handler located"
  lacks_f "$NODE_TAP" 'deactivateGraphView()' \
    "node tap: tapping a node no longer deactivates the graph view (the panel opens in place)"
  lacks_f "$NODE_TAP" 'state.graphOn = false' \
    "node tap: tapping a node no longer alters the current view mode"
  if grep -qE 'panel|Panel' "$NODE_TAP"; then
    pass "node tap: the handler opens the node panel"
  else
    fail "node tap: the handler does not reference the panel"
  fi
fi

# --- Behavior: the panel carries the node's full information -----------------
# id, title, status with reason, goal, parent, deps, notes. statusReason,
# goalNodes/notesNodes and deps already appear in the card path, so each is
# pinned to its pre-B19 count and must grow; the panel is a second consumer.
grew 'statusReason' 5 "panel content: statusReason gained a consumer (status with its reason)"
grew '\bgoal\b|goalNodes' 7 "panel content: the node's goal text gained a consumer"
grew '\bnotes\b|notesNodes' 6 "panel content: the node's notes text gained a consumer"
grew '\bdeps\b' 9 "panel content: the node's deps gained a consumer"
grew '\bparent\b' 10 "panel content: the node's parent gained a consumer"

# --- Behavior: a panel control jumps to the node's card ----------------------
# "it deactivates the graph exactly as the existing toggle does and scrolls to
# the node's section with the existing jump highlight" — so both the
# deactivate path and the existing wg-jump-highlight/scrollIntoView treatment
# must be reached from a second place.
grew 'wg-jump-highlight' 2 "jump control: the existing jump highlight is applied from a second call site"
grew 'scrollIntoView' 1 "jump control: the node's section is scrolled into view from a second call site"
grew 'deactivateGraphView\(' 5 "jump control: the graph is deactivated exactly as the toggle does"

# --- Behavior: close control, empty-background tap, another node's tap -------
present '(id|getElementById\(["'"'"'])[^"'"'"']*panel-close' \
  "close control: the panel carries a close control (panel-close)"
# A core tap handler (no "node" selector) is how cytoscape reports a tap on
# empty background; there is exactly one cy.on( call today (the node tap).
grew 'cy\.on\(|cyInstance\.on\(' 1 "tap-away: a second cytoscape tap handler is registered (empty background closes the panel)"

# --- Inputs: the captured model is EXTENDED with goal and notes text ---------
CAPTURE="$WORK/capture.js"
extract_function "$APP_JS" captureWorkGraphModel > "$CAPTURE"
if [ ! -s "$CAPTURE" ]; then
  fail "model: captureWorkGraphModel could not be extracted (renamed?) — the Inputs clauses cannot be checked"
else
  pass "model: captureWorkGraphModel located"
  if grep -qE 'goal' "$CAPTURE"; then
    pass "model: the captured node payload retains the node's goal text"
  else
    fail "model: the captured node payload does not retain goal text"
  fi
  if grep -qE 'notes' "$CAPTURE"; then
    pass "model: the captured node payload retains the node's notes text"
  else
    fail "model: the captured node payload does not retain notes text"
  fi

  # --- Inputs: a GENERIC {nodes, edges, focus} model ------------------------
  # The pre-B19 model is work-graph-specific by shape as well as by content:
  # nodesById / order / effectiveParent / focusId. The contract requires the
  # shape the graph build and the panel consume to be {nodes, edges, focus},
  # so a second document type can supply its own model. Edges in particular
  # must be part of the MODEL rather than derived inside the graph build from
  # effectiveParent and each node's deps.
  for key in 'nodes:' 'edges:' 'focus:'; do
    if grep -qE -- "$key" "$CAPTURE"; then
      pass "model shape: the returned model carries a '$key' property"
    else
      fail "model shape: the returned model has no '$key' property — still the work-graph-specific shape"
    fi
  done
fi

GRAPH_BUILD="$WORK/graph-build.js"
extract_function "$APP_JS" renderWorkGraphGraphView > "$GRAPH_BUILD"
if [ ! -s "$GRAPH_BUILD" ]; then
  fail "graph build: renderWorkGraphGraphView could not be extracted — the generic-model clause cannot be checked"
else
  pass "graph build: the graph build function located"
  if grep -qE '\.edges\b' "$GRAPH_BUILD"; then
    pass "graph build: edges come from the model rather than being rederived from work-graph fields"
  else
    fail "graph build: no model .edges consumption — the build still derives edges from effectiveParent/deps itself"
  fi
  lacks_f "$GRAPH_BUILD" 'effectiveParent' \
    "graph build: the build no longer keys on the work-graph-specific effectiveParent field"
  lacks_f "$GRAPH_BUILD" 'WG_FOCUS_RE' \
    "graph build: the build no longer keys on work-graph focus parsing"
fi

# --- Outputs: panel markup rendered from model data only, HTML-escaped -------
# The app script assigns innerHTML three times: marked's own output into the
# render scratch element, the split-view panel's Notes value (whitelist-
# sanitized in wgFieldHtml before assignment), and the panel's hydrated
# linked-doc section (marked's output again). Node data must never reach the
# panel unsanitized; the guards below pin the two panel paths to their
# sanitizer and to marked respectively.
pinned 'innerHTML[[:space:]]*=' 4 "escaping: innerHTML assignments limited to marked output, the sanitized Notes value, and the static legend markup"
pinned 'nv\.innerHTML = node\.notesHtml' 1 "escaping: the Notes assignment consumes only the wgFieldHtml-sanitized value"
pinned 'content\.innerHTML = marked\.parse' 1 "escaping: the hydrated section is marked's own output, nothing hand-built"
pinned 'https?://' 0 "no new external resources: the app script introduces no absolute URL"

# --- Errors: opening the panel degrades to today's tap-to-card behavior ------
# "any failure while opening the panel degrades to today's tap-to-card
# behavior rather than breaking the graph" — a try/catch must guard the open
# path, and its catch must still be able to reach the card.
panel_guard="$(awk '
  /try[[:space:]]*\{/ { buf = $0; intry = 1; next }
  intry { buf = buf "\n" $0 }
  intry && /catch/ {
    if (buf ~ /[Pp]anel/) found = 1
    intry = 0
  }
  END { if (found) print "FOUND"; else print "NOTFOUND" }
' "$APP_JS")"
if [ "$panel_guard" = "FOUND" ]; then
  pass "panel errors: opening the panel is wrapped in try/catch"
else
  fail "panel errors: no try/catch found around the panel-open path"
fi

# --- Invariants: the card view stays reachable via the existing toggle -------
TOGGLE="$WORK/graph-toggle.js"
awk '
  index($0, "graph-toggle") && index($0, "addEventListener") { ing = 1 }
  ing { print; if ($0 ~ /^[[:space:]]*\}\);[[:space:]]*$/) exit }
' "$APP_JS" > "$TOGGLE"
if [ ! -s "$TOGGLE" ]; then
  # The toggle may be wired through a named handler rather than inline; the
  # invariant is then checked by the presence of both branches below.
  skip "toggle: the graph-toggle listener could not be located inline — checking the toggle branches instead"
else
  pass "toggle: the graph-toggle listener located"
fi
has_f "$APP_JS" 'deactivateGraphView();' "toggle invariant: the card view is still reachable by deactivating the graph"
has_f "$APP_JS" 'activateGraphView();' "toggle invariant: the graph view is still reachable by activating the graph"

# --- Invariant: the graph-build-failure fallback is unchanged ----------------
ACTIVATE="$(extract_function "$APP_JS" activateGraphView | flatten)"
ACTIVATE_BASELINE='function activateGraphView() { var docEl = document.getElementById("doc"); var container = document.getElementById("graph-view"); docEl.style.display = "none"; container.hidden = false; try { if (cyInstance) { cyInstance.destroy(); cyInstance = null; } cyInstance = renderWorkGraphGraphView(); state.graphOn = true; } catch (err) { deactivateGraphView(); state.graphOn = false; } }'
case "$ACTIVATE" in
  *'catch (err) { deactivateGraphView(); state.graphOn = false; }'*)
    pass "fallback invariant: the graph-build-failure catch still falls back to the card view with graphOn false" ;;
  '') fail "fallback invariant: activateGraphView could not be extracted" ;;
  *) fail "fallback invariant: activateGraphView's build-failure catch changed (was: ...$ACTIVATE_BASELINE)" ;;
esac

# --- Invariant: a live-update re-render closes any open panel, never errors --
# render() rebuilds the sections and recaptures the model on every update, so
# the panel — which holds references into the old DOM — has to be closed from
# the render path. A panel-close reference inside render() is what makes that
# structural.
RENDER_FN="$WORK/render.js"
extract_function "$APP_JS" render > "$RENDER_FN"
if [ ! -s "$RENDER_FN" ]; then
  fail "re-render: render() could not be extracted — the panel-close-on-rerender clause cannot be checked"
else
  pass "re-render: render() located"
  if grep -qE 'panel|Panel' "$RENDER_FN"; then
    pass "re-render: render() closes any open panel before/while repainting"
  else
    fail "re-render: render() never touches the panel — an open panel would survive a live update holding stale node refs"
  fi
fi

# --- Invariant: the feedback aside keeps its markup, ids and behavior --------
has_f "$TEMPLATE_CODE" '<aside class="drawer" id="drawer" aria-label="Feedback panel">' \
  "feedback aside: the drawer markup is byte-unchanged"
for id in 'id="drawer-head"' 'id="drawer-close"' 'id="drawer-list"' 'id="copy-all"' 'id="clear-all"'; do
  case "$id" in
    'id="drawer-head"') continue ;; # the head is a class, not an id — skip
  esac
  has_f "$TEMPLATE_CODE" "$id" "feedback aside: $id still present"
done
pinned 'getElementById\("drawer"\)' 3 "feedback aside: the drawer is not newly manipulated"

# --- Edge case: very long notes scroll inside the panel, not the page --------
if grep -qE '#node-panel|\.node-panel' "$TEMPLATE_CODE"; then
  pass "panel style: the panel has its own style rules"
  if grep -A 12 -E '#node-panel|\.node-panel' "$TEMPLATE_CODE" | grep -qE 'overflow(-y)?[[:space:]]*:'; then
    pass "panel style: the panel scrolls its own content (overflow rule present)"
  else
    fail "panel style: no overflow rule near the panel's style rules — long notes would grow the page"
  fi
else
  fail "panel style: no #node-panel/.node-panel style rules found"
fi

# --- Left to acceptance (no DOM harness) -------------------------------------
# Executing the panel needs a live DOM plus cytoscape, which this repo has no
# harness for. Verified by the orchestrator in a browser instead:
#   - a tap actually paints the panel with that node's rows, and the graph
#     stays visible behind it;
#   - the jump control actually lands on the node's card with the highlight;
#   - tapping empty background and tapping a second node actually close /
#     re-open;
#   - a node whose model entry has no goal or notes renders without those
#     rows and without throwing;
#   - a re-render arriving while a dropped node's panel is open closes it
#     cleanly;
#   - tapping the same node twice leaves exactly one panel.

# =============================================================================
# PART B — Contract: 003-B22 cross-doc auto-linking (client side)
# =============================================================================

B22_DOCBLOCK="$WORK/b22.docblock"
extract_docblock "$TEMPLATE" 'Contract: 003-B22 cross-doc auto-linking' > "$B22_DOCBLOCK"
if [ ! -s "$B22_DOCBLOCK" ]; then
  fail "B22 docblock: not found in template.html (the contract must survive implementation)"
else
  pass "B22 docblock: present in template.html"
  lacks_f "$B22_DOCBLOCK" 'DELIBERATELY UNIMPLEMENTED' \
    "B22 docblock: the scaffold's DELIBERATELY UNIMPLEMENTED note is removed"
  has_f "$B22_DOCBLOCK" 'Behavior:' "B22 docblock: the contract clauses are retained"
fi

# --- Behavior: a linkify pass exists and matches .md path tokens -------------
# A literal "\.md" (the escaped form a JS regex uses) appears nowhere in the
# app script today: the only two ".md" occurrences are unescaped, inside
# ordinary prose comments. So this is new by construction.
present '\\\.md' "linkify: a .md path token pattern is present in the app script"
present '"/doc|'"'"'/doc' "linkify: the emitted href targets the server's /doc view"
grew 'encodeURI' 2 "linkify: the resolved target path is percent-encoded"

# --- Behavior: bare AND backticked tokens; text nodes and inline code --------
# Bare tokens live in text nodes; backticked ones become <code> elements. The
# contract's Inputs clause names both, so both have to be walked.
grew 'createTreeWalker|SHOW_TEXT' 4 "linkify: the pass walks text nodes"
present '(["'"'"'`])code\1|querySelectorAll\([^)]*code' \
  "linkify: inline-code spans are considered as well as bare text"

# --- Behavior: relative references resolve against the doc's own directory ---
grew 'sourcePath' 8 "linkify: relative references resolve against the source document's own path"
# A quoted ".." token appears nowhere in the app script today, so the lexical
# resolver's own segment handling is new by construction (a bare \.\. would
# match ordinary comment ellipses).
present '"\.\."|'"'"'\.\.'"'"'' "linkify: ../ traversal is resolved lexically"

# --- Invariant: author-written markdown links are held INVARIANT -------------
# "a reference already inside an anchor is never re-wrapped" — the walk has to
# reject nodes with an anchor ancestor. closest("a") is the idiomatic test;
# a tagName check is equally acceptable.
# The annotation composer already calls closest("a") once, so this is a growth
# check rather than a presence check.
grew 'closest\((["'"'"'])a\1\)|tagName[^\n]*===[^\n]*(["'"'"'])A\2|nodeName[^\n]*(["'"'"'])A\3' 1 \
  "author links: the pass skips references already inside an anchor"

# --- Edge case: fenced code BLOCKS are left alone ----------------------------
# "pre" appears once today (the fatal-error renderer's createElement("pre")),
# so a second occurrence is the exclusion this clause asks for.
grew '(["'"'"'`])pre\1|closest\((["'"'"'])pre\2' 1 \
  "code blocks: <pre> content is excluded from linkification"

# --- Behavior: http(s) only; file:// pages are unchanged ---------------------
# servedOverNetwork is the file's existing http(s) discriminator (topbar-nav
# introduced it); SAVE_ENABLED and a direct location.protocol test are equally
# valid. Whichever is used, the guard count must grow: the linkify call is a
# new consumer of the same detection.
grew 'servedOverNetwork|SAVE_ENABLED|location\.protocol' 7 \
  "file:// guard: linkification is gated on the page being http(s)-served"

# --- Errors: NO client-side existence check ----------------------------------
# A client cannot stat, and the contract records the trade-off explicitly: a
# bad reference links anyway. So the page must gain no lookup route — the
# server's document inventory (/docs.json) in particular must stay uncalled,
# and the only routes the page requests remain /annotate and /raw. (/doc
# appears as an anchor href, never as a request.)
pinned '/docs\.json|/health' 0 "no existence check: the page calls no inventory or health route"
# Baseline 2 (/annotate POST, /raw live-update poll) plus the split-view
# panel's /raw hydration fetch — still none issued by linkification itself.
pinned 'fetch\(' 3 "no existence check: no new fetch is introduced by linkification"
absent 'method:[[:space:]]*(["'"'"'])HEAD\1' "no existence check: no HEAD probe of a link target"

# --- Errors: linkification never breaks rendering ----------------------------
linkify_guard="$(awk '
  /try[[:space:]]*\{/ { buf = $0; intry = 1; next }
  intry { buf = buf "\n" $0 }
  intry && /catch/ {
    if (buf ~ /[Ll]inkif|\\\.md|"\/doc/) found = 1
    intry = 0
  }
  END { if (found) print "FOUND"; else print "NOTFOUND" }
' "$APP_JS")"
if [ "$linkify_guard" = "FOUND" ]; then
  pass "linkify errors: the linkify pass is wrapped in try/catch (a failure leaves the page rendered)"
else
  fail "linkify errors: no try/catch found around the linkify pass"
fi

# --- Invariants: the render pipeline's existing stages are untouched ---------
# The linkify pass is an ADDITION to render(), after the DOM exists; every
# existing stage must still be called, in its existing order. Running it from
# render() is also what makes a live-update re-render idempotent: the DOM is
# rebuilt from markdown each time, so linkification is re-applied to fresh
# text and can never nest anchors.
if [ -s "$RENDER_FN" ]; then
  prev=0
  ok=1
  for stage in 'buildHero(' 'sectionize(' 'highlightTags(' 'captureWorkGraphModel(' 'buildToc(' 'attachAnnotators(' 'updateChrome('; do
    line="$(grep -nF -- "$stage" "$RENDER_FN" | head -1 | cut -d: -f1)"
    if [ -z "$line" ]; then
      fail "pipeline invariant: render() no longer calls $stage"
      ok=0
    elif [ "$line" -lt "$prev" ]; then
      fail "pipeline invariant: render() calls $stage out of its established order"
      ok=0
    else
      prev="$line"
    fi
  done
  [ "$ok" = "1" ] && pass "pipeline invariant: render()'s existing stages all still run, in order"

  if grep -qE '[Ll]inkif' "$RENDER_FN"; then
    pass "idempotence: linkification runs from render(), so every re-render re-applies it to a freshly built DOM"
  else
    fail "idempotence: render() does not run the linkify pass — a live-update re-render would drop or nest links"
  fi
fi

# --- Invariant: the graph container and annotation selectors are untouched ---
BLOCK_SEL_BASELINE='p, li, blockquote, tr, .tl-entry, .wg-summary'
current_block_sel="$(grep -oE 'var BLOCK_SEL = "[^"]+"' "$TEMPLATE_CODE" | head -1 | sed -e 's/^var BLOCK_SEL = "//' -e 's/"$//')"
if [ "$current_block_sel" = "$BLOCK_SEL_BASELINE" ]; then
  pass "annotation invariant: BLOCK_SEL unchanged (linkification adds no annotatable block)"
else
  fail "annotation invariant: BLOCK_SEL changed ('$BLOCK_SEL_BASELINE' -> '$current_block_sel')"
fi

# --- Left to acceptance (no DOM harness) -------------------------------------
# Verified by the orchestrator in a browser instead:
#   - a bare token, a backticked token, an absolute path and a ../ relative
#     path each actually navigate to the right /doc view;
#   - an author-written [text](path.md) link's href is byte-unchanged;
#   - a token containing a space is left as plain text;
#   - a path referenced twice links at both occurrences;
#   - a file:// page's rendered output is byte-identical to today's;
#   - a live-update re-render produces no nested or duplicated anchors.

# =============================================================================
# PART C — Contract: 003-B22, Errors clause, server side (executable)
# =============================================================================
# "a reference to a missing or out-of-scope file links anyway and clicks
# through to the server's normal JSON error". This is the one B22 clause that
# can be executed without a DOM: ask a real server for the /doc view of a
# file that does not exist and check the answer is the ordinary JSON error.

MISSING_TOOL=0
for tool in python3 curl; do
  command -v "$tool" > /dev/null 2>&1 || MISSING_TOOL=1
done

if [ "$MISSING_TOOL" -ne 0 ]; then
  skip "click-through: python3/curl unavailable — the server-side B22 Errors clause cannot be executed"
else
  free_port() {
    local p
    while :; do
      p="$(python3 -c "import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()")"
      [ -n "$p" ] || return 1
      [ "$p" != "27183" ] && break
    done
    printf '%s' "$p"
  }

  PORT="$(free_port)"
  PIDFILE="/tmp/render-doc-serve-$PORT.pid"
  if [ -e "$PIDFILE" ]; then
    # Bounded retry rather than clobbering somebody else's state.
    PORT="$(free_port)"
    PIDFILE="/tmp/render-doc-serve-$PORT.pid"
  fi

  if [ -e "$PIDFILE" ]; then
    fail "click-through: drew a port whose pidfile already exists twice running — refusing to clobber $PIDFILE"
  else
    RENDER_DOC_PORT="$PORT" python3 "$SERVE" > "$WORK/srv.stdout" 2> "$WORK/srv.stderr" &
    SERVER_PIDS+=($!)
    PID_PATHS+=("$PIDFILE")

    healthy=1
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
      if curl -sf --max-time 1 "http://127.0.0.1:$PORT/health" > /dev/null 2>&1; then
        healthy=0
        break
      fi
      sleep 0.25
    done

    if [ "$healthy" -ne 0 ]; then
      fail "click-through: the test server did not become healthy on port $PORT"
    else
      pass "click-through: test server healthy on port $PORT"
      BODY="$WORK/body"
      MISSING_DOC="$REPO_ROOT/plans/no-such-document-$$-$RANDOM.md"
      code="$(curl -s --max-time 15 -o "$BODY" -w '%{http_code}' \
        "http://127.0.0.1:$PORT/doc$MISSING_DOC" 2> /dev/null)"
      code="${code:-000}"
      if [ "$code" = "404" ]; then
        pass "click-through: a /doc view of a nonexistent reference answers 404 (the server's normal error)"
      else
        fail "click-through: expected 404 for a nonexistent /doc target, got $code"
      fi
      err_msg="$(python3 - "$BODY" << 'PY' 2> /dev/null
import json, sys
try:
    with open(sys.argv[1]) as fh:
        print(json.load(fh).get("error", ""))
except Exception:
    print("")
PY
)"
      if [ -n "$err_msg" ]; then
        pass "click-through: the response body is the server's normal JSON error (\"$err_msg\")"
      else
        fail "click-through: the response body is not a JSON {\"error\": ...} payload"
      fi
    fi
  fi
fi

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'node-panel.test.sh: %d check(s) skipped\n' "$SKIPPED" >&2
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'node-panel.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'node-panel.test.sh: all assertions passed\n'
