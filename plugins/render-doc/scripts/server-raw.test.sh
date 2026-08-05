#!/usr/bin/env bash
# server-raw.test.sh — verifies the docblock "Contract: B01 raw-doc route" on
# Handler._serve_raw in plugins/render-doc/scripts/serve.py, clause by clause.
#
# /raw is the polling target for a live-updating page: it hands back the CURRENT
# bytes of the source markdown with a sha256 ETag, so a page that already holds
# those bytes can ask again cheaply and get a 304. Everything asserted here is a
# clause of that docblock — the response shape, the conditional-request rules,
# the scope rules it shares with /doc and /annotate, and the read-only invariant
# that separates it from /doc.
#
# Every server started here binds a throwaway high port handed out by the kernel
# — never the default 27183, where a real server may be running — and is killed
# by the EXIT trap. Document fixtures live under $HOME (the scope rules demand a
# realpath under the home directory) inside a throwaway git repo (the scope
# rules demand a worktree); the same trap removes them, along with the
# /tmp/render-doc-registry-<port>.json file the registry writes for this port.
#
# The two clauses that reach outside this route are asserted only as far as
# their /raw half goes:
#   - registry recording (B01 clause 6) is observed through /docs.json, since
#     that is the only way a client can see it; the registry's own semantics
#     belong to server-registry.test.sh.
#   - the loopback-only bind and the no-traceback rule are properties of the
#     whole server (server.test.sh); this file only re-checks that /raw's own
#     error paths do not break them.
#
# Out of scope here: /doc's rendering pipeline and /annotate (server.test.sh),
# render.sh itself (render.test.sh).

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVE="$SCRIPT_DIR/serve.py"

WORK="$(mktemp -d)"
HEADERS="$WORK/resp.headers"
BODY="$WORK/resp.body"

SERVER_PIDS=()
TMP_ARTEFACTS=()
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
  for f in ${TMP_ARTEFACTS[@]+"${TMP_ARTEFACTS[@]}"}; do
    [ -n "$f" ] && rm -rf "$f"
  done
  # chmod first: one fixture is deliberately mode 000.
  for d in ${HOME_DIRS[@]+"${HOME_DIRS[@]}"}; do
    [ -n "$d" ] && chmod -R u+rwX "$d" 2> /dev/null
    [ -n "$d" ] && rm -rf "$d"
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
# Environment-dependent checks (root, $HOME inside a repo) are reported and
# counted, never silently turned into a pass.
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
if [ "$MISSING" -ne 0 ]; then
  printf 'server-raw.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
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
start_server() { # <port> <stderr file>
  RENDER_DOC_PORT="$1" python3 "$SERVE" > "$2.stdout" 2> "$2" &
  LAST_PID=$!
  SERVER_PIDS+=("$LAST_PID")
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
  # Truncated up front: a curl that never connects writes no body file, and a
  # later assertion must read an empty file rather than a missing one.
  : > "$HEADERS"
  : > "$BODY"
  RESP_CODE="$(curl -s --max-time 15 -D "$HEADERS" -o "$BODY" \
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

enc() { # percent-encode a filesystem path for the /raw route
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$1"
}

sha_of() { # <file>
  python3 -c "import hashlib, sys
with open(sys.argv[1], 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())" "$1" 2> /dev/null
}

header_value() { # <header name>
  awk -v want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]'):" '
    { k = tolower($1) }
    k == want { sub(/\r$/, "", $2); print $2; exit }
  ' "$HEADERS" 2> /dev/null
}

body_bytes() { wc -c < "$BODY" | tr -d ' '; }

has_git_ancestor() { # <dir>
  local d="$1" parent
  while :; do
    [ -e "$d/.git" ] && return 0
    parent="$(dirname "$d")"
    [ "$parent" = "$d" ] && return 1
    d="$parent"
  done
}

realpath_of() { # <path>
  python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$1" 2> /dev/null
}

# Numeric comparison in python, not test -gt: the contract calls last-served "a
# number", so an implementation is free to store a float, and a shell integer
# comparison would fail a legal one.
num_gt() { # <a> <b>  -> true when a > b
  python3 -c "import sys
try:
    sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)
except ValueError:
    sys.exit(1)" "$1" "$2" 2> /dev/null
}

# lastServed for <path> in the last /docs.json body, or empty. Used only for
# clause 6 (a successful /raw serve is recorded); the registry's own semantics
# are server-registry.test.sh's subject.
docs_json_time() { # <realpath>
  python3 - "$BODY" "$1" << 'PY' 2> /dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        obj = json.load(f)
    for e in obj['docs']:
        if e['path'] == sys.argv[2]:
            print(e['lastServed'])
            break
except Exception:
    sys.exit(1)
PY
}

# --- Fixtures ----------------------------------------------------------------
RAW_WORK="$(mktemp -d "$HOME/.render-doc-rawtest.XXXXXX")"
NOGIT_WORK="$(mktemp -d "$HOME/.render-doc-rawtest-nogit.XXXXXX")"
OUT_WORK="$(mktemp -d)"
HOME_DIRS+=("$RAW_WORK" "$NOGIT_WORK")
TMP_DIRS+=("$OUT_WORK")

git init -q "$RAW_WORK" 2> /dev/null
git init -q "$OUT_WORK" 2> /dev/null

RAW_MD="$RAW_WORK/doc.md"
printf '# Raw\n\nFirst body line.\nSecond body line.\n' > "$RAW_MD"
# Taken before any request: the mutation check below is worthless if its
# "before" value is read after the serve it is supposed to be watching.
RAW_MD_SHA_BEFORE="$(python3 -c "import hashlib, sys
with open(sys.argv[1], 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())" "$RAW_MD")"

EMPTY_MD="$RAW_WORK/empty.md"
: > "$EMPTY_MD"

SPACED_MD="$RAW_WORK/a spaced ünïcode doc.md"
printf '# Spaced\n\nSPACED-RAW-MARKER\n' > "$SPACED_MD"

printf 'not markdown\n' > "$RAW_WORK/notes.txt"
printf '# Outside the home directory\n' > "$OUT_WORK/outside-home.md"
printf '# Outside any worktree\n' > "$NOGIT_WORK/outside.md"
ln -s "$NOGIT_WORK/outside.md" "$RAW_WORK/link.md"

# Clause 5's fixture: a document whose sibling .html is deliberately STALE.
# /doc would re-render it; /raw must leave it exactly as it is.
STALE_MD="$RAW_WORK/stale.md"
STALE_HTML="$RAW_WORK/stale.html"
printf '# Stale\n\nSTALE-RAW-MARKER\n' > "$STALE_MD"
printf 'PRE-EXISTING-HTML-SENTINEL\n' > "$STALE_HTML"
touch -t 202101010000 "$STALE_HTML"
touch "$STALE_MD"

PORT_A="$(free_port)"
BASE="http://127.0.0.1:$PORT_A"
SRV_ERR="$WORK/srv-a.stderr"

start_server "$PORT_A" "$SRV_ERR"
if wait_healthy "$BASE"; then
  pass "server: healthy on test port $PORT_A"
else
  fail "server: did not become healthy on test port $PORT_A — no /raw clause can be checked"
  printf 'server-raw.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

RAW_URL="$BASE/raw$(enc "$RAW_MD")"

# =============================================================================
# Clause 3: a successful response — 200, text/plain, correct Content-Length,
# the file's raw bytes, and a quoted sha256 ETag over exactly those bytes.
# =============================================================================

do_request "$RAW_URL"
if [ "$RESP_CODE" = "200" ]; then
  pass "/raw: an in-scope markdown path is served (200)"
else
  fail "/raw: expected 200 for an in-scope markdown path, got $RESP_CODE"
fi

ctype="$(header_value Content-Type)"
if printf '%s' "$ctype" | grep -qi '^text/plain'; then
  pass "/raw: Content-Type is text/plain (\"$ctype\")"
else
  fail "/raw: Content-Type is \"$ctype\", expected text/plain; charset=utf-8"
fi
if printf '%s' "$ctype" | grep -qi 'charset=utf-8'; then
  pass "/raw: Content-Type names charset=utf-8"
else
  fail "/raw: Content-Type \"$ctype\" does not name charset=utf-8"
fi

clen="$(header_value Content-Length)"
blen="$(body_bytes)"
if [ -n "$clen" ] && [ "$clen" = "$blen" ]; then
  pass "/raw: Content-Length matches the body ($blen bytes)"
else
  fail "/raw: Content-Length \"$clen\" does not match the $blen received bytes"
fi

if cmp -s "$RAW_MD" "$BODY"; then
  pass "/raw: the body is the source markdown byte for byte"
else
  fail "/raw: the body is not identical to $RAW_MD"
fi

# The rendered sibling is what /doc serves; /raw must never return it.
if grep -q 'id="doc-b64"' "$BODY" 2> /dev/null; then
  fail "/raw: served the rendered html instead of the source markdown"
else
  pass "/raw: served the source markdown, not the rendered sibling"
fi

RAW_SHA="$(sha_of "$RAW_MD")"
ETAG="$(header_value ETag)"
if [ "$ETAG" = "\"$RAW_SHA\"" ]; then
  pass "/raw: ETag is the sha256 of the file's bytes, in double quotes"
else
  fail "/raw: ETag is \"$ETAG\", expected \"\\\"$RAW_SHA\\\"\""
fi

# Invariant: the bytes hashed are the bytes sent — hash what actually arrived.
BODY_SHA="$(sha_of "$BODY")"
if [ -n "$ETAG" ] && [ "$ETAG" = "\"$BODY_SHA\"" ]; then
  pass "/raw: the ETag hashes the bytes that were actually sent"
else
  fail "/raw: ETag $ETAG does not hash the received body (sha256 $BODY_SHA)"
fi

# =============================================================================
# Clause 5 / Invariants: /raw never writes, renders, or mutates anything
# =============================================================================

if [ -e "${RAW_MD%.md}.html" ]; then
  fail "/raw: rendering happened — a sibling .html was created for $RAW_MD"
else
  pass "/raw: no sibling .html was rendered for the served document"
fi

if [ "$(sha_of "$RAW_MD")" = "$RAW_MD_SHA_BEFORE" ]; then
  pass "/raw: serving a document does not mutate it"
else
  fail "/raw: the markdown changed while being served"
fi

STALE_HTML_SHA="$(sha_of "$STALE_HTML")"
STALE_HTML_MTIME="$(python3 -c "import os, sys; print(os.stat(sys.argv[1]).st_mtime)" "$STALE_HTML" 2> /dev/null)"
expect_code "/raw: a document with a stale sibling .html is still served" 200 \
  "$BASE/raw$(enc "$STALE_MD")"
if [ "$(sha_of "$STALE_HTML")" = "$STALE_HTML_SHA" ] \
  && [ "$(python3 -c "import os, sys; print(os.stat(sys.argv[1]).st_mtime)" "$STALE_HTML" 2> /dev/null)" = "$STALE_HTML_MTIME" ]; then
  pass "/raw: a stale sibling .html is left untouched (no re-render)"
else
  fail "/raw: the stale sibling .html was re-rendered or rewritten"
fi
if grep -q 'PRE-EXISTING-HTML-SENTINEL' "$BODY" 2> /dev/null; then
  fail "/raw: the sibling .html was served instead of the markdown source"
else
  pass "/raw: the markdown source was served even though a sibling .html exists"
fi

# =============================================================================
# Clause 4: If-None-Match — 304 with the same ETag and no body, quoted or bare;
# any other value gets the full 200.
# =============================================================================

do_request -H "If-None-Match: \"$RAW_SHA\"" "$RAW_URL"
# The two clauses below describe the 304 itself, so they are reported as
# unverified rather than passing vacuously when no 304 arrived.
if [ "$RESP_CODE" = "304" ]; then
  pass "/raw: If-None-Match with the current quoted ETag -> 304"
  if [ "$(header_value ETag)" = "\"$RAW_SHA\"" ]; then
    pass "/raw: the 304 carries the same ETag header"
  else
    fail "/raw: the 304's ETag is \"$(header_value ETag)\", expected \"\\\"$RAW_SHA\\\"\""
  fi
  if [ "$(body_bytes)" = "0" ]; then
    pass "/raw: the 304 has no body"
  else
    fail "/raw: the 304 carried a $(body_bytes)-byte body"
  fi
else
  fail "/raw: If-None-Match with the current ETag expected 304, got $RESP_CODE"
  fail "/raw: the 304's ETag header could not be checked (no 304 was returned)"
  fail "/raw: the 304's empty body could not be checked (no 304 was returned)"
fi

do_request -H "If-None-Match: $RAW_SHA" "$RAW_URL"
if [ "$RESP_CODE" = "304" ]; then
  pass "/raw: If-None-Match matched without the surrounding quotes -> 304"
else
  fail "/raw: unquoted If-None-Match expected 304, got $RESP_CODE"
fi

do_request -H 'If-None-Match: "0000000000000000000000000000000000000000000000000000000000000000"' "$RAW_URL"
if [ "$RESP_CODE" = "200" ] && cmp -s "$RAW_MD" "$BODY"; then
  pass "/raw: a non-matching If-None-Match gets the full 200 body"
else
  fail "/raw: non-matching If-None-Match expected a full 200, got $RESP_CODE"
fi

# Edge case: the file is replaced between poll cycles. The stale ETag must no
# longer match, and the new body and the new ETag must agree with each other.
printf '# Raw\n\nFirst body line.\nSecond body line.\nPOLL-CYCLE-MARKER-9f8e7d\n' > "$RAW_MD"
NEW_SHA="$(sha_of "$RAW_MD")"
do_request -H "If-None-Match: \"$RAW_SHA\"" "$RAW_URL"
if [ "$RESP_CODE" = "200" ] && grep -q 'POLL-CYCLE-MARKER-9f8e7d' "$BODY" 2> /dev/null; then
  pass "/raw: after the file changes, the old ETag no longer matches and the new bytes are served"
else
  fail "/raw: a changed file still answered $RESP_CODE to the previous ETag"
fi
if [ "$(header_value ETag)" = "\"$NEW_SHA\"" ] && [ "$(sha_of "$BODY")" = "$NEW_SHA" ]; then
  pass "/raw: the new ETag and the new body agree (one read per request)"
else
  fail "/raw: ETag \"$(header_value ETag)\" and body hash $(sha_of "$BODY") disagree after the file changed"
fi

# =============================================================================
# Clause 2: scope rules, identical to /doc, on the realpath, before any read
# =============================================================================

expect_code "scope: non-.md path rejected" 403 "$BASE/raw$(enc "$RAW_WORK/notes.txt")"
expect_error_naming "scope: non-.md path" '\.md|markdown'

expect_code "scope: missing .md rejected" 404 "$BASE/raw$(enc "$RAW_WORK/absent.md")"
expect_error_naming "scope: missing .md" 'not found|missing|exist'

expect_code "scope: .md outside the home directory rejected" 403 \
  "$BASE/raw$(enc "$OUT_WORK/outside-home.md")"
expect_error_naming "scope: outside the home directory" 'home'

if has_git_ancestor "$NOGIT_WORK"; then
  skip "scope: \$HOME sits inside a git worktree here, so no path under it can test the worktree rule"
else
  expect_code "scope: .md outside any git worktree rejected" 403 \
    "$BASE/raw$(enc "$NOGIT_WORK/outside.md")"
  expect_error_naming "scope: outside a git worktree" 'git|worktree'
fi

# Rule order: .md before existence, existence before the home-directory rule.
expect_code "scope: the .md rule is checked before existence" 403 \
  "$BASE/raw$(enc "$RAW_WORK/absent.txt")"
expect_code "scope: existence is checked before the home-directory rule" 404 \
  "$BASE/raw$(enc "$OUT_WORK/absent.md")"

# Realpath, before any read: a symlink inside the worktree pointing at a file
# outside it is rejected on the target's path, and neither end is read.
expect_code "scope: symlink escaping the worktree rejected" 403 \
  "$BASE/raw$(enc "$RAW_WORK/link.md")"
if grep -q 'Outside any worktree' "$BODY" 2> /dev/null; then
  fail "scope: the rejected symlink's target was read and returned anyway"
else
  pass "scope: the rejected symlink's contents were never returned"
fi
if [ -e "$RAW_WORK/link.html" ] || [ -e "$NOGIT_WORK/outside.html" ]; then
  fail "scope: the symlinked document was rendered despite the rejection"
else
  pass "scope: the rejected symlink was never rendered"
fi

# =============================================================================
# Inputs: Host pinning applies before routing; query strings are stripped
# =============================================================================

expect_code "host: wrong Host on /raw rejected" 403 -H 'Host: evil.example' "$RAW_URL"
expect_error_naming "host: wrong Host on /raw" 'host'

expect_code "host: localhost:<port> is not 127.0.0.1:<port> on /raw" 403 \
  -H "Host: localhost:$PORT_A" "$RAW_URL"

expect_code "/raw: query string stripped before routing" 200 "$RAW_URL?ts=1700000000"

# =============================================================================
# Edge cases: an empty document, and a path with spaces and non-ASCII
# =============================================================================

EMPTY_SHA="$(sha_of "$EMPTY_MD")"
do_request "$BASE/raw$(enc "$EMPTY_MD")"
if [ "$RESP_CODE" = "200" ] && [ "$(body_bytes)" = "0" ]; then
  pass "/raw: an empty .md is 200 with an empty body"
else
  fail "/raw: empty .md expected 200 with a 0-byte body, got $RESP_CODE with $(body_bytes) bytes"
fi
if [ "$(header_value ETag)" = "\"$EMPTY_SHA\"" ]; then
  pass "/raw: an empty .md carries the ETag of the empty-string hash"
else
  fail "/raw: empty .md ETag is \"$(header_value ETag)\", expected \"\\\"$EMPTY_SHA\\\"\""
fi
if [ "$(header_value Content-Length)" = "0" ]; then
  pass "/raw: an empty .md declares Content-Length: 0"
else
  fail "/raw: empty .md declared Content-Length \"$(header_value Content-Length)\", expected 0"
fi

do_request "$BASE/raw$(enc "$SPACED_MD")"
if [ "$RESP_CODE" = "200" ] && cmp -s "$SPACED_MD" "$BODY"; then
  pass "/raw: a percent-encoded path with spaces and non-ASCII is decoded and served"
else
  fail "/raw: percent-encoded path with spaces/non-ASCII returned $RESP_CODE"
fi
if [ "$(header_value ETag)" = "\"$(sha_of "$SPACED_MD")\"" ]; then
  pass "/raw: the spaced/non-ASCII document's ETag hashes its own bytes"
else
  fail "/raw: wrong ETag for the spaced/non-ASCII document"
fi

# =============================================================================
# Errors: a file that passes scope but cannot be read -> 500 naming the OSError
# =============================================================================

if [ "$(id -u)" -eq 0 ]; then
  skip "/raw: running as root, so a mode-000 document would still be readable"
else
  UNREAD_MD="$RAW_WORK/unreadable.md"
  printf '# Unreadable\n' > "$UNREAD_MD"
  chmod 000 "$UNREAD_MD"
  do_request "$BASE/raw$(enc "$UNREAD_MD")"
  err_msg="$(json_field error)"
  if [ "$RESP_CODE" = "500" ] && [ -n "$err_msg" ]; then
    pass "/raw: an unreadable in-scope document -> 500 with a JSON error (\"$err_msg\")"
  else
    fail "/raw: unreadable document expected 500 with a JSON error, got $RESP_CODE \"$err_msg\""
  fi
  if grep -q 'Traceback (most recent call last)' "$BODY" 2> /dev/null; then
    fail "/raw: a traceback leaked into the response body"
  else
    pass "/raw: no traceback leaked into the response body"
  fi
  chmod 644 "$UNREAD_MD"
fi

expect_code "/raw: the server is still healthy after every error path" 200 "$BASE/health"

# An unhandled exception in the handler shows up in two places at once: an
# empty reply to the client and a traceback on the server's stderr. The client
# half is B01's own Errors clause; the stderr half is the inherited "request
# logging is suppressed entirely (no stderr noise per request)" clause of the
# fixed-port contract, which every route is subject to.
if grep -q 'Traceback (most recent call last)' "$SRV_ERR" 2> /dev/null; then
  fail "/raw: the server's stderr carries a traceback from a /raw request"
else
  pass "/raw: no /raw error path wrote a traceback to the server's stderr"
fi

# =============================================================================
# Clause 6: a successful serve is recorded — on the 200 AND on the 304
# =============================================================================

REG_MD="$RAW_WORK/registered.md"
printf '# Registered\n\nbody\n' > "$REG_MD"
REG_REAL="$(python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$REG_MD")"
REG_SHA="$(sha_of "$REG_MD")"

do_request "$BASE/raw$(enc "$REG_MD")"
raw_200_code="$RESP_CODE"
do_request "$BASE/docs.json"
t_after_200="$(docs_json_time "$REG_REAL")"
if [ "$raw_200_code" = "200" ] && [ -n "$t_after_200" ]; then
  pass "/raw: a 200 records the document in the registry (last-served $t_after_200)"
else
  fail "/raw: after a $raw_200_code the document is absent from /docs.json ($(cat "$BODY" 2> /dev/null))"
fi

sleep 1 # last-served is epoch SECONDS; the advance must be observable
do_request -H "If-None-Match: \"$REG_SHA\"" "$BASE/raw$(enc "$REG_MD")"
raw_304_code="$RESP_CODE"
do_request "$BASE/docs.json"
t_after_304="$(docs_json_time "$REG_REAL")"
if [ "$raw_304_code" != "304" ]; then
  fail "/raw: the conditional re-request returned $raw_304_code, so the 304 recording clause could not be checked"
elif [ -z "$t_after_304" ]; then
  fail "/raw: the document vanished from /docs.json after a 304"
elif num_gt "$t_after_304" "$t_after_200"; then
  pass "/raw: a 304 records the serve too (last-served advanced $t_after_200 -> $t_after_304)"
else
  fail "/raw: a 304 did not update last-served (still $t_after_304, was $t_after_200)"
fi

# A rejected request is not a serve: nothing out of scope may be recorded.
do_request "$BASE/raw$(enc "$RAW_WORK/notes.txt")"
do_request "$BASE/docs.json"
if [ "$RESP_CODE" != "200" ]; then
  fail "/raw: whether a scope-rejected request is recorded could not be checked (/docs.json returned $RESP_CODE)"
elif [ -z "$(docs_json_time "$(realpath_of "$RAW_WORK/notes.txt")")" ]; then
  pass "/raw: a scope-rejected request is not recorded"
else
  fail "/raw: a scope-rejected request was recorded in the registry"
fi

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'server-raw.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'server-raw.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'server-raw.test.sh: all assertions passed\n'
