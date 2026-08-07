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

GitHub forge implementation: creates pull requests and keeps their
descriptions in sync via the `gh` CLI, applying flowing-prose formatting
conventions so PR text renders cleanly on GitHub. Implements the forge
interface the landing plugin delegates to, and works standalone without it.

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

Installing this plugin is inert on its own — nothing runs until you
invoke one of its skills. Running `/forge-github:create-pr` pushes the
current branch and opens a pull request; running `/forge-github:sync-pr`
brings an existing open PR's description up to date with the branch. Both
compose flowing-prose descriptions rather than hard-wrapped text, so the
result renders cleanly on GitHub.

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

## Commands

- `/forge-github:create-pr` — push the current branch and open a pull
  request against a base branch, composing the title and description.
- `/forge-github:sync-pr` — update the description of the current
  branch's open pull request to reflect its current state.

Their full behavioral contracts live in the skills' SKILL.md docblocks
(`skills/create-pr/SKILL.md`, `skills/sync-pr/SKILL.md`).

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

Uninstalling removes the two skills; it does not affect any pull request
already created or synced by them, and does not touch your `gh` CLI
authentication.
