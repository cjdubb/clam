#!/usr/bin/env bash
# realm-gate.test.sh — contract tests for realm-gate.sh (B04
# realm-gate-local-readonly).
#
# Self-contained bash test harness (no bats/shellcheck), mirroring the style
# of worktree_test.sh. Black-box only: every test pipes hook-input JSON on
# stdin to realm-gate.sh through its public CLI (stdin -> stdout/exit code)
# and asserts on the observable result -- never on realm-gate.sh's internals.
#
# .local/-shaped strings appear here only as PATH STRINGS inside stdin JSON
# payloads; this file never creates or writes real .local/ files.
#
# Run directly: `bash realm-gate.test.sh`. Exits 0 when every test passes,
# 1 when any test fails.
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/realm-gate.sh"

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
# JSON builders for hook input. All output is compact (single-line) so the
# sed-based no-jq fallback in realm-gate.sh (which is line-oriented) can
# parse it identically to the jq path.
# ---------------------------------------------------------------------------

# json_ft <agent_type> <file_path>
json_ft() {
  jq -cn --arg at "$1" --arg fp "$2" '{agent_type:$at, tool_input:{file_path:$fp}}'
}

# json_nt <agent_type> <notebook_path>
json_nt() {
  jq -cn --arg at "$1" --arg np "$2" '{agent_type:$at, tool_input:{notebook_path:$np}}'
}

# json_no_agent_type_key <file_path> -- agent_type key entirely absent
json_no_agent_type_key() {
  jq -cn --arg fp "$1" '{tool_input:{file_path:$fp}}'
}

# json_no_file_path_key <agent_type> -- tool_input present but empty
json_no_file_path_key() {
  jq -cn --arg at "$1" '{agent_type:$at, tool_input:{}}'
}

# json_empty_file_path <agent_type> -- file_path present but ""
json_empty_file_path() {
  jq -cn --arg at "$1" '{agent_type:$at, tool_input:{file_path:""}}'
}

# json_no_tool_input_key <agent_type> -- tool_input key entirely absent
json_no_tool_input_key() {
  jq -cn --arg at "$1" '{agent_type:$at}'
}

# ---------------------------------------------------------------------------
# Invocation helper: pipes JSON on stdin to the script under test, captures
# stdout/stderr/exit code. Optional second arg overrides PATH for the SUT
# process only (used to exercise the no-jq fallback).
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
RUN_OUT_LINES=0

run_gate() {
  local json="$1" path_override="${2:-}"
  local usepath="$path_override"
  [ -n "$usepath" ] || usepath="$PATH"
  local out err ec
  out="$(mktemp)"
  err="$(mktemp)"
  printf '%s' "$json" | PATH="$usepath" bash "$SCRIPT" >"$out" 2>"$err"
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

# assert_denied <label> [required-reason-substring ...]
# Asserts: exit 0, exactly one stdout line, valid JSON with
# hookSpecificOutput.permissionDecision == "deny", a non-empty
# permissionDecisionReason, and (if given) that the reason contains every
# required substring.
assert_denied() {
  local label="$1"
  shift
  if [ "$RUN_EXIT" -ne 0 ]; then
    record_fail "$label: expected exit 0 on deny, got $RUN_EXIT (stderr: $RUN_ERR)"
  fi
  if [ "$RUN_OUT_LINES" -ne 1 ]; then
    record_fail "$label: expected exactly 1 stdout line on deny, got $RUN_OUT_LINES (stdout: $RUN_OUT)"
    return
  fi
  local decision reason
  decision="$(printf '%s' "$RUN_OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  reason="$(printf '%s' "$RUN_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
  assert_eq "deny" "$decision" "$label: permissionDecision"
  if [ -z "$reason" ]; then
    record_fail "$label: expected a non-empty permissionDecisionReason (stdout: $RUN_OUT)"
  fi
  local needle
  for needle in "$@"; do
    case "$reason" in
      *"$needle"*) : ;;
      *) record_fail "$label: reason missing expected substring [$needle] (reason: $reason)" ;;
    esac
  done
}

# assert_allowed <label>
# Asserts: exit 0, no stdout at all.
assert_allowed() {
  local label="$1"
  if [ "$RUN_EXIT" -ne 0 ]; then
    record_fail "$label: expected exit 0 on allow, got $RUN_EXIT (stderr: $RUN_ERR)"
  fi
  if [ -n "$RUN_OUT" ]; then
    record_fail "$label: expected no stdout on allow, got: $RUN_OUT"
  fi
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

# ===========================================================================
# Pre-existing behavior (clauses 1-6, Errors, Invariants) -- expected to
# pass against today's script.
# ===========================================================================

# Clause 1: lego-test-writer denied outside the test family, allowed inside it.
test_test_writer_denied_outside_and_allowed_inside_realm() {
  run_gate "$(json_ft lego-test-writer src/app.js)"
  assert_denied "test-writer on impl-family file" "ESCALATION"

  run_gate "$(json_ft lego-test-writer src/app.test.js)"
  assert_allowed "test-writer on test-family file"
}

# Clause 2: lego-implementer denied inside the test family, allowed outside
# it (and outside .local).
test_implementer_denied_inside_test_realm_and_allowed_outside() {
  run_gate "$(json_ft lego-implementer src/app.test.js)"
  assert_denied "implementer on test-family file" "ESCALATION"

  run_gate "$(json_ft lego-implementer src/app.js)"
  assert_allowed "implementer on non-test-family, non-.local file"
}

# Clause 3: agent_type suffix matching (e.g. "lego:lego-test-writer" matches
# lego-test-writer; an analogous implementer suffix matches too).
test_agent_type_suffix_matching() {
  run_gate "$(json_ft lego:lego-test-writer src/app.js)"
  assert_denied "suffix-matched test-writer on impl-family file" "ESCALATION"

  run_gate "$(json_ft org/lego-implementer src/app.test.js)"
  assert_denied "suffix-matched implementer on test-family file" "ESCALATION"
}

# Clause 4 / Invariant 1: non-worker agent types (including empty/absent)
# always pass through, even when targeting a file a worker would be denied
# on.
test_non_worker_agent_types_pass_through() {
  run_gate "$(json_ft orchestrator src/app.test.js)"
  assert_allowed "unrelated agent_type on test-family file"

  run_gate "$(json_ft "" src/app.test.js)"
  assert_allowed "empty agent_type on test-family file"

  run_gate "$(json_no_agent_type_key src/app.test.js)"
  assert_allowed "absent agent_type key on test-family file"

  run_gate "$(json_ft lego-tester src/app.test.js)"
  assert_allowed "agent_type not exactly ending in a worker role name passes through"
}

# Clause 5: missing/empty file_path passes through; notebook_path is honored
# when file_path is absent.
test_missing_or_empty_file_path_passes_through() {
  run_gate "$(json_no_file_path_key lego-implementer)"
  assert_allowed "implementer with tool_input containing no file_path key"

  run_gate "$(json_empty_file_path lego-implementer)"
  assert_allowed "implementer with empty-string file_path"

  run_gate "$(json_no_tool_input_key lego-test-writer)"
  assert_allowed "test-writer with no tool_input key at all"
}

test_notebook_path_is_honored() {
  run_gate "$(json_nt lego-test-writer notebook.ipynb)"
  assert_denied "test-writer notebook_path outside test family" "ESCALATION"

  run_gate "$(json_nt lego-test-writer notebook.test.ipynb)"
  assert_allowed "test-writer notebook_path inside test family"
}

# Clause 6 / Outputs: deny is exactly one line of JSON, exit is always 0 on
# both deny and allow.
test_output_shape_deny_single_line_allow_silent_exit_zero() {
  run_gate "$(json_ft lego-implementer src/app.test.js)"
  assert_denied "deny output shape" "ESCALATION"
  assert_eq "0" "$RUN_EXIT" "deny: exit code"
  assert_eq "1" "$RUN_OUT_LINES" "deny: stdout line count"

  run_gate "$(json_ft lego-implementer src/app.js)"
  assert_allowed "allow output shape"
  assert_eq "0" "$RUN_EXIT" "allow: exit code"
  assert_eq "0" "$RUN_OUT_LINES" "allow: stdout line count"
}

# Errors: without jq, falls back to sed-based field extraction and produces
# the same deny/allow decisions.
test_no_jq_sed_fallback_field_extraction() {
  local path_no_jq
  path_no_jq="$(path_without jq)"

  run_gate "$(json_ft lego-test-writer src/app.js)" "$path_no_jq"
  assert_denied "no-jq: test-writer on impl-family file" "ESCALATION"

  run_gate "$(json_ft lego-implementer src/app.js)" "$path_no_jq"
  assert_allowed "no-jq: implementer on impl-family file"

  run_gate "$(json_ft orchestrator src/app.test.js)" "$path_no_jq"
  assert_allowed "no-jq: non-worker agent_type passes through"
}

# Errors: unparseable input passes through (exit 0, no output) rather than
# blocking the tool call.
test_unparseable_input_passes_through() {
  local out err ec
  out="$(mktemp)"
  err="$(mktemp)"
  printf 'not json at all' | bash "$SCRIPT" >"$out" 2>"$err"
  ec=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  RUN_EXIT=$ec
  rm -f "$out" "$err"
  assert_allowed "unparseable stdin passes through"
}

# Invariant: read-only -- inspects stdin only, writes nothing to disk.
test_read_only_no_disk_side_effects() {
  local tmpdir before after
  tmpdir="$(mktemp -d)"
  track_tmp "$tmpdir"
  before="$(ls -A "$tmpdir" 2>/dev/null | sort)"

  ( cd "$tmpdir" && printf '%s' "$(json_ft lego-implementer src/app.test.js)" | bash "$SCRIPT" >/dev/null 2>/dev/null )
  ( cd "$tmpdir" && printf '%s' "$(json_ft lego-test-writer src/app.js)" | bash "$SCRIPT" >/dev/null 2>/dev/null )
  ( cd "$tmpdir" && printf '%s' "$(json_ft lego-implementer .local/status.md)" | bash "$SCRIPT" >/dev/null 2>/dev/null )
  ( cd "$tmpdir" && printf 'garbage' | bash "$SCRIPT" >/dev/null 2>/dev/null )

  after="$(ls -A "$tmpdir" 2>/dev/null | sort)"
  assert_eq "$before" "$after" "no files/directories created in cwd as a side effect of gate invocations"
}

# ===========================================================================
# NEW (plan 001): .local/ is orchestrator-owned and read-only -- expected to
# fail against today's script, which has no .local handling.
# ===========================================================================

# Clause 7: lego-implementer targeting .local/status.md -> denied; reason
# states .local/ is orchestrator-owned/read-only and directs to ESCALATION.
test_local_denies_implementer_on_status_md() {
  run_gate "$(json_ft lego-implementer .local/status.md)"
  assert_denied "implementer on .local/status.md" "orchestrator-owned" "read-only" "ESCALATION"
}

# Clause 8: the .local rule fires even where realm rules would otherwise
# allow -- a lego-test-writer targeting a test-family file under .local/ is
# still denied.
test_local_denies_test_writer_even_when_realm_would_allow() {
  run_gate "$(json_ft lego-test-writer .local/__tests__/x.test.js)"
  assert_denied "test-writer on .local/__tests__/x.test.js (test-family, but under .local)" "orchestrator-owned" "read-only" "ESCALATION"
}

# Clause 9 (part 1): ".local" must match a whole path segment. All of these
# must be denied by the .local rule alone -- lego-implementer is used
# throughout with plain non-test-family basenames so any realm rule alone
# would ALLOW, isolating the .local rule as the only possible source of a
# deny. Both relative and absolute paths must match.
test_local_segment_matching_denied_cases() {
  run_gate "$(json_ft lego-implementer a/.local/b)"
  assert_denied ".local as a middle segment (a/.local/b)" "orchestrator-owned" "read-only"

  run_gate "$(json_ft lego-implementer .local/b)"
  assert_denied ".local as the first segment (.local/b)" "orchestrator-owned" "read-only"

  run_gate "$(json_ft lego-implementer a/b/.local)"
  assert_denied ".local as the final segment (a/b/.local)" "orchestrator-owned" "read-only"

  run_gate "$(json_ft lego-implementer /abs/path/.local/config.json)"
  assert_denied "absolute path with a .local segment" "orchestrator-owned" "read-only"
}

# Clause 9 (part 2): segments that merely contain ".local" as a substring,
# not as a whole path segment, must NOT be denied by the .local rule. Same
# isolation technique: lego-implementer + plain non-test-family basenames,
# so an observed allow proves the .local rule did not fire (and the realm
# rule correctly allowed on its own).
test_local_segment_matching_not_denied_cases() {
  run_gate "$(json_ft lego-implementer my.local/b)"
  assert_allowed "my.local/b is not denied by the .local rule"

  run_gate "$(json_ft lego-implementer xlocal/b)"
  assert_allowed "xlocal/b is not denied by the .local rule"

  run_gate "$(json_ft lego-implementer a/local/b)"
  assert_allowed "a/local/b (missing leading dot) is not denied by the .local rule"
}

# ===========================================================================
# main
# ===========================================================================

run_test "test-writer: denied outside test family, allowed inside it" test_test_writer_denied_outside_and_allowed_inside_realm
run_test "implementer: denied inside test family, allowed outside it" test_implementer_denied_inside_test_realm_and_allowed_outside
run_test "agent_type suffix matching for both worker roles" test_agent_type_suffix_matching
run_test "non-worker agent types (incl. empty/absent) always pass through" test_non_worker_agent_types_pass_through
run_test "missing/empty file_path passes through" test_missing_or_empty_file_path_passes_through
run_test "notebook_path is honored" test_notebook_path_is_honored
run_test "output shape: deny is one JSON line, allow is silent, exit always 0" test_output_shape_deny_single_line_allow_silent_exit_zero
run_test "no-jq sed fallback extracts fields correctly" test_no_jq_sed_fallback_field_extraction
run_test "unparseable stdin passes through rather than blocking" test_unparseable_input_passes_through
run_test "read-only: no disk side effects" test_read_only_no_disk_side_effects

run_test "(NEW) .local: implementer denied on .local/status.md" test_local_denies_implementer_on_status_md
run_test "(NEW) .local: overrides realm-allow for test-writer" test_local_denies_test_writer_even_when_realm_would_allow
run_test "(NEW) .local: whole-segment matches are denied (mid/first/final/absolute)" test_local_segment_matching_denied_cases
run_test "(NEW) .local: substring-only matches are not denied" test_local_segment_matching_not_denied_cases

echo "---"
echo "Passed: $TOTAL_PASS  Failed: $TOTAL_FAIL  Total: $((TOTAL_PASS + TOTAL_FAIL))"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
