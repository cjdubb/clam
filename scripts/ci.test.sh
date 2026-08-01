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
# Real claude/gh locations, so "absent" can strip exactly those dirs from
# PATH while leaving git/bash/jq/coreutils reachable — never falls back to
# an ambient PATH that could reach the real claude/gh CLIs.
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

BASE_PATH="$(path_without "$REAL_CLAUDE_DIR" "$REAL_GH_DIR")"

# ---------------------------------------------------------------------------
# Fixture repo builder: git-inits, one commit, GitHub origin remote,
# scripts/ plugins/ .claude-plugin/ dirs pre-created.
# ---------------------------------------------------------------------------
new_repo() { # -> prints repo root path
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
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
  ( cd "$root" && find . -type f -exec sha256sum {} + ) | sort
}

# Namespaced check names, shared across cases.
NAME_MP="lint:marketplace-lint"
NAME_EX="lint:executable-lint"
NAME_RL="lint:readme-lint"
NAME_VB="lint:version-bump-lint"
NAME_ITL="lint:issue-template-lint"
NAME_AL="lint:architecture-lint"

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
check "1. lint order: architecture-lint before test stage" \
  "$(order_ok "$log" "CHECK $NAME_AL" "CHECK test:scripts/a.test.sh")" "yes"
check "1. lint checks all ran from repo root (no CWD_BAD)" \
  "$(log_has "$log" "CWD_BAD")" "no"
check "1. test order: repo-level a before repo-level z" \
  "$(order_ok "$log" "CHECK test:scripts/a.test.sh" "CHECK test:scripts/z.test.sh")" "yes"
check "1. test order: repo-level z before plugins/alpha/lib" \
  "$(order_ok "$log" "CHECK test:scripts/z.test.sh" "CHECK test:plugins/alpha/lib/m.test.sh")" "yes"
check "1. test order: alpha/lib before alpha/scripts (lexicographic)" \
  "$(order_ok "$log" "CHECK test:plugins/alpha/lib/m.test.sh" "CHECK test:plugins/alpha/scripts/n.test.sh")" "yes"
check "1. test order: alpha/scripts before zeta/lib (lexicographic)" \
  "$(order_ok "$log" "CHECK test:plugins/alpha/scripts/n.test.sh" "CHECK test:plugins/zeta/lib/k.test.sh")" "yes"
check "1. test order: zeta/lib before zeta/scripts (lexicographic)" \
  "$(order_ok "$log" "CHECK test:plugins/zeta/lib/k.test.sh" "CHECK test:plugins/zeta/scripts/q.test.sh")" "yes"
check "1. validate order: marketplace.json before plugins/alpha" \
  "$(order_ok "$log" "CHECK validate:.claude-plugin/marketplace.json" "CHECK validate:plugins/alpha")" "yes"
check "1. validate order: marketplace.json before plugins/zeta" \
  "$(order_ok "$log" "CHECK validate:.claude-plugin/marketplace.json" "CHECK validate:plugins/zeta")" "yes"

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
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "2. fail-fast lint: exit 1" "$RUN_EXIT" "1"
check "2. fail-fast lint: marketplace-lint ran" "$(log_has "$log" "CHECK $NAME_MP")" "yes"
check "2. fail-fast lint: executable-lint ran" "$(log_has "$log" "CHECK $NAME_EX")" "yes"
check "2. fail-fast lint: readme-lint never ran" "$(log_has "$log" "CHECK $NAME_RL")" "no"
check "2. fail-fast lint: version-bump-lint never ran" "$(log_has "$log" "CHECK $NAME_VB")" "no"
check "2. fail-fast lint: issue-template-lint never ran" "$(log_has "$log" "CHECK $NAME_ITL")" "no"
check "2. fail-fast lint: architecture-lint never ran" "$(log_has "$log" "CHECK $NAME_AL")" "no"
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
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 0
mkdir -p "$f/plugins/alpha"
run_ci "$f" "$BASE_PATH" --lint

check "3. --lint solo: exit 0" "$RUN_EXIT" "0"
check "3. --lint solo: final line CI PASS" "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"
check "3. --lint solo: all 6 lint checks ran" "$(log_count "$log" "CHECK lint:")" "6"
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

# ===========================================================================
# 17. A test check exiting 2 is likewise CI FAIL, exit 1; fail-fast stops
#     later test checks and validate. Contract: Errors (same clause,
#     explicitly covers "lint/test").
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_check_stub "$f/scripts/marketplace-lint.sh" "$NAME_MP" "$log" "$f" 0
write_check_stub "$f/scripts/executable-lint.sh" "$NAME_EX" "$log" "$f" 0
write_check_stub "$f/scripts/readme-lint.sh" "$NAME_RL" "$log" "$f" 0
write_check_stub "$f/scripts/version-bump-lint.sh" "$NAME_VB" "$log" "$f" 0
write_check_stub "$f/scripts/issue-template-lint.sh" "$NAME_ITL" "$log" "$f" 0
write_check_stub "$f/scripts/architecture-lint.sh" "$NAME_AL" "$log" "$f" 0
write_check_stub "$f/scripts/a.test.sh" "test:scripts/a.test.sh" "$log" "$f" 2
write_check_stub "$f/scripts/z.test.sh" "test:scripts/z.test.sh" "$log" "$f" 0
run_ci "$f" "$BASE_PATH"

check "17. test check exits 2: exit 1 (not 2)" "$RUN_EXIT" "1"
check "17. test check exits 2: final line names test/a.test.sh" \
  "$(line_has_all "$(final_line "$RUN_OUT")" "CI FAIL:" "test/" "a.test.sh")" "yes"
check "17. test check exits 2: z.test.sh never ran (fail-fast)" \
  "$(log_has "$log" "CHECK test:scripts/z.test.sh")" "no"
check "17. test check exits 2: validate never ran (fail-fast)" \
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
run_ci "$f/scripts" "$BASE_PATH"

check "18. cwd-independence: exit 0 from nested subdir" "$RUN_EXIT" "0"
check "18. cwd-independence: final line CI PASS" "$(contains "$(final_line "$RUN_OUT")" "CI PASS")" "yes"
check "18. cwd-independence: all lint checks ran from repo root" \
  "$(log_has "$log" "CWD_BAD")" "no"
check "18. cwd-independence: all 6 lint checks ran" "$(log_count "$log" "CHECK lint:")" "6"

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
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
