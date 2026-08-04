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
  printf 'Usage: render.sh <doc.md> [--open]\n' >&2
  exit 1
}

# --- Argument parsing -------------------------------------------------------
DOC=""
OPEN=0
for arg in "$@"; do
  case "$arg" in
    --open) OPEN=1 ;;
    --*) die "unknown flag: $arg (only --open is supported)" ;;
    *)
      [ -n "$DOC" ] && usage
      DOC="$arg"
      ;;
  esac
done
[ -n "$DOC" ] || usage

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

if [ "$OPEN" -eq 1 ]; then
  SERVE="$SCRIPT_DIR/serve.py"
  STATE_FILE="/tmp/render-doc-serve.json"
  OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

  if command -v python3 > /dev/null 2>&1 && [ -f "$SERVE" ]; then
    # --- Ensure the shared annotation server is running -----------------------
    SERVER_PORT=""
    if [ -f "$STATE_FILE" ]; then
      SERVER_PID="$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['pid'])" 2>/dev/null || true)"
      SERVER_PORT="$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['port'])" 2>/dev/null || true)"
      # Verify it's actually alive.
      if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2> /dev/null \
         && [ -n "$SERVER_PORT" ] \
         && curl -sf "http://127.0.0.1:$SERVER_PORT/health" > /dev/null 2>&1; then
        : # server is alive, reuse it
      else
        # Stale state file; clean up.
        [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2> /dev/null || true
        rm -f "$STATE_FILE"
        SERVER_PORT=""
      fi
    fi

    if [ -z "$SERVER_PORT" ]; then
      # Start a new server. It writes the state file itself.
      URLFILE="$(mktemp)"
      python3 "$SERVE" "$STATE_FILE" > "$URLFILE" 2>/dev/null &
      SERVE_PID=$!
      disown "$SERVE_PID" 2> /dev/null || true

      for _ in 1 2 3 4 5 6 7 8; do
        sleep 0.15
        if [ -f "$STATE_FILE" ]; then
          SERVER_PORT="$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['port'])" 2>/dev/null || true)"
          [ -n "$SERVER_PORT" ] && break
        fi
        if ! kill -0 "$SERVE_PID" 2> /dev/null; then break; fi
      done
      rm -f "$URLFILE"

      if [ -z "$SERVER_PORT" ]; then
        kill "$SERVE_PID" 2> /dev/null || true
        printf 'render-doc: annotation server failed to start; falling back to file:// open\n' >&2
        open_file "$OUT"
        exit 0
      fi
    fi

    # --- Register this document with the running server -----------------------
    REG_RESP="$(curl -sf -X POST "http://127.0.0.1:$SERVER_PORT/register" \
      -H "Content-Type: application/json" \
      -d "$(printf '{"html":"%s","md":"%s"}' "$OUT_ABS" "$DOC_ABS")" 2>/dev/null || true)"

    DOC_PATH="$(printf '%s' "$REG_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['url'])" 2>/dev/null || true)"

    if [ -n "$DOC_PATH" ]; then
      open_file "http://127.0.0.1:$SERVER_PORT$DOC_PATH"
    else
      printf 'render-doc: document registration failed; falling back to file:// open\n' >&2
      open_file "$OUT"
    fi
  else
    open_file "$OUT"
  fi
fi
