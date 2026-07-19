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
- Hooks: `pr-status.sh` (Stop)

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
  `capture-make-progress.sh`, `prompt-timestamp.sh`,
  `capture-permission-mode.sh`, `post-compact.sh`, `precompact-snapshot.sh`
- (`keep-working.sh` and `awaiting-user.sh` moved to **tracking**)

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

## worktrees — ported (fresh-written)

Skills `usage` and `per-worker` are fresh-written against current
git-helpers, not ported from clam-code's `creating-worktrees` and
`parallel-branch-work` skills — those had gone stale relative to the
current `newtree`/`rmtree`/`copyenv`/`cloneBareRepo` shell functions.

`general/todo-worktree.sh` was deliberately **not** ported: it depends on
clam-code session tooling this repo doesn't have yet. Revisit it alongside
the tracking plugin.

## guards — planned

- Hooks: `git-guard.sh`, `cron-guard.sh`, `block-task-tools.sh`,
  `permission-audit.sh`, `notify.sh`, `push-notify.sh`, `stop-notify.sh`,
  `log-skill-trigger.sh`

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

## Out of scope — stays in clam-code / dotfiles

Elements plugins cannot express. Per the SessionStart-injection decision these
are not carried into this repo:

- `general/system-prompt.md` + `claude-alias.sh` / `claude-alias.fish` — the
  `clam` alias; its *content* migrates into session-modes' SessionStart hook,
  the alias mechanism itself dies
- `general/clam-settings.json` sidecar, `global-settings-bundle.json`,
  `managed-settings-setup.sh`, `managed-version-lock.json`
- `setup.sh`, `update.sh`, `cleanup.sh`, `cleanup-legacy.sh`,
  `setup-git-repo-with-trees.sh`, `claude-rules*.sh`
- `general/lib/` shell helpers (ported piecemeal only if a hook needs one)
- `general/CLAUDE.md` universal rules (global, user-managed)
