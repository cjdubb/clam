# Work Graph

One node per problem or subproblem, added at the moment it surfaces. A
node's disposition — `open`, `done`, or `dropped (<reason>)` — is
edited in place as work resolves; entries are never deleted, and a
dropped disposition always requires a reason. Focus, below, is edited
in place as attention moves from one node to the next.

Focus: none

## N01 — [short title]
- Goal: [what done looks like for this node]
- Status: open | done | dropped ([reason])
- Parent: none | N<NN>
- Deps: none | N<NN>[, N<NN>...]
- Notes: [optional context]

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

The `- Status: open` line above is a machine-read marker, matched
literally, modulo trailing whitespace. Reword it and a consumer stops
seeing the node as open.
