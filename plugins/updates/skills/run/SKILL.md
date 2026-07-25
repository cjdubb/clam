---
name: run
description: "Update all installed clam plugins: refresh the marketplace catalog, show installed vs latest versions, apply per-plugin updates after one confirmation, then surface which setup skills need re-running and how to reload. Explicit user action: never runs implicitly."
disable-model-invocation: true
---

# Clam Updates

<!--
Contract: B02 updates-run-skill (plan 001-update-flow-for-users)
Behavior:
  Guided, engineer-confirmed update flow over every installed clam plugin:
  1. Refresh the catalog: run `claude plugin marketplace update clam` (the
     CLI form of /plugin marketplace update; verify the exact invocation
     empirically at implementation and encode what actually works).
  2. Run ${CLAUDE_PLUGIN_ROOT}/scripts/check-versions.sh and parse the TSV.
  3. Present the report as a readable table: what is current, what is
     stale, what is unstamped; nothing has been changed yet.
  4. If nothing is stale: say so and stop (setup re-run offers still apply
     when stamps are stale against already-installed versions).
  5. Ask ONE confirmation for the whole batch of stale plugins (listing
     them). No per-plugin nagging; an explicit subset reply updates only
     that subset.
  6. Run `claude plugin update <plugin>@clam` per confirmed plugin,
     reporting each result; a failure on one plugin does not abort the
     rest — collect and report failures at the end.
  7. Re-run check-versions.sh; show the after state.
  8. Map setup-relevant plugins to their setup commands and offer (never
     run) the ones whose setup column is `stale`:
       attribution → /attribution:setup     privacy → /privacy:setup
       settings    → /settings:setup        statusline → /statusline:setup
       landing     → /landing:init
     `unstamped` plugins from this list are mentioned as "setup state
     unknown — run the setup once to stamp it", never as "needs setup".
  9. Close with reload guidance: /reload-plugins, or restart the session
     when updated plugins ship hooks/agents (state which applied here).
Inputs:
  Optional argument "check": stop after step 3 (report only, no updates).
  No other arguments.
Outputs:
  The before/after version report, per-plugin update results, setup re-run
  offers, and reload/restart guidance — all conversational; no files
  written by this skill.
Errors:
  - `claude` CLI not on PATH → report and fall back to instructing the
    user through the interactive /plugin flow; do not silently stop.
  - check-versions.sh exit 3 (no marketplace clone) → step 1 failed or was
    skipped; surface the script's message and stop.
  - check-versions.sh exit 2/4 → surface stderr verbatim and stop.
  - A plugin update command failing → record, continue with the rest,
    report the failure list at the end.
Invariants:
  - Nothing is updated without the explicit batch confirmation (step 5).
  - Read-only until that confirmation; "check" mode is always read-only.
  - Setup skills are OFFERED as commands, never invoked by this skill.
  - Absent stamps never block or gate updates.
  - The skill works when the updates plugin itself is stale; if `updates`
    is among the plugins updated, say that the new version applies from
    the next session/reload.
Edge cases:
  - Marketplace auto-update enabled for clam: the catalog may already be
    fresh and plugins may already be current — the flow degrades to a
    no-op report. The skill's guidance text about auto-update must match
    empirically verified Claude Code behavior (verify at implementation;
    do not copy the unverified README claim).
  - Zero clam plugins installed: report that and stop.
  - `not-installed` rows are informational only; this skill never installs.
-->

NotImplemented: B02 — the flow body lands at implementation. Test structure
against the contract above.
