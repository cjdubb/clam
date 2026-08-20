---
name: context
description: Present the delivery framework this repo operates under — which of the landing, lego, and tracking companion plugins are installed and which lifecycle stage each governs. Use when orienting in a repo with the build plugin installed, or when deciding how work gets planned, tracked, or landed here.
---

<!--
Contract: B09 build-skill-conversion (plan 001-fix-pr-line-lengths)

Behavior:
  On-demand replacement for the removed SessionStart hook
  (build-context.sh): invoked as /build:context, it presents the
  delivery-framework framing instead of injecting it into every session.
  1. Detect companion plugins by skill-catalog presence: landing:land
     for landing, lego:plan for lego, and active session-start tracking
     instructions for tracking. Detection is catalog-based only —
     never source or import companion code.
  2. Present the framing, adapted to the installed subset:
     - landing present: it governs merge policy — how and where finished
       work lands (local merge vs. PR creation).
     - lego present: it provides the plan/scaffold/dispatch workflow for
       decomposing and delivering work in verified units.
     - tracking present: it manages the state lifecycle of in-progress
       work via .local/ tracking docs, surviving compaction and session
       restarts.
     - none present: explain build's composite purpose (the delivery
       lifecycle: work is planned and built, then finished work is
       landed) and suggest the companion plugins.
  3. The framing stays CONCEPTUAL: it names what each companion governs,
     never issues standing instructions, and never maps states to
     specific companion skills — the agent resolves specifics from state
     files and installed skills at point of use.

Outputs:
  Conversational orientation only. No files written, no settings
  changed, no hooks registered by this skill.

Errors:
  None. Degrades gracefully: no companion catalog entries means no
  companions detected, which is the "none present" case, not an error.

Invariants:
  - Purely on-demand: nothing about this skill fires automatically at
    session start (the plugin's only hook is the separate routing
    pointer, which never invokes this skill).
  - No injected standing instructions; companion descriptions are
    conceptual.
  - Skill-catalog-based detection only; companion code is never executed.
  - All user-visible text references "build" (the plugin name), never
    "deliver".
  - Works with any subset of companions present, including none.

Edge cases:
  - Repo with no plugins/ directory: treated as no companions present.
  - Empty or broken companion directory: treated as present (the plugin
    system owns broken-plugin handling, not this skill).
  - Multiple repos/worktrees: the current working directory's repo root
    determines which plugins are checked.
-->

This skill orients you in the delivery framework this repo runs under.
Run it on demand — nothing about it fires automatically at session start.
(The plugin's only hook is the SessionStart routing pointer for
`build:build`; it never invokes this skill.)

## What it does

Check the session's skill catalog for whether each companion plugin is
installed: `landing:land` for landing, `lego:plan` for lego, and active
session-start tracking instructions for tracking. This is catalog-based
detection — companion code is never sourced or imported (the plugin
system owns broken-plugin handling, not this skill). If none of those
catalog entries are present, treat that as no companions present, not an
error — this skill has no error cases; it degrades gracefully.

For whichever subset is present, adapt the framing:

- **landing present** — landing governs merge policy: how and where
  finished work lands, whether that's a local merge or PR creation.
- **lego present** — lego provides the plan / scaffold / dispatch
  workflow for decomposing and delivering work in verified units of work.
- **tracking present** — tracking manages the state lifecycle of
  in-progress work through `.local/` tracking docs, surviving compaction
  and session restarts.
- **none present** — explain build's own composite purpose instead: the
  delivery lifecycle in which work is planned and built, then finished
  work is landed, and suggest installing the companion plugins for
  richer, stage-specific framing.

## How to present it

Keep the framing conceptual throughout: name what each companion governs
in general terms, never issue standing instructions, and never maps a
state to a specific companion skill or command — the agent resolves those
specifics itself from state files and installed skills at the point of
use. Refer to this plugin only by its current name, "build", in anything
user-visible.

## Outputs

Conversational orientation only, presented directly in the reply. No
files written, no settings changed, and no hooks are registered or
touched by running this skill.

## Edge cases

- No companion catalog entries at all: treated as no companions
  present, the same as the none-present case above.
- A companion whose skills are listed but broken: still treated as
  present — detection only checks the catalog, it never inspects or
  executes what's behind an entry.
