---
name: usage
description: "TODO(B02): NotImplemented"
---

<!--
Contract: B02 skill-usage
Behavior:   model-invocable skill that teaches Claude Code to recognize a
            bare-clone worktree root and correctly invoke the four git-helpers
            utilities (newtree, rmtree, copyenv, cloneBareRepo) from the Bash
            tool. Source of truth for all claims: worktree-helpers.sh at
            github.com/cjdubb/git-helpers (current master), NOT the stale
            clam-code creating-worktrees skill.
Inputs:     frontmatter description must carry the trigger phrases so the model
            invokes it when creating/removing worktrees or when newtree/rmtree
            are mentioned; model invocation stays enabled (no
            disable-model-invocation).
Outputs:    required sections, each accurate to current git-helpers:
            - The worktree root: <root>/.bare layout; helpers work from the
              root OR from inside any of its worktrees (they resolve the root
              via the repo's common git dir) — explicitly correct the stale
              claim that they only work from the root.
            - newtree: branch keeps slashes, directory name converts slashes
              to dashes (feat/x -> feat-x/); existing origin/<branch> is
              checked out with upstream set; dash input matches a slashed
              remote branch; otherwise new branch from the resolved default
              branch (cached origin/HEAD -> git remote set-head origin --auto
              -> origin/master fallback with warning); runs `git fetch origin`
              so an `origin` remote is required; cd's into the new worktree —
              teach single-call composition `cd <root> && newtree <branch> &&
              pwd` and capturing the absolute path for later calls; if the
              worktree dir already exists it warns and navigates instead of
              failing; auto-runs copyenv when configured, and a failed copy
              returns non-zero with the worktree KEPT.
            - rmtree: by directory name (not branch name) from the root or a
              sibling; bare `rmtree` from inside a worktree removes that one
              and leaves the shell at the root; refuses dirty worktrees, extra
              flags pass through to `git worktree remove` (e.g. --force).
            - copyenv: --configure <source-dir> [rel-file ...] stored in the
              shared .bare config; paths relative to BOTH source dir and
              worktree; existing files skipped unless --force; --list previews;
              env files are secrets — destination must be gitignored.
            - cloneBareRepo: one-time conversion of a repo into a worktree
              root; setup-git-repo-with-trees.sh as the script equivalent.
            - Helpers not available: try `newtree` DIRECTLY first (Bash tool
              shells initialize from the user profile, so sourced functions
              are usually present); on "command not found", locate the
              managed "# BEGIN GIT-HELPERS" block in ~/.bashrc / ~/.zshrc to
              find worktree-helpers.sh and source it in the same call; never
              fall back to raw `git worktree` commands or hardcoded paths.
Errors:     n/a (skill is documentation; inaccuracies are defects).
Invariants: no machine-specific absolute paths; unopinionated about
            orchestration (worker patterns live in the per-worker skill,
            cross-referenced); invoke as `newtree`, never `./newtree`.
Edge cases: offline (default-branch fallback warning), dirty worktree removal,
            repo without copyenv config (newtree behaves as plain).
-->

# Using git-helpers worktrees

TODO(B02): NotImplemented.

## The worktree root

TODO(B02): NotImplemented.

## newtree

TODO(B02): NotImplemented.

## rmtree

TODO(B02): NotImplemented.

## copyenv

TODO(B02): NotImplemented.

## cloneBareRepo

TODO(B02): NotImplemented.

## If the helpers are not available

TODO(B02): NotImplemented.
