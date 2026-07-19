---
name: per-worker
description: "TODO(B03): NotImplemented"
---

<!--
Contract: B03 skill-per-worker
Behavior:   model-invocable skill documenting the worktree-per-worker pattern:
            provisioning an isolated worktree for each worker performing git
            write operations, framework-agnostically.
Inputs:     frontmatter description carries the trigger context (dispatching
            parallel workers/subagents that will commit, branch, or open PRs;
            handing a branch to another session); model invocation enabled.
Outputs:    required sections:
            - Why isolation: a checkout has exactly one branch; parallel
              writers sharing a working directory race (wrong-branch commits,
              overwritten files); read-only parallel work needs none of this.
            - When to use it: worktree-root layout available -> one worktree
              per writing worker; regular repo (no .bare layout) -> run
              writing workers sequentially instead.
            - Lifecycle: create (newtree from the root, per the usage skill);
              record the worktree's ABSOLUTE path (pwd after newtree); hand
              off — give the worker the absolute path and branch name and
              require it to work only under that path; integrate (commit/push/
              PR from inside the worktree); clean up (rmtree <dir-name> after
              merge; --force only to discard intentionally).
            - Hand-off examples, briefly, at least two: a subagent instructed
              with an explicit working directory, and a handover to a separate
              session/human; both presented as equally valid.
Errors:     n/a (documentation).
Invariants: UNOPINIONATED — must not mandate any orchestration framework,
            agent tool, naming scheme, or branch workflow; must serve both
            orchestrator-handover and subagent-orchestration styles; must
            cross-reference the `usage` skill for helper mechanics rather than
            duplicating them.
Edge cases: worker leaves the worktree dirty (rmtree refuses; decide merge vs
            --force discard); worktree dir name vs branch name confusion at
            cleanup (rmtree takes the dashed directory name).
-->

# Worktree per worker

TODO(B03): NotImplemented.

## Why isolation

TODO(B03): NotImplemented.

## When to use it

TODO(B03): NotImplemented.

## Lifecycle

TODO(B03): NotImplemented.

## Hand-off examples

TODO(B03): NotImplemented.
