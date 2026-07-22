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

set -e

LOG="$HOME/.claude/skill-triggers.jsonl"

if [[ ! -f "$LOG" ]]; then
    echo "No skill trigger log at $LOG"
    echo "(Created on first Skill tool invocation in a clam session.)"
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required but not installed."
    exit 1
fi

# jq's default parser aborts entirely on the first malformed JSON value in a
# multi-document stream, which would drop every row after a bad line. Reading
# raw lines and parsing each independently via fromjson? skips bad lines
# without aborting the rest.
PRE=$(jq -R -c 'fromjson? | select(.event=="pre")' "$LOG")

if [[ -z "$PRE" ]]; then
    echo "No skill triggers logged yet."
else
    total=$(printf '%s\n' "$PRE" | wc -l | tr -d ' ')
    unique=$(printf '%s\n' "$PRE" | jq -r '.skill // "(unknown)"' | sort -u | wc -l | tr -d ' ')
    first=$(printf '%s\n' "$PRE" | head -1 | jq -r '.ts')
    last=$(printf '%s\n' "$PRE" | tail -1 | jq -r '.ts')

    echo "Skill Trigger Stats"
    echo "==================="
    echo "Log:    $LOG"
    echo "Range:  $first .. $last"
    echo "Total:  $total triggers, $unique unique skills"
    echo ""

    echo "Top skills (all-time)"
    echo "---------------------"
    printf '%s\n' "$PRE" \
      | jq -r '.skill // "(unknown)"' \
      | sort | uniq -c | sort -rn | head -15 \
      | awk '{n=$1; $1=""; sub(/^ /,""); printf "  %-45s %d\n", $0, n}'
    echo ""

    echo "Daily triggers (last 14 days)"
    echo "-----------------------------"
    cutoff=$(date -u -d "-13 days" +%Y-%m-%d 2>/dev/null || date -u -v-13d +%Y-%m-%d)
    printf '%s\n' "$PRE" \
      | jq -r '.ts | .[0:10]' \
      | awk -v cutoff="$cutoff" '$0 >= cutoff' \
      | sort | uniq -c \
      | awk '{printf "  %s  %d\n", $2, $1}'
    echo ""
fi

err_count=$(jq -R -c 'fromjson? | select(.event=="post" and .error != null)' "$LOG" | wc -l | tr -d ' ')
echo "Errors: $err_count"
if [[ "$err_count" -gt 0 ]]; then
    jq -R -c 'fromjson? | select(.event=="post" and .error != null) | {ts, skill, error}' "$LOG" | head -10 | sed 's/^/  /'
fi
