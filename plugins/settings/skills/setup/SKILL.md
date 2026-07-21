---
name: setup
description: "Write or remove session defaults (env vars, model, effort level, permission mode) at the plugin's installation scope. Explicit opt-in: installing the plugin changes nothing until the user runs /settings:setup."
disable-model-invocation: true
---

# Settings Setup

<!--
Contract: B02 settings
Behavior:   Writes two env vars into the `env` object AND three session-default
             keys into the Claude Code settings file matching the plugin's
             installation scope:
               env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
               env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1"
               model = <user-provided value>
               effortLevel = <user-provided value>
               permissions.defaultMode = <user-provided value>
             The user MUST provide the values for model, effortLevel, and
             permissions.defaultMode interactively; there are no defaults or
             fallbacks.
             `/settings:setup remove` reverses the change (deletes all five
             keys/paths).
Inputs:      Subcommand (none = install, "remove" = uninstall). No other args.
             For install: the user is prompted for three values (model,
             effortLevel, permissions.defaultMode) during execution.
Outputs:     A confirmation message stating what was written, to which file, and
             at which scope. On remove: confirmation of what was deleted.
Errors:
  - Plugin not found in installed_plugins.json → report and stop; do not guess.
  - Target settings file missing → treat as `{}` and create it.
  - Target settings file is not valid JSON → report and stop; do not corrupt.
  - `jq` not available → report and stop.
  - Either env var already set to a different value → show current values,
    ask before overwriting.
  - Any of model, effortLevel, or permissions.defaultMode already set to a
    different value → show the current value, ask before overwriting.
  - On remove: all five keys/paths absent → report "nothing to remove", succeed.
Invariants:
  - Never touches settings keys other than `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`,
    `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, `model`, `effortLevel`, and
    `permissions.defaultMode`.
  - Always backs up the target file before writing (`<file>.bak-<date>`).
  - Merge semantics: read → patch keys → write. Never full-overwrite.
  - All five keys/paths are written atomically (one jq pass), never partially.
  - Env var values are always the string `"1"`, never a number or boolean.
  - The user provides model, effortLevel, and permissions.defaultMode values;
    the skill never assumes or falls back to a default.
Edge cases:
  - Plugin installed at multiple scopes → present the list, ask which to
    configure; do not default silently.
  - Target file does not exist yet → create with the `env` object and the
    three session-default keys.
  - Target file is empty (0 bytes) → treat as `{}`.
  - `env` key exists but is not an object → report and stop; do not corrupt.
  - `permissions` key exists but is not an object → report and stop; do not
    corrupt.
  - settings.json vs settings.local.json: scope "project" targets
    `.claude/settings.json`; scope "local" targets `.claude/settings.local.json`;
    scope "user" targets `~/.claude/settings.json`.
  - Mid-session /model, /effort, or /plan commands change in-memory session
    state only; they do not alter the persisted defaults in settings.json.
-->

This skill writes (or removes) two env vars —
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` and
`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, both set to the string `"1"` — plus
three session-default keys — `model`, `effortLevel`, and
`permissions.defaultMode` — into the Claude Code settings file that matches
however this plugin was installed. Installing the plugin changes nothing by
itself; only running this skill writes anything.

## `/settings:setup`

1. **Detect the installation scope.** Read
   `~/.claude/plugins/installed_plugins.json` and find every entry for
   `settings@clam`.
   - If the plugin is not present at all, report that it was not found in
     `installed_plugins.json` and stop — do not guess a scope.
   - If there is exactly one installation entry, use its `scope` field
     (`user`, `project`, or `local`).
   - If there are multiple installation entries, present the list (scope and
     project path for each) and ask the user which scope to configure. Do
     not default silently.
2. **Map scope to a target settings file.**
   - `user` → `~/.claude/settings.json`
   - `project` → `<projectPath>/.claude/settings.json`, where `projectPath`
     comes from the matching installation entry; if that field is absent,
     fall back to the current git repo root.
   - `local` → `<projectPath>/.claude/settings.local.json`, same
     `projectPath` resolution as above.
3. **Prompt for session defaults.** Ask the user for the three
   session-default values. The user MUST provide each value; there are no
   defaults or fallbacks. Do not proceed until all three are provided:
   - `model` — the Claude model to use by default (e.g. `claude-sonnet-5`,
     `opus`, `sonnet`)
   - `effortLevel` — the reasoning effort level (`low`, `medium`, `high`,
     `xhigh`)
   - `permissions.defaultMode` — the default permission mode (e.g.
     `acceptEdits`, `plan`, `bypassPermissions`, `default`)
4. **Show the change before making it.** Read the target settings file,
   treating a missing file as `{}` and an empty (0-byte) file as `{}`.
   - If the file exists but is not valid JSON, report that and stop —
     never write on top of a file you can't parse.
   - If the `env` key exists but is not a JSON object, report that and stop
     — do not corrupt it.
   - If the `permissions` key exists but is not a JSON object, report that
     and stop — do not corrupt it.
   - Report the current values of all five keys (the two env vars and the
     three session defaults), if any, and the values about to be written:

     ```json
     {
       "env": {
         "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
         "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING": "1"
       },
       "model": "<user-provided>",
       "effortLevel": "<user-provided>",
       "permissions": {
         "defaultMode": "<user-provided>"
       }
     }
     ```

   - If any of the five keys is already set to a different value, ask the
     user to confirm before overwriting it.
5. **Merge, don't overwrite.** Back up the target file first, as
   `<file>.bak-<date>` (e.g. `settings.json.bak-2026-07-21`). Then patch all
   five keys with jq, preserving every other setting and every other `env`
   and `permissions` entry, in a single atomic jq pass:

   ```bash
   jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
     | .env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1"
     | .model = "<user-provided>"
     | .effortLevel = "<user-provided>"
     | .permissions.defaultMode = "<user-provided>"' <target> > <tmpfile> \
     && mv <tmpfile> <target>
   ```

   If `jq` is not available, report that and stop before touching the file.
   All five keys are written in the one jq pass above — never partially.
   Env var values are always the string `"1"`, never a number or boolean.
6. **Verify.** Run `jq empty <target>` to confirm the result is still valid
   JSON. Then tell the user exactly what was written, to which settings
   file, and at which scope (user, project, or local).

## `/settings:setup remove`

Reverse the change, at the same scope-detection flow as above (steps 1-2):

1. Read the target settings file (missing or empty treated as `{}`; invalid
   JSON → report and stop; `env` present but not an object → report and
   stop; `permissions` present but not an object → report and stop).
2. If all five keys/paths (`env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`,
   `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, `model`, `effortLevel`,
   `permissions.defaultMode`) are absent, report "nothing to remove" and
   stop — this is a success, not an error.
3. Otherwise, back up the target file first (`<file>.bak-<date>`), then
   delete all five keys/paths with jq:

   ```bash
   jq 'del(.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS,
           .env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING,
           .model,
           .effortLevel,
           .permissions.defaultMode)' \
     <target> > <tmpfile> && mv <tmpfile> <target>
   ```
4. Verify with `jq empty <target>`, then report what was removed, from
   which settings file, and at which scope.

## Notes

- Never touch settings keys other than the five managed keys:
  `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`,
  `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, `model`, `effortLevel`, and
  `permissions.defaultMode` — this is a merge operation, not a file
  replacement.
- The three settings files by scope: `user` → `~/.claude/settings.json`;
  `project` → `.claude/settings.json` under the project path; `local` →
  `.claude/settings.local.json` under the project path.
- All writes go through a temp file and `mv`, after a `.bak-<date>` backup,
  so a failed or interrupted run never leaves the target file corrupted.
- Mid-session changes via `/model`, `/effort`, or `/plan` change in-memory
  session state only. They do not write back to settings.json, so the
  persisted defaults are unaffected.
