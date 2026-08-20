#!/usr/bin/env bash
# live-update.test.sh — verifies the docblock "Contract: B05
# live-update-client" (plan 001-render-graph-always) in
# plugins/render-doc/assets/template.html clause by clause: a page served over
# http: polls /raw with If-None-Match, re-renders in place while preserving
# view state, holds the update while an annotation composer is open, backs off
# after repeated failures, and never polls at all on file://.
#
# There is no DOM/browser harness in this repo (render.test.sh's header says
# so, and workgraph-graph.test.sh repeats it for the graph view), so these are
# structural/string assertions over template.html's source, reaching only what
# the contract itself pins as observable: the route and header names, the
# timing constants, the state the update path must consult, and the state it
# must leave alone. Whether the page actually repaints, and whether a draft
# actually survives, is acceptance-verified by the orchestrator in a browser —
# the plan records that split explicitly.
#
# Block-letter collision warning: an earlier, already-merged plan
# (001-render-doc-workgraph-transform) numbered its blocks with bare letters
# too, so "Contract: B05" appears in the header prose of other test files in
# this directory meaning something else entirely, and serve.py carries its own
# "Contract: B01". The only live B05 for this plan is the template.html
# docblock this file greps by its full marker text, "Contract: B05
# live-update-client".
#
# SCOPE: checks run over the whole app script, not over startLiveUpdate()'s
# body. Splitting the poll loop, the update application, and the composer-hold
# buffer into separate helpers is a perfectly reasonable factoring that the
# contract neither requires nor forbids, and a body-scoped grep would fail it
# for no defect — this was verified empirically while writing the suite, on a
# stand-in implementation that used helpers. So each clause is asserted in the
# form that survives any factoring:
#   - PRESENT: strings that appear nowhere in the app script today (1500,
#     /raw, If-None-Match, ETag, 304, encodeURI, the ×4 back-off), so their
#     presence anywhere in it is new by construction.
#   - GREW: identifiers that DO already appear (sourceMd, render, collapsed,
#     the scroll position, openComposerEl, fetch), pinned to a pre-B05 line
#     count that the live-update path must push past. Baseline-growth is this
#     repo's idiom for exactly this problem — workgraph-graph.test.sh's
#     REUSE_BASELINE and ENVIRON_BASELINE.
#   - PINNED: the contract's "untouched" list (docType re-detection, the
#     feedback state, the drawer, the save-status UI, the view-mode flags),
#     asserted as line counts that must NOT change. A count rather than a
#     scoped negative is what makes these hold no matter where the new code
#     lives.
#
# Every check runs against a copy of template.html with ALL "/* Contract: ... */"
# docblocks removed: the B05 docblock quotes nearly every string checked below
# (POLL_MS, 1500, If-None-Match, ETag, 304, /raw, openComposerEl), so without
# the strip the contract prose would satisfy checks meant for real code.
# Precedent: workgraph-graph.test.sh.

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

# One line, single-spaced, untrimmed edges removed — so an exact-text
# comparison is not defeated by indentation or line wrapping.
flatten() { tr '\n' ' ' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'; }

TEMPLATE_CODE="$WORK/template.no-docblocks.html"
strip_contract_docblocks "$TEMPLATE" > "$TEMPLATE_CODE"

APP_JS="$WORK/app-script.js"
extract_app_script "$TEMPLATE_CODE" > "$APP_JS"

# --- Assertion helpers --------------------------------------------------------
# All of them grep a FILE rather than a piped string: under `set -o pipefail` a
# `grep -q` that exits on its first match closes the pipe beneath a still-
# writing printf, and the SIGPIPE becomes the pipeline's status — a false FAIL
# on any haystack larger than the pipe buffer.

count() { # <ERE> -> matching line count in the app script
  grep -cE -- "$1" "$APP_JS" 2> /dev/null || true
}

present() { # <ERE> <label>   (for strings absent from the app script pre-B05)
  if grep -qE -- "$1" "$APP_JS"; then pass "$2"; else fail "$2"; fi
}

grew() { # <ERE> <pre-B05 baseline> <label>
  local n
  n="$(count "$1")"
  if [ "${n:-0}" -gt "$2" ]; then
    pass "$3 (now $n line(s), pre-B05 baseline $2)"
  else
    fail "$3 — still $n line(s), unchanged from the pre-B05 baseline of $2"
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

# --- Sanity: the strip and the extraction actually worked ---------------------
if grep -qF 'Contract:' "$TEMPLATE_CODE"; then
  fail "sanity: contract docblocks were not stripped from template.html (strip helper needs adjusting)"
else
  pass "sanity: contract docblocks stripped from template.html"
fi
if grep -qF 'Contract: B05 live-update-client' "$TEMPLATE"; then
  pass "sanity: the B05 contract docblock is present to be stripped"
else
  fail "sanity: no 'Contract: B05 live-update-client' docblock in template.html — nothing proves the strip ran"
fi
if [ -s "$APP_JS" ]; then
  pass "sanity: app script extracted from template.html"
else
  fail "sanity: app script could not be extracted (the \"use strict\" anchor moved?) — no clause below can be checked"
fi

# =============================================================================
# The poller itself: defined, implemented, and its contract docblock retained
# =============================================================================

has_f "$TEMPLATE_CODE" 'function startLiveUpdate' "startLiveUpdate(): still defined"

if grep -qF 'NotImplemented: B05 live-update-client' "$APP_JS"; then
  fail "startLiveUpdate(): the NotImplemented throw is still in the app script"
else
  pass "startLiveUpdate(): the NotImplemented throw is gone"
fi

B05_DOCBLOCK="$WORK/b05.docblock"
extract_docblock "$TEMPLATE" 'Contract: B05 live-update-client' > "$B05_DOCBLOCK"
if [ ! -s "$B05_DOCBLOCK" ]; then
  fail "B05 docblock: not found in template.html (the contract must survive implementation)"
else
  pass "B05 docblock: still present in template.html"
  if grep -qF 'DELIBERATELY UNIMPLEMENTED' "$B05_DOCBLOCK"; then
    fail "B05 docblock: the scaffold's DELIBERATELY UNIMPLEMENTED note is still there"
  else
    pass "B05 docblock: the scaffold's DELIBERATELY UNIMPLEMENTED note is removed"
  fi
  has_f "$B05_DOCBLOCK" 'Behavior:' "B05 docblock: the contract clauses are retained"
fi

# =============================================================================
# Behavior 1: poll GET /raw/<percent-encoded sourcePath> every POLL_MS (1500),
# carrying If-None-Match once an ETag is known
# =============================================================================

present '\b1500\b' "poll cadence: the 1500ms poll interval is present"
present '/raw' "poll target: the /raw route is requested"
present 'encodeURI' "poll target: the source path is percent-encoded (encodeURI/encodeURIComponent)"
present 'If-None-Match' "conditional request: If-None-Match is sent"
present '[Ee][Tt]ag' "conditional request: the response ETag is read"
grew 'sourcePath' 3 "poll target: the request is built from sourcePath"
grew 'fetch\(|XMLHttpRequest' 1 "poll request: an HTTP request is issued beyond the annotation POST"
grew 'setTimeout\(|setInterval\(' 4 "poll loop: the poller schedules itself with a timer"

# =============================================================================
# Behavior 2 and 3: 304 changes nothing; 200 re-renders in place
# =============================================================================

present '\b304\b' "response handling: 304 is handled distinctly (nothing changes)"
present '\b200\b|res\.ok|\.ok\b' "response handling: a 200/ok response is distinguished from the rest"
grew 'sourceMd[[:space:]]*=[^=]' 1 "update: the response text replaces sourceMd"
grew 'render\(\)' 4 "update: render() is called to repaint the document"
grew 'collapsed' 5 "view state: the collapsed sections are recorded and re-applied"
grew 'scrollY|pageYOffset|scrollTo|scrollTop' 2 "view state: the window scroll position is recorded and restored"
grew 'openComposerEl' 3 "composer guard: the update path consults openComposerEl"

# A held update must be applied "the moment the composer closes", which means
# the close path has to notify the poller — closeComposer() is the only place
# that can. Its two existing statements must survive: closing a composer keeps
# doing exactly what it did.
CLOSE_COMPOSER="$(extract_function "$APP_JS" closeComposer | flatten)"
CLOSE_COMPOSER_BASELINE='function closeComposer() { if (openComposerEl) { openComposerEl.remove(); openComposerEl = null; } if (annotatingBlock) { annotatingBlock.classList.remove("annotating"); annotatingBlock = null; } }'

if [ -z "$CLOSE_COMPOSER" ]; then
  fail "composer flush: closeComposer() could not be extracted — the held-update clause cannot be checked"
elif [ "$CLOSE_COMPOSER" = "$CLOSE_COMPOSER_BASELINE" ]; then
  fail "composer flush: closeComposer() is unchanged from its pre-B05 body — nothing applies a held update when the composer closes"
else
  pass "composer flush: closeComposer() gained a hook for the held update"
fi
case "$CLOSE_COMPOSER" in
  *'if (openComposerEl) { openComposerEl.remove(); openComposerEl = null; }'*)
    pass "composer flush: closeComposer() still removes the composer element" ;;
  *) fail "composer flush: closeComposer() no longer removes the composer element" ;;
esac
case "$CLOSE_COMPOSER" in
  *'if (annotatingBlock) { annotatingBlock.classList.remove("annotating"); annotatingBlock = null; }'*)
    pass "composer flush: closeComposer() still clears the annotating block" ;;
  *) fail "composer flush: closeComposer() no longer clears the annotating block" ;;
esac

# Behavior 3b's explicit "untouched" list, pinned by count so it holds wherever
# the update path ends up living.
pinned 'detectDocType\(' 2 "update: docType is not re-detected (definition + the one call at load)"
pinned 'state\.feedback[[:space:]]*=[^=]' 2 "update: state.feedback is not reassigned anywhere new"
pinned 'getElementById\("drawer"\)' 3 "update: the feedback drawer is untouched"
pinned 'state\.schemaOn[[:space:]]*=[^=]' 1 "update: state.schemaOn is not reassigned (view mode preserved)"
pinned 'state\.graphOn[[:space:]]*=[^=]' 5 "update: state.graphOn is not reassigned (view mode preserved)"
pinned '\bactivateGraphView\(' 3 "update: an active graph view rebuilds through render()'s existing branch, not a new direct call"

# =============================================================================
# Behavior 4: failures never break the page; ×4 back-off after 5 in a row
# =============================================================================

grew 'catch' 13 "poll failures: a rejected request is caught rather than thrown"
present '\b5\b' "back-off: the 5-consecutive-failure threshold is present"
# The factor, not one spelling of it: "POLL_MS * 4", a literal 6000, and
# "skip 3 of every 4 ticks" all satisfy the clause, so the anchor is the
# number 4 growing past its single pre-B05 appearance (a cytoscape
# border-width) rather than a multiplication.
grew '\b6000\b|\b4\b' 1 "back-off: the ×4 back-off factor (POLL_MS * 4 / 6000ms) is present"

# =============================================================================
# Behavior 5 and the sourcePath edge case: when the poller must not start
# =============================================================================

grew 'SAVE_ENABLED|location\.protocol' 3 \
  "file:// guard: the poller keys on the same http: detection as SAVE_ENABLED"
present '![[:space:]]*sourcePath|sourcePath[[:space:]]*===?[[:space:]]*""|sourcePath\.length' \
  "empty-sourcePath guard: the poller does not start when there is nothing to poll"

# =============================================================================
# Errors: polling failures are silent to the user
# =============================================================================

pinned 'showSaveStatus\(' 3 "errors: the annotation save-status UI is not reused for poll failures"
pinned '\balert\(|\bconfirm\(' 0 "errors: no user-facing dialog is introduced"

# =============================================================================
# Invariants: exactly one poller, wired once in Boot, polling nothing else
# =============================================================================

call_sites="$(grep -cF 'startLiveUpdate(' "$APP_JS" 2> /dev/null || true)"
if [ "${call_sites:-0}" = "2" ]; then
  pass "one poller: startLiveUpdate appears exactly twice in the app script (its definition and a single call)"
else
  fail "one poller: expected exactly 2 'startLiveUpdate(' lines in the app script (definition + one call), found $call_sites"
fi

BOOT="$WORK/boot.js"
awk '/---------- Boot ----------/ { p = 1 } p { print }' "$APP_JS" > "$BOOT"
if [ ! -s "$BOOT" ]; then
  fail "boot wiring: the Boot section could not be located — the call-site clause cannot be checked"
else
  pass "boot wiring: Boot section located"
  boot_call_line="$(grep -nF 'startLiveUpdate(' "$BOOT" | head -1 | cut -d: -f1)"
  boot_feedback_line="$(grep -nF 'renderFeedback();' "$BOOT" | head -1 | cut -d: -f1)"
  if [ -z "$boot_call_line" ]; then
    fail "boot wiring: Boot does not call startLiveUpdate()"
  elif [ -z "$boot_feedback_line" ]; then
    fail "boot wiring: Boot's first renderFeedback() call could not be found (anchor moved?)"
  elif [ "$boot_call_line" -gt "$boot_feedback_line" ]; then
    pass "boot wiring: startLiveUpdate() is called from Boot, after the first render()/renderFeedback()"
  else
    fail "boot wiring: startLiveUpdate() is called before the first render()/renderFeedback()"
  fi
fi

# "Polls nothing but /raw on the page's own origin, no new external resources."
pinned '/annotate' 1 "same-server invariant: /annotate is still the only other route the page calls"
# The one "/doc/" occurrence is the split-view panel's pathname check on an
# existing anchor (hydration keys on it before fetching /raw) — not a request.
pinned '/doc/|/docs\.json|/health' 1 "same-server invariant: the page calls no other server route"
pinned 'https?://' 0 "same-origin invariant: no absolute/external URL is introduced"

# Invariant: the annotation write-back path is untouched by this block.
has_f "$APP_JS" 'var SAVE_ENABLED = window.location.protocol === "http:";' \
  "annotation flow: SAVE_ENABLED detection byte-unchanged"
has_f "$APP_JS" 'function saveAnnotationToFile(item) {' "annotation flow: saveAnnotationToFile still defined"
has_f "$APP_JS" 'fetch("/annotate", {' "annotation flow: annotations still POST to /annotate"

# =============================================================================
# Not mechanically checkable here — verified by the orchestrator at acceptance
# =============================================================================
# Executing the poller needs a live DOM, a running server and elapsed time, and
# this repo has no browser harness. These clauses are acceptance-verified in a
# browser instead of asserted above:
#   - Outputs: the page reflects a file change within about two poll intervals.
#   - Behavior 3a: a draft actually survives, newer content replaces held
#     content, and the newest held update lands when the composer closes.
#   - Behavior 3b: collapsed sections and scroll are actually restored, and an
#     active graph view actually rebuilds.
#   - Behavior 4: the interval actually widens after five failures and actually
#     returns to 1500ms after the next success.
#   - Behavior 5: zero network requests on file://.
#   - Edge cases: an empty document, a 200 carrying no ETag (every 200 treated
#     as changed), a server restarted mid-session, and background-tab timer
#     throttling.
# The plan records this split: template behavior is structurally anchored here
# and behaviourally checked at acceptance.

# --- Summary -----------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'live-update.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'live-update.test.sh: all assertions passed\n'
