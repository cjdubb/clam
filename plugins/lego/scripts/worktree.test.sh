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

# <!--
# Contract: B04 lego-dependency-injection (plan 001-speed-up-repo-ci)
#
# Behavior:
#   Supersedes B02 path-without-builtin-defork. The `path_without` helper
#   (rebuilding a PATH-minus-one-command symlink farm per call) is deleted
#   outright: the jq-absent and gh-absent tests below set JQ=/nonexistent /
#   GH=/nonexistent in the environment of the single invocation under test,
#   driving worktree.sh's `: "${JQ:=jq}"` / `: "${GH:=gh}"` seams directly
#   instead of reconstructing PATH. This file's ASSERTIONS remain frozen —
#   only the arrangement of the dependency-absent worlds changes.
#
# Inputs:  unchanged — the same throwaway git fixtures under mktemp.
# Outputs: unchanged — `Passed: 115  Failed: 0  Total: 115`.
#
# Invariants:
#   - Pass count is EXACTLY 115, failures EXACTLY 0. A changed count is a
#     defect, not an improvement, whichever direction it moves.
#   - No assertion may be weakened, skipped, merged, or deleted.
#   - Do NOT rewrite the git fixtures for speed. `new_git_repo` was measured
#     at 1.7s across all 93 calls, 1.9% of this file's runtime; a `cp -a`
#     template would save 1.3s and is not worth the fidelity risk.
#
# Edge cases:
#   - Injected absence (JQ=/nonexistent, GH=/nonexistent) must reproduce the
#     exit-3 "missing dependency" behaviour identically to a PATH genuinely
#     missing jq/gh: both are detected with `command -v`, which a
#     nonexistent path fails the same way a PATH without the binary does.
#   - The $GH_SHIM_BIN-prepended PATH used by the deliver/PR-creation tests
#     below (a fake `gh` that succeeds and records its invocation, not an
#     absent one) is a separate mechanism via `run_cmd`'s PATH override and
#     is untouched by this block.
#   - B09 may still split this file later; that is independent of B04.
# -->

# <!--
# Amendment: B06 deliver tip-restore (plan 002-fix-plan-001-followups)
#
# B04's freeze above is scoped to that refactor (rearranging the
# dependency-absent worlds), not to later contracts. B06 changes deliver's
# observable behavior, so two of B04's clauses no longer hold verbatim:
#   - The pass count moves from 115 to 120. It is still exact: any other
#     value is a defect.
#   - test_assemble_divergence_from_integration_tip_blocks_push is REPLACED,
#     not weakened. Its fixture (a path advanced on the integration branch
#     after the unit merged) is the one B06's contract names as "plan 001's
#     G5 abort case becomes a pass", so the same arrangement is now asserted
#     to succeed by
#     test_assemble_restores_integration_tip_content_not_unit_commit. Its
#     other assertions -- nothing pushed, no PR, delivery branch cleaned up
#     -- survive inverted in that test and unchanged in the other failure
#     tests. No other assertion in this file is weakened, skipped, merged,
#     or deleted.
# -->

# <!--
# Amendment: B07 manifest extraCommits (plan 002-fix-plan-001-followups)
#
# Same scoping as B06's amendment above: B04's freeze covers that refactor,
# not later contracts. B07 adds an optional manifest field, so one clause
# moves again:
#   - The pass count moves from 120 to 131. It is still exact: any other
#     value is a defect, whichever direction it moves.
# Nothing else changes. B07 appends eleven checks (in their own section after
# the realm.sh tests) and edits, reorders, weakens and deletes nothing: every
# assertion above them, B04's and B06's alike, is untouched.
# -->

# <!--
# Amendment: B10 deliver fresh-base resolution (plan 003-fix-plan-002-followups)
#
# Same scoping as the B06 and B07 amendments above: B04's freeze covers that
# refactor, not later contracts. B10 changes how deliver resolves
# <base-branch>, so one clause moves again:
#   - The pass count moves from 131 to 140. It is still exact: any other
#     value is a defect, whichever direction it moves.
# Nothing else changes. B10 appends nine tests in their own section after the
# B07 extraCommits tests and edits, reorders, weakens and deletes nothing.
# test_assemble_underlying_git_failure_on_push (the unreachable-origin
# fixture) was originally untouched here, asserting exit 4 with a single
# "ERROR: " line on the premise that a fresh-base deliver still reaches a
# push after resolving BASE_REF, whichever of the fetch or the push actually
# failed first. Superseded by B10 lego-delivery-refactor-reapply (plan
# 001-fix-pr-line-lengths): push no longer exists, and this fresh-base
# resolution's own ls-remote-first design (line ~1324 of worktree.sh) makes
# an unreachable origin indistinguishable from an origin that simply lacks
# <base-branch> -- ls-remote fails silently either way, so BASE_REF falls
# back to the local base and no fetch is even attempted. The premise this
# test pinned is gone; it is renamed and rewritten as
# test_assemble_unreachable_origin_falls_back_to_local_base, asserting the
# new correct behavior (exit 0, local-base fallback, no stderr) rather than
# the old exit-4 failure. See that test for the full rationale.
# -->
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

# Two deliver failures print plain (non-"ERROR: ") diagnostic lines before
# the single mandated error line, because that one line cannot carry the
# detail: the empty-file-list failure names the offending commit and why it
# restored nothing, and the divergence gate names every divergent path.
# assert_single_error_line's "exactly one stderr line" is too strict for
# those; what still holds there is exactly one line starting "ERROR: ".
assert_one_error_line() {
  local err="$1" label="$2"
  local n
  n="$(printf '%s\n' "$err" | grep -c '^ERROR: ')"
  if [ "$n" -ne 1 ]; then
    record_fail "$label: expected exactly 1 'ERROR: ' stderr line, got $n (stderr: $err)"
  fi
}

# ---------------------------------------------------------------------------
# Invocation helpers.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
RUN_OUT_LINES=0
RUN_OUT_LAST=""

# run_cmd <dir> <path-or-empty-for-default> <args...> — the PATH override is
# used by the $GH_SHIM_BIN deliver/PR-creation tests further down. To
# exercise the jq-/gh-absent seams instead, prefix the call with
# JQ=/nonexistent or GH=/nonexistent (e.g. `JQ=/nonexistent run_in "$repo"
# ...`) — bash exports a prefix assignment into the environment of
# everything the function invokes, including nested function calls and the
# subshell's `bash "$SCRIPT"` below.
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

# integrate_units <repo> <unit-branch>... -- puts the fixture into the
# production-shaped pre-delivery state: an "integration" branch forked from
# master (created on first use), every given unit branch merged into it
# --no-ff the way `worktree.sh merge` does, and that branch left checked
# out. deliver runs from the integration worktree with master as its base
# branch, and gates what it builds against the integration tip before
# pushing -- so any fixture whose deliver is expected to reach the push
# step must integrate its units first, exactly as the dispatch flow does.
# Called as a plain statement (it mutates the repo, prints nothing).
integrate_units() {
  local repo="$1"
  shift
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/integration"; then
    git -C "$repo" branch integration master
  fi
  git -C "$repo" checkout -q integration
  local b
  for b in "$@"; do
    git -C "$repo" merge -q --no-ff -m "lego: merge $b" "$b" >/dev/null
  done
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

  JQ=/nonexistent run_in "$repo" add plan1 U01 greetstuff
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
  run_in "$dir" assemble --manifest "$dir/unused-manifest.json" plan1 master U01 slug1
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

  GH=/nonexistent run_in "$repo" add plan1 U01 greetstuff
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

test_assemble_usage() {
  local repo manifest
  repo="$(new_git_repo)"
  # --manifest is parsed and required *before* the positional-argument usage
  # check (cmd_deliver checks manifest-presence first), so every one of
  # these usage-error invocations must carry a --manifest flag itself, or
  # they would now die exit 3 ("--manifest is required") instead of
  # exercising the exit-2 usage path this test is about. The path is never
  # read on any of these (usage_die fires first), so it need not exist.
  manifest="$repo/unused-manifest.json"

  run_in "$repo" assemble --manifest "$manifest"
  [ "$RUN_EXIT" -eq 2 ] || record_fail "no args: expected exit 2, got $RUN_EXIT"

  run_in "$repo" assemble --manifest "$manifest" plan1
  [ "$RUN_EXIT" -eq 2 ] || record_fail "1 arg: expected exit 2, got $RUN_EXIT"

  run_in "$repo" assemble --manifest "$manifest" plan1 master
  [ "$RUN_EXIT" -eq 2 ] || record_fail "2 args (plan-slug + base-branch, no unit id/slug pair): expected exit 2, got $RUN_EXIT"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01
  [ "$RUN_EXIT" -eq 2 ] || record_fail "3 args (dangling unit-id with no matching slug): expected exit 2, got $RUN_EXIT"
}

test_assemble_odd_paired_args() {
  local repo manifest
  repo="$(new_git_repo)"
  manifest="$repo/unused-manifest.json"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff U02
  [ "$RUN_EXIT" -eq 2 ] || record_fail "odd count of unit-id/unit-slug args after plan-slug+base-branch (U02 has no matching slug): expected exit 2, got $RUN_EXIT"
}

test_assemble_invalid_chars() {
  local repo manifest
  repo="$(new_git_repo)"
  manifest="$repo/unused-manifest.json"

  run_in "$repo" assemble --manifest "$manifest" "plan slug" master U01 greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "space in plan-slug: expected exit 2, got $RUN_EXIT"

  run_in "$repo" assemble --manifest "$manifest" plan1 "master;rm" U01 greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "invalid char in base-branch: expected exit 2, got $RUN_EXIT"

  run_in "$repo" assemble --manifest "$manifest" plan1 master "U0/1" greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "invalid char in unit-id: expected exit 2, got $RUN_EXIT"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 'slug;rm'
  [ "$RUN_EXIT" -eq 2 ] || record_fail "invalid char in unit-slug: expected exit 2, got $RUN_EXIT"
}

test_assemble_manifest_flag_required() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  run_in "$repo" assemble plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "deliver without --manifest: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "deliver without --manifest"
}

# B10: gh is no longer a dependency of assemble at all -- the old
# require_gh/missing-gh exit-3 path is removed along with every push/PR
# call. GH=/nonexistent must therefore succeed exactly like any other run;
# a lingering dependency check would regress this to exit 3.
test_assemble_succeeds_without_gh() {
  local repo manifest
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet_test.sh" "greet test v1" "lego(U01): tests"
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  manifest="$(write_valid_manifest "$repo" "test: succeeds without gh" "lego/deliver/plan1/U01" U01)"

  GH=/nonexistent run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "gh is no longer a dependency of assemble: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "lego/deliver/plan1/U01" "$RUN_OUT_LAST" "assembled branch name as last stdout line, GH=/nonexistent"
}

# B10: not only is gh not required -- it is never invoked, even when a
# working gh IS present on PATH and would succeed. The shim would record any
# invocation; a successful assemble must leave its log untouched.
test_assemble_never_invokes_gh_even_when_present() {
  local repo manifest
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet_test.sh" "greet test v1" "lego(U01): tests"
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  make_gh_shim
  manifest="$(write_valid_manifest "$repo" "test: never invokes gh" "lego/deliver/plan1/U01" U01)"

  run_cmd "$repo" "$GH_SHIM_BIN:$PATH" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "lego/deliver/plan1/U01" "$RUN_OUT_LAST" "assembled branch name as last stdout line"
  if [ -s "$GH_SHIM_LOG" ]; then
    record_fail "B10: assemble must never invoke gh, but the shim log is non-empty: $(cat "$GH_SHIM_LOG")"
  fi
}

test_assemble_missing_dependencies() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  # jq/config.json/blocks.md are all required before the manifest file is
  # read, so --manifest just needs to be present here too; content/existence
  # of the manifest path is irrelevant to these error paths.
  JQ=/nonexistent run_in "$repo" assemble --manifest "$repo/unused-manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "jq absent: expected exit 3, got $RUN_EXIT"
  # Same masking as the gh-absent case above: exit 3 alone also fires when
  # the manifest just isn't readable, so pin the message too.
  case "$RUN_ERR" in
    *jq*|*JQ*) : ;;
    *) record_fail "jq absent: diagnostic does not mention jq (stderr: $RUN_ERR)" ;;
  esac

  local repo2
  repo2="$(new_git_repo)"
  write_blocks_md "$repo2"
  run_in "$repo2" assemble --manifest "$repo2/unused-manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "config.json missing: expected exit 3, got $RUN_EXIT"

  local repo3
  repo3="$(new_git_repo)"
  write_config_json "$repo3" "true"
  run_in "$repo3" assemble --manifest "$repo3/unused-manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "blocks.md missing: expected exit 3, got $RUN_EXIT"
}

test_assemble_zero_branch_match() {
  local repo manifest
  repo="$(build_deliver_base)"
  manifest="$(write_valid_manifest "$repo" "test: zero branch match" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "constructed unit branch absent: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "constructed unit branch absent"
}

test_assemble_cross_plan_isolation() {
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
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: cross plan isolation" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
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
test_assemble_stale_tests_commit_in_base_history_is_skipped() {
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
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  mkdir -p "$repo/.local"
  jq -n '{title: "test: stale tests subject outside unit paths", branch: "lego/deliver/plan1/U01", commits: {U01: {impl: "lego(U01): implementation"}}}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
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

# An implementation commit that touches no files (a prose unit committed
# with --allow-empty) derives an EMPTY file list: there is nothing to
# restore, so the unit contributes nothing to the PR. That is a defect, not
# a no-op -- deliver fails the build rather than opening a PR silently
# missing the unit. The distinguishing diagnostic must say the commit
# touched no files, not that it was a merge.
test_assemble_unit_with_empty_commit_fails_loudly() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U03-nocodeslug" master
  git -C "$repo" commit -q --allow-empty -m "lego(U03): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U03-nocodeslug"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: empty commits" "lego/deliver/plan1/U03" U03)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U03 nocodeslug
  [ "$RUN_EXIT" -eq 4 ] || record_fail "empty implementation commit: expected exit 4, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_one_error_line "$RUN_ERR" "empty implementation commit"
  case "$RUN_ERR" in
    *"touched no files"*) : ;;
    *) record_fail "expected stderr to distinguish 'touched no files' from the merge-commit case: got [$RUN_ERR]" ;;
  esac
  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U03"; then
    record_fail "expected no delivery branch to survive the failed build"
  fi
}

# Regression tests for the "unit subject lands on a merge commit" defect.
# Refreshing a unit branch mid-flight with
# `git merge <integration-branch> -m "lego(U01): implementation"` puts the
# unit's exact subject on a MERGE commit, and git diff-tree prints no paths
# for a merge -- so resolving that merge as the unit's commit derives an
# empty file list and the unit contributes nothing. The commit-subject scan
# skips merges, so the plain same-subject commit (what the
# merge-then-stamp-a-separate-commit workaround already assumes) is what
# gets delivered.
test_assemble_stamped_merge_commit_is_not_resolved() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  # Concurrent work folded into the unit branch with the unit's own subject
  # stamped onto the merge itself. It is NEWER than the plain commit above,
  # so a scan that considers merges picks it and restores nothing.
  git -C "$repo" checkout -q -b concurrent-work master
  commit_file "$repo" "src/other.sh" "other v1" "concurrent work"
  git -C "$repo" checkout -q "lego/plan1/U01-greetstuff"
  git -C "$repo" merge -q --no-ff -m "lego(U01): implementation" concurrent-work >/dev/null
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  mkdir -p "$repo/.local"
  jq -n '{title: "test: stamped merge is not resolved", branch: "lego/deliver/plan1/U01",
          commits: {U01: {impl: "lego(U01): implementation"}}}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    local greet_content subjects
    greet_content="$(git -C "$repo" show "lego/deliver/plan1/U01:src/greet.sh" 2>/dev/null || echo "MISSING")"
    assert_eq "greet v1" "$greet_content" "the plain same-subject commit is delivered; the newer stamped merge (which restores nothing) is skipped"
    subjects="$(git -C "$repo" log --format=%s master..lego/deliver/plan1/U01 2>/dev/null)"
    if ! printf '%s\n' "$subjects" | grep -qF "lego(U01): implementation"; then
      record_fail "expected the delivery branch to carry the implementation commit, not an empty delivery"
    fi
  else
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  fi
}

# Same defect, no plain commit to fall back on: the unit's exact subject
# exists ONLY on a stamped merge. Skipping merges leaves nothing to
# resolve, so deliver must fail loudly (missing required implementation
# commit) rather than open a PR that silently omits the unit.
test_assemble_only_a_stamped_merge_fails_loudly() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  # The unit's work is here, but under a subject deliver does not look for.
  commit_file "$repo" "src/greet.sh" "greet v1" "wip: greeting"
  git -C "$repo" checkout -q -b concurrent-work master
  commit_file "$repo" "src/other.sh" "other v1" "concurrent work"
  git -C "$repo" checkout -q "lego/plan1/U01-greetstuff"
  # ...and the exact subject is carried only by the refresh merge.
  git -C "$repo" merge -q --no-ff -m "lego(U01): implementation" concurrent-work >/dev/null
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  mkdir -p "$repo/.local"
  jq -n '{title: "test: only a stamped merge", branch: "lego/deliver/plan1/U01",
          commits: {U01: {impl: "lego(U01): implementation"}}}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "a unit whose only same-subject commit is a merge must fail loudly: expected exit 4, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_one_error_line "$RUN_ERR" "stamped merge is the only same-subject commit"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    record_fail "expected no delivery branch to survive the failed deliver"
  fi
}

# ===========================================================================
# deliver: tip-restore (B06 deliver tip-restore, plan 002)
#
# restore_and_commit takes every restored path's CONTENT from the integration
# tip -- the HEAD of the worktree deliver was invoked from. The resolved unit
# commit supplies only the subject's provenance and, when no explicit paths
# are passed, the file list via git diff-tree. Plan 001's byte-gate abort
# case (a path advanced on integration after the unit merged) is inverted by
# this contract into the headline pass below; the gate itself is unchanged
# and now passes by construction for content this function wrote.
# ===========================================================================

# The headline behavior, and the same fixture plan 001 asserted aborts at the
# byte-gate: the integration branch carries a follow-up fix to a delivered
# path that never reached the unit branch. Restoring from the unit commit
# replays the older state and the gate would have blocked the build (under
# B10 there is no push to stop, but the gate's abort condition is unchanged);
# restoring from the tip delivers the fix and the build succeeds.
test_assemble_restores_integration_tip_content_not_unit_commit() {
  local repo head_before status_before
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1 (unit)\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  commit_file "$repo" "src/greet.sh" $'greet v2 (fixed on the integration branch)\n' \
    "fix: follow-up that never reached the unit branch"

  head_before="$(git -C "$repo" rev-parse HEAD)"
  status_before="$(git -C "$repo" status --porcelain)"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: tip restore" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "a path advanced on integration after the unit merged must deliver the tip content, not abort: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "lego/deliver/plan1/U01" "$RUN_OUT_LAST" "assembled branch name as last stdout line"
  case "$RUN_ERR" in
    *"diverges from the integration tip"*)
      record_fail "the byte-gate must pass by construction under tip-restore: got [$RUN_ERR]" ;;
  esac

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    local delivered
    delivered="$(git -C "$repo" show "lego/deliver/plan1/U01:src/greet.sh" 2>/dev/null || echo "MISSING")"
    assert_eq "greet v2 (fixed on the integration branch)" "$delivered" "restored content comes from the integration tip, not from the resolved unit commit"
  else
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  fi

  if [ -n "$(git -C "$repo" ls-remote --heads origin "lego/deliver/plan1/U01" 2>/dev/null)" ]; then
    record_fail "B10: assemble never pushes anywhere -- the delivery branch must not appear on origin"
  fi

  assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "deliver never moves the integration worktree's HEAD"
  assert_eq "$status_before" "$(git -C "$repo" status --porcelain)" "deliver never modifies the integration worktree's files"
}

# Content comes from the tip; the FILE LIST still comes from the unit
# commit's own diff-tree. A path that moved on integration but appears in no
# unit commit must not be swept into the delivery, and the byte-gate stays
# scoped to the restored union rather than the whole tree.
test_assemble_file_list_still_comes_from_the_unit_commit() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1 (unit)\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  # Two paths move on integration after the merge; only src/greet.sh is in
  # the unit commit's diff-tree.
  commit_files "$repo" "fix: follow-ups on the integration branch" \
    "src/greet.sh" $'greet v2 (integration)\n' \
    "src/other.sh" $'other v2 (integration, in no unit commit)\n'

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: file list from the unit commit" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    local greet_delivered other_delivered
    greet_delivered="$(git -C "$repo" show "lego/deliver/plan1/U01:src/greet.sh" 2>/dev/null || echo "MISSING")"
    other_delivered="$(git -C "$repo" show "lego/deliver/plan1/U01:src/other.sh" 2>/dev/null || echo "MISSING")"
    assert_eq "greet v2 (integration)" "$greet_delivered" "a path in the unit commit's diff-tree carries the tip's content"
    assert_eq "other v0" "$other_delivered" "a path that moved on integration but is in no unit commit stays at the base branch's content -- the file list is the unit commit's, not the tip's"
  else
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  fi
}

# A restored path that is ABSENT at the integration tip and TRACKED in the
# delivery worktree is removed, so the delivery matches the tip there too.
test_assemble_path_absent_at_tip_is_removed_when_tracked() {
  local repo
  repo="$(build_deliver_base)"
  # On master (the delivery base), so the delivery worktree tracks it. The
  # push keeps the seed on origin/master too -- deliver resolves its base
  # fresh from origin, so origin/master is the actual delivery base.
  commit_file "$repo" "src/doomed.sh" $'doomed v0\n' "seed a path the unit touches and integration later deletes"
  git -C "$repo" push -q origin master >/dev/null 2>&1

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/doomed.sh" $'doomed v1 (unit)\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  git -C "$repo" rm -q -- "src/doomed.sh"
  git -C "$repo" commit -q -m "fix: the unit's path is deleted on the integration branch"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: path absent at tip is removed" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "a path deleted on integration must be removed from the delivery, not abort: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  case "$RUN_ERR" in
    *"diverges from the integration tip"*)
      record_fail "removing a path absent at the tip must satisfy the byte-gate, not trip it: got [$RUN_ERR]" ;;
  esac

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    if git -C "$repo" cat-file -e "lego/deliver/plan1/U01:src/doomed.sh" 2>/dev/null; then
      record_fail "expected src/doomed.sh (absent at the integration tip, tracked in the delivery worktree) to be removed from the delivery branch"
    fi
    local subjects
    subjects="$(git -C "$repo" log --format=%s master..lego/deliver/plan1/U01 2>/dev/null)"
    if ! printf '%s\n' "$subjects" | grep -qF "test impl for U01"; then
      record_fail "expected the removal to be a real staged change and produce the implementation commit"
    fi
  else
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  fi
}

# The same absent-at-tip path, but UNTRACKED in the delivery worktree (the
# unit added it and integration dropped it again, so the base branch never
# had it): there is nothing to remove, so it is silently skipped -- not a git
# failure, and not restored from the unit commit either.
test_assemble_path_absent_at_tip_and_untracked_is_skipped() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_files "$repo" "lego(U01): implementation" \
    "src/greet.sh" $'greet v1 (unit)\n' \
    "src/unit-only.sh" $'unit-only v1\n'
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  git -C "$repo" rm -q -- "src/unit-only.sh"
  git -C "$repo" commit -q -m "fix: the unit's new file is dropped on the integration branch"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: absent and untracked is skipped" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "a path absent at the tip and untracked in the delivery worktree must be skipped, not fail: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ -z "$RUN_ERR" ] || record_fail "skipping an untracked absent path must be silent: got stderr [$RUN_ERR]"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    if git -C "$repo" cat-file -e "lego/deliver/plan1/U01:src/unit-only.sh" 2>/dev/null; then
      record_fail "expected src/unit-only.sh (absent at the integration tip) not to be restored from the unit commit"
    fi
    local greet_delivered
    greet_delivered="$(git -C "$repo" show "lego/deliver/plan1/U01:src/greet.sh" 2>/dev/null || echo "MISSING")"
    assert_eq "greet v1 (unit)" "$greet_delivered" "the sibling path in the same commit still carries the tip's content"
  else
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  fi
}

# The no-op rule survives the change of content source: when the TIP's
# content for a restored path already equals what the delivery worktree
# holds, the restore stages nothing and no commit is created. Here
# integration backs the unit's change out again, so the implementation
# restore is a genuine no-op even though the unit commit does differ.
test_assemble_noop_restore_when_tip_matches_the_delivery_base() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet_test.sh" $'greet test v1\n' "lego(U01): tests"
  commit_file "$repo" "src/greet.sh" $'greet v1 (unit)\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  commit_file "$repo" "src/greet.sh" $'greet v0\n' "revert: back the unit's change out on the integration branch"

  mkdir -p "$repo/.local"
  jq -n '{title: "test: no-op restore under tip content", branch: "lego/deliver/plan1/U01",
          commits: {U01: {tests: "lego(U01): contract + tests", impl: "lego(U01): implementation"}}}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    local subjects greet_delivered
    subjects="$(git -C "$repo" log --format=%s master..lego/deliver/plan1/U01 2>/dev/null)"
    if ! printf '%s\n' "$subjects" | grep -qF "lego(U01): contract + tests"; then
      record_fail "expected the tests restore (which does change content) to produce its commit"
    fi
    if printf '%s\n' "$subjects" | grep -qF "lego(U01): implementation"; then
      record_fail "a restore whose tip content matches the delivery worktree must stage no diff and create no commit"
    fi
    greet_delivered="$(git -C "$repo" show "lego/deliver/plan1/U01:src/greet.sh" 2>/dev/null || echo "MISSING")"
    assert_eq "greet v0" "$greet_delivered" "the delivered path still matches the integration tip after the no-op restore"
  else
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  fi
}

# The empty-file-list failure is unchanged, and is still derived from the
# UNIT COMMIT: an implementation commit that touched no files fails loudly
# with the distinguishing diagnostic even when the integration tip is full of
# content a tip-derived file list would have found.
test_assemble_empty_unit_commit_still_fails_when_the_tip_has_content() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U03-nocodeslug" master
  git -C "$repo" commit -q --allow-empty -m "lego(U03): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U03-nocodeslug"
  commit_file "$repo" "src/other.sh" $'other v2 (integration)\n' "fix: unrelated work on the integration branch"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: empty commit, non-empty tip" "lego/deliver/plan1/U03" U03)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U03 nocodeslug
  [ "$RUN_EXIT" -eq 4 ] || record_fail "empty implementation commit: expected exit 4, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_one_error_line "$RUN_ERR" "empty implementation commit under tip-restore"
  case "$RUN_ERR" in
    *"touched no files"*) : ;;
    *) record_fail "expected stderr to distinguish 'touched no files' from the merge-commit case: got [$RUN_ERR]" ;;
  esac
  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U03"; then
    record_fail "expected no delivery branch to survive the failed build"
  fi
}

test_assemble_missing_implementation_commit_fails() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U04-needsimplslug" master
  commit_file "$repo" "src/needsimpl.sh" "needsimpl tests only" "lego(U04): tests"
  git -C "$repo" checkout -q master

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: missing impl commit" "lego/deliver/plan1/U04" U04)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U04 needsimplslug
  [ "$RUN_EXIT" -eq 4 ] || record_fail "missing implementation commit: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "missing implementation commit"
}

test_assemble_delivery_branch_already_exists() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  git -C "$repo" branch "lego/deliver/plan1/U01" master

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: delivery branch pre-exists" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "delivery branch pre-exists: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "delivery branch pre-exists (EC3)"
}

# B10 lego-delivery-refactor-reapply (plan 001-fix-pr-line-lengths): this
# fixture used to fail at deliver's push (exit 4). Under B10, assemble has
# no push at all, and the fresh-base resolution's own design (worktree.sh
# ~line 1324: `ls-remote --heads origin <base-branch>` with stderr
# discarded) makes an unreachable origin indistinguishable from an origin
# that simply lacks <base-branch> -- both make ls-remote report nothing, so
# BASE_REF falls back to the local base and no fetch is even attempted. The
# correct behavior for this exact fixture is therefore success, built from
# the local base unchanged. (The silent-fallback diagnosability question --
# should an unreachable origin be distinguished from one merely lacking the
# branch? -- is out of scope here; tracked as follow-up F08.)
test_assemble_unreachable_origin_falls_back_to_local_base() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  git -C "$repo" remote set-url origin "/nonexistent/path/that/does/not/exist.git"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: unreachable origin" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "unreachable origin: fresh-base resolution treats a failed ls-remote the same as an origin lacking <base-branch> (local-base fallback, no push to fail at under B10): expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "lego/deliver/plan1/U01" "$RUN_OUT_LAST" "assembled branch name as last stdout line, unreachable origin"
  if [ -n "$RUN_ERR" ]; then
    record_fail "unreachable origin falling back to the local base must be silent on stderr: got [$RUN_ERR]"
  fi
  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    assert_eq "greet v1" "$(git -C "$repo" show "lego/deliver/plan1/U01:src/greet.sh" 2>/dev/null || echo MISSING)" "delivery branch built from the local base ref, unaffected by the unreachable origin"
  else
    record_fail "expected delivery branch lego/deliver/plan1/U01 to exist"
  fi
}

test_assemble_tests_commit_optional_success() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo v1" "lego(U02): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U02-soloslug"

  # commits.U02.impl must equal the literal string this test asserts is on
  # the delivery branch, since impl subject is now always manifest-sourced
  # (impl is a required field with no default fallback once a manifest is
  # mandatory).
  mkdir -p "$repo/.local"
  jq -n '{title: "test: tests commit optional", branch: "lego/deliver/plan1/U02", commits: {U02: {impl: "lego(U02): implementation"}}}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ "$RUN_OUT_LINES" -eq 1 ] || record_fail "expected exactly 1 stdout line (assembled branch name), got $RUN_OUT_LINES"
  assert_eq "lego/deliver/plan1/U02" "$RUN_OUT_LAST" "assembled branch name as last stdout line"

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

test_assemble_single_unit_union_and_newest_and_spaces() {
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
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  # Manifest title/branch/commit subjects mirror the old defaults' shapes
  # ("lego: U01" / "lego/deliver/plan1/U01" / etc.) purely so the
  # delivery-branch/commit-subject assertions below check for those exact
  # strings. This proves manifest pass-through wiring, not the (now-removed)
  # hardcoded defaults; title itself is otherwise vestigial (never consumed
  # by any gh/PR call under B10).
  mkdir -p "$repo/.local"
  jq -n '{title: "lego: U01", branch: "lego/deliver/plan1/U01",
          commits: {U01: {tests: "lego(U01): contract + tests", impl: "lego(U01): implementation"}}}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ "$RUN_OUT_LINES" -eq 1 ] || record_fail "expected exactly 1 stdout line (assembled branch name), got $RUN_OUT_LINES"
  assert_eq "lego/deliver/plan1/U01" "$RUN_OUT_LAST" "assembled branch name as last stdout line"

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
    record_fail "expected the temporary delivery worktree to be removed after assemble (D4)"
  fi
}

test_assemble_multi_unit_branch_naming_and_pr_title_order() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet NEW" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo NEW" "lego(U02): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff" "lego/plan1/U02-soloslug"

  # Branch naming is no longer constructed by deliver at all -- it always
  # comes from the (now-required) manifest "branch" field. Use explicit
  # custom values (not the old "lego/deliver/.../U01+U02" / "lego: ..."
  # shapes) so a pass only proves the manifest value was honored, not that
  # it happens to coincide with a removed default.
  local manifest
  manifest="$(jq -n '{title: "Custom multi-unit title U01 U02", branch: "custom/multi-unit-delivery",
                       commits: {U01: {impl: "impl subject for U01"}, U02: {impl: "impl subject for U02"}}}')"
  printf '%s' "$manifest" > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/custom/multi-unit-delivery"; then
    record_fail "expected delivery branch 'custom/multi-unit-delivery' (manifest-provided) to exist"
  fi
  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01+U02"; then
    record_fail "expected the old constructed default branch name NOT to be created; branch is manifest-only now"
  fi

  assert_eq "custom/multi-unit-delivery" "$RUN_OUT_LAST" "assembled branch name (manifest-provided) as last stdout line"
}

test_assemble_multi_unit_argument_order_is_not_sorted() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet NEW" "lego(U01): implementation"
  git -C "$repo" checkout -q master

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" "solo NEW" "lego(U02): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff" "lego/plan1/U02-soloslug"

  # The delivery branch name is now entirely manifest-provided (not
  # constructed from unit-id argument order at all), so branch naming no
  # longer proves anything about argument order. Under B10 there is no PR
  # body to inspect either (the old ALL_HEADINGS-in-argument-order proof
  # lived there). What still depends on argument order is the delivery
  # branch's own commit sequence: units are restored in argument order, so
  # delivering U02 before U01 must produce U02's implementation commit
  # BEFORE (older than) U01's on the resulting branch, proving the
  # restore iteration is positional, not sorted.
  local manifest
  manifest="$(jq -n '{title: "test: order not sorted", branch: "custom/order-test-branch",
                       commits: {U01: {impl: "impl subject for U01"}, U02: {impl: "impl subject for U02"}}}')"
  printf '%s' "$manifest" > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U02 soloslug U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/custom/order-test-branch"; then
    record_fail "expected delivery branch 'custom/order-test-branch' (manifest-provided, order-independent) to exist"
  else
    local subjects u01_line u02_line
    subjects="$(git -C "$repo" log --format=%s custom/order-test-branch)"
    # git log lists newest-first: the unit argued LAST is restored last and
    # so its commit is newest, appearing EARLIER (smaller line number) here.
    u01_line="$(printf '%s\n' "$subjects" | grep -nF "impl subject for U01" | head -n1 | cut -d: -f1)"
    u02_line="$(printf '%s\n' "$subjects" | grep -nF "impl subject for U02" | head -n1 | cut -d: -f1)"
    if [ -z "$u01_line" ] || [ -z "$u02_line" ]; then
      record_fail "expected both U01's and U02's implementation commits on the delivery branch"
    elif [ "$u01_line" -ge "$u02_line" ]; then
      record_fail "expected U01's commit (argued second: U02 then U01) to be newer than U02's, reflecting argument order, not sorted"
    fi
  fi
}

test_assemble_noop_restore_creates_no_second_commit() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U05-noopslug" master
  commit_file "$repo" "src/noop.sh" "noop FINAL" "lego(U05): tests"
  # implementation commit deliberately does not touch src/noop.sh (B06's
  # only Code path); restoring it should therefore be a no-op.
  commit_file "$repo" "src/needsimpl.sh" "irrelevant change" "lego(U05): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U05-noopslug"

  # commits.U05.tests is deliberately left unset: this exercises the
  # optional-tests-subject fallback (B01 clause 6) at the same time, and the
  # default "lego(U05): contract + tests" is what the assertion below checks
  # for. impl's value is arbitrary since the restore is a no-op (no commit
  # is ever created from it).
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: noop restore" "lego/deliver/plan1/U05" U05)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U05 noopslug
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

test_assemble_manifest_invalid_file() {
  local repo
  repo="$(build_deliver_base)"
  # Manifest validation happens before any unit-branch resolution, so no
  # unit branch needs to exist to exercise this error path.

  run_in "$repo" assemble --manifest "$repo/.local/does-not-exist.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "unreadable manifest path: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "unreadable manifest path"
}

test_assemble_manifest_invalid_json() {
  local repo
  repo="$(build_deliver_base)"
  printf 'not { valid json' > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "manifest file is not valid JSON: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest file is not valid JSON"
}

test_assemble_manifest_missing_title() {
  local repo
  repo="$(build_deliver_base)"
  # Manifest validation (and thus this rejection) happens before any
  # unit-branch resolution, so no unit branch needs to exist.
  jq -n '{branch: "lego/deliver/plan1/U01", commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "manifest missing title: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest missing title"
  case "$RUN_ERR" in
    *title*) : ;;
    *) record_fail "expected error message to name the missing field (title): got [$RUN_ERR]" ;;
  esac
}

test_assemble_manifest_missing_branch() {
  local repo
  repo="$(build_deliver_base)"
  jq -n '{title: "test: missing branch", commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "manifest missing branch: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest missing branch"
  case "$RUN_ERR" in
    *branch*) : ;;
    *) record_fail "expected error message to name the missing field (branch): got [$RUN_ERR]" ;;
  esac
}

test_assemble_manifest_missing_unit_impl() {
  local repo
  repo="$(build_deliver_base)"

  # Single delivered unit, commits.<id>.impl absent entirely (no "commits"
  # key at all).
  jq -n '{title: "test: missing unit impl", branch: "lego/deliver/plan1/U01"}' \
    > "$repo/.local/manifest.json"
  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "manifest missing commits.U01.impl (no commits key): expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest missing commits.U01.impl (no commits key)"

  # Two delivered units: the first has a valid impl subject, the second
  # doesn't -- proves the check runs for every delivered unit-id, not just
  # the first.
  jq -n '{title: "test: missing unit impl multi", branch: "lego/deliver/plan1/U01+U02",
          commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"
  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff U02 soloslug
  [ "$RUN_EXIT" -eq 3 ] || record_fail "manifest missing commits.U02.impl (second of two units): expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest missing commits.U02.impl (second of two units)"
}

test_assemble_manifest_body_optional_default() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  # A full manifest (title, branch, commits.U01.impl) but no "body": under
  # B10 body is vestigial (never consumed by any gh/PR call), so all this
  # proves is that omitting it is not a validation failure -- required-field
  # validation is scoped to title/branch/commits.<id>.impl only.
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: body optional" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "manifest omitting 'body' must not fail validation: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
}

test_assemble_manifest_tests_subject_optional_default() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_files "$repo" "lego(U01): tests" "src/greet_test.sh" "greet test v1"
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  # A full manifest but no commits.U01.tests: when a tests commit exists on
  # the unit branch, its delivered subject must fall back to the default
  # "lego(U01): contract + tests".
  local manifest
  manifest="$(write_valid_manifest "$repo" "test: tests subject optional" "lego/deliver/plan1/U01" U01)"


  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
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

# title/body override no longer have any observable effect under B10 (no
# gh/PR call consumes them; they are vestigial pass-through fields), so the
# old title- and body-override tests are gone. What survives from them is
# the still-load-bearing invariant both relied on incidentally: the manifest
# file itself is read-only and must never be modified by assemble.
test_assemble_manifest_file_is_read_only() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  jq -n '{title: "Custom PR Title", body: "Custom PR body text",
          branch: "lego/deliver/plan1/U01", commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"
  local manifest_before
  manifest_before="$(cat "$repo/.local/manifest.json")"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  local manifest_after
  manifest_after="$(cat "$repo/.local/manifest.json")"
  assert_eq "$manifest_before" "$manifest_after" "manifest file is read-only and must never be modified by assemble"
}

test_assemble_manifest_branch_override() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  # title and commits.U01.impl are also required now; fill them with
  # arbitrary valid values so this test isolates the branch-override
  # behavior it's named for.
  jq -n '{title: "test: branch override", branch: "custom/delivery-branch",
          commits: {U01: {impl: "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"


  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/custom/delivery-branch"; then
    record_fail "expected delivery branch 'custom/delivery-branch' (manifest override) to exist"
  fi
  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U01"; then
    record_fail "expected the default delivery branch name NOT to be created when manifest overrides branch"
  fi
}

test_assemble_manifest_commit_subjects_override() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_files "$repo" "lego(U01): tests" "src/greet_test.sh" "greet test v1"
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  # title and branch are also required now; fill them with arbitrary valid
  # values so this test isolates the commit-subject-override behavior it's
  # named for.
  jq -n '{title: "test: commit subjects override", branch: "lego/deliver/plan1/U01",
          commits: {U01: {tests: "custom tests subject", impl: "custom impl subject"}}}' \
    > "$repo/.local/manifest.json"


  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
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

test_assemble_manifest_partial() {
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

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "partial manifest missing branch/commits.impl: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "partial manifest missing required fields"
}

test_assemble_manifest_branch_already_exists() {
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

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "manifest branch already exists: expected exit 4, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "manifest branch already exists"
}

test_assemble_manifest_empty_object() {
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
  # test_assemble_manifest_branch_already_exists.

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "empty object manifest missing required fields: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "empty object manifest missing required fields"
}

test_assemble_manifest_empty_string_field_treated_as_absent() {
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
  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "empty-string title treated as absent: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "empty-string title treated as absent"

  printf '{"title": "t", "branch": "", "commits": {"U01": {"impl": "test impl for U01"}}}' \
    > "$repo/.local/manifest.json"
  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "empty-string branch treated as absent: expected exit 3, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "empty-string branch treated as absent"

  printf '{"title": "t", "branch": "lego/deliver/plan1/U01", "commits": {"U01": {"impl": ""}}}' \
    > "$repo/.local/manifest.json"
  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
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
test_assemble_files_not_in_code_field_are_included() {
  local repo
  repo="$(build_deliver_base)"

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo_test.sh" "solo test v1" "lego(U02): tests"
  commit_file "$repo" "src/solo.sh" "solo v1" "lego(U02): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U02-soloslug"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: unlisted files" "lego/deliver/plan1/U02" U02)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/lego/deliver/plan1/U02"; then
    local test_file_content impl_file_content
    test_file_content="$(git -C "$repo" show "lego/deliver/plan1/U02:src/solo_test.sh" 2>/dev/null || echo "MISSING")"
    impl_file_content="$(git -C "$repo" show "lego/deliver/plan1/U02:src/solo.sh" 2>/dev/null || echo "MISSING")"
    assert_eq "solo test v1" "$test_file_content" "test file not in Code: field is delivered from the tests commit"
    assert_eq "solo v1" "$impl_file_content" "impl file is delivered from the impl commit"
  else
    record_fail "expected delivery branch lego/deliver/plan1/U02 to exist"
  fi
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

# B10: deliver is gone as a subcommand name -- it must be rejected exactly
# like any other unrecognized subcommand (usage error, exit 2), not treated
# as a deprecated alias for assemble.
test_deliver_subcommand_is_unknown() {
  local repo
  repo="$(new_git_repo)"

  run_in "$repo" deliver --manifest "$repo/unused-manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 2 ] || record_fail "B10: 'deliver' must be an unknown subcommand: expected exit 2, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "deliver as unknown subcommand"
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

test_assemble_cleanup_removes_unit_branch_and_worktree() {
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
  integrate_units "$repo" "$branch"
  # A worktree for the unit branch still lingers (e.g. merge's own best-effort
  # cleanup did not run or did not succeed) -- deliver must remove it too.
  git -C "$repo" worktree add -q "$wt" "$branch"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: cleanup removes branch and worktree" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "lego/deliver/plan1/U01" "$RUN_OUT_LAST" "assembled branch name still printed as last stdout line after cleanup"

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

test_assemble_cleanup_branch_deletion_failure_still_exits_0() {
  local repo branch
  repo="$(build_deliver_base)"
  branch="lego/plan1/U01-greetstuff"

  git -C "$repo" checkout -q -b "$branch" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  # Deliberately do NOT merge the unit branch anywhere: it stays unmerged,
  # so `git branch -d` in deliver's cleanup step will fail. The integration
  # branch still reaches the same delivered CONTENT by its own commit, so
  # the pre-push divergence gate passes and deliver gets as far as the
  # cleanup step this test is about -- which also pins the gate down as a
  # content comparison, not an ancestry one.
  git -C "$repo" checkout -q -b integration master
  commit_file "$repo" "src/greet.sh" "greet v1" "same content, reached without merging the unit branch"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: cleanup branch deletion failure" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "deliver cleanup failure must never change deliver's exit code: expected exit 0, got $RUN_EXIT"
  assert_eq "lego/deliver/plan1/U01" "$RUN_OUT_LAST" "assembled branch name still printed despite cleanup failure"

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
# archive_unit_local: unit audit-trail archiving (B01 worktree-unit-archive,
# plan 001-brief-report-archive)
#
# archive_unit_local is an internal helper with no CLI entry point of its
# own -- every test here exercises it only through merge, deliver, remove,
# and clean, exactly as the file-header docblock's call-site clauses
# describe. A worktree with a real seeded .local/ (briefs/, reports/,
# status.md) requires going through `worktree.sh add`, not a manual
# `git worktree add`, so fixtures below use `add` whenever there is
# something to archive.
# ===========================================================================

test_archive_merge_copies_three_components_only() {
  local repo wt branch dest wt_status_content dest_entries
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  wt="$(dirname "$repo")/$(basename "$repo")-U01"
  branch="lego/plan1/U01-greetstuff"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add failed: $RUN_ERR"; return; }

  printf 'brief one\n' > "$wt/.local/briefs/01-a.md"
  printf 'report one\n' > "$wt/.local/reports/01-a.md"
  wt_status_content="$(cat "$wt/.local/status.md" 2>/dev/null)"
  commit_file "$wt" "feature.txt" "feature content" "unit work"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  dest="$repo/.local/units/plan1/U01"
  assert_eq "brief one" "$(cat "$dest/briefs/01-a.md" 2>/dev/null)" "archived briefs/01-a.md content intact"
  assert_eq "report one" "$(cat "$dest/reports/01-a.md" 2>/dev/null)" "archived reports/01-a.md content intact"
  assert_eq "$wt_status_content" "$(cat "$dest/status.md" 2>/dev/null)" "archived status.md content intact"

  if [ -e "$dest/unit.md" ]; then
    record_fail "unit.md must not be archived (only briefs/, reports/, status.md)"
  fi
  if [ -e "$dest/config.json" ]; then
    record_fail "config.json must not be archived"
  fi
  if [ -e "$dest/contracts" ]; then
    record_fail "contracts/ must not be archived"
  fi
  dest_entries="$(ls -A "$dest" 2>/dev/null | sort | tr '\n' ' ')"
  assert_eq "briefs reports status.md " "$dest_entries" "archive destination contains exactly the three components, nothing else"

  # Ordering: the archive exists BECAUSE it happens before removal -- assert
  # both the archive contents (above) and the worktree's removal (below) in
  # this same test.
  if [ -d "$wt" ]; then
    record_fail "expected the unit worktree to be removed after a successful merge+archive"
  fi
  if git -C "$repo" worktree list | grep -qF "$wt"; then
    record_fail "expected git worktree list to no longer include the removed unit worktree"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected the unit branch to still exist after merge (merge never removes the branch)"
  fi
}

test_archive_plan_scoping_isolates() {
  local repo wtA wtB
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  wtA="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add planA U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add planA failed: $RUN_ERR"; return; }
  printf 'planA brief\n' > "$wtA/.local/briefs/01.md"
  commit_file "$wtA" "featureA.txt" "featureA" "unit work A"

  run_in "$repo" merge planA U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "planA merge: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  # planA's worktree is gone now (merge removed it), so the same path is
  # free for planB's own U01 worktree.
  wtB="$(dirname "$repo")/$(basename "$repo")-U01"
  run_in "$repo" add planB U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add planB failed: $RUN_ERR"; return; }
  printf 'planB brief\n' > "$wtB/.local/briefs/01.md"
  commit_file "$wtB" "featureB.txt" "featureB" "unit work B"

  run_in "$repo" merge planB U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "planB merge: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  assert_eq "planA brief" "$(cat "$repo/.local/units/planA/U01/briefs/01.md" 2>/dev/null)" "planA's archive is untouched by planB's later merge (plan-scoped, no clobber)"
  assert_eq "planB brief" "$(cat "$repo/.local/units/planB/U01/briefs/01.md" 2>/dev/null)" "planB's archive has its own content, separate from planA"
}

test_archive_skips_absent_components_without_failing() {
  local repo wt dest
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add failed: $RUN_ERR"; return; }

  # briefs/ absent entirely (not merely empty); reports/ and status.md
  # present.
  rm -rf -- "$wt/.local/briefs"
  printf 'report x\n' > "$wt/.local/reports/x.md"
  commit_file "$wt" "feature.txt" "feature" "unit work"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  dest="$repo/.local/units/plan1/U01"
  if [ -e "$dest/briefs" ]; then
    record_fail "briefs/ absent from the source must not appear at the destination at all"
  fi
  assert_eq "report x" "$(cat "$dest/reports/x.md" 2>/dev/null)" "reports/ still archived when briefs/ is absent"
  if [ ! -f "$dest/status.md" ]; then
    record_fail "status.md should still be archived when briefs/ is absent"
  fi
}

test_archive_nothing_when_source_has_no_local_at_all() {
  local repo container branch wt
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  branch="lego/plan1/U01-greetstuff"
  wt="$container/manual-wt-U01"

  # A worktree created by hand, not via `add` -- no .local/ at all (NEW,
  # plan 001-bra edge case).
  git -C "$repo" branch "$branch"
  git -C "$repo" worktree add -q "$wt" "$branch"
  commit_file "$wt" "feature.txt" "feature content" "unit work"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ -e "$repo/.local" ]; then
    record_fail "expected no .local/ at all to be created in the invoking worktree when the source worktree has none"
  fi
}

test_archive_nothing_when_local_has_none_of_the_three_components() {
  local repo wt
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add failed: $RUN_ERR"; return; }

  # .local/ is non-empty (unit.md, config.json, contracts/ are all seeded
  # by add) but holds none of the three archived components.
  rm -rf -- "$wt/.local/briefs" "$wt/.local/reports" "$wt/.local/status.md"
  commit_file "$wt" "feature.txt" "feature" "unit work"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if [ -e "$repo/.local/units" ]; then
    record_fail "expected no .local/units/ to be created when the source .local/ holds none of the three archived components"
  fi
}

test_archive_empty_seeded_dirs_are_archived_as_empty() {
  local repo wt dest
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add failed: $RUN_ERR"; return; }
  # add seeds briefs/ and reports/ as empty directories; leave them empty --
  # a unit that merged without a single test/report wave.
  commit_file "$wt" "feature.txt" "feature" "unit work"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  dest="$repo/.local/units/plan1/U01"
  if [ ! -d "$dest/briefs" ]; then
    record_fail "expected briefs/ to be archived as an (empty) directory -- 'archived and empty' is distinct from 'never archived'"
  elif [ -n "$(ls -A "$dest/briefs" 2>/dev/null)" ]; then
    record_fail "expected archived briefs/ to be empty"
  fi
  if [ ! -d "$dest/reports" ]; then
    record_fail "expected reports/ to be archived as an (empty) directory"
  elif [ -n "$(ls -A "$dest/reports" 2>/dev/null)" ]; then
    record_fail "expected archived reports/ to be empty"
  fi
  if [ ! -f "$dest/status.md" ]; then
    record_fail "expected status.md to be archived"
  fi
}

test_archive_rearchive_overwrites_same_named_preserves_others() {
  local repo wt branch dest
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  wt="$(dirname "$repo")/$(basename "$repo")-U01"
  branch="lego/plan1/U01-greetstuff"
  dest="$repo/.local/units/plan1/U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add failed: $RUN_ERR"; return; }
  printf 'brief v1\n' > "$wt/.local/briefs/01.md"
  commit_file "$wt" "feature.txt" "feature" "unit work"
  # Leave the unit worktree dirty (uncommitted tracked change) so merge's
  # own best-effort worktree removal fails and the worktree survives for a
  # second archive.
  printf 'dirty\n' >> "$wt/README.md"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "first merge: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  if [ ! -d "$wt" ]; then
    record_fail "test setup invalid: expected the dirty unit worktree to survive merge's best-effort cleanup so a second archive can be exercised"
    return
  fi
  assert_eq "brief v1" "$(cat "$dest/briefs/01.md" 2>/dev/null)" "first archive has the first content"

  # A destination-only file that a re-archive must never remove.
  mkdir -p "$dest/briefs"
  printf 'manual only\n' > "$dest/briefs/99-manual.md"

  # Update the source: overwrite the existing file and add a new one; clean
  # the tracked dirt so the next removal (via `remove`) can succeed.
  printf 'brief v2\n' > "$wt/.local/briefs/01.md"
  printf 'brief new\n' > "$wt/.local/briefs/02.md"
  git -C "$wt" checkout -q -- README.md

  run_in "$repo" remove plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "remove (second archive): expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  assert_eq "brief v2" "$(cat "$dest/briefs/01.md" 2>/dev/null)" "re-archiving overwrites a same-named destination file with the new content"
  assert_eq "brief new" "$(cat "$dest/briefs/02.md" 2>/dev/null)" "re-archiving adds a newly-appeared source file"
  assert_eq "manual only" "$(cat "$dest/briefs/99-manual.md" 2>/dev/null)" "re-archiving leaves a destination-only file in place"

  if [ -d "$wt" ]; then
    record_fail "expected the unit worktree to be removed by remove's successful cleanup"
  fi
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected the unit branch to be deleted by remove (it was already merged by the earlier merge)"
  fi
}

test_archive_merge_failure_warns_and_keeps_worktree_exit0() {
  local repo wt branch
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  wt="$(dirname "$repo")/$(basename "$repo")-U01"
  branch="lego/plan1/U01-greetstuff"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add failed: $RUN_ERR"; return; }
  printf 'brief\n' > "$wt/.local/briefs/01.md"
  commit_file "$wt" "feature.txt" "feature" "unit work"

  # Make the archive destination uncreatable: a plain file sits where a
  # directory needs to be created.
  printf 'blocker\n' > "$repo/.local/units"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "archive failure must never change merge's exit code: expected exit 0, got $RUN_EXIT"
  if [ -z "$RUN_ERR" ]; then
    record_fail "expected a warning on stderr when the unit archive fails"
  fi

  if [ ! -d "$wt" ]; then
    record_fail "expected the unit worktree to be KEPT when its archive fails (never destroy the only copy of the record)"
  fi
  if ! git -C "$repo" worktree list | grep -qF "$wt"; then
    record_fail "expected git worktree list to still include the kept unit worktree"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected the unit branch to still exist"
  fi
  if [ ! -f "$repo/feature.txt" ]; then
    record_fail "expected the merge itself to have succeeded despite the archive failure"
  fi
}

test_archive_assemble_failure_warns_and_keeps_worktree_and_branch() {
  local repo wt branch manifest
  repo="$(build_deliver_base)"
  wt="$(dirname "$repo")/$(basename "$repo")-U01"
  branch="lego/plan1/U01-greetstuff"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add failed: $RUN_ERR"; return; }
  printf 'brief\n' > "$wt/.local/briefs/01.md"
  commit_file "$wt" "src/greet.sh" "greet v1" "lego(U01): implementation"
  # Simulate the unit having already been merged into the integration branch
  # before delivery: the divergence gate requires the integration tip to
  # already contain the delivered content -- same setup as
  # test_archive_deliver_success_archives_before_removing_worktree.
  git -C "$repo" merge -q --no-ff -m "lego: merge $branch" "$branch"

  printf 'blocker\n' > "$repo/.local/units"

  manifest="$(write_valid_manifest "$repo" "test: archive failure on assemble" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "archive failure must never change assemble's exit code: expected exit 0, got $RUN_EXIT"
  assert_eq "lego/deliver/plan1/U01" "$RUN_OUT_LAST" "assembled branch name still printed as last stdout line despite the archive failure"
  if [ -z "$RUN_ERR" ]; then
    record_fail "expected a warning on stderr when the unit archive fails during assemble's cleanup"
  fi

  if [ ! -d "$wt" ]; then
    record_fail "expected the unit worktree to be KEPT when its archive fails"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected the unit branch to be KEPT when its archive fails (a branch checked out in a surviving worktree cannot be deleted anyway)"
  fi
}

test_archive_remove_failure_exit4_removes_nothing() {
  local repo wt branch
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  wt="$(dirname "$repo")/$(basename "$repo")-U01"
  branch="lego/plan1/U01-greetstuff"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add failed: $RUN_ERR"; return; }
  printf 'brief\n' > "$wt/.local/briefs/01.md"

  printf 'blocker\n' > "$repo/.local/units"

  run_in "$repo" remove plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "expected exit 4 when the unit archive fails, got $RUN_EXIT"
  assert_single_error_line "$RUN_ERR" "archive failure"

  if [ ! -d "$wt" ]; then
    record_fail "expected remove to leave the worktree in place when the archive fails (removes nothing)"
  fi
  if ! git -C "$repo" worktree list | grep -qF "$wt"; then
    record_fail "expected git worktree list to still include the unit worktree"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected the unit branch to still exist when the archive fails"
  fi
}

test_archive_clean_does_not_archive() {
  local repo container branch wt
  repo="$(new_git_repo)"
  container="$(dirname "$repo")"
  branch="lego/plan1/U01-greetstuff"
  wt="$container/manual-wt-U01"

  git -C "$repo" branch "$branch"
  git -C "$repo" worktree add -q "$wt" "$branch"
  mkdir -p "$wt/.local/briefs"
  printf 'brief\n' > "$wt/.local/briefs/01.md"
  commit_file "$wt" "feature1.txt" "feature1" "unit work 1"
  git -C "$repo" merge -q --no-ff -m "merge $branch" "$branch"

  run_in "$repo" clean --all
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "1" "$RUN_OUT_LAST" "count of removed branches"

  if [ -d "$wt" ] || git -C "$repo" worktree list | grep -qF "$wt"; then
    record_fail "expected the worktree to be removed by clean"
  fi
  if [ -e "$repo/.local/units" ]; then
    record_fail "clean must never archive (by design -- a merged unit branch has already been through merge, which archived it): expected no .local/units/ to be created"
  fi
}

test_archive_never_modifies_invoking_worktree_tracked_files() {
  local repo wt readme_before readme_after tracked_dirty
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  wt="$(dirname "$repo")/$(basename "$repo")-U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add failed: $RUN_ERR"; return; }
  printf 'brief\n' > "$wt/.local/briefs/01.md"
  printf 'report\n' > "$wt/.local/reports/01.md"
  commit_file "$wt" "feature.txt" "feature" "unit work"

  readme_before="$(git -C "$repo" hash-object README.md)"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  readme_after="$(git -C "$repo" hash-object README.md)"
  assert_eq "$readme_before" "$readme_after" "the archive never modifies a pre-existing tracked file"

  tracked_dirty="$(git -C "$repo" status --porcelain --untracked-files=no)"
  assert_eq "" "$tracked_dirty" "no tracked file is left modified by the archive"
}

test_archive_deterministic_across_identical_repo_state() {
  local repoA repoB wtA wtB diffout
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

  wtA="$(dirname "$repoA")/$(basename "$repoA")-U01"
  wtB="$(dirname "$repoB")/$(basename "$repoB")-U01"

  run_in "$repoA" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add on repoA failed: $RUN_ERR"; return; }
  run_in "$repoB" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add on repoB failed: $RUN_ERR"; return; }

  printf 'same brief\n' > "$wtA/.local/briefs/01.md"
  printf 'same brief\n' > "$wtB/.local/briefs/01.md"

  run_in "$repoA" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "repoA merge: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  run_in "$repoB" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "repoB merge: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  diffout="$(diff -ru "$repoA/.local/units/plan1/U01" "$repoB/.local/units/plan1/U01" 2>&1)"
  if [ -n "$diffout" ]; then
    record_fail "archive is not byte-identical across two runs from identical repo state and arguments: $diffout"
  fi
}

test_archive_assemble_success_archives_before_removing_worktree() {
  local repo container branch wt manifest dest
  repo="$(build_deliver_base)"
  container="$(dirname "$repo")"
  branch="lego/plan1/U01-greetstuff"
  wt="$container/manual-wt-U01"

  git -C "$repo" checkout -q -b "$branch" master
  commit_file "$repo" "src/greet.sh" "greet v1" "lego(U01): implementation"
  git -C "$repo" checkout -q master
  # Simulate the unit having already been merged into the integration branch
  # (e.g. via `worktree.sh merge`) before assembly, so `git branch -d` in
  # assemble's cleanup step can succeed -- same setup as
  # test_assemble_cleanup_removes_unit_branch_and_worktree.
  git -C "$repo" merge -q --no-ff -m "lego: merge $branch" "$branch"
  # A worktree for the unit branch still lingers at assemble's cleanup step;
  # seed its .local/ audit trail by hand since this worktree was not created
  # via `add`.
  git -C "$repo" worktree add -q "$wt" "$branch"
  mkdir -p "$wt/.local/briefs" "$wt/.local/reports"
  printf 'deliver brief\n' > "$wt/.local/briefs/01.md"
  printf 'deliver report\n' > "$wt/.local/reports/01.md"
  printf 'deliver status\n' > "$wt/.local/status.md"

  manifest="$(write_valid_manifest "$repo" "test: assemble success archives before removing worktree" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "lego/deliver/plan1/U01" "$RUN_OUT_LAST" "assembled branch name still printed as last stdout line after a successful archive+cleanup"

  dest="$repo/.local/units/plan1/U01"
  assert_eq "deliver brief" "$(cat "$dest/briefs/01.md" 2>/dev/null)" "archived briefs/01.md content intact"
  assert_eq "deliver report" "$(cat "$dest/reports/01.md" 2>/dev/null)" "archived reports/01.md content intact"
  assert_eq "deliver status" "$(cat "$dest/status.md" 2>/dev/null)" "archived status.md content intact"

  if [ -d "$wt" ]; then
    record_fail "expected the unit worktree to be removed after a successful assemble (archive lands first, then removal)"
  fi
  if git -C "$repo" worktree list | grep -qF "$wt"; then
    record_fail "expected git worktree list to no longer include the removed unit worktree"
  fi
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected the unit branch to be deleted after a successful assemble"
  fi
}

test_archive_merge_success_removal_failure_preserves_source_copy() {
  local repo wt branch dest wt_status_before
  repo="$(new_git_repo)"
  write_config_json "$repo" "true"
  write_blocks_md "$repo"
  write_contracts "$repo"
  wt="$(dirname "$repo")/$(basename "$repo")-U01"
  branch="lego/plan1/U01-greetstuff"
  dest="$repo/.local/units/plan1/U01"

  run_in "$repo" add plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || { record_fail "fixture setup: add failed: $RUN_ERR"; return; }
  printf 'brief content\n' > "$wt/.local/briefs/01.md"
  printf 'report content\n' > "$wt/.local/reports/01.md"
  wt_status_before="$(cat "$wt/.local/status.md" 2>/dev/null)"
  commit_file "$wt" "feature.txt" "feature content" "unit work"
  # Leave the unit worktree dirty (uncommitted tracked change) so `git
  # worktree remove` refuses in merge's best-effort cleanup -- the archive
  # itself, which runs first and unconditionally, must still succeed. Same
  # lever as test_archive_rearchive_overwrites_same_named_preserves_others.
  printf 'dirty\n' >> "$wt/README.md"

  run_in "$repo" merge plan1 U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  # The archive (the copy) landed...
  assert_eq "brief content" "$(cat "$dest/briefs/01.md" 2>/dev/null)" "archive exists with the expected content despite the later removal failure"
  assert_eq "report content" "$(cat "$dest/reports/01.md" 2>/dev/null)" "archived reports content intact despite the later removal failure"

  # ...and, because removal failed, the source must still be there too,
  # byte-for-byte: this is what makes "copy, never move" an observable fact
  # rather than a coincidence of every other test removing the worktree
  # right after archiving it.
  if [ ! -d "$wt" ]; then
    record_fail "test setup invalid: expected the dirty unit worktree to survive merge's best-effort removal so both copies are observable at once"
    return
  fi
  assert_eq "brief content" "$(cat "$wt/.local/briefs/01.md" 2>/dev/null)" "source briefs/01.md still present and unmodified after a successful archive"
  assert_eq "report content" "$(cat "$wt/.local/reports/01.md" 2>/dev/null)" "source reports/01.md still present and unmodified after a successful archive"
  assert_eq "$wt_status_before" "$(cat "$wt/.local/status.md" 2>/dev/null)" "source status.md still present and unmodified after a successful archive"
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
# deliver --manifest: extraCommits (B07 manifest extraCommits, plan 002)
#
# An OPTIONAL top-level manifest field
#   "extraCommits": [{"subject": <string>, "files": [<path>, ...]}, ...]
# appends one commit per entry, in array order, AFTER every unit commit.
# Each entry's content comes from the integration tip through the same
# restore path B06 gave the unit commits (this is that path's explicit-paths
# arm: the files come from the manifest, not from a commit's diff-tree), and
# its paths join DELIVERED_PATHS so the pre-push byte-gate covers them
# identically. Absent or empty reproduces the previous behavior; a malformed
# field dies exit 3 in pass-1 validation.
# ===========================================================================

# build_extra_commits_fixture -- a fully valid single-unit deliver fixture:
# unit branch with a resolvable implementation commit, integrated, plus one
# path (src/other.sh) the integration tip advances past the delivery base and
# no unit commit touches, so it can only reach the delivery branch through an
# extraCommits entry. Prints the repo path.
build_extra_commits_fixture() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1 (unit)\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  commit_file "$repo" "src/other.sh" $'other v2 (integration only)\n' \
    "fix: integration-only follow-up no unit commit carries"
  printf '%s' "$repo"
}

# run_deliver_with_extra_commits <raw-json> -- builds a FRESH valid fixture
# (so extraCommits is the only possible defect, and so a run that wrongly
# succeeds cannot contaminate the next sub-case's branches), writes a
# manifest whose top-level "extraCommits" is the given raw JSON verbatim, and
# runs assemble. Sets the RUN_* globals and EXTRA_FIXTURE_REPO. Called as a
# plain statement, never via $(...).
EXTRA_FIXTURE_REPO=""
run_deliver_with_extra_commits() {
  local extra_json="$1"
  local repo
  repo="$(build_extra_commits_fixture)"
  EXTRA_FIXTURE_REPO="$repo"
  mkdir -p "$repo/.local"
  printf '{"title":"test: extraCommits validation","branch":"custom/extra-commits-validation","commits":{"U01":{"impl":"unit impl subject"}},"extraCommits":%s}' \
    "$extra_json" > "$repo/.local/manifest.json"
  # A malformed VALUE must still leave a syntactically valid manifest file:
  # otherwise the expected exit 3 would come from the JSON-parse check rather
  # than from the extraCommits validation under test -- the right code for
  # the wrong reason.
  if ! jq empty "$repo/.local/manifest.json" >/dev/null 2>&1; then
    record_fail "test setup invalid: manifest built for extraCommits=$extra_json is not valid JSON, so exit 3 would be the JSON check, not the extraCommits check"
  fi
  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
}

# deliver_extra_commits_outcome <extraCommits-json-or-empty-for-absent> --
# runs one deliver over an identical fixture and prints a single line
# summarising everything the invariant cares about: exit code, the delivered
# tree's sha (content-addressed, so it is comparable across two throwaway
# repos even though commit shas are not) and the delivered commit subjects in
# order. Invoked via $(...), so it asserts nothing itself.
deliver_extra_commits_outcome() {
  local extra_json="$1"
  local repo branch
  branch="custom/extra-commits-invariant"
  repo="$(build_extra_commits_fixture)"
  mkdir -p "$repo/.local"
  if [ -n "$extra_json" ]; then
    jq -n --argjson e "$extra_json" --arg b "$branch" \
      '{title: "test: extraCommits invariant", branch: $b, commits: {U01: {impl: "unit impl subject"}}, extraCommits: $e}' \
      > "$repo/.local/manifest.json"
  else
    jq -n --arg b "$branch" \
      '{title: "test: extraCommits invariant", branch: $b, commits: {U01: {impl: "unit impl subject"}}}' \
      > "$repo/.local/manifest.json"
  fi
  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  printf 'exit=%s tree=%s subjects=%s' \
    "$RUN_EXIT" \
    "$(git -C "$repo" rev-parse "$branch^{tree}" 2>/dev/null)" \
    "$(git -C "$repo" log --reverse --format=%s "master..$branch" 2>/dev/null | tr '\n' '|')"
}

# The headline behavior: one commit per entry, in manifest order, after ALL
# unit commits of ALL units -- never merged into a unit commit. Both extra
# paths are carried by no unit commit at all, so nothing but an extraCommits
# entry can put them on the delivery branch; the second one contains a space,
# the arrangement B02's Code paths already use to catch unquoted expansions.
test_assemble_extra_commits_appended_after_unit_commits_in_order() {
  local repo branch
  repo="$(build_deliver_base)"
  branch="custom/extra-commits-order"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet_test.sh" $'greet test v1\n' "lego(U01): tests"
  commit_file "$repo" "src/greet.sh" $'greet v1\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master

  git -C "$repo" checkout -q -b "lego/plan1/U02-soloslug" master
  commit_file "$repo" "src/solo.sh" $'solo v1\n' "lego(U02): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff" "lego/plan1/U02-soloslug"

  commit_files "$repo" "chore: integration-only follow-ups no unit commit carries" \
    "src/other.sh" $'other v2 (integration only)\n' \
    "src/dir with space/file.sh" $'spacey v2 (integration only)\n'

  mkdir -p "$repo/.local"
  jq -n --arg b "$branch" \
    '{title: "test: extraCommits order", branch: $b,
      commits: {U01: {tests: "unit tests subject U01", impl: "unit impl subject U01"},
                U02: {impl: "unit impl subject U02"}},
      extraCommits: [{subject: "chore(deps): first extra commit", files: ["src/other.sh"]},
                     {subject: "docs: second extra commit", files: ["src/dir with space/file.sh"]}]}' \
    > "$repo/.local/manifest.json"
  local manifest_before
  manifest_before="$(cat "$repo/.local/manifest.json")"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff U02 soloslug
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "$branch" "$RUN_OUT_LAST" "assembled branch name as last stdout line"

  assert_eq "$manifest_before" "$(cat "$repo/.local/manifest.json")" "the manifest file is read-only; extraCommits must not modify it"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected delivery branch $branch to exist"
    return
  fi

  local expected actual
  expected=$'unit tests subject U01\nunit impl subject U01\nunit impl subject U02\nchore(deps): first extra commit\ndocs: second extra commit'
  actual="$(git -C "$repo" log --reverse --format=%s "master..$branch")"
  assert_eq "$expected" "$actual" "one commit per extraCommits entry, in manifest order, after every unit commit of every unit"

  local first_extra second_extra
  first_extra="$(git -C "$repo" show "$branch:src/other.sh" 2>/dev/null || echo "MISSING")"
  second_extra="$(git -C "$repo" show "$branch:src/dir with space/file.sh" 2>/dev/null || echo "MISSING")"
  assert_eq "other v2 (integration only)" "$first_extra" "the first entry's path is delivered with the integration tip's content"
  assert_eq "spacey v2 (integration only)" "$second_extra" "an entry path containing a space is restored, not split into two paths"

  # Distinctness: the extra commit carries exactly its own manifest files, and
  # the last unit commit carries only the unit's.
  local extra_sha impl_sha
  extra_sha="$(git -C "$repo" log --format='%H %s' "$branch" | grep -F ' chore(deps): first extra commit' | head -n1 | cut -d' ' -f1)"
  impl_sha="$(git -C "$repo" log --format='%H %s' "$branch" | grep -F ' unit impl subject U02' | head -n1 | cut -d' ' -f1)"
  if [ -n "$extra_sha" ]; then
    assert_eq "src/other.sh" "$(git -C "$repo" diff-tree --no-commit-id --name-only -r "$extra_sha")" "the extra commit changes exactly the paths its entry lists"
  else
    record_fail "could not locate the first extra commit to inspect its diff"
  fi
  if [ -n "$impl_sha" ]; then
    assert_eq "src/solo.sh" "$(git -C "$repo" diff-tree --no-commit-id --name-only -r "$impl_sha")" "an extraCommits path is never folded into a unit commit"
  else
    record_fail "could not locate U02's implementation commit to inspect its diff"
  fi
}

# The E1 case B06 deferred: the explicit-paths arm of the restore takes its
# content from the INTEGRATION TIP too. The path here is touched on the unit
# branch under a subject deliver never resolves, so the tip's content differs
# from the delivery base's AND from every version the unit branch holds --
# only a tip-sourced restore can produce the expected content. The byte-gate
# assertions below are the observable face of "these paths join
# DELIVERED_PATHS": a restore from anywhere but the tip would be reported
# divergent and nothing would be pushed.
test_assemble_extra_commit_content_comes_from_the_integration_tip() {
  local repo branch
  repo="$(build_deliver_base)"
  branch="custom/extra-commits-tip-content"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/needsimpl.sh" $'needsimpl v1 (unit branch)\n' \
    "wip: unit-branch work under a subject deliver never resolves"
  commit_file "$repo" "src/greet.sh" $'greet v1\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  commit_file "$repo" "src/needsimpl.sh" $'needsimpl v2 (integration tip)\n' \
    "fix: advance the path past every version the unit branch holds"

  mkdir -p "$repo/.local"
  jq -n --arg b "$branch" \
    '{title: "test: extraCommits tip content", branch: $b,
      commits: {U01: {impl: "unit impl subject"}},
      extraCommits: [{subject: "chore: carry the integration-only fix", files: ["src/needsimpl.sh"]}]}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  case "$RUN_ERR" in
    *"diverges from the integration tip"*)
      record_fail "an extra commit's paths join DELIVERED_PATHS and must pass the byte-gate by construction: got [$RUN_ERR]" ;;
  esac

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected delivery branch $branch to exist"
    return
  fi

  local delivered
  delivered="$(git -C "$repo" show "$branch:src/needsimpl.sh" 2>/dev/null || echo "MISSING")"
  assert_eq "needsimpl v2 (integration tip)" "$delivered" "an extra commit's content comes from the integration tip, not from any unit-branch version (v1) or the delivery base (v0)"

  local gate_diff
  gate_diff="$(git -C "$repo" diff --name-only HEAD "$branch" -- "src/needsimpl.sh" 2>/dev/null)"
  assert_eq "" "$gate_diff" "the extra commit's path is byte-identical to the integration tip, exactly what the pre-push gate compares"

  local subjects
  subjects="$(git -C "$repo" log --format=%s "master..$branch")"
  if ! printf '%s\n' "$subjects" | grep -qF "chore: carry the integration-only fix"; then
    record_fail "expected the entry's subject to appear as a commit on the delivery branch"
  fi
  if [ -n "$(git -C "$repo" ls-remote --heads origin "$branch" 2>/dev/null)" ]; then
    record_fail "B10: assemble never pushes anywhere -- the delivery branch must not appear on origin"
  fi
}

# B06's removal rule reaches the explicit-paths arm: an entry file ABSENT at
# the integration tip and TRACKED in the delivery worktree is removed, and
# that removal is a real staged change, so the entry still produces its
# commit.
test_assemble_extra_commit_path_absent_at_tip_is_removed_when_tracked() {
  local repo branch
  repo="$(build_deliver_base)"
  branch="custom/extra-commits-absent-tracked"
  # On master (the delivery base), so the delivery worktree tracks it. The
  # push keeps the seed on origin/master too -- deliver resolves its base
  # fresh from origin, so origin/master is the actual delivery base.
  commit_file "$repo" "src/retired.sh" $'retired v0\n' "seed a path integration later deletes"
  git -C "$repo" push -q origin master >/dev/null 2>&1

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  git -C "$repo" rm -q -- "src/retired.sh"
  git -C "$repo" commit -q -m "chore: delete the retired script on the integration branch"

  mkdir -p "$repo/.local"
  jq -n --arg b "$branch" \
    '{title: "test: extraCommits absent-at-tip path", branch: $b,
      commits: {U01: {impl: "unit impl subject"}},
      extraCommits: [{subject: "chore: drop the retired script", files: ["src/retired.sh"]}]}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "an entry path deleted on integration must be removed, not abort: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  case "$RUN_ERR" in
    *"diverges from the integration tip"*)
      record_fail "removing an entry path absent at the tip must satisfy the byte-gate, not trip it: got [$RUN_ERR]" ;;
  esac

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected delivery branch $branch to exist"
    return
  fi
  if git -C "$repo" cat-file -e "$branch:src/retired.sh" 2>/dev/null; then
    record_fail "expected src/retired.sh (absent at the tip, tracked in the delivery worktree) to be removed from the delivery branch"
  fi
  local subjects
  subjects="$(git -C "$repo" log --format=%s "master..$branch")"
  if ! printf '%s\n' "$subjects" | grep -qF "chore: drop the retired script"; then
    record_fail "expected the removal to be a real staged change and produce the entry's commit"
  fi
}

# The other half of the same rule: an entry file absent at the tip and
# UNTRACKED in the delivery worktree is silently skipped -- no git failure and
# no fabricated content. The second entry (a path the tip really does carry)
# is what proves the skip is a skip and not the whole field being ignored.
test_assemble_extra_commit_path_absent_at_tip_and_untracked_is_skipped() {
  local repo branch
  repo="$(build_deliver_base)"
  branch="custom/extra-commits-absent-untracked"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  commit_file "$repo" "src/other.sh" $'other v2 (integration only)\n' "fix: integration-only follow-up"

  mkdir -p "$repo/.local"
  jq -n --arg b "$branch" \
    '{title: "test: extraCommits untracked absent path", branch: $b,
      commits: {U01: {impl: "unit impl subject"}},
      extraCommits: [{subject: "chore: an entry naming a path nothing has", files: ["src/never-existed.sh"]},
                     {subject: "chore: an entry naming a path the tip has", files: ["src/other.sh"]}]}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "an entry path absent at the tip and untracked in the delivery worktree must be skipped, not fail: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  [ -z "$RUN_ERR" ] || record_fail "skipping an untracked absent entry path must be silent: got stderr [$RUN_ERR]"

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected delivery branch $branch to exist"
    return
  fi
  if git -C "$repo" cat-file -e "$branch:src/never-existed.sh" 2>/dev/null; then
    record_fail "expected src/never-existed.sh (absent at the tip) never to be created on the delivery branch"
  fi

  local expected actual
  expected=$'unit impl subject\nchore: an entry naming a path the tip has'
  actual="$(git -C "$repo" log --reverse --format=%s "master..$branch")"
  assert_eq "$expected" "$actual" "the skipped entry stages nothing and creates no commit; the following entry still gets its own"
  assert_eq "other v2 (integration only)" "$(git -C "$repo" show "$branch:src/other.sh" 2>/dev/null || echo MISSING)" "the entry after a skipped one still restores the tip's content"
}

# The no-op rule of the unit commits holds for entries: an entry whose restore
# stages no diff creates no commit. Two ways to get there -- a later entry
# naming a path an earlier entry already restored, and an entry naming a path
# whose tip content already equals the delivery base's. Neither is an error,
# and neither trips the byte-gate (their paths still join DELIVERED_PATHS,
# where they compare equal to the tip).
test_assemble_extra_commit_entry_staging_no_diff_creates_no_commit() {
  local repo branch
  repo="$(build_deliver_base)"
  branch="custom/extra-commits-noop-entry"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  commit_file "$repo" "src/other.sh" $'other v2 (integration only)\n' "fix: integration-only follow-up"

  mkdir -p "$repo/.local"
  # src/solo.sh is untouched everywhere, so restoring it from the tip stages
  # nothing at all.
  jq -n --arg b "$branch" \
    '{title: "test: extraCommits no-op entries", branch: $b,
      commits: {U01: {impl: "unit impl subject"}},
      extraCommits: [{subject: "chore: the entry that does change something", files: ["src/other.sh"]},
                     {subject: "chore: the same path a second time", files: ["src/other.sh"]},
                     {subject: "chore: a path already at the tip content", files: ["src/solo.sh"]}]}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  case "$RUN_ERR" in
    *"diverges from the integration tip"*)
      record_fail "a no-op entry's paths still join DELIVERED_PATHS and must compare equal to the tip: got [$RUN_ERR]" ;;
  esac

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "expected delivery branch $branch to exist"
    return
  fi

  local expected actual
  expected=$'unit impl subject\nchore: the entry that does change something'
  actual="$(git -C "$repo" log --reverse --format=%s "master..$branch")"
  assert_eq "$expected" "$actual" "an entry whose restore stages no diff creates no commit, whether the path was already restored by an earlier entry or already matches the tip"
  assert_eq "other v2 (integration only)" "$(git -C "$repo" show "$branch:src/other.sh" 2>/dev/null || echo MISSING)" "the duplicate entry leaves the earlier entry's restored content in place"
}

# Invariant: an ABSENT extraCommits key and an EMPTY array are the same
# delivery -- same exit, same delivered tree, same commit subjects. The
# non-empty arm is what makes this discriminating rather than vacuous: if a
# non-empty array produced that same delivery too, the field would simply be
# ignored.
test_assemble_extra_commits_absent_and_empty_reproduce_previous_behavior() {
  local absent empty nonempty
  absent="$(deliver_extra_commits_outcome "")"
  empty="$(deliver_extra_commits_outcome '[]')"
  nonempty="$(deliver_extra_commits_outcome '[{"subject":"chore: one extra commit","files":["src/other.sh"]}]')"

  case "$absent" in
    "exit=0 tree="?*) : ;;
    *) record_fail "test setup invalid: the baseline (no extraCommits key) deliver did not succeed: [$absent]" ;;
  esac
  assert_eq "$absent" "$empty" "an empty extraCommits array must reproduce the absent-key delivery exactly (same exit, delivered tree and commit subjects)"
  if [ "$absent" = "$nonempty" ]; then
    record_fail "a non-empty extraCommits array must change the delivery; got the same outcome as the absent-key run [$absent]"
  fi
}

# Malformed shape: the field is present but is not an array at all.
test_assemble_extra_commits_not_an_array_exits_3() {
  run_deliver_with_extra_commits '{"subject":"chore: x","files":["src/other.sh"]}'
  [ "$RUN_EXIT" -eq 3 ] || record_fail "extraCommits set to an object instead of an array: expected exit 3, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "extraCommits is an object, not an array"
  case "$RUN_ERR" in
    *extraCommits*) : ;;
    *) record_fail "expected the error to name the malformed field (extraCommits): got [$RUN_ERR]" ;;
  esac

  run_deliver_with_extra_commits '"src/other.sh"'
  [ "$RUN_EXIT" -eq 3 ] || record_fail "extraCommits set to a string instead of an array: expected exit 3, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "extraCommits is a string, not an array"
  case "$RUN_ERR" in
    *extraCommits*) : ;;
    *) record_fail "expected the error to name the malformed field (extraCommits): got [$RUN_ERR]" ;;
  esac
}

# Malformed entry: "subject" missing entirely, or present but empty (the
# manifest-wide "empty string is absent" rule).
test_assemble_extra_commits_entry_missing_or_empty_subject_exits_3() {
  run_deliver_with_extra_commits '[{"files":["src/other.sh"]}]'
  [ "$RUN_EXIT" -eq 3 ] || record_fail "entry missing subject: expected exit 3, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "extraCommits entry missing subject"
  case "$RUN_ERR" in
    *subject*) : ;;
    *) record_fail "expected the error to name the missing key (subject): got [$RUN_ERR]" ;;
  esac

  run_deliver_with_extra_commits '[{"subject":"","files":["src/other.sh"]}]'
  [ "$RUN_EXIT" -eq 3 ] || record_fail "entry with an empty subject: expected exit 3, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "extraCommits entry with an empty subject"
  case "$RUN_ERR" in
    *subject*) : ;;
    *) record_fail "expected the error to name the empty key (subject): got [$RUN_ERR]" ;;
  esac

  # A well-formed first entry followed by a defective second one: the check
  # runs over every entry, not just the first.
  run_deliver_with_extra_commits '[{"subject":"chore: fine","files":["src/other.sh"]},{"files":["src/solo.sh"]}]'
  [ "$RUN_EXIT" -eq 3 ] || record_fail "second entry missing subject after a valid first: expected exit 3, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "second extraCommits entry missing subject"
}

# Malformed entry: "files" missing, empty, or not an array.
test_assemble_extra_commits_entry_files_missing_empty_or_non_array_exits_3() {
  run_deliver_with_extra_commits '[{"subject":"chore: no files key"}]'
  [ "$RUN_EXIT" -eq 3 ] || record_fail "entry missing files: expected exit 3, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "extraCommits entry missing files"
  case "$RUN_ERR" in
    *files*) : ;;
    *) record_fail "expected the error to name the missing key (files): got [$RUN_ERR]" ;;
  esac

  run_deliver_with_extra_commits '[{"subject":"chore: empty files","files":[]}]'
  [ "$RUN_EXIT" -eq 3 ] || record_fail "entry with an empty files array: expected exit 3, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "extraCommits entry with an empty files array"
  case "$RUN_ERR" in
    *files*) : ;;
    *) record_fail "expected the error to name the empty key (files): got [$RUN_ERR]" ;;
  esac

  run_deliver_with_extra_commits '[{"subject":"chore: files is a string","files":"src/other.sh"}]'
  [ "$RUN_EXIT" -eq 3 ] || record_fail "entry whose files is a string, not an array: expected exit 3, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "extraCommits entry whose files is not an array"
  case "$RUN_ERR" in
    *files*) : ;;
    *) record_fail "expected the error to name the malformed key (files): got [$RUN_ERR]" ;;
  esac
}

# The rejection happens in pass 1, before anything is built: no delivery
# branch, no temporary worktree, nothing pushed, no PR -- and the unit's own
# branch is left alone, since deliver's post-run cleanup never ran either.
test_assemble_extra_commits_malformed_dies_before_any_branch_or_worktree() {
  run_deliver_with_extra_commits '[{"files":["src/other.sh"]}]'
  [ "$RUN_EXIT" -eq 3 ] || record_fail "malformed extraCommits: expected exit 3, got $RUN_EXIT (stderr: $RUN_ERR)"

  local repo="$EXTRA_FIXTURE_REPO"
  if git -C "$repo" show-ref --verify --quiet "refs/heads/custom/extra-commits-validation"; then
    record_fail "expected no delivery branch to be created before extraCommits validation"
  fi
  local wt_count
  wt_count="$(git -C "$repo" worktree list | grep -c '')"
  [ "$wt_count" -eq 1 ] || record_fail "expected no temporary delivery worktree to be created before extraCommits validation, got $wt_count worktrees"
  if [ -n "$(git -C "$repo" ls-remote --heads origin "custom/extra-commits-validation" 2>/dev/null)" ]; then
    record_fail "expected nothing to be pushed when extraCommits is malformed"
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/lego/plan1/U01-greetstuff"; then
    record_fail "expected the unit branch to survive: a manifest rejection must not run deliver's post-delivery cleanup"
  fi
}

# A valid extraCommits field does not buy a manifest out of B01's
# required-field validation: the missing commits.<unit>.impl still wins.
test_assemble_extra_commits_does_not_relax_required_field_validation() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  mkdir -p "$repo/.local"
  jq -n '{title: "test: extraCommits does not relax required fields",
          branch: "custom/extra-commits-required-fields",
          extraCommits: [{subject: "chore: a perfectly valid entry", files: ["src/other.sh"]}]}' \
    > "$repo/.local/manifest.json"

  run_in "$repo" assemble --manifest "$repo/.local/manifest.json" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 3 ] || record_fail "valid extraCommits but missing commits.U01.impl: expected exit 3, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "required-field validation still applies alongside extraCommits"
  case "$RUN_ERR" in
    *impl*) : ;;
    *) record_fail "expected the error to name the missing required field (commits.U01.impl): got [$RUN_ERR]" ;;
  esac
}

# ===========================================================================
# deliver: fresh-base resolution (B10 deliver fresh-base, plan 003)
#
# Before any other use of <base-branch>, cmd_deliver resolves it to a fresh
# base ref: when a remote named "origin" exists and carries <base-branch>, it
# fetches that branch and uses origin/<base-branch> for the base-existence
# check, the newest_commit_with_subject lower bound and the delivery-branch
# creation; otherwise it uses the local <base-branch> exactly as before. The
# PR target (`gh pr create --base`) keeps the plain branch NAME either way.
#
# Every fixture here is hermetic: "origin" is the local bare repo
# build_deliver_base already registers, and the commits that reach it are
# pushed from a throwaway clone, so the fixture repo can be left genuinely
# behind its remote -- no objects, stale tracking ref -- the way a real
# integration checkout is when someone else has landed work in the meantime.
# ===========================================================================

# advance_origin_branch <repo> <branch> <relpath> <content> <subject> [date]
# -- commits <relpath> onto <branch> in <repo>'s origin through a throwaway
# clone, creating the branch off master when origin does not carry it yet.
# The objects never pass through <repo>, so its own refs (the local <branch>
# and refs/remotes/origin/<branch>) stay exactly where they were: only a
# fetch can bring the new tip in. <date> (any git-parseable timestamp) fixes
# the author and committer date, for the one test whose fixture depends on
# the order `git log` scans two same-subject commits in. Prints the new tip's
# sha.
advance_origin_branch() {
  local repo="$1" branch="$2" rel="$3" content="$4" subject="$5" date="${6:-}"
  local url container clone
  url="$(git -C "$repo" remote get-url origin)"
  container="$(mktemp -d)"
  track_tmp "$container"
  clone="$container/clone"
  # --branch master, never the remote's HEAD: the bare origin comes from
  # `git init --bare`, whose HEAD follows the ambient init.defaultBranch and
  # so may name a branch that was never pushed.
  git clone -q --branch master "$url" "$clone" >/dev/null 2>&1
  git -C "$clone" config user.email "lego-fixture@example.com"
  git -C "$clone" config user.name "Lego Fixture"
  git -C "$clone" config commit.gpgsign false
  git -C "$clone" config core.hooksPath "$NOOP_HOOKS_DIR"
  if [ "$branch" != "master" ]; then
    if git -C "$clone" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git -C "$clone" checkout -q "$branch"
    else
      git -C "$clone" checkout -q -b "$branch"
    fi
  fi
  mkdir -p "$(dirname "$clone/$rel")"
  printf '%s' "$content" > "$clone/$rel"
  git -C "$clone" add -- "$rel"
  if [ -n "$date" ]; then
    GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" git -C "$clone" commit -q -m "$subject"
  else
    git -C "$clone" commit -q -m "$subject"
  fi
  git -C "$clone" push -q origin "$branch" >/dev/null 2>&1
  git -C "$clone" rev-parse HEAD
}

# build_fresh_base_fixture -- build_deliver_base plus one integrated unit
# (U01, one resolvable implementation commit touching src/greet.sh), left in
# the production-shaped pre-delivery state with the integration branch
# checked out. The base-side arrangement is what each test varies. Prints the
# repo path.
build_fresh_base_fixture() {
  local repo
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1 (unit)\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  printf '%s' "$repo"
}

# The core clause. The local base ref is behind origin's same-named branch by
# a commit whose objects the fixture repo has never seen; the delivery branch
# must still fork from that remote tip, which is only reachable by fetching.
# The side branch is the "no fetch of anything beyond <base-branch>" tripwire.
test_assemble_forks_from_the_freshly_fetched_origin_when_the_local_base_is_stale() {
  local repo origin_tip side_tip local_base_before head_before status_before
  repo="$(build_deliver_base)"
  local_base_before="$(git -C "$repo" rev-parse master)"
  origin_tip="$(advance_origin_branch "$repo" master "docs/remote-only.md" $'remote only\n' "docs: a commit that only ever reached origin")"
  side_tip="$(advance_origin_branch "$repo" sidebranch "docs/side-only.md" $'side only\n' "docs: a commit on a branch deliver must not fetch")"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1 (unit)\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  head_before="$(git -C "$repo" rev-parse HEAD)"
  status_before="$(git -C "$repo" status --porcelain)"

  local manifest branch="lego/deliver/plan1/U01"
  manifest="$(write_valid_manifest "$repo" "test: fresh base resolution" "$branch" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "stale local base, fresh origin: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    if ! git -C "$repo" merge-base --is-ancestor "$origin_tip" "$branch" 2>/dev/null; then
      record_fail "the delivery branch must fork from origin/master's just-fetched tip ($origin_tip), not from the stale local master ($local_base_before)"
    fi
    assert_eq "remote only" "$(git -C "$repo" show "$branch:docs/remote-only.md" 2>/dev/null || echo MISSING)" "a commit carried only by origin's base branch reaches the delivery branch"
    assert_eq "greet v1 (unit)" "$(git -C "$repo" show "$branch:src/greet.sh" 2>/dev/null || echo MISSING)" "the unit's delivered content is unaffected by the fresher base"
  else
    record_fail "expected delivery branch $branch to exist"
  fi

  assert_eq "$origin_tip" "$(git -C "$repo" rev-parse --verify --quiet refs/remotes/origin/master || echo MISSING)" "origin/master resolves to the remote's current tip, i.e. <base-branch> was actually fetched"

  if git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/sidebranch" >/dev/null 2>&1; then
    record_fail "nothing beyond <base-branch> may be fetched: origin/sidebranch was fetched too"
  fi
  if git -C "$repo" cat-file -e "${side_tip}^{commit}" 2>/dev/null; then
    record_fail "nothing beyond <base-branch> may be fetched: the side branch's objects reached the repo"
  fi

  assert_eq "$local_base_before" "$(git -C "$repo" rev-parse master)" "the local base branch is never moved by the fetch"
  assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "deliver never moves the integration worktree's HEAD"
  assert_eq "$status_before" "$(git -C "$repo" status --porcelain)" "deliver never modifies the integration worktree's files"
}

# No origin at all: there is nothing to fetch and (under B10) nothing to
# push either, so base resolution falls through to the local ref and the
# build succeeds -- "works with no origin remote configured" is now an
# explicit B10 invariant, not a failure at a push step that no longer
# exists.
test_assemble_without_an_origin_remote_uses_the_local_base_unchanged() {
  local repo
  repo="$(build_fresh_base_fixture)"
  git -C "$repo" remote remove origin

  local manifest branch="lego/deliver/plan1/U01"
  manifest="$(write_valid_manifest "$repo" "test: no origin remote" "$branch" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "B10: no origin remote must not be fatal (no fetch, no push): expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_eq "$branch" "$RUN_OUT_LAST" "assembled branch name as last stdout line, no origin remote configured"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    assert_eq "greet v1 (unit)" "$(git -C "$repo" show "$branch:src/greet.sh" 2>/dev/null || echo MISSING)" "the delivery branch is built from the local base ref when no origin remote exists"
  else
    record_fail "expected delivery branch $branch to exist"
  fi
  if [ -n "$(git -C "$repo" for-each-ref --format='%(refname)' 'refs/remotes/origin/*')" ]; then
    record_fail "no origin remote: nothing may be fetched"
  fi
}

# An origin that does not carry <base-branch> is the same world as no origin
# for base resolution: the local ref wins. The base here exists only locally
# AND carries a commit origin has never seen, so a delivery branch that
# contains it can only have forked from the local ref.
test_assemble_origin_without_the_base_branch_falls_back_to_the_local_ref() {
  local repo mainline_tip
  repo="$(build_deliver_base)"
  git -C "$repo" checkout -q -b mainline master
  commit_file "$repo" "docs/local-base.md" $'local base\n' "docs: a commit only the local base branch carries"
  mainline_tip="$(git -C "$repo" rev-parse mainline)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" mainline
  commit_file "$repo" "src/greet.sh" $'greet v1 (unit)\n' "lego(U01): implementation"
  git -C "$repo" checkout -q mainline
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  local manifest branch="lego/deliver/plan1/U01"
  manifest="$(write_valid_manifest "$repo" "test: origin lacks the base branch" "$branch" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 mainline U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "origin lacks <base-branch>: expected exit 0 on the local-ref fallback, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    if ! git -C "$repo" merge-base --is-ancestor "$mainline_tip" "$branch" 2>/dev/null; then
      record_fail "the delivery branch must fork from the local base ref when origin does not carry <base-branch>"
    fi
    assert_eq "local base" "$(git -C "$repo" show "$branch:docs/local-base.md" 2>/dev/null || echo MISSING)" "a commit only the local base carries reaches the delivery branch"
  else
    record_fail "expected delivery branch $branch to exist"
  fi

  if git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/mainline" >/dev/null 2>&1; then
    record_fail "origin does not carry <base-branch>; there is nothing to fetch"
  fi

}

# origin is reachable and still advertises <base-branch>, so this is the
# "carries it but the fetch fails" case, not the fallback case: the fetch
# cannot complete because refs/remotes/origin/master is blocked by a
# directory/file ref conflict, leaving git nowhere to write the fetched tip.
test_assemble_fetch_failure_dies_naming_the_fetch() {
  local repo
  repo="$(build_fresh_base_fixture)"
  git -C "$repo" update-ref -d refs/remotes/origin/master
  git -C "$repo" update-ref "refs/remotes/origin/master/blocked" "$(git -C "$repo" rev-parse master)"

  local manifest branch="lego/deliver/plan1/U01"
  manifest="$(write_valid_manifest "$repo" "test: fetch failure" "$branch" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "origin carries <base-branch> but the fetch cannot complete: expected exit 4, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "failed fetch of <base-branch>"
  case "$RUN_ERR" in
    *fetch*) : ;;
    *) record_fail "a failed fetch must be named as such: got [$RUN_ERR]" ;;
  esac

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    record_fail "a failed fetch must abort before the delivery branch is created"
  fi
  if [ -n "$(git -C "$repo" ls-remote --heads origin "$branch" 2>/dev/null)" ]; then
    record_fail "nothing may be pushed when the base fetch fails"
  fi
}

# The same clause with every signal that origin carries <base-branch> intact
# -- reachable remote, advertised branch, and a resolvable (if stale)
# refs/remotes/origin/master. Only `git fetch origin master` fails: origin's
# fetch refspec is pointed at the branch this worktree has checked out, which
# git refuses to update. A stale origin/master that still resolves is exactly
# the state a swallowed fetch failure would deliver from.
test_assemble_fetch_failure_with_an_intact_tracking_ref_dies_naming_the_fetch() {
  local repo
  repo="$(build_fresh_base_fixture)"
  git -C "$repo" config remote.origin.fetch "+refs/heads/master:refs/heads/integration"

  local manifest branch="lego/deliver/plan1/U01"
  manifest="$(write_valid_manifest "$repo" "test: fetch failure, tracking ref intact" "$branch" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "reachable origin, advertised branch, failing fetch: expected exit 4, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "failed fetch with an intact tracking ref"
  case "$RUN_ERR" in
    *fetch*) : ;;
    *) record_fail "a failed fetch must be named as such, never silently degraded to the stale tracking ref: got [$RUN_ERR]" ;;
  esac
  if [ -n "$(git -C "$repo" ls-remote --heads origin "$branch" 2>/dev/null)" ]; then
    record_fail "nothing may be pushed when the base fetch fails"
  fi
}

# Unchanged behaviour, guarded: a base resolvable neither remotely nor
# locally is still the same exit 4 with the same message.
test_assemble_base_missing_locally_and_remotely_exits_4() {
  local repo
  repo="$(build_fresh_base_fixture)"

  local manifest
  manifest="$(write_valid_manifest "$repo" "test: base nowhere" "lego/deliver/plan1/U01" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 nosuchbase U01 greetstuff
  [ "$RUN_EXIT" -eq 4 ] || record_fail "base resolvable neither remotely nor locally: expected exit 4, got $RUN_EXIT (stderr: $RUN_ERR)"
  assert_single_error_line "$RUN_ERR" "base branch not found"
  case "$RUN_ERR" in
    *"base branch not found"*) : ;;
    *) record_fail "expected the unchanged 'base branch not found' error: got [$RUN_ERR]" ;;
  esac
  case "$RUN_ERR" in
    *nosuchbase*) : ;;
    *) record_fail "expected the error to name the base branch: got [$RUN_ERR]" ;;
  esac
}

# Edge case: the local base is AHEAD of origin (unpushed commits). The PR
# targets the remote branch, so origin still wins -- the ahead-only commit
# must be absent from the delivery branch.
test_assemble_local_base_ahead_of_origin_still_forks_from_origin() {
  local repo origin_tip ahead_sha
  repo="$(build_deliver_base)"
  origin_tip="$(git -C "$repo" rev-parse master)"
  git -C "$repo" checkout -q master
  commit_file "$repo" "docs/local-only.md" $'local only\n' "docs: an unpushed commit on the local base"
  ahead_sha="$(git -C "$repo" rev-parse master)"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1 (unit)\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  local manifest branch="lego/deliver/plan1/U01"
  manifest="$(write_valid_manifest "$repo" "test: local base ahead of origin" "$branch" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "local base ahead of origin: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    if ! git -C "$repo" merge-base --is-ancestor "$origin_tip" "$branch" 2>/dev/null; then
      record_fail "the delivery branch must fork from origin's tip ($origin_tip)"
    fi
    if git -C "$repo" merge-base --is-ancestor "$ahead_sha" "$branch" 2>/dev/null; then
      record_fail "an unpushed commit that only the local base carries must not reach the delivery branch: origin is the PR target"
    fi
    if git -C "$repo" show "$branch:docs/local-only.md" >/dev/null 2>&1; then
      record_fail "the ahead-only commit's file must be absent from the delivery branch"
    fi
    assert_eq "greet v1 (unit)" "$(git -C "$repo" show "$branch:src/greet.sh" 2>/dev/null || echo MISSING)" "the unit's delivered content is unaffected by the older base"
  else
    record_fail "expected delivery branch $branch to exist"
  fi

  assert_eq "$ahead_sha" "$(git -C "$repo" rev-parse master)" "the local base branch is never rewound to origin"
}

# Edge case: no local <base-branch> ref at all. Remote resolution suffices --
# deliver succeeds where today it dies "base branch not found".
test_assemble_local_base_absent_with_the_remote_branch_present_succeeds() {
  local repo origin_tip
  repo="$(build_deliver_base)"
  origin_tip="$(advance_origin_branch "$repo" master "docs/remote-only.md" $'remote only\n' "docs: a commit that only ever reached origin")"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  commit_file "$repo" "src/greet.sh" $'greet v1 (unit)\n' "lego(U01): implementation"
  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"
  # integration is checked out, so the local base branch can go away
  # entirely -- as it does in a worktree that never created one.
  git -C "$repo" branch -D master >/dev/null 2>&1

  local manifest branch="lego/deliver/plan1/U01"
  manifest="$(write_valid_manifest "$repo" "test: no local base ref" "$branch" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "local base ref absent, remote branch present: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    if ! git -C "$repo" merge-base --is-ancestor "$origin_tip" "$branch" 2>/dev/null; then
      record_fail "the delivery branch must fork from origin/master's tip when no local base ref exists"
    fi
    assert_eq "greet v1 (unit)" "$(git -C "$repo" show "$branch:src/greet.sh" 2>/dev/null || echo MISSING)" "the unit's content is delivered from a purely remote base"
  else
    record_fail "expected delivery branch $branch to exist"
  fi

  if git -C "$repo" show-ref --verify --quiet "refs/heads/master"; then
    record_fail "deliver must not recreate a local base branch"
  fi
}

# The lower bound handed to newest_commit_with_subject moves with the base
# too. An older plan's commit carrying this unit's exact subject is already
# on origin's master and reaches the unit branch through the mid-flight
# refresh merge; it is NOT in the stale local master. Under the fresh base it
# is below the lower bound and excluded; under the stale one it is inside the
# scan range and -- being the newer of the two by commit date -- outranks the
# unit's own commit, so the wrong commit's file list is delivered.
test_assemble_subject_scan_lower_bound_uses_the_fresh_base() {
  local repo stray_sha unit_sha
  repo="$(build_deliver_base)"
  stray_sha="$(advance_origin_branch "$repo" master "src/other.sh" $'other v9 (an older plan, already on origin)\n' "lego(U01): implementation" "2026-06-01T00:00:00Z")"

  git -C "$repo" checkout -q -b "lego/plan1/U01-greetstuff" master
  mkdir -p "$repo/src"
  printf '%s' $'greet v1 (unit)\n' > "$repo/src/greet.sh"
  git -C "$repo" add -- "src/greet.sh"
  GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
    git -C "$repo" commit -q -m "lego(U01): implementation"
  unit_sha="$(git -C "$repo" rev-parse HEAD)"
  # The mid-flight refresh every long-running unit branch does: merge the
  # base as it stands on the remote.
  git -C "$repo" fetch -q origin master >/dev/null 2>&1
  git -C "$repo" merge -q --no-ff -m "lego: refresh the unit branch from the base" FETCH_HEAD >/dev/null 2>&1

  git -C "$repo" checkout -q master
  integrate_units "$repo" "lego/plan1/U01-greetstuff"

  # Fixture precondition: under the stale local base the stray really does
  # outrank the unit's own commit in the scan. Without that this test cannot
  # tell the two lower bounds apart.
  local first_under_stale
  first_under_stale="$(git -C "$repo" log --no-merges --format='%H' "master..lego/plan1/U01-greetstuff" | head -n1)"
  [ "$first_under_stale" = "$stray_sha" ] || record_fail "fixture precondition: expected the stray commit ($stray_sha) to be scanned first under the stale local base, got [$first_under_stale]"

  local manifest branch="lego/deliver/plan1/U01"
  manifest="$(write_valid_manifest "$repo" "test: subject scan lower bound" "$branch" U01)"

  run_in "$repo" assemble --manifest "$manifest" plan1 master U01 greetstuff
  [ "$RUN_EXIT" -eq 0 ] || record_fail "same-subject stray on origin's base: expected exit 0, got $RUN_EXIT (stderr: $RUN_ERR)"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    assert_eq "greet v1 (unit)" "$(git -C "$repo" show "$branch:src/greet.sh" 2>/dev/null || echo MISSING)" "the subject scan's lower bound is the fresh base, so the unit's own commit ($unit_sha) wins over the stray already on origin ($stray_sha)"
    if ! git -C "$repo" merge-base --is-ancestor "$stray_sha" "$branch" 2>/dev/null; then
      record_fail "the stray commit is part of origin's base branch, so the delivery branch inherits it from the base"
    fi
  else
    record_fail "expected delivery branch $branch to exist"
  fi
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

run_test "deliver: usage error on wrong argument count (plan-scoped, --manifest present)" test_assemble_usage
run_test "deliver: usage error on odd unit-id/unit-slug pair count (--manifest present)" test_assemble_odd_paired_args
run_test "deliver: usage error on invalid characters in plan-slug/base-branch/unit-id/unit-slug (--manifest present)" test_assemble_invalid_chars
run_test "deliver --manifest: --manifest flag itself is required, dies exit 3 when absent (B01 manifest-required)" test_assemble_manifest_flag_required
run_test "assemble: succeeds with GH=/nonexistent -- gh is no longer a dependency (B10)" test_assemble_succeeds_without_gh
run_test "assemble: never invokes gh, even when a working gh is present on PATH (B10)" test_assemble_never_invokes_gh_even_when_present
run_test "deliver: missing dependency/input errors (jq, config.json, blocks.md)" test_assemble_missing_dependencies
run_test "deliver: constructed unit branch does not exist" test_assemble_zero_branch_match
run_test "deliver: cross-plan isolation (same unit-id under a different plan is untouched)" test_assemble_cross_plan_isolation
run_test "deliver: stale same-subject commit inherited from base history is skipped, not fatal" test_assemble_stale_tests_commit_in_base_history_is_skipped
run_test "deliver: unit whose implementation commit touches no files fails loudly, not silently" test_assemble_unit_with_empty_commit_fails_loudly
run_test "deliver: a merge stamped with the unit subject is skipped; the plain same-subject commit wins" test_assemble_stamped_merge_commit_is_not_resolved
run_test "deliver: a stamped merge as the ONLY same-subject commit fails loudly instead of contributing nothing" test_assemble_only_a_stamped_merge_fails_loudly
run_test "deliver: restores content from the integration tip, not the resolved unit commit (B06 deliver tip-restore)" test_assemble_restores_integration_tip_content_not_unit_commit
run_test "deliver: the restored file list still comes from the unit commit's diff-tree, not the tip (B06 deliver tip-restore)" test_assemble_file_list_still_comes_from_the_unit_commit
run_test "deliver: a path absent at the integration tip is removed when tracked in the delivery worktree (B06 deliver tip-restore)" test_assemble_path_absent_at_tip_is_removed_when_tracked
run_test "deliver: a path absent at the integration tip and untracked in the delivery worktree is silently skipped (B06 deliver tip-restore)" test_assemble_path_absent_at_tip_and_untracked_is_skipped
run_test "deliver: a restore whose tip content matches the delivery worktree creates no commit (B06 deliver tip-restore)" test_assemble_noop_restore_when_tip_matches_the_delivery_base
run_test "deliver: an empty unit commit still fails loudly when the integration tip has content (B06 deliver tip-restore)" test_assemble_empty_unit_commit_still_fails_when_the_tip_has_content
run_test "deliver: missing required implementation commit" test_assemble_missing_implementation_commit_fails
run_test "deliver: delivery branch already exists at new plan-scoped path (EC3)" test_assemble_delivery_branch_already_exists
run_test "assemble: an unreachable origin falls back to the local base (B10 no push, ls-remote-first fresh-base design)" test_assemble_unreachable_origin_falls_back_to_local_base
run_test "deliver: tests commit is optional (untested prose unit)" test_assemble_tests_commit_optional_success
run_test "deliver: single unit - union of Code paths, newest-exact-subject, space path (EC1,EC2,D1,D4)" test_assemble_single_unit_union_and_newest_and_spaces
run_test "assemble: multi-unit branch naming is manifest-provided, not constructed (B01 manifest-required)" test_assemble_multi_unit_branch_naming_and_pr_title_order
run_test "assemble: multi-unit argument order is preserved, not sorted, in the delivery branch's commit sequence (branch naming is manifest-only) (B01 manifest-required)" test_assemble_multi_unit_argument_order_is_not_sorted
run_test "deliver: restore producing no changes creates no second commit" test_assemble_noop_restore_creates_no_second_commit

run_test "deliver --manifest: unreadable manifest path exits 3 (B01 deliver-manifest)" test_assemble_manifest_invalid_file
run_test "deliver --manifest: invalid JSON exits 3 (B01 deliver-manifest)" test_assemble_manifest_invalid_json
run_test "deliver --manifest: missing non-empty title exits 3 (B01 manifest-required)" test_assemble_manifest_missing_title
run_test "deliver --manifest: missing non-empty branch exits 3 (B01 manifest-required)" test_assemble_manifest_missing_branch
run_test "deliver --manifest: missing non-empty commits.<unit-id>.impl for any delivered unit exits 3 (B01 manifest-required)" test_assemble_manifest_missing_unit_impl
run_test "deliver --manifest: body remains optional, falls back to auto-generated default (B01 manifest-required)" test_assemble_manifest_body_optional_default
run_test "deliver --manifest: per-unit tests commit subject remains optional, falls back to default (B01 manifest-required)" test_assemble_manifest_tests_subject_optional_default
run_test "assemble --manifest: manifest file is never modified, even with title/body set (title/body are vestigial under B10 -- no gh/PR call consumes them) (B01 deliver-manifest)" test_assemble_manifest_file_is_read_only
run_test "deliver --manifest: branch override replaces default delivery branch name (B01 deliver-manifest)" test_assemble_manifest_branch_override
run_test "deliver --manifest: commit subject overrides replace default tests/impl subjects (B01 deliver-manifest)" test_assemble_manifest_commit_subjects_override
run_test "deliver --manifest: partial manifest missing required fields (branch/commits.impl) is rejected exit 3 (B01 manifest-required)" test_assemble_manifest_partial
run_test "deliver --manifest: manifest branch already exists exits 4 (B01 deliver-manifest)" test_assemble_manifest_branch_already_exists
run_test "deliver --manifest: empty object manifest is rejected for missing required fields, exit 3 (B01 manifest-required)" test_assemble_manifest_empty_object
run_test "deliver --manifest: empty-string required field (title/branch/commits.impl) treated as absent, exit 3 (B01 manifest-required)" test_assemble_manifest_empty_string_field_treated_as_absent

run_test "deliver: files not in Code: field are included via commit diff-tree" test_assemble_files_not_in_code_field_are_included

run_test "remove: usage error on wrong argument count (plan-scoped)" test_remove_usage
run_test "remove: usage error on invalid characters in plan-slug/unit-id/unit-slug" test_remove_invalid_chars
run_test "remove: constructed branch does not exist" test_remove_zero_branch_match
run_test "remove: cross-plan isolation (same unit-id under a different plan is untouched)" test_remove_cross_plan_isolation
run_test "remove: success removes worktree and deletes branch" test_remove_success
run_test "remove: dirty worktree fails" test_remove_dirty_worktree_fails
run_test "remove: unmerged branch fails (worktree still removed)" test_remove_unmerged_branch_fails

run_test "unknown subcommand" test_unknown_subcommand
run_test "deliver: gone as a subcommand, rejected as unknown (exit 2) (B10)" test_deliver_subcommand_is_unknown

run_test "merge: removes unit worktree on success, keeps branch (B01)" test_merge_removes_unit_worktree_on_success
run_test "merge: unit-worktree cleanup failure does not change exit code (B01)" test_merge_worktree_removal_failure_does_not_change_exit_code

run_test "deliver: cleanup removes unit branch and worktree, keeps delivery branch and PR URL (B01)" test_assemble_cleanup_removes_unit_branch_and_worktree
run_test "deliver: branch-cleanup failure does not change exit code or suppress PR URL (B01)" test_assemble_cleanup_branch_deletion_failure_still_exits_0

run_test "clean: bare clean and extra arguments are usage errors (B02 clean-plan-scoped)" test_clean_usage_unexpected_args
run_test "clean --all: requires running inside a git work tree (B01)" test_clean_requires_git_work_tree
run_test "clean --all: no lego branches exits 0 and prints count 0 (B01)" test_clean_no_lego_branches
run_test "clean --all: removes merged lego/*/* and lego/deliver/*/* branches+worktrees; skips unmerged; leaves non-lego untouched (B01 worktree-plan-scoping)" test_clean_removes_merged_lego_and_delivery_branches_and_worktrees
run_test "clean --all: runs git worktree prune to clean up stale worktree entries (B01)" test_clean_prunes_stale_worktree_entries

run_test "clean <plan-slug>: removes only in-scope merged branches; reports foreign; unmerged in-scope wins over foreign (B02 clean-plan-scoped)" test_clean_plan_scoped_removes_only_in_scope_and_reports_foreign
run_test "clean <plan-slug>: plan slug matching no branches exits 0, prints 0, no messages (B02 clean-plan-scoped)" test_clean_plan_scoped_matches_no_branches
run_test "clean --all: spans all plans, no foreign-skip messages (B02 clean-plan-scoped)" test_clean_all_mode_spans_all_plans_with_no_foreign_messages
run_test "clean <plan-slug>: invalid token as plan-slug is a usage error (B02 clean-plan-scoped)" test_clean_invalid_plan_slug_token_is_usage_error

run_test "archive: merge copies exactly briefs/, reports/, status.md with content intact, then removes the worktree (B01 worktree-unit-archive)" test_archive_merge_copies_three_components_only
run_test "archive: same unit id under two plan slugs produces two isolated archives, neither clobbering the other (B01 worktree-unit-archive)" test_archive_plan_scoping_isolates
run_test "archive: a component absent from the source is skipped without failing (B01 worktree-unit-archive)" test_archive_skips_absent_components_without_failing
run_test "archive: a hand-made unit worktree with no .local/ at all archives nothing (B01 worktree-unit-archive)" test_archive_nothing_when_source_has_no_local_at_all
run_test "archive: a .local/ holding none of the three components archives nothing (B01 worktree-unit-archive)" test_archive_nothing_when_local_has_none_of_the_three_components
run_test "archive: add's empty briefs/reports/ are archived as empty directories, distinguishing archived-empty from never-archived (B01 worktree-unit-archive)" test_archive_empty_seeded_dirs_are_archived_as_empty
run_test "archive: re-archiving overwrites same-named destination files and leaves destination-only files in place (B01 worktree-unit-archive)" test_archive_rearchive_overwrites_same_named_preserves_others
run_test "archive: merge warns and keeps the worktree on an archive failure, exit 0 (B01 worktree-unit-archive)" test_archive_merge_failure_warns_and_keeps_worktree_exit0
run_test "archive: assemble warns and keeps both the worktree and branch on an archive failure, exit 0, assembled branch name still last stdout line (B01 worktree-unit-archive)" test_archive_assemble_failure_warns_and_keeps_worktree_and_branch
run_test "archive: remove exits 4 and removes nothing on an archive failure (B01 worktree-unit-archive)" test_archive_remove_failure_exit4_removes_nothing
run_test "archive: clean never archives, by design (B01 worktree-unit-archive)" test_archive_clean_does_not_archive
run_test "archive: never modifies a tracked file in the invoking worktree (B01 worktree-unit-archive)" test_archive_never_modifies_invoking_worktree_tracked_files
run_test "archive: deterministic across identical repo state and arguments (B01 worktree-unit-archive)" test_archive_deterministic_across_identical_repo_state
run_test "archive: assemble's successful cleanup archives the worktree's audit trail before removing it, keeps branch deleted, assembled branch name still last stdout line (B01 worktree-unit-archive)" test_archive_assemble_success_archives_before_removing_worktree
run_test "archive: a successful merge archive leaves the source worktree's .local/ untouched when the later removal fails, proving copy-not-move (B01 worktree-unit-archive)" test_archive_merge_success_removal_failure_preserves_source_copy

run_test "realm.sh: testPatterns union combines base and override files (NEW)" test_realm_testpatterns_union_combines_base_and_override
run_test "realm.sh: testPatterns from base alone when no override file is present (NEW)" test_realm_testpatterns_base_only_when_no_override_present
run_test "realm.sh: \$LEGO_CONFIG overrides only the override file's location; base path is fixed (NEW)" test_realm_lego_config_env_overrides_only_override_location_base_fixed

run_test "deliver --manifest: extraCommits appends one commit per entry, in manifest order, after every unit commit (B07 manifest extraCommits)" test_assemble_extra_commits_appended_after_unit_commits_in_order
run_test "deliver --manifest: an extra commit's content comes from the integration tip, not any unit-branch version (B07 manifest extraCommits)" test_assemble_extra_commit_content_comes_from_the_integration_tip
run_test "deliver --manifest: an entry path absent at the tip is removed when tracked in the delivery worktree (B07 manifest extraCommits)" test_assemble_extra_commit_path_absent_at_tip_is_removed_when_tracked
run_test "deliver --manifest: an entry path absent at the tip and untracked is silently skipped (B07 manifest extraCommits)" test_assemble_extra_commit_path_absent_at_tip_and_untracked_is_skipped
run_test "deliver --manifest: an entry whose restore stages no diff creates no commit (B07 manifest extraCommits)" test_assemble_extra_commit_entry_staging_no_diff_creates_no_commit
run_test "deliver --manifest: absent and empty extraCommits reproduce the previous delivery; non-empty does not (B07 manifest extraCommits)" test_assemble_extra_commits_absent_and_empty_reproduce_previous_behavior
run_test "deliver --manifest: extraCommits that is not an array exits 3 (B07 manifest extraCommits)" test_assemble_extra_commits_not_an_array_exits_3
run_test "deliver --manifest: an entry with a missing or empty subject exits 3 (B07 manifest extraCommits)" test_assemble_extra_commits_entry_missing_or_empty_subject_exits_3
run_test "deliver --manifest: an entry whose files is missing, empty or not an array exits 3 (B07 manifest extraCommits)" test_assemble_extra_commits_entry_files_missing_empty_or_non_array_exits_3
run_test "deliver --manifest: a malformed extraCommits dies before any branch, worktree, push or PR (B07 manifest extraCommits)" test_assemble_extra_commits_malformed_dies_before_any_branch_or_worktree
run_test "deliver --manifest: a valid extraCommits does not relax the required-field validation (B07 manifest extraCommits)" test_assemble_extra_commits_does_not_relax_required_field_validation

run_test "deliver: a stale local base forks the delivery branch from the freshly fetched origin/<base>, and nothing beyond it is fetched (B10 deliver fresh-base)" test_assemble_forks_from_the_freshly_fetched_origin_when_the_local_base_is_stale
run_test "deliver: no origin remote resolves the local base unchanged, failing at the push as today (B10 deliver fresh-base)" test_assemble_without_an_origin_remote_uses_the_local_base_unchanged
run_test "deliver: an origin that does not carry <base-branch> falls back to the local ref and succeeds (B10 deliver fresh-base)" test_assemble_origin_without_the_base_branch_falls_back_to_the_local_ref
run_test "deliver: origin carries <base-branch> but the fetch fails -> exit 4 naming the fetch (B10 deliver fresh-base)" test_assemble_fetch_failure_dies_naming_the_fetch
run_test "deliver: a failing fetch is fatal even with a resolvable stale origin/<base> to fall back on (B10 deliver fresh-base)" test_assemble_fetch_failure_with_an_intact_tracking_ref_dies_naming_the_fetch
run_test "deliver: a base resolvable neither remotely nor locally is still exit 4 'base branch not found' (B10 deliver fresh-base)" test_assemble_base_missing_locally_and_remotely_exits_4
run_test "deliver: a local base AHEAD of origin still forks from origin; the unpushed commit is absent (B10 deliver fresh-base)" test_assemble_local_base_ahead_of_origin_still_forks_from_origin
run_test "deliver: no local <base-branch> ref at all succeeds when origin carries it (B10 deliver fresh-base)" test_assemble_local_base_absent_with_the_remote_branch_present_succeeds
run_test "deliver: the subject-scan lower bound moves with the base, excluding a same-subject stray already on origin (B10 deliver fresh-base)" test_assemble_subject_scan_lower_bound_uses_the_fresh_base

echo "---"
echo "Passed: $TOTAL_PASS  Failed: $TOTAL_FAIL  Total: $((TOTAL_PASS + TOTAL_FAIL))"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
