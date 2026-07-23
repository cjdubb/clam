<!--
SCAFFOLD Contract: B11 notifications-readme (plan 002-readme-conformance)
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
  (/plugin marketplace add cjdubb/clam; /plugin install notifications@clam).
  Uninstalling opens with /plugin uninstall notifications@clam plus any cleanup.
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
  Current H2s: How it works, Agent-side notify, Knobs, Soft integrations,
  Install, Tests. Install -> Getting started; How it works -> What to
  expect; agent-side notify -> Commands plus a Common workflows recipe;
  the Knobs table DISSOLVES per config doctrine — each of the 7 env vars
  documented with the hook/path that reads it, summary table at the end of
  Commands, and an exact settings-env-block instruction for hand-set vars
  (CLAUDE_PUSH_NTFY_TOPIC is required for pushes; say so); Soft
  integrations -> Relationships; Tests -> optional slot.
-->

# notifications

The summoning stack from clam-code, as a standalone plugin: turn the tracking
plugin's summoning states (`Blocked`, `Waiting For Decision`,
`Awaiting User Review`) into a terminal bell, a desktop notification, a tmux
pane highlight, and an [ntfy](https://ntfy.sh) phone push — ringing once on
the *transition* into a summoning state, and staying silent for parked
sessions that resume on their own (`Awaiting CI`, `Awaiting Human Review`, …).

## How it works

- **Notification** (`scripts/notify.sh`) — local attention-grabber for
  permission prompts and 60s idle events: bell (via `terminalSequence`),
  desktop toast, tmux pane-border tint. Suppressed when the session is parked
  and not summoning.
- **Notification** (`scripts/push-notify.sh`) — ntfy phone push. Permission
  prompts always page; idle events page only in a summoning state (the
  clam-code#264 leak fix). Plan mode suppresses everything. Delegates to
  `lib/notify.sh`'s `notify()` — one source of truth for the push logic.
- **Stop** (`scripts/stop-notify.sh`) — rings only on the transition into a
  summoning state, tracked per worktree in `.local/.last-stop-state`. A
  re-stop in the same summoning state stays silent; `.local/.silent-stop`
  forces one silent turn (for watch crons that polled and found nothing new).
- **UserPromptSubmit** (`scripts/prompt-timestamp.sh`) — records per-worktree
  and global prompt timestamps (elapsed-turn time in notifications; the
  cross-worktree activity gate) and clears the transition marker so a fresh
  summons after the user replies rings again.
- **UserPromptSubmit** (`scripts/capture-permission-mode.sh`) — captures the
  session's permission mode to `.local/.permission-mode`; `push-notify.sh`
  reads it to suppress pushes in plan mode (agent-dash displays it too).
- **`lib/states.sh` / `lib/states.tsv`** — VENDORED copy of the state
  manifest; canonical home is the tracking plugin. Keep in lockstep.

## Agent-side `notify` (instant pushes)

A plugin cannot inject shell functions, so the `notify()` helper the agent
calls when it parks in a summoning state is optional here. Without it the
push still arrives via the idle-event backstop, just up to ~60s later: the
agent parks, `stop-notify.sh` rings locally, and the 60s idle Notification
reaches `push-notify.sh`, whose state gate passes for summoning states.

For instant pushes, source the lib into your interactive shell:

```bash
# .bashrc / .zshrc
source ~/.claude/plugins/marketplaces/clam/plugins/notifications/lib/notify.sh
```

(Adjust the path to wherever your marketplace clone lives; the lib is
bash-and-zsh safe.)

## Knobs

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAM_NOTIFICATIONS_GATE` | `enabled` | `disabled` turns off every hook in this plugin. |
| `CLAUDE_PUSH_NTFY_TOPIC` | unset | Required to enable pushes. Topic name = password — must be unguessable. |
| `CLAUDE_PUSH_NTFY_SERVER` | `https://ntfy.sh` | ntfy server override. |
| `CLAUDE_PUSH_DEBOUNCE_SECONDS` | `120` | Per-worktree push cooldown. |
| `CLAUDE_PUSH_ACTIVITY_GATE_SECONDS` | `30` | Skip pushes when the user prompted any session this recently (0 disables). |
| `CLAUDE_PUSH_DEDUP` | `1` | Suppress a push byte-identical to the last one sent for the worktree (0 disables). |
| `CLAUDE_PUSH_BODY_MODE` | unset | `minimal` strips TODO state and tmux info from push bodies. |
| `CLAUDE_PUSH_SILENT_STOP_WINDOW_SECONDS` | `90` | Idle pushes are suppressed this long after a silent stop. |
| `CLAUDE_NOTIFY_SOUND` | `default` | macOS notification sound name. |

## Soft integrations

All optional; everything degrades gracefully when absent:

- **tracking plugin** — supplies `.local/TODO.md` and the state lifecycle
  that drives every gate here. Without it there are no summoning states, so
  this plugin falls back to unconditional permission-prompt/idle behaviour.
- **agent-dash** — reads `.local/.permission-mode`.

## Install

```
/plugin marketplace add cjdubb/clam
/plugin install notifications@clam
```

Installing changes nothing globally; the hooks apply only where the plugin is
enabled, and without `CLAUDE_PUSH_NTFY_TOPIC` the push path is a no-op (the
local bell/desktop/tmux signals still work).

## Tests

```
bash scripts/push-notify.test.sh
bash scripts/stop-notify.test.sh
bash lib/notify.test.sh
bash lib/desktop-notify.test.sh
```

All hermetic: curl/osascript/notify-send/paplay are PATH-shimmed, no network.
