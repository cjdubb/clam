---
name: plan
description: Plan and decompose a deliverable into lego blocks together with the engineer. Use at the start of any feature, fix, or refactor in a repo using the clam workflow. Produces an approved plan document and block-map entries; scaffolding must not begin before the engineer approves.
---

# Lego Planning

Planning is a conversation with the engineer, not a document you produce alone.
The output is a shared mental model: which blocks exist, what each promises, and
how they compose into the deliverable. The engineer approves before anything is
scaffolded.

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
