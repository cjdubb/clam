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

The [updates](plugins/updates/) plugin wraps this in a guided flow:
`/updates:run` refreshes the catalog, shows which installed plugins are
behind, updates each on confirmation, and offers to re-run a plugin's setup
when the update calls for it. Install it once with
`/plugin install updates@clam`. Manually:

```
/plugin marketplace update clam        # re-fetch this repo, refresh the catalog
claude plugin update <plugin>@clam     # update one installed plugin (CLI only — no /plugin update)
```

Auto-update is **off by default** for third-party marketplaces like this one.
Turn it on per marketplace under `/plugin` → Marketplaces → clam →
Enable auto-update; Claude Code then checks shortly after session startup and
applies updates on the next launch (it prompts `/reload-plugins` when
something updated). `/plugin marketplace update clam` (or the CLI form `claude
plugin marketplace update clam`) only refreshes the marketplace catalog — it
never updates installed plugins, regardless of the auto-update setting; follow
it with `claude plugin update <plugin>@clam` per plugin to actually update.
Even with auto-update enabled, plugins that ship bundled hooks stay pinned to
the last explicitly installed version until you run that explicit update —
auto-update doesn't refresh the recorded install path
(anthropics/claude-code#52218, closed as not planned).

## Plugins

| Plugin | Status | What it does |
|--------|--------|--------------|
| [lego](plugins/lego/) | ✅ v0.5.2 | Contract-first planning, scaffolded stubs, realm-restricted test and implementation agent waves. Ported from clam-v2. |
| pr-workflow | planned | PR lifecycle: create, review, address feedback, author checklist, pre-PR verify, doc-sync gate, retrospective, reviewer agent, issue-tracker seam. |
| session-modes | planned | Session workflow modes (`/start`, orient, sitrep, make-progress, …) plus the session-lifecycle hooks and the SessionStart workflow-rules injection that replaces the old `clam` alias. |
| [decision-log](plugins/decision-log/) | ✅ v0.1.1 | Decision Logs: `/decision-log:create`, `/decision-log:interactive`, `/decision-log:rundown`. Ported from clam-code. |
| [tracking](plugins/tracking/) | ✅ v0.6.1 | Tracking documents: `.local/TODO.md` as session state of record, 13-state lifecycle with Stop-hook enforcement, resume after `/clear` via SessionStart injection. Powers agent-dash and the statusline State segment. |
| [statusline](plugins/statusline/) | ✅ v0.3.1 | Statusline: context usage, session/day/week cost, effort, tracking State. One explicit global write via `/statusline:setup`. |
| [landing](plugins/landing/) | ✅ v0.2.0 | The landing seam: `/landing:land` lands finished work per the repo's committed policy in `.claude/clam-profile.jsonc` (github-pr or local-merge); `/landing:init` detects and records it. |
| [orchestrator-handover](plugins/orchestrator-handover/) | ✅ v0.1.1 | Orchestrator-to-orchestrator handover: `/orchestrator-handover:create` writes a handover document, scaffolds the recipient worktree, populates its `.local/`, and hands off to the user. |
| team-review | planned | Multi-agent review and exploration: team code review, council, independent review, subagent orchestration; Explore and browser agents. |
| [worktrees](plugins/worktrees/) | ✅ v0.1.1 | Git worktree workflow on top of git-helpers (`newtree`, `rmtree`, `copyenv`, `cloneBareRepo`), plus the worktree-per-worker pattern for parallel agents. |
| [attribution](plugins/attribution/) | ✅ v0.2.0 | Suppress co-author attribution on commits and PRs. One explicit write via `/attribution:setup`. |
| [settings](plugins/settings/) | ✅ v0.2.0 | Agent teams and disabled adaptive thinking. One explicit write via `/settings:setup`. |
| [privacy](plugins/privacy/) | ✅ v0.2.0 | Opt out of telemetry, error reporting, feedback surveys, and non-essential traffic. One explicit write via `/privacy:setup`. |
| guards | planned | Safety hooks: git guard, cron guard, permission audit, notifications. |
| agent-dash | planned | Hooks integrating sessions with [clam-agent-dashboard](https://github.com/cjdubb/clam-agent-dashboard). |
| [deliver](plugins/deliver/) | ✅ v0.1.1 | High-level software delivery framework: composites landing, lego, and tracking into a cohesive delivery lifecycle. Provides PR description sync and delivery workflow context. |
| [render-doc](plugins/render-doc/) | ✅ v0.1.1 | Renders a markdown document into a self-contained HTML view via `/render-doc:render <file>`, with an annotation server that writes feedback back into the source markdown. Ported from clam-code. |
| [ask-in-text](plugins/ask-in-text/) | ✅ v0.1.1 | Blocks the AskUserQuestion picker via a PreToolUse deny and injects a SessionStart convention to ask numbered plain-text questions in the conversation instead. |
| [notifications](plugins/notifications/) | ✅ v0.1.1 | The summoning stack: terminal bell, desktop notification, tmux pane highlight, and ntfy phone push, driven by tracking states — rings on Blocked/Waiting For Decision/Awaiting User Review, silent for sessions that resume on their own. |
| [session-data](plugins/session-data/) | ✅ v0.1.1 | Locate the current session's conversation data files — transcript JSONL, subagent transcripts, file-history snapshots, session metadata — via `/session-data:paths`, with sensitivity annotations. |
| [skill-tracker](plugins/skill-tracker/) | ✅ v0.1.1 | Skill invocation telemetry: logs every `/skill` trigger to `~/.claude/skill-triggers.jsonl` and reports usage stats via `/skill-tracker:stats`. |
| [updates](plugins/updates/) | ✅ v0.1.0 | Guided plugin update flow: `/updates:run` refreshes the clam catalog, diffs installed vs latest versions, and applies per-plugin updates on confirmation. |
| [debugging](plugins/debugging/) | ✅ v0.2.1 | Root-cause debugging guidance for orchestrators: reproduction, what-changed archaeology, differential diagnosis, binary-search isolation, log/DB evidence gathering with engineer paste-back, and class-level recurrence prevention. |

<!--
Contract: B04 registration & root-README integrity (plan 001-update-flow-for-users)
Behavior: register the updates plugin and restore the Plugins table to
agreement with plugin.json versions (the single source of truth).
Outputs:
- .claude-plugin/marketplace.json: exactly one plugins[] entry — name
  "updates", source "./plugins/updates", a non-empty description naming
  /updates:run, and no version field. (Landed at scaffold because
  marketplace-lint requires directory/entry parity from the moment the
  plugin directory exists; content is contractual.)
- The Plugins table above gains exactly four rows, each inserted BEFORE the
  debugging row (which remains the last row — standing invariant):
  | [updates](plugins/updates/) | ✅ v0.1.0 | <what it does, naming /updates:run> |
  | [notifications](plugins/notifications/) | ✅ v<plugin.json> | <summoning stack per its marketplace description> |
  | [skill-tracker](plugins/skill-tracker/) | ✅ v<plugin.json> | <skill telemetry, naming /skill-tracker:stats> |
  | [session-data](plugins/session-data/) | ✅ v<plugin.json> | <session data file location, naming /session-data:paths> |
- Existing drifted rows corrected: lego → v0.5.1, tracking → v0.6.1.
- The five B05-bumped plugins' rows updated (attribution, privacy,
  settings, landing → v0.2.0; statusline → v0.3.0 — #123's caching
  release had consumed 0.2.0) — B05 is a dependency; use the plugin.json
  values as they stand when this block is implemented.
- The Update section prose above: corrected only if B02's empirical
  auto-update verification contradicts it; otherwise untouched.
Invariants: every marketplace plugin has exactly one table row whose
  version agrees with its plugin.json at implementation time; planned rows
  (pr-workflow, session-modes, team-review, guards, agent-dash) untouched;
  debugging stays the last row; no duplicate entries or rows; the
  marketplace entry reaches master only together with the working plugin
  (single-PR delivery G01; integration-branch intermediate states are
  internal).
Errors: n/a — declarative edits; validity enforced by the jq lint,
  scripts/marketplace-lint.sh, B06's root-table lint, and this block's
  registration test.
Edge cases: row placement beyond the before-debugging invariant mirrors
  the existing ordering style and is not contractual; presence, uniqueness,
  and version agreement are.
-->

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

## Checks

No plugins need to be installed to run the repo's checks — they're plain
bash/jq scripts.

```
bash scripts/ci.sh          # full gate: lint, test, then validate
bash scripts/ci.sh --lint   # lint stage only
bash scripts/ci.sh --test   # test stage only
```

The validate stage shells out to `claude plugin validate`; without the
`claude` CLI on PATH it prints `WARN  validate skipped (claude CLI not
found)` and does not fail the run — everything else in `ci.sh` runs and
gates normally regardless of whether `claude` is installed.

One-time per clone: `bash scripts/setup-hooks.sh` points `core.hooksPath`
at the committed `scripts/githooks/`, wiring the pre-push hook. Because
worktrees share the repo's config, this only needs to run once and takes
effect across every worktree of the clone.

**Version-bump rule:** any change under `plugins/<name>/` — code, README,
or test files alike — requires bumping that plugin's `.claude-plugin/
plugin.json` `version`. There are no exemptions; installed copies are
whole-directory snapshots keyed by version, so an unbumped change silently
never reaches installs. `scripts/version-bump-lint.sh` enforces this over
the committed range and runs as part of `ci.sh`'s lint stage.

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

