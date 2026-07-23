# decision-log

Skills for recording technical decisions as lightweight Decision Logs (DLs):
what was decided, why, and what alternatives were considered, with pros and
cons grounded in the actual codebase rather than generic claims. Draft
one-shot (`create`) or section-by-section in dialogue (`interactive`);
`rundown` renders and deepens the pending-decision files sessions park on
mid-workflow.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install decision-log@clam
```

No configuration required — installing the plugin is enough to use
`/decision-log:create`, `/decision-log:interactive`, and
`/decision-log:rundown`. Optional integrations (ticket linking, HTML
rendering) are documented under Relationships to other plugins below.

## What to expect

Installing changes nothing on its own — decision-log is inert until a skill
runs. No hooks fire, no context is injected into sessions, and no settings
are written.

Once a skill does run, it reads and writes specific files:

- `create` and `interactive` write and update `.local/DL-DRAFT.md` while
  drafting; on your approval, they write the final Decision Log to
  `dev-docs/decision-logs/{YYYY-MM-DD}-DL-{short-description}.md` and delete
  the draft.
- `rundown` reads and writes `.local/decisions/NNN-<slug>.md` files — the
  session workflow writes one before parking on `State: Waiting For
  Decision` — and, when the render-doc plugin is installed, invokes the
  `render-doc:render` skill to open an HTML render in the browser.

## Common workflows

### Draft a Decision Log in one shot

Run `/decision-log:create` (it also fires automatically when a decision
needs recording). It asks what's being decided, spawns Explore subagents to
verify the codebase state, then drafts to `.local/DL-DRAFT.md` with "Do
Nothing" as Option 1 and at least two real alternatives, pros/cons cited to
file:line. Review the draft and either reply in chat or annotate it inline
with `@COMMENT:` / `@QUESTION:` / `@CONCERN:` / `@APPROVE:` / `@EVIDENCE:`
tags; once you approve, it finalizes to `dev-docs/decision-logs/` and
deletes the draft.

### Work through a contested decision collaboratively

Run `/decision-log:interactive` when the problem framing itself is unsettled
or you expect three or more plausible options. It walks six gates in
order — Problem Framing, Impact, Option Set (names only), per-option
Pros/Cons, Decision + Rationale, Consequences — proposing each in chat and
appending to `.local/DL-DRAFT.md` only after you confirm it. Finalizes the
same way as `create`.

### Check what's pending, or dig into one option

Run `/decision-log:rundown` with no arguments for a chat summary of every
open decision under `.local/decisions/` — question, one line per option,
recommendation, the default on a bare "go", and the file path. Run
`/decision-log:rundown <option>` to re-ground and deepen one option with
fresh reads before you decide.

## Commands

**create** — `/decision-log:create` (model-invocable; also fires
automatically when a decision needs recording, not only on explicit
invocation)

One-shot Decision Log draft. Gathers context on the decision and the current
ticket, spawns Explore subagents to verify the codebase state proportional
to the decision's scope, then drafts to `.local/DL-DRAFT.md` from
[template.md](skills/create/template.md): mandatory "Do Nothing" as Option
1, at least two further real options, pros/cons grounded in file:line
references, never generic claims. Iterates on inline annotation tags
(`@COMMENT:`, `@QUESTION:`, `@CONCERN:`, `@APPROVE:`, `@EVIDENCE:`) until
approved, then finalizes to
`dev-docs/decision-logs/{YYYY-MM-DD}-DL-{short-description}.md` — any
referenced ticket rendered via the issue-tracker skill's `ref` operation
when that skill is installed, omitted otherwise — and deletes the draft. A
DL must be merged via PR before implementation begins.

**interactive** — `/decision-log:interactive` (explicit only;
`disable-model-invocation: true`)

Same output and template as `create`, built one section at a time in
dialogue instead of drafted in one shot: six gates (Problem Framing, Impact,
Option Set names-only, per-option Pros/Cons, Decision + Rationale,
Consequences), each proposed in chat and appended to `.local/DL-DRAFT.md`
only after explicit confirmation. Prefer it over `create` when the problem
framing is contested, the option space is unclear, or past one-shot drafts
came out generic. Finalizes the same way as `create`.

**rundown** — `/decision-log:rundown [option]` (explicit only;
`disable-model-invocation: true`)

Renders and deepens the pending-decision files the session workflow writes
to `.local/decisions/NNN-<slug>.md` before parking on `State: Waiting For
Decision`. With no arguments, summarizes every open decision (question, one
line per option, recommendation, default on "go", file path); given an
option number or name, re-grounds it with targeted reads and expands the
file. Also hosts the canonical decision-file template the session workflow
references. After writing or updating a file, checks whether the
`render-doc:render` skill is available and invokes it to open an HTML
render when the render-doc plugin is installed; skips the render silently
when it is not, and on a render failure falls back to plain markdown with a
one-line notice — a render failure never blocks the decision.

### Conventions

- **DL draft:** `.local/DL-DRAFT.md`; **final:**
  `dev-docs/decision-logs/{YYYY-MM-DD}-DL-{slug}.md`
- **Pending decisions:** `.local/decisions/NNN-<slug>.md`, `Status: Open` →
  `Resolved (<choice>; <who>, <YYYY-MM-DD>)`
- **Review annotations in drafts:** `@COMMENT:`, `@QUESTION:`, `@CONCERN:`,
  `@APPROVE:`, `@EVIDENCE:`

## Tests

```bash
bash plugins/decision-log/scripts/rundown-render-seam.test.sh
```

## Relationships to other plugins

- **Requires:** none — the plugin is fully standalone; drafting, iterating,
  and finalizing a DL works without any other plugin installed.
- **Provides:** the `.local/decisions/NNN-<slug>.md` decision-file template
  that `rundown` hosts is the canonical format the clam session workflow
  (session-modes plugin, formerly the clam-code system prompt) references
  and is expected to write before a session parks on `State: Waiting For
  Decision`.
- **Consumes** (all optional; everything degrades gracefully when absent):
  - **issue-tracker skill** (pr-workflow plugin, not yet ported): ticket
    fetch and canonical ticket links; without it, ticket references are
    omitted.
  - **render-doc** (`render-doc:render` skill, render-doc plugin): HTML
    render of decision files, gated on skill availability rather than a
    filesystem path; skipped silently when the plugin is not installed.
  - **team-council** (team-review plugin, not yet ported): escalation
    target `rundown` names for genuinely contested calls.

## Uninstalling

```
/plugin uninstall decision-log@clam
```

Uninstalling does not touch existing Decision Logs — files already
finalized under `dev-docs/decision-logs/` are permanent project records and
stay. It also does not clean up an in-progress `.local/DL-DRAFT.md` if a
draft was never finalized, or any files left under `.local/decisions/`.
Delete these by hand for a clean state.
