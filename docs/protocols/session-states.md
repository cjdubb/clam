# Session-states protocol

This document is the normative spec for the shared session-state
vocabulary used by every session-tracking artifact in this repository. It
is owned by the repository's architecture, not by any plugin, and it
names no plugin: whatever reads or writes session state conforms to the
table below rather than to a copy embedded in its own implementation.

## Runtime artifact

The protocol's runtime home is the `State:` field in the `## Status`
section of `.local/TODO.md`. That field's placement and the rest of the
document's shape are specified in docs/protocols/todo-format.md; this
document owns only the vocabulary the field may hold.

## Three attributes, not more

Every state in the table below carries exactly three attributes: a name,
a category, and a summons value. Presentation attributes — an emoji, a
colour — are explicitly not part of the protocol. A renderer keeps its
own private mapping from state to emoji or colour and may change that
mapping at will without it being a protocol change, because the mapping
is not part of what this document specifies.

## Category vocabulary

Four categories describe what a state means for whether a session should
continue:

- **active** — work is in flight; a session should not end a turn in an
  active state without cause.
- **parked** — the session is waiting on something that resolves on its
  own; stopping is allowed, and the state stays silent while it waits.
- **needs_user** — a human must act before the work can continue; the
  session stops.
- **terminal** — no actionable work remains.

## Summons semantics

A state whose summons value is `yes` alerts the user — a bell, a
dashboard flag, a push notification, whatever the renderer offers — once
on the transition into the state, never on every turn after that.
Awaiting User Review summons once on entry and then parks silently;
Blocked and Waiting For Decision both stop the session outright.

## The state table

| Name | Category | Summons |
|---|---|---|
| Not Started | active | no |
| In Progress | active | no |
| Awaiting Agent | parked | no |
| Awaiting CI | parked | no |
| Awaiting Independent Agent Review | parked | no |
| Awaiting User Review | parked | yes |
| Awaiting Bot Review | parked | no |
| Awaiting Reviewer Assignment | parked | no |
| Awaiting Human Review | parked | no |
| Awaiting Merge Queue | parked | no |
| Waiting For Decision | needs_user | yes |
| Blocked | needs_user | yes |
| Complete | terminal | no |

## Conformance

Any plugin that reads or writes the `State:` field, or that carries a
vendored copy of this table, must match the (name, category, summons)
triples above exactly; drift on those three columns is a conformance
defect, even where a vendored copy's presentation columns differ freely.
Additions and removals of states happen here first, and copies follow —
this document is the sole owner of the list.

## Edge cases

A `State:` value that does not appear in the table above is a protocol
violation by whatever wrote it, not an extension point: the writer is
wrong, not the table.
