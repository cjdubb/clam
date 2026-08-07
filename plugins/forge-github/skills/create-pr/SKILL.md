---
name: create-pr
description: Create a GitHub pull request for the current branch via the gh CLI, composing the title and description with flowing-prose formatting conventions. Use when finished work on a branch needs a PR opened against the repo's main branch.
---

<!--
Contract: B05 forge-github create-pr

Behavior:
  Implements the "create" operation of the forge interface (spec:
  plugins/landing/docs/forge-interface.md). Pushes the current branch to
  origin and opens a GitHub pull request with a composed title and
  description.

  Steps:
  1. Preflight: `gh` CLI available and authenticated (`gh auth status`);
     `git remote get-url origin` resolves to a GitHub remote. Either
     failing: report the exact remediation (e.g. `gh auth login`) and stop.
  2. Duplicate check: if the current branch already has an open PR
     (`gh pr list --head <branch> --state open`), do not create another —
     report the existing PR URL and suggest the sync-pr skill instead.
  3. Push: `git push -u origin <branch>`.
  4. Resolve the PR body template: the invoker's template, when
     provided, wins; else repo templates, checked
     case-sensitively in order (.github/PULL_REQUEST_TEMPLATE.md,
     .github/pull_request_template.md, docs/pull_request_template.md,
     PULL_REQUEST_TEMPLATE.md, pull_request_template.md); if none exists,
     fall back to the default structure:
       ## Summary, ## Why, ## Changes, ## Verification.
  5. Compose title and body per the formatting conventions below. Content
     comes from the invoker when provided (explicit title/body/base
     arguments win); otherwise from repo context: plan documents
     (.local/PLAN.md, .local/plans/*.md), verification records
     (.local/TODO.md), the commit log (`git log <base>..HEAD --oneline`),
     and the diff (`git diff <base>...HEAD --stat`, full diff for detail).
     Absence of optional context is normal, not an error.
  6. Create: `gh pr create --base <base>` with the composed title and body.
     Base branch: the invoker's explicit base when provided, otherwise the
     repo's default branch.
  7. Report the PR URL.

Formatting conventions (own the fix for hard-wrapped PR prose):
  - Write all prose as flowing paragraphs: NEVER insert hard line breaks
    inside a paragraph, list item, or table cell. GitHub renders markdown
    with soft wrapping; hard-wrapped 72-80 column prose renders as ragged,
    prematurely broken lines.
  - Line breaks appear only at markdown structural boundaries: between
    paragraphs, before/after headings, list markers, code fences, tables.
  - Title: imperative one-line summary of the change, no trailing period.
  - Write for a reviewer who has only the diff and this description — no
    internal workflow terminology (block IDs, unit IDs, plan slugs, or any
    label a reviewer cannot look up).

Inputs:
  - Current git branch with commits ahead of the base.
  - Optional invoker-provided title, body content, and base branch.
  - Optional repo context: .local/PLAN.md, .local/plans/*.md, .local/TODO.md.

Outputs:
  - Branch pushed to origin; PR created on GitHub; PR URL reported.

Errors:
  - gh missing/unauthenticated: report remediation, stop. Never work around.
  - Origin is not a GitHub remote: stop with a clear message.
  - Open PR already exists for the branch: stop, report its URL, point at
    sync-pr. Never create a duplicate.
  - No commits ahead of the base: stop — nothing to propose.
  - `gh pr create` failure: report the error as returned, do not retry.

Invariants:
  - Never merges the PR, never force-pushes, never modifies the branch.
  - The formatting conventions above apply to every composed description,
    whatever the content source.
  - Works standalone: no other plugin is required for this skill to run.

Edge cases:
  - Detached HEAD or on the default branch itself: stop with a message.
  - Very large diff: summarize structural changes rather than pasting the
    diff into the description.
  - Invoker provides body content that is hard-wrapped: reflow it into
    flowing paragraphs before composing (conventions win over input form).
-->

Open a pull request for the current branch, pushing it to origin and
composing a title and description that render cleanly on GitHub.

## Preflight

Confirm `gh` is installed and authenticated with `gh auth status`, and
that the repo's origin resolves to a GitHub remote via `git remote
get-url origin`. If `gh` is missing or unauthenticated, report the exact
remediation — typically `gh auth login` — and stop; never work around
it. If the origin is not a GitHub remote, stop with a clear message.

If there are no commits ahead of the base branch, stop: there is nothing
to propose.

## Duplicate check

Before creating anything, check whether the current branch already has
an open PR with `gh pr list --head <branch> --state open`. If one
exists, do not create a duplicate — report the existing PR's URL and
suggest running the sync-pr skill instead to bring its description up to
date.

## Push

Push the branch with `git push -u origin <branch>`.

## Resolve the PR body template

Decide which template supplies the body's structure. The invoker's own
template, when provided, always wins. Otherwise, look for a repository
template, checked case-sensitively in order: `.github/PULL_REQUEST_TEMPLATE.md`,
`.github/pull_request_template.md`, `docs/pull_request_template.md`,
`PULL_REQUEST_TEMPLATE.md`, `pull_request_template.md`. If none of those
exist, fall back to the default structure:

```
## Summary
## Why
## Changes
## Verification
```

## Compose title and body

Content comes from the invoker when provided: explicit title, body, and
base arguments win over anything gathered from the repo. Otherwise,
compose from repo context: plan documents (`.local/PLAN.md`,
`.local/plans/*.md`), verification records (`.local/TODO.md`), the
commit log (`git log <base>..HEAD --oneline`), and the diff (`git diff
<base>...HEAD --stat`, with the full diff pulled in for detail). Absence
of optional context is normal, not an error — compose from whatever is
available.

Apply the formatting conventions below to every composed title and body.

## Create

Open the PR with `gh pr create --base <base>`, passing the composed title
and body. The base branch is the invoker's explicit base when provided,
otherwise the repository's default branch. If `gh pr create` fails,
report the error exactly as returned; do not retry.

## Report

Report the PR URL that `gh pr create` returns.

## Formatting conventions

These conventions own the fix for hard-wrapped PR prose and apply to
every composed description, whatever the content source — repo context,
invoker-supplied text, or a mix of both.

- Write all prose as flowing paragraphs. Never insert hard line breaks
  inside a paragraph, list item, or table cell — GitHub renders markdown
  with soft wrapping, so hard-wrapped 72-80 column prose renders as
  ragged, prematurely broken lines.
- Line breaks appear only at markdown structural boundaries: between
  paragraphs, before and after headings, list markers, code fences, and
  tables.
- The title is an imperative one-line summary of the change, with no
  trailing period.
- Write for a reviewer who has only the diff and this description: avoid
  internal workflow terminology — block IDs, unit IDs, plan slugs, or any
  label a reviewer cannot look up.

## Edge cases

- Detached HEAD, or already on the default branch: stop with a message
  rather than attempting to open a PR.
- A very large diff: summarize the structural changes in the description
  rather than pasting the full diff.
- Invoker-provided body content that is hard-wrapped: reflow it into
  flowing paragraphs before composing — the formatting conventions win
  over the input's original form.

## Invariants

- Never merges the PR, never force-pushes, and never modifies the branch
  beyond the initial push.
- Works standalone: no other plugin is required for this skill to run.
