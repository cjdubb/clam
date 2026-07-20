#!/bin/bash
# Records the time the user submitted a prompt.
# - $stamp_dir/<cwd-hash>: per-agent. stop-notify.sh uses it to calculate
#   elapsed time on this agent's turn.
# - $stamp_dir/.global: cross-worktree. notify()'s activity gate reads this
#   so pushes from agent A are suppressed when the user is actively typing
#   into agent B (or any other clam agent).
# Escape hatch: CLAM_NOTIFICATIONS_GATE=disabled at launch turns off every
# hook in this plugin (hooks do not see mid-session exports).

[[ "${CLAM_NOTIFICATIONS_GATE:-enabled}" == "enabled" ]] || exit 0

input=$(cat)
cwd=""
if command -v jq &>/dev/null; then
    cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
fi
[[ -z "$cwd" ]] && exit 0

stamp_dir="/tmp/claude-prompt-timestamps"
mkdir -p "$stamp_dir"
# Use cwd hash as filename so concurrent sessions don't collide
key=$(echo -n "$cwd" | md5 -q 2>/dev/null || echo -n "$cwd" | md5sum | cut -d' ' -f1)
now=$(date +%s)
echo "$now" > "$stamp_dir/$key"
echo "$now" > "$stamp_dir/.global"

# Reset the stop-notify transition epoch: a user prompt means the next Stop in a
# summoning State (Blocked / Waiting For Decision / Awaiting User Review) is a
# fresh transition and rings, even when the State name is unchanged (e.g. a new
# Blocked question asked right after the user replied and stepped away).
rm -f "$cwd/.local/.last-stop-state"
