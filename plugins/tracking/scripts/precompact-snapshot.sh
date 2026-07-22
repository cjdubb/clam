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
#     TROUBLESHOOTING.md, and all SUBAGENT-LOG-*.md files from .local/.
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

# NotImplemented: B03
exit 0
