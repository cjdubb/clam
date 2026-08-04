#!/usr/bin/env bash
# Contract: B02 prune-stamp (plan 001-stamp-staleness-actionable, issue #239)
# Behavior:
#   Delete exactly one setup-stamp record — the one matching both <plugin>
#   and <target> — from the shared stamp file, so a stale record can be
#   cleared through the flow instead of by hand-editing JSON. This is the
#   ONLY writer of that file outside the setup skills themselves, and the
#   only way to remove a record whose target no longer corresponds to an
#   installation (the setup skills' `remove` subcommands resolve their
#   target from installed_plugins.json and so cannot reach such a record).
#
#   Deliberately dumb: it deletes what it is told to delete. It performs no
#   liveness inference about whether a target "should" still be stamped —
#   see the plan's decision 001 for why every such heuristic considered was
#   wrong on the evidence. The judgement stays with the engineer, who is
#   offered the command and chooses to run it.
#
#   Stamp file format and its atomicity/corruption rules are specified in
#   ../docs/setup-stamps.md; this script is bound by that document.
# Inputs:
#   $1  plugin  — plugin name as it appears in a stamp record's `plugin`
#                 field (marketplace name, no "@clam" suffix). Required,
#                 non-empty.
#   $2  target  — the record's `target` field, matched by exact string
#                 equality. No path normalization, no symlink resolution,
#                 no tilde expansion: the value must match what is stored.
#                 Required, non-empty.
#   Env:
#     CLAUDE_CONFIG_DIR  root to read/write under (default: $HOME/.claude) —
#                        the override that makes this testable on fixtures.
#   No other arguments are accepted; extra arguments are an error.
# Outputs:
#   On a successful delete: a one-line confirmation on stdout naming the
#   plugin, the target, and the version of the record that was removed.
#   On a no-op (no matching record): a one-line notice on stdout saying so.
#   Nothing is written to stdout on any error path.
# Errors:
#   exit 2  wrong argument count, or an empty plugin/target argument
#           (usage message on stderr)
#   exit 3  stamp file does not exist — there is nothing to prune from;
#           message on stderr naming the path it looked for
#   exit 4  jq not available on PATH
#   exit 5  stamp file exists but is not valid JSON, or its `.stamps` is not
#           an array. NEVER repaired, moved aside, or overwritten here:
#           a corrupt file is reported and left exactly as found, because
#           this script's whole job is a targeted delete and it has no
#           basis to reconstruct a file it cannot parse.
#   exit 6  the write failed (backup, temp file, or mv) — the original file
#           is left intact; the failure names which step failed.
# Invariants:
#   - Deletes at most ONE record per run: the one matching (plugin, target)
#     exactly. Every other record survives byte-identical, including other
#     records for the same plugin at different targets and records for
#     other plugins at the same target.
#   - Idempotent: running twice is not an error. The second run finds no
#     match, changes nothing, and exits 0 (see Edge cases).
#   - Writes atomically: back up to <file>.bak-<YYYY-MM-DD>, write the new
#     content to a temp file, then `mv` it into place. The stamp file is
#     never truncated in place, so an interrupted run cannot leave it
#     partially written.
#   - Preserves the file's top-level `version` field and any other
#     top-level keys untouched.
#   - Never touches installed_plugins.json, any settings file, or any
#     marketplace clone. The stamp file is the only file it writes.
#   - No network access.
# Edge cases:
#   - No matching record: exit 0 with the notice on stdout, and NO write
#     at all — no backup file is created for a no-op. "Already absent" is
#     the desired end state, so it is success, matching the setup skills'
#     "no record present is silent success" rule in setup-stamps.md.
#   - Multiple records matching the SAME (plugin, target): all of them are
#     removed. Duplicates are already a malformed stamp file — the key is
#     specified as unique in setup-stamps.md — and leaving some behind
#     would make the command non-idempotent.
#   - Empty `.stamps` array: treated as no match; exit 0, no write.
#   - `target` given with a trailing slash, a relative path, or an
#     unexpanded "~": no match, because matching is exact string equality.
#     This is contract, not a bug — the confirmation/notice line is what
#     tells the caller which happened.
#   - Stamp file present but empty (0 bytes): not valid JSON, so exit 5.

set -euo pipefail

if [[ $# -ne 2 || -z "$1" || -z "$2" ]]; then
    echo "usage: prune-stamp.sh <plugin> <target>" >&2
    exit 2
fi
PLUGIN="$1"
TARGET="$2"

command -v jq &>/dev/null || {
    echo "prune-stamp: jq is required but was not found on PATH" >&2
    exit 4
}

CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMPS_FILE="$CLAUDE_CONFIG_DIR/clam-setup-stamps.json"

if [[ ! -f "$STAMPS_FILE" ]]; then
    echo "prune-stamp: stamp file not found: $STAMPS_FILE" >&2
    exit 3
fi

# A single check covers every malformed shape: invalid JSON, .stamps present
# but not an array, and .stamps missing entirely (jq sees it as null, whose
# type is "null", not "array"). Never repaired, moved aside, or overwritten —
# report and leave the bytes exactly as found (setup-stamps.md's "move a
# corrupt file aside" rule is scoped to the setup skills' writes, not this
# targeted delete, which has no basis to reconstruct a file it cannot parse).
if ! jq -e '(.stamps // null) | type == "array"' "$STAMPS_FILE" >/dev/null 2>&1; then
    echo "prune-stamp: stamp file is not valid JSON, or its .stamps is not an array: $STAMPS_FILE" >&2
    exit 5
fi

MATCHES=$(jq -c --arg p "$PLUGIN" --arg t "$TARGET" \
    '[.stamps[] | select(.plugin == $p and .target == $t)]' "$STAMPS_FILE")
MATCH_COUNT=$(jq 'length' <<<"$MATCHES")

if [[ "$MATCH_COUNT" -eq 0 ]]; then
    echo "prune-stamp: no stamp record for plugin '$PLUGIN' at target '$TARGET'; nothing to prune"
    exit 0
fi

# Decide the match BEFORE creating the backup — a no-op run above this point
# has written nothing, not even a backup.
VERSIONS=$(jq -r '[.[].version] | join(", ")' <<<"$MATCHES")

TODAY=$(date +%Y-%m-%d)
BACKUP_FILE="$STAMPS_FILE.bak-$TODAY"

# Backup, then temp file, then mv — in that order — so the stamp file's
# inode changes on success and an interrupted run never leaves it partially
# written. The original is left intact if any step below fails.
if ! cp "$STAMPS_FILE" "$BACKUP_FILE" 2>/dev/null; then
    echo "prune-stamp: failed to write backup file: $BACKUP_FILE" >&2
    exit 6
fi

TMP_FILE=$(mktemp "$STAMPS_FILE.tmp.XXXXXX" 2>/dev/null) || TMP_FILE=""
if [[ -z "$TMP_FILE" ]]; then
    rm -f "$BACKUP_FILE"
    echo "prune-stamp: failed to create temp file for stamp update" >&2
    exit 6
fi

if ! jq --arg p "$PLUGIN" --arg t "$TARGET" \
    '.stamps |= map(select(.plugin != $p or .target != $t))' "$STAMPS_FILE" >"$TMP_FILE" 2>/dev/null; then
    rm -f "$TMP_FILE" "$BACKUP_FILE"
    echo "prune-stamp: failed to write temp file for stamp update" >&2
    exit 6
fi

if ! mv "$TMP_FILE" "$STAMPS_FILE"; then
    rm -f "$TMP_FILE" "$BACKUP_FILE"
    echo "prune-stamp: failed to move temp file into place: $STAMPS_FILE" >&2
    exit 6
fi

echo "prune-stamp: removed stamp for plugin '$PLUGIN' at target '$TARGET' (version $VERSIONS)"
exit 0
