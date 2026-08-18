#!/usr/bin/env bash
# bash3-gate.test.sh — contract tests for scripts/bash3-gate.sh
# (B19 ci-bash3-gate, plan 003-statusline-meter-colour).
#
# Subject: scripts/bash3-gate.sh. The "Contract: B19 ci-bash3-gate" docblock
# at the top of that file is the source of truth.
#
# HOW A BASH-3 GATE IS TESTED ON A BASH-5 MACHINE
#
# This suite runs under `scripts/ci.sh --test`, which CI runs on ubuntu under
# bash 5 with no compiler and no network. A real bash 3.2 binary is therefore
# not available and may not be required. The lever the contract leaves open is
# that the gate validates what the interpreter REPORTS: "--bash <path> ... must
# exist, be executable, and report a 3.x version".
#
# So every scenario hands the gate an interpreter SHIM: a small script under
# mktemp that answers `--version` with a chosen banner (3.2.57 for the accept
# path, 5.2.21 for the reject path), sets $BASH_VERSION to the same value for a
# `-c` probe, LOGS every invocation, and otherwise execs the real bash so the
# fixture suites genuinely run. That log is what turns "the gate ran the suites
# under the interpreter it was given" from an inference into an assertion, and
# what makes "it never fell back to a newer bash" checkable directly.
#
# What the shim CANNOT fake is ${BASH_VERSINFO[@]}: bash marks that array
# readonly at startup, so no fixture on a bash-5 host can make it report 3. A
# version check reading BASH_VERSINFO is not exercisable here; read
# `--version`, or $BASH_VERSION under `-c`.
#
# THE SUITE LIST IS NOT AN INPUT, SO THE FIXTURE IS A FAKE REPO ROOT
#
# The gate takes only --bash and --timeout — no environment variables, no
# config files — and its suite list is a literal array in its own source,
# pointing into plugins/statusline/. Tests therefore copy the REAL script into
# a fake repo root under mktemp, git-init that root, and plant fixture suites
# at exactly the paths the script names. The gate under test is the real one;
# the suites it runs are this file's. It never runs the real suites — only
# fixture suites planted at matching paths. Section 14 asserts that.
#
# The declared set is LEARNED from the gate's own per-suite lines rather than
# hardcoded, because the contract fixes that line's format
# ("<path>  rc=<n>  PASS=<n>  FAIL=<n>") but not which suites are in the list.
# Section 3 cross-checks the learned set against the script's source, so the
# derivation cannot quietly shrink to nothing and take the assertions with it.
#
# TWO TRAPS THIS SUITE AVOIDS
#
# 1. Counting. The house harness prints "PASS  <label>" lines plus an
#    "ALL PASS" / "FAILURES" trailer. A gate counting `grep -c PASS` reports 4
#    where 3 is right; `grep -c FAIL` reports 2 where 1 is right. Every fixture
#    prints the trailers, so the asserted counts are the discriminating ones.
# 2. A wrong-reason pass off the contract comment. The docblock quotes nearly
#    every string worth asserting — "BASH3 PASS", the 120 default, the excluded
#    suite's path. Structural assertions therefore run against $CODE, the
#    script with its comment lines stripped, and a parse-sanity check proves
#    that view really is comment-free.
#
# Hermetic: reads scripts/bash3-gate.sh, writes only under mktemp, no network.
# Mirrors the PASS/FAIL harness style of scripts/ci-workflow.test.sh and the
# fixture-tree / record-invocation style of scripts/pre-push.test.sh.
#
# Run: bash scripts/bash3-gate.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/bash3-gate.sh"

# Resolved BEFORE any scenario prepends a shim directory to PATH, so a shim can
# exec the real interpreter instead of recursing into itself.
REAL_BASH="$(command -v bash)"

BASH3_VER='3.2.57(2)-release'
BASH5_VER='5.2.21(1)-release'

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# A missing or unimplemented gate must not abort the run: it is reported as
# failed assertions, which is the honest verdict.
SCRATCH="$(mktemp -d)"
CODE="$SCRATCH/gate.code"
cleanup() { rm -rf -- "$SCRATCH"; }
trap cleanup EXIT

: > "$CODE"
if [ -f "$GATE" ]; then
  grep -v '^[[:space:]]*#' "$GATE" | grep -v '^[[:space:]]*$' > "$CODE"
fi

# ---------------------------------------------------------------------------
# Small helpers.
# ---------------------------------------------------------------------------
contains() { # <text> <needle> -- yes/no
  case "$1" in *"$2"*) printf 'yes' ;; *) printf 'no' ;; esac
}

# Suite paths hold only [A-Za-z0-9_./-], so `.` is the sole ERE metacharacter
# that needs neutralising before a path becomes part of a pattern.
re_escape() { printf '%s' "$1" | sed 's/\./\\./g'; }

last_line() { # <text> -- the last non-blank line
  printf '%s\n' "$1" | grep -v '^[[:space:]]*$' | tail -n1
}

code_grep() { # <ERE> -- yes/no over the comment-stripped script
  if grep -Eq -- "$1" "$CODE"; then printf 'yes'; else printf 'no'; fi
}

nonempty() { # <text> -- yes/no
  if [ -n "$1" ]; then printf 'yes'; else printf 'no'; fi
}

# ---------------------------------------------------------------------------
# Interpreter shims.
# ---------------------------------------------------------------------------

# new_shim <bare version> -- prints a fresh directory holding an executable
# `bash` that REPORTS that version. Its calls.log records one line per
# invocation, so which interpreter ran which suite is directly observable.
new_shim() {
  local d ver="$1"
  d="$(mktemp -d "$SCRATCH/shim.XXXXXX")"
  : > "$d/calls.log"
  cat > "$d/bash" <<SHIM
#!/bin/bash
printf '%s\n' "\$*" >> '$d/calls.log'
case "\${1:-}" in
  --version|-version)
    echo "GNU bash, version $ver (x86_64-unknown-linux-gnu)"
    echo "Copyright (C) 2007 Free Software Foundation, Inc."
    exit 0
    ;;
  -c)
    shift
    __cmd="\${1:-}"
    if [ \$# -gt 0 ]; then shift; fi
    exec '$REAL_BASH' -c "BASH_VERSION='$ver'
\$__cmd" bash "\$@"
    ;;
esac
exec '$REAL_BASH' "\$@"
SHIM
  chmod +x "$d/bash"
  printf '%s' "$d"
}

shim_ran_a_suite() { # <shim dir> -- yes/no: was it ever asked to run a suite?
  if grep -q '\.test\.sh' "$1/calls.log" 2>/dev/null; then
    printf 'yes'
  else
    printf 'no'
  fi
}

# ---------------------------------------------------------------------------
# Fake repo roots and fixture suites.
# ---------------------------------------------------------------------------

# new_root -- a git-initialised fake repo root holding a copy of the REAL gate
# script and a canary scripts/ci.sh. The canary is what makes "scripts/ci.sh is
# not invoked" a behavioural assertion rather than only a grep: if the gate
# ever shells out to it, a marker file appears.
new_root() {
  local root
  root="$(mktemp -d "$SCRATCH/root.XXXXXX")"
  mkdir -p "$root/scripts" "$root/plugins/statusline/scripts" \
           "$root/plugins/statusline/lib"
  if [ -f "$GATE" ]; then
    cp "$GATE" "$root/scripts/bash3-gate.sh"
    chmod +x "$root/scripts/bash3-gate.sh"
  fi
  {
    printf '#!/bin/bash\n'
    printf ": > '%s/RAN-ci.sh'\nexit 0\n" "$root"
  } > "$root/scripts/ci.sh"
  chmod +x "$root/scripts/ci.sh"
  git init -q "$root" >/dev/null 2>&1 || true
  printf '%s' "$root"
}

# write_fixture <root> <relpath> <kind> -- a fixture suite in house format.
#   pass     3 PASS lines + an "ALL PASS" trailer, exit 0  -> PASS=3 FAIL=0
#   fail     1 PASS + 1 FAIL line + a "FAILURES" trailer, exit 1 -> PASS=1 FAIL=1
#   slow     no stdout at all, sleeps well past a small timeout, exit 0
#   noisy    2 PASS lines on stdout, chatter on stderr, exit 0 -> PASS=2 FAIL=0
#   naptime  1 PASS line after a 3-second sleep, exit 0 -> PASS=1 FAIL=0
# Every kind records its own path in <root>/RAN.log first, so what actually ran
# is observable independently of what the gate reports about it.
write_fixture() {
  local root="$1" rel="$2" kind="$3" f="$1/$2"
  mkdir -p "$(dirname "$f")"
  {
    printf '#!/bin/bash\n'
    printf "echo '%s' >> '%s/RAN.log'\n" "$rel" "$root"
    case "$kind" in
      pass)
        cat <<'BODY'
echo "PASS  alpha"
echo "PASS  beta"
echo "PASS  gamma"
echo "----"
echo "ALL PASS"
exit 0
BODY
        ;;
      fail)
        cat <<'BODY'
echo "PASS  alpha"
echo "FAIL  beta -> got 'x', expected 'y'"
echo "----"
echo "FAILURES"
exit 1
BODY
        ;;
      slow)
        cat <<'BODY'
sleep 5
exit 0
BODY
        ;;
      noisy)
        cat <<'BODY'
echo "PASS  alpha"
echo "chatter on stderr, which the gate does not read" >&2
echo "PASS  beta"
echo "more chatter" >&2
echo "----"
echo "ALL PASS"
exit 0
BODY
        ;;
      naptime)
        cat <<'BODY'
sleep 3
echo "PASS  alpha"
echo "----"
echo "ALL PASS"
exit 0
BODY
        ;;
    esac
  } > "$f"
  chmod +x "$f"
}

ran() { # <root> <relpath> -- yes/no: did that fixture actually execute?
  if [ -f "$1/RAN.log" ] && grep -Fxq -- "$2" "$1/RAN.log"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

ci_sh_ran() { # <root> -- yes/no
  if [ -e "$1/RAN-ci.sh" ]; then printf 'yes'; else printf 'no'; fi
}

# ---------------------------------------------------------------------------
# Invocation. Wrapped in `timeout` as a suite-level safety net: a gate that
# forgets its own per-suite timeout must not hang the repo's whole test stage.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
POLLUTE=0

run_gate() { # <root> <PATH prefix dir or ""> [args...]
  local root="$1" pathpre="$2"
  shift 2
  local out err
  out="$(mktemp)"; err="$(mktemp)"
  (
    cd "$root" || exit 1
    if [ -n "$pathpre" ]; then PATH="$pathpre:$PATH"; export PATH; fi
    if [ "$POLLUTE" -eq 1 ]; then
      # Plausible config-by-environment names. The contract says the gate reads
      # NO environment variables, so none of these may change anything.
      export SUITES=/dev/null TIMEOUT=1 BASH3_TIMEOUT=1 BASH3_BASH=/nonexistent
      export BASH3_GATE_SUITES=/dev/null BASH3_GATE_TIMEOUT=1
      export GATE_TIMEOUT=1 GATE_BASH=/nonexistent BASH_PATH=/nonexistent
    fi
    timeout 120 "$REAL_BASH" "$root/scripts/bash3-gate.sh" "$@"
  ) >"$out" 2>"$err"
  RUN_EXIT=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  rm -f "$out" "$err"
}

# ---------------------------------------------------------------------------
# Reading the gate's report.
# ---------------------------------------------------------------------------

# verdict_kind <output> -- PASS / FAIL / none, from the final non-blank line.
verdict_kind() {
  case "$(last_line "$1")" in
    'BASH3 PASS') printf 'PASS' ;;
    'BASH3 FAIL:'*) printf 'FAIL' ;;
    *) printf 'none' ;;
  esac
}

verdict_names() { # <output> <relpath> -- yes/no
  contains "$(last_line "$1")" "$2"
}

# suite_line_ok <output> <relpath> <rc> <pass> <fail> -- yes/no.
# The contract writes the line as "<path>  rc=<n>  PASS=<n>  FAIL=<n>". The
# amount of whitespace is not asserted and the path may be reported absolute or
# repo-relative; the tokens, their values and their order are asserted.
suite_line_ok() {
  local re
  re="(^|/)$(re_escape "$2")[[:space:]]+rc=$3[[:space:]]+PASS=$4[[:space:]]+FAIL=$5[[:space:]]*$"
  if printf '%s\n' "$1" | grep -Eq -- "$re"; then printf 'yes'; else printf 'no'; fi
}

# suite_lines_present <output> -- the declared suite paths, in report order. A
# per-suite line is the one carrying the rc= field; an exclusion line, which
# carries a reason instead, is deliberately not matched here.
suite_lines_present() {
  printf '%s\n' "$1" \
    | sed -n 's/^\(.*[^[:space:]]\)[[:space:]]\{1,\}rc=[0-9]\{1,\}[[:space:]]\{1,\}PASS=.*/\1/p' \
    | sed 's#^.*\(plugins/\)#\1#'
}

# exclusion_line <output> <relpath> -- the line naming <relpath> that is NOT a
# per-suite report line.
exclusion_line() {
  printf '%s\n' "$1" | grep -F -- "$2" | grep -v 'rc=' | head -n1
}

# exclusion_reason_len <output> <relpath> -- characters on that line beyond the
# path itself, or -1 when there is no such line. A bare path dump scores near
# zero; a path plus a reason scores well clear of the threshold asserted below.
exclusion_reason_len() {
  local line
  line="$(exclusion_line "$1" "$2")"
  if [ -z "$line" ]; then printf '%s' '-1'; return; fi
  printf '%s' "$(( ${#line} - ${#2} ))"
}

# before_verdict <output> <relpath> -- yes/no: is the exclusion line printed
# BEFORE the verdict, as the Outputs clause orders it?
before_verdict() {
  local n_excl n_verdict
  n_excl="$(printf '%s\n' "$1" | grep -nF -- "$2" | grep -v 'rc=' | head -n1 | cut -d: -f1)"
  n_verdict="$(printf '%s\n' "$1" | grep -n '^BASH3 ' | tail -n1 | cut -d: -f1)"
  if [ -n "$n_excl" ] && [ -n "$n_verdict" ] && [ "$n_excl" -lt "$n_verdict" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

mentions_unbound() { # <stderr text> -- yes/no
  contains "$1" 'unbound variable'
}

# ===========================================================================
# 1. Parse sanity. A red suite must never be an artefact of an unreadable
#    script or of the comment strip having eaten it.
# ===========================================================================

check "1. parse: the gate script exists at scripts/bash3-gate.sh" \
  "$([ -f "$GATE" ] && echo yes || echo no)" "yes"
check "1. parse: the comment-stripped view is non-empty" \
  "$([ -s "$CODE" ] && echo yes || echo no)" "yes"
check "1. parse: the comment-stripped view holds no comment line (the B19 docblock cannot satisfy an assertion)" \
  "$(grep -c '^[[:space:]]*#' "$CODE" || true)" "0"
check "1. parse: a real bash interpreter was resolved for the shims" \
  "$([ -x "$REAL_BASH" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 2. Inputs / Invariants — structural claims about the script's own source.
#
# "The suite list is a literal array in this file. It is NOT globbed and must
# never become a glob" is a claim about the SOURCE, not only about behaviour:
# a glob expanding to the same set today satisfies every behavioural assertion
# in this file and still widens the gate next month. So it is asserted where it
# lives, over the comment-stripped view.
# ===========================================================================

SRC_PATHS="$(grep -oE 'plugins/[A-Za-z0-9_./-]+\.test\.sh' "$CODE" | sort -u || true)"
N_SRC="$(printf '%s\n' "$SRC_PATHS" | grep -c . || true)"

# array_paths_of <script file> -- the suite paths sitting inside an array
# literal, i.e. between `NAME=(` and the `)` closing it, with comment lines
# stripped first so a docblock cannot supply one.
array_paths_of() {
  grep -v '^[[:space:]]*#' "$1" 2>/dev/null | awk '
    {
      line = $0
      if (!inarr && line ~ /=\(/) inarr = 1
      if (inarr) {
        while (match(line, /plugins\/[A-Za-z0-9_.\/-]+\.test\.sh/)) {
          print substr(line, RSTART, RLENGTH)
          line = substr(line, RSTART + RLENGTH)
        }
      }
      if (inarr && $0 ~ /\)/) inarr = 0
    }
  ' | sort -u
}

ARRAY_PATHS="$(array_paths_of "$GATE")"

check "2. literal list: the script names at least one suite path (an empty gate is not a contract)" \
  "$([ "$N_SRC" -ge 1 ] && echo yes || echo no)" "yes"
check "2. literal list: every suite path the script names sits inside an array literal" \
  "$(printf '%s\n' "$ARRAY_PATHS" | grep -c . || true)" "$N_SRC"
check "2. literal list: no *.test.sh glob pattern appears in the code" \
  "$(code_grep '\*\.test\.sh')" "no"
check "2. literal list: the suite set is not discovered with find" \
  "$(code_grep '(^|[^A-Za-z_])find[[:space:]]')" "no"
check "2. literal list: the suite set is not discovered with compgen" \
  "$(code_grep 'compgen')" "no"
check "2. literal list: globstar is not enabled to widen a path" \
  "$(code_grep 'globstar')" "no"

check "2. scope: every suite path the script names is under plugins/statusline/" \
  "$(printf '%s\n' "$SRC_PATHS" | grep -c '^plugins/statusline/' || true)" "$N_SRC"
check "2. scope: repo tooling under scripts/ is not a bash-3 target, so no scripts/*.test.sh is listed" \
  "$(code_grep '(^|[^A-Za-z0-9_/-])scripts/[A-Za-z0-9_.-]+\.test\.sh')" "no"

check "2. invariant: scripts/ci.sh is never named in the code" \
  "$(code_grep 'ci\.sh')" "no"
check "2. inputs: nothing is read from .claude/" "$(code_grep '\.claude/')" "no"
check "2. inputs: nothing is read from .local/" "$(code_grep '\.local/')" "no"
check "2. inputs: the 120-second default timeout is in the code, not only in the docblock" \
  "$(code_grep '(^|[^0-9])120([^0-9]|$)')" "yes"

# ===========================================================================
# 3. Behavior / Outputs — the accept path, and where the declared set is
#    LEARNED.
#
# Fixture suites are planted at every suite path the script names — declared
# and excluded alike — so this run depends on nothing but the gate's own
# reporting: whatever it prints an rc= line for is declared, whatever it names
# without one is excluded. Both halves are cross-checked against the source
# below, so a derivation that found nothing cannot pass for a gate that
# excluded everything.
# ===========================================================================

ROOT_OK="$(new_root)"
SHIM3="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_OK" "$p" pass
done <<< "$SRC_PATHS"

run_gate "$ROOT_OK" "" --bash "$SHIM3/bash"
OK_OUT="$RUN_OUT"; OK_EXIT="$RUN_EXIT"

DECLARED=()
while IFS= read -r p; do
  [ -n "$p" ] && DECLARED+=("$p")
done < <(suite_lines_present "$OK_OUT")
N_DECLARED="${#DECLARED[@]}"

EXCLUDED=()
while IFS= read -r p; do
  [ -z "$p" ] && continue
  printf '%s\n' "${DECLARED[@]+"${DECLARED[@]}"}" | grep -Fxq -- "$p" || EXCLUDED+=("$p")
done <<< "$SRC_PATHS"

FIRST="plugins/statusline/scripts/__no_suite_declared__.test.sh"
LAST="$FIRST"
if [ "$N_DECLARED" -ge 1 ]; then
  FIRST="${DECLARED[0]}"
  LAST="${DECLARED[$((N_DECLARED - 1))]}"
fi

# The "all" / "none" sentinels below exist so that a run with ZERO declared
# suites reports "0/0" and fails, rather than satisfying a bare count
# comparison and turning an unimplemented gate into a green suite.

all_suite_lines() { # <output> <rc> <pass> <fail>
  local n=0 k=0 s
  for s in ${DECLARED[@]+"${DECLARED[@]}"}; do
    n=$((n + 1))
    if [ "$(suite_line_ok "$1" "$s" "$2" "$3" "$4")" = yes ]; then k=$((k + 1)); fi
  done
  if [ "$n" -ge 1 ] && [ "$k" -eq "$n" ]; then printf 'all'; else printf '%s/%s' "$k" "$n"; fi
}

all_ran() { # <root>
  local n=0 k=0 s
  for s in ${DECLARED[@]+"${DECLARED[@]}"}; do
    n=$((n + 1))
    if [ "$(ran "$1" "$s")" = yes ]; then k=$((k + 1)); fi
  done
  if [ "$n" -ge 1 ] && [ "$k" -eq "$n" ]; then printf 'all'; else printf '%s/%s' "$k" "$n"; fi
}

none_ran() { # <root> -- "none" only when suites were declared and none of them ran
  local n=0 k=0 s
  for s in ${DECLARED[@]+"${DECLARED[@]}"}; do
    n=$((n + 1))
    if [ "$(ran "$1" "$s")" = yes ]; then k=$((k + 1)); fi
  done
  if [ "$n" -ge 1 ] && [ "$k" -eq 0 ]; then printf 'none'; else printf '%s of %s ran' "$k" "$n"; fi
}

all_under_shim() { # <shim dir> -- each declared suite handed to that interpreter
  local n=0 k=0 s
  for s in ${DECLARED[@]+"${DECLARED[@]}"}; do
    n=$((n + 1))
    if grep -Fq -- "$s" "$1/calls.log" 2>/dev/null; then k=$((k + 1)); fi
  done
  if [ "$n" -ge 1 ] && [ "$k" -eq "$n" ]; then printf 'all'; else printf '%s/%s' "$k" "$n"; fi
}

none_excluded_ran() { # <root>
  local k=0 s
  for s in ${EXCLUDED[@]+"${EXCLUDED[@]}"}; do
    if [ "$(ran "$1" "$s")" = yes ]; then k=$((k + 1)); fi
  done
  if [ "$k" -eq 0 ]; then printf 'none'; else printf '%s ran' "$k"; fi
}

in_array_source() { # -- every declared suite path also appears in a literal array
  local n=0 k=0 s
  for s in ${DECLARED[@]+"${DECLARED[@]}"}; do
    n=$((n + 1))
    if printf '%s\n' "$ARRAY_PATHS" | grep -Fxq -- "$s"; then k=$((k + 1)); fi
  done
  if [ "$n" -ge 1 ] && [ "$k" -eq "$n" ]; then printf 'all'; else printf '%s/%s' "$k" "$n"; fi
}

check "3. accept: at least one suite is declared and reported on" \
  "$([ "$N_DECLARED" -ge 1 ] && echo yes || echo no)" "yes"
check "3. accept: every path the script names is either declared or excluded, none unaccounted for" \
  "$(( N_DECLARED + ${#EXCLUDED[@]} ))" "$N_SRC"
check "3. accept: every declared suite path appears in a literal array in the source" \
  "$(in_array_source)" "all"

check "3. accept: every declared suite passing exits 0" "$OK_EXIT" "0"
check "3. accept: the final line is exactly 'BASH3 PASS'" "$(last_line "$OK_OUT")" "BASH3 PASS"
check "3. accept: one per-suite line each, rc=0 PASS=3 FAIL=0 (the 'ALL PASS' trailer is not a fourth pass)" \
  "$(all_suite_lines "$OK_OUT" 0 3 0)" "all"
check "3. accept: every declared suite actually executed" "$(all_ran "$ROOT_OK")" "all"
check "3. accept: every declared suite was run under the interpreter given to --bash" \
  "$(all_under_shim "$SHIM3")" "all"
check "3. accept: scripts/ci.sh was not invoked" "$(ci_sh_ran "$ROOT_OK")" "no"

# ===========================================================================
# 4. Invariant — context.test.sh is now declared (bash-4-only constructs
#    removed), and the exclusion set is empty.
# ===========================================================================

CONTEXT_SUITE="plugins/statusline/scripts/context.test.sh"

check "4. context.test.sh IS in the declared set" \
  "$(printf '%s\n' "${DECLARED[@]+"${DECLARED[@]}"}" | grep -Fxq -- "$CONTEXT_SUITE" && echo yes || echo no)" "yes"
check "4. no exclusions remain" \
  "${#EXCLUDED[@]}" "0"

# ===========================================================================
# 5. Outputs / Errors — a failing suite: exit 1, and a verdict naming the FIRST
#    failing suite.
# ===========================================================================

ROOT_F1="$(new_root)"
SHIM_F1="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ "$p" = "$FIRST" ]; then write_fixture "$ROOT_F1" "$p" fail
  else write_fixture "$ROOT_F1" "$p" pass; fi
done <<< "$SRC_PATHS"
run_gate "$ROOT_F1" "" --bash "$SHIM_F1/bash"
F1_OUT="$RUN_OUT"; F1_EXIT="$RUN_EXIT"

check "5. fail: a failing suite exits 1" "$F1_EXIT" "1"
check "5. fail: the verdict is a BASH3 FAIL line" "$(verdict_kind "$F1_OUT")" "FAIL"
check "5. fail: the verdict names the failing suite" "$(verdict_names "$F1_OUT" "$FIRST")" "yes"
check "5. fail: its per-suite line is rc=1 PASS=1 FAIL=1 (the 'FAILURES' trailer is not a second FAIL)" \
  "$(suite_line_ok "$F1_OUT" "$FIRST" 1 1 1)" "yes"
check "5. fail: the exclusions are still printed on a failing run" \
  "$(contains "$F1_OUT" "$CONTEXT_SUITE")" "yes"

# The LAST suite failing and the rest passing: proves the verdict tracks the
# failure rather than echoing the first entry of the list.
ROOT_F2="$(new_root)"
SHIM_F2="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ "$p" = "$LAST" ]; then write_fixture "$ROOT_F2" "$p" fail
  else write_fixture "$ROOT_F2" "$p" pass; fi
done <<< "$SRC_PATHS"
run_gate "$ROOT_F2" "" --bash "$SHIM_F2/bash"
F2_OUT="$RUN_OUT"; F2_EXIT="$RUN_EXIT"

check "5. fail(last): exit 1 when only the last declared suite fails" "$F2_EXIT" "1"
check "5. fail(last): the verdict names that suite" "$(verdict_names "$F2_OUT" "$LAST")" "yes"

# Every suite failing: the verdict names the FIRST of them, and the run does
# not abandon the remaining suites.
ROOT_F3="$(new_root)"
SHIM_F3="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_F3" "$p" fail
done <<< "$SRC_PATHS"
run_gate "$ROOT_F3" "" --bash "$SHIM_F3/bash"
F3_OUT="$RUN_OUT"; F3_EXIT="$RUN_EXIT"

check "5. fail(all): exit 1" "$F3_EXIT" "1"
check "5. fail(all): the verdict names the first failing suite" \
  "$(verdict_names "$F3_OUT" "$FIRST")" "yes"
check "5. fail(all): every suite still ran — one failure does not abandon the rest" \
  "$(all_ran "$ROOT_F3")" "all"

# ===========================================================================
# 6. Errors — a declared suite whose file is ABSENT is a failure, not a skip.
#    A gate that skips what it cannot find reports green on a repo that moved
#    the file.
# ===========================================================================

ROOT_ABS="$(new_root)"
SHIM_ABS="$(new_shim "$BASH3_VER")"
run_gate "$ROOT_ABS" "" --bash "$SHIM_ABS/bash"
ABS_OUT="$RUN_OUT"; ABS_EXIT="$RUN_EXIT"

check "6. absent: a missing declared suite exits 1, not 0" "$ABS_EXIT" "1"
check "6. absent: the verdict is a BASH3 FAIL line" "$(verdict_kind "$ABS_OUT")" "FAIL"
check "6. absent: the verdict names the first missing suite" \
  "$(verdict_names "$ABS_OUT" "$FIRST")" "yes"
check "6. absent: the run is not reported as a pass" \
  "$(contains "$ABS_OUT" 'BASH3 PASS')" "no"

# ===========================================================================
# 7. Errors — a suite that exceeds the timeout is a FAILURE, reported as one,
#    and NAMED in the verdict. Exercised with a real slow fixture and a tiny
#    --timeout, because the clause is about what the gate does to a process
#    that will not finish, not about a flag being parsed.
# ===========================================================================

ROOT_TO="$(new_root)"
SHIM_TO="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ "$p" = "$FIRST" ]; then write_fixture "$ROOT_TO" "$p" slow
  else write_fixture "$ROOT_TO" "$p" pass; fi
done <<< "$SRC_PATHS"
run_gate "$ROOT_TO" "" --bash "$SHIM_TO/bash" --timeout 1
TO_OUT="$RUN_OUT"; TO_EXIT="$RUN_EXIT"

others_ran() { # <root> -- every declared suite EXCEPT $FIRST
  local n=0 k=0 s
  for s in ${DECLARED[@]+"${DECLARED[@]}"}; do
    [ "$s" = "$FIRST" ] && continue
    n=$((n + 1))
    if [ "$(ran "$1" "$s")" = yes ]; then k=$((k + 1)); fi
  done
  if [ "$k" -eq "$n" ]; then printf 'all'; else printf '%s/%s' "$k" "$n"; fi
}

check "7. timeout: a suite that overruns exits 1 (a failure, not a usage error)" "$TO_EXIT" "1"
check "7. timeout: the verdict is a BASH3 FAIL line" "$(verdict_kind "$TO_OUT")" "FAIL"
check "7. timeout: the verdict names the suite that overran" \
  "$(verdict_names "$TO_OUT" "$FIRST")" "yes"
check "7. timeout: its per-suite line reports rc=124, the timeout's own code" \
  "$(suite_line_ok "$TO_OUT" "$FIRST" 124 0 0)" "yes"
check "7. timeout: the suites after it still ran — one overrun does not abandon the gate" \
  "$(others_ran "$ROOT_TO")" "all"

# ===========================================================================
# 8. Inputs / Errors / Invariant — interpreter validation, and the invariant
#    the whole block exists for: the gate NEVER falls back to a newer bash.
#    Every rejection is asserted twice — on the exit code, and on the fact that
#    no suite ran at all.
# ===========================================================================

ROOT_MISSING="$(new_root)"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_MISSING" "$p" pass
done <<< "$SRC_PATHS"
run_gate "$ROOT_MISSING" "" --bash "$SCRATCH/definitely-not-here/bash"
check "8. interpreter: a missing interpreter is exit 2" "$RUN_EXIT" "2"
check "8. interpreter: a missing interpreter puts a message on stderr" "$(nonempty "$RUN_ERR")" "yes"
check "8. interpreter: a missing interpreter runs no suite (no fallback to the shell in hand)" \
  "$(none_ran "$ROOT_MISSING")" "none"

NOEXEC="$(mktemp -d "$SCRATCH/noexec.XXXXXX")"
{
  printf '#!/bin/bash\n'
  printf 'echo "GNU bash, version %s (x86_64-unknown-linux-gnu)"\n' "$BASH3_VER"
} > "$NOEXEC/bash"
chmod 644 "$NOEXEC/bash"
ROOT_NOEXEC="$(new_root)"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_NOEXEC" "$p" pass
done <<< "$SRC_PATHS"
run_gate "$ROOT_NOEXEC" "" --bash "$NOEXEC/bash"
check "8. interpreter: a non-executable interpreter is exit 2, though its contents would report 3.2" \
  "$RUN_EXIT" "2"
check "8. interpreter: a non-executable interpreter puts a message on stderr" \
  "$(nonempty "$RUN_ERR")" "yes"
check "8. interpreter: a non-executable interpreter runs no suite" \
  "$(none_ran "$ROOT_NOEXEC")" "none"

ROOT_B5="$(new_root)"
SHIM5="$(new_shim "$BASH5_VER")"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_B5" "$p" pass
done <<< "$SRC_PATHS"
run_gate "$ROOT_B5" "" --bash "$SHIM5/bash"
B5_EXIT="$RUN_EXIT"

check "8. no-fallback: an interpreter reporting 5.x is exit 2, never a pass" "$B5_EXIT" "2"
check "8. no-fallback: it puts a message on stderr" "$(nonempty "$RUN_ERR")" "yes"
check "8. no-fallback: it does not report BASH3 PASS" "$(contains "$RUN_OUT" 'BASH3 PASS')" "no"
check "8. no-fallback: NO suite was handed to the rejected interpreter" \
  "$(shim_ran_a_suite "$SHIM5")" "no"
check "8. no-fallback: NO suite ran under any other interpreter either" \
  "$(none_ran "$ROOT_B5")" "none"
check "8. no-fallback: scripts/ci.sh was not invoked as a consolation run" \
  "$(ci_sh_ran "$ROOT_B5")" "no"

# ===========================================================================
# 9. Inputs — the defaults: `bash` on PATH, and 120 seconds.
#
#    The interpreter default is asserted through a PATH-resolved shim rather
#    than the host's own bash, so the result is the same on a bash-3 host and a
#    bash-5 one.
# ===========================================================================

ROOT_DEF="$(new_root)"
SHIM_DEF3="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_DEF" "$p" pass
done <<< "$SRC_PATHS"
run_gate "$ROOT_DEF" "$SHIM_DEF3"
check "9. default --bash: with no flag the gate uses bash from PATH (a 3.x one is accepted)" \
  "$RUN_EXIT" "0"
check "9. default --bash: the PATH interpreter is what ran the suites" \
  "$(all_under_shim "$SHIM_DEF3")" "all"

ROOT_DEF5="$(new_root)"
SHIM_DEF5="$(new_shim "$BASH5_VER")"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_DEF5" "$p" pass
done <<< "$SRC_PATHS"
run_gate "$ROOT_DEF5" "$SHIM_DEF5"
check "9. edge case: only bash 5 available and no --bash given -> exit 2, not a green run that proves nothing" \
  "$RUN_EXIT" "2"
check "9. edge case: that message goes to stderr" "$(nonempty "$RUN_ERR")" "yes"
check "9. edge case: and no suite is run under it" "$(shim_ran_a_suite "$SHIM_DEF5")" "no"

# A 3-second suite under the DEFAULT timeout must pass. Section 2 asserts the
# literal 120 is in the code; only a real run shows the default in force is not
# some small value that would kill an ordinary suite.
ROOT_DT="$(new_root)"
SHIM_DT="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ "$p" = "$FIRST" ]; then write_fixture "$ROOT_DT" "$p" naptime
  else write_fixture "$ROOT_DT" "$p" pass; fi
done <<< "$SRC_PATHS"
run_gate "$ROOT_DT" "" --bash "$SHIM_DT/bash"
check "9. default --timeout: a 3-second suite is not killed by the default timeout" \
  "$RUN_EXIT" "0"
check "9. default --timeout: that suite reports rc=0, not the timeout's 124" \
  "$(suite_line_ok "$RUN_OUT" "$FIRST" 0 1 0)" "yes"

# ===========================================================================
# 10. Errors — flag usage. Every one of these is exit 2 with a usage message on
#     stderr, and specifically NOT a `set -u` unbound-variable abort: the
#     contract says the two outcomes are distinguishable and that the tests
#     assert on the difference. A set -u abort exits 1 or 127 with a bash
#     diagnostic naming an unbound variable; the contract requires exit 2 with
#     a usage message naming the flag.
# ===========================================================================

usage_case() { # <description> <flag the message must name> <args...>
  local desc="$1" flag="$2" root p
  shift 2
  root="$(new_root)"
  while IFS= read -r p; do
    [ -n "$p" ] && write_fixture "$root" "$p" pass
  done <<< "$SRC_PATHS"
  run_gate "$root" "" "$@"
  check "10. usage: $desc -> exit 2" "$RUN_EXIT" "2"
  check "10. usage: $desc -> a usage message on stderr naming $flag" \
    "$(contains "$RUN_ERR" "$flag")" "yes"
  check "10. usage: $desc -> not a set -u unbound-variable abort" \
    "$(mentions_unbound "$RUN_ERR")" "no"
  check "10. usage: $desc -> no suite ran" "$(none_ran "$root")" "none"
}

usage_case "--bash as the final argument" "--bash" --bash
usage_case "--timeout as the final argument" "--timeout" --timeout
usage_case "--bash followed by another flag" "--bash" --bash --timeout 5
usage_case "--timeout followed by another flag" "--timeout" --timeout --bash /bin/bash
usage_case "--timeout with a non-integer value" "--timeout" --timeout abc
usage_case "--timeout with zero" "--timeout" --timeout 0
usage_case "--timeout with a negative value" "--timeout" --timeout -1

# ===========================================================================
# 11. Edge case — a suite that passes but writes to stderr is still a pass.
#     This gate reads exit codes and PASS/FAIL counts, not stderr.
# ===========================================================================

ROOT_NOISY="$(new_root)"
SHIM_NOISY="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ "$p" = "$FIRST" ]; then write_fixture "$ROOT_NOISY" "$p" noisy
  else write_fixture "$ROOT_NOISY" "$p" pass; fi
done <<< "$SRC_PATHS"
run_gate "$ROOT_NOISY" "" --bash "$SHIM_NOISY/bash"

check "11. stderr: a suite that writes to stderr but exits 0 still passes" "$RUN_EXIT" "0"
check "11. stderr: the verdict is still BASH3 PASS" "$(last_line "$RUN_OUT")" "BASH3 PASS"
check "11. stderr: its per-suite line reports rc=0 PASS=2 FAIL=0" \
  "$(suite_line_ok "$RUN_OUT" "$FIRST" 0 2 0)" "yes"

# ===========================================================================
# 12. Outputs — the three exit codes are distinct from one another, asserted in
#     one place so that "everything returns 1" cannot satisfy the sections
#     above piecemeal.
# ===========================================================================

check "12. exit codes: pass / suite-failure / usage are 0, 1 and 2 respectively" \
  "$OK_EXIT/$F1_EXIT/$B5_EXIT" "0/1/2"

# ===========================================================================
# 13. Inputs — "No environment variables. No config files."
#
#     The same fixture root is run twice, once with a set of plausible
#     gate-configuration variables exported. An identical report and an
#     identical exit code is what that clause means operationally: a gate
#     honouring $TIMEOUT=1 would kill its own suites and diverge.
# ===========================================================================

ROOT_ENV="$(new_root)"
SHIM_ENV="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_ENV" "$p" pass
done <<< "$SRC_PATHS"

run_gate "$ROOT_ENV" "" --bash "$SHIM_ENV/bash"
CLEAN_OUT="$RUN_OUT"; CLEAN_EXIT="$RUN_EXIT"
POLLUTE=1
run_gate "$ROOT_ENV" "" --bash "$SHIM_ENV/bash"
POLLUTE=0
DIRTY_OUT="$RUN_OUT"; DIRTY_EXIT="$RUN_EXIT"

check "13. env: a polluted environment does not change the exit code" \
  "$DIRTY_EXIT" "$CLEAN_EXIT"
check "13. env: a polluted environment does not change one byte of the report" \
  "$DIRTY_OUT" "$CLEAN_OUT"

# ===========================================================================
# 14. Edge case — zero declared suites is exit 2. An empty gate is a
#     configuration error, not a vacuous pass.
#
#     The suite list is not an input, so this runs against a VARIANT of the
#     real script with its declared paths removed: every line that is nothing
#     but a suite path is deleted, and a single-line array holding them is
#     emptied. Exclusion entries survive, because an entry carrying a reason is
#     never a bare path. The two fixture-sanity checks come first so that a
#     transform which did not apply reports itself, rather than masquerading as
#     a defect in the gate.
# ===========================================================================

ROOT_ZERO="$(new_root)"
SHIM_ZERO="$(new_shim "$BASH3_VER")"
ZERO_GATE="$ROOT_ZERO/scripts/bash3-gate.sh"
if [ -f "$ZERO_GATE" ]; then
  sed -i.bak \
    -e '/^[[:space:]]*"\{0,1\}plugins\/[A-Za-z0-9_./-]*\.test\.sh"\{0,1\}[[:space:]]*$/d' \
    -e 's/\(=(\)[^)]*plugins[^)]*)/\1)/' \
    "$ZERO_GATE"
  rm -f "$ZERO_GATE.bak"
fi
# The fixtures are still planted: a gate that fell back to globbing them up off
# the filesystem would have something to find.
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_ZERO" "$p" pass
done <<< "$SRC_PATHS"

ZERO_ARRAY_PATHS="$(array_paths_of "$ZERO_GATE")"

check "14. fixture sanity: the zero-suite variant is still a parsable script" \
  "$([ -f "$ZERO_GATE" ] && "$REAL_BASH" -n "$ZERO_GATE" 2>/dev/null && echo yes || echo no)" "yes"
# Exclusion entries are meant to survive the transform — an entry carrying a
# reason is not a bare path — so this counts only the DECLARED paths left
# behind, which must be none.
check "14. fixture sanity: no declared suite path survives in the variant's arrays" \
  "$(
    left=0
    for s in ${DECLARED[@]+"${DECLARED[@]}"}; do
      if printf '%s\n' "$ZERO_ARRAY_PATHS" | grep -Fxq -- "$s"; then left=$((left + 1)); fi
    done
    printf '%s' "$left"
  )" "0"

run_gate "$ROOT_ZERO" "" --bash "$SHIM_ZERO/bash"
check "14. zero suites: an empty declared list is exit 2, not a vacuous pass" "$RUN_EXIT" "2"
check "14. zero suites: it puts a message on stderr" "$(nonempty "$RUN_ERR")" "yes"
check "14. zero suites: it does not report BASH3 PASS" \
  "$(contains "$RUN_OUT" 'BASH3 PASS')" "no"
check "14. zero suites: no suite is globbed up off the filesystem to fill the gap" \
  "$(shim_ran_a_suite "$SHIM_ZERO")" "no"

# ===========================================================================
# 15. Hermeticity of this suite itself: no real plugin suite was ever executed,
#     which is what keeps this file's runtime independent of another block's
#     suite.
# ===========================================================================

check "15. hermetic: no interpreter was ever asked to run a suite inside this repo" \
  "$(
    found=no
    for d in "$SCRATCH"/shim.*; do
      [ -f "$d/calls.log" ] || continue
      if grep -q -- "$(re_escape "$REPO_ROOT")" "$d/calls.log"; then found=yes; fi
    done
    printf '%s' "$found"
  )" "no"
check "15. hermetic: the repo's own scripts/bash3-gate.sh is still readable and unmodified in place" \
  "$([ -f "$GATE" ] && [ -r "$GATE" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 16. Contract: B07 bash3-gate-timeout-fallback / resolve_timeout.
#
#     resolve_timeout takes no arguments and reads only PATH, so it is
#     exercised directly: the function's source is extracted from the real
#     gate script and evaluated in a child bash whose PATH is a fixture
#     directory holding exactly the candidates that scenario is about. Nothing
#     private is touched — the assertions are on stdout and the return code,
#     which is the whole of its interface.
#
#     Fixture candidates are shell scripts, not binaries, so these scenarios
#     behave identically on macOS/BSD and GNU/Linux and depend on nothing the
#     host does or does not have installed.
# ===========================================================================

# The utilities the gate itself needs. A fixture PATH holds links to these and
# to the chosen timeout candidates, and to nothing else — which is how "no
# timeout binary exists" is made true for a process on a host that has one.
PATH_UTILS="sh bash env mktemp grep sed awk cat cut tail head rm mkdir chmod
sleep dirname basename pwd tr sort uniq git"

# Resolved BEFORE any PATH override, so both the fixture candidates and this
# suite's own outer safety net keep working inside a PATH that deliberately has
# no timeout on it at all.
REAL_TIMEOUT="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"

# new_pathdir <spec> -- prints a directory to be used as an entire PATH.
#   both        a usable `timeout` and a usable `gtimeout`
#   timeout     only a usable `timeout`
#   gtimeout    only a usable `gtimeout`
#   broken      only a `gtimeout` whose --version fails
#   none        neither candidate
# Each candidate logs its invocations to <dir>/<name>-calls.log and, for a real
# run, drops its duration argument and execs the command — enough for the gate
# to run a suite under it.
new_pathdir() {
  local spec="$1" d u src
  d="$(mktemp -d "$SCRATCH/pathdir.XXXXXX")"
  for u in $PATH_UTILS; do
    src="$(command -v "$u" 2>/dev/null || true)"
    if [ -n "$src" ] && [ ! -e "$d/$u" ]; then
      ln -s "$src" "$d/$u" 2>/dev/null || true
    fi
  done
  case "$spec" in
    both)     _mk_timeout "$d" timeout ok; _mk_timeout "$d" gtimeout ok ;;
    timeout)  _mk_timeout "$d" timeout ok ;;
    gtimeout) _mk_timeout "$d" gtimeout ok ;;
    broken)   _mk_timeout "$d" gtimeout broken ;;
    none)     : ;;
  esac
  printf '%s' "$d"
}

_mk_timeout() { # <dir> <name> ok|broken
  local d="$1" name="$2" kind="$3"
  rm -f "$d/$name"
  {
    printf '#!/bin/bash\n'
    printf "printf '%%s\\\\n' \"\$*\" >> '%s/%s-calls.log'\n" "$d" "$name"
    # SC2016: the `${1:-}` here is shim source text being written out, not an
    # expansion this script should perform — single quotes are required.
    # shellcheck disable=SC2016
    if [ "$kind" = ok ]; then
      printf 'case "${1:-}" in --version) echo "%s (GNU coreutils) 9.4"; exit 0 ;; esac\n' "$name"
    else
      printf 'case "${1:-}" in --version) echo "%s: broken" >&2; exit 1 ;; esac\n' "$name"
    fi
    if [ -n "$REAL_TIMEOUT" ]; then
      # A usable candidate really enforces its duration, so a slow suite still
      # reports the timeout's own 124.
      printf "exec '%s' \"\$@\"\n" "$REAL_TIMEOUT"
    else
      printf 'shift\nexec "$@"\n'
    fi
  } > "$d/$name"
  chmod +x "$d/$name"
}

# The function under test, lifted out of the real script.
RESOLVE_FN="$SCRATCH/resolve_timeout.sh"
: > "$RESOLVE_FN"
if [ -f "$GATE" ]; then
  awk '/^resolve_timeout\(\)/ { f = 1 } f { print } f && /^\}[[:space:]]*$/ { exit }' \
    "$GATE" > "$RESOLVE_FN"
fi

R_OUT=""
R_RC=0
call_resolve() { # <pathdir>
  local o
  o="$(mktemp)"
  # SC2016: `$1` is the inner `bash -c` script's own positional, bound below by
  # the `_ "$RESOLVE_FN"` arguments — it must not expand here.
  # shellcheck disable=SC2016
  PATH="$1" "$REAL_BASH" -c '. "$1"; resolve_timeout' _ "$RESOLVE_FN" \
    >"$o" 2>/dev/null
  R_RC=$?
  R_OUT="$(cat "$o")"
  rm -f "$o"
}

check "16. fixture sanity: resolve_timeout's definition was found in the gate script" \
  "$([ -s "$RESOLVE_FN" ] && echo yes || echo no)" "yes"
check "16. fixture sanity: the extracted definition is parsable on its own" \
  "$("$REAL_BASH" -n "$RESOLVE_FN" 2>/dev/null && echo yes || echo no)" "yes"

PD_BOTH="$(new_pathdir both)"
call_resolve "$PD_BOTH"
check "16. edge case: with both candidates usable, resolve_timeout prefers 'timeout'" \
  "$R_OUT" "timeout"
check "16. edge case: preferring 'timeout' returns 0" "$R_RC" "0"

PD_T="$(new_pathdir timeout)"
call_resolve "$PD_T"
check "16. behavior: with only 'timeout' usable it resolves to 'timeout'" "$R_OUT" "timeout"
check "16. behavior: that resolution returns 0" "$R_RC" "0"

PD_G="$(new_pathdir gtimeout)"
call_resolve "$PD_G"
check "16. behavior: with only 'gtimeout' usable it falls back to 'gtimeout'" \
  "$R_OUT" "gtimeout"
check "16. behavior: the gtimeout fallback returns 0" "$R_RC" "0"

PD_BROKEN="$(new_pathdir broken)"
call_resolve "$PD_BROKEN"
check "16. edge case: a gtimeout present but broken (--version fails) is not resolved" \
  "$R_RC" "1"
check "16. edge case: a broken gtimeout leaves stdout empty (probed, not merely resolved on PATH)" \
  "$R_OUT" ""

PD_NONE="$(new_pathdir none)"
call_resolve "$PD_NONE"
check "16. errors: neither candidate usable returns 1" "$R_RC" "1"
check "16. errors: neither candidate usable prints nothing on stdout" "$R_OUT" ""

check "16. invariant: resolve_timeout mutates no global — a caller's own name is untouched" \
  "$(
    # SC2016: `$1` and `$TIMEOUT_CMD` belong to the inner `bash -c` script;
    # expanding them out here would defeat the invariant under test.
    # shellcheck disable=SC2016
    PATH="$PD_BOTH" "$REAL_BASH" -c \
      '. "$1"; TIMEOUT_CMD=sentinel; resolve_timeout >/dev/null 2>&1; printf "%s" "$TIMEOUT_CMD"' \
      _ "$RESOLVE_FN" 2>/dev/null
  )" "sentinel"

# ===========================================================================
# 17. Errors (caller half) — on a machine with NEITHER candidate, the gate
#     warns once on stderr, naming both candidates, and still runs its suites
#     unbounded rather than reporting rc=127 for every one of them. A gate that
#     shells out to a `timeout` that is not there fails every suite with 127
#     and reads as a repo-wide breakage; that is the failure this clause
#     exists to prevent.
# ===========================================================================

run_gate_with_path() { # <root> <entire PATH> [args...]
  local root="$1" newpath="$2"
  shift 2
  local out err
  out="$(mktemp)"; err="$(mktemp)"
  (
    cd "$root" || exit 1
    PATH="$newpath"; export PATH
    if [ -n "$REAL_TIMEOUT" ]; then
      "$REAL_TIMEOUT" 120 "$REAL_BASH" "$root/scripts/bash3-gate.sh" "$@"
    else
      "$REAL_BASH" "$root/scripts/bash3-gate.sh" "$@"
    fi
  ) >"$out" 2>"$err"
  RUN_EXIT=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  rm -f "$out" "$err"
}

stderr_line_count() { # <text> -- non-blank lines
  printf '%s\n' "$1" | grep -c '[^[:space:]]' || true
}

# Whole words, so "gtimeout" alone cannot satisfy "names timeout".
names_word() { # <text> <word> -- yes/no
  if printf '%s\n' "$1" | grep -Eq "(^|[^A-Za-z0-9_-])$2([^A-Za-z0-9_-]|$)"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

ROOT_NOTO="$(new_root)"
SHIM_NOTO="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_NOTO" "$p" pass
done <<< "$SRC_PATHS"
run_gate_with_path "$ROOT_NOTO" "$PD_NONE" --bash "$SHIM_NOTO/bash"
NOTO_OUT="$RUN_OUT"; NOTO_ERR="$RUN_ERR"; NOTO_EXIT="$RUN_EXIT"

check "17. no timeout binary: the gate still exits 0 when every suite passes" \
  "$NOTO_EXIT" "0"
check "17. no timeout binary: the verdict is still exactly 'BASH3 PASS'" \
  "$(last_line "$NOTO_OUT")" "BASH3 PASS"
check "17. no timeout binary: suites run unbounded, reporting rc=0 PASS=3 FAIL=0, never rc=127" \
  "$(all_suite_lines "$NOTO_OUT" 0 3 0)" "all"
check "17. no timeout binary: no per-suite line reports rc=127" \
  "$(printf '%s\n' "$NOTO_OUT" | grep -c 'rc=127' || true)" "0"
check "17. no timeout binary: every declared suite actually executed" \
  "$(all_ran "$ROOT_NOTO")" "all"
check "17. no timeout binary: a warning is written to stderr" \
  "$(nonempty "$NOTO_ERR")" "yes"
check "17. no timeout binary: that warning is a single line" \
  "$(stderr_line_count "$NOTO_ERR")" "1"
check "17. no timeout binary: the warning names the 'timeout' candidate" \
  "$(names_word "$NOTO_ERR" 'timeout')" "yes"
check "17. no timeout binary: the warning names the 'gtimeout' candidate" \
  "$(names_word "$NOTO_ERR" 'gtimeout')" "yes"
check "17. no timeout binary: the exclusions are still printed" \
  "$(contains "$NOTO_OUT" "$CONTEXT_SUITE")" "yes"

# A machine with only Homebrew's prefixed coreutils: no warning at all, and the
# gate bounds its suites with gtimeout.
ROOT_GT="$(new_root)"
SHIM_GT="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_GT" "$p" pass
done <<< "$SRC_PATHS"
run_gate_with_path "$ROOT_GT" "$PD_G" --bash "$SHIM_GT/bash"
GT_ERR="$RUN_ERR"; GT_EXIT="$RUN_EXIT"

check "17. gtimeout only: the gate passes" "$GT_EXIT" "0"
check "17. gtimeout only: no warning is emitted when a candidate was resolved" \
  "$(stderr_line_count "$GT_ERR")" "0"
check "17. gtimeout only: the resolved gtimeout is what bounded the suites" \
  "$([ -s "$PD_G/gtimeout-calls.log" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 18. Invariant — with GNU coreutils installed unprefixed, the gate's
#     observable behavior is byte-identical to today's. Asserted as the report
#     from a run whose PATH holds an unprefixed `timeout` being byte-identical
#     to the same fixture root's report on the unmodified PATH of this host,
#     which is what "today" means for this suite.
# ===========================================================================

ROOT_BASE="$(new_root)"
SHIM_BASE="$(new_shim "$BASH3_VER")"
while IFS= read -r p; do
  [ -n "$p" ] && write_fixture "$ROOT_BASE" "$p" pass
done <<< "$SRC_PATHS"

run_gate "$ROOT_BASE" "" --bash "$SHIM_BASE/bash"
BASE_OUT="$RUN_OUT"; BASE_ERR="$RUN_ERR"; BASE_EXIT="$RUN_EXIT"

PD_BOTH2="$(new_pathdir timeout)"
run_gate_with_path "$ROOT_BASE" "$PD_BOTH2" --bash "$SHIM_BASE/bash"
CORE_OUT="$RUN_OUT"; CORE_ERR="$RUN_ERR"; CORE_EXIT="$RUN_EXIT"

check "18. unchanged: with an unprefixed timeout the exit code is today's" \
  "$CORE_EXIT" "$BASE_EXIT"
check "18. unchanged: with an unprefixed timeout the report is byte-identical to today's" \
  "$CORE_OUT" "$BASE_OUT"
check "18. unchanged: nothing new is written to stderr on that path" \
  "$CORE_ERR" "$BASE_ERR"
check "18. unchanged: the unprefixed timeout is the command the gate used" \
  "$([ -s "$PD_BOTH2/timeout-calls.log" ] && echo yes || echo no)" "yes"
check "18. unchanged: a timeout is still enforced — a slow suite reports rc=124" \
  "$(
    r="$(new_root)"; s="$(new_shim "$BASH3_VER")"
    while IFS= read -r q; do
      [ -z "$q" ] && continue
      if [ "$q" = "$FIRST" ]; then write_fixture "$r" "$q" slow
      else write_fixture "$r" "$q" pass; fi
    done <<< "$SRC_PATHS"
    run_gate_with_path "$r" "$(new_pathdir both)" --bash "$s/bash" --timeout 1
    suite_line_ok "$RUN_OUT" "$FIRST" 124 0 0
  )" "yes"

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
