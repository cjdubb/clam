#!/usr/bin/env bash
# Black-box CLI tests for B09 debug-session-script
# (plugins/debugging/scripts/debug-session.sh). Source of truth: the header
# comment contract at the top of that script.
#
# Covers, per the contract: both subcommands' happy paths (created tree,
# verbatim template copies, stdout = exactly the created path, exit 0);
# numbering rules (001/01 start, max+1 regardless of slug/name, zero-padding,
# gaps never filled, non-dir and non-matching entries ignored, overflow at
# 999/99 is an error); slug/name/ext input validation; every enumerated error
# case (exactly ONE "ERROR: " line on stderr, exit 1, nothing on stdout, no
# partial artifacts); the never-overwrites/writes-only-within invariants;
# script-relative (not CWD-relative) template resolution; and quote-safety
# with spaces in CWD paths.
#
# Every invocation goes through the script's public CLI only (stdin/argv in,
# stdout/stderr/exit-code/filesystem out) — nothing here inspects internals.
#
# Hermetic: every case runs against a fresh mktemp -d fixture tree; nothing
# under the real repo is read except the script itself and (for the
# verbatim-copy assertions) the plugin's own templates/*.md, both accessed
# read-only. Cleaned up via an EXIT trap.
#
# Run: bash plugins/debugging/scripts/b09-debug-session.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/debug-session.sh"
JOURNAL_TPL="$SCRIPT_DIR/../templates/journal.md"
QUERY_TPL="$SCRIPT_DIR/../templates/query-results.md"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT
ERRFILE="$TMPROOT/.stderr.log"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Runs the script from cwd $1 with args "${@:2}". Sets globals OUT/ERR/RC.
run_in() { # dir args...
  local dir="$1"; shift
  OUT="$(cd "$dir" && bash "$SCRIPT" "$@" 2>"$ERRFILE")"
  RC=$?
  ERR="$(cat "$ERRFILE")"
}

# Asserts the shape every error case must have: exit 1, empty stdout, and
# stderr that is exactly one line starting with "ERROR: ".
assert_error_shape() { # label
  local label="$1"
  check "$label: exit code is 1" "$RC" "1"
  check "$label: stdout is empty" "$OUT" ""
  check "$label: stderr is non-empty" "$([[ -n "$ERR" ]] && echo yes || echo no)" "yes"
  check "$label: stderr is exactly one line" "$([[ "$ERR" != *$'\n'* ]] && echo yes || echo no)" "yes"
  check "$label: stderr line starts with 'ERROR: '" "$([[ "$ERR" == "ERROR: "* ]] && echo yes || echo no)" "yes"
}

snapshot() { find "$1" 2>/dev/null | sort; } # $1: root dir

# "yes" if glob pattern $1 matches at least one existing path, "no" otherwise.
# (Bare `[[ -d some/glob-* ]]` does NOT expand the glob — the operand of a
# unary test inside [[ ]] is compared literally — so this uses compgen -G,
# which does perform pathname expansion, to test for a real match.)
glob_matches() { # pattern
  local matches
  matches="$(compgen -G "$1" 2>/dev/null)"
  [[ -n "$matches" ]] && echo yes || echo no
}

assert_tree_unchanged() { # label root before_snapshot
  local label="$1" root="$2" before="$3"
  local after; after="$(snapshot "$root")"
  check "$label: no partial artifacts (filesystem tree unchanged)" \
    "$([[ "$after" == "$before" ]] && echo yes || echo no)" "yes"
}

# Asserts that the only paths that newly exist under $2 (compared to
# snapshot $3) are exactly the newline-separated set $4 (order-independent).
assert_new_entries_exactly() { # label root before_snapshot expected_newline_list
  local label="$1" root="$2" before="$3" expected="$4"
  local after new expected_sorted
  after="$(snapshot "$root")"
  new="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
  expected_sorted="$(printf '%s\n' "$expected" | sort)"
  check "$label: new filesystem entries are exactly the contracted set" "$new" "$expected_sorted"
}

# ===========================================================================
# 1. start: happy path — created tree, verbatim journal.md, empty queries/,
#    stdout is exactly the created path, exit 0
# ===========================================================================

W1="$TMPROOT/w1"; mkdir -p "$W1/.local"
before1="$(snapshot "$W1")"
run_in "$W1" start my-first-slug
check "start happy path: exit code is 0" "$RC" "0"
check "start happy path: stdout is exactly the created path" "$OUT" ".local/debug/001-my-first-slug"
check "start happy path: stderr is empty" "$ERR" ""
check "start happy path: session dir was created" \
  "$([[ -d "$W1/.local/debug/001-my-first-slug" ]] && echo yes || echo no)" "yes"
check "start happy path: journal.md is a byte-for-byte copy of templates/journal.md" \
  "$(cmp -s "$W1/.local/debug/001-my-first-slug/journal.md" "$JOURNAL_TPL" && echo yes || echo no)" "yes"
check "start happy path: queries/ subdir was created" \
  "$([[ -d "$W1/.local/debug/001-my-first-slug/queries" ]] && echo yes || echo no)" "yes"
check "start happy path: queries/ subdir is empty" \
  "$([[ -z "$(ls -A "$W1/.local/debug/001-my-first-slug/queries" 2>/dev/null)" ]] && echo yes || echo no)" "yes"
assert_new_entries_exactly "start happy path" "$W1" "$before1" "$(printf '%s\n' \
  "$W1/.local/debug" \
  "$W1/.local/debug/001-my-first-slug" \
  "$W1/.local/debug/001-my-first-slug/journal.md" \
  "$W1/.local/debug/001-my-first-slug/queries")"

# ===========================================================================
# 2. query: happy path — created tree, verbatim results.md, empty query
#    file with default ext, stdout exactly the created path, exit 0
# ===========================================================================

W2="$TMPROOT/w2"; mkdir -p "$W2/.local"
SESS2="$W2/manual-session"; mkdir -p "$SESS2"; : > "$SESS2/journal.md"
before2="$(snapshot "$W2")"
run_in "$W2" query "$SESS2" first-query
check "query happy path: exit code is 0" "$RC" "0"
check "query happy path: stdout is exactly the created path" "$OUT" "$SESS2/queries/01-first-query"
check "query happy path: stderr is empty" "$ERR" ""
check "query happy path: default ext is txt (query.txt created, empty)" \
  "$([[ -f "$SESS2/queries/01-first-query/query.txt" && ! -s "$SESS2/queries/01-first-query/query.txt" ]] && echo yes || echo no)" "yes"
check "query happy path: results.md is a byte-for-byte copy of templates/query-results.md" \
  "$(cmp -s "$SESS2/queries/01-first-query/results.md" "$QUERY_TPL" && echo yes || echo no)" "yes"
assert_new_entries_exactly "query happy path" "$W2" "$before2" "$(printf '%s\n' \
  "$SESS2/queries" \
  "$SESS2/queries/01-first-query" \
  "$SESS2/queries/01-first-query/query.txt" \
  "$SESS2/queries/01-first-query/results.md")"

# --- query: explicit ext is honored ----------------------------------------
run_in "$W2" query "$SESS2" sql-query sql
check "query with explicit ext: exit code is 0" "$RC" "0"
check "query with explicit ext: stdout path uses next number" "$OUT" "$SESS2/queries/02-sql-query"
check "query with explicit ext: query.sql created (empty)" \
  "$([[ -f "$SESS2/queries/02-sql-query/query.sql" && ! -s "$SESS2/queries/02-sql-query/query.sql" ]] && echo yes || echo no)" "yes"
check "query with explicit ext: no query.txt created for this call" \
  "$([[ ! -e "$SESS2/queries/02-sql-query/query.txt" ]] && echo yes || echo no)" "yes"

# ===========================================================================
# 3. start: numbering — max+1 regardless of slug, gaps never filled, a file
#    entry ignored, a non-3-digit entry ignored, a non-matching name ignored
# ===========================================================================

W3="$TMPROOT/w3"; mkdir -p "$W3/.local/debug"
mkdir -p "$W3/.local/debug/001-alpha"
mkdir -p "$W3/.local/debug/004-beta"        # gap at 002/003
: > "$W3/.local/debug/010-fileentry"        # file, not dir: must be ignored
mkdir -p "$W3/.local/debug/misc"            # non-matching name: ignored
mkdir -p "$W3/.local/debug/12-shortnum"     # only 2 digits, not NNN: ignored
before3="$(snapshot "$W3")"
run_in "$W3" start gamma
check "numbering: next is max(matching dirs)+1 regardless of slug, ignoring file/non-matching entries" \
  "$OUT" ".local/debug/005-gamma"
check "numbering: exit code is 0" "$RC" "0"
check "numbering: gap at 002 is not filled" "$([[ -e "$W3/.local/debug/002" || -e "$W3/.local/debug/002-gamma" ]] && echo present || echo absent)" "absent"
check "numbering: gap at 003 is not filled" "$(glob_matches "$W3/.local/debug/003-*")" "no"
assert_new_entries_exactly "numbering" "$W3" "$before3" "$(printf '%s\n' \
  "$W3/.local/debug/005-gamma" \
  "$W3/.local/debug/005-gamma/journal.md" \
  "$W3/.local/debug/005-gamma/queries")"

# --- start: zero-padding across the 9 -> 10 boundary ------------------------
W4="$TMPROOT/w4"; mkdir -p "$W4/.local/debug"
for n in 001 002 003 004 005 006 007 008 009; do mkdir -p "$W4/.local/debug/$n-existing"; done
run_in "$W4" start ten
check "numbering: zero-padding at the 9->10 boundary yields 010" "$OUT" ".local/debug/010-ten"

# --- start: overflow past 999 is an error, not a wraparound -----------------
W5="$TMPROOT/w5"; mkdir -p "$W5/.local/debug/999-last"
before5="$(snapshot "$W5")"
run_in "$W5" start overflow
assert_error_shape "start numbering overflow past 999"
assert_tree_unchanged "start numbering overflow past 999" "$W5" "$before5"

# ===========================================================================
# 4. query: numbering — same rules over <session-dir>/queries/
# ===========================================================================

W6="$TMPROOT/w6"; mkdir -p "$W6/.local"
SESS6="$W6/sess"; mkdir -p "$SESS6"; : > "$SESS6/journal.md"
mkdir -p "$SESS6/queries/01-a"
mkdir -p "$SESS6/queries/03-b"          # gap at 02
: > "$SESS6/queries/05-fileentry"       # file: ignored
mkdir -p "$SESS6/queries/misc"          # non-matching name: ignored
mkdir -p "$SESS6/queries/9-shortnum"    # only 1 digit, not NN: ignored
before6="$(snapshot "$W6")"
run_in "$W6" query "$SESS6" newname
check "query numbering: next is max(matching dirs)+1, ignoring file/non-matching entries" \
  "$OUT" "$SESS6/queries/04-newname"
check "query numbering: gap at 02 is not filled" "$(glob_matches "$SESS6/queries/02-*")" "no"
assert_new_entries_exactly "query numbering" "$W6" "$before6" "$(printf '%s\n' \
  "$SESS6/queries/04-newname" \
  "$SESS6/queries/04-newname/query.txt" \
  "$SESS6/queries/04-newname/results.md")"

# --- query: zero-padding across the 9 -> 10 boundary ------------------------
W7="$TMPROOT/w7"; mkdir -p "$W7/.local"
SESS7="$W7/sess"; mkdir -p "$SESS7"; : > "$SESS7/journal.md"
for n in 01 02 03 04 05 06 07 08 09; do mkdir -p "$SESS7/queries/$n-existing"; done
run_in "$W7" query "$SESS7" ten
check "query numbering: zero-padding at the 9->10 boundary yields 10" "$OUT" "$SESS7/queries/10-ten"

# --- query: overflow past 99 is an error, not a wraparound ------------------
W8="$TMPROOT/w8"; mkdir -p "$W8/.local"
SESS8="$W8/sess"; mkdir -p "$SESS8"; : > "$SESS8/journal.md"
mkdir -p "$SESS8/queries/99-last"
before8="$(snapshot "$W8")"
run_in "$W8" query "$SESS8" overflow
assert_error_shape "query numbering overflow past 99"
assert_tree_unchanged "query numbering overflow past 99" "$W8" "$before8"

# ===========================================================================
# 5. never-overwrites invariant: an unrelated sibling's content is untouched
# ===========================================================================

W9="$TMPROOT/w9"; mkdir -p "$W9/.local/debug/001-existing"
printf 'SENTINEL-DO-NOT-TOUCH\n' > "$W9/.local/debug/001-existing/journal.md"
mkdir -p "$W9/.local/debug/001-existing/queries"
: > "$W9/.local/debug/001-existing/queries/01-old-query.marker"
run_in "$W9" start second
check "never-overwrites: sibling session's journal.md content is untouched" \
  "$(cat "$W9/.local/debug/001-existing/journal.md")" "SENTINEL-DO-NOT-TOUCH"
check "never-overwrites: sibling session's queries/ contents are untouched" \
  "$([[ -e "$W9/.local/debug/001-existing/queries/01-old-query.marker" ]] && echo yes || echo no)" "yes"

# ===========================================================================
# 6. errors: missing/unknown subcommand, wrong arg count (isolated from any
#    other failure cause by running in a valid, pre-existing .local/)
# ===========================================================================

WE="$TMPROOT/we"; mkdir -p "$WE/.local"
before_we="$(snapshot "$WE")"

run_in "$WE" ""            ; assert_error_shape "empty-string subcommand"
run_in "$WE"               ; assert_error_shape "no subcommand at all"
run_in "$WE" bogus-command ; assert_error_shape "unknown subcommand"
run_in "$WE" bogus-command arg1 arg2 ; assert_error_shape "unknown subcommand with extra args"

run_in "$WE" start                  ; assert_error_shape "start with no slug (too few args)"
run_in "$WE" start a b              ; assert_error_shape "start with an extra arg (too many args)"

run_in "$WE" query                  ; assert_error_shape "query with no args (too few args)"
run_in "$WE" query some-dir         ; assert_error_shape "query with only session-dir (too few args)"
run_in "$WE" query some-dir name sql extra ; assert_error_shape "query with an extra arg (too many args)"

assert_tree_unchanged "arg-count/subcommand error group" "$WE" "$before_we"

# ===========================================================================
# 7. errors: invalid slug / name / ext (isolated in a valid environment)
# ===========================================================================

WV="$TMPROOT/wv"; mkdir -p "$WV/.local"
SESSV="$WV/sess"; mkdir -p "$SESSV"; : > "$SESSV/journal.md"
before_wv="$(snapshot "$WV")"

for bad_slug in "UpperCase" "with_underscore" "-leading-hyphen" "with space" "dot.slug" "../traversal" ""; do
  run_in "$WV" start "$bad_slug"
  assert_error_shape "start with invalid slug '$bad_slug'"
done

for bad_name in "UpperCase" "with_underscore" "-leading-hyphen" "with space" "dot.name" ""; do
  run_in "$WV" query "$SESSV" "$bad_name"
  assert_error_shape "query with invalid name '$bad_name'"
done

for bad_ext in "TXT" "s q l" "sql!" "dot.ext" ""; do
  run_in "$WV" query "$SESSV" validname "$bad_ext"
  assert_error_shape "query with invalid ext '$bad_ext'"
done

# --- valid single-character slug/name (edge of the pattern) is accepted ----
run_in "$WV" start a
check "start with single-char slug 'a' is accepted" "$RC" "0"
run_in "$WV" query "$SESSV" q
check "query with single-char name 'q' is accepted" "$RC" "0"

# Recount precisely: exactly one new start-session dir (for slug "a") and
# exactly one new query dir (for name "q") should exist, nothing else.
check "invalid-input group: exactly one session dir exists under .local/debug/ (from the single valid 'start a' call)" \
  "$(find "$WV/.local/debug" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" "1"
check "invalid-input group: exactly one query dir exists under the session's queries/ (from the single valid 'query q' call)" \
  "$(find "$SESSV/queries" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" "1"

# ===========================================================================
# 8. errors: start when ./.local does not exist (CWD-relative only, no
#    upward search)
# ===========================================================================

WN="$TMPROOT/wn"; mkdir -p "$WN" # deliberately no .local/ here
before_wn="$(snapshot "$WN")"
run_in "$WN" start no-local-here
assert_error_shape "start when ./.local does not exist"
assert_tree_unchanged "start when ./.local does not exist" "$WN" "$before_wn"

# .local exists in the parent but NOT in the CWD itself: still an error,
# proving resolution is strictly CWD-relative, not an upward search.
WP="$TMPROOT/wp"; mkdir -p "$WP/.local"
WPSUB="$WP/subdir"; mkdir -p "$WPSUB"
before_wpsub="$(snapshot "$WPSUB")"
run_in "$WPSUB" start no-upward-search
assert_error_shape "start from a subdir whose CWD lacks ./.local (parent having one doesn't count)"
assert_tree_unchanged "start from a subdir whose CWD lacks ./.local" "$WPSUB" "$before_wpsub"

# ===========================================================================
# 9. errors: query when <session-dir> does not exist, or exists but lacks
#    journal.md
# ===========================================================================

WQ="$TMPROOT/wq"; mkdir -p "$WQ/.local"
before_wq="$(snapshot "$WQ")"
run_in "$WQ" query "$WQ/does-not-exist" somename
assert_error_shape "query when session-dir does not exist"
assert_tree_unchanged "query when session-dir does not exist" "$WQ" "$before_wq"

NOJOURNAL="$WQ/no-journal-here"; mkdir -p "$NOJOURNAL"
before_nj="$(snapshot "$WQ")"
run_in "$WQ" query "$NOJOURNAL" somename
assert_error_shape "query when session-dir exists but lacks journal.md"
assert_tree_unchanged "query when session-dir exists but lacks journal.md" "$WQ" "$before_nj"

# ===========================================================================
# 10. errors: template file missing at the script-relative location.
#     Tested by running a COPY of the real script relocated next to a
#     deliberately incomplete templates/ sibling — the real repo templates
#     are never touched.
# ===========================================================================

FAKE_START="$TMPROOT/fake-missing-journal-tpl"
mkdir -p "$FAKE_START/scripts" "$FAKE_START/templates"
cp "$SCRIPT" "$FAKE_START/scripts/debug-session.sh"
cp "$QUERY_TPL" "$FAKE_START/templates/query-results.md"   # journal.md deliberately absent
WFS="$TMPROOT/wfs"; mkdir -p "$WFS/.local"
before_wfs="$(snapshot "$WFS")"
OUT="$(cd "$WFS" && bash "$FAKE_START/scripts/debug-session.sh" start missing-tpl 2>"$ERRFILE")"
RC=$?
ERR="$(cat "$ERRFILE")"
assert_error_shape "start when journal.md template is missing at the script-relative location"
assert_tree_unchanged "start when journal.md template is missing at the script-relative location" "$WFS" "$before_wfs"

FAKE_QUERY="$TMPROOT/fake-missing-query-tpl"
mkdir -p "$FAKE_QUERY/scripts" "$FAKE_QUERY/templates"
cp "$SCRIPT" "$FAKE_QUERY/scripts/debug-session.sh"
cp "$JOURNAL_TPL" "$FAKE_QUERY/templates/journal.md"       # query-results.md deliberately absent
WFQ="$TMPROOT/wfq"; mkdir -p "$WFQ/.local"
SESSFQ="$WFQ/sess"; mkdir -p "$SESSFQ"; : > "$SESSFQ/journal.md"
before_wfq="$(snapshot "$WFQ")"
OUT="$(cd "$WFQ" && bash "$FAKE_QUERY/scripts/debug-session.sh" query "$SESSFQ" missing-tpl 2>"$ERRFILE")"
RC=$?
ERR="$(cat "$ERRFILE")"
assert_error_shape "query when results.md template is missing at the script-relative location"
assert_tree_unchanged "query when results.md template is missing at the script-relative location" "$WFQ" "$before_wfq"

# ===========================================================================
# 11. template resolution is relative to the SCRIPT's own location, never
#     the CWD — a decoy templates/ directory sitting in the CWD must be
#     ignored in favor of the real plugin templates.
# ===========================================================================

WD="$TMPROOT/wd"; mkdir -p "$WD/.local" "$WD/templates"
printf 'DECOY JOURNAL - SHOULD NEVER BE COPIED\n' > "$WD/templates/journal.md"
printf 'DECOY QUERY RESULTS - SHOULD NEVER BE COPIED\n' > "$WD/templates/query-results.md"
run_in "$WD" start decoy-test
check "CWD decoy templates/: start still succeeds" "$RC" "0"
check "CWD decoy templates/: journal.md copied matches the real plugin template, not the CWD decoy" \
  "$(cmp -s "$WD/.local/debug/001-decoy-test/journal.md" "$JOURNAL_TPL" && echo yes || echo no)" "yes"
check "CWD decoy templates/: journal.md copied is NOT the CWD decoy content" \
  "$(grep -q 'SHOULD NEVER BE COPIED' "$WD/.local/debug/001-decoy-test/journal.md" && echo decoy-leaked || echo clean)" "clean"

SESSD="$WD/sess"; mkdir -p "$SESSD"; : > "$SESSD/journal.md"
run_in "$WD" query "$SESSD" decoy-query
check "CWD decoy templates/: query still succeeds" "$RC" "0"
check "CWD decoy templates/: results.md copied matches the real plugin template, not the CWD decoy" \
  "$(cmp -s "$SESSD/queries/01-decoy-query/results.md" "$QUERY_TPL" && echo yes || echo no)" "yes"
check "CWD decoy templates/: results.md copied is NOT the CWD decoy content" \
  "$(grep -q 'SHOULD NEVER BE COPIED' "$SESSD/queries/01-decoy-query/results.md" && echo decoy-leaked || echo clean)" "clean"

# ===========================================================================
# 12. writes only within the contracted subtree: no network, no git.
#     PATH-shims git/curl/wget/nc/ssh (prepended, so real filesystem tools
#     still resolve) to prove neither happy path invokes them.
# ===========================================================================

SHIMBIN="$TMPROOT/shimbin"; mkdir -p "$SHIMBIN"
NETLOG="$TMPROOT/netlog"; : > "$NETLOG"
for cmd in git curl wget nc ssh; do
  cat > "$SHIMBIN/$cmd" <<EOF
#!/bin/bash
echo "$cmd \$*" >> "$NETLOG"
exit 1
EOF
  chmod +x "$SHIMBIN/$cmd"
done

WNET="$TMPROOT/wnet"; mkdir -p "$WNET/.local"
OUT="$(cd "$WNET" && PATH="$SHIMBIN:$PATH" bash "$SCRIPT" start net-check 2>"$ERRFILE")"
RC=$?
check "no-network/no-git: start succeeds even with git/curl/wget/nc/ssh shimmed to fail" "$RC" "0"
SESSNET="$WNET/.local/debug/001-net-check"
OUT="$(cd "$WNET" && PATH="$SHIMBIN:$PATH" bash "$SCRIPT" query "$SESSNET" q1 2>"$ERRFILE")"
RC=$?
check "no-network/no-git: query succeeds even with git/curl/wget/nc/ssh shimmed to fail" "$RC" "0"
check "no-network/no-git: neither call invoked git/curl/wget/nc/ssh" \
  "$([[ ! -s "$NETLOG" ]] && echo yes || echo no)" "yes"

# ===========================================================================
# 13. spaces in CWD paths are handled (quote-safe throughout)
# ===========================================================================

WS="$TMPROOT/dir with spaces"; mkdir -p "$WS/.local"
run_in "$WS" start space-slug
check "spaces in CWD: start exit code is 0" "$RC" "0"
check "spaces in CWD: stdout is exactly the created path" "$OUT" ".local/debug/001-space-slug"
check "spaces in CWD: journal.md created under the spaced path" \
  "$([[ -f "$WS/.local/debug/001-space-slug/journal.md" ]] && echo yes || echo no)" "yes"

SESSSPACE="$WS/session dir"; mkdir -p "$SESSSPACE"; : > "$SESSSPACE/journal.md"
run_in "$WS" query "session dir" spacedname
check "spaces in CWD: query exit code is 0" "$RC" "0"
check "spaces in CWD: stdout is exactly the created path (session-dir arg had an embedded space)" \
  "$OUT" "session dir/queries/01-spacedname"
check "spaces in CWD: query.txt created under the spaced session dir" \
  "$([[ -f "$SESSSPACE/queries/01-spacedname/query.txt" ]] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
