#!/usr/bin/env bash
# workgraph-docs.test.sh — test suite for B03 (docs-and-version, contract
# label 229-B03). Verifies the render-doc README/SKILL.md prose documents
# the Graph display mode (cytoscape+dagre node-and-edge view) and the
# version legs land at 0.3.0, once 229-B03 is implemented. Contract
# docblock lives in plugins/render-doc/README.md, "Contract: 229-B03"
# (mirrored in skills/render/SKILL.md).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
README="$PLUGIN_DIR/README.md"
SKILL_MD="$PLUGIN_DIR/skills/render/SKILL.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
ROOT_README="$REPO_ROOT/README.md"

FAILURES=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'PASS  %s\n' "$*"
}

# Strip HTML comments before asserting prose — the contract docblock itself
# quotes several of the strings being checked for, so a naive scan would let
# the comment satisfy the assertion and the test would go green (then red
# again) exactly when the comment is deleted at acceptance. Precedent:
# structure.test.sh's strip_docblocks.
strip_docblocks() { sed '/<!--/,/-->/d' "$1"; }

assert_contains() { # <haystack> <needle> <label>
  local haystack="$1" needle="$2" label="$3"
  if printf '%s' "$haystack" | grep -qiF -- "$needle"; then
    pass "$label"
  else
    fail "$label"
  fi
}

assert_not_contains_f() { # <haystack> <needle> <label>
  local haystack="$1" needle="$2" label="$3"
  if printf '%s' "$haystack" | grep -qiF -- "$needle"; then
    fail "$label"
  else
    pass "$label"
  fi
}

# Sibling plugin directory names, discovered from the tree rather than
# hardcoded — mirrors architecture-lint's own approach (CLAUDE.md: "the
# plugin-name vocabulary is discovered from the tree, never hardcoded").
# This also keeps this file itself clean under architecture-lint: a literal
# "<name> plugin"/"/<name>:"/"<name>@clam"/"plugins/<name>/" string in a
# .test.sh's own source is itself a reference and gets flagged, so the
# names below are runtime values from `find`, never spelled out in source.
sibling_plugins() {
  find "$REPO_ROOT/plugins" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -vFx "$(basename "$PLUGIN_DIR")" | sort
}

# Reports whether $1 contains a genuine reference (any of the four forms
# ARCHITECTURE.md/CLAUDE.md define — skill invocation, marketplace id,
# filesystem path, or "<name> plugin" English naming) to any sibling
# plugin. Deliberately NOT a bare substring scan for a plugin's name: this
# README already contains the unrelated, pre-existing phrase "TOC with
# scroll tracking" (a baseline-rendering feature name, nothing to do with
# any plugin), which the contract's own invariant ("every other claim in
# this README and SKILL.md is unchanged") requires to survive untouched.
# See the report's escalation section for the full rationale, including why
# this is scoped to specific new-prose regions rather than whole files (the
# README legitimately references decision-log elsewhere, pre-existing and
# already architecture-lint-baselined; a whole-file scan would false-fail
# on that unrelated, unchanged reference forever).
assert_no_sibling_reference() { # <haystack> <label>
  local haystack="$1" label="$2"
  local hit="" p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if printf '%s' "$haystack" | grep -qiE "/${p}:|${p}@clam|plugins/${p}/|${p}[[:space:]]plugin"; then
      hit="$p"
      break
    fi
  done < <(sibling_plugins)
  if [ -n "$hit" ]; then
    fail "$label: names a sibling plugin (reference form found — see contract invariant)"
  else
    pass "$label: names no sibling plugin"
  fi
}

readme_stripped="$(strip_docblocks "$README")"
skill_stripped="$(strip_docblocks "$SKILL_MD")"

# Region scoped to exactly the schema-enumeration paragraph (where clause 1
# lands the Work Graph clause), bounded by two headings that are themselves
# untouched by this block. Scoping here — rather than the whole file —
# means the pre-existing, legitimate decision-log skill reference under
# "## Relationships to other plugins" elsewhere in this README can never
# be mistaken for a new violation.
readme_schema_section="$(awk '
  /^### Render a plan or decision file for review$/ { p=1 }
  /^### Leave feedback that writes back into the source$/ { exit }
  p
' "$README" | strip_docblocks /dev/stdin)"

# --- Clause 1: README schema-enumeration prose gains the Work Graph type ----
# Anchors drawn from the contract's own vocabulary (tree of node cards
# nested by Parent edges, dependency badges, three-way status pills
# open/done/dropped, focus banner for the Focus: node, per-node fallback to
# baseline, protocol reference). Wording is the implementer's choice; only
# presence of each anchor token is asserted, not exact sentences.
assert_contains "$readme_schema_section" '# Work Graph' "README: Work Graph H1 referenced"
assert_contains "$readme_schema_section" 'node card' "README: node cards mentioned"
assert_contains "$readme_schema_section" 'Parent' "README: Parent edges/nesting mentioned"
assert_contains "$readme_schema_section" 'dependency badge' "README: dependency badges mentioned"
assert_contains "$readme_schema_section" 'dropped' "README: dropped status mentioned"
assert_contains "$readme_schema_section" 'done' "README: done status mentioned"
assert_contains "$readme_schema_section" 'focus banner' "README: focus banner mentioned"
assert_contains "$readme_schema_section" 'Focus' "README: Focus node reference"
assert_contains "$readme_schema_section" 'fallback' "README: per-node fallback to baseline mentioned"

if printf '%s' "$readme_schema_section" | grep -qiE 'work-graph document format|docs/protocols/work-graph\.md|protocols/work-graph\.md'; then
  pass "README: work-graph document format / protocol referenced"
else
  fail "README: work-graph document format / protocol not referenced"
fi

assert_no_sibling_reference "$readme_schema_section" "README schema-enumeration prose"

# --- Clause 1b: README schema section gains the Graph display mode ----------
# Anchors drawn from the contract's own vocabulary (topbar "Graph" toggle,
# node-and-edge cytoscape+dagre rendering, status-colored nodes, parent vs
# dep edge styles, Focus highlight, click-a-node back to its card, card view
# remains default). Presence/proximity only — exact sentence is the
# implementer's choice, same as clause 1 above.
assert_contains "$readme_schema_section" 'cytoscape' "README: cytoscape rendering named"
assert_contains "$readme_schema_section" 'dagre' "README: dagre named"

if printf '%s' "$readme_schema_section" | grep -qiE 'graph[^.]{0,40}toggle|toggle[^.]{0,40}graph'; then
  pass "README: Graph toggle mentioned"
else
  fail "README: Graph toggle mentioned"
fi

if printf '%s' "$readme_schema_section" | grep -qiE 'node-and-edge|node[- ]and[- ]edge'; then
  pass "README: node-and-edge rendering mentioned"
else
  fail "README: node-and-edge rendering mentioned"
fi

if printf '%s' "$readme_schema_section" | grep -qiE 'status[- ]colored'; then
  pass "README: status-colored nodes mentioned"
else
  fail "README: status-colored nodes mentioned"
fi

assert_contains "$readme_schema_section" 'edge style' "README: parent vs dep edge styling mentioned"

if printf '%s' "$readme_schema_section" | grep -qiE 'focus[^.]{0,15}highlight'; then
  pass "README: Focus highlight mentioned"
else
  fail "README: Focus highlight mentioned"
fi

if printf '%s' "$readme_schema_section" | grep -qiE 'click[^.]{0,25}node[^.]{0,25}card|node[^.]{0,25}back[^.]{0,25}card'; then
  pass "README: click-a-node back to its card mentioned"
else
  fail "README: click-a-node back to its card mentioned"
fi

if printf '%s' "$readme_schema_section" | grep -qiE 'card view[^.]{0,20}default|default[^.]{0,20}card view'; then
  pass "README: card view remains default mentioned"
else
  fail "README: card view remains default mentioned"
fi

# Raw (unstripped) file: the contract comment itself must be gone at green —
# its presence is what keeps this whole suite red pre-implementation, and
# its removal is the acceptance signal for this block.
if grep -qF 'Contract: B03' "$README"; then
  fail "README: 'Contract: B03' marker still present (must be removed at acceptance)"
else
  pass "README: 'Contract: B03' marker removed"
fi

# --- Clause 2: README Maintenance fixture list becomes four, naming work-graph
readme_maint="$(awk '/^### Maintenance$/{p=1; next} p && /^#/{exit} p' "$README" | strip_docblocks /dev/stdin)"

assert_not_contains_f "$readme_maint" 'renders all three fixtures' "README Maintenance: no longer lists three fixtures"
assert_contains "$readme_maint" 'work-graph' "README Maintenance: work-graph fixture named"
assert_contains "$readme_maint" 'four' "README Maintenance: fixture count updated to four"
assert_no_sibling_reference "$readme_maint" "README Maintenance fixture list"

# --- Clause 2b: README Maintenance gains the two vendored-library bullets ----
assert_contains "$readme_maint" 'cytoscape@3.34.0' "README Maintenance: cytoscape version pinned"
assert_contains "$readme_maint" 'cytoscape-dagre@4.0.0' "README Maintenance: cytoscape-dagre version pinned"
assert_contains "$readme_maint" 'assets/cytoscape.min.js' "README Maintenance: cytoscape asset path named"
assert_contains "$readme_maint" 'assets/cytoscape-dagre.min.js' "README Maintenance: cytoscape-dagre asset path named"

if printf '%s' "$readme_maint" | grep -qiE 'bundle[^.]{0,15}dagre|dagre[^.]{0,15}bundle'; then
  pass "README Maintenance: dagre bundling noted"
else
  fail "README Maintenance: dagre bundling noted"
fi

# --- Clause 3: SKILL.md Schema-aware row + Maintenance bullet -----------------
schema_row="$(printf '%s\n' "$skill_stripped" | grep '^| Schema-aware ' || true)"

if [ -z "$schema_row" ]; then
  fail "SKILL.md: Schema-aware table row not found"
else
  pass "SKILL.md: Schema-aware table row found"
  assert_contains "$schema_row" '# Work Graph' "SKILL.md Schema-aware row: Work Graph H1 referenced"
  assert_contains "$schema_row" 'node card' "SKILL.md Schema-aware row: node cards mentioned"
  assert_contains "$schema_row" 'Parent' "SKILL.md Schema-aware row: Parent edges/nesting mentioned"
  assert_contains "$schema_row" 'dependency badge' "SKILL.md Schema-aware row: dependency badges mentioned"
  assert_contains "$schema_row" 'dropped' "SKILL.md Schema-aware row: dropped status mentioned"
  assert_contains "$schema_row" 'done' "SKILL.md Schema-aware row: done status mentioned"
  assert_contains "$schema_row" 'focus banner' "SKILL.md Schema-aware row: focus banner mentioned"
  assert_contains "$schema_row" 'fallback' "SKILL.md Schema-aware row: per-node fallback mentioned"
  assert_no_sibling_reference "$schema_row" "SKILL.md Schema-aware row"

  # --- Clause 3b: Schema-aware row gains the Graph display mode -------------
  assert_contains "$schema_row" 'cytoscape' "SKILL.md Schema-aware row: cytoscape rendering named"
  assert_contains "$schema_row" 'dagre' "SKILL.md Schema-aware row: dagre named"
  if printf '%s' "$schema_row" | grep -qiE 'graph[^.]{0,40}toggle|toggle[^.]{0,40}graph'; then
    pass "SKILL.md Schema-aware row: Graph toggle mentioned"
  else
    fail "SKILL.md Schema-aware row: Graph toggle mentioned"
  fi
  if printf '%s' "$schema_row" | grep -qiE 'card view[^.]{0,20}default|default[^.]{0,20}card view'; then
    pass "SKILL.md Schema-aware row: card view remains default mentioned"
  else
    fail "SKILL.md Schema-aware row: card view remains default mentioned"
  fi
fi

skill_maint="$(awk '/^## Maintenance$/{p=1; next} p && /^#/{exit} p' "$SKILL_MD" | strip_docblocks /dev/stdin)"

assert_not_contains_f "$skill_maint" 'renders all three fixtures' "SKILL.md Maintenance: no longer lists three fixtures"
assert_contains "$skill_maint" 'work-graph' "SKILL.md Maintenance: work-graph fixture named"
assert_contains "$skill_maint" 'four' "SKILL.md Maintenance: fixture count updated to four"
assert_no_sibling_reference "$skill_maint" "SKILL.md Maintenance bullet"

# --- Clause 3c: SKILL.md Maintenance gains the two vendored-library bullets --
assert_contains "$skill_maint" 'cytoscape@3.34.0' "SKILL.md Maintenance: cytoscape version pinned"
assert_contains "$skill_maint" 'cytoscape-dagre@4.0.0' "SKILL.md Maintenance: cytoscape-dagre version pinned"

if printf '%s' "$skill_maint" | grep -qiE 'bundle[^.]{0,15}dagre|dagre[^.]{0,15}bundle'; then
  pass "SKILL.md Maintenance: dagre bundling noted"
else
  fail "SKILL.md Maintenance: dagre bundling noted"
fi

# --- Clause 4: version legs ---------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  fail "jq not found — cannot check plugin.json version/description"
else
  pj_version="$(jq -r '.version' "$PLUGIN_JSON")"
  if [ "$pj_version" = "0.3.0" ]; then
    pass "plugin.json: version is exactly 0.3.0"
  else
    fail "plugin.json: version is '$pj_version', expected exactly 0.3.0"
  fi

  # Byte-exact expected description, pinned as of the pre-B03 scaffold —
  # the contract requires this field to survive the version bump unchanged.
  EXPECTED_DESC='Render a planning or decision markdown file into a single self-contained dark-theme HTML view, with an annotation server whose in-page composer writes @TAG: feedback lines back into the source markdown.'
  pj_desc="$(jq -r '.description' "$PLUGIN_JSON")"
  if [ "$pj_desc" = "$EXPECTED_DESC" ]; then
    pass "plugin.json: description byte-unchanged"
  else
    fail "plugin.json: description changed (expected byte-unchanged)"
  fi
fi

# Anchor the root README row so a sibling plugin's row can never satisfy this.
root_row="$(grep -E '^\| *\[render-doc\]\(plugins/render-doc/\) *\|' "$ROOT_README" || true)"
if [ -z "$root_row" ]; then
  fail "root README: render-doc plugins-table row not found"
else
  root_row_version="$(printf '%s' "$root_row" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ "$root_row_version" = "v0.3.0" ]; then
    pass "root README: render-doc row version is v0.3.0"
  else
    fail "root README: render-doc row version is '${root_row_version:-missing}', expected v0.3.0"
  fi

  # Description cell is pinned unchanged by the contract, parallel to the
  # plugin.json description-unchanged check above.
  ROOT_ROW_EXPECTED_DESC='Renders a markdown document into a self-contained HTML view via `/render-doc:render <file>`, with an annotation server that writes feedback back into the source markdown. Ported from clam-code.'
  if printf '%s' "$root_row" | grep -qF "$ROOT_ROW_EXPECTED_DESC"; then
    pass "root README: render-doc row description byte-unchanged"
  else
    fail "root README: render-doc row description byte-unchanged (expected byte-unchanged)"
  fi
fi

# --- Summary --------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'workgraph-docs.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'workgraph-docs.test.sh: all assertions passed\n'
