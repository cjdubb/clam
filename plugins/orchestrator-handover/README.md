<!--
SCAFFOLD Contract: B12 orchestrator-handover-readme (plan 002-readme-conformance)
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
  (/plugin marketplace add cjdubb/clam; /plugin install orchestrator-handover@clam).
  Uninstalling opens with /plugin uninstall orchestrator-handover@clam plus any cleanup.
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
  Current H2s: Skill, What it does, Dependencies, Install. Install ->
  Getting started; What it does -> What to expect plus the H1 paragraph;
  Skill (create) -> Commands; Dependencies (worktrees/newtree) ->
  Relationships to other plugins.
-->

# orchestrator-handover

Hands off a discrete sub-effort from an active orchestrator session to a
fresh one: writes a handover document, scaffolds the recipient orchestrator
worktree, and populates its `.local/` — all before the user ever starts the
new session. The orchestrator only ever scaffolds; a worktree becomes a live
orchestrator when a human runs `clam` there and picks `Build`.

## Skill

- **create** (`/orchestrator-handover:create`) — the four-step handover
  procedure: write the handover document to the current worktree's
  `.local/`, create and populate a recipient worktree via `newtree`, write a
  placeholder tracking document for the recipient, and report the path back
  to the user.

Invoke it directly with `/orchestrator-handover:create`, or let Claude Code
invoke it automatically when an active orchestrator session identifies a
discrete sub-effort that deserves its own coordination context.

## What it does

1. Writes `.local/handover-{ISSUE-KEY}.md` in the current worktree, using
   the skill's companion template — a structured document covering
   source-of-truth artifacts, what's done, what's open, decisions pending, a
   proposed work breakdown, cross-unit compatibility notes, and the
   recipient's first move.
2. Creates the recipient worktree with `newtree` (never a ticket-specific
   variant) and populates its `.local/` with a copy of the handover, a
   `MODE` file set to `Build`, and an empty `.orchestrator` marker.
3. Writes a placeholder tracking document into the recipient's `.local/`,
   using the tracking plugin's template format when that plugin is
   installed, or inlining the essential fields when it is not.
4. Reports the created path and hands off — the orchestrator never starts a
   session in the recipient worktree; only the user does.

Issue-tracker-agnostic throughout: it works the same whether the sub-effort
is tracked in GitHub Issues, Linear, Jira, or nothing at all — with no issue
key, a descriptive slug takes its place.

## Dependencies

- **Requires:** the worktrees plugin's `newtree` (or an equivalent shell
  function already sourced) to create the recipient worktree.
- **Soft integrations, all optional:** the tracking plugin's tracking-doc
  template format (falls back to inlined fields when absent); the
  team-review plugin's `orchestrator-guard.sh`, which allows `.local/`
  writes into sibling worktrees (without it, the Write tool may simply
  prompt for confirmation); a session-modes plugin's `/start`, which may
  pick up the handover document automatically (without it, the recipient
  reads it manually as a documented first move).
- **Provides:** the `create` skill only. Installing this plugin changes
  nothing globally.

## Install

```
/plugin marketplace add cjdubb/clam
/plugin install orchestrator-handover@clam
```
