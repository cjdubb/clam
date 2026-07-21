#!/bin/bash
# Structural/contract tests for B01 handover-plugin — manifest + README.
#
# Neither plugins/orchestrator-handover/.claude-plugin/plugin.json (pure
# JSON, cannot carry an HTML-comment docblock) nor
# plugins/orchestrator-handover/README.md (no Contract docblock of its own)
# carries the contract inline the way SKILL.md and template.md do. Their
# contract is the orchestrator's explicit dispatch-brief checklist for B01,
# cross-checked against the unit.md block-map summary and this repo's
# established plugin-manifest convention (see
# plugins/worktrees/scripts/b01-manifest.test.sh for the sibling pattern):
#
# plugin.json:
#   - valid JSON
#   - .name is "orchestrator-handover"
#   - .version is a well-formed, non-empty semver string
#   - .description is non-empty, single-line, free of TODO/NotImplemented
#     placeholder markers
#   - .author matches the marketplace .owner (single source of truth for
#     plugin authorship across the marketplace), with non-empty name/email
#
# README.md:
#   - exists and has non-blank content
#   - carries the "# orchestrator-handover" plugin heading
#   - documents the plugin's purpose and the /orchestrator-handover:create
#     skill (literal skill invocation string present)
#   - no machine-specific absolute paths (/home/<user> or /Users/<user>)
#   - no TODO/NotImplemented placeholder marker anywhere (checked against the
#     full raw file: unlike SKILL.md/template.md, this README carries no
#     persistent Contract docblock to strip first — its only comment is the
#     scaffold's own NotImplemented marker, which implementation must remove
#     outright, not merely rephrase inside a surviving comment)
#
# Tests only the public artifacts (JSON fields, heading text, rendered
# prose) — never implementation-internal structure. Hermetic: reads only the
# repo's own committed files, no network, no mutation, cwd-independent (all
# paths resolved from the script's own location).
#
# Run: bash plugins/orchestrator-handover/scripts/b01-manifest.test.sh
# (exits non-zero on failure)

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

nonblank() { # string -> "yes"/"no"
  if [[ -n "$(printf '%s' "$1" | tr -d '[:space:]')" ]]; then echo yes; else echo no; fi
}

# ---------------------------------------------------------------------------
# plugin.json
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

name=$(jq -r '.name' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .name is 'orchestrator-handover'" "$name" "orchestrator-handover"

version=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is a well-formed semver string" \
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

author_name=$(jq -r '.author.name // empty' "$PLUGIN_JSON" 2>/dev/null)
author_email=$(jq -r '.author.email // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .author.name is non-empty" "$([[ -n "$author_name" ]] && echo yes || echo no)" "yes"
check "plugin.json .author.email is non-empty" "$([[ -n "$author_email" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# README.md
# ---------------------------------------------------------------------------

check "README.md exists" "$([[ -f "$README" ]] && echo yes || echo no)" "yes"

readme_content=$(cat "$README" 2>/dev/null)
check "README.md has non-blank content" "$(nonblank "$readme_content")" "yes"

check "README carries the '# orchestrator-handover' plugin heading" \
  "$(grep -qxF '# orchestrator-handover' "$README" && echo yes || echo no)" "yes"

check "README documents the /orchestrator-handover:create skill (literal invocation string present)" \
  "$(grep -qF '/orchestrator-handover:create' "$README" && echo yes || echo no)" "yes"

# Purpose: some prose beyond the bare heading and skill name describing what
# the plugin does (handover between orchestrators).
check "README documents the plugin's purpose (mentions 'handover')" \
  "$(grep -qi 'handover' "$README" && echo yes || echo no)" "yes"

check "README contains no machine-specific absolute paths (/home/<user> or /Users/<user>)" \
  "$(grep -qE '/(home|Users)/[A-Za-z0-9_.-]+' "$README" && echo present || echo absent)" "absent"

check "README has no TODO/NotImplemented placeholder marker anywhere" \
  "$(grep -qiE 'TODO|NotImplemented' "$README" && echo present || echo absent)" "absent"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
