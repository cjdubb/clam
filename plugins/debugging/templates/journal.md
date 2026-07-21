<!--
Contract: B08 session-templates (journal)

Behavior:
  Template for the per-investigation debug journal. debug-session.sh start
  copies this file VERBATIM (contract comment included) to
  .local/debug/NNN-<slug>/journal.md; the orchestrator fills it in as the
  investigation proceeds. This comment doubles as the template's usage doc.

Inputs: n/a (template file; placeholders in [brackets]).

Outputs (required document structure — tests assert these):
  - H1: `# Debug Journal: [issue title]` followed by metadata lines:
    `Started:`, `Status:` (investigating | root cause found | abandoned),
    `Session dir:`.
  - H2 sections, exactly this order:
      ## Symptom        — expected vs actual, affected scope, first seen,
                          one-line problem statement.
      ## Reproduction   — status ladder (none | flaky | reliable), steps,
                          observed rate (e.g. 5/5).
      ## What Changed   — window (last-known-good → first-seen) and the
                          candidate-change timeline.
      ## Hypotheses     — table with header exactly:
                          | # | Hypothesis | Evidence for | Evidence against | Status |
                          Status values: open | refuted | confirmed.
      ## Probe Log      — chronological table with header exactly:
                          | When | Probe | Expected | Observed |
      ## Queries        — index of queries/NN-<name>/ dirs: purpose, tool,
                          results-received? (yes/no).
      ## Root Cause     — statement; how it explains ALL the evidence; fix
                          direction; repro-as-regression-test note.
Errors: n/a.

Invariants:
  - Section names and the two table headers are load-bearing: SKILL.md, the
    references, and structure tests refer to them by these exact names.
  - Placeholders use [brackets] so an unfilled journal is recognizable.

Edge cases:
  - Abandoned investigations keep the journal (Status: abandoned) — the
    negative trail has diagnostic value for the next attempt.
-->

NotImplemented: B08
