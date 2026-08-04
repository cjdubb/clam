---
name: setup
description: "Write or remove session defaults (env vars, model, effort level, permission mode) at the plugin's installation scope. Explicit opt-in: installing the plugin changes nothing until the user runs /settings:setup."
disable-model-invocation: true
---

# Settings Setup

This skill writes (or removes) two hardcoded env vars —
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` and
`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, both set to the string `"1"` — plus
an optional, user-prompted env var, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, and
three session-default keys — `model`, `effortLevel`, and
`permissions.defaultMode` — into the Claude Code settings file that matches
however this plugin was installed. `CLAUDE_CODE_AUTO_COMPACT_WINDOW` bounds
auto-compaction so a session's context cannot run away on 1M-native models:
the harness compacts at approximately the configured window minus a 20%
buffer. The user is prompted for it during setup and may decline; if
declined, the key is not written. Installing the plugin changes nothing by
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
3. **Prompt for `CLAUDE_CODE_AUTO_COMPACT_WINDOW`.** Ask the user whether
   they want to set an auto-compact window. This env var bounds
   auto-compaction so a session's context cannot run away on 1M-native
   models; the harness compacts at approximately the window minus a ~20%
   buffer, so e.g. `250000` triggers compaction around 200K tokens. This
   value is optional: the user may provide it or decline.
   - If the user provides a value, it must be a string of digits (e.g.
     `"250000"`). If the value is not a string of digits, report the
     invalid value and re-prompt.
   - If the user declines, do not write `CLAUDE_CODE_AUTO_COMPACT_WINDOW` —
     proceed without it.
4. **Prompt for session defaults.** Ask the user for the three
   session-default values. The user MUST provide each value; there are no
   defaults or fallbacks. Do not proceed until all three are provided:
   - `model` — the Claude model to use by default (e.g. `claude-sonnet-5`,
     `opus`, `sonnet`)
   - `effortLevel` — the reasoning effort level (`low`, `medium`, `high`,
     `xhigh`)
   - `permissions.defaultMode` — the default permission mode (e.g.
     `acceptEdits`, `plan`, `bypassPermissions`, `default`)
5. **Show the change before making it.** Read the target settings file,
   treating a missing file as `{}` and an empty (0-byte) file as `{}`.
   - If the file exists but is not valid JSON, report that and stop —
     never write on top of a file you can't parse.
   - If the `env` key exists but is not a JSON object, report that and stop
     — do not corrupt it.
   - If the `permissions` key exists but is not a JSON object, report that
     and stop — do not corrupt it.
   - Report the current values of all five keys (the two env vars and the
     three session defaults) — plus `CLAUDE_CODE_AUTO_COMPACT_WINDOW` if the
     user accepted a value for it — if any, and the values about to be
     written. Include the `CLAUDE_CODE_AUTO_COMPACT_WINDOW` line in the `env`
     object below only when the user accepted a value; omit it entirely when
     declined:

     ```json
     {
       "env": {
         "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
         "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING": "1",
         "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "<user-provided, only if accepted>"
       },
       "model": "<user-provided>",
       "effortLevel": "<user-provided>",
       "permissions": {
         "defaultMode": "<user-provided>"
       }
     }
     ```

   - If any of the five keys — or `CLAUDE_CODE_AUTO_COMPACT_WINDOW` when the
     user accepted it, making six — is already set to a different value, ask
     the user to confirm before overwriting it.
6. **Merge, don't overwrite.** Back up the target file first, as
   `<file>.bak-<date>` (e.g. `settings.json.bak-2026-07-21`). Then patch the
   accepted keys with jq, preserving every other setting and every other
   `env` and `permissions` entry, in a single atomic jq pass. Include the
   `.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW` assignment below only when the
   user accepted a value for it; omit that line entirely when declined:

   ```bash
   jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
     | .env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1"
     | .env.CLAUDE_CODE_AUTO_COMPACT_WINDOW = "<user-provided>"
     | .model = "<user-provided>"
     | .effortLevel = "<user-provided>"
     | .permissions.defaultMode = "<user-provided>"' <target> > <tmpfile> \
     && mv <tmpfile> <target>
   ```

   If `jq` is not available, report that and stop before touching the file.
   All accepted keys/paths — five, or six when `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
   was accepted — are written atomically in the one jq pass above — never
   partially. `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` and
   `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` values are always the string
   `"1"`, never a number or boolean; `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, when
   accepted, is always a string of digits provided by the user.
7. **Verify.** Run `jq empty <target>` to confirm the result is still valid
   JSON. Then tell the user exactly what was written, to which settings
   file, and at which scope (user, project, or local).
8. **Record the setup stamp.** After the verify step succeeds, record this
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
       "plugin": "settings",
       "version": "<from plugin.json>",
       "scope": "<user | project | local>",
       "target": "<target settings file>",
       "at": "<ISO-8601 UTC timestamp>"
     }
     ```

   - If the stamp write fails, report the failure but never fail the
     setup — the settings write above already succeeded. A declined
     optional value (e.g. `CLAUDE_CODE_AUTO_COMPACT_WINDOW`) still counts
     as a successful setup and is stamped.

## `/settings:setup remove`

Reverse the change, at the same scope-detection flow as above (steps 1-2):

1. Read the target settings file (missing or empty treated as `{}`; invalid
   JSON → report and stop; `env` present but not an object → report and
   stop; `permissions` present but not an object → report and stop).
2. If all six managed keys/paths (`env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`,
   `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`,
   `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `model`, `effortLevel`,
   `permissions.defaultMode`) are absent, report "nothing to remove" and
   stop — this is a success, not an error. `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW`
   is included in this check and in the delete below even if it was never
   set: deleting an absent key is a no-op in jq.
3. Otherwise, back up the target file first (`<file>.bak-<date>`), then
   delete all six keys/paths with jq:

   ```bash
   jq 'del(.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS,
           .env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING,
           .env.CLAUDE_CODE_AUTO_COMPACT_WINDOW,
           .model,
           .effortLevel,
           .permissions.defaultMode)' \
     <target> > <tmpfile> && mv <tmpfile> <target>
   ```
4. Verify with `jq empty <target>`, then report what was removed, from
   which settings file, and at which scope.
5. Delete this plugin's stamp for the same target from the shared stamp
   file (`docs/protocols/setup-stamp.md`); if there is no stamp for this
   target, that's already fine — nothing to do.

## Notes

- Never touch settings keys other than the six managed keys:
  `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`,
  `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`,
  `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW` (optional), `model`, `effortLevel`,
  and `permissions.defaultMode` — this is a merge operation, not a file
  replacement.
- The three settings files by scope: `user` → `~/.claude/settings.json`;
  `project` → `.claude/settings.json` under the project path; `local` →
  `.claude/settings.local.json` under the project path.
- All writes go through a temp file and `mv`, after a `.bak-<date>` backup,
  so a failed or interrupted run never leaves the target file corrupted.
- Mid-session changes via `/model`, `/effort`, or `/plan` change in-memory
  session state only. They do not write back to settings.json, so the
  persisted defaults are unaffected.
