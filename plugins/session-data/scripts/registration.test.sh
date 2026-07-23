#!/bin/bash
# Structural/contract tests for B03 plugin-registration.
#
# Source of truth: the "B03 — plugin-registration" contract in
# .local/unit.md — "Valid plugin.json with required fields; marketplace.json
# entry with name, source, description; author matches marketplace owner".
#
# Covers plugins/session-data/.claude-plugin/plugin.json:
#   - exists; valid JSON; has the required fields (name, description,
#     version, author); .name is "session-data"; .version is non-empty;
#     .description is non-empty and not a TODO/NotImplemented placeholder;
#     .author has both name and email fields
#
# Covers the repo-root .claude-plugin/marketplace.json:
#   - exists; valid JSON; has an entry with .name == "session-data"; that
#     entry's .source resolves to a real directory; plugin.json .author
#     matches the marketplace .owner (single source of truth, not a
#     hardcoded copy)
#
# plugin.json is pure metadata (not behavioral code), so it is already
# fully implemented — these tests are expected to PASS against the current
# state, not fail red. They verify the metadata is correct, not that an
# implementation is missing.
#
# Tests only the public artifacts (JSON fields) — never runtime behavior.
# Hermetic: reads only the repo's own committed files, no network, no
# mutation, cwd-independent (all paths resolved from this script's own
# location).
#
# Run: bash plugins/session-data/scripts/registration.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugins/session-data/ exists" \
  "$([ -d "$PLUGIN_ROOT" ] && echo yes || echo no)" "yes"
check "plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 1. plugin.json validity
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

check "plugin.json has the required fields (name, description, version, author)" \
  "$(jq -e 'has("name") and has("description") and has("version") and has("author")' "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

pj_name=$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .name is 'session-data'" "$pj_name" "session-data"

pj_version=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is non-empty" \
  "$([ -n "$pj_version" ] && echo yes || echo no)" "yes"

pj_description=$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is non-empty" \
  "$([ -n "$pj_description" ] && echo yes || echo no)" "yes"
check "plugin.json .description is not a TODO/NotImplemented placeholder" \
  "$(grep -qiE 'TODO|NotImplemented' <<<"$pj_description" && echo placeholder || echo ok)" "ok"

check "plugin.json .author has a 'name' field" \
  "$(jq -e '.author | has("name")' "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "plugin.json .author has an 'email' field" \
  "$(jq -e '.author | has("email")' "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 2. Marketplace alignment
# ---------------------------------------------------------------------------

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

mp_entry=$(jq -c '.plugins[]? | select(.name == "session-data")' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json has an entry with .name == 'session-data'" \
  "$([ -n "$mp_entry" ] && echo yes || echo no)" "yes"

mp_source=$(jq -r '.plugins[]? | select(.name == "session-data") | .source // empty' "$MARKETPLACE" 2>/dev/null)
mp_source_dir=""
if [[ -n "$mp_source" ]]; then
  mp_source_dir="$REPO_ROOT/${mp_source#./}"
fi
check "marketplace.json 'session-data' entry's .source resolves to a real directory" \
  "$([[ -n "$mp_source_dir" && -d "$mp_source_dir" ]] && echo yes || echo no)" "yes"

pj_author=$(jq -Sc '.author' "$PLUGIN_JSON" 2>/dev/null)
mp_owner=$(jq -Sc '.owner' "$MARKETPLACE" 2>/dev/null)
check "plugin.json .author matches the marketplace .owner (single source of truth)" \
  "$([[ -n "$pj_author" && "$pj_author" == "$mp_owner" ]] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
