# orchestrator-handover

Hands off a discrete sub-effort from an active orchestrator session to a
fresh one: writes a handover document, scaffolds the recipient orchestrator
worktree, and populates its `.local/` — all before the user ever starts the
new session. The orchestrator only ever scaffolds; a worktree becomes a live
orchestrator when a human runs `clam` there and picks `Build`.

## Skill

- **create** (`/orchestrator-handover:create`) — the four-step handover
  procedure: write the handover document to the current worktree's
  `.local/`, create and populate a recipient worktree via `newtree`, write a
  placeholder tracking document for the recipient, and report the path back
  to the user.

Invoke it directly with `/orchestrator-handover:create`, or let Claude Code
invoke it automatically when an active orchestrator session identifies a
discrete sub-effort that deserves its own coordination context.

## What it does

1. Writes `.local/handover-{ISSUE-KEY}.md` in the current worktree, using
   the skill's companion template — a structured document covering
   source-of-truth artifacts, what's done, what's open, decisions pending, a
   proposed work breakdown, cross-unit compatibility notes, and the
   recipient's first move.
2. Creates the recipient worktree with `newtree` (never a ticket-specific
   variant) and populates its `.local/` with a copy of the handover, a
   `MODE` file set to `Build`, and an empty `.orchestrator` marker.
3. Writes a placeholder tracking document into the recipient's `.local/`,
   using the tracking plugin's template format when that plugin is
   installed, or inlining the essential fields when it is not.
4. Reports the created path and hands off — the orchestrator never starts a
   session in the recipient worktree; only the user does.

Issue-tracker-agnostic throughout: it works the same whether the sub-effort
is tracked in GitHub Issues, Linear, Jira, or nothing at all — with no issue
key, a descriptive slug takes its place.

## Dependencies

- **Requires:** the worktrees plugin's `newtree` (or an equivalent shell
  function already sourced) to create the recipient worktree.
- **Soft integrations, all optional:** the tracking plugin's tracking-doc
  template format (falls back to inlined fields when absent); the
  team-review plugin's `orchestrator-guard.sh`, which allows `.local/`
  writes into sibling worktrees (without it, the Write tool may simply
  prompt for confirmation); a session-modes plugin's `/start`, which may
  pick up the handover document automatically (without it, the recipient
  reads it manually as a documented first move).
- **Provides:** the `create` skill only. Installing this plugin changes
  nothing globally.

## Install

```
/plugin marketplace add cjdubb/clam
/plugin install orchestrator-handover@clam
```
