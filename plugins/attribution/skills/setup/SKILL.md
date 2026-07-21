---
name: setup
description: "Write or remove the attribution suppression setting at the plugin's installation scope. Explicit opt-in: installing the plugin changes nothing until the user runs /attribution:setup."
disable-model-invocation: true
---

# Attribution Setup

<!--
Contract: B01 attribution
Behavior:   Writes `attribution: {"commit":"","pr":""}` to the Claude Code
             settings file matching the plugin's installation scope, suppressing
             the co-author line on commits and the attribution block on PRs.
             `/attribution:setup remove` reverses the change.
Inputs:      Subcommand (none = install, "remove" = uninstall). No other args.
Outputs:     A confirmation message stating what was written, to which file, and
             at which scope. On remove: confirmation of what was deleted.
Errors:
  - Plugin not found in installed_plugins.json → report and stop; do not guess.
  - Target settings file missing → treat as `{}` and create it.
  - Target settings file is not valid JSON → report and stop; do not corrupt.
  - `jq` not available → report and stop.
  - `attribution` key already set to a different value → show current value,
    ask before overwriting.
  - On remove: `attribution` key absent → report "nothing to remove", succeed.
Invariants:
  - Never touches settings keys other than `attribution`.
  - Always backs up the target file before writing (`<file>.bak-<date>`).
  - Merge semantics: read → patch one key → write. Never full-overwrite.
  - The written value is always exactly `{"commit":"","pr":""}` — no
    partial writes, no other shapes.
Edge cases:
  - Plugin installed at multiple scopes → present the list, ask which to
    configure; do not default silently.
  - Target file does not exist yet → create with only the `attribution` key.
  - Target file is empty (0 bytes) → treat as `{}`.
  - settings.json vs settings.local.json: scope "project" targets
    `.claude/settings.json`; scope "local" targets `.claude/settings.local.json`;
    scope "user" targets `~/.claude/settings.json`.
-->

<!-- NotImplemented: B01 — scope detection and jq merge instructions to be filled by implementer -->
