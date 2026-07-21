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

# Database Evidence

**When to use:** phase 7 of the root-cause loop — you need to inspect actual database state (not just logs) to confirm or refute a hypothesis, whether or not you can run queries directly from this session.

## Safety first

**Read-only, always.** Every query you run or hand off is SELECT or EXPLAIN — never INSERT, UPDATE, DELETE, or a DDL statement (CREATE/ALTER/DROP/TRUNCATE). You are gathering evidence, not fixing anything from inside an investigation.

- **Prefer a replica** over the primary whenever one exists — it's read-only by construction and keeps your investigation from competing with production traffic.
- **Bound every result with LIMIT.** Even a "just checking" query against a hot table can return more rows than you want to read, and can hold locks or add replication lag longer than necessary.
- **Keep PII out of the journal.** Don't paste customer emails, names, payment details, or other PII into the journal or query-results files unless the engineer has explicitly okayed it for this investigation — summarize shape and counts instead ("3 of 40 rows had a null address") rather than the raw values.

## Access first

Determine whether you can query the database directly from this session (a CLI, an MCP tool, a read replica you're already connected to). If you can, query directly, following the patterns below.

If you can't, ask the engineer to run it for you: write the exact query and use the Paste-back protocol below. Always state the expected result shape alongside the query you hand over (e.g. "should be zero rows" or "one row, `status` column should read `active`") — that's what makes a surprising result recognizable as evidence rather than something that gets shrugged off.

## Query patterns

Every pattern below leads with an indexed column (primary key, `created_at`/`updated_at`, foreign key) and bounds the result with LIMIT. On a large production table, a filter that isn't indexed forces a full table scan — slow, and it can add replication lag on a replica or contend with live traffic on the primary. If you don't know which columns are indexed, ask the engineer or check with EXPLAIN before running an unbounded version of any of these.

**The affected entity's current row(s):**
```sql
SELECT *
FROM orders
WHERE id = 123
LIMIT 1;
```

**Recent mutations via `created_at`/`updated_at` windows:**
```sql
SELECT id, status, created_at, updated_at
FROM orders
WHERE updated_at >= now() - interval '1 hour'
ORDER BY updated_at DESC
LIMIT 200;
```
Swap in `created_at` to see what's new versus what merely changed.

**Aggregate sanity counts and per-status distribution:**
```sql
SELECT status, count(*)
FROM orders
WHERE created_at >= now() - interval '1 day'
GROUP BY status
ORDER BY count(*) DESC;
```
Compare this distribution against the last-known-good baseline — a shifted status mix is often the first quantitative sign something changed.

**Orphan/referential checks between related tables:**
```sql
SELECT o.id
FROM orders o
LEFT JOIN customers c ON c.id = o.customer_id
WHERE c.id IS NULL
LIMIT 100;
```
A nonzero count here is an orphan row — a child whose parent is missing — and is evidence for a referential-integrity or ordering hypothesis.

**Schema and migration state:**
```sql
SELECT *
FROM schema_migrations
ORDER BY version DESC
LIMIT 20;
```
The applied-migrations table name varies by framework (`schema_migrations`, `django_migrations`, `flyway_schema_history`); ask the engineer if you're not sure which one applies.

**Unknown schema?** Derive the table shape before writing any of the above against it:
```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_name = 'orders';
```
Or just ask the engineer — either is faster than guessing at column names.

## Paste-back protocol

1. Create the query dir with the `sql` extension so the query file is named correctly: `${CLAUDE_PLUGIN_ROOT}/scripts/debug-session.sh query <session-dir> <name> sql`.
2. Write the exact SQL into the resulting `query.sql` — the literal query you'd run yourself, not a description of one.
3. Fill in the query-results.md header: **Purpose** (what question this answers), **Tool** (psql, mysql, a specific ORM console, etc.), **How to run** (which database/replica to connect to, and exactly where to paste the query).
4. Ask the engineer to run it and paste the raw output into the Results section.
5. Interpret only after the results arrive — don't write the interpretation in advance.

## Journal

Every query — run directly or handed off — gets indexed in the journal's Queries section. Record the interpretation next to the pasted results, and feed it into the Hypotheses table as evidence for or against the hypothesis it targeted.
