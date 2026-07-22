---
name: rundown
description: "Render or deep-dive the pending decision files in `.local/decisions/`. Use when a decision prompt needs more context: `/decision-log:rundown` summarizes every open decision, `/decision-log:rundown <option>` re-grounds and expands one option. Also hosts the decision-file template sessions write at park time."
disable-model-invocation: true
---

# Decision Rundown

Give the user decision-grade context on demand. Sessions capture the full analysis behind a pending decision in a file at park time; this skill renders those files in chat and deepens them on request.

## Decision file convention

One file per decision: `.local/decisions/NNN-<slug>.md`.

- `NNN`: zero-padded, max existing number plus one (`001`, `002`, ...). Create the directory if it does not exist.
- `<slug>`: short kebab-case name for the question (e.g. `001-typecheck-gate.md`).

### Template

Canonical; the clam session workflow (session-modes plugin; formerly the clam-code system prompt) references it here.

```markdown
# Decision: <question>

Status: Open
Refs: <ticket / PR / related decision files>

## Context

Why the decision arose now. Evidence with citations: file:line, command
output, measurements.

## Options

### 1. <name>

What it entails, in plain terms.

**Pros:** ...
**Cons:** ...

### 2. <name>

(one block per option, same shape)

## Recommendation

<option>, because <why>.

## If Deferred

What happens if the user does not decide, or just replies "go".
```

Rules:

- Evidence goes in `## Context` at write time, while it is still in the context window. Compaction discards exploration and superseded approaches, which is exactly the analysis behind a pending decision; it cannot be re-derived later.
- Mandatory per option: what it entails in plain terms, pros, cons. Optional depth fields (effort, risk, reversibility) only when material to the choice; forcing them invites formulaic filler.
- `## Recommendation` (which option and why) and `## If Deferred` are mandatory: they are what make a bare "go" reply safe to act on.
- `Status:` stays `Open` until decided, then becomes `Resolved (<choice>; <who>, <YYYY-MM-DD>)`.

## When the file is written and resolved

The session writes the file BEFORE setting `State: Waiting For Decision`. The clam session workflow mandates this; this skill hosts the how.

<!--
Contract: B04 decision-log re-point
Behavior: the rendered-doc gate below consumes the render-doc plugin BY SKILL
NAME, keeping decision-log fully functional when render-doc is absent.
Outputs (what the gate paragraph below says):
- Check whether the skill `render-doc:render` appears in the available
  skills. If it does not (the render-doc plugin is not installed), skip the
  render silently and continue with the chat flow.
- If it does, invoke it on the decision file with the open-in-browser intent.
- If the render fails, note "HTML render failed — presenting as markdown"
  once and continue with the chat flow; a render failure must NEVER block
  the decision.
- plugins/decision-log/README.md's soft-dependency entry for render-doc
  names the plugin and skill (render-doc:render) and notes the graceful
  degradation.
Invariants: no filesystem path into another plugin anywhere in decision-log;
gate is skill availability; degradation: skill absent -> silent skip; skill
present -> render; render failure -> one-line notice, continue.
Edge cases: skill present but broken manifests as a render failure -> notice
+ continue.
-->

After writing the file, check whether the skill `render-doc:render` appears in the available skills. If it does not (the render-doc plugin is not installed), skip the render silently and continue with the chat flow. If it does, invoke `render-doc:render` on the decision file (`.local/decisions/NNN-<slug>.md`) with the intent to open it in the browser so the user reads the rendered HTML view.

If the render fails, note "HTML render failed — presenting as markdown" and continue with the chat flow; a render failure must NEVER block the decision.

When the user decides:

1. Append `## Resolution`: the choice, the rationale, the date.
2. Flip `Status:` to `Resolved (...)`.
3. Have other tracking docs (PLAN.md changelog, TODO.md Implementation Log) reference the file rather than repeat its content.

## Invocation

### `/decision-log:rundown` (no arguments)

1. Find open decisions: files under `.local/decisions/` whose `Status:` is `Open`.
2. Render a concise chat summary per decision: the question, one line per option, the recommendation and why, the default path on "go", and the file path.
3. If the session is parked on a decision but no file exists (a legacy or non-compliant park), generate the file post-hoc from current context. Mark every claim you cannot re-verify now as `unverified (pre-compaction context)`; never assert it as fact.

### `/decision-log:rundown <option>`

`<option>` is an option number or name; when several decisions are open, disambiguate as `/decision-log:rundown <decision> <option>`.

Deep-dive the named option:

1. Re-ground: targeted reads and searches that verify, refute, or extend the option's claims.
2. Expand the analysis in the decision file.
3. Summarize the delta in chat: what was confirmed, what changed, what was overturned.

## Grounding rules

Borrowed from the decision-log discipline:

- No generic pros/cons ("more maintainable", "better performance"). Every claim is specific to this decision.
- Claims cite sources: file:line, command output, measurements, documentation links.
- No formulaic boilerplate; vary phrasing across options and decisions.
- Mark what you cannot verify (`unverified (pre-compaction context)`) instead of asserting it.

## Boundaries

- Write only under `.local/decisions/`. Everything else is read-only.
- Escalate genuinely contested calls to a team council (`team-council` in the team-review plugin; `/team-council` in clam-code until that plugin is ported).
- When a decision needs to become a permanent repo record, use `/decision-log:create`.
