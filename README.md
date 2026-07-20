# clam

A Claude Code plugin marketplace: the workflows from previous clam iterations
([clam-code](https://github.com/cjdubb/clam-code), clam-v2), converted into
independently installable plugins.

**Design constraint:** installing any plugin here changes nothing globally — no
writes to `~/.claude/CLAUDE.md` or global settings beyond Claude Code's own
plugin-enablement entry. Behaviour that used to be injected via the `clam`
shell alias and `--append-system-prompt-file` is delivered through SessionStart
hooks instead. Plain `claude` in a repo without these plugins enabled is
untouched.

## Install

```
/plugin marketplace add cjdubb/clam
/plugin install lego@clam
```

Enable per repo (or per machine) — take only the clusters you want.

## Update

```
/plugin marketplace update clam        # re-fetch this repo, refresh the catalog
claude plugin update <plugin>@clam     # update one installed plugin (CLI only — no /plugin update)
```

Auto-update is **off by default** for third-party marketplaces like this one.
Turn it on per marketplace under `/plugin` → Marketplaces → clam →
Enable auto-update; Claude Code then checks shortly after session startup and
applies updates on the next launch (it prompts `/reload-plugins` when
something updated). With auto-update off, `/plugin marketplace update clam`
is the manual refresh; it also updates installed plugins when auto-update is
enabled for the marketplace, otherwise follow it with `claude plugin update`.

## Plugins

| Plugin | Status | What it does |
|--------|--------|--------------|
| [lego](plugins/lego/) | ✅ v0.4.0 | Contract-first planning, scaffolded stubs, realm-restricted test and implementation agent waves. Ported from clam-v2. |
| pr-workflow | planned | PR lifecycle: create, review, address feedback, author checklist, pre-PR verify, doc-sync gate, retrospective, reviewer agent, issue-tracker seam. |
| session-modes | planned | Session workflow modes (`/start`, orient, sitrep, make-progress, …) plus the session-lifecycle hooks and the SessionStart workflow-rules injection that replaces the old `clam` alias. |
| [decision-log](plugins/decision-log/) | ✅ v0.1.0 | Decision Logs: `/decision-log:create`, `/decision-log:interactive`, `/decision-log:rundown`. Ported from clam-code. |
| [tracking](plugins/tracking/) | ✅ v0.1.0 | Tracking documents: `.local/TODO.md` as session state of record, 13-state lifecycle with Stop-hook enforcement, resume after `/clear` via SessionStart injection. Powers agent-dash and the statusline State segment. |
| [statusline](plugins/statusline/) | ✅ v0.1.0 | Statusline: context usage, session/day/week cost, effort, tracking State. One explicit global write via `/statusline:setup`. |
| [landing](plugins/landing/) | ✅ v0.1.0 | The landing seam: `/landing:land` lands finished work per the repo's committed policy in `.claude/clam-profile.md` (github-pr or local-merge); `/landing:init` detects and records it. |
| team-review | planned | Multi-agent review and exploration: team code review, council, independent review, subagent orchestration; Explore and browser agents. |
| worktrees | planned | Worktree creation and parallel branch work. |
| guards | planned | Safety hooks: git guard, cron guard, permission audit, notifications. |
| agent-dash | planned | Hooks integrating sessions with [clam-agent-dashboard](https://github.com/cjdubb/clam-agent-dashboard). |

See [MIGRATION.md](MIGRATION.md) for the full element-by-element mapping from
clam-code, including what is deliberately left behind.

## Repo conventions

- Each plugin lives in `plugins/<name>/` with its own
  `.claude-plugin/plugin.json`, `skills/`, `agents/`, `hooks/`, `scripts/`.
- Skill names avoid repeating the plugin name: the invocation is
  `/lego:plan`, not `/lego:lego-plan`.
- A plugin is added to `.claude-plugin/marketplace.json` only once it is
  ported and working — the marketplace never lists empty shells.
