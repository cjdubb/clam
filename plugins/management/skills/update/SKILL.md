---
name: update
description: "Update all installed clam plugins: refresh the marketplace catalog, show installed vs latest versions, apply per-plugin updates after one confirmation, then surface which setup skills need re-running and how to reload. Explicit user action: never runs implicitly."
disable-model-invocation: true
---

# Clam Updates

This is the guided, engineer-confirmed flow for updating every installed
clam plugin. It never runs on its own — only an explicit `/management:update`
starts it.

## `/management:update`

1. **Refresh the marketplace catalog.** Run `claude plugin marketplace
   update clam` to pull the latest catalog for the clam marketplace before
   checking anything. This is a read-only refresh of the marketplace
   clone — it does not touch any installed plugin.
2. **Build the version report.** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/check-versions.sh` and parse its TSV
   output (columns: `plugin`, `installed`, `latest`, `update`, `stamp`,
   `setup`).
3. **Present the report before anything changes.** Show the table as a
   readable summary — what's current, what's stale, what's unstamped.
   Nothing has changed yet; this step is purely informational.
4. **Nothing stale?** If no row's `update` column is `stale`, say plainly
   that nothing is stale and stop — there is nothing to update. (Setup
   re-run offers below can still apply even here, if a stamp is stale
   against an already-installed version.)
5. **Ask for one batch confirmation.** List every stale plugin and ask a
   single question covering the whole batch — never nag per plugin one at
   a time. An explicit subset reply (naming only some of the listed
   plugins) is honored: update only that subset, not the full batch.
6. **Apply confirmed updates.** For each plugin confirmed in step 5, run
   `claude plugin update <plugin>@clam`. Report each result as it
   completes. A failure on one plugin does not abort the rest — keep going
   through the remaining confirmed plugins and collect every failure to
   report at the end.
7. **Re-run the check after updating.** Run `check-versions.sh` again and
   show the after state next to the before state, so the before/after
   change is visible.
8. **Offer setup re-runs — never run them.** Using the `setup` column from
   the after-state check, offer the matching setup command (see the
   mapping below) for every plugin whose `setup` status is `stale`.
9. **Close with reload guidance.** Tell the user to run `/reload-plugins`
   to pick up the updates in the current session, or to restart the
   Claude Code session entirely if any updated plugin ships hooks or
   agents — state explicitly which of the two applies, based on what was
   actually updated.

## Setup re-run mapping

| Plugin | Setup command |
|---|---|
| `attribution` | `/attribution:setup` |
| `privacy` | `/privacy:setup` |
| `settings` | `/settings:setup` |
| `statusline` | `/statusline:setup` |
| `landing` | `/landing:init` |

Offer these commands — never run them yourself; the engineer decides
whether and when to run them.

A plugin whose `setup` column reads `stale` gets its matching command
offered from the table above. A plugin whose `setup` column reads
`unstamped` has setup state unknown — run the setup once to stamp it.
Never phrase an unstamped or stale plugin as needing setup: both statuses
are informational, and neither one blocks or gates the update in step 6.

## `/management:update check`

The optional `check` argument stops the flow after the version report
(step 3 above) — no confirmation is asked, and nothing is updated. This
mode is strictly read-only: it still refreshes the catalog (step 1) and
runs the version-report steps (2-3), then stops there. Use it whenever you
just want to see what's stale without changing anything.

## Errors

- **`claude` CLI not found on PATH.** Report that the `claude` CLI is not
  available and fall back to instructing the user through the interactive
  `/plugin` flow instead — `/plugin marketplace update clam` for the
  refresh, and the `/plugin` menu's install/update actions in place of the
  CLI commands above. Never silently stop without saying so.
- **`check-versions.sh` exit 3** (no marketplace clone found): surface the
  script's own stderr message and stop — this means step 1 failed or was
  skipped.
- **`check-versions.sh` exit 2 or exit 4** (malformed/missing
  installed-plugins data, or missing `jq`): surface stderr verbatim and
  stop; do not paraphrase or guess at the cause.
- **A `claude plugin update` command fails for one plugin.** Record the
  failure, keep going with the rest of the confirmed batch, and report the
  full failure list at the end, per step 6.

## Notes

- Nothing is updated without the explicit batch confirmation in step 5;
  every step before it is read-only, and `check` mode above is always
  read-only.
- Absent setup stamps never block or gate updates: an `unstamped` plugin
  updates exactly the same way as a `current` or `stale` one.
- If marketplace auto-update is enabled for clam, the catalog may already
  be fresh and plugins may already be current by the time this flow
  runs — steps 1-3 then simply confirm there's nothing stale, and the flow
  follows the nothing-stale path in step 4. That doesn't change this
  skill's behavior, only what the report is likely to show.
- `not-installed` rows in the report are informational only — this skill
  never installs a plugin.
- If `management` itself is updated, the new version applies at next session
  or reload — say so explicitly when it happens, since the running
  session keeps the old code loaded until then.
- Zero clam plugins installed → report that and stop; there is nothing to
  check or update.
