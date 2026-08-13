#!/usr/bin/env bash
# blocks-lint.test.sh — contract tests for blocks-lint.sh (B04 blocks-lint,
# plan 001-improve-lego-decomposition-and-parallelism).
#
# Self-contained bash test harness (no bats), mirroring the style of
# pr-size-check.test.sh / realm-gate.test.sh. Black-box only: every test
# builds a throwaway block map under mktemp, invokes blocks-lint.sh through
# its public CLI (--budget, an optional positional path, the default
# .local/blocks.md, $LEGO_CONFIG, $JQ) and asserts on its real
# exit code, stdout finding/summary lines, and stderr — never on internals.
#
# Run directly: `bash blocks-lint.test.sh`. Exits 0 when every test passes,
# 1 when any test fails, 2 on an environment error of the suite itself.
# <!--
# Contract: B11 blocks-lint-dependency-injection (plan 001-speed-up-repo-ci)
#
# Behavior:
#   The `path_without` helper below — which rebuilds a whole PATH-minus-jq
#   symlink farm on every call — is deleted outright, together with the
#   `PATH_NO_JQ` / `path_no_jq` memo wrapper that fronts it. The five
#   jq-absence sites drive `blocks-lint.sh`'s new `: "${JQ:=jq}"` seam
#   directly, by setting JQ=/nonexistent in the environment of the single
#   invocation under test, instead of reconstructing PATH.
#
#   This mirrors B04, which made exactly this change to realm-gate.test.sh,
#   pr-size-check.test.sh and worktree.test.sh. blocks-lint.sh predates that
#   conversion and is the fourth script to receive the same seam: every
#   `jq` in command position becomes `"$JQ"`, and `command -v jq` becomes
#   `command -v "$JQ"`. Error-message strings mentioning jq are NOT touched.
#
# Inputs:  unchanged — the same block-map fixtures and the same CLI.
# Outputs: unchanged — `Passed: 35  Failed: 0  Total: 35`.
#
# Errors:
#   Unchanged. In particular the jq-required diagnostic and its exit 2 must
#   fire identically whether jq is absent from PATH or JQ names a
#   nonexistent path: both are detected through `command -v "$JQ"`.
#
# Invariants:
#   - Pass count is EXACTLY 35, failures EXACTLY 0. A changed count is a
#     defect, not an improvement, whichever direction it moves.
#   - No assertion may be weakened, skipped, merged, or deleted.
#   - blocks-lint.sh's observable behaviour is unchanged on every path:
#     stdout, stderr and exit code byte-identical, jq present or absent.
#   - Zero `basename` and zero `ln` spawns from this suite. The current
#     figures are 39,465 and 17,800 — five surviving calls to the helper
#     (the memo is dead, because a `PATH_NO_JQ=` assignment inside command
#     substitution dies with the subshell) across 7,895 files on $PATH.
#   - No wall-clock assertion anywhere in this file.
#
# Edge cases:
#   - `JQ=""` must degrade to the default rather than to an empty command,
#     which is why the seam uses `:=` and not `:-`.
#   - The seam must not be exported: it applies to the invocation under
#     test, never to the suite's own jq calls, which build fixtures and must
#     keep working.
# -->
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/blocks-lint.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: script under test not found at $SCRIPT" >&2
  exit 2
fi

# The suite's own prerequisites. jq builds the config-resolution fixtures
# (the script's own jq requirement is exercised separately, by pointing $JQ
# at a nonexistent path); git backs the read-only invariant and the
# cwd-relative default-path fixtures.
for tool in jq git md5sum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "FATAL: this suite requires $tool on \$PATH" >&2
    exit 2
  fi
done
if [ "$(id -u)" -eq 0 ]; then
  echo "FATAL: refusing to run as root (the unreadable-file fixture relies on chmod 000 actually denying reads)" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Cleanup registry (command substitution forks a subshell, so a file-based
# manifest is needed to survive it — see pr-size-check.test.sh).
# ---------------------------------------------------------------------------
CLEANUP_MANIFEST="$(mktemp)"

track_tmp() {
  printf '%s\n' "$1" >> "$CLEANUP_MANIFEST"
}

cleanup() {
  if [ -f "$CLEANUP_MANIFEST" ]; then
    while IFS= read -r d; do
      [ -e "$d" ] || continue
      chmod -R u+rwX -- "$d" 2>/dev/null
      rm -rf -- "$d"
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
# <args...> — runs blocks-lint.sh with cwd <dir>, optionally overriding $PATH
# and/or $LEGO_CONFIG (the override-path redirection seam). Sets RUN_OUT /
# RUN_ERR / RUN_EXIT / RUN_OUT_LINES. To exercise the jq-absent paths, prefix
# the call with JQ=/nonexistent (e.g. `JQ=/nonexistent run_in "$dir"`) — bash
# exports a prefix assignment into the environment of everything the function
# invokes, including the `bash "$SCRIPT"` below.
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

# run_in <dir> <args...>  (default $PATH, default $LEGO_CONFIG)
run_in() {
  local dir="$1"
  shift
  run_cmd "$dir" "" "" "$@"
}

# ---------------------------------------------------------------------------
# Block-map fixture builders.
#
# block <id> <est> — a well-formed entry in the block map's real shape (the
# plan skill's Step 4 template). <est> is emitted VERBATIM after "- Est: ",
# so callers can pass malformed values ("1,200", "", "~200") to exercise the
# integer rule; the sentinel NO_EST omits the field entirely.
# ---------------------------------------------------------------------------
block() {
  local id="$1" est="$2"
  printf '## %s — %s widget\n' "$id" "$id"
  printf -- '- Status: Planned\n'
  printf -- '- Owner: agent\n'
  printf -- '- Kind: leaf\n'
  printf -- '- Deps: none\n'
  printf -- '- Unit: U01\n'
  printf -- '- PR group: G01\n'
  if [ "$est" != "NO_EST" ]; then
    printf -- '- Est: %s\n' "$est"
  fi
  printf -- '- Code: src/%s.ts\n' "$id"
  printf -- '- Contract: does a thing\n'
  printf -- '- Plan: plans/001-x.md\n'
}

# block_j <id> <est> <justification> — same, with a Justification field
# carrying its value on the same line.
block_j() {
  local id="$1" est="$2" just="$3"
  printf '## %s — %s widget\n' "$id" "$id"
  printf -- '- Status: Planned\n'
  printf -- '- Owner: agent\n'
  printf -- '- Kind: leaf\n'
  printf -- '- Deps: none\n'
  printf -- '- Unit: U01\n'
  printf -- '- PR group: G01\n'
  printf -- '- Est: %s\n' "$est"
  printf -- '- Justification: %s\n' "$just"
  printf -- '- Code: src/%s.ts\n' "$id"
  printf -- '- Contract: does a thing\n'
  printf -- '- Plan: plans/001-x.md\n'
}

MAP_HEADER='# Block Map

The contract-level view of this system.
'

# render_map <part...> — the standard block-map header followed by each part,
# each terminated by a blank line. Parts are passed as separate arguments
# (command substitution strips trailing newlines, so concatenating
# "$(block ...)$(block ...)" would run two entries together).
render_map() {
  printf '%s\n' "$MAP_HEADER"
  local part
  for part in "$@"; do
    printf '%s\n\n' "$part"
  done
}

# new_map_dir <part...> — a fresh tracked dir whose .local/blocks.md (the
# default path) holds the rendered map. Prints the dir.
new_map_dir() {
  local dir
  dir="$(mktemp -d)"
  track_tmp "$dir"
  mkdir -p "$dir/.local"
  render_map "$@" > "$dir/.local/blocks.md"
  printf '%s' "$dir"
}

# write_map_at <dir> <relpath> <part...> — the same map, somewhere else.
write_map_at() {
  local dir="$1" rel="$2"
  shift 2
  mkdir -p "$(dirname "$dir/$rel")"
  render_map "$@" > "$dir/$rel"
}

# write_file_at <dir> <relpath> <content> — content written verbatim.
write_file_at() {
  local dir="$1" rel="$2" content="$3"
  mkdir -p "$(dirname "$dir/$rel")"
  printf '%s' "$content" > "$dir/$rel"
}

# budget_json <n> — {"delivery":{"prSizeBudget": <n>}}, the shape
# docs/config-schema.md documents for delivery.* fields.
budget_json() {
  printf '{"delivery":{"prSizeBudget": %s}}' "$1"
}

# ---------------------------------------------------------------------------
# Output assertions.
#
# Outputs clause: "one line per finding, format LINT B<NN>: <problem> (or
# LINT <file>: <problem> for file-level findings), then a blank line and
# either ALL PASS (<n> blocks, ceiling <c>) or FAILURES: <count> — fix the
# block map before scaffolding".
# ---------------------------------------------------------------------------
out_line() {
  printf '%s\n' "$RUN_OUT" | sed -n "$1p"
}

# assert_clean_structure <expected-summary-line> <label> — a clean run: the
# exact summary line and no findings. The contract's blank separator has
# nothing to separate when no finding was printed, so both a bare summary
# line and blank-then-summary are accepted; the summary text and the absence
# of findings are what is pinned.
assert_clean_structure() {
  local expected="$1" label="$2"
  case "$RUN_OUT_LINES" in
    1)
      assert_eq "$expected" "$(out_line 1)" "$label: summary line"
      ;;
    2)
      assert_eq "" "$(out_line 1)" "$label: the line before the summary must be the contract's blank separator"
      assert_eq "$expected" "$(out_line 2)" "$label: summary line"
      ;;
    *)
      record_fail "$label: expected the summary line alone (optionally preceded by the blank separator), got $RUN_OUT_LINES stdout line(s): [$RUN_OUT]"
      ;;
  esac
  case "$RUN_OUT" in
    *"LINT "*) record_fail "$label: a clean map must print no LINT finding line (stdout: $RUN_OUT)" ;;
  esac
}

# assert_findings_structure <expected-summary-line> <label> — a run with
# findings: every line up to the last two is a "LINT " finding, then a blank
# line, then the exact summary line.
assert_findings_structure() {
  local expected="$1" label="$2"
  local n="$RUN_OUT_LINES"
  if [ "$n" -lt 3 ]; then
    record_fail "$label: expected at least one finding line, a blank line and the summary, got $n stdout line(s): [$RUN_OUT]"
    return
  fi
  assert_eq "$expected" "$(out_line "$n")" "$label: summary line"
  assert_eq "" "$(out_line "$((n - 1))")" "$label: blank line separating the findings from the summary"
  local i line
  for i in $(seq 1 $((n - 2))); do
    line="$(out_line "$i")"
    case "$line" in
      "LINT "*) : ;;
      *) record_fail "$label: stdout line $i is neither a finding nor part of the summary block: [$line]" ;;
    esac
  done
}

# assert_block_finding <id> <keyword-regex> <label> — a block-level finding
# in the contracted "LINT B<NN>: <problem>" form whose problem text mentions
# <keyword-regex> (matched case-insensitively; the exact wording of
# <problem> is deliberately not pinned).
assert_block_finding() {
  local id="$1" re="$2" label="$3" line
  line="$(printf '%s\n' "$RUN_OUT" | grep -m1 "^LINT $id: ")"
  if [ -z "$line" ]; then
    record_fail "$label: expected a finding line \"LINT $id: <problem>\", got stdout: [$RUN_OUT]"
    return
  fi
  if ! printf '%s\n' "$line" | grep -qiE "$re"; then
    record_fail "$label: the finding for $id does not mention /$re/: [$line]"
  fi
}

# assert_no_block_finding <id> <label>
assert_no_block_finding() {
  local id="$1" label="$2"
  if printf '%s\n' "$RUN_OUT" | grep -q "^LINT $id: "; then
    record_fail "$label: expected no finding for $id, got: [$(printf '%s\n' "$RUN_OUT" | grep -m1 "^LINT $id: ")]"
  fi
}

# assert_no_summary <label> — an exit-2 usage/environment error must not
# emit a lint verdict on stdout.
assert_no_summary() {
  local label="$1"
  case "$RUN_OUT" in
    *"ALL PASS"*|*"FAILURES:"*)
      record_fail "$label: a usage/environment error must not print a lint summary (stdout: $RUN_OUT)" ;;
  esac
}

# assert_usage_error <label> — exit 2, a diagnostic on stderr, no verdict.
assert_usage_error() {
  local label="$1"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "$label: expected exit 2, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  [ -n "$RUN_ERR" ] || record_fail "$label: expected a diagnostic on stderr"
  assert_no_summary "$label"
}

# ===========================================================================
# Inputs / usage errors (Inputs; Errors clause 1)
# ===========================================================================

# Unknown flag: diagnostic on stderr, exit 2.
test_usage_unknown_flag() {
  local dir
  dir="$(new_map_dir "$(block B01 100)")"

  run_in "$dir" --frobnicate
  assert_usage_error "unknown flag"

  run_in "$dir" --frobnicate .local/blocks.md
  assert_usage_error "unknown flag alongside a valid positional"
}

# --budget with no value at all, and --budget swallowing the positional
# (which is then not an integer): exit 2 either way.
test_usage_budget_missing_value() {
  local dir
  dir="$(new_map_dir "$(block B01 100)")"

  run_in "$dir" --budget
  assert_usage_error "--budget with nothing after it"

  run_in "$dir" --budget .local/blocks.md
  assert_usage_error "--budget as the last flag, positional consumed as its value"
}

# --budget with a non-integer or non-positive value: exit 2. 0 is included
# explicitly — a zero budget derives a zero ceiling, which is a caller bug,
# not a lint mode.
test_usage_budget_invalid_value() {
  local dir bad
  dir="$(new_map_dir "$(block B01 100)")"

  for bad in abc 5.5 -5 0 " " 1e3 "12,00"; do
    run_in "$dir" --budget "$bad"
    assert_usage_error "--budget [$bad]"
  done
}

# Exactly one positional argument is accepted; two is a usage error.
test_usage_more_than_one_positional() {
  local dir
  dir="$(new_map_dir "$(block B01 100)")"
  cp "$dir/.local/blocks.md" "$dir/other.md"

  run_in "$dir" .local/blocks.md other.md
  assert_usage_error "two positional paths"
}

# ===========================================================================
# Block-map file errors (Errors clauses 1-2)
# ===========================================================================

test_missing_file_is_exit_2() {
  local dir
  dir="$(mktemp -d)"
  track_tmp "$dir"

  run_in "$dir" no/such/blocks.md
  assert_usage_error "explicit path to a nonexistent file"

  run_in "$dir"
  assert_usage_error "default .local/blocks.md absent"
}

test_unreadable_file_is_exit_2() {
  local dir
  dir="$(new_map_dir "$(block B01 100)")"
  chmod 000 "$dir/.local/blocks.md"

  run_in "$dir"
  assert_usage_error "unreadable block map"

  chmod 644 "$dir/.local/blocks.md"
}

# A file with zero block entries is an environment error (exit 2), not a
# clean pass — linting nothing is far more likely a wrong path than a real
# empty plan.
test_zero_block_entries_is_exit_2() {
  local dir

  dir="$(new_map_dir)"
  run_in "$dir"
  assert_usage_error "header-only block map (no entries)"

  dir="$(mktemp -d)"
  track_tmp "$dir"
  mkdir -p "$dir/.local"
  : > "$dir/.local/blocks.md"
  run_in "$dir"
  assert_usage_error "completely empty file"

  # Only non-block "## " headings: those are ignored as entries (Edge case),
  # which leaves zero block entries.
  dir="$(new_map_dir '## Notes
- Status: this is prose, not a block
- Est: nonsense

## Status legend
- Planned means planned')"
  run_in "$dir"
  assert_usage_error "only non-block \"## \" headings"
}

# ===========================================================================
# Budget resolution and the derived ceiling
# (Behavior clauses 2-3; Inputs; Edge case: odd budget floors)
# ===========================================================================

# No --budget and no config file: the 500 default applies, ceiling 250, and
# jq is never needed because no config resolution happens.
test_default_budget_500_ceiling_250_no_jq_needed() {
  local dir
  dir="$(new_map_dir "$(block B01 250)" "$(block B02 1)")"

  JQ=/nonexistent run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "default budget, Est at the ceiling: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "default budget 500 derives ceiling 250"

  dir="$(new_map_dir "$(block B01 251)" "$(block B02 1)")"
  JQ=/nonexistent run_in "$dir"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "default budget, Est one over the ceiling: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 1 — fix the block map before scaffolding" "one over the default ceiling"
  assert_block_finding B01 "justif" "251 over the default ceiling of 250"
}

# --budget overrides the default, and the ceiling is the FLOOR of half the
# budget: 501 → 250, 99 → 49.
test_budget_flag_ceiling_is_floor_of_half() {
  local dir
  dir="$(new_map_dir "$(block B01 250)" "$(block B02 10)")"

  run_in "$dir" --budget 501
  [ "$RUN_EXIT" -eq 0 ] || record_fail "--budget 501, Est 250: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "odd budget 501 floors to ceiling 250"

  local dir2
  dir2="$(new_map_dir "$(block B01 251)" "$(block B02 10)")"
  run_in "$dir2" --budget 501
  [ "$RUN_EXIT" -eq 1 ] || record_fail "--budget 501, Est 251: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 1 — fix the block map before scaffolding" "251 over the floored ceiling 250"

  # A smaller budget, on a map sized to sit exactly on its ceiling, proves
  # the ceiling tracks the flag rather than being a constant — and that 99
  # floors to 49, not 50.
  local dir3
  dir3="$(new_map_dir "$(block B01 50)" "$(block B02 10)")"
  run_in "$dir3" --budget 100
  [ "$RUN_EXIT" -eq 0 ] || record_fail "--budget 100, Est 50: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 50)" "budget 100 derives ceiling 50"

  run_in "$dir3" --budget 99
  [ "$RUN_EXIT" -eq 1 ] || record_fail "--budget 99, Est 50 over ceiling 49: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 1 — fix the block map before scaffolding" "budget 99 floors to ceiling 49"
  assert_block_finding B01 "justif" "Est 50 over ceiling 49"
}

# delivery.prSizeBudget from the committed base layer alone.
test_budget_from_base_config() {
  local dir
  dir="$(new_map_dir "$(block B01 50)" "$(block B02 10)")"
  write_file_at "$dir" ".claude/lego.json" "$(budget_json 100)"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "base config budget 100, Est 50: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 50)" "budget resolved from .claude/lego.json"

  # Sharpened: the same map is a finding one line over that ceiling, so the
  # config value is really what set it (not a coincidental default pass).
  local dir2
  dir2="$(new_map_dir "$(block B01 51)" "$(block B02 10)")"
  write_file_at "$dir2" ".claude/lego.json" "$(budget_json 100)"
  run_in "$dir2"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "base config budget 100, Est 51: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 1 — fix the block map before scaffolding" "Est 51 over the config-derived ceiling 50"
}

# delivery.prSizeBudget from the local override layer alone (no base file).
test_budget_from_override_config() {
  local dir
  dir="$(new_map_dir "$(block B01 50)" "$(block B02 10)")"
  write_file_at "$dir" ".local/config.json" "$(budget_json 100)"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "override config budget 100, Est 50: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 50)" "budget resolved from .local/config.json"
}

# Both layers present: the override wins per key, and the merge is DEEP — a
# sibling key under .delivery in the override must not wipe the base's
# prSizeBudget (a shallow top-level merge would, falling back to 500 /
# ceiling 250).
test_config_deep_merge_override_wins() {
  local dir
  dir="$(new_map_dir "$(block B01 50)" "$(block B02 10)")"
  write_file_at "$dir" ".claude/lego.json" "$(budget_json 1000)"
  write_file_at "$dir" ".local/config.json" "$(budget_json 100)"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "override 100 over base 1000: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 50)" "the override layer wins over the base layer"

  local dir2
  dir2="$(new_map_dir "$(block B01 50)" "$(block B02 10)")"
  write_file_at "$dir2" ".claude/lego.json" "$(budget_json 100)"
  write_file_at "$dir2" ".local/config.json" '{"delivery":{"someOtherKey": true}}'

  run_in "$dir2"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "deep merge preserving the base prSizeBudget: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 50)" "deep merge: an unrelated override key under .delivery keeps the base's prSizeBudget (100) rather than falling back to the 500 default"
}

# $LEGO_CONFIG redirects the override file's path; the real
# .local/config.json is then ignored.
test_lego_config_env_redirects_override_path() {
  local dir
  dir="$(new_map_dir "$(block B01 50)" "$(block B02 10)")"
  write_file_at "$dir" ".local/config.json" "$(budget_json 1000)"
  write_file_at "$dir" "custom/dir/myconfig.json" "$(budget_json 100)"

  run_cmd "$dir" "" "custom/dir/myconfig.json"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "LEGO_CONFIG redirect: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 50)" "\$LEGO_CONFIG points at custom/dir/myconfig.json (budget 100), not the default .local/config.json (budget 1000)"
}

# --budget beats the config, the config is never consulted, and jq is not
# needed on that path even though a config file exists.
test_budget_flag_wins_over_config_and_no_jq_needed() {
  local dir
  dir="$(new_map_dir "$(block B01 50)" "$(block B02 10)")"
  write_file_at "$dir" ".claude/lego.json" "$(budget_json 20)"

  JQ=/nonexistent run_in "$dir" --budget 100
  [ "$RUN_EXIT" -eq 0 ] || record_fail "--budget 100 over a config budget of 20, jq absent: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 50)" "--budget wins over the config value and needs no jq"
}

# jq needed (a config file exists, no --budget) but unavailable: diagnostic
# on stderr, exit 2 — never a silent fall back to the 500 default.
test_jq_required_when_config_resolution_needed() {
  local dir
  dir="$(new_map_dir "$(block B01 50)" "$(block B02 10)")"
  write_file_at "$dir" ".claude/lego.json" "$(budget_json 20)"

  JQ=/nonexistent run_in "$dir"
  assert_usage_error "base config present, no --budget, jq absent"
  case "$RUN_ERR" in
    *jq*|*JQ*) : ;;
    *) record_fail "jq absent: the diagnostic does not mention jq (stderr: $RUN_ERR)" ;;
  esac

  local dir2
  dir2="$(new_map_dir "$(block B01 50)" "$(block B02 10)")"
  write_file_at "$dir2" ".local/config.json" "$(budget_json 20)"
  JQ=/nonexistent run_in "$dir2"
  assert_usage_error "override config present, no --budget, jq absent"
}

# ===========================================================================
# The Est field (Behavior clause 1; Edge case: Est 0)
# ===========================================================================

test_missing_est_is_a_finding() {
  local dir
  dir="$(new_map_dir "$(block B01 100)" "$(block B02 NO_EST)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "entry with no Est field: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 1 — fix the block map before scaffolding" "missing Est"
  assert_block_finding B02 "est" "block with no Est field"
  assert_no_block_finding B01 "the well-formed sibling entry"
}

# "a non-negative integer (bare digits; no commas, units, or ranges)" —
# every non-conforming value is a finding, each in its own map so the
# FAILURES count is unambiguous.
test_non_integer_est_values_are_findings() {
  local bad dir
  for bad in "1,200" "200 lines" "150-250" "~200" "abc" "" "-5" "250.0" "+250" "0x10"; do
    dir="$(new_map_dir "$(block B01 "$bad")" "$(block B02 10)")"
    run_in "$dir"
    [ "$RUN_EXIT" -eq 1 ] || record_fail "Est: [$bad]: expected exit 1, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
    assert_findings_structure "FAILURES: 1 — fix the block map before scaffolding" "Est: [$bad]"
    assert_block_finding B01 "est" "Est: [$bad]"
    assert_no_block_finding B02 "the well-formed sibling entry, with Est: [$bad] present elsewhere"
  done
}

# Est: 0 is valid and never requires justification — including against a
# ceiling of 0 (--budget 1), where it sits exactly at the ceiling.
test_est_zero_is_valid_and_never_needs_justification() {
  local dir
  dir="$(new_map_dir "$(block B01 0)" "$(block B02 10)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "Est: 0 under the default ceiling: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "Est: 0 is a valid non-negative integer"

  local dir2
  dir2="$(new_map_dir "$(block B01 0)" "$(block B02 0)")"
  run_in "$dir2" --budget 1
  [ "$RUN_EXIT" -eq 0 ] || record_fail "Est: 0 against ceiling 0: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 0)" "Est: 0 at a ceiling of 0 needs no justification (only a strictly-greater Est does)"

  local dir3
  dir3="$(new_map_dir "$(block B01 1)" "$(block B02 0)")"
  run_in "$dir3" --budget 1
  [ "$RUN_EXIT" -eq 1 ] || record_fail "Est: 1 against ceiling 0: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_block_finding B01 "justif" "Est: 1 strictly over a ceiling of 0"
}

# ===========================================================================
# The Justification requirement
# (Behavior clause 2; Invariant on non-whitespace values; Edge cases)
# ===========================================================================

# The boundary in one place: ceiling-1, ceiling, ceiling+1 — only the last
# needs a justification.
test_ceiling_boundary_only_strictly_over_needs_justification() {
  local dir
  dir="$(new_map_dir "$(block B01 249)" "$(block B02 250)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "Est 249 and 250 against ceiling 250: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "an Est exactly at the ceiling needs no justification"

  local dir2
  dir2="$(new_map_dir "$(block B01 249)" "$(block B02 250)" "$(block B03 251)")"
  run_in "$dir2"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "Est 251 against ceiling 250: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 1 — fix the block map before scaffolding" "only the strictly-over entry is a finding"
  assert_block_finding B03 "justif" "Est 251, one over the ceiling"
  assert_no_block_finding B01 "Est 249, under the ceiling"
  assert_no_block_finding B02 "Est 250, exactly at the ceiling"
}

# A same-line justification value satisfies the requirement.
test_justification_same_line_satisfies() {
  local dir
  dir="$(new_map_dir "$(block_j B01 900 "one generated file, cannot be split")" "$(block B02 10)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "over-ceiling entry with a same-line justification: expected exit 0, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "a justified over-ceiling entry passes"
}

# An indented continuation immediately after "- Justification:" carries the
# value; the requirement is satisfied by the continuation alone.
test_justification_indented_continuation_satisfies() {
  local dir
  dir="$(new_map_dir '## B01 — generated client
- Status: Planned
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U01
- PR group: G01
- Est: 900
- Justification:
  a single generated artifact; splitting it would not reduce review
  surface, and the generator is the real unit of change
- Code: src/client.ts
- Contract: does a thing
- Plan: plans/001-x.md' "$(block B02 10)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "justification on indented continuation lines: expected exit 0, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "an indented continuation carries the justification value"
}

# An empty "- Justification:" — no same-line value, no continuation, just
# the next field line — does NOT satisfy the requirement.
test_empty_justification_does_not_satisfy() {
  local dir
  dir="$(new_map_dir '## B01 — generated client
- Status: Planned
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U01
- PR group: G01
- Est: 900
- Justification:
- Code: src/client.ts
- Contract: does a thing
- Plan: plans/001-x.md' "$(block B02 10)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "empty Justification on an over-ceiling entry: expected exit 1, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 1 — fix the block map before scaffolding" "empty Justification"
  assert_block_finding B01 "justif" "empty Justification on an over-ceiling entry"
}

# A whitespace-only justification — same line, and on a continuation line —
# does not satisfy it either: the value must contain at least one
# non-whitespace character.
test_whitespace_only_justification_does_not_satisfy() {
  local dir
  dir="$(new_map_dir "$(block_j B01 900 "   ")" "$(block B02 10)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "whitespace-only same-line Justification: expected exit 1, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_block_finding B01 "justif" "whitespace-only same-line Justification"

  local dir2
  dir2="$(new_map_dir '## B01 — generated client
- Status: Planned
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U01
- PR group: G01
- Est: 900
- Justification:

- Code: src/client.ts
- Contract: does a thing
- Plan: plans/001-x.md' "$(block B02 10)")"
  run_in "$dir2"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "whitespace-only continuation line: expected exit 1, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_block_finding B01 "justif" "whitespace-only continuation line"
}

# A justification on an entry at or under the ceiling is harmless: not a
# finding, and it does not disturb the clean verdict.
test_stray_justification_under_ceiling_is_harmless() {
  local dir
  dir="$(new_map_dir "$(block_j B01 250 "kept from an earlier, larger design")" "$(block_j B02 10 "belt and braces")")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "stray justifications at/under the ceiling: expected exit 0, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "a stray Justification at or under the ceiling is harmless"
}

# ===========================================================================
# Duplicate block ids (Behavior clause 3)
# ===========================================================================

# Two headings carrying the same B<NN>: a finding. Either the block-level
# "LINT B02: ..." form or the file-level "LINT <file>: ..." form is
# accepted, but the duplicated id must be named and the problem described.
test_duplicate_block_ids_are_a_finding() {
  local dir line
  dir="$(new_map_dir "$(block B01 10)" "$(block B02 20)" "$(block B02 30)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "duplicate B02: expected exit 1, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  line="$(printf '%s\n' "$RUN_OUT" | grep '^LINT ' | grep -m1 -F 'B02')"
  if [ -z "$line" ]; then
    record_fail "duplicate B02: expected a LINT finding naming B02, got stdout: [$RUN_OUT]"
    return
  fi
  if ! printf '%s\n' "$line" | grep -qiE "duplicat|twice|repeat"; then
    record_fail "duplicate B02: the finding does not describe the duplication: [$line]"
  fi
  assert_no_block_finding B01 "the non-duplicated entry"
}

# ===========================================================================
# Parsing tolerance (Invariants: CRLF, whitespace, field order; Edge case:
# non-block "## " headings)
# ===========================================================================

# CRLF line endings parse identically to LF — for the clean map and for the
# over-ceiling comparison alike (a stray \r must not make "250" a
# non-integer, nor "251" compare as something other than 251).
test_crlf_line_endings_tolerated() {
  local dir
  dir="$(new_map_dir "$(block B01 250)" "$(block B02 10)")"
  sed -i 's/$/\r/' "$dir/.local/blocks.md"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "CRLF map, Est at the ceiling: expected exit 0, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "a CRLF map parses as cleanly as an LF one"

  local dir2
  dir2="$(new_map_dir "$(block B01 251)" "$(block B02 10)")"
  sed -i 's/$/\r/' "$dir2/.local/blocks.md"
  run_in "$dir2"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "CRLF map, Est over the ceiling: expected exit 1, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 1 — fix the block map before scaffolding" "CRLF over-ceiling entry"
  assert_block_finding B01 "justif" "CRLF map: the over-ceiling entry is still found"
}

# Leading and trailing whitespace on field lines is tolerated: the value is
# the trimmed text after the colon.
test_field_line_whitespace_tolerated() {
  local dir
  dir="$(new_map_dir '## B01 — spaced out
   - Status: Planned
   - Owner: agent
- Est:    250
- Code: src/a.ts
- Contract: does a thing
- Plan: plans/001-x.md' "$(block B02 10)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "whitespace-padded field lines: expected exit 0, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "leading/trailing whitespace on field lines is tolerated"
}

# Fields in any order within an entry: Est and Justification are found
# wherever they sit.
test_field_order_within_entry_tolerated() {
  local dir
  dir="$(new_map_dir '## B01 — reordered
- Plan: plans/001-x.md
- Justification: one generated artifact
- Code: src/a.ts
- Est: 900
- Contract: does a thing
- Status: Planned' '## B02 — reordered too
- Est: 10
- Status: Planned
- Code: src/small.ts
- Contract: does a thing
- Plan: plans/001-x.md')"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "reordered fields: expected exit 0, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "Est and Justification are found in any field order"
}

# A "## " heading that is not a block id is prose: ignored entirely, never a
# finding and never counted in <n> blocks — the summary's count proves it.
test_non_block_headings_ignored() {
  local dir
  dir="$(new_map_dir "$(block B01 10)" '## Status legend
Planned means planned. This section carries no block fields.

- Status: prose
- Est: definitely not an integer' "$(block B02 20)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "prose section between entries: expected exit 0, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "a non-block \"## \" heading is neither counted nor linted"
}

# ===========================================================================
# Invariants: every entry linted regardless of Status, read-only, exit codes
# ===========================================================================

# Dropped and Accepted entries are linted the same as Planned ones — history
# stays parseable.
test_every_entry_linted_regardless_of_status() {
  local dir
  dir="$(new_map_dir '## B01 — dropped, no Est
- Status: Dropped
- Owner: agent
- Code: src/a.ts
- Contract: does a thing
- Plan: plans/001-x.md' '## B02 — accepted, over ceiling, unjustified
- Status: Accepted
- Owner: agent
- Est: 900
- Code: src/b.ts
- Contract: does a thing
- Plan: plans/001-x.md' '## B03 — accepted and fine
- Status: Accepted
- Owner: agent
- Est: 10
- Code: src/c.ts
- Contract: does a thing
- Plan: plans/001-x.md')"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "Dropped/Accepted entries with defects: expected exit 1, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 2 — fix the block map before scaffolding" "Dropped and Accepted entries are linted too"
  assert_block_finding B01 "est" "a Dropped entry still needs a valid Est"
  assert_block_finding B02 "justif" "an Accepted over-ceiling entry still needs a justification"
  assert_no_block_finding B03 "a well-formed Accepted entry"
}

# The default path is resolved against the CWD, not the repo root: from a
# subdirectory of a repo whose ROOT holds .local/blocks.md, the default path
# does not exist and the run is an environment error.
test_default_path_is_cwd_relative() {
  local dir
  dir="$(new_map_dir "$(block B01 10)" "$(block B02 20)")"
  git init -q -b master "$dir" >/dev/null 2>&1
  mkdir -p "$dir/sub/deeper"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "from the dir holding .local/blocks.md: expected exit 0, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "the default path is found relative to the cwd"

  run_in "$dir/sub/deeper"
  assert_usage_error "from a subdirectory, where .local/blocks.md does not exist (the default path is cwd-relative, not repo-root-relative)"
}

# An explicit positional path is linted instead of the default — proven by
# pointing at a file whose verdict differs from the default path's.
test_explicit_positional_path() {
  local dir
  dir="$(new_map_dir "$(block B01 10)" "$(block B02 20)")"
  write_map_at "$dir" "elsewhere.md" "$(block B01 900)" "$(block B02 20)" "$(block B03 30)"

  run_in "$dir" elsewhere.md
  [ "$RUN_EXIT" -eq 1 ] || record_fail "explicit path to a defective map: expected exit 1, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 1 — fix the block map before scaffolding" "explicit positional path"
  assert_block_finding B01 "justif" "the explicit path's over-ceiling entry"

  # An absolute path works the same, from an unrelated cwd.
  local other
  other="$(mktemp -d)"
  track_tmp "$other"
  run_in "$other" "$dir/.local/blocks.md"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "absolute path from an unrelated cwd: expected exit 0, got $RUN_EXIT (stdout: $RUN_OUT / stderr: $RUN_ERR)"
  assert_clean_structure "ALL PASS (2 blocks, ceiling 250)" "an absolute positional path is linted from any cwd"
}

# Read-only: neither the block map nor any git state changes, across clean,
# findings, and error runs alike.
tree_sum() { # <dir>
  find "$1" -path "$1/.git" -prune -o -type f -print0 2>/dev/null \
    | sort -z | xargs -0 md5sum 2>/dev/null
}

test_invariant_read_only() {
  local dir sum_before sum_after status_before status_after head_before head_after refs_before refs_after
  dir="$(new_map_dir "$(block B01 10)" "$(block B02 900)")"
  write_file_at "$dir" ".claude/lego.json" "$(budget_json 100)"
  git init -q -b master "$dir" >/dev/null 2>&1
  git -C "$dir" config user.email "lego-fixture@example.com"
  git -C "$dir" config user.name "Lego Fixture"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.hooksPath "$NOOP_HOOKS_DIR"
  git -C "$dir" add -A >/dev/null 2>&1
  git -C "$dir" commit -q -m "block map fixture" >/dev/null 2>&1

  sum_before="$(tree_sum "$dir")"
  status_before="$(git -C "$dir" status --porcelain)"
  head_before="$(git -C "$dir" rev-parse HEAD)"
  refs_before="$(git -C "$dir" show-ref)"

  run_in "$dir"                          # findings (Est 900 over ceiling 50)
  [ "$RUN_EXIT" -eq 1 ] || record_fail "read-only fixture: expected the findings run to exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  run_in "$dir" --budget 5000            # clean
  [ "$RUN_EXIT" -eq 0 ] || record_fail "read-only fixture: expected the clean run to exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  run_in "$dir" no/such/file.md          # environment error
  run_in "$dir" --budget 0               # usage error
  run_in "$dir" a.md b.md                # usage error

  sum_after="$(tree_sum "$dir")"
  status_after="$(git -C "$dir" status --porcelain)"
  head_after="$(git -C "$dir" rev-parse HEAD)"
  refs_after="$(git -C "$dir" show-ref)"

  assert_eq "$sum_before" "$sum_after" "read-only: no file content changed across clean, findings and error runs"
  assert_eq "$status_before" "$status_after" "read-only: git status unchanged"
  assert_eq "$head_before" "$head_after" "read-only: HEAD unchanged"
  assert_eq "$refs_before" "$refs_after" "read-only: refs unchanged"
}

# Exit status is only ever 0, 1 or 2 — spot-checked across the clean,
# findings, usage-error and environment-error families.
test_invariant_exit_status_only_0_1_2() {
  local dir ec
  dir="$(new_map_dir "$(block B01 10)" "$(block B02 20)")"

  run_in "$dir"
  ec="$RUN_EXIT"
  case "$ec" in 0) : ;; *) record_fail "clean map: expected exit 0, got $ec" ;; esac

  run_in "$dir" --budget 10
  ec="$RUN_EXIT"
  case "$ec" in 1) : ;; *) record_fail "findings (ceiling 5): expected exit 1, got $ec" ;; esac

  run_in "$dir" --nope
  ec="$RUN_EXIT"
  case "$ec" in 2) : ;; *) record_fail "usage error: expected exit 2, got $ec" ;; esac

  run_in "$dir" no/such/file.md
  ec="$RUN_EXIT"
  case "$ec" in 2) : ;; *) record_fail "environment error: expected exit 2, got $ec" ;; esac
}

# ===========================================================================
# Output shape (Outputs clause), pinned once in isolation: findings land on
# stdout (not stderr), one per line, in the "LINT B<NN>: <problem>" form.
# ===========================================================================

test_output_findings_on_stdout_one_per_line() {
  local dir
  dir="$(new_map_dir "$(block B01 NO_EST)" "$(block B02 900)" "$(block B03 10)")"

  run_in "$dir"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "two defective entries: expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_findings_structure "FAILURES: 2 — fix the block map before scaffolding" "two findings"
  [ "$RUN_OUT_LINES" -eq 4 ] || record_fail "two findings: expected 2 finding lines + blank + summary = 4 stdout lines, got $RUN_OUT_LINES (stdout: $RUN_OUT)"
  assert_block_finding B01 "est" "missing Est"
  assert_block_finding B02 "justif" "unjustified over-ceiling Est"
  assert_no_block_finding B03 "the well-formed entry"
  case "$RUN_ERR" in
    *"LINT "*) record_fail "findings must be reported on stdout, not stderr (stderr: $RUN_ERR)" ;;
  esac
}

# ===========================================================================
# main
# ===========================================================================

run_test "usage: unknown flag -> exit 2" test_usage_unknown_flag
run_test "usage: --budget with no value -> exit 2" test_usage_budget_missing_value
run_test "usage: --budget non-integer/non-positive -> exit 2" test_usage_budget_invalid_value
run_test "usage: more than one positional -> exit 2" test_usage_more_than_one_positional

run_test "block map missing -> exit 2" test_missing_file_is_exit_2
run_test "block map unreadable -> exit 2" test_unreadable_file_is_exit_2
run_test "block map with zero entries -> exit 2" test_zero_block_entries_is_exit_2

run_test "budget: default 500 -> ceiling 250, no jq needed" test_default_budget_500_ceiling_250_no_jq_needed
run_test "budget: --budget sets the ceiling, floored (501 -> 250)" test_budget_flag_ceiling_is_floor_of_half
run_test "budget: resolved from .claude/lego.json" test_budget_from_base_config
run_test "budget: resolved from .local/config.json" test_budget_from_override_config
run_test "budget: layered config deep-merges, override wins" test_config_deep_merge_override_wins
run_test "budget: \$LEGO_CONFIG redirects the override path" test_lego_config_env_redirects_override_path
run_test "budget: --budget wins over config and needs no jq" test_budget_flag_wins_over_config_and_no_jq_needed
run_test "budget: jq required for config resolution -> exit 2 without it" test_jq_required_when_config_resolution_needed

run_test "Est: a missing field is a finding" test_missing_est_is_a_finding
run_test "Est: non-integer values (commas, units, ranges, ...) are findings" test_non_integer_est_values_are_findings
run_test "Est: 0 is valid and never needs justification" test_est_zero_is_valid_and_never_needs_justification

run_test "ceiling boundary: only a strictly-over Est needs justification" test_ceiling_boundary_only_strictly_over_needs_justification
run_test "justification: a same-line value satisfies" test_justification_same_line_satisfies
run_test "justification: an indented continuation satisfies" test_justification_indented_continuation_satisfies
run_test "justification: an empty field does not satisfy" test_empty_justification_does_not_satisfy
run_test "justification: a whitespace-only value does not satisfy" test_whitespace_only_justification_does_not_satisfy
run_test "justification: a stray one at/under the ceiling is harmless" test_stray_justification_under_ceiling_is_harmless

run_test "duplicate block ids are a finding" test_duplicate_block_ids_are_a_finding

run_test "parsing: CRLF line endings tolerated" test_crlf_line_endings_tolerated
run_test "parsing: field-line whitespace tolerated" test_field_line_whitespace_tolerated
run_test "parsing: field order within an entry tolerated" test_field_order_within_entry_tolerated
run_test "parsing: non-block \"## \" headings ignored" test_non_block_headings_ignored

run_test "invariant: every entry linted regardless of Status" test_every_entry_linted_regardless_of_status
run_test "input: the default path is cwd-relative" test_default_path_is_cwd_relative
run_test "input: an explicit positional path is linted" test_explicit_positional_path
run_test "invariant: read-only" test_invariant_read_only
run_test "invariant: exit status only ever 0, 1 or 2" test_invariant_exit_status_only_0_1_2

run_test "output: findings on stdout, one per line, LINT B<NN>: form" test_output_findings_on_stdout_one_per_line

echo "---"
echo "Passed: $TOTAL_PASS  Failed: $TOTAL_FAIL  Total: $((TOTAL_PASS + TOTAL_FAIL))"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
