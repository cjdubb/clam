# settings

Opinionated Claude Code session defaults — agent teams, adaptive thinking,
model, effort level, and permission mode — written into whichever settings
file matches how the plugin is installed. Installing the plugin changes
nothing by itself; you opt in by running `/settings:setup`, and
`/settings:setup remove` undoes exactly what it wrote.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install settings@clam
```

No configuration required to install. Run `/settings:setup` whenever you're
ready to write your session defaults — see Common workflows below.

## What to expect

Installing changes nothing — the plugin is inert until you run
`/settings:setup`. Once you run it, it merges up to six keys into the
Claude Code settings file at the plugin's installation scope
(`~/.claude/settings.json` for `user`, `.claude/settings.json` for
`project`, `.claude/settings.local.json` for `local`):

- `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` — always written as `"1"`.
- `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` — always written as `"1"`.
- `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW` — optional, a user-provided string
  of digits; omitted entirely if you decline it.
- `model`, `effortLevel`, `permissions.defaultMode` — session defaults you
  provide interactively; there are no fallbacks, so setup won't proceed
  until you've given all three.

The write is a merge, not a replacement: every other key in the file, and
every other `env`/`permissions` entry, is left alone. The target file is
backed up first (`<file>.bak-<date>`), and all accepted keys land in one
atomic `jq` pass.

Mid-session `/model`, `/effort`, or `/plan` only change in-memory state for
that session — they never write back to the settings file, so what
`/settings:setup` persisted stays unaffected until you run it again.

## Common workflows

### Write your session defaults

Run `/settings:setup`. It detects your installation scope from
`~/.claude/plugins/installed_plugins.json` (asking you to pick if the
plugin is installed at more than one scope), confirms the install record
belongs to the current repository (for `project` and `local` scopes, via
`git rev-parse --git-common-dir`), prompts you for `model`, `effortLevel`,
and `permissions.defaultMode`, shows you the settings file change before
making it, and asks for confirmation before overwriting any key that's
already set to something else.

### Bound context growth with an auto-compact window

During setup you're asked whether to set
`CLAUDE_CODE_AUTO_COMPACT_WINDOW`. This bounds auto-compaction so a
session's context can't run away on 1M-native models — the harness
compacts at roughly the configured window minus a 20% buffer (e.g.
`"250000"` triggers compaction around 200K tokens). Provide a string of
digits, or decline and setup proceeds without writing the key.

### Remove your session defaults

Run `/settings:setup remove`. It reverses whatever `/settings:setup` wrote
— deleting up to six keys/paths (the two hardcoded env vars, the optional
compact-window env var, and the three session-default keys) from the same
scope-detected settings file, after backing it up. If none of the managed
keys are present, it reports "nothing to remove" and succeeds.

## Commands

### `/settings:setup`

Not model-invocable (`disable-model-invocation: true`) — run it directly.

Writes the settings described in What to expect. In order: detects scope
from `installed_plugins.json`; prompts for `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
(optional, string of digits, re-prompts if invalid); prompts for `model`,
`effortLevel`, and `permissions.defaultMode` (all required, no defaults);
shows the pending change and asks before overwriting any already-set key;
backs up the target file and applies the merge with a single `jq` pass;
verifies the result with `jq empty` and confirms that every pre-existing
top-level key survived the write (restores the backup and stops if any
were lost); reports what was written, to which file, and at which scope.

Stops without writing if: the plugin isn't found in
`installed_plugins.json`; the install record's `projectPath` belongs to a
different repository than the current working directory (checked via `git
rev-parse --git-common-dir`); the target settings file exists but isn't
valid JSON; the `env` or `permissions` key exists but isn't a JSON object;
or `jq` isn't available.

### `/settings:setup remove`

Same scope detection as install. Deletes all six managed keys/paths
(`env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`,
`env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`,
`env.CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `model`, `effortLevel`,
`permissions.defaultMode`) from the scope-detected settings file after
backing it up, then verifies with `jq empty` and reports what was removed
and from where. If none of the six are present, reports "nothing to
remove" and stops — this is a success, not an error.

## Tests

```bash
bash plugins/settings/scripts/structure.test.sh
```

Structural/contract checks over `plugin.json` and `skills/setup/SKILL.md`
— frontmatter, required fields, marketplace-author alignment, and that the
instruction prose actually covers every key, scope, and edge case the
contract requires.

## Update

```
/plugin marketplace update clam
claude plugin update settings@clam
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

None required in either direction. This plugin is standalone, but it isn't
alone in the settings files it writes to: attribution's
`/attribution:setup` manages its own `attribution` key, and privacy's
`/privacy:setup` manages `env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`,
`env.DISABLE_TELEMETRY`, `env.DISABLE_ERROR_REPORTING`,
`env.DISABLE_FEEDBACK_COMMAND`, `env.CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY`,
and `feedbackSurveyRate` in the same scope-matched files. Each plugin's
setup command touches only its own disjoint keys, so there's no
dependency or conflict between them.

## Uninstalling

```
/plugin uninstall settings@clam
```

Uninstalling does not revert what `/settings:setup` wrote. Run
`/settings:setup remove` first if you want the managed keys removed from
your settings file. Backup files (`<file>.bak-<date>`) created by past
`setup`/`setup remove` runs are left in place either way.
