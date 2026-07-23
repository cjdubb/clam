#!/bin/bash
# Shared conversation-activity readers for the tracking plugin.
# Sourced (not executed) by hook scripts; bash-3.2-safe; requires jq for any
# non-trivial result and fails open (0 / empty output, return 0) without it.
#
# Contract: B01 — activity-lib
#
# Behavior:
#   Two pure reader functions over Claude Code conversation transcripts, used
#   by the freshness Stop gate (B02) and the resume-freshness SessionStart
#   check (B04) to compare `.local/` tracking-doc age against conversation
#   activity. Read-only: neither function writes, deletes, or locks anything.
#
# Functions:
#
#   activity_prompts_since <ref_epoch> <transcript_path>
#     Behavior:
#       Prints (stdout, single line, no padding) the count of HUMAN PROMPTS in
#       the transcript strictly newer than <ref_epoch>.
#       A transcript line counts as a human prompt when ALL hold:
#         - it is valid JSON (malformed lines are skipped, never fatal);
#         - .type == "user";
#         - .message.content is a STRING (array-content user entries are tool
#           results, never typed prompts);
#         - .isMeta is absent or false;
#         - the content does NOT look machine-generated, i.e. it does not
#           start (after optional whitespace) with any of:
#             "<"                                  (command echoes
#                                                   <command-name>/<local-command-*,
#                                                   <teammate-message>,
#                                                   <system-reminder>, ...)
#             "Stop hook feedback:"                (hook feedback turns)
#             "Another Claude session sent"        (teammate relay preamble)
#             "[Request interrupted"               (interruption notices)
#             "Shell cwd was reset"                (harness cwd notices)
#             "Caveat: the messages below"         (local-command caveat)
#         - .timestamp parses as ISO-8601 UTC (milliseconds tolerated:
#           "2026-07-23T01:47:31.720Z" and "...:31Z" both valid) AND its epoch
#           value is strictly greater than <ref_epoch>.
#     Inputs:
#       ref_epoch       — integer seconds since the Unix epoch. Non-integer or
#                         empty → fail-open (prints 0).
#       transcript_path — path to a session .jsonl. Missing, unreadable, empty,
#                         or a directory → fail-open (prints 0).
#     Outputs:
#       stdout: a single non-negative integer followed by a newline. Exactly
#       one line on EVERY path, including all failure paths ("0").
#     Errors:
#       Never returns nonzero. No jq → prints 0. Any jq/parse failure → 0.
#       Never writes to the transcript. stderr may carry diagnostics.
#     Invariants:
#       - Pure read; idempotent; no globals mutated beyond its own locals.
#       - Filtering is best-effort: OVERCOUNTING is tolerated by consumers
#         (both callers gate on thresholds and once-per-epoch markers);
#         undercounting to zero on any doubt/error is the required bias.
#       - Single pass over the file (transcripts run to several MB; callers
#         run inside 5-10s hook timeouts).
#     Edge cases:
#       - ref_epoch in the future → 0.
#       - Timestamps without milliseconds, or with unparseable formats: lines
#         with unparseable timestamps are skipped (not counted).
#       - Entries missing .timestamp entirely → skipped.
#
#   activity_prior_transcripts <cwd> [exclude_path]
#     Behavior:
#       Prints (stdout) the absolute paths of conversation transcript .jsonl
#       files recorded for the worktree at <cwd>, one per line, NEWEST FIRST
#       by file mtime. The project directory is derived with the Claude Code
#       convention used by session-data/scripts/resolve-paths.sh:
#         $HOME/.claude/projects/<cwd with every "/" replaced by "-">
#       (a leading "/" becomes a leading "-"). Only regular *.jsonl files
#       DIRECTLY in that directory are listed (no recursion — subdirectories
#       hold per-session sidecar data, not conversation transcripts).
#     Inputs:
#       cwd          — absolute path of the worktree. Empty → no output.
#       exclude_path — optional; a transcript path to omit (the CURRENT
#                      session's transcript, which hooks receive on stdin).
#                      Compared after path normalization is NOT required:
#                      literal string equality on the constructed candidate
#                      path is sufficient.
#     Outputs:
#       stdout: zero or more absolute paths, one per line, mtime-descending.
#       No output at all (not even a blank line) when the project directory
#       does not exist or contains no matching files.
#     Errors:
#       Never returns nonzero. Unreadable directory → no output.
#     Invariants:
#       - Pure read. Deterministic given a fixed filesystem state (ties on
#         identical mtimes may order arbitrarily but stably within one call).
#       - Must not depend on CLAUDE_CODE_SESSION_ID or any session env; the
#         ONLY inputs are the two arguments and $HOME.
#     Edge cases:
#       - cwd containing "-" characters: no special handling; the encoding is
#         lossy by design and collisions are accepted (upstream convention).
#       - exclude_path names a file not in the listing → listing unchanged.
#       - Project dir exists but only the excluded transcript is present →
#         no output.
#
# Composition note (for consumers):
#   "Docs are stale" is DEFINED as:
#     activity_prompts_since(mtime(.local/TODO.md), <transcript>) >= threshold
#   B02 applies it to the current session's transcript (threshold
#   CLAM_TRACKING_FRESHNESS_THRESHOLD, default 2); B04 sums the count over the
#   newest 5 prior transcripts (threshold CLAM_TRACKING_RESUME_STALE_THRESHOLD,
#   default 1). Thresholds live with the consumers, not here.

activity_prompts_since() {
    local ref_epoch="$1"
    local transcript_path="$2"

    [[ "$ref_epoch" =~ ^[0-9]+$ ]] || { printf '%s\n' "0"; return 0; }
    [[ -f "$transcript_path" && -r "$transcript_path" && -s "$transcript_path" ]] || { printf '%s\n' "0"; return 0; }
    command -v jq >/dev/null 2>&1 || { printf '%s\n' "0"; return 0; }

    # Single jq pass over the file (transcripts run to several MB): parse each
    # line best-effort (fromjson? drops malformed lines), apply every
    # contract filter, normalize/parse the timestamp, and collect only the
    # epochs that qualify — the array's length is the count. try/catch around
    # the date parse means an unparseable timestamp drops that line rather
    # than aborting the whole pass.
    local count
    count=$(jq -nR --argjson ref "$ref_epoch" '
        def is_machine_generated:
            test("^\\s*(<|Stop hook feedback:|Another Claude session sent|\\[Request interrupted|Shell cwd was reset|Caveat: the messages below)");
        [
            inputs
            | fromjson?
            | select(.type == "user")
            | select((.message.content | type) == "string")
            | select((.isMeta // false) == false)
            | select((.message.content | is_machine_generated) | not)
            | (.timestamp // empty)
            | select(. != "")
            | sub("\\.[0-9]+Z$"; "Z")
            | (try fromdateiso8601 catch empty)
            | select(. > $ref)
        ] | length
    ' "$transcript_path" 2>/dev/null) || true

    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    printf '%s\n' "$count"
    return 0
}

activity_prior_transcripts() {
    local cwd="$1"
    local exclude_path="${2:-}"

    [[ -n "$cwd" ]] || return 0

    local sanitized="${cwd//\//-}"
    local project_dir="$HOME/.claude/projects/$sanitized"

    [[ -d "$project_dir" && -r "$project_dir" ]] || return 0

    # Direct-children-only glob (no recursion); -f rejects both non-matches
    # (the unexpanded literal pattern, when nothing matches) and directories
    # that merely happen to end in .jsonl.
    local f
    local -a files=()
    for f in "$project_dir"/*.jsonl; do
        [[ -f "$f" ]] || continue
        [[ "$f" == "$exclude_path" ]] && continue
        files+=("$f")
    done

    [[ "${#files[@]}" -gt 0 ]] || return 0

    local out
    out=$(ls -1t -- "${files[@]}" 2>/dev/null) || return 0
    [[ -n "$out" ]] && printf '%s\n' "$out"
    return 0
}
