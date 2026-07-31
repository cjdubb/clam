#!/usr/bin/env bash
# architecture-lint.test.sh — contract tests for scripts/architecture-lint.sh
# (B08 architecture-lint, plan 001-ensure-agents-understand-architecture).
#
# Black-box only: builds throwaway git repositories under mktemp -d containing
# a plugins/ tree and (per case) a scripts/architecture-lint-baseline.txt,
# then invokes the REAL scripts/architecture-lint.sh (resolved via
# BASH_SOURCE from this repo) with cwd inside the fixture, so its git-root
# discovery and git-ls-files scan operate on the fixture, never this repo's
# own plugins/ tree or baseline. Every fixture plugin referenced as a hit
# TARGET is given at least one tracked file of its own under plugins/<name>/,
# since the contract discovers the plugin-name vocabulary from directory
# names under plugins/ — an unregistered name can never be detected as a
# reference target.
#
# Mirrors the named-test / assert-helper harness style of
# plugins/lego/scripts/pr-size-check.test.sh.
#
# Run: bash architecture-lint.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/architecture-lint.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: script under test not found at $SCRIPT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Cleanup registry (command substitution forks a subshell, so a file-based
# manifest is needed to survive it — see pr-size-check.test.sh).
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
# Minimal named-test harness (see pr-size-check.test.sh).
# ---------------------------------------------------------------------------
CURRENT_FAILURES=0
TOTAL_PASS=0
TOTAL_FAIL=0

start_test() { CURRENT_FAILURES=0; }
record_fail() {
  CURRENT_FAILURES=$((CURRENT_FAILURES + 1))
  printf '    FAIL: %s\n' "$1"
}
end_test() {
  local name="$1"
  if [ "$CURRENT_FAILURES" -eq 0 ]; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
    echo "ok - $name"
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    echo "not ok - $name ($CURRENT_FAILURES failing assertion(s))"
  fi
}
run_test() {
  local name="$1"
  shift
  start_test
  "$@"
  end_test "$name"
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" != "$actual" ]; then
    record_fail "$label: expected [$expected] got [$actual]"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in
    *"$needle"*) : ;;
    *) record_fail "$label: expected output to contain [$needle], got: $haystack" ;;
  esac
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in
    *"$needle"*) record_fail "$label: expected output NOT to contain [$needle], got: $haystack" ;;
  esac
}

# ---------------------------------------------------------------------------
# Fixture repo builder: git-init, one commit, plugins/ and scripts/
# pre-created. Ambient global hooks neutralized (see version-bump-lint.test.sh).
# ---------------------------------------------------------------------------
new_repo() {
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    git config core.hooksPath "$d/.git/no-such-hooks-dir"
    mkdir -p scripts plugins
    printf '# fixture\n' > README.md
    git add -A
    git commit -q -m init
  ) >/dev/null
  printf '%s' "$d"
}

# ensure_plugin <repo> <name> -- registers <name> in the discovered plugin
# vocabulary via one committed, self-referencing (therefore inert) tracked
# file. Every target plugin used anywhere below needs this, or the scanner
# has no vocabulary entry to detect references to it.
ensure_plugin() {
  local repo="$1" name="$2"
  mkdir -p "$repo/plugins/$name"
  printf '# %s plugin\n\nInternal notes for %s.\n' "$name" "$name" > "$repo/plugins/$name/README.md"
  git -C "$repo" add "plugins/$name/README.md"
  git -C "$repo" commit -q -m "add $name plugin" >/dev/null
}

# write_plugin_file <repo> <name> <relpath> <content> -- writes (not
# committed) a file under plugins/<name>/<relpath>.
write_plugin_file() {
  local repo="$1" name="$2" rel="$3" content="$4"
  mkdir -p "$repo/plugins/$name/$(dirname "$rel")"
  printf '%s' "$content" > "$repo/plugins/$name/$rel"
}

commit_all() {
  local repo="$1" msg="$2"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "$msg" >/dev/null
}

write_baseline() {
  local repo="$1" content="$2"
  printf '%s' "$content" > "$repo/scripts/architecture-lint-baseline.txt"
}

# line_no <file> <needle> -- 1-indexed line number of the first line of
# <file> containing the literal <needle>. Works with process substitution
# too, so it doubles as a line-finder over captured stdout.
line_no() {
  grep -n -F -- "$2" "$1" | head -n1 | cut -d: -f1
}

expected_new() { # path line form target text
  printf "NEW  %s:%s: %s reference to '%s': %s" "$1" "$2" "$3" "$4" "$5"
}

expected_stale() { # path form target
  printf "STALE  baseline entry has no matches: %s %s %s" "$1" "$2" "$3"
}

# ---------------------------------------------------------------------------
# Invocation helper.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0

run_lint() { # <cwd>
  local cwd="$1"
  local out err
  out="$(mktemp)"; err="$(mktemp)"
  ( cd "$cwd" && bash "$SCRIPT" >"$out" 2>"$err" )
  RUN_EXIT=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  rm -f "$out" "$err"
}

# ===========================================================================
# Clause 1: each of the four reference forms is detected and reported with
# exact path:line, form name, and target. Contract: Behavior (the four
# forms), Outputs (NEW line format).
# ===========================================================================
test_four_forms_detected_with_exact_reporting() {
  local repo l1 l2 l3 l4
  repo="$(new_repo)"
  ensure_plugin "$repo" beta

  local skill_line='Uses /beta:some-skill for X.'
  local mkt_line='Also see beta@clam in the marketplace.'
  local eng_line='The beta plugin handles Y.'
  local path_line='Path: plugins/beta/lib/foo.sh'
  write_plugin_file "$repo" alpha "NOTES.md" "$skill_line
$mkt_line
$eng_line
$path_line
"
  commit_all "$repo" "add alpha notes"

  l1="$(line_no "$repo/plugins/alpha/NOTES.md" "$skill_line")"
  l2="$(line_no "$repo/plugins/alpha/NOTES.md" "$mkt_line")"
  l3="$(line_no "$repo/plugins/alpha/NOTES.md" "$eng_line")"
  l4="$(line_no "$repo/plugins/alpha/NOTES.md" "$path_line")"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1 (4 new hits, no baseline), got $RUN_EXIT (stderr: $RUN_ERR)"

  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$l1" "skill-invocation" "beta" "$skill_line")" "skill-invocation hit"
  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$l2" "marketplace-id" "beta" "$mkt_line")" "marketplace-id hit"
  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$l3" "english" "beta" "$eng_line")" "english hit"
  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$l4" "path" "beta" "$path_line")" "path hit"
}

# Contract clause: english form is "case-insensitive on the word 'plugin'".
test_english_form_case_insensitive_on_plugin_word() {
  local repo line l
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  line='See the beta PLUGIN docs.'
  write_plugin_file "$repo" alpha "NOTES.md" "$line
"
  commit_all "$repo" "add alpha notes"
  l="$(line_no "$repo/plugins/alpha/NOTES.md" "$line")"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$l" "english" "beta" "$line")" "case-insensitive PLUGIN still matches"
}

# ===========================================================================
# Clause 2: form-based ONLY -- a bare plugin name in prose is never a hit
# (the word-sense clause, e.g. "landing strategy" or a `build` command word).
# ===========================================================================
test_word_sense_bare_name_never_flags() {
  local repo line
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  line='The beta strategy guides beta workflows; run the beta command to start.'
  write_plugin_file "$repo" alpha "NOTES.md" "$line
"
  commit_all "$repo" "add alpha notes"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "bare plugin-name prose (no form) should be a clean pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_not_contains "$RUN_OUT" "reference to 'beta'" "bare-word prose must never be reported as a hit"
}

# ===========================================================================
# Clause 3: self-reference never flags, in any of the four forms.
# ===========================================================================
test_self_reference_never_flags_any_form() {
  local repo
  repo="$(new_repo)"
  ensure_plugin "$repo" alpha
  write_plugin_file "$repo" alpha "MORE.md" "/alpha:some-skill
alpha@clam
the alpha plugin
plugins/alpha/lib/x.sh
"
  commit_all "$repo" "add alpha self references"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "self-references in all 4 forms should be a clean pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_not_contains "$RUN_OUT" "reference to 'alpha'" "self-reference must never be reported as a hit, in any form"
}

# ===========================================================================
# Clause 4: allowlist -- build->{landing,lego,tracking,forge-github,
# forge-gitlab} is silent (not reported, not baseline-required); build-> any
# other plugin flags; a non-build plugin referencing landing flags.
# ===========================================================================
test_allowlist_build_to_allowlisted_targets_silent() {
  local repo p
  repo="$(new_repo)"
  for p in landing lego tracking forge-github forge-gitlab; do
    ensure_plugin "$repo" "$p"
  done
  ensure_plugin "$repo" build
  write_plugin_file "$repo" build "NOTES.md" "plugins/landing/
plugins/lego/
plugins/tracking/
plugins/forge-github/
plugins/forge-gitlab/
"
  commit_all "$repo" "add build notes"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "build referencing the 5 allowlisted plugins (no baseline at all) should be a clean pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  for p in landing lego tracking forge-github forge-gitlab; do
    assert_not_contains "$RUN_OUT" "reference to '$p'" "allowlisted build->$p reference must be silent"
  done
}

test_allowlist_build_referencing_non_allowlisted_target_flags() {
  local repo line l
  repo="$(new_repo)"
  ensure_plugin "$repo" build
  ensure_plugin "$repo" gamma
  line='plugins/gamma/lib/x.sh'
  write_plugin_file "$repo" build "NOTES.md" "$line
"
  commit_all "$repo" "add build notes"
  l="$(line_no "$repo/plugins/build/NOTES.md" "$line")"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "build referencing non-allowlisted gamma should flag, got exit $RUN_EXIT (stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new "plugins/build/NOTES.md" "$l" "path" "gamma" "$line")" "build->gamma (not allowlisted) must be reported"
}

test_non_build_plugin_referencing_landing_flags() {
  local repo line l
  repo="$(new_repo)"
  ensure_plugin "$repo" alpha
  ensure_plugin "$repo" landing
  line='plugins/landing/lib/x.sh'
  write_plugin_file "$repo" alpha "NOTES.md" "$line
"
  commit_all "$repo" "add alpha notes"
  l="$(line_no "$repo/plugins/alpha/NOTES.md" "$line")"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "non-build alpha referencing landing should flag (allowlist only exempts build), got exit $RUN_EXIT (stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$l" "path" "landing" "$line")" "alpha->landing must be reported (allowlist is build-only)"
}

# ===========================================================================
# Clause 5: allow-pragma. A hit line containing "architecture-lint: allow
# <reason>" is excused; an empty reason does NOT excuse and is itself
# reported as a defect.
# ===========================================================================
test_pragma_nonempty_reason_excuses_hit() {
  local repo line
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  line='See plugins/beta/ for docs. # architecture-lint: allow intentional interop, tracked in issue 42'
  write_plugin_file "$repo" alpha "NOTES.md" "$line
"
  commit_all "$repo" "add alpha notes"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "pragma with a non-empty reason should excuse the hit, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_not_contains "$RUN_OUT" "reference to 'beta'" "pragma-excused hit must not be reported as NEW"
}

test_pragma_empty_reason_does_not_excuse_and_is_reported_as_defect() {
  local repo line l
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  line='See plugins/beta/ for docs. # architecture-lint: allow'
  write_plugin_file "$repo" alpha "NOTES.md" "$line
"
  commit_all "$repo" "add alpha notes"
  l="$(line_no "$repo/plugins/alpha/NOTES.md" "$line")"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "empty-reason pragma must not excuse -- expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "plugins/alpha/NOTES.md:$l:" "empty-reason pragma: the underlying hit is still reported"
  assert_contains "$RUN_OUT" "reference to 'beta'" "empty-reason pragma: the underlying hit still names its target"
  case "$RUN_OUT" in
    *[Ee]mpty*) : ;;
    *) record_fail "empty-reason pragma: expected a note that the pragma reason is empty, got: $RUN_OUT" ;;
  esac
}

# ===========================================================================
# Clause 6: baseline semantics.
# ===========================================================================

# A triple-matched hit passes (counted, not failed).
test_baseline_matched_hit_passes_counted_not_failed() {
  local repo line
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  line='plugins/beta/lib/foo.sh'
  write_plugin_file "$repo" alpha "NOTES.md" "$line
"
  commit_all "$repo" "add alpha notes"
  write_baseline "$repo" "$(printf 'plugins/alpha/NOTES.md\tpath\tbeta\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "a hit matching a baseline triple should pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_not_contains "$RUN_OUT" "reference to 'beta'" "baselined hit must not be reported as a per-hit NEW line"
}

# A STALE baseline row (no matching hits) fails exit 1 with the STALE output
# line -- covering both the file-deleted case and the reference-edited-away
# case in one run, and confirming stale entries appear in BASELINE order
# (not path order).
test_baseline_stale_rows_reported_and_preserve_baseline_order() {
  local repo
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  ensure_plugin "$repo" alpha
  ensure_plugin "$repo" zeta
  write_plugin_file "$repo" zeta "OLD.md" "plugins/beta/lib/x.sh
"
  write_plugin_file "$repo" alpha "OLD.md" "plugins/beta/lib/y.sh
"
  commit_all "$repo" "add references that will go stale"

  # zeta's row listed BEFORE alpha's -- the reverse of path-sort order -- so
  # the assertion below can distinguish "baseline order" from "sorted by
  # path".
  write_baseline "$repo" "$(printf 'plugins/zeta/OLD.md\tpath\tbeta\nplugins/alpha/OLD.md\tpath\tbeta\n')"

  # Delete zeta's file entirely; edit alpha's file so the reference text is
  # gone (file still exists). Both are now stale, by different mechanisms.
  git -C "$repo" rm -q plugins/zeta/OLD.md
  write_plugin_file "$repo" alpha "OLD.md" "no references here anymore
"
  commit_all "$repo" "remove/rewrite references"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "stale baseline rows must fail the run, got exit $RUN_EXIT (stderr: $RUN_ERR)"

  local zeta_stale alpha_stale
  zeta_stale="$(expected_stale "plugins/zeta/OLD.md" "path" "beta")"
  alpha_stale="$(expected_stale "plugins/alpha/OLD.md" "path" "beta")"
  assert_contains "$RUN_OUT" "$zeta_stale" "stale: deleted-file row is reported"
  assert_contains "$RUN_OUT" "$alpha_stale" "stale: edited-away row is reported"

  local pos_zeta pos_alpha
  pos_zeta="$(line_no <(printf '%s' "$RUN_OUT") "$zeta_stale")"
  pos_alpha="$(line_no <(printf '%s' "$RUN_OUT") "$alpha_stale")"
  if [ -z "$pos_zeta" ] || [ -z "$pos_alpha" ]; then
    record_fail "expected both STALE lines present to check ordering, got: $RUN_OUT"
  else
    [ "$pos_zeta" -lt "$pos_alpha" ] || record_fail "stale entries must appear in baseline order (zeta's row precedes alpha's in the baseline file), got zeta at output line $pos_zeta, alpha at $pos_alpha"
  fi
}

# Comments and blank lines in the baseline are ignored.
test_baseline_comments_and_blank_lines_ignored() {
  local repo
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  write_plugin_file "$repo" alpha "NOTES.md" "plugins/beta/lib/x.sh
"
  commit_all "$repo" "add alpha notes"
  write_baseline "$repo" "$(printf '# a leading comment\n\nplugins/alpha/NOTES.md\tpath\tbeta\n\n# a trailing comment\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "comments/blank lines around a real entry must not error or cause a false stale/new, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
}

# Missing baseline file = empty baseline (not an error).
test_baseline_missing_file_is_treated_as_empty() {
  local repo line l
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  line='plugins/beta/lib/x.sh'
  write_plugin_file "$repo" alpha "NOTES.md" "$line
"
  commit_all "$repo" "add alpha notes"
  rm -f "$repo/scripts/architecture-lint-baseline.txt"
  l="$(line_no "$repo/plugins/alpha/NOTES.md" "$line")"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "missing baseline file must be treated as empty (hit is unexcused NEW), got exit $RUN_EXIT (stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$l" "path" "beta" "$line")" "missing baseline: hit reported as NEW, not errored"
}

# A malformed baseline row (not a comment, blank, or well-formed 3-field
# triple) is exit 2.
test_baseline_malformed_row_is_usage_error() {
  local repo
  repo="$(new_repo)"
  ensure_plugin "$repo" alpha
  write_baseline "$repo" "$(printf 'this-row-has-only-two-fields\tpath\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "a baseline row that is not a well-formed 3-field triple must be exit 2, got $RUN_EXIT (stdout: $RUN_OUT)"
  assert_contains "$RUN_ERR" "this-row-has-only-two-fields" "malformed row: diagnostic names the offending row"
}

# Duplicate hits of the same triple in one file are covered by the one
# baseline entry (line-number-free).
test_baseline_one_entry_covers_all_duplicate_hits_in_a_file() {
  local repo
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  write_plugin_file "$repo" alpha "NOTES.md" "plugins/beta/lib/a.sh
plugins/beta/lib/b.sh
"
  commit_all "$repo" "add alpha notes with two path hits, same triple"
  write_baseline "$repo" "$(printf 'plugins/alpha/NOTES.md\tpath\tbeta\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "one baseline entry must cover both duplicate-triple hits in the same file, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
}

# ===========================================================================
# Clause 7: exit codes (0 clean / 1 new-or-stale / 2 usage-environment),
# summary line with counts, deterministic ordering (path then line).
# ===========================================================================
test_not_a_git_repo_is_exit_2() {
  local plain
  plain="$(mktemp -d)"
  track_tmp "$plain"

  run_lint "$plain"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "outside any git repo: expected exit 2, got $RUN_EXIT"
  [ -n "$RUN_ERR" ] || record_fail "outside any git repo: expected a diagnostic on stderr"
}

test_clean_tree_is_exit_0() {
  local repo
  repo="$(new_repo)"
  ensure_plugin "$repo" alpha

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "a tree with no cross-plugin references should be a clean pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
}

test_summary_line_reports_all_four_categories() {
  local repo
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  ensure_plugin "$repo" alpha

  # baselined: a matched hit
  write_plugin_file "$repo" alpha "A.md" "plugins/beta/lib/a.sh
"
  # pragma-excused: a hit excused on its own line
  write_plugin_file "$repo" alpha "B.md" "plugins/beta/lib/b.sh # architecture-lint: allow deliberate example
"
  # new: an unexcused hit
  write_plugin_file "$repo" alpha "C.md" "plugins/beta/lib/c.sh
"
  commit_all "$repo" "add mixed references"
  # stale: a baseline row naming a path/form/target with zero current hits.
  write_baseline "$repo" "$(printf 'plugins/alpha/A.md\tpath\tbeta\nplugins/ghost/NOPE.md\tpath\tbeta\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "mixed new+stale scenario must fail, got exit $RUN_EXIT (stderr: $RUN_ERR)"

  local summary summary_lc kw
  summary="$(printf '%s\n' "$RUN_OUT" | tail -n1)"
  summary_lc="$(printf '%s' "$summary" | tr '[:upper:]' '[:lower:]')"
  for kw in new stale baselined pragma; do
    case "$summary_lc" in
      *"$kw"*) : ;;
      *) record_fail "summary line must mention '$kw' (with its count), got: $summary" ;;
    esac
  done
  case "$summary" in
    *[0-9]*) : ;;
    *) record_fail "summary line must carry actual counts (expected a digit), got: $summary" ;;
  esac
}

test_deterministic_ordering_by_path_then_line() {
  local repo
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  # zeta sorts after alpha; within alpha's file, put the two hits in
  # descending line order in the source so sort-by-line is actually
  # exercised (not just incidentally already ascending).
  write_plugin_file "$repo" zeta "NOTES.md" "plugins/beta/lib/z.sh
"
  write_plugin_file "$repo" alpha "NOTES.md" "irrelevant line one
plugins/beta/lib/a2.sh
irrelevant line three
plugins/beta/lib/a1.sh
"
  commit_all "$repo" "add alpha and zeta notes"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1 (unbaselined hits), got $RUN_EXIT (stderr: $RUN_ERR)"

  local pos_a2 pos_a1 pos_zeta
  pos_a2="$(line_no <(printf '%s' "$RUN_OUT") "plugins/alpha/NOTES.md:2:")"
  pos_a1="$(line_no <(printf '%s' "$RUN_OUT") "plugins/alpha/NOTES.md:4:")"
  pos_zeta="$(line_no <(printf '%s' "$RUN_OUT") "plugins/zeta/NOTES.md:1:")"

  if [ -z "$pos_a2" ] || [ -z "$pos_a1" ] || [ -z "$pos_zeta" ]; then
    record_fail "expected hits for both alpha lines and the zeta line, got: $RUN_OUT"
    return
  fi
  [ "$pos_a2" -lt "$pos_a1" ] || record_fail "within the same file, line 2's hit must be reported before line 4's (ascending by line), got positions $pos_a2 vs $pos_a1"
  [ "$pos_a1" -lt "$pos_zeta" ] || record_fail "plugins/alpha/... must sort before plugins/zeta/... (ascending by path), got positions $pos_a1 vs $pos_zeta"
}

test_invariant_exit_status_only_0_1_2() {
  local repo ec
  repo="$(new_repo)"
  ensure_plugin "$repo" alpha
  run_lint "$repo"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "clean-tree scenario: exit code $ec not in {0,1,2}" ;; esac

  ensure_plugin "$repo" beta
  write_plugin_file "$repo" alpha "NOTES.md" "plugins/beta/lib/x.sh
"
  commit_all "$repo" "add a reference"
  run_lint "$repo"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "new-hit scenario: exit code $ec not in {0,1,2}" ;; esac

  local plain
  plain="$(mktemp -d)"
  track_tmp "$plain"
  run_lint "$plain"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "non-git-dir scenario: exit code $ec not in {0,1,2}" ;; esac
}

# ===========================================================================
# Clause 8: word-boundary on plugin names -- a plugin name that is a
# substring of another's never matches the longer name's text, in either
# direction (prefix-substring across all four forms, and no-boundary-before
# for the english form).
# ===========================================================================
test_word_boundary_prefix_substring_does_not_leak_to_shorter_name() {
  local repo
  repo="$(new_repo)"
  ensure_plugin "$repo" lego
  ensure_plugin "$repo" lego-extras

  local skill_line='/lego-extras:build'
  local mkt_line='lego-extras@clam'
  local eng_line='the lego-extras plugin'
  local path_line='plugins/lego-extras/lib/x.sh'
  write_plugin_file "$repo" alpha "NOTES.md" "$skill_line
$mkt_line
$eng_line
$path_line
"
  commit_all "$repo" "add alpha notes referencing lego-extras"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1 (4 new hits against lego-extras), got $RUN_EXIT (stderr: $RUN_ERR)"

  assert_contains "$RUN_OUT" "reference to 'lego-extras'" "a genuine reference to lego-extras must be detected"
  assert_not_contains "$RUN_OUT" "reference to 'lego':" "referencing lego-extras must never register as a hit for the shorter name 'lego'"
}

test_word_boundary_before_name_excludes_suffix_match() {
  local repo unbounded_line bounded_line lb
  repo="$(new_repo)"
  ensure_plugin "$repo" lego

  unbounded_line='Our extralego plugin does XYZ.'
  bounded_line='Also see the lego plugin docs.'
  write_plugin_file "$repo" alpha "NOTES.md" "$unbounded_line
$bounded_line
"
  commit_all "$repo" "add alpha notes"
  lb="$(line_no "$repo/plugins/alpha/NOTES.md" "$bounded_line")"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1 (one genuine bounded hit), got $RUN_EXIT (stderr: $RUN_ERR)"

  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$lb" "english" "lego" "$bounded_line")" "a genuinely word-boundaried 'lego plugin' mention must be detected"

  local hit_count
  hit_count="$(printf '%s\n' "$RUN_OUT" | grep -c "reference to 'lego':" || true)"
  [ "$hit_count" -eq 1 ] || record_fail "'extralego plugin' (no word boundary before 'lego') must not also register as a hit -- expected exactly 1 'lego' hit, got $hit_count"
}

# ===========================================================================
# Clause 9: scan scope is EXACTLY tracked files under plugins/*/ -- repo-root
# files (README.md, docs/, scripts/, ARCHITECTURE.md, CLAUDE.md) with blatant
# references are never flagged.
# ===========================================================================
test_scan_scope_excludes_repo_root_docs_and_scripts() {
  local repo blatant
  repo="$(new_repo)"
  ensure_plugin "$repo" alpha
  ensure_plugin "$repo" beta
  blatant='See the beta plugin at plugins/beta/ (beta@clam, /beta:skill).'
  printf '%s\n' "$blatant" >> "$repo/README.md"
  mkdir -p "$repo/docs" "$repo/scripts"
  printf '%s\n' "$blatant" > "$repo/ARCHITECTURE.md"
  printf '%s\n' "$blatant" > "$repo/CLAUDE.md"
  printf '%s\n' "$blatant" > "$repo/docs/notes.md"
  printf '%s\n' "$blatant" > "$repo/scripts/helper.sh"
  commit_all "$repo" "add blatant repo-root references"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "repo-root docs/scripts referencing plugins must never be scanned, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_not_contains "$RUN_OUT" "reference to 'beta'" "no hit should originate from any repo-root file"
}

# ===========================================================================
# Clause 10: a hit line matching multiple forms yields one hit per form.
# ===========================================================================
test_multi_form_single_line_yields_one_hit_per_form() {
  local repo line l
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  line='/beta:skill beta@clam plugins/beta/lib/x.sh'
  write_plugin_file "$repo" alpha "NOTES.md" "$line
"
  commit_all "$repo" "add alpha notes"
  l="$(line_no "$repo/plugins/alpha/NOTES.md" "$line")"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"

  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$l" "skill-invocation" "beta" "$line")" "multi-form line: skill-invocation hit present"
  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$l" "marketplace-id" "beta" "$line")" "multi-form line: marketplace-id hit present"
  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/NOTES.md" "$l" "path" "beta" "$line")" "multi-form line: path hit present"

  local count
  count="$(printf '%s\n' "$RUN_OUT" | grep -c "NEW  plugins/alpha/NOTES.md:$l:" || true)"
  [ "$count" -eq 3 ] || record_fail "one line matching 3 forms must yield exactly 3 separate hit lines, got $count (stdout: $RUN_OUT)"
}

# ===========================================================================
# Fixture-guidance callout: git ls-files drives the scan -- staged-but-
# uncommitted files count, untracked files don't.
# ===========================================================================
test_scan_uses_git_ls_files_staged_counts_untracked_does_not() {
  local repo staged_line l
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  ensure_plugin "$repo" alpha

  staged_line='plugins/beta/lib/staged.sh'
  write_plugin_file "$repo" alpha "STAGED.md" "$staged_line
"
  git -C "$repo" add plugins/alpha/STAGED.md

  write_plugin_file "$repo" alpha "UNTRACKED.md" "plugins/beta/lib/untracked.sh
"
  # deliberately never `git add`ed -- untracked

  l="$(line_no "$repo/plugins/alpha/STAGED.md" "$staged_line")"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1 (the staged hit is unexcused), got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new "plugins/alpha/STAGED.md" "$l" "path" "beta" "$staged_line")" "a staged-but-uncommitted reference must be scanned (git ls-files includes it)"
  assert_not_contains "$RUN_OUT" "UNTRACKED.md" "an untracked file must never be scanned (git ls-files excludes it)"
}

# ===========================================================================
# Edge cases / invariants (bonus coverage beyond the 10 load-bearing clauses).
# ===========================================================================
test_vacuous_empty_plugins_dir_is_clean_pass() {
  local repo
  repo="$(new_repo)"
  # plugins/ exists (from new_repo) but is empty -- no tracked files at all.

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "an empty plugins/ tree must be a clean pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
}

test_invariant_read_only_repo_unchanged() {
  local repo before after
  repo="$(new_repo)"
  ensure_plugin "$repo" beta
  write_plugin_file "$repo" alpha "NOTES.md" "plugins/beta/lib/x.sh
"
  commit_all "$repo" "add alpha notes"
  write_baseline "$repo" "$(printf 'plugins/zeta/GONE.md\tpath\tbeta\n')"

  before="$( (cd "$repo" && find . -type f -exec sha256sum {} + ) | sort)"
  run_lint "$repo"
  after="$( (cd "$repo" && find . -type f -exec sha256sum {} + ) | sort)"

  assert_eq "$before" "$after" "the fixture tree (including the baseline file) must be byte-identical before and after a run"
}

# ===========================================================================
# main
# ===========================================================================

run_test "clause 1: four forms detected with exact path:line/form/target reporting" test_four_forms_detected_with_exact_reporting
run_test "clause 1: english form is case-insensitive on the word 'plugin'" test_english_form_case_insensitive_on_plugin_word

run_test "clause 2: bare plugin name in prose never flags (word-sense)" test_word_sense_bare_name_never_flags

run_test "clause 3: self-reference never flags, any form" test_self_reference_never_flags_any_form

run_test "clause 4: allowlist -- build to the 5 allowlisted plugins is silent" test_allowlist_build_to_allowlisted_targets_silent
run_test "clause 4: build referencing a non-allowlisted plugin flags" test_allowlist_build_referencing_non_allowlisted_target_flags
run_test "clause 4: a non-build plugin referencing landing flags" test_non_build_plugin_referencing_landing_flags

run_test "clause 5: pragma with a non-empty reason excuses the hit" test_pragma_nonempty_reason_excuses_hit
run_test "clause 5: pragma with an empty reason does not excuse and is reported as a defect" test_pragma_empty_reason_does_not_excuse_and_is_reported_as_defect

run_test "clause 6: a baselined (triple-matched) hit passes" test_baseline_matched_hit_passes_counted_not_failed
run_test "clause 6: stale baseline rows fail and preserve baseline order" test_baseline_stale_rows_reported_and_preserve_baseline_order
run_test "clause 6: comments/blank lines in the baseline are ignored" test_baseline_comments_and_blank_lines_ignored
run_test "clause 6: a missing baseline file is treated as empty" test_baseline_missing_file_is_treated_as_empty
run_test "clause 6: a malformed baseline row is a usage error (exit 2)" test_baseline_malformed_row_is_usage_error
run_test "clause 6: one baseline entry covers all duplicate hits in a file" test_baseline_one_entry_covers_all_duplicate_hits_in_a_file

run_test "clause 7: not inside a git repo -> exit 2" test_not_a_git_repo_is_exit_2
run_test "clause 7: a clean tree -> exit 0" test_clean_tree_is_exit_0
run_test "clause 7: summary line reports all four categories" test_summary_line_reports_all_four_categories
run_test "clause 7: deterministic ordering by path then line" test_deterministic_ordering_by_path_then_line
run_test "clause 7: exit status is only ever 0, 1, or 2" test_invariant_exit_status_only_0_1_2

run_test "clause 8: prefix-substring plugin name never leaks to the shorter name" test_word_boundary_prefix_substring_does_not_leak_to_shorter_name
run_test "clause 8: english form requires a word boundary before the name" test_word_boundary_before_name_excludes_suffix_match

run_test "clause 9: repo-root docs/scripts are never scanned" test_scan_scope_excludes_repo_root_docs_and_scripts

run_test "clause 10: one hit per form on a multi-form line" test_multi_form_single_line_yields_one_hit_per_form

run_test "fixture guidance: git ls-files drives the scan (staged counts, untracked doesn't)" test_scan_uses_git_ls_files_staged_counts_untracked_does_not

run_test "edge case: empty plugins/ dir is a clean pass" test_vacuous_empty_plugins_dir_is_clean_pass
run_test "invariant: read-only (fixture tree unchanged)" test_invariant_read_only_repo_unchanged

echo "---"
echo "Passed: $TOTAL_PASS  Failed: $TOTAL_FAIL  Total: $((TOTAL_PASS + TOTAL_FAIL))"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
