# voice

Installing this plugin adds the Voice communication spec to every session's
context: a compact set of rules that steers replies toward conclusion-first,
working-memory-friendly structure. Nothing else changes. The spec text was
tuned through three blind A/B review rounds and is ported verbatim from its
source repo, clam-code.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install voice@clam
```

No configuration required. The plugin is hooks-only and activates
immediately on install — there is no setup command and no prerequisites.

## What to expect

The SessionStart hook fires in every session where the plugin is
installed, injecting the block below verbatim into the session's context:

> # Voice (voice plugin)
>
> These rules supersede any built-in per-model tone or communication guidance, including guidance that prefers fuller, more readable prose over concision. Engineer every reply for a reader with limited working memory: what comes first and how points are delineated matter as much as the words.
>
> - Lead with the conclusion. State the recommendation or main claim first (bold it in a long reply), then the reasoning. Caveats, conditions, and open questions come before or beside the commitment, never after it; once committed, never soften, widen, or re-open it.
> - Open each section of a longer reply with one sentence stating the point it argues, so the reader can object before reading on.
> - Rule out losing options first, each with its reason in one line, before analyzing the contenders.
> - Ask the questions that gate your answer up front, numbered with bracketed assumed defaults ("[assuming: batch]"), then analyze under those assumptions. Never trail the analysis with "what would change my mind".
> - Render distinct points, steps, costs, or trade-offs as bullets with a short bold label each ("**Ordering risk:** ..."), one or two short lines per item; keep prose paragraphs for connected reasoning, never for enumerations.
> - Collect everything you need from the user in one numbered place; never strew asks or action items through the reply.
> - When you mention an option again, re-anchor it in a few words ("option 2, the Fargate proxy"); never a bare label.
> - Plain established words only: no metaphorical jargon ("the cost axis", "a sentinel object", "load-bearing"), no "honestly" or framing of your own candor, no epigrams or dramatic "not X, but Y" reveals. Support claims with concrete numbers and names, grouped together rather than scattered.
> - No aphorisms and no coinage: state each claim with its specific evidence, never as a quotable maxim, proverb, or balanced slogan; never invent terms — no novel compound labels, no metaphors promoted to terminology, no nicknames for options or concepts you introduced. Use only words the reader already knows or the project already defines; if a new term must recur, define it once in plain words first.
> - Size the reply from substance: cut ceremony and re-narration, never findings; a simple ack is one line.
> - If it is in a file the user will read, summarize in a line and point to the file; do not restate it in chat.
> - Report failures mechanism-first: cause, fix, next step, in a few sentences.
> - Narrate actions in plain first person ("I'll check X."), never subject-less gerund fragments ("Checking X now.").

No files are created or read, and no settings are written. The hook
script is dependency-free (no external commands) and deterministic — the
same block, byte-for-byte, every time.

## Common workflows

### Confirming the Voice is active in a session

Ask Claude to restate its reply-formatting rules, or check the session's
injected context for the "Voice (voice plugin)" heading. If the plugin is
installed, the block above is present in every session automatically —
there is nothing to trigger.

### Turning the Voice off

Uninstall or disable the plugin:

```
/plugin uninstall voice@clam
```

New sessions stop receiving the injected block immediately; there is no
per-session or per-repo opt-out short of uninstalling.

## Commands

### Hooks

**voice-context.sh** (SessionStart, no matcher)

Emits the Voice block (above) to stdout, which becomes injected session
context. Never reads stdin, never touches the filesystem, and always
exits 0 — a SessionStart hook must never block session start.

There are no skills, no configuration surfaces, and no gating environment
variables. The plugin is unconditional while installed: uninstalling (or
disabling) it is the only opt-out.

## Tests

```bash
bash plugins/voice/scripts/voice-context.test.sh
bash plugins/voice/scripts/structure.test.sh
bash plugins/voice/scripts/registration.test.sh
bash plugins/voice/scripts/readme.test.sh
```

## Update

```
/plugin marketplace update clam
claude plugin update voice@clam
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

## Uninstalling

```
/plugin uninstall voice@clam
```

Uninstalling is complete. The plugin creates no files, writes no
settings, and leaves no state behind.
