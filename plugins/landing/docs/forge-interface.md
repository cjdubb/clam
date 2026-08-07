<!--
Contract: B04 forge-interface spec

Behavior:
  This document IS the deliverable: the authoritative specification of the
  forge interface — the seam between the landing plugin (which owns merge
  policy and the landing verb) and forge plugins (which own the mechanics
  of one specific forge). Implementation replaces the NotImplemented
  marker below with the full spec. Tests verify the spec's presence and
  its required clauses, not prose style.

  The implemented spec must define, at minimum:

  1. Naming convention: a forge plugin is named forge-<forge>
     (forge-github, forge-gitlab). The forge is identified from the
     repo's origin remote.
  2. Required operations, each provided as a skill in the forge plugin:
     - create-pr: push the current branch and open a pull/merge request
       against a given base branch, composing title and description.
     - sync-pr: update the description of the current branch's open
       pull/merge request to reflect the branch's current state.
  3. Formatting conventions binding EVERY forge implementation's composed
     output:
     - All prose is written as flowing paragraphs — never hard-wrapped.
       Hard line breaks appear only at markdown structural boundaries
       (headings, list markers, code fences, tables), never inside a
       paragraph, list item, or table cell.
     - Titles are imperative one-line summaries.
     - Descriptions are written for a reviewer who has only the diff —
       no internal workflow terminology.
  4. Delegation: how /landing:land selects and invokes the forge plugin
     matching the repo's remote, what context it passes (base branch from
     merge.target, the default body template when the repo has none,
     content context), and the fallback when no forge plugin is
     installed (landing's built-in path).
  5. Standalone guarantee: forge plugins never require landing (or any
     other plugin) to be installed; the interface is a spec they conform
     to, not a runtime dependency.

Inputs: n/a (specification document).
Outputs: the spec itself, consumed by forge plugin authors and by
  /landing:land's delegation step.
Errors: n/a.
Invariants:
  - The dependency direction is landing → forge plugin (landing detects
    and delegates). A forge plugin never invokes landing.
  - The spec never references lego, build, tracking, or any other
    non-forge plugin.
Edge cases:
  - No forge plugin installed: landing's built-in path applies the same
    formatting conventions itself.
  - Multiple forge plugins installed: the one matching the origin remote
    wins; no match falls back to the built-in path.
-->

# Forge interface

The forge interface is the seam between the landing plugin, which owns
merge policy and the landing verb, and forge plugins, which own the
mechanics of one specific forge (GitHub, GitLab, and so on). Landing
detects which forge plugin applies to the current repo and delegates the
mechanical work to it; a forge plugin implements this interface without
ever depending on landing.

## Naming and remote identification

A forge plugin is named `forge-<forge>` — `forge-github` for GitHub,
`forge-gitlab` for GitLab. The forge is identified from the repo's
origin remote: `git remote get-url origin` resolves to a host, and the
matching `forge-<forge>` plugin, when installed, is the delegation
target.

## Required operations

Every forge plugin provides two skills:

- **create-pr** — push the current branch and open a pull or merge
  request against a given base branch, composing the title and
  description.
- **sync-pr** — update the description of the current branch's open
  pull or merge request to reflect the branch's current state.

## Formatting conventions

These conventions bind every forge implementation's composed output,
whichever operation produces it:

- All prose is written as flowing paragraphs — never hard-wrapped. Hard
  line breaks appear only at markdown structural boundaries (headings,
  list markers, code fences, tables), never inside a paragraph, list
  item, or table cell.
- Titles are imperative one-line summaries.
- Descriptions are written for a reviewer who has only the diff — no
  internal workflow terminology (block IDs, unit IDs, plan slugs, or any
  label the reviewer cannot look up).

## Delegation

`/landing:land` selects the forge plugin matching the repo's origin
remote and invokes its create-pr skill for the github-pr path, passing:

- the base branch, from `merge.target`;
- the default body template
  (`plugins/landing/templates/pr-body-template.md`), used when the repo
  has no PR template of its own;
- the content context landing has already gathered for the change.

When no forge plugin is installed, or none matches the origin remote,
landing falls back to its own built-in path, applying the same
formatting conventions itself.

## Standalone guarantee

Forge plugins never require landing, or any other plugin, to be
installed. This document is a specification a forge plugin conforms to,
not a runtime dependency — `forge-github`, for example, works whether or
not landing is present.

## Invariants

- Dependency direction: landing depends on forge plugins, never the
  reverse. Landing detects and delegates; a forge plugin never invokes
  landing.
- This spec references no plugin outside the forge family.

## Edge cases

- No forge plugin installed: landing's built-in path applies the same
  formatting conventions itself.
- Multiple forge plugins installed: the one matching the origin remote
  wins; no match falls back to the built-in path.
