#!/bin/bash
# SessionStart hook for the deliver plugin. Detects which companion plugins
# are installed and injects the delivery framework context — the lifecycle
# stages, how plugins compose, and standing instructions for PR description
# sync.
#
# Contract: B03 deliver-plugin-skeleton
#
# Behavior:
#   Checks for companion plugins (landing, lego, tracking) by testing for
#   their directories relative to the repo root. Injects a delivery
#   framework context block as additionalContext, listing the available
#   lifecycle stages and standing instructions. The context adapts to which
#   companions are present:
#     - landing present: includes merge policy context, PR creation guidance.
#     - lego present: includes dispatch/delivery context.
#     - tracking present: includes state lifecycle context.
#     - none present: injects a minimal context explaining the deliver
#       plugin's purpose and suggesting companion plugins.
#
#   Always includes the standing instruction: "After every push to a branch
#   with an open PR, sync the PR description using /deliver:sync-pr."
#
# Inputs:
#   stdin — JSON object with at least { "cwd": "<path>" }.
#
# Outputs:
#   stdout — valid hookSpecificOutput JSON:
#   { "hookSpecificOutput": { "hookEventName": "SessionStart",
#     "additionalContext": "<delivery framework context>" } }
#   OR no output (fail-open).
#
# Errors:
#   All errors fail open: exit 0, no output. Never breaks session start.
#   Specific fail-open triggers: jq not on PATH, no cwd in payload.
#
# Invariants:
#   - Never requires any companion plugin to be installed.
#   - Companion detection is directory-based (checks for plugin dirs),
#     not import-based (never sources companion scripts).
#   - The PR description sync instruction is always injected regardless
#     of which companions are present.
#
# Edge cases:
#   - Repo with no plugins/ directory: all companions absent, minimal context.
#   - Companion plugin directory exists but is empty/broken: treated as present
#     (the plugin system handles broken plugins, not this hook).
#   - Multiple repos in a worktree layout: cwd determines which repo's
#     plugins are checked.

set -u

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || exit 0

landing_present=false
lego_present=false
tracking_present=false
[ -d "$cwd/plugins/landing" ] && landing_present=true
[ -d "$cwd/plugins/lego" ] && lego_present=true
[ -d "$cwd/plugins/tracking" ] && tracking_present=true

sections=""

if $landing_present; then
  sections="${sections}
### Landing (merge policy)

The landing plugin is installed. It governs merge policy — how and where
finished work lands (local merge vs. PR creation) — and drives PR creation
when the repo's policy calls for it. Use /landing:land to land finished
work according to the recorded policy.
"
fi

if $lego_present; then
  sections="${sections}
### Lego (dispatch)

The lego plugin is installed. It provides the plan/scaffold/dispatch
workflow for decomposing and delivering work in small, verified units.
"
fi

if $tracking_present; then
  sections="${sections}
### Tracking (state lifecycle)

The tracking plugin is installed. It manages the state lifecycle of
in-progress work via .local/ tracking docs (TODO.md, PLAN.md and friends),
so progress and decisions survive compaction and session restarts.
"
fi

if ! $landing_present && ! $lego_present && ! $tracking_present; then
  sections="
No companion plugins (landing, lego, tracking) were detected. The deliver
plugin still works standalone for PR description sync via /deliver:sync-pr,
as long as the gh CLI is installed and authenticated. Installing the
companion plugins under plugins/ unlocks richer session context: how
merges and pull requests are handled, how work gets planned and carried
out in units, and how in-progress work is tracked across sessions.
"
fi

standing="
Standing instruction: after every push to a branch with an open PR, sync
the PR description to reflect the current state of the branch using
/deliver:sync-pr.
"

context="# Delivery framework
${sections}
${standing}"

printf '%s' "$context" | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
