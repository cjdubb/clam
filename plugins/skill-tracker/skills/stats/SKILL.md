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

STUB: not yet implemented
