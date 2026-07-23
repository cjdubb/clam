<!--
SCAFFOLD Contract: B07 decision-log-readme (plan 002-readme-conformance)
This comment IS the unit's contract. It is removed as part of implementation;
the finished README must not contain it.
Behavior:
  Restructure the existing README (below this comment) so it conforms exactly to
  plugins/PLUGIN_README_TEMPLATE.md (the locked template; authoritative for
  every section's semantics and placeholder guidance).
Inputs:
  The template; this plugin's actual sources (.claude-plugin/plugin.json,
  skills/*/SKILL.md, hooks/, scripts/, lib/ as present); the existing README
  content below this comment, if any. Facts come ONLY from these sources —
  never invented. If sources contradict this contract or the template seems
  wrong for this plugin, STOP and escalate to the orchestrator.
Outputs:
  A README whose H2 sections are exactly, in order:
    ## Getting started
    ## What to expect
    ## Common workflows
    ## Commands
    ## Relationships to other plugins
    ## Uninstalling
  Extra H2 sections (## Tests, plugin-specific ones) are allowed ONLY
  between "## Commands" and "## Relationships to other plugins".
  H1 is the plugin name followed by a one-paragraph operational purpose
  statement. Getting started opens with the standard install commands
  (/plugin marketplace add cjdubb/clam; /plugin install decision-log@clam).
  Uninstalling opens with /plugin uninstall decision-log@clam plus any cleanup.
Errors:
  n/a (static document). Ambiguity or contradiction -> escalate, never guess.
Invariants:
  - Every substantive fact in the existing README is preserved by
    RELOCATING it under the correct template heading; nothing is merely
    left in place, nothing substantive is dropped.
  - Pre-existing HTML contract comments in the original content are
    preserved verbatim.
  - Config doctrine (no standalone config section): config written by a
    setup command is documented under that command in ## Commands; env vars
    read by a hook are documented inline with that hook; plugins with many
    env vars get a summary table at the end of ## Commands; any var a user
    must set by hand gets an exact instruction to set it in the env block
    of the settings file at the plugin's installation scope.
  - What to expect and Common workflows are written fresh from plugin
    sources per the template's placeholder guidance.
  - This SCAFFOLD comment is deleted; no other file is touched.
Edge cases / plugin-specific mapping:
  Current H2s: Skills, Conventions, Soft dependencies, Install. Install ->
  Getting started; Skills (create, rundown) -> Commands; Conventions -> an
  extra "## Conventions" section in the optional slot, or folded under
  Commands if short; Soft dependencies (render-doc graceful degradation) ->
  Relationships to other plugins.
-->

# decision-log

Skills for recording technical decisions as lightweight Decision Logs (DLs):
what was decided, why, and what alternatives were considered — with pros/cons
grounded in the actual codebase, never generic claims.

## Skills

| Skill | Invocation | What it does |
|-------|-----------|--------------|
| create | `/decision-log:create` (also model-invoked when a decision needs recording) | One-shot DL draft: explore the codebase, draft to `.local/DL-DRAFT.md` with a mandatory "Do Nothing" option and ≥2 real alternatives, iterate via annotation tags, finalize to `dev-docs/decision-logs/`. |
| interactive | `/decision-log:interactive` (explicit only) | Same output, built one section at a time in dialogue — for contested problem framings or unclear option spaces. |
| rundown | `/decision-log:rundown [option]` (explicit only) | Render or deep-dive the pending decision files in `.local/decisions/` that sessions write at park time; hosts the decision-file template. |

## Conventions

- **DL draft:** `.local/DL-DRAFT.md`; **final:** `dev-docs/decision-logs/{YYYY-MM-DD}-DL-{slug}.md`
- **Pending decisions:** `.local/decisions/NNN-<slug>.md`, `Status: Open` → `Resolved (...)`
- Review annotations in drafts: `@COMMENT:`, `@QUESTION:`, `@CONCERN:`, `@APPROVE:`, `@EVIDENCE:`

## Soft dependencies

Everything degrades gracefully when absent:

- **issue-tracker skill** (pr-workflow plugin, not yet ported): ticket fetch and
  canonical ticket links; without it, ticket references are omitted.
- **render-doc** (`render-doc:render` skill, render-doc plugin): HTML render
  of decision files; skipped silently when the plugin is not installed.
- **team-council** (team-review plugin, not yet ported): escalation target for
  genuinely contested calls.

## Install

```
/plugin marketplace add cjdubb/clam
/plugin install decision-log@clam
```
