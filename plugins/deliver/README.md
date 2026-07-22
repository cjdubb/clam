<!--
Contract: B03 deliver-plugin-skeleton

Behavior:
  README documents the deliver plugin: purpose, companion plugin model,
  the delivery lifecycle, and how the plugin composes landing, lego, and
  tracking into a cohesive workflow.

Inputs: n/a (documentation surface).

Outputs (required document structure):
  - H1 `# deliver` with purpose statement matching the plugin.json
    description in spirit.
  - H2 sections:
      ## Purpose         — the high-level software delivery framework concept;
                           why a composition layer exists above the individual
                           plugins.
      ## Companion plugins — which plugins it detects and how behavior adapts
                           to their presence/absence.
      ## Delivery lifecycle — the stages from "ready to land" through
                           "deployed", mapped to which companion handles each.
      ## Skills          — /deliver:sync-pr and its contract summary.
      ## Hook            — deliver-context.sh SessionStart injection,
                           companion detection, standing instructions.
      ## Standing instructions — the PR description sync rule and any other
                           always-on delivery guidance.

Invariants:
  - No hard dependency on any companion plugin.
  - The lifecycle documentation references companion plugins as optional
    enhancers, not requirements.

Edge cases:
  - Plugin installed alone (no companions): documents what still works
    (sync-pr if gh is available) and what doesn't (no merge policy without
    landing, no dispatch without lego).
-->

NotImplemented: B03 — README to be written.
