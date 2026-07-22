#!/bin/bash
# B01 — log-skill-trigger hook
#
# Behavior:
#   PreToolUse + PostToolUse hook for the Skill tool.
#   Appends one JSONL row per event to ~/.claude/skill-triggers.jsonl.
#   Always exits 0 — fire-and-forget telemetry; never blocks the session.
#
# Inputs:
#   stdin — JSON object from Claude Code hook system containing:
#     .tool_name (string) — must be "Skill" or the hook exits immediately
#     .hook_event_name (string) — "PreToolUse" or "PostToolUse"
#     .tool_input.skill (string|null) — the skill name being invoked
#     .tool_input.args (string|null) — arguments passed to the skill
#     .cwd (string|null) — working directory
#     .session_id (string|null) — Claude Code session ID
#     .transcript_path (string|null) — path to session transcript
#     .tool_response.error (string|null) — error from skill execution (post only)
#
# Outputs:
#   Appends one JSON line to ~/.claude/skill-triggers.jsonl with fields:
#     ts (string) — UTC ISO 8601 timestamp
#     event (string) — "pre" or "post" (derived from hook_event_name)
#     skill (string|null) — skill name
#     args (string|null) — skill arguments
#     cwd (string|null) — working directory
#     session_id (string|null) — session ID
#     transcript_path (string|null) — transcript path
#     error (string|null) — error message (post events only)
#
# Errors:
#   If jq is not installed, exits 0 silently (graceful degradation).
#   If tool_name is not "Skill", exits 0 silently (not our event).
#   Any write failure is swallowed — never returns non-zero.
#
# Invariants:
#   - Exit code is always 0.
#   - Never blocks, never writes to stdout/stderr that would affect the session.
#   - The event field is derived by stripping "ToolUse" suffix and lowercasing.
#   - One and only one JSONL row is appended per invocation.
#
# Edge cases:
#   - Missing jq → silent exit 0
#   - Empty or malformed stdin → jq fails silently, exit 0
#   - Log file doesn't exist → created on first append
#   - Disk full or permission denied on append → swallowed, exit 0

exit 1  # STUB: not yet implemented
