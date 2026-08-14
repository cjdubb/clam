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
mental model of the system current at the contract level throughout. The
division of labor is deliberate: the engineer designs the block graph in
conversation before any code exists, so the shape of what ships is theirs,
and the agents supply the labor inside it.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install lego@clam
```

Installing changes nothing globally: no writes to `~/.claude/CLAUDE.md` or
any global settings beyond Claude Code's own plugin-enablement entry, and
plain `claude` in any other repo is untouched — enable it only for the
repos where you want the workflow.

There is no settings file to write first, and nothing to keep in sync: the
plugin ships no repo interface of its own. The first `/lego:plan`
invocation discovers the repo's setup and test commands from its marker
files, agrees them with you, runs each one to prove it works, and records
them **per block** on the block map — a `Setup:` line (optional) and a
`Test:` line (required, one per block). See `/lego:plan` under Commands
for the full flow.

The workflow is deliberately opinionated, with no lightweight path — for
work that doesn't warrant the full plan/scaffold/dispatch machinery, use
plain `claude` instead.

## What to expect

Until an engineer runs a lego skill, the plugin is inert: no files are
created, no settings are written, and no plugin-wide hooks run. The
workflow's standing rules — clarify over guess, workers never design, realm
restriction is mechanical, contract docblocks are the spec tests are
checked against, and so on — are stated inside each skill itself, so a
skill carries everything it needs at invocation; the skills likewise pick
up the live block map from `.local/blocks.md` themselves.
Nothing lego-related enters a session's context until a lego skill is
activated.

The one hook the plugin ships never touches the main session: the realm gate
(`scripts/realm-gate.sh`, matcher `Edit|Write|NotebookEdit`) is registered
in the frontmatter of the two agent definitions rather than plugin-wide, so
it runs only inside `lego-test-writer` and `lego-implementer` subagents —
the workers `/lego:dispatch` spawns. There it mechanically denies
Edit/Write/NotebookEdit calls outside that role's realm (test-writers may
touch only test-family files; implementers may never touch them) and, for
both roles, denies any write under a `.local/` path segment, since that
tree is orchestrator-owned and read-only for workers. One path is carved
out: a worker's own report file under `.local/reports/`, which it writes
itself and which the gate allows ahead of every other rule, for both roles.

Once `/lego:plan` runs, everything it writes is gitignored session state
under `.local/` (block map, plans) — excluded from the tracked tree via
`.git/info/exclude` by default; a team that wants the block map shared can
remove that exclude entry and commit `.local/` deliberately. Nothing lands
in the repo's committed tree until the work itself does.

## Common workflows

### Bootstrap a repo for the workflow

Run `/lego:plan` for the first time in a repo. It autodetects candidate
setup/test/build/typecheck/lint commands from marker files
(`package.json`, `pyproject.toml`, `go.mod`, …), confirms them with you,
and runs each one to see it pass before anything is recorded — then
proceeds straight into planning. No file is committed on your behalf; the
proved commands become per-block fields on the block map instead.

### Plan and scaffold a deliverable

`/lego:plan` is a conversation, not a document you get alone: the engineer
states the deliverable, the skill decomposes it into blocks (with
dependencies, an owner — agent or engineer — and a unit/PR-group
assignment) top-down until every leaf is one agent's worth of work, sizes
each block in changed lines against the PR budget (splitting anything over
it) and settles a landing strategy per PR group — branch name, PR title,
and commit sequence. Every block also gets an **interface draft** — its
signature plus a drafted line or two of all six contract clauses — recorded
in the plan document's Interface drafts section, agreed with you in
conversation as they are drafted. The same skill then materializes those
agreed interface drafts into runtime-present stubs carrying full contract
docblocks, transcribing that design rather than inventing a new one, and
proves the design composes with the strongest available check (typecheck >
build > lint > the test wave's own red run). Only then does it stop for
your approval: one decision, on a design already proven to compose. Stubs
written before approval stay uncommitted, so a rejected design is discarded
by dropping them; the approved scaffold is committed as the phase boundary
every unit worktree forks from.

### Dispatch, verify, and merge a work unit

`/lego:dispatch` runs each work unit through its own pipeline in a
dedicated worktree: a test wave writes tests against the stub's contract,
the orchestrator verifies clause coverage and realm purity before
accepting; an implementation wave then makes them pass, verified the same
way plus a check that contracts stayed unchanged; accepted units merge
locally into the integration branch, and (under `main-prs` delivery) PR
groups are raised to master/main once every unit in the group is merged.
Scheduling across units is **background-first**: every wave dispatch runs in
the background, and the orchestrator advances whichever unit has an
actionable stage right now rather than waiting synchronously on one unit
while a sibling sits idle — ending its turn only once no unit has an
actionable stage and at least one background wave is still outstanding.
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
archaeology. On first use in a repo it establishes the commands the later
waves run, then creates `.local/blocks.md` (seeded from
`templates/blocks.md`) and `.local/plans/`.

The commands are **proved by execution** before they are recorded: the
skill autodetects candidates from marker files, agrees them with the
engineer, and runs each one exactly once — a command that fails, hangs, or
turns out not to exist goes back to the engineer as a question, never into
the plan as an assumption. What survives that proof is written down at
plan time, per block, on the block map entry:

- **`Test:`** — required of every block: the command that runs this
  block's tests. It is the only place any wave reads a test command from,
  and a unit whose blocks record no `Test:` is a block-map defect, not a
  silent skip.
- **`Setup:`** — optional: the command that prepares the environment
  before the tests run, written only where the repo needs one. Blocks
  sharing a unit must agree on both fields.

Sizes each block in changed lines against the **PR size budget** and splits
anything over it, then records the **Landing strategy** in the plan
document: the budget the design was sized against and the delivery mode the
work lands under (`main-prs` or `local-only`) — the two plan facts with no
home anywhere else — plus branch name, PR title, member units, and commit
sequence per PR group. Budget and mode are decisions of the plan, agreed in
conversation and read back from it at delivery, never settings resolved at
run time. Writes the plan document and block map, then materializes the
agreed interface drafts as stubs — runtime-present, deliberately
unimplemented (e.g. `throw new Error("NotImplemented: B<NN>")` in
TypeScript) — each carrying a full contract docblock (Behavior, Inputs,
Outputs, Errors, Invariants, Edge cases). Materialization is
orchestrator-only, never delegated. It proves the design composes using the
strongest available check among the commands the plan proved (`typecheck` >
`build` > `lint` > none, deferring to the test wave's red run), stops for
engineer approval of the verified design, and commits the approved scaffold
as the phase boundary every unit worktree forks from.

**`/lego:dispatch`** (model-invocable) — Runs the per-unit pipeline
described under Common workflows above. Notably:

- Every unit gets its own worktree via `scripts/worktree.sh add`, which
  resolves the unit's `Setup:`/`Test:` commands from the block map and runs
  them as a baseline before returning the worktree's path. `--setup-cmd`
  and `--test-cmd` override the resolved value for one invocation — the
  escape hatch when the map does not yet record the right command — and
  never write back to the map.
- Worker briefs are always written to
  `.local/briefs/NN-<wave>-<blocks>.md` before dispatch, and each worker
  writes its own report to `.local/reports/NN-<wave>-<blocks>.md` — the
  signal that a wave has reported is that file appearing, not a message
  arriving. Once the unit merges, both are carried forward to
  `.local/units/<plan-slug>/<unit-id>/` in the integration worktree.
- Delivery reads the branch name, PR title, and commit subjects from the
  plan's recorded Landing strategy rather than deriving them fresh, and
  gates every PR group on `scripts/pr-size-check.sh` before calling
  `deliver` — an unjustified over-budget group is escalated to the
  engineer, never opened as-is.
- Escalations (`STATUS: ESCALATION`) come back to the orchestrator rather
  than being resolved by a worker; a wrong contract goes to the engineer, a
  wrong test goes back to a test-writer.
- Ends with `scripts/worktree.sh clean`, a best-effort sweep that removes
  any lego branches/worktrees left over from the run.

### Hooks

**PreToolUse — `scripts/realm-gate.sh`** (matcher `Edit|Write|NotebookEdit`,
registered per-agent in `agents/lego-test-writer.md` and
`agents/lego-implementer.md` frontmatter — the plugin has no plugin-wide
`hooks/hooks.json`): see "What to expect." Denies file writes outside a
lego worker's realm and any write under `.local/` other than the worker's
own report file under `.local/reports/`; falls back to `sed`-based field
extraction without `jq`; always exits 0, communicating a denial through the
hook's JSON output rather than a nonzero exit.

### Scripts

**`scripts/worktree.sh`** — the unit-worktree lifecycle. Run from the
integration worktree's repo root:

- `add <plan-slug> <unit-id> <unit-slug> [--setup-cmd <cmd>]
  [--test-cmd <cmd>]` — creates the unit branch
  `lego/<plan-slug>/<unit-id>-<unit-slug>` at the current HEAD and a
  worktree at `<repo-root-parent>/<repo-basename>-<unit-id>`, seeds its
  `.local/` (a scoped `unit.md` carrying this unit's block-map sections
  with the delivery fields stripped, this unit's contracts), runs the
  unit's `Setup:` command (when one is recorded) and then its `Test:`
  command as the baseline, and prints the worktree's absolute path. Both
  commands are resolved from the block map's own fields; the two flags
  override them for this invocation only.
- `merge <plan-slug> <unit-id> <unit-slug>` — merges the unit branch into
  the current branch with `--no-ff` (commit message
  `lego: merge <branch-name>`); refuses when the working tree has
  uncommitted tracked changes. Afterward it archives the unit worktree's
  `briefs/`, `reports/`, and `status.md` to
  `.local/units/<plan-slug>/<unit-id>/` in the invoking worktree, then
  best-effort removes the unit worktree. A failed archive skips removal
  instead, warning on stderr rather than destroying the only copy of that
  record.
- `assemble --manifest <path> <plan-slug> <base-branch> <unit-id>
  <unit-slug> [...]` — builds a delivery branch from `<base-branch>`,
  restoring the files each unit's `lego(<unit-id>): tests` and
  `lego(<unit-id>): implementation` commits changed, derived from each
  commit's own diff. Merge commits are never resolved as a unit's commit,
  and a resolved commit that restores no files fails the build rather than
  contributing nothing. Before finishing, the built branch must match the
  integration tip byte for byte on every path it restored; any divergence
  aborts the build with nothing left behind. Assemble stops once the branch
  is built and gated — no push, no PR, no `gh` invocation anywhere in the
  script — and prints the assembled branch name as its last stdout line.
  The manifest (written by the orchestrator to `.local/pr-manifest.json`)
  supplies the title, branch name, and commit subjects — required — plus
  an optional body (falling back to `blocks.md` headings and contracts). Afterward,
  best-effort removes each delivered unit's branch and any remaining
  worktree — a worktree still present at that point is archived first, the
  same as `merge`, to `.local/units/<plan-slug>/<unit-id>/`; a failed
  archive skips removal of both the worktree and the branch.
- `remove <plan-slug> <unit-id> <unit-slug>` — archives the unit worktree's
  `briefs/`, `reports/`, and `status.md` to
  `.local/units/<plan-slug>/<unit-id>/`, then removes the worktree and
  branch directly (fails on a dirty tree or an unmerged branch). Unlike
  `merge` and `assemble`, this path is not best-effort: a failed archive
  exits nonzero and removes nothing.
- `clean <plan-slug>` — best-effort removes every fully-merged branch of
  that plan (`lego/<plan-slug>/*` and `lego/deliver/<plan-slug>/*`) and its
  worktree; always exits 0. `clean --all` widens the sweep to every
  `lego/*/*` and `lego/deliver/*/*` branch.

**`scripts/realm.sh <path>`** — the single source of truth for the
test-file family: basenames `*.spec.*`, `*.test.*`, `*_test.*`,
`*_spec.*`, `test_*`, plus any path with a `__tests__/` segment. The family
is built in and fixed — there is nothing to extend it with and nothing to
keep in sync. Prints `test` or `impl`.

**`scripts/realm-check.sh <test|impl> [diff-range]`** — the mechanical,
post-hoc realm check the orchestrator runs at every wave boundary (catches
Bash-based writes the PreToolUse hook can't see): with no diff-range,
checks all uncommitted changes; with one, checks the files changed in that
range. Exits 1 with one `VIOLATION:` line per offending file, 2 on a usage
error.

**`scripts/pr-size-check.sh [--budget <n>] [--justified] <diff-range> [--
<pathspec>...]`** — measures a diff range's total changed lines against
`--budget` when given, else the built-in default of 500 — pass the budget
the plan recorded — and reports PASS/FAIL/WARN with a per-file breakdown
when over budget. `--justified` turns an over-budget FAIL into a WARN and exits 0.
Exit 0 within budget (or over but justified), 1 over budget, 2 on a usage
or environment error.

**`scripts/wave-check.sh <test|impl> [--test-cmd "<command>"] [options]
[diff-range]`** — the mechanical half of a wave gate in one command: mode `test` proves the red
run is red for the right reason (never a collection/import failure) and
realm-pure; mode `impl` proves the suite is green, realm-pure, and, with
`--scaffold-ref` and one or more `--stub`, that contract docblocks and
signatures are unchanged from the scaffold commit. The command it runs is
`--test-cmd` when given, else the `Test:` field of the unit worktree's
seeded `unit.md`; when neither resolves it exits with an error rather than
skipping silently. One `WAVE-CHECK <CHECK>: PASS|FAIL|SKIPPED` line per
check plus a summary verdict.

**`scripts/blocks-lint.sh [--budget <n>] [path/to/blocks.md]`** — the
plan-time sizing lint: every block entry needs a bare-integer `Est:`, and
every entry whose `Est` exceeds the **per-block ceiling** — derived, never
configured, as half the PR size budget — needs a non-empty
`Justification:`. The budget is `--budget` when given, else the built-in
default of 500.
Run once at plan time and again as rung 0 of the scaffold gate (see
`skills/plan/SKILL.md`), so a plan that shrank a budget after sizing its
blocks can't slip an unjustified oversized block through to dispatch. Exit
0 clean, 1 on findings, 2 on a usage or environment error.

### Agents

**`lego-test-writer`** (model `sonnet`, set in the agent definition's
frontmatter) — writes tests against a scaffolded block's contract;
realm-restricted to test-family files only.

**`lego-implementer`** (model `sonnet`, set the same way) — fills in a
scaffolded block's internals to make the verified tests pass; may never touch a test-family file or change a
public interface or contract.

Both read their brief from `.local/briefs/` inside their unit worktree
first, before any other file, and each writes its report to the
`.local/reports/` path that brief names — the one place under `.local/` a
worker may write — in a fixed format: `STATUS`, `BLOCKS`, and `FILES` in
common, plus role-specific fields (clause coverage and the red run for the
test-writer, verification for the implementer). A worker's final message is
only a one-line notification of that path, never the report itself.

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
- **Design authorship stays with the engineer.** Interfaces, contracts,
  and dependencies are settled in conversation before any code exists, so
  the engineer's understanding of the system is formed at design time
  rather than reverse-engineered at review time out of a diff an agent
  produced. That is the answer to this era's failure mode: the engineer as
  detached reviewer, approving code they never shaped.
- **The engineer can take any block.** Same contract, same tests, same
  acceptance gate; stubs keep every sibling block unblocked meanwhile.
  Marking a block `Owner: engineer` is how the engineer stays hands-on
  where it matters, building the blocks they care about themselves without
  holding up the parallel waves around them.

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
skills/           plan, dispatch
agents/           lego-test-writer, lego-implementer (model sonnet);
                  frontmatter registers the PreToolUse realm gate
scripts/          realm.sh (test-family source of truth), realm-check.sh,
                  realm-gate.sh, worktree.sh (unit worktree lifecycle +
                  delivery)
templates/        blocks.md (the starter block map)
```

History: ported from the clam-v2 repo at v0.3.0; skills renamed from
`/clam:lego-*` to `/lego:*` in the move.

## Update

```
/plugin marketplace update clam
claude plugin update lego@clam
```

Both commands are needed: refreshing the catalog never touches an installed
plugin, and updating one is CLI-only — there is no `/plugin update`.
Afterwards run `/reload-plugins` to pick the new version up in the current
session, or restart the session if this plugin ships hooks or agents.

Auto-update is off by default for third-party marketplaces. Even with it
enabled, a plugin that ships hooks stays pinned to the last explicitly
installed version until you run the update command yourself
(anthropics/claude-code#52218).

## Relationships to other plugins

No hard dependencies. Despite the overlapping vocabulary, lego does not
consume the worktrees plugin: `scripts/worktree.sh` implements its own
git-worktree lifecycle directly (raw `git worktree` commands), not the
worktrees plugin's `newtree`/`rmtree` helpers. It does not consume the
landing plugin either: `worktree.sh assemble` stops once it has built and
gated a delivery branch — landing it (via `/landing:land` or by hand)
happens outside lego. And it deliberately never touches tracking's own
files (`.local/PLAN.md`, `TODO.md`) — an isolation invariant covered by
this plugin's own tests.

Two companion plugins optionally consume lego, one-directionally, when
it's installed:

- **tracking**'s `/tracking:make-progress` skill reads `.local/blocks.md`,
  when present, as one of its progress signals — recognizing dispatchable
  blocks (e.g. Scaffolded blocks ready for a test wave) and recommending
  `/lego:dispatch`.
- **build** detects the `plugins/lego` directory at session start and,
  when present, adds plan/scaffold/dispatch context to its briefing; its
  `/build:sync-pr` skill treats PRs opened from a branch lego assembled
  as one of the paths whose description it keeps in sync, alongside
  `/landing:land` and manually opened PRs.

## Uninstalling

```
/plugin uninstall lego@clam
```

Before uninstalling, run
`${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh clean --all` to remove any unit
worktrees/branches left over from an interrupted run —
`${CLAUDE_PLUGIN_ROOT}` stops resolving once the plugin is gone. Nothing
committed is left behind — lego writes no settings into the repo — but the
gitignored `.local/` (block map, plans) survives both uninstalling and
`clean`; delete it by hand if you want no trace.
