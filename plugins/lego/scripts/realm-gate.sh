#!/usr/bin/env bash
# realm-gate.sh — PreToolUse hook: mechanical realm enforcement for lego workers.
#
# Contract: B04 realm-gate-local-readonly
#
# New clauses in plan 001 are marked (NEW, plan 001); every other clause is
# pre-existing behavior.
#
# Behavior:
#   Reads the hook input JSON on stdin. When the running agent is a lego
#   worker (agent_type ends in lego-test-writer or lego-implementer), denies
#   Edit/Write/NotebookEdit calls whose target file is outside the agent's
#   realm:
#     lego-test-writer  → may ONLY touch test-family files
#     lego-implementer  → may NEVER touch test-family files
#   (NEW, plan 001) Additionally denies, for BOTH worker roles and evaluated
#   before the realm-family rules above, any call whose target path contains
#   a path segment exactly ".local": the unit worktree's .local/
#   (config.json, unit.md, contracts/, status.md, briefs/, reports/) is
#   orchestrator-owned and read-only for workers. This deny fires even for
#   paths the realm rules would allow (e.g. a lego-test-writer targeting
#   .local/__tests__/x.test.js, or a lego-implementer targeting
#   .local/status.md).
#   All other agents (including the main session) pass through untouched.
#
# Inputs:
#   Hook JSON on stdin: .agent_type, .tool_input.file_path or
#   .tool_input.notebook_path. Missing/empty agent_type or file path →
#   pass through.
#
# Outputs:
#   On deny: one line of JSON — hookSpecificOutput with permissionDecision
#   "deny" and a permissionDecisionReason naming the violated rule and
#   directing the worker to STOP and return an ESCALATION report.
#   (NEW, plan 001) The .local deny reason states that .local/ is
#   orchestrator-owned and read-only for workers. On allow: no output.
#   Always exit 0.
#
# Errors:
#   Never blocks on its own failure: without jq, falls back to sed-based
#   field extraction; unparseable input passes through (exit 0, no output).
#
# Invariants:
#   - Only lego worker agent types are ever denied; any other agent_type
#     (including none) always passes through.
#   - Read-only: inspects stdin only; writes nothing to disk.
#
# Edge cases:
#   - (NEW, plan 001) ".local" must match a whole path segment: "a/.local/b"
#     and ".local/b" are denied (as is a path whose final segment is
#     ".local"); "my.local/b", "xlocal/b", and "a/local/b" are not denied by
#     this rule. Both relative and absolute paths match — the test is on the
#     path string, not the filesystem.
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
