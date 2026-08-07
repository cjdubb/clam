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
  1. Detect companion plugins by directory presence relative to the
     repo root of the current working directory: plugins/landing,
     plugins/lego, plugins/tracking. Detection is directory-based only —
     never source or import companion code; a present-but-broken
     companion directory still counts as present.
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
  changed, no hooks registered.

Errors:
  None. Degrades gracefully: no plugins/ directory means no companions
  detected, which is the "none present" case, not an error.

Invariants:
  - Purely on-demand: the build plugin registers no hooks; nothing about
    this skill fires automatically at session start.
  - No injected standing instructions; companion descriptions are
    conceptual.
  - Directory-based detection only; companion code is never executed.
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
Run it on demand — nothing about it fires automatically at session start,
and the build plugin registers no hooks at all.

## What it does

Check, by directory presence only, whether each companion plugin is
installed in the current repo: `plugins/landing`, `plugins/lego`, and
`plugins/tracking`. This is directory-based detection — companion code is
never sourced or imported, and a present-but-empty or broken companion
directory still counts as present (the plugin system owns broken-plugin
handling, not this skill). If there is no `plugins/` directory at all,
treat that as no companions present, not an error — this skill has no
error cases; it degrades gracefully.

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

- No plugins/ directory in the repo at all: treated as no companions
  present, the same as the none-present case above.
- An empty or broken companion directory: still treated as present —
  detection only checks that the directory exists, it never inspects or
  executes what's inside.
- Multiple repos or worktrees: always resolve companion presence against
  the current working directory's repo root, not any other checkout.
