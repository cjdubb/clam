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

NotImplemented: B11
