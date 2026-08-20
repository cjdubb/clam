#!/bin/bash
# Stop hook: prevents the agent from ending its turn while .local/TODO.md
# State is In Progress / Not Started. Allows stop only when State indicates
# work is genuinely complete or paused for the user.
#
# Enabling the tracking plugin is the opt-in (clam-code gated this behind the
# clam alias's $CLAM_SESSION; plugins are enabled per-repo instead). Escape
# hatch: CLAM_TRACKING_STOP_GATE=disabled turns the hook off entirely.
#
# Allows stop when:
#   - CLAM_TRACKING_STOP_GATE is set to disabled (gated out — no log entry written)
#   - jq is unavailable (cannot safely parse input/emit JSON)
#   - stop_hook_active is true (prevents infinite loops if we already nudged once)
#   - .local/TODO.md does not exist (Go Commando, ad-hoc sessions)
#   - State is Blocked or Waiting For Decision (needs the user). Waiting For
#     Decision carries a once-per-epoch decision-file nudge: a park whose
#     Decision Needed field lacks a .local/decisions/ pointer, or that has no
#     open decision file, is blocked once with instructions, then allowed
#     (marker .local/.decision-nudge-fired, cleared on SessionStart/PostCompact)
#   - State is a parked Awaiting * state (the manifest's parked category;
#     see lib/states.tsv) — parked on delegated work, CI, review, or
#     the merge queue; resumes on its own, no user action. The five PR-watched
#     parked states (Awaiting CI, Awaiting Bot Review, Awaiting Reviewer
#     Assignment, Awaiting Human Review, Awaiting Merge Queue) carry the
#     PR-cron backstop below; the three human-review-adjacent ones also carry
#     the independent-review backstop. Every other parked state allows freely.
#   - State is Complete AND any open PR on the current branch has a matching
#     monitoring cron in .claude/scheduled_tasks.json (or there is no open PR),
#     AND the independent-review backstop is satisfied
#
# PR-cron backstop: the hook blocks if the current branch has an open PR but
# no entry in .claude/scheduled_tasks.json whose prompt contains "PR #<number>".
# It fires at State=Complete AND at the five parked states above (#264: a
# park with no watch is blind to an out-of-band merge/close/enqueue/drift).
# This catches PRs parked or completed without the create-pr skill's mandatory
# CronCreate steps. Fail-open: no-op when CLAM_PR_CRONS is disabled, the branch
# is a default branch, there is no open PR, or gh is unavailable.
#
# Independent-review backstop: when CLAM_INDEPENDENT_REVIEW=enabled, the hook
# blocks if the current branch has an open PR (#<N>) but no report at
# .local/INDEPENDENT-REVIEW-PR-<N>.md, so the auto-run self-review cannot be
# silently skipped before a human reviews. It fires on Awaiting Reviewer
# Assignment / Awaiting Human Review / Awaiting Merge Queue / Complete; on those
# it composes with the PR-cron backstop (both must pass to allow). It does NOT
# fire at Awaiting CI / Awaiting Bot Review (which precede human handoff).
# Unset / disabled CLAM_INDEPENDENT_REVIEW makes this a full no-op.
#
# Stop log: every invocation past the stop-gate check appends a JSONL
# entry to $CLAUDE_STOP_LOG (default ~/.claude/stop-log.jsonl) recording
# the disposition for later auditing. Logging is best-effort and silent
# on failure.

set -e

[[ "${CLAM_TRACKING_STOP_GATE:-enabled}" == "enabled" ]] || exit 0

command -v jq &>/dev/null || exit 0

# Session-State metadata (parked-state list, categories) from the shared
# manifest. Fail open (allow stop) if the lib is missing, matching the jq guard.
STATES_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)/states.sh"
[[ -f "$STATES_LIB" ]] || exit 0
# shellcheck source=/dev/null
source "$STATES_LIB"

# Conversation-activity readers (B01) for the freshness gate. Guarded source:
# a missing lib disables the freshness gate only (fail-open), never the whole
# Stop hook — unlike states.sh, nothing else here depends on it.
ACTIVITY_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)/activity.sh"
# shellcheck source=/dev/null
[[ -f "$ACTIVITY_LIB" ]] && source "$ACTIVITY_LIB"

# Cross-platform mtime reader (clam_mtime_epoch) for the freshness gate (B02).
# Guarded source, same rationale as ACTIVITY_LIB above: a missing lib disables
# the freshness gate only (fail-open), never the whole Stop hook.
PLATFORM_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)/platform.sh"
# shellcheck source=/dev/null
[[ -f "$PLATFORM_LIB" ]] && source "$PLATFORM_LIB"

LOG_FILE="${CLAUDE_STOP_LOG:-$HOME/.claude/stop-log.jsonl}"

# Appended to EVERY block reason at emission (not into the stop log). A block
# fires after the agent has already written an end-of-turn message; without
# this note the post-hook closing message tends to cover only the blocker and
# point the user back at content buried behind the hook output.
SELF_CONTAINED_NOTE="This hook fired after your end-of-turn message was already written; that message has scrolled away behind hook output, and the user reads from the bottom without scrolling up. After any remedial work, end the turn with a closing message that is complete on its own: restate the substance of what you already told the user this turn — the actual answer or analysis, not a pointer to it — along with any blocker or decision."

input=$(cat)

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
stop_hook_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

log_stop() {
    local decision="$1"
    local state="${2:-}"
    local reason="${3:-}"
    local ts
    ts=$(date "+%Y-%m-%dT%H:%M:%S%z")
    local worktree=""
    [[ -n "$cwd" ]] && worktree=$(basename "$cwd")
    {
        mkdir -p "$(dirname "$LOG_FILE")"
        jq -nc \
            --arg ts "$ts" \
            --arg cwd "$cwd" \
            --arg worktree "$worktree" \
            --arg session_id "$session_id" \
            --arg decision "$decision" \
            --arg state "$state" \
            --argjson stop_hook_active "$stop_hook_active" \
            --arg reason "$reason" \
            '{ts:$ts, cwd:$cwd, worktree:$worktree, session_id:$session_id, decision:$decision, state:$state, stop_hook_active:$stop_hook_active, reason:$reason}' \
            >> "$LOG_FILE"
    } 2>/dev/null || true
}

# Populates $PR_NUM and $PR_BLOCK_REASON. Returns 0 when monitoring is satisfied
# (no open PR for the current branch, OR a matching cron exists in
# .claude/scheduled_tasks.json). Returns 1 when an open PR exists but no
# matching cron is found.
# Reads outer-scope $cwd (worktree path) and $state (the park State, used to
# name the park-appropriate watch in the block reason).
check_pr_monitoring() {
    PR_NUM=""
    PR_BLOCK_REASON=""

    # PR monitoring crons are opt-IN via CLAM_PR_CRONS in the plugin port
    # (clam-code defaulted unset to enabled). Standalone, without the
    # pr-workflow plugin's create-pr skill scheduling watch crons, "no
    # matching cron" carries no meaning and must not block stop — so unset
    # means disabled. Export CLAM_PR_CRONS=enabled to restore the backstop.
    [[ "${CLAM_PR_CRONS:-disabled}" == "enabled" ]] || return 0

    local branch=""
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null || true)
    [[ -z "$branch" ]] && return 0

    case "$branch" in
        master|main|develop|trunk) return 0 ;;
    esac

    command -v gh &>/dev/null || return 0

    # No `timeout` here: GNU coreutils isn't on macOS by default. The hook
    # itself has a timeout configured in hooks/hooks.json which is
    # the backstop if gh hangs.
    # Note: under merge queue, an enqueued PR still reports --state open
    # until queue CI completes and the merge lands (or the queue ejects it).
    # The cron-presence check below applies uniformly; monitoring should
    # stay alive through both the pre-enqueue and in-queue phases.
    local pr_num=""
    pr_num=$(cd "$cwd" 2>/dev/null || exit 0; gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
    [[ -z "$pr_num" ]] && return 0

    PR_NUM="$pr_num"

    local tasks_file="$cwd/.claude/scheduled_tasks.json"
    if [[ -f "$tasks_file" ]]; then
        local match_count="0"
        match_count=$(jq -r --arg n "PR #$pr_num" '[.tasks[]? | select(.prompt | contains($n))] | length' "$tasks_file" 2>/dev/null || echo 0)
        [[ "${match_count:-0}" -gt 0 ]] && return 0
    fi

    # Name the park-appropriate watch template so the block reason points at
    # the right create-pr section for the state that triggered it.
    local watch_hint
    case "$state" in
        "Awaiting CI")                  watch_hint="the CI watch" ;;
        "Awaiting Bot Review")          watch_hint="the bot-review watch" ;;
        "Awaiting Reviewer Assignment") watch_hint="the PR-state watch" ;;
        "Awaiting Human Review")        watch_hint="the human-review watch" ;;
        "Awaiting Merge Queue")         watch_hint="the merge-queue watch" ;;
        *)                              watch_hint="a CI watch and a bot-review watch" ;;
    esac

    PR_BLOCK_REASON="Stop hook: TODO State is ${state}, but PR #${pr_num} on branch ${branch} has no monitoring cron in ${tasks_file}.

Schedule ${watch_hint} via the /create-pr skill's watch-cron templates, with durable: true. Every watch carries the literal 'PR #${pr_num}' token this hook greps for, opens with the terminal-state preamble, and self-deletes when its condition is met.

If you are intentionally handing off without monitoring (PR awaiting merge, work picked up by a human, etc.), set State: Blocked in .local/TODO.md with a reason and end the turn that way."
    return 1
}

# Populates $IR_BLOCK_REASON. Returns 0 when the independent review is satisfied
# (feature off, no open PR for the current branch, or the report file exists).
# Returns 1 when an open PR exists but its .local/INDEPENDENT-REVIEW-PR-<N>.md
# report is absent. Mirrors check_pr_monitoring's shape; gated independently by
# CLAM_INDEPENDENT_REVIEW so the two backstops compose without coupling.
check_independent_review() {
    IR_BLOCK_REASON=""

    # Independent-review enforcement is opt-in via CLAM_INDEPENDENT_REVIEW (see
    # setup.sh). Unset / disabled is a full no-op: the create-pr skill skips the
    # auto-run, so "no report" carries no meaning and must not block stop.
    [[ "${CLAM_INDEPENDENT_REVIEW:-disabled}" == "enabled" ]] || return 0

    local branch=""
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null || true)
    [[ -z "$branch" ]] && return 0

    case "$branch" in
        master|main|develop|trunk) return 0 ;;
    esac

    command -v gh &>/dev/null || return 0

    # Same open-PR detection as check_pr_monitoring; the hook's 5s managed
    # timeout is the backstop if gh hangs (no `timeout` on macOS by default).
    local pr_num=""
    pr_num=$(cd "$cwd" 2>/dev/null || exit 0; gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
    [[ -z "$pr_num" ]] && return 0

    local report_file="$cwd/.local/INDEPENDENT-REVIEW-PR-${pr_num}.md"
    [[ -f "$report_file" ]] && return 0

    IR_BLOCK_REASON="Stop hook: CLAM_INDEPENDENT_REVIEW is enabled, but PR #${pr_num} on branch ${branch} has no independent-review report at ${report_file}.

If you have not yet asked the engineer this session whether they want independent reviews, ask now — the review is worth skipping in legitimate cases (e.g. rationing a token budget, or a PR too small to warrant a reviewer subagent), and that call is the engineer's. If they decline, write the report file yourself with a one-line note that the engineer opted out of independent review for this PR; that satisfies this check honestly. Ask once per session, then apply the answer to every PR without re-asking.

If the engineer wants the review, run /independent-review (it parks State: Awaiting Independent Agent Review, spawns a fresh read-only reviewer subagent, and writes the report). It supplements the configured bot reviewer and human review; it does not replace them, and the reviewer posts nothing to the PR.

If the review genuinely cannot run (e.g. the reviewer subagent repeatedly fails), set State: Blocked in .local/TODO.md with a reason and end the turn that way."
    return 1
}

# Populates $WFD_BLOCK_REASON. Returns 0 when a Waiting For Decision park
# complies with the decision-file mandate (PR #237): the TODO's Decision Needed
# field references a .local/decisions/ file AND at least one file under
# .local/decisions/ has Status: Open. Returns 1 with the reason otherwise.
# Mirrors the other check_* helpers' shape; the once-per-epoch marker handling
# lives at the call site.
check_decision_file() {
    WFD_BLOCK_REASON=""

    local needed=""
    needed=$(todo_field "$todo" "Decision Needed")

    local has_pointer=1
    [[ "$needed" == *".local/decisions/"* ]] && has_pointer=0

    # Guarded glob: when .local/decisions/ is absent or empty, grep sees the
    # unexpanded pattern, errors into /dev/null, and open_files stays empty.
    local open_files=""
    open_files=$(grep -l '^Status: Open' "$cwd"/.local/decisions/*.md 2>/dev/null || true)

    if [[ "$has_pointer" -eq 0 && -n "$open_files" ]]; then
        return 0
    fi

    local failed=""
    [[ "$has_pointer" -ne 0 ]] && failed="the Decision Needed field does not reference a .local/decisions/ file"
    if [[ -z "$open_files" ]]; then
        [[ -n "$failed" ]] && failed="$failed, and "
        failed="${failed}no file under .local/decisions/ has Status: Open"
    fi

    WFD_BLOCK_REASON="Stop hook: TODO State is Waiting For Decision, but ${failed}.

Write the full decision analysis to .local/decisions/NNN-<slug>.md following the decision-log plugin's rundown template (the /decision-log:rundown skill hosts it; without that plugin, capture the options, the evidence for each, your recommendation, and the if-deferred path in that file), then put the file path in Decision Needed: alongside the question and the recommended option.

Exemption: if this is a single yes/no confirmation with no real alternatives, or live back-and-forth while the user is actively responding, end the turn again; this nudge fires at most once per session epoch."
    return 1
}

# Populates $PLAN_GATE_BLOCK_REASON. Returns 0 when the Lego Block plan gate is
# satisfied — .local/PLAN.md is absent (nothing to gate) OR contains a line
# matching '^## Block Design'. Returns 1 when PLAN.md exists without that heading.
# Recurring by design (no once-per-epoch marker): a non-compliant plan blocks
# EVERY turn-end until the section is added. Gates heading PRESENCE only — content
# quality (real design vs sound N/A reason) stays with human plan review. Mirrors
# the other check_* helpers' shape; the arg is the worktree cwd.
check_plan_block_design() {
    local wt="$1"
    PLAN_GATE_BLOCK_REASON=""

    local plan="$wt/.local/PLAN.md"
    # An absent plan is compliant: Go Commando, pre-plan, and ad-hoc sessions
    # have nothing to gate.
    [[ -f "$plan" ]] || return 0

    grep -qE '^## Block Design' "$plan" 2>/dev/null && return 0

    PLAN_GATE_BLOCK_REASON="Stop hook: .local/PLAN.md has no '## Block Design' section.

Every plan requires a '## Block Design' section. Its body is EITHER the interface design (### Blocks + ### Composition) OR the single line 'N/A — <reason>' when the change has no meaningful decomposition. Add the section, then end the turn.

This gate checks only that the '## Block Design' heading is present; the design's content is for human plan review, not this hook."
    return 1
}

if [[ "$stop_hook_active" == "true" ]]; then
    log_stop "allow_loop_guard"
    exit 0
fi

if [[ -z "$cwd" ]]; then
    log_stop "allow_no_cwd"
    exit 0
fi

# Contract: B08 — no-todo-nudge
# Behavior:
#   Generic "substantive work but no TODO.md" backstop. Fires once per epoch
#   when .local/ exists as a directory and git shows edits or commits ahead
#   of the base branch, but .local/TODO.md is absent. Nudges the session to
#   create tracking state.
# Inputs:
#   $cwd — worktree path (from hook JSON, already validated non-empty above).
# Outputs:
#   On first fire per epoch: JSON {decision: "block", reason: ...} on stdout.
#   On subsequent fires (marker exists): passes through (no block).
# Errors:
#   Fail-open: if the marker cannot be written, allow stop.
# Invariants:
#   - No .local/ directory → no nudge (Go Commando preserved)
#   - No substantive git work → no nudge (pure conversation sessions pass)
#   - Once-per-epoch marker prevents repeated blocking
#   - .local/TODO.md present → skips entirely (normal tracked-session path)
# Edge cases:
#   - .local/ exists but is empty (workflow created it, no tracking yet) → nudges
#   - .local/ exists and TODO.md exists → falls through to normal state check
#   - git not available → no nudge (cannot confirm substantive work)
#   - Marker write fails (read-only fs) → allow stop (fail-open)
check_no_todo_nudge() {
    NO_TODO_BLOCK_REASON=""

    [[ -d "$cwd/.local" ]] || return 0
    [[ -f "$cwd/.local/TODO.md" ]] && return 0

    local marker="$cwd/.local/.no-todo-nudge-fired"
    [[ -f "$marker" ]] && return 0

    local dirty=""
    dirty=$(git -C "$cwd" status --porcelain -- . ':(exclude).local' 2>/dev/null || true)

    local ahead=""
    if [[ -z "$dirty" ]]; then
        local base
        base=$(git -C "$cwd" merge-base HEAD master 2>/dev/null || echo HEAD)
        ahead=$(git -C "$cwd" log --oneline "HEAD...$base" 2>/dev/null || true)
    fi

    [[ -z "$dirty" && -z "$ahead" ]] && return 0

    if ! : > "$marker" 2>/dev/null; then
        return 0
    fi

    local plugin_root
    plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null || exit 0; pwd)
    local template_hint=""
    if [[ -n "$plugin_root" && -f "$plugin_root/templates/TODO.md" ]]; then
        template_hint=" A starter template is available at ${plugin_root}/templates/TODO.md."
    fi

    NO_TODO_BLOCK_REASON="Stop hook: substantive work detected in ${cwd} (uncommitted changes or commits ahead of master) but .local/TODO.md is absent.

Create .local/TODO.md before ending the turn to track this session's work.${template_hint}

This nudge fires once per session epoch (marker: ${marker}); it will not block again until the next SessionStart."

    return 1
}

todo="$cwd/.local/TODO.md"

# No-TODO nudge: fires BEFORE the no-todo early-exit so it can catch sessions
# with substantive work but no tracking. After the nudge fires (or if no nudge
# is needed), the no-todo early-exit proceeds normally.
if ! check_no_todo_nudge; then
    log_stop "block_no_todo_nudge" "" "$NO_TODO_BLOCK_REASON"
    jq -n --arg r "$NO_TODO_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
    exit 0
fi

if [[ ! -f "$todo" ]]; then
    log_stop "allow_no_todo"
    exit 0
fi

state=$(todo_field "$todo" State)

# Contract: B02 — freshness-stop-gate
#
# Behavior:
#   Mechanical doc-vs-conversation drift enforcement at turn end. For every
#   State that would otherwise PERMIT ending the turn (all parked Awaiting *
#   states, Blocked, Waiting For Decision, Complete — NOT Not Started /
#   In Progress, which block anyway), the gate compares conversation activity
#   against .local/TODO.md's freshness: when
#     activity_prompts_since(mtime(TODO.md), transcript_path) >= threshold
#   the turn-end is blocked ONCE per session epoch with a reason instructing
#   the agent to bring the tracking docs up to date — update State / Current
#   Task / Implementation Log / open questions to reflect the conversation
#   since the docs were last touched, or, when the docs are genuinely current,
#   refresh Last Updated (any TODO.md write moves its mtime and satisfies the
#   gate on the re-stop). This closes the parked-state hole: a session that
#   resumes substantive work while parked (e.g. State: Awaiting User Review)
#   can no longer end turns silently with stale docs.
#
# Inputs:
#   $state           — outer scope, already read from TODO.md.
#   $todo, $cwd      — outer scope. mtime of $todo is the reference epoch
#                      (clam_mtime_epoch semantics: integer seconds; 0/absent
#                      → fail-open pass).
#   $transcript_path — outer scope, parsed from hook stdin JSON. Empty or
#                      non-file → fail-open pass.
#   activity_prompts_since — from lib/activity.sh (B01). Not sourced /
#                      NotImplemented → fail-open pass.
#   CLAM_TRACKING_FRESHNESS_GATE      — "disabled" turns the gate off
#                      entirely (default enabled).
#   CLAM_TRACKING_FRESHNESS_THRESHOLD — integer >= 1; prompts-since-mtime at
#                      or above this block. Default 2 (tolerates a single
#                      pleasantry turn); invalid / <1 → 2.
#
# Outputs:
#   Return 0  — fresh (or any fail-open path): caller proceeds to the normal
#               state handling.
#   Return 1  — stale: caller emits {decision:"block", reason:
#               $FRESHNESS_BLOCK_REASON} and logs disposition
#               "block_freshness". $FRESHNESS_BLOCK_REASON is set to a
#               multi-line reason that names the State, the prompt count, the
#               threshold, and the update-or-touch instruction, and states
#               that the nudge fires at most once per session epoch.
#   Return >1 — treated by the caller as fail-open pass (NotImplemented
#               sentinel 90 included).
#
# Errors:
#   Fail-open on EVERY uncertainty: gate disabled, activity lib absent,
#   transcript_path empty/missing, TODO mtime unreadable, marker unwritable,
#   count non-numeric. The gate must never block when it cannot safely
#   evaluate staleness.
#
# Invariants:
#   - Once per session epoch: marker .local/.freshness-nudge-fired is created
#     on the first block; while it exists the gate always passes. The marker
#     is cleared by session-context.sh on every SessionStart event (B04), the
#     same epoch scheme as the other nudge markers.
#   - Runs AFTER the plan gate and BEFORE the state case; never fires for
#     Not Started / In Progress.
#   - A TODO.md write during the blocked turn satisfies the gate (mtime
#     moves), so the agent always has a same-turn escape.
#   - Read-only apart from the marker file.
#
# Edge cases:
#   - TODO.md updated this turn AFTER the last user prompt → count 0 → pass.
#   - Threshold 1 + a bare "thanks" turn → blocks once, marker then allows;
#     default 2 avoids this.
#   - stop_hook_active loop guard exits earlier; the gate never re-fires
#     within the same stop cycle.
#   - Epoch marker present but docs still stale at next session → marker was
#     cleared at SessionStart → gate can fire again (by design).
check_tracking_freshness() {
    FRESHNESS_BLOCK_REASON=""

    [[ "${CLAM_TRACKING_FRESHNESS_GATE:-enabled}" == "disabled" ]] && return 0

    [[ -n "$transcript_path" && -f "$transcript_path" ]] || return 0

    command -v activity_prompts_since &>/dev/null || return 0
    command -v clam_mtime_epoch &>/dev/null || return 0

    local marker="$cwd/.local/.freshness-nudge-fired"
    [[ -f "$marker" ]] && return 0

    local ref_epoch
    ref_epoch=$(clam_mtime_epoch "$todo")
    [[ "$ref_epoch" =~ ^[0-9]+$ && "$ref_epoch" -gt 0 ]] || return 0

    local threshold="${CLAM_TRACKING_FRESHNESS_THRESHOLD:-2}"
    [[ "$threshold" =~ ^[0-9]+$ && "$threshold" -ge 1 ]] || threshold=2

    local count
    count=$(activity_prompts_since "$ref_epoch" "$transcript_path")
    [[ "$count" =~ ^[0-9]+$ ]] || return 0

    [[ "$count" -ge "$threshold" ]] || return 0

    FRESHNESS_BLOCK_REASON="Stop hook: TODO State is ${state}, but ${count} conversation prompt(s) have occurred since .local/TODO.md was last updated (threshold: ${threshold}).

Bring .local/TODO.md up to date before ending the turn — update State / Current Task / Implementation Log / open questions to reflect the conversation since the docs were last touched. If the docs are genuinely current, touch .local/TODO.md (or make any write to it) to refresh its mtime and satisfy this check.

This nudge fires at most once per session epoch."

    : > "$marker" 2>/dev/null || return 0

    return 1
}

# Plan gate (Lego Block methodology): every .local/PLAN.md must carry a
# '## Block Design' section (a real design or an explicit N/A — <reason>). This
# composes in FRONT of the State case, so it applies in all states — its escape
# is always available (add the section). Recurring by design: no epoch marker, so
# a non-compliant plan blocks every turn-end until backfilled. See
# decision-logs/HOOKS-DECISIONS.md.
if ! check_plan_block_design "$cwd"; then
    log_stop "block_plan_block_design" "$state" "$PLAN_GATE_BLOCK_REASON"
    jq -n --arg r "$PLAN_GATE_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
    exit 0
fi

# Freshness gate (B02) composes after the plan gate and in front of the state
# case, for every state that permits ending the turn. Non-0/1 returns (incl.
# the NotImplemented sentinel) fall through fail-open. `|| rc=$?` disarms
# set -e.
case "$state" in
    "Not Started"|"In Progress") : ;;
    *)
        freshness_rc=0
        check_tracking_freshness || freshness_rc=$?
        if [[ "$freshness_rc" -eq 1 ]]; then
            log_stop "block_freshness" "$state" "$FRESHNESS_BLOCK_REASON"
            jq -n --arg r "$FRESHNESS_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
            exit 0
        fi
        ;;
esac

# Work-graph creation gate. Once per session epoch, prevent parking while the
# session has demonstrably decomposed its problem — a decomposition artifact
# exists under .local/ — but .local/WORKGRAPH.md does not. This is the
# creation-side sibling of check_workgraph_closeout: closeout polices open
# nodes at Complete; this polices the graph existing at all, at the first
# park after decomposition. Evidence for the trigger: an 18h47m session
# (13 Aug) wrote PLAN.md, a 13-block table, and dispatched 9 units under the
# prose-only "the moment it first happens" instruction without ever creating
# the graph — prose without an artifact anchor and a gate demonstrably does
# not fire, while the artifacts this gate keys on (TODO.md, FOLLOWUPS.md)
# were created promptly under exactly this once-per-epoch block pattern.
#
# Decomposition artifact := any of .local/PLAN.md, .local/blocks.md,
# .local/IMPLEMENTATION-PLAN.md, or a *.md under .local/plans/. TODO.md task
# lists deliberately do NOT count: the template ships with placeholder tasks,
# so every tracked session would trip the gate on its first stop.
#
# Fail-open like the sibling gates: unwritable marker or disabled env
# (CLAM_WORKGRAPH_GATE, shared with closeout) → pass. Marker
# .local/.workgraph-create-nudge-fired is cleared each SessionStart by
# session-context.sh.
check_workgraph_creation() {
    WORKGRAPH_CREATE_BLOCK_REASON=""

    [[ "${CLAM_WORKGRAPH_GATE:-enabled}" == "enabled" ]] || return 0
    [[ -f "$cwd/.local/WORKGRAPH.md" ]] && return 0

    local marker="$cwd/.local/.workgraph-create-nudge-fired"
    [[ -f "$marker" ]] && return 0

    local evidence=""
    local f
    for f in PLAN.md blocks.md IMPLEMENTATION-PLAN.md; do
        [[ -f "$cwd/.local/$f" ]] && evidence="${evidence}  - .local/$f"$'\n'
    done
    if [[ -d "$cwd/.local/plans" ]]; then
        for f in "$cwd/.local/plans"/*.md; do
            [[ -f "$f" ]] && evidence="${evidence}  - .local/plans/$(basename "$f")"$'\n'
        done
    fi
    # A TODO.md Current Task citing a graph node id is itself decomposition
    # evidence: a node id with no graph on disk is the exact drift this gate
    # exists to stop, and it can appear before any plan artifact does
    # (round-3 checkpoint 1: Current Task "N01", no WORKGRAPH.md, no plan
    # yet — the artifact-only evidence set above stayed silent).
    if [[ -f "$todo" && -r "$todo" ]]; then
        local ct
        ct=$(todo_field "$todo" "Current Task")
        if [[ "$ct" =~ (^|[^A-Za-z0-9_])(N[0-9]+)([^0-9]|$) ]]; then
            evidence="${evidence}  - TODO.md Current Task cites graph node ${BASH_REMATCH[2]}"$'\n'
        fi
    fi
    [[ -z "$evidence" ]] && return 0

    if ! : > "$marker" 2>/dev/null; then
        return 0
    fi

    WORKGRAPH_CREATE_BLOCK_REASON="Stop hook: this session has decomposed its problem — decomposition artifact(s) exist:

${evidence}
— but .local/WORKGRAPH.md does not. Create it now from the tracking plugin's templates/WORKGRAPH.md: one root node for the deliverable, a Parent edge on every other node, one node per actual work item (per phase per actor, not per topic), Deps ordering edges, each node's Notes linking to the artifact entry that owns its detail, and the Focus pointer on the node being worked. Then park again.

This nudge fires at most once per session epoch."

    return 1
}

case "$state" in
    "Not Started"|"In Progress") : ;;
    *)
        if ! check_workgraph_creation; then
            log_stop "block_workgraph_missing" "$state" "$WORKGRAPH_CREATE_BLOCK_REASON"
            jq -n --arg r "$WORKGRAPH_CREATE_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
            exit 0
        fi
        ;;
esac

# Work-graph live-view nudge. Once per session epoch, prevent parking while
# .local/WORKGRAPH.md exists but TODO.md records no live view for it. The
# serve-on-creation instruction has been prose in the SessionStart context
# since the graph-primary redesign and demonstrably does not fire (round 3:
# graph created at plan time, engineer never given a URL) — the same
# prose-without-a-gate failure the creation gate above was built for. The
# recorded line is the anchor: "Live view: <url>" once served, or
# "Live view: none" when no serving skill is installed, and either satisfies
# this check for the rest of the effort. Capability-phrased throughout —
# the nudge names what a serving skill does, never a plugin.
check_workgraph_live_view() {
    LIVE_VIEW_BLOCK_REASON=""

    [[ "${CLAM_WORKGRAPH_GATE:-enabled}" == "enabled" ]] || return 0
    [[ -f "$cwd/.local/WORKGRAPH.md" ]] || return 0
    [[ -f "$todo" && -r "$todo" ]] || return 0
    grep -qiE '^Live [Vv]iew:' "$todo" && return 0

    local marker="$cwd/.local/.live-view-nudge-fired"
    [[ -f "$marker" ]] && return 0
    if ! : > "$marker" 2>/dev/null; then
        return 0
    fi

    LIVE_VIEW_BLOCK_REASON="Stop hook: .local/WORKGRAPH.md exists but .local/TODO.md records no live view for it.

Check the skill catalog for a skill that can serve a markdown document as a live, self-updating HTML view without opening a browser. If one is available: serve .local/WORKGRAPH.md with it, tell the engineer the resulting URL once in conversation, and add a line to TODO.md's Status section: Live view: <url>. If no such skill is installed, add: Live view: none — and this check stays quiet for the rest of the effort.

This nudge fires at most once per session epoch."

    return 1
}

case "$state" in
    "Not Started"|"In Progress") : ;;
    *)
        if ! check_workgraph_live_view; then
            log_stop "block_live_view_missing" "$state" "$LIVE_VIEW_BLOCK_REASON"
            jq -n --arg r "$LIVE_VIEW_BLOCK_REASON" '{decision: "block", reason: $r}'
            exit 0
        fi
        ;;
esac

# Summons-presentation gate. Once per session epoch, prevent a summons park
# (Waiting For Decision / Awaiting User Review) whose TODO.md Status section
# carries no URL while a rendered HTML view exists under .local/ — the
# round-3 approval summons cited a bare .md path with the rendered sibling
# sitting on disk (F09), after the presentation rule had already shipped as
# prose twice. Evidence gating keeps this quiet for markdown-only flows: no
# .html under .local/, no gate. The URL can be any http(s) link in the
# Status section (Decision Needed, Current Task, or a Live view line all
# count) — the point is that the summons the engineer reads contains a
# clickable rendered view, not which field carries it.
check_summons_presentation() {
    SUMMONS_URL_BLOCK_REASON=""

    [[ "${CLAM_SUMMONS_URL_GATE:-enabled}" == "enabled" ]] || return 0
    [[ -f "$todo" && -r "$todo" ]] || return 0

    local html
    html=$(find "$cwd/.local" -maxdepth 2 -name '*.html' -print -quit 2>/dev/null)
    [[ -n "$html" ]] || return 0

    awk '/^## Status/{f=1;next}/^## /{f=0}f' "$todo" | grep -qE 'https?://' && return 0

    local marker="$cwd/.local/.summons-url-nudge-fired"
    [[ -f "$marker" ]] && return 0
    if ! : > "$marker" 2>/dev/null; then
        return 0
    fi

    SUMMONS_URL_BLOCK_REASON="Stop hook: State is ${state} — a summons — but TODO.md's Status section contains no URL, while a rendered HTML view exists under .local/ (e.g. $(basename "$html")).

A summons must present the document it is asking the engineer to read: serve or open the rendered view and put its URL in the Status section (Decision Needed, Current Task, or a Live view line), so the engineer lands on the document, not on a bare file path.

This nudge fires at most once per session epoch."

    return 1
}

case "$state" in
    "Waiting For Decision"|"Awaiting User Review")
        if ! check_summons_presentation; then
            log_stop "block_summons_url_missing" "$state" "$SUMMONS_URL_BLOCK_REASON"
            jq -n --arg r "$SUMMONS_URL_BLOCK_REASON" '{decision: "block", reason: $r}'
            exit 0
        fi
        ;;
esac

# Contract: B03 — followups-closeout-gate
#
# Behavior:
#   Once per session epoch, prevent a Complete park while
#   $cwd/.local/FOLLOWUPS.md still has OPEN entries. Wiring (part of this
#   block's implementation): runs FIRST in the Complete branch below, before
#   check_independent_review — being once-per-epoch it yields on subsequent
#   stops, so the repeating IR/PR-cron block reasons are masked for at most
#   one turn. On the first violating stop of the epoch: write the marker,
#   set FOLLOWUPS_BLOCK_REASON to a message listing each open entry
#   (`F<NN> — <title>`) and instructing that every one be dispositioned —
#   filed <issue-ref> / resolved / dropped (<reason>) — or the State moved
#   off Complete; the caller then logs log_stop "block_followups_open" and
#   emits the block JSON, exactly like the sibling Complete-branch checks.
# Inputs: $cwd; $cwd/.local/FOLLOWUPS.md (absent → pass);
#   marker $cwd/.local/.followups-nudge-fired (cleared each SessionStart by
#   session-context.sh, B02); env CLAM_FOLLOWUPS_GATE (default "enabled";
#   any other value disables the gate → always pass).
#   Open entry := line matching ^- Status: open[[:space:]]*$.
# Outputs: return 0 = pass (file absent, no open entries, gate disabled,
#   marker already present, or marker unwritable). return 1 = block, with
#   FOLLOWUPS_BLOCK_REASON set (non-empty).
# Errors: unreadable file or unwritable marker → return 0 (fail-open; an
#   unwritable filesystem must never block parking, same as the WFD nudge).
# Invariants:
#   - Never blocks more than once per session epoch.
#   - Read-only wrt FOLLOWUPS.md; side effects are only the marker file and
#     the caller's log line.
#   - States other than Complete are unaffected; Complete with a fully
#     dispositioned (or absent) FOLLOWUPS.md behaves exactly as today.
# Edge cases:
#   - Engineer genuinely wants an item to stay open past close-out: re-stop
#     after the nudge (marker → pass) or use dropped (<reason>) — the
#     sanctioned escape hatches; the gate is a nudge, not a wall.
#   - FOLLOWUPS.md present but zero-byte/malformed → pass (no open lines).
check_followups_disposition() {
    FOLLOWUPS_BLOCK_REASON=""

    [[ "${CLAM_FOLLOWUPS_GATE:-enabled}" == "enabled" ]] || return 0

    local followups="$cwd/.local/FOLLOWUPS.md"
    [[ -f "$followups" && -r "$followups" ]] || return 0

    local marker="$cwd/.local/.followups-nudge-fired"
    [[ -f "$marker" ]] && return 0

    # Open entry := a "- Status: open" line (trailing whitespace tolerated),
    # attributed to the nearest preceding "## F<NN> — <title>" heading. The
    # heading search is unanchored (not "line starts with") because a
    # heading can land mid-line, glued onto the prior entry's last content
    # line with no separating newline.
    local open_re='^- Status: open[[:space:]]*$'
    local heading_re='##[[:space:]]F[0-9]+[[:space:]].*$'
    local heading="" line="" entries=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $heading_re ]]; then
            heading="${BASH_REMATCH[0]#"## "}"
        fi
        if [[ -n "$heading" && "$line" =~ $open_re ]]; then
            entries="${entries}  - ${heading}"$'\n'
        fi
    done < "$followups"

    [[ -z "$entries" ]] && return 0

    # Fail-open when the marker can't be written: an unwritable filesystem
    # must never block parking, same as the WFD nudge.
    if ! : > "$marker" 2>/dev/null; then
        return 0
    fi

    FOLLOWUPS_BLOCK_REASON="Stop hook: TODO State is Complete, but .local/FOLLOWUPS.md has open follow-up(s) that still need a disposition:

${entries}
Disposition every open entry before ending the turn — set its Status to filed <issue-ref>, resolved, or dropped (<reason>) — or move State off Complete if the work genuinely is not done.

This nudge fires at most once per session epoch."

    return 1
}

# Contract: B04 — workgraph-closeout-gate (plan 001-tracking-work-graph)
#
# Behavior:
#   Once per session epoch, prevent a Complete park while
#   $cwd/.local/WORKGRAPH.md still has OPEN nodes (format:
#   docs/protocols/work-graph.md). Wiring (part of this block's
#   implementation): runs in the Complete branch below AFTER
#   check_followups_disposition and BEFORE check_independent_review — the
#   two once-per-epoch close-out gates fire in artifact order (follow-ups
#   first, per that gate's masking rationale), ahead of the repeating
#   IR/PR-cron backstops. On the first violating stop of the epoch: write
#   the marker, set WORKGRAPH_BLOCK_REASON to a message listing each open
#   node (`N<NN> — <title>`) and instructing that every one be
#   dispositioned — done, or dropped (<reason>) — or the State moved off
#   Complete if the work genuinely is not done; the caller then logs
#   log_stop "block_workgraph_open" and emits the block JSON, exactly like
#   the sibling Complete-branch checks.
# Inputs: $cwd; $cwd/.local/WORKGRAPH.md (absent → pass);
#   marker $cwd/.local/.workgraph-nudge-fired (cleared each SessionStart by
#   session-context.sh, B03); env CLAM_WORKGRAPH_GATE (default "enabled";
#   any other value disables the gate → always pass).
#   Open node := line matching ^- Status: open[[:space:]]*$, attributed to
#   the nearest preceding node heading matching ##[[:space:]]N[0-9]+
#   followed by whitespace (unanchored, same glued-heading tolerance as the
#   follow-ups gate; heading text = the match with the leading "## "
#   stripped).
# Outputs: return 0 = pass (file absent, no open nodes, gate disabled,
#   marker already present, or marker unwritable). return 1 = block, with
#   WORKGRAPH_BLOCK_REASON set (non-empty).
# Errors: unreadable file or unwritable marker → return 0 (fail-open; an
#   unwritable filesystem must never block parking, same as the sibling
#   gates).
# Invariants:
#   - Never blocks more than once per session epoch.
#   - Read-only wrt WORKGRAPH.md; side effects are only the marker file and
#     the caller's log line.
#   - States other than Complete are unaffected; Complete with a fully
#     dispositioned (or absent) WORKGRAPH.md behaves exactly as today.
#   - The Focus pointer is NOT checked (a dangling or none Focus never
#     blocks; only open nodes do).
# Edge cases:
#   - Engineer genuinely wants a node to stay open past close-out: re-stop
#     after the nudge (marker → pass) or use dropped (<reason>) — the
#     sanctioned escape hatches; the gate is a nudge, not a wall.
#   - WORKGRAPH.md present but zero-byte/malformed → pass (no open lines).
#   - An open Status line with no preceding node heading lists as
#     `(untitled)`.
check_workgraph_closeout() {
    WORKGRAPH_BLOCK_REASON=""

    [[ "${CLAM_WORKGRAPH_GATE:-enabled}" == "enabled" ]] || return 0

    local workgraph="$cwd/.local/WORKGRAPH.md"
    [[ -f "$workgraph" && -r "$workgraph" ]] || return 0

    local marker="$cwd/.local/.workgraph-nudge-fired"
    [[ -f "$marker" ]] && return 0

    # Open node := a "- Status: open" line (trailing whitespace tolerated),
    # attributed to the nearest preceding "## N<NN> — <title>" heading. The
    # heading search is unanchored (not "line starts with") because a
    # heading can land mid-line, glued onto the prior entry's last content
    # line with no separating newline — same tolerance as the follow-ups
    # gate. An open Status line with no preceding node-heading match
    # (including one under a non-N<NN> "##" heading) attributes as
    # (untitled).
    local open_re='^- Status: open[[:space:]]*$'
    local heading_re='##[[:space:]]N[0-9]+[[:space:]].*$'
    local heading="" line="" entries=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $heading_re ]]; then
            heading="${BASH_REMATCH[0]#"## "}"
        fi
        if [[ "$line" =~ $open_re ]]; then
            entries="${entries}  - ${heading:-(untitled)}"$'\n'
        fi
    done < "$workgraph"

    [[ -z "$entries" ]] && return 0

    # Fail-open when the marker can't be written: an unwritable filesystem
    # must never block parking, same as the follow-ups gate.
    if ! : > "$marker" 2>/dev/null; then
        return 0
    fi

    WORKGRAPH_BLOCK_REASON="Stop hook: TODO State is Complete, but .local/WORKGRAPH.md has open node(s) that still need a disposition:

${entries}
Disposition every open node before ending the turn — set its Status to done or dropped (<reason>) — or move State off Complete if the work genuinely is not done.

This nudge fires at most once per session epoch."

    return 1
}

# Parked states (the manifest's parked category) allow stop — work resumes on
# its own, no user action. state_is_parked / state_parked_list come from
# lib/states.sh, the single source that also feeds the reject message
# below, so the allow-check and the printed list cannot drift (#137).
#
# Needs-user and terminal states get bespoke handling; Complete carries the
# PR-monitoring backstop.
case "$state" in
    Complete)
        # Followups closeout gate (B03) runs FIRST, ahead of the other two
        # Complete-branch backstops: an open follow-up is a closeout-readiness
        # problem, and being once-per-epoch it should get first crack at the
        # turn before the (repeating) IR/PR-cron reasons would otherwise mask it.
        if ! check_followups_disposition; then
            log_stop "block_followups_open" "$state" "$FOLLOWUPS_BLOCK_REASON"
            jq -n --arg r "$FOLLOWUPS_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
            exit 0
        fi
        # Work-graph closeout gate (B04) runs SECOND, after follow-ups and
        # before independent-review: same once-per-epoch-goes-first rationale
        # as the follow-ups gate above, so it also gets a turn before the
        # (repeating) IR/PR-cron reasons would otherwise mask it.
        if ! check_workgraph_closeout; then
            log_stop "block_workgraph_open" "$state" "$WORKGRAPH_BLOCK_REASON"
            jq -n --arg r "$WORKGRAPH_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
            exit 0
        fi
        # Two independent backstops compose: both must pass to allow Complete.
        # Independent-review is checked first so its block reason wins when both
        # are unsatisfied (it is the earlier semantic deadline).
        if ! check_independent_review; then
            log_stop "block_independent_review_missing" "$state" "$IR_BLOCK_REASON"
            jq -n --arg r "$IR_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
            exit 0
        fi
        if check_pr_monitoring; then
            log_stop "allow_state_complete" "$state"
            exit 0
        fi
        log_stop "block_pr_no_cron" "$state" "$PR_BLOCK_REASON"
        jq -n --arg r "$PR_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
        exit 0
        ;;
    Blocked)
        log_stop "allow_state_blocked" "$state"
        exit 0
        ;;
    "Waiting For Decision")
        # Decision-file nudge (#238): a WFD park must carry the decision
        # analysis mandated by the system prompt (PR #237). Non-compliant
        # parks are blocked ONCE per session epoch; session-context.sh clears
        # the marker on every SessionStart event (startup, resume, clear, compact), the
        # same epoch scheme clam-code used.
        marker="$cwd/.local/.decision-nudge-fired"
        if [[ -f "$marker" ]]; then
            log_stop "allow_state_waiting_nudged" "$state"
            exit 0
        fi
        if check_decision_file; then
            log_stop "allow_state_waiting" "$state"
            exit 0
        fi
        # Fail open when the marker cannot be written: an unwritable
        # filesystem must never block parking.
        if ! : > "$marker" 2>/dev/null; then
            log_stop "allow_state_waiting" "$state"
            exit 0
        fi
        log_stop "block_wfd_decision_file_missing" "$state" "$WFD_BLOCK_REASON"
        jq -n --arg r "$WFD_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
        exit 0
        ;;
    "Awaiting CI"|"Awaiting Bot Review")
        # Watched parked states before human handoff: an open PR here must carry
        # its monitoring cron (CI watch / bot-review watch), else a merge, close,
        # or bot-review event during the park goes undetected (#264). These two
        # precede the human-review handoff, so the independent-review backstop
        # does NOT fire here — only PR monitoring. check_pr_monitoring is a no-op
        # when CLAM_PR_CRONS is disabled or there is no open PR (fail-open).
        if check_pr_monitoring; then
            log_stop "allow_state_$(printf '%s' "$state" | tr 'A-Z ' 'a-z_')" "$state"
            exit 0
        fi
        log_stop "block_pr_no_cron" "$state" "$PR_BLOCK_REASON"
        jq -n --arg r "$PR_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
        exit 0
        ;;
    "Awaiting Reviewer Assignment"|"Awaiting Human Review"|"Awaiting Merge Queue")
        # Human-review-adjacent parked states: TWO backstops compose (both must
        # pass to allow). Independent-review is checked first so its reason wins
        # when both are unsatisfied (it is the earlier semantic deadline: the
        # self-review must land before a human reviewer sees the work). PR
        # monitoring then enforces that the park is not blind to a merge, close,
        # enqueue, or drift while it waits (#264). Every other parked state
        # (Awaiting Independent Agent Review while the review legitimately runs,
        # Awaiting Agent) falls through to the generic parked allow below. Both
        # checks are no-ops when their flag is off or there is no open PR.
        if ! check_independent_review; then
            log_stop "block_independent_review_missing" "$state" "$IR_BLOCK_REASON"
            jq -n --arg r "$IR_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
            exit 0
        fi
        if check_pr_monitoring; then
            log_stop "allow_state_$(printf '%s' "$state" | tr 'A-Z ' 'a-z_')" "$state"
            exit 0
        fi
        log_stop "block_pr_no_cron" "$state" "$PR_BLOCK_REASON"
        jq -n --arg r "$PR_BLOCK_REASON" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
        exit 0
        ;;
esac

# Parked states allow stop. Derive the log label from the state name so the
# allow_state_awaiting_* label scheme stays in lockstep with the manifest.
if state_is_parked "$state"; then
    log_stop "allow_state_$(printf '%s' "$state" | tr 'A-Z ' 'a-z_')" "$state"
    exit 0
fi

# Unrecognised state: block, and SHOW the valid turn-ending states so a
# near-miss (typo, abbreviation, renamed state) can self-correct instead of
# being rationalised into a false Complete.
parked_list=$(state_parked_list | awk 'NR > 1 {printf " | "} {printf "%s", $0}')

reason="Stop hook: .local/TODO.md State is \"${state:-<unset>}\", which is not a State that permits ending the turn.

States that END the turn (these must match EXACTLY):
  - Complete: work done (an open PR still needs a monitoring cron).
  - Blocked / Waiting For Decision: needs the user. Set the reason field, then run notify <worktree-name> if the notify helper is installed (check with command -v notify; skip silently otherwise).
  - Parked, resumes on its own with no user action: ${parked_list}

If you wrote a near-miss (e.g. \"Awaiting Review\" instead of \"Awaiting Human Review\"), correct it to the precise name above. Do NOT downgrade to Complete just to satisfy this hook; that reports the work as finished when it is not.

If you need the user: set Blocked or Waiting For Decision (with a reason in Blocked Reason: or Decision Needed:), run notify <worktree-name> if that helper is installed, then write a final user-facing message that restates the blocker/decision in plain terms (the user sees this screen-bottom line first; do not assume they will scroll up).

Otherwise the work is not done: continue working. Do NOT invent work just because this reminder fired."

log_stop "block" "$state" "$reason"
jq -n --arg r "$reason" --arg n "$SELF_CONTAINED_NOTE" '{decision: "block", reason: ($r + "\n\n" + $n)}'
