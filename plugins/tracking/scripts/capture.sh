#!/bin/bash
# Contract: B02 — Capture hook (migrated from make-progress plugin)
#
# Behavior:
#   UserPromptSubmit hook that snapshots the session's state when the user's
#   prompt contains "/make-progress". Each snapshot becomes a labeled training
#   example: (stall state) → (correct next move, recorded later as DECISION.md
#   by the make-progress skill). Two modes: hook (default, called by Claude Code
#   on UserPromptSubmit with JSON on stdin) and fallback (--fallback, called by
#   the skill when the hook did not fire).
#
# Inputs:
#   Hook mode (default):
#     stdin — JSON with keys: prompt (string), transcript_path (string),
#             cwd (string), session_id (string). All optional; missing keys
#             treated as empty strings.
#     Requires: jq on PATH for JSON parsing; exits 0 immediately if absent.
#   Fallback mode (--fallback):
#     No stdin. cwd comes from $PWD. Transcript tail is unavailable and
#     skipped. prompt.txt is NOT written (the skill writes it instead).
#
# Outputs:
#   Creates a capture directory at:
#     <CAPTURE_ROOT>/<UTC %Y%m%dT%H%M%SZ>-<worktree-basename>/
#   with collision suffixes (-2, -3, ...) when the base name already exists.
#
#   Files written to the capture directory:
#     meta.txt              — timestamp, mode, cwd, session_id, worktree basename
#     prompt.txt            — verbatim triggering prompt (hook mode only),
#                             capped at PROMPT_MAX_BYTES (default 65536)
#     transcript-tail.jsonl — last 20 assistant messages from transcript_path,
#                             size-capped at TAIL_MAX_BYTES (default 204800),
#                             oldest lines dropped first (hook mode only,
#                             requires readable transcript_path)
#     <state files>         — copies of all regular files at depth 1 in
#                             <cwd>/.local/ (preserving basenames); plus an
#                             ls listing of each subdirectory of .local/ as
#                             <dirname>-listing.txt
#     git-state.txt         — branch name, bounded porcelain status (first 100
#                             lines), last 3 commits
#     crons.txt             — copy of <cwd>/.claude/scheduled_tasks.json if
#                             present
#
# Errors:
#   NEVER fails. Exit 0 on every path including: missing jq, unreadable
#   transcript, missing .local/, stat failures, mkdir failures, date failures.
#   Capture what exists, skip the rest.
#   stdout stays empty on every path (UserPromptSubmit stdout is injected into
#   conversation context). All diagnostics go to stderr.
#   No network calls (must finish well under 5s hook timeout).
#
# Invariants:
#   - stdout is always empty (enforced by exec >&2 at top of script)
#   - exit code is always 0
#   - no network calls, no subshells that call network
#   - captures are machine-local, never committed
#   - in hook mode, non-matching prompts (no "/make-progress" substring) exit
#     immediately after one jq parse + one string match — no filesystem writes
#   - collision suffixes ensure no data loss on same-second invocations
#
# Edge cases:
#   - Prompt does not contain /make-progress: fast-path exit 0, no writes
#   - jq not on PATH (hook mode): exit 0, no writes
#   - Duplicate hook fire: same non-empty session_id within DEDUPE_SECS
#     (default 60) of the newest capture for this worktree → exit 0, no writes.
#     Age is from directory birth time (clam_birth_epoch); falls back to mtime
#     if birth is 0/unavailable; any stat failure means "capture anyway".
#     Fallback mode and empty session_id never dedupe.
#   - Capture dir for this worktree already has DECISION.md (belongs to a
#     previous invocation the hook deduped into): treated as no match by the
#     skill, not by this hook (the hook does not check DECISION.md).
#   - .local/ does not exist: state-file capture silently skipped
#   - .local/ contains subdirectories: their contents listed in
#     <dirname>-listing.txt (not recursively copied)
#   - Empty or zero-byte transcript: transcript-tail.jsonl not created
#   - Malformed JSON lines in transcript: silently dropped (jq fromjson?)
#   - $PWD contains spaces: all paths quoted
#   - Worktree basename collision (e.g. "wt" vs "wt-bare"): anchored glob
#     patterns prevent cross-matching
#
# Overrides (for tests):
#   MAKE_PROGRESS_CAPTURE_ROOT     — capture root (default ~/.claude/make-progress-captures)
#   MAKE_PROGRESS_TAIL_MAX_BYTES   — transcript-tail size cap (default 204800)
#   MAKE_PROGRESS_PROMPT_MAX_BYTES — prompt.txt size cap (default 65536)
#   MAKE_PROGRESS_DEDUPE_SECS      — duplicate-fire dedupe window (default 60)

echo "NotImplemented: B02 — capture hook stub" >&2
exit 0
