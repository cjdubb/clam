#!/usr/bin/env bash
# realm-gate.sh — PreToolUse hook: mechanical realm enforcement for lego workers.
#
# Reads the hook input JSON on stdin. When the running agent is a lego worker
# (agent_type ends in lego-test-writer or lego-implementer), denies Edit/Write/
# NotebookEdit calls whose target file is outside the agent's realm:
#   lego-test-writer  → may ONLY touch test-family files
#   lego-implementer  → may NEVER touch test-family files
# All other agents (including the main session) pass through untouched.
#
# This gate covers file tools only; Bash-based writes are caught post-hoc by
# realm-check.sh, which the orchestrator runs at each wave boundary.
set -euo pipefail

input="$(cat)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v jq >/dev/null 2>&1; then
  agent_type="$(printf '%s' "$input" | jq -r '.agent_type // empty')"
  file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
else
  # Best-effort fallback without jq: extract simple string fields.
  agent_type="$(printf '%s' "$input" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  file_path="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [ -z "$file_path" ]; then
    file_path="$(printf '%s' "$input" | sed -n 's/.*"notebook_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  fi
fi

case "$agent_type" in
  *lego-test-writer) role="test" ;;
  *lego-implementer) role="impl" ;;
  *) exit 0 ;;
esac

[ -n "$file_path" ] || exit 0

realm="$("$here/realm.sh" "$file_path")"

reason=""
if [ "$role" = "test" ] && [ "$realm" != "test" ]; then
  reason="lego-test-writer is realm-restricted to test-family files (*.spec.*, *.test.*, *_test.*, *_spec.*, test_*, __tests__/). $file_path is outside that family. If this file genuinely must change, STOP and return an ESCALATION report to the orchestrator instead."
elif [ "$role" = "impl" ] && [ "$realm" = "test" ]; then
  reason="lego-implementer may not modify test-family files. $file_path is in the test family. If a test seems wrong, STOP and return an ESCALATION report to the orchestrator; never adjust tests to fit the implementation."
fi

if [ -n "$reason" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
exit 0
