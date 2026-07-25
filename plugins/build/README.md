# build

<!-- Contract: B01 plugin-rename-core (README)

Behavior:
  Replace all references to "deliver" with "build" throughout the README.
  The plugin name becomes "build", the skill namespace becomes
  /build:sync-pr, the hook script becomes build-context.sh, and all prose
  describing the plugin's role uses "build" consistently. The README
  structure (six H2 sections from PLUGIN_README_TEMPLATE.md) and content
  are otherwise unchanged — this is a rename, not a rewrite.

Inputs:
  The existing README content (moved from plugins/deliver/README.md).

Outputs:
  README.md with every "deliver" reference replaced by "build" and every
  "/deliver:sync-pr" replaced by "/build:sync-pr", every
  "deliver-context.sh" replaced by "build-context.sh", and install/
  uninstall commands updated to build@clam.

Invariants:
  - No remaining references to "deliver" as the plugin name
  - The six required template H2 sections remain, in order
  - All factual content (SessionStart hook, sync-pr skill, companion
    detection, fail-open behavior) is preserved
  - No hard-dependency wording on companion plugins

Edge cases:
  - The word "delivery" (as in "delivery framework", "delivery lifecycle")
    is a common English word describing the workflow concept, not the plugin
    name — it stays as-is. Only "deliver" as a proper name for this plugin
    is renamed.
  - "deliver@clam" in install/uninstall commands → "build@clam"
-->

NotImplemented: B01 — replace all "deliver" plugin-name references with
"build" throughout this README. Preserve the six required template H2
sections, all factual content, and the distinction between "deliver" as a
plugin name (rename) vs "delivery" as a workflow concept (keep).

## Getting started

NotImplemented: B01

## What to expect

NotImplemented: B01

## Common workflows

NotImplemented: B01

## Commands

NotImplemented: B01

## Relationships to other plugins

NotImplemented: B01

## Uninstalling

NotImplemented: B01
