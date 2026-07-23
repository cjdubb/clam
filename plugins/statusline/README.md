<!--
SCAFFOLD Contract: B15 statusline-readme (plan 002-readme-conformance)
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
  (/plugin marketplace add cjdubb/clam; /plugin install statusline@clam).
  Uninstalling opens with /plugin uninstall statusline@clam plus any cleanup.
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
  Current H2s: Why setup is a command, Layout, Behaviour notes. Getting
  started from the install + setup flow; the "why setup is a command"
  rationale folds under the setup command docs in Commands; Layout and
  Behaviour notes -> optional slot or folded under Commands as content
  dictates; What to expect: what the statusline shows once configured.
-->

# statusline

Cam's statusline for Claude Code: context-window usage, session/day/week cost,
reasoning effort, and — in repos using the tracking plugin — the session's
State (emoji + colour straight from the states manifest).

## Why setup is a command

Plugins cannot provide a statusline: `statusLine` exists only in
`~/.claude/settings.json`, and plugin path variables don't resolve there. This
marketplace's rule is that installing a plugin changes nothing globally, so
the settings write is an explicit step:

```
/plugin install statusline@clam
/statusline:setup          # writes statusLine into ~/.claude/settings.json
/statusline:setup remove   # puts it back
```

## Layout

```
scripts/context.sh   statusline entry point (reads the statusLine JSON on stdin)
scripts/ccost.sh     session/day/week cost from local JSONL transcripts
scripts/prices.json  pinned price table (update when Anthropic rates change)
scripts/*.test.sh    test suites for both scripts
lib/platform.sh      OS-aware helpers (mtime, darwin/linux)
lib/states.sh|tsv    session-State metadata — vendored copy; canonical source
                     is the tracking plugin, keep in lockstep
```

## Behaviour notes

- Costs are list-price equivalents computed from `~/.claude/projects`
  transcripts against `prices.json` — a counterfactual to a subscription, not
  what you were billed. Cached 300s under `~/.claude/.ccost-cache`.
- The State segment reads `.local/TODO.md` in the current worktree and stays
  hidden when there is none — the statusline works fine without the tracking
  plugin.
- Requires `jq`. Bash 3.2-safe (macOS `/bin/bash`).
