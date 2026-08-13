#!/usr/bin/env bash
# ci-workflow.test.sh — contract tests for .github/workflows/ci.yml
# (B13 ci-workflow-job-split, plan 001-speed-up-repo-ci; B19 ci-bash3-gate,
# plan 003-statusline-meter-colour).
#
# Subject: the workflow file itself. The "Contract: B13 ci-workflow-job-split"
# and "Contract: B19 ci-bash3-gate" docblocks at the top of
# .github/workflows/ci.yml are the source of truth. B19 adds a fourth job and
# widens the aggregator to three dependencies; B13's invariants are unchanged
# by it and are still asserted here exactly as they were.
#
# WHY THIS SUITE PARSES YAML BY HAND
#
# scripts/ci.sh's contract promises the gate needs only bash, git and jq, so
# there is no YAML parser here and none may be added. Every assertion is
# structural over the workflow TEXT: the file is cut into top-level blocks,
# `jobs:` into one block per job by indentation, and each job's `steps:` into
# individual steps. That is what lets a claim like "the `ci` job carries
# `if: always()`" be made about that job's own lines, at job level, rather
# than about the string appearing somewhere in the file.
#
# TWO TRAPS THIS SUITE AVOIDS
#
# 1. A wrong-reason pass off the contract comment. The docblocks quote nearly
#    every string worth asserting — `if: always()`, `fetch-depth: 0`,
#    `LC_ALL: en_US.UTF-8`, `bash scripts/ci.sh --lint`, even the job name
#    `ci`; B19's adds `bison`, all four `-Wno-*` CFLAGS, `3.2.57`,
#    `scripts/bash3-gate.sh` and `== 'success'`. A grep over the raw file goes
#    green on the comment alone. So every assertion runs against $YAML: the
#    file with all comment lines stripped. A parse-sanity check below asserts
#    the stripped view really is comment-free, so an all-red suite can never be
#    an empty-parse artefact.
#
# 2. Executing the real gate. The aggregator's guard is SIMULATED: a result
#    value is substituted into the `ci` job's `${{ needs.<job>.result }}`
#    expressions and the guard is then evaluated for real, which is the only
#    way to show that a *cancelled* stage genuinely fails the job. Only steps
#    that mention `needs.` are ever evaluated — the stage steps, which run
#    `bash scripts/ci.sh --lint` and `sudo locale-gen`, are never executed by
#    this suite, at any point, in any scenario.
#
# Read-only and hermetic: reads .github/workflows/ci.yml and scripts/ci.sh,
# writes only under mktemp, no network.
#
# Mirrors the PASS/FAIL harness style of scripts/ci.test.sh.
#
# Run: bash scripts/ci-workflow.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
CI_SCRIPT="$REPO_ROOT/scripts/ci.sh"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# A missing workflow must not abort the run: it is reported as a failed
# assertion and every structural check below then fails against an empty
# parse, which is the honest verdict.
YAML="$(mktemp)"
SCRATCH="$(mktemp -d)"
cleanup() { rm -f -- "$YAML"; rm -rf -- "$SCRATCH"; }
trap cleanup EXIT

if [ -f "$WORKFLOW" ]; then
  grep -v '^[[:space:]]*#' "$WORKFLOW" | grep -v '^[[:space:]]*$' > "$YAML"
fi

# ---------------------------------------------------------------------------
# Small string helpers.
# ---------------------------------------------------------------------------
trim() { # <string> -- strip leading and trailing whitespace
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# unquote <string> -- strip one layer of matching quotes, but ONLY when the
# whole string is a single quoted token. `'failure' != 'success'` starts and
# ends with a quote without being quoted, and stripping there would corrupt
# the expression rather than unwrap it.
unquote() {
  local s="$1" inner
  case "$s" in
    \"*\")
      inner="${s#\"}"; inner="${inner%\"}"
      case "$inner" in *\"*) ;; *) s="$inner" ;; esac
      ;;
    \'*\')
      inner="${s#\'}"; inner="${inner%\'}"
      case "$inner" in *\'*) ;; *) s="$inner" ;; esac
      ;;
  esac
  printf '%s' "$s"
}

# norm_expr <string> -- an expression with its ${{ }} wrapper, surrounding
# quotes and outer whitespace removed. `if: always()`, `if: "always()"` and
# `if: ${{ always() }}` are the same expression and must assert the same.
norm_expr() {
  local s
  s="$(trim "$1")"
  s="$(unquote "$s")"
  s="$(trim "$s")"
  case "$s" in
    \$\{\{*\}\})
      s="${s#\$\{\{}"
      s="${s%\}\}}"
      s="$(trim "$s")"
      ;;
  esac
  printf '%s' "$s"
}

yaml_grep() { # <ERE> -- yes/no, over the comment-stripped workflow
  if grep -Eq -- "$1" "$YAML"; then printf 'yes'; else printf 'no'; fi
}

# ---------------------------------------------------------------------------
# Structural YAML helpers. Indentation is the only structure YAML gives away
# to a text scanner, so these work in leading-space counts throughout. Blank
# and comment lines are already gone from $YAML, so an indentation of 0 always
# means "a top-level key" and never "an empty line".
# ---------------------------------------------------------------------------

# min_indent <text> -- the smallest leading-space count in <text> ("" if empty).
# This is the indent at which that block's own keys live.
min_indent() {
  printf '%s\n' "$1" | awk '
    NF { match($0, /^ */); if (!seen || RLENGTH < m) { m = RLENGTH; seen = 1 } }
    END { if (seen) print m }
  '
}

# top_block_re <ERE for the key line> -- the lines under a top-level key, the
# key line itself excluded.
top_block_re() {
  awk -v re="$1" '
    /^[^[:space:]]/ { inb = ($0 ~ re) ? 1 : 0; next }
    inb { print }
  ' "$YAML"
}

# keys_at <text> <indent> -- the mapping keys at exactly <indent>, in order.
keys_at() {
  printf '%s\n' "$1" | awk -v ind="$2" '
    { match($0, /^ */); if (RLENGTH != ind) next }
    {
      line = $0
      sub(/^ */, "", line)
      if (line ~ /^[A-Za-z_][A-Za-z0-9_.-]*:([ \t]|$)/) {
        sub(/:.*$/, "", line)
        print line
      }
    }
  '
}

# sub_block <text> <indent> <key> -- the lines under `<key>:` at <indent>, the
# key line excluded. A sequence written at the key's own indent (valid YAML)
# still belongs to the key, so `- item` lines at <indent> do not end the block.
sub_block() {
  printf '%s\n' "$1" | awk -v ind="$2" -v key="$3" '
    { match($0, /^ */); cur = RLENGTH }
    cur == ind {
      if ($0 ~ /^ *- /) { if (inb) print; next }
      k = $0
      sub(/^ */, "", k)
      if (k ~ /^[^ ]*:/) { sub(/:.*$/, "", k); inb = (k == key) } else { inb = 0 }
      next
    }
    cur < ind { inb = 0; next }
    inb { print }
  '
}

# inline_value <text> <indent> <key> -- whatever follows `<key>:` on the key's
# own line at <indent> ("" when the key is absent or opens a block).
inline_value() {
  printf '%s\n' "$1" | awk -v ind="$2" -v key="$3" '
    { match($0, /^ */); if (RLENGTH != ind) next }
    {
      k = $0
      sub(/^ */, "", k)
      if (k !~ /^[^ ]*:/) next
      name = k
      sub(/:.*$/, "", name)
      if (name != key) next
      v = k
      sub(/^[^:]*:[ \t]*/, "", v)
      print v
      exit
    }
  '
}

# scalar_list <text> <indent> <key> -- the items of a scalar list, one per
# line, whether written flow style (`[a, b]`), block style (`- a`), or as a
# single bare scalar.
scalar_list() {
  {
    inline_value "$1" "$2" "$3"
    sub_block "$1" "$2" "$3"
  } | tr -d "[]\"'," | tr -s '[:blank:]' '\n' | sed 's/^-//' \
    | grep -E '^[A-Za-z0-9_./*-]+$' || true
}

# ---------------------------------------------------------------------------
# Jobs.
# ---------------------------------------------------------------------------
JOBS_BLOCK="$(top_block_re '^jobs:')"
JOB_INDENT="$(min_indent "$JOBS_BLOCK")"; JOB_INDENT="${JOB_INDENT:--1}"

job_names() { keys_at "$JOBS_BLOCK" "$JOB_INDENT"; }
job_block() { sub_block "$JOBS_BLOCK" "$JOB_INDENT" "$1"; }

has_job() { # <name> -- yes/no, on an exact key match (never a substring)
  if job_names | grep -Fxq -- "$1"; then printf 'yes'; else printf 'no'; fi
}

job_inline() { # <job> <key> -- a JOB-LEVEL key's inline value
  local blk ind
  blk="$(job_block "$1")"
  ind="$(min_indent "$blk")"; ind="${ind:--1}"
  inline_value "$blk" "$ind" "$2"
}

job_list() { # <job> <key> -- a JOB-LEVEL key's list items, one per line
  local blk ind
  blk="$(job_block "$1")"
  ind="$(min_indent "$blk")"; ind="${ind:--1}"
  scalar_list "$blk" "$ind" "$2"
}

job_grep() { # <job> <ERE> -- yes/no within that job's own lines
  if [ "$(has_job "$1")" != yes ]; then printf 'no such job'; return; fi
  if printf '%s\n' "$(job_block "$1")" | grep -Eq -- "$2"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

# job_needs <job> <other> -- yes/no, with its own sentinel for an absent job:
# a missing job has no needs edge, so a plain "no" here would let the absent
# case satisfy a negative assertion.
job_needs() {
  if [ "$(has_job "$1")" != yes ]; then printf 'no such job'; return; fi
  if job_list "$1" needs | grep -Fxq -- "$2"; then printf 'yes'; else printf 'no'; fi
}

# job_context <job> -- the status-check context GitHub will report for the
# job. It is the job key UNLESS a job-level `name:` overrides it, which is
# exactly how a well-meaning rename silently deletes a required context.
job_context() {
  local nm
  if [ "$(has_job "$1")" != yes ]; then printf 'no such job'; return; fi
  nm="$(unquote "$(trim "$(job_inline "$1" name)")")"
  if [ -n "$nm" ]; then printf '%s' "$nm"; else printf '%s' "$1"; fi
}

# BASH3_JOB -- the job key that is neither lint, test, test_macos nor ci: the
# bash-3 stage B19 adds. Its docblock says "a fourth job" without fixing the
# key, so the key is DERIVED rather than hardcoded — renaming the stage is not
# a failure, its absence is. (B08's macOS stage is excluded by its literal key
# `test_macos`, which B08 does fix.) When the bash-3 job is absent (or when an
# extra job muddies the derivation) the sentinel below stands in, and every
# helper answers "no such job" for it, which fails the B19 assertions rather
# than satisfying the negative ones.
BASH3_JOB="$(job_names | grep -vFx -e lint -e test -e test_macos -e ci || true)"
BASH3_JOB_COUNT="$(printf '%s\n' "$BASH3_JOB" | grep -c . || true)"
if [ "$BASH3_JOB_COUNT" -ne 1 ]; then BASH3_JOB="__no_bash3_job__"; fi

# ---------------------------------------------------------------------------
# Steps.
# ---------------------------------------------------------------------------
STEP_SEP='@@STEP@@'

steps_block() { # <job>
  local blk ind
  blk="$(job_block "$1")"
  ind="$(min_indent "$blk")"; ind="${ind:--1}"
  sub_block "$blk" "$ind" steps
}

# steps_of <job> -- the job's steps, each introduced by a $STEP_SEP line, with
# the leading "- " rewritten to spaces so every key of a step sits at one
# indent and the generic block helpers apply to it unchanged.
steps_of() {
  local blk ind
  blk="$(steps_block "$1")"
  ind="$(min_indent "$blk")"; ind="${ind:--1}"
  printf '%s\n' "$blk" | awk -v ind="$ind" -v sep="$STEP_SEP" '
    { match($0, /^ */); cur = RLENGTH }
    cur == ind && $0 ~ /^ *- / {
      print sep
      print substr($0, 1, ind) "  " substr($0, ind + 3)
      next
    }
    { print }
  '
}

n_steps() { # <job>
  local n
  n="$(steps_of "$1" | grep -c "^$STEP_SEP" || true)"
  printf '%s' "${n:-0}"
}

step_n() { # <job> <n> -- the nth step's text (1-indexed)
  steps_of "$1" | awk -v sep="$STEP_SEP" -v want="$2" '
    $0 == sep { i++; next }
    i == want { print }
  '
}

# step_scalar <step text> <key> -- the key's value: the inline scalar, or the
# dedented body of a block scalar (`|`, `>` and their chomping variants).
step_scalar() {
  local txt="$1" key="$2" ind v body m
  ind="$(min_indent "$txt")"; ind="${ind:--1}"
  v="$(inline_value "$txt" "$ind" "$key")"
  case "$(trim "$v")" in
    '|'|'|-'|'|+'|'>'|'>-'|'>+'|'')
      body="$(sub_block "$txt" "$ind" "$key")"
      [ -n "$body" ] || return 0
      m="$(min_indent "$body")"; m="${m:-0}"
      printf '%s\n' "$body" | sed "s/^ \{0,$m\}//"
      ;;
    *) printf '%s\n' "$v" ;;
  esac
}

step_sub() { # <step text> <key> -- the sub-block under a step key (e.g. `with`)
  local ind
  ind="$(min_indent "$1")"; ind="${ind:--1}"
  sub_block "$1" "$ind" "$2"
}

# ---------------------------------------------------------------------------
# Stage-command and checkout helpers.
# ---------------------------------------------------------------------------

# has_exact_run <job> <script> -- yes when some step of <job> runs EXACTLY
# that script. Exactness matters: the contract preserves the stage commands
# verbatim, so `bash scripts/ci.sh --lint --jobs 2` is a different command.
has_exact_run() {
  local n i step run
  if [ "$(has_job "$1")" != yes ]; then printf 'no such job'; return; fi
  n="$(n_steps "$1")"
  for ((i = 1; i <= n; i++)); do
    step="$(step_n "$1" "$i")"
    run="$(trim "$(step_scalar "$step" run)")"
    if [ "$run" = "$2" ]; then printf 'yes'; return; fi
  done
  printf 'no'
}

# checkout_fetch_depth <job> -- the fetch-depth the job's actions/checkout
# step asks for, or a sentinel naming what is missing instead.
checkout_fetch_depth() {
  local n i step uses w v
  if [ "$(has_job "$1")" != yes ]; then printf 'no such job'; return; fi
  n="$(n_steps "$1")"
  for ((i = 1; i <= n; i++)); do
    step="$(step_n "$1" "$i")"
    uses="$(unquote "$(trim "$(step_scalar "$step" uses)")")"
    case "$uses" in
      actions/checkout*) ;;
      *) continue ;;
    esac
    w="$(step_sub "$step" with)"
    v="$(trim "$(printf '%s\n' "$w" | sed -n 's/^[[:space:]]*fetch-depth:[[:space:]]*//p' | head -n1)")"
    if [ -n "$v" ]; then printf '%s' "$(unquote "$v")"; else printf 'unset'; fi
    return
  done
  printf 'no checkout step'
}

job_uses_checkout() { # <job>
  local n i step uses
  if [ "$(has_job "$1")" != yes ]; then printf 'no such job'; return; fi
  n="$(n_steps "$1")"
  for ((i = 1; i <= n; i++)); do
    step="$(step_n "$1" "$i")"
    uses="$(unquote "$(trim "$(step_scalar "$step" uses)")")"
    case "$uses" in
      actions/checkout*) printf 'yes'; return ;;
    esac
  done
  printf 'no'
}

# ---------------------------------------------------------------------------
# Aggregator simulation.
#
# The Errors and Edge-case clauses are runtime claims: what the `ci` job DOES
# when a dependency reports failure / cancelled / skipped. They are checkable
# without GitHub by substituting a result value into the job's expressions and
# evaluating the guard for real.
#
# The execution rule that keeps this safe: a step is evaluated ONLY when its
# `if:` or its `run:` mentions `needs.` before substitution. Nothing else in
# the workflow is ever executed by this suite — not the checkout, not
# `sudo locale-gen`, and above all not `bash scripts/ci.sh --lint`, which
# would recurse into the whole gate.
# ---------------------------------------------------------------------------

# subst_results <text> <lint result> <test result> [<bash-3 result>]
# [<test_macos result>]
# `${{ needs.x.result }}` is interpolated into shell text, so it becomes the
# bare value; a bare `needs.x.result` is expression context, so it becomes a
# quoted literal the expression evaluator can compare.
#
# The bash-3 stage (B19) is substituted under its DERIVED key, and the macOS
# stage (B08) under its fixed key `test_macos`; both default to `success`, so
# the two-argument callers below are unaffected: a workflow without the extra
# job has no `needs.<job>.result` for the extra rules to match, and a workflow
# with one gets a neutral value unless the caller says otherwise. The
# test_macos rules run FIRST: `needs.test.result` is a prefix of
# `needs.test_macos.result`, so the other order would corrupt the longer key.
subst_results() {
  local b3="${4:-success}" tm="${5:-success}"
  printf '%s\n' "$1" | sed -E \
    -e "s/\\\$\{\{[[:space:]]*needs\.test_macos\.result[[:space:]]*\}\}/$tm/g" \
    -e "s/needs\.test_macos\.result/'$tm'/g" \
    -e "s/\\\$\{\{[[:space:]]*needs\.lint\.result[[:space:]]*\}\}/$2/g" \
    -e "s/\\\$\{\{[[:space:]]*needs\.test\.result[[:space:]]*\}\}/$3/g" \
    -e "s/\\\$\{\{[[:space:]]*needs\.$BASH3_JOB\.result[[:space:]]*\}\}/$b3/g" \
    -e "s/needs\.lint\.result/'$2'/g" \
    -e "s/needs\.test\.result/'$3'/g" \
    -e "s/needs\.$BASH3_JOB\.result/'$b3'/g"
}

# gh_expr_true <substituted expression> -- yes / no / unsupported.
# Understands the always()/success()/failure()/cancelled() status functions
# and flat `==` / `!=` comparisons between string literals joined by && and
# ||. Anything else is reported as unsupported rather than guessed at.
gh_expr_true() {
  local e st
  e="$(norm_expr "$1")"
  if [ -z "$e" ]; then printf 'yes'; return; fi
  e="${e//always()/true}"
  e="${e//success()/true}"
  e="${e//failure()/false}"
  e="${e//cancelled()/false}"
  e="${e//\'/\"}"
  e="$(printf '%s' "$e" | sed -E \
    -e 's/("[^"]*")[[:space:]]*==[[:space:]]*("[^"]*")/[ \1 = \2 ]/g' \
    -e 's/("[^"]*")[[:space:]]*!=[[:space:]]*("[^"]*")/[ \1 != \2 ]/g')"
  if printf '%s' "$e" | grep -qE '[^][ "A-Za-z0-9_./=!&|-]'; then
    printf 'unsupported'; return
  fi
  ( eval "$e" ) >/dev/null 2>&1
  st=$?
  case "$st" in
    0) printf 'yes' ;;
    1) printf 'no' ;;
    *) printf 'unsupported' ;;
  esac
}

# simulate_ci <lint result> <test result> [<bash-3 result>]
# [<test_macos result>] -- pass / fail / unsupported: the verdict the `ci`
# job's own guard steps reach for those dependency results. "unsupported"
# means no guard was found, or one was found in a shape this evaluator will
# not guess at — never a silent pass.
# The third and fourth results default to `success`; see subst_results.
simulate_ci() {
  local lr="$1" tr_="$2" b3="${3:-success}" tm="${4:-success}" n i step ifexpr run gate sif srun evaluated=0
  n="$(n_steps ci)"
  if [ "$n" -eq 0 ]; then printf 'unsupported'; return; fi
  for ((i = 1; i <= n; i++)); do
    step="$(step_n ci "$i")"
    ifexpr="$(step_scalar "$step" if)"
    run="$(step_scalar "$step" run)"
    case "$ifexpr$run" in
      *needs.*) : ;;
      *) continue ;;
    esac
    evaluated=1
    sif="$(subst_results "$ifexpr" "$lr" "$tr_" "$b3" "$tm")"
    srun="$(subst_results "$run" "$lr" "$tr_" "$b3" "$tm")"
    # A `${{ }}` left in the SCRIPT is a context this suite did not
    # substitute (`github.*`, `steps.*`): bash would choke on it, so the run
    # is not simulatable. An `if:` may legitimately still be wrapped in
    # `${{ }}`; gh_expr_true unwraps it and judges what is inside.
    case "$srun" in
      *\$\{\{*) printf 'unsupported'; return ;;
    esac
    gate="$(gh_expr_true "$sif")"
    case "$gate" in
      unsupported) printf 'unsupported'; return ;;
      no) continue ;;
    esac
    [ -n "$(trim "$srun")" ] || continue
    # The runner's writable GITHUB_* sinks are pointed at the scratch dir, so
    # a guard that also appends to the step summary fails for its verdict and
    # never for an unset path.
    if ! (
      cd "$SCRATCH" || exit 1
      GITHUB_OUTPUT="$SCRATCH/github_output" \
      GITHUB_ENV="$SCRATCH/github_env" \
      GITHUB_PATH="$SCRATCH/github_path" \
      GITHUB_STEP_SUMMARY="$SCRATCH/github_step_summary" \
        bash -c "$srun"
    ) >/dev/null 2>&1; then
      printf 'fail'; return
    fi
  done
  if [ "$evaluated" -eq 0 ]; then printf 'unsupported'; return; fi
  printf 'pass'
}

# ===========================================================================
# Parse sanity. These exist so that a red suite is never an artefact of the
# file being unreadable or of the comment strip having eaten it.
# ===========================================================================

check "parse: the workflow exists at .github/workflows/ci.yml" \
  "$([ -f "$WORKFLOW" ] && echo yes || echo no)" "yes"
check "parse: the comment-stripped view is non-empty" \
  "$([ -s "$YAML" ] && echo yes || echo no)" "yes"
check "parse: the comment-stripped view holds no comment line (the B13 docblock cannot satisfy an assertion)" \
  "$(grep -c '^[[:space:]]*#' "$YAML" || true)" "0"
check "parse: a top-level jobs: mapping is present" \
  "$(yaml_grep '^jobs:')" "yes"

# ===========================================================================
# Behavior / Outputs — three jobs, and the check contexts they produce.
#
# GitHub derives a status-check context from the JOB KEY, unless a job-level
# `name:` overrides it. The `Protect master` ruleset requires the literal
# context `ci`, so both halves of that are asserted.
# ===========================================================================

# B19 supersedes B13's job count ("a fourth job runs the statusline plugin's
# test suites under a bash 3.2 interpreter"), and B08 supersedes B19's: a
# fifth job runs the test stage on macOS, under the fixed key `test_macos`.
# The count and the key set are therefore restated for five jobs. The bash-3
# job's key is not asserted, because no docblock fixes one; what is asserted
# is that there is exactly one job beyond the four named keys, so a sixth job
# is still caught.
check "jobs: the workflow declares exactly five jobs" \
  "$(job_names | grep -c . || true)" "5"
check "jobs: ci, lint, test and test_macos are still four of the five job keys" \
  "$(job_names | grep -Fx -e ci -e lint -e test -e test_macos | sort | tr '\n' ' ')" "ci lint test test_macos "
check "jobs: exactly one job key beyond ci, lint, test and test_macos — the bash-3 stage (B19)" \
  "$BASH3_JOB_COUNT" "1"

check "jobs: a job whose key is the literal string 'ci' exists (the required status check)" \
  "$(has_job ci)" "yes"
check "jobs: a job whose key is the literal string 'lint' exists" \
  "$(has_job lint)" "yes"
check "jobs: a job whose key is the literal string 'test' exists" \
  "$(has_job test)" "yes"

check "outputs: the ci job's check context is the literal string 'ci' (no job-level name: override)" \
  "$(job_context ci)" "ci"
check "outputs: the lint job's check context is 'lint'" \
  "$(job_context lint)" "lint"
check "outputs: the test job's check context is 'test'" \
  "$(job_context test)" "test"

check "behavior: the lint job declares its own runner" \
  "$(job_grep lint '^[[:space:]]*runs-on:')" "yes"
check "behavior: the test job declares its own runner" \
  "$(job_grep test '^[[:space:]]*runs-on:')" "yes"
check "behavior: the ci job declares its own runner" \
  "$(job_grep ci '^[[:space:]]*runs-on:')" "yes"

# ===========================================================================
# Behavior / Invariant — the stages run CONCURRENTLY: no needs edge between
# them. An edge either way restores the sequential runtime this block exists
# to remove.
# ===========================================================================

check "concurrency: the lint job does not name test in needs" \
  "$(job_needs lint test)" "no"
check "concurrency: the test job does not name lint in needs" \
  "$(job_needs test lint)" "no"
check "concurrency: the lint job declares no needs at all" \
  "$(job_grep lint '^[[:space:]]*needs:')" "no"
check "concurrency: the test job declares no needs at all" \
  "$(job_grep test '^[[:space:]]*needs:')" "no"

# ===========================================================================
# Behavior / Invariant — the aggregator depends on both stages.
# ===========================================================================

check "aggregator: the ci job needs the lint job" \
  "$(job_needs ci lint)" "yes"
check "aggregator: the ci job needs the test job" \
  "$(job_needs ci test)" "yes"
# B19 widens this from two dependencies to three, and B08 to four: each new
# job JOINS `needs:`, and nothing else may.
check "aggregator: the ci job needs exactly lint, test, test_macos and the bash-3 stage" \
  "$(job_list ci needs | sort | tr '\n' ' ')" \
  "$(printf '%s\n' lint test test_macos "$BASH3_JOB" | sort | tr '\n' ' ')"

# ===========================================================================
# Invariant — `if: always()` on the ci job, at JOB level.
#
# Without it a failed lint leaves the aggregator SKIPPED rather than FAILED,
# and a skipped required check does not block a merge: the gate would report
# green over a red stage. Asserted as a job-level key of the ci job
# specifically — a step-level `if:`, or an `always()` sitting in another job,
# does not satisfy it.
# ===========================================================================

check "aggregator: the ci job carries a job-level if: always()" \
  "$(norm_expr "$(job_inline ci if)")" "always()"

# ===========================================================================
# Invariant / Errors — the ci job asserts SUCCESS explicitly.
#
# A cancelled or timed-out job's result is neither 'success' nor 'failure',
# so only an equality test against 'success' makes those count as a failure.
# ===========================================================================

check "aggregator: the ci job compares needs.lint.result against the literal 'success'" \
  "$(job_grep ci "needs\.lint\.result[^=!]*(==|!=|=)[^=]*success|success[^=!]*(==|!=|=)[^=]*needs\.lint\.result")" "yes"
check "aggregator: the ci job compares needs.test.result against the literal 'success'" \
  "$(job_grep ci "needs\.test\.result[^=!]*(==|!=|=)[^=]*success|success[^=!]*(==|!=|=)[^=]*needs\.test\.result")" "yes"
check "aggregator: no result is compared against 'failure' (that would let a cancelled stage through)" \
  "$(job_grep ci "(==|!=|=)[[:space:]]*[\"']*failure|contains\([^)]*result[^)]*failure")" "no"

# ===========================================================================
# Errors / Edge cases — the guard's actual verdict per dependency result.
#
# These execute the ci job's guard with substituted results. "unsupported"
# means no guard step was found at all (today's unsplit workflow) or one was
# found in a shape this evaluator declines to guess at.
# ===========================================================================

check "edge case: both stages succeed -> the ci guard passes" \
  "$(simulate_ci success success)" "pass"
check "edge case: lint fails, test passes -> the ci guard fails" \
  "$(simulate_ci failure success)" "fail"
check "edge case: lint passes, test fails -> the ci guard fails" \
  "$(simulate_ci success failure)" "fail"
check "edge case: both stages fail -> the ci guard fails" \
  "$(simulate_ci failure failure)" "fail"
check "edge case: the lint stage is CANCELLED -> the ci guard fails" \
  "$(simulate_ci cancelled success)" "fail"
check "edge case: the test stage is CANCELLED -> the ci guard fails" \
  "$(simulate_ci success cancelled)" "fail"
check "edge case: the lint stage is SKIPPED -> the ci guard fails" \
  "$(simulate_ci skipped success)" "fail"

# ===========================================================================
# Invariant — each stage's environment is preserved exactly, so the split is
# observable only to a stopwatch.
# ===========================================================================

check "preservation: the lint job checks out the repo with actions/checkout" \
  "$(job_uses_checkout lint)" "yes"
check "preservation: the test job checks out the repo with actions/checkout" \
  "$(job_uses_checkout test)" "yes"
check "preservation: the lint job's checkout sets fetch-depth: 0" \
  "$(checkout_fetch_depth lint)" "0"
check "preservation: the test job's checkout sets fetch-depth: 0" \
  "$(checkout_fetch_depth test)" "0"

check "preservation: the lint job installs the en_US.UTF-8 locale" \
  "$(job_grep lint 'locale-gen[[:space:]]+en_US\.UTF-8')" "yes"
check "preservation: the test job installs the en_US.UTF-8 locale" \
  "$(job_grep test 'locale-gen[[:space:]]+en_US\.UTF-8')" "yes"
check "preservation: the lint job runs update-locale" \
  "$(job_grep lint 'update-locale')" "yes"
check "preservation: the test job runs update-locale" \
  "$(job_grep test 'update-locale')" "yes"

check "preservation: LC_ALL is en_US.UTF-8 on the test stage" \
  "$(job_grep test 'LC_ALL[^A-Za-z0-9]*en_US\.UTF-8')" "yes"
check "preservation: the lint stage sets no LC_ALL at all" \
  "$(job_grep lint 'LC_ALL')" "no"
check "preservation: no workflow-level env leaks LC_ALL onto both stages" \
  "$(printf '%s\n' "$(top_block_re '^env:')" | grep -c 'LC_ALL' || true)" "0"

check "preservation: the lint job runs exactly 'bash scripts/ci.sh --lint'" \
  "$(has_exact_run lint 'bash scripts/ci.sh --lint')" "yes"
check "preservation: the test job runs exactly 'bash scripts/ci.sh --test'" \
  "$(has_exact_run test 'bash scripts/ci.sh --test')" "yes"
check "preservation: the lint job never runs the test stage" \
  "$(job_grep lint 'ci\.sh.*--test')" "no"
check "preservation: the test job never runs the lint stage" \
  "$(job_grep test 'ci\.sh.*--lint')" "no"
check "preservation: the aggregator runs no ci.sh stage of its own" \
  "$(job_grep ci 'scripts/ci\.sh')" "no"
# B08's macOS stage invokes the same script through Homebrew bash
# ("$(brew --prefix)/bin/bash"), so a bash path ending in /bash, optionally
# quoted, is accepted alongside the bare `bash` the Linux stages use.
check "preservation: every scripts/ci.sh invocation is exactly a stage command under a bash interpreter" \
  "$(grep -F 'scripts/ci.sh' "$YAML" | grep -cvE '(^|[[:space:]/])bash\"?[[:space:]]+scripts/ci\.sh[[:space:]]+--(lint|test)[[:space:]]*$' || true)" "0"

# ===========================================================================
# Invariant — scripts/ci.sh is not touched by this block.
#
# "Unmodified since some baseline" is a git-diff property no committed test
# can hold an opinion on: on master the tree is always clean, and off master
# it would fail for edits that have nothing to do with this block. What IS
# assertable, and is what the workflow actually depends on, is that the two
# independent stage flags still exist in ci.sh and that the workflow uses
# nothing else from it.
# ===========================================================================

check "ci.sh: the script the stages invoke exists" \
  "$([ -f "$CI_SCRIPT" ] && echo yes || echo no)" "yes"
check "ci.sh: --lint is still parsed as its own stage flag" \
  "$(grep -cE '^[[:space:]]*--lint\)' "$CI_SCRIPT" || true)" "1"
check "ci.sh: --test is still parsed as its own stage flag" \
  "$(grep -cE '^[[:space:]]*--test\)' "$CI_SCRIPT" || true)" "1"

# ===========================================================================
# Inputs — pull_request and push against master, and nothing else.
# ===========================================================================

ON_BLOCK="$(top_block_re "^[\"']?on[\"']?:")"
ON_INDENT="$(min_indent "$ON_BLOCK")"; ON_INDENT="${ON_INDENT:--1}"

check "inputs: the workflow triggers on exactly the pull_request and push events" \
  "$(keys_at "$ON_BLOCK" "$ON_INDENT" | sort | tr '\n' ' ')" "pull_request push "
check "inputs: pull_request is limited to the master branch" \
  "$(scalar_list "$(sub_block "$ON_BLOCK" "$ON_INDENT" pull_request)" \
      "$(min_indent "$(sub_block "$ON_BLOCK" "$ON_INDENT" pull_request)")" branches | tr '\n' ' ')" "master "
check "inputs: push is limited to the master branch" \
  "$(scalar_list "$(sub_block "$ON_BLOCK" "$ON_INDENT" push)" \
      "$(min_indent "$(sub_block "$ON_BLOCK" "$ON_INDENT" push)")" branches | tr '\n' ' ')" "master "

check "inputs: no secrets are referenced" "$(yaml_grep 'secrets\.')" "no"
check "inputs: no repository variables are referenced" "$(yaml_grep '(^|[^A-Za-z_.])vars\.')" "no"
check "inputs: no workflow inputs are declared" "$(yaml_grep '^[[:space:]]*inputs:')" "no"
check "inputs: nothing is read from .claude/" "$(yaml_grep '\.claude/')" "no"
check "inputs: nothing is read from .local/" "$(yaml_grep '\.local/')" "no"

# ===========================================================================
# Contract: B08 macOS test stage (plan 001-macos-test-portability) — the
# fifth job, under the fixed key `test_macos`.
#
# It runs the SAME test stage as `test`, on a macos-latest runner, so the
# suites execute under a BSD userland on every pull request. The runner's
# /bin/bash is 3.2, which lacks constructs ci.sh relies on (mapfile), so the
# stage runs under Homebrew bash — the interpreter a Homebrew macOS dev box
# resolves first in PATH. No locale-gen step: the tool does not exist on
# macOS and the runners ship en_US.UTF-8 already.
# ===========================================================================

check "b08: a job whose key is the literal string 'test_macos' exists" \
  "$(has_job test_macos)" "yes"
check "b08: the test_macos job's check context is 'test_macos' (no name: override)" \
  "$(job_context test_macos)" "test_macos"
check "b08: the test_macos job runs on macOS" \
  "$(case "$(job_inline test_macos runs-on)" in *macos*) echo yes ;; *) echo no ;; esac)" "yes"
check "b08: the test_macos job checks out the repo with actions/checkout" \
  "$(job_uses_checkout test_macos)" "yes"
check "b08: the test_macos job's checkout sets fetch-depth: 0" \
  "$(checkout_fetch_depth test_macos)" "0"

check "b08: LC_ALL is en_US.UTF-8 on the macOS stage" \
  "$(job_grep test_macos 'LC_ALL[^A-Za-z0-9]*en_US\.UTF-8')" "yes"
check "b08: no locale-gen step (the tool does not exist on macOS)" \
  "$(job_grep test_macos 'locale-gen')" "no"

check "b08: the macOS stage runs ci.sh --test under Homebrew bash (the runner's /bin/bash is 3.2)" \
  "$(job_grep test_macos 'brew --prefix.*/bin/bash.*scripts/ci\.sh[[:space:]]+--test')" "yes"
check "b08: the macOS stage ensures Homebrew bash is present" \
  "$(job_grep test_macos 'brew (list|install) bash')" "yes"
check "b08: the test_macos job never runs the lint stage" \
  "$(job_grep test_macos 'ci\.sh.*--lint')" "no"

# The macOS stage runs CONCURRENTLY with the other stages: no needs edge in
# either direction.
check "b08: the test_macos job declares no needs at all" \
  "$(job_grep test_macos '^[[:space:]]*needs:')" "no"
check "b08: neither lint nor test declares a needs edge onto test_macos" \
  "$(
    if [ "$(job_needs lint test_macos)" = no ] \
      && [ "$(job_needs test test_macos)" = no ]; then echo yes; else echo no; fi
  )" "yes"

# The aggregator gains the job and asserts its result on == 'success', so a
# cancelled or skipped macOS stage counts as failure like every other stage.
check "b08: the ci job needs test_macos" \
  "$(job_needs ci test_macos)" "yes"
check "b08: the ci job compares needs.test_macos.result against the literal 'success'" \
  "$(job_grep ci "needs\.test_macos\.result[^=!]*(==|!=|=)[^=]*success|success[^=!]*(==|!=|=)[^=]*needs\.test_macos\.result")" "yes"

check "b08 edge case: all four stages succeed -> the ci guard passes" \
  "$(simulate_ci success success success success)" "pass"
check "b08 edge case: the macOS stage fails -> the ci guard fails" \
  "$(simulate_ci success success success failure)" "fail"
check "b08 edge case: the macOS stage is CANCELLED -> the ci guard fails" \
  "$(simulate_ci success success success cancelled)" "fail"
check "b08 edge case: the macOS stage is SKIPPED -> the ci guard fails" \
  "$(simulate_ci success success success skipped)" "fail"

# ===========================================================================
# Contract: B19 ci-bash3-gate — the fourth job.
#
# Everything below asserts against $BASH3_JOB, derived above as the job key
# that is neither lint, test nor ci. While no such job exists, the helpers
# answer "no such job" rather than "no", so a negative assertion cannot be
# satisfied by the job's absence.
#
# B19's Inputs clause ("the same pull_request and push events, no repository
# variables, no secrets, nothing from .claude/ or .local/") is asserted
# file-wide by the Inputs section above and is not restated here. Nor is
# "the lint and test jobs are untouched": their steps, `fetch-depth: 0`,
# locale install and `LC_ALL` are each already asserted by the preservation
# section, and B19 changes none of those claims.
# ===========================================================================

check "b19: a fourth job exists, distinct from lint, test and ci" \
  "$(has_job "$BASH3_JOB")" "yes"
check "b19: the bash-3 job declares its own runner" \
  "$(job_grep "$BASH3_JOB" '^[[:space:]]*runs-on:')" "yes"
check "b19: the bash-3 job runs on ubuntu (macos-latest ships a real 3.2.57 but costs ten times the minutes and brings a BSD userland)" \
  "$(case "$(job_inline "$BASH3_JOB" runs-on)" in *ubuntu*) echo yes ;; *) echo no ;; esac)" "yes"
check "b19: the bash-3 job's check context is its own key — no name: override stealing another context" \
  "$(job_context "$BASH3_JOB")" "$BASH3_JOB"
check "b19: the bash-3 job checks out the repo (it runs a script from it)" \
  "$(job_uses_checkout "$BASH3_JOB")" "yes"

# ---------------------------------------------------------------------------
# Invariant — the new job runs CONCURRENTLY with the other two stages. A needs
# edge in either direction serialises what is deliberately concurrent.
# ---------------------------------------------------------------------------

check "b19: the bash-3 job does not name lint in needs" \
  "$(job_needs "$BASH3_JOB" lint)" "no"
check "b19: the bash-3 job does not name test in needs" \
  "$(job_needs "$BASH3_JOB" test)" "no"
check "b19: the bash-3 job declares no needs at all" \
  "$(job_grep "$BASH3_JOB" '^[[:space:]]*needs:')" "no"
check "b19: the bash-3 job exists and neither lint nor test declares a needs edge onto it" \
  "$(
    if [ "$(has_job "$BASH3_JOB")" = yes ] \
      && [ "$(job_needs lint "$BASH3_JOB")" = no ] \
      && [ "$(job_needs test "$BASH3_JOB")" = no ]; then echo yes; else echo no; fi
  )" "yes"

# ---------------------------------------------------------------------------
# Invariant — the gate script is standalone and is called directly;
# scripts/ci.sh is not invoked by this job. (The file-wide check above already
# proves every scripts/ci.sh invocation in the workflow is one of the two
# stage commands; this scopes the claim to the new job's own lines.)
# ---------------------------------------------------------------------------

check "b19: the bash-3 job invokes scripts/bash3-gate.sh" \
  "$(job_grep "$BASH3_JOB" 'scripts/bash3-gate\.sh')" "yes"
check "b19: the bash-3 job does not invoke scripts/ci.sh" \
  "$(job_grep "$BASH3_JOB" 'scripts/ci\.sh')" "no"
check "b19: the bash-3 job hands the built interpreter to the gate with --bash" \
  "$(job_grep "$BASH3_JOB" '--bash([[:space:]]|=)')" "yes"

# ---------------------------------------------------------------------------
# Invariant — the build prerequisites. These are not decoration: without
# `bison` the build dies at `yacc -d ./parse.y`, and that is a red `ci` on
# every pull request until someone diagnoses it. The four -Wno-* flags are what
# let 3.2-era C compile under a modern gcc.
# ---------------------------------------------------------------------------

check "b19: the bash-3 job installs bison (without it make dies at 'yacc -d ./parse.y')" \
  "$(job_grep "$BASH3_JOB" '(^|[^A-Za-z0-9_-])bison([^A-Za-z0-9_-]|$)')" "yes"
check "b19: the build sets CFLAGS" \
  "$(job_grep "$BASH3_JOB" 'CFLAGS')" "yes"
check "b19: CFLAGS carries -Wno-implicit-function-declaration" \
  "$(job_grep "$BASH3_JOB" '-Wno-implicit-function-declaration')" "yes"
check "b19: CFLAGS carries -Wno-implicit-int" \
  "$(job_grep "$BASH3_JOB" '-Wno-implicit-int')" "yes"
check "b19: CFLAGS carries -Wno-return-mismatch" \
  "$(job_grep "$BASH3_JOB" '-Wno-return-mismatch')" "yes"
check "b19: CFLAGS carries -Wno-int-conversion" \
  "$(job_grep "$BASH3_JOB" '-Wno-int-conversion')" "yes"
check "b19: the job builds bash 3.2.57 specifically" \
  "$(job_grep "$BASH3_JOB" '3\.2\.57')" "yes"
check "b19: the built interpreter is cached (a miss is a ~90s build, a hit is a restore)" \
  "$(job_grep "$BASH3_JOB" 'actions/cache')" "yes"
check "b19: the bash-3 job exists and runs on the runner, not in the bash:3.2 container (that image keeps bash off /bin/bash and brings a busybox userland)" \
  "$(
    if [ "$(has_job "$BASH3_JOB")" = yes ] \
      && [ "$(job_grep "$BASH3_JOB" '^[[:space:]]*container:')" = no ] \
      && [ "$(yaml_grep 'bash:3\.2')" = no ]; then echo yes; else echo no; fi
  )" "yes"

# ---------------------------------------------------------------------------
# Invariant — the aggregator gains the new job and asserts its result on
# `== 'success'`, so a cancelled or skipped bash-3 stage counts as failure
# exactly as the other two do. The `ci` job itself is neither renamed nor
# replaced: ruleset 19719395 requires that literal context, and the checks
# asserting has_job ci / job_context ci / if: always() above are unchanged.
# ---------------------------------------------------------------------------

check "b19: the ci job needs the bash-3 job" \
  "$(job_needs ci "$BASH3_JOB")" "yes"
check "b19: the ci job compares the bash-3 job's result against the literal 'success'" \
  "$(job_grep ci "needs\.$BASH3_JOB\.result[^=!]*(==|!=|=)[^=]*success|success[^=!]*(==|!=|=)[^=]*needs\.$BASH3_JOB\.result")" "yes"

# ---------------------------------------------------------------------------
# Errors / Edge cases — the guard's actual verdict for the three-input case,
# evaluated for real rather than asserted on the string 'success' appearing.
# GitHub reports a job that exceeds its timeout as `failure`; `cancelled` and
# `skipped` are the results that ONLY an `== 'success'` test catches.
# ---------------------------------------------------------------------------

check "b19 edge case: all three stages succeed -> the ci guard passes" \
  "$(
    if [ "$(job_needs ci "$BASH3_JOB")" = yes ]; then
      simulate_ci success success success
    else
      printf 'ci does not depend on the bash-3 job'
    fi
  )" "pass"
check "b19 edge case: the bash-3 stage fails (a timeout is reported as failure) -> the ci guard fails" \
  "$(simulate_ci success success failure)" "fail"
check "b19 edge case: the bash-3 stage is CANCELLED -> the ci guard fails" \
  "$(simulate_ci success success cancelled)" "fail"
check "b19 edge case: the bash-3 stage is SKIPPED -> the ci guard fails" \
  "$(simulate_ci success success skipped)" "fail"
check "b19 edge case: lint fails and the bash-3 stage succeeds -> the ci guard still fails" \
  "$(simulate_ci failure success success)" "fail"

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
