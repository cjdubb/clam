---
name: init
description: Detect, confirm, and record a repository's landing policy into a user-local clam-profile.jsonc. Use in a repo that has no landing profile recorded, when asked to "set up the landing workflow" or "configure how work lands here", or right after enabling the landing plugin in a new repo.
---

# Landing Init

Create the repo's landing policy, stored in the user's local Claude Code
project directory (never committed to the repo). Detection informs the
proposal; the user decides — "who merges" is a human policy choice, never
derivable from remotes.

## Step 1 — inspect

Gather evidence; tolerate individual failures (absence is signal too):

- `git remote -v` — is there a GitHub (or other forge) remote at all?
- `gh auth status`, and `gh pr list --state merged --limit 5` — are PRs
  actually in use here?
- Branch protection on the default branch
  (`gh api repos/{owner}/{repo}/branches/<default>/protection`; 404 means
  none).
- `git worktree list` — worktree layout.
- `git log --merges --oneline -5 <default-branch>` — direct merge-commit
  landing history?
- The default branch name (`git symbolic-ref refs/remotes/origin/HEAD`,
  falling back to whichever of `master`/`main` exists locally).

If `gh` is unavailable, skip the PR-based detection steps and rely on the
remaining evidence.

## Step 2 — propose

Map the evidence to a proposed merge policy, and state the evidence in one
or two lines:

- GitHub remote with merged PRs (or branch protection) →
  `github-pr` + `merged-by: user`.
- No forge remote, merge commits straight to the default branch →
  `local-merge` + `merged-by: orchestrator`.
- Mixed or thin evidence → present both options with no default.

## Step 3 — confirm

Walk the user through `merge.strategy`, `merge.target`, and
`merge.merged-by` — and `merge.merge-style` plus `merge.cleanup` for
local-merge — presenting the proposal as the default. Offer a
`merge.verify` command: suggest the repo's own test entrypoint if one is
evident (package.json scripts, Makefile, test suites); leave the key out
otherwise.

## Step 4 — write

Resolve the profile path:

```bash
sanitized_cwd="${PWD//\//-}"
profile_dir="$HOME/.claude/projects/$sanitized_cwd"
profile="$profile_dir/clam-profile.jsonc"
```

Create `$profile_dir` if it does not exist (`mkdir -p`).

Write `clam-profile.jsonc` at that path from the template below with the
confirmed values, plus JSONC comments recording the evidence and any
repo-specific landing nuance the user mentioned.

If a profile already exists at that path: change ONLY the keys being
confirmed, leave every other key, the `deploy` section, and existing
comments intact — other seams share this file — and show the diff before
writing.

The profile is user-local — it is never committed to the repo.

## Step 5 — stamp

After the profile is written and confirmed, record this init in the shared
stamp file so the update flow can tell this repo's landing setup is current
with the installed version:
`${CLAUDE_CONFIG_DIR:-~/.claude}/clam-setup-stamps.json` — format defined
in `docs/protocols/setup-stamp.md`.

- Read the plugin's version from the `plugin.json` at this installation's
  `installPath` (from its `installed_plugins.json` entry) — never from the
  entry's own `version` field, which can go stale. Scope is always
  `"project"`; target is the absolute path of the `clam-profile.jsonc`
  just written — one stamp per project directory, so initializing several
  worktrees yields several records.
- If the stamp file does not exist yet, create it first as
  `{"version": 1, "stamps": []}`.
- If the existing stamp file is corrupt (not valid JSON), move it aside to
  `clam-setup-stamps.json.corrupt-<date>`, report the move to the user, and
  recreate it fresh.
- Set `at` to the current UTC time by running `date -u +%Y-%m-%dT%H:%M:%SZ`
  — never invented, guessed, or copied from another record.
- Replace this plugin's record, keyed by `plugin` and `target`; touch no
  other records. Write via jq to a temp file, then `mv` it into place:

  ```json
  {
    "plugin": "landing",
    "version": "<from plugin.json>",
    "scope": "project",
    "target": "<absolute path to the profile just written>",
    "at": "<output of date -u +%Y-%m-%dT%H:%M:%SZ>"
  }
  ```

- If the stamp write fails, report the failure but never fail the init —
  the profile write above already succeeded.
- This skill has no `remove` subcommand: deleting a profile is manual,
  so a stale landing stamp left behind after a profile is removed by hand
  is acceptable and harmless.

## Template

````jsonc
{
  "profile-version": 2,

  // Merge policy
  "merge": {
    "strategy": "<github-pr | local-merge>",
    "target": "<branch>",
    "merged-by": "<user | orchestrator>",
    "verify": "<single shell command, or omit this key>",
    "merge-style": "<no-ff | ff-only | squash — local-merge only, omit otherwise>",
    "cleanup": "<remove-worktree | keep — local-merge only, omit otherwise>"
  },

  // Deploy policy
  "deploy": {
    "trigger": "<merge-to-target | tag | manual | none>"
  }

  // <How work lands here, in prose: who does what, and any repo-specific
  // conventions the orchestrator must honor when landing.>
}
````
