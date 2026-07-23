---
name: root-cause
description: "Root-cause debugging methodology for an orchestrator: establish a reliable repro, mine what changed, run a differential diagnosis, isolate by binary search, and gather log/database evidence — with exact queries handed to the engineer for paste-back when the orchestrator lacks access. Use when investigating a bug, regression, incident, or any 'why is this happening?' issue."
---

<!--
Contract: B01 root-cause-skill

Behavior:
  Guides the orchestrator session through a root-cause debugging loop, from
  symptom intake to a confirmed root cause. The skill is the methodology
  driver only: it sequences phases, gates progress, and points at the
  per-technique references; technique depth lives in references/, never here.

Inputs:
  A reported issue (symptom) from the engineer or from the orchestrator's own
  work. No frontmatter inputs; invoked as /debugging:root-cause or
  model-invoked when debugging work appears.

Outputs (required document structure — tests assert these):
  - Frontmatter with exactly two keys: `name: root-cause` and a non-empty
    `description` that states when to use the skill.
  - Body H2 phases, in this order, each an `## <n>. <name>` heading:
      1. Intake            — capture symptom: expected vs actual, scope,
                             first-seen; one-line problem statement.
      2. Session setup     — run ${CLAUDE_PLUGIN_ROOT}/scripts/debug-session.sh
                             start <slug>; all later phases journal into the
                             created .local/debug/NNN-<slug>/journal.md.
      3. Reproduce         — reach a reliable repro before deep diagnosis;
                             loads references/reproduce.md.
      4. What changed      — build the candidate-change timeline; loads
                             references/what-changed.md.
      5. Differential diagnosis — hypothesis table, evidence for/against,
                             discriminating probes; loads
                             references/differential-diagnosis.md.
      6. Isolate           — binary-search the surviving search space; loads
                             references/binary-search.md.
      7. Evidence: logs and database — gather external evidence; loads
                             references/logs.md and references/database.md;
                             uses the paste-back protocol (debug-session.sh
                             query) whenever the orchestrator lacks access,
                             asking the engineer rather than guessing.
      8. Root cause gate   — a root cause is accepted ONLY when it explains
                             ALL recorded evidence; unexplained evidence
                             reopens phase 5.
      9. Prevention        — mandatory class-level analysis once the gate
                             passes: defect-class statement, latent-instance
                             sweep (method, scope, results — "0 found" is a
                             valid recorded outcome), and a concrete
                             guardrail proposal whenever recurrence potential
                             shows; declining a proposed guardrail requires a
                             journaled cost/benefit rationale plus explicit
                             engineer sign-off; loads
                             references/prevention.md.
     10. Wrap-up           — journal completed: root cause statement, fix
                             direction, repro-as-regression-test note.
Errors:
  n/a (guidance document). Missing sections or unresolved references are
  contract violations caught by tests (shape) and B11 (resolution).

Invariants:
  - Progressive disclosure: each references/*.md is named by relative path
    with a one-line "load when ..." trigger; the skill never inlines the
    technique content it defers.
  - Delegation is OPTIONAL and marked at explicit points (at minimum:
    parallel investigation of independent hypotheses; repro attempts);
    wording must never mandate subagents.
  - Every phase says what to record in the journal before moving on.
  - Access rule: when logs or DB are not reachable from the session, the
    skill instructs handing the engineer the exact query plus how to run it,
    and asking them to paste results back — never skipping the evidence.
  - Altitude cap: body stays methodology-level and under 300 lines.

Edge cases:
  - Issue arrives mid-session (model-invoked): phase 1 still runs; the skill
    must not assume a fresh conversation.
  - No repro achievable: phase 3 defines when to proceed with a flaky repro
    (per references/reproduce.md) and what extra evidence weight that demands.
  - Evidence contradicts the engineer's description: surface the
    contradiction to the engineer; do not silently trust either side.
  - Genuinely one-off root cause (transient outage, code slated for
    deletion): phase 9's analysis still runs; the journaled outcome is a
    justified "no guardrail warranted", never a skipped phase.
  - Engineer declines a proposed guardrail: the decline, its rationale, and
    the sign-off are journaled in the Prevention section; wrap-up proceeds.
-->

# Root Cause

Debugging is a loop, not a hunch. This skill sequences the phases that turn a
reported symptom into a confirmed root cause: capture it precisely, reach a
reliable repro, mine what changed, run a differential diagnosis, isolate by
bisection, gather external evidence, gate acceptance on explaining everything
you've recorded, and close the loop with class-level prevention before
wrap-up. It is the methodology driver only — technique
depth lives in `references/`, loaded one file at a time as each phase needs
it; this file never inlines what a reference already covers. Every phase
writes into the session journal before you move to the next one — the
journal, not your own memory of the conversation, is the record a fresh
reader (including a future you) can trust.

## 1. Intake

- Capture the symptom before touching anything: **expected** vs **actual**
  behavior, **scope** (who/what/how widely affected), and **first seen**
  (when it started, or "always"). Distill these into a one-line problem
  statement — the sentence you'd put at the top of an incident doc.
- Run this phase even when the issue surfaces mid-conversation, layered on
  other work already underway. Do not assume the surrounding context already
  covers intake — write it down explicitly. A debugging need doesn't imply a
  fresh conversation, and gaps hidden in assumed context are exactly what the
  phase 8 gate will later have to catch.
- Journal: record expected/actual, scope, first-seen, and the problem
  statement in the journal's Symptom section before starting phase 2.

## 2. Session setup

- Start the session: `${CLAUDE_PLUGIN_ROOT}/scripts/debug-session.sh start <slug>`,
  with `<slug>` a short lowercase-kebab tag drawn from the problem statement.
- This creates `.local/debug/NNN-<slug>/` with a fresh `journal.md` already
  scaffolded with the sections named below. Every later phase in this loop
  journals into that same `.local/debug/NNN-<slug>/journal.md` — never a new
  file, and never skipped because "it's just a quick check."
- Journal: transcribe phase 1's findings into the Symptom section now, and
  note the session directory path so it's easy to find again mid-session.

## 3. Reproduce

- Before deep diagnosis, reach a reliable repro: same steps, same failure,
  every time (or a quantified rate, e.g. 5/5). A reliable repro is the
  discriminator every later phase leans on — spend real effort here.
- Load `references/reproduce.md` when you need technique guidance: capturing
  the exact failing conditions before touching anything, minimizing the
  repro, automating it into a script or failing test, or judging when a
  flaky repro is good enough to proceed and what extra evidence weight that
  demands from later phases.
- Delegation point (optional): repro attempts — especially ones spanning
  several environments, inputs, or code paths — can be handed to a subagent
  to try in parallel while you continue other work. This is never required;
  a single-threaded repro attempt is equally valid.
- Journal: record repro status (none | flaky | reliable), the steps, and the
  observed rate in the Reproduction section.

## 4. What changed

- Build the candidate-change timeline: bound the window between
  last-known-good and first-seen, then walk it.
- Load `references/what-changed.md` when you need the checklist of change
  surfaces to walk (code, config, data, dependencies, infrastructure, and
  more) and how to correlate candidates against symptom onset without
  mistaking correlation for causation.
- Journal: record the window and the resulting candidate-change list in the
  What Changed section.

## 5. Differential diagnosis

- Turn the candidates (plus standing categories the timeline alone might
  miss) into a hypothesis table: hypothesis, evidence for, evidence against,
  status. Weigh each hypothesis against all evidence gathered so far, then
  design the cheapest probe that discriminates between the survivors.
- Load `references/differential-diagnosis.md` when you need help generating
  hypotheses broadly, weighing evidence that fits more than one hypothesis,
  or designing a discriminating probe.
- Delegation point (optional): independent hypotheses can be investigated in
  parallel by separate subagents. This is never required and never the only
  path — investigating one hypothesis at a time is equally valid.
- Journal: keep the Hypotheses table current after every probe — refute a
  row with the evidence that refuted it, never delete it; the trail matters.

## 6. Isolate

- Binary-search whatever space survives phase 5: history (`git bisect`),
  code path, data, configuration, or environment.
- Load `references/binary-search.md` when you need the discipline for
  running a bisection — one variable per probe, hypothesis/probe/
  expected/observed recorded before each, stopping once the culprit is
  minimal (one commit, one input, one flag).
- Journal: every probe becomes a Probe Log row, win or lose.

## 7. Evidence: logs and database

- Load `references/logs.md` when you need log evidence for the incident
  window — error onset, frequency changes, correlation ids to pivot on.
  Load `references/database.md` when you need to inspect current database
  state — read-only, always.
- Access rule: if you can query logs or the database directly from this
  session, do it. If you cannot, do not guess at what they would show — ask
  the engineer which tool they use and follow the paste-back protocol:
  create the query directory with
  `${CLAUDE_PLUGIN_ROOT}/scripts/debug-session.sh query <session-dir> <name> [ext]`,
  write the exact query into the query file, fill in the results template's
  header (purpose, tool, how to run), then ask the engineer to run it and
  paste the raw output back into its Results section. Interpret only after
  results arrive.
- Edge case: when evidence you gather contradicts what the engineer
  described, say so — surface the contradiction to the engineer rather than
  silently trusting either account over the other.
- Journal: index every query in the Queries section; interpretations feed
  back into the Hypotheses table as evidence.

## 8. Root cause gate

- Accept a root cause only when it explains ALL evidence recorded in the
  journal — every hypothesis row, every probe, every pasted-back result.
- If any recorded evidence is left unexplained, that is not a detail to wave
  away: reopen phase 5 (differential diagnosis) and keep working the
  hypothesis table rather than settling for a plausible-but-incomplete
  story.
- Journal: nothing new is written here beyond keeping the Hypotheses table
  honest — the Root Cause section itself is written once the gate passes,
  in phase 10.

## 9. Prevention

- Mandatory class-level analysis once phase 8's root cause gate passes: every
  confirmed root cause gets generalized from the single instance that
  surfaced it to the defect class it belongs to — the property of the system
  that allowed it, stated so class membership is mechanically checkable.
- Record a defect-class statement: not "this one null check was missing" but
  "any handler on this path skips null checks on optional fields."
- Run a latent-instance sweep for other current members of that class:
  record the method (exact commands/queries run), the scope covered, and the
  results. An explicit "0 found" is a valid recorded outcome — the sweep
  still ran, it just came back clean.
- Whenever the sweep or the defect class shows recurrence potential, propose
  a concrete guardrail — the highest rung that fits the cost: impossible by
  construction, static check or lint, test, CI gate, runtime check, or
  process/documentation. The instance's own regression test (from phase 10)
  is the floor, never a substitute for the class guardrail.
- Declining a proposed guardrail is a legitimate outcome, but never a silent
  one: it requires a journaled cost/benefit rationale plus explicit engineer
  sign-off before wrap-up proceeds.
- Edge case: a genuinely one-off root cause (transient outage, code slated
  for deletion) still runs the full analysis — the journaled outcome is a
  justified "no guardrail warranted", never a skipped phase.
- Edge case: when the engineer declines a proposed guardrail, journal the
  decline together with its cost/benefit rationale and the sign-off in the
  Prevention section; wrap-up proceeds from there.
- Load `references/prevention.md` when you need the guardrail ladder in
  full, how to scope a sweep to the class's breadth, or the ritual-guardrail
  pitfalls to avoid (e.g. relabeling the instance test as the class
  guardrail).
- Journal: record the defect-class statement, the sweep's method/scope/
  results, and the guardrail decision in the journal's Prevention section —
  labels there: `Defect class:`, `Sweep method:`, `Sweep results:`,
  `Guardrail:`.

## 10. Wrap-up

- Write the journal's Root Cause section: the root cause statement, how it
  explains all the evidence, the fix direction, and a note that the repro
  from phase 3 should become a regression test.
- Journal: set the journal's Status to "root cause found" (or "abandoned" if
  the investigation stopped short — keep the journal either way; a
  documented dead end has diagnostic value for the next attempt).
