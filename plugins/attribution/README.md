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

<!-- STUB: NotImplemented B02 — fill in all sections per the contract above -->
