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

# Session Data Paths

Run the paths-resolution script and present the current session's
conversation data file locations to the user.

## `/session-data:paths`

1. **Run the script.** Execute
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.sh` and capture both
   its stdout and its exit code.

2. **On success (exit 0):** Present the script's output to the user,
   organized by the categories it reports (main transcript, subagent
   transcripts, file-history snapshots, session metadata).

   - **Sensitivity warning.** Always warn the user that these files may
     contain secrets — for example API keys, tokens, or other sensitive
     values captured in tool output within the transcript JSONL, or
     sensitive file contents preserved in file-history snapshots.
   - **Never read file contents without asking.** Do not open, read, or
     display the contents of any discovered file unless the user
     explicitly asks you to. If they do ask, repeat the sensitivity
     warning before reading.
   - **Offer to hand off.** After presenting the paths, offer to help the
     user hand the transcript path to a fresh agent for conversation
     review (e.g. "I can spawn a fresh agent with this transcript path to
     review the conversation — want me to?").

3. **On failure (non-zero exit):** Present the script's error message
   verbatim to the user and explain the likely cause — most commonly that
   the skill isn't running inside Claude Code, or that
   `CLAUDE_CODE_SESSION_ID` is not set in the environment.
