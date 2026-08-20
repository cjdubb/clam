---
name: pr-status
description: Show a live status table of the GitHub PRs for the current worktree — the branch's own PR, or every PR a coordination worktree is shepherding — with reviews, CI, merge-queue state, and merge-readiness sorting. Use when the user asks for PR status, "where are my PRs", or a holistic view of review and CI state.
---

# PR Status

Show a live status table for all PRs related to the current work.

## Step 1: Detect context

```
if .local/.orchestrator is non-empty  -> Coordination worktree (active effort; PRs live on delegated branches)
else                                  -> Standalone (single branch; an empty or absent .orchestrator is topology only)
```

## Step 2: Collect the PR set

**Coordination:** gather GitHub PR URLs from the worktree's own `.local`
planning documents, preferring the most structured source: `**PR:**` fields
in `.local/PLAN.md` and `.local/plans/*.md`; when none, any PR URL in
`.local/TODO.md`, then `.local/PLAN.md`, then `.local/WORKGRAPH.md`.

**Standalone:** resolve the current branch's PR:

```bash
pr_number=$(gh pr list --head $(git branch --show-current) --json number --jq '.[0].number')
```

If nothing turns up in either mode, report:

```
No PR found for branch `{branch-name}`.
```

## Step 3: Fetch live status

Run the bundled helper once with every PR URL or number collected:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/pr-status.sh" [--repo OWNER/REPO] {PR_1} {PR_2} ...
```

The script outputs one JSON line per PR with pre-computed fields: `number`,
`title`, `url`, `size`, `state`, `queuePosition`, `queueState`, `reviews`,
`requested`, `ci`, `mergeable`, `mergeStateStatus`, `comments`, `tier`,
`tier_label`. Use these values directly in the table. Do NOT attempt to
parse GitHub API responses or write jq yourself. The field vocabularies and
tier table are specified in the PR-status cache protocol
(`docs/protocols/pr-status-cache.md`); the semantics that matter when
rendering:

- `state` values: `Draft`, `Open`, `In Queue` (enqueued; queue CI is
  running against the queue head), `Queue Failed` (queue CI failed; the PR
  was kicked out of the queue and the author must fix), `Merged`, `CLOSED`.
  While a PR is `In Queue`, GitHub stops recomputing `mergeable` /
  `mergeStateStatus` and they report `UNKNOWN`; do not interpret that as a
  fresh conflict.
- `mergeable == "CONFLICTING"` means the PR cannot merge until the author
  rebases or merges base; surface it as an action item even when reviews
  and CI are otherwise clean. The reverse does not hold: `MERGEABLE` only
  says "no conflicts" — it promises nothing about approval, CI, or branch
  protection, so never report a PR as ready on the strength of this field.
  Whether a PR can actually be merged is the readiness tier (tier 4 "Ready
  to enqueue" / tier 5 "Merged").
- `tier` is the merge-readiness sort key: 5 Merged, 4.5 In queue, 4 Ready
  to enqueue (open + approved + CI pass + no conflicts — clicking "Merge"
  will enqueue, not merge), 3 Approved with caveats, 2 Awaiting review,
  1 Action required (including `Queue Failed`, which gets the distinct
  `tier_label` `Queue failed` so Notes can say the queue ejected the PR).

## Output rules

<rule enforcement="must">The table has exactly these 7 columns in this order: Title, PR, State, Reviews, Requested, CI, Notes. Do NOT omit any column. Do NOT add extra columns.</rule>
<rule enforcement="must">PR column format: `[#NUMBER SIZE](FULL_URL)` where `SIZE` is the `size` field from the helper (e.g. `+27,493 -27,616`). The whole thing is a single clickable markdown link. Never show raw URLs. Example: `[#1234 +27,493 -27,616](https://github.com/owner/repo/pull/1234)`.</rule>
<rule enforcement="should">Keep output concise: just the table and a one-line summary if anything needs attention (e.g., "1 PR has failing CI", "2 PRs need reviewers", "1 PR has merge conflicts").</rule>
<rule enforcement="must">Sort rows by `tier` descending (5 → 1). Within the same tier, when the worktree's planning documents record a merge order or dependency between the PRs, a PR that another depends on appears above it; otherwise keep the order the PRs were collected in.</rule>
<rule enforcement="must">Notes column: combine useful context into a short string, items in priority order (separate multiples with `; `); show "-" only if none apply:
1. Dependency info recorded in the planning docs: `Depends on #N` and/or `Blocks #N`.
2. `Queue failed` if `state == "Queue Failed"` — the queue ejected the PR; the author must fix and re-enqueue.
3. `Queue position N` if `state == "In Queue"` and `queuePosition` is set.
4. `Merge conflicts` if `mergeable == "CONFLICTING"` — action-required regardless of review/CI state.
5. `N unreplied` if `comments` > 0.
6. Other action items (e.g., "Assign reviewer", "Follow up with reviewer").
</rule>
<rule enforcement="must">Prefix the Title cell with a color indicator showing whether the PR author needs to act. Evaluate conditions in this order; first category matched wins:

**🚫 Queue failed (action required, queue ejected the PR):**
- `state == "Queue Failed"`

**🔴 Red (action required by me):**
- CI Fail (any review state)
- Reviews: Changes Requested (any CI)
- Reviews: Commented (ambiguous verdict, need to follow up with reviewer)
- Reviews: Not Requested (need to assign reviewers)
- Unreplied review comments > 0
- `mergeable == "CONFLICTING"` (must rebase or merge base before this can land)
- Approved + CI Pass (ready to enqueue; click Merge to add to queue)

**🚂 Train (in merge queue, passive wait):**
- `state == "In Queue"` (nothing to do until it merges or ejects)

**🟡 Yellow (in progress, monitor):**
- Approved + CI Running (will be ready to enqueue once green)
- Approved (stale) (new commits since approval, may need re-review)
- State: Draft

**🟢 Green (no action required):**
- Pending review + CI Pass or Running (reviewer's turn)
- All other combinations

**✅ Green tick (merged):**
- Merged

Example: `🔴 Relay error classification`, `🚂 Foundation (in queue, position 2)`, `✅ Remove dead orphan aliases`, or `🚫 Auth refactor (queue ejected)`
</rule>
