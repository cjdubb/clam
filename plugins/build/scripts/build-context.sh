#!/bin/bash
# SessionStart hook for the build plugin. Detects which companion plugins
# are present for the session's working directory and injects the delivery
# framework context — the lifecycle stages, how plugins compose, and
# standing instructions for PR description sync.
#
# Contract: B01 companion-detection (plan 001-issues-317-318, issue #317)
#
# Behavior:
#   Decides, for each companion (landing, lego, tracking) independently,
#   whether it is present FOR THE SESSION'S WORKING DIRECTORY, then injects
#   a delivery framework context block as additionalContext describing the
#   companions that are present.
#
#   "Present" means what Claude Code itself means by it: the plugin is
#   installed somewhere on this machine AND enabled by the settings that
#   apply to `cwd`. Neither half alone is presence — a plugin installed for
#   another directory is not active here unless enabled here, and a plugin
#   enabled here is not active unless it is installed somewhere. An install
#   record's `projectPath` is provenance (where the install command ran),
#   never a scope boundary, and is not consulted.
#
#   Two signals answer that question. They are tried IN ORDER and
#   short-circuit: the first signal that resolves decides, and a signal
#   that cannot be evaluated (tool missing, file absent, output
#   unparseable) is skipped rather than treated as "absent". A signal that
#   evaluates to false HAS resolved — a failed conjunction is an answer,
#   not a fall-through. When no signal resolves, the companion is absent.
#
#   The repo's own file tree is NOT a signal. A `plugins/<name>/`
#   directory under `cwd` says a source checkout is here, never that the
#   plugin is loaded in this session, and the earlier revision of this
#   hook that read presence off that directory is the defect this contract
#   replaces (issue #317; ruling in decision 002).
#
#     1. Plugin CLI — `claude plugin list --json` run with `cwd` as the
#        working directory. Each element is an install record shaped
#        { id, version, scope, enabled, installPath, installedAt,
#        lastUpdated, projectPath }, where `id` is "<name>@<marketplace>"
#        and `enabled` is resolved against the working directory. A
#        companion is present when ANY element has an `id` beginning
#        "<name>@" and `enabled` true. Since only installed plugins are
#        listed, this one signal answers the whole conjunction.
#        This is Claude Code's own resolution and is why it is tried
#        first: settings precedence and scope semantics are its rules, and
#        a copy of them here is a copy that can drift.
#        The CLI is invoked AT MOST ONCE per hook run — one call answers
#        all three companions — and is bounded by `timeout 5` when the
#        `timeout` utility is available, so a hung CLI cannot consume the
#        hook's budget. A missing `claude` binary, a non-zero exit, empty
#        output, or output that is not a JSON array means this signal did
#        not resolve; fall through to signal 2.
#
#     2. Config files — used when signal 1 did not resolve. A companion is
#        present when BOTH hold:
#          a. an entry keyed "<name>@<anything>" exists under `.plugins`
#             in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
#             (installed somewhere; every scope — user, project, local —
#             shares this one file), AND
#          b. the resolved `enabledPlugins` value for a key beginning
#             "<name>@" is true, resolved across
#             "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json", then
#             "$cwd/.claude/settings.json", then
#             "$cwd/.claude/settings.local.json" — later file wins, an
#             explicit false disables, and a file that is absent or
#             unparseable contributes nothing rather than disabling.
#        A missing or malformed installed_plugins.json means this signal
#        did not resolve either, and with no signal left the companion is
#        absent.
#
#   Marketplace is matched by plugin NAME only — a leading "<name>@" — and
#   never hardcoded to a particular marketplace: the same marketplace can
#   be added under any local name.
#
#   The injected context adapts to which companions are present:
#     - landing present: includes merge policy context, PR creation guidance.
#     - lego present: includes dispatch/delivery context.
#     - tracking present: includes state lifecycle context.
#     - none present: injects a minimal context explaining the build
#       plugin's purpose and how the companions become available. That
#       branch describes installing them from the marketplace and enabling
#       them for the repo; it never tells the user to place plugins under
#       a `plugins/` directory, which is a layout no consumer repo has.
#
#   Always includes the standing instruction: "After every push to a branch
#   with an open PR, sync the PR description using /build:sync-pr."
#
# Inputs:
#   stdin — JSON object with at least { "cwd": "<path>" }.
#   Env — CLAUDE_CONFIG_DIR: root of the Claude config dir, default
#   "$HOME/.claude". Honoured wherever a config path is read, which is
#   also what makes signal 2 testable against a fixture.
#
# Outputs:
#   stdout — valid hookSpecificOutput JSON:
#   { "hookSpecificOutput": { "hookEventName": "SessionStart",
#     "additionalContext": "<delivery framework context>" } }
#   OR no output (fail-open).
#
# Errors:
#   All errors fail open: exit 0, no output. Never breaks session start.
#   Specific fail-open triggers: jq not on PATH, no cwd in payload,
#   malformed payload. Every detection failure is narrower than that: it
#   demotes one signal, never the hook.
#
# Invariants:
#   - Never requires any companion plugin to be installed.
#   - Detection never sources, imports, or executes a companion's own
#     scripts; the only external command it may run for detection is the
#     Claude Code CLI's read-only `plugin list` subcommand.
#   - Detection is read-only: it writes no file and mutates no config.
#   - Detection never reads the repository's own file tree. Presence is a
#     property of the session, not of what happens to be checked out.
#   - The PR description sync instruction is always injected regardless
#     of which companions are present.
#   - All user-visible text references "build" (the plugin name) and
#     "/build:sync-pr" (the skill namespace), never "deliver".
#   - Both branches' wording is true of what was measured: the positive
#     branch may claim a companion is installed only because presence was
#     established, and the negative branch may claim none was detected
#     only after both signals were tried.
#
# Edge cases:
#   - Consumer repo with no plugins/ directory but all companions
#     installed and enabled: all three present, via signal 1 (or 2).
#   - Repo whose settings enable a companion that is installed nowhere:
#     absent — there is no row for it under signal 1, and signal 2's
#     install check fails.
#   - Companion installed on the machine but not enabled for this cwd:
#     absent.
#   - `claude` not on PATH (hook launched from an IDE or desktop app with
#     a restricted PATH): signal 2 still answers.
#   - A checkout of the plugin repo itself, with the companions not
#     installed or not enabled: absent. The negative branch's advice —
#     install them from the marketplace and enable them for this repo — is
#     the accurate thing to say in that state, and claiming presence off
#     the source tree would point the reader at skills the session cannot
#     resolve.
#   - Companion installed and enabled but its cached plugin directory is
#     broken: still present. The plugin system handles broken plugins, not
#     this hook.
#   - Neither signal resolves (no `claude`, and installed_plugins.json
#     missing or malformed): all three absent, negative branch, exit 0.
#   - Companion listed several times (one row per install record, several
#     versions): present if ANY row is enabled.
#   - Multiple repos in a worktree layout: the payload's cwd decides,
#     never the hook process's own working directory.

set -u

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || exit 0

config_dir="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"

# --- Signal 1: the plugin CLI, invoked at most once for this hook run. ---
cli_resolved=false
cli_json='[]'
if command -v claude >/dev/null 2>&1; then
  if command -v timeout >/dev/null 2>&1; then
    cli_out=$(cd "$cwd" 2>/dev/null && timeout 5 claude plugin list --json 2>/dev/null)
  else
    cli_out=$(cd "$cwd" 2>/dev/null && claude plugin list --json 2>/dev/null)
  fi
  cli_rc=$?
  if [ "$cli_rc" -eq 0 ] && [ -n "$cli_out" ] \
     && printf '%s' "$cli_out" | jq -e 'type == "array"' >/dev/null 2>&1; then
    cli_resolved=true
    cli_json="$cli_out"
  fi
fi

# --- Signal 2: config files, resolved only when signal 1 did not. ---
if ! $cli_resolved; then
  installed_plugins_file="$config_dir/plugins/installed_plugins.json"
  signal2_installed_ok=false
  if [ -f "$installed_plugins_file" ] && jq empty "$installed_plugins_file" >/dev/null 2>&1; then
    signal2_installed_ok=true
  fi

  merged_enabled='{}'
  for settings_file in "$config_dir/settings.json" \
                        "$cwd/.claude/settings.json" \
                        "$cwd/.claude/settings.local.json"; do
    if [ -f "$settings_file" ] && jq empty "$settings_file" >/dev/null 2>&1; then
      part=$(jq -c '.enabledPlugins // {}' "$settings_file" 2>/dev/null)
      merged_enabled=$(jq -cn --argjson a "$merged_enabled" --argjson b "$part" '$a * $b')
    fi
  done
fi

signal2_present() { # <name> -> 0 present, 1 absent
  local name="$1"
  $signal2_installed_ok || return 1
  jq -e --arg n "$name" 'any(.plugins // {} | keys[]; startswith($n + "@"))' \
    "$installed_plugins_file" >/dev/null 2>&1 || return 1
  printf '%s' "$merged_enabled" | jq -e --arg n "$name" \
    'any(to_entries[]; (.key | startswith($n + "@")) and (.value == true))' >/dev/null 2>&1
}

companion_present() { # <name> -> 0 present, 1 absent
  local name="$1"
  if $cli_resolved; then
    printf '%s' "$cli_json" | jq -e --arg n "$name" \
      'any(.[]; ((.id // "") | startswith($n + "@")) and (.enabled == true))' >/dev/null 2>&1
    return
  fi
  signal2_present "$name"
}

landing_present=false
lego_present=false
tracking_present=false
companion_present landing  && landing_present=true
companion_present lego     && lego_present=true
companion_present tracking && tracking_present=true

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
No companion plugins (landing, lego, tracking) were detected for this
directory. The build plugin still works standalone for PR description sync
via /build:sync-pr, as long as the gh CLI is installed and authenticated.
Installing the companion plugins from the marketplace and enabling them for
this repo unlocks richer session context: how merges and pull requests are
handled, how work gets planned and carried out in units, and how in-progress
work is tracked across sessions.
"
fi

standing="
Standing instruction: after every push to a branch with an open PR, sync
the PR description to reflect the current state of the branch using
/build:sync-pr.
"

context="# Delivery framework
${sections}
${standing}"

printf '%s' "$context" | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
