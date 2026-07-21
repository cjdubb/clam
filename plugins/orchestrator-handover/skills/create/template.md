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

# Orchestrator handover: {ISSUE-KEY}: {one-line subject}

**Author session:** {current orchestrator worktree name}, {current issue key}
**Recipient:** orchestrator picking up {ISSUE-KEY}
**Proposed worktree:** `orchestrate-{ISSUE-KEY}-{short-description}`
**Issue:** {ISSUE-KEY} (parent: {parent-issue})

> No issue tracker in use? Replace `{ISSUE-KEY}` throughout with a short
> descriptive slug (for example `improve-caching`), and drop or mark any
> header field above that names an issue as `n/a`.

## Source-of-truth artifacts

Read these, in this order, before doing anything else:

| Artifact | Purpose |
|----------|---------|
| {path or PR/issue link} | {why it matters} |

## What is done

- {bullet list of what's already merged, decided, or agreed upstream}

## What is open

- {bullet list of what the recipient orchestrator must drive to completion}

## Pending decisions

For each open decision: the question, the options already explored, the
trade-offs, and — if you have one — a recommendation. The recipient can
accept it or re-deliberate.

- **{decision name}**: {one-line question}
  - Option A: {description, trade-offs}
  - Option B: {description, trade-offs}
  - Recommendation: {if any}

If there are no pending decisions, write **None**.

## Proposed work breakdown

A pre-analyzed breakdown the recipient orchestrator can validate or adjust
during its own planning. Each item:

- **{item name}**: scope, issue key (if filed), proposed branch name, rough
  size estimate

Treat this as a starting point, not a fait accompli — the recipient
orchestrator owns its own splitting decisions.

## Cross-unit compatibility notes

If work across units shares interfaces, types, or data contracts, list them
here so the recipient can carry them through into each unit's own tracking
doc.

- {shared interface / type / contract: exact shape and where it lives}

If there are no shared interfaces across units, write **None**.

## Recipient's first move

The source orchestrator has already created this worktree and placed this
handover — plus the local artifacts listed above — in `.local/`. Your first
move:

1. Skim this document in full, then the source-of-truth artifacts above
   (the local ones are already in your `.local/`).
2. If the session-modes plugin is installed, its `/start` may detect this
   handover automatically; if it is not installed, read this document as
   your own starting point instead.
3. Continue through your own orchestration workflow's gates from wherever
   it begins, using the parent issue noted above.
