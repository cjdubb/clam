#!/bin/bash
# Structural/contract tests for the B05 forge-github plugin's
# documentation and metadata surfaces: README.md and plugin.json. The two
# skill behavioral contracts (create-pr, sync-pr) are covered separately
# in create-pr.test.sh and sync-pr.test.sh.
#
# README.md content checks run against the file with two things stripped,
# in order:
#   1. HTML comment blocks (the "Contract: B05 forge-github README
#      (scaffold)" docblock) -- otherwise a check could pass on the
#      unimplemented stub for the wrong reason, satisfied by the
#      docblock's own description of what to write rather than by real
#      README prose.
#   2. "**NotImplemented: B05** -- ..." placeholder paragraphs -- these
#      sit in the rendered body (not inside a comment) and already name
#      several of the exact concepts a real section must cover (e.g. the
#      Relationships placeholder already says "landing delegates forge
#      operations to this plugin when installed; this plugin never
#      requires landing"). Left unstripped, a content check for those
#      same words would already pass on the scaffold and could never go
#      red. Stripping the placeholder paragraphs empties every
#      unimplemented section, so each section's content checks can only
#      be satisfied by the real prose that replaces the placeholder.
#
# plugin.json is already complete at scaffold time (per the block brief),
# so its checks assert shape and cross-file consistency with README.md,
# the repo's marketplace.json registration, and the root README.md
# Plugins table -- not a red/green implementation gate.
# Run: bash plugins/forge-github/scripts/plugin-docs.test.sh (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
README="$PLUGIN_DIR/README.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
ROOT_README="$REPO_ROOT/README.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

nonblank() { # string -> "yes"/"no"
  if [[ -n "$(printf '%s' "$1" | tr -d '[:space:]')" ]]; then echo yes; else echo no; fi
}

strip_comments_stdin() {
  awk '/<!--/{c=1} !c{print} /-->/{c=0}'
}

# Removes "**NotImplemented: ...**"-led placeholder paragraphs: skips from
# a line starting with that marker through the next blank line.
strip_notimplemented_stdin() {
  awk '
    /^\*\*NotImplemented:/{skip=1}
    skip && /^$/{skip=0; next}
    skip{next}
    {print}
  '
}

# Removes fenced code blocks (```...```), leaving only prose.
strip_fences_stdin() {
  awk '/^```/{f=!f; next} !f{print}'
}

RAW_BODY="$(strip_comments_stdin < "$README")"                       # comments stripped only
BODY="$(printf '%s\n' "$RAW_BODY" | strip_notimplemented_stdin)"     # + placeholders stripped

# flatten: collapses internal newlines to spaces so a multi-word check
# isn't defeated by the source markdown's own 80-column hard-wrapping --
# that source-level wrapping is unrelated to the contract, which is about
# the flowing-vs-hard-wrapped shape of *composed PR descriptions*, not of
# this documentation file.
flatten() { # string
  printf '%s' "$1" | tr '\n' ' ' | tr -s ' '
}

has_literal() { # body needle
  printf '%s' "$(flatten "$1")" | grep -qF -- "$2" && echo yes || echo no
}
has_pattern_ci() { # body extended-regex
  printf '%s' "$(flatten "$1")" | grep -qiE -- "$2" && echo yes || echo no
}

section_body_of() { # body_string heading_line_exact
  printf '%s\n' "$1" | awk -v heading="$2" '
    $0 == heading {found=1; next}
    found && /^## / {exit}
    found {print}
  '
}

# ---------------------------------------------------------------------------
# README.md -- top-level structure
# ---------------------------------------------------------------------------

check "README.md exists" "$([[ -f "$README" ]] && echo yes || echo no)" "yes"
check "README.md has H1 '# forge-github'" \
  "$(head -1 "$README" 2>/dev/null)" "# forge-github"

REQUIRED_H2_ORDER=$'Getting started\nWhat to expect\nCommon workflows\nCommands\nRelationships to other plugins\nUninstalling'
ACTUAL_H2_ORDER="$(grep -E '^## (Getting started|What to expect|Common workflows|Commands|Relationships to other plugins|Uninstalling)$' "$README" 2>/dev/null | sed 's/^## //')"
check "README.md has the required H2 sections, in order (contractually fixed skeleton)" \
  "$ACTUAL_H2_ORDER" "$REQUIRED_H2_ORDER"

# Global red/green gate: no NotImplemented marker left anywhere once
# implementation is done (checked with only the docblock stripped, so the
# marker itself -- which lives in the rendered body -- is still visible
# here).
check "no NotImplemented marker anywhere in the rendered README" \
  "$(has_pattern_ci "$RAW_BODY" 'NotImplemented')" "no"

# ---------------------------------------------------------------------------
# README.md -- standing facts from the real (non-placeholder) intro
# paragraph, which must remain true after implementation (location-agnostic
# over the whole rendered body).
# ---------------------------------------------------------------------------

# literal backticked `gh`, no expansion intended
# shellcheck disable=SC2016
check "README documents the gh CLI as the mechanism" \
  "$(has_pattern_ci "$BODY" '`gh`|gh cli')" "yes"
check "README documents the flowing-prose formatting convention" \
  "$(has_pattern_ci "$BODY" 'flowing')" "yes"
check "README documents the relationship to the forge interface" \
  "$(has_pattern_ci "$BODY" 'forge interface')" "yes"
check "README documents the standalone guarantee" \
  "$(has_pattern_ci "$BODY" 'standalone')" "yes"

# ---------------------------------------------------------------------------
# README.md -- per-section content, checked against the fully stripped
# body so each check can only be satisfied by real prose, not the
# placeholder it replaces.
# ---------------------------------------------------------------------------

GS_BODY="$(section_body_of "$BODY" '## Getting started')"
check "Getting started: documents authentication as a prerequisite" \
  "$(has_pattern_ci "$GS_BODY" 'authenticat')" "yes"

WTE_BODY="$(section_body_of "$BODY" '## What to expect')"
check "What to expect: documents the Stop-hook cache refresh" \
  "$(has_pattern_ci "$WTE_BODY" 'stop hook')" "yes"
check "What to expect: names the PR-status cache file" \
  "$(has_literal "$WTE_BODY" '.pr-status.json')" "yes"

CW_BODY="$(section_body_of "$BODY" '## Common workflows')"
check "Common workflows: covers a create-pr recipe" \
  "$(has_literal "$CW_BODY" 'create-pr')" "yes"
check "Common workflows: covers a sync-pr recipe" \
  "$(has_literal "$CW_BODY" 'sync-pr')" "yes"

CMD_BODY="$(section_body_of "$BODY" '## Commands')"
check "Commands: documents /forge-github:create-pr" \
  "$(has_literal "$CMD_BODY" '/forge-github:create-pr')" "yes"
check "Commands: documents /forge-github:sync-pr" \
  "$(has_literal "$CMD_BODY" '/forge-github:sync-pr')" "yes"

REL_BODY="$(section_body_of "$BODY" '## Relationships to other plugins')"
check "Relationships: documents the forge-interface relationship" \
  "$(has_pattern_ci "$REL_BODY" 'forge interface')" "yes"
check "Relationships: names landing as the interface's delegating consumer" \
  "$(has_pattern_ci "$REL_BODY" 'landing')" "yes"
check "Relationships: states the standalone/never-requires-landing guarantee" \
  "$(has_pattern_ci "$REL_BODY" 'standalone|never require')" "yes"

UN_BODY="$(section_body_of "$BODY" '## Uninstalling')"
UN_PROSE="$(printf '%s\n' "$UN_BODY" | strip_fences_stdin)"
check "Uninstalling: has real cleanup-notes prose beyond the fenced command" \
  "$(nonblank "$UN_PROSE")" "yes"

# ---------------------------------------------------------------------------
# README.md -- invariant: no hard runtime dependency on another plugin.
# "landing" legitimately appears above (describing the interface this
# plugin implements and that landing delegates to); what must never appear
# is a runtime dependency on landing (or any other plugin) to function.
# ---------------------------------------------------------------------------

check "README states no hard dependency on any companion plugin" \
  "$(printf '%s' "$BODY" | grep -qiE 'requires (the )?(landing|lego|tracking|build) plugin|(landing|lego|tracking|build) plugin is required' && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# plugin.json -- shape
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

pj_name=$(jq -r '.name' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .name is 'forge-github'" "$pj_name" "forge-github"

pj_version=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is present and non-empty" \
  "$([[ -n "$pj_version" && "$pj_version" != "null" ]] && echo yes || echo no)" "yes"
check "plugin.json .version looks like semver (X.Y.Z)" \
  "$([[ "$pj_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" "yes"

pj_description=$(jq -r '.description' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is non-empty and free of TODO/NotImplemented markers" \
  "$([[ -n "$pj_description" && "$pj_description" != "null" ]] && ! grep -qiE 'TODO|NotImplemented' <<<"$pj_description" && echo yes || echo no)" "yes"
check "plugin.json .description is a single line (no embedded newline)" \
  "$([[ "$pj_description" != *$'\n'* ]] && echo yes || echo no)" "yes"
check "plugin.json .description has no hard-dependency phrasing on another plugin" \
  "$(printf '%s' "$pj_description" | grep -qiE 'requires (the )?(landing|lego|tracking|build) plugin|(landing|lego|tracking|build) plugin is required' && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# plugin.json -- consistency with the repo's registration expectations
# ---------------------------------------------------------------------------

pj_author=$(jq -Sc '.author' "$PLUGIN_JSON" 2>/dev/null)
mp_owner=$(jq -Sc '.owner' "$MARKETPLACE" 2>/dev/null)
check "plugin.json .author matches marketplace.json .owner (single source of truth)" \
  "$([[ -n "$pj_author" && "$pj_author" == "$mp_owner" ]] && echo yes || echo no)" "yes"

mp_name=$(jq -r '.plugins[] | select(.source == "./plugins/forge-github") | .name' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json registers forge-github at ./plugins/forge-github" "$mp_name" "forge-github"

mp_description=$(jq -r '.plugins[] | select(.name == "forge-github") | .description' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json forge-github entry has a non-empty description" \
  "$(nonblank "$mp_description")" "yes"

root_row=$(grep -F '[forge-github](plugins/forge-github/)' "$ROOT_README" 2>/dev/null)
check "root README.md has exactly one forge-github Plugins-table row" \
  "$(grep -cF '[forge-github](plugins/forge-github/)' "$ROOT_README" 2>/dev/null)" "1"
check "root README.md status cell version matches plugin.json .version" \
  "$(printf '%s' "$root_row" | grep -qF "✅ v${pj_version}" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
