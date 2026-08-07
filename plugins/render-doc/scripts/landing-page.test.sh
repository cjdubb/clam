#!/usr/bin/env bash
# landing-page.test.sh — verifies the docblock "Contract: 002-B04 worktree
# landing page" in plugins/render-doc/scripts/serve.py, clause by clause: the
# per-worktree page at GET /project/<abs root> and the GET /project/for?path=
# resolver that redirects to it.
#
# Both stubs are Handler methods and the do_GET wiring already routes to them,
# so every assertion here runs over HTTP against a live server on a throwaway
# port — there is nothing to gain from importing serve.py when the contract is
# written in terms of status codes, headers and what a reader sees on a page.
#
# The page reads the SAME two sources the index does (discover_docs plus the
# registry) but merges them differently: only the requested root's own
# documents, never a sibling worktree's. That difference is the first thing
# this suite pins — a fixture repo with a linked worktree whose documents must
# NOT appear, which is exactly the bug an implementation that reuses
# index_doc_entries() would ship.
#
# Reading the page follows server-index.test.sh and index-discovery.test.sh:
# assertions about what a reader SEES run over a tag-stripped, entity-decoded
# copy of the body; assertions about where a link POINTS run over the raw
# body; and every <details> group is located by its own <summary> text rather
# than by position, so a group can never bleed into its neighbour.
#
# The annotation clauses are checked with unique tokens rather than realistic
# values ("NotesStateToken", not "in progress"): the contract says only the two
# protocol fields are parsed, and the only way to prove a document's OTHER
# content was not parsed is for the token to be absent from the whole page.
#
# Marker note: plan-002 contract markers are plan-qualified ("Contract:
# 002-B04"). serve.py also carries permanent, unrelated "Contract: B01"…"B03"
# docblocks from earlier plans, so nothing here greps the bare form.
#
# Server-fixture hygiene: every test server here runs on a free random port
# (never 27183, which belongs to a live session), and the teardown removes that
# port's /tmp registry and pidfile as well as killing the process — a leftover
# registry file collides with the random-port refuse-to-clobber guard that this
# suite and serve-mode.test.sh both use.
#
# Out of scope, because another suite owns it: the scan functions themselves
# (discovery-scan.test.sh), the registry (server-registry.test.sh), the global
# index page (server-index.test.sh, index-discovery.test.sh), the topbar links
# that point AT this page (topbar-nav.test.sh) and the prose describing it
# (landing-docs.test.sh).

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
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
  # The port's own /tmp artefacts go with it: a stale registry file would trip
  # the refuse-to-clobber guard of whichever suite draws that port next.
  for f in ${TMP_ARTEFACTS[@]+"${TMP_ARTEFACTS[@]}"}; do
    [ -n "$f" ] && rm -rf "$f"
  done
  # chmod first: one fixture document is deliberately mode 000.
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
die() { # abort when nothing further can be checked
  printf 'landing-page.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
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
[ "$MISSING" -ne 0 ] && die

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

enc() { # percent-encode a path the way the server's own links do
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$1"
}

PY_BIN="$(command -v python3)"

start_server() { # <port> <stderr file>
  env RENDER_DOC_PORT="$1" "$PY_BIN" "$SERVE" > "$2.stdout" 2> "$2" &
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

# Everything after "<name>:" on the response's header line, so a value carrying
# its own "; charset=..." survives intact.
header_value() { # <header name>
  python3 - "$HEADERS" "$1" << 'PY' 2> /dev/null
import sys
want = sys.argv[2].lower() + ':'
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    if line.lower().startswith(want):
        print(line[len(want):].strip())
        break
PY
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

page_ok() {
  [ "$RESP_CODE" = "200" ] && [ -s "$BODY" ]
}

# Character index of <needle> in the raw response body, or -1.
raw_pos() { # <needle>
  python3 - "$BODY" "$1" << 'PY' 2> /dev/null
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
print(data.find(sys.argv[2]))
PY
}

body_has() { # <literal string>
  [ "$(raw_pos "$1")" != "-1" ]
}

# How many times a literal occurs in the raw body.
raw_count() { # <needle>
  python3 - "$BODY" "$1" << 'PY' 2> /dev/null
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
print(data.count(sys.argv[2]))
PY
}

# The body as a reader sees it: style/script elements dropped WITH their
# contents, then tags removed, entities decoded, whitespace runs collapsed.
# Dropping the stylesheet matters — the page's own CSS names the class it marks
# unserved documents with, and that class name would otherwise satisfy the very
# clauses the marks are supposed to. (server-index.test.sh strips the same way.)
visible_text() {
  python3 - "$BODY" << 'PY' 2> /dev/null
import html
import re
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
data = re.sub(r'<(script|style)[^>]*>.*?</\1>', ' ', data, flags=re.S | re.I)
data = re.sub(r'<[^>]*>', ' ', data)
print(re.sub(r'\s+', ' ', html.unescape(data)))
PY
}

text_pos() { # <text> <needle>
  python3 -c "import sys; sys.stdout.write(str(sys.argv[1].lower().find(sys.argv[2].lower())))" \
    "$1" "$2" 2> /dev/null
}

text_count() { # <text> <needle>
  python3 -c "import sys; sys.stdout.write(str(sys.argv[1].lower().count(sys.argv[2].lower())))" \
    "$1" "$2" 2> /dev/null
}

text_matches() { # <text> <ere>
  printf '%s' "$1" | grep -Eqi -- "$2"
}

has_text() { # <text> <literal> <label>
  if printf '%s' "$1" | grep -qiF -- "$2"; then pass "$3"; else fail "$3"; fi
}

lacks_text() { # <text> <literal> <label>
  if printf '%s' "$1" | grep -qiF -- "$2"; then fail "$3"; else pass "$3"; fi
}

# A visible-text window that no path can span, so a digit lifted out of a
# fixture directory name can never satisfy an open-node count clause. Borrowed
# from server-index.test.sh.
WIN='[^0-9/.~]{0,40}'

# Strictly increasing visible-text positions, in the order given.
in_order() { # <text> <label> <needle>...
  local text="$1" label="$2" prev=-1 p n
  shift 2
  for n in "$@"; do
    p="$(text_pos "$text" "$n")"
    p="${p:--1}"
    if [ "$p" -lt 0 ]; then
      fail "$label: \"$n\" is not on the page at all"
      return 1
    fi
    if [ "$p" -le "$prev" ]; then
      fail "$label: \"$n\" at $p does not follow the entry before it (at $prev)"
      return 1
    fi
    prev="$p"
  done
  pass "$label"
}

# The full <details>…</details> block whose <summary> text contains <needle>.
# Groups are never nested, so the non-greedy match is exact.
details_with() { # <summary substring>
  python3 - "$BODY" "$1" << 'PY' 2> /dev/null
import re
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
want = sys.argv[2].lower()
for m in re.finditer(r'<details\b.*?</details>', data, re.S | re.I):
    block = m.group(0)
    sm = re.search(r'<summary\b[^>]*>(.*?)</summary>', block, re.S | re.I)
    text = re.sub(r'<[^>]*>', ' ', sm.group(1)) if sm else ''
    if want in text.lower():
        sys.stdout.write(block)
PY
}

# How many <details> groups carry <needle> in their summary.
details_matching() { # <summary substring>
  python3 - "$BODY" "$1" << 'PY' 2> /dev/null
import re
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
want = sys.argv[2].lower()
n = 0
for m in re.finditer(r'<details\b.*?</details>', data, re.S | re.I):
    sm = re.search(r'<summary\b[^>]*>(.*?)</summary>', m.group(0), re.S | re.I)
    text = re.sub(r'<[^>]*>', ' ', sm.group(1)) if sm else ''
    if want in text.lower():
        n += 1
print(n)
PY
}

block_text() { # <html fragment on stdin> -> reader-visible text
  python3 -c "
import html, re, sys
data = sys.stdin.read()
data = re.sub(r'<(script|style)[^>]*>.*?</\1>', ' ', data, flags=re.S | re.I)
data = re.sub(r'<[^>]*>', ' ', data)
print(re.sub(r'\s+', ' ', html.unescape(data)))
" 2> /dev/null
}

block_has_link_to() { # <html fragment> <absolute md path>
  printf '%s' "$1" | grep -oE 'href="[^"]*"' | sed 's/^href="//; s/"$//' \
    | grep -qxF -- "/doc$(enc "$2")"
}

# The response body as a JSON {"error": "<non-empty>"} object — scope_error's
# shape, which the contract says these failures mirror.
json_error_ok() {
  python3 - "$BODY" << 'PY' 2> /dev/null
import json
import sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
assert isinstance(d, dict), d
assert list(d.keys()) == ['error'], d
assert isinstance(d['error'], str) and d['error'].strip(), d
PY
}

expect_json_error() { # <label> <expected code> <curl args...>
  local label="$1" expected="$2"
  shift 2
  do_request "$@"
  if [ "$RESP_CODE" != "$expected" ]; then
    fail "$label: expected $expected, got $RESP_CODE"
    return
  fi
  local ctype
  ctype="$(header_value Content-Type)"
  if ! printf '%s' "$ctype" | grep -qi 'application/json'; then
    fail "$label: $expected returned Content-Type \"$ctype\", expected application/json"
    return
  fi
  if json_error_ok; then
    pass "$label ($expected, {\"error\": ...})"
  else
    fail "$label: $expected body is not scope_error's {\"error\": <message>} shape: $(head -c 200 "$BODY")"
  fi
}

# Sibling plugin directory names, read from the tree rather than written out:
# a literal name in one of the four reference forms would itself be a
# cross-plugin reference in this file. Copied from discovery-docs.test.sh.
sibling_plugins() {
  find "$REPO_ROOT/plugins" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2> /dev/null \
    | grep -vFx "$(basename "$PLUGIN_DIR")" | sort
}

assert_no_sibling_reference() { # <haystack> <label>
  local haystack="$1" label="$2"
  local hit="" p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if printf '%s' "$haystack" | grep -qEi -- "/${p}:|${p}@clam|plugins/${p}/|${p}[[:space:]]plugin"; then
      hit="$p"
      break
    fi
  done < <(sibling_plugins)
  if [ -n "$hit" ]; then
    fail "$label: names another plugin — the page's labels must come only from paths and protocol fields"
  else
    pass "$label: names no other plugin"
  fi
}

has_git_ancestor() { # <path>
  local d
  d="$(dirname "$1")"
  while :; do
    [ -e "$d/.git" ] && return 0
    [ "$d" = "/" ] && return 1
    d="$(dirname "$d")"
  done
}

manifest() {
  find "$FIX" \( -type f -o -type l \) ! -path '*/.git/*' -printf '%p %y %T@\n' 2> /dev/null | sort
}

# --- Fixtures ----------------------------------------------------------------
# Fixtures live under $HOME because every path the page lists passes through
# scope_error, which requires exactly that (plus a git worktree ancestor).

FIX="$(mktemp -d "$HOME/.render-doc-lptest.XXXXXX")"
HOME_DIRS+=("$FIX")

WT_MAIN="$FIX/wt-main"       # the page under test: docs, groups, annotations
WT_SIBLING="$FIX/wt-sibling" # a LINKED worktree of wt-main: must not bleed in
WT_BROKEN="$FIX/wt-broken"   # an unparseable WORKGRAPH.md
WT_EMPTY="$FIX/wt-empty"     # a worktree with no .local at all
WT_NODOCS="$FIX/wt-nodocs"   # a .local carrying no markdown
WT_OTHER="$FIX/wt-other"     # registered, unrelated: must not bleed in
PLAIN_DIR="$FIX/plain-dir"   # under $HOME, carries no .git
OUTSIDE="$WORK/outside-repo" # a git worktree outside $HOME

for d in "$WT_MAIN" "$WT_BROKEN" "$WT_EMPTY" "$WT_NODOCS" "$WT_OTHER" "$OUTSIDE"; do
  mkdir -p "$d"
  git init -q "$d" 2> /dev/null
done
mkdir -p "$PLAIN_DIR"

LINKED_OK=0
if git -C "$WT_MAIN" -c user.email=test@example.invalid -c user.name=Test \
  commit -q --allow-empty -m init > /dev/null 2>&1 \
  && git -C "$WT_MAIN" worktree add -q "$WT_SIBLING" -b lp-sibling > /dev/null 2>&1; then
  LINKED_OK=1
  mkdir -p "$WT_SIBLING/.local"
  printf '# Sibling\n' > "$WT_SIBLING/.local/SIBLINGONLY.md"
fi

mkdir -p "$WT_MAIN/.local/reports/nested" "$WT_MAIN/.local/briefs" \
  "$WT_MAIN/.local/decisions" "$WT_MAIN/.local/assets" \
  "$WT_BROKEN/.local" "$WT_NODOCS/.local" "$WT_OTHER/.local"

# Unique tokens: each proves a clause by being present exactly where the
# contract says it should be, or absent from the whole page where it says
# nothing else is parsed.
T_NOTES='NotesStateToken'
T_DECIDE='DecideStatusToken'
T_BOTH_STATE='BothStateToken'
T_BOTH_STATUS='BothStatusToken'
T_LATE='LateStateToken'
T_PRIORITY='PlainPriorityToken'
T_HEADING='PlainHeadingToken'
T_INDENTED='IndentedStateToken'
T_PREFIXED='PrefixedStateToken'
T_FALLBACK='FallbackStatusToken'
T_UNREADABLE='UnreadableStateToken'

# 74 characters, so "truncated to 60" is observable from both sides.
LONG_VALUE='LongState-ABCDEFGHIJKLMNOPQRSTUVWXYZ-abcdefghijklmnopqrstuvwxyz-0123456789'
LONG_KEPT="${LONG_VALUE:0:50}"
LONG_OVER="${LONG_VALUE:0:61}"

# A name carrying markup and an ampersand: every character of it is
# file-derived, therefore untrusted.
ANGLE_NAME='doc<img>&x.md'
UTF8_NAME='café.md'

# The headline document, and a second WORKGRAPH.md deeper in the tree that must
# stay an ordinary listed document (distinct Focus id, so a headline built from
# the wrong file names itself).
cat > "$WT_MAIN/.local/WORKGRAPH.md" << 'MD'
# Work Graph

Focus: N05

## N01 — first
- Status: open

## N02 — second
- Status: open

## N03 — landed
- Status: done
MD

cat > "$WT_MAIN/.local/reports/WORKGRAPH.md" << 'MD'
# Work Graph

Focus: N09

## N01 — a
- Status: open

## N02 — b
- Status: open

## N03 — c
- Status: open

## N04 — d
- Status: open

## N05 — e
- Status: open
MD

printf '# Plan\n' > "$WT_MAIN/.local/PLAN.md"
printf '# Second\n' > "$WT_MAIN/.local/SECOND.md"
# Registered but NOT under .local: the union with the registry is what puts it
# on the page at all — discovery alone never sees it.
printf '# Outside\n' > "$WT_MAIN/outside-local.md"

printf '# Notes\nState: %s\n' "$T_NOTES" > "$WT_MAIN/.local/NOTES.md"
printf '# Decision\nStatus: %s\n' "$T_DECIDE" > "$WT_MAIN/.local/DECIDE.md"
printf '# Both\nStatus: %s\nState: %s\n' "$T_BOTH_STATUS" "$T_BOTH_STATE" \
  > "$WT_MAIN/.local/BOTH.md"
printf '# Long\nState: %s\n' "$LONG_VALUE" > "$WT_MAIN/.local/LONG.md"
{
  printf '# Late\n'
  i=1
  while [ "$i" -le 110 ]; do
    printf 'filler line %s\n' "$i"
    i=$((i + 1))
  done
  printf 'State: %s\n' "$T_LATE"
} > "$WT_MAIN/.local/LATE.md"
printf '# %s\nPriority: %s\n' "$T_HEADING" "$T_PRIORITY" > "$WT_MAIN/.local/PLAIN.md"
printf '# Anchors\n  State: %s\nxState: %s\n' "$T_INDENTED" "$T_PREFIXED" \
  > "$WT_MAIN/.local/NOTANCHOR.md"
# A State: line with no value does not match ^State:[ \t]*(.+)$, so the
# decision-file field is what remains.
printf '# Empty\nState:\nStatus: %s\n' "$T_FALLBACK" > "$WT_MAIN/.local/EMPTYSTATE.md"
printf '# Unreadable\nState: %s\n' "$T_UNREADABLE" > "$WT_MAIN/.local/UNREADABLE.md"
printf '# Cafe\n' > "$WT_MAIN/.local/$UTF8_NAME"
printf '# Markup\nState: <script>alert(1)</script>\n' > "$WT_MAIN/.local/$ANGLE_NAME"

printf '# Report one\n' > "$WT_MAIN/.local/reports/r1.md"
printf '# Deep\n' > "$WT_MAIN/.local/reports/nested/deep.md"
printf '# Brief one\n' > "$WT_MAIN/.local/briefs/b1.md"
printf '# Decision one\n' > "$WT_MAIN/.local/decisions/d1.md"
# A subdirectory holding no markdown at all: no group may be emitted for it.
printf 'not markdown\n' > "$WT_MAIN/.local/assets/readme.txt"

# A WORKGRAPH.md with no Focus line: read_workgraph cannot parse it, and both
# halves of the headline must degrade rather than error.
cat > "$WT_BROKEN/.local/WORKGRAPH.md" << 'MD'
# Work Graph

## N01 — first
- Status: open
MD
printf '# Still listed\n' > "$WT_BROKEN/.local/OTHERDOC.md"

printf 'not markdown\n' > "$WT_NODOCS/.local/readme.txt"
printf '# Other repo\n' > "$WT_OTHER/.local/OTHERREPO.md"
printf '# Loose\n' > "$FIX/loose.md"

chmod 000 "$WT_MAIN/.local/UNREADABLE.md"

# Distinct mtimes so every ordering assertion below rests on this file's
# choices rather than on the order things happened to be created in.
python3 - "$WT_MAIN" "$ANGLE_NAME" "$UTF8_NAME" << 'PY'
import os
import sys
root, angle, utf8 = sys.argv[1], sys.argv[2], sys.argv[3]
stamps = {
    '.local/WORKGRAPH.md': 9000,
    '.local/NOTES.md': 8800,
    '.local/DECIDE.md': 8700,
    '.local/BOTH.md': 8600,
    '.local/LONG.md': 8500,
    '.local/LATE.md': 8400,
    '.local/PLAIN.md': 8300,
    '.local/NOTANCHOR.md': 8200,
    '.local/EMPTYSTATE.md': 8100,
    '.local/UNREADABLE.md': 8000,
    '.local/' + utf8: 7900,
    '.local/' + angle: 7800,
    '.local/PLAN.md': 100,
    '.local/SECOND.md': 100,
    '.local/reports/r1.md': 9500,
    '.local/reports/nested/deep.md': 9400,
    '.local/reports/WORKGRAPH.md': 9300,
    '.local/decisions/d1.md': 7000,
    '.local/briefs/b1.md': 6000,
}
for rel, t in stamps.items():
    p = os.path.join(root, rel)
    if os.path.exists(p):
        os.utime(p, (t, t))
PY

MAIN_ROOT="$(realpath_of "$WT_MAIN")"
BROKEN_ROOT="$(realpath_of "$WT_BROKEN")"
EMPTY_ROOT="$(realpath_of "$WT_EMPTY")"
NODOCS_ROOT="$(realpath_of "$WT_NODOCS")"
SIBLING_ROOT="$(realpath_of "$WT_SIBLING")"

MAIN_PLAN="$(realpath_of "$WT_MAIN/.local/PLAN.md")"
MAIN_SECOND="$(realpath_of "$WT_MAIN/.local/SECOND.md")"
MAIN_OUTSIDE="$(realpath_of "$WT_MAIN/outside-local.md")"
MAIN_WG="$(realpath_of "$WT_MAIN/.local/WORKGRAPH.md")"
MAIN_NOTES="$(realpath_of "$WT_MAIN/.local/NOTES.md")"
MAIN_UNREADABLE="$(realpath_of "$WT_MAIN/.local/UNREADABLE.md")"
MAIN_UTF8="$(realpath_of "$WT_MAIN/.local/$UTF8_NAME")"
MAIN_ANGLE="$(realpath_of "$WT_MAIN/.local/$ANGLE_NAME")"
MAIN_R1="$(realpath_of "$WT_MAIN/.local/reports/r1.md")"
MAIN_DEEP="$(realpath_of "$WT_MAIN/.local/reports/nested/deep.md")"
MAIN_REPORTS_WG="$(realpath_of "$WT_MAIN/.local/reports/WORKGRAPH.md")"
MAIN_B1="$(realpath_of "$WT_MAIN/.local/briefs/b1.md")"
MAIN_D1="$(realpath_of "$WT_MAIN/.local/decisions/d1.md")"
BROKEN_WG="$(realpath_of "$WT_BROKEN/.local/WORKGRAPH.md")"
BROKEN_OTHER="$(realpath_of "$WT_BROKEN/.local/OTHERDOC.md")"
OTHER_DOC="$(realpath_of "$WT_OTHER/.local/OTHERREPO.md")"
SIBLING_DOC="$(realpath_of "$WT_SIBLING/.local/SIBLINGONLY.md")"
LOOSE_DOC="$(realpath_of "$FIX/loose.md")"

# A symlink whose realpath lands inside wt-main: /project/for resolves the path
# before it looks for a worktree.
ln -s "$MAIN_NOTES" "$FIX/link-to-notes.md"
LINK_DOC="$FIX/link-to-notes.md"

HOME_REAL="$(realpath_of "$HOME")"
label_for() { # <worktree dir> -> the ~-abbreviated label worktree_label returns
  local real
  real="$(realpath_of "$1")"
  printf '~%s' "${real#"$HOME_REAL"}"
}
L_MAIN="$(label_for "$WT_MAIN")"
L_EMPTY="$(label_for "$WT_EMPTY")"
L_NODOCS="$(label_for "$WT_NODOCS")"

if [ "$HOME_REAL" = "$(realpath_of "$FIX")" ] || [ "$L_MAIN" = "~" ]; then
  fail "setup: the fixture did not resolve under \$HOME; no scope-dependent clause can be checked"
  die
fi
[ "$LINKED_OK" -eq 1 ] \
  || skip "sibling isolation: 'git worktree add' failed here, so that clause is unchecked"

# The outside-$HOME fixture only means anything when the temp directory really
# is outside $HOME (a TMPDIR pointing inside it would make the clause vacuous).
OUTSIDE_OK=1
case "$(realpath_of "$WORK")/" in
  "$HOME_REAL"/*) OUTSIDE_OK=0 ;;
esac

# --- Server ------------------------------------------------------------------

PORT_A="$(free_port)"
BASE_A="http://127.0.0.1:$PORT_A"
REG_A="/tmp/render-doc-registry-$PORT_A.json"
if [ -e "$REG_A" ]; then
  fail "test port $PORT_A already has a registry file at $REG_A; aborting to avoid clobbering it"
  die
fi
# Served entries, newest first: PLAN, outside-local, SECOND. OTHERREPO.md
# belongs to a different worktree and must never reach wt-main's page.
write_seed "$REG_A" \
  "$MAIN_PLAN" 5000 \
  "$MAIN_OUTSIDE" 4500 \
  "$MAIN_SECOND" 4000 \
  "$OTHER_DOC" 6000
TMP_ARTEFACTS+=("$REG_A")

start_server "$PORT_A" "$WORK/srv-a.stderr"
if wait_healthy "$BASE_A"; then
  pass "server: healthy on test port $PORT_A"
else
  fail "server: did not become healthy on test port $PORT_A — no clause can be checked"
  die
fi

MANIFEST_BEFORE="$(manifest)"
do_request "$BASE_A/docs.json"
DOCS_BEFORE="$(python3 -c "
import json, sys
print('\n'.join(sorted(e['path'] for e in json.load(open(sys.argv[1]))['docs'])))
" "$BODY" 2> /dev/null)"

PROJECT_MAIN="$BASE_A/project$(enc "$MAIN_ROOT")"

# =============================================================================
# Outputs: 200, text/html; charset=utf-8, a correct Content-Length, and ONE
# self-contained page
# =============================================================================

do_request "$PROJECT_MAIN"
if [ "$RESP_CODE" = "200" ]; then
  pass "GET /project/<root>: the worktree's landing page is served (200)"
else
  fail "GET /project/<root>: expected 200, got $RESP_CODE"
fi

ctype="$(header_value Content-Type)"
if [ "$ctype" = 'text/html; charset=utf-8' ]; then
  pass "GET /project/<root>: Content-Type is exactly \"text/html; charset=utf-8\""
else
  fail "GET /project/<root>: Content-Type is \"$ctype\", expected exactly \"text/html; charset=utf-8\""
fi

clen="$(header_value Content-Length)"
blen="$(wc -c < "$BODY" | tr -d ' ')"
if [ -n "$clen" ] && [ "$clen" = "$blen" ]; then
  pass "GET /project/<root>: Content-Length matches the body ($blen bytes)"
else
  fail "GET /project/<root>: Content-Length \"$clen\" does not match the $blen received bytes"
fi

if body_has "<html" && body_has "</html>"; then
  pass "GET /project/<root>: the response is one complete HTML document"
else
  fail "GET /project/<root>: the response is not a complete HTML document"
fi

if ! page_ok; then
  fail "GET /project/<root>: the self-contained clauses could not be checked (no page was returned)"
else
  if grep -E '<link[^>]+href="https?:|src="https?:|src='"'"'https?:|url\(https?:|@import|fonts\.googleapis' \
    "$BODY" > /dev/null 2>&1; then
    fail "GET /project/<root>: the page references external URLs/CDNs"
  else
    pass "GET /project/<root>: no external URL/CDN references"
  fi
  if grep -qi '<style' "$BODY" 2> /dev/null; then
    pass "GET /project/<root>: styling is inline (a <style> block is present)"
  else
    fail "GET /project/<root>: no inline <style> block — the page is not self-contained"
  fi
  if grep -qi '<script' "$BODY" 2> /dev/null; then
    fail "GET /project/<root>: the page carries a <script> element — it must work with scripting disabled"
  else
    pass "GET /project/<root>: no <script> element (the page works with scripting disabled)"
  fi
fi

PAGE_TEXT="$(visible_text)"

# =============================================================================
# Behavior 2: the document set is THIS root's discovered documents united with
# THIS root's registry entries — and nothing else
# =============================================================================

for p in "$MAIN_NOTES" "$MAIN_R1" "$MAIN_DEEP" "$MAIN_B1" "$MAIN_D1" "$MAIN_UTF8"; do
  if body_has "\"/doc$(enc "$p")\""; then
    pass "documents: the discovered document $(basename "$p") is listed with a /doc link"
  else
    fail "documents: no /doc link for the discovered document $p"
  fi
done

for p in "$MAIN_PLAN" "$MAIN_SECOND"; do
  if body_has "\"/doc$(enc "$p")\""; then
    pass "documents: the registered document $(basename "$p") is listed"
  else
    fail "documents: the registered document $p is missing from the page"
  fi
done

if body_has "\"/doc$(enc "$MAIN_OUTSIDE")\""; then
  pass "documents: a registered document outside .local reaches the page through the registry union"
else
  fail "documents: the registered document $MAIN_OUTSIDE (outside .local) was lost from the union"
fi

if body_has "\"/doc$(enc "$OTHER_DOC")\"" || text_matches "$PAGE_TEXT" 'OTHERREPO'; then
  fail "isolation: a registered document belonging to a different worktree appears on this page"
else
  pass "isolation: only this root's registry entries reach the page"
fi

if [ "$LINKED_OK" -ne 1 ]; then
  skip "isolation: the linked-worktree fixture could not be built"
elif body_has "\"/doc$(enc "$SIBLING_DOC")\"" || text_matches "$PAGE_TEXT" 'SIBLINGONLY'; then
  fail "isolation: a SIBLING worktree's documents appear on this page (the landing page scans one root, not the repo)"
else
  pass "isolation: a sibling worktree's documents stay off this page"
fi

# Edge case: a document both registered and discovered is ONE entry, served.
n_plan="$(raw_count "\"/doc$(enc "$MAIN_PLAN")\"")"
if [ "${n_plan:-0}" = "1" ]; then
  pass "merge: a document that is both registered and discovered is listed exactly once"
else
  fail "merge: PLAN.md is registered and discovered, and its /doc link appears $n_plan time(s), expected 1"
fi

# =============================================================================
# Behavior 2 (order and marking): served first in last-served order, then
# unserved by mtime descending, each unserved document marked
# =============================================================================

in_order "$PAGE_TEXT" "order: served documents list in last-served order" \
  "PLAN.md" "SECOND.md"

in_order "$PAGE_TEXT" "order: served documents precede every unserved one" \
  "SECOND.md" "NOTES.md"

in_order "$PAGE_TEXT" "order: unserved documents follow mtime, newest first" \
  "NOTES.md" "DECIDE.md" "BOTH.md" "LONG.md" "LATE.md" "PLAIN.md" \
  "NOTANCHOR.md" "EMPTYSTATE.md" "UNREADABLE.md"

n_marks="$(text_count "$PAGE_TEXT" unserved)"
# 11 top-level unserved documents plus the 5 inside the three groups. The
# headline is deliberately excluded: whether the headline document itself
# carries the mark is not something the contract settles.
if [ "${n_marks:-0}" -ge 16 ]; then
  pass "marking: every unserved document carries an \"unserved\" mark ($n_marks marks)"
else
  fail "marking: the page carries $n_marks \"unserved\" marks, expected at least one per unserved document (16)"
fi

p_second="$(text_pos "$PAGE_TEXT" "SECOND.md")"
p_mark="$(text_pos "$PAGE_TEXT" "unserved")"
p_second="${p_second:--1}"
p_mark="${p_mark:--1}"
if [ "$p_second" -ge 0 ] && [ "$p_mark" -gt "$p_second" ]; then
  pass "marking: no served document is marked unserved (the first mark follows every served entry)"
else
  fail "marking: an \"unserved\" mark at $p_mark precedes the served SECOND.md at $p_second"
fi

# =============================================================================
# Behavior 3: the headline is exactly <root>/.local/WORKGRAPH.md
# =============================================================================

if body_has "\"/doc$(enc "$MAIN_WG")\""; then
  pass "headline: .local/WORKGRAPH.md is on the page with its own /doc link"
else
  fail "headline: no /doc link for $MAIN_WG"
fi
if text_matches "$PAGE_TEXT" "2${WIN}open|open${WIN}2"; then
  pass "headline: the open-node count (2) is read from the protocol's markers"
else
  fail "headline: no open-node count of 2 on the page: $PAGE_TEXT"
fi
has_text "$PAGE_TEXT" "N05" "headline: the Focus id is read from the protocol's markers"

# A WORKGRAPH.md elsewhere in the tree is an ordinary document: it is listed in
# its own subdirectory's group, and its Focus id is never read.
if body_has "\"/doc$(enc "$MAIN_REPORTS_WG")\""; then
  pass "headline: a WORKGRAPH.md deeper in the tree is still listed as an ordinary document"
else
  fail "headline: the WORKGRAPH.md under .local/reports/ was dropped from the page"
fi
lacks_text "$PAGE_TEXT" "N09" \
  "headline: only .local/WORKGRAPH.md is parsed for a headline (a deeper one's Focus is never read)"

# =============================================================================
# Behavior 4: flat top-level documents first, one collapsed group per .local
# subdirectory, groups ordered by newest member
# =============================================================================

p_details="$(raw_pos "<details")"
p_details="${p_details:--1}"
if [ "$p_details" -lt 0 ]; then
  fail "layout: the page carries no <details> group at all — the layout clauses are unchecked"
else
  pass "layout: the page carries collapsible groups"
  flat_ok=1
  for p in "$MAIN_PLAN" "$MAIN_NOTES" "$MAIN_UTF8"; do
    pp="$(raw_pos "\"/doc$(enc "$p")\"")"
    pp="${pp:--1}"
    if [ "$pp" -lt 0 ] || [ "$pp" -gt "$p_details" ]; then
      fail "layout: the top-level document $(basename "$p") is not listed flat before the first group (at $pp, groups start at $p_details)"
      flat_ok=0
    fi
  done
  [ "$flat_ok" -eq 1 ] \
    && pass "layout: documents directly in .local/ list flat, first, outside every collapsible group"
fi

details_count="$(grep -oi '<details' "$BODY" 2> /dev/null | wc -l | tr -d ' ')"
if [ "$details_count" = "3" ]; then
  pass "layout: one group per .local subdirectory that contains listed documents (3)"
else
  fail "layout: found $details_count <details> groups, expected 3 — one for each of the .local subdirectories holding markdown"
fi

open_details="$(grep -oiE '<details[^>]*\bopen\b' "$BODY" 2> /dev/null | wc -l | tr -d ' ')"
if [ "$open_details" = "0" ]; then
  pass "layout: every group renders collapsed by default (no open attribute)"
else
  fail "layout: $open_details group(s) carry the open attribute — groups must render collapsed"
fi

for name in reports briefs decisions; do
  n="$(details_matching "$name")"
  if [ "${n:-0}" = "1" ]; then
    pass "layout: the .local/$name subdirectory has exactly one group, labelled with its name"
  else
    fail "layout: ${n:-0} group(s) are labelled \"$name\", expected exactly 1"
  fi
done

n_assets="$(details_matching "assets")"
if [ "${n_assets:-0}" = "0" ]; then
  pass "layout: a subdirectory holding no markdown gets no group"
else
  fail "layout: a group was emitted for .local/assets, which holds no listable document"
fi

REPORTS_BLOCK="$(details_with reports)"
if [ -z "$REPORTS_BLOCK" ]; then
  fail "layout: the reports group could not be located — its nesting clauses are unchecked"
else
  if block_has_link_to "$REPORTS_BLOCK" "$MAIN_R1"; then
    pass "layout: a subdirectory's own document is listed inside its group"
  else
    fail "layout: reports/r1.md is not inside the reports group"
  fi
  if block_has_link_to "$REPORTS_BLOCK" "$MAIN_DEEP"; then
    pass "layout: a nested document groups under its TOP-LEVEL subdirectory"
  else
    fail "layout: reports/nested/deep.md is not inside the reports group"
  fi
  reports_text="$(printf '%s' "$REPORTS_BLOCK" | block_text)"
  has_text "$reports_text" "nested/deep.md" \
    "layout: a nested document's entry text is its subdirectory-relative path"
fi

# Groups order by their newest member: reports (9500), then decisions (7000),
# then briefs (6000). Each name's FIRST appearance in the visible text is its
# own group's summary label, since no fixture document is named after another
# group's directory.
in_order "$PAGE_TEXT" "layout: groups order by their newest member's mtime, newest first" \
  "reports" "decisions" "briefs"

# =============================================================================
# Behavior 5: annotations come from the two protocol fields and nothing else
# =============================================================================

has_text "$PAGE_TEXT" "State: $T_NOTES" \
  "annotations: a todo-format State: line is shown as \"State: <value>\""
has_text "$PAGE_TEXT" "Status: $T_DECIDE" \
  "annotations: a decision-file Status: line is shown as \"Status: <value>\""
has_text "$PAGE_TEXT" "State: $T_BOTH_STATE" \
  "annotations: State: wins when a document carries both fields"
lacks_text "$PAGE_TEXT" "$T_BOTH_STATUS" \
  "annotations: the Status: value of a document that also has State: is not shown"
has_text "$PAGE_TEXT" "Status: $T_FALLBACK" \
  "annotations: a State: line with no value falls through to Status:"

has_text "$PAGE_TEXT" "$LONG_KEPT" "annotations: a long value is still shown"
lacks_text "$PAGE_TEXT" "$LONG_OVER" \
  "annotations: a value longer than 60 characters is truncated"

lacks_text "$PAGE_TEXT" "$T_LATE" \
  "annotations: a State: line past the first 100 lines is not read"
lacks_text "$PAGE_TEXT" "$T_INDENTED" \
  "annotations: an indented State: line does not match (the pattern is anchored)"
lacks_text "$PAGE_TEXT" "$T_PREFIXED" \
  "annotations: a State: preceded by other text does not match"
lacks_text "$PAGE_TEXT" "$T_PRIORITY" \
  "annotations: no other field is parsed out of a document"
lacks_text "$PAGE_TEXT" "$T_HEADING" \
  "annotations: a document's headings are not read into the page"

if body_has "\"/doc$(enc "$MAIN_UNREADABLE")\""; then
  pass "annotations: a document that cannot be read is still listed as a plain link"
else
  fail "annotations: an unreadable document was dropped from the page"
fi
if [ "$(id -u)" -eq 0 ]; then
  skip "annotations: running as root, so a mode-000 document would still be readable"
else
  lacks_text "$PAGE_TEXT" "$T_UNREADABLE" \
    "annotations: an unreadable document degrades to a plain link, not an error"
fi
if [ "$RESP_CODE" = "000" ] || [ "$RESP_CODE" = "500" ]; then
  fail "errors: a document that could not be read produced a $RESP_CODE"
else
  pass "errors: no per-document failure turns the page into an error response"
fi

# =============================================================================
# Behavior 6 / Invariants: /doc links and escaping of all file-derived text
# =============================================================================

if body_has "\"/doc$(enc "$MAIN_ANGLE")\""; then
  pass "escaping: a document whose name carries markup still links to its percent-encoded /doc view"
else
  fail "escaping: no percent-encoded /doc link for $MAIN_ANGLE"
fi
if body_has "&lt;img&gt;"; then
  pass "escaping: markup in a document NAME is HTML-escaped"
else
  fail "escaping: the name doc<img>&x.md is not escaped as &lt;img&gt;"
fi
if body_has "<img>"; then
  fail "escaping: an unescaped element from a document name reached the page"
else
  pass "escaping: no unescaped element from a document name reached the page"
fi
if body_has "<script>alert(1)"; then
  fail "escaping: an unescaped element from a document's CONTENT reached the page"
else
  pass "escaping: markup in an annotation value is HTML-escaped"
fi
has_text "$PAGE_TEXT" "café" \
  "encoding: a non-ASCII document name is decoded and shown as its own characters"

assert_no_sibling_reference "$PAGE_TEXT" "the landing page"

# =============================================================================
# Behavior 1: validation, mirroring scope_error's shape
# =============================================================================

expect_json_error "validation: a directory that carries no .git is refused" 403 \
  "$BASE_A/project$(enc "$(realpath_of "$PLAIN_DIR")")"
if [ "$OUTSIDE_OK" -eq 1 ]; then
  expect_json_error "validation: a git worktree outside \$HOME is refused" 403 \
    "$BASE_A/project$(enc "$(realpath_of "$OUTSIDE")")"
else
  skip "validation: the temp directory is inside \$HOME here, so the outside-home clause cannot be forced"
fi
expect_json_error "validation: a root that does not exist is a 404" 404 \
  "$BASE_A/project$(enc "$FIX/no-such-worktree")"

if [ -e "$HOME_REAL/.git" ]; then
  skip "validation: \$HOME itself carries a .git entry here, so the \$HOME-as-root clause would be a 200"
else
  do_request "$BASE_A/project$(enc "$HOME_REAL")"
  if [ "$RESP_CODE" = "403" ]; then
    pass "validation: \$HOME itself is refused when it carries no .git entry (403)"
  else
    fail "validation: \$HOME as the requested root returned $RESP_CODE, expected 403"
  fi
fi

# A path that exists but is a file, not a directory: whichever of the two
# refusals it takes, it must be a refusal in the documented JSON shape.
do_request "$BASE_A/project$(enc "$MAIN_PLAN")"
if [ "$RESP_CODE" = "403" ] || [ "$RESP_CODE" = "404" ]; then
  if json_error_ok; then
    pass "validation: a file rather than a directory is refused with a JSON error ($RESP_CODE)"
  else
    fail "validation: a file as the root returned $RESP_CODE without an {\"error\": ...} body"
  fi
else
  fail "validation: a file as the requested root returned $RESP_CODE, expected 403 or 404"
fi

# Edge case: a trailing slash is normalized by realpath, so it is the same page.
do_request "$BASE_A/project$(enc "$MAIN_ROOT")/"
if [ "$RESP_CODE" = "200" ] && body_has "\"/doc$(enc "$MAIN_WG")\""; then
  pass "validation: a root with a trailing slash renders the same page"
else
  fail "validation: a trailing slash on the root returned $RESP_CODE without the worktree's documents"
fi

# =============================================================================
# Behavior 7: a worktree with nothing to list is an empty state, not an error
# =============================================================================

for pair in "$EMPTY_ROOT|$L_EMPTY|no .local at all" "$NODOCS_ROOT|$L_NODOCS|a .local holding no markdown"; do
  root="${pair%%|*}"
  rest="${pair#*|}"
  label="${rest%%|*}"
  what="${rest#*|}"
  do_request "$BASE_A/project$(enc "$root")"
  if [ "$RESP_CODE" = "200" ]; then
    pass "empty state: a worktree with $what still renders a page (200)"
  else
    fail "empty state: a worktree with $what returned $RESP_CODE, expected 200"
  fi
  if body_has "$label" || body_has "$root"; then
    pass "empty state: the message names the worktree ($what)"
  else
    fail "empty state: the page for $root names neither its label \"$label\" nor its path"
  fi
  n_links="$(grep -oE 'href="/doc[^"]*"' "$BODY" 2> /dev/null | wc -l | tr -d ' ')"
  if [ "$n_links" = "0" ]; then
    pass "empty state: no document is listed for a worktree with $what"
  else
    fail "empty state: $n_links document link(s) on the page of a worktree with $what"
  fi
done

# =============================================================================
# Behavior 3 (degradation): an unparseable work graph shows both halves as
# unavailable, and never as an error
# =============================================================================

do_request "$BASE_A/project$(enc "$BROKEN_ROOT")"
if [ "$RESP_CODE" = "200" ]; then
  pass "degradation: a WORKGRAPH.md that cannot be parsed does not turn the page into an error"
else
  fail "degradation: an unparseable work graph returned $RESP_CODE, expected 200"
fi
broken_text="$(visible_text)"
if body_has "\"/doc$(enc "$BROKEN_WG")\""; then
  pass "degradation: the unparseable work graph is still listed with its link"
else
  fail "degradation: the unparseable work graph was dropped from the page"
fi
if body_has "\"/doc$(enc "$BROKEN_OTHER")\""; then
  pass "degradation: the worktree's other documents are unaffected"
else
  fail "degradation: one unparseable work graph cost the worktree its other documents"
fi
if text_matches "$broken_text" "[0-9]${WIN}open|open${WIN}[0-9]"; then
  fail "degradation: the headline claims an open-node count it could not read: $broken_text"
else
  pass "degradation: no open-node count is claimed for an unparseable work graph"
fi
n_unavail="$(text_count "$broken_text" unavailable)"
if [ "${n_unavail:-0}" -ge 2 ]; then
  pass "degradation: both the count and the Focus id show as unavailable ($n_unavail)"
elif text_matches "$broken_text" 'unavailable|unknown|not available|n/a|unreadable'; then
  fail "degradation: only one half of the headline degrades — the contract says both do: $broken_text"
else
  fail "degradation: the headline does not mark its count and Focus unavailable: $broken_text"
fi

# =============================================================================
# GET /project/for?path= — the 302 resolver
# =============================================================================

EXPECTED_LOC="/project$(enc "$MAIN_ROOT")"

# Location, with any scheme+host prefix removed so an absolute redirect target
# is compared on equal terms.
location_path() {
  python3 -c "
import re, sys
print(re.sub(r'^https?://[^/]*', '', sys.argv[1]))" "$(header_value Location)" 2> /dev/null
}

expect_redirect() { # <label> <doc path>
  local label="$1" doc="$2" loc
  do_request "$BASE_A/project/for?path=$(enc "$2")"
  if [ "$RESP_CODE" != "302" ]; then
    fail "$label: expected 302, got $RESP_CODE (path $doc)"
    return
  fi
  loc="$(location_path)"
  if [ "$loc" = "$EXPECTED_LOC" ]; then
    pass "$label (302 -> $EXPECTED_LOC)"
  else
    fail "$label: redirected to \"$loc\", expected \"$EXPECTED_LOC\""
  fi
}

expect_redirect "resolver: a served document redirects to its worktree's page" "$MAIN_PLAN"
expect_redirect "resolver: an unserved document redirects just the same" "$MAIN_NOTES"
expect_redirect "resolver: a document that does not exist still resolves to its worktree" \
  "$WT_MAIN/.local/never-created.md"
expect_redirect "resolver: a path that is not a .md file still resolves (full scope is not required)" \
  "$WT_MAIN/outside-local.md"
expect_redirect "resolver: the path is realpath'd before its worktree is found" "$LINK_DOC"

# Following the redirect must land on that worktree's own page.
do_request -L "$BASE_A/project/for?path=$(enc "$MAIN_NOTES")"
if [ "$RESP_CODE" = "200" ] && body_has "\"/doc$(enc "$MAIN_WG")\""; then
  pass "resolver: following the redirect lands on the owning worktree's landing page"
else
  fail "resolver: following the redirect returned $RESP_CODE without the worktree's documents"
fi

if [ "$LINKED_OK" -ne 1 ]; then
  skip "resolver: the linked-worktree fixture could not be built"
else
  do_request "$BASE_A/project/for?path=$(enc "$SIBLING_DOC")"
  loc="$(location_path)"
  if [ "$RESP_CODE" = "302" ] && [ "$loc" = "/project$(enc "$SIBLING_ROOT")" ]; then
    pass "resolver: a document in a linked worktree resolves to THAT worktree, not the repo's main one"
  else
    fail "resolver: a linked worktree's document redirected to \"$loc\" ($RESP_CODE)"
  fi
fi

expect_json_error "resolver: no query at all is a 400" 400 "$BASE_A/project/for"
expect_json_error "resolver: an empty path is a 400" 400 "$BASE_A/project/for?path="
expect_json_error "resolver: a query carrying no path is a 400" 400 "$BASE_A/project/for?other=x"
if [ "$OUTSIDE_OK" -eq 1 ]; then
  expect_json_error "resolver: a path outside \$HOME is a 403" 403 \
    "$BASE_A/project/for?path=$(enc "$OUTSIDE/doc.md")"
else
  skip "resolver: the temp directory is inside \$HOME here, so the outside-home clause cannot be forced"
fi

if has_git_ancestor "$LOOSE_DOC"; then
  skip "resolver: the fixture has a git ancestor here, so the no-worktree clause cannot be forced"
else
  expect_json_error "resolver: a path with no worktree ancestor is a 403" 403 \
    "$BASE_A/project/for?path=$(enc "$LOOSE_DOC")"
fi

# =============================================================================
# Invariants: Host pinning, and the whole feature is read-only
# =============================================================================

expect_code "host: a wrong Host on /project/<root> is rejected" 403 \
  -H 'Host: evil.example' "$PROJECT_MAIN"
expect_code "host: a wrong Host on /project/for is rejected" 403 \
  -H 'Host: evil.example' "$BASE_A/project/for?path=$(enc "$MAIN_PLAN")"

do_request "$PROJECT_MAIN"
do_request "$BASE_A/project$(enc "$BROKEN_ROOT")"
do_request "$BASE_A/project/for?path=$(enc "$MAIN_NOTES")"
do_request "$BASE_A/docs.json"
DOCS_AFTER="$(python3 -c "
import json, sys
print('\n'.join(sorted(e['path'] for e in json.load(open(sys.argv[1]))['docs'])))
" "$BODY" 2> /dev/null)"
if [ -n "$DOCS_BEFORE" ] && [ "$DOCS_BEFORE" = "$DOCS_AFTER" ]; then
  pass "read-only: visiting a landing page registers nothing — /docs.json is unchanged by it"
else
  fail "read-only: /docs.json changed after landing pages were served (before: $DOCS_BEFORE / after: $DOCS_AFTER)"
fi

if [ "$(manifest)" = "$MANIFEST_BEFORE" ]; then
  pass "read-only: the landing page rendered nothing and changed no fixture file"
else
  fail "read-only: the fixture tree changed while landing pages were served: $(diff <(printf '%s' "$MANIFEST_BEFORE") <(manifest) | head -5)"
fi

expect_code "server: still healthy after every landing-page path" 200 "$BASE_A/health"
expect_code "index: GET / is unaffected by this block" 200 "$BASE_A/"

if grep -q 'Traceback (most recent call last)' "$WORK/srv-a.stderr" 2> /dev/null; then
  fail "outputs: a landing-page path raised — stderr carries $(grep -oE '[A-Za-z]*Error\("[^"]*"\)|[A-Za-z]*Error' "$WORK/srv-a.stderr" | tail -1)"
else
  pass "outputs: no landing-page path wrote a traceback to the server's stderr"
fi

# =============================================================================
# Left to acceptance review
# =============================================================================
# Three things are deliberately unasserted. WHERE a registered document that
# lives outside .local is placed on the page: the contract puts it in the
# document set and says nothing about its position, so pinning one would invent
# a rule (that it is listed at all is asserted above). Whether the headline
# document itself carries the "unserved" mark, for the same reason. And how the
# page LOOKS — that the collapsed groups are usable, that the headline reads as
# a headline — which is a browser judgement the orchestrator makes at
# acceptance.

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'landing-page.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'landing-page.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'landing-page.test.sh: all assertions passed\n'
