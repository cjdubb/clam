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
/plugin install management@clam
```

Run `/reload-plugins` to pick that up, then `/management:install`. It reads
the catalog at runtime, offers everything you don't already have as themed
multi-select pages, and installs the set you pick at one scope. Nothing is
pre-selected, no scope is assumed, and it names the setup skills a new plugin
ships rather than running them for you.

The scope question is asked once and covers the whole batch:

- `local` — this repo only, recorded in the gitignored
  `.claude/settings.local.json`. Suits a per-repo working style, and is the
  easiest to undo.
- `user` — every project on this machine.
- `project` — this repo, written to the committed `.claude/settings.json`, so
  everyone working in the repo gets the same set.

A `local` choice does not travel to git worktrees: the file holding it is
gitignored, so a new worktree starts with none of these plugins enabled. The
[worktrees](plugins/worktrees/) plugin's README explains how to seed it
automatically with `copyenv`.

### Without the picker

To take the whole catalog unattended, read the names out of the marketplace
clone Claude Code already keeps and install each from the shell:

```
CLAM=${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/marketplaces/clam
for p in $(jq -r '.plugins[].name' "$CLAM/.claude-plugin/marketplace.json"); do
  claude plugin install "$p@clam" --scope local
done
```

Pass `--scope` explicitly — the CLI defaults to `user`.

A repo you own can also name the marketplace and the plugins it wants in a
committed `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "clam": { "source": { "source": "github", "repo": "cjdubb/clam" } }
  },
  "enabledPlugins": {
    "lego@clam": true,
    "tracking@clam": true
  }
}
```

That declares enablement, not installation. Measured on Claude Code 2.1.220: a
session started in such a repo installed nothing — the named plugin was still
absent from `installed_plugins.json` afterwards, with no plugin cache entry
written and no install offered in a non-interactive run. Use the snippet
alongside one of the routes above, not instead of them.

## Update

`/management:update` refreshes the catalog, shows which installed plugins are
behind, updates each on confirmation, and offers to re-run a plugin's setup
when the update calls for it. It ships in the same
[management](plugins/management/) plugin the Install section starts with.
Manually:

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
| [lego](plugins/lego/) | ✅ v0.21.1 | Contract-first planning, scaffolded stubs, realm-restricted test and implementation agent waves. Ported from clam-v2. |
| pr-workflow | planned | PR lifecycle: create, review, address feedback, author checklist, pre-PR verify, doc-sync gate, retrospective, reviewer agent, issue-tracker seam. |
| session-modes | planned | Session workflow modes (`/start`, orient, sitrep, make-progress, …) plus the session-lifecycle hooks and the SessionStart workflow-rules injection that replaces the old `clam` alias. |
| [decision-log](plugins/decision-log/) | ✅ v0.2.1 | Decision Logs: `/decision-log:create`, `/decision-log:interactive`, `/decision-log:rundown`. Ported from clam-code. |
| [tracking](plugins/tracking/) | ✅ v0.11.2 | Tracking documents: `.local/TODO.md` as session state of record, 13-state lifecycle with Stop-hook enforcement, resume after `/clear` via SessionStart injection. Powers agent-dash and the statusline State segment. |
| [statusline](plugins/statusline/) | ✅ v0.12.0 | Statusline: path, branch, tracking State, model and effort, weekly and 5-hour plan limits paced to the hours you actually work, context usage. One explicit global write via `/statusline:setup`. |
| [landing](plugins/landing/) | ✅ v0.4.0 | The landing seam: `/landing:land` lands finished work per the repo's landing policy (github-pr or local-merge); `/landing:init` detects and records it in user-local storage. |
| [orchestrator-handover](plugins/orchestrator-handover/) | ✅ v0.1.4 | Orchestrator-to-orchestrator handover: `/orchestrator-handover:create` writes a handover document, scaffolds the recipient worktree, populates its `.local/`, and hands off to the user. |
| team-review | planned | Multi-agent review and exploration: team code review, council, independent review, subagent orchestration; Explore and browser agents. |
| [worktrees](plugins/worktrees/) | ✅ v0.1.5 | Git worktree workflow on top of git-helpers (`newtree`, `rmtree`, `copyenv`, `cloneBareRepo`), plus the worktree-per-worker pattern for parallel agents. |
| [attribution](plugins/attribution/) | ✅ v0.2.4 | Suppress co-author attribution on commits and PRs. One explicit write via `/attribution:setup`. |
| [settings](plugins/settings/) | ✅ v0.2.4 | Agent teams and disabled adaptive thinking. One explicit write via `/settings:setup`. |
| [privacy](plugins/privacy/) | ✅ v0.2.4 | Opt out of telemetry, error reporting, feedback surveys, and non-essential traffic. One explicit write via `/privacy:setup`. |
| guards | planned | Safety hooks: git guard, cron guard, permission audit, notifications. |
| agent-dash | planned | Hooks integrating sessions with [clam-agent-dashboard](https://github.com/cjdubb/clam-agent-dashboard). |
| [build](plugins/build/) | ✅ v0.6.1 | High-level software build lifecycle framework: composites landing, lego, and tracking into a cohesive delivery lifecycle, providing delivery workflow context. |
| [render-doc](plugins/render-doc/) | ✅ v0.13.1 | Renders a markdown document into a self-contained HTML view via `/render-doc:render <file>`, with an annotation server that writes feedback back into the source markdown. Ported from clam-code. |
| [ask-in-text](plugins/ask-in-text/) | ✅ v0.1.3 | Blocks the AskUserQuestion picker via a PreToolUse deny and injects a SessionStart convention to ask numbered plain-text questions in the conversation instead. |
| [notifications](plugins/notifications/) | ✅ v0.1.2 | The summoning stack: terminal bell, desktop notification, tmux pane highlight, and ntfy phone push, driven by tracking states — rings on Blocked/Waiting For Decision/Awaiting User Review, silent for sessions that resume on their own. |
| [session-data](plugins/session-data/) | ✅ v0.1.3 | Locate the current session's conversation data files — transcript JSONL, subagent transcripts, file-history snapshots, session metadata — via `/session-data:paths`, with sensitivity annotations. |
| [skill-tracker](plugins/skill-tracker/) | ✅ v0.1.2 | Skill invocation telemetry: logs every `/skill` trigger to `~/.claude/skill-triggers.jsonl` and reports usage stats via `/skill-tracker:stats`. |
| [management](plugins/management/) | ✅ v0.6.3 | Guided plugin lifecycle: `/management:install` offers the catalog's uninstalled plugins as themed multi-select picks and installs them at one chosen scope; `/management:update` diffs installed vs latest versions and applies confirmed updates. |
| [voice](plugins/voice/) | ✅ v0.4.0 | Voice communication spec: two selectable output styles apply conclusion-first, working-memory-friendly reply structure, with or without Claude Code's built-in coding instructions, plus a user-invoked re-pitch skill. Ported from clam-code. |
| [forge-github](plugins/forge-github/) | ✅ v0.2.1 | GitHub forge implementation: `/forge-github:create-pr` opens PRs, `/forge-github:sync-pr` keeps their descriptions current, and `/forge-github:address-pr-feedback` triages review comments behind an approval gate, all via the `gh` CLI with flowing-prose descriptions. |
| [debugging](plugins/debugging/) | ✅ v0.2.7 | Root-cause debugging guidance for orchestrators: reproduction, what-changed archaeology, differential diagnosis, binary-search isolation, log/DB evidence gathering with engineer paste-back, and class-level recurrence prevention. |

<!-- Editing the Plugins table: every plugin in .claude-plugin/marketplace.json
     has exactly one row here, and its status cell must read "✅ vX.Y.Z" matching
     that plugin's .claude-plugin/plugin.json. The debugging row stays last —
     insert new rows before it. Both rules are enforced: scripts/readme-lint.sh
     (version agreement) and plugins/debugging/scripts/b10-registration.test.sh
     (last-row invariant). -->

<!--
Contract: B08 registration (plan 001-fix-pr-line-lengths)
Behavior: register the forge-github plugin and sync this repo's
registration surfaces to the post-refactor state of build, landing, and
lego.
Outputs:
- .claude-plugin/marketplace.json: exactly one forge-github entry (name,
  source "./plugins/forge-github", non-empty description naming both
  skills, no version field) — landed at scaffold for directory/entry
  parity; content is contractual. The build entry's description updated
  to drop its PR-description-sync claim (the skill moved to
  forge-github); landing's and lego's descriptions updated only if they
  contradict the post-refactor behavior.
- The Plugins table above: exactly one forge-github row (inserted before
  the debugging row — standing last-row invariant), and the build,
  landing, and lego rows' versions and descriptions agree with their
  plugin.json files at implementation time (build's row no longer
  mentions /build:sync-pr).
- .github/ISSUE_TEMPLATE/{bug,feature}.yml: forge-github in each
  affected-plugin dropdown, alphabetical order (landed at scaffold for
  issue-template-lint parity).
- .claude/settings.local.json: forge-github@clam enabled alongside the
  other repo plugins.
Invariants: every marketplace plugin has exactly one table row whose
  version agrees with its plugin.json; debugging stays the last row;
  planned rows untouched; no duplicate entries; the registration reaches
  master only together with the working plugin (single-PR delivery G02;
  integration-branch intermediate states are internal).
Errors: n/a — declarative edits; validity enforced by marketplace-lint,
  readme-lint's root-table check, issue-template-lint, and this block's
  tests.
Edge cases: row placement beyond the before-debugging invariant mirrors
  the existing ordering style and is not contractual; presence,
  uniqueness, and version agreement are.
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

- [ARCHITECTURE.md](ARCHITECTURE.md) records what each workflow plugin is
  responsible for and the layering rules governing how they may refer to each
  other — references point downward only, leaf plugins work effectively
  installed alone, and siblings like `lego` and `landing` have no knowledge
  of each other. Read it before adding a cross-plugin reference.
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

