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

# Contract: B03 — unpark-nudge
#
# Behavior:
#   Turn-START drift prevention, complementing the turn-END freshness gate
#   (B02 in keep-working.sh). When the user submits a prompt into a session
#   whose TODO State is a PARKED state (states.tsv category "parked", e.g.
#   Awaiting User Review), print a nudge to stdout — UserPromptSubmit stdout
#   is injected into conversation context — reminding the agent that the park
#   may be over: if this turn resumes substantive work, set State: In Progress
#   and record the direction change (what the user asked, any pivot from the
#   recorded plan) in TODO.md before proceeding; if the turn is a mere
#   acknowledgement with no new work, the State may stand.
#
# Inputs:
#   $marker — outer scope: $cwd/.local/.awaiting-user. The nudge fires ONLY
#             when the marker exists (the previous turn genuinely ended and
#             this prompt reopens the session); the caller removes the marker
#             immediately after, so the nudge fires at most once per
#             return-to-parked-session, with no epoch marker of its own.
#   $cwd    — outer scope. State read via todo_field from
#             $cwd/.local/TODO.md; lib/states.sh provides todo_field and
#             state_is_parked (sourced lazily by this function; the script
#             must keep working without the lib — fail-open, no nudge).
#   CLAM_TRACKING_UNPARK_NUDGE — "disabled" turns the nudge off (default
#             enabled).
#
# Outputs:
#   stdout: the nudge text (single fire), naming the current State verbatim
#   and the two-way instruction above. Empty on every skip path — this
#   script's stdout was previously always empty; ONLY this nudge may write
#   to it, and only on the fire path.
#   Return value: always 0 to the caller (the caller also guards with
#   `|| true`); NotImplemented sentinel 90 until implemented.
#
# Errors:
#   Fail-open on everything: no TODO.md, no states lib, no jq, unreadable
#   State, State not parked, marker absent, nudge disabled → no output.
#
# Invariants:
#   - Never blocks or denies the prompt (UserPromptSubmit non-zero exits and
#     "decision" JSON are out of contract for this script — plain stdout
#     context only).
#   - Never writes/removes files; marker lifecycle stays with the caller.
#   - Stop-branch behavior of this script is unchanged by B03.
#
# Edge cases:
#   - State Blocked / Waiting For Decision (needs_user, not parked): no nudge
#     — the user answering a summons is the designed flow, not drift.
#   - Active states (In Progress / Not Started): no nudge.
#   - Marker exists but TODO.md was deleted mid-session: no nudge.
#   - Two prompts in quick succession: first removes the marker, second finds
#     none → single fire.
unpark_nudge() {
    [[ "${CLAM_TRACKING_UNPARK_NUDGE:-}" == "disabled" ]] && return 0

    local script_dir states_lib
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || return 0
    states_lib="$script_dir/../lib/states.sh"
    [[ -f "$states_lib" ]] || return 0
    # shellcheck source=/dev/null
    source "$states_lib" 2>/dev/null || return 0

    local todo="$cwd/.local/TODO.md"
    [[ -f "$todo" ]] || return 0

    local state
    state=$(todo_field "$todo" "State")
    [[ -n "$state" ]] || return 0
    [[ "$(state_category "$state")" == "parked" ]] || return 0

    cat <<EOF
[CLAM UNPARK NUDGE] This session was parked in State: ${state}. If this turn resumes substantive work, set State: In Progress and record the direction change (what the user asked, any pivot from the recorded plan) in TODO.md before proceeding. If this turn is a mere acknowledgement with no new work, the State may stand.
EOF

    return 0
}

case "$event" in
    Stop)
        printf '%s\n' "$(date +%s)" > "$marker" 2>/dev/null
        ;;
    UserPromptSubmit)
        if [[ -f "$marker" ]]; then
            unpark_nudge || true
        fi
        rm -f "$marker" 2>/dev/null
        ;;
esac

exit 0
