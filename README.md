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
| [landing](plugins/landing/) | ✅ v0.1.0 | The landing seam: `/landing:land` lands finished work per the repo's committed policy in `.claude/clam-profile.jsonc` (github-pr or local-merge); `/landing:init` detects and records it. |
| [orchestrator-handover](plugins/orchestrator-handover/) | ✅ v0.1.0 | Orchestrator-to-orchestrator handover: `/orchestrator-handover:create` writes a handover document, scaffolds the recipient worktree, populates its `.local/`, and hands off to the user. |
| team-review | planned | Multi-agent review and exploration: team code review, council, independent review, subagent orchestration; Explore and browser agents. |
| [worktrees](plugins/worktrees/) | ✅ v0.1.0 | Git worktree workflow on top of git-helpers (`newtree`, `rmtree`, `copyenv`, `cloneBareRepo`), plus the worktree-per-worker pattern for parallel agents. |
| [attribution](plugins/attribution/) | ✅ v0.1.0 | Suppress co-author attribution on commits and PRs. One explicit write via `/attribution:setup`. |
| [settings](plugins/settings/) | ✅ v0.1.0 | Agent teams and disabled adaptive thinking. One explicit write via `/settings:setup`. |
| [privacy](plugins/privacy/) | ✅ v0.1.0 | Opt out of telemetry, error reporting, feedback surveys, and non-essential traffic. One explicit write via `/privacy:setup`. |
| guards | planned | Safety hooks: git guard, cron guard, permission audit, notifications. |
| agent-dash | planned | Hooks integrating sessions with [clam-agent-dashboard](https://github.com/cjdubb/clam-agent-dashboard). |
| [deliver](plugins/deliver/) | ✅ v0.1.0 | High-level software delivery framework: composites landing, lego, and tracking into a cohesive delivery lifecycle. Provides PR description sync and delivery workflow context. |
| [render-doc](plugins/render-doc/) | ✅ v0.1.0 | Renders a markdown document into a self-contained HTML view via `/render-doc:render <file>`, with an annotation server that writes feedback back into the source markdown. Ported from clam-code. |
| [ask-in-text](plugins/ask-in-text/) | ✅ v0.1.0 | Blocks the AskUserQuestion picker via a PreToolUse deny and injects a SessionStart convention to ask numbered plain-text questions in the conversation instead. |
| [debugging](plugins/debugging/) | ✅ v0.2.0 | Root-cause debugging guidance for orchestrators: reproduction, what-changed archaeology, differential diagnosis, binary-search isolation, log/DB evidence gathering with engineer paste-back, and class-level recurrence prevention. |

<!--
Contract: B02 registration
Behavior: register the render-doc plugin in the marketplace and this README.
Outputs:
- .claude-plugin/marketplace.json gains exactly one entry in its "plugins"
  array: name "render-doc", source "./plugins/render-doc", a one-sentence
  description covering both HTML rendering and annotation write-back, and
  version "0.1.0". The file stays jq-valid.
- The Plugins table above gains exactly one row:
  | [render-doc](plugins/render-doc/) | ✅ v0.1.0 | <what it does, naming
  /render-doc:render> |
Invariants: version agrees with plugins/render-doc/.claude-plugin/plugin.json;
no duplicate render-doc entries or rows; per the repo convention below
("the marketplace never lists empty shells") the entry reaches master only
together with the working plugin — satisfied by single-PR delivery (G01);
integration-branch intermediate states are internal.
Errors: n/a — declarative edits; validity enforced by the jq lint and the
registration test.
Edge cases: row and entry placement mirror the existing ordering style; the
exact position is not contractual, presence and uniqueness are.
-->

<!--
Contract: B03 assembly & registration (ask-in-text)
Behavior: assemble the ask-in-text plugin (manifest + hook wiring) and
register it in the marketplace and this README. Composition block: its
children are B01 (scripts/block-question.sh, the PreToolUse deny) and B02
(scripts/questions-context.sh, the SessionStart convention); this block's
promise is that both are wired so the plugin blocks AskUserQuestion and
injects the numbered-text question convention in every session.
Outputs:
- plugins/ask-in-text/.claude-plugin/plugin.json: name "ask-in-text",
  version "0.1.0", a one-sentence description naming AskUserQuestion and
  the plain-text redirect, and an author object byte-identical (jq -Sc) to
  .claude-plugin/marketplace.json's owner. Stays jq-valid.
- plugins/ask-in-text/hooks/hooks.json: object form {"hooks": {...}}
  registering exactly two hooks and nothing else: a PreToolUse group with
  matcher "AskUserQuestion" running
  ${CLAUDE_PLUGIN_ROOT}/scripts/block-question.sh (type "command",
  timeout 10), and a SessionStart group (no matcher) running
  ${CLAUDE_PLUGIN_ROOT}/scripts/questions-context.sh (type "command",
  timeout 10). Stays jq-valid.
- .claude-plugin/marketplace.json: exactly one plugins[] entry — name
  "ask-in-text", source "./plugins/ask-in-text", a non-empty description
  naming AskUserQuestion, and no version field.
- The Plugins table above gains exactly one row:
  | [ask-in-text](plugins/ask-in-text/) | ✅ v0.1.0 | <what it does, naming
  AskUserQuestion and the numbered plain-text convention> |
Invariants: version agrees between plugin.json and the README row; no
duplicate ask-in-text entries or rows; hooks.json registers no events or
commands beyond the two above; every .sh under plugins/ask-in-text/ is
executable in the git index (scripts/executable-lint.sh); hooks-only
plugin — no skills/ directory; per the repo convention below ("the
marketplace never lists empty shells") the registration reaches master
only together with the working plugin — satisfied by single-PR delivery
(G01); integration-branch intermediate states are internal (the
marketplace entry lands at scaffold because marketplace-lint requires
directory/entry parity from the moment the plugin directory exists).
Errors: n/a — declarative edits; validity enforced by the jq lint,
scripts/marketplace-lint.sh, and this block's tests.
Edge cases: reloading plugins mid-build is safe — the scaffolded
hooks.json registers nothing until this block's implementation wires it;
row and entry placement mirror the existing ordering style, presence and
uniqueness are contractual, position is not.
-->

See [MIGRATION.md](MIGRATION.md) for the full element-by-element mapping from
clam-code, including what is deliberately left behind.

## Repo conventions

- Each plugin lives in `plugins/<name>/` with its own
  `.claude-plugin/plugin.json`, `skills/`, `agents/`, `hooks/`, `scripts/`.
- Skill names avoid repeating the plugin name: the invocation is
  `/lego:plan`, not `/lego:lego-plan`.
- A plugin is added to `.claude-plugin/marketplace.json` only once it is
  ported and working — the marketplace never lists empty shells.
- `plugin.json` is the single source of truth for version. Do not set
  `version` in marketplace.json plugin entries — Claude Code reads it from
  plugin.json and a duplicate drifts silently.
- When a plugin is absorbed into another or renamed, add a `renames` entry
  to `marketplace.json` mapping the old name to the new one (or to `null` if
  removed without replacement). This lets Claude Code (v2.1.193+)
  auto-rewrite installed references on the next sync instead of erroring
  with "plugin not found".
- Run `bash scripts/marketplace-lint.sh` before merging to catch
  directory/marketplace mismatches, stale renames, and redundant version
  fields.

- Every issue is one of two categories — feature or bug — filed through the
  issue forms in `.github/ISSUE_TEMPLATE/` (blank issues are disabled);
  forms auto-apply the `feature` / `bug` label.
- Issue titles carry the matching commit-style prefix: `feat: ` for
  features, `fix: ` for bugs (the forms pre-fill it).
- The forms' affected-plugin dropdown must list every `plugins/*`
  directory; `bash scripts/issue-template-lint.sh` enforces sync.

