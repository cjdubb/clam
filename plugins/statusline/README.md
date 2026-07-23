# statusline

Cam's statusline for Claude Code: path and git branch, PR-status and
git-sync badges, context-window usage, session/day/week cost, reasoning
effort, and — in repos using the tracking plugin — the session's clam mode
and State (emoji + colour straight from the shared states manifest). Claude
Code has no plugin field for statuslines, so installing this plugin changes
nothing by itself; you opt in explicitly with `/statusline:setup`.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install statusline@clam
```

Installing writes no configuration. `statusLine` exists only in
`~/.claude/settings.json`, and plugin path variables like
`${CLAUDE_PLUGIN_ROOT}` don't resolve there, so wiring it up is a deliberate
second step:

```
/statusline:setup          # writes statusLine into ~/.claude/settings.json
/statusline:setup remove   # puts it back
```

Requires `jq` on `PATH`.

## What to expect

Installing changes nothing: the plugin is inert until you run
`/statusline:setup`. Once wired, `scripts/context.sh` renders on every
statusline refresh (each turn, and on Claude Code's `statusLine` heartbeat)
as up to four lines:

- **Path + badges:** current directory (`~` for `$HOME`), git branch, a
  PR-status badge when `.local/.pr-status.json` exists at the worktree
  root, and a git ahead/behind indicator (`↓N ↑M`) when
  `.local/.git-sync.json` exists. Both files are expected to come from
  refresher engines (`lib/pr-status-refresh.sh`, `lib/git-sync-refresh.sh`)
  that `context.sh` launches in the background when their cache goes stale
  — this plugin does not currently ship those two scripts itself, so the
  badges only populate when something else writes those files.
- **Mode / model / effort:** the clam session mode from `.local/MODE`, the
  model's display name, and the reasoning-effort level, each omitted when
  absent, with the whole line dropped if all three are empty.
- **Context usage:** occupied tokens against the auto-compaction budget,
  colour-coded by occupancy and idle time.
- **Cost:** session / today (AEST) / week (AEST) spend, list-price
  equivalents computed from local transcripts — a counterfactual to a
  subscription plan, not what you were billed.

In a repo using the tracking plugin's `.local/TODO.md` convention, a State
segment (emoji + colour from the shared states manifest) appears on the
first line; elsewhere it stays hidden — the statusline works fine without
the tracking plugin.

## Common workflows

### Check today's or this week's spend from the shell

The statusline's cost figures come from `scripts/ccost.sh`, which you can
also run directly:

```
bash scripts/ccost.sh day
bash scripts/ccost.sh week
bash scripts/ccost.sh session /path/to/transcript.jsonl
```

Each mode prints one USD number to stdout (`0` on any error, e.g. missing
`jq`).

### Align the context meter with your compaction window

The context-usage line divides real occupancy (`total_input_tokens`) by
`CLAUDE_CODE_AUTO_COMPACT_WINDOW`, falling back to the same setting read
from `~/.claude/settings.json`, then to the model's full reported context
window. If you've set a custom auto-compact window, set the matching env
var in the `env` block of the settings file at whichever scope you set it,
so the meter tracks the budget compaction actually fires against instead of
the model's full window.

### Update prices after an Anthropic rate change

Cost figures come from the pinned table in `scripts/prices.json` (USD per
million tokens, matched by longest model-ID prefix). Edit that file when
Anthropic publishes new rates; nothing else needs to change.

### Turn the statusline off without uninstalling

```
/statusline:setup remove
```

Restores whatever `statusLine` value (or absence of one) preceded the
setup, without touching any other setting.

## Commands

### Skills

**`/statusline:setup`** — not model-invocable
(`disable-model-invocation: true`); must be run explicitly. Resolves the
installed plugin root, shows the current `statusLine` value in
`~/.claude/settings.json` and the entry it's about to write (asking first
if a different statusline is already configured), backs up the settings
file, merges in just the `statusLine` key via `jq` (preserving every other
setting), and verifies the result still parses.

**`/statusline:setup remove`** — reverses it: deletes the `statusLine` key
(or restores the backup), preserving all other settings.

### Scripts

**`scripts/context.sh`** — the statusLine entry point; reads the
`statusLine` JSON payload on stdin and prints the rendered lines described
in [What to expect](#what-to-expect). Requires `jq`; bash 3.2-safe (macOS
`/bin/bash`). Reads `CLAUDE_EFFORT` as a fallback for the reasoning-effort
segment when the live JSON's `.effort.level` field is absent (e.g.
mid-session `/effort` changes take the JSON field; a fresh launch without
that field falls back to the env var). Reads `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
as described above. Also opportunistically writes
`.local/.ctx-status.json` (context tokens, budget, occupancy, idle seconds,
staleness level, timestamp) for the separate agent-dash project to read
across sessions — best-effort and atomic, never errors the statusline on
failure.

**`scripts/ccost.sh`** — cost calculator invoked by `context.sh` and usable
standalone (see [Common workflows](#common-workflows)). Sums
`input`/`output`/cache token usage from `~/.claude/projects` JSONL
transcripts against `scripts/prices.json`. `day`/`week` are bounded at the
Australia/Sydney midnight boundary (DST-aware via `python3`'s `zoneinfo`;
falls back to no cutoff if `python3` is unavailable) and cached 300s under
`~/.claude/.ccost-cache`, single-flighted with an `mkdir`-based lock (stale
after 120s) so concurrent sessions don't all rescan hundreds of MB of
transcripts at once — a process that loses the lock race serves the last
cached figure (or `0` if none exists) instead of waiting. `session` mode is
cached per transcript path and stays valid while the transcript is
untouched.

**`scripts/prices.json`** — the pinned price table `ccost.sh` reads;
see [Common workflows](#common-workflows) for updating it.

Both scripts source `lib/platform.sh` for OS-aware `stat`/`uname` handling,
and `context.sh` additionally sources `lib/states.sh` and `lib/states.tsv`
for the State segment — a vendored copy of the tracking plugin's session
States manifest; keep it in lockstep with the canonical copy there.

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAUDE_EFFORT` | unset | Fallback reasoning-effort value when the live JSON has none. |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | unset | Context-meter budget; falls back to the same key in `~/.claude/settings.json`, then the model's reported context window. |
| `CLAUDE_PROJECTS_DIR` | `~/.claude/projects` | Where `ccost.sh` looks for transcript JSONL files. |
| `CCOST_CACHE_DIR` | `~/.claude/.ccost-cache` | Where `ccost.sh` caches period sums and locks. |

## Tests

```bash
bash plugins/statusline/scripts/context.test.sh
bash plugins/statusline/scripts/ccost.test.sh
```

## Relationships to other plugins

Soft integration only; everything degrades gracefully when absent:

- **tracking plugin** — canonical source of the session-States manifest
  (`lib/states.sh` / `lib/states.tsv` here are a vendored copy) and of
  `.local/TODO.md`, whose `State:` field drives the State segment. Without
  it, the State segment simply doesn't render.
- **agent-dash** (separate project) — reads the `.local/.ctx-status.json`
  file `context.sh` publishes.

## Uninstalling

```
/plugin uninstall statusline@clam
```

If you ran `/statusline:setup`, run `/statusline:setup remove` first (or
right after) — otherwise `~/.claude/settings.json` keeps pointing
`statusLine` at a `context.sh` path that no longer exists. Plugin updates
keep the same install path, so the settings entry survives updates on its
own; only an uninstall breaks it. `~/.claude/.ccost-cache` is not removed
automatically; it's harmless disk clutter safe to delete by hand.
