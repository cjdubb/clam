# statusline

Cam's statusline for Claude Code, in two lines: **where you are** — path, git
branch, PR-status and git-sync badges, the clam session mode and the session
State — and **how fast you are burning** — model and reasoning effort, your
weekly and 5-hour plan limits paced against the hours you actually work, and
context-window occupancy. Claude Code has no plugin field for
statuslines, so installing this plugin changes nothing by itself; you opt in
explicitly with `/statusline:setup`.

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
/statusline:setup          # writes the statusline keys into ~/.claude/settings.json
/statusline:setup remove   # puts them back
```

Requires `jq` on `PATH`.

## What to expect

Installing changes nothing: the plugin is inert until you run
`/statusline:setup`. Once wired, `scripts/context.sh` renders on every
statusline refresh (each turn, and on Claude Code's `statusLine` heartbeat)
as two lines:

```
~/github/clam › plugins/statusline (burnrate) wip #231 ↑2  Build  In Progress
Fable 5 high │ ctx 10% │ 5h 1% ▼-1 (4h54m) │ wk 32% ▼-28 (2d23h)
```

**Line 1 — where you are.** In the order shown: the project directory the
session started in (`~` for `$HOME`), then `›` and the current directory
written relative to the project dir whenever the two differ — when they are
the same path it renders as a single segment, and a current dir outside the
project dir keeps its absolute path. That whole path segment is a clickable
`file://` link, and it opens the directory you are working in now. Then the
git branch, a PR-status badge when `.local/.pr-status.json`
exists at the worktree root — `ok`, `queued` and `merged` collapse to counts,
while `todo`, `wip` and `ejected` render per PR as a clickable `#N` — a git
ahead/behind indicator (`↓N ↑M`) when `.local/.git-sync.json` exists, the
clam session mode from `.local/MODE`, and the session State
(colour from the shared states manifest) read from `.local/TODO.md`. When
that document's optional `Live view:` field (todo-format protocol) holds an
http(s) URL, the State segment gains a clickable `live` hyperlink to it;
`none` or any other value renders nothing. Every
segment past the path is omitted when its source isn't there, so a plain
directory outside a repo renders just the path. The two badge files come
from refresher engines that `context.sh` launches in the background when
their cache goes stale. This plugin ships its own copy of the PR-status
engine (`lib/pr-status-refresh.sh`, with the `lib/pr-status.sh` fetch
helper beside it), conforming to the repo-level
[PR-status cache protocol](../../docs/protocols/pr-status-cache.md), so the
PR badge populates on its own in any worktree with a `.local/` directory —
and the cache is shared, so anything else writing the same protocol files
is picked up too. The git-sync engine (`lib/git-sync-refresh.sh`) is not
shipped yet, so that badge only populates when something else writes
`.local/.git-sync.json`.

**Line 2 — the burnrate line.** Four groups joined by a dim `│`. A group with
no data vanishes together with its separator, so the line never shows a
dangling `│` or a label with no number beside it; when every group is empty
the line is not printed at all.

- **Model** — the model's display name coloured by family (blue deepening
  with capability, purple for Fable), and the reasoning-effort tier coloured
  cool-to-hot.
- **Context** — `ctx used%`, occupied tokens against the auto-compaction
  budget, coloured by occupancy alone: green below 20%, yellow from 20%,
  orange from 40%, and red from 60% and above. The idle-aware tier survives
  as the `level` field published to `.local/.ctx-status.json` — still
  staleness, not fullness.
- **5-hour limit** — `5h used%` of the rolling 5-hour allowance, the trend
  arrow against plain wall-clock pacing across that window, and the
  parenthesised countdown to its reset (`(4h54m)`, or `(12m)` under the
  hour).
- **Weekly limit** — `wk used%` of your 7-day allowance, the same trend
  arrow — paced across your working week rather than the raw clock — and the
  countdown to the weekly reset (`(2d23h)`).

### Reading the burnrate figures

Both limit groups carry the same three figures — used percentage, trend
arrow, reset countdown — in the same order, so the reading you learn on the
5-hour meter is the one the weekly meter wants too. Together they answer
*"am I going to run out before the reset?"*.

- **The trend arrow** — where you sit against the even-burn line for that
  window, with the gap beside it in percentage points of the window. `▲`
  means you are above the line: you have used more of the window than the
  time elapsed in it says you should have, so you will hit the cap before
  the reset if nothing changes. `▼` means you are below it, on course to
  leave part of the allowance unused. The 5-hour group measures elapsed time
  as plain wall clock, since a five-hour window is too short for a schedule
  to apply; the weekly group counts only the hours you work, so a weekend
  never drags its trend down on its own.
- **The countdown** — how long until that window's allowance resets, dimmed
  in parentheses (`(4h54m)`, `(2d23h)`, or `(12m)` under the hour).

Any `▲` carries a warm colour, and it warms as the gap widens: yellow just
over the line, orange as the gap grows, red once you are running well ahead
of it. On the line or behind it — a `▼`, or a gap of zero — the arrow
carries no colour at all, because running behind is unused allowance rather
than a hazard.

Both used percentages come straight from Claude Code's own payload and are
never cached — a stale quota figure is worse than none. They are the
server's view of your account, so parallel sessions, other machines and
claude.ai usage all count against them without being visible here. The
percentages are also deliberately plain and carry no colour of their own: a
high figure late in a window is information, not an alarm, and what warrants
a change of behaviour is the gap the arrow measures.

### Subagent rows in the agent panel

`/statusline:setup` also wires `subagentStatusLine`, so `scripts/subagent.sh`
renders the body of each row in the agent panel while subagents are running.
A row carries the task's name, its model, its reasoning effort, the basename
of the directory the task runs in (the last path segment, never the whole
path), and its context percentage. Every figure on a row is that subagent's
own, never the main session's — the `statusLine` payload has no per-task
state at all, which is why this is a second script rather than the same one.
A row shows no effort when the task inherits the session's effort level, so a
blank effort is inheritance rather than a bug or a dropped figure.

### Caching and staleness

Rendering line 1 on every heartbeat is expensive (git calls, badge-file
reads), so `context.sh` caches its pricier segments and accepts a small
amount of staleness in exchange:

- **Branch, PR badge, git-sync, the State segment and the clam mode** are one
  bundle, refreshed at most once every 5 seconds
  (`CLAM_STATUSLINE_SEGMENT_TTL_SECONDS`, default `5`) and stored under
  `CLAM_STATUSLINE_CACHE_DIR` (default `~/.claude/.statusline-cache`) in a
  file keyed on the payload's `session_id`, so two sessions never share a
  bundle; a payload carrying no `session_id` is keyed on the current
  directory instead. A render inside that window reuses the cached bundle
  instead of re-running the git, badge and state lookups.
- **The cache directory bounds itself.** Each time `context.sh` rebuilds the
  bundle it also sweeps that directory, removing the files left there more
  than a day ago, so an old session's bundle ages out on its own.
- **The path segment and the whole of line 2 always render live** — recomputed
  on every render, never served from that bundle — along with the
  `.local/.ctx-status.json` publish. Only the bundled segments above are
  throttled.
- Cache failures (unwritable cache dir, corrupt cache file, etc.) degrade to
  a full, freshly computed render — you get a slightly slower statusline,
  never a broken or blank one.

## Common workflows

### Match the pacing to the hours you actually work

The weekly trend paces your 7-day allowance across the hours you work, so
the days you are away from the keyboard never read as burnable time. Three
knobs describe that week, and the defaults assume Monday to Friday, 08:00 to
18:00. If that isn't you, set them in the `env` block of the settings file at
whichever scope you installed the plugin:

```jsonc
"env": {
  "CLAM_STATUSLINE_WORK_DAYS": "1-5",   // ISO weekdays, 1=Mon .. 7=Sun
  "CLAM_STATUSLINE_DAY_START": "7",     // your working day starts at 07:00
  "CLAM_STATUSLINE_DAY_END": "16"       // and finishes at 16:00
}
```

`CLAM_STATUSLINE_WORK_DAYS` takes ISO weekday numbers with commas and ranges
(`1-5`, `1,3,5`, `1-4,6`). The two hour knobs take whole hours — `0..23` for
the start, `1..24` for the end — and each unusable value falls back to its
own default rather than erroring, except an end at or before the start,
which falls back to the default pair. Every figure on the line is computed
in machine local time; there is deliberately no timezone knob, so a machine
whose clock is set away from the zone you work in shifts every working
window by that offset. The trend arrow shifts with these knobs — the raw
`wk used%` does not, since that number is the server's, and neither does the
5-hour group, which paces on wall clock alone.

**Upgrading.** `CLAM_STATUSLINE_DAY_START` keeps its name and changes both
its meaning and its default: it named the hour a pacing day flipped over,
defaulting to `2`, and it now names the hour your working day begins,
defaulting to `8`. If you already set it, re-read it against the working
week above and set `CLAM_STATUSLINE_DAY_END` beside it.

### Align the context meter with your compaction window

The `ctx` meter divides real occupancy (`total_input_tokens`) by
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

Restores whatever `statusLine`, `subagentStatusLine` and `refreshInterval`
values (or absences of them) preceded the setup, and deletes the three
schedule keys — `CLAM_STATUSLINE_WORK_DAYS`, `CLAM_STATUSLINE_DAY_START` and
`CLAM_STATUSLINE_DAY_END` — that setup may have written, without touching any
other setting.

## Commands

### Skills

**`/statusline:setup`** — not model-invocable
(`disable-model-invocation: true`); must be run explicitly. Resolves the
installed plugin root, shows the current `statusLine` and
`subagentStatusLine` values in `~/.claude/settings.json` and the entries it's
about to write (asking first if a different statusline is already
configured), backs up the settings file, merges in the `statusLine`,
`subagentStatusLine` and `refreshInterval` keys in one `jq` pass (preserving
every other setting), and verifies the result still parses.

It also discloses the effective working week the weekly trend arrow paces
against — `CLAM_STATUSLINE_WORK_DAYS`, `CLAM_STATUSLINE_DAY_START` and
`CLAM_STATUSLINE_DAY_END`, each shown as either a default or a value this
machine already carries — and asks once whether to keep that schedule or
change it. Accepting the schedule as shown writes nothing: no env key is
added and the `env` block is left untouched. Values you change are validated
against their documented domains and folded into the same single `jq` merge
as the three statusline keys, so `~/.claude/settings.json` is still written
once; the three schedule keys are written only when the schedule changes.

**`/statusline:setup remove`** — reverses it: deletes the `statusLine`,
`subagentStatusLine` and `refreshInterval` keys (or restores the backup),
preserving all other settings. It also deletes the three schedule keys —
`CLAM_STATUSLINE_WORK_DAYS`, `CLAM_STATUSLINE_DAY_START` and
`CLAM_STATUSLINE_DAY_END` — that setup may have written, dropping the `env`
block itself if that leaves it empty. A settings file written by an older
version has only the first of the three statusline keys, and remove handles
that.

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
failure. Caches the branch/badges/State/mode bundle under
`CLAM_STATUSLINE_CACHE_DIR`, keyed on the payload's `session_id`, for
`CLAM_STATUSLINE_SEGMENT_TTL_SECONDS` (default 5s), and sweeps files more
than a day old out of that directory whenever it rebuilds the bundle; see
[Caching and staleness](#caching-and-staleness).

**`scripts/subagent.sh`** — the `subagentStatusLine` entry point; reads the
agent-panel payload on stdin and prints one row per visible subagent, each
carrying that task's own name, model, reasoning effort, working directory and
context percentage (see [What to expect](#what-to-expect)). Requires `jq`;
bash 3.2-safe. Renders on the same tight process budget as the statusline —
one `jq` over the whole payload, no `git`, and no per-row forks. A malformed
payload emits no lines at all, which leaves every row at its default
rendering, and a missing `jq` does the same: a status line that fails loudly
is worse than one that fails invisibly.

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
lockstep with it; the colour beside each name is this renderer's own
mapping, which the protocol deliberately leaves private.

The burnrate line lives in two more libraries `context.sh` sources:
`lib/burn-math.sh` (the working-week pacing model behind the trend arrows)
and `lib/burn-theme.sh` (colour scales and countdowns). Either being absent
drops only the groups that need it, rather than failing the render.

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAUDE_EFFORT` | unset | Fallback reasoning-effort value when the live JSON has none. |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | unset | Context-meter budget; falls back to the same key in `~/.claude/settings.json`, then the model's reported context window. |
| `CLAUDE_PROJECTS_DIR` | `~/.claude/projects` | Where `ccost.sh` looks for transcript JSONL files. |
| `CCOST_CACHE_DIR` | `~/.claude/.ccost-cache` | Where `ccost.sh` caches period sums and locks. |
| `CCOST_SESSION_TTL_SECONDS` | `30` | How long `ccost.sh session` serves its cached figure without touching the transcript. `<= 0` disables the window. |
| `CLAM_STATUSLINE_CACHE_DIR` | `~/.claude/.statusline-cache` | Where `context.sh` caches the per-session branch/badges/State/mode bundle. |
| `CLAM_STATUSLINE_SEGMENT_TTL_SECONDS` | `5` | How long that cached bundle is served before `context.sh` rebuilds it. `<= 0` disables the cache. |
| `CLAM_STATUSLINE_WORK_DAYS` | `1-5` | ISO weekdays (1=Mon .. 7=Sun) you work, with commas and ranges. Unparseable values fall back to the default. |
| `CLAM_STATUSLINE_DAY_START` | `8` | Hour (`0..23`, local) your working day begins. Out-of-range or non-integer values fall back to the default. |
| `CLAM_STATUSLINE_DAY_END` | `18` | Hour (`1..24`, local) your working day ends. Same fallback rule; an end at or before the start falls back to the default pair. |

## Tests

```bash
bash plugins/statusline/scripts/context.test.sh
bash plugins/statusline/scripts/ccost.test.sh
bash plugins/statusline/scripts/render-budget.test.sh
bash plugins/statusline/scripts/readme.test.sh
bash plugins/statusline/scripts/live-view.test.sh
bash plugins/statusline/lib/burn-math.test.sh
bash plugins/statusline/lib/burn-theme.test.sh
```

## Attribution

The burnrate line is ported from
[claude-statusline-burnrate](https://github.com/Gui-Gou/claude-statusline-burnrate)
by Gui-Gou, MIT licensed. The even-burn trend — a plan limit read against
the share of its window already elapsed, signed so the arrow says which side
of the line you are on — is that project's idea; `lib/burn-math.sh` and
`lib/burn-theme.sh` each carry the upstream copyright notice in full. This
port differs from the upstream in a few deliberate places — 256-colour
output throughout, a working-week schedule where the upstream paces on its
own window, and the context meter's colour bands, which match the
upstream's exactly. The numerator behind that meter and its non-saturating
division stay this plugin's own.

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
`statusLine` and `subagentStatusLine` at `context.sh` and `subagent.sh` paths
that no longer exist, and keeps the `refreshInterval` the setup wrote. Plugin updates
keep the same install path, so the settings entry survives updates on its
own; only an uninstall breaks it. `~/.claude/.statusline-cache` bounds
itself — `context.sh` sweeps files more than a day old out of it as it
rebuilds — so an uninstall leaves at most a day's bundles behind there.
`~/.claude/.ccost-cache` is left where it is, harmless disk clutter, safe
to delete by hand.
