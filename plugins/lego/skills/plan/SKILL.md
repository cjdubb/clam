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
   hold you to.
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
   order derived from `Deps:` (which work units dispatch in parallel), a
   **Landing strategy** section, risks and open questions, and a Changelog
   section. Every contract change after approval is appended to the
   Changelog.

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
   - Code: <intended path(s)>
   - Contract: <one-line summary; authoritative contract is the docblock at Code>
   - Plan: plans/NNN-<slug>.md
   ```

   `Est:` carries the block's estimated changed lines from Step 3a; the same
   field is added to the example entry in `templates/blocks.md` so a fresh
   repo inherits it.

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
