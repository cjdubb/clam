---
name: dispatch
description: Run the per-unit worktree pipeline over scaffolded lego blocks — worktree, test wave, verification, implementation wave, acceptance, local merge, and (per delivery mode) PR delivery — dependency-ordered and parallel where independent, with orchestrator verification checklists, mechanical realm checks, and the escalation loop. Use after /lego:scaffold's gate passes.
---

# Lego Dispatch

The orchestrator runs each work unit through its own pipeline in a dedicated
git worktree: no shared tree, no global phase that gates every block on every
other block. A unit progresses from worktree creation through a test wave,
verification, an implementation wave, acceptance, and a local merge into the
integration branch — entirely on its own branch, entirely on its own
timeline. Independent units run this pipeline in parallel; a unit's pipeline
starts only once every unit it depends on has locally merged. PR delivery,
when the delivery mode calls for it, happens per PR group once every unit in
that group is accepted and merged.

Verification is not optional and not a skim: the checklists below are what
make cheap-tier workers safe.

## Vocabulary

- **Work unit**: one or more blocks dispatched together (`.local/blocks.md`'s
  `Unit:` field) — the thing that gets one worktree, one branch, one pipeline.
- **Integration branch**: the branch lego was started on, and the branch this
  skill runs from; it accumulates every unit's work via local merges. The
  checkout on that branch is the integration worktree.
- **PR group**: the blocks delivered together as one pull request, once every
  unit in the group is accepted and locally merged.
- **Delivery mode**: `delivery.mode` in the effective config —
  `.claude/lego.json` merged with any `.local/config.json` override, see
  `docs/config-schema.md` — either `main-prs` (open PRs against
  master/main per PR group) or `local-only` (stop at the local merge; the
  engineer delivers manually).

## Preconditions

The scaffold gate has passed on the integration branch, every block sits at
`Status: Scaffolded`, and the phase-boundary commit from scaffolding is made.

`.local/blocks.md` on the integration branch is the live block map for the
rest of dispatch. Its state transitions happen there, in real time, as they
occur. A unit worktree's seeded `.local/` — `unit.md`, contracts, any
`config.json` override copy (the committed `.claude/lego.json` base arrives
via checkout), and (once the worktree is created) `status.md`, `briefs/`,
and `reports/` — is a read-only reference copy scoped to that unit:
orchestrator-owned throughout, never the thing a worker edits.

## Tier resolution

Read `models.testWriter` and `models.implementer` from the effective config
(default both to `sonnet` when absent) and pass the value as the `model`
parameter on every Agent call. Do not rely on agent-definition defaults alone.

## Worker briefs

Every dispatch — test wave or implementation wave — is preceded by writing
the complete brief to a file, before the Agent call that names it. The brief
goes to `.local/briefs/NN-<wave>-<blocks>.md` inside the unit worktree: `NN`
is a two-digit sequence starting `01` in dispatch order, one shared counter
per unit — every brief that unit ever gets, test wave and implementation
wave alike, draws the next `NN`, and numbering never resets within a unit —
`<wave>` is `test` or `impl`, and `<blocks>` is this dispatch's block id(s)
joined with `+` (multi-block waves still write one brief per Agent dispatch,
so parallel same-wave agents in one unit get distinct `NN`s and `<blocks>`
values). The brief itself names: the unit worktree's absolute path (workers
do all work and run all commands there, never in the orchestrator's own
tree), the block ID(s) this unit covers, their stub path(s) (the contract
docblocks), the repo's commands from the effective config — when
`commands.test` is an object of named variants, name the specific command
this wave runs, chosen for the unit's test type and scope (construct
scope-specific monorepo commands like `nx run mylib:unit-test` here, at
brief-writing time), never just "the test command" — where tests
conventionally live (test wave) or the test paths (implementation wave), and
the required report format (the agents' definitions specify it). State
explicitly that `.local/` inside the worktree is a seeded copy scoped to
this unit — a `unit.md` carrying only this unit's block-map sections, this
unit's contracts, and any `config.json` override copy — not the live block
map and not the full plan, and that the whole of it is orchestrator-owned
and read-only for workers: they read it, they never write to it.

The dispatch prompt itself is only a pointer to that file: it names the unit
worktree's absolute path and the brief file's path, and instructs the worker
to read the brief file first — it never restates the brief's content inline.

Reports mirror briefs the other way: on receiving a worker's final report,
archive it verbatim to `.local/reports/NN-<wave>-<blocks>.md` — the same
`NN` as the brief it answers — before acting on the report in any way. Both
outlive the unit worktree itself: once the unit merges (step 4), `merge`
copies `.local/briefs/`, `.local/reports/`, and `.local/status.md` into
`.local/units/<plan-slug>/<unit-id>/` in the integration worktree before the
unit worktree is removed, so this unit's brief and report history stays
readable long after its worktree is gone.

Workers must `cd` to their unit worktree once at session start, then run all
subsequent Bash commands directly — e.g. `npm test`, not
`cd /path/to/worktree && npm test`. Include this instruction in every worker
brief. Bash permission allowlists match bare commands; compound
`cd <path> && <command>` forms do not match, causing unnecessary permission
prompts.

Group only independent blocks within the unit into one wave; dispatch a
wave's agents in a single message so they run in parallel.

## Unit status file

Every unit worktree carries `.local/status.md`, seeded by `worktree.sh add`
(step 1) at worktree creation. From that point on, mirror every lifecycle
transition for this unit's blocks into `.local/status.md` — Phase, Blocks,
Timeline — in real time, in the same breath as the corresponding update to
the integration worktree's `blocks.md`: the two never drift apart —
a stale status file is a defect.

The Timeline records, as they happen: each brief written (its `NN`, wave,
and blocks), each wave dispatched, each acceptance, each rejection (naming
the specific deficiency and the brief/report `NN`s involved), each
escalation and its resolution, and each phase commit.

## Dispatch order

Blocks group into work units per the block map; units form a dependency
graph via `Deps:`. A unit's worktree cannot be created until every unit it
depends on is accepted and locally merged into the integration branch — the
new worktree branches from the integration branch's current tip, so that's
the only way a dependency's real implementation is actually there for it to
build against. Units with no dependency relationship between them run their
pipelines concurrently: create their worktrees together and dispatch their
waves together.

## The per-unit pipeline

Run every step below inside the unit's own worktree once step 1 has created
it. Never run test-wave or implementation-wave commands, agent dispatches, or
commits against the integration worktree on a unit's behalf — the whole point
of the worktree is that this unit's diff is never entangled with another
unit's, or with the orchestrator's own tree.

### 1. Create the worktree

From the integration worktree, run:

```
${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh add <plan-slug> <unit-id> <unit-slug>
```

This creates the unit branch from the integration branch's current tip (so
previously-accepted dependencies are present as real implementations, not
stubs) and a seeded worktree — any `.local/config.json` override copied
verbatim when present (the committed `.claude/lego.json` base arrives via
checkout), a `.local/unit.md` carrying only this unit's block-map sections,
and this unit's `.local/contracts/` files where they exist — then runs the
effective config's default test command inside the new worktree as a
baseline; a failing baseline fails the whole operation. The worktree's absolute path is the last line of
stdout — capture it; every worker brief for this unit names it.

### 2. Test wave

Dispatch `lego-test-writer` agents for every leaf block in the unit
(engineer-owned blocks included; the engineer implements against the same
tests), briefed per "Worker briefs" above.

Then verify the returned work — inside the unit worktree — against this
checklist before accepting:

1. **Clause coverage.** Open each stub's contract docblock; walk clause by
   clause against the agent's clause-coverage map AND the actual test code.
   Every Behavior/Output/Error/Invariant/Edge-case clause has at least one
   real test.
2. **Contract, not internals.** Spot-read the tests: no private state, no
   imagined implementation mirrored in assertions.
3. **Red discipline, re-run yourself.** Run the repo's test command inside
   the unit worktree. Failures must be assertion or NotImplemented failures;
   import/compile/collection errors reject the wave.

4. **Pipe safety.** Piping a test command (e.g. `bash "$t" 2>&1 | tail -10`)
   replaces `$?` with the exit code of the last pipeline stage (e.g. `tail`,
   always 0), masking the test command's real exit code.

   Never pipe when the exit code matters — run the command on its own,
   capture `$?` immediately, then inspect output separately if needed:

   ```bash
   bash "$t" >/tmp/out.log 2>&1
   status=$?
   tail -10 /tmp/out.log
   ```

   Output redirection (`>/dev/null 2>&1` or to a file) does not create a
   pipe and does not affect `$?` — it is safe and unrestricted.

   Do not rely on `pipefail` as the fix, since it is not guaranteed to be
   set in ad-hoc bash commands. (`PIPESTATUS` is bash-specific and not the
   preferred pattern here.)
5. **Realm purity, mechanical.** Inside the unit worktree, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/realm-check.sh test` (uncommitted-changes
   mode — the worktree holds only this unit's changes, so there's no other
   diff it could mean). Any violation rejects the wave; this also catches
   Bash-based writes the edit hook cannot see.

Because the whole diff in this worktree belongs to one unit, triage is
unambiguous — there's no sibling block's changes to sort out first.

Rejected work goes back to a test-writer, in the same worktree, via a
fresh-`NN` brief naming the specific deficiency — the rejected wave's brief
and report files are never edited or deleted, only superseded by the next
`NN`. Accepted: set the unit's blocks to `Tests Written`
in the integration worktree's block map, then `Tests Verified` once the full
checklist passes, then commit the accepted tests on the unit branch, inside
the unit worktree, with subject exactly:

```
lego(<unit-id>): tests
```

### 3. Implementation wave

Dispatch `lego-implementer` agents in the same worktree, briefed with the
same absolute path per "Worker briefs" above. Engineer-owned blocks are not
dispatched to an agent at this step — see "Engineer-owned blocks" below.

"Suite green" means green in this worktree specifically: sibling blocks
outside this unit exist only as stubs with no tests of their own, so there
are no foreign reds to reason about. Acceptance gate, checked by the
orchestrator, inside the unit worktree:

1. Repo test command green (run it yourself; also typecheck/lint if
   configured).

2. **Pipe safety (same hazard as step 2.3).** Re-run the repo test command
   without piping it through anything (e.g. no `| tail`) before trusting
   `$?` — a masked exit code on this green run is worse than on the red
   run, since it produces a false acceptance of a broken implementation.
   Follow the same pipe-safety pattern as step 2.3: never pipe when the
   exit code matters; capture `$?` from the bare command, redirect output
   to a file or `/dev/null` if you need it out of the way.
3. `${CLAUDE_PLUGIN_ROOT}/scripts/realm-check.sh impl`, run over this wave's
   diff range — zero test-family diffs, mechanically proven. Uncommitted-
   changes mode covers the common case; if an agent left committed WIP on
   the unit branch, pass the diff-range argument explicitly from the branch
   point instead.
4. **Contracts unchanged.** Diff the stub files against the scaffold commit
   (an ancestor of every unit branch) and confirm signatures and contract
   docblocks are untouched — bodies change, surfaces do not. By-eye in v0;
   treat any surface change as a defect unless it went through the
   escalation loop.

   One exception: a **prose block**'s HTML-comment contract, marked
   `(remove at acceptance)` at scaffold time, must be *gone* — the document's
   prose is the implementation, so a surviving contract is a duplicate spec
   every future reader of that file loads. Confirm it was deleted, and that
   anything in it that must outlive the block was moved into the document's
   prose first.
5. Spot-review the diff for quality: contract clauses the tests undercover
   are still binding (workers are told this; verify it on anything security-
   or correctness-critical).

Rejected work goes back to a lego-implementer, in the same worktree, via a
fresh-`NN` brief naming the specific deficiency — same rule as the test
wave: the rejected wave's brief and report files are never edited or
deleted, only superseded by the next `NN`.

Accepted: set `Implemented` in the integration worktree's block map, then
commit the accepted implementation on the unit branch, inside the unit
worktree, with subject exactly:

```
lego(<unit-id>): implementation
```

Then set `Accepted` once the engineer has seen the block-map update.

### 4. Local merge

Merging is always immediate, regardless of delivery mode: as soon as a unit
is `Accepted`, from the integration worktree, run:

```
${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh merge <plan-slug> <unit-id> <unit-slug>
```

This folds the accepted unit branch into the integration branch (`--no-ff`).
Any unit whose `Deps:` this one satisfies can now have its own worktree
created (step 1) — development is never gated on PR review, only on this
local merge.

Once the merge lands, the command archives the unit worktree's
orchestrator-owned audit trail — `briefs/`, `reports/`, and `status.md` —
into `.local/units/<plan-slug>/<unit-id>/` in the integration worktree, then
removes the unit worktree as a best-effort side effect (warns on failure,
never changes the merge exit code). When the archive itself fails, the
command warns and leaves the worktree in place instead of removing it,
since the worktree would otherwise be the only surviving copy of that
record; the merge's own exit code is unaffected either way. The unit
branch is kept regardless — under `main-prs`, `deliver` still needs it to
resolve commits; under `local-only`, it is cleaned up by `clean` at dispatch
completion (see "Done").

### 5. Delivery

`main-prs` mode only. Once every unit in a PR group is `Accepted` and
locally merged, compose the PR content and open the PR.

Before composing the manifest,
merge master into the integration branch before delivery.
This surfaces concurrent changes as merge conflicts rather than silent
reverts. If conflicts arise in files the PR group delivers, apply the
same escalation rule as the Conflicts section: resolve trivial,
mechanical conflicts yourself; escalate anything else to the engineer
with the conflicting paths and a recommendation.

#### 5a. Compose PR content

Before calling `deliver`, the orchestrator composes the PR content — but
composing here means *reading*, not deriving. The branch name, PR title, and
every commit subject come from this PR group's row in the plan document's
Landing strategy section (`.local/plans/NNN-<slug>.md`), written by
`/lego:plan` at plan time: branch name, PR title, member units,
estimated changed lines, commit sequence (one subject per unit per phase),
and — for a group deliberately left over budget — its written
justification.
Re-deriving any of these fresh at delivery time is exactly the behavior this
replaces: it let a group's identity drift from what the engineer approved.
Because the value is read rather than recomputed, the plan document and the
opened PR always agree on branch and title.

Nothing in the PR title, body, commit subjects, or branch name may reference
internal workflow terminology — no `lego`, `B01`, `U01`, `G01`, plan slugs,
block-map field syntax, or any other label a reviewer cannot look up. This
was already enforced when `/lego:plan` recorded the row; reading it verbatim
keeps it enforced here.

**When the plan has no Landing strategy section** — a plan written before
this was required, or a delivery that went off-plan — compose the content
the old way, per the derivation rules below, and then write the resulting
branch, title, and commit subjects back into the plan document, so it stays
the single source of truth for what actually landed.

**PR title.** Read verbatim from the group's Landing strategy row when one
exists. Otherwise (the fallback above), derive it: conventional commit
format `type(scope): description`. The type is `feat`, `fix`, `refactor`,
`chore`, `docs`, or `test`. The scope is optional and describes the area of
the codebase. The description summarizes the change in imperative mood,
drawn from the plan's goal rather than block names.

**PR body.** Fill in a PR template with content from the plan document and
the delivered blocks' contracts. Template resolution order:

1. Check the repo for a PR template at standard GitHub paths (check each,
   case-sensitive): `.github/PULL_REQUEST_TEMPLATE.md`,
   `.github/pull_request_template.md`, `docs/pull_request_template.md`,
   `PULL_REQUEST_TEMPLATE.md`, `pull_request_template.md`.
2. If no repo template exists, use the plugin's default template at
   `${CLAUDE_PLUGIN_ROOT}/templates/pr-body-template.md`.

Fill every section of the resolved template. Write for a reviewer who has
only the diff and this PR description — no access to `.local/`, the planning
session, or the block map. If the plan references GitHub issues, link them.

**Branch name.** Read verbatim from the group's Landing strategy row when
one exists. Otherwise (the fallback above), derive it: conventional format
`type/short-slug` (e.g. `feat/native-symlink-engine`,
`fix/auth-token-refresh`), from the plan's goal.

**Commit subjects.** Read each unit's tests/impl subjects verbatim from the
group's recorded commit sequence when a Landing strategy row exists.
Otherwise (the fallback above), compose one conventional subject per unit
per phase describing its actual content (e.g. `feat(links): add symlink
manifest engine`) — never a phase label like "tests" or "implementation" —
each commit should read as a self-contained description of what it
introduces.

**Errors.** A Landing strategy row that names a branch which already exists
locally, or a title that violates conventional-commit form, is a plan
defect: fix it in the plan document — appending to its Changelog — rather
than silently substituting a different value here.

**Edge cases.** A row written before a mid-dispatch re-plan is superseded by
that re-plan's Changelog entry, which the row must already reflect; if it
doesn't, treat it as the same plan defect, not a value to trust as-is. Under
`local-only` delivery mode, nothing is opened here — the recorded Landing
strategy is simply what the engineer delivers by hand.

#### 5b. Write manifest and deliver

Before writing the manifest, measure this PR group against the size budget
— `deliver` builds the branch, pushes, and opens the PR in one operation, so
this is the last point a size check can still change the outcome:

```
${CLAUDE_PLUGIN_ROOT}/scripts/pr-size-check.sh <base-branch>...<integration-branch> -- <the group's Code paths>
```

The range to measure is the base branch against the integration branch,
scoped to this group's `Code:` paths from `.local/blocks.md` — step 5's sync
(merge master into the integration branch before delivery) already made this
equivalent to the diff `deliver` will actually produce. Act on the result:

- **exit 0** (within budget): proceed to write the manifest and call
  `deliver`.
- **exit 1** (over budget): if the plan's Landing strategy row for this
  group records a written justification, re-run with `--justified` to
  record the overrun explicitly, then proceed — a justified overrun is what
  the engineer already approved at plan time. Otherwise, escalate to the
  engineer with the script's per-file breakdown and a concrete splitting
  recommendation. The orchestrator never waives the budget on its own
  authority; every over-budget group takes one of these two paths, never a
  silent pass.
- **exit 2** (usage or environment error, including `pr-size-check.sh`
  being absent in an older plugin checkout): fix the invocation or the
  environment and re-run. An unmeasured group is not delivered.

An escalation here is a defined outcome, not a pipeline failure — record it
in the plan Changelog and the unit status file's Timeline like any other
escalation. The budget itself is `delivery.prSizeBudget` from the effective
config, resolved by the script.

If master moved between the check and `deliver` by enough to matter, the
step-5 sync above is what keeps the two ranges equivalent — a large move
re-runs the check. A group of one unit whose single block is inherently
oversized still goes through the justified path above; the decision to
accept that is made by the engineer at plan time, not here. Under
`local-only` delivery mode, no PR is ever opened, so the size gate does not
apply — nothing to measure, nothing to deliver.

Write the composed content as a JSON manifest file at
`.local/pr-manifest.json` with this schema:

```json
{
  "title": "<PR title>",
  "body": "<PR body markdown>",
  "branch": "<delivery branch name>",
  "commits": {
    "<unit-id>": {
      "tests": "<commit subject for this unit's tests commit>",
      "impl": "<commit subject for this unit's implementation commit>"
    }
  }
}
```

Then call deliver with the manifest:

```
${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh deliver --manifest .local/pr-manifest.json <plan-slug> <base-branch> <unit-id> <unit-slug> [<unit-id> <unit-slug>...]
```

This builds a delivery branch from master/main containing only complete
blocks — contract, tests, and implementation together, never a bare stub;
that's also what keeps a brownfield "changing" block safe to deliver — and
opens the PR. PRs target master/main only, never any other branch. Raise PR
groups' PRs in dependency order: a group's PR waits until every group it
depends on has its own PR merged.

After the PR is opened, the deliver command removes each delivered unit's
branch and any remaining worktree as a best-effort side effect (warns on
failure, never changes the deliver exit code). Under the normal flow, step
4's `merge` already removed the worktree, so this is a fallback for the
case where one lingered, not the usual path. When a worktree is still
present at this point, the command archives it first — `briefs/`,
`reports/`, and `status.md` into `.local/units/<plan-slug>/<unit-id>/` —
exactly as `merge` does, before removing it. When that archive fails, the
command warns and skips both the worktree removal and that unit's branch
deletion, since a branch checked out in a surviving worktree cannot be
deleted anyway; the deliver exit code is unaffected either way.

Under `local-only`, or when `origin`/`gh` is unavailable under `main-prs`
(warn and degrade), skip PR creation entirely and the engineer delivers
manually. Unit worktrees were already removed by `merge` (step 4); unit
branches are cleaned up by `clean` at dispatch completion (see "Done").

## Composition blocks

Dispatch a composition block's own unit once every child block is locally
merged (step 4). It runs the exact same pipeline — its own worktree, its own
test wave, its own implementation wave (typically thin wiring plus
integration tests against the composition's contract) — in its own unit
worktree. Its PR is naturally last within its subtree: composition is the
feature-activation point.

## Engineer-owned blocks

An engineer-owned block still gets its worktree and test wave exactly as
above — the engineer implements against verified tests, not a hand-wave.
Once its blocks are `Tests Verified`, hand the engineer the unit worktree
itself instead of dispatching a `lego-implementer` agent — the worktree is
the handover, nothing else needs restating: its absolute path,
`.local/status.md` for phase and blocks, and the latest brief in
`.local/briefs/` for what's required and what's already done, all read
straight off the worktree the same way an agent would. The same acceptance
gate and the same delivery apply to what they commit. Sibling units — those
with no dependency on this one — proceed through their own pipelines
meanwhile; this unit's own dependents wait for it exactly as they would for
an agent-implemented unit.

## Conflicts

A merge conflict (step 4) or a delivery conflict (step 5) means two units
touched paths the plan declared disjoint — a decomposition defect, not a
routine event. Resolve only trivial, mechanical conflicts yourself; anything
else is a re-plan: escalate to the engineer with the conflicting paths and a
recommendation.

If master/main moves externally while a feature is mid-flight, sync the
integration branch from master before creating any new unit worktree, so new
units branch from current master.

## Escalation loop

Workers stop and return `STATUS: ESCALATION` rather than design. On receipt:

- **Resolvable within the contract** (ambiguous brief, tooling issue):
  clarify and re-dispatch the same wave, in the same unit worktree, via a
  fresh-`NN` brief naming the specific deficiency.
- **Contract is wrong or the block is mis-sized**: a design change. Take it
  to the engineer with a recommendation; on their decision, append to the
  plan Changelog, re-scaffold the affected blocks, re-run their test wave,
  then re-dispatch (again, a fresh-`NN` brief). Affected dependents get
  re-verified.

  Wait for the engineer's full decision before re-scaffolding or
  re-dispatching. If their response only answers part of the escalation,
  restate the unanswered part rather than proceeding as if it doesn't matter.
- **A test is wrong** (implementer escalation): arbitrate against the
  contract. Test wrong → back to a test-writer, contract clause cited.
  Contract wrong → engineer, as above. Never let an implementer's claim
  weaken a correct test.

Whichever path it takes, the rejected wave's brief and report files stay put
— never edited, never deleted — and the resolution is a new brief at the
next `NN`. That promise outlives the unit worktree: once the unit merges,
`.local/units/<plan-slug>/<unit-id>/` in the integration worktree is where
those files actually live on, so they stay put even after `merge` removes
the unit worktree they were written in.

Log every escalation and its resolution in the plan's Changelog as it
happens, and in the unit worktree's `.local/status.md` Timeline (see "Unit
status file" above) as it happens. Track `Escalated` — and its resolution
back to the normal lifecycle state — in the integration worktree's
`.local/blocks.md` in real time, not after the fact.

## Done

Dispatch is done when: every block is `Accepted`; the integration branch
carries every unit's implementation (all local merges landed); every PR
group is delivered under `main-prs`, or `local-only` is noted as the reason
none were opened; the block map is current; and the plan Changelog records
every deviation.

As a final sweep, run:

```
${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh clean <plan-slug>
```

This removes any lego branches and worktrees that survived the normal flow for
the given plan — scoped to `lego/<plan-slug>/*` and `lego/deliver/<plan-slug>/*`.
It is best-effort (exits 0 always) and safe to run at any time. Use `--all`
instead of `<plan-slug>` for a global sweep across all plans.

Present the engineer a contract-level summary: which blocks exist, what
changed since approval, where the map lives. No lego worktrees remain.
