---
name: land
description: Land finished work onto the repo's main branch by following the landing policy declared in .claude/clam-profile.md (github-pr or local-merge). Use when implementation is complete and verified and it is time to "land this", "ship it", "open the PR", or "merge to master", or when the tracking plan reaches its landing step.
---

# Land

One verb for "get finished work onto the main branch", identical across
repos. The mechanism comes from the repo's committed profile
(`.claude/clam-profile.md`), never from guesswork: plugins ship mechanism,
repos declare policy.

## Step 0 — read the policy

Read `.claude/clam-profile.md` at the repo root (it is committed, so every
worktree has its own checkout). The flat frontmatter keys:

| Key | Values | Default |
|-----|--------|---------|
| `landing-strategy` | `github-pr` \| `local-merge` | — (required) |
| `landing-target` | branch name | `master` |
| `landing-merged-by` | `user` \| `orchestrator` | — (required) |
| `landing-verify` | single shell command | unset (skip verify) |
| `landing-merge-style` | `no-ff` \| `ff-only` \| `squash` | `no-ff` (local-merge only) |
| `landing-cleanup` | `remove-worktree` \| `keep` | `keep` (local-merge only) |

Read the profile's markdown body too — it carries repo-specific workflow
notes that qualify every step below.

**No profile file** → stop. Offer to run `/landing:init` (or ask the user
how work lands here). Never guess a strategy.

**Unsupported policy** → stop with an error naming the offending value.
v0.1 supports exactly two combinations:

| strategy + merged-by | Action | Terminal tracking state |
|---|---|---|
| `github-pr` + `user` | push branch, open PR | `Awaiting User Review` |
| `local-merge` + `orchestrator` | merge into target's worktree | `Complete` |

## Step 1 — preconditions

Stop (and say why) unless ALL hold:

1. Working tree clean: `git status --porcelain` is empty. Otherwise list
   the uncommitted paths and stop — landing never commits work for you.
2. The current branch is not `landing-target`.
3. If `.local/TODO.md` exists, its pre-land checklist (the `## Pre-PR`
   section) is fully checked. Unchecked boxes are unfinished work.

## Step 2 — verify

If `landing-verify` is set, run it from the repo root. Any non-zero exit:
stop, keep tracking state `In Progress`, and fix before retrying. Never
land red — a failing gate is not a judgment call.

## Step 3 — dispatch on strategy

### github-pr

1. Delegation seam: if a `pr-workflow` plugin providing a `create-pr`
   skill is installed, invoke that skill for steps 3–4 below instead of
   the built-in path (it owns richer PR conventions). Step 5's tracking
   handoff still applies either way.
2. Preflight: `git remote get-url origin` resolves to a GitHub remote and
   `gh auth status` succeeds. Either failing → tracking state `Blocked`
   with the exact remediation (e.g. `gh auth login`).
3. `git push -u origin <branch>`.
4. `gh pr create --base <landing-target>` with:
   - Title: imperative one-line summary of the change.
   - Body: what changed and why, how it was verified (which gates ran and
     their results), and anything the reviewer must know — sourced from
     `.local/PLAN.md` and `.local/TODO.md`.
5. Hand off per `merged-by: user`: set `.local/TODO.md` State to
   `Awaiting User Review` with the PR URL in `Current Task:`, follow the
   tracking plugin's summons rules, and end the turn with the PR URL and
   what the user should review.

The orchestrator NEVER merges the PR — under this policy, merging is the
user's act.

### local-merge

1. Locate the worktree where `landing-target` is checked out: the
   `git worktree list --porcelain` entry whose `branch` line is
   `refs/heads/<landing-target>`. None found → stop and ask; v0.1 does not
   merge into a branch that has no checkout.
2. Merge the work branch there, honoring `landing-merge-style`:
   - `no-ff`: `git -C <target-worktree> merge --no-ff <branch> -m "<msg>"`
   - `ff-only`: `git -C <target-worktree> merge --ff-only <branch>`
   - `squash`: `git -C <target-worktree> merge --squash <branch>`, then
     commit with `<msg>`.

   Merge message: `Merge branch '<branch>': <one-line summary>` — match
   the repo's own history conventions (see the profile body).
3. Merge conflict → `git -C <target-worktree> merge --abort`, set State
   `Blocked` with a summary of the conflicting paths, and summon the user.
4. If `landing-verify` is set, re-run it in the target worktree — this
   catches integration breakage the branch-level run could not see. On
   failure: State `Blocked`; present the revert option
   (`git -C <target-worktree> reset --hard ORIG_HEAD`, valid only while
   nothing else has landed since) and let the user decide.
5. Cleanup, only when `landing-cleanup: remove-worktree`:
   `git worktree remove <work-worktree>` then `git branch -d <branch>`.
   If the session's cwd IS that worktree, skip removal and print both
   commands for the user instead — never delete the directory the session
   is running in.
6. Set State `Complete` with an Implementation Log entry naming the merge
   commit.

## Step 4 — record

Whatever the path, update `.local/TODO.md` before ending the turn: State
per the matrix above, `Current Task:` describing what is in flight, and an
Implementation Log entry carrying the PR URL or merge commit hash.
