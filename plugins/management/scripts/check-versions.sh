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
#   Amended again by plan 001-repo-scoped-report (issues #324, #325): the
#   report is scoped to the repo it is run from — entries belonging to other
#   repositories no longer contribute to any column — installed reports the
#   LOWEST of this repo's versions rather than the highest, and a ninth
#   column stale_installs names the projectPaths still behind. Specified in
#   Outputs below, which remains the single authoritative statement of this
#   script's contract.
# Behavior:
#   Read-only report of every clam-marketplace plugin INSTALLED IN THIS REPO:
#   installed version vs latest available vs setup stamp. Reads three sources
#   under the Claude config dir:
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
#   "plugin\tinstalled\tlatest\tupdate\tstamp\tsetup\tstale_targets\tscope
#    \tstale_installs",
#   then one row per catalog plugin, sorted by plugin name.
#
#   WHICH ENTRIES COUNT (issue #324). installed_plugins.json is machine-wide:
#   it holds one entry per projectPath, including projects in OTHER
#   repositories. Every column below describes ONLY the entries belonging to
#   the repo the script is run from, because the report exists to drive
#   /management:update for THIS repo. An entry counts when:
#     - it carries no projectPath — a user-scope install applies to every
#       repo, including this one; or
#     - its projectPath resolves to the same git common dir as the cwd.
#       Comparing common dirs rather than paths is what makes this
#       worktree-proof: sibling worktrees of one repo share a common dir; or
#     - its projectPath no longer exists but sat under this repo's container
#       directory — a deleted worktree's record, which is exactly the kind
#       that goes silently stale.
#   Run outside any git repository there is nothing to attribute against, so
#   no filtering happens and the report stays machine-wide.
#   Without this filter a sibling repo's entry — usually the NEWEST on the
#   machine — won the installed collapse and the row read `current` while
#   this repo ran a version several releases behind.
#     installed: the LOWEST version among THIS REPO's entries by `sort -V`
#                | "-" (not installed here). Lowest, not highest, for the
#                same reason the stamp column reports the lowest: the row
#                exists to say whether anything here still needs updating,
#                and ONE behind record is enough to mean yes (issue #325).
#                Reporting the highest let an already-updated record mask a
#                behind one — `claude plugin update` resolves a single
#                record, so a repo with several local entries updates them
#                one at a time and spends most of that time in exactly the
#                mixed state the highest collapse hid.
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
#                column: scope covers all of this repo's entries, not just
#                the entry whose version won the `lowest` collapse.
#     stale_installs:
#                the projectPath of every one of THIS REPO's entries whose
#                version differs from latest, joined by ";" in entry order |
#                "-" whenever the row is not stale, or latest is unknown. A
#                user-scope entry has no projectPath and is named "user".
#                This is what keeps a stale row actionable (issue #325).
#                Because installed reports the LOWEST version, a repo whose
#                records disagree stays `stale` until every record is
#                updated; without naming them, that row says work is needed
#                but not where, and `claude plugin update` may not be able
#                to reach a given record at all — it resolves one record per
#                run and exposes no per-projectPath target. Same role for
#                install records that stale_targets plays for stamps.
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
#   - Plugin installed in ANOTHER repo but not this one: the row reads
#     not-installed, exactly as if the foreign entry were absent. It is not
#     this repo's install and no command run here can update it.
#   - Plugin installed in several worktrees of THIS repo at DIFFERENT
#     versions (the ordinary mid-update state): one row; installed is the
#     lowest of them, update reads stale, and stale_installs names every
#     projectPath still behind latest.
#   - Every entry for a plugin belongs to another repo: the row is
#     not-installed and scope is "-", never the foreign entry's scope —
#     passing a foreign record's scope to `-s` fails outright.
#   - A projectPath that no longer exists: counted when it sat under this
#     repo's container directory, ignored otherwise. A deleted worktree's
#     record cannot be resolved through git, and its container is the only
#     evidence left of which repo it belonged to.
#   - SETUP STAMPS ARE NOT REPO-FILTERED. The repo scoping above applies to
#     installation entries only; the stamp/setup/stale_targets columns still
#     consider every stamp for the plugin, so stale_targets can name a path
#     in another repository. A stamp records a `target` settings file rather
#     than a project root, so attributing one to a repo is a different
#     problem than attributing an install entry, and it is deliberately left
#     to its own change rather than guessed at here.
#   - Not inside a git repository: no attribution is possible, so no
#     filtering happens and every entry counts (machine-wide, the pre-#324
#     behaviour). The report is still internally consistent; it simply
#     describes the machine rather than a repo.
#   - Plugin installed at multiple scopes: one row; installed = lowest
#     version among this repo's entries by `sort -V`; setup column is the worst status
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
#   - update=current, not-installed, or unknown: stale_installs is "-",
#     never empty. A row needing no update names no path.
#   - A projectPath containing a ";" or a tab would corrupt the joined
#     stale_installs field. Same standing as stale_targets: these are
#     absolute filesystem paths written by the CLI, so no escaping is
#     performed and none is expected.
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

# lowest_of prints the lowest of its arguments per `sort -V` (never plain
# lexicographic sort). Both multi-value columns take the lowest: the stamp
# column since #239 (reporting the highest made the stamp and setup columns
# contradict each other) and the installed column since #325 (reporting the
# highest let an updated record mask a behind one).
lowest_of() {
    printf '%s\n' "$@" | sort -V | head -n1
}

# This repo's git common dir, resolved absolutely so sibling worktrees of the
# same repo compare equal (they share one common dir; their working-tree paths
# differ). Empty when the script is run outside a git repository, which turns
# the entry filter off rather than emptying the report.
REPO_COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
REPO_CONTAINER=""
[[ -n "$REPO_COMMON" ]] && REPO_CONTAINER=$(dirname "$REPO_COMMON")

# Resolving a projectPath costs a git invocation, and the same handful of
# paths recur across every plugin in the catalog, so each verdict is cached.
declare -A REPO_MATCH_CACHE=()

# entry_in_this_repo projectPath
# Succeeds when an installation entry belongs to the repo being reported on.
# See "WHICH ENTRIES COUNT" in the contract above for why each case counts.
entry_in_this_repo() {
    local pp="$1" cached common verdict
    [[ -n "$pp" ]] || return 0
    [[ -n "$REPO_COMMON" ]] || return 0

    cached="${REPO_MATCH_CACHE[$pp]:-}"
    if [[ -n "$cached" ]]; then
        [[ "$cached" == "1" ]]
        return
    fi

    verdict=0
    if [[ -d "$pp" ]]; then
        common=$(git -C "$pp" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
        [[ -n "$common" && "$common" == "$REPO_COMMON" ]] && verdict=1
    elif [[ -n "$REPO_CONTAINER" && "$pp" == "$REPO_CONTAINER"/* ]]; then
        verdict=1
    fi

    REPO_MATCH_CACHE["$pp"]="$verdict"
    [[ "$verdict" == "1" ]]
}

printf 'plugin\tinstalled\tlatest\tupdate\tstamp\tsetup\tstale_targets\tscope\tstale_installs\n'

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
    # Reset per row: a plugin with no entries in THIS repo must report as
    # not-installed, never inherit the previous row's records.
    versions=()
    version_paths=()
    # scopes: the DISTINCT scope of every one of THIS REPO's entries, in the
    # entries' own (file) order, deduplicated as they are collected — never
    # sorted, and independent of which entry's version wins the `installed`
    # lowest-of collapse below.
    scopes=()
    if [[ -n "$entries_json" && "$entries_json" != "null" ]]; then
        while IFS=$'\t' read -r install_path entry_version entry_scope project_path; do
            entry_in_this_repo "$project_path" || continue
            versions+=("$(resolve_installed_version "$install_path" "$entry_version")")
            # A user-scope entry has no projectPath; name it so stale_installs
            # can still point at something a reader can act on.
            version_paths+=("${project_path:-user}")
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
        done < <(jq -r '.[] | [.installPath, .version, (.scope // ""), (.projectPath // "")] | @tsv' <<<"$entries_json")
        if [[ ${#versions[@]} -gt 0 ]]; then
            installed=$(lowest_of "${versions[@]}")
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

    # stale_installs: which of THIS repo's install records are still behind
    # latest, in entry order; "-" whenever the row needs no update. Compared
    # against latest rather than against installed, because installed is the
    # lowest and comparing to it would name the records that are AHEAD.
    stale_installs="-"
    if [[ "$update" == "stale" ]]; then
        behind=()
        for i in "${!versions[@]}"; do
            if [[ "${versions[$i]}" != "$latest" ]]; then
                behind+=("${version_paths[$i]}")
            fi
        done
        if [[ ${#behind[@]} -gt 0 ]]; then
            stale_installs=$(IFS=';'; printf '%s' "${behind[*]}")
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$installed" "$latest" "$update" "$stamp" "$setup" "$stale_targets" "$scope" "$stale_installs"
done < <(jq -r '(.plugins // []) | sort_by(.name)[] | [.name, (.source | ltrimstr("./"))] | @tsv' "$MKT_JSON")

if [[ "$any_stale" -eq 1 ]]; then
    exit 10
fi
exit 0
