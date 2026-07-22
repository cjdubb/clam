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
  .claude/clam-profile.md exists, offer to migrate it to the new format.
  When a .jsonc profile already exists, change ONLY the keys being confirmed
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

NotImplemented: B02 — skill instructions to be updated for JSONC profile format.
