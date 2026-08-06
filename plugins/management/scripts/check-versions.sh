#!/usr/bin/env bash
# Contract: B01 updates-check-versions (plan 001-update-flow-for-users)
#   Amended by B01 stale-target-reporting (plan 001-stamp-staleness-actionable,
#   issue #239): the stamp column now reports the LOWEST stamp version rather
#   than the highest, and a seventh column stale_targets names the offending
#   targets. Both are specified in Outputs below, which remains the single
#   authoritative statement of this script's contract.
#   Amended again by B01 scope-column (plan 001-update-install-scope, issue
#   #276): an eighth column scope reports where each plugin is installed, so
#   the update skill can pass the right -s flag instead of defaulting to user
#   scope. Specified in Outputs below.
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
#       plugins/management/docs/setup-stamps.md; absent file = zero stamps)
# Inputs:
#   No arguments. Env:
#     CLAUDE_CONFIG_DIR  root to read under (default: $HOME/.claude) — the
#                        override that makes the script testable on fixtures
#     CLAM_MARKETPLACE   marketplace name (default: clam)
# Outputs:
#   TSV on stdout: header
#   "plugin\tinstalled\tlatest\tupdate\tstamp\tsetup\tstale_targets\tscope",
#   then one row per catalog plugin, sorted by plugin name:
#     installed: version | "-" (not installed)
#     latest:    version | "?" (source or plugin.json unresolvable)
#     update:    current | stale | not-installed | unknown
#                (stale = installed and latest both known and different;
#                 unknown = installed but latest is "?")
#     stamp:     the stamp version DRIVING the setup column — the LOWEST
#                version among this plugin's stamps by `sort -V` | "-" (no
#                stamp for this plugin). Lowest, not highest: the setup
#                column reports the worst status across the plugin's
#                stamps, so reporting the highest version made the two
#                columns contradict each other on screen (issue #239).
#                When setup=current every stamp equals installed, so lowest
#                and highest coincide and only the stale case differs.
#     setup:     current | stale | unstamped | "-"
#                (current = every stamp for the plugin equals installed;
#                 stale = any stamp differs from installed;
#                 unstamped = installed but no stamp; "-" = not installed)
#     stale_targets:
#                the absolute `target` path of every stamp whose version
#                differs from installed, joined by ";" in the stamp file's
#                own record order | "-" when the row is not stale (setup =
#                current, unstamped, or "-"). This is what makes a stale
#                row diagnosable without hand-reading the stamp file; the
#                update skill turns each path into a prune offer.
#     scope:     the DISTINCT `scope` values of this plugin's installation
#                entries, in installed_plugins.json's own entry order,
#                joined by ";" | "-" (not installed, or no entry carries a
#                usable scope). This is what lets the update skill pass
#                `-s <scope>` to `claude plugin update` instead of taking
#                the CLI's `user` default, which fails outright for a
#                local-scope install (issue #276).
#                DEDUPLICATED, and that is the point rather than a detail:
#                the normal case is several entries at ONE scope — local
#                installs record one entry per project — so a plugin
#                present in three worktrees must read "local", never
#                "local;local;local".
#                EVERY distinct scope is listed rather than one chosen,
#                because a plugin installed at two scopes needs an update
#                run at each; collapsing to one would leave the other
#                silently stale. Note this is independent of the installed
#                column: scope covers all entries, not just the entry whose
#                version won the `highest` collapse.
#   Plugins installed from OTHER marketplaces are out of scope and never
#   appear. Version comparison is string (in)equality — the marketplace
#   only moves forward; no semver ordering is attempted. NOTE the two
#   distinct uses of `sort -V` here: it orders VERSIONS for the installed
#   and stamp columns, while equality comparisons stay string equality.
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
#     across that plugin's stamps (stale beats current); stamp column is
#     the LOWEST stamp version by `sort -V` (the one driving that status);
#     stale_targets lists every differing stamp's target, not just one;
#     scope lists every distinct scope, in entry order, ";"-joined.
#   - Plugin with several entries all at the SAME scope (the ordinary
#     multi-worktree local install): scope is that one value, not a
#     repeated list.
#   - An installation entry whose `scope` field is absent or empty
#     contributes NOTHING to scope: it is skipped, never emitted as an
#     empty ";;" segment or a trailing ";".
#   - Installed, but no entry carries a usable scope: scope is "-", the
#     same sentinel an uninstalled row gets. Never empty.
#   - A scope value containing ";" or a tab would corrupt the joined field.
#     Scopes are a closed set written by the CLI (user, project, local,
#     managed), so this is out of contract exactly as it is for
#     stale_targets: no escaping is performed and none is expected.
#   - A stamp target containing a ";" or a tab would corrupt the joined
#     stale_targets field. Targets are absolute filesystem paths written by
#     the setup skills, so this is out of contract: no escaping is
#     performed and none is expected.
#   - setup=unstamped or "-": stale_targets is "-", never empty.
#   - Catalog entry whose source path resolves but has no plugin.json:
#     latest "?", update unknown (if installed).
#   - Empty stamps array / absent stamp file: setup = unstamped or "-".
#   - installed_plugins.json v2 shape: plugin keys map to ARRAYS of
#     installation entries.
set -euo pipefail

CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAM_MARKETPLACE="${CLAM_MARKETPLACE:-clam}"

command -v jq &>/dev/null || {
    echo "check-versions: jq is required but was not found on PATH" >&2
    exit 4
}

INSTALLED_FILE="$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
if [[ ! -f "$INSTALLED_FILE" ]]; then
    echo "check-versions: installed plugins file not found: $INSTALLED_FILE" >&2
    exit 2
fi
if ! jq -e '(.plugins // null) | type == "object"' "$INSTALLED_FILE" >/dev/null 2>&1; then
    echo "check-versions: installed plugins file is malformed or missing a 'plugins' object: $INSTALLED_FILE" >&2
    exit 2
fi

MKT_DIR="$CLAUDE_CONFIG_DIR/plugins/marketplaces/$CLAM_MARKETPLACE"
MKT_JSON="$MKT_DIR/.claude-plugin/marketplace.json"
if [[ ! -d "$MKT_DIR" || ! -f "$MKT_JSON" ]]; then
    echo "check-versions: marketplace clone for '$CLAM_MARKETPLACE' not found; run \"/plugin marketplace update $CLAM_MARKETPLACE\" to refresh it" >&2
    exit 3
fi

# Stamp file is read-only reference data (setup-stamps.md); an absent or
# malformed file is never an error here, just zero stamps.
STAMPS_FILE="$CLAUDE_CONFIG_DIR/clam-setup-stamps.json"
STAMPS_DATA='[]'
if [[ -f "$STAMPS_FILE" ]]; then
    if jq -e '(.stamps // null) | type == "array"' "$STAMPS_FILE" >/dev/null 2>&1; then
        STAMPS_DATA=$(jq -c '.stamps' "$STAMPS_FILE")
    else
        echo "check-versions: stamp file is malformed, treating as zero stamps: $STAMPS_FILE" >&2
    fi
fi

# resolve_installed_version installPath entryVersion
# Prints the authoritative version for one installation entry: the
# installPath's own plugin.json when resolvable, else the entry's own
# version field (installed_plugins.json can go stale, per setup-stamps.md).
resolve_installed_version() {
    local install_path="$1" entry_version="$2" plugin_json v
    plugin_json="$install_path/.claude-plugin/plugin.json"
    if [[ -f "$plugin_json" ]] && v=$(jq -r '.version // empty' "$plugin_json" 2>/dev/null) && [[ -n "$v" ]]; then
        printf '%s\n' "$v"
    else
        printf '%s\n' "$entry_version"
    fi
}

# highest_of prints the highest of its arguments per `sort -V` (never plain
# lexicographic sort — the contract calls this out explicitly for
# multi-install "highest" selection).
highest_of() {
    printf '%s\n' "$@" | sort -V | tail -n1
}

# lowest_of prints the lowest of its arguments per `sort -V` — the stamp
# column reports the LOWEST stamp version (issue #239: reporting the
# highest made the stamp and setup columns contradict each other).
lowest_of() {
    printf '%s\n' "$@" | sort -V | head -n1
}

printf 'plugin\tinstalled\tlatest\tupdate\tstamp\tsetup\tstale_targets\tscope\n'

any_stale=0

while IFS=$'\t' read -r name source; do
    src_path="$MKT_DIR/$source"
    plugin_json="$src_path/.claude-plugin/plugin.json"
    latest="?"
    if [[ -f "$plugin_json" ]] && v=$(jq -r '.version // empty' "$plugin_json" 2>/dev/null) && [[ -n "$v" ]]; then
        latest="$v"
    fi

    key="$name@$CLAM_MARKETPLACE"
    entries_json=$(jq -c --arg k "$key" '.plugins[$k] // empty' "$INSTALLED_FILE")

    installed="-"
    scope="-"
    if [[ -n "$entries_json" && "$entries_json" != "null" ]]; then
        versions=()
        # scopes: the DISTINCT scope of every entry, in the entries' own
        # (file) order, deduplicated as they are collected — never sorted,
        # and independent of which entry's version wins the `installed`
        # highest-of collapse below.
        scopes=()
        while IFS=$'\t' read -r install_path entry_version entry_scope; do
            versions+=("$(resolve_installed_version "$install_path" "$entry_version")")
            if [[ -n "$entry_scope" ]]; then
                already_seen=0
                for seen in "${scopes[@]}"; do
                    if [[ "$seen" == "$entry_scope" ]]; then
                        already_seen=1
                        break
                    fi
                done
                [[ "$already_seen" -eq 1 ]] || scopes+=("$entry_scope")
            fi
        done < <(jq -r '.[] | [.installPath, .version, (.scope // "")] | @tsv' <<<"$entries_json")
        if [[ ${#versions[@]} -gt 0 ]]; then
            installed=$(highest_of "${versions[@]}")
        fi
        if [[ ${#scopes[@]} -gt 0 ]]; then
            scope=$(IFS=';'; printf '%s' "${scopes[*]}")
        fi
    fi

    if [[ "$installed" == "-" ]]; then
        update="not-installed"
    elif [[ "$latest" == "?" ]]; then
        update="unknown"
    elif [[ "$installed" == "$latest" ]]; then
        update="current"
    else
        update="stale"
        any_stale=1
    fi

    # Collected in the stamp file's own record order (STAMPS_DATA preserves
    # array order from the file; the jq filter below does not reorder).
    stamp_versions=()
    stamp_targets=()
    while IFS=$'\t' read -r sv st; do
        [[ -n "$sv" ]] || continue
        stamp_versions+=("$sv")
        stamp_targets+=("$st")
    done < <(jq -r --arg p "$name" '.[] | select(.plugin == $p) | [.version, .target] | @tsv' <<<"$STAMPS_DATA")

    if [[ ${#stamp_versions[@]} -eq 0 ]]; then
        stamp="-"
    else
        stamp=$(lowest_of "${stamp_versions[@]}")
    fi

    if [[ "$installed" == "-" ]]; then
        setup="-"
    elif [[ ${#stamp_versions[@]} -eq 0 ]]; then
        setup="unstamped"
    else
        setup="current"
        for sv in "${stamp_versions[@]}"; do
            if [[ "$sv" != "$installed" ]]; then
                setup="stale"
                break
            fi
        done
    fi

    # stale_targets: the target of every differing stamp, in the stamp
    # file's own record order; "-" whenever the row is not stale.
    stale_targets="-"
    if [[ "$setup" == "stale" ]]; then
        differing=()
        for i in "${!stamp_versions[@]}"; do
            if [[ "${stamp_versions[$i]}" != "$installed" ]]; then
                differing+=("${stamp_targets[$i]}")
            fi
        done
        stale_targets=$(IFS=';'; printf '%s' "${differing[*]}")
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$installed" "$latest" "$update" "$stamp" "$setup" "$stale_targets" "$scope"
done < <(jq -r '(.plugins // []) | sort_by(.name)[] | [.name, (.source | ltrimstr("./"))] | @tsv' "$MKT_JSON")

if [[ "$any_stale" -eq 1 ]]; then
    exit 10
fi
exit 0
