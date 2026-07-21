---
name: setup
description: "Write or remove telemetry and feedback opt-out settings at the plugin's installation scope. Explicit opt-in: installing the plugin changes nothing until the user runs /privacy:setup."
disable-model-invocation: true
---

# Privacy Setup

<!--
Contract: B03 privacy
Behavior:   Writes telemetry and feedback opt-out settings to the Claude Code
             settings file matching the plugin's installation scope:

             env vars:
               CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
               DISABLE_TELEMETRY = "1"
               DISABLE_ERROR_REPORTING = "1"
               DISABLE_FEEDBACK_COMMAND = "1"
               CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1"

             top-level setting:
               feedbackSurveyRate = 0

             `/privacy:setup remove` reverses the change.
Inputs:      Subcommand (none = install, "remove" = uninstall). No other args.
Outputs:     A confirmation message stating what was written, to which file, and
             at which scope. On remove: confirmation of what was deleted.
Errors:
  - Plugin not found in installed_plugins.json → report and stop; do not guess.
  - Target settings file missing → treat as `{}` and create it.
  - Target settings file is not valid JSON → report and stop; do not corrupt.
  - `jq` not available → report and stop.
  - Any managed key already set to a different value → show current values,
    ask before overwriting.
  - On remove: managed keys absent → report "nothing to remove", succeed.
Invariants:
  - Never touches settings keys other than the six listed above.
  - Always backs up the target file before writing (`<file>.bak-<date>`).
  - Merge semantics: read → patch managed keys → write. Never full-overwrite.
  - All six settings are written atomically (one jq pass), never partially.
  - Env var values are always the string `"1"`, never a number or boolean.
  - `feedbackSurveyRate` is always the number `0`, never a string.
Edge cases:
  - Plugin installed at multiple scopes → present the list, ask which to
    configure; do not default silently.
  - Target file does not exist yet → create with only the managed keys.
  - Target file is empty (0 bytes) → treat as `{}`.
  - `env` key exists but is not an object → report and stop; do not corrupt.
  - settings.json vs settings.local.json: scope "project" targets
    `.claude/settings.json`; scope "local" targets `.claude/settings.local.json`;
    scope "user" targets `~/.claude/settings.json`.
-->

<!-- NotImplemented: B03 — scope detection and jq merge instructions to be filled by implementer -->
