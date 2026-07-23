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

# Stub bodies: deliberately unimplemented. They violate the contract on every
# path (no stdout, nonzero return) so that EVERY contract-clause test — happy
# path and fail-open alike — runs red against the scaffold. Implementations
# replace the bodies; the docblock above is the authoritative contract.
activity_prompts_since() {
    echo "NotImplemented: B01 activity-lib (activity_prompts_since)" >&2
    return 90
}

activity_prior_transcripts() {
    echo "NotImplemented: B01 activity-lib (activity_prior_transcripts)" >&2
    return 90
}
