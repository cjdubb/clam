# voice

This plugin ships the Voice communication spec — a compact set of rules that
steers replies toward conclusion-first, working-memory-friendly structure —
as two selectable Claude Code output styles. The spec text was tuned through
three blind A/B review rounds and is ported verbatim from its source repo,
clam-code. The two styles carry the identical spec text and differ only in
the `keep-coding-instructions` frontmatter setting, so their effect can be
compared directly across conversations.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install voice@clam
```

Then pick a style: run `/config`, select **Output style**, and choose one of
the two Voice styles. The selection is saved to `.claude/settings.local.json`
and takes effect after `/clear` or the next session. Installing alone changes
nothing — a style must be selected before it applies.

## What to expect

Two output styles appear in the `/config` picker:

- **Voice** — the spec below with `keep-coding-instructions: true`: Claude
  Code's built-in software engineering instructions (task scoping, comment
  style, security guidance, git safety) stay in the system prompt, with the
  Voice rules layered on top.
- **Voice (no coding instructions)** — the identical spec with
  `keep-coding-instructions: false`: the built-in "Doing tasks" and
  "Executing actions with care" sections are omitted from the system prompt,
  leaving the Voice rules to carry more of the weight.

Whichever style is selected adds this block, verbatim, to the system prompt:

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
> - Plain established words only: no metaphorical jargon ("the cost axis", "a sentinel object", "load-bearing"), no "honestly" or framing of your own candor, no epigrams or dramatic reveal constructions in any form — "not X, but Y", "not just X; Y", "isn't X — it's Y". Support claims with concrete numbers and names, grouped together rather than scattered.
> - No aphorisms and no coinage: state each claim with its specific evidence, never as a quotable maxim, proverb, or balanced slogan; never invent terms — no novel compound labels, no metaphors promoted to terminology, no nicknames for options or concepts you introduced. Use only words the reader already knows or the project already defines; if a new term must recur, define it once in plain words first.
> - The jargon and coinage bans hold for vocabulary you did not choose as much as for your own: when the user, a quoted report, or a teammate message introduces a banned-category term, restate the idea in plain words rather than adopting the term.
> - Size the reply from substance: cut ceremony and re-narration, never findings; a simple ack is one line.
> - If it is in a file the user will read, summarize in a line and point to the file; do not restate it in chat.
> - Report failures mechanism-first: cause, fix, next step, in a few sentences.
> - Narrate actions in plain first person ("I'll check X."), never subject-less gerund fragments ("Checking X now.").

No files are created or read at session time, and the plugin writes no
settings itself — the only setting involved is the `outputStyle` value
Claude Code writes when a style is picked in `/config`. Output styles apply
to the main conversation only; subagents run their own system prompts.

## Common workflows

### A/B testing the two styles

Switch styles between conversations via `/config` → **Output style** (or by
editing the `outputStyle` field in `.claude/settings.local.json`), then
compare replies to similar prompts. The styles differ only in whether Claude
Code's built-in coding instructions remain in the system prompt, so any
behavioral difference is attributable to that setting.

### Confirming a Voice style is active

Run `/config` and check which style is selected under **Output style**, or
ask Claude to restate its reply-formatting rules. A style change takes
effect after `/clear` or a new session, not mid-conversation.

### Turning the Voice off

Select the **Default** output style in `/config`, or uninstall the plugin:

```
/plugin uninstall voice@clam
```

Unlike the plugin's earlier SessionStart-hook delivery, the styles are
opt-in per selection — deselecting is a complete opt-out without
uninstalling.

## Commands

### Output styles

**Voice** (`output-styles/voice.md`, `keep-coding-instructions: true`)

The canonical Voice block layered on top of Claude Code's built-in software
engineering instructions.

**Voice (no coding instructions)** (`output-styles/voice-no-coding.md`,
`keep-coding-instructions: false`)

The identical canonical Voice block with the built-in software engineering
instructions omitted from the system prompt.

There are no skills, hooks, or gating environment variables. The two style
bodies are byte-identical; only the frontmatter differs.

## Tests

```bash
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
session, or restart the session.

Auto-update is off by default for third-party marketplaces.

## Relationships to other plugins

None required. This plugin is fully standalone.

## Uninstalling

```
/plugin uninstall voice@clam
```

Uninstalling removes both styles from the picker. If one of them was the
selected `outputStyle`, Claude Code falls back to the Default style; the
stale `outputStyle` value in `.claude/settings.local.json` is the only
trace left behind.
