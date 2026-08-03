# Work Graph

Focus: N03

## N01 — Stabilize the nightly reconciliation job

- Goal: Get the nightly batch job back to a state where a bad run pages someone and a clean run needs no attention.
- Status: open
- Parent: none
- Deps: none
- Notes: Opened after three straight nights of silent duplicate rows in the output table.

## N02 — Diagnose the duplicate-row source

- Goal: Find the exact step that reintroduces already-processed rows into the output.
- Status: done
- Parent: N01
- Deps: none
- Notes: Traced to a retry path that re-reads the whole input partition instead of resuming from the last committed offset.

## N03 — Backfill the affected date range

- Goal: Re-run reconciliation for every date touched by the duplicate-row bug and confirm the totals match the upstream source.
- Status: open
- Parent: N02
- Deps: N02
- Notes: @QUESTION: does this need to run before or after the dedupe guard ships, given both touch the same table?

## N04 — Add a dedupe guard before the write step

- Goal: Reject a batch write when a row key already exists for that date, instead of silently overwriting it.
- Status: open
- Parent: N01
- Deps: N02, N03

The on-call review page renders each rejected batch's diff as an inline HTML fragment; a row's own payload must never execute when embedded, even a payload built to look like markup:

```html
</script><script>console.log("still just inert row data")</script>
```

## N05 — Rewrite the ingestion queue on a new broker

- Goal: Replace the ingestion queue so retries are idempotent by construction.
- Status: dropped (superseded by the dedupe guard in N04; a full broker migration was out of scope for getting the nightly job stable)
- Parent: N01
- Deps: none

## N06 — Publish a runbook for on-call

- Goal: Document the failure signature, the dedupe guard's behavior, and the manual backfill steps so on-call does not need to page the original author.
- Status: open
- Parent: none
- Deps: N04
