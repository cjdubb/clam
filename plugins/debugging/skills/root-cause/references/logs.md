<!--
Contract: B05 ref-logs

Behavior:
  Technique reference on gathering log evidence, loaded by the root-cause
  skill at phase 7. Covers direct access AND the paste-back protocol when the
  orchestrator cannot reach the logs itself. Written to the orchestrator.

Inputs: n/a (guidance document).

Outputs (required document structure — tests assert these):
  - H1 title, then a "When to use" line.
  - H2 sections, exactly this set:
      ## Access first        — determine whether you can query logs from this
                               session (CLI, MCP, local files). If yes, query
                               directly. If not, do NOT guess: ask the
                               engineer which tool they use, then follow the
                               paste-back protocol.
      ## What to look for    — error onset time, first occurrence vs steady
                               state, frequency changes at deploy boundaries,
                               correlation/request ids to pivot on, adjacent
                               warnings before the first error.
      ## Tool guidance       — per-tool query idioms, one concrete example
                               query pattern each, for AT LEAST: Datadog,
                               CloudWatch Logs Insights, Splunk, Loki
                               (LogQL), Kibana/Elasticsearch (KQL or
                               Lucene), and plain files / kubectl logs with
                               grep. Each example is copy-adaptable: shows a
                               time window, a service/source filter, and a
                               message match.
      ## Paste-back protocol — create a query dir with
                               ${CLAUDE_PLUGIN_ROOT}/scripts/debug-session.sh
                               query <session-dir> <name>; write the exact
                               query into the query file; fill the
                               query-results.md header (purpose, tool, how to
                               run); hand the engineer the file path and ask
                               them to paste output into its Results section;
                               interpret only after results arrive.
      ## Journal             — every query indexed in the journal's Queries
                               section; findings land as hypothesis evidence.
Errors: n/a.

Invariants:
  - Never fabricates or extrapolates log content; absence of access always
    routes through the paste-back protocol.
  - Tool examples are patterns, not environment-specific facts; the doc says
    to confirm index/source names with the engineer.

Edge cases:
  - Engineer's tool is not in the table: the doc says to ask the engineer for
    one sample query from their tool and adapt the idioms.
  - Logs rotated/expired for the incident window: treat as evidence gap;
    note it in the journal rather than substituting guesses.
-->

# Log Evidence

**When to use:** phase 7 of the root-cause loop — you need corroborating evidence from application logs, whether or not you can reach the log tooling directly from this session.

## Access first

Before writing a single query, work out whether you can reach the logs from this session at all: a CLI (e.g. `aws logs`, `splunk`, `logcli`), an MCP tool, or plain local/mounted log files.

- **If yes:** query directly. Use the idioms in Tool guidance below and iterate — logs are cheap to re-query.
- **If no:** do not guess at log content. Ask the engineer which tool they use, then follow the Paste-back protocol below rather than inventing what the logs might say.

Never fabricate or extrapolate log content: absence of access always routes through the paste-back protocol, never through inference about what a log line probably said.

**Logs rotated or expired for the incident window:** treat this as an evidence gap, not a blank to fill in. Note it in the journal and lean on corroborating evidence elsewhere (metrics, traces, database state) instead of substituting a guess.

## What to look for

Whatever the tool, the same signals matter:

- **Error onset time** — the first timestamp the failure appears, not just "recently."
- **First occurrence vs steady state** — is this a brand-new error, or a rate change in something that always existed?
- **Frequency changes at deploy boundaries** — a spike or step-change that lines up with a deploy is strong evidence, not proof.
- **Correlation/request ids to pivot on** — grab one from a failing request and use it to pull every log line that touched that request across services.
- **Adjacent warnings before the first error** — the lines immediately preceding the first error often show the precondition that made it fail.

## Tool guidance

Each pattern below shows a time window, a service/source filter, and a message match — adapt the field names to the environment; **confirm the exact index/service/source name with the engineer** before trusting a filter, since these are patterns, not facts about this system.

**Datadog** — Log Explorer search bar, with the time-range picker set to the incident window (e.g. "Past 4 hours" or a custom range from first-seen to now):
```
service:checkout-api status:error "connection timed out"
```

**CloudWatch Logs Insights** — set the query's time range to the incident window, then:
```
fields @timestamp, @message
| filter @logStream like /checkout-service/
| filter @message like /connection timed out/
| sort @timestamp desc
| limit 200
```

**Splunk** — time window is inline via `earliest`/`latest`:
```
index=prod_app sourcetype=checkout-service earliest=-4h latest=now
| search "connection timed out"
```

**Loki (LogQL)** — via `logcli`, bounding the window with `--from`/`--to`:
```
logcli query --from="2026-07-20T10:00:00Z" --to="2026-07-20T14:00:00Z" \
  '{service="checkout-service"} |= "connection timed out"'
```

**Kibana / Elasticsearch (KQL or Lucene)** — set Kibana's time picker to the incident window, then:
```
service.name:"checkout-service" and message:"connection timed out"
```

**Plain files / `kubectl logs` + grep** — `--since` bounds the window, the deployment name is the source filter, `grep` is the message match:
```
kubectl logs deploy/checkout-service --since=4h | grep -i "connection timed out"
```
For rotated-in-place files: `grep -i "connection timed out" /var/log/checkout-service/*.log`.

**Tool not in this table?** Ask the engineer for one sample query they already know works, then adapt the pattern above (time window, source filter, message match) to that tool's syntax rather than guessing at it yourself.

## Paste-back protocol

When you can't reach the logs directly:

1. Create the query dir: `${CLAUDE_PLUGIN_ROOT}/scripts/debug-session.sh query <session-dir> <name>`.
2. Write the exact query you want run into the created query file — the same query you'd run yourself, not a description of one.
3. Fill in the query-results.md header: **Purpose** (what question this answers), **Tool** (Datadog, CloudWatch, Splunk, Loki, Kibana, kubectl, etc.), **How to run** (exactly where to paste it and which time window to select).
4. Hand the engineer the file path and ask them to paste the raw output into the Results section — no reformatting, no summarizing on their end.
5. Interpret only after results arrive. Don't pre-write conclusions; a result that contradicts your expectation is itself evidence.

## Journal

Every query — run directly or handed off — gets indexed in the journal's Queries section (purpose, tool, results-received?). Once results are in hand, findings become hypothesis evidence: log the finding next to the hypothesis it supports or refutes in the Hypotheses table.
