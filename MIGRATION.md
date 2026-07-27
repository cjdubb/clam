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
alongside the **deliver** plugin's introduction (plan 001) — see
**deliver** below.

Couplings to honor at later ports:

- **pr-workflow**: `create-pr` slots in behind the github-pr strategy (the
  delegation seam is already written into the land skill).
- **worktrees**: the local-merge strategy locates target checkouts and can
  remove work worktrees — keep conventions aligned when that plugin lands.
- **issue-tracker** (inside pr-workflow): its jira/github/none provider knob
  is the natural second resident of the profile file — namespaced keys in
  `.claude/clam-profile.jsonc`, not a new file.

## deliver — new (not a port)

No clam-code ancestor; born 2026-07-22 from issue #56 (PR description
sync). Composition layer above **landing**, **lego**, and **tracking**:
a SessionStart hook (`deliver-context.sh`) that detects which companion
plugins are installed and explains how they compose into a delivery
lifecycle, plus the `/deliver:sync-pr` skill that keeps an open PR's
description current with the branch behind it regardless of which
companion (or manual `gh pr create`) opened it. Degrades gracefully when
none of its companions are installed.

Absorbs the composition/orchestration slice of the **pr-workflow** plugin
planned above: `pr-workflow`'s reviewer-side skills (`pr-review`,
`pr-review-perfect`, `find-reviewer`, `get-pr-comments`,
`address-pr-feedback`, etc.) remain planned there unchanged, but the
PR-description-freshness concern that would otherwise have landed in
`pr-workflow` belongs to deliver instead.

Shipped alongside the `.claude/clam-profile.md` → `.claude/clam-profile.jsonc`
profile format change (see **landing**), since deliver's session-start
context and `/deliver:sync-pr` both read repo-declared policy.

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

- Skills: `start`, `orient`, `sitrep`, `role-check`, `make-progress`,
  `whats-cooking`, `planning`, `orchestrator-handover` (moved to
  **orchestrator-handover**)
- Hooks: `session-start.sh` (grows into the workflow-rules injection that
  replaces the `clam` alias — content sourced from `general/system-prompt.md`;
  the Work Management section is already carried by the tracking plugin's
  injection, so session-modes must not duplicate it), `flush-nudge.sh`,
  `capture-make-progress.sh`, `post-compact.sh`, `precompact-snapshot.sh`
- (`keep-working.sh` and `awaiting-user.sh` moved to **tracking**;
  `prompt-timestamp.sh` and `capture-permission-mode.sh` moved to
  **notifications**, their consumers)

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

<!--
Contract: B01 audit-unmapped-surfaces (plan 001-github-issue-13)

Behavior:
  Catalog the three source surfaces this map has never covered, as three new
  sections, so that every element of each surface is named and carries a
  status. The map's own header claims to track "where every element of the
  previous iterations lands"; today it tracks two of five surfaces. This block
  closes three of the three gaps. It records what EXISTS and what its status
  IS; it does not recommend action (that is B03) and it does not touch any
  pre-existing section (that is B02).

  Read-only against the sources. This block writes ONLY MIGRATION.md inside
  this repo. It must never write, commit, checkout, or otherwise mutate
  anything under the source repo paths below.

Inputs (all read-only, absolute paths):
  - /home/cwilliamson/github/clam-code-trees/master
      origin clipboard-app/clam-code — the original.
  - /home/cwilliamson/github/clam-code-generic-trees/master
      origin cjdubb/clam-generic — the genericized fork.
  - /home/cwilliamson/github/clam-code-trees/<other worktrees>
      sibling worktrees of the clam-code bare repo.
  - This repo's plugins/ directory, to judge whether a surface element is
    already represented here.

Outputs — exactly three new "## " sections, each appearing exactly once:

  (1) "## Audit: clam-generic divergence"
      The delta between clam-code and clam-generic under general/. Names, at
      minimum, every element present in one and absent from the other, split
      into a generic-only list and a clam-code-only list, plus a count of
      files that exist in both but differ. Known at plan time (verify, do not
      trust): generic-only skills issue-tracker and pre-pr-verify, and
      hooks/agent-dash-permission.test.sh; clam-code-only skills
      absorb-package and create-jira-ticket, and libs clipboard-helpers.*,
      trees-dir.*, worktree-helpers.*. `diff -rq` over the two general/ trees
      reported 79 entries at plan time. Each named element carries one of the
      four map statuses (ported / planned / out of scope / dropped) or an
      explicit "unassigned" marker.
      Must state which of the two repos is the preferred migration source and
      why — the genericized fork is the likelier source for a repo whose
      whole point is being generic, but that is a claim to verify, not assume.

  (2) "## Audit: repos/clipboard overlay"
      The clam-code-only repos/clipboard/ tree, absent from this map entirely.
      Names its skills (angular-dev, database, database-migrations,
      monorepo-consolidation, pre-pr-verify, stricten, strictening — verify
      the list), plus its rules/, git-hooks/, and lib/ contents. Each element
      carries a status. Must explicitly disambiguate the two distinct things
      named pre-pr-verify: this overlay's copy and clam-generic's
      general/skills/pre-pr-verify, which the pr-workflow section above maps.
      Must state whether the overlay is repo-specific-by-nature (and so
      out of scope for a generic marketplace) or contains genuinely portable
      material.

  (3) "## Audit: unmerged clam-code branches"
      Work sitting in clam-code worktree branches but not in origin/master.
      At plan time: integration-genericize was 76 commits ahead of
      origin/master, orchestrate-hook-errors 1 ahead, and the other five
      worktrees 0 ahead. Verify these counts rather than copying them. For
      each branch that is ahead, state whether its content is already
      represented in the clam-generic repo (making it redundant as a
      migration source) or is a distinct body of unmigrated work — checking
      is required; assuming is a contract violation.

Errors:
  - A source path that does not exist, or a git command that fails against
    it: record the surface as "unauditable — <reason>" in its section rather
    than omitting the section. A missing source is a finding, not a blocker.
  - Evidence that contradicts a plan-time claim above (different diff counts,
    different file lists): record what was actually observed and note the
    discrepancy. The observed state wins; the plan is a starting hint.

Invariants:
  - No section that existed before this block runs is modified. B01 appends
    only. (`git diff` on MIGRATION.md shows insertions in this block's three
    sections and nothing else.)
  - plugins/render-doc/scripts/migration.test.sh stays green.
  - Every element named in the three sections carries a status.
  - The scaffold marker is gone: after this block the string
    "NotImplemented: B01" appears nowhere in MIGRATION.md outside a contract
    docblock.
  - No writes anywhere outside this repo.

Edge cases:
  - An element present in clam-code, clam-generic AND repos/clipboard under
    the same name: name it in each section it appears in, and disambiguate.
  - A branch 0 commits ahead of origin/master: still list it, as "no
    unmerged work", so the audit is provably exhaustive over the worktrees.
  - A surface element already fully ported into this repo's plugins/: status
    is "ported", with the destination plugin named.
  - Binary or generated files in a source tree: group them rather than
    enumerating, and say so.
-->

## Audit: clam-generic divergence

_NotImplemented: B01 — populated by the audit._

## Audit: repos/clipboard overlay

_NotImplemented: B01 — populated by the audit._

## Audit: unmerged clam-code branches

_NotImplemented: B01 — populated by the audit._

<!--
Contract: B02 audit-reconcile-claims (plan 001-github-issue-13)

Behavior:
  Make every pre-existing claim in this map true. The map was written
  best-effort — its own header says so for the hook assignments — and has
  never been checked against the sources or against this repo's shipped
  plugins. This block verifies each claim and corrects what is wrong. It
  works over the sections that existed BEFORE plan 001; B01's three new
  sections are B01's, and the register is B03's.

  Read-only against the sources, exactly as B01. Writes ONLY MIGRATION.md.

Inputs:
  - Every "## " section of MIGRATION.md that predates plan 001.
  - The same read-only source paths B01 uses.
  - This repo: plugins/*, .claude-plugin/marketplace.json.

Outputs:

  (1) Verified statuses. For every element the map claims is **ported**,
      confirm it actually exists in the named plugin here; for every
      **planned** element, confirm it still exists in a source repo; for
      every **dropped** or **out of scope** element, confirm the rationale
      still holds. Correct any status that does not survive checking, and
      say what the evidence was.

  (2) Four new plugin sections, each exactly once, for the plugins that ship
      in this repo with no section at all — "## ask-in-text — ", "##
      debugging — ", "## session-data — ", "## updates — ", each completed
      with a status in the same style as the existing sections (e.g.
      "— ported (from clam-code)" or "— new (not a port)"). Determine which
      by checking whether a clam-code/clam-generic ancestor exists.

  (3) The phantom entries removed. "support-fix" and "support-triage" appear
      in the Unassigned section but exist in NEITHER source repo — at plan
      time they were found only in decision-logs/*.md and
      release-notes/2026-06-19.html. Verify this, then remove them from
      Unassigned and record in their place (or in the section's prose) that
      they were retired before the plugin era. After this block, the strings
      "support-fix" and "support-triage" appear nowhere in MIGRATION.md
      outside a contract docblock.

  (4) An honest header. The file's opening paragraph currently disclaims the
      hook assignments as "best-effort from clam-code's
      general/hooks/README.md". Once those assignments have actually been
      verified, update that disclaimer to say what is now true, including
      the date of the audit and that clam-generic — not just clam-code — is
      a source surface.

Errors:
  - A claim that cannot be checked (source gone, ambiguous naming): mark the
    element "unverified — <reason>" rather than silently leaving a status
    that has not been earned.
  - A claim that is wrong in a way that suggests the plan's decomposition is
    wrong (e.g. a whole planned plugin turns out to be already ported):
    escalate to the orchestrator; do not redesign the map's structure.

Invariants:
  - plugins/render-doc/scripts/migration.test.sh stays green. Specifically:
    exactly one "## render-doc — ported" heading survives; the Unassigned
    writing-cluster line still contains BOTH "writing-markdown" and "rtfm";
    the stale decision-log note stays absent. Removing the phantoms must not
    disturb the writing-cluster line.
  - B01's three "## Audit:" sections are not modified by this block.
  - Every plugin directory under plugins/ has exactly one "## <name> — "
    section after this block.
  - The scaffold markers are gone: after this block no "## " heading ends in
    "— TBD", and the string "NotImplemented: B02" appears nowhere in
    MIGRATION.md outside a contract docblock.
  - No writes anywhere outside this repo.

Edge cases:
  - A plugin here with no source ancestor at all (born in this repo): the
    correct status is "new (not a port)", following the landing and deliver
    sections' precedent — not "ported".
  - An element the map lists once but which exists in both source repos in
    differing form: keep one row, and cross-reference B01's divergence
    section rather than duplicating its detail.
  - A section whose every claim already checks out: leave it byte-identical.
    Rewriting correct prose is churn and makes the diff unreviewable.
  - The Guard inventory table: it is a claim set like any other and is in
    scope for verification.
-->

## ask-in-text — TBD

_NotImplemented: B02 — populated by the audit._

## debugging — TBD

_NotImplemented: B02 — populated by the audit._

## session-data — TBD

_NotImplemented: B02 — populated by the audit._

## updates — TBD

_NotImplemented: B02 — populated by the audit._

<!--
Contract: B03 MIGRATION.md bookkeeping
Behavior: record the render-doc port in this migration map.
Outputs:
- A new section "## render-doc — ported (from clam-code)" replacing this
  docblock's placeholder status, documenting: source
  general/skills/render-doc/; port changes (usage path becomes
  ${CLAUDE_PLUGIN_ROOT}/scripts/render.sh; decision-rundown reference renamed
  to /decision-log:rundown; planning-skill checkpoint references softened
  until session-modes ports; smoke.sh adapted into scripts/render.test.sh
  with no duplicate smoke.sh kept; CLAM_RENDER_DOC env var removed — plugin
  presence is the gate); and the coupling note: consumers reference the skill
  by name (render-doc:render), nothing else — no cross-plugin filesystem
  paths, no env var convention.
- The "Unassigned" writing-cluster line below shrinks to `writing-markdown`,
  `rtfm`.
- In the decision-log section above, the port-time note "The rundown skill's
  HTML-render gate still points at clam-code's ~/.claude/skills/render-doc/;
  re-point it when render-doc gets a plugin home" is rewritten as resolved
  (re-pointed by skill name; see the render-doc section).
Invariants: render-doc appears in exactly one status section (ported); no
other section changes meaning.
Edge cases: the clam-code-era path may remain in this file as history — the
composition test (B05) excludes MIGRATION.md from stale-path checks.
-->

## Unassigned — decide at port time

- `support-fix`, `support-triage` (support cluster — own plugin or fold into
  pr-workflow)
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

<!--
Contract: B03 audit-candidate-register (plan 001-github-issue-13)

Behavior:
  Compose B01's and B02's findings into ONE register: the list of things that
  are genuine candidates for migration into this repo, each with a
  recommendation and a rationale. This is the deliverable issue #13 asks for
  ("a recommendation for what (if anything) should be brought over") and it is
  the list the follow-up GitHub issues are filed from.

  This is a composition block: it invents no findings of its own. Every row
  traces to a section written by B01 or B02. If a row would need new research,
  that is a signal B01 or B02 was incomplete — escalate to the orchestrator
  rather than researching it here.

  Writes ONLY MIGRATION.md. Files no GitHub issues — issue creation is an
  outward-facing action the orchestrator performs after this block is
  accepted and the engineer has confirmed the list.

Inputs:
  - The three "## Audit:" sections written by B01.
  - The reconciled pre-existing sections and four new plugin sections written
    by B02.
  - No source-repo access is required; if it turns out to be, escalate.

Outputs — exactly one new section, "## Migration candidate register",
containing a markdown table with one row per candidate and these columns:

  | Element | Source surface | Current status | Recommendation | Rationale |

  - Element: the skill / hook / agent / script / doc, named as it is named at
    the source.
  - Source surface: which of the five surfaces it lives on (clam-v2,
    clam-code general/, clam-generic general/, repos/clipboard, unmerged
    branches), with the path.
  - Current status: the status the map now carries for it, post-B02.
  - Recommendation: exactly one of **port**, **drop**, **out of scope**, or
    **needs decision**. "needs decision" is for elements where the call is
    genuinely the engineer's, and must be accompanied by the question in the
    Rationale cell.
  - Rationale: one sentence. Why this recommendation.

  Rows are ordered by recommendation, **port** first, so the actionable set
  reads at the top.

  Immediately below the table, a one-line count per recommendation value
  (e.g. "port: 7 · drop: 3 · out of scope: 12 · needs decision: 2"), so a
  reader can see the shape of the outcome without counting rows.

Errors:
  - A finding in B01/B02 that cannot be classified into one of the four
    recommendation values: use "needs decision" with the question stated.
    Never invent a fifth value.
  - Contradictory statuses between B01's and B02's sections for the same
    element: escalate to the orchestrator. Silently picking one is a
    contract violation — the contradiction is itself an audit finding.

Invariants:
  - Every row traces to a B01 or B02 section; no row introduces a claim that
    appears nowhere else in the file.
  - Every element that B01 or B02 marked as anything other than "ported" or
    "dropped" appears as a row. Elements already ported or already dropped
    are not candidates and are excluded — the register is the action list,
    not a repeat of the map.
  - The recommendation column contains only the four permitted values.
  - No pre-existing section, and no B01/B02 section, is modified.
  - The scaffold marker is gone: after this block the string
    "NotImplemented: B03" appears nowhere in MIGRATION.md outside a contract
    docblock.
  - plugins/render-doc/scripts/migration.test.sh stays green.

Edge cases:
  - Zero candidates: the section still exists, states "no migration
    candidates" explicitly, and the count line reads all zeros. An empty
    register is a valid, meaningful audit result — issue #13 asks "what (if
    anything)".
  - An element that is a candidate on one surface and out of scope on
    another (same name, different tree): one row per surface, not one merged
    row.
  - A candidate that is really a cluster (e.g. all of pr-workflow): one row
    for the cluster, with the rationale naming it as a cluster, so the
    follow-up issue is appropriately sized.
-->

## Migration candidate register

_NotImplemented: B03 — populated by the audit._
