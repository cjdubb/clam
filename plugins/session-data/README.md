# session-data

session-data locates the current Claude Code session's own conversation data
files on disk — the main transcript JSONL, subagent transcripts,
file-history snapshots, and session metadata — and reports their absolute
paths, existence, and size, each annotated with whether it may contain
sensitive material. Install it when you need to find, review, or hand off
your own session's data without knowing Claude Code's on-disk layout by
heart.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install session-data@clam
```

No configuration required.

## What to expect

Installing this plugin changes nothing on its own — it ships one skill and
no hooks, so nothing runs until you invoke `/session-data:paths`. Nothing is
injected into sessions, no settings are written, and no files are created;
the plugin only ever reads.

When you run the skill, Claude executes `scripts/resolve-paths.sh` and
presents a structured report of where the current session's data lives,
derived from `$CLAUDE_CODE_SESSION_ID`, `$PWD`, `$HOME`, and (when set)
`$CLAUDE_PID`:

- **Main transcript** — the session's JSONL, with its found/not-found status
  and size in bytes.
- **Subagent transcripts** — the directory of any subagent `.jsonl` files,
  with a count.
- **File-history snapshots** — the directory of full-content snapshots
  Claude Code keeps of edited files, with a count.
- **Session metadata** — reported only when `$CLAUDE_PID` is set.

Every category that can hold sensitive material (the main transcript,
subagent transcripts, file-history) carries a sensitivity annotation in the
script's own output, and Claude repeats that warning when it presents the
paths. The script never surfaces `~/.claude/daemon/roster.json`,
`~/.claude/.credentials.json`, or any other Claude Code internal, and never
creates, modifies, or deletes anything.

## Common workflows

### Locate your current session's data

Run `/session-data:paths`. Claude runs the resolution script and presents
each category — main transcript, subagent transcripts, file-history,
session metadata — with its absolute path and existence status, plus a
sensitivity warning. Claude won't open or read any of the listed files
unless you explicitly ask, and repeats the sensitivity warning first if you
do.

### Hand your transcript to a fresh agent for review

After `/session-data:paths` reports the main transcript path, Claude offers
to spawn a fresh agent with that path to review the conversation — accept
the offer, or ask directly at any point. Keep in mind the fresh agent will
see the full transcript, including any secrets captured in tool output.

### Diagnose a failed lookup

If `/session-data:paths` fails, Claude reports the script's error message
verbatim and explains the likely cause. The most common one is running
outside Claude Code, where `CLAUDE_CODE_SESSION_ID` isn't set; that's a hard
failure (exit 1), distinct from a category that simply doesn't exist yet
(reported inline as `[not found]`, not an error).

## Commands

### Skills

- **`/session-data:paths`** — runs `scripts/resolve-paths.sh` and presents
  the current session's conversation data file locations: main transcript,
  subagent transcripts, file-history snapshots, and session metadata.
  Always includes a sensitivity warning and never reads file contents
  without asking first. Model-invocable — Claude will run it when you ask
  to locate, review, or hand off your session data, not only on the literal
  slash command.

### Scripts

- **`scripts/resolve-paths.sh`** — the skill's underlying implementation;
  can also be run directly:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.sh"
  ```
  Requires `CLAUDE_CODE_SESSION_ID` and `HOME` in the environment (both are
  set automatically inside a Claude Code session); exits 1 with a
  diagnostic on stderr if either is missing. `CLAUDE_PID`, if also set,
  additionally reports the session-metadata file. Read-only and
  deterministic — the same environment always produces the same report.

## Tests

```bash
bash plugins/session-data/scripts/resolve-paths.test.sh
bash plugins/session-data/scripts/paths-skill.test.sh
bash plugins/session-data/scripts/registration.test.sh
bash plugins/session-data/scripts/structure.test.sh
bash plugins/session-data/scripts/structure-meta.test.sh
```

## Relationships to other plugins

None required. This plugin is fully standalone.

## Uninstalling

```
/plugin uninstall session-data@clam
```

No cleanup needed — the plugin never writes files or settings, so
uninstalling removes everything.
