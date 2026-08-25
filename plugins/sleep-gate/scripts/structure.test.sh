#!/bin/bash
# Structural/contract tests for B02 — plugin manifests and hook registration
# (sleep-gate).
#
# Source of truth: the B02 contract — the plugin declares itself, and wires
# the gate script to exactly one PreToolUse hook group with matcher `Bash`.
# Surfaces covered:
#   - plugins/sleep-gate/.claude-plugin/plugin.json
#   - plugins/sleep-gate/hooks/hooks.json
#
# Covers plugin.json:
#   - valid JSON; .name exactly "sleep-gate" (matching the directory it lives
#     in); .version present and semver-shaped; .author present and non-empty;
#     .description present, non-empty, not a NotImplemented/TODO/stub
#     placeholder, and specific — it names the Bash tool and the
#     completion-wait misuse the gate exists for.
#
# Covers hooks.json:
#   - valid JSON; top-level .hooks is an object; EXACTLY one event key and it
#     is PreToolUse; exactly one group under it; that group's matcher is
#     exactly "Bash"; the group holds exactly one hook, of type "command",
#     running ${CLAUDE_PLUGIN_ROOT}/scripts/sleep-gate.sh with a positive
#     numeric timeout; exactly one command in the whole document.
#   - the referenced script exists in this repo (${CLAUDE_PLUGIN_ROOT}
#     resolved against the plugin directory) and is executable on disk.
#
# Tests only the public artifacts (JSON fields, file presence/mode) — never
# how the implementation produces them. Hermetic: reads only the repo's own
# files, no network, no mutation, no writes, cwd-independent (all paths
# resolved from this script's own location).
#
# Run: bash plugins/sleep-gate/scripts/structure.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"

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
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 1. plugin.json: valid JSON, name, version, author
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

pj_name=$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .name is exactly 'sleep-gate'" "$pj_name" "sleep-gate"

plugin_dir_name=$(basename "$(cd "$PLUGIN_DIR" && pwd)")
check "plugin.json .name matches the directory the plugin lives in" \
  "$pj_name" "$plugin_dir_name"

pj_version=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is present and semver-shaped (X.Y.Z)" \
  "$([[ "$pj_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" "yes"

pj_author=$(jq -r '.author // empty | if type == "object" then (.name // empty) else . end' \
  "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .author is present and non-empty" \
  "$([ -n "$pj_author" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 2. plugin.json: description is real and specific
# ---------------------------------------------------------------------------

pj_description=$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is present and non-empty" \
  "$([ -n "$pj_description" ] && echo yes || echo no)" "yes"

check "plugin.json .description is not a NotImplemented/TODO/stub placeholder" \
  "$(grep -qiE 'NotImplemented|TODO|\bstub\b|\bB02\b' <<<"$pj_description" \
    && echo placeholder || echo ok)" "ok"

check "plugin.json .description names the Bash tool" \
  "$(grep -qF 'Bash' <<<"$pj_description" && echo yes || echo no)" "yes"

check "plugin.json .description names the completion-wait misuse (sleep/wait/poll)" \
  "$(grep -qiE 'sleep|wait|poll' <<<"$pj_description" && echo yes || echo no)" "yes"

check "plugin.json .description is a single line" \
  "$(printf '%s' "$pj_description" | wc -l | tr -d ' ')" "0"

# ---------------------------------------------------------------------------
# 3. hooks.json: valid JSON, exactly one event key, and it is PreToolUse
# ---------------------------------------------------------------------------

check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

hooks_type=$(jq -r '.hooks | type' "$HOOKS_JSON" 2>/dev/null)
check "top-level .hooks is an object, not an array" "$hooks_type" "object"

event_keys=$(jq -Sc '.hooks | keys' "$HOOKS_JSON" 2>/dev/null)
check "hooks.json has exactly one event key, and it is PreToolUse" \
  "$event_keys" '["PreToolUse"]'

pretooluse_type=$(jq -r '.hooks.PreToolUse | type' "$HOOKS_JSON" 2>/dev/null)
check "hooks.PreToolUse is an array" "$pretooluse_type" "array"

# ---------------------------------------------------------------------------
# 4. The single PreToolUse group: matcher Bash -> the gate script
# ---------------------------------------------------------------------------

pt_group_count=$(jq -r '.hooks.PreToolUse | length' "$HOOKS_JSON" 2>/dev/null)
check "exactly one PreToolUse group" "${pt_group_count:-0}" "1"

pt_matcher=$(jq -r '.hooks.PreToolUse[0].matcher // empty' "$HOOKS_JSON" 2>/dev/null)
check "PreToolUse group matcher is exactly 'Bash'" "$pt_matcher" "Bash"

pt_hooks_count=$(jq -r '.hooks.PreToolUse[0].hooks | length' "$HOOKS_JSON" 2>/dev/null)
check "PreToolUse group holds exactly one hook" "${pt_hooks_count:-0}" "1"

pt_cmd_type=$(jq -r '.hooks.PreToolUse[0].hooks[0].type // empty' "$HOOKS_JSON" 2>/dev/null)
check "PreToolUse hook type is 'command'" "$pt_cmd_type" "command"

pt_command=$(jq -r '.hooks.PreToolUse[0].hooks[0].command // empty' "$HOOKS_JSON" 2>/dev/null)
# shellcheck disable=SC2016  # the literal ${CLAUDE_PLUGIN_ROOT} token is the expected value
check "PreToolUse command is \${CLAUDE_PLUGIN_ROOT}/scripts/sleep-gate.sh" \
  "$pt_command" '${CLAUDE_PLUGIN_ROOT}/scripts/sleep-gate.sh'

pt_timeout=$(jq -r '.hooks.PreToolUse[0].hooks[0].timeout // empty' "$HOOKS_JSON" 2>/dev/null)
check "PreToolUse hook declares a timeout" \
  "$([ -n "$pt_timeout" ] && echo yes || echo no)" "yes"
check "PreToolUse hook timeout is a positive number" \
  "$(jq -r '.hooks.PreToolUse[0].hooks[0].timeout
            | if (type == "number" and . > 0) then "yes" else "no" end' \
     "$HOOKS_JSON" 2>/dev/null)" "yes"

# ---------------------------------------------------------------------------
# 5. Whole-document invariant: exactly one command anywhere in the file
# ---------------------------------------------------------------------------

total_commands=$(jq '[.. | objects | select(has("command")) | .command] | length' \
  "$HOOKS_JSON" 2>/dev/null)
check "hooks.json registers exactly one command total (no others anywhere)" \
  "${total_commands:-0}" "1"

# ---------------------------------------------------------------------------
# 6. The referenced script exists in this repo and is executable
# ---------------------------------------------------------------------------
# ${CLAUDE_PLUGIN_ROOT} is the plugin root at runtime; resolve it against the
# plugin directory to confirm the target is really there.

resolved_target="${pt_command/\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_DIR}"
# shellcheck disable=SC2016  # the literal ${CLAUDE_PLUGIN_ROOT} token is the expected prefix
check "hook command is rooted at \${CLAUDE_PLUGIN_ROOT}" \
  "$([[ "$pt_command" == '${CLAUDE_PLUGIN_ROOT}/'* ]] && echo yes || echo no)" "yes"
check "the script the hook points at exists in this repo" \
  "$([ -n "$pt_command" ] && [ -f "$resolved_target" ] && echo yes || echo no)" "yes"
check "the script the hook points at is executable" \
  "$([ -n "$pt_command" ] && [ -x "$resolved_target" ] && echo yes || echo no)" "yes"

check "scripts/structure.test.sh is executable" \
  "$([ -x "$SCRIPT_DIR/structure.test.sh" ] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
