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
      9. Wrap-up           — journal completed: root cause statement, fix
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
-->

NotImplemented: B01
