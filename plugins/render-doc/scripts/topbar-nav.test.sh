#!/usr/bin/env bash
# topbar-nav.test.sh — verifies the docblock "Contract: 002-B05 doc-page topbar
# nav" (plan 002-discovery-landing-dns) in
# plugins/render-doc/assets/template.html clause by clause: an http-served
# document page grows two plain links at the start of its topbar — "Index" to
# the server's index and "Worktree" to the resolver that redirects to the
# owning worktree's landing page — while a page opened over file:// grows
# neither and every existing topbar control keeps its behaviour and place.
#
# There is no DOM/browser harness in this repo (render.test.sh's header says
# so, live-update.test.sh and graph-default.test.sh repeat it for the template's
# other client-side blocks), so these are structural/string assertions over
# template.html's source, reaching only what the contract pins as observable:
# the two link targets, the protocol gate they share with the annotation
# client, the guard that drops the second link when there is no source path,
# and the controls the contract declares untouched. Whether the links actually
# appear, sit first, and survive a live-update repaint is acceptance-verified
# in a browser.
#
# SCOPE, following live-update.test.sh's reasoning: checks run over the whole
# app script rather than over one function's body. Building the links inline at
# boot, in a helper, or from a template string are all reasonable factorings
# that the contract neither requires nor forbids, and a body-scoped grep would
# fail one of them for no defect. So each clause is asserted in the form that
# survives any factoring:
#   - PRESENT: strings that appear NOWHERE in the template today (/project,
#     Worktree, the quoted "Index" label, encodeURIComponent), so their
#     presence is new by construction.
#   - GREW: identifiers that already appear (sourcePath, the protocol gate, the
#     topbar container), pinned to a pre-B05 count the new code must push past.
#   - PINNED: the contract's "untouched" list (the three existing controls, the
#     docType branches, the fetch call sites), asserted as counts that must NOT
#     change — which holds no matter where the new code lives.
#
# Every check runs against a copy of template.html with ALL "/* Contract: ... */"
# docblocks removed: the 002-B05 docblock quotes nearly every string checked
# below (/project/for, Index, Worktree, encodeURIComponent, topbar-actions), so
# without the strip the contract prose would satisfy checks meant for real code.
# Precedent: workgraph-graph.test.sh, live-update.test.sh, graph-default.test.sh.
#
# Marker note: plan-002 markers are plan-qualified. template.html ALSO carries
# bare "Contract: B05" and "Contract: B06" docblocks from an earlier plan, plus
# "Contract: 229-B02", all meaning something else entirely — so every marker
# check here uses the full "Contract: 002-B05 doc-page topbar nav" text and
# nothing greps the bare form.
#
# Out of scope, because another suite owns it: the page the Worktree link
# points AT (landing-page.test.sh), the live-update poller whose repaints must
# not duplicate the links (live-update.test.sh), and the prose describing the
# navigation (landing-docs.test.sh).

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

# The app IIFE script, located by content rather than line number: the first
# bare <script> block containing "use strict". Borrowed from
# workgraph-graph.test.sh via live-update.test.sh.
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

# The topbar markup itself, so a markup-first implementation can be read the
# same way a script-first one is.
extract_topbar() { # <file>
  awk '
    /<header class="topbar">/ { p = 1 }
    p { print }
    p && /<\/header>/ { exit }
  ' "$1"
}

TEMPLATE_CODE="$WORK/template.no-docblocks.html"
strip_contract_docblocks "$TEMPLATE" > "$TEMPLATE_CODE"

APP_JS="$WORK/app-script.js"
extract_app_script "$TEMPLATE_CODE" > "$APP_JS"

TOPBAR="$WORK/topbar.html"
extract_topbar "$TEMPLATE_CODE" > "$TOPBAR"

# --- Assertion helpers --------------------------------------------------------
# All of them grep a FILE rather than a piped string: under `set -o pipefail` a
# `grep -q` that exits on its first match closes the pipe beneath a still-
# writing printf, and the SIGPIPE becomes the pipeline's status — a false FAIL
# on any haystack larger than the pipe buffer, which template.html is.

count() { # <ERE> <file>
  grep -cE -- "$1" "$2" 2> /dev/null || true
}

present() { # <ERE> <label>   (for strings absent from the template pre-002-B05)
  if grep -qE -- "$1" "$APP_JS"; then pass "$2"; else fail "$2"; fi
}

present_anywhere() { # <ERE> <label>  (markup or script — the contract allows both)
  if grep -qE -- "$1" "$TEMPLATE_CODE"; then pass "$2"; else fail "$2"; fi
}

grew() { # <ERE> <pre-002-B05 baseline> <label>
  local n
  n="$(count "$1" "$APP_JS")"
  if [ "${n:-0}" -gt "$2" ]; then
    pass "$3 (now $n line(s), pre-002-B05 baseline $2)"
  else
    fail "$3 — still $n line(s), unchanged from the pre-002-B05 baseline of $2"
  fi
}

pinned() { # <ERE> <pinned count> <label>
  local n
  n="$(count "$1" "$APP_JS")"
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
# Every check below depends on them, so a strip that silently stopped matching
# must be loud rather than quietly permissive.

if grep -qF 'Contract:' "$TEMPLATE_CODE"; then
  fail "sanity: contract docblocks were not stripped from template.html (strip helper needs adjusting)"
else
  pass "sanity: contract docblocks stripped from template.html"
fi
if grep -qF 'Contract: 002-B05 doc-page topbar nav' "$TEMPLATE"; then
  pass "sanity: the 002-B05 contract docblock is present to be stripped"
else
  fail "sanity: no 'Contract: 002-B05 doc-page topbar nav' docblock in template.html — nothing proves the strip ran"
fi
if [ -s "$APP_JS" ]; then
  pass "sanity: app script extracted from template.html"
else
  fail "sanity: app script could not be extracted (the \"use strict\" anchor moved?) — no clause below can be checked"
fi
if [ -s "$TOPBAR" ]; then
  pass "sanity: topbar markup extracted from template.html"
else
  fail "sanity: the topbar markup could not be extracted (the header anchor moved?)"
fi

# =============================================================================
# Behavior: the two link targets exist at all
# =============================================================================

present_anywhere '/project/for' \
  "Worktree link: the page points at the /project/for resolver"
present_anywhere '/project/for[^"'"'"']*path=' \
  "Worktree link: the resolver is called with its path query parameter"
present_anywhere '"Worktree"|>[[:space:]]*Worktree|Worktree[[:space:]]*<' \
  "Worktree link: it is labelled \"Worktree\""
present_anywhere '"Index"|>[[:space:]]*Index[[:space:]]*<' \
  "Index link: it is labelled \"Index\""
present_anywhere 'href[[:space:]]*=[[:space:]]*"/"|"href",[[:space:]]*"/"|href="/"' \
  "Index link: it points at the server's index (\"/\")"

# Edge case: a source path carrying spaces or quotes has to survive being put
# in a query parameter, which is what encodeURIComponent (not encodeURI) is for
# — encodeURI would leave &, ? and # to be read as query syntax.
present 'encodeURIComponent' \
  "Worktree link: the source path is encoded with encodeURIComponent"

# Inputs: the link is built from the embedded sourcePath, and the second link
# is dropped when there is nothing to point at.
grew 'sourcePath' 6 "Worktree link: the target is built from the embedded sourcePath"
# The guard, in the forms a guard actually takes — deliberately NOT matching a
# bare "(sourcePath)", which the href expression itself would satisfy and which
# would make this check vacuous.
grew 'if[[:space:]]*\([^)]*sourcePath|![[:space:]]*sourcePath|sourcePath[[:space:]]*(&&|\|\||\?|===|!==|==|!=|\.length)' 2 \
  "empty sourcePath: a guard decides whether the Worktree link is rendered at all"

# =============================================================================
# Behavior: the links are gated on the page being served over http(s), so a
# file:// page renders neither
# =============================================================================

grew 'SAVE_ENABLED|location\.protocol' 4 \
  "file:// guard: the links key on the page's protocol, as the annotation client does"
# The contract names both schemes; the existing SAVE_ENABLED flag is http-only,
# so reusing it verbatim would leave an https-served page without its links.
present 'https:' "file:// guard: https: counts as served, not as a local file"
has_f "$APP_JS" 'var SAVE_ENABLED = window.location.protocol === "http:";' \
  "file:// guard: the existing protocol detection is byte-unchanged"

# =============================================================================
# Behavior: the links come FIRST in .topbar-actions, before the doctype pill.
# Markup-first and script-first implementations are both legitimate, so the
# clause is checked in whichever form the implementation took.
# =============================================================================

topbar_anchor_line="$(grep -nE '<a[[:space:]]' "$TOPBAR" | head -1 | cut -d: -f1)"
pill_line="$(grep -nF 'id="doctype-pill"' "$TOPBAR" | head -1 | cut -d: -f1)"
prepend_n="$(count 'prepend\(|insertBefore\(|insertAdjacentHTML\(|firstChild|\.before\(' "$APP_JS")"
container_n="$(count 'topbar-actions|doctype-pill' "$APP_JS")"

if [ -z "$pill_line" ]; then
  fail "link position: the doctype pill could not be located in the topbar markup"
elif [ -n "$topbar_anchor_line" ]; then
  # Markup-first: the anchors are written into the container, so their place is
  # readable straight off the source.
  if [ "$topbar_anchor_line" -lt "$pill_line" ]; then
    pass "link position: the topbar's links are markup, placed before the doctype pill"
  else
    fail "link position: a topbar link at line $topbar_anchor_line follows the doctype pill at line $pill_line"
  fi
elif [ "${prepend_n:-0}" -gt 13 ] && [ "${container_n:-0}" -gt 1 ]; then
  # Script-first: the code has to reach the container the contract names and
  # insert at its front rather than append.
  pass "link position: the links are inserted at the front of the topbar container ($prepend_n insert-at-front call(s), baseline 13)"
elif [ "${prepend_n:-0}" -gt 13 ]; then
  fail "link position: something inserts at the front, but nothing addresses .topbar-actions (or the pill it must precede)"
else
  fail "link position: neither markup before the doctype pill nor a new insert-at-front call — nothing puts the links at the START of .topbar-actions"
fi

# =============================================================================
# Outputs: two ANCHOR elements — plain links, not buttons wired to a handler
# =============================================================================

anchor_created="$(count 'createElement\("a"\)' "$APP_JS")"
markup_anchors="$(grep -coE '<a[[:space:]]' "$TOPBAR" 2> /dev/null || true)"
literal_anchors="$(count '<a[[:space:]]' "$APP_JS")"
if [ "${anchor_created:-0}" -gt 2 ] || [ "${markup_anchors:-0}" -ge 1 ] \
  || [ "${literal_anchors:-0}" -ge 1 ]; then
  pass "outputs: the navigation is rendered as anchor elements (plain links)"
else
  fail "outputs: no new anchor element is produced (createElement(\"a\") still at its baseline of 2, and no <a> in the topbar markup)"
fi

# Errors: plain navigation means no new request and no dialog — a failure on
# the target URL is the server's JSON error in the browser, not page breakage.
# Baseline 2 (/annotate POST, /raw live-update poll) plus the split-view
# panel's /raw hydration fetch — the topbar links themselves add none.
# Count raised 3 -> 4 by the park banner (round-6 F34): one fetch of the
# sibling tracking document's /raw route; the topbar links still issue none.
pinned 'fetch\(|XMLHttpRequest' 4 \
  "errors: the links navigate rather than fetch (no new request is issued)"
pinned '\balert\(|\bconfirm\(' 0 "errors: no user-facing dialog is introduced"
pinned '/annotate' 1 "same-server invariant: /annotate is still the only route the page POSTs to"
pinned 'https?://' 0 "same-origin invariant: no absolute or external URL is introduced"

# =============================================================================
# Outputs: present on EVERY docType, work-graph included — so the links may not
# hang off a docType branch
# =============================================================================

# Count raised 11 -> 12 by the park banner (round-6 F34): the banner is
# gated to work-graph documents; the topbar links remain ungated.
pinned 'docType[[:space:]]*[!=]==' 12 \
  "every docType: no new docType comparison — the links are not gated on the kind of document"

# =============================================================================
# Invariants: live-update re-renders never duplicate the links
# =============================================================================
# render() is the repaint path the poller drives, so building the topbar inside
# it is exactly what would duplicate the links on every update.

RENDER_FN="$WORK/render.js"
extract_function "$APP_JS" render > "$RENDER_FN"
if [ ! -s "$RENDER_FN" ]; then
  fail "no duplication: render() could not be extracted — the repaint clause cannot be checked"
else
  pass "no duplication: render() extracted"
  lacks_f "$RENDER_FN" '/project/for' \
    "no duplication: render() does not build the Worktree link (a repaint would add another)"
  lacks_f "$RENDER_FN" 'Worktree' \
    "no duplication: render() does not build the topbar navigation at all"
fi

# =============================================================================
# Invariants: the existing topbar controls keep their behaviour and their
# relative order
# =============================================================================

pinned 'getElementById\("schema-toggle"\)' 2 "existing controls: the schema toggle is untouched"
pinned 'getElementById\("graph-toggle"\)' 2 "existing controls: the graph toggle is untouched"
pinned 'getElementById\("feedback-btn"\)' 3 "existing controls: the feedback button is untouched"
pinned 'getElementById\("doctype-pill"\)' 1 "existing controls: the doctype pill is still read in exactly one place"

order_ok=1
prev=0
for id in doctype-pill schema-toggle graph-toggle feedback-btn; do
  line="$(grep -nF "id=\"$id\"" "$TOPBAR" | head -1 | cut -d: -f1)"
  if [ -z "$line" ]; then
    fail "existing controls: #$id is no longer in the topbar markup"
    order_ok=0
  elif [ "$line" -le "$prev" ]; then
    fail "existing controls: #$id moved — it no longer follows the control before it"
    order_ok=0
  else
    prev="$line"
  fi
done
[ "$order_ok" -eq 1 ] \
  && pass "existing controls: the pill, both toggles and the feedback button keep their relative order"

has_f "$APP_JS" 'graphToggle.textContent = state.graphOn ? "Card view" : "Graph";' \
  "existing controls: the graph toggle's labeling is byte-unchanged"
has_f "$APP_JS" 'state.schemaOn = !state.schemaOn;' \
  "existing controls: the schema toggle's two-state semantics are untouched"

# Invariant: no external resources. The topbar gains links, not assets.
if grep -E '<link[^>]+href="https?:|src="https?:|@import|fonts\.googleapis' \
  "$TEMPLATE_CODE" > /dev/null 2>&1; then
  fail "no external resources: the template references an external URL/CDN"
else
  pass "no external resources: the template still fetches nothing at view time"
fi

# =============================================================================
# The contract docblock survives implementation, minus its scaffold note
# =============================================================================

B05_DOCBLOCK="$WORK/b05.docblock"
extract_docblock "$TEMPLATE" 'Contract: 002-B05 doc-page topbar nav' > "$B05_DOCBLOCK"
if [ ! -s "$B05_DOCBLOCK" ]; then
  fail "002-B05 docblock: not found in template.html (the contract must survive implementation)"
else
  pass "002-B05 docblock: still present in template.html"
  lacks_f "$B05_DOCBLOCK" 'DELIBERATELY UNIMPLEMENTED' \
    "002-B05 docblock: the scaffold's DELIBERATELY UNIMPLEMENTED note is removed"
  has_f "$B05_DOCBLOCK" 'Behavior:' "002-B05 docblock: the contract clauses are retained"
fi

# =============================================================================
# Not mechanically checkable here — verified by the orchestrator at acceptance
# =============================================================================
# Executing the template needs a live DOM and a running server, and this repo
# has no browser harness. These clauses are acceptance-verified in a browser
# instead of asserted above:
#   - Behavior: the two links actually render, actually sit first in the
#     topbar, and actually navigate to the index and to the owning worktree's
#     landing page.
#   - Behavior: a page opened over file:// really shows neither link, and a
#     page whose sourcePath is empty really shows Index alone.
#   - Outputs: the links are styled consistently with the existing controls —
#     a visual judgement no grep can make — and are present on a work-graph
#     document as on every other docType.
#   - Invariants: a live-update repaint really leaves exactly two links.
#   - Edge case: the links wrap rather than overflow on a narrow viewport.

# --- Summary -----------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'topbar-nav.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'topbar-nav.test.sh: all assertions passed\n'
