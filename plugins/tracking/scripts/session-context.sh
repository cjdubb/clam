#!/bin/bash
# SessionStart hook for the tracking plugin. Four jobs:
#
# 1. Inject the Work Management rules (ported from clam-code's system-prompt
#    Work Management section) as additionalContext, so tracking-doc discipline
#    holds without the clam alias / --append-system-prompt-file mechanism.
# 2. Auto-create TODO.md: when $cwd/.local/ exists as a directory but
#    $cwd/.local/TODO.md does not, copy the template from
#    $PLUGIN_ROOT/templates/TODO.md, substitute [branch-name] with the git
#    branch and [YYYY-MM-DD] / [YYYY-MM-DD HH:MM] with the current date/time,
#    and write the result. Fail-open: missing template or write failure must
#    not break session start. Must run BEFORE the resume check (job 3) so a
#    freshly auto-created TODO.md triggers resume injection.
# 3. Resume support: when the cwd already has .local/TODO.md, surface its
#    State and Current Task and instruct the session to read the tracking docs
#    before doing anything else — this is what makes /clear + fresh
#    orchestrator pickup work.
# 4. Clear the once-per-session-epoch markers (.decision-nudge-fired) that
#    scripts/keep-working.sh sets, on every SessionStart event (startup,
#    resume, clear, compact) — the same epoch semantics clam-code implemented
#    across session-track.sh and post-compact.sh.
#
# Fail-open: any error exits 0 with no output rather than breaking session start.

set -u

command -v jq >/dev/null 2>&1 || exit 0

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
STATES_LIB="$PLUGIN_ROOT/lib/states.sh"
# shellcheck source=/dev/null
[ -f "$STATES_LIB" ] && . "$STATES_LIB"

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

# Epoch markers reset on every session boundary.
[ -n "$cwd" ] && rm -f "$cwd/.local/.decision-nudge-fired" 2>/dev/null

# --- Auto-create TODO.md (B01: auto-create-todo) ---
#
# Behavior: when $cwd/.local/ exists as a directory but $cwd/.local/TODO.md
#   does not, copy $PLUGIN_ROOT/templates/TODO.md into $cwd/.local/TODO.md
#   with placeholder substitution.
# Inputs: $cwd (from hook JSON), $PLUGIN_ROOT (resolved above).
# Outputs: $cwd/.local/TODO.md on disk (or nothing on failure).
# Substitutions:
#   - [branch-name] → current git branch (empty string if not in a git repo)
#   - [YYYY-MM-DD HH:MM] → current date+time (local timezone)
#   - [YYYY-MM-DD] → current date (local timezone, only standalone occurrences
#     not already covered by the HH:MM substitution)
# Errors: fail-open — missing template, unwritable directory, or any error
#   must exit 0 with no output, never breaking session start.
# Invariants:
#   - NEVER overwrites an existing TODO.md.
#   - Runs BEFORE the resume-context check below so a freshly created TODO.md
#     triggers resume injection on the same SessionStart event.
#   - bash 3.2 safe (no associative arrays, no bash 4+ features).
# Edge cases:
#   - $cwd/.local/ does not exist → no-op.
#   - Template file missing → no-op.
#   - git not available or not in a repo → [branch-name] substituted with "".
#   - Write fails (read-only fs, permissions) → no-op, no error output.
_auto_create_todo() {
    [ -d "$cwd/.local" ] || return 0
    [ ! -f "$cwd/.local/TODO.md" ] || return 0
    local tmpl="$PLUGIN_ROOT/templates/TODO.md"
    [ -f "$tmpl" ] || return 0
    local branch
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null || true)
    local datetime
    datetime=$(date '+%Y-%m-%d %H:%M')
    local today
    today=$(date '+%Y-%m-%d')
    sed -e "s/\[branch-name\]/${branch:-}/g" \
        -e "s/\[YYYY-MM-DD HH:MM\]/${datetime}/g" \
        -e "s/\[YYYY-MM-DD\]/${today}/g" \
        "$tmpl" > "$cwd/.local/TODO.md" 2>/dev/null || rm -f "$cwd/.local/TODO.md" 2>/dev/null
}
[ -n "$cwd" ] && _auto_create_todo

rules=$(cat <<EOF
# Tracking (clam tracking plugin)

All work tracking uses \`.local/\` files in the current worktree as the single
source of truth. Do NOT use the built-in TaskCreate/TaskUpdate/TaskList/TaskGet
tools; they write to ~/.claude/tasks/, which is not visible or discoverable.

Update \`.local/TODO.md\` in real time — write state as you go, not at session
end. Compaction can happen at any time; state that lives only in conversation
is lost. Create it from the template at \`$PLUGIN_ROOT/templates/TODO.md\` when
starting tracked work. Persist immediately: decisions and plan changes to
\`.local/PLAN.md\` (append to its Changelog after creation), task changes to
\`TODO.md\`, failed fix attempts to \`.local/TROUBLESHOOTING.md\` before trying
the next approach.

State lifecycle (\`State:\` field in TODO.md). Three states summon the user
(bell, dashboard flag, push — once on the transition in, not on every turn):

- **Needs the user (stopped):** \`Blocked\` (a human must act; populate
  \`Blocked Reason:\`) and \`Waiting For Decision\` (user must choose between
  approaches; first write the analysis to \`.local/decisions/NNN-<slug>.md\`
  per the /decision-log:rundown template — options, evidence, recommendation,
  if-deferred path — then populate \`Decision Needed:\` with the question, the
  recommended option, and the file path).
- **Parked, summons once then waits:** \`Awaiting User Review\` (draft PR up,
  user reviewing at their own pace).
- **Parked, resumes on its own, stays silent:** \`Awaiting Agent\`,
  \`Awaiting CI\`, \`Awaiting Independent Agent Review\`, \`Awaiting Bot
  Review\`, \`Awaiting Reviewer Assignment\`, \`Awaiting Human Review\`,
  \`Awaiting Merge Queue\`. Put what is in flight in \`Current Task:\`.
- **Active/terminal:** \`Not Started\`, \`In Progress\` (do not end a turn
  here unless genuinely still going — the Stop hook nudges), \`Complete\`
  (only when no actionable work remains in this session's scope).

Never park on \`Blocked\`/\`Waiting For Decision\` when no user action is
required — a false summons trains the user to ignore real ones. On the
transition into a summoning state, run \`notify <worktree-basename>\` if that
helper is installed (\`command -v notify\`; skip silently otherwise).

A turn ending in a summoning state must END with a user-facing message that
restates the blocker or decision in plain terms — what is needed, from whom,
what actions to take — mirrored into \`Blocked Reason:\`/\`Decision Needed:\`.
The screen-bottom line is what the user sees first; do not assume they scroll
up. For decisions, make each option decidable at a glance: plain-terms
meaning, one-line trade-off, recommendation and why, the default on a bare
"go", and the decision-file path (~10 lines for a 2-3 option decision).
EOF
)

resume=""
if [ -n "$cwd" ] && [ -f "$cwd/.local/TODO.md" ]; then
    state=""
    task=""
    if command -v todo_field >/dev/null 2>&1; then
        state=$(todo_field "$cwd/.local/TODO.md" State)
        task=$(todo_field "$cwd/.local/TODO.md" "Current Task")
    fi
    resume=$(cat <<EOF


# Tracking document present — resume from it

This worktree already has \`.local/TODO.md\` (State: ${state:-unknown};
Current Task: ${task:-unset}). Before doing anything else, read
\`.local/TODO.md\` — plus \`.local/PLAN.md\` and any \`.local/decisions/\`
files if present — and continue from the recorded state. Do not restart
completed work; trust the tracking docs over assumptions about a fresh start.
EOF
)
fi

printf '%s%s' "$rules" "$resume" | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
