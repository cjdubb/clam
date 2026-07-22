#!/bin/bash
# SessionStart hook for the landing plugin. Reads the repo's landing policy
# from .claude/clam-profile.jsonc and injects the parsed merge policy into
# the session context.
#
# Contract: B01 profile-format-migration
#
# Behavior:
#   Reads .claude/clam-profile.jsonc (JSONC with // line comments) from the
#   session's cwd. Strips comments, extracts merge.strategy, merge.target,
#   and merge.merged-by via jq, and injects a SessionStart additionalContext
#   block with the policy summary and the /landing:land instruction. When no
#   profile exists, injects a /landing:init nudge instead.
#
# Inputs:
#   stdin — JSON object with at least { "cwd": "<path>" }.
#
# Outputs:
#   stdout — valid hookSpecificOutput JSON:
#   { "hookSpecificOutput": { "hookEventName": "SessionStart",
#     "additionalContext": "<policy summary>" } }
#   OR no output (fail-open).
#
# Errors:
#   All errors fail open: exit 0, no output. Never breaks session start.
#   Specific fail-open triggers: jq not on PATH, no cwd in payload,
#   unreadable profile, invalid JSON after comment stripping.
#
# Invariants:
#   - Only .claude/clam-profile.jsonc is read; the legacy .md path is
#     never consulted.
#   - The profile body (JSONC comments) is never parsed for policy values.
#   - Output shape is identical to v1 (strategy=X, target=Y, merged-by=Z)
#     so downstream consumers see no change.
#
# Edge cases:
#   - Profile with no merge section: all values render as "unset".
#   - Profile with extra/unknown keys: ignored (forward-compatible).
#   - Values containing special characters: jq handles escaping.
#   - Empty or whitespace-only cwd: treated as missing, fail-open.

set -u

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)

# Missing, empty, or whitespace-only cwd: nothing to inspect, fail open.
[[ -n "${cwd//[[:space:]]/}" ]] || exit 0

profile="$cwd/.claude/clam-profile.jsonc"

emit() { # additionalContext
  jq -n --arg ctx "$1" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
}

if [[ ! -e "$profile" ]]; then
  emit "No landing policy recorded for this repo yet. Run /landing:init to detect and record how work lands here, then /landing:land to land finished work."
  exit 0
fi

# Unreadable profile: fail open silently (distinct from "no profile").
[[ -r "$profile" ]] || exit 0

stripped=$(sed 's#//.*##' "$profile" 2>/dev/null)

printf '%s' "$stripped" | jq empty >/dev/null 2>&1 || exit 0

strategy=$(printf '%s' "$stripped" | jq -r '.merge.strategy // "unset"' 2>/dev/null) || exit 0
target=$(printf '%s' "$stripped" | jq -r '.merge.target // "unset"' 2>/dev/null) || exit 0
merged_by=$(printf '%s' "$stripped" | jq -r '.merge["merged-by"] // "unset"' 2>/dev/null) || exit 0

emit "strategy=$strategy, target=$target, merged-by=$merged_by. Land finished work with /landing:land."
