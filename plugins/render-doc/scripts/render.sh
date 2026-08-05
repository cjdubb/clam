#!/usr/bin/env bash
# render.sh — turn a markdown document into a self-contained HTML view.
#
# Usage: render.sh <doc.md> [--open]
#
# Splices the vendored markdown parser and the base64-encoded document into
# assets/template.html and writes a sibling .html file next to the input
# (.local/PLAN.md -> .local/PLAN.html). Base64 embedding means the document
# can never contain a sequence (like a closing script tag) that breaks the
# page. No network access, no server: everything ships inside the one file.
#
# Exit codes: 0 on success; 1 on any failure, with a message on stderr, so
# consuming skills can fall back to the plain-markdown flow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../assets/template.html"
PARSER="$SCRIPT_DIR/../assets/marked.min.js"
CYTOSCAPE="$SCRIPT_DIR/../assets/cytoscape.min.js"
CYTOSCAPE_DAGRE="$SCRIPT_DIR/../assets/cytoscape-dagre.min.js"

# Contract: 229-B01 vendored-graph-libs-and-splice (plan 001-render-doc-graph-view)
# Behavior:
#   This script splices TWO additional vendored libraries into the template,
#   exactly as the marked parser is spliced: each marker line in
#   assets/template.html is replaced by the named asset's contents verbatim,
#   via its own ENVIRON-backed block in the single existing awk program.
#     __CYTOSCAPE_SPLICE__       <- assets/cytoscape.min.js
#     __CYTOSCAPE_DAGRE_SPLICE__ <- assets/cytoscape-dagre.min.js
#   In the template the cytoscape script element precedes the
#   cytoscape-dagre element (the extension registers against the global
#   cytoscape object), and both precede the app script.
# Inputs:
#   assets/cytoscape.min.js — cytoscape@3.34.0, file dist/cytoscape.min.js
#     from the npm tarball, byte-identical below a marked.min.js-style
#     provenance header; sha256(original) =
#     9c2a3bf2592e0b14a1f7bec07c03a54f16dedf32af9cd0af155c716aa6c87bc3
#     (original: 31 lines, 435,328 bytes; MIT).
#   assets/cytoscape-dagre.min.js — cytoscape-dagre@4.0.0, file
#     dist/cytoscape-dagre.min.js (bundles dagre internally; peer
#     cytoscape ^3.2.22), same header convention; sha256(original) =
#     b9e9d704119970f4255c035baa98d778e94af4b2efd2bdba20a601a869417223
#     (original: 7 lines, 45,620 bytes; MIT).
# Outputs:
#   The rendered HTML carries both libraries inline in their own script
#   elements; the output's closing-script-tag count equals the template's.
# Errors:
#   A missing or empty asset file dies before any output is written, with a
#   message naming the path — a [ -s ] precondition beside the PARSER check.
#   A leftover marker after the splice dies via the self-check, whose grep
#   is extended with BOTH new marker names.
# Invariants:
#   The vendored files are byte-identical to the pinned npm dist artifacts
#   below their provenance headers (header format identical to
#   marked.min.js's, including the "To upgrade:" line). Neither file
#   contains a closing script tag, an HTML comment opener, or any
#   external-resource form (href/src to http(s), url(http...), @import,
#   fonts.googleapis) — this is what keeps inline splicing and the
#   script-count proof sound.
# Edge cases:
#   The provenance header records the sha256 of the ORIGINAL dist file, not
#   of the shipped file (which prepends the header); a hash mismatch after
#   any edit below the header is a defect, never something to re-pin.

die() {
  printf 'render-doc: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: render.sh <doc.md> [--open|--serve]\n' >&2
  exit 1
}

# --- Argument parsing -------------------------------------------------------
DOC=""
OPEN=0
SERVE_MODE=0
for arg in "$@"; do
  case "$arg" in
    --open) OPEN=1 ;;
    --serve) SERVE_MODE=1 ;;
    --*) die "unknown flag: $arg (only --open and --serve are supported)" ;;
    *)
      [ -n "$DOC" ] && usage
      DOC="$arg"
      ;;
  esac
done
[ -n "$DOC" ] || usage
# --open and --serve are mutually exclusive (B08): --open may degrade to a
# file:// open while --serve exists to guarantee registration; one run
# cannot promise both. (SERVE_MODE, not SERVE: the --open block below owns
# SERVE as the serve.py path.)
[ "$OPEN" -eq 1 ] && [ "$SERVE_MODE" -eq 1 ] && usage

# Resolve to absolute path for the source-path splice.
DOC_ABS="$(cd "$(dirname "$DOC")" && pwd)/$(basename "$DOC")"

# --- Preconditions -----------------------------------------------------------
[ -f "$DOC" ] || die "input not found: $DOC"
[ -r "$DOC" ] || die "input not readable: $DOC"
[ -s "$TEMPLATE" ] || die "template missing or empty: $TEMPLATE"
[ -s "$PARSER" ] || die "vendored parser missing or empty: $PARSER"
[ -s "$CYTOSCAPE" ] || die "vendored cytoscape library missing or empty: $CYTOSCAPE"
[ -s "$CYTOSCAPE_DAGRE" ] || die "vendored cytoscape-dagre library missing or empty: $CYTOSCAPE_DAGRE"

OUT="${DOC%.md}.html"
[ "$OUT" != "$DOC" ] || OUT="$DOC.html"

# --- Splice ------------------------------------------------------------------
B64_TMP="$(mktemp)" || die "mktemp failed"
OUT_TMP="$(mktemp)" || { rm -f "$B64_TMP"; die "mktemp failed"; }
cleanup() { rm -f "$B64_TMP" "$OUT_TMP"; }
trap cleanup EXIT

base64 < "$DOC" > "$B64_TMP" || die "base64 encoding failed for: $DOC"

# Slot markers each live on their own line in the template; awk replaces the
# marker line with the file contents verbatim. Paths travel via ENVIRON so no
# shell or awk escaping can mangle them.
RENDER_PARSER_FILE="$PARSER" RENDER_B64_FILE="$B64_TMP" RENDER_SOURCE_PATH="$DOC_ABS" \
RENDER_CYTOSCAPE_FILE="$CYTOSCAPE" RENDER_CYTOSCAPE_DAGRE_FILE="$CYTOSCAPE_DAGRE" awk '
  /__MARKED_SPLICE__/ {
    f = ENVIRON["RENDER_PARSER_FILE"]
    while ((getline line < f) > 0) print line
    close(f)
    next
  }
  /__DOC_B64_SPLICE__/ {
    f = ENVIRON["RENDER_B64_FILE"]
    while ((getline line < f) > 0) print line
    close(f)
    next
  }
  /__SOURCE_PATH_SPLICE__/ {
    print ENVIRON["RENDER_SOURCE_PATH"]
    next
  }
  /__CYTOSCAPE_SPLICE__/ {
    f = ENVIRON["RENDER_CYTOSCAPE_FILE"]
    while ((getline line < f) > 0) print line
    close(f)
    next
  }
  /__CYTOSCAPE_DAGRE_SPLICE__/ {
    f = ENVIRON["RENDER_CYTOSCAPE_DAGRE_FILE"]
    while ((getline line < f) > 0) print line
    close(f)
    next
  }
  { print }
' "$TEMPLATE" > "$OUT_TMP" || die "template splice failed"

# --- Self-check --------------------------------------------------------------
if grep -q '__MARKED_SPLICE__\|__DOC_B64_SPLICE__\|__SOURCE_PATH_SPLICE__\|__CYTOSCAPE_SPLICE__\|__CYTOSCAPE_DAGRE_SPLICE__' "$OUT_TMP"; then
  die "splice incomplete: slot markers remain (template drift?)"
fi
[ -s "$OUT_TMP" ] || die "splice produced an empty file"

# mktemp files are 0600; make the artifact world-readable like a normal file.
if ! cp "$OUT_TMP" "$OUT"; then
  die "could not write output: $OUT"
fi
chmod 644 "$OUT" || true

printf 'rendered: %s\n' "$OUT"

# --- Open --------------------------------------------------------------------
open_file() {
  if command -v xdg-open > /dev/null 2>&1; then
    xdg-open "$1" || printf 'render-doc: could not auto-open; view manually: %s\n' "$1" >&2
  elif command -v open > /dev/null 2>&1; then
    open "$1" || printf 'render-doc: could not auto-open; view manually: %s\n' "$1" >&2
  else
    printf 'render-doc: the open command is unavailable on this system; view manually: %s\n' "$1" >&2
  fi
}

# Contract: B02 --open server client (plan 001-render-doc-fixed-port-server)
#
# DELIBERATELY UNIMPLEMENTED. The block below is a stub that fails loudly;
# everything above this line (the render pipeline) is finished code and must
# keep working unchanged.
#
# Reference implementation to port from:
#   /home/cwilliamson/github/clam-code @ origin/master (41442a2),
#   general/skills/render-doc/scripts/render.sh  (commit 50ccb32), the
#   `if [ "$OPEN" -eq 1 ]` block. Port it rather than re-deriving.
#
# Behavior:
#   Point a browser at the document, served by the shared server described
#   in serve.py's B01 contract, degrading to a file:// open whenever that
#   server cannot be reached or trusted. Order of operations:
#
#   1. No python3, or no serve.py beside this script -> file:// open of the
#      rendered .html. No server is started, nothing is printed to stderr
#      about it.
#   2. Otherwise poll GET http://127.0.0.1:$PORT/health, where PORT is
#      RENDER_DOC_PORT or 27183. EVERY curl in this block carries
#      --max-time, so an unresponsive process on the port can never hang
#      the render (the failure this replaces).
#      - Health answers with "app" != "render-doc": a foreign process owns
#        the port. Print a stderr notice naming the port, then file:// open.
#      - Health answers with "app" == "render-doc" and "version" equal to
#        the sha256 of serve.py on disk: reuse this server.
#      - Health answers with "app" == "render-doc" but a different
#        "version": the server runs outdated code. Kill it (by the pid in
#        the health payload, and by /tmp/render-doc-serve-$PORT.pid), poll
#        until the port stops answering, then spawn a fresh one. If it will
#        not die, print a stderr notice and file:// open.
#      - Nothing answers: spawn `python3 serve.py` detached, then poll
#        /health until it answers. A spawn that exits early is either a real
#        failure or a losing EADDRINUSE race, so stop polling and do ONE
#        final health check: if it answers, the race winner is serving and
#        this run reuses it; if not, print a stderr notice and file:// open.
#   3. On success, open
#      http://127.0.0.1:$PORT/doc/<percent-encoded absolute path of the
#      SOURCE MARKDOWN> — note the markdown path, not the .html; the server
#      derives the sibling .html and re-renders it when stale.
#
# Inputs:
#   - $OPEN (1 when --open was passed), $OUT (rendered .html path),
#     $DOC_ABS (absolute source .md path), $SCRIPT_DIR.
#   - RENDER_DOC_PORT (optional, default 27183).
#
# Outputs:
#   - A browser opened on either the server URL or the file:// URL.
#   - One stderr line per degradation, naming the reason.
#
# Errors:
#   - There are none that stop the script: every failure path degrades to a
#     file:// open. render.sh must still exit 0 after a successful render,
#     whatever the server did — callers treat a non-zero exit as "fall back
#     to the markdown flow", so a server problem must never look like a
#     render problem.
#
# Invariants:
#   - open_file's opener preference is unchanged and load-bearing: xdg-open
#     is tried BEFORE open, because some Linux distributions ship an
#     unrelated `open` (openvt). Neither the order nor the command -v guards
#     may be reordered.
#   - Never contacts anything but 127.0.0.1 on the configured port.
#   - Writes no state file. /tmp/render-doc-serve.json belongs to the
#     retired design and must not be read, written, or referenced.
#
# Edge cases:
#   - Port held by an unrelated service (foreign app marker).
#   - Two renders racing to spawn the server: one wins the bind, both open.
#   - Server killed between the health check and the open: the browser shows
#     a connection error; render.sh has already exited 0. Acceptable.
#   - Markdown path with spaces or non-ASCII: percent-encoded into the URL.
#   - RENDER_DOC_PORT pointing at a port already held by a foreign process.
if [ "$OPEN" -eq 1 ]; then
  PORT="${RENDER_DOC_PORT:-27183}"
  SERVE="$SCRIPT_DIR/serve.py"
  BASE="http://127.0.0.1:$PORT"

  if command -v python3 > /dev/null 2>&1 && [ -f "$SERVE" ]; then
    FALLBACK=0

    # --- Ensure the shared server is running and current ----------------------
    # The fixed port is the lock. If /health answers with our app marker and
    # the sha256 of serve.py on disk, reuse the server; a stale version gets
    # killed and respawned; a foreign process on the port means file://
    # fallback. A losing EADDRINUSE racer exits 0 by design and the winner
    # answers the health poll, so concurrent sessions never fight.
    HEALTH="$(curl -sf --max-time 2 "$BASE/health" 2> /dev/null || true)"
    if [ -n "$HEALTH" ]; then
      APP="$(printf '%s' "$HEALTH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('app',''))" 2> /dev/null || true)"
      if [ "$APP" != "render-doc" ]; then
        printf 'render-doc: port %s is held by another process; falling back to file:// open\n' "$PORT" >&2
        FALLBACK=1
      else
        RUNNING_SHA="$(printf '%s' "$HEALTH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('version',''))" 2> /dev/null || true)"
        DISK_SHA="$(python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$SERVE" 2> /dev/null || true)"
        if [ "$RUNNING_SHA" != "$DISK_SHA" ]; then
          # Outdated server (e.g. after a master pull): kill it, wait for the
          # port to clear, then respawn the current code below.
          SERVER_PID="$(printf '%s' "$HEALTH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('pid',''))" 2> /dev/null || true)"
          [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2> /dev/null || true
          PIDFILE="/tmp/render-doc-serve-$PORT.pid"
          [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE" 2> /dev/null)" 2> /dev/null || true
          DEAD=0
          for _ in 1 2 3 4; do
            sleep 0.25
            if ! curl -sf --max-time 1 "$BASE/health" > /dev/null 2>&1; then
              DEAD=1
              break
            fi
          done
          if [ "$DEAD" -eq 0 ]; then
            printf 'render-doc: could not replace the outdated server on port %s; falling back to file:// open\n' "$PORT" >&2
            FALLBACK=1
          fi
          HEALTH=""
        fi
      fi
    fi

    if [ "$FALLBACK" -eq 0 ] && [ -z "$HEALTH" ]; then
      python3 "$SERVE" > /dev/null 2>&1 &
      SERVE_PID=$!
      disown "$SERVE_PID" 2> /dev/null || true

      HEALTHY=0
      for _ in 1 2 3 4 5 6 7 8; do
        sleep 0.25
        if curl -sf --max-time 1 "$BASE/health" > /dev/null 2>&1; then
          HEALTHY=1
          break
        fi
        # A spawn that dies is either a real startup failure or a losing
        # EADDRINUSE racer; stop polling either way. The final health check
        # below tells the two apart: the race winner answers it.
        if ! kill -0 "$SERVE_PID" 2> /dev/null; then break; fi
      done
      if [ "$HEALTHY" -eq 0 ] \
        && curl -sf --max-time 1 "$BASE/health" > /dev/null 2>&1; then
        HEALTHY=1
      fi
      if [ "$HEALTHY" -eq 0 ]; then
        printf 'render-doc: annotation server failed to start; falling back to file:// open\n' >&2
        FALLBACK=1
      fi
    fi

    if [ "$FALLBACK" -eq 1 ]; then
      open_file "$OUT"
    else
      DOC_URL_PATH="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$DOC_ABS")"
      open_file "$BASE/doc$DOC_URL_PATH"
    fi
  else
    open_file "$OUT"
  fi
fi

# Contract: B08 --serve registration mode (plan 001-render-graph-always)
#
# DELIBERATELY UNIMPLEMENTED. The block below is a stub that fails loudly;
# the render pipeline and the --open block above are finished code and must
# keep working unchanged.
#
# Behavior:
#   render.sh <doc.md> --serve makes the document available (and
#   registered) on the shared server WITHOUT opening anything:
#   1. The render pipeline above has already produced the sibling .html.
#   2. Ensure the shared server is up and current, REUSING the exact
#      posture of the --open block: health probe with --max-time on every
#      curl, foreign-process detection by the "app" marker,
#      version-mismatch kill-and-respawn against serve.py's on-disk
#      sha256, EADDRINUSE-race tolerance with one final health check.
#   3. Trigger a server-side render + registration with one
#      GET /doc/<percent-encoded DOC_ABS> request (curl -sf --max-time;
#      the response body is discarded — the request existing is what
#      renders and registers).
#   4. Print exactly one line to stdout:
#      serving: http://127.0.0.1:<port>/doc/<percent-encoded DOC_ABS>
#   5. Open no browser, ever — open_file is never called on this path.
# Inputs: $SERVE_MODE=1; $DOC_ABS; RENDER_DOC_PORT (default 27183);
#   serve.py beside this script; python3 on PATH.
# Outputs: the single "serving: <url>" stdout line; the server has the
#   doc rendered and registered (serve.py B02), so a WORKGRAPH.md now
#   appears on the index (serve.py B03).
# Errors: unlike --open, --serve does NOT degrade to file:// — its whole
#   point is registration. python3 missing, serve.py missing, a foreign
#   process holding the port, a server that cannot be started or
#   replaced, or the /doc request failing -> one stderr line naming the
#   reason, exit 3. (Exit 3, not 1: the local render DID succeed and the
#   sibling .html exists; capability-gated callers treat any non-zero as
#   "skip silently".)
# Invariants:
#   - Mutual exclusion with --open is enforced at argument parsing
#     (usage error, exit 1) — already wired above.
#   - Never contacts anything but 127.0.0.1 on the configured port.
#   - Writes no state file.
#   - A --serve failure exits 3 AFTER the successful render; a render
#     failure has already exited 1 long before this block.
# Edge cases: doc path with spaces/non-ASCII (percent-encoded exactly as
#   the --open path does); two --serve runs racing to spawn the server
#   (one binds, both register against the winner); a doc outside $HOME or
#   outside a git worktree (the server refuses the /doc request with 403
#   -> stderr + exit 3 — the scope rules live server-side).
if [ "$SERVE_MODE" -eq 1 ]; then
  PORT="${RENDER_DOC_PORT:-27183}"
  SERVE="$SCRIPT_DIR/serve.py"
  BASE="http://127.0.0.1:$PORT"

  # Unlike open_file's degrade-and-continue, every failure here is terminal:
  # registration is the whole point of --serve, so there is nothing to
  # degrade to. Exit 3 (not 1): the render above already succeeded.
  serve_die() { # <reason>
    printf 'render-doc: %s\n' "$*" >&2
    exit 3
  }

  command -v python3 > /dev/null 2>&1 \
    || serve_die "python3 is required for --serve but was not found on PATH"
  [ -f "$SERVE" ] || serve_die "the annotation server script is missing: $SERVE"

  # --- Ensure the shared server is running and current ------------------------
  # Identical posture to the --open block above: the fixed port is the lock;
  # a foreign process on it is left alone; an outdated version is killed and
  # respawned; a losing EADDRINUSE racer's early exit is indistinguishable
  # from a real crash until the final health check tells them apart.
  HEALTH="$(curl -sf --max-time 2 "$BASE/health" 2> /dev/null || true)"
  if [ -n "$HEALTH" ]; then
    APP="$(printf '%s' "$HEALTH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('app',''))" 2> /dev/null || true)"
    if [ "$APP" != "render-doc" ]; then
      serve_die "port $PORT is held by another, non-render-doc process; leaving it alone"
    fi

    RUNNING_SHA="$(printf '%s' "$HEALTH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('version',''))" 2> /dev/null || true)"
    DISK_SHA="$(python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$SERVE" 2> /dev/null || true)"
    if [ "$RUNNING_SHA" != "$DISK_SHA" ]; then
      # Outdated server: kill it, wait for the port to clear, then respawn
      # the current code below.
      SERVER_PID="$(printf '%s' "$HEALTH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('pid',''))" 2> /dev/null || true)"
      [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2> /dev/null || true
      PIDFILE="/tmp/render-doc-serve-$PORT.pid"
      [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE" 2> /dev/null)" 2> /dev/null || true
      DEAD=0
      for _ in 1 2 3 4; do
        sleep 0.25
        if ! curl -sf --max-time 1 "$BASE/health" > /dev/null 2>&1; then
          DEAD=1
          break
        fi
      done
      [ "$DEAD" -eq 1 ] || serve_die "could not replace the outdated server on port $PORT"
      HEALTH=""
    fi
  fi

  if [ -z "$HEALTH" ]; then
    python3 "$SERVE" > /dev/null 2>&1 &
    SERVE_PID=$!
    disown "$SERVE_PID" 2> /dev/null || true

    HEALTHY=0
    for _ in 1 2 3 4 5 6 7 8; do
      sleep 0.25
      if curl -sf --max-time 1 "$BASE/health" > /dev/null 2>&1; then
        HEALTHY=1
        break
      fi
      # A dead spawn is either a real startup failure or a losing EADDRINUSE
      # racer; stop polling either way and let the final check below tell
      # them apart.
      if ! kill -0 "$SERVE_PID" 2> /dev/null; then break; fi
    done
    if [ "$HEALTHY" -eq 0 ] \
      && curl -sf --max-time 1 "$BASE/health" > /dev/null 2>&1; then
      HEALTHY=1
    fi
    [ "$HEALTHY" -eq 1 ] || serve_die "the annotation server failed to start on port $PORT"
  fi

  # --- Register: the GET request IS the render + registration -----------------
  DOC_URL_PATH="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$DOC_ABS")"
  DOC_URL="$BASE/doc$DOC_URL_PATH"
  curl -sf --max-time 10 "$DOC_URL" > /dev/null 2>&1 \
    || serve_die "the server refused the request for $DOC_ABS (see its own log for the reason)"

  printf 'serving: %s\n' "$DOC_URL"
fi
