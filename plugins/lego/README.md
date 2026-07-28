# lego

Composes software as a tree of contract-first "lego blocks" — units with a
public interface, a written behavioral contract, and internals nothing else
in the system sees — and runs each one through an engineer-supervised,
orchestrator-verified pipeline: plan the decomposition with the engineer,
scaffold every block as a runtime-present but deliberately unimplemented
stub carrying its full contract, then dispatch cheaper, realm-restricted
test-writer and implementer agents per work unit, each in its own dedicated
git worktree forked from the integration branch. Accepted units merge
locally and, under `main-prs` delivery mode, deliver incrementally as PR
groups raised to master/main; a living block map keeps the engineer's
mental model of the system current at the contract level throughout.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install lego@clam
```

Installing changes nothing globally: no writes to `~/.claude/CLAUDE.md` or
any global settings beyond Claude Code's own plugin-enablement entry, and
plain `claude` in any other repo is untouched — enable it only for the
repos where you want the workflow.

Hard prerequisite before the workflow can scaffold or dispatch anything: a
committed **`.claude/lego.json`**, the repo interface that carries
commands, models, and delivery mode. It does not ship with the plugin. The
first `/lego:plan` invocation in a repo detects it's missing and offers to
create it for you; see `/lego:plan` under Commands for the full bootstrap
flow, or copy the plugin's `templates/lego.json` to `.claude/lego.json` and
fill in `commands.test` (the only required field) yourself. Full schema:
`docs/config-schema.md`.

The workflow is deliberately opinionated, with no lightweight path — for
work that doesn't warrant the full plan/scaffold/dispatch machinery, use
plain `claude` instead.

## What to expect

Until an engineer runs `/lego:plan`, the plugin is otherwise inert: no
files are created and no settings are written. Two hooks are active in
every session from install onward:

- **SessionStart** (`scripts/session-context.sh`) injects the workflow's
  standing rules — clarify over guess, workers never design, realm
  restriction is mechanical, contract docblocks are the spec tests are
  checked against, and so on — into every session's context. When the repo
  already has `.local/blocks.md`, it also appends the first 16000 bytes of
  the current block map, so a fresh session (or a subagent) picks up the
  live state of an in-flight plan without being told.
- **PreToolUse** (`scripts/realm-gate.sh`, matcher `Edit|Write|NotebookEdit`)
  is a no-op for the main session and any non-lego agent. It only activates
  for sessions running as a `lego-test-writer` or `lego-implementer`
  subagent — the workers `/lego:dispatch` spawns — where it mechanically
  denies Edit/Write/NotebookEdit calls outside that role's realm
  (test-writers may touch only test-family files; implementers may never
  touch them) and, for both roles, denies any write under a `.local/` path
  segment, since that tree is orchestrator-owned and read-only for workers.

Once `/lego:plan` runs, it writes the committed `.claude/lego.json` (with
your consent) and gitignored session state under `.local/` (block map,
plans) — excluded from the tracked tree via `.git/info/exclude` by default;
a team that wants the block map shared can remove that exclude entry and
commit `.local/` deliberately.

## Common workflows

### Bootstrap a repo for the workflow

Run `/lego:plan` for the first time in a repo. It detects the missing
`.claude/lego.json`, autodetects candidate test/build/typecheck/lint
commands from marker files (`package.json`, `pyproject.toml`, `go.mod`,
…), and asks your consent before writing and committing it — then proceeds
straight into planning.

### Plan and scaffold a deliverable

`/lego:plan` is a conversation, not a document you get alone: the engineer
states the deliverable, the skill decomposes it into blocks (with
dependencies, an owner — agent or engineer — and a unit/PR-group
assignment) top-down until every leaf is one agent's worth of work, and
stops for your approval. `/lego:scaffold` then turns the approved design
into runtime-present stubs carrying full contract docblocks and proves the
design composes with the strongest available check (typecheck > build >
lint > the test wave's own red run).

### Dispatch, verify, and merge a work unit

`/lego:dispatch` runs each work unit through its own pipeline in a
dedicated worktree: a test wave writes tests against the stub's contract,
the orchestrator verifies clause coverage and realm purity before
accepting; an implementation wave then makes them pass, verified the same
way plus a check that contracts stayed unchanged; accepted units merge
locally into the integration branch, and (under `main-prs` delivery) PR
groups are raised to master/main once every unit in the group is merged.
Watch `.local/blocks.md` for status as it happens.

### Take a block yourself

Mark a block `Owner: engineer` at plan time. It still gets its own worktree
and test wave exactly like an agent-owned block; once its tests are
verified, the orchestrator hands you the worktree instead of dispatching a
`lego-implementer` — same contract, same tests, same acceptance gate.

## Commands

### Skills

**`/lego:plan`** (model-invocable) — Plan and decompose a deliverable into
blocks with the engineer; the deliverable is always what the engineer
states in conversation, never inferred from branch names, slugs, or code
archaeology. Bootstraps the repo interface on first use in a repo:

- **`.claude/lego.json`** (committed): `commands.test` (required — a
  string, or an object of named variants with a `default` key for repos
  with multiple test types or monorepo scopes), `commands.typecheck` /
  `build` / `lint` (optional), `models.testWriter` / `models.implementer`
  (default `sonnet`), `testPatterns` (extra test-family globs, unioned —
  never replaced — with the built-in family), `delivery.mode` (`main-prs`
  or `local-only`; absent behaves as `local-only`).
- **`.local/config.json`** (gitignored, optional): a local override
  deep-merged over the base — machine-specific values like
  `delivery.worktreeDir`, or, for a repo whose conventions you don't
  control, the whole config as a per-clone escape hatch.
- `.local/blocks.md` (seeded from `templates/blocks.md`) and
  `.local/plans/` are created alongside it.

Writes the plan document and block map, and stops for engineer approval
before any scaffolding begins.

**`/lego:scaffold`** (model-invocable) — Orchestrator-only; never
delegated. Turns an approved plan's blocks into stubs — runtime-present,
deliberately unimplemented (e.g. `throw new Error("NotImplemented: B<NN>")`
in TypeScript) — each carrying a full contract docblock (Behavior, Inputs,
Outputs, Errors, Invariants, Edge cases), then proves the design composes
using the strongest available check from the effective config: `typecheck`
> `build` > `lint` > none (defers to the test wave's red run). Commits the
scaffold as the phase boundary every unit worktree forks from.

**`/lego:dispatch`** (model-invocable) — Runs the per-unit pipeline
described under Common workflows above. Notably:

- Every unit gets its own worktree via `scripts/worktree.sh add`, which
  runs the effective config's default test command as a baseline before
  returning the worktree's path.
- Worker briefs are always written to
  `.local/briefs/NN-<wave>-<blocks>.md` before dispatch, and reports
  archived verbatim to `.local/reports/NN-<wave>-<blocks>.md`.
- Escalations (`STATUS: ESCALATION`) come back to the orchestrator rather
  than being resolved by a worker; a wrong contract goes to the engineer, a
  wrong test goes back to a test-writer.
- Ends with `scripts/worktree.sh clean`, a best-effort sweep that removes
  any lego branches/worktrees left over from the run.

### Hooks

**PreToolUse — `scripts/realm-gate.sh`** (matcher `Edit|Write|NotebookEdit`):
see "What to expect." Denies file writes outside a lego worker's realm and
any write under `.local/`; falls back to `sed`-based field extraction
without `jq`; always exits 0, communicating a denial through the hook's
JSON output rather than a nonzero exit.

**SessionStart — `scripts/session-context.sh`** (no matcher): see "What to
expect." Injects the standing rules plus, when present, the current
`.local/blocks.md`.

### Scripts

**`scripts/worktree.sh`** — the unit-worktree lifecycle. Run from the
integration worktree's repo root:

- `add <plan-slug> <unit-id> <unit-slug>` — creates the unit branch
  `lego/<plan-slug>/<unit-id>-<unit-slug>` at the current HEAD and a
  worktree at `<worktreeDir>/<repo-basename>-<unit-id>`
  (`delivery.worktreeDir` from the effective config, default the repo
  root's parent directory), seeds its `.local/` (a scoped `unit.md`, this
  unit's contracts, any `.local/config.json` override), runs the baseline
  test command, and prints the worktree's absolute path.
- `merge <plan-slug> <unit-id> <unit-slug>` — merges the unit branch into
  the current branch with `--no-ff` (commit message
  `lego: merge <branch-name>`); refuses when the working tree has
  uncommitted tracked changes; best-effort removes the unit worktree
  afterward.
- `deliver --manifest <path> <plan-slug> <base-branch> <unit-id>
  <unit-slug> [...]` — builds a delivery branch from `<base-branch>`,
  restoring each unit's `- Code:` paths from its `lego(<unit-id>): tests`
  and `lego(<unit-id>): implementation` commits, pushes it to `origin`, and
  opens a PR with `gh pr create`. The manifest (written by the orchestrator
  to `.local/pr-manifest.json`) supplies the title, branch name, and
  commit subjects — required — plus an optional body (falling back to
  `blocks.md` headings and contracts). Best-effort removes delivered
  units' branches and worktrees afterward.
- `remove <plan-slug> <unit-id> <unit-slug>` — removes one unit's worktree
  and branch directly (fails on a dirty tree or an unmerged branch).
- `clean` — best-effort removes every fully-merged `lego/*/*` and
  `lego/deliver/*/*` branch and its worktree; always exits 0.

**`scripts/realm.sh <path>`** — the single source of truth for the
test-file family: basenames `*.spec.*`, `*.test.*`, `*_test.*`,
`*_spec.*`, `test_*`, plus any path with a `__tests__/` segment, unioned
with `testPatterns` from the effective config (requires `jq`; silently
skipped without it). Prints `test` or `impl`. The gitignored override
file's location can be redirected via `$LEGO_CONFIG` (default
`.local/config.json`) — an internal seam used by this plugin's own test
fixtures, not something you set by hand.

**`scripts/realm-check.sh <test|impl> [diff-range]`** — the mechanical,
post-hoc realm check the orchestrator runs at every wave boundary (catches
Bash-based writes the PreToolUse hook can't see): with no diff-range,
checks all uncommitted changes; with one, checks the files changed in that
range. Exits 1 with one `VIOLATION:` line per offending file, 2 on a usage
error.

**`scripts/pr-size-check.sh [--budget <n>] [--justified] <diff-range> [--
<pathspec>...]`** — measures a diff range's total changed lines against
`delivery.prSizeBudget` (effective config, default 500) or an explicit
`--budget`, and reports PASS/FAIL/WARN with a per-file breakdown when over
budget. `--justified` turns an over-budget FAIL into a WARN and exits 0.
Exit 0 within budget (or over but justified), 1 over budget, 2 on a usage
or environment error.

### Agents

**`lego-test-writer`** (default model `sonnet`, override with
`models.testWriter`) — writes tests against a scaffolded block's contract;
realm-restricted to test-family files only.

**`lego-implementer`** (default model `sonnet`, override with
`models.implementer`) — fills in a scaffolded block's internals to make
the verified tests pass; may never touch a test-family file or change a
public interface or contract.

Both read their brief from `.local/briefs/` inside their unit worktree
first, before any other file, and each reports back in a fixed format —
`STATUS`, `BLOCKS`, and `FILES` in common, plus role-specific fields
(clause coverage and the red run for the test-writer, verification for the
implementer).

## Why it works

- **Clarify over guess.** The deliverable is what the engineer says it is,
  never inferred from branch names, slugs, or repo archaeology. Ambiguity
  at any level (goal, contract, test) becomes a question or an escalation,
  not an assumption. Planning cannot start until the engineer confirms a
  restated goal.
- **Types are not contracts.** Every stub carries a docblock stating
  behavior, inputs, outputs, errors, invariants, and edge cases. Tests are
  verified clause-by-clause against it; cheap workers execute a spec
  written at the frontier tier, they don't invent one.
- **Realm restriction is mechanical, not vibes.** A PreToolUse hook denies
  test-writers any non-test file and implementers any test file; a
  post-hoc diff check (`scripts/realm-check.sh`) catches what the hook
  can't see. An implementer structurally cannot weaken a test to get to
  green.
- **Isolation is mechanical too.** Each work unit is dispatched in its own
  dedicated worktree: a worker cannot even see a sibling block's tests, let
  alone its contract under review. Delivery is incremental — each PR is one
  reviewable chunk of contract + tests + implementation, never a bare stub.
- **Workers never design.** Ambiguity, mis-sized blocks, and wrong-seeming
  tests are escalated to the orchestrator; contract changes go through the
  engineer, always.
- **The engineer can take any block.** Same contract, same tests, same
  acceptance gate; stubs keep every sibling block unblocked meanwhile.

## Tests

```bash
bash plugins/lego/scripts/agent-defs.test.sh
bash plugins/lego/scripts/dispatch-skill.test.sh
bash plugins/lego/scripts/plan-lifecycle.test.sh
bash plugins/lego/scripts/pr-size-check.test.sh
bash plugins/lego/scripts/realm-gate.test.sh
bash plugins/lego/scripts/worktree.test.sh
```

## Layout

```
.claude-plugin/   plugin manifest
skills/           plan, scaffold, dispatch
agents/           lego-test-writer, lego-implementer (sonnet by default)
hooks/            PreToolUse realm gate, SessionStart context injection
scripts/          realm.sh (test-family source of truth), realm-check.sh,
                  realm-gate.sh, session-context.sh, worktree.sh (unit
                  worktree lifecycle + delivery)
templates/        starter .claude/lego.json (lego.json), blocks.md, and
                  pr-body-template.md (default PR body when the repo has
                  no PR template of its own)
docs/             config schema / repo-interface spec
```

History: ported from the clam-v2 repo at v0.3.0; skills renamed from
`/clam:lego-*` to `/lego:*` in the move.

## Relationships to other plugins

No hard dependencies. Despite the overlapping vocabulary, lego does not
consume the worktrees plugin: `scripts/worktree.sh` implements its own
git-worktree lifecycle directly (raw `git worktree` commands), not the
worktrees plugin's `newtree`/`rmtree` helpers. It does not consume the
landing plugin either: `worktree.sh deliver` opens PRs directly with
`gh pr create` rather than through `/landing:land`. And it deliberately
never touches tracking's own files (`.local/PLAN.md`, `TODO.md`) — an
isolation invariant covered by this plugin's own tests.

Two companion plugins optionally consume lego, one-directionally, when
it's installed:

- **tracking**'s `/tracking:make-progress` skill reads `.local/blocks.md`,
  when present, as one of its progress signals — recognizing dispatchable
  blocks (e.g. Scaffolded blocks ready for a test wave) and recommending
  `/lego:dispatch`.
- **build** detects the `plugins/lego` directory at session start and,
  when present, adds plan/scaffold/dispatch context to its briefing; its
  `/build:sync-pr` skill treats PRs opened via lego's own delivery step
  as one of the paths whose description it keeps in sync, alongside
  `/landing:land` and manual `gh pr create`.

## Uninstalling

```
/plugin uninstall lego@clam
```

Before uninstalling, run `${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh clean`
to remove any unit worktrees/branches left over from an interrupted run —
`${CLAUDE_PLUGIN_ROOT}` stops resolving once the plugin is gone. The
committed `.claude/lego.json` and the gitignored `.local/` (block map,
plans) are not removed by uninstalling or by `clean`; delete them by hand
if you want no trace.
