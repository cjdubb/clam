# notifications

The summoning stack from clam-code, as a standalone plugin: turn the tracking
plugin's summoning states (`Blocked`, `Waiting For Decision`,
`Awaiting User Review`) into a terminal bell, a desktop notification, a tmux
pane highlight, and an [ntfy](https://ntfy.sh) phone push — ringing once on
the *transition* into a summoning state, and staying silent for parked
sessions that resume on their own (`Awaiting CI`, `Awaiting Human Review`, …).

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install notifications@clam
```

No additional configuration is required to install. Installing changes
nothing globally — the hooks only fire in sessions where the plugin is
enabled, and the local signals (bell, desktop toast, tmux pane highlight)
work immediately. Phone pushes are opt-in and need one hand-set variable;
see `CLAUDE_PUSH_NTFY_TOPIC` under Commands to turn them on.

## What to expect

Once installed and enabled (`CLAM_NOTIFICATIONS_GATE` is not `disabled`),
three hook events start firing:

- **Notification** (permission prompts, the 60s idle-wait event) — a
  terminal bell, a desktop toast, and a yellow tmux pane-border tint fire
  locally; an ntfy phone push fires too when `CLAUDE_PUSH_NTFY_TOPIC` is
  set.
- **Stop** (every turn end) — the same three local signals, but only on the
  *transition* into a summoning state (`Blocked`, `Waiting For Decision`,
  `Awaiting User Review`); a re-stop in the same summoning state, or any
  non-summoning state, stays silent.
- **UserPromptSubmit** (every prompt you send) — records timestamps used to
  report elapsed time and gate cross-worktree push activity, and captures
  the session's permission mode for `push-notify.sh` and agent-dash to
  read.

State-aware gating reads the tracking plugin's `.local/TODO.md` State field
through the vendored `lib/states.sh`. Without a tracking plugin, or without
a TODO.md, there are no summoning states to gate on, so the plugin falls
back to firing unconditionally on every permission prompt and idle
event — a noisier default, but never a silent one. `CLAM_NOTIFICATIONS_GATE=disabled`,
set before the session launches (hooks never see exports made mid-session),
turns off every hook in the plugin.

## Common workflows

### Enable phone pushes

Phone pushes need a private ntfy topic. Set it in the `env` block of the
settings file at the scope where notifications is installed (project,
user, or local `settings.json`):

```
CLAUDE_PUSH_NTFY_TOPIC=<a-hard-to-guess-topic-name>
```

The topic name doubles as the password for anyone who knows it, so pick
something unguessable. Once set, permission prompts page immediately, and
idle events page while the tracking plugin's State is `Blocked`,
`Waiting For Decision`, or `Awaiting User Review`. Tune the server,
debounce, and other push behavior with the remaining env vars under
Commands.

### Get instant pushes instead of waiting up to 60s

Without any extra setup, a push still arrives via the idle-event backstop:
the agent parks, `stop-notify.sh` rings locally, and the next 60s idle
Notification reaches `push-notify.sh`, whose state gate passes for
summoning states. For an instant push the moment the agent parks, source
the library into your interactive shell so the agent can call it directly:

```bash
# .bashrc / .zshrc
source ~/.claude/plugins/marketplaces/clam/plugins/notifications/lib/notify.sh
```

(Adjust the path to wherever your marketplace clone lives; the lib is
bash-and-zsh safe.)

### Silence one noisy turn

A cron-driven turn that polled and found nothing worth surfacing shouldn't
ring. Touch `.local/.silent-stop` in the worktree before the turn ends:
`stop-notify.sh` consumes (deletes) the flag on that Stop and stays
silent, and `push-notify.sh` also suppresses the following idle push for
`CLAUDE_PUSH_SILENT_STOP_WINDOW_SECONDS` (default 90s). The transition
marker is left untouched, so the next Stop in that same summoning state
still rings.

### Turn off the plugin for a session

Set `CLAM_NOTIFICATIONS_GATE=disabled` before launching the session (hooks
don't see mid-session exports) to turn off every hook this plugin
installs.

## Commands

### Hooks

**Notification** (permission prompts, the 60s idle-wait event):

- `scripts/notify.sh` — local attention-grabber: bell (via
  `terminalSequence`), desktop toast, tmux pane-border tint. Suppressed
  when the session is parked and not summoning, per the State read from
  `.local/TODO.md` via `lib/states.sh`; a missing lib degrades to always
  firing.
- `scripts/push-notify.sh` — ntfy phone push; a no-op unless
  `CLAUDE_PUSH_NTFY_TOPIC` is set. Permission prompts always page. Idle
  events page only when the session's State is a summoning state
  (`Blocked`, `Waiting For Decision`, `Awaiting User Review`) — this is
  the fix for the clam-code#264 leak, where idle pushes used to fire for
  parked-but-not-summoning states too. Plan mode
  (`.local/.permission-mode` == `plan`) suppresses every push, including
  permission prompts. `.local/.silent-stop` suppresses idle-class pushes
  for the rest of the turn. Delegates to `lib/notify.sh`'s `notify()`
  function.

**Stop** (every turn end):

- `scripts/stop-notify.sh` — rings the bell, desktop toast, and tmux
  border only on the *transition* into a summoning state, tracked per
  worktree in `.local/.last-stop-state`; a re-stop in the same summoning
  state stays silent. Touching `.local/.silent-stop` before the turn ends
  forces one silent turn regardless of State — the hook consumes
  (deletes) the flag and records `.local/.last-silent-stop`, which
  `push-notify.sh` reads.

**UserPromptSubmit** (every prompt you send):

- `scripts/prompt-timestamp.sh` — records a per-worktree and a global
  prompt timestamp under `/tmp/claude-prompt-timestamps/` (elapsed-turn
  time in notification bodies; the cross-worktree activity gate in
  `lib/notify.sh`), and clears the Stop-hook transition marker so a fresh
  summons after you reply rings again.
- `scripts/capture-permission-mode.sh` — writes the session's permission
  mode to `.local/.permission-mode`; `push-notify.sh` reads it to suppress
  pushes in plan mode, and agent-dash displays it too.

### Library

- `lib/notify.sh` — exports the `notify <worktree-name> [worktree-dir]`
  function, the single source of truth for push logic; `push-notify.sh`
  sources it for every push, and you can source it into an interactive
  shell yourself (see Common workflows) to call it directly. Resolves the
  worktree's directory from the explicit argument (or `$PWD`), then a scan
  of `$AGENT_DASH_ROOTS`, then a `/tmp` fallback, so it never mints a
  ghost `.local/`. Reads `.local/TODO.md` for a rich body on `Blocked` /
  `Waiting For Decision` / `Awaiting User Review`, appends the tmux
  session/window/pane when available, and applies the debounce,
  activity-gate, and dedup knobs below before sending.
- `lib/desktop-notify.sh` — cross-platform desktop toast: `osascript` on
  macOS (using the `CLAUDE_NOTIFY_SOUND` sound name), `notify-send` +
  `paplay` on Linux, a silent no-op otherwise.
- `lib/states.sh` / `lib/states.tsv` — a vendored copy of the clam
  workflow State manifest; canonical home is the tracking plugin. Keep the
  two copies in lockstep.

### Env vars

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

None of these have a setup command that writes them — set any of them by
hand in the `env` block of the settings file at the scope where
notifications is installed.

## Tests

```bash
bash scripts/push-notify.test.sh
bash scripts/stop-notify.test.sh
bash lib/notify.test.sh
bash lib/desktop-notify.test.sh
```

All hermetic: curl/osascript/notify-send/paplay are PATH-shimmed, no
network.

## Update

```
/plugin marketplace update clam
claude plugin update notifications@clam
```

Both commands are needed: refreshing the catalog never touches an installed
plugin, and updating one is CLI-only — there is no `/plugin update`.
Afterwards run `/reload-plugins` to pick the new version up in the current
session, or restart the session if this plugin ships hooks or agents.

Auto-update is off by default for third-party marketplaces. Even with it
enabled, a plugin that ships hooks stays pinned to the last explicitly
installed version until you run the update command yourself
(anthropics/claude-code#52218).

## Relationships to other plugins

No hard dependencies — this plugin is fully standalone. Without any other
plugin installed, `notify.sh` and `push-notify.sh` fall back to
unconditional permission-prompt/idle firing, since there are no summoning
states to gate on. Two optional integrations:

- **tracking plugin** — supplies `.local/TODO.md` and the State lifecycle
  that drives every summoning gate here. `lib/states.sh` / `lib/states.tsv`
  are a vendored copy of its canonical state manifest.
- **agent-dash** — reads `.local/.permission-mode`, written by
  `scripts/capture-permission-mode.sh`.

This plugin provides the `notify` shell function (`lib/notify.sh`) for
other tooling, or your own shell, to source and call directly.

## Uninstalling

```
/plugin uninstall notifications@clam
```

Uninstalling stops every hook this plugin installs. It does not remove anything they
wrote: `.local/.last-stop-state`, `.local/.silent-stop`,
`.local/.last-silent-stop`, `.local/.permission-mode`, and the push
markers (`.last-push`, `.last-push-body`) in each worktree's `.local/`
(or under `/tmp/claude-push-markers/` when a worktree can't be resolved),
plus the timestamp files under `/tmp/claude-prompt-timestamps/`. If you
sourced `lib/notify.sh` into your shell config (see Common workflows),
remove that `source` line by hand — the plugin doesn't manage it.
