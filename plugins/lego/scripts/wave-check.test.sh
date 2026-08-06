#!/usr/bin/env bash
# wave-check.test.sh — contract tests for wave-check.sh (B02 wave-check,
# plan 001-improve-lego-decomposition-and-parallelism).
#
# Self-contained bash test harness (no bats/shellcheck), mirroring the style
# of pr-size-check.test.sh / realm-gate.test.sh. Black-box only: every test
# builds a throwaway git repository under mktemp, invokes wave-check.sh
# through its public CLI (positional mode, --test-cmd, --scaffold-ref,
# --stub, --collection-pattern, trailing diff-range, $LEGO_CONFIG, $TMPDIR),
# and asserts on its real exit code, stdout lines and stderr — never on the
# script's internals.
#
# Two fixture conventions worth knowing before reading a test:
#
#   * Fake test commands are generated as executable scripts OUTSIDE the
#     fixture repo (make_raw_cmd / make_test_cmd). Anything written inside
#     the repo would show up as an untracked file and change realm-check's
#     verdict, which several tests pin independently.
#   * CONTRACT-DIFF fixtures always COMMIT their mutation. The contract says
#     the comparison is "relative to <ref>" without saying whether the near
#     side is the working tree or HEAD; committing makes the two identical
#     so these tests pin the contract, not a reading of it.
#
# Run directly: `bash wave-check.test.sh`. Exits 0 when every test passes,
# 1 when any test fails, 2 on the suite's own environment errors.
# <!--
# Contract: B12 wave-check-dependency-injection (plan 001-speed-up-repo-ci)
#
# Behavior:
#   As B11, applied to wave-check.sh / wave-check.test.sh. The `path_without`
#   helper below is deleted outright and the two jq-absence sites drive
#   wave-check.sh's new `: "${JQ:=jq}"` seam directly, by setting
#   JQ=/nonexistent in the environment of the single invocation under test,
#   instead of reconstructing PATH.
#
#   wave-check.sh is the fifth script to receive the seam B04 gave
#   realm-gate.sh, pr-size-check.sh and worktree.sh: every `jq` in command
#   position becomes `"$JQ"`, and `command -v jq` becomes
#   `command -v "$JQ"`. Error-message strings mentioning jq are NOT touched.
#
# Inputs:  unchanged — the same fixture repositories and the same CLI.
# Outputs: unchanged — `Passed: 48  Failed: 0  Total: 48`.
#
# Errors:
#   Unchanged. The jq-required diagnostic and its exit 2 must fire
#   identically whether jq is absent from PATH or JQ names a nonexistent
#   path: both are detected through `command -v "$JQ"`.
#
# Invariants:
#   - Pass count is EXACTLY 48, failures EXACTLY 0. A changed count is a
#     defect, not an improvement, whichever direction it moves.
#   - No assertion may be weakened, skipped, merged, or deleted.
#   - wave-check.sh's observable behaviour is unchanged on every path:
#     stdout, stderr and exit code byte-identical, jq present or absent.
#   - Zero `basename` and zero `ln` spawns from this suite. The current
#     figures are 15,786 and 7,120 — two calls to the helper across 7,895
#     files on $PATH.
#   - No wall-clock assertion anywhere in this file.
#
# Edge cases:
#   - `JQ=""` must degrade to the default rather than to an empty command,
#     which is why the seam uses `:=` and not `:-`.
#   - The seam must not be exported: it applies to the invocation under
#     test, never to the suite's own jq calls, which build fixtures.
#   - run_wave_env's PATH parameter stays in the signature: tests unrelated
#     to jq use it, and only the jq-absence sites stop passing a value.
# -->
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wave-check.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: script under test not found at $SCRIPT" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "FATAL: git is required to build fixtures for this suite" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Cleanup registry (see pr-size-check.test.sh for rationale: command
# substitution forks a subshell, so a file-based manifest is needed to
# survive it).
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

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in
    *"$needle"*) : ;;
    *) record_fail "$label: expected to contain [$needle], got [$haystack]" ;;
  esac
}

# ---------------------------------------------------------------------------
# Invocation helper. Sets RUN_OUT / RUN_ERR / RUN_EXIT / RUN_OUT_LINES.
#
# run_wave_env <dir> <path-or-empty> <lego-config-or-empty> <tmpdir-or-empty>
#              <args...>
#   Runs wave-check.sh with cwd <dir>, optionally overriding $PATH,
#   $LEGO_CONFIG (the override-config redirection seam) and $TMPDIR (used to
#   observe the captured-output temp file).
#
# To exercise the jq-absent path, prefix the call with JQ=/nonexistent (e.g.
# `JQ=/nonexistent run_wave_env "$repo" "" "" "" test`) — bash exports a
# prefix assignment into the environment of everything the function invokes,
# including the `bash "$SCRIPT"` below.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
RUN_OUT_LINES=0

run_wave_env() {
  local dir="$1" pth="$2" cfg="$3" tmp="$4"
  shift 4
  local usepath="$pth"
  [ -n "$usepath" ] || usepath="$PATH"
  local usetmp="$tmp"
  [ -n "$usetmp" ] || usetmp="${TMPDIR:-/tmp}"
  local out err ec
  out="$(mktemp)"
  err="$(mktemp)"
  if [ -n "$cfg" ]; then
    ( cd "$dir" && PATH="$usepath" TMPDIR="$usetmp" LEGO_CONFIG="$cfg" bash "$SCRIPT" "$@" ) >"$out" 2>"$err"
  else
    ( cd "$dir" && PATH="$usepath" TMPDIR="$usetmp" bash "$SCRIPT" "$@" ) >"$out" 2>"$err"
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

# run_wave <dir> <args...>  (ambient PATH / LEGO_CONFIG / TMPDIR)
run_wave() {
  local dir="$1"
  shift
  run_wave_env "$dir" "" "" "" "$@"
}

# run_wave_at <script-path> <dir> <args...> -- runs a COPY of the script
# from another location (used to exercise "realm-check.sh not found beside
# this script"). Sets the same RUN_* globals.
run_wave_at() {
  local script="$1" dir="$2"
  shift 2
  local out err ec
  out="$(mktemp)"
  err="$(mktemp)"
  ( cd "$dir" && bash "$script" "$@" ) >"$out" 2>"$err"
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

# ---------------------------------------------------------------------------
# Output assertions built on the "WAVE-CHECK <CHECK>: <STATUS> [detail]"
# format and the fixed check order.
# ---------------------------------------------------------------------------

# check_line <stdout> <CHECK> -- the single line for that check, or empty.
check_line() {
  printf '%s\n' "$1" | grep -m1 "^WAVE-CHECK $2:"
}

# check_status <stdout> <CHECK> -- the PASS|FAIL|SKIPPED token, or empty.
check_status() {
  local line
  line="$(check_line "$1" "$2")"
  [ -n "$line" ] || return 0
  line="${line#WAVE-CHECK $2: }"
  printf '%s' "${line%% *}"
}

# assert_check <stdout> <CHECK> <expected-status> <label>
assert_check() {
  local out="$1" check="$2" want="$3" label="$4"
  local line got
  line="$(check_line "$out" "$check")"
  if [ -z "$line" ]; then
    record_fail "$label: no 'WAVE-CHECK $check:' line on stdout (stdout: $out)"
    return
  fi
  got="$(check_status "$out" "$check")"
  [ "$got" = "$want" ] || record_fail "$label: expected $check $want, got line [$line]"
}

# assert_shape <first-check: RED-RUN|GREEN-RUN> <label> -- the Behavior
# clause "one line per check, fixed order (RED-RUN|GREEN-RUN, REALM,
# CONTRACT-DIFF), then a summary", plus the Outputs clause "stdout: the
# per-check lines and summary, nothing else". Reads the RUN_* globals.
assert_shape() {
  local first="$1" label="$2"
  if [ "$RUN_OUT_LINES" -ne 4 ]; then
    record_fail "$label: expected exactly 4 stdout lines (3 checks + summary), got $RUN_OUT_LINES (stdout: $RUN_OUT)"
    return
  fi
  local l1 l2 l3 l4
  l1="$(printf '%s\n' "$RUN_OUT" | sed -n '1p')"
  l2="$(printf '%s\n' "$RUN_OUT" | sed -n '2p')"
  l3="$(printf '%s\n' "$RUN_OUT" | sed -n '3p')"
  l4="$(printf '%s\n' "$RUN_OUT" | sed -n '4p')"
  case "$l1" in "WAVE-CHECK $first: "*) : ;; *) record_fail "$label: line 1 must be the $first check, got [$l1]" ;; esac
  case "$l2" in "WAVE-CHECK REALM: "*) : ;; *) record_fail "$label: line 2 must be the REALM check, got [$l2]" ;; esac
  case "$l3" in "WAVE-CHECK CONTRACT-DIFF: "*) : ;; *) record_fail "$label: line 3 must be the CONTRACT-DIFF check, got [$l3]" ;; esac
  case "$l4" in "WAVE-CHECK RESULT: "*) : ;; *) record_fail "$label: line 4 must be the RESULT summary, got [$l4]" ;; esac
}

# assert_summary <expected-summary-line> <label>
assert_summary() {
  local want="$1" label="$2"
  local last
  last="$(printf '%s\n' "$RUN_OUT" | tail -n1)"
  assert_eq "$want" "$last" "$label"
}

# assert_status_token <status> <label> -- every check line carries one of the
# three legal status tokens (format clause).
assert_status_token() {
  local st="$1" label="$2"
  case "$st" in
    PASS|FAIL|SKIPPED) : ;;
    *) record_fail "$label: status token [$st] is not one of PASS|FAIL|SKIPPED" ;;
  esac
}

# ---------------------------------------------------------------------------
# Fixture helpers: repos.
# ---------------------------------------------------------------------------

# new_git_repo -- a fresh repo at <container>/repo, branch "master", one
# commit (README.md), no uncommitted changes. A clean worktree means
# realm-check reports no violations in either realm, so REALM is PASS by
# default and tests that care about it dirty the repo deliberately.
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
  # .local/ is gitignored in production; mirror that here so an uncommitted
  # .local/config.json fixture never appears as an untracked file (which
  # would change realm-check's verdict and the read-only invariant check).
  printf '%s\n' '.local/' >> "$repo/.git/info/exclude"
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial commit"
  printf '%s' "$repo"
}

# commit_file <repo> <relpath> <content> <message>
commit_file() {
  local repo="$1" rel="$2" content="$3" msg="$4"
  mkdir -p "$(dirname "$repo/$rel")"
  printf '%s\n' "$content" > "$repo/$rel"
  git -C "$repo" add -- "$rel"
  git -C "$repo" commit -q -m "$msg"
}

# write_untracked <repo> <relpath> <content> -- an uncommitted, untracked
# file: what realm-check sees in its no-diff-range mode.
write_untracked() {
  local repo="$1" rel="$2" content="$3"
  mkdir -p "$(dirname "$repo/$rel")"
  printf '%s\n' "$content" > "$repo/$rel"
}

# write_base_config <repo> <json> -- commits .claude/lego.json (the committed
# base layer of the layered config).
write_base_config() {
  local repo="$1" content="$2"
  mkdir -p "$repo/.claude"
  printf '%s' "$content" > "$repo/.claude/lego.json"
  git -C "$repo" add .claude/lego.json
  git -C "$repo" commit -q -m "add base lego.json"
}

# write_override_config <repo> <json> -- writes .local/config.json (the
# gitignored default override path), uncommitted.
write_override_config() {
  local repo="$1" content="$2"
  mkdir -p "$repo/.local"
  printf '%s' "$content" > "$repo/.local/config.json"
}

# write_json_at <repo> <relpath> <json> -- arbitrary JSON at an arbitrary
# relpath, uncommitted (for $LEGO_CONFIG redirection fixtures). Kept under
# .local/ so it stays invisible to realm-check.
write_json_at() {
  local repo="$1" rel="$2" content="$3"
  mkdir -p "$(dirname "$repo/$rel")"
  printf '%s' "$content" > "$repo/$rel"
}

# new_tmpdir -- a fresh, empty directory to hand the script as $TMPDIR.
new_tmpdir() {
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  printf '%s' "$d"
}

# ---------------------------------------------------------------------------
# Fixture helpers: fake test commands.
#
# Every fake command lives outside the fixture repo so it never perturbs
# realm-check. Paths contain no spaces (mktemp -d under /tmp), so the
# generated path is safe to hand to --test-cmd whether the script runs it
# via eval, bash -c, or a bare invocation.
# ---------------------------------------------------------------------------

# make_raw_cmd <body> -- an executable bash script with <body> as its body.
make_raw_cmd() {
  local body="$1" dir f
  dir="$(mktemp -d)"
  track_tmp "$dir"
  f="$dir/testcmd.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$body"
  } > "$f"
  chmod +x "$f"
  printf '%s' "$f"
}

# make_test_cmd <exit-code> <stdout-text> <stderr-text> <marker-file> <id>
#   Any of <stdout-text>, <stderr-text>, <marker-file> may be empty. When a
#   marker file is given, the command appends <id> to it, which is how tests
#   prove WHICH resolved command actually ran.
make_test_cmd() {
  local ec="$1" so="$2" se="$3" mf="$4" mid="$5"
  local body=""
  if [ -n "$mf" ]; then
    body+="$(printf 'printf "%%s\\n" %q >> %q' "$mid" "$mf")"$'\n'
  fi
  if [ -n "$so" ]; then
    body+="$(printf 'printf "%%s\\n" %q' "$so")"$'\n'
  fi
  if [ -n "$se" ]; then
    body+="$(printf 'printf "%%s\\n" %q >&2' "$se")"$'\n'
  fi
  body+="exit $ec"
  make_raw_cmd "$body"
}

# Shorthands for the two commands most tests need.
red_cmd()   { make_test_cmd 1 "1 test failed" "AssertionError: expected 1 got 2" "" ""; }
green_cmd() { make_test_cmd 0 "all tests passed" "" "" ""; }

# ---------------------------------------------------------------------------
# Fixture helpers: contract-carrying stub files for CONTRACT-DIFF.
# ---------------------------------------------------------------------------

# stub_content <fn-name> <behavior-line> -- a scaffolded stub: a contract
# docblock region delimited by "# <!--" / "# -->", a function signature, and
# a NotImplemented body.
stub_content() {
  cat <<EOF
#!/usr/bin/env bash
# fixture stub for CONTRACT-DIFF tests.
#
# <!--
# Contract: FIXTURE $1
#
# Behavior:
#   $2
#
# Inputs:
#   - the input argument.
#
# Outputs:
#   - stdout: the result.
# -->

$1() {
  echo "NotImplemented" >&2
  return 70
}
EOF
}

# commit_stub <repo> <relpath> <fn-name> <behavior-line> <message>
commit_stub() {
  local repo="$1" rel="$2" fn="$3" behavior="$4" msg="$5"
  mkdir -p "$(dirname "$repo/$rel")"
  stub_content "$fn" "$behavior" > "$repo/$rel"
  git -C "$repo" add -- "$rel"
  git -C "$repo" commit -q -m "$msg"
}

# commit_sed <repo> <relpath> <sed-expr> <message> -- applies a mutation and
# commits it, so working tree and HEAD agree (see the header note).
commit_sed() {
  local repo="$1" rel="$2" expr="$3" msg="$4"
  sed -i "$expr" "$repo/$rel"
  git -C "$repo" add -- "$rel"
  git -C "$repo" commit -q -m "$msg"
}

# ===========================================================================
# Usage and argument errors
# (Errors: "Unknown mode, unknown flag, flag missing its value: usage on
# stderr, exit 2")
# ===========================================================================

test_usage_missing_mode() {
  local repo
  repo="$(new_git_repo)"

  run_wave "$repo"
  assert_eq 2 "$RUN_EXIT" "no arguments at all: exit code"
  [ -n "$RUN_ERR" ] || record_fail "no arguments: expected a usage diagnostic on stderr"
  [ "$RUN_OUT_LINES" -eq 0 ] || record_fail "no arguments: expected no stdout on a usage error, got: $RUN_OUT"
}

test_usage_unknown_mode() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"

  local bad
  for bad in bogus TEST Impl tests implementation; do
    run_wave "$repo" "$bad" --test-cmd "$cmd"
    assert_eq 2 "$RUN_EXIT" "mode '$bad' (only literal test|impl are legal): exit code"
    [ "$RUN_OUT_LINES" -eq 0 ] || record_fail "mode '$bad': expected no stdout, got: $RUN_OUT"
  done
  [ -n "$RUN_ERR" ] || record_fail "unknown mode: expected a usage diagnostic on stderr"
}

test_usage_unknown_flag() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"

  run_wave "$repo" test --frobnicate --test-cmd "$cmd"
  assert_eq 2 "$RUN_EXIT" "unknown flag before known flags: exit code"

  run_wave "$repo" impl --test-cmd "$cmd" --frobnicate
  assert_eq 2 "$RUN_EXIT" "unknown flag after known flags: exit code"
  [ -n "$RUN_ERR" ] || record_fail "unknown flag: expected a usage diagnostic on stderr"
  [ "$RUN_OUT_LINES" -eq 0 ] || record_fail "unknown flag: expected no stdout, got: $RUN_OUT"
}

test_usage_flag_missing_its_value() {
  local repo
  repo="$(new_git_repo)"

  local f
  for f in --test-cmd --scaffold-ref --stub --collection-pattern; do
    run_wave "$repo" impl "$f"
    assert_eq 2 "$RUN_EXIT" "$f as the last argument, no value: exit code"
    [ "$RUN_OUT_LINES" -eq 0 ] || record_fail "$f with no value: expected no stdout, got: $RUN_OUT"
  done
}

# ===========================================================================
# Environment errors
# (Errors: "Unresolvable test command, jq unavailable when config resolution
# is required, not inside a git repository, realm-check.sh not found beside
# this script: diagnostic on stderr, exit 2")
# ===========================================================================

test_not_inside_a_git_repository() {
  local dir cmd
  dir="$(mktemp -d)"
  track_tmp "$dir"
  cmd="$(red_cmd)"

  run_wave "$dir" test --test-cmd "$cmd"
  assert_eq 2 "$RUN_EXIT" "outside any git worktree: exit code"
  [ -n "$RUN_ERR" ] || record_fail "outside any git worktree: expected a diagnostic on stderr"
  [ "$RUN_OUT_LINES" -eq 0 ] || record_fail "outside any git worktree: expected no stdout, got: $RUN_OUT"
}

# The script resolves its sibling scripts relative to its own location, never
# the cwd (Inputs clause), so a copy placed somewhere without realm-check.sh
# beside it must fail as an environment error even when the cwd is a perfectly
# good git worktree.
test_realm_check_missing_beside_script() {
  local repo dir copy cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"
  dir="$(mktemp -d)"
  track_tmp "$dir"
  copy="$dir/wave-check.sh"
  cp "$SCRIPT" "$copy"
  if [ -e "$dir/realm-check.sh" ]; then
    record_fail "fixture bug: the isolated copy directory must not contain realm-check.sh"
    return
  fi

  run_wave_at "$copy" "$repo" test --test-cmd "$cmd"
  assert_eq 2 "$RUN_EXIT" "realm-check.sh not beside the script: exit code"
  [ -n "$RUN_ERR" ] || record_fail "realm-check.sh not beside the script: expected a diagnostic on stderr"
}

# ===========================================================================
# Test-command resolution
# (Inputs: --test-cmd; layered-config fallback; object variants; Errors:
# unresolvable command, jq unavailable when config resolution is required)
# ===========================================================================

# No --test-cmd and nothing in config to resolve: unresolvable, exit 2.
test_unresolvable_test_command_exit_2() {
  local repo
  repo="$(new_git_repo)"
  run_wave "$repo" test
  assert_eq 2 "$RUN_EXIT" "no --test-cmd and no config file at all: exit code"
  [ -n "$RUN_ERR" ] || record_fail "no --test-cmd, no config: expected a diagnostic on stderr"

  # A config that exists but has no commands.test.
  local repo2
  repo2="$(new_git_repo)"
  write_base_config "$repo2" '{"commands":{"lint":"true"}}'
  run_wave "$repo2" test
  assert_eq 2 "$RUN_EXIT" "config present but commands.test absent: exit code"

  # An object-valued commands.test with no "default" key is a config error
  # (config-schema.md: default is required for the variants form).
  local repo3
  repo3="$(new_git_repo)"
  write_base_config "$repo3" '{"commands":{"test":{"unit":"true"}}}'
  run_wave "$repo3" test
  assert_eq 2 "$RUN_EXIT" "object commands.test with no default variant: exit code"

  # A "default" naming a variant that does not exist.
  local repo4
  repo4="$(new_git_repo)"
  write_base_config "$repo4" '{"commands":{"test":{"unit":"true","default":"missing"}}}'
  run_wave "$repo4" test
  assert_eq 2 "$RUN_EXIT" "default naming an absent variant: exit code"
}

# jq is required only when the command must come from config.
test_jq_required_when_config_resolution_needed() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"
  write_base_config "$repo" "{\"commands\":{\"test\":\"$cmd\"}}"

  JQ=/nonexistent run_wave_env "$repo" "" "" "" test
  assert_eq 2 "$RUN_EXIT" "config-sourced test command with jq absent: exit code"
  case "$RUN_ERR" in
    *jq*|*JQ*) : ;;
    *) record_fail "jq absent: diagnostic does not mention jq (stderr: $RUN_ERR)" ;;
  esac
}

# ...and NOT required when --test-cmd is given: the config is never consulted
# on that path, so a repo with a config file but no jq still works.
test_no_jq_needed_when_test_cmd_given() {
  local repo cmd marker cfg_cmd
  repo="$(new_git_repo)"
  marker="$(mktemp)"
  track_tmp "$marker"
  cfg_cmd="$(make_test_cmd 0 "" "" "$marker" "from-config")"
  write_base_config "$repo" "{\"commands\":{\"test\":\"$cfg_cmd\"}}"
  cmd="$(make_test_cmd 1 "1 test failed" "" "$marker" "from-flag")"

  JQ=/nonexistent run_wave_env "$repo" "" "" "" test --test-cmd "$cmd"
  assert_eq 0 "$RUN_EXIT" "--test-cmd with jq absent and a config present: exit code (stderr: $RUN_ERR)"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "--test-cmd with jq absent: red run"
  assert_eq "from-flag" "$(cat "$marker")" "--test-cmd wins: only the flag's command ran, config never read"
}

# commands.test as a plain string in the committed base config.
test_config_test_cmd_string_from_base() {
  local repo marker cmd
  repo="$(new_git_repo)"
  marker="$(mktemp)"
  track_tmp "$marker"
  cmd="$(make_test_cmd 1 "1 test failed" "" "$marker" "base-string")"
  write_base_config "$repo" "{\"commands\":{\"test\":\"$cmd\"}}"

  run_wave "$repo" test
  assert_eq 0 "$RUN_EXIT" "commands.test string from base config: exit code (stderr: $RUN_ERR)"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "commands.test string from base config: red run"
  assert_eq "base-string" "$(cat "$marker")" "commands.test string from base config: that command is what ran"
}

# An object-valued commands.test uses its "default" variant, not the first
# key and not the "default" string itself.
test_config_test_cmd_object_uses_default_variant() {
  local repo marker unit_cmd e2e_cmd
  repo="$(new_git_repo)"
  marker="$(mktemp)"
  track_tmp "$marker"
  unit_cmd="$(make_test_cmd 1 "1 test failed" "" "$marker" "unit-variant")"
  e2e_cmd="$(make_test_cmd 1 "1 test failed" "" "$marker" "e2e-variant")"
  write_base_config "$repo" "{\"commands\":{\"test\":{\"e2e\":\"$e2e_cmd\",\"unit\":\"$unit_cmd\",\"default\":\"unit\"}}}"

  run_wave "$repo" test
  assert_eq 0 "$RUN_EXIT" "object commands.test: exit code (stderr: $RUN_ERR)"
  assert_eq "unit-variant" "$(cat "$marker")" "object commands.test: the 'default' variant (unit) ran, not another key"
}

# The override layer deep-merges over the base, override winning per key.
test_config_override_wins_over_base() {
  local repo marker base_cmd over_cmd
  repo="$(new_git_repo)"
  marker="$(mktemp)"
  track_tmp "$marker"
  base_cmd="$(make_test_cmd 1 "1 test failed" "" "$marker" "base")"
  over_cmd="$(make_test_cmd 1 "1 test failed" "" "$marker" "override")"
  write_base_config "$repo" "{\"commands\":{\"test\":\"$base_cmd\"}}"
  write_override_config "$repo" "{\"commands\":{\"test\":\"$over_cmd\"}}"

  run_wave "$repo" test
  assert_eq 0 "$RUN_EXIT" "layered config: exit code (stderr: $RUN_ERR)"
  assert_eq "override" "$(cat "$marker")" "layered config: .local/config.json wins over .claude/lego.json"
}

# $LEGO_CONFIG redirects the override file's path, exactly as in realm.sh:
# a real .local/config.json is present and must be ignored once the env var
# points elsewhere.
test_lego_config_env_redirects_override_path() {
  local repo marker default_cmd custom_cmd
  repo="$(new_git_repo)"
  marker="$(mktemp)"
  track_tmp "$marker"
  default_cmd="$(make_test_cmd 1 "1 test failed" "" "$marker" "default-override-path")"
  custom_cmd="$(make_test_cmd 1 "1 test failed" "" "$marker" "redirected-override-path")"
  write_override_config "$repo" "{\"commands\":{\"test\":\"$default_cmd\"}}"
  write_json_at "$repo" ".local/custom/myconfig.json" "{\"commands\":{\"test\":\"$custom_cmd\"}}"

  run_wave_env "$repo" "" ".local/custom/myconfig.json" "" test
  assert_eq 0 "$RUN_EXIT" "\$LEGO_CONFIG redirect: exit code (stderr: $RUN_ERR)"
  assert_eq "redirected-override-path" "$(cat "$marker")" "\$LEGO_CONFIG points at .local/custom/myconfig.json, not the default .local/config.json"
}

# ===========================================================================
# Mode test — RED-RUN
# (Behavior: "FAIL if it exits 0 ... PASS when no line of the combined output
# matches the collection-error pattern; FAIL labeled COLLECTION when any line
# matches")
# ===========================================================================

test_red_run_pass_on_honest_red() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_eq 0 "$RUN_EXIT" "honest red run in a clean repo: exit code (stderr: $RUN_ERR)"
  assert_shape "RED-RUN" "honest red run: output shape"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "honest red run"
  assert_check "$RUN_OUT" "REALM" "PASS" "honest red run, clean worktree"
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "SKIPPED" "honest red run, no --scaffold-ref"
  assert_summary "WAVE-CHECK RESULT: PASS" "honest red run: summary line"
}

test_red_run_fail_when_test_command_exits_zero() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_eq 1 "$RUN_EXIT" "test-mode run whose command exits 0: exit code"
  assert_shape "RED-RUN" "nothing red: output shape"
  assert_check "$RUN_OUT" "RED-RUN" "FAIL" "nothing red — the wave produced no failing tests"
  assert_check "$RUN_OUT" "REALM" "PASS" "nothing red: realm still clean"
  assert_summary "WAVE-CHECK RESULT: FAIL (1 failed)" "nothing red: summary line"
}

# EC: "Test command exits non-zero with empty output: RED-RUN PASS in test
# mode (a silent red is still red)".
test_red_run_pass_on_silent_red() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(make_test_cmd 1 "" "" "" "")"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "non-zero exit with completely empty output is still red"
  assert_eq 0 "$RUN_EXIT" "silent red: exit code (stderr: $RUN_ERR)"
}

# Each alternative of the default collection pattern, on stdout.
test_red_run_collection_fail_default_pattern() {
  local repo cmd token
  repo="$(new_git_repo)"
  for token in \
    "SyntaxError" \
    "ImportError" \
    "ModuleNotFoundError" \
    "cannot find module" \
    "command not found" \
    "CompileError" \
    "compilation failed" \
    "ParseError" \
    "collection error"; do
    cmd="$(make_test_cmd 1 "$token: while loading the suite" "" "" "")"
    run_wave "$repo" test --test-cmd "$cmd"
    assert_check "$RUN_OUT" "RED-RUN" "FAIL" "default collection pattern alternative '$token'"
    assert_contains "$(check_line "$RUN_OUT" "RED-RUN")" "COLLECTION" "collection alternative '$token': the FAIL is labeled COLLECTION"
    assert_eq 1 "$RUN_EXIT" "collection alternative '$token': exit code"
  done
}

# The pattern is matched against the COMBINED output: a collection error that
# only ever reaches stderr must still be classified.
test_red_run_collection_detected_on_stderr_too() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(make_test_cmd 1 "" "ModuleNotFoundError: No module named widgets" "" "")"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_check "$RUN_OUT" "RED-RUN" "FAIL" "collection error on stderr only (combined output is what is scanned)"
  assert_contains "$(check_line "$RUN_OUT" "RED-RUN")" "COLLECTION" "collection error on stderr only: labeled COLLECTION"
  assert_eq 1 "$RUN_EXIT" "collection error on stderr only: exit code"
}

# EC: "Collection pattern matching inside a legitimate assertion message:
# FAILs conservatively; --collection-pattern is the escape hatch."
test_collection_pattern_conservative_then_overridden() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(make_test_cmd 1 "AssertionError: expected raise ImportError, got None" "" "" "")"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_check "$RUN_OUT" "RED-RUN" "FAIL" "collection token inside an assertion message: FAILs conservatively"
  assert_contains "$(check_line "$RUN_OUT" "RED-RUN")" "COLLECTION" "conservative match: labeled COLLECTION"

  run_wave "$repo" test --test-cmd "$cmd" --collection-pattern "SyntaxError|Segmentation fault"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "--collection-pattern is the escape hatch: the default pattern no longer applies"
  assert_eq 0 "$RUN_EXIT" "escape hatch: exit code (stderr: $RUN_ERR)"
}

# --collection-pattern REPLACES the default (it is not additive) and is
# treated as an ERE, alternation included.
test_collection_pattern_override_is_an_ere() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(make_test_cmd 1 "fatal: WIDGET EXPLOSION during setup" "" "" "")"

  run_wave "$repo" test --test-cmd "$cmd" --collection-pattern "NOTHING|WIDGET EXPLOSION"
  assert_check "$RUN_OUT" "RED-RUN" "FAIL" "custom ERE alternative matches"
  assert_contains "$(check_line "$RUN_OUT" "RED-RUN")" "COLLECTION" "custom ERE match: labeled COLLECTION"

  run_wave "$repo" test --test-cmd "$cmd" --collection-pattern "NOTHING|NOTHING-ELSE"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "custom ERE with no matching alternative"
}

# ---------------------------------------------------------------------------
# SUCCESS-line exclusion (issue #326)
#
# Behavior: "Scanned means every line except test-framework SUCCESS lines".
# The regression this pins is specific: lego's own suite tests the collection
# detector, so its PASSING output necessarily carries the detector's own
# vocabulary, and before the exclusion `wave-check.sh test` FAILed RED-RUN on
# every wave of every plan in this repo — tripped by the test proving the
# detector works.
# ---------------------------------------------------------------------------

# One case per success marker the contract names. Each command emits the
# success line carrying "collection error" AND an honest failing line, so the
# run is genuinely red and only the classification is under test.
test_red_run_success_lines_are_not_scanned() {
  local repo cmd prefix
  repo="$(new_git_repo)"
  for prefix in \
    "ok - " \
    "ok 1 - " \
    "OK: " \
    "PASS  " \
    "PASSED " \
    "SUCCESS: " \
    "✓ " \
    "✔ " \
    "--- PASS: " \
    "[ OK ] " \
    "[  PASSED  ] " \
    "    ok - "; do
    cmd="$(make_raw_cmd "$(printf 'printf "%%s\\n" %q\nprintf "%%s\\n" "not ok - unrelated failing test"\nexit 1' "${prefix}collection error is still detected")")"
    run_wave "$repo" test --test-cmd "$cmd"
    assert_check "$RUN_OUT" "RED-RUN" "PASS" "success line '${prefix}' carrying a collection token is not scanned"
    assert_eq 0 "$RUN_EXIT" "success line '${prefix}': exit code (stderr: $RUN_ERR)"
  done
}

# The exclusion is leading-token only and must not swallow "not ok", which
# shares its first two characters with "ok". A FAILING assertion whose message
# carries a collection token still FAILs conservatively — the same clause the
# escape-hatch test above pins, asserted here for the TAP prefix specifically
# because that is the form the exclusion could most easily over-match.
test_red_run_not_ok_line_is_still_scanned() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(make_test_cmd 1 "not ok - collection error detection" "" "" "")"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_check "$RUN_OUT" "RED-RUN" "FAIL" "'not ok' is not a success line: still scanned"
  assert_contains "$(check_line "$RUN_OUT" "RED-RUN")" "COLLECTION" "'not ok' line: labeled COLLECTION"
  assert_eq 1 "$RUN_EXIT" "'not ok' line: exit code"
}

# The exclusion drops lines, never the whole scan: a real collection error
# sharing its output with passing lines must still be caught. This is the
# check that would catch an over-broad exclusion regressing the detector to
# useless.
test_red_run_success_lines_do_not_mask_a_real_collection_error() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(make_raw_cmd "$(printf 'printf "%%s\\n" "ok - collection error is still detected"\nprintf "%%s\\n" "ModuleNotFoundError: No module named widgets"\nexit 1')")"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_check "$RUN_OUT" "RED-RUN" "FAIL" "a real collection error alongside passing output is still caught"
  assert_contains "$(check_line "$RUN_OUT" "RED-RUN")" "COLLECTION" "unmasked collection error: labeled COLLECTION"
  assert_eq 1 "$RUN_EXIT" "unmasked collection error: exit code"
}

# EC: "A framework that marks success at the END of a line rather than the
# start ... is NOT excluded". Pinned because it is a stated limitation, not an
# accident: widening the rule to trailing markers would let a diagnostic
# ending in "ok" escape the scan.
test_red_run_trailing_success_marker_is_still_scanned() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(make_test_cmd 1 "tests/test_widgets.py::test_collection error PASSED" "" "" "")"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_check "$RUN_OUT" "RED-RUN" "FAIL" "a trailing PASSED marker does not exclude the line"
  assert_contains "$(check_line "$RUN_OUT" "RED-RUN")" "COLLECTION" "trailing marker: labeled COLLECTION"
}

# The scan runs on the combined output, so the exclusion must apply to stderr
# lines too — a framework writing its progress to stderr is ordinary.
test_red_run_success_line_exclusion_applies_to_stderr() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(make_test_cmd 1 "" "ok - collection error is still detected" "" "")"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "a success line on stderr is excluded just as one on stdout is"
  assert_eq 0 "$RUN_EXIT" "success line on stderr: exit code (stderr: $RUN_ERR)"
}

# The test command runs in a subshell, so an `exit` inside a --test-cmd
# string ends the command and not wave-check itself. Before the subshell,
# this produced no output at all and exit 1 — indistinguishable from a
# crash, and silent enough to be diagnosed as a flake.
test_test_cmd_containing_exit_does_not_terminate_wave_check() {
  local repo
  repo="$(new_git_repo)"

  run_wave "$repo" test --test-cmd 'printf "%s\n" "1 test failed"; exit 1'
  assert_shape "RED-RUN" "--test-cmd containing a bare exit: output shape"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "--test-cmd containing a bare exit is an honest red, not a crash"
  assert_eq 0 "$RUN_EXIT" "--test-cmd containing a bare exit: exit code (stderr: $RUN_ERR)"
}

# ===========================================================================
# Mode impl — GREEN-RUN
# (Behavior: "FAIL unless the resolved test command exits 0")
# ===========================================================================

test_green_run_pass_on_green() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"

  run_wave "$repo" impl --test-cmd "$cmd"
  assert_eq 0 "$RUN_EXIT" "green suite in a clean repo: exit code (stderr: $RUN_ERR)"
  assert_shape "GREEN-RUN" "green suite: output shape"
  assert_check "$RUN_OUT" "GREEN-RUN" "PASS" "green suite"
  assert_check "$RUN_OUT" "REALM" "PASS" "green suite, clean worktree"
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "SKIPPED" "green suite, no --scaffold-ref"
  assert_summary "WAVE-CHECK RESULT: PASS" "green suite: summary line"
}

test_green_run_fail_on_nonzero() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"

  run_wave "$repo" impl --test-cmd "$cmd"
  assert_eq 1 "$RUN_EXIT" "failing suite in impl mode: exit code"
  assert_check "$RUN_OUT" "GREEN-RUN" "FAIL" "failing suite in impl mode"
  assert_summary "WAVE-CHECK RESULT: FAIL (1 failed)" "failing suite in impl mode: summary line"
}

# EC: "Test command exits non-zero with empty output: ... GREEN-RUN FAIL in
# impl mode."
test_green_run_fail_on_silent_nonzero() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(make_test_cmd 1 "" "" "" "")"

  run_wave "$repo" impl --test-cmd "$cmd"
  assert_check "$RUN_OUT" "GREEN-RUN" "FAIL" "non-zero exit with empty output is not green"
  assert_eq 1 "$RUN_EXIT" "silent non-zero in impl mode: exit code"
}

# Collection classification belongs to RED-RUN alone: in impl mode the only
# question GREEN-RUN asks is whether the command exited 0.
test_impl_mode_ignores_collection_pattern() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(make_test_cmd 0 "ImportError mentioned in a passing test's name" "" "" "")"

  run_wave "$repo" impl --test-cmd "$cmd"
  assert_check "$RUN_OUT" "GREEN-RUN" "PASS" "impl mode: exit 0 is green regardless of collection-pattern text in the output"
  assert_eq 0 "$RUN_EXIT" "impl mode with collection text but exit 0: exit code (stderr: $RUN_ERR)"
}

# ===========================================================================
# REALM
# (Behavior: "delegates to realm-check.sh <mode> [diff-range]; any VIOLATION
# line FAILs this check")
# ===========================================================================

test_realm_fail_in_test_mode_when_impl_file_changed() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"
  write_untracked "$repo" "src/widget.js" "function widget() {}"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_eq 1 "$RUN_EXIT" "test wave touching a non-test file: exit code"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "test wave touching a non-test file: the red run itself is still fine"
  assert_check "$RUN_OUT" "REALM" "FAIL" "test wave touching a non-test file"
  assert_summary "WAVE-CHECK RESULT: FAIL (1 failed)" "realm violation only: summary line"
}

test_realm_pass_in_test_mode_when_only_test_files_changed() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"
  write_untracked "$repo" "src/widget.test.js" "it('fails', () => {})"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_check "$RUN_OUT" "REALM" "PASS" "test wave touching only test-family files"
  assert_eq 0 "$RUN_EXIT" "test wave touching only test-family files: exit code (stderr: $RUN_ERR)"
}

test_realm_fail_in_impl_mode_when_test_file_changed() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"
  write_untracked "$repo" "src/widget.test.js" "it('passes', () => {})"

  run_wave "$repo" impl --test-cmd "$cmd"
  assert_eq 1 "$RUN_EXIT" "impl wave touching a test-family file: exit code"
  assert_check "$RUN_OUT" "GREEN-RUN" "PASS" "impl wave touching a test-family file: the suite is still green"
  assert_check "$RUN_OUT" "REALM" "FAIL" "impl wave touching a test-family file"
}

test_realm_pass_in_impl_mode_when_only_impl_files_changed() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"
  write_untracked "$repo" "src/widget.js" "function widget() { return 1 }"

  run_wave "$repo" impl --test-cmd "$cmd"
  assert_check "$RUN_OUT" "REALM" "PASS" "impl wave touching only non-test files"
  assert_eq 0 "$RUN_EXIT" "impl wave touching only non-test files: exit code (stderr: $RUN_ERR)"
}

# The trailing diff-range is passed through verbatim; without it, realm-check
# runs in its uncommitted-changes mode. The same repo therefore gives two
# different verdicts depending on whether the range is supplied — which is
# what proves the passthrough happened.
test_trailing_diff_range_is_passed_through() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"
  commit_file "$repo" "src/widget.js" "function widget() {}" "add an impl file"

  run_wave "$repo" test --test-cmd "$cmd" "HEAD~1..HEAD"
  assert_eq 1 "$RUN_EXIT" "range naming a commit that touched an impl file: exit code"
  assert_check "$RUN_OUT" "REALM" "FAIL" "range naming a commit that touched an impl file"
  assert_contains "$(check_line "$RUN_OUT" "REALM")" "src/widget.js" "realm failure detail names the offending file"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_check "$RUN_OUT" "REALM" "PASS" "same repo with no range: uncommitted-changes mode sees a clean worktree"
  assert_eq 0 "$RUN_EXIT" "same repo with no range: exit code (stderr: $RUN_ERR)"
}

# EC: "Empty diff-range (no commits between refs): passed to realm-check.sh
# verbatim; its verdict is passed through."
test_empty_diff_range_passes_through_its_verdict() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"
  # A dirty worktree that WOULD fail the uncommitted-changes mode, so the
  # empty range is demonstrably what is being checked.
  write_untracked "$repo" "src/widget.js" "function widget() {}"

  run_wave "$repo" test --test-cmd "$cmd" "HEAD..HEAD"
  assert_check "$RUN_OUT" "REALM" "PASS" "empty range: no files in the range, so no violations"
  assert_eq 0 "$RUN_EXIT" "empty range: exit code (stderr: $RUN_ERR)"
}

# ===========================================================================
# CONTRACT-DIFF
# (Behavior: --scaffold-ref / --stub; Edge case: a stub missing at <ref>)
# ===========================================================================

# "Without --scaffold-ref the check reports 'CONTRACT-DIFF: SKIPPED (no
# --scaffold-ref)' — visible, never silent."
test_contract_diff_skipped_without_scaffold_ref() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"

  run_wave "$repo" impl --test-cmd "$cmd"
  assert_eq "WAVE-CHECK CONTRACT-DIFF: SKIPPED (no --scaffold-ref)" "$(check_line "$RUN_OUT" "CONTRACT-DIFF")" "impl mode without --scaffold-ref: the exact SKIPPED line"
  assert_summary "WAVE-CHECK RESULT: PASS" "SKIPPED never fails the run on its own: summary line"
  assert_eq 0 "$RUN_EXIT" "SKIPPED never causes exit 1 on its own: exit code (stderr: $RUN_ERR)"
}

# "With --scaffold-ref but no --stub, PASS vacuously with detail '(no stubs
# named)'."
test_contract_diff_vacuous_pass_without_stubs() {
  local repo cmd ref
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"
  ref="$(git -C "$repo" rev-parse HEAD)"

  run_wave "$repo" impl --test-cmd "$cmd" --scaffold-ref "$ref"
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "PASS" "--scaffold-ref with no --stub: vacuous pass"
  assert_contains "$(check_line "$RUN_OUT" "CONTRACT-DIFF")" "(no stubs named)" "--scaffold-ref with no --stub: detail says why it is vacuous"
  assert_eq 0 "$RUN_EXIT" "vacuous CONTRACT-DIFF pass: exit code (stderr: $RUN_ERR)"
}

# The whole point of the check: an implementer may replace the stub body
# freely, so long as the contract docblock and the signature survive intact.
test_contract_diff_pass_when_only_the_body_was_implemented() {
  local repo cmd ref
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"
  commit_stub "$repo" "src/thing.sh" "do_thing" "Does the thing." "scaffold src/thing.sh"
  ref="$(git -C "$repo" rev-parse HEAD)"
  sed -i 's/^  echo "NotImplemented" >&2$/  printf "%s\\n" "$1"/' "$repo/src/thing.sh"
  sed -i 's/^  return 70$/  return 0/' "$repo/src/thing.sh"
  git -C "$repo" add -- src/thing.sh
  git -C "$repo" commit -q -m "implement do_thing"

  run_wave "$repo" impl --test-cmd "$cmd" --scaffold-ref "$ref" --stub src/thing.sh
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "PASS" "body replaced, docblock and signature untouched"
  assert_shape "GREEN-RUN" "body-only change: output shape"
  assert_summary "WAVE-CHECK RESULT: PASS" "body-only change: summary line"
  assert_eq 0 "$RUN_EXIT" "body-only change: exit code (stderr: $RUN_ERR)"
}

test_contract_diff_fail_when_a_docblock_line_is_changed() {
  local repo cmd ref
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"
  commit_stub "$repo" "src/thing.sh" "do_thing" "Does the thing." "scaffold src/thing.sh"
  ref="$(git -C "$repo" rev-parse HEAD)"
  commit_sed "$repo" "src/thing.sh" 's/^#   Does the thing\.$/#   Does something else entirely./' "reword the contract"

  run_wave "$repo" impl --test-cmd "$cmd" --scaffold-ref "$ref" --stub src/thing.sh
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "FAIL" "a line inside the contract docblock was reworded"
  assert_contains "$(check_line "$RUN_OUT" "CONTRACT-DIFF")" "src/thing.sh" "docblock reworded: the failing detail names the stub"
  assert_eq 1 "$RUN_EXIT" "docblock reworded: exit code"
  assert_summary "WAVE-CHECK RESULT: FAIL (1 failed)" "docblock reworded: summary line"
}

test_contract_diff_fail_when_a_docblock_line_is_removed() {
  local repo cmd ref
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"
  commit_stub "$repo" "src/thing.sh" "do_thing" "Does the thing." "scaffold src/thing.sh"
  ref="$(git -C "$repo" rev-parse HEAD)"
  commit_sed "$repo" "src/thing.sh" '/^#   - the input argument\.$/d' "drop a contract clause"

  run_wave "$repo" impl --test-cmd "$cmd" --scaffold-ref "$ref" --stub src/thing.sh
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "FAIL" "a line inside the contract docblock was deleted"
  assert_contains "$(check_line "$RUN_OUT" "CONTRACT-DIFF")" "src/thing.sh" "docblock line deleted: the failing detail names the stub"
  assert_eq 1 "$RUN_EXIT" "docblock line deleted: exit code"
}

# "...or any signature line present at <ref>, was changed or removed" — the
# docblock is left byte-identical here, so only the signature half of the
# clause can catch this.
test_contract_diff_fail_when_a_signature_line_is_changed() {
  local repo cmd ref
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"
  commit_stub "$repo" "src/thing.sh" "do_thing" "Does the thing." "scaffold src/thing.sh"
  ref="$(git -C "$repo" rev-parse HEAD)"
  commit_sed "$repo" "src/thing.sh" 's/^do_thing() {$/do_the_thing() {/' "rename the public function"

  local docblock_now docblock_ref
  docblock_now="$(sed -n '/^# <!--$/,/^# -->$/p' "$repo/src/thing.sh")"
  docblock_ref="$(git -C "$repo" show "$ref:src/thing.sh" | sed -n '/^# <!--$/,/^# -->$/p')"
  if [ "$docblock_now" != "$docblock_ref" ]; then
    record_fail "fixture bug: the docblock must be byte-identical to <ref> so only the signature change can be caught"
    return
  fi

  run_wave "$repo" impl --test-cmd "$cmd" --scaffold-ref "$ref" --stub src/thing.sh
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "FAIL" "the signature line present at <ref> was renamed"
  assert_contains "$(check_line "$RUN_OUT" "CONTRACT-DIFF")" "src/thing.sh" "signature renamed: the failing detail names the stub"
  assert_eq 1 "$RUN_EXIT" "signature renamed: exit code"
}

# EC: "A --stub path that does not exist at <ref> (new file since scaffold):
# CONTRACT-DIFF FAIL naming the path."
test_contract_diff_fail_when_stub_missing_at_ref() {
  local repo cmd ref
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"
  ref="$(git -C "$repo" rev-parse HEAD)"
  commit_stub "$repo" "src/latecomer.sh" "do_late" "Arrived after scaffold." "add a stub that did not exist at scaffold"

  run_wave "$repo" impl --test-cmd "$cmd" --scaffold-ref "$ref" --stub src/latecomer.sh
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "FAIL" "stub absent at <ref>: the surface moved"
  assert_contains "$(check_line "$RUN_OUT" "CONTRACT-DIFF")" "src/latecomer.sh" "stub absent at <ref>: the failing detail names the path"
  assert_eq 1 "$RUN_EXIT" "stub absent at <ref>: exit code"
}

# --stub is repeatable, and however many stubs are named the check still
# contributes exactly one output line.
test_contract_diff_stub_flag_is_repeatable() {
  local repo cmd ref
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"
  commit_stub "$repo" "src/alpha.sh" "do_alpha" "Does alpha." "scaffold src/alpha.sh"
  commit_stub "$repo" "src/beta.sh" "do_beta" "Does beta." "scaffold src/beta.sh"
  ref="$(git -C "$repo" rev-parse HEAD)"

  # Both clean: one PASS line.
  run_wave "$repo" impl --test-cmd "$cmd" --scaffold-ref "$ref" --stub src/alpha.sh --stub src/beta.sh
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "PASS" "two untouched stubs"
  assert_shape "GREEN-RUN" "two untouched stubs: still exactly one line per check"
  assert_eq 0 "$RUN_EXIT" "two untouched stubs: exit code (stderr: $RUN_ERR)"

  # Second one's contract reworded: one FAIL line naming it.
  commit_sed "$repo" "src/beta.sh" 's/^#   Does beta\.$/#   Does gamma./' "reword beta's contract"
  run_wave "$repo" impl --test-cmd "$cmd" --scaffold-ref "$ref" --stub src/alpha.sh --stub src/beta.sh
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "FAIL" "one of two stubs had its contract reworded"
  assert_contains "$(check_line "$RUN_OUT" "CONTRACT-DIFF")" "src/beta.sh" "one dirty stub of two: the failing detail names the dirty one"
  assert_shape "GREEN-RUN" "one dirty stub of two: still exactly one line per check"
  assert_eq 1 "$RUN_EXIT" "one dirty stub of two: exit code"
}

# "--scaffold-ref <ref>: ... in test mode it is ignored with a warning on
# stderr" — ignored means the stub is not compared even though it is dirty.
test_scaffold_ref_ignored_in_test_mode_with_a_warning() {
  local repo cmd ref
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"
  commit_stub "$repo" "src/thing.sh" "do_thing" "Does the thing." "scaffold src/thing.sh"
  ref="$(git -C "$repo" rev-parse HEAD)"
  commit_sed "$repo" "src/thing.sh" 's/^#   Does the thing\.$/#   Does something else entirely./' "reword the contract"

  run_wave "$repo" test --test-cmd "$cmd" --scaffold-ref "$ref" --stub src/thing.sh
  [ -n "$RUN_ERR" ] || record_fail "test mode with --scaffold-ref: expected a warning on stderr"
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "SKIPPED" "test mode: --scaffold-ref is ignored, so no contract comparison happens"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "test mode with an ignored --scaffold-ref: red run unaffected"
  assert_summary "WAVE-CHECK RESULT: PASS" "test mode with an ignored --scaffold-ref: summary line"
  assert_eq 0 "$RUN_EXIT" "test mode with an ignored --scaffold-ref: exit code"
}

# ===========================================================================
# Output format and the captured-output temp file
# (Outputs clause; Invariants: exit codes; SKIPPED carries its reason)
# ===========================================================================

# Every stdout line is a WAVE-CHECK line — the test command's own output
# never leaks onto stdout, in either mode, passing or failing.
test_stdout_carries_nothing_but_wave_check_lines() {
  local repo cmd line
  repo="$(new_git_repo)"
  cmd="$(make_test_cmd 1 "DISTINCTIVE-STDOUT-MARKER" "DISTINCTIVE-STDERR-MARKER" "" "")"
  write_untracked "$repo" "src/widget.js" "function widget() {}"

  # Test mode, mixed verdicts (RED-RUN PASS, REALM FAIL).
  run_wave "$repo" test --test-cmd "$cmd"
  assert_shape "RED-RUN" "mixed-verdict test-mode run: output shape"
  while IFS= read -r line; do
    case "$line" in
      "WAVE-CHECK "*) : ;;
      *) record_fail "stdout must contain nothing but WAVE-CHECK lines, got: [$line]" ;;
    esac
  done <<< "$RUN_OUT"
  case "$RUN_OUT" in
    *DISTINCTIVE-STDOUT-MARKER*|*DISTINCTIVE-STDERR-MARKER*)
      record_fail "the test command's own output must not leak onto stdout (stdout: $RUN_OUT)" ;;
  esac

  # Impl mode, all three checks failing.
  run_wave "$repo" impl --test-cmd "$cmd"
  assert_shape "GREEN-RUN" "impl-mode run with a failing suite: output shape"
  case "$RUN_OUT" in
    *DISTINCTIVE-STDOUT-MARKER*|*DISTINCTIVE-STDERR-MARKER*)
      record_fail "impl mode: the test command's own output must not leak onto stdout (stdout: $RUN_OUT)" ;;
  esac
}

# Every check line's status token is one of the three legal values.
test_status_tokens_are_legal() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_status_token "$(check_status "$RUN_OUT" "RED-RUN")" "test mode RED-RUN"
  assert_status_token "$(check_status "$RUN_OUT" "REALM")" "test mode REALM"
  assert_status_token "$(check_status "$RUN_OUT" "CONTRACT-DIFF")" "test mode CONTRACT-DIFF"

  cmd="$(green_cmd)"
  run_wave "$repo" impl --test-cmd "$cmd"
  assert_status_token "$(check_status "$RUN_OUT" "GREEN-RUN")" "impl mode GREEN-RUN"
  assert_status_token "$(check_status "$RUN_OUT" "REALM")" "impl mode REALM"
  assert_status_token "$(check_status "$RUN_OUT" "CONTRACT-DIFF")" "impl mode CONTRACT-DIFF"
}

# The summary counts FAILs, and only FAILs: a SKIPPED check alongside two
# failures still reports "(2 failed)".
test_summary_counts_only_failures() {
  local repo cmd
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"
  write_untracked "$repo" "src/widget.test.js" "it('x', () => {})"

  # impl mode: GREEN-RUN FAIL (command exits 1) + REALM FAIL (a test-family
  # file changed) + CONTRACT-DIFF SKIPPED.
  run_wave "$repo" impl --test-cmd "$cmd"
  assert_check "$RUN_OUT" "GREEN-RUN" "FAIL" "two-failure run: green run"
  assert_check "$RUN_OUT" "REALM" "FAIL" "two-failure run: realm"
  assert_check "$RUN_OUT" "CONTRACT-DIFF" "SKIPPED" "two-failure run: contract diff"
  assert_summary "WAVE-CHECK RESULT: FAIL (2 failed)" "two failures and one skip: the count is of FAILs only"
  assert_eq 1 "$RUN_EXIT" "two-failure run: exit code"
}

# "SKIPPED ... is always accompanied by its reason in the detail" — so a
# SKIPPED line is never the bare "WAVE-CHECK <CHECK>: SKIPPED" with nothing
# after it, in either mode.
test_skipped_always_carries_its_reason() {
  local repo cmd line ref
  repo="$(new_git_repo)"
  cmd="$(green_cmd)"

  run_wave "$repo" impl --test-cmd "$cmd"
  line="$(check_line "$RUN_OUT" "CONTRACT-DIFF")"
  assert_eq "SKIPPED" "$(check_status "$RUN_OUT" "CONTRACT-DIFF")" "impl mode without --scaffold-ref: skipped"
  if [ "$line" = "WAVE-CHECK CONTRACT-DIFF: SKIPPED" ]; then
    record_fail "impl mode: SKIPPED must be accompanied by its reason, got a bare [$line]"
  fi

  # Test mode, where --scaffold-ref is ignored: the skip still says why.
  ref="$(git -C "$repo" rev-parse HEAD)"
  cmd="$(red_cmd)"
  run_wave "$repo" test --test-cmd "$cmd" --scaffold-ref "$ref"
  line="$(check_line "$RUN_OUT" "CONTRACT-DIFF")"
  assert_eq "SKIPPED" "$(check_status "$RUN_OUT" "CONTRACT-DIFF")" "test mode with an ignored --scaffold-ref: skipped"
  if [ "$line" = "WAVE-CHECK CONTRACT-DIFF: SKIPPED" ]; then
    record_fail "test mode: SKIPPED must be accompanied by its reason, got a bare [$line]"
  fi
}

# Outputs: "The test command's full output is captured to a temp file; the
# path is printed in the failing check's detail for triage, and the file is
# left in place on failure, removed on overall PASS." Observed by handing
# the script a private $TMPDIR (Invariant: "temp files live under
# ${TMPDIR:-/tmp}").
test_captured_output_temp_file_lifecycle() {
  local repo tmp cmd path
  repo="$(new_git_repo)"
  tmp="$(new_tmpdir)"
  cmd="$(make_test_cmd 1 "CAPTURED-STDOUT-MARKER" "CAPTURED-STDERR-MARKER" "" "")"

  # Failing GREEN-RUN: the path appears in that check's detail, under our
  # $TMPDIR, and the file survives with the command's full output in it.
  run_wave_env "$repo" "" "" "$tmp" impl --test-cmd "$cmd"
  assert_check "$RUN_OUT" "GREEN-RUN" "FAIL" "captured-output fixture: the suite must fail for the path to be printed"
  path="$(check_line "$RUN_OUT" "GREEN-RUN" | grep -o "$tmp/[^[:space:]]*" | head -n1)"
  if [ -z "$path" ]; then
    record_fail "failing check's detail does not name a temp-file path under \$TMPDIR (line: $(check_line "$RUN_OUT" "GREEN-RUN"))"
  else
    if [ ! -f "$path" ]; then
      record_fail "the captured-output file must be left in place on failure, but $path does not exist"
    else
      assert_contains "$(cat "$path")" "CAPTURED-STDOUT-MARKER" "captured-output file holds the command's stdout"
      assert_contains "$(cat "$path")" "CAPTURED-STDERR-MARKER" "captured-output file holds the command's stderr (full, combined output)"
    fi
  fi

  # Overall PASS: nothing holding the command's output is left behind.
  local tmp2 green
  tmp2="$(new_tmpdir)"
  green="$(make_test_cmd 0 "CAPTURED-STDOUT-MARKER" "" "" "")"
  run_wave_env "$repo" "" "" "$tmp2" impl --test-cmd "$green"
  assert_eq 0 "$RUN_EXIT" "captured-output PASS fixture: exit code (stderr: $RUN_ERR)"
  if [ -n "$(grep -rl 'CAPTURED-STDOUT-MARKER' "$tmp2" 2>/dev/null)" ]; then
    record_fail "the captured-output file must be removed on overall PASS, but $tmp2 still holds it"
  fi
}

# ===========================================================================
# Invariants
# ===========================================================================

# "The test command is never piped; its exit code is taken from $? immediately
# after the bare invocation (output redirected to the temp file — redirection,
# not a pipeline)." The command reports what its own fd 1 and fd 2 are
# connected to, into a side file outside the repo.
test_test_command_is_never_piped() {
  local repo probe cmd
  repo="$(new_git_repo)"
  probe="$(mktemp)"
  track_tmp "$probe"
  cmd="$(make_raw_cmd "$(printf 'readlink /proc/self/fd/1 >> %q\nreadlink /proc/self/fd/2 >> %q\nexit 1' "$probe" "$probe")")"

  run_wave "$repo" test --test-cmd "$cmd"
  assert_check "$RUN_OUT" "RED-RUN" "PASS" "pipe-probe fixture: the probe exits 1, so the red run passes"

  local seen
  seen="$(cat "$probe")"
  if [ -z "$seen" ]; then
    record_fail "pipe probe never ran (no fd information recorded) — the resolved test command was not invoked"
    return
  fi
  case "$seen" in
    *pipe:*) record_fail "the test command's output must be REDIRECTED to a temp file, not piped; its fds resolved to: $seen" ;;
  esac
}

# "Read-only with respect to the repository: never modifies tracked files,
# the index, or git state." Checked across passing, failing and error paths.
test_read_only_with_respect_to_the_repository() {
  local repo cmd ref status_before status_after head_before head_after refs_before refs_after content_before content_after
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"
  commit_stub "$repo" "src/thing.sh" "do_thing" "Does the thing." "scaffold src/thing.sh"
  ref="$(git -C "$repo" rev-parse HEAD)"
  write_untracked "$repo" "src/widget.js" "function widget() {}"

  status_before="$(git -C "$repo" status --porcelain)"
  head_before="$(git -C "$repo" rev-parse HEAD)"
  refs_before="$(git -C "$repo" show-ref)"
  content_before="$(cat "$repo/src/thing.sh")"

  run_wave "$repo" test --test-cmd "$cmd"
  # Pin one verdict so a script that did nothing at all cannot satisfy the
  # read-only claim vacuously.
  assert_shape "RED-RUN" "read-only fixture: the first run must really have run"
  assert_check "$RUN_OUT" "REALM" "FAIL" "read-only fixture: the untracked impl file makes this test-mode run fail"
  run_wave "$repo" impl --test-cmd "$cmd" --scaffold-ref "$ref" --stub src/thing.sh
  run_wave "$repo" impl --test-cmd "$cmd" --scaffold-ref "$ref" --stub src/never-existed.sh
  run_wave "$repo" test --test-cmd "$cmd" "HEAD~1..HEAD"
  run_wave "$repo" bogus-mode --test-cmd "$cmd"
  run_wave "$repo" test

  status_after="$(git -C "$repo" status --porcelain)"
  head_after="$(git -C "$repo" rev-parse HEAD)"
  refs_after="$(git -C "$repo" show-ref)"
  content_after="$(cat "$repo/src/thing.sh")"

  assert_eq "$status_before" "$status_after" "read-only: git status unchanged across passing, failing and error runs"
  assert_eq "$head_before" "$head_after" "read-only: HEAD unchanged"
  assert_eq "$refs_before" "$refs_after" "read-only: refs unchanged"
  assert_eq "$content_before" "$content_after" "read-only: a named stub's contents unchanged"
}

# "Exit codes: 0 (all checks PASS or SKIPPED), 1 (any FAIL), 2
# (usage/environment) — never anything else." In particular the stub's own 70
# must never surface, and a FAIL must never be reported as 2.
test_exit_codes_are_only_0_1_2() {
  local repo cmd ec
  repo="$(new_git_repo)"

  cmd="$(red_cmd)"
  run_wave "$repo" test --test-cmd "$cmd"
  ec="$RUN_EXIT"
  assert_eq 0 "$ec" "all checks PASS or SKIPPED: exit 0"

  run_wave "$repo" impl --test-cmd "$cmd"
  ec="$RUN_EXIT"
  assert_eq 1 "$ec" "a check FAILed: exit 1, never conflated with the environment code 2"

  run_wave "$repo" test --test-cmd /nonexistent/definitely-not-a-command
  case "$RUN_EXIT" in 0|1|2) : ;; *) record_fail "unrunnable test command: exit code $RUN_EXIT not in {0,1,2}" ;; esac

  run_wave "$repo" --test-cmd "$cmd"
  ec="$RUN_EXIT"
  assert_eq 2 "$ec" "no mode positional: exit 2"

  local dir
  dir="$(mktemp -d)"
  track_tmp "$dir"
  run_wave "$dir" test --test-cmd "$cmd"
  ec="$RUN_EXIT"
  assert_eq 2 "$ec" "outside a git worktree: exit 2"
}

# Determinism: the same repo state and the same arguments produce the same
# stdout and the same exit code.
test_deterministic_across_repeat_runs() {
  local repo cmd out1 out2 ec1 ec2
  repo="$(new_git_repo)"
  cmd="$(red_cmd)"
  write_untracked "$repo" "src/widget.js" "function widget() {}"

  run_wave "$repo" test --test-cmd "$cmd"
  out1="$RUN_OUT"; ec1="$RUN_EXIT"
  # Pin the shape so "identical output" cannot be satisfied by producing
  # nothing twice.
  assert_shape "RED-RUN" "determinism fixture: the run must really have run"
  run_wave "$repo" test --test-cmd "$cmd"
  out2="$RUN_OUT"; ec2="$RUN_EXIT"

  assert_eq "$ec1" "$ec2" "determinism: exit code differs across two identical runs"
  assert_eq "$out1" "$out2" "determinism: stdout differs across two identical runs"
}

# ===========================================================================
# main
# ===========================================================================

run_test "usage: no mode positional -> exit 2" test_usage_missing_mode
run_test "usage: unknown mode -> exit 2" test_usage_unknown_mode
run_test "usage: unknown flag -> exit 2" test_usage_unknown_flag
run_test "usage: flag missing its value -> exit 2" test_usage_flag_missing_its_value

run_test "env: not inside a git worktree -> exit 2" test_not_inside_a_git_repository
run_test "env: realm-check.sh not beside the script -> exit 2" test_realm_check_missing_beside_script

run_test "test command: unresolvable -> exit 2" test_unresolvable_test_command_exit_2
run_test "test command: jq required for config resolution -> exit 2" test_jq_required_when_config_resolution_needed
run_test "test command: --test-cmd needs no jq and no config" test_no_jq_needed_when_test_cmd_given
run_test "test command: commands.test string from base config" test_config_test_cmd_string_from_base
run_test "test command: object commands.test uses its default variant" test_config_test_cmd_object_uses_default_variant
run_test "test command: override config wins over base" test_config_override_wins_over_base
run_test "test command: \$LEGO_CONFIG redirects the override path" test_lego_config_env_redirects_override_path

run_test "RED-RUN: honest red -> PASS" test_red_run_pass_on_honest_red
run_test "RED-RUN: command exits 0 -> FAIL" test_red_run_fail_when_test_command_exits_zero
run_test "RED-RUN: non-zero with empty output -> PASS" test_red_run_pass_on_silent_red
run_test "RED-RUN: default collection pattern alternatives -> FAIL COLLECTION" test_red_run_collection_fail_default_pattern
run_test "RED-RUN: collection error on stderr is still detected" test_red_run_collection_detected_on_stderr_too
run_test "RED-RUN: conservative match, then --collection-pattern escape hatch" test_collection_pattern_conservative_then_overridden
run_test "RED-RUN: --collection-pattern replaces the default and is an ERE" test_collection_pattern_override_is_an_ere
run_test "RED-RUN: test-framework success lines are excluded from the scan" test_red_run_success_lines_are_not_scanned
run_test "RED-RUN: a 'not ok' line is not a success line" test_red_run_not_ok_line_is_still_scanned
run_test "RED-RUN: passing output does not mask a real collection error" test_red_run_success_lines_do_not_mask_a_real_collection_error
run_test "RED-RUN: a trailing success marker does not exclude the line" test_red_run_trailing_success_marker_is_still_scanned
run_test "RED-RUN: the success-line exclusion applies to stderr too" test_red_run_success_line_exclusion_applies_to_stderr
run_test "RED-RUN: a --test-cmd containing exit does not terminate wave-check" test_test_cmd_containing_exit_does_not_terminate_wave_check

run_test "GREEN-RUN: green suite -> PASS" test_green_run_pass_on_green
run_test "GREEN-RUN: non-zero -> FAIL" test_green_run_fail_on_nonzero
run_test "GREEN-RUN: non-zero with empty output -> FAIL" test_green_run_fail_on_silent_nonzero
run_test "GREEN-RUN: collection pattern is not consulted in impl mode" test_impl_mode_ignores_collection_pattern

run_test "REALM: test mode, non-test file changed -> FAIL" test_realm_fail_in_test_mode_when_impl_file_changed
run_test "REALM: test mode, only test files changed -> PASS" test_realm_pass_in_test_mode_when_only_test_files_changed
run_test "REALM: impl mode, test file changed -> FAIL" test_realm_fail_in_impl_mode_when_test_file_changed
run_test "REALM: impl mode, only impl files changed -> PASS" test_realm_pass_in_impl_mode_when_only_impl_files_changed
run_test "REALM: trailing diff-range is passed through verbatim" test_trailing_diff_range_is_passed_through
run_test "REALM: empty diff-range passes its verdict through" test_empty_diff_range_passes_through_its_verdict

run_test "CONTRACT-DIFF: no --scaffold-ref -> SKIPPED, visible" test_contract_diff_skipped_without_scaffold_ref
run_test "CONTRACT-DIFF: --scaffold-ref with no --stub -> vacuous PASS" test_contract_diff_vacuous_pass_without_stubs
run_test "CONTRACT-DIFF: body implemented, contract intact -> PASS" test_contract_diff_pass_when_only_the_body_was_implemented
run_test "CONTRACT-DIFF: docblock line changed -> FAIL" test_contract_diff_fail_when_a_docblock_line_is_changed
run_test "CONTRACT-DIFF: docblock line removed -> FAIL" test_contract_diff_fail_when_a_docblock_line_is_removed
run_test "CONTRACT-DIFF: signature line changed -> FAIL" test_contract_diff_fail_when_a_signature_line_is_changed
run_test "CONTRACT-DIFF: stub missing at <ref> -> FAIL naming the path" test_contract_diff_fail_when_stub_missing_at_ref
run_test "CONTRACT-DIFF: --stub is repeatable, still one line" test_contract_diff_stub_flag_is_repeatable
run_test "CONTRACT-DIFF: --scaffold-ref ignored in test mode, with a warning" test_scaffold_ref_ignored_in_test_mode_with_a_warning

run_test "output: stdout carries nothing but WAVE-CHECK lines" test_stdout_carries_nothing_but_wave_check_lines
run_test "output: every status token is PASS|FAIL|SKIPPED" test_status_tokens_are_legal
run_test "output: the summary counts FAILs only" test_summary_counts_only_failures
run_test "output: SKIPPED always carries its reason" test_skipped_always_carries_its_reason
run_test "output: captured-output temp file named on failure, removed on pass" test_captured_output_temp_file_lifecycle

run_test "invariant: the test command is never piped" test_test_command_is_never_piped
run_test "invariant: read-only with respect to the repository" test_read_only_with_respect_to_the_repository
run_test "invariant: exit codes are only 0, 1 or 2" test_exit_codes_are_only_0_1_2
run_test "invariant: deterministic across repeat runs" test_deterministic_across_repeat_runs

echo "---"
echo "Passed: $TOTAL_PASS  Failed: $TOTAL_FAIL  Total: $((TOTAL_PASS + TOTAL_FAIL))"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
