# management

Claude Code has no built-in way to install or update clam plugins in bulk:
getting a set of them into a repo is one CLI command per plugin, staleness
afterward is silent until you go looking for it, and even after an update
lands, the setup skill that configured the old version never re-runs on its
own — so its written configuration quietly falls behind. This plugin gives
you two commands. `/management:install` shows you what the marketplace has
that you don't, in themed multi-select pages, and installs the set you pick
at one scope. `/management:update` reports every installed plugin's version
against the marketplace, applies updates you confirm, and tells you which
setup skills are worth re-running afterward.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install management@clam
```

Installing changes nothing — the plugin is inert until you explicitly run
`/management:install` or `/management:update`. No other configuration or
prerequisites.

## What to expect

- **On install:** nothing changes. No hooks fire, no background process
  starts, and no files are written — the plugin has no effect until you run
  one of its skills.
- **When `/management:install` is invoked:** it refreshes the marketplace
  clone (`claude plugin marketplace update clam`), reads that clone's
  catalog and `~/.claude/plugins/installed_plugins.json` to work out what
  you don't have yet, asks you which of those to install and at which
  scope, and then runs `claude plugin install <plugin>@clam --scope
  <scope>` for each one you picked.
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

### Install a batch of plugins

Run `/management:install`. It refreshes the catalog, drops everything you
already have, and offers the rest as themed multi-select pages of 2-4
plugins each — pick across as many pages as you like. It then asks once
which scope to install at (`local` is the recommendation: this repo only,
private to your machine), installs each pick, and reports the lot. One
failure doesn't stop the batch; you get the full list of what failed at the
end. It finishes by naming any setup skills the new plugins ship, and
whether a `/reload-plugins` or a full session restart is needed.

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

**`/management:install`** — not model-invocable
(`disable-model-invocation: true`); always run explicitly by name.

Refreshes the catalog, subtracts what's already installed, and offers the
remainder as multi-select pages grouped by each catalog entry's `category`.
Asks once for the install scope (`local`, `user`, or `project` — `local` is
the recommendation, and the scope is always asked, never assumed), then
installs each selection with `claude plugin install <plugin>@clam --scope
<scope>`, continuing past any individual failure and reporting them all at
the end. Selecting nothing is a no-op. Setup skills belonging to the newly
installed plugins are offered, never run. Where the multi-select picker
isn't available, the same pages are presented as numbered plain-text lists.

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

Prints a TSV (`plugin  installed  latest  update  stamp  setup
stale_targets  scope  stale_installs`) to stdout, one row per marketplace
plugin.

The report describes **the repo you run it in**. Claude Code's install
records are machine-wide — one record per project path, across every repo
on the machine — so entries belonging to other repositories are excluded
from every column. Without that filter a sibling repo's record, usually
the newest on the machine, decided the `installed` value and a plugin
several versions behind here read as `current`. An entry counts when it
has no project path (a user-scope install applies everywhere), when its
project path resolves to the same git common dir as your working
directory (so sibling worktrees of one repo count as one repo), or when
its project path is gone but sat inside this repo's container directory.
Run outside a git repo, there is nothing to attribute against and the
report stays machine-wide.

`installed` is the **lowest** version among this repo's records, so a repo
whose worktrees disagree stays `stale` until every one of them is updated
— one behind record is enough to mean there is work to do. `stamp` reports
the lowest — i.e. driving — version among that plugin's stamps, the one
setting its `setup` status; `stale_targets` names the absolute path of
each stamp target that is behind, or `-` when the row isn't stale. `scope`
carries the distinct scopes of the plugin's installation entries (not one
per entry), `;`-joined, and `-` when the plugin isn't installed; it's what
lets the update flow pass `-s <scope>` to `claude plugin update` rather
than take the CLI's own `user` default, which fails outright for a
local-scope install. `stale_installs` names the project paths whose
records are still behind `latest`, `;`-joined, or `-` when the row needs
no update — which is what keeps a row that stays stale after a successful
update diagnosable, since `claude plugin update` resolves one record per
run and offers no per-project target.

Setup stamps are **not** repo-filtered: the `stamp`, `setup` and
`stale_targets` columns still consider every stamp for the plugin, so a
stale target in another repo can appear. A stamp records a target settings
file rather than a project root, so attributing one to a repo is a
different problem, left to its own change.

Exit `0` when nothing is stale, `10`
when at least one plugin is; `2`/`3`/`4` on missing or malformed
installed-plugin data, a missing marketplace clone, and a missing `jq`,
respectively (see the script's own header for the full contract). Honors
`CLAUDE_CONFIG_DIR` (default `~/.claude`) and `CLAM_MARKETPLACE` (default
`clam`) for testing against fixtures.

The `setup` column reflects setup version stamps — see
[`docs/setup-stamps.md`](docs/setup-stamps.md) for the stamp file's format
and semantics.

**`scripts/prune-stamp.sh <plugin> <target>`** — deletes one setup-stamp
record: the one for `<plugin>` at `<target>`, an engineer-named pair taken
from a `stale_targets` value in the version report above.

```
bash plugins/management/scripts/prune-stamp.sh privacy /home/user/.claude/settings.json
```

The update skill offers this exact command for each stale target and
never runs it itself — the engineer decides whether and when to run it.
Deletes at most the one record named; no matching record is a silent
no-op (exit `0`). Exit `2` on a wrong argument count or an empty
argument, `3` when the stamp file doesn't exist, `4` when `jq` is
missing, `5` when the stamp file is present but not valid JSON, `6` on a
write failure (see the script's own header for the full contract).
Honors `CLAUDE_CONFIG_DIR` (default `~/.claude`) for testing against
fixtures.

## Tests

```bash
bash plugins/management/scripts/manifest.test.sh
bash plugins/management/scripts/check-versions.test.sh
bash plugins/management/scripts/prune-stamp.test.sh
```

## Update

```
/plugin marketplace update clam
claude plugin update management@clam
```

Both commands are needed: refreshing the catalog never touches an installed
plugin, and updating one is CLI-only — there is no `/plugin update`.
Afterwards run `/reload-plugins` to pick the new version up in the current
session, or restart the session if this plugin ships hooks or agents.

Auto-update is off by default for third-party marketplaces. Even with it
enabled, a plugin that ships hooks stays pinned to the last explicitly
installed version until you run the update command yourself
(anthropics/claude-code#52218).

## Relationships to other plugins

Soft integrations only: this plugin reads the setup version stamps written
by five plugins' setup skills — `attribution`, `privacy`, `settings`,
`statusline`, and `landing` — to know when their setup is worth re-running
after an update. None of them need to be installed; with fewer of them
present, `/management:update` simply has fewer setup-stamp rows to report
on and degrades gracefully. `/management:install` takes a different posture:
it hardcodes no plugin list at all. Which setup skills it offers is worked
out as it runs, from the skill frontmatter of whatever plugins that
invocation just installed. Nothing in clam depends on this plugin.

## Uninstalling

```
/plugin uninstall management@clam
```

`~/.claude/clam-setup-stamps.json` is not removed by uninstalling. That's
harmless: the file only ever informs `/management:update`'s own setup-re-run
report, nothing else reads it, and reinstalling the plugin later picks the
existing stamps back up rather than needing them recreated.
