# management

Claude Code has no built-in way to update every installed clam plugin at
once: each plugin has to be checked and updated one at a time, staleness is
silent until you go looking for it, and even after an update lands, the
setup skill that configured the old version never re-runs on its own — so
its written configuration quietly falls behind. This plugin gives you one
command, `/management:update`, that reports every installed plugin's version
against the marketplace, applies updates you confirm, and tells you which
setup skills are worth re-running afterward.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install management@clam
```

Installing changes nothing — the plugin is inert until you explicitly run
`/management:update`. No other configuration or prerequisites.

## What to expect

- **On install:** nothing changes. No hooks fire, no background process
  starts, and no files are written — the plugin has no effect until you run
  its skill.
- **When `/management:update` is invoked:** it reads
  `~/.claude/plugins/installed_plugins.json` (what's installed),
  `~/.claude/plugins/marketplaces/clam/.claude-plugin/marketplace.json`
  plus each plugin's own `plugin.json` in that clone (what's latest), and
  `~/.claude/clam-setup-stamps.json` (which versions last had their setup
  run). It then runs `scripts/check-versions.sh` to build the version
  report, and — after your confirmation — the `claude plugin update
  <plugin>@clam` CLI commands for the plugins you approve.
- Outside of a `/management:update` invocation, the plugin reads and writes
  nothing.

## Common workflows

### Update everything

Run `/management:update`. It refreshes the marketplace catalog, shows a
table of installed vs. latest versions, and — if anything is stale — asks
once for confirmation covering the whole batch (you can reply with a
subset to update only those). It reports each update's result, then lists
which setup skills are worth re-running because their stamped version no
longer matches the plugin's new version.

### Check for updates without changing anything

Run `/management:update check`. This stops after the version report —
nothing is updated, and you aren't asked to confirm anything. Use it when
you just want to know what's stale.

### Re-run setup after an update

After `/management:update` updates a plugin, it names which setup skills (of
`/attribution:setup`, `/privacy:setup`, `/settings:setup`,
`/statusline:setup`, `/landing:init`) are stale for the new version and
offers the command to run — it never runs them for you.

## Commands

### Skills

**`/management:update [check]`** — not model-invocable
(`disable-model-invocation: true`); always run explicitly by name.

- With no argument: refreshes the catalog, reports current/stale/unstamped
  versions, asks one confirmation for the batch of stale plugins, applies
  the confirmed updates, and closes with setup re-run offers and
  reload/restart guidance.
- `/management:update check`: stops after the version report. Read-only —
  nothing is updated and no confirmation is asked.

### Scripts

**`scripts/check-versions.sh`** — read-only version report, no arguments.

```
bash plugins/management/scripts/check-versions.sh
```

Prints a TSV (`plugin  installed  latest  update  stamp  setup`) to stdout,
one row per marketplace plugin. Exit `0` when nothing is stale, `10` when
at least one plugin is; `2`/`3`/`4` on missing or malformed installed-plugin
data, a missing marketplace clone, and a missing `jq`, respectively (see
the script's own header for the full contract). Honors `CLAUDE_CONFIG_DIR`
(default `~/.claude`) and `CLAM_MARKETPLACE` (default `clam`) for testing
against fixtures.

The `setup` column reflects setup version stamps — see
[`docs/setup-stamps.md`](docs/setup-stamps.md) for the stamp file's format
and semantics.

## Tests

```bash
bash plugins/management/scripts/manifest.test.sh
bash plugins/management/scripts/check-versions.test.sh
```

## Relationships to other plugins

Soft integrations only: this plugin reads the setup version stamps written
by five plugins' setup skills — `attribution`, `privacy`, `settings`,
`statusline`, and `landing` — to know when their setup is worth re-running
after an update. None of them need to be installed; with fewer of them
present, `/management:update` simply has fewer setup-stamp rows to report
on and degrades gracefully. Nothing in clam depends on this plugin.

## Uninstalling

```
/plugin uninstall management@clam
```

`~/.claude/clam-setup-stamps.json` is not removed by uninstalling. That's
harmless: the file only ever informs `/management:update`'s own setup-re-run
report, nothing else reads it, and reinstalling the plugin later picks the
existing stamps back up rather than needing them recreated.
