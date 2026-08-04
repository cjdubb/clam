---
name: setup
description: "Write or remove the attribution suppression setting at the plugin's installation scope. Explicit opt-in: installing the plugin changes nothing until the user runs /attribution:setup."
disable-model-invocation: true
---

# Attribution Setup

This skill writes (or removes) the `attribution` setting —
`{"commit":"","pr":""}` — in the Claude Code settings file that matches
however this plugin was installed. Installing the plugin changes nothing by
itself; only running this skill writes anything.

## `/attribution:setup`

1. **Detect the installation scope.** Read
   `~/.claude/plugins/installed_plugins.json` and find every entry for
   `attribution@clam`.
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
   - Report the current `attribution` value, if any, and the value about to
     be written:

     ```json
     {
       "attribution": {
         "commit": "",
         "pr": ""
       }
     }
     ```

   - If `attribution` is already set to a different value, ask the user to
     confirm before overwriting it.
4. **Merge, don't overwrite.** Back up the target file first, as
   `<file>.bak-<date>` (e.g. `settings.json.bak-2026-07-21`). Then patch only
   the `attribution` key with jq, preserving every other setting:

   ```bash
   jq '.attribution = {"commit":"","pr":""}' <target> > <tmpfile> \
     && mv <tmpfile> <target>
   ```

   If `jq` is not available, report that and stop before touching the file.
5. **Verify.** Run `jq empty <target>` to confirm the result is still valid
   JSON. Then tell the user exactly what was written, to which settings
   file, and at which scope (user, project, or local).
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
   - Replace this plugin's record, keyed by `plugin` and `target`; touch
     no other records. Write via jq to a temp file, then `mv` it into
     place — the same atomic pattern as the settings write above:

     ```json
     {
       "plugin": "attribution",
       "version": "<from plugin.json>",
       "scope": "<user | project | local>",
       "target": "<target settings file>",
       "at": "<ISO-8601 UTC timestamp>"
     }
     ```

   - If the stamp write fails, report the failure but never fail the
     setup — the settings write above already succeeded.

## `/attribution:setup remove`

Reverse the change, at the same scope-detection flow as above (steps 1-2):

1. Read the target settings file (missing or empty treated as `{}`; invalid
   JSON → report and stop).
2. If the `attribution` key is absent, report "nothing to remove" and stop
   — this is a success, not an error.
3. Otherwise, back up the target file first (`<file>.bak-<date>`), then
   delete only the `attribution` key with jq:

   ```bash
   jq 'del(.attribution)' <target> > <tmpfile> && mv <tmpfile> <target>
   ```

4. Verify with `jq empty <target>`, then report what was removed, from
   which settings file, and at which scope.
5. Delete this plugin's stamp for the same target from the shared stamp
   file (`docs/protocols/setup-stamp.md`); if there is no stamp for this
   target, that's already fine — nothing to do.

## Notes

- Never touch settings keys other than `attribution` — this is a merge
  operation, not a file replacement.
- The three settings files by scope: `user` → `~/.claude/settings.json`;
  `project` → `.claude/settings.json` under the project path; `local` →
  `.claude/settings.local.json` under the project path.
- All writes go through a temp file and `mv`, after a `.bak-<date>` backup,
  so a failed or interrupted run never leaves the target file corrupted.
