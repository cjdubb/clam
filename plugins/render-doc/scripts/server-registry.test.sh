#!/usr/bin/env bash
# server-registry.test.sh — verifies the module-level docblock "Contract: B02
# served-doc registry" in plugins/render-doc/scripts/serve.py (registry_record,
# registry_entries) together with its /docs.json handler, clause by clause.
#
# The registry is what lets the index page list documents nobody asked it about:
# every successful serve is remembered, the memory survives a restart through a
# /tmp file, and paths that have since left scope are pruned rather than served
# up stale. Only two of those are observable from outside the process —
# /docs.json and the /tmp file — so every assertion here goes through one of
# them.
#
# Six servers are started, each on its own kernel-assigned high port (never the
# default 27183, where a real server may be running), because most clauses are
# about what a server does with the registry file it finds AT STARTUP: a valid
# seed, a corrupt one, a wrong-shaped one, an unwritable path, and a second port
# that must not see the first port's entries. All are killed by the EXIT trap,
# which also removes every /tmp/render-doc-registry-<port>.json and pidfile this
# run created — the registry file is the one new /tmp artefact of this contract,
# and leaving it behind would seed the next run.
#
# Fixtures live under $HOME inside throwaway git repos because the scope rules
# demand both, and the pruning clauses need paths that pass and fail those rules.
#
# Out of scope here: /raw's own response shape (server-raw.test.sh), /doc's
# rendering (server.test.sh), and the index page that consumes this registry
# (server-index.test.sh).

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
  # rm -rf, not rm -f: one registry path is deliberately a directory below.
  for f in ${TMP_ARTEFACTS[@]+"${TMP_ARTEFACTS[@]}"}; do
    [ -n "$f" ] && rm -rf "$f"
  done
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
  printf 'server-registry.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
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

REG_FILE_OF() { printf '/tmp/render-doc-registry-%s.json' "$1"; }

LAST_PID=""
start_server() { # <port> <stderr file>
  RENDER_DOC_PORT="$1" python3 "$SERVE" > "$2.stdout" 2> "$2" &
  LAST_PID=$!
  SERVER_PIDS+=("$LAST_PID")
  TMP_ARTEFACTS+=("/tmp/render-doc-serve-$1.pid" "$(REG_FILE_OF "$1")")
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

RESP_CODE=""
do_request() { # <curl args...>
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

enc() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$1"
}

realpath_of() {
  python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$1" 2> /dev/null
}

# GET /docs.json from <base> into $BODY, then answer questions about it. The
# helpers below all read that saved body, so one fetch serves several clauses.
fetch_docs() { # <base>
  do_request "$1/docs.json"
}

# The paths in the last /docs.json body, in the order they appear.
docs_paths() {
  python3 - "$BODY" << 'PY' 2> /dev/null
import json, sys
with open(sys.argv[1]) as f:
    obj = json.load(f)
for e in obj['docs']:
    print(e['path'])
PY
}

docs_time() { # <realpath>
  python3 - "$BODY" "$1" << 'PY' 2> /dev/null
import json, sys
with open(sys.argv[1]) as f:
    obj = json.load(f)
for e in obj['docs']:
    if e['path'] == sys.argv[2]:
        print(e['lastServed'])
        break
PY
}

docs_has() { # <realpath>
  docs_paths | grep -qxF -- "$1"
}

# True when the last fetch_docs returned a parseable 200. A "this path is NOT
# listed" assertion says nothing when /docs.json answered nothing at all, so
# those are gated on this and reported as unverified rather than passing
# vacuously.
docs_ok() {
  [ "$RESP_CODE" = "200" ] || return 1
  python3 -c "import json, sys
obj = json.load(open(sys.argv[1]))
sys.exit(0 if isinstance(obj.get('docs'), list) else 1)" "$BODY" 2> /dev/null
}

docs_count() { # <realpath> — how many entries carry this path
  docs_paths | grep -cxF -- "$1"
}

# The registry file's own contents: a JSON object mapping realpath -> number.
reg_file_paths() { # <registry file>
  python3 - "$1" << 'PY' 2> /dev/null
import json, sys
with open(sys.argv[1]) as f:
    obj = json.load(f)
if not isinstance(obj, dict):
    sys.exit(1)
for k, v in obj.items():
    if not isinstance(v, (int, float)) or isinstance(v, bool):
        sys.exit(1)
    print(k)
PY
}

reg_file_has() { # <registry file> <realpath>
  reg_file_paths "$1" | grep -qxF -- "$2"
}

# Write a registry seed file before a server starts. Arguments are
# <path> <epoch> pairs.
write_seed() { # <file> [<path> <epoch>]...
  local f="$1"
  shift
  python3 - "$f" "$@" << 'PY'
import json, sys
out = {}
args = sys.argv[2:]
for i in range(0, len(args), 2):
    out[args[i]] = float(args[i + 1])
with open(sys.argv[1], 'w') as fh:
    json.dump(out, fh)
PY
}

num_gt() { # <a> <b>
  python3 -c "import sys
try:
    sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)
except ValueError:
    sys.exit(1)" "$1" "$2" 2> /dev/null
}

NOW() { date +%s; }

# --- Fixtures ----------------------------------------------------------------
REG_WORK="$(mktemp -d "$HOME/.render-doc-regtest.XXXXXX")"
OUT_WORK="$(mktemp -d)"
HOME_DIRS+=("$REG_WORK")
TMP_DIRS+=("$OUT_WORK")
git init -q "$REG_WORK" 2> /dev/null

for name in alpha beta gamma delta; do
  printf '# %s\n\nbody of %s\n' "$name" "$name" > "$REG_WORK/$name.md"
done
printf 'not markdown\n' > "$REG_WORK/notes.txt"
printf '# Outside the home directory\n' > "$OUT_WORK/outside-home.md"

# An in-scope symlink to an in-scope document: the registry records the realpath
# the scope check ran on, never the alias the client asked for.
ln -s "$REG_WORK/delta.md" "$REG_WORK/alias.md"

ALPHA="$(realpath_of "$REG_WORK/alpha.md")"
BETA="$(realpath_of "$REG_WORK/beta.md")"
GAMMA="$(realpath_of "$REG_WORK/gamma.md")"
DELTA="$(realpath_of "$REG_WORK/delta.md")"
ALIAS="$REG_WORK/alias.md"
NOTES="$(realpath_of "$REG_WORK/notes.txt")"

PORT_A="$(free_port)"
BASE_A="http://127.0.0.1:$PORT_A"
REG_A="$(REG_FILE_OF "$PORT_A")"

if [ -e "$REG_A" ]; then
  fail "test port $PORT_A already has a registry file at $REG_A; aborting to avoid clobbering it"
  printf 'server-registry.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

start_server "$PORT_A" "$WORK/srv-a.stderr"
if wait_healthy "$BASE_A"; then
  pass "server: healthy on test port $PORT_A"
else
  fail "server: did not become healthy on test port $PORT_A — no registry clause can be checked"
  printf 'server-registry.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

# =============================================================================
# Clause 5 + Errors: GET /docs.json is 200 application/json, body exactly
# {"docs": [...]}, and an empty registry is {"docs": []} rather than a 500.
# =============================================================================

fetch_docs "$BASE_A"
if [ "$RESP_CODE" = "200" ]; then
  pass "/docs.json: 200 before anything has been served"
else
  fail "/docs.json: expected 200 on a fresh server, got $RESP_CODE"
fi

if grep -qi '^content-type:[[:space:]]*application/json' "$HEADERS" 2> /dev/null; then
  pass "/docs.json: served as application/json"
else
  fail "/docs.json: Content-Type is not application/json"
fi

if python3 - "$BODY" << 'PY' 2> /dev/null
import json, sys
with open(sys.argv[1]) as f:
    obj = json.load(f)
assert isinstance(obj, dict), obj
assert list(obj.keys()) == ['docs'], obj
assert obj['docs'] == [], obj
PY
then
  pass "/docs.json: an empty registry is exactly {\"docs\": []}"
else
  fail "/docs.json: expected exactly {\"docs\": []} on a fresh server, got: $(cat "$BODY" 2> /dev/null)"
fi

# =============================================================================
# Clause 1: every successful serve is recorded — /doc's 200 and /raw's 200 alike
# =============================================================================

t0="$(NOW)"
expect_code "/doc: alpha.md serves" 200 "$BASE_A/doc$(enc "$REG_WORK/alpha.md")"
fetch_docs "$BASE_A"
if docs_has "$ALPHA"; then
  pass "registry: a successful /doc serve is recorded"
else
  fail "registry: alpha.md is absent from /docs.json after a successful /doc serve"
fi
alpha_t="$(docs_time "$ALPHA")"
if [ -n "$alpha_t" ] && ! num_gt "$((t0 - 5))" "$alpha_t" && ! num_gt "$alpha_t" "$(($(NOW) + 5))"; then
  pass "registry: last-served is the current epoch time ($alpha_t)"
else
  fail "registry: last-served \"$alpha_t\" is not near the current epoch time ($t0)"
fi

expect_code "/raw: beta.md serves" 200 "$BASE_A/raw$(enc "$REG_WORK/beta.md")"
fetch_docs "$BASE_A"
if docs_has "$BETA"; then
  pass "registry: a successful /raw serve is recorded"
else
  fail "registry: beta.md is absent from /docs.json after a successful /raw serve"
fi

# Entry shape: exactly {"path", "lastServed"}, with a numeric time.
if python3 - "$BODY" << 'PY' 2> /dev/null
import json, sys
with open(sys.argv[1]) as f:
    obj = json.load(f)
assert obj['docs'], 'no entries to check the shape of'
for e in obj['docs']:
    assert isinstance(e, dict), e
    assert sorted(e.keys()) == ['lastServed', 'path'], e
    assert isinstance(e['path'], str) and e['path'].startswith('/'), e
    assert isinstance(e['lastServed'], (int, float)) and not isinstance(e['lastServed'], bool), e
PY
then
  pass "/docs.json: every entry is {\"path\": <realpath>, \"lastServed\": <number>}"
else
  fail "/docs.json: entry shape is wrong: $(cat "$BODY" 2> /dev/null)"
fi

# Invariant: entries are realpaths — the same md_real the scope check ran on.
expect_code "/doc: an in-scope symlink serves" 200 "$BASE_A/doc$(enc "$ALIAS")"
fetch_docs "$BASE_A"
if docs_has "$DELTA" && ! docs_has "$ALIAS"; then
  pass "registry: a serve through a symlink is recorded under the target's realpath"
else
  fail "registry: expected $DELTA and not $ALIAS in /docs.json"
fi

# Clause 1 upsert: one entry per path, newest time wins.
sleep 1 # last-served is epoch seconds; the advance must be observable
expect_code "/doc: alpha.md serves again" 200 "$BASE_A/doc$(enc "$REG_WORK/alpha.md")"
fetch_docs "$BASE_A"
alpha_t2="$(docs_time "$ALPHA")"
if [ "$(docs_count "$ALPHA")" = "1" ]; then
  pass "registry: re-serving a document leaves exactly one entry for it"
else
  fail "registry: alpha.md has $(docs_count "$ALPHA") entries after two serves, expected 1"
fi
if [ -n "$alpha_t2" ] && num_gt "$alpha_t2" "$alpha_t"; then
  pass "registry: re-serving updates last-served to the newer time ($alpha_t -> $alpha_t2)"
else
  fail "registry: last-served did not advance on re-serve (was $alpha_t, now $alpha_t2)"
fi

# Clause 4: sorted by lastServed, descending. alpha was served last.
first_path="$(docs_paths | head -1)"
if [ "$first_path" = "$ALPHA" ]; then
  pass "/docs.json: entries are sorted by last-served, most recent first"
else
  fail "/docs.json: first entry is \"$first_path\", expected the most recently served $ALPHA"
fi

# Errors clause: an unsuccessful serve is not a serve.
do_request "$BASE_A/doc$(enc "$REG_WORK/notes.txt")"
do_request "$BASE_A/raw$(enc "$REG_WORK/absent.md")"
fetch_docs "$BASE_A"
if ! docs_ok; then
  fail "registry: whether scope-rejected requests are recorded could not be checked (/docs.json did not answer)"
elif ! docs_has "$NOTES" && ! docs_has "$(realpath_of "$REG_WORK")/absent.md"; then
  pass "registry: scope-rejected requests (403 and 404) are not recorded"
else
  fail "registry: a scope-rejected request was recorded"
fi

# =============================================================================
# Clause 2: best-effort persistence to /tmp/render-doc-registry-<port>.json
# =============================================================================

if [ -f "$REG_A" ]; then
  pass "persistence: the registry file $REG_A exists after a serve"
else
  fail "persistence: no registry file at $REG_A after several serves"
fi
if reg_file_has "$REG_A" "$ALPHA" && reg_file_has "$REG_A" "$BETA"; then
  pass "persistence: the file is a JSON object mapping realpath -> a numeric time"
else
  fail "persistence: $REG_A does not map the served realpaths to numbers: $(cat "$REG_A" 2> /dev/null)"
fi

# Edge case: the file is deleted while the server runs — recreated on the next
# change, with the in-memory registry intact.
rm -f "$REG_A"
expect_code "/doc: gamma.md serves after the registry file was deleted" 200 \
  "$BASE_A/doc$(enc "$REG_WORK/gamma.md")"
if [ -f "$REG_A" ] && reg_file_has "$REG_A" "$GAMMA" && reg_file_has "$REG_A" "$ALPHA"; then
  pass "persistence: a deleted registry file is recreated on the next change, without losing entries"
else
  fail "persistence: after deleting $REG_A and serving again, the file is missing or incomplete: $(cat "$REG_A" 2> /dev/null)"
fi

# =============================================================================
# Invariant: a lock serializes every read-modify-write. Concurrent serves of
# distinct documents must not lose each other; concurrent serves of one
# document must still leave one entry.
# =============================================================================

RACE_DIR="$REG_WORK/race"
mkdir -p "$RACE_DIR"
race_pids=()
for i in 1 2 3 4 5 6 7 8; do
  printf '# Race %s\n' "$i" > "$RACE_DIR/race-$i.md"
done
for i in 1 2 3 4 5 6 7 8; do
  curl -s --max-time 15 -o /dev/null "$BASE_A/raw$(enc "$RACE_DIR/race-$i.md")" &
  race_pids+=("$!")
done
for p in ${race_pids[@]+"${race_pids[@]}"}; do
  wait "$p" 2> /dev/null
done
fetch_docs "$BASE_A"
recorded=0
for i in 1 2 3 4 5 6 7 8; do
  docs_has "$(realpath_of "$RACE_DIR/race-$i.md")" && recorded=$((recorded + 1))
done
if [ "$recorded" -eq 8 ]; then
  pass "lock: 8 concurrent serves of distinct documents are all recorded"
else
  fail "lock: only $recorded of 8 concurrently served documents were recorded"
fi

race_pids=()
for i in 1 2 3 4 5 6 7 8; do
  curl -s --max-time 15 -o /dev/null "$BASE_A/raw$(enc "$RACE_DIR/race-1.md")" &
  race_pids+=("$!")
done
for p in ${race_pids[@]+"${race_pids[@]}"}; do
  wait "$p" 2> /dev/null
done
fetch_docs "$BASE_A"
if [ "$(docs_count "$(realpath_of "$RACE_DIR/race-1.md")")" = "1" ]; then
  pass "lock: 8 concurrent serves of ONE document leave exactly one entry"
else
  fail "lock: one document has $(docs_count "$(realpath_of "$RACE_DIR/race-1.md")") entries after 8 concurrent serves"
fi

# =============================================================================
# Inputs: /docs.json is a route like any other — Host pinned, query stripped
# =============================================================================

expect_code "host: wrong Host on /docs.json rejected" 403 \
  -H 'Host: evil.example' "$BASE_A/docs.json"
expect_code "/docs.json: query string stripped before routing" 200 "$BASE_A/docs.json?ts=1"

# =============================================================================
# Clause 3 + 4: a seed file is read at startup, and entries that have since
# left scope are pruned from the response AND from the persisted file.
# =============================================================================

PORT_B="$(free_port)"
BASE_B="http://127.0.0.1:$PORT_B"
REG_B="$(REG_FILE_OF "$PORT_B")"
VANISHED="$REG_WORK/vanished.md"
printf '# Vanished\n' > "$VANISHED"
VANISHED_REAL="$(realpath_of "$VANISHED")"
rm -f "$VANISHED" # seeded, then gone: the classic stale entry

write_seed "$REG_B" \
  "$ALPHA" 1000 \
  "$BETA" 3000 \
  "$VANISHED_REAL" 2000 \
  "$NOTES" 2500 \
  "$(realpath_of "$OUT_WORK/outside-home.md")" 2600
start_server "$PORT_B" "$WORK/srv-b.stderr"
if wait_healthy "$BASE_B"; then
  pass "seeding: a server with a seed file starts and is healthy"
else
  fail "seeding: the seeded server did not become healthy on port $PORT_B"
fi

fetch_docs "$BASE_B"
if [ "$RESP_CODE" = "200" ] && docs_has "$ALPHA" && docs_has "$BETA"; then
  pass "seeding: entries from the /tmp file are in the registry before anything is served"
else
  fail "seeding: seeded entries missing from /docs.json (code $RESP_CODE): $(cat "$BODY" 2> /dev/null)"
fi
if [ "$(docs_time "$ALPHA")" = "1000" ] || [ "$(docs_time "$ALPHA")" = "1000.0" ]; then
  pass "seeding: the seeded last-served time is preserved"
else
  fail "seeding: seeded time for alpha is \"$(docs_time "$ALPHA")\", expected 1000"
fi
if [ "$(docs_paths | head -1)" = "$BETA" ]; then
  pass "seeding: seeded entries are returned in last-served-descending order"
else
  fail "seeding: first seeded entry is \"$(docs_paths | head -1)\", expected the newest ($BETA)"
fi

if ! docs_ok; then
  fail "pruning: the vanished-file prune could not be checked (/docs.json did not answer)"
  fail "pruning: the out-of-scope prune could not be checked (/docs.json did not answer)"
else
  if ! docs_has "$VANISHED_REAL"; then
    pass "pruning: a seeded entry whose file has vanished is pruned from the response"
  else
    fail "pruning: the vanished document is still listed in /docs.json"
  fi
  if ! docs_has "$NOTES" && ! docs_has "$(realpath_of "$OUT_WORK/outside-home.md")"; then
    pass "pruning: seeded entries that now fail the scope rules are pruned"
  else
    fail "pruning: an out-of-scope seeded entry is still listed in /docs.json"
  fi
fi

# "PRUNING — from both the returned list and the registry itself, persisting
# the prune": the /tmp file must have lost them too.
if [ -f "$REG_B" ] && ! reg_file_has "$REG_B" "$VANISHED_REAL" \
  && ! reg_file_has "$REG_B" "$NOTES" && reg_file_has "$REG_B" "$ALPHA"; then
  pass "pruning: the prune is persisted — the /tmp file keeps the valid entries only"
else
  fail "pruning: $REG_B still carries pruned entries or lost a valid one: $(cat "$REG_B" 2> /dev/null)"
fi

# =============================================================================
# Clause 3: a corrupt or wrong-shaped seed file is silently treated as empty
# =============================================================================

PORT_C="$(free_port)"
BASE_C="http://127.0.0.1:$PORT_C"
printf 'this is not json at all {{{\n' > "$(REG_FILE_OF "$PORT_C")"
start_server "$PORT_C" "$WORK/srv-c.stderr"
if wait_healthy "$BASE_C"; then
  pass "corrupt seed: the server starts normally with an unparseable registry file"
else
  fail "corrupt seed: the server did not become healthy with an unparseable registry file"
fi
fetch_docs "$BASE_C"
if [ "$RESP_CODE" = "200" ] && [ "$(docs_paths | wc -l | tr -d ' ')" = "0" ]; then
  pass "corrupt seed: treated as empty — /docs.json is 200 {\"docs\": []}"
else
  fail "corrupt seed: expected 200 with no entries, got $RESP_CODE: $(cat "$BODY" 2> /dev/null)"
fi

PORT_D="$(free_port)"
BASE_D="http://127.0.0.1:$PORT_D"
printf '["%s", "%s"]\n' "$ALPHA" "$BETA" > "$(REG_FILE_OF "$PORT_D")"
start_server "$PORT_D" "$WORK/srv-d.stderr"
if wait_healthy "$BASE_D"; then
  pass "wrong-shape seed: the server starts normally with a JSON array instead of an object"
else
  fail "wrong-shape seed: the server did not become healthy with a wrong-shaped registry file"
fi
fetch_docs "$BASE_D"
if [ "$RESP_CODE" = "200" ] && [ "$(docs_paths | wc -l | tr -d ' ')" = "0" ]; then
  pass "wrong-shape seed: treated as empty — /docs.json is 200 {\"docs\": []}"
else
  fail "wrong-shape seed: expected 200 with no entries, got $RESP_CODE: $(cat "$BODY" 2> /dev/null)"
fi
expect_code "wrong-shape seed: the server still serves documents" 200 \
  "$BASE_D/doc$(enc "$REG_WORK/alpha.md")"

# =============================================================================
# Clause 2 + invariant: a failed write is silent and never breaks a serve
# =============================================================================

if [ "$(id -u)" -eq 0 ]; then
  skip "unwritable registry: running as root, so a directory in the file's place could still be replaced"
else
  PORT_E="$(free_port)"
  BASE_E="http://127.0.0.1:$PORT_E"
  REG_E="$(REG_FILE_OF "$PORT_E")"
  mkdir -p "$REG_E" # a directory where the file must go: every write will fail
  start_server "$PORT_E" "$WORK/srv-e.stderr"
  if wait_healthy "$BASE_E"; then
    pass "unwritable registry: the server starts with an unwritable registry path"
  else
    fail "unwritable registry: the server did not become healthy when its registry path was unwritable"
  fi
  expect_code "unwritable registry: /doc still serves" 200 "$BASE_E/doc$(enc "$REG_WORK/alpha.md")"
  expect_code "unwritable registry: /raw still serves" 200 "$BASE_E/raw$(enc "$REG_WORK/beta.md")"
  fetch_docs "$BASE_E"
  if [ "$RESP_CODE" = "200" ] && docs_has "$ALPHA" && docs_has "$BETA"; then
    pass "unwritable registry: the in-memory registry keeps working when persistence fails"
  else
    fail "unwritable registry: /docs.json lost the served documents (code $RESP_CODE): $(cat "$BODY" 2> /dev/null)"
  fi
  if [ -d "$REG_E" ]; then
    pass "unwritable registry: the failed write is silent — nothing was forced over the directory"
  else
    fail "unwritable registry: the server replaced the directory at $REG_E"
  fi
fi

# =============================================================================
# Edge case: two servers on different ports keep separate, port-keyed files
# =============================================================================

expect_code "/doc: alpha.md serves on port A" 200 "$BASE_A/doc$(enc "$REG_WORK/alpha.md")"
expect_code "/doc: gamma.md serves on port C" 200 "$BASE_C/doc$(enc "$REG_WORK/gamma.md")"
REG_C="$(REG_FILE_OF "$PORT_C")"
# Port A legitimately holds gamma (it was served there earlier in this run), so
# the claim under test is the other direction: port C's file holds only what
# port C itself served.
if reg_file_has "$REG_C" "$GAMMA" && ! reg_file_has "$REG_C" "$BETA"; then
  pass "two servers: each port's registry file holds only that port's serves"
else
  fail "two servers: $REG_C does not hold gamma alone: $(cat "$REG_C" 2> /dev/null)"
fi
fetch_docs "$BASE_C"
if docs_has "$GAMMA" && ! docs_has "$BETA"; then
  pass "two servers: /docs.json on one port does not show the other port's serves"
else
  fail "two servers: port C's /docs.json shows port B's or A's entries: $(cat "$BODY" 2> /dev/null)"
fi

# =============================================================================
# Invariants: a registry failure never turns a successful serve into an error,
# and no registry path leaks a traceback
# =============================================================================

expect_code "server: still healthy after every registry path" 200 "$BASE_A/health"
for f in "$WORK/srv-a.stderr" "$WORK/srv-b.stderr" "$WORK/srv-c.stderr" "$WORK/srv-d.stderr"; do
  if grep -q 'Traceback (most recent call last)' "$f" 2> /dev/null; then
    fail "outputs: $(basename "$f") carries a traceback — a registry path raised"
  else
    pass "outputs: $(basename "$f") is free of tracebacks"
  fi
done

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'server-registry.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'server-registry.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'server-registry.test.sh: all assertions passed\n'
