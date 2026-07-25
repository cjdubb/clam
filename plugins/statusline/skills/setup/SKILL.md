---
name: setup
description: "Wire the clam statusline into ~/.claude/settings.json, or remove it. Explicit opt-in: installing the plugin changes nothing until the user runs /statusline:setup."
disable-model-invocation: true
---

# Statusline Setup

<!--
Contract: B05 setup-version-stamp — statusline (plan 001-update-flow-for-users)
Behavior (extension, to be added): after a successful statusLine write (the
  verify step passes), record a setup stamp
  {plugin: "statusline", version, scope: "user",
   target: <absolute path of ~/.claude/settings.json>, at} in the stamp
  file per plugins/updates/docs/setup-stamps.md; on
  `/statusline:setup remove` (or the documented removal flow), delete this
  plugin's stamp for the same target.
Inputs: version is read from the plugin.json at this installation's
  installPath (from its installed_plugins.json entry) — never from the
  entry's version field. statusLine lives only in user settings, so scope
  is always "user".
Outputs: stamp record created/replaced (keyed plugin+target); the final
  confirmation message also names the stamp that was written.
Errors: a stamp write failure is reported but never fails the setup; a
  corrupt stamp file is moved aside (.corrupt-<date>) and recreated, per
  the format doc.
Invariants: setup behaves identically whether or not the updates plugin is
  installed; stamp writes are temp-file + mv; no stamp records other than
  this plugin+target are touched.
Edge cases: absent stamp file → created; removal with no stamp → silent
  success (stamp-wise). Updates keep the same install path so the
  statusLine entry survives updates — the stamp is what tells the update
  flow whether this setup ran against the current version. Plugin version
  bumps 0.1.0 → 0.2.0 with this change.
-->

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

## `/statusline:setup remove`

Restore the pre-setup state: delete the `statusLine` key (or restore the
backup if the user prefers), preserving all other settings.

## Notes

- The scripts need `jq`. Cost figures come from `scripts/prices.json` —
  list-price equivalents computed from local transcripts, not billing data.
- The session-State segment lights up only in repos using the tracking
  plugin's `.local/TODO.md` convention; elsewhere it stays hidden.
- Plugin updates keep the same install path, so the settings entry survives
  updates. If the plugin is uninstalled, the statusline command dies with it —
  run `/statusline:setup remove` first.
