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

This skill writes (or removes) two env vars —
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` and
`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, both set to the string `"1"` — into
the `env` object of the Claude Code settings file that matches however this
plugin was installed. Installing the plugin changes nothing by itself; only
running this skill writes anything.

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
3. **Show the change before making it.** Read the target settings file,
   treating a missing file as `{}` and an empty (0-byte) file as `{}`.
   - If the file exists but is not valid JSON, report that and stop —
     never write on top of a file you can't parse.
   - If the `env` key exists but is not a JSON object, report that and stop
     — do not corrupt it.
   - Report the current `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` and
     `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` values, if any, and the
     values about to be written:

     ```json
     {
       "env": {
         "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
         "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING": "1"
       }
     }
     ```

   - If either env var is already set to a different value, ask the user to
     confirm before overwriting it.
4. **Merge, don't overwrite.** Back up the target file first, as
   `<file>.bak-<date>` (e.g. `settings.json.bak-2026-07-21`). Then patch only
   the two env keys with jq, preserving every other setting and every other
   `env` entry, in a single atomic jq pass:

   ```bash
   jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
     | .env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1"' <target> > <tmpfile> \
     && mv <tmpfile> <target>
   ```

   If `jq` is not available, report that and stop before touching the file.
   Both vars are written in the one jq pass above — never partially, and
   always as the string `"1"`, never a number or boolean.
5. **Verify.** Run `jq empty <target>` to confirm the result is still valid
   JSON. Then tell the user exactly what was written, to which settings
   file, and at which scope (user, project, or local).

## `/settings:setup remove`

Reverse the change, at the same scope-detection flow as above (steps 1-2):

1. Read the target settings file (missing or empty treated as `{}`; invalid
   JSON → report and stop; `env` present but not an object → report and
   stop).
2. If both `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` and
   `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` are absent, report "nothing
   to remove" and stop — this is a success, not an error.
3. Otherwise, back up the target file first (`<file>.bak-<date>`), then
   delete only those two env keys with jq:

   ```bash
   jq 'del(.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS, .env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING)' \
     <target> > <tmpfile> && mv <tmpfile> <target>
   ```

4. Verify with `jq empty <target>`, then report what was removed, from
   which settings file, and at which scope.

## Notes

- Never touch settings keys other than
  `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` and
  `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` — this is a merge operation on
  the `env` object, not a file replacement.
- The three settings files by scope: `user` → `~/.claude/settings.json`;
  `project` → `.claude/settings.json` under the project path; `local` →
  `.claude/settings.local.json` under the project path.
- All writes go through a temp file and `mv`, after a `.bak-<date>` backup,
  so a failed or interrupted run never leaves the target file corrupted.
