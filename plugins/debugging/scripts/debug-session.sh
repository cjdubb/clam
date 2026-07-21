#!/usr/bin/env bash
# Contract: B09 debug-session-script
#
# Behavior:
#   CLI managing the .local/debug/ artifact tree for a debugging session.
#   Two subcommands:
#     debug-session.sh start <slug>
#       Creates the next-numbered session dir .local/debug/NNN-<slug>/
#       containing journal.md (copied VERBATIM from this plugin's
#       templates/journal.md) and an empty queries/ subdir.
#     debug-session.sh query <session-dir> <name> [ext]
#       Creates the next-numbered query dir <session-dir>/queries/NN-<name>/
#       containing an empty query file query.<ext> (ext defaults to txt) and
#       results.md (copied VERBATIM from templates/query-results.md).
#
# Inputs:
#   <slug>, <name>: must match ^[a-z0-9][a-z0-9-]*$ (lowercase kebab).
#   <session-dir>:  path to an existing session dir that contains journal.md.
#   [ext]:          must match ^[a-z0-9]+$ (e.g. txt, sql, logql); default txt.
#   CWD:            `start` resolves .local/ relative to the current working
#                   directory; .local/ itself must already exist (it marks the
#                   repo/worktree root). Templates are resolved relative to
#                   THIS SCRIPT's location (../templates), never the CWD.
#
# Outputs:
#   stdout on success: exactly one line — the path of the directory created
#   (as resolvable from the CWD: .local/debug/NNN-<slug> for start;
#   <session-dir>/queries/NN-<name> for query). Exit 0.
#
# Numbering:
#   NNN: three-digit zero-padded, starts at 001; next = highest existing
#   NNN-* dir under .local/debug/ + 1, regardless of slug; non-matching
#   entries are ignored. NN: two-digit zero-padded, starts at 01, same rule
#   over <session-dir>/queries/. Numbering never reuses or fills gaps.
#
# Errors (every failure: exactly ONE `ERROR: <message>` line on stderr,
# exit 1, nothing on stdout, no partial artifacts left behind):
#   - unknown or missing subcommand; wrong arg count for the subcommand
#   - invalid slug / name / ext (pattern above)
#   - `start` when ./.local does not exist
#   - `query` when <session-dir> does not exist or lacks journal.md
#   - template file missing at the script-relative location
#
# Invariants:
#   - Never overwrites or modifies existing files or dirs; each call creates
#     exactly one new numbered dir plus its contracted contents.
#   - Writes only within .local/debug/ (start) or the given session dir's
#     queries/ (query).
#   - No network, no git commands; plain filesystem only.
#
# Edge cases:
#   - Numbering overflow past 999/99 is an error, not a wraparound.
#   - A .local/debug entry that is a file (not dir) is ignored for numbering.
#   - Spaces in CWD paths are handled (quote-safe throughout).
set -u

echo "ERROR: NotImplemented: B09" >&2
exit 1
