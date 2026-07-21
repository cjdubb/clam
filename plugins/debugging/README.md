<!--
Contract: B11 plugin-composition

Behavior:
  The composition block for the debugging plugin: this README documents how
  the parts compose, and the block's integration test
  (scripts/structure.test.sh) mechanically verifies the cross-file contract
  below. Dispatched only after B01-B10 are accepted.

Inputs: n/a (composition surface; children are B01-B10).

Outputs (required document structure — tests assert these):
  - H1 `# debugging` and a one-paragraph purpose statement matching the
    marketplace description in spirit.
  - H2 sections, exactly this set:
      ## Usage           — invocation (/debugging:root-cause), what the
                           orchestrator experiences phase by phase, and that
                           the skill is also model-invocable.
      ## Artifacts       — the .local/debug/NNN-<slug>/ layout: journal.md,
                           queries/NN-<name>/ (query file + results.md),
                           paste-back flow in two sentences.
      ## Components      — table listing the skill, the six references, the
                           two templates, and debug-session.sh with a
                           one-line role each.

Cross-file integrity (the composed behavior structure.test.sh verifies):
  - Every references/*.md path named in SKILL.md exists.
  - Every ${CLAUDE_PLUGIN_ROOT}/... path named in SKILL.md or the references
    resolves to a file within this plugin.
  - debug-session.sh's script-relative template paths exist
    (templates/journal.md, templates/query-results.md).
  - Section names the skill/references cite in the templates (Hypotheses,
    Probe Log, Queries, Results, Interpretation) match the template
    headings exactly.
  - plugin.json parses; its name is "debugging"; its version matches the
    marketplace entry's version and the root README row's version.
  - End-to-end artifact smoke: `start` then `query` in a temp .local
    produces the contracted tree (defers to B09's own tests for detail;
    here only the composed shape is asserted).

Errors: n/a.

Invariants:
  - This README describes only what exists; it never documents planned or
    absent behavior.

Edge cases: n/a.
-->

# debugging

Root-cause debugging guidance for orchestrator sessions: a single skill
sequences a bug from reported symptom to a confirmed root cause —
establishing a reliable reproduction, mining what changed, running a
differential diagnosis, isolating by binary search, and gathering log and
database evidence, handing the engineer exact queries to paste results back
whenever the orchestrator lacks direct access itself.

## Usage

Invoke the loop directly with `/debugging:root-cause`, or let it pick itself
up: the skill is also model-invocable, so a session that runs into a bug, a
regression, or any "why is this happening?" question mid-conversation can
start the loop without an explicit command.

Phase by phase, the orchestrator experiences: intake (expected vs actual,
scope, first-seen, distilled into a one-line problem statement); session
setup (`debug-session.sh start <slug>` creates the session directory every
later phase journals into); reproduce (reach a reliable repro before deep
diagnosis); what changed (build the candidate-change timeline across every
change surface); differential diagnosis (a hypothesis table, weighed and
pruned probe by probe); isolate (binary-search whatever search space
survives); evidence gathering (logs and database, queried directly or handed
to the engineer via paste-back); a root-cause gate that accepts a cause only
once it explains every piece of recorded evidence; and wrap-up, where the
journal gets its root-cause statement, fix direction, and a note that the
reproduction becomes the regression test.

## Artifacts

Each investigation gets its own directory, `.local/debug/NNN-<slug>/`,
sequentially numbered and created by `debug-session.sh start`. Inside it,
`journal.md` is the running record the orchestrator keeps current through
every phase, and `queries/` holds one `NN-<name>/` directory per piece of
external evidence gathered, each pairing the query file itself with a
`results.md`.

The paste-back flow: when the orchestrator can't reach logs or the database
directly from the session, it writes the exact query into the query file and
fills in `results.md`'s header, then hands the engineer that file's path and
asks them to paste the raw output into its Results section. The orchestrator
writes the Interpretation only after those results arrive, feeding the
finding back into the journal's Hypotheses table.

## Components

| Component | Role |
| --- | --- |
| `skills/root-cause/SKILL.md` | Sequences the root-cause debugging loop phase by phase; defers technique depth to `references/`. |
| `references/reproduce.md` | Technique reference for reaching a reliable, quantified reproduction. |
| `references/what-changed.md` | Technique reference for building the candidate-change timeline across every change surface. |
| `references/differential-diagnosis.md` | Technique reference for building and weighing the hypothesis table until one survivor explains all evidence. |
| `references/binary-search.md` | Technique reference for halving history, code path, data, configuration, or environment to isolate a cause. |
| `references/logs.md` | Technique reference for gathering log evidence, direct or via paste-back, across common log tools. |
| `references/database.md` | Technique reference for read-only database evidence gathering, direct or via paste-back. |
| `templates/journal.md` | Per-investigation journal template, copied verbatim into each new session directory. |
| `templates/query-results.md` | Paste-back results template, copied verbatim into each query directory. |
| `scripts/debug-session.sh` | CLI that creates the numbered session and query directories from the templates above. |
