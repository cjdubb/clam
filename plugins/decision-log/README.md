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
