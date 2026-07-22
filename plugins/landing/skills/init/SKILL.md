---
name: init
description: Detect, confirm, and record a repository's landing policy into a committed .claude/clam-profile.jsonc. Use in a repo that has no clam-profile, when asked to "set up the landing workflow" or "configure how work lands here", or right after enabling the landing plugin in a new repo.
---

<!--
Contract: B02 landing-skills-jsonc-update

Behavior:
  Detect the repo's landing conventions (remotes, gh auth, branch protection,
  merge history, worktree layout), propose a merge + deploy policy, confirm
  with the user, and write .claude/clam-profile.jsonc with the structured
  JSONC schema (profile-version 2, merge/deploy sections). When a legacy
  clam-profile.md (the pre-v2 profile, previously committed under .claude/)
  exists, offer to migrate it to the new format. When a .jsonc profile
  already exists, change ONLY the keys being confirmed
  and preserve everything else (comments, deploy section, unknown keys).

Inputs:
  Repo state (remotes, gh auth, branch protection, merge history, worktree
  layout). User confirmation of proposed policy.

Outputs:
  .claude/clam-profile.jsonc written with confirmed values. User reminded
  to commit the file.

Errors:
  - File write failure: stop and report.
  - gh CLI unavailable: degrade gracefully (skip PR-based detection).

Invariants:
  - "Who merges" is always a human policy choice, never auto-detected.
  - Detection informs the proposal; the user decides.
  - Other profile sections (deploy, comments) are preserved on update.

Edge cases:
  - Legacy .md profile exists but no .jsonc: offer migration.
  - Both .md and .jsonc exist: warn, prefer .jsonc.
  - No forge remote at all: propose local-merge.
  - Mixed evidence (PRs exist but no branch protection): present both
    options with no default.
-->

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

If `gh` is unavailable, skip the PR-based detection steps and rely on the
remaining evidence.

## Step 2 — propose

Map the evidence to a proposed merge policy, and state the evidence in one
or two lines:

- GitHub remote with merged PRs (or branch protection) →
  `github-pr` + `merged-by: user`.
- No forge remote, merge commits straight to the default branch →
  `local-merge` + `merged-by: orchestrator`.
- Mixed or thin evidence → present both options with no default.

## Step 3 — confirm

Walk the user through `merge.strategy`, `merge.target`, and
`merge.merged-by` — and `merge.merge-style` plus `merge.cleanup` for
local-merge — presenting the proposal as the default. Offer a
`merge.verify` command: suggest the repo's own test entrypoint if one is
evident (package.json scripts, Makefile, test suites); leave the key out
otherwise.

## Step 4 — write

Write `.claude/clam-profile.jsonc` from the template below with the
confirmed values, plus JSONC comments recording the evidence and any
repo-specific landing nuance the user mentioned.

If a `.jsonc` profile already exists: change ONLY the keys being confirmed,
leave every other key, the `deploy` section, and existing comments intact
— other seams share this file — and show the diff before writing.

If only the legacy `clam-profile.md` (previously committed under
`.claude/`) exists (no `.jsonc`): offer to migrate it. Map its flat
frontmatter keys onto the new schema
(`landing-strategy` → `merge.strategy`, `landing-target` → `merge.target`,
`landing-merged-by` → `merge.merged-by`, `landing-verify` → `merge.verify`,
`landing-merge-style` → `merge.merge-style`, `landing-cleanup` →
`merge.cleanup`), carry the markdown body over as comments, confirm the
mapped values with the user per Step 3, and write the `.jsonc` file. Leave
the old `.md` file in place unless the user asks to remove it.

If both `.md` and `.jsonc` exist: warn the user about the duplication and
prefer the `.jsonc` file — it is the one every other seam reads.

Remind the user to commit the file: it is repo policy, not local state.

## Template

````jsonc
{
  "profile-version": 2,

  // Merge policy
  "merge": {
    "strategy": "<github-pr | local-merge>",
    "target": "<branch>",
    "merged-by": "<user | orchestrator>",
    "verify": "<single shell command, or omit this key>",
    "merge-style": "<no-ff | ff-only | squash — local-merge only, omit otherwise>",
    "cleanup": "<remove-worktree | keep — local-merge only, omit otherwise>"
  },

  // Deploy policy
  "deploy": {
    "trigger": "<merge-to-target | tag | manual | none>"
  }

  // <How work lands here, in prose: who does what, and any repo-specific
  // conventions the orchestrator must honor when landing.>
}
````
