#!/usr/bin/env bash
# marketplace-lint.test.sh — contract tests for scripts/marketplace-lint.sh,
# focused on the check that every marketplace entry carries a nonempty
# "category" string.
#
# Black-box only: builds fixture trees under mktemp -d and asserts on the
# script's stdout lines and exit code, never on its internals.
#
# Two deliberate departures from the sibling lint tests
# (readme-lint.test.sh, issue-template-lint.test.sh), both forced by the
# script under test:
#
#   1. Fixtures contain a COPY of the script. marketplace-lint.sh resolves
#      its repo root from its own location ("$(dirname "$BASH_SOURCE")/..")
#      rather than from cwd, so cd'ing into a fixture and invoking the real
#      script by absolute path would still lint this worktree. Copying it to
#      <fixture>/scripts/ is what points it at the fixture tree.
#   2. Assertions on the happy path are line-level (a PASS line naming the
#      plugin and its category check) rather than exit-code-level, because
#      marketplace-lint.sh lists plugin directories with `find -printf`,
#      a GNU extension BSD find (macOS) lacks. Where that fails, the
#      entry/dir parity check fails for reasons unrelated to categories and
#      the script exits 1 no matter what the categories say. Exit-code
#      assertions that require an otherwise-clean run are therefore gated on
#      a runtime probe, mirroring how issue-template-lint.test.sh gates its
#      parser-present assertions on HAVE_PARSER. Failure-case exit codes are
#      asserted unconditionally: exit 1 is correct on either host.
#
# Category-line assertions match "<name>:" plus the word "category" on one
# status line, without pinning the check's exact wording — the invariant is
# that a violation is reported against the offending entry, not its phrasing.
#
# Run: bash scripts/marketplace-lint.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/marketplace-lint.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REAL_MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: script under test not found at $SCRIPT" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq is required by the script under test and by this harness" >&2
  exit 2
fi

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# GNU find's -printf, used by the script to enumerate plugin directories.
# Absent on BSD find; see the header note.
HAVE_FIND_PRINTF="$(find . -maxdepth 0 -printf '' >/dev/null 2>&1 && echo yes || echo no)"

# ---------------------------------------------------------------------------
# Cleanup registry for mktemp fixture trees (command substitution forks a
# subshell, so a file-based manifest is needed to survive it).
# ---------------------------------------------------------------------------
CLEANUP_MANIFEST="$(mktemp)"
track_tmp() { printf '%s\n' "$1" >> "$CLEANUP_MANIFEST"; }
cleanup() {
  if [ -f "$CLEANUP_MANIFEST" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] && [ -e "$d" ] && rm -rf -- "$d"
    done < "$CLEANUP_MANIFEST"
    rm -f -- "$CLEANUP_MANIFEST"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fixture builders. Fixture plugin names (alpha/beta/gamma) are fictional and
# independent of the real catalog.
# ---------------------------------------------------------------------------
entry() { # <name> [category-as-JSON] -> one plugin entry; omit the 2nd arg for no category key
  local name="$1"
  if [ "$#" -lt 2 ]; then
    printf '{"name":"%s","source":"./plugins/%s","description":"d"}' "$name" "$name"
  else
    printf '{"name":"%s","source":"./plugins/%s","description":"d","category":%s}' \
      "$name" "$name" "$2"
  fi
}

marketplace() { # <entry>... -> full marketplace.json text
  local IFS=','
  printf '{"name":"fixture","owner":{"name":"t","email":"t@example.com"},"plugins":[%s]}' "$*"
}

new_fixture() { # <marketplace.json text> -> fixture root
  local json="$1" d name
  d="$(mktemp -d)"
  track_tmp "$d"
  mkdir -p "$d/scripts" "$d/.claude-plugin" "$d/plugins"
  cp "$SCRIPT" "$d/scripts/marketplace-lint.sh"
  printf '%s\n' "$json" > "$d/.claude-plugin/marketplace.json"
  # A plugin directory (with plugin.json) per entry, so entry/dir parity and
  # source resolution pass and the category check is the only variable.
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    mkdir -p "$d/plugins/$name/.claude-plugin"
    printf '{"name":"%s","version":"0.1.0"}\n' "$name" \
      > "$d/plugins/$name/.claude-plugin/plugin.json"
  done < <(jq -r '.plugins[].name' "$d/.claude-plugin/marketplace.json")
  printf '%s' "$d"
}

# ---------------------------------------------------------------------------
# Invocation helper.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0

run_lint() { # <fixture_root>
  local fixture="$1" out err
  out="$(mktemp)"; err="$(mktemp)"
  ( cd "$fixture" && bash "$fixture/scripts/marketplace-lint.sh" >"$out" 2>"$err" )
  RUN_EXIT=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  rm -f "$out" "$err"
}

cat_line() { # <text> <PASS|FAIL> <plugin name> -> yes/no
  printf '%s\n' "$1" \
    | grep -Eq "^$2[[:space:]]+$3:[[:space:]].*category" && echo yes || echo no
}

cat_fail_count() { # <text> -> number of category FAIL lines
  printf '%s\n' "$1" | grep -Ec "^FAIL[[:space:]].*category" || true
}

tree_snapshot() { # <root> -> sorted per-file checksums (cksum is POSIX; sha256sum is not)
  ( cd "$1" && find . -type f -exec cksum {} + ) | sort
}

ALL_OK="$(marketplace \
  "$(entry alpha '"delivery"')" \
  "$(entry beta '"records"')" \
  "$(entry gamma '"setup"')")"

# ===========================================================================
# 1. Happy path: every entry carries a nonempty category -> a category PASS
#    line per entry, zero category FAIL lines.
# ===========================================================================
f="$(new_fixture "$ALL_OK")"
run_lint "$f"
check "all categorized: alpha reported PASS" "$(cat_line "$RUN_OUT" PASS alpha)" "yes"
check "all categorized: beta reported PASS" "$(cat_line "$RUN_OUT" PASS beta)" "yes"
check "all categorized: gamma reported PASS" "$(cat_line "$RUN_OUT" PASS gamma)" "yes"
check "all categorized: no category FAIL lines" "$(cat_fail_count "$RUN_OUT")" "0"
if [ "$HAVE_FIND_PRINTF" = "yes" ]; then
  check "all categorized: exit 0" "$RUN_EXIT" "0"
else
  echo "NOTE: find lacks -printf here; skipping the clean-run exit-0 assertions (category line assertions still cover the check)."
fi

# ===========================================================================
# 2. Missing category key -> FAIL for that entry only; siblings unaffected.
#    This is the "a future plugin entry added without a category must FAIL"
#    boundary condition.
# ===========================================================================
f="$(new_fixture "$(marketplace \
  "$(entry alpha '"delivery"')" \
  "$(entry beta)" \
  "$(entry gamma '"setup"')")")"
run_lint "$f"
check "missing category key: beta reported FAIL" "$(cat_line "$RUN_OUT" FAIL beta)" "yes"
check "missing category key: exit 1" "$RUN_EXIT" "1"
check "missing category key: alpha still PASS" "$(cat_line "$RUN_OUT" PASS alpha)" "yes"
check "missing category key: gamma still PASS" "$(cat_line "$RUN_OUT" PASS gamma)" "yes"
check "missing category key: exactly one category FAIL" "$(cat_fail_count "$RUN_OUT")" "1"

# ===========================================================================
# 3. Empty-string category -> FAIL (present but useless is not "present").
# ===========================================================================
f="$(new_fixture "$(marketplace \
  "$(entry alpha '"delivery"')" \
  "$(entry beta '""')" \
  "$(entry gamma '"setup"')")")"
run_lint "$f"
check "empty-string category: beta reported FAIL" "$(cat_line "$RUN_OUT" FAIL beta)" "yes"
check "empty-string category: exit 1" "$RUN_EXIT" "1"
check "empty-string category: exactly one category FAIL" "$(cat_fail_count "$RUN_OUT")" "1"

# ===========================================================================
# 4. Explicit JSON null -> FAIL. Guards the jq null-coalescing trap: a null
#    must not read as a value merely because the key exists.
# ===========================================================================
f="$(new_fixture "$(marketplace \
  "$(entry alpha '"delivery"')" \
  "$(entry beta 'null')" \
  "$(entry gamma '"setup"')")")"
run_lint "$f"
check "null category: beta reported FAIL" "$(cat_line "$RUN_OUT" FAIL beta)" "yes"
check "null category: exit 1" "$RUN_EXIT" "1"

# ===========================================================================
# 5. Non-string categories -> FAIL. The array case is the one a length-only
#    check would wrongly accept: ["delivery"] is nonempty but is not a
#    category string.
# ===========================================================================
f="$(new_fixture "$(marketplace \
  "$(entry alpha '"delivery"')" \
  "$(entry beta '42')" \
  "$(entry gamma '"setup"')")")"
run_lint "$f"
check "numeric category: beta reported FAIL" "$(cat_line "$RUN_OUT" FAIL beta)" "yes"
check "numeric category: exit 1" "$RUN_EXIT" "1"

f="$(new_fixture "$(marketplace \
  "$(entry alpha '"delivery"')" \
  "$(entry beta '["delivery"]')" \
  "$(entry gamma '"setup"')")")"
run_lint "$f"
check "array category: beta reported FAIL" "$(cat_line "$RUN_OUT" FAIL beta)" "yes"
check "array category: exit 1" "$RUN_EXIT" "1"

# ===========================================================================
# 6. Every entry uncategorized -> every entry reported, not just the first.
# ===========================================================================
f="$(new_fixture "$(marketplace \
  "$(entry alpha)" "$(entry beta)" "$(entry gamma)")")"
run_lint "$f"
check "no categories at all: alpha reported FAIL" "$(cat_line "$RUN_OUT" FAIL alpha)" "yes"
check "no categories at all: beta reported FAIL" "$(cat_line "$RUN_OUT" FAIL beta)" "yes"
check "no categories at all: gamma reported FAIL" "$(cat_line "$RUN_OUT" FAIL gamma)" "yes"
check "no categories at all: three category FAILs" "$(cat_fail_count "$RUN_OUT")" "3"
check "no categories at all: exit 1" "$RUN_EXIT" "1"

# ===========================================================================
# 7. Differential: dropping one category changes the report in exactly one
#    place, and that place is the offending entry's category line. This is
#    the host-independent form of "the category check decides the outcome" —
#    it holds whether or not find supports -printf, since any -printf-induced
#    noise is identical across the two runs and cancels out.
# ===========================================================================
run_lint "$(new_fixture "$ALL_OK")"
out_ok="$RUN_OUT"
run_lint "$(new_fixture "$(marketplace \
  "$(entry alpha '"delivery"')" \
  "$(entry beta)" \
  "$(entry gamma '"setup"')")")"
out_bad="$RUN_OUT"

diff_lines="$(diff <(printf '%s\n' "$out_ok") <(printf '%s\n' "$out_bad") \
  | grep -E '^[<>]' || true)"
check "differential: one line differs, in both directions" \
  "$(printf '%s\n' "$diff_lines" | grep -Ec '^[<>]' || true)" "2"
check "differential: the differing lines are beta's category line" \
  "$(printf '%s\n' "$diff_lines" | grep -Evc 'beta:.*category' || true)" "0"

# ===========================================================================
# 8. Read-only invariant: the fixture tree is byte-identical after a run,
#    across both a passing and a failing category state.
# ===========================================================================
f="$(new_fixture "$ALL_OK")"
before="$(tree_snapshot "$f")"
run_lint "$f"
check "read-only (all categorized): fixture unchanged" "$(tree_snapshot "$f")" "$before"

f="$(new_fixture "$(marketplace "$(entry alpha)" "$(entry beta '"records"')")")"
before="$(tree_snapshot "$f")"
run_lint "$f"
check "read-only (violating run): fixture unchanged" "$(tree_snapshot "$f")" "$before"

# ===========================================================================
# 9. Integration against the real catalog, read-only: every committed entry
#    satisfies the invariant this check enforces. Asserted on the catalog
#    directly so it holds regardless of find's -printf support; the full
#    clean-run exit code is asserted only where the script can produce one.
# ===========================================================================
uncategorized="$(jq -r '
  .plugins[]
  | select((.category | type == "string" and length > 0) | not)
  | .name' "$REAL_MARKETPLACE")"
check "real catalog: no entry lacks a nonempty category" "$uncategorized" ""

real_entries="$(jq -r '.plugins | length' "$REAL_MARKETPLACE")"
check "real catalog: every entry reported PASS for category" \
  "$( (cd "$REPO_ROOT" && bash "$SCRIPT" 2>/dev/null) \
      | grep -Ec "^PASS[[:space:]].*category" || true)" "$real_entries"

if [ "$HAVE_FIND_PRINTF" = "yes" ]; then
  ( cd "$REPO_ROOT" && bash "$SCRIPT" >/dev/null 2>&1 )
  check "real repo root: exit 0" "$?" "0"
fi

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
