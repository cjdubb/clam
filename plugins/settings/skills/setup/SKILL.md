---
name: setup
description: "Write or remove the agent-teams and adaptive-thinking env vars at the plugin's installation scope. Explicit opt-in: installing the plugin changes nothing until the user runs /settings:setup."
disable-model-invocation: true
---

# Settings Setup

<!--
Contract: B02 settings
Behavior:   Writes two env vars into the `env` object of the Claude Code
             settings file matching the plugin's installation scope:
               CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
               CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1"
             `/settings:setup remove` reverses the change.
Inputs:      Subcommand (none = install, "remove" = uninstall). No other args.
Outputs:     A confirmation message stating what was written, to which file, and
             at which scope. On remove: confirmation of what was deleted.
Errors:
  - Plugin not found in installed_plugins.json → report and stop; do not guess.
  - Target settings file missing → treat as `{}` and create it.
  - Target settings file is not valid JSON → report and stop; do not corrupt.
  - `jq` not available → report and stop.
  - Either env var already set to a different value → show current values,
    ask before overwriting.
  - On remove: env vars absent → report "nothing to remove", succeed.
Invariants:
  - Never touches settings keys other than `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`
    and `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`.
  - Always backs up the target file before writing (`<file>.bak-<date>`).
  - Merge semantics: read → patch env keys → write. Never full-overwrite.
  - Both vars are written atomically (one jq pass), never partially.
  - Values are always the string `"1"`, never a number or boolean.
Edge cases:
  - Plugin installed at multiple scopes → present the list, ask which to
    configure; do not default silently.
  - Target file does not exist yet → create with only the `env` object.
  - Target file is empty (0 bytes) → treat as `{}`.
  - `env` key exists but is not an object → report and stop; do not corrupt.
  - settings.json vs settings.local.json: scope "project" targets
    `.claude/settings.json`; scope "local" targets `.claude/settings.local.json`;
    scope "user" targets `~/.claude/settings.json`.
-->

<!-- NotImplemented: B02 — scope detection and jq merge instructions to be filled by implementer -->
