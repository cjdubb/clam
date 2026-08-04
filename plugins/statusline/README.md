# statusline

Cam's statusline for Claude Code, in two lines: **where you are** — path, git
branch, PR-status and git-sync badges, the clam session mode and the session
State — and **how fast you are burning** — model and reasoning effort, your
weekly and 5-hour plan limits paced against the hours you are actually awake,
context-window occupancy, and a pet whose mood tracks whichever meter is
worst. Claude Code has no plugin field for statuslines, so installing this
plugin changes nothing by itself; you opt in explicitly with
`/statusline:setup`.

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
as two lines:

```
~/github/clam (burnrate) 🟡 #231 ↑2  Build  ⚡ In Progress
🦄 Fable 5 high │ 🎯 32% 72%t 17%/d ▼-11 │ 🧠 10% +503/-16 │ 🔥 1% 4h54m │ 😼·
```

**Line 1 — where you are.** In the order shown: the current directory (`~`
for `$HOME`), the git branch, a PR-status badge when `.local/.pr-status.json`
exists at the worktree root, a git ahead/behind indicator (`↓N ↑M`) when
`.local/.git-sync.json` exists, the clam session mode from `.local/MODE`, and
the session State (emoji + colour from the shared states manifest) read from
`.local/TODO.md`. Every segment past the path is omitted when its source
isn't there, so a plain directory outside a repo renders just the path. The
two badge files are expected to come from refresher engines
(`lib/pr-status-refresh.sh`,
`lib/git-sync-refresh.sh`) that `context.sh` launches in the background when
their cache goes stale — this plugin does not currently ship those two
scripts itself, so the badges only populate when something else writes those
files.

**Line 2 — the burnrate line.** Five groups joined by a dim `│`. A group with
no data vanishes together with its separator, so the line never shows a
dangling `│` or an emoji with no number beside it; when every group is empty
the line is not printed at all.

- **Model** — a mascot per model family (🎭 Opus, 🪶 Sonnet, 🦄 Fable,
  🌸 Haiku, 🤖 anything else), the model's display name in a slowly drifting
  rainbow, and the reasoning-effort tier coloured cool-to-hot.
- **Weekly limit** — `🎯 used%` of your 7-day allowance, followed by the
  three pacing figures explained below: `%t`, `%/d` and a trend arrow.
- **Context** — `🧠 ctx%`, occupied tokens against the auto-compaction
  budget, coloured by occupancy and idle time, plus `+added/-removed` once
  the session has actually edited something.
- **5-hour limit** — `🔥 used%` of the rolling 5-hour allowance and the
  countdown to its reset (`4h54m`, or `12m` under the hour).
- **Pet** — a cat whose mood is keyed to whichever of the three meters above
  is worst (happy → alert → nervous → panic), animated across eight frames
  so it visibly reacts rather than sitting still.

### Reading the burnrate figures

The weekly group's three derived figures all answer *"am I going to run out
before the reset?"*, from different angles.

- **`%t` — how much of today's share is still unspent.** Your weekly
  allowance is spread evenly over the days between the last reset and the
  next; `%t` is the part of *today's* slice you have left, as a percentage of
  that slice. `100%t` means the whole of today is still ahead of you, `0%t`
  means you have landed exactly on tonight's checkpoint. It goes **negative**
  when you have spent past that checkpoint and are eating into tomorrow's
  slice — a perfectly ordinary thing to do on a heavy day, and a signal to
  ease off tomorrow rather than a fault.
- **`%/d` — the sustainable pace.** How many percentage points of the weekly
  limit you can spend per day, from right now until the reset, without
  running out. About `14%/d` is the even-burn baseline over a full week: a
  higher number means you have built up slack, a lower one means the rest of
  the week is tight and you should spend it deliberately.
- **The trend arrow** — where you sit against that even-burn line, with the
  gap beside it in weekly percentage points. `▲` means you are above the line
  (you have used more of the week than the clock says you should have by now,
  so you will hit the cap before the reset if nothing changes); `▼` means you
  are below it, on course to leave part of the subscription unused.

**The pacing counts awake hours only.** A day here starts at
`CLAM_STATUSLINE_DAY_START` (default `2`, so 02:00 local), and the first
`CLAM_STATUSLINE_SLEEP_HOURS` (default `6`) after that count for nothing at
all. The budget is therefore spread across the hours you are actually
working, not all 24 — without that, the trend would drift `▼` further behind
every night while you slept and snap back every morning, which is the single
most misleading thing a naive pacing model does. If your day starts at 07:00
and you sleep eight hours, set both knobs to match: see
[Common workflows](#common-workflows).

The two plan meters come straight from Claude Code's own payload and are
never cached — a stale quota figure is worse than none. The server reports
weekly usage in whole percentage points, so between ticks `%t` is interpolated
from this session's own spend to keep it moving smoothly instead of jumping;
it re-anchors on every real tick, and it deliberately errs toward showing
slightly *more* headroom than you have, since parallel sessions, other
machines and claude.ai usage are invisible to it.

### Caching and staleness

Rendering line 1 on every heartbeat is expensive (git calls, badge-file
reads), so `context.sh` caches its pricier segments and accepts a small
amount of staleness in exchange:

- **Branch, PR badge, git-sync, the State segment and the clam mode** are one
  bundle, refreshed at most once every 5 seconds
  (`CLAM_STATUSLINE_SEGMENT_TTL_SECONDS`, default `5`) and stored per-session
  under `CLAM_STATUSLINE_CACHE_DIR` (default `~/.claude/.statusline-cache`).
  A render inside that window reuses the cached bundle instead of re-running
  the git, badge and state lookups.
- **The cwd path and the whole of line 2 always render live** — recomputed
  on every render, never served from that bundle — along with the
  `.local/.ctx-status.json` publish. Only the bundled segments above are
  throttled.
- Two small state files sit beside the bundle in the same cache directory:
  the animation frame counter and the interpolator's anchor. Both are
  best-effort — an unwritable path freezes the animation, it does not break
  the render.
- Cache failures (unwritable cache dir, corrupt cache file, etc.) degrade to
  a full, freshly computed render — you get a slightly slower statusline,
  never a broken or blank one.

## Common workflows

### Match the pacing to the hours you actually work

The defaults assume a day that flips at 02:00 and six hours of sleep after
it. If that isn't you, set both knobs in the `env` block of the settings file
at whichever scope you installed the plugin:

```jsonc
"env": {
  "CLAM_STATUSLINE_DAY_START": "7",     // your day flips at 07:00 local
  "CLAM_STATUSLINE_SLEEP_HOURS": "8"    // 07:00-15:00 counted as sleep
}
```

Both take whole hours in `0..23`; anything else falls back to the default
rather than erroring. `%t`, `%/d` and the trend arrow all shift with them —
the raw `🎯 used%` does not, since that number is the server's.

### Align the context meter with your compaction window

The `🧠` meter divides real occupancy (`total_input_tokens`) by
`CLAUDE_CODE_AUTO_COMPACT_WINDOW`, falling back to the same setting read from
`~/.claude/settings.json`, then to the model's full reported context window.
If you've set a custom auto-compact window, set the matching env var in the
`env` block of the settings file at whichever scope you set it, so the meter
tracks the budget compaction actually fires against instead of the model's
full window.

### Check today's or this week's spend from the shell

The statusline itself no longer shows a spend figure — the plan meters
replaced it — but `scripts/ccost.sh` stays in the plugin as a standalone CLI:

```
bash scripts/ccost.sh day
bash scripts/ccost.sh week
bash scripts/ccost.sh session /path/to/transcript.jsonl
```

Each mode prints one USD number to stdout (`0` on any error, e.g. missing
`jq`). The figures are list-price equivalents computed from local transcripts
— a counterfactual to a subscription plan, not what you were billed.

### Update prices after an Anthropic rate change

`ccost.sh` prices token counts from the pinned table in
`scripts/prices.json` (USD per million tokens, matched by longest model-ID
prefix). Edit that file when Anthropic publishes new rates; nothing else
needs to change.

### Turn the statusline off without uninstalling

```
/statusline:setup remove
```

Restores whatever `statusLine` value (or absence of one) preceded the setup,
without touching any other setting.

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

**`scripts/context.sh`** — the statusLine entry point; reads the `statusLine`
JSON payload on stdin and prints the two lines described in
[What to expect](#what-to-expect). Requires `jq`; bash 3.2-safe (macOS
`/bin/bash`). Renders on a tight process budget — one `jq`, at most two
`date` and two `awk`, no `git` and nothing read under `CLAUDE_PROJECTS_DIR`
on a warm render. Reads `CLAUDE_EFFORT` as a fallback for the
reasoning-effort segment when the live JSON's `.effort.level` field is absent
(e.g. mid-session `/effort` changes take the JSON field; a fresh launch
without that field falls back to the env var). Reads
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` as described above. Also opportunistically
writes `.local/.ctx-status.json` (context tokens, budget, occupancy, idle
seconds, staleness level, timestamp) for the separate agent-dash project to
read across sessions — best-effort and atomic, never errors the statusline on
failure. Caches the branch/badges/State/mode bundle per session under
`CLAM_STATUSLINE_CACHE_DIR` for `CLAM_STATUSLINE_SEGMENT_TTL_SECONDS`
(default 5s); see [Caching and staleness](#caching-and-staleness).

**`scripts/ccost.sh`** — cost calculator, run standalone (see
[Common workflows](#common-workflows)); nothing in the render invokes it.
Sums `input`/`output`/cache token usage from `~/.claude/projects` JSONL
transcripts against `scripts/prices.json`. `day`/`week` are bounded at the
Australia/Sydney midnight boundary (DST-aware via `python3`'s `zoneinfo`;
falls back to no cutoff if `python3` is unavailable) and cached for 300
seconds under `~/.claude/.ccost-cache`, single-flighted with an `mkdir`-based
lock (stale after 120s) so concurrent sessions don't all rescan hundreds of
MB of transcripts at once — a process that loses the lock race serves the
last cached figure (or `0` if none exists) instead of waiting. `session` mode
serves its cached figure without touching the transcript at all while the
cache is younger than `CCOST_SESSION_TTL_SECONDS` (default 30s); once that
window lapses it falls back to the legacy behaviour of staying cached as long
as the transcript itself is untouched.

**`scripts/prices.json`** — the pinned price table `ccost.sh` reads;
see [Common workflows](#common-workflows) for updating it.

Both scripts source `lib/platform.sh` for OS-aware `stat`/`uname` handling,
and `context.sh` additionally sources `lib/states.sh` and `lib/states.tsv`
for the State segment. The state *names* in that manifest are the shared
vocabulary specified in `docs/protocols/session-states.md`, so keep them in
lockstep with it; the emoji and colour beside each name are this renderer's
own mapping, which the protocol deliberately leaves private.

The burnrate line lives in three more libraries `context.sh` sources:
`lib/burn-math.sh` (the awake-hours pacing model), `lib/burn-tick.sh` (the
sub-tick interpolator behind `%t`) and `lib/burn-theme.sh` (every mascot,
colour scale, countdown and pet frame). Any of the three being absent drops
only the groups that need it, rather than failing the render.

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAUDE_EFFORT` | unset | Fallback reasoning-effort value when the live JSON has none. |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | unset | Context-meter budget; falls back to the same key in `~/.claude/settings.json`, then the model's reported context window. |
| `CLAUDE_PROJECTS_DIR` | `~/.claude/projects` | Where `ccost.sh` looks for transcript JSONL files. |
| `CCOST_CACHE_DIR` | `~/.claude/.ccost-cache` | Where `ccost.sh` caches period sums and locks. |
| `CCOST_SESSION_TTL_SECONDS` | `30` | How long `ccost.sh session` serves its cached figure without touching the transcript. `<= 0` disables the window. |
| `CLAM_STATUSLINE_CACHE_DIR` | `~/.claude/.statusline-cache` | Where `context.sh` caches the per-session branch/badges/State/mode bundle, the animation frame and the interpolator anchor. |
| `CLAM_STATUSLINE_SEGMENT_TTL_SECONDS` | `5` | How long that cached bundle is served before `context.sh` rebuilds it. `<= 0` disables the cache. |
| `CLAM_STATUSLINE_DAY_START` | `2` | Hour (`0..23`, local) the pacing day flips. Out-of-range or non-integer values fall back to the default. |
| `CLAM_STATUSLINE_SLEEP_HOURS` | `6` | Hours after the day start counted as sleep and excluded from the pacing budget. Same fallback rule. |

## Tests

```bash
bash plugins/statusline/scripts/context.test.sh
bash plugins/statusline/scripts/ccost.test.sh
bash plugins/statusline/scripts/render-budget.test.sh
bash plugins/statusline/scripts/readme.test.sh
bash plugins/statusline/lib/burn-math.test.sh
bash plugins/statusline/lib/burn-tick.test.sh
bash plugins/statusline/lib/burn-theme.test.sh
```

## Attribution

The burnrate line is ported from
[claude-statusline-burnrate](https://github.com/Gui-Gou/claude-statusline-burnrate)
by Gui-Gou, MIT licensed. The awake-hours pacing model, the sub-tick
interpolator that keeps `%t` moving between server ticks, and the pet are all
that project's ideas; `lib/burn-math.sh`, `lib/burn-tick.sh` and
`lib/burn-theme.sh` each carry the upstream copyright notice in full. This
port differs in a few deliberate places — 256-colour output throughout, and
this plugin's own idle-aware context meter in place of the upstream's — but
the pacing arithmetic is Gui-Gou's.

## Update

```
/plugin marketplace update clam
claude plugin update statusline@clam
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
own; only an uninstall breaks it. Neither `~/.claude/.statusline-cache` nor
`~/.claude/.ccost-cache` is removed automatically; both are harmless disk
clutter, safe to delete by hand.
