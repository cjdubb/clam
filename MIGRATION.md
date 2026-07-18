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
  `issue-tracker` (keeps its jira/github/none provider seam and `CLAM_*` knobs)
- Docs: `skills/PR-WORKFLOW.md`
- Agents: `reviewer`
- Hooks: `pr-status.sh` (Stop)

## session-modes — planned

- Skills: `start`, `orient`, `sitrep`, `role-check`, `make-progress`,
  `whats-cooking`, `planning`, `orchestrator-handover`
- Hooks: `session-start.sh` (grows into the workflow-rules injection that
  replaces the `clam` alias — content sourced from `general/system-prompt.md`),
  `keep-working.sh`, `awaiting-user.sh`, `flush-nudge.sh`,
  `capture-make-progress.sh`, `prompt-timestamp.sh`,
  `capture-permission-mode.sh`, `post-compact.sh`, `precompact-snapshot.sh`

## decision-log — planned

- Skills: `decision-log`, `decision-log-interactive`, `decision-rundown`,
  `doc-sync`

## team-review — planned

- Skills: `team-code-review`, `team-council`, `team-exploration`,
  `independent-review`, `independence-protocol`, `subagent-orchestration`
- Agents: `Explore`, `browser`

## worktrees — planned

- Skills: `creating-worktrees`, `parallel-branch-work`
- Scripts: `general/todo-worktree.sh`

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
- `general/statusline/` (ccost, context, prices)
- `setup.sh`, `update.sh`, `cleanup.sh`, `cleanup-legacy.sh`,
  `setup-git-repo-with-trees.sh`, `claude-rules*.sh`
- `general/lib/` shell helpers (ported piecemeal only if a hook needs one)
- `general/CLAUDE.md` universal rules (global, user-managed)
