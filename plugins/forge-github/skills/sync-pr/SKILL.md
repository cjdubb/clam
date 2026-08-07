---
name: sync-pr
description: Update the description of the current branch's open GitHub pull request to reflect the branch's current state, using flowing-prose formatting conventions. Use after pushing changes to a branch with an open PR, after addressing review feedback, or whenever the PR description is stale.
---

<!--
Contract: B05 forge-github sync-pr

Behavior:
  Implements the "sync description" operation of the forge interface
  (spec: plugins/landing/docs/forge-interface.md). Detects the current
  branch's open PR, composes an updated description reflecting the
  branch's current state, and applies it. Works for PRs created by any
  path (this plugin's create-pr, another tool, manual `gh pr create`).

  Steps:
  1. Detect: `gh pr list --head <branch> --state open`. No open PR:
     report that and stop (expected outcome, not an error). More than
     one: use the most recent.
  2. Read: `gh pr view <number> --json body,title,baseRefName`. The base
     may have moved since creation; all diffs below use the CURRENT base.
  3. Gather context: diff against the base (`git diff <base>...HEAD
     --stat` plus full diff for detail), plan documents (.local/PLAN.md,
     .local/plans/*.md) when present, verification records
     (.local/TODO.md) when present, and the commit log
     (`git log <base>..HEAD --oneline`). Absence of optional context is
     normal: compose from diff and commit log alone.
  4. Resolve the PR body template: the invoker's template, when
     provided, wins; else repo templates (same paths and order as
     create-pr); else the default structure:
       ## Summary, ## Why, ## Changes, ## Verification.
  5. Compose the updated description per the formatting conventions
     below, reflecting the CURRENT state of the branch.
  6. Apply: `gh pr edit <number> --body <new-body>`.
  7. Report which sections were added, updated, or unchanged.

Formatting conventions (identical to create-pr's; both own the fix for
hard-wrapped PR prose):
  - Flowing paragraphs only: NEVER insert hard line breaks inside a
    paragraph, list item, or table cell; line breaks only at markdown
    structural boundaries.
  - Write for a reviewer who has only the diff and this description — no
    internal workflow terminology.

Inputs:
  - Current git branch (must have an open PR for anything to happen).
  - Optional: .local/PLAN.md, .local/plans/*.md, .local/TODO.md.

Outputs:
  - PR description updated on GitHub; summary of changes reported.

Errors:
  - No open PR: report and stop (not an error state).
  - gh missing/unauthenticated: report remediation (gh auth login), stop.
  - `gh pr edit` fails: report the error as returned, do not retry.
  - Not a git repository: stop with a clear message.

Invariants:
  - Never creates a PR — only updates existing ones.
  - Never modifies the PR title — only the body.
  - Idempotent: running twice with no new commits produces the same body.
  - The description reflects the branch's current state, not its state at
    PR creation time.
  - Works standalone: no other plugin is required for this skill to run.

Edge cases:
  - PR created manually with no .local/ context: diff + commit log alone.
  - Very large diff: summarize structural changes.
  - Description manually edited since last sync: the generated
    description is authoritative and overwrites manual edits.
  - Hard-wrapped prose in the existing description: replaced by reflowed
    flowing paragraphs (conventions win over the prior body's form).
-->

Update the description of the current branch's open pull request so it
reflects the branch's current state, whether the PR was opened by this
plugin's create-pr skill, another tool, or a manual `gh pr create`.

## Detect

Look for an open PR on the current branch with `gh pr list --head
<branch> --state open`. If there is no open PR, report that and stop —
this is an expected outcome, not an error. If more than one open PR is
found, use the most recent.

## Read

Read the PR with `gh pr view <number> --json body,title,baseRefName`.
The base branch may have moved since the PR was created, so every diff
gathered below is computed against the current base, not the base
recorded at creation time.

## Gather context

Gather the same kind of context create-pr uses: the diff against the
current base (`git diff <base>...HEAD --stat`, with the full diff pulled
in for detail), plan documents (`.local/PLAN.md`, `.local/plans/*.md`)
when present, verification records (`.local/TODO.md`) when present, and
the commit log (`git log <base>..HEAD --oneline`). Absence of optional
context is normal — a PR created manually with no `.local/` context is
composed from the diff and commit log alone.

## Resolve the PR body template

Use the same paths and order as create-pr: the invoker's own template,
when provided, wins; otherwise a repository template, checked
case-sensitively in order — `.github/PULL_REQUEST_TEMPLATE.md`,
`.github/pull_request_template.md`, `docs/pull_request_template.md`,
`PULL_REQUEST_TEMPLATE.md`, `pull_request_template.md`; otherwise the
default structure:

```
## Summary
## Why
## Changes
## Verification
```

## Compose

Compose the updated description so it reflects the branch's current
state — not its state at PR creation time — applying the formatting
conventions below. If the existing description was manually edited since
the last sync, the generated description is authoritative and overwrites
those manual edits. If the existing description contains hard-wrapped
prose, replace it with reflowed flowing paragraphs; the conventions win
over the prior body's form.

## Apply

Apply the new body with `gh pr edit <number> --body <new-body>`. Never
touch the title. If `gh pr edit` fails, report the error exactly as
returned; do not retry.

## Report

Report which sections were added, updated, or unchanged.

## Formatting conventions

Identical to create-pr's, and both own the fix for hard-wrapped PR prose.
These conventions apply to every composed description, whatever the
content source.

- Flowing paragraphs only: never insert hard line breaks inside a
  paragraph, list item, or table cell; line breaks appear only at
  markdown structural boundaries.
- Write for a reviewer who has only the diff and this description — no
  internal workflow terminology.

## Errors

- No open PR: report and stop; this is not an error state.
- `gh` missing or unauthenticated: report the remediation (`gh auth
  login`) and stop.
- `gh pr edit` fails: report the error as returned, do not retry.
- Not a git repository: stop with a clear message.

## Invariants

- Never creates a PR — only updates existing ones.
- Never modifies the PR title — only the body.
- Idempotent: running it twice with no new commits produces the same
  body both times.
- The description reflects the branch's current state, not its state at
  PR creation time.
- Works standalone: no other plugin is required for this skill to run.

## Edge cases

- PR created manually with no `.local/` context: compose from the diff
  and commit log alone.
- Very large diff: summarize structural changes rather than pasting the
  diff into the description.
- Description manually edited since the last sync: the generated
  description is authoritative and overwrites manual edits.
- Hard-wrapped prose in the existing description: replaced by reflowed
  flowing paragraphs.
