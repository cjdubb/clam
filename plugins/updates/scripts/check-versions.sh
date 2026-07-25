#!/usr/bin/env bash
# Contract: B01 updates-check-versions (plan 001-update-flow-for-users)
# Behavior:
#   Read-only report of every clam-marketplace plugin: installed version vs
#   latest available vs setup stamp. Reads three sources under the Claude
#   config dir:
#     - plugins/installed_plugins.json          (what is installed, keyed
#       "<plugin>@<marketplace>"; installed version is read from the
#       plugin.json at each entry's installPath when resolvable, falling
#       back to the entry's own version field)
#     - plugins/marketplaces/<mkt>/.claude-plugin/marketplace.json  (the
#       catalog; "latest" for each listed plugin is the version in
#       <clone>/<source>/.claude-plugin/plugin.json — marketplace entries
#       carry no version by repo convention)
#     - clam-setup-stamps.json                  (setup stamps, format per
#       plugins/updates/docs/setup-stamps.md; absent file = zero stamps)
# Inputs:
#   No arguments. Env:
#     CLAUDE_CONFIG_DIR  root to read under (default: $HOME/.claude) — the
#                        override that makes the script testable on fixtures
#     CLAM_MARKETPLACE   marketplace name (default: clam)
# Outputs:
#   TSV on stdout: header "plugin\tinstalled\tlatest\tupdate\tstamp\tsetup",
#   then one row per catalog plugin, sorted by plugin name:
#     installed: version | "-" (not installed)
#     latest:    version | "?" (source or plugin.json unresolvable)
#     update:    current | stale | not-installed | unknown
#                (stale = installed and latest both known and different;
#                 unknown = installed but latest is "?")
#     stamp:     stamped version | "-" (no stamp for this plugin)
#     setup:     current | stale | unstamped | "-"
#                (current = every stamp for the plugin equals installed;
#                 stale = any stamp differs from installed;
#                 unstamped = installed but no stamp; "-" = not installed)
#   Plugins installed from OTHER marketplaces are out of scope and never
#   appear. Version comparison is string (in)equality — the marketplace
#   only moves forward; no semver ordering is attempted.
# Errors:
#   exit 2: installed_plugins.json missing or malformed (stderr message)
#   exit 3: marketplace clone missing — stderr suggests running
#           "/plugin marketplace update <mkt>" first
#   exit 4: jq not available
#   Malformed stamp file is NOT an error: warn on stderr, treat as zero
#   stamps (read-only script never moves the corrupt file aside).
# Exit status on success:
#   0  report printed, no row has update=stale
#   10 report printed, at least one row has update=stale
# Invariants:
#   - Read-only: writes nothing anywhere; no network access.
#   - Deterministic: same inputs -> same output bytes and exit code.
#   - Header line is always printed, even for an empty catalog.
# Edge cases:
#   - Plugin installed at multiple scopes: one row; installed = highest
#     version among entries by `sort -V`; setup column is the worst status
#     across that plugin's stamps (stale beats current).
#   - Catalog entry whose source path resolves but has no plugin.json:
#     latest "?", update unknown (if installed).
#   - Empty stamps array / absent stamp file: setup = unstamped or "-".
#   - installed_plugins.json v2 shape: plugin keys map to ARRAYS of
#     installation entries.
set -euo pipefail

echo "NotImplemented: B01 updates-check-versions" >&2
exit 70
