---
name: dispatch-issues
description: "Clear this repo's GitHub issue backlog by dispatching issues to their own orchestrator worktrees. Selects candidates, verifies each defect is still live before spending a session on it, detects collisions between issues that touch the same code, then writes a handover and scaffolds a recipient worktree per issue. Use when asked to clear the bug backlog, work through open issues, pick up the next bug, or hand a GitHub issue over to a fresh orchestrator."
---

# Dispatching issues to orchestrator worktrees

This skill is **repo-local on purpose**. It names `gh`, the `bug` label, and
sibling plugins by name — couplings a plugin under `plugins/` may not take
(`CLAUDE.md`, the layering rule) and that `architecture-lint.sh` exists to
catch. Living at the repo root puts it outside that lint's scan scope
(`scripts/architecture-lint.sh:86` — "EXACTLY tracked files under `plugins/*/`")
legitimately rather than by evasion. **Do not promote this into a plugin.**

You are the orchestrator running this. Do not delegate any step to a subagent —
same rule the handover skill carries, and for the same reason: the judgement in
steps 2 and 3 is the whole value.

## Step 0 — Settle scope with the engineer

Ask, and wait for answers, before touching anything:

1. **How many** issues in this batch? Recommend 5 — enough to keep the engineer
   busy, few enough that the worktrees get used before they go stale.
2. **Which label / selection rule?** Default `bug`, your pick of highest-value
   live issues. Alternatives: oldest-first, or clustered by plugin.
3. **Already-fixed issues — close or report?** Default report only; closing is
   the engineer's call.

A bare "go" accepts all three.

## Step 1 — Enumerate and exclude

```bash
gh issue list --label bug --state open --limit 100 --json number,title,createdAt
```

Exclude any issue that is already in flight. Check all three — a branch can
exist with no worktree, and a worktree can exist with no PR:

```bash
git branch -a --list '*orchestrate/github-issue-<n>-*'
gh pr list --state open --json number,headRefName,body
ls "$(git rev-parse --path-format=absolute --git-common-dir)/.." 
```

## Step 2 — Verify each candidate is still live (mandatory)

**Never dispatch an issue without checking the defect still exists.** Issues in
this repo go stale silently — a batch triaged on 2026-08-05 found three of
roughly a dozen checked already fixed (#77, #99, #121). A handover for a fixed
bug costs the engineer a whole session to discover nothing is wrong.

For each candidate, open the issue, find the concrete claim, and grep for it:

- Does the cited file still contain the offending line?
- Does a later commit already touch that area? (`git log --oneline -- <path>`)
- Is it a duplicate of another open issue?
- Is it actually a bug, or a feature request wearing the `bug` label?

**Line numbers in issues drift.** Every issue checked in the 2026-08-05 batch
that cited a line number had the wrong one (#268 cited `worktree.sh:1151`, the
code was at 1280; #147 cited `SKILL.md:94`, it was at 91). Resolve the current
line and put it in the handover — a recipient sent to the wrong line wastes time
deciding whether the bug was already fixed.

Record what you find in `.local/FOLLOWUPS.md` (create from the tracking plugin's
template on first use): stale issues, mislabels, and duplicates each get an
entry so the finding is not lost when this session ends.

## Step 3 — Detect collisions before creating anything

Two issues that edit the same file — or worse, the same function — will conflict
when their orchestrators run in parallel. Check the selected set against itself
before scaffolding:

```bash
# for each pair of selected issues, compare the paths their bodies cite
```

The 2026-08-05 batch shipped #268 and #219 as separate worktrees when both
rewrite the same `deliver` function in `plugins/lego/scripts/worktree.sh`.
That was flagged to the engineer, but it should have been caught before the
worktrees existed.

When you find a collision, put it to the engineer before scaffolding: sequence
the two (smaller change lands first, the other rebases) or fold them into one
effort. If you scaffold both anyway, say so in **both** handovers' cross-unit
section — do not assume either session will notice the overlap on its own.

## Step 4 — Write the handover, one per issue

Use `/orchestrator-handover:create`, which owns the handover template and the
worktree mechanics. This skill supplies what that skill cannot know:

- **Branch name**: `orchestrate/github-issue-{number}-{shortDescription}`.
  This overrides the handover skill's default of `orchestrate/{ISSUE-KEY}-...`.
- **Handover filename**: `.local/handover-{number}.md`.

Beyond the template's own sections, every handover for this repo must carry:

- **Verified current line numbers**, with a note where the issue's cited numbers
  were wrong — so the recipient does not re-derive the drift.
- **A version-bump line in "What is open"**, naming the exact `plugin.json`.
  `version-bump-lint` reads **committed** state, so a `scripts/ci.sh` run before
  the bump is committed is a vacuous pass. This catches people out repeatedly.
- **What is already settled**, stated as not-open-for-redesign where the issue
  says so. Several issues here record an agreed fix (#147's is purely
  subtractive); a recipient that re-litigates it wastes the session.
- **Cross-unit collision notes** from step 3, if any.
- **A pending-decisions section that does not invent decisions.** Where the
  issue genuinely leaves a question open (#277's prompt-vs-hard-stop), say so
  and give no recommendation. Where it does not, say **None**.

## Step 5 — Verify the recipient worktree

`newtree` is **not on PATH** in Bash-tool shells — it is a shell function, and
non-interactive shells skip the `.bashrc` block that sources it. Read the path
out of the `# BEGIN GIT-HELPERS` block in `~/.bashrc` and source it in the same
invocation as the call:

```bash
source "$(grep -oP '(?<=^source ").*(?=")' ~/.bashrc | grep worktree-helpers)" && newtree "$branch"
```

After the handover skill finishes, confirm each recipient has all four:

```bash
ls -A <wt_dir>/.local/    # handover-<n>.md, MODE, .orchestrator, TODO.md
```

Write the recipient's `TODO.md` with `State: Not Started`, a `Current Task`
pointing at the handover, and — in Blockers/Notes — any collision warning and
the corrected line numbers.

## Step 6 — Report, with a pickup instruction that works

Give the engineer one line per worktree. **Do not tell them to run `clam` and
pick `Build`.** The handover skill still says that; it is wrong here and is
filed as [#288](https://github.com/cjdubb/clam/issues/288) — `clam` is a
clam-code alias this port deliberately dropped (`MIGRATION.md:568`), and the
`/start` picker the "pick Build" half needs was never ported (session-modes is
`planned`; no `plugins/*/skills/start` exists).

The instruction that works today:

```
cd <worktree> && claude
```

then let the session read `.local/TODO.md`, which points at the handover.

Close the report with what you deliberately did **not** dispatch — stale issues,
mislabels, duplicates — so the backlog's real size stays visible. A batch that
reports only its successes makes the backlog look healthier than it is.
