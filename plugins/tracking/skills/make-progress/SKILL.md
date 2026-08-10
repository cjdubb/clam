---
name: make-progress
description: "USER-INVOKED ONLY — never auto-triggered, never invoked from crons or other skills. The user types /make-progress when the session stopped but should have kept going. Assess the session's work state, take the next action within the approved plan's scope, and record the stall for later analysis of automatic-trigger design."
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash(gh:*, git:*, bash:*, ls:*, cat:*, date:*), CronCreate, CronList, Agent, Skill
---

# Make Progress

The user invoked this because the session stalled: a unit of work finished (a
PR merged, a subagent returned, a review posted) and the session stopped
instead of finding the next in-plan action. Every invocation is a labeled
example — (state at the stall) → (correct next move) — feeding the eventual
automatic-trigger design. So this skill does two jobs: get the work moving
again, and record the decision.

Scope is strictly the approved plan. This skill never invents new work.

## Workflow

### 1. Verify capture

A UserPromptSubmit hook (`capture.sh` in this plugin) should already have
snapshotted the session state, including the transcript tail — what the agent
said right before stalling — which only the hook can capture.

Find the capture dir for this invocation — the OLDEST matching dir created
within the last ~2 minutes for this worktree:

```bash
find "$HOME/.claude/make-progress-captures" -maxdepth 1 -mmin -2 \
  \( -name "*-$(basename "$PWD")" -o -name "*-$(basename "$PWD")-[0-9]*" \) 2>/dev/null | sort | head -1
```

Oldest, not newest: a duplicate hook fire or a mid-turn re-fire must never
receive the DECISION — the oldest dir in the window is the pristine stall
snapshot (names are timestamp-prefixed, so ascending sort is chronological).
The two `-name` patterns anchor the worktree name (exact, plus `-N`
collision suffixes) so a sibling worktree with a longer name never
cross-matches.

If the selected dir already contains a `DECISION.md`, it belongs to a
previous invocation (e.g. a genuine re-invocation the hook deduped inside
its 60s window): treat it as no match and run the fallback capture below,
so this invocation gets its own capture dir.

If nothing matches (e.g. slash-command routing bypassed UserPromptSubmit),
run the capture script in fallback mode:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/capture.sh" --fallback
```

Fallback captures everything except the transcript tail (unavailable outside
the hook) and `prompt.txt` — write `prompt.txt` into the capture dir
yourself, containing the verbatim invocation text (the hook could not run,
so it never saw the prompt). Either way, note the capture dir path — step 4
writes to it and step 6 appends to it.

### 2. Assess

Gather the current work state, skipping sources that don't exist:

1. `.local/TODO.md` — `State:`, current task, blocked/decision fields
2. `.local/PLAN.md` and any plan files in `.local/plans/` — approved scope
3. `.local/FOLLOWUPS.md` — open follow-up entries (`Status: open`) may themselves be the dispatchable next action (file the issue, or otherwise disposition the entry)
4. `.local/WORKGRAPH.md` — open nodes and the `Focus:` pointer are assessment inputs; the Focus node's `Goal:` is a candidate next action
5. Any other `.local/` state files present (list the directory and read
   what exists) — block maps, tracking state, or other plugin-written
   artifacts, read without assuming which plugin wrote them
6. PR state for the current branch:
   ```bash
   gh pr view --json state,isDraft,reviewDecision,mergeStateStatus,isInMergeQueue
   ```
7. Active watch crons: `CronList`, plus the durable file
   `.claude/scheduled_tasks.json` if present

When a source is
absent, report "no artifacts found at <path>" — never infer from that
absence what did or didn't happen. DECISION.md labels should record
artifact state (what was and wasn't found on disk), not history claims.

### 3. Decide

Apply the first matching row. This is an ATTENDED decision table — the user
is present, so approval gates behave exactly as in normal attended flow;
nothing here grants autonomy.

| Observed state | Decision |
|----------------|----------|
| Lego blocks dispatchable: `.local/blocks.md` exists and contains blocks whose Status indicates they are ready for the next pipeline phase (e.g. Scaffolded blocks ready for test wave, Tests Verified blocks ready for implementation, Accepted blocks enabling dependent units), with all dependency blocks at the required status | Invoke `/lego:dispatch` to advance the dispatchable units. State which units and why they are unblocked. |
| PR merged but post-merge cleanup not run (branch still exists locally, worktree still present, TODO.md still references the merged PR) | Run post-merge cleanup: remove the worktree if applicable, update `.local/TODO.md`, then re-assess from step 2. |
| Feedback (bot or human) posted on an open PR and unaddressed (comments exist after the last force-push or commit) | Route to the feedback-addressing flow. If `/address-pr-feedback` is available, invoke it; otherwise tell the user what feedback is pending and where. |
| Feedback addressed and pushed, but re-review not requested from the existing reviewer | Re-request review from that reviewer — distinct from assigning NEW reviewers, which stays user-gated. |
| Open PR with no active watch cron that should have one (a PR in a reviewable state with no cron monitoring it) | Reschedule the missing watch. If the create-pr monitoring templates are not available, tell the user. |
| Parked state contradicted by current PR reality (e.g. `mergeable: CONFLICTING` while TODO says Awaiting Human Review, or PR closed while TODO says Awaiting Merge Queue) | Treat as an in-plan blocker: resolve the concrete issue (merge base branch for conflicts, update state for closed PRs), re-verify green, re-park correctly. |
| `State: Blocked` or `Waiting For Decision` with the reason still unresolved | The stop was CORRECT. Re-surface the blocker/decision to the user in plain terms; record "stop was correct: blocked on X" as the decision (a valuable negative example). |
| Nothing dispatchable | State explicitly why nothing can proceed, set the correct parked state in `.local/TODO.md` if it exists, and record that as the decision. |

This skill NEVER:

- invents work outside the approved plan
- merges PRs
- assigns reviewers (requesting re-review from an EXISTING reviewer is allowed)
- promotes draft PRs without user direction
- bypasses any existing approval gate

### 4. Record

Record the decision in the capture dir from step 1 BEFORE acting — an act
phase can run long, compact the context, or fail halfway, and a record
written afterwards tends to get lost. Write both files even when the
decision is "no action" or "stop was correct", so later invocations can see
what was already ruled out.

- `DECISION.md` — YAML frontmatter, then three parts: the state found (one
  summary line per source read in step 2), the matched decision-table row
  with the intended action, and a one-paragraph rationale. Example:

  ```markdown
  ---
  invoked_with: <verbatim /make-progress argument, or "none">
  row_matched: <decision-table row name>
  stop_was_correct: yes | no | partial
  action_class: dispatch | cleanup | feedback | reschedule | resurface | report-only | none
  ---

  ## State found
  One summary line per source read in step 2.

  ## Decision
  The matched row and the intended action.

  ## Rationale
  One paragraph.
  ```

- `pr-state.json` — ALWAYS written: the raw `gh pr view` JSON from step 2
  when the branch has a PR; the literal `{"noPr": true}` when it has none.
  Never write raw `gh` error text — it doesn't aggregate.

### 5. Act

Execute the intended action recorded in step 4. Normal attended-workflow
rules apply throughout (plan approval, notify on Blocked, etc.).

### 6. Append the outcome

Append a `## Outcome` section to `DECISION.md`: what was actually executed,
any deviation from the intended action recorded in step 4, and the
resulting parked state. Mandatory on every invocation, including "no
action" and "stop was correct" decisions — without the recorded outcome,
the next invocation cannot tell whether the intended action happened.
