<!--
SCAFFOLD Contract: B16 tracking-readme (plan 002-readme-conformance)
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
  (/plugin marketplace add cjdubb/clam; /plugin install tracking@clam).
  Uninstalling opens with /plugin uninstall tracking@clam plus any cleanup.
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
  Current H2s: How it works, Knobs, Soft integrations, Install. Install ->
  Getting started; How it works -> What to expect; the Knobs table (10 env
  vars) DISSOLVES per config doctrine — each var with the hook that reads
  it, summary table at the end of Commands, env-block instruction for
  hand-set vars; Soft integrations -> Relationships; Commands MUST document
  the /tracking:make-progress skill (currently undocumented) and the
  .local/ tracking-doc lifecycle; Common workflows: start tracked work,
  resume after a restart/compaction, park on a decision.
-->

# tracking

The tracking-document approach from clam-code, as a standalone plugin:
`.local/TODO.md` in each worktree is the session's single source of truth,
updated in real time, so session state survives compaction, `/clear`, and
orchestrator handoff — a fresh session reads the tracking docs and picks up
exactly where the last one parked. The same files power the
[agent-dash](https://github.com/cjdubb/clam-agent-dashboard) and the
statusline plugin's State segment.

## How it works

- **SessionStart** (`scripts/session-context.sh`) injects the Work Management
  rules as context — the plugin replacement for clam-code's system-prompt
  injection — and, when `.local/TODO.md` already exists, surfaces its State
  and Current Task with an instruction to resume from the docs, not restart.
- **Stop** (`scripts/keep-working.sh`) enforces the state lifecycle: a turn
  may end only in `Complete`, a needs-user state (`Blocked`,
  `Waiting For Decision` — with its decision-file nudge), or a parked
  `Awaiting *` state. `In Progress` gets nudged to continue; unrecognised
  states get the exact valid list so a near-miss self-corrects instead of
  being rationalised into a false `Complete`.
- **Stop/UserPromptSubmit** (`scripts/awaiting-user.sh`) maintains the
  `.local/.awaiting-user` marker consumers use for summons-epoch semantics.
- **PreToolUse** (`scripts/block-task-tools.sh`) denies the built-in
  TaskCreate/TaskUpdate/TaskList/TaskGet tools: they write to
  `~/.claude/tasks/`, which the tracking docs, agent-dash, and the statusline
  never see. The deny message redirects tracking to `.local/TODO.md`.
  TeamCreate and the other team-coordination tools are not matched.
- **`lib/states.tsv`** is the canonical State manifest (13 states; category,
  emoji, colour, summons). `lib/states.sh` holds the shared readers
  (`todo_field`, `state_category`, …). The statusline plugin vendors a copy —
  keep them in lockstep.
- **`templates/TODO.md`** is the tracking-doc skeleton.

## Knobs

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAM_TRACKING_STOP_GATE` | `enabled` | `disabled` turns off the Stop-hook enforcement entirely. |
| `CLAM_TRACKING_TASK_TOOLS_GATE` | `enabled` | `disabled` turns off the built-in task-tools deny. |
| `CLAM_PR_CRONS` | `disabled` | `enabled` blocks parking/completing with an open PR that has no monitoring cron (needs the pr-workflow plugin's create-pr watch crons; opt-in here, unlike clam-code where unset meant enabled). |
| `CLAM_INDEPENDENT_REVIEW` | `disabled` | `enabled` blocks human-handoff states without an independent-review report (needs the independent-review skill). |
| `CLAUDE_STOP_LOG` | `~/.claude/stop-log.jsonl` | Stop-hook audit log location. |

## Soft integrations

All optional; everything degrades gracefully when absent:

- **decision-log plugin** — `Waiting For Decision` parks expect a
  `.local/decisions/NNN-<slug>.md` file per `/decision-log:rundown`.
- **notifications plugin** — bell, desktop notification, tmux highlight, and
  phone push on summoning transitions; its idle-event backstop delivers the
  push even when the `notify` shell helper is not installed.
- **statusline plugin** — shows the State segment; **agent-dash** — reads the
  same files for its dashboard.

## Install

```
/plugin marketplace add cjdubb/clam
/plugin install tracking@clam
```

Installing changes nothing globally; the hooks apply only where the plugin is
enabled. Sessions without a `.local/TODO.md` skip the Stop-hook enforcement
(ad-hoc sessions stay ad-hoc); the task-tools deny is the one hook that fires
regardless, since tracking anywhere but `.local/TODO.md` is exactly what it
exists to prevent.
