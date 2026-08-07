---
name: address-pr-feedback
description: Address review feedback on a GitHub pull request and request re-review. Use when the user mentions PR comments, review feedback to address, reviewer comments needing responses, or asks to handle/respond to feedback on a PR.
---

# Address PR Feedback

Work through every comment on a pull request with the user: fetch and
triage the feedback, propose a resolution and draft response per comment,
stop for approval, then execute only what was approved and put the PR back
in the reviewer's queue.

This skill is for the PR's author. If the user wants to *review* someone
else's PR rather than respond to feedback on their own, this is the wrong
skill — say so and stop. If the user mentioned comments but their intent
is unclear, ask whether they want the feedback addressed or just
summarized.

## Workflow

### 0. Get onto the PR branch

Work happens in a checkout of the PR's head branch:

```bash
gh pr view <PR> --json headRefName --jq '.headRefName'
git branch --show-current
```

If the current checkout is already on that branch, proceed. Otherwise the
goal is a working copy of that branch that doesn't disturb other in-flight
work: reach for a worktree-creation skill if the catalog offers one;
fall back to `git worktree add` or, in a clean single-checkout repo, a
plain `git checkout` of the branch.

### 1. Gather context for "why" questions

Reviewers ask why an approach was taken. Before triaging, note what
context exists: plan documents (`.local/PLAN.md`, `.local/plans/*.md`),
progress and decision records (`.local/TODO.md`, decision files) in this
worktree — and, when the branch is part of a larger coordinated effort,
the same artifacts in the coordinating worktree. Read state as you find it
without assuming which tool wrote it. Absence of any of these is normal;
compose answers from the diff and commit log alone.

### 2. Fetch, triage, and present every comment

```bash
gh pr view <PR> --json author,state,additions,deletions
"${CLAUDE_PLUGIN_ROOT}/scripts/pr-comments.sh" --repo <OWNER>/<REPO> <PR>
```

The script emits one JSON object per comment (review comments and PR-level
comments, resolved threads excluded by default; pass `--resolved` to
include them) with pre-computed fields: `id`, `user`, `type`, `severity`,
`path`, `line`, `url`, `body`, `created_at`, `outdated`, `resolved`,
`thread_id`, `in_reply_to`, and a final summary object. Use the `severity`
field for triage — do not re-parse comment bodies for prefixes:

- `blocking` — must fix before merge
- `non-blocking` — should address
- `suggestion` — optional improvement (includes `nitpick:` prefixes)
- `question` — needs a response, not necessarily a code change
- `unknown` — triage manually from the content

Then present **every comment** to the user, numbered, in this shape:

```
## PR Feedback Summary: PR #N

Found X comments: N blocking, N non-blocking, N suggestions, N questions.

---

### Comment 1 (blocking): @reviewer
**File:** `path/to/file.ts:42` | <bare comment URL>
**Comment:** "verbatim reviewer comment"

**Proposed resolution:** Fix: what would change
**Draft response:**
> Fixed in [commit]. Description of the fix.
**Reasoning:** why this resolution fits
```

For each comment propose exactly one resolution: fix immediately
(describe the change — do not make it), create a follow-up issue
(`gh issue create`, or the project's tracker if CLAUDE.md names one),
document a limitation, agree it's out of scope, split the PR, or escalate
a fundamental disagreement. Show the comment verbatim, include the bare
GitHub URL, and use `[commit]` as a placeholder since nothing is committed
yet.

**This step is presentation only.** Make no code changes and post no PR
comments here.

### 3. Wait for approval — hard stop

After presenting, output this and stop the turn:

```
Review the proposed responses above. You can:
- Approve all and I'll proceed
- Approve specific comments by number (e.g., "approve 1, 2, skip 3")
- Discuss any you disagree with
- Modify any draft response

I will NOT make any code changes or post any PR comments until you approve.
```

Do not proceed, make changes, or post comments until the user explicitly
approves (all, or specific numbers). Iterate on disagreements and rewording
until agreement. Never combine this gate with step 2 or step 4.

### 4. Execute the approved changes

Only what the user approved; skip anything rejected or deferred.

For approved code fixes: make the change, commit. For approved responses:
reply on each comment's thread, substituting real commit hashes for
`[commit]` placeholders. Every comment gets a response — none dismissed
silently, none marked resolved without being addressed. When proposing
code in a reply, use a GitHub suggestion block:

````markdown
```suggestion
// proposed code here
```
````

Response patterns: "Fixed in <hash>", "Created <issue> to track this",
"I considered this, but <reason> — happy to discuss", "Could you clarify
what you mean by X?", "Out of scope for this PR because <reason>; created
<issue> to address it separately."

If any feedback was resolved outside the PR (chat, a call), add a PR
comment summarizing the decision and who agreed, so the record lives on
the PR.

### 5. Keep the artifacts truthful

When a change alters the implementation — different values, approach,
scope, or functionality — the PR description must not go stale: recompose
and apply it (the sibling `/forge-github:sync-pr` skill is the owner of
that operation; invoke it rather than hand-editing the body). Update plan
documents (`.local/PLAN.md`) and the tracker issue with the decision
rationale for the same reason.

### 6. Re-run verification

Run the project's pre-PR verification (whatever CLAUDE.md or the repo's
own checks define) before asking anyone to look again.

### 7. Request re-review

Two distinct actions — do not conflate them:

- **Re-requesting the EXISTING reviewer** whose feedback was just
  addressed is part of the re-review flow and needs no further approval.
  A thread reply or `gh pr comment` does NOT put the PR back in their
  GitHub review queue; only the API call does:

  ```bash
  gh pr comment <PR> --body "Addressed all feedback, ready for re-review"
  gh api repos/{owner}/{repo}/pulls/<PR>/requested_reviewers -f 'reviewers[]=<login>'
  ```

  Re-request every reviewer whose feedback was addressed (the call is
  idempotent); leave other reviewers' pending requests untouched.

- **Assigning a NEW reviewer** (`gh pr edit <PR> --add-reviewer <user>`)
  is always user-gated: never run it without the user explicitly naming
  the reviewer in response to a direct question.

**CI-green precondition:** never point a reviewer at a red or pending PR.
If rework commits were just pushed, do not re-request yet — record the
pending action in `.local/TODO.md` so a later session (or CI watch, if one
is armed) can execute it mechanically once checks pass:

```
On CI green: re-request review from <login> (gh api repos/{owner}/{repo}/pulls/<PR>/requested_reviewers -f 'reviewers[]=<login>') and post the ready-for-re-review courtesy comment
```

If a CI-monitoring pattern is in use for this PR (see create-pr's
post-creation monitoring guidance), re-arm it after the fix push. The
recorded line is a pre-decided, mechanical action: whoever observes green
executes it verbatim and clears the line — the decision stays in this
attended turn.

## Anti-patterns

- Dismissing comments without a response
- Marking threads resolved without addressing them
- Making changes without explaining what changed
- Offline agreement with no record on the PR
- Changing the implementation without updating the PR description
- Making code changes before the user reviews proposed responses
- Posting PR comments without user approval
- Skipping the approval gate by combining triage with execution
- Assigning a new reviewer without an explicit user decision
