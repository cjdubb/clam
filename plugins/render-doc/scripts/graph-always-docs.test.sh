#!/usr/bin/env bash
# graph-always-docs.test.sh — test suite for the docs-and-version block of plan
# 001-render-graph-always ("Contract: B07 template docs + version bump", the
# HTML comment in plugins/render-doc/README.md, mirrored as "Contract: B07
# template docs — SKILL.md part" in skills/render/SKILL.md).
#
# Two template changes have to reach the reader: Work Graph documents now paint
# the node-and-edge graph view first (the card tree is a toggle away), and a
# page served by the annotation server updates itself in place when the source
# markdown changes. The version legs land at 0.6.0 in plugin.json and in the
# root README's Plugins table, which readme-lint pairs.
#
# Prose is asserted by presence/proximity anchors drawn from the contract's own
# vocabulary, never by exact sentences — the wording is the implementer's
# choice. That is the convention workgraph-docs.test.sh established for this
# plugin's docs blocks, and this file follows it, including its
# discovered-from-the-tree sibling-plugin check.
#
# Block-letter collision warning: earlier merged plans numbered their blocks
# with bare letters too, so "Contract: B05"/"Contract: B06" appear in other
# test files' header prose meaning something else. The only live B07 is this
# plan's, and both markers are greped by their full text.
#
# Scoping matters here more than usual. The README's "### Scripts" section
# already documents /raw, ETag and If-None-Match as server routes (that is what
# the previous block added), so a whole-file grep for those strings would pass
# vacuously while the reader-facing prose said nothing about live updates.
# Every prose check below is therefore scoped to the region the contract names:
#   - the graph-first flip → the schema-enumeration paragraph (README) and the
#     Schema-aware table row (SKILL.md);
#   - the live-update paragraph → "## What to expect" plus the --open workflow
#     section (README, the contract's two allowed homes), and the usage/view
#     prose from "## Usage" through "## What the view provides" (SKILL.md).

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
README="$PLUGIN_DIR/README.md"
SKILL_MD="$PLUGIN_DIR/skills/render/SKILL.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
ROOT_README="$REPO_ROOT/README.md"

# The version this block bumps to, asserted as a FLOOR rather than an equality:
# later blocks and later plans keep bumping this plugin, and a test about
# graph-first docs must not go red the day an unrelated block bumps past it.
# Repo precedent: workgraph-docs.test.sh's own de-pinned floor (#120).
VERSION_FLOOR='0.6.0'

FAILURES=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'PASS  %s\n' "$*"
}

# Contract prose quotes the very strings these checks look for, so every prose
# check runs against a copy with HTML comments removed — otherwise the checks
# would go green while the contract comment is still there and red again the
# moment it is deleted at acceptance. Precedent: workgraph-docs.test.sh.
strip_docblocks() { sed '/<!--/,/-->/d' "$1"; }

flatten() { tr '\n' ' ' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'; }

# Not `grep -q`: under `set -o pipefail` an early-exiting grep -q closes the
# pipe under a still-writing printf and the SIGPIPE becomes the pipeline's
# status. Cheap to avoid, invisible when it bites.
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
lacks() { # <haystack> <ERE> <label>
  if matches "$1" "$2"; then fail "$3"; else pass "$3"; fi
}

# Sibling plugin directory names, discovered from the tree rather than
# hardcoded — a literal "<name> plugin"/"/<name>:"/"<name>@clam"/"plugins/
# <name>/" string in this file's own source would itself be a cross-plugin
# reference and get flagged by architecture-lint. Copied from
# workgraph-docs.test.sh, which explains the reasoning at length.
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

# --- Regions ------------------------------------------------------------------

readme_schema_section="$(awk '
  /^### Render a plan or decision file for review$/ { p = 1 }
  /^### Leave feedback that writes back into the source$/ { exit }
  p
' "$README" | strip_docblocks /dev/stdin | flatten)"

readme_expect_section="$(awk '
  /^## What to expect$/ { p = 1; next }
  p && /^## / { exit }
  p
' "$README" | strip_docblocks /dev/stdin | flatten)"

# The contract allows the live-update paragraph in either home, so the anchors
# below look at both together.
readme_live_region="$readme_expect_section $readme_schema_section"

skill_stripped="$(strip_docblocks "$SKILL_MD")"
skill_schema_row="$(printf '%s\n' "$skill_stripped" | grep '^| Schema-aware ' || true)"
skill_usage_region="$(printf '%s\n' "$skill_stripped" | awk '
  /^## Usage$/ { p = 1 }
  /^## Checkpoint integration$/ { exit }
  p
' | flatten)"

# =============================================================================
# Contract markers: both prose contracts are marked "remove at acceptance"
# =============================================================================

if grep -qF 'Contract: B07' "$README"; then
  fail "README: 'Contract: B07' marker still present (the contract comment is removed at acceptance)"
else
  pass "README: 'Contract: B07' marker removed"
fi
if grep -qF 'Contract: B07' "$SKILL_MD"; then
  fail "SKILL.md: 'Contract: B07' marker still present (the contract comment is removed at acceptance)"
else
  pass "SKILL.md: 'Contract: B07' marker removed"
fi

# =============================================================================
# Clause 1: the graph view is the default for Work Graph documents
# =============================================================================

if [ -z "$readme_schema_section" ]; then
  fail "README: the schema-enumeration section could not be located — the graph-default clauses cannot be checked"
else
  pass "README: schema-enumeration section located"

  if matches "$readme_schema_section" 'graph view[^.]{0,60}default|default[^.]{0,60}graph view|graph[- ]first|opens? (in|with|on)[^.]{0,20}graph|graph[^.]{0,50}\b(is|as|becomes)\b[^.]{0,25}default'; then
    pass "README: the graph view is described as the default for Work Graph documents"
  else
    fail "README: the graph view is not described as the default for Work Graph documents"
  fi

  lacks "$readme_schema_section" 'card view[^.]{0,20}default|default[^.]{0,20}card view' \
    "README: the card view is no longer described as the default"

  if matches "$readme_schema_section" 'card[^.]{0,60}toggle|toggle[^.]{0,60}card'; then
    pass "README: the card tree is still reachable by the toggle"
  else
    fail "README: the card tree is not described as reachable by the toggle"
  fi

  # Invariant: apart from which view is the default, the card view's own
  # description is unchanged. Spot-checked on the sentences that describe it.
  for lit in \
    'tree of node cards nested by their' \
    'dependency badge' \
    'three-way status pill' \
    'focus banner' \
    'falls back to baseline rendering for that node only'; do
    if matches_f "$readme_schema_section" "$lit"; then
      pass "README: card-view description intact — $lit"
    else
      fail "README: card-view description lost — $lit"
    fi
  done

  assert_no_sibling_reference "$readme_schema_section" "README schema-enumeration prose"
fi

if [ -z "$skill_schema_row" ]; then
  fail "SKILL.md: the Schema-aware table row could not be located — the graph-default clauses cannot be checked"
else
  pass "SKILL.md: Schema-aware table row located"

  if matches "$skill_schema_row" 'graph view[^.]{0,60}default|default[^.]{0,60}graph view|graph[- ]first|opens? (in|with|on)[^.]{0,20}graph|graph[^.]{0,50}\b(is|as|becomes)\b[^.]{0,25}default'; then
    pass "SKILL.md Schema-aware row: the graph view is described as the default"
  else
    fail "SKILL.md Schema-aware row: the graph view is not described as the default"
  fi

  lacks "$skill_schema_row" 'card view[^.]{0,20}default|default[^.]{0,20}card view' \
    "SKILL.md Schema-aware row: the card view is no longer described as the default"

  if matches "$skill_schema_row" 'card[^.]{0,60}toggle|toggle[^.]{0,60}card'; then
    pass "SKILL.md Schema-aware row: the card tree is still reachable by the toggle"
  else
    fail "SKILL.md Schema-aware row: the card tree is not described as reachable by the toggle"
  fi

  # Invariant: the row keeps everything it already said about the card view.
  for lit in \
    'node card' \
    'dependency badge' \
    'status pill' \
    'focus banner' \
    'cytoscape' \
    'dagre'; do
    if matches_f "$skill_schema_row" "$lit"; then
      pass "SKILL.md Schema-aware row: existing claim intact — $lit"
    else
      fail "SKILL.md Schema-aware row: existing claim lost — $lit"
    fi
  done

  assert_no_sibling_reference "$skill_schema_row" "SKILL.md Schema-aware row"
fi

# =============================================================================
# Clause 2: served pages update themselves in place
# =============================================================================

check_live_update_prose() { # <haystack> <label prefix>
  local region="$1" what="$2"

  if [ -z "$region" ]; then
    fail "$what: the region could not be located — the live-update clauses cannot be checked"
    return
  fi

  if matches "$region" 'updates? (itself|themselves|in place)|in place|live[- ]updat|re-render'; then
    pass "$what: says a served page updates itself in place"
  else
    fail "$what: does not say a served page updates itself in place"
  fi

  has "$region" 'poll' "$what: names polling as the mechanism"
  has "$region" 'etag|if-none-match|/raw' "$what: names the conditional-request mechanism (ETag/If-None-Match//raw)"
  has "$region" '1\.5' "$what: gives the ~1.5s cadence"

  if matches "$region" '(draft|composer)[^.]{0,90}(never destroy|not destroy|preserv|held|hold|until[^.]{0,25}clos)|(never destroy|not destroy|preserv|held|hold)[^.]{0,90}(draft|composer)'; then
    pass "$what: says an open annotation draft is never destroyed (updates held until the composer closes)"
  else
    fail "$what: does not say an open annotation draft is never destroyed"
  fi

  if matches "$region" 'file://[^.]{0,90}(no|not|never|without)[^.]{0,40}poll|(no|not|never|without)[^.]{0,40}poll[^.]{0,90}file://'; then
    pass "$what: says a file:// open does not poll"
  else
    fail "$what: does not say a file:// open is exempt from polling"
  fi

  assert_no_sibling_reference "$region" "$what"
}

check_live_update_prose "$readme_live_region" "README live-update prose"
check_live_update_prose "$skill_usage_region" "SKILL.md usage/view prose"

# Invariants named by the SKILL.md contract: the sections it must leave alone.
for lit in \
  'The composer emits exactly this annotation vocabulary' \
  'Automatic rendering at checkpoints is gated by plugin presence' \
  '| Missing input / template / parser | Exit 1, message on stderr, no output written |' \
  'Do not add network fetches to the template or server; no CDNs, no web fonts.'; do
  if matches_f "$skill_stripped" "$lit"; then
    pass "SKILL.md: untouched section intact — $lit"
  else
    fail "SKILL.md: untouched section changed or lost — $lit"
  fi
done

# =============================================================================
# Clause 3: the version legs
# =============================================================================

if ! command -v jq > /dev/null 2>&1; then
  fail "jq not found — the version legs cannot be checked"
else
  pj_version="$(jq -r '.version' "$PLUGIN_JSON")"
  if [ -z "$pj_version" ] || [ "$pj_version" = "null" ]; then
    fail "plugin.json: version missing or unparseable"
  elif [ "$(printf '%s\n%s\n' "$VERSION_FLOOR" "$pj_version" | sort -V | head -1)" = "$VERSION_FLOOR" ]; then
    pass "plugin.json: version is $pj_version (>= $VERSION_FLOOR)"
  else
    fail "plugin.json: version is '$pj_version', expected $VERSION_FLOOR or later"
  fi

  # Anchored on the render-doc row so a sibling plugin's row can never satisfy
  # it. readme-lint pairs this cell with plugin.json, so both legs are pinned:
  # the floor (this block's bump actually happened) and the agreement (the two
  # never drift apart).
  root_row="$(grep -E '^\| *\[render-doc\]\(plugins/render-doc/\) *\|' "$ROOT_README" || true)"
  if [ -z "$root_row" ]; then
    fail "root README: render-doc plugins-table row not found — the version cell cannot be checked"
  else
    pass "root README: render-doc plugins-table row found"
    root_row_version="$(printf '%s' "$root_row" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -z "$root_row_version" ]; then
      fail "root README: render-doc row has no vX.Y.Z version cell"
    elif [ "$(printf '%s\n%s\n' "$VERSION_FLOOR" "${root_row_version#v}" | sort -V | head -1)" = "$VERSION_FLOOR" ]; then
      pass "root README: render-doc row version is $root_row_version (>= v$VERSION_FLOOR)"
    else
      fail "root README: render-doc row version is '$root_row_version', expected v$VERSION_FLOOR or later"
    fi
    if [ "$root_row_version" = "v$pj_version" ]; then
      pass "root README: render-doc row version $root_row_version matches plugin.json"
    else
      fail "root README: render-doc row version is '${root_row_version:-missing}', expected v$pj_version to match plugin.json"
    fi
  fi
fi

# =============================================================================
# Left to acceptance review
# =============================================================================
# Whether the new prose is ACCURATE — that the page really does open in the
# graph view and really does update itself the way the paragraph describes — is
# a reading of the shipped template against the shipped docs, which the
# orchestrator does at acceptance. These anchors prove the claims are present
# and in the right place, not that they are true.

# --- Summary ------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'graph-always-docs.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'graph-always-docs.test.sh: all assertions passed\n'
