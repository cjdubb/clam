# `.local/config.json` — the repo interface

The plugin is technology-agnostic; everything repo-specific enters through this
one file. It is created by `/lego:plan` (autodetected, then confirmed with
the engineer) and read by the skills, the realm library, and worker briefs.
Like the rest of `.local/`, it is git-ignored per-clone via `.git/info/exclude`
by default; teams may deliberately commit it instead.

> **Known gap, by design:** this interface is expected to be the weakest part of
> v0 and to evolve through dogfooding. Problems found in real repos should be
> fixed here first, not worked around in skills.

## Schema

```json
{
  "commands": {
    "test": "npm test",
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
    "worktreeDir": "../<repo-basename>-lego/"
  }
}
```

| Field | Required | Meaning |
|---|---|---|
| `commands.test` | yes | Runs the repo's test suite. Used for red runs and acceptance gates. |
| `commands.typecheck` | no | Strongest scaffold-gate rung. |
| `commands.build` | no | Second scaffold-gate rung. |
| `commands.lint` | no | Third rung; also run at impl acceptance when present. |
| `models.testWriter` | no | Model passed to lego-test-writer dispatches. Default `sonnet`. |
| `models.implementer` | no | Model passed to lego-implementer dispatches. Default `sonnet`. |
| `testPatterns` | no | Extra globs added to the test-file family, matched against basename and full path by `scripts/realm.sh` (requires `jq`; silently skipped without it). Use for repo conventions the built-in family misses (e.g. `conftest.py`, `tests/*`). |
| `delivery.mode` | no | Delivery mode: `"main-prs"` or `"local-only"`. Absent → behaves as `local-only`. See "Delivery" below. |
| `delivery.worktreeDir` | no | Directory where unit worktrees are created. Missing/empty → the parent directory of the repo root. A relative value resolves against the repo root. |

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
