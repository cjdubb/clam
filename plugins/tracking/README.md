# tracking

The tracking-document approach from clam-code, as a standalone plugin:
`.local/TODO.md` in each worktree is the session's single source of truth,
updated in real time, so session state survives compaction, `/clear`, and
orchestrator handoff — a fresh session reads the tracking docs and picks up
exactly where the last one parked. The same files power the
[agent-dash](https://github.com/cjdubb/clam-agent-dashboard) and the
statusline plugin's State segment. It also absorbs the former make-progress
plugin's stall-recovery: a capture hook plus the `/tracking:make-progress`
skill for the user to manually get a stalled session moving again.


## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install tracking@clam
```

No configuration is required to start — every hook activates as soon as the
plugin is enabled. All tuning (gates, thresholds, log locations) is via
environment variables, documented alongside the hook that reads each one in
[Commands](#commands), with a summary table at the end of that section.

## What to expect

Installing changes nothing globally; the hooks apply only where the plugin
is enabled, and most of them are no-ops until a `.local/TODO.md` exists.
Sessions without one skip the Stop-hook enforcement entirely (ad-hoc "Go
Commando" sessions stay ad-hoc) — the task-tools deny is the one hook that
fires regardless, since tracking anywhere but `.local/TODO.md` is exactly
what it exists to prevent.

Concretely, once enabled:

- **Every SessionStart** (startup, resume, `/clear`, compact) injects the
  Work Management rules as `additionalContext` — the plugin replacement for
  clam-code's system-prompt injection — and clears the once-per-epoch
  nudge markers (`.decision-nudge-fired`, `.no-todo-nudge-fired`,
  `.flush-nudge-fired`, `.freshness-nudge-fired`) so each new epoch gets a
  fresh chance to nudge. When `$cwd/.local/` exists as a directory but
  `.local/TODO.md` does not, it is auto-created from `templates/TODO.md`
  with `[branch-name]` and the `[YYYY-MM-DD]` / `[YYYY-MM-DD HH:MM]`
  placeholders filled in — never overwriting an existing file. When
  `.local/TODO.md` already exists, its `State:` and `Current Task:` are
  normally surfaced with an instruction to resume from the docs rather
  than restart — this is what makes `/clear` and fresh orchestrator
  pickup work — UNLESS the docs demonstrably lag the conversation (human
  prompts recorded in this worktree's other transcripts postdate the
  docs), in which case a staleness warning replaces that message instead;
  see [Commands](#commands) for the mechanics and threshold.
- **SessionStart on compaction specifically** additionally re-injects the
  full contents of `.local/TODO.md`, `PLAN.md`, `IMPLEMENTATION-PLAN.md`,
  and `TROUBLESHOOTING.md` as a "POST-COMPACTION RECOVERY" context block,
  since the lossy compaction summary can drop details those files still
  have on disk.
- **Every turn-end** is gated: a turn may end only in `Complete`, a
  needs-user state (`Blocked`, `Waiting For Decision`), or a parked
  `Awaiting *` state. `In Progress` / `Not Started` get nudged to keep
  going; an unrecognised `State:` value is blocked with the exact valid
  list so a near-miss self-corrects instead of being rationalised into a
  false `Complete`. In every one of those turn-end-permitting states, a
  freshness check additionally compares conversation activity against
  `.local/TODO.md`'s age: enough prompts since the docs were last touched
  blocks the turn-end once per session epoch until they're updated (or
  merely touched, which also satisfies it) — see [Commands](#commands).
  Every invocation past the gate appends a JSONL audit entry.
- **Follow-ups mentioned in conversation** — "worth filing later", a
  deferred product decision, a defect noticed but out of scope here — land
  in `.local/FOLLOWUPS.md`, lazily created from `templates/FOLLOWUPS.md` on
  first capture (no hook creates it ahead of need). One entry is appended
  per follow-up, each carrying a disposition `Status:` (`open` / `filed
  <ref>` / `resolved` / `dropped (<reason>)`); entries are never deleted,
  only dispositioned in place. Every open entry is surfaced at
  SessionStart in an "Open follow-ups" block until it's dispositioned, and
  a close-out gate blocks parking `State: Complete` while any follow-up
  entry is still open — once per session epoch, same marker scheme as the
  other nudges; see [Commands](#commands) for the mechanics and the
  `CLAM_FOLLOWUPS_GATE` escape hatch.
- **A prompt arriving into a parked session** (State in the manifest's
  `parked` category, e.g. `Awaiting User Review`) gets a one-time nudge
  reminding the agent that the park may be over: set `State: In Progress`
  and record the direction change before proceeding if this turn resumes
  substantive work, or leave the State standing if it's a mere
  acknowledgement.
- **Approaching auto-compaction**, a one-time nudge lists the `.local/`
  tracking docs to flush before the harness lossily summarises
  in-conversation state; immediately before an auto-compaction actually
  runs, `.local/TODO.md`/`PLAN.md`/`IMPLEMENTATION-PLAN.md`/
  `TROUBLESHOOTING.md`/`SUBAGENT-LOG-*.md` are snapshotted to
  `.local/snapshots/<timestamp>/` regardless — the deterministic backstop
  if the flush nudge went unheeded.
- **The built-in TaskCreate/TaskUpdate/TaskList/TaskGet tools are denied**
  unconditionally while the plugin is enabled: they write to
  `~/.claude/tasks/`, which the tracking docs, agent-dash, and the
  statusline never see. TeamCreate and the other team-coordination tools
  are not matched.
- **Every prompt containing `/make-progress`** is snapshotted (session
  state, transcript tail, git state, active crons) to
  `~/.claude/make-progress-captures/` for the skill below to consume.

## Common workflows

### Start tracked work

Create `.local/TODO.md` from `templates/TODO.md` (SessionStart auto-creates
it the moment `.local/` exists, or copy the template by hand). Set `State:`
as you go — `Not Started` → `In Progress` while working — and keep `Current
Task:` and the Implementation Log current in real time, not just at session
end: compaction can happen at any point, and state that lives only in
conversation is lost. Park unresolved conversation threads (a question
asked but never answered, a naming/design thread left hanging) in the
template's `## Open Questions` section as they come up, and remove each
entry once it's answered, recording the answer in the Implementation Log,
`PLAN.md`'s Changelog, or a decisions file.

### Resume after a restart, `/clear`, or compaction

Nothing to do manually — SessionStart surfaces `State:` and `Current Task:`
from `.local/TODO.md` on every session boundary, and a compaction
additionally re-injects the full contents of `.local/TODO.md`, `PLAN.md`,
`IMPLEMENTATION-PLAN.md`, and `TROUBLESHOOTING.md`. Read those before doing
anything else, and trust them over assumptions about a fresh start —
UNLESS SessionStart instead surfaces a staleness warning (the docs lag
prompts recorded in one of this worktree's other transcripts), in which
case read that transcript's tail first and reconcile the docs before
trusting them. If a session stopped when it should have kept going (a PR
merged, a subagent returned, a review posted, and nothing picked up the
next step), the user runs `/tracking:make-progress` to assess state and
take the next in-plan action.

### Park on a decision

Set `State: Waiting For Decision`, write the full analysis to
`.local/decisions/NNN-<slug>.md` (options, evidence, recommendation,
if-deferred path — the decision-log plugin's `/decision-log:rundown`
template if installed), and put the question, the recommended option, and
that file path in `Decision Needed:`. The Stop hook checks for this pairing
once per session epoch and blocks with instructions if it's missing —
recurring only once, so a genuine single yes/no confirmation isn't
re-blocked. End the turn with a user-facing message that restates the
decision in plain terms; the screen-bottom line is what the user sees
first.

### Capture and disposition follow-ups

The moment a follow-up surfaces in conversation — "worth filing later", a
separate decision, a defect noticed but not fixed here — append an entry to
`.local/FOLLOWUPS.md` in real time (create it from `templates/FOLLOWUPS.md`
on first capture; see [What to expect](#what-to-expect) for the entry
format). Every new entry starts `Status: open`, and SessionStart surfaces
every still-open entry at the start of each session until it's
dispositioned. Before parking `State: Complete`, the Stop hook's close-out
gate blocks once per session epoch while any entry remains open. Disposition
each one in place — edit its `Status:` line to `filed <issue-ref>`,
`resolved`, or `dropped (<reason>)` — never delete an entry, even a dropped
one.

`- Status: open` is a machine-read marker, matched literally (modulo trailing
whitespace) by `scripts/keep-working.sh`'s close-out gate and
`scripts/session-context.sh`'s open-follow-ups surfacing. Reword it and both
hooks stop seeing the entry — an open follow-up then silently reads as
dispositioned. Every other `Status:` value is a disposition and ends the
entry's open state.

## Commands

### Skills

- **`/tracking:make-progress`** — user-invoked only
  (`disable-model-invocation: true`; never auto-triggered, never called
  from crons or other skills). Run when a session stalled after a unit of
  work finished. It: (1) locates the capture directory the
  UserPromptSubmit capture hook wrote for this invocation (or falls back to
  `capture.sh --fallback` if the hook didn't fire), (2) assesses current
  state from `.local/TODO.md`, `.local/PLAN.md`, other `.local/` artifacts,
  `gh pr view`, and active watch crons, (3) applies an attended decision
  table (dispatch more lego blocks, run post-merge cleanup, route to
  feedback-addressing, re-request review, reschedule a missing PR-watch
  cron, resolve a park contradicted by PR reality, re-surface a correct
  stop, or report nothing-dispatchable), (4) records the decision as
  `DECISION.md` + `pr-state.json` in the capture directory before acting,
  (5) executes it under normal attended-workflow rules, and (6) appends an
  `## Outcome` section. It never invents work outside the approved plan,
  merges PRs, assigns new reviewers, promotes draft PRs, or bypasses an
  approval gate. Every invocation — including "no action" or "stop was
  correct" — is recorded as a labeled example for future automatic-trigger
  design.

### Hooks

- **SessionStart** (`scripts/session-context.sh`) — rules injection,
  TODO.md auto-create, and resume-context surfacing; see
  [What to expect](#what-to-expect). Resume surfacing cross-checks
  `.local/TODO.md`'s mtime against conversation activity recorded in this
  worktree's OTHER transcripts under `~/.claude/projects/` (the current
  session's own transcript is excluded): it sums `lib/activity.sh`'s
  `activity_prompts_since` over the newest 5 prior transcripts (newest by
  mtime), and when the total is at or above
  `CLAM_TRACKING_RESUME_STALE_THRESHOLD` (default `1`), the normal
  "resume from the docs" message is REPLACED by a staleness warning
  naming the last-updated time, the prompt count, the newest prior
  transcript's path, and an instruction to read that transcript's tail
  (~30 entries) and reconcile the docs before trusting them. Escape
  hatch: `CLAM_TRACKING_RESUME_STALE_GATE=disabled` (default `enabled`).
  Fail-open throughout, including this check: any error exits 0 with no
  output (or falls back to the plain resume message) rather than breaking
  session start. It also surfaces any open follow-up entries from
  `.local/FOLLOWUPS.md` (see [What to expect](#what-to-expect)) as a
  trailing "Open follow-ups" block, read-only and appended after the
  resume text.
- **SessionStart, `compact` matcher** (`scripts/post-compact-recovery.sh`)
  — re-injects the full contents of `.local/TODO.md`, `PLAN.md`,
  `IMPLEMENTATION-PLAN.md`, and `TROUBLESHOOTING.md` after a compaction,
  and drops a `.local/.flush-nudge-skip-next` marker so the flush-nudge
  hook doesn't misread stale pre-compaction token counts on the very next
  prompt. Fail-open.
- **Stop** (`scripts/keep-working.sh`) — enforces the state lifecycle
  described in [What to expect](#what-to-expect). Escape hatch:
  `CLAM_TRACKING_STOP_GATE=disabled` turns the hook off entirely.

  A freshness gate composes right after the plan gate below and in front
  of the state case, for every state that would otherwise permit ending
  the turn (all parked `Awaiting *` states, `Blocked`, `Waiting For
  Decision`, `Complete` — not `Not Started` / `In Progress`, which already
  block): when the count of human prompts in the current transcript since
  `.local/TODO.md`'s mtime (`lib/activity.sh`'s `activity_prompts_since`)
  is at or above `CLAM_TRACKING_FRESHNESS_THRESHOLD` (default `2`), the
  turn-end is blocked once per session epoch (marker
  `.local/.freshness-nudge-fired`, cleared at SessionStart) until the docs
  are updated — or merely touched, since any write to TODO.md moves its
  mtime and satisfies the gate on the re-stop. Escape hatch:
  `CLAM_TRACKING_FRESHNESS_GATE=disabled` (default `enabled`).

  A follow-ups close-out gate runs first within `State: Complete`, ahead of
  the two backstops below: once per session epoch (marker
  `.local/.followups-nudge-fired`, cleared at SessionStart), it blocks
  parking `Complete` while `.local/FOLLOWUPS.md` still has open entries,
  listing each by title and instructing that it be dispositioned (`filed
  <ref>` / `resolved` / `dropped (<reason>)`) — or the State moved off
  `Complete` if the work genuinely isn't done. Escape hatch:
  `CLAM_FOLLOWUPS_GATE=disabled` (default `enabled`).

  Two further backstops compose on top of the state check:
  - `CLAM_PR_CRONS=enabled` (default `disabled`) blocks parking on
    `Complete` or any of the five PR-watched `Awaiting *` states when the
    branch has an open PR with no matching entry in
    `.claude/scheduled_tasks.json` — needs the pr-workflow plugin's
    create-pr skill to have scheduled the watch cron. Opt-in here, unlike
    clam-code where unset meant enabled.
  - `CLAM_INDEPENDENT_REVIEW=enabled` (default `disabled`) blocks the
    human-handoff states (`Awaiting Reviewer Assignment`, `Awaiting Human
    Review`, `Awaiting Merge Queue`, `Complete`) when the branch has an
    open PR with no `.local/INDEPENDENT-REVIEW-PR-<N>.md` report — needs
    the independent-review skill.

  A `Waiting For Decision` park without a `.local/decisions/` file
  reference and an open (`Status: Open`) decision file is blocked once per
  session epoch with instructions, then allowed (marker
  `.local/.decision-nudge-fired`). A `.local/PLAN.md` lacking a `##
  Block Design` heading blocks every turn-end, with no epoch marker, until
  the heading is added. A generic backstop blocks once per epoch
  (`.local/.no-todo-nudge-fired`) when `.local/` has uncommitted changes or
  commits ahead of `master` but no `.local/TODO.md` at all. Every
  invocation past the top-level gate appends a JSONL entry to
  `CLAUDE_STOP_LOG` (default `~/.claude/stop-log.jsonl`) recording the
  disposition, best-effort and silent on failure.
- **Stop and UserPromptSubmit** (`scripts/awaiting-user.sh`) — writes
  `.local/.awaiting-user` on Stop and removes it on the next
  UserPromptSubmit, so other consumers (notifications' summons-epoch
  semantics) can tell whether a session is currently waiting on the user.
  When a prompt arrives while the marker is present (the previous turn
  genuinely ended and this prompt reopens the session) AND the recorded
  `State:` is in the manifest's `parked` category, it injects a one-time
  unpark nudge into conversation context before removing the marker: a
  reminder to set `State: In Progress` and record the direction change
  (what the user asked, any pivot from the recorded plan) if this turn
  resumes substantive work, or to leave the State standing for a mere
  acknowledgement. Never fires for `Blocked` / `Waiting For Decision`
  (needs-user, not parked) or the active states. Escape hatch:
  `CLAM_TRACKING_UNPARK_NUDGE=disabled` (default `enabled`). Silent-exits
  on any failure.
- **UserPromptSubmit** (`scripts/capture.sh`) — when the prompt contains
  `/make-progress`, snapshots session state (transcript tail, `.local/`
  files, git state, active crons) to a timestamped directory under
  `MAKE_PROGRESS_CAPTURE_ROOT` for the make-progress skill to read. A
  duplicate fire for the same session within `MAKE_PROGRESS_DEDUPE_SECS`
  is skipped so the first, pristine snapshot is the one the skill labels.
  Non-matching prompts cost one `jq` parse and no filesystem writes. Never
  fails and never writes to stdout (UserPromptSubmit stdout becomes
  conversation context).
- **UserPromptSubmit** (`scripts/flush-nudge.sh`) — when `.local/TODO.md`
  exists and context fill (summed from the transcript's last assistant
  usage block) crosses `CLAM_FLUSH_NUDGE_THRESHOLD` percent of the
  compaction window, injects a one-time-per-epoch nudge listing the
  `.local/` docs to flush before auto-compaction discards
  in-conversation state. The window is resolved in order:
  `CLAM_FLUSH_CONTEXT_WINDOW` (test override) →
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (process env) →
  `~/.claude/settings.json`'s `.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW` → a
  built-in default of `200000` tokens when all three are unset, so metering
  always has a window instead of silently never firing on an unconfigured
  machine. Escape hatch: `CLAM_TRACKING_FLUSH_GATE=disabled`.
- **PreCompact, `auto` matcher** (`scripts/precompact-snapshot.sh`) — on
  auto-compaction only (not manual `/compact`), copies `.local/TODO.md`,
  `PLAN.md`, `IMPLEMENTATION-PLAN.md`, `TROUBLESHOOTING.md`, and any
  `SUBAGENT-LOG-*.md` to `.local/snapshots/<YYYYMMDD-HHMMSS>/`, and appends
  an HTML-comment marker recording the snapshot path to `TODO.md`. This is
  the deterministic backstop when the flush nudge above went unheeded;
  never blocks compaction on failure.
- **PreToolUse**, matcher `TaskCreate|TaskUpdate|TaskList|TaskGet`
  (`scripts/block-task-tools.sh`) — denies the built-in task tools
  unconditionally while enabled; see [What to expect](#what-to-expect).
  Escape hatch: `CLAM_TRACKING_TASK_TOOLS_GATE=disabled` at launch (hooks
  do not see mid-session exports).

### Library files

- **`lib/states.tsv`** is the canonical State manifest (13 states; name,
  category, emoji, colour, summons). It is the single source of truth —
  the statusline and notifications plugins each carry a vendored copy that
  must stay in lockstep with it.
- **`lib/states.sh`** holds the shared readers sourced by the hooks above:
  `todo_field` (bold-tolerant `State:`/`**State:**` field extraction),
  `state_category`, `state_is_parked`, `state_summons`, `state_emoji`,
  `state_color`, `state_parked_list`, `state_names`. `notify.sh` in the
  notifications plugin carries a byte-identical twin of `todo_field`
  (`_clam_todo_field`) since it sources into an interactive shell where
  this lib's path resolution doesn't apply.
- **`lib/activity.sh`** holds two pure, read-only conversation-activity
  readers used by the Stop-hook freshness gate and the SessionStart
  resume-staleness check: `activity_prompts_since <ref_epoch>
  <transcript_path>` counts human prompts (real user turns, excluding
  tool-result / meta / machine-generated entries such as command echoes
  or hook feedback) strictly newer than `ref_epoch` in one transcript;
  `activity_prior_transcripts <cwd> [exclude_path]` lists a worktree's
  other transcript files under `~/.claude/projects/`, newest first by
  mtime. Requires `jq`; fails open (prints `0` / no output) on any
  missing input, unreadable file, or absent `jq`.
- **`lib/platform.sh`** — OS-detection helpers (`clam_os`,
  `clam_mtime_epoch`, `clam_birth_epoch`, `clam_managed_settings_path`,
  `clam_pkg_hint`). `clam_birth_epoch` backs `capture.sh`'s
  duplicate-fire dedupe (needs a directory's creation time);
  `clam_mtime_epoch` backs the freshness gate (`keep-working.sh`) and the
  resume-staleness check (`session-context.sh`), both of which read
  `.local/TODO.md`'s modification time.
- **`templates/TODO.md`** is the tracking-doc skeleton copied by
  `session-context.sh`'s auto-create and referenced by the injected Work
  Management rules. Its `## Open Questions` section (between
  Blockers/Notes and Discovered Tasks) gives unresolved conversation
  threads a durable, structured home; existing worktrees' TODO.md files
  are not migrated — the section applies only to newly instantiated
  templates (auto-create and manual copies).
- **`templates/FOLLOWUPS.md`** is the reference/template for
  `.local/FOLLOWUPS.md`, instantiated by hand (or by the agent, per the
  injected rules) on first capture — unlike `templates/TODO.md`, no hook
  auto-creates it. Documents the entry format (`## F<NN> — <title>` plus
  `Status:`/`Captured:`/`Source:`/`Refs:`/`Statement:` fields) that
  `session-context.sh`'s surfacing and `keep-working.sh`'s close-out gate
  both parse.

### Env var summary

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAM_TRACKING_STOP_GATE` | `enabled` | `disabled` turns off the Stop-hook state-lifecycle enforcement entirely. |
| `CLAM_TRACKING_FRESHNESS_GATE` | `enabled` | `disabled` turns off the Stop-hook freshness-drift gate. |
| `CLAM_TRACKING_FRESHNESS_THRESHOLD` | `2` | Human prompts since `.local/TODO.md`'s mtime, in the current transcript, at or above which the freshness gate blocks a turn-end-permitting state once per session epoch. |
| `CLAM_FOLLOWUPS_GATE` | `enabled` | Any other value disables the Stop-hook follow-ups close-out gate that blocks parking `Complete` while `.local/FOLLOWUPS.md` has open entries. |
| `CLAM_TRACKING_TASK_TOOLS_GATE` | `enabled` | `disabled` turns off the built-in task-tools deny. |
| `CLAM_PR_CRONS` | `disabled` | `enabled` blocks parking/completing with an open PR that has no monitoring cron (needs the pr-workflow plugin's create-pr watch crons; opt-in here, unlike clam-code where unset meant enabled). |
| `CLAM_INDEPENDENT_REVIEW` | `disabled` | `enabled` blocks human-handoff states without an independent-review report (needs the independent-review skill). |
| `CLAUDE_STOP_LOG` | `~/.claude/stop-log.jsonl` | Stop-hook audit log location. |
| `CLAM_TRACKING_UNPARK_NUDGE` | `enabled` | `disabled` turns off the nudge injected when a prompt arrives into a parked session. |
| `CLAM_TRACKING_RESUME_STALE_GATE` | `enabled` | `disabled` turns off the SessionStart resume-staleness warning. |
| `CLAM_TRACKING_RESUME_STALE_THRESHOLD` | `1` | Prior-transcript human prompts newer than `.local/TODO.md`'s mtime, summed over the newest 5 prior transcripts, at or above which resume surfaces the staleness warning instead of the plain resume message. |
| `CLAM_TRACKING_FLUSH_GATE` | `enabled` | `disabled` turns off the pre-compaction flush nudge. |
| `CLAM_FLUSH_NUDGE_THRESHOLD` | `75` | Context-fill percentage (of the compaction window) that triggers the flush nudge. |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | *(from `~/.claude/settings.json`; `200000` if that's unset too)* | Compaction window in tokens the flush nudge meters fill against. |
| `CLAM_FLUSH_CONTEXT_WINDOW` | unset | Test-only override that takes precedence over `CLAUDE_CODE_AUTO_COMPACT_WINDOW` and `settings.json` for metering the flush nudge. |
| `MAKE_PROGRESS_CAPTURE_ROOT` | `~/.claude/make-progress-captures` | Where `capture.sh` writes snapshot directories. |
| `MAKE_PROGRESS_TAIL_MAX_BYTES` | `204800` | Size cap for `capture.sh`'s captured transcript tail. |
| `MAKE_PROGRESS_PROMPT_MAX_BYTES` | `65536` | Size cap for `capture.sh`'s captured `prompt.txt`. |
| `MAKE_PROGRESS_DEDUPE_SECS` | `60` | `capture.sh`'s duplicate-fire dedupe window. |

The last four are documented in `capture.sh` as overrides for its own test
suite; they work as real overrides but are not expected to need changing
in normal use.

Any of these may be set by hand in the `env` block of the settings file at
the scope where the plugin is installed — no setup command writes them.

## Relationships to other plugins

No hard dependencies — tracking is fully standalone, and every hook above
still functions (or fails open) with none of the following installed.

Soft integrations, all optional, everything degrading gracefully when
absent:

- **decision-log plugin** — `Waiting For Decision` parks expect a
  `.local/decisions/NNN-<slug>.md` file, ideally written via
  `/decision-log:rundown`.
- **notifications plugin** — bell, desktop notification, tmux highlight,
  and phone push on summoning transitions (`Awaiting User Review`,
  `Blocked`, `Waiting For Decision`); its idle-event backstop delivers the
  push even when the `notify` shell helper is not installed. It also
  vendors a copy of `lib/states.tsv`/`states.sh`, so its notify logic
  tracks this plugin's State manifest.
- **statusline plugin** — vendors the same `lib/states.tsv`/`states.sh` to
  show the State segment.
- **agent-dash** (external) — reads the same `.local/` files for its
  dashboard.
- **pr-workflow plugin's create-pr skill** — schedules the watch crons
  that the `CLAM_PR_CRONS` Stop-hook backstop checks for.
- **independent-review skill** — produces the
  `.local/INDEPENDENT-REVIEW-PR-<N>.md` report the `CLAM_INDEPENDENT_REVIEW`
  Stop-hook backstop checks for.

What tracking provides to others: `.local/TODO.md` and the rest of the
`.local/` tracking docs as the stable file-based interface consumed by
agent-dash and the statusline; `lib/states.tsv` as the canonical State
manifest vendored by statusline and notifications.

## Uninstalling

```
/plugin uninstall tracking@clam
```

`.local/TODO.md`, `.local/PLAN.md`, `.local/decisions/`,
`.local/snapshots/`, `~/.claude/make-progress-captures/`, and
`~/.claude/stop-log.jsonl` are not removed — they are ordinary state,
capture, and log files outside the plugin's own directory. Any of the env
vars from the summary table set by hand in a settings file's `env` block
are no longer read once the plugin is disabled, but are harmless to leave
in place.
