# Decision-file protocol

A decision file is the artifact a session writes before it parks on an
open question, so that whoever resolves the question can decide from the
file alone. This document is the normative spec for that artifact. It is
owned by the repository's architecture, not by any plugin, and it names
no plugin.

## Location and naming

A decision file lives at `.local/decisions/NNN-<slug>.md`, where `NNN` is
the next free zero-padded three-digit number in that directory and
`<slug>` is a kebab-case rendering of the question being asked. `.local/`
is gitignored, so decision files are session-local records rather than
tracked artifacts — nothing under that directory is expected to survive
a commit.

## Header

Every decision file opens with an H1 of the form `# Decision: <question>`,
followed by a `Status:` line and, optionally, a `Refs:` line pointing at
related files or issues.

## Status lifecycle

The `Status:` line reads `Status: Open` while the question is undecided,
and becomes `Status: Resolved (<choice>; <who>, <date>)` once it is
settled. Resolution is recorded by editing the Status line in place; any
detail written after the decision is appended below the existing
sections rather than rewritten over the analysis that led to it.

## Required sections

Four sections follow the header, in this order:

- `## Context` — the evidence available at the time the file was
  written.
- `## Options` — each option under consideration, with what it entails,
  its pros, and its cons.
- `## Recommendation` — the one option being recommended, and why.
- `## If Deferred` — what a bare "go" or no answer at all adopts by
  default.

## Consumption

A session that parks on the Waiting For Decision state (per
docs/protocols/session-states.md) points its `.local/TODO.md` entry's
`Decision Needed:` field (per docs/protocols/todo-format.md) at the
decision file's path, so a reader can jump straight from the tracking
document to the open question.

## Edge cases

Multiple open decisions at once are always separate files, never one
file carrying multiple questions. A decision that resolves itself —
overtaken by events before anyone answers it — still gets its Status
line updated to record the outcome; it is not deleted.
