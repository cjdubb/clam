#!/usr/bin/env bash
# ci.test.sh — contract tests for scripts/ci.sh (B02 ci-runner, plan
# 001-pseudo-ci).
#
# Black-box only: builds fixture git repos under mktemp -d containing fake
# scripts/marketplace-lint.sh, scripts/executable-lint.sh,
# scripts/readme-lint.sh, scripts/version-bump-lint.sh,
# scripts/issue-template-lint.sh (record-invocation
# stubs that log to a file OUTSIDE the fixture tree and exit a configured
# code), fake scripts/*.test.sh and plugins/*/{scripts,lib}/*.test.sh files
# (same stub shape), and a plugins/ tree — then invokes the REAL
# scripts/ci.sh (resolved via BASH_SOURCE from this repo) with cwd inside
# the fixture, so its git-root discovery operates on the fixture. `claude`
# and `gh` availability is controlled via PATH: "present" prepends a shim
# dir with a record-and-exit-configured-code stub; "absent" strips the real
# binaries' directories out of PATH entirely (never falls back to the
# ambient PATH, so a real `claude`/`gh` is never invoked by these tests).
#
# Every stub writes to one shared per-fixture log file (outside the fixture
# tree) so cross-stage/cross-check invocation ORDER and PRESENCE/ABSENCE
# can be asserted losslessly, independent of anything ci.sh prints to
# stdout. Log line shape: "CHECK <name>", "CWD_OK <name>" / "CWD_BAD <name>
# <pwd>", or "CALL claude <args>" / "CALL gh <args>". Check names are
# namespaced "lint:<check>", "test:<relpath>", "validate:<target>" so
# absence of a whole category can be asserted via a prefix search.
#
# Mirrors the PASS/FAIL harness style of scripts/readme-lint.test.sh.
#
# Run: bash scripts/ci.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_SCRIPT="$SCRIPT_DIR/ci.sh"

if [ ! -f "$CI_SCRIPT" ]; then
  echo "FATAL: script under test not found at $CI_SCRIPT" >&2
  exit 1
fi

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# Cleanup registry for mktemp fixture trees/log files/shim dirs (command
# substitution forks a subshell, so a file-based manifest is needed to
# survive it).
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
# "absent" claude/gh: per-BINARY hiding, not per-directory. `claude` and
# `gh` must be unresolvable (ci.sh gates on `command -v`, so a failing shim
# would not do — the binary NAME must not resolve at all), while every
# other tool the fixtures need (jq, shellcheck, bash, timeout, git,
# coreutils...) resolves exactly as on the caller's PATH.
#
# Dropping the directories that contain claude/gh is not portable: on
# Homebrew macOS `gh` lives in /opt/homebrew/bin alongside jq, shellcheck,
# bash and timeout, so dropping it hides the fixtures' whole toolchain and
# `== validate ==` never runs. Instead, drop those directories and then
# re-expose everything in them EXCEPT `claude`/`gh` through a rescue
# directory of symlinks, prepended to the trimmed PATH. Net effect: exactly
# two names disappear. Safe when claude/gh are not installed at all (no
# directories to trim, empty rescue dir). Fixtures that supply their own
# claude/gh shims prepend those dirs ahead of all of this, so they win.
# ---------------------------------------------------------------------------
REAL_CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
REAL_GH_BIN="$(command -v gh 2>/dev/null || true)"
REAL_CLAUDE_DIR=""
REAL_GH_DIR=""
[ -n "$REAL_CLAUDE_BIN" ] && REAL_CLAUDE_DIR="$(dirname "$REAL_CLAUDE_BIN")"
[ -n "$REAL_GH_BIN" ] && REAL_GH_DIR="$(dirname "$REAL_GH_BIN")"

path_without() { # dir... -> PATH with those dirs removed
  local p=":$PATH:" d
  for d in "$@"; do
    [ -n "$d" ] || continue
    p="${p//:$d:/:}"
  done
  p="${p#:}"; p="${p%:}"
  printf '%s' "$p"
}

# Symlink every entry of the given dirs into one rescue dir, skipping the
# names to hide; first occurrence wins, so PATH precedence is preserved.
path_rescue_dir() { # <hide-csv> <dir>... -> rescue dir path
  local hide=",$1," d entry name r
  shift
  r="$(mktemp -d)"
  track_tmp "$r"
  for d in "$@"; do
    [ -d "$d" ] || continue
    for entry in "$d"/*; do
      [ -e "$entry" ] || continue
      name="${entry##*/}"
      case "$hide" in *",$name,"*) continue ;; esac
      [ -e "$r/$name" ] && continue
      ln -s "$entry" "$r/$name" 2>/dev/null || true
    done
  done
  printf '%s' "$r"
}

BASE_PATH="$(path_rescue_dir "claude,gh" "$REAL_CLAUDE_DIR" "$REAL_GH_DIR"):$(path_without "$REAL_CLAUDE_DIR" "$REAL_GH_DIR")"

# ---------------------------------------------------------------------------
# Fixture repo builder: git-inits, one commit, GitHub origin remote,
# scripts/ plugins/ .claude-plugin/ dirs pre-created.
# ---------------------------------------------------------------------------
new_repo() { # -> prints repo root path (physical, symlinks resolved)
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  # macOS mktemp returns /var/folders/... which is a symlink to
  # /private/var/folders/...; ci.sh resolves the repo root physically, so
  # stub cwd comparisons must be against the physical path too. No-op on
  # Linux, where the temp dir is already physical.
  d="$(cd "$d" && pwd -P)"
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    mkdir -p scripts plugins .claude-plugin
    printf '{}\n' > .claude-plugin/marketplace.json
    printf '# fixture\n' > README.md
    git add -A
    git commit -q -m init
    git remote add origin https://github.com/testowner/testrepo.git
  ) >/dev/null
  printf '%s' "$d"
}

# ---------------------------------------------------------------------------
# Stub writers. All log to an external (outside-fixture) log file so the
# fixture tree itself stays pristine for the read-only-invariant check.
# ---------------------------------------------------------------------------
write_check_stub() { # <file_path> <name> <log_file> <expected_cwd> <exit_code>
  local path="$1" name="$2" log="$3" exp="$4" code="$5"
  cat > "$path" <<STUB
#!/bin/bash
printf 'CHECK %s\n' '$name' >> '$log'
if [ "\$(pwd)" = '$exp' ]; then
  printf 'CWD_OK %s\n' '$name' >> '$log'
else
  printf 'CWD_BAD %s %s\n' '$name' "\$(pwd)" >> '$log'
fi
exit $code
STUB
  chmod +x "$path"
}

write_claude_shim() { # <shim_dir> <log_file> <expected_cwd> <fail_target_substring_or_empty>
  local dir="$1" log="$2" exp="$3" failsub="$4"
  mkdir -p "$dir"
  cat > "$dir/claude" <<STUB
#!/bin/bash
printf 'CALL claude %s\n' "\$*" >> '$log'
if [ "\$1" = "plugin" ] && [ "\$2" = "validate" ]; then
  printf 'CHECK validate:%s\n' "\$3" >> '$log'
  if [ "\$(pwd)" = '$exp' ]; then
    printf 'CWD_OK validate:%s\n' "\$3" >> '$log'
  else
    printf 'CWD_BAD validate:%s %s\n' "\$3" "\$(pwd)" >> '$log'
  fi
  FAILSUB='$failsub'
  if [ -n "\$FAILSUB" ]; then
    case "\$3" in
      *"\$FAILSUB"*) exit 1 ;;
    esac
  fi
fi
exit 0
STUB
  chmod +x "$dir/claude"
}

write_gh_shim() { # <shim_dir> <log_file> <exit_code>
  local dir="$1" log="$2" code="$3"
  mkdir -p "$dir"
  cat > "$dir/gh" <<STUB
#!/bin/bash
printf 'CALL gh %s\n' "\$*" >> '$log'
exit $code
STUB
  chmod +x "$dir/gh"
}

# ---------------------------------------------------------------------------
# Invocation helper.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0

run_ci() { # <cwd> <path_value> <ci_args...>
  local cwd="$1" pathval="$2"; shift 2
  local out err
  out="$(mktemp)"; err="$(mktemp)"
  ( cd "$cwd" && PATH="$pathval" bash "$CI_SCRIPT" "$@" >"$out" 2>"$err" )
  RUN_EXIT=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  rm -f "$out" "$err"
}

# ---------------------------------------------------------------------------
# Assertion helpers.
# ---------------------------------------------------------------------------
contains() { # text needle -> yes/no
  case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac
}

# yes if some single line of $1 contains every one of the remaining needles
line_has_all() { # text needle...
  local text="$1"; shift
  local line ok n
  while IFS= read -r line; do
    ok=1
    for n in "$@"; do
      case "$line" in *"$n"*) ;; *) ok=0; break ;; esac
    done
    [ "$ok" -eq 1 ] && { echo yes; return; }
  done <<< "$text"
  echo no
}

final_line() { # text -> last non-blank line
  printf '%s\n' "$1" | grep -v '^[[:space:]]*$' | tail -n 1
}

log_has() { # log_file needle -> yes/no
  [ -f "$1" ] && grep -qF -- "$2" "$1" && echo yes || echo no
}

log_pos() { # log_file needle -> line number of first match, or empty
  [ -f "$1" ] || return
  grep -n -F -- "$2" "$1" | head -1 | cut -d: -f1
}

order_ok() { # log_file needleA needleB -> yes if A's first match precedes B's
  local log="$1" a="$2" b="$3" pa pb
  pa="$(log_pos "$log" "$a")"
  pb="$(log_pos "$log" "$b")"
  if [ -z "$pa" ] || [ -z "$pb" ]; then echo no; return; fi
  [ "$pa" -lt "$pb" ] && echo yes || echo no
}

log_count() { # log_file needle -> count of matching lines
  [ -f "$1" ] || { echo 0; return; }
  grep -cF -- "$2" "$1" || true
}

tree_snapshot() { # root -> sorted "relpath  sha256" lines
  local root="$1"
  ( cd "$root" && find . -type f -exec cksum {} + ) | sort
}

# ---------------------------------------------------------------------------
# B03 (ci-parallel-stages) helpers.
#
# Concurrency changes what EXECUTION order guarantees still hold (none,
# within the test/validate stages) versus what OUTPUT order guarantees hold
# (fixed, always) -- text_pos/text_order_ok below assert the latter, against
# ci.sh's own stdout, instead of the log-write order the pre-B03 tests used.
# ---------------------------------------------------------------------------
text_pos() { # text needle -> line number of first EXACT-line match, or empty
  # -x (whole-line) matters here: "-- plugins/alpha" must not match the
  # earlier "-- plugins/alpha/lib/m.test.sh" test-check header as a prefix.
  printf '%s\n' "$1" | grep -n -x -F -- "$2" | head -1 | cut -d: -f1
}

text_order_ok() { # text needleA needleB -> yes if A's first match precedes B's
  local text="$1" a="$2" b="$3" pa pb
  pa="$(text_pos "$text" "$a")"
  pb="$(text_pos "$text" "$b")"
  if [ -z "$pa" ] || [ -z "$pb" ]; then echo no; return; fi
  [ "$pa" -lt "$pb" ] && echo yes || echo no
}

# A check stub that emits a large, exact, predictable body to stdout only
# (no stderr, to keep the transcript-identity assertion unambiguous about
# which real stream carries it). build_expected_block below must be kept
# byte-for-byte in sync with the line this prints.
write_output_stub() { # <path> <name> <n_lines> <exit_code>
  local path="$1" name="$2" n="$3" code="$4"
  cat > "$path" <<STUB
#!/bin/bash
i=0
while [ "\$i" -lt $n ]; do
  printf '%s stdout line %d aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' '$name' "\$i"
  i=\$((i+1))
done
exit $code
STUB
  chmod +x "$path"
}

# The exact "-- <name>" header plus body ci.sh should emit for one
# write_output_stub check, so the transcript-identity test can assert byte
# equality of a whole contiguous slice of RUN_OUT rather than just presence.
build_expected_block() { # <name> <n_lines>
  local name="$1" n="$2" i=0 out
  out="-- $name"$'\n'
  while [ "$i" -lt "$n" ]; do
    out="${out}$(printf '%s stdout line %d aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$name" "$i")"$'\n'
    i=$((i+1))
  done
  printf '%s' "$out"
}

# Like write_claude_shim, but fails validate on ANY of several target
# substrings instead of just one, so a stage can be given more than one
# failing target to test "first failure in fixed order" reporting.
write_claude_shim_multi() { # <shim_dir> <log_file> <expected_cwd> <fail_substr...>
  local dir="$1" log="$2" exp="$3"; shift 3
  mkdir -p "$dir"
  local cases="" fs
  for fs in "$@"; do
    cases="$cases
  case \"\$3\" in *'$fs'*) exit 1 ;; esac"
  done
  cat > "$dir/claude" <<STUB
#!/bin/bash
printf 'CALL claude %s\n' "\$*" >> '$log'
if [ "\$1" = "plugin" ] && [ "\$2" = "validate" ]; then
  printf 'CHECK validate:%s\n' "\$3" >> '$log'
  if [ "\$(pwd)" = '$exp' ]; then
    printf 'CWD_OK validate:%s\n' "\$3" >> '$log'
  else
    printf 'CWD_BAD validate:%s %s\n' "\$3" "\$(pwd)" >> '$log'
  fi
$cases
fi
exit 0
STUB
  chmod +x "$dir/claude"
}

# A fake scheduler binary (xargs/parallel/sem) that just records that it was
# invoked at all -- ci.sh must never spawn any of these (B03: bash job
# control and wait only).
write_scheduler_shim() { # <shim_dir> <log_file> <tool_name>
  local dir="$1" log="$2" tool="$3"
  mkdir -p "$dir"
  cat > "$dir/$tool" <<STUB
#!/bin/bash
printf 'CALLED $tool %s\n' "\$*" >> '$log'
exit 0
STUB
  chmod +x "$dir/$tool"
}

# ---------------------------------------------------------------------------
# Concurrency-cap barrier apparatus. No sleep and no wall-clock assertion is
# used to decide pass/fail: each stub blocks on a shared FIFO until this
# script explicitly releases it, so "how many checks are running right now"
# is an exact causal signal, never a timing guess. Wall time (via
# wait_for_count's deadline) is used ONLY as a hang guard against a truly
# broken run; it never determines a pass.
# ---------------------------------------------------------------------------
write_barrier_stub() { # <path> <name> <run_dir> <gate_fifo> <exit_code>
  local path="$1" name="$2" rundir="$3" gate="$4" code="$5"
  cat > "$path" <<STUB
#!/bin/bash
: > '$rundir/running-$name'
read -r _ < '$gate'
rm -f '$rundir/running-$name'
: > '$rundir/done-$name'
exit $code
STUB
  chmod +x "$path"
}

count_glob() { # dir pattern -> count of matching files
  local d="$1" p="$2" n=0 f
  for f in "$d"/$p; do
    [ -e "$f" ] && n=$((n+1))
  done
  echo "$n"
}

# Busy-waits (no sleep) for at least <want> files matching <pattern> in
# <dir>, bailing out early -- "yes" if met, "no" if the background pid has
# already exited (nothing more will change) or a generous deadline elapses.
wait_for_count() { # <dir> <pattern> <want> <pid> <timeout_secs>
  local dir="$1" pat="$2" want="$3" pid="$4" secs="$5" deadline
  deadline=$(( $(date +%s) + secs ))
  while :; do
    [ "$(count_glob "$dir" "$pat")" -ge "$want" ] && { echo yes; return; }
    if ! kill -0 "$pid" 2>/dev/null; then echo no; return; fi
    [ "$(date +%s)" -ge "$deadline" ] && { echo no; return; }
  done
}

RUN_BG_PID=""
RUN_BG_OUT=""
RUN_BG_ERR=""

run_ci_bg() { # <cwd> <path_value> <ci_args...> -- backgrounds ci.sh
  local cwd="$1" pathval="$2"; shift 2
  RUN_BG_OUT="$(mktemp)"; RUN_BG_ERR="$(mktemp)"
  track_tmp "$RUN_BG_OUT"; track_tmp "$RUN_BG_ERR"
  ( cd "$cwd" && PATH="$pathval" bash "$CI_SCRIPT" "$@" >"$RUN_BG_OUT" 2>"$RUN_BG_ERR" ) &
  RUN_BG_PID=$!
}

wait_bg() { # -> sets RUN_EXIT/RUN_OUT/RUN_ERR from the backgrounded run
  wait "$RUN_BG_PID" 2>/dev/null
  RUN_EXIT=$?
  RUN_OUT="$(cat "$RUN_BG_OUT" 2>/dev/null)"
  RUN_ERR="$(cat "$RUN_BG_ERR" 2>/dev/null)"
}

# Runs ci.sh in the background against a test stage made entirely of
# barrier stubs, and reports "yes" only if (a) at no point did more than
# $cap of them run at once, and (b) the run eventually finished all of them
# with exit 0. <extra_args...> -- <check_name...>  (names become
# scripts/<name>.test.sh in $repo).
assert_jobs_cap() { # <repo> <pathval> <cap> <extra_args...> -- <names...>
  local repo="$1" pathval="$2" cap="$3"; shift 3
  local extra=()
  while [ "$1" != "--" ]; do extra+=("$1"); shift; done
  shift
  local names=("$@") rundir gate n total want got count
  rundir="$(mktemp -d)"; track_tmp "$rundir"
  gate="$(mktemp -u)"; mkfifo "$gate"; track_tmp "$gate"
  exec 8<>"$gate"
  for n in "${names[@]}"; do
    write_barrier_stub "$repo/scripts/$n.test.sh" "$n" "$rundir" "$gate" 0
  done
  run_ci_bg "$repo" "$pathval" "${extra[@]}"
  total="${#names[@]}"
  want=$(( total < cap ? total : cap ))
  got="$(wait_for_count "$rundir" "running-*" "$want" "$RUN_BG_PID" 3)"
  count="$(count_glob "$rundir" "running-*")"
  printf 'go\n%.0s' $(seq 1 "$total") >&8
  wait_bg
  exec 8>&-
  if [ "$got" = "yes" ] && [ "$count" -le "$cap" ] && [ "$RUN_EXIT" -eq 0 ]; then
    echo yes
  else
    echo no
  fi
}

# ---------------------------------------------------------------------------
# B10 (ci-scheduler-slot-fill) helpers. write_barrier_stub above already
# gives a controllable long-running check; these two add the other roles
# the fill-on-any-completion distinguishing construction needs: a check
# that finishes at once, and a check whose completion leaves a durable,
# no-timing mark that a poll loop can detect.
# ---------------------------------------------------------------------------
write_immediate_stub() { # <path> <exit_code>
  local path="$1" code="$2"
  cat > "$path" <<STUB
#!/bin/bash
exit $code
STUB
  chmod +x "$path"
}

write_marker_stub() { # <path> <marker_file> <exit_code>
  local path="$1" marker="$2" code="$3"
  cat > "$path" <<STUB
#!/bin/bash
: > '$marker'
exit $code
STUB
  chmod +x "$path"
}

# Namespaced check names, shared across cases.
NAME_MP="lint:marketplace-lint"
NAME_EX="lint:executable-lint"
NAME_RL="lint:readme-lint"
NAME_VB="lint:version-bump-lint"
NAME_ITL="lint:issue-template-lint"
NAME_AL="lint:architecture-lint"
NAME_SC="lint:shellcheck-lint"

# ===========================================================================
# 1. Full green run (no flags): stage headers, check-prefix lines, stage
#    order, lint check order (+ cwd), test check order (repo-level before
#    plugins, lexicographic), validate order (marketplace.json before any
#    plugin). Contract: Behavior (stage list, lint/test/validate contents),
#    Outputs ("==" headers, "--" check lines, final "CI PASS"), Invariants
#    (stage order fixed, check order fixed, cwd-independent).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
write_check_stub "$f/scripts/z.test.sh" "test:scripts/z.test.sh" "$log" "$f" 0
mkdir -p "$f/plugins/alpha/scripts" "$f/plugins/alpha/lib" "$f/plugins/zeta/scripts" "$f/plugins/zeta/lib"
write_check_stub "$f/plugins/alpha/scripts/n.test.sh" "test:plugins/alpha/scripts/n.test.sh" "$log" "$f" 0
write_check_stub "$f/plugins/alpha/lib/m.test.sh" "test:plugins/alpha/lib/m.test.sh" "$log" "$f" 0
write_check_stub "$f/plugins/zeta/scripts/q.test.sh" "test:plugins/zeta/scripts/q.test.sh" "$log" "$f" 0
write_check_stub "$f/plugins/zeta/lib/k.test.sh" "test:plugins/zeta/lib/k.test.sh" "$log" "$f" 0
shim="$(mktemp -d)"; track_tmp "$shim"
write_claude_shim "$shim" "$log" "$f" ""
run_ci "$f" "$shim:$BASE_PATH"

check "1. full green: exit 0" "$RUN_EXIT" "0"
check "1. full green: final line CI PASS" "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"
check "1. stage headers: == lint ==" "$(contains "$RUN_OUT" "== lint ==")" "yes"
check "1. stage headers: == test ==" "$(contains "$RUN_OUT" "== test ==")" "yes"
check "1. stage headers: == validate ==" "$(contains "$RUN_OUT" "== validate ==")" "yes"
check "1. check-prefix line for a lint check" \
  "$(line_has_all "$RUN_OUT" "--" "marketplace-lint")" "yes"
check "1. check-prefix line for architecture-lint check" \
  "$(line_has_all "$RUN_OUT" "--" "architecture-lint")" "yes"
check "1. check-prefix line for shellcheck-lint check" \
  "$(line_has_all "$RUN_OUT" "--" "shellcheck-lint")" "yes"
check "1. check-prefix line for a test check" \
  "$(line_has_all "$RUN_OUT" "--" "a.test.sh")" "yes"
check "1. stage order: lint before test" \
  "$(order_ok "$log" "CHECK $NAME_MP" "CHECK test:scripts/a.test.sh")" "yes"
check "1. stage order: test before validate" \
  "$(order_ok "$log" "CHECK test:scripts/a.test.sh" "CHECK validate:.claude-plugin/marketplace.json")" "yes"
check "1. lint order: marketplace before executable" \
  "$(order_ok "$log" "CHECK $NAME_MP" "CHECK $NAME_EX")" "yes"
check "1. lint order: executable before readme" \
  "$(order_ok "$log" "CHECK $NAME_EX" "CHECK $NAME_RL")" "yes"
check "1. lint order: readme before version-bump" \
  "$(order_ok "$log" "CHECK $NAME_RL" "CHECK $NAME_VB")" "yes"
check "1. lint order: issue-template-lint before architecture-lint" \
  "$(order_ok "$log" "CHECK $NAME_ITL" "CHECK $NAME_AL")" "yes"
check "1. lint stage: shellcheck-lint ran (B07: seventh and last lint check)" \
  "$(log_has "$log" "CHECK $NAME_SC")" "yes"
check "1. lint order: architecture-lint before shellcheck-lint" \
  "$(order_ok "$log" "CHECK $NAME_AL" "CHECK $NAME_SC")" "yes"
check "1. lint order: shellcheck-lint before test stage" \
  "$(order_ok "$log" "CHECK $NAME_SC" "CHECK test:scripts/a.test.sh")" "yes"
check "1. lint checks all ran from repo root (no CWD_BAD)" \
  "$(log_has "$log" "CWD_BAD")" "no"
# B03: within the test/validate stages EXECUTION order is explicitly no
# longer guaranteed (checks run concurrently), so these can no longer be
# asserted via the log's CHECK-write order -- only ci.sh's own OUTPUT order
# is contracted to stay fixed. Asserted against RUN_OUT (the "-- <name>"
# header ci.sh itself prints), not the log.
check "1. test order: repo-level a before repo-level z (OUTPUT order)" \
  "$(text_order_ok "$RUN_OUT" "-- scripts/a.test.sh" "-- scripts/z.test.sh")" "yes"
check "1. test order: repo-level z before plugins/alpha/lib (OUTPUT order)" \
  "$(text_order_ok "$RUN_OUT" "-- scripts/z.test.sh" "-- plugins/alpha/lib/m.test.sh")" "yes"
check "1. test order: alpha/lib before alpha/scripts (OUTPUT order, lexicographic)" \
  "$(text_order_ok "$RUN_OUT" "-- plugins/alpha/lib/m.test.sh" "-- plugins/alpha/scripts/n.test.sh")" "yes"
check "1. test order: alpha/scripts before zeta/lib (OUTPUT order, lexicographic)" \
  "$(text_order_ok "$RUN_OUT" "-- plugins/alpha/scripts/n.test.sh" "-- plugins/zeta/lib/k.test.sh")" "yes"
check "1. test order: zeta/lib before zeta/scripts (OUTPUT order, lexicographic)" \
  "$(text_order_ok "$RUN_OUT" "-- plugins/zeta/lib/k.test.sh" "-- plugins/zeta/scripts/q.test.sh")" "yes"
check "1. validate order: marketplace.json before plugins/alpha (OUTPUT order)" \
  "$(text_order_ok "$RUN_OUT" "-- .claude-plugin/marketplace.json" "-- plugins/alpha")" "yes"
check "1. validate order: marketplace.json before plugins/zeta (OUTPUT order)" \
  "$(text_order_ok "$RUN_OUT" "-- .claude-plugin/marketplace.json" "-- plugins/zeta")" "yes"

# ===========================================================================
# 2. Fail-fast within lint stage: 2nd lint check (executable-lint) fails;
#    later lint checks and the entire test/validate stages never run.
#    Contract: Behavior (fail-fast), Outputs (final "CI FAIL: <stage>/
#    <check>"), Errors (exit 1 on check failure).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 1
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "2. fail-fast lint: exit 1" "$RUN_EXIT" "1"
check "2. fail-fast lint: marketplace-lint ran" "$(log_has "$log" "CHECK $NAME_MP")" "yes"
check "2. fail-fast lint: executable-lint ran" "$(log_has "$log" "CHECK $NAME_EX")" "yes"
check "2. fail-fast lint: readme-lint never ran" "$(log_has "$log" "CHECK $NAME_RL")" "no"
check "2. fail-fast lint: version-bump-lint never ran" "$(log_has "$log" "CHECK $NAME_VB")" "no"
check "2. fail-fast lint: issue-template-lint never ran" "$(log_has "$log" "CHECK $NAME_ITL")" "no"
check "2. fail-fast lint: architecture-lint never ran" "$(log_has "$log" "CHECK $NAME_AL")" "no"
check "2. fail-fast lint: shellcheck-lint never ran" "$(log_has "$log" "CHECK $NAME_SC")" "no"
check "2. fail-fast lint: test stage never ran" "$(log_has "$log" "CHECK test:")" "no"
check "2. fail-fast lint: final line names lint/executable-lint" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "lint/" "executable-lint")" "yes"

# ===========================================================================
# 3. --lint solo: only the lint stage's checks run; test/validate never
#    invoked (claude/gh stripped from PATH entirely as an extra proof they
#    are never even reachable). Contract: Inputs (stage flag semantics).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
mkdir -p "$f/plugins/alpha"
run_ci "$f" "$BASE_PATH" --lint

check "3. --lint solo: exit 0" "$RUN_EXIT" "0"
check "3. --lint solo: final line CI PASS" "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"
check "3. --lint solo: all 7 lint checks ran" "$(log_count "$log" "CHECK lint:")" "7"
check "3. --lint solo: test stage never ran" "$(log_has "$log" "CHECK test:")" "no"
check "3. --lint solo: validate stage never ran" "$(log_has "$log" "CHECK validate:")" "no"

# ===========================================================================
# 4. --test solo: only the test stage's checks run; lint/validate never
#    invoked. Contract: Inputs (stage flag semantics).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
mkdir -p "$f/plugins/alpha"
run_ci "$f" "$BASE_PATH" --test

check "4. --test solo: exit 0" "$RUN_EXIT" "0"
check "4. --test solo: final line CI PASS" "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"
check "4. --test solo: test check ran" "$(log_has "$log" "CHECK test:scripts/a.test.sh")" "yes"
check "4. --test solo: lint stage never ran" "$(log_has "$log" "CHECK lint:")" "no"
check "4. --test solo: validate stage never ran" "$(log_has "$log" "CHECK validate:")" "no"

# ===========================================================================
# 5. --lint and --test together: usage error, exit 2, nothing invoked.
#    Contract: Inputs ("--lint and --test together is a usage error"),
#    Errors (usage line on stderr, exit 2).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --lint --test

check "5. --lint --test together: exit 2" "$RUN_EXIT" "2"
check "5. --lint --test together: stderr non-empty" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
check "5. --lint --test together: nothing invoked" \
  "$([ -s "$log" ] && echo no || echo yes)" "yes"

# ===========================================================================
# 6. Unknown flag: usage error, exit 2, nothing invoked. Contract: Errors
#    ("Unknown flag ... usage line on stderr, exit 2").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --bogus

check "6. unknown flag: exit 2" "$RUN_EXIT" "2"
check "6. unknown flag: stderr non-empty" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
check "6. unknown flag: nothing invoked" \
  "$([ -s "$log" ] && echo no || echo yes)" "yes"

# ===========================================================================
# 7. Not inside a git repository: exit 2, diagnostic on stderr. Contract:
#    Errors ("Not inside a git repository: diagnostic on stderr, exit 2").
# ===========================================================================
plain="$(mktemp -d)"; track_tmp "$plain"
run_ci "$plain" "$BASE_PATH"

check "7. not a repo: exit 2" "$RUN_EXIT" "2"
check "7. not a repo: stderr non-empty" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 8. claude absent, everything else passing: validate WARN-skips, exit
#    unaffected. Contract: Outputs (WARN skip notice, exact wording),
#    Invariants (absent enhancer degrades to WARN, not failure).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "8. claude absent: exit 0" "$RUN_EXIT" "0"
check "8. claude absent: WARN skip notice" \
  "$(contains "$RUN_OUT" "WARN  validate skipped (claude CLI not found)")" "yes"
check "8. claude absent: final line CI PASS" "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"
check "8. claude absent: claude never actually invoked" \
  "$(log_has "$log" "CALL claude")" "no"

# ===========================================================================
# 9. claude present with a failing validate check, combined with a vacuous
#    test stage (no test files anywhere). Contract: Outputs (empty-stage
#    notice "no <stage> checks to run", vacuous pass), Edge cases (claude
#    present + validate fails -> CI FAIL exit 1; presence gates).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
mkdir -p "$f/plugins/beta"
shim="$(mktemp -d)"; track_tmp "$shim"
write_claude_shim "$shim" "$log" "$f" "beta"
run_ci "$f" "$shim:$BASE_PATH"

check "9. vacuous test stage: notice printed" \
  "$(contains "$RUN_OUT" "no test checks to run")" "yes"
check "9. lint stage completes: architecture-lint ran" "$(log_has "$log" "CHECK $NAME_AL")" "yes"
check "9. validate fails: marketplace.json still checked" \
  "$(log_has "$log" "CHECK validate:.claude-plugin/marketplace.json")" "yes"
check "9. validate fails: plugins/beta checked" \
  "$(log_has "$log" "CHECK validate:plugins/beta")" "yes"
check "9. validate fails: exit 1" "$RUN_EXIT" "1"
check "9. validate fails: final line names validate/beta" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "validate/" "beta")" "yes"

# ===========================================================================
# 10. --post-status on a green run: gh posted exactly once with context
#     "pseudo-ci", state "success", HEAD's sha, and the origin-derived repo.
#     Contract: Behavior (--post-status), Inputs (context/state/sha/repo),
#     Invariants (status POST reflects true outcome).
# ===========================================================================
f="$(new_repo)"
sha="$(git -C "$f" rev-parse HEAD)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
shim="$(mktemp -d)"; track_tmp "$shim"
write_claude_shim "$shim" "$log" "$f" ""
write_gh_shim "$shim" "$log" 0
run_ci "$f" "$shim:$BASE_PATH" --post-status

check "10. post-status green: exit 0" "$RUN_EXIT" "0"
check "10. post-status green: gh invoked exactly once" "$(log_count "$log" "CALL gh")" "1"
check "10. post-status green: state success" "$(log_has "$log" "success")" "yes"
check "10. post-status green: context pseudo-ci" "$(log_has "$log" "pseudo-ci")" "yes"
check "10. post-status green: sha present" "$(log_has "$log" "$sha")" "yes"
check "10. post-status green: repo derived from origin" \
  "$(log_has "$log" "testowner/testrepo")" "yes"

# ===========================================================================
# 11. --post-status on a fail-fast run: a fail-fast run still posts
#     "failure" before exiting. Contract: Behavior ("With --post-status, a
#     GitHub commit status is posted ... when the run concludes (pass or
#     fail alike)"), Invariants ("a fail-fast run still posts failure
#     before exiting").
# ===========================================================================
f="$(new_repo)"
sha="$(git -C "$f" rev-parse HEAD)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 1
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
shim="$(mktemp -d)"; track_tmp "$shim"
write_gh_shim "$shim" "$log" 0
run_ci "$f" "$shim:$BASE_PATH" --post-status

check "11. post-status fail-fast: exit 1" "$RUN_EXIT" "1"
check "11. post-status fail-fast: gh invoked" "$(log_has "$log" "CALL gh")" "yes"
check "11. post-status fail-fast: state failure" "$(log_has "$log" "failure")" "yes"
check "11. post-status fail-fast: context pseudo-ci" "$(log_has "$log" "pseudo-ci")" "yes"
check "11. post-status fail-fast: sha present" "$(log_has "$log" "$sha")" "yes"
check "11. post-status fail-fast: executable-lint never ran (fail-fast)" \
  "$(log_has "$log" "CHECK $NAME_EX")" "no"
check "11. post-status fail-fast: architecture-lint never ran (fail-fast)" \
  "$(log_has "$log" "CHECK $NAME_AL")" "no"
check "11. post-status fail-fast: shellcheck-lint never ran (fail-fast)" \
  "$(log_has "$log" "CHECK $NAME_SC")" "no"

# ===========================================================================
# 12. No --post-status flag: gh is never attempted (gh entirely absent from
#     PATH to prove no dependency on it), and no "status not posted" WARN
#     appears since posting was never requested. Contract: Outputs ("never
#     attempted without --post-status"), Invariants (gh is an optional
#     enhancer only engaged by the flag).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "12. no post-status flag: exit 0" "$RUN_EXIT" "0"
check "12. no post-status flag: no 'status not posted' WARN" \
  "$(contains "$RUN_OUT" "status not posted")" "no"

# ===========================================================================
# 13. gh absent + --post-status: WARN, exit unaffected. Contract: Outputs
#     (WARN reason "gh absent"), Invariants (absence degrades to WARN never
#     failure).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --post-status

check "13. gh absent + post-status: exit 0 (unaffected)" "$RUN_EXIT" "0"
check "13. gh absent + post-status: WARN status not posted" \
  "$(contains "$RUN_OUT" "WARN  status not posted (")" "yes"
check "13. gh absent + post-status: final line still CI PASS" \
  "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"

# ===========================================================================
# 14. gh present but failing (e.g. unauthenticated) + --post-status: gh WAS
#     attempted, WARN issued, exit unaffected. Contract: Outputs (WARN
#     reasons include gh failure modes), Invariants (never a failure).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
shim="$(mktemp -d)"; track_tmp "$shim"
write_gh_shim "$shim" "$log" 1
run_ci "$f" "$shim:$BASE_PATH" --post-status

check "14. gh failing + post-status: gh was attempted" "$(log_has "$log" "CALL gh")" "yes"
check "14. gh failing + post-status: WARN status not posted" \
  "$(contains "$RUN_OUT" "WARN  status not posted (")" "yes"
check "14. gh failing + post-status: exit 0 (unaffected)" "$RUN_EXIT" "0"

# ===========================================================================
# 15. --post-status with a non-GitHub origin remote: WARN, no POST attempt
#     at all, exit unaffected. Contract: Edge cases ("--post-status with a
#     non-GitHub origin remote: WARN, no POST, exit code unaffected").
# ===========================================================================
f="$(new_repo)"
git -C "$f" remote set-url origin https://gitlab.com/testowner/testrepo.git
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
shim="$(mktemp -d)"; track_tmp "$shim"
write_gh_shim "$shim" "$log" 0
run_ci "$f" "$shim:$BASE_PATH" --post-status

check "15. non-GitHub remote: gh never invoked" "$(log_has "$log" "CALL gh")" "no"
check "15. non-GitHub remote: WARN status not posted" \
  "$(contains "$RUN_OUT" "WARN  status not posted (")" "yes"
check "15. non-GitHub remote: exit 0 (unaffected)" "$RUN_EXIT" "0"

# ===========================================================================
# 16. A lint check exiting 2 (its own environment error) is reported as
#     that check's failure: CI FAIL, exit 1 (not 2) — and fail-fast still
#     applies (the next lint check never runs). Contract: Errors ("A
#     lint/test script that exits 2 ... is reported as that check's
#     failure: CI FAIL, exit 1").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 2
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "16. lint check exits 2: exit 1 (not 2)" "$RUN_EXIT" "1"
check "16. lint check exits 2: final line names lint/readme-lint" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "lint/" "readme-lint")" "yes"
check "16. lint check exits 2: version-bump-lint never ran (fail-fast)" \
  "$(log_has "$log" "CHECK $NAME_VB")" "no"
check "16. lint check exits 2: issue-template-lint never ran (fail-fast)" \
  "$(log_has "$log" "CHECK $NAME_ITL")" "no"
check "16. lint check exits 2: architecture-lint never ran (fail-fast)" \
  "$(log_has "$log" "CHECK $NAME_AL")" "no"
check "16. lint check exits 2: shellcheck-lint never ran (fail-fast)" \
  "$(log_has "$log" "CHECK $NAME_SC")" "no"

# ===========================================================================
# 17. A test check exiting 2 is likewise CI FAIL, exit 1. Errors (same
#     clause, explicitly covers "lint/test"). Post-B03: the test STAGE still
#     fail-fasts the overall run (validate never starts), but WITHIN the
#     stage every check now runs to completion even after an earlier one
#     already failed -- z.test.sh (later in fixed order than the failing
#     a.test.sh) still runs. Contract: Behavior ("every check in the stage
#     runs to completion even when an earlier one fails").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 2
write_check_stub "$f/scripts/z.test.sh" "test:scripts/z.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "17. test check exits 2: exit 1 (not 2)" "$RUN_EXIT" "1"
check "17. test check exits 2: final line names test/a.test.sh" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "test/" "a.test.sh")" "yes"
check "17. test check exits 2: z.test.sh DOES run (B03: stage runs to completion, only stage-level fail-fast remains)" \
  "$(log_has "$log" "CHECK test:scripts/z.test.sh")" "yes"
check "17. test check exits 2: validate never ran (stage-level fail-fast)" \
  "$(log_has "$log" "CHECK validate:")" "no"

# ===========================================================================
# 18. cwd-independence: invoking from a nested subdirectory still resolves
#     the repo root and passes; every lint check still runs with cwd at the
#     repo root (no CWD_BAD). Contract: Invariants ("cwd-independent:
#     resolves the repo root via git rev-parse and runs every check from
#     there").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
run_ci "$f/scripts" "$BASE_PATH"

check "18. cwd-independence: exit 0 from nested subdir" "$RUN_EXIT" "0"
check "18. cwd-independence: final line CI PASS" "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"
check "18. cwd-independence: all lint checks ran from repo root" \
  "$(log_has "$log" "CWD_BAD")" "no"
check "18. cwd-independence: all 7 lint checks ran" "$(log_count "$log" "CHECK lint:")" "7"

# ===========================================================================
# 19. Read-only invariant: the fixture tree is byte-identical before/after
#     a run (no --post-status, so the only possible side effect is
#     excluded by construction). Contract: Invariants ("Read-only with
#     respect to the repo; the only side effect is the optional gh status
#     POST").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
before="$(tree_snapshot "$f")"
run_ci "$f" "$BASE_PATH"
after="$(tree_snapshot "$f")"

check "19. read-only invariant: fixture tree unchanged" "$after" "$before"

# ===========================================================================
# 20. No config/env reads: a .claude/ and .local/ tree containing
#     unparseable/arbitrary content does not affect the outcome. Contract:
#     Inputs ("No environment variables, no config files ... reads NOTHING
#     from .claude/ or .local/").
# ===========================================================================
f="$(new_repo)"
mkdir -p "$f/.claude" "$f/.local"
printf '{not valid json' > "$f/.claude/settings.json"
printf 'arbitrary tracking content\n' > "$f/.local/status.md"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "20. unread config: exit 0 unaffected" "$RUN_EXIT" "0"
check "20. unread config: final line CI PASS" "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"

# ===========================================================================
# 21. architecture-lint fails as the lint stage's sixth check: the five
#     preceding lint checks ran (in order), architecture-lint ran and
#     failed, and fail-fast stops the run before the test stage starts.
#     Contract: Contract-delta B09 Behavior/Outputs ("SIXTH check ... after
#     issue-template-lint"; "a architecture-lint failure is 'CI FAIL:
#     lint/architecture-lint', exit 1"), Invariants ("fail-fast semantics
#     unchanged").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 1
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "21. architecture-lint fails: exit 1" "$RUN_EXIT" "1"
check "21. architecture-lint fails: marketplace-lint ran" "$(log_has "$log" "CHECK $NAME_MP")" "yes"
check "21. architecture-lint fails: executable-lint ran" "$(log_has "$log" "CHECK $NAME_EX")" "yes"
check "21. architecture-lint fails: readme-lint ran" "$(log_has "$log" "CHECK $NAME_RL")" "yes"
check "21. architecture-lint fails: version-bump-lint ran" "$(log_has "$log" "CHECK $NAME_VB")" "yes"
check "21. architecture-lint fails: issue-template-lint ran" "$(log_has "$log" "CHECK $NAME_ITL")" "yes"
check "21. architecture-lint fails: architecture-lint ran" "$(log_has "$log" "CHECK $NAME_AL")" "yes"
check "21. architecture-lint fails: issue-template-lint before architecture-lint" \
  "$(order_ok "$log" "CHECK $NAME_ITL" "CHECK $NAME_AL")" "yes"
check "21. architecture-lint fails: shellcheck-lint never ran (fail-fast stops at the sixth check)" \
  "$(log_has "$log" "CHECK $NAME_SC")" "no"
check "21. architecture-lint fails: test stage never ran (fail-fast)" \
  "$(log_has "$log" "CHECK test:")" "no"
check "21. architecture-lint fails: final line CI FAIL: lint/architecture-lint" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "lint/" "architecture-lint")" "yes"

# ===========================================================================
# 22. architecture-lint exiting 2 (its own environment error) is reported as
#     that check's failure like every other lint check: CI FAIL, exit 1 (not
#     2); fail-fast still stops the test stage. Contract: Contract-delta B09
#     Errors clause ("architecture-lint exiting 2 ... is reported as that
#     check's failure, same as every other lint failure").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 2
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "22. architecture-lint exits 2: exit 1 (not 2)" "$RUN_EXIT" "1"
check "22. architecture-lint exits 2: final line names lint/architecture-lint" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "lint/" "architecture-lint")" "yes"
check "22. architecture-lint exits 2: test stage never ran (fail-fast)" \
  "$(log_has "$log" "CHECK test:")" "no"

# ===========================================================================
# B03 (ci-parallel-stages): stage-level fail-fast survives; within the test
# and validate stages, checks run concurrently under --jobs <n>; per-check
# output is buffered and emitted whole in fixed order; bash job control
# only, no external scheduler; lint stays sequential.
# ===========================================================================

# ===========================================================================
# 23. --jobs 1 is documented as the escape hatch that forces fully
#     sequential execution. With jobs=1 there is no concurrency to race, so
#     -- uniquely among the test/validate ordering assertions -- EXECUTION
#     order (via the log's CHECK-write order) is legitimately deterministic
#     and can be asserted directly. Contract: Inputs ("--jobs 1 forces fully
#     sequential execution ... the escape hatch for debugging an
#     interleaving-sensitive failure").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
write_check_stub "$f/scripts/z.test.sh" "test:scripts/z.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --test --jobs 1

check "23. --jobs 1 escape hatch: exit 0" "$RUN_EXIT" "0"
check "23. --jobs 1 escape hatch: final line CI PASS" "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"
check "23. --jobs 1 escape hatch: deterministic execution order, a before z" \
  "$(order_ok "$log" "CHECK test:scripts/a.test.sh" "CHECK test:scripts/z.test.sh")" "yes"

# ===========================================================================
# 24. --jobs with a valid value (3) is accepted and does not change the
#     outcome of an all-green run. Contract: Inputs ("--jobs <n> ... max
#     concurrent checks").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
shim="$(mktemp -d)"; track_tmp "$shim"
write_claude_shim "$shim" "$log" "$f" ""
run_ci "$f" "$shim:$BASE_PATH" --jobs 3

check "24. --jobs 3 valid value: exit 0" "$RUN_EXIT" "0"
check "24. --jobs 3 valid value: final line CI PASS" "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"

# ===========================================================================
# 25-27. Invalid --jobs values are a usage error, exit 2, nothing invoked.
#     Contract: Inputs ("A non-integer or <1 value is a usage error, exit
#     2."). 0 and -1 are both <1; "abc" is non-integer.
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --jobs 0

check "25. --jobs 0: exit 2" "$RUN_EXIT" "2"
check "25. --jobs 0: stderr non-empty" "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
check "25. --jobs 0: nothing invoked" "$([ -s "$log" ] && echo no || echo yes)" "yes"

f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --jobs -1

check "26. --jobs -1: exit 2" "$RUN_EXIT" "2"
check "26. --jobs -1: stderr non-empty" "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
check "26. --jobs -1: nothing invoked" "$([ -s "$log" ] && echo no || echo yes)" "yes"

f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --jobs abc

check "27. --jobs abc (non-integer): exit 2" "$RUN_EXIT" "2"
check "27. --jobs abc (non-integer): stderr non-empty" "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
check "27. --jobs abc (non-integer): nothing invoked" "$([ -s "$log" ] && echo no || echo yes)" "yes"

# ===========================================================================
# 28. The lint stage stays strictly sequential and check-level fail-fast
#     even when --jobs is given a value greater than 1: --jobs only affects
#     the test and validate stages. Contract: Behavior ("Lint checks remain
#     strictly sequential and check-level fail-fast").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 1
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --lint --jobs 4

check "28. lint stays sequential under --jobs: exit 1" "$RUN_EXIT" "1"
check "28. lint stays sequential under --jobs: version-bump-lint never ran (fail-fast unaffected)" \
  "$(log_has "$log" "CHECK $NAME_VB")" "no"
check "28. lint stays sequential under --jobs: architecture-lint never ran" \
  "$(log_has "$log" "CHECK $NAME_AL")" "no"
check "28. lint stays sequential under --jobs: shellcheck-lint never ran" \
  "$(log_has "$log" "CHECK $NAME_SC")" "no"
check "28. lint stays sequential under --jobs: final line names lint/readme-lint" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "lint/" "readme-lint")" "yes"

# ===========================================================================
# 29. Multiple failures in the TEST stage: every check still runs to
#     completion (b and c both fail, but a and d -- which come both before
#     and after them in fixed order -- still run), the reported failure is
#     the FIRST one in FIXED order (b), not whichever happened to finish
#     first under concurrency (c), and the stage failure still prevents
#     validate from starting at all. No timing is used to force b to
#     "finish first": for a correct implementation this holds regardless of
#     real completion order, since the docblock requires the choice to be
#     made by fixed order, not completion order. Contract: Behavior ("every
#     check in the stage runs to completion... reports the FIRST failure in
#     fixed output order"), Behavior ("Stage-level fail-fast: a failing
#     STAGE stops the run").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
write_check_stub "$f/scripts/b.test.sh" "test:scripts/b.test.sh" "$log" "$f" 1
write_check_stub "$f/scripts/c.test.sh" "test:scripts/c.test.sh" "$log" "$f" 1
write_check_stub "$f/scripts/d.test.sh" "test:scripts/d.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "29. test-stage multi-failure: exit 1" "$RUN_EXIT" "1"
check "29. test-stage multi-failure: a.test.sh ran" "$(log_has "$log" "CHECK test:scripts/a.test.sh")" "yes"
check "29. test-stage multi-failure: b.test.sh ran (first failure)" \
  "$(log_has "$log" "CHECK test:scripts/b.test.sh")" "yes"
check "29. test-stage multi-failure: c.test.sh ALSO ran (stage runs to completion despite b already failing)" \
  "$(log_has "$log" "CHECK test:scripts/c.test.sh")" "yes"
check "29. test-stage multi-failure: d.test.sh ALSO ran" "$(log_has "$log" "CHECK test:scripts/d.test.sh")" "yes"
check "29. test-stage multi-failure: final line names the FIRST failure in fixed order (b)" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "test/" "scripts/b.test.sh")" "yes"
check "29. test-stage multi-failure: final line does not name scripts/c.test.sh" \
  "$(contains "$(final_line "$RUN_OUT")" "scripts/c.test.sh")" "no"
check "29. test-stage multi-failure: validate stage never ran (stage-level fail-fast still applies)" \
  "$(log_has "$log" "CHECK validate:")" "no"

# ===========================================================================
# 30. Same three properties as #29, for the VALIDATE stage: both failing
#     plugin targets run to completion, and the reported failure is the one
#     first in fixed (sorted) order -- alpha, not beta.
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
mkdir -p "$f/plugins/alpha" "$f/plugins/beta"
shim="$(mktemp -d)"; track_tmp "$shim"
write_claude_shim_multi "$shim" "$log" "$f" "alpha" "beta"
run_ci "$f" "$shim:$BASE_PATH"

check "30. validate-stage multi-failure: exit 1" "$RUN_EXIT" "1"
check "30. validate-stage multi-failure: marketplace.json checked" \
  "$(log_has "$log" "CHECK validate:.claude-plugin/marketplace.json")" "yes"
check "30. validate-stage multi-failure: plugins/alpha checked (first failure)" \
  "$(log_has "$log" "CHECK validate:plugins/alpha")" "yes"
check "30. validate-stage multi-failure: plugins/beta ALSO checked (stage runs to completion)" \
  "$(log_has "$log" "CHECK validate:plugins/beta")" "yes"
check "30. validate-stage multi-failure: final line names the FIRST failure in fixed order (alpha)" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "validate/" "plugins/alpha")" "yes"
check "30. validate-stage multi-failure: final line does not name plugins/beta" \
  "$(contains "$(final_line "$RUN_OUT")" "plugins/beta")" "no"

# ===========================================================================
# 31. Transcript identity: the strongest available assertion. Four
#     concurrent, all-green test-stage checks each emit a sizeable, exact
#     body to stdout; RUN_OUT must contain, byte for byte, the header plus
#     body of each in fixed order as ONE contiguous block per check, with no
#     other check's lines interleaved into it -- proving output order is
#     fixed and per-check output is buffered and emitted whole, even though
#     execution order (four checks genuinely running at once, --jobs 4) is
#     not. Contract: Outputs, Invariants ("A reader diffing two transcripts
#     sees no difference attributable to concurrency").
# ===========================================================================
f="$(new_repo)"
write_output_stub "$f/scripts/a.test.sh" "scripts/a.test.sh" 30 0
write_output_stub "$f/scripts/b.test.sh" "scripts/b.test.sh" 30 0
write_output_stub "$f/scripts/c.test.sh" "scripts/c.test.sh" 30 0
write_output_stub "$f/scripts/d.test.sh" "scripts/d.test.sh" 30 0
run_ci "$f" "$BASE_PATH" --test --jobs 4
# Command substitution unconditionally strips trailing newlines, so each
# $(build_expected_block ...) call loses the newline that separates it from
# the next block's header. Restore one explicitly at each boundary.
expected="$(build_expected_block "scripts/a.test.sh" 30)"$'\n'"$(build_expected_block "scripts/b.test.sh" 30)"$'\n'"$(build_expected_block "scripts/c.test.sh" 30)"$'\n'"$(build_expected_block "scripts/d.test.sh" 30)"

check "31. transcript identity: exit 0" "$RUN_EXIT" "0"
check "31. transcript identity: exact contiguous a+b+c+d block, in fixed order, no interleaving" \
  "$(contains "$RUN_OUT" "$expected")" "yes"

# ===========================================================================
# 32. No external scheduler: a run that exercises lint, test, and validate
#     never invokes xargs, parallel, or sem, even when shims for all three
#     are placed ahead of everything else on PATH. Mechanical, dependency-
#     free spawn-count check (no strace). Contract: Invariants ("implemented
#     with bash job control and wait, NOT with xargs -P, GNU parallel, or
#     any other external scheduler").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
sched_log="$(mktemp)"; track_tmp "$sched_log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
write_check_stub "$f/scripts/z.test.sh" "test:scripts/z.test.sh" "$log" "$f" 0
shim="$(mktemp -d)"; track_tmp "$shim"
write_claude_shim "$shim" "$log" "$f" ""
sched_shim="$(mktemp -d)"; track_tmp "$sched_shim"
write_scheduler_shim "$sched_shim" "$sched_log" xargs
write_scheduler_shim "$sched_shim" "$sched_log" parallel
write_scheduler_shim "$sched_shim" "$sched_log" sem
run_ci "$f" "$sched_shim:$shim:$BASE_PATH"

check "32. no external scheduler: exit 0" "$RUN_EXIT" "0"
check "32. no external scheduler: xargs never invoked" "$(log_has "$sched_log" "CALLED xargs")" "no"
check "32. no external scheduler: parallel never invoked" "$(log_has "$sched_log" "CALLED parallel")" "no"
check "32. no external scheduler: sem never invoked" "$(log_has "$sched_log" "CALLED sem")" "no"

# ===========================================================================
# 33. --jobs <n> caps concurrency: with --jobs 2 and 4 blocking checks in
#     the test stage, at no point do more than 2 run at once, and all 4
#     eventually complete. See the barrier apparatus above for why this
#     needs no sleep and asserts no wall-clock duration.
# ===========================================================================
f="$(new_repo)"
check "33. --jobs 2 caps concurrency (never exceeds 2, all 4 complete)" \
  "$(assert_jobs_cap "$f" "$BASE_PATH" 2 --test --jobs 2 -- a b c d)" "yes"

# ===========================================================================
# 34. --jobs default reads the machine's core count via nproc: with a fake
#     nproc reporting "3" ahead of everything else on PATH and no --jobs
#     flag, the cap defaults to 3. Contract: Inputs ("Defaults to the
#     machine's core count as reported by nproc").
# ===========================================================================
f="$(new_repo)"
nproc_shim="$(mktemp -d)"; track_tmp "$nproc_shim"
printf '#!/bin/bash\necho 3\n' > "$nproc_shim/nproc"
chmod +x "$nproc_shim/nproc"
check "34. --jobs default reads nproc (fake nproc=3 caps at 3, no --jobs given)" \
  "$(assert_jobs_cap "$f" "$nproc_shim:$BASE_PATH" 3 --test -- a b c d e)" "yes"

# ===========================================================================
# 35. --jobs default falls back to 4 when nproc is unavailable, simulated
#     via a PATH shim rather than uninstalling anything: PATH is replaced
#     with a minimal directory of symlinks to exactly what ci.sh and these
#     stubs need (bash, git, find, sort, rm) with no nproc anywhere in it --
#     nproc's real binary is never touched, it is simply unreachable via
#     this PATH. Contract: Inputs ("falling back to 4 when nproc is
#     unavailable").
# ===========================================================================
f="$(new_repo)"
noproc_shim="$(mktemp -d)"; track_tmp "$noproc_shim"
for b in bash git find sort rm; do
  p="$(type -P "$b" 2>/dev/null)"
  [ -n "$p" ] && ln -s "$p" "$noproc_shim/$b"
done
check "35. --jobs default falls back to 4 when nproc is unavailable (caps at 4, all 5 complete)" \
  "$(assert_jobs_cap "$f" "$noproc_shim" 4 --test -- a b c d e)" "yes"

# ===========================================================================
# 36. --jobs 1 caps concurrency at one but is NOT the old sequential
#     short-circuit: a failing check part-way through the stage must not
#     stop later checks from running. --jobs 1 only removes the race, it
#     does not restore intra-stage fail-fast. This is the case an
#     implementer is most likely to get wrong by treating --jobs 1 as "the
#     old sequential path" wholesale. Since jobs=1 leaves no concurrency to
#     race, execution order is legitimately deterministic here too, so it
#     is asserted directly via the log (as in #23). Contract: Behavior
#     ("every check in the stage runs to completion even when an earlier
#     one fails"), Inputs ("--jobs 1 forces fully sequential execution").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
write_check_stub "$f/scripts/b.test.sh" "test:scripts/b.test.sh" "$log" "$f" 1
write_check_stub "$f/scripts/c.test.sh" "test:scripts/c.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --test --jobs 1

check "36. --jobs 1 still runs to completion: exit 1" "$RUN_EXIT" "1"
check "36. --jobs 1 still runs to completion: a.test.sh ran" \
  "$(log_has "$log" "CHECK test:scripts/a.test.sh")" "yes"
check "36. --jobs 1 still runs to completion: b.test.sh ran (the failure)" \
  "$(log_has "$log" "CHECK test:scripts/b.test.sh")" "yes"
check "36. --jobs 1 still runs to completion: c.test.sh ALSO ran (not the old short-circuit)" \
  "$(log_has "$log" "CHECK test:scripts/c.test.sh")" "yes"
check "36. --jobs 1 still runs to completion: order is a, then b, then c" \
  "$(order_ok "$log" "CHECK test:scripts/a.test.sh" "CHECK test:scripts/b.test.sh")" "yes"
check "36. --jobs 1 still runs to completion: final line names the failure (b)" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "test/" "scripts/b.test.sh")" "yes"

# ===========================================================================
# 37. --jobs with no value at all (the flag is the last argument) is a
#     usage error, exit 2 -- the same bucket as a non-integer or <1 value,
#     not a `set -u` crash. A parser that shifts and reads $1 without first
#     checking $# aborts on an unbound variable, which exits 1 (or 127),
#     not 2, and prints a bash diagnostic rather than a usage message; the
#     exit-code-2 assertion alone already fails such an implementation, and
#     the explicit "not unbound variable" check below documents why.
#     Contract: Inputs ("A non-integer or <1 value is a usage error, exit
#     2") extended to "no value" by the same reasoning; ruled explicitly by
#     the orchestrator since the docblock as scaffolded doesn't spell out
#     the missing-argument case.
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --jobs

check "37. --jobs with missing value: exit 2 (not a set -u crash)" "$RUN_EXIT" "2"
check "37. --jobs with missing value: stderr non-empty (usage message)" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
check "37. --jobs with missing value: stderr is not a bash unbound-variable diagnostic" \
  "$(contains "$RUN_ERR" "unbound variable")" "no"
check "37. --jobs with missing value: nothing invoked" "$([ -s "$log" ] && echo no || echo yes)" "yes"

# ===========================================================================
# 38. --jobs immediately followed by another flag: the next token must not
#     be silently consumed as --jobs's value. Same usage-error bucket as
#     #37. Contract: same ruling as #37.
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
run_ci "$f" "$BASE_PATH" --jobs --test

check "38. --jobs followed by another flag: exit 2" "$RUN_EXIT" "2"
check "38. --jobs followed by another flag: stderr non-empty (usage message)" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
check "38. --jobs followed by another flag: stderr is not a bash unbound-variable diagnostic" \
  "$(contains "$RUN_ERR" "unbound variable")" "no"
check "38. --jobs followed by another flag: nothing invoked" "$([ -s "$log" ] && echo no || echo yes)" "yes"

# ===========================================================================
# B10 (ci-scheduler-slot-fill): a free concurrency slot must be filled as
# soon as ANY in-flight check completes, never only when the OLDEST
# launched check completes. No test above (1-38) can tell the two
# schedulers apart -- B03's cap, transcript, and ordering guarantees all
# hold identically whether the scheduler waits on the oldest pid or on
# whichever finishes first, and 1-38 all pass against either. These two
# tests are causal, not timing-based: they never assert a duration, only
# that specific events happen (or fail to happen) in a specific order,
# using durable marker files and blocking release gates instead of sleeps.
# ===========================================================================

# ===========================================================================
# 39. The definitive distinguishing test. --jobs 2, three test checks in
#     fixed order a, b, c. a blocks on a release gate and is held blocked
#     for the whole test; b exits 0 the instant it starts; c creates a
#     marker file the instant it starts, then exits 0. The window (cap 2)
#     fills with a+b; b finishes almost immediately, freeing one slot while
#     a is still running and NOT yet released.
#       - Fill-on-any (correct): the freed slot is taken by c, so c's
#         marker appears WHILE a is still blocked.
#       - Oldest-first (current bug): run_concurrent's `wait "${pids[0]}"`
#         blocks specifically on a (the oldest of the two in-flight pids),
#         so c is never even launched until a is released -- the marker
#         cannot appear first, no matter how long the test waits.
#     wait_for_count's deadline below is a bounded hang guard only (25s,
#     generous), not the assertion under test: whether the marker appears
#     AT ALL before a is released is the causal fact being checked, not how
#     fast. a is released unconditionally right after the poll, outside any
#     conditional, so a failing assertion here can never leave a wedged
#     background ci.sh process behind.
#     Contract: Invariants (B10: "a free concurrency slot is filled as soon
#     as ANY in-flight check completes -- never only when the OLDEST
#     launched check completes").
# ===========================================================================
f="$(new_repo)"
rundir="$(mktemp -d)"; track_tmp "$rundir"
gate="$(mktemp -u)"; mkfifo "$gate"; track_tmp "$gate"
write_barrier_stub "$f/scripts/a.test.sh" "a" "$rundir" "$gate" 0
write_immediate_stub "$f/scripts/b.test.sh" 0
write_marker_stub "$f/scripts/c.test.sh" "$rundir/marker-c" 0

exec 8<>"$gate"
run_ci_bg "$f" "$BASE_PATH" --test --jobs 2

marker_seen="$(wait_for_count "$rundir" "marker-c" 1 "$RUN_BG_PID" 25)"
# Unconditional release of a: fed here regardless of the outcome above, so
# a stuck oldest-first run (marker never appeared) still finishes rather
# than leaving a wedged background process.
printf 'go\n' >&8
exec 8>&-
wait_bg

check "39. B10 fill-on-any: c's marker appears while a is still blocked (free slot filled by ANY completion, not only the oldest)" \
  "$marker_seen" "yes"
check "39. B10 fill-on-any: run still completes all checks once a is released, exit 0" \
  "$RUN_EXIT" "0"

# ===========================================================================
# 40. The cap boundary that 33/34/35 cannot reach. Those three all gate
#     EVERY check in the stage on one shared release fed to all of them at
#     once, so their window is always either "full, about to be released in
#     lockstep" or "empty" -- it never holds one long-running check while a
#     SECOND, unrelated check completes and is replaced by a THIRD next to
#     the still-running first one. That mixed-age window is exactly what
#     fill-on-any opens up, and exactly where an off-by-one in a
#     from-scratch scheduler rewrite would first show a cap violation.
#     Construction: --jobs 2, three test checks: a (held blocked the whole
#     test) and b, c (sharing one release gate, so at most one of them is
#     ever a live process at a time -- the other is still queued, not yet
#     forked, under a correct scheduler). The window fills with a+b;
#     releasing b must free its slot for c WHILE a is still blocked, and
#     the running-check count sampled at that exact moment must never
#     exceed the cap of 2.
#     Contract: Invariants (B10, restated) and (unchanged: "the cap itself
#     ... [tests] must pass untouched" -- this is an ADDITIONAL cap sample
#     at a boundary 33/34/35 structurally cannot produce, not a replacement
#     for them).
# ===========================================================================
f="$(new_repo)"
rundir="$(mktemp -d)"; track_tmp "$rundir"
gate_a="$(mktemp -u)"; mkfifo "$gate_a"; track_tmp "$gate_a"
gate_bc="$(mktemp -u)"; mkfifo "$gate_bc"; track_tmp "$gate_bc"
write_barrier_stub "$f/scripts/a.test.sh" "a" "$rundir" "$gate_a" 0
write_barrier_stub "$f/scripts/b.test.sh" "b" "$rundir" "$gate_bc" 0
write_barrier_stub "$f/scripts/c.test.sh" "c" "$rundir" "$gate_bc" 0

exec 8<>"$gate_a"
exec 9<>"$gate_bc"
run_ci_bg "$f" "$BASE_PATH" --test --jobs 2

filled="$(wait_for_count "$rundir" "running-*" 2 "$RUN_BG_PID" 20)"
initial_count="$(count_glob "$rundir" "running-*")"

printf 'go\n' >&9
refilled="$(wait_for_count "$rundir" "running-c" 1 "$RUN_BG_PID" 20)"
count_at_refill="$(count_glob "$rundir" "running-*")"

printf 'go\n' >&9
# Unconditional release of a: fed here regardless of the outcome above, so
# a stuck oldest-first run (c never admitted) still finishes rather than
# leaving a wedged background process.
printf 'go\n' >&8
exec 8>&- 9>&-
wait_bg

check "40. B10 cap boundary: initial window fills at exactly 2 (a+b)" "$filled" "yes"
check "40. B10 cap boundary: initial running count is 2, not more" "$initial_count" "2"
check "40. B10 cap boundary: c is admitted into the freed slot while a is still blocked" \
  "$refilled" "yes"
check "40. B10 cap boundary: running count at refill is still capped at 2 (a+c), never 3" \
  "$count_at_refill" "2"
check "40. B10 cap boundary: run completes once a is released, exit 0" "$RUN_EXIT" "0"

# ===========================================================================
# 41. Corrective (brief 02): forces completion order to be the INVERSE of
#     fixed order among the two failing checks in a stage, and asserts the
#     reported failure is still the one first in FIXED order (b), never the
#     one that completed first in real time (c). --jobs 4 puts all four
#     checks in flight together: a and d succeed immediately; c is the
#     SECOND failing check in fixed order but the FIRST to complete
#     (immediate exit 1); b is the FIRST failing check in fixed order but
#     the LAST to complete (held on a release gate until this script
#     explicitly frees it, well after a/c/d have all finished).
#
#     Tests 29/30 already assert this invariant, but -- as test 29's own
#     comment concedes -- under B03's oldest-pid scheduler, completion order
#     tracks launch order closely enough that 29/30 pass whether an
#     implementation selects the failure by fixed order or by completion
#     order; the two are not distinguished by either test. B10's fill-on-any
#     scheduler decouples completion order from launch order by design,
#     which is exactly what makes "report whichever failure was reaped
#     first" an easy mistake once the scheduler is rewritten. This test
#     arms a regression guard for that mistake before the rewrite happens.
#
#     Causal, not timing-based: a, c, and d are confirmed complete (via
#     durable marker files) and b is confirmed STILL in flight (via its
#     barrier stub's running-b marker) before b is ever released -- never
#     via a sleep or an assumed race outcome. b is released unconditionally
#     right after the poll, outside any conditional, so a failing assertion
#     here can never leave a wedged background ci.sh process behind.
#
#     This test PASSES against the current scripts/ci.sh: B03 already
#     records exit codes by fixed array index and scans them in fixed order
#     once every check has completed, regardless of reap/completion order.
#     Its job is to be armed now, not to specify new behaviour. Contract:
#     Behavior ("every check in the stage runs to completion... reports the
#     FIRST failure in fixed output order"), same as #29/#30, exercised at
#     the completion-order boundary B10 newly puts at risk.
# ===========================================================================
f="$(new_repo)"
rundir="$(mktemp -d)"; track_tmp "$rundir"
gate="$(mktemp -u)"; mkfifo "$gate"; track_tmp "$gate"
write_marker_stub "$f/scripts/a.test.sh" "$rundir/marker-a" 0
write_barrier_stub "$f/scripts/b.test.sh" "b" "$rundir" "$gate" 1
write_marker_stub "$f/scripts/c.test.sh" "$rundir/marker-c" 1
write_marker_stub "$f/scripts/d.test.sh" "$rundir/marker-d" 0

exec 8<>"$gate"
run_ci_bg "$f" "$BASE_PATH" --test --jobs 4

# a, c, d (the three non-blocked checks) must all complete -- and b must
# still be in flight, unreaped -- before b is released, so completion order
# is forced to be c (and a, d), then b: the exact inverse of fixed order
# among the two failures (b, c).
others_done="$(wait_for_count "$rundir" "marker-*" 3 "$RUN_BG_PID" 25)"
# Contract: B11 deterministic in-flight sampling
# Behavior: before sampling b_still_running, wait (bounded, via this
#   suite's existing busy-wait helper and the same generous 25s budget)
#   for b's running-b marker to EXIST, so "b was still in flight" can
#   never read "no" merely because b's stub had not yet STARTED under
#   load. Waiting for the marker is sound: the barrier stub removes
#   running-b only after reading the gate fifo, and the gate is not fed
#   until after this sample, so once the marker appears b is provably
#   in flight at sampling time.
# Outputs: the same five section-41 checks, same labels, same semantics.
# Errors: b never starting within the budget -> the wait expires, the
#   in-flight check fails as today; no new failure mode and no hang (the
#   gate release below stays unconditional and wait_bg still runs).
# Invariants: the gate is released unconditionally right after sampling,
#   outside any conditional; no sleep-based timing assumption is
#   introduced; every other section of this suite is untouched; the suite
#   passes against the current scripts/ci.sh.
# Edge cases: b's stub scheduled only after a/c/d all complete (the
#   observed load flake) -> now passes; a wedged b (never starts) ->
#   bounded wait expires, the check fails, the suite still terminates.
b_still_running="$(wait_for_count "$rundir" "running-b" 1 "$RUN_BG_PID" 25)"
# Unconditional release of b: fed here regardless of the outcome above, so
# a truly wedged implementation (a/c/d never reaped) still finishes rather
# than leaving a wedged background process.
printf 'go\n' >&8
exec 8>&-
wait_bg

check "41. B10 completion-order inversion: a, c, d all completed before b was released" \
  "$others_done" "yes"
check "41. B10 completion-order inversion: b was still in flight (unreaped) at that point" \
  "$b_still_running" "yes"
check "41. B10 completion-order inversion: exit 1" "$RUN_EXIT" "1"
check "41. B10 completion-order inversion: all four checks ran (stage runs to completion)" \
  "$([ -e "$rundir/marker-a" ] && [ -e "$rundir/marker-c" ] && [ -e "$rundir/marker-d" ] && [ -e "$rundir/done-b" ] && echo yes || echo no)" "yes"
check "41. B10 completion-order inversion: final line names the FIRST failure in FIXED order (b), not the first to complete (c)" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "test/" "scripts/b.test.sh")" "yes"
check "41. B10 completion-order inversion: final line does not name scripts/c.test.sh" \
  "$(contains "$(final_line "$RUN_OUT")" "scripts/c.test.sh")" "no"

# ===========================================================================
# B07 (shellcheck-lint): the lint stage gains a SEVENTH check named
# `shellcheck-lint`, appended after architecture-lint. Test 1 above covers it
# on the green path (it runs, after architecture-lint, before the test
# stage) and tests 3/18 count the stage at 7; this block covers the failure
# path, which test 21 no longer covers. Test 21 was written for "the LAST
# check in the lint stage fails" -- with architecture-lint sixth of seven it
# now only exercises "a MIDDLE check fails", so the end-of-stage failure
# boundary (nothing left to fail-fast past, yet the run must still stop
# before the test stage) needs its own fixture.
# ===========================================================================

# ===========================================================================
# 42. shellcheck-lint fails as the lint stage's seventh and last check: the
#     six preceding lint checks all ran, shellcheck-lint ran after
#     architecture-lint and failed, the run is reported as "CI FAIL:
#     lint/shellcheck-lint" with exit 1, and fail-fast still stops the run
#     before the test stage starts. Contract: Behavior (lint check list,
#     "bash scripts/shellcheck-lint.sh (B07)" last; "Stage-level fail-fast:
#     a failing STAGE stops the run"), Outputs (final "CI FAIL:
#     <stage>/<check>"), Errors (exit 1 on check failure).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/shellcheck-lint.sh" "$NAME_SC" "$log" "$f" 1
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "42. shellcheck-lint fails: exit 1" "$RUN_EXIT" "1"
check "42. shellcheck-lint fails: architecture-lint ran" "$(log_has "$log" "CHECK $NAME_AL")" "yes"
check "42. shellcheck-lint fails: shellcheck-lint ran" "$(log_has "$log" "CHECK $NAME_SC")" "yes"
check "42. shellcheck-lint fails: architecture-lint before shellcheck-lint" \
  "$(order_ok "$log" "CHECK $NAME_AL" "CHECK $NAME_SC")" "yes"
check "42. shellcheck-lint fails: all 7 lint checks ran before the stage failed" \
  "$(log_count "$log" "CHECK lint:")" "7"
check "42. shellcheck-lint fails: test stage never ran (fail-fast)" \
  "$(log_has "$log" "CHECK test:")" "no"
check "42. shellcheck-lint fails: final line CI FAIL: lint/shellcheck-lint" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "lint/" "shellcheck-lint")" "yes"

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
