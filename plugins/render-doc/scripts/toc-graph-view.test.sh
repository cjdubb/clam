#!/usr/bin/env bash
# toc-graph-view.test.sh — the U10 suite. It verifies one contract docblock in
# plugins/render-doc/assets/template.html, clause by clause:
#
#   - "Contract: 004-B25 hide TOC in graph view" (plan
#     004-graph-view-toc-and-plan-as-graph) — activateGraphView() hides the
#     #toc nav and deactivateGraphView() restores it, so the Contents pane is
#     never visible while the graph view is active and is fully functional
#     again when the card view returns; no new markup or external resources;
#     a failure while hiding or restoring never breaks rendering; the drawer
#     and the node panel are untouched.
#
# There is no DOM/browser harness in this repo (render.test.sh's header says
# so; workgraph-graph.test.sh, graph-default.test.sh, live-update.test.sh and
# node-panel.test.sh each repeat it for their own surface), so everything
# below is a structural/string assertion over template.html's source — the
# observable commitments the contract pins (which lifecycle function touches
# the TOC, the TOC's markup and ids, the degrade posture) and never
# implementation micro-structure such as helper or variable names. Whether
# the pane actually disappears on a toggle is acceptance-verified by the
# orchestrator in a browser; the clauses left to acceptance are listed at the
# foot of this file.
#
# Docblock stripping: the 004-B25 contract quotes nearly every string checked
# below ("#toc", "activateGraphView", "deactivateGraphView", "visibility"), so
# every code-facing check runs against a copy of template.html with ALL
# "/* Contract: ... */" docblocks removed — contract prose can then never
# satisfy a check meant for real code. Precedent: node-panel.test.sh,
# graph-default.test.sh, live-update.test.sh.
#
# Baseline-growth idiom: identifiers that already appear in the app script are
# pinned to a pre-B25 count the new code must push past, rather than merely
# asserted present. Every baseline below was measured against the app script
# AS OF THIS TEST WAVE, with docblocks stripped, and is stated inline in the
# failure message.
#
# EREs here use no backreferences: the system grep may be ugrep, which rejects
# \1 inside a bracket-quoted alternation.
#
# This suite starts no server and opens no port, so it has no port hygiene to
# do; it never reads or writes port 27183's registry or pidfile.

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
pass() { printf 'PASS  %s\n' "$*"; }

# --- Source extraction --------------------------------------------------------

strip_contract_docblocks() { # <file>
  awk '
    /^[[:space:]]*\/\* Contract:/ { instrip = 1 }
    instrip { if ($0 ~ /\*\//) { instrip = 0 } ; next }
    { print }
  ' "$1"
}

extract_docblock() { # <file> <marker substring>
  awk -v m="$2" '
    !started && index($0, m) { started = 1 }
    started { print; if (index($0, "*/")) exit }
  ' "$1"
}

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

TEMPLATE_CODE="$WORK/template.no-docblocks.html"
strip_contract_docblocks "$TEMPLATE" > "$TEMPLATE_CODE"

APP_JS="$WORK/app-script.js"
extract_app_script "$TEMPLATE_CODE" > "$APP_JS"

# --- Assertion helpers --------------------------------------------------------
# All of them grep a FILE, never a piped string: under `set -o pipefail` a
# `grep -q` exiting on its first match can SIGPIPE a still-writing printf and
# turn a pass into a spurious FAIL (the hazard live-update.test.sh documents).

countf() { # <ERE> <file>   (grep -c exits 1 on zero matches; that is not an error here)
  local n
  n="$(grep -cE -- "$1" "$2" 2> /dev/null)" || n=0
  printf '%s' "${n:-0}"
}

count() { # <ERE> -> matching line count in the app script
  countf "$1" "$APP_JS"
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

has_e() { # <file> <ERE> <label>
  if grep -qE -- "$2" "$1"; then pass "$3"; else fail "$3"; fi
}

lacks_e() { # <file> <ERE> <label>
  if grep -qE -- "$2" "$1"; then fail "$3"; else pass "$3"; fi
}

# A reference to the TOC nav ELEMENT (not to toc-list, not to the data-toc
# attribute): however the implementation looks it up.
TOC_LOOKUP='getElementById\(["'"'"']toc["'"'"']\)|querySelector\(["'"'"'][.#]?toc["'"'"']\)'
# Any visibility toggle: the two idioms already used for #doc and #graph-view.
VIS_TOGGLE='\.hidden[[:space:]]*=|style\.display[[:space:]]*='

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
# Contract: 004-B25 hide TOC in graph view
# =============================================================================

DOCBLOCK="$WORK/b25.docblock"
extract_docblock "$TEMPLATE" 'Contract: 004-B25 hide TOC in graph view' > "$DOCBLOCK"
if [ ! -s "$DOCBLOCK" ]; then
  fail "B25 docblock: not found in template.html (the contract must survive implementation)"
else
  pass "B25 docblock: present in template.html"
  lacks_f "$DOCBLOCK" 'DELIBERATELY UNIMPLEMENTED' \
    "B25 docblock: the scaffold's DELIBERATELY UNIMPLEMENTED note is removed"
  for clause in 'Behavior:' 'Inputs:' 'Outputs:' 'Errors:' 'Invariants:' 'Edge cases:'; do
    has_f "$DOCBLOCK" "$clause" "B25 docblock: the $clause clause is retained"
  done
fi

# --- Behavior + Inputs: activateGraphView() hides the #toc nav ----------------
# Today activateGraphView touches only #doc and #graph-view, and the app script
# looks the #toc NAV up nowhere at all (only #toc-list, in buildToc) — so both
# the lookup and the hide inside this function are new by construction.
ACTIVATE="$WORK/activate.js"
extract_function "$APP_JS" activateGraphView > "$ACTIVATE"
if [ ! -s "$ACTIVATE" ]; then
  fail "activate: activateGraphView could not be extracted (renamed?) — the Behavior clause cannot be checked"
else
  pass "activate: activateGraphView located"
  has_e "$ACTIVATE" "$TOC_LOOKUP" \
    "hide: activateGraphView reaches the #toc nav element (it touched only #doc/#graph-view at the baseline)"
  # Two visibility toggles at the baseline (#doc's style.display, #graph-view's
  # hidden); the TOC's is a third, in the same idiom.
  n="$(countf "$VIS_TOGGLE" "$ACTIVATE")"
  if [ "$n" -gt 2 ]; then
    pass "hide: activateGraphView gained a visibility toggle (now $n, baseline 2 — #doc and #graph-view)"
  else
    fail "hide: activateGraphView still toggles $n element(s), unchanged from the baseline of 2 (#doc, #graph-view) — the TOC is not hidden"
  fi
fi

DEACTIVATE="$WORK/deactivate.js"
extract_function "$APP_JS" deactivateGraphView > "$DEACTIVATE"
if [ ! -s "$DEACTIVATE" ]; then
  fail "deactivate: deactivateGraphView could not be extracted (renamed?) — the restore clause cannot be checked"
else
  pass "deactivate: deactivateGraphView located"
  has_e "$DEACTIVATE" "$TOC_LOOKUP" \
    "restore: deactivateGraphView reaches the #toc nav element to restore it"
  n="$(countf "$VIS_TOGGLE" "$DEACTIVATE")"
  if [ "$n" -gt 2 ]; then
    pass "restore: deactivateGraphView gained a visibility toggle (now $n, baseline 2 — #graph-view and #doc)"
  else
    fail "restore: deactivateGraphView still toggles $n element(s), unchanged from the baseline of 2 (#graph-view, #doc) — the TOC is not restored"
  fi
fi

# The lookup must have gained call sites at all (the whole-script view of the
# two checks above): zero today, at least two after the block.
toc_sites="$(count "$TOC_LOOKUP")"
if [ "${toc_sites:-0}" -ge 2 ]; then
  pass "lifecycle: the #toc nav is reached from at least two places (hide and restore) — now $toc_sites"
else
  fail "lifecycle: the #toc nav is reached from $toc_sites place(s), baseline 0, expected at least 2 (hide + restore)"
fi

# --- Invariant: the toggling is CONFINED to the graph lifecycle ---------------
# "visibility is toggled on the existing #toc element only", from the graph
# lifecycle. If render() or buildToc() also showed or hid the nav, a live
# update arriving while the graph is active could reveal it (Edge cases) and
# a non-work-graph docType could have its TOC hidden (Invariants).
for fn in render buildToc; do
  F="$WORK/$fn.js"
  extract_function "$APP_JS" "$fn" > "$F"
  if [ ! -s "$F" ]; then
    fail "confinement: $fn() could not be extracted — the re-render clause cannot be checked"
  else
    lacks_e "$F" "$TOC_LOOKUP" \
      "confinement: $fn() does not touch the #toc nav's visibility — a re-render while the graph is active leaves the TOC hidden"
  fi
done

# Every lookup of the nav lives inside one of the two lifecycle functions:
# their combined count accounts for the whole script's.
in_lifecycle=$(( $(countf "$TOC_LOOKUP" "$ACTIVATE") + $(countf "$TOC_LOOKUP" "$DEACTIVATE") ))
if [ "${toc_sites:-0}" -gt 0 ] && [ "$in_lifecycle" = "${toc_sites:-0}" ]; then
  pass "confinement: all $toc_sites #toc nav reference(s) live in activateGraphView/deactivateGraphView"
else
  fail "confinement: $in_lifecycle of $toc_sites #toc nav reference(s) live in the graph lifecycle — the rest could hide or reveal the pane outside the graph view"
fi

# --- Edge case: a graph-build failure degrades to a VISIBLE TOC ---------------
# activate's catch calls deactivateGraphView(), and the restore lives there
# (checked above), so the degraded card view shows its TOC. Both halves of
# that argument are asserted: the catch is unchanged, and the restore is in
# deactivate rather than in the toggle handler.
if [ -s "$ACTIVATE" ]; then
  has_f "$ACTIVATE" 'deactivateGraphView();' \
    "build-failure degrade: activateGraphView's catch still falls back through deactivateGraphView (which restores the TOC)"
  has_f "$ACTIVATE" 'state.graphOn = false' \
    "build-failure degrade: the build-failure path still leaves graphOn false"
fi

# --- Errors: a failure while hiding or restoring never breaks rendering -------
# Either idiom satisfies the clause: a try/catch around the toggle, or a
# null-guard on the looked-up element (the file's established "if (!x) return"
# posture). Asserted over the two lifecycle bodies together.
LIFECYCLE="$WORK/lifecycle.js"
cat "$ACTIVATE" "$DEACTIVATE" > "$LIFECYCLE" 2> /dev/null
if [ ! -s "$LIFECYCLE" ]; then
  fail "degrade: neither lifecycle function could be extracted — the Errors clause cannot be checked"
else
  if grep -qE 'try[[:space:]]*\{' "$LIFECYCLE" && grep -qE 'catch' "$LIFECYCLE"; then
    pass "degrade: the TOC toggle sits inside a guarded (try/catch) lifecycle body"
  elif grep -qE 'if[[:space:]]*\([[:space:]]*!|&&|\?\.' "$LIFECYCLE"; then
    pass "degrade: the looked-up #toc element is null-guarded before it is toggled"
  else
    fail "degrade: neither a try/catch nor a null-guard protects the TOC toggle — a missing #toc would throw and break rendering"
  fi
fi

# --- Outputs: no new markup, no new external resources -----------------------
# The TOC's content, ids and controls are byte-unchanged; only visibility
# toggles.
has_f "$TEMPLATE_CODE" '<nav class="toc" id="toc" aria-label="Table of contents">' \
  "TOC markup: the nav element is byte-unchanged"
has_f "$TEMPLATE_CODE" '<div class="toc-title">Contents</div>' \
  "TOC markup: the Contents title is byte-unchanged"
has_f "$TEMPLATE_CODE" '<ul id="toc-list"></ul>' \
  "TOC markup: the toc-list element is byte-unchanged"
has_f "$TEMPLATE_CODE" '<button class="btn" id="expand-all">Expand all</button>' \
  "TOC markup: the Expand all control is byte-unchanged"
has_f "$TEMPLATE_CODE" '<button class="btn" id="collapse-all">Collapse all</button>' \
  "TOC markup: the Collapse all control is byte-unchanged"
nav_count="$(grep -cF 'id="toc"' "$TEMPLATE_CODE" 2> /dev/null || true)"
if [ "${nav_count:-0}" = "1" ]; then
  pass "TOC markup: exactly one element carries id=\"toc\" (no second nav was added)"
else
  fail "TOC markup: $nav_count element(s) carry id=\"toc\" — expected exactly 1"
fi
pinned 'https?://' 0 "no new external resources: the app script introduces no absolute URL"

# --- Invariant: the TOC stays fully functional in the card view --------------
# Its behaviour is unchanged code: buildToc still fills #toc-list, the
# delegated click handler still runs, and the scroll-tracking observer still
# marks the active link. None of that may be removed or made conditional.
has_f "$APP_JS" 'document.getElementById("toc-list")' \
  "TOC function: the toc-list element is still populated/wired by id"
has_f "$APP_JS" 'document.getElementById("toc-list").addEventListener("click"' \
  "TOC function: the delegated toc-list click handler is still installed"
has_e "$APP_JS" 'data-toc' \
  "TOC function: the data-toc labelling the entries are built from is still written"
has_e "$APP_JS" 'classList\.(add|toggle)\("active"\)|className[^\n]*active' \
  "TOC function: scroll tracking still marks the active entry"
for ctl in 'expand-all' 'collapse-all'; do
  has_f "$APP_JS" "$ctl" "TOC function: the $ctl control is still wired"
done

# --- Invariant: the drawer and the node panel are untouched ------------------
pinned 'getElementById\("drawer"\)' 3 "feedback drawer: not newly manipulated"
has_f "$TEMPLATE_CODE" '<aside class="drawer" id="drawer" aria-label="Feedback panel">' \
  "feedback drawer: the drawer markup is byte-unchanged"
if [ -s "$DEACTIVATE" ]; then
  has_f "$DEACTIVATE" 'closeNodePanel();' \
    "node panel: deactivateGraphView still closes the node panel exactly as before"
fi
if [ -s "$ACTIVATE" ]; then
  lacks_e "$ACTIVATE" 'NodePanel|node-panel' \
    "node panel: activateGraphView does not newly touch the node panel"
fi

# --- Left to acceptance (no DOM harness) -------------------------------------
# Executing the lifecycle needs a live DOM plus cytoscape, which this repo has
# no harness for. Verified by the orchestrator in a browser instead:
#   - the Contents pane actually disappears when the graph opens and reappears
#     on return to cards, with the main column laid out sensibly meanwhile;
#   - after returning to cards, TOC links scroll, expand/collapse work, and
#     the active-entry highlight still tracks the scroll position;
#   - a work-graph doc rendered from file:// and a non-work-graph docType each
#     keep their TOC throughout (neither ever activates the graph view);
#   - a live update arriving while the graph is active leaves the TOC hidden;
#   - a graph-build failure lands on the card view WITH its TOC visible.

# --- Summary -----------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'toc-graph-view.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'toc-graph-view.test.sh: all assertions passed\n'
