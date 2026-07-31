# Setup-stamp protocol

A setup stamp is the record a plugin's setup command writes so that a
later session can tell configured from unconfigured without repeating
the work of finding out. This document is the normative spec for that
record. It is owned by the repository's architecture, is self-contained,
and names no plugin.

## Location

Every setup stamp lives in one JSON file at
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/clam-setup-stamps.json`, shared by
every plugin whose setup command writes a stamp.

## Shape

The file holds `{"version": 1, "stamps": [...]}`. Each entry in `stamps`
is an object with exactly five fields:

- `plugin` — the plugin's name.
- `version` — the plugin's version at the time the stamp was written.
- `scope` — the settings scope that was configured.
- `target` — what was configured: a path, or a scope identifier.
- `at` — an ISO 8601 UTC timestamp.

## Key and lifecycle

A stamp's key is `(plugin, target)`: one stamp per key. Running setup
again for the same key overwrites the existing stamp in place, and a
`remove` or teardown command deletes it.

## Write discipline

A write is atomic: the new document is built with `jq` into a temporary
file, then that file is moved (`mv`) over the original, so a reader never
observes a half-written file. Stamps are advisory records, not the
source of truth for whether setup itself succeeded: a stamp-write
failure never fails the setup that triggered it, and is otherwise logged
and ignored.

## Corruption

A file that fails to parse is moved aside to
`clam-setup-stamps.json.corrupt-<date>` and treated as empty, rather
than raising an error of its own.

## Absence and staleness

No file, or no stamp matching a given key, carries zero information: it
must be presented as "setup state unknown," never as though the plugin
needs setup — absence is not evidence either way. A stamp whose
`version` field is older than the currently installed plugin version
means setup may be stale and may be worth re-running.

## Edge cases

Two plugins stamping concurrently can race: the atomic `mv` makes
last-writer-wins the documented behaviour, and a lost update is an
accepted cost of advisory data rather than a defect to fix. A `stamps`
entry carrying unknown extra fields is tolerated by readers, which read
only the five fields above and ignore the rest.
