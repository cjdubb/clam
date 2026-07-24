#!/usr/bin/env bash
# version-bump-lint.test.sh — contract tests for scripts/version-bump-lint.sh
# (B01 version-bump-lint, plan 001-pseudo-ci).
#
# Black-box only: builds throwaway git repositories under mktemp -d, commits
# fixture states (a base commit plus follow-up commits under plugins/), and
# invokes scripts/version-bump-lint.sh by absolute path (resolved via
# BASH_SOURCE) with the fixture directory — or a subdirectory of it — as
# cwd. Every case that isn't specifically about base-resolution pins the
# comparison base explicitly with `--base <ref>`. Asserts on exit code and
# stdout/stderr content only — never on git plumbing internals.
#
# Ambient neutralization: every fixture repo gets its own user.name/
# user.email and a core.hooksPath pointed at a directory that never exists,
# so no ambient global git hooks can interfere with fixture commits.
#
# Mirrors the PASS/FAIL harness style of scripts/readme-lint.test.sh; the
# jq-missing PATH shim mirrors plugins/tracking/scripts/capture.test.sh's
# build_path_without helper.
#
# Run: bash scripts/version-bump-lint.test.sh   (exits non-zero on failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/version-bump-lint.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: script under test not found at $SCRIPT" >&2
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
# Cleanup registry for mktemp fixture trees (command substitution forks a
# subshell, so a file-based manifest is needed to survive it).
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
# Fixture repo builders.
# ---------------------------------------------------------------------------
new_repo() { # -> prints repo root path, a fresh git init'd repo on branch "main"
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  git init -q -b main "$d"
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  # Neutralize any ambient global hooksPath so fixture commits never run a
  # real hook.
  git -C "$d" config core.hooksPath "$d/.git/no-such-hooks-dir"
  printf '%s' "$d"
}

write_plugin_json() { # repo name version [description]
  local repo="$1" name="$2" version="$3" desc="${4:-A test plugin.}"
  mkdir -p "$repo/plugins/$name/.claude-plugin"
  cat > "$repo/plugins/$name/.claude-plugin/plugin.json" <<EOF
{
  "name": "$name",
  "version": "$version",
  "description": "$desc"
}
EOF
}

write_plugin_file() { # repo name relpath content
  local repo="$1" name="$2" rel="$3" content="$4"
  mkdir -p "$repo/plugins/$name/$(dirname "$rel")"
  printf '%s' "$content" > "$repo/plugins/$name/$rel"
}

write_file() { # repo relpath content
  local repo="$1" rel="$2" content="$3"
  mkdir -p "$(dirname "$repo/$rel")"
  printf '%s' "$content" > "$repo/$rel"
}

commit_all() { # repo message -> prints resulting commit SHA
  local repo="$1" msg="$2"
  git -C "$repo" add -A >/dev/null
  git -C "$repo" -c commit.gpgsign=false commit -q -m "$msg" >/dev/null
  git -C "$repo" rev-parse HEAD
}

# ---------------------------------------------------------------------------
# `jq`-missing PATH shim: every /usr/bin entry except jq, symlinked into a
# fresh dir (git and bash — both needed to invoke the script under test —
# live in /usr/bin here, so both stay reachable; only jq disappears).
# ---------------------------------------------------------------------------
build_path_without() { # cmd -> prints new PATH dir
  local cmd="$1" out
  out="$(mktemp -d)"
  track_tmp "$out"
  ln -s /usr/bin/* "$out/" 2>/dev/null
  rm -f "$out/$cmd"
  printf '%s' "$out"
}
NOJQBIN="$(build_path_without jq)"

# ---------------------------------------------------------------------------
# Invocation helper.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
RUN_PATH=""

run_lint() { # <cwd> [args...]   (honors $RUN_PATH override if set)
  local wd="$1"; shift
  local out err
  out="$(mktemp)"; err="$(mktemp)"
  if [ -n "${RUN_PATH:-}" ]; then
    ( cd "$wd" && PATH="$RUN_PATH" bash "$SCRIPT" "$@" >"$out" 2>"$err" )
  else
    ( cd "$wd" && bash "$SCRIPT" "$@" >"$out" 2>"$err" )
  fi
  RUN_EXIT=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  rm -f "$out" "$err"
}

# ---------------------------------------------------------------------------
# Assertion helpers over RUN_OUT / RUN_ERR text blobs (mirrors
# readme-lint.test.sh's substring-based, wording-agnostic style).
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

repo_snapshot() { # repo -> a signature covering worktree contents + HEAD + status
  local repo="$1"
  ( cd "$repo" && find . -path ./.git -prune -o -type f -exec sha256sum {} + ) | sort
  echo "HEAD:$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
  echo "STATUS:$(git -C "$repo" status --porcelain=v1 2>/dev/null)"
}

# ===========================================================================
# 1. Vacuous pass: no plugin changes, HEAD equals the merge-base.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init foo")"
run_lint "$f" --base "$c0"
check "1. vacuous pass: exit 0" "$RUN_EXIT" "0"
check "1. vacuous pass: reports no plugin changes" \
  "$(contains "$RUN_OUT" "no plugin changes to check")" "yes"
check "1. vacuous pass: no ALL PASS trailer" \
  "$(contains "$RUN_OUT" "ALL PASS")" "no"
check "1. vacuous pass: no FAIL text" \
  "$(contains "$RUN_OUT" "FAIL")" "no"

# ===========================================================================
# 2. Change without a version bump: FAIL, exit 1.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init foo")"
write_plugin_file "$f" foo "notes.md" "some content change"
commit_all "$f" "edit foo without bump" >/dev/null
run_lint "$f" --base "$c0"
check "2. change without bump: exit 1" "$RUN_EXIT" "1"
check "2. change without bump: FAIL names foo" \
  "$(line_has_all "$RUN_OUT" "FAIL" "foo")" "yes"
check "2. change without bump: unchanged version shown" \
  "$(line_has_all "$RUN_OUT" "foo" "1.0.0")" "yes"
check "2. change without bump: exact FAIL line format" \
  "$(contains "$RUN_OUT" "FAIL  foo -> files changed but version unchanged (1.0.0)")" "yes"
check "2. change without bump: FAILURES trailer preceded by a blank line" \
  "$(contains "$RUN_OUT" "$(printf '\n\nFAILURES — fix before merging')")" "yes"
check "2. change without bump: remediation names plugin.json path" \
  "$(contains "$RUN_OUT" "plugins/foo/.claude-plugin/plugin.json")" "yes"

# ===========================================================================
# 3. Change with a version bump: PASS, exit 0.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init foo")"
write_plugin_file "$f" foo "notes.md" "some content change"
write_plugin_json "$f" foo 1.1.0
commit_all "$f" "edit foo with bump" >/dev/null
run_lint "$f" --base "$c0"
check "3. change with bump: exit 0" "$RUN_EXIT" "0"
check "3. change with bump: exact PASS line format" \
  "$(contains "$RUN_OUT" "PASS  foo (version 1.0.0 -> 1.1.0)")" "yes"
check "3. change with bump: ALL PASS trailer preceded by a blank line" \
  "$(contains "$RUN_OUT" "$(printf '\n\nALL PASS')")" "yes"

# ===========================================================================
# 4. New plugin (no plugin.json at merge-base): PASS.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init foo")"
write_plugin_json "$f" bar 1.0.0
write_plugin_file "$f" bar "README.md" "bar plugin"
commit_all "$f" "add bar" >/dev/null
run_lint "$f" --base "$c0"
check "4. new plugin: exit 0" "$RUN_EXIT" "0"
check "4. new plugin: PASS names bar" \
  "$(line_has_all "$RUN_OUT" "PASS" "bar")" "yes"
check "4. new plugin: untouched foo has no verdict line" \
  "$(line_has_all "$RUN_OUT" "foo")" "no"

# ===========================================================================
# 5. Plugin deleted entirely at HEAD: skipped (no verdict line), alongside a
#    real PASS for an unrelated plugin so exit code / trailer are unambiguous.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
write_plugin_json "$f" baz 1.0.0
write_plugin_file "$f" baz "notes.md" "baz content"
c0="$(commit_all "$f" "init foo+baz")"
write_plugin_file "$f" foo "notes.md" "foo content"
write_plugin_json "$f" foo 1.1.0
rm -rf "$f/plugins/baz"
commit_all "$f" "bump foo, delete baz" >/dev/null
run_lint "$f" --base "$c0"
check "5. deleted plugin skipped: exit 0" "$RUN_EXIT" "0"
check "5. deleted plugin skipped: PASS for foo" \
  "$(line_has_all "$RUN_OUT" "PASS" "foo")" "yes"
check "5. deleted plugin skipped: no baz verdict line" \
  "$(line_has_all "$RUN_OUT" "baz")" "no"
check "5. deleted plugin skipped: ALL PASS trailer" \
  "$(contains "$RUN_OUT" "ALL PASS")" "yes"

# ===========================================================================
# 6. plugin.json-only change, only the version differs: PASS.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0 "Original description."
write_plugin_file "$f" foo "notes.md" "static content"
c0="$(commit_all "$f" "init foo")"
write_plugin_json "$f" foo 1.1.0 "Original description."
commit_all "$f" "bump only" >/dev/null
run_lint "$f" --base "$c0"
check "6. plugin.json-only version bump: exit 0" "$RUN_EXIT" "0"
check "6. plugin.json-only version bump: exact PASS line format" \
  "$(contains "$RUN_OUT" "PASS  foo (version 1.0.0 -> 1.1.0)")" "yes"

# ===========================================================================
# 7. plugin.json changed (e.g. description) but version identical: FAIL.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0 "Original description."
c0="$(commit_all "$f" "init foo")"
write_plugin_json "$f" foo 1.0.0 "Updated description, no version bump."
commit_all "$f" "description only" >/dev/null
run_lint "$f" --base "$c0"
check "7. plugin.json non-version change: exit 1" "$RUN_EXIT" "1"
check "7. plugin.json non-version change: exact FAIL line format" \
  "$(contains "$RUN_OUT" "FAIL  foo -> files changed but version unchanged (1.0.0)")" "yes"

# ===========================================================================
# 8. Multiple plugins, mixed verdicts: one PASS, one FAIL, one untouched.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" alpha 1.0.0
write_plugin_json "$f" beta 1.0.0
write_plugin_json "$f" gamma 1.0.0
c0="$(commit_all "$f" "init three plugins")"
write_plugin_file "$f" alpha "notes.md" "alpha change"
write_plugin_json "$f" alpha 2.0.0
write_plugin_file "$f" beta "notes.md" "beta change"
commit_all "$f" "mixed changes" >/dev/null
run_lint "$f" --base "$c0"
check "8. mixed verdicts: exit 1 (beta fails)" "$RUN_EXIT" "1"
check "8. mixed verdicts: alpha PASS" \
  "$(line_has_all "$RUN_OUT" "PASS" "alpha")" "yes"
check "8. mixed verdicts: beta FAIL" \
  "$(line_has_all "$RUN_OUT" "FAIL" "beta")" "yes"
check "8. mixed verdicts: gamma has no verdict line" \
  "$(line_has_all "$RUN_OUT" "gamma")" "no"
check "8. mixed verdicts: FAILURES trailer" \
  "$(contains "$RUN_OUT" "FAILURES — fix before merging")" "yes"

# ===========================================================================
# 9. Changes outside plugins/ are ignored entirely: vacuous pass.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
write_file "$f" "scripts/foo.sh" "#!/bin/bash
echo hi
"
write_file "$f" "README.md" "# repo
"
c0="$(commit_all "$f" "init")"
write_file "$f" "scripts/foo.sh" "#!/bin/bash
echo changed
"
write_file "$f" "README.md" "# repo changed
"
write_file "$f" ".claude-plugin/marketplace.json" '{"plugins":[]}'
commit_all "$f" "non-plugin changes" >/dev/null
run_lint "$f" --base "$c0"
check "9. changes outside plugins/ ignored: exit 0" "$RUN_EXIT" "0"
check "9. changes outside plugins/ ignored: vacuous message" \
  "$(contains "$RUN_OUT" "no plugin changes to check")" "yes"

# ===========================================================================
# 10. Files directly under plugins/ (not inside any <name>/ dir): ignored.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init")"
write_file "$f" "plugins/PLUGIN_README_TEMPLATE.md" "template body"
commit_all "$f" "add top-level plugins file" >/dev/null
run_lint "$f" --base "$c0"
check "10. files directly under plugins/ ignored: exit 0" "$RUN_EXIT" "0"
check "10. files directly under plugins/ ignored: vacuous message" \
  "$(contains "$RUN_OUT" "no plugin changes to check")" "yes"

# ===========================================================================
# 11. Uncommitted (unstaged) changes are ignored — only the committed range
#     counts.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init")"
write_plugin_file "$f" foo "notes.md" "uncommitted edit"
run_lint "$f" --base "$c0"
check "11. uncommitted (unstaged) changes ignored: exit 0" "$RUN_EXIT" "0"
check "11. uncommitted (unstaged) changes ignored: vacuous message" \
  "$(contains "$RUN_OUT" "no plugin changes to check")" "yes"

# ===========================================================================
# 12. Staged-but-uncommitted changes are ignored too.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init")"
write_plugin_file "$f" foo "notes.md" "staged edit"
git -C "$f" add -A >/dev/null
run_lint "$f" --base "$c0"
check "12. staged-but-uncommitted changes ignored: exit 0" "$RUN_EXIT" "0"
check "12. staged-but-uncommitted changes ignored: vacuous message" \
  "$(contains "$RUN_OUT" "no plugin changes to check")" "yes"

# ===========================================================================
# 13. File renamed across plugin dirs counts as a change for BOTH the source
#     and destination plugins.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" alpha 1.0.0
write_plugin_file "$f" alpha "notes.md" "shared content, unchanged across the rename"
write_plugin_json "$f" beta 1.0.0
c0="$(commit_all "$f" "init alpha+beta")"
git -C "$f" mv plugins/alpha/notes.md plugins/beta/notes.md
commit_all "$f" "move notes from alpha to beta" >/dev/null
run_lint "$f" --base "$c0"
check "13. rename across plugins: exit 1 (neither bumped)" "$RUN_EXIT" "1"
check "13. rename across plugins: FAIL for alpha (source)" \
  "$(line_has_all "$RUN_OUT" "FAIL" "alpha")" "yes"
check "13. rename across plugins: FAIL for beta (destination)" \
  "$(line_has_all "$RUN_OUT" "FAIL" "beta")" "yes"

# ===========================================================================
# 14. Version decrease still counts as "changed" — no semver ordering.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 2.0.0
write_plugin_file "$f" foo "notes.md" "before"
c0="$(commit_all "$f" "init foo at 2.0.0")"
write_plugin_file "$f" foo "notes.md" "after"
write_plugin_json "$f" foo 1.0.0
commit_all "$f" "decrease version" >/dev/null
run_lint "$f" --base "$c0"
check "14. version decrease counts as changed: exit 0" "$RUN_EXIT" "0"
check "14. version decrease counts as changed: exact PASS line format" \
  "$(contains "$RUN_OUT" "PASS  foo (version 2.0.0 -> 1.0.0)")" "yes"

# ===========================================================================
# 15. --base default: origin/master is preferred over master when both
#     exist. master is set up to point at an ALREADY-bumped commit (which
#     would wrongly yield a PASS-hiding-nothing-to-see... actually yields a
#     FAIL if wrongly used, since the file changes again after without a
#     further bump); origin/master points at the pre-bump commit, which
#     yields PASS. A PASS here proves origin/master won.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init foo 1.0.0")"
write_plugin_file "$f" foo "notes.md" "first edit"
write_plugin_json "$f" foo 1.1.0
c1="$(commit_all "$f" "bump foo to 1.1.0")"
git -C "$f" branch master "$c1"
git -C "$f" update-ref refs/remotes/origin/master "$c0"
write_plugin_file "$f" foo "notes.md" "second edit, no further bump"
commit_all "$f" "second edit" >/dev/null
run_lint "$f"
check "15. default base prefers origin/master over master: exit 0" "$RUN_EXIT" "0"
check "15. default base prefers origin/master over master: PASS for foo" \
  "$(line_has_all "$RUN_OUT" "PASS" "foo")" "yes"

# ===========================================================================
# 16. --base default: falls back to master when no origin/master exists.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init foo 1.0.0")"
git -C "$f" branch master "$c0"
git -C "$f" checkout -q -b work
write_plugin_file "$f" foo "notes.md" "edit without bump"
commit_all "$f" "edit foo, no bump" >/dev/null
run_lint "$f"
check "16. default base falls back to master: exit 1" "$RUN_EXIT" "1"
check "16. default base falls back to master: FAIL for foo" \
  "$(line_has_all "$RUN_OUT" "FAIL" "foo")" "yes"

# ===========================================================================
# 17. --base default: neither origin/master nor master resolves: exit 2.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
commit_all "$f" "init" >/dev/null
run_lint "$f"
check "17. default base, neither resolves: exit 2" "$RUN_EXIT" "2"
check "17. default base, neither resolves: stderr diagnostic" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 18. Not inside a git repository: exit 2.
# ===========================================================================
f="$(mktemp -d)"; track_tmp "$f"
run_lint "$f"
check "18. not a git repo: exit 2" "$RUN_EXIT" "2"
check "18. not a git repo: stderr diagnostic" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 19. jq not available: exit 2, regardless of what the diff would show.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init")"
write_plugin_file "$f" foo "notes.md" "edit"
commit_all "$f" "edit foo" >/dev/null
RUN_PATH="$NOJQBIN" run_lint "$f" --base "$c0"
check "19. jq missing: exit 2" "$RUN_EXIT" "2"
check "19. jq missing: stderr diagnostic" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 20. Usage error: unknown flag.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
commit_all "$f" "init" >/dev/null
run_lint "$f" --bogus-flag
check "20. usage error, unknown flag: exit 2" "$RUN_EXIT" "2"
check "20. usage error, unknown flag: stderr diagnostic" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 21. Usage error: --base given without a following value.
# ===========================================================================
run_lint "$f" --base
check "21. usage error, --base without value: exit 2" "$RUN_EXIT" "2"
check "21. usage error, --base without value: stderr diagnostic" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 22. plugin.json missing at HEAD for a changed-and-still-existing plugin:
#     FAIL (distinct from case 5, where the whole plugin dir is gone).
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
write_plugin_file "$f" foo "notes.md" "content"
c0="$(commit_all "$f" "init foo")"
rm -f "$f/plugins/foo/.claude-plugin/plugin.json"
write_plugin_file "$f" foo "notes.md" "content changed too"
commit_all "$f" "drop plugin.json, keep dir" >/dev/null
run_lint "$f" --base "$c0"
check "22. missing plugin.json at HEAD: exit 1" "$RUN_EXIT" "1"
check "22. missing plugin.json at HEAD: FAIL for foo" \
  "$(line_has_all "$RUN_OUT" "FAIL" "foo")" "yes"

# ===========================================================================
# 23. plugin.json unparseable at HEAD for a changed-and-existing plugin:
#     FAIL.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init foo")"
printf '{ "version": "1.0.0", this is not valid json' > "$f/plugins/foo/.claude-plugin/plugin.json"
commit_all "$f" "corrupt plugin.json" >/dev/null
run_lint "$f" --base "$c0"
check "23. unparseable plugin.json at HEAD: exit 1" "$RUN_EXIT" "1"
check "23. unparseable plugin.json at HEAD: FAIL for foo" \
  "$(line_has_all "$RUN_OUT" "FAIL" "foo")" "yes"

# ===========================================================================
# 24. Read-only invariant: the fixture repo (worktree, HEAD, git status) is
#     unchanged after a run that produces real output.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init foo")"
write_plugin_file "$f" foo "notes.md" "edit"
write_plugin_json "$f" foo 1.1.0
commit_all "$f" "bump" >/dev/null
before="$(repo_snapshot "$f")"
run_lint "$f" --base "$c0"
after="$(repo_snapshot "$f")"
check "24. read-only invariant: repo unchanged after run" "$after" "$before"

# ===========================================================================
# 25. cwd-independence: running from a subdirectory of the repo produces the
#     same result as running from the repo root.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init foo")"
write_plugin_file "$f" foo "notes.md" "edit"
write_plugin_json "$f" foo 1.1.0
commit_all "$f" "bump" >/dev/null
run_lint "$f" --base "$c0"
root_out="$RUN_OUT"; root_exit="$RUN_EXIT"
run_lint "$f/plugins/foo/.claude-plugin" --base "$c0"
check "25. cwd-independence: same exit code from nested cwd" "$RUN_EXIT" "$root_exit"
check "25. cwd-independence: same stdout from nested cwd" "$RUN_OUT" "$root_out"

# ===========================================================================
# 26. Explicit --base <ref> that does not resolve to a commit: exit 2, with
#     NO silent fallback to origin/master or master. master exists here and
#     would itself produce a clean FAIL verdict (files changed, no bump) if
#     consulted — so exit 2 (not exit 1 with a FAIL line) proves the typo'd
#     ref was not quietly swapped for a default.
# ===========================================================================
f="$(new_repo)"
write_plugin_json "$f" foo 1.0.0
c0="$(commit_all "$f" "init foo 1.0.0")"
git -C "$f" branch master "$c0"
write_plugin_file "$f" foo "notes.md" "edit without bump"
commit_all "$f" "edit foo, no bump" >/dev/null
run_lint "$f" --base no-such-ref
check "26. explicit unresolvable --base: exit 2 (no silent fallback)" "$RUN_EXIT" "2"
check "26. explicit unresolvable --base: stderr diagnostic" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"
check "26. explicit unresolvable --base: no fallback verdict leaked to stdout" \
  "$(contains "$RUN_OUT" "FAIL")" "no"

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
