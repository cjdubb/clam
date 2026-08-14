---
name: dispatch
description: Run the per-unit worktree pipeline over scaffolded lego blocks — worktree, test wave, verification, implementation wave, acceptance, local merge, and (per delivery mode) PR delivery — dependency-ordered and parallel where independent, with orchestrator verification checklists, mechanical realm checks, and the escalation loop. Use after /lego:plan's approval gate passes.
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

Run every checklist below in full: the checklists are what make workers on
the cheaper model tiers safe.

**What the orchestrator never delegates, and never does.** The orchestrator
never implements block internals — a block's body is a worker's work, or the
engineer's — and never changes a contract without the engineer, since a
contract defect travels the escalation loop rather than becoming a quiet edit.
Five verification steps are non-delegable, the orchestrator's own judgment
every time: clause coverage against each contract docblock (step 2), the
prose-contract check on prose blocks (step 3), the implementation spot-review
(step 3), the PR size check (step 5b), and the delivery-diff gate that proves
the delivery branch matches the integration branch on every path it delivers
(step 5b). No script and no worker performs any of these on the
orchestrator's behalf.

## Vocabulary

- **Work unit**: one or more blocks dispatched together (`.local/blocks.md`'s
  `Unit:` field) — the thing that gets one worktree, one branch, one pipeline.
- **Integration branch**: the branch lego was started on, and the branch this
  skill runs from; it accumulates every unit's work via local merges. The
  checkout on that branch is the integration worktree.
- **PR group**: the blocks delivered together as one pull request, once every
  unit in the group is accepted and locally merged.
- **Delivery mode**: how a PR group leaves this repo, recorded by `/lego:plan`
  in the plan document's Landing strategy section — either `main-prs` (open
  PRs against master/main per PR group) or `local-only` (stop at the local
  merge; the engineer delivers manually). The plan document is the only
  source there is: a plan whose Landing strategy section is missing entirely
  means dispatch stops and asks the engineer which mode applies, and never
  guesses a mode from the repo's shape.

## Preconditions

The scaffold gate has passed on the integration branch, every block sits at
`Status: Scaffolded`, and the phase-boundary commit from scaffolding is made.

`.local/blocks.md` on the integration branch is the live block map for the
rest of dispatch. Its state transitions happen there, in real time, as they
occur. A unit worktree's seeded `.local/` — `unit.md`, contracts, and (once
the worktree is created) `status.md` and `briefs/` — is a read-only reference
copy scoped to that unit: orchestrator-owned throughout, never the thing a
worker edits. `.local/reports/` is the single exception, and only for the
file a worker writes its own report to. Nothing in dispatch reads a
configuration file: the block map carries every per-unit command, and the
plan document carries everything else.

That plan document is `.local/plans/NNN-<slug>.md`, and its
Landing strategy section is where dispatch reads how this work is delivered —
which PR groups exist, what each is called, the budget the design was sized
against, and the delivery mode — so the plan the engineer approved and the
delivery that happens cannot drift apart.

**Delivery knowledge is orchestrator-only.** The size budget, the PR
grouping, and the delivery mode are facts the orchestrator reads from that
plan document and acts on itself; none of them may reach a worker-visible
artifact — not a brief, not a seeded unit `.local/`, not an agent definition.
`worktree.sh add` holds up the seeding half mechanically, stripping
`PR group:`, `Est:`, and `Justification:` from the `unit.md` it writes; the
brief half is yours to keep. A worker that can see a budget starts
optimising for the budget instead of for its contract.

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
docblocks), the commands this unit runs — taken from the recorded per-block
`Setup:` and `Test:` fields of this unit's `blocks.md` sections, named as the
literal command line the worker types (a scope-specific monorepo command like
`nx run mylib:unit-test` is recorded on the block, so it reaches the brief
verbatim), never just "the test command" — where tests
conventionally live (test wave) or the test paths (implementation wave), the
required report format (the agents' definitions specify it), and the report
file the worker writes when it finishes —
`.local/reports/NN-<wave>-<blocks>.md`, carrying this brief's own `NN`,
`<wave>`, and `<blocks>`. State explicitly that `.local/` inside the
worktree is a seeded copy scoped to this unit — a `unit.md` carrying only
this unit's block-map sections, plus this unit's contracts — not the live
block map and not the full plan, and that it is orchestrator-owned and read-only for workers everywhere
except that one report file: they read the rest, they never write to it.

The dispatch prompt itself is only a pointer to that file: it names the unit
worktree's absolute path and the brief file's path, and instructs the worker
to read the brief file first — it never restates the brief's content inline.

Every Agent dispatch also passes a teammate name, so the orchestrator can
tear it down later: `<unit-id>-<wave>-<NN>` (e.g. `U04-test-03`), where
`<wave>` is `test` or `impl` and `NN` is the brief this dispatch answers.
This name is the only handle teardown has — matching the brief's `NN` keeps
a release traceable to the brief/report pair it ends.

Reports mirror briefs the other way, and travel the same way: the worker
writes its report file itself, so the orchestrator's receipt signal is the
file appearing on disk, not a message arriving. A worker's final message is
only a notification that the file is there — an optimisation, never a
precondition, because a report sent as a message has been lost outright with
the send reporting success on the worker's side and nothing arriving on
yours. When a report reaches you only as a message — a legacy worker, or one
that died before writing — archive that message verbatim to the same path
yourself, with a note recording that the worker did not write it. A worker
that finished and wrote nothing at all leaves one last resort: recover the
report from its transcript at
`~/.claude/projects/<project>/<session>/subagents/agent-a<name>-<hash>.jsonl`
and archive it the same way. Never edit a report a worker wrote.

However it arrives, a worker's report is a notification, never a gate. The
sole acceptance evidence is the orchestrator's own `wave-check.sh` run,
together with its own reading of the diff and the contracts (steps 2 and 3):
a report's claim that the suite is green is a claim, and acceptance rests on
the run you did yourself. That is why a missing report costs nothing an
orchestrator cannot recover on its own.

An orchestrator that finds no report file chases the worker a single
time — one `SendMessage` ping — then stops chasing and escalates to the
engineer, naming the unit, the outstanding brief's `NN`, and what the
orchestrator was able to verify without the report. A resend can vanish
exactly as the first send did, so a second chase proves nothing; and a
`SendMessage` ping to a worker that is merely idle IS a resume, not a free
nudge — it resumes the worker inside the unit worktree, which the existing
rule not to verify concurrently with a resumed worker already treats as
hazardous, not merely wasteful — the same caution that also keeps you from
blocking on a report in the first place, not a competing one. A report
file that is present but malformed is an ordinary rejection at a fresh
`NN`, the same path as any other rejected wave — not a third handling
path beside absent and message-only.

Brief and report both outlive the unit worktree itself: once the unit merges
(step 4), `merge` copies `.local/briefs/`, `.local/reports/`, and
`.local/status.md` into `.local/units/<plan-slug>/<unit-id>/` in the
integration worktree before the unit worktree is removed, so this unit's
brief and report history stays readable long after its worktree is gone.

Workers must `cd` to their unit worktree once at session start, then run all
subsequent Bash commands directly — e.g. `npm test`, not
`cd /path/to/worktree && npm test`. Include this instruction in every worker
brief. Bash permission allowlists match bare commands; compound
`cd <path> && <command>` forms do not match, causing unnecessary permission
prompts.

Group only independent blocks within the unit into one wave — see
"Scheduling" below for how that wave is actually dispatched (background by
default, with its degrade path).

## Unit status file

Every unit worktree carries `.local/status.md`, seeded by `worktree.sh add`
(step 1) at worktree creation. From that point on, mirror every lifecycle
transition for this unit's blocks into `.local/status.md` — Phase, Blocks,
Timeline — in real time, in the same breath as the corresponding update to
the integration worktree's `blocks.md`: the two never drift apart —
update the status file at every transition.

The Timeline records, as they happen: each brief written (its `NN`, wave,
and blocks), each wave dispatched, each acceptance, each rejection (naming
the specific deficiency and the brief/report `NN`s involved), each
escalation and its resolution, each teammate release, and each phase
commit.

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

**Commit ownership.** The orchestrator makes every commit on a unit branch,
and makes it after its own verification of the work — the phase commits in
steps 2 and 3 are the only commits a unit branch gets. Workers never run
`git commit`: a wave arrives as an uncommitted diff in the unit worktree, and
that diff is what the acceptance gate reads. Worker briefs say so, and no
brief ever asks a worker to commit, push, or branch.

**The review-gated branch of this pipeline.** A block the plan marked
review-gated — one whose contract has no executably assertable clause — runs
the same pipeline with two differences. Its test wave is skipped — step 2
does not run at all — and a skipped test wave is never a silent one: record
the skip and its reason in the block map and in the unit status file's
Timeline, then go straight to step 3. Its acceptance then takes
a dual-acceptance gate in place of the normal one: the orchestrator's own
verification of the artifact against every contract clause, plus the
engineer's explicit acceptance — orchestrator verification alone does not
accept a review-gated block, and neither does the engineer's word alone; both
are required. Everything else — the worktree, realm rules, the commit
subjects, the local merge, delivery — is unchanged, and an engineer-owned
review-gated block takes this same gate, since no one accepts their own block
unilaterally.

### 1. Create the worktree

From the integration worktree, run:

```
${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh add <plan-slug> <unit-id> <unit-slug> [--setup-cmd <cmd>] [--test-cmd <cmd>]
```

This creates the unit branch from the integration branch's current tip (so
previously-accepted dependencies are present as real implementations, not
stubs) and a seeded worktree — a `.local/unit.md` carrying only this unit's
block-map sections with the delivery fields stripped, this unit's
`.local/contracts/` files where they exist, `.local/status.md`, and empty
`.local/briefs/` and `.local/reports/`.

`add` resolves the commands it runs from the block map, not from anywhere
else: the per-block `Setup:` (optional) and `Test:` (required) fields on the
`blocks.md` sections whose `Unit:` matches this unit. It then runs the Setup
phase first when one resolved, and the Test phase after it, inside the new
worktree as the baseline; a failing baseline fails the whole operation and
names which phase failed. Blocks sharing a unit must agree on those fields,
and a unit with no `Test:` anywhere is an error rather than a silent skip —
both are block-map defects to fix in the map.

`--setup-cmd` and `--test-cmd` override the resolved value per key for this
invocation only — the escape hatch for a command the map does not yet record
correctly — and never write back to `blocks.md`. When you reach for one, fix
the block map too, or the next invocation resolves the wrong command again.
The worktree's absolute path is the last line of
stdout — capture it; every worker brief for this unit names it.

### 2. Test wave

Dispatch `lego-test-writer` agents for every leaf block in the unit
(engineer-owned blocks included; the engineer implements against the same
tests) in the background (see "Scheduling"), briefed per "Worker briefs"
above.

The wave's report is a file the worker wrote, not a message it sent: read
`.local/reports/NN-<wave>-<blocks>.md` inside the unit worktree. An absent
report file once the worker has gone idle — not an absent message — is what
tells you to chase, then escalate.

Then verify the returned work — inside the unit worktree — against this
checklist before accepting:

1. **Mechanical gate, one command.** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/wave-check.sh test [diff-range]` inside the
   unit worktree. In test mode it proves the red run is red for the right
   reason (pipe-safe: never piped, exit code captured directly from the bare
   invocation) and realm-pure, in one invocation — the manual pipe-safe
   capture recipe and the separate realm-check.sh run this checklist used to
   spell out by hand are no longer performed that way. Any FAIL rejects the
   wave.
2. **Clause coverage** (the orchestrator's own non-delegable judgment — no
   script performs this). Open each stub's contract docblock; walk clause by
   clause against the agent's clause-coverage map AND the actual test code.
   Every Behavior/Output/Error/Invariant/Edge-case clause has at least one
   real test.
3. **Contract, not internals.** Spot-read the tests: no private state, no
   imagined implementation mirrored in assertions.
4. **Never block on a report.** A worker that has gone idle without writing
   its report file does not hold acceptance hostage: inspect the worktree
   diff, run this whole checklist yourself, and accept or reject on your own
   evidence. Archive a report that lands afterwards with a timing note
   saying when it arrived relative to the decision. Reports have straggled
   in after the PR merged; a session that waits for one stalls indefinitely.
5. **Never verify concurrently with a resumed worker.** Pinging an idle
   worker resumes it, and a resumed test-writer may re-run its own red-run
   proof — including stash-based reverts of shared files — while your run is
   in flight. Your suite then reads a mid-stash tree and reports a flake
   that is really your own doing. If you ping, say exactly what you want:
   report from memory, touch nothing. Then verify sequentially, so your run
   and the worker's never overlap.

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

On the accepted path only, release this unit's test-writer teammate(s) with
`TaskStop`, passing the teammate name as `task_id` — a wave that dispatched
several test-writers releases all of that unit's teammates for that wave,
not just one. Release waits for acceptance rather than firing as soon as a
worker's report arrives, because the escalation loop can still send the
wave back to a worker after a rejection — a worker stays available until
its wave is actually accepted. A rejected wave's re-dispatch gets its own
name at a fresh `NN`, and only the accepted wave's teammates are released.
Once accepted, a worker is never needed again: a re-dispatch is always a
fresh agent on a fresh-`NN` brief, so worker identity is disposable, which
is what makes releasing it here safe. Release is best-effort and
non-fatal, in the same register as the worktree removal in step 4: a
`TaskStop` failure — the teammate already gone, or its name unknown — is a
warning, never a unit failure, and no step here depends on the release
succeeding. This is a unilateral `TaskStop`, not the `SendMessage`
`shutdown_request` handshake: that request is filed under "Protocol
responses (legacy)" and its own tool description says not to originate it
unless asked, and an approved shutdown has an open upstream failure mode
where it does not actually terminate the teammate
(anthropics/claude-code#60199) — `TaskStop` ends it unilaterally instead.

### 3. Implementation wave

Dispatch `lego-implementer` agents in the same worktree, in the background
(see "Scheduling"), briefed with the same absolute path per "Worker briefs"
above. Engineer-owned blocks are not dispatched to an agent at this step —
see "Engineer-owned blocks" below.

The wave's report is a file here too: read
`.local/reports/NN-<wave>-<blocks>.md` inside the unit worktree rather than
waiting on a message. An absent report file once the worker has gone idle —
not an absent message — is what tells you to chase, then escalate.

"Suite green" means green in this worktree specifically: sibling blocks
outside this unit exist only as stubs with no tests of their own, so there
are no foreign reds to reason about. Acceptance gate, checked by the
orchestrator, inside the unit worktree:

1. **Mechanical gate, one command.** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/wave-check.sh impl --scaffold-ref <scaffold
   commit> --stub <path> [--stub <path>...] [diff-range]` inside the unit
   worktree, naming every executable stub this wave touched. In impl mode it
   proves the suite is genuinely green (pipe-safe, same hazard as the test
   wave), realm-pure over this wave's diff range, and — for each named
   `--stub` — that its contract docblock and signatures are unchanged from
   the scaffold commit, all in one invocation. Any FAIL rejects the wave.
   Uncommitted-changes mode covers the common case for the realm check — a
   worker's wave is always an uncommitted diff, per "Commit ownership" above.
   Where the unit branch already carries this unit's earlier phase commit (the
   tests commit from step 2), pass the diff-range argument explicitly from the
   branch point instead, so the range covers both.
2. **Contracts unchanged, prose blocks** (the orchestrator's own
   non-delegable judgment — wave-check.sh's CONTRACT-DIFF reaches only the
   stub paths passed via `--stub`, i.e. executable stubs, and never an
   HTML-comment contract). A **prose block**'s contract runs the opposite
   check: the comment marked `(remove at acceptance)` at scaffold time must
   end up *gone* — the document's prose is the implementation, so a surviving
   contract is a duplicate spec every future reader of that file loads. Here
   the orchestrator deletes it, at acceptance, as part of accepting the block:
   check first that anything inside the comment which must outlive the block
   was moved into the document's own prose, then remove the comment yourself
   in the same commit as the accepted implementation. By-eye; treat any
   surface change on either kind of contract as a defect unless it went
   through the escalation loop.
3. **Spot-review the diff for quality.** Contract clauses the tests
   undercover are still binding (workers are told this; verify it on
   anything security- or correctness-critical).
4. **Never block on a report** (same rule as step 2). An implementer that
   has gone idle without writing its report file does not hold acceptance
   hostage: inspect the diff, run this whole gate yourself, and accept or
   reject on your own evidence. Archive a report that lands afterwards with
   a timing note.
5. **Never verify concurrently with a resumed worker** (same hazard as step
   2). Pinging an idle implementer resumes it, and a worker editing the
   tree underneath your green run costs more than the test wave's phantom
   flake — it is how a broken implementation gets accepted. If you ping, say
   exactly what you want: report from memory, touch nothing. Then verify
   sequentially.

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

Then the orchestrator sets `Accepted` — no one else, and never on a worker's
word: present the engineer the verification evidence first (the
`wave-check.sh` result, what the clause walk and the spot-review found, and
the commit it landed as), and set `Accepted` once the engineer explicitly
acknowledges it. Silence is not acknowledgement.

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

Release this unit's implementer teammate(s) here too, alongside the
worktree removal above — the same lifecycle moment, for the other resource
the unit holds. Use `TaskStop`, passing the teammate name as `task_id`; a
wave with several implementers releases all of them, not just one. This
release is best-effort in the same register as the worktree removal: a
failed `TaskStop` — the teammate already gone, or its name unknown — is a
warning and never changes the unit's outcome, and no merge step depends on
it succeeding. For an engineer-owned block there is no implementer
teammate to release, so this step is vacuous there — not a precondition of
the merge.

### 5. Delivery

`main-prs` mode only — the mode the plan document's Landing strategy records.
Once every unit in a PR group is `Accepted` and
locally merged, compose the PR content and assemble the delivery branch.

**Degrade path.** With no origin or no `gh` available, deliver this group
`local-only` — stop at the local merge — and tell the engineer what was
missing, rather than treating `main-prs` as satisfied.

Before composing the manifest, run `git fetch origin`, then
merge master into the integration branch before delivery.
The fetch comes first and is not optional: merging a stale `origin/master`
reports "Already up to date" and changes nothing, which silently invalidates
every base-relative check that follows — the size check, the version-bump
lint, and the PR diff itself then all measure against a master that has
already moved. The merge surfaces concurrent changes as merge conflicts
rather than silent
reverts. If conflicts arise in files the PR group delivers, apply the
same escalation rule as the Conflicts section: resolve trivial,
mechanical conflicts yourself; escalate anything else to the engineer
with the conflicting paths and a recommendation.

`assemble` builds the delivery branch from the **local** `<base-branch>` ref,
not from `origin/master`, so fast-forward the base checkout as well — when
its tree is clean:

```
git -C <base-worktree> merge --ff-only origin/master
```

A base checkout left behind produces a delivery branch built on a stale base;
the PR's three-dot diff still reads as correct, so nothing downstream catches
it. A refused fast-forward (dirty tree, or a base checkout that has diverged)
is an escalation, not something to force.

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
2. If no repo template exists, compose the body directly from the plan
   document's Landing strategy row and the delivered blocks' headings and
   contracts — the same default `assemble` itself falls back to when the
   manifest omits a body.

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

#### 5b. Write manifest and assemble

Before writing the manifest, measure this PR group against the size budget
— `assemble` builds and gates the delivery branch, so this is the last
point a size check can still change what gets handed off:

```
${CLAUDE_PLUGIN_ROOT}/scripts/pr-size-check.sh --budget <the recorded budget> <base-branch>...<integration-branch> -- <the group's Code paths>
```

The range to measure is the base branch against the integration branch,
scoped to this group's `Code:` paths from `.local/blocks.md` — step 5's sync
(merge master into the integration branch before delivery) already made this
equivalent to the diff `assemble` will actually produce. Act on the result:

- **exit 0** (within budget): proceed to write the manifest and call
  `assemble`.
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
escalation. The budget itself is a plan fact, not a setting: it is the figure
the design was sized against, recorded in the plan document's Landing
strategy section, and it reaches the script only because you pass it as
`--budget`. Omitting the flag measures against the script's own default
instead of against what the engineer approved.

If master moved between the check and `assemble` by enough to matter, the
step-5 sync above is what keeps the two ranges equivalent — a large move
re-runs the check. A group of one unit whose single block is inherently
oversized still goes through the justified path above; the decision to
accept that is made by the engineer at plan time, not here. Under
`local-only` delivery mode, no PR is ever opened, so the size gate does not
apply — nothing to measure, nothing to assemble.

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

Then call assemble with the manifest:

```
${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh assemble --manifest .local/pr-manifest.json <plan-slug> <base-branch> <unit-id> <unit-slug> [<unit-id> <unit-slug>...]
```

This builds a delivery branch from master/main containing only complete
blocks — contract, tests, and implementation together, never a bare stub;
that's also what keeps a brownfield "changing" block safe to deliver.
Assemble PR groups in dependency order: a group is assembled only once
every group it depends on has already been assembled and handed off —
whoever lands them raises PRs in that same order.

The delivery branch must match the integration branch exactly on the paths it
delivers. This gate blocks delivery on failure — the check is:

```
git diff <integration-branch> <delivery-branch> -- <the delivered paths>
```

Empty output is the only pass. Anything else is a defect in the delivery, not
a difference to reason away: it is how a stale base, a restore that reverted
a file, and a unit that contributed nothing have each shipped before.
`assemble` now enforces this mechanically: it compares the branch it built
against the integration tip on every path it restored, and
aborts on any divergence — so an `assemble` that exits 0 has already
passed the gate. Run the diff by hand whenever the PR was produced any other
way. An unverified delivery is not handed over.

After assembly succeeds, the assemble command removes each delivered unit's
branch and any remaining worktree as a best-effort side effect (warns on
failure, never changes the assemble exit code). Under the normal flow, step
4's `merge` already removed the worktree, so this is a fallback for the
case where one lingered, not the usual path. When a worktree is still
present at this point, the command archives it first — `briefs/`,
`reports/`, and `status.md` into `.local/units/<plan-slug>/<unit-id>/` —
exactly as `merge` does, before removing it. When that archive fails, the
command warns and skips both the worktree removal and that unit's branch
deletion, since a branch checked out in a surviving worktree cannot be
deleted anyway; the assemble exit code is unaffected either way.

The assembled branch (`lego/deliver/<plan-slug>/...`, assemble's last
stdout line) is the handoff artifact this step produces; raising a PR from
it — or landing it any other way — happens outside this skill. Unit
worktrees were already removed by `merge` (step 4); unit branches are
cleaned up by `clean` at dispatch completion (see "Done").

## Composition blocks

Dispatch a composition block's own unit once every child block is locally
merged (step 4). It runs the exact same pipeline — its own worktree, its own
test wave, its own implementation wave (typically thin wiring plus
integration tests against the composition's contract) — in its own unit
worktree. Its PR is naturally last within its subtree: the feature only
activates once the composition merges.

## Scheduling

The per-unit pipeline above runs once per unit, but a plan is rarely one
unit: dispatch treats every unit's pipeline as its own independent state
machine and advances whichever one has work ready, rather than stepping
through units one at a time.

**Loop invariant.** At every scheduling moment, every runnable unit — every
unit whose `Deps:` are all locally merged — either has its worktree created
and its next wave in flight, or a recorded reason in its `.local/status.md`.
A runnable unit sitting idle while the orchestrator works a sibling
sequentially is a scheduling defect, not a style choice.

**Background dispatch is the default model.** Every wave dispatch explicitly
requests background execution — `run_in_background: true`, or the harness's
own background-agent mechanism — never left to a harness default. The
orchestrator never waits synchronously on one wave while any other unit has
an actionable stage: a stage that unit can advance right now, whether that
is creating its worktree, dispatching its next wave, verifying a finished
one, or merging.

**Completion and advancement.** A wave's completion signal is its task
notification plus the report file on disk. On each completion, the
orchestrator advances that unit's own pipeline — verify, dispatch the next
wave, merge — while other units' workers run on undisturbed.

**Ceremony overlaps too.** Orchestrator ceremony for one unit —
brief-writing, wave verification, merges, map/status updates — proceeds
while other units' workers run; it does not wait for a quiet moment. This
cross-unit overlap is distinct from the per-unit rule to never verify
concurrently with a resumed worker (steps 2 and 3 above), which continues to
bind unchanged within a unit: overlapping a sibling's workers is never
license to also verify over a resumed worker inside this unit.

**Parking.** The orchestrator ends its turn parking on Awaiting Agent only
when no unit has an actionable stage and at least one background wave is
still outstanding. Ending the turn any earlier abandons schedulable work;
treating any unit as unschedulable while a background wave for it is still
outstanding is the same defect from the other direction.

**Degrade path.** Background dispatch is the default model; the earlier
instruction to dispatch a wave's agents in a single message survives only as
the explicit degrade path for harnesses without background dispatch.

**The standing question rule.** An open engineer question pauses new
dispatches and new verifications only — it does not reach into workers
already in flight, which run to completion regardless; their results simply
wait unverified until every open question is answered.

**Edge cases.**

- A single-unit plan degenerates to the sequential flow above with no extra
  ceremony — there is no sibling to overlap with.
- An engineer-owned unit's implementation phase counts as an outstanding
  wave for scheduling purposes: it never blocks sibling scheduling, exactly
  as an agent-dispatched wave in flight would not.
- An escalated unit parks; sibling units keep scheduling through it unless
  the escalation opens an engineer question — then the standing question
  rule above governs instead.

## Engineer-owned blocks

An engineer-owned block still gets its worktree and test wave exactly as
above — the engineer implements against verified tests.
Once its blocks are `Tests Verified`, hand the engineer the unit worktree
itself instead of dispatching a `lego-implementer` agent — the handover
needs only: the worktree's absolute path,
`.local/status.md` for phase and blocks, and the latest brief in
`.local/briefs/` for what's required and what's already done, all read
straight off the worktree the same way an agent would.

The engineer is the one exception to "the orchestrator makes every commit":
they commit their own implementation on the unit branch, and that commit
carries the exact reserved subject the orchestrator would have used —
`lego(<unit-id>): implementation`, nothing appended, exactly as step 3 spells
it — so delivery can still resolve the unit's commits by subject. The tests
commit stays the orchestrator's own, as always. The same acceptance gate then
applies to what they commit: the orchestrator runs `wave-check.sh impl` over
the result, with the same `--scaffold-ref` and `--stub` arguments an agent
wave would have taken, and works the judgment items itself, before
acceptance. The same delivery applies too.

Sibling units — those
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
