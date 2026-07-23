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
# 4. Clear the once-per-session-epoch markers (.decision-nudge-fired,
#    .no-todo-nudge-fired) that scripts/keep-working.sh sets, on every
#    SessionStart event (startup, resume, clear, compact) — the same epoch
#    semantics clam-code implemented across session-track.sh and
#    post-compact.sh.
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
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

# Epoch markers reset on every session boundary.
[ -n "$cwd" ] && rm -f "$cwd/.local/.decision-nudge-fired" "$cwd/.local/.no-todo-nudge-fired" "$cwd/.local/.flush-nudge-fired" "$cwd/.local/.freshness-nudge-fired" 2>/dev/null

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

Park unresolved conversation threads (a question asked but never answered, a naming/design thread left hanging) in \`TODO.md\`'s Open Questions section in real time, and clear each entry once it is resolved, recording the answer where it belongs (Implementation Log, PLAN.md's Changelog, or a decisions/ file).

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

# Contract: B04 — resume-freshness
#
# Behavior:
#   Reader-side staleness net for the resume injection below. Before telling
#   a fresh session to trust the tracking docs, cross-check the docs' age
#   against actual conversation activity recorded on disk:
#     ref      = mtime(.local/TODO.md)
#     prior    = activity_prior_transcripts($cwd, $transcript_path)   [B01]
#     count    = sum over the NEWEST 5 prior transcripts of
#                activity_prompts_since(ref, transcript)              [B01]
#   When count >= CLAM_TRACKING_RESUME_STALE_THRESHOLD (default 1), the docs
#   demonstrably lag the last conversation: print (stdout) a STALE-variant
#   resume block that REPLACES the trust-the-docs text. It must contain, in
#   plain terms:
#     - a warning that .local/TODO.md may be STALE: it was last updated at
#       <ISO-8601 local time of ref> but ~<count> human prompt(s) arrived
#       after that (most recent conversation activity: <ISO-8601 local mtime
#       of the newest prior transcript>);
#     - the newest prior transcript's absolute path, with the instruction to
#       read its TAIL (the last ~30 entries) to recover pivots, decisions,
#       and open questions the docs missed, BEFORE trusting recorded state;
#     - the instruction to still read .local/TODO.md, .local/PLAN.md, and
#       .local/decisions/, then reconcile: update the docs with anything the
#       transcript tail shows the docs missed, before resuming work;
#     - the current recorded State and Current Task (same fields the fresh
#       variant surfaces).
#   When count < threshold, or on ANY failure/uncertainty: print nothing —
#   the caller falls back to the existing trust-the-docs resume block.
#
# Inputs:
#   $cwd, $transcript_path — outer scope (transcript_path is the CURRENT
#     session's transcript, passed as the exclusion to
#     activity_prior_transcripts so a resumed session never reads itself as
#     "prior" activity; empty is fine — nothing to exclude).
#   $cwd/.local/TODO.md — must exist (caller only invokes when it does).
#   lib/activity.sh, lib/platform.sh (clam_mtime_epoch) — sourced lazily;
#     absent → fail-open (no output).
#   CLAM_TRACKING_RESUME_STALE_GATE — "disabled" turns the check off
#     (default enabled).
#   CLAM_TRACKING_RESUME_STALE_THRESHOLD — integer >= 1, default 1 (one
#     unreflected human prompt at recap time is worth a warning); invalid → 1.
#
# Outputs:
#   stdout: the complete stale-variant resume block, or nothing. Never
#   partial output. Return 0 on both paths (90 NotImplemented sentinel until
#   implemented; caller treats any output-less path identically).
#
# Errors:
#   Fail-open everywhere: no jq, no libs, unreadable TODO mtime, no project
#   dir, count non-numeric → no output (fresh-variant behavior).
#
# Invariants:
#   - Pure read; no markers, no writes.
#   - Bounded work: at most 5 transcripts scanned, single pass each, within
#     the hook's 10s timeout.
#   - The stale variant must NOT say "trust the tracking docs" — the two
#     variants are mutually exclusive by construction.
#
# Edge cases:
#   - Post-compaction SessionStart: the continuing session's own transcript
#     is excluded via $transcript_path; other prior transcripts still count.
#   - Brand-new worktree, no project dir yet → fresh variant.
#   - TODO.md auto-created moments ago by _auto_create_todo (mtime ~now) →
#     count vs a just-now ref is 0 → fresh variant (correct: nothing recorded
#     to be stale yet — the transcripts predate the tracking, not the
#     reverse; acceptable known limit of the mtime reference).
_resume_freshness() {
    [ "${CLAM_TRACKING_RESUME_STALE_GATE:-}" = "disabled" ] && return 0
    [ -n "$cwd" ] && [ -f "$cwd/.local/TODO.md" ] || return 0

    local activity_lib platform_lib
    activity_lib="$PLUGIN_ROOT/lib/activity.sh"
    platform_lib="$PLUGIN_ROOT/lib/platform.sh"
    [ -f "$activity_lib" ] && [ -f "$platform_lib" ] || return 0
    # shellcheck source=/dev/null
    . "$activity_lib"
    # shellcheck source=/dev/null
    . "$platform_lib"
    command -v activity_prior_transcripts >/dev/null 2>&1 || return 0
    command -v activity_prompts_since >/dev/null 2>&1 || return 0
    command -v clam_mtime_epoch >/dev/null 2>&1 || return 0

    local threshold="${CLAM_TRACKING_RESUME_STALE_THRESHOLD:-}"
    case "$threshold" in
        ''|*[!0-9]*|0) threshold=1 ;;
    esac

    local ref_epoch
    ref_epoch=$(clam_mtime_epoch "$cwd/.local/TODO.md" 2>/dev/null)
    case "$ref_epoch" in ''|*[!0-9]*|0) return 0 ;; esac

    local prior
    prior=$(activity_prior_transcripts "$cwd" "$transcript_path" 2>/dev/null)
    [ -n "$prior" ] || return 0

    # Sum activity_prompts_since over the newest 5 prior transcripts only
    # (already mtime-descending from activity_prior_transcripts); track the
    # first (newest) one for the report below.
    local newest="" total=0 n=0 line count
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        n=$((n + 1))
        [ "$n" -gt 5 ] && break
        [ -z "$newest" ] && newest="$line"
        count=$(activity_prompts_since "$ref_epoch" "$line" 2>/dev/null)
        case "$count" in ''|*[!0-9]*) count=0 ;; esac
        total=$((total + count))
    done <<PRIOR_EOF
$prior
PRIOR_EOF

    [ -n "$newest" ] || return 0
    [ "$total" -ge "$threshold" ] || return 0

    local newest_mtime
    newest_mtime=$(clam_mtime_epoch "$newest" 2>/dev/null)
    case "$newest_mtime" in ''|*[!0-9]*) newest_mtime=0 ;; esac

    # Portable epoch->local-ISO-8601: BSD `date -r <epoch>` first (fails fast
    # on GNU, no such file), then GNU `date -d "@<epoch>"`.
    local ref_iso newest_iso
    ref_iso=$(date -r "$ref_epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -d "@$ref_epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)
    newest_iso=$(date -r "$newest_mtime" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -d "@$newest_mtime" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)
    [ -n "$ref_iso" ] && [ -n "$newest_iso" ] || return 0

    cat <<STALE_EOF
# Tracking document may be STALE — verify before resuming

\`.local/TODO.md\` was last updated at ${ref_iso}, but ~${total} human prompt(s) arrived in this worktree's conversation after that (most recent conversation activity: ${newest_iso}).

Before trusting recorded state: read the TAIL (the last ~30 entries) of the most recent prior transcript to recover pivots, decisions, and open questions the docs may have missed:
${newest}

Then still read \`.local/TODO.md\`, \`.local/PLAN.md\`, and any \`.local/decisions/\` files, and reconcile — update the docs with anything the transcript tail shows they missed, before resuming work.

Recorded State: ${state:-unknown}
Recorded Current Task: ${task:-unset}
STALE_EOF
}

resume=""
if [ -n "$cwd" ] && [ -f "$cwd/.local/TODO.md" ]; then
    state=""
    task=""
    if command -v todo_field >/dev/null 2>&1; then
        state=$(todo_field "$cwd/.local/TODO.md" State)
        task=$(todo_field "$cwd/.local/TODO.md" "Current Task")
    fi
    # B04: the stale-variant block replaces the trust-the-docs text when the
    # docs demonstrably lag recorded conversation activity. Empty output (or
    # the NotImplemented sentinel) falls through to the fresh variant.
    stale_block=$(_resume_freshness 2>/dev/null) || stale_block=""
    if [ -n "$stale_block" ]; then
        resume=$(printf '\n\n%s' "$stale_block")
    else
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
fi

printf '%s%s' "$rules" "$resume" | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
