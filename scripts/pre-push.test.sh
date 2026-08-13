#!/usr/bin/env bash
# pre-push.test.sh — contract tests for scripts/githooks/pre-push (B03a
# pre-push hook, plan 001-pseudo-ci).
#
# Black-box only: builds fixture git repos under mktemp -d, plants a fake
# scripts/ci.sh in the fixture (a record-invocation stub that logs its
# args/cwd to a file OUTSIDE the fixture tree, emits distinguishable
# stdout/stderr markers, and exits a configured code), then invokes the
# REAL scripts/githooks/pre-push (resolved via BASH_SOURCE from this repo)
# with cwd set inside the fixture and $1/$2/stdin fed exactly as git would
# feed a pre-push hook. Assertions are on the hook's own exit code and
# stdout/stderr plus the stub's log — never on the hook's internals.
#
# Mirrors the PASS/FAIL harness style of scripts/readme-lint.test.sh and
# the record-invocation stub style of scripts/ci.test.sh.
#
# Run: bash scripts/pre-push.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/githooks/pre-push"

if [ ! -f "$HOOK" ]; then
  echo "FATAL: script under test not found at $HOOK" >&2
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
# Cleanup registry for mktemp fixture trees/log files (command substitution
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
# Fixture repo builder: git-inits, one commit, NO scripts/ci.sh (callers add
# one via write_ci_stub when the scenario needs it).
# ---------------------------------------------------------------------------
new_repo() { # -> prints repo root path
  local d
  # Physical (symlink-resolved) path: on macOS `mktemp -d` returns a
  # /var/... path that is a symlink to /private/var/..., while the hook's
  # own cwd/toplevel resolution reports the physical form. Resolving at
  # creation keeps the CWD assertions comparable on macOS and Linux.
  d="$(cd "$(mktemp -d)" && pwd -P)"
  track_tmp "$d"
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    mkdir -p scripts
    printf '# fixture\n' > README.md
    git add -A
    git commit -q -m init
  ) >/dev/null
  printf '%s' "$d"
}

STDOUT_MARKER="CI-STDOUT-MARKER-42"
STDERR_MARKER="CI-STDERR-MARKER-42"

write_ci_stub() { # <fixture_root> <log_file> <exit_code>
  local root="$1" log="$2" code="$3"
  cat > "$root/scripts/ci.sh" <<STUB
#!/bin/bash
printf 'ARGS:%s\n' "\$*" >> '$log'
printf 'CWD:%s\n' "\$(pwd)" >> '$log'
echo '$STDOUT_MARKER'
echo '$STDERR_MARKER' >&2
exit $code
STUB
  chmod +x "$root/scripts/ci.sh"
}

write_broken_ci() { # <fixture_root> -- a ci.sh that fails to PARSE (bash syntax error)
  local root="$1"
  cat > "$root/scripts/ci.sh" <<'STUB'
#!/bin/bash
if [ 1 -eq 1
echo "unterminated conditional -- syntax error"
STUB
  chmod +x "$root/scripts/ci.sh"
}

# ---------------------------------------------------------------------------
# Invocation helper. Feeds $1 (remote name), $2 (remote url), and stdin
# exactly like git's own pre-push invocation. Wrapped in `timeout` as a
# test-suite safety net: stdin must be drained, never blocked on.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0

run_hook() { # <cwd> <remote_name> <remote_url> <stdin_content>
  local cwd="$1" remote="$2" url="$3" stdin="$4"
  local out err
  out="$(mktemp)"; err="$(mktemp)"
  ( cd "$cwd" && printf '%s' "$stdin" | timeout 10 bash "$HOOK" "$remote" "$url" >"$out" 2>"$err" )
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

log_has() { # log_file needle -> yes/no
  [ -f "$1" ] && grep -qF -- "$2" "$1" && echo yes || echo no
}

log_count() { # log_file -> number of non-empty lines (invocation count proxy via ARGS: lines)
  [ -f "$1" ] || { echo 0; return; }
  grep -c '^ARGS:' "$1" || true
}

tree_snapshot() { # root -> sorted "relpath  sha256" lines
  local root="$1"
  # `sha256sum` is GNU-only; macOS ships `shasum`. Prefer whichever exists
  # so the snapshot is a real digest on both platforms (a missing binary
  # would otherwise make every -exec fail and compare empty-to-empty,
  # i.e. pass vacuously).
  local hasher
  if command -v sha256sum >/dev/null 2>&1; then
    hasher=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    hasher=(shasum -a 256)
  else
    echo "FATAL: no sha256sum/shasum available for tree_snapshot" >&2
    exit 1
  fi
  ( cd "$root" && find . -type f -exec "${hasher[@]}" {} + ) | sort
}

BLOCK_MSG="pre-push: pseudo-CI failed — push blocked (bypass: git push --no-verify)"
MISSING_MSG="pre-push: scripts/ci.sh not on this branch; skipping checks"

# ===========================================================================
# 1. ci.sh passes: exit 0, invoked with exactly "--post-status" from the
#    repo root, its stdout/stderr pass through untouched, no block or
#    missing-ci.sh notice appears, "no extra ceremony" on pass.
#    Contract: Behavior, Inputs (repo root), Outputs (pass line).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_ci_stub "$f" "$log" 0
run_hook "$f" "origin" "https://example.com/repo.git" \
  "refs/heads/main $(printf '%040d' 1) refs/heads/main $(printf '%040d' 2)"$'\n'

check "1. pass: exit 0" "$RUN_EXIT" "0"
check "1. pass: ci.sh invoked with exactly --post-status" \
  "$(log_has "$log" 'ARGS:--post-status')" "yes"
check "1. pass: ci.sh invoked from repo root" \
  "$(log_has "$log" "CWD:$f")" "yes"
check "1. pass: ci.sh stdout passes through" \
  "$(contains "$RUN_OUT" "$STDOUT_MARKER")" "yes"
check "1. pass: ci.sh stderr passes through" \
  "$(contains "$RUN_ERR" "$STDERR_MARKER")" "yes"
check "1. pass: no block message" "$(contains "$RUN_ERR" "$BLOCK_MSG")" "no"
check "1. pass: no missing-ci.sh notice" "$(contains "$RUN_ERR" "$MISSING_MSG")" "no"
check "1. pass: ci.sh invoked exactly once" "$(log_count "$log")" "1"

# ===========================================================================
# 2. ci.sh fails with exit 1: push blocked, exact block message on stderr
#    naming the --no-verify bypass, exit propagates, ci.sh output still
#    passes through, repo tree unmodified (Invariant: never modifies repo
#    state). Contract: Behavior, Outputs (block line), Invariants.
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_ci_stub "$f" "$log" 1
before="$(tree_snapshot "$f")"
run_hook "$f" "origin" "https://example.com/repo.git" \
  "refs/heads/main $(printf '%040d' 1) refs/heads/main $(printf '%040d' 2)"$'\n'
after="$(tree_snapshot "$f")"

check "2. fail(1): exit propagates as 1" "$RUN_EXIT" "1"
check "2. fail(1): exact block message on stderr" \
  "$(contains "$RUN_ERR" "$BLOCK_MSG")" "yes"
check "2. fail(1): ci.sh stdout still passes through" \
  "$(contains "$RUN_OUT" "$STDOUT_MARKER")" "yes"
check "2. fail(1): ci.sh stderr still passes through" \
  "$(contains "$RUN_ERR" "$STDERR_MARKER")" "yes"
check "2. fail(1): repo tree unmodified" "$after" "$before"

# ===========================================================================
# 3. ci.sh fails with a DISTINCT exit code (7): the hook's exit code must
#    equal ci.sh's exit code exactly, not a hardcoded 1 -- proving the hook
#    delegates the decision rather than reinterpreting it (Invariant: NO
#    check logic of its own).
# ===========================================================================
f="$(new_repo)"
log="$(mktemp)"; track_tmp "$log"
write_ci_stub "$f" "$log" 7
run_hook "$f" "origin" "https://example.com/repo.git" \
  "refs/heads/main $(printf '%040d' 1) refs/heads/main $(printf '%040d' 2)"$'\n'

check "3. fail(7): exit propagates as 7 (not hardcoded)" "$RUN_EXIT" "7"
check "3. fail(7): exact block message on stderr" \
  "$(contains "$RUN_ERR" "$BLOCK_MSG")" "yes"

# ===========================================================================
# 4. scripts/ci.sh absent (branch predating pseudo-CI): one-line notice on
#    stderr, exit 0, never blocks. Contract: Behavior, Outputs.
# ===========================================================================
f="$(new_repo)"
run_hook "$f" "origin" "https://example.com/repo.git" \
  "refs/heads/main $(printf '%040d' 1) refs/heads/main $(printf '%040d' 2)"$'\n'

check "4. ci.sh absent: exit 0" "$RUN_EXIT" "0"
check "4. ci.sh absent: exact missing notice on stderr" \
  "$(contains "$RUN_ERR" "$MISSING_MSG")" "yes"
check "4. ci.sh absent: no block message" \
  "$(contains "$RUN_ERR" "$BLOCK_MSG")" "no"

# ===========================================================================
# 5. stdin is drained, not parsed: well-formed ref lines, multiple ref
#    lines, empty stdin (push with no refs, e.g. --tags with nothing to
#    send), and odd/malformed ref lines all produce the IDENTICAL outcome
#    as the baseline passing case. Contract: Inputs, Edge cases.
# ===========================================================================
declare -a STDIN_CASES=(
  "refs/heads/main $(printf '%040d' 1) refs/heads/main $(printf '%040d' 2)"$'\n'
  ""
  $'refs/heads/a 1111111111111111111111111111111111111111 refs/heads/a 2222222222222222222222222222222222222222\nrefs/heads/b 3333333333333333333333333333333333333333 refs/heads/b 4444444444444444444444444444444444444444\n'
  $'not a ref line at all\n\n   \ngarbage\tfields\there\n'
  $'\n\n\n'
)
STDIN_LABELS=("single ref" "empty stdin" "multiple refs" "malformed lines" "blank lines only")
for i in "${!STDIN_CASES[@]}"; do
  f="$(new_repo)"
  log="$(mktemp)"; track_tmp "$log"
  write_ci_stub "$f" "$log" 0
  run_hook "$f" "origin" "https://example.com/repo.git" "${STDIN_CASES[$i]}"
  check "5. stdin '${STDIN_LABELS[$i]}': exit 0" "$RUN_EXIT" "0"
  check "5. stdin '${STDIN_LABELS[$i]}': ci.sh still invoked with --post-status" \
    "$(log_has "$log" 'ARGS:--post-status')" "yes"
done

# ===========================================================================
# 6. $1 (remote name) / $2 (remote url) are accepted but ignored: varying
#    them (including empty strings, and unusual values) does not change the
#    outcome. Contract: Inputs.
# ===========================================================================
declare -a REMOTE_NAMES=("origin" "upstream" "" "weird name with spaces")
declare -a REMOTE_URLS=("https://example.com/repo.git" "git@example.com:x/y.git" "" "not-a-url-at-all")
for i in "${!REMOTE_NAMES[@]}"; do
  f="$(new_repo)"
  log="$(mktemp)"; track_tmp "$log"
  write_ci_stub "$f" "$log" 0
  run_hook "$f" "${REMOTE_NAMES[$i]}" "${REMOTE_URLS[$i]}" \
    "refs/heads/main $(printf '%040d' 1) refs/heads/main $(printf '%040d' 2)"$'\n'
  check "6. remote args #$i: exit 0 regardless of \$1/\$2" "$RUN_EXIT" "0"
  check "6. remote args #$i: ci.sh still invoked with --post-status" \
    "$(log_has "$log" 'ARGS:--post-status')" "yes"
done

# ===========================================================================
# 7. Runs ci.sh from the repo root even when the hook itself starts in a
#    subdirectory (the hook re-resolves the root via git rev-parse for
#    safety). Contract: Inputs, Behavior ("from the repo root").
# ===========================================================================
f="$(new_repo)"
mkdir -p "$f/sub/dir"
log="$(mktemp)"; track_tmp "$log"
write_ci_stub "$f" "$log" 0
run_hook "$f/sub/dir" "origin" "https://example.com/repo.git" \
  "refs/heads/main $(printf '%040d' 1) refs/heads/main $(printf '%040d' 2)"$'\n'

check "7. subdir invocation: exit 0" "$RUN_EXIT" "0"
check "7. subdir invocation: ci.sh still invoked from repo root, not subdir" \
  "$(log_has "$log" "CWD:$f")" "yes"

# ===========================================================================
# 8. Not inside a git repository: git rev-parse fails, diagnostic on
#    stderr, exit 1. Contract: Errors.
# ===========================================================================
f="$(mktemp -d)"; track_tmp "$f"
run_hook "$f" "origin" "https://example.com/repo.git" ""
check "8. not a repo: exit 1" "$RUN_EXIT" "1"
check "8. not a repo: stderr non-empty diagnostic" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 9. ci.sh present but unparseable (bash syntax error): bash's own failure
#    exit propagates and blocks the push (fail closed). Contract: Edge
#    cases.
# ===========================================================================
f="$(new_repo)"
write_broken_ci "$f"
run_hook "$f" "origin" "https://example.com/repo.git" \
  "refs/heads/main $(printf '%040d' 1) refs/heads/main $(printf '%040d' 2)"$'\n'

check "9. unparseable ci.sh: exit non-zero (fail closed)" \
  "$([ "$RUN_EXIT" -ne 0 ] && echo yes || echo no)" "yes"
check "9. unparseable ci.sh: block message on stderr" \
  "$(contains "$RUN_ERR" "$BLOCK_MSG")" "yes"

# ===========================================================================
# 10. The committed hook itself carries executable mode (100755): git
#     ignores non-executable hooksPath hooks, which would silently disable
#     the gate. Checked on the REAL file (not a fixture). Contract:
#     Invariants.
# ===========================================================================
check "10. hook file is executable on disk" \
  "$([ -x "$HOOK" ] && echo yes || echo no)" "yes"
TRACKED_MODE="$(git -C "$SCRIPT_DIR/.." ls-files -s -- "scripts/githooks/pre-push" 2>/dev/null | awk '{print $1}')"
if [ -n "$TRACKED_MODE" ]; then
  check "10. hook file tracked with mode 100755" "$TRACKED_MODE" "100755"
else
  echo "SKIP  10. hook file not yet tracked by git (untracked working file)"
fi

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
