# forge-github

<!--
Contract: B05 forge-github README (scaffold)
Behavior: this README is scaffolded to the locked template
  (plugins/PLUGIN_README_TEMPLATE.md). Section bodies below are
  deliberately unimplemented placeholders; implementation fills them with
  real content covering both skills (create-pr, sync-pr), the formatting
  conventions, and the relationship to the landing plugin's forge
  interface. The required H2 skeleton is contractual and must survive
  implementation unchanged.
-->

GitHub forge implementation: creates pull requests, keeps their
descriptions in sync, and tracks their review, CI, and merge-queue status
via the `gh` CLI, applying flowing-prose formatting conventions so PR text
renders cleanly on GitHub. Implements the forge interface the landing
plugin delegates to, and works standalone without it.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install forge-github@clam
```

Requires the [`gh` CLI](https://cli.github.com/) installed and
authenticated (`gh auth login`) against the GitHub account that should
open and edit pull requests, and a repo whose `origin` remote resolves to
GitHub.

## What to expect

Running `/forge-github:create-pr` pushes the
current branch and opens a pull request; running `/forge-github:sync-pr`
brings an existing open PR's description up to date with the branch. Both
compose flowing-prose descriptions rather than hard-wrapped text, so the
result renders cleanly on GitHub. Running
`/forge-github:address-pr-feedback` fetches a PR's review comments,
proposes a resolution and draft reply for each, and stops for your
approval before changing any code or posting anything. Running
`/forge-github:pr-status` renders a live table of every PR under a
coordination worktree's remit — reviews, CI, merge-queue position, and
merge-readiness sorting — degrading to the branch's own PR in a
single-branch worktree.

One thing runs without being invoked: a Stop hook that refreshes the
worktree's PR-status cache (`.local/.pr-status.json` and
`.local/PR-STATUS.md`, per the repo-level
[PR-status cache protocol](../../docs/protocols/pr-status-cache.md)) at
the end of each turn, so any consumer of that cache renders a current
picture. It is silent, only writes inside a worktree that already has a
`.local/` directory, skips entirely when the cache is under 60 seconds
old, and never fails the session on a network or `gh` error.

## Common workflows

**Open a PR for finished work.** Once a branch has commits ahead of its
base, run `/forge-github:create-pr`. It pushes the branch, composes a
title and description from repo context (plan documents, verification
records, the commit log, and the diff), and opens the pull request with
`gh pr create`.

**Keep a PR description current.** After pushing more commits or
addressing review feedback, run `/forge-github:sync-pr` to recompose the
description from the branch's current state and apply it with `gh pr
edit`. It works on a PR opened by create-pr, by another tool, or by hand.

**Check where everything stands.** Run `/forge-github:pr-status` for a
sorted table of every PR under the effort's remit: state (including
merge-queue position or ejection), reviews, pending reviewers, CI, and a
Notes column surfacing conflicts, unreplied comments, and dependencies.
A coordination worktree (non-empty `.local/.orchestrator`) shows every
PR its planning documents reference; a single-branch worktree degrades
to its own PR.

**Work through review feedback.** When a reviewer leaves comments, run
`/forge-github:address-pr-feedback`. It fetches every comment as
structured data (severity, thread state, location), presents each one
verbatim with a proposed resolution and draft response, and waits for
your approval. Only then does it make the approved fixes, post the
replies, re-sync the description if the changes made it stale, and — once
CI is green — put the PR back in the reviewer's queue with a formal
re-review request.

## Commands

- `/forge-github:create-pr` — push the current branch and open a pull
  request against a base branch, composing the title and description.
- `/forge-github:sync-pr` — update the description of the current
  branch's open pull request to reflect its current state.
- `/forge-github:address-pr-feedback` — triage a pull request's review
  comments, propose resolutions and draft replies for approval, execute
  the approved changes, and request re-review.
- `/forge-github:pr-status` — show a live status table of every PR a
  coordination worktree is shepherding (degrading to the branch's own
  PR in a single-branch worktree), sorted by merge readiness.

Their full behavioral contracts live in the skills' SKILL.md files
(`skills/create-pr/SKILL.md`, `skills/sync-pr/SKILL.md`,
`skills/address-pr-feedback/SKILL.md`, `skills/pr-status/SKILL.md`).

## Relationships to other plugins

This plugin implements the [forge interface](../landing/docs/forge-interface.md)
that the landing plugin's `/landing:land` skill delegates to for the
github-pr path: when landing detects a GitHub origin remote and this
plugin is installed, it invokes `/forge-github:create-pr` with the base
branch, the default body template, and the content context it has already
gathered. Landing is the seam's only consumer — forge-github never
invokes landing, and works standalone whether or not landing is present.

## Uninstalling

```
/plugin uninstall forge-github@clam
```

Uninstalling removes the four skills and the Stop hook; it does not
affect any pull request already created, synced, or commented on by
them, and does not touch your `gh` CLI authentication. A
`.local/.pr-status.json` / `.local/PR-STATUS.md` cache already written
stays where it is — it lives in your worktree, not in the plugin — and
simply stops refreshing.
