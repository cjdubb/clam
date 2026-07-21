<!--
Contract: B01 handover-plugin — template
Behavior:   markdown template for the handover document written in step 1 of
            /orchestrator-handover:create. Provides a structured format that
            captures everything the recipient orchestrator needs to pick up
            the sub-effort cold.
Inputs:     populated by the orchestrator session with sub-effort-specific
            content. Placeholder tokens use {ISSUE-KEY}, {short-description},
            {parent-issue}, etc. — issue-tracker-agnostic.
Outputs:    a complete handover document at
            .local/handover-{ISSUE-KEY}.md (or .local/handover-{slug}.md
            when no issue key exists).
Errors:     n/a (template is documentation; inaccuracies are defects).
Invariants: - issue-tracker-agnostic: uses generic terms (issue, parent
              issue) not provider-specific ones (Jira, Sub-Jira, CLIP)
            - all 7 sections present: (1) source-of-truth artifacts,
              (2) what is done, (3) what is open, (4) decisions pending,
              (5) proposed work breakdown, (6) cross-unit compatibility
              notes, (7) recipient's first move
            - sections may be trimmed by the skill when they don't apply,
              but the template itself carries all 7
            - recipient's first move section does not hard-depend on /start
              or subagent-orchestration; references them informationally
Edge cases: - no issue tracker → {ISSUE-KEY} replaced with a descriptive
              slug; header fields that reference issues are omitted or
              marked n/a
            - sub-effort has no pending decisions → section 4 carries a
              "None" marker
            - no shared interfaces across units → section 6 carries a
              "None" marker
-->

<!-- NotImplemented: B01 — template body to be written during implementation.
     The 7-section handover template will be written here following the
     contract above, adapted from clam-code's template.md with issue-tracker
     language generalized. -->

# Orchestrator handover: {ISSUE-KEY}: {one-line subject}

Not yet implemented.
