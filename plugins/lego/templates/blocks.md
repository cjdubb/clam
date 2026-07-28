# Block Map

The contract-level view of this system: every lego block, its promise, its
status, its owner. Kept current in real time by the clam workflow; a stale map
is a defect. Full behavioral contracts live in the code docblocks at each
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
- Code: src/rate-limiter.ts
- Contract: token-bucket limiter; allow/deny per key with configurable refill
- Plan: plans/001-api-hardening.md

-->
