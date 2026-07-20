#!/usr/bin/env bash
# worktree.sh — lego unit-worktree lifecycle helper.
#
# Contract: B01 worktree-lib
#
# Behavior:
#   Manages the git worktrees, branches, and delivery PRs for lego work
#   units. Run from the repo root of the integration worktree (the branch
#   lego was started on). Subcommands:
#
#   add <plan-slug> <unit-id> <unit-slug>
#     Creates branch "lego/<plan-slug>/<unit-id>-<unit-slug>" at the current
#     HEAD plus a git worktree for it at
#     "<worktreeDir>/<repo-basename>-<unit-id>", where <worktreeDir> is
#     delivery.worktreeDir from .local/config.json (missing/empty → the
#     parent directory of the repo root; a relative value resolves against
#     the repo root) and <repo-basename> is the basename of the repo root.
#     Seeds the new worktree's .local/ directory:
#       - .local/config.json copied verbatim
#       - .local/unit.md: the single line "# Unit <unit-id>", then exactly
#         the "## B<NN> — ..." sections of the integration worktree's
#         .local/blocks.md whose "- Unit:" field equals <unit-id>, verbatim
#       - every .local/contracts/B<NN>-*.md whose B<NN> belongs to one of
#         those sections, copied to the same relative path (silently skipped
#         when no such file exists)
#     Then runs the repo test command (commands.test) inside the new worktree
#     as a baseline check. On success prints the new worktree's absolute path
#     as the LAST line of stdout and exits 0.
#
#   merge <unit-id>
#     From the integration worktree: finds the unique local branch matching
#     glob "lego/*/<unit-id>-*" and merges it into the current branch with
#     --no-ff and commit message "lego: merge <branch-name>". Refuses when
#     the working tree has uncommitted tracked changes.
#
#   deliver <base-branch> <unit-id> [<unit-id>...]
#     Builds delivery branch "lego/deliver/<unit-id>[+<unit-id>...]" (ids in
#     argument order) from <base-branch> in a temporary worktree. For each
#     unit, in argument order:
#       - resolves the unit branch (unique match of "lego/*/<unit-id>-*") and
#         the unit's block paths: the comma-separated "- Code:" entries of
#         every blocks.md section whose "- Unit:" equals the unit id, each
#         path trimmed of surrounding spaces
#       - finds on the unit branch the newest commit with subject exactly
#         "lego(<unit-id>): tests" and the newest with subject exactly
#         "lego(<unit-id>): implementation"; the implementation commit is
#         required, the tests commit is optional (untested prose units)
#       - when the tests commit exists: restores the block paths from it and
#         commits with subject "lego(<unit-id>): contract + tests"; then
#         restores the block paths from the implementation commit and commits
#         with subject "lego(<unit-id>): implementation". A restore that
#         produces no changes creates no commit.
#     Pushes the delivery branch to the "origin" remote and opens a PR
#     against <base-branch> with `gh pr create`; the PR title is
#     "lego: <unit-id list>" and the body lists, for every delivered block,
#     its "## B<NN> — ..." heading line and its "- Contract:" line from
#     blocks.md. Removes the temporary worktree (the local delivery branch
#     remains) and prints the PR URL as the LAST line of stdout.
#
#   remove <unit-id>
#     Removes the unit's worktree via `git worktree remove` (fails on a dirty
#     tree) and deletes its branch with `git branch -d` (fails when unmerged).
#
# Inputs:
#   Positional arguments as above. .local/config.json (jq-parsed;
#   commands.test required; delivery.worktreeDir optional). .local/blocks.md
#   with "- Unit:" and "- Code:" fields per block section. Must run inside a
#   git work tree, at the repo root.
#
# Outputs:
#   Human-readable progress on stderr only. Machine-consumable result — the
#   worktree path (add) or PR URL (deliver) — as the last stdout line.
#   Exit 0 on success.
#
# Errors:
#   exit 2 — usage error: unknown subcommand, wrong argument count, or an id/
#            slug containing characters outside [A-Za-z0-9._-]; prints usage
#            to stderr.
#   exit 3 — missing dependency or input: jq absent; gh absent (deliver
#            only); .local/config.json missing or commands.test absent/empty;
#            .local/blocks.md missing; not inside a git work tree.
#   exit 4 — state error: unit-id matches no blocks.md section (add/deliver);
#            branch or worktree path already exists (add); zero or multiple
#            unit-branch matches (merge/deliver/remove); dirty working tree
#            (merge); baseline test failure (add); required implementation
#            commit missing (deliver); delivery branch already exists
#            (deliver); unmerged branch (remove); underlying git/gh failure.
#   Every error prints exactly one line starting "ERROR: " to stderr.
#
# Invariants:
#   - Files in the invoking worktree are modified only by `merge`, and only
#     through `git merge` itself; no subcommand edits files there directly.
#   - `add` cleans up everything it created in the same invocation on any
#     failure: no half-created branch, worktree, or seed survives.
#   - Only creates or deletes branches under "lego/" and worktrees it created
#     itself; all other branches and worktrees are untouched.
#   - Deterministic: identical repo state and arguments produce identical
#     names and results.
#
# Edge cases:
#   - Multiple blocks sharing one unit: unit.md carries all their sections;
#     deliver restores the union of their Code paths.
#   - Code paths containing spaces are preserved verbatim (comma is the only
#     separator in a "- Code:" list).
#   - Repeated `add` or `deliver` for the same unit fails (exit 4); existing
#     artifacts are never silently reused.
#   - A unit whose blocks have no "- Code:" paths cannot be delivered
#     (treated as unit-id matching no deliverable content, exit 4).
set -euo pipefail

echo "NotImplemented: B01 worktree.sh" >&2
exit 42
