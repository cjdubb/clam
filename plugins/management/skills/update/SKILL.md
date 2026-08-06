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
   `${CLAUDE_PLUGIN_ROOT}/scripts/check-versions.sh` and parse its
   nine-column TSV output (columns: `plugin`, `installed`, `latest`,
   `update`, `stamp`, `setup`, `stale_targets`, `scope`,
   `stale_installs`). The report describes THIS repo: install records
   belonging to other repositories on the machine are excluded from every
   column, so what it says is what applies here.
3. **Present the report before anything changes.** Show the table as a
   readable summary — what's current, what's stale, what's unstamped —
   and for any row whose `setup` is `stale`, show its `stale_targets`
   value too, so the reader can see which target is behind without
   opening the stamp file. For any row whose `update` is `stale`, show its
   `stale_installs` value the same way: it names the project paths in this
   repo whose records are behind, which is the difference between one
   worktree being out of date and all of them. Nothing has changed yet;
   this step is purely informational.
4. **Nothing stale?** If no row's `update` column is `stale`, say plainly
   that nothing is stale and stop — there is nothing to update. (Setup
   re-run offers below can still apply even here, if a stamp is stale
   against an already-installed version.)
5. **Ask for one batch confirmation.** List every stale plugin and ask a
   single question covering the whole batch — never nag per plugin one at
   a time. An explicit subset reply (naming only some of the listed
   plugins) is honored: update only that subset, not the full batch.
6. **Apply confirmed updates.** For each plugin confirmed in step 5, take
   that plugin's `scope` value from the report and run
   `claude plugin update <plugin>@clam -s <scope>` for it — never omit the
   flag, since the CLI's own default scope is `user` and every clam plugin
   here is installed at some other scope. The `scope` column can carry
   several `;`-separated scopes for one plugin; when it does, run the
   update command once per scope in that case, and treat each per-scope
   run as its own independent result: report it separately, exactly like
   any other result, so a failure at one scope never suppresses or hides
   the outcome at another. A row whose `scope` is `-` gets no update
   command at all — never construct `-s -`; step 5 confirms only stale
   rows, so a `-` row cannot reach this step in practice, but the rule
   holds regardless. Report each result as it completes. A failure on one
   plugin does not abort the rest — keep going through the remaining
   confirmed plugins and collect every failure to report at the end.
7. **Re-run the check after updating.** Run `check-versions.sh` again and
   show the after state — including each row's `stale_targets` and
   `stale_installs` values — next to the before state, so the before/after
   change is visible.

   A row can legitimately stay `stale` here even though its update command
   succeeded. `installed` reports the LOWEST version among this repo's
   records, so a plugin recorded in several project paths goes green only
   once every one of them is updated, and `claude plugin update` resolves a
   single record per run. When that happens, say so plainly and show the
   remaining `stale_installs` paths rather than reporting the update as
   failed or re-running it blindly — it did what it could reach.
8. **Offer setup re-runs — never run them.** Using the `setup` column from
   the after-state check, offer the matching setup command (see the
   mapping below) for every plugin whose `setup` status is `stale`.

   Alongside that offer, use each row's `stale_targets`: for every target
   listed there, offer the exact command
   `${CLAUDE_PLUGIN_ROOT}/scripts/prune-stamp.sh <plugin> <target>` that
   would clear that record — one full command per target, never a single
   command with a placeholder covering several. The skill never runs
   `prune-stamp.sh` itself, under any circumstance, including an
   instruction like "fix everything": it only offers the command, and the
   engineer decides whether and when to run it — the same never-run rule
   this step already applies to the setup commands above, and the reason
   offering a deletion is safe at all. The skill states no opinion on
   whether a stamp should be pruned; it reports which targets are behind
   and leaves that judgement to the engineer. A row whose `stale_targets`
   is `-` gets no prune offer and no mention of pruning. An `unstamped`
   row is unaffected by any of this — it has no stamp record to remove,
   so it is never a prune candidate.
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
- **A `claude plugin update` command fails with `Plugin "<p>" is not
  installed at scope <s>`.** This is a scope mismatch: the scope the
  command used is not where that plugin is actually installed. Re-read
  that plugin's row and its `scope` column in the report, then re-run the
  command with `-s <scope>` using the value found there for that plugin.
- **A row is still `stale` after its update command reported success.**
  Not a failure, and not a reason to retry: `installed` is the LOWEST
  version among this repo's install records, and one `claude plugin
  update` run resolves a single record. Read that row's `stale_installs`
  value — it names the project paths still behind — and report them. The
  CLI exposes no per-project target, so a record for a project path other
  than the current one may only be reachable by running the update from
  that project. Say that plainly rather than looping the same command.

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
