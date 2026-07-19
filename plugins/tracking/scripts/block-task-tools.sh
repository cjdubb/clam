#!/bin/bash
# PreToolUse hook (TaskCreate|TaskUpdate|TaskList|TaskGet): denies the
# built-in task tools. Work tracking lives in .local/TODO.md — the built-in
# tools write to ~/.claude/tasks/, which the tracking docs, agent-dash, and
# the statusline never see, so anything tracked there is invisible state.
#
# The deny is unconditional while the plugin is enabled: even in a session
# with no .local/TODO.md yet, the right first tracking act is creating the
# TODO, not diverting state into ~/.claude/tasks/. Matcher-scoped — no other
# tool is touched (TeamCreate and the team-coordination tools stay available).
#
# Escape hatch: CLAM_TRACKING_TASK_TOOLS_GATE=disabled at launch turns the
# deny off (hooks do not see mid-session exports).
#
# On PreToolUse, exit 2 denies the tool call and stderr is shown to Claude.

[[ "${CLAM_TRACKING_TASK_TOOLS_GATE:-enabled}" == "enabled" ]] || exit 0

echo "BLOCKED: work tracking lives in .local/TODO.md, not the built-in task tools (they write to ~/.claude/tasks/, invisible to the tracking docs, agent-dash, and the statusline). Record the task in .local/TODO.md instead. Escape hatch: relaunch with CLAM_TRACKING_TASK_TOOLS_GATE=disabled." >&2
exit 2
