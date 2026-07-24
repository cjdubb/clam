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
#                   scripts/issue-template-lint.sh (each invoked from the
#                   repo root; readme-lint requires root cwd).
#     2. test     — every repo-level scripts/*.test.sh, then every
#                   plugins/*/scripts/*.test.sh and plugins/*/lib/*.test.sh,
#                   each via bash.
#     3. validate — claude plugin validate .claude-plugin/marketplace.json,
#                   then claude plugin validate plugins/<name> for every
#                   plugin directory.
#   Fail-fast: the first failing check stops the run (later checks and
#   stages do not execute) and the runner exits 1. With --post-status, a
#   GitHub commit status is posted for HEAD when the run concludes (pass or
#   fail alike).
#
# Inputs:
#   - Optional stage flag: --lint or --test runs ONLY that stage (at most
#     one stage flag; --lint and --test together is a usage error). No
#     stage flag runs all three stages. (validate has no solo flag; it runs
#     only as part of the full suite.)
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
#   - Stage order is fixed (lint, test, validate); check order within a
#     stage is fixed (lints as listed; tests sorted lexicographically,
#     repo-level before plugins).
#   - The status POST (when requested) reflects the true outcome: success
#     only when the run would exit 0; a fail-fast run still posts failure
#     before exiting.
#   - Requires only bash+git+jq for the gate itself: claude and gh are
#     optional enhancers whose absence degrades to WARN, never to a
#     failure or a silent skip.
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
    *)
      echo "ci.sh: unknown flag: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

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
  local checks=(marketplace-lint executable-lint readme-lint version-bump-lint issue-template-lint)
  local c
  for c in "${checks[@]}"; do
    run_check "lint" "$c" bash "scripts/$c.sh" || return 1
  done
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
  local abs rel
  for abs in "${all[@]}"; do
    rel="${abs#$ROOT/}"
    run_check "test" "$rel" bash "$abs" || return 1
  done
  return 0
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
  local t
  for t in "${targets[@]}"; do
    run_check "validate" "$t" claude plugin validate "$t" || return 1
  done
  return 0
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
