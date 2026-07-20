#!/bin/bash
# Fires when Claude Code needs user attention (permission prompt, idle, etc.)
# Sends terminal bell (tmux flags the window) + desktop notification
# with the working directory so the user can identify which agent.
#
# State gate: suppress output when TODO.md says the session is parked and NOT
# summoning (Awaiting Agent, Awaiting CI, and the other silent Awaiting *
# states). Those resume on their own; pinging the user for them is pure noise
# and causes notification fatigue. Awaiting User Review is parked yet summoning,
# so it is excluded from the gate and gets permission-prompt/idle bells like
# Blocked. The gate mirrors stop-notify.sh's summons-driven behaviour.
#
# Escape hatch: CLAM_NOTIFICATIONS_GATE=disabled at launch turns off every
# hook in this plugin (hooks do not see mid-session exports).

[[ "${CLAM_NOTIFICATIONS_GATE:-enabled}" == "enabled" ]] || exit 0

input=$(cat)

# Extract cwd early so the state gate can read TODO.md.
cwd=""
if command -v jq &>/dev/null; then
    cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
fi

PLUGIN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)"

# State gate: suppress when the session is parked and not summoning. The shared
# states lib provides state_is_parked()/state_summons(); a missing lib means a
# broken install, so degrade to the old unconditional-fire behavior (safe default).
STATES_LIB="$PLUGIN_LIB_DIR/states.sh"
if [[ -n "$cwd" ]] && [[ -f "$STATES_LIB" ]]; then
    # shellcheck source=/dev/null
    source "$STATES_LIB"
    todo="$cwd/.local/TODO.md"
    if [[ -f "$todo" ]]; then
        state=$(todo_field "$todo" State)
        if [[ -n "$state" ]] && state_is_parked "$state" && ! state_summons "$state"; then
            exit 0
        fi
    fi
fi

# Ring the bell so tmux raises window_bell_flag (status-bar indicator +
# prefix+Tab navigation). Claude Code 2.1.139+ runs hooks without a controlling
# terminal, so /dev/tty is "Device not configured"; return a BEL in the
# allowlisted terminalSequence field and Claude Code emits it on the real
# terminal for us. printf keeps the control byte off the command line; jq
# JSON-encodes it correctly. (Requires Claude Code >= 2.1.141.)
command -v jq &>/dev/null && jq -nc --arg seq "$(printf '\007')" '{terminalSequence: $seq}'

# Extract message from hook JSON (cwd already extracted above for the state gate)
message=""
if command -v jq &>/dev/null; then
    message=$(echo "$input" | jq -r '.message // empty' 2>/dev/null)
fi

# Derive a short label from the working directory (worktree name or basename)
label=""
if [[ -n "$cwd" ]]; then
    label=$(basename "$cwd")
fi
[[ -z "$label" ]] && label="Claude Code"
[[ -z "$message" ]] && message="Needs your attention"

# Desktop notification (title = worktree/directory name): osascript on macOS,
# notify-send/paplay on Linux, silent no-op otherwise. Quote-escaping for the
# osascript AppleScript string lives in the shared helper now.
DESKTOP_NOTIFY_LIB="$PLUGIN_LIB_DIR/desktop-notify.sh"
if [[ -f "$DESKTOP_NOTIFY_LIB" ]]; then
    # shellcheck source=../lib/desktop-notify.sh
    source "$DESKTOP_NOTIFY_LIB"
    desktop_notify "$label" "$message"
fi

# Highlight tmux pane border if inside tmux
if [[ -n "$TMUX" ]] && [[ -n "$TMUX_PANE" ]]; then
    tmux select-pane -t "$TMUX_PANE" -P 'bg=default,fg=default' 2>/dev/null
    tmux set-option -p -t "$TMUX_PANE" pane-border-style 'fg=yellow' 2>/dev/null
    tmux set-option -p -t "$TMUX_PANE" pane-active-border-style 'fg=yellow' 2>/dev/null
fi
