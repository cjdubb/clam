#!/bin/bash
# Structural/contract tests for the build plugin's metadata and
# documentation artifacts: plugin.json and README.md. The skill's own
# content is covered separately in b09-context-skill.test.sh.
#
# Contract: B02 test-rename
#
# Behavior:
#   All assertions reference the new plugin name "build". Path variables
#   point to the renamed locations. Test logic and coverage are unchanged
#   from the original — this is a rename of references, not a test
#   rewrite.
#
# Invariants:
#   - No remaining references to "deliver" as a plugin name, script name,
#     or skill namespace in assertions or path variables
#   - All existing test cases preserved (no coverage regression)
#
# Contract: B06 build-cleanup
#
# Behavior:
#   The sync-pr skill and its standing instruction are removed. The
#   plugin.json description and the README no longer name /build:sync-pr,
#   PR description syncing, the gh CLI prerequisite, or any standing
#   instruction — assertions on those points now check for ABSENCE.
#
# Contract: B09 build-skill-conversion
#
# Behavior:
#   The SessionStart hook (hooks/hooks.json, scripts/build-context.sh) is
#   removed entirely — no replacement hook, no pointer hook. The prior
#   hooks.json/build-context.sh coverage in this suite is replaced with
#   ABSENCE checks. The README no longer describes a SessionStart hook as
#   current behavior; it describes the on-demand /build:context skill
#   instead. plugin.json is out of scope for B09 (no version bump, no
#   description change) — its checks are unchanged from B06.
#
# Covers plugins/build/.claude-plugin/plugin.json:
#   - valid JSON; name "build"; non-empty single-line description free of
#     TODO/NotImplemented placeholders; version present
#   - author matches the marketplace .owner in the repo-root
#     .claude-plugin/marketplace.json (single source of truth)
#   - description has no reference to the removed sync-pr skill (B06)
#
# Covers hooks removal (B09):
#   - plugins/build/hooks/hooks.json exists (F06 routing hook)
#   - plugins/build/scripts/build-context.sh does not exist
#
# Covers plugins/build/README.md:
#   - H1 "# build" with a non-empty, non-placeholder intro paragraph (no
#     TODO/NotImplemented marker)
#   - the six PLUGIN_README_TEMPLATE.md H2 sections (Getting started, What
#     to expect, Common workflows, Commands, Relationships to other
#     plugins, Uninstalling) appear, in that order
#   - (B06) no reference to sync-pr, PR description syncing, the gh CLI
#     prerequisite, or standing-instruction language anywhere in the body
#   - (B09) no reference to build-context.sh; (F06) routing pointer described
#     as current behavior; names /build:context instead
#   - no hard-dependency wording on companion plugins (invariant: companions
#     are optional enhancers)
#
# Run: bash plugins/build/scripts/b03-plugin-metadata.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
HOOK_SCRIPT="$PLUGIN_ROOT/scripts/build-context.sh"
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

nonblank() { # string -> "yes"/"no"
  if [[ -n "$(printf '%s' "$1" | tr -d '[:space:]')" ]]; then echo yes; else echo no; fi
}

has() { # haystack needle (case-insensitive fixed-string)
  printf '%s' "$1" | grep -qiF -- "$2" && echo yes || echo no
}

# ---------------------------------------------------------------------------
# plugin.json (out of scope for B09 — unchanged from B06)
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

name=$(jq -r '.name' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .name is 'build'" "$name" "build"

version=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is present and non-empty" \
  "$([[ -n "$version" && "$version" != "null" ]] && echo yes || echo no)" "yes"

description=$(jq -r '.description' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is non-empty and free of TODO/NotImplemented markers" \
  "$([[ -n "$description" && "$description" != "null" ]] && ! grep -qiE 'TODO|NotImplemented' <<<"$description" && echo yes || echo no)" "yes"
check "plugin.json .description is a single line (no embedded newline)" \
  "$([[ "$description" != *$'\n'* ]] && echo yes || echo no)" "yes"
check "plugin.json .description has no reference to the removed sync-pr skill (B06)" \
  "$(printf '%s' "$description" | grep -qiF 'sync-pr' && echo present || echo absent)" "absent"

plugin_author=$(jq -Sc '.author' "$PLUGIN_JSON" 2>/dev/null)
marketplace_owner=$(jq -Sc '.owner' "$MARKETPLACE" 2>/dev/null)
check "plugin.json .author matches the marketplace .owner (single source of truth)" \
  "$([[ -n "$plugin_author" && "$plugin_author" == "$marketplace_owner" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# hooks removal (B09): the plugin registers no hooks at all
# ---------------------------------------------------------------------------

check "hooks/hooks.json exists (F06: SessionStart routing pointer)" \
  "$([ -f "$HOOKS_JSON" ] && echo present || echo absent)" "present"
check "scripts/build-context.sh does not exist (B09: framing hook stays removed)" \
  "$([ -f "$HOOK_SCRIPT" ] && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# README.md — intro paragraph
# ---------------------------------------------------------------------------

intro=$(awk '
  $0 == "# build" {found=1; next}
  found && /^## / {exit}
  found {print}
' "$README")

check "README has a non-empty intro paragraph under the # build heading" \
  "$(nonblank "$intro")" "yes"
check "README intro paragraph has no TODO/NotImplemented placeholder" \
  "$(printf '%s' "$intro" | grep -qiE 'TODO|NotImplemented' && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# README.md — required template H2 sections, in order
# ---------------------------------------------------------------------------

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
# README.md — facts (location-agnostic), stripped of any HTML contract
# docblocks first: a fact must be STATED in the rendered README, not
# merely present in a docblock's own contract prose.
# ---------------------------------------------------------------------------

readme_body_facts=$(sed '/<!--/,/-->/d' "$README")

# Backticks stripped for the absence checks below: markdown code-span
# backticks can sit mid-phrase (e.g. "the `gh` CLI"), which would defeat a
# fixed-string match on 'gh cli' even though the prose plainly says it.
readme_body_facts_flat=$(printf '%s' "$readme_body_facts" | tr -d '`')

check "README has no reference to sync-pr (B06: skill removed, moved to forge-github)" \
  "$(has "$readme_body_facts" 'sync-pr')" "no"
check "README has no PR-description-syncing reference (B06)" \
  "$(has "$readme_body_facts" 'pr description')" "no"
check "README has no standing-instruction language (B06)" \
  "$(has "$readme_body_facts" 'standing instruction')" "no"
check "README has no gh CLI prerequisite mention (B06: tied to the removed sync-pr skill)" \
  "$(has "$readme_body_facts_flat" 'gh cli')" "no"

check "README has no reference to build-context.sh (B09: hook removed)" \
  "$(has "$readme_body_facts" 'build-context.sh')" "no"
check "README describes the session-start routing pointer (F06)" \
  "$(has "$readme_body_facts" 'routing pointer')" "yes"
check "README names /build:context (B09: on-demand skill replacement)" \
  "$(has "$readme_body_facts" '/build:context')" "yes"

# ---------------------------------------------------------------------------
# README.md — the /build:build lifecycle front door (B02)
# ---------------------------------------------------------------------------

section_body() { # heading -> that section's body, up to the next H2
  awk -v want="$1" '
    $0 == want {found=1; next}
    found && /^## / {exit}
    found {print}
  ' "$README" | sed '/<!--/,/-->/d'
}

what_to_expect=$(section_body '## What to expect')
commands=$(section_body '## Commands')

check "README names /build:build (B02: new lifecycle front door skill)" \
  "$(has "$readme_body_facts" '/build:build')" "yes"
check "README's 'What to expect' section names /build:build (B02)" \
  "$(has "$what_to_expect" '/build:build')" "yes"
check "README's 'Commands' section names /build:build (B02)" \
  "$(has "$commands" '/build:build')" "yes"
check "README describes /build:build's purpose as the lifecycle front door (B02)" \
  "$(has "$readme_body_facts" 'front door')" "yes"
check "README describes /build:build routing between resuming and starting work (B02)" \
  "$(printf '%s' "$readme_body_facts" | grep -qiE 'resume[^.]{0,120}(start|new)|(start|new)[^.]{0,120}resume' && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# README.md — whole-file invariant: no hard dependency on companion plugins
# ---------------------------------------------------------------------------

readme_body=$(cat "$README")
check "README does not state a hard dependency on any companion plugin" \
  "$(printf '%s' "$readme_body" | grep -qiE 'requires (the )?(landing|lego|tracking) plugin|(landing|lego|tracking) plugin is required' && echo present || echo absent)" "absent"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
