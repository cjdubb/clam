#!/usr/bin/env bash
# landing-docs.test.sh — the prose-and-version block of plan
# 002-discovery-landing-dns ("Contract: 002-B06 G02 docs + bump", the HTML
# comment near the end of plugins/render-doc/README.md).
#
# Two audiences have to learn that a document page is no longer a dead end:
# a reader of the plugin README, and a reader of the render skill. Both have to
# learn the per-worktree landing page (the route that takes a worktree root,
# and the resolver that redirects from a document to its owner) and the two
# topbar links that reach it — including that those links are there only on a
# page the server handed over, never on one opened from disk. The version legs
# land at 0.9.0 in plugin.json and in the root README's Plugins table, which
# readme-lint pairs.
#
# Prose is asserted by presence/proximity anchors drawn from the contract's own
# vocabulary, never by exact sentences: the wording is the implementer's
# choice. That is the convention workgraph-docs.test.sh established for this
# plugin's docs blocks and serve-mode-docs.test.sh and discovery-docs.test.sh
# continued, including the discovered-from-the-tree sibling-plugin check.
#
# Scoping is what makes these checks mean anything. The README's "### Scripts"
# section ALREADY describes the server, its routes, the registry and the
# project index, so a section-wide grep for "route" or "worktree" would go
# green today on prose that never mentions the landing page. Every fact below
# is therefore asserted inside the text immediately surrounding a LANDING
# mention ("/project/", "landing page", "worktree page"), or a NAV mention
# (the resolver route, or "topbar" beside a link word) — windows that are empty
# until the feature is documented and cannot be satisfied by a neighbouring
# paragraph about something else. Every one of those anchor strings is absent
# from both files today, which is what makes the windows honest.
#
# Marker note: plan-002 contract markers are plan-qualified. README.md carries
# a second, LATER plan-002 comment (a block this suite has no business
# asserting anything about) and both files also carry bare "Contract: B<NN>"
# markers from earlier plans meaning something else, so every marker check here
# uses the full 002-B06 form and nothing greps the bare one.
#
# Deliberately NOT asserted here, because another suite already gates it: the
# README "## Tests" list naming every shipped suite (server-docs.test.sh
# derives that list from the tree), README template conformance (readme-lint),
# and whether the new prose is TRUE — landing-page.test.sh and
# topbar-nav.test.sh gate the behaviour it describes.

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
README="$PLUGIN_DIR/README.md"
SKILL_MD="$PLUGIN_DIR/skills/render/SKILL.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
ROOT_README="$REPO_ROOT/README.md"

# The version this block bumps to, asserted as a FLOOR rather than an equality:
# a later block of this same plan bumps the plugin again, and a test about
# landing-page docs must not go red the day that lands. Repo precedent:
# discovery-docs.test.sh and workgraph-docs.test.sh's own de-pinned floors.
VERSION_FLOOR='0.9.0'

# How much text either side of an anchor counts as documenting it. Wide enough
# for a paragraph that states several facts at once, narrow enough that an
# unrelated neighbouring paragraph cannot satisfy a clause on its own.
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
# discovery-docs.test.sh, which copied it from workgraph-docs.test.sh.
sibling_plugins() {
  find "$REPO_ROOT/plugins" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2> /dev/null \
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

# The two anchors. Every one of these strings is absent from both files today,
# which is exactly why the windows they define are empty until this block
# writes something. "/project" without the trailing slash is deliberately NOT
# an anchor: the README already says "grouped by worktree/project".
LANDING='/project/|landing[- ]page|worktree[- ]page|per-worktree[- ]page'
# The nav anchor deliberately does NOT include the resolver route: the landing
# paragraph names that route too, and an anchor that fired there would let
# landing prose satisfy the navigation clause without a word about the topbar.
# It takes a topbar word beside a link label instead — measured at zero
# occurrences in both files today, in either order.
NAV="(top ?bar|nav ?bar|navigation).{0,120}(index|worktree)|(index|worktree).{0,120}(top ?bar|nav ?bar|navigation)"

RESOLVER='/project/for'
WORKTREES="worktree|checkout"
LOCAL_DIR='\.local'
HEADLINE='WORKGRAPH'
GROUPING="collaps|expand|fold|details|group|section"
# The two protocol fields, named as fields rather than as words. The
# non-letter run allows for the code-span backticks the surrounding prose puts
# around a field name.
STATE_FIELD='State:|State[^A-Za-z]{0,3}field'
STATUS_FIELD='Status:|Status[^A-Za-z]{0,3}field|decision[- ]file'
# The degradation: something is missing or unreadable, and the page still lists
# the document / still renders.
FAILS="fails?|failure|unavailable|missing|cannot|can't|unreadable|without|no${WS}(such|match)|degrad|falls?${WS}back|fallback"
STILL_WORKS="still${WS}(listed|shown|rendered|appears)|plain${WS}link|unavailable|listed${WS}(plain|without)|no${WS}annotation|never${WS}(a${WS})?(500|error)|renders?${WS}anyway"
# The nav's own facts.
LINK_INDEX="index"
LINK_WORKTREE="worktree"
FILE_URL="file:|from${WS}disk|opened${WS}locally|without${WS}(the${WS})?server"

# --- Regions ------------------------------------------------------------------

README_BODY="$WORK/README.stripped.md"
strip_docblocks "$README" > "$README_BODY"

if [ ! -s "$README_BODY" ]; then
  fail "setup: the stripped copy of README.md came out empty — no clause could be checked"
  printf 'landing-docs.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
pass "setup: README.md stripped of its HTML comments"

# The strip is what makes every check below meaningful. Prove it worked rather
# than assuming it: any plan-002 contract comment present in the raw file must
# be absent from the stripped copy. Pinned to no single block id — once every
# 002 comment is gone a check naming only one would be vacuously green, which
# is exactly when the strip stops being proven, so that case reports itself.
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

# The three homes the contract's audience reads, taken as one region: which of
# them carries which sentence is the implementer's call, that all of it is said
# is the contract's.
readme_region="$readme_expect $readme_scripts $readme_failmodes"

skill_body="$WORK/SKILL.stripped.md"
strip_docblocks "$SKILL_MD" > "$skill_body"
skill_region="$(flatten < "$skill_body")"

# The text around every anchor mention in a region. Empty when the feature is
# not documented at all, which is what keeps every fact check honest: no
# mention, no window, no accidental pass from a neighbour.
#
# The obvious spelling of this — `grep -oEi ".{0,$WINDOW}($2).{0,$WINDOW}"` —
# is correct but pathologically slow once the anchor actually matches: on a
# region flattened to one ~20KB line grep expands a DFA state per (start
# offset x window length) pair, and four windowed anchors take minutes rather
# than the seconds this suite is allowed. Finding the anchor and slicing either
# side of it is the same answer in linear time.
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
# Acceptance signal: this block's own contract comment is gone. Read RAW, on
# purpose — this is the one assertion the strip would defeat. Nothing here says
# anything about the OTHER plan-002 comment in this file: it belongs to a later
# block and is removed by that block, not this one.
# =============================================================================

if grep -qF 'Contract: 002-B06' "$README"; then
  fail "README.md: the 'Contract: 002-B06' comment is still present (deleting it is part of the work)"
else
  pass "README.md: the 'Contract: 002-B06' comment is removed"
fi

# =============================================================================
# Clause: the README describes the per-worktree landing page
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

readme_landing="$(window_around "$readme_region" "$LANDING")"

if [ -z "$readme_region" ]; then
  fail "README: none of the three sections could be located — no landing-page clause can be checked"
elif [ -z "$readme_landing" ]; then
  fail "README: the landing page is never mentioned in 'What to expect', 'Scripts' or 'Failure modes'"
  fail "README: names the route that takes a worktree root"
  fail "README: names the /project/for resolver and its path parameter"
  fail "README: says the page covers one worktree"
  fail "README: says it lists the worktree's .local documents"
  fail "README: says the work graph is the page's headline"
  fail "README: says a subdirectory's documents collapse into a group"
  fail "README: describes the todo-format State: annotation source"
  fail "README: describes the decision-file Status: annotation source"
  fail "README: states the landing page's degradation"
else
  pass "README: the landing page is documented in the sections that own it"
  has_f "$readme_landing" '/project/' "README: names the route that takes a worktree root"
  if matches "$readme_landing" "$RESOLVER" && matches "$readme_landing" 'path='; then
    pass "README: names the /project/for resolver and its path parameter"
  else
    fail "README: names the /project/for resolver and its path parameter"
  fi
  has "$readme_landing" "$WORKTREES" "README: says the page covers one worktree"
  has "$readme_landing" "$LOCAL_DIR" "README: says it lists the worktree's .local documents"
  has "$readme_landing" "$HEADLINE" "README: says the work graph is the page's headline"
  has "$readme_landing" "$GROUPING" "README: says a subdirectory's documents collapse into a group"
  has "$readme_landing" "$STATE_FIELD" "README: describes the todo-format State: annotation source"
  has "$readme_landing" "$STATUS_FIELD" "README: describes the decision-file Status: annotation source"
  if matches "$readme_landing" "$FAILS" && matches "$readme_landing" "$STILL_WORKS"; then
    pass "README: states the landing page's degradation"
  else
    fail "README: states the landing page's degradation (a document that cannot be read is still listed)"
  fi
  assert_no_sibling_reference "$readme_landing" "README landing-page prose"
fi

# Invariant: the annotation sources are the two protocol fields and NOTHING
# else — a README that advertises reading a document's title or its first
# paragraph would describe a page the contract forbids. Kept short-range and
# free of "tag", which is this plugin's OWN annotation vocabulary: the
# neighbouring /annotate sentence names a tag legitimately, and a window that
# reached it must not be read as a second annotation source.
if matches "$readme_landing" "annotat[^.]{0,60}(title|heading|summary|first${WS}(line|paragraph)|front[- ]?matter)"; then
  fail "README: claims the landing page reads something other than the two protocol fields"
else
  pass "README: names no annotation source beyond the two protocol fields"
fi

# =============================================================================
# Clause: the README describes the doc-page topbar navigation
# =============================================================================

readme_nav="$(window_around "$readme_region" "$NAV")"

if [ -z "$readme_nav" ]; then
  fail "README: the doc page's topbar navigation is never described"
  fail "README: names the Index link"
  fail "README: names the Worktree link"
  fail "README: says the links are absent on a page opened over file://"
else
  pass "README: the doc page's topbar navigation is described"
  has "$readme_nav" "$LINK_INDEX" "README: names the Index link"
  has "$readme_nav" "$LINK_WORKTREE" "README: names the Worktree link"
  has "$readme_nav" "$FILE_URL" "README: says the links are absent on a page opened over file://"
  assert_no_sibling_reference "$readme_nav" "README topbar-navigation prose"
fi

# =============================================================================
# Clause: the Failure modes table gains a row for the landing page. The
# invariant is "degradation stated beside each feature", and this table is
# where this README states degradations — the same shape discovery-docs.test.sh
# took for the block before this one.
# =============================================================================

if [ -z "$readme_failmodes" ]; then
  fail "README Failure modes: the section could not be located — the landing-page row cannot be checked"
else
  fm_rows="$(printf '%s\n' "$readme_failmodes_raw" | grep -c '^|')"
  : "${fm_rows:=0}"
  fm_rows=$((fm_rows - 2)) # the header row and its separator
  if [ "$fm_rows" -gt 12 ]; then
    pass "README Failure modes: the table gained a row ($fm_rows, was 12)"
  else
    fail "README Failure modes: the table still has $fm_rows data rows — none was added for the landing page"
  fi
  fm_row="$(printf '%s\n' "$readme_failmodes_raw" | grep -iE "^\|.*(/project|landing[- ]page|worktree[- ]page)" | head -1)"
  if [ -z "$fm_row" ]; then
    fail "README Failure modes: no row covers a landing-page failure"
  else
    pass "README Failure modes: a row covers a landing-page failure"
    has "$fm_row" "$STILL_WORKS|403|404|error" \
      "README Failure modes: that row states what the reader gets instead"
  fi
  assert_no_sibling_reference "$readme_failmodes" "README Failure modes"
fi

# =============================================================================
# Clause: the render skill describes both features too
# =============================================================================

if [ ! -s "$skill_body" ]; then
  fail "setup: SKILL.md could not be read — no skill clause can be checked"
else
  pass "setup: SKILL.md read and stripped of its HTML comments"

  skill_landing="$(window_around "$skill_region" "$LANDING")"
  if [ -z "$skill_landing" ]; then
    fail "SKILL.md: the landing page is never described"
    fail "SKILL.md: names the route that takes a worktree root"
    fail "SKILL.md: says the page lists that worktree's .local documents"
    fail "SKILL.md: names the /project/for resolver"
  else
    pass "SKILL.md: the landing page is described"
    has_f "$skill_landing" '/project/' "SKILL.md: names the route that takes a worktree root"
    has "$skill_landing" "$LOCAL_DIR" "SKILL.md: says the page lists that worktree's .local documents"
    has "$skill_landing" "$RESOLVER" "SKILL.md: names the /project/for resolver"
    assert_no_sibling_reference "$skill_landing" "SKILL.md landing-page prose"
  fi

  skill_nav="$(window_around "$skill_region" "$NAV")"
  if [ -z "$skill_nav" ]; then
    fail "SKILL.md: the doc page's topbar navigation is never described"
    fail "SKILL.md: names the Index link"
    fail "SKILL.md: names the Worktree link"
    fail "SKILL.md: says the links are absent on a page opened over file://"
  else
    pass "SKILL.md: the doc page's topbar navigation is described"
    has "$skill_nav" "$LINK_INDEX" "SKILL.md: names the Index link"
    has "$skill_nav" "$LINK_WORKTREE" "SKILL.md: names the Worktree link"
    has "$skill_nav" "$FILE_URL" "SKILL.md: says the links are absent on a page opened over file://"
    assert_no_sibling_reference "$skill_nav" "SKILL.md topbar-navigation prose"
  fi
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
  "README Scripts: the WORKGRAPH.md headline of the index is still documented"
# Anchored on the feature, not on the marker the page used to print for it:
# 003-B15 removed the "unserved" mark from the index and 003-B18 removed the word
# from this paragraph with it, so a guard spelled that way would go red on a
# faithful rewrite of prose this block never touches.
has "$readme_scripts" 'discover|never[- ]served' \
  "README Scripts: the index's filesystem discovery is still documented"
if matches "$readme_failmodes" '\-\-serve' && matches "$readme_failmodes" '/raw'; then
  pass "README Failure modes: the existing --serve and /raw rows survive"
else
  fail "README Failure modes: an existing failure-mode row was lost"
fi
has_f "$skill_region" '/annotate' "SKILL.md: the existing /annotate route prose survives"
has_f "$skill_region" '/doc/' "SKILL.md: the existing /doc route prose survives"

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
# Whether the new prose is ACCURATE — that the page really groups by
# subdirectory, really annotates from those two fields and only those, and that
# the links really vanish on file:// — is what landing-page.test.sh and
# topbar-nav.test.sh gate against the shipped code; these anchors prove the
# claims are present and in the right place, not that they are true. Two
# judgement calls also stay with the orchestrator: whether the phrasing
# references docs/protocols/ conventions rather than inventing its own names
# for them (a reading, not a grep), and whether the skill doc stays a summary
# rather than becoming a second copy of the README.

# --- Summary ------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'landing-docs.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'landing-docs.test.sh: all assertions passed\n'
