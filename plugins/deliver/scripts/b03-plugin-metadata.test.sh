#!/bin/bash
# Structural/contract tests for B03 deliver-plugin-skeleton's metadata and
# documentation artifacts: plugin.json, hooks.json, and README.md. The
# executable hook behavior itself is covered separately in
# b03-deliver-context.test.sh.
#
# Covers plugins/deliver/.claude-plugin/plugin.json:
#   - valid JSON; name "deliver"; non-empty single-line description free of
#     TODO/NotImplemented placeholders; version present
#   - author matches the marketplace .owner in the repo-root
#     .claude-plugin/marketplace.json (single source of truth)
#
# Covers plugins/deliver/hooks/hooks.json:
#   - valid JSON
#   - wires a SessionStart hook whose command points at
#     ${CLAUDE_PLUGIN_ROOT}/scripts/deliver-context.sh with a positive timeout
#   - deliver-context.sh exists and is executable
#
# Covers plugins/deliver/README.md:
#   - H1 "# deliver" with a non-empty, non-placeholder intro paragraph (no
#     TODO/NotImplemented marker)
#   - the six PLUGIN_README_TEMPLATE.md H2 sections (Getting started, What
#     to expect, Common workflows, Commands, Relationships to other
#     plugins, Uninstalling) appear, in that order
#   - facts carried over from the pre-restructure README, checked
#     body-wide since placement under the new structure is the
#     implementer's freedom: /deliver:sync-pr named; deliver-context.sh and
#     SessionStart named
#   - no hard-dependency wording on companion plugins (invariant: companions
#     are optional enhancers)
#
# plugin.json and hooks.json are declarative data the scaffold already wrote
# in full (no "NotImplemented" body is possible for static JSON) — these
# checks are legitimately green against the current stub. README.md instead
# carries a real "NotImplemented: B03" placeholder body and MUST fail here
# until real prose replaces it.
#
# Run: bash plugins/deliver/scripts/b03-plugin-metadata.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
HOOK_SCRIPT="$PLUGIN_ROOT/scripts/deliver-context.sh"
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

# Extracts the body of a level-2 markdown section: everything after a line
# that matches $2 exactly, up to (not including) the next "## " heading or
# end of file.
section_body() { # file heading_line_exact
  awk -v heading="$2" '
    $0 == heading {found=1; next}
    found && /^## / {exit}
    found {print}
  ' "$1"
}

# ---------------------------------------------------------------------------
# plugin.json
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

name=$(jq -r '.name' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .name is 'deliver'" "$name" "deliver"

version=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is present and non-empty" \
  "$([[ -n "$version" && "$version" != "null" ]] && echo yes || echo no)" "yes"

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
# hooks.json
# ---------------------------------------------------------------------------

check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

hook_command=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$HOOKS_JSON" 2>/dev/null)
check "hooks.json wires SessionStart to deliver-context.sh via CLAUDE_PLUGIN_ROOT" \
  "$hook_command" '${CLAUDE_PLUGIN_ROOT}/scripts/deliver-context.sh'

hook_timeout=$(jq -r '.hooks.SessionStart[0].hooks[0].timeout' "$HOOKS_JSON" 2>/dev/null)
check "hooks.json SessionStart hook has a positive numeric timeout" \
  "$([[ "$hook_timeout" =~ ^[0-9]+$ ]] && [[ "$hook_timeout" -gt 0 ]] && echo yes || echo no)" "yes"

check "deliver-context.sh exists" "$([ -f "$HOOK_SCRIPT" ] && echo yes || echo no)" "yes"
check "deliver-context.sh is executable" "$([ -x "$HOOK_SCRIPT" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# README.md — intro paragraph
# ---------------------------------------------------------------------------

intro=$(awk '
  $0 == "# deliver" {found=1; next}
  found && /^## / {exit}
  found {print}
' "$README")

check "README has a non-empty intro paragraph under the # deliver heading" \
  "$(nonblank "$intro")" "yes"
check "README intro paragraph has no TODO/NotImplemented placeholder" \
  "$(printf '%s' "$intro" | grep -qiE 'TODO|NotImplemented' && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# README.md — required template H2 sections, in order
# ---------------------------------------------------------------------------
# The B08 restructure moves this README onto PLUGIN_README_TEMPLATE.md's
# locked section set. The old headings ("## Purpose", "## Companion
# plugins", "## Delivery lifecycle", "## Skills", "## Hook", "## Standing
# instructions") do not survive it, so this suite stops asserting on them
# by name. What it asserts here: the six template H2s appear, in template
# order (extra plugin-specific H2s elsewhere in the file are the
# implementer's freedom, per the template).

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
# Everything the old "## Skills" / "## Hook" / "## Standing instructions"
# sections required is still required here, unweakened — just checked over
# the whole rendered body instead of a named section, since where the
# restructure relocates each fact is the implementer's call. Stripped of
# any HTML contract docblocks first (this README currently carries none,
# but stripping is defensive and matches the convention used elsewhere in
# this repo): a fact must be STATED in the rendered README, not merely
# present in a docblock's own contract prose.

readme_body_facts=$(sed '/<!--/,/-->/d' "$README")

check "README names /deliver:sync-pr" \
  "$(has "$readme_body_facts" '/deliver:sync-pr')" "yes"
check "README names deliver-context.sh" \
  "$(has "$readme_body_facts" 'deliver-context.sh')" "yes"
check "README names the SessionStart event" \
  "$(has "$readme_body_facts" 'SessionStart')" "yes"

# ---------------------------------------------------------------------------
# README.md — whole-file invariant: no hard dependency on companion plugins
# ---------------------------------------------------------------------------

readme_body=$(cat "$README")
check "README does not state a hard dependency on any companion plugin" \
  "$(printf '%s' "$readme_body" | grep -qiE 'requires (the )?(landing|lego|tracking) plugin|(landing|lego|tracking) plugin is required' && echo present || echo absent)" "absent"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
