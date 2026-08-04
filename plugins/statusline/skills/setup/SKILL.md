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
   (treat a missing file as `{}`). Report the current `statusLine` value (if
   any) and the entry you are about to write:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "<plugin-root>/scripts/context.sh"
     }
   }
   ```

   If a different statusline is already configured, ask before replacing it.
3. **Merge, don't overwrite.** Update only the `statusLine` key, preserving
   every other setting:

   ```bash
   jq --arg cmd "<plugin-root>/scripts/context.sh" \
      '.statusLine = {type: "command", command: $cmd}' \
      ~/.claude/settings.json > /tmp/settings.json.new \
     && mv /tmp/settings.json.new ~/.claude/settings.json
   ```

   Back up the original first (`settings.json.bak-<date>`).
4. **Verify.** `jq empty ~/.claude/settings.json`, then tell the user the
   statusline appears on the next session (or immediately in current sessions
   on the next render).
5. **Record the setup stamp.** After the verify step succeeds, record this
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
   - Replace this plugin's record, keyed by `plugin` and `target`; touch
     no other records. Write via jq to a temp file, then `mv` it into
     place — the same atomic pattern as the settings write above:

     ```json
     {
       "plugin": "statusline",
       "version": "<from plugin.json>",
       "scope": "user",
       "target": "~/.claude/settings.json",
       "at": "<ISO-8601 UTC timestamp>"
     }
     ```

   - If the stamp write fails, report the failure but never fail the
     setup — the settings write above already succeeded.

## `/statusline:setup remove`

Restore the pre-setup state: delete the `statusLine` key (or restore the
backup if the user prefers), preserving all other settings. Also delete
this plugin's stamp record for `~/.claude/settings.json` from the shared
stamp file; if there is no stamp for this target, that's already fine —
nothing to do.

## Notes

- The scripts need `jq`. Cost figures come from `scripts/prices.json` —
  list-price equivalents computed from local transcripts, not billing data.
- The session-State segment lights up only in repos using the tracking
  plugin's `.local/TODO.md` convention; elsewhere it stays hidden.
- Plugin updates keep the same install path, so the settings entry survives
  updates. If the plugin is uninstalled, the statusline command dies with it —
  run `/statusline:setup remove` first.
