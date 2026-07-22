---
name: stats
description: "Show skill trigger statistics — how often each skill fires, daily trends, and errors. Use when the user asks about skill usage, trigger frequency, or wants to audit which skills are being invoked."
---

<!-- B03 — stats skill

Behavior:
  Runs the skill-stats.sh reporter and presents the output to the user.

Inputs:
  None. The reporter reads ~/.claude/skill-triggers.jsonl.

Outputs:
  The stats report rendered in the conversation.

Errors:
  If the reporter exits non-zero (jq missing), relay the error message.
  If the log doesn't exist, relay the informational message.

Invariants:
  - Always runs the reporter via Bash; never reimplements the stats logic.
  - Presents the output verbatim — no summarization or filtering.

Edge cases:
  - No log file → show the "no log" message from the reporter
  - Empty results → show the "no triggers" message from the reporter
-->

# Skill Trigger Stats

Run the reporter and show its output. Do not reimplement the stats logic
here.

## `/skill-tracker:stats`

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-stats.sh` via the Bash tool.
2. Present the output verbatim — no summarization or filtering.
3. If the script exits non-zero, relay the error message it printed (e.g.
   `jq` missing) instead of the report.
4. If there's no log file yet, or the log has no triggers, relay the
   reporter's informational message as-is.
