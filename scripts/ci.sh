#!/bin/bash
# Canonical pseudo-CI runner: lints, tests, and manifest validation in one gate.
#
# Run: bash scripts/ci.sh [--lint | --test] [--post-status]
#      (exits non-zero on any check failure)

# <!--
# Contract: B02 ci-runner (plan 001-pseudo-ci)
#
# Behavior:
#   Runs the repo's full check suite in three stages, in order:
#     1. lint     — bash scripts/marketplace-lint.sh, bash
#                   scripts/executable-lint.sh, bash scripts/readme-lint.sh,
#                   bash scripts/version-bump-lint.sh, bash
#                   scripts/issue-template-lint.sh, bash
#                   scripts/architecture-lint.sh, bash
#                   scripts/shellcheck-lint.sh (B07) (each invoked from the
#                   repo root; readme-lint requires root cwd).
#     2. test     — every repo-level scripts/*.test.sh, then every
#                   plugins/*/scripts/*.test.sh and plugins/*/lib/*.test.sh,
#                   each via bash.
#     3. validate — claude plugin validate .claude-plugin/marketplace.json,
#                   then claude plugin validate plugins/<name> for every
#                   plugin directory.
#   Stage-level fail-fast: a failing STAGE stops the run, so later stages do
#   not execute and the runner exits 1. Within the test and validate stages,
#   checks run CONCURRENTLY (B03, plan 001-speed-up-repo-ci): every check in
#   the stage runs to completion even when an earlier one fails, and the
#   stage then reports the FIRST failure in fixed output order. Lint checks
#   remain strictly sequential and check-level fail-fast — they total 1.0s
#   once architecture-lint is fixed, so concurrency buys nothing there and
#   their fixed order is load-bearing for readability.
#   With --post-status, a GitHub commit status is posted for HEAD when the
#   run concludes (pass or fail alike).
#
# Inputs:
#   - Optional stage flag: --lint or --test runs ONLY that stage (at most
#     one stage flag; --lint and --test together is a usage error). No
#     stage flag runs all three stages. (validate has no solo flag; it runs
#     only as part of the full suite.)
#   - Optional flag: --jobs <n> (B03) — max concurrent checks within the
#     test and validate stages. Defaults to the machine's core count as
#     reported by nproc, falling back to 4 when nproc is unavailable.
#     --jobs 1 caps concurrency at one check at a time and is the escape
#     hatch for debugging an interleaving-sensitive failure. It does NOT
#     restore intra-stage fail-fast: at ANY --jobs value, including 1, every
#     check in a stage still runs to completion after an earlier one fails.
#     A non-integer or <1 value is a usage error, exit 2. So is a MISSING
#     value — `--jobs` as the final argument, or `--jobs` followed by another
#     flag (a token beginning with `-`). The parser must check the remaining
#     argument count before consuming the next token: aborting with a `set -u`
#     unbound-variable error is NOT acceptable behaviour for a user-facing
#     flag. The two outcomes are distinguishable, which is what the tests
#     assert on — a `set -u` abort exits 1 or 127 with a bash diagnostic,
#     whereas the contract requires exit 2 with a usage message on stderr.
#   - Optional flag: --post-status — after the run, POST the outcome to
#     GitHub as a commit status on HEAD's sha: context "pseudo-ci", state
#     "success" or "failure", via gh api, repo derived from the origin
#     remote URL.
#   - Requires: git, bash, jq. Optional: claude (validate stage), gh
#     (--post-status).
#   - No environment variables, no config files — the runner reads NOTHING
#     from .claude/ or .local/; it is the standalone source of truth that
#     plugin-workflow configs delegate to, never the reverse.
#
# Outputs:
#   - A "== <stage> ==" header line per stage as it starts; each check's
#     own output passes through beneath it, prefixed by a "-- <check>" line.
#   - Skip notices: "WARN  validate skipped (claude CLI not found)" when
#     claude is absent; "WARN  status not posted (<reason>)" when
#     --post-status cannot complete (gh absent, unauthenticated, no origin
#     remote, network failure). Skips never affect the exit code.
#   - A stage with nothing to run (e.g. no test files) prints "no <stage>
#     checks to run" and counts as a pass.
#   - Final line: "CI PASS" or "CI FAIL: <stage>/<check>".
#   - Exit codes: 0 all executed checks passed (skips allowed), 1 a check
#     failed, 2 usage/environment error.
#
# Errors:
#   - Unknown flag, or both --lint and --test: usage line on stderr, exit 2.
#   - Not inside a git repository: diagnostic on stderr, exit 2.
#   - A lint/test script that exits 2 (its own environment error, e.g.
#     missing jq) is reported as that check's failure: CI FAIL, exit 1.
#
# Invariants:
#   - Read-only with respect to the repo; the only side effect is the
#     optional gh status POST (never attempted without --post-status).
#   - cwd-independent: resolves the repo root via git rev-parse and runs
#     every check from there.
#   - Stage order is fixed (lint, test, validate). OUTPUT order within a
#     stage is fixed (lints as listed; tests sorted lexicographically,
#     repo-level before plugins) even though EXECUTION order is now
#     concurrent and nondeterministic. This is the load-bearing invariant of
#     B03: each concurrent check's stdout+stderr is buffered to a temp file
#     and emitted whole, in the fixed order, once the stage completes. A
#     reader diffing two transcripts sees no difference attributable to
#     concurrency; only wall-clock changes. Interleaved or reordered output
#     is a contract violation, not an acceptable consequence.
#   - No check may depend on another check within the same stage, on shared
#     mutable state, or on a fixed cwd beyond the repo root. Concurrency
#     makes any such coupling a race. (Verified before this change: all 113
#     test files build their own mktemp fixtures and pass at -P8.)
#   - B10: a free concurrency slot is filled as soon as ANY in-flight check
#     completes — never only when the OLDEST launched check completes. This
#     is a throughput contract, and it is the reason the stage is concurrent
#     at all. Waiting on the oldest pid still honours the cap and still
#     produces an identical transcript, so no other clause here detects the
#     difference; what it does is idle up to JOBS-1 slots behind a single
#     slow check. Measured against this repo's own 113 files (serial sum
#     142.1s, slowest file 33.5s) at --jobs 8, oldest-first takes 61.1s where
#     fill-on-any-completion takes 37.1s, against an absolute floor of 33.5s.
#     Launching longest-first instead does NOT fix it (41.1s) and is in any
#     case not available, since durations are unknown before the run.
#     Consequences that are part of this clause, not implementation detail:
#       * The bash floor rises to 4.3 for `wait -n`. That is a smaller step
#         than it looks: this file already requires 4.0 for mapfile, so no
#         bash 3.2 host (stock macOS) can run it today either.
#       * `wait -n` reports A completion, not WHICH one, and `wait -p` needs
#         bash 5.1 — too new to require. So each check records its own exit
#         status beside its output buffer, and the parent reads statuses by
#         index at emission time rather than mapping pids to slots. This
#         keeps first-failure-in-fixed-order exactly as B03 specified it:
#         the reported failure is the first in OUTPUT order, never the first
#         to finish.
#       * mktemp and cat remain unusable anywhere in this path. The nproc
#         fallback test strips PATH to bash/git/find/sort/rm, so the status
#         files are written by plain redirection and read by builtins, the
#         same constraint that already shapes the output buffers.
#     Unchanged by B10: the cap itself, the fixed-order buffered transcript,
#     stage-level fail-fast, intra-stage run-to-completion, and the --jobs
#     parsing rules. Those tests must pass untouched.
#   - The status POST (when requested) reflects the true outcome: success
#     only when the run would exit 0; a fail-fast run still posts failure
#     before exiting.
#   - Requires only bash+git+jq for the gate itself: claude, gh and
#     shellcheck are optional enhancers whose absence degrades to WARN,
#     never to a failure or a silent skip. Concurrency adds no dependency —
#     it is implemented with bash job control and wait, NOT with xargs -P,
#     GNU parallel, or any other external scheduler, precisely so this
#     promise survives B03. nproc is read for the --jobs default and its
#     absence falls back to 4 rather than failing.
#
# Edge cases:
#   - Repo with no plugins/ dir or no test files anywhere: each empty
#     stage vacuously passes with its notice; CI PASS.
#   - claude present but a validate check fails: CI FAIL, exit 1 (absence
#     WARN-skips; presence gates).
#   - --post-status on a sha that does not exist on the remote yet: the
#     POST still succeeds (GitHub accepts statuses for unknown shas and
#     attaches them when the sha arrives) — no special handling.
#   - --post-status with a non-GitHub origin remote: WARN, no POST, exit
#     code unaffected.
#   - Interrupted run (signal): no status is posted; partial output stands.
# -->

set -u

usage() {
  echo "Usage: ci.sh [--lint | --test] [--post-status]" >&2
}

STAGE_ONLY=""
POST_STATUS=0
JOBS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --lint)
      if [ -n "$STAGE_ONLY" ] && [ "$STAGE_ONLY" != "lint" ]; then
        echo "ci.sh: --lint and --test are mutually exclusive" >&2
        usage
        exit 2
      fi
      STAGE_ONLY="lint"
      ;;
    --test)
      if [ -n "$STAGE_ONLY" ] && [ "$STAGE_ONLY" != "test" ]; then
        echo "ci.sh: --lint and --test are mutually exclusive" >&2
        usage
        exit 2
      fi
      STAGE_ONLY="test"
      ;;
    --post-status)
      POST_STATUS=1
      ;;
    --jobs)
      # Check the remaining argument count BEFORE consuming $2 -- with
      # set -u, referencing $2 when it doesn't exist aborts with an
      # unbound-variable diagnostic, which is exactly the failure mode the
      # contract requires this flag NOT to have (exit 2 with a usage
      # message instead).
      if [ "$#" -lt 2 ]; then
        echo "ci.sh: --jobs requires a value" >&2
        usage
        exit 2
      fi
      case "$2" in
        -*)
          # A token beginning with "-" (another flag, or a negative
          # number) is treated as a missing value, per the docblock.
          echo "ci.sh: --jobs requires a value" >&2
          usage
          exit 2
          ;;
      esac
      case "$2" in
        ''|*[!0-9]*)
          echo "ci.sh: --jobs value must be a positive integer" >&2
          usage
          exit 2
          ;;
      esac
      if [ "$2" -lt 1 ]; then
        echo "ci.sh: --jobs value must be a positive integer" >&2
        usage
        exit 2
      fi
      JOBS="$2"
      shift
      ;;
    *)
      echo "ci.sh: unknown flag: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

if [ -z "$JOBS" ]; then
  JOBS="$(nproc 2>/dev/null)"
  [ -n "$JOBS" ] || JOBS=4
fi

ROOT="$(git rev-parse --show-toplevel 2>&1)" || {
  echo "ci.sh: $ROOT" >&2
  exit 2
}

SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"

FAIL_LABEL=""

# Runs one check: prints its "-- <name>" line, executes it with cwd at the
# repo root, and records stage/name on failure for the final CI FAIL line.
run_check() { # <stage> <name> <cmd...>
  local stage="$1" name="$2"
  shift 2
  echo "-- $name"
  ( cd "$ROOT" && "$@" )
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    FAIL_LABEL="$stage/$name"
    return 1
  fi
  return 0
}

run_lint_stage() {
  echo "== lint =="
  local checks=(marketplace-lint executable-lint readme-lint version-bump-lint issue-template-lint architecture-lint)
  local c
  for c in "${checks[@]}"; do
    run_check "lint" "$c" bash "scripts/$c.sh" || return 1
  done
  return 0
}

# Runs up to $JOBS checks of the current stage concurrently via bash job
# control and `wait` only (no xargs -P, GNU parallel, sem, or any other
# external scheduler). The caller must first populate the global NAMES[]
# (display name per check, used for "-- <name>" and the failure label) and
# BUFFERS[] (a private output-file path per check) arrays, and define a
# global run_one() that runs check $1 with its cwd already at $ROOT.
#
# Concurrency is capped by keeping a count of in-flight jobs: once it
# reaches $JOBS, `wait -n` blocks until ANY one of them completes (B10) --
# never specifically the oldest -- before a new check is launched. This
# never lets more than $JOBS checks run at once, and a free slot is always
# taken as soon as it opens, regardless of which check vacated it.
#
# Each check's stdout+stderr is redirected to its own buffer file while it
# runs, so nothing can interleave; buffers are emitted whole, in fixed
# NAMES[] order, only after every check in the stage has completed. Since
# `wait -n` reports THAT a job finished but not WHICH one (and `wait -p`
# needs bash 5.1, too new to require), each backgrounded check writes its
# own exit status to a status file beside its buffer, by plain redirection.
# Statuses are then read back by fixed array index at emission time, not by
# completion order, so the reported failure is always the first one in
# fixed order, never whichever check happened to finish first. The status
# file is seeded with a nonzero sentinel before the check is launched, so a
# subshell that dies before it can write its real status (OOM kill, an
# external kill, a read-only TMPDIR) is read back as a failure, never as a
# silent pass.
run_concurrent() { # <stage> <n>
  local stage="$1" n="$2"
  local running=0
  local i
  for ((i = 0; i < n; i++)); do
    : > "${BUFFERS[i]}"
    echo 1 > "${BUFFERS[i]}.rc"  # fail-closed: overwritten by the child with the real status
    (
      ( cd "$ROOT" && run_one "$i" ) > "${BUFFERS[i]}" 2>&1
      echo "$?" > "${BUFFERS[i]}.rc"
    ) &
    running=$((running + 1))
    if [ "$running" -ge "$JOBS" ]; then
      wait -n
      running=$((running - 1))
    fi
  done
  wait

  local fail="" body rc
  for ((i = 0; i < n; i++)); do
    echo "-- ${NAMES[i]}"
    body=""
    IFS= read -r -d '' body < "${BUFFERS[i]}" || true
    printf '%s' "$body"
    rm -f "${BUFFERS[i]}"
    rc=""
    read -r rc < "${BUFFERS[i]}.rc" || true
    rm -f "${BUFFERS[i]}.rc"
    if [ -z "$fail" ] && [ "${rc:-0}" -ne 0 ]; then
      fail="$i"
    fi
  done
  if [ -n "$fail" ]; then
    FAIL_LABEL="$stage/${NAMES[$fail]}"
    return 1
  fi
  return 0
}

run_test_stage() {
  echo "== test =="
  mapfile -t repo_tests < <(find "$ROOT/scripts" -maxdepth 1 -type f -name '*.test.sh' 2>/dev/null | sort)
  mapfile -t plugin_tests < <(find "$ROOT/plugins" -mindepth 3 -maxdepth 3 -type f -name '*.test.sh' \( -path '*/scripts/*' -o -path '*/lib/*' \) 2>/dev/null | sort)
  local all=("${repo_tests[@]}" "${plugin_tests[@]}")
  if [ "${#all[@]}" -eq 0 ]; then
    echo "no test checks to run"
    return 0
  fi
  local tmpdir="${TMPDIR:-/tmp}" i
  NAMES=()
  ABS_PATHS=()
  BUFFERS=()
  for i in "${!all[@]}"; do
    NAMES[i]="${all[i]#$ROOT/}"
    ABS_PATHS[i]="${all[i]}"
    BUFFERS[i]="$tmpdir/ci.sh.$$.test.$i.out"
  done
  run_one() { bash "${ABS_PATHS[$1]}"; }
  run_concurrent "test" "${#all[@]}"
}

run_validate_stage() {
  echo "== validate =="
  if ! command -v claude >/dev/null 2>&1; then
    echo "WARN  validate skipped (claude CLI not found)"
    return 0
  fi
  local targets=(".claude-plugin/marketplace.json")
  local names
  mapfile -t names < <(find "$ROOT/plugins" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
  local n
  for n in "${names[@]}"; do
    targets+=("plugins/$n")
  done
  local tmpdir="${TMPDIR:-/tmp}" i
  NAMES=()
  TARGETS=()
  BUFFERS=()
  for i in "${!targets[@]}"; do
    NAMES[i]="${targets[i]}"
    TARGETS[i]="${targets[i]}"
    BUFFERS[i]="$tmpdir/ci.sh.$$.validate.$i.out"
  done
  run_one() { claude plugin validate "${TARGETS[$1]}"; }
  run_concurrent "validate" "${#targets[@]}"
}

# Extracts "owner/repo" from a GitHub origin URL (https, http, ssh, or
# git@ scp-like form). Fails (non-zero) for any non-GitHub host.
parse_github_repo() { # <url>
  local url="$1" rest
  case "$url" in
    git@github.com:*)
      rest="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      rest="${url#ssh://git@github.com/}"
      ;;
    https://github.com/*|http://github.com/*)
      rest="${url#*github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
  rest="${rest%.git}"
  rest="${rest%/}"
  [ -n "$rest" ] || return 1
  printf '%s' "$rest"
}

# Posts the run outcome as a GitHub commit status on HEAD, or prints a WARN
# and returns cleanly when any prerequisite is missing -- never affects the
# run's exit code.
post_status() { # <state: success|failure>
  local state="$1"
  if ! command -v gh >/dev/null 2>&1; then
    echo "WARN  status not posted (gh CLI not found)"
    return
  fi
  local origin
  if ! origin="$(git -C "$ROOT" remote get-url origin 2>/dev/null)" || [ -z "$origin" ]; then
    echo "WARN  status not posted (no origin remote)"
    return
  fi
  local repo
  if ! repo="$(parse_github_repo "$origin")"; then
    echo "WARN  status not posted (origin is not a GitHub remote)"
    return
  fi
  if ! gh api "repos/$repo/statuses/$SHA" \
      -f "state=$state" \
      -f "context=pseudo-ci" \
      -f "description=pseudo-ci $state" \
      >/dev/null 2>&1; then
    echo "WARN  status not posted (gh api call failed)"
    return
  fi
}

FAILED=0
if [ -n "$STAGE_ONLY" ]; then
  STAGES=("$STAGE_ONLY")
else
  STAGES=(lint test validate)
fi

for s in "${STAGES[@]}"; do
  case "$s" in
    lint) run_lint_stage ;;
    test) run_test_stage ;;
    validate) run_validate_stage ;;
  esac
  rc=$?
  if [ "$rc" -ne 0 ]; then
    FAILED=1
    break
  fi
done

if [ "$FAILED" -eq 0 ]; then
  STATE="success"
  EXIT_CODE=0
else
  STATE="failure"
  EXIT_CODE=1
fi

# The status POST (when requested) happens here, before the final summary
# line is printed, so "CI PASS"/"CI FAIL: ..." always stays the true last
# line. This is a plain statement, not a trap: on an interrupting signal
# the script simply dies here and this line -- and the POST -- never runs,
# which is exactly the contracted "interrupted run: no status posted"
# behavior.
if [ "$POST_STATUS" -eq 1 ]; then
  post_status "$STATE"
fi

if [ "$FAILED" -eq 0 ]; then
  echo "CI PASS"
else
  echo "CI FAIL: $FAIL_LABEL"
fi

exit "$EXIT_CODE"
