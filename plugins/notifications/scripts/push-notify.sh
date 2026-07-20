#!/bin/bash
# Push notification hook for Notification events (permission prompts, 60s idle).
# Delegates to the notify() function in ../lib/notify.sh so there's one
# source of truth for the push logic. The agent calls notify() directly when
# blocking (when the lib is sourced into the shell); this hook covers
# harness-level events the agent can't intercept — and doubles as the push
# backstop when the shell helper is not installed.
#
# Two event classes, handled differently (clam-code#264 / P7):
#   - Permission prompt: ALWAYS pages. An unattended watch fire wedged on a
#     permission ask needs the user regardless of TODO state or a recent silent
#     stop, so it bypasses the silent-stop stack and the summoning-state gate.
#   - Idle / everything else (the 60s "waiting for input" event, and any unknown
#     event): an idle-class push, gated by the silent-stop stack AND the
#     summoning-state gate — it pages only when TODO State is a summoning state
#     (Blocked / Waiting For Decision / Awaiting User Review). A parked,
#     non-summoning session is re-woken by its own watch cron and needs nothing
#     from the user, so its idle event must NOT push (the #264 leak).
#
# The permission vs idle split reads the structured notification_type field
# (permission_prompt / idle_prompt); older builds may omit it, so a message-text
# fallback matches "permission". Anything not clearly a permission prompt is
# treated as idle-class — the leak-safe default (the bug is idle pushes leaking
# in non-summoning parks).
#
# Escape hatch (idle class only): when .local/.silent-stop exists in the cwd
# this hook exits silently. The flag is NOT deleted here — stop-notify.sh
# consumes it at the end of the turn — so all idle events within the same silent
# turn stay suppressed.
#
# CLAM_NOTIFICATIONS_GATE=disabled at launch turns off every hook in this
# plugin (hooks do not see mid-session exports).
#
# No set -e, matching the plugin's other hooks: a notification hook that hits
# an unexpected non-zero should degrade silently, not abort the event.

[[ "${CLAM_NOTIFICATIONS_GATE:-enabled}" == "enabled" ]] || exit 0
[[ -z "$CLAUDE_PUSH_NTFY_TOPIC" ]] && exit 0

input=$(cat)
cwd=""
notif_type=""
message=""
if command -v jq &>/dev/null; then
    cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
    notif_type=$(echo "$input" | jq -r '.notification_type // empty' 2>/dev/null)
    message=$(echo "$input" | jq -r '.message // empty' 2>/dev/null)
fi
[[ -z "$cwd" ]] && exit 0

# Plan mode suppresses ALL pushes (the user is actively planning). Applies to
# permission prompts too — unchanged behavior.
mode_file="$cwd/.local/.permission-mode"
if [[ -f "$mode_file" ]] && [[ "$(cat "$mode_file" 2>/dev/null)" == "plan" ]]; then
    exit 0
fi

PLUGIN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)"

push_now() {
    # shellcheck source=../lib/notify.sh
    source "$PLUGIN_LIB_DIR/notify.sh"
    # Pass the worktree name AND its dir (the session cwd): notify resolves the
    # worktree dir from the explicit arg, so any session — wherever its worktree
    # lives — reads the right TODO.md and drops its dedup markers in its own
    # .local (no ghost dirs).
    notify "${cwd##*/}" "$cwd"
}

# Classify the event. Primary discriminator is the structured notification_type;
# fall back to the message text when the field is absent (older builds).
is_permission=0
if [[ "$notif_type" == "permission_prompt" ]]; then
    is_permission=1
elif [[ -z "$notif_type" ]]; then
    case "$message" in
        *[Pp]ermission*) is_permission=1 ;;
    esac
fi

# Permission prompts always page (bypass the idle-suppression stack + state gate).
if (( is_permission )); then
    push_now
    exit 0
fi

# --- Idle-class event: silent-stop stack, then the summoning-state gate ------

if [[ -f "$cwd/.local/.silent-stop" ]]; then
    exit 0
fi

# Suppress when stop-notify recently went silent. Stop fires before the 60s
# idle that triggers this hook, so a .silent-stop flag set by the agent has
# already been consumed and removed by the time we get here — the timestamp
# below is the durable signal.
last_silent="$cwd/.local/.last-silent-stop"
silent_window="${CLAUDE_PUSH_SILENT_STOP_WINDOW_SECONDS:-90}"
if [[ -f "$last_silent" ]] && (( silent_window > 0 )); then
    last_ts=$(cat "$last_silent" 2>/dev/null || echo 0)
    if (( $(date +%s) - last_ts <= silent_window )); then
        exit 0
    fi
fi

# Summoning-state gate (P7): an idle Notification pushes ONLY when the session is
# in a summoning state. A parked, non-summoning session (Awaiting CI, Awaiting
# Human Review, ...) needs nothing from the user — its watch cron re-wakes it —
# so pushing on its 60s idle is the #264 leak. Source summoning-ness from the
# manifest (states.tsv summons column via states.sh), never a hardcoded list, so
# a future state inherits correct paging. Fail open (push) when the lib or TODO
# is missing, or the state is unset/unknown/non-parked: the safe default is to
# page (a wedged non-parked session must still summon).
todo="$cwd/.local/TODO.md"
states_lib="$PLUGIN_LIB_DIR/states.sh"
if [[ -f "$todo" && -f "$states_lib" ]]; then
    # shellcheck source=../lib/states.sh
    source "$states_lib"
    state=$(todo_field "$todo" State)
    if [[ -n "$state" ]] && state_is_parked "$state" && ! state_summons "$state"; then
        exit 0
    fi
fi

push_now
