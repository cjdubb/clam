#!/usr/bin/env bash
# worktree.test.sh — contract tests for worktree.sh (B01 worktree-lib).
#
# Self-contained bash test harness (no bats/shellcheck). Every test is a
# shell function that builds its own throwaway git fixture(s) under
# mktemp, invokes worktree.sh through its public CLI, and asserts on its
# exit code / stdout / stderr / resulting git+filesystem state — never on
# worktree.sh's internals. Run directly: `bash worktree.test.sh`.
#
# Exits 0 when every test passes, 1 when any test fails.
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/worktree.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: script under test not found at $SCRIPT" >&2
  exit 1
fi

REALM_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/realm.sh"

if [ ! -f "$REALM_SCRIPT" ]; then
  echo "FATAL: script under test not found at $REALM_SCRIPT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Cleanup registry. Functions that build fixtures are usually invoked via
# command substitution (repo="$(new_git_repo)"), which forks a subshell —
# any plain shell-variable mutation made inside that subshell (e.g. an
# array append) is lost when the subshell exits. A file-based manifest
# survives that boundary because it is real disk I/O, not shell memory.
# ---------------------------------------------------------------------------
CLEANUP_MANIFEST="$(mktemp)"

track_tmp() {
  printf '%s\n' "$1" >> "$CLEANUP_MANIFEST"
}

cleanup() {
  if [ -f "$CLEANUP_MANIFEST" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] && [ -e "$d" ] && rm -rf -- "$d"
    done < "$CLEANUP_MANIFEST"
    rm -f -- "$CLEANUP_MANIFEST"
  fi
}
trap cleanup EXIT

# Neutralize any global core.hooksPath the ambient environment might set,
# so fixture commits never trigger unrelated repo hooks.
NOOP_HOOKS_DIR="$(mktemp -d)"
track_tmp "$NOOP_HOOKS_DIR"

# ---------------------------------------------------------------------------
# Minimal test harness: named tests, per-test assertion failures, summary.
# ---------------------------------------------------------------------------
CURRENT_TEST=""
CURRENT_FAILURES=0
TOTAL_PASS=0
TOTAL_FAIL=0

start_test() {
  CURRENT_TEST="$1"
  CURRENT_FAILURES=0
}

record_fail() {
  CURRENT_FAILURES=$((CURRENT_FAILURES + 1))
  printf '    FAIL: %s\n' "$1"
}

end_test() {
  if [ "$CURRENT_FAILURES" -eq 0 ]; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
    echo "ok - $CURRENT_TEST"
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    echo "not ok - $CURRENT_TEST ($CURRENT_FAILURES failing assertion(s))"
  fi
}

run_test() {
  local name="$1"
  shift
  start_test "$name"
  "$@"
  end_test
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" != "$actual" ]; then
    record_fail "$label: expected [$expected] got [$actual]"
  fi
}

# Every error must be exactly one stderr line starting "ERROR: ".
assert_single_error_line() {
  local err="$1" label="$2"
  if [ -z "$err" ]; then
    record_fail "$label: expected a single 'ERROR: ' stderr line, got empty stderr"
    return
  fi
  local n
  n="$(printf '%s\n' "$err" | grep -c '')"
  if [ "$n" -ne 1 ]; then
    record_fail "$label: expected exactly 1 stderr line, got $n (stderr: $err)"
  fi
  case "$err" in
    "ERROR: "*) : ;;
    *) record_fail "$label: stderr does not start with 'ERROR: ' (got: $err)" ;;
  esac
}

# ---------------------------------------------------------------------------
# Invocation helpers.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
RUN_OUT_LINES=0
RUN_OUT_LAST=""

# run_cmd <dir> <path-or-empty-for-default> <args...>
run_cmd() {
  local dir="$1" pth="$2"
  shift 2
  local usepath="$pth"
  [ -n "$usepath" ] || usepath="$PATH"
  local out err ec
  out="$(mktemp)"
  err="$(mktemp)"
  ( cd "$dir" && PATH="$usepath" bash "$SCRIPT" "$@" ) >"$out" 2>"$err"
  ec=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  RUN_EXIT=$ec
  if [ -s "$out" ]; then
    RUN_OUT_LINES="$(grep -c '' "$out")"
  else
    RUN_OUT_LINES=0
  fi
  RUN_OUT_LAST="$(tail -n1 "$out")"
  rm -f "$out" "$err"
}

# run_in <dir> <args...>  (default PATH)
run_in() {
  local dir="$1"
  shift
  run_cmd "$dir" "" "$@"
}

# run_realm <dir> <lego-config-or-empty> <path> -- invokes realm.sh <path>
# with cwd <dir> (LEGO_CONFIG's default ".local/config.json" and the fixed
# base path ".claude/lego.json" are both relative to cwd), optionally
# overriding $LEGO_CONFIG. Sets RUN_REALM_OUT (stdout) and RUN_REALM_EXIT.
RUN_REALM_OUT=""
RUN_REALM_EXIT=0
run_realm() {
  local dir="$1" cfg="$2" path="$3"
  local out ec
  out="$(mktemp)"
  if [ -n "$cfg" ]; then
    ( cd "$dir" && LEGO_CONFIG="$cfg" bash "$REALM_SCRIPT" "$path" ) >"$out" 2>/dev/null
  else
    ( cd "$dir" && bash "$REALM_SCRIPT" "$path" ) >"$out" 2>/dev/null
  fi
  ec=$?
  RUN_REALM_OUT="$(cat "$out")"
  RUN_REALM_EXIT=$ec
  rm -f "$out"
}

# path_without <exe-name> -- prints a dir containing symlinks to every
# executable currently resolvable on $PATH except <exe-name>.
path_without() {
  local exclude="$1"
  local dir p b name
  dir="$(mktemp -d)"
  track_tmp "$dir"
  local parts
  IFS=':' read -ra parts <<< "$PATH"
  for p in "${parts[@]}"; do
    [ -n "$p" ] && [ -d "$p" ] || continue
    for b in "$p"/*; do
      [ -e "$b" ] || continue
      name="$(basename "$b")"
      [ "$name" = "$exclude" ] && continue
      [ -e "$dir/$name" ] && continue
      ln -s "$b" "$dir/$name" 2>/dev/null || true
    done
  done
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# Fixture helpers.
# ---------------------------------------------------------------------------

# new_git_repo -- a fresh repo at <container>/repo, branch "master", one
# commit. Nested inside a unique tracked container so that "the parent
# directory of the repo root" is always something we own and can clean up.
new_git_repo() {
  local container repo
  container="$(mktemp -d)"
  track_tmp "$container"
  repo="$container/repo"
  mkdir -p "$repo"
  git init -q -b master "$repo" >/dev/null
  git -C "$repo" config user.email "lego-fixture@example.com"
  git -C "$repo" config user.name "Lego Fixture"
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" config core.hooksPath "$NOOP_HOOKS_DIR"
  # Mirrors production: lego's plan skill excludes .local/ via
  # .git/info/exclude, so it never shows up in `git status --porcelain` or
  # a `git add -A`. Fixtures write .local/config.json, .local/blocks.md,
  # .local/contracts/* directly to disk (never via `git add`); without this
  # exclude, those files are perpetually untracked and any assertion that
  # the invoking worktree is clean after a subcommand runs would always
  # find "?? .local/", regardless of what the subcommand under test does.
  printf '%s\n' '.local/' >> "$repo/.git/info/exclude"
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial commit"
  printf '%s' "$repo"
}

# commit_files <repo> <message> <relpath> <content> [<relpath> <content> ...]
commit_files() {
  local repo="$1" msg="$2"
  shift 2
  while [ "$#" -ge 2 ]; do
    local rel="$1" content="$2"
    shift 2
    mkdir -p "$(dirname "$repo/$rel")"
    printf '%s' "$content" > "$repo/$rel"
    git -C "$repo" add -- "$rel"
  done
  git -C "$repo" commit -q -m "$msg"
}

commit_file() {
  local repo="$1" rel="$2" content="$3" msg="$4"
  commit_files "$repo" "$msg" "$rel" "$content"
}

# write_config_json <repo> <test-cmd> [<worktree-dir>]
write_config_json() {
  local repo="$1" testcmd="$2"
  mkdir -p "$repo/.local"
  if [ "$#" -ge 3 ]; then
    jq -n --arg t "$testcmd" --arg w "$3" \
      '{commands:{test:$t},models:{testWriter:"sonnet",implementer:"sonnet"},testPatterns:[],delivery:{mode:"main-prs",worktreeDir:$w}}' \
      > "$repo/.local/config.json"
  else
    jq -n --arg t "$testcmd" \
      '{commands:{test:$t},models:{testWriter:"sonnet",implementer:"sonnet"},testPatterns:[],delivery:{mode:"main-prs"}}' \
      > "$repo/.local/config.json"
  fi
}

# write_base_config <repo> <json-content> -- writes and commits
# .claude/lego.json (the committed base layer of the layered config).
# <json-content> is written verbatim as the file body; build it by hand
# (these fixtures are small enough not to need jq -n).
write_base_config() {
  local repo="$1" content="$2"
  mkdir -p "$repo/.claude"
  printf '%s' "$content" > "$repo/.claude/lego.json"
  git -C "$repo" add .claude/lego.json
  git -C "$repo" commit -q -m "add base lego.json"
}

# write_override_config <repo> <json-content> -- writes .local/config.json
# (the gitignored override layer) verbatim, uncommitted. Unlike
# write_config_json (which always builds one fixed shape from a test
# command), this accepts arbitrary JSON content for tests that need custom
# shapes: merge semantics, object-form commands.test, invalid JSON.
write_override_config() {
  local repo="$1" content="$2"
  mkdir -p "$repo/.local"
  printf '%s' "$content" > "$repo/.local/config.json"
}

write_blocks_md() {
  local repo="$1"
  mkdir -p "$repo/.local"
  cat > "$repo/.local/blocks.md" <<'BLOCKSMD'
# Block Map

## B01 — greet
- Status: Scaffolded
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U01
- Code: src/greet.sh, src/greet_test.sh
- Contract: greets politely and covers the happy path
- Plan: plans/001-test.md

## B02 — other
- Status: Scaffolded
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U01
- Code: src/other.sh, src/dir with space/file.sh
- Contract: handles the other responsibilities of the unit
- Plan: plans/001-test.md

## B03 — solo
- Status: Scaffolded
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U02
- Code: src/solo.sh
- Contract: stands alone as a single-block unit
- Plan: plans/001-test.md

## B04 — nocode
- Status: Scaffolded
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U03
- Contract: documents a decision; carries no code paths
- Plan: plans/001-test.md

## B05 — needsimpl
- Status: Scaffolded
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U04
- Code: src/needsimpl.sh
- Contract: exercises the missing-implementation-commit error path
- Plan: plans/001-test.md

## B06 — noop
- Status: Scaffolded
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U05
- Code: src/noop.sh
- Contract: exercises the no-op restore path
- Plan: plans/001-test.md
BLOCKSMD
}

write_contracts() {
  local repo="$1"
  mkdir -p "$repo/.local/contracts"
  printf '# B01 contract\n\nGreets politely.\n' > "$repo/.local/contracts/B01-greet.md"
  printf '# B02 contract\n\nHandles other things.\n' > "$repo/.local/contracts/B02-other.md"
  # B03-B06 deliberately have no contract file: tests the "silently skipped
  # when no such file exists" clause.
}

# build_deliver_base -- full add-fixture plus base source files for every
# block's Code path, and an "origin" remote (local bare repo) with master
# pushed. Callers add unit branches on top of master as each test needs.
build_deliver_base() {
  local repo
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"

  mkdir -p "$repo/src/dir with space"
  printf 'greet v0\n' > "$repo/src/greet.sh"
  printf 'greet test v0\n' > "$repo/src/greet_test.sh"
  printf 'other v0\n' > "$repo/src/other.sh"
  printf 'spacey v0\n' > "$repo/src/dir with space/file.sh"
  printf 'solo v0\n' > "$repo/src/solo.sh"
  printf 'needsimpl v0\n' > "$repo/src/needsimpl.sh"
  printf 'noop v0\n' > "$repo/src/noop.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "seed block source files"

  local bare_container bare
  bare_container="$(mktemp -d)"
  track_tmp "$bare_container"
  bare="$bare_container/origin.git"
  git init -q --bare "$bare" >/dev/null
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" push -q origin master >/dev/null 2>&1

  printf '%s' "$repo"
}

# make_gh_shim -- sets GH_SHIM_BIN (a dir to prepend to PATH) and
# GH_SHIM_LOG (a file recording every invocation's raw args) as globals.
# Called as a plain statement (not via command substitution) so its
# global assignments are not lost to a subshell.
GH_SHIM_BIN=""
GH_SHIM_LOG=""
make_gh_shim() {
  local container
  container="$(mktemp -d)"
  track_tmp "$container"
  mkdir -p "$container/bin"
  : > "$container/gh.log"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'GH_SHIM_LOGFILE=%s\n' "$(printf '%q' "$container/gh.log")"
    cat <<'SHIM_BODY'
printf '%s\n' "$*" >> "$GH_SHIM_LOGFILE"
if [ "$1" = "pr" ] && [ "$2" = "create" ]; then
  echo "https://github.com/example/lego-fixture/pull/123"
fi
exit 0
SHIM_BODY
  } > "$container/bin/gh"
  chmod +x "$container/bin/gh"

  GH_SHIM_BIN="$container/bin"
  GH_SHIM_LOG="$container/gh.log"
}

# write_valid_manifest <repo> <title> <branch> <unit-id>... -- writes
# "$repo/.local/manifest.json" satisfying B01's required-field contract:
# non-empty title, non-empty branch, and a non-empty
# commits.<unit-id>.impl for every given unit-id (generic placeholder
# subject "test impl for <unit-id>" -- callers that need an exact subject
# string, e.g. to match an existing assertion on delivered commit text,
# should build the manifest by hand with jq/printf instead). "tests" is
# deliberately left unset per unit (it is optional per the contract).
# Prints the manifest path on stdout.
write_valid_manifest() {
  local repo="$1" title="$2" branch_name="$3"
  shift 3
  local commits="{}"
  local uid
  for uid in "$@"; do
    commits="$(printf '%s' "$commits" | jq --arg u "$uid" --arg s "test impl for $uid" '.[$u] = {impl: $s}')"
  done
  mkdir -p "$repo/.local"
  jq -n --arg t "$title" --arg br "$branch_name" --argjson c "$commits" \
    '{title: $t, branch: $br, commits: $c}' > "$repo/.local/manifest.json"
  printf '%s' "$repo/.local/manifest.json"
}

# ===========================================================================
# add
# ===========================================================================

test_add_usage_argcount() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" add
  [ "$RUN_EXIT" -eq 2 ] || record_fail "no args: expected exit 2, got $RUN_EXIT"

  run_in "$repo" add onlyplan
  [ "$RUN_EXIT" -eq 2 ] || record_fail "1 arg: expected exit 2, got $RUN_EXIT"

  run_in "$repo" add plan1 U01
  [ "$RUN_EXIT" -eq 2 ] || record_fail "2 args: expected exit 2, got $RUN_EXIT"

  run_in "$repo" add plan1 U01 slug1 extra
  [ "$RUN_EXIT" -eq 2 ] || record_fail "4 args: expected exit 2, got $RUN_EXIT"
}

test_add_invalid_chars() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" add "plan slug" U01 slug1
  [ "$RUN_EXIT" -eq 2 ] || record_fail "space in plan-slug: expected exit 2, got $RUN_EXIT"

  run_in "$repo" add plan1 "U0/1" slug1
  [ "$RUN_EXIT" -eq 2 ] || record_fail "slash in unit-id: expected exit 2, got $RUN_EXIT"

  run_in "$repo" add plan1 U01 'slug;rm'
  [ "$RUN_EXIT" -eq 2 ] || record_fail "semicolon in unit-slug: expected exit 2, got $RUN_EXIT"
}

test_add_missing_dependencies() {
  local repo
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"

  local path_no_jq
  path_no_jq="$(path_without jq)"
  run_cmd "$repo" "$path_no_jq" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "jq absent: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "jq absent"

  local repo2
  repo2="$(new_git_repo)"
  write_blocks_md "$repo2"
  run_in "$repo2" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "config.json missing: expected exit 3, got $RUN_EXIT"

  local repo3
  repo3="$(new_git_repo)"
  write_config_json "$repo3" ""
  write_blocks_md "$repo3"
  run_in "$repo3" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "commands.test empty: expected exit 3, got $RUN_EXIT"

  local repo4
  repo4="$(new_git_repo)"
  mkdir -p "$repo4/.local"
  jq -n '{commands:{}}' > "$repo4/.local/config.json"
  write_blocks_md "$repo4"
  run_in "$repo4" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "commands.test key absent: expected exit 3, got $RUN_EXIT"

  local repo5
  repo5="$(new_git_repo)"
  write_config_json "$repo5" "true"
  run_in "$repo5" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "blocks.md missing: expected exit 3, got $RUN_EXIT"
}

test_requires_git_work_tree() {
  local dir
  dir="$(mktemp -d)"
  track_tmp "$dir"

  run_in "$dir" add plan1 U01 slug1
  [ "$RUN_EXIT" -eq 3 ] || record_fail "add outside git worktree: expected exit 3, got $RUN_EXIT"

  run_in "$dir" merge plan1 U01 slug1
  [ "$RUN_EXIT" -eq 3 ] || record_fail "merge outside git worktree: expected exit 3, got $RUN_EXIT"

  # --manifest is required before require_repo_root ever runs, but the path
  # itself is never read on this path: require_repo_root fires first, for
  # the git-worktree reason this test is about, not the manifest-required
  # reason. The path need not exist or be valid JSON.
  run_in "$dir" deliver --manifest "$dir/unused-manifest.json" plan1 master U01 slug1
  [ "$RUN_EXIT" -eq 3 ] || record_fail "deliver outside git worktree: expected exit 3, got $RUN_EXIT"

  run_in "$dir" remove plan1 U01 slug1
  [ "$RUN_EXIT" -eq 3 ] || record_fail "remove outside git worktree: expected exit 3, got $RUN_EXIT"
}

test_add_unit_not_found() {
  local repo
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"

  run_in "$repo" add plan1 U99 slug1
  [ "$RUN_EXIT" -eq 4 ] || record_fail "unknown unit id: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "unknown unit id"
}

test_add_branch_already_exists() {
  local repo
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  git -C "$repo" branch "lego/plan1/U01-greetstuff"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "branch pre-exists: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "branch pre-exists"
}

test_add_worktree_path_already_exists() {
  local repo expected_wt
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U01"
  mkdir -p "$expected_wt"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "worktree path pre-exists: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "worktree path pre-exists"
}

test_add_baseline_failure_cleans_up() {
  local repo expected_wt
  repo="$(new_git_repo)"
  write_config_json "$repo" "false"
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "baseline failure: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "baseline failure"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/plan1/U01-greetstuff"; then
    record_fail "baseline failure: branch should have been cleaned up but still exists (INV2)"
  fi
  if [ -e "$expected_wt" ]; then
    record_fail "baseline failure: worktree dir $expected_wt should have been cleaned up but still exists (INV2)"
  fi
}

test_add_success_and_seeding() {
  local repo expected_wt head_before untouched_sha
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U01"

  git -C "$repo" branch "feature/untouched"
  untouched_sha="$(git -C "$repo" rev-parse feature/untouched)"
  head_before="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" add plan1 U01 greetstuff

  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ "$RUN_OUT_LINES" -eq 1 ] || record_fail "expected exactly 1 stdout line, got $RUN_OUT_LINES (stdout: $RUN_OUT)"
  assert_eq "$expected_wt" "$RUN_OUT_LAST" "worktree path as last stdout line"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/plan1/U01-greetstuff"; then
    local branch_sha
    branch_sha="$(git -C "$repo" rev-parse lego/plan1/U01-greetstuff)"
    assert_eq "$head_before" "$branch_sha" "new branch points at prior HEAD"
  else
    record_fail "expected branch lego/plan1/U01-greetstuff to exist"
  fi

  if [ ! -d "$expected_wt" ]; then
    record_fail "expected worktree directory $expected_wt to exist"
  fi
  if ! git -C "$repo" worktree list | grep -qF "$expected_wt"; then
    record_fail "expected git worktree list to include $expected_wt"
  fi

  if [ -f "$expected_wt/.local/config.json" ]; then
    if ! diff -q "$repo/.local/config.json" "$expected_wt/.local/config.json" >/dev/null 2>&1; then
      record_fail "seeded .local/config.json is not a verbatim copy"
    fi
  else
    record_fail "expected seeded .local/config.json to exist in new worktree"
  fi

  if [ -f "$expected_wt/.local/unit.md" ]; then
    local first_line
    first_line="$(head -n1 "$expected_wt/.local/unit.md")"
    assert_eq "# Unit U01" "$first_line" "unit.md first line"
    if ! grep -qF "## B01 — greet" "$expected_wt/.local/unit.md"; then
      record_fail "unit.md missing B01 section heading"
    fi
    if ! grep -qF "## B02 — other" "$expected_wt/.local/unit.md"; then
      record_fail "unit.md missing B02 section heading (multi-block unit, EC1)"
    fi
    if grep -qF "## B03 — solo" "$expected_wt/.local/unit.md"; then
      record_fail "unit.md should not include B03 (different unit)"
    fi
    if ! grep -qF -- "- Contract: greets politely and covers the happy path" "$expected_wt/.local/unit.md"; then
      record_fail "unit.md B01 section not copied verbatim (missing contract line)"
    fi
  else
    record_fail "expected seeded .local/unit.md to exist in new worktree"
  fi

  if [ ! -f "$expected_wt/.local/contracts/B01-greet.md" ]; then
    record_fail "expected .local/contracts/B01-greet.md to be seeded"
  fi
  if [ ! -f "$expected_wt/.local/contracts/B02-other.md" ]; then
    record_fail "expected .local/contracts/B02-other.md to be seeded"
  fi

  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    record_fail "invoking worktree has uncommitted changes after add (INV1 violation)"
  fi
  local head_after
  head_after="$(git -C "$repo" rev-parse HEAD)"
  assert_eq "$head_before" "$head_after" "invoking worktree HEAD unchanged by add (INV1)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/feature/untouched"; then
    local after_sha
    after_sha="$(git -C "$repo" rev-parse feature/untouched)"
    assert_eq "$untouched_sha" "$after_sha" "unrelated branch feature/untouched untouched (INV3)"
  else
    record_fail "unrelated branch feature/untouched should still exist (INV3)"
  fi
}

test_add_no_contract_file_silently_skipped() {
  local repo expected_wt
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U02"

  run_in "$repo" add plan2 U02 solostuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ -d "$expected_wt/.local/contracts" ] && [ -n "$(ls -A "$expected_wt/.local/contracts" 2>/dev/null)" ]; then
    record_fail "expected no contracts to be seeded for U02 (B03 has no contract file); found: $(ls -A "$expected_wt/.local/contracts")"
  fi
  if [ -f "$expected_wt/.local/unit.md" ]; then
    if ! grep -qF "## B03 — solo" "$expected_wt/.local/unit.md"; then
      record_fail "unit.md missing B03 section heading"
    fi
  else
    record_fail "expected seeded .local/unit.md to exist"
  fi
}

test_add_worktree_dir_resolution() {
  local repo expected_wt
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "default worktreeDir: expected exit 0, got $RUN_EXIT"
  assert_eq "$expected_wt" "$RUN_OUT_LAST" "default (missing) worktreeDir resolves to parent of repo root"

  local repo2 expected_wt2
  repo2="$(new_git_repo)"
  write_config_json "$repo2" "true" "../wtout"
  write_blocks_md "$repo2"
  write_contracts "$repo2"
  expected_wt2="$(dirname "$repo2")/wtout/$(basename "$repo2")-U01"

  run_in "$repo2" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "relative worktreeDir: expected exit 0, got $RUN_EXIT"
  assert_eq "$expected_wt2" "$RUN_OUT_LAST" "relative worktreeDir resolves against repo root"
}

test_add_deterministic() {
  local repoA repoB
  repoA="$(new_git_repo)"
  write_config_json "$repoA" "true"
  write_blocks_md "$repoA"
  write_contracts "$repoA"
  repoB="$(new_git_repo)"
  write_config_json "$repoB" "true"
  write_blocks_md "$repoB"
  write_contracts "$repoB"

  run_in "$repoA" add plan1 U01 greetstuff
  local exitA="$RUN_EXIT" outA="$RUN_OUT_LAST"
  run_in "$repoB" add plan1 U01 greetstuff
  local exitB="$RUN_EXIT" outB="$RUN_OUT_LAST"

  [ "$exitA" -eq 0 ] || record_fail "run A: expected exit 0, got $exitA"
  [ "$exitB" -eq 0 ] || record_fail "run B: expected exit 0, got $exitB"
  assert_eq "$(basename "$outA")" "$(basename "$outB")" "deterministic result shape across identical repo state and args (INV4)"
}

test_add_baseline_runs_inside_new_worktree_after_seeding() {
  local repo
  repo="$(new_git_repo)"
  # .local/unit.md exists only inside the seeded new worktree — the
  # invoking repo never has one (write_config_json/write_blocks_md/
  # write_contracts never create it). If the baseline ran in the invoking
  # repo, or before seeding completed, this command would fail there and
  # `add` would report a baseline failure instead of succeeding.
  write_config_json "$repo" "test -f .local/unit.md"
  write_blocks_md "$repo"
  write_contracts "$repo"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "baseline test command must run inside the new worktree, after seeding: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
}

test_add_succeeds_without_gh() {
  local repo
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"

  local path_no_gh
  path_no_gh="$(path_without gh)"
  run_cmd "$repo" "$path_no_gh" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "gh is a deliver-only dependency; add must succeed without it: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
}

# ---------------------------------------------------------------------------
# add: status.md seeding (NEW, plan 001)
# ---------------------------------------------------------------------------

test_add_status_md_content() {
  local repo expected_wt head_before status_file expected_file diffout
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U02"
  head_before="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" add plan2 U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  status_file="$expected_wt/.local/status.md"
  if [ ! -f "$status_file" ]; then
    record_fail "expected seeded .local/status.md to exist in new worktree"
    return
  fi

  expected_file="$(mktemp)"
  track_tmp "$expected_file"
  {
    printf '%s\n' "# Unit U02 — status"
    printf '\n'
    printf '%s\n' "- Branch: lego/plan2/U02-soloslug"
    printf '%s\n' "- Created from: $head_before"
    printf '%s\n' "- Phase: Created"
    printf '\n'
    printf '%s\n' "## Blocks"
    printf '\n'
    printf '%s\n' "- B03 — solo: Scaffolded"
    printf '\n'
    printf '%s\n' "## Timeline"
    printf '\n'
    printf '%s\n' "<!-- orchestrator appends one line per event -->"
  } > "$expected_file"

  diffout="$(diff -u "$expected_file" "$status_file" 2>&1)"
  if [ -n "$diffout" ]; then
    record_fail "status.md content does not match the exact contract line sequence (heading, blank, Branch, Created from <full sha>, Phase, blank, ## Blocks, blank, block lines, blank, ## Timeline, blank, comment, trailing newline): $diffout"
  fi
}

test_add_status_md_status_field_verbatim_and_empty() {
  local repo expected_wt status_file line_b01 line_b02
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  mkdir -p "$repo/.local"
  cat > "$repo/.local/blocks.md" <<'BLOCKSMD'
# Block Map

## B01 — nostatus
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U01
- Code: src/a.sh
- Contract: has no Status field at all
- Plan: plans/001-test.md

## B02 — withstatus
- Status: In Progress
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U01
- Code: src/b.sh
- Contract: carries an explicit Status field
- Plan: plans/001-test.md
BLOCKSMD
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 mixedstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  status_file="$expected_wt/.local/status.md"
  if [ ! -f "$status_file" ]; then
    record_fail "expected seeded .local/status.md to exist"
    return
  fi

  line_b01="$(grep -F -- '- B01 — nostatus:' "$status_file" | head -n1)"
  line_b02="$(grep -F -- '- B02 — withstatus:' "$status_file" | head -n1)"
  assert_eq "- B01 — nostatus: " "$line_b01" "Blocks line status is empty (heading + ': ' + nothing) when the section has no '- Status:' field"
  assert_eq "- B02 — withstatus: In Progress" "$line_b02" "Blocks line status is the section's '- Status:' value verbatim"
}

test_add_status_md_multiblock_file_order() {
  local repo expected_wt status_file blocks_lines line1 line2
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  mkdir -p "$repo/.local"
  cat > "$repo/.local/blocks.md" <<'BLOCKSMD'
# Block Map

## B02 — second
- Status: Delivered
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U01
- Code: src/b.sh
- Contract: appears first in the file despite the higher block id
- Plan: plans/001-test.md

## B01 — first
- Status: Scaffolded
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U01
- Code: src/a.sh
- Contract: appears second in the file despite the lower block id
- Plan: plans/001-test.md
BLOCKSMD
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 mixedstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  status_file="$expected_wt/.local/status.md"
  if [ ! -f "$status_file" ]; then
    record_fail "expected seeded .local/status.md to exist"
    return
  fi

  blocks_lines="$(awk '/^## Blocks$/{f=1;next} /^## Timeline$/{f=0} f && /^- B/{print}' "$status_file")"
  line1="$(printf '%s\n' "$blocks_lines" | sed -n '1p')"
  line2="$(printf '%s\n' "$blocks_lines" | sed -n '2p')"
  assert_eq "- B02 — second: Delivered" "$line1" "first Blocks line follows blocks.md file order, not block-id order (multi-block unit)"
  assert_eq "- B01 — first: Scaffolded" "$line2" "second Blocks line follows blocks.md file order, not block-id order (multi-block unit)"
}

test_add_creates_empty_briefs_and_reports_dirs() {
  local repo expected_wt
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ -d "$expected_wt/.local/briefs" ]; then
    if [ -n "$(ls -A "$expected_wt/.local/briefs" 2>/dev/null)" ]; then
      record_fail "expected .local/briefs/ to be seeded as an empty directory"
    fi
  else
    record_fail "expected .local/briefs/ to be created"
  fi

  if [ -d "$expected_wt/.local/reports" ]; then
    if [ -n "$(ls -A "$expected_wt/.local/reports" 2>/dev/null)" ]; then
      record_fail "expected .local/reports/ to be seeded as an empty directory"
    fi
  else
    record_fail "expected .local/reports/ to be created"
  fi
}

test_add_status_md_deterministic() {
  local repoA repoB wtA wtB exitA exitB diffout
  repoA="$(GIT_AUTHOR_DATE='1577836800 +0000' GIT_COMMITTER_DATE='1577836800 +0000' new_git_repo)"
  write_config_json "$repoA" "true"
  write_blocks_md "$repoA"
  write_contracts "$repoA"
  repoB="$(GIT_AUTHOR_DATE='1577836800 +0000' GIT_COMMITTER_DATE='1577836800 +0000' new_git_repo)"
  write_config_json "$repoB" "true"
  write_blocks_md "$repoB"
  write_contracts "$repoB"

  if [ "$(git -C "$repoA" rev-parse HEAD)" != "$(git -C "$repoB" rev-parse HEAD)" ]; then
    record_fail "fixture bug: repoA and repoB HEAD shas differ despite pinned author/committer dates, cannot exercise determinism"
    return
  fi

  run_in "$repoA" add plan1 U01 greetstuff
  exitA="$RUN_EXIT"
  run_in "$repoB" add plan1 U01 greetstuff
  exitB="$RUN_EXIT"

  [ "$exitA" -eq 0 ] || record_fail "run A: expected exit 0, got $exitA"
  [ "$exitB" -eq 0 ] || record_fail "run B: expected exit 0, got $exitB"

  wtA="$(dirname "$repoA")/$(basename "$repoA")-U01"
  wtB="$(dirname "$repoB")/$(basename "$repoB")-U01"

  if [ -f "$wtA/.local/status.md" ] && [ -f "$wtB/.local/status.md" ]; then
    diffout="$(diff -u "$wtA/.local/status.md" "$wtB/.local/status.md" 2>&1)"
    if [ -n "$diffout" ]; then
      record_fail "status.md is not byte-identical across two 'add' runs from identical repo state and arguments (no timestamps/randomness): $diffout"
    fi
  else
    record_fail "expected .local/status.md to exist in both worktrees"
  fi
}

# ===========================================================================
# add: layered config resolution (NEW/CHANGED, plan 001-lc)
#
# Effective config = jq recursive merge (.[0] * .[1]) of .claude/lego.json
# (committed base, read first) and .local/config.json (gitignored override,
# read second, wins per key). Fixtures below deliberately construct cases
# the OLD single-file (.local/config.json only) implementation cannot
# satisfy by coincidence, so a red run here reflects a real gap rather than
# an accident of the old error paths (e.g. old code's hard requirement that
# .local/config.json exist would itself produce exit 3/4 for the wrong
# reason if a fixture only supplied .claude/lego.json or only relied on
# object-form commands.test).
# ===========================================================================

test_config_base_only_resolves_and_seeds_without_local_override() {
  local repo expected_wt base_content_before base_content_after
  repo="$(new_git_repo)"
  write_base_config "$repo" '{"commands":{"test":"printf BASE_ONLY > MARKER; true"},"delivery":{"worktreeDir":"../basewt"}}'
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/basewt/$(basename "$repo")-U01"
  base_content_before="$(cat "$repo/.claude/lego.json")"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "only .claude/lego.json exists (no .local/config.json anywhere): expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "$expected_wt" "$RUN_OUT_LAST" "delivery.worktreeDir resolved from the base-only effective config"

  if [ -f "$expected_wt/MARKER" ]; then
    assert_eq "BASE_ONLY" "$(cat "$expected_wt/MARKER")" "baseline test command resolved from the base-only effective config actually ran"
  else
    record_fail "expected baseline MARKER file written by the base-resolved test command"
  fi

  if [ ! -f "$expected_wt/.claude/lego.json" ]; then
    record_fail "expected the committed .claude/lego.json to reach the new worktree via git checkout (not explicit seeding)"
  fi
  if [ -e "$expected_wt/.local/config.json" ]; then
    record_fail "no .local/config.json existed in the invoking worktree to copy; the new worktree should not have one either (absence is not an error)"
  fi

  base_content_after="$(cat "$repo/.claude/lego.json" 2>/dev/null)"
  assert_eq "$base_content_before" "$base_content_after" "committed .claude/lego.json in the invoking worktree is never written by add (read-only input)"
}

test_config_invalid_json_exit3() {
  local repo
  repo="$(new_git_repo)"
  write_base_config "$repo" '{not valid json'
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "invalid JSON in committed .claude/lego.json, even though .local/config.json alone would otherwise be sufficient: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "invalid JSON in base config"

  local repo2
  repo2="$(new_git_repo)"
  write_base_config "$repo2" '{"commands":{"test":"true"}}'
  write_override_config "$repo2" '{not valid json'
  write_blocks_md "$repo2"
  write_contracts "$repo2"

  run_in "$repo2" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "invalid JSON in .local/config.json override, even though .claude/lego.json alone would otherwise be sufficient: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "invalid JSON in override config"
}

test_config_commands_test_object_errors() {
  local repo
  repo="$(new_git_repo)"
  write_override_config "$repo" '{"commands":{"test":{"main":"true"}}}'
  write_blocks_md "$repo"
  write_contracts "$repo"
  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "object-form commands.test without a 'default' key: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "object commands.test missing default"

  local repo2
  repo2="$(new_git_repo)"
  write_override_config "$repo2" '{"commands":{"test":{"main":"true","default":"missing"}}}'
  write_blocks_md "$repo2"
  write_contracts "$repo2"
  run_in "$repo2" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "'default' names a variant that does not exist: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "default names an absent variant"

  local repo3
  repo3="$(new_git_repo)"
  write_override_config "$repo3" '{"commands":{"test":{"main":"","default":"main"}}}'
  write_blocks_md "$repo3"
  write_contracts "$repo3"
  run_in "$repo3" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "'default' names a variant whose value is an empty string: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "default names an empty-string variant"
}

test_config_commands_test_object_resolves_default_variant() {
  local repo expected_wt
  repo="$(new_git_repo)"
  write_override_config "$repo" '{"commands":{"test":{"main":"printf MAIN > MARKER; true","other":"printf OTHER > MARKER; true","default":"main"}}}'
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "object-form commands.test with a valid default: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ -f "$expected_wt/MARKER" ]; then
    assert_eq "MAIN" "$(cat "$expected_wt/MARKER")" "resolved and ran the variant named by 'default' ('main'), proving 'default' is used as a key reference and never itself eval'd as a command"
  else
    record_fail "expected baseline MARKER file from the resolved 'main' variant"
  fi
}

test_config_merge_nested_object_override_wins_default_key() {
  local repo expected_wt
  repo="$(new_git_repo)"
  write_base_config "$repo" '{"commands":{"test":{"fast":"printf FAST > MARKER; true","slow":"printf SLOW > MARKER; true","default":"fast"}}}'
  write_override_config "$repo" '{"commands":{"test":{"default":"slow"}}}'
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "recursive merge of a nested commands.test object: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ -f "$expected_wt/MARKER" ]; then
    assert_eq "SLOW" "$(cat "$expected_wt/MARKER")" "override's 'default' wins per-key while base's variant definitions ('fast'/'slow') survive the merge -- if commands.test were replaced wholesale by the override object instead of merged per key, 'slow' would be undefined and this would fail as an unresolvable default (exit 3), not succeed"
  else
    record_fail "expected baseline MARKER file from the resolved 'slow' variant (defined only in base, selected by override's 'default')"
  fi
}

test_config_merge_combines_base_and_override_keys() {
  local repo expected_wt base_before base_after override_before override_after
  repo="$(new_git_repo)"
  write_base_config "$repo" '{"commands":{"test":"printf BASE_CMD > MARKER; true"},"delivery":{"worktreeDir":"../basewt"}}'
  write_override_config "$repo" '{"commands":{"test":"printf OVERRIDE_CMD > MARKER; true"}}'
  write_blocks_md "$repo"
  write_contracts "$repo"
  expected_wt="$(dirname "$repo")/basewt/$(basename "$repo")-U01"
  base_before="$(cat "$repo/.claude/lego.json")"
  override_before="$(cat "$repo/.local/config.json")"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "merge of base+override across different top-level keys: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "$expected_wt" "$RUN_OUT_LAST" "delivery.worktreeDir inherited from base when the override does not set it"

  if [ -f "$expected_wt/MARKER" ]; then
    assert_eq "OVERRIDE_CMD" "$(cat "$expected_wt/MARKER")" "commands.test from the override wins over base's value for the same key"
  else
    record_fail "expected baseline MARKER file from the override-resolved test command"
  fi

  base_after="$(cat "$repo/.claude/lego.json" 2>/dev/null)"
  override_after="$(cat "$repo/.local/config.json" 2>/dev/null)"
  assert_eq "$base_before" "$base_after" "committed .claude/lego.json unchanged by add (read-only input)"
  assert_eq "$override_before" "$override_after" "invoking worktree's .local/config.json unchanged by add (read-only input; only the seeded copy in the new worktree is written)"
}

# ===========================================================================
# merge
#
# merge <plan-slug> <unit-id> <unit-slug> -- construct_unit_branch replaces
# the old glob-based resolve_unit_branch: the branch name is built directly
# from the three arguments, so "multiple branches found" is no longer
# possible. What used to be tested as ambiguity is now tested as cross-plan
# isolation: a same-unit-id branch under a different plan must never be
# picked up or touched.
# ===========================================================================

test_merge_usage() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" merge
  [ "$RUN_EXIT" -eq 2 ] || record_fail "no args: expected exit 2, got $RUN_EXIT"

  run_in "$repo" merge plan1
  [ "$RUN_EXIT" -eq 2 ] || record_fail "1 arg: expected exit 2, got $RUN_EXIT"

  run_in "$repo" merge plan1 U01
  [ "$RUN_EXIT" -eq 2 ] || record_fail "2 args: expected exit 2, got $RUN_EXIT"

  run_in "$repo" merge plan1 U01 greetstuff extra
  [ "$RUN_EXIT" -eq 2 ] || record_fail "4 args: expected exit 2, got $RUN_EXIT"
}

test_merge_invalid_chars() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" merge "plan slug" U01 greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "space in plan-slug: expected exit 2, got $RUN_EXIT"

  run_in "$repo" merge plan1 "U0/1" greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "slash in unit-id: expected exit 2, got $RUN_EXIT"

  run_in "$repo" merge plan1 U01 'slug;rm'
  [ "$RUN_EXIT" -eq 2 ] || record_fail "semicolon in unit-slug: expected exit 2, got $RUN_EXIT"
}

test_merge_no_branch_match() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "constructed branch absent: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "constructed branch absent (also proves construct_unit_branch never itself calls die/err on a lookup miss: a second 'ERROR:' line would fail this assertion)"
}

test_merge_branch_construction_deterministic() {
  local repoA repoB branch
  branch="lego/plan1/U01-greetstuff"

  repoA="$(new_git_repo)"
  git -C "$repoA" checkout -q -b "$branch"
  git -C "$repoA" commit -q --allow-empty -m "unit work"
  git -C "$repoA" checkout -q master

  repoB="$(new_git_repo)"
  git -C "$repoB" checkout -q -b "$branch"
  git -C "$repoB" commit -q --allow-empty -m "unit work"
  git -C "$repoB" checkout -q master

  run_in "$repoA" merge plan1 U01 greetstuff
  local exitA="$RUN_EXIT"
  local subjectA
  subjectA="$(git -C "$repoA" log -1 --format=%s HEAD 2>/dev/null || echo "")"

  run_in "$repoB" merge plan1 U01 greetstuff
  local exitB="$RUN_EXIT"
  local subjectB
  subjectB="$(git -C "$repoB" log -1 --format=%s HEAD 2>/dev/null || echo "")"

  [ "$exitA" -eq 0 ] || record_fail "run A: expected exit 0, got $exitA"
  [ "$exitB" -eq 0 ] || record_fail "run B: expected exit 0, got $exitB"
  assert_eq "$subjectA" "$subjectB" "identical repo state and args construct the identical branch name (construct_unit_branch is deterministic)"
  assert_eq "lego: merge $branch" "$subjectA" "constructed branch name lego/<plan-slug>/<unit-id>-<unit-slug> appears verbatim in the merge commit subject"
}

test_merge_dirty_tracked_tree_refuses() {
  local repo
  repo="$(new_git_repo)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff"
  git -C "$repo" commit -q --allow-empty -m "unit work"
  git -C "$repo" checkout -q master

  printf 'uncommitted change\n' >> "$repo/README.md"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "dirty tracked tree: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "dirty tracked tree"
}

test_merge_untracked_only_does_not_block() {
  local repo
  repo="$(new_git_repo)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff"
  printf 'feature\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "unit work"
  git -C "$repo" checkout -q master

  printf 'scratch\n' > "$repo/scratch.txt"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "untracked-only tree should not block merge: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
}

test_merge_success() {
  local repo branch head_before
  repo="$(new_git_repo)"
  branch="lego/plan1/U01-greetstuff"
  git -C "$repo" checkout -q -b "$branch"
  printf 'feature content\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "unit work"
  git -C "$repo" checkout -q master
  head_before="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  local head_after
  head_after="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo "")"
  if [ -z "$head_after" ] || [ "$head_after" = "$head_before" ]; then
    record_fail "expected HEAD to advance via a merge commit"
  else
    local subject parents
    subject="$(git -C "$repo" log -1 --format=%s HEAD 2>/dev/null || echo "")"
    assert_eq "lego: merge $branch" "$subject" "merge commit subject"
    parents="$(git -C "$repo" log -1 --format=%P HEAD 2>/dev/null | wc -w | tr -d ' ')"
    assert_eq "2" "$parents" "merge commit has two parents (--no-ff)"
    if [ ! -f "$repo/feature.txt" ]; then
      record_fail "expected feature.txt introduced by unit branch to be present after merge"
    fi
  fi

  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    record_fail "invoking worktree has uncommitted changes after merge (INV1 violation)"
  fi
}

test_merge_cross_plan_isolation() {
  local repo branchA branchB shaB_before
  repo="$(new_git_repo)"
  branchA="lego/planA/U01-foo"
  branchB="lego/planB/U01-bar"

  git -C "$repo" checkout -q -b "$branchA"
  printf 'planA feature\n' > "$repo/planA.txt"
  git -C "$repo" add planA.txt
  git -C "$repo" commit -q -m "planA unit work"
  git -C "$repo" checkout -q master

  git -C "$repo" checkout -q -b "$branchB"
  printf 'planB feature\n' > "$repo/planB.txt"
  git -C "$repo" add planB.txt
  git -C "$repo" commit -q -m "planB unit work"
  git -C "$repo" checkout -q master

  shaB_before="$(git -C "$repo" rev-parse "$branchB")"

  run_in "$repo" merge planA U01 foo
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ ! -f "$repo/planA.txt" ]; then
    record_fail "expected planA's branch to have been merged (planA.txt present)"
  fi
  if [ -f "$repo/planB.txt" ]; then
    record_fail "expected planB's same-unit-id branch to be left untouched by 'merge planA U01 foo' (planB.txt should not be present)"
  fi

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branchB"; then
    record_fail "expected planB's branch $branchB to still exist"
  fi
  local shaB_after
  shaB_after="$(git -C "$repo" rev-parse "$branchB" 2>/dev/null || echo "")"
  assert_eq "$shaB_before" "$shaB_after" "planB's branch ref is byte-for-byte unchanged (construct_unit_branch is a pure lookup: it never creates, deletes, or modifies any ref)"
}

# ---------------------------------------------------------------------------
# merge: guard_merge_context (B01 merge-self-guard)
# ---------------------------------------------------------------------------

test_merge_guard_current_branch_is_unit_branch_refuses() {
  local repo current_branch target_branch current_sha target_sha
  repo="$(new_git_repo)"
  target_branch="lego/planB/U05-target"
  current_branch="lego/plan1/U02-current"

  git -C "$repo" checkout -q -b "$target_branch"
  commit_file "$repo" "target-feature.txt" "target feature" "unit work"
  git -C "$repo" checkout -q master
  git -C "$repo" checkout -q -b "$current_branch"

  current_sha="$(git -C "$repo" rev-parse HEAD)"
  target_sha="$(git -C "$repo" rev-parse "$target_branch")"

  run_in "$repo" merge planB U05 target
  [ "$RUN_EXIT" -eq 4 ] || record_fail "current branch matches unit-branch pattern: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "current branch matches unit-branch pattern"
  assert_eq "ERROR: merge must run from the integration worktree, not a unit worktree (current branch: $current_branch)" "$RUN_ERR" "unit-worktree guard error message"

  # Invariant: pure read -- no refs, files, or worktrees modified on refusal.
  assert_eq "$current_sha" "$(git -C "$repo" rev-parse HEAD)" "current branch HEAD unchanged after refused merge"
  assert_eq "$target_sha" "$(git -C "$repo" rev-parse "$target_branch")" "target branch ref unchanged after refused merge"
  assert_eq "$current_branch" "$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo "")" "still checked out on current branch (no branch switch, no detach)"
  if [ -e "$repo/.git/MERGE_HEAD" ]; then
    record_fail "no merge should have been attempted (MERGE_HEAD present)"
  fi

  # Invariant: deterministic -- rerunning against unchanged repo state gives
  # the identical result.
  run_in "$repo" merge planB U05 target
  [ "$RUN_EXIT" -eq 4 ] || record_fail "second run: expected exit 4, got $RUN_EXIT"
  assert_eq "ERROR: merge must run from the integration worktree, not a unit worktree (current branch: $current_branch)" "$RUN_ERR" "second run: identical error message (deterministic)"
}

test_merge_guard_self_merge_refuses() {
  local repo branch sha
  repo="$(new_git_repo)"
  # "foo" does not start with "U", so this branch does NOT match the
  # lego/*/U*-* unit-branch pattern -- isolates check (2) from check (1).
  branch="lego/plan1/foo-bar"

  git -C "$repo" checkout -q -b "$branch"
  sha="$(git -C "$repo" rev-parse HEAD)"

  run_in "$repo" merge plan1 foo bar
  [ "$RUN_EXIT" -eq 4 ] || record_fail "self-merge (target == current, current not a unit branch): expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "self-merge"
  assert_eq "ERROR: cannot merge a branch into itself (branch: $branch)" "$RUN_ERR" "self-merge guard error message"

  # Invariant: pure read -- no refs, files, or worktrees modified on refusal.
  assert_eq "$sha" "$(git -C "$repo" rev-parse HEAD)" "branch HEAD unchanged after refused self-merge"
  assert_eq "$branch" "$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo "")" "still checked out on same branch"
  if [ -e "$repo/.git/MERGE_HEAD" ]; then
    record_fail "no merge should have been attempted (MERGE_HEAD present)"
  fi
}

test_merge_guard_non_unit_lego_branch_as_current_succeeds() {
  local repo current branch head_before
  repo="$(new_git_repo)"
  # "foo-bar" has no U*-* trailing segment, so this current branch does NOT
  # match lego/*/U*-* even though it lives under "lego/" like a unit branch.
  current="lego/plan1/foo-bar"
  branch="lego/plan2/U01-feature"

  git -C "$repo" checkout -q -b "$current"
  head_before="$(git -C "$repo" rev-parse HEAD)"

  git -C "$repo" checkout -q -b "$branch" master
  printf 'feature content\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "unit work"
  git -C "$repo" checkout -q "$current"

  run_in "$repo" merge plan2 U01 feature
  [ "$RUN_EXIT" -eq 0 ] || record_fail "non-unit lego/* current branch: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "" "$RUN_ERR" "guard passes silently: no stderr on success"

  local head_after
  head_after="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo "")"
  if [ -z "$head_after" ] || [ "$head_after" = "$head_before" ]; then
    record_fail "expected HEAD to advance via a merge commit"
  else
    local subject parents
    subject="$(git -C "$repo" log -1 --format=%s HEAD 2>/dev/null || echo "")"
    assert_eq "lego: merge $branch" "$subject" "merge commit subject"
    parents="$(git -C "$repo" log -1 --format=%P HEAD 2>/dev/null | wc -w | tr -d ' ')"
    assert_eq "2" "$parents" "merge commit has two parents (--no-ff)"
    if [ ! -f "$repo/feature.txt" ]; then
      record_fail "expected feature.txt introduced by unit branch to be present after merge"
    fi
  fi
}

test_merge_guard_detached_head_succeeds() {
  local repo branch base_sha
  repo="$(new_git_repo)"
  branch="lego/plan1/U01-greetstuff"
  base_sha="$(git -C "$repo" rev-parse HEAD)"

  git -C "$repo" checkout -q -b "$branch"
  printf 'feature content\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "unit work"
  git -C "$repo" checkout -q --detach "$base_sha"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "detached HEAD as current branch: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "" "$RUN_ERR" "guard passes silently: no stderr on success"

  if [ ! -f "$repo/feature.txt" ]; then
    record_fail "expected feature.txt introduced by unit branch to be present after merge"
  fi

  local head_after
  head_after="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo "")"
  if [ -z "$head_after" ] || [ "$head_after" = "$base_sha" ]; then
    record_fail "expected HEAD to advance via a merge commit"
  fi
  if git -C "$repo" symbolic-ref -q HEAD >/dev/null 2>&1; then
    record_fail "expected HEAD to remain detached after merging from a detached HEAD (no branch was ever current)"
  fi
}

test_merge_guard_runs_before_dirty_tree_check() {
  local repo current_branch target_branch
  repo="$(new_git_repo)"
  target_branch="lego/planB/U05-target"
  current_branch="lego/plan1/U02-current"

  git -C "$repo" checkout -q -b "$target_branch"
  commit_file "$repo" "target-feature.txt" "target feature" "unit work"
  git -C "$repo" checkout -q master
  git -C "$repo" checkout -q -b "$current_branch"

  # Dirty tracked tree AND current branch matches the unit-branch pattern:
  # per the contract, guard_merge_context runs before the dirty-tree check,
  # so the unit-worktree error must win, not the dirty-tree error.
  printf 'uncommitted change\n' >> "$repo/README.md"

  run_in "$repo" merge planB U05 target
  [ "$RUN_EXIT" -eq 4 ] || record_fail "expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "guard should fire before the dirty-tree check"
  assert_eq "ERROR: merge must run from the integration worktree, not a unit worktree (current branch: $current_branch)" "$RUN_ERR" "unit-worktree guard message wins over the dirty-tree message when both conditions hold"
}

test_merge_guard_check_order_unit_branch_before_self_merge() {
  local repo branch
  repo="$(new_git_repo)"
  branch="lego/plan1/U01-greetstuff"

  git -C "$repo" checkout -q -b "$branch"

  # Current branch matches the unit-branch pattern AND target == current:
  # both check (1) and check (2) conditions hold simultaneously. Per the
  # contract's enumeration order ("(1) ... (2) ..."), check (1) must be
  # evaluated first.
  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "check ordering"
  assert_eq "ERROR: merge must run from the integration worktree, not a unit worktree (current branch: $branch)" "$RUN_ERR" "check (1) unit-worktree guard fires before check (2) self-merge guard when both apply"
}

# ===========================================================================
# deliver
#
# deliver <plan-slug> <base-branch> <unit-id> <unit-slug> [<unit-id>
# <unit-slug>...] -- as with merge, exact construction removes the old
# "multiple branches found" ambiguity error; cross-plan isolation replaces
# it as the thing worth testing.
# ===========================================================================

test_deliver_usage() {
  local repo manifest
  repo="$(new_git_repo)"
  # --manifest is parsed and required *before* the positional-argument usage
  # check (cmd_deliver checks manifest-presence first), so every one of
  # these usage-error invocations must carry a --manifest flag itself, or
  # they would now die exit 3 ("--manifest is required") instead of
  # exercising the exit-2 usage path this test is about. The path is never
  # read on any of these (usage_die fires first), so it need not exist.
  manifest="$repo/unused-manifest.json"

  run_in "$repo" deliver --manifest "$manifest"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "no args: expected exit 2, got $RUN_EXIT"

  run_in "$repo" deliver --manifest "$manifest" plan1
  [ "$RUN_EXIT" -eq 2 ] || record_fail "1 arg: expected exit 2, got $RUN_EXIT"

  run_in "$repo" deliver --manifest "$manifest" plan1 master
  [ "$RUN_EXIT" -eq 2 ] || record_fail "2 args (plan-slug + base-branch, no unit id/slug pair): expected exit 2, got $RUN_EXIT"

  run_in "$repo" deliver --manifest "$manifest" plan1 master U01
  [ "$RUN_EXIT" -eq 2 ] || record_fail "3 args (dangling unit-id with no matching slug): expected exit 2, got $RUN_EXIT"
}

test_deliver_odd_paired_args() {
  local repo manifest
  repo="$(new_git_repo)"
  manifest="$repo/unused-manifest.json"

  run_in "$repo" deliver --manifest "$manifest" plan1 master U01 greetstuff U02
  [ "$RUN_EXIT" -eq 2 ] || record_fail "odd count of unit-id/unit-slug args after plan-slug+base-branch (U02 has no matching slug): expected exit 2, got $RUN_EXIT"
}

test_deliver_invalid_chars() {
  local repo manifest
  repo="$(new_git_repo)"
  manifest="$repo/unused-manifest.json"

  run_in "$repo" deliver --manifest "$manifest" "plan slug" master U01 greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "space in plan-slug: expected exit 2, got $RUN_EXIT"

  run_in "$repo" deliver --manifest "$manifest" plan1 "master;rm" U01 greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "invalid char in base-branch: expected exit 2, got $RUN_EXIT"

  run_in "$repo" deliver --manifest "$manifest" plan1 master "U0/1" greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "invalid char in unit-id: expected exit 2, got $RUN_EXIT"

  run_in "$repo" deliver --manifest "$manifest" plan1 master U01 'slug;rm'
  [ "$RUN_EXIT" -eq 2 ] || record_fail "invalid char in unit-slug: expected exit 2, got $RUN_EXIT"
}

test_deliver_manifest_flag_required() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  run_in "$repo" deliver plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "deliver without --manifest: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "deliver without --manifest"
}

test_deliver_missing_gh() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet_test.sh" "greet test v1" "lego(U01): tests"
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # require_gh fires before the manifest file is ever opened, so the
  # manifest just needs to be present as a flag; its content (and even
  # whether the path exists) is irrelevant to this error path.
  local path_no_gh
  path_no_gh="$(path_without gh)"
  run_cmd "$repo" "$path_no_gh" deliver --manifest "$repo/unused-manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "gh absent: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "gh absent"
}

test_deliver_missing_dependencies() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # jq/config.json/blocks.md are all required before the manifest file is
  # read, so --manifest just needs to be present here too; content/existence
  # of the manifest path is irrelevant to these error paths.
  local path_no_jq
  path_no_jq="$(path_without jq)"
  run_cmd "$repo" "$path_no_jq" deliver --manifest "$repo/unused-manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "jq absent: expected exit 3, got $RUN_EXIT"

  local repo2
  repo2="$(new_git_repo)"
  write_blocks_md "$repo2"
  run_in "$repo2" deliver --manifest "$repo2/unused-manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "config.json missing: expected exit 3, got $RUN_EXIT"

  local repo3
  repo3="$(new_git_repo)"
  write_config_json "$repo3" "true"
  run_in "$repo3" deliver --manifest "$repo3/unused-manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "blocks.md missing: expected exit 3, got $RUN_EXIT"
}

test_deliver_zero_branch_match() {
  local repo manifest
  repo="$(build_deliver_base)"
  manifest="$(write_valid_manifest "$repo" "test: zero branch match" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" deliver --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "constructed unit branch absent: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "constructed unit branch absent"
}

test_deliver_cross_plan_isolation() {
  local repo
  repo="$(build_deliver_base)"
  # A same-unit-id branch under a different plan must never be picked up by
  # exact construction, and must be untouched by plan1's delivery.
  git -C "$repo" checkout -q -b "lego/planB/U01-otherslug" master
  commit_file "$repo" "src/greet.sh" "should never be delivered" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1 (plan1)" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: cross plan isolation" "lego/deliver/plan1/U01" U01)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  else
    local greet_content
    greet_content="$(git -C "$repo" show "lego/deliver/plan1/U01:src/greet.sh" 2>/dev/null || echo "MISSING")"
    assert_eq "greet v1 (plan1)" "$greet_content" "delivered content comes from plan1's exact branch, not planB's same-unit-id branch"
  fi

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/lego/planB/U01-otherslug"; then
    record_fail "expected planB's branch lego/planB/U01-otherslug to remain untouched by delivering plan1's unit"
  fi
}

# Regression test for the "stray same-subject commit from an old plan"
# defect: unit ids (U01, U02, ...) recur across plans, so a commit-subject
# scan over a unit branch's ENTIRE history can surface an unrelated OLD
# commit that happens to share the exact subject "lego(U01): tests" but
# was inherited from the base branch's history long before the current
# unit branch forked. Before the fix, that stray commit was picked as
# tests_sha and restore_and_commit's `git checkout <stray-sha> --
# <unit-paths>` failed outright (none of the paths exist at that ancient
# tree), and deliver died exit 4. The fix scopes the commit-subject lookup
# to the fork range `<base>..<branch>` (commits reachable from the unit
# branch but not from the base branch it forked from), so the stray commit
# -- reachable via the base -- is never a candidate: the tests restore is
# skipped (as if no tests commit existed) and the impl commit still
# delivers cleanly.
test_deliver_stale_tests_commit_in_base_history_is_skipped() {
  local repo root_sha
  repo="$(build_deliver_base)"
  root_sha="$(git -C "$repo" rev-list --max-parents=0 master)"

  # An OLD plan's history, reachable via master, containing a commit with
  # the exact subject a fresh U01 tests commit would use -- but at a point
  # before any of U01's current Code paths (src/greet.sh etc.) existed,
  # and touching only an unrelated path.
  git -C "$repo" checkout -q "$root_sha"
  git -C "$repo" checkout -q -b old-plan-history
  commit_file "$repo" "src/old-plan-artifact.sh" "old plan artifact" "lego(U01): tests"
  git -C "$repo" checkout -q master
  git -C "$repo" merge -q --no-ff old-plan-history -m "merge old plan history into master" >/dev/null

  # The current U01 branch never gets its own tests commit -- only impl.
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  mkdir -p "$repo/.local"
  jq -n '{title: "test: stale tests subject outside unit paths", branch: "lego/deliver/plan1/U01", commits: {U01: {impl: "lego(U01): implementation"}}}' \
    > "$repo/.local/manifest.json"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "stale cross-history same-subject commit must be skipped, not fatal: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    local subjects
    # Scoped to the delivery branch's own range past master: the stray
    # commit is legitimately reachable via master (it was merged into
    # master above), so it would appear in the full log even on correct
    # behavior. Only commits master..lego/deliver/plan1/U01 tell us what
    # deliver actually restored/committed.
    subjects="$(git -C "$repo" log --format=%s master..lego/deliver/plan1/U01 2>/dev/null)"
    if printf '%s\n' "$subjects" | grep -qF "lego(U01): tests"; then
      record_fail "no in-scope tests commit existed for U01; delivery must not restore the stale out-of-scope tests commit"
    fi
    if ! printf '%s\n' "$subjects" | grep -qF "lego(U01): implementation"; then
      record_fail "expected delivery branch to contain the implementation commit"
    fi
    local greet_content
    greet_content="$(git -C "$repo" show "lego/deliver/plan1/U01:src/greet.sh" 2>/dev/null || echo "MISSING")"
    assert_eq "greet v1" "$greet_content" "delivered greet.sh content comes from the impl commit, not any stale restore"
  else
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  fi
}

test_deliver_unit_with_no_code_paths_fails() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U03-nocodeslug" master
  git -C "$repo" commit -q --allow-empty -m "lego(U03): implementation"
  git -C "$repo" checkout -q master

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: no code paths" "lego/deliver/plan1/U03" U03)"

  run_in "$repo" deliver --manifest "$manifest" plan1 master U03 nocodeslug
  [ "$RUN_EXIT" -eq 4 ] || record_fail "unit with no Code paths: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "unit with no Code paths (EC4)"
}

test_deliver_missing_implementation_commit_fails() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U04-needsimplslug" master
  commit_file "$repo" "src/needsimpl.sh" "needsimpl tests only" "lego(U04): tests"
  git -C "$repo" checkout -q master

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: missing impl commit" "lego/deliver/plan1/U04" U04)"

  run_in "$repo" deliver --manifest "$manifest" plan1 master U04 needsimplslug
  [ "$RUN_EXIT" -eq 4 ] || record_fail "missing implementation commit: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "missing implementation commit"
}

test_deliver_delivery_branch_already_exists() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  git -C "$repo" branch "lego/deliver/plan1/U01" master

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: delivery branch pre-exists" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" deliver --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "delivery branch pre-exists: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "delivery branch pre-exists (EC3)"
}

test_deliver_underlying_git_failure_on_push() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  git -C "$repo" remote set-url origin "/nonexistent/path/that/does/not/exist.git"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: unreachable origin" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" deliver --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "unreachable origin: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "unreachable origin (underlying git failure)"
}

test_deliver_tests_commit_optional_success() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo v1" "lego(U02): implementation"
  git -C "$repo" checkout -q master

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  # commits.U02.impl must equal the literal string this test asserts is on
  # the delivery branch, since impl subject is now always manifest-sourced
  # (impl is a required field with no default fallback once a manifest is
  # mandatory).
  mkdir -p "$repo/.local"
  jq -n '{title: "test: tests commit optional", branch: "lego/deliver/plan1/U02", commits: {U02: {impl: "lego(U02): implementation"}}}' \
    > "$repo/.local/manifest.json"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ "$RUN_OUT_LINES" -eq 1 ] || record_fail "expected exactly 1 stdout line (PR URL), got $RUN_OUT_LINES"
  assert_eq "https://github.com/example/lego-fixture/pull/123" "$RUN_OUT_LAST" "PR URL as last stdout line"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U02"; then
    local subjects
    subjects="$(git -C "$repo" log --format=%s lego/deliver/plan1/U02 2>/dev/null)"
    if printf '%s\n' "$subjects" | grep -qF "lego(U02): contract + tests"; then
      record_fail "no tests commit existed for U02; delivery must not fabricate a 'contract + tests' commit"
    fi
    if ! printf '%s\n' "$subjects" | grep -qF "lego(U02): implementation"; then
      record_fail "expected delivery branch to contain the implementation commit"
    fi
  else
    record_fail "expected delivery branch lego/deliver/plan1/U02 to exist"
  fi

  if git -C "$repo" worktree list | grep -q "deliver/plan1/U02"; then
    record_fail "expected the temporary delivery worktree to be removed after deliver (D4)"
  fi
}

test_deliver_single_unit_union_and_newest_and_spaces() {
  local repo master_tip
  repo="$(build_deliver_base)"
  master_tip="$(git -C "$repo" rev-parse master)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_files "$repo" "lego(U01): tests" \
    "src/greet_test.sh" $'greet test OLD\n' \
    "src/other.sh" $'other OLD\n'
  commit_files "$repo" "lego(U01): tests draft" \
    "src/greet_test.sh" $'should not be picked\n'
  commit_files "$repo" "lego(U01): tests" \
    "src/greet_test.sh" $'greet test NEW\n' \
    "src/other.sh" $'other NEW\n'
  commit_files "$repo" "unrelated work" \
    "src/needsimpl.sh" $'should not matter\n'
  commit_files "$repo" "lego(U01): implementation" \
    "src/greet.sh" $'greet NEW\n' \
    "src/dir with space/file.sh" $'spacey NEW\n'
  git -C "$repo" checkout -q master

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  # Manifest title mirrors the old default's shape ("lego: U01") since the
  # gh-args assertions below check for that pattern; branch/commit subjects
  # mirror the old defaults too, since the delivery-branch/commit-subject
  # assertions below check for those exact strings. This proves manifest
  # pass-through wiring, not the (now-removed) hardcoded defaults.
  mkdir -p "$repo/.local"
  jq -n '{title: "lego: U01", branch: "lego/deliver/plan1/U01",
          commits: {U01: {tests: "lego(U01): contract + tests", impl: "lego(U01): implementation"}}}' \
    > "$repo/.local/manifest.json"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ "$RUN_OUT_LINES" -eq 1 ] || record_fail "expected exactly 1 stdout line (PR URL), got $RUN_OUT_LINES"
  assert_eq "https://github.com/example/lego-fixture/pull/123" "$RUN_OUT_LAST" "PR URL as last stdout line"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  else
    local subjects
    subjects="$(git -C "$repo" log --format=%s lego/deliver/plan1/U01)"
    if ! printf '%s\n' "$subjects" | grep -qF "lego(U01): contract + tests"; then
      record_fail "expected 'lego(U01): contract + tests' commit on delivery branch"
    fi
    if ! printf '%s\n' "$subjects" | grep -qF "lego(U01): implementation"; then
      record_fail "expected 'lego(U01): implementation' commit on delivery branch"
    fi

    local delivery_merge_base
    delivery_merge_base="$(git -C "$repo" merge-base master lego/deliver/plan1/U01)"
    assert_eq "$master_tip" "$delivery_merge_base" "delivery branch is built from base-branch's tip (D1)"

    local tests_sha impl_sha
    tests_sha="$(git -C "$repo" log --format='%H %s' lego/deliver/plan1/U01 | grep -F ' lego(U01): contract + tests' | head -n1 | cut -d' ' -f1)"
    impl_sha="$(git -C "$repo" log --format='%H %s' lego/deliver/plan1/U01 | grep -F ' lego(U01): implementation' | head -n1 | cut -d' ' -f1)"

    if [ -n "$tests_sha" ]; then
      local greet_at_tests other_at_tests
      greet_at_tests="$(git -C "$repo" show "$tests_sha:src/greet.sh" 2>/dev/null || echo "MISSING")"
      other_at_tests="$(git -C "$repo" show "$tests_sha:src/other.sh" 2>/dev/null || echo "MISSING")"
      assert_eq "greet v0" "$greet_at_tests" "implementation-only path untouched by the tests-restore step"
      assert_eq "other NEW" "$other_at_tests" "tests-restore uses the newest exact-subject commit, not the decoy or the older one"
    else
      record_fail "could not locate the 'contract + tests' commit to inspect its content"
    fi

    if [ -n "$impl_sha" ]; then
      local greet_final testfile_final other_final spacey_final
      greet_final="$(git -C "$repo" show "$impl_sha:src/greet.sh" 2>/dev/null || echo "MISSING")"
      testfile_final="$(git -C "$repo" show "$impl_sha:src/greet_test.sh" 2>/dev/null || echo "MISSING")"
      other_final="$(git -C "$repo" show "$impl_sha:src/other.sh" 2>/dev/null || echo "MISSING")"
      spacey_final="$(git -C "$repo" show "$impl_sha:src/dir with space/file.sh" 2>/dev/null || echo "MISSING")"
      assert_eq "greet NEW" "$greet_final" "implementation restore updates greet.sh"
      assert_eq "greet test NEW" "$testfile_final" "tests-restore result persists after the implementation restore"
      assert_eq "other NEW" "$other_final" "union restore preserves B02's other.sh from the tests step (EC1)"
      assert_eq "spacey NEW" "$spacey_final" "union restore reaches the space-containing path from B02 (EC2)"
    else
      record_fail "could not locate the 'implementation' commit to inspect its content"
    fi
  fi

  if git -C "$repo" worktree list | grep -q "deliver/plan1/U01"; then
    record_fail "expected the temporary delivery worktree to be removed after deliver (D4)"
  fi

  if [ -s "$GH_SHIM_LOG" ]; then
    local ghargs
    ghargs="$(cat "$GH_SHIM_LOG")"
    case "$ghargs" in
      *"lego: "*"U01"*) : ;;
      *) record_fail "expected gh pr create invocation to carry a title starting 'lego: ' mentioning U01" ;;
    esac
    case "$ghargs" in
      *"## B01 — greet"*) : ;;
      *) record_fail "expected PR body to include the B01 heading line" ;;
    esac
    case "$ghargs" in
      *"- Contract: greets politely and covers the happy path"*) : ;;
      *) record_fail "expected PR body to include B01's Contract line" ;;
    esac
    case "$ghargs" in
      *"## B02 — other"*) : ;;
      *) record_fail "expected PR body to include the B02 heading line" ;;
    esac
    case "$ghargs" in
      *"- Contract: handles the other responsibilities of the unit"*) : ;;
      *) record_fail "expected PR body to include B02's Contract line" ;;
    esac
  else
    record_fail "expected gh to have been invoked (shim log is empty)"
  fi
}

test_deliver_multi_unit_branch_naming_and_pr_title_order() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet NEW" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo NEW" "lego(U02): implementation"
  git -C "$repo" checkout -q master

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  # Branch naming is no longer constructed by deliver at all -- it always
  # comes from the (now-required) manifest "branch" field. Use explicit
  # custom values (not the old "lego/deliver/.../U01+U02" / "lego: ..."
  # shapes) so a pass only proves the manifest value was honored, not that
  # it happens to coincide with a removed default.
  local manifest
  manifest="$(jq -n '{title: "Custom multi-unit title U01 U02", branch: "custom/multi-unit-delivery",
                       commits: {U01: {impl: "impl subject for U01"}, U02: {impl: "impl subject for U02"}}}')"
  printf '%s' "$manifest" > "$repo/.local/manifest.json"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/custom/multi-unit-delivery"; then
    record_fail "expected delivery branch 'custom/multi-unit-delivery' (manifest-provided) to exist"
  fi
  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01+U02"; then
    record_fail "expected the old constructed default branch name NOT to be created; branch is manifest-only now"
  fi

  if [ -s "$GH_SHIM_LOG" ]; then
    local ghargs u01_pos u02_pos
    ghargs="$(cat "$GH_SHIM_LOG")"
    case "$ghargs" in
      *"Custom multi-unit title U01 U02"*) : ;;
      *) record_fail "expected PR title to be the manifest-provided title" ;;
    esac
    if ! printf '%s' "$ghargs" | grep -qF "U01"; then
      record_fail "expected PR title/body to mention U01"
    fi
    if ! printf '%s' "$ghargs" | grep -qF "U02"; then
      record_fail "expected PR title/body to mention U02"
    fi
    u01_pos="${ghargs%%U01*}"
    u02_pos="${ghargs%%U02*}"
    if [ "${#u01_pos}" -ge "${#u02_pos}" ]; then
      record_fail "expected unit ids to be listed in argument order (U01 before U02)"
    fi
  else
    record_fail "expected gh to have been invoked (shim log is empty)"
  fi
}

test_deliver_multi_unit_argument_order_is_not_sorted() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet NEW" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo NEW" "lego(U02): implementation"
  git -C "$repo" checkout -q master

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  # The delivery branch name is now entirely manifest-provided (not
  # constructed from unit-id argument order at all), so branch naming no
  # longer proves anything about argument order. What still depends on
  # argument order is the PR body: ALL_HEADINGS is built by iterating
  # unit_ids in argument order, so delivering U02 before U01 must produce
  # B03's heading (U02's block) before B01's heading (U01's block) in the
  # default body, proving the iteration is positional, not sorted.
  local manifest
  manifest="$(jq -n '{title: "test: order not sorted", branch: "custom/order-test-branch",
                       commits: {U01: {impl: "impl subject for U01"}, U02: {impl: "impl subject for U02"}}}')"
  printf '%s' "$manifest" > "$repo/.local/manifest.json"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U02 soloslug U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/custom/order-test-branch"; then
    record_fail "expected delivery branch 'custom/order-test-branch' (manifest-provided, order-independent) to exist"
  fi

  if [ -s "$GH_SHIM_LOG" ]; then
    local ghargs b03_pos b01_pos
    ghargs="$(cat "$GH_SHIM_LOG")"
    if ! printf '%s' "$ghargs" | grep -qF "## B03 — solo"; then
      record_fail "expected PR body to include the B03 (U02's block) heading"
    fi
    if ! printf '%s' "$ghargs" | grep -qF "## B01 — greet"; then
      record_fail "expected PR body to include the B01 (U01's block) heading"
    fi
    b03_pos="${ghargs%%"## B03 — solo"*}"
    b01_pos="${ghargs%%"## B01 — greet"*}"
    if [ "${#b03_pos}" -ge "${#b01_pos}" ]; then
      record_fail "expected U02's heading (B03) before U01's heading (B01), reflecting argument order (U02 first), not sorted"
    fi
  else
    record_fail "expected gh to have been invoked (shim log is empty)"
  fi
}

test_deliver_noop_restore_creates_no_second_commit() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U05-noopslug" master
  commit_file "$repo" "src/noop.sh" "noop FINAL" "lego(U05): tests"
  # implementation commit deliberately does not touch src/noop.sh (B06's
  # only Code path); restoring it should therefore be a no-op.
  commit_file "$repo" "src/needsimpl.sh" "irrelevant change" "lego(U05): implementation"
  git -C "$repo" checkout -q master

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  # commits.U05.tests is deliberately left unset: this exercises the
  # optional-tests-subject fallback (B01 clause 6) at the same time, and the
  # default "lego(U05): contract + tests" is what the assertion below checks
  # for. impl's value is arbitrary since the restore is a no-op (no commit
  # is ever created from it).
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: noop restore" "lego/deliver/plan1/U05" U05)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U05 noopslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U05"; then
    local subjects impl_count
    subjects="$(git -C "$repo" log --format=%s lego/deliver/plan1/U05)"
    if ! printf '%s\n' "$subjects" | grep -qF "lego(U05): contract + tests"; then
      record_fail "expected 'lego(U05): contract + tests' commit"
    fi
    impl_count="$(printf '%s\n' "$subjects" | grep -cF "lego(U05): implementation")"
    if [ "$impl_count" -ne 0 ]; then
      record_fail "restoring an unchanged path should create no 'implementation' commit, found $impl_count"
    fi
  else
    record_fail "expected delivery branch lego/deliver/plan1/U05 to exist"
  fi
}

# ===========================================================================
# deliver --manifest (B01 deliver-manifest)
# ===========================================================================

test_deliver_manifest_invalid_file() {
  local repo
  repo="$(build_deliver_base)"
  # Manifest validation happens before any unit-branch resolution, so no
  # unit branch needs to exist to exercise this error path.

  run_in "$repo" deliver --manifest "$repo/.local/does-not-exist.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "unreadable manifest path: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "unreadable manifest path"
}

test_deliver_manifest_invalid_json() {
  local repo
  repo="$(build_deliver_base)"
  printf 'not { valid json' > "$repo/.local/manifest.json"

  run_in "$repo" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "manifest file is not valid JSON: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest file is not valid JSON"
}

test_deliver_manifest_missing_title() {
  local repo
  repo="$(build_deliver_base)"
  # Manifest validation (and thus this rejection) happens before any
  # unit-branch resolution, so no unit branch needs to exist.
  jq -n '{branch: "lego/deliver/plan1/U01", commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "manifest missing title: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest missing title"
  case "$RUN_ERR" in
    *title*) : ;;
    *) record_fail "expected error message to name the missing field (title): got [$RUN_ERR]" ;;
  esac
}

test_deliver_manifest_missing_branch() {
  local repo
  repo="$(build_deliver_base)"
  jq -n '{title: "test: missing branch", commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "manifest missing branch: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest missing branch"
  case "$RUN_ERR" in
    *branch*) : ;;
    *) record_fail "expected error message to name the missing field (branch): got [$RUN_ERR]" ;;
  esac
}

test_deliver_manifest_missing_unit_impl() {
  local repo
  repo="$(build_deliver_base)"

  # Single delivered unit, commits.<id>.impl absent entirely (no "commits"
  # key at all).
  jq -n '{title: "test: missing unit impl", branch: "lego/deliver/plan1/U01"}' \
    > "$repo/.local/manifest.json"
  run_in "$repo" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "manifest missing commits.U01.impl (no commits key): expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest missing commits.U01.impl (no commits key)"

  # Two delivered units: the first has a valid impl subject, the second
  # doesn't -- proves the check runs for every delivered unit-id, not just
  # the first.
  jq -n '{title: "test: missing unit impl multi", branch: "lego/deliver/plan1/U01+U02",
          commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"
  run_in "$repo" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff U02 soloslug
  [ "$RUN_EXIT" -eq 3 ] || record_fail "manifest missing commits.U02.impl (second of two units): expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest missing commits.U02.impl (second of two units)"
}

test_deliver_manifest_body_optional_default() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # A full manifest (title, branch, commits.U01.impl) but no "body": PR
  # body must fall back to the auto-generated headings+contracts default.
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: body optional" "lego/deliver/plan1/U01" U01)"

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ -s "$GH_SHIM_LOG" ]; then
    local ghargs
    ghargs="$(cat "$GH_SHIM_LOG")"
    case "$ghargs" in
      *"## B01 — greet"*) : ;;
      *) record_fail "expected the default auto-generated PR body when manifest omits 'body'" ;;
    esac
    case "$ghargs" in
      *"- Contract: greets politely and covers the happy path"*) : ;;
      *) record_fail "expected the default PR body to include B01's Contract line" ;;
    esac
  else
    record_fail "expected gh to have been invoked (shim log is empty)"
  fi
}

test_deliver_manifest_tests_subject_optional_default() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_files "$repo" "lego(U01): tests" "src/greet_test.sh" "greet test v1"
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # A full manifest but no commits.U01.tests: when a tests commit exists on
  # the unit branch, its delivered subject must fall back to the default
  # "lego(U01): contract + tests".
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: tests subject optional" "lego/deliver/plan1/U01" U01)"

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  else
    local subjects
    subjects="$(git -C "$repo" log --format=%s lego/deliver/plan1/U01)"
    if ! printf '%s\n' "$subjects" | grep -qF "lego(U01): contract + tests"; then
      record_fail "expected the default tests-commit subject when manifest omits commits.U01.tests"
    fi
  fi
}

test_deliver_manifest_title_override() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # branch and commits.U01.impl are also required now; fill them with
  # arbitrary valid values so this test isolates the title-override
  # behavior it's named for.
  jq -n '{title: "Custom PR Title", branch: "lego/deliver/plan1/U01", commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"
  local manifest_before
  manifest_before="$(cat "$repo/.local/manifest.json")"

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  local manifest_after
  manifest_after="$(cat "$repo/.local/manifest.json")"
  assert_eq "$manifest_before" "$manifest_after" "manifest file is read-only and must never be modified by deliver"

  if [ -s "$GH_SHIM_LOG" ]; then
    local ghargs
    ghargs="$(cat "$GH_SHIM_LOG")"
    case "$ghargs" in
      *"Custom PR Title"*) : ;;
      *) record_fail "expected gh pr create to be called with the manifest title override" ;;
    esac
    case "$ghargs" in
      *"lego: U01"*) record_fail "expected the default title 'lego: U01' NOT to be used when manifest overrides title" ;;
      *) : ;;
    esac
  else
    record_fail "expected gh to have been invoked (shim log is empty)"
  fi
}

test_deliver_manifest_body_override() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # title and branch and commits.U01.impl are also required now; fill them
  # with arbitrary valid values so this test isolates the body-override
  # behavior it's named for.
  jq -n '{title: "test: body override", body: "Custom PR body text",
          branch: "lego/deliver/plan1/U01", commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ -s "$GH_SHIM_LOG" ]; then
    local ghargs
    ghargs="$(cat "$GH_SHIM_LOG")"
    case "$ghargs" in
      *"Custom PR body text"*) : ;;
      *) record_fail "expected gh pr create to be called with the manifest body override" ;;
    esac
    case "$ghargs" in
      *"## B01 — greet"*) record_fail "expected the default body heading NOT to appear when manifest overrides body" ;;
      *) : ;;
    esac
  else
    record_fail "expected gh to have been invoked (shim log is empty)"
  fi
}

test_deliver_manifest_branch_override() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # title and commits.U01.impl are also required now; fill them with
  # arbitrary valid values so this test isolates the branch-override
  # behavior it's named for.
  jq -n '{title: "test: branch override", branch: "custom/delivery-branch",
          commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/custom/delivery-branch"; then
    record_fail "expected delivery branch 'custom/delivery-branch' (manifest override) to exist"
  fi
  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    record_fail "expected the default delivery branch name NOT to be created when manifest overrides branch"
  fi
}

test_deliver_manifest_commit_subjects_override() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_files "$repo" "lego(U01): tests" "src/greet_test.sh" "greet test v1"
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # title and branch are also required now; fill them with arbitrary valid
  # values so this test isolates the commit-subject-override behavior it's
  # named for.
  jq -n '{title: "test: commit subjects override", branch: "lego/deliver/plan1/U01",
          commits: {U01: {tests: "custom tests subject", impl: "custom impl subject"}}}' \
    > "$repo/.local/manifest.json"

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  else
    local subjects
    subjects="$(git -C "$repo" log --format=%s lego/deliver/plan1/U01)"
    if ! printf '%s\n' "$subjects" | grep -qF "custom tests subject"; then
      record_fail "expected delivery branch to carry the manifest override tests-commit subject"
    fi
    if ! printf '%s\n' "$subjects" | grep -qF "custom impl subject"; then
      record_fail "expected delivery branch to carry the manifest override implementation-commit subject"
    fi
    if printf '%s\n' "$subjects" | grep -qF "lego(U01): contract + tests"; then
      record_fail "expected the default tests-commit subject NOT to be used when manifest overrides it"
    fi
    if printf '%s\n' "$subjects" | grep -qF "lego(U01): implementation"; then
      record_fail "expected the default implementation-commit subject NOT to be used when manifest overrides it"
    fi
  fi
}

test_deliver_manifest_partial() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # Only "title" is set. Under the old contract, branch/body/commits fell
  # back to defaults; under B01's required-fields contract, "branch" and
  # "commits.U01.impl" are mandatory, so this now must be rejected exit 3
  # rather than silently deliver with defaults filled in.
  printf '{"title": "Only Title Overridden"}' > "$repo/.local/manifest.json"

  # Deterministic isolation, same rationale as
  # test_deliver_manifest_branch_already_exists: a stub/buggy
  # implementation that doesn't validate would otherwise fall through to a
  # real, unauthenticated `gh pr create`.
  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "partial manifest missing branch/commits.impl: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "partial manifest missing required fields"
}

test_deliver_manifest_branch_already_exists() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  git -C "$repo" branch "custom/delivery-branch" master

  # title and commits.U01.impl are also required now; the branch-collision
  # check (line ~701) runs after validate_manifest_required_fields (line
  # ~682), so a manifest missing them would be rejected exit 3 before ever
  # reaching the collision check this test is about.
  jq -n '{title: "test: branch already exists", branch: "custom/delivery-branch",
          commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"

  # Use the gh shim so this test is deterministic and isolates the branch-
  # collision check: without it, a correct implementation still exits 4
  # before ever invoking gh, but a stubbed implementation that ignores the
  # manifest branch override would fall through to a real, unauthenticated
  # `gh pr create` and could exit non-zero for an unrelated reason (network/
  # auth failure) instead of failing on the intended assertion.
  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "manifest branch already exists: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest branch already exists"
}

test_deliver_manifest_empty_object() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # Under the old contract an empty object meant "use every default"; under
  # B01's required-fields contract it means "every required field is
  # absent", so this must now be rejected exit 3.
  printf '{}' > "$repo/.local/manifest.json"

  # Deterministic isolation, same rationale as
  # test_deliver_manifest_branch_already_exists.
  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"

  run_cmd "$repo" "$newpath" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "empty object manifest missing required fields: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "empty object manifest missing required fields"
}

test_deliver_manifest_empty_string_field_treated_as_absent() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # An explicit empty string "" for any required field must be treated the
  # same as the field being absent entirely (manifest_field's null/empty
  # contract): B01's required-field validation rejects it exit 3. Cover
  # each required field independently (title, branch, commits.U01.impl) so
  # the empty-string special case is proven for all of them, not just one.

  printf '{"title": "", "branch": "lego/deliver/plan1/U01", "commits": {"U01": {"impl": "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"
  run_in "$repo" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "empty-string title treated as absent: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "empty-string title treated as absent"

  printf '{"title": "t", "branch": "", "commits": {"U01": {"impl": "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"
  run_in "$repo" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "empty-string branch treated as absent: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "empty-string branch treated as absent"

  printf '{"title": "t", "branch": "lego/deliver/plan1/U01", "commits": {"U01": {"impl": ""}}}' \
    > "$repo/.local/manifest.json"
  run_in "$repo" deliver --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "empty-string commits.U01.impl treated as absent: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "empty-string commits.U01.impl treated as absent"
}

# ---------------------------------------------------------------------------
# deliver: stale-base check (B03 deliver-stale-base-check)
# ---------------------------------------------------------------------------

# Base branch (master) modifies a unit's Code path (src/solo.sh, B03/U02's
# only Code path) after the unit branched. Without --force, deliver must
# refuse: exit 4, with an error mentioning both "Code paths" and "--force"
# (the exact die message documented in cmd_deliver's integration of B03).
test_deliver_stale_base_check_blocks_without_force() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo v1" "lego(U02): implementation"
  git -C "$repo" checkout -q master

  # Base moves under U02's only Code path after the unit branched.
  commit_file "$repo" "src/solo.sh" "solo v0 patched on base" "fix: patch solo directly on base"

  # A working gh shim is deliberately used here even though a correct
  # implementation never reaches it (the stale check dies before Pass 2):
  # this makes an unimplemented stale check unambiguously observable as
  # exit 0 (deliver sails through to a fake successful PR) rather than
  # risking a coincidental exit 4 from the real system gh failing for an
  # unrelated reason (no auth/network), which would mask the missing
  # behavior.
  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: stale base blocks deliver" "lego/deliver/plan1/U02" U02)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U02 soloslug
  [ "$RUN_EXIT" -eq 4 ] || record_fail "base moved under a Code path: expected exit 4, got $RUN_EXIT (stderr: $RUN_ERR)"

  case "$RUN_ERR" in
    *"Code paths"*) : ;;
    *) record_fail "expected stderr to mention 'Code paths' (got: $RUN_ERR)" ;;
  esac
  case "$RUN_ERR" in
    *"--force"*) : ;;
    *) record_fail "expected stderr to mention '--force' (got: $RUN_ERR)" ;;
  esac

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U02"; then
    record_fail "expected no delivery branch to be created when the stale-base check fails"
  fi
}

# Identical stale-base fixture to the test above, but with --force: the
# check must be skipped entirely and delivery must succeed normally.
test_deliver_stale_base_check_force_bypasses() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo v1" "lego(U02): implementation"
  git -C "$repo" checkout -q master

  commit_file "$repo" "src/solo.sh" "solo v0 patched on base" "fix: patch solo directly on base"

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: force bypasses stale check" "lego/deliver/plan1/U02" U02)"

  run_cmd "$repo" "$newpath" deliver --force --manifest "$manifest" plan1 master U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "--force must bypass the stale-base check: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ "$RUN_OUT_LINES" -eq 1 ] || record_fail "expected exactly 1 stdout line (PR URL), got $RUN_OUT_LINES"
  assert_eq "https://github.com/example/lego-fixture/pull/123" "$RUN_OUT_LAST" "PR URL as last stdout line"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U02"; then
    record_fail "expected delivery branch lego/deliver/plan1/U02 to exist under --force"
  fi
}

# Base (master) is never touched after the unit branched: merge-base equals
# base tip, so no Code path can be stale (EC: base hasn't moved). deliver
# must succeed without --force.
test_deliver_stale_base_check_base_not_moved_succeeds() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo v1" "lego(U02): implementation"
  git -C "$repo" checkout -q master

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: base not moved" "lego/deliver/plan1/U02" U02)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "base unchanged since branch point: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
}

# A Code path introduced entirely by the unit branch itself: it never
# existed on base, neither at the merge-base nor at base's current tip.
# "Modified" per the contract means git diff reports a change between
# merge-base and base tip for that path; a path absent on both sides
# produces no diff output, so it must not be reported stale (EC: path not
# in either tree).
test_deliver_stale_base_check_path_not_in_either_tree_not_stale() {
  local repo
  repo="$(build_deliver_base)"

  cat >> "$repo/.local/blocks.md" <<'BLOCKSMD'

## B07 — ghost
- Status: Scaffolded
- Owner: agent
- Kind: leaf
- Deps: none
- Unit: U06
- Code: src/ghost.sh
- Contract: exercises a Code path absent from base in either direction
- Plan: plans/001-test.md
BLOCKSMD

  git -C "$repo" checkout -q -b "lego/plan1/U06-ghostslug" master
  commit_file "$repo" "src/ghost.sh" "ghost v1" "lego(U06): implementation"
  git -C "$repo" checkout -q master

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: path absent from base entirely" "lego/deliver/plan1/U06" U06)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U06 ghostslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "Code path absent from base tree entirely must not be stale: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
}

# Two units delivered together; only one (U04) has a stale Code path. The
# whole deliver must fail exit 4, even though U02's own Code path
# (src/solo.sh) was never touched on base.
test_deliver_stale_base_check_multi_unit_one_stale_fails_whole_deliver() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo v1" "lego(U02): implementation"
  git -C "$repo" checkout -q master

  git -C "$repo" checkout -q -b "lego/plan1/U04-needsimplslug" master
  commit_file "$repo" "src/needsimpl.sh" "needsimpl v1" "lego(U04): implementation"
  git -C "$repo" checkout -q master

  # Base moves under U04's Code path only; U02's Code path is untouched.
  commit_file "$repo" "src/needsimpl.sh" "needsimpl v0 patched on base" "fix: patch needsimpl directly on base"

  # See test_deliver_stale_base_check_blocks_without_force for why a
  # working gh shim (not the real system gh) is used for an exit-4
  # expectation: it keeps an unimplemented stale check unambiguously
  # observable as exit 0, instead of a coincidental exit 4 from real gh
  # failing for an unrelated reason.
  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: multi-unit one stale" "lego/deliver/plan1/multi" U02 U04)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U02 soloslug U04 needsimplslug
  [ "$RUN_EXIT" -eq 4 ] || record_fail "one stale unit among many must fail the whole deliver: expected exit 4, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/multi"; then
    record_fail "expected no delivery branch to be created when any unit is stale"
  fi
}

# Verifies the documented stderr report line shape: "  stale: <path>
# (changed by: <sha1-short> <sha2-short> ...)" -- two commits touch the
# same stale path on base after the unit branched, and both their short
# shas must appear in the report line for that path.
test_deliver_stale_base_check_stderr_report_format() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo v1" "lego(U02): implementation"
  git -C "$repo" checkout -q master

  commit_file "$repo" "src/solo.sh" "solo v0 patched1" "patch1: touch solo on base"
  local sha1 sha1_prefix
  sha1="$(git -C "$repo" rev-parse master)"
  sha1_prefix="${sha1:0:7}"

  commit_file "$repo" "src/solo.sh" "solo v0 patched2" "patch2: touch solo on base again"
  local sha2 sha2_prefix
  sha2="$(git -C "$repo" rev-parse master)"
  sha2_prefix="${sha2:0:7}"

  # See test_deliver_stale_base_check_blocks_without_force for why a
  # working gh shim (not the real system gh) is used for an exit-4
  # expectation.
  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: stderr report format" "lego/deliver/plan1/U02" U02)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U02 soloslug
  [ "$RUN_EXIT" -eq 4 ] || record_fail "expected exit 4 for the stale-report fixture, got $RUN_EXIT (stderr: $RUN_ERR)"

  local stale_line
  stale_line="$(printf '%s\n' "$RUN_ERR" | grep -E '^  stale: src/solo\.sh \(changed by: ' || true)"
  if [ -z "$stale_line" ]; then
    record_fail "expected a '  stale: src/solo.sh (changed by: ...)' line on stderr (got: $RUN_ERR)"
  else
    case "$stale_line" in
      *"$sha1_prefix"*) : ;;
      *) record_fail "expected the stale report to mention commit $sha1_prefix (got: $stale_line)" ;;
    esac
    case "$stale_line" in
      *"$sha2_prefix"*) : ;;
      *) record_fail "expected the stale report to mention commit $sha2_prefix (got: $stale_line)" ;;
    esac
  fi
}

# --force is parsed alongside --manifest regardless of their relative
# order on the command line; both orderings must bypass an otherwise-fatal
# stale-base condition.
test_deliver_stale_base_check_force_flag_order_independent() {
  local repo1 repo2

  repo1="$(build_deliver_base)"
  git -C "$repo1" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo1" "src/solo.sh" "solo v1" "lego(U02): implementation"
  git -C "$repo1" checkout -q master
  commit_file "$repo1" "src/solo.sh" "solo v0 patched on base" "fix: patch solo on base"

  make_gh_shim
  local newpath1="$GH_SHIM_BIN:$PATH"
  local manifest1
  manifest1="$(write_valid_manifest "$repo1" "test: force before manifest" "lego/deliver/plan1/U02" U02)"

  run_cmd "$repo1" "$newpath1" deliver --force --manifest "$manifest1" plan1 master U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "--force before --manifest: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  repo2="$(build_deliver_base)"
  git -C "$repo2" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo2" "src/solo.sh" "solo v1" "lego(U02): implementation"
  git -C "$repo2" checkout -q master
  commit_file "$repo2" "src/solo.sh" "solo v0 patched on base" "fix: patch solo on base"

  make_gh_shim
  local newpath2="$GH_SHIM_BIN:$PATH"
  local manifest2
  manifest2="$(write_valid_manifest "$repo2" "test: manifest before force" "lego/deliver/plan1/U02" U02)"

  run_cmd "$repo2" "$newpath2" deliver --manifest "$manifest2" --force plan1 master U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "--manifest before --force: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
}

# The unit branch shares no history with base at all (an orphan branch), so
# `git merge-base <base> <unit-branch>` itself fails -- the documented
# Errors clause requires this to be treated as "all paths stale" and
# reported, never as an uncaught git failure that crashes or misbehaves.
test_deliver_stale_base_check_unresolvable_merge_base_treated_as_all_stale() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q --orphan "lego/plan1/U02-soloslug"
  commit_file "$repo" "src/solo.sh" "solo v1 orphan" "lego(U02): implementation"
  git -C "$repo" checkout -q master

  # See test_deliver_stale_base_check_blocks_without_force for why a
  # working gh shim (not the real system gh) is used for an exit-4
  # expectation.
  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: unresolvable merge-base" "lego/deliver/plan1/U02" U02)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U02 soloslug
  [ "$RUN_EXIT" -eq 4 ] || record_fail "unresolvable merge-base must be treated as all-paths-stale, not silently ignored or crashed: expected exit 4, got $RUN_EXIT (stderr: $RUN_ERR)"

  case "$RUN_ERR" in
    *"stale: src/solo.sh"*) : ;;
    *) record_fail "expected stderr to report src/solo.sh as stale when merge-base is unresolvable (got: $RUN_ERR)" ;;
  esac

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U02"; then
    record_fail "expected no delivery branch to be created when merge-base is unresolvable"
  fi
}

# A unit with two Code paths (B01/U01: src/greet.sh, src/greet_test.sh),
# both modified on base after the unit branched. Per the documented edge
# case "All paths stale: all are listed in the report", both must appear
# as separate "  stale: ..." lines, not just the first one found.
test_deliver_stale_base_check_all_paths_stale_all_listed() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_files "$repo" "lego(U01): implementation" \
    "src/greet.sh" $'greet NEW\n' \
    "src/greet_test.sh" $'greet test NEW\n'
  git -C "$repo" checkout -q master

  commit_files "$repo" "fix: patch both greet paths on base" \
    "src/greet.sh" $'greet v0 patched\n' \
    "src/greet_test.sh" $'greet test v0 patched\n'

  # See test_deliver_stale_base_check_blocks_without_force for why a
  # working gh shim (not the real system gh) is used for an exit-4
  # expectation.
  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: all paths stale" "lego/deliver/plan1/U01" U01)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "both Code paths stale: expected exit 4, got $RUN_EXIT (stderr: $RUN_ERR)"

  case "$RUN_ERR" in
    *"stale: src/greet.sh"*) : ;;
    *) record_fail "expected stderr to report src/greet.sh as stale (got: $RUN_ERR)" ;;
  esac
  case "$RUN_ERR" in
    *"stale: src/greet_test.sh"*) : ;;
    *) record_fail "expected stderr to report src/greet_test.sh as stale too, not just the first path found (got: $RUN_ERR)" ;;
  esac
}

# ===========================================================================
# remove
# ===========================================================================

test_remove_usage() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" remove
  [ "$RUN_EXIT" -eq 2 ] || record_fail "no args: expected exit 2, got $RUN_EXIT"

  run_in "$repo" remove plan1
  [ "$RUN_EXIT" -eq 2 ] || record_fail "1 arg: expected exit 2, got $RUN_EXIT"

  run_in "$repo" remove plan1 U01
  [ "$RUN_EXIT" -eq 2 ] || record_fail "2 args: expected exit 2, got $RUN_EXIT"

  run_in "$repo" remove plan1 U01 greetstuff extra
  [ "$RUN_EXIT" -eq 2 ] || record_fail "4 args: expected exit 2, got $RUN_EXIT"
}

test_remove_invalid_chars() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" remove "plan slug" U01 greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "space in plan-slug: expected exit 2, got $RUN_EXIT"

  run_in "$repo" remove plan1 "U0/1" greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "slash in unit-id: expected exit 2, got $RUN_EXIT"

  run_in "$repo" remove plan1 U01 'slug;rm'
  [ "$RUN_EXIT" -eq 2 ] || record_fail "semicolon in unit-slug: expected exit 2, got $RUN_EXIT"
}

test_remove_zero_branch_match() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" remove plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "constructed branch absent: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "constructed branch absent"
}

test_remove_cross_plan_isolation() {
  local repo container wtA wtB branchA branchB shaB_before
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  branchA="lego/planA/U01-foo"
  branchB="lego/planB/U01-bar"
  wtA="$container/manual-wt-planA-U01"
  wtB="$container/manual-wt-planB-U01"

  git -C "$repo" branch "$branchA"
  git -C "$repo" worktree add -q "$wtA" "$branchA"
  git -C "$repo" branch "$branchB"
  git -C "$repo" worktree add -q "$wtB" "$branchB"
  shaB_before="$(git -C "$repo" rev-parse "$branchB")"

  run_in "$repo" remove planA U01 foo
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branchA"; then
    record_fail "expected planA's branch $branchA to be deleted"
  fi
  if [ -d "$wtA" ]; then
    record_fail "expected planA's worktree to be removed"
  fi

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branchB"; then
    record_fail "expected planB's same-unit-id branch $branchB to remain untouched by removing planA's unit"
  fi
  local shaB_after
  shaB_after="$(git -C "$repo" rev-parse "$branchB" 2>/dev/null || echo "")"
  assert_eq "$shaB_before" "$shaB_after" "planB's branch ref is unchanged by removing planA's same-unit-id branch"
  if [ ! -d "$wtB" ]; then
    record_fail "expected planB's worktree to remain untouched"
  fi
}

test_remove_success() {
  local repo container wt branch
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  branch="lego/plan1/U01-greetstuff"
  wt="$container/manual-wt-U01"

  git -C "$repo" branch "$branch"
  git -C "$repo" worktree add -q "$wt" "$branch"

  run_in "$repo" remove plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ -d "$wt" ]; then
    record_fail "expected worktree directory to be removed"
  fi
  if git -C "$repo" worktree list | grep -qF "$wt"; then
    record_fail "expected git worktree list to no longer include the removed worktree"
  fi
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected branch $branch to be deleted"
  fi
}

test_remove_dirty_worktree_fails() {
  local repo container wt branch
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  branch="lego/plan1/U01-greetstuff"
  wt="$container/manual-wt-U01"

  git -C "$repo" branch "$branch"
  git -C "$repo" worktree add -q "$wt" "$branch"
  printf 'dirty\n' >> "$wt/README.md"

  run_in "$repo" remove plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "dirty worktree: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "dirty worktree"
}

test_remove_unmerged_branch_fails() {
  local repo container wt branch
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  branch="lego/plan1/U01-greetstuff"
  wt="$container/manual-wt-U01"

  git -C "$repo" branch "$branch"
  git -C "$repo" worktree add -q "$wt" "$branch"
  printf 'unmerged work\n' > "$wt/extra.txt"
  git -C "$wt" add extra.txt
  git -C "$wt" commit -q -m "unmerged work"

  run_in "$repo" remove plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "unmerged branch: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "unmerged branch"

  if [ -d "$wt" ]; then
    record_fail "expected the worktree itself to have been removed (it was clean) even though branch deletion failed"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected branch $branch to still exist since deletion failed (unmerged)"
  fi
}

# ===========================================================================
# cross-cutting
# ===========================================================================

test_unknown_subcommand() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" bogus-command
  [ "$RUN_EXIT" -eq 2 ] || record_fail "unknown subcommand: expected exit 2, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "unknown subcommand"
}

# ===========================================================================
# merge: auto-removal of the unit worktree (B01 worktree-auto-cleanup)
# ===========================================================================

test_merge_removes_unit_worktree_on_success() {
  local repo container branch wt
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  branch="lego/plan1/U01-greetstuff"
  wt="$container/manual-wt-U01"

  git -C "$repo" branch "$branch"
  git -C "$repo" worktree add -q "$wt" "$branch"
  commit_file "$wt" "feature.txt" "feature content" "unit work"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ -d "$wt" ]; then
    record_fail "expected unit worktree directory $wt to be removed after a successful merge"
  fi
  if git -C "$repo" worktree list | grep -qF "$wt"; then
    record_fail "expected git worktree list to no longer include the removed unit worktree"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected unit branch $branch to still exist after merge (branch is not removed; deliver may need it)"
  fi
  if [ ! -f "$repo/feature.txt" ]; then
    record_fail "expected the merge itself to have succeeded (feature.txt from unit branch present)"
  fi
}

test_merge_worktree_removal_failure_does_not_change_exit_code() {
  local repo container branch wt
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  branch="lego/plan1/U01-greetstuff"
  wt="$container/manual-wt-U01"

  git -C "$repo" branch "$branch"
  git -C "$repo" worktree add -q "$wt" "$branch"
  commit_file "$wt" "feature.txt" "feature content" "unit work"
  # Leave the unit worktree dirty (uncommitted tracked change) so `git
  # worktree remove` refuses it -- this is the cleanup-failure path, not the
  # invoking-worktree dirty-tree check (that check is about $repo, not $wt).
  printf 'dirty\n' >> "$wt/README.md"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "merge cleanup failure must never change merge's exit code: expected exit 0, got $RUN_EXIT"

  if [ -z "$RUN_ERR" ]; then
    record_fail "expected a warning on stderr when unit-worktree cleanup fails"
  fi
  if [ ! -d "$wt" ]; then
    record_fail "expected the dirty unit worktree to still exist since its removal should have failed"
  fi
  if ! git -C "$repo" worktree list | grep -qF "$wt"; then
    record_fail "expected git worktree list to still include the unit worktree (removal failed)"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected unit branch $branch to still exist after merge"
  fi
  if [ ! -f "$repo/feature.txt" ]; then
    record_fail "expected the merge itself to have succeeded despite the cleanup failure"
  fi
}

# ===========================================================================
# deliver: auto-removal of unit branches/worktrees (B01 worktree-auto-cleanup)
# ===========================================================================

test_deliver_cleanup_removes_unit_branch_and_worktree() {
  local repo container branch wt
  repo="$(build_deliver_base)"
  container="$(dirname "$repo")"
  branch="lego/plan1/U01-greetstuff"
  wt="$container/manual-wt-U01"

  git -C "$repo" checkout -q -b "$branch" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  # Simulate the unit having already been merged into the integration branch
  # (e.g. via `worktree.sh merge`) before delivery, so `git branch -d` in
  # deliver's cleanup step can succeed.
  git -C "$repo" merge -q --no-ff -m "lego: merge $branch" "$branch"
  # A worktree for the unit branch still lingers (e.g. merge's own best-effort
  # cleanup did not run or did not succeed) -- deliver must remove it too.
  git -C "$repo" worktree add -q "$wt" "$branch"

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: cleanup removes branch and worktree" "lego/deliver/plan1/U01" U01)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "https://github.com/example/lego-fixture/pull/123" "$RUN_OUT_LAST" "PR URL still printed as last stdout line after cleanup"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected unit branch $branch to be deleted after a successful deliver"
  fi
  if [ -d "$wt" ]; then
    record_fail "expected unit worktree $wt to be removed after a successful deliver"
  fi
  if git -C "$repo" worktree list | grep -qF "$wt"; then
    record_fail "expected git worktree list to no longer include the removed unit worktree"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    record_fail "expected the local delivery branch lego/deliver/plan1/U01 to be left intact"
  fi
}

test_deliver_cleanup_branch_deletion_failure_still_exits_0() {
  local repo branch
  repo="$(build_deliver_base)"
  branch="lego/plan1/U01-greetstuff"

  git -C "$repo" checkout -q -b "$branch" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  # Deliberately do NOT merge the unit branch into master: it stays
  # unmerged, so `git branch -d` in deliver's cleanup step will fail.

  make_gh_shim
  local newpath="$GH_SHIM_BIN:$PATH"
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: cleanup branch deletion failure" "lego/deliver/plan1/U01" U01)"

  run_cmd "$repo" "$newpath" deliver --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "deliver cleanup failure must never change deliver's exit code: expected exit 0, got $RUN_EXIT"
  assert_eq "https://github.com/example/lego-fixture/pull/123" "$RUN_OUT_LAST" "PR URL still printed despite cleanup failure"

  if [ -z "$RUN_ERR" ]; then
    record_fail "expected a warning on stderr when unit-branch cleanup fails"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected unit branch $branch to still exist since deletion should have failed (unmerged)"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    record_fail "expected the local delivery branch lego/deliver/plan1/U01 to be left intact"
  fi
}

# ===========================================================================
# clean (B01 worktree-auto-cleanup)
# ===========================================================================

test_clean_usage_unexpected_args() {
  local repo
  repo="$(new_git_repo)"

  # Bare "clean" (no args) is a usage error under B02 (previously fell back
  # to global mode during scaffold).
  run_in "$repo" clean
  [ "$RUN_EXIT" -eq 2 ] || record_fail "bare clean (no args): expected exit 2, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "clean with no arguments"

  # Extra arguments are a usage error in both scoped and --all mode.
  run_in "$repo" clean plan1 extra-arg
  [ "$RUN_EXIT" -eq 2 ] || record_fail "clean <slug> extra: expected exit 2, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "clean <slug> extra"

  run_in "$repo" clean --all extra-arg
  [ "$RUN_EXIT" -eq 2 ] || record_fail "clean --all extra: expected exit 2, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "clean --all extra"
}

test_clean_requires_git_work_tree() {
  local dir
  dir="$(mktemp -d)"
  track_tmp "$dir"

  run_in "$dir" clean --all
  [ "$RUN_EXIT" -eq 3 ] || record_fail "clean --all outside git worktree: expected exit 3, got $RUN_EXIT"
}

test_clean_no_lego_branches() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" clean --all
  [ "$RUN_EXIT" -eq 0 ] || record_fail "clean --all with no lego branches: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ "$RUN_OUT_LINES" -eq 1 ] || record_fail "expected exactly 1 stdout line (count), got $RUN_OUT_LINES (stdout: $RUN_OUT)"
  assert_eq "0" "$RUN_OUT_LAST" "clean --all with no lego branches prints count 0 as last stdout line"
}

test_clean_removes_merged_lego_and_delivery_branches_and_worktrees() {
  local repo container branch1 branch2 branch3 other_branch wt1 wt2
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  branch1="lego/plan1/U01-greetstuff"
  # Delivery branches now carry an extra plan-slug path segment:
  # lego/deliver/<plan-slug>/<unit-ids>. clean's glob was updated from
  # "lego/deliver/*" to "lego/deliver/*/*" to match this new depth.
  branch2="lego/deliver/plan1/U02"
  branch3="lego/plan1/U03-otherslug"
  other_branch="feature/other"
  wt1="$container/manual-wt-U01"
  wt2="$container/manual-wt-U02"

  # branch1: a merged "lego/*/*" branch with its own worktree.
  git -C "$repo" branch "$branch1"
  git -C "$repo" worktree add -q "$wt1" "$branch1"
  commit_file "$wt1" "feature1.txt" "feature1" "unit work 1"
  git -C "$repo" merge -q --no-ff -m "merge $branch1" "$branch1"

  # branch2: a merged "lego/deliver/*/*" branch with its own worktree.
  git -C "$repo" branch "$branch2"
  git -C "$repo" worktree add -q "$wt2" "$branch2"
  commit_file "$wt2" "feature2.txt" "feature2" "unit work 2"
  git -C "$repo" merge -q --no-ff -m "merge $branch2" "$branch2"

  # branch3: an UNMERGED lego branch -- must be skipped, not deleted.
  git -C "$repo" checkout -q -b "$branch3"
  commit_file "$repo" "unmerged.txt" "content" "unit work 3"
  git -C "$repo" checkout -q master

  # other_branch: a non-lego branch, trivially merged (points at current
  # HEAD) -- must be left untouched since it does not match a lego pattern.
  git -C "$repo" branch "$other_branch"

  run_in "$repo" clean --all
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "2" "$RUN_OUT_LAST" "count of removed branches (branch1 + branch2) as last stdout line"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch1"; then
    record_fail "expected merged lego/*/* branch $branch1 to be deleted"
  fi
  if [ -d "$wt1" ] || git -C "$repo" worktree list | grep -qF "$wt1"; then
    record_fail "expected the worktree for $branch1 to be removed"
  fi

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch2"; then
    record_fail "expected merged lego/deliver/*/* branch $branch2 to be deleted"
  fi
  if [ -d "$wt2" ] || git -C "$repo" worktree list | grep -qF "$wt2"; then
    record_fail "expected the worktree for $branch2 to be removed"
  fi

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch3"; then
    record_fail "expected unmerged lego branch $branch3 to be skipped, not deleted"
  fi
  if [ -z "$RUN_ERR" ]; then
    record_fail "expected a warning on stderr for the skipped unmerged branch"
  fi

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$other_branch"; then
    record_fail "expected non-lego branch $other_branch to be left untouched by clean"
  fi
}

test_clean_prunes_stale_worktree_entries() {
  local repo container branch wt
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  branch="feature/stale"
  wt="$container/manual-wt-stale"

  git -C "$repo" branch "$branch"
  git -C "$repo" worktree add -q "$wt" "$branch"
  # Simulate a stale worktree entry: the directory is gone from disk without
  # ever going through `git worktree remove`, leaving administrative files
  # behind. This branch is deliberately non-lego and unmerged-irrelevant so
  # that only the unconditional `git worktree prune` step (not the
  # merged-branch loop) can be responsible for cleaning it up.
  rm -rf -- "$wt"

  if ! git -C "$repo" worktree list --porcelain | grep -qF "worktree $wt"; then
    record_fail "test setup invalid: expected a stale worktree entry for $wt to be present before clean"
    return
  fi

  run_in "$repo" clean --all
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "0" "$RUN_OUT_LAST" "no lego branches removed; only a stale worktree entry pruned"

  if git -C "$repo" worktree list --porcelain | grep -qF "worktree $wt"; then
    record_fail "expected git worktree prune to remove the stale worktree entry for $wt"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected the non-lego branch $branch itself to remain untouched by prune"
  fi
}

# ===========================================================================
# clean: plan-scoped (B02 clean-plan-scoped)
# ===========================================================================

test_clean_plan_scoped_removes_only_in_scope_and_reports_foreign() {
  local repo container p1a p1deliver p2 p1unmerged other wt1 wt2
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  p1a="lego/plan1/U01-greetstuff"
  p1deliver="lego/deliver/plan1/U02"
  p2="lego/plan2/U01-otherstuff"
  p1unmerged="lego/plan1/U03-unmergedslug"
  other="feature/other"
  wt1="$container/manual-wt-p1a"
  wt2="$container/manual-wt-p1deliver"

  # p1a: in-scope for plan1, merged, has its own worktree.
  git -C "$repo" branch "$p1a"
  git -C "$repo" worktree add -q "$wt1" "$p1a"
  commit_file "$wt1" "feature1.txt" "feature1" "unit work 1"
  git -C "$repo" merge -q --no-ff -m "merge $p1a" "$p1a"

  # p1deliver: in-scope delivery branch for plan1, merged, has its own
  # worktree.
  git -C "$repo" branch "$p1deliver"
  git -C "$repo" worktree add -q "$wt2" "$p1deliver"
  commit_file "$wt2" "feature2.txt" "feature2" "unit work 2"
  git -C "$repo" merge -q --no-ff -m "merge $p1deliver" "$p1deliver"

  # p2: a merged branch belonging to a DIFFERENT plan -- out of scope for a
  # plan1-scoped clean; must be reported as foreign and left untouched.
  git -C "$repo" branch "$p2"
  git -C "$repo" merge -q --no-ff -m "merge $p2" "$p2"

  # p1unmerged: in-scope for plan1 but unmerged -- must be skipped with the
  # "skipping unmerged" message, never reported as foreign.
  git -C "$repo" checkout -q -b "$p1unmerged"
  commit_file "$repo" "unmerged.txt" "content" "unit work 3"
  git -C "$repo" checkout -q master

  # other: non-lego branch, left untouched regardless of scope.
  git -C "$repo" branch "$other"

  run_in "$repo" clean plan1
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "2" "$RUN_OUT_LAST" "count of removed branches scoped to plan1 (p1a + p1deliver)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$p1a"; then
    record_fail "expected in-scope merged branch $p1a to be deleted"
  fi
  if [ -d "$wt1" ] || git -C "$repo" worktree list | grep -qF "$wt1"; then
    record_fail "expected the worktree for $p1a to be removed"
  fi

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$p1deliver"; then
    record_fail "expected in-scope merged delivery branch $p1deliver to be deleted"
  fi
  if [ -d "$wt2" ] || git -C "$repo" worktree list | grep -qF "$wt2"; then
    record_fail "expected the worktree for $p1deliver to be removed"
  fi

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$p2"; then
    record_fail "expected out-of-scope (foreign) branch $p2 to be left untouched by a plan1-scoped clean"
  fi
  case "$RUN_ERR" in
    *"skipped (foreign): $p2"*) : ;;
    *) record_fail "expected stderr to report the foreign branch $p2 (stderr: $RUN_ERR)" ;;
  esac

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$p1unmerged"; then
    record_fail "expected unmerged in-scope branch $p1unmerged to be skipped, not deleted"
  fi
  case "$RUN_ERR" in
    *"skipping unmerged lego branch $p1unmerged"*) : ;;
    *) record_fail "expected stderr to report the unmerged in-scope branch $p1unmerged (stderr: $RUN_ERR)" ;;
  esac
  case "$RUN_ERR" in
    *"foreign): $p1unmerged"*)
      record_fail "unmerged in-scope branch must never be reported as foreign (stderr: $RUN_ERR)" ;;
    *) : ;;
  esac

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$other"; then
    record_fail "expected non-lego branch $other to be left untouched"
  fi
}

test_clean_plan_scoped_matches_no_branches() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" clean noexistplan
  [ "$RUN_EXIT" -eq 0 ] || record_fail "plan slug matching no branches: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "0" "$RUN_OUT_LAST" "plan slug matching no branches prints count 0"
  [ -z "$RUN_ERR" ] || record_fail "expected no stderr output when no lego branches exist at all, got: $RUN_ERR"
}

test_clean_all_mode_spans_all_plans_with_no_foreign_messages() {
  local repo container p1 p2 pdeliver wt b
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  p1="lego/plan1/U01-a"
  p2="lego/plan2/U01-b"
  pdeliver="lego/deliver/plan1/U02"
  wt="$container/manual-wt-p1"

  git -C "$repo" branch "$p1"
  git -C "$repo" worktree add -q "$wt" "$p1"
  commit_file "$wt" "f1.txt" "f1" "unit work 1"
  git -C "$repo" merge -q --no-ff -m "merge $p1" "$p1"

  git -C "$repo" branch "$p2"
  git -C "$repo" merge -q --no-ff -m "merge $p2" "$p2"

  git -C "$repo" branch "$pdeliver"
  git -C "$repo" merge -q --no-ff -m "merge $pdeliver" "$pdeliver"

  run_in "$repo" clean --all
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "3" "$RUN_OUT_LAST" "count of removed branches spanning multiple plans in --all mode"

  for b in "$p1" "$p2" "$pdeliver"; do
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$b"; then
      record_fail "expected branch $b to be deleted by clean --all"
    fi
  done
  if [ -d "$wt" ] || git -C "$repo" worktree list | grep -qF "$wt"; then
    record_fail "expected the worktree for $p1 to be removed"
  fi

  case "$RUN_ERR" in
    *"foreign"*) record_fail "expected no foreign-skip messages in --all mode (stderr: $RUN_ERR)" ;;
    *) : ;;
  esac
}

test_clean_invalid_plan_slug_token_is_usage_error() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" clean "plan slug"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "space in plan-slug: expected exit 2, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "clean with space in plan-slug"

  run_in "$repo" clean "plan/slug"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "slash in plan-slug: expected exit 2, got $RUN_EXIT"

  run_in "$repo" clean 'slug;rm'
  [ "$RUN_EXIT" -eq 2 ] || record_fail "semicolon in plan-slug: expected exit 2, got $RUN_EXIT"

  run_in "$repo" clean ""
  [ "$RUN_EXIT" -eq 2 ] || record_fail "empty-string plan-slug: expected exit 2, got $RUN_EXIT"
}

# ===========================================================================
# realm.sh: testPatterns union across the layered config (NEW, plan 001-lc)
#
# realm.sh's extension point currently reads only .local/config.json
# (LEGO_CONFIG-overridable). The new contract unions its testPatterns with
# .claude/lego.json's (fixed path, unaffected by $LEGO_CONFIG), each file
# optional -- a deliberate exception to the recursive-merge-with-override-
# wins semantics used elsewhere: the test-file family can only grow.
# ===========================================================================

test_realm_testpatterns_union_combines_base_and_override() {
  local repo
  repo="$(new_git_repo)"
  write_base_config "$repo" '{"testPatterns":["*.basepat"]}'
  write_override_config "$repo" '{"testPatterns":["*.overridepat"]}'

  run_realm "$repo" "" "foo.basepat"
  assert_eq "test" "$RUN_REALM_OUT" "base-contributed pattern matches (union includes .claude/lego.json's testPatterns, not just .local/config.json's)"

  run_realm "$repo" "" "bar.overridepat"
  assert_eq "test" "$RUN_REALM_OUT" "override-contributed pattern still matches"

  run_realm "$repo" "" "baz.other"
  assert_eq "impl" "$RUN_REALM_OUT" "a path matching neither file's patterns and no built-in test family is impl"
}

test_realm_testpatterns_base_only_when_no_override_present() {
  local repo
  repo="$(new_git_repo)"
  write_base_config "$repo" '{"testPatterns":["*.basepat"]}'

  run_realm "$repo" "" "x.basepat"
  assert_eq "test" "$RUN_REALM_OUT" "base file alone (no .local/config.json present at all) still contributes its testPatterns -- each file is independently optional"
}

test_realm_lego_config_env_overrides_only_override_location_base_fixed() {
  local repo
  repo="$(new_git_repo)"
  write_base_config "$repo" '{"testPatterns":["*.basepat"]}'
  mkdir -p "$repo/custom"
  printf '%s' '{"testPatterns":["*.custompat"]}' > "$repo/custom/override.json"

  run_realm "$repo" "custom/override.json" "a.custompat"
  assert_eq "test" "$RUN_REALM_OUT" "\$LEGO_CONFIG redirects the override file's location"

  run_realm "$repo" "custom/override.json" "b.basepat"
  assert_eq "test" "$RUN_REALM_OUT" "the base path (.claude/lego.json) is fixed and still read even when \$LEGO_CONFIG points the override elsewhere"
}

# ===========================================================================
# main
# ===========================================================================

run_test "add: usage error on wrong argument count" test_add_usage_argcount
run_test "add: usage error on invalid characters in id/slug" test_add_invalid_chars
run_test "add: missing dependency/input errors (jq, config.json, commands.test, blocks.md)" test_add_missing_dependencies
run_test "all subcommands: require running inside a git work tree" test_requires_git_work_tree
run_test "add: unknown unit id (no matching blocks.md section)" test_add_unit_not_found
run_test "add: branch already exists" test_add_branch_already_exists
run_test "add: worktree path already exists" test_add_worktree_path_already_exists
run_test "add: baseline test failure cleans up branch and worktree" test_add_baseline_failure_cleans_up
run_test "add: success creates branch+worktree and seeds .local (config, unit.md, contracts)" test_add_success_and_seeding
run_test "add: unit with no contract file seeds no contracts (silently skipped)" test_add_no_contract_file_silently_skipped
run_test "add: worktreeDir resolution (default and relative)" test_add_worktree_dir_resolution
run_test "add: deterministic across identical repo state and args" test_add_deterministic
run_test "add: baseline test command runs inside the new worktree, after seeding" test_add_baseline_runs_inside_new_worktree_after_seeding
run_test "add: succeeds without gh (deliver-only dependency)" test_add_succeeds_without_gh
run_test "add: status.md seeded with the exact contract line sequence (NEW)" test_add_status_md_content
run_test "add: status.md Blocks line status is verbatim, empty when Status field absent (NEW)" test_add_status_md_status_field_verbatim_and_empty
run_test "add: status.md multi-block unit lists one Blocks line per section in blocks.md file order (NEW)" test_add_status_md_multiblock_file_order
run_test "add: creates .local/briefs/ and .local/reports/ as empty directories (NEW)" test_add_creates_empty_briefs_and_reports_dirs
run_test "add: status.md is deterministic across identical repo state and args (NEW)" test_add_status_md_deterministic

run_test "config: base-only (.claude/lego.json, no .local/config.json) resolves commands.test/worktreeDir and seeds without an override copy (NEW)" test_config_base_only_resolves_and_seeds_without_local_override
run_test "config: invalid JSON in either layer is exit 3 even when the other layer alone would suffice (CHANGED)" test_config_invalid_json_exit3
run_test "config: object-form commands.test errors (missing default, default names absent/empty variant) (NEW)" test_config_commands_test_object_errors
run_test "config: object-form commands.test resolves the variant named by 'default' (NEW)" test_config_commands_test_object_resolves_default_variant
run_test "config: recursive merge on a nested commands.test object -- override wins per key, base-only keys survive (NEW)" test_config_merge_nested_object_override_wins_default_key
run_test "config: merge combines distinct top-level keys from base and override; override wins on a shared key (NEW/CHANGED)" test_config_merge_combines_base_and_override_keys

run_test "merge: usage error on wrong argument count (plan-scoped)" test_merge_usage
run_test "merge: usage error on invalid characters in plan-slug/unit-id/unit-slug" test_merge_invalid_chars
run_test "merge: constructed branch does not exist (no glob ambiguity possible)" test_merge_no_branch_match
run_test "merge: construct_unit_branch is deterministic (same inputs, same constructed branch)" test_merge_branch_construction_deterministic
run_test "merge: refuses on dirty tracked working tree" test_merge_dirty_tracked_tree_refuses
run_test "merge: untracked-only changes do not block merge" test_merge_untracked_only_does_not_block
run_test "merge: success (--no-ff, commit message, file introduced)" test_merge_success
run_test "merge: cross-plan isolation (same unit-id under a different plan is untouched)" test_merge_cross_plan_isolation

run_test "merge: guard refuses when current branch matches the unit-branch pattern (B01 merge-self-guard)" test_merge_guard_current_branch_is_unit_branch_refuses
run_test "merge: guard refuses self-merge when target branch equals current branch (B01 merge-self-guard)" test_merge_guard_self_merge_refuses
run_test "merge: guard passes for a lego/* current branch with no U*-* segment (B01 merge-self-guard)" test_merge_guard_non_unit_lego_branch_as_current_succeeds
run_test "merge: guard passes for a detached HEAD current branch (B01 merge-self-guard)" test_merge_guard_detached_head_succeeds
run_test "merge: guard runs before the dirty-tree check (B01 merge-self-guard)" test_merge_guard_runs_before_dirty_tree_check
run_test "merge: guard check (1) unit-worktree fires before check (2) self-merge when both apply (B01 merge-self-guard)" test_merge_guard_check_order_unit_branch_before_self_merge

run_test "deliver: usage error on wrong argument count (plan-scoped, --manifest present)" test_deliver_usage
run_test "deliver: usage error on odd unit-id/unit-slug pair count (--manifest present)" test_deliver_odd_paired_args
run_test "deliver: usage error on invalid characters in plan-slug/base-branch/unit-id/unit-slug (--manifest present)" test_deliver_invalid_chars
run_test "deliver --manifest: --manifest flag itself is required, dies exit 3 when absent (B01 manifest-required)" test_deliver_manifest_flag_required
run_test "deliver: missing gh dependency" test_deliver_missing_gh
run_test "deliver: missing dependency/input errors (jq, config.json, blocks.md)" test_deliver_missing_dependencies
run_test "deliver: constructed unit branch does not exist" test_deliver_zero_branch_match
run_test "deliver: cross-plan isolation (same unit-id under a different plan is untouched)" test_deliver_cross_plan_isolation
run_test "deliver: stale same-subject commit inherited from base history is skipped, not fatal" test_deliver_stale_tests_commit_in_base_history_is_skipped
run_test "deliver: unit with no Code paths cannot be delivered (EC4)" test_deliver_unit_with_no_code_paths_fails
run_test "deliver: missing required implementation commit" test_deliver_missing_implementation_commit_fails
run_test "deliver: delivery branch already exists at new plan-scoped path (EC3)" test_deliver_delivery_branch_already_exists
run_test "deliver: underlying git failure (unreachable origin) on push" test_deliver_underlying_git_failure_on_push
run_test "deliver: tests commit is optional (untested prose unit)" test_deliver_tests_commit_optional_success
run_test "deliver: single unit - union of Code paths, newest-exact-subject, space path (EC1,EC2,D1,D4)" test_deliver_single_unit_union_and_newest_and_spaces
run_test "deliver: multi-unit branch naming is manifest-provided (not constructed); PR title/body order still argument-order (B01 manifest-required)" test_deliver_multi_unit_branch_naming_and_pr_title_order
run_test "deliver: multi-unit argument order is preserved, not sorted, in PR body headings (branch naming is now manifest-only) (B01 manifest-required)" test_deliver_multi_unit_argument_order_is_not_sorted
run_test "deliver: restore producing no changes creates no second commit" test_deliver_noop_restore_creates_no_second_commit

run_test "deliver --manifest: unreadable manifest path exits 3 (B01 deliver-manifest)" test_deliver_manifest_invalid_file
run_test "deliver --manifest: invalid JSON exits 3 (B01 deliver-manifest)" test_deliver_manifest_invalid_json
run_test "deliver --manifest: missing non-empty title exits 3 (B01 manifest-required)" test_deliver_manifest_missing_title
run_test "deliver --manifest: missing non-empty branch exits 3 (B01 manifest-required)" test_deliver_manifest_missing_branch
run_test "deliver --manifest: missing non-empty commits.<unit-id>.impl for any delivered unit exits 3 (B01 manifest-required)" test_deliver_manifest_missing_unit_impl
run_test "deliver --manifest: body remains optional, falls back to auto-generated default (B01 manifest-required)" test_deliver_manifest_body_optional_default
run_test "deliver --manifest: per-unit tests commit subject remains optional, falls back to default (B01 manifest-required)" test_deliver_manifest_tests_subject_optional_default
run_test "deliver --manifest: title override replaces default PR title (B01 deliver-manifest)" test_deliver_manifest_title_override
run_test "deliver --manifest: body override replaces default PR body (B01 deliver-manifest)" test_deliver_manifest_body_override
run_test "deliver --manifest: branch override replaces default delivery branch name (B01 deliver-manifest)" test_deliver_manifest_branch_override
run_test "deliver --manifest: commit subject overrides replace default tests/impl subjects (B01 deliver-manifest)" test_deliver_manifest_commit_subjects_override
run_test "deliver --manifest: partial manifest missing required fields (branch/commits.impl) is rejected exit 3 (B01 manifest-required)" test_deliver_manifest_partial
run_test "deliver --manifest: manifest branch already exists exits 4 (B01 deliver-manifest)" test_deliver_manifest_branch_already_exists
run_test "deliver --manifest: empty object manifest is rejected for missing required fields, exit 3 (B01 manifest-required)" test_deliver_manifest_empty_object
run_test "deliver --manifest: empty-string required field (title/branch/commits.impl) treated as absent, exit 3 (B01 manifest-required)" test_deliver_manifest_empty_string_field_treated_as_absent

run_test "deliver: base moved under a Code path without --force fails exit 4, mentions Code paths and --force (B03 deliver-stale-base-check)" test_deliver_stale_base_check_blocks_without_force
run_test "deliver: --force bypasses the stale-base check (B03 deliver-stale-base-check)" test_deliver_stale_base_check_force_bypasses
run_test "deliver: base hasn't moved since unit branched -- no stale paths, deliver succeeds (B03 deliver-stale-base-check)" test_deliver_stale_base_check_base_not_moved_succeeds
run_test "deliver: Code path absent from base in either direction is not stale (B03 deliver-stale-base-check)" test_deliver_stale_base_check_path_not_in_either_tree_not_stale
run_test "deliver: multi-unit delivery fails whole deliver when any one unit has a stale Code path (B03 deliver-stale-base-check)" test_deliver_stale_base_check_multi_unit_one_stale_fails_whole_deliver
run_test "deliver: stale-base stderr report line format includes short shas of the modifying commits (B03 deliver-stale-base-check)" test_deliver_stale_base_check_stderr_report_format
run_test "deliver: --force works with --manifest in either flag order (B03 deliver-stale-base-check)" test_deliver_stale_base_check_force_flag_order_independent
run_test "deliver: unresolvable merge-base is treated as all-paths-stale, not an uncaught git failure (B03 deliver-stale-base-check)" test_deliver_stale_base_check_unresolvable_merge_base_treated_as_all_stale
run_test "deliver: all Code paths stale are each listed in the report, not just the first found (B03 deliver-stale-base-check)" test_deliver_stale_base_check_all_paths_stale_all_listed

run_test "remove: usage error on wrong argument count (plan-scoped)" test_remove_usage
run_test "remove: usage error on invalid characters in plan-slug/unit-id/unit-slug" test_remove_invalid_chars
run_test "remove: constructed branch does not exist" test_remove_zero_branch_match
run_test "remove: cross-plan isolation (same unit-id under a different plan is untouched)" test_remove_cross_plan_isolation
run_test "remove: success removes worktree and deletes branch" test_remove_success
run_test "remove: dirty worktree fails" test_remove_dirty_worktree_fails
run_test "remove: unmerged branch fails (worktree still removed)" test_remove_unmerged_branch_fails

run_test "unknown subcommand" test_unknown_subcommand

run_test "merge: removes unit worktree on success, keeps branch (B01)" test_merge_removes_unit_worktree_on_success
run_test "merge: unit-worktree cleanup failure does not change exit code (B01)" test_merge_worktree_removal_failure_does_not_change_exit_code

run_test "deliver: cleanup removes unit branch and worktree, keeps delivery branch and PR URL (B01)" test_deliver_cleanup_removes_unit_branch_and_worktree
run_test "deliver: branch-cleanup failure does not change exit code or suppress PR URL (B01)" test_deliver_cleanup_branch_deletion_failure_still_exits_0

run_test "clean: bare clean and extra arguments are usage errors (B02 clean-plan-scoped)" test_clean_usage_unexpected_args
run_test "clean --all: requires running inside a git work tree (B01)" test_clean_requires_git_work_tree
run_test "clean --all: no lego branches exits 0 and prints count 0 (B01)" test_clean_no_lego_branches
run_test "clean --all: removes merged lego/*/* and lego/deliver/*/* branches+worktrees; skips unmerged; leaves non-lego untouched (B01 worktree-plan-scoping)" test_clean_removes_merged_lego_and_delivery_branches_and_worktrees
run_test "clean --all: runs git worktree prune to clean up stale worktree entries (B01)" test_clean_prunes_stale_worktree_entries

run_test "clean <plan-slug>: removes only in-scope merged branches; reports foreign; unmerged in-scope wins over foreign (B02 clean-plan-scoped)" test_clean_plan_scoped_removes_only_in_scope_and_reports_foreign
run_test "clean <plan-slug>: plan slug matching no branches exits 0, prints 0, no messages (B02 clean-plan-scoped)" test_clean_plan_scoped_matches_no_branches
run_test "clean --all: spans all plans, no foreign-skip messages (B02 clean-plan-scoped)" test_clean_all_mode_spans_all_plans_with_no_foreign_messages
run_test "clean <plan-slug>: invalid token as plan-slug is a usage error (B02 clean-plan-scoped)" test_clean_invalid_plan_slug_token_is_usage_error

run_test "realm.sh: testPatterns union combines base and override files (NEW)" test_realm_testpatterns_union_combines_base_and_override
run_test "realm.sh: testPatterns from base alone when no override file is present (NEW)" test_realm_testpatterns_base_only_when_no_override_present
run_test "realm.sh: \$LEGO_CONFIG overrides only the override file's location; base path is fixed (NEW)" test_realm_lego_config_env_overrides_only_override_location_base_fixed

echo "---"
echo "Passed: $TOTAL_PASS  Failed: $TOTAL_FAIL  Total: $((TOTAL_PASS + TOTAL_FAIL))"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
