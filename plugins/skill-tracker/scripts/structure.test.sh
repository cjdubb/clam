#!/bin/bash
# B04 — structure test for the skill-tracker plugin
#
# Checks the wiring, not the runtime behavior, of the plugin: plugin.json's
# manifest fields, hooks.json's PreToolUse/PostToolUse registration, the two
# scripts' presence and shebangs, the stats skill's frontmatter, and the
# plugin's registration in the repo-root marketplace.json. Runtime behavior
# of log-skill-trigger.sh and skill-stats.sh (still stubs at time of
# writing) is out of scope here — that belongs to their own behavioral
# tests, not this structural one.
#
# The marketplace check is deliberately red until the implementer adds a
# "skill-tracker" entry to .claude-plugin/marketplace.json — this file does
# not special-case that away.
#
# Hermetic: reads only the repo's own committed files, no network, no
# mutation, cwd-independent (all paths resolved from this script's own
# location).
#
# Run: bash plugins/skill-tracker/scripts/structure.test.sh (exits non-zero
# on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PLUGIN_ROOT="$ROOT/plugins/skill-tracker"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
LOG_SCRIPT="$PLUGIN_ROOT/scripts/log-skill-trigger.sh"
STATS_SCRIPT="$PLUGIN_ROOT/scripts/skill-stats.sh"
SKILL_MD="$PLUGIN_ROOT/skills/stats/SKILL.md"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
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

check "plugins/skill-tracker/ exists" \
  "$([ -d "$PLUGIN_ROOT" ] && echo yes || echo no)" "yes"
check "plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "hooks.json exists" \
  "$([ -f "$HOOKS_JSON" ] && echo yes || echo no)" "yes"
check "scripts/log-skill-trigger.sh exists" \
  "$([ -f "$LOG_SCRIPT" ] && echo yes || echo no)" "yes"
check "scripts/skill-stats.sh exists" \
  "$([ -f "$STATS_SCRIPT" ] && echo yes || echo no)" "yes"
check "skills/stats/SKILL.md exists" \
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
check "plugin.json .name is 'skill-tracker'" "$pj_name" "skill-tracker"

# ---------------------------------------------------------------------------
# 2. hooks.json wiring: PreToolUse and PostToolUse, both matching "Skill",
#    both pointing at the log-skill-trigger.sh hook script.
# ---------------------------------------------------------------------------

check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

pre_matcher=$(jq -r '.hooks.PreToolUse[0].matcher // empty' "$HOOKS_JSON" 2>/dev/null)
pre_command=$(jq -r '.hooks.PreToolUse[0].hooks[0].command // empty' "$HOOKS_JSON" 2>/dev/null)
post_matcher=$(jq -r '.hooks.PostToolUse[0].matcher // empty' "$HOOKS_JSON" 2>/dev/null)
post_command=$(jq -r '.hooks.PostToolUse[0].hooks[0].command // empty' "$HOOKS_JSON" 2>/dev/null)

check "hooks.json PreToolUse matcher is 'Skill'" "$pre_matcher" "Skill"
check "hooks.json PreToolUse hook points at scripts/log-skill-trigger.sh" \
  "$pre_command" '${CLAUDE_PLUGIN_ROOT}/scripts/log-skill-trigger.sh'

check "hooks.json PostToolUse matcher is 'Skill'" "$post_matcher" "Skill"
check "hooks.json PostToolUse hook points at scripts/log-skill-trigger.sh" \
  "$post_command" '${CLAUDE_PLUGIN_ROOT}/scripts/log-skill-trigger.sh'

# ---------------------------------------------------------------------------
# 3. Scripts have a bash shebang.
# ---------------------------------------------------------------------------

log_shebang="$(sed -n '1p' "$LOG_SCRIPT" 2>/dev/null)"
check "log-skill-trigger.sh has a bash shebang" \
  "$(grep -qE '^#!.*bash' <<<"$log_shebang" && echo yes || echo no)" "yes"

stats_shebang="$(sed -n '1p' "$STATS_SCRIPT" 2>/dev/null)"
check "skill-stats.sh has a bash shebang" \
  "$(grep -qE '^#!.*bash' <<<"$stats_shebang" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 4. skills/stats/SKILL.md frontmatter.
# ---------------------------------------------------------------------------

fm_ok="$(frontmatter_ok "$SKILL_MD")"
check "SKILL.md frontmatter parses (opens/closes with a bare ---)" "$fm_ok" "yes"

if [[ "$fm_ok" == "yes" ]]; then
  fm_name="$(frontmatter_field "$SKILL_MD" name)"
  check "SKILL.md frontmatter name is 'stats'" "$fm_name" "stats"

  fm_desc="$(frontmatter_field "$SKILL_MD" description)"
  check "SKILL.md frontmatter description is non-empty" \
    "$([ -n "$fm_desc" ] && echo yes || echo no)" "yes"
fi

# ---------------------------------------------------------------------------
# 5. Marketplace registration.
# ---------------------------------------------------------------------------

check "marketplace.json contains a 'skill-tracker' entry" \
  "$(jq -e '.plugins[] | select(.name == "skill-tracker")' "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
