# landing

One generic landing verb across repos that land work differently.

The post-implementation flow — "get finished work onto master/main" — varies
per repo: some land via GitHub PRs the user reviews and merges, some merge
worktree branches straight into the target branch with no forge involved.
The orchestrator's behavior should not vary with it. This plugin owns that
seam:

- **Mechanism (this plugin):** `/landing:land`, `/landing:init`, and a
  SessionStart hook that injects the repo's declared policy into every
  session.
- **Policy (each repo):** one committed file, `.claude/clam-profile.md`.

Detection assists first-time setup but never silently decides — "who
merges" is a human policy choice, not derivable from git remotes. Same
provider-seam pattern as clam-code's `issue-tracker` (jira/github/none).

## The profile: `.claude/clam-profile.md`

Committed to each consumer repo. YAML frontmatter for machines, markdown
body for the orchestrator. Keys are **flat and namespaced by seam**
(`landing-strategy`, not nested YAML) so hooks can parse them with awk —
no YAML-parser dependency. Future seams (issue-tracker, verify-mode, …)
add their own key prefixes and body sections to the same file.

| Key | Values | Default |
|-----|--------|---------|
| `profile-version` | `1` | — |
| `landing-strategy` | `github-pr` \| `local-merge` | — (required) |
| `landing-target` | branch name | `master` |
| `landing-merged-by` | `user` \| `orchestrator` | — (required) |
| `landing-verify` | single shell command run before landing | unset (skip) |
| `landing-merge-style` | `no-ff` \| `ff-only` \| `squash` | `no-ff` (local-merge only) |
| `landing-cleanup` | `remove-worktree` \| `keep` | `keep` (local-merge only) |

A PR-flow repo:

```markdown
---
profile-version: 1
landing-strategy: github-pr
landing-target: master
landing-merged-by: user
---
# Workflow notes
Orchestrator pushes the branch and opens the PR; the engineer reviews and
merges. The orchestrator never merges to master.
```

A local-merge repo:

```markdown
---
profile-version: 1
landing-strategy: local-merge
landing-target: master
landing-merged-by: orchestrator
landing-merge-style: no-ff
landing-cleanup: keep
---
# Workflow notes
Worktree branches merge straight into master (no forge, no PRs); keep the
"Merge branch '<name>': <summary>" message convention.
```

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
  tree, off-target branch, pre-land checklist green) → `landing-verify` →
  dispatch on strategy → update `.local/TODO.md`. Never lands red; never
  guesses a missing policy.
- `/landing:init` — detect (remotes, `gh` auth, branch protection, merge
  history, worktree layout) → propose with evidence → user confirms →
  write the profile, preserving other seams' keys and the body when the
  file already exists.

## Hook

`landing-context.sh` (SessionStart): injects the parsed policy line
(strategy / target / merged-by) plus the instruction to land via
`/landing:land`, or — when the repo has no profile — a nudge that
`/landing:init` records one. Fail-open: no jq, no cwd, or an unreadable
profile produces no output rather than breaking session start. Frontmatter
values are sanitized (non-printables dropped, capped at 40 chars) and the
body is never parsed by the hook.

## Failure modes

- No profile → offer `/landing:init`; never guess.
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
  `git merge` into `landing-target` under `github-pr` and `gh pr create`
  under `local-merge`. v0.1 ships awareness (SessionStart injection), not
  enforcement.
- **pr-workflow delegation:** once the planned `pr-workflow` plugin is
  ported, `/landing:land`'s github-pr path delegates to its `create-pr`
  skill (the seam is already in the skill).

## Tests

```
bash plugins/landing/scripts/landing-context.test.sh
```
