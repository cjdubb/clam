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

NotImplemented: B05
