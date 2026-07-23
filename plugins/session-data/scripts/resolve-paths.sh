#!/bin/bash
# <!--
# Contract: B01 resolve-paths
#
# Behavior:
#   Discovers and reports all conversation data files for the current Claude
#   Code session. Derives the project directory from $PWD (replacing / with
#   -), uses $CLAUDE_CODE_SESSION_ID to locate the main transcript JSONL,
#   then discovers related artifacts: subagent transcripts, file-history
#   snapshots, and session metadata. Outputs a structured, human-readable
#   report with one section per data category, each showing the absolute
#   path, existence status, size (when present), and a sensitivity
#   annotation.
#
# Inputs:
#   - Environment: CLAUDE_CODE_SESSION_ID (required), CLAUDE_PID (optional),
#     PWD (always set), HOME (always set)
#   - No arguments, no stdin, no config files
#
# Outputs:
#   Structured text to stdout. Sections:
#   - Header with session ID and derived project directory
#   - Main transcript JSONL: absolute path, existence, human-readable size
#   - Subagent transcripts: directory path, existence, count of .jsonl files
#   - File-history snapshots: directory path, existence, file count
#   - Session metadata: path (via CLAUDE_PID), existence
#   Each section includes a sensitivity annotation line where the category
#   may contain secrets (tool output in JSONL, file contents in history).
#   Exit code 0 on success, 1 on missing required env vars.
#
# Errors:
#   - CLAUDE_CODE_SESSION_ID not set: print diagnostic to stderr, exit 1
#   - HOME not set: print diagnostic to stderr, exit 1
#   - Paths that don't exist: reported as "[not found]" in the output, not
#     an error (exit 0)
#   - CLAUDE_PID not set: skip session-metadata section with a note, not
#     an error
#
# Invariants:
#   - Read-only: never creates, modifies, or deletes any file
#   - Never surfaces ~/.claude/daemon/roster.json, ~/.claude/.credentials.json,
#     or any other security-sensitive Claude Code internal
#   - Sensitivity annotations are always present for categories that may
#     contain secrets (transcript JSONL, subagent transcripts, file-history)
#   - Output is deterministic for a given environment state
#   - All paths in output are absolute
#
# Edge cases:
#   - PWD contains spaces or special characters: paths must not break
#   - No subagent transcripts exist (directory absent): reported as not found
#   - No file-history exists: reported as not found
#   - Session metadata file gone (process ended): reported as not found
#   - CLAUDE_CODE_SESSION_ID is set but the JSONL doesn't exist yet (very
#     early in session): path reported with "[not found]"
#   - Multiple .jsonl files in subagents dir: count reported accurately
#   - Project directory name derived from a PWD with leading slash: the
#     leading slash becomes the leading dash (e.g., /home/user -> -home-user)
# -->

if [[ -z "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
  echo "Error: required environment variable CLAUDE_CODE_SESSION_ID is not set." >&2
  exit 1
fi

if [[ -z "${HOME:-}" ]]; then
  echo "Error: required environment variable HOME is not set." >&2
  exit 1
fi

session_id="$CLAUDE_CODE_SESSION_ID"
sanitized_cwd="${PWD//\//-}"
project_dir="$HOME/.claude/projects/$sanitized_cwd"

echo "Claude Code session data paths"
echo "==============================="
echo ""
echo "Session ID: $session_id"
echo "Project directory: $project_dir"
echo ""

transcript="$project_dir/$session_id.jsonl"
echo "Main transcript (sensitive: may contain tool output and file contents)"
echo "  Main transcript path: $transcript"
if [[ -f "$transcript" ]]; then
  size=$(wc -c < "$transcript" | tr -d ' ')
  echo "  Main transcript status: found"
  echo "  Main transcript size: $size bytes"
else
  echo "  Main transcript status: [not found]"
fi
echo ""

subagents_dir="$project_dir/$session_id/subagents"
echo "Subagent transcripts (sensitive: may contain tool output and file contents)"
echo "  Subagent transcripts directory: $subagents_dir"
if [[ -d "$subagents_dir" ]]; then
  subagent_count=$(find "$subagents_dir" -maxdepth 1 -type f -name '*.jsonl' | wc -l | tr -d ' ')
  echo "  Subagent transcripts status: found"
  echo "  Subagent transcripts count: $subagent_count .jsonl file(s)"
else
  echo "  Subagent transcripts status: [not found]"
fi
echo ""

filehist_dir="$HOME/.claude/file-history/$session_id"
echo "File-history snapshots (sensitive: may contain full contents of edited files)"
echo "  File-history directory: $filehist_dir"
if [[ -d "$filehist_dir" ]]; then
  filehist_count=$(find "$filehist_dir" -maxdepth 1 -type f | wc -l | tr -d ' ')
  echo "  File-history status: found"
  echo "  File-history count: $filehist_count file(s)"
else
  echo "  File-history status: [not found]"
fi

if [[ -n "${CLAUDE_PID:-}" ]]; then
  meta_path="$HOME/.claude/sessions/$CLAUDE_PID.json"
  echo ""
  echo "Session metadata"
  echo "  Session metadata path: $meta_path"
  if [[ -f "$meta_path" ]]; then
    echo "  Session metadata status: found"
  else
    echo "  Session metadata status: [not found]"
  fi
fi

exit 0
