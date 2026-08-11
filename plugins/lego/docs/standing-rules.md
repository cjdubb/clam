# Lego Workflow (clam plugin)

Read this document at the start of every lego skill invocation; its rules
govern the whole engagement, not just the invoking skill's phase.

This repo uses the clam lego workflow. Software is composed of lego blocks: units
with a public interface, a behavioral contract, and internals the rest of the
system never sees. Blocks are recursive; compositions are themselves blocks
(integration is a higher-order block with its own contract and tests).

## Workflow

1. `/lego:plan` — decompose the deliverable into blocks WITH the engineer;
   write the plan and block map. Engineer approval is required before scaffolding.
2. `/lego:scaffold` — the orchestrator (this session) writes runtime-present,
   deliberately unimplemented stubs carrying full behavioral contracts, then runs
   the scaffold gate (strongest available check).
3. `/lego:dispatch` — per-unit pipeline, each work unit dispatched in its own
   dedicated worktree: test wave (lego-test-writer agents), orchestrator
   verification, then implementation wave (lego-implementer agents),
   orchestrator acceptance, local merge, and incremental delivery.
   Dependency-ordered, parallel where independent.

## Standing rules

- **Clarify and verify; never guess.** This is the workflow's central rule.
  The deliverable is what the engineer states in conversation — NEVER inferred
  from branch/worktree names, directory slugs, commit history, or code
  archaeology. Ambiguity at any level (goal, contract, test, tooling) becomes a
  question to the engineer or an escalation to the orchestrator, not an
  assumption. When evidence contradicts what you were told, surface the
  contradiction before acting on either version.
- The orchestrator designs and verifies; it does not implement block internals.
- Workers NEVER design. Any ambiguity, mis-sized block, or wrong-seeming test is
  escalated back to the orchestrator. Contract changes go through the engineer.
- Realm restriction is mechanical: test-writers touch only the test-file family
  (*.spec.*, *.test.*, *_test.*, *_spec.*, test_*, __tests__/); implementers may
  never touch it. Verify every wave with scripts/realm-check.sh.
- Every stub carries a contract docblock (Behavior, Inputs, Outputs, Errors,
  Invariants, Edge cases); a type signature alone does not specify behavior.
  Tests verify contract clauses, never internals.
- The engineer may claim any block (Owner: engineer). Same contract, same tests,
  same acceptance gate; sibling blocks proceed against stubs meanwhile. This
  keeps design authorship with the engineer: they implement the blocks that
  matter to them, under the same gates as any worker.
- Every work unit (one block by default) is dispatched in a dedicated worktree
  forked from the integration branch; workers see only their own unit's tests
  and contract.
- Accepted units always merge locally into the integration branch. Under
  `main-prs` delivery mode, PR groups are raised as PRs targeting master/main
  only (never another branch), each containing only complete blocks (contract
  + tests + implementation).
- Keep `.local/blocks.md` current in real time. The engineer reads it to know
  the current state of every block, so update it the moment a block changes.
- Repo specifics (verify commands, model tiers) come ONLY from the layered
  config: committed `.claude/lego.json` merged with an optional gitignored
  `.local/config.json` override (see the plugin's docs/config-schema.md).
- **Every question must be explicitly answered before proceeding.** When the
  orchestrator poses a question to the engineer, no background agents,
  exploration, or next-step progression may proceed until every question
  receives an explicit answer — partial responses do not count as
  sufficient, and any question left unanswered must be restated to the
  engineer. A question the engineer explicitly declines or skips counts as
  answered; a bare "go" accepting the recommended defaults counts as
  answering all open questions.
