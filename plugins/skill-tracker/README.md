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

No configuration required.

## What to expect

Installing enables the hooks immediately: every Skill tool invocation
(PreToolUse and PostToolUse) in any session where the plugin is active
appends a JSONL row to `~/.claude/skill-triggers.jsonl`. The log file (and
`~/.claude/` itself) is created automatically on the first invocation if it
doesn't already exist.

The hooks are fire-and-forget — they always exit 0, never block the
session, and degrade silently (no-op) if `jq` is not installed. No context
is injected into sessions and no settings are written.

## Common workflows

### Checking which skills fire (and which don't)

After a few days of use, invoke `/skill-tracker:stats` in any session. The
"Top skills (all-time)" section shows which skills are earning their keep;
skills absent from the list have never triggered — candidates for description
rewrites or pruning. The "Daily triggers" section shows whether a recent
change (new skill, description rewrite, budget adjustment) moved the needle.

### Debugging a skill that isn't triggering

If a skill should have fired but didn't, check the log directly:

```bash
grep '"skill":"my-skill-name"' ~/.claude/skill-triggers.jsonl
```

No hits means the model never selected it. Hits with `"event":"pre"` but a
matching `"event":"post"` carrying an `"error"` means it fired but failed.

### Auditing skill errors

Invoke `/skill-tracker:stats` — the "Errors" section at the bottom lists
failed invocations with timestamps, skill names, and error messages. For the
raw data:

```bash
jq -c 'select(.event=="post" and .error != null)' ~/.claude/skill-triggers.jsonl
```

### Running the reporter outside a session

The stats script works standalone — no active Claude Code session required:

```bash
bash ~/.claude/plugins/marketplaces/clam/plugins/skill-tracker/scripts/skill-stats.sh
```

## Commands

### Skills

#### `/skill-tracker:stats`

Runs `skill-stats.sh` and presents the output verbatim in the conversation.
Relays error or informational messages (missing jq, no log file, no
triggers) as-is. Model-invocable: its description ("Show skill trigger
statistics — how often each skill fires, daily trends, and errors") lets the
model select it whenever the user asks about skill usage, trigger frequency,
or wants to audit invocations, in addition to being run directly.

### Hooks

#### `log-skill-trigger.sh` (PreToolUse + PostToolUse)

Matched on the `Skill` tool. On every skill invocation, appends one JSONL row
to `~/.claude/skill-triggers.jsonl`:

```json
{"ts":"2026-07-22T10:30:00Z","event":"pre","skill":"deep-research","args":"some query","cwd":"/project","session_id":"sess-abc","transcript_path":"/tmp/t.jsonl","error":null}
```

| Field | Description |
|-------|-------------|
| `ts` | UTC ISO 8601 timestamp |
| `event` | `"pre"` (before execution) or `"post"` (after execution) |
| `skill` | Skill name, or `null` if not provided |
| `args` | Arguments passed to the skill, or `null` |
| `cwd` | Working directory at invocation time |
| `session_id` | Claude Code session ID |
| `transcript_path` | Path to the session transcript |
| `error` | Error message on post events when the skill failed; `null` otherwise |

- Always exits 0 — fire-and-forget; never blocks the session.
- Gracefully degrades when `jq` is absent (silent exit 0).
- Creates `~/.claude/` if it doesn't exist; write failures are swallowed.

### Scripts

#### `skill-stats.sh`

CLI reporter that reads `~/.claude/skill-triggers.jsonl` and prints a
single-page summary:

- **Header** — log path and date range of recorded data.
- **Total triggers** — count and unique skill count.
- **Top skills (all-time)** — top 15 by invocation count, descending.
- **Daily triggers (last 14 days)** — per-date trigger counts.
- **Errors** — count of failed invocations, plus up to 10 error details.

Only pre-events count as triggers; post-events are used only for error
reporting. Malformed JSONL lines are skipped silently. The log file is never
modified.

Requires `jq`. Exits 1 if `jq` is missing; exits 0 in all other cases
(missing log, empty log, successful report).

## Tests

```bash
bash plugins/skill-tracker/scripts/structure.test.sh
```

Structural only — checks `plugin.json`'s manifest fields, `hooks.json`'s
PreToolUse/PostToolUse wiring, the scripts' presence and shebangs, the stats
skill's frontmatter, and the plugin's registration in the repo-root
`marketplace.json`. Hermetic: reads only the repo's own committed files, no
network, no mutation, cwd-independent.

## Update

```
/plugin marketplace update clam
claude plugin update skill-tracker@clam
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
