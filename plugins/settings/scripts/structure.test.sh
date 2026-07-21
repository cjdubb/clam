#!/bin/bash
# Structural/contract tests for B02 settings.
#
# Source of truth: the HTML-comment docblock labeled "Contract: B02
# settings" in plugins/settings/skills/setup/SKILL.md. This is a
# `disable-model-invocation: true` skill — its "implementation" is the
# instructional prose Claude follows at runtime, not executable code — so
# this file checks structure and content, never runtime behavior.
#
# Covers plugins/settings/.claude-plugin/plugin.json:
#   - valid JSON; has the required fields (name, description, version,
#     author); name is "settings"; version is non-empty; description is
#     non-empty and not a TODO/NotImplemented placeholder
#   - .author matches the marketplace .owner in the repo-root
#     .claude-plugin/marketplace.json (single source of truth, not a
#     hardcoded copy)
#
# Covers plugins/settings/skills/setup/SKILL.md:
#   - exists; frontmatter parses (opens/closes with a bare '---' line);
#     frontmatter `name` is "setup"; frontmatter carries
#     `disable-model-invocation: true`; frontmatter `description` is
#     non-empty
#   - skill name "setup" does not repeat/contain the plugin name "settings"
#     (repo convention, matches plugins/attribution's rule)
#   - no leftover NotImplemented marker anywhere in the raw file EXCEPT the
#     one deliberately-stub `<!-- NotImplemented: B02` line
#   - the actual instructions (the file with its HTML-comment contract
#     docblock stripped out, and further scoped to the content AFTER the
#     first H1 heading — i.e. what Claude actually reads as guidance, not
#     the contract prose describing it) mention every element the contract
#     requires an implementer to surface:
#       * both env var names: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS and
#         CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING
#       * the value "1" for both vars
#       * the `env` key/object in settings
#       * scope detection via installed_plugins.json
#       * all three scopes: user, project, local
#       * the correct settings file per scope (~/.claude/settings.json,
#         .claude/settings.json, .claude/settings.local.json)
#       * backing up the target file before writing
#       * the `remove` subcommand
#       * jq as the merge tool
#
# Scoping content checks to "after the first H1, docblock stripped" (rather
# than the whole file) matters for red discipline: the contract docblock
# itself already contains most of these terms (it's the spec), so a
# whole-file search would pass vacuously against the unimplemented stub.
# Scoping to what's left after stripping the docblock and heading means
# these checks only pass once an implementer actually writes the
# instructions body — currently that body is empty, so they correctly fail.
#
# Tests only the public artifacts (JSON fields, frontmatter, instruction
# prose) — never implementation-internal structure, and never runtime
# invocation of the skill (which is instructions for Claude, not a script).
# Hermetic: reads only the repo's own committed files, no network, no
# mutation, cwd-independent (all paths resolved from this script's own
# location).
#
# Run: bash plugins/settings/scripts/structure.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
SKILL_MD="$PLUGIN_ROOT/skills/setup/SKILL.md"
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

# The SKILL.md content Claude actually reads as guidance: the HTML-comment
# contract docblock stripped out, then scoped to everything after the first
# H1 heading (the docblock itself is prose ABOUT the contract, not the
# instructions; the frontmatter and heading aren't instructions either).
skill_instructions_body() {
  local file="$1"
  local stripped
  stripped=$(sed '/<!--/,/-->/d' "$file")
  awk '
    /^# / {found=1; next}
    found {print}
  ' <<<"$stripped"
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugins/settings/ exists" \
  "$([ -d "$PLUGIN_ROOT" ] && echo yes || echo no)" "yes"
check "plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "skills/setup/SKILL.md exists" \
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
check "plugin.json .name is 'settings'" "$pj_name" "settings"

pj_version=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is non-empty" \
  "$([ -n "$pj_version" ] && echo yes || echo no)" "yes"

pj_description=$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is non-empty" \
  "$([ -n "$pj_description" ] && echo yes || echo no)" "yes"
check "plugin.json .description is not a TODO/NotImplemented placeholder" \
  "$(grep -qiE 'TODO|NotImplemented' <<<"$pj_description" && echo placeholder || echo ok)" "ok"

# ---------------------------------------------------------------------------
# 2. Marketplace alignment
# ---------------------------------------------------------------------------

pj_author=$(jq -Sc '.author' "$PLUGIN_JSON" 2>/dev/null)
mp_owner=$(jq -Sc '.owner' "$MARKETPLACE" 2>/dev/null)
check "plugin.json .author matches the marketplace .owner (single source of truth)" \
  "$([[ -n "$pj_author" && "$pj_author" == "$mp_owner" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 3. SKILL.md frontmatter structure
# ---------------------------------------------------------------------------

fm_ok="$(frontmatter_ok "$SKILL_MD")"
check "SKILL.md frontmatter parses (opens/closes with a bare ---)" "$fm_ok" "yes"

fm_name="$(frontmatter_field "$SKILL_MD" name)"
check "SKILL.md frontmatter name is 'setup'" "$fm_name" "setup"

fm_dmi="$(frontmatter_field "$SKILL_MD" disable-model-invocation)"
check "SKILL.md frontmatter has disable-model-invocation: true" "$fm_dmi" "true"

fm_desc="$(frontmatter_field "$SKILL_MD" description)"
check "SKILL.md frontmatter description is non-empty" \
  "$(nonblank "$fm_desc")" "yes"

# ---------------------------------------------------------------------------
# 4. Skill name convention: "setup", not "settings-setup"
# ---------------------------------------------------------------------------

check "SKILL.md skill name does not repeat/contain the plugin name 'settings'" \
  "$(grep -qi 'settings' <<<"$fm_name" && echo contains || echo ok)" "ok"

# ---------------------------------------------------------------------------
# 5. No leftover NotImplemented marker outside the deliberate stub line
# ---------------------------------------------------------------------------

stray_markers=$(grep -n 'NotImplemented' "$SKILL_MD" 2>/dev/null | grep -v 'NotImplemented: B02')
check "no NotImplemented markers outside the expected '<!-- NotImplemented: B02' stub line" \
  "$([ -z "$stray_markers" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 6. Contract content: the instructions body (docblock stripped, content
#    after the first H1 heading) covers every element the contract requires.
# ---------------------------------------------------------------------------

instructions="$(skill_instructions_body "$SKILL_MD")"

check "instructions mention the CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var" \
  "$(grep -qiF 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' <<<"$instructions" && echo yes || echo no)" "yes"
check "instructions mention the CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING env var" \
  "$(grep -qiF 'CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention the value \"1\" for the env vars" \
  "$(grep -qF '"1"' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention the 'env' key/object in settings" \
  "$(grep -qiw 'env' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention scope detection via installed_plugins.json" \
  "$(grep -qiF 'installed_plugins.json' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention the 'user' scope" \
  "$(grep -qiw 'user' <<<"$instructions" && echo yes || echo no)" "yes"
check "instructions mention the 'project' scope" \
  "$(grep -qiw 'project' <<<"$instructions" && echo yes || echo no)" "yes"
check "instructions mention the 'local' scope" \
  "$(grep -qiw 'local' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention the user-scope settings file (~/.claude/settings.json)" \
  "$(grep -qiF '~/.claude/settings.json' <<<"$instructions" && echo yes || echo no)" "yes"
check "instructions mention the project-scope settings file (.claude/settings.json)" \
  "$(grep -qiF '.claude/settings.json' <<<"$instructions" && echo yes || echo no)" "yes"
check "instructions mention the local-scope settings file (.claude/settings.local.json)" \
  "$(grep -qiF '.claude/settings.local.json' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention backing up the target file before writing" \
  "$(grep -qiE 'backup|\.bak' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention the 'remove' subcommand" \
  "$(grep -qiw 'remove' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention jq as the merge tool" \
  "$(grep -qiw 'jq' <<<"$instructions" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
