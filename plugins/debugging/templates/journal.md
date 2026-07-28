
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
