#!/bin/bash
# Contract: B01 question-gate
#
# Behavior:
#   PreToolUse hook for the AskUserQuestion tool. Matcher-scoped by
#   hooks.json (matcher "AskUserQuestion"); the script itself performs no
#   matching and no stdin parsing. It unconditionally denies the tool call:
#   it writes a single-line deny message to stderr and exits 2. The message
#   is a redirect, not a bare refusal — it must tell Claude to ask the
#   engineer in the conversation as plain text instead, following the
#   numbered-question convention: number the questions (1., 2., ...), one
#   decision per number, give a recommended default for each, and state
#   what a bare "go"/"confirmed" accepts.
#
# Inputs:
#   Hook JSON on stdin — deliberately never read (matcher scoping makes
#   parsing unnecessary; ignoring stdin removes every failure mode). No
#   arguments. No environment variables consulted.
#
# Outputs:
#   stderr: exactly one line, which must name the blocked tool
#   "AskUserQuestion", name the ask-in-text plugin as the source of the
#   block, and instruct asking in plain text with numbered questions
#   (the words "numbered" and "plain text" appear literally), including
#   a recommended default per question and bare-"go" semantics.
#   stdout: nothing, ever.
#
# Errors:
#   None. The script uses only echo and exit — no external commands, no
#   file access, no jq. It cannot fail for environmental reasons.
#
# Exit:
#   Always 2. On PreToolUse, exit 2 denies the tool call and stderr is
#   shown to Claude (same mechanism as tracking's block-task-tools.sh).
#
# Invariants:
#   - Unconditional while the plugin is installed: no config surface, no
#     env escape hatch (engineer decision 2026-07-23; uninstalling the
#     plugin is the opt-out). Deliberate divergence from block-task-tools.sh's
#     CLAM_* gate variable.
#   - No side effects: nothing read, nothing written except the stderr line.
#   - stdin is never consumed (safe when stdin is empty, closed, or huge).
#   - Completes instantly; the hooks.json timeout of 10s is generous.
#
# Edge cases:
#   - Empty/closed/oversized stdin: irrelevant, stdin untouched.
#   - Invoked outside a hook context (manually, or by a test): identical
#     behavior — deny line on stderr, exit 2.
#   - Subagent tool calls: PreToolUse hooks fire for these too; the deny
#     applies identically (subagents should never user-prompt).

echo "AskUserQuestion is blocked by the ask-in-text plugin: ask in the conversation as plain text with numbered questions (1., 2., ...) instead, one decision per number, each with a recommended default; a bare \"go\" or \"confirmed\" accepts all the defaults." >&2
exit 2
