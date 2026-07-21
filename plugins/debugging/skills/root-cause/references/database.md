<!--
Contract: B06 ref-database

Behavior:
  Technique reference on inspecting database state as evidence, loaded by the
  root-cause skill at phase 7. Read-only by principle; covers direct access
  AND the paste-back protocol. Written to the orchestrator.

Inputs: n/a (guidance document).

Outputs (required document structure — tests assert these):
  - H1 title, then a "When to use" line.
  - H2 sections, exactly this set:
      ## Safety first        — READ-ONLY always: SELECT/EXPLAIN only, never
                               INSERT/UPDATE/DELETE/DDL; prefer a replica;
                               bound every result with LIMIT; keep PII out of
                               the journal unless the engineer explicitly
                               okays it.
      ## Access first        — determine whether you can query from this
                               session; if not, ask the engineer and use the
                               paste-back protocol with the exact query and
                               the expected result shape.
      ## Query patterns      — state-inspection patterns, one example each,
                               for AT LEAST: the affected entity's current
                               row(s); recent mutations via
                               created_at/updated_at windows; aggregate
                               sanity counts (totals, per-status
                               distribution); orphan/referential checks
                               between related tables; schema and migration
                               state (applied-migrations table).
      ## Paste-back protocol — create the query dir with
                               ${CLAUDE_PLUGIN_ROOT}/scripts/debug-session.sh
                               query <session-dir> <name> sql; write the
                               exact SQL into query.sql; fill query-results.md
                               (purpose, tool, how to run); ask the engineer
                               to run it and paste the output into Results;
                               interpret only after results arrive.
      ## Journal             — queries indexed in the journal's Queries
                               section; interpretation recorded next to the
                               pasted results and fed into the hypothesis
                               table.
Errors: n/a.

Invariants:
  - No guidance ever produces a state-mutating statement, even as an example.
  - Expected result shape is stated with each query handed to the engineer,
    so surprising results are recognizable as evidence.

Edge cases:
  - Unknown schema: the doc shows how to ask for/derive the relevant table
    shapes first (information_schema or the engineer) before writing queries.
  - Very large tables: patterns lead with indexed-column filters and LIMIT;
    the doc warns about full scans on production.
-->

NotImplemented: B06
