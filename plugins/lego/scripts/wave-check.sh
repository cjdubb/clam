#!/bin/bash
# Runs the mechanical half of a lego wave gate in one command.
#
# Run: bash plugins/lego/scripts/wave-check.sh <test|impl> [options] [diff-range]
#
# <!--
# Contract: B02 wave-check
#
# Behavior:
#   Mode `test` (test-wave gate) proves the unit's red run is red for the
#   right reason and realm-pure:
#     RED-RUN: runs the resolved test command pipe-safely (never piped; exit
#       code captured directly from the bare invocation). FAIL if it exits 0
#       (nothing red — the wave produced no failing tests). If it exits
#       non-zero: PASS when no SCANNED line of the combined output matches
#       the collection-error pattern; FAIL labeled COLLECTION when any
#       scanned line matches — import/parse/collection breakage is never a
#       right-reason red. Scanned means every line except test-framework
#       SUCCESS lines: a line whose leading token marks a passing assertion
#       (`ok`, `OK`, `PASS`, `PASSED`, `SUCCESS`, `✓`, `✔`, `--- PASS:`, or
#       a bracketed `[ OK ]`/`[ PASSED ]`) is the framework naming a test
#       that ran and succeeded, so its text is a test DESCRIPTION and never
#       a runtime diagnostic.
#     REALM: delegates to realm-check.sh test [diff-range]; any VIOLATION
#       line FAILs this check.
#   Mode `impl` (implementation-wave gate) proves the suite is genuinely
#   green, realm-pure, and contract surfaces untouched:
#     GREEN-RUN: FAIL unless the resolved test command exits 0 (same
#       pipe-safe capture).
#     REALM: delegates to realm-check.sh impl [diff-range].
#     CONTRACT-DIFF: with --scaffold-ref <ref>, for each --stub <path>
#       (repeatable), FAIL if any line inside the file's contract docblock
#       region, or any signature line present at <ref>, was changed or
#       removed relative to <ref>. Without --scaffold-ref the check reports
#       "CONTRACT-DIFF: SKIPPED (no --scaffold-ref)" — visible, never
#       silent. With --scaffold-ref but no --stub, PASS vacuously with
#       detail "(no stubs named)".
#   Both modes emit one line per check, fixed order (RED-RUN|GREEN-RUN,
#   REALM, CONTRACT-DIFF), format "WAVE-CHECK <CHECK>: PASS|FAIL|SKIPPED
#   [detail]", then a summary "WAVE-CHECK RESULT: PASS" or "WAVE-CHECK
#   RESULT: FAIL (<n> failed)".
#
# Inputs:
#   - $1 (required): literally `test` or `impl`.
#   - --test-cmd "<command>": the resolved test command. When absent, the
#     script resolves commands.test from the layered config
#     (.claude/lego.json deep-merged with .local/config.json; $LEGO_CONFIG
#     overrides the override-file path as in realm.sh); an object-valued
#     commands.test uses its `default` variant. Unresolvable: exit 2.
#   - --scaffold-ref <ref>: git ref of the scaffold phase-boundary commit
#     (impl mode; in test mode it is ignored with a warning on stderr).
#   - --stub <path>: repeatable; stub files for CONTRACT-DIFF (impl mode).
#   - --collection-pattern "<ERE>": overrides the default pattern
#     "SyntaxError|ImportError|ModuleNotFoundError|cannot find module|command not found|CompileError|compilation failed|ParseError|collection error".
#   - Optional trailing diff-range (any argument after options not starting
#     with --), passed through verbatim to realm-check.sh; absent means
#     realm-check's uncommitted-changes mode.
#   - Must run inside a git worktree (the unit worktree); resolves scripts
#     relative to its own location, never the cwd.
#
# Outputs:
#   - stdout: the per-check lines and summary described above, nothing else.
#   - The test command's full output is captured to a temp file; the path is
#     printed in the failing check's detail for triage, and the file is left
#     in place on failure, removed on overall PASS.
#
# Errors:
#   - Unknown mode, unknown flag, flag missing its value: usage on stderr,
#     exit 2.
#   - Unresolvable test command, jq unavailable when config resolution is
#     required, not inside a git repository, realm-check.sh not found
#     beside this script: diagnostic on stderr, exit 2.
#   - One or more check FAILs: exit 1 (never conflated with exit 2).
#
# Invariants:
#   - Read-only with respect to the repository: never modifies tracked
#     files, the index, or git state; temp files live under ${TMPDIR:-/tmp}.
#   - The test command is never piped; its exit code is taken from $?
#     immediately after the bare invocation (output redirected to the temp
#     file — redirection, not a pipeline).
#   - Exit codes: 0 (all checks PASS or SKIPPED), 1 (any FAIL), 2
#     (usage/environment) — never anything else.
#   - SKIPPED never causes exit 1 on its own; it is always accompanied by
#     its reason in the detail.
#
# Edge cases:
#   - Test command exits non-zero with empty output: RED-RUN PASS in test
#     mode (a silent red is still red), GREEN-RUN FAIL in impl mode.
#   - Collection pattern matching inside a legitimate assertion message:
#     FAILs conservatively; --collection-pattern is the escape hatch. This
#     applies to a FAILING assertion's message — a PASSING one is excluded
#     per the SUCCESS-line rule above and does not FAIL the check.
#   - A framework that marks success at the END of a line rather than the
#     start (pytest -v's "test_x.py::test_y PASSED") is NOT excluded: the
#     SUCCESS rule is leading-token only, so such a line is still scanned.
#     Conservative in the same direction as everything else here.
#   - Empty diff-range (no commits between refs): passed to realm-check.sh
#     verbatim; its verdict is passed through.
#   - A --stub path that does not exist at <ref> (new file since scaffold):
#     CONTRACT-DIFF FAIL naming the path — stubs are created at scaffold,
#     so a missing-at-ref stub means the surface moved.
# -->

set -uo pipefail

: "${JQ:=jq}"

USAGE_MSG="usage: wave-check.sh <test|impl> [--test-cmd \"<command>\"] [--scaffold-ref <ref>] [--stub <path>]... [--collection-pattern \"<ERE>\"] [diff-range]"
DEFAULT_COLLECTION_PATTERN="SyntaxError|ImportError|ModuleNotFoundError|cannot find module|command not found|CompileError|compilation failed|ParseError|collection error"

# Lines excluded from the collection-error scan: test-framework output
# announcing a test that PASSED. Every alternative of the default collection
# pattern is a phrase a test description can legitimately contain, so a suite
# that tests a collection detector carries the detector's own vocabulary in
# its passing output and tripped the scan on itself — for lego's own suite,
# on every wave of every plan (issue #326). A passing line cannot be evidence
# that the suite failed to collect, so dropping it costs no detection.
# Deliberately narrower than "any framework line": FAILING lines stay in
# scope, because a wrong-reason red is exactly what this check exists to
# catch.
SUCCESS_LINE_PATTERN='^[[:space:]]*(---[[:space:]]+)?(\[[[:space:]]*(OK|PASS|PASSED)[[:space:]]*\]|ok|OK|PASS|PASSED|SUCCESS|✓|✔)([[:space:]:]|$)'

# Signature-line detection pattern (CONTRACT-DIFF): a "signature line present
# at <ref>" is any non-comment line matching a shell function definition
# (`name() {`) or one of the keyword-led forms (function/def/class/
# interface/type/export function/async function/pub fn/fn/func). Applied to
# the ref's content only; a line's presence (verbatim) in the working-tree
# file is what CONTRACT-DIFF checks for each such line.
SIG_PATTERN='^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{|^(function|def|class|interface|type|(export[[:space:]]+)?(async[[:space:]]+)?function|(pub[[:space:]]+)?fn|func)[[:space:]]'

err() { printf 'ERROR: %s\n' "$1" >&2; }
usage() { err "$USAGE_MSG"; exit 2; }

# ---------------------------------------------------------------------------
# Argument parsing.
# ---------------------------------------------------------------------------
mode=""
if [ "$#" -ge 1 ]; then
  mode="$1"
  shift
fi
case "$mode" in
  test|impl) ;;
  *) usage ;;
esac

test_cmd_flag=""
have_test_cmd_flag=0
scaffold_ref=""
have_scaffold_ref=0
stubs=()
collection_pattern="$DEFAULT_COLLECTION_PATTERN"
diff_range=""
have_diff_range=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --test-cmd)
      shift
      [ "$#" -gt 0 ] || usage
      test_cmd_flag="$1"
      have_test_cmd_flag=1
      shift
      ;;
    --scaffold-ref)
      shift
      [ "$#" -gt 0 ] || usage
      scaffold_ref="$1"
      have_scaffold_ref=1
      shift
      ;;
    --stub)
      shift
      [ "$#" -gt 0 ] || usage
      stubs+=("$1")
      shift
      ;;
    --collection-pattern)
      shift
      [ "$#" -gt 0 ] || usage
      collection_pattern="$1"
      shift
      ;;
    --*)
      usage
      ;;
    *)
      diff_range="$1"
      have_diff_range=1
      shift
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Environment checks: a git worktree, and realm-check.sh resolved relative
# to this script's own location (never the cwd).
# ---------------------------------------------------------------------------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  err "not inside a git repository"
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REALM_CHECK="$SCRIPT_DIR/realm-check.sh"
if [ ! -f "$REALM_CHECK" ]; then
  err "realm-check.sh not found beside wave-check.sh (expected at $REALM_CHECK)"
  exit 2
fi

# ---------------------------------------------------------------------------
# Resolve the test command: --test-cmd wins outright (config is never read,
# jq never invoked); otherwise commands.test from the layered config
# (.claude/lego.json deep-merged with the override file; $LEGO_CONFIG
# overrides the override path, both cwd-relative as in realm.sh).
# ---------------------------------------------------------------------------
TEST_CMD=""
if [ "$have_test_cmd_flag" -eq 1 ]; then
  TEST_CMD="$test_cmd_flag"
else
  base_config=".claude/lego.json"
  override_config="${LEGO_CONFIG:-.local/config.json}"

  have_base=0
  have_override=0
  [ -f "$base_config" ] && have_base=1
  [ -f "$override_config" ] && have_override=1

  if [ "$have_base" -eq 0 ] && [ "$have_override" -eq 0 ]; then
    err "unresolvable test command: no --test-cmd given and no config file present ($base_config, $override_config)"
    exit 2
  fi

  if ! command -v "$JQ" >/dev/null 2>&1; then
    err "jq is required to resolve commands.test from config ($base_config and/or $override_config present); pass --test-cmd to skip config entirely"
    exit 2
  fi

  if [ "$have_base" -eq 1 ] && ! "$JQ" -e . "$base_config" >/dev/null 2>&1; then
    err "invalid JSON in config file: $base_config"
    exit 2
  fi
  if [ "$have_override" -eq 1 ] && ! "$JQ" -e . "$override_config" >/dev/null 2>&1; then
    err "invalid JSON in config file: $override_config"
    exit 2
  fi

  if [ "$have_base" -eq 1 ] && [ "$have_override" -eq 1 ]; then
    effective_config="$("$JQ" -s '.[0] * .[1]' "$base_config" "$override_config" 2>/dev/null)"
  elif [ "$have_base" -eq 1 ]; then
    effective_config="$(cat "$base_config")"
  else
    effective_config="$(cat "$override_config")"
  fi

  raw_type="$("$JQ" -r '.commands.test | type' <<<"$effective_config" 2>/dev/null)"
  case "$raw_type" in
    string)
      TEST_CMD="$("$JQ" -r '.commands.test' <<<"$effective_config" 2>/dev/null)"
      [ -n "$TEST_CMD" ] || { err "commands.test is an empty string in the effective config"; exit 2; }
      ;;
    object)
      default_key="$("$JQ" -r '.commands.test.default // empty' <<<"$effective_config" 2>/dev/null)"
      [ -n "$default_key" ] || { err "commands.test is an object without a 'default' key in the effective config"; exit 2; }
      # $k is the jq variable bound by --arg, not a shell one, so the single
      # quotes are required. shellcheck cannot tell: it special-cases the
      # literal command word `jq`, and "$JQ" hides that.
      # shellcheck disable=SC2016
      TEST_CMD="$("$JQ" -r --arg k "$default_key" '.commands.test[$k] // empty' <<<"$effective_config" 2>/dev/null)"
      [ -n "$TEST_CMD" ] || { err "commands.test.default names an absent or empty variant in the effective config"; exit 2; }
      ;;
    *)
      err "commands.test missing or empty in the effective config"
      exit 2
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# run_captured <shell-command> -- evaluates <shell-command>, redirecting its
# combined stdout+stderr to a fresh temp file under ${TMPDIR:-/tmp} (a
# redirection, never a pipeline, so the command's own $? is taken directly).
# Sets CAPTURED_OUTPUT_FILE; returns the command's exit code.
# ---------------------------------------------------------------------------
CAPTURED_OUTPUT_FILE=""
run_captured() {
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/wave-check.XXXXXX")"
  # Subshell, not a bare eval: a command containing `exit` would otherwise
  # terminate wave-check itself, silently and with no check lines printed.
  ( eval "$1" ) >"$tmp" 2>&1
  local ec=$?
  CAPTURED_OUTPUT_FILE="$tmp"
  return "$ec"
}

# <!--
# Contract: 003-B09 wave-check pipe-free greps (plan 003-followup-fixes)
#
# Behavior:
#   Two membership checks in this script feed a variable into a -q grep
#   through a pipe today; both are rewritten to read WITHOUT a
#   writer-side pipeline:
#   1. The sig-line survival loop in check_contract_diff_stub — whether
#      each signature line from the scaffold ref survives verbatim in
#      the working-tree stub. Read the stub file directly (e.g.
#      grep -qxF -- "$sig_line" "$stub") or via a herestring — any
#      spelling in which no writer process exists to take SIGPIPE when
#      grep exits at its first match.
#   2. The collection-error scan on the RED-RUN path — whether the
#      success-line-filtered captured output matches the collection
#      pattern. Same rewrite (herestring or reading the capture file).
# Inputs: unchanged — the scaffold ref and stub path (check 1); the
#   captured, success-line-filtered test output (check 2).
# Outputs: unchanged semantics — check 1 reports DIRTY exactly when a
#   signature line is genuinely absent from the working-tree file;
#   check 2 reports the COLLECTION failure exactly when the pattern
#   genuinely matches. lego plugin.json 0.14.5 -> 0.14.6 with the root
#   README lego version cell in step (closes #330, dup #301).
# Errors: a missing stub file still reports MISSING; no new failure
#   modes are introduced.
# Invariants: under `set -o pipefail`, a successful early match can
#   never surface as exit 141, a false DIRTY, or a false FAIL;
#   genuinely changed surfaces and genuine collection errors are still
#   detected; no other check in this script changes; the script's
#   exit-code surface is unchanged.
# Edge cases: the signature line matching at line 1 of a
#   multi-hundred-KB stub (the observed false-DIRTY shape); the match
#   on the file's final line; empty scanned output (no match, never an
#   error); a signature line containing regex metacharacters (still
#   matched fixed and whole-line).
# -->

# check_contract_diff_stub <ref> <path> -- CLEAN, DIRTY or MISSING per the
# Behavior clause: the contract docblock region and every signature line
# present at <ref> must survive, byte-identical, in the working-tree file.
check_contract_diff_stub() {
  local ref="$1" stub="$2"
  local ref_content
  if ! ref_content="$(git show "$ref:$stub" 2>/dev/null)"; then
    printf '%s' "MISSING"
    return
  fi
  if [ ! -f "$stub" ]; then
    printf '%s' "MISSING"
    return
  fi
  local current_content
  current_content="$(cat "$stub")"

  local docblock_ref docblock_now
  docblock_ref="$(printf '%s\n' "$ref_content" | sed -n '/^# <!--$/,/^# -->$/p')"
  docblock_now="$(printf '%s\n' "$current_content" | sed -n '/^# <!--$/,/^# -->$/p')"
  if [ "$docblock_ref" != "$docblock_now" ]; then
    printf '%s' "DIRTY"
    return
  fi

  # grep reads the stub file directly: fed through a pipe instead, `grep -q`
  # exiting at its first match kills the writer with SIGPIPE, and under
  # `set -o pipefail` an early match in an oversized stub surfaces as 141 --
  # read here as "signature absent", a false DIRTY (issue #330).
  local sig_line
  while IFS= read -r sig_line; do
    [ -n "$sig_line" ] || continue
    if ! grep -qxF -- "$sig_line" "$stub"; then
      printf '%s' "DIRTY"
      return
    fi
  done < <(printf '%s\n' "$ref_content" | grep -Ev '^[[:space:]]*#' | grep -E "$SIG_PATTERN")

  printf '%s' "CLEAN"
}

# ---------------------------------------------------------------------------
# RED-RUN / GREEN-RUN.
# ---------------------------------------------------------------------------
run_status=""
run_detail=""
CAPTURED_TMP=""

if [ "$mode" = "test" ]; then
  run_captured "$TEST_CMD"
  run_ec=$?
  CAPTURED_TMP="$CAPTURED_OUTPUT_FILE"
  if [ "$run_ec" -eq 0 ]; then
    run_status="FAIL"
    run_detail="(test command exited 0 -- nothing red; output: $CAPTURED_TMP )"
  else
    # Two steps rather than one pipeline: under `set -o pipefail` the
    # pipeline's status would come from whichever grep exited non-zero last,
    # which is not the question being asked here.
    scanned_output="$(grep -Ev -- "$SUCCESS_LINE_PATTERN" "$CAPTURED_TMP")" || scanned_output=""
    # Herestring, not a pipe: `grep -q` exits at its first match, so a writer
    # feeding oversized output would take SIGPIPE and pipefail would report
    # 141 -- read here as "pattern did not match", waving a wrong-reason red
    # through (issue #330). The scan still reads the success-line-FILTERED
    # text, never $CAPTURED_TMP directly (issue #326).
    if grep -Eq -- "$collection_pattern" <<<"$scanned_output"; then
      run_status="FAIL"
      run_detail="(COLLECTION -- combined output matches the collection-error pattern; see $CAPTURED_TMP )"
    else
      run_status="PASS"
    fi
  fi
else
  run_captured "$TEST_CMD"
  run_ec=$?
  CAPTURED_TMP="$CAPTURED_OUTPUT_FILE"
  if [ "$run_ec" -eq 0 ]; then
    run_status="PASS"
  else
    run_status="FAIL"
    run_detail="(test command exited $run_ec; output: $CAPTURED_TMP )"
  fi
fi

# ---------------------------------------------------------------------------
# REALM -- delegates to realm-check.sh <mode> [diff-range].
# ---------------------------------------------------------------------------
realm_args=("$REALM_CHECK" "$mode")
if [ "$have_diff_range" -eq 1 ]; then
  realm_args+=("$diff_range")
fi
realm_out="$("${realm_args[@]}" 2>&1)"
realm_ec=$?

realm_status=""
realm_detail=""
if [ "$realm_ec" -eq 0 ]; then
  realm_status="PASS"
else
  realm_status="FAIL"
  realm_detail_joined="$(printf '%s' "$realm_out" | tr '\n' ' ')"
  realm_detail_joined="${realm_detail_joined% }"
  realm_detail="($realm_detail_joined)"
fi

# ---------------------------------------------------------------------------
# CONTRACT-DIFF.
# ---------------------------------------------------------------------------
contract_status=""
contract_detail=""

if [ "$mode" = "test" ]; then
  contract_status="SKIPPED"
  if [ "$have_scaffold_ref" -eq 1 ]; then
    printf 'WARNING: --scaffold-ref is ignored in test mode; CONTRACT-DIFF is always SKIPPED\n' >&2
    contract_detail="(ignored in test mode)"
  else
    contract_detail="(not applicable in test mode)"
  fi
else
  if [ "$have_scaffold_ref" -eq 0 ]; then
    contract_status="SKIPPED"
    contract_detail="(no --scaffold-ref)"
  elif [ "${#stubs[@]}" -eq 0 ]; then
    contract_status="PASS"
    contract_detail="(no stubs named)"
  else
    bad_stubs=()
    for stub in "${stubs[@]}"; do
      result="$(check_contract_diff_stub "$scaffold_ref" "$stub")"
      [ "$result" = "CLEAN" ] || bad_stubs+=("$stub")
    done
    if [ "${#bad_stubs[@]}" -eq 0 ]; then
      contract_status="PASS"
    else
      contract_status="FAIL"
      joined="$(IFS=', '; printf '%s' "${bad_stubs[*]}")"
      contract_detail="(contract surface changed: $joined)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Assemble output: fixed order (RED-RUN|GREEN-RUN, REALM, CONTRACT-DIFF),
# then the summary. Count FAILs only -- SKIPPED never contributes.
# ---------------------------------------------------------------------------
if [ "$mode" = "test" ]; then
  first_check="RED-RUN"
else
  first_check="GREEN-RUN"
fi

printf 'WAVE-CHECK %s: %s%s\n' "$first_check" "$run_status" "${run_detail:+ $run_detail}"
printf 'WAVE-CHECK REALM: %s%s\n' "$realm_status" "${realm_detail:+ $realm_detail}"
printf 'WAVE-CHECK CONTRACT-DIFF: %s%s\n' "$contract_status" "${contract_detail:+ $contract_detail}"

fail_count=0
for s in "$run_status" "$realm_status" "$contract_status"; do
  [ "$s" = "FAIL" ] && fail_count=$((fail_count + 1))
done

if [ "$fail_count" -gt 0 ]; then
  printf 'WAVE-CHECK RESULT: FAIL (%s failed)\n' "$fail_count"
  overall_ec=1
else
  printf 'WAVE-CHECK RESULT: PASS\n'
  overall_ec=0
fi

# Captured-output temp file: left in place on failure (for triage), removed
# on overall PASS.
if [ -n "$CAPTURED_TMP" ] && [ "$overall_ec" -eq 0 ]; then
  rm -f -- "$CAPTURED_TMP"
fi

exit "$overall_ec"
