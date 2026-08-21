# Work Graph

This file is the primary record of the work's structure and progress:
one node per problem or subproblem, added at the moment it surfaces,
starting with a single root node for the deliverable. A node's status —
`open`, `in progress`, `done`, or `dropped (<reason>)` — is edited in
place as work starts and resolves; entries are never deleted, and a
dropped disposition always requires a reason. Focus, below, is edited
in place as attention moves from one node to the next.

Focus: none

## N01 — [short title]
- Goal: [what done looks like for this node]
- Status: open | in progress | done | dropped ([reason])
- Parent: none | N<NN>
- Deps: none | N<NN>[, N<NN>...]
- Delivery: local | pr <ref> | merged | deployed [optional; only on nodes whose work produces a code change]
- Notes: [optional context; a relative markdown link to the artifact that owns this node's detail — a plan section, a ledger entry — rather than a copy of it]

`N<NN>` is a zero-padded sequence number scoped to this file (N01, N02,
…); ids are assigned once and never reused, even for a node that is
later dropped.

Titles are plain language — the work as a reader would say it out loud.
`N<NN>` is the only identifier a title needs; ids from other numbering
systems belong in `Notes:` or in the artifacts that own them.

Add one node per actual work item, not one per topic. When a problem is
worked as distinct phases by distinct actors — a test-writing pass and
an implementation pass, say — each phase is its own node carrying its
own dependency edge, so who is doing what right now reads from the graph
alone.

A follow-up captured mid-effort gets its node at capture, not once it is
acted on; mirror the follow-up's disposition onto that node as it
resolves.

The graph is a tree with ordering edges, not a flat list: exactly one
node is a root per deliverable, and every other node carries a `Parent:`
edge to the node it decomposes. A graph created late — after work has
already started — is still authored this way, top-down with per-phase
nodes and Parent edges, never transcribed as a flat summary of a unit
table.

Nodes owned by another artifact link to it from `Notes:` and duplicate
only `Status:` — status is what live views display, so it is updated in
the same edit as the owning artifact's own transition: `in progress` the
moment work on the node starts, `done`/`dropped` at its resolution.

On a node whose work produces a code change, `Delivery:` records how far
that change has travelled — `local` (worktree or local branch only),
`pr <ref>` (in review), `merged` (on the default or integration branch),
`deployed` (running where users meet it) — updated in place by whoever
moves the change forward. Where `Status:` answers "is the problem
solved", `Delivery:` answers "has it shipped": a node can be `done` yet
still `local`. Omit the field on nodes with no code change.

The `- Status: open` / `- Status: in progress` lines are machine-read
markers, matched literally, modulo trailing whitespace. Reword one and a
consumer stops seeing the node as live.
