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

When to use: once the root-cause gate has passed and the instance is understood — before wrap-up closes out the investigation. This phase asks a different question than everything before it: not "why did this happen" but how do you stop this class of problem from happening again? The analysis is mandatory on every investigation; building a guardrail is optional, a proposal for the engineer to decide on.

## Name the defect class

Generalize the confirmed instance to the property of the system that allowed it to happen — not "this .sh file was committed without its executable bit" but "any .sh file can be committed without its executable bit, because nothing checks for it." State the class so that membership is mechanically checkable: someone, or something, should be able to test whether a given file, config, or code path belongs to the class without needing your judgment call.

This is the line between instance-level prevention and class-level prevention. The regression test you wrote in wrap-up is instance-level — it proves this one file keeps its executable bit. Naming the defect class is what makes class-level prevention possible: a statement general enough to sweep the rest of the codebase against, and specific enough that "member of the class" isn't a matter of opinion.

## Sweep for latent instances

Search the codebase or system for other current members of the class you just named. Record three things: the method (the exact commands or queries you ran), the scope (what you searched — which repos, directories, environments, or tables), and the results (what you found, or didn't).

An explicit "0 found" is a valid, complete recorded outcome — a clean sweep is evidence, not a shortcut you get to skip recording. For the executable-bit class, the sweep might be `find . -name '*.sh' ! -perm -u+x`, scoped to the whole repository; turning up 34 more files missing the bit means recording all 34, not just the count.

Scale sweep depth to class breadth: a class scoped to one file extension in one repo is a five-minute grep; a class like "any endpoint missing auth middleware" spans every service and warrants a scripted, systematic sweep instead of a manual look. Match the effort to how wide the class actually is, not to how the first instance felt.

When the sweep needs access you don't have — a production database, a third-party dashboard, an internal system you can't query — hand the engineer the exact command or query and ask for a paste-back of the results rather than guessing at what a sweep would find. This is the same access rule that applies during evidence gathering.

Edge case — sweep finds members beyond scope: if the sweep turns up members beyond the current deliverable's scope, record them and surface the list to the engineer — never silently expand the fix to cover them. Broader remediation is the engineer's call, not something you fold in quietly on your way out.

## Choose a guardrail layer

The guardrail ladder, strongest rung first — walk it top-down and stop at the first rung that plausibly fits the class:

1. **Make the defect impossible** — types, construction, or removing the footgun entirely, so the defect class cannot occur at all.
2. **Static check / lint** — a lint rule or static analyzer flags every instance of the class automatically.
3. **Test** — a test beyond the single instance's regression test, exercising the class directly.
4. **CI gate** — a pipeline check blocks merge or deploy whenever the class recurs.
5. **Runtime check** — a runtime check (assertion, validation, monitor) catches the class after it's already shipped, at execution time rather than before.
6. **Process or documentation** — a checklist step, review requirement, or written guidance that relies on a human doing the right thing.

Prefer the highest rung whose cost fits the class: expensive rungs (impossible-by-construction, a new lint rule) pay for themselves on classes that will keep recurring; a class that's cheap and unlikely to regrow may only warrant a lower rung. The instance's regression test from wrap-up is the floor, never the class guardrail — it proves this one instance stays fixed, but does nothing for the next member of the class that hasn't been written yet.

Watch for ritual guardrails: a guardrail built, or an existing artifact relabeled, just to have something to point at for this phase — like calling the instance's regression test "the guardrail" — protects nothing beyond the single instance it already covered. A guardrail is only real if it would catch a *different* member of the class.

## Decide and record

The engineer decides whether to build the guardrail or decline it; your job is to propose and record, not to decide unilaterally. Propose a concrete guardrail whenever the sweep found members of the class, or whenever the class plausibly regrows even if this sweep came back clean — a "0 found" result on a class that's easy to reintroduce (a missing lint rule, a manual step nobody automated) still deserves a proposal.

Declining a proposed guardrail requires a journaled cost/benefit rationale plus explicit engineer sign-off — you don't get to decide "not worth it" and move on unilaterally. Write down what the guardrail would cost to build and maintain against what it would prevent, and get the engineer to sign off on skipping it. "No guardrail warranted" is a legitimate outcome only when that analysis is recorded and justified, never as a default when you'd rather skip the step.

Guardrail work is scoped outside the current fix — treat it as separate follow-up work unless the engineer explicitly folds it into the current deliverable.

Edge case — genuinely one-off causes: a transient external outage, code slated for deletion, or a one-time migration script that will never run again are all real candidates for "no guardrail warranted." Run the analysis anyway — name the class, sweep for it — and record the justified conclusion that no guardrail is worth building, rather than skipping the phase because the cause looks one-off.

Edge case — an adequate guardrail already exists: verify it would actually have caught this instance before crediting it. If it would have, the recorded outcome is that the existing guardrail covers this class — but also ask why it didn't catch this instance (a bypass, a gap, a disabled check) and record that answer too. If it would not have caught this instance, it isn't an adequate guardrail for this class regardless of what it was built for; treat the class as undefended.

## Journal

Record in the session journal's Prevention section:

- **Class statement** — the defect class you named, in the mechanically-checkable form from Name the defect class.
- **Sweep** — method (the exact commands or queries run), scope (what was searched), and results (members found, or the explicit "0 found").
- **Guardrail decision** — the decision and its status: proposed and built, proposed and declined (with the cost/benefit rationale and engineer sign-off), or "no guardrail warranted" (with justification).
