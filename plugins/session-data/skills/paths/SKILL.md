---
name: paths
description: "Show absolute paths to the current Claude Code session's conversation data files — transcript JSONL, subagent transcripts, file-history snapshots, session metadata — with sensitivity annotations. Use when the user wants to locate, review, or hand off their session data."
---

<!--
Contract: B02 paths-skill

Behavior:
  Instructs Claude to run resolve-paths.sh and present the output to the
  user. After presenting, offers to help the user hand paths to a fresh
  agent for conversation review, and warns about sensitivity of files that
  may contain secrets in tool outputs or edited file snapshots.

Inputs:
  Invocation as /session-data:paths. No arguments.

Outputs:
  Claude runs the script, presents the structured output with brief
  explanations of what each data category is, and offers next-step
  suggestions (e.g., "I can spawn a fresh agent to review this transcript"
  or "copy the path to hand to another session").

Errors:
  - Script exits non-zero: Claude reports the error message to the user
    and explains the likely cause (e.g., not running inside Claude Code)
  - Script not found at expected path: Claude reports the issue

Invariants:
  - Always runs the script; never guesses or remembers paths from prior
    invocations
  - Always includes the sensitivity warning in presentation
  - Never opens, reads, or displays the contents of any discovered file
    unless the user explicitly asks — and warns about sensitivity first
  - The script path is always ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.sh

Edge cases:
  - User invokes outside of Claude Code (env vars missing): script handles
    gracefully with exit 1 diagnostic; skill presents the diagnostic
  - User asks to review a specific file after seeing paths: skill may read
    it but warns about sensitivity first and asks for confirmation
  - User asks to "hand this to a fresh agent": skill suggests spawning an
    agent with the transcript path, noting the agent will see full tool
    output including any secrets
-->

<!-- NotImplemented: B02 -->
