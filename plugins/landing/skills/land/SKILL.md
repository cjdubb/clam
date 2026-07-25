---
name: land
description: Land finished work onto the repo's main branch by following the landing policy declared in .claude/clam-profile.jsonc (github-pr or local-merge). Use when implementation is complete and verified and it is time to "land this", "ship it", "open the PR", or "merge to master", or when the tracking plan reaches its landing step.
---

<!--
Contract: B02 landing-skills-jsonc-update

Behavior:
  Read the merge and deploy policy from .claude/clam-profile.jsonc (JSONC
  format, profile-version 2). Extract merge.strategy, merge.target,
  merge.merged-by, merge.verify, and merge.merge-style. Dispatch on
  merge.strategy (github-pr or local-merge) following the same precondition,
  verify, and dispatch logic as v1. The JSONC comments serve as workflow
  notes for the orchestrator (same role as the old markdown body).

  Key mapping from v1 → v2:
    landing-strategy   → merge.strategy
    landing-target     → merge.target
    landing-merged-by  → merge.merged-by
    landing-verify     → merge.verify
    landing-merge-style → merge.merge-style
    landing-cleanup    → merge.cleanup

  New v2 keys (read but not yet acted on by land):
    merge.open-as       — draft | ready
    merge.bot-reviewers — array of {login, trigger, gate}
    merge.human-review  — required | optional | none
    deploy.trigger      — merge-to-target | tag | manual | none
    deploy.verify       — post-deploy verification command

Inputs:
  .claude/clam-profile.jsonc at repo root. Working tree state. .local/TODO.md
  (optional, for pre-land checklist and state updates).

Outputs:
  PR created (github-pr) or branch merged (local-merge). .local/TODO.md
  updated with terminal state and PR URL or merge commit.

Errors:
  - No profile: stop, offer /landing:init.
  - Unsupported strategy/combination: stop with explicit error.
  - Dirty tree: stop, list uncommitted paths.
  - github-pr: gh missing/unauthed, no GitHub remote → Blocked.
  - local-merge: no checkout of target → stop and ask.
  - Merge conflict → abort, Blocked with conflicting paths.
  - Post-merge verify failure → Blocked, present revert option.

Invariants:
  - Never lands red (failing verify is not a judgment call).
  - Never guesses a missing policy.
  - github-pr + user: orchestrator never merges the PR.
  - Delegation seam: if a build plugin providing a create-pr skill is
    installed, invoke that for the github-pr path instead of the built-in.
    <!-- NotImplemented: B03 cross-plugin-refs — "deliver" → "build" rename -->

Edge cases:
  - Legacy .md profile with no .jsonc: stop, offer migration via /landing:init.
  - merge.verify unset: skip verify step.
  - Pre-land checklist with unchecked boxes: stop (unfinished work).
-->

# Land

One verb for "get finished work onto the main branch", identical across
repos. The mechanism comes from the repo's committed profile
(`.claude/clam-profile.jsonc`), never from guesswork: plugins ship
mechanism, repos declare policy.

## Step 0 — read the policy

Read `.claude/clam-profile.jsonc` at the repo root (it is committed, so
every worktree has its own checkout). JSONC: strip `//` line comments
before parsing as JSON. The relevant keys, under `merge`:

| Key | Values | Default |
|-----|--------|---------|
| `merge.strategy` | `github-pr` \| `local-merge` | — (required) |
| `merge.target` | branch name | `master` |
| `merge.merged-by` | `user` \| `orchestrator` | — (required) |
| `merge.verify` | single shell command | unset (skip verify) |
| `merge.merge-style` | `no-ff` \| `ff-only` \| `squash` | `no-ff` (local-merge only) |
| `merge.cleanup` | `remove-worktree` \| `keep` | `keep` (local-merge only) |

New v2 keys, read but not yet acted on by this skill: `merge.open-as`
(`draft` \| `ready`), `merge.bot-reviewers` (array of
`{login, trigger, gate}`), `merge.human-review`
(`required` \| `optional` \| `none`), `deploy.trigger`
(`merge-to-target` \| `tag` \| `manual` \| `none`), `deploy.verify`.

Read the profile's JSONC comments too — they carry repo-specific workflow
notes that qualify every step below (same role the markdown body played in
the v1 format).

**No profile file** → stop. Offer to run `/landing:init` (or ask the user
how work lands here). Never guess a strategy. A repo with only the legacy
`clam-profile.md` (previously committed under `.claude/`) and no `.jsonc`
counts as no profile: offer migration via `/landing:init` rather than
reading the legacy file.

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
2. The current branch is not `merge.target`.
3. If `.local/TODO.md` exists, its pre-land checklist (the `## Pre-PR`
   section) is fully checked. Unchecked boxes are unfinished work.

## Step 2 — verify

If `merge.verify` is set, run it from the repo root. Any non-zero exit:
stop, keep tracking state `In Progress`, and fix before retrying. Never
land red — a failing gate is not a judgment call.

## Step 3 — dispatch on strategy

### github-pr

1. Delegation seam: if a `build` plugin providing a create-pr skill is
   installed, invoke that skill for steps 3–4 below instead of the
   built-in path (it owns richer PR conventions). Step 5's tracking
   handoff still applies either way.
   <!-- NotImplemented: B03 cross-plugin-refs — "deliver" → "build" rename -->
2. Preflight: `git remote get-url origin` resolves to a GitHub remote and
   `gh auth status` succeeds. Either failing → tracking state `Blocked`
   with the exact remediation (e.g. `gh auth login`).
3. `git push -u origin <branch>`.
4. `gh pr create --base <merge.target>` with:
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

1. Locate the worktree where `merge.target` is checked out: the
   `git worktree list --porcelain` entry whose `branch` line is
   `refs/heads/<merge.target>`. None found → stop and ask; v0.1 does not
   merge into a branch that has no checkout.
2. Merge the work branch there, honoring `merge.merge-style`:
   - `no-ff`: `git -C <target-worktree> merge --no-ff <branch> -m "<msg>"`
   - `ff-only`: `git -C <target-worktree> merge --ff-only <branch>`
   - `squash`: `git -C <target-worktree> merge --squash <branch>`, then
     commit with `<msg>`.

   Merge message: `Merge branch '<branch>': <one-line summary>` — match
   the repo's own history conventions (see the profile comments).
3. Merge conflict → `git -C <target-worktree> merge --abort`, set State
   `Blocked` with a summary of the conflicting paths, and summon the user.
4. If `merge.verify` is set, re-run it in the target worktree — this
   catches integration breakage the branch-level run could not see. On
   failure: State `Blocked`; present the revert option
   (`git -C <target-worktree> reset --hard ORIG_HEAD`, valid only while
   nothing else has landed since) and let the user decide.
5. Cleanup, only when `merge.cleanup: remove-worktree`:
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
