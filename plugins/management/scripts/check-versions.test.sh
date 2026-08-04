#!/bin/bash
# Functional test for check-versions.sh: read-only catalog/installed/stamp
# report (Contract: B01 updates-check-versions, docblock in
# check-versions.sh; companion format contract:
# plugins/management/docs/setup-stamps.md).
# Run: bash plugins/management/scripts/check-versions.test.sh
# (exits non-zero on failure)
#
# The script reads three sources under $CLAUDE_CONFIG_DIR (default
# $HOME/.claude), so every fixture below builds a fake config-dir tree
# matching the REAL on-disk shapes (verified against a live ~/.claude/
# during test authoring):
#   plugins/installed_plugins.json
#     {"version":2,"plugins":{"<name>@<mkt>":[{"scope":...,
#       "installPath":...,"version":...,"projectPath"?:...}, ...]}}
#   plugins/marketplaces/<mkt>/.claude-plugin/marketplace.json
#     {"name":...,"owner":{...},"plugins":[{"name":...,"source":"./plugins/x",
#       "description":...}, ...]}  (no per-entry version, by repo convention)
#   <clone>/<source, "./" stripped>/.claude-plugin/plugin.json
#     {"name":...,"version":...,"description":...,"author":{...}}
#   clam-setup-stamps.json (top-level of config dir, per setup-stamps.md)
#     {"version":1,"stamps":[{"plugin":...,"version":...,"scope":...,
#       "target":...,"at":...}]}
#
# Every fixture is fully self-contained under $TMPROOT (removed on exit).
# No network.
#
# Amended for B01 stale-target-reporting (plan 001-stamp-staleness-actionable,
# issue #239). The contract gained a seventh column, stale_targets, and the
# stamp column now reports the LOWEST stamp version by `sort -V` rather than
# the highest. The script still emits the OLD six-column output, so every
# assertion touching the seventh column, and the two stamp-column assertions
# whose lowest/highest choice actually differs (MULTI multi, STALETARGETS
# st-many/st-mixed), are expected to fail red until the implementation
# catches up. Failures are assertion failures, not collection errors: the
# suite itself runs to completion.
#
# Clause coverage map (contract clause -> fixture/case):
#   TSV header (7 columns) + one sorted row per catalog plugin -> MAIN
#   column semantics: update current/stale/not-installed/unknown -> MAIN
#   column semantics: setup current/stale/unstamped/"-"       -> MAIN
#   installed: installPath plugin.json, fallback to entry .version -> FALLBACK
#   latest: clone source-path plugin.json; unresolvable -> "?"  -> LATEST
#   update/latest precedence when not installed at all        -> LATEST
#   exit 0 (no stale)                                          -> NOSTAMP
#   exit 10 (>=1 stale)                                        -> MAIN
#   exit 0 keys on update=stale, NOT on setup=stale            -> STALETARGETS
#   exit 2 (missing/malformed installed_plugins.json)          -> NOINSTALLED, BADINSTALLED
#   exit 3 (missing marketplace clone)                         -> NOMKT, NOMKTJSON
#   exit 4 (no jq)                                              -> NOJQ
#   malformed stamp file: warn, zero stamps, not an error exit -> BADSTAMP
#   multi-install: one row, installed = highest by sort -V,
#     worst setup wins                                         -> MULTI
#   stamp column = LOWEST stamp version by sort -V (lexicographic
#     and version order deliberately disagree)                 -> MULTI, STALETARGETS
#   stamp "-" only when the plugin has no stamp at all         -> MAIN, STALETARGETS
#   stale_targets "-" when setup=current                       -> MAIN, MULTI, STALETARGETS
#   stale_targets "-" when setup=unstamped                     -> MAIN, STALETARGETS
#   stale_targets "-" when not installed (setup="-")           -> MAIN, STALETARGETS
#   stale_targets = exactly that stamp's target (one stale stamp) -> MAIN, MULTI, STALETARGETS
#   stale_targets = every differing target, ";"-joined, in the
#     stamp file's own record order                            -> STALETARGETS
#   stale_targets lists only the DIFFERING stamps of a plugin
#     whose stamps are a mix of matching and differing         -> STALETARGETS
#   stale_targets is a per-plugin field (never another plugin's
#     targets)                                                 -> MAIN, STALETARGETS
#   version comparison is string (in)equality, never ordering  -> MAIN, STALETARGETS
#   empty catalog -> header only, exit 0                       -> EMPTY
#   absent stamp file -> unstamped/"-"                         -> NOSTAMP
#   empty stamps array -> unstamped/"-"                        -> EMPTYSTAMPS
#   read-only invariant                                        -> MAIN, STALETARGETS
#   determinism                                                -> MAIN
#   out-of-scope: install under a different marketplace key    -> SCOPE
#   CLAM_MARKETPLACE override + default                        -> MKT
#   CLAUDE_CONFIG_DIR default ($HOME/.claude)                  -> HOMEDEFAULT
#   ";" or tab inside a stamp target                           -> explicitly
#     out of contract ("no escaping is performed and none is expected"),
#     deliberately not tested

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-versions.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

STDOUT="$TMPROOT/.stdout"
STDERR="$TMPROOT/.stderr"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }
check() { # label got expected
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 -> got '$2', expected '$3'"; fi
}
check_true() { # label yes/no
  check "$1" "$2" "yes"
}

HEADER=$'plugin\tinstalled\tlatest\tupdate\tstamp\tsetup\tstale_targets'

# --- Fixture-building helpers ------------------------------------------------

# mkplugin_json <dir> <version> [name]
# Writes a real plugin.json (name/version/description/author) at <dir>/.claude-plugin/plugin.json.
mkplugin_json() {
  mkdir -p "$1/.claude-plugin"
  printf '{"name":"%s","version":"%s","description":"d","author":{"name":"a","email":"a@b.c"}}' \
    "${3:-p}" "$2" > "$1/.claude-plugin/plugin.json"
}

# init_marketplace <cfg> <mkt> <plugins-json-array-literal>
init_marketplace() {
  local cfg="$1" mkt="$2" plugins="$3"
  mkdir -p "$cfg/plugins/marketplaces/$mkt/.claude-plugin"
  printf '{"name":"%s","owner":{"name":"o","email":"o@b.c"},"plugins":%s}' "$mkt" "$plugins" \
    > "$cfg/plugins/marketplaces/$mkt/.claude-plugin/marketplace.json"
}

# clone_source_plugin <cfg> <mkt> <source-relpath, e.g. ./plugins/foo> <version> [name]
clone_source_plugin() {
  local cfg="$1" mkt="$2" src="${3#./}" version="$4" name="${5:-p}"
  mkplugin_json "$cfg/plugins/marketplaces/$mkt/$src" "$version" "$name"
}

# write_installed <cfg> <plugins-json-object-literal>
write_installed() {
  mkdir -p "$1/plugins"
  printf '{"version":2,"plugins":%s}' "$2" > "$1/plugins/installed_plugins.json"
}

# write_stamps <cfg> <json-literal>
write_stamps() {
  printf '%s' "$2" > "$1/clam-setup-stamps.json"
}

# an installation entry object, given an installPath and version (own field)
inst_entry() { # installPath version [scope]
  printf '{"scope":"%s","installPath":"%s","version":"%s","installedAt":"2026-01-01T00:00:00.000Z","lastUpdated":"2026-01-01T00:00:00.000Z"}' \
    "${3:-user}" "$1" "$2"
}

tree_digest() { find "$1" -type f -exec md5sum {} \; 2>/dev/null | sed "s#$1#<ROOT>#" | sort; }

# run_check <cfg> [marketplace-override]
run_check() {
  if [[ -n "${2:-}" ]]; then
    CLAUDE_CONFIG_DIR="$1" CLAM_MARKETPLACE="$2" bash "$SCRIPT" >"$STDOUT" 2>"$STDERR"
  else
    CLAUDE_CONFIG_DIR="$1" bash "$SCRIPT" >"$STDOUT" 2>"$STDERR"
  fi
  RC=$?
  OUT=$(cat "$STDOUT")
  ERR=$(cat "$STDERR")
}

# run_check_home <home>  -- CLAUDE_CONFIG_DIR unset, exercises the default
run_check_home() {
  env -u CLAUDE_CONFIG_DIR HOME="$1" bash "$SCRIPT" >"$STDOUT" 2>"$STDERR"
  RC=$?
  OUT=$(cat "$STDOUT")
  ERR=$(cat "$STDERR")
}

# run_check_nojq <cfg>  -- jq excluded from PATH
run_check_nojq() {
  CLAUDE_CONFIG_DIR="$1" PATH="$NOJQ_BIN" bash "$SCRIPT" >"$STDOUT" 2>"$STDERR"
  RC=$?
  OUT=$(cat "$STDOUT")
  ERR=$(cat "$STDERR")
}

# row_of <tsv> <plugin> -> the matching data row (excluding header), or empty
row_of() {
  awk -F'\t' -v p="$2" 'NR>1 && $1==p {print; exit}' <<<"$1"
}
# field_of <row> <index 1-based>
field_of() {
  awk -F'\t' -v i="$2" '{print $i}' <<<"$1"
}
# check_row <label> <tsv> <plugin> <installed> <latest> <update> <stamp> <setup> <stale_targets>
check_row() {
  local label="$1" tsv="$2" plugin="$3" exp_installed="$4" exp_latest="$5" exp_update="$6" exp_stamp="$7" exp_setup="$8" exp_stale_targets="$9"
  local row; row=$(row_of "$tsv" "$plugin")
  check_true "$label: row present" "$([[ -n "$row" ]] && echo yes || echo no)"
  check "$label: installed column" "$(field_of "$row" 2)" "$exp_installed"
  check "$label: latest column" "$(field_of "$row" 3)" "$exp_latest"
  check "$label: update column" "$(field_of "$row" 4)" "$exp_update"
  check "$label: stamp column" "$(field_of "$row" 5)" "$exp_stamp"
  check "$label: setup column" "$(field_of "$row" 6)" "$exp_setup"
  check "$label: stale_targets column" "$(field_of "$row" 7)" "$exp_stale_targets"
}

# A stub PATH with common coreutils (including bash) symlinked in, but
# deliberately excluding jq, so "jq not available" can be exercised without
# touching the real system PATH. Mirrors activity.test.sh's NOJQ_BIN.
NOJQ_BIN="$TMPROOT/no-jq-bin"
mkdir -p "$NOJQ_BIN"
for tool in bash sh cat rm tr mkdir printf sed grep basename dirname wc head tail cp mv touch date ls sort mktemp readlink realpath env find stat cut awk; do
  src=$(command -v "$tool" 2>/dev/null) || continue
  ln -sf "$src" "$NOJQ_BIN/$tool" 2>/dev/null
done

echo "=== Fixture MAIN: header, sort order, full column-semantics matrix, exit 10, read-only, determinism ==="
# ============================================================================
# Six catalog plugins (deliberately scrambled in the catalog JSON), one per
# combination of update/setup state named in the contract:
#   alpha:   installed==latest, stamp matches       -> update=current,      setup=current
#   beta:    installed!=latest, stamp matches       -> update=stale,        setup=current
#   delta:   installed known, source unresolvable   -> update=unknown,      setup=unstamped (no stamp)
#   epsilon: installed==latest, no stamp for it     -> update=current,      setup=unstamped
#   gamma:   not installed at all                   -> update=not-installed, setup="-"
#   zeta:    installed==latest, stamp MISMATCHES    -> update=current,      setup=stale
# Exactly one row (beta) is stale, so exit must be 10.
# ============================================================================

CFG_MAIN="$TMPROOT/cfg-main"
init_marketplace "$CFG_MAIN" clam '[
  {"name":"zeta","source":"./plugins/zeta","description":"d"},
  {"name":"alpha","source":"./plugins/alpha","description":"d"},
  {"name":"gamma","source":"./plugins/gamma","description":"d"},
  {"name":"delta","source":"./plugins/delta","description":"d"},
  {"name":"beta","source":"./plugins/beta","description":"d"},
  {"name":"epsilon","source":"./plugins/epsilon","description":"d"}
]'
clone_source_plugin "$CFG_MAIN" clam ./plugins/alpha   1.0.0 alpha
clone_source_plugin "$CFG_MAIN" clam ./plugins/beta    2.0.0 beta
clone_source_plugin "$CFG_MAIN" clam ./plugins/gamma   3.0.0 gamma
clone_source_plugin "$CFG_MAIN" clam ./plugins/epsilon 1.0.0 epsilon
clone_source_plugin "$CFG_MAIN" clam ./plugins/zeta    2.0.0 zeta
# delta: deliberately NO ./plugins/delta directory under the clone -> unresolvable source

mkplugin_json "$CFG_MAIN/plugins/cache/clam/alpha/1.0.0"   1.0.0 alpha
mkplugin_json "$CFG_MAIN/plugins/cache/clam/beta/1.0.0"    1.0.0 beta
mkplugin_json "$CFG_MAIN/plugins/cache/clam/delta/1.5.0"   1.5.0 delta
mkplugin_json "$CFG_MAIN/plugins/cache/clam/epsilon/1.0.0" 1.0.0 epsilon
mkplugin_json "$CFG_MAIN/plugins/cache/clam/zeta/2.0.0"    2.0.0 zeta

write_installed "$CFG_MAIN" "{
  \"alpha@clam\":   [$(inst_entry "$CFG_MAIN/plugins/cache/clam/alpha/1.0.0" 1.0.0)],
  \"beta@clam\":    [$(inst_entry "$CFG_MAIN/plugins/cache/clam/beta/1.0.0" 1.0.0)],
  \"delta@clam\":   [$(inst_entry "$CFG_MAIN/plugins/cache/clam/delta/1.5.0" 1.5.0)],
  \"epsilon@clam\": [$(inst_entry "$CFG_MAIN/plugins/cache/clam/epsilon/1.0.0" 1.0.0)],
  \"zeta@clam\":    [$(inst_entry "$CFG_MAIN/plugins/cache/clam/zeta/2.0.0" 2.0.0)]
}"

# Each stamp carries a DISTINCT target so that zeta's stale_targets value
# proves the field is scoped to that plugin's own stamps, rather than being
# satisfied by whatever target happens to be in the file.
write_stamps "$CFG_MAIN" '{
  "version": 1,
  "stamps": [
    {"plugin":"alpha","version":"1.0.0","scope":"user","target":"/t/alpha","at":"2026-01-01T00:00:00Z"},
    {"plugin":"beta","version":"1.0.0","scope":"user","target":"/t/beta","at":"2026-01-01T00:00:00Z"},
    {"plugin":"zeta","version":"1.0.0","scope":"user","target":"/t/zeta","at":"2026-01-01T00:00:00Z"}
  ]
}'

DIGEST_BEFORE=$(tree_digest "$CFG_MAIN")
run_check "$CFG_MAIN"
OUT1="$OUT"; RC1="$RC"

check "MAIN: header line exact text" "$(head -n1 <<<"$OUT1")" "$HEADER"
check "MAIN: row names in order match sorted catalog names" \
  "$(tail -n +2 <<<"$OUT1" | cut -f1)" "$(printf 'alpha\nbeta\ndelta\nepsilon\ngamma\nzeta')"
check "MAIN: exactly 7 lines total (header + 6 rows)" "$(wc -l <<<"$OUT1" | tr -d ' ')" "7"

# stale_targets (7th arg): "-" for every row whose setup is current,
# unstamped or "-"; only zeta is setup=stale, and its single differing stamp
# names /t/zeta.
check_row "MAIN alpha (current/current)"        "$OUT1" alpha   1.0.0 1.0.0 current       1.0.0 current   "-"
check_row "MAIN beta (stale-update/current-setup)" "$OUT1" beta 1.0.0 2.0.0 stale         1.0.0 current   "-"
check_row "MAIN delta (unknown-latest/unstamped)"  "$OUT1" delta 1.5.0 "?"  unknown       "-"   unstamped "-"
check_row "MAIN epsilon (current/unstamped)"    "$OUT1" epsilon 1.0.0 1.0.0 current       "-"   unstamped "-"
check_row "MAIN gamma (not installed, all dashes)" "$OUT1" gamma "-"   3.0.0 not-installed "-"   "-"       "-"
check_row "MAIN zeta (current-update/stale-setup)" "$OUT1" zeta 2.0.0 2.0.0 current       1.0.0 stale     /t/zeta

check "MAIN: exit 10 (>=1 stale row present)" "$RC1" "10"

DIGEST_AFTER=$(tree_digest "$CFG_MAIN")
check "MAIN: fixture tree byte-identical after run (read-only)" "$DIGEST_AFTER" "$DIGEST_BEFORE"

run_check "$CFG_MAIN"
check "MAIN: determinism, stdout identical across two runs" "$OUT" "$OUT1"
check "MAIN: determinism, exit code identical across two runs" "$RC" "$RC1"

echo ""
echo "=== Fixture FALLBACK: installed version resolution (installPath plugin.json, fallback to entry .version) ==="
# ============================================================================
# - resolvable-fb:  installPath resolves; its plugin.json (3.5.0) must win
#                   over the entry's own (deliberately stale) .version field.
# - unresolvable-fb: installPath points nowhere; falls back to entry .version.
# - noPluginJson-fb: installPath is a real directory but has no plugin.json
#                    inside (a second unresolvable flavor); falls back too.
# ============================================================================

CFG_FB="$TMPROOT/cfg-fallback"
init_marketplace "$CFG_FB" clam '[
  {"name":"resolvable-fb","source":"./plugins/resolvable-fb","description":"d"},
  {"name":"unresolvable-fb","source":"./plugins/unresolvable-fb","description":"d"},
  {"name":"noPluginJson-fb","source":"./plugins/noPluginJson-fb","description":"d"}
]'
clone_source_plugin "$CFG_FB" clam ./plugins/resolvable-fb   3.5.0 resolvable-fb
clone_source_plugin "$CFG_FB" clam ./plugins/unresolvable-fb 4.2.0 unresolvable-fb
clone_source_plugin "$CFG_FB" clam ./plugins/noPluginJson-fb 5.5.0 noPluginJson-fb

# resolvable: installPath has a real, authoritative plugin.json (3.5.0); the
# entry's own .version field is deliberately wrong (9.9.9) to prove it's ignored.
mkplugin_json "$CFG_FB/plugins/cache/clam/resolvable-fb/3.5.0" 3.5.0 resolvable-fb
# unresolvable: installPath directory never created at all.
UNRESOLVABLE_PATH="$CFG_FB/plugins/cache/clam/unresolvable-fb/DOES-NOT-EXIST"
# noPluginJson: installPath directory exists, but no .claude-plugin/plugin.json inside.
mkdir -p "$CFG_FB/plugins/cache/clam/noPluginJson-fb/5.5.0"

write_installed "$CFG_FB" "{
  \"resolvable-fb@clam\":   [$(inst_entry "$CFG_FB/plugins/cache/clam/resolvable-fb/3.5.0" 9.9.9)],
  \"unresolvable-fb@clam\": [$(inst_entry "$UNRESOLVABLE_PATH" 4.2.0)],
  \"noPluginJson-fb@clam\": [$(inst_entry "$CFG_FB/plugins/cache/clam/noPluginJson-fb/5.5.0" 5.5.0)]
}"

run_check "$CFG_FB"
check_row "FALLBACK resolvable-fb (installPath plugin.json wins over stale entry .version)" \
  "$OUT" resolvable-fb 3.5.0 3.5.0 current "-" unstamped "-"
check_row "FALLBACK unresolvable-fb (installPath missing entirely -> entry .version used)" \
  "$OUT" unresolvable-fb 4.2.0 4.2.0 current "-" unstamped "-"
check_row "FALLBACK noPluginJson-fb (installPath dir has no plugin.json -> entry .version used)" \
  "$OUT" noPluginJson-fb 5.5.0 5.5.0 current "-" unstamped "-"

echo ""
echo "=== Fixture LATEST: marketplace-clone latest resolution, and not-installed/unknown precedence ==="
# ============================================================================
# - src-missing:        catalog source dir absent from the clone entirely.
# - src-no-pluginjson:  catalog source dir exists but has no plugin.json.
#   Both installed -> latest "?", update unknown.
# - gone-and-uninstalled: source absent AND never installed -> update must be
#   "not-installed" (not "unknown"): "unknown" presupposes installed is known.
# ============================================================================

CFG_LATEST="$TMPROOT/cfg-latest"
init_marketplace "$CFG_LATEST" clam '[
  {"name":"src-missing","source":"./plugins/src-missing","description":"d"},
  {"name":"src-no-pluginjson","source":"./plugins/src-no-pluginjson","description":"d"},
  {"name":"gone-and-uninstalled","source":"./plugins/gone-and-uninstalled","description":"d"}
]'
# src-missing: no directory created under the clone at all.
mkdir -p "$CFG_LATEST/plugins/marketplaces/clam/plugins/src-no-pluginjson"  # dir exists, no plugin.json
# gone-and-uninstalled: no directory either, and no installed_plugins.json entry.

mkplugin_json "$CFG_LATEST/plugins/cache/clam/src-missing/1.0.0"        1.0.0 src-missing
mkplugin_json "$CFG_LATEST/plugins/cache/clam/src-no-pluginjson/2.0.0"  2.0.0 src-no-pluginjson

write_installed "$CFG_LATEST" "{
  \"src-missing@clam\":       [$(inst_entry "$CFG_LATEST/plugins/cache/clam/src-missing/1.0.0" 1.0.0)],
  \"src-no-pluginjson@clam\": [$(inst_entry "$CFG_LATEST/plugins/cache/clam/src-no-pluginjson/2.0.0" 2.0.0)]
}"

run_check "$CFG_LATEST"
check_row "LATEST src-missing (source dir absent -> latest '?', update unknown)" \
  "$OUT" src-missing 1.0.0 "?" unknown "-" unstamped "-"
check_row "LATEST src-no-pluginjson (source dir has no plugin.json -> latest '?', update unknown)" \
  "$OUT" src-no-pluginjson 2.0.0 "?" unknown "-" unstamped "-"
check_row "LATEST gone-and-uninstalled (not installed wins over unknown latest)" \
  "$OUT" gone-and-uninstalled "-" "?" not-installed "-" "-" "-"

echo ""
echo "=== Fixture MULTI: multiple installations of one plugin (sort -V, worst-setup-wins) ==="
# ============================================================================
# - multi: two installations, versions "2.9.0" and "2.10.0". A naive
#   lexicographic sort would pick "2.9.0" as "highest"; sort -V must pick
#   "2.10.0". Stamps: one matches the highest (2.10.0, target /y), one
#   doesn't (2.9.0, target /x) -> setup must be "stale" (worst wins), and
#   stale_targets must be exactly "/x" -- the differing stamp only, never
#   the matching one.
#   The same 2.9.0/2.10.0 pair pins the stamp column in the other
#   direction: it reports the LOWEST stamp version by sort -V, i.e. the one
#   driving setup=stale, so stamp is "2.9.0". Lexicographic ordering would
#   answer "2.10.0" and the old contract's "highest" would answer "2.10.0"
#   too, so this single assertion separates all three.
# - multi-current: same two-installation shape, but BOTH stamps match the
#   highest version -> setup must be "current" (proves worst-wins isn't
#   simply "always stale with >1 install"), stamp is 2.10.0 (with every
#   stamp equal, lowest and highest coincide), and stale_targets is "-"
#   even though the plugin has two stamps with real targets.
# ============================================================================

CFG_MULTI="$TMPROOT/cfg-multi"
init_marketplace "$CFG_MULTI" clam '[
  {"name":"multi","source":"./plugins/multi","description":"d"},
  {"name":"multi-current","source":"./plugins/multi-current","description":"d"}
]'
clone_source_plugin "$CFG_MULTI" clam ./plugins/multi         2.10.0 multi
clone_source_plugin "$CFG_MULTI" clam ./plugins/multi-current 2.10.0 multi-current

mkplugin_json "$CFG_MULTI/plugins/cache/clam/multi/2.9.0"          2.9.0  multi
mkplugin_json "$CFG_MULTI/plugins/cache/clam/multi/2.10.0"         2.10.0 multi
mkplugin_json "$CFG_MULTI/plugins/cache/clam/multi-current/2.10.0-a" 2.10.0 multi-current
mkplugin_json "$CFG_MULTI/plugins/cache/clam/multi-current/2.10.0-b" 2.10.0 multi-current

write_installed "$CFG_MULTI" "{
  \"multi@clam\": [
    $(inst_entry "$CFG_MULTI/plugins/cache/clam/multi/2.9.0" 2.9.0 user),
    $(inst_entry "$CFG_MULTI/plugins/cache/clam/multi/2.10.0" 2.10.0 project)
  ],
  \"multi-current@clam\": [
    $(inst_entry "$CFG_MULTI/plugins/cache/clam/multi-current/2.10.0-a" 2.10.0 user),
    $(inst_entry "$CFG_MULTI/plugins/cache/clam/multi-current/2.10.0-b" 2.10.0 project)
  ]
}"

write_stamps "$CFG_MULTI" '{
  "version": 1,
  "stamps": [
    {"plugin":"multi","version":"2.9.0","scope":"user","target":"/x","at":"2026-01-01T00:00:00Z"},
    {"plugin":"multi","version":"2.10.0","scope":"project","target":"/y","at":"2026-01-01T00:00:00Z"},
    {"plugin":"multi-current","version":"2.10.0","scope":"user","target":"/x","at":"2026-01-01T00:00:00Z"},
    {"plugin":"multi-current","version":"2.10.0","scope":"project","target":"/y","at":"2026-01-01T00:00:00Z"}
  ]
}'

run_check "$CFG_MULTI"
check_row "MULTI multi (installed=highest 2.10.0 via sort -V; stamp=lowest 2.9.0; worst setup=stale; only the differing stamp's target)" \
  "$OUT" multi 2.10.0 2.10.0 current 2.9.0 stale /x
check_row "MULTI multi-current (all installs+stamps agree -> setup=current, no stale targets)" \
  "$OUT" multi-current 2.10.0 2.10.0 current 2.10.0 current "-"

echo ""
echo "=== Fixture STALETARGETS: the stale_targets column, and the stamp column as the LOWEST stamp version ==="
# ============================================================================
# Every plugin here has installed == latest, so update is "current"
# everywhere and the exit code must be 0 -- which also proves the exit code
# keys on update=stale and not on setup=stale, of which this fixture has
# three.
#
# - st-one:         one stamp, differing -> stale_targets is exactly that
#                   stamp's target.
# - st-many:        three stamps, all differing -> all three targets,
#                   ";"-joined, in the STAMP FILE's own record order. That
#                   order (zulu, alpha, mike) is deliberately distinct from
#                   version-ascending (alpha, zulu, mike), version-descending
#                   (mike, zulu, alpha) and target-lexicographic (alpha,
#                   mike, zulu), so only record order passes.
#                   Its stamp versions 1.10.0 / 1.9.0 / 1.11.0 also pin the
#                   stamp column three ways at once: lowest by sort -V is
#                   1.9.0, lexicographic-lowest would be "1.10.0", and the
#                   pre-#239 "highest" would be 1.11.0.
# - st-mixed:       four stamps, two matching installed and two not -> only
#                   the two differing targets appear, still in record order
#                   (they are not adjacent in the file). Stamp column is
#                   2.9.0: the lowest by sort -V across ALL of the plugin's
#                   stamps, matching or not (lexicographic-lowest would be
#                   "2.10.0").
# - st-current:     two stamps, both matching -> setup current, and
#                   stale_targets is "-" even though real targets exist, so
#                   the column cannot be "the plugin's targets".
# - st-unstamped:   installed, with no stamp of its own in a stamp file that
#                   does hold other plugins' stamps -> stamp "-",
#                   stale_targets "-".
# - st-uninstalled: NOT installed, yet a leftover stamp names it -> setup "-"
#                   and stale_targets "-" (Edge cases: 'setup=unstamped or
#                   "-": stale_targets is "-", never empty'). It carries
#                   exactly one stamp, so its stamp column is that version
#                   under either reading of "lowest".
# - st-newer:       its one stamp is ABOVE installed (2.0.0 vs 1.0.0). The
#                   contract compares stamp to installed by string
#                   (in)equality, not by ordering, so this is stale too and
#                   its target appears -- "differs" must not be implemented
#                   as "older than installed".
# ============================================================================

CFG_ST="$TMPROOT/cfg-staletargets"
init_marketplace "$CFG_ST" clam '[
  {"name":"st-one","source":"./plugins/st-one","description":"d"},
  {"name":"st-many","source":"./plugins/st-many","description":"d"},
  {"name":"st-mixed","source":"./plugins/st-mixed","description":"d"},
  {"name":"st-current","source":"./plugins/st-current","description":"d"},
  {"name":"st-unstamped","source":"./plugins/st-unstamped","description":"d"},
  {"name":"st-uninstalled","source":"./plugins/st-uninstalled","description":"d"},
  {"name":"st-newer","source":"./plugins/st-newer","description":"d"}
]'
clone_source_plugin "$CFG_ST" clam ./plugins/st-one         1.0.0 st-one
clone_source_plugin "$CFG_ST" clam ./plugins/st-many        2.0.0 st-many
clone_source_plugin "$CFG_ST" clam ./plugins/st-mixed       3.0.0 st-mixed
clone_source_plugin "$CFG_ST" clam ./plugins/st-current     1.0.0 st-current
clone_source_plugin "$CFG_ST" clam ./plugins/st-unstamped   1.0.0 st-unstamped
clone_source_plugin "$CFG_ST" clam ./plugins/st-uninstalled 1.0.0 st-uninstalled
clone_source_plugin "$CFG_ST" clam ./plugins/st-newer       1.0.0 st-newer

mkplugin_json "$CFG_ST/plugins/cache/clam/st-one/1.0.0"       1.0.0 st-one
mkplugin_json "$CFG_ST/plugins/cache/clam/st-many/2.0.0"      2.0.0 st-many
mkplugin_json "$CFG_ST/plugins/cache/clam/st-mixed/3.0.0"     3.0.0 st-mixed
mkplugin_json "$CFG_ST/plugins/cache/clam/st-current/1.0.0"   1.0.0 st-current
mkplugin_json "$CFG_ST/plugins/cache/clam/st-unstamped/1.0.0" 1.0.0 st-unstamped
mkplugin_json "$CFG_ST/plugins/cache/clam/st-newer/1.0.0"     1.0.0 st-newer
# st-uninstalled: deliberately no installation entry (and so no cache dir).

write_installed "$CFG_ST" "{
  \"st-one@clam\":       [$(inst_entry "$CFG_ST/plugins/cache/clam/st-one/1.0.0" 1.0.0)],
  \"st-many@clam\":      [$(inst_entry "$CFG_ST/plugins/cache/clam/st-many/2.0.0" 2.0.0)],
  \"st-mixed@clam\":     [$(inst_entry "$CFG_ST/plugins/cache/clam/st-mixed/3.0.0" 3.0.0)],
  \"st-current@clam\":   [$(inst_entry "$CFG_ST/plugins/cache/clam/st-current/1.0.0" 1.0.0)],
  \"st-unstamped@clam\": [$(inst_entry "$CFG_ST/plugins/cache/clam/st-unstamped/1.0.0" 1.0.0)],
  \"st-newer@clam\":     [$(inst_entry "$CFG_ST/plugins/cache/clam/st-newer/1.0.0" 1.0.0)]
}"

# Record order below IS the contract for stale_targets; do not tidy it into
# version or path order. st-mixed's matching and differing stamps are
# interleaved on purpose.
write_stamps "$CFG_ST" '{
  "version": 1,
  "stamps": [
    {"plugin":"st-one","version":"0.9.0","scope":"user","target":"/opt/one/only","at":"2026-01-01T00:00:00Z"},
    {"plugin":"st-many","version":"1.10.0","scope":"user","target":"/opt/many/zulu","at":"2026-01-01T00:00:00Z"},
    {"plugin":"st-many","version":"1.9.0","scope":"project","target":"/opt/many/alpha","at":"2026-01-02T00:00:00Z"},
    {"plugin":"st-many","version":"1.11.0","scope":"local","target":"/opt/many/mike","at":"2026-01-03T00:00:00Z"},
    {"plugin":"st-mixed","version":"3.0.0","scope":"user","target":"/opt/mixed/match-first","at":"2026-01-01T00:00:00Z"},
    {"plugin":"st-mixed","version":"2.9.0","scope":"project","target":"/opt/mixed/stale-a","at":"2026-01-02T00:00:00Z"},
    {"plugin":"st-mixed","version":"3.0.0","scope":"local","target":"/opt/mixed/match-second","at":"2026-01-03T00:00:00Z"},
    {"plugin":"st-mixed","version":"2.10.0","scope":"user","target":"/opt/mixed/stale-b","at":"2026-01-04T00:00:00Z"},
    {"plugin":"st-current","version":"1.0.0","scope":"user","target":"/opt/current/a","at":"2026-01-01T00:00:00Z"},
    {"plugin":"st-current","version":"1.0.0","scope":"project","target":"/opt/current/b","at":"2026-01-02T00:00:00Z"},
    {"plugin":"st-uninstalled","version":"0.5.0","scope":"user","target":"/opt/gone/only","at":"2026-01-01T00:00:00Z"},
    {"plugin":"st-newer","version":"2.0.0","scope":"user","target":"/opt/newer/only","at":"2026-01-01T00:00:00Z"}
  ]
}'

ST_DIGEST_BEFORE=$(tree_digest "$CFG_ST")
run_check "$CFG_ST"

check "STALETARGETS: exit 0 (setup=stale rows never make the exit code 10; only update=stale does)" "$RC" "0"

check_row "STALETARGETS st-one (single differing stamp -> exactly that target)" \
  "$OUT" st-one 1.0.0 1.0.0 current 0.9.0 stale /opt/one/only
check_row "STALETARGETS st-many (all three targets ';'-joined in stamp-file record order; stamp=lowest 1.9.0 by sort -V)" \
  "$OUT" st-many 2.0.0 2.0.0 current 1.9.0 stale '/opt/many/zulu;/opt/many/alpha;/opt/many/mike'
check_row "STALETARGETS st-mixed (only the differing stamps' targets, in record order; stamp=lowest 2.9.0 across all stamps)" \
  "$OUT" st-mixed 3.0.0 3.0.0 current 2.9.0 stale '/opt/mixed/stale-a;/opt/mixed/stale-b'
check_row "STALETARGETS st-current (every stamp matches -> setup current, stale_targets '-' despite real targets)" \
  "$OUT" st-current 1.0.0 1.0.0 current 1.0.0 current "-"
check_row "STALETARGETS st-unstamped (no stamp of its own -> stamp '-', stale_targets '-')" \
  "$OUT" st-unstamped 1.0.0 1.0.0 current "-" unstamped "-"
check_row "STALETARGETS st-uninstalled (not installed but stamped -> setup '-', stale_targets '-', never empty)" \
  "$OUT" st-uninstalled "-" 1.0.0 not-installed 0.5.0 "-" "-"
check_row "STALETARGETS st-newer (stamp ABOVE installed still differs -> stale; comparison is inequality, not ordering)" \
  "$OUT" st-newer 1.0.0 1.0.0 current 2.0.0 stale /opt/newer/only

check "STALETARGETS: fixture tree byte-identical after run (stamp file never rewritten to compute stale_targets)" \
  "$(tree_digest "$CFG_ST")" "$ST_DIGEST_BEFORE"

echo ""
echo "=== Fixture EMPTY: empty catalog -> header only, exit 0 ==="

CFG_EMPTY="$TMPROOT/cfg-empty"
init_marketplace "$CFG_EMPTY" clam '[]'
write_installed "$CFG_EMPTY" '{}'

run_check "$CFG_EMPTY"
check "EMPTY: exit 0" "$RC" "0"
check "EMPTY: output is exactly the header line, no rows" "$OUT" "$HEADER"

echo ""
echo "=== Fixture NOSTAMP: absent stamp file -> unstamped/'-'; also exit 0 (no stale) ==="

CFG_NOSTAMP="$TMPROOT/cfg-nostamp"
init_marketplace "$CFG_NOSTAMP" clam '[
  {"name":"installed-no-stamp","source":"./plugins/installed-no-stamp","description":"d"},
  {"name":"not-installed-no-stamp","source":"./plugins/not-installed-no-stamp","description":"d"}
]'
clone_source_plugin "$CFG_NOSTAMP" clam ./plugins/installed-no-stamp     1.0.0 installed-no-stamp
clone_source_plugin "$CFG_NOSTAMP" clam ./plugins/not-installed-no-stamp 1.0.0 not-installed-no-stamp
mkplugin_json "$CFG_NOSTAMP/plugins/cache/clam/installed-no-stamp/1.0.0" 1.0.0 installed-no-stamp
write_installed "$CFG_NOSTAMP" "{
  \"installed-no-stamp@clam\": [$(inst_entry "$CFG_NOSTAMP/plugins/cache/clam/installed-no-stamp/1.0.0" 1.0.0)]
}"
# Deliberately no clam-setup-stamps.json file at all.

run_check "$CFG_NOSTAMP"
check "NOSTAMP: exit 0 (no stale rows)" "$RC" "0"
check_row "NOSTAMP installed-no-stamp (installed, no stamp file -> unstamped)" \
  "$OUT" installed-no-stamp 1.0.0 1.0.0 current "-" unstamped "-"
check_row "NOSTAMP not-installed-no-stamp (not installed, no stamp file -> '-')" \
  "$OUT" not-installed-no-stamp "-" 1.0.0 not-installed "-" "-" "-"

echo ""
echo "=== Fixture EMPTYSTAMPS: present stamp file with an EMPTY stamps array -> same as no stamp file ==="
# The contract pairs these two in one edge case ("Empty stamps array / absent
# stamp file: setup = unstamped or '-'"), so the well-formed-but-empty file
# must land exactly where NOSTAMP's absent file does, stale_targets included.

CFG_EMPTYSTAMPS="$TMPROOT/cfg-emptystamps"
init_marketplace "$CFG_EMPTYSTAMPS" clam '[
  {"name":"es-installed","source":"./plugins/es-installed","description":"d"},
  {"name":"es-absent","source":"./plugins/es-absent","description":"d"}
]'
clone_source_plugin "$CFG_EMPTYSTAMPS" clam ./plugins/es-installed 1.0.0 es-installed
clone_source_plugin "$CFG_EMPTYSTAMPS" clam ./plugins/es-absent    1.0.0 es-absent
mkplugin_json "$CFG_EMPTYSTAMPS/plugins/cache/clam/es-installed/1.0.0" 1.0.0 es-installed
write_installed "$CFG_EMPTYSTAMPS" "{
  \"es-installed@clam\": [$(inst_entry "$CFG_EMPTYSTAMPS/plugins/cache/clam/es-installed/1.0.0" 1.0.0)]
}"
write_stamps "$CFG_EMPTYSTAMPS" '{"version":1,"stamps":[]}'

run_check "$CFG_EMPTYSTAMPS"
check "EMPTYSTAMPS: exit 0" "$RC" "0"
check_true "EMPTYSTAMPS: an empty stamps array is well-formed, so no warning on stderr" \
  "$([[ -z "$ERR" ]] && echo yes || echo no)"
check_row "EMPTYSTAMPS es-installed (empty stamps array -> unstamped, stamp '-', stale_targets '-')" \
  "$OUT" es-installed 1.0.0 1.0.0 current "-" unstamped "-"
check_row "EMPTYSTAMPS es-absent (not installed, empty stamps array -> all dashes)" \
  "$OUT" es-absent "-" 1.0.0 not-installed "-" "-" "-"

echo ""
echo "=== Fixture BADSTAMP: malformed stamp file -> stderr warning, zero stamps, NOT an error exit ==="

CFG_BADSTAMP="$TMPROOT/cfg-badstamp"
init_marketplace "$CFG_BADSTAMP" clam '[{"name":"warn-plugin","source":"./plugins/warn-plugin","description":"d"}]'
clone_source_plugin "$CFG_BADSTAMP" clam ./plugins/warn-plugin 1.0.0 warn-plugin
mkplugin_json "$CFG_BADSTAMP/plugins/cache/clam/warn-plugin/1.0.0" 1.0.0 warn-plugin
write_installed "$CFG_BADSTAMP" "{
  \"warn-plugin@clam\": [$(inst_entry "$CFG_BADSTAMP/plugins/cache/clam/warn-plugin/1.0.0" 1.0.0)]
}"
write_stamps "$CFG_BADSTAMP" '{ this is not valid json !!'
BADSTAMP_DIGEST_BEFORE=$(md5sum "$CFG_BADSTAMP/clam-setup-stamps.json")

run_check "$CFG_BADSTAMP"
check "BADSTAMP: exit 0, not an error exit (2/3/4 reserved for other failures)" "$RC" "0"
check_true "BADSTAMP: stderr carries a warning (non-empty)" "$([[ -n "$ERR" ]] && echo yes || echo no)"
check_true "BADSTAMP: stderr warning mentions the stamp file" "$(grep -qi 'stamp' <<<"$ERR" && echo yes || echo no)"
check_row "BADSTAMP warn-plugin (malformed stamps treated as zero stamps -> unstamped, no stale targets)" \
  "$OUT" warn-plugin 1.0.0 1.0.0 current "-" unstamped "-"
check "BADSTAMP: corrupt stamp file left byte-identical (never moved aside by this read-only script)" \
  "$(md5sum "$CFG_BADSTAMP/clam-setup-stamps.json")" "$BADSTAMP_DIGEST_BEFORE"

echo ""
echo "=== Fixture SCOPE: installs under a DIFFERENT marketplace key are out of scope ==="

CFG_SCOPE="$TMPROOT/cfg-scope"
init_marketplace "$CFG_SCOPE" clam '[{"name":"shared-name","source":"./plugins/shared-name","description":"d"}]'
clone_source_plugin "$CFG_SCOPE" clam ./plugins/shared-name 1.0.0 shared-name
mkplugin_json "$CFG_SCOPE/plugins/cache/othermarketplace/shared-name/1.0.0" 1.0.0 shared-name
# Installed only as "shared-name@othermarketplace", never "shared-name@clam".
write_installed "$CFG_SCOPE" "{
  \"shared-name@othermarketplace\": [$(inst_entry "$CFG_SCOPE/plugins/cache/othermarketplace/shared-name/1.0.0" 1.0.0)]
}"

run_check "$CFG_SCOPE"
check_row "SCOPE shared-name (installed under a different marketplace key -> not installed for clam)" \
  "$OUT" shared-name "-" 1.0.0 not-installed "-" "-" "-"

echo ""
echo "=== Fixture MKT: CLAM_MARKETPLACE override, and its default value ('clam') ==="

CFG_MKT="$TMPROOT/cfg-mkt"
init_marketplace "$CFG_MKT" customhub '[{"name":"cust1","source":"./plugins/cust1","description":"d"}]'
clone_source_plugin "$CFG_MKT" customhub ./plugins/cust1 1.0.0 cust1
mkplugin_json "$CFG_MKT/plugins/cache/customhub/cust1/1.0.0" 1.0.0 cust1
write_installed "$CFG_MKT" "{
  \"cust1@customhub\": [$(inst_entry "$CFG_MKT/plugins/cache/customhub/cust1/1.0.0" 1.0.0)]
}"
# Deliberately no plugins/marketplaces/clam/ in this fixture, so the DEFAULT
# marketplace name must fail with "clone missing" while the override succeeds.

run_check "$CFG_MKT" customhub
check "MKT: CLAM_MARKETPLACE=customhub succeeds (exit 0)" "$RC" "0"
check_row "MKT cust1 (read via CLAM_MARKETPLACE override)" "$OUT" cust1 1.0.0 1.0.0 current "-" unstamped "-"

run_check "$CFG_MKT"
check "MKT: default marketplace name is 'clam' (no override -> clone missing here -> exit 3)" "$RC" "3"

echo ""
echo "=== Fixture NOINSTALLED / BADINSTALLED: exit 2 (missing/malformed installed_plugins.json) ==="

CFG_NOINSTALLED="$TMPROOT/cfg-noinstalled"
init_marketplace "$CFG_NOINSTALLED" clam '[{"name":"p","source":"./plugins/p","description":"d"}]'
clone_source_plugin "$CFG_NOINSTALLED" clam ./plugins/p 1.0.0 p
# Deliberately no plugins/installed_plugins.json at all.

run_check "$CFG_NOINSTALLED"
check "NOINSTALLED: missing installed_plugins.json -> exit 2" "$RC" "2"
check_true "NOINSTALLED: stderr message present" "$([[ -n "$ERR" ]] && echo yes || echo no)"

CFG_BADINSTALLED="$TMPROOT/cfg-badinstalled"
init_marketplace "$CFG_BADINSTALLED" clam '[{"name":"p","source":"./plugins/p","description":"d"}]'
clone_source_plugin "$CFG_BADINSTALLED" clam ./plugins/p 1.0.0 p
mkdir -p "$CFG_BADINSTALLED/plugins"
printf '{ this is not valid json' > "$CFG_BADINSTALLED/plugins/installed_plugins.json"

run_check "$CFG_BADINSTALLED"
check "BADINSTALLED: malformed installed_plugins.json -> exit 2" "$RC" "2"
check_true "BADINSTALLED: stderr message present" "$([[ -n "$ERR" ]] && echo yes || echo no)"

echo ""
echo "=== Fixture NOMKT / NOMKTJSON: exit 3 (missing marketplace clone) ==="

CFG_NOMKT="$TMPROOT/cfg-nomkt"
write_installed "$CFG_NOMKT" '{}'
# Deliberately no plugins/marketplaces/clam/ directory at all.

run_check "$CFG_NOMKT"
check "NOMKT: marketplace clone dir absent -> exit 3" "$RC" "3"
check_true "NOMKT: stderr suggests the refresh command" \
  "$(grep -qF -- '/plugin marketplace update' <<<"$ERR" && echo yes || echo no)"
check_true "NOMKT: stderr names the marketplace ('clam')" \
  "$(grep -qF -- 'clam' <<<"$ERR" && echo yes || echo no)"

CFG_NOMKTJSON="$TMPROOT/cfg-nomktjson"
write_installed "$CFG_NOMKTJSON" '{}'
mkdir -p "$CFG_NOMKTJSON/plugins/marketplaces/clam"  # clone dir exists, but no .claude-plugin/marketplace.json

run_check "$CFG_NOMKTJSON"
check "NOMKTJSON: marketplace.json absent from an existing clone dir -> exit 3" "$RC" "3"
check_true "NOMKTJSON: stderr suggests the refresh command" \
  "$(grep -qF -- '/plugin marketplace update' <<<"$ERR" && echo yes || echo no)"

echo ""
echo "=== Fixture NOJQ: exit 4 (jq not available) ==="

# Reuse NOSTAMP's fully-valid fixture; only the SUT's PATH is restricted.
run_check_nojq "$CFG_NOSTAMP"
check "NOJQ: jq absent from PATH -> exit 4" "$RC" "4"
check_true "NOJQ: stderr message present" "$([[ -n "$ERR" ]] && echo yes || echo no)"

echo ""
echo "=== Fixture HOMEDEFAULT: CLAUDE_CONFIG_DIR defaults to \$HOME/.claude ==="

HOME_DEFAULT="$TMPROOT/home-default"
mkdir -p "$HOME_DEFAULT/.claude"
init_marketplace "$HOME_DEFAULT/.claude" clam '[{"name":"defp","source":"./plugins/defp","description":"d"}]'
clone_source_plugin "$HOME_DEFAULT/.claude" clam ./plugins/defp 1.0.0 defp
mkplugin_json "$HOME_DEFAULT/.claude/plugins/cache/clam/defp/1.0.0" 1.0.0 defp
write_installed "$HOME_DEFAULT/.claude" "{
  \"defp@clam\": [$(inst_entry "$HOME_DEFAULT/.claude/plugins/cache/clam/defp/1.0.0" 1.0.0)]
}"

run_check_home "$HOME_DEFAULT"
check "HOMEDEFAULT: CLAUDE_CONFIG_DIR unset -> reads \$HOME/.claude, exit 0" "$RC" "0"
check_row "HOMEDEFAULT defp (found via default config dir)" "$OUT" defp 1.0.0 1.0.0 current "-" unstamped "-"

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit $FAILED
