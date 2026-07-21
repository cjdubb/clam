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

NotImplemented: B07
