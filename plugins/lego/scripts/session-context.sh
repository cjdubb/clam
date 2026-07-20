#!/usr/bin/env bash
# session-context.sh — SessionStart hook: inject the lego workflow standing
# rules and, when present, the host repo's current block map. Plain stdout
# becomes session context.
set -euo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"

cat <<'EOF'
# Lego Workflow (clam plugin)

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
- Types are not contracts: every stub carries a contract docblock (Behavior,
  Inputs, Outputs, Errors, Invariants, Edge cases). Tests verify contract
  clauses, never internals.
- The engineer may claim any block (Owner: engineer). Same contract, same tests,
  same acceptance gate; sibling blocks proceed against stubs meanwhile.
- Every work unit (one block by default) is dispatched in a dedicated worktree
  forked from the integration branch; workers see only their own unit's tests
  and contract.
- Accepted units always merge locally into the integration branch. Under
  `main-prs` delivery mode, PR groups are raised as PRs targeting master/main
  only (never another branch), each containing only complete blocks (contract
  + tests + implementation).
- Keep `.local/blocks.md` current in real time. It is the engineer's mental model
  of the system; a stale map is a defect.
- Repo specifics (verify commands, model tiers) come ONLY from `.local/config.json`.
EOF

if [ -f "$root/.local/blocks.md" ]; then
  echo
  echo "## Current block map (.local/blocks.md)"
  echo
  head -c 16000 "$root/.local/blocks.md"
fi
