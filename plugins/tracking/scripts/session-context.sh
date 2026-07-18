#!/bin/bash
# SessionStart hook for the tracking plugin. Three jobs:
#
# 1. Inject the Work Management rules (ported from clam-code's system-prompt
#    Work Management section) as additionalContext, so tracking-doc discipline
#    holds without the clam alias / --append-system-prompt-file mechanism.
# 2. Resume support: when the cwd already has .local/TODO.md, surface its
#    State and Current Task and instruct the session to read the tracking docs
#    before doing anything else — this is what makes /clear + fresh
#    orchestrator pickup work.
# 3. Clear the once-per-session-epoch markers (.decision-nudge-fired) that
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
