# PR-status cache protocol

The PR-status cache is a pair of files at a worktree's root recording the
live review, CI, and merge-queue state of the pull requests the worktree's
work rides on, refreshed in the background so that consumers can render a
current picture without ever blocking on the network. This document is the
normative spec for those files and for the refresh discipline any writer
must follow. It is owned by the repository's architecture, is
self-contained, and names no plugin.

## Location

Both files live in the worktree's `.local/` directory:

- `.local/.pr-status.json` — the machine-read cache.
- `.local/PR-STATUS.md` — a human-readable rendering of the same fetch,
  written in the same refresh.

A writer must resolve the worktree root (`git rev-parse --show-toplevel`)
before writing, so a caller invoked from a subdirectory and one invoked
from the root agree on where `.local` lives. A worktree with no `.local`
directory is not participating: a writer exits silently rather than
creating it.

## JSON shape

The top-level object has four fields:

- `branch` — the worktree's current branch name, possibly empty.
- `fetched_at` — ISO 8601 UTC timestamp of the fetch, from
  `date -u +%Y-%m-%dT%H:%M:%SZ`.
- `prs` — an array of 0, 1, or N per-PR objects, in a stable order
  across refreshes.
- `pr` — deprecated mirror: the single `prs` entry when the array has
  exactly one element, else `null`. Readers use `prs`; writers keep the
  mirror until no reader in the wild reads it.

Each `prs[]` entry carries these fields:

| Field | Meaning |
| --- | --- |
| `number` | PR number (integer). |
| `title` | PR title. |
| `url` | Full PR URL. |
| `size` | Diff-stat string, `+additions -deletions` with thousands separators (e.g. `+27,493 -27,616`). |
| `state` | `Draft`, `Open`, `In Queue`, `Queue Failed`, `Merged`, or `CLOSED` — see below. |
| `queuePosition` | Merge-queue position (integer) or `null` when not enqueued. |
| `queueState` | Raw merge-queue entry state (`QUEUED`, `AWAITING_CHECKS`, `MERGEABLE`, `LOCKED`, `UNMERGEABLE`) or `null`. |
| `reviews` | `Approved`, `Approved (stale)`, `Changes Requested`, `Commented`, `Pending`, or `Not Requested`. |
| `requested` | Comma-joined pending reviewer logins/team names, or `-` when none. |
| `ci` | `Pass`, `Fail`, `Running`, or `N/A` (no checks). |
| `mergeable` | Forge conflict verdict: `MERGEABLE`, `CONFLICTING`, or `UNKNOWN`. |
| `mergeStateStatus` | Granular merge state: `CLEAN`, `DIRTY`, `BEHIND`, `BLOCKED`, `UNSTABLE`, `HAS_HOOKS`, `DRAFT`, or `UNKNOWN`. |
| `comments` | Count of unresolved review threads whose latest comment is not by the PR author (integer). |
| `tier` | Merge-readiness sort key — see the tier table. |
| `tier_label` | Human label for the tier. |

A reader tolerates unknown extra fields and missing optional ones —
`comments` and `url` in particular are read with defaults — and treats a
file that fails to parse as absent.

### State vocabulary

`Draft`, `Open`, and `Merged` follow the forge's own PR lifecycle.
`In Queue` means the PR sits in a merge queue with queue CI running
against the queue head — a passive wait. `Queue Failed` means queue CI
failed and the queue ejected the PR; the author must fix and re-enqueue.
While a PR is enqueued the forge stops recomputing `mergeable` /
`mergeStateStatus` and both report `UNKNOWN`; that is not a conflict.
`CLOSED` is a PR closed without merging; consumers typically skip it.

`mergeable == "MERGEABLE"` is not a green light — the field only checks
for conflicts and says nothing about approval, CI, or branch protection.
Actual readiness is the tier.

### Tiers

| Tier | Label | Condition |
| --- | --- | --- |
| 5 | Merged | `state == "Merged"` |
| 4.5 | In queue | `state == "In Queue"` |
| 4 | Ready to enqueue | Open + Approved + CI Pass + `mergeable != "CONFLICTING"` |
| 3 | Approved (caveats) | Open + Approved or Approved (stale), but not tier 4 |
| 2 | Awaiting review | Open + Pending + CI not Fail |
| 1 | Action required | Everything else, including `Queue Failed` (distinct `tier_label`: `Queue failed`) |

## Markdown companion

`PR-STATUS.md` is a human rendering of the same data: a title, the branch,
the `fetched_at` timestamp, and one entry per PR (number, title, state,
reviews, CI, unresolved-comment count, URL). Its exact layout is not
normative; the JSON is the machine surface.

## Which PRs a refresh covers

- A worktree whose branch has its own PR (open or merged, most recent
  first) caches that single PR.
- A coordination worktree — one marked by a non-empty
  `.local/.orchestrator` file, or any worktree whose branch has no PR of
  its own — shepherds PRs that live on other branches. Its refresh
  scrapes GitHub PR URLs from the worktree's own `.local` planning
  documents, preferring the most structured source available: a
  `**PR:**` field in a plan document, then any PR URL in `.local/TODO.md`,
  `.local/PLAN.md`, or `.local/WORKGRAPH.md`. A scraped document that
  happens to reference an unrelated PR can produce a false positive;
  that is an accepted tradeoff for a glanceable hint.
- A detached HEAD, or a checkout of a default branch (`master`, `main`),
  is not refreshed.
- A branch with no PR and no scraped URLs writes an empty `prs: []` —
  genuine absence is recorded, not skipped.

## Refresh discipline

Any process that writes the cache follows these rules:

- **CLI contract.** A refresh engine is invocable as
  `<engine> <worktree-dir> [ttl-seconds]`, TTL defaulting to 60. Callers
  with different freshness needs pass different TTLs against the same
  cache (a turn-end hook a short one, an idle poller a longer one).
- **TTL guard.** Skip entirely when `.pr-status.json` is younger than the
  given TTL.
- **Lock.** One refresh per worktree at a time, via `mkdir` of
  `.local/.pr-status-refresh.lock`. The lock directory records its
  owner's PID in a `pid` file; a lock older than 120 seconds is treated
  as a crashed refresher and broken. A process releases only a lock it
  still owns. Watchers may treat a lock younger than 120 seconds as "a
  refresh is already in flight" and decline to start another.
- **Preserve on failure.** A network or CLI failure exits without
  writing, so a background refresh never blanks a previously good cache.
  Only a successful fetch — including a successful "no PRs" answer —
  writes. Per-PR fetch failures inside a multi-PR refresh are dropped
  from the array rather than failing the whole write, but an all-fail
  refresh preserves the old cache.
- **Atomic writes.** Each file is built in a temporary file and moved
  (`mv`) over the destination, so a reader never observes a half-written
  cache.
- **Silence.** A refresh engine never errors at its caller: any failure
  is a silent exit. It is a cache, not a source of truth.

## Absence and staleness

No file means no refresh has succeeded yet; a consumer renders nothing
rather than an error. `fetched_at` and the file's mtime tell a consumer
how stale the picture is; a consumer wanting fresher data invokes a
refresh engine in the background and renders what is on disk now, never
blocking on the fetch.
