#!/usr/bin/env bash
# sleep-gate.sh — PreToolUse hook denying `sleep` used as a completion-wait
# for a backgrounded script. Wired via hooks/hooks.json with matcher "Bash".
#
# <!--
# Contract: B01 sleep-gate hook script (plan 001-sleep-gate)
#
# Behavior:
#   Reads the PreToolUse hook JSON from stdin and extracts
#   .tool_input.command. Applies two rules to that command string; either
#   one matching denies the tool call.
#
#   Rule L — a leading bare sleep. The command's FIRST STATEMENT is
#     `sleep <duration>` and the duration is 2 seconds or longer. The first
#     statement is the command text up to the first `;`, `&&`, `||`, `|`, or
#     newline, trimmed. Exactly one operand, optionally suffixed `s`, `m`,
#     `h`, or `d`, converted to seconds (m=60, h=3600, d=86400). Matches:
#     `sleep 45`, `sleep 2m`, `sleep 30 && cat /tmp/build.log`. Does not
#     match: `sleep 0.25`, `sleep 1`, or any sleep that is not the first
#     statement. This is the rule that catches the separate-turn shape —
#     the agent backgrounds a script in one tool call and sleeps in the
#     next — without the hook holding any state between calls.
#
#   Rule B — a background launch followed by a sleep. All three hold:
#     (1) the command contains a BACKGROUND `&`: an `&` that is not part of
#         `&&`, `>&`, `&>`, `<&`, or an escaped `\&`;
#     (2) a `sleep` appears AFTER the first background `&`;
#     (3) the command contains NONE of the words `while`, `until`, `for`,
#         `break`, `wait`, or `trap` anywhere in it.
#     Clause 3 is the carve-out that keeps the rule honest: a poll loop
#     (`srv & until curl -sf "$u/health"; do sleep 0.25; done`) already
#     waits on the real event, and a kill-grace sleep sits beside a `trap`.
#     It errs toward allowing — a missed misuse costs nothing, whereas a
#     wrong denial interrupts a session that was doing the right thing.
#
#   On a match, write ONE single-line JSON object to stdout:
#     {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#      "permissionDecision":"deny","permissionDecisionReason":"<reason>"}}
#   and exit 0. On no match, write nothing and exit 0.
#
# Inputs:
#   Hook JSON on stdin. No arguments. No config files, no reads from
#   .claude/ or .local/. The only environment variable consulted is JQ
#   (defaulting to `jq`), which exists so tests can point at a stub or an
#   absent binary; it is not a user-facing configuration surface.
#
# Outputs:
#   stdout: the deny object above, or nothing at all. The
#   permissionDecisionReason must name WHICH rule matched, state that a
#   fixed sleep is not a completion signal, and list all four alternatives:
#     - run the command in the foreground and let the Bash tool's own
#       `timeout` parameter bound it;
#     - pass run_in_background: true and let the harness re-invoke on exit;
#     - `wait "$pid"` when the process is a child of this shell;
#     - poll the real condition (`until [ -f done.marker ]; do sleep 1; done`,
#       or `kill -0 "$pid"`).
#   stderr: nothing, ever.
#
# Errors:
#   None reachable. Every failure allows the call: absent jq, unparseable
#   JSON, absent .tool_input.command, an empty command, a duration that is
#   not a number, a multi-operand `sleep 5 10`.
#
# Invariants:
#   - ALWAYS exits 0. A nonzero exit from a PreToolUse hook is itself a
#     denial, so the entire fail-open promise rests on this. There is no
#     code path that exits nonzero.
#   - Fail-open everywhere: when in doubt, allow. A gate on the Bash tool
#     that failed closed would wedge every session it is installed in.
#   - Read-only: never writes a file, never reads one.
#   - Never writes to stderr.
#   - Deterministic: the same command string always yields the same
#     decision.
#   - No configuration surface and no environment escape hatch;
#     uninstalling the plugin is the opt-out.
#   - Uses only constructs available in bash 3.2, so it behaves identically
#     under stock macOS bash. No associative arrays, no `wait -n`, no
#     `${var,,}`.
#   - Keys on the SHAPE of the wait, never on the word `sleep`. Poll
#     intervals inside condition loops, SIGTERM/SIGKILL grace periods,
#     clock- and mtime-granularity waits, and `sleep` used as a test double
#     for a slow process all pass untouched.
#
# Edge cases:
#   - `sleep 0.25`, `sleep 1`: allow (below the 2s floor).
#   - `sleep` inside a while/until/for body, or alongside wait/break/trap:
#     allow, under Rule B clause 3.
#   - `&&`, `2>&1`, `&>`, `>&`, `<&`, `\&`: none counts as a background
#     launch.
#   - A `sleep` appearing BEFORE the first background `&`: allow.
#   - Multi-operand `sleep 5 10`: allow (no match).
#   - A quoted or heredoc mention of `sleep` cannot be the first statement,
#     so Rule L cannot false-positive on it; Rule B may, and a denial there
#     is harmless because the reason names the alternative.
#   - Empty, closed, or oversized stdin: allow.
#   - Invoked outside a hook context (manually, or by a test): identical
#     behavior.
#   - Subagent tool calls: PreToolUse hooks fire for these too; the gate
#     applies identically.
# -->

set -u

echo "NotImplemented: B01 sleep-gate" >&2
exit 70
