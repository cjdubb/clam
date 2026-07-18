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

## Plugins

| Plugin | Status | What it does |
|--------|--------|--------------|
| [lego](plugins/lego/) | ✅ v0.4.0 | Contract-first planning, scaffolded stubs, realm-restricted test and implementation agent waves. Ported from clam-v2. |
| pr-workflow | planned | PR lifecycle: create, review, address feedback, author checklist, pre-PR verify, retrospective, reviewer agent, issue-tracker seam. |
| session-modes | planned | Session workflow modes (`/start`, orient, sitrep, make-progress, …) plus the session-lifecycle hooks and the SessionStart workflow-rules injection that replaces the old `clam` alias. |
| decision-log | planned | Decision logging: capture, interactive capture, rundown, doc-sync. |
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
