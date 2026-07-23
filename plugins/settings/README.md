<!--
Contract: B04 settings-readme
Behavior:
  README for the settings plugin, following the PLUGIN_README_TEMPLATE.
  Documents the plugin's single skill (/settings:setup and
  /settings:setup remove) and its purpose (persisting session defaults
  for model, effort level, permission mode, and experimental env vars).
Inputs:
  The plugin's SKILL.md, plugin.json, and the PLUGIN_README_TEMPLATE.
Outputs:
  A complete README with all required sections:
    1. H1 + purpose paragraph: what session defaults are persisted and why
    2. Getting started: install command, note that installing changes nothing
       until /settings:setup is run, note the interactive prompts
    3. Commands: /settings:setup (the interactive flow — scope detection,
       auto-compact window prompt, session defaults prompts, merge-write)
       and /settings:setup remove (reverse it), listing all managed keys
    4. Relationships: standalone, no dependencies
    5. Uninstalling: uninstall command + note to run setup remove first
       if the settings should also be reverted
Errors: n/a (documentation).
Invariants:
  - Content must be accurate to the actual SKILL.md behavior.
  - Follows PLUGIN_README_TEMPLATE section order.
  - Lists all managed keys/paths so the user knows what's being set.
  - Must explain the interactive nature (user is prompted for values).
Edge cases:
  - The jq dependency should be mentioned.
  - The optional CLAUDE_CODE_AUTO_COMPACT_WINDOW should be clearly marked
    as optional.
  - The distinction between hardcoded env vars and user-prompted values
    should be clear.
-->

# settings

Persists opinionated Claude Code session defaults into the settings file at
whatever scope the plugin was installed — two hardcoded env vars
(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`),
an optional user-prompted env var (`CLAUDE_CODE_AUTO_COMPACT_WINDOW`, which
bounds auto-compaction so a session's context can't run away on 1M-native
models), and three user-prompted session defaults (`model`, `effortLevel`,
`permissions.defaultMode`) so every new session starts with the same model,
reasoning effort, and permission mode without re-selecting them each time.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install settings@clam
```

Installing changes nothing by itself — no file is written until you run
`/settings:setup`. That command is interactive: it detects where the plugin
is installed, then prompts you for the auto-compact window (optional) and
for the model, effort level, and permission mode (required, no defaults).
Requires `jq`.

## Commands

### `/settings:setup`

1. **Detects installation scope** by reading
   `~/.claude/plugins/installed_plugins.json` for `settings@clam`. If it's
   installed at exactly one scope, that scope is used. If installed at
   multiple scopes, you're asked which one to configure. Scope maps to a
   settings file:
   - `user` → `~/.claude/settings.json`
   - `project` → `.claude/settings.json` in the project
   - `local` → `.claude/settings.local.json` in the project
2. **Prompts for `CLAUDE_CODE_AUTO_COMPACT_WINDOW`** — optional. Accept a
   string of digits (e.g. `"250000"`) or decline; if declined, the key is
   not written.
3. **Prompts for the three session defaults** — all required, no defaults
   or fallbacks:
   - `model` — the Claude model to use by default
   - `effortLevel` — the reasoning effort level (`low`, `medium`, `high`,
     `xhigh`)
   - `permissions.defaultMode` — the default permission mode (e.g.
     `acceptEdits`, `plan`, `bypassPermissions`, `default`)
4. **Shows the change before writing it**, including current values of any
   keys already set, and asks before overwriting any that differ.
5. **Backs up the target file** (`<file>.bak-<date>`), then merges all
   accepted keys in a single atomic `jq` pass — never a full-file overwrite,
   never a partial write.
6. **Verifies** the result is still valid JSON and reports exactly what was
   written, to which file, and at which scope.

Managed keys/paths (up to six, depending on whether the optional one is
accepted):

| Key/path | Value |
|---|---|
| `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | always `"1"` |
| `env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` | always `"1"` |
| `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW` | optional, user-provided string of digits |
| `model` | user-provided |
| `effortLevel` | user-provided |
| `permissions.defaultMode` | user-provided |

Mid-session `/model`, `/effort`, or `/plan` commands change in-memory
session state only — they never write back to the settings file, so the
persisted defaults from `/settings:setup` are unaffected until you rerun it.

### `/settings:setup remove`

Reverses the change, using the same scope-detection flow. Deletes all six
managed keys/paths (backing up the file first). If none of them are set,
reports "nothing to remove" and succeeds — this is not an error.

## Relationships to other plugins

None required. This plugin is fully standalone.

## Uninstalling

```
/plugin uninstall settings@clam
```

Uninstalling removes the plugin but does not revert any settings it wrote.
Run `/settings:setup remove` first if you also want the managed keys
deleted from your settings file.
