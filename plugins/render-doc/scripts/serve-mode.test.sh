#!/usr/bin/env bash
# serve-mode.test.sh — verifies the docblock "Contract: B08 --serve registration
# mode" in plugins/render-doc/scripts/render.sh, clause by clause.
#
# --serve is the registration-only sibling of --open: it makes a document
# available ON the shared server and prints its URL, opens no browser, and —
# unlike --open — refuses to degrade to file://, because registration is the
# whole point. Every check below is end-to-end: a real render.sh run against a
# real (or deliberately broken) server, asserted on what the run printed, what
# it exited, and what the server afterwards says it knows.
#
# Two techniques carry most of the file, both ported from open.test.sh:
#   - the opener shims, prepended to PATH so a stray browser open is recorded
#     rather than shown. Here they are a pure negative: --serve must NEVER fire
#     one, on any path, so every run's log is folded into $ALL_OPEN and the
#     whole aggregate is asserted empty at the end;
#   - fake_health.py, the stand-in for whatever owns the port (a foreign
#     service, an outdated server, one that will not die, one that never
#     answers).
#
# What is NOT ported, and matters most: every fixture document lives in a
# scratch git repo under $HOME. open.test.sh renders out of /tmp and never
# needs the server to accept anything, but --serve's success clause IS the
# server accepting the /doc request, and serve.py's scope rules reject any path
# that is not a .md under $HOME inside a git worktree. A /tmp fixture would
# make every happy-path check here vacuously fail. The one deliberate
# exception is the out-of-scope group, which uses /tmp precisely because the
# server must refuse it.
#
# No default port is ever bound: every server, real or fake, gets a
# kernel-assigned free port — never 27183 — and both its pidfile and its
# registry file are cleaned by the EXIT trap, so a real render-doc server on
# this machine is neither disturbed nor depended on.
#
# Wall clock: ~45s. Most of it is the groups that hand render.sh a server that
# will not answer, will not die, or will not start, and wait for its timeouts.
#
# Out of scope here: the render pipeline (render.test.sh), the --open client
# (open.test.sh), and the server's own routes (server.test.sh,
# server-registry.test.sh, server-index.test.sh). This file asserts only what
# render.sh --serve does, and uses /docs.json and / only as the observable that
# registration really happened.

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER="$SCRIPT_DIR/render.sh"
SERVE="$SCRIPT_DIR/serve.py"

# In $HOME, not /tmp: serve.py refuses to serve anything outside it, and a
# refused /doc request is exactly what this suite must not trip over by
# accident. Realpath-resolved because scope_error compares realpaths.
WORK="$(mktemp -d "$HOME/.render-doc-serve-test-XXXXXX")" || {
  printf "serve-mode.test.sh: could not create a scratch directory under \$HOME\n" >&2
  exit 1
}
WORK="$(cd "$WORK" && pwd -P)"

# The one fixture that must NOT be servable: /tmp is outside $HOME.
OUT_SCOPE="$(mktemp -d)"
OUT_SCOPE="$(cd "$OUT_SCOPE" && pwd -P)"

OPEN_BIN="$WORK/open-bin"
OPEN_LOG="$WORK/open.log"
ALL_OPEN="$WORK/all-open.log"
MIRROR="$WORK/path-mirror"
PYBIN="$WORK/py-bin"
FAKE="$WORK/fake_health.py"
ALL_ERR="$WORK/all.err"

mkdir -p "$OPEN_BIN" "$PYBIN"
: > "$OPEN_LOG"
: > "$ALL_OPEN"
: > "$ALL_ERR"

FIXTURE_PIDS=()
PORTS=()

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
    f="/tmp/render-doc-serve-$p.pid"
    [ -f "$f" ] && kill -9 "$(cat "$f" 2> /dev/null)" 2> /dev/null
    rm -f "$f" "/tmp/render-doc-registry-$p.json"
  done
  rm -rf "$WORK" "$OUT_SCOPE"
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
# Environment-dependent checks (a PATH this suite cannot mirror, a $HOME that
# is itself inside a git worktree) are reported and counted, never silently
# turned into a pass.
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
  printf 'serve-mode.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
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

# Contract: 003-B10 registry-litter teardown — claim_port retry (plan 003-followup-fixes)
#
# Behavior: claim_port retries freshly drawn ports a BOUNDED, small,
#   fixed number of times when a drawn port collides with stale /tmp
#   state (an existing pidfile or registry file), failing only when
#   every attempt collides.
# Inputs: none (each attempt draws through free_port).
# Outputs: PORT set and appended to PORTS on success; non-zero only
#   after the bounded attempts are exhausted.
# Errors: a free_port failure still propagates as failure immediately.
# Invariants: 27183 is never claimed; another process's /tmp state is
#   never deleted to claim a port — the refuse-to-clobber property is
#   preserved as collision AVOIDANCE, not clobbering; every claimed
#   port still lands in PORTS so the EXIT trap cleans it.
# Edge cases: first draw clean (no retry, today's fast path); all
#   attempts colliding (fails, message still names the collision); a
#   pidfile without a registry file and vice versa (each alone counts
#   as a collision).

# Every port this suite hands to render.sh is claimed through here, so the EXIT
# trap knows which pidfile and which registry file to clean up. A port whose
# /tmp files already exist is never clobbered — it is abandoned and another one
# is drawn, which is the only safe move: those files may belong to a live server
# this suite knows nothing about.
#
# The kernel hands out ports the /tmp litter of an earlier run can already be
# sitting on, so one collision says nothing about the next draw. A small fixed
# number of attempts turns that into the non-event it is; giving up only after
# all of them keeps a genuinely wedged environment loud.
#
# Only a port that CLEARS the check is recorded in PORTS. The trap deletes the
# pidfile and registry file of every port in there, so recording a collided one
# would make this suite delete exactly the foreign state it just refused to
# clobber.
PORT=""
claim_port() {
  # Five attempts, spelled the way this file's other bounded waits are.
  for _ in 1 2 3 4 5; do
    PORT="$(free_port)" || return 1
    if [ ! -e "/tmp/render-doc-serve-$PORT.pid" ] \
      && [ ! -e "/tmp/render-doc-registry-$PORT.json" ]; then
      PORTS+=("$PORT")
      return 0
    fi
  done
  # PORT still names the last collision, so the caller's message stays true.
  return 1
}

alive() { kill -0 "$1" 2> /dev/null; }

wait_healthy() { # <port>
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
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

# The registration observable. B02's registry is what the server knows it has
# served, and /docs.json is its public face: a document that reached the
# registry is a document the /doc request really rendered and recorded.
docs_json_paths() { # <port>
  curl -sf --max-time 5 "http://127.0.0.1:$1/docs.json" 2> /dev/null \
    | python3 -c "import json, sys
try:
    for d in json.load(sys.stdin).get('docs', []):
        print(d.get('path', ''))
except Exception:
    pass"
}

registered() { # <port> <doc path>
  docs_json_paths "$1" | grep -qxF "$(abs_of "$2")"
}

index_html() { # <port>
  curl -sf --max-time 5 "http://127.0.0.1:$1/" 2> /dev/null
}

# True when no ancestor of <dir> carries a .git entry — the condition serve.py's
# in_git_worktree() checks. Used to decide whether the "not inside a git
# worktree" scope case can be exercised on this machine at all.
no_git_ancestor() { # <dir>
  local d="$1"
  while :; do
    [ -e "$d/.git" ] && return 1
    [ "$d" = "/" ] && return 0
    d="$(dirname "$d")"
  done
}

# --- Opener shims ------------------------------------------------------------
# Prepended to PATH, never replacing it, so they shadow the real xdg-open/open
# and no window is ever opened. Each logs "<tool>\t<url it was given>". Under
# --serve every one of these logs must stay empty: the contract's clause 5 is
# "open no browser, ever".
write_open_shim() { # <tool name>
  cat > "$OPEN_BIN/$1" << SHIM
#!/bin/sh
printf '%s\t%s\n' '$1' "\$1" >> "\${RD_OPEN_LOG:-$OPEN_LOG}"
exit 0
SHIM
  chmod +x "$OPEN_BIN/$1"
}
write_open_shim xdg-open
write_open_shim open

# --- Running render.sh --serve -----------------------------------------------
RUN_RC=0
RUN_ELAPSED=0
RUN_OUT="$WORK/run.out"
RUN_ERR="$WORK/run.err"

run_serve() { # <render.sh> <doc> <port> <PATH for the run>
  : > "$OPEN_LOG"
  : > "$RUN_OUT"
  : > "$RUN_ERR"
  PATH="$4" RENDER_DOC_PORT="$3" "$1" "$2" --serve > "$RUN_OUT" 2> "$RUN_ERR"
  RUN_RC=$?
  cat "$RUN_ERR" >> "$ALL_ERR"
  cat "$OPEN_LOG" >> "$ALL_OPEN"
}

# Same, but with a hard wall-clock deadline: the --max-time clause is about a
# run that must return rather than hang, so the test must be able to observe
# "did not return" instead of hanging with it.
RUN_TIMED_OUT=0
run_serve_bounded() { # <render.sh> <doc> <port> <PATH> <deadline seconds>
  : > "$OPEN_LOG"
  : > "$RUN_OUT"
  : > "$RUN_ERR"
  : > "$WORK/run.rc"
  local start finish waited bg
  start="$(date +%s)"
  (
    PATH="$4" RENDER_DOC_PORT="$3" "$1" "$2" --serve > "$RUN_OUT" 2> "$RUN_ERR"
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
  cat "$OPEN_LOG" >> "$ALL_OPEN"
}

# --- Assertions on one run ---------------------------------------------------

serving_lines() { grep -c '^serving: ' "$RUN_OUT" 2> /dev/null || true; }
serving_url() { grep '^serving: ' "$RUN_OUT" 2> /dev/null | head -1 | sed 's/^serving: //'; }

assert_rc() { # <expected> <label>
  if [ "$RUN_RC" = "$1" ]; then
    pass "$2: exit $1"
  else
    fail "$2: exited $RUN_RC, expected $1"
  fi
}

assert_no_browser() { # <label>
  if [ ! -s "$OPEN_LOG" ]; then
    pass "$1: no browser was opened"
  else
    fail "$1: a browser opener fired ($(tr '\t' ' ' < "$OPEN_LOG" | head -1)) — --serve opens nothing"
  fi
}

assert_serving_line() { # <expected url> <label>
  local n url
  n="$(serving_lines)"
  : "${n:=0}"
  url="$(serving_url)"
  if [ "$n" = "1" ]; then
    pass "$2: exactly one 'serving:' line on stdout"
  else
    fail "$2: $n 'serving:' line(s) on stdout, expected exactly 1"
  fi
  if [ "$url" = "$1" ]; then
    pass "$2: the serving URL is the deterministic /doc URL"
  else
    fail "$2: serving URL was \"$url\", expected \"$1\""
  fi
}

assert_no_serving_line() { # <label>
  local n
  n="$(serving_lines)"
  : "${n:=0}"
  if [ "$n" = "0" ]; then
    pass "$1: no 'serving:' line was printed"
  else
    fail "$1: printed a 'serving:' line although the run failed"
  fi
}

# The stub this suite is written against already exits 3 with a stderr line, so
# "fails non-zero with a note" is green before a line of the block is written.
# Every failure group therefore pins BOTH the reason-specific wording and this:
# the note is render.sh's own diagnosis, not the scaffold's placeholder.
assert_not_stub() { # <label>
  if grep -qi 'notimplemented' "$RUN_ERR"; then
    fail "$1: stderr is still the scaffold's NotImplemented line, not a reason for this failure"
  else
    pass "$1: stderr is a real diagnosis, not the NotImplemented stub"
  fi
}

assert_stderr_matches() { # <ere> <label>
  if [ -s "$RUN_ERR" ] && grep -qiE -- "$1" "$RUN_ERR"; then
    pass "$2"
  else
    fail "$2 (stderr: \"$(head -1 "$RUN_ERR")\")"
  fi
}

# Invariant: a --serve failure exits AFTER the successful render, so the
# sibling .html exists and the pipeline's own line was printed either way.
assert_render_survived() { # <doc> <label>
  local html="${1%.md}.html"
  if [ -s "$html" ]; then
    pass "$2: the sibling .html was still written"
  else
    fail "$2: no sibling .html at $html — the render did not survive"
  fi
  if grep -q "^rendered: " "$RUN_OUT"; then
    pass "$2: the pipeline's 'rendered:' line is still printed"
  else
    fail "$2: no 'rendered:' line on stdout — the render pipeline changed"
  fi
}

# --- Fake port holders -------------------------------------------------------
# A stand-in for whatever process happens to own the port: a foreign service, a
# render-doc server running outdated code, a server that will not die, or a
# wedged process that accepts connections and never answers. Ported verbatim
# from open.test.sh — the two suites exercise the same server posture.
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
    # timeout waits here forever; that is the failure this block must not have.
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

# --- Fixtures ----------------------------------------------------------------
# A scratch git repo under $HOME: the server's scope rules demand a .md that
# resolves under $HOME and sits inside a git worktree, and --serve's success
# clause is the server ACCEPTING the request.
REPO="$WORK/repo"
mkdir -p "$REPO"
if command -v git > /dev/null 2>&1; then
  git init -q "$REPO" 2> /dev/null || mkdir -p "$REPO/.git"
else
  mkdir -p "$REPO/.git"
fi
if [ -e "$REPO/.git" ]; then
  pass "fixture: a scratch git worktree exists under \$HOME"
else
  fail "fixture: could not make $REPO look like a git worktree — no happy path can be checked"
fi

DOC="$REPO/plan.md"
printf '# Plan: serve mode\n\n## Section\n\nBody text.\n' > "$DOC"

SPACED_DOC="$REPO/a spaced ünïcode doc.md"
printf '# Spaced\n\nBody.\n' > "$SPACED_DOC"

# A work-graph document, so the Outputs clause's "a WORKGRAPH.md now appears on
# the index" has a subject. The markers are the work-graph protocol's
# machine-read ones the index reads: "- Status: open" lines and a Focus line.
WG_REPO="$WORK/wg-repo"
mkdir -p "$WG_REPO"
if command -v git > /dev/null 2>&1; then
  git init -q "$WG_REPO" 2> /dev/null || mkdir -p "$WG_REPO/.git"
else
  mkdir -p "$WG_REPO/.git"
fi
WG_DOC="$WG_REPO/WORKGRAPH.md"
cat > "$WG_DOC" << 'MD'
# Work Graph

Focus: N2

## N1: First
- Status: open

## N2: Second
- Status: open

## N3: Third
- Status: done
MD

# Out of scope on purpose: /tmp is not under $HOME, so the server must refuse
# the /doc request for this one.
OUT_DOC="$OUT_SCOPE/outside.md"
printf '# Outside\n\nBody.\n' > "$OUT_DOC"

# Under $HOME but in no git worktree — the other half of the scope clause. Only
# usable when nothing above it carries a .git, which is a property of the
# machine, not of this suite.
LOOSE_DIR="$WORK/loose"
mkdir -p "$LOOSE_DIR"
LOOSE_DOC="$LOOSE_DIR/loose.md"
printf '# Loose\n\nBody.\n' > "$LOOSE_DOC"

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

# A PATH on which python3 is genuinely missing. Prepending a shim cannot hide a
# command, only replace one, so the "no python3" clause needs every directory
# on the caller's PATH mirrored into one directory of symlinks, minus python3.
MIRROR_OK=0
build_mirror() {
  mkdir -p "$MIRROR" || return 1
  printf '%s\n' "$PATH" | tr ':' '\n' | while read -r d; do
    [ -n "$d" ] && [ -d "$d" ] && ln -s -- "$d"/* "$MIRROR/" 2> /dev/null
    :
  done
  rm -f "$MIRROR"/python3* "$MIRROR"/python "$MIRROR"/xdg-open "$MIRROR"/open
  local t
  for t in bash env sed awk grep cp mktemp base64 chmod dirname basename curl; do
    command -v "$t" > /dev/null 2>&1 || continue # absent for everyone, not just here
    PATH="$MIRROR" command -v "$t" > /dev/null 2>&1 || return 1
  done
  PATH="$MIRROR" command -v python3 > /dev/null 2>&1 && return 1
  return 0
}
if build_mirror; then
  MIRROR_OK=1
  ln -s "$(command -v python3)" "$PYBIN/python3" 2> /dev/null
fi

SHIM_PATH="$OPEN_BIN:$PATH"     # everything real, openers shadowed and logged
MIRROR_PATH="$OPEN_BIN:$MIRROR" # ...and no python3 either

# The health "version" covers serve.py AND the template (F21): compute the
# same combined digest the server reports.
SERVE_SHA="$(python3 -c "import hashlib, sys
with open(sys.argv[1], 'rb') as f: a = f.read()
with open(sys.argv[2], 'rb') as f: b = f.read()
print(hashlib.sha256(a + b).hexdigest())" "$SERVE" "$SCRIPT_DIR/../assets/template.html")"

# =============================================================================
# Acceptance signal: the scaffold's stub is gone from the source.
# Read the file, not a run: this is the one check that is meaningful only
# against render.sh itself.
# =============================================================================
if grep -qi 'notimplemented' "$RENDER"; then
  fail "acceptance: render.sh still carries a NotImplemented stub for --serve"
else
  pass "acceptance: no NotImplemented stub remains in render.sh"
fi

# =============================================================================
# 1. Nothing on the port: spawn, render, register, print, open nothing
# Behavior clauses 1-5, and the Outputs clause's registration effect.
# =============================================================================
if ! claim_port; then
  fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
fi
SPAWN_PORT="$PORT"
run_serve "$RENDER" "$DOC" "$SPAWN_PORT" "$SHIM_PATH"

assert_rc 0 "empty port"
assert_render_survived "$DOC" "empty port"
assert_serving_line "$(doc_url "$SPAWN_PORT" "$DOC")" "empty port"
assert_no_browser "empty port"

if [ ! -s "$RUN_ERR" ]; then
  pass "empty port: stderr is silent on the success path"
else
  fail "empty port: stderr was not silent (\"$(head -1 "$RUN_ERR")\")"
fi

# Exactly two stdout lines: the pipeline's "rendered:" and this block's one
# "serving:". The contract's "print exactly one line" is this block's line, and
# the render pipeline above it is finished code that must keep printing its own.
STDOUT_LINES="$(wc -l < "$RUN_OUT" | tr -d ' ')"
if [ "$STDOUT_LINES" = "2" ]; then
  pass "empty port: stdout is exactly 'rendered:' + one 'serving:' line"
else
  fail "empty port: stdout has $STDOUT_LINES line(s), expected 2 (rendered + serving)"
fi
if [ "$(tail -1 "$RUN_OUT")" = "serving: $(doc_url "$SPAWN_PORT" "$DOC")" ]; then
  pass "empty port: the serving line is the last thing printed"
else
  fail "empty port: the last stdout line is \"$(tail -1 "$RUN_OUT")\""
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

# The registration clause's real observable.
if registered "$SPAWN_PORT" "$DOC"; then
  pass "empty port: the document is registered — it appears in GET /docs.json"
else
  fail "empty port: $(abs_of "$DOC") is not in GET /docs.json — the /doc request never registered it"
fi

# The server-side render really happened: /doc returns the page, not an error.
if curl -sf --max-time 5 "$(doc_url "$SPAWN_PORT" "$DOC")" > /dev/null 2>&1; then
  pass "empty port: the serving URL really serves the document"
else
  fail "empty port: the URL printed by --serve does not serve anything"
fi

# =============================================================================
# 2. A current server is already running: reuse it, register against it
# =============================================================================
if ! claim_port; then
  fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
fi
REUSE_PORT="$PORT"
start_real_server "$REUSE_PORT"
REUSE_PID="$LAST_REAL_PID"
if wait_healthy "$REUSE_PORT"; then
  pass "reuse: the fixture server is healthy on port $REUSE_PORT"
else
  fail "reuse: the fixture server never became healthy on port $REUSE_PORT"
fi

run_serve "$RENDER" "$DOC" "$REUSE_PORT" "$SHIM_PATH"
assert_rc 0 "reuse"
assert_serving_line "$(doc_url "$REUSE_PORT" "$DOC")" "reuse"
assert_no_browser "reuse"

if alive "$REUSE_PID" && [ "$(health_field "$REUSE_PORT" pid)" = "$REUSE_PID" ]; then
  pass "reuse: a server whose version matches is left running, not killed and respawned"
else
  fail "reuse: the matching server was replaced (pid was $REUSE_PID, /health now says \"$(health_field "$REUSE_PORT" pid)\")"
fi
if registered "$REUSE_PORT" "$DOC"; then
  pass "reuse: the document is registered on the server that was already running"
else
  fail "reuse: the document never reached the running server's /docs.json"
fi

# =============================================================================
# 3. Outputs clause: a served WORKGRAPH.md appears on the project index
# =============================================================================
run_serve "$RENDER" "$WG_DOC" "$REUSE_PORT" "$SHIM_PATH"
assert_rc 0 "work graph"
assert_serving_line "$(doc_url "$REUSE_PORT" "$WG_DOC")" "work graph"
assert_no_browser "work graph"

WG_INDEX="$WORK/index.html"
index_html "$REUSE_PORT" > "$WG_INDEX"
if [ -s "$WG_INDEX" ]; then
  pass "work graph: the project index responds"
else
  fail "work graph: GET / returned nothing — the index effect cannot be checked"
fi
if grep -qF 'WORKGRAPH.md' "$WG_INDEX"; then
  pass "work graph: the served WORKGRAPH.md appears on the index"
else
  fail "work graph: no WORKGRAPH.md on the index after --serve registered it"
fi
if grep -qF 'Focus: N2' "$WG_INDEX"; then
  pass "work graph: the index headline carries the document's Focus id"
else
  fail "work graph: the index headline does not show Focus: N2"
fi
if grep -qF '2 open nodes' "$WG_INDEX"; then
  pass "work graph: the index headline carries the open-node count"
else
  fail "work graph: the index headline does not show the open-node count"
fi

# =============================================================================
# 4. Edge case: a path with spaces and non-ASCII is percent-encoded
# =============================================================================
run_serve "$RENDER" "$SPACED_DOC" "$REUSE_PORT" "$SHIM_PATH"
SPACED_URL="$(serving_url)"
assert_rc 0 "encoded path"
assert_no_browser "encoded path"
if [ "$SPACED_URL" = "$(doc_url "$REUSE_PORT" "$SPACED_DOC")" ]; then
  pass "encoded path: spaces and non-ASCII are percent-encoded exactly as --open encodes them"
else
  fail "encoded path: printed \"$SPACED_URL\", expected \"$(doc_url "$REUSE_PORT" "$SPACED_DOC")\""
fi
case "$SPACED_URL" in
  *%20*) pass "encoded path: the spaces really were encoded (%20 present)" ;;
  *) fail "encoded path: no %20 in \"$SPACED_URL\" — the path was not percent-encoded" ;;
esac
case "$SPACED_URL" in
  *.html) fail "encoded path: the URL names the rendered .html; the contract says the source .md" ;;
  *.md) pass "encoded path: the URL names the source .md, not the rendered .html" ;;
  *) fail "encoded path: \"$SPACED_URL\" ends in neither .md nor .html" ;;
esac
if registered "$REUSE_PORT" "$SPACED_DOC"; then
  pass "encoded path: the document is registered under its real absolute path"
else
  fail "encoded path: $(abs_of "$SPACED_DOC") never reached /docs.json"
fi

# =============================================================================
# 5. Errors: python3 missing
# =============================================================================
if [ "$MIRROR_OK" -ne 1 ]; then
  skip "no python3: this PATH could not be mirrored without python3, so the clause cannot be exercised"
else
  if ! claim_port; then
    fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
  fi
  NOPY_PORT="$PORT"
  run_serve "$RENDER" "$DOC" "$NOPY_PORT" "$MIRROR_PATH"

  assert_rc 3 "no python3"
  assert_not_stub "no python3"
  assert_stderr_matches 'python' "no python3: the stderr note names python3 as the reason"
  assert_no_serving_line "no python3"
  assert_no_browser "no python3"
  assert_render_survived "$DOC" "no python3"
  if curl -sf --max-time 1 "http://127.0.0.1:$NOPY_PORT/health" > /dev/null 2>&1; then
    fail "no python3: something is serving on port $NOPY_PORT — a server was started without python3"
  else
    pass "no python3: no server was started on port $NOPY_PORT"
  fi
fi

# =============================================================================
# 6. Errors: serve.py missing beside render.sh
# =============================================================================
if ! claim_port; then
  fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
fi
NOSERVE_PORT="$PORT"
NOSERVE_DOC="$REPO/no-serve.md"
printf '# No serve\n\nBody.\n' > "$NOSERVE_DOC"
run_serve "$NOSERVE_RENDER" "$NOSERVE_DOC" "$NOSERVE_PORT" "$SHIM_PATH"

assert_rc 3 "no serve.py"
assert_not_stub "no serve.py"
assert_stderr_matches 'serve\.py|server script|no server' "no serve.py: the stderr note names the missing server script"
assert_no_serving_line "no serve.py"
assert_no_browser "no serve.py"
assert_render_survived "$NOSERVE_DOC" "no serve.py"
if curl -sf --max-time 1 "http://127.0.0.1:$NOSERVE_PORT/health" > /dev/null 2>&1; then
  fail "no serve.py: something is serving on port $NOSERVE_PORT — a server was started"
else
  pass "no serve.py: no server was started on port $NOSERVE_PORT"
fi

# =============================================================================
# 7. Errors: a foreign process holds the port
# --serve does NOT degrade to file:// the way --open does; it refuses.
# =============================================================================
if ! claim_port; then
  fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
fi
FOREIGN_PORT="$PORT"
start_fake "$FOREIGN_PORT" --app some-other-app --version "$SERVE_SHA"
FOREIGN_PID="$LAST_FAKE_PID"
if wait_healthy "$FOREIGN_PORT"; then
  pass "foreign: the foreign fixture answers on port $FOREIGN_PORT"
else
  fail "foreign: the foreign fixture never answered on port $FOREIGN_PORT"
fi

run_serve "$RENDER" "$DOC" "$FOREIGN_PORT" "$SHIM_PATH"
assert_rc 3 "foreign"
assert_not_stub "foreign"
assert_stderr_matches "$FOREIGN_PORT" "foreign: the stderr note names the port"
assert_stderr_matches 'held|another|other|foreign|unrelated|different|not (our|ours|render-doc)' \
  "foreign: the stderr note says the port belongs to something else"
assert_no_serving_line "foreign"
assert_no_browser "foreign"
assert_render_survived "$DOC" "foreign"
if alive "$FOREIGN_PID" && [ "$(health_field "$FOREIGN_PORT" app)" = "some-other-app" ]; then
  pass "foreign: the process that owns the port is left alone"
else
  fail "foreign: the foreign process was killed or displaced"
fi
stop_fake "$FOREIGN_PID"

# =============================================================================
# 8. The --open posture, reused: an outdated server is killed and respawned
# =============================================================================
if ! claim_port; then
  fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
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

run_serve "$RENDER" "$DOC" "$DRIFT_PORT" "$SHIM_PATH"
assert_rc 0 "drift"
assert_serving_line "$(doc_url "$DRIFT_PORT" "$DOC")" "drift"
assert_no_browser "drift"
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
if registered "$DRIFT_PORT" "$DOC"; then
  pass "drift: the document is registered against the replacement server"
else
  fail "drift: the document never reached the replacement server's /docs.json"
fi

# =============================================================================
# 9. Errors: an outdated server that will not die
# =============================================================================
if ! claim_port; then
  fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
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

run_serve "$RENDER" "$DOC" "$STUBBORN_PORT" "$SHIM_PATH"
assert_rc 3 "stubborn"
assert_not_stub "stubborn"
assert_stderr_matches "$STUBBORN_PORT" "stubborn: the stderr note names the port that could not be replaced"
assert_stderr_matches 'replace|outdated|stale|could not|cannot|unable|kill' \
  "stubborn: the stderr note says the outdated server could not be replaced"
assert_no_serving_line "stubborn"
assert_no_browser "stubborn"
assert_render_survived "$DOC" "stubborn"
if alive "$STUBBORN_PID"; then
  pass "stubborn: render.sh gave up rather than hanging on a server that will not die"
else
  fail "stubborn: the fixture died although it ignores SIGTERM — the test lost its subject"
fi
stop_fake "$STUBBORN_PID"

# =============================================================================
# 10. Errors: the server cannot be started
# =============================================================================
if ! claim_port; then
  fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
fi
BADSPAWN_PORT="$PORT"
BADSPAWN_DOC="$REPO/bad-spawn.md"
printf '# Bad spawn\n\nBody.\n' > "$BADSPAWN_DOC"
run_serve "$BADSERVE_RENDER" "$BADSPAWN_DOC" "$BADSPAWN_PORT" "$SHIM_PATH"

assert_rc 3 "spawn failure"
assert_not_stub "spawn failure"
assert_stderr_matches 'start|spawn|launch|unreachable|could not|cannot|unable|fail' \
  "spawn failure: the stderr note says the server could not be started"
assert_no_serving_line "spawn failure"
assert_no_browser "spawn failure"
assert_render_survived "$BADSPAWN_DOC" "spawn failure"
if curl -sf --max-time 1 "http://127.0.0.1:$BADSPAWN_PORT/health" > /dev/null 2>&1; then
  fail "spawn failure: something answered on port $BADSPAWN_PORT after a server that cannot start"
else
  pass "spawn failure: nothing is left listening on port $BADSPAWN_PORT"
fi

# =============================================================================
# 11. Errors: the /doc request itself fails — a document outside the scope
# rules. The server is healthy; only the request is refused (403), which is the
# failure this clause is about and the one that distinguishes it from every
# server-availability failure above.
# =============================================================================
if ! claim_port; then
  fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
fi
SCOPE_PORT="$PORT"
start_real_server "$SCOPE_PORT"
if wait_healthy "$SCOPE_PORT"; then
  pass "out of scope: the fixture server is healthy on port $SCOPE_PORT"
else
  fail "out of scope: the fixture server never became healthy on port $SCOPE_PORT"
fi

run_serve "$RENDER" "$OUT_DOC" "$SCOPE_PORT" "$SHIM_PATH"
assert_rc 3 "out of scope"
assert_not_stub "out of scope"
assert_stderr_matches '403|scope|refus|reject|denied|declin|outside|home|worktree|/doc|request|failed' \
  "out of scope: the stderr note names the refused request, not a missing server"
assert_no_serving_line "out of scope"
assert_no_browser "out of scope"
assert_render_survived "$OUT_DOC" "out of scope"
if wait_healthy "$SCOPE_PORT"; then
  pass "out of scope: the healthy server is left running — only the request failed"
else
  fail "out of scope: the server on $SCOPE_PORT is gone; --serve killed a server it should not have"
fi
if registered "$SCOPE_PORT" "$OUT_DOC"; then
  fail "out of scope: a document the server refused was recorded as registered"
else
  pass "out of scope: the refused document is not in /docs.json"
fi

# The other half of the scope clause: under $HOME, but in no git worktree.
if ! no_git_ancestor "$LOOSE_DIR"; then
  skip "not a worktree: an ancestor of \$HOME carries a .git entry, so this scope case cannot be exercised here"
else
  run_serve "$RENDER" "$LOOSE_DOC" "$SCOPE_PORT" "$SHIM_PATH"
  assert_rc 3 "not a worktree"
  assert_not_stub "not a worktree"
  assert_stderr_matches '403|scope|refus|reject|denied|declin|outside|worktree|/doc|request|failed' \
    "not a worktree: the stderr note names the refused request"
  assert_no_serving_line "not a worktree"
  assert_no_browser "not a worktree"
  assert_render_survived "$LOOSE_DOC" "not a worktree"
fi

# =============================================================================
# 12. Every curl carries --max-time: a wedged holder cannot hang --serve
# =============================================================================
if ! claim_port; then
  fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
fi
WEDGE_PORT="$PORT"
WEDGE_DOC="$REPO/wedge.md"
printf '# Wedge\n\nBody.\n' > "$WEDGE_DOC"
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
run_serve_bounded "$RENDER" "$WEDGE_DOC" "$WEDGE_PORT" "$SHIM_PATH" 30
if [ "$RUN_TIMED_OUT" -eq 0 ]; then
  pass "wedged port: --serve returned in ${RUN_ELAPSED}s instead of hanging (every curl carries --max-time)"
else
  fail "wedged port: --serve had not returned after ${RUN_ELAPSED}s — a curl with no --max-time is hanging on the silent process"
fi
assert_rc 3 "wedged port"
assert_not_stub "wedged port"
assert_stderr_matches 'start|spawn|reach|unreachable|could not|cannot|unable|fail|timed out|timeout' \
  "wedged port: the stderr note says the server could not be reached or started"
assert_no_serving_line "wedged port"
assert_no_browser "wedged port"
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
  fail "--max-time: render.sh runs no curl at all, so neither mode can reach the server"
elif [ "$curl_untimed" -eq 0 ]; then
  pass "--max-time: all $curl_total curl invocation(s) in render.sh carry --max-time"
else
  fail "--max-time: $curl_untimed of $curl_total curl invocation(s) carry no --max-time"
fi

# =============================================================================
# 13. Edge case: two --serve runs racing to spawn the server
# One binds, the loser's serve.py exits 0 by design, and BOTH register.
# =============================================================================
if ! claim_port; then
  fail "port $PORT already has a pidfile or registry file; refusing to clobber it"
fi
RACE_PORT="$PORT"
RACE_DOC_1="$REPO/race-1.md"
RACE_DOC_2="$REPO/race-2.md"
printf '# Race one\n' > "$RACE_DOC_1"
printf '# Race two\n' > "$RACE_DOC_2"
: > "$WORK/race-1.log"
: > "$WORK/race-2.log"
RD_OPEN_LOG="$WORK/race-1.log" PATH="$SHIM_PATH" RENDER_DOC_PORT="$RACE_PORT" \
  "$RENDER" "$RACE_DOC_1" --serve > "$WORK/race-1.out" 2> "$WORK/race-1.err" &
RACE_BG_1=$!
RD_OPEN_LOG="$WORK/race-2.log" PATH="$SHIM_PATH" RENDER_DOC_PORT="$RACE_PORT" \
  "$RENDER" "$RACE_DOC_2" --serve > "$WORK/race-2.out" 2> "$WORK/race-2.err" &
RACE_BG_2=$!
wait "$RACE_BG_1"
RACE_RC_1=$?
wait "$RACE_BG_2"
RACE_RC_2=$?
cat "$WORK/race-1.err" "$WORK/race-2.err" >> "$ALL_ERR"
cat "$WORK/race-1.log" "$WORK/race-2.log" >> "$ALL_OPEN"

if [ "$RACE_RC_1" -eq 0 ] && [ "$RACE_RC_2" -eq 0 ]; then
  pass "race: both concurrent --serve runs exit 0"
else
  fail "race: concurrent --serve runs exited $RACE_RC_1 and $RACE_RC_2, expected 0 and 0"
fi
RACE_URL_1="$(grep '^serving: ' "$WORK/race-1.out" | head -1 | sed 's/^serving: //')"
RACE_URL_2="$(grep '^serving: ' "$WORK/race-2.out" | head -1 | sed 's/^serving: //')"
if [ "$RACE_URL_1" = "$(doc_url "$RACE_PORT" "$RACE_DOC_1")" ] \
  && [ "$RACE_URL_2" = "$(doc_url "$RACE_PORT" "$RACE_DOC_2")" ]; then
  pass "race: both runs print their own /doc URL on the winner's port"
else
  fail "race: printed \"$RACE_URL_1\" and \"$RACE_URL_2\", expected each document's own /doc URL"
fi
if [ "$(health_field "$RACE_PORT" version)" = "$SERVE_SHA" ]; then
  pass "race: one current server is left serving on port $RACE_PORT"
else
  fail "race: no current render-doc server on port $RACE_PORT after the race"
fi
if registered "$RACE_PORT" "$RACE_DOC_1" && registered "$RACE_PORT" "$RACE_DOC_2"; then
  pass "race: both documents are registered against the winner"
else
  fail "race: only some of the raced documents reached /docs.json"
fi
if [ ! -s "$WORK/race-1.log" ] && [ ! -s "$WORK/race-2.log" ]; then
  pass "race: neither concurrent run opened a browser"
else
  fail "race: a concurrent --serve run opened a browser"
fi

# =============================================================================
# 14. Invariants
# =============================================================================

# Mutual exclusion with --open, enforced at argument parsing: a usage error,
# exit 1, no URL and no browser. One run cannot promise both postures.
: > "$OPEN_LOG"
PATH="$SHIM_PATH" RENDER_DOC_PORT="$SPAWN_PORT" "$RENDER" "$DOC" --open --serve \
  > "$RUN_OUT" 2> "$RUN_ERR"
RUN_RC=$?
cat "$RUN_ERR" >> "$ALL_ERR"
cat "$OPEN_LOG" >> "$ALL_OPEN"
if [ "$RUN_RC" = "1" ]; then
  pass "mutual exclusion: --open --serve exits 1"
else
  fail "mutual exclusion: --open --serve exited $RUN_RC, expected the usage error's 1"
fi
if grep -qi 'usage' "$RUN_ERR"; then
  pass "mutual exclusion: the usage line is printed to stderr"
else
  fail "mutual exclusion: no usage line on stderr (\"$(head -1 "$RUN_ERR")\")"
fi
assert_no_serving_line "mutual exclusion"
assert_no_browser "mutual exclusion"

# A render failure exits 1 long before this block: --serve never converts a
# broken render into its own exit 3.
: > "$OPEN_LOG"
PATH="$SHIM_PATH" RENDER_DOC_PORT="$SPAWN_PORT" "$RENDER" "$REPO/does-not-exist.md" --serve \
  > "$RUN_OUT" 2> "$RUN_ERR"
RUN_RC=$?
cat "$RUN_ERR" >> "$ALL_ERR"
cat "$OPEN_LOG" >> "$ALL_OPEN"
if [ "$RUN_RC" = "1" ]; then
  pass "render failure: a missing input exits 1, not the --serve block's 3"
else
  fail "render failure: a missing input exited $RUN_RC, expected 1"
fi
if grep -qi 'not found\|input' "$RUN_ERR"; then
  pass "render failure: stderr names the missing input"
else
  fail "render failure: stderr does not name the missing input (\"$(head -1 "$RUN_ERR")\")"
fi
assert_no_serving_line "render failure"
assert_no_browser "render failure"

# Loopback only, on the configured port: no other host may appear in the code.
http_hosts="$(grep -o 'http://[^"'"'"' )]*' "$CODE" 2> /dev/null | sed 's|^http://||; s|/.*$||; s|:.*$||' | sort -u)"
if [ -z "$http_hosts" ]; then
  fail "invariant: render.sh contacts no http:// URL at all, so --serve cannot reach the server"
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

# Writes no state file.
if [ "$STATE_FILE_PRESENT" -eq 1 ]; then
  skip "invariant: $STATE_FILE already existed before this run; cannot attribute it"
elif [ -e "$STATE_FILE" ]; then
  fail "invariant: this run created a state file at $STATE_FILE"
else
  pass "invariant: no state file was written"
fi

# The aggregate of clause 5: across every --serve run in this file — success,
# refusal, missing python3, unreachable server, race — not one browser opened.
if [ ! -s "$ALL_OPEN" ]; then
  pass "invariant: no --serve run in this suite opened a browser, on any path"
else
  fail "invariant: $(wc -l < "$ALL_OPEN" | tr -d ' ') browser open(s) fired across the suite; --serve must open nothing"
fi

# Every note above should be render-doc's own sentence; a shell or curl
# diagnostic reaching the user's terminal is a different failure.
if grep -qE 'command not found|Traceback \(most recent call last\)|syntax error|^curl:' "$ALL_ERR" 2> /dev/null; then
  fail "outputs: a tool diagnostic leaked to stderr: \"$(grep -Em1 'command not found|Traceback \(most recent call last\)|syntax error|^curl:' "$ALL_ERR")\""
else
  pass "outputs: every stderr line came from render.sh itself"
fi

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'serve-mode.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'serve-mode.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'serve-mode.test.sh: all assertions passed\n'
