<!--
Contract: B04 ref-binary-search

Behavior:
  Technique reference on isolating a cause by halving the search space,
  loaded by the root-cause skill at phase 6. Written to the orchestrator.

Inputs: n/a (guidance document).

Outputs (required document structure — tests assert these):
  - H1 title, then a "When to use" line (large search space + a reliable
    discriminator).
  - H2 sections, exactly this set:
      ## Prerequisite        — a reliable discriminator (usually the repro
                               from phase 3); bisecting on a flaky signal
                               corrupts the search.
      ## Dimensions          — what can be halved: history (git bisect,
                               including automation with `git bisect run`),
                               code path (instrumentation, early returns),
                               data (input halving), configuration (toggle
                               halves), environment (diff and swap halves).
      ## Discipline          — one variable per probe; before each probe
                               record hypothesis, probe, expected, observed;
                               stop when the culprit is minimal (one commit,
                               one input, one flag).
      ## Pitfalls            — flaky discriminator, unbuildable commits
                               (git bisect skip), non-monotonic spaces where
                               halving is invalid, fix-masking interactions.
      ## Journal             — every probe becomes a Probe Log row in the
                               session journal.
Errors: n/a.

Invariants:
  - git bisect is presented as the primary tool for the history dimension,
    with the exact command sequence (start/good/bad/run/reset).
  - The doc never suggests changing two variables in one probe.

Edge cases:
  - Non-monotonic space (intermittent regressions): instructs falling back to
    differential diagnosis instead of forcing a bisect.
  - Search space of one (single candidate change): skip bisection, go verify
    directly.
-->

NotImplemented: B04
