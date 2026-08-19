# TODO-format protocol

`.local/TODO.md`, at the root of a session's worktree, is the session
tracking document: where a session records what state it is in and what
has its attention. The structure of the work itself — its decomposition,
per-item progress, and the log of what happened — lives in the work
graph (docs/protocols/work-graph.md), the primary structural record;
this document's `Current Task:` cites the graph's Focus node. This
document is the normative spec for the tracking document's shape. It is owned by the repository's architecture and
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

Six sections appear, in this order: `## Status`, `## Testing`,
`## Pre-PR`, `## Blockers/Notes`, `## Open Questions`, and
`## Discovered Tasks`.

Two sections earlier revisions of this protocol required — `## Tasks`
and `## Implementation Log` — are superseded by the work graph: work
items and their breakdown are graph nodes, and what happened to an item
is recorded on its node. A document still carrying those sections stays
valid (readers tolerate them; writers stop adding to them), so existing
worktrees need no migration.

## Real-time discipline

State is written as it changes, not at session end. The document must
survive compaction and session restarts: together with the work graph it
cites, a reader should be able to resume the work with nothing else to
consult.

## Edge cases

A field with no current value stays present and empty — `Blocked
Reason:` with nothing after the colon — and is never deleted. Extra
repo-specific sections may follow the required six, but they may never
reorder or replace them.
