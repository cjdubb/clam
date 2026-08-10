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
- Code: src/rate-limiter.ts
- Contract: token-bucket limiter; allow/deny per key with configurable refill
- Plan: plans/001-api-hardening.md

Justification: is optional — required only when Est exceeds the per-block
ceiling (half the PR size budget); an under-ceiling entry needs no
Justification: at all.

-->
