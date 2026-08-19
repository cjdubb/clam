# Setup version stamps

The stamp file records which plugin version each clam setup skill last
configured, so the update flow can tell when an updated plugin needs its
setup re-run. This document is the authoritative format contract (B01, plan
001-update-flow-for-users): the five setup skills write it, and
`scripts/check-versions.sh` reads it. Neither side may deviate from what is
specified here.

## Location

```
${CLAUDE_CONFIG_DIR:-$HOME/.claude}/clam-setup-stamps.json
```

One file per user, all scopes and repos included. The file belongs to clam
(not Claude Code); Claude Code never reads or writes it.

## Shape

```json
{
  "version": 1,
  "stamps": [
    {
      "plugin": "attribution",
      "version": "0.2.0",
      "scope": "user",
      "target": "/home/user/.claude/settings.json",
      "at": "2026-07-24T10:00:00Z"
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `version` | Stamp-file schema version. Always `1` for this format. |
| `stamps[].plugin` | Plugin name as it appears in the marketplace (no `@clam` suffix). |
| `stamps[].version` | The plugin version that performed the setup, read from the `plugin.json` at the installation's `installPath` (authoritative; the `version` field in `installed_plugins.json` can go stale). |
| `stamps[].scope` | Installation scope the setup configured: `user`, `project`, or `local`. |
| `stamps[].target` | Absolute path of the file the setup wrote (settings file, or the user-local `clam-profile.jsonc` for landing). |
| `stamps[].at` | ISO-8601 UTC timestamp measured when the stamp is written, via `date -u +%Y-%m-%dT%H:%M:%SZ`. |

## Semantics

- **Key: `(plugin, target)`.** Re-running a setup for the same plugin and
  target replaces that record; configuring the same plugin for a different
  target (another repo, another scope) adds a record.
- **`remove` deletes.** A setup's `remove` subcommand deletes this plugin's
  record for the target it just cleaned; no record present is silent success.
- **Nothing is pruned automatically; removal is always explicit.** A record
  whose target no longer corresponds to an installation does not self-clear
  on its own — it stays until removed, either through a setup skill's
  `remove` subcommand for a target it can still resolve, or through
  `scripts/prune-stamp.sh` for a target it cannot.
- **Writes are atomic:** jq to a temp file, then `mv`. Absent file is
  created as `{"version": 1, "stamps": []}` before the first record.
- **Corrupt file never blocks setup:** if the file exists but is not valid
  JSON, move it aside to `clam-setup-stamps.json.corrupt-<date>` and start
  fresh; report the move to the user.
- **Stamp failures never fail setup:** the settings write is the setup's
  job; a stamp write failure is reported but the setup still succeeds.
- **Readers treat an absent file as zero stamps** — every plugin is then
  `unstamped`, which consumers must present as "setup state unknown", never
  as "needs setup".
