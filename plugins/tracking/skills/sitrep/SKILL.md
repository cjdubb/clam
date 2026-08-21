---
name: sitrep
description: "Session situation report. Summarizes the goal, what has been done so far and why, where any PRs stand, and what remains. Use when resuming a session, switching between conversations, or needing a quick orientation."
disable-model-invocation: true
---

# Situation Report

Produce a concise, read-only situation report for the current session.
Do not modify any files.

## Information sources

Gather from these, skipping any that do not exist:

1. **`.local/WORKGRAPH.md`** — the primary structural record: node
   decomposition, per-node `Status:`, and the `Focus:` pointer naming what
   has attention now. Read this first; it is where the work itself lives.
2. **`.local/TODO.md`** — the session's own state: the `State:` field,
   `Current Task:` (which cites the graph's Focus node), `Blocked
   Reason:`, `Decision Needed:`, open questions, and the ticket reference
   if the header names one.
3. **`.local/PLAN.md`** — goal, approved approach, and Changelog entries.
4. **`.local/IMPLEMENTATION-PLAN.md`** — multi-PR chunk status, where a
   session keeps one.
5. **`.local/TROUBLESHOOTING.md`** — active debugging threads and failed
   attempts.
6. **`.local/FOLLOWUPS.md`** and **`.local/decisions/`** — captured
   follow-ups and their outcomes; any decision file still at
   `Status: Open`.
7. **`git log` and `git diff --stat`** — commits and changes on the current
   branch against its merge base.
8. **Conversation context** — anything discussed but not yet persisted to
   `.local/`.
9. **PR state** — see the PRs section below.

## Report format

Output these sections in order, omitting any that do not apply.

### Goal

What we are trying to accomplish and why, from the work graph's root node
and PLAN.md. Reference the ticket if `.local/TODO.md`'s header names one.

### PRs

**Include only if there are PRs to show.** Follow the `pr-status` skill in
this plugin and embed its table here: the same 7 columns, the same colour
indicators, the same tier sort order. That skill is the one owner of how PR
state is rendered — do not restate its column list or re-derive its tiers
here, and do not substitute the stale `**Status:**` field from a planning
document for what the cache reports.

When there are no PRs, or nothing has written the PR-status cache, omit
this section entirely rather than showing an empty table.

### Progress

What has been done so far, with brief rationale for each significant piece:

- Nodes at `Status: done` in the work graph.
- Commits on this branch, summarized rather than listed verbatim.
- Decisions made and approach changes, from PLAN.md's Changelog and from
  resolved decision files.

Do not duplicate PR state here; the PRs section covers it. Reference a PR
by number where it explains a piece of progress ("landed via #1234"), and
rely on the table above for its state.

### Next

What remains, in priority order:

- The Focus node, then open and in-progress nodes from the work graph.
- Blocked items and what each is waiting on, from `Blocked Reason:` and
  `Decision Needed:`.
- Unresolved entries from Open Questions and FOLLOWUPS.md.
- Active debugging threads from TROUBLESHOOTING.md.

## Rules

- **Read-only.** Never create or modify files, and never take an action the
  report describes — including advancing work that looks obviously next.
  Observe and report.
- **Concise.** This is a quick orientation, not a detailed report. A few
  bullets per section is typical. The PRs table is the one exception:
  render it in full.
- **Honest.** Do not fabricate goals or plans from ambiguous context. When
  the goal is not clear, state what is observable and flag what is not.
  Absence on disk is reported as absence — "no plan document found", never
  a claim about history like "no plan was made".
- **No bare PR references.** If the report names a PR anywhere, that PR
  must also appear in the PRs section with its current review and CI
  state. Never write "PR #1234" without showing where it stands.
- **No-work sessions.** When no `.local/` documents exist, no
  branch-specific commits are found, and the conversation carries no
  tracked work, say so plainly.
