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
  - Delegation seam: if a deliver plugin providing a create-pr skill is
    installed, invoke that for the github-pr path instead of the built-in.

Edge cases:
  - Legacy .md profile with no .jsonc: stop, offer migration via /landing:init.
  - merge.verify unset: skip verify step.
  - Pre-land checklist with unchecked boxes: stop (unfinished work).
-->

NotImplemented: B02 — skill instructions to be updated for JSONC profile format.
