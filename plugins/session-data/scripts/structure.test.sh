#!/bin/bash
# <!--
# Contract: B04 structure-tests
#
# Behavior:
#   Validates the structural integrity of the session-data plugin:
#   plugin.json validity and required fields, SKILL.md frontmatter
#   correctness, marketplace.json alignment, and resolve-paths.sh
#   existence and git-index executability. Uses the same check()/FAILED
#   pattern as other plugins' structure tests.
#
# Inputs:
#   The plugin's committed files. No arguments, no env vars, no network.
#
# Outputs:
#   One PASS or FAIL line per check. Summary line "ALL PASS" (exit 0) or
#   "FAILURES" (exit 1).
#
# Errors:
#   - Missing prerequisite (jq): FAIL on the prerequisite check
#   - Missing files: FAIL per missing file
#   - Invalid JSON: FAIL with diagnostic
#   - Mismatched fields: FAIL with got/expected
#
# Invariants:
#   - Read-only: never modifies any file or git state
#   - Hermetic: reads only the repo's own files, no network, cwd-independent
#   - Uses the same check()/FAILED/exit pattern as other structure.test.sh
#     files in this repo for consistency
#
# Edge cases:
#   - jq not available: FAIL on prerequisite, remaining checks still run
#     where possible
#   - Plugin directory exists but files are missing: FAIL per file
#   - SKILL.md frontmatter malformed: FAIL on parse check
# -->

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
SKILL_MD="$PLUGIN_ROOT/skills/paths/SKILL.md"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
RESOLVE_PATHS="$PLUGIN_ROOT/scripts/resolve-paths.sh"

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

# Whether $1 (a SKILL.md path) opens with a bare '---' line on line 1 and
# closes the frontmatter block with a second bare '---' line somewhere after
# it. "yes"/"no".
frontmatter_ok() {
  local file="$1"
  [[ -f "$file" ]] || { echo no; return; }
  [[ "$(sed -n '1p' "$file")" == "---" ]] || { echo no; return; }
  local close_line
  close_line=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$file")
  [[ -n "$close_line" ]] && echo yes || echo no
}

# The lines strictly between the first two '---' delimiters of $1.
frontmatter_body() {
  local file="$1"
  local close_line
  close_line=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$file")
  [[ -n "$close_line" && "$close_line" -gt 2 ]] || return 0
  sed -n "2,$((close_line - 1))p" "$file"
}

# frontmatter_field <file> <field> -> the field's value, first match, with
# a wrapping pair of single or double quotes stripped.
frontmatter_field() {
  local file="$1" field="$2"
  frontmatter_body "$file" \
    | sed -n "s/^${field}: *//p" \
    | head -n1 \
    | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugins/session-data/ exists" \
  "$([ -d "$PLUGIN_ROOT" ] && echo yes || echo no)" "yes"
check "plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "skills/paths/SKILL.md exists" \
  "$([ -f "$SKILL_MD" ] && echo yes || echo no)" "yes"
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

pj_author_name=$(jq -r '.author.name // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .author has a name field" \
  "$(nonblank "$pj_author_name")" "yes"

pj_author_email=$(jq -r '.author.email // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .author has an email field" \
  "$(nonblank "$pj_author_email")" "yes"

# ---------------------------------------------------------------------------
# 2. Marketplace alignment
# ---------------------------------------------------------------------------

pj_author=$(jq -Sc '.author' "$PLUGIN_JSON" 2>/dev/null)
mp_owner=$(jq -Sc '.owner' "$MARKETPLACE" 2>/dev/null)
check "plugin.json .author matches the marketplace .owner (single source of truth)" \
  "$([[ -n "$pj_author" && "$pj_author" == "$mp_owner" ]] && echo yes || echo no)" "yes"

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

mp_entry=$(jq -c '.plugins[] | select(.name == "session-data")' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json has an entry with .name == 'session-data'" \
  "$([ -n "$mp_entry" ] && echo yes || echo no)" "yes"

mp_source=$(jq -r '.source // empty' <<<"$mp_entry" 2>/dev/null)
check "marketplace.json session-data entry's .source resolves to a real directory" \
  "$([ -n "$mp_source" ] && [ -d "$REPO_ROOT/$mp_source" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 3. SKILL.md frontmatter structure
# ---------------------------------------------------------------------------

fm_ok="$(frontmatter_ok "$SKILL_MD")"
check "SKILL.md frontmatter parses (opens/closes with a bare ---)" "$fm_ok" "yes"

fm_name="$(frontmatter_field "$SKILL_MD" name)"
check "SKILL.md frontmatter name is 'paths'" "$fm_name" "paths"

fm_desc="$(frontmatter_field "$SKILL_MD" description)"
check "SKILL.md frontmatter description is non-empty" \
  "$(nonblank "$fm_desc")" "yes"

# ---------------------------------------------------------------------------
# 4. Skill name convention: "paths", not "session-data-paths"
# ---------------------------------------------------------------------------

check "SKILL.md skill name does not repeat/contain the plugin name 'session-data'" \
  "$(grep -qi 'session-data' <<<"$fm_name" && echo contains || echo ok)" "ok"

# ---------------------------------------------------------------------------
# 5. resolve-paths.sh existence and executability
# ---------------------------------------------------------------------------

check "resolve-paths.sh exists" \
  "$([ -f "$RESOLVE_PATHS" ] && echo yes || echo no)" "yes"

check "resolve-paths.sh is executable" \
  "$([ -x "$RESOLVE_PATHS" ] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
