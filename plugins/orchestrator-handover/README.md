# orchestrator-handover

Hands a discrete sub-effort off from an active orchestrator session to a
fresh one: writes a handover document, scaffolds the recipient orchestrator
worktree, and populates its `.local/` — all before the user ever starts the
new session. The orchestrator only ever scaffolds; a worktree becomes a live
orchestrator when a human runs `clam` there and picks `Build`.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install orchestrator-handover@clam
```

No configuration required. The one hard prerequisite is the worktrees
plugin's `newtree` (or an equivalent shell function already sourced) — the
skill uses it to create the recipient worktree; see Relationships to other
plugins below.

## What to expect

Installing this plugin changes nothing globally — it is inert until you (or
Claude Code) invoke `/orchestrator-handover:create`. There are no hooks and
no background behavior. When the skill runs, in the current worktree it:

- writes a handover document to `.local/handover-{ISSUE-KEY}.md` (or
  `.local/handover-{slug}.md` with no issue tracker in use) — a provenance
  copy that stays behind in the current worktree;
- creates a sibling worktree with `newtree` and writes into its `.local/`: a
  copy of the handover, a `MODE` file set to `Build`, and an empty
  `.orchestrator` marker;
- writes a placeholder tracking document into that sibling worktree's
  `.local/`, so the new session has a starting pointer;
- reports the created path back to you and stops — it never starts a
  session there itself.

Claude Code may also invoke the skill automatically when an active
orchestrator session identifies a discrete sub-effort that deserves its own
coordination context, not just another section of the current
`IMPLEMENTATION-PLAN.md`.

## Common workflows

### Hand off a sub-effort to a fresh orchestrator

Invoke `/orchestrator-handover:create` (or let Claude Code invoke it) once
you've identified a discrete sub-effort that warrants its own PLAN and
tracking document. It writes the handover document, creates and populates
the recipient worktree, and reports back a path plus the one remaining
step:

> Scaffolded `orchestrate-{ISSUE-KEY}-{short-description}` with the
> handover in its `.local/`. Run `cd <path> && clam`, pick `Build`, and the
> new orchestrator will read the handover and proceed from Gate 1.

You then relay that to the user — the skill never starts a session in the
recipient worktree itself, and never delegates any of its own steps to a
subagent.

### Pick up a handover as the recipient

1. `cd` into the scaffolded worktree and run `clam`; pick `Build`.
2. If a session-modes plugin is installed, its `/start` may detect and read
   the handover document automatically; without it, read
   `.local/handover-*.md` yourself as your first move.
3. Continue through your own orchestration workflow's gates from wherever
   it begins, using the parent issue named in the handover.

### Hand off with no issue tracker

The skill is issue-tracker-agnostic: it works the same whether the
sub-effort is tracked in GitHub Issues, Linear, Jira, or nothing at all.
With no tracker, use a descriptive slug in place of `{ISSUE-KEY}` throughout
— branch `orchestrate/{short-description}`, document
`.local/handover-{slug}.md`.

## Commands

**create** (`/orchestrator-handover:create`) — model-invocable. Runs the
four-step handover procedure described above: write the handover document;
create and populate the recipient worktree; write the recipient's
placeholder tracking document; report the path and stop. Needs enough
session context to fill the handover template's sections (what's done,
what's open, decisions pending, a proposed work breakdown) and, when the
sub-effort is tracked, its issue key.

Guarantees that hold regardless of session:

- never starts a session in the recipient worktree — only the user runs
  `clam` and picks `Build`;
- never writes content into the recipient's `.local/.orchestrator` — only
  an empty marker; the recipient fills it in at its own Gate 1;
- never pre-populates `PLAN.md` or `IMPLEMENTATION-PLAN.md` in the
  recipient worktree, and never files subtasks for its chunks;
- always uses `newtree` (never a ticket-specific variant), run inside a
  subshell so the current session's own working directory never drifts;
  aborts immediately if creation fails rather than leaving a
  half-populated directory behind.

If the recipient worktree directory already exists, `newtree` warns and
navigates into it rather than failing. The recipient's placeholder tracking
document uses the tracking plugin's template format (`State: Not Started`,
a `Current Task` pointing at the handover document) when that plugin is
installed, or inlines the same fields by hand when it is not — either way
the new orchestrator overwrites it at its own Gate 1.

See [skills/create/SKILL.md](skills/create/SKILL.md) for the full
step-by-step contract, and
[skills/create/template.md](skills/create/template.md) for the handover
document's structure: 7 sections covering source-of-truth artifacts, what's
done, what's open, pending decisions, a proposed work breakdown, cross-unit
compatibility notes, and the recipient's first move. Sections that don't
apply (no pending decisions, no shared interfaces across units) carry an
explicit "None" marker rather than being dropped.

## Update

```
/plugin marketplace update clam
claude plugin update orchestrator-handover@clam
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

- **Requires:** the worktrees plugin's `newtree` (or an equivalent shell
  function already sourced) to create the recipient worktree.
- **Soft integrations, all optional:**
  - the tracking plugin — supplies the template format for the recipient's
    placeholder tracking document; without it, the skill inlines the
    essential fields by hand.
  - the team-review plugin's `orchestrator-guard.sh` — allows `.local/`
    writes into sibling worktrees without a confirmation prompt; without
    it, the Write tool may simply prompt for confirmation on those writes.
  - a session-modes plugin's `/start` — may pick up the handover document
    in a fresh session automatically; without it, the recipient reads it
    manually as a documented first move.
- **Provides:** the `create` skill only. Installing this plugin changes
  nothing globally.

## Uninstalling

```
/plugin uninstall orchestrator-handover@clam
```

Nothing else to revert — the skill only ever writes plain files into
worktrees' `.local/` directories (handover documents, `MODE`,
`.orchestrator` markers, the placeholder tracking document), and
uninstalling the plugin doesn't touch those. Clean them up by hand if you no
longer need them.
