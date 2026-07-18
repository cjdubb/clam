#!/bin/bash
# CANONICAL home of the clam session-State manifest. The statusline plugin
# carries a vendored copy (plugins/statusline/lib/); keep the two in lockstep.
# Single source of truth for clam workflow session States (the TODO.md `State:`
# field). Sourced by the Stop hook (general/hooks/keep-working.sh), the
# stop notifier (general/hooks/stop-notify.sh), the statusline
# (general/statusline/context.sh), and the orchestrator chunk-status script
# (general/skills/subagent-orchestration/scripts/check-chunk-status.sh). The
# bold-tolerant field reader todo_field() is also mirrored in general/lib/notify.sh.
#
# To add or change a State, edit general/lib/states.tsv. general/lib/states.test.sh
# guards the markdown enumerations (system-prompt.md, TODO-TEMPLATE.md,
# reference.md) against drift from this manifest.
#
# bash 3.2 safe: macOS /bin/bash (which runs the hooks) is 3.2, so NO
# associative arrays. Lookups are awk over the tiny TSV. The manifest is
# resolved relative to THIS file, so the helpers work under any cwd.

_CLAM_STATES_TSV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/states.tsv"

# todo_field <todo-file> <label> -> the first matching field's value, trimmed,
# tolerating an optional markdown-bold label (matches **State:** as well as the
# plain State:). Handover/agent-improvised TODO.md files sometimes bold the
# metadata block; without this the `^State:` consumers read the field as empty
# and the Stop hook blocks every turn-end (issue #176).
#
# Pure text extraction with no manifest dependency; <label> MUST be a trusted
# literal (a workflow field name, no regex metacharacters) since it is
# interpolated into the pattern. Empty output when the field is absent or the
# file is unreadable. bash 3.2 safe (grep/sed only).
#
# notify.sh carries a byte-identical twin (_clam_todo_field) because it is
# sourced into the interactive zsh shell, where this lib's BASH_SOURCE path
# resolution does not work. Keep the two bodies in lockstep; states.test.sh and
# notify.test.sh both pin the bold/plain behavior so a drift is caught.
todo_field() {
    grep -m1 -E "^[*]{0,2}$2:" "$1" 2>/dev/null \
        | sed -E "s/^[*]{0,2}$2:[*]{0,2}[[:space:]]*//; s/[[:space:]]*\$//"
}

# state_category <state> -> category (active|parked|needs_user|terminal), or empty.
state_category() {
    awk -F'\t' -v s="$1" '/^#/ {next} $1 == s {print $2; exit}' "$_CLAM_STATES_TSV"
}

# state_is_parked <state> -> exit 0 when the State is parked (turn may end,
# resumes on its own with no user action).
state_is_parked() {
    [ "$(state_category "$1")" = "parked" ]
}

# state_summons <state> -> exit 0 when the State pages the user (summons column
# is "yes": bell + toast + tmux border + phone push). Unknown or empty States
# return nonzero (fail-quiet, matching the state_emoji/state_color fallbacks).
state_summons() {
    [ "$(awk -F'\t' -v s="$1" '/^#/ {next} $1 == s {print $5; exit}' "$_CLAM_STATES_TSV")" = "yes" ]
}

# state_emoji <state> -> statusline glyph (fallback "•" for an unknown State).
state_emoji() {
    local e
    e=$(awk -F'\t' -v s="$1" '/^#/ {next} $1 == s {print $3; exit}' "$_CLAM_STATES_TSV")
    if [ -n "$e" ]; then printf '%s' "$e"; else printf '%s' "•"; fi
}

# state_color <state> -> 256-colour number (fallback "245"/dim for unknown).
state_color() {
    local c
    c=$(awk -F'\t' -v s="$1" '/^#/ {next} $1 == s {print $4; exit}' "$_CLAM_STATES_TSV")
    if [ -n "$c" ]; then printf '%s' "$c"; else printf '%s' "245"; fi
}

# state_parked_list -> parked State names, one per line, in manifest order.
# Single source for both the Stop hook's allow-check and the names printed in
# its reject message, so the two cannot drift (the #137 regression).
state_parked_list() {
    awk -F'\t' '/^#/ {next} $2 == "parked" {print $1}' "$_CLAM_STATES_TSV"
}

# state_names -> every State name, one per line (used by the sync test).
state_names() {
    awk -F'\t' '/^#/ {next} NF {print $1}' "$_CLAM_STATES_TSV"
}
