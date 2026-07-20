# tracking

The tracking-document approach from clam-code, as a standalone plugin:
`.local/TODO.md` in each worktree is the session's single source of truth,
updated in real time, so session state survives compaction, `/clear`, and
orchestrator handoff — a fresh session reads the tracking docs and picks up
exactly where the last one parked. The same files power the
[agent-dash](https://github.com/cjdubb/clam-agent-dashboard) and the
statusline plugin's State segment.

## How it works

- **SessionStart** (`scripts/session-context.sh`) injects the Work Management
  rules as context — the plugin replacement for clam-code's system-prompt
  injection — and, when `.local/TODO.md` already exists, surfaces its State
  and Current Task with an instruction to resume from the docs, not restart.
- **Stop** (`scripts/keep-working.sh`) enforces the state lifecycle: a turn
  may end only in `Complete`, a needs-user state (`Blocked`,
  `Waiting For Decision` — with its decision-file nudge), or a parked
  `Awaiting *` state. `In Progress` gets nudged to continue; unrecognised
  states get the exact valid list so a near-miss self-corrects instead of
  being rationalised into a false `Complete`.
- **Stop/UserPromptSubmit** (`scripts/awaiting-user.sh`) maintains the
  `.local/.awaiting-user` marker consumers use for summons-epoch semantics.
- **PreToolUse** (`scripts/block-task-tools.sh`) denies the built-in
  TaskCreate/TaskUpdate/TaskList/TaskGet tools: they write to
  `~/.claude/tasks/`, which the tracking docs, agent-dash, and the statusline
  never see. The deny message redirects tracking to `.local/TODO.md`.
  TeamCreate and the other team-coordination tools are not matched.
- **`lib/states.tsv`** is the canonical State manifest (13 states; category,
  emoji, colour, summons). `lib/states.sh` holds the shared readers
  (`todo_field`, `state_category`, …). The statusline plugin vendors a copy —
  keep them in lockstep.
- **`templates/TODO.md`** is the tracking-doc skeleton.

## Knobs

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAM_TRACKING_STOP_GATE` | `enabled` | `disabled` turns off the Stop-hook enforcement entirely. |
| `CLAM_TRACKING_TASK_TOOLS_GATE` | `enabled` | `disabled` turns off the built-in task-tools deny. |
| `CLAM_PR_CRONS` | `disabled` | `enabled` blocks parking/completing with an open PR that has no monitoring cron (needs the pr-workflow plugin's create-pr watch crons; opt-in here, unlike clam-code where unset meant enabled). |
| `CLAM_INDEPENDENT_REVIEW` | `disabled` | `enabled` blocks human-handoff states without an independent-review report (needs the independent-review skill). |
| `CLAUDE_STOP_LOG` | `~/.claude/stop-log.jsonl` | Stop-hook audit log location. |

## Soft integrations

All optional; everything degrades gracefully when absent:

- **decision-log plugin** — `Waiting For Decision` parks expect a
  `.local/decisions/NNN-<slug>.md` file per `/decision-log:rundown`.
- **notifications plugin** — bell, desktop notification, tmux highlight, and
  phone push on summoning transitions; its idle-event backstop delivers the
  push even when the `notify` shell helper is not installed.
- **statusline plugin** — shows the State segment; **agent-dash** — reads the
  same files for its dashboard.

## Install

```
/plugin marketplace add cjdubb/clam
/plugin install tracking@clam
```

Installing changes nothing globally; the hooks apply only where the plugin is
enabled. Sessions without a `.local/TODO.md` skip the Stop-hook enforcement
(ad-hoc sessions stay ad-hoc); the task-tools deny is the one hook that fires
regardless, since tracking anywhere but `.local/TODO.md` is exactly what it
exists to prevent.
