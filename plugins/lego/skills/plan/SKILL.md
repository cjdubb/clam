---
name: plan
description: Plan and decompose a deliverable into lego blocks together with the engineer, materialize the agreed interface drafts as runtime-present stubs carrying full behavioral contracts, run the scaffold gate, and obtain the engineer's approval of the verified design. Use at the start of any feature, fix, or refactor in a repo using the clam workflow. Stub-writing is orchestrator-authored, never delegated; dispatch must not begin before the engineer approves.
---

# Lego Planning

Plan together with the engineer in conversation; never produce the plan document alone.
The output is a shared mental model: which blocks exist, what each promises, and
how they compose into the deliverable — carried all the way to materialized,
gate-passing stubs the engineer approves in one pass. Dispatch begins only
after that approval.

## Standing rules

These rules govern the whole lego engagement — this skill and `/lego:dispatch`
alike:

- **Clarify and verify; never guess.** This is the workflow's central rule.
  The deliverable is what the engineer states in conversation — NEVER inferred
  from branch/worktree names, directory slugs, commit history, or code
  archaeology. Ambiguity at any level (goal, contract, test, tooling) becomes a
  question to the engineer or an escalation to the orchestrator, not an
  assumption. When evidence contradicts what you were told, surface the
  contradiction before acting on either version.
- The orchestrator designs and verifies; it does not implement block internals.
  Workers NEVER design: any ambiguity, mis-sized block, or wrong-seeming test
  is escalated back to the orchestrator, and contract changes go through the
  engineer.
- The engineer may claim any block (Owner: engineer). Same contract, same tests,
  same acceptance gate; sibling blocks proceed against stubs meanwhile. This
  keeps design authorship with the engineer: they implement the blocks that
  matter to them, under the same gates as any worker.
- **Every question must be explicitly answered before proceeding.** When the
  orchestrator poses a question to the engineer, no background agents,
  exploration, or next-step progression may proceed until every question
  receives an explicit answer — partial responses do not count as
  sufficient, and any question left unanswered must be restated to the
  engineer. A question the engineer explicitly declines or skips counts as
  answered; a bare "go" accepting the recommended defaults counts as
  answering all open questions.

## Step 0a: Record plan entry

At skill invocation, BEFORE the Step 0 deliverable dialogue begins, create the
plan-doc stub at `.local/plans/NNN-<slug>.md`, where NNN is the next free
number in `.local/plans/`. Derive the slug from the branch name if one is
available, or use a placeholder slug otherwise — the deliverable is not yet
confirmed, so the slug is provisional and may be renamed once it is. The stub
opens with `Status: Planning` and `Deliverable: TBD`.

If `.local/` does not exist yet — the first invocation of this skill in the
repo — defer this write until immediately after Step 1 creates
`.local/plans/`; do not skip it outright.

On re-invocation for a deliverable already being planned, check
`.local/plans/` for an existing stub before creating a new one — never create
a duplicate plan doc for the same deliverable.

Once Step 0's gate closes and the engineer has confirmed the deliverable,
update the plan doc's `Deliverable:` line with the confirmed restatement,
replacing TBD.

## Step 0: Establish the deliverable — a hard gate

The deliverable is what the engineer says it is, in this conversation, in their
own words. Nothing else is a source for it:

- **NEVER infer the goal** from branch or worktree names, directory slugs,
  ticket-looking strings, commit history, TODO comments, or code inspection.
  A worktree named `fix-missing-zenith-similarity` does not state the
  deliverable; investigating the codebase to reconstruct what it "probably
  means" is still guessing.
- If this skill was invoked with no deliverable stated, ask for it and STOP:
  goal, rough scope, constraints, what done looks like. Do not run a single
  exploration command before the engineer answers.
- If a deliverable was stated but is vague ("improve the recommendations"),
  ask targeted clarifying questions until it is concrete enough to decompose.
- Close the gate by restating the deliverable back in one or two sentences the
  engineer explicitly confirms. That confirmed restatement is what the plan
  document opens with.

Before closing this gate, verify that every question asked during deliverable
scoping has received an explicit answer. Do not launch exploration agents,
begin discovery, or proceed to Step 1 while any question remains unanswered.

This gate is an instance of the workflow's central rule: clarify and verify,
never assume. It applies at every level below this one too — an ambiguous
contract, a surprising repo state, or evidence that contradicts the engineer's
description are all questions to raise, not gaps to fill silently.

## Step 1: Ensure the repo interface exists

The repo interface is layered (full semantics in `docs/config-schema.md`):

- **`.claude/lego.json`** — the committed base config: commands, models,
  testPatterns, delivery mode. Repo facts belong with the repo; because
  this file is committed, every worktree and fresh clone inherits it via
  git checkout, so repo config never needs copying between worktrees.
- **`.local/config.json`** — optional gitignored local override,
  deep-merged over the base: machine-specific values
  (`delivery.worktreeDir`), personal tweaks. Also the escape hatch for a
  repo whose conventions the engineer doesn't control: the whole config
  can live here instead, accepting that it is then per-clone and does not
  survive a fresh clone.
- **`.local/`** otherwise holds session state (block map, plans, per-unit
  seeds) and stays untracked.

If the repo has no `.claude/lego.json` (and no deliberate
`.local/config.json`-only setup), ask the engineer for consent to create
the interface, then:

0. **Keep session state out of the tracked tree.** Append `.local/` to
   `.git/info/exclude` (create the file if absent; skip if the entry
   already exists, the repo's `.gitignore` already covers it, or the repo
   deliberately tracks `.local/` files). A team that wants the block map
   shared can commit `.local/` deliberately; the workflow works identically
   either way.
1. Create `.claude/lego.json`. Autodetect candidates and CONFIRM with the
   engineer before writing; never guess silently:

   | Marker file | Likely commands |
   |---|---|
   | `package.json` | `test`: npm/pnpm/yarn/bun test; `typecheck`: `tsc --noEmit` if tsconfig exists |
   | `pyproject.toml` / `setup.py` | `test`: `pytest`; `typecheck`: `mypy .` if configured |
   | `go.mod` | `test`: `go test ./...`; `build`: `go build ./...` |
   | `Cargo.toml` | `test`: `cargo test`; `build`: `cargo check` |
   | `Gemfile` | `test`: `bundle exec rspec` |
   | `pom.xml` / `build.gradle` | `test`: `mvn test` / `gradle test` |
   | `Makefile` | inspect for `test` target |

   Where the repo has more than one meaningful test command — a monorepo
   (per-package vs affected-wide runs) or multiple test types (unit,
   integration, e2e, storybook) — record them as named variants instead of
   a single string, and agree with the engineer which one is `default`
   (what mechanical checks run; prefer the cheapest tier that needs no
   external infrastructure, usually unit):

   ```json
   "test": { "unit": "...", "integration": "...", "default": "unit" }
   ```

   Scope permutations (`nx run mylib:unit-test`) are constructed at
   dispatch time; config records the repo's test *types*, not every
   permutation.

   Schema: see `docs/config-schema.md` in the plugin; starter in
   `templates/lego.json`. `commands.test` is required; `typecheck`, `build`,
   `lint` optional; `models.testWriter`/`models.implementer` default to sonnet.

   Also ask the engineer for the **delivery mode** (`delivery.mode`):
   `main-prs` — each PR group is raised as a PR to master/main, or
   `local-only` — units are merged locally and the engineer delivers
   manually. `delivery.worktreeDir` (where per-unit worktrees are created)
   is machine-specific: when needed, it goes in the `.local/config.json`
   override, never the committed base.

   Commit `.claude/lego.json` (with the engineer's consent) once confirmed.
2. Create `.local/blocks.md` from `templates/blocks.md`.
3. Create `.local/plans/`.

## Step 2: Brownfield discovery (skip only in an empty repo)

Before decomposing, map the territory the deliverable touches. This begins only
after Step 0's gate has closed; discovery is scoped BY the confirmed
deliverable, never a substitute for one. Explore the existing code (delegate
broad exploration to a subagent) and record the de-facto blocks already there:
for each, its current interface and observed contract.
Classify every existing block the work touches as either:

- **Held invariant** — its contract must not change; other blocks' contracts depend on it.
- **Changing** — its contract will change; this is a design decision the
  engineer must see explicitly.

New blocks must fit the existing composition. If the existing code does not
decompose cleanly, record the seams as they actually are; do not invent a
fictional architecture.

### Step 2a: When discovery invalidates the premise

Discovery sometimes shows that the deliverable does not exist at all: the
work is already done, or the premise collapsed under evidence gathered in
Step 0 or Step 2. That is a finding about the world — factual and citable,
never a preference about whether the workflow suits the task — so record it
as a closure of the plan doc and stop; do not proceed to decomposition. This
is the ONLY exit from planning that produces no blocks, and it is reachable
only from evidence, never from an opinion about the size or shape of the
work.

The evidence must be citable: a merged commit or PR, an observed passing
behavior, a superseding change already in the codebase. "It looks done" is
not evidence — if the deliverable's status is genuinely unclear, decompose
instead and let the uncertainty resolve inside the blocks (see Step 3).

Update the plan doc from Step 0a in place: `Status: Closed (deliverable does not exist)`,
an `Outcome:` summary of what was found, and an `Evidence:` field citing the
commit, PR, or observation that establishes it. Record the same in
`.local/blocks.md` — a note that the plan closed with no blocks and why. As
with an approved block design, the engineer must confirm the closure before
the plan doc is considered closed: the orchestrator proposes and stops, it
never closes the doc unilaterally. Throughout, the plan doc's Status field reflects the closure
— never left reading Planning once the work is known to be done.

If the plan doc from Step 0a is missing when this closure is reached, create
it now before recording the closure — this is a recovery path, not a reason
to skip the record. If the evidence does not actually establish that the
deliverable is void — it merely suggests the work is small, awkward, or a
poor fit for the lego machinery — this closure does NOT apply; decompose
instead (see Step 3).

This closure is reachable only from evidence gathered in Step 0 or Step 2,
never later: once Step 3 decomposition is underway, a change of mind about
the work's value no longer routes here. Watch for these shapes:

- The deliverable collapses during Step 0 clarification, before discovery runs at all.
- Discovery finds the work already merged, but under a different design than
  the one the engineer described — still close, but record the design delta as a follow-up.
- Only part of the deliverable is already done — this closure does not
  apply; decompose the remainder only.

## Step 3: Decompose with the engineer

Work top-down, recursively: the deliverable is a block; split it until you reach
leaves. A **leaf** is a block one agent can implement against one contract,
independently testable through its public interface. A **composition** is a
higher-order block whose contract is about how its children compose; its tests
are integration tests and it is dispatched only after its children are accepted.

A block stays a leaf only if it passes the **leaf test**, three parts read
together as one test: **one contract** — a single coherent behavioral promise;
**one concern** — no "and" joining two separable concerns in its name or summary;
**one worker run** — a single agent session can implement it against its
tests without mid-flight re-briefing. A block that fails the leaf test is not
a leaf; split it further here in Step 3.

For every block, agree with the engineer on:

- **Name and interface draft.** The draft is the content bar every block
  clears: a **signature** sketched in the repo's language — its name, its
  **typed** inputs and outputs, and its **primary error mode**, stated
  together as one bar — plus all six contract clauses drafted a line or two
  each: Behavior, Inputs, Outputs, Errors, Invariants, Edge cases. Sketch
  from what Step 2's discovery recorded — the existing interfaces the block
  sits against are the raw material, not a from-scratch invention. A prose
  or documentation block carries a heading/anchor outline in place of a
  signature; the outline is the only substitution, and the same six clauses
  are drafted under it. Engineer-owned blocks clear the same bar — ownership
  is no exemption. A block presented with no draft, or a prose block with no
  outline, is not plan-complete: a plan defect that blocks Step 7 approval.
  The draft stays a draft — the full contract docblock is still
  written when the stubs are materialized (Step 5), and that docblock, never this sketch, is the
  authoritative contract. A block re-planned mid-dispatch updates its draft and re-passes
  this bar before it is re-scaffolded.
- Dependencies (which other blocks it consumes)
- Kind: leaf or composition
- **Owner: agent or engineer.** Ask which blocks the engineer wants to build
  themselves. Engineer-owned blocks get the same contract and the same tests;
  siblings proceed against stubs, so an engineer block never stalls the wave.
  Offer this as a first-class choice, not an edge case: it is how design
  authorship stays with the engineer, hands-on in the code they care about
  rather than reviewing an agent's output after the fact.
- **Intended file paths**, pairwise disjoint across units. Disjointness is
  what makes parallel dispatch conflict-free by construction; a later merge
  conflict is treated as a planning defect.
- **Unit assignment** (`Unit: U<NN>`): which work unit the block belongs to.
  Default one block per unit; small, related blocks may share a unit and are
  then dispatched to the same agents sequentially.
- **PR group** (`PR group: G<NN>`): default one unit per group; small units
  may be grouped to share one PR to master/main.

### Every deliverable yields at least one block

Decomposition always terminates in at least one block. There is no size
threshold below which the workflow is skipped, and the orchestrator never
asks whether a deliverable is "worth" block decomposition — that question
has no principled answer and is not the orchestrator's to raise. A change
too small to warrant dispatching a worker is still a block: the engineer
claims it (`Owner: engineer`), builds it directly, and it carries the same
contract, the same tests, and the same acceptance gate as any other block.
That direct-change path lives INSIDE the workflow, not as an exit from it —
planning has exactly two terminal states: an approved block design (Step 7),
or the factual closure of Step 2a when the deliverable does not exist.

This step is reached with a confirmed deliverable from Step 0 that Step 2a did not close.
Decomposition here always yields a block design containing >= 1 block,
presented at the Step 7 approval gate. Where a block is trivial or better
done by hand, mark it `Owner: engineer` rather than omitted — it still needs
a name, a contract, and a place in the block map.

If decomposition seems to yield zero blocks, that is one of two things and
neither is an exit: either the deliverable is void (go to Step 2a, with
evidence), or the deliverable is a single block (write it as one). A plan
presented with no blocks and no Step 2a evidence is a defect.

Keep these invariants in view while decomposing:

- Planning never concludes with zero blocks except via Step 2a.
- Size, triviality, and "fit for the machinery" are NEVER grounds for
  skipping decomposition.
- `Owner: engineer` is the direct-change path; it does not bypass the
  contract, the tests, or the acceptance gate.
- One block is a legitimate, complete plan.

Edge cases worth naming explicitly:

- **Single-file, single-line changes:** one block, often `Owner: engineer`.
- **Documentation-only deliverables: still blocks** — see Step 6a
  for the acceptance gate when a block has no red/green cycle.
- Deliverable partly already done: decompose the remainder only.

Before moving to Step 4, confirm that every decomposition question — block
name, dependencies, owner, paths, unit assignment, and PR group — has been
answered by the engineer. Do not write plan artifacts while any remain open.

Decomposition happens HERE and only here. Workers never design; if
implementation later reveals a mis-sized block, it comes back to this skill as a
re-plan, with the engineer.

## Step 3a: Size the blocks and decide the landing strategy

Sizing happens once decomposition is agreed, and it happens before Step 4's
artifacts are written — the plan document is never produced without a landing
strategy behind it. Three things happen here, in order, with the engineer:

1. **Estimate each block's size in changed lines** — implementation plus its
   own tests. These are explicitly rough numbers, a basis for grouping, not a
   promise the mechanical `pr-size-check.sh` gate at delivery time will later
   hold you to. Test volume typically dominates that total — 2-4x the
   implementation's size is a common multiple for behavioral or anchor-style
   suites — so weigh estimates accordingly.

2. **Feed the estimates back into decomposition.** Compare each block against
   the budget — `delivery.prSizeBudget` from the effective config, defaulting
   to 500 changed lines when the config doesn't set one. A block estimated
   over budget is a mis-sized block, and the first remedy is to split it:
   return to Step 3 and break it into smaller blocks, never accept an
   oversized PR by default. Splitting fails only for a genuinely indivisible
   block — one file, a generated artifact — and even then it proceeds only
   with a written justification recorded alongside the group it lands in; an
   absent justification is a defect, not permission to proceed. If a block
   can't be split under budget and has no justification, don't decide it
   alone — that's an escalation to the engineer, not something to resolve by
   picking a number and moving on.

   Independently of the group budget, every block also carries a
   **per-block ceiling** DERIVED from it: `ceiling = floor(prSizeBudget / 2)`
   — default budget 500 gives a default ceiling of **250** — no new config
   key is introduced. A block's Est exactly at the ceiling needs no
   justification; only a strictly-over-ceiling Est triggers the requirement,
   and a rough Est on a prose or config block is not an exemption from the
   ceiling. An over-ceiling block is first split, same as any mis-sized
   block; a genuinely indivisible one instead carries a written
   `Justification:` field, recorded in its block-map entry (Step 4). An
   over-ceiling block with no `Justification:` field is a plan defect that
   blocks Step 7 approval. A block re-planned mid-dispatch re-passes the
   leaf test and the ceiling before it is re-scaffolded.
3. **Form PR groups** whose combined estimate fits the budget — default one
   unit per group, small related units sharing one. For each group, fix its
   landing details now rather than at delivery time: a branch name
   (conventional `type/short-slug` form), a PR title (conventional commit
   form), the member units it carries, its estimated changed lines, and its
   commit sequence — every commit's final human-readable subject, so nothing
   is improvised later. Order groups so a group's dependencies land before
   it. Shared paths that force sequential delivery — a version file every PR
   must bump, a lockfile — constrain grouping and are called out with the
   group they affect.

A deliverable small enough for a single PR still gets this treatment: one group,
sized and recorded the same as any other.

Estimates decide grouping, not acceptance — the mechanical check at delivery
time is what actually gates a PR. Under `local-only` delivery mode, this
section still records the intended grouping even though no PR is ever
raised; the grouping is a design decision independent of whether it ships as
a PR.

## Step 4: Write the artifacts

1. **Plan document** at `.local/plans/NNN-<slug>.md` (NNN = next free number):
   goal, constraints, the block design (table of blocks with contract
   summaries, deps, owner, kind, unit, PR group), the dependency graph / wave
   order derived from `Deps:` (which work units dispatch in parallel), an
   **Interface drafts** section, a **Landing strategy** section, risks and
   open questions, and a Changelog section. Every contract change after
   approval is appended to the Changelog.

   The **Interface drafts** section carries Step 3's drafts to disk: one
   subsection per block, headed by the block's id and name, holding that
   block's sketched signature (or heading/anchor outline, for a prose block)
   and its six drafted clauses verbatim as agreed. It is where the scaffold
   reads the design from; a block with no subsection here is not
   plan-complete.

   Every artifact the plan document references — the decision files it
   cites, the protocols it relies on, sibling plan documents — is carried
   as a relative markdown link resolvable from the plan file's own
   directory, never a bare path or name, so a reader previewing or serving
   the plan reaches what it references in one click. An artifact that does
   not exist yet when the plan is written is linked where it is
   first referenced, not named now and linked once it lands; a reference
   that lives outside the plan's own worktree is a link too, wherever a
   resolvable relative path to it exists.

   The Landing strategy section carries Step 3a's sizing decisions to disk so
   `/lego:dispatch` delivers from a recorded plan instead of improvising
   branch names, titles, and commit subjects at delivery time. It names the
   budget the design was sized against, then one row per PR group: its
   branch name, PR title, member units, and estimated changed lines, plus a
   written justification for any group deliberately left over budget. Each
   group's commit sequence is recorded alongside it — every commit in
   delivery order, with its final human-readable subject. Write this section
   for a reader with no access to the planning conversation: branch names and
   titles are final here, not placeholders. A deliverable small enough for
   one PR still gets the section, with one group in it; a block whose size
   can't be meaningfully estimated (pure prose, config) still gets an `Est:`
   figure, marked rough rather than omitted. If a mid-dispatch escalation
   forces a re-plan, update this section in place and append the change to
   the Changelog.
2. **Block map entries** in `.local/blocks.md`, one per block:

   ```
   ## B<NN> — <name>
   - Status: Planned
   - Owner: agent | engineer
   - Kind: leaf | composition
   - Deps: B<NN>, ... | none
   - Unit: U<NN>
   - PR group: G<NN>
   - Est: <estimated changed lines>
   - Justification: <optional; required only when Est is strictly over the per-block ceiling from Step 3a>
   - Code: <intended path(s)>
   - Contract: <one-line summary; authoritative contract is the docblock at Code>
   - Plan: plans/NNN-<slug>.md
   ```

   The entry format is unchanged by the interface drafts: no draft,
   signature, or outline field is added here. The one-line `Contract:`
   summary stays exactly as it is and serves as an index — it points a
   reader at the block's subsection in the plan document's Interface drafts
   section and at the authoritative docblock at `Code:`, and it is never
   asked to carry the draft itself.

   `Est:` carries the block's estimated changed lines from Step 3a; the same
   field is added to the example entry in `templates/blocks.md` so a fresh
   repo inherits it. `Justification:` is optional — it is written only for a
   block whose Est exceeds the per-block ceiling and cannot be split
   further; a block under the ceiling omits it.

   Status lifecycle: `Planned → Scaffolded → Tests Written → Tests Verified →
   Implemented → Accepted`, with `Escalated` as a side-state that returns to the
   phase that resolves it. Update the map in real time at every transition so the
   engineer always reads current state.

## Materialization

The scaffold **materializes** the interfaces agreed with the engineer in
Step 3. The design already happened there: the plan document's
Interface drafts section carries one draft per block, and scaffolding turns those
drafts into the code-level interfaces the whole flow hangs off —
test-writers test against them, implementers fill them in, and the compiler
(where one exists) proves the design composes. Materializing before the
Step 7 approval gate is what makes that approval strong: the engineer
approves interfaces already proven to compose, not sketches. Scaffolding is
orchestrator work; do not delegate it.

Scaffolding happens on the **integration branch** — the branch lego was
started on. Every work unit's worktree forks from the integration tip, so all
stubs must land there first: each work unit then sees every sibling block's
*stub* but never a sibling's *tests* or *implementation*.

Materialization begins once Step 4's artifacts are written and every block
sits at `Status: Planned`. Stubs stay **uncommitted** until Step 8's
phase-boundary commit: a design the engineer rejects at Step 7 is revised or
discarded from the working tree, never committed.

## Step 5: Write the stubs

For every block, transcribe its agreed draft from the plan's **Interface
drafts** section into its public interface in the repo's language. The draft
is the source: signature, name, and shape come across as agreed, and the
contract docblock is *finalized* from the agreed draft rather than invented
here. Finalizing adds precision — the units, ordering, nullability, and edge
cases a draft leaves loose — and nothing else. New design is not written at
scaffold time; a stub that quietly grows a parameter, a return shape, or a
behavior the draft never carried has bypassed the design agreed with the engineer.

Scaffolding does find things planning missed. When a discovery genuinely
invalidates an agreed signature — the interface cannot express a correct
implementation, or two blocks' drafts do not compose — that is a
return-to-design event, not a scaffold-time redesign: go back to Step 3
with the engineer, revise the draft there, and record the change in the plan
document's Changelog. The same applies to any smaller deviation from an
agreed draft: it is legitimate only once the Changelog says so. A stub
docblock that deviates from its agreed draft with no matching Changelog
entry is a **scaffold defect** — the design silently forked from what was
agreed with the engineer, and Step 7's approval is then uninformed.

If the plan carries no Interface drafts section at all — a plan written
before drafts existed — fall back to authoring the docblocks fresh here,
against the plan's block descriptions, and note the fallback in the plan
Changelog so acceptance knows the contracts were not agreed with the engineer at
plan time.

The transcription obeys two principles:

1. **Runtime-present, deliberately unimplemented.** Tests must be able to import
   and CALL the stub and fail for the right reason. Declaration-only stubs
   (`declare function`, header-only) cannot produce a right-reason red run, so
   bodies exist and fail loudly:

   | Language | Stub body |
   |---|---|
   | TypeScript/JS | `throw new Error("NotImplemented: B<NN>")` |
   | Python | `raise NotImplementedError("B<NN>")` |
   | Go | `panic("NotImplemented: B<NN>")` |
   | Rust | `unimplemented!("B<NN>")` |
   | Ruby/JVM/other | the idiomatic equivalent |

   Supporting types, interfaces, and signatures are written in full; only
   behavior is absent.

2. **Every stub carries a contract docblock** in the language's doc
   convention; a type signature alone does not specify behavior. This
   docblock is the authoritative contract that
   tests and implementations are verified against:

   ```
   Contract: B<NN> <name>
   Behavior:   what it does, stated operationally
   Inputs:     domains, units, preconditions
   Outputs:    exact semantics (ordering, stability, nullability, units)
   Errors:     every failure mode and how it manifests
   Invariants: what always holds (purity, no mutation, idempotency, ...)
   Edge cases: empty, boundary, duplicate, oversized, concurrent, ...
   ```

   Write contracts so a test-writer with NO other context can enumerate the
   clauses and test each one. Ambiguity here surfaces later as worker
   escalations; spend the effort now.

   **Prose blocks are the exception to docblock permanence.** When a block's
   deliverable is a document — a `SKILL.md`, a `README.md`, a template — its
   "doc convention" is an HTML comment, and the prose written below it *is*
   the implementation. A contract left in place there ships as a duplicate of
   the text beneath it, and an HTML comment is invisible only to the markdown
   renderer: every reader that loads the file, Claude included, still pays for
   it. So mark these for removal when you write them:

   ```
   <!-- Contract: B<NN> <name> (remove at acceptance)
   Behavior: ...
   -->
   ```

   A prose block materializes the same way as any other: its agreed draft
   is an outline rather than a signature, and that outline is transcribed as
   the document's skeleton — headings and section order in place, the prose
   itself deliberately absent — with the contract comment above it.

   The implementation wave deletes the comment; acceptance confirms it is
   gone. Anything the contract asserts that must outlive the block — a
   standing editing rule, an invariant with no other home — is moved into the
   document's own prose or a short editing note *before* the contract goes.

Composition blocks are scaffolded too: their stub is the function or module
that composes the children, and their contract describes the
composed behavior.

## Step 6: Run the scaffold gate

**Rung 0: the sizing lint.** Before the composition rungs below run,
re-check the plan's own sizing discipline rather than trusting it from
planning time: run `scripts/blocks-lint.sh` against `.local/blocks.md`
(this presupposes an approved plan's block map already exists — a fresh
repo with no `.local/blocks.md` yet has nothing to scaffold, so the rung
never runs). Exit 0 proceeds to the rungs below. Exit 1 means findings — an
oversized entry with no `Justification:`, a malformed `Est:`, or similar —
and the plan goes back to Step 3, with the engineer, as a sizing defect; it is never
patched silently here, at scaffold time. Exit 2 is an environment or usage
error (a missing block map, a bad `--budget`, e.g.): fix it and re-run, it
says nothing about the plan itself. If `scripts/blocks-lint.sh` is absent —
an older checkout mid an upgrade — rung 0 is skipped with an explicit
warning naming the script, visible in the transcript, never silent. A block
whose `Est:` already carries a `Justification:` for exceeding the
per-block ceiling passes the lint as written; nothing about it is
re-argued here.

Prove the design composes using the **strongest available check**, from the
effective config's commands (`.claude/lego.json` merged with any
`.local/config.json` override — see `docs/config-schema.md`), in this order:

1. `typecheck` — best: interfaces are proven to compose.
2. `build` / compile — good: everything at least resolves and compiles.
3. `lint` or an import/syntax check — weak: files parse and resolve.
4. None available — the gate defers to the test wave's red run (tests importing
   and calling every stub is the first mechanical composition proof).

Record which rung ran in the plan document. Fix scaffold errors here; a scaffold
that fails its gate must not be dispatched.

### Step 6a: Blocks with no red/green cycle

Some blocks carry no executable behavior to verify: prose whose quality is the
deliverable (a README section, guidance text), or configuration whose only
assertion is its own literal content. Planning always produces some of these,
so decide their gate now, at scaffold time, rather than leaving dispatch to
improvise one.

**Decide by clause, not by convenience.** Walk every clause in the block's
contract docblock and ask whether it can be expressed as an executable
assertion. Structural and anchor assertions count as executable — a token,
heading, or ordering check over a prose file is a real test — so a prose
file with anchors is not review-gated; it takes the normal test wave like
any other block.

Reserve review-gated status for blocks where no clause is executably assertable —
never merely because tests would be inconvenient, low-value, or awkward to
write. Content with no assertable structure — README body text carrying no
anchors a script could check, for instance — is review-gated. A block with a
mix of assertable and non-assertable clauses is not review-gated either:
partial testability means the normal wave runs and covers what it can, and
the reviewer covers the remainder at acceptance.

Review-gating is decided at scaffold time, by the orchestrator, and
recorded on the block; it is never a dispatch-time improvisation. The
moment you mark a block review-gated, note it — with the reason — on its
`.local/blocks.md` entry.

A review-gated block's test wave is skipped, and a skipped test wave is
always recorded with its reason; the skip is never silent. Its acceptance
gate replaces the normal one: orchestrator verification of the artifact
against every contract clause, plus explicit engineer acceptance —
orchestrator verification alone does not accept a review-gated block;
both are required. Everything else about the block — realm rules, the
contract docblock, the block-map lifecycle — is unchanged.

This applies identically to engineer-owned blocks. An engineer-owned
review-gated block takes the same gate as any other — the engineer
cannot accept their own block unilaterally, and the orchestrator still
verifies it against every clause before the block can move to `Accepted`.

## Step 7: Approval gate

Present the verified design to the engineer and stop: the plan document, the
block map, the stub docblocks, and which gate rung ran. This is the single
approval of the whole design — annotations and objections route back to
Step 3 for design changes or Step 5 for materialization defects, the gate
re-runs, and the design is re-presented. A rejected design's stubs are
revised or discarded; nothing has been committed. Record the approval
(date + summary) in the plan's Changelog. Dispatch begins only after
explicit approval.

## Step 8: Update state and checkpoint

- Set every scaffolded block to `Status: Scaffolded` and fill in its `Code:`
  field in `.local/blocks.md` with each block's **actual** path(s), verified
  pairwise disjoint across work units. A violation goes back to Step 3
  as a decomposition defect rather than being resolved silently here.
  Before committing, verify that any questions raised during scaffolding —
  contract ambiguities, path-disjointness concerns — have been resolved with
  the engineer.

- Commit the scaffold (with the engineer's consent) as a phase boundary. Clean
  phase-boundary commits are what make realm verification precise in dispatch:
  each wave's diff can then be checked in isolation. This commit is what every
  work unit's worktree forks from — dispatch runs `worktree.sh add` against
  this commit's branch tip.

Then proceed to `/lego:dispatch`.
