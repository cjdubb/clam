# The layered config — the repo interface

The plugin is technology-agnostic; everything repo-specific enters through
one layered config, resolved as the jq recursive merge (`.[0] * .[1]`) of
two files at the repo root, both optional, at least one required:

- **`.claude/lego.json`** — the committed base. Commands, models,
  testPatterns, delivery mode: facts about the repo and team decisions.
  Because it is committed, every worktree and every fresh clone inherits it
  via git checkout — repo config never needs copying between worktrees.
  Created by `/lego:plan` (autodetected, then confirmed with the engineer)
  and versioned like code.
- **`.local/config.json`** — an optional gitignored local override,
  deep-merged over the base (override wins per key). Machine-specific
  values (`delivery.worktreeDir`), personal tweaks. It is also the escape
  hatch: an engineer who cannot commit workflow files puts the whole config
  here and accepts that it is per-clone.

Merge semantics are jq's recursive merge: nested objects merge per key with
the override winning; arrays and scalars are replaced whole. One deliberate
exception: `testPatterns` is the **union** of both files' arrays (applied by
`scripts/realm.sh`) — the test-file family can only grow, never shrink.

The effective config is read by the skills, the realm library, worker
briefs, and `scripts/worktree.sh`.

> **Known gap, by design:** this interface is expected to be the weakest part
> of v0 and to evolve through dogfooding. Problems found in real repos should
> be fixed here first, not worked around in skills.

## Schema

```json
{
  "commands": {
    "test": {
      "unit": "nx affected -t unit-test",
      "integration": "nx affected -t integration-test",
      "e2e": "nx affected -t playwright-e2e",
      "default": "unit"
    },
    "typecheck": "npx tsc --noEmit",
    "build": "npm run build",
    "lint": "npx eslint ."
  },
  "models": {
    "testWriter": "sonnet",
    "implementer": "sonnet"
  },
  "testPatterns": [],
  "delivery": {
    "mode": "main-prs",
    "prSizeBudget": 500
  }
}
```

| Field | Required | Meaning |
|---|---|---|
| `commands.test` | yes | Runs the repo's test suite; string or variants object, see below. Used for red runs and acceptance gates. |
| `commands.typecheck` | no | Strongest scaffold-gate rung. |
| `commands.build` | no | Second scaffold-gate rung. |
| `commands.lint` | no | Third rung; also run at impl acceptance when present. |
| `models.testWriter` | no | Model passed to lego-test-writer dispatches. Default `sonnet`. |
| `models.implementer` | no | Model passed to lego-implementer dispatches. Default `sonnet`. |
| `testPatterns` | no | Extra globs added to the test-file family, matched against basename and full path by `scripts/realm.sh` (requires `jq`; silently skipped without it). Unioned across both config files. Use for repo conventions the built-in family misses (e.g. `conftest.py`, `tests/*`). |
| `delivery.mode` | no | Delivery mode: `"main-prs"` or `"local-only"`. Absent → behaves as `local-only`. See "Delivery" below. |
| `delivery.worktreeDir` | no | Directory where unit worktrees are created. Missing/empty → the parent directory of the repo root. A relative value resolves against the repo root. Machine-specific — belongs in the `.local/config.json` override, not the committed base. |
| `delivery.prSizeBudget` | no | Per-PR changed-line budget `scripts/pr-size-check.sh` measures against. Default `500`. A team decision — belongs in the committed base, not the local override. |

## Multiple test commands

`commands.test` is either:

- **a string** — the single test command, used everywhere; or
- **an object of named variants** with a `"default"` field naming the
  variant to use when nothing more specific is chosen:

  ```json
  "test": {
    "unit": "npm run -w backend test",
    "frontend": "npm run -w frontend test -- --watch=false",
    "e2e": "npm test",
    "default": "unit"
  }
  ```

  The variants are every key except `default`; `default` is a key
  reference, never itself a command. An object without `default`, or a
  `default` naming an absent or empty variant, is a config error.

Who uses what:

- **Mechanical consumers** (`worktree.sh add`'s baseline check) always run
  the `default` variant. Prefer the cheapest reliable tier as default —
  usually unit tests with no infrastructure needs.
- **The orchestrator** chooses the appropriate variant per dispatch brief —
  the test type matching what the unit touches. Scope-specific permutations
  (`nx run mylib:unit-test` instead of `nx affected -t unit-test`) are
  constructed by the orchestrator at brief-writing time; config records the
  repo's test *types*, not every scope permutation.
- **Workers** run whatever command their brief names; the config is their
  fallback only when the brief is silent.

Variants whose infrastructure cannot be assumed present (a docker database,
a running app stack — common for integration/e2e/storybook tiers) should
not be `default`; briefs name them only when the orchestrator knows the
environment provides what they need. Declaring those prerequisites in
config is a known gap, deliberately deferred (variant values staying plain
strings keeps a future per-variant object form backward-compatible).

## Delivery

`delivery.mode` governs how accepted work units are delivered:

- `main-prs` — each PR group of accepted units is raised as a PR **targeting
  master/main only**; lego never opens a PR against any other branch. Every
  PR contains only complete blocks (contract + tests + implementation), never
  a bare stub.
- `local-only` — accepted units merge into the integration branch and the
  engineer delivers manually.

A missing `origin` remote or a missing `gh` CLI degrades `main-prs` behavior
to `local-only`, with a warning emitted by dispatch.

PR grouping is not config: it is recorded per work unit in the plan document
and `.local/blocks.md` (`PR group:`), decided with the engineer at plan time.

## The built-in test-file family

Single source of truth: `scripts/realm.sh`. Basenames `*.spec.*`, `*.test.*`,
`*_test.*`, `*_spec.*`, `test_*`, plus any path containing a `__tests__/`
segment. `testPatterns` extends this per repo; nothing can shrink it.

## Scaffold-gate ladder

`/lego:scaffold` runs the strongest configured rung: `typecheck` >
`build` > `lint` > none (gate defers to the test wave's red run). The rung used
is recorded in the plan document, so the strength of the composition proof is
always explicit.
