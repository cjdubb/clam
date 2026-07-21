<!--
Contract: B03 ref-what-changed

Behavior:
  Technique reference answering "what has changed to cause this issue?",
  loaded by the root-cause skill at phase 4. Written to the orchestrator.

Inputs: n/a (guidance document).

Outputs (required document structure — tests assert these):
  - H1 title, then a "When to use" line.
  - H2 sections, exactly this set:
      ## Establish the window   — first-seen and last-known-good timestamps
                                  bound the search window.
      ## Change surfaces        — enumerate ALL of: code commits, deploys and
                                  releases, config and feature flags,
                                  dependencies and base images, schema and
                                  data migrations, infrastructure and
                                  platform, external services, data drift,
                                  and time-triggered changes (cert expiry,
                                  quotas, DST).
      ## Enumerate changes per surface — how to list changes in the window
                                  for each surface (git log/diff, deploy
                                  history, flag audit logs, dependency
                                  lockfiles, migration tables); when records
                                  are not reachable, ask the engineer where
                                  they live — never guess.
      ## Correlate              — line changes up against symptom onset;
                                  near-coincidence is a hypothesis, not a
                                  verdict.
      ## Output                 — a candidate-change list feeding the
                                  differential-diagnosis table.
      ## Journal                — record window, surfaces checked, candidates.
Errors: n/a.

Invariants:
  - The surface list above is the minimum; the doc must present it as a
    checklist to walk exhaustively, not a menu.
  - Correlation-is-not-causation caveat appears with the Correlate guidance.

Edge cases:
  - No last-known-good exists (never worked): the doc says to reframe from
    regression hunting to first-principles diagnosis and skip this technique's
    window narrowing.
  - Multiple simultaneous changes (deploy trains): candidates stay separate
    hypotheses rather than being lumped.
-->

NotImplemented: B03
