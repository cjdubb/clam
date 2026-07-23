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
      ## Prevention     — labeled lines, each value a [bracket] placeholder:
                          `Defect class:` (the class statement),
                          `Sweep method:` (commands/queries + scope),
                          `Sweep results:` (instances found; "0 found" is a
                          valid recorded outcome),
                          `Guardrail:` (proposed | built | declined with
                          rationale + engineer sign-off | none warranted
                          with rationale).
Errors: n/a.

Invariants:
  - Section names and the two table headers are load-bearing: SKILL.md, the
    references, and structure tests refer to them by these exact names.
  - Placeholders use [brackets] so an unfilled journal is recognizable.

Edge cases:
  - Abandoned investigations keep the journal (Status: abandoned) — the
    negative trail has diagnostic value for the next attempt.
-->

# Debug Journal: [issue title]

Started: [YYYY-MM-DD HH:MM]
Status: [investigating | root cause found | abandoned]
Session dir: [.local/debug/NNN-slug]

## Symptom

- Expected: [what should happen]
- Actual: [what happens instead]
- Affected scope: [users / environments / requests affected]
- First seen: [date/time or event the problem was first observed]

[One-line problem statement.]

## Reproduction

Status: [none | flaky | reliable]

Steps:
1. [step]
2. [step]

Observed rate: [e.g. 5/5]

## What Changed

Window: [last-known-good] -> [first-seen]

Candidate changes in the window:
- [candidate change — commit/deploy/config/flag, when, who]
- [candidate change]

## Hypotheses

| # | Hypothesis | Evidence for | Evidence against | Status |
| --- | --- | --- | --- | --- |
| 1 | [hypothesis] | [evidence] | [evidence] | [open | refuted | confirmed] |

## Probe Log

| When | Probe | Expected | Observed |
| --- | --- | --- | --- |
| [timestamp] | [probe or check performed] | [expected result] | [observed result] |

## Queries

- queries/[NN-name]/ — purpose: [purpose]; tool: [tool]; results received?: [yes | no]

## Root Cause

[Root cause statement.]

- Explains all evidence: [how this explains every symptom and probe observation above]
- Fix direction: [what should change]
- Regression test: [note that the reproduction steps above become the regression test]

## Prevention

Defect class: [the class of defect this represents, not just this one instance]
Sweep method: [commands or queries run, and their scope, to find other instances of this defect class]
Sweep results: [instances found elsewhere; "0 found" is a valid recorded outcome]
Guardrail: [proposed | built | declined with rationale + engineer sign-off | none warranted with rationale]
