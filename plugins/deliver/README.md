# deliver

The deliver plugin is a composition layer for shipping work: it stitches
landing, lego, and tracking into a single, coherent software delivery
lifecycle, and provides the parts of that lifecycle that no single
companion plugin owns — most importantly, keeping a pull request's
description in sync with the branch it describes. It works standalone,
and adapts its behavior as companion plugins become available.

## Purpose

Landing, lego, and tracking each solve one slice of getting work from
"in progress" to "shipped": lego decomposes and dispatches units of work,
tracking keeps state durable across sessions, and landing decides how and
where finished work lands. None of them, on their own, describe the whole
delivery framework a session is operating under, and none of them own the
job of keeping a pull request's description honest as the branch behind
it keeps changing. deliver is the composition layer above those plugins:
it explains, at session start, which parts of the delivery lifecycle are
available and how they fit together, and it supplies the PR description
sync workflow that ties the end of that lifecycle together regardless of
which companions produced the PR in the first place.

## Companion plugins

deliver detects landing, lego, and tracking by checking for their
directories under `plugins/` in the current repo — a directory-based
check, not an import of their code. Each companion that is present adds
its own section to the session-start context:

- **landing present** — adds context about merge policy (how finished
  work lands: local merge or PR) and PR creation guidance.
- **lego present** — adds context about the plan/scaffold/dispatch
  workflow for decomposing and delivering work in units.
- **tracking present** — adds context about the state lifecycle recorded
  in `.local/` tracking docs across sessions.

Any subset of these can be present, including none at all. Detection is
independent per plugin, so a repo with only lego installed gets only the
lego-flavored context, and a repo with none installed still gets a
minimal, useful context plus the standing instructions below.

## Delivery lifecycle

The stages below span "ready to land" through "deployed." Each stage
names the companion that owns it when installed, and what happens when
that companion is absent:

1. **Plan and dispatch work** — owned by lego when installed (plan,
   scaffold, dispatch units of work). Without lego, work can still be
   planned and carried out directly.
2. **Track state across sessions** — owned by tracking when installed
   (`.local/` docs recording state, plan, and progress). Without
   tracking, state lives only in the session and conversation history.
3. **Land finished work** — owned by landing when installed (merge
   policy: local merge or PR, applied consistently per repo). Without
   landing, landing decisions are made ad hoc per session.
4. **Keep the PR description current** — owned by deliver itself via the
   `/deliver:sync-pr` skill, regardless of which companion (or manual
   `gh pr create`) opened the PR in the first place.

## Skills

- **`/deliver:sync-pr`** — updates the current branch's open PR
  description to reflect the branch's current state. It detects the PR
  with `gh pr list`/`gh pr view`, gathers context from the diff, plan and
  verification docs (when present), and the commit log, and applies the
  result with `gh pr edit`. It never creates a PR and never changes the
  PR title; running it repeatedly with no new changes leaves the
  description unchanged.

## Hook

`deliver-context.sh` is wired to the `SessionStart` event. On every
session start, resume, clear, or compact, it reads the session's `cwd`
from its JSON stdin payload, checks for the companion plugin directories
described above, and emits an `additionalContext` block naming the
delivery lifecycle stages that are available and how they compose. It
fails open: if `jq` is unavailable, the payload has no `cwd`, or the
input is malformed, it exits 0 with no output rather than interrupting
session start.

## Standing instructions

After every push to a branch with an open PR, sync the PR description
with `/deliver:sync-pr` so it always reflects the current state of the
branch rather than the state at PR creation time. This instruction is
injected on every session start regardless of which companion plugins
are installed.
