#!/bin/bash
# Structural/contract tests for B01 plugin-manifest.
#
# Covers plugins/worktrees/.claude-plugin/plugin.json:
#   - valid JSON; name "worktrees"; version "0.1.0"
#   - author matches the marketplace .owner in the repo-root
#     .claude-plugin/marketplace.json (single source of truth, not a
#     hardcoded copy)
#   - description is real: non-empty, single-line, no TODO/NotImplemented
#     placeholder marker
#
# Covers plugins/worktrees/README.md:
#   - non-placeholder intro paragraph under the "# worktrees" heading (no
#     TODO/NotImplemented marker)
#   - the six PLUGIN_README_TEMPLATE.md H2 sections (Getting started, What
#     to expect, Common workflows, Commands, Relationships to other
#     plugins, Uninstalling) appear, in that order
#   - facts carried over from the pre-restructure README, checked
#     body-wide since placement under the new structure is the
#     implementer's freedom: the upstream repo (github.com/cjdubb/
#     git-helpers) named; the setup.sh install mechanism named; git-helpers
#     is never installed by this plugin; the absent-git-helpers "degrades
#     to instructions, not a hard failure" edge case; the `usage` and
#     `per-worker` skills named; requires/provides/consumes style
#   - the "installing changes nothing globally" invariant, stated somewhere
#     in the README
#   - no machine-specific absolute paths (e.g. /home/<user>, /Users/<user>)
#     anywhere in the README
#   - if a marketplace.json worktrees entry exists (B04), it has no version
#     field (plugin.json is the single source of truth for version)
#
# Tests only the public artifacts (JSON fields, section headings, semantic
# anchor terms) — never implementation-internal structure. Hermetic: reads
# only the repo's own committed files, no network, no mutation, cwd-
# independent (all paths resolved from the script's own location).
#
# Run: bash plugins/worktrees/scripts/b01-manifest.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
README="$PLUGIN_ROOT/README.md"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Extracts the body of a level-2 markdown section: everything after a line
# that matches $2 exactly, up to (not including) the next "## " heading or
# end of file. Used to scope semantic-anchor assertions to the right section
# rather than matching anywhere in the file.
section_body() { # file heading_line_exact
  awk -v heading="$2" '
    $0 == heading {found=1; next}
    found && /^## / {exit}
    found {print}
  ' "$1"
}

nonblank() { # string -> "yes"/"no"
  if [[ -n "$(printf '%s' "$1" | tr -d '[:space:]')" ]]; then echo yes; else echo no; fi
}

# ---------------------------------------------------------------------------
# plugin.json
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

name=$(jq -r '.name' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .name is 'worktrees'" "$name" "worktrees"

version=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is non-empty and well-formed semver (X.Y.Z)" \
  "$([[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" "yes"

description=$(jq -r '.description' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is non-empty and free of TODO/NotImplemented markers" \
  "$([[ -n "$description" && "$description" != "null" ]] && ! grep -qiE 'TODO|NotImplemented' <<<"$description" && echo yes || echo no)" "yes"
check "plugin.json .description is a single line (no embedded newline)" \
  "$([[ "$description" != *$'\n'* ]] && echo yes || echo no)" "yes"

plugin_author=$(jq -Sc '.author' "$PLUGIN_JSON" 2>/dev/null)
marketplace_owner=$(jq -Sc '.owner' "$MARKETPLACE" 2>/dev/null)
check "plugin.json .author matches the marketplace .owner (single source of truth)" \
  "$([[ -n "$plugin_author" && "$plugin_author" == "$marketplace_owner" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# README.md — intro paragraph
# ---------------------------------------------------------------------------

intro=$(awk '
  $0 == "# worktrees" {found=1; next}
  found && /^## / {exit}
  found {print}
' "$README")

check "README has a non-empty intro paragraph under the # worktrees heading" \
  "$(nonblank "$intro")" "yes"
check "README intro paragraph has no TODO/NotImplemented placeholder" \
  "$(printf '%s' "$intro" | grep -qiE 'TODO|NotImplemented' && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# README.md — required template H2 sections, in order
# ---------------------------------------------------------------------------
# The plugin-readme-conformance restructure (B17) moves this README onto
# PLUGIN_README_TEMPLATE.md's locked section set. The old headings ("##
# Prerequisite: git-helpers", "## Skills", "## Dependencies") do not survive
# it, so this suite stops asserting on them by name. What it asserts here:
# the six template H2s appear, in template order (extra plugin-specific H2s
# elsewhere in the file are the implementer's freedom, per the template).

expected_h2_order="## Getting started
## What to expect
## Common workflows
## Commands
## Relationships to other plugins
## Uninstalling"

actual_h2_order=$(grep '^## ' "$README" | grep -Fxf <(printf '%s\n' "$expected_h2_order"))

check "README's six required template H2 sections appear, in template order" \
  "$actual_h2_order" "$expected_h2_order"

# ---------------------------------------------------------------------------
# README.md — facts carried over from the old sections (location-agnostic)
# ---------------------------------------------------------------------------
# Everything the old "## Prerequisite: git-helpers" / "## Skills" / "##
# Dependencies" sections required is still required here, unweakened — just
# checked over the whole rendered body instead of a named section, since
# where the restructure relocates each fact is the implementer's call.
# Stripped of the HTML contract docblocks first, same rationale as the
# whole-file invariants below: a fact must be STATED in the rendered
# README, not merely present in a docblock's own contract prose.

readme_body_facts=$(sed '/<!--/,/-->/d' "$README")

check "README names the upstream repo (github.com/cjdubb/git-helpers)" \
  "$(printf '%s' "$readme_body_facts" | grep -qiF 'cjdubb/git-helpers' && echo yes || echo no)" "yes"
check "README points at the setup.sh install mechanism" \
  "$(printf '%s' "$readme_body_facts" | grep -qiF 'setup.sh' && echo yes || echo no)" "yes"
check "README states git-helpers is never installed by this plugin" \
  "$(printf '%s' "$readme_body_facts" | grep -qiE "never install|not install|does not install|won.t install" && echo yes || echo no)" "yes"
check "README covers the absent-git-helpers degrade (not hard-fail) edge case" \
  "$(printf '%s' "$readme_body_facts" | grep -qi 'degrad' && echo yes || echo no)" "yes"
check "README names the 'usage' skill" \
  "$(printf '%s' "$readme_body_facts" | grep -qiw 'usage' && echo yes || echo no)" "yes"
check "README names the 'per-worker' skill" \
  "$(printf '%s' "$readme_body_facts" | grep -qiw 'per-worker' && echo yes || echo no)" "yes"
check "README is in requires/provides/consumes style (all three terms present)" \
  "$(printf '%s' "$readme_body_facts" | grep -qiw 'requires' \
     && printf '%s' "$readme_body_facts" | grep -qiw 'provides' \
     && printf '%s' "$readme_body_facts" | grep -qiw 'consumes' \
     && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# README.md — whole-file invariants
# ---------------------------------------------------------------------------

readme_content=$(cat "$README")
# The contract docblocks at the top of the README are HTML comments that
# persist in the file (they describe the contract itself, and even contain
# the phrase "changes nothing globally" verbatim) — strip them before
# asserting the invariant is actually STATED in the rendered README, not
# merely present anywhere in the file, so this check can't pass vacuously
# off the docblock's own contract prose.
readme_body=$(sed '/<!--/,/-->/d' "$README")

check "README states installing the plugin changes nothing globally" \
  "$(printf '%s' "$readme_body" | grep -qiF 'nothing globally' && echo yes || echo no)" "yes"

# The absolute-paths invariant says "anywhere" — deliberately checked against
# the FULL file (docblocks included), unlike the check above.
check "README contains no machine-specific absolute paths (/home/<user> or /Users/<user>)" \
  "$(printf '%s' "$readme_content" | grep -qE '/(home|Users)/[A-Za-z0-9_.-]+' && echo present || echo absent)" "absent"

# Version single-source-of-truth invariant: if the marketplace already has a
# worktrees entry (B04's job), it must NOT carry a version field — plugin.json
# is the single source of truth. B01 alone doesn't create that entry, so this
# is a no-op pass until B04 runs — it still pins the invariant for whenever
# the entry appears.
mp_entry_exists=$(jq -r '[.plugins[]? | select(.name=="worktrees")] | length' "$MARKETPLACE" 2>/dev/null)
if [[ "$mp_entry_exists" -gt 0 ]]; then
  check "marketplace.json worktrees entry has no version field (plugin.json is source of truth)" \
    "$(jq -r '.plugins[]? | select(.name=="worktrees") | has("version")' "$MARKETPLACE" 2>/dev/null)" "false"
else
  echo "SKIP  no marketplace.json worktrees entry yet (B04 not run) - version-field invariant not yet applicable"
fi

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
