# TODO-format protocol

`.local/TODO.md`, at the root of a session's worktree, is the session
tracking document: the single place a session records what it is doing,
what state it is in, and what remains. This document is the normative
spec for its shape. It is owned by the repository's architecture and
names no plugin. `.local/` is gitignored, so the document is per-worktree
session state rather than a tracked artifact.

## Header

The document opens with an H1 naming the feature, followed by three
lines: `Branch:`, `Started:`, and `Last Updated:`.

## Status

The `## Status` section carries five fields, each on its own line:

- `State:` — the current state, drawn from the vocabulary defined in
  docs/protocols/session-states.md; this document does not restate that
  table.
- `Current Task:` — what the session is doing right now.
- `Last Updated:` — when the section was last touched, echoing the
  header line of the same name.
- `Blocked Reason:` — populated only while `State:` is Blocked.
- `Decision Needed:` — populated only while `State:` is Waiting For
  Decision: the question, the recommended option, and a path to the
  relevant decision file (per docs/protocols/decision-file.md).

## Required sections

Eight sections appear, in this order: `## Status`, `## Tasks` (a
checkbox list of outstanding work), `## Testing`, `## Pre-PR`,
`## Implementation Log`, `## Blockers/Notes`, `## Open Questions`, and
`## Discovered Tasks`.

## Real-time discipline

State is written as it changes, not at session end. The document must
survive compaction and session restarts as the single source of truth
for the work: a reader should be able to resume the work from this file
alone, with nothing else to consult.

## Edge cases

A field with no current value stays present and empty — `Blocked
Reason:` with nothing after the colon — and is never deleted. Extra
repo-specific sections may follow the required eight, but they may never
reorder or replace them.
