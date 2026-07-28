---
name: per-worker
description: "Use when dispatching parallel workers or subagents that will commit, create branches, or open pull requests, or when handing a branch off to another session or human. Documents the worktree-per-worker pattern: give each git-writing worker its own isolated worktree so parallel writes never race on a single checkout."
---

# Worktree per worker

Whenever more than one worker is going to write to git — commit, create a branch,
push, or open a pull request — give each writing worker its own worktree. This
pattern is intentionally framework-agnostic: it applies the same whether "worker"
means a dispatched subagent, a separate Claude Code session, or a human you're
handing a branch to. It says nothing about how workers are dispatched or
coordinated, only how to keep their git writes from colliding.

## Why isolation

A git checkout has exactly one branch checked out at a time. If two workers write
to git from the same working directory — committing, branching, or checking out a
different ref — they race: one worker's commit can land on the wrong branch, or
one worker's uncommitted changes can be overwritten when the other checks out
something else. Giving each writing worker its own worktree gives it its own
working directory, index, and checked-out branch, so no worker can step on
another's changes.

This only matters for writes. Parallel work that is strictly read-only —
searching, reading, analysis — needs none of this; there's nothing to race over
when nobody is writing.

## When to use it

Check whether the repo you're in follows the worktree-root layout: a directory
containing a bare clone at `.bare/`, with individual worktrees living as sibling
directories (the layout the `usage` skill's `newtree`/`rmtree` helpers manage).

- If that layout is available, give one worktree per writing worker — provision
  each worker's worktree before it starts writing.
- If the repo is a regular checkout with no `.bare` layout, don't try to
  improvise isolation. Run writing workers sequentially instead: one worker
  writes and finishes (commits, pushes, opens its PR) before the next one
  starts.

## Lifecycle

1. **Create.** From the worktree root, run `newtree <branch-name>` (see the
   `usage` skill for the mechanics: how it resolves the root, what happens on an
   existing branch, etc.). This creates a new worktree as a sibling directory
   and lands you in it.
2. **Record the absolute path.** Immediately capture the worktree's ABSOLUTE
   path — e.g. `pwd` right after `newtree`, or compose the two in one call:
   `cd <root> && newtree <branch> && pwd`. A relative path is only meaningful
   from wherever you happened to be standing; the worker won't be.
3. **Hand off.** Give the worker both the absolute path and the branch name,
   and require it to work only under that path — never elsewhere in the tree,
   and never inside another worker's worktree.
4. **Integrate.** The worker commits, pushes, and opens its pull request (PR)
   from inside its own worktree, against its own branch. Because the worktree
   is isolated, none of that can race with another worker's git writes.
5. **Clean up.** Once the branch is merged or otherwise no longer needed, run
   `rmtree <dir-name>` from the root. Note that `rmtree` takes the dashed
   DIRECTORY name (e.g. `feat-my-feature`), not the branch name (e.g.
   `feat/my-feature`) — see the `usage` skill for the slash-to-dash mapping.
   `rmtree` refuses to remove a dirty worktree (one with uncommitted changes),
   so first decide whether the work should be committed/merged or thrown away;
   pass `--force` only when you intend to discard it.

## Hand-off examples

Both examples below are equally valid ways to hand off a worker's worktree;
neither is the "right" one — pick whichever matches how the work is actually
going to happen.

- **Dispatching a subagent.** After creating the worktree and recording its
  absolute path, launch the subagent with that path as its explicit working
  directory — e.g. tell it to do all its work in
  `/abs/path/to/feat-my-feature` and never `cd` outside that directory. The
  subagent commits, pushes, and opens its PR from inside that worktree, then
  reports back.
- **Handing off to a separate session or human.** Instead of dispatching a
  subagent at all, just hand the worktree over: share the absolute path and
  branch name with a teammate, or leave it for a separate session (or
  yourself, later) to pick up. Whoever continues only needs the path and the
  branch name — the worktree is an ordinary git checkout, so any tool or
  person can `cd` into it and keep working.
