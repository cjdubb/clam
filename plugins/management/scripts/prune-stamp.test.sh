#!/bin/bash
# Functional test for prune-stamp.sh: targeted delete of exactly the ONE
# setup-stamp record matching (plugin, target) (Contract: B02 prune-stamp,
# docblock in prune-stamp.sh; companion format contract:
# plugins/management/docs/setup-stamps.md).
# Run: bash plugins/management/scripts/prune-stamp.test.sh
# (exits non-zero on failure)
#
# This script WRITES, so every fixture below is a self-contained fake config
# dir under $TMPROOT (removed on exit) driven through CLAUDE_CONFIG_DIR. No
# test ever reads or writes the real ~/.claude. Each fixture carries decoy
# files the script must never touch — plugins/installed_plugins.json,
# settings.json, a marketplace clone with marketplace.json and a cached
# plugin.json — so "the stamp file is the only file it writes" is checked
# against a tree, not an assertion of faith. Shapes match setup-stamps.md:
#   clam-setup-stamps.json (top level of the config dir)
#     {"version":1,"stamps":[{"plugin":...,"version":...,"scope":...,
#       "target":...,"at":...}]}
#
# The stub currently exits 70/"NotImplemented" for everything, so every
# behavioral assertion below is expected to fail red; the "fixture unchanged"
# assertions can incidentally pass against a no-op stub (a script that does
# nothing trivially writes nothing).
#
# Clause coverage map (contract clause -> fixture/case):
#   Behavior: delete the one (plugin,target) record                -> DELETE
#   Inputs $1 plugin: matched as stored, no "@clam" suffix         -> EXACT
#   Inputs $2 target: exact string equality, no normalization      -> EXACT
#   Inputs: both required, non-empty                               -> ARGS
#   Inputs: no other arguments accepted                            -> ARGS
#   Inputs: CLAUDE_CONFIG_DIR override                             -> all fixtures
#   Inputs: CLAUDE_CONFIG_DIR default ($HOME/.claude)              -> HOMEDEFAULT
#   Outputs: one-line confirmation naming plugin/target/version    -> DELETE
#   Outputs: one-line notice on a no-op                            -> NOMATCH
#   Outputs: nothing on stdout on any error path         -> ARGS, NOFILE, NOJQ,
#                                                           BADJSON, NOTARRAY,
#                                                           EMPTYFILE, WRITEFAIL
#   exit 2 wrong arg count / empty argument (usage on stderr)      -> ARGS
#   exit 3 stamp file absent (stderr names the path)               -> NOFILE
#   exit 4 jq not on PATH                                          -> NOJQ
#   exit 5 not valid JSON                                          -> BADJSON
#   exit 5 .stamps not an array                                    -> NOTARRAY
#   exit 5 corrupt file never repaired/moved aside/overwritten     -> BADJSON
#   exit 6 write failure, original intact, names the step          -> WRITEFAIL
#   Invariant: deletes at most one record; others survive          -> DELETE
#   Invariant: same plugin, different target survives              -> DELETE
#   Invariant: different plugin, same target survives              -> DELETE
#   Invariant: idempotent (second run exits 0, changes nothing)    -> IDEMPOTENT
#   Invariant: backup <file>.bak-<YYYY-MM-DD> holds pre-delete     -> DELETE
#   Invariant: atomic mv (inode replaced, not truncated in place)  -> DELETE
#   Invariant: top-level version and other top-level keys survive  -> DELETE
#   Invariant: stamp file is the only file written    -> DELETE, IDEMPOTENT,
#                                                        NOMATCH, BADJSON
#   Invariant: no network access                                   -> STATIC
#   Edge: no match -> exit 0, notice, NO backup at all              -> NOMATCH
#   Edge: duplicate (plugin,target) records -> all removed          -> DUP
#   Edge: empty .stamps array -> exit 0, no write                   -> EMPTYSTAMPS
#   Edge: trailing slash / relative path / unexpanded "~" no match  -> EXACT
#   Edge: 0-byte stamp file -> exit 5                               -> EMPTYFILE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/prune-stamp.sh"

TMPROOT=$(mktemp -d)
trap 'chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"' EXIT

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
check_ne() { # label got not-expected
  if [[ "$2" != "$3" ]]; then pass "$1"; else fail "$1 -> got '$2', expected anything else"; fi
}
yesno() { if [[ "$1" -eq 0 ]]; then echo yes; else echo no; fi; }

STAMP_BASENAME="clam-setup-stamps.json"
# Relative-path pattern for "the stamp file or its dated backup", used to
# exclude exactly those two — and nothing else, so a stray temp file still
# shows up — from tree digests.
STAMP_EXCL='/clam-setup-stamps\.json(\.bak-[0-9]{4}-[0-9]{2}-[0-9]{2})?$'
TODAY_LOCAL=$(date +%Y-%m-%d)
TODAY_UTC=$(date -u +%Y-%m-%d)

# The two targets used throughout: the SAME target appears under two
# different plugins, and the SAME plugin appears under two different targets,
# so the "deletes at most one record" invariant has something to violate.
T_USER="/home/u/.claude/settings.json"
T_PROJ="/repo/.claude/settings.json"

# --- Portability helpers -----------------------------------------------------

if command -v md5sum >/dev/null 2>&1; then
  hash_of() { [ -f "$1" ] || { echo "<absent>"; return 0; }; md5sum "$1" | cut -d' ' -f1; }
else
  hash_of() { [ -f "$1" ] || { echo "<absent>"; return 0; }; md5 -q "$1"; }
fi

inode_of() {
  [ -e "$1" ] || { echo "<absent>"; return 0; }
  stat -c %i "$1" 2>/dev/null || stat -f %i "$1" 2>/dev/null
}

# tree_digest <dir> [exclude-regex-on-relative-path]
tree_digest() {
  local d="$1" excl="${2:-}" f rel
  find "$d" -type f | sort | while read -r f; do
    rel="${f#$d}"
    if [[ -n "$excl" ]] && printf '%s' "$rel" | grep -Eq "$excl"; then continue; fi
    printf '%s  %s\n' "$rel" "$(hash_of "$f")"
  done
}

# --- Fixture-building helpers ------------------------------------------------

stampfile() { printf '%s/%s' "$1" "$STAMP_BASENAME"; }

# mkcfg <cfg> — a config dir with the decoy files the script must never touch.
mkcfg() {
  local cfg="$1"
  mkdir -p "$cfg/plugins/marketplaces/clam/.claude-plugin"
  mkdir -p "$cfg/plugins/cache/clam/alpha/0.2.0/.claude-plugin"
  printf '{"version":2,"plugins":{"alpha@clam":[{"scope":"user","installPath":"%s","version":"0.2.0"}]}}' \
    "$cfg/plugins/cache/clam/alpha/0.2.0" > "$cfg/plugins/installed_plugins.json"
  printf '{"name":"clam","owner":{"name":"o","email":"o@b.c"},"plugins":[{"name":"alpha","source":"./plugins/alpha","description":"d"}]}' \
    > "$cfg/plugins/marketplaces/clam/.claude-plugin/marketplace.json"
  printf '{"name":"alpha","version":"0.2.0","description":"d","author":{"name":"a","email":"a@b.c"}}' \
    > "$cfg/plugins/cache/clam/alpha/0.2.0/.claude-plugin/plugin.json"
  printf '{"hooks":{},"model":"opus"}' > "$cfg/settings.json"
}

# write_stamps <cfg> <json-literal>
write_stamps() { printf '%s' "$2" > "$(stampfile "$1")"; }

# The standard three-record file. Deleting (alpha, T_USER) must leave
# records 2 and 3 alone, plus the top-level "version" and "extra" keys.
std_stamps() {
  cat <<JSON
{
  "version": 1,
  "extra": {"keep": "me"},
  "stamps": [
    {"plugin":"alpha","version":"0.2.0","scope":"user","target":"$T_USER","at":"2026-07-24T10:00:00Z"},
    {"plugin":"alpha","version":"0.3.0","scope":"project","target":"$T_PROJ","at":"2026-07-25T10:00:00Z"},
    {"plugin":"beta","version":"1.1.0","scope":"local","target":"$T_USER","at":"2026-07-26T10:00:00Z"}
  ]
}
JSON
}

# --- Backup helpers ----------------------------------------------------------

backups_of() { find "$1" -maxdepth 1 -type f -name "$STAMP_BASENAME.bak-*" | sort; }
nbackups() { backups_of "$1" | wc -l | tr -d ' '; }
# every file whose name starts with the stamp basename (stamp + backups + any
# temp file the script forgot to clean up)
nstampfamily() { find "$1" -maxdepth 1 -type f -name "$STAMP_BASENAME*" | wc -l | tr -d ' '; }

# --- Runners -----------------------------------------------------------------

# run_prune <cfg> [args...]
run_prune() {
  local cfg="$1"; shift
  CLAUDE_CONFIG_DIR="$cfg" bash "$SCRIPT" "$@" >"$STDOUT" 2>"$STDERR"
  RC=$?
  OUT=$(cat "$STDOUT")
  ERR=$(cat "$STDERR")
  OUTLINES=$(awk 'END{print NR}' "$STDOUT")
}

# run_prune_nojq <cfg> [args...] — jq excluded from PATH
run_prune_nojq() {
  local cfg="$1"; shift
  CLAUDE_CONFIG_DIR="$cfg" PATH="$NOJQ_BIN" bash "$SCRIPT" "$@" >"$STDOUT" 2>"$STDERR"
  RC=$?
  OUT=$(cat "$STDOUT")
  ERR=$(cat "$STDERR")
  OUTLINES=$(awk 'END{print NR}' "$STDOUT")
}

# run_prune_home <home> [args...] — CLAUDE_CONFIG_DIR unset, exercises default
run_prune_home() {
  local home="$1"; shift
  env -u CLAUDE_CONFIG_DIR HOME="$home" bash "$SCRIPT" "$@" >"$STDOUT" 2>"$STDERR"
  RC=$?
  OUT=$(cat "$STDOUT")
  ERR=$(cat "$STDERR")
  OUTLINES=$(awk 'END{print NR}' "$STDOUT")
}

# A stub PATH with common coreutils (including bash) symlinked in, but
# deliberately excluding jq, so "jq not available" can be exercised without
# touching the real system PATH. Mirrors check-versions.test.sh's NOJQ_BIN.
NOJQ_BIN="$TMPROOT/no-jq-bin"
mkdir -p "$NOJQ_BIN"
for tool in bash sh cat rm tr mkdir printf sed grep basename dirname wc head tail cp mv touch date ls sort mktemp readlink realpath env find stat cut awk; do
  src=$(command -v "$tool" 2>/dev/null) || continue
  ln -sf "$src" "$NOJQ_BIN/$tool" 2>/dev/null
done

echo "=== Fixture ARGS: exit 2 — wrong argument count, empty plugin/target, usage on stderr ==="
# ============================================================================
# A fully valid fixture, so nothing but the arguments can be at fault. Each
# case must exit 2, print nothing on stdout, print a usage message on stderr,
# and leave the fixture completely untouched (no backup, no write).
# ============================================================================

CFG_ARGS="$TMPROOT/cfg-args"
mkcfg "$CFG_ARGS"
write_stamps "$CFG_ARGS" "$(std_stamps)"
ARGS_TREE_BEFORE=$(tree_digest "$CFG_ARGS")

check_args_case() { # label <args...>
  local label="$1"; shift
  run_prune "$CFG_ARGS" "$@"
  check "ARGS $label: exit 2" "$RC" "2"
  check "ARGS $label: stdout empty (no output on an error path)" "$OUT" ""
  check_true "ARGS $label: usage message on stderr" \
    "$(grep -qi 'usage' "$STDERR"; yesno $?)"
  check "ARGS $label: fixture untouched" "$(tree_digest "$CFG_ARGS")" "$ARGS_TREE_BEFORE"
  check "ARGS $label: no backup file created" "$(nbackups "$CFG_ARGS")" "0"
}

check_args_case "no arguments"
check_args_case "one argument" alpha
check_args_case "three arguments" alpha "$T_USER" extra
check_args_case "empty plugin" "" "$T_USER"
check_args_case "empty target" alpha ""
check_args_case "both empty" "" ""

echo ""
echo "=== Fixture NOFILE: exit 3 — stamp file does not exist ==="
# ============================================================================
# Valid config dir, jq present, valid arguments; only the stamp file is
# absent. The message must name the path it looked for, and the script must
# not create the file it failed to find.
# ============================================================================

CFG_NOFILE="$TMPROOT/cfg-nofile"
mkcfg "$CFG_NOFILE"
# Deliberately no clam-setup-stamps.json.

run_prune "$CFG_NOFILE" alpha "$T_USER"
check "NOFILE: exit 3" "$RC" "3"
check "NOFILE: stdout empty (no output on an error path)" "$OUT" ""
check_true "NOFILE: stderr names the path it looked for" \
  "$(grep -qF -- "$(stampfile "$CFG_NOFILE")" "$STDERR"; yesno $?)"
check_true "NOFILE: stamp file still absent (not created by the failure)" \
  "$([[ ! -e "$(stampfile "$CFG_NOFILE")" ]]; yesno $?)"
check "NOFILE: no backup file created" "$(nbackups "$CFG_NOFILE")" "0"

echo ""
echo "=== Fixture NOJQ: exit 4 — jq not available on PATH ==="
# ============================================================================
# Fully valid fixture with a matching record; only the SUT's PATH is
# restricted, so exit 4 cannot be confused with any other failure.
# ============================================================================

CFG_NOJQ="$TMPROOT/cfg-nojq"
mkcfg "$CFG_NOJQ"
write_stamps "$CFG_NOJQ" "$(std_stamps)"
NOJQ_TREE_BEFORE=$(tree_digest "$CFG_NOJQ")

run_prune_nojq "$CFG_NOJQ" alpha "$T_USER"
check "NOJQ: exit 4" "$RC" "4"
check "NOJQ: stdout empty (no output on an error path)" "$OUT" ""
check_true "NOJQ: stderr message present" "$([[ -n "$ERR" ]]; yesno $?)"
check "NOJQ: fixture untouched (no delete attempted without jq)" \
  "$(tree_digest "$CFG_NOJQ")" "$NOJQ_TREE_BEFORE"
check "NOJQ: no backup file created" "$(nbackups "$CFG_NOJQ")" "0"

echo ""
echo "=== Fixture BADJSON: exit 5 — invalid JSON, left EXACTLY as found ==="
# ============================================================================
# The contract is emphatic here: a corrupt file is reported and never
# repaired, moved aside, or overwritten. Note this differs from the setup
# skills' "move it aside to .corrupt-<date> and start fresh" rule in
# setup-stamps.md, which is scoped to setup writes; a targeted delete has no
# basis to reconstruct a file it cannot parse. So: same inode, same bytes, no
# .corrupt-* sibling, no backup, no other file touched.
# ============================================================================

CFG_BAD="$TMPROOT/cfg-badjson"
mkcfg "$CFG_BAD"
write_stamps "$CFG_BAD" '{ this is not valid json !!'
BAD_MD5_BEFORE=$(hash_of "$(stampfile "$CFG_BAD")")
BAD_INODE_BEFORE=$(inode_of "$(stampfile "$CFG_BAD")")
BAD_TREE_BEFORE=$(tree_digest "$CFG_BAD")

run_prune "$CFG_BAD" alpha "$T_USER"
check "BADJSON: exit 5" "$RC" "5"
check "BADJSON: stdout empty (no output on an error path)" "$OUT" ""
check_true "BADJSON: stderr message present" "$([[ -n "$ERR" ]]; yesno $?)"
check "BADJSON: corrupt file byte-identical (never repaired or overwritten)" \
  "$(hash_of "$(stampfile "$CFG_BAD")")" "$BAD_MD5_BEFORE"
check "BADJSON: corrupt file same inode (never rewritten in place)" \
  "$(inode_of "$(stampfile "$CFG_BAD")")" "$BAD_INODE_BEFORE"
check "BADJSON: no backup file created" "$(nbackups "$CFG_BAD")" "0"
check "BADJSON: corrupt file not moved aside (no .corrupt-* sibling)" \
  "$(find "$CFG_BAD" -maxdepth 1 -name "$STAMP_BASENAME.corrupt*" | wc -l | tr -d ' ')" "0"
check "BADJSON: whole fixture tree untouched, stamp file included" \
  "$(tree_digest "$CFG_BAD")" "$BAD_TREE_BEFORE"

echo ""
echo "=== Fixture NOTARRAY: exit 5 — valid JSON whose .stamps is not an array ==="

CFG_OBJ="$TMPROOT/cfg-stamps-object"
mkcfg "$CFG_OBJ"
write_stamps "$CFG_OBJ" '{"version":1,"stamps":{"alpha":"0.2.0"}}'
OBJ_MD5_BEFORE=$(hash_of "$(stampfile "$CFG_OBJ")")

run_prune "$CFG_OBJ" alpha "$T_USER"
check "NOTARRAY object: exit 5" "$RC" "5"
check "NOTARRAY object: stdout empty (no output on an error path)" "$OUT" ""
check_true "NOTARRAY object: stderr message present" "$([[ -n "$ERR" ]]; yesno $?)"
check "NOTARRAY object: file left exactly as found" \
  "$(hash_of "$(stampfile "$CFG_OBJ")")" "$OBJ_MD5_BEFORE"
check "NOTARRAY object: no backup file created" "$(nbackups "$CFG_OBJ")" "0"

CFG_STR="$TMPROOT/cfg-stamps-string"
mkcfg "$CFG_STR"
write_stamps "$CFG_STR" '{"version":1,"stamps":"none"}'

run_prune "$CFG_STR" alpha "$T_USER"
check "NOTARRAY string: exit 5" "$RC" "5"
check "NOTARRAY string: stdout empty (no output on an error path)" "$OUT" ""

# .stamps absent entirely is also "not an array" (jq sees null), so it takes
# the same path — the file is malformed against setup-stamps.md's shape.
CFG_MISSING="$TMPROOT/cfg-stamps-missing"
mkcfg "$CFG_MISSING"
write_stamps "$CFG_MISSING" '{"version":1}'

run_prune "$CFG_MISSING" alpha "$T_USER"
check "NOTARRAY absent: .stamps missing entirely -> exit 5" "$RC" "5"
check "NOTARRAY absent: stdout empty (no output on an error path)" "$OUT" ""

echo ""
echo "=== Fixture EMPTYFILE: exit 5 — stamp file present but 0 bytes ==="

CFG_ZERO="$TMPROOT/cfg-zerobyte"
mkcfg "$CFG_ZERO"
: > "$(stampfile "$CFG_ZERO")"
check "EMPTYFILE: fixture precondition, file is 0 bytes" \
  "$(wc -c < "$(stampfile "$CFG_ZERO")" | tr -d ' ')" "0"

run_prune "$CFG_ZERO" alpha "$T_USER"
check "EMPTYFILE: 0-byte file is not valid JSON -> exit 5" "$RC" "5"
check "EMPTYFILE: stdout empty (no output on an error path)" "$OUT" ""
check_true "EMPTYFILE: stderr message present" "$([[ -n "$ERR" ]]; yesno $?)"
check "EMPTYFILE: file still present and still 0 bytes (not repaired)" \
  "$(wc -c < "$(stampfile "$CFG_ZERO")" | tr -d ' ')" "0"
check "EMPTYFILE: no backup file created" "$(nbackups "$CFG_ZERO")" "0"

echo ""
echo "=== Fixture DELETE: the successful delete — confirmation, survivors, backup, atomicity ==="
# ============================================================================
# Three records; delete (alpha, T_USER). The two survivors are chosen to
# be the exact near-misses the invariant is about:
#   - alpha @ T_PROJ  (same plugin, different target)
#   - beta  @ T_USER  (different plugin, same target)
# ============================================================================

CFG_DEL="$TMPROOT/cfg-delete"
mkcfg "$CFG_DEL"
write_stamps "$CFG_DEL" "$(std_stamps)"
DEL_FILE="$(stampfile "$CFG_DEL")"
DEL_BEFORE_COPY="$TMPROOT/delete-before.json"
cp "$DEL_FILE" "$DEL_BEFORE_COPY"
DEL_MD5_BEFORE=$(hash_of "$DEL_FILE")
DEL_INODE_BEFORE=$(inode_of "$DEL_FILE")
DEL_TREE_BEFORE=$(tree_digest "$CFG_DEL" "$STAMP_EXCL")

# canonical form of one record, from a given file
record_of() { # <file> <plugin> <target>
  jq -S -c --arg p "$2" --arg t "$3" '[.stamps[] | select(.plugin==$p and .target==$t)]' "$1"
}

run_prune "$CFG_DEL" alpha "$T_USER"
DEL_CONFIRM="$OUT"

check "DELETE: exit 0" "$RC" "0"
check "DELETE: exactly one line on stdout" "$OUTLINES" "1"
check_true "DELETE: confirmation names the plugin" \
  "$(grep -qF -- 'alpha' "$STDOUT"; yesno $?)"
check_true "DELETE: confirmation names the target" \
  "$(grep -qF -- "$T_USER" "$STDOUT"; yesno $?)"
check_true "DELETE: confirmation names the removed record's version (0.2.0)" \
  "$(grep -qF -- '0.2.0' "$STDOUT"; yesno $?)"
check_true "DELETE: confirmation does not name a surviving record's version (0.3.0)" \
  "$(if grep -qF -- '0.3.0' "$STDOUT"; then echo no; else echo yes; fi)"

# The single strongest assertion: the new file must equal the old file with
# exactly the matching record deleted — same top-level keys, same survivor
# order, nothing else rewritten.
DEL_EXPECT=$(jq -S -c --arg t "$T_USER" \
  '.stamps |= map(select(.plugin != "alpha" or .target != $t))' "$DEL_BEFORE_COPY")
check "DELETE: file equals the original minus exactly the matching record" \
  "$(jq -S -c . "$DEL_FILE")" "$DEL_EXPECT"

check "DELETE: matching record is gone" \
  "$(record_of "$DEL_FILE" alpha "$T_USER")" "[]"
check "DELETE: same plugin at a DIFFERENT target survives unchanged" \
  "$(record_of "$DEL_FILE" alpha "$T_PROJ")" \
  "$(record_of "$DEL_BEFORE_COPY" alpha "$T_PROJ")"
check "DELETE: DIFFERENT plugin at the same target survives unchanged" \
  "$(record_of "$DEL_FILE" beta "$T_USER")" \
  "$(record_of "$DEL_BEFORE_COPY" beta "$T_USER")"
check "DELETE: exactly one record removed (3 -> 2)" \
  "$(jq -c '.stamps | length' "$DEL_FILE")" "2"
check "DELETE: survivor order preserved" \
  "$(jq -c '[.stamps[].plugin]' "$DEL_FILE")" '["alpha","beta"]'
check "DELETE: top-level version field preserved" "$(jq -c '.version' "$DEL_FILE")" "1"
check "DELETE: other top-level keys preserved" "$(jq -c '.extra' "$DEL_FILE")" '{"keep":"me"}'
check "DELETE: top-level key set unchanged" \
  "$(jq -S -c 'keys' "$DEL_FILE")" "$(jq -S -c 'keys' "$DEL_BEFORE_COPY")"

check "DELETE: exactly one backup file created" "$(nbackups "$CFG_DEL")" "1"
DEL_BACKUP=$(backups_of "$CFG_DEL")
DEL_BACKUP_DATE="${DEL_BACKUP##*.bak-}"
check_true "DELETE: backup is named <file>.bak-<YYYY-MM-DD>" \
  "$(printf '%s' "$DEL_BACKUP_DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; yesno $?)"
check_true "DELETE: backup date is today ($TODAY_LOCAL local / $TODAY_UTC UTC)" \
  "$([[ "$DEL_BACKUP_DATE" == "$TODAY_LOCAL" || "$DEL_BACKUP_DATE" == "$TODAY_UTC" ]]; yesno $?)"
check "DELETE: backup holds the pre-delete content byte-for-byte" \
  "$(hash_of "$DEL_BACKUP")" "$DEL_MD5_BEFORE"

check_ne "DELETE: stamp file inode replaced (written via temp+mv, not truncated in place)" \
  "$(inode_of "$DEL_FILE")" "$DEL_INODE_BEFORE"
check "DELETE: only the stamp file and its backup exist under that basename (no temp left behind)" \
  "$(nstampfamily "$CFG_DEL")" "2"
check "DELETE: every other file in the config dir untouched" \
  "$(tree_digest "$CFG_DEL" "$STAMP_EXCL")" "$DEL_TREE_BEFORE"

echo ""
echo "=== Fixture IDEMPOTENT: running the same delete twice ==="
# Continues on CFG_DEL, whose record is now already gone.

IDEM_TREE_BEFORE=$(tree_digest "$CFG_DEL")
IDEM_INODE_BEFORE=$(inode_of "$DEL_FILE")

run_prune "$CFG_DEL" alpha "$T_USER"
check "IDEMPOTENT: second run exits 0 (already absent is success)" "$RC" "0"
check "IDEMPOTENT: exactly one line on stdout" "$OUTLINES" "1"
check_ne "IDEMPOTENT: the no-match notice differs from the delete confirmation" \
  "$OUT" "$DEL_CONFIRM"
check "IDEMPOTENT: nothing at all changed on disk (stamp file and backup included)" \
  "$(tree_digest "$CFG_DEL")" "$IDEM_TREE_BEFORE"
check "IDEMPOTENT: stamp file not rewritten (same inode)" \
  "$(inode_of "$DEL_FILE")" "$IDEM_INODE_BEFORE"
check "IDEMPOTENT: still exactly one backup (the second run wrote no backup)" \
  "$(nbackups "$CFG_DEL")" "1"

echo ""
echo "=== Fixture NOMATCH: no matching record -> exit 0, notice, and NO write at all ==="
# ============================================================================
# A fresh fixture, so "no backup file was created" is unambiguous: absent, not
# merely unchanged.
# ============================================================================

CFG_NOMATCH="$TMPROOT/cfg-nomatch"
mkcfg "$CFG_NOMATCH"
write_stamps "$CFG_NOMATCH" "$(std_stamps)"
NOMATCH_FILE="$(stampfile "$CFG_NOMATCH")"
NOMATCH_MD5_BEFORE=$(hash_of "$NOMATCH_FILE")
NOMATCH_INODE_BEFORE=$(inode_of "$NOMATCH_FILE")
NOMATCH_TREE_BEFORE=$(tree_digest "$CFG_NOMATCH")

run_prune "$CFG_NOMATCH" ghost-plugin "$T_USER"
check "NOMATCH: exit 0" "$RC" "0"
check "NOMATCH: exactly one line of notice on stdout" "$OUTLINES" "1"
check_ne "NOMATCH: notice differs from a delete confirmation" "$OUT" "$DEL_CONFIRM"
check "NOMATCH: NO backup file created at all" "$(nbackups "$CFG_NOMATCH")" "0"
check "NOMATCH: only the stamp file exists under that basename" \
  "$(nstampfamily "$CFG_NOMATCH")" "1"
check "NOMATCH: stamp file byte-identical" "$(hash_of "$NOMATCH_FILE")" "$NOMATCH_MD5_BEFORE"
check "NOMATCH: stamp file not rewritten (same inode)" \
  "$(inode_of "$NOMATCH_FILE")" "$NOMATCH_INODE_BEFORE"
check "NOMATCH: whole fixture tree untouched" \
  "$(tree_digest "$CFG_NOMATCH")" "$NOMATCH_TREE_BEFORE"

echo ""
echo "=== Fixture EMPTYSTAMPS: empty .stamps array -> exit 0, no write ==="

CFG_EMPTY="$TMPROOT/cfg-emptystamps"
mkcfg "$CFG_EMPTY"
write_stamps "$CFG_EMPTY" '{"version":1,"stamps":[]}'
EMPTY_TREE_BEFORE=$(tree_digest "$CFG_EMPTY")

run_prune "$CFG_EMPTY" alpha "$T_USER"
check "EMPTYSTAMPS: exit 0 (treated as no match)" "$RC" "0"
check "EMPTYSTAMPS: exactly one line of notice on stdout" "$OUTLINES" "1"
check "EMPTYSTAMPS: no backup file created" "$(nbackups "$CFG_EMPTY")" "0"
check "EMPTYSTAMPS: nothing written" "$(tree_digest "$CFG_EMPTY")" "$EMPTY_TREE_BEFORE"

echo ""
echo "=== Fixture DUP: duplicate (plugin,target) records -> ALL of them removed ==="
# ============================================================================
# Duplicates are already a malformed stamp file (the key is unique per
# setup-stamps.md); leaving one behind would make the command non-idempotent.
# ============================================================================

CFG_DUP="$TMPROOT/cfg-duplicates"
mkcfg "$CFG_DUP"
write_stamps "$CFG_DUP" "$(cat <<JSON
{
  "version": 1,
  "stamps": [
    {"plugin":"alpha","version":"0.2.0","scope":"user","target":"$T_USER","at":"2026-07-24T10:00:00Z"},
    {"plugin":"beta","version":"1.1.0","scope":"local","target":"$T_USER","at":"2026-07-26T10:00:00Z"},
    {"plugin":"alpha","version":"0.9.0","scope":"user","target":"$T_USER","at":"2026-07-27T10:00:00Z"}
  ]
}
JSON
)"
DUP_FILE="$(stampfile "$CFG_DUP")"

run_prune "$CFG_DUP" alpha "$T_USER"
check "DUP: exit 0" "$RC" "0"
check "DUP: exactly one line on stdout" "$OUTLINES" "1"
check "DUP: BOTH duplicate records removed, none left behind" \
  "$(jq -S -c --arg t "$T_USER" '[.stamps[] | select(.plugin=="alpha" and .target==$t)]' "$DUP_FILE")" \
  "[]"
check "DUP: the unrelated record survives" \
  "$(jq -c '[.stamps[].plugin]' "$DUP_FILE")" '["beta"]'
check "DUP: exactly one backup file created" "$(nbackups "$CFG_DUP")" "1"

# A rerun must now be a clean no-op — the point of removing all duplicates.
run_prune "$CFG_DUP" alpha "$T_USER"
check "DUP: rerun after removing duplicates is a no-op, exit 0" "$RC" "0"
check_ne "DUP: rerun prints the no-match notice, not a confirmation" "$OUT" "$DEL_CONFIRM"

echo ""
echo "=== Fixture EXACT: matching is exact string equality — no normalization of any kind ==="
# ============================================================================
# The stored target is an absolute path; a trailing slash, a relative form, an
# unexpanded "~", or a "@clam"-suffixed plugin name must all miss. Contract,
# not bug: exit 0 with the notice, and no write.
# ============================================================================

CFG_EXACT="$TMPROOT/cfg-exact"
mkcfg "$CFG_EXACT"
# This fixture's target is the REAL $HOME expansion, purely as a string, so
# the "~" case has something it would have matched had tildes been expanded.
HOME_TARGET="$HOME/.claude/settings.json"
write_stamps "$CFG_EXACT" "$(cat <<JSON
{
  "version": 1,
  "stamps": [
    {"plugin":"alpha","version":"0.2.0","scope":"user","target":"$HOME_TARGET","at":"2026-07-24T10:00:00Z"}
  ]
}
JSON
)"
EXACT_TREE_BEFORE=$(tree_digest "$CFG_EXACT")

check_nomatch_case() { # label plugin target
  local label="$1" plugin="$2" target="$3"
  run_prune "$CFG_EXACT" "$plugin" "$target"
  check "EXACT $label: exit 0 (no match)" "$RC" "0"
  check "EXACT $label: one-line notice on stdout" "$OUTLINES" "1"
  check "EXACT $label: no backup file created" "$(nbackups "$CFG_EXACT")" "0"
  check "EXACT $label: nothing written" "$(tree_digest "$CFG_EXACT")" "$EXACT_TREE_BEFORE"
}

check_nomatch_case "trailing slash"    alpha "$HOME_TARGET/"
check_nomatch_case "relative path"     alpha ".claude/settings.json"
check_nomatch_case "unexpanded tilde"  alpha '~/.claude/settings.json'
check_nomatch_case "double slash"      alpha "$HOME//.claude/settings.json"
check_nomatch_case "plugin with @clam suffix" "alpha@clam" "$HOME_TARGET"
check_nomatch_case "plugin case mismatch"     "Alpha" "$HOME_TARGET"

# ...and the exact stored string DOES match, proving the misses above are
# about normalization and not about a fixture that can never match.
run_prune "$CFG_EXACT" alpha "$HOME_TARGET"
check "EXACT control: the exactly-stored target matches and is removed" \
  "$(jq -c '.stamps | length' "$(stampfile "$CFG_EXACT")")" "0"
check "EXACT control: exit 0" "$RC" "0"

echo ""
echo "=== Fixture WRITEFAIL: exit 6 — the write fails, the original survives ==="
# ============================================================================
# The config dir is made read-only, so the backup/temp write inside it cannot
# succeed. Skipped (rather than silently passing) if the read-only mode is not
# actually enforced for this user, e.g. when running as root.
# ============================================================================

CFG_WF="$TMPROOT/cfg-writefail"
mkcfg "$CFG_WF"
write_stamps "$CFG_WF" "$(std_stamps)"
WF_FILE="$(stampfile "$CFG_WF")"
WF_MD5_BEFORE=$(hash_of "$WF_FILE")
WF_INODE_BEFORE=$(inode_of "$WF_FILE")
chmod 555 "$CFG_WF"

if touch "$CFG_WF/.probe" 2>/dev/null; then
  rm -f "$CFG_WF/.probe"
  chmod 755 "$CFG_WF"
  echo "SKIP  WRITEFAIL: read-only dir not enforced for this user (root?); exit 6 not exercised"
else
  run_prune "$CFG_WF" alpha "$T_USER"
  check "WRITEFAIL: exit 6" "$RC" "6"
  check "WRITEFAIL: stdout empty (no confirmation for a write that did not happen)" "$OUT" ""
  check_true "WRITEFAIL: stderr names the step that failed (backup/temp/mv/write)" \
    "$(grep -Eqi 'backup|temp|mv|rename|write' "$STDERR"; yesno $?)"
  check "WRITEFAIL: original stamp file intact, byte-identical" \
    "$(hash_of "$WF_FILE")" "$WF_MD5_BEFORE"
  check "WRITEFAIL: original stamp file not replaced (same inode)" \
    "$(inode_of "$WF_FILE")" "$WF_INODE_BEFORE"
  check "WRITEFAIL: record still present (the delete did not take effect)" \
    "$(jq -c '.stamps | length' "$WF_FILE")" "3"
  chmod 755 "$CFG_WF"
fi

echo ""
echo "=== Fixture HOMEDEFAULT: CLAUDE_CONFIG_DIR defaults to \$HOME/.claude ==="

HOME_DEFAULT="$TMPROOT/home-default"
mkdir -p "$HOME_DEFAULT/.claude"
mkcfg "$HOME_DEFAULT/.claude"
write_stamps "$HOME_DEFAULT/.claude" "$(std_stamps)"

run_prune_home "$HOME_DEFAULT" alpha "$T_USER"
check "HOMEDEFAULT: CLAUDE_CONFIG_DIR unset -> writes under \$HOME/.claude, exit 0" "$RC" "0"
check "HOMEDEFAULT: the record was removed from the default location" \
  "$(jq -S -c --arg t "$T_USER" '[.stamps[] | select(.plugin=="alpha" and .target==$t)]' \
     "$(stampfile "$HOME_DEFAULT/.claude")")" "[]"
check "HOMEDEFAULT: exactly one backup, alongside the default-location file" \
  "$(nbackups "$HOME_DEFAULT/.claude")" "1"

echo ""
echo "=== STATIC: no network access ==="
# Not observable through the interface; asserted against the script body, with
# comments stripped so prose cannot trip it.
NETHITS=$(sed 's/#.*//' "$SCRIPT" \
  | grep -Eci '(^|[^[:alnum:]_/-])(curl|wget|nc|ssh|scp|sftp)([^[:alnum:]_-]|$)')
check "STATIC: no network client invoked anywhere in the script" "$NETHITS" "0"

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit $FAILED
