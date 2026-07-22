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
#     decisions/*.md) with actionable instructions for each.
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

# NotImplemented: B02
exit 0
