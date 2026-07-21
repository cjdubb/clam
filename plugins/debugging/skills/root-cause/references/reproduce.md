<!--
Contract: B02 ref-reproduce

Behavior:
  Technique reference on establishing a RELIABLE reproduction, loaded by the
  root-cause skill at phase 3. Written to the orchestrator as reader ("you").

Inputs: n/a (guidance document).

Outputs (required document structure — tests assert these):
  - H1 title, then a "When to use" line (load trigger restated).
  - H2 sections, exactly this set, any order unless noted:
      ## Goal                — what counts as reliable: same steps, same
                               failure, quantified (e.g. N/N runs).
      ## Capture             — freeze the exact failing input, environment,
                               versions, and data before touching anything.
      ## Minimize            — shrink input/steps while the failure persists;
                               smallest repro wins.
      ## Automate            — turn the repro into a script or failing test;
                               prefer a failing test in the repo's own runner.
      ## Flaky and intermittent — estimate frequency; force the conditions
                               (timing, concurrency, load, data variance,
                               environment); when to proceed with a flaky
                               repro and how that weakens later inference.
      ## Journal             — what to record: repro status ladder
                               (none → flaky → reliable), steps, rate.
Errors: n/a.

Invariants:
  - Never duplicates the phase loop from SKILL.md; techniques only.
  - Repro-as-regression-test is stated as the preferred end state.

Edge cases:
  - Cannot reproduce at all: instructs widening evidence gathering (logs/DB)
    and treating the repro gap itself as diagnostic information.
  - Production-only failures: safe capture guidance (no destructive probing).
-->

NotImplemented: B02
