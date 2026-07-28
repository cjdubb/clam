#!/usr/bin/env bash
# pr-size-check.test.sh — contract tests for pr-size-check.sh (B01
# pr-size-budget-check, plan 001-lego-pr-sizing-landing-strategy).
#
# Self-contained bash test harness (no bats/shellcheck), mirroring the style
# of worktree_test.sh / realm-gate.test.sh. Black-box only: every test
# builds a throwaway git repository under mktemp, invokes pr-size-check.sh
# through its public CLI (positional diff-range, --budget, --justified,
# "-- <pathspec>...", $LEGO_CONFIG), and asserts on its real exit code and
# stdout/stderr — never on the script's internals.
#
# Several tests compute an expected total independently, via a small awk
# oracle over `git diff --numstat` that mirrors the contract's own
# "additions + deletions over text rows, binary rows contribute 0" rule
# (see expected_total below). This grounds assertions in real git behavior
# instead of hand-guessed numbers.
#
# Run directly: `bash pr-size-check.test.sh`. Exits 0 when every test
# passes, 1 when any test fails.
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-size-check.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: script under test not found at $SCRIPT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Cleanup registry (see worktree_test.sh for rationale: command substitution
# forks a subshell, so a file-based manifest is needed to survive it).
# ---------------------------------------------------------------------------
CLEANUP_MANIFEST="$(mktemp)"

track_tmp() {
  printf '%s\n' "$1" >> "$CLEANUP_MANIFEST"
}

cleanup() {
  if [ -f "$CLEANUP_MANIFEST" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] && [ -e "$d" ] && rm -rf -- "$d"
    done < "$CLEANUP_MANIFEST"
    rm -f -- "$CLEANUP_MANIFEST"
  fi
}
trap cleanup EXIT

# Neutralize any global core.hooksPath the ambient environment might set, so
# fixture commits never trigger unrelated repo hooks.
NOOP_HOOKS_DIR="$(mktemp -d)"
track_tmp "$NOOP_HOOKS_DIR"

# ---------------------------------------------------------------------------
# Minimal test harness: named tests, per-test assertion failures, summary.
# ---------------------------------------------------------------------------
CURRENT_TEST=""
CURRENT_FAILURES=0
TOTAL_PASS=0
TOTAL_FAIL=0

start_test() {
  CURRENT_TEST="$1"
  CURRENT_FAILURES=0
}

record_fail() {
  CURRENT_FAILURES=$((CURRENT_FAILURES + 1))
  printf '    FAIL: %s\n' "$1"
}

end_test() {
  if [ "$CURRENT_FAILURES" -eq 0 ]; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
    echo "ok - $CURRENT_TEST"
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    echo "not ok - $CURRENT_TEST ($CURRENT_FAILURES failing assertion(s))"
  fi
}

run_test() {
  local name="$1"
  shift
  start_test "$name"
  "$@"
  end_test
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" != "$actual" ]; then
    record_fail "$label: expected [$expected] got [$actual]"
  fi
}

# ---------------------------------------------------------------------------
# Invocation helper: run_cmd <dir> <path-or-empty> <lego-config-or-empty>
# <args...> — runs pr-size-check.sh with cwd <dir>, optionally overriding
# PATH (used to exercise the no-jq path) and/or $LEGO_CONFIG (the
# contract's override-path redirection seam). Sets RUN_OUT / RUN_ERR /
# RUN_EXIT / RUN_OUT_LINES.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
RUN_OUT_LINES=0

run_cmd() {
  local dir="$1" pth="$2" cfg="$3"
  shift 3
  local usepath="$pth"
  [ -n "$usepath" ] || usepath="$PATH"
  local out err ec
  out="$(mktemp)"
  err="$(mktemp)"
  if [ -n "$cfg" ]; then
    ( cd "$dir" && PATH="$usepath" LEGO_CONFIG="$cfg" bash "$SCRIPT" "$@" ) >"$out" 2>"$err"
  else
    ( cd "$dir" && PATH="$usepath" bash "$SCRIPT" "$@" ) >"$out" 2>"$err"
  fi
  ec=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  RUN_EXIT=$ec
  if [ -s "$out" ]; then
    RUN_OUT_LINES="$(grep -c '' "$out")"
  else
    RUN_OUT_LINES=0
  fi
  rm -f "$out" "$err"
}

# run_in <dir> <args...>  (default PATH, default $LEGO_CONFIG)
run_in() {
  local dir="$1"
  shift
  run_cmd "$dir" "" "" "$@"
}

# path_without <exe-name> -- prints a dir containing symlinks to every
# executable currently resolvable on $PATH except <exe-name>.
path_without() {
  local exclude="$1"
  local dir p b name
  dir="$(mktemp -d)"
  track_tmp "$dir"
  local parts
  IFS=':' read -ra parts <<< "$PATH"
  for p in "${parts[@]}"; do
    [ -n "$p" ] && [ -d "$p" ] || continue
    for b in "$p"/*; do
      [ -e "$b" ] || continue
      name="$(basename "$b")"
      [ "$name" = "$exclude" ] && continue
      [ -e "$dir/$name" ] && continue
      ln -s "$b" "$dir/$name" 2>/dev/null || true
    done
  done
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# Fixture helpers.
# ---------------------------------------------------------------------------

# new_git_repo -- a fresh repo at <container>/repo, branch "master", one
# commit (README.md). Nested inside a unique tracked container so cleanup
# owns the whole thing.
new_git_repo() {
  local container repo
  container="$(mktemp -d)"
  track_tmp "$container"
  repo="$container/repo"
  mkdir -p "$repo"
  git init -q -b master "$repo" >/dev/null
  git -C "$repo" config user.email "lego-fixture@example.com"
  git -C "$repo" config user.name "Lego Fixture"
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" config core.hooksPath "$NOOP_HOOKS_DIR"
  # .local/ is gitignored in production (lego's plan skill excludes it via
  # .git/info/exclude); mirror that here so an uncommitted .local/config.json
  # fixture never shows up in `git status --porcelain`, which the read-only
  # invariant tests rely on being empty when nothing else changed.
  printf '%s\n' '.local/' >> "$repo/.git/info/exclude"
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial commit"
  printf '%s' "$repo"
}

# commit_file <repo> <relpath> <content> <message> -- writes <content>
# verbatim (no extra trailing newline added beyond what's passed) and
# commits it.
commit_file() {
  local repo="$1" rel="$2" content="$3" msg="$4"
  mkdir -p "$(dirname "$repo/$rel")"
  printf '%s' "$content" > "$repo/$rel"
  git -C "$repo" add -- "$rel"
  git -C "$repo" commit -q -m "$msg"
}

# n_lines <n> -- prints <n> newline-terminated lines ("1\n2\n...\nN\n").
n_lines() {
  seq 1 "$1"
}

# write_base_config <repo> <json-content> -- writes and commits
# .claude/lego.json (the committed base layer of the layered config).
write_base_config() {
  local repo="$1" content="$2"
  mkdir -p "$repo/.claude"
  printf '%s' "$content" > "$repo/.claude/lego.json"
  git -C "$repo" add .claude/lego.json
  git -C "$repo" commit -q -m "add base lego.json"
}

# write_override_config <repo> <json-content> -- writes .local/config.json
# (the gitignored default override path) verbatim, uncommitted.
write_override_config() {
  local repo="$1" content="$2"
  mkdir -p "$repo/.local"
  printf '%s' "$content" > "$repo/.local/config.json"
}

# write_json_at <repo> <relpath> <json-content> -- writes arbitrary JSON at
# an arbitrary relpath, uncommitted (used for $LEGO_CONFIG redirection
# fixtures, where the override lives somewhere other than the default
# .local/config.json).
write_json_at() {
  local repo="$1" rel="$2" content="$3"
  mkdir -p "$(dirname "$repo/$rel")"
  printf '%s' "$content" > "$repo/$rel"
}

# budget_json <n> -- {"delivery":{"prSizeBudget": <n>}} (the shape shown in
# docs/config-schema.md for delivery.* fields).
budget_json() {
  printf '{"delivery":{"prSizeBudget": %s}}' "$1"
}

# ---------------------------------------------------------------------------
# Oracle helpers: compute expected values straight from real git output,
# mirroring the contract's own measurement rule, so assertions are grounded
# in actual git behavior rather than hand-guessed numbers.
# ---------------------------------------------------------------------------

# expected_total <repo> <range> [-- <pathspec>...] -- additions + deletions
# summed over non-binary numstat rows (Behavior step 3 / Invariant: <total>
# is additions+deletions over text files).
expected_total() {
  local repo="$1"
  shift
  git -C "$repo" diff --numstat "$@" 2>/dev/null | awk '
    $1 == "-" || $2 == "-" { next }
    { sum += $1 + $2 }
    END { print sum + 0 }
  '
}

# expected_binary_paths <repo> <range> -- newline-separated list of paths
# whose numstat row is "-\t-\t<path>" (binary rows).
expected_binary_paths() {
  local repo="$1"
  shift
  git -C "$repo" diff --numstat "$@" 2>/dev/null | awk -F'\t' '$1 == "-" && $2 == "-" { print $3 }'
}

# git_stderr_for <repo> <args-to-git-diff-numstat...> -- git's own stderr
# for the equivalent `git diff --numstat` invocation. Used to assert the
# script's diagnostic surfaces git's real error text (the "git's own error
# text is what surfaces" invariant) without hardcoding wording that could
# drift across git versions.
git_stderr_for() {
  local repo="$1"
  shift
  ( cd "$repo" && git diff --numstat "$@" ) 2>&1 >/dev/null
}

# ===========================================================================
# Usage / argument errors (Errors clause 1; Edge cases EC7, EC11)
# ===========================================================================

# No positional, more than one positional: usage line on stderr, exit 2.
test_usage_no_positional_or_extra_positional() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "no args: expected exit 2, got $RUN_EXIT"
  [ -z "$RUN_OUT" ] || record_fail "no args: expected no stdout on a usage error, got: $RUN_OUT"
  [ -n "$RUN_ERR" ] || record_fail "no args: expected a usage diagnostic on stderr"

  run_in "$repo" --justified
  [ "$RUN_EXIT" -eq 2 ] || record_fail "only flags, no positional: expected exit 2, got $RUN_EXIT"

  run_in "$repo" HEAD..HEAD extra-positional
  [ "$RUN_EXIT" -eq 2 ] || record_fail "two positionals with no --: expected exit 2, got $RUN_EXIT"
}

# Unknown flag: usage line on stderr, exit 2.
test_usage_unknown_flag() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" --frobnicate HEAD..HEAD
  [ "$RUN_EXIT" -eq 2 ] || record_fail "unknown flag before positional: expected exit 2, got $RUN_EXIT"

  run_in "$repo" HEAD..HEAD --frobnicate
  [ "$RUN_EXIT" -eq 2 ] || record_fail "unknown flag after positional: expected exit 2, got $RUN_EXIT"
}

# --budget with no value, and --budget with a non-integer or non-positive
# value (Errors clause), including the explicit 0 edge case (EC7).
test_usage_budget_missing_or_invalid_value() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" --budget
  [ "$RUN_EXIT" -eq 2 ] || record_fail "--budget with nothing after it: expected exit 2, got $RUN_EXIT"

  run_in "$repo" --budget HEAD..HEAD
  [ "$RUN_EXIT" -eq 2 ] || record_fail "--budget as the last flag, positional consumed as its value: expected exit 2, got $RUN_EXIT"

  local bad
  for bad in abc 5.5 -5; do
    run_in "$repo" --budget "$bad" HEAD..HEAD
    [ "$RUN_EXIT" -eq 2 ] || record_fail "--budget $bad: expected exit 2, got $RUN_EXIT"
  done
}

# EC7: --budget 0 is a usage error, not "everything fails" — a zero budget
# would fail every non-empty range, so it is rejected outright.
test_usage_budget_zero_is_error() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" --budget 0 HEAD..HEAD
  [ "$RUN_EXIT" -eq 2 ] || record_fail "--budget 0: expected exit 2, got $RUN_EXIT"
}

# EC11: "--" with no pathspecs after it is a usage error, distinct from
# "--" followed by a pathspec matching nothing (tested separately as PASS).
test_double_dash_no_pathspecs_is_usage_error() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" HEAD..HEAD --
  [ "$RUN_EXIT" -eq 2 ] || record_fail "-- with no pathspecs after it: expected exit 2, got $RUN_EXIT"
}

# ===========================================================================
# Environment errors (Errors clauses 2-3; Invariant: git's own error text
# surfaces, never rewritten)
# ===========================================================================

test_not_a_git_repo() {
  local dir
  dir="$(mktemp -d)"
  track_tmp "$dir"

  run_in "$dir" HEAD..HEAD
  [ "$RUN_EXIT" -eq 2 ] || record_fail "outside any git repo: expected exit 2, got $RUN_EXIT"
  [ -n "$RUN_ERR" ] || record_fail "outside any git repo: expected a diagnostic on stderr"
  [ -z "$RUN_OUT" ] || record_fail "outside any git repo: expected no stdout, got: $RUN_OUT"
}

# git diff --numstat failing for the given range (bad revision / ambiguous
# argument): diagnostic naming the range, exit 2 -- and per the Invariant
# clause, git's own error text (not a rewritten message) is what surfaces.
# Grounded via git_stderr_for rather than a hardcoded git error string.
test_bad_revision_diagnostic_surfaces_gits_own_text() {
  local repo range raw_err first_git_line
  repo="$(new_git_repo)"
  range="definitely-not-a-real-ref..HEAD"

  raw_err="$(git_stderr_for "$repo" "$range")"
  if [ -z "$raw_err" ]; then
    record_fail "fixture bug: expected git itself to error on range '$range', got no stderr"
    return
  fi
  first_git_line="$(printf '%s\n' "$raw_err" | head -n1)"

  run_in "$repo" "$range"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "bad revision: expected exit 2, got $RUN_EXIT (stderr: $RUN_ERR)"
  case "$RUN_ERR" in
    *"$range"*) : ;;
    *) record_fail "bad revision: diagnostic does not name the range '$range' (stderr: $RUN_ERR)" ;;
  esac
  case "$RUN_ERR" in
    *"$first_git_line"*) : ;;
    *) record_fail "bad revision: diagnostic does not surface git's own error text (expected substring: [$first_git_line], got: $RUN_ERR)" ;;
  esac
}

# ===========================================================================
# Config errors (Errors clauses 4-6)
# ===========================================================================

# A config file that exists but is not valid JSON: diagnostic naming the
# file, exit 2 -- for both the base and the override layer independently.
test_config_invalid_json_base_and_override() {
  local repo
  repo="$(new_git_repo)"
  write_base_config "$repo" '{not valid json'

  run_in "$repo" HEAD..HEAD
  [ "$RUN_EXIT" -eq 2 ] || record_fail "invalid JSON in base .claude/lego.json: expected exit 2, got $RUN_EXIT"
  case "$RUN_ERR" in
    *lego.json*) : ;;
    *) record_fail "invalid JSON in base: diagnostic does not name the file (stderr: $RUN_ERR)" ;;
  esac

  local repo2
  repo2="$(new_git_repo)"
  write_override_config "$repo2" '{not valid json'

  run_in "$repo2" HEAD..HEAD
  [ "$RUN_EXIT" -eq 2 ] || record_fail "invalid JSON in override .local/config.json: expected exit 2, got $RUN_EXIT"
  case "$RUN_ERR" in
    *config.json*) : ;;
    *) record_fail "invalid JSON in override: diagnostic does not name the file (stderr: $RUN_ERR)" ;;
  esac
}

# .delivery.prSizeBudget present but not a positive integer: diagnostic on
# stderr, exit 2 -- string, zero, negative, and non-integer values.
test_config_pr_size_budget_not_positive_integer() {
  local repo bad
  for bad in '"abc"' '0' '-5' '3.5'; do
    repo="$(new_git_repo)"
    write_override_config "$repo" "$(printf '{"delivery":{"prSizeBudget": %s}}' "$bad")"

    run_in "$repo" HEAD..HEAD
    [ "$RUN_EXIT" -eq 2 ] || record_fail "prSizeBudget=$bad: expected exit 2, got $RUN_EXIT"
    [ -n "$RUN_ERR" ] || record_fail "prSizeBudget=$bad: expected a diagnostic on stderr"
  done
}

# jq needed (config-sourced budget, at least one config file present, no
# --budget) but not installed: diagnostic on stderr, exit 2.
test_jq_required_when_config_budget_needed_but_absent() {
  local repo path_no_jq
  repo="$(new_git_repo)"
  write_base_config "$repo" "$(budget_json 50)"
  path_no_jq="$(path_without jq)"

  run_cmd "$repo" "$path_no_jq" "" HEAD..HEAD
  [ "$RUN_EXIT" -eq 2 ] || record_fail "config present, no --budget, jq absent: expected exit 2, got $RUN_EXIT"
  case "$RUN_ERR" in
    *jq*|*JQ*) : ;;
    *) record_fail "jq absent: diagnostic does not mention jq (stderr: $RUN_ERR)" ;;
  esac
}

# ===========================================================================
# Budget resolution (Behavior clause 2; Inputs; Edge cases EC6, EC8, EC9)
# ===========================================================================

# --budget wins over any config value, config is never read, and jq is not
# needed on this path (a repo with no jq still works when --budget is
# given, even with a config file present that would otherwise require it).
test_budget_flag_wins_and_config_never_read_and_no_jq_needed() {
  local repo path_no_jq head0 head1 t
  repo="$(new_git_repo)"
  write_base_config "$repo" "$(budget_json 1)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 5)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t="$(expected_total "$repo" "$head0..$head1")"
  path_no_jq="$(path_without jq)"

  run_cmd "$repo" "$path_no_jq" "" --budget 1000 "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "--budget 1000 over a config budget of 1, jq absent: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  $t lines changed (budget 1000)" "$RUN_OUT" "--budget wins: summary reflects the flag's value, not the config's"
}

# Merged config, base only: .claude/lego.json alone resolves the budget.
test_budget_from_merged_config_base_only() {
  local repo head0 head1 t
  repo="$(new_git_repo)"
  write_base_config "$repo" "$(budget_json 100)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 5)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t="$(expected_total "$repo" "$head0..$head1")"

  run_in "$repo" "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "base-only config: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  $t lines changed (budget 100)" "$RUN_OUT" "base-only config: budget resolved from .claude/lego.json"
}

# Merged config, override only: .local/config.json alone (no base file at
# all) resolves the budget.
test_budget_from_merged_config_override_only() {
  local repo head0 head1 t
  repo="$(new_git_repo)"
  write_override_config "$repo" "$(budget_json 100)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 5)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t="$(expected_total "$repo" "$head0..$head1")"

  run_in "$repo" "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "override-only config: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  $t lines changed (budget 100)" "$RUN_OUT" "override-only config: budget resolved from .local/config.json"
}

# Merged config, both present: override wins per key (jq recursive merge
# .[0] * .[1], base first then override).
test_budget_from_merged_config_override_wins_over_base() {
  local repo head0 head1 t first_line
  repo="$(new_git_repo)"
  write_base_config "$repo" "$(budget_json 100)"
  write_override_config "$repo" "$(budget_json 5)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 8)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t="$(expected_total "$repo" "$head0..$head1")"

  run_in "$repo" "$head0..$head1"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "override wins over base: expected exit 1 (over the override's budget of 5), got $RUN_EXIT (stderr: $RUN_ERR)"
  first_line="$(printf '%s\n' "$RUN_OUT" | head -n1)"
  assert_eq "FAIL  $t lines changed, over budget 5 by $((t - 5))" "$first_line" "override wins over base: FAIL summary reflects the override's budget (5), not the base's (100)"
}

# $LEGO_CONFIG redirects the override file's path (default .local/config.json)
# -- a real .local/config.json is present with a different value, but must
# be ignored once $LEGO_CONFIG points elsewhere.
test_lego_config_env_redirects_override_path() {
  local repo head0 head1 t
  repo="$(new_git_repo)"
  write_override_config "$repo" "$(budget_json 999)"
  write_json_at "$repo" "custom/dir/myconfig.json" "$(budget_json 7)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 5)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t="$(expected_total "$repo" "$head0..$head1")"

  run_cmd "$repo" "" "custom/dir/myconfig.json" "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "LEGO_CONFIG redirect: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  $t lines changed (budget 7)" "$RUN_OUT" "LEGO_CONFIG points at custom/dir/myconfig.json (budget 7), not the default .local/config.json (budget 999)"
}

# EC8/EC9: neither config file exists and no --budget -- the 500 default
# applies without error and without needing jq.
test_default_budget_500_when_no_config_no_flag_and_no_jq_needed() {
  local repo head0 head1 path_no_jq
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/exact500.txt" "$(n_lines 500)" "add exactly 500 lines"
  head1="$(git -C "$repo" rev-parse HEAD)"
  path_no_jq="$(path_without jq)"

  run_cmd "$repo" "$path_no_jq" "" "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "500 lines, default budget, no jq: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  500 lines changed (budget 500)" "$RUN_OUT" "default budget is exactly 500 (inclusive boundary)"

  # One line over the default budget: FAIL by 1.
  local head2
  commit_file "$repo" "src/exact500.txt" "$(n_lines 501)" "grow to 501 lines"
  head2="$(git -C "$repo" rev-parse HEAD)"
  run_cmd "$repo" "$path_no_jq" "" "$head0..$head2"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "501 lines vs default 500: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  case "$RUN_OUT" in
    "FAIL  501 lines changed, over budget 500 by 1"*) : ;;
    *) record_fail "501 lines vs default 500: expected a FAIL summary over by 1, got: $RUN_OUT" ;;
  esac
}

# ===========================================================================
# Measurement & summary/breakdown formats
# (Behavior clauses 3-4; Outputs; Invariants; Edge cases EC1-EC5)
# ===========================================================================

# A breakdown line must start with exactly two leading spaces (Outputs: "two
# leading spaces") -- neither one nor three.
assert_two_leading_spaces() {
  local line="$1" label="$2"
  case "$line" in
    '  '*) : ;;
    *) record_fail "$label: expected line to start with exactly two leading spaces, got: [$line]"; return ;;
  esac
  case "$line" in
    '   '*) record_fail "$label: expected exactly two leading spaces (found a third), got: [$line]" ;;
  esac
}

# A breakdown line must contain the changed-line count before the path
# (Outputs: "changed-line count and path"). Deliberately does not pin the
# separator between them -- the contract specifies the leading spaces and
# the field order, not the internal spacing.
assert_line_has_count_then_path() {
  local line="$1" count="$2" path="$3" label="$4"
  case "$line" in
    *"$count"*"$path"*) : ;;
    *) record_fail "$label: expected line to contain count [$count] before path [$path], got: $line" ;;
  esac
}

# line_number_of <text> <needle> -- 1-indexed line number of the first line
# of <text> containing <needle>, or empty if none.
line_number_of() {
  printf '%s\n' "$1" | grep -n -F -- "$2" | head -n1 | cut -d: -f1
}

test_measurement_basic_pass_and_fail_and_exit_codes() {
  local repo head0 head1 head2 t1 t2 budget delta first_line
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 4)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t1="$(expected_total "$repo" "$head0..$head1")"

  run_in "$repo" --budget 10 "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "within budget: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  $t1 lines changed (budget 10)" "$RUN_OUT" "within budget: exact single-line summary"
  [ "$RUN_OUT_LINES" -eq 1 ] || record_fail "within budget: expected exactly 1 stdout line, got $RUN_OUT_LINES"

  commit_file "$repo" "src/small.txt" "$(n_lines 20)" "rewrite small.txt"
  head2="$(git -C "$repo" rev-parse HEAD)"
  t2="$(expected_total "$repo" "$head1..$head2")"
  budget=$((t2 - 1))
  delta=1

  run_in "$repo" --budget "$budget" "$head1..$head2"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "over budget: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  first_line="$(printf '%s\n' "$RUN_OUT" | head -n1)"
  assert_eq "FAIL  $t2 lines changed, over budget $budget by $delta" "$first_line" "over budget: exact FAIL summary line"
  [ "$RUN_OUT_LINES" -eq 2 ] || record_fail "over budget, single file changed: expected summary + 1 breakdown line, got $RUN_OUT_LINES lines (stdout: $RUN_OUT)"
  local breakdown_line
  breakdown_line="$(printf '%s\n' "$RUN_OUT" | sed -n '2p')"
  assert_two_leading_spaces "$breakdown_line" "over budget breakdown line"
  assert_line_has_count_then_path "$breakdown_line" "$t2" "src/small.txt" "over budget breakdown line"
}

# EC1: a range with no changes at all.
test_empty_range_pass_zero() {
  local repo head0
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" --budget 500 "$head0..$head0"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "empty range: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  0 lines changed (budget 500)" "$RUN_OUT" "empty range: exact summary"
  [ "$RUN_OUT_LINES" -eq 1 ] || record_fail "empty range: expected exactly 1 stdout line, got $RUN_OUT_LINES"
}

# EC2: total exactly equal to the budget is within budget (inclusive), not
# over. Paired with budget-1 to prove the boundary is actually exercised.
test_total_equal_to_budget_is_pass_inclusive() {
  local repo head0 head1 t
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 6)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t="$(expected_total "$repo" "$head0..$head1")"
  if [ "$t" -ne 6 ]; then
    record_fail "fixture bug: expected a fresh 6-line file to measure 6, got $t"
    return
  fi

  run_in "$repo" --budget "$t" "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "total == budget: expected exit 0 (inclusive), got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  $t lines changed (budget $t)" "$RUN_OUT" "total == budget: exact PASS summary"

  run_in "$repo" --budget "$((t - 1))" "$head0..$head1"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "sanity: total == budget+1 should FAIL, expected exit 1, got $RUN_EXIT"
}

# EC3: a pure deletion range counts its deletions toward the total, so a
# large deletion-only range can exceed the budget.
test_deletion_only_range_can_exceed_budget() {
  local repo head0 head1 head2 t first_line
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/big.txt" "$(n_lines 20)" "add big.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" rm -q src/big.txt
  git -C "$repo" commit -q -m "remove big.txt"
  head2="$(git -C "$repo" rev-parse HEAD)"
  t="$(expected_total "$repo" "$head1..$head2")"
  if [ "$t" -ne 20 ]; then
    record_fail "fixture bug: expected deleting a 20-line file to measure 20, got $t"
    return
  fi

  run_in "$repo" --budget 15 "$head1..$head2"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "deletion-only over budget: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  first_line="$(printf '%s\n' "$RUN_OUT" | head -n1)"
  assert_eq "FAIL  20 lines changed, over budget 15 by 5" "$first_line" "deletion-only: exact FAIL summary (deletions count toward total)"
}

# EC4: a binary-only change measures 0 counted lines (PASS), but the binary
# file is still listed -- the binary listing is not gated on being over
# budget, unlike the count/path breakdown.
test_binary_only_change_pass_with_binary_listed() {
  local repo head0 head1
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  mkdir -p "$repo/src"
  printf '\x00\x01BINARYDATA' > "$repo/src/asset.bin"
  git -C "$repo" add src/asset.bin
  git -C "$repo" commit -q -m "add binary asset"
  head1="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" --budget 5 "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "binary-only: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ "$RUN_OUT_LINES" -eq 2 ] || record_fail "binary-only: expected summary + 1 binary line, got $RUN_OUT_LINES lines (stdout: $RUN_OUT)"
  local first second
  first="$(printf '%s\n' "$RUN_OUT" | sed -n '1p')"
  second="$(printf '%s\n' "$RUN_OUT" | sed -n '2p')"
  assert_eq "PASS  0 lines changed (budget 5)" "$first" "binary-only: 0 counted lines, PASS"
  assert_eq "  binary  src/asset.bin" "$second" "binary-only: exact binary breakdown line"
}

# EC4 (mixed): a within-budget change with both a binary file and a small
# text change -- the binary is listed, but the count/path breakdown (which
# is gated on "when over budget") does not appear for the text file.
test_binary_and_text_mixed_within_budget_only_binary_listed() {
  local repo head0 head1 t
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  mkdir -p "$repo/src"
  printf '%s' "$(n_lines 3)" > "$repo/src/small.txt"
  printf '\x00\x01BINARYDATA' > "$repo/src/asset.bin"
  git -C "$repo" add src/small.txt src/asset.bin
  git -C "$repo" commit -q -m "add small text + binary"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t="$(expected_total "$repo" "$head0..$head1")"
  if [ "$t" -ne 3 ]; then
    record_fail "fixture bug: expected the binary to contribute 0 and the text file to contribute 3, got total $t"
    return
  fi

  run_in "$repo" --budget 10 "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "mixed within budget: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ "$RUN_OUT_LINES" -eq 2 ] || record_fail "mixed within budget: expected summary + 1 binary line only, got $RUN_OUT_LINES lines (stdout: $RUN_OUT)"
  case "$RUN_OUT" in
    *small.txt*) record_fail "mixed within budget: the within-budget text file must not appear in a count/path breakdown line (stdout: $RUN_OUT)" ;;
  esac
  case "$RUN_OUT" in
    *"  binary  src/asset.bin"*) : ;;
    *) record_fail "mixed within budget: expected the binary breakdown line, got: $RUN_OUT" ;;
  esac
}

# EC5: a pure rename with no content change contributes 0 lines.
test_pure_rename_contributes_zero_lines() {
  local repo head1 head2
  repo="$(new_git_repo)"
  commit_file "$repo" "src/orig.txt" "$(n_lines 5)" "add orig.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" mv src/orig.txt src/renamed.txt
  git -C "$repo" commit -q -m "rename orig.txt to renamed.txt"
  head2="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" --budget 5 "$head1..$head2"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "pure rename: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  0 lines changed (budget 5)" "$RUN_OUT" "pure rename: contributes 0 lines, single-line summary"
  [ "$RUN_OUT_LINES" -eq 1 ] || record_fail "pure rename: expected exactly 1 stdout line (no breakdown), got $RUN_OUT_LINES"
}

# EC10: more than 10 changed files while over budget -- the 10 largest by
# count are listed (ties broken by path ascending), then a remainder line.
# Deliberately constructed with an exact tie inside the visible top 10
# (fileA/fileB both at count 12) so the tie-break is actually exercised.
test_breakdown_over_ten_files_sorted_and_remainder() {
  local repo head0 head1 t
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  mkdir -p "$repo/many"
  local names=(file01 file02 file03 file04 file05 file06 file07 file08 fileA fileB file09 file10)
  local counts=(20 19 18 17 16 15 14 13 12 12 5 3)
  local i
  for i in "${!names[@]}"; do
    printf '%s' "$(n_lines "${counts[$i]}")" > "$repo/many/${names[$i]}.txt"
  done
  git -C "$repo" add many
  git -C "$repo" commit -q -m "add 12 files of varying size"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t="$(expected_total "$repo" "$head0..$head1")"
  if [ "$t" -ne 164 ]; then
    record_fail "fixture bug: expected the 12 fresh files to total 164 lines, got $t"
    return
  fi

  run_in "$repo" --budget 10 "$head0..$head1"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "12 files over budget: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  local first_line
  first_line="$(printf '%s\n' "$RUN_OUT" | head -n1)"
  assert_eq "FAIL  164 lines changed, over budget 10 by 154" "$first_line" "12 files over budget: exact FAIL summary"
  [ "$RUN_OUT_LINES" -eq 12 ] || record_fail "12 files over budget: expected summary + 10 entries + 1 remainder line = 12, got $RUN_OUT_LINES lines (stdout: $RUN_OUT)"

  local n ln_prev=0 ln_cur path_prev=""
  for n in file01 file02 file03 file04 file05 file06 file07 file08 fileA fileB; do
    ln_cur="$(line_number_of "$RUN_OUT" "many/$n.txt")"
    if [ -z "$ln_cur" ]; then
      record_fail "12 files over budget: expected many/$n.txt in the top-10 breakdown, but it is missing"
      continue
    fi
    if [ "$ln_prev" -ne 0 ] && [ "$ln_cur" -le "$ln_prev" ]; then
      record_fail "12 files over budget: many/$n.txt (line $ln_cur) does not follow $path_prev (line $ln_prev) -- sort order (count desc, path asc on ties) violated"
    fi
    ln_prev="$ln_cur"
    path_prev="many/$n.txt"
  done

  case "$RUN_OUT" in
    *file09.txt*|*file10.txt*)
      record_fail "12 files over budget: the two smallest files (file09.txt count 5, file10.txt count 3) must be summarized, not individually listed (stdout: $RUN_OUT)" ;;
  esac

  local last_line
  last_line="$(printf '%s\n' "$RUN_OUT" | tail -n1)"
  assert_eq "  ... and 2 more files" "$last_line" "12 files over budget: exact remainder line"

  local file01_line
  file01_line="$(printf '%s\n' "$RUN_OUT" | sed -n "$(line_number_of "$RUN_OUT" "many/file01.txt")p")"
  assert_two_leading_spaces "$file01_line" "top-10 breakdown line"
  assert_line_has_count_then_path "$file01_line" "20" "many/file01.txt" "top-10 breakdown line"
}

# ===========================================================================
# --justified (Inputs; Behavior/Invariant: changes only exit + label;
# Edge case EC9: inert when within budget)
# ===========================================================================

test_justified_changes_only_exit_and_label() {
  local repo head0 head1 t budget delta out_fail out_warn ec_fail ec_warn
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 8)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t="$(expected_total "$repo" "$head0..$head1")"
  budget=$((t - 3))
  delta=3

  run_in "$repo" --budget "$budget" "$head0..$head1"
  out_fail="$RUN_OUT"; ec_fail="$RUN_EXIT"
  run_in "$repo" --budget "$budget" --justified "$head0..$head1"
  out_warn="$RUN_OUT"; ec_warn="$RUN_EXIT"

  [ "$ec_fail" -eq 1 ] || record_fail "without --justified: expected exit 1, got $ec_fail"
  [ "$ec_warn" -eq 0 ] || record_fail "with --justified: expected exit 0, got $ec_warn"

  local first_fail first_warn
  first_fail="$(printf '%s\n' "$out_fail" | head -n1)"
  first_warn="$(printf '%s\n' "$out_warn" | head -n1)"
  assert_eq "FAIL  $t lines changed, over budget $budget by $delta" "$first_fail" "--justified: FAIL summary without the flag"
  assert_eq "WARN  $t lines changed, over budget $budget by $delta — justified" "$first_warn" "--justified: WARN summary with the flag"

  local rest_fail rest_warn
  rest_fail="$(printf '%s\n' "$out_fail" | tail -n +2)"
  rest_warn="$(printf '%s\n' "$out_warn" | tail -n +2)"
  assert_eq "$rest_fail" "$rest_warn" "--justified: breakdown is byte-identical with and without the flag"
}

# EC9: --justified on a within-budget range is inert -- plain PASS, no
# suffix, output byte-identical to omitting the flag.
test_justified_inert_when_within_budget() {
  local repo head0 head1 out1 out2
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 3)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" --budget 100 "$head0..$head1"
  out1="$RUN_OUT"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "without --justified, within budget: expected exit 0, got $RUN_EXIT"

  run_in "$repo" --budget 100 --justified "$head0..$head1"
  out2="$RUN_OUT"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "with --justified, within budget: expected exit 0, got $RUN_EXIT"

  assert_eq "PASS  3 lines changed (budget 100)" "$out1" "within budget, no --justified: exact PASS summary"
  assert_eq "$out1" "$out2" "--justified is inert on a within-budget range (byte-identical output)"
}

# ===========================================================================
# "-- <pathspec>..." passthrough (Inputs; Invariants; Edge cases EC11-EC12)
# ===========================================================================

# A pathspec-scoped run measures exactly the files matched -- the same total
# the caller would get from git diff with the same arguments (checked here
# against the real, unfiltered total to prove it is actually scoped, not
# coincidentally equal).
test_pathspec_scoped_measurement_matches_git_exactly() {
  local repo head0 head1 t_full t_scoped
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  mkdir -p "$repo/src"
  printf '%s' "$(n_lines 4)" > "$repo/src/a.txt"
  printf '%s' "$(n_lines 6)" > "$repo/src/b.txt"
  git -C "$repo" add src/a.txt src/b.txt
  git -C "$repo" commit -q -m "add a.txt and b.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  t_full="$(expected_total "$repo" "$head0..$head1")"
  t_scoped="$(expected_total "$repo" "$head0..$head1" -- src/a.txt)"
  if [ "$t_full" -eq "$t_scoped" ]; then
    record_fail "fixture bug: expected the pathspec-scoped total to differ from the full-range total"
    return
  fi

  run_in "$repo" --budget 100 "$head0..$head1" -- src/a.txt
  [ "$RUN_EXIT" -eq 0 ] || record_fail "pathspec-scoped: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  $t_scoped lines changed (budget 100)" "$RUN_OUT" "pathspec-scoped: total matches git diff with the same pathspec, not the full range"

  run_in "$repo" --budget 100 "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "unscoped: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  $t_full lines changed (budget 100)" "$RUN_OUT" "unscoped: total covers both files"
}

# EC12: a pathspec matching nothing in the range is not an error -- 0 lines,
# PASS, the same way git itself treats a non-matching pathspec.
test_pathspec_matching_nothing_is_pass() {
  local repo head0 head1
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/a.txt" "$(n_lines 4)" "add a.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" --budget 5 "$head0..$head1" -- src/does-not-exist.txt
  [ "$RUN_EXIT" -eq 0 ] || record_fail "non-matching pathspec: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  0 lines changed (budget 5)" "$RUN_OUT" "non-matching pathspec: exact PASS summary"
}

# Inputs: "everything after -- is a pathspec; no flag parsing happens
# there". A flag-shaped pathspec after -- must be taken literally (and
# match nothing here), not parsed as a real flag -- distinguished sharply:
# if "--budget" were mis-parsed as a flag, the budget would become 5 and
# the real 20-line change would still be measured (FAIL); taken literally,
# the pathspecs match nothing (0 lines) and the default budget (500) is
# untouched (PASS).
test_pathspec_no_flag_parsing_after_double_dash() {
  local repo head0 head1
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/real.txt" "$(n_lines 20)" "add real.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" "$head0..$head1" -- --budget 5
  [ "$RUN_EXIT" -eq 0 ] || record_fail "flag-shaped pathspec after --: expected exit 0 (no flag parsing after --), got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "PASS  0 lines changed (budget 500)" "$RUN_OUT" "flag-shaped pathspec after --: taken literally (matches nothing) and default budget untouched"
}

# Inputs: flags may appear before or after the positional argument.
test_flags_before_or_after_positional_equivalent() {
  local repo head0 head1 out_before out_after
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 6)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" --budget 100 "$head0..$head1"
  out_before="$RUN_OUT"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "flag before positional: expected exit 0, got $RUN_EXIT"

  run_in "$repo" "$head0..$head1" --budget 100
  out_after="$RUN_OUT"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "flag after positional: expected exit 0, got $RUN_EXIT"

  assert_eq "$out_before" "$out_after" "--budget before vs after the positional produces identical output"
}

# ===========================================================================
# Invariants: read-only, cwd-independent, deterministic, exit in {0,1,2}
# ===========================================================================

test_invariant_read_only_repo_state_unchanged() {
  local repo head0 head1 status_before status_after head_before head_after refs_before refs_after
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 8)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"

  status_before="$(git -C "$repo" status --porcelain)"
  head_before="$(git -C "$repo" rev-parse HEAD)"
  refs_before="$(git -C "$repo" show-ref)"

  run_in "$repo" "$head0..$head1"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "read-only fixture: measuring 8 lines against the default 500 budget should PASS, expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  run_in "$repo" --budget 1 "$head0..$head1"
  run_in "$repo" --budget 1 --justified "$head0..$head1"
  run_in "$repo" "$head0..$head1" -- src/small.txt
  run_in "$repo" "not-a-real-revision..HEAD"

  status_after="$(git -C "$repo" status --porcelain)"
  head_after="$(git -C "$repo" rev-parse HEAD)"
  refs_after="$(git -C "$repo" show-ref)"

  assert_eq "$status_before" "$status_after" "read-only: git status unchanged after several runs (incl. an error path)"
  assert_eq "$head_before" "$head_after" "read-only: HEAD unchanged"
  assert_eq "$refs_before" "$refs_after" "read-only: refs unchanged"
}

# cwd-independence: the same range and the same config-sourced budget
# produce the same result whether invoked from the repo root or from a
# subdirectory. Uses a committed base config (reaches every subdirectory via
# git checkout, same as the repo root) so this isolates cwd-independence of
# config resolution itself, not $LEGO_CONFIG's own relative-path semantics.
test_invariant_cwd_independence_from_subdirectory() {
  local repo head0 head1 out_root out_sub
  repo="$(new_git_repo)"
  write_base_config "$repo" "$(budget_json 8)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 5)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"
  mkdir -p "$repo/sub/deeper"

  run_in "$repo" "$head0..$head1"
  out_root="$RUN_OUT"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "from repo root: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  run_in "$repo/sub/deeper" "$head0..$head1"
  out_sub="$RUN_OUT"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "from a subdirectory: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  assert_eq "PASS  5 lines changed (budget 8)" "$out_root" "from repo root: exact summary (config-sourced budget resolved)"
  assert_eq "$out_root" "$out_sub" "cwd-independence: identical result from repo root and from a subdirectory (config resolution is repo-root-relative)"
}

test_invariant_deterministic_same_input_same_output() {
  local repo head0 head1 out1 out2 ec1 ec2
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 7)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" --budget 10 "$head0..$head1"
  out1="$RUN_OUT"; ec1="$RUN_EXIT"
  run_in "$repo" --budget 10 "$head0..$head1"
  out2="$RUN_OUT"; ec2="$RUN_EXIT"

  [ "$ec1" -eq 0 ] || record_fail "determinism fixture: 7 lines against budget 10 should PASS, expected exit 0, got $ec1"
  [ "$ec1" -eq "$ec2" ] || record_fail "determinism: exit code differs across two runs against the same repo state ($ec1 vs $ec2)"
  assert_eq "PASS  7 lines changed (budget 10)" "$out1" "determinism fixture: exact PASS summary"
  assert_eq "$out1" "$out2" "determinism: stdout differs across two runs against the same repo state and args"

  local repoA repoB outA outB ecA ecB
  repoA="$(new_git_repo)"
  commit_file "$repoA" "src/small.txt" "$(n_lines 7)" "add small.txt"
  repoB="$(new_git_repo)"
  commit_file "$repoB" "src/small.txt" "$(n_lines 7)" "add small.txt"

  run_in "$repoA" --budget 10 "HEAD~1..HEAD"
  outA="$RUN_OUT"; ecA="$RUN_EXIT"
  run_in "$repoB" --budget 10 "HEAD~1..HEAD"
  outB="$RUN_OUT"; ecB="$RUN_EXIT"

  [ "$ecA" -eq 0 ] || record_fail "determinism fixture (independent repos): 7 lines against budget 10 should PASS, expected exit 0, got $ecA"
  [ "$ecA" -eq "$ecB" ] || record_fail "determinism across independent identical fixtures: exit code differs ($ecA vs $ecB)"
  assert_eq "PASS  7 lines changed (budget 10)" "$outA" "determinism fixture (independent repos): exact PASS summary"
  assert_eq "$outA" "$outB" "determinism across independent identical fixtures: stdout differs despite identical repo content and args"
}

# Invariant: exit status is only ever 0, 1, or 2 (spot-checked across the
# PASS, FAIL, usage-error, and environment-error families; every other test
# in this file also pins an exact 0/1/2 exit code for its own scenario).
test_invariant_exit_status_only_0_1_2() {
  local repo head0 head1 ec
  repo="$(new_git_repo)"
  head0="$(git -C "$repo" rev-parse HEAD)"
  commit_file "$repo" "src/small.txt" "$(n_lines 3)" "add small.txt"
  head1="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" --budget 100 "$head0..$head1"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "PASS scenario: exit code $ec not in {0,1,2}" ;; esac

  run_in "$repo" --budget 1 "$head0..$head1"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "FAIL scenario: exit code $ec not in {0,1,2}" ;; esac

  run_in "$repo"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "usage-error scenario: exit code $ec not in {0,1,2}" ;; esac

  run_in "$repo" "not-a-real-revision..HEAD"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "environment-error scenario: exit code $ec not in {0,1,2}" ;; esac
}

# ===========================================================================
# main
# ===========================================================================

run_test "usage: no positional / extra positional -> exit 2" test_usage_no_positional_or_extra_positional
run_test "usage: unknown flag -> exit 2" test_usage_unknown_flag
run_test "usage: --budget missing/invalid value -> exit 2" test_usage_budget_missing_or_invalid_value
run_test "EC7: --budget 0 -> exit 2" test_usage_budget_zero_is_error
run_test "EC11: -- with no pathspecs -> exit 2" test_double_dash_no_pathspecs_is_usage_error

run_test "not a git repository -> exit 2" test_not_a_git_repo
run_test "bad revision: diagnostic names range and surfaces git's own error text" test_bad_revision_diagnostic_surfaces_gits_own_text

run_test "config: invalid JSON in base and override -> exit 2, names the file" test_config_invalid_json_base_and_override
run_test "config: prSizeBudget not a positive integer -> exit 2" test_config_pr_size_budget_not_positive_integer
run_test "jq required when config-sourced budget needed but jq absent -> exit 2" test_jq_required_when_config_budget_needed_but_absent

run_test "--budget wins, config never read, jq not needed" test_budget_flag_wins_and_config_never_read_and_no_jq_needed
run_test "budget resolution: base config only" test_budget_from_merged_config_base_only
run_test "budget resolution: override config only" test_budget_from_merged_config_override_only
run_test "budget resolution: override wins over base (recursive merge)" test_budget_from_merged_config_override_wins_over_base
run_test "\$LEGO_CONFIG redirects the override path" test_lego_config_env_redirects_override_path
run_test "EC6/EC8: default budget 500 when no config/flag, no jq needed" test_default_budget_500_when_no_config_no_flag_and_no_jq_needed

run_test "measurement: basic PASS/FAIL summaries and breakdown line" test_measurement_basic_pass_and_fail_and_exit_codes
run_test "EC1: empty range -> PASS 0 lines" test_empty_range_pass_zero
run_test "EC2: total == budget -> PASS (inclusive)" test_total_equal_to_budget_is_pass_inclusive
run_test "EC3: deletion-only range can exceed budget" test_deletion_only_range_can_exceed_budget
run_test "EC4: binary-only change -> PASS, binary listed" test_binary_only_change_pass_with_binary_listed
run_test "EC4: binary+text mixed, within budget -> only binary listed" test_binary_and_text_mixed_within_budget_only_binary_listed
run_test "EC5: pure rename contributes 0 lines" test_pure_rename_contributes_zero_lines
run_test "EC10: >10 files -> top 10 sorted (count desc, path asc ties) + remainder" test_breakdown_over_ten_files_sorted_and_remainder

run_test "--justified changes only exit code and summary label" test_justified_changes_only_exit_and_label
run_test "EC9: --justified inert when within budget" test_justified_inert_when_within_budget

run_test "pathspec-scoped measurement matches git exactly" test_pathspec_scoped_measurement_matches_git_exactly
run_test "EC12: pathspec matching nothing -> PASS 0 lines" test_pathspec_matching_nothing_is_pass
run_test "no flag parsing after --" test_pathspec_no_flag_parsing_after_double_dash
run_test "flags before or after the positional are equivalent" test_flags_before_or_after_positional_equivalent

run_test "invariant: read-only (repo state unchanged)" test_invariant_read_only_repo_state_unchanged
run_test "invariant: cwd-independent" test_invariant_cwd_independence_from_subdirectory
run_test "invariant: deterministic" test_invariant_deterministic_same_input_same_output
run_test "invariant: exit status only ever 0, 1, or 2" test_invariant_exit_status_only_0_1_2

echo "---"
echo "Passed: $TOTAL_PASS  Failed: $TOTAL_FAIL  Total: $((TOTAL_PASS + TOTAL_FAIL))"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
