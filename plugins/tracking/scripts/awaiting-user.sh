#!/bin/bash
# Tracks whether the agent is waiting on user input.
# - Stop event: agent finished turn → write $cwd/.local/.awaiting-user
# - UserPromptSubmit: user sent new prompt → remove $cwd/.local/.awaiting-user
# Silent-exits on any failure.

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)

[[ -n "$cwd" && -d "$cwd/.local" ]] || exit 0

marker="$cwd/.local/.awaiting-user"

case "$event" in
    Stop)
        printf '%s\n' "$(date +%s)" > "$marker" 2>/dev/null
        ;;
    UserPromptSubmit)
        rm -f "$marker" 2>/dev/null
        ;;
esac

exit 0
