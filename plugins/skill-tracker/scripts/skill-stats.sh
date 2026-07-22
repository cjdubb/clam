#!/bin/bash
# B02 — skill-stats reporter
#
# Behavior:
#   Reads ~/.claude/skill-triggers.jsonl and prints a single comprehensive
#   report to stdout. JSONL-only — no on-disk skill directory scanning.
#
# Inputs:
#   No arguments. Reads from $HOME/.claude/skill-triggers.jsonl.
#
# Outputs (stdout, plain text):
#   Header: "Skill Trigger Stats" with log path and date range
#   Section 1: Total triggers and unique skill count
#   Section 2: "Top skills (all-time)" — top 15 by invocation count
#   Section 3: "Daily triggers (last 14 days)" — date and count per day
#   Section 4: "Errors:" — count, plus up to 10 error details if any
#
# Errors:
#   - Log file missing → prints informational message, exits 0
#   - jq not installed → prints error message, exits 1
#   - No triggers in log → prints "No skill triggers logged yet.", exits 0
#
# Invariants:
#   - Only reads pre-events for trigger counting (event=="pre").
#   - Error counting uses post-events with non-null error field.
#   - Output is deterministic for a given JSONL file.
#   - Never modifies the log file.
#
# Edge cases:
#   - Empty log file → "No skill triggers logged yet."
#   - Log with only post events → "No skill triggers logged yet."
#   - Skills with null name → counted as "(unknown)"
#   - Malformed JSONL lines → skipped by jq

exit 1  # STUB: not yet implemented
