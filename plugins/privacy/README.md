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

<!-- STUB: NotImplemented B03 — fill in all sections per the contract above -->
