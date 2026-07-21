# Migration map: clam-code / clam-v2 → clam plugins

Tracks where every element of the previous iterations lands. Statuses:
**ported** (in this repo, listed in the marketplace), **planned** (assigned a
plugin, not yet ported), **out of scope** (deliberately left behind),
**dropped** (superseded).

Hook assignments are best-effort from clam-code's `general/hooks/README.md`;
confirm each hook's wiring and dependencies at port time.

## lego — ported (from clam-v2)

Skills renamed to drop the redundant prefix: `lego-plan` → `/lego:plan`,
`lego-scaffold` → `/lego:scaffold`, `lego-dispatch` → `/lego:dispatch`.
Agents (`lego-test-writer`, `lego-implementer`), realm scripts, hooks,
templates, and docs ported unchanged. clam-v2's repo and marketplace retire;
this is the canonical home.

The v1 lego agents in clam-code (`lego-builder`, `lego-stub-builder`,
`lego-test-writer`) and the `lego-dispatch-guard.sh` hook are **dropped** —
superseded by this plugin.

## pr-workflow — planned

- Skills: `create-pr`, `address-pr-feedback`, `get-pr-comments`,
  `find-reviewer`, `pr-author-checklist`, `pre-pr-verify`, `pr-retrospective`,
  `pr-review`, `pr-review-perfect`, `pr-status`, `status-sync`,
  `issue-tracker` (keeps its jira/github/none provider seam and `CLAM_*` knobs),
  `doc-sync` (pre-PR documentation-accuracy gate; reassigned from decision-log)
- Docs: `skills/PR-WORKFLOW.md`
- Agents: `reviewer`
- Hooks: `pr-status.sh` (Stop), `log-skill-trigger.sh` (PreToolUse +
  PostToolUse on Skill; reassigned from the dissolved guards cluster — its
  only consumer is `pr-retrospective`. Generic telemetry: split into its own
  plugin if a second consumer appears)
- When ported, `create-pr` also becomes the delegated github-pr provider
  behind `/landing:land` (see **landing**), and `pre-pr-verify` should be
  reconciled with the profile's `landing-verify` command.

## landing — new (not a port)

No clam-code ancestor; born 2026-07-20 from the "generic config across repo
variances" work. Owns the landing seam: a repo-committed policy file
(`.claude/clam-profile.md`, flat namespaced frontmatter keys shared with
future seams) plus the generic `/landing:land` verb with `github-pr` and
`local-merge` strategies, `/landing:init` policy setup, and a SessionStart
policy injection.

Couplings to honor at later ports:

- **pr-workflow**: `create-pr` slots in behind the github-pr strategy (the
  delegation seam is already written into the land skill).
- **worktrees**: the local-merge strategy locates target checkouts and can
  remove work worktrees — keep conventions aligned when that plugin lands.
- **issue-tracker** (inside pr-workflow): its jira/github/none provider knob
  is the natural second resident of the profile file — namespaced keys in
  `.claude/clam-profile.md`, not a new file.

## tracking — ported (from clam-code)

The tracking-document approach, carved out of what was originally mapped
across session-modes and agent-dash: `.local/TODO.md` as session state of
record, the 13-state lifecycle, Stop-hook enforcement, and resume-after-/clear.

- Templates: `TODO-TEMPLATE.md` → `templates/TODO.md`
- Lib: `general/lib/states.sh` + `states.tsv` (canonical home; statusline
  plugin vendors a copy)
- Hooks: `keep-working.sh` (Stop), `awaiting-user.sh` (Stop +
  UserPromptSubmit), new `session-context.sh` (SessionStart) carrying the
  system-prompt Work Management rules + resume pointer + epoch-marker resets
  (the marker-clearing duties of `session-track.sh`/`post-compact.sh`)

Port changes: the `CLAM_SESSION` alias gate became
`CLAM_TRACKING_STOP_GATE` (default enabled; plugin enablement is the opt-in);
**`CLAM_PR_CRONS` unset now means disabled** (clam-code: enabled) — export
`CLAM_PR_CRONS=enabled` to keep the PR-cron backstop; decision-file nudge text
points at `/decision-log:rundown`; `notify` calls are conditional on the
helper existing.

Tracking v0.2.0 adds `block-task-tools.sh` (PreToolUse deny on
TaskCreate/TaskUpdate/TaskList/TaskGet; reassigned from the dissolved guards
cluster) — the enforcement leg of ".local/TODO.md is the state of record",
same rationale as `keep-working.sh`. Port change: gated behind
`CLAM_TRACKING_TASK_TOOLS_GATE` (default enabled).

## statusline — ported (from clam-code)

Reassigned from the out-of-scope list: plugins cannot set `statusLine` (no
manifest field; `${CLAUDE_PLUGIN_ROOT}` doesn't resolve in settings.json), so
the plugin ships the scripts plus an explicit `/statusline:setup` skill that
performs the one settings.json write at the user's request — the
install-changes-nothing constraint holds.

- Scripts: `general/statusline/{context.sh,ccost.sh,prices.json}` + both test
  suites
- Lib: `lib/platform.sh` vendored; `states.sh`/`states.tsv` vendored copy
  (canonical in tracking — keep in lockstep)

## session-modes — planned

- Skills: `start`, `orient`, `sitrep`, `role-check`, `make-progress`,
  `whats-cooking`, `planning`, `orchestrator-handover`
- Hooks: `session-start.sh` (grows into the workflow-rules injection that
  replaces the `clam` alias — content sourced from `general/system-prompt.md`;
  the Work Management section is already carried by the tracking plugin's
  injection, so session-modes must not duplicate it), `flush-nudge.sh`,
  `capture-make-progress.sh`, `post-compact.sh`, `precompact-snapshot.sh`
- (`keep-working.sh` and `awaiting-user.sh` moved to **tracking**;
  `prompt-timestamp.sh` and `capture-permission-mode.sh` moved to
  **notifications**, their consumers)

## decision-log — ported (from clam-code)

Skills renamed: `decision-log` → `/decision-log:create`,
`decision-log-interactive` → `/decision-log:interactive`, `decision-rundown` →
`/decision-log:rundown`. Soft dependencies (issue-tracker, render-doc,
team-council) degrade gracefully when the providing plugin/skill is absent.

`doc-sync` was originally mapped here but its content is a pre-PR verification
gate (slots into the `pre-pr-verify` sequence, blocks `create-pr`) — it moved
to **pr-workflow**.

Port-time notes for later plugins:

- clam-code's `general/system-prompt.md` references `/decision-rundown` and
  the `decision-rundown` template by name — the session-modes port must update
  those to `/decision-log:rundown`.
- The rundown skill's HTML-render gate still points at clam-code's
  `~/.claude/skills/render-doc/`; re-point it when render-doc gets a plugin
  home.

## team-review — planned

- Skills: `team-code-review`, `team-council`, `team-exploration`,
  `independent-review`, `independence-protocol`, `subagent-orchestration`
- Agents: `Explore`, `browser`
- Hooks: `orchestrator-guard.sh` (PreToolUse on Edit|Write|NotebookEdit;
  previously unmapped — the enforcement leg of `subagent-orchestration`'s
  "the orchestrator never implements" rule)

## worktrees — ported (fresh-written)

Skills `usage` and `per-worker` are fresh-written against current
git-helpers, not ported from clam-code's `creating-worktrees` and
`parallel-branch-work` skills — those had gone stale relative to the
current `newtree`/`rmtree`/`copyenv`/`cloneBareRepo` shell functions.

`general/todo-worktree.sh` was deliberately **not** ported: it depends on
clam-code session tooling this repo doesn't have yet. Revisit it alongside
the tracking plugin.

## notifications — ported (from clam-code)

The summoning stack, carved out of the dissolved guards cluster: the hooks
that turn tracking's summoning states into bells, desktop notifications, and
phone pushes.

- Hooks: `notify.sh` (Notification: bell + desktop + tmux tint, suppressed
  for parked non-summoning states), `push-notify.sh` (Notification: ntfy
  phone push; permission prompts always page, idle events page only in
  summoning states), `stop-notify.sh` (Stop: rings once on the transition
  into a summoning state), `prompt-timestamp.sh` (UserPromptSubmit; moved
  from session-modes — `stop-notify.sh` is its sole consumer: elapsed-turn
  timer + summons-epoch reset), `capture-permission-mode.sh`
  (UserPromptSubmit; also moved from session-modes — `push-notify.sh`'s
  plan-mode suppression is its real consumer; agent-dash reads the file too)
- Lib: `desktop-notify.sh` and `notify.sh` + their test suites; vendored
  `states.sh`/`states.tsv` copy (canonical in tracking — keep in lockstep)
- Tests: `push-notify.test.sh`, `stop-notify.test.sh`

Port changes: every hook is gated behind `CLAM_NOTIFICATIONS_GATE` (default
enabled; plugin enablement is the opt-in). The agent-side `notify()` shell
function cannot be injected by a plugin: pushes fall back to the 60s
idle-event backstop (state-gated in `push-notify.sh`), and the README
documents sourcing `lib/notify.sh` into the interactive shell for instant
pushes.

## permissions — planned

The audit-then-allowlist loop: a guard that observes plus skills that act on
the corpus.

- Hooks: `permission-audit.sh` (PermissionRequest; appends every prompted
  tool/command to `~/.claude/permission-audit.log`)
- Skills: `analyze-permissions.sh` promoted from an unwired CLI helper
  (previously unmapped) to `/permissions:analyze`
- Gap: clam-code's docs reference a `fewer-permission-prompts` skill that was
  never built. Decide at port time whether to build it here or drop the
  references.

## git-guard — planned

Single guard. Hard-blocks force-push when the PR carries a non-author human
review; soft-warns on `git add -A`/`--all`/`.`. Kept standalone rather than
folded into pr-workflow: the staging warn is generic and the safety rails are
useful without the PR machinery.

- Hooks: `git-guard.sh` (PreToolUse on Bash) + `git-guard.test.sh`
- Knob shared with pr-workflow: `CLAM_AUTO_REVIEWER` names the bot reviewer
  exempt from the force-push block — document in both places.

## cron-guard — planned

Single guard. Caps active crons per session and keeps the audit ledger.

- Hooks: `cron-guard.sh` (PreToolUse on CronCreate + PostToolUse on
  CronCreate/CronDelete) + `cron-guard.test.sh`
- Knobs and couplings to document at port time: `CLAM_CRON_CAP` (default 6,
  sized for pr-workflow's park-scoped watch stacking); `.local/.cron-count`
  mirror read by agent-dash (soft dependency); ledger at
  `~/.claude/cron-audit.log`.

## Guard inventory

Every guard-type hook in clam-code and where it is tracked. Being tracked
here does not commit to porting it; any row can still move to out of scope or
dropped.

| Guard | Destination | Status |
|-------|-------------|--------|
| `notify.sh`, `push-notify.sh`, `stop-notify.sh` (+ `prompt-timestamp.sh` and `capture-permission-mode.sh`, moved from session-modes) | notifications | ported |
| `permission-audit.sh` (+ unwired `analyze-permissions.sh`) | permissions | planned |
| `git-guard.sh` | git-guard | planned |
| `cron-guard.sh` | cron-guard | planned |
| `block-task-tools.sh` | tracking | ported |
| `log-skill-trigger.sh` | pr-workflow | planned |
| `orchestrator-guard.sh` | team-review | planned |
| `keep-working.sh` | tracking | ported |
| realm gate (`realm-gate.sh` + `realm-check.sh`) | lego | ported |
| `lego-dispatch-guard.sh` | — (superseded by lego) | dropped |

## agent-dash — planned

Integration with clam-agent-dashboard.

- Hooks: `agent-dash-permission.sh`, `session-track.sh`, `git-sync.sh`
  (verify: several session-modes hooks also touch agent-dash state files —
  untangle the coupling or accept a soft dependency between the two plugins)

## Unassigned — decide at port time

- `support-fix`, `support-triage` (support cluster — own plugin or fold into
  pr-workflow)
- `writing-markdown`, `render-doc`, `rtfm` (writing cluster)
- `debug-playwright-tests` (tech-specific; maybe stays a repo-local skill)
- `orient`-adjacent statusline data? (see statusline note below)

## attribution — ported (new plugin)

Not a direct port of a clam-code file; implements the `attribution`
settings key that was previously set via `clam-settings.json`. Ships as a
scope-aware `/attribution:setup` skill following the statusline pattern:
install changes nothing, the explicit skill writes `attribution:
{"commit":"","pr":""}` to the settings file matching the plugin's
installation scope (user, project, or local).

## settings — ported (new plugin)

Catch-all for opinionated session defaults that don't warrant their own
plugin. Currently carries two env vars from `clam-settings.json`:
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` and
`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`. Same scope-aware
`/settings:setup` pattern.

## privacy — ported (new plugin)

Consolidates all telemetry and feedback opt-out settings from
`global-settings-bundle.json`: five env vars
(`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_TELEMETRY`,
`DISABLE_ERROR_REPORTING`, `DISABLE_FEEDBACK_COMMAND`,
`CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY`) plus `feedbackSurveyRate: 0`. Same
scope-aware `/privacy:setup` pattern.

## Out of scope — stays in clam-code / dotfiles

Elements plugins cannot express, or that remain personal tuning:

- `general/system-prompt.md` + `claude-alias.sh` / `claude-alias.fish` — the
  `clam` alias; its *content* migrates into session-modes' SessionStart hook,
  the alias mechanism itself dies
- `general/clam-settings.json` sidecar (hooks, permissions, skill overrides,
  bash timeouts, skill listing budget — elements already migrated to other
  plugins or personal tuning), `managed-settings-setup.sh`,
  `managed-version-lock.json`
- `global-settings-bundle.json` (permission deny list migrates to the planned
  permissions plugin; telemetry settings now in the privacy plugin;
  `defaultExecutionMode` migrates to the planned session-modes plugin)
- `setup.sh`, `update.sh`, `cleanup.sh`, `cleanup-legacy.sh`,
  `setup-git-repo-with-trees.sh`, `claude-rules*.sh`
- `general/lib/` shell helpers (ported piecemeal only if a hook needs one)
- `general/CLAUDE.md` universal rules (global, user-managed)
