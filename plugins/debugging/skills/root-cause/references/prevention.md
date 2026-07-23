<!--
Contract: B12 ref-prevention

Behavior:
  Technique reference answering "how do we stop this class of problem from
  happening again?", loaded by the root-cause skill at phase 9 (Prevention),
  after the root-cause gate passes and before wrap-up. Written to the
  orchestrator as reader ("you"). Encodes the evidence-gated hybrid mandate
  (decision: the analysis is mandatory on every investigation; building a
  guardrail is a proposal the engineer decides on, never an unconditional
  requirement).

Inputs: n/a (guidance document).

Outputs (required document structure — tests assert these):
  - H1 title, then a "When to use" line.
  - H2 sections, exactly this set:
      ## Name the defect class      — generalize the confirmed instance to
                                      the property of the system that allowed
                                      it (e.g. "any .sh file can be committed
                                      without its executable bit"), stated so
                                      class membership is mechanically
                                      checkable; distinguishes instance-level
                                      prevention (the regression test from
                                      wrap-up) from class-level prevention
                                      (this phase).
      ## Sweep for latent instances — search the codebase/system for other
                                      current members of the class; record
                                      method (exact commands/queries), scope,
                                      and results; an explicit "0 found" is a
                                      valid recorded outcome; scale sweep
                                      depth to class breadth; when the sweep
                                      needs access the orchestrator lacks,
                                      hand the engineer the exact command and
                                      ask for paste-back rather than guessing
                                      (same access rule as evidence
                                      gathering).
      ## Choose a guardrail layer   — the guardrail ladder, strongest rung
                                      first: make the defect impossible
                                      (types, construction, removing the
                                      footgun) > static check / lint > test >
                                      CI gate > runtime check > process or
                                      documentation; prefer the highest rung
                                      whose cost fits the class; the
                                      instance's regression test is the
                                      floor, never the class guardrail.
      ## Decide and record          — propose a concrete guardrail whenever
                                      the sweep found members or the class
                                      plausibly regrows; declining a proposed
                                      guardrail requires a journaled
                                      cost/benefit rationale plus explicit
                                      engineer sign-off; "no guardrail
                                      warranted" is a legitimate outcome only
                                      with the analysis recorded.
      ## Journal                    — record the class statement, sweep
                                      method/scope/results, and the guardrail
                                      decision with its status in the
                                      journal's Prevention section.
Errors: n/a.

Invariants:
  - Evidence-gated mandate: the analysis artifacts (class statement, sweep,
    recorded decision) are always required; a built artifact never is. The
    doc must never word building the guardrail as unconditionally mandatory.
  - Ritual-guardrail warning: the doc explicitly warns against token
    guardrails produced to satisfy the phase (e.g. relabeling the instance
    regression test as the class guardrail).
  - The engineer decides build/decline; the orchestrator proposes and
    records. Guardrail work is scoped OUTSIDE the current fix unless the
    engineer folds it in.

Edge cases:
  - Genuinely one-off causes (transient external outage, code slated for
    deletion, one-time migration script): the analysis still runs; the
    recorded outcome is a justified "no guardrail warranted".
  - Sweep finds members beyond the current deliverable's scope: record them
    and surface to the engineer; never silently expand the fix.
  - An adequate guardrail already exists: verify it would actually have
    caught this instance (if it would have, why didn't it?) and record that
    as the outcome.
-->

# Prevention

NotImplemented: B12
