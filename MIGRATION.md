# Migration map: clam-code / clam-v2 → clam plugins

Tracks where every element of the previous iterations lands. Statuses:
**ported** (in this repo, listed in the marketplace), **planned** (assigned a
plugin, not yet ported), **out of scope** (deliberately left behind),
**dropped** (superseded).

Hook-to-plugin assignments, and every other status claim in this file
predating plan 001-github-issue-13, were verified on 2026-07-27 against
clam-code (origin `clipboard-app/clam-code`) and clam-generic (origin
`cjdubb/clam-generic`) — **both are source surfaces this map tracks, not
clam-code alone** — and against this repo's shipped `plugins/` and
`.claude-plugin/marketplace.json`. Claims that did not survive checking were
corrected in place, with the evidence noted inline; a status of
`unverified — <reason>` marks a claim that could not be checked at all.

## lego — ported (from clam-v2)

Skills renamed to drop the redundant prefix: `lego-plan` → `/lego:plan`,
`lego-scaffold` → `/lego:scaffold`, `lego-dispatch` → `/lego:dispatch`.
Agents (`lego-test-writer`, `lego-implementer`), realm scripts, hooks,
templates, and docs ported from clam-v2. "Unchanged" no longer holds, though
— diffed against clam-v2's working tree (2026-07-27): `hooks/hooks.json` and
`scripts/realm-check.sh` remain byte-identical, but `scripts/realm-gate.sh`
has since gained the `.local/`-read-only deny, `scripts/realm.sh` and
`docs/config-schema.md` gained the layered `.claude/lego.json` +
`.local/config.json` config with multi-variant test commands,
`scripts/session-context.sh`, `agents/lego-implementer.md`, and
`agents/lego-test-writer.md` were rewritten for the worktree-per-unit
dispatch model (each worker gets its own dedicated worktree and a seeded
`.local/` brief, rather than sharing one checkout), and `templates/blocks.md`
/ `templates/lego.json` (renamed from clam-v2's `config.json`) gained
`Unit:`/`PR group:` and `delivery.mode` fields. The status stays **ported
(from clam-v2)** — nothing here gained a clam-code ancestor instead — this
corrects only the "unchanged" claim. clam-v2's repo and marketplace retire;
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
- Hooks: `pr-status.sh` (Stop). (`log-skill-trigger.sh` reassigned to
  **skill-tracker** — see below)
- When ported, `create-pr` also becomes the delegated github-pr provider
  behind `/landing:land` (see **landing**), and `pre-pr-verify` should be
  reconciled with the profile's `landing-verify` command.

## landing — new (not a port)

No clam-code ancestor; born 2026-07-20 from the "generic config across repo
variances" work. Owns the landing seam: a repo-committed policy file
(`.claude/clam-profile.jsonc`, namespaced keys shared with future seams)
plus the generic `/landing:land` verb with `github-pr` and `local-merge`
strategies, `/landing:init` policy setup, and a SessionStart policy
injection.

Port change: the policy file moved from `.claude/clam-profile.md` (flat
frontmatter keys) to `.claude/clam-profile.jsonc` (JSON with `//` comments)
alongside the **build** plugin's introduction (plan 001) — see
**build** below.

Couplings to honor at later ports:

- **pr-workflow**: `create-pr` slots in behind the github-pr strategy (the
  delegation seam is already written into the land skill).
- **worktrees**: the local-merge strategy locates target checkouts and can
  remove work worktrees — keep conventions aligned when that plugin lands.
- **issue-tracker** (inside pr-workflow): its jira/github/none provider knob
  is the natural second resident of the profile file — namespaced keys in
  `.claude/clam-profile.jsonc`, not a new file.

## build — new (not a port)

No clam-code ancestor; born 2026-07-22 from issue #56 (PR description
sync) as **deliver**, renamed to **build** 2026-07-26 (PR #137, plan
001-github-issue-13) — a filesystem rename, not a replacement: same
directory history, same contract, only the name and its `/deliver:` skill
namespace changed (now `/build:`). Composition layer above **landing**,
**lego**, and **tracking**: a SessionStart hook (`build-context.sh`) that
detects which companion plugins are installed and explains how they
compose into a delivery lifecycle, plus the `/build:sync-pr` skill that
keeps an open PR's description current with the branch behind it
regardless of which companion (or manual `gh pr create`) opened it.
Degrades gracefully when none of its companions are installed.

Absorbs the composition/orchestration slice of the **pr-workflow** plugin
planned above: `pr-workflow`'s reviewer-side skills (`pr-review`,
`pr-review-perfect`, `find-reviewer`, `get-pr-comments`,
`address-pr-feedback`, etc.) remain planned there unchanged, but the
PR-description-freshness concern that would otherwise have landed in
`pr-workflow` belongs to build instead.

Shipped alongside the `.claude/clam-profile.md` → `.claude/clam-profile.jsonc`
profile format change (see **landing**), since build's session-start
context and `/build:sync-pr` both read repo-declared policy.

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
- Also carries `flush-nudge.sh` (UserPromptSubmit), `post-compact-recovery.sh`
  (SessionStart, `compact` matcher), and `precompact-snapshot.sh`
  (PreCompact) — session-continuity hooks landed directly in tracking on
  2026-07-22 (`b29758b`), separately from the make-progress absorption below.
  Corrected 2026-07-27: this map previously still listed these three under
  session-modes' still-to-port hooks; they are already shipped and wired
  here (`plugins/tracking/hooks/hooks.json`).

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

Tracking v0.3.0 absorbs the standalone make-progress plugin: stall recovery
(the `/make-progress` skill, its `capture.sh` UserPromptSubmit hook, and
`lib/platform.sh`) now ships as part of tracking rather than its own plugin.
The `make-progress` plugin is **dropped** from the marketplace and its
directory removed. A `renames` entry in `marketplace.json` maps
`make-progress` → `tracking` so existing installs auto-resolve on sync
(requires Claude Code v2.1.193+).

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

- Skills: `start`, `orient`, `sitrep`, `role-check`, `whats-cooking`,
  `planning`, `orchestrator-handover` (moved to **orchestrator-handover**)
- Hooks: `session-start.sh` (grows into the workflow-rules injection that
  replaces the `clam` alias — content sourced from `general/system-prompt.md`;
  the Work Management section is already carried by the tracking plugin's
  injection, so session-modes must not duplicate it)
- (`keep-working.sh` and `awaiting-user.sh` moved to **tracking**;
  `prompt-timestamp.sh` and `capture-permission-mode.sh` moved to
  **notifications**, their consumers. Corrected 2026-07-27: the
  `make-progress` skill, and hooks `flush-nudge.sh`, `capture-make-progress.sh`
  (now `capture.sh`), `post-compact.sh` (now `post-compact-recovery.sh`), and
  `precompact-snapshot.sh`, are also already ported — into **tracking**, not
  session-modes (see the **tracking** section above) — verified via this
  repo's own commit history (`5dd0145`, `b29758b`) and
  `plugins/tracking/hooks/hooks.json`. This map previously still listed them
  here as session-modes' to port.)

## orchestrator-handover — ported (from clam-code)

Moved out of the session-modes bucket into its own standalone plugin, since
its behavior (writing a handover document, scaffolding the recipient
worktree, populating its `.local/`, and handing off to the user) is
self-contained and doesn't depend on the rest of session-modes.

Single skill: `/orchestrator-handover:create`, ported from clam-code's
`general/skills/orchestrator-handover/`.

Port changes: dropped the `newcliptree`/CLIP-* branching (always uses
`newtree` now), generalized issue-tracker language away from any specific
tracker, and softened cross-plugin references so the skill degrades
gracefully when a referenced plugin isn't installed.

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
- The rundown skill's HTML-render gate is resolved: it now consumes
  render-doc by skill name (`render-doc:render`) instead of a clam-code
  filesystem path — see the **render-doc** section below.

## render-doc — ported (from clam-code)

Ported from `general/skills/render-doc/`: renders a planning or decision
markdown document into a single self-contained dark-theme HTML view, with an
annotation server whose in-page composer writes `@TAG:` feedback lines back
into the source markdown.

Port changes: the usage path becomes
`${CLAUDE_PLUGIN_ROOT}/scripts/render.sh <doc.md> [--open]`; the
decision-rundown reference is renamed to `/decision-log:rundown`;
`smoke.sh` is adapted into `scripts/render.test.sh`, with no duplicate
`smoke.sh` kept; `CLAM_RENDER_DOC` env var removed — plugin presence is
the gate (installing the plugin opts in to automatic checkpoint rendering;
callers check skill availability, not an env var).

Coupling note: consumers reference the skill by name (`render-doc:render`),
nothing else — no cross-plugin filesystem paths, no env var convention.

## team-review — planned

- Skills: `team-code-review`, `team-council`, `team-exploration`,
  `independent-review`, `independence-protocol`, `subagent-orchestration`
- Agents: `Explore`, `browser`
- Hooks: *(none — `orchestrator-guard.sh` dropped; see Guard inventory)*

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

## skill-tracker — ported (from clam-code)

Skill invocation telemetry, split out from the pr-workflow plan where it was
originally assigned alongside `pr-retrospective`. Generic enough to stand
alone: any consumer of `~/.claude/skill-triggers.jsonl` can depend on this
plugin without pulling in the full PR workflow.

- Hooks: `log-skill-trigger.sh` (PreToolUse + PostToolUse on Skill; appends
  one JSONL row per event to `~/.claude/skill-triggers.jsonl`)
- Scripts: `skill-stats.sh` (CLI reporter: top skills, daily triggers, errors)
- Skills: `/skill-tracker:stats` (runs the reporter conversationally)

Port changes: `skill-stats.sh` drops the "On-disk skills never triggered"
section (hardcoded clipboard-specific paths; replaced with JSONL-only
reporting). `log-skill-trigger.sh` adds `mkdir -p ~/.claude` before the
append. Both scripts use `jq -R -c 'fromjson? | ...'` for malformed-line
resilience instead of the reference's whole-file `jq -c 'select(...)'`.

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
| `log-skill-trigger.sh` | skill-tracker | ported |
| `orchestrator-guard.sh` | — (incompatible with lego scaffold phase) | dropped |
| `keep-working.sh` | tracking | ported |
| realm gate (`realm-gate.sh` + `realm-check.sh`) | lego | ported |
| `lego-dispatch-guard.sh` | — (superseded by lego) | dropped |

## agent-dash — planned

Integration with clam-agent-dashboard.

- Hooks: `agent-dash-permission.sh`, `session-track.sh`, `git-sync.sh`
  (verify: several session-modes hooks also touch agent-dash state files —
  untangle the coupling or accept a soft dependency between the two plugins)

## Audit: clam-generic divergence

A diff -rq run between clam-code's general/ tree (origin clipboard-app/clam-code) and clam-generic's general/ tree (origin cjdubb/clam-generic) reports 79 entries, confirming the plan-time count exactly: 3 present only in clam-generic, 11 present only in clam-code, and 65 present in both but differing in content.

**Preferred migration source: clam-generic.** Where the two repos diverge on a shared file, clam-generic's version is consistently the already-genericized one, and in several cases it already matches decisions this map has made independently, which is stronger evidence than "the fork whose point is being generic, therefore prefer it" would be on its own. clam-generic's hooks/git-guard.sh exempts a configurable reviewer login instead of hardcoding CodeRabbit — the exact CLAM_AUTO_REVIEWER knob the **git-guard** section above already plans to carry. clam-generic's system-prompt.md replaces the Jira-only ticket gate with the issue-tracker skill's provider seam and drops the Clipboard-only "Strictening" mode entirely; lib/worktree-naming.sh drops that same Strictening mode from its legal-mode table. clam-code's clam-settings.json still carries clipboard-repo-only permission entries (Bash(newcliptree:*), Bash(cdt), Read(~/clipboard-repos/**)) that clam-generic has already stripped.

Generic-only (present only in clam-generic; verified, matches the plan-time hint):

- `general/skills/issue-tracker` — planned (pr-workflow)
- `general/skills/pre-pr-verify` — planned (pr-workflow); this is the provider-agnostic gate sequence — disambiguated against repos/clipboard's own copy of `pre-pr-verify` in the next section
- `general/hooks/agent-dash-permission.test.sh` — planned (agent-dash); the test suite for `agent-dash-permission.sh`, which the **agent-dash** section already lists

Clam-code-only (present only in clam-code; verified, matches the plan-time hint):

- `general/skills/absorb-package` — out of scope; an NX-graph-driven package-consolidation skill scoped to the Clipboard monorepo (`nx graph`, `libs/`, `apps/`); it is the implementation-layer skill that repos/clipboard's own `monorepo-consolidation` skill hands off to (see the next section) — not portable to a generic marketplace
- `general/skills/create-jira-ticket` — dropped; its entire content (the Atlassian-MCP current-user lookup, the `createJiraIssue` call with Project/Summary/Assignee/Issue Type, and the documented `\n`-literal-text quirk) is folded verbatim into clam-generic's `issue-tracker` skill's `providers/jira.md` `create()` operation — genuinely superseded, not merely renamed
- `general/lib/clipboard-helpers.sh`, `general/lib/clipboard-helpers.fish`, `general/lib/clipboard-helpers.test.sh` — out of scope; the file's own header calls it "Clipboard-repo-coupled" (reads `CLIPBOARD_ENV_DIR`, implements `newcliptree`); the **orchestrator-handover** port already dropped the `newcliptree`/CLIP-* branching these files exist to serve, always using `newtree` now
- `general/lib/trees-dir.sh`, `general/lib/trees-dir.fish`, `general/lib/trees-dir.test.sh` — out of scope; implements the `cdt` derivation. Repo-agnostic per its own header, but not shipped as a file anywhere in this repo's `plugins/` — it is the actual implementation behind a shell function the **worktrees** plugin's skills document usage of without shipping, matching the "Out of scope" section's existing `general/lib/` shell-helpers line
- `general/lib/worktree-helpers.sh`, `general/lib/worktree-helpers.fish`, `general/lib/worktree-helpers.test.sh` — out of scope, same reasoning; implements `cdt`/`newtree`/`rmtree`

Two more files among the 65 that differ are worth flagging because neither is named anywhere in this map yet. `general/lib/worktree-naming.sh` is consumed only by `general/skills/start/SKILL.md` (the `/start` naming gate), which the **session-modes** section lists as planned — planned, by the same reasoning, though not itself named there. `general/lib/session-guard.sh` is consumed by both `general/hooks/session-track.sh` (agent-dash, planned) and `general/claude-alias.sh` (the out-of-scope `clam` alias mechanism) — unassigned, since its two consumers currently carry different statuses and nothing in the map picks one for it; this is a judgment call for whoever ports agent-dash, not one this audit can make for them.

Several elements this map already marks ported also appear among the 65 differing files: render-doc's `assets/template.html` and `fixtures/plan.md`, decision-log's `SKILL.md` and `template.md`, orchestrator-handover's `SKILL.md` and `template.md`, skill-tracker's `skill-stats.sh`, and notifications' `push-notify.sh` and `lib/notify.sh` have all moved in clam-generic since those elements were ported into this repo's plugins/ tree. This audit does not re-diff each already-ported element against clam-generic's newer content — recorded here as an observed fact for whoever next touches those plugins, not a re-porting claim.

## Audit: repos/clipboard overlay

clam-code carries a repos/clipboard/ tree, wholly absent from this map. Verified absent from clam-generic entirely — repos/ does not exist there at all, not even a subset. This is clam-code's per-repo overlay for the Clipboard EMS monorepo (a school-software platform, per its own CLAUDE.md), layered onto a checked-out Clipboard worktree by the overlay-claude-config.sh script listed below.

**Verdict: repo-specific-by-nature, and out of scope for a generic marketplace**, with one already-extracted exception (`pre-pr-verify`, below). This isn't personal tuning left behind for lack of time — every skill, rule, and hook here is bound to the Clipboard monorepo's own stack (NX, Angular, PostgreSQL DAOs) or its own CI (Husky), not portable material a generic plugin could carry.

Skills (verified against the plan-time hint — all 7 present, nothing more):

- `angular-dev` — out of scope; Angular/`cb-*` design-system, Material, signals, and RxJS conventions specific to the Clipboard monorepo's frontend
- `database` — out of scope; PostgreSQL DAO conventions (Either-returning contracts, UPDATE/DELETE return checks, TIMESTAMPTZ rules) specific to Clipboard's repository layer
- `database-migrations` — out of scope; wraps Clipboard's own `db-migrate` / `db:migration:create` tooling
- `monorepo-consolidation` — out of scope; runs `nx graph` analysis over the Clipboard workspace and hands implementation off to `general/skills/absorb-package` (also out of scope — see the divergence section above)
- `pre-pr-verify` — out of scope; this is the Clipboard-hardcoded original: NX targets (`nx affected -t lint`, `-t unit-test`, `-t integration-test-isolated`), `npm run format-code`, Docker/`.env` preconditions. This is a **different thing** from clam-generic's `general/skills/pre-pr-verify` (planned, mapped under **pr-workflow** above), which is the provider-agnostic gate sequence this overlay's copy was generalized into — same gate structure (format → lint → unit → doc-sync → integration → commit-structure), concrete commands resolved per-repo instead of hardcoded. The overlay's copy stays here, repo-bound; the generic copy is the migration source
- `stricten` — out of scope; per-package TypeScript strictening for Clipboard, tests-first protocol tied to the monorepo's own NX/ESLint setup
- `strictening` — out of scope; reads the Clipboard NX package inventory to pick the next `stricten` target, same repo-binding

Also present, not skills (verified):

- `rules/backend.md`, `rules/tests.md`, `rules/typescript.md` — out of scope; path-scoped code-style rules gated on Clipboard monorepo paths (`apps/*-api/**`, `libs/backend/**`, `libs/node/**`, `libs/lambda/**`, `**/*.sql`)
- `git-hooks/pre-push` — out of scope; a shim delegating to the Clipboard repo's own checked-in `.husky/pre-push`
- `lib/overlay-claude-config.sh`, `lib/overlay-claude-config.test.sh` — out of scope; the overlay mechanism itself, which lays this whole tree onto a checked-out Clipboard worktree's `.claude/` from `~/.claude/repo-configs/clipboard` — has no purpose once a repo consumes plugins from a marketplace instead of a filesystem overlay
- `API.md`, `CLAUDE.md` — out of scope; Clipboard product-context (school-software framing) and REST API-style docs, not present in the plan-time hint but found during verification — repo-specific by content, not by omission

No genuinely portable material was found beyond the already-extracted pre-pr-verify generalization; everything else here is bound to Clipboard's specific stack and would need a rewrite, not a port, to serve a generic marketplace.

## Audit: unmerged clam-code branches

clam-code-trees's bare repo has 7 worktrees besides `master`, each tracking one branch. Verified ahead/behind counts via `git rev-list --count origin/master..<branch>` against origin's `master` (`clipboard-app/clam-code`, currently at `0213ee4`), confirming the plan-time count exactly: `integration/genericize` 76 ahead, `orchestrate/hook-errors` 1 ahead, and the other five 0 ahead.

- `integration/genericize` — 76 commits ahead of `origin/master`. Distinct-vs-redundant call: **redundant**, and more strongly so than the plan-time hint anticipated. This branch's current tip commit, `1712ebd`, is not merely similar to clam-generic's content — it is byte-identical in SHA to clam-generic's current `master` HEAD (verified: `git rev-parse HEAD` on both worktrees returns the same `1712ebd03ffa4b8b99852d58a7ca4d55aada6edd`). The two are, right now, the same commit graph. Nothing on this branch is unmigrated relative to clam-generic; the divergence section above, audited against clam-generic directly, already covers everything this branch would contribute
- `orchestrate/hook-errors` — 1 commit ahead of `origin/master`. Distinct-vs-redundant call: **redundant**. Its one commit (`e97c612`, "fix(settings): remove ineffective Write() permission rules") is a stale fork: the branch's merge-base with `origin/master` is 15 commits behind current `origin/master`, and in the interim `origin/master` gained `b9bea11`, "fix(settings): remove ineffective Write() permission rules (#317)" — same message, and verified byte-identical diff content (`general/clam-settings.json` and `general/global-settings-bundle.json` match exactly between the two commits). The fix already landed on `origin/master` under a different commit hash; this worktree's branch was simply never fast-forwarded or removed afterward
- `feat/enable-linux-worktree-helpers` — 0 commits ahead of `origin/master`: no unmerged work
- `orchestrate/lego-approach-not-working` — 0 commits ahead of `origin/master`: no unmerged work
- `orchestrate/linux-worktree-helpers` — 0 commits ahead of `origin/master`: no unmerged work
- `orchestrate/pluginize-config` — 0 commits ahead of `origin/master`: no unmerged work
- `orchestrate/remove-clipboard-trees-dir` — 0 commits ahead of `origin/master`: no unmerged work

Every worktree in `/home/cwilliamson/github/clam-code-trees/` other than `master` is accounted for above; none contributes unmigrated content beyond what the clam-generic divergence audit already covers.

## ask-in-text — new (not a port)

No clam-code/clam-generic ancestor. `AskUserQuestion` appears exactly once in
either source repo's `general/` tree — `general/skills/start/SKILL.md`,
telling that one skill not to use the tool because of its 4-option limit —
not a generic picker-blocking mechanism. This plugin's PreToolUse deny
(`scripts/block-question.sh`) plus SessionStart plain-text-question redirect
(`scripts/questions-context.sh`) has no source-repo precedent.

## debugging — new (not a port)

No clam-code/clam-generic ancestor. The only debugging-named skill in either
source repo is `debug-playwright-tests` (tech-specific; already tracked in
**Unassigned**), a narrow Playwright-test debugger, not a general root-cause
methodology. This plugin's `root-cause` skill (reproduction, what-changed
archaeology, differential diagnosis, binary-search isolation, log/database
evidence gathering, class-level prevention) has no source-repo precedent.

## session-data — new (not a port)

No clam-code/clam-generic ancestor. Neither source repo has a skill or hook
that locates session transcript/data files; this plugin's
`/session-data:paths` skill is new.

## management — new (not a port)

No clam-code/clam-generic ancestor in the sense that matters here: clam-code
ships an `update.sh` at its repo root, but that is a fast-forward `git pull`
followed by re-running `setup.sh` over the whole dotfiles-style `general/`
tree — a different mechanism entirely from this plugin's per-plugin
marketplace version diff, which only makes sense once plugins exist as
independently versioned units (clam-code predates the plugin architecture).
`/management:update`'s catalog refresh, per-plugin version diff and
confirm-to-apply flow, and setup-version-stamp tracking
(`docs/setup-stamps.md`) are new.

Management v0.2.0 renames the plugin from `updates` to `management` and its
`run` skill to `update`: `/updates:run` becomes `/management:update`, and
the marketplace entry and directory become `management`. The name now states
the concern — plugin lifecycle for this marketplace — rather than the single
flow that currently implements it; behaviour is unchanged by the rename. A
`renames` entry in `marketplace.json` maps `updates` → `management` so
existing installs auto-resolve on sync (requires Claude Code v2.1.193+).
Below that version `renames` is not honoured: the old `updates@clam` id stops
resolving once the catalog refreshes, and the plugin has to be reinstalled as
`management@clam` by hand.

## voice — ported (from clam-code)

Source: clam-code `general/system-prompt.md`'s Voice section, PRs #357 and
#361, merged 2026-07-31.

What came over: the spec text verbatim, with one standalone adaptation —
the clause tying the rules to the source file's surrounding Communication section
is dropped, since this plugin injects the spec on its own (originally via a
SessionStart hook, since v0.3.0 as output styles) rather than as a
subsection of a larger system prompt.

What deliberately stays behind: the `dev-docs/voice` campaign record and
Phase 6 toolkit — org-private material (transcript excerpts and captured system prompts)
approved only for the private source repo, while this repo is public.

Canonical-home decision: this plugin is now canonical for the Voice
spec. The source repo's copy is a consumer until retired.

## Unassigned — decide at port time

- _(the former "support" cluster entries here — two skill names — were
  retired before the plugin era and are not a migration candidate. Verified
  2026-07-27: absent from both source repos' `general/` trees entirely;
  every occurrence found in either repo is historical — confined to
  `decision-logs/*.md`, 4 files, and one dated release note — matching the
  plan-time hint exactly.)_
- `writing-markdown`, `rtfm` (writing cluster)
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

## Migration candidate register

Every row below traces to a B01 "## Audit:" section or a B02-reconciled
pre-existing section. Elements B01/B02 marked **ported** or **dropped** are
excluded — they are not candidates, the action already happened. Clusters
(a whole "planned" plugin section) get one row each, named as a cluster, so
the follow-up issue they become is sized right; individual elements get
their own row when the map itself singles them out (the two `pre-pr-verify`
findings, the two lib files the divergence audit surfaced but never
assigned, the Unassigned bullets, the doc-referenced `fewer-permission-prompts`
gap).

| Element | Source surface | Current status | Recommendation | Rationale |
| --- | --- | --- | --- | --- |
| pr-workflow plugin cluster (12 skills incl. `create-pr`, `address-pr-feedback`, `get-pr-comments`, `find-reviewer`, `pr-author-checklist`, `pr-retrospective`, `pr-review`, `pr-review-perfect`, `pr-status`, `status-sync`, `issue-tracker`, `doc-sync`; `skills/PR-WORKFLOW.md`; `reviewer` agent; `pr-status.sh` hook) | clam-code general/skills+hooks (clam-generic preferred where a skill diverges — see the divergence audit) | planned | port | Whole plugin is assigned but not yet built; `pre-pr-verify` is disambiguated into its own row below rather than folded in here. |
| `pre-pr-verify` skill (clam-generic's provider-agnostic copy) | clam-generic general/skills/pre-pr-verify | planned (pr-workflow) | port | The gate sequence pr-workflow is planned to absorb; generalized from repos/clipboard's Clipboard-hardcoded copy, listed separately (out of scope) below — same name, different surface. |
| session-modes plugin cluster (skills: `start`, `orient`, `sitrep`, `role-check`, `whats-cooking`, `planning`; hook: `session-start.sh`; lib dependency: `worktree-naming.sh`) | clam-code general/skills/{start,orient,sitrep,role-check,whats-cooking,planning}, general/hooks/session-start.sh, general/lib/worktree-naming.sh | planned | port | Whole plugin assigned but not yet built; `session-start.sh` must absorb `system-prompt.md`'s workflow-rules content (the alias mechanism itself is out of scope, below), and `worktree-naming.sh` is `/start`'s un-shipped lib dependency, surfaced by the divergence audit. |
| team-review plugin cluster (skills: `team-code-review`, `team-council`, `team-exploration`, `independent-review`, `independence-protocol`, `subagent-orchestration`; agents: `Explore`, `browser`) | clam-code general/skills/{...}, general/agents/{Explore,browser} | planned | port | Whole plugin assigned but not yet built; no hook (`orchestrator-guard.sh` is dropped, incompatible with the lego scaffold phase). |
| permissions plugin cluster (hook: `permission-audit.sh`; skill: `analyze-permissions.sh` promoted to `/permissions:analyze`) | clam-code general/hooks/permission-audit.sh, general/analyze-permissions.sh (unwired CLI helper) | planned | port | Whole plugin assigned but not yet built; the doc-referenced `fewer-permission-prompts` gap is a separate open call, listed under needs decision below. |
| git-guard plugin cluster (hook: `git-guard.sh` + `git-guard.test.sh`) | clam-code general/hooks/git-guard.sh | planned | port | Single guard assigned but not yet built; shares the `CLAM_AUTO_REVIEWER` knob with pr-workflow. |
| cron-guard plugin cluster (hook: `cron-guard.sh` + `cron-guard.test.sh`) | clam-code general/hooks/cron-guard.sh | planned | port | Single guard assigned but not yet built. |
| agent-dash plugin cluster (hooks: `agent-dash-permission.sh`, `session-track.sh`, `git-sync.sh`) | clam-code general/hooks/{agent-dash-permission.sh,session-track.sh,git-sync.sh}; clam-generic general/hooks/agent-dash-permission.test.sh | planned | port | Whole plugin assigned but not yet built; the coupling with session-modes' state files still needs untangling per the map's own note, and `session-guard.sh`'s ownership is a separate open decision, listed below. |
| `absorb-package` skill | clam-code general/skills/absorb-package | out of scope | out of scope | NX-graph package-consolidation skill scoped to the Clipboard monorepo; the implementation layer repos/clipboard's `monorepo-consolidation` hands off to — not portable to a generic marketplace. |
| `clipboard-helpers.sh` / `.fish` / `.test.sh` | clam-code general/lib/clipboard-helpers.* | out of scope | out of scope | Clipboard-repo-coupled (`CLIPBOARD_ENV_DIR`, `newcliptree`); orchestrator-handover already dropped the CLIP-* branching these files exist to serve. |
| `trees-dir.sh` / `.fish` / `.test.sh` and `worktree-helpers.sh` / `.fish` / `.test.sh` | clam-code general/lib/trees-dir.*, general/lib/worktree-helpers.* | out of scope | out of scope | Implement `cdt`/`newtree`/`rmtree`; repo-agnostic but not shipped as files anywhere in `plugins/` — the worktrees plugin's skills document their usage without shipping them, same reasoning the map gives both. |
| repos/clipboard overlay — skills `angular-dev`, `database`, `database-migrations`, `monorepo-consolidation`, `stricten`, `strictening`; `rules/backend.md`, `rules/tests.md`, `rules/typescript.md`; `git-hooks/pre-push`; `lib/overlay-claude-config.sh`/`.test.sh`; `API.md`, `CLAUDE.md` | repos/clipboard/ | out of scope | out of scope | Repo-specific-by-nature — bound to the Clipboard monorepo's own stack (NX, Angular, PostgreSQL, Husky) or its product context; would need a rewrite, not a port, to serve a generic marketplace. |
| `pre-pr-verify` skill (repos/clipboard's Clipboard-hardcoded original) | repos/clipboard/skills/pre-pr-verify | out of scope | out of scope | Clipboard-hardcoded (NX targets, `npm run format-code`, Docker/.env preconditions); the provider-agnostic generalization it was rewritten into is clam-generic's copy, listed as a port candidate above — same name, different surface. |
| `claude-alias.sh` + `claude-alias.fish` (the clam alias mechanism) | clam-code general/claude-alias.sh, general/claude-alias.fish | out of scope | out of scope | The alias mechanism itself dies with the `clam` alias; only its content (system-prompt.md's workflow-rules text) survives, already folded into the session-modes cluster above. |
| `clam-settings.json` sidecar, `managed-settings-setup.sh`, `managed-version-lock.json` | clam-code general/clam-settings.json, general/managed-settings-setup.sh, general/managed-version-lock.json | out of scope | out of scope | Contents already redistributed piecemeal into other plugins (hooks, permissions, skill overrides); what remains is personal tuning, not a portable unit. |
| `setup.sh`, `update.sh`, `cleanup.sh`, `cleanup-legacy.sh`, `setup-git-repo-with-trees.sh`, `claude-rules*.sh` | clam-code repo root | out of scope | out of scope | Dotfiles-style repo-bootstrap scripts, superseded by the plugin/marketplace install model (updates' per-plugin version diff replaces `update.sh`'s whole-tree `git pull`); not portable as marketplace plugins. |
| `general/CLAUDE.md` | clam-code general/CLAUDE.md | out of scope | out of scope | Global, user-managed universal rules — not plugin-shaped content. |
| `todo-worktree.sh` | clam-code general/todo-worktree.sh | deliberately not ported (revisit alongside tracking) | needs decision | Depends on clam-code session tooling this repo doesn't have yet — should it be revisited once the tracking plugin's session tooling matures, or dropped permanently? |
| `session-guard.sh` | clam-code/clam-generic general/lib/session-guard.sh (one of the 65 files differing between the two) | unassigned | needs decision | Consumed by both `session-track.sh` (agent-dash, planned) and `claude-alias.sh` (out of scope) — should it follow agent-dash's port, or the alias mechanism's retirement? |
| `writing-markdown`, `rtfm` (writing cluster) | clam-code general/ (exact skill paths not stated in the map's pre-existing Unassigned section) | unassigned | needs decision | Listed in Unassigned with no destination plugin named — should this become its own plugin, fold into an existing one, or move to out of scope? |
| `debug-playwright-tests` | clam-code general/ (exact path not stated in the map) | unassigned | needs decision | Narrow, tech-specific Playwright-test debugger — should it ship as a marketplace plugin skill, or remain repo-local tooling outside the marketplace? |
| orient-adjacent statusline data | clam-code general/ (Unassigned section bullet; its own cross-reference to a "statusline note below" does not resolve to any content elsewhere in this file) | unassigned | needs decision | What should happen to `/orient`'s statusline-adjacent data is unresolved, and the map's own pointer to a clarifying note is dangling — should this wait until that note is found or rewritten, or be decided without it? |
| `fewer-permission-prompts` (doc-referenced, never built) | clam-code docs reference only — general/ (no skill file exists in either source repo) | gap — referenced in clam-code's docs, never built | needs decision | clam-code's docs reference a `fewer-permission-prompts` skill that was never built in either source repo — build it fresh here, or drop the dangling doc references? |

port: 8 · drop: 0 · out of scope: 9 · needs decision: 6

Excluded, and why: the seven clam-code-trees worktree branches B01 audited
are not rows above. Five carry zero commits ahead of `origin/master` (no
content to name). The two with commits — `integration/genericize` (76
ahead) and `orchestrate/hook-errors` (1 ahead) — are both **redundant** per
B01: the former's tip is byte-identical to clam-generic's current `master`,
already covered by the divergence audit above; the latter's one commit
already landed on `origin/master` under a different SHA. Neither contributes
a distinct candidate beyond what the rows above already carry, so treating
them as additional rows would restate the map rather than extend the action
list.

## forge-github — new (not a port)

No clam-code ancestor: clam-code created PRs inline in its deliver flow
rather than through a forge abstraction. forge-github is born in this repo
as the first implementation of the forge interface
(`plugins/landing/docs/forge-interface.md`), extracted so that landing
delegates PR mechanics (`/forge-github:create-pr`, `/forge-github:sync-pr`)
instead of owning `gh` calls itself. The PR-description flowing-prose
conventions it carries originate from this repo's issue #53, not from any
clam-code element.
