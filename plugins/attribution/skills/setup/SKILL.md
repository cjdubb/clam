---
name: setup
description: "Write or remove the attribution suppression setting at the plugin's installation scope. Explicit opt-in: installing the plugin changes nothing until the user runs /attribution:setup."
disable-model-invocation: true
---

# Attribution Setup

<!--
Contract: B05 setup-version-stamp — attribution (plan 001-update-flow-for-users)
Behavior (extension, to be added): after a successful install write (the
  verify step passes), record a setup stamp
  {plugin: "attribution", version, scope, target, at} in the stamp file per
  plugins/updates/docs/setup-stamps.md; on `/attribution:setup remove`,
  delete this plugin's stamp for the same target.
Inputs: version is read from the plugin.json at this installation's
  installPath (from its installed_plugins.json entry) — never from the
  entry's version field. target = the settings file written; scope = the
  configured scope.
Outputs: stamp record created/replaced (keyed plugin+target); the final
  confirmation message also names the stamp that was written.
Errors: a stamp write failure is reported but never fails the setup; a
  corrupt stamp file is moved aside (.corrupt-<date>) and recreated, per
  the format doc.
Invariants: setup behaves identically whether or not the updates plugin is
  installed; stamp writes are temp-file + mv; no stamp records other than
  this plugin+target are touched.
Edge cases: absent stamp file → created; remove with no stamp → silent
  success (stamp-wise). Plugin version bumps 0.1.0 → 0.2.0 with this change.
-->

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

## Notes

- Never touch settings keys other than `attribution` — this is a merge
  operation, not a file replacement.
- The three settings files by scope: `user` → `~/.claude/settings.json`;
  `project` → `.claude/settings.json` under the project path; `local` →
  `.claude/settings.local.json` under the project path.
- All writes go through a temp file and `mv`, after a `.bak-<date>` backup,
  so a failed or interrupted run never leaves the target file corrupted.
