<!--
SCAFFOLD Contract: B10 lego-readme (plan 002-readme-conformance)
This comment IS the unit's contract. It is removed as part of implementation;
the finished README must not contain it.
Behavior:
  Restructure the existing README (below this comment) so it conforms exactly to
  plugins/PLUGIN_README_TEMPLATE.md (the locked template; authoritative for
  every section's semantics and placeholder guidance).
Inputs:
  The template; this plugin's actual sources (.claude-plugin/plugin.json,
  skills/*/SKILL.md, hooks/, scripts/, lib/ as present); the existing README
  content below this comment, if any. Facts come ONLY from these sources —
  never invented. If sources contradict this contract or the template seems
  wrong for this plugin, STOP and escalate to the orchestrator.
Outputs:
  A README whose H2 sections are exactly, in order:
    ## Getting started
    ## What to expect
    ## Common workflows
    ## Commands
    ## Relationships to other plugins
    ## Uninstalling
  Extra H2 sections (## Tests, plugin-specific ones) are allowed ONLY
  between "## Commands" and "## Relationships to other plugins".
  H1 is the plugin name followed by a one-paragraph operational purpose
  statement. Getting started opens with the standard install commands
  (/plugin marketplace add cjdubb/clam; /plugin install lego@clam).
  Uninstalling opens with /plugin uninstall lego@clam plus any cleanup.
Errors:
  n/a (static document). Ambiguity or contradiction -> escalate, never guess.
Invariants:
  - Every substantive fact in the existing README is preserved by
    RELOCATING it under the correct template heading; nothing is merely
    left in place, nothing substantive is dropped.
  - Pre-existing HTML contract comments in the original content are
    preserved verbatim.
  - Config doctrine (no standalone config section): config written by a
    setup command is documented under that command in ## Commands; env vars
    read by a hook are documented inline with that hook; plugins with many
    env vars get a summary table at the end of ## Commands; any var a user
    must set by hand gets an exact instruction to set it in the env block
    of the settings file at the plugin's installation scope.
  - What to expect and Common workflows are written fresh from plugin
    sources per the template's placeholder guidance.
  - This SCAFFOLD comment is deleted; no other file is touched.
Edge cases / plugin-specific mapping:
  Current H2s: Why it works, Install, Getting started, Use, Layout.
  Install -> Getting started; Why it works -> H1 paragraph and/or an extra
  section in the optional slot; Use -> Common workflows (the
  plan -> scaffold -> dispatch flow); Layout -> optional slot; the three
  skills -> Commands. Relationships: verify against sources (worktrees for
  per-unit worktrees, tracking, landing for delivery).
-->

# lego — the lego workflow for Claude Code

A technology-agnostic Claude Code plugin for engineers who want to stay in the
loop. Software is treated as a composition of **lego blocks**: units with a
public interface, a written behavioral contract, and internals the rest of the
system never sees. Blocks are recursive; integration is just a higher-order
block with its own contract and tests.

The engineer and an orchestrator (your main session, presumed frontier-tier)
plan and decompose the deliverable together. The orchestrator scaffolds every
block as a runtime-present, deliberately unimplemented stub carrying its full
contract, then dispatches each work unit through a per-unit pipeline in its
own dedicated git worktree, forked from the integration branch, using cheaper
realm-restricted workers: a **test wave** writes tests against the contract,
an **implementation wave** makes them pass. The orchestrator verifies every
wave against explicit checklists; accepted units merge locally and, under
`main-prs` delivery mode, deliver incrementally as PR groups raised to
master/main. A living block map keeps the engineer's mental model current at
the contract level.

## Why it works

- **Clarify over guess.** The deliverable is what the engineer says it is,
  never inferred from branch names, slugs, or repo archaeology. Ambiguity at
  any level (goal, contract, test) becomes a question or an escalation, not an
  assumption. Planning cannot start until the engineer confirms a restated
  goal.
- **Types are not contracts.** Every stub carries a docblock stating behavior,
  inputs, outputs, errors, invariants, and edge cases. Tests are verified
  clause-by-clause against it; cheap workers execute a spec written at the
  frontier tier, they don't invent one.
- **Realm restriction is mechanical, not vibes.** A PreToolUse hook denies
  test-writers any non-test file and implementers any test file; a post-hoc
  diff check (`scripts/realm-check.sh`) catches what file hooks can't see. An
  implementer structurally cannot weaken a test to get to green.
- **Isolation is mechanical too.** Each work unit is dispatched in its own
  dedicated worktree: a worker cannot even see a sibling block's tests, let
  alone its contract under review. Delivery is incremental — each PR is one
  reviewable chunk of contract + tests + implementation, never a bare stub.
- **Workers never design.** Ambiguity, mis-sized blocks, and wrong-seeming
  tests are escalated to the orchestrator; contract changes go through the
  engineer, always.
- **The engineer can take any block.** Same contract, same tests, same
  acceptance gate; stubs keep every sibling block unblocked meanwhile.

## Install

```
/plugin marketplace add cjdubb/clam
/plugin install lego@clam
```

Enable it for the repos where you want the workflow. **Installing lego changes
nothing globally**: no writes to `~/.claude/CLAUDE.md` or any global settings
beyond Claude Code's own plugin-enablement entry. Plain `claude` in any other
repo is untouched. That is a hard design constraint of this project.

## Getting started

Everything repo-specific — test/build commands, worker models, delivery
mode — comes from one committed config file, **`.claude/lego.json`**. It
does not ship with the plugin and the workflow will not scaffold or
dispatch without it, so setting it up is the first step in any new repo.

You don't have to write it by hand. The first `/lego:plan` in a repo
detects that the config is missing, autodetects candidate commands from
the repo's marker files (`package.json`, `pyproject.toml`, `go.mod`, …),
and asks your consent before writing and committing it. Prefer to do it
yourself? Copy the plugin's `templates/lego.json` to `.claude/lego.json`
and fill in the commands — `commands.test` is the only required field.

Machine-specific values and personal tweaks go in a gitignored
`.local/config.json`, deep-merged over the committed base. Full schema and
merge semantics: `docs/config-schema.md`.

## Use

1. `/lego:plan` — decompose the deliverable into blocks with your
   orchestrator; approve the plan. Creates the committed repo interface
   `.claude/lego.json` (commands, models, delivery mode — inherited by
   every worktree via checkout) plus gitignored `.local/` session state
   (block map, plans), kept out of your tracked tree automatically via
   `.git/info/exclude`. Teams that want the block map shared can remove
   that exclude entry and commit `.local/` deliberately.
2. `/lego:scaffold` — the orchestrator writes stubs + contracts and proves
   the design composes (typecheck > build > lint, whatever your repo has).
3. `/lego:dispatch` — per-unit pipeline: each work unit dispatched in its own
   dedicated worktree for a test wave, verification, implementation wave, and
   acceptance, then a local merge to the integration branch and incremental
   delivery (PR groups raised to master/main under `main-prs` delivery mode).
   You watch the block map; you build any block you claimed.

The workflow is deliberately opinionated with no lightweight path; for work
that doesn't warrant it, use plain `claude`.

## Layout

```
.claude-plugin/   plugin manifest
skills/           plan, scaffold, dispatch
agents/           lego-test-writer, lego-implementer (sonnet by default)
hooks/            PreToolUse realm gate, SessionStart context injection
scripts/          realm.sh (test-family source of truth), realm-check.sh,
                  realm-gate.sh, session-context.sh, worktree.sh (unit
                  worktree lifecycle + delivery)
templates/        starter .claude/lego.json (lego.json) and blocks.md
docs/             config schema / repo-interface spec
```

History: ported from the clam-v2 repo at v0.3.0; skills renamed from
`/clam:lego-*` to `/lego:*` in the move.
