<!--
Contract: B08 session-templates (query-results)

Behavior:
  Template for the paste-back results file created alongside every query.
  debug-session.sh query copies this file VERBATIM (contract comment
  included) to .local/debug/NNN-<slug>/queries/NN-<name>/results.md. The
  orchestrator fills the header; the ENGINEER pastes raw tool output into
  Results; the orchestrator writes Interpretation only after results arrive.

Inputs: n/a (template file; placeholders in [brackets]).

Outputs (required document structure — tests assert these):
  - H1: `# Query: [name]` followed by header lines, exactly these keys:
      Purpose:      — what question this query answers, in one line.
      Tool:         — e.g. Datadog | CloudWatch Logs Insights | Splunk |
                      Loki | Kibana | psql | mysql | files/grep.
      Query file:   — relative path to the sibling query file.
      How to run:   — exact instructions for the engineer (where to paste
                      the query, which time window/database to select).
  - H2 sections, exactly this order:
      ## Results         — starts with the paste-marker line: an HTML
                           comment whose text is exactly
                           "paste tool output below this line";
                           engineer pastes raw output here, ideally fenced.
      ## Interpretation  — orchestrator-written; what the results say about
                           the open hypotheses; empty until results arrive.
Errors: n/a.

Invariants:
  - Header keys, section names, and the paste marker are load-bearing:
    references/logs.md, references/database.md, and structure tests refer to
    them by these exact names.
  - The file never asks the engineer to transform output — raw paste only;
    interpretation is the orchestrator's job.

Edge cases:
  - Results too large to paste: How to run guidance tells the engineer they
    may truncate, stating what was cut (e.g. "first 50 rows of 12k").
-->

NotImplemented: B08
