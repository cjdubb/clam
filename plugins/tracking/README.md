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
- **`lib/states.tsv`** is the canonical State manifest (13 states; category,
  emoji, colour, summons). `lib/states.sh` holds the shared readers
  (`todo_field`, `state_category`, …). The statusline plugin vendors a copy —
  keep them in lockstep.
- **`templates/TODO.md`** is the tracking-doc skeleton.

## Knobs

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAM_TRACKING_STOP_GATE` | `enabled` | `disabled` turns off the Stop-hook enforcement entirely. |
| `CLAM_PR_CRONS` | `disabled` | `enabled` blocks parking/completing with an open PR that has no monitoring cron (needs the pr-workflow plugin's create-pr watch crons; opt-in here, unlike clam-code where unset meant enabled). |
| `CLAM_INDEPENDENT_REVIEW` | `disabled` | `enabled` blocks human-handoff states without an independent-review report (needs the independent-review skill). |
| `CLAUDE_STOP_LOG` | `~/.claude/stop-log.jsonl` | Stop-hook audit log location. |

## Soft integrations

All optional; everything degrades gracefully when absent:

- **decision-log plugin** — `Waiting For Decision` parks expect a
  `.local/decisions/NNN-<slug>.md` file per `/decision-log:rundown`.
- **notify helper** (clam-code shell block, until the notifications plugin
  exists) — phone push on summoning transitions; skipped when not installed.
- **statusline plugin** — shows the State segment; **agent-dash** — reads the
  same files for its dashboard.

## Install

```
/plugin marketplace add cjdubb/clam
/plugin install tracking@clam
```

Installing changes nothing globally; the hooks apply only where the plugin is
enabled, and sessions without a `.local/TODO.md` are untouched (ad-hoc
sessions stay ad-hoc).
