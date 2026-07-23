# attribution

Suppress Claude Code's co-author attribution on commits and pull requests.
Installing the plugin changes nothing; running `/attribution:setup` writes
an `attribution` key to whichever settings file matches the plugin's
installation scope, so Claude Code stops adding the co-author line to
commits and the attribution block to PRs. `/attribution:setup remove`
reverses it.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install attribution@clam
```

Installing changes nothing — the plugin is inert until you run
`/attribution:setup`. No other configuration or prerequisites.

## What to expect

- **On install:** nothing changes. This is an explicit opt-in — Claude Code
  keeps adding the co-author line and the attribution block until you run
  the setup command yourself.
- **After `/attribution:setup`:** the settings file matching wherever the
  plugin is installed gains an `attribution` key set to
  `{"commit":"","pr":""}`. From then on, commits stop carrying the Claude
  Code co-author line and PRs stop carrying the attribution block.
- **After `/attribution:setup remove`:** the `attribution` key is deleted
  and both attributions resume.
- No hooks, no background processes, no files created — the entire effect
  is that one settings key.

## Common workflows

### Suppress attribution

Run `/attribution:setup`. It detects where the plugin is installed by
reading `~/.claude/plugins/installed_plugins.json` (asking you to pick a
scope if it's installed in more than one place), shows you the current and
about-to-be-written `attribution` value, backs up the target settings file,
and merges the key in with `jq` — every other setting in the file is left
untouched.

### Restore attribution

Run `/attribution:setup remove`. Same scope detection as above; if
`attribution` isn't set, it reports "nothing to remove" and stops (this
counts as success, not an error). Otherwise it backs up the settings file
and deletes just the `attribution` key.

## Commands

### Skills

**`/attribution:setup`** — not model-invocable
(`disable-model-invocation: true`); always run explicitly by name.

1. Detects the installation scope from
   `~/.claude/plugins/installed_plugins.json`; stops and reports if the
   plugin isn't listed there, and asks you to pick a scope when it's
   installed at more than one.
2. Maps scope to a target file: `user` → `~/.claude/settings.json`,
   `project` → `.claude/settings.json` under the installing project,
   `local` → `.claude/settings.local.json` under the installing project.
3. Reads the target file (a missing or empty file is treated as `{}`;
   invalid JSON stops the run rather than writing on top of it) and shows
   the current and pending `attribution` value. If `attribution` is
   already set to something else, asks for confirmation before
   overwriting it.
4. Backs up the target file as `<file>.bak-<date>`, then patches only the
   `attribution` key with `jq` — a merge, never a full overwrite. Stops
   without writing if `jq` isn't available.
5. Verifies the result with `jq empty` and reports exactly what was
   written, to which file, and at which scope.

**`/attribution:setup remove`** — same scope-detection flow (steps 1-2
above). Backs up the target file, deletes the `attribution` key with
`jq 'del(.attribution)'`, and verifies with `jq empty`. If the key was
already absent, reports "nothing to remove" and succeeds without writing.

## Tests

```bash
bash plugins/attribution/scripts/structure.test.sh
```

## Relationships to other plugins

None required. This plugin is fully standalone.

## Uninstalling

```
/plugin uninstall attribution@clam
```

Run `/attribution:setup remove` first if you want the `attribution` key
reverted — uninstalling the plugin package does not touch settings files
it previously wrote to.
