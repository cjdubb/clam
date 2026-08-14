---
name: setup
description: "Wire the clam statusline into ~/.claude/settings.json, or remove it. Explicit opt-in: installing the plugin changes nothing until the user runs /statusline:setup."
disable-model-invocation: true
---

# Statusline Setup

Claude Code has no plugin field for statuslines — `statusLine` lives only in
`~/.claude/settings.json`, and `${CLAUDE_PLUGIN_ROOT}` does not resolve there.
This skill performs that one global write explicitly, at the user's request,
keeping the marketplace's install-changes-nothing constraint intact.

## `/statusline:setup`

1. **Resolve the plugin root.** This SKILL.md lives at
   `<plugin-root>/skills/setup/SKILL.md` — take the directory two levels up
   from this file's location. Verify: `<plugin-root>/scripts/context.sh` must
   exist and be executable. If you cannot determine this file's path from the
   skill invocation context, find it via
   `ls -d ~/.claude/plugins/*/statusline/scripts/context.sh 2>/dev/null` and
   friends, and confirm the match with the user before writing anything.
2. **Show the change before making it.** Read `~/.claude/settings.json`
   (treat a missing file as `{}`). Setup writes three keys: `statusLine` (the
   main line), `subagentStatusLine` (the agent-panel rows) and
   `refreshInterval`. Report the current value of each of those three keys (if
   any) and the entries you are about to write:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "<plugin-root>/scripts/context.sh"
     },
     "subagentStatusLine": {
       "type": "command",
       "command": "<plugin-root>/scripts/subagent.sh"
     },
     "refreshInterval": 5
   }
   ```

   If a different `statusLine` or `subagentStatusLine` is already configured,
   or the user already set their own `refreshInterval` for some other reason,
   ask before replacing or changing that value.

   Why the refresh interval is 5 and not left to the default: Claude Code
   renders the statusline on events, and those event-driven triggers go quiet
   while a coordinator sits waiting on background subagents — which is exactly
   the stretch where the 5-hour block countdown and both burn trends matter
   most, and exactly when they would otherwise freeze on screen at their last
   rendered value. A 5-second interval keeps them moving through the wait.
3. **Disclose the working week, and ask before changing it.** The weekly
   trend arrow paces against a working week described by three keys in the
   `env` block of `~/.claude/settings.json`: `CLAM_STATUSLINE_WORK_DAYS`,
   `CLAM_STATUSLINE_DAY_START` and `CLAM_STATUSLINE_DAY_END`. Read that
   `env` block and tell the user in plain words which days the week covers
   and which hours the day runs between — Monday to Friday (`1-5`), 08:00 to
   18:00 are the defaults. Mark each of the three values as either a default
   or set, so the user can see which ones this machine actually carries. A
   settings file that is missing, or one with no `env` block, means all
   three are at their defaults. When only some of the three keys are set,
   disclose the mix exactly as it stands, each value marked the same way.

   Say in one line that the weekly trend arrow paces against this schedule,
   while the raw `wk used%` figure and the reset countdown do not move with
   it, and point the user at the README's "Match the pacing to the hours you
   actually work" section for the rest of the picture.

   Whenever `CLAM_STATUSLINE_DAY_START` is already set, add one line about
   the 0.9.0 change: the knob kept its name but changed both its meaning —
   it named the hour the pacing day flipped over, and it now names the hour
   your working day begins — and its default, from `2` to `8`. Disclose the
   current value as it stands under the new meaning, and let the user decide
   what it should be.

   Then ask once: keep this schedule, or change it? If the user keeps it, no
   env key is written and the settings file's `env` block stays untouched —
   what is set stays set, what is absent stays absent.

   If the user changes it, validate each new value against its documented
   domain before accepting it. `CLAM_STATUSLINE_WORK_DAYS` takes ISO weekday
   numbers 1-7 (1 = Monday), written with commas and ranges (`1-5`,
   `1,3,5`, `1-4,6`); `CLAM_STATUSLINE_DAY_START` takes a whole hour 0..23;
   `CLAM_STATUSLINE_DAY_END` takes a whole hour 1..24, strictly greater than
   the start. An answer outside these domains is re-asked and never written.
   An end at or before the start is rejected as a pair rather than as one
   bad value, so re-ask for both hours together — the same rule the render
   itself falls back on. The accepted values are handed to step 4, which
   performs the one write; this step only reads and asks.
4. **Merge, don't overwrite.** Set the three keys in one pass over the
   existing file, preserving every other setting in it, and fold any
   schedule value the user changed in step 3 into that same pass:

   ```bash
   jq --arg main "<plugin-root>/scripts/context.sh" \
      --arg sub  "<plugin-root>/scripts/subagent.sh" \
      --arg days "" --arg start "" --arg end "" \
      '.statusLine = {type: "command", command: $main}
       | .subagentStatusLine = {type: "command", command: $sub}
       | .refreshInterval = 5
       | if $days  == "" then . else .env.CLAM_STATUSLINE_WORK_DAYS = $days  end
       | if $start == "" then . else .env.CLAM_STATUSLINE_DAY_START = $start end
       | if $end   == "" then . else .env.CLAM_STATUSLINE_DAY_END   = $end   end' \
      ~/.claude/settings.json > /tmp/settings.json.new \
     && mv /tmp/settings.json.new ~/.claude/settings.json
   ```

   The existing settings file is the input, so every key this filter does not
   name survives untouched. Back up the original first
   (`settings.json.bak-<date>`). Pass `--arg days`, `--arg start` and
   `--arg end` only when the user changed that value in step 3; left empty,
   each `if` leaves the env block exactly as it was. The three schedule
   values are written as env strings, since an env block holds strings, so
   an hour of 8 is written as `"8"`.
5. **Verify.** `jq empty ~/.claude/settings.json`, then tell the user the
   statusline appears on the next session (or immediately in current sessions
   on the next render), and that the agent-panel rows appear whenever
   subagents are running.
6. **Record the setup stamp.** After the verify step succeeds, record this
   setup in the shared stamp file so the update flow can tell this plugin's
   setup is current with the installed version:
   `${CLAUDE_CONFIG_DIR:-~/.claude}/clam-setup-stamps.json` — format defined
   in `docs/protocols/setup-stamp.md`.
   - Read the plugin's version from the `plugin.json` at this
     installation's `installPath` (from its `installed_plugins.json`
     entry) — never from the entry's own `version` field, which can go
     stale. The statusline scope is always `"user"`; the target is always
     `~/.claude/settings.json`.
   - If the stamp file does not exist yet, create it first as
     `{"version": 1, "stamps": []}`.
   - If the existing stamp file is corrupt (not valid JSON), move it aside
     to `clam-setup-stamps.json.corrupt-<date>`, report the move to the
     user, and recreate it fresh.
   - Set `at` to the current UTC time by running
     `date -u +%Y-%m-%dT%H:%M:%SZ` — never invented, guessed, or copied
     from another record.
   - Replace this plugin's record, keyed by `plugin` and `target`; touch
     no other records. Write via jq to a temp file, then `mv` it into
     place — the same atomic pattern as the settings write above:

     ```json
     {
       "plugin": "statusline",
       "version": "<from plugin.json>",
       "scope": "user",
       "target": "~/.claude/settings.json",
       "at": "<output of date -u +%Y-%m-%dT%H:%M:%SZ>"
     }
     ```

   - If the stamp write fails, report the failure but never fail the
     setup — the settings write above already succeeded.

## `/statusline:setup remove`

Restore the pre-setup state: delete all three keys this setup wrote —
`statusLine`, `subagentStatusLine` and `refreshInterval` — together with the
three schedule keys step 3 may have written, in one pass over the existing
file that preserves all other settings:

```bash
jq 'del(.statusLine, .subagentStatusLine, .refreshInterval,
        .env.CLAM_STATUSLINE_WORK_DAYS, .env.CLAM_STATUSLINE_DAY_START,
        .env.CLAM_STATUSLINE_DAY_END)
    | if (.env | length) == 0 then delpaths([["env"]]) else . end' \
   ~/.claude/settings.json > /tmp/settings.json.new \
  && mv /tmp/settings.json.new ~/.claude/settings.json
```

Every other `env` key survives that pass untouched. A settings file with no
env block, or one where these schedule keys are absent, is a no-op for them
rather than an error. If deleting them leaves the `env` block empty, drop
the empty block itself rather than leaving an env key with nothing inside
it. Say the three schedule keys were removed only when they were present.

If the user
prefers, restore the timestamped backup instead; say which backup you are
restoring, since a backup taken by an earlier version of this setup predates
the two new keys and restoring it leaves whatever those keys held before.

If `subagentStatusLine` or `refreshInterval` is absent — the case for a user
who only ever ran the previous version's setup — that is not an error and
there is nothing to do for that key; delete the ones that are there and say
so.

Also delete
this plugin's stamp record for `~/.claude/settings.json` from the shared
stamp file; if there is no stamp for this target, that's already fine —
nothing to do.

## Notes

- The scripts need `jq`. The statusline shows no cost figure;
  `scripts/ccost.sh` is a standalone CLI that does. Its figures come from
  `scripts/prices.json` — list-price equivalents computed from local
  transcripts, not billing data.
- The session-State segment lights up only in repos using the tracking
  plugin's `.local/TODO.md` convention; elsewhere it stays hidden.
- Plugin updates keep the same install path, so the settings entry survives
  updates. If the plugin is uninstalled, the statusline command dies with it —
  run `/statusline:setup remove` first.
