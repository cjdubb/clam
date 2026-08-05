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
so the document is per-worktree session state, created lazily — only
when work genuinely decomposes recursively, never ahead of need.

## Focus pointer

Directly below the H1 `# Work Graph`, a single line names the node
currently being worked: `Focus: N<NN>`, or `Focus: none` when no node
currently has attention. The line is machine-read, matched literally,
modulo trailing whitespace:

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
- `Status:` — `open | done | dropped (<reason>)`.
- `Parent:` — `none | N<NN>`, the decomposition edge: this node is a
  subproblem of its parent, and solving all of a parent's non-dropped
  children solves the parent.
- `Deps:` — `none | N<NN>[, N<NN>...]`, ordering edges: nodes that must
  be done before this one can start. Soft references such as issue or
  PR refs do not belong here; only node ids.
- `Notes:` — optional context; the field may be omitted.

A node with `- Status: open` is OPEN; the machine-read marker is the
literal line, matched modulo trailing whitespace:

`^- Status: open[[:space:]]*$`

`done` and `dropped (<reason>)` are dispositions, edited in place rather
than by deleting and re-adding the entry; entries are never deleted, and
a dropped disposition requires a reason. An empty graph — the header and
`Focus: none` with no node entries — is valid; entries appear only once
decomposition genuinely begins.

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

The session tracking document (per docs/protocols/todo-format.md)
remains the state-of-record; its `Current Task:` field should cite the
Focus node id while a work graph is in use. Follow-up collections may
soft-reference node ids from their Refs fields, but the graph never
carries hard edges to follow-ups.
