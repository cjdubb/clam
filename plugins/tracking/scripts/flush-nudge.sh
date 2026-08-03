#!/bin/bash
# Contract: B02 flush-nudge
# Behavior: UserPromptSubmit hook. Parses the JSONL transcript for the last
#   assistant usage block and computes context fill against
#   CLAUDE_CODE_AUTO_COMPACT_WINDOW. When fill ≥ threshold, injects a one-time
#   nudge (stdout text) listing the .local/ tracking docs the agent should flush
#   before auto-compaction discards in-conversation state.
# Inputs:
#   - stdin: JSON with .cwd (working directory) and .transcript_path (path to
#     the session's JSONL transcript file)
#   - env CLAUDE_CODE_AUTO_COMPACT_WINDOW: compaction window in tokens; if not
#     in the process env, falls back to reading
#     ~/.claude/settings.json → .env.CLAUDE_CODE_AUTO_COMPACT_WINDOW; if absent
#     from both, skip silently (no window to meter against)
#   - env CLAM_FLUSH_NUDGE_THRESHOLD: fill percentage to trigger nudge
#     (default 75; must be an integer 1-100)
#   - env CLAM_TRACKING_FLUSH_GATE: set to "disabled" to disable this hook
#   - env CLAM_FLUSH_CONTEXT_WINDOW: override for testing (takes precedence
#     over CLAUDE_CODE_AUTO_COMPACT_WINDOW and settings.json)
# Outputs:
#   - stdout: nudge text when firing (becomes a system-reminder via the
#     UserPromptSubmit hook contract); empty on all skip paths
#   - side effect: creates .local/.flush-nudge-fired marker on fire
#   - side effect: deletes .local/.flush-nudge-skip-next marker when consumed
# Errors: fail-open — any error exits 0 with no output. Never breaks a prompt.
# Invariants:
#   - Always exits 0.
#   - One-shot per epoch: fires at most once between session boundaries
#     (SessionStart events). Marker .local/.flush-nudge-fired is cleared by
#     session-context.sh on every SessionStart event (startup, resume, clear,
#     compact), so the nudge can fire again in each new epoch.
#   - Consumes .local/.flush-nudge-skip-next (dropped by post-compact-recovery)
#     on the first prompt after compaction to avoid false nudge from stale
#     transcript reads. When present: delete the marker and exit without
#     checking fill. Placed before the TODO.md gate so the marker is always
#     consumed, never left to suppress a future epoch.
#   - Gated on .local/TODO.md existing — if tracking has no state file, there
#     is nothing to protect and no nudge to give.
#   - CLAM_TRACKING_FLUSH_GATE=disabled exits immediately.
#   - Requires jq; skips silently without it.
#   - Context fill = sum of input_tokens + cache_read_input_tokens +
#     cache_creation.ephemeral_5m_input_tokens +
#     cache_creation.ephemeral_1h_input_tokens from the last assistant usage
#     block in the transcript. This approximates the token count the model saw
#     on its most recent invocation.
#   - Window resolution order: CLAM_FLUSH_CONTEXT_WINDOW (test override) →
#     CLAUDE_CODE_AUTO_COMPACT_WINDOW (process env) →
#     ~/.claude/settings.json .env.CLAUDE_CODE_AUTO_COMPACT_WINDOW → skip.
#   - Nudge text enumerates specific .local/ files (TODO.md, PLAN.md,
#     IMPLEMENTATION-PLAN.md, TROUBLESHOOTING.md, SUBAGENT-LOG-*.md,
#     decisions/*.md, FOLLOWUPS.md, WORKGRAPH.md) with actionable
#     instructions for each.
# Edge cases:
#   - CLAUDE_CODE_AUTO_COMPACT_WINDOW not set anywhere → skip (no window)
#   - CLAUDE_CODE_AUTO_COMPACT_WINDOW not a positive integer → skip
#   - Transcript missing or unreadable → skip
#   - Transcript has no assistant usage blocks (empty or all user turns) → skip
#   - Fill below threshold → skip (not yet approaching compaction)
#   - .flush-nudge-fired marker already exists → skip (already fired this epoch)
#   - .flush-nudge-skip-next exists → consume marker and skip
#   - .local/TODO.md does not exist → skip (no tracking state)
#   - .local/ directory does not exist → skip
#   - cwd missing from input JSON → skip
#   - transcript_path missing from input JSON → skip
#   - CLAM_FLUSH_NUDGE_THRESHOLD not a number → use default 75
#   - Threshold of 0 or negative → use default 75
#   - Threshold > 100 → use as-is (will fire at >100% fill, effectively never)
#   - jq not available → skip
#   - Malformed JSONL lines in transcript → skip (jq fromjson? drops them)

set -e
trap 'exit 0' ERR

[[ "${CLAM_TRACKING_FLUSH_GATE:-}" == "disabled" ]] && exit 0

command -v jq &>/dev/null || exit 0

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

[[ -n "$cwd" ]] || exit 0

# First prompt after a compaction: the transcript has no post-compaction
# assistant usage block yet, so metering now would read the stale
# pre-compaction fill and fire a false nudge. Consume the marker (one prompt
# only) and skip. Placed before the TODO.md gate so it's always cleared,
# never left to suppress a later epoch.
skip_marker="$cwd/.local/.flush-nudge-skip-next"
if [[ -f "$skip_marker" ]]; then
    rm -f "$skip_marker" 2>/dev/null || true
    exit 0
fi

[[ -f "$cwd/.local/TODO.md" ]] || exit 0

# Contract: B05 — flush-nudge-default-window
#
# Behavior:
#   Closes the silent-no-op hole in the window resolution below: on machines
#   where CLAM_FLUSH_CONTEXT_WINDOW, CLAUDE_CODE_AUTO_COMPACT_WINDOW, and the
#   settings.json fallback are ALL unset/empty, the nudge previously never
#   fired (permanently, silently). This function supplies the last-resort
#   default so context-fill metering still happens.
# Inputs:  none (no arguments, no environment reads — the three configured
#   sources above always take precedence at the call site; this function is
#   consulted only when every one of them came up empty).
# Outputs: prints "200000" (tokens — the standard 200k context window) to
#   stdout and returns 0. NotImplemented sentinel: no stdout, return 90
#   (caller degrades to the historical skip behavior).
# Errors:  none possible once implemented; must not read files or the net.
# Invariants:
#   - Resolution ORDER is unchanged: explicit test override → process env →
#     settings.json → THIS DEFAULT. A set-but-invalid value in any earlier
#     source still falls through the numeric guard and skips — the default
#     applies ONLY to the fully-unset case, never masking a misconfiguration.
#   - The constant is defined here, in one place.
# Edge cases:
#   - Deployments with larger/smaller real windows: the default may misjudge
#     fill % (e.g. fire late on 1M-context models); acceptable — the
#     configured sources exist precisely to override it.
_default_window() {
    echo "200000"
    return 0
}

# Resolve the compaction window: test override, then process env, then the
# deployed settings.json, then the built-in default (B05); a still-empty or
# non-numeric result skips.
window="${CLAM_FLUSH_CONTEXT_WINDOW:-}"
[[ -n "$window" ]] || window="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
if [[ -z "$window" ]]; then
    # A missing settings.json must fall through to the next resolution step, not trip the ERR trap.
    window=$(jq -r '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW // empty' "$HOME/.claude/settings.json" 2>/dev/null) || window=""
fi
if [[ -z "$window" ]]; then
    window=$(_default_window 2>/dev/null) || window=""
fi
[[ "$window" =~ ^[0-9]+$ ]] || exit 0
(( window > 0 )) || exit 0

[[ -f "$transcript" ]] || exit 0

# Sum tokens across the transcript stream and take the last assistant usage
# block — the token count the model saw on its most recent invocation,
# approximating current context occupancy. fromjson? drops malformed lines.
fill=$(jq -rR '
    fromjson?
    | select(.type == "assistant" and (.message.usage // null) != null)
    | .message.usage
    | (.input_tokens // 0)
      + (.cache_read_input_tokens // 0)
      + (.cache_creation.ephemeral_5m_input_tokens // 0)
      + (.cache_creation.ephemeral_1h_input_tokens // 0)
' < "$transcript" 2>/dev/null | tail -1)

[[ "$fill" =~ ^[0-9]+$ ]] || exit 0

# Invalid or non-positive threshold falls back to the default; > 100 is used
# as-is (effectively never fires).
threshold="${CLAM_FLUSH_NUDGE_THRESHOLD:-}"
if [[ ! "$threshold" =~ ^[0-9]+$ ]]; then
    threshold=75
elif (( threshold <= 0 )); then
    threshold=75
fi

pct=$(( fill * 100 / window ))
(( pct >= threshold )) || exit 0

# One-shot per epoch. Marker is cleared by session-context.sh on every
# SessionStart event, so the next epoch can fire again.
marker="$cwd/.local/.flush-nudge-fired"
[[ -f "$marker" ]] && exit 0
: > "$marker" 2>/dev/null || exit 0

# Contract: B04 — followups-lifecycle (flush-nudge leg)
# Behavior: the nudge below gains a 7th numbered item, after the
#   decisions/*.md item, instructing: `.local/FOLLOWUPS.md` — capture any
#   follow-up mentioned in conversation but not yet recorded, and verify
#   every open entry is still genuinely open (disposition any resolved
#   in-conversation).
# Invariants: numbering stays sequential; the header comment at the top of
#   this script naming the enumerated files is updated to match; the closing
#   "If every doc above is already current" line stays last.
#
# Contract: B05 — workgraph-lifecycle (flush-nudge leg, plan 001-tracking-work-graph)
# Behavior: the nudge below gains an 8th numbered item, after the
#   FOLLOWUPS.md item, instructing: `.local/WORKGRAPH.md` — add any
#   subproblem surfaced in conversation but not yet recorded as a node,
#   verify the `Focus:` pointer names the node actually being worked, and
#   disposition any node resolved in-conversation (done / dropped (<reason>)).
# Invariants: numbering stays sequential; the header comment at the top of
#   this script naming the enumerated files is updated to match; the closing
#   "If every doc above is already current" line stays last.
cat <<EOF
[CLAM FLUSH NUDGE] Context fill is ~${pct}% (${fill} / ${window} tokens). Auto-compaction is approaching and will lossily summarise in-conversation state. Before doing any other work this turn, verify each \`.local/\` tracking doc reflects current reality and update only what is stale:

1. \`.local/TODO.md\` — \`State:\`, \`Last Updated:\`, and the Implementation Log section. If \`State:\` is \`Blocked\` or \`Waiting For Decision\`, populate \`Blocked Reason:\` / \`Decision Needed:\`.
2. \`.local/PLAN.md\` — append to the Changelog section if the plan has changed mid-implementation.
3. \`.local/IMPLEMENTATION-PLAN.md\` — chunk status if any chunk transitioned.
4. \`.local/TROUBLESHOOTING.md\` — log any failed fix attempt before trying the next approach.
5. \`.local/SUBAGENT-LOG-{descriptiveName}.md\` — persist any subagent return summaries received since last flush.
6. \`.local/decisions/*.md\` — verify any open decision file (\`Status: Open\`) has its evidence, recommendation, and if-deferred path complete before compaction discards the supporting context.
7. \`.local/FOLLOWUPS.md\` — capture any follow-up mentioned in conversation but not yet recorded, and verify every open entry is still genuinely open (disposition any resolved in-conversation).
8. \`.local/WORKGRAPH.md\` — add any subproblem surfaced but not yet recorded as a node, verify the \`Focus:\` pointer names the node actually being worked, and disposition any node resolved in-conversation (done / dropped (<reason>)).

If every doc above is already current, proceed with the user's request. Do not rewrite files that are already accurate.
EOF

exit 0
