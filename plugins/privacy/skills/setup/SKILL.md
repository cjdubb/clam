---
name: setup
description: "Write or remove telemetry and feedback opt-out settings at the plugin's installation scope. Explicit opt-in: installing the plugin changes nothing until the user runs /privacy:setup."
disable-model-invocation: true
---

# Privacy Setup

This skill writes (or removes) five env vars —
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_TELEMETRY`,
`DISABLE_ERROR_REPORTING`, `DISABLE_FEEDBACK_COMMAND`, and
`CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` (each set to the string `"1"`), plus
one top-level setting — `feedbackSurveyRate` set to the number `0` — into
the Claude Code settings file that matches however this plugin was
installed. Installing the plugin changes nothing by itself; only running
this skill writes anything.

## `/privacy:setup`

1. **Detect the installation scope.** Read
   `~/.claude/plugins/installed_plugins.json` and find every entry for
   `privacy@clam`.
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
   - Report the current values, if any, of the six managed settings —
     `env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `env.DISABLE_TELEMETRY`,
     `env.DISABLE_ERROR_REPORTING`, `env.DISABLE_FEEDBACK_COMMAND`,
     `env.CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY`, and the top-level
     `feedbackSurveyRate` — and the values about to be written:

     ```json
     {
       "env": {
         "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
         "DISABLE_TELEMETRY": "1",
         "DISABLE_ERROR_REPORTING": "1",
         "DISABLE_FEEDBACK_COMMAND": "1",
         "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1"
       },
       "feedbackSurveyRate": 0
     }
     ```

   - If any of the six managed keys is already set to a different value,
     ask the user to confirm before overwriting it.
4. **Merge, don't overwrite.** Back up the target file first, as
   `<file>.bak-<date>` (e.g. `settings.json.bak-2026-07-21`). Then patch only
   the six managed keys with jq, preserving every other setting and every
   other `env` entry, in a single atomic jq pass:

   ```bash
   jq '.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
     | .env.DISABLE_TELEMETRY = "1"
     | .env.DISABLE_ERROR_REPORTING = "1"
     | .env.DISABLE_FEEDBACK_COMMAND = "1"
     | .env.CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1"
     | .feedbackSurveyRate = 0' <target> > <tmpfile> \
     && mv <tmpfile> <target>
   ```

   If `jq` is not available, report that and stop before touching the file.
   All six settings are written in the one jq pass above — never partially.
   The five env vars are always the string `"1"`, never a number or
   boolean; `feedbackSurveyRate` is always the number `0`, never a string.
5. **Verify.** Run `jq empty <target>` to confirm the result is still valid
   JSON. Then compare the set of top-level keys in the written file against
   the set that was present before the write (captured in step 3). If any
   pre-existing key is missing from the result — `enabledPlugins` is the
   most likely victim, but check all keys — the merge was not a merge:
   restore the backup file (`mv <backup> <target>`), report which keys were
   lost, and stop. A correct jq merge never drops keys it does not name.
   Once the key-preservation check passes, tell the user exactly what was
   written, to which settings file, and at which scope (user, project, or
   local).
6. **Record the setup stamp.** After the verify step succeeds, record this
   setup in the shared stamp file so the update flow can tell this plugin's
   setup is current with the installed version:
   `${CLAUDE_CONFIG_DIR:-~/.claude}/clam-setup-stamps.json` — format defined
   in `docs/protocols/setup-stamp.md`.
   - Read the plugin's version from the `plugin.json` at this
     installation's `installPath` (from its `installed_plugins.json`
     entry) — never from the entry's own `version` field, which can go
     stale.
   - If the stamp file does not exist yet, create it first as
     `{"version": 1, "stamps": []}`.
   - If the existing stamp file is corrupt (not valid JSON), move it aside
     to `clam-setup-stamps.json.corrupt-<date>`, report the move to the
     user, and recreate it fresh.
   - Set `at` to the current UTC time by running
     `date -u +%Y-%m-%dT%H:%M:%SZ` — never invented, guessed, or copied
     from another record.
   - Replace this plugin's record, keyed by `plugin` and `target`; touch
     no other records. Write via jq to a temp file, then `mv` it into
     place — the same atomic pattern as the settings write above:

     ```json
     {
       "plugin": "privacy",
       "version": "<from plugin.json>",
       "scope": "<user | project | local>",
       "target": "<target settings file>",
       "at": "<output of date -u +%Y-%m-%dT%H:%M:%SZ>"
     }
     ```

   - If the stamp write fails, report the failure but never fail the
     setup — the settings write above already succeeded.

## `/privacy:setup remove`

Reverse the change, at the same scope-detection flow as above (steps 1-2):

1. Read the target settings file (missing or empty treated as `{}`; invalid
   JSON → report and stop; `env` present but not an object → report and
   stop).
2. If all six managed keys — the five env vars and top-level
   `feedbackSurveyRate` — are absent, report "nothing to remove" and stop —
   this is a success, not an error.
3. Otherwise, back up the target file first (`<file>.bak-<date>`), then
   delete all six managed keys with jq:

   ```bash
   jq 'del(.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC,
           .env.DISABLE_TELEMETRY,
           .env.DISABLE_ERROR_REPORTING,
           .env.DISABLE_FEEDBACK_COMMAND,
           .env.CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY,
           .feedbackSurveyRate)' \
     <target> > <tmpfile> && mv <tmpfile> <target>
   ```

4. Verify with `jq empty <target>`, then report what was removed, from
   which settings file, and at which scope.
5. Delete this plugin's stamp for the same target from the shared stamp
   file (`docs/protocols/setup-stamp.md`); if there is no stamp for this
   target, that's already fine — nothing to do.

## Notes

- Never touch settings keys other than the five env vars under `env` and
  the top-level `feedbackSurveyRate` — this is a merge operation, not a
  file replacement.
- The three settings files by scope: `user` → `~/.claude/settings.json`;
  `project` → `.claude/settings.json` under the project path; `local` →
  `.claude/settings.local.json` under the project path.
- All writes go through a temp file and `mv`, after a `.bak-<date>` backup,
  so a failed or interrupted run never leaves the target file corrupted.
