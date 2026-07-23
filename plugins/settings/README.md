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

<!-- STUB: NotImplemented B04 — fill in all sections per the contract above -->
