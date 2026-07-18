# lego — the lego workflow for Claude Code

A technology-agnostic Claude Code plugin for engineers who want to stay in the
loop. Software is treated as a composition of **lego blocks**: units with a
public interface, a written behavioral contract, and internals the rest of the
system never sees. Blocks are recursive; integration is just a higher-order
block with its own contract and tests.

The engineer and an orchestrator (your main session, presumed frontier-tier)
plan and decompose the deliverable together. The orchestrator scaffolds every
block as a runtime-present, deliberately unimplemented stub carrying its full
contract, then dispatches cheaper realm-restricted workers: a **test wave**
writes tests against the contracts, an **implementation wave** makes them pass.
The orchestrator verifies every wave against explicit checklists, and a living
block map keeps the engineer's mental model current at the contract level.

## Why it works

- **Clarify over guess.** The deliverable is what the engineer says it is,
  never inferred from branch names, slugs, or repo archaeology. Ambiguity at
  any level (goal, contract, test) becomes a question or an escalation, not an
  assumption. Planning cannot start until the engineer confirms a restated
  goal.
- **Types are not contracts.** Every stub carries a docblock stating behavior,
  inputs, outputs, errors, invariants, and edge cases. Tests are verified
  clause-by-clause against it; cheap workers execute a spec written at the
  frontier tier, they don't invent one.
- **Realm restriction is mechanical, not vibes.** A PreToolUse hook denies
  test-writers any non-test file and implementers any test file; a post-hoc
  diff check (`scripts/realm-check.sh`) catches what file hooks can't see. An
  implementer structurally cannot weaken a test to get to green.
- **Workers never design.** Ambiguity, mis-sized blocks, and wrong-seeming
  tests are escalated to the orchestrator; contract changes go through the
  engineer, always.
- **The engineer can take any block.** Same contract, same tests, same
  acceptance gate; stubs keep every sibling block unblocked meanwhile.

## Install

```
/plugin marketplace add cjdubb/clam
/plugin install lego@clam
```

Enable it for the repos where you want the workflow. **Installing lego changes
nothing globally**: no writes to `~/.claude/CLAUDE.md` or any global settings
beyond Claude Code's own plugin-enablement entry. Plain `claude` in any other
repo is untouched. That is a hard design constraint of this project.

## Use

1. `/lego:plan` — decompose the deliverable into blocks with your
   orchestrator; approve the plan. Creates `.local/` in your repo (config, block
   map, plans) — the workflow's only footprint, kept out of your tracked tree
   automatically via `.git/info/exclude`. Teams that want the block map shared
   can remove that exclude entry and commit `.local/` deliberately.
2. `/lego:scaffold` — the orchestrator writes stubs + contracts and proves
   the design composes (typecheck > build > lint, whatever your repo has).
3. `/lego:dispatch` — test wave, verification, implementation wave,
   acceptance. You watch the block map; you build any block you claimed.

Repo specifics live in one place: `.local/config.json` (see
`docs/config-schema.md`). The workflow is deliberately opinionated with no
lightweight path; for work that doesn't warrant it, use plain `claude`.

## Layout

```
.claude-plugin/   plugin manifest
skills/           plan, scaffold, dispatch
agents/           lego-test-writer, lego-implementer (sonnet by default)
hooks/            PreToolUse realm gate, SessionStart context injection
scripts/          realm.sh (test-family source of truth), realm-check.sh,
                  realm-gate.sh, session-context.sh
templates/        starter .local/config.json and blocks.md
docs/             config schema / repo-interface spec
```

History: ported from the clam-v2 repo at v0.3.0; skills renamed from
`/clam:lego-*` to `/lego:*` in the move.
