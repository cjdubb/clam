# CLAUDE.md

This repo is a marketplace of **independently installable** Claude Code
plugins. Any given user has some installed and not others — that is the normal
case, not a degraded one, and it is the reason for every rule below.

## Before any edit that crosses a plugin boundary

Read [ARCHITECTURE.md](ARCHITECTURE.md). It is normative. The summary here is
the part that gets broken most often, not a replacement for it. Shared
artifact conventions — session state, decision files, setup stamps, TODO
format — are specified in `docs/protocols/`; a plugin references the
protocol, never the plugin that happens to implement it.

## The layering rule

Plugins form layers, not a graph. A **leaf** owns one concern and is complete
in itself. A **composite** sits above leaves and composes them.

```
build (the only composite)
├── landing
│   ├── forge-github
│   └── forge-gitlab
├── lego
└── tracking
```

Everything under `build` is a leaf. Protocols connect leaves through shared
artifacts, not plugin references.

1. **References point downward only.** A composite may know its components
   exist. A component may never reach up at a composite. "If plugin X is
   installed, delegate to it" is still a dependency on X — conditionality is
   no defence.
2. **Leaf plugins work effectively in isolation.** A leaf must be fully useful
   installed alone, with no sibling and no composite present. A leaf whose
   behaviour thins out when a companion is missing has taken a dependency it
   should not have.
3. **Siblings do not know each other.** ARCHITECTURE.md states this holds
   universally, for every plugin pair — not only the ones this file happens
   to name. If `landing` mentions `tracking` and the user installed only
   `landing`, the agent reading that mention is misled about a plugin that is
   not there.

## Capabilities, not plugins

Plugins require capabilities and artifacts, never plugins; only build may
name components — downward, detect-and-degrade, never required.

A plugin states its goal — "create a worktree" — and reaches for `newtree`
when a skill in the catalog offers it, falling back to raw `git worktree`
when it doesn't. That fallback is **graceful degradation**: every capability
works with or without an enhancing plugin.

## What counts as a reference

Any of these forms inside plugin A naming plugin B is a reference from A to B,
regardless of whether it is conditional, hedged, or in a comment:

| Form | Example |
|---|---|
| Skill invocation | `/landing:land` |
| Marketplace id | `lego@clam` |
| English naming | "the tracking plugin" |
| Filesystem path | `plugins/tracking/lib/…` |

A README mention, a directory-existence check, and a conditional delegation
seam are all dependencies. These are the forms the layering rule is most often
broken in, precisely because none of them look like a dependency as you type
them.

Beware word-sense collisions in the other direction: `landing strategy` in
`lego` is lego's own domain vocabulary, and `build` in one of `blocks.md`'s
`Setup:`/`Test:` command-field lines is a build *command*. Neither is a
plugin reference.

## Not mechanically checkable — your judgement is the only check

- Rule 2 (a leaf genuinely working in isolation) is behavioural.
- Every concern having exactly one architectural owner, and context being
  injected at point-of-use rather than session start, are ARCHITECTURE.md's
  own rulings — see its "Conventions that fall out" section rather than
  re-deriving them here.

## Fixes are usually subtractive

There is deliberately no registry, rule file, or extension seam for
cross-plugin behaviour. The executor is an LLM and repo state is
self-describing, so the fix for a coupling is almost always to **delete**
the offending reference and let an agent reading state without assuming
which plugin wrote it, plus the skill catalog, cover it. Reach for a
mechanism only after that demonstrably fails.

## Checks

`bash scripts/ci.sh` is the full gate (lint, test, validate). Note that
`version-bump-lint` reads **committed** state: a plugin edit without a
`plugin.json` version bump is invisible to installed users, and running
`ci.sh` before committing the bump is a vacuous pass.
