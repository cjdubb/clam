---
name: paths
description: "Show absolute paths to the current Claude Code session's conversation data files — transcript JSONL, subagent transcripts, file-history snapshots, session metadata — with sensitivity annotations. Use when the user wants to locate, review, or hand off their session data."
---

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
