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
#   - non-placeholder intro paragraph under the "# worktrees" heading
#   - "## Prerequisite: git-helpers" section: names the upstream repo
#     (github.com/cjdubb/git-helpers), points at the setup.sh install
#     mechanism, states git-helpers is never installed by this plugin, and
#     covers the absent-git-helpers "degrades to instructions, not a hard
#     failure" edge case
#   - "## Skills" section names both the `usage` and `per-worker` skills
#   - "## Dependencies" section in requires/provides/consumes style
#   - the "installing changes nothing globally" invariant, stated somewhere
#     in the README
#   - no machine-specific absolute paths (e.g. /home/<user>, /Users/<user>)
#     anywhere in the README
#   - no section is left with a TODO/NotImplemented placeholder body
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
check "plugin.json .version is '0.1.0'" "$version" "0.1.0"

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
# README.md — ## Prerequisite: git-helpers
# ---------------------------------------------------------------------------

prereq=$(section_body "$README" "## Prerequisite: git-helpers")

check "README has a '## Prerequisite: git-helpers' section with content" \
  "$(nonblank "$prereq")" "yes"
check "Prerequisite section names the upstream repo (github.com/cjdubb/git-helpers)" \
  "$(printf '%s' "$prereq" | grep -qiF 'cjdubb/git-helpers' && echo yes || echo no)" "yes"
check "Prerequisite section points at the setup.sh install mechanism" \
  "$(printf '%s' "$prereq" | grep -qiF 'setup.sh' && echo yes || echo no)" "yes"
check "Prerequisite section states git-helpers is never installed by this plugin" \
  "$(printf '%s' "$prereq" | grep -qiE "never install|not install|does not install|won.t install" && echo yes || echo no)" "yes"
check "Prerequisite section covers the absent-git-helpers degrade (not hard-fail) edge case" \
  "$(printf '%s' "$prereq" | grep -qi 'degrad' && echo yes || echo no)" "yes"
check "Prerequisite section has no TODO/NotImplemented placeholder" \
  "$(printf '%s' "$prereq" | grep -qiE 'TODO|NotImplemented' && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# README.md — ## Skills
# ---------------------------------------------------------------------------

skills=$(section_body "$README" "## Skills")

check "README has a '## Skills' section with content" \
  "$(nonblank "$skills")" "yes"
check "Skills section names the 'usage' skill" \
  "$(printf '%s' "$skills" | grep -qiw 'usage' && echo yes || echo no)" "yes"
check "Skills section names the 'per-worker' skill" \
  "$(printf '%s' "$skills" | grep -qiw 'per-worker' && echo yes || echo no)" "yes"
check "Skills section has no TODO/NotImplemented placeholder" \
  "$(printf '%s' "$skills" | grep -qiE 'TODO|NotImplemented' && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# README.md — ## Dependencies
# ---------------------------------------------------------------------------

deps=$(section_body "$README" "## Dependencies")

check "README has a '## Dependencies' section with content" \
  "$(nonblank "$deps")" "yes"
check "Dependencies section is in requires/provides/consumes style (all three terms present)" \
  "$(printf '%s' "$deps" | grep -qiw 'requires' \
     && printf '%s' "$deps" | grep -qiw 'provides' \
     && printf '%s' "$deps" | grep -qiw 'consumes' \
     && echo yes || echo no)" "yes"
check "Dependencies section has no TODO/NotImplemented placeholder" \
  "$(printf '%s' "$deps" | grep -qiE 'TODO|NotImplemented' && echo present || echo absent)" "absent"

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
