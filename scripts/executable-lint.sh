#!/bin/bash
# Validates that all .sh files under plugins/ are executable in the git index.
#
# Run: bash scripts/executable-lint.sh (exits non-zero on failure)

# <!--
# Contract: B01 executable-lint
#
# Behavior:
#   Walks all .sh files under plugins/ tracked by git and checks each file's
#   mode in the git index. Fails when any .sh file has mode 100644 (non-
#   executable). Passes when every .sh file is 100755 (executable). Uses the
#   same check()/FAILED/exit pattern as marketplace-lint.sh for consistency
#   across repo-level lint scripts.
#
# Inputs:
#   - The git index of the current worktree (read via git ls-files -s)
#   - Scope: plugins/**/*.sh (all .sh files at any depth under plugins/)
#   - No arguments, no environment variables, no config files
#
# Outputs:
#   - One PASS line per .sh file that is 100755
#   - One FAIL line per .sh file that is 100644, including the file path
#   - A blank line followed by "ALL PASS" (exit 0) or "FAILURES — fix before
#     merging" (exit 1)
#   - When failures exist, a remediation hint line after the summary showing
#     the exact git update-index command to fix all offending files
#
# Errors:
#   - Not inside a git repository: exits 1 with a diagnostic message (git
#     ls-files will fail; the script does not need to add its own guard
#     beyond letting git's error propagate)
#   - No .sh files found under plugins/: exits 0 with a "no files to check"
#     message (vacuous pass — nothing to fail on)
#
# Invariants:
#   - Checks the git INDEX mode, not filesystem permissions — this is the
#     whole point; filesystem state can lie (local chmod +x masks a 100644
#     commit)
#   - Requires only git and bash — no jq, no awk beyond what bash builtins
#     provide
#   - Never modifies any file or git state; read-only
#   - Path resolution is relative to the repo root (found via git
#     rev-parse --show-toplevel or BASH_SOURCE traversal), not the caller's
#     cwd
#
# Edge cases:
#   - .sh file with mode other than 100644 or 100755 (e.g. 100664, 120000
#     symlink): treat as a pass — the lint targets the specific 100644 bug
#     class, not arbitrary mode auditing
#   - Untracked .sh files: not visible to git ls-files, so not checked —
#     correct, since untracked files have no index mode to validate
#   - Staged but uncommitted .sh files: git ls-files -s reflects the index
#     including staged changes, so a staged chmod +x is seen as 100755 —
#     correct, that is the state that will be committed
# -->

echo "NotImplemented: B01" >&2
exit 1
