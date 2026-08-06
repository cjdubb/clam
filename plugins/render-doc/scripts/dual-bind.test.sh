#!/usr/bin/env bash
# dual-bind.test.sh — verifies the main() half of the comment block "Contract:
# 002-B07 hostname allowlist + dual bind" in
# plugins/render-doc/scripts/serve.py.
#
# Accepting "<label>.localhost:<port>" as a name is only half the capability.
# curl on this machine hands *.localhost to the system resolver, which answers
# ::1 — so a server listening only on 127.0.0.1 accepts the name and then never
# sees the connection. main() therefore grows a second ThreadingHTTPServer on
# ('::1', PORT) sharing the same Handler, served on a daemon thread.
#
# That second listener is BEST-EFFORT, and the whole point of this suite is the
# asymmetry: the v6 bind may fail for any environmental reason (IPv6 disabled,
# ::1 already taken) and the v4 server must be completely unaffected — same exit
# code, same pidfile, same singleton semantics, at most a one-line note on
# stderr. So the scenarios are deliberately three separate servers:
#
#   A. a clean dual bind — both listeners answer, and /health's pid proves it
#      is one process rather than two servers that happen to agree;
#   B. ('::1', PORT) pre-occupied by this file before the server starts, so the
#      v6 bind is guaranteed to fail while the v4 port stays free (binding a
#      specific v6 address never reserves the v4 one);
#   C. the singleton race, run against a server that HAS a v6 listener, because
#      the losing racer must still lose on the v4 bind and exit 0 — the new
#      listener must not turn a normal losing race into an error.
#
# Where ::1 cannot be bound at all, every v6 clause skips with a reason rather
# than failing: the contract makes the v6 leg best-effort, and an environment
# without IPv6 is exactly the case it promises to survive.
#
# Marker note: plan-002 contract markers are plan-qualified ("Contract:
# 002-B07"). serve.py also carries permanent, unrelated "Contract: B01"…"B03"
# docblocks from earlier plans, so nothing here greps the bare form.
#
# Out of scope, because another suite owns it: which Host values host_allowed()
# accepts (hostname-allowlist.test.sh), and the general pidfile/SIGTERM
# behaviour of the v4 server (server.test.sh) — only what this block must leave
# UNCHANGED about those is re-asserted here.

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVE="$SCRIPT_DIR/serve.py"

WORK="$(mktemp -d)"

SERVER_PIDS=()
TMP_ARTEFACTS=()

# Teardown: every server and every socket holder this file starts, plus the
# /tmp pidfile and registry file each test port owns. Litter left on a
# throwaway port is what flakes the other server suites for whoever runs next.
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
  printf 'dual-bind.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

PY_BIN="$(command -v python3)"

# --- Helpers -----------------------------------------------------------------

# Can this environment bind the IPv6 loopback at all? Everything v6 below is
# conditional on this: the contract makes the second listener best-effort
# precisely so that a host without IPv6 keeps a working server.
HAVE_V6=0
if python3 -c "
import socket
import sys
try:
    s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    s.bind(('::1', 0))
    s.close()
except OSError:
    sys.exit(1)
" 2> /dev/null; then
  HAVE_V6=1
fi

# A port free in BOTH address families, so a dual bind can succeed on it. 27183
# is the live server's port on a developer machine: never returned, never
# connected to, never named in a /tmp path by this file.
free_dual_port() {
  python3 -c "
import socket
import sys

want_v6 = sys.argv[1] == '1'
for _ in range(64):
    s4 = socket.socket()
    s4.bind(('127.0.0.1', 0))
    port = s4.getsockname()[1]
    s4.close()
    if port == 27183:
        continue
    if want_v6:
        try:
            s6 = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
            s6.bind(('::1', port))
            s6.close()
        except OSError:
            continue
    print(port)
    break
" "$HAVE_V6"
}

start_server() { # <port> <stderr file>
  env RENDER_DOC_PORT="$1" "$PY_BIN" "$SERVE" > "$2.stdout" 2> "$2" &
  LAST_PID="$!"
  SERVER_PIDS+=("$LAST_PID")
  TMP_ARTEFACTS+=("/tmp/render-doc-serve-$1.pid" "/tmp/render-doc-registry-$1.json")
}
LAST_PID=""

wait_healthy() { # <base url>
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if curl -sf --max-time 1 "$1/health" > /dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

# -g keeps curl from reading the brackets of a v6 literal as a glob.
BODY="$WORK/resp.body"
RESP_CODE=""
do_request() { # <curl args...>
  : > "$BODY"
  RESP_CODE="$(curl -gs --max-time 20 -o "$BODY" -w '%{http_code}' "$@" 2> /dev/null)"
  RESP_CODE="${RESP_CODE:-000}"
}

health_field() { # <field>
  python3 -c "
import json, sys
try:
    print(json.load(open(sys.argv[1])).get(sys.argv[2], ''))
except Exception:
    print('')
" "$BODY" "$1" 2> /dev/null
}

# Non-empty stderr lines, for the "at most a one-line note" clause. grep -c
# prints its count and THEN exits 1 on zero matches, so the count is read from
# stdout and the status ignored rather than or-ed into a second value.
noise_lines() { # <stderr file>
  local n
  n="$(grep -c '[^[:space:]]' "$1" 2> /dev/null)"
  printf '%s' "${n:-0}"
}

reserve_v6() { # <port> — hold ('::1', <port>) until this file exits
  "$PY_BIN" -c "
import socket
import sys
import time

s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 0)
s.bind(('::1', int(sys.argv[1])))
s.listen(1)
sys.stderr.write('held\n')
sys.stderr.flush()
time.sleep(600)
" "$1" 2> "$WORK/holder.err" &
  SERVER_PIDS+=("$!")
}

# =============================================================================
# Scenario A: a clean start — the v4 server is unchanged and a second listener
# answers on [::1]
# =============================================================================

PORT_A="$(free_dual_port)"
if [ -z "$PORT_A" ]; then
  fail "setup: no port free in both address families; no clause can be checked"
  printf 'dual-bind.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
BASE4_A="http://127.0.0.1:$PORT_A"
BASE6_A="http://[::1]:$PORT_A"
PIDFILE_A="/tmp/render-doc-serve-$PORT_A.pid"
if [ -e "$PIDFILE_A" ] || [ -e "/tmp/render-doc-registry-$PORT_A.json" ]; then
  fail "test port $PORT_A already has /tmp state; aborting to avoid clobbering it"
  printf 'dual-bind.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

start_server "$PORT_A" "$WORK/srv-a.stderr"
SRV_A_PID="$LAST_PID"

if wait_healthy "$BASE4_A"; then
  pass "v4: the server is healthy on 127.0.0.1:$PORT_A"
else
  fail "v4: the server did not become healthy on 127.0.0.1:$PORT_A — no clause can be checked"
  printf 'dual-bind.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

# The v4 legs the contract freezes: same pidfile, same content, same exit path.
if [ -f "$PIDFILE_A" ] && [ "$(cat "$PIDFILE_A" 2> /dev/null)" = "$SRV_A_PID" ]; then
  pass "v4: the pidfile still holds the server pid, unaffected by the second listener"
else
  fail "v4: pidfile $PIDFILE_A missing or does not hold pid $SRV_A_PID (got \"$(cat "$PIDFILE_A" 2> /dev/null)\")"
fi

do_request "$BASE4_A/health"
V4_HEALTH_PID="$(health_field pid)"
if [ "$RESP_CODE" = "200" ] && [ "$V4_HEALTH_PID" = "$SRV_A_PID" ]; then
  pass "v4: /health reports the process that owns the port (pid $V4_HEALTH_PID)"
else
  fail "v4: /health returned $RESP_CODE with pid \"$V4_HEALTH_PID\", expected 200 and pid $SRV_A_PID"
fi

if [ "$HAVE_V6" -ne 1 ]; then
  skip "v6: this environment cannot bind ::1, so every second-listener clause is unchecked"
  skip "v6: whether the same process answers on [::1] is unchecked"
  skip "v6: whether the [::1]:<port> Host is accepted over the v6 listener is unchecked"
  skip "v6: whether a foreign Host is still rejected over the v6 listener is unchecked"
else
  # Does a listener exist at all on [::1]? Asked with an explicit Host of the
  # v4 form, so the answer cannot be confused with a Host-allowlist failure —
  # a missing listener is 000 (refused), a listener that dislikes the name is
  # 403, and only a working one is 200. The two facts are asserted separately
  # for exactly that reason.
  do_request -H "Host: 127.0.0.1:$PORT_A" "$BASE6_A/health"
  V6_CODE="$RESP_CODE"
  V6_HEALTH_PID="$(health_field pid)"
  if [ "$V6_CODE" = "200" ]; then
    pass "v6: a second listener answers on [::1]:$PORT_A"
  elif [ "$V6_CODE" = "000" ]; then
    fail "v6: nothing is listening on [::1]:$PORT_A (connection refused) — main() binds no second listener"
  else
    fail "v6: [::1]:$PORT_A answered $V6_CODE, expected 200"
  fi

  # "the same server": one process, not a second instance. /health carries the
  # pid, so the two listeners agreeing on it is the proof.
  if [ "$V6_CODE" = "200" ] && [ -n "$V6_HEALTH_PID" ] && [ "$V6_HEALTH_PID" = "$V4_HEALTH_PID" ]; then
    pass "v6: the same process answers on both listeners (pid $V6_HEALTH_PID on each)"
  else
    fail "v6: /health over [::1] reported pid \"$V6_HEALTH_PID\", expected the v4 server's pid \"$V4_HEALTH_PID\""
  fi

  # The clause that motivates the whole block: a client that resolved
  # *.localhost to ::1 sends its own Host and must be served. curl sends
  # "[::1]:<port>" by default here; a real *.localhost client sends
  # "<label>.localhost:<port>". Both must work over the v6 listener.
  do_request "$BASE6_A/health"
  if [ "$RESP_CODE" = "200" ]; then
    pass "v6: the default Host curl sends over v6 ([::1]:<port>) is accepted"
  else
    fail "v6: [::1]:<port> as the Host over the v6 listener returned $RESP_CODE, expected 200"
  fi

  do_request -H "Host: clam.localhost:$PORT_A" "$BASE6_A/health"
  if [ "$RESP_CODE" = "200" ]; then
    pass "v6: a <label>.localhost:<port> Host is accepted over the v6 listener"
  else
    fail "v6: a <label>.localhost:<port> Host over v6 returned $RESP_CODE, expected 200"
  fi

  # Sharing the Handler means sharing the guard: the second listener is not a
  # back door around the Host check.
  do_request -H 'Host: evil.example' "$BASE6_A/health"
  if [ "$RESP_CODE" = "403" ]; then
    pass "v6: a foreign Host is rejected over the v6 listener too (403)"
  else
    fail "v6: a foreign Host over the v6 listener returned $RESP_CODE, expected 403"
  fi

  # Same Handler, so every route — not just /health — is reachable over v6.
  do_request -H "Host: 127.0.0.1:$PORT_A" "$BASE6_A/docs.json"
  if [ "$RESP_CODE" = "200" ]; then
    pass "v6: the second listener serves the same routes, not only /health"
  else
    fail "v6: /docs.json over the v6 listener returned $RESP_CODE, expected 200"
  fi

  # Loopback only, in the second family as well as the first: ('::1', PORT),
  # never ('::', PORT). Skipped where this host has no routable v6 address.
  V6_GLOBAL="$(python3 -c "
import socket
s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
try:
    s.connect(('2001:db8::1', 9))
    addr = s.getsockname()[0]
    print('' if addr.startswith('::1') or addr.startswith('fe80') else addr)
except OSError:
    print('')
finally:
    s.close()" 2> /dev/null)"
  if [ -z "$V6_GLOBAL" ]; then
    skip "v6: no routable IPv6 address on this host; cannot prove the second bind is not ::"
  else
    ext_code="$(curl -gs --max-time 3 -o /dev/null -w '%{http_code}' \
      -H "Host: 127.0.0.1:$PORT_A" "http://[$V6_GLOBAL]:$PORT_A/health" 2> /dev/null)"
    ext_code="${ext_code:-000}"
    if [ "$ext_code" = "000" ]; then
      pass "v6: not reachable on the routable address $V6_GLOBAL (binds ::1 only)"
    else
      fail "v6: answered on [$V6_GLOBAL]:$PORT_A with $ext_code — the second bind is not loopback-only"
    fi
  fi
fi

# A successful dual bind is silent: the note the contract allows is for the
# failure path.
if grep -q 'Traceback (most recent call last)' "$WORK/srv-a.stderr" 2> /dev/null; then
  fail "v6: a clean start left a traceback on stderr: $(head -3 "$WORK/srv-a.stderr" | tr '\n' ' ')"
else
  pass "v6: a clean start leaves no traceback on stderr"
fi

# =============================================================================
# Scenario C: the singleton race, against a server that already has both
# listeners. Run before the scenario-A server is stopped, since it needs a live
# winner on the port.
# =============================================================================
# The v4 bind keeps today's semantics exactly: a losing racer prints a
# diagnostic naming the port and exits 0. The second listener must not change
# that — in particular the loser must not exit non-zero because ::1 was busy
# too, and must not report the v6 port as the reason it lost.

env RENDER_DOC_PORT="$PORT_A" "$PY_BIN" "$SERVE" \
  > "$WORK/second.out" 2> "$WORK/second.err" &
SECOND_PID="$!"
SERVER_PIDS+=("$SECOND_PID")
SECOND_RC=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! kill -0 "$SECOND_PID" 2> /dev/null; then
    break
  fi
  sleep 0.3
done
if kill -0 "$SECOND_PID" 2> /dev/null; then
  fail "singleton: a second instance on a bound port did not exit promptly"
else
  wait "$SECOND_PID" 2> /dev/null
  SECOND_RC="$?"
  if [ "$SECOND_RC" = "0" ]; then
    pass "singleton: a second instance on a bound port still exits 0"
  else
    fail "singleton: a second instance exited $SECOND_RC, expected 0 (the v6 listener must not change the exit code)"
  fi
fi

if [ -s "$WORK/second.err" ] && grep -q "$PORT_A" "$WORK/second.err"; then
  pass "singleton: the losing instance still prints a diagnostic naming the port"
else
  fail "singleton: no stderr diagnostic naming port $PORT_A from the losing instance"
fi

do_request "$BASE4_A/health"
if [ "$RESP_CODE" = "200" ]; then
  pass "singleton: the winner still answers on v4 after the race"
else
  fail "singleton: the winner returned $RESP_CODE on v4 after the race, expected 200"
fi

if [ "$HAVE_V6" -eq 1 ]; then
  do_request -H "Host: 127.0.0.1:$PORT_A" "$BASE6_A/health"
  if [ "$RESP_CODE" = "200" ]; then
    pass "singleton: the losing instance did not disturb the winner's v6 listener"
  else
    fail "singleton: the winner's v6 listener returned $RESP_CODE after the race, expected 200"
  fi
else
  skip "singleton: the winner's v6 listener cannot be checked without IPv6"
fi

# The pidfile still belongs to the winner: a loser that exits must not have
# overwritten or removed it.
if [ "$(cat "$PIDFILE_A" 2> /dev/null)" = "$SRV_A_PID" ]; then
  pass "singleton: the pidfile still holds the winner's pid after the race"
else
  fail "singleton: the pidfile holds \"$(cat "$PIDFILE_A" 2> /dev/null)\", expected the winner's pid $SRV_A_PID"
fi

# =============================================================================
# Scenario D: shutdown — the v6 listener is closed alongside the v4 server and
# never outlives it
# =============================================================================

kill -TERM "$SRV_A_PID" 2> /dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  kill -0 "$SRV_A_PID" 2> /dev/null || break
  sleep 0.3
done
if kill -0 "$SRV_A_PID" 2> /dev/null; then
  fail "shutdown: the server did not exit on SIGTERM"
else
  pass "shutdown: the server exits on SIGTERM"
fi

if [ -e "$PIDFILE_A" ]; then
  fail "shutdown: the pidfile survived SIGTERM — the v6 listener changed the shutdown path"
else
  pass "shutdown: the pidfile is removed on SIGTERM, unchanged by the second listener"
fi

do_request "$BASE4_A/health"
if [ "$RESP_CODE" = "000" ]; then
  pass "shutdown: nothing answers on 127.0.0.1:$PORT_A afterwards"
else
  fail "shutdown: 127.0.0.1:$PORT_A still answered $RESP_CODE after the server exited"
fi

if [ "$HAVE_V6" -eq 1 ]; then
  do_request -H "Host: 127.0.0.1:$PORT_A" "$BASE6_A/health"
  if [ "$RESP_CODE" = "000" ]; then
    pass "shutdown: the v6 listener is closed alongside the v4 server, never outliving it"
  else
    fail "shutdown: [::1]:$PORT_A still answered $RESP_CODE after the server exited"
  fi
else
  skip "shutdown: whether the v6 listener outlives the server cannot be checked without IPv6"
fi

# =============================================================================
# Scenario B: the v6 bind FAILS — the clause the whole design rests on
# =============================================================================
# ('::1', PORT) is held by this file before the server starts, so the second
# bind is guaranteed to raise EADDRINUSE while the v4 port stays free: binding
# a specific v6 address never reserves the v4 one. Everything about the v4
# server must be indistinguishable from scenario A.

if [ "$HAVE_V6" -ne 1 ]; then
  skip "v6 failure: this environment has no ::1 to occupy, so the best-effort clause is unchecked"
  skip "v6 failure: whether a failed v6 bind leaves the v4 server working is unchecked"
  skip "v6 failure: whether the note stays to one stderr line is unchecked"
else
  PORT_B="$(free_dual_port)"
  if [ -z "$PORT_B" ]; then
    fail "v6 failure: no port free in both address families for the sabotage scenario"
  else
    BASE4_B="http://127.0.0.1:$PORT_B"
    PIDFILE_B="/tmp/render-doc-serve-$PORT_B.pid"
    reserve_v6 "$PORT_B"
    sleep 0.5
    if grep -q 'held' "$WORK/holder.err" 2> /dev/null; then
      pass "v6 failure: ('::1', $PORT_B) is occupied, so the server's v6 bind must fail"
    else
      fail "v6 failure: could not occupy ('::1', $PORT_B) -- $(tail -2 "$WORK/holder.err" 2> /dev/null | tr '\n' ' ')"
    fi

    start_server "$PORT_B" "$WORK/srv-b.stderr"
    SRV_B_PID="$LAST_PID"

    # THE clause: a failed v6 bind costs nothing on v4.
    if wait_healthy "$BASE4_B"; then
      pass "v6 failure: the v4 server is fully functional with the v6 bind refused"
    else
      fail "v6 failure: the v4 server never became healthy — a failed v6 bind broke it"
    fi

    if kill -0 "$SRV_B_PID" 2> /dev/null; then
      pass "v6 failure: the server is still running (a v6 bind failure is not fatal)"
    else
      fail "v6 failure: the server exited when the v6 bind failed"
    fi

    do_request "$BASE4_B/health"
    if [ "$RESP_CODE" = "200" ] && [ "$(health_field pid)" = "$SRV_B_PID" ]; then
      pass "v6 failure: /health on v4 answers normally, reporting the server's own pid"
    else
      fail "v6 failure: /health on v4 returned $RESP_CODE with pid \"$(health_field pid)\", expected 200 and $SRV_B_PID"
    fi

    if [ -f "$PIDFILE_B" ] && [ "$(cat "$PIDFILE_B" 2> /dev/null)" = "$SRV_B_PID" ]; then
      pass "v6 failure: the pidfile is written exactly as it would be on a clean start"
    else
      fail "v6 failure: pidfile $PIDFILE_B missing or does not hold pid $SRV_B_PID (got \"$(cat "$PIDFILE_B" 2> /dev/null)\")"
    fi

    # The whole routing surface still works: the failure is invisible to a v4
    # client, not merely survivable.
    do_request -H "Host: clam.localhost:$PORT_B" "$BASE4_B/docs.json"
    if [ "$RESP_CODE" = "200" ]; then
      pass "v6 failure: the widened Host allowlist still works on the v4 listener"
    else
      fail "v6 failure: an accepted Host on v4 returned $RESP_CODE, expected 200"
    fi

    # "at most a one-line stderr note", and never a traceback: the failure is
    # expected, so it must not read like a crash.
    if grep -q 'Traceback (most recent call last)' "$WORK/srv-b.stderr" 2> /dev/null; then
      fail "v6 failure: the refused v6 bind left a traceback on stderr: $(head -3 "$WORK/srv-b.stderr" | tr '\n' ' ')"
    else
      pass "v6 failure: the refused v6 bind leaves no traceback on stderr"
    fi
    B_NOISE="$(noise_lines "$WORK/srv-b.stderr")"
    if [ "${B_NOISE:-0}" -le 1 ]; then
      pass "v6 failure: stderr carries at most a one-line note ($B_NOISE line(s))"
    else
      fail "v6 failure: stderr carries $B_NOISE non-empty lines, expected at most one: $(head -3 "$WORK/srv-b.stderr" | tr '\n' ' ')"
    fi

    # The exit code is the v4 bind's business alone: a server whose v6 bind
    # failed must NOT take the EADDRINUSE-exit-0 path meant for a lost race.
    if kill -0 "$SRV_B_PID" 2> /dev/null; then
      pass "v6 failure: the v6 listener never reaches the exit path (the server did not exit 0)"
    else
      fail "v6 failure: the server exited — a busy ::1 was mistaken for a lost singleton race"
    fi

    kill -TERM "$SRV_B_PID" 2> /dev/null
    sleep 0.5
    if [ -e "$PIDFILE_B" ]; then
      fail "v6 failure: the pidfile survived SIGTERM"
    else
      pass "v6 failure: SIGTERM still removes the pidfile"
    fi
  fi
fi

# =============================================================================
# Left to acceptance review
# =============================================================================
# Two clauses are deliberately not pinned. That the second listener runs on a
# DAEMON thread is an implementation detail whose observable consequence —
# shutdown not hanging on it — is what scenario D asserts, so nothing here
# inspects threads. And "clients whose resolver takes *.localhost to ::1 reach
# the same server" depends on the resolver, not on this process: the halves
# that live in the code (a listener on ::1, and the name accepted there) are
# asserted; whether a given machine's resolver answers ::1 is not something a
# suite can or should fix.

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'dual-bind.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'dual-bind.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'dual-bind.test.sh: all assertions passed\n'
