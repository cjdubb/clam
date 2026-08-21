#!/usr/bin/env bash
# open.test.sh — verifies the docblock "Contract: B02 --open server client" in
# plugins/render-doc/scripts/render.sh, clause by clause.
#
# The opener-preference group and the PATH-shim technique behind it are ported
# from the upstream verification suite's --open section
# (clam-code/general/skills/render-doc/scripts/smoke.sh, lines 171-230). The
# health outcomes, the /doc URL shape, the --max-time guarantee and the exit-0
# invariant cover contract clauses that suite did not reach.
#
# No browser is ever opened: xdg-open and open are shadowed by shims that log
# the URL they were handed and exit. No default port is ever bound: every
# server, real or fake, gets a kernel-assigned free port — never 27183 — and is
# killed by the EXIT trap, so a real render-doc server on this machine is
# neither disturbed nor depended on.
#
# Wall clock: ~40s. Most of it is the --max-time group, which hands render.sh a
# deliberately wedged process and waits for its timeouts to fire, plus the
# one-off PATH mirror built below.
#
# Out of scope here: the render pipeline (render.test.sh) and the server's own
# behaviour (server.test.sh). This file asserts only what render.sh does with a
# server — never what the server does with a request.

set -uo pipefail  # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER="$SCRIPT_DIR/render.sh"
SERVE="$SCRIPT_DIR/serve.py"

WORK="$(mktemp -d)"
WORK="$(cd "$WORK" && pwd -P)"  # render.sh resolves the doc's dir; match it

OPEN_BIN="$WORK/open-bin"
OPEN_LOG="$WORK/open.log"
MIRROR="$WORK/path-mirror"
PYBIN="$WORK/py-bin"
FAKE="$WORK/fake_health.py"
ALL_ERR="$WORK/all.err"

mkdir -p "$OPEN_BIN" "$PYBIN"
: > "$OPEN_LOG"
: > "$ALL_ERR"

FIXTURE_PIDS=()
PORTS=()

# Contract: 003-B10 registry-litter teardown — open.test.sh scope (plan 003-followup-fixes)
#
# Behavior: every /tmp/render-doc-registry-<port>.json this suite can
#   cause to exist (render.sh --serve registers documents on the
#   servers it starts) is removed by the EXIT trap, alongside the
#   per-port pidfile cleanup that already exists.
# Inputs: the PORTS array (every port the suite claimed).
# Outputs: after any exit — pass, fail, or signal — no
#   /tmp/render-doc-registry-<port>.json remains for any port this
#   suite used.
# Errors: cleanup stays best-effort (rm -f); a file already gone is not
#   an error.
# Invariants: the live default port 27183 is never touched; other
#   suites' or servers' /tmp files are never removed; the suite's
#   assertion semantics are unchanged.
# Edge cases: a server killed before it ever wrote a registry file
#   (nothing to remove); several ports claimed in one run (all
#   cleaned).
cleanup() {
  local p f
  for p in ${FIXTURE_PIDS[@]+"${FIXTURE_PIDS[@]}"}; do
    [ -n "$p" ] && kill "$p" 2> /dev/null
  done
  # Servers render.sh spawned are detached on purpose; their pidfile is the
  # only handle this suite has on them.
  for p in ${PORTS[@]+"${PORTS[@]}"}; do
    f="/tmp/render-doc-serve-$p.pid"
    [ -f "$f" ] && kill "$(cat "$f" 2> /dev/null)" 2> /dev/null
  done
  sleep 0.3
  for p in ${FIXTURE_PIDS[@]+"${FIXTURE_PIDS[@]}"}; do
    [ -n "$p" ] && kill -9 "$p" 2> /dev/null
  done
  for p in ${PORTS[@]+"${PORTS[@]}"}; do
    # Ports are kernel-drawn and never 27183, so the live default server is out
    # of reach by construction; the guard says so anyway, because "the caller
    # promised" is thin cover for an rm in /tmp.
    [ "$p" = 27183 ] && continue
    f="/tmp/render-doc-serve-$p.pid"
    [ -f "$f" ] && kill -9 "$(cat "$f" 2> /dev/null)" 2> /dev/null
    # The registry file outlives the server that wrote it, and nothing else ever
    # deletes it: left behind, it is the stale state that fails the NEXT suite
    # to draw this port from the kernel. Best-effort — a port whose server never
    # got as far as registering a document has no file here, and that is normal.
    rm -f "$f" "/tmp/render-doc-registry-$p.json"
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
# Environment-dependent checks (a PATH this suite cannot mirror, a pid that
# cannot be freed) are reported and counted, never silently turned into a pass.
skip() {
  printf 'skip: %s\n' "$*"
  SKIPPED=$((SKIPPED + 1))
}

# --- Required tooling --------------------------------------------------------
# Without these there is nothing to test, and a vacuous green is worse than a
# red: the client under test is a curl/python3 program.
MISSING=0
for tool in python3 curl; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    fail "required tool not available: $tool"
    MISSING=1
  fi
done
if [ "$MISSING" -ne 0 ]; then
  printf 'open.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
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

# Every port this suite hands to render.sh is claimed through here, so the EXIT
# trap knows which pidfiles and registry files to clean up. Only a port that
# CLEARS the check is recorded: the trap deletes the /tmp files of every port in
# PORTS, so recording a port whose files were already there would make this
# suite delete exactly the foreign state it refused to clobber.
PORT=""
claim_port() {
  PORT="$(free_port)" || return 1
  [ -e "/tmp/render-doc-serve-$PORT.pid" ] && return 1
  PORTS+=("$PORT")
  return 0
}

alive() { kill -0 "$1" 2> /dev/null; }

wait_healthy() { # <port>
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if curl -sf --max-time 1 "http://127.0.0.1:$1/health" > /dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

wait_listening() { # <port> — TCP connect only; a silent holder answers nothing
  python3 - "$1" << 'PY'
import socket, sys, time
port = int(sys.argv[1])
for _ in range(80):
    try:
        socket.create_connection(('127.0.0.1', port), timeout=0.5).close()
        sys.exit(0)
    except OSError:
        time.sleep(0.1)
sys.exit(1)
PY
}

health_field() { # <port> <key>
  curl -sf --max-time 3 "http://127.0.0.1:$1/health" 2> /dev/null \
    | python3 -c "import json, sys
try:
    print(json.load(sys.stdin).get(sys.argv[1], ''))
except Exception:
    pass" "$2"
}

sha_of() { # <file>
  python3 -c "import hashlib, sys
with open(sys.argv[1], 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())" "$1" 2> /dev/null
}

enc() { # percent-encode a filesystem path for the /doc route
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$1"
}

abs_of() { # the absolute path render.sh derives for a document
  printf '%s/%s' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"
}

doc_url() { # <port> <doc path> — the deterministic URL the contract specifies
  printf 'http://127.0.0.1:%s/doc%s' "$1" "$(enc "$(abs_of "$2")")"
}

# Upstream hands open_file the plain output path; a file:// URL names the same
# local file. Either satisfies "file:// open of the rendered .html" — an
# http:// URL does not, and that is what these checks are really asking.
is_local_open() { # <logged url> <expected .html path>
  [ "$1" = "$2" ] || [ "$1" = "file://$2" ]
}

# --- Opener shims ------------------------------------------------------------
# Prepended to PATH, never replacing it, so they shadow the real xdg-open/open
# and no window is ever opened. Each logs "<tool>\t<url it was given>".
write_open_shim() { # <tool name>
  cat > "$OPEN_BIN/$1" << SHIM
#!/bin/sh
printf '%s\t%s\n' '$1' "\$1" >> "\${RD_OPEN_LOG:-$OPEN_LOG}"
exit 0
SHIM
  chmod +x "$OPEN_BIN/$1"
}
reset_openers() {
  rm -f "$OPEN_BIN"/*
  : > "$OPEN_LOG"
}

opened_tools() { cut -f1 "$OPEN_LOG" 2> /dev/null | tr '\n' ' ' | sed 's/ *$//'; }
opened_url() { cut -f2 "${1:-$OPEN_LOG}" 2> /dev/null | head -1; }
opened_count() { wc -l < "$OPEN_LOG" 2> /dev/null | tr -d ' '; }

# --- Running render.sh --open ------------------------------------------------
RUN_RC=0
RUN_ELAPSED=0
RUN_OUT="$WORK/run.out"
RUN_ERR="$WORK/run.err"

run_open() { # <render.sh> <doc> <port> <PATH for the run>
  : > "$OPEN_LOG"
  : > "$RUN_OUT"
  : > "$RUN_ERR"
  local start finish
  start="$(date +%s)"
  PATH="$4" RENDER_DOC_PORT="$3" "$1" "$2" --open > "$RUN_OUT" 2> "$RUN_ERR"
  RUN_RC=$?
  finish="$(date +%s)"
  RUN_ELAPSED=$((finish - start))
  cat "$RUN_ERR" >> "$ALL_ERR"
}

# Same, but with a hard wall-clock deadline: the --max-time clause is about a
# render that must return rather than hang, so the test must be able to observe
# "did not return" instead of hanging with it.
RUN_TIMED_OUT=0
run_open_bounded() { # <render.sh> <doc> <port> <PATH> <deadline seconds>
  : > "$OPEN_LOG"
  : > "$RUN_OUT"
  : > "$RUN_ERR"
  : > "$WORK/run.rc"
  local start finish waited bg
  start="$(date +%s)"
  (
    PATH="$4" RENDER_DOC_PORT="$3" "$1" "$2" --open > "$RUN_OUT" 2> "$RUN_ERR"
    printf '%s' "$?" > "$WORK/run.rc"
  ) &
  bg=$!
  RUN_TIMED_OUT=0
  waited=0
  # The rc file, not the pid, is the completion signal: a reaped background job
  # is ambiguous, a written exit status is not.
  while [ ! -s "$WORK/run.rc" ]; do
    if [ "$waited" -ge "$5" ]; then
      RUN_TIMED_OUT=1
      kill -9 "$bg" 2> /dev/null
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$bg" 2> /dev/null
  finish="$(date +%s)"
  RUN_ELAPSED=$((finish - start))
  RUN_RC="$(cat "$WORK/run.rc" 2> /dev/null)"
  : "${RUN_RC:=none}"
  cat "$RUN_ERR" >> "$ALL_ERR"
}

# --- Fake port holders -------------------------------------------------------
# A stand-in for whatever process happens to own the port: a foreign service, a
# render-doc server running outdated code, a server that will not die, or a
# wedged process that accepts connections and never answers.
cat > "$FAKE" << 'PY'
#!/usr/bin/env python3
"""fake_health.py <port> [--app N] [--version V] [--health-pid N]
                         [--pidfile-pid self|N] [--ignore-sigterm] [--silent]
"""
import json
import os
import signal
import socket
import sys
import time
import socketserver
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def clean_exit(*_a):
    # Exit 0 rather than dying by signal, so the test shell has no abnormal
    # job termination to announce over the suite's own output. Dying is still
    # dying: --ignore-sigterm below replaces this for SIGTERM.
    sys.exit(0)


signal.signal(signal.SIGTERM, clean_exit)
signal.signal(signal.SIGUSR1, clean_exit)  # the test's own "stop now"

port = int(sys.argv[1])
app = 'render-doc'
version = 'f' * 64
health_pid = os.getpid()
pidfile_pid = None
silent = False

args = sys.argv[2:]
i = 0
while i < len(args):
    a = args[i]
    if a == '--app':
        i += 1
        app = args[i]
    elif a == '--version':
        i += 1
        version = args[i]
    elif a == '--health-pid':
        i += 1
        health_pid = int(args[i])
    elif a == '--pidfile-pid':
        i += 1
        pidfile_pid = os.getpid() if args[i] == 'self' else int(args[i])
    elif a == '--ignore-sigterm':
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
    elif a == '--silent':
        silent = True
    else:
        raise SystemExit('fake_health.py: unknown option %s' % a)
    i += 1

if pidfile_pid is not None:
    with open('/tmp/render-doc-serve-%d.pid' % port, 'w') as f:
        f.write(str(pidfile_pid))

if silent:
    # Bound, listening, accepting — and never replying. A client without a
    # timeout waits here forever; that is the failure this block replaces.
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('127.0.0.1', port))
    sock.listen(16)
    held = []
    while True:
        try:
            conn, _ = sock.accept()
            held.append(conn)
        except OSError:
            time.sleep(0.1)

payload = {'app': app, 'version': version, 'pid': health_pid, 'port': port}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split('?')[0] != '/health':
            self.send_error(404)
            return
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


class QuietServer(ThreadingHTTPServer):
    # server_bind without socket.getfqdn(): the reverse-DNS lookup hangs on
    # hosts with a wedged resolver (GitHub's macOS runners), and the fixture
    # serves only loopback.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name = self.server_address[0]
        self.server_port = self.server_address[1]


QuietServer(('127.0.0.1', port), Handler).serve_forever()
PY

LAST_FAKE_PID=""
start_fake() { # <port> <fake_health.py args...>
  local port="$1"
  shift
  python3 "$FAKE" "$port" "$@" > "$WORK/fake-$port.log" 2>&1 &
  LAST_FAKE_PID=$!
  FIXTURE_PIDS+=("$LAST_FAKE_PID")
}

# SIGUSR1, not SIGKILL: a fixture that exits 0 leaves the test shell nothing
# to announce, so no job-control notice lands in the middle of the results.
stop_fake() { # <pid>
  kill -USR1 "$1" 2> /dev/null
}

LAST_REAL_PID=""
start_real_server() { # <port>
  RENDER_DOC_PORT="$1" python3 "$SERVE" > "$WORK/real-$1.log" 2>&1 &
  LAST_REAL_PID=$!
  FIXTURE_PIDS+=("$LAST_REAL_PID")
}

# A pid that is certainly nobody's: spawned, reaped, and never handed out again
# within this run (pids are allocated in increasing order).
dead_pid() {
  local p
  (exit 0) &
  p=$!
  wait "$p" 2> /dev/null
  printf '%s' "$p"
}

# --- Fixtures ----------------------------------------------------------------
DOC="$WORK/plan.md"
printf '# Plan: open client\n\n## Section\n\nBody text.\n' > "$DOC"
OUT_HTML="${DOC%.md}.html"

SPACED_DOC="$WORK/a spaced ünïcode doc.md"
printf '# Spaced\n\nBody.\n' > "$SPACED_DOC"

# A plugin copy with no serve.py beside render.sh, and one whose serve.py dies
# the moment it is started. Copies only: the repo's own scripts are untouched.
NOSERVE_PLUGIN="$WORK/plugin-no-serve"
cp -r "$PLUGIN_DIR" "$NOSERVE_PLUGIN"
rm -f "$NOSERVE_PLUGIN/scripts/serve.py"
NOSERVE_RENDER="$NOSERVE_PLUGIN/scripts/render.sh"

BADSERVE_PLUGIN="$WORK/plugin-bad-serve"
cp -r "$PLUGIN_DIR" "$BADSERVE_PLUGIN"
cat > "$BADSERVE_PLUGIN/scripts/serve.py" << 'PY'
#!/usr/bin/env python3
# Test double: a server that cannot start. Never binds, never answers.
import sys
sys.exit(1)
PY
BADSERVE_RENDER="$BADSERVE_PLUGIN/scripts/render.sh"

# Whether the retired design's state file is already lying around: only a file
# this run creates counts against the "writes no state file" clause.
STATE_FILE="/tmp/render-doc-serve.json"
STATE_FILE_PRESENT=0
[ -e "$STATE_FILE" ] && STATE_FILE_PRESENT=1

# A PATH on which a command is genuinely missing.
#
# Two clauses are about commands that are NOT there — "no python3 -> file://
# open" and "xdg-open is tried BEFORE open" — and prepending a shim cannot hide
# a command, only replace one. So this mirrors every directory on the caller's
# PATH into one directory of symlinks, minus python3/python/xdg-open/open, and
# the two groups that need an absent command run against that instead of the
# inherited PATH. Everything it creates lives in this suite's own $WORK.
MIRROR_OK=0
build_mirror() {
  mkdir -p "$MIRROR" || return 1
  # One ln per PATH entry rather than one per command; existing names are left
  # alone, so earlier PATH entries win exactly as they do in a real lookup.
  printf '%s\n' "$PATH" | tr ':' '\n' | while read -r d; do
    [ -n "$d" ] && [ -d "$d" ] && ln -s -- "$d"/* "$MIRROR/" 2> /dev/null
    :
  done
  rm -f "$MIRROR"/python3* "$MIRROR"/python "$MIRROR"/xdg-open "$MIRROR"/open
  local t
  for t in bash env sed awk grep cp mktemp base64 chmod dirname basename curl; do
    command -v "$t" > /dev/null 2>&1 || continue  # absent for everyone, not just here
    PATH="$MIRROR" command -v "$t" > /dev/null 2>&1 || return 1
  done
  PATH="$MIRROR" command -v python3 > /dev/null 2>&1 && return 1
  PATH="$MIRROR" command -v xdg-open > /dev/null 2>&1 && return 1
  PATH="$MIRROR" command -v open > /dev/null 2>&1 && return 1
  return 0
}
if build_mirror; then
  MIRROR_OK=1
  ln -s "$(command -v python3)" "$PYBIN/python3" 2> /dev/null
fi

SHIM_PATH="$OPEN_BIN:$PATH"           # everything real, openers shadowed
MIRROR_PATH="$OPEN_BIN:$MIRROR"       # ...and no python3 either
MIRROR_PY_PATH="$OPEN_BIN:$MIRROR:$PYBIN"  # python3 back, openers still absent

# The health "version" covers serve.py AND the template (F21): compute the
# same combined digest the server reports.
SERVE_SHA="$(python3 -c "import hashlib, sys
with open(sys.argv[1], 'rb') as f: a = f.read()
with open(sys.argv[2], 'rb') as f: b = f.read()
print(hashlib.sha256(a + b).hexdigest())" "$SERVE" "$SCRIPT_DIR/../assets/template.html")"

# --- 1. No python3, or no serve.py -------------------------------------------
# Clause 1: file:// open of the rendered .html, no server started, and nothing
# said about a server on stderr.

reset_openers
write_open_shim xdg-open
if ! claim_port; then
  fail "port $PORT already has a pidfile at /tmp/render-doc-serve-$PORT.pid; refusing to clobber it"
fi
run_open "$NOSERVE_RENDER" "$DOC" "$PORT" "$SHIM_PATH"
if [ "$RUN_RC" = "0" ]; then
  pass "no serve.py: render.sh exits 0"
else
  fail "no serve.py: render.sh exited $RUN_RC, expected 0"
fi
if is_local_open "$(opened_url)" "$OUT_HTML"; then
  pass "no serve.py: opens the rendered .html locally"
else
  fail "no serve.py: opened \"$(opened_url)\", expected the local $OUT_HTML"
fi
if [ ! -s "$RUN_ERR" ]; then
  pass "no serve.py: nothing printed to stderr about a server"
else
  fail "no serve.py: stderr was not silent (\"$(head -1 "$RUN_ERR")\")"
fi
if curl -sf --max-time 1 "http://127.0.0.1:$PORT/health" > /dev/null 2>&1; then
  fail "no serve.py: something is serving on port $PORT — a server was started"
else
  pass "no serve.py: no server was started on port $PORT"
fi

if [ "$MIRROR_OK" -ne 1 ]; then
  skip "no python3: this PATH could not be mirrored without python3, so the clause cannot be exercised"
else
  reset_openers
  write_open_shim xdg-open
  if ! claim_port; then
    fail "port $PORT already has a pidfile; refusing to clobber it"
  fi
  run_open "$RENDER" "$DOC" "$PORT" "$MIRROR_PATH"
  if [ "$RUN_RC" = "0" ]; then
    pass "no python3: render.sh exits 0"
  else
    fail "no python3: render.sh exited $RUN_RC, expected 0"
  fi
  if is_local_open "$(opened_url)" "$OUT_HTML"; then
    pass "no python3: opens the rendered .html locally"
  else
    fail "no python3: opened \"$(opened_url)\", expected the local $OUT_HTML"
  fi
  if [ ! -s "$RUN_ERR" ]; then
    pass "no python3: nothing printed to stderr about a server"
  else
    fail "no python3: stderr was not silent (\"$(head -1 "$RUN_ERR")\")"
  fi
  if curl -sf --max-time 1 "http://127.0.0.1:$PORT/health" > /dev/null 2>&1; then
    fail "no python3: something is serving on port $PORT — a server was started"
  else
    pass "no python3: no server was started on port $PORT"
  fi
fi

# --- 2. Nothing answers: spawn a server --------------------------------------
reset_openers
write_open_shim xdg-open
if ! claim_port; then
  fail "port $PORT already has a pidfile; refusing to clobber it"
fi
SPAWN_PORT="$PORT"
run_open "$RENDER" "$DOC" "$SPAWN_PORT" "$SHIM_PATH"
if [ "$RUN_RC" = "0" ]; then
  pass "empty port: render.sh exits 0"
else
  fail "empty port: render.sh exited $RUN_RC, expected 0"
fi
if [ "$(opened_url)" = "$(doc_url "$SPAWN_PORT" "$DOC")" ]; then
  pass "empty port: opens the server's /doc URL"
else
  fail "empty port: opened \"$(opened_url)\", expected \"$(doc_url "$SPAWN_PORT" "$DOC")\""
fi
# render.sh has already exited, so anything still answering was detached.
if [ "$(health_field "$SPAWN_PORT" app)" = "render-doc" ]; then
  pass "empty port: a render-doc server is serving after render.sh exited (spawned detached)"
else
  fail "empty port: no render-doc server on $SPAWN_PORT after the run"
fi
if [ "$(health_field "$SPAWN_PORT" version)" = "$SERVE_SHA" ]; then
  pass "empty port: the spawned server runs the serve.py beside render.sh"
else
  fail "empty port: server version \"$(health_field "$SPAWN_PORT" version)\", expected $SERVE_SHA"
fi

# --- 3. Health matches: reuse the running server ------------------------------
reset_openers
write_open_shim xdg-open
if ! claim_port; then
  fail "port $PORT already has a pidfile; refusing to clobber it"
fi
REUSE_PORT="$PORT"
start_real_server "$REUSE_PORT"
REUSE_PID="$LAST_REAL_PID"
if wait_healthy "$REUSE_PORT"; then
  pass "reuse: the fixture server is healthy on port $REUSE_PORT"
else
  fail "reuse: the fixture server never became healthy on port $REUSE_PORT"
fi
run_open "$RENDER" "$DOC" "$REUSE_PORT" "$SHIM_PATH"
if [ "$RUN_RC" = "0" ]; then
  pass "reuse: render.sh exits 0"
else
  fail "reuse: render.sh exited $RUN_RC, expected 0"
fi
if [ "$(opened_url)" = "$(doc_url "$REUSE_PORT" "$DOC")" ]; then
  pass "reuse: opens the server's /doc URL"
else
  fail "reuse: opened \"$(opened_url)\", expected \"$(doc_url "$REUSE_PORT" "$DOC")\""
fi
if alive "$REUSE_PID" && [ "$(health_field "$REUSE_PORT" pid)" = "$REUSE_PID" ]; then
  pass "reuse: a server whose version matches is left running, not killed and respawned"
else
  fail "reuse: the matching server was replaced (pid was $REUSE_PID, /health now says \"$(health_field "$REUSE_PORT" pid)\")"
fi

# --- 4. Foreign process on the port ------------------------------------------
reset_openers
write_open_shim xdg-open
if ! claim_port; then
  fail "port $PORT already has a pidfile; refusing to clobber it"
fi
FOREIGN_PORT="$PORT"
start_fake "$FOREIGN_PORT" --app some-other-app --version "$SERVE_SHA"
FOREIGN_PID="$LAST_FAKE_PID"
if wait_healthy "$FOREIGN_PORT"; then
  pass "foreign: the foreign fixture answers on port $FOREIGN_PORT"
else
  fail "foreign: the foreign fixture never answered on port $FOREIGN_PORT"
fi
run_open "$RENDER" "$DOC" "$FOREIGN_PORT" "$SHIM_PATH"
if [ "$RUN_RC" = "0" ]; then
  pass "foreign: render.sh exits 0"
else
  fail "foreign: render.sh exited $RUN_RC, expected 0"
fi
if is_local_open "$(opened_url)" "$OUT_HTML"; then
  pass "foreign: degrades to a local open of the rendered .html"
else
  fail "foreign: opened \"$(opened_url)\", expected the local $OUT_HTML"
fi
if [ -s "$RUN_ERR" ] && grep -q "$FOREIGN_PORT" "$RUN_ERR"; then
  pass "foreign: a stderr notice names the port"
else
  fail "foreign: no stderr notice naming port $FOREIGN_PORT (stderr: \"$(head -1 "$RUN_ERR")\")"
fi
if alive "$FOREIGN_PID" && [ "$(health_field "$FOREIGN_PORT" app)" = "some-other-app" ]; then
  pass "foreign: the process that owns the port is left alone"
else
  fail "foreign: the foreign process was killed or displaced"
fi
stop_fake "$FOREIGN_PID"

# --- 5. Version drift: killed by the pid in the health payload ----------------
reset_openers
write_open_shim xdg-open
if ! claim_port; then
  fail "port $PORT already has a pidfile; refusing to clobber it"
fi
DRIFT_PORT="$PORT"
# No pidfile is written, so the health payload's pid is the only handle.
start_fake "$DRIFT_PORT" --version 0000000000000000000000000000000000000000000000000000000000000000
DRIFT_PID="$LAST_FAKE_PID"
if wait_healthy "$DRIFT_PORT"; then
  pass "drift: the outdated fixture answers on port $DRIFT_PORT"
else
  fail "drift: the outdated fixture never answered on port $DRIFT_PORT"
fi
run_open "$RENDER" "$DOC" "$DRIFT_PORT" "$SHIM_PATH"
if [ "$RUN_RC" = "0" ]; then
  pass "drift: render.sh exits 0"
else
  fail "drift: render.sh exited $RUN_RC, expected 0"
fi
if alive "$DRIFT_PID"; then
  fail "drift: the outdated server (pid $DRIFT_PID, named in its health payload) was not killed"
else
  pass "drift: the outdated server is killed by the pid in its health payload"
fi
if [ "$(health_field "$DRIFT_PORT" version)" = "$SERVE_SHA" ]; then
  pass "drift: a fresh server running the serve.py on disk took the port"
else
  fail "drift: port $DRIFT_PORT serves version \"$(health_field "$DRIFT_PORT" version)\", expected $SERVE_SHA"
fi
if [ "$(opened_url)" = "$(doc_url "$DRIFT_PORT" "$DOC")" ]; then
  pass "drift: opens the replacement server's /doc URL"
else
  fail "drift: opened \"$(opened_url)\", expected \"$(doc_url "$DRIFT_PORT" "$DOC")\""
fi

# --- 6. Version drift: killed by the pidfile ---------------------------------
# Same clause, other handle: the health payload names a pid that is nobody's,
# so only /tmp/render-doc-serve-<port>.pid can identify the process to kill.
DEAD_PID="$(dead_pid)"
if alive "$DEAD_PID"; then
  skip "drift via pidfile: could not obtain a pid that is certainly free"
else
  reset_openers
  write_open_shim xdg-open
  if ! claim_port; then
    fail "port $PORT already has a pidfile; refusing to clobber it"
  fi
  PIDFILE_PORT="$PORT"
  start_fake "$PIDFILE_PORT" --version 1111111111111111111111111111111111111111111111111111111111111111 \
    --health-pid "$DEAD_PID" --pidfile-pid self
  PIDFILE_FAKE_PID="$LAST_FAKE_PID"
  if wait_healthy "$PIDFILE_PORT"; then
    pass "drift via pidfile: the outdated fixture answers on port $PIDFILE_PORT"
  else
    fail "drift via pidfile: the outdated fixture never answered on port $PIDFILE_PORT"
  fi
  run_open "$RENDER" "$DOC" "$PIDFILE_PORT" "$SHIM_PATH"
  if [ "$RUN_RC" = "0" ]; then
    pass "drift via pidfile: render.sh exits 0"
  else
    fail "drift via pidfile: render.sh exited $RUN_RC, expected 0"
  fi
  if alive "$PIDFILE_FAKE_PID"; then
    fail "drift via pidfile: the outdated server survived — /tmp/render-doc-serve-$PIDFILE_PORT.pid was not used"
  else
    pass "drift via pidfile: the outdated server is killed via /tmp/render-doc-serve-<port>.pid"
  fi
  if [ "$(health_field "$PIDFILE_PORT" version)" = "$SERVE_SHA" ]; then
    pass "drift via pidfile: a fresh server running the serve.py on disk took the port"
  else
    fail "drift via pidfile: port serves \"$(health_field "$PIDFILE_PORT" version)\", expected $SERVE_SHA"
  fi
  if [ "$(opened_url)" = "$(doc_url "$PIDFILE_PORT" "$DOC")" ]; then
    pass "drift via pidfile: opens the replacement server's /doc URL"
  else
    fail "drift via pidfile: opened \"$(opened_url)\", expected \"$(doc_url "$PIDFILE_PORT" "$DOC")\""
  fi
fi

# --- 7. Version drift that will not die --------------------------------------
reset_openers
write_open_shim xdg-open
if ! claim_port; then
  fail "port $PORT already has a pidfile; refusing to clobber it"
fi
STUBBORN_PORT="$PORT"
start_fake "$STUBBORN_PORT" --version 2222222222222222222222222222222222222222222222222222222222222222 \
  --pidfile-pid self --ignore-sigterm
STUBBORN_PID="$LAST_FAKE_PID"
if wait_healthy "$STUBBORN_PORT"; then
  pass "stubborn: the unkillable fixture answers on port $STUBBORN_PORT"
else
  fail "stubborn: the unkillable fixture never answered on port $STUBBORN_PORT"
fi
run_open "$RENDER" "$DOC" "$STUBBORN_PORT" "$SHIM_PATH"
if [ "$RUN_RC" = "0" ]; then
  pass "stubborn: render.sh exits 0"
else
  fail "stubborn: render.sh exited $RUN_RC, expected 0"
fi
if is_local_open "$(opened_url)" "$OUT_HTML"; then
  pass "stubborn: degrades to a local open of the rendered .html"
else
  fail "stubborn: opened \"$(opened_url)\", expected the local $OUT_HTML"
fi
if [ -s "$RUN_ERR" ] && grep -q "$STUBBORN_PORT" "$RUN_ERR"; then
  pass "stubborn: a stderr notice names the port that could not be replaced"
else
  fail "stubborn: no stderr notice naming port $STUBBORN_PORT (stderr: \"$(head -1 "$RUN_ERR")\")"
fi
if alive "$STUBBORN_PID"; then
  pass "stubborn: render.sh gave up rather than hanging on a server that will not die"
else
  fail "stubborn: the fixture died although it ignores SIGTERM — the test lost its subject"
fi
stop_fake "$STUBBORN_PID"

# --- 8. The spawn fails ------------------------------------------------------
reset_openers
write_open_shim xdg-open
if ! claim_port; then
  fail "port $PORT already has a pidfile; refusing to clobber it"
fi
BADSPAWN_PORT="$PORT"
run_open "$BADSERVE_RENDER" "$DOC" "$BADSPAWN_PORT" "$SHIM_PATH"
if [ "$RUN_RC" = "0" ]; then
  pass "spawn failure: render.sh exits 0"
else
  fail "spawn failure: render.sh exited $RUN_RC, expected 0"
fi
if is_local_open "$(opened_url)" "$OUT_HTML"; then
  pass "spawn failure: degrades to a local open of the rendered .html"
else
  fail "spawn failure: opened \"$(opened_url)\", expected the local $OUT_HTML"
fi
if [ -s "$RUN_ERR" ]; then
  pass "spawn failure: a stderr notice is printed"
else
  fail "spawn failure: nothing on stderr"
fi
if curl -sf --max-time 1 "http://127.0.0.1:$BADSPAWN_PORT/health" > /dev/null 2>&1; then
  fail "spawn failure: something answered on port $BADSPAWN_PORT after a server that cannot start"
else
  pass "spawn failure: nothing is left listening on port $BADSPAWN_PORT"
fi

# --- 9. --max-time: an unresponsive holder cannot hang the render ------------
# The failure this block replaces: a process that accepts the connection and
# never replies wedged render.sh forever, because its health check had no
# timeout. Behavioural first, source-level second.
reset_openers
write_open_shim xdg-open
if ! claim_port; then
  fail "port $PORT already has a pidfile; refusing to clobber it"
fi
WEDGE_PORT="$PORT"
start_fake "$WEDGE_PORT" --silent
WEDGE_PID="$LAST_FAKE_PID"
if wait_listening "$WEDGE_PORT"; then
  pass "wedged port: the silent fixture is accepting connections on port $WEDGE_PORT"
else
  fail "wedged port: the silent fixture never listened on port $WEDGE_PORT"
fi
# 30s is far above any timeout the contract implies (a 2s health poll and a
# handful of 1s ones) and far below "forever", which is what an untimed curl
# against this fixture would take.
run_open_bounded "$RENDER" "$DOC" "$WEDGE_PORT" "$SHIM_PATH" 30
if [ "$RUN_TIMED_OUT" -eq 0 ]; then
  pass "wedged port: render.sh returned in ${RUN_ELAPSED}s instead of hanging (every curl carries --max-time)"
else
  fail "wedged port: render.sh had not returned after ${RUN_ELAPSED}s — a curl with no --max-time is hanging on the silent process"
fi
if [ "$RUN_RC" = "0" ]; then
  pass "wedged port: render.sh exits 0"
else
  fail "wedged port: render.sh exited $RUN_RC, expected 0"
fi
if is_local_open "$(opened_url)" "$OUT_HTML"; then
  pass "wedged port: degrades to a local open of the rendered .html"
else
  fail "wedged port: opened \"$(opened_url)\", expected the local $OUT_HTML"
fi
if [ -s "$RUN_ERR" ]; then
  pass "wedged port: a stderr notice is printed"
else
  fail "wedged port: nothing on stderr"
fi
stop_fake "$WEDGE_PID"

# Source-level: every curl in the file carries --max-time. Full-line comments
# are blanked first (the contract docblock says "--max-time" itself), and line
# continuations are joined so a wrapped invocation is judged as one command.
CODE="$WORK/render.code.sh"
JOINED="$WORK/render.joined.sh"
sed 's/^[[:space:]]*#.*$//' "$RENDER" > "$CODE"
sed -e :a -e '/\\$/N; s/\\\n//; ta' "$CODE" > "$JOINED"
curl_total="$(grep -c 'curl' "$JOINED" 2> /dev/null)"
: "${curl_total:=0}"
curl_untimed="$(grep 'curl' "$JOINED" 2> /dev/null | grep -vc -- '--max-time')"
: "${curl_untimed:=0}"
if [ "$curl_total" -eq 0 ]; then
  fail "--max-time: render.sh runs no curl at all, so the health poll is missing"
elif [ "$curl_untimed" -eq 0 ]; then
  pass "--max-time: all $curl_total curl invocation(s) in render.sh carry --max-time"
else
  fail "--max-time: $curl_untimed of $curl_total curl invocation(s) carry no --max-time"
fi

# --- 10. The /doc URL --------------------------------------------------------
reset_openers
write_open_shim xdg-open
if ! claim_port; then
  fail "port $PORT already has a pidfile; refusing to clobber it"
fi
URL_PORT="$PORT"
start_real_server "$URL_PORT"
if wait_healthy "$URL_PORT"; then
  pass "url: the fixture server is healthy on port $URL_PORT"
else
  fail "url: the fixture server never became healthy on port $URL_PORT"
fi

run_open "$RENDER" "$SPACED_DOC" "$URL_PORT" "$SHIM_PATH"
SPACED_URL="$(opened_url)"
if [ "$RUN_RC" = "0" ]; then
  pass "url: render.sh exits 0 for a path with spaces and non-ASCII"
else
  fail "url: render.sh exited $RUN_RC for a path with spaces and non-ASCII"
fi
if [ "$SPACED_URL" = "$(doc_url "$URL_PORT" "$SPACED_DOC")" ]; then
  pass "url: a path with spaces and non-ASCII is percent-encoded into the URL"
else
  fail "url: opened \"$SPACED_URL\", expected \"$(doc_url "$URL_PORT" "$SPACED_DOC")\""
fi
case "$SPACED_URL" in
  *%20*) pass "url: the spaces really were encoded (%20 present)" ;;
  *) fail "url: no %20 in \"$SPACED_URL\" — the path was not percent-encoded" ;;
esac
# The markdown path, not the .html: the server derives the sibling itself.
case "$SPACED_URL" in
  *.html*) fail "url: the URL names the rendered .html; the contract says the source .md" ;;
  *.md) pass "url: the URL names the source .md, not the rendered .html" ;;
  *) fail "url: \"$SPACED_URL\" ends in neither .md nor .html" ;;
esac
case "$SPACED_URL" in
  "http://127.0.0.1:$URL_PORT/doc/"*)
    pass "url: the URL is /doc + the absolute path on 127.0.0.1:<configured port>"
    ;;
  *)
    fail "url: \"$SPACED_URL\" is not http://127.0.0.1:$URL_PORT/doc/<absolute path>"
    ;;
esac

# Deterministic: the same document yields the same URL on every render.
run_open "$RENDER" "$DOC" "$URL_PORT" "$SHIM_PATH"
FIRST_URL="$(opened_url)"
run_open "$RENDER" "$DOC" "$URL_PORT" "$SHIM_PATH"
SECOND_URL="$(opened_url)"
if [ -n "$FIRST_URL" ] && [ "$FIRST_URL" = "$SECOND_URL" ]; then
  pass "url: the same document opens the same URL twice (deterministic per file)"
else
  fail "url: two renders of one document opened \"$FIRST_URL\" and \"$SECOND_URL\""
fi

# --- 11. Opener preference ---------------------------------------------------
# xdg-open before open: some Linux distributions ship an unrelated `open`
# (openvt), so macOS's opener must never win. Ported from the upstream suite,
# with the PATH mirror added because this machine may well have a real
# xdg-open that a prepended shim could not hide.
if [ "$MIRROR_OK" -ne 1 ]; then
  skip "opener preference: this PATH could not be mirrored without xdg-open/open, so preference cannot be isolated"
else
  reset_openers
  write_open_shim xdg-open
  write_open_shim open
  if ! claim_port; then
    fail "port $PORT already has a pidfile; refusing to clobber it"
  fi
  run_open "$NOSERVE_RENDER" "$DOC" "$PORT" "$MIRROR_PY_PATH"
  if [ "$RUN_RC" = "0" ]; then
    pass "opener: render.sh exits 0 with both openers shimmed"
  else
    fail "opener: render.sh exited $RUN_RC with both openers shimmed"
  fi
  if [ "$(opened_tools)" = "xdg-open" ] && [ "$(opened_count)" = "1" ]; then
    pass "opener: xdg-open is preferred over open when both exist"
  else
    fail "opener: expected only xdg-open to fire, got \"$(opened_tools)\""
  fi

  reset_openers
  write_open_shim open
  if ! claim_port; then
    fail "port $PORT already has a pidfile; refusing to clobber it"
  fi
  run_open "$NOSERVE_RENDER" "$DOC" "$PORT" "$MIRROR_PY_PATH"
  if [ "$RUN_RC" = "0" ]; then
    pass "opener: render.sh exits 0 with only open available"
  else
    fail "opener: render.sh exited $RUN_RC with only open available"
  fi
  if [ "$(opened_tools)" = "open" ] && [ "$(opened_count)" = "1" ]; then
    pass "opener: falls back to open when xdg-open is unavailable"
  else
    fail "opener: expected only open to fire, got \"$(opened_tools)\""
  fi

  reset_openers
  if ! claim_port; then
    fail "port $PORT already has a pidfile; refusing to clobber it"
  fi
  run_open "$NOSERVE_RENDER" "$DOC" "$PORT" "$MIRROR_PY_PATH"
  if [ "$RUN_RC" = "0" ]; then
    pass "opener: render.sh exits 0 when no opener exists at all"
  else
    fail "opener: render.sh exited $RUN_RC with no opener available"
  fi
  if [ -s "$RUN_ERR" ] && grep -qF "$OUT_HTML" "$RUN_ERR"; then
    pass "opener: with no opener, stderr names the file to view manually"
  else
    fail "opener: with no opener, stderr does not name $OUT_HTML (stderr: \"$(head -1 "$RUN_ERR")\")"
  fi
fi

# --- 12. Two renders racing to spawn -----------------------------------------
# Edge case: one wins the bind, the loser's serve.py exits 0 by design, and
# both renders open the winner's URL.
reset_openers
write_open_shim xdg-open
if ! claim_port; then
  fail "port $PORT already has a pidfile; refusing to clobber it"
fi
RACE_PORT="$PORT"
RACE_DOC_1="$WORK/race-1.md"
RACE_DOC_2="$WORK/race-2.md"
printf '# Race one\n' > "$RACE_DOC_1"
printf '# Race two\n' > "$RACE_DOC_2"
: > "$WORK/race-1.log"
: > "$WORK/race-2.log"
RD_OPEN_LOG="$WORK/race-1.log" PATH="$SHIM_PATH" RENDER_DOC_PORT="$RACE_PORT" \
  "$RENDER" "$RACE_DOC_1" --open > /dev/null 2> "$WORK/race-1.err" &
RACE_BG_1=$!
RD_OPEN_LOG="$WORK/race-2.log" PATH="$SHIM_PATH" RENDER_DOC_PORT="$RACE_PORT" \
  "$RENDER" "$RACE_DOC_2" --open > /dev/null 2> "$WORK/race-2.err" &
RACE_BG_2=$!
wait "$RACE_BG_1"
RACE_RC_1=$?
wait "$RACE_BG_2"
RACE_RC_2=$?
cat "$WORK/race-1.err" "$WORK/race-2.err" >> "$ALL_ERR"
if [ "$RACE_RC_1" -eq 0 ] && [ "$RACE_RC_2" -eq 0 ]; then
  pass "race: both concurrent renders exit 0"
else
  fail "race: concurrent renders exited $RACE_RC_1 and $RACE_RC_2, expected 0 and 0"
fi
if [ "$(opened_url "$WORK/race-1.log")" = "$(doc_url "$RACE_PORT" "$RACE_DOC_1")" ] \
  && [ "$(opened_url "$WORK/race-2.log")" = "$(doc_url "$RACE_PORT" "$RACE_DOC_2")" ]; then
  pass "race: both renders open their own /doc URL on the winner's port"
else
  fail "race: opened \"$(opened_url "$WORK/race-1.log")\" and \"$(opened_url "$WORK/race-2.log")\", expected each document's own /doc URL"
fi
if [ "$(health_field "$RACE_PORT" version)" = "$SERVE_SHA" ]; then
  pass "race: one server is left serving on port $RACE_PORT"
else
  fail "race: no current render-doc server on port $RACE_PORT after the race"
fi

# --- 13. Invariants ----------------------------------------------------------
# Loopback only, on the configured port: no other host may appear in the code.
http_hosts="$(grep -o 'http://[^"'"'"' )]*' "$CODE" 2> /dev/null | sed 's|^http://||; s|/.*$||; s|:.*$||' | sort -u)"
if [ -z "$http_hosts" ]; then
  fail "invariant: render.sh contacts no http:// URL at all, so it cannot reach the server"
elif [ "$http_hosts" = "127.0.0.1" ]; then
  pass "invariant: the only host render.sh contacts is 127.0.0.1"
else
  fail "invariant: render.sh names host(s) other than 127.0.0.1: $(printf '%s' "$http_hosts" | tr '\n' ' ')"
fi

# The port is configurable and defaults to 27183. Only the default can be
# checked here: binding 27183 to prove it would touch a real server.
if grep -q 'RENDER_DOC_PORT' "$CODE" && grep -q '27183' "$CODE"; then
  pass "invariant: the port comes from RENDER_DOC_PORT and defaults to 27183"
else
  fail "invariant: no RENDER_DOC_PORT/27183 default in render.sh"
fi

# The retired design's state file: not read, not written, not referenced.
if grep -q 'render-doc-serve\.json' "$CODE"; then
  fail "invariant: render.sh still references the retired state file /tmp/render-doc-serve.json"
else
  pass "invariant: no reference to the retired /tmp/render-doc-serve.json"
fi
if [ "$STATE_FILE_PRESENT" -eq 1 ]; then
  skip "invariant: $STATE_FILE already existed before this run; cannot attribute it"
elif [ -e "$STATE_FILE" ]; then
  fail "invariant: this run created a state file at $STATE_FILE"
else
  pass "invariant: no state file was written"
fi

# Every degradation notice above should be render-doc's own sentence; a shell
# or curl diagnostic reaching the user's terminal is a different failure.
if grep -qE 'command not found|Traceback \(most recent call last\)|syntax error|^curl:' "$ALL_ERR" 2> /dev/null; then
  fail "outputs: a tool diagnostic leaked to stderr: \"$(grep -Em1 'command not found|Traceback \(most recent call last\)|syntax error|^curl:' "$ALL_ERR")\""
else
  pass "outputs: every stderr line came from render.sh itself"
fi

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'open.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'open.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'open.test.sh: all assertions passed\n'
