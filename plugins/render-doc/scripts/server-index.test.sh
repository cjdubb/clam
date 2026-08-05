#!/usr/bin/env bash
# server-index.test.sh — verifies the docblock "Contract: B03 project index" on
# Handler._serve_index in plugins/render-doc/scripts/serve.py, clause by clause.
#
# GET / is the one page that lists documents nobody navigated to: it reads the
# served-doc registry, groups the entries by worktree, and gives each group a
# WORKGRAPH.md headline carrying the open-node count and the Focus id read
# through the work-graph protocol's machine-read markers
# (docs/protocols/work-graph.md).
#
# Fixtures are five worktrees under $HOME (the scope rules demand both), each
# shaped for one clause: a full work graph whose Focus names a node that does
# not exist, a group with no work graph at all, an unreadable work graph, an
# empty one, and a linked worktree of the first repo — two worktrees of one
# repo must be two groups. The registry is SEEDED through
# /tmp/render-doc-registry-<port>.json before the server starts, so every
# ordering assertion rests on last-served times this file chose rather than on
# the wall clock.
#
# Reading the page: assertions about what a reader SEES run over a tag-stripped
# copy of the group's slice, and assertions about where a link POINTS run over
# the raw slice. That split is deliberate — the contract fixes the /doc target
# and the visible facts, never the markup that carries them, so pinning tag
# shape would fail a faithful implementation for no reason. Digit windows
# exclude / . and ~ so a random mktemp suffix inside a group label can never
# stand in for a count the page failed to print.
#
# Every server binds a throwaway kernel-assigned port (never the default 27183)
# and is killed by the EXIT trap, which also removes each port's registry file
# and pidfile.
#
# Out of scope here: the registry's own semantics (server-registry.test.sh),
# /raw (server-raw.test.sh), /doc's rendering (server.test.sh).

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  for f in ${TMP_ARTEFACTS[@]+"${TMP_ARTEFACTS[@]}"}; do
    [ -n "$f" ] && rm -rf "$f"
  done
  # chmod first: one work graph is deliberately mode 000.
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

# --- Required tooling --------------------------------------------------------
MISSING=0
for tool in python3 curl git; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    fail "required tool not available: $tool"
    MISSING=1
  fi
done
if [ "$MISSING" -ne 0 ]; then
  printf 'server-index.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
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

start_server() { # <port> <stderr file>
  RENDER_DOC_PORT="$1" python3 "$SERVE" > "$2.stdout" 2> "$2" &
  SERVER_PIDS+=("$!")
  TMP_ARTEFACTS+=("/tmp/render-doc-serve-$1.pid" "/tmp/render-doc-registry-$1.json")
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

header_value() { # <header name>
  awk -v want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]'):" '
    { k = tolower($1) }
    k == want { sub(/\r$/, "", $2); print $2; exit }
  ' "$HEADERS" 2> /dev/null
}

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

# Character index of <needle> in the last response body, or -1. Ordering
# clauses compare these.
pos_of() { # <needle>
  python3 - "$BODY" "$1" << 'PY' 2> /dev/null
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
print(data.find(sys.argv[2]))
PY
}

body_has() { # <literal string>
  [ "$(pos_of "$1")" != "-1" ]
}

# True when the last request returned a page at all. "This must NOT appear on
# the page" says nothing about an empty reply, so those assertions are gated on
# this and reported as unverified rather than passing vacuously.
page_ok() {
  [ "$RESP_CODE" = "200" ] && [ -s "$BODY" ]
}

# Group labels, filled once the fixtures exist. A group's slice runs from its
# own label to whichever OTHER group label comes next — markup-independent, so
# no assertion here depends on how groups are nested or wrapped.
GROUP_LABELS=()

group_slice() { # <label>
  python3 - "$BODY" "$1" ${GROUP_LABELS[@]+"${GROUP_LABELS[@]}"} << 'PY' 2> /dev/null
import sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
label, labels = sys.argv[2], sys.argv[3:]
i = data.find(label)
if i < 0:
    sys.exit(1)
end = len(data)
for other in labels:
    if other == label:
        continue
    j = data.find(other, i + len(label))
    if j >= 0:
        end = min(end, j)
sys.stdout.write(data[i:end])
PY
}

# The same slice as a reader sees it: tags removed, entities decoded, runs of
# whitespace collapsed.
group_text() { # <label>
  group_slice "$1" | python3 -c "
import html, re, sys
data = sys.stdin.read()
data = re.sub(r'<[^>]*>', ' ', data)
print(re.sub(r'\s+', ' ', html.unescape(data)))
" 2> /dev/null
}

# <a href> targets inside a group slice.
group_hrefs() { # <label>
  group_slice "$1" | grep -oE 'href="[^"]*"' | sed 's/^href="//; s/"$//'
}

group_has_link_to() { # <label> <absolute md path>
  local want
  want="/doc$(enc "$2")"
  group_hrefs "$1" | grep -qxF -- "$want"
}

# A visible-text window that cannot be spanned by a path: / . and ~ are
# excluded, so a digit from a group label can never satisfy a count clause.
WIN='[^0-9/.~]{0,40}'

text_matches() { # <text> <ere>
  printf '%s' "$1" | grep -Eqi -- "$2"
}

# --- Fixtures ----------------------------------------------------------------
IDX_HOME="$(mktemp -d "$HOME/.render-doc-indextest.XXXXXX")"
HOME_DIRS+=("$IDX_HOME")

ALPHA="$IDX_HOME/repo-alpha"   # full work graph, Focus names a missing node
BETA="$IDX_HOME/repo-beta"     # no work graph at all
GAMMA="$IDX_HOME/repo-gamma"   # unreadable work graph
DELTA="$IDX_HOME/repo-delta"   # empty work graph
LINKED="$IDX_HOME/repo-linked" # linked worktree of repo-alpha
for d in "$ALPHA" "$BETA" "$GAMMA" "$DELTA"; do
  mkdir -p "$d"
  git init -q "$d" 2> /dev/null
done

mkdir -p "$ALPHA/.local" "$ALPHA/docs" "$GAMMA/.local" "$DELTA/.local"

# repo-alpha's work graph: 7 lines match the protocol's open marker exactly.
# The three decoys below match a loose "grep for open" and must not be counted,
# so an implementation that ignores the literal marker lands on 10, not 7.
cat > "$ALPHA/.local/WORKGRAPH.md" << 'MD'
# Work Graph

Focus: N42

## N01 — first node
- Goal: something
- Status: open
- Parent: none
- Deps: none

## N02 — second node
- Goal: something
- Status: open
- Parent: N01
- Deps: none

## N03 — third node
- Goal: something
- Status: open
- Parent: N01
- Deps: none

## N04 — fourth node
- Goal: something
- Status: open
- Parent: N01
- Deps: none

## N05 — fifth node
- Goal: something
- Status: open
- Parent: N01
- Deps: none

## N06 — sixth node
- Goal: something
- Status: open
- Parent: N02
- Deps: none

## N07 — seventh node
- Goal: something
- Status: open
- Parent: N02
- Deps: none

## N08 — decoy, qualified status
- Goal: not open by the marker
- Status: open (blocked)
- Parent: none
- Deps: none

## N09 — decoy, indented status
- Goal: not open by the marker
  - Status: open
- Parent: none
- Deps: none

## N10 — decoy, longer word
- Goal: not open by the marker
- Status: opened
- Parent: none
- Deps: none

## N11 — done node
- Goal: finished
- Status: done
- Parent: none
- Deps: none
- Notes: Focus: N07 — a decoy that is not the Focus line

## N12 — dropped node
- Goal: abandoned
- Status: dropped (superseded)
- Parent: none
- Deps: none
MD

printf '# Plan: alpha\n\nbody\n' > "$ALPHA/docs/plan.md"
printf '# Notes\n\nbody\n' > "$ALPHA/notes.md"

printf '# Design: beta\n\nbody\n' > "$BETA/design.md"
# Escaping fixture: entry-derived text is untrusted, and a filename is the
# cheapest untrusted thing there is.
EVIL_MD="$BETA/evil<img>.md"
printf '# Evil\n\nbody\n' > "$EVIL_MD"

printf '# Work Graph\n\nFocus: N01\n\n## N01 — hidden\n- Status: open\n' > "$GAMMA/.local/WORKGRAPH.md"

printf '# Work Graph\n\nFocus: none\n' > "$DELTA/.local/WORKGRAPH.md"

# Two worktrees of ONE repo are two groups. A linked worktree's .git is a plain
# file, which the scope rule counts as a worktree just like a directory.
LINKED_OK=0
if git -C "$ALPHA" -c user.email=test@example.invalid -c user.name=Test \
  commit -q --allow-empty -m init > /dev/null 2>&1 \
  && git -C "$ALPHA" worktree add -q "$LINKED" -b index-test > /dev/null 2>&1; then
  printf '# Linked\n\nbody\n' > "$LINKED/linked-doc.md"
  LINKED_OK=1
fi

ALPHA_WG="$(realpath_of "$ALPHA/.local/WORKGRAPH.md")"
ALPHA_PLAN="$(realpath_of "$ALPHA/docs/plan.md")"
ALPHA_NOTES="$(realpath_of "$ALPHA/notes.md")"
BETA_DESIGN="$(realpath_of "$BETA/design.md")"
BETA_EVIL="$(realpath_of "$EVIL_MD")"
GAMMA_WG="$(realpath_of "$GAMMA/.local/WORKGRAPH.md")"
DELTA_WG="$(realpath_of "$DELTA/.local/WORKGRAPH.md")"
LINKED_DOC="$(realpath_of "$LINKED/linked-doc.md")"

# A seeded entry whose file is already gone: the index's source of truth is
# scope-pruned, so it must not reach the page at all.
VANISHED="$(realpath_of "$ALPHA/docs")/vanished-doc.md"

HOME_REAL="$(realpath_of "$HOME")"
label_for() { # <worktree dir> -> the ~-abbreviated label the page must show
  local real
  real="$(realpath_of "$1")"
  printf '~%s' "${real#"$HOME_REAL"}"
}

L_ALPHA="$(label_for "$ALPHA")"
L_BETA="$(label_for "$BETA")"
L_GAMMA="$(label_for "$GAMMA")"
L_DELTA="$(label_for "$DELTA")"
L_LINKED="$(label_for "$LINKED")"
GROUP_LABELS=("$L_ALPHA" "$L_BETA" "$L_GAMMA" "$L_DELTA")
[ "$LINKED_OK" -eq 1 ] && GROUP_LABELS+=("$L_LINKED")

if [ "$HOME_REAL" = "$(realpath_of "$IDX_HOME")" ] || [ "$L_ALPHA" = "~" ]; then
  fail "setup: the fixture labels did not resolve under \$HOME; the grouping clauses cannot be checked"
  printf 'server-index.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

# Seed times: group order must come out repo-beta, repo-alpha, repo-linked,
# repo-gamma, repo-delta — each group ranked by its most recent member.
PORT_A="$(free_port)"
BASE_A="http://127.0.0.1:$PORT_A"
REG_A="/tmp/render-doc-registry-$PORT_A.json"
if [ -e "$REG_A" ]; then
  fail "test port $PORT_A already has a registry file at $REG_A; aborting to avoid clobbering it"
  printf 'server-index.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

SEED_ARGS=(
  "$BETA_DESIGN" 5000
  "$BETA_EVIL" 4900
  "$ALPHA_WG" 4000
  "$ALPHA_PLAN" 3500
  "$ALPHA_NOTES" 3000
  "$GAMMA_WG" 1500
  "$DELTA_WG" 1000
  "$VANISHED" 4500
)
[ "$LINKED_OK" -eq 1 ] && SEED_ARGS+=("$LINKED_DOC" 2000)
write_seed "$REG_A" "${SEED_ARGS[@]}"

# Read-only invariant: a manifest of every fixture file and its hash, compared
# again once the page has been served.
manifest() {
  find "$IDX_HOME" -type f ! -path '*/.git/*' -exec sha256sum {} + 2> /dev/null | sort
}
MANIFEST_BEFORE="$(manifest)"

start_server "$PORT_A" "$WORK/srv-a.stderr"
if wait_healthy "$BASE_A"; then
  pass "server: healthy on test port $PORT_A"
else
  fail "server: did not become healthy on test port $PORT_A — no index clause can be checked"
  printf 'server-index.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

if [ "$LINKED_OK" -ne 1 ]; then
  skip "grouping: git worktree add failed here, so the two-worktrees-of-one-repo clause is unchecked"
fi

# =============================================================================
# Outputs: 200 text/html, correct Content-Length, one self-contained page
# =============================================================================

do_request "$BASE_A/"
if [ "$RESP_CODE" = "200" ]; then
  pass "GET /: the index is served (200)"
else
  fail "GET /: expected 200, got $RESP_CODE"
fi

ctype="$(header_value Content-Type)"
if printf '%s' "$ctype" | grep -qi '^text/html'; then
  pass "GET /: Content-Type is text/html (\"$ctype\")"
else
  fail "GET /: Content-Type is \"$ctype\", expected text/html; charset=utf-8"
fi
if printf '%s' "$ctype" | grep -qi 'charset=utf-8'; then
  pass "GET /: Content-Type names charset=utf-8"
else
  fail "GET /: Content-Type \"$ctype\" does not name charset=utf-8"
fi

clen="$(header_value Content-Length)"
blen="$(wc -c < "$BODY" | tr -d ' ')"
if [ -n "$clen" ] && [ "$clen" = "$blen" ]; then
  pass "GET /: Content-Length matches the body ($blen bytes)"
else
  fail "GET /: Content-Length \"$clen\" does not match the $blen received bytes"
fi

if grep -qi '<html' "$BODY" 2> /dev/null && grep -qi '</html>' "$BODY" 2> /dev/null; then
  pass "GET /: the response is one complete HTML page"
else
  fail "GET /: the response is not a complete HTML document"
fi

# Self-contained: nothing fetched from the network at view time (the
# render.test.sh idiom).
if ! page_ok; then
  fail "GET /: the no-external-resources clause could not be checked (no page was returned)"
elif grep -E '<link[^>]+href="https?:|src="https?:|src='"'"'https?:|url\(https?:|@import|fonts\.googleapis' "$BODY" > /dev/null 2>&1; then
  fail "GET /: the page references external URLs/CDNs"
else
  pass "GET /: no external URL/CDN references"
fi
if grep -qi '<style' "$BODY" 2> /dev/null; then
  pass "GET /: styling is inline (a <style> block is present)"
else
  fail "GET /: no inline <style> block — the page is not self-contained"
fi

# =============================================================================
# Clause 6: one collapsible, expanded-by-default group per worktree
# =============================================================================

details_count="$(grep -oi '<details' "$BODY" 2> /dev/null | wc -l | tr -d ' ')"
summary_count="$(grep -oi '<summary' "$BODY" 2> /dev/null | wc -l | tr -d ' ')"
expected_groups="${#GROUP_LABELS[@]}"
if [ "$details_count" = "$expected_groups" ]; then
  pass "groups: one <details> element per worktree ($expected_groups)"
else
  fail "groups: found $details_count <details> elements, expected $expected_groups (one per worktree)"
fi
if [ "$summary_count" = "$expected_groups" ]; then
  pass "groups: each group carries a <summary> (collapsible without scripting)"
else
  fail "groups: found $summary_count <summary> elements, expected $expected_groups"
fi
open_details="$(grep -oiE '<details[^>]*\bopen\b' "$BODY" 2> /dev/null | wc -l | tr -d ' ')"
if [ "$open_details" = "$expected_groups" ]; then
  pass "groups: every group renders expanded by default (the open attribute)"
else
  fail "groups: $open_details of $expected_groups groups carry the open attribute"
fi

# =============================================================================
# Clause 2: a group per worktree, labelled by the nearest .git ancestor,
# abbreviated with a leading ~
# =============================================================================

for lbl in ${GROUP_LABELS[@]+"${GROUP_LABELS[@]}"}; do
  if body_has "$lbl"; then
    pass "groups: the worktree label \"$lbl\" is shown ~-abbreviated"
  else
    fail "groups: no group labelled \"$lbl\" (the ~-abbreviated worktree path)"
  fi
done

# =============================================================================
# Clause 1 + 5: every registered document is listed, linking to its live /doc
# view under the percent-encoded realpath
# =============================================================================

for p in "$ALPHA_WG" "$ALPHA_PLAN" "$ALPHA_NOTES" "$BETA_DESIGN" "$BETA_EVIL" "$GAMMA_WG" "$DELTA_WG"; do
  if body_has "\"/doc$(enc "$p")\""; then
    pass "links: $(basename "$p") links to /doc/<percent-encoded realpath>"
  else
    fail "links: no href=\"/doc$(enc "$p")\" on the page"
  fi
done
if [ "$LINKED_OK" -eq 1 ]; then
  if body_has "\"/doc$(enc "$LINKED_DOC")\""; then
    pass "links: the linked worktree's document links to its own /doc view"
  else
    fail "links: no /doc link for the linked worktree's document"
  fi
fi

# The registry is scope-pruned before the page is built, so a seeded entry
# whose file has vanished never reaches it.
if ! page_ok; then
  fail "links: the scope-pruning clause could not be checked (no page was returned)"
elif body_has "vanished-doc.md"; then
  fail "links: a seeded entry whose file no longer exists was listed"
else
  pass "links: a seeded entry whose file no longer exists is not listed"
fi

# =============================================================================
# Clause 3: groups ordered by their most recently served member; within a
# group, the registry's own last-served order
# =============================================================================

p_beta="$(pos_of "$L_BETA")"
p_alpha="$(pos_of "$L_ALPHA")"
p_gamma="$(pos_of "$L_GAMMA")"
p_delta="$(pos_of "$L_DELTA")"
if [ "$p_beta" -ge 0 ] && [ "$p_alpha" -gt "$p_beta" ] && [ "$p_gamma" -gt "$p_alpha" ] \
  && [ "$p_delta" -gt "$p_gamma" ] 2> /dev/null; then
  pass "order: groups are ordered by their most recently served member"
else
  fail "order: group order is wrong (beta@$p_beta, alpha@$p_alpha, gamma@$p_gamma, delta@$p_delta; expected that order)"
fi
if [ "$LINKED_OK" -eq 1 ]; then
  p_linked="$(pos_of "$L_LINKED")"
  if [ "$p_linked" -gt "$p_alpha" ] && [ "$p_linked" -lt "$p_gamma" ] 2> /dev/null; then
    pass "order: the linked worktree's group is ranked by its own member's time"
  else
    fail "order: the linked worktree's group sits at $p_linked, expected between $p_alpha and $p_gamma"
  fi
fi

alpha_slice="$(group_slice "$L_ALPHA")"
if [ -z "$alpha_slice" ]; then
  fail "order: repo-alpha's group could not be located on the page; its member order is unchecked"
else
  p_plan="$(printf '%s' "$alpha_slice" | grep -bo "/doc$(enc "$ALPHA_PLAN")" | head -1 | cut -d: -f1)"
  p_notes="$(printf '%s' "$alpha_slice" | grep -bo "/doc$(enc "$ALPHA_NOTES")" | head -1 | cut -d: -f1)"
  if [ -n "$p_plan" ] && [ -n "$p_notes" ] && [ "$p_plan" -lt "$p_notes" ]; then
    pass "order: within a group, entries keep the registry's last-served order"
  else
    fail "order: docs/plan.md (last served later) does not precede notes.md within repo-alpha's group"
  fi
fi

# =============================================================================
# Clause 4: a group's WORKGRAPH.md is its headline — /doc link, open-node
# count and Focus id, read through the protocol's machine-read markers
# =============================================================================

alpha_text="$(group_text "$L_ALPHA")"
if [ -z "$alpha_text" ]; then
  fail "workgraph: repo-alpha's group could not be located; its headline clauses are unchecked"
  fail "workgraph: the open-node count could not be checked"
  fail "workgraph: the Focus id could not be checked"
else
  if group_has_link_to "$L_ALPHA" "$ALPHA_WG"; then
    pass "workgraph: the group's WORKGRAPH.md links to its own /doc view"
  else
    fail "workgraph: repo-alpha's group has no /doc link for its WORKGRAPH.md"
  fi
  # 7 lines match ^- Status: open$; the three decoys must not be counted.
  if text_matches "$alpha_text" "7${WIN}open|open${WIN}7"; then
    pass "workgraph: the headline shows the open-node count (7, the marker-matching lines only)"
  else
    fail "workgraph: repo-alpha's headline does not show 7 open nodes: $alpha_text"
  fi
  # Edge case: the Focus id names a node that does not exist — shown as
  # recorded, per the protocol's fail-open rule.
  if text_matches "$alpha_text" "N42"; then
    pass "workgraph: the headline shows the Focus id, even though it names a missing node"
  else
    fail "workgraph: repo-alpha's headline does not show the Focus id N42: $alpha_text"
  fi
fi

# The headline comes first: the work graph precedes the group's other documents.
if [ -n "$alpha_slice" ]; then
  p_wg="$(printf '%s' "$alpha_slice" | grep -bo "/doc$(enc "$ALPHA_WG")" | head -1 | cut -d: -f1)"
  p_plan="$(printf '%s' "$alpha_slice" | grep -bo "/doc$(enc "$ALPHA_PLAN")" | head -1 | cut -d: -f1)"
  if [ -n "$p_wg" ] && [ -n "$p_plan" ] && [ "$p_wg" -lt "$p_plan" ]; then
    pass "workgraph: the WORKGRAPH.md headline precedes the group's other documents"
  else
    fail "workgraph: the WORKGRAPH.md headline does not lead repo-alpha's group"
  fi
fi

# Edge case: a work graph with zero nodes — count 0, Focus none.
delta_text="$(group_text "$L_DELTA")"
if [ -z "$delta_text" ]; then
  fail "workgraph: repo-delta's group could not be located; the empty-graph clause is unchecked"
else
  if text_matches "$delta_text" "0${WIN}open|open${WIN}0"; then
    pass "workgraph: an empty work graph shows an open-node count of 0"
  else
    fail "workgraph: repo-delta's empty work graph does not show a count of 0: $delta_text"
  fi
  if text_matches "$delta_text" "focus${WIN}none|none${WIN}focus"; then
    pass "workgraph: an empty work graph shows Focus none"
  else
    fail "workgraph: repo-delta's headline does not show Focus none: $delta_text"
  fi
fi

# Edge case: a group with no work graph is a plain document list, no headline.
beta_text="$(group_text "$L_BETA")"
if [ -z "$beta_text" ]; then
  fail "workgraph: repo-beta's group could not be located; the no-headline clause is unchecked"
elif text_matches "$beta_text" "WORKGRAPH"; then
  fail "workgraph: repo-beta has no work graph, yet its group mentions one: $beta_text"
else
  pass "workgraph: a group with no work graph gets a plain document list, no headline"
fi

# =============================================================================
# Clause 5: other documents are listed as worktree-relative paths
# =============================================================================

if [ -n "$alpha_text" ]; then
  if text_matches "$alpha_text" "docs/plan\.md"; then
    pass "paths: a document is labelled by its worktree-relative path (docs/plan.md)"
  else
    fail "paths: repo-alpha's group does not show docs/plan.md as a worktree-relative path: $alpha_text"
  fi
  # ...and not by its absolute path. Read from the tag-stripped text, so the
  # href — and any other attribute — legitimately carrying the realpath is out
  # of scope; the claim is only about what a reader sees.
  if printf '%s' "$alpha_text" | grep -qF -- "$ALPHA_PLAN"; then
    fail "paths: repo-alpha's group shows the absolute path of docs/plan.md as visible text"
  else
    pass "paths: the absolute path is only in the link target, never the visible label"
  fi
fi

# =============================================================================
# Clause 7: a file that cannot be read is STILL listed, with its count and
# Focus shown as unavailable — never a 500
# =============================================================================

if [ "$(id -u)" -eq 0 ]; then
  skip "degradation: running as root, so a mode-000 work graph would still be readable"
else
  chmod 000 "$GAMMA/.local/WORKGRAPH.md"
  do_request "$BASE_A/"
  if [ "$RESP_CODE" = "200" ]; then
    pass "degradation: an unreadable work graph does not turn the index into an error"
  else
    fail "degradation: the index returned $RESP_CODE with an unreadable work graph"
  fi
  gamma_text="$(group_text "$L_GAMMA")"
  if group_has_link_to "$L_GAMMA" "$GAMMA_WG"; then
    pass "degradation: the unreadable document is still listed, with its link"
  else
    fail "degradation: the unreadable document was dropped from the page"
  fi
  # "Unavailable" is the implementer's word to choose; what the contract fixes
  # is that no count is CLAIMED for a file that could not be read. The digit
  # window cannot be spanned by a path, so the group label's own random suffix
  # can never satisfy it.
  if text_matches "$gamma_text" "[0-9]${WIN}open|open${WIN}[0-9]"; then
    fail "degradation: repo-gamma's headline claims an open-node count it could not read: $gamma_text"
  else
    pass "degradation: no open-node count is claimed for an unreadable work graph"
  fi
  if text_matches "$gamma_text" "unavailable|unknown|not available|n/a|unreadable|could not|error"; then
    pass "degradation: its count and Focus are marked unavailable"
  else
    fail "degradation: repo-gamma's headline does not say the count and Focus are unavailable: $gamma_text"
  fi
  chmod 644 "$GAMMA/.local/WORKGRAPH.md"
fi

# =============================================================================
# Invariant: ALL entry-derived text is HTML-escaped — file names are untrusted
# =============================================================================

do_request "$BASE_A/"
if body_has "&lt;img&gt;"; then
  pass "escaping: a document name containing markup is HTML-escaped in the page"
else
  fail "escaping: the document named evil<img>.md is not escaped as &lt;img&gt;"
fi
if ! page_ok; then
  fail "escaping: the no-unescaped-markup clause could not be checked (no page was returned)"
elif body_has "<img>"; then
  fail "escaping: an unescaped <img> element from a document name reached the page"
else
  pass "escaping: no unescaped element from a document name reached the page"
fi
if body_has "/doc$(enc "$BETA_EVIL")"; then
  pass "escaping: that document's link target is percent-encoded"
else
  fail "escaping: no percent-encoded /doc link for the document with markup in its name"
fi

# =============================================================================
# Inputs / invariants: Host pinning, query strings, read-only
# =============================================================================

expect_code "host: wrong Host on / rejected" 403 -H 'Host: evil.example' "$BASE_A/"
expect_code "GET /: query string stripped before routing" 200 "$BASE_A/?from=index"

if [ "$(manifest)" = "$MANIFEST_BEFORE" ]; then
  pass "read-only: serving the index rendered nothing and changed no fixture file"
else
  fail "read-only: the fixture tree changed while the index was served: $(diff <(printf '%s' "$MANIFEST_BEFORE") <(manifest) | head -5)"
fi

expect_code "server: still healthy after every index path" 200 "$BASE_A/health"
if grep -q 'Traceback (most recent call last)' "$WORK/srv-a.stderr" 2> /dev/null; then
  fail "outputs: the index raised — a traceback reached the server's stderr"
else
  pass "outputs: no index path wrote a traceback to the server's stderr"
fi

# =============================================================================
# Clause 8 + Errors: zero registered documents is an empty state, not a 500 —
# and a registry that cannot be read is the same empty state
# =============================================================================

EMPTY_STATE='no documents|nothing (has been |been )?(served|rendered|registered)|no (rendered|served|registered) documents|appears? here|will appear|not yet|none yet|empty'

PORT_B="$(free_port)"
BASE_B="http://127.0.0.1:$PORT_B"
start_server "$PORT_B" "$WORK/srv-b.stderr"
if wait_healthy "$BASE_B"; then
  pass "empty state: a server with an empty registry is healthy"
else
  fail "empty state: the empty-registry server did not become healthy"
fi
do_request "$BASE_B/"
if [ "$RESP_CODE" = "200" ]; then
  pass "empty state: zero registered documents still yields 200"
else
  fail "empty state: expected 200 with an empty registry, got $RESP_CODE"
fi
if ! page_ok; then
  fail "empty state: the no-documents clause could not be checked (no page was returned)"
elif body_has 'href="/doc'; then
  fail "empty state: the page lists a document although nothing is registered"
else
  pass "empty state: no document links on an empty page"
fi
empty_text="$(python3 -c "
import html, re, sys
data = open(sys.argv[1], encoding='utf-8', errors='replace').read()
data = re.sub(r'<(script|style)[^>]*>.*?</\1>', ' ', data, flags=re.S | re.I)
data = re.sub(r'<[^>]*>', ' ', data)
print(re.sub(r'\s+', ' ', html.unescape(data)))
" "$BODY" 2> /dev/null)"
if text_matches "$empty_text" "$EMPTY_STATE"; then
  pass "empty state: the page explains that documents appear here once served"
else
  fail "empty state: no empty-state message on the page: $empty_text"
fi

PORT_C="$(free_port)"
BASE_C="http://127.0.0.1:$PORT_C"
printf 'not json at all {{{\n' > "/tmp/render-doc-registry-$PORT_C.json"
start_server "$PORT_C" "$WORK/srv-c.stderr"
if wait_healthy "$BASE_C"; then
  pass "registry failure: a server with an unreadable registry file is healthy"
else
  fail "registry failure: the corrupt-registry server did not become healthy"
fi
do_request "$BASE_C/"
if [ "$RESP_CODE" = "200" ]; then
  pass "registry failure: yields the empty state, not a 500"
else
  fail "registry failure: the index returned $RESP_CODE with an unreadable registry file"
fi

# --- Summary -----------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
  printf 'server-index.test.sh: %d check(s) skipped for this environment\n' "$SKIPPED"
fi
if [ "$FAILURES" -gt 0 ]; then
  printf 'server-index.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'server-index.test.sh: all assertions passed\n'
