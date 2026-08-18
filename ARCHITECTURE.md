# Plugin architecture and responsibilities

This document records the agreed responsibilities of the workflow plugins in
this marketplace and the rules governing how they may refer to each other. It
exists because the same concern kept being patched into three different
skills, and duplication of that kind is a symptom: *we shouldn't need to add
it to 3 different skills — that suggests the architecture of the plugins is
flawed.*

Tracing that duplication back found a genuine cycle: `build` detected
`landing`, while `landing` documented a delegation seam back to `build`. Both
halves were conditional, and both were still dependencies.

The rules below were settled in conversation while fixing issue #53 (the
`deliver` → `build` rename and the PR-formatting concern behind it). They are
normative for all plugins in this marketplace, not only the ones that
motivated them — a plugin written after this document is bound by the same
rules from the moment it exists. Where a rule is not yet true of the code,
the [Current state](#current-state) section says so plainly.

## The layering rule

Plugins form layers, not a graph. A **leaf** plugin owns one concern and is
complete in itself. A **composite** plugin sits above leaves and composes
them into a larger flow.

`build` is the only composite in this marketplace at the time of writing,
though there may eventually be others, and a composite may itself be
composed by another. Nothing below is special to it:

```
build (a composite: work is planned and built, then finished work is landed)
├── landing
│   ├── forge-github
│   └── forge-gitlab
├── lego
└── tracking
```

`forge-github` and `forge-gitlab` are planned components of the diagram
above, not built plugins — nothing in this document assumes either exists
yet.

Three rules follow, and they are the whole architecture:

1. **References point downward only, detect-and-degrade, never required.**
   A composite may know its components exist and adapt to whichever of them
   are present; a component may never reach up at a composite.
   Conditionality is no defence — an "if plugin X is installed, delegate to
   it" seam is still a dependency on X, and one that inverts the layering is
   still wrong when it happens to be inert. An absent component means
   silence, not failure: a leaf's presence is never required for the
   composite to function, only detected and degraded around.

2. **Leaf plugins work effectively in isolation.** A leaf must be fully
   useful installed on its own, with no sibling and no composite present —
   that is the normal case, not a degraded one. A leaf whose behaviour
   thins out when a companion is missing has taken a dependency it should
   not have.

3. **Siblings do not know each other, universally.** This holds for every
   plugin pair, not only the ones this document happens to name — `lego`
   and `landing`, `tracking` and `lego`, or any pair not yet invented: no
   skill invocations, no imports, no mentions in documentation, in either
   direction. It is a consequence of rule 2: a leaf that names a sibling
   the user has not installed misleads the agent reading it about what
   actually exists in this installation, which is exactly the dependency a
   leaf working in isolation cannot afford to take.

The rules exist because plugins are installed independently. A plugin that
references a sibling or a composite breaks whenever that other plugin is
absent, renamed, or evolved — and absent is the common case.

## Capabilities, not plugins

The rule underneath every leaf is capabilities, not plugins: a plugin states
its goal — "create a worktree" — and carries a baseline implementation using
standard tools, so the goal is always met even alone. The executor then
enhances that baseline via whatever skill the catalog advertises for the
job, without ever naming which plugin provides it: `newtree` when the
catalog offers it, raw `git worktree` when it doesn't.

Graceful degradation is the property this produces, and it is named
explicitly because it is easy to lose by accident: every capability works
with or without any enhancing plugin present. A leaf that only works well
when a specific companion happens to be installed has smuggled a dependency
back in through the capability layer — the same failure rule 2 forbids,
wearing a different disguise.

## Protocols

A protocol is a shared artifact convention: a file format and lifecycle two
or more plugins read or write, specified once at repo level rather than
inside whichever plugin happens to implement it today. No plugin owns a
protocol's spec — the architecture does — so a plugin depends on the
protocol, never on whichever plugin wrote a given artifact.

Four protocols are named this way: the session-state vocabulary
(`docs/protocols/session-states.md`), the decision-file format
(`docs/protocols/decision-file.md`), the setup-stamp record
(`docs/protocols/setup-stamp.md`), and the session tracking document
(`docs/protocols/todo-format.md`). Each spec is self-contained and names no
plugin.

Shell scripts cannot consult the skill catalog the way an LLM executor can,
so script-level integration with a protocol works differently: it vendors a
conforming copy of the logic it needs, instead of reaching for the skill
catalog or into another plugin's implementation, or it reads the protocol's
spec directly.

## Responsibilities

### build — the lifecycle composite

Build frames the software lifecycle conceptually — work is planned and built,
then finished work is landed — and notes which companion plugins are present.
That is the entirety of its job.

Build is the only plugin permitted to know that the others exist, and it is
the seam through which they are connected. It was named `build` rather than
`sdlc` deliberately, to leave room for other lifecycle flows alongside it.

Build does **not** own any verb of its own. It does not create PRs, does not
sync PR descriptions, and does not carry plugin-specific mappings from state
to skill. Hardcoding a companion's artifact format or status vocabulary into
build would make build break every time that companion evolves — maintenance
coupling, even in the plugin whose job is composition.

### landing — the landing seam

A **forge** is the hosted platform a repository lives on and where its review
process happens — GitHub, GitLab, Bitbucket. Each offers the same broad shape
(a pull or merge request, review, CI, merge) behind a different CLI and
vocabulary.

Landing takes a finished branch and lands it, per the repo's landing policy
(user-local, detected and cached by `/landing:init`). Landing is responsible
for the whole path from finished branch to merged commit, which is a good
deal more than opening a PR:

- Creating the pull or merge request.
- Monitoring CI progress on it.
- Monitoring bot reviews.
- Addressing review feedback.
- Keeping the request's contents in sync as it changes — a description that
  no longer describes the branch is a defect, not a cosmetic lag.
- Monitoring merge-queue progress.

Where feedback calls for reworking the deliverable itself rather than the
request around it, the cycle returns to whoever built it. Landing drives the
process through to merge; it does not redesign the work.

It owns the forge interface: what a forge plugin must provide, and the
presentation conventions every forge inherits — flowing prose, no
hard-wrapped line breaks. It detects the installed forge plugin and
delegates.

Landing works with **any** branch. It does not read `lego`'s manifest, does
not know `lego` exists, and does not reach up at `build`.

Forge-specific mechanics belong in a forge plugin (`forge-github`,
`forge-gitlab` — planned, neither built yet), never in landing itself, for
two reasons.

**Supporting more than one tool.** Landing defines each operation once; a
forge plugin implements it in its own CLI and vocabulary. Adding Bitbucket
means writing a plugin, not editing landing and re-testing every forge it
already supports.

**Not paying for the tools you don't use.** One plugin carrying every
forge's mechanics is the gorilla-and-the-rainforest problem — you wanted a
banana, and what you got was the gorilla holding it and the entire
rainforest. Someone who only ever uses GitHub should never have GitLab and
Bitbucket instructions occupying their context window. Installing one forge
plugin should load one forge's worth of context, nothing more.

### lego — contract-first decomposition and parallel dispatch

Lego solves the problem of safely parallelizing implementation across cheap
agents. It decomposes work into blocks carrying behavioral contracts,
scaffolds deliberately unimplemented stubs, and dispatches realm-restricted
workers in isolated worktrees — test-writers first, implementers second —
with orchestrator verification at every gate. It owns its own block ledger,
plans, contracts, briefs, and reports, all session-local artifacts scoped to
lego alone.

**Lego builds the deliverable; landing lands it.** Lego's output is a
ready-to-land branch: units merged locally into the integration branch, a
clean delivery branch assembled from it, and a manifest describing what
changed, why, and how it was verified. Then lego stops.

Assembling that delivery branch — starting from the target branch and
cherry-picking the final unit commits off the integration branch, so the PR
carries the completed work without scaffold and test-wave noise — is pure
git. No forge API is involved, so it is not a forge concern and belongs with
lego, which is assembling its own output.

Lego does not call `gh pr create`, does not invoke `/landing:land`, and does
not mention landing or any forge. Its content-composition guidance states its
own output conventions for its own artifacts; it inherits nothing from a forge
and dictates nothing to one.

When landed work needs changes — review feedback, CI failures — the cycle
returns to lego. That return path is driven by the engineer or by build, not
by a landing → lego reference.

### tracking — session state lifecycle

Tracking makes work-in-progress state survive compaction, session restarts,
and `/clear`. It owns the session tracking document the todo-format protocol
defines (`docs/protocols/todo-format.md`) as the state of record, enforces
the state lifecycle through Stop and SessionStart hooks, and captures
follow-ups and open questions.

`/tracking:make-progress` is **stall recovery**, not session resumption —
resumption is the SessionStart hook's job. Make-progress addresses the case
where the session stopped when it should have kept going, and its decision
table is a catalog of known stall shapes and their remedies. Each invocation
also serves as a labeled training example: the state at the stall, and the
correct next move.

Tracking's built-in rows may only cover concerns tracking itself owns —
session-tracking states, parked-state-versus-reality contradictions,
cleanup, crons. A row that names another plugin's artifact format, status
vocabulary, or skill namespace is a layering violation regardless of how
useful it is.

### management — marketplace-meta

Management is marketplace-meta: its domain is the catalog as data —
installed versions, marketplace listings, and setup stamps — never any
particular plugin's behavior. It may enumerate installed plugins by reading
marketplace, catalog, and stamp data at runtime, but its own docs and skills
may not hardcode plugin names: a hardcoded name is exactly the kind of
per-plugin knowledge a marketplace-meta plugin exists to avoid needing.

## Bridging without coupling

If `lego` and `landing` cannot see each other, something must connect them.
Two things do, and only two:

- **build**, when installed — the composite knows both exist and frames the
  handoff.
- **the engineer**, always — lego produces its delivery branch and manifest,
  and the engineer says "now land these."

There is no third mechanism, and deliberately no registry, rule file, or
extension seam for contributing cross-plugin behavior. The executor is an
LLM, and the state files are self-describing: an agent that reads the
session tracking document saying *dispatch B04* alongside lego's own block
ledger full of block statuses will follow the trail on its own. Installed
skills already advertise themselves through their descriptions, so the
skill catalog *is* the registry.

This is why the fix for a cross-plugin coupling is almost always
**subtractive** — delete the offending row or reference and let the generic
"read session state without assuming which plugin wrote it" step plus the
skill catalog cover it. Reach for a mechanism only after that demonstrably
fails.

## Conventions that fall out

**Every concern has exactly one architectural owner.** When a rule needs
stating in three places, the architecture is wrong — find the owner rather
than copying the rule. Presentation conventions for PRs and MRs are defined
once, in landing's forge interface, and inherited by every forge. Nobody
points at anyone else's rules.

**Context is injected at point-of-use, not at session start.** A standing
instruction like "sync the PR description after every push" does not belong
in initial session context; it belongs at the moment the work happens.
Session-start injection should be limited to what genuinely orients a
session.

**Soft dependencies count.** A directory-existence check, a conditional
delegation seam, and a mention in a README are all dependencies — the forms
the layering rule is most often broken in, precisely because none of them
look like a dependency at the point they are written.

## What counts as a reference

A reference from one plugin to another takes one of four forms: a skill
invocation (`/landing:land`), a marketplace id (`lego@clam`), English naming
("the tracking plugin"), or a filesystem path (`plugins/tracking/lib/…`).
All four count regardless of whether they are conditional, hedged, or
sitting inside a comment — a directory-existence check and an "if
installed, delegate" seam are references dressed as safety nets, not
exceptions to the rule.

Word-sense collisions run the other way: a plugin's own domain vocabulary
can coincide with another plugin's name without being a reference at all.
`lego`'s own "landing strategy" is lego's domain vocabulary, not a nod to
the `landing` plugin, and `build` in one of `blocks.md`'s `Setup:`/`Test:`
command-field lines is a build *command*, not the `build` composite.
Neither is a hit.

`scripts/architecture-lint.sh` mechanically enforces these four forms
inside `plugins/*/` — a plugin naming a sibling in its own tracked files.
Root-level documents such as this one are out of scan scope, held instead by
review, and may name plugins freely: describing the architecture requires
naming the plugins it governs.

## Current state

Only the rename has landed — composite named `build` (was `deliver`), #137
— and each leaf still works installed alone today. Everything else above is
agreed but not yet built. `scripts/architecture-lint-baseline.txt` is the
mechanical, shrink-only record of exactly which cross-plugin references
still exist; consult it rather than a hand-maintained table here, since a
table drifts out of date the moment the baseline shrinks and this document
does not.

Work in flight for the forge-interface rows sits on the unmerged branches
`lego/fix-pr-line-lengths/U04-landing-forge-interface` and
`lego/fix-pr-line-lengths/U05-forge-github`, tracked by #53.

Known follow-ups:

- **#147** — remove the lego-specific row from `/tracking:make-progress`.
- **#148** — `/tracking:make-progress` hardcodes `gh pr view` and GitHub PR
  semantics in its assess step and several decision rows; the same forge
  coupling being extracted from landing applies here.
- **#149** — implement `forge-gitlab` against landing's interface.
- **#179** — landing drives the request through to merge: CI monitoring, bot
  reviews, feedback handling, description sync, merge-queue monitoring.
  Everything between "request opened" and "merged" is currently unowned.
