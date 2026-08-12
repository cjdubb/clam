#!/usr/bin/env bash
# discovery-scan.test.sh — verifies the two docblocks marked
# "Contract: 002-B01 discovery scan" in plugins/render-doc/scripts/serve.py:
# worktree_siblings(root) and discover_docs(root), clause by clause.
#
# These two are the only part of the discovery feature that is NOT reachable
# over HTTP: they are pure helpers the index (002-B02) and the worktree landing
# page (002-B04) consume. So unlike every other suite for this file, the
# assertions here import serve.py as a module and call the functions directly,
# through PYTHONPATH. Importing is safe and side-effect-free for these clauses:
# the module only READS its registry file at import, and RENDER_DOC_PORT is
# pointed at a throwaway port so that read can never be a real session's.
#
# What the two contracts really promise is that neither function can ever be
# the reason a page fails to render. worktree_siblings must survive git being
# absent, failing, hanging, or talking nonsense; discover_docs must survive a
# missing directory, an unreadable one, a symlink cycle and a file that
# disappears. So most of the file is about degradation, and the fixtures are
# built to force each degradation rather than to describe a happy path:
#   - git shims earlier on PATH than the real binary, one per failure mode
#     (nonzero exit, garbage output, a 30-second hang, duplicate lines, a
#     listing that omits the root);
#   - a repo with two linked worktrees, one of which is deleted from disk
#     behind git's back, and a bare repo whose control directory git reports
#     as a worktree but which carries no .git entry;
#   - a .local tree carrying nested docs, non-.md files, a mode-000 directory,
#     a mode-000 document, a symlinked directory, a symlink cycle, a dangling
#     symlink and a symlink pointing out of the worktree entirely.
#
# Fixtures live under $HOME because discover_docs filters through scope_error,
# which requires exactly that (plus a git worktree ancestor).
#
# Marker note: plan-002 contract markers are plan-qualified ("Contract:
# 002-B01"). serve.py also carries a permanent, unrelated "Contract: B01"
# docblock from an earlier plan, so nothing here greps the bare form.
#
# Out of scope: how the index consumes these lists (index-discovery.test.sh),
# the registry (server-registry.test.sh), and the prose describing discovery
# (discovery-docs.test.sh).

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVE="$SCRIPT_DIR/serve.py"

WORK="$(mktemp -d)"
HOME_DIRS=()
TMP_ARTEFACTS=()

cleanup() {
  # chmod first: a fixture directory and a fixture document are deliberately
  # mode 000.
  for d in ${HOME_DIRS[@]+"${HOME_DIRS[@]}"}; do
    [ -n "$d" ] && chmod -R u+rwX "$d" 2> /dev/null
    [ -n "$d" ] && rm -rf "$d"
  done
  for f in ${TMP_ARTEFACTS[@]+"${TMP_ARTEFACTS[@]}"}; do
    [ -n "$f" ] && rm -rf "$f"
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

FAILURES=0
SKIPPED=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'ok: %s\n' "$*"
}
skip() {
  printf 'skip: %s\n' "$*"
  SKIPPED=$((SKIPPED + 1))
}

# --- Required tooling --------------------------------------------------------
MISSING=0
for tool in python3 git; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    fail "required tool not available: $tool"
    MISSING=1
  fi
done
if [ ! -f "$SERVE" ]; then
  fail "serve.py not found at $SERVE"
  MISSING=1
fi
if [ "$MISSING" -ne 0 ]; then
  printf 'discovery-scan.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

# --- Helpers -----------------------------------------------------------------

free_port() {
  local p
  while :; do
    p="$(python3 -c "import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()")"
    [ -n "$p" ] || return 1
    [ "$p" != "27183" ] && break
  done
  printf '%s' "$p"
}

# A throwaway port keys serve.py's registry file, so importing the module for a
# pure-function test can never read (or later be blamed for) a real session's
# registry.
PY_PORT="$(free_port)"
TMP_ARTEFACTS+=("/tmp/render-doc-registry-$PY_PORT.json")

realpath_of() {
  python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$1" 2> /dev/null
}

# run_py <label> [args...] — the python snippet arrives on stdin and is passed
# sys.argv[1:] = args. A snippet that returns cleanly is a pass; any exception
# (including the NotImplementedError of an unimplemented stub) is a fail
# carrying the tail of the traceback, so a red says WHY.
#
# PYTHONDONTWRITEBYTECODE keeps the import from dropping a __pycache__ into the
# plugin's own scripts/ directory: running a suite must leave no trace in the
# tree it tests.
PY_OUT=""
run_py() {
  local label="$1"
  shift
  if PY_OUT="$(PYTHONPATH="$SCRIPT_DIR" RENDER_DOC_PORT="$PY_PORT" \
    PYTHONDONTWRITEBYTECODE=1 python3 - "$@" 2>&1)"; then
    pass "$label"
    return 0
  fi
  fail "$label -- $(printf '%s' "$PY_OUT" | tail -2 | tr '\n' ' ')"
  return 1
}

# A fake git, earlier on PATH than the real one, so a failure mode can be forced
# without breaking the repo the test itself lives in.
make_git_shim() { # <dir> <body...>
  local dir="$1"
  shift
  mkdir -p "$dir"
  {
    printf '#!/bin/sh\n'
    printf '%s\n' "$@"
  } > "$dir/git"
  chmod +x "$dir/git"
}

# Every fixture path with its mtime, and every regular file with its content
# hash: both functions are specified read-only, and this is how that is proved
# rather than assumed.
# Portable stand-in for GNU `find -printf '%p %y %T@\n'`, which BSD find lacks:
# BSD `stat -f` first, GNU `stat -c` as the fallback; the type character comes
# from a test, so no %y either.
_mtime() { stat -f '%m' "$1" 2> /dev/null || stat -c '%Y' "$1" 2> /dev/null; }
manifest() {
  local p t
  find "$FIX" \( -type f -o -type l \) ! -path '*/.git/*' 2> /dev/null | sort \
    | while IFS= read -r p; do
        if [ -L "$p" ]; then t=l; else t=f; fi
        printf '%s %s %s\n' "$p" "$t" "$(_mtime "$p")"
      done
  find "$FIX" -type f ! -path '*/.git/*' -exec cksum {} + 2> /dev/null | sort
}

# --- Fixtures ----------------------------------------------------------------
FIX="$(mktemp -d "$HOME/.render-doc-discovery.XXXXXX")"
HOME_DIRS+=("$FIX")

# A single-worktree repo, and a repo with two linked worktrees — one of which is
# deleted from disk without pruning, so git keeps reporting it.
SOLO="$FIX/solo"
MAIN="$FIX/main"
LINK_A="$FIX/link-a"
GONE="$FIX/gone"
mkdir -p "$SOLO" "$MAIN"
git init -q "$SOLO" 2> /dev/null
git init -q "$MAIN" 2> /dev/null

LINKED_OK=0
if git -C "$MAIN" -c user.email=test@example.invalid -c user.name=Test \
  commit -q --allow-empty -m init > /dev/null 2>&1 \
  && git -C "$MAIN" worktree add -q "$LINK_A" -b scan-a > /dev/null 2>&1 \
  && git -C "$MAIN" worktree add -q "$GONE" -b scan-gone > /dev/null 2>&1; then
  rm -rf "$GONE" # reported by git, absent from disk
  LINKED_OK=1
fi

# A bare repo: git lists its control directory as a worktree, but that directory
# carries no .git entry, so the contract excludes it.
BARE="$FIX/bare.git"
BARE_WT="$FIX/bare-wt"
BARE_OK=0
if [ "$LINKED_OK" -eq 1 ] \
  && git init -q --bare "$BARE" > /dev/null 2>&1 \
  && git -C "$MAIN" push -q "$BARE" HEAD:refs/heads/master > /dev/null 2>&1 \
  && git -C "$BARE" worktree add -q "$BARE_WT" master > /dev/null 2>&1; then
  BARE_OK=1
fi

SOLO_REAL="$(realpath_of "$SOLO")"
MAIN_REAL="$(realpath_of "$MAIN")"
LINK_A_REAL="$(realpath_of "$LINK_A")"
BARE_REAL="$(realpath_of "$BARE")"
BARE_WT_REAL="$(realpath_of "$BARE_WT")"

HOME_REAL="$(realpath_of "$HOME")"
if [ -z "$HOME_REAL" ] || [ "$(realpath_of "$FIX")" = "$HOME_REAL" ]; then
  fail "setup: the fixture tree did not resolve under \$HOME; no scope-filtered clause could be checked"
  printf 'discovery-scan.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

# git shims, one per failure mode.
SHIM_FAIL="$WORK/shim-fail"
SHIM_GARBAGE="$WORK/shim-garbage"
SHIM_SLOW="$WORK/shim-slow"
SHIM_DUP="$WORK/shim-dup"
SHIM_NOROOT="$WORK/shim-noroot"
SHIM_PHANTOM="$WORK/shim-phantom"

make_git_shim "$SHIM_FAIL" 'echo "fatal: not a git repository" >&2' 'exit 128'
make_git_shim "$SHIM_GARBAGE" 'echo "?? this is not porcelain output ??"' 'exit 0'
make_git_shim "$SHIM_SLOW" 'exec sleep 30'
# Duplicates, with the root listed twice: the result must be unique, first
# occurrence wins.
make_git_shim "$SHIM_DUP" \
  "printf 'worktree %s\n\nworktree %s\n\nworktree %s\n\nworktree %s\n' \
   \"\$WT_MAIN\" \"\$WT_LINK\" \"\$WT_MAIN\" \"\$WT_LINK\""
# git's own output omits the directory it was run in.
make_git_shim "$SHIM_NOROOT" "printf 'worktree %s\n\n' \"\$WT_LINK\""
# A worktree git reports that does not exist on disk at all.
make_git_shim "$SHIM_PHANTOM" \
  "printf 'worktree %s\n\nworktree %s\n\n' \"\$WT_MAIN\" \"\$WT_PHANTOM\""

# =============================================================================
# worktree_siblings — Behavior and Outputs
# =============================================================================

run_py "worktree_siblings: a single-worktree repo returns exactly [root]" "$SOLO_REAL" << 'PY'
import sys
import serve
root = sys.argv[1]
got = serve.worktree_siblings(root)
assert isinstance(got, list), got
assert got == [root], got
PY

if [ "$LINKED_OK" -ne 1 ]; then
  skip "worktree_siblings: 'git worktree add' failed here, so the multi-worktree clauses are unchecked"
else
  run_py "worktree_siblings: every worktree of the repo is returned, root first" \
    "$MAIN_REAL" "$LINK_A_REAL" << 'PY'
import sys
import serve
root, link = sys.argv[1], sys.argv[2]
got = serve.worktree_siblings(root)
assert got[0] == root, got
assert link in got, got
assert len(got) == len(set(got)), got
PY

  # "root itself included, root FIRST" — asked from the linked worktree, where
  # git's own output leads with the main worktree instead.
  run_py "worktree_siblings: the requested root leads the list even when git does not list it first" \
    "$LINK_A_REAL" "$MAIN_REAL" << 'PY'
import sys
import serve
root, main = sys.argv[1], sys.argv[2]
got = serve.worktree_siblings(root)
assert got[0] == root, got
assert main in got, got
PY

  # Outputs: every returned path exists as a directory at return time, so the
  # deleted-but-still-reported worktree is dropped.
  run_py "worktree_siblings: a worktree git still reports but that is gone from disk is dropped" \
    "$MAIN_REAL" "$(realpath_of "$FIX")/gone" << 'PY'
import os
import sys
import serve
root, gone = sys.argv[1], sys.argv[2]
got = serve.worktree_siblings(root)
assert gone not in got, got
for p in got:
    assert os.path.isdir(p), (p, got)
PY

  run_py "worktree_siblings: every returned path is a realpath" "$MAIN_REAL" << 'PY'
import os
import sys
import serve
got = serve.worktree_siblings(sys.argv[1])
for p in got:
    assert p == os.path.realpath(p), (p, got)
PY
fi

if [ "$BARE_OK" -ne 1 ]; then
  skip "worktree_siblings: the bare-repo fixture could not be built, so the control-directory clause is unchecked"
else
  run_py "worktree_siblings: a listed path carrying no .git entry (a bare control dir) is excluded" \
    "$BARE_WT_REAL" "$BARE_REAL" << 'PY'
import sys
import serve
root, bare = sys.argv[1], sys.argv[2]
got = serve.worktree_siblings(root)
assert root in got, got
assert bare not in got, got
PY
fi

# =============================================================================
# worktree_siblings — Errors: no environmental failure may ever raise, and
# every one of them degrades to exactly [root]
# =============================================================================

run_py "worktree_siblings: git missing from PATH degrades to [root]" "$MAIN_REAL" << 'PY'
import os
import sys
os.environ['PATH'] = ''
import serve
root = sys.argv[1]
assert serve.worktree_siblings(root) == [root], serve.worktree_siblings(root)
PY

run_py "worktree_siblings: a nonzero git exit degrades to [root]" "$MAIN_REAL" "$SHIM_FAIL" << 'PY'
import os
import sys
os.environ['PATH'] = sys.argv[2] + os.pathsep + os.environ.get('PATH', '')
import serve
root = sys.argv[1]
assert serve.worktree_siblings(root) == [root], serve.worktree_siblings(root)
PY

run_py "worktree_siblings: unparseable git output degrades to [root]" "$MAIN_REAL" "$SHIM_GARBAGE" << 'PY'
import os
import sys
os.environ['PATH'] = sys.argv[2] + os.pathsep + os.environ.get('PATH', '')
import serve
root = sys.argv[1]
assert serve.worktree_siblings(root) == [root], serve.worktree_siblings(root)
PY

# Invariant: the subprocess ALWAYS runs with an explicit timeout, capped at 5
# seconds. A git that hangs for 30s proves both halves at once — an
# implementation with no timeout, or a generous one, blows the wall-clock bound
# instead of returning.
run_py "worktree_siblings: a hanging git is cut off by the timeout and degrades to [root]" \
  "$MAIN_REAL" "$SHIM_SLOW" << 'PY'
import os
import sys
import time
os.environ['PATH'] = sys.argv[2] + os.pathsep + os.environ.get('PATH', '')
import serve
root = sys.argv[1]
t0 = time.time()
got = serve.worktree_siblings(root)
elapsed = time.time() - t0
assert got == [root], got
assert elapsed < 15, 'took %.1fs; the contract caps the subprocess timeout at 5s' % elapsed
PY

# Invariant: no shell=True. Asserted on the source, because the observable
# difference is a shell injection nobody should have to demonstrate to prove it
# absent. Read through the parser rather than by grep: the contract docblock
# itself contains the words "no shell=True", and a textual scan would fail on
# the spec that forbids the thing.
if python3 - "$SERVE" << 'PY'
import ast
import sys
tree = ast.parse(open(sys.argv[1], encoding='utf-8').read())
bad = [n.lineno for n in ast.walk(tree) if isinstance(n, ast.Call)
       for k in n.keywords
       if k.arg == 'shell' and not (isinstance(k.value, ast.Constant) and not k.value.value)]
if bad:
    print('shell= passed truthy or non-literal at line(s): %s' % bad)
    sys.exit(1)
PY
then
  pass "worktree_siblings: no call in serve.py passes shell=True"
else
  fail "worktree_siblings: a subprocess call in serve.py uses shell=True — the contract forbids it"
fi

# =============================================================================
# worktree_siblings — Edge cases: duplicates, and a root git omits
# =============================================================================

if [ "$LINKED_OK" -ne 1 ]; then
  skip "worktree_siblings: the shim edge cases need the multi-worktree fixture, which could not be built"
else
  run_py "worktree_siblings: duplicate paths in git's output are deduplicated, first occurrence winning" \
    "$MAIN_REAL" "$SHIM_DUP" "$LINK_A_REAL" << 'PY'
import os
import sys
os.environ['PATH'] = sys.argv[2] + os.pathsep + os.environ.get('PATH', '')
os.environ['WT_MAIN'] = sys.argv[1]
os.environ['WT_LINK'] = sys.argv[3]
import serve
root, link = sys.argv[1], sys.argv[3]
got = serve.worktree_siblings(root)
assert got == [root, link], got
PY

  run_py "worktree_siblings: a root absent from git's own output is still first in the result" \
    "$MAIN_REAL" "$SHIM_NOROOT" "$LINK_A_REAL" << 'PY'
import os
import sys
os.environ['PATH'] = sys.argv[2] + os.pathsep + os.environ.get('PATH', '')
os.environ['WT_LINK'] = sys.argv[3]
import serve
root, link = sys.argv[1], sys.argv[3]
got = serve.worktree_siblings(root)
assert got[0] == root, got
assert link in got, got
assert len(got) == len(set(got)), got
PY

  run_py "worktree_siblings: a reported worktree that never existed is dropped, not returned" \
    "$MAIN_REAL" "$SHIM_PHANTOM" "$FIX/no-such-worktree" << 'PY'
import os
import sys
os.environ['PATH'] = sys.argv[2] + os.pathsep + os.environ.get('PATH', '')
os.environ['WT_MAIN'] = sys.argv[1]
os.environ['WT_PHANTOM'] = sys.argv[3]
import serve
root, phantom = sys.argv[1], sys.argv[3]
got = serve.worktree_siblings(root)
assert got == [root], got
assert phantom not in got, got
PY
fi

# =============================================================================
# discover_docs — fixtures
# =============================================================================
# One worktree carrying every shape the contract names, so a single walk has to
# get all of them right at once.

DOCS_WT="$FIX/docs-wt"
OTHER_WT="$FIX/other-wt"
mkdir -p "$DOCS_WT" "$OTHER_WT"
git init -q "$DOCS_WT" 2> /dev/null
git init -q "$OTHER_WT" 2> /dev/null

mkdir -p "$DOCS_WT/.local/reports" "$DOCS_WT/.local/briefs/nested/deeper" \
  "$DOCS_WT/.local/node_modules" "$DOCS_WT/.local/.hidden" \
  "$DOCS_WT/.local/no-docs-here" "$DOCS_WT/.local/locked" \
  "$DOCS_WT/docs" "$OTHER_WT/.local"

printf '# Top\n' > "$DOCS_WT/.local/TODO.md"
printf '# Graph\n\nFocus: none\n' > "$DOCS_WT/.local/WORKGRAPH.md"
printf '# Report\n' > "$DOCS_WT/.local/reports/01-report.md"
printf '# Brief\n' > "$DOCS_WT/.local/briefs/nested/deeper/deep.md"
printf '# Vendored\n' > "$DOCS_WT/.local/node_modules/vendored.md"
printf '# Hidden\n' > "$DOCS_WT/.local/.hidden/hidden.md"
printf '# Locked\n' > "$DOCS_WT/.local/locked/locked.md"

# Non-.md neighbours, and a rendered sibling: the .md filter must drop all three.
printf '<html></html>\n' > "$DOCS_WT/.local/TODO.html"
printf 'plain\n' > "$DOCS_WT/.local/notes.txt"
mkdir -p "$DOCS_WT/.local/directory.md" # a DIRECTORY whose name ends in .md

# Outside .local entirely: neither of these may ever be returned.
printf '# Outside\n' > "$DOCS_WT/README.md"
printf '# Outside\n' > "$DOCS_WT/docs/plan.md"
printf '# Other worktree\n' > "$OTHER_WT/.local/other.md"

# A symlinked directory (not followed), a symlink cycle (cannot hang the walk),
# a dangling symlink and a symlink out of the worktree.
OUTSIDE_DIR="$WORK/outside"
mkdir -p "$OUTSIDE_DIR"
printf '# Outside home\n' > "$OUTSIDE_DIR/outside-home.md"
ln -s "$OUTSIDE_DIR" "$DOCS_WT/.local/linked-dir"
ln -s "$DOCS_WT/.local" "$DOCS_WT/.local/loop"
ln -s "$FIX/nowhere.md" "$DOCS_WT/.local/dangling.md"
ln -s "$OUTSIDE_DIR/outside-home.md" "$DOCS_WT/.local/outside-home.md"
ln -s "$OTHER_WT/.local/other.md" "$DOCS_WT/.local/foreign.md"

# Distinct mtimes, oldest to newest, so the sort order is this file's choice
# rather than the wall clock's.
python3 - "$DOCS_WT" << 'PY'
import os
import sys
root = sys.argv[1]
order = [
    ('.local/node_modules/vendored.md', 1000),
    ('.local/.hidden/hidden.md', 2000),
    ('.local/briefs/nested/deeper/deep.md', 3000),
    ('.local/reports/01-report.md', 4000),
    ('.local/WORKGRAPH.md', 5000),
    ('.local/TODO.md', 6000),
]
for rel, t in order:
    os.utime(os.path.join(root, rel), (t, t))
PY

# Three degenerate worktrees for the Errors clauses, built here rather than
# beside their assertions so the read-only manifest below covers them too.
NO_LOCAL="$FIX/no-local"
EMPTY_LOCAL="$FIX/empty-local"
FILE_LOCAL="$FIX/file-local"
mkdir -p "$NO_LOCAL" "$EMPTY_LOCAL/.local/sub" "$FILE_LOCAL"
for d in "$NO_LOCAL" "$EMPTY_LOCAL" "$FILE_LOCAL"; do
  git init -q "$d" 2> /dev/null
done
printf 'not markdown\n' > "$EMPTY_LOCAL/.local/sub/notes.txt"
printf 'this is a file, not a directory\n' > "$FILE_LOCAL/.local"

DOCS_WT_REAL="$(realpath_of "$DOCS_WT")"
MANIFEST_BEFORE="$(manifest)"

# =============================================================================
# discover_docs — Behavior, Outputs, Invariants
# =============================================================================

run_py "discover_docs: every .local/**/*.md is returned, at any depth" "$DOCS_WT_REAL" << 'PY'
import os
import sys
import serve
root = sys.argv[1]
got = serve.discover_docs(root)
paths = [e['path'] for e in got]
for rel in ('.local/TODO.md', '.local/WORKGRAPH.md', '.local/reports/01-report.md',
            '.local/briefs/nested/deeper/deep.md', '.local/node_modules/vendored.md',
            '.local/.hidden/hidden.md'):
    assert os.path.join(root, rel) in paths, (rel, paths)
PY

run_py "discover_docs: each entry is {'path': <realpath>, 'mtime': <epoch number>}" "$DOCS_WT_REAL" << 'PY'
import os
import sys
import serve
got = serve.discover_docs(sys.argv[1])
assert got, 'nothing discovered, so the entry shape cannot be checked'
for e in got:
    assert isinstance(e, dict), e
    assert sorted(e.keys()) == ['mtime', 'path'], e
    assert isinstance(e['path'], str) and e['path'].startswith('/'), e
    assert e['path'] == os.path.realpath(e['path']), e
    assert isinstance(e['mtime'], (int, float)) and not isinstance(e['mtime'], bool), e
    assert abs(e['mtime'] - os.stat(e['path']).st_mtime) < 1, e
PY

run_py "discover_docs: entries are sorted by mtime, newest first" "$DOCS_WT_REAL" << 'PY'
import os
import sys
import serve
root = sys.argv[1]
got = serve.discover_docs(root)
times = [e['mtime'] for e in got]
assert times == sorted(times, reverse=True), times
expected_head = [os.path.join(root, r) for r in (
    '.local/TODO.md', '.local/WORKGRAPH.md', '.local/reports/01-report.md',
    '.local/briefs/nested/deeper/deep.md', '.local/.hidden/hidden.md',
    '.local/node_modules/vendored.md')]
assert [e['path'] for e in got if e['path'] in expected_head] == expected_head, [e['path'] for e in got]
PY

run_py "discover_docs: no directory name below .local is treated specially" "$DOCS_WT_REAL" << 'PY'
import os
import sys
import serve
root = sys.argv[1]
paths = [e['path'] for e in serve.discover_docs(root)]
# A vendored-looking directory, a dotted one and a deeply nested one all count.
for rel in ('.local/node_modules/vendored.md', '.local/.hidden/hidden.md',
            '.local/briefs/nested/deeper/deep.md'):
    assert os.path.join(root, rel) in paths, (rel, paths)
PY

run_py "discover_docs: non-.md files and a directory named *.md are excluded" "$DOCS_WT_REAL" << 'PY'
import os
import sys
import serve
root = sys.argv[1]
paths = [e['path'] for e in serve.discover_docs(root)]
for rel in ('.local/TODO.html', '.local/notes.txt', '.local/directory.md'):
    assert os.path.join(root, rel) not in paths, (rel, paths)
PY

run_py "discover_docs: nothing outside root/.local is ever returned" "$DOCS_WT_REAL" << 'PY'
import os
import sys
import serve
root = sys.argv[1]
local = os.path.join(root, '.local') + os.sep
for e in serve.discover_docs(root):
    assert e['path'].startswith(local), (e, local)
PY

# The same invariant, forced: symlinks inside .local that resolve elsewhere. The
# scope rules are what stop the out-of-home one; the containment invariant is
# what stops the one pointing at an in-scope document in another worktree.
run_py "discover_docs: a symlink resolving outside root/.local does not smuggle a document in" \
  "$DOCS_WT_REAL" "$(realpath_of "$OTHER_WT")" << 'PY'
import os
import sys
import serve
root, other = sys.argv[1], sys.argv[2]
paths = [e['path'] for e in serve.discover_docs(root)]
assert os.path.join(other, '.local/other.md') not in paths, paths
assert not any('outside-home.md' in p for p in paths), paths
assert not any(p.startswith(other + os.sep) for p in paths), paths
PY

run_py "discover_docs: documents elsewhere in the worktree are not discovered" "$DOCS_WT_REAL" << 'PY'
import os
import sys
import serve
root = sys.argv[1]
paths = [e['path'] for e in serve.discover_docs(root)]
for rel in ('README.md', 'docs/plan.md'):
    assert os.path.join(root, rel) not in paths, (rel, paths)
PY

# Only paths passing scope_error are included — the same rules every serve route
# enforces. A dangling symlink is the cheapest one to force: it ends in .md but
# is not an existing file.
run_py "discover_docs: entries that fail scope_error are excluded" "$DOCS_WT_REAL" << 'PY'
import os
import sys
import serve
root = sys.argv[1]
for e in serve.discover_docs(root):
    assert serve.scope_error(e['path']) is None, e
paths = [e['path'] for e in serve.discover_docs(root)]
assert os.path.join(root, '.local/dangling.md') not in paths, paths
PY

# Invariant: only names and stat results are examined; CONTENTS are never read.
# A mode-000 document is stat-able and unreadable, so an implementation that
# opens what it finds drops it (or raises) and this reddens.
if [ "$(id -u)" -eq 0 ]; then
  skip "discover_docs: running as root, so a mode-000 document would still be readable"
else
  chmod 000 "$DOCS_WT/.local/locked/locked.md"
  run_py "discover_docs: an unreadable document is still discovered (contents are never read)" \
    "$DOCS_WT_REAL" << 'PY'
import os
import sys
import serve
root = sys.argv[1]
paths = [e['path'] for e in serve.discover_docs(root)]
assert os.path.join(root, '.local/locked/locked.md') in paths, paths
PY
  chmod 644 "$DOCS_WT/.local/locked/locked.md"
fi

# =============================================================================
# discover_docs — Errors: nothing here may raise, ever
# =============================================================================

run_py "discover_docs: a worktree with no .local returns []" "$(realpath_of "$NO_LOCAL")" << 'PY'
import sys
import serve
got = serve.discover_docs(sys.argv[1])
assert got == [], got
PY

run_py "discover_docs: a .local with no .md files returns []" "$(realpath_of "$EMPTY_LOCAL")" << 'PY'
import sys
import serve
got = serve.discover_docs(sys.argv[1])
assert got == [], got
PY

run_py "discover_docs: a .local that is a file rather than a directory returns []" \
  "$(realpath_of "$FILE_LOCAL")" << 'PY'
import sys
import serve
got = serve.discover_docs(sys.argv[1])
assert got == [], got
PY

run_py "discover_docs: a root that does not exist at all returns [] rather than raising" \
  "$FIX/never-created" << 'PY'
import sys
import serve
got = serve.discover_docs(sys.argv[1])
assert got == [], got
PY

# The walk does not follow symlinked directories, so neither the out-of-tree
# link nor the cycle back into .local can hang it or widen its reach. The
# wall-clock bound is the anti-hang half of the clause.
run_py "discover_docs: symlinked directories are not followed, so a cycle cannot hang the walk" \
  "$DOCS_WT_REAL" << 'PY'
import sys
import time
import serve
root = sys.argv[1]
t0 = time.time()
got = serve.discover_docs(root)
elapsed = time.time() - t0
assert elapsed < 20, 'the walk took %.1fs — a symlink cycle was followed' % elapsed
assert not any('linked-dir' in e['path'] for e in got), got
assert not any('/loop/' in e['path'] for e in got), got
PY

if [ "$(id -u)" -eq 0 ]; then
  skip "discover_docs: running as root, so a mode-000 directory would still be readable"
else
  chmod 000 "$DOCS_WT/.local/locked"
  run_py "discover_docs: an unreadable directory is skipped silently, the rest still returned" \
    "$DOCS_WT_REAL" << 'PY'
import os
import sys
import serve
root = sys.argv[1]
got = serve.discover_docs(root)
paths = [e['path'] for e in got]
assert os.path.join(root, '.local/TODO.md') in paths, paths
assert os.path.join(root, '.local/reports/01-report.md') in paths, paths
PY
  chmod 755 "$DOCS_WT/.local/locked"
fi

# =============================================================================
# Invariant: both functions are read-only
# =============================================================================

# Not an assertion — one last call of each function, so the manifest below is
# compared against a tree both of them have just walked. A stub that raises is
# swallowed on purpose: the clauses that care about raising are above.
PYTHONPATH="$SCRIPT_DIR" RENDER_DOC_PORT="$PY_PORT" PYTHONDONTWRITEBYTECODE=1 \
  python3 - "$DOCS_WT_REAL" > /dev/null 2>&1 << 'PY'
import sys
import serve
root = sys.argv[1]
for fn in (serve.worktree_siblings, serve.discover_docs):
    try:
        fn(root)
    except Exception:
        pass
PY

if [ "$(manifest)" = "$MANIFEST_BEFORE" ]; then
  pass "read-only: scanning changed no fixture file (contents and mtimes identical)"
else
  fail "read-only: the fixture tree changed while scanning: $(diff <(printf '%s' "$MANIFEST_BEFORE") <(manifest) | head -5)"
fi

REG_PY="/tmp/render-doc-registry-$PY_PORT.json"
if [ -e "$REG_PY" ]; then
  fail "read-only: scanning created a registry file at $REG_PY — discovery must not touch registry state"
else
  pass "read-only: scanning touched no registry state"
fi

# =============================================================================
# Left to acceptance review
# =============================================================================
# Two judgement calls stay with the orchestrator. First, whether the timeout is
# the contract's 5 seconds exactly rather than merely "short enough" — the
# hanging-git check bounds it at 15s of wall clock, which is what a test can see
# from outside without reading the call. Second, whether `git worktree list
# --porcelain` is the command actually used: every clause here is stated in
# terms of the RESULT, so a faithful implementation reaching the same list
# another way passes, and the contract's naming of the command is verified by
# reading the diff.

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'discovery-scan.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'discovery-scan.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'discovery-scan.test.sh: all assertions passed\n'
