#!/usr/bin/env bash
# discovery-docs.test.sh — the prose-and-version block of plan
# 002-discovery-landing-dns ("Contract: 002-B03 G01 docs + bump", the HTML
# comment near the end of plugins/render-doc/README.md).
#
# Two audiences have to learn that the index no longer shows only what somebody
# opened: a reader of the plugin README, and a reader of serve.py's own header.
# Both have to learn the degradation in the same breath — when git or the scan
# fails, the listing falls back to the registry. The version legs land at 0.8.0
# in plugin.json and in the root README's Plugins table, which readme-lint
# pairs.
#
# Prose is asserted by presence/proximity anchors drawn from the contract's own
# vocabulary, never by exact sentences: the wording is the implementer's choice.
# That is the convention workgraph-docs.test.sh established for this plugin's
# docs blocks and serve-mode-docs.test.sh continued, including its
# discovered-from-the-tree sibling-plugin check.
#
# Scoping is what makes these checks mean anything. The README's "### Scripts"
# section ALREADY describes the registry, /docs.json, the project index and its
# grouping — that is what the previous plan's docs block added — so a
# section-wide grep for "registry" or "index" would go green today on prose that
# never mentions discovery at all. Every fact below is therefore asserted inside
# the text immediately surrounding a DISCOVERY mention (discover / scan /
# unserved), a window that is empty until the feature is documented and cannot
# be satisfied by a neighbouring paragraph about something else. The same trick
# the --serve suite uses on its own flag.
#
# serve.py's "header prose" is read as its MODULE docstring, extracted through
# the python parser rather than by grep. That matters: the file's contract
# docblocks quote the very words these checks look for — "discovery", ".local",
# "degrade" — and a textual scan would pass on the spec instead of on the prose
# a reader of the file's first screen actually sees.
#
# Marker note: plan-002 contract markers are plan-qualified. README.md and
# serve.py both also carry bare "Contract: B<NN>" markers from earlier plans
# meaning something else, so every marker check here uses the full 002-B<NN>
# form.
#
# Deliberately NOT asserted here, because another suite already gates it: the
# README "## Tests" list naming every shipped suite (server-docs.test.sh derives
# that list from the tree), README template conformance (readme-lint), and
# whether the new prose is TRUE — discovery-scan.test.sh and
# index-discovery.test.sh gate the behaviour it describes.

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
README="$PLUGIN_DIR/README.md"
SERVE="$SCRIPT_DIR/serve.py"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
ROOT_README="$REPO_ROOT/README.md"

# The version this block bumps to, asserted as a FLOOR rather than an equality:
# two later blocks of this same plan bump the plugin again, and a test about
# discovery docs must not go red the day one of them lands. Repo precedent:
# workgraph-docs.test.sh's own de-pinned floor (#120).
VERSION_FLOOR='0.8.0'

# How much text either side of a discovery mention counts as documenting it.
# Wide enough for a paragraph that states several facts at once, narrow enough
# that an unrelated neighbouring paragraph cannot satisfy a clause on its own.
WINDOW=400

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

# --- Helpers -----------------------------------------------------------------

# Contract prose quotes the very strings these checks look for, so every prose
# check runs against a copy with HTML comments removed — otherwise the checks
# would go green while the contract comment is still there and red again the
# moment it is deleted at acceptance. Precedent: workgraph-docs.test.sh.
strip_docblocks() { sed '/<!--/,/-->/d' "$1"; }

# Both files are hard-wrapped and every check below is a proximity check, so
# each region is flattened to one line first. A two-word pattern must not miss
# because the author's line broke between the words.
flatten() { tr '\n' ' ' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'; }

# Not `grep -q`: under `set -o pipefail` an early-exiting grep -q closes the
# pipe under a still-writing printf and the SIGPIPE becomes the pipeline's
# status. Cheap to avoid, invisible when it bites. (graph-always-docs.test.sh
# documents the same trap.)
matches() { # <haystack> <ERE>
  printf '%s\n' "$1" | grep -iE -- "$2" > /dev/null 2>&1
}
matches_f() { # <haystack> <literal>
  printf '%s\n' "$1" | grep -iF -- "$2" > /dev/null 2>&1
}
has() { # <haystack> <ERE> <label>
  if matches "$1" "$2"; then pass "$3"; else fail "$3"; fi
}
has_f() { # <haystack> <literal> <label>
  if matches_f "$1" "$2"; then pass "$3"; else fail "$3"; fi
}

section() { # <file> <heading-ere> <stop-ere>
  awk -v pat="$2" -v stop="$3" '
    /^(```|~~~)/ { fence = !fence; if (p) print; next }
    !p { if (!fence && $0 ~ pat) p = 1; next }
    p && !fence && $0 ~ stop { exit }
    p
  ' "$1"
}

# Sibling plugin directory names, discovered from the tree rather than
# hardcoded — a literal "<name> plugin"/"/<name>:"/"<name>@clam"/"plugins/
# <name>/" string in this file's own source would itself be a cross-plugin
# reference and get flagged by architecture-lint. Copied from
# workgraph-docs.test.sh, which explains the reasoning at length.
sibling_plugins() {
  find "$REPO_ROOT/plugins" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2> /dev/null \
    | grep -vFx "$(basename "$PLUGIN_DIR")" | sort
}

assert_no_sibling_reference() { # <haystack> <label>
  local haystack="$1" label="$2"
  local hit="" p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if matches "$haystack" "/${p}:|${p}@clam|plugins/${p}/|${p}[[:space:]]plugin"; then
      hit="$p"
      break
    fi
  done < <(sibling_plugins)
  if [ -n "$hit" ]; then
    fail "$label: names a sibling plugin (reference form found — see CLAUDE.md's layering rule)"
  else
    pass "$label: names no sibling plugin"
  fi
}

# --- Vocabulary ---------------------------------------------------------------
# Each fact as an alternation, so a faithful rewrite is not forced into one
# word. $WS spells a gap that survives a hard wrap flattened to one space.
WS='[[:space:]]+'

# The anchor. None of these three words appears anywhere in the reader-facing
# README today, which is exactly why the window they define is empty until this
# block writes something.
DISCOVERY='discover|scan|unserved'

LOCAL_DIR='\.local'
MARKDOWN='\.md|markdown'
WORKTREES="worktree|sibling|checkout"
# "never-served docs included and marked unserved".
NEVER_SERVED="unserved|never${WS}(been${WS})?(served|opened|rendered)|not${WS}(yet${WS})?(been${WS})?(served|opened)|have${WS}not${WS}been${WS}served|without${WS}(being${WS})?(served|opened)"
# The degradation: something fails, and the listing falls back to the registry.
FAILS="fails?|failure|unavailable|missing|cannot|can't|broken|error|degrad|falls?${WS}back|fallback"
FALLBACK_STATE="registr|already[- ]served|only${WS}(the${WS})?(served|registered|previously)|served${WS}documents?|what${WS}(has${WS})?(been${WS})?served"
# ...and it names WHAT fails, within one sentence ([^.] cannot cross a full stop).
NAMES_THE_FAILURE="(git|scan|discover|enumerat)[^.]{0,120}(fails?|failure|unavailable|missing|broken|error|cannot|can't)|(fails?|failure|unavailable|missing|broken|error|cannot|can't)[^.]{0,120}(git|scan|discover|enumerat)"

# --- Regions ------------------------------------------------------------------

README_BODY="$WORK/README.stripped.md"
strip_docblocks "$README" > "$README_BODY"

if [ ! -s "$README_BODY" ]; then
  fail "setup: the stripped copy of README.md came out empty — no clause could be checked"
  printf 'discovery-docs.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
pass "setup: README.md stripped of its HTML comments"

# The strip is what makes every check below meaningful. Prove it worked rather
# than assuming it: any plan-002 contract comment present in the raw file must be
# absent from the stripped copy. Pinned to no single block id — once every 002
# comment is gone a check naming only one would be vacuously green, which is
# exactly when the strip stops being proven, so that case reports itself.
if ! grep -qE 'Contract: 002-B[0-9]+' "$README"; then
  pass "sanity: no plan-002 contract comment remains in the raw README to prove the strip against"
elif grep -qE 'Contract: 002-B[0-9]+' "$README_BODY"; then
  fail "sanity: a plan-002 contract comment survived the strip — the sed range needs adjusting"
else
  pass "sanity: plan-002 contract comments are stripped from the body"
fi

readme_expect="$(section "$README_BODY" '^## What to expect$' '^## ' | flatten)"
readme_scripts="$(section "$README_BODY" '^### Scripts$' '^### ' | flatten)"
readme_failmodes_raw="$(section "$README_BODY" '^### Failure modes$' '^### ')"
readme_failmodes="$(printf '%s\n' "$readme_failmodes_raw" | flatten)"

# The three homes the contract names, read as one region: which of them carries
# which sentence is the implementer's call, that all of it is said is the
# contract's.
readme_region="$readme_expect $readme_scripts $readme_failmodes"

# serve.py's header prose is its MODULE docstring — read through the parser, so
# the contract docblocks further down the file cannot stand in for it.
serve_header="$(python3 -c "
import ast, sys
src = open(sys.argv[1], encoding='utf-8').read()
print(ast.get_docstring(ast.parse(src)) or '')
" "$SERVE" 2> /dev/null | flatten)"

# Contract: 003-B11 linear doc anchors (plan 003-followup-fixes)
#
# Behavior: the windowing helper is replaced by the window_around()
#   idiom the sibling docs suites use (find each anchor match, slice a
#   fixed-width window either side of it, linear time), with IDENTICAL
#   assertion semantics: same anchor alternation, same window width,
#   same joined single-string output shape, both call sites converted.
# Inputs: a flattened region string (unchanged).
# Outputs: the concatenated windows around every anchor match —
#   equivalent content to today's helper for the same inputs; empty
#   when the region is empty or no anchor matches (the honesty
#   property: no mention, no window, no accidental pass).
# Errors: none new.
# Invariants: suite verdicts are unchanged for unchanged inputs; suite
#   runtime drops from ~28s to under ~2s (closes #334).
# Edge cases: an anchor at the region's start or end (window truncates
#   cleanly); overlapping matches (each windowed; duplication tolerated
#   as today); case-insensitive matching preserved.

# The text around every anchor mention in a region — here, every discovery
# mention. Empty when discovery is not documented at all, which is what keeps
# every fact check honest: no mention, no window, no accidental pass from a
# neighbour.
#
# The obvious spelling of this — `grep -oEi ".{0,$WINDOW}($2).{0,$WINDOW}"` —
# is correct but pathologically slow once the anchor actually matches: on a
# region flattened to one ~20KB line grep expands a DFA state per (start
# offset x window length) pair, and the two windowed anchors below took ~27s of
# every run of this suite. Finding the anchor and slicing either side of it is
# the same answer in linear time. (landing-docs.test.sh and
# hostname-docs.test.sh carry the same helper and document the same
# measurement.)
window_around() { # <flattened region> <anchor ERE>
  ANCHOR="$2" ANCHOR_WINDOW="$WINDOW" python3 -c '
import os
import re
import sys

data = sys.stdin.read()
width = int(os.environ["ANCHOR_WINDOW"])
spans = [
    data[max(0, m.start() - width):m.end() + width]
    for m in re.finditer(os.environ["ANCHOR"], data, re.I)
]
sys.stdout.write(" ".join(spans))
' <<< "$1" 2> /dev/null
}

# =============================================================================
# Acceptance signal: the contract comment itself is gone. Read RAW, on purpose —
# this is the one assertion the strip would defeat.
# =============================================================================

if grep -qF 'Contract: 002-B03' "$README"; then
  fail "README.md: the 'Contract: 002-B03' comment is still present (deleting it is part of the work)"
else
  pass "README.md: the 'Contract: 002-B03' comment is removed"
fi

# =============================================================================
# Clause: the README describes filesystem discovery, in the sections that own it
# =============================================================================

if [ -z "$readme_expect" ]; then
  fail "README: the '## What to expect' section could not be located"
else
  pass "README: the '## What to expect' section is present"
fi
if [ -z "$readme_scripts" ]; then
  fail "README: the '### Scripts' section could not be located"
else
  pass "README: the '### Scripts' section is present"
fi
if [ -z "$readme_failmodes" ]; then
  fail "README: the '### Failure modes' section could not be located"
else
  pass "README: the '### Failure modes' section is present"
fi

readme_window="$(window_around "$readme_region" "$DISCOVERY")"

if [ -z "$readme_region" ]; then
  fail "README: none of the three sections could be located — no discovery clause can be checked"
elif [ -z "$readme_window" ]; then
  fail "README: discovery is never mentioned in 'What to expect', 'Scripts' or 'Failure modes'"
  fail "README: says the index lists documents under .local"
  fail "README: says those documents are markdown"
  fail "README: says discovery reaches every worktree of a served repo"
  fail "README: says never-served documents are listed and marked unserved"
  fail "README: states discovery's degradation to a registry-only listing"
  fail "README: names what fails when discovery degrades (git or the scan)"
else
  pass "README: discovery is documented in the sections the contract names"
  has "$readme_window" "$LOCAL_DIR" "README: says the index lists documents under .local"
  has "$readme_window" "$MARKDOWN" "README: says those documents are markdown"
  has "$readme_window" "$WORKTREES" "README: says discovery reaches every worktree of a served repo"
  has "$readme_window" "$NEVER_SERVED" \
    "README: says never-served documents are listed and marked unserved"
  if matches "$readme_window" "$FAILS" && matches "$readme_window" "$FALLBACK_STATE"; then
    pass "README: states discovery's degradation to a registry-only listing"
  else
    fail "README: states discovery's degradation to a registry-only listing"
  fi
  has "$readme_window" "$NAMES_THE_FAILURE" \
    "README: names what fails when discovery degrades (git or the scan)"
  assert_no_sibling_reference "$readme_window" "README discovery prose"
fi

# The page's own word for an unlisted document is "unserved" (the index
# contract fixes it), so the README has to use the reader's vocabulary rather
# than a synonym of its own.
has_f "$readme_region" 'unserved' \
  "README: uses the page's own word, \"unserved\", for a never-served document"

# =============================================================================
# Clause: the Failure modes table gains a row for discovery. The invariant is
# "every described feature states its degradation beside it", and this table is
# where this README states degradations — the same shape the previous docs
# block's row-per-route check took.
# =============================================================================

if [ -z "$readme_failmodes" ]; then
  fail "README Failure modes: the section could not be located — the discovery row cannot be checked"
else
  fm_rows="$(printf '%s\n' "$readme_failmodes_raw" | grep -c '^|')"
  : "${fm_rows:=0}"
  fm_rows=$((fm_rows - 2)) # the header row and its separator
  if [ "$fm_rows" -gt 11 ]; then
    pass "README Failure modes: the table gained a row ($fm_rows, was 11)"
  else
    fail "README Failure modes: the table still has $fm_rows data rows — none was added for discovery"
  fi
  fm_row="$(printf '%s\n' "$readme_failmodes_raw" | grep -iE "^\|.*($DISCOVERY|worktree list)" | head -1)"
  if [ -z "$fm_row" ]; then
    fail "README Failure modes: no row covers a failed discovery scan"
  else
    pass "README Failure modes: a row covers a failed discovery scan"
    has "$fm_row" "$FALLBACK_STATE" \
      "README Failure modes: that row states the fallback is the registry-only listing"
  fi
  assert_no_sibling_reference "$readme_failmodes" "README Failure modes"
fi

# =============================================================================
# Clause: serve.py's header prose describes discovery and its degradation
# =============================================================================

serve_window="$(window_around "$serve_header" "$DISCOVERY")"

if [ -z "$serve_header" ]; then
  fail "serve.py: the module docstring could not be read — no header clause can be checked"
elif [ -z "$serve_window" ]; then
  fail "serve.py header: discovery is never mentioned in the module docstring"
  fail "serve.py header: says the scan covers .local documents"
  fail "serve.py header: says the scan spans the repo's worktrees"
  fail "serve.py header: states discovery's degradation"
else
  pass "serve.py header: the module docstring describes discovery"
  has "$serve_window" "$LOCAL_DIR" "serve.py header: says the scan covers .local documents"
  has "$serve_window" "$WORKTREES" "serve.py header: says the scan spans the repo's worktrees"
  if matches "$serve_window" "$FAILS" && matches "$serve_window" "$FALLBACK_STATE"; then
    pass "serve.py header: states discovery's degradation"
  else
    fail "serve.py header: states discovery's degradation"
  fi
  assert_no_sibling_reference "$serve_header" "serve.py header prose"
fi

# =============================================================================
# Invariant: this block adds prose, it does not rewrite what is already there.
# The facts pinned below belong to earlier blocks and have no reason to move.
# =============================================================================

if matches "$readme_scripts" '27183' && matches "$readme_scripts" 'RENDER_DOC_PORT'; then
  pass "README Scripts: the fixed port and its override are still documented"
else
  fail "README Scripts: the fixed port or the RENDER_DOC_PORT override was lost"
fi
has_f "$readme_scripts" '/docs.json' "README Scripts: the /docs.json route is still documented"
has "$readme_scripts" 'render-doc-registry' \
  "README Scripts: the registry's /tmp file, keyed by port, is still documented"
has_f "$readme_scripts" 'WORKGRAPH' \
  "README Scripts: the WORKGRAPH.md headline is still documented"
if matches "$readme_failmodes" '\-\-serve' && matches "$readme_failmodes" '/raw'; then
  pass "README Failure modes: the existing --serve and /raw rows survive"
else
  fail "README Failure modes: an existing failure-mode row was lost"
fi

# =============================================================================
# Clause: the version legs
# =============================================================================

if ! command -v jq > /dev/null 2>&1; then
  fail "jq not found — the version legs cannot be checked"
else
  pj_version="$(jq -r '.version' "$PLUGIN_JSON" 2> /dev/null)"
  if [ -z "$pj_version" ] || [ "$pj_version" = "null" ]; then
    fail "plugin.json: version missing or unparseable"
  elif [ "$(printf '%s\n%s\n' "$VERSION_FLOOR" "$pj_version" | sort -V | head -1)" = "$VERSION_FLOOR" ]; then
    pass "plugin.json: version is $pj_version (>= $VERSION_FLOOR)"
  else
    fail "plugin.json: version is '$pj_version', expected $VERSION_FLOOR or later"
  fi

  # Byte-exact description: this block bumps the version, it does not restate
  # what the plugin is.
  EXPECTED_DESC='Render a planning or decision markdown file into a single self-contained dark-theme HTML view, with an annotation server whose in-page composer writes @TAG: feedback lines back into the source markdown.'
  pj_desc="$(jq -r '.description' "$PLUGIN_JSON" 2> /dev/null)"
  if [ "$pj_desc" = "$EXPECTED_DESC" ]; then
    pass "plugin.json: description byte-unchanged"
  else
    fail "plugin.json: description changed (expected byte-unchanged)"
  fi

  # Anchored on the render-doc row so a sibling plugin's row can never satisfy
  # it. readme-lint pairs this cell with plugin.json, so both legs are pinned:
  # the floor (this block's bump actually happened) and the agreement (the two
  # never drift apart).
  root_row="$(grep -E '^\| *\[render-doc\]\(plugins/render-doc/\) *\|' "$ROOT_README" || true)"
  if [ -z "$root_row" ]; then
    fail "root README: the render-doc plugins-table row was not found — the version cell cannot be checked"
  else
    pass "root README: the render-doc plugins-table row is present"
    root_row_version="$(printf '%s' "$root_row" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -z "$root_row_version" ]; then
      fail "root README: the render-doc row has no vX.Y.Z version cell"
    elif [ "$(printf '%s\n%s\n' "$VERSION_FLOOR" "${root_row_version#v}" | sort -V | head -1)" = "$VERSION_FLOOR" ]; then
      pass "root README: the render-doc row version is $root_row_version (>= v$VERSION_FLOOR)"
    else
      fail "root README: the render-doc row version is '$root_row_version', expected v$VERSION_FLOOR or later"
    fi
    if [ "$root_row_version" = "v$pj_version" ]; then
      pass "root README: the render-doc row version $root_row_version matches plugin.json"
    else
      fail "root README: the render-doc row version is '${root_row_version:-missing}', expected v$pj_version to match plugin.json"
    fi
    if matches_f "$root_row" '✅'; then
      pass "root README: the render-doc row keeps the ✅ status marker"
    else
      fail "root README: the render-doc row lost the ✅ status marker"
    fi
  fi
fi

# =============================================================================
# Left to acceptance review
# =============================================================================
# Whether the new prose is ACCURATE — that discovery really reaches every
# sibling worktree, really marks what it has not served, and really degrades the
# way the paragraph claims — is what discovery-scan.test.sh and
# index-discovery.test.sh gate against the shipped code; these anchors prove the
# claims are present and in the right place, not that they are true. Two
# judgement calls also stay with the orchestrator: whether the phrasing
# references docs/protocols/ conventions rather than inventing its own names for
# them (a reading, not a grep), and whether the serve.py header stays a header —
# short enough to be the first screen of the file rather than a second copy of
# the README.

# --- Summary ------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'discovery-docs.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'discovery-docs.test.sh: all assertions passed\n'
