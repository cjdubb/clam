#!/bin/bash
# UserPromptSubmit hook: captures the session's current permission_mode
# to $cwd/.local/.permission-mode. push-notify.sh reads it to suppress pushes
# in plan mode; agent-dash surfaces it on the dashboard.
# Silent-exits on any failure — never blocks or injects output.
# Escape hatch: CLAM_NOTIFICATIONS_GATE=disabled at launch turns off every
# hook in this plugin (hooks do not see mid-session exports).

[[ "${CLAM_NOTIFICATIONS_GATE:-enabled}" == "enabled" ]] || exit 0

input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
mode=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)

[[ -n "$cwd" && -n "$mode" && -d "$cwd/.local" ]] || exit 0

printf '%s\n' "$mode" > "$cwd/.local/.permission-mode" 2>/dev/null
exit 0
