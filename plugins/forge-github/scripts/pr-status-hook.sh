#!/bin/bash
# Stop-event wrapper around pr-status-refresh.sh, which holds all fetch and
# cache-write behavior (spec: docs/protocols/pr-status-cache.md). Turn-end
# refreshes use a short 60s TTL so the cache is fresh right after pushes and
# PR creation; other callers may run the same engine with a longer TTL.

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)

[[ "$event" == "Stop" ]] || exit 0
[[ -n "$cwd" ]] || exit 0

engine="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/pr-status-refresh.sh"
[[ -f "$engine" ]] || exit 0

exec bash "$engine" "$cwd" 60
