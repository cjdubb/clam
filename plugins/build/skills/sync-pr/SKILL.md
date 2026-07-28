---
name: sync-pr
description: Update the PR description for the current branch's open PR to reflect the current state of the changes. Use after pushing changes to a branch with an open PR, after addressing review feedback, or whenever the PR description is stale.
---

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
