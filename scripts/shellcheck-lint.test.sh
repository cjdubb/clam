#!/usr/bin/env bash
# scripts/shellcheck-lint.test.sh — contract tests for shellcheck-lint.sh
# (B07 shellcheck-lint, plan 001-speed-up-repo-ci).
#
# Black-box only: builds throwaway git repositories under mktemp -d holding
# tracked *.sh files and (per case) a scripts/shellcheck-baseline.txt, then
# invokes the REAL scripts/shellcheck-lint.sh (resolved via BASH_SOURCE) with
# cwd inside the fixture, so its git-root discovery and git-ls-files scan
# operate on the fixture and never on this repo's own tree or baseline.
#
# Mirrors the named-test / assert-helper harness style of
# scripts/architecture-lint.test.sh, whose baseline semantics B07's contract
# deliberately copies.
#
# TWO THINGS THIS SUITE DOES THAT THE SIBLING DOES NOT
#
# 1. shellcheck is never the machine's real shellcheck. Every "present" run
#    puts a FAKE shellcheck ahead of the real one on PATH. The fake analyses
#    nothing: it replays a scripted list of findings, in whichever output
#    format it is asked for (gcc, json, json1, checkstyle, or the default tty
#    layout), naming files with the exact argv spelling it was handed and
#    reporting only files that were actually passed to it. That keeps the
#    suite deterministic and keeps it black-box: the contract pins the lint's
#    own I/O, not the flags it uses to talk to shellcheck, so the fake adapts
#    to the implementation rather than the other way round.
#
# 2. shellcheck's ABSENCE is simulated without a whole-PATH symlink farm.
#    `path_hiding_shellcheck` finds every shellcheck reachable on a candidate
#    PATH (`type -aP`), drops exactly those directories by string surgery on
#    the PATH value, and prepends one small purpose-built toolbox directory
#    holding symlinks for the ~50 tools a shell lint could plausibly need —
#    so nothing essential is lost when a system directory has to go. Cost:
#    one fork per toolbox entry, once for the whole suite. Every absence run
#    asserts its own preconditions (shellcheck unreachable, git and bash
#    still reachable), so a machine where the trick fails reports a named
#    assertion failure rather than a mystery.
#
# Both consequences of (1) and (2): this suite behaves identically on a
# machine with shellcheck installed and on one without.
#
# Fixture constraint: finding MESSAGES must stay free of quotes, backslashes
# and angle brackets, so the fake can emit them into JSON and XML without an
# escaping layer.
#
# Run: bash shellcheck-lint.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/shellcheck-lint.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: script under test not found at $SCRIPT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Cleanup registry (command substitution forks a subshell, so a file-based
# manifest is needed to survive it — see architecture-lint.test.sh).
# ---------------------------------------------------------------------------
CLEANUP_MANIFEST="$(mktemp)"
track_tmp() { printf '%s\n' "$1" >> "$CLEANUP_MANIFEST"; }
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
# Minimal named-test harness (see architecture-lint.test.sh).
# ---------------------------------------------------------------------------
CURRENT_FAILURES=0
TOTAL_PASS=0
TOTAL_FAIL=0

start_test() { CURRENT_FAILURES=0; }
record_fail() {
  CURRENT_FAILURES=$((CURRENT_FAILURES + 1))
  printf '    FAIL: %s\n' "$1"
}
end_test() {
  local name="$1"
  if [ "$CURRENT_FAILURES" -eq 0 ]; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
    echo "ok - $name"
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    echo "not ok - $name ($CURRENT_FAILURES failing assertion(s))"
  fi
}
run_test() {
  local name="$1"
  shift
  start_test
  "$@"
  end_test "$name"
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
    *) record_fail "$label: expected output to contain [$needle], got: $haystack" ;;
  esac
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in
    *"$needle"*) record_fail "$label: expected output NOT to contain [$needle], got: $haystack" ;;
  esac
}

# line_no <file> <needle> -- 1-indexed line number of the first line of <file>
# containing the literal <needle>. Works with process substitution, so it
# doubles as a line-finder over captured stdout.
line_no() {
  grep -n -F -- "$2" "$1" | head -n1 | cut -d: -f1
}

# ---------------------------------------------------------------------------
# Fixture repo builder: git-init, one commit, scripts/ pre-created, a tracked
# non-.sh file present from the start. Ambient global hooks neutralized.
# ---------------------------------------------------------------------------
new_repo() {
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    git config core.hooksPath "$d/.git/no-such-hooks-dir"
    mkdir -p scripts
    printf '# fixture\n' > README.md
    git add -A
    git commit -q -m init
  ) >/dev/null
  printf '%s' "$d"
}

# write_file <repo> <relpath> [content] -- writes (not committed) a file,
# creating parent directories.
write_file() {
  local repo="$1" rel="$2" content="${3:-}"
  mkdir -p "$repo/$(dirname "$rel")"
  if [ -n "$content" ]; then
    printf '%s\n' "$content" > "$repo/$rel"
  else
    printf '#!/bin/bash\necho fixture\n' > "$repo/$rel"
  fi
}

commit_all() {
  local repo="$1" msg="$2"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "$msg" >/dev/null
}

write_baseline() {
  local repo="$1" content="$2"
  printf '%s' "$content" > "$repo/scripts/shellcheck-baseline.txt"
}

# Expected output line builders (contract: Outputs).
expected_new() {   # <path> <line> <code> <message>
  printf 'NEW  %s:%s: %s %s' "$1" "$2" "$3" "$4"
}
expected_stale() { # <path> <code> <baseline_count> <actual_count>
  printf 'STALE  baseline count %d exceeds actual %d: %s %s' "$3" "$4" "$1" "$2"
}

WARN_LINE='WARN  shellcheck skipped (shellcheck not found)'

# Realistic shellcheck messages, chosen quote-free (see the fixture
# constraint in the header). SC1091's carries a colon on purpose: a NEW line
# is `NEW  <path>:<line>: <code> <message>`, so a message containing a colon
# is the case a naive colon-splitting parser gets wrong.
MSG_SC2086='Double quote to prevent globbing and word splitting.'
MSG_SC1091='Not following: the file was not specified as input (see shellcheck -x).'
MSG_SC2164='Use cd ... || exit in case cd fails.'
MSG_SC2115='Use a guard to ensure this never expands to a slash.'
MSG_SC2046='Quote this to prevent word splitting.'
MSG_SC2181='Check exit code directly with e.g. if mycmd, not indirectly.'

# ===========================================================================
# Fake shellcheck.
#
# Replays a scripted findings list in whichever format it is asked for. It
# reports ONLY files that appear in its own argv (so a file the lint never
# passes can never show up in the lint's output), and names each file with
# the exact argv spelling it was given (so the lint may pass absolute or
# repo-relative paths — either way the fake echoes back what real shellcheck
# would). Every invocation appends its argv to an invocation log, which is
# how the one-invocation invariant is asserted.
#
# Deliberately lenient in one place: invoked with no file arguments it stays
# silent and exits 0 rather than printing real shellcheck's usage error, so
# the no-files-to-check verdict is decided by the lint's own output and not
# by the fake's opinion.
# ===========================================================================
SHIM_DIR=""
SPEC_FILE=""
INVOKE_LOG=""
SHIM_EXIT_FILE=""
RUN_ENV=()

new_shellcheck_shim() {
  SHIM_DIR="$(mktemp -d)"
  track_tmp "$SHIM_DIR"
  SPEC_FILE="$(mktemp)"
  track_tmp "$SPEC_FILE"
  INVOKE_LOG="$(mktemp)"
  track_tmp "$INVOKE_LOG"
  SHIM_EXIT_FILE="$(mktemp -u)"
  track_tmp "$SHIM_EXIT_FILE"
  RUN_ENV=()
  : > "$SPEC_FILE"
  : > "$INVOKE_LOG"

  {
    printf '#!/bin/bash\n'
    printf 'SPEC=%q\n' "$SPEC_FILE"
    printf 'LOG=%q\n' "$INVOKE_LOG"
    printf 'EXITFILE=%q\n' "$SHIM_EXIT_FILE"
    cat <<'SHIM'
ARGS=("$@")
printf '%s\n' "${ARGS[*]}" >> "$LOG"

for a in "${ARGS[@]}"; do
  case "$a" in
    --version|-V)
      printf 'ShellCheck - shell script analysis tool\nversion: 0.9.0\nlicense: GNU General Public License, version 3\n'
      exit 0
      ;;
  esac
done

if [ -f "$EXITFILE" ]; then
  read -r rc < "$EXITFILE"
  printf 'shellcheck: simulated internal failure\n' >&2
  exit "${rc:-2}"
fi

fmt=tty
i=0
while [ "$i" -lt "${#ARGS[@]}" ]; do
  a="${ARGS[$i]}"
  case "$a" in
    -f|--format) i=$((i + 1)); fmt="${ARGS[$i]:-tty}" ;;
    --format=*)  fmt="${a#--format=}" ;;
    -f?*)        fmt="${a#-f}" ;;
  esac
  i=$((i + 1))
done

# argv_form <spec path> -- the argv spelling of that file, or failure when
# the file was never passed to this invocation.
argv_form() {
  local want="$1" a
  for a in "${ARGS[@]}"; do
    [ "$a" = "$want" ] && { printf '%s' "$a"; return 0; }
  done
  for a in "${ARGS[@]}"; do
    case "$a" in
      */"$want") printf '%s' "$a"; return 0 ;;
    esac
  done
  return 1
}

FP=(); FL=(); FC=(); FV=(); FCODE=(); FMSG=(); N=0
if [ -f "$SPEC" ]; then
  while IFS=$'\t' read -r sp sl sc sv scode smsg; do
    [ -n "$sp" ] || continue
    form="$(argv_form "$sp")" || continue
    FP[N]="$form"; FL[N]="$sl"; FC[N]="$sc"
    FV[N]="$sv"; FCODE[N]="$scode"; FMSG[N]="$smsg"
    N=$((N + 1))
  done < "$SPEC"
fi

gcc_level() {
  case "$1" in
    error)   printf 'error' ;;
    warning) printf 'warning' ;;
    *)       printf 'note' ;;
  esac
}

case "$fmt" in
  gcc)
    for ((k = 0; k < N; k++)); do
      printf '%s:%s:%s: %s: %s [%s]\n' \
        "${FP[k]}" "${FL[k]}" "${FC[k]}" "$(gcc_level "${FV[k]}")" "${FMSG[k]}" "${FCODE[k]}"
    done
    ;;
  json|json1)
    body=""
    for ((k = 0; k < N; k++)); do
      [ -n "$body" ] && body="$body,"
      body="$body{\"file\":\"${FP[k]}\",\"line\":${FL[k]},\"endLine\":${FL[k]},\"column\":${FC[k]},\"endColumn\":$((${FC[k]} + 1)),\"level\":\"${FV[k]}\",\"code\":${FCODE[k]#SC},\"message\":\"${FMSG[k]}\",\"fix\":null}"
    done
    if [ "$fmt" = json1 ]; then
      printf '{"comments":[%s]}\n' "$body"
    else
      printf '[%s]\n' "$body"
    fi
    ;;
  checkstyle)
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<checkstyle version="4.3">\n'
    for ((k = 0; k < N; k++)); do
      printf '<file name="%s">\n' "${FP[k]}"
      printf '<error line="%s" column="%s" severity="%s" message="%s" source="ShellCheck.%s" />\n' \
        "${FL[k]}" "${FC[k]}" "${FV[k]}" "${FMSG[k]}" "${FCODE[k]}"
      printf '</file>\n'
    done
    printf '</checkstyle>\n'
    ;;
  quiet|diff)
    :
    ;;
  *)
    for ((k = 0; k < N; k++)); do
      printf '\nIn %s line %s:\n' "${FP[k]}" "${FL[k]}"
      printf 'placeholder source line\n'
      printf '%*s^-- %s (%s): %s\n' \
        "$((${FC[k]} - 1))" "" "${FCODE[k]}" "${FV[k]}" "${FMSG[k]}"
    done
    ;;
esac

if [ "$N" -gt 0 ]; then
  exit 1
fi
exit 0
SHIM
  } > "$SHIM_DIR/shellcheck"
  chmod +x "$SHIM_DIR/shellcheck"
}

# add_finding <path> <line> <col> <level> <code> <message>
add_finding() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$SPEC_FILE"
}

clear_findings() { : > "$SPEC_FILE"; }

# set_shellcheck_exit <n> -- make the fake fail with <n> on every scan
# invocation (a --version probe still succeeds, which is what "shellcheck
# present but erroring on its own" means).
set_shellcheck_exit() { printf '%s\n' "$1" > "$SHIM_EXIT_FILE"; }

invocations_total() {
  local n
  n="$(wc -l < "$INVOKE_LOG" 2>/dev/null | tr -d '[:space:]')"
  printf '%s' "${n:-0}"
}

# Invocations that carry at least one .sh file argument. Version probes and
# other file-free calls are excluded on purpose: the invariant is about not
# forking per FILE, not about never touching shellcheck twice.
scan_invocations() {
  local n
  n="$(grep -c -F '.sh' "$INVOKE_LOG" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}

scan_argv() {
  grep -F '.sh' "$INVOKE_LOG" 2>/dev/null | head -n1
}

# ===========================================================================
# PATH surgery for the shellcheck-absent path.
#
# NOT a whole-PATH symlink farm: the toolbox is an explicit ~50-entry list
# built once for the whole suite, and PATH filtering is pure bash string
# substitution.
# ===========================================================================
TOOLBOX_DIR=""

build_toolbox() {
  [ -n "$TOOLBOX_DIR" ] && return 0
  TOOLBOX_DIR="$(mktemp -d)"
  track_tmp "$TOOLBOX_DIR"
  local t p
  for t in bash sh dash git grep egrep fgrep sed awk gawk mawk sort uniq cut \
           tr head tail wc cat ls find xargs dirname basename mktemp rm mkdir \
           rmdir env comm diff tee expr realpath readlink stat chmod touch cp \
           mv date jq tac paste seq cmp od nl printf true false getconf nproc \
           id uname; do
    p="$(command -v "$t" 2>/dev/null || true)"
    case "$p" in
      /*) ln -sf "$p" "$TOOLBOX_DIR/$t" 2>/dev/null || true ;;
    esac
  done
  return 0
}

# path_hiding_shellcheck <candidate PATH> -- the same PATH with every
# directory holding a shellcheck removed, and the toolbox prepended so the
# removal cannot take git/grep/sed down with it.
path_hiding_shellcheck() {
  local cand="$1"
  build_toolbox
  local p d prev out=":$cand:"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    d="${p%/*}"
    [ -n "$d" ] || continue
    prev=""
    while [ "$out" != "$prev" ]; do
      prev="$out"
      out="${out//:$d:/:}"
      out="${out//:$d\/:/:}"
    done
  done < <(PATH="$cand" bash -c 'type -aP shellcheck' 2>/dev/null || true)
  out="${out#:}"
  out="${out%:}"
  printf '%s' "$TOOLBOX_DIR:$out"
}

resolves_with_path() { # <PATH value> <name> -> resolved path, or empty
  PATH="$1" bash -c 'type -P -- "$1"' _ "$2" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Invocation helpers.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
RUN_BOTH=""

_run() { # <cwd> <PATH value> [args...]
  local wd="$1" pv="$2"
  shift 2
  local out err
  out="$(mktemp)"; err="$(mktemp)"
  if [ "${#RUN_ENV[@]}" -eq 0 ]; then
    ( cd "$wd" && PATH="$pv" bash "$SCRIPT" "$@" >"$out" 2>"$err" )
  else
    ( cd "$wd" && PATH="$pv" env "${RUN_ENV[@]}" bash "$SCRIPT" "$@" >"$out" 2>"$err" )
  fi
  RUN_EXIT=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  RUN_BOTH="$RUN_OUT
$RUN_ERR"
  rm -f "$out" "$err"
}

# The fake shellcheck IS reachable.
run_lint() { # <cwd> [args...]
  local wd="$1"
  shift
  _run "$wd" "$SHIM_DIR:$PATH" "$@"
}

# NO shellcheck is reachable — not the fake, not the machine's real one.
# Self-checks its own preconditions so a machine where the trick fails
# reports a named assertion failure instead of a confusing verdict.
run_lint_no_shellcheck() { # <cwd> [args...]
  local wd="$1"
  shift
  local hidden found
  hidden="$(path_hiding_shellcheck "$SHIM_DIR:$PATH")"

  found="$(resolves_with_path "$hidden" shellcheck)"
  [ -z "$found" ] || record_fail "precondition: the shellcheck-absent PATH must resolve no shellcheck, but found [$found]"
  [ -n "$(resolves_with_path "$hidden" git)" ] || record_fail "precondition: the shellcheck-absent PATH must still resolve git"
  [ -n "$(resolves_with_path "$hidden" bash)" ] || record_fail "precondition: the shellcheck-absent PATH must still resolve bash"

  _run "$wd" "$hidden" "$@"
}

tree_hash() { # <repo> -- content hash of the working tree, .git excluded
  ( cd "$1" && find . -path './.git' -prune -o -type f -exec cksum {} + ) | sort
}

# assert_summary_count <summary line> <count> <keyword> <label> -- tolerant of
# `2 new` and of `new: 2` / `new=2`; the contract fixes the counts, not the
# punctuation.
assert_summary_count() {
  local summary="$1" n="$2" kw="$3" label="$4" lc
  lc="$(printf '%s' "$summary" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lc" =~ (^|[^0-9])${n}[[:space:]]+${kw} ]]; then
    return 0
  fi
  if [[ "$lc" =~ ${kw}[[:space:]]*[:=][[:space:]]*${n}([^0-9]|$) ]]; then
    return 0
  fi
  record_fail "$label: summary must report $n $kw, got: $summary"
}

# ===========================================================================
# Clause: Behavior — "Scans every git-tracked *.sh file in the repo — sources
# AND tests alike"; Invariant — "Scope is tracked *.sh files ONLY".
# ===========================================================================
test_scope_is_every_tracked_sh_sources_tests_and_nested() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"

  write_file "$repo" scripts/a.sh
  write_file "$repo" scripts/a.test.sh
  write_file "$repo" plugins/x/lib/y.sh
  write_file "$repo" deep/er/nest/z.sh
  # Tracked, but NOT *.sh — must never reach shellcheck.
  write_file "$repo" Makefile 'all:'
  write_file "$repo" docs/notes.md '# notes'
  write_file "$repo" scripts/tool.bash '#!/bin/bash'
  commit_all "$repo" "add fixture files"

  add_finding 'scripts/a.test.sh' 7 3 warning SC2086 "$MSG_SC2086"
  add_finding 'plugins/x/lib/y.sh' 2 1 info SC2164 "$MSG_SC2164"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "unbaselined findings must fail the run, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"

  assert_contains "$RUN_OUT" "$(expected_new 'scripts/a.test.sh' 7 SC2086 "$MSG_SC2086")" "a TEST file's finding is reported (test files are in scope)"
  assert_contains "$RUN_OUT" "$(expected_new 'plugins/x/lib/y.sh' 2 SC2164 "$MSG_SC2164")" "a nested source file's finding is reported"

  local argv
  argv="$(scan_argv)"
  local f
  for f in scripts/a.sh scripts/a.test.sh plugins/x/lib/y.sh deep/er/nest/z.sh; do
    assert_contains "$argv" "$f" "every tracked *.sh at any depth is handed to shellcheck ($f)"
  done
  for f in Makefile docs/notes.md scripts/tool.bash README.md; do
    assert_not_contains "$argv" "$f" "a tracked non-*.sh file must never be handed to shellcheck ($f)"
  done
}

# Inputs clause: the scan is driven by `git ls-files` — staged-but-
# uncommitted counts, untracked does not.
test_scan_uses_git_ls_files_staged_counts_untracked_does_not() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"

  write_file "$repo" scripts/tracked.sh
  commit_all "$repo" "add tracked.sh"

  write_file "$repo" scripts/staged.sh
  git -C "$repo" add scripts/staged.sh

  write_file "$repo" scripts/untracked.sh
  # deliberately never `git add`ed

  add_finding 'scripts/tracked.sh' 4 1 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/staged.sh' 5 1 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/untracked.sh' 6 1 warning SC2086 "$MSG_SC2086"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1 (unbaselined findings), got $RUN_EXIT (stderr: $RUN_ERR)"

  assert_contains "$RUN_OUT" "$(expected_new 'scripts/tracked.sh' 4 SC2086 "$MSG_SC2086")" "a committed *.sh is scanned"
  assert_contains "$RUN_OUT" "$(expected_new 'scripts/staged.sh' 5 SC2086 "$MSG_SC2086")" "a staged-but-uncommitted *.sh is scanned (git ls-files includes it)"
  assert_not_contains "$RUN_OUT" "untracked.sh" "an untracked *.sh must never be scanned (git ls-files excludes it)"
  assert_not_contains "$(scan_argv)" "untracked.sh" "an untracked *.sh must never be handed to shellcheck"
}

# ===========================================================================
# Clause: Outputs — `NEW  <path>:<line>: <code> <message>`; Behavior —
# "Reports each finding and exits nonzero unless it is excused".
# ===========================================================================
test_new_finding_exact_format_on_stdout_exit_1() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"

  # SC1091's message carries a colon: the NEW line is colon-delimited, so a
  # naive parser truncates it here.
  add_finding 'scripts/a.sh' 12 5 info SC1091 "$MSG_SC1091"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "one unbaselined finding must be exit 1, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new 'scripts/a.sh' 12 SC1091 "$MSG_SC1091")" "NEW line matches the contract format exactly, message intact"
  assert_not_contains "$RUN_ERR" "NEW  " "findings are reported on stdout, not stderr"
}

# Edge case: "A file with multiple findings of the same code: ... each
# occurrence is reported individually when not baselined."
test_multiple_findings_same_code_each_reported_individually() {
  local repo count
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"

  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/a.sh' 40 9 warning SC2086 "$MSG_SC2086"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new 'scripts/a.sh' 3 SC2086 "$MSG_SC2086")" "first occurrence reported"
  assert_contains "$RUN_OUT" "$(expected_new 'scripts/a.sh' 40 SC2086 "$MSG_SC2086")" "second occurrence reported"

  count="$(printf '%s\n' "$RUN_OUT" | grep -c '^NEW  ' || true)"
  [ "$count" -eq 2 ] || record_fail "two same-code findings must yield exactly 2 NEW lines, got $count (stdout: $RUN_OUT)"
}

# ===========================================================================
# Clause: baseline semantics — "A finding present in the baseline is counted,
# not failed."
# ===========================================================================
test_baselined_finding_is_counted_not_failed() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"
  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\t1\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "a finding matching a baseline pair must pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_not_contains "$RUN_OUT" "NEW  " "a baselined finding must not be reported as NEW"
  assert_not_contains "$RUN_OUT" "STALE  " "a matched baseline row is not stale"
}

# Clause: "A baseline entry with ZERO current findings is STALE and fails the
# run" + Edge case: "Baseline entry for a file that no longer exists: STALE".
# Both stale mechanisms in one run, and stale rows must appear in BASELINE
# order (the rows below are in the reverse of path-sort order, so the two are
# distinguishable).
test_stale_rows_reported_in_baseline_order_both_mechanisms() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/zeta.sh
  write_file "$repo" scripts/alpha.sh
  commit_all "$repo" "add zeta.sh and alpha.sh"

  # zeta.sh is deleted outright; alpha.sh survives but no longer produces the
  # baselined code (its finding is a different code, itself baselined).
  git -C "$repo" rm -q scripts/zeta.sh
  commit_all "$repo" "remove zeta.sh"
  add_finding 'scripts/alpha.sh' 2 1 warning SC2164 "$MSG_SC2164"

  write_baseline "$repo" "$(printf 'scripts/zeta.sh\tSC2086\t1\nscripts/alpha.sh\tSC2115\t1\nscripts/alpha.sh\tSC2164\t1\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "stale baseline rows must fail the run, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"

  local zeta_stale alpha_stale pos_z pos_a
  zeta_stale="$(expected_stale 'scripts/zeta.sh' SC2086 1 0)"
  alpha_stale="$(expected_stale 'scripts/alpha.sh' SC2115 1 0)"
  assert_contains "$RUN_OUT" "$zeta_stale" "stale: a row whose file no longer exists is reported"
  assert_contains "$RUN_OUT" "$alpha_stale" "stale: a row whose finding is gone is reported"
  assert_not_contains "$RUN_OUT" "$(expected_stale 'scripts/alpha.sh' SC2164 1 1)" "a row that still matches is not stale"

  pos_z="$(line_no <(printf '%s' "$RUN_OUT") "$zeta_stale")"
  pos_a="$(line_no <(printf '%s' "$RUN_OUT") "$alpha_stale")"
  if [ -z "$pos_z" ] || [ -z "$pos_a" ]; then
    record_fail "expected both STALE lines present to check ordering, got: $RUN_OUT"
  else
    [ "$pos_z" -lt "$pos_a" ] || record_fail "stale entries must appear in baseline order (zeta's row precedes alpha's in the file), got zeta at output line $pos_z, alpha at $pos_a"
  fi
}

# Clause: "Both failure kinds can be reported in a single run."
test_new_and_stale_both_reported_in_one_run() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"
  add_finding 'scripts/a.sh' 8 1 warning SC2046 "$MSG_SC2046"
  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\t1\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "a run with both a new finding and a stale row must exit 1, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new 'scripts/a.sh' 8 SC2046 "$MSG_SC2046")" "the new finding is reported"
  assert_contains "$RUN_OUT" "$(expected_stale 'scripts/a.sh' SC2086 1 0)" "the stale row is reported in the SAME run"
}

# Inputs clause: "The count caps how many findings of that (path, code) pair
# are excused; occurrences beyond the count are NEW."
test_baseline_count_caps_excused_findings() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"
  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/a.sh' 40 9 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/a.sh' 41 2 warning SC2086 "$MSG_SC2086"
  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\t3\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "three findings at count 3 must pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_not_contains "$RUN_OUT" "NEW  " "no finding may leak through as NEW when count matches"

  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\t2\n')"
  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "three findings at count 2 must fail (1 excess), got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "NEW  " "the excess finding is reported as NEW"
}

# Behavior clause: "Entries are line-number-free so that edits which move code
# do not churn the baseline." Same baseline, finding relocated: still clean,
# and byte-identical output.
test_baseline_entries_are_line_number_free() {
  local repo out_before exit_before
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"
  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\t1\n')"

  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  run_lint "$repo"
  exit_before="$RUN_EXIT"
  out_before="$RUN_OUT"
  [ "$exit_before" -eq 0 ] || record_fail "baselined finding at line 3 must pass, got exit $exit_before (stdout: $RUN_OUT, stderr: $RUN_ERR)"

  # The code moved; the finding is now at line 77. The baseline is untouched.
  clear_findings
  add_finding 'scripts/a.sh' 77 1 warning SC2086 "$MSG_SC2086"
  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "the SAME baseline row must still excuse the finding after it moves to line 77, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_eq "$out_before" "$RUN_OUT" "moving a baselined finding to another line must not change the output at all"
}

# Inputs clause: an entry is a (path, code) PAIR — it excuses neither another
# path with the same code nor another code in the same path.
test_baseline_entry_is_scoped_to_its_path_and_code() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  write_file "$repo" scripts/b.sh
  commit_all "$repo" "add a.sh and b.sh"

  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/a.sh' 9 1 warning SC2115 "$MSG_SC2115"
  add_finding 'scripts/b.sh' 4 1 warning SC2086 "$MSG_SC2086"
  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\t1\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1 (two findings outside the one baseline pair), got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new 'scripts/a.sh' 9 SC2115 "$MSG_SC2115")" "a different code in the baselined path is NOT excused"
  assert_contains "$RUN_OUT" "$(expected_new 'scripts/b.sh' 4 SC2086 "$MSG_SC2086")" "the same code in a different path is NOT excused"
  assert_not_contains "$RUN_OUT" "$(expected_new 'scripts/a.sh' 3 SC2086 "$MSG_SC2086")" "the exact baselined pair IS excused"
  assert_not_contains "$RUN_OUT" "STALE  " "the matched row must not also be reported stale"
}

# Inputs clause: "`#`-comment lines and blank lines are ignored."
test_baseline_comments_and_blank_lines_ignored() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"
  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  write_baseline "$repo" "$(printf '# leading comment\n\n  # indented comment\nscripts/a.sh\tSC2086\t1\n\n# trailing comment\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "comments and blank lines must be ignored, not parsed as rows, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_not_contains "$RUN_OUT" "STALE  " "a comment line must never become a stale entry"
}

# Inputs clause: "Missing file = empty baseline."
test_missing_baseline_file_is_treated_as_empty() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"
  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  rm -f "$repo/scripts/shellcheck-baseline.txt"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "a missing baseline must be an EMPTY baseline (finding unexcused), not an error, got exit $RUN_EXIT (stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new 'scripts/a.sh' 3 SC2086 "$MSG_SC2086")" "missing baseline: the finding is reported as NEW"
}

# Errors clause: "A baseline row that is not a `#` comment, blank, or a
# well-formed 3-field triple: diagnostic naming the row, exit 2."
test_malformed_baseline_row_is_exit_2_naming_the_row() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"

  write_baseline "$repo" "$(printf 'this-row-has-only-one-field\n')"
  run_lint "$repo"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "a 1-field baseline row must be exit 2, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$RUN_ERR" "this-row-has-only-one-field" "the diagnostic names the offending row, on stderr"

  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\n')"
  run_lint "$repo"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "a 2-field baseline row must be exit 2, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$RUN_ERR" "scripts/a.sh" "the diagnostic names the offending 2-field row, on stderr"

  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\tnot-a-number\n')"
  run_lint "$repo"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "a non-numeric count must be exit 2, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$RUN_ERR" "not-a-number" "the diagnostic names the offending non-numeric row, on stderr"

  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\t0\n')"
  run_lint "$repo"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "a zero count must be exit 2, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$RUN_ERR" "positive integer" "the diagnostic mentions positive integer, on stderr"
}

# ===========================================================================
# Clause: Invariant — "shellcheck's ABSENCE degrades to a WARN and exit 0,
# never a failure ... Its PRESENCE gates." Both halves, same fixture.
# ===========================================================================
test_absence_warns_and_passes_presence_gates() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"
  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"

  # --- absence ---
  run_lint_no_shellcheck "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "shellcheck absent must exit 0, never fail, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$RUN_BOTH" "$WARN_LINE" "shellcheck absent emits the contract's exact skip notice"
  assert_not_contains "$RUN_OUT" "NEW  " "shellcheck absent reports no findings"
  assert_eq "0" "$(scan_invocations)" "shellcheck absent: the fake must never have been reachable"

  # --- presence, same fixture ---
  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "shellcheck present must GATE on the same fixture, expected exit 1, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new 'scripts/a.sh' 3 SC2086 "$MSG_SC2086")" "shellcheck present: the finding is reported"
  assert_not_contains "$RUN_OUT" "$WARN_LINE" "shellcheck present: no skip notice"
}

# Outputs clause: "Exit 0: ... (or shellcheck absent)". A non-empty baseline
# must not go stale just because there was nothing to match it against.
test_absence_does_not_stale_the_baseline() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"
  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\t1\nscripts/a.sh\tSC2164\t1\n')"

  run_lint_no_shellcheck "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "a non-empty baseline with shellcheck absent must still exit 0, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$RUN_BOTH" "$WARN_LINE" "the skip notice is still emitted with a baseline present"
  assert_not_contains "$RUN_OUT" "STALE  " "no baseline row may be called stale when shellcheck never ran"
}

# ===========================================================================
# Clause: Outputs — summary line with counts (new / stale / baselined).
# ===========================================================================
test_summary_line_reports_new_stale_and_baselined_counts() {
  local repo summary
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  write_file "$repo" scripts/b.sh
  write_file "$repo" scripts/c.sh
  commit_all "$repo" "add a.sh b.sh c.sh"

  # 3 baselined (a.sh SC2086 x2 at count 2, b.sh SC2115 x1 at count 1),
  # 2 new (b.sh SC2046, c.sh SC2181), 1 stale (ghost.sh SC2001).
  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/a.sh' 9 1 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/b.sh' 4 1 warning SC2115 "$MSG_SC2115"
  add_finding 'scripts/b.sh' 7 1 warning SC2046 "$MSG_SC2046"
  add_finding 'scripts/c.sh' 2 1 info SC2181 "$MSG_SC2181"
  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\t2\nscripts/b.sh\tSC2115\t1\nscripts/ghost.sh\tSC2001\t1\n')"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "mixed new+stale must fail, got exit $RUN_EXIT (stderr: $RUN_ERR)"

  summary="$(printf '%s\n' "$RUN_OUT" | tail -n1)"
  assert_summary_count "$summary" 2 new "summary new count"
  assert_summary_count "$summary" 1 stale "summary stale count"
  assert_summary_count "$summary" 3 baselined "summary baselined count"
}

test_clean_tree_is_exit_0_with_zeroed_summary() {
  local repo summary
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  write_file "$repo" scripts/a.test.sh
  commit_all "$repo" "add clean fixture"
  # no findings scripted, no baseline written

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "no findings and no baseline must be a clean pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_not_contains "$RUN_OUT" "NEW  " "clean run reports no findings"
  assert_not_contains "$RUN_OUT" "STALE  " "clean run reports no stale rows"

  summary="$(printf '%s\n' "$RUN_OUT" | tail -n1)"
  assert_summary_count "$summary" 0 new "clean summary new count"
  assert_summary_count "$summary" 0 stale "clean summary stale count"
  assert_summary_count "$summary" 0 baselined "clean summary baselined count"
}

# ===========================================================================
# Clause: Errors / Outputs — exit 2 for usage and environment errors.
# ===========================================================================
test_not_a_git_repo_is_exit_2_with_stderr_diagnostic() {
  local plain
  new_shellcheck_shim
  plain="$(mktemp -d)"
  track_tmp "$plain"

  run_lint "$plain"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "outside any git repository: expected exit 2, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  [ -n "$RUN_ERR" ] || record_fail "outside any git repository: expected a diagnostic on stderr"
}

test_unknown_flag_is_usage_line_on_stderr_exit_2() {
  local repo err_lc
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"

  run_lint "$repo" --no-such-flag
  [ "$RUN_EXIT" -eq 2 ] || record_fail "an unknown flag must be exit 2, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  [ -n "$RUN_ERR" ] || record_fail "an unknown flag must print to stderr"
  err_lc="$(printf '%s' "$RUN_ERR" | tr '[:upper:]' '[:lower:]')"
  assert_contains "$err_lc" "usage" "an unknown flag must print a usage line"
}

# Edge case: "shellcheck present but erroring on its own (bad install,
# unreadable file): treated as an environment error, exit 2 — never a silent
# pass."
test_shellcheck_own_failure_is_environment_error_exit_2() {
  local repo
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"

  set_shellcheck_exit 2
  run_lint "$repo"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "shellcheck exiting 2 on its own must be an environment error (exit 2), got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  [ -n "$RUN_ERR" ] || record_fail "shellcheck erroring must produce a diagnostic on stderr"
  assert_not_contains "$RUN_OUT" "$WARN_LINE" "a present-but-broken shellcheck is NOT the absent case"

  # A different self-error code is still an environment error, never a pass.
  set_shellcheck_exit 4
  run_lint "$repo"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "shellcheck exiting 4 on its own must also be exit 2, got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
}

test_exit_status_is_only_ever_0_1_or_2() {
  local repo plain ec
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"

  run_lint "$repo"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "clean scenario: exit $ec not in {0,1,2}" ;; esac

  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  run_lint "$repo"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "finding scenario: exit $ec not in {0,1,2}" ;; esac

  run_lint_no_shellcheck "$repo"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "shellcheck-absent scenario: exit $ec not in {0,1,2}" ;; esac

  set_shellcheck_exit 2
  run_lint "$repo"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "broken-shellcheck scenario: exit $ec not in {0,1,2}" ;; esac

  plain="$(mktemp -d)"
  track_tmp "$plain"
  run_lint "$plain"
  ec="$RUN_EXIT"
  case "$ec" in 0|1|2) : ;; *) record_fail "non-git-dir scenario: exit $ec not in {0,1,2}" ;; esac
}

# ===========================================================================
# Clause: Invariants.
# ===========================================================================

# "Read-only; never modifies the tree or the baseline."
test_invariant_read_only_tree_and_baseline_unchanged() {
  local repo before after
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"
  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/a.sh' 9 1 warning SC2115 "$MSG_SC2115"
  # A baseline holding one matching row and one stale row: an implementation
  # tempted to "fix" the baseline would rewrite exactly this file.
  write_baseline "$repo" "$(printf 'scripts/a.sh\tSC2086\t1\nscripts/gone.sh\tSC2164\t1\n')"

  before="$(tree_hash "$repo")"
  run_lint "$repo"
  after="$(tree_hash "$repo")"

  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1 (a new finding and a stale row), got $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_eq "$before" "$after" "the fixture tree (including scripts/shellcheck-baseline.txt) must be byte-identical before and after a run"
}

# "cwd-independent: resolves the repo root via git rev-parse and scans from
# there; all reported paths are repo-relative."
test_invariant_cwd_independent_and_paths_repo_relative() {
  local repo out_root exit_root
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  write_file "$repo" plugins/x/lib/y.sh
  commit_all "$repo" "add nested fixture"
  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  add_finding 'plugins/x/lib/y.sh' 6 1 info SC2164 "$MSG_SC2164"

  run_lint "$repo"
  exit_root="$RUN_EXIT"
  out_root="$RUN_OUT"
  [ "$exit_root" -eq 1 ] || record_fail "from the repo root: expected exit 1, got $exit_root (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$out_root" "$(expected_new 'scripts/a.sh' 3 SC2086 "$MSG_SC2086")" "from the repo root: paths are repo-relative"
  assert_contains "$out_root" "$(expected_new 'plugins/x/lib/y.sh' 6 SC2164 "$MSG_SC2164")" "from the repo root: nested paths are repo-relative"

  run_lint "$repo/plugins/x/lib"
  [ "$RUN_EXIT" -eq "$exit_root" ] || record_fail "run from a nested subdirectory: exit code must match the repo-root run ($exit_root), got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "$out_root" "$RUN_OUT" "output must be identical whether the lint is run from the repo root or a nested subdirectory"
  assert_not_contains "$RUN_OUT" "$repo" "no reported path may be absolute (the fixture root must never appear in the output)"
  assert_not_contains "$RUN_OUT" "../" "no reported path may be relative to the cwd"
}

# "Deterministic output: findings sorted by path then line."
test_invariant_findings_sorted_by_path_then_line() {
  local repo pos_a3 pos_a40 pos_m pos_z
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  write_file "$repo" scripts/m.sh
  write_file "$repo" scripts/z.sh
  commit_all "$repo" "add a.sh m.sh z.sh"

  # Scripted deliberately out of order in BOTH dimensions.
  add_finding 'scripts/z.sh' 5 1 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/a.sh' 40 1 warning SC2115 "$MSG_SC2115"
  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"
  add_finding 'scripts/m.sh' 1 1 info SC2181 "$MSG_SC2181"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "expected exit 1 (four unbaselined findings), got $RUN_EXIT (stderr: $RUN_ERR)"

  pos_a3="$(line_no <(printf '%s' "$RUN_OUT") 'NEW  scripts/a.sh:3:')"
  pos_a40="$(line_no <(printf '%s' "$RUN_OUT") 'NEW  scripts/a.sh:40:')"
  pos_m="$(line_no <(printf '%s' "$RUN_OUT") 'NEW  scripts/m.sh:1:')"
  pos_z="$(line_no <(printf '%s' "$RUN_OUT") 'NEW  scripts/z.sh:5:')"

  if [ -z "$pos_a3" ] || [ -z "$pos_a40" ] || [ -z "$pos_m" ] || [ -z "$pos_z" ]; then
    record_fail "expected all four findings present to check ordering, got: $RUN_OUT"
    return
  fi
  [ "$pos_a3" -lt "$pos_a40" ] || record_fail "within a file, line 3 must precede line 40, got positions $pos_a3 vs $pos_a40"
  [ "$pos_a40" -lt "$pos_m" ] || record_fail "scripts/a.sh must precede scripts/m.sh, got positions $pos_a40 vs $pos_m"
  [ "$pos_m" -lt "$pos_z" ] || record_fail "scripts/m.sh must precede scripts/z.sh, got positions $pos_m vs $pos_z"
}

# "No environment variables, no config files beyond the baseline. Reads
# NOTHING from .claude/ or .local/."
test_invariant_ignores_environment_and_stray_config() {
  local repo decoy
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add a.sh"
  add_finding 'scripts/a.sh' 3 1 warning SC2086 "$MSG_SC2086"

  # Decoy baselines that WOULD excuse the finding if any of them were read.
  decoy="$(printf 'scripts/a.sh\tSC2086\t1\n')"
  write_file "$repo" .claude/shellcheck-baseline.txt "$decoy"
  write_file "$repo" .claude/settings.json '{"shellcheckBaseline": "scripts/a.sh SC2086"}'
  write_file "$repo" .local/shellcheck-baseline.txt "$decoy"
  write_file "$repo" shellcheck-baseline.txt "$decoy"
  commit_all "$repo" "add decoy config"

  RUN_ENV=(
    "SHELLCHECK_BASELINE=$repo/.claude/shellcheck-baseline.txt"
    "SHELLCHECK_LINT_BASELINE=$repo/.local/shellcheck-baseline.txt"
    "BASELINE_FILE=$repo/shellcheck-baseline.txt"
    "BASELINE=$repo/shellcheck-baseline.txt"
    "SKIP_SHELLCHECK=1"
    "SHELLCHECK_LINT_SKIP=1"
    "NO_COLOR=1"
  )

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 1 ] || record_fail "no env var and no stray baseline may excuse a finding or skip the run, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  assert_contains "$RUN_OUT" "$(expected_new 'scripts/a.sh' 3 SC2086 "$MSG_SC2086")" "the finding is still NEW: only scripts/shellcheck-baseline.txt is read"
  assert_not_contains "$RUN_OUT" "$WARN_LINE" "no environment variable may turn the gate into a skip"
}

# ===========================================================================
# Clause: Invariant — "Invoking shellcheck once over the full file list, not
# once per file". Asserted mechanically with a counting fake; no strace, no
# wall-clock threshold.
# ===========================================================================
test_invariant_one_shellcheck_invocation_over_the_full_file_list() {
  local repo argv f n
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  write_file "$repo" scripts/a.test.sh
  write_file "$repo" scripts/b.sh
  write_file "$repo" plugins/x/lib/y.sh
  write_file "$repo" plugins/x/scripts/y.test.sh
  write_file "$repo" deep/er/nest/z.sh
  commit_all "$repo" "add six tracked shell files"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected a clean pass over six finding-free files, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"

  n="$(scan_invocations)"
  [ "$n" -eq 1 ] || record_fail "shellcheck must be invoked exactly ONCE over the whole file list, observed $n invocation(s) carrying file arguments (log: $(cat "$INVOKE_LOG"))"

  argv="$(scan_argv)"
  for f in scripts/a.sh scripts/a.test.sh scripts/b.sh plugins/x/lib/y.sh plugins/x/scripts/y.test.sh deep/er/nest/z.sh; do
    assert_contains "$argv" "$f" "the single invocation carries the FULL file list ($f)"
  done
}

# ===========================================================================
# Clause: Invariant — "SC2317 is excluded at the invocation rather than
# baselined ... No other code is excluded". The fake cannot filter, so what is
# asserted here is the argv: the exclusion is passed, and it is the only one.
# ===========================================================================
test_invariant_sc2317_is_excluded_at_the_invocation_and_nothing_else_is() {
  local repo argv
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" scripts/a.sh
  commit_all "$repo" "add one tracked shell file"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected a clean pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"

  argv="$(scan_argv)"
  assert_contains "$argv" "--exclude=SC2317" "SC2317 must be excluded at the invocation, not carried in the baseline"

  case "$argv" in
    *--exclude=SC2317*--exclude=*|*--exclude=*--exclude=SC2317*)
      record_fail "SC2317 must be the ONLY exclusion; argv carries more than one --exclude ($argv)" ;;
  esac
}

# The same invariant from the angle that actually bites: invocation count must
# not grow with the number of files. Four times the files, same count.
test_invariant_invocation_count_does_not_scale_with_file_count() {
  local repo3 repo12 i s3 s12 t3 t12 e3 e12
  repo3="$(new_repo)"
  for i in 1 2 3; do
    write_file "$repo3" "scripts/f$i.sh"
  done
  commit_all "$repo3" "three shell files"

  repo12="$(new_repo)"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    write_file "$repo12" "scripts/f$i.sh"
  done
  commit_all "$repo12" "twelve shell files"

  new_shellcheck_shim
  run_lint "$repo3"
  e3="$RUN_EXIT"; s3="$(scan_invocations)"; t3="$(invocations_total)"

  new_shellcheck_shim
  run_lint "$repo12"
  e12="$RUN_EXIT"; s12="$(scan_invocations)"; t12="$(invocations_total)"

  [ "$e3" -eq 0 ] || record_fail "3-file fixture: expected a clean pass, got exit $e3 (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  [ "$e12" -eq 0 ] || record_fail "12-file fixture: expected a clean pass, got exit $e12 (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  [ "$s3" -eq 1 ] || record_fail "3-file fixture: expected exactly 1 scanning invocation, got $s3"
  [ "$s12" -eq 1 ] || record_fail "12-file fixture: expected exactly 1 scanning invocation, got $s12"
  [ "$t3" -eq "$t12" ] || record_fail "total shellcheck invocations must not depend on the file count: 3 files gave $t3, 12 files gave $t12"
}

# ===========================================================================
# Clause: Edge case — "Repo with no tracked *.sh files: clean pass, exit 0,
# 'no files to check'."
# ===========================================================================
test_repo_with_no_tracked_sh_files_is_a_clean_pass() {
  local repo out_lc
  new_shellcheck_shim
  repo="$(new_repo)"
  write_file "$repo" docs/notes.md '# notes'
  write_file "$repo" Makefile 'all:'
  commit_all "$repo" "add non-shell files only"

  run_lint "$repo"
  [ "$RUN_EXIT" -eq 0 ] || record_fail "a repo with no tracked *.sh must be a clean pass, got exit $RUN_EXIT (stdout: $RUN_OUT, stderr: $RUN_ERR)"
  out_lc="$(printf '%s\n%s' "$RUN_OUT" "$RUN_ERR" | tr '[:upper:]' '[:lower:]')"
  assert_contains "$out_lc" "no files to check" "the empty-scope run says so explicitly"
  assert_not_contains "$RUN_OUT" "NEW  " "nothing to scan means nothing to report"
  assert_not_contains "$RUN_OUT" "STALE  " "nothing to scan means no stale rows either"
}

# ===========================================================================
# main
# ===========================================================================

run_test "behavior: scope is every tracked *.sh — sources, tests, any depth — and nothing else" test_scope_is_every_tracked_sh_sources_tests_and_nested
run_test "inputs: git ls-files drives the scan (staged counts, untracked does not)" test_scan_uses_git_ls_files_staged_counts_untracked_does_not

run_test "outputs: a new finding prints the exact NEW line on stdout and exits 1" test_new_finding_exact_format_on_stdout_exit_1
run_test "edge case: multiple findings of one code are each reported individually" test_multiple_findings_same_code_each_reported_individually

run_test "baseline: a matched finding is counted, not failed" test_baselined_finding_is_counted_not_failed
run_test "baseline: stale rows fail, in baseline order, for both stale mechanisms" test_stale_rows_reported_in_baseline_order_both_mechanisms
run_test "baseline: a new finding and a stale row are both reported in one run" test_new_and_stale_both_reported_in_one_run
run_test "baseline: count caps how many duplicate findings are excused" test_baseline_count_caps_excused_findings
run_test "baseline: entries are line-number-free (a finding that moves does not churn it)" test_baseline_entries_are_line_number_free
run_test "baseline: an entry excuses only its own (path, code) pair" test_baseline_entry_is_scoped_to_its_path_and_code
run_test "baseline: comment and blank lines are ignored" test_baseline_comments_and_blank_lines_ignored
run_test "baseline: a missing baseline file is an empty baseline, not an error" test_missing_baseline_file_is_treated_as_empty
run_test "errors: a malformed baseline row is exit 2 with a diagnostic naming the row" test_malformed_baseline_row_is_exit_2_naming_the_row

run_test "invariant: shellcheck absent WARNs and exits 0; shellcheck present gates" test_absence_warns_and_passes_presence_gates
run_test "invariant: shellcheck absent does not turn the baseline stale" test_absence_does_not_stale_the_baseline

run_test "outputs: the summary line carries the new / stale / baselined counts" test_summary_line_reports_new_stale_and_baselined_counts
run_test "outputs: a clean tree exits 0 with a zeroed summary" test_clean_tree_is_exit_0_with_zeroed_summary

run_test "errors: not inside a git repository is exit 2 with a stderr diagnostic" test_not_a_git_repo_is_exit_2_with_stderr_diagnostic
run_test "errors: an unknown flag prints a usage line on stderr and exits 2" test_unknown_flag_is_usage_line_on_stderr_exit_2
run_test "edge case: shellcheck failing on its own is an environment error (exit 2)" test_shellcheck_own_failure_is_environment_error_exit_2
run_test "outputs: exit status is only ever 0, 1, or 2" test_exit_status_is_only_ever_0_1_or_2

run_test "invariant: read-only — the tree and the baseline are unchanged" test_invariant_read_only_tree_and_baseline_unchanged
run_test "invariant: cwd-independent, and all reported paths are repo-relative" test_invariant_cwd_independent_and_paths_repo_relative
run_test "invariant: findings are sorted by path then line" test_invariant_findings_sorted_by_path_then_line
run_test "invariant: no env var and no stray config file changes the verdict" test_invariant_ignores_environment_and_stray_config

run_test "invariant: shellcheck is invoked exactly once, over the full file list" test_invariant_one_shellcheck_invocation_over_the_full_file_list
run_test "invariant: invocation count does not scale with the file count" test_invariant_invocation_count_does_not_scale_with_file_count
run_test "invariant: SC2317 is excluded at the invocation, and it is the only exclusion" test_invariant_sc2317_is_excluded_at_the_invocation_and_nothing_else_is

run_test "edge case: a repo with no tracked *.sh files is a clean pass" test_repo_with_no_tracked_sh_files_is_a_clean_pass

echo "---"
echo "Passed: $TOTAL_PASS  Failed: $TOTAL_FAIL  Total: $((TOTAL_PASS + TOTAL_FAIL))"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
