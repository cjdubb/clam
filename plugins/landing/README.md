# landing

<!--
Contract: B07 landing-readme
Behavior:
  Update the existing landing README to meet all 4 issue #61 sections.
Inputs:
  The existing README content, PLUGIN_README_TEMPLATE, plugin directory scan.
Outputs:
  Three updates to the existing README:
    1. Add ## Getting started — install command
       (/plugin marketplace add cjdubb/clam, /plugin install landing@clam),
       note that the first step after installing is /landing:init to set up
       the repo's clam-profile.
    2. Add or formalize ## Relationships to other plugins — document that
       the landing plugin works with tracking (updates TODO.md state),
       lego (dispatch uses /landing:land for main-prs delivery), and the
       worktree layout.
    3. Add ## Uninstalling — uninstall command
       (/plugin uninstall landing@clam), note that the .claude/clam-profile.jsonc
       is a committed repo file and stays in place.
Errors: n/a (documentation).
Invariants:
  - Preserve ALL existing content: profile schema table, policy matrix,
    skills docs, hook docs, failure modes, roadmap, tests sections.
  - The existing "Skills" section already serves as the "Commands" section;
    do not duplicate.
  - Follow PLUGIN_README_TEMPLATE section order for new sections.
Edge cases:
  - The existing README is very detailed; new sections should be concise
    to avoid bloating it further.
-->

One generic landing verb across repos that land work differently.

The post-implementation flow — "get finished work onto master/main" — varies
per repo: some land via GitHub PRs the user reviews and merges, some merge
worktree branches straight into the target branch with no forge involved.
The orchestrator's behavior should not vary with it. This plugin owns that
seam:

- **Mechanism (this plugin):** `/landing:land`, `/landing:init`, and a
  SessionStart hook that injects the repo's declared policy into every
  session.
- **Policy (each repo):** one committed file, `.claude/clam-profile.jsonc`.

Detection assists first-time setup but never silently decides — "who
merges" is a human policy choice, not derivable from git remotes. Same
provider-seam pattern as clam-code's `issue-tracker` (jira/github/none).

## The profile: `.claude/clam-profile.jsonc`

Committed to each consumer repo. JSONC (JSON with `//` line comments): a
`merge` section for landing mechanics, a `deploy` section for what happens
after landing, and comments for the orchestrator's workflow notes — the
same role the v1 markdown body played. Other seams add their own
top-level sections and unknown keys to the same file; this plugin ignores
anything outside `merge`/`deploy`.

| Key | Values | Default |
|-----|--------|---------|
| `profile-version` | `2` | — |
| `merge.strategy` | `github-pr` \| `local-merge` | — (required) |
| `merge.target` | branch name | `master` |
| `merge.merged-by` | `user` \| `orchestrator` | — (required) |
| `merge.verify` | single shell command run before landing | unset (skip) |
| `merge.merge-style` | `no-ff` \| `ff-only` \| `squash` | `no-ff` (local-merge only) |
| `merge.cleanup` | `remove-worktree` \| `keep` | `keep` (local-merge only) |
| `merge.open-as` | `draft` \| `ready` | `ready` |
| `merge.bot-reviewers` | array of `{login, trigger, gate}` | `[]` |
| `merge.human-review` | `required` \| `optional` \| `none` | `none` |
| `deploy.trigger` | `merge-to-target` \| `tag` \| `manual` \| `none` | `none` |
| `deploy.verify` | post-deploy verification command | unset |

A PR-flow repo:

```jsonc
{
  "profile-version": 2,

  // Merge policy
  "merge": {
    "strategy": "github-pr",
    "target": "master",
    "merged-by": "user"
  },

  // Deploy policy
  "deploy": {
    "trigger": "manual"
  }

  // Orchestrator pushes the branch and opens the PR; the engineer reviews
  // and merges. The orchestrator never merges to master.
}
```

A local-merge repo:

```jsonc
{
  "profile-version": 2,

  // Merge policy
  "merge": {
    "strategy": "local-merge",
    "target": "master",
    "merged-by": "orchestrator",
    "merge-style": "no-ff",
    "cleanup": "keep"
  },

  // Deploy policy
  "deploy": {
    "trigger": "none"
  }

  // Worktree branches merge straight into master (no forge, no PRs); keep
  // the "Merge branch '<name>': <summary>" message convention.
}
```

Migrating from the legacy `clam-profile.md` (previously committed under
`.claude/`, flat `landing-*` keys)? Run `/landing:init` — it detects the
old file, maps each key onto the `merge`/`deploy` schema above, carries
the markdown body over as comments, and confirms the mapped values before
writing the new `.jsonc` file.

## Supported policy matrix (v0.1)

| strategy + merged-by | Action | Terminal tracking state |
|---|---|---|
| `github-pr` + `user` | verify → push branch → `gh pr create` | `Awaiting User Review` |
| `local-merge` + `orchestrator` | verify → merge into target's worktree → optional cleanup | `Complete` |

Any other value or combination stops with an explicit error naming it —
no fallback guessing. Terminal state is derived from the matrix, not a
profile knob, so a contradictory combination cannot be declared.

## Skills

- `/landing:land` — the generic verb: read policy → preconditions (clean
  tree, off-target branch, pre-land checklist green) → `merge.verify` →
  dispatch on strategy → update `.local/TODO.md`. Never lands red; never
  guesses a missing policy.
- `/landing:init` — detect (remotes, `gh` auth, branch protection, merge
  history, worktree layout) → propose with evidence → user confirms →
  write the profile, preserving other seams' keys, the `deploy` section,
  and comments when the file already exists.

## Hook

`landing-context.sh` (SessionStart): reads `.claude/clam-profile.jsonc`,
strips `//` comments, and injects the parsed policy line
(`strategy=… , target=… , merged-by=…`) plus the instruction to land via
`/landing:land` — or, when the repo has no profile, a nudge that
`/landing:init` records one. The legacy `.md` path is never consulted:
a repo with only that file is treated as having no profile. Fail-open: no
`jq` on PATH, no cwd in the payload, an unreadable profile, or invalid
JSON left after comment-stripping all produce no output rather than
breaking session start.

## Failure modes

- No profile → offer `/landing:init`; never guess.
- Legacy `.md`-only repo → treated as no profile; offer migration via
  `/landing:init`.
- Unknown strategy / unsupported combination → explicit error.
- Dirty working tree → stop and list the uncommitted paths.
- github-pr: `gh` missing or unauthenticated, or no GitHub remote →
  `Blocked` with exact remediation.
- local-merge: target checked out in no worktree → stop and ask (v0.1
  does not merge into an unchecked-out branch).
- local-merge conflict → abort the merge cleanly, `Blocked` with the
  conflicting paths.
- Post-merge verify failure → `Blocked`; present the
  `reset --hard ORIG_HEAD` revert option, user decides.
- Cleanup targeting the session's own cwd → skipped; commands printed for
  the user instead.

## Roadmap

- **v0.2 candidate — enforcement:** a PreToolUse guard that blocks
  `git merge` into `merge.target` under `github-pr` and `gh pr create`
  under `local-merge`. v0.1 ships awareness (SessionStart injection), not
  enforcement.
- **deliver plugin delegation:** the `deliver` plugin's create-pr skill is
  the delegation target for `/landing:land`'s github-pr path (the seam is
  already in the skill) — this replaces the earlier standalone
  `pr-workflow` plugin plan.

## Tests

```
bash plugins/landing/scripts/landing-context.test.sh
bash plugins/landing/scripts/landing-docs.test.sh
```
