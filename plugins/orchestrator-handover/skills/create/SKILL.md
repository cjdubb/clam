---
name: create
description: "Spin up a fresh orchestrator for a sub-effort. Writes a handover document, creates the recipient orchestration worktree via newtree, and populates its .local/ so the user just runs clam and picks Build. Use when an orchestrator session has identified a discrete sub-effort that warrants its own coordination context, or when the user explicitly asks for a handover. The orchestrator scaffolds the worktree but never starts the new session; the user does."
---

<!--
Contract: B01 handover-plugin — skill
Behavior:   provides /orchestrator-handover:create, a four-step procedural skill
            that an orchestrator invokes to spin off a sub-effort into its own
            orchestration context:
            (1) write a handover document to the current worktree's .local/
                using the companion template (template.md);
            (2) create a recipient orchestrator worktree via newtree and
                populate its .local/ (handover doc copy, MODE file set to
                "Build", empty .orchestrator marker);
            (3) write a placeholder TODO.md in the recipient's .local/ using
                the tracking plugin's template format;
            (4) report the created path and hand off to the user.
Inputs:     invoked by an active orchestrator session. Requires: an issue key
            or descriptive slug for the sub-effort, and enough session context
            to populate the handover template sections (what is done, what is
            open, decisions pending, proposed work breakdown).
Outputs:    (a) .local/handover-{ISSUE-KEY}.md in the current worktree
            (provenance copy); (b) a recipient worktree at
            orchestrate-{ISSUE-KEY}-{short-description} with .local/ populated:
            handover doc, MODE=Build, empty .orchestrator, TODO.md, and any
            local artifacts referenced in the handover's source-of-truth
            section.
Errors:     worktree creation failure (newtree fails or .git absent after
            creation) → abort immediately, surface to user, never leave a
            half-populated directory behind.
Invariants: - never starts a session in the recipient worktree (human-start
              gate: only the user runs clam + Build)
            - never writes content into .orchestrator (empty marker only;
              the recipient fills it at Gate 1)
            - never pre-populates PLAN.md or IMPLEMENTATION-PLAN.md in the
              recipient worktree
            - never delegates any scaffolding step to a subagent
            - issue-tracker-agnostic: works with GitHub Issues, Linear,
              Jira, or no tracker at all
            - always uses newtree (no newcliptree)
            - worktree creation runs in a subshell so the current session's
              cwd never drifts
            - all bash commands for step 2 run in a single shell invocation
              (Bash tool does not persist variables between calls)
Edge cases: - no issue tracker in use → slug-based naming
              (orchestrate/{short-description})
            - tracking plugin not installed → skill inlines the essential
              TODO.md fields rather than referencing the template
            - team-review plugin absent → orchestrator-guard.sh not
              available; Write to sibling worktree may prompt for
              confirmation
            - session-modes plugin absent → /start detection of handover
              docs not available; recipient's first move section documents
              manual pickup
            - recipient worktree directory already exists → newtree warns
              and navigates (not a failure)
            - cross-repo sub-effort → skill notes this is possible but the
              default assumes same repo
-->

# Orchestrator Handover

When an active orchestrator session reaches a point where a discrete
sub-effort deserves its own coordination context, invoke
`/orchestrator-handover:create`. This skill writes a handover document,
creates the recipient orchestrator worktree, and populates that worktree's
`.local/` — then hands off to the user. It never starts the new orchestrator
session itself: a worktree only becomes a live orchestrator once a human
runs `clam` there and picks `Build`.

## When to invoke

- A sub-effort is a discrete deliverable that warrants its own PLAN and
  TODO, not just another section of the current orchestration.
- The user explicitly asks for a handover.
- You are about to hand-roll a `newtree orchestrate/...` call from inside an
  existing orchestrator — use this skill instead; it creates the worktree
  correctly and populates the recipient's `.local/` for you.

Small, tightly-coupled sub-efforts that fit inline in the current
`IMPLEMENTATION-PLAN.md` do not need this skill — just add a section and
spawn chunks as usual.

## What this skill does

### 1. Write the handover document

Write the handover to the current worktree's `.local/handover-{ISSUE-KEY}.md`
(or `.local/handover-{slug}.md` when there is no issue tracker) using the
companion [template.md](template.md). Trim sections that do not apply — the
source-of-truth artifacts, decisions-pending, and cross-unit compatibility
sections carry an explicit "None" marker in the template for exactly this
case. This copy stays in the current worktree as a provenance record. Write
it using whatever session context you already have: what's done, what's
open, decisions pending, and a proposed work breakdown.

### 2. Create, verify, and populate the recipient worktree

Run this as a single shell invocation — the Bash tool does not persist
variables between calls, so every variable this step sets must be set and
used in one block. It resolves the worktree root, always creates the
recipient with `newtree` (never a ticket-specific variant), runs the
creation inside a subshell so this session's own cwd never drifts, aborts
immediately if the create failed rather than populating a half-populated
directory, then copies the handover and writes `MODE`:

```bash
common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"   # absolute .../<trees-dir>/.bare
trees_dir="$(cd "$(dirname "$common_dir")" && pwd)"
branch="orchestrate/{ISSUE-KEY}-{short-description}"                    # or orchestrate/{short-description} with no issue key
wt_dir="$trees_dir/$(printf '%s' "$branch" | tr '/' '-')"

( cd "$trees_dir" && newtree "$branch" )

# Abort before populating if the create failed — never leave a
# half-populated directory behind. A .git file (worktrees use a file, not a
# directory) means the worktree is real.
[ -e "$wt_dir/.git" ] || { echo "FAILED: worktree not created at $wt_dir"; exit 1; }

mkdir -p "$wt_dir/.local"
cp ".local/handover-{ISSUE-KEY}.md" "$wt_dir/.local/"
printf 'Build' > "$wt_dir/.local/MODE"
# Empty .orchestrator marker: records coordinator topology only. The
# recipient session fills its content (the parent issue) at its own Gate 1 —
# never write content here yourself.
touch "$wt_dir/.local/.orchestrator"
echo "RECIPIENT READY: $wt_dir"
```

Notes:

- If `newtree` reports that the target directory already exists, that is
  not a failure — it warns and navigates into the existing directory, and
  this step proceeds normally.
- This assumes the sub-effort lives in the same repo as the current
  orchestration, the default and common case. A cross-repo sub-effort is
  possible — point `trees_dir` at the other repo's worktree root instead —
  but that is the exception, not the default.
- Also copy every local artifact the handover's source-of-truth section
  lists (for example, planning or findings docs) into `"$wt_dir/.local/"`,
  so the recipient is self-contained. Links to PRs or issues need no copy.
- If the `FAILED` line prints, stop and surface the failure to the user
  immediately; never leave a half-populated directory behind for someone
  else to clean up.
- Populating `.local/` in a sibling worktree is a normal part of this step.
  If the team-review plugin (and its `orchestrator-guard.sh`) is installed,
  it explicitly allows `.local/` writes into sibling worktrees; without it,
  the Write tool may prompt for confirmation on any file written outside
  the current worktree — that prompt is expected, not an error.
- See the worktrees plugin's usage skill for the full `newtree` mechanics
  (branch naming, default-branch resolution, existing-directory handling);
  this skill only documents the calls needed for handover.

### 3. Write the recipient's placeholder TODO.md

Using the `RECIPIENT READY:` path from step 2, write `<wt_dir>/.local/TODO.md`
with the tracking plugin's template format: `State: Not Started` and a
`Current Task` pointing at `Handover pickup: read
.local/handover-{ISSUE-KEY}.md, then proceed through the orchestration
workflow from Gate 1`. Use the Write tool at the concrete path — it targets
a sibling worktree, per the note in step 2. If the tracking plugin is not
installed, inline the essential fields yourself (a `## Status` block with
`State`, `Current Task`, `Last Updated`) rather than referencing a template
that is not there; either way this gives the new session a starting
pointer, and the new orchestrator overwrites it at its own Gate 1.

### 4. Hand off to the user

Report the created path and the one remaining step, then stop:

> Scaffolded `orchestrate-{ISSUE-KEY}-{short-description}` with the
> handover in its `.local/`. Run `cd <path> && clam`, pick `Build`, and the
> new orchestrator will read the handover and proceed from Gate 1.

This is a hand off, not a start: the user runs `clam` and picks `Build`
themselves.

## What you must not do

- Never write content into the recipient's `.local/.orchestrator` — the
  empty marker is correct; the new session fills its content, the parent
  issue, at its own Gate 1.
- Never pre-populate `PLAN.md` or `IMPLEMENTATION-PLAN.md` in the recipient
  worktree.
- Never file subtasks for the new orchestrator's chunks — the new
  orchestrator does that at its own Gate 1.
- Never start a session in the recipient worktree yourself, or `cd` into it
  for the rest of your own session — only the user runs `clam` there.
- Never delegate any step of this scaffolding to a subagent — write the
  handover, create the worktree, and populate `.local/` yourself, directly.

## Recipient's flow (informational)

For context on what happens after you scaffold — you do not perform any of
this yourself:

1. The user runs `cd <recipient worktree> && clam` and picks `Build`.
2. If a session-modes plugin is installed, its `/start` may detect the
   handover document under `.local/` and read it automatically; without it,
   the recipient's first move (documented in the template) is to read the
   handover manually as the starting point.
3. The new session proceeds through the orchestration workflow's own gates
   from Gate 1, using the parent issue named in the handover.

## Issue-tracker-agnostic by design

This skill works the same way whether the sub-effort is tracked in GitHub
Issues, Linear, Jira, or no tracker at all — it is issue-tracker-agnostic.
When there is no issue key, use a descriptive slug in its place throughout
(`orchestrate/{short-description}` for the branch,
`.local/handover-{slug}.md` for the doc).
