#!/bin/bash
# Structural/contract tests for B03 assembly & registration (ask-in-text).
#
# Source of truth: the HTML-comment docblock "Contract: B03 assembly &
# registration (ask-in-text)" in the root README.md, just under the
# Plugins table. This file covers the plugin-local surfaces the contract
# names: plugins/ask-in-text/.claude-plugin/plugin.json and
# plugins/ask-in-text/hooks/hooks.json. The shared repo surfaces
# (marketplace.json entry, README Plugins-table row) are covered by
# registration.test.sh.
#
# Covers plugin.json:
#   - valid JSON; name "ask-in-text"; version "0.1.0" exactly; non-empty
#     description naming AskUserQuestion and not a stub/TODO/NotImplemented
#     placeholder; .author byte-identical (jq -Sc) to marketplace.json's
#     .owner (single source of truth, not a hardcoded copy)
#
# Covers hooks.json:
#   - valid JSON; top-level .hooks is an object (not an array); exactly
#     two event keys, PreToolUse and SessionStart, each an array; the
#     PreToolUse group has matcher exactly "AskUserQuestion" and runs
#     ${CLAUDE_PLUGIN_ROOT}/scripts/block-question.sh, type "command",
#     timeout 10; the SessionStart group has NO matcher and runs
#     ${CLAUDE_PLUGIN_ROOT}/scripts/questions-context.sh, type "command",
#     timeout 10; no other events, groups, or commands anywhere in the
#     file (checked both per-group and via a whole-document command tally)
#
# Also covers the hooks-only-plugin invariant (no skills/ directory) and
# that both hook scripts and both test files in this directory are
# executable on disk.
#
# Tests only the public artifacts (JSON fields, file presence/mode) —
# never how the implementation produces them. Hermetic: reads only the
# repo's own committed files, no network, no mutation, cwd-independent
# (all paths resolved from this script's own location).
#
# Run: bash plugins/ask-in-text/scripts/structure.test.sh (exits non-zero
# on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
SKILLS_DIR="$PLUGIN_DIR/skills"
BLOCK_QUESTION_SH="$PLUGIN_DIR/scripts/block-question.sh"
QUESTIONS_CONTEXT_SH="$PLUGIN_DIR/scripts/questions-context.sh"

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

check "plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "hooks.json exists" \
  "$([ -f "$HOOKS_JSON" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 1. plugin.json validity and content
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

pj_name=$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .name is 'ask-in-text'" "$pj_name" "ask-in-text"

pj_version=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is non-empty and well-formed semver (X.Y.Z)" \
  "$([[ "$pj_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" "yes"

pj_description=$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is non-empty" \
  "$([ -n "$pj_description" ] && echo yes || echo no)" "yes"
check "plugin.json .description names AskUserQuestion" \
  "$(grep -qF 'AskUserQuestion' <<<"$pj_description" && echo yes || echo no)" "yes"
check "plugin.json .description is not a stub/TODO/NotImplemented placeholder" \
  "$(grep -qiE 'TODO|NotImplemented|\bstub\b' <<<"$pj_description" && echo placeholder || echo ok)" "ok"

pj_author=$(jq -Sc '.author' "$PLUGIN_JSON" 2>/dev/null)
mp_owner=$(jq -Sc '.owner' "$MARKETPLACE" 2>/dev/null)
check "plugin.json .author is byte-identical (jq -Sc) to marketplace.json .owner" \
  "$([[ -n "$pj_author" && "$pj_author" == "$mp_owner" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 2. hooks.json validity and top-level shape
# ---------------------------------------------------------------------------

check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

hooks_type=$(jq -r '.hooks | type' "$HOOKS_JSON" 2>/dev/null)
check "top-level .hooks is an object, not an array" "$hooks_type" "object"

event_keys=$(jq -Sc '.hooks | keys' "$HOOKS_JSON" 2>/dev/null)
check "hooks.json has exactly two event keys: PreToolUse and SessionStart" \
  "$event_keys" '["PreToolUse","SessionStart"]'

pretooluse_type=$(jq -r '.hooks.PreToolUse | type' "$HOOKS_JSON" 2>/dev/null)
check "hooks.PreToolUse is an array" "$pretooluse_type" "array"

sessionstart_type=$(jq -r '.hooks.SessionStart | type' "$HOOKS_JSON" 2>/dev/null)
check "hooks.SessionStart is an array" "$sessionstart_type" "array"

# ---------------------------------------------------------------------------
# 3. PreToolUse group: matcher "AskUserQuestion" -> block-question.sh
# ---------------------------------------------------------------------------

pt_group_count=$(jq -r '.hooks.PreToolUse | length' "$HOOKS_JSON" 2>/dev/null)
check "exactly one PreToolUse group" "${pt_group_count:-0}" "1"

pt_matcher=$(jq -r '.hooks.PreToolUse[0].matcher // empty' "$HOOKS_JSON" 2>/dev/null)
check "PreToolUse group matcher is exactly 'AskUserQuestion'" "$pt_matcher" "AskUserQuestion"

pt_hooks_count=$(jq -r '.hooks.PreToolUse[0].hooks | length' "$HOOKS_JSON" 2>/dev/null)
check "PreToolUse group runs exactly one command" "${pt_hooks_count:-0}" "1"

pt_command=$(jq -r '.hooks.PreToolUse[0].hooks[0].command // empty' "$HOOKS_JSON" 2>/dev/null)
check "PreToolUse command is \${CLAUDE_PLUGIN_ROOT}/scripts/block-question.sh" \
  "$pt_command" '${CLAUDE_PLUGIN_ROOT}/scripts/block-question.sh'

pt_cmd_type=$(jq -r '.hooks.PreToolUse[0].hooks[0].type // empty' "$HOOKS_JSON" 2>/dev/null)
check "PreToolUse command type is 'command'" "$pt_cmd_type" "command"

pt_timeout=$(jq -r '.hooks.PreToolUse[0].hooks[0].timeout // empty' "$HOOKS_JSON" 2>/dev/null)
check "PreToolUse command timeout is 10" "$pt_timeout" "10"

# ---------------------------------------------------------------------------
# 4. SessionStart group: no matcher -> questions-context.sh
# ---------------------------------------------------------------------------

ss_group_count=$(jq -r '.hooks.SessionStart | length' "$HOOKS_JSON" 2>/dev/null)
check "exactly one SessionStart group" "${ss_group_count:-0}" "1"

ss_has_matcher=$(jq -r '.hooks.SessionStart[0] | has("matcher")' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart group has no matcher key" "$ss_has_matcher" "false"

ss_hooks_count=$(jq -r '.hooks.SessionStart[0].hooks | length' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart group runs exactly one command" "${ss_hooks_count:-0}" "1"

ss_command=$(jq -r '.hooks.SessionStart[0].hooks[0].command // empty' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart command is \${CLAUDE_PLUGIN_ROOT}/scripts/questions-context.sh" \
  "$ss_command" '${CLAUDE_PLUGIN_ROOT}/scripts/questions-context.sh'

ss_cmd_type=$(jq -r '.hooks.SessionStart[0].hooks[0].type // empty' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart command type is 'command'" "$ss_cmd_type" "command"

ss_timeout=$(jq -r '.hooks.SessionStart[0].hooks[0].timeout // empty' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart command timeout is 10" "$ss_timeout" "10"

# ---------------------------------------------------------------------------
# 5. Registers no other events/commands anywhere in the file (invariant)
# ---------------------------------------------------------------------------

total_commands=$(jq '[.. | objects | select(has("command")) | .command] | length' "$HOOKS_JSON" 2>/dev/null)
check "hooks.json registers exactly two commands total (no others anywhere)" \
  "${total_commands:-0}" "2"

# ---------------------------------------------------------------------------
# 6. Hooks-only plugin: no skills/ directory
# ---------------------------------------------------------------------------

check "plugins/ask-in-text/skills/ does not exist (hooks-only plugin)" \
  "$([ -d "$SKILLS_DIR" ] && echo exists || echo absent)" "absent"

# ---------------------------------------------------------------------------
# 7. Executability on disk
# ---------------------------------------------------------------------------

check "scripts/block-question.sh is executable" \
  "$([ -x "$BLOCK_QUESTION_SH" ] && echo yes || echo no)" "yes"
check "scripts/questions-context.sh is executable" \
  "$([ -x "$QUESTIONS_CONTEXT_SH" ] && echo yes || echo no)" "yes"
check "scripts/structure.test.sh is executable" \
  "$([ -x "$SCRIPT_DIR/structure.test.sh" ] && echo yes || echo no)" "yes"
check "scripts/registration.test.sh is executable" \
  "$([ -x "$SCRIPT_DIR/registration.test.sh" ] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
