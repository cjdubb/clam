---
name: sync-pr
description: Update the PR description for the current branch's open PR to reflect the current state of the changes. Use after pushing changes to a branch with an open PR, after addressing review feedback, or whenever the PR description is stale.
---

<!--
Contract: B04 pr-description-sync-skill

Behavior:
  Detects the current branch's open PR, composes an updated description
  reflecting the current state of the branch, and applies it. Works for
  PRs created by any path (lego delivery, /landing:land, manual gh pr create).

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

Bring the current branch's open pull request description back in sync
with the branch's actual current state. Run this after pushing new
commits, after addressing review feedback, or any time the PR description
might be stale.

## When to use

- Immediately after pushing to a branch that already has an open PR.
- After addressing review comments, so the description reflects the
  latest round of changes.
- Any time the PR description looks out of date relative to the diff.

## Step 1 — Detect the open PR

Find the open PR for the current branch:

```
gh pr list --head <current-branch> --state open
```

If there is no open PR, this is expected and not an error: report that
there is nothing to sync and stop. Do not create a PR — this skill only
ever updates an existing one.

If more than one open PR is returned for the branch (unusual, but
possible), use the most recent one.

## Step 2 — Read the current PR state

Fetch the existing description and metadata:

```
gh pr view <number> --json body,title,baseRefName
```

Note the current base branch — the base may have moved since the PR was
opened, and the diff in the next step must be computed against the
current base, not the original one. Never modify the PR title; only the
body is ever updated.

## Step 3 — Gather context

Collect the material the new description will be built from:

- **Diff against the merge target.** Use `git diff <base>...HEAD --stat`
  for a structural overview, and the full diff for content detail. For a
  very large diff, summarize the structural changes rather than including
  the entire diff verbatim.
- **Plan context**, if present: a project plan document (for example
  `.local/PLAN.md` or files under `.local/plans/`). Its absence is normal
  — most PRs won't have one, and that's fine.
- **Verification results**, if present: a tracked verification/checklist
  document (for example `.local/TODO.md`) recording which checks or gates
  were run and their outcomes.
- **Commit log**: `git log <base>..HEAD --oneline` for a concise summary
  of the changes that make up the branch.

If none of the optional context (plan, verification) is available —
which is the normal case for a PR opened by hand — compose the
description from the diff and commit log alone.

## Step 4 — Resolve a PR body template

Look for a repo-standard PR template first, in the usual GitHub locations
(for example `.github/PULL_REQUEST_TEMPLATE.md` or
`.github/PULL_REQUEST_TEMPLATE/*.md`). If none exists, fall back to this
default structure:

```
## Summary
## Why
## Changes
## Verification
```

## Step 5 — Compose the updated description

Fill the resolved template using the context gathered in Step 3. Write
for a reviewer who has access only to the diff and this description —
never mention internal workflow scaffolding, planning artifacts, or any
other detail that only makes sense inside the authoring session. The
description should read as a self-contained account of what the PR does
and why, based on the CURRENT state of the branch, not the state when the
PR was first opened.

If the PR description was edited by hand since it was last generated,
treat the generated description as authoritative and overwrite the
manual edits — the generated version is the one kept in sync with the
branch going forward.

## Step 6 — Apply the update

Write the new body back to the PR:

```
gh pr edit <number> --body <new-body>
```

Never touch the title. This skill never creates a PR — if `gh pr edit`
fails (for example, because the PR was closed in the meantime), report
the failure and stop rather than retrying or falling back to creating
one.

## Step 7 — Report the result

Summarize what changed: which sections were added, updated, or left
unchanged. Running this skill twice in a row with no new commits should
produce the same description both times — it is idempotent, not
additive.

## Error handling

- **No open PR for the current branch.** Stop and report this plainly —
  it is an expected outcome, not an error.
- **`gh` CLI unavailable or unauthenticated.** Report the problem and
  point at the fix: run `gh auth login`, then retry. Do not attempt to
  work around a missing or unauthenticated `gh` CLI.
- **`gh pr edit` fails.** Report the error as returned and stop; do not
  retry automatically.
- **Not inside a git repository.** Stop with a clear message; there is no
  branch or PR to operate on.
