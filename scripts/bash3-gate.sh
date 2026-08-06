#!/bin/bash
# bash3-gate.sh — run a declared set of test suites under a bash 3.2
# interpreter, so a bash-4-only construct in shipped plugin code fails a check
# instead of failing silently on a user's Mac.
#
# Run: bash scripts/bash3-gate.sh [--bash <path>] [--timeout <seconds>]
#
# Contract: B19 ci-bash3-gate (plan 003-statusline-meter-colour)
#
# Behavior:
#   Runs each suite in a DECLARED list under the interpreter given by --bash,
#   one at a time, each under a per-suite timeout. Prints one line per suite —
#   its path, its exit code, and its PASS and FAIL counts — then a single
#   verdict line. Also prints the excluded set and each exclusion's reason, on
#   every run, before the verdict.
#
#   The suite list is a literal array in this file. It is NOT globbed and must
#   never become a glob: a glob silently widens the gate as the repo grows, so
#   an unrelated plugin's bash-4 code becomes a red bash-3 check nobody chose
#   to take on. Adding a suite here is a deliberate act.
#
# Inputs:
#   --bash <path>      interpreter to run the suites under. Default: `bash` on
#                      PATH. Must exist, be executable, and report a 3.x
#                      version — anything else is a usage error, never a
#                      fallback to a newer bash and never a silent pass.
#   --timeout <secs>   per-suite timeout, positive integer. Default 120.
#                      A non-integer or non-positive value is a usage error.
#   No environment variables. No config files. Reads nothing from .claude/ or
#   .local/.
#
# Outputs:
#   Per suite, one line: "<path>  rc=<n>  PASS=<n>  FAIL=<n>". A suite killed
#   by the timeout reports its rc as the timeout's (124) and is named in the
#   verdict.
#   The excluded set: one line per excluded suite with its reason.
#   Final line: "BASH3 PASS" or "BASH3 FAIL: <first failing suite>".
#   Exit codes: 0 every declared suite passed; 1 a suite failed or timed out;
#   2 usage or environment error (message on stderr).
#
# Errors:
#   - Interpreter missing, not executable, or not 3.x: exit 2.
#   - --bash or --timeout given as the final argument, or followed by another
#     flag: exit 2 with a usage message. Aborting with a `set -u` unbound
#     variable diagnostic is NOT acceptable for a user-facing flag — the two
#     outcomes are distinguishable and the tests assert on the difference.
#   - A declared suite whose file is absent: a FAILURE, not a skip. A gate that
#     skips what it cannot find reports green on a repo that moved the file.
#   - A suite that exceeds the timeout: a FAILURE, reported as one, and named
#     in the verdict. This is not hypothetical — see the exclusion note for
#     context.test.sh below.
#
# Invariants:
#   - The gate never falls back to a newer bash. Its entire value is that the
#     interpreter is old; silently running bash 5 would report green on exactly
#     the code it exists to catch.
#   - Every exclusion is printed on every run, with its reason. A silently
#     narrow gate reads as coverage it does not have.
#   - scripts/ci.sh is not invoked and not modified. This script is standalone
#     and is called directly by the workflow job.
#   - Scope is plugins/statusline/ only, deliberately, and widening it is a
#     decision rather than an oversight: pointed at the whole repo the gate
#     goes red immediately on plugins/lego/scripts/worktree.sh (six `mapfile`
#     calls) and plugins/lego/scripts/blocks-lint.sh — a real but separate
#     defect, filed as F43. Repo tooling under scripts/ is NOT a bash-3 target
#     and is out of scope permanently: it runs in CI and in this repo, never on
#     an installed user's machine.
#
# Edge cases:
#   - Only bash 5 available (an ordinary developer machine): exit 2 with a
#     clear message. Better than a green run that proves nothing.
#   - A suite that passes but writes to stderr: still a pass; this gate reads
#     exit codes and PASS/FAIL counts, not stderr.
#   - Zero declared suites: exit 2. An empty gate is a configuration error, not
#     a vacuous pass.
#
# The bash 3.2 interpreter itself is built by the workflow, not by this script:
# bash 3.2.57 compiles on ubuntu-latest from the GNU tarball with
# build-essential and bison, given
# CFLAGS="-Wno-implicit-function-declaration -Wno-implicit-int
# -Wno-return-mismatch -Wno-int-conversion". bison is required; without it the
# build dies at `yacc -d ./parse.y`.

set -u

usage() {
  echo "Usage: bash3-gate.sh [--bash <path>] [--timeout <seconds>]" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BASH_PATH_ARG=""
TIMEOUT=120

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bash)
      if [ "$#" -lt 2 ]; then
        echo "bash3-gate.sh: --bash requires a value" >&2
        usage
        exit 2
      fi
      case "$2" in
        -*)
          echo "bash3-gate.sh: --bash requires a value" >&2
          usage
          exit 2
          ;;
      esac
      BASH_PATH_ARG="$2"
      shift
      ;;
    --timeout)
      if [ "$#" -lt 2 ]; then
        echo "bash3-gate.sh: --timeout requires a value" >&2
        usage
        exit 2
      fi
      case "$2" in
        -*)
          echo "bash3-gate.sh: --timeout requires a value" >&2
          usage
          exit 2
          ;;
      esac
      case "$2" in
        ''|*[!0-9]*)
          echo "bash3-gate.sh: --timeout value must be a positive integer" >&2
          usage
          exit 2
          ;;
      esac
      if [ "$2" -lt 1 ]; then
        echo "bash3-gate.sh: --timeout value must be a positive integer" >&2
        usage
        exit 2
      fi
      TIMEOUT="$2"
      shift
      ;;
    *)
      echo "bash3-gate.sh: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

DECLARED=(
  "plugins/statusline/lib/burn-math.test.sh"
  "plugins/statusline/lib/burn-theme.test.sh"
  "plugins/statusline/lib/burn-tick.test.sh"
  "plugins/statusline/scripts/ccost.test.sh"
  "plugins/statusline/scripts/readme.test.sh"
  "plugins/statusline/scripts/render-budget.test.sh"
)

EXCLUDED_SUITES=(
  "plugins/statusline/scripts/context.test.sh"
)

CONTEXT_EXCLUDE_REASON="does not terminate under bash 3.2, see F44 -- printf -v with a percent-T time format at seven call sites, two inside a polling loop"

if [ "${#DECLARED[@]}" -eq 0 ]; then
  echo "bash3-gate.sh: zero declared suites, refusing a vacuous pass" >&2
  exit 2
fi

if [ -n "$BASH_PATH_ARG" ]; then
  INTERP="$BASH_PATH_ARG"
else
  INTERP="$(command -v bash 2>/dev/null || true)"
  if [ -z "$INTERP" ]; then
    echo "bash3-gate.sh: no bash interpreter found on PATH" >&2
    exit 2
  fi
fi

if [ ! -e "$INTERP" ]; then
  echo "bash3-gate.sh: interpreter not found: $INTERP" >&2
  exit 2
fi

if [ ! -x "$INTERP" ]; then
  echo "bash3-gate.sh: interpreter is not executable: $INTERP" >&2
  exit 2
fi

INTERP_VERSION="$("$INTERP" --version 2>&1)"
INTERP_VERSION_RC=$?

if [ "$INTERP_VERSION_RC" -ne 0 ]; then
  echo "bash3-gate.sh: interpreter did not report a version: $INTERP" >&2
  exit 2
fi

case "$INTERP_VERSION" in
  *"version 3."*)
    :
    ;;
  *)
    echo "bash3-gate.sh: interpreter is not bash 3.x, refusing to fall back to a newer bash: $INTERP" >&2
    exit 2
    ;;
esac

FIRST_FAIL=""
ANY_FAILED=0

for rel in "${DECLARED[@]}"; do
  abs="$REPO_ROOT/$rel"

  if [ ! -f "$abs" ]; then
    echo "$rel  rc=1  PASS=0  FAIL=0"
    ANY_FAILED=1
    if [ -z "$FIRST_FAIL" ]; then
      FIRST_FAIL="$rel"
    fi
    continue
  fi

  OUT_FILE="$(mktemp)"
  timeout "$TIMEOUT" "$INTERP" "$abs" >"$OUT_FILE" 2>/dev/null
  rc=$?
  pass_n="$(grep -c '^PASS  ' "$OUT_FILE")"
  fail_n="$(grep -c '^FAIL  ' "$OUT_FILE")"
  rm -f "$OUT_FILE"

  echo "$rel  rc=$rc  PASS=$pass_n  FAIL=$fail_n"

  if [ "$rc" -ne 0 ]; then
    ANY_FAILED=1
    if [ -z "$FIRST_FAIL" ]; then
      FIRST_FAIL="$rel"
    fi
  fi
done

for excluded in "${EXCLUDED_SUITES[@]}"; do
  case "$excluded" in
    "plugins/statusline/scripts/context.test.sh")
      echo "$excluded  $CONTEXT_EXCLUDE_REASON"
      ;;
    *)
      echo "$excluded  excluded, no reason recorded"
      ;;
  esac
done

if [ "$ANY_FAILED" -eq 0 ]; then
  echo "BASH3 PASS"
  exit 0
else
  echo "BASH3 FAIL: $FIRST_FAIL"
  exit 1
fi
