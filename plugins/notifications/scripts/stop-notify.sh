#!/bin/bash
# Fires on every Stop event. Quiet by default: rings the bell, shows a desktop
# notification, and yellows the tmux pane border only on the TRANSITION into a
# summoning State (the states.tsv summons column: Blocked, Waiting For Decision,
# Awaiting User Review). A re-stop in the same summoning State (e.g. a cron-woken
# turn that ended still-Blocked with nothing new) stays silent, as do all other
# states (Complete, In Progress, parked Awaiting *, no TODO.md). The transition
# is tracked per worktree in .local/.last-stop-state; a user prompt clears it
# (prompt-timestamp.sh) so a fresh summons after the user replies rings again.
#
# Escape hatch: touch .local/.silent-stop in the cwd before the turn ends and
# this hook becomes silent even when the state would otherwise notify. The flag
# is consumed (deleted) on this Stop; the transition marker is left untouched
# (this path exits before the State read), so the next stop in that state still
# rings. Use this from cron-driven prompts that polled and found nothing worth
# pinging the user about.
#
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
key=$(echo -n "$cwd" | md5 -q 2>/dev/null || echo -n "$cwd" | md5sum | cut -d' ' -f1)
stamp_file="$stamp_dir/$key"

# Records the time of the last silent stop so the (later) idle Notification
# event in push-notify.sh can suppress the ntfy push for a short window. We
# can't keep the .silent-stop flag around for push-notify to read because it
# would persist past this turn; the timestamped file ages out cleanly.
mark_silent() {
    mkdir -p "$cwd/.local" 2>/dev/null
    date +%s > "$cwd/.local/.last-silent-stop"
}

# Explicit silencer set by the agent for this turn.
silent_flag="$cwd/.local/.silent-stop"
if [[ -f "$silent_flag" ]]; then
    rm -f "$silent_flag" "$stamp_file"
    mark_silent
    exit 0
fi

# Shared session-State metadata + the bold-tolerant field reader from the
# manifest lib (../lib/states.sh, vendored; canonical in the tracking plugin).
# A missing lib means a broken plugin install; degrade to a silent no-op
# (consistent with this hook's other silent exits) rather than mis-reading State.
STATES_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)/states.sh"
[[ -f "$STATES_LIB" ]] || exit 0
# shellcheck source=/dev/null
source "$STATES_LIB"

# Read State once (bold-tolerant, from the manifest lib). A missing or empty
# State (no TODO.md, blank field, unknown name) is treated as non-summoning.
state=""
todo="$cwd/.local/TODO.md"
if [[ -f "$todo" ]]; then
    state=$(todo_field "$todo" State)
fi

# Transition epoch: compare against the last stop's State, then record the
# current one so the NEXT stop can dedup against it. Recording happens on every
# stop, summoning or not, so leaving a summoning State and later returning to it
# reads as a fresh transition. Only a known manifest State is recorded; an empty
# or unrecognised State removes the marker (state_category is empty for both), so
# the marker only ever holds a valid State name or is absent.
last_state_file="$cwd/.local/.last-stop-state"
prev_state=""
[[ -f "$last_state_file" ]] && prev_state=$(cat "$last_state_file" 2>/dev/null)
if [[ -n "$(state_category "$state")" ]]; then
    mkdir -p "$cwd/.local" 2>/dev/null
    printf '%s' "$state" > "$last_state_file"
else
    rm -f "$last_state_file"
fi

# Summon gate: ring only on the TRANSITION into a summoning State (states.tsv
# summons column: Blocked, Waiting For Decision, Awaiting User Review). A non-
# summoning State, or a re-stop in the SAME summoning State (nothing new since
# the last page), takes the silent path. The silent path writes .last-silent-stop
# (mark_silent) so push-notify.sh keeps suppressing the idle phone push; the
# ringing path deliberately does NOT, so the idle backstop push fires and
# notify()'s debounce absorbs the double (parity with Blocked).
if ! state_summons "$state" || [[ "$state" == "$prev_state" ]]; then
    rm -f "$stamp_file"
    mark_silent
    exit 0
fi

# Build the notification body from state.
case "$state" in
    "Blocked")              elapsed_msg="Blocked" ;;
    "Waiting For Decision") elapsed_msg="Decision needed" ;;
    "Awaiting User Review") elapsed_msg="Awaiting your review" ;;
    # Self-heal: a future summons=yes State with no arm here still gets a sane body.
    *)                      elapsed_msg="$state" ;;
esac

if [[ -f "$stamp_file" ]]; then
    prompt_time=$(cat "$stamp_file")
    now=$(date +%s)
    elapsed=$((now - prompt_time))
    elapsed_msg="${elapsed_msg} (${elapsed}s)"
    rm -f "$stamp_file"
fi

label=$(basename "$cwd")
[[ -z "$label" ]] && label="Claude Code"

# Ring the bell via terminalSequence so Claude Code emits the BEL on the real
# terminal (sets tmux window_bell_flag for the status indicator + prefix+Tab
# navigation). Hooks have no controlling terminal as of Claude Code 2.1.139, so
# /dev/tty is unavailable; printf keeps the control byte off the command line
# and jq JSON-encodes it. (Requires Claude Code >= 2.1.141.)
command -v jq &>/dev/null && jq -nc --arg seq "$(printf '\007')" '{terminalSequence: $seq}'

# Desktop notification: osascript on macOS, notify-send/paplay on Linux,
# silent no-op otherwise. Quote-escaping for the osascript AppleScript string
# lives in the shared helper now.
DESKTOP_NOTIFY_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)/desktop-notify.sh"
if [[ -f "$DESKTOP_NOTIFY_LIB" ]]; then
    # shellcheck source=../lib/desktop-notify.sh
    source "$DESKTOP_NOTIFY_LIB"
    desktop_notify "$label" "$elapsed_msg"
fi

# Highlight tmux pane border
if [[ -n "$TMUX" ]] && [[ -n "$TMUX_PANE" ]]; then
    tmux select-pane -t "$TMUX_PANE" -P 'bg=default,fg=default' 2>/dev/null
    tmux set-option -p -t "$TMUX_PANE" pane-border-style 'fg=yellow' 2>/dev/null
    tmux set-option -p -t "$TMUX_PANE" pane-active-border-style 'fg=yellow' 2>/dev/null
fi
