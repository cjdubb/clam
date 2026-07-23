<!--
Contract: B12 skill-tracker-readme
Behavior:
  Verify the existing skill-tracker README against the PLUGIN_README_TEMPLATE.
  This README already has all 4 required sections and complete command coverage.
Inputs:
  The existing README content, PLUGIN_README_TEMPLATE.
Outputs:
  Minimal or no changes. Verify that:
    1. Getting started — present and adequate (already has install command)
    2. Commands — present as Hooks/Scripts/Skills sections (complete)
    3. Relationships to other plugins — present (already says standalone)
    4. Uninstalling — present (already has uninstall + cleanup steps)
  If section headings don't match the template exactly but the content
  is equivalent, do NOT rename them — this README is the gold standard
  and existing section names are fine.
Errors: n/a (documentation).
Invariants:
  - Preserve ALL existing content verbatim.
  - This is a verify-only pass; changes should be minimal to none.
Edge cases:
  - If the README is already fully compliant (expected), output unchanged.
-->
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

## Hooks

### `log-skill-trigger.sh` (PreToolUse + PostToolUse)

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

## Scripts

### `skill-stats.sh`

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

## Skills

### `/skill-tracker:stats`

Runs `skill-stats.sh` and presents the output verbatim in the conversation.
Relays error or informational messages (missing jq, no log file, no
triggers) as-is.

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
