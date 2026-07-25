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

<!-- NotImplemented: B03 — sections below are scaffold placeholders; content
     lands at implementation. -->

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install updates@clam
```

<!-- NotImplemented: B03 -->

## What to expect

<!-- NotImplemented: B03 -->

## Common workflows

<!-- NotImplemented: B03 -->

## Commands

<!-- NotImplemented: B03 -->

## Relationships to other plugins

<!-- NotImplemented: B03 -->

## Uninstalling

```
/plugin uninstall updates@clam
```

<!-- NotImplemented: B03 -->
