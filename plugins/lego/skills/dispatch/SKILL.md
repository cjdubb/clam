---
name: dispatch
description: Run the test wave and implementation wave over scaffolded lego blocks, dependency-ordered and parallel where independent, with orchestrator verification checklists, mechanical realm checks, and the escalation loop. Use after /lego:scaffold's gate passes.
---

# Lego Dispatch

The orchestrator dispatches realm-restricted workers and verifies every wave.
Verification is not optional and not a skim: the test wave's checklist is what
makes cheap-tier workers safe.

Preconditions: scaffold gate passed; blocks at `Status: Scaffolded`;
phase-boundary commit made.

## Tier resolution

Read `models.testWriter` and `models.implementer` from `.local/config.json`
(default both to `sonnet` when absent) and pass the value as the `model`
parameter on every Agent call. Do not rely on agent-definition defaults alone.

## Worker briefs

Every dispatch names: the block ID(s), stub path(s) (the contract docblocks),
the repo's commands from `.local/config.json`, where tests conventionally live
(test wave) or the test paths (impl wave), and the required report format (the
agents' definitions specify it). Group only independent blocks into one wave;
dispatch a wave's agents in a single message so they run in parallel.

## Phase A: Test wave

Dispatch `lego-test-writer` agents for every leaf block (engineer-owned blocks
included; the engineer implements against the same tests). Then verify each
returned block against this checklist before accepting:

1. **Clause coverage.** Open the stub's contract docblock; walk clause by clause
   against the agent's clause-coverage map AND the actual test code. Every
   Behavior/Output/Error/Invariant/Edge-case clause has at least one real test.
2. **Contract, not internals.** Spot-read the tests: no private state, no
   imagined implementation mirrored in assertions.
3. **Red discipline, re-run yourself.** Run the repo's test command. Failures
   must be assertion or NotImplemented failures; import/compile/collection
   errors reject the wave.
4. **Realm purity, mechanical.** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/realm-check.sh test` (uncommitted-changes
   mode). Any violation rejects the wave; this also catches Bash-based writes
   the edit hook cannot see.

Rejected work goes back to a test-writer with the specific deficiency named.
Accepted: set blocks to `Tests Written`, then `Tests Verified` once the full
checklist passes. Commit the phase boundary (engineer consent).

## Phase B: Implementation wave

Dispatch `lego-implementer` agents in dependency order (topological by `Deps:`;
independent siblings in parallel). Engineer-owned blocks are NOT dispatched:
hand the engineer the contract and tests, mark the block map, and continue with
sibling blocks; stubs keep dependents unblocked.

Acceptance gate per wave:

1. Repo test command green (run it yourself; also typecheck/lint if configured).
2. `${CLAUDE_PLUGIN_ROOT}/scripts/realm-check.sh impl` — zero test-family
   diffs, mechanically proven.
3. **Contracts unchanged.** Diff the stub files against the scaffold commit and
   confirm signatures and contract docblocks are untouched (bodies change,
   surfaces do not). This check is by-eye in v0; treat any surface change as a
   defect unless it went through the escalation loop.
4. Spot-review the diff for quality: contract clauses the tests undercover are
   still binding (workers are told this; verify it on anything security- or
   correctness-critical).

Accepted: `Implemented`, then `Accepted` after the engineer has seen the block
map update. Commit the phase boundary.

## Phase C: Composition blocks

When all children of a composition block are `Accepted`, run its own test wave
(integration tests against the composition's contract) and implementation wave
(usually thin wiring) through the same phases A and B.

## Escalation loop

Workers stop and return `STATUS: ESCALATION` rather than design. On receipt:

- **Resolvable within the contract** (ambiguous brief, tooling issue): clarify
  and re-dispatch the same phase.
- **Contract is wrong or block is mis-sized**: this is a design change. Take it
  to the engineer with a recommendation; on their decision, append to the plan
  Changelog, re-scaffold the affected blocks, re-run their test wave, then
  re-dispatch. Affected dependents get re-verified.
- **A test is wrong** (implementer escalation): arbitrate against the contract.
  Test wrong → back to a test-writer with the contract clause cited. Contract
  wrong → engineer, as above. Never let an implementer's claim weaken a correct
  test.

Log every escalation and its resolution in the plan's Changelog. Update
`.local/blocks.md` (`Escalated` and back) in real time.

## Done

All blocks `Accepted`, full suite green, block map current, plan Changelog
records every deviation. Present the engineer a contract-level summary: which
blocks exist, what changed since approval, where the map lives.
