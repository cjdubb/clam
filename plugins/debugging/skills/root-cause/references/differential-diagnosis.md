<!--
Contract: B07 ref-differential-diagnosis

Behavior:
  Technique reference on running a differential diagnosis over competing
  causes, loaded by the root-cause skill at phase 5. This is the reasoning
  engine the other techniques feed. Written to the orchestrator.

Inputs: n/a (guidance document).

Outputs (required document structure — tests assert these):
  - H1 title, then a "When to use" line (more than one plausible cause).
  - H2 sections, exactly this set:
      ## Generate hypotheses — enumerate broadly before judging; seed from
                               the what-changed candidate list plus the
                               standing categories: code change, config/flag,
                               data, dependency, environment/infra,
                               load/timing/concurrency, external service.
      ## Build the table     — one row per hypothesis in the journal's
                               Hypotheses table: hypothesis, evidence for,
                               evidence against, status (open | refuted |
                               confirmed).
      ## Weigh evidence      — score each hypothesis against ALL evidence
                               gathered so far; evidence that fits every
                               hypothesis discriminates nothing.
      ## Discriminating probes — design the cheapest probe that splits the
                               surviving hypotheses best; run it (or its
                               binary-search/logs/database technique); this
                               is also the marked OPTIONAL delegation point —
                               independent hypotheses may be investigated by
                               parallel subagents, never mandatorily.
      ## Update loop         — after each probe: update rows, refute what the
                               evidence kills, add hypotheses new evidence
                               suggests; repeat until one survivor.
      ## Convergence rule    — accept the survivor as root cause ONLY when it
                               explains ALL recorded evidence; any unexplained
                               evidence reopens generation. (Mirrors the
                               skill's phase-8 gate.)
Errors: n/a.

Invariants:
  - A hypothesis is never deleted, only refuted with the evidence that
    refuted it — the trail is part of the journal's value.
  - The doc never lets a "likely" hypothesis skip the convergence rule.

Edge cases:
  - Two surviving hypotheses that current evidence cannot split: the doc
    directs designing a new discriminating probe rather than choosing by
    plausibility.
  - Compound causes (two interacting changes): the combination becomes its
    own hypothesis row.
-->

# Differential Diagnosis

**When to use:** phase 5 of the root-cause loop — whenever there is more than one plausible cause and you need a disciplined way to narrow between them instead of chasing the first plausible story.

## Generate hypotheses

Enumerate broadly before judging — write down every hypothesis that could produce the observed symptom, even ones that feel unlikely, before you start ruling anything out. Seed the list from two places:

- The candidate-change list produced by the what-changed technique.
- These standing categories, walked every time regardless of what what-changed turned up:
  - **Code change** — a commit or PR that touched the affected path.
  - **Config/flag** — a feature flag, environment variable, or config value.
  - **Data** — a shape, volume, or quality change in the data itself.
  - **Dependency** — a library, service, or base-image version bump.
  - **Environment/infra** — host, network, resource limits, a scaling event.
  - **Load/timing/concurrency** — a traffic spike, race condition, or timing shift.
  - **External service** — a third-party API's behavior, latency, or outage.

## Build the table

Give every hypothesis its own row in the journal's Hypotheses table — one row per hypothesis, never combined:

| # | Hypothesis | Evidence for | Evidence against | Status |
|---|------------|---------------|-------------------|--------|
| 1 | ... | ... | ... | open |

Status is one of: **open**, **refuted**, **confirmed**. A hypothesis is never deleted from the table, even once refuted — it stays, with the evidence that refuted it, because the refuted trail is part of the journal's value if the investigation ever reopens.

## Weigh evidence

Score each hypothesis against all evidence gathered so far — from reproduction, what-changed, logs, database queries, and prior probes — not just the newest data point. Evidence that fits every surviving hypothesis equally discriminates nothing: it might feel reassuring, but it doesn't move any row forward and isn't worth citing as if it did.

## Discriminating probes

Design the cheapest probe that splits the surviving hypotheses best — the test whose two possible outcomes would kill the most hypotheses or cleanly separate what's left, not the most thorough test you could run. Then execute it: run it directly, or reach for the binary-search, logs, or database technique to carry it out.

This is also the OPTIONAL parallel-subagent delegation point: when two or more surviving hypotheses are independent of each other (probing one tells you nothing about the others), you may hand each to a parallel subagent to investigate at the same time. This is never mandatory — a single probe at a time is always an acceptable choice, and delegation only pays for itself when the hypotheses are genuinely independent.

**Two survivors current evidence can't split:** don't resolve it by plausibility — design a new discriminating probe that would separate them and run that instead.

## Update loop

After every probe, update the Hypotheses table before doing anything else: mark refuted whatever the new evidence kills, citing that evidence in Evidence against; add any new hypothesis the result suggests that wasn't already on the list; leave everything else open. Repeat weigh → probe → update until exactly one hypothesis remains as the sole survivor.

**Compound causes:** when two changes interact — neither alone reproduces the symptom, but the combination does — give the interacting combination its own hypothesis row rather than forcing it into one of the individual rows.

## Convergence rule

Accept the surviving hypothesis as the root cause only when it explains all recorded evidence — every log line, query result, probe outcome, and reproduction detail gathered during the investigation, not just the evidence that led you to it. A hypothesis that merely seems likely does not get to skip the convergence rule — "probably it" is not confirmed until it explains everything. If even one piece of evidence remains unexplained, the investigation has not converged: reopen hypothesis generation rather than settling. This mirrors the skill's phase-8 root-cause gate.
