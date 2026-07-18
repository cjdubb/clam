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
  "testPatterns": []
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

## The built-in test-file family

Single source of truth: `scripts/realm.sh`. Basenames `*.spec.*`, `*.test.*`,
`*_test.*`, `*_spec.*`, `test_*`, plus any path containing a `__tests__/`
segment. `testPatterns` extends this per repo; nothing can shrink it.

## Scaffold-gate ladder

`/lego:scaffold` runs the strongest configured rung: `typecheck` >
`build` > `lint` > none (gate defers to the test wave's red run). The rung used
is recorded in the plan document, so the strength of the composition proof is
always explicit.
