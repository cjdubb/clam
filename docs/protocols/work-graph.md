# Work-graph protocol

`.local/WORKGRAPH.md`, at the root of a session's worktree, is the
per-worktree work-graph document that tracks recursive problem
decomposition. This document is the normative spec for its shape. Like
the other docs/protocols/ files, it is owned by the repository's
architecture and names no plugin.

## Purpose

A problem decomposes into subproblems, recorded as parent/child edges
between nodes. Subproblems may also depend on one another, recorded as
dependency edges. Each node carries a clearly-stated goal, and a Focus
pointer names the node being worked right now. `.local/` is gitignored,
so the document is per-worktree session state.

The graph is the **primary structural record** of a session's work: the
one place its decomposition, progress, and current attention are
recorded. It is created eagerly, at the start of tracked work — a
single-node graph (the deliverable as root) is a valid and normal
starting state — and grows nodes as the work decomposes. Other
artifacts a workflow produces (plans, ledgers, task tables) carry their
own domain detail and are linked from nodes; they are never a
substitute for the graph, and the graph never transcribes their
content. Per-node `Status:` is the one deliberate exception to that
link-don't-transcribe rule: status is duplicated from the owning
artifact into the node because status is what live views of the graph
display.

## Focus pointer

A single line in the file names the node currently being worked:
`Focus: N<NN>`, or `Focus: none` when no node currently has attention.
The line is machine-read, matched literally, modulo trailing whitespace:

`^Focus: (N[0-9]+|none)[[:space:]]*$`

Exactly one Focus line appears per file. It is edited in place, in real
time, whenever attention moves from one node to another.

## Node entries

One entry exists per problem or subproblem, headed `## N<NN> — <title>`,
where `N<NN>` is a zero-padded id scoped to the file, assigned once, and
never reused — a node that finishes or is dropped keeps its id and its
entry. Each heading is followed by these fields, one per line, in this
order:

- `Goal:` — what done looks like for this node, in one or two lines.
- `Status:` — `open | in progress | done | dropped (<reason>)`.
  `in progress` marks a node someone — the session, a subagent, the
  engineer — is actively working right now. It exists because the
  single Focus pointer cannot show parallel work: when several workers
  run at once, each of their nodes reads `in progress`, and a live view
  colours them distinctly.
- `Parent:` — `none | N<NN>`, the decomposition edge: this node is a
  subproblem of its parent, and solving all of a parent's non-dropped
  children solves the parent.
- `Deps:` — `none | N<NN>[, N<NN>...]`, ordering edges: nodes that must
  be done before this one can start. Soft references such as issue or
  PR refs do not belong here; only node ids.
- `Delivery:` — optional; the field may be omitted, and is meaningful only
  on nodes whose work produces a code change. Where `Status:` answers "is
  the problem solved", `Delivery:` answers "how far has the change
  travelled": `local` (exists only in a worktree or local branch),
  `pr <ref>` (in review, `<ref>` naming the PR), `merged` (on the default
  or integration branch), or `deployed` (running where users meet it).
  Written by whoever moves the change forward — a node can be `done` yet still
  `local`, and that difference is the point: a graph whose done nodes all
  read `merged` is a shippable state, one full of `done` + `local` is not.
  Views render it as a second badge beside status; a node without the
  field renders exactly as before.
- `Notes:` — optional context; the field may be omitted. When the node's
  work is owned by another artifact — a plan section, a ledger entry, a
  follow-up — `Notes:` carries a relative markdown link to it, resolvable
  from this file's own directory. The link is the whole obligation: the
  artifact's content is never copied into the node. A finer-grained phase
  from an owning artifact's own lifecycle also rides here, never as a
  `Status:` value.

A node with `- Status: open` or `- Status: in progress` is LIVE; the
machine-read marker is the literal line, matched modulo trailing
whitespace:

`^- Status: (open|in progress)[[:space:]]*$`

`done` and `dropped (<reason>)` are dispositions, edited in place rather
than by deleting and re-adding the entry; entries are never deleted, and
a dropped disposition requires a reason. An empty graph — the header and
`Focus: none` with no node entries — is valid, though under eager
creation the normal starting state is a single root node for the
deliverable.

## Authoring defaults

Four defaults govern how nodes are written. A graph that ignores them
still parses; it just stops answering the questions this document exists
to answer.

**Node titles are plain language.** A title names the work in the words
a reader would use out loud — "serve the graph over HTTP", not a
borrowed label. `N<NN>` is the only identifier a title needs; ids from
other numbering systems — issue refs, plan-step labels, any scheme owned
elsewhere — belong in the `Notes:` field or in the artifacts that own
them, never in the title. A title carrying a foreign id is unreadable to
anyone without that scheme to hand, and quietly ties the graph to an
artifact it does not control.

**One node per actual work item.** A node stands for work someone is
doing, not for a topic. When a problem is worked as distinct phases by
distinct actors — a test-writing pass and an implementation pass over
the same code, say — each phase is its own node, carrying its own
dependency edge onto the phase before it. Collapsed into a single node,
the live phase is invisible; kept apart, who is doing what right now
reads from the graph alone.

**A follow-up captured mid-effort gets a node at capture.** Add the node
the moment the item is captured — open, parented where the work belongs
— rather than waiting to see whether it is acted on. When the follow-up
resolves, mirror that disposition onto its node: `done` once the work is
done, `dropped (<reason>)` when it is dropped or handed to another
effort. A follow-up with no node is invisible to every reader of the
graph, and a node whose disposition was never mirrored back reports work
as live long after it stopped being so.

**The graph is a tree with ordering edges, not a flat list.** Exactly one
node is a root per deliverable; every other node carries a `Parent:` edge
to the node it decomposes, so the decomposition reads from the edges
rather than from node ordering. A graph created late — after work has
already started — is still authored this way, top-down with per-phase
nodes and Parent edges, never transcribed as a flat summary of a unit
table: a backfilled flat list records only what a plan table already
said, and answers none of the questions this document exists to answer.

## Real-time discipline

Nodes are added at the moment a decomposition or a new subproblem
surfaces, dispositioned at the moment they resolve, and the Focus line
is moved at the moment attention moves — state that lives only in
conversation is lost to compaction. The document must let a cold reader
answer, from the file alone: what the overall problem is, how it was
decomposed, what is done, what remains, and what is being worked now.

A Focus id that names a node which no longer exists, or which is not
open, is a defect in the pointer rather than in the graph; the fix is to
move Focus back onto a real, open node. A reader or agent encountering
such a pointer tolerates it and fails open rather than treating it as an
error.

## Viewing

On request — "show the work graph" or similar — an agent renders the
graph as an indented ASCII tree: children nested under their parents,
dependency annotations such as `[needs: N<NN>]`, a status glyph per
node, and an arrow marking the Focus node. The markdown file remains the
document of record; rendered views are derived and disposable.

In addition to the on-request ASCII tree, an installed rendering
capability may serve a live, automatically-updating HTML view of this
document; the markdown file remains the document of record and every
served view stays derived and disposable.

## Relationship to other artifacts

The graph is the primary record of the work's structure and progress.
The session tracking document (per docs/protocols/todo-format.md)
remains the state-of-record for the session's own lifecycle — its
`## Status` header (State, Current Task, Blocked Reason, Decision
Needed) is the surface other tooling parses — and its `Current Task:`
field cites the Focus node id. Work items, their breakdown, and the log
of what happened to each belong on nodes, not in the tracking
document's own sections.

A workflow whose artifacts carry their own status lifecycle — a task
ledger, a block table — rewrites the corresponding node's `Status:` in
the same edit as its own artifact's transition, so a live view of the
graph shows progress in real time: `in progress` when work on the node
actually starts, `done`/`dropped` at its resolution. Follow-up
collections may soft-reference node ids from their Refs fields, but the
graph never carries hard edges to follow-ups.
