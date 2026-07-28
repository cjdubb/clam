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
normative for `build`, `landing`, `lego`, and `tracking`. Where a rule is not
yet true of the code, the [Current state](#current-state) section says so
plainly.

## The layering rule

Plugins form layers, not a graph. A **leaf** plugin owns one concern and is
complete in itself. A **composite** plugin sits above leaves and composes
them into a larger flow.

`build` is a composite — the only one at the time of writing, though there
may be many, and a composite may itself be composed by another. Nothing
below is special to it:

```
build (a composite: work is planned and built, then finished work is landed)
├── landing
│   ├── forge-github
│   └── forge-gitlab
├── lego
└── tracking
```

Three rules follow, and they are the whole architecture:

1. **References point downward only.** A composite may know its components
   exist. A component may never reach up at a composite. Conditionality is
   no defence — an "if plugin X is installed, delegate to it" seam is still
   a dependency on X, and one that inverts the layering is still wrong when
   it happens to be inert.

2. **Leaf plugins work effectively in isolation.** A leaf must be fully
   useful installed on its own, with no sibling and no composite present —
   that is the normal case, not a degraded one. A leaf whose behaviour
   thins out when a companion is missing has taken a dependency it should
   not have.

3. **Siblings do not know each other.** `lego` and `landing` in particular
   must have no references or knowledge that the other exists: no skill
   invocations, no imports, no mentions in documentation. Same for
   `tracking` and `lego`.

The rules exist because plugins are installed independently. A plugin that
references a sibling or a composite breaks whenever that other plugin is
absent, renamed, or evolved — and absent is the common case.

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

Landing takes a finished branch and lands it, per the policy committed in
`.claude/clam-profile.jsonc`. Landing is responsible for the whole path from
finished branch to merged commit, which is a good deal more than opening a
PR:

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

Forge-specific mechanics live in a forge plugin (`forge-github`,
`forge-gitlab`), never in landing itself, for two reasons.

**Supporting more than one tool.** Landing defines each operation once; a
forge plugin implements it in its own CLI and vocabulary. Adding Bitbucket
means writing a plugin, not editing landing and re-testing every forge it
already supports.

**Not paying for the tools you don't use.** One plugin carrying every
forge's mechanics is the gorilla-and-the-rainforest problem — you wanted a
banana, and what you got was the gorilla holding it and the entire
rainforest. Someone who only ever uses GitHub should never have GitLab and
Bitbucket instructions occupying their context window. Install one forge
plugin; load one forge's worth of context.

### lego — contract-first decomposition and parallel dispatch

Lego solves the problem of safely parallelizing implementation across cheap
agents. It decomposes work into blocks carrying behavioral contracts,
scaffolds deliberately unimplemented stubs, and dispatches realm-restricted
workers in isolated worktrees — test-writers first, implementers second — with
orchestrator verification at every gate. It owns `.local/blocks.md`,
`.local/plans/`, `.local/contracts/`, `.local/briefs/`, and
`.local/reports/`.

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
and `/clear`. It owns `.local/TODO.md` as the state of record, enforces the
state lifecycle through Stop and SessionStart hooks, and captures follow-ups
and open questions.

`/tracking:make-progress` is **stall recovery**, not session resumption —
resumption is the SessionStart hook's job. Make-progress addresses the case
where the session stopped when it should have kept going, and its decision
table is a catalog of known stall shapes and their remedies. Each invocation
also serves as a labeled training example: the state at the stall, and the
correct next move.

Tracking's built-in rows may only cover concerns tracking itself owns —
`TODO.md` states, parked-state-versus-reality contradictions, cleanup, crons.
A row that names another plugin's artifact format, status vocabulary, or
skill namespace is a layering violation regardless of how useful it is.

## Bridging without coupling

If `lego` and `landing` cannot see each other, something must connect them.
Two things do, and only two:

- **build**, when installed — the composite knows both exist and frames the
  handoff.
- **the engineer**, always — lego produces its delivery branch and manifest,
  and the engineer says "now land these."

There is no third mechanism, and deliberately no registry, rule file, or
extension seam for contributing cross-plugin behavior. The executor is an
LLM, and the state files are self-describing: an agent that reads a
`TODO.md` saying *dispatch B04* alongside a `.local/blocks.md` full of block
statuses will follow the trail on its own. Installed skills already advertise
themselves through their descriptions, so the skill catalog *is* the registry.

This is why the fix for a cross-plugin coupling is almost always
**subtractive** — delete the offending row or reference and let the generic
"read `.local/` artifacts without assuming which plugin wrote them" step plus
the skill catalog cover it. Reach for a mechanism only after that demonstrably
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

## Current state

Only the rename has landed. The rest of the architecture above is agreed but
not yet implemented, and the code still contradicts it in the places noted.

| Rule | State |
|---|---|
| Composite named `build` (was `deliver`) | Landed — #137 |
| Leaf plugins work installed alone | Holds — `landing`, `lego`, and `tracking` are each independently usable today |
| `landing` must not reference `build` | **Not yet** — `plugins/landing/README.md` still documents the delegation seam |
| `landing` defines a forge interface and delegates | **Not yet** — no forge interface; `merge.strategy` is handled inline |
| `landing` drives the branch through to merge | **Largely not yet** — `/landing:land` creates the request and stops; no CI monitoring, bot-review monitoring, feedback handling, description sync, or merge-queue monitoring |
| `forge-github` / `forge-gitlab` plugins exist | **Not yet** — neither plugin exists |
| `build` carries no verb of its own | **Not yet** — `/build:sync-pr` still ships, and `build-context.sh` still injects the standing sync instruction |
| `lego` ends at the assembled deliverable | **Not yet** — `worktree.sh` still calls `gh pr create`; `plugins/lego/README.md` still names `/landing:land` |
| `tracking` names no other plugin's artifacts | **Not yet** — the make-progress decision table still carries a `.local/blocks.md` → `/lego:dispatch` row |

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
