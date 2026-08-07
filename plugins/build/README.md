# build

The build plugin is a composition layer for shipping work: it frames the
delivery lifecycle a session is operating under and names which of
landing, lego, and tracking are installed alongside it. Landing, lego, and
tracking each solve one slice of getting work from "in progress" to
"shipped" (lego decomposes and dispatches units of work, tracking keeps
state durable across sessions, and landing decides how and where finished
work lands), but none of them alone describes the whole delivery framework
a session is operating under. build works standalone and adapts its
context as companion plugins become available.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install build@clam
```

No configuration required. Run `/build:context` whenever you want the
framing; build detects companion plugins (landing, lego, tracking)
automatically by checking for their directories under `plugins/` — there's
no setup step to enable that.

## What to expect

build ships two on-demand skills, `/build:build` and `/build:context`.
Nothing fires automatically — you invoke either one when you want it, and
both present a conversational summary, not a file or setting change.

`/build:build` is the lifecycle front door. It detects which companion
plugins are installed and whether the current worktree carries in-flight
work, then routes the session accordingly: resuming work already in
progress, or starting new work from a standing start. Like the rest of
build, it writes no files and changes no settings — it works out where the
session is and hands off to the right next step.

`/build:context` is the orientation skill: you invoke it when you want to
be oriented in the delivery framework this repo runs under.

Running `/build:context` checks for companion plugin directories under `plugins/` (a
directory-based check, not an import of their code) and frames the
installed subset:

1. **Plan and dispatch work** — owned by lego when installed (plan,
   scaffold, dispatch units of work). Without lego, work can still be
   planned and carried out directly.
2. **Track state across sessions** — owned by tracking when installed
   (`.local/` docs recording state, plan, and progress). Without
   tracking, state lives only in the session and conversation history.
3. **Land finished work** — owned by landing when installed (merge
   policy: local merge or PR, applied consistently per repo). Without
   landing, landing decisions are made ad hoc per session.

Any subset of the three companions can be present, including none — a
repo with only lego installed gets only the lego-flavored framing, and a
repo with none installed still gets a minimal framing explaining build's
standalone, composite purpose and suggesting the companion plugins. The
framing stays conceptual: it names what each companion governs without
prescribing what to do next or mapping states to specific companion
skills. Beyond these on-demand skills, build is otherwise inert.

## Common workflows

### Start or pick up work

Run `/build:build`. It works out whether this worktree already carries
in-flight work and routes you there, or sets you up to start something
new — using whichever companion plugins happen to be installed, and
degrading gracefully when none are.

### See what's available in a session

Run `/build:context`. It checks which of landing, lego, and tracking are
also installed and presents the delivery stages each one owns. Install
landing, lego, and/or tracking alongside build for the richer,
companion-specific framing; build still works standalone, explaining its
composite purpose, without any of them.

## Commands

### Skills

- **`/build:build`** — on-demand skill that acts as the lifecycle front
  door: it detects companion plugins and in-flight work state, then routes
  the session to resume work already in progress or to start new work.
  Conversational only: no files written, no settings changed, no hooks
  registered.
- **`/build:context`** — on-demand skill that detects companion plugins
  and presents the delivery framework framing described above under What
  to expect. Purely conceptual and conversational: no files written, no
  settings changed, no hooks registered.

## Update

```
/plugin marketplace update clam
claude plugin update build@clam
```

Both commands are needed: refreshing the catalog never touches an installed
plugin, and updating one is CLI-only — there is no `/plugin update`.
Afterwards run `/reload-plugins` to pick the new version up in the current
session, or restart the session if this plugin ships hooks or agents.

Auto-update is off by default for third-party marketplaces. Even with it
enabled, a plugin that ships hooks stays pinned to the last explicitly
installed version until you run the update command yourself
(anthropics/claude-code#52218).

## Relationships to other plugins

build detects landing, lego, and tracking by checking for their
directories under `plugins/` in the current repo — a directory-based
check, not an import of their code. Each one that is present adds its own
section to the framing presented by `/build:context` (see What to expect
for what each section says):

- **landing** — soft integration. Adds context about merge policy (how
  finished work lands: local merge or PR) and PR creation guidance.
- **lego** — soft integration. Adds context about the plan/scaffold/
  dispatch workflow for decomposing and delivering work in units.
- **tracking** — soft integration. Adds context about the state
  lifecycle recorded in `.local/` tracking docs across sessions.

Detection is independent per plugin, so any subset can be present,
including none. build has no hard dependencies — it is fully functional
standalone — and doesn't currently provide any interface, file, or skill
that another clam plugin consumes.

## Uninstalling

```
/plugin uninstall build@clam
```

No cleanup needed beyond uninstalling — build writes no settings, config
files, or `.local/` state of its own, and registers no hooks to stop.
