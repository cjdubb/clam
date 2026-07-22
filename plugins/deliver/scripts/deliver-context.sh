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

echo "NotImplemented: B03" >&2; exit 1
