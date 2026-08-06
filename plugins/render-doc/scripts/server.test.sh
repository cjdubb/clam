#!/usr/bin/env bash
# server.test.sh — verifies the docblock "Contract: B01 fixed-port server" in
# plugins/render-doc/scripts/serve.py, clause by clause.
#
# Ported from the upstream verification suite's server section
# (clam-code/general/skills/render-doc/scripts/smoke.sh, lines 251-412): the
# /health shape, render-on-GET freshness, the scope rejections, the ##/###
# annotate insertions and the EADDRINUSE singleton all come from there. The
# remaining groups cover contract clauses that suite did not reach.
#
# Every server started here binds a throwaway high port handed out by the
# kernel — never the default 27183 — and is killed by the EXIT trap, so a real
# render-doc server on this machine is neither disturbed nor depended on.
# Document fixtures live under $HOME because the scope rules demand a realpath
# under the home directory; they are removed by the same trap.
#
# Wall clock: two clauses are inherently slow — render.sh's 30s subprocess
# timeout and the handler's 30s per-request socket timeout. They are run
# overlapped, so the whole suite waits ~35s rather than ~65s.
#
# Out of scope here: render.sh's own pipeline (render.test.sh) and the --open
# client (open.test.sh); this file only ever talks to a server it started.

set -uo pipefail  # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVE="$SCRIPT_DIR/serve.py"
TEMPLATE="$PLUGIN_DIR/assets/template.html"

WORK="$(mktemp -d)"
HEADERS="$WORK/resp.headers"
BODY="$WORK/resp.body"

SERVER_PIDS=()
PID_PATHS=()
HOME_DIRS=()
TMP_DIRS=()

cleanup() {
  for p in ${SERVER_PIDS[@]+"${SERVER_PIDS[@]}"}; do
    [ -n "$p" ] && kill "$p" 2> /dev/null
  done
  sleep 0.2
  for p in ${SERVER_PIDS[@]+"${SERVER_PIDS[@]}"}; do
    [ -n "$p" ] && kill -9 "$p" 2> /dev/null
  done
  # rm -rf, not rm -f: one pidfile path is deliberately a directory below.
  for f in ${PID_PATHS[@]+"${PID_PATHS[@]}"}; do
    [ -n "$f" ] && rm -rf "$f"
  done
  for d in ${HOME_DIRS[@]+"${HOME_DIRS[@]}"}; do
    [ -n "$d" ] && chmod -R u+rwX "$d" 2> /dev/null; rm -rf "$d"
  done
  for d in ${TMP_DIRS[@]+"${TMP_DIRS[@]}"}; do
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
# Environment-dependent checks (root, no non-loopback address, $HOME inside a
# repo) are reported and counted, never silently turned into a pass.
skip() {
  printf 'skip: %s\n' "$*"
  SKIPPED=$((SKIPPED + 1))
}

# macOS and GNU disagree on the base64 decode flag.
if printf 'aGkK' | base64 -d > /dev/null 2>&1; then
  B64_DECODE="-d"
else
  B64_DECODE="-D"
fi

# --- Required tooling --------------------------------------------------------
# serve.py IS a python3 program; without these there is nothing to test, and a
# vacuous green is worse than a red.
MISSING=0
for tool in python3 curl git; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    fail "required tool not available: $tool"
    MISSING=1
  fi
done
if [ "$MISSING" -ne 0 ]; then
  printf 'server.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

# --- Helpers -----------------------------------------------------------------

# A port the kernel says is free right now. Never 27183: the default port may
# hold a real server, and this suite must not touch it.
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

LAST_PID=""
start_server() { # <serve.py path> <port> <stderr file>
  RENDER_DOC_PORT="$2" python3 "$1" > "$3.stdout" 2> "$3" &
  LAST_PID=$!
  SERVER_PIDS+=("$LAST_PID")
  PID_PATHS+=("/tmp/render-doc-serve-$2.pid")
}

wait_healthy() { # <base url>
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if curl -sf --max-time 1 "$1/health" > /dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

EXIT_RC=""
wait_for_exit() { # <pid> <tries>
  local pid="$1" tries="$2" i
  EXIT_RC=""
  for ((i = 0; i < tries; i++)); do
    if ! kill -0 "$pid" 2> /dev/null; then
      wait "$pid"
      EXIT_RC=$?
      return 0
    fi
    sleep 0.25
  done
  return 1
}

REQ_TIMEOUT=15
RESP_CODE=""
do_request() { # <curl args...>
  # Truncated up front: a curl that never connects writes no body file, and a
  # later assertion must read an empty file rather than a missing one.
  : > "$HEADERS"
  : > "$BODY"
  RESP_CODE="$(curl -s --max-time "$REQ_TIMEOUT" -D "$HEADERS" -o "$BODY" \
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

# Value of a top-level JSON key in the last response body, or empty.
json_field() { # <key>
  python3 - "$BODY" "$1" << 'PY' 2> /dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        obj = json.load(f)
except Exception:
    sys.exit(1)
v = obj.get(sys.argv[2])
if v is None:
    sys.exit(1)
print(v)
PY
}

# Every scope/Host rejection must carry a JSON {"error": ...} naming its rule.
expect_error_naming() { # <label> <extended regex the message must match>
  local label="$1" pat="$2" msg
  msg="$(json_field error)"
  if [ -z "$msg" ]; then
    fail "$label: response body carries no JSON \"error\" field"
  elif printf '%s' "$msg" | grep -Eqi -- "$pat"; then
    pass "$label: error names the rule (\"$msg\")"
  else
    fail "$label: error does not name the rule (\"$msg\", expected /$pat/i)"
  fi
}

enc() { # percent-encode a filesystem path for the /doc route
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$1"
}

sha_of() { # <file>
  python3 -c "import hashlib, sys
with open(sys.argv[1], 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())" "$1" 2> /dev/null
}

annotate() { # <base> <md> <section> <excerpt> <tag> <note>  -> RESP_CODE
  local base="$1" payload
  shift
  payload="$(python3 - "$@" << 'PY'
import json, sys
print(json.dumps({'md': sys.argv[1], 'section': sys.argv[2],
                  'excerpt': sys.argv[3], 'tag': sys.argv[4],
                  'note': sys.argv[5]}))
PY
)"
  do_request -X POST "$base/annotate" -H 'Content-Type: application/json' \
    -d "$payload"
}

# The line immediately after the first line equal to <literal>.
line_after() { # <file> <literal line>
  awk -v want="$2" '$0 == want { getline nxt; print nxt; exit }' "$1" 2> /dev/null
}

last_nonempty() { # <file>
  awk 'NF { last = $0 } END { print last }' "$1" 2> /dev/null
}

has_git_ancestor() { # <dir>
  local d="$1" parent
  while :; do
    [ -e "$d/.git" ] && return 0
    parent="$(dirname "$d")"
    [ "$parent" = "$d" ] && return 1
    d="$parent"
  done
}

# --- Fixtures ----------------------------------------------------------------
# Documents live under $HOME (scope rule) inside a throwaway git repo (scope
# rule). OUT_WORK is a git repo OUTSIDE $HOME; NOGIT_WORK is under $HOME with
# no .git anywhere above it.
SRV_WORK="$(mktemp -d "$HOME/.render-doc-servertest.XXXXXX")"
NOGIT_WORK="$(mktemp -d "$HOME/.render-doc-servertest-nogit.XXXXXX")"
OUT_WORK="$(mktemp -d)"
FAKE_PLUGIN="$WORK/plugin-fake"
HOME_DIRS+=("$SRV_WORK" "$NOGIT_WORK")
TMP_DIRS+=("$OUT_WORK")

git init -q "$SRV_WORK" 2> /dev/null
git init -q "$OUT_WORK" 2> /dev/null

SRV_MD="$SRV_WORK/doc.md"
cat > "$SRV_MD" << 'MD'
# Plan: server suite

## Section

Body text under the section.

### Subsection

Body text under the subsection.
MD

printf 'not markdown\n' > "$SRV_WORK/notes.txt"
printf '# Outside the home directory\n' > "$OUT_WORK/outside-home.md"
printf '# Outside any worktree\n' > "$NOGIT_WORK/outside.md"
ln -s "$NOGIT_WORK/outside.md" "$SRV_WORK/link.md"

SPACED_MD="$SRV_WORK/a spaced ünïcode doc.md"
printf '# Spaced\n\nSPACED-DOC-MARKER\n' > "$SPACED_MD"

PORT_A="$(free_port)"
BASE="http://127.0.0.1:$PORT_A"
PIDFILE_A="/tmp/render-doc-serve-$PORT_A.pid"
SRV_A_ERR="$WORK/srv-a.stderr"

# --- 1. Binding and singleton (start) ----------------------------------------
if [ -e "$PIDFILE_A" ]; then
  fail "test port $PORT_A already has a pidfile at $PIDFILE_A; aborting to avoid clobbering it"
  printf 'server.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

# Whether the retired design's state file is already lying around: only a
# file this run creates counts against the "no state file" clause.
STATE_FILE="/tmp/render-doc-serve.json"
STATE_FILE_PRESENT=0
[ -e "$STATE_FILE" ] && STATE_FILE_PRESENT=1

# No arguments: the retired state-file argument must not be required.
start_server "$SERVE" "$PORT_A" "$SRV_A_ERR"
SRV_PID="$LAST_PID"

if wait_healthy "$BASE"; then
  pass "server: starts with no arguments and is healthy on test port $PORT_A"
else
  fail "server: did not become healthy on test port $PORT_A"
fi

# The pidfile is best-effort but must be written when it can be.
if [ -f "$PIDFILE_A" ] && [ "$(cat "$PIDFILE_A" 2> /dev/null)" = "$SRV_PID" ]; then
  pass "server: pidfile $PIDFILE_A holds the server pid"
else
  fail "server: pidfile $PIDFILE_A missing or does not hold pid $SRV_PID (got \"$(cat "$PIDFILE_A" 2> /dev/null)\")"
fi

# Invariant: 127.0.0.1 only, never 0.0.0.0. Reaching the port on this host's
# routable address would prove a wildcard bind. (UDP connect: no packet is
# sent, and TEST-NET-1 needs no DNS or route.)
NONLOOP="$(python3 -c "import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(('192.0.2.1', 9))
    print(s.getsockname()[0])
except OSError:
    print('')
finally:
    s.close()" 2> /dev/null)"
case "$NONLOOP" in
  '' | 127.*)
    skip "server: no non-loopback address on this host; cannot prove the bind is not 0.0.0.0"
    ;;
  *)
    ext_code="$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' \
      "http://$NONLOOP:$PORT_A/health" 2> /dev/null)"
    ext_code="${ext_code:-000}"
    if [ "$ext_code" = "000" ]; then
      pass "server: not reachable on the routable address $NONLOOP (binds 127.0.0.1 only)"
    else
      fail "server: answered on $NONLOOP:$PORT_A with $ext_code — the bind is not loopback-only"
    fi
    ;;
esac

# --- 2. GET /health ----------------------------------------------------------
expect_code "GET /health" 200 "$BASE/health"

SERVE_SHA="$(sha_of "$SERVE")"
if python3 - "$BODY" "$SERVE_SHA" "$SRV_PID" "$PORT_A" << 'PY' 2> /dev/null
import json, sys
with open(sys.argv[1]) as f:
    h = json.load(f)
assert h['app'] == 'render-doc', h
assert h['version'] == sys.argv[2], h
assert isinstance(h['pid'], bool) is False and isinstance(h['pid'], int), h
assert h['pid'] == int(sys.argv[3]), h
assert h['port'] == int(sys.argv[4]), h
PY
then
  pass "/health: app marker, version = sha256 of serve.py on disk, int pid, bound port"
else
  fail "/health: payload does not match {app: render-doc, version: $SERVE_SHA, pid: $SRV_PID, port: $PORT_A} (got: $(cat "$BODY" 2> /dev/null))"
fi

if grep -qi '^content-type:[[:space:]]*application/json' "$HEADERS" 2> /dev/null; then
  pass "/health: served as application/json"
else
  fail "/health: Content-Type is not application/json"
fi

# Edge case: a query string is stripped before routing.
expect_code "GET /health?ts=1 (query string stripped)" 200 "$BASE/health?ts=1"

# --- 3. GET /doc/<abs-md-path> -----------------------------------------------
DOC_URL="$BASE/doc$(enc "$SRV_MD")"
SRV_MD_SHA_BEFORE="$(sha_of "$SRV_MD")"

do_request "$DOC_URL"
if [ "$RESP_CODE" = "200" ] && grep -q 'id="doc-b64"' "$BODY"; then
  pass "/doc: serves the rendered html for an absolute markdown path"
else
  fail "/doc: expected 200 with rendered html, got $RESP_CODE"
fi

if [ -f "${SRV_MD%.md}.html" ]; then
  pass "/doc: rendered the missing sibling .html on demand"
else
  fail "/doc: no sibling .html was produced for $SRV_MD"
fi

if grep -qi '^content-type:[[:space:]]*text/html' "$HEADERS" 2> /dev/null; then
  pass "/doc: served as text/html"
else
  fail "/doc: Content-Type is not text/html"
fi

clen="$(awk 'tolower($1) == "content-length:" { gsub(/\r/, "", $2); print $2; exit }' "$HEADERS" 2> /dev/null)"
blen="$(wc -c < "$BODY" | tr -d ' ')"
if [ -n "$clen" ] && [ "$clen" = "$blen" ]; then
  pass "/doc: Content-Length matches the body ($blen bytes)"
else
  fail "/doc: Content-Length \"$clen\" does not match the $blen received bytes"
fi

if [ "$(sha_of "$SRV_MD")" = "$SRV_MD_SHA_BEFORE" ]; then
  pass "/doc: serving a document does not mutate it"
else
  fail "/doc: the markdown changed while being served"
fi

# Freshness: an edited .md is re-rendered on the next GET.
sleep 1  # the edit needs a strictly newer mtime than the sibling html
printf '\nRERENDER-MARKER-a1b2c3\n' >> "$SRV_MD"
do_request "$DOC_URL"
if [ "$RESP_CODE" = "200" ]; then
  payload="$(awk '/id="doc-b64"/ { grab = 1; next } grab && /<\/script>/ { exit } grab { print }' "$BODY" | tr -d '[:space:]')"
  if printf '%s' "$payload" | base64 "$B64_DECODE" 2> /dev/null | grep -q 'RERENDER-MARKER-a1b2c3'; then
    pass "/doc: edited markdown is re-rendered on the next GET"
  else
    fail "/doc: stale content served after the markdown changed"
  fi
else
  fail "/doc: re-GET after the edit returned $RESP_CODE"
fi

# Edge case: sibling .html newer than the .md but older than the template is
# still stale. (Timestamps only — the repo's own template is never touched.)
STALE_MD="$SRV_WORK/stale.md"
STALE_HTML="$SRV_WORK/stale.html"
printf '# Stale\n\nSTALE-DOC-MARKER\n' > "$STALE_MD"
printf 'PRE-EXISTING-HTML-SENTINEL\n' > "$STALE_HTML"
touch -t 202001010000 "$STALE_MD"
touch -t 202101010000 "$STALE_HTML"
do_request "$BASE/doc$(enc "$STALE_MD")"
if [ "$RESP_CODE" = "200" ] && ! grep -q 'PRE-EXISTING-HTML-SENTINEL' "$BODY"; then
  pass "/doc: html newer than the .md but older than the template is re-rendered"
else
  fail "/doc: html older than the template was served stale (code $RESP_CODE)"
fi

# ...and the converse: a sibling newer than both is served untouched.
FRESH_MD="$SRV_WORK/fresh.md"
FRESH_HTML="$SRV_WORK/fresh.html"
printf '# Fresh\n\nFRESH-DOC-MARKER\n' > "$FRESH_MD"
printf 'UNTOUCHED-HTML-SENTINEL\n' > "$FRESH_HTML"
touch -t 202001010000 "$FRESH_MD"
touch "$FRESH_HTML"
FRESH_HTML_SHA="$(sha_of "$FRESH_HTML")"
do_request "$BASE/doc$(enc "$FRESH_MD")"
if [ "$RESP_CODE" = "200" ] && grep -q 'UNTOUCHED-HTML-SENTINEL' "$BODY"; then
  pass "/doc: an up-to-date sibling .html is served as-is"
else
  fail "/doc: up-to-date sibling .html was not served verbatim (code $RESP_CODE)"
fi
if [ "$(sha_of "$FRESH_HTML")" = "$FRESH_HTML_SHA" ]; then
  pass "/doc: an up-to-date sibling .html is not re-rendered"
else
  fail "/doc: an up-to-date sibling .html was rewritten"
fi

# Edge case: spaces and non-ASCII, percent-encoded in the URL.
do_request "$BASE/doc$(enc "$SPACED_MD")"
if [ "$RESP_CODE" = "200" ] && grep -q 'id="doc-b64"' "$BODY"; then
  pass "/doc: percent-encoded path with spaces and non-ASCII is decoded and served"
else
  fail "/doc: percent-encoded path with spaces/non-ASCII returned $RESP_CODE"
fi

expect_code "/doc: query string stripped before routing" 200 "$DOC_URL?highlight=1"

# Errors: unknown routes.
expect_code "unknown GET route rejected" 404 "$BASE/nope"
expect_code "POST to a route other than /annotate rejected" 404 \
  -X POST "$BASE/health" -H 'Content-Type: application/json' -d '{}'

# --- 4. Scope rules ----------------------------------------------------------
# Order matters: .md check, then existence, then $HOME, then git worktree.
expect_code "scope: non-.md path rejected" 403 "$BASE/doc$(enc "$SRV_WORK/notes.txt")"
expect_error_naming "scope: non-.md path" '\.md|markdown'

expect_code "scope: missing .md rejected" 404 "$BASE/doc$(enc "$SRV_WORK/absent.md")"
expect_error_naming "scope: missing .md" 'not found|missing|exist'

expect_code "scope: .md outside the home directory rejected" 403 \
  "$BASE/doc$(enc "$OUT_WORK/outside-home.md")"
expect_error_naming "scope: outside the home directory" 'home'

if has_git_ancestor "$NOGIT_WORK"; then
  skip "scope: \$HOME sits inside a git worktree here, so no path under it can test the worktree rule"
else
  expect_code "scope: .md outside any git worktree rejected" 403 \
    "$BASE/doc$(enc "$NOGIT_WORK/outside.md")"
  expect_error_naming "scope: outside a git worktree" 'git|worktree'
fi

# Precedence: a non-.md path that also does not exist must fail the .md rule
# (403), and a missing .md outside $HOME must fail the existence rule (404).
expect_code "scope: .md rule is checked before existence" 403 \
  "$BASE/doc$(enc "$SRV_WORK/absent.txt")"
expect_code "scope: existence is checked before the home-directory rule" 404 \
  "$BASE/doc$(enc "$OUT_WORK/absent.md")"

# Realpath, before any read: a symlink inside the worktree pointing at a file
# outside it is rejected, and nothing is rendered at either end.
expect_code "scope: symlink escaping the worktree rejected" 403 \
  "$BASE/doc$(enc "$SRV_WORK/link.md")"
if [ -e "$SRV_WORK/link.html" ] || [ -e "$NOGIT_WORK/outside.html" ]; then
  fail "scope: the symlinked document was rendered despite the rejection"
else
  pass "scope: the rejected symlink was never read or rendered"
fi

# The same rules gate /annotate.
NOTES_SHA="$(sha_of "$SRV_WORK/notes.txt")"
annotate "$BASE" "$SRV_WORK/notes.txt" "Section" "" "COMMENT" "nope"
if [ "$RESP_CODE" = "403" ]; then
  pass "/annotate: non-.md target rejected (403)"
else
  fail "/annotate: non-.md target expected 403, got $RESP_CODE"
fi
if [ "$(sha_of "$SRV_WORK/notes.txt")" = "$NOTES_SHA" ]; then
  pass "/annotate: a scope-rejected target is left unmodified"
else
  fail "/annotate: a scope-rejected target was written to"
fi

OUTSIDE_SHA="$(sha_of "$OUT_WORK/outside-home.md")"
annotate "$BASE" "$OUT_WORK/outside-home.md" "Section" "" "COMMENT" "nope"
if [ "$RESP_CODE" = "403" ]; then
  pass "/annotate: target outside the home directory rejected (403)"
else
  fail "/annotate: target outside the home directory expected 403, got $RESP_CODE"
fi
if [ "$(sha_of "$OUT_WORK/outside-home.md")" = "$OUTSIDE_SHA" ]; then
  pass "/annotate: an out-of-scope document is left unmodified"
else
  fail "/annotate: an out-of-scope document was written to"
fi

annotate "$BASE" "$SRV_WORK/absent.md" "Section" "" "COMMENT" "nope"
if [ "$RESP_CODE" = "404" ]; then
  pass "/annotate: missing target rejected (404)"
else
  fail "/annotate: missing target expected 404, got $RESP_CODE"
fi

# --- 5. Host pinning ---------------------------------------------------------
expect_code "host: wrong Host on /health rejected" 403 \
  -H 'Host: evil.example' "$BASE/health"
expect_error_naming "host: wrong Host" 'host'

# "localhost:<port>" USED to be rejected here, as one more name that is not the
# literal address. Plan 002's "Contract: 002-B07 hostname allowlist + dual
# bind" widened the accepted set to four loopback-only names, localhost among
# them, so the old expectation now contradicts the contract this server is
# built to. What the check is really for — that a name outside the accepted set
# is still turned away before routing — is kept, with a name that is outside
# it under both the old rule and the new one. hostname-allowlist.test.sh owns
# the full accepted/rejected frontier.
expect_code "host: a name outside the accepted set is not 127.0.0.1:<port>" 403 \
  -H "Host: localhost.evil.example:$PORT_A" "$DOC_URL"

# "before any routing": an unknown route with a bad Host is 403, not 404.
expect_code "host: checked before routing (unknown route yields 403, not 404)" 403 \
  -H 'Host: evil.example' "$BASE/nope"

HOST_MD="$SRV_WORK/host.md"
printf '# Host\n\n## Section\n\nBody.\n' > "$HOST_MD"
HOST_SHA="$(sha_of "$HOST_MD")"
payload="$(python3 -c "import json, sys; print(json.dumps({'md': sys.argv[1], 'section': 'Section', 'excerpt': '', 'tag': 'COMMENT', 'note': 'nope'}))" "$HOST_MD")"
expect_code "host: wrong Host on /annotate rejected" 403 \
  -X POST -H 'Host: evil.example' -H 'Content-Type: application/json' \
  -d "$payload" "$BASE/annotate"
if [ "$(sha_of "$HOST_MD")" = "$HOST_SHA" ]; then
  pass "host: a Host-rejected annotate writes nothing"
else
  fail "host: a Host-rejected annotate modified the document"
fi

# --- 6. POST /annotate -------------------------------------------------------
annotate "$BASE" "$SRV_MD" "Section" "" "COMMENT" "smoke"
if [ "$RESP_CODE" = "200" ] && [ "$(json_field ok)" = "True" ]; then
  pass "/annotate: 200 {\"ok\": true}"
else
  fail "/annotate: expected 200 {\"ok\": true}, got $RESP_CODE $(cat "$BODY" 2> /dev/null)"
fi
if [ "$(line_after "$SRV_MD" '## Section')" = "@COMMENT: smoke" ]; then
  pass "/annotate: the line lands directly under the ## heading"
else
  fail "/annotate: missing or misplaced under '## Section' (got \"$(line_after "$SRV_MD" '## Section')\")"
fi

annotate "$BASE" "$SRV_MD" "Subsection" "" "QUESTION" "smoke-sub"
if [ "$(line_after "$SRV_MD" '### Subsection')" = "@QUESTION: smoke-sub" ]; then
  pass "/annotate: the line lands directly under the ### heading"
else
  fail "/annotate: missing or misplaced under '### Subsection' (got \"$(line_after "$SRV_MD" '### Subsection')\")"
fi

# Section matching: case-insensitive, inline markdown stripped, whitespace
# collapsed.
CASE_MD="$SRV_WORK/case.md"
printf '# Case\n\n## **Bold** Heading\n\nBody.\n' > "$CASE_MD"
annotate "$BASE" "$CASE_MD" "bold heading" "" "COMMENT" "case"
if [ "$(line_after "$CASE_MD" '## **Bold** Heading')" = "@COMMENT: case" ]; then
  pass "/annotate: section matched case-insensitively with inline markdown stripped"
else
  fail "/annotate: '## **Bold** Heading' not matched by section \"bold heading\""
fi

WS_MD="$SRV_WORK/whitespace.md"
printf '# Whitespace\n\n## Spaced Heading\n\nBody.\n' > "$WS_MD"
annotate "$BASE" "$WS_MD" "  Spaced   Heading  " "" "COMMENT" "ws"
if [ "$(line_after "$WS_MD" '## Spaced Heading')" = "@COMMENT: ws" ]; then
  pass "/annotate: section whitespace is collapsed before matching"
else
  fail "/annotate: '## Spaced Heading' not matched by a section with padded whitespace"
fi

# Excerpt targeting inside the section.
excerpt_fixture() { # <file>
  cat > "$1" << 'MD'
# Excerpt

## Alpha

First body line.
The excerpt target line with a distinctive TOKEN inside.
Third body line.

## Beta

A line only in the Beta section.
MD
}

EX_MD="$SRV_WORK/excerpt.md"
excerpt_fixture "$EX_MD"
annotate "$BASE" "$EX_MD" "Alpha" "excerpt target line" "CONCERN" "hit"
if [ "$(line_after "$EX_MD" 'The excerpt target line with a distinctive TOKEN inside.')" = "@CONCERN: hit" ]; then
  pass "/annotate: a matching excerpt places the line after the excerpt line"
else
  fail "/annotate: excerpt match did not place the line after the excerpt line"
fi

# Trailing "…" is removed before comparison: without that, this excerpt
# matches nothing and the line would fall back under the heading.
EX_ELL_MD="$SRV_WORK/excerpt-ellipsis.md"
excerpt_fixture "$EX_ELL_MD"
annotate "$BASE" "$EX_ELL_MD" "Alpha" "excerpt target line…" "CONCERN" "ell"
if [ "$(line_after "$EX_ELL_MD" 'The excerpt target line with a distinctive TOKEN inside.')" = "@CONCERN: ell" ]; then
  pass "/annotate: a trailing ellipsis is stripped from the excerpt before matching"
else
  fail "/annotate: excerpt with a trailing ellipsis did not match its line"
fi

# Truncation to 40 chars: everything past char 40 is junk that appears
# nowhere in the document, so only a truncated comparison can match.
EX_LONG_MD="$SRV_WORK/excerpt-long.md"
excerpt_fixture "$EX_LONG_MD"
annotate "$BASE" "$EX_LONG_MD" "Alpha" \
  "The excerpt target line with a distinctive TOKEN inside. JUNK-NOT-IN-THE-DOCUMENT" \
  "CONCERN" "long"
if [ "$(line_after "$EX_LONG_MD" 'The excerpt target line with a distinctive TOKEN inside.')" = "@CONCERN: long" ]; then
  pass "/annotate: the excerpt is truncated to 40 characters before matching"
else
  fail "/annotate: over-long excerpt was not truncated to 40 characters"
fi

# Excerpt compared with inline markdown stripped from the line.
EX_MD_MD="$SRV_WORK/excerpt-inline.md"
cat > "$EX_MD_MD" << 'MD'
# Inline

## Alpha

A line with **bold** and `code` words.
Another line.
MD
annotate "$BASE" "$EX_MD_MD" "Alpha" "A line with bold and code words." "CONCERN" "inline"
if [ "$(line_after "$EX_MD_MD" 'A line with **bold** and `code` words.')" = "@CONCERN: inline" ]; then
  pass "/annotate: excerpt matching strips inline markdown from the candidate line"
else
  fail "/annotate: excerpt did not match a line whose inline markdown must be stripped"
fi

# The search stops at the next ##/### heading: an excerpt that only occurs in
# a later section must not be used.
EX_STOP_MD="$SRV_WORK/excerpt-stop.md"
excerpt_fixture "$EX_STOP_MD"
annotate "$BASE" "$EX_STOP_MD" "Alpha" "A line only in the Beta section." "CONCERN" "stop"
if [ "$(line_after "$EX_STOP_MD" '## Alpha')" = "@CONCERN: stop" ]; then
  pass "/annotate: excerpt search stops at the next heading and falls back under the section"
else
  fail "/annotate: excerpt from a later section was used (search did not stop at the next heading)"
fi

# Excerpt present nowhere: fall back to the line under the heading.
EX_MISS_MD="$SRV_WORK/excerpt-miss.md"
excerpt_fixture "$EX_MISS_MD"
annotate "$BASE" "$EX_MISS_MD" "Alpha" "NO-SUCH-EXCERPT-ANYWHERE" "CONCERN" "miss"
if [ "$(line_after "$EX_MISS_MD" '## Alpha')" = "@CONCERN: miss" ]; then
  pass "/annotate: an unmatched excerpt falls back to the line under the heading"
else
  fail "/annotate: unmatched excerpt did not fall back under the heading"
fi

# Edge case: the section is absent -> append at the end of the file.
EOF_MD="$SRV_WORK/no-section.md"
printf '# Only a title\n\nSome prose.\n' > "$EOF_MD"
annotate "$BASE" "$EOF_MD" "Nowhere" "" "COMMENT" "appended"
if [ "$(last_nonempty "$EOF_MD")" = "@COMMENT: appended" ]; then
  pass "/annotate: an absent section appends the line at the end of the file"
else
  fail "/annotate: absent section did not append at the end (last line \"$(last_nonempty "$EOF_MD")\")"
fi

# Edge case: an empty note yields "@TAG:" with no trailing space.
EMPTY_MD="$SRV_WORK/empty-note.md"
printf '# Empty\n\n## Section\n\nBody.\n' > "$EMPTY_MD"
annotate "$BASE" "$EMPTY_MD" "Section" "" "APPROVE" ""
if [ "$(line_after "$EMPTY_MD" '## Section')" = "@APPROVE:" ]; then
  pass "/annotate: an empty note writes \"@APPROVE:\" with no trailing space"
else
  fail "/annotate: empty note produced \"$(line_after "$EMPTY_MD" '## Section')\", expected \"@APPROVE:\""
fi

# Edge case: query string on /annotate is stripped before routing.
QS_MD="$SRV_WORK/querystring.md"
printf '# Query\n\n## Section\n\nBody.\n' > "$QS_MD"
qs_payload="$(python3 -c "import json, sys; print(json.dumps({'md': sys.argv[1], 'section': 'Section', 'excerpt': '', 'tag': 'COMMENT', 'note': 'qs'}))" "$QS_MD")"
expect_code "/annotate: query string stripped before routing" 200 \
  -X POST -H 'Content-Type: application/json' -d "$qs_payload" \
  "$BASE/annotate?from=view"

# The read-modify-write is locked: concurrent annotates cannot lose lines.
RACE_MD="$SRV_WORK/race.md"
printf '# Race\n\n## Race\n\nBody.\n' > "$RACE_MD"
race_pids=()
for i in 1 2 3 4 5 6 7 8; do
  (
    p="$(python3 -c "import json, sys; print(json.dumps({'md': sys.argv[1], 'section': 'Race', 'excerpt': '', 'tag': 'RACE', 'note': sys.argv[2]}))" "$RACE_MD" "line-$i")"
    curl -s --max-time 10 -o /dev/null -X POST "$BASE/annotate" \
      -H 'Content-Type: application/json' -d "$p"
  ) &
  race_pids+=("$!")
done
for p in ${race_pids[@]+"${race_pids[@]}"}; do
  wait "$p" 2> /dev/null
done
race_lines="$(grep -c '^@RACE: line-' "$RACE_MD" 2> /dev/null)"
: "${race_lines:=0}"
if [ "$race_lines" -eq 8 ]; then
  pass "/annotate: 8 concurrent annotations all survive (the write is serialized)"
else
  fail "/annotate: expected 8 concurrent annotations, found $race_lines"
fi

# Errors: a malformed body is a 400 with a fixed message.
do_request -X POST "$BASE/annotate" -H 'Content-Type: application/json' \
  -d 'this is not json'
if [ "$RESP_CODE" = "400" ] && [ "$(json_field error)" = "invalid JSON body" ]; then
  pass "/annotate: malformed JSON body -> 400 {\"error\": \"invalid JSON body\"}"
else
  fail "/annotate: malformed body expected 400 invalid JSON body, got $RESP_CODE $(cat "$BODY" 2> /dev/null)"
fi

# --- 7. Render failure paths -------------------------------------------------
# A copy of the plugin whose render.sh is a test double, driven by the
# document's name. Using the copy also proves the server resolves render.sh
# from ITS OWN directory: the real render.sh would succeed on these inputs.
cp -r "$PLUGIN_DIR" "$FAKE_PLUGIN"
cat > "$FAKE_PLUGIN/scripts/render.sh" << 'SH'
#!/usr/bin/env bash
# Test double for render.sh; behaviour chosen by the document's name.
case "$1" in
  *sleepdoc*) sleep 60 ;;
  *faildoc*)
    printf 'fake render: earlier stderr line\n' >&2
    printf 'FAKE-RENDER-LAST-LINE\n' >&2
    exit 3
    ;;
  *) printf '<html>fake render output</html>\n' > "${1%.md}.html" ;;
esac
SH
chmod +x "$FAKE_PLUGIN/scripts/render.sh"

PORT_C="$(free_port)"
BASE_C="http://127.0.0.1:$PORT_C"
start_server "$FAKE_PLUGIN/scripts/serve.py" "$PORT_C" "$WORK/srv-c.stderr"
if wait_healthy "$BASE_C"; then
  pass "server: a second server on its own port serves from its own directory"
else
  fail "server: the render-failure server did not become healthy on port $PORT_C"
fi

printf '# Fail\n' > "$SRV_WORK/faildoc.md"
do_request "$BASE_C/doc$(enc "$SRV_WORK/faildoc.md")"
err_msg="$(json_field error)"
case "$err_msg" in
  *FAKE-RENDER-LAST-LINE) ends_with_stderr=1 ;;
  *) ends_with_stderr=0 ;;
esac
if [ "$RESP_CODE" = "500" ] && [ "$ends_with_stderr" -eq 1 ]; then
  pass "/doc: render.sh exiting non-zero -> 500 ending with its last stderr line"
else
  fail "/doc: render failure expected 500 ending in FAKE-RENDER-LAST-LINE, got $RESP_CODE \"$err_msg\""
fi

# Invariant: a silent connection cannot wedge a thread forever (30s
# per-request socket timeout), and other requests are served meanwhile
# (threading server). Started here so its 30s overlaps the render timeout.
python3 - "$PORT_A" > "$WORK/silent.out" 2>&1 << 'PY' &
import socket, sys, time
s = socket.create_connection(('127.0.0.1', int(sys.argv[1])), timeout=5)
s.settimeout(50)
start = time.time()
try:
    data = s.recv(1)
except OSError:
    data = None
elapsed = time.time() - start
print('closed' if data == b'' else 'open', round(elapsed, 1))
PY
SILENT_PID=$!

sleep 1
expect_code "server: a silent connection does not block other requests (threading)" 200 "$BASE/health"

# render.sh timing out -> 500 {"error": "render timed out"} after ~30s.
printf '# Sleep\n' > "$SRV_WORK/sleepdoc.md"
REQ_TIMEOUT=60
do_request "$BASE_C/doc$(enc "$SRV_WORK/sleepdoc.md")"
REQ_TIMEOUT=15
if [ "$RESP_CODE" = "500" ] && [ "$(json_field error)" = "render timed out" ]; then
  pass "/doc: render.sh exceeding its 30s timeout -> 500 {\"error\": \"render timed out\"}"
else
  fail "/doc: render timeout expected 500 render timed out, got $RESP_CODE $(cat "$BODY" 2> /dev/null)"
fi

wait "$SILENT_PID" 2> /dev/null
silent_result="$(cat "$WORK/silent.out" 2> /dev/null)"
case "$silent_result" in
  closed*)
    secs="${silent_result#closed }"
    if python3 -c "import sys; sys.exit(0 if 20 <= float(sys.argv[1]) <= 45 else 1)" "$secs" 2> /dev/null; then
      pass "server: a silent connection is dropped by the 30s socket timeout (after ${secs}s)"
    else
      fail "server: silent connection dropped after ${secs}s, expected roughly 30s"
    fi
    ;;
  *) fail "server: silent connection was not dropped by a per-request timeout ($(tail -1 "$WORK/silent.out" 2> /dev/null))" ;;
esac

# render.sh that cannot be started at all -> 500 naming the OSError.
if [ "$(id -u)" -eq 0 ]; then
  skip "/doc: running as root, so a non-executable render.sh would still start"
else
  chmod -x "$FAKE_PLUGIN/scripts/render.sh"
  printf '# Nostart\n' > "$SRV_WORK/nostartdoc.md"
  do_request "$BASE_C/doc$(enc "$SRV_WORK/nostartdoc.md")"
  err_msg="$(json_field error)"
  if [ "$RESP_CODE" = "500" ] && printf '%s' "$err_msg" | grep -qi 'permission denied'; then
    pass "/doc: render.sh failing to start -> 500 naming the OSError"
  else
    fail "/doc: unstartable render.sh expected 500 naming the OSError, got $RESP_CODE \"$err_msg\""
  fi
  chmod +x "$FAKE_PLUGIN/scripts/render.sh"
fi

# An unreadable rendered .html -> 500 naming the OSError.
if [ "$(id -u)" -eq 0 ]; then
  skip "/doc: running as root, so a 0600-cleared .html would still be readable"
else
  UNREAD_MD="$SRV_WORK/unreadable.md"
  UNREAD_HTML="$SRV_WORK/unreadable.html"
  printf '# Unreadable\n' > "$UNREAD_MD"
  printf '<html>unreadable</html>\n' > "$UNREAD_HTML"
  touch -t 202001010000 "$UNREAD_MD"
  touch "$UNREAD_HTML"
  chmod 000 "$UNREAD_HTML"
  do_request "$BASE/doc$(enc "$UNREAD_MD")"
  err_msg="$(json_field error)"
  if [ "$RESP_CODE" = "500" ] && [ -n "$err_msg" ]; then
    pass "/doc: an unreadable rendered .html -> 500 naming the OSError"
  else
    fail "/doc: unreadable .html expected 500 with an error message, got $RESP_CODE \"$err_msg\""
  fi
  chmod 644 "$UNREAD_HTML"
fi

# No error path leaks a traceback to the client.
if grep -q 'Traceback (most recent call last)' "$BODY" 2> /dev/null; then
  fail "errors: a traceback leaked into the response body"
else
  pass "errors: no traceback leaked into the response body"
fi

# --- 8. Outputs and invariants ----------------------------------------------
# Request logging is suppressed entirely; and after every error path above the
# main server is still up, so nothing crashed it.
if grep -Eq 'HTTP/1\.|"GET |"POST |code 404|code 403' "$SRV_A_ERR" 2> /dev/null; then
  fail "outputs: per-request logging reached the server's stderr"
elif grep -q 'Traceback (most recent call last)' "$SRV_A_ERR" 2> /dev/null; then
  fail "outputs: the server's stderr carries a traceback"
else
  pass "outputs: the server logs no per-request noise and no traceback to stderr"
fi

expect_code "server: still healthy after every error path" 200 "$BASE/health"

# There is no state file: the server's only /tmp artefact is its pidfile.
if [ "$STATE_FILE_PRESENT" -eq 1 ]; then
  skip "invariant: $STATE_FILE already existed before this run; cannot attribute it"
elif [ -e "$STATE_FILE" ]; then
  fail "invariant: the server created a state file at $STATE_FILE"
else
  pass "invariant: the server writes no state file"
fi

# The only document the server wrote outside /tmp is the annotated markdown
# (plus the sibling .html render.sh produces for it).
unexpected="$(find "$SRV_WORK" -maxdepth 1 -type f ! -name '*.md' ! -name '*.html' ! -name 'notes.txt' 2> /dev/null | wc -l | tr -d ' ')"
if [ "$unexpected" -eq 0 ]; then
  pass "invariant: the server created no files beyond the documents and their siblings"
else
  fail "invariant: $unexpected unexpected file(s) appeared in the document directory"
fi

# --- 9. Singleton, pidfile and shutdown --------------------------------------
# A second instance on the occupied port loses the bind race: stderr
# diagnostic, exit 0, and the winner keeps serving.
RENDER_DOC_PORT="$PORT_A" python3 "$SERVE" > "$WORK/second.out" 2> "$WORK/second.err" &
SECOND_PID=$!
SERVER_PIDS+=("$SECOND_PID")
if wait_for_exit "$SECOND_PID" 16; then
  if [ "$EXIT_RC" = "0" ]; then
    pass "singleton: a second instance on a bound port exits 0"
  else
    fail "singleton: a second instance exited $EXIT_RC, expected 0"
  fi
else
  kill "$SECOND_PID" 2> /dev/null
  fail "singleton: a second instance did not exit promptly"
fi
if [ -s "$WORK/second.err" ] && grep -q "$PORT_A" "$WORK/second.err"; then
  pass "singleton: the losing instance prints a diagnostic naming the port to stderr"
else
  fail "singleton: no stderr diagnostic naming port $PORT_A from the losing instance"
fi
expect_code "singleton: the winner still answers after the race" 200 "$BASE/health"

# Edge case: two instances started concurrently — exactly one binds, the other
# exits 0, and the winner answers.
PORT_E="$(free_port)"
BASE_E="http://127.0.0.1:$PORT_E"
PID_PATHS+=("/tmp/render-doc-serve-$PORT_E.pid")
RENDER_DOC_PORT="$PORT_E" python3 "$SERVE" > /dev/null 2> "$WORK/race-1.err" &
RACE1=$!
RENDER_DOC_PORT="$PORT_E" python3 "$SERVE" > /dev/null 2> "$WORK/race-2.err" &
RACE2=$!
SERVER_PIDS+=("$RACE1" "$RACE2")
survivors=0
for p in "$RACE1" "$RACE2"; do
  if wait_for_exit "$p" 16; then
    if [ "$EXIT_RC" != "0" ]; then
      fail "singleton race: the losing instance exited $EXIT_RC, expected 0"
    fi
  else
    survivors=$((survivors + 1))
  fi
done
if [ "$survivors" -eq 1 ]; then
  pass "singleton race: exactly one of two concurrent instances keeps running"
else
  fail "singleton race: $survivors of 2 concurrent instances survived, expected exactly 1"
fi
expect_code "singleton race: the winner serves /health" 200 "$BASE_E/health"

# Best-effort pidfile: an unwritable pidfile path is not fatal.
PORT_F="$(free_port)"
BASE_F="http://127.0.0.1:$PORT_F"
PIDFILE_F="/tmp/render-doc-serve-$PORT_F.pid"
PID_PATHS+=("$PIDFILE_F")
mkdir -p "$PIDFILE_F"
start_server "$SERVE" "$PORT_F" "$WORK/srv-f.stderr"
if wait_healthy "$BASE_F"; then
  pass "pidfile: a pidfile that cannot be written is not fatal (the server still serves)"
else
  fail "pidfile: the server did not serve when its pidfile path was unwritable"
fi

# SIGTERM: remove the pidfile and exit 0.
PORT_D="$(free_port)"
BASE_D="http://127.0.0.1:$PORT_D"
PIDFILE_D="/tmp/render-doc-serve-$PORT_D.pid"
start_server "$SERVE" "$PORT_D" "$WORK/srv-d.stderr"
TERM_PID="$LAST_PID"
if wait_healthy "$BASE_D"; then
  pass "shutdown: the shutdown fixture server is healthy on port $PORT_D"
else
  fail "shutdown: the shutdown fixture server did not become healthy on port $PORT_D"
fi
# The removal check below means nothing unless the pidfile was there first.
if [ -f "$PIDFILE_D" ]; then
  pass "shutdown: the pidfile exists while the server runs"
else
  fail "shutdown: no pidfile at $PIDFILE_D while the server was running"
fi
kill -TERM "$TERM_PID" 2> /dev/null
if wait_for_exit "$TERM_PID" 20; then
  if [ "$EXIT_RC" = "0" ]; then
    pass "shutdown: SIGTERM exits 0"
  else
    fail "shutdown: SIGTERM exited $EXIT_RC, expected 0"
  fi
else
  fail "shutdown: the server did not exit on SIGTERM"
fi
if [ -e "$PIDFILE_D" ]; then
  fail "shutdown: the pidfile $PIDFILE_D survived SIGTERM"
else
  pass "shutdown: the pidfile is removed on SIGTERM"
fi

# Any OSError other than EADDRINUSE propagates: a privileged port must not be
# swallowed into a quiet exit 0.
if [ "$(id -u)" -eq 0 ]; then
  skip "binding: running as root, so a privileged port would bind successfully"
elif python3 -c "import socket, sys
s = socket.socket()
try:
    s.bind(('127.0.0.1', 1))
    s.close()
except OSError:
    sys.exit(1)" 2> /dev/null; then
  skip "binding: port 1 is bindable here, so no OSError to propagate"
else
  RENDER_DOC_PORT=1 python3 "$SERVE" > /dev/null 2> "$WORK/priv.err" &
  PRIV_PID=$!
  SERVER_PIDS+=("$PRIV_PID")
  if wait_for_exit "$PRIV_PID" 20; then
    if [ "$EXIT_RC" != "0" ]; then
      pass "binding: an OSError other than EADDRINUSE propagates (exit $EXIT_RC)"
    else
      fail "binding: a non-EADDRINUSE bind failure exited 0 instead of propagating"
    fi
  else
    kill "$PRIV_PID" 2> /dev/null
    fail "binding: the server did not exit after failing to bind a privileged port"
  fi
fi

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'server.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'server.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'server.test.sh: all assertions passed\n'
