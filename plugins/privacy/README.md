# privacy

Privacy opts your Claude Code sessions out of telemetry, error reporting,
feedback surveys, and non-essential network traffic. Installing the plugin
changes nothing by itself — running `/privacy:setup` writes the opt-out
settings to whichever settings file matches how the plugin is installed
(user, project, or local scope), and `/privacy:setup remove` undoes them.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install privacy@clam
```

No prerequisites for installing. `/privacy:setup` (the one skill this
plugin provides) needs `jq` on PATH to merge settings — install `jq` first
if it isn't already available. Installing the plugin changes nothing by
itself; run `/privacy:setup` afterward to actually write the opt-out
settings.

## What to expect

Installing changes nothing — the plugin is inert until you run
`/privacy:setup`. Once you run it:

- The settings file matching the plugin's installation scope
  (`~/.claude/settings.json` for `user`, `<project>/.claude/settings.json`
  for `project`, or `<project>/.claude/settings.local.json` for `local`)
  gets five env vars set to the string `"1"` —
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_TELEMETRY`,
  `DISABLE_ERROR_REPORTING`, `DISABLE_FEEDBACK_COMMAND`,
  `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` — plus a top-level
  `feedbackSurveyRate` set to the number `0`.
- The target file is backed up first, as `<file>.bak-<date>`, and every
  other key in the file (including other `env` entries) is preserved — the
  write is a merge, never a full overwrite.
- `/privacy:setup remove` deletes exactly those six keys and leaves
  everything else untouched.

No files are created or read other than the one settings file (and its
backup); no hooks fire and no background process runs.

## Common workflows

### Opt out of telemetry and feedback surveys

Run:

```
/privacy:setup
```

Claude detects the installation scope from
`~/.claude/plugins/installed_plugins.json` (asking you to pick if the
plugin is installed at more than one scope), shows the current and
about-to-be-written values for the six managed keys, backs up the target
settings file, and writes the five env vars plus `feedbackSurveyRate` in
one atomic `jq` pass. It reports which file was written and at which
scope.

### Undo the opt-out

Run:

```
/privacy:setup remove
```

Same scope detection, then it deletes the five env vars and
`feedbackSurveyRate` from the target file (backing it up first). If none
of the six keys are present, it reports "nothing to remove" and succeeds.

## Commands

### `/privacy:setup`

Not model-invocable (`disable-model-invocation: true` in the skill's
frontmatter) — it only runs when you type it.

1. Detects the installation scope by reading
   `~/.claude/plugins/installed_plugins.json` for `privacy@clam` entries.
   No entry → reports "not found" and stops. One entry → uses its scope.
   Multiple entries → lists them and asks which scope to configure.
2. Maps scope to a target file: `user` → `~/.claude/settings.json`;
   `project` → `<projectPath>/.claude/settings.json`; `local` →
   `<projectPath>/.claude/settings.local.json` (falling back to the
   current repo root if `projectPath` is absent).
3. Reads the target file (missing or 0-byte → treated as `{}`; invalid
   JSON, or an `env` key that isn't an object → reports and stops rather
   than risk corrupting it) and shows the current vs. about-to-be-written
   values for the six managed keys, asking for confirmation if any managed
   key already holds a different value.
4. Backs up the target file as `<file>.bak-<date>`, then patches all six
   keys in one atomic `jq` pass — never partially:

   ```bash
   jq '.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
     | .env.DISABLE_TELEMETRY = "1"
     | .env.DISABLE_ERROR_REPORTING = "1"
     | .env.DISABLE_FEEDBACK_COMMAND = "1"
     | .env.CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1"
     | .feedbackSurveyRate = 0' <target> > <tmpfile> \
     && mv <tmpfile> <target>
   ```

   Stops before touching the file if `jq` isn't on PATH.
5. Verifies the result with `jq empty <target>`, then reports exactly what
   was written, to which file, and at which scope.

### `/privacy:setup remove`

Same scope-detection flow (steps 1-2 above), then:

1. Reads the target file the same way.
2. If all six managed keys are already absent, reports "nothing to
   remove" and succeeds — this is not an error.
3. Otherwise backs up the target file first, then deletes all six keys
   with `jq del(...)`.
4. Verifies with `jq empty <target>` and reports what was removed, from
   which file, and at which scope.

| Setting | Value | Where |
|---------|-------|-------|
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `"1"` | `env` |
| `DISABLE_TELEMETRY` | `"1"` | `env` |
| `DISABLE_ERROR_REPORTING` | `"1"` | `env` |
| `DISABLE_FEEDBACK_COMMAND` | `"1"` | `env` |
| `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` | `"1"` | `env` |
| `feedbackSurveyRate` | `0` (number) | top-level |

None of these are meant to be hand-edited — `/privacy:setup` and
`/privacy:setup remove` are the only sanctioned way to write or remove
them.

## Tests

```bash
bash plugins/privacy/scripts/structure.test.sh
```

## Relationships to other plugins

None required. This plugin is fully standalone — no other plugin depends
on it, and it depends on none.

It shares the same scope-aware setup-skill pattern as the `attribution`
and `settings` plugins (detect installation scope, show the change, back
up, write managed keys via `jq`, offer a `remove` subcommand), but it
manages an entirely separate set of settings keys, so there's no overlap
or ordering dependency between them.

## Uninstalling

```
/plugin uninstall privacy@clam
```

Uninstalling the plugin does not touch settings files — if you ran
`/privacy:setup`, the five env vars and `feedbackSurveyRate` remain in
place after uninstall. Run `/privacy:setup remove` first if you want the
opt-out reversed. Backup files (`<file>.bak-<date>`) created by past
setup/remove runs are never cleaned up automatically and can be deleted by
hand once no longer needed.
