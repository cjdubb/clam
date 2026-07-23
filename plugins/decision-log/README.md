<!--
Contract: B06 decision-log-readme
Behavior:
  Update the existing decision-log README to meet all 4 issue #61 sections.
Inputs:
  The existing README content, PLUGIN_README_TEMPLATE, plugin directory scan.
Outputs:
  Two updates to the existing README:
    1. Expand the existing "Install" section into a proper "## Getting started"
       section — keep the install command, add any configuration guidance
       (mention the DL conventions, the .local/decisions/ directory that
       sessions use).
    2. Add ## Uninstalling — uninstall command
       (/plugin uninstall decision-log@clam), note that existing decision
       logs in dev-docs/decision-logs/ and .local/decisions/ are not removed.
Errors: n/a (documentation).
Invariants:
  - Preserve ALL existing content: Skills table, Conventions, Soft
    dependencies sections.
  - The existing "Soft dependencies" section already serves as the
    "Relationships" section; do not duplicate, just verify adequacy.
  - The existing "Skills" section already serves as the "Commands" section;
    do not duplicate.
  - Follow PLUGIN_README_TEMPLATE section order for new/modified sections.
Edge cases:
  - References to not-yet-ported plugins (issue-tracker, team-council)
    should be preserved as-is — they're accurate about the current state.
-->
# decision-log

Skills for recording technical decisions as lightweight Decision Logs (DLs):
what was decided, why, and what alternatives were considered — with pros/cons
grounded in the actual codebase, never generic claims.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install decision-log@clam
```

No configuration required. Sessions that park in `Waiting For Decision` write
pending-decision files to `.local/decisions/` (per-worktree, not tracked); DLs
finalized via `/decision-log:create` or `/decision-log:interactive` land in
`dev-docs/decision-logs/` (tracked, part of the repo history). Both
directories are created on first use — see Conventions below for the exact
naming scheme.

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

## Uninstalling

```
/plugin uninstall decision-log@clam
```

Existing decision logs in `dev-docs/decision-logs/` and pending decisions in
`.local/decisions/` are not removed — they're plain markdown files tracked
independently of the plugin.
