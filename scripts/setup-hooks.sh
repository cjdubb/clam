#!/bin/bash
# One-time opt-in: point core.hooksPath at the committed scripts/githooks/.
#
# Run: bash scripts/setup-hooks.sh [--remove]

# <!--
# Contract: B03b setup-hooks (plan 001-pseudo-ci)
#
# Behavior:
#   Idempotently sets core.hooksPath to the RELATIVE path "scripts/githooks"
#   in the repository's shared git config, activating the committed hooks
#   for this clone — and, in a bare-repo-plus-worktrees layout, for every
#   worktree at once, since worktrees share the common config and a
#   relative hooksPath resolves against each worktree's own root at hook
#   time. Refuses to run outside a clam checkout. --remove reverses the
#   change, restoring git's default hooks behavior.
#
# Inputs:
#   - Optional flag: --remove — unset core.hooksPath instead of setting it.
#     Any other argument is a usage error.
#   - The git repository containing the cwd. Clam-checkout detection: the
#     repo root must contain .claude-plugin/marketplace.json whose "name"
#     is "clam" (read via jq).
#   - Requires: git, bash, jq.
#
# Outputs:
#   - Install: "hooks enabled: core.hooksPath = scripts/githooks (all
#     worktrees of this repo)" on first run; "hooks already enabled" when
#     the value is already exactly "scripts/githooks" (exit 0 both ways).
#   - Remove: "hooks disabled" after unsetting; "hooks were not enabled"
#     when core.hooksPath was not set (exit 0 both ways — idempotent).
#   - All state-changing output states what was written and where.
#
# Errors:
#   - Not inside a git repository: diagnostic on stderr, exit 2.
#   - Not a clam checkout (marker missing or name != "clam"): diagnostic on
#     stderr, exit 2, config untouched.
#   - jq not available: diagnostic on stderr, exit 2.
#   - core.hooksPath already set to a DIFFERENT value: print the current
#     value and a resolution hint, exit 1, config untouched — never
#     clobber someone's existing hooks silently.
#   - --remove when core.hooksPath is set to a different value than ours:
#     same refusal, exit 1 — only remove what we installed.
#   - Usage error (unknown flag): usage line on stderr, exit 2.
#
# Invariants:
#   - Idempotent: any number of repeat runs of either mode converges to
#     the same state with exit 0.
#   - Writes exactly one config key (core.hooksPath) at the repository
#     scope (git config without --global/--system); never touches user or
#     system git config, never touches files.
#   - The configured value is always the relative literal
#     "scripts/githooks" — never an absolute path, which would break
#     sibling worktrees.
#   - Standalone bash+git+jq; no clam plugins, no Claude Code assumed.
#
# Edge cases:
#   - Plain (non-worktree) clone of the repo: works identically; the
#     relative path resolves against that clone's root.
#   - Run from a subdirectory of a worktree: repo detection via git
#     rev-parse; behaves the same.
#   - Branch without scripts/githooks/ checked out (dir absent at
#     activation time): still succeeds — git treats a missing hooksPath
#     dir as "no hooks", and the committed pre-push additionally no-ops
#     where ci.sh is absent.
# -->

usage() {
  echo "usage: setup-hooks.sh [--remove]" >&2
}

REMOVE=0
if [ "$#" -eq 0 ]; then
  :
elif [ "$#" -eq 1 ] && [ "$1" = "--remove" ]; then
  REMOVE=1
else
  usage
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel 2>&1)" || { echo "setup-hooks: $ROOT" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || {
  echo "setup-hooks: jq is required but was not found in PATH" >&2
  exit 2
}

MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
if [ ! -f "$MARKETPLACE" ]; then
  echo "setup-hooks: not a clam checkout ($MARKETPLACE not found)" >&2
  exit 2
fi

NAME="$(jq -r '.name // empty' "$MARKETPLACE" 2>/dev/null)"
if [ "$NAME" != "clam" ]; then
  echo "setup-hooks: not a clam checkout (marketplace name is '$NAME', expected 'clam')" >&2
  exit 2
fi

cd "$ROOT" || { echo "setup-hooks: cannot cd to $ROOT" >&2; exit 2; }

CURRENT="$(git config --get core.hooksPath 2>/dev/null)"

if [ "$REMOVE" -eq 0 ]; then
  if [ -z "$CURRENT" ]; then
    git config core.hooksPath scripts/githooks
    echo "hooks enabled: core.hooksPath = scripts/githooks (all worktrees of this repo)"
    exit 0
  elif [ "$CURRENT" = "scripts/githooks" ]; then
    echo "hooks already enabled"
    exit 0
  else
    echo "setup-hooks: core.hooksPath is already set to '$CURRENT'; refusing to overwrite. To switch, run: git config core.hooksPath scripts/githooks" >&2
    exit 1
  fi
else
  if [ -z "$CURRENT" ]; then
    echo "hooks were not enabled"
    exit 0
  elif [ "$CURRENT" = "scripts/githooks" ]; then
    git config --unset core.hooksPath
    echo "hooks disabled"
    exit 0
  else
    echo "setup-hooks: core.hooksPath is set to '$CURRENT', which this tool did not install; refusing to remove it." >&2
    exit 1
  fi
fi
