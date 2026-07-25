# updates

<!--
Contract: B03 updates-plugin-manifest (plan 001-update-flow-for-users)
Behavior: declarative block — the plugin manifest and this README.
Outputs:
- .claude-plugin/plugin.json: name "updates", version "0.1.0", a
  one-sentence description naming /updates:run, and an author object
  byte-identical (jq -Sc) to .claude-plugin/marketplace.json's owner.
  Stays jq-valid. (Lands at scaffold for marketplace-lint parity; content
  is contractual.)
- This README filled per the locked template (plugins/PLUGIN_README_TEMPLATE.md):
  intro paragraph stating the problem (no bulk update, silent staleness,
  setups never re-run); Getting started (install commands; no configuration
  required — inert until /updates:run); What to expect (no hooks, nothing
  changes at install; what the skill reads and runs when invoked); Common
  workflows (update everything; check-only report); Commands (/updates:run
  incl. "check" mode and non-model-invocability, scripts/check-versions.sh
  CLI usage, pointer to docs/setup-stamps.md; optional ## Tests section
  listing check-versions.test.sh and sibling tests); Relationships (soft:
  reads stamps written by attribution/privacy/settings/statusline/landing
  setup skills, degrades gracefully without them; nothing depends on this
  plugin); Uninstalling (uninstall command; note the stamp file
  ~/.claude/clam-setup-stamps.json is not removed and why that is harmless).
Invariants: readme-lint PASS (6 required H2s, exact order; extra sections
  only between Commands and Relationships); no hooks/ directory in the
  plugin; the skill stays disable-model-invocation.
Errors: n/a — declarative; validity enforced by readme-lint and the unit's
  structure tests.
Edge cases: template comments removed in the filled version; code blocks
  must not trigger readme-lint's fence handling edge cases.
-->

Claude Code has no built-in way to update every installed clam plugin at
once: each plugin has to be checked and updated one at a time, staleness is
silent until you go looking for it, and even after an update lands, the
setup skill that configured the old version never re-runs on its own — so
its written configuration quietly falls behind. This plugin gives you one
command, `/updates:run`, that reports every installed plugin's version
against the marketplace, applies updates you confirm, and tells you which
setup skills are worth re-running afterward.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install updates@clam
```

Installing changes nothing — the plugin is inert until you explicitly run
`/updates:run`. No other configuration or prerequisites.

## What to expect

- **On install:** nothing changes. No hooks fire, no background process
  starts, and no files are written — the plugin has no effect until you run
  its skill.
- **When `/updates:run` is invoked:** it reads
  `~/.claude/plugins/installed_plugins.json` (what's installed),
  `~/.claude/plugins/marketplaces/clam/.claude-plugin/marketplace.json`
  plus each plugin's own `plugin.json` in that clone (what's latest), and
  `~/.claude/clam-setup-stamps.json` (which versions last had their setup
  run). It then runs `scripts/check-versions.sh` to build the version
  report, and — after your confirmation — the `claude plugin update
  <plugin>@clam` CLI commands for the plugins you approve.
- Outside of a `/updates:run` invocation, the plugin reads and writes
  nothing.

## Common workflows

### Update everything

Run `/updates:run`. It refreshes the marketplace catalog, shows a table of
installed vs. latest versions, and — if anything is stale — asks once for
confirmation covering the whole batch (you can reply with a subset to
update only those). It reports each update's result, then lists which
setup skills are worth re-running because their stamped version no longer
matches the plugin's new version.

### Check for updates without changing anything

Run `/updates:run check`. This stops after the version report — nothing is
updated, and you aren't asked to confirm anything. Use it when you just
want to know what's stale.

### Re-run setup after an update

After `/updates:run` updates a plugin, it names which setup skills (of
`/attribution:setup`, `/privacy:setup`, `/settings:setup`,
`/statusline:setup`, `/landing:init`) are stale for the new version and
offers the command to run — it never runs them for you.

## Commands

### Skills

**`/updates:run [check]`** — not model-invocable
(`disable-model-invocation: true`); always run explicitly by name.

- With no argument: refreshes the catalog, reports current/stale/unstamped
  versions, asks one confirmation for the batch of stale plugins, applies
  the confirmed updates, and closes with setup re-run offers and
  reload/restart guidance.
- `/updates:run check`: stops after the version report. Read-only —
  nothing is updated and no confirmation is asked.

### Scripts

**`scripts/check-versions.sh`** — read-only version report, no arguments.

```
bash plugins/updates/scripts/check-versions.sh
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
bash plugins/updates/scripts/manifest.test.sh
bash plugins/updates/scripts/check-versions.test.sh
```

## Relationships to other plugins

Soft integrations only: this plugin reads the setup version stamps written
by five plugins' setup skills — `attribution`, `privacy`, `settings`,
`statusline`, and `landing` — to know when their setup is worth re-running
after an update. None of them need to be installed; with fewer of them
present, `/updates:run` simply has fewer setup-stamp rows to report on and
degrades gracefully. Nothing in clam depends on this plugin.

## Uninstalling

```
/plugin uninstall updates@clam
```

`~/.claude/clam-setup-stamps.json` is not removed by uninstalling. That's
harmless: the file only ever informs `/updates:run`'s own setup-re-run
report, nothing else reads it, and reinstalling the plugin later picks the
existing stamps back up rather than needing them recreated.
