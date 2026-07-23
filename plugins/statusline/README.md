<!--
Contract: B13 statusline-readme
Behavior:
  Update the existing statusline README to meet all 4 issue #61 sections.
Inputs:
  The existing README content, PLUGIN_README_TEMPLATE, plugin directory scan.
Outputs:
  Three new sections added/expanded in the existing README:
    1. Add ## Getting started — install command
       (/plugin marketplace add cjdubb/clam, /plugin install statusline@clam),
       note that /statusline:setup must be run after install to write the
       statusLine setting. Existing "Why setup is a command" content can be
       folded into or referenced from this section.
    2. Add ## Relationships to other plugins — document the tracking plugin
       soft integration (State segment reads .local/TODO.md), the vendored
       copy of states.sh/tsv from tracking (keep in lockstep).
    3. Add ## Uninstalling — uninstall command
       (/plugin uninstall statusline@clam), note to run /statusline:setup remove
       first to revert the statusLine setting in ~/.claude/settings.json.
Errors: n/a (documentation).
Invariants:
  - Preserve ALL existing content: Why setup is a command, Layout,
    Behaviour notes sections.
  - The existing content documents the skill and scripts adequately for
    the "Commands" section; do not duplicate.
  - Follow PLUGIN_README_TEMPLATE section order for new sections.
Edge cases:
  - The statusline write to ~/.claude/settings.json is unusual (most
    plugins don't touch global settings) — the uninstalling section
    should make the revert step prominent.
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
