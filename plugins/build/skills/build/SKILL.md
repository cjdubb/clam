---
name: build
description: >-
  Detect companion plugins and in-flight work state,
  then route the session to resume in-progress work or start new work via the
  appropriate companion skill. Use when starting a session, when the user says
  "build this", or when deciding how to begin work in a repo with the build
  plugin installed.
---

This skill is the session's entry point. It works out where the session
already is — mid-flight on recorded work, or at a standing start — and
routes accordingly. Run it on demand: the build plugin registers no hooks,
and nothing here ever fires automatically.

Routing is conversational only. This skill writes no files, changes no
settings, and does not write to `.local/` or anywhere else; it presents the
situation and hands the session to the right next step.

## Step 1 — detect the companions

Check, by directory presence relative to the current working directory's
repo root, which companions are installed: `plugins/landing`,
`plugins/lego`, and `plugins/tracking`. Detection is directory-based only.
Companion code is never sourced, imported, or executed — an empty or broken
companion directory still counts as present, since the plugin system owns
broken-plugin handling, not this skill.

If there is no plugins/ directory at all, that is simply no companions
present — not an error. Every companion is optional and this skill
degrades gracefully: it works with any subset present, including none.

## Step 2 — detect in-flight work

Check whether the current worktree carries recorded in-flight state:
`.local/TODO.md`, and/or entries under `.local/plans/`. This is an
existence check and nothing more — never read the content of
companion-specific artifacts, and never interpret companion status
vocabularies, to make the routing decision.

- Either one present → **resume path**.
- No .local/ directory, or `.local/` holding only system files with no
  TODO.md and no plans entries → **new-work path**.

## Resume path

Tell the user what in-flight state was found, then direct the session to
read those files — `.local/TODO.md` and anything under `.local/plans/` —
and resume from the recorded state there. The session resolves which
companion skill to invoke next from the state content and the skill
catalog.

This skill does not parse companion-specific artifact formats or status
vocabularies to make that call. It detects existence; the session reads
meaning.

Notes on this path:

- `.local/TODO.md` present but plans/ is empty is still the resume path —
  the session reads TODO.md for context.
- Invoked mid-session with work already underway, it re-reads current
  `.local/` state and re-routes. It does not restart the work and never
  discards work in progress.
- With tracking installed, tracking's own hook owns the state lifecycle;
  this path complements it by framing which lifecycle stage the session is
  in, without duplicating tracking's state reading.

## New-work path

Ask the user what they want to build. Then route on the detected subset:

- **lego present** — route to `/lego:plan` to begin structured
  decomposition into verified units of work. When both lego and landing
  are present, lego governs the build phase and landing the land phase;
  frame both, but route to lego first for new work.
- **lego absent, landing present** — proceed with direct implementation,
  then land the finished work via `/landing:land`.
- **no companions present** — frame the lifecycle conceptually: work is
  planned and built, then finished work is landed. Same conceptual
  framing as `/build:context`. Then proceed with direct implementation.

## Invariants

- On-demand only; no hooks are registered by this plugin.
- Detect-and-degrade: every companion is optional, any subset works,
  including none present.
- Companion detection is directory-based only; companion code is never
  sourced, imported, or executed.
- No companion artifact parsing — file existence only.
- References point downward only: this skill names companion entry points
  such as `/lego:plan` and `/landing:land`; companions never reference
  build in return.
- User-visible text refers to this plugin by its name, "build".
