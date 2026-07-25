---
name: plan
description: Plan and decompose a deliverable into lego blocks together with the engineer. Use at the start of any feature, fix, or refactor in a repo using the clam workflow. Produces an approved plan document and block-map entries; scaffolding must not begin before the engineer approves.
---

# Lego Planning

Planning is a conversation with the engineer, not a document you produce alone.
The output is a shared mental model: which blocks exist, what each promises, and
how they compose into the deliverable. The engineer approves before anything is
scaffolded.

## Step 0a: Record plan entry

<!-- Contract: B07 — lego-plan-lifecycle (entry record)
Behavior:
  At skill invocation — BEFORE the Step 0 dialogue — create the plan-doc stub
  in .local/plans/ so the workflow has a disk footprint from its earliest
  moment. This is what prevents a later disk-based reader (make-progress,
  handover, fresh session) from concluding no workflow ran.
Inputs:
  .local/plans/ directory (created by Step 1 on first invocation; if .local/
  does not exist yet, defer this write to immediately after Step 1 creates it).
Outputs:
  .local/plans/NNN-<slug>.md with Status: Planning and deliverable TBD.
  NNN is the next free number in .local/plans/.
Errors:
  If .local/ does not exist and Step 1 has not run, defer — do not fail.
Invariants:
  - The plan doc is created BEFORE the Step 0 deliverable dialogue begins
  - The file exists even if planning concludes without blocks (Step 5a)
Edge cases:
  - First invocation in a repo (no .local/ yet): defer to after Step 1
  - Re-invocation for the same deliverable: do not create a duplicate plan doc
-->

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
  A worktree named `fix-missing-zenith-similarity` is a hint someone once
  encoded, not a spec; investigating the codebase to reverse-engineer what it
  "probably means" is guessing with extra steps.
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

- **Held invariant** — its contract must not change; it is load-bearing context.
- **Changing** — its contract will change; this is a design decision the
  engineer must see explicitly.

New blocks must fit the existing composition. If the existing code does not
decompose cleanly, record the seams as they actually are; do not invent a
fictional architecture.

## Step 3: Decompose with the engineer

Work top-down, recursively: the deliverable is a block; split it until you reach
leaves. A **leaf** is a block one agent can implement against one contract,
independently testable through its public interface. A **composition** is a
higher-order block whose contract is about how its children compose; its tests
are integration tests and it is dispatched only after its children are accepted.

For every block, agree with the engineer on:

- Name and one-line contract summary (the full contract is written at scaffold)
- Dependencies (which other blocks it consumes)
- Kind: leaf or composition
- **Owner: agent or engineer.** Ask which blocks the engineer wants to build
  themselves. Engineer-owned blocks get the same contract and the same tests;
  siblings proceed against stubs, so an engineer block never stalls the wave.
- **Intended file paths**, pairwise disjoint across units. Disjointness is
  what makes parallel dispatch conflict-free by construction; a later merge
  conflict is treated as a planning defect.
- **Unit assignment** (`Unit: U<NN>`): which work unit the block belongs to.
  Default one block per unit; small, related blocks may share a unit and are
  then dispatched to the same agents sequentially.
- **PR group** (`PR group: G<NN>`): default one unit per group; small units
  may be grouped to share one PR to master/main.

Before moving to Step 4, confirm that every decomposition question — block
name, dependencies, owner, paths, unit assignment, and PR group — has been
answered by the engineer. Do not write plan artifacts while any remain open.

Decomposition happens HERE and only here. Workers never design; if
implementation later reveals a mis-sized block, it comes back to this skill as a
re-plan, with the engineer.

## Step 4: Write the artifacts

1. **Plan document** at `.local/plans/NNN-<slug>.md` (NNN = next free number):
   goal, constraints, the block design (table of blocks with contract
   summaries, deps, owner, kind, unit, PR group), the dependency graph / wave
   order derived from `Deps:` (which work units dispatch in parallel), risks
   and open questions, and a Changelog section. Every contract change after
   approval is appended to the Changelog.
2. **Block map entries** in `.local/blocks.md`, one per block:

   ```
   ## B<NN> — <name>
   - Status: Planned
   - Owner: agent | engineer
   - Kind: leaf | composition
   - Deps: B<NN>, ... | none
   - Unit: U<NN>
   - PR group: G<NN>
   - Code: <intended path(s)>
   - Contract: <one-line summary; authoritative contract is the docblock at Code>
   - Plan: plans/NNN-<slug>.md
   ```

   Status lifecycle: `Planned → Scaffolded → Tests Written → Tests Verified →
   Implemented → Accepted`, with `Escalated` as a side-state that returns to the
   phase that resolves it. Update the map in real time at every transition; a
   stale map is a defect.

## Step 5: Approval gate

Present the plan to the engineer and stop. Scaffolding begins only after
explicit approval. If the engineer annotates or objects, revise and re-present.
Record the approval (date + summary) in the plan's Changelog.

Then proceed to `/lego:scaffold`.

## Step 5a: Conclude without blocks (off-ramp)

<!-- Contract: B07 — lego-plan-lifecycle (off-ramp)
Behavior:
  When planning determines no block decomposition is warranted — the
  deliverable collapsed during research, the work is already done, or it's a
  single direct change that doesn't need the lego machinery — record the
  outcome explicitly in the plan doc and close it out. This is the defined
  exit that prevents a silent workflow disappearance.
Inputs:
  The plan doc created in Step 0a. The engineer's confirmation that no
  decomposition is needed (this is still a gate — the orchestrator proposes,
  the engineer confirms).
Outputs:
  Plan doc updated: Status: Concluded (no blocks), outcome summary, rationale,
  pointer to the direct change/PR if one was made. blocks.md updated to
  record that the plan concluded without blocks.
Errors:
  If the plan doc from Step 0a is missing, create it now (recovery path).
Invariants:
  - The off-ramp is an explicit, recorded transition — not a silent exit
  - The engineer must confirm the conclusion (same approval standard as Step 5)
  - The plan doc's Status field reflects the conclusion
Edge cases:
  - Deliverable collapses during Step 0 clarification (before discovery)
  - Deliverable collapses during Step 2 discovery (research reveals no work)
  - Deliverable collapses during Step 3 decomposition (all blocks already exist)
  - Direct change was already made and PR'd before the off-ramp fires
-->

When planning determines that no block decomposition is warranted — the
deliverable collapsed during Step 0 clarification, Step 2 discovery revealed
the work is already done, or Step 3 decomposition found the work is better
served by a single direct change than by the lego machinery — take this
off-ramp explicitly instead of letting the workflow trail off with no record.
This step can be reached from any point in the planning flow: after Step 0
clarification, after Step 2 discovery, or after Step 3 once it turns out all
needed blocks already exist. A direct change may already have been made and
PR'd before the off-ramp fires; that is fine, record it as the outcome.

Update the plan doc from Step 0a in place:

- `Status: Concluded (no blocks)`
- `Outcome:` what was decided and why
- `Rationale:` the rationale for skipping decomposition
- `Direct change:` a pointer to the commit or PR, if one was made

Present the conclusion to the engineer and stop. The engineer must confirm it
before the plan doc is considered closed — the same approval standard Step 5
applies to an approved block design. If the engineer objects, revise and
re-present rather than closing unilaterally.

Update `.local/blocks.md` with a note recording that the plan concluded
without blocks (e.g., a line at the top pointing to the plan doc and its
no-blocks status).

If the plan doc from Step 0a is missing when this step is reached, create it
now before recording the conclusion — this is a recovery path, not a reason
to skip the record.
