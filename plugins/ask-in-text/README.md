# ask-in-text

Blocks the AskUserQuestion picker UI and redirects Claude to ask numbered
plain-text questions in the conversation instead. When Claude needs input,
it asks directly in the chat — numbered, one decision per question, each
with a recommended default — so the engineer can reply efficiently
("1: A, 2: B") or accept all defaults with a bare "go".

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install ask-in-text@clam
```

No configuration required. The plugin is hooks-only and activates
immediately on install — there is no setup command, no config file, and no
prerequisites.

## What to expect

Both hooks start firing right away in every session where the plugin is
installed:

- **PreToolUse (AskUserQuestion):** denies every `AskUserQuestion` tool
  call with exit 2 and a one-line stderr redirect. This fires for
  top-level and subagent tool calls alike, so no session can invoke the
  picker UI.
- **SessionStart:** injects a short (~700-byte) markdown convention block
  into the session context. The block reads:

  > **Question-Asking Convention (ask-in-text plugin)**
  >
  > Never call the AskUserQuestion tool. It is blocked in this environment
  > by the ask-in-text plugin's PreToolUse gate — do not attempt it, do
  > not retry it.
  >
  > Ask the engineer questions in the conversation as plain text instead:
  >
  > - Use numbered questions (1., 2., ...), one decision per number, so a
  >   reply like "1: A, 2: B" resolves unambiguously.
  > - Give a recommended default per question, with a one-line rationale
  >   or trade-off where it helps.
  > - Keep each question decidable at a glance — no walls of text.
  >
  > A bare "go" or "confirmed" accepts all the recommended defaults.

No files are created or read. No settings are written. Both hook scripts
are dependency-free (no `jq`, no external commands) and produce
deterministic output.

## Common workflows

### Answering a batch of questions

When Claude asks numbered questions, reply with the number and your choice:

```
1: A, 2: B
```

To accept every recommended default, reply with just:

```
go
```

### Getting the picker UI back

Uninstall or disable the plugin:

```
/plugin uninstall ask-in-text@clam
```

The AskUserQuestion tool becomes available again immediately in new
sessions.

## Commands

### Hooks

**block-question.sh** (PreToolUse, matcher: `AskUserQuestion`)

Unconditionally denies the `AskUserQuestion` tool call (exit 2). Writes a
single-line message to stderr naming the blocked tool and instructing
Claude to ask in plain text with numbered questions instead. Never reads
stdin, writes to stdout, or touches the filesystem.

**questions-context.sh** (SessionStart, no matcher)

Emits the standing question-asking convention to stdout so it appears in
every session's context. Never reads stdin, writes to stderr, or touches
the filesystem. Always exits 0.

There are no skills, no configuration surfaces, and no gating environment
variables — by design. The plugin is unconditional while installed;
uninstalling (or disabling) it is the only opt-out.

## Tests

```bash
bash plugins/ask-in-text/scripts/block-question.test.sh
bash plugins/ask-in-text/scripts/questions-context.test.sh
bash plugins/ask-in-text/scripts/structure.test.sh
bash plugins/ask-in-text/scripts/registration.test.sh
```

## Update

```
/plugin marketplace update clam
claude plugin update ask-in-text@clam
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

None required. This plugin is fully standalone.

It follows the same PreToolUse deny pattern that the tracking plugin uses
for its task-tools gate (`block-task-tools.sh`), but has no dependency on
tracking and can be installed independently. Its numbered-question
convention — recommended default per question, bare "go" accepts all
defaults — is consistent with the tracking plugin's decision-format
guidance, reinforcing the same interaction style without requiring it.

## Uninstalling

```
/plugin uninstall ask-in-text@clam
```

Uninstalling is complete. The plugin creates no files, writes no settings,
and leaves no state behind.
