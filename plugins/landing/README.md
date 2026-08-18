# landing

One generic landing verb across repos that land work differently: some land
via GitHub PRs the user reviews and merges, some merge worktree branches
straight into the target branch with no forge involved. This plugin owns
that seam so the orchestrator's behavior doesn't have to vary with it —
mechanism (`/landing:land` and `/landing:init`) ships in the plugin; policy
(a user-local `clam-profile.jsonc` in the Claude Code project directory)
is detected and cached per user, never committed to the repo. Detection
assists first-time setup but never silently decides — "who merges" is a
human policy choice, not derivable from git remotes — the same
provider-seam pattern as clam-code's `issue-tracker` (jira/github/none).

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install landing@clam
```

No configuration is required to install. The plugin is otherwise inert
until a landing profile has been recorded — run `/landing:init` to detect
and record one (see Common workflows below).

## What to expect

- **No hooks.** This plugin registers no hooks and injects nothing at
  session start. Discovery happens through the skill catalog.
- **Nothing is written automatically.** The profile is written only when
  `/landing:init` runs and the user confirms the proposed values; work is
  only pushed, PR'd, or merged when `/landing:land` runs.
- **Two skills become available:** `/landing:init` and `/landing:land` (see
  Commands).
- In a repo with no profile recorded, `/landing:land` stops and offers to
  run `/landing:init`.

## Common workflows

### Record how work lands in this repo

Run `/landing:init`. It inspects the repo — remotes, `gh auth status` and
merged-PR history, branch protection on the default branch, worktree
layout, merge-commit history — and proposes a policy: `github-pr` +
`merged-by: user` when GitHub PRs are in evidence, `local-merge` +
`merged-by: orchestrator` when work merges straight to the default branch
with no forge remote, or both options with no default when the evidence is
mixed. Confirm each key (plus `merge-style`/`cleanup` for local-merge) —
"who merges" is always a human decision, never inferred. The skill writes
the profile to the user's Claude Code project directory, preserving any
existing `deploy` section, comments, or unrelated keys other seams added.
The profile is user-local and never committed to the repo. See Commands
for the full key reference.

### Land finished work

Once implementation is complete and verified, run `/landing:land`. It reads
the profile, stops if the working tree is dirty or `.local/TODO.md`'s
pre-land checklist has unchecked boxes, runs `merge.verify` if set, then
dispatches on `merge.strategy`: pushes the branch and opens a PR
(`github-pr`) or merges into the target branch's worktree (`local-merge`),
honoring `merge.merge-style` and `merge.cleanup`. `.local/TODO.md` is
updated with the resulting state either way. See Commands for the full
per-strategy walkthrough.

## Commands

### Skills

**`/landing:init`** — detect, confirm, and record a repo's landing policy
into a user-local `clam-profile.jsonc`. Model-invocable: fires in a repo
with no profile, when asked to "set up the landing workflow" or "configure
how work lands here", or right after installing this plugin.

1. **Inspect** — gather evidence, tolerating individual failures:
   `git remote -v`; `gh auth status` and `gh pr list --state merged --limit
   5`; branch protection on the default branch (`gh api
   repos/{owner}/{repo}/branches/<default>/protection`; 404 means none);
   `git worktree list`; `git log --merges --oneline -5 <default-branch>`;
   the default branch name. Skips the `gh`-based checks when `gh` is
   unavailable.
2. **Propose** — GitHub remote with merged PRs or branch protection →
   `github-pr` + `merged-by: user`; no forge remote with direct merge
   commits → `local-merge` + `merged-by: orchestrator`; mixed or thin
   evidence → both options presented, no default.
3. **Confirm** — walks through `merge.strategy`, `merge.target`,
   `merge.merged-by` (plus `merge.merge-style` and `merge.cleanup` for
   local-merge), offering a `merge.verify` command when a test entrypoint
   is evident (package.json scripts, Makefile, test suites).
4. **Write** — writes `clam-profile.jsonc` to the user's Claude Code
   project directory (`~/.claude/projects/<sanitized-cwd>/`) from the
   template below with the confirmed values. If a profile already exists,
   changes only the confirmed keys and leaves everything else — the
   `deploy` section, comments, unrelated keys — intact, since other seams
   share this file. The profile is user-local and never committed.

#### The profile: `clam-profile.jsonc`

Stored in the user's Claude Code project directory
(`~/.claude/projects/<sanitized-cwd>/clam-profile.jsonc`), never committed
to the repo. JSONC (JSON with `//` line comments): a `merge` section for
landing mechanics, a `deploy` section for what happens after landing, and
comments for the orchestrator's workflow notes. Other seams add their own
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

The `merge.open-as`, `merge.bot-reviewers`, `merge.human-review`, and
`deploy.*` keys are v2 additions: `/landing:init` writes them and
`/landing:land` reads them, but v0.1 does not yet act on them.

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

**`/landing:land`** — land finished work onto the repo's main branch by
following the landing policy. Model-invocable: fires when implementation is
complete and verified and it's time to "land this", "ship it", "open the
PR", or "merge to master", or when the tracking plan reaches its landing
step.

0. **Read the policy** — resolve the profile path
   (`~/.claude/projects/<sanitized-cwd>/clam-profile.jsonc`), read it as
   JSONC (strip `//` comments before parsing). See the profile table above
   for the `merge.*` keys; the v2-only keys are read but not yet acted on.
   No profile → stop, offer `/landing:init`, never guess a strategy.
   Unsupported strategy/combination → stop with an explicit error naming
   the offending value; see Supported policy matrix below for the two
   combinations v0.1 supports.
1. **Preconditions** — stop (and say why) unless all hold: the working
   tree is clean (`git status --porcelain` empty — otherwise list the
   uncommitted paths and stop); the current branch is not `merge.target`;
   and, if `.local/TODO.md` exists, its `## Pre-PR` checklist is fully
   checked.
2. **Verify** — if `merge.verify` is set, run it from the repo root. Any
   non-zero exit stops, keeps tracking state `In Progress`, and must be
   fixed before retrying — landing never lands red.
3. **Dispatch on strategy:**
   - **`github-pr`** — delegates to the forge plugin matching the repo's
     origin remote (e.g. `forge-github`) when one provides a create-pr
     skill, passing the base branch, the default body template, and the
     content context gathered so far (see `docs/forge-interface.md` and
     `templates/pr-body-template.md`); otherwise falls back to the
     built-in path, which checks that `git remote get-url origin`
     resolves to a GitHub remote and `gh auth status` succeeds (`Blocked`
     with exact remediation if either fails), runs
     `git push -u origin <branch>`, then `gh pr create --base
     <merge.target>` with a title and body composed as flowing
     paragraphs — never hard-wrapped — sourced from `.local/PLAN.md` and
     `.local/TODO.md`. Sets tracking state `Awaiting User Review` with
     the PR URL. The orchestrator never merges the PR — under this
     policy, merging is the user's act.
   - **`local-merge`** — locates the worktree where `merge.target` is
     checked out (stops and asks if none is found; v0.1 does not merge
     into a branch with no checkout), merges the work branch there
     honoring `merge.merge-style` (`no-ff`, `ff-only`, or `squash`) with
     the message `Merge branch '<branch>': <summary>`. A conflict aborts
     the merge cleanly and sets state `Blocked` with the conflicting
     paths. If `merge.verify` is set, re-runs it in the target worktree —
     on failure, sets `Blocked` and presents the
     `reset --hard ORIG_HEAD` revert option. Cleanup runs only when
     `merge.cleanup: remove-worktree`, and is skipped — with the commands
     printed for the user instead — when the session's own cwd is the
     worktree being removed. Sets state `Complete`.
4. **Record** — updates `.local/TODO.md` before ending the turn: State per
   the matrix above, `Current Task:` describing what is in flight, and an
   Implementation Log entry with the PR URL or merge commit hash.

### Hooks

This plugin registers no hooks.

## Supported policy matrix (v0.1)

| strategy + merged-by | Action | Terminal tracking state |
|---|---|---|
| `github-pr` + `user` | verify → push branch → `gh pr create` | `Awaiting User Review` |
| `local-merge` + `orchestrator` | verify → merge into target's worktree → optional cleanup | `Complete` |

Any other value or combination stops with an explicit error naming it —
no fallback guessing. Terminal state is derived from the matrix, not a
profile knob, so a contradictory combination cannot be declared.

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

<!--
Contract: B04 landing-forge-interface (README leg)

Behavior:
  Implementation updates this README to match the skill changes:
  - The github-pr bullet in the workflow walkthrough (Commands section)
    describes forge delegation (a forge plugin matching the origin
    remote, e.g. forge-github, handles push+create when installed) with
    the built-in gh path as fallback, and names the flowing-prose
    formatting conventions the built-in path applies. No build
    references.
  - The Roadmap section's "build plugin delegation" item is REMOVED
    (replaced by the forge interface, which is no longer roadmap).
  - Relationships: the build soft-integration bullet loses its
    delegation-seam sentence (build may still detect landing — that is
    build's business, described from build's side only if mentioned at
    all); a forge-plugins bullet is added: landing delegates forge
    operations to an installed forge-<forge> plugin per
    docs/forge-interface.md, and works without one.
  - A pointer to docs/forge-interface.md and templates/
    pr-body-template.md is added where the github-pr path is described.
Invariants:
  - No reference to the build plugin's delegation seam remains anywhere
    in this README.
  - Required H2 skeleton unchanged.
-->

## Roadmap

- **v0.2 candidate — enforcement:** a PreToolUse guard that blocks
  `git merge` into `merge.target` under `github-pr` and `gh pr create`
  under `local-merge`. v0.1 ships awareness (SessionStart injection), not
  enforcement.

## Tests

```
bash plugins/landing/scripts/landing-docs.test.sh
```

## Update

```
/plugin marketplace update clam
claude plugin update landing@clam
```

Both commands are needed: refreshing the catalog never touches an installed
plugin, and updating one is CLI-only — there is no `/plugin update`.
Afterwards run `/reload-plugins` to pick the new version up in the current
session, or restart the session if this plugin ships hooks or agents.

Auto-update is off by default for third-party marketplaces. Even with it
enabled, a plugin that ships hooks stays pinned to the last explicitly
installed version until you run the update command yourself
(anthropics/claude-code#52218).

## Relationships to other plugins

- **Requires:** nothing — this plugin is fully standalone among clam
  plugins. Its only dependency is user-level, not plugin-level: a landing
  profile recorded via `/landing:init` before `/landing:land` has anything
  to act on.
- **Soft integrations:**
  - `build` — detects landing's presence and adds delivery-framework
    context to its own summary.
  - **forge plugins** — `/landing:land`'s github-pr path delegates
    push-and-create to an installed `forge-<forge>` plugin (e.g.
    `forge-github`) matching the repo's origin remote, per
    `docs/forge-interface.md`; landing works without one, falling back
    to its built-in path.
  - `tracking` — landing reads and writes `.local/TODO.md`: the pre-land
    checklist gates Step 1 of `/landing:land`, and Step 4 records the
    terminal state (`Awaiting User Review`, `Complete`, `Blocked`, `In
    Progress`) and an Implementation Log entry there. Landing works
    without `tracking` installed; it just updates the file directly using
    the same conventions.
- **Provides:** the `/landing:land` and `/landing:init` skills and the
  state-transition vocabulary (`Awaiting User Review`, `Blocked`,
  `Complete`) that other plugins reading `.local/TODO.md` key off of.

## Uninstalling

```
/plugin uninstall landing@clam
```

The landing profile in `~/.claude/projects/<sanitized-cwd>/clam-profile.jsonc`
is user-local — uninstalling does not remove it. Delete it by hand if
you no longer want a recorded landing policy. No other files or settings
are written by this plugin.
