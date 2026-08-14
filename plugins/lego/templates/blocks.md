# Block Map

The contract-level view of this system: every lego block, its promise, its
status, its owner. Kept current in real time by the clam workflow so the
engineer always reads current state. Full behavioral contracts live in the code docblocks at each
block's `Code:` path; this map carries the summaries and the state.

Status lifecycle: `Planned → Scaffolded → Tests Written → Tests Verified →
Implemented → Accepted` (side-state: `Escalated`).

<!-- Example entry; delete once real blocks exist:

## B01 — rate-limiter
- Status: Planned
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U01
- PR group: G01
- Est: 180
- Justification: exceeds the per-block ceiling because the token-bucket
  algorithm and its concurrency-safe refill logic don't split cleanly
  without duplicating shared state between two blocks
- Setup: npm ci
- Test: npm test -- src/rate-limiter.spec.ts
- Code: src/rate-limiter.ts
- Contract: token-bucket limiter; allow/deny per key with configurable refill
- Plan: plans/001-api-hardening.md

Justification: is optional — required only when Est exceeds the per-block
ceiling (half the PR size budget); an under-ceiling entry needs no
Justification: at all.

Test: is required of every block: the command that runs that block's tests,
agreed with the engineer and proved by running it at plan time. It is the
only place a wave reads a test command from.

Setup: is optional — write it only when the repo needs a preparation step
before the tests run. Blocks sharing a Unit: must agree on both fields.

-->
