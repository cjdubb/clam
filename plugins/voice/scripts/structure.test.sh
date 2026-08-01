#!/bin/bash
# Structural/contract tests for B02 assembly-and-registration (voice).
#
# Source of truth: the HTML-comment docblock "Contract: B02
# assembly-and-registration (voice)" in the root README.md, just under
# the Plugins table. This file covers the plugin-local surfaces the
# contract names: plugins/voice/.claude-plugin/plugin.json and
# plugins/voice/hooks/hooks.json. The shared repo surfaces (marketplace
# entry, README row, MIGRATION.md section, issue-template dropdowns) are
# covered by registration.test.sh.
#
# Covers plugin.json:
#   - valid JSON; name "voice"; version "0.1.0" exactly; non-empty
#     description naming both the Voice communication spec and its
#     SessionStart injection, free of STUB/TODO/NotImplemented markers;
#     .author byte-identical (jq -Sc) to marketplace.json's .owner (single
#     source of truth, never a hand-maintained copy)
#
# Covers hooks.json:
#   - valid JSON; top-level document has exactly one key, .hooks, an
#     object with exactly one event key, SessionStart, an array with
#     exactly one group; the group has NO matcher and exactly one hook:
#     type "command", command "${CLAUDE_PLUGIN_ROOT}/scripts/voice-context.sh",
#     timeout 10; no other events, groups, or commands anywhere in the
#     file (checked both per-group and via a whole-document command tally)
#
# Also covers the hooks-only-plugin invariant (no skills/ directory) and
# that voice-context.sh and every *.test.sh file in this directory are
# executable on disk.
#
# Tests only the public artifacts (JSON fields, file presence/mode) —
# never how the implementation produces them. Hermetic: reads only the
# repo's own committed files, no network, no mutation, cwd-independent
# (all paths resolved from this script's own location).
#
# Run: bash plugins/voice/scripts/structure.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
SKILLS_DIR="$PLUGIN_DIR/skills"
VOICE_CONTEXT_SH="$PLUGIN_DIR/scripts/voice-context.sh"

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
check "plugin.json .name is 'voice'" "$pj_name" "voice"

pj_version=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is exactly '0.1.0'" "$pj_version" "0.1.0"

pj_description=$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is non-empty" \
  "$([ -n "$pj_description" ] && echo yes || echo no)" "yes"
check "plugin.json .description names the Voice spec" \
  "$(grep -qi 'voice' <<<"$pj_description" && echo yes || echo no)" "yes"
check "plugin.json .description names SessionStart" \
  "$(grep -qF 'SessionStart' <<<"$pj_description" && echo yes || echo no)" "yes"
check "plugin.json .description is not a STUB/TODO/NotImplemented placeholder" \
  "$(grep -qiE 'TODO|NotImplemented|\bstub\b' <<<"$pj_description" && echo placeholder || echo ok)" "ok"

pj_author=$(jq -Sc '.author' "$PLUGIN_JSON" 2>/dev/null)
mp_owner=$(jq -Sc '.owner' "$MARKETPLACE" 2>/dev/null)
check "plugin.json .author is byte-identical (jq -Sc) to marketplace.json .owner" \
  "$([[ -n "$pj_author" && "$pj_author" == "$mp_owner" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 2. hooks.json validity, top-level shape, and whole-document minimality
# ---------------------------------------------------------------------------

check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

doc_keys=$(jq -Sc 'keys' "$HOOKS_JSON" 2>/dev/null)
check "hooks.json top-level document has exactly one key: hooks" \
  "$doc_keys" '["hooks"]'

hooks_type=$(jq -r '.hooks | type' "$HOOKS_JSON" 2>/dev/null)
check "top-level .hooks is an object, not an array" "$hooks_type" "object"

event_keys=$(jq -Sc '.hooks | keys' "$HOOKS_JSON" 2>/dev/null)
check "hooks.json has exactly one event key: SessionStart" \
  "$event_keys" '["SessionStart"]'

sessionstart_type=$(jq -r '.hooks.SessionStart | type' "$HOOKS_JSON" 2>/dev/null)
check "hooks.SessionStart is an array" "$sessionstart_type" "array"

# ---------------------------------------------------------------------------
# 3. SessionStart group: no matcher -> voice-context.sh
# ---------------------------------------------------------------------------

ss_group_count=$(jq -r '.hooks.SessionStart | length' "$HOOKS_JSON" 2>/dev/null)
check "exactly one SessionStart group" "${ss_group_count:-0}" "1"

ss_group_keys=$(jq -Sc '.hooks.SessionStart[0] | keys' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart group has no matcher key (only hooks)" "$ss_group_keys" '["hooks"]'

ss_hooks_count=$(jq -r '.hooks.SessionStart[0].hooks | length' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart group runs exactly one command" "${ss_hooks_count:-0}" "1"

ss_hook_keys=$(jq -Sc '.hooks.SessionStart[0].hooks[0] | keys' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart hook object has exactly type, command, timeout" \
  "$ss_hook_keys" '["command","timeout","type"]'

ss_command=$(jq -r '.hooks.SessionStart[0].hooks[0].command // empty' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart command is \${CLAUDE_PLUGIN_ROOT}/scripts/voice-context.sh" \
  "$ss_command" '${CLAUDE_PLUGIN_ROOT}/scripts/voice-context.sh'

ss_cmd_type=$(jq -r '.hooks.SessionStart[0].hooks[0].type // empty' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart command type is 'command'" "$ss_cmd_type" "command"

ss_timeout=$(jq -r '.hooks.SessionStart[0].hooks[0].timeout // empty' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart command timeout is 10" "$ss_timeout" "10"

# ---------------------------------------------------------------------------
# 4. Registers no other events/commands anywhere in the file (invariant)
# ---------------------------------------------------------------------------

total_commands=$(jq '[.. | objects | select(has("command")) | .command] | length' "$HOOKS_JSON" 2>/dev/null)
check "hooks.json registers exactly one command total (no others anywhere)" \
  "${total_commands:-0}" "1"

# ---------------------------------------------------------------------------
# 5. Hooks-only plugin: no skills/ directory
# ---------------------------------------------------------------------------

check "plugins/voice/skills/ does not exist (hooks-only plugin)" \
  "$([ -d "$SKILLS_DIR" ] && echo exists || echo absent)" "absent"

# ---------------------------------------------------------------------------
# 6. Executability on disk
# ---------------------------------------------------------------------------

check "scripts/voice-context.sh is executable" \
  "$([ -x "$VOICE_CONTEXT_SH" ] && echo yes || echo no)" "yes"

mapfile -t TEST_FILES < <(find "$SCRIPT_DIR" -maxdepth 1 -name '*.test.sh' | sort)
check "at least one *.test.sh file found in plugins/voice/scripts/" \
  "$([ "${#TEST_FILES[@]}" -gt 0 ] && echo yes || echo no)" "yes"

ALL_TESTS_EXEC=yes
for f in "${TEST_FILES[@]}"; do
  if [[ ! -x "$f" ]]; then
    ALL_TESTS_EXEC=no
    echo "      (not executable: $f)"
  fi
done
check "every *.test.sh file under plugins/voice/scripts/ is executable" \
  "$ALL_TESTS_EXEC" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
