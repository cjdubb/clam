# skill-tracker

Skill invocation telemetry: logs every `/skill` trigger to
`~/.claude/skill-triggers.jsonl` and reports usage stats via
`/skill-tracker:stats`. Ported from clam-code's
`general/hooks/log-skill-trigger.sh` and `general/skill-stats.sh`.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install skill-tracker@clam
```

Installing enables the hooks immediately — every Skill tool invocation in
sessions where the plugin is active appends a JSONL row to the log. No
configuration required.

To see your stats, invoke `/skill-tracker:stats` in any session, or run the
reporter directly:

```bash
bash ~/.claude/plugins/marketplaces/clam/plugins/skill-tracker/scripts/skill-stats.sh
```

## Commands

### Hook: `log-skill-trigger.sh`

Wired as both PreToolUse and PostToolUse on the `Skill` tool. On every
invocation, appends one JSONL row to `~/.claude/skill-triggers.jsonl`:

```json
{"ts":"2026-07-22T10:30:00Z","event":"pre","skill":"deep-research","args":"some query","cwd":"/project","session_id":"sess-abc","transcript_path":"/tmp/t.jsonl","error":null}
```

- `event` is `"pre"` or `"post"` (derived from the hook event name).
- `error` is populated only on post events when the skill failed; null
  otherwise.
- Always exits 0 — fire-and-forget; never blocks the session.
- Gracefully degrades when `jq` is absent (silent exit 0).

### Script: `skill-stats.sh`

CLI reporter that reads the JSONL log and prints:

- **Header** — log path and date range of recorded data.
- **Top skills (all-time)** — top 15 skills by invocation count, descending.
- **Daily triggers (last 14 days)** — per-date trigger counts.
- **Errors** — count of failed skill invocations, plus up to 10 error
  details.

Requires `jq`. Exits 1 if `jq` is missing; exits 0 in all other cases
(missing log, empty log, successful report).

### Skill: `/skill-tracker:stats`

Runs `skill-stats.sh` and presents the output verbatim in the conversation.

## Relationships to other plugins

None required. This plugin is fully standalone.

The JSONL log at `~/.claude/skill-triggers.jsonl` is a stable interface —
any plugin or script can read it. In clam-code, `pr-retrospective` was the
primary consumer; that skill can depend on this plugin when it is ported to
pr-workflow.

## Uninstalling

```
/plugin uninstall skill-tracker@clam
```

The hooks stop firing immediately. The log file at
`~/.claude/skill-triggers.jsonl` is not removed — delete it manually if you
no longer need the data:

```bash
rm ~/.claude/skill-triggers.jsonl
```

## Tests

```bash
bash plugins/skill-tracker/scripts/log-skill-trigger.test.sh
bash plugins/skill-tracker/scripts/skill-stats.test.sh
bash plugins/skill-tracker/scripts/structure.test.sh
```

All hermetic: each test uses a temp `$HOME` so the real log is never touched.
