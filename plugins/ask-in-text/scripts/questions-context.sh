#!/bin/bash
# Contract: B02 questions-context
#
# Behavior:
#   SessionStart hook. Emits the standing question-asking convention to
#   stdout (plain stdout becomes session context, same mechanism as lego's
#   session-context.sh). The emitted context must instruct, in this
#   substance (wording is the implementer's, clauses are contractual):
#     1. Never call the AskUserQuestion tool — it is blocked in this
#        environment by the ask-in-text plugin's PreToolUse gate; do not
#        attempt it, do not retry it.
#     2. Ask the engineer questions in the conversation as plain text.
#     3. Number the questions (1., 2., ...), one decision per number, so
#        a reply like "1: A, 2: B" resolves unambiguously (issue #29).
#     4. Give a recommended default per question, with a one-line
#        rationale or trade-off where it helps.
#     5. State what a bare "go"/"confirmed" accepts (all defaults).
#     6. Keep each question decidable at a glance; no walls of text.
#
# Inputs:
#   Hook JSON on stdin — deliberately never read. No arguments. No
#   environment variables consulted; no file reads.
#
# Outputs:
#   stdout: a markdown block containing at minimum a heading identifying
#   the convention, the literal tool name "AskUserQuestion", the word
#   "numbered", and the bare-"go" semantics. Deterministic: byte-identical
#   on every run.
#   stderr: nothing.
#
# Errors:
#   None. Heredoc-to-stdout only; no external commands. It cannot fail
#   for environmental reasons.
#
# Exit:
#   Always 0. A SessionStart hook must never block session start.
#
# Invariants:
#   - No side effects; nothing read from disk or stdin.
#   - Unconditional while installed: no config surface, no env escape
#     hatch (engineer decision 2026-07-23).
#   - Output stays compact (well under typical context-injection budgets).
#
# Edge cases:
#   - Invoked outside a hook context (manually, or by a test): identical
#     output, exit 0.
#   - Runs alongside other plugins' SessionStart context (lego, landing,
#     tracking): the convention must stand alone and not contradict the
#     tracking plugin's decision-format guidance (recommended option,
#     default on bare "go") — it restates the same convention for
#     question-asking generally.

echo "NotImplemented: B02 questions-context" >&2
exit 1
