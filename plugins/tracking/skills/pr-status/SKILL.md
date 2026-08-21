---
name: pr-status
description: Show a status table of every PR under the current effort's remit — reviews, CI, merge-queue state, and merge-readiness sorting — rendered from the PR-status cache on disk. Use when the user asks where their PRs stand, for PR status across an effort, or for a holistic view of review and CI state. Reports only; it never merges, re-enqueues, replies, or edits a PR.
---

# PR Status

Show where every PR under the current effort's remit stands, in one table,
so the next action is obvious at a glance.

This is a **reporting** skill. It observes and renders; it never acts. When
a row says action is required, the action belongs to whichever installed
capability acts on pull requests, not here — naming what is needed is this
skill's whole job.

## Step 1: Read the cache

Every field this skill renders comes from the PR-status cache specified in
`docs/protocols/pr-status-cache.md`. Resolve the worktree root and read the
JSON there:

```bash
cat "$(git rev-parse --show-toplevel)/.local/.pr-status.json"
```

Render what is on disk. Do **not** call `gh`, and do not fetch: the cache
protocol makes refreshing a background concern with its own TTL, lock, and
atomic-write discipline, and a report that blocks on the network is not a
glance. Which PRs the cache covers — a single branch's own PR, or the set
scraped from a coordination worktree's planning documents — is the refresh
engine's decision, already made by the time the file exists.

Read `prs`, not the deprecated `pr` mirror. Tolerate unknown extra fields
and missing optional ones (`comments` and `url` in particular), and treat a
file that fails to parse exactly as you would treat one that is absent.

**Absent or unparseable cache.** Say so plainly and stop:

```
No PR-status cache in this worktree. Nothing has written
.local/.pr-status.json — no PR state to report.
```

That is genuine absence, not an error, and it is the expected state in a
worktree whose work has no PRs or where no refresh engine is installed.

**Empty `prs: []`.** The refresh succeeded and found nothing. Report "No
PRs under this worktree's remit" rather than an empty table.

**Staleness.** `fetched_at` is an ISO 8601 UTC timestamp. When it is more
than five minutes old, append its age to the table's summary line — "as of
14 minutes ago" — so nobody mistakes a stale picture for a live one. Never
suppress a stale table; render it and label it.

## Step 2: Interpret the fields

The vocabularies below are normative in the cache protocol; the semantics
that matter when rendering are these.

- `state`: `Draft`, `Open`, `In Queue` (enqueued; queue CI is running
  against the queue head — a passive wait), `Queue Failed` (queue CI
  failed, the queue ejected the PR, and the author must fix and
  re-enqueue), `Merged`, `CLOSED`. While a PR is `In Queue` the forge stops
  recomputing `mergeable` and `mergeStateStatus`, and both report
  `UNKNOWN`; that is not a fresh conflict.
- `mergeable == "CONFLICTING"`: the PR cannot land until its author rebases
  or merges base. Surface it as action-required even when reviews and CI
  are otherwise clean. The reverse does not hold — `MERGEABLE` says only
  "no conflicts" and promises nothing about approval, CI, or branch
  protection, so never call a PR ready on the strength of that field.
- `tier` is the merge-readiness sort key, already computed: 5 Merged,
  4.5 In queue, 4 Ready to enqueue, 3 Approved with caveats, 2 Awaiting
  review, 1 Action required (including `Queue Failed`, which carries the
  distinct `tier_label` `Queue failed`).

Use the pre-computed values as they stand. Do not recompute a tier, and do
not derive readiness yourself from the raw fields.

## Output rules

<rule enforcement="must">The table has exactly these 7 columns in this order: Title, PR, State, Reviews, Requested, CI, Notes. Do NOT omit any column. Do NOT add extra columns.</rule>
<rule enforcement="must">PR column format: `[#NUMBER SIZE](FULL_URL)` where `SIZE` is the `size` field (e.g. `+27,493 -27,616`). The whole thing is a single clickable markdown link. Never show raw URLs. Example: `[#1234 +27,493 -27,616](https://github.com/owner/repo/pull/1234)`.</rule>
<rule enforcement="should">Keep output concise: the table, plus a one-line summary when something needs attention (e.g. "1 PR has failing CI", "2 PRs need reviewers", "1 PR has merge conflicts").</rule>
<rule enforcement="must">Sort rows by `tier` descending (5 → 1). Within a tier, when the worktree's planning documents record a merge order or a dependency between PRs, a PR another depends on appears above it; otherwise keep the order the cache lists them in.</rule>
<rule enforcement="must">Notes column: combine context into a short string, items in priority order, multiples separated by `; `; show "-" when none apply:
1. Dependency info recorded in the planning documents: `Depends on #N` and/or `Blocks #N`.
2. `Queue failed` when `state == "Queue Failed"` — the queue ejected the PR; the author must fix and re-enqueue.
3. `Queue position N` when `state == "In Queue"` and `queuePosition` is set.
4. `Merge conflicts` when `mergeable == "CONFLICTING"` — action-required regardless of review and CI state.
5. `N unreplied` when `comments` > 0.
6. Other action items (e.g. "Assign reviewer", "Follow up with reviewer").
</rule>
<rule enforcement="must">Prefix the Title cell with a colour indicator showing whether the PR author needs to act. Evaluate in this order; first match wins:

**🚫 Queue failed (action required, the queue ejected the PR):**
- `state == "Queue Failed"`

**🔴 Red (action required by me):**
- CI Fail (any review state)
- Reviews: Changes Requested (any CI)
- Reviews: Commented (ambiguous verdict; follow up with the reviewer)
- Reviews: Not Requested (reviewers need assigning)
- Unreplied review comments > 0
- `mergeable == "CONFLICTING"` (rebase or merge base before this can land)
- Approved + CI Pass (ready to enqueue; clicking Merge adds it to the queue)

**🚂 Train (in the merge queue, passive wait):**
- `state == "In Queue"` (nothing to do until it merges or ejects)

**🟡 Yellow (in progress, monitor):**
- Approved + CI Running (ready to enqueue once green)
- Approved (stale) (new commits since approval; may need re-review)
- State: Draft

**🟢 Green (no action required):**
- Pending review + CI Pass or Running (the reviewer's turn)
- All other combinations

**✅ Green tick (merged):**
- Merged

Example: `🔴 Relay error classification`, `🚂 Foundation (in queue, position 2)`, `✅ Remove dead orphan aliases`, `🚫 Auth refactor (queue ejected)`
</rule>
<rule enforcement="must">Report only. Never merge, enqueue, re-enqueue, close, reopen, approve, request review, reply to a comment, push, or edit a PR's title or description from this skill — not even when a row is plainly ready and the action looks trivial. Name the action the row calls for and stop.</rule>
