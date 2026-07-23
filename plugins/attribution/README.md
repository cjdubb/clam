<!--
Contract: B02 attribution-readme
Behavior:
  README for the attribution plugin, following the PLUGIN_README_TEMPLATE.
  Documents the plugin's single skill (/attribution:setup and
  /attribution:setup remove) and its purpose (suppressing co-author
  attribution lines on commits and PRs).
Inputs:
  The plugin's SKILL.md, plugin.json, and the PLUGIN_README_TEMPLATE.
Outputs:
  A complete README with all required sections:
    1. H1 + purpose paragraph: what attribution suppression is and why
    2. Getting started: install command, note that installing changes nothing
       until /attribution:setup is run
    3. Commands: /attribution:setup (write the setting) and
       /attribution:setup remove (reverse it), with enough detail to
       understand what gets written where
    4. Relationships: standalone, no dependencies
    5. Uninstalling: uninstall command + note to run setup remove first
       if the setting should also be reverted
Errors: n/a (documentation).
Invariants:
  - Content must be accurate to the actual SKILL.md behavior.
  - Follows PLUGIN_README_TEMPLATE section order.
  - Does not duplicate the full SKILL.md contract verbatim; summarizes
    for a user audience.
Edge cases:
  - The jq dependency should be mentioned.
  - The scope detection flow should be summarized (not the full algorithm).
-->

# attribution

Suppresses Claude Code's co-author attribution: the `Co-Authored-By` line it
adds to commits and the attribution block it adds to PR descriptions.
Installing the plugin changes nothing by itself — attribution keeps working
as normal until you explicitly run `/attribution:setup`.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install attribution@clam
```

Installing only makes the `/attribution:setup` skill available; it does not
write any settings. Run `/attribution:setup` to actually suppress
attribution. Requires `jq`.

## Commands

### `/attribution:setup`

Writes `{"commit":"","pr":""}` to the `attribution` key of the Claude Code
settings file matching however the plugin was installed, which is what
suppresses the co-author line on commits and the attribution block on PRs.

It first works out where to write:

- **Scope detection** — reads `installed_plugins.json` for the plugin's
  installation entries. One entry: uses its scope automatically. Multiple
  entries: asks which scope to configure. No entry: reports and stops rather
  than guessing.
- **Scope → file** — `user` → `~/.claude/settings.json`; `project` →
  `.claude/settings.json` in the installing project; `local` →
  `.claude/settings.local.json` in the installing project.

Before writing, it shows the current `attribution` value (if any) and the
value about to be written, and asks for confirmation if a different value is
already set. The write itself is a merge, not a file replacement: only the
`attribution` key is touched, everything else in the settings file is
preserved, and the file is backed up to `<file>.bak-<date>` beforehand.

### `/attribution:setup remove`

Reverses the change, using the same scope-detection flow. Deletes the
`attribution` key from the same settings file (backing it up first). If the
key is already absent, it reports "nothing to remove" as a success rather
than an error.

## Relationships to other plugins

None required. This plugin is fully standalone.

## Uninstalling

```
/plugin uninstall attribution@clam
```

Uninstalling does not revert the settings change. If you want commit and PR
attribution restored, run `/attribution:setup remove` first, then uninstall.
