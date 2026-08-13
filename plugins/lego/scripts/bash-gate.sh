#!/usr/bin/env bash
# bash-gate.sh — PreToolUse hook denying worker Bash commands that cross
# the orchestrator/worker boundary. Wired via worker agent-def frontmatter
# alongside realm-gate.sh.
#
# <!--
# Contract: B12 worker-bash-gate-and-tier (plan 001-lego-config-redesign)
# Behavior:   reads the PreToolUse hook JSON from stdin (same protocol as
#             realm-gate.sh) and denies a Bash tool call whose command
#             matches the prohibited family — git push, git merge,
#             git branch (creation forms), git checkout -b / git switch -c,
#             git worktree, git commit, gh pr, gh api — anywhere in the
#             command string (compound commands included). Everything else
#             passes through untouched.
# Inputs:     hook JSON on stdin; no arguments; no config, no jq beyond
#             what realm-gate.sh already uses.
# Outputs:    allow -> exit 0, no output; deny -> the hook-protocol deny
#             response with a reason naming the matched rule and telling
#             the worker to escalate to the orchestrator.
# Errors:     malformed/absent input -> allow (fail-open, matching
#             realm-gate's posture); the B09 prose prohibitions remain the
#             backstop.
# Invariants: never wired into orchestrator context (worker defs only);
#             read-only — never touches the repo; git status/diff/log/stash
#             and all non-git commands always pass.
# Edge cases: quoted or echoed mentions of a prohibited command (heredocs)
#             may false-positive -> the deny message says to escalate,
#             which is the correct outcome anyway.
#
# Alongside this script, B12 also: deletes the repo-local
# .claude/agents/lego-*.md shadow copies (drift class removed), moves both
# plugin worker defs' frontmatter to model: opus / effort: low, adds the
# Bash matcher to their hooks, and extends agent-defs.test.sh to assert the
# matcher, the tier, and the absence of repo-local copies.
# -->

set -euo pipefail
: "${JQ:=jq}"

input="$(cat)"

# Extract the Bash command exactly as realm-gate.sh extracts its file path:
# jq when available, a best-effort sed fallback otherwise. Any failure or
# absence yields an empty command, which fails OPEN (allow) per the contract.
if command -v "$JQ" >/dev/null 2>&1; then
  if ! command_str="$(printf '%s' "$input" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)"; then
    exit 0
  fi
else
  command_str="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi

[ -n "$command_str" ] || exit 0

# The prohibited family, matched as a plain substring anywhere in the command
# string so compound commands ("... && git push", "cd /tmp; git commit") are
# caught too. A quoted or echoed mention false-positives into a deny whose
# reason says to escalate — the harmless outcome named in Edge cases.
rule=""
case "$command_str" in
  *"git push"*)        rule="git push" ;;
  *"git merge"*)       rule="git merge" ;;
  *"git checkout -b"*) rule="git checkout -b" ;;
  *"git switch -c"*)   rule="git switch -c" ;;
  *"git branch"*)      rule="git branch" ;;
  *"git worktree"*)    rule="git worktree" ;;
  *"git commit"*)      rule="git commit" ;;
  *"gh pr"*)           rule="gh pr" ;;
  *"gh api"*)          rule="gh api" ;;
esac

[ -n "$rule" ] || exit 0

reason="Blocked: '$rule' crosses the orchestrator/worker boundary. Workers never push, merge, create branches, commit, manage worktrees, or open/alter PRs — delivery is the orchestrator's job. If this operation genuinely needs to happen, STOP and escalate to the orchestrator in your report instead."

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
exit 0
