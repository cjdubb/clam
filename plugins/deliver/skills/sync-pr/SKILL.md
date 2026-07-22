---
name: sync-pr
description: Update the PR description for the current branch's open PR to reflect the current state of the changes. Use after pushing changes to a branch with an open PR, after addressing review feedback, or whenever the PR description is stale.
---

<!--
Contract: B04 pr-description-sync-skill

Behavior:
  Detects the current branch's open PR, composes an updated description
  reflecting the current state of the branch, and applies it. Works for
  PRs created by any path (lego deliver, /landing:land, manual gh pr create).

  Steps:
  1. Detect PR: query for an open PR on the current branch using
     `gh pr list --head <branch> --state open`. If no open PR, report
     that and stop (not an error).
  2. Read current state: fetch the existing PR description via
     `gh pr view <number> --json body,title,baseRefName`.
  3. Gather context for the updated description:
     a. The diff against the merge target (`git diff <base>...HEAD --stat`
        for an overview, full diff for content).
     b. Plan context: .local/PLAN.md or .local/plans/*.md if present.
     c. Verification results: .local/TODO.md if present (which gates ran,
        their results).
     d. Commit log: `git log <base>..HEAD --oneline` for a change summary.
  4. Resolve the PR body template:
     a. Check standard GitHub template paths (.github/PULL_REQUEST_TEMPLATE.md,
        etc.).
     b. Fall back to a default structure:
        ## Summary, ## Why, ## Changes, ## Verification.
  5. Compose the updated description: fill the template with content from
     the gathered context. Write for a reviewer who has only the diff and
     this description — no access to .local/, the planning session, or
     internal workflow state.
  6. Apply: `gh pr edit <number> --body <new-body>`.
  7. Report what changed (sections added, updated, or unchanged).

Inputs:
  - Current git branch (must have an open PR).
  - Optional: .local/PLAN.md, .local/plans/*.md, .local/TODO.md for richer
    context. Their absence is normal, not an error.

Outputs:
  - PR description updated on the forge.
  - Summary of what changed reported to the user.

Errors:
  - No open PR on current branch: report and stop (not an error state).
  - gh CLI unavailable or unauthenticated: report the issue, suggest
    remediation (gh auth login), stop.
  - gh pr edit fails: report the error, do not retry.
  - No git repo: stop with clear message.

Invariants:
  - Never creates a PR — only updates existing ones.
  - Never modifies the PR title — only the body/description.
  - Never references internal workflow terminology (lego block IDs, unit
    IDs, plan slugs, block-map syntax) in the PR description. Write for
    external reviewers.
  - The PR description always reflects the CURRENT state of the branch,
    not the state at PR creation time.
  - Idempotent: running sync-pr twice without changes produces the same
    description.

Edge cases:
  - Multiple open PRs on the same branch: use the first (most recent).
    This is unusual but not an error.
  - PR was created manually (no .local/ context): compose description
    from diff and commit log alone.
  - Very large diff: summarize rather than include full diff content.
    Focus on the structural changes.
  - PR description was manually edited by the user: overwrite with the
    generated description. The generated description is authoritative;
    manual edits are ephemeral.
  - Base branch has advanced since PR creation: use the current base for
    the diff, not the original base.
-->

NotImplemented: B04 — skill instructions to be written.
