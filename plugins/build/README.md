# build

The build plugin is a composition layer for shipping work: it stitches
landing, lego, and tracking into a single, coherent software delivery
lifecycle, and provides the parts of that lifecycle no single companion
plugin owns — most importantly, keeping a pull request's description in
sync with the branch it describes. Landing, lego, and tracking each solve
one slice of getting work from "in progress" to "shipped" (lego decomposes
and dispatches units of work, tracking keeps state durable across
sessions, and landing decides how and where finished work lands), but none
of them alone describes the whole delivery framework a session is
operating under. build works standalone and adapts its behavior as
companion plugins become available.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install build@clam
```

No configuration required. build detects companion plugins (landing,
lego, tracking) automatically by checking for their directories under
`plugins/` — there's no setup step to enable that. The one prerequisite is
for the `/build:sync-pr` skill: the `gh` CLI must be installed and
authenticated when you run it, not to install the plugin.

## What to expect

Installing build wires a `SessionStart` hook, `build-context.sh`, that
fires on every session start, resume, clear, and compact. It reads the
session's `cwd` from its stdin payload, checks for companion plugin
directories under `plugins/` (a directory-based check, not an import of
their code), and injects an `additionalContext` block naming which
delivery-lifecycle stages are available in this session and how they
compose:

1. **Plan and dispatch work** — owned by lego when installed (plan,
   scaffold, dispatch units of work). Without lego, work can still be
   planned and carried out directly.
2. **Track state across sessions** — owned by tracking when installed
   (`.local/` docs recording state, plan, and progress). Without
   tracking, state lives only in the session and conversation history.
3. **Land finished work** — owned by landing when installed (merge
   policy: local merge or PR, applied consistently per repo). Without
   landing, landing decisions are made ad hoc per session.
4. **Keep the PR description current** — owned by build itself via the
   `/build:sync-pr` skill, regardless of which companion (or manual
   `gh pr create`) opened the PR in the first place.

Any subset of the three companions can be present, including none — a
repo with only lego installed gets only the lego-flavored context, and a
repo with none installed still gets a minimal context explaining
build's standalone purpose plus the standing instruction below.
Regardless of which companions are present, the injected context always
includes:

> After every push to a branch with an open PR, sync the PR description
> with `/build:sync-pr` so it always reflects the current state of the
> branch rather than the state at PR creation time.

The hook fails open: if `jq` is unavailable, the payload has no `cwd`, or
the input is malformed, it exits 0 with no output rather than
interrupting session start. Beyond this session-start context, build is
otherwise inert — its only other user-facing behavior is the
`/build:sync-pr` skill, which runs only when invoked.

## Common workflows

### Sync a PR description after a push

Whenever you push new commits to a branch that already has an open PR,
run `/build:sync-pr`. It finds the open PR for your current branch,
gathers the diff against the merge target, any `.local/PLAN.md` /
`.local/TODO.md` context if present, and the commit log, then rewrites
the PR body to match — never touching the title. If there's no open PR
yet, it reports that and stops rather than creating one. Run it again
after addressing review feedback; it's idempotent, so re-running with no
new changes leaves the description unchanged.

### See what's available in a session

Nothing to run — just start a session in a repo with build installed.
The `SessionStart` hook checks which of landing, lego, and tracking are
also installed and injects context describing the delivery stages each
one owns, plus the standing instruction to keep PR descriptions in sync.
Install landing, lego, and/or tracking alongside build for the richer,
companion-specific context; build still works standalone for PR
description sync without any of them.

## Commands

### Skills

- **`/build:sync-pr`** — updates the current branch's open PR
  description to reflect the branch's current state. It detects the PR
  with `gh pr list`/`gh pr view`, gathers context from the diff, plan and
  verification docs (when present), and the commit log, and applies the
  result with `gh pr edit`. It never creates a PR and never changes the
  PR title; running it repeatedly with no new changes leaves the
  description unchanged.

### Hooks

- **`build-context.sh`** — fires on the `SessionStart` event (session
  start, resume, clear, and compact). Detects companion plugins and
  injects the delivery framework context described above under What to
  expect. Fails open (exits 0, no output) if `jq` is unavailable, the
  payload's `cwd` is missing, or the input is malformed. No gating env
  vars.

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
section to the session-start context injected by the `SessionStart` hook
(see What to expect for what each section says):

- **landing** — soft integration. Adds context about merge policy (how
  finished work lands: local merge or PR) and PR creation guidance.
- **lego** — soft integration. Adds context about the plan/scaffold/
  dispatch workflow for decomposing and delivering work in units.
- **tracking** — soft integration. Adds context about the state
  lifecycle recorded in `.local/` tracking docs across sessions.

Detection is independent per plugin, so any subset can be present,
including none. build has no hard dependencies — it is fully functional
standalone, needing only the `gh` CLI for `/build:sync-pr` — and
doesn't currently provide any interface, file, or skill that another clam
plugin consumes.

## Uninstalling

```
/plugin uninstall build@clam
```

No cleanup needed beyond uninstalling — build writes no settings,
config files, or `.local/` state of its own. Uninstalling stops the
`SessionStart` hook from firing and removes the `/build:sync-pr` skill;
any PR descriptions it already synced remain on the forge as-is.
