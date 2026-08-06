#!/usr/bin/env bash
# hostname-allowlist.test.sh — verifies the comment block "Contract: 002-B07
# hostname allowlist + dual bind" in plugins/render-doc/scripts/serve.py, for
# the two surfaces that live in one process: the host_allowed() predicate and
# the _check_host() wiring that consumes it.
#
# Today the server answers to exactly one name, "127.0.0.1:<port>". The block
# widens that to four: the address, "localhost", the bracketed IPv6 loopback
# literal, and any single-label "<label>.localhost" — each only ever with this
# server's own port digits attached. Every one of those names resolves to
# loopback under RFC 6761 with no configuration anywhere, which is what lets
# the allowlist grow without giving up the DNS-rebinding defense the exact
# match was there for.
#
# So the assertions come in two layers, for the reason discovery-scan.test.sh
# and index-discovery.test.sh split theirs the same way:
#
#   1. host_allowed() called directly (imported through PYTHONPATH, with
#      RENDER_DOC_PORT naming a throwaway port so the port digits under test
#      are this file's choice). The contract is a statement about a predicate
#      over strings — accepted forms, rejected forms, totality — and forty-odd
#      such statements read back out of HTTP status codes would prove less and
#      run far slower. Each case is one named assertion, so a red says exactly
#      which form regressed.
#   2. _check_host() over HTTP on a throwaway port, because "reaches routing"
#      and "403 before any routing" are claims about the server, not about the
#      predicate. The Host values sent there carry the TEST port; nothing in
#      this file connects to 27183 or touches its /tmp files.
#
# The dual [::1] listener that main() grows is the same contract's third
# surface and is covered by dual-bind.test.sh, because it needs a port free in
# both address families and a deliberately sabotaged v6 bind.
#
# Marker note: plan-002 contract markers are plan-qualified ("Contract:
# 002-B07"). serve.py also carries permanent, unrelated "Contract: B01"…"B03"
# docblocks from earlier plans, so nothing here greps the bare form.
#
# Out of scope, because another suite owns it: that a rejected Host writes
# nothing through /annotate and that an unknown route with a foreign Host is
# 403 rather than 404 (server.test.sh), and the README prose describing the
# friendly hostname (hostname-docs.test.sh).

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVE="$SCRIPT_DIR/serve.py"

WORK="$(mktemp -d)"
HEADERS="$WORK/resp.headers"
BODY="$WORK/resp.body"

SERVER_PIDS=()
TMP_ARTEFACTS=()

# Teardown: every server this file starts, and every /tmp file its port owns.
# Stale registry files and pidfiles left behind on a throwaway port are what
# flakes the other server suites for whoever runs next.
cleanup() {
  for p in ${SERVER_PIDS[@]+"${SERVER_PIDS[@]}"}; do
    [ -n "$p" ] && kill "$p" 2> /dev/null
  done
  sleep 0.2
  for p in ${SERVER_PIDS[@]+"${SERVER_PIDS[@]}"}; do
    [ -n "$p" ] && kill -9 "$p" 2> /dev/null
  done
  for f in ${TMP_ARTEFACTS[@]+"${TMP_ARTEFACTS[@]}"}; do
    [ -n "$f" ] && rm -f "$f"
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
for tool in python3 curl; do
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
  printf 'hostname-allowlist.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

# --- Helpers -----------------------------------------------------------------

# 27183 is the live server's port on a developer machine: never returned, never
# connected to, never named in a /tmp path by this file.
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

# The rejection semantics the contract freezes: 403 carrying exactly
# {"error": "bad Host header"} — the scope_error JSON shape, byte for byte as
# it is today, so widening the accepted set costs the rejected set nothing.
expect_rejected() { # <label> <curl args...>
  local label="$1" body_err
  shift
  do_request "$@"
  if [ "$RESP_CODE" != "403" ]; then
    fail "$label: expected 403, got $RESP_CODE"
    return
  fi
  body_err="$(python3 -c "
import json, sys
try:
    print(json.load(open(sys.argv[1])).get('error'))
except Exception as e:
    print('<unparseable: %s>' % e)
" "$BODY" 2> /dev/null)"
  if [ "$body_err" = "bad Host header" ]; then
    pass "$label (403 {\"error\": \"bad Host header\"})"
  else
    fail "$label: 403 but the body's error was \"$body_err\", expected \"bad Host header\""
  fi
}

# =============================================================================
# Layer 1: host_allowed() as a predicate
# =============================================================================
# Every case below is (expected, host, label). They are declared as data rather
# than as forty near-identical python snippets so that a reader can see the
# whole accepted/rejected frontier at once, and so one evaluation run reports
# every case instead of stopping at the first raise.

PY_PORT="$(free_port)"
TMP_ARTEFACTS+=("/tmp/render-doc-registry-$PY_PORT.json")

# A port that is emphatically NOT this server's, for the "the port digits must
# match exactly" clause. Not 27183: that would read as a claim about the live
# server rather than about digit comparison.
WRONG_PORT=$((PY_PORT + 1))
if [ "$WRONG_PORT" = "$PY_PORT" ]; then
  fail "setup: the wrong-port fixture equals the test port; no port clause can be checked"
fi

# Label length bounds, per "1-63 chars of [A-Za-z0-9-]".
L1="a"
L63="$(python3 -c 'print("a" * 63)')"
L64="$(python3 -c 'print("a" * 64)')"

CASES="$WORK/cases.tsv"
: > "$CASES"
# A literal NUL-free sentinel for the absent header: None is not a string, and
# the contract names it as its own edge case.
NONE_SENTINEL='__NONE__'

case_yes() { printf '1\t%s\t%s\n' "$1" "$2" >> "$CASES"; }
case_no() { printf '0\t%s\t%s\n' "$1" "$2" >> "$CASES"; }

# --- Accepted: the four forms, each with the explicit :<PORT> suffix ---------
case_yes "127.0.0.1:$PY_PORT" "accepts 127.0.0.1:<port> (form 1, today's only name)"
case_yes "localhost:$PY_PORT" "accepts localhost:<port> (form 2)"
case_yes "[::1]:$PY_PORT" "accepts [::1]:<port> (form 3, the bracketed v6 loopback literal)"
case_yes "clam.localhost:$PY_PORT" "accepts <label>.localhost:<port> (form 4)"
case_yes "$L1.localhost:$PY_PORT" "accepts a 1-char label (the shortest legal label)"
case_yes "$L63.localhost:$PY_PORT" "accepts a 63-char label (the longest legal label)"
case_yes "my-tree.localhost:$PY_PORT" "accepts a label with an interior hyphen"
case_yes "0123456789.localhost:$PY_PORT" "accepts an all-digit label"
case_yes "orchestrate-serve-discovery.localhost:$PY_PORT" "accepts a realistic worktree-shaped label"
# Case-insensitivity, named in the contract's edge cases.
case_yes "CLAM.LOCALHOST:$PY_PORT" "accepts CLAM.LOCALHOST:<port> (names match case-insensitively)"
case_yes "LOCALHOST:$PY_PORT" "accepts LOCALHOST:<port> (bare name, case-insensitively)"
case_yes "Clam.LocalHost:$PY_PORT" "accepts a mixed-case <label>.localhost"

# --- Rejected: absent, empty, and portless ----------------------------------
case_no "$NONE_SENTINEL" "rejects None (no Host header at all)"
case_no "" "rejects the empty string"
case_no "localhost" "rejects bare localhost with no port"
case_no "clam.localhost" "rejects clam.localhost with no port"
case_no "127.0.0.1" "rejects 127.0.0.1 with no port"
case_no "[::1]" "rejects [::1] with no port"

# --- Rejected: the port digits do not match exactly --------------------------
case_no "localhost:$WRONG_PORT" "rejects localhost with another port"
case_no "clam.localhost:$WRONG_PORT" "rejects <label>.localhost with another port"
case_no "127.0.0.1:$WRONG_PORT" "rejects 127.0.0.1 with another port"
case_no "[::1]:$WRONG_PORT" "rejects [::1] with another port"
case_no "localhost:0$PY_PORT" "rejects a zero-padded port (digits must match exactly)"
case_no "localhost:" "rejects an empty port"
case_no "localhost:abc" "rejects a non-numeric port"
# The named trailing-garbage edge case, on the address and on a name.
case_no "127.0.0.1:${PY_PORT}extra" "rejects 127.0.0.1:<port> with trailing garbage"
case_no "localhost:${PY_PORT}extra" "rejects localhost:<port> with trailing garbage"
case_no "localhost:$PY_PORT:$PY_PORT" "rejects a doubled port suffix"

# --- Rejected: label shape ---------------------------------------------------
case_no "a.b.localhost:$PY_PORT" "rejects a multi-label subdomain (a.b.localhost)"
case_no "x.y.z.localhost:$PY_PORT" "rejects a three-label subdomain"
case_no ".localhost:$PY_PORT" "rejects an empty label"
case_no "-x.localhost:$PY_PORT" "rejects a leading-hyphen label"
case_no "x-.localhost:$PY_PORT" "rejects a trailing-hyphen label"
case_no "-.localhost:$PY_PORT" "rejects a label that is a lone hyphen"
case_no "$L64.localhost:$PY_PORT" "rejects a 64-char label (one over the limit)"
case_no "a_b.localhost:$PY_PORT" "rejects an underscore in the label (charset is [A-Za-z0-9-])"
case_no "[clam.localhost]:$PY_PORT" "rejects a bracketed name (brackets are for the v6 literal only)"

# --- Rejected: trailing dot, and localhost in the wrong position -------------
case_no "localhost.:$PY_PORT" "rejects a trailing dot on localhost"
case_no "clam.localhost.:$PY_PORT" "rejects a trailing dot on <label>.localhost"
case_no "localhost.evil.example:$PY_PORT" "rejects localhost used as a leading label"
case_no "notlocalhost:$PY_PORT" "rejects a name that merely ends in localhost"
case_no "evil.example:$PY_PORT" "rejects an unrelated registrable name"

# --- Rejected: other IPs -----------------------------------------------------
case_no "127.0.0.2:$PY_PORT" "rejects another loopback address"
case_no "0.0.0.0:$PY_PORT" "rejects 0.0.0.0"
case_no "192.168.1.1:$PY_PORT" "rejects a private-range address"
case_no "10.0.0.1:$PY_PORT" "rejects another private-range address"
case_no "[::2]:$PY_PORT" "rejects a non-loopback v6 literal"
case_no "[::ffff:127.0.0.1]:$PY_PORT" "rejects the v4-mapped v6 form of the loopback address"
case_no "::1:$PY_PORT" "rejects an unbracketed v6 loopback literal"

# --- Rejected: userinfo and path smuggling -----------------------------------
case_no "user@localhost:$PY_PORT" "rejects userinfo before an accepted name"
case_no "evil.example@localhost:$PY_PORT" "rejects a hostname smuggled into userinfo"
case_no "localhost:$PY_PORT/" "rejects a trailing slash"
case_no "localhost:$PY_PORT/evil" "rejects a smuggled path"
case_no "http://localhost:$PY_PORT" "rejects a scheme prefix"
case_no "clam.localhost:$PY_PORT?x=1" "rejects a smuggled query string"
case_no "clam.localhost:$PY_PORT#frag" "rejects a smuggled fragment"
# "nothing else" after the port suffix includes whitespace either side.
case_no "clam.localhost:$PY_PORT " "rejects a trailing space"
case_no " clam.localhost:$PY_PORT" "rejects a leading space"

# Evaluate every case in one interpreter. A raise is reported per case rather
# than aborting the run, because "never raises" is itself a clause: the stub's
# NotImplementedError("002-B07") shows up as the reason on every line, which is
# exactly the red this suite is meant to produce before the block is written.
RESULTS="$WORK/results.tsv"
PYTHONPATH="$SCRIPT_DIR" RENDER_DOC_PORT="$PY_PORT" PYTHONDONTWRITEBYTECODE=1 \
  python3 - "$CASES" "$NONE_SENTINEL" > "$RESULTS" 2> "$WORK/table.stderr" << 'PY'
import sys

cases_path, none_sentinel = sys.argv[1], sys.argv[2]


def emit(ok, label, detail=''):
    sys.stdout.write('%d\t%s\t%s\n' % (1 if ok else 0, label, detail))


try:
    import serve
except Exception as exc:  # noqa: BLE001 - any import failure is one clear red
    emit(False, 'setup: serve.py imports', '%s: %s' % (type(exc).__name__, exc))
    sys.exit(0)

emit(True, 'setup: serve.py imports')

if not hasattr(serve, 'host_allowed'):
    emit(False, 'setup: host_allowed is importable from serve',
         'serve.host_allowed is not defined')
    sys.exit(0)
emit(True, 'setup: host_allowed is importable from serve')

non_bool = []
returned = 0
with open(cases_path, encoding='utf-8') as fh:
    for line in fh:
        line = line.rstrip('\n')
        if not line:
            continue
        want_raw, host, label = line.split('\t', 2)
        want = want_raw == '1'
        arg = None if host == none_sentinel else host
        try:
            got = serve.host_allowed(arg)
        except Exception as exc:  # noqa: BLE001 - totality is a clause
            emit(False, label,
                 'raised %s(%s) — the contract says it never raises'
                 % (type(exc).__name__, exc))
            continue
        returned += 1
        if not isinstance(got, bool):
            non_bool.append((host, type(got).__name__))
        if bool(got) is want:
            emit(True, label)
        else:
            emit(False, label,
                 'host_allowed(%r) returned %r, expected %s' % (arg, got, want))

# Never vacuously green: with nothing returned there is no answer to inspect,
# so the clause is unproven rather than satisfied.
label = 'every answer is a bool (Outputs: True or False)'
if not returned:
    emit(False, label, 'no call returned a value, so no answer could be inspected')
elif non_bool:
    emit(False, label, 'non-bool for %r' % (non_bool[:3],))
else:
    emit(True, label)
PY

if [ ! -s "$RESULTS" ]; then
  fail "host_allowed: the evaluation run produced no result lines -- $(tail -2 "$WORK/table.stderr" 2> /dev/null | tr '\n' ' ')"
else
  while IFS=$'\t' read -r ok label detail; do
    [ -n "$label" ] || continue
    if [ "$ok" = "1" ]; then
      pass "host_allowed: $label"
    elif [ -n "$detail" ]; then
      fail "host_allowed: $label -- $detail"
    else
      fail "host_allowed: $label"
    fi
  done < "$RESULTS"
fi

# Invariant: the predicate is pure. Asking the same question twice gives the
# same answer, and asking it never touches the registry or the filesystem —
# it is consulted on every single request, so anything it wrote would be
# written thousands of times.
PYTHONPATH="$SCRIPT_DIR" RENDER_DOC_PORT="$PY_PORT" PYTHONDONTWRITEBYTECODE=1 \
  python3 - "$PY_PORT" > "$WORK/pure.out" 2>&1 << 'PY'
import sys

port = sys.argv[1]
import serve

probes = ['127.0.0.1:%s' % port, 'localhost:%s' % port, 'evil.example', None]
first = [serve.host_allowed(p) for p in probes]
second = [serve.host_allowed(p) for p in probes]
assert first == second, (first, second)
print('OK')
PY
if grep -qx 'OK' "$WORK/pure.out" 2> /dev/null; then
  pass "host_allowed: repeated calls with the same input give the same answer"
else
  fail "host_allowed: repeated calls with the same input give the same answer -- $(tail -2 "$WORK/pure.out" | tr '\n' ' ')"
fi

if [ -e "/tmp/render-doc-registry-$PY_PORT.json" ]; then
  fail "host_allowed: importing serve.py and calling the predicate created a registry file"
else
  pass "host_allowed: importing serve.py and calling the predicate wrote no /tmp state"
fi

# =============================================================================
# Layer 2: _check_host() over HTTP — accepted names reach routing, rejected
# ones are stopped with 403 before it
# =============================================================================
# Every Host value below carries the TEST port. A Host naming 27183 would be a
# statement about a different server, and this file makes none.

PORT_A="$(free_port)"
BASE_A="http://127.0.0.1:$PORT_A"
if [ -e "/tmp/render-doc-serve-$PORT_A.pid" ] || [ -e "/tmp/render-doc-registry-$PORT_A.json" ]; then
  fail "test port $PORT_A already has /tmp state; aborting to avoid clobbering it"
  printf 'hostname-allowlist.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
start_server "$PORT_A" "$WORK/srv-a.stderr"
if wait_healthy "$BASE_A"; then
  pass "server: healthy on test port $PORT_A"
else
  fail "server: did not become healthy on test port $PORT_A — no wiring clause can be checked"
  printf 'hostname-allowlist.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

# --- Accepted names reach routing -------------------------------------------
# /health is the probe: a 200 with the app marker proves the request was routed
# and answered, not merely admitted.
check_reaches_routing() { # <label> <host header value>
  do_request -H "Host: $2" "$BASE_A/health"
  if [ "$RESP_CODE" != "200" ]; then
    fail "$1: expected 200, got $RESP_CODE"
    return
  fi
  if python3 -c "
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get('app') == 'render-doc' else 1)
" "$BODY" 2> /dev/null; then
    pass "$1 (200, routed to /health)"
  else
    fail "$1: 200 but the body is not the /health payload"
  fi
}

check_reaches_routing "wiring: 127.0.0.1:<port> reaches routing" "127.0.0.1:$PORT_A"
check_reaches_routing "wiring: localhost:<port> reaches routing" "localhost:$PORT_A"
check_reaches_routing "wiring: [::1]:<port> reaches routing" "[::1]:$PORT_A"
check_reaches_routing "wiring: <label>.localhost:<port> reaches routing" "clam.localhost:$PORT_A"
check_reaches_routing "wiring: CLAM.LOCALHOST:<port> reaches routing" "CLAM.LOCALHOST:$PORT_A"

# An accepted name reaches EVERY route, not just /health: _check_host gates the
# whole handler, so widening it must widen it uniformly.
expect_code "wiring: an accepted name reaches the project index" 200 \
  -H "Host: clam.localhost:$PORT_A" "$BASE_A/"
expect_code "wiring: an accepted name reaches /docs.json" 200 \
  -H "Host: clam.localhost:$PORT_A" "$BASE_A/docs.json"

# --- Rejected names are stopped, with today's exact semantics ----------------
expect_rejected "wiring: a foreign name is rejected" \
  -H 'Host: evil.example' "$BASE_A/health"
expect_rejected "wiring: a multi-label subdomain is rejected" \
  -H "Host: a.b.localhost:$PORT_A" "$BASE_A/health"
expect_rejected "wiring: a leading-hyphen label is rejected" \
  -H "Host: -x.localhost:$PORT_A" "$BASE_A/health"
expect_rejected "wiring: an accepted name with the wrong port is rejected" \
  -H "Host: localhost:$WRONG_PORT" "$BASE_A/health"
expect_rejected "wiring: an accepted name with no port is rejected" \
  -H 'Host: localhost' "$BASE_A/health"
expect_rejected "wiring: a non-loopback address is rejected" \
  -H "Host: 192.168.1.1:$PORT_A" "$BASE_A/health"
expect_rejected "wiring: userinfo before an accepted name is rejected" \
  -H "Host: evil.example@localhost:$PORT_A" "$BASE_A/health"

# "Before any routing", unchanged: a bad Host on a route that does not exist is
# still 403 and not 404, on both verbs.
expect_code "wiring: the check still runs before routing (unknown route yields 403, not 404)" 403 \
  -H 'Host: evil.example' "$BASE_A/nope"
expect_code "wiring: the check still runs before routing on POST" 403 \
  -X POST -H 'Host: evil.example' -H 'Content-Type: application/json' \
  -d '{}' "$BASE_A/annotate"

# An absent Host header: host_allowed(None) is False, so the request is
# rejected rather than crashing the handler. curl always sends a Host, so the
# request is spoken directly over a socket as HTTP/1.0.
NOHOST_STATUS="$(python3 - "$PORT_A" << 'PY' 2> /dev/null
import socket
import sys

try:
    s = socket.create_connection(('127.0.0.1', int(sys.argv[1])), timeout=5)
    s.sendall(b'GET /health HTTP/1.0\r\n\r\n')
    data = b''
    while len(data) < 4096:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
    s.close()
    print(data.split(b'\r\n', 1)[0].decode('latin-1'))
except Exception as exc:  # noqa: BLE001
    print('<no response: %s>' % exc)
PY
)"
case "$NOHOST_STATUS" in
  *' 403'*)
    pass "wiring: a request with no Host header at all is rejected (403)"
    ;;
  *)
    fail "wiring: a request with no Host header got \"$NOHOST_STATUS\", expected a 403 status line"
    ;;
esac

# --- Invariants --------------------------------------------------------------
# The widened allowlist is still loopback-only at the socket layer: a name
# being accepted says nothing about which interface answers. If this host has a
# routable address, nothing may answer there whatever Host it is asked for.
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
    skip "invariant: no non-loopback address on this host; cannot prove the bind stayed loopback-only"
    ;;
  *)
    ext_code="$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' \
      -H "Host: clam.localhost:$PORT_A" "http://$NONLOOP:$PORT_A/health" 2> /dev/null)"
    ext_code="${ext_code:-000}"
    if [ "$ext_code" = "000" ]; then
      pass "invariant: an accepted name still does not make the server answer on $NONLOOP"
    else
      fail "invariant: the server answered on $NONLOOP:$PORT_A with $ext_code — the bind is no longer loopback-only"
    fi
    ;;
esac

# Zero configuration: nothing on this machine had to be registered for any of
# the accepted names to work, so the server must not have written or read a
# host allowlist anywhere. The check that matters operationally is that no new
# /tmp file appeared beyond the two this port already owns.
STRAY="$(find /tmp -maxdepth 1 -name "render-doc-*$PORT_A*" ! -name "render-doc-serve-$PORT_A.pid" \
  ! -name "render-doc-registry-$PORT_A.json" 2> /dev/null | head -3)"
if [ -z "$STRAY" ]; then
  pass "invariant: the allowlist needs no configuration file (no new /tmp state for this port)"
else
  fail "invariant: unexpected /tmp state for the test port: $STRAY"
fi

expect_code "server: still healthy after every Host path" 200 "$BASE_A/health"
if grep -q 'Traceback (most recent call last)' "$WORK/srv-a.stderr" 2> /dev/null; then
  fail "outputs: the server's stderr carries a traceback — a Host path raised"
else
  pass "outputs: the server's stderr is free of tracebacks"
fi

# =============================================================================
# Left to acceptance review
# =============================================================================
# The Invariants clause — that every accepted form can only ever reach loopback
# under RFC 6761 — is a claim about resolvers and browsers, not about this
# process, and no assertion in a test suite can establish it. What is asserted
# here is the half that lives in the code: the accepted set is exactly the four
# named forms, so no name outside RFC 6761's special-use space is ever admitted.
# Two readings are also deliberately left open rather than pinned: whether the
# fully expanded loopback literal ([0:0:0:0:0:0:0:1]) counts as "the bracketed
# IPv6 loopback literal", and whether serve.py's own "Contract: B01" docblock —
# which still states the exact-match rule this block supersedes — should be
# amended. Both are the orchestrator's call, not a grep's.

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'hostname-allowlist.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'hostname-allowlist.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'hostname-allowlist.test.sh: all assertions passed\n'
