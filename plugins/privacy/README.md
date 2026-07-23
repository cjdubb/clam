<!--
Contract: B03 privacy-readme
Behavior:
  README for the privacy plugin, following the PLUGIN_README_TEMPLATE.
  Documents the plugin's single skill (/privacy:setup and
  /privacy:setup remove) and its purpose (opting out of Claude Code
  telemetry, error reporting, and feedback surveys).
Inputs:
  The plugin's SKILL.md, plugin.json, and the PLUGIN_README_TEMPLATE.
Outputs:
  A complete README with all required sections:
    1. H1 + purpose paragraph: what the privacy opt-outs cover
    2. Getting started: install command, note that installing changes nothing
       until /privacy:setup is run
    3. Commands: /privacy:setup (write the 5 env vars + feedbackSurveyRate)
       and /privacy:setup remove (reverse it), listing what gets written
    4. Relationships: standalone, no dependencies
    5. Uninstalling: uninstall command + note to run setup remove first
       if the settings should also be reverted
Errors: n/a (documentation).
Invariants:
  - Content must be accurate to the actual SKILL.md behavior.
  - Follows PLUGIN_README_TEMPLATE section order.
  - Lists all 6 managed settings by name so the user knows what's being set.
Edge cases:
  - The jq dependency should be mentioned.
  - The scope detection flow should be summarized (not the full algorithm).
-->

# privacy

Opt out of Claude Code telemetry, error reporting, feedback prompts, and
non-essential network traffic. The plugin itself is inert — installing it
writes nothing — and the opt-out only takes effect once you explicitly run
`/privacy:setup`, which writes the settings to whichever configuration file
matches how the plugin was installed.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install privacy@clam
```

Installing changes nothing by itself. Run `/privacy:setup` to actually write
the opt-out settings; until then, none of your Claude Code configuration is
touched.

## Commands

### `/privacy:setup`

Writes five env vars — `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`,
`DISABLE_TELEMETRY`, `DISABLE_ERROR_REPORTING`, `DISABLE_FEEDBACK_COMMAND`,
and `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` (each set to the string `"1"`),
plus one top-level setting — `feedbackSurveyRate` set to the number `0` —
into a Claude Code settings file:

```json
{
  "env": {
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_TELEMETRY": "1",
    "DISABLE_ERROR_REPORTING": "1",
    "DISABLE_FEEDBACK_COMMAND": "1",
    "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1"
  },
  "feedbackSurveyRate": 0
}
```

Which file gets written depends on where the plugin is installed: the skill
looks up `privacy@clam` in `~/.claude/plugins/installed_plugins.json` to
find the installation scope, then targets `~/.claude/settings.json` for a
`user`-scope install, `.claude/settings.json` for `project`, or
`.claude/settings.local.json` for `local`. If the plugin is installed at
several scopes, it asks which one to configure rather than guessing.

Before writing, it backs up the target file (`<file>.bak-<date>`) and shows
you the current values of the six managed settings alongside what's about to
be written. It only ever patches those six keys — via a single `jq` pass —
and leaves everything else in the file untouched; if any of the six is
already set to something else, it asks before overwriting. Requires `jq`;
if `jq` isn't installed, it reports that and stops without touching the
file.

### `/privacy:setup remove`

Reverses the above: deletes the same six keys (the five env vars and
`feedbackSurveyRate`) from the same scope-appropriate settings file, again
backing up first. If none of the six keys are present, it reports "nothing
to remove" rather than treating that as an error.

## Relationships to other plugins

None required. This plugin is fully standalone.

## Uninstalling

```
/plugin uninstall privacy@clam
```

Uninstalling removes the plugin but does not revert any settings it wrote.
Run `/privacy:setup remove` first if you want the telemetry and feedback
opt-outs reverted before uninstalling.
