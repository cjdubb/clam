#!/bin/bash
# Contract: B03 precompact-snapshot
# Behavior: PreCompact hook (matcher=auto; fires only on auto-compaction, not
#   manual /compact). Snapshots .local/ tracking docs to a timestamped directory
#   (.local/snapshots/<timestamp>/) immediately before the harness compacts the
#   conversation. This is the deterministic backstop: if the agent did not flush
#   in-flight state (despite the flush-nudge), whatever was on disk is preserved
#   as a forensic and recovery point.
# Inputs:
#   - stdin: JSON with .cwd (working directory)
# Outputs:
#   - side effect: creates .local/snapshots/<YYYYMMDD-HHMMSS>/ with copies of
#     tracking docs
#   - side effect: appends an HTML-comment marker to .local/TODO.md recording
#     the snapshot timestamp and path
#   - stdout: empty (PreCompact hooks cannot inject context into the agent)
# Errors: fail-open — any error exits 0 with no output. A snapshot failure must
#   never block compaction.
# Invariants:
#   - Always exits 0.
#   - Gated on .local/TODO.md existing — if tracking has no state file, there
#     is nothing to snapshot.
#   - Files copied: TODO.md, PLAN.md, IMPLEMENTATION-PLAN.md,
#     TROUBLESHOOTING.md, FOLLOWUPS.md, WORKGRAPH.md, and all
#     SUBAGENT-LOG-*.md files from .local/.
#   - Never modifies the source files (except the HTML-comment marker appended
#     to TODO.md).
#   - HTML-comment marker format:
#     <!-- AUTO-COMPACTION YYYY-MM-DD HH:MM:SS — pre-compact snapshot at .local/snapshots/<ts>/ -->
#     Appended to the end of TODO.md. Does not render in markdown previews.
#   - Empty snapshot directories (no files copied) are cleaned up (rmdir).
#   - Timestamp format for directory name: YYYYMMDD-HHMMSS (local timezone).
#   - Requires jq for input parsing; skips silently without it.
# Edge cases:
#   - .local/TODO.md does not exist → skip (nothing to protect)
#   - .local/ directory does not exist → skip
#   - cwd missing from input JSON → skip
#   - None of the tracked files exist in .local/ → rmdir the empty snapshot dir
#   - Snapshot directory already exists (same-second compaction) → files
#     overwrite; no collision handling needed (compaction is not concurrent)
#   - TODO.md is not writable (read-only fs) → skip marker append, still exit 0
#   - Snapshot directory creation fails → exit 0 (fail-open)
#   - jq not available → skip
#   - SUBAGENT-LOG-*.md glob matches nothing → no-op (nullglob)

set -e

command -v jq &>/dev/null || exit 0

input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
[[ -n "$cwd" ]] || exit 0

[[ -f "$cwd/.local/TODO.md" ]] || exit 0

ts=$(date '+%Y%m%d-%H%M%S')
snapshot_dir="$cwd/.local/snapshots/$ts"
mkdir -p "$snapshot_dir" 2>/dev/null || exit 0

# Contract: B04 — followups-lifecycle (snapshot leg)
# Behavior: FOLLOWUPS.md joins this fixed snapshot list, appended after
#   TROUBLESHOOTING.md, so captured follow-ups survive auto-compaction like
#   the other tracking docs (copy-if-present semantics unchanged).
# Invariants: list order otherwise preserved; the header comment at the top
#   of this script naming the copied files is updated to match; absent
#   FOLLOWUPS.md remains a silent no-op.
#
# Contract: B05 — workgraph-lifecycle (snapshot leg, plan 001-tracking-work-graph)
# Behavior: WORKGRAPH.md joins the same fixed snapshot list, appended after
#   FOLLOWUPS.md, so the work graph survives auto-compaction like the other
#   tracking docs (copy-if-present semantics unchanged).
# Invariants: list order otherwise preserved; the header comment at the top
#   of this script naming the copied files is updated to match; absent
#   WORKGRAPH.md remains a silent no-op.
copied=0
for f in TODO.md PLAN.md IMPLEMENTATION-PLAN.md TROUBLESHOOTING.md FOLLOWUPS.md WORKGRAPH.md; do
    if [[ -f "$cwd/.local/$f" ]]; then
        cp "$cwd/.local/$f" "$snapshot_dir/" 2>/dev/null && copied=$((copied + 1))
    fi
done

# Subagent logs use a per-name suffix (SUBAGENT-LOG-foo.md); glob may not
# match anything, in which case nullglob keeps the loop a no-op.
shopt -s nullglob
for f in "$cwd/.local"/SUBAGENT-LOG-*.md; do
    cp "$f" "$snapshot_dir/" 2>/dev/null && copied=$((copied + 1))
done
shopt -u nullglob

# If nothing was snapshotted there's no marker worth writing. Cleanup.
if [[ "$copied" -eq 0 ]]; then
    rmdir "$snapshot_dir" 2>/dev/null || true
    exit 0
fi

# Marker into TODO.md so a future session can see when its state was last
# potentially-stale and where the snapshot lives. HTML comment so it
# doesn't render in markdown previews.
{
    printf '\n<!-- AUTO-COMPACTION %s — pre-compact snapshot at .local/snapshots/%s/ -->\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$ts"
} >> "$cwd/.local/TODO.md" 2>/dev/null || true

exit 0
