#!/usr/bin/env bash
# setup-hooks.test.sh — contract tests for scripts/setup-hooks.sh (B03b
# setup-hooks, plan 001-pseudo-ci).
#
# Black-box only: builds fixture git repos under mktemp -d (clam-like: a
# .claude-plugin/marketplace.json with "name": "clam", detected via jq; and
# non-clam variants), then invokes the REAL scripts/setup-hooks.sh
# (resolved via BASH_SOURCE from this repo) with cwd inside the fixture.
# Every invocation runs under an isolated, disposable HOME (a fresh
# mktemp -d per call) so the tests can never touch the real developer's
# ~/.gitconfig, and so "never touches user/system git config" is checkable
# directly by inspecting that HOME's .gitconfig afterward. jq presence is
# controlled via PATH, following the same shim/strip pattern as
# scripts/ci.test.sh: "absent" strips jq's real directory out of PATH
# entirely (never falls back to an ambient PATH).
#
# State assertions use `git config --list --local` snapshots taken before
# and after each run; the contract promises exactly one key
# (core.hooksPath, normalized by git to "hookspath") is ever written, so
# the diff between snapshots must never contain a non-hookspath line.
#
# Mirrors the PASS/FAIL harness style of scripts/readme-lint.test.sh and
# the record-invocation/PATH-shim style of scripts/ci.test.sh.
#
# Run: bash scripts/setup-hooks.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/setup-hooks.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: script under test not found at $SCRIPT" >&2
  exit 1
fi

# shellcheck source=lib/test-portability.sh
# shellcheck disable=SC1091  # resolved at runtime via $SCRIPT_DIR
. "$SCRIPT_DIR/lib/test-portability.sh"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# Cleanup registry for mktemp fixture trees/homes (command substitution
# forks a subshell, so a file-based manifest is needed to survive it).
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
# `jq`-missing PATH shim: allowlist every executable on the caller's real
# PATH except jq, symlinked into a fresh dir (git and bash -- both needed to
# invoke the script under test -- stay reachable; only jq disappears).
# A blocklist that merely strips jq's own directory from PATH is not enough
# on usrmerge systems, where /bin is a symlink to /usr/bin and stays on
# PATH -- /bin/jq would still be reachable there. Farming only /usr/bin is
# equally wrong the other way on macOS, where /bin/bash is NOT under
# /usr/bin and the shim would yield exit 127 instead of the contract's
# exit 2; tp_shim_path walks the whole real PATH, so both platforms keep a
# usable bash/git. Mirrors build_path_without in
# scripts/version-bump-lint.test.sh.
# ---------------------------------------------------------------------------
build_path_without() { # cmd -> prints new PATH dir
  local cmd="$1" out
  out="$(mktemp -d)"
  track_tmp "$out"
  tp_shim_path "$out" --remove "$cmd" >/dev/null || return 1
  printf '%s' "$out"
}

FULL_PATH="$PATH"
NOJQ_PATH="$(build_path_without jq)"

# ---------------------------------------------------------------------------
# Fixture repo builders.
# ---------------------------------------------------------------------------
CLAM_MARKETPLACE='{"name": "clam", "description": "fixture", "owner": {"name": "Test", "email": "test@example.com"}, "plugins": []}'

new_clam_repo() { # [--no-hooks-dir] -> prints repo root path
  local nohooks=0
  [ "${1:-}" = "--no-hooks-dir" ] && nohooks=1
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    mkdir -p .claude-plugin scripts
    printf '%s\n' "$CLAM_MARKETPLACE" > .claude-plugin/marketplace.json
    if [ "$nohooks" -eq 0 ]; then
      mkdir -p scripts/githooks
      printf '#!/bin/bash\nexit 0\n' > scripts/githooks/pre-push
      chmod +x scripts/githooks/pre-push
    fi
    printf '# fixture\n' > README.md
    git add -A
    git commit -q -m init
  ) >/dev/null
  printf '%s' "$d"
}

new_repo_no_marker() { # -> git repo with no .claude-plugin dir at all
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    mkdir -p scripts/githooks
    printf '# fixture\n' > README.md
    git add -A
    git commit -q -m init
  ) >/dev/null
  printf '%s' "$d"
}

new_repo_wrong_name() { # -> git repo with marketplace.json but name != clam
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    mkdir -p .claude-plugin scripts/githooks
    printf '%s\n' '{"name": "not-clam"}' > .claude-plugin/marketplace.json
    printf '# fixture\n' > README.md
    git add -A
    git commit -q -m init
  ) >/dev/null
  printf '%s' "$d"
}

new_repo_missing_name_key() { # -> marketplace.json present but no "name" key
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    mkdir -p .claude-plugin scripts/githooks
    printf '%s\n' '{"description": "no name field"}' > .claude-plugin/marketplace.json
    printf '# fixture\n' > README.md
    git add -A
    git commit -q -m init
  ) >/dev/null
  printf '%s' "$d"
}

new_plain_dir() { # -> a directory that is not a git repo at all
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  printf '%s' "$d"
}

# ---------------------------------------------------------------------------
# Invocation helper. Runs under an isolated, disposable HOME every time
# (never the real developer HOME), so "never touches user/system config"
# is directly checkable via LAST_HOME afterward.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
LAST_HOME=""

run_setup() { # <cwd> <path_value> <arg>...
  local cwd="$1" pathval="$2"; shift 2
  local out err home
  out="$(mktemp)"; err="$(mktemp)"
  home="$(mktemp -d)"; track_tmp "$home"
  LAST_HOME="$home"
  ( cd "$cwd" && HOME="$home" PATH="$pathval" bash "$SCRIPT" "$@" >"$out" 2>"$err" )
  RUN_EXIT=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  rm -f "$out" "$err"
}

# ---------------------------------------------------------------------------
# Assertion / config helpers.
# ---------------------------------------------------------------------------
contains() { # text needle -> yes/no
  case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac
}

anywhere() { # out err needle -> yes/no (stream-agnostic; contract doesn't
             # pin a stream for this message)
  case "$1" in *"$3"*) echo yes; return ;; esac
  case "$2" in *"$3"*) echo yes; return ;; esac
  echo no
}

config_snapshot() { # repo_dir -> sorted `git config --list --local` lines
  git -C "$1" config --list --local 2>/dev/null | sort
}

config_get() { # repo_dir key -> value or empty
  git -C "$1" config --get "$2" 2>/dev/null || true
}

config_untouched() { # before after -> yes/no
  [ "$1" = "$2" ] && echo yes || echo no
}

config_only_hookspath_changed() { # before after -> yes/no
  local d
  d="$(diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | grep -E '^[<>]' | grep -vi hookspath || true)"
  [ -z "$d" ] && echo yes || echo no
}

global_config_untouched() { # home_dir -> yes/no (no hookspath ever landed globally)
  local gc="$1/.gitconfig"
  [ -f "$gc" ] || { echo yes; return; }
  grep -qi hookspath "$gc" && echo no || echo yes
}

# ===========================================================================
# 1. Fresh install on a conforming clam repo: exact enable message, exit 0,
#    core.hooksPath set to the RELATIVE literal "scripts/githooks", only
#    that key written (repo-scope snapshot diff), global config untouched.
#    Contract: Behavior, Outputs, Invariants.
# ===========================================================================
f="$(new_clam_repo)"
before="$(config_snapshot "$f")"
run_setup "$f" "$FULL_PATH"
after="$(config_snapshot "$f")"

check "1. fresh install: exit 0" "$RUN_EXIT" "0"
check "1. fresh install: exact enable message" \
  "$(anywhere "$RUN_OUT" "$RUN_ERR" "hooks enabled: core.hooksPath = scripts/githooks (all worktrees of this repo)")" "yes"
check "1. fresh install: config value is exactly the relative literal" \
  "$(config_get "$f" core.hooksPath)" "scripts/githooks"
check "1. fresh install: only core.hooksPath changed" \
  "$(config_only_hookspath_changed "$before" "$after")" "yes"
check "1. fresh install: global config (HOME) untouched" \
  "$(global_config_untouched "$LAST_HOME")" "yes"

# ===========================================================================
# 2. Idempotent re-run: second run reports "already enabled", exit 0,
#    value unchanged, no further config writes. Contract: Outputs,
#    Invariants (idempotent).
# ===========================================================================
f="$(new_clam_repo)"
run_setup "$f" "$FULL_PATH"
after_first="$(config_snapshot "$f")"
run_setup "$f" "$FULL_PATH"
after_second="$(config_snapshot "$f")"

check "2. idempotent re-run: exit 0" "$RUN_EXIT" "0"
check "2. idempotent re-run: exact already-enabled message" \
  "$(anywhere "$RUN_OUT" "$RUN_ERR" "hooks already enabled")" "yes"
check "2. idempotent re-run: value still exactly scripts/githooks" \
  "$(config_get "$f" core.hooksPath)" "scripts/githooks"
check "2. idempotent re-run: no further config changes" \
  "$(config_untouched "$after_first" "$after_second")" "yes"

# ===========================================================================
# 3. Conflict: core.hooksPath already set to a DIFFERENT value. Refuses,
#    exit 1, config untouched, current value surfaced in output. Contract:
#    Errors (never clobber silently).
# ===========================================================================
f="$(new_clam_repo)"
git -C "$f" config core.hooksPath custom-hooks
before="$(config_snapshot "$f")"
run_setup "$f" "$FULL_PATH"
after="$(config_snapshot "$f")"

check "3. conflict: exit 1" "$RUN_EXIT" "1"
check "3. conflict: config untouched" "$(config_untouched "$before" "$after")" "yes"
check "3. conflict: value still custom-hooks" "$(config_get "$f" core.hooksPath)" "custom-hooks"
check "3. conflict: current value shown in output" \
  "$(anywhere "$RUN_OUT" "$RUN_ERR" "custom-hooks")" "yes"

# ===========================================================================
# 4. --remove unsets a value THIS tool installed: exact "hooks disabled"
#    message, exit 0, key removed. Contract: Behavior, Outputs.
# ===========================================================================
f="$(new_clam_repo)"
run_setup "$f" "$FULL_PATH"
run_setup "$f" "$FULL_PATH" --remove

check "4. remove: exit 0" "$RUN_EXIT" "0"
check "4. remove: exact disabled message" \
  "$(anywhere "$RUN_OUT" "$RUN_ERR" "hooks disabled")" "yes"
check "4. remove: core.hooksPath no longer set" "$(config_get "$f" core.hooksPath)" ""

# ===========================================================================
# 5. --remove when never installed: idempotent no-op, exact "were not
#    enabled" message, exit 0, config untouched. Contract: Outputs
#    ("idempotent both ways").
# ===========================================================================
f="$(new_clam_repo)"
before="$(config_snapshot "$f")"
run_setup "$f" "$FULL_PATH" --remove
after="$(config_snapshot "$f")"

check "5. remove-when-unset: exit 0" "$RUN_EXIT" "0"
check "5. remove-when-unset: exact were-not-enabled message" \
  "$(anywhere "$RUN_OUT" "$RUN_ERR" "hooks were not enabled")" "yes"
check "5. remove-when-unset: config untouched" "$(config_untouched "$before" "$after")" "yes"

# ===========================================================================
# 6. --remove refuses a FOREIGN value (something this tool did not
#    install): exit 1, refusal, config untouched. Contract: Errors ("only
#    remove what we installed").
# ===========================================================================
f="$(new_clam_repo)"
git -C "$f" config core.hooksPath other-path
before="$(config_snapshot "$f")"
run_setup "$f" "$FULL_PATH" --remove
after="$(config_snapshot "$f")"

check "6. remove-foreign: exit 1" "$RUN_EXIT" "1"
check "6. remove-foreign: config untouched" "$(config_untouched "$before" "$after")" "yes"
check "6. remove-foreign: value still other-path" "$(config_get "$f" core.hooksPath)" "other-path"

# ===========================================================================
# 7. Not inside a git repository: exit 2, diagnostic on stderr. Contract:
#    Errors.
# ===========================================================================
f="$(new_plain_dir)"
run_setup "$f" "$FULL_PATH"
check "7. not a repo: exit 2" "$RUN_EXIT" "2"
check "7. not a repo: stderr diagnostic" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 8. Not a clam checkout -- marketplace.json missing entirely: exit 2,
#    stderr diagnostic, config untouched. Contract: Errors.
# ===========================================================================
f="$(new_repo_no_marker)"
before="$(config_snapshot "$f")"
run_setup "$f" "$FULL_PATH"
after="$(config_snapshot "$f")"
check "8. not-clam (no marker): exit 2" "$RUN_EXIT" "2"
check "8. not-clam (no marker): stderr diagnostic" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
check "8. not-clam (no marker): config untouched" "$(config_untouched "$before" "$after")" "yes"

# ===========================================================================
# 9. Not a clam checkout -- marketplace.json present but "name" != "clam"
#    (also covers "name" key absent entirely). Contract: Errors.
# ===========================================================================
f="$(new_repo_wrong_name)"
before="$(config_snapshot "$f")"
run_setup "$f" "$FULL_PATH"
after="$(config_snapshot "$f")"
check "9. not-clam (wrong name): exit 2" "$RUN_EXIT" "2"
check "9. not-clam (wrong name): config untouched" "$(config_untouched "$before" "$after")" "yes"

f="$(new_repo_missing_name_key)"
before="$(config_snapshot "$f")"
run_setup "$f" "$FULL_PATH"
after="$(config_snapshot "$f")"
check "9b. not-clam (missing name key): exit 2" "$RUN_EXIT" "2"
check "9b. not-clam (missing name key): config untouched" "$(config_untouched "$before" "$after")" "yes"

# ===========================================================================
# 10. jq not available: even an otherwise-conforming clam repo is refused,
#     exit 2, stderr diagnostic, config untouched. Contract: Errors.
# ===========================================================================
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP  10. jq-missing case: no real jq found on this system to hide"
else
  # Self-guard: the PATH shim must actually hide jq. If jq is still
  # reachable here, the shim is broken and the three checks below would be
  # silently exercising a REACHABLE jq -- fail loudly instead of drifting
  # back into the false-negative this test exists to prevent.
  if PATH="$NOJQ_PATH" command -v jq >/dev/null 2>&1; then
    echo "FATAL: jq still reachable under the constructed NOJQ_PATH -- PATH shim is broken" >&2
    exit 1
  fi
  # Second half of the same self-guard: the shim must hide ONLY jq. If bash
  # itself is missing from the farm the script under test cannot even start
  # and exits 127, which would read as a contract failure rather than as
  # the broken fixture it is. Assert bash is reachable so a regression in
  # the farm's coverage fails here, loudly, instead of downstream.
  check "10. jq-missing shim self-guard: bash still reachable under NOJQ_PATH" \
    "$(PATH="$NOJQ_PATH" command -v bash >/dev/null 2>&1 && echo yes || echo no)" "yes"
  f="$(new_clam_repo)"
  before="$(config_snapshot "$f")"
  run_setup "$f" "$NOJQ_PATH"
  after="$(config_snapshot "$f")"
  check "10. jq missing: exit 2" "$RUN_EXIT" "2"
  check "10. jq missing: stderr diagnostic" \
    "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
  check "10. jq missing: config untouched" "$(config_untouched "$before" "$after")" "yes"
fi

# ===========================================================================
# 11. Usage errors: unknown flag, stray positional arg, and "--remove" with
#     an extra argument are all usage errors -- usage line on stderr, exit
#     2, config untouched. Contract: Inputs ("any other argument is a
#     usage error"), Errors.
# ===========================================================================
for args in "--bogus" "extra-positional-arg" "--remove extra"; do
  f="$(new_clam_repo)"
  before="$(config_snapshot "$f")"
  run_setup "$f" "$FULL_PATH" $args
  after="$(config_snapshot "$f")"
  check "11. usage error ('$args'): exit 2" "$RUN_EXIT" "2"
  check "11. usage error ('$args'): stderr usage line" \
    "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
  check "11. usage error ('$args'): config untouched" \
    "$(config_untouched "$before" "$after")" "yes"
done

# ===========================================================================
# 12. --remove is also gated by clam-checkout detection (the checkout
#     detection isn't install-specific in the contract's Behavior section):
#     on a non-clam repo, --remove refuses the same as install would.
# ===========================================================================
f="$(new_repo_no_marker)"
run_setup "$f" "$FULL_PATH" --remove
check "12. remove on non-clam repo: exit 2" "$RUN_EXIT" "2"

# ===========================================================================
# 13. Run from a subdirectory of the repo: repo detection via git
#     rev-parse; behaves identically to running from the root. Contract:
#     Edge cases.
# ===========================================================================
f="$(new_clam_repo)"
mkdir -p "$f/sub/dir"
run_setup "$f/sub/dir" "$FULL_PATH"
check "13. subdir invocation: exit 0" "$RUN_EXIT" "0"
check "13. subdir invocation: config lands at repo root" \
  "$(config_get "$f" core.hooksPath)" "scripts/githooks"

# ===========================================================================
# 14. Branch without scripts/githooks/ checked out (dir absent at
#     activation time): install still succeeds. Contract: Edge cases.
# ===========================================================================
f="$(new_clam_repo --no-hooks-dir)"
run_setup "$f" "$FULL_PATH"
check "14. missing scripts/githooks dir: exit 0" "$RUN_EXIT" "0"
check "14. missing scripts/githooks dir: config still set" \
  "$(config_get "$f" core.hooksPath)" "scripts/githooks"

# ===========================================================================
# 15. Worktree scenario: config written from the primary checkout must be
#     visible from a SIBLING worktree, since worktrees share the common
#     (repository-scope) config and the hooksPath is relative. Contract:
#     Behavior ("for every worktree at once").
# ===========================================================================
f="$(new_clam_repo)"
wt="$(mktemp -d)"; track_tmp "$wt"
rmdir "$wt"
(
  cd "$f" && git worktree add -q "$wt" -b setup-hooks-fixture-wt >/dev/null 2>&1
) >/dev/null 2>&1
run_setup "$f" "$FULL_PATH"
check "15. worktree: install exit 0 from primary" "$RUN_EXIT" "0"
check "15. worktree: sibling worktree sees the SAME config value" \
  "$(config_get "$wt" core.hooksPath)" "scripts/githooks"

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
