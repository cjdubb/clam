#!/usr/bin/env bash
# index-discovery.test.sh — verifies the docblock "Contract: 002-B02 index
# discovery integration" on index_doc_entries() in
# plugins/render-doc/scripts/serve.py, and the changes it makes to GET /.
#
# Until this block lands, the index can only show what somebody already opened.
# Afterwards it shows what EXISTS: for every worktree root the registry knows
# about, every sibling worktree of that root, and every .local markdown document
# in each of them — served or not. So the assertions come in two layers:
#
#   1. index_doc_entries() called directly (imported through PYTHONPATH, the
#      discovery-scan.test.sh idiom), because the merge rules — served entries
#      untouched and first, unserved joining with lastServed None and an mtime,
#      each path exactly once, degradation to registry-only — are statements
#      about a list, and reading them back out of HTML would prove less.
#   2. GET / over HTTP, because the rest of the clause is about what a reader
#      SEES: unserved entries after served ones in their group, listed exactly
#      as the served ones are (003-B15 removed the visible marker, so position
#      is the whole distinction), and groups appearing for worktrees that never
#      served anything.
#
# The fixture is one repo with three worktrees plus two standalone repos, and
# one repo that is deliberately unreachable from the registry — discovery is
# anchored on registered roots, not a filesystem sweep, and an unregistered,
# unrelated repo showing up would be a bug this suite has to catch. The
# registry is SEEDED through /tmp/render-doc-registry-<port>.json, so every
# ordering assertion rests on last-served times this file chose.
#
# Reading the page follows server-index.test.sh exactly: assertions about what
# a reader sees run over a tag-stripped slice of the group, assertions about
# where a link points run over the raw slice, and no worktree name is a prefix
# of another so a group slice can never bleed into its neighbour.
#
# Marker note: plan-002 contract markers are plan-qualified ("Contract:
# 002-B02"). serve.py also carries a permanent, unrelated "Contract: B02"
# docblock from an earlier plan, so nothing here greps the bare form.
#
# Out of scope, because another suite owns it: the scan functions themselves
# (discovery-scan.test.sh), the registry (server-registry.test.sh), and the
# index page's registry-only behaviour — grouping, labels, headline parsing,
# escaping, empty state, Content-Type and Content-Length (server-index.test.sh).
# Only what this block CHANGES about the page is asserted here.

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVE="$SCRIPT_DIR/serve.py"

WORK="$(mktemp -d)"
HEADERS="$WORK/resp.headers"
BODY="$WORK/resp.body"

SERVER_PIDS=()
TMP_ARTEFACTS=()
HOME_DIRS=()

cleanup() {
  for p in ${SERVER_PIDS[@]+"${SERVER_PIDS[@]}"}; do
    [ -n "$p" ] && kill "$p" 2> /dev/null
  done
  sleep 0.2
  for p in ${SERVER_PIDS[@]+"${SERVER_PIDS[@]}"}; do
    [ -n "$p" ] && kill -9 "$p" 2> /dev/null
  done
  for f in ${TMP_ARTEFACTS[@]+"${TMP_ARTEFACTS[@]}"}; do
    [ -n "$f" ] && rm -rf "$f"
  done
  # chmod first: one fixture .local is deliberately mode 000.
  for d in ${HOME_DIRS[@]+"${HOME_DIRS[@]}"}; do
    [ -n "$d" ] && chmod -R u+rwX "$d" 2> /dev/null
    [ -n "$d" ] && rm -rf "$d"
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
for tool in python3 curl git; do
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
  printf 'index-discovery.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
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

realpath_of() {
  python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$1" 2> /dev/null
}

enc() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$1"
}

# python3 is invoked by its resolved path, so a server started with a sabotaged
# PATH (the broken-git case below) still finds its own interpreter.
PY_BIN="$(command -v python3)"

start_server() { # <port> <stderr file> [extra PATH prefix]
  env RENDER_DOC_PORT="$1" PATH="${3:+$3:}$PATH" \
    "$PY_BIN" "$SERVE" > "$2.stdout" 2> "$2" &
  SERVER_PIDS+=("$!")
  TMP_ARTEFACTS+=("/tmp/render-doc-serve-$1.pid" "/tmp/render-doc-registry-$1.json")
}

wait_healthy() { # <base url>
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if curl -sf --max-time 1 "$1/health" > /dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

RESP_CODE=""
do_request() { # <curl args...>
  : > "$HEADERS"
  : > "$BODY"
  RESP_CODE="$(curl -s --max-time 20 -D "$HEADERS" -o "$BODY" \
    -w '%{http_code}' "$@" 2> /dev/null)"
  RESP_CODE="${RESP_CODE:-000}"
}

expect_code() { # <label> <expected> <curl args...>
  local label="$1" expected="$2"
  shift 2
  do_request "$@"
  if [ "$RESP_CODE" = "$expected" ]; then
    pass "$label ($expected)"
  else
    fail "$label: expected $expected, got $RESP_CODE"
  fi
}

write_seed() { # <file> [<path> <epoch>]...
  local f="$1"
  shift
  python3 - "$f" "$@" << 'PY'
import json
import sys
out = {}
args = sys.argv[2:]
for i in range(0, len(args), 2):
    out[args[i]] = float(args[i + 1])
with open(sys.argv[1], 'w') as fh:
    json.dump(out, fh)
PY
}

# run_py <label> [args...] — the python snippet arrives on stdin. Any exception
# (including an unimplemented stub's NotImplementedError) is a fail carrying the
# tail of the traceback, so a red says WHY.
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

# Character index of <needle> in the last response body, or -1.
pos_of() { # <needle>
  python3 - "$BODY" "$1" << 'PY' 2> /dev/null
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
print(data.find(sys.argv[2]))
PY
}

body_has() { # <literal string>
  [ "$(pos_of "$1")" != "-1" ]
}

page_ok() {
  [ "$RESP_CODE" = "200" ] && [ -s "$BODY" ]
}

# Group labels, filled once the fixtures exist. A group's slice runs from its
# own label to whichever OTHER group label comes next. No fixture worktree name
# is a prefix of another, so a slice can never start inside a neighbour's label.
GROUP_LABELS=()

group_slice() { # <label>
  python3 - "$BODY" "$1" ${GROUP_LABELS[@]+"${GROUP_LABELS[@]}"} << 'PY' 2> /dev/null
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
label, labels = sys.argv[2], sys.argv[3:]
i = data.find(label)
if i < 0:
    sys.exit(1)
end = len(data)
for other in labels:
    if other == label:
        continue
    j = data.find(other, i + len(label))
    if j >= 0:
        end = min(end, j)
sys.stdout.write(data[i:end])
PY
}

# The same slice as a reader sees it: tags removed, entities decoded, runs of
# whitespace collapsed.
group_text() { # <label>
  group_slice "$1" | python3 -c "
import html, re, sys
data = sys.stdin.read()
data = re.sub(r'<[^>]*>', ' ', data)
print(re.sub(r'\s+', ' ', html.unescape(data)))
" 2> /dev/null
}

group_hrefs() { # <label>
  group_slice "$1" | grep -oE 'href="[^"]*"' | sed 's/^href="//; s/"$//'
}

group_has_link_to() { # <label> <absolute md path>
  local want
  want="/doc$(enc "$2")"
  group_hrefs "$1" | grep -qxF -- "$want"
}

# Case-insensitive occurrences of a literal in the RAW body — markup and the
# inline stylesheet alike. The visible-text helpers below cannot see a CSS class
# name or a rule in <style>, and 003-B15 bans the marker from both.
raw_count_ci() { # <needle>
  python3 - "$BODY" "$1" << 'PY' 2> /dev/null
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
print(data.lower().count(sys.argv[2].lower()))
PY
}

# The <li> element carrying the /doc link for one document. Entry elements are
# never nested, so the non-greedy match is exact.
li_for() { # <absolute md path>
  python3 - "$BODY" "/doc$(enc "$1")" << 'PY' 2> /dev/null
import re
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
want = 'href="%s"' % sys.argv[2]
for m in re.finditer(r'<li\b.*?</li>', data, re.S | re.I):
    if want in m.group(0):
        sys.stdout.write(m.group(0))
        break
PY
}

# The same element with the two things that legitimately differ between any two
# entries — the link target and the link text — replaced by placeholders. What
# survives is the markup shape, which 003-B15 requires to be the SAME for a
# served and a never-served entry. Comparing shapes rather than asserting one
# literal shape keeps a faithful rewrite of the markup from failing this.
li_shape() { # <li html>
  python3 -c '
import re
import sys
li = sys.argv[1]
li = re.sub(r"href=\"[^\"]*\"", "href=\"HREF\"", li)
li = re.sub(r"(<a\b[^>]*>).*?(</a>)", r"\1TEXT\2", li, flags=re.S)
sys.stdout.write(li)
' "$1" 2> /dev/null
}

# Byte offset of <needle> within a group's VISIBLE text, or -1. Every ordering
# and marking clause below is expressed with these, so no assertion depends on
# the markup that carries the facts.
text_pos() { # <group text> <needle>
  python3 -c "import sys; sys.stdout.write(str(sys.argv[1].lower().find(sys.argv[2].lower())))" \
    "$1" "$2" 2> /dev/null
}

text_count() { # <group text> <needle>
  python3 -c "import sys; sys.stdout.write(str(sys.argv[1].lower().count(sys.argv[2].lower())))" \
    "$1" "$2" 2> /dev/null
}

# A visible-text window that cannot be spanned by a path: / . and ~ are
# excluded, so a digit from a group label can never satisfy a count clause.
WIN='[^0-9/.~]{0,40}'

text_matches() { # <text> <ere>
  printf '%s' "$1" | grep -Eqi -- "$2"
}

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
}

# --- Fixtures ----------------------------------------------------------------
# One repo with three worktrees (two of them registered, one never served), two
# standalone registered repos, and one repo the registry has never heard of.
FIX="$(mktemp -d "$HOME/.render-doc-idxtest.XXXXXX")"
HOME_DIRS+=("$FIX")

WT_MAIN="$FIX/wt-main"       # registered; mixed served + unserved docs
WT_SIBLING="$FIX/wt-sibling" # NEVER served: reachable only as a sibling
WT_SECOND="$FIX/wt-second"   # a second registered worktree of the same repo
REPO_BETA="$FIX/repo-beta"   # standalone, mixed
REPO_DELTA="$FIX/repo-delta" # standalone, everything it has is served
REPO_GAMMA="$FIX/repo-gamma" # standalone, unregistered, unrelated: must not appear

for d in "$WT_MAIN" "$REPO_BETA" "$REPO_DELTA" "$REPO_GAMMA"; do
  mkdir -p "$d"
  git init -q "$d" 2> /dev/null
done

LINKED_OK=0
if git -C "$WT_MAIN" -c user.email=test@example.invalid -c user.name=Test \
  commit -q --allow-empty -m init > /dev/null 2>&1 \
  && git -C "$WT_MAIN" worktree add -q "$WT_SIBLING" -b idx-sibling > /dev/null 2>&1 \
  && git -C "$WT_MAIN" worktree add -q "$WT_SECOND" -b idx-second > /dev/null 2>&1; then
  LINKED_OK=1
fi

mkdir -p "$WT_MAIN/.local/reports" "$WT_MAIN/.local/briefs" \
  "$REPO_BETA/.local" "$REPO_DELTA/.local" "$REPO_GAMMA/.local"

printf '# Plan\n' > "$WT_MAIN/.local/PLAN.md"
printf '# Report\n' > "$WT_MAIN/.local/reports/r1.md"
printf '# Brief\n' > "$WT_MAIN/.local/briefs/b1.md"
# Registered but NOT under .local: a registry entry discovery never sees must
# still be listed, exactly as it is today.
printf '# Notes\n' > "$WT_MAIN/notes.md"

printf '# Design\n' > "$REPO_BETA/.local/DESIGN.md"
printf '# Extra\n' > "$REPO_BETA/.local/EXTRA.md"
printf '# Delta\n' > "$REPO_DELTA/.local/DELTA.md"
printf '# Gamma\n' > "$REPO_GAMMA/.local/GAMMA.md"

if [ "$LINKED_OK" -eq 1 ]; then
  mkdir -p "$WT_SIBLING/.local" "$WT_SECOND/.local"
  # Three open nodes and a Focus, so the never-served group has a headline to
  # render exactly like a served one.
  cat > "$WT_SIBLING/.local/WORKGRAPH.md" << 'MD'
# Work Graph

Focus: N02

## N01 — first
- Status: open

## N02 — second
- Status: open

## N03 — third
- Status: open

## N04 — finished
- Status: done
MD
  printf '# Notes\n' > "$WT_SIBLING/.local/NOTES.md"
  printf '# Tasks\n' > "$WT_SIBLING/.local/TASKS.md"
  printf '# Registered\n' > "$WT_SECOND/.local/REG.md"
fi

# Distinct mtimes so the unserved sort order is this file's choice.
python3 - "$FIX" << 'PY'
import os
import sys
fix = sys.argv[1]
stamps = {
    'wt-main/.local/reports/r1.md': 7000,
    'wt-main/.local/briefs/b1.md': 6000,
    'wt-sibling/.local/WORKGRAPH.md': 9000,
    'wt-sibling/.local/NOTES.md': 8500,
    'wt-sibling/.local/TASKS.md': 8000,
    'repo-beta/.local/EXTRA.md': 5500,
}
for rel, t in stamps.items():
    p = os.path.join(fix, rel)
    if os.path.exists(p):
        os.utime(p, (t, t))
PY

MAIN_PLAN="$(realpath_of "$WT_MAIN/.local/PLAN.md")"
MAIN_NOTES="$(realpath_of "$WT_MAIN/notes.md")"
MAIN_R1="$(realpath_of "$WT_MAIN/.local/reports/r1.md")"
MAIN_B1="$(realpath_of "$WT_MAIN/.local/briefs/b1.md")"
BETA_DESIGN="$(realpath_of "$REPO_BETA/.local/DESIGN.md")"
BETA_EXTRA="$(realpath_of "$REPO_BETA/.local/EXTRA.md")"
DELTA_DOC="$(realpath_of "$REPO_DELTA/.local/DELTA.md")"
GAMMA_DOC="$(realpath_of "$REPO_GAMMA/.local/GAMMA.md")"
SIBLING_WG="$(realpath_of "$WT_SIBLING/.local/WORKGRAPH.md")"
SIBLING_NOTES="$(realpath_of "$WT_SIBLING/.local/NOTES.md")"
SIBLING_TASKS="$(realpath_of "$WT_SIBLING/.local/TASKS.md")"
SECOND_REG="$(realpath_of "$WT_SECOND/.local/REG.md")"

HOME_REAL="$(realpath_of "$HOME")"
label_for() { # <worktree dir> -> the ~-abbreviated label the page must show
  local real
  real="$(realpath_of "$1")"
  printf '~%s' "${real#"$HOME_REAL"}"
}

L_MAIN="$(label_for "$WT_MAIN")"
L_SIBLING="$(label_for "$WT_SIBLING")"
L_SECOND="$(label_for "$WT_SECOND")"
L_BETA="$(label_for "$REPO_BETA")"
L_DELTA="$(label_for "$REPO_DELTA")"
L_GAMMA="$(label_for "$REPO_GAMMA")"

GROUP_LABELS=("$L_MAIN" "$L_BETA" "$L_DELTA")
if [ "$LINKED_OK" -eq 1 ]; then
  GROUP_LABELS+=("$L_SIBLING" "$L_SECOND")
fi

if [ "$HOME_REAL" = "$(realpath_of "$FIX")" ] || [ "$L_MAIN" = "~" ]; then
  fail "setup: the fixture labels did not resolve under \$HOME; no grouping clause can be checked"
  printf 'index-discovery.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
if [ "$LINKED_OK" -ne 1 ]; then
  skip "sibling discovery: 'git worktree add' failed here, so every sibling-worktree clause is unchecked"
fi

# The seed every layer of this suite reads. Times descend in the order the
# groups must appear: wt-main, wt-second, repo-beta, repo-delta.
SEED_ARGS=(
  "$MAIN_PLAN" 5000
  "$MAIN_NOTES" 4000
  "$BETA_DESIGN" 3000
  "$DELTA_DOC" 2000
)
[ "$LINKED_OK" -eq 1 ] && SEED_ARGS+=("$SECOND_REG" 3500)

PY_PORT="$(free_port)"
REG_PY="/tmp/render-doc-registry-$PY_PORT.json"
TMP_ARTEFACTS+=("$REG_PY")
if [ -e "$REG_PY" ]; then
  fail "test port $PY_PORT already has a registry file at $REG_PY; aborting to avoid clobbering it"
  printf 'index-discovery.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
write_seed "$REG_PY" "${SEED_ARGS[@]}"

MANIFEST_BEFORE="$(manifest)"

# =============================================================================
# index_doc_entries() — Behavior 1 and 3, Outputs: the registry comes first,
# untouched and in its own order; discovery joins behind it
# =============================================================================

run_py "index_doc_entries: served entries come first, in registry_entries() order" << 'PY'
import serve
got = serve.index_doc_entries()
assert isinstance(got, list), got
served = [e for e in got if e.get('lastServed') is not None]
assert [e['path'] for e in served] == [e['path'] for e in serve.registry_entries()], \
    [e['path'] for e in served]
assert [e['path'] for e in got[:len(served)]] == [e['path'] for e in served], \
    'a served entry does not precede every unserved one: %s' % [e['path'] for e in got]
PY

run_py "index_doc_entries: a discovered path that is already registered keeps its registry entry" \
  "$MAIN_PLAN" "$BETA_DESIGN" << 'PY'
import sys
import serve
got = {e['path']: e for e in serve.index_doc_entries()}
for path, when in ((sys.argv[1], 5000.0), (sys.argv[2], 3000.0)):
    e = got.get(path)
    assert e is not None, (path, sorted(got))
    assert e['lastServed'] == when, e
PY

run_py "index_doc_entries: a registered document outside .local survives the merge" "$MAIN_NOTES" << 'PY'
import sys
import serve
got = {e['path']: e for e in serve.index_doc_entries()}
e = got.get(sys.argv[1])
assert e is not None, sorted(got)
assert e['lastServed'] == 4000.0, e
PY

run_py "index_doc_entries: an unserved entry is {'path', 'lastServed': None, 'mtime': <epoch>}" \
  "$MAIN_R1" << 'PY'
import os
import sys
import serve
got = {e['path']: e for e in serve.index_doc_entries()}
e = got.get(sys.argv[1])
assert e is not None, sorted(got)
assert sorted(e.keys()) == ['lastServed', 'mtime', 'path'], e
assert e['lastServed'] is None, e
assert isinstance(e['mtime'], (int, float)) and not isinstance(e['mtime'], bool), e
assert abs(e['mtime'] - os.stat(e['path']).st_mtime) < 1, e
PY

run_py "index_doc_entries: unserved entries follow the served ones, sorted by mtime descending" << 'PY'
import serve
got = serve.index_doc_entries()
unserved = [e for e in got if e.get('lastServed') is None]
assert unserved, 'nothing was discovered, so the ordering clause cannot be checked'
times = [e['mtime'] for e in unserved]
assert times == sorted(times, reverse=True), times
first_unserved = next(i for i, e in enumerate(got) if e.get('lastServed') is None)
assert all(e.get('lastServed') is None for e in got[first_unserved:]), \
    'a served entry appears after an unserved one: %s' % [(e['path'], e.get('lastServed')) for e in got]
PY

run_py "index_doc_entries: each path appears exactly once" << 'PY'
import serve
paths = [e['path'] for e in serve.index_doc_entries()]
assert len(paths) == len(set(paths)), sorted(paths)
PY

# =============================================================================
# index_doc_entries() — Behavior 2: every sibling worktree of every registered
# root is scanned, and nothing else is
# =============================================================================

if [ "$LINKED_OK" -ne 1 ]; then
  skip "index_doc_entries: the sibling-enumeration clause needs the multi-worktree fixture"
else
  run_py "index_doc_entries: documents in a sibling worktree that never served anything are discovered" \
    "$SIBLING_WG" "$SIBLING_NOTES" "$SIBLING_TASKS" << 'PY'
import sys
import serve
got = {e['path']: e for e in serve.index_doc_entries()}
for path in sys.argv[1:]:
    e = got.get(path)
    assert e is not None, (path, sorted(got))
    assert e['lastServed'] is None, e
PY

  run_py "index_doc_entries: one repo reached through two registered worktrees yields each path once" \
    "$SIBLING_NOTES" << 'PY'
import sys
import serve
paths = [e['path'] for e in serve.index_doc_entries()]
assert paths.count(sys.argv[1]) == 1, paths
assert len(paths) == len(set(paths)), sorted(paths)
PY
fi

run_py "index_doc_entries: an unregistered, unrelated repo is never discovered" "$GAMMA_DOC" << 'PY'
import sys
import serve
paths = [e['path'] for e in serve.index_doc_entries()]
assert sys.argv[1] not in paths, paths
PY

run_py "index_doc_entries: every .local document of a registered root is discovered" \
  "$MAIN_R1" "$MAIN_B1" "$BETA_EXTRA" << 'PY'
import sys
import serve
paths = [e['path'] for e in serve.index_doc_entries()]
for path in sys.argv[1:]:
    assert path in paths, (path, paths)
PY

# =============================================================================
# index_doc_entries() — Errors: NEVER raises; any discovery failure degrades to
# exactly the registry-only entries
# =============================================================================

run_py "index_doc_entries: a raising worktree_siblings degrades to the registry-only entries" << 'PY'
import serve


def boom(*_args, **_kwargs):
    raise RuntimeError('sibling enumeration exploded')


serve.worktree_siblings = boom
got = serve.index_doc_entries()
assert got == serve.registry_entries(), got
PY

run_py "index_doc_entries: a raising discover_docs degrades to the registry-only entries" << 'PY'
import serve


def boom(*_args, **_kwargs):
    raise RuntimeError('discovery exploded')


serve.discover_docs = boom
got = serve.index_doc_entries()
assert got == serve.registry_entries(), got
PY

# A port with no registry file at all: no registered root, so nothing to reach
# discovery through, so the existing empty state stands.
PY_PORT_SEEDED="$PY_PORT"
PY_PORT="$(free_port)"
TMP_ARTEFACTS+=("/tmp/render-doc-registry-$PY_PORT.json")
run_py "index_doc_entries: an empty registry with nothing discoverable is an empty list" << 'PY'
import serve
assert serve.registry_entries() == [], 'the fixture port is not actually empty'
got = serve.index_doc_entries()
assert got == [], got
PY
PY_PORT="$PY_PORT_SEEDED"

# =============================================================================
# Invariant: discovery never modifies registry state
# =============================================================================

REG_BEFORE="$(cat "$REG_PY" 2> /dev/null)"
run_py "index_doc_entries: the call leaves the in-memory registry untouched" << 'PY'
import serve
before = [(e['path'], e['lastServed']) for e in serve.registry_entries()]
serve.index_doc_entries()
after = [(e['path'], e['lastServed']) for e in serve.registry_entries()]
assert before == after, (before, after)
PY
if [ "$REG_BEFORE" = "$(cat "$REG_PY" 2> /dev/null)" ]; then
  pass "index_doc_entries: the persisted registry file is byte-unchanged by a call"
else
  fail "index_doc_entries: the registry file changed during discovery: $(cat "$REG_PY" 2> /dev/null)"
fi

# =============================================================================
# GET / — what a reader sees. From here on the assertions run against a live
# server whose registry carries the same seed.
# =============================================================================

PORT_A="$(free_port)"
BASE_A="http://127.0.0.1:$PORT_A"
REG_A="/tmp/render-doc-registry-$PORT_A.json"
if [ -e "$REG_A" ]; then
  fail "test port $PORT_A already has a registry file at $REG_A; aborting to avoid clobbering it"
  printf 'index-discovery.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
write_seed "$REG_A" "${SEED_ARGS[@]}"
start_server "$PORT_A" "$WORK/srv-a.stderr"
if wait_healthy "$BASE_A"; then
  pass "server: healthy on test port $PORT_A"
else
  fail "server: did not become healthy on test port $PORT_A — no page clause can be checked"
  printf 'index-discovery.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

do_request "$BASE_A/"
if [ "$RESP_CODE" = "200" ]; then
  pass "GET /: the index is served with discovery merged in (200)"
else
  fail "GET /: expected 200, got $RESP_CODE"
fi

# Every discovered document reaches the page as a live /doc link, alongside the
# registered ones.
for p in "$MAIN_R1" "$MAIN_B1" "$BETA_EXTRA"; do
  if body_has "\"/doc$(enc "$p")\""; then
    pass "GET /: the never-served document $(basename "$p") is listed with a /doc link"
  else
    fail "GET /: no /doc link for the discovered document $p"
  fi
done
for p in "$MAIN_PLAN" "$MAIN_NOTES" "$BETA_DESIGN" "$DELTA_DOC"; do
  if body_has "\"/doc$(enc "$p")\""; then
    pass "GET /: the registered document $(basename "$p") is still listed"
  else
    fail "GET /: the registered document $p was lost from the page"
  fi
done

if ! page_ok; then
  fail "GET /: the unrelated-repo clause could not be checked (no page was returned)"
elif body_has "$L_GAMMA" || body_has "GAMMA.md"; then
  fail "GET /: a repo the registry never heard of was discovered and listed"
else
  pass "GET /: an unregistered, unrelated repo does not appear on the page"
fi

# Contract: 003-B15 unserved marker removed (plan 003-followup-fixes)
#
# The visible marker is gone: a never-served document is listed IDENTICALLY to a
# served one and distinguished only by where it sits. Two consequences shape the
# assertions below.
#
# Absence is asserted over the RAW body, never the visible text. The mark was a
# <span class="unserved">(unserved)</span> and the page's inline stylesheet
# carried a matching .unserved rule; a tag-stripped slice sees neither the class
# attribute nor the stylesheet, so a check that only read visible text would go
# green on a page still shipping the CSS.
#
# Every clause that used to LOCATE the never-served entries by their mark is
# re-anchored on the fixture paths this file chose the mtimes for — wt-main's
# r1.md (stamped 7000) and b1.md (6000) are never served, PLAN.md (seeded 5000)
# and notes.md (4000) are. The ordering clause itself is UNCHANGED by this
# block; what changed is that it is now the only thing carrying the distinction,
# which is why it is asserted as an exact sequence rather than pairwise.

# --- The marker is gone from the markup and from the styles ------------------

n_marker="$(raw_count_ci "unserved")"
if [ "${n_marker:-0}" = "0" ]; then
  pass "marker: no \"unserved\" text, marker or CSS class anywhere in the index page"
else
  fail "marker: the index page carries \"unserved\" $n_marker time(s) — its markup or its stylesheet still marks never-served documents"
fi

if body_has 'class="unserved"'; then
  fail "marker: an entry still carries the unserved CSS class"
else
  pass "marker: no entry carries an unserved CSS class"
fi

# The block's other half is prose: the docblock clauses in serve.py that promise
# a visible mark are rewritten to promise the position-only distinction instead.
# Four of them do today, in index_doc_entries (this suite's own subject),
# render_project_entry, the 002-B04 landing-page contract and the render_group
# entry markup — so the scan is file-wide rather than a list of four line
# numbers that would go stale the moment one moves.
#
# It runs against a copy with the plan-003 contract comments removed: those
# comments quote the promise in order to retire it, and they stay in the file
# until acceptance. Without the strip this check could only ever be red during
# implementation and green afterwards for the wrong reason.
SERVE_STRIPPED="$WORK/serve.stripped.py"
python3 - "$SERVE" << 'PY' > "$SERVE_STRIPPED" 2> /dev/null
import re
import sys

out = []
skipping = False
with open(sys.argv[1], encoding='utf-8') as fh:
    for line in fh:
        if re.match(r'\s*#\s*Contract:\s*003-B[0-9]+', line):
            skipping = True
            continue
        if skipping:
            if re.match(r'\s*#', line):
                continue
            skipping = False
        out.append(line)
sys.stdout.write(''.join(out))
PY

MARK_PROMISE='mark[a-z]*[^.]{0,60}unserved|unserved[^.]{0,60}mark[a-z]*'
if [ ! -s "$SERVE_STRIPPED" ]; then
  fail "marker: the plan-003 strip of serve.py produced nothing — the docblock clause is unchecked"
elif grep -qE 'Contract: 003-B[0-9]+' "$SERVE" && grep -qE 'Contract: 003-B[0-9]+' "$SERVE_STRIPPED"; then
  fail "marker: a plan-003 contract comment survived the strip — the docblock check is unreliable"
elif grep -qiE -- "$MARK_PROMISE" "$SERVE_STRIPPED"; then
  fail "marker: serve.py still ties a mark to a never-served document: $(grep -niE -- "$MARK_PROMISE" "$SERVE_STRIPPED" | head -4 | tr '\n' ' ')"
else
  pass "marker: no docblock clause or line in serve.py promises a visible \"unserved\" mark any more"
fi

# --- A never-served entry's markup is a served entry's markup ----------------

served_li="$(li_for "$MAIN_PLAN")"
unserved_li="$(li_for "$MAIN_R1")"
if [ -z "$served_li" ] || [ -z "$unserved_li" ]; then
  fail "markup: a served and a never-served entry element could not both be located; the identical-markup clause is unchecked"
elif [ "$(li_shape "$served_li")" = "$(li_shape "$unserved_li")" ]; then
  pass "markup: a never-served entry is marked up exactly like a served one (only its link target and text differ)"
else
  fail "markup: the served entry is \"$(li_shape "$served_li")\" but the never-served entry is \"$(li_shape "$unserved_li")\""
fi

# --- Position is the whole distinction ---------------------------------------

main_text="$(group_text "$L_MAIN")"
if [ -z "$main_text" ]; then
  fail "order: the wt-main group could not be located; its ordering clauses are unchecked"
  fail "order: whether the group's entries come out in the contract's exact sequence is unchecked"
else
  p_plan="$(text_pos "$main_text" ".local/PLAN.md")"
  p_notes="$(text_pos "$main_text" "notes.md")"
  p_r1="$(text_pos "$main_text" ".local/reports/r1.md")"
  p_b1="$(text_pos "$main_text" ".local/briefs/b1.md")"
  p_plan="${p_plan:--1}"
  p_notes="${p_notes:--1}"
  p_r1="${p_r1:--1}"
  p_b1="${p_b1:--1}"
  if [ "$p_plan" -ge 0 ] && [ "$p_r1" -gt "$p_plan" ] && [ "$p_b1" -gt "$p_plan" ]; then
    pass "order: within a group, unserved documents list after every served one"
  else
    fail "order: wt-main's served PLAN.md@$p_plan does not precede its unserved r1.md@$p_r1 / b1.md@$p_b1: $main_text"
  fi
  if [ "$p_r1" -ge 0 ] && [ "$p_b1" -gt "$p_r1" ]; then
    pass "order: unserved documents are ordered by mtime, newest first"
  else
    fail "order: reports/r1.md (newer) does not precede briefs/b1.md within wt-main: $main_text"
  fi
  # The exact sequence, which is what a reader now has instead of a mark:
  # registry order (PLAN.md, notes.md) then mtime descending (r1.md, b1.md).
  if [ "$p_plan" -ge 0 ] && [ "$p_notes" -gt "$p_plan" ] && [ "$p_r1" -gt "$p_notes" ] \
    && [ "$p_b1" -gt "$p_r1" ]; then
    pass "order: the group reads served-in-registry-order then never-served-newest-first, which is the only distinction left"
  else
    fail "order: wt-main's entries are not in the contract's sequence (PLAN.md@$p_plan, notes.md@$p_notes, r1.md@$p_r1, b1.md@$p_b1): $main_text"
  fi
fi

delta_text="$(group_text "$L_DELTA")"
if [ -z "$delta_text" ]; then
  fail "marker: the repo-delta group could not be located; the all-served clause is unchecked"
elif text_matches "$delta_text" 'unserved'; then
  fail "marker: repo-delta has served every document it has, yet its group says \"unserved\": $delta_text"
else
  pass "marker: a group whose documents were all served says nothing about serving either"
fi

# --- A group for a worktree that never served anything -----------------------

if [ "$LINKED_OK" -ne 1 ]; then
  skip "never-served group: the multi-worktree fixture could not be built"
else
  if body_has "$L_SIBLING"; then
    pass "groups: a worktree that never served a document still gets a group, labelled like any other"
  else
    fail "groups: no group for the never-served sibling worktree \"$L_SIBLING\""
  fi

  sibling_text="$(group_text "$L_SIBLING")"
  if [ -z "$sibling_text" ]; then
    fail "never-served group: its slice could not be located; the headline clauses are unchecked"
  else
    if group_has_link_to "$L_SIBLING" "$SIBLING_WG"; then
      pass "never-served group: its WORKGRAPH.md is the headline, linking to its own /doc view"
    else
      fail "never-served group: no /doc link for the never-served worktree's WORKGRAPH.md"
    fi
    if text_matches "$sibling_text" "3${WIN}open|open${WIN}3"; then
      pass "never-served group: the headline shows the open-node count (3), exactly as a served group does"
    else
      fail "never-served group: no open-node count of 3 in the headline: $sibling_text"
    fi
    if text_matches "$sibling_text" "N02"; then
      pass "never-served group: the headline shows the Focus id"
    else
      fail "never-served group: the headline does not show Focus N02: $sibling_text"
    fi
    # 003-B15's edge case: a group holding ONLY never-served documents renders
    # like any other group, so it says nothing about serving and its entries are
    # marked up like a served group's.
    if text_matches "$sibling_text" 'unserved'; then
      fail "never-served group: a group holding only never-served documents still marks them: $sibling_text"
    else
      pass "never-served group: a group holding only never-served documents renders like any other"
    fi
    sib_li="$(li_for "$SIBLING_NOTES")"
    if [ -z "$sib_li" ] || [ -z "$served_li" ]; then
      fail "never-served group: its entry element could not be compared with a served one"
    elif [ "$(li_shape "$sib_li")" = "$(li_shape "$served_li")" ]; then
      pass "never-served group: its entries carry the same markup as a served group's"
    else
      fail "never-served group: its entry is \"$(li_shape "$sib_li")\" against a served group's \"$(li_shape "$served_li")\""
    fi
    if group_has_link_to "$L_SIBLING" "$SIBLING_NOTES" \
      && group_has_link_to "$L_SIBLING" "$SIBLING_TASKS"; then
      pass "never-served group: every one of its documents links to its live /doc view"
    else
      fail "never-served group: a document of the never-served worktree has no /doc link"
    fi
  fi

  # Contract: 003-B16 homepage groups collapsed (plan 003-followup-fixes)
  #
  # A group renders collapsible and COLLAPSED whether or not it has served
  # anything — "exactly like served groups", and now like the landing page's own
  # subdirectory groups, which have always shipped without the open attribute.
  details_count="$(grep -oi '<details' "$BODY" 2> /dev/null | wc -l | tr -d ' ')"
  open_details="$(grep -oiE '<details[^>]*\bopen\b' "$BODY" 2> /dev/null | wc -l | tr -d ' ')"
  expected_groups="${#GROUP_LABELS[@]}"
  if [ "$details_count" = "$expected_groups" ]; then
    pass "groups: one <details> per worktree, discovered and registered alike ($expected_groups)"
  else
    fail "groups: found $details_count <details> elements, expected $expected_groups (one per worktree)"
  fi
  if [ "$open_details" = "0" ]; then
    pass "groups: every group renders collapsed by default, never-served groups included"
  else
    fail "groups: $open_details of $expected_groups groups carry the open attribute — every group must render collapsed"
  fi
fi

# --- Groups that DID serve keep the order they have today --------------------

do_request "$BASE_A/"
p_main="$(pos_of "$L_MAIN")"
p_beta="$(pos_of "$L_BETA")"
p_delta="$(pos_of "$L_DELTA")"
p_main="${p_main:--1}"
p_beta="${p_beta:--1}"
p_delta="${p_delta:--1}"
if [ "$p_main" -ge 0 ] && [ "$p_beta" -gt "$p_main" ] && [ "$p_delta" -gt "$p_beta" ]; then
  pass "order: groups with served documents keep their last-served ranking"
else
  fail "order: served-group order changed (wt-main@$p_main, repo-beta@$p_beta, repo-delta@$p_delta; expected that order)"
fi
if [ "$LINKED_OK" -eq 1 ]; then
  p_second="$(pos_of "$L_SECOND")"
  p_second="${p_second:--1}"
  if [ "$p_second" -gt "$p_main" ] && [ "$p_second" -lt "$p_beta" ]; then
    pass "order: a second registered worktree of one repo is ranked by its own last-served time"
  else
    fail "order: the second registered worktree sits at $p_second, expected between $p_main and $p_beta"
  fi
fi

# =============================================================================
# Errors: GET / never 500s for discovery reasons, and a discovery failure
# degrades the page to what it shows today
# =============================================================================

# git broken for the server process: sibling enumeration fails on every root.
SHIM="$WORK/shim"
mkdir -p "$SHIM"
{
  printf '#!/bin/sh\n'
  printf 'echo "fatal: git is broken here" >&2\n'
  printf 'exit 128\n'
} > "$SHIM/git"
chmod +x "$SHIM/git"

PORT_B="$(free_port)"
BASE_B="http://127.0.0.1:$PORT_B"
write_seed "/tmp/render-doc-registry-$PORT_B.json" "${SEED_ARGS[@]}"
start_server "$PORT_B" "$WORK/srv-b.stderr" "$SHIM"
if wait_healthy "$BASE_B"; then
  pass "broken git: the server is healthy with a git that always fails"
else
  fail "broken git: the server did not become healthy"
fi
do_request "$BASE_B/"
if [ "$RESP_CODE" = "200" ]; then
  pass "broken git: GET / is 200, never a 500 for a discovery reason"
else
  fail "broken git: GET / returned $RESP_CODE"
fi
if ! page_ok; then
  fail "broken git: the registry-only degradation could not be checked (no page was returned)"
elif body_has "\"/doc$(enc "$MAIN_PLAN")\"" && body_has "\"/doc$(enc "$BETA_DESIGN")\""; then
  pass "broken git: the page still lists every registered document"
else
  fail "broken git: a registered document was lost when sibling enumeration failed"
fi
# worktree_siblings degrades to [root], so a registered root's OWN documents are
# still discovered — the failure costs siblings, not the whole feature.
if ! page_ok; then
  fail "broken git: the degraded-but-still-scanning clause could not be checked"
elif body_has "\"/doc$(enc "$MAIN_R1")\""; then
  pass "broken git: a registered root's own .local documents are still discovered"
else
  fail "broken git: discovery of the registered root's own documents stopped when git failed"
fi

# An unreadable .local on one of the registered roots.
if [ "$(id -u)" -eq 0 ]; then
  skip "unreadable .local: running as root, so a mode-000 directory would still be readable"
else
  chmod 000 "$REPO_BETA/.local"
  do_request "$BASE_A/"
  if [ "$RESP_CODE" = "200" ]; then
    pass "unreadable .local: GET / is still 200"
  else
    fail "unreadable .local: GET / returned $RESP_CODE"
  fi
  if ! page_ok; then
    fail "unreadable .local: whether other groups survive could not be checked"
  elif body_has "\"/doc$(enc "$MAIN_R1")\""; then
    pass "unreadable .local: one unreadable directory does not cost the other groups their documents"
  else
    fail "unreadable .local: the whole index degraded because one directory could not be read"
  fi
  chmod 755 "$REPO_BETA/.local"
fi

# =============================================================================
# Invariants: visiting the index registers nothing and writes nothing
# =============================================================================

do_request "$BASE_A/docs.json"
DOCS_BEFORE="$(python3 -c "
import json, sys
print('\n'.join(sorted(e['path'] for e in json.load(open(sys.argv[1]))['docs'])))
" "$BODY" 2> /dev/null)"
do_request "$BASE_A/"
do_request "$BASE_A/"
do_request "$BASE_A/docs.json"
DOCS_AFTER="$(python3 -c "
import json, sys
print('\n'.join(sorted(e['path'] for e in json.load(open(sys.argv[1]))['docs'])))
" "$BODY" 2> /dev/null)"
if [ -n "$DOCS_BEFORE" ] && [ "$DOCS_BEFORE" = "$DOCS_AFTER" ]; then
  pass "read-only: rendering the index registers nothing — /docs.json is unchanged by it"
else
  fail "read-only: /docs.json changed after the index was served (before: $DOCS_BEFORE / after: $DOCS_AFTER)"
fi

if [ "$(manifest)" = "$MANIFEST_BEFORE" ]; then
  pass "read-only: discovery rendered nothing and changed no fixture file"
else
  fail "read-only: the fixture tree changed while the index was served: $(diff <(printf '%s' "$MANIFEST_BEFORE") <(manifest) | head -5)"
fi

expect_code "host: wrong Host on / is still rejected" 403 -H 'Host: evil.example' "$BASE_A/"
expect_code "GET /: a query string is still stripped before routing" 200 "$BASE_A/?from=test"
expect_code "server: still healthy after every discovery path" 200 "$BASE_A/health"

for f in "$WORK/srv-a.stderr" "$WORK/srv-b.stderr"; do
  if grep -q 'Traceback (most recent call last)' "$f" 2> /dev/null; then
    fail "outputs: $(basename "$f") carries a traceback — a discovery path raised"
  else
    pass "outputs: $(basename "$f") is free of tracebacks"
  fi
done

# =============================================================================
# Left to acceptance review
# =============================================================================
# Two things are deliberately unasserted. Where a group with NO served member
# ranks among the others: the contract fixes that such groups exist and render
# like served ones, and says nothing about their position, so pinning one would
# invent a rule. And the edge case "a doc discovered now and served moments
# later shows as served on the next request" is covered only in the sense that
# no caching exists to break it — the contract promises no caching rather than
# any particular freshness, so there is nothing stronger to assert.

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'index-discovery.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'index-discovery.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'index-discovery.test.sh: all assertions passed\n'
