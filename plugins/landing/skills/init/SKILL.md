---
name: init
description: Detect, confirm, and record a repository's landing policy into a committed .claude/clam-profile.md. Use in a repo that has no clam-profile, when asked to "set up the landing workflow" or "configure how work lands here", or right after enabling the landing plugin in a new repo.
---

# Landing Init

Create the repo's committed landing policy. Detection informs the proposal;
the user decides — "who merges" is a human policy choice, never derivable
from remotes.

## Step 1 — inspect

Gather evidence; tolerate individual failures (absence is signal too):

- `git remote -v` — is there a GitHub (or other forge) remote at all?
- `gh auth status`, and `gh pr list --state merged --limit 5` — are PRs
  actually in use here?
- Branch protection on the default branch
  (`gh api repos/{owner}/{repo}/branches/<default>/protection`; 404 means
  none).
- `git worktree list` — worktree layout.
- `git log --merges --oneline -5 <default-branch>` — direct merge-commit
  landing history?
- The default branch name (`git symbolic-ref refs/remotes/origin/HEAD`,
  falling back to whichever of `master`/`main` exists locally).

## Step 2 — propose

Map the evidence to a proposed profile, and state the evidence in one or
two lines:

- GitHub remote with merged PRs (or branch protection) →
  `github-pr` + `merged-by: user`.
- No forge remote, merge commits straight to the default branch →
  `local-merge` + `merged-by: orchestrator`.
- Mixed or thin evidence → present both options with no default.

## Step 3 — confirm

Walk the user through strategy, target, and merged-by — and merge-style
plus cleanup for local-merge — presenting the proposal as the default.
Offer a `landing-verify` command: suggest the repo's own test entrypoint if
one is evident (package.json scripts, Makefile, test suites); leave the key
out otherwise.

## Step 4 — write

Write `.claude/clam-profile.md` from the template below with the confirmed
values, plus a body recording the evidence and any repo-specific landing
nuance the user mentioned.

If the file already exists: change ONLY the `landing-*` keys being
confirmed, leave every other frontmatter key and the body intact — other
seams share this file — and show the diff before writing.

Remind the user to commit the file: it is repo policy, not local state.

## Template

````markdown
---
profile-version: 1
landing-strategy: <github-pr | local-merge>
landing-target: <branch>
landing-merged-by: <user | orchestrator>
landing-verify: <single shell command, or delete this line>
landing-merge-style: <no-ff | ff-only | squash — local-merge only, delete otherwise>
landing-cleanup: <remove-worktree | keep — local-merge only, delete otherwise>
---

# Workflow notes

<How work lands here, in prose: who does what, and any repo-specific
conventions the orchestrator must honor when landing.>
````
