#!/usr/bin/env bash
# workgraph-render.test.sh — verifies two contract docblocks clause by
# clause:
#   - "Contract: B01 workgraph-transform" in
#     plugins/render-doc/assets/template.html (the transformWorkGraph
#     stub and its detectDocType/applySchema/BLOCK_SEL/SYNTH_SEL/tooltip
#     wiring).
#   - "Contract: B02 workgraph-fixture (remove at acceptance)" in
#     plugins/render-doc/fixtures/work-graph.md (the fixture's own
#     content; the render.test.sh wiring for this fixture is a separate
#     check_render call there, not repeated here).
#
# There is no DOM/browser harness in this repo (see render.test.sh's own
# header), so B01 is covered by structural assertions over template.html's
# source rather than by executing the transform: the contract's visible
# commitments (doc-type dispatch, the Focus regex, selector growth, the
# tooltip string, the NotImplemented marker), never implementation
# micro-structure such as helper function names or DOM shape, which are
# the implementer's choice.
#
# Docblocks quote the very strings some of these checks look for. B01's
# code-facing checks therefore run against the file with the B01 docblock
# comment itself stripped out (a sed range delete), and B02's checks run
# against the fixture with ALL HTML comments stripped (the render.test.sh /
# structure.test.sh precedent: `sed '/<!--/,/-->/d'`) — so contract prose
# can never satisfy a check meant for real content.

set -uo pipefail  # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$PLUGIN_DIR/assets/template.html"
FIXTURE="$PLUGIN_DIR/fixtures/work-graph.md"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

FAILURES=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'ok: %s\n' "$*"
}

# =============================================================================
# B01 — plugins/render-doc/assets/template.html
# =============================================================================

# The B01 docblock is a single contiguous /* ... */ block; delete it so its
# prose (which quotes "work-graph", the Focus regex, etc. verbatim) cannot
# satisfy a check meant for the real implementation below it.
CODE="$WORK/template.no-docblock.html"
sed '/\/\* Contract: B01 workgraph-transform/,/^[[:space:]]*\*\/[[:space:]]*$/d' "$TEMPLATE" > "$CODE"

if grep -qF 'Contract: B01' "$CODE"; then
  fail "sanity: B01 docblock strip did not remove the marker — the sed range needs adjusting"
fi

# --- Clause: detectDocType has a Work Graph arm (exact-match, no colon) -----
DETECT="$WORK/detectDocType.body"
sed -n '/function detectDocType(md) {/,/var docType = detectDocType(sourceMd);/p' "$TEMPLATE" > "$DETECT"

if [ -s "$DETECT" ]; then
  pass "detectDocType: function found"
else
  fail "detectDocType: function not found (extraction anchor moved?)"
fi

if grep -q 'return "work-graph"' "$DETECT"; then
  pass "detectDocType: an arm returns \"work-graph\""
else
  fail "detectDocType: no arm returns \"work-graph\""
fi

if grep -qiF 'work graph:' "$DETECT"; then
  fail "detectDocType: Work Graph arm looks colon-prefixed like the other arms (contract requires exact-match, no colon)"
else
  pass "detectDocType: no colon-prefixed Work Graph variant"
fi

if grep -qiE '(work graph[$])|(===[[:space:]]*.work graph.)' "$DETECT"; then
  pass "detectDocType: Work Graph arm looks exact-match (end-anchored regex or strict equality)"
else
  fail "detectDocType: Work Graph arm doesn't look exact-match (no end anchor or strict-equality comparison found)"
fi

# --- Clause: applySchema has an explicit work-graph branch running ----------
# transformWorkGraph, never the trailing plan-transforms else.
APPLY="$WORK/applySchema.body"
sed -n '/function applySchema(doc) {/,/transforms.forEach(function (fn) {/p' "$TEMPLATE" > "$APPLY"

if [ -s "$APPLY" ]; then
  pass "applySchema: function found"
else
  fail "applySchema: function not found (extraction anchor moved?)"
fi

wg_line="$(grep -n 'docType === "work-graph"' "$APPLY" | head -1 | cut -d: -f1)"
if [ -n "$wg_line" ]; then
  pass "applySchema: explicit docType === \"work-graph\" branch present"
  window="$(sed -n "${wg_line},$((wg_line + 1))p" "$APPLY")"
  if printf '%s\n' "$window" | grep -q 'transformWorkGraph'; then
    pass "applySchema: the work-graph branch runs transformWorkGraph"
  else
    fail "applySchema: work-graph branch does not reference transformWorkGraph"
  fi
else
  fail "applySchema: no explicit docType === \"work-graph\" branch — a work-graph doc would fall into the plan-transforms else"
fi

# --- Clause: transformWorkGraph exists; NotImplemented marker gone ---------
if grep -q 'function transformWorkGraph(doc)' "$TEMPLATE"; then
  pass "transformWorkGraph: function still present"
else
  fail "transformWorkGraph: function definition missing"
fi

if grep -qF 'NotImplemented: B01 workgraph-transform' "$CODE"; then
  fail "transformWorkGraph: NotImplemented marker still present in code (docblock-stripped)"
else
  pass "transformWorkGraph: NotImplemented marker gone"
fi

# --- Clause: the protocol's Focus regex commitment appears (positionless) --
# Anywhere in the code (docblock stripped), a line combining the literal
# tokens Focus:, N[0-9]+, and none — the protocol's alternation — without
# pinning it to one exact regex spelling or one location in the file.
if grep -F 'Focus:' "$CODE" | grep -F 'N[0-9]+' | grep -qF 'none'; then
  pass "code carries the protocol's Focus regex commitment (Focus: / N[0-9]+ / none)"
else
  fail "no line in the code combines Focus:, N[0-9]+, and none (the protocol's Focus regex)"
fi

# --- Clause: no-schema tooltip names Work Graph alongside the existing types -
tooltip_line="$(grep -F 'toggle.title =' "$TEMPLATE")"
if printf '%s' "$tooltip_line" | grep -qF 'Work Graph'; then
  pass "no-schema tooltip mentions Work Graph"
else
  fail "no-schema tooltip does not mention Work Graph"
fi
for t in 'Plan' 'Decision' 'Design Questions'; do
  if printf '%s' "$tooltip_line" | grep -qF "$t"; then
    pass "no-schema tooltip still mentions $t"
  else
    fail "no-schema tooltip lost its mention of $t"
  fi
done

# --- Clause: BLOCK_SEL / SYNTH_SEL grew past the scaffold baseline ---------
# Pinned literally from the scaffold state (read, not guessed); the check is
# "grew beyond these", never specific new class names — those are the
# implementer's choice.
BLOCK_SEL_BASELINE='p, li, blockquote, tr, .tl-entry'
SYNTH_SEL_BASELINE='.rec-flag, .opt-num, .crit-badge, .edge-arrow, .pros-lbl, .cons-lbl, .dq-rec-lbl, .block-annotate, .composer'

current_block_sel="$(grep -oP 'var BLOCK_SEL = "\K[^"]+' "$TEMPLATE" | head -1)"
current_synth_sel="$(grep -oP 'var SYNTH_SEL = "\K[^"]+' "$TEMPLATE" | head -1)"

block_baseline_count="$(printf '%s' "$BLOCK_SEL_BASELINE" | tr ',' '\n' | wc -l | tr -d ' ')"
synth_baseline_count="$(printf '%s' "$SYNTH_SEL_BASELINE" | tr ',' '\n' | wc -l | tr -d ' ')"
current_block_count="$(printf '%s' "$current_block_sel" | tr ',' '\n' | wc -l | tr -d ' ')"
current_synth_count="$(printf '%s' "$current_synth_sel" | tr ',' '\n' | wc -l | tr -d ' ')"

if [ -n "$current_block_sel" ] && [ "$current_block_sel" != "$BLOCK_SEL_BASELINE" ] && [ "$current_block_count" -gt "$block_baseline_count" ]; then
  pass "BLOCK_SEL grew past the scaffold baseline ($block_baseline_count -> $current_block_count classes)"
else
  fail "BLOCK_SEL did not grow past the scaffold baseline ('$BLOCK_SEL_BASELINE')"
fi

if [ -n "$current_synth_sel" ] && [ "$current_synth_sel" != "$SYNTH_SEL_BASELINE" ] && [ "$current_synth_count" -gt "$synth_baseline_count" ]; then
  pass "SYNTH_SEL grew past the scaffold baseline ($synth_baseline_count -> $current_synth_count classes)"
else
  fail "SYNTH_SEL did not grow past the scaffold baseline ('$SYNTH_SEL_BASELINE')"
fi

# =============================================================================
# B02 — plugins/render-doc/fixtures/work-graph.md
# =============================================================================
strip_comments() { sed '/<!--/,/-->/d' "$1"; }

FIXTURE_BODY="$WORK/work-graph.stripped.md"
strip_comments "$FIXTURE" > "$FIXTURE_BODY"

# --- Clause: the Contract: B02 marker is gone at acceptance -----------------
# Checked on BOTH the raw file (the real acceptance bar: the whole HTML
# comment is deleted) and the stripped body (trivially true once comments
# are stripped, but keeps the two checks independent and honest).
if grep -qF 'Contract: B02' "$FIXTURE"; then
  fail "fixture still contains the Contract: B02 marker (must be deleted at acceptance)"
else
  pass "Contract: B02 marker is gone from the raw fixture"
fi
if grep -qF 'Contract: B02' "$FIXTURE_BODY"; then
  fail "fixture (comment-stripped) still contains a Contract: B02 marker"
else
  pass "Contract: B02 marker is gone from the comment-stripped fixture"
fi

# --- Clause: H1 exactly "# Work Graph" --------------------------------------
if grep -qE '^# Work Graph[[:space:]]*$' "$FIXTURE_BODY"; then
  pass "fixture: H1 is exactly \"# Work Graph\""
else
  fail "fixture: H1 is not exactly \"# Work Graph\""
fi

# --- Clause: a Focus line matching the protocol regex, naming a real node --
focus_line="$(grep -E '^Focus: (N[0-9]+|none)[[:space:]]*$' "$FIXTURE_BODY" | head -1)"
if [ -n "$focus_line" ]; then
  pass "fixture: has a Focus line matching the protocol regex"
else
  fail "fixture: no line matches ^Focus: (N[0-9]+|none)[[:space:]]*\$"
fi

focus_id="$(printf '%s' "$focus_line" | sed -E 's/^Focus: (N[0-9]+|none).*/\1/')"
if [ "$focus_id" = "none" ] || [ -z "$focus_id" ]; then
  fail "fixture: Focus does not name an existing node (found '$focus_id') — contract requires it to name one"
elif grep -qE "^## ${focus_id} — " "$FIXTURE_BODY"; then
  pass "fixture: Focus names an existing node ($focus_id)"
else
  fail "fixture: Focus id '$focus_id' does not match any node heading"
fi

# --- Clause: >= 5 node sections ----------------------------------------------
node_count="$(grep -cE '^## N[0-9]+ — ' "$FIXTURE_BODY")"
if [ "$node_count" -ge 5 ]; then
  pass "fixture: $node_count node sections (>= 5)"
else
  fail "fixture: only $node_count node sections (need >= 5)"
fi

# --- Clause: >= 1 done node --------------------------------------------------
if grep -qE '^- Status: done[[:space:]]*$' "$FIXTURE_BODY"; then
  pass "fixture: at least one node with - Status: done"
else
  fail "fixture: no node with - Status: done"
fi

# --- Clause: >= 1 dropped node with a (non-empty) reason ---------------------
if grep -qE '^- Status: dropped \(.+\)[[:space:]]*$' "$FIXTURE_BODY"; then
  pass "fixture: at least one dropped node with a reason"
else
  fail "fixture: no node with - Status: dropped (<reason>)"
fi

# --- Clause: >= 1 node with >= 2 Deps ----------------------------------------
if grep -qE '^- Deps: N[0-9]+(, N[0-9]+)+[[:space:]]*$' "$FIXTURE_BODY"; then
  pass "fixture: at least one node with >= 2 Deps"
else
  fail "fixture: no node has a Deps line with >= 2 entries"
fi

# --- Clause: a Parent chain >= 2 deep (a grandchild exists) ------------------
declare -A PARENT_OF=()
node_id=""
while IFS= read -r line; do
  case "$line" in
    "## N"*" — "*)
      node_id="$(printf '%s' "$line" | sed -E 's/^## (N[0-9]+) — .*/\1/')"
      ;;
    "- Parent: "*)
      if [ -n "$node_id" ]; then
        p="$(printf '%s' "$line" | sed -E 's/^- Parent: (none|N[0-9]+).*/\1/')"
        PARENT_OF["$node_id"]="$p"
      fi
      ;;
  esac
done < "$FIXTURE_BODY"

max_depth=0
deepest=""
for id in "${!PARENT_OF[@]}"; do
  depth=0
  cur="$id"
  visited=" $id "
  while :; do
    p="${PARENT_OF[$cur]:-none}"
    if [ "$p" = "none" ] || [ -z "$p" ]; then break; fi
    case "$visited" in *" $p "*) break ;; esac  # cycle guard
    visited="$visited$p "
    depth=$((depth + 1))
    cur="$p"
  done
  if [ "$depth" -gt "$max_depth" ]; then
    max_depth=$depth
    deepest="$id"
  fi
done

if [ "$max_depth" -ge 2 ]; then
  pass "fixture: a Parent chain reaches >= 2 levels deep (grandchild: $deepest at depth $max_depth)"
else
  fail "fixture: no Parent chain reaches 2 levels deep (deepest found: $max_depth)"
fi

# --- Clause: a fenced block containing a literal </script> line -------------
# Confirm the </script> line falls strictly between two fence markers (```),
# not merely present somewhere in the file.
script_line_no="$(grep -nF '</script>' "$FIXTURE_BODY" | head -1 | cut -d: -f1)"
if [ -n "$script_line_no" ]; then
  fences_before="$(sed -n "1,${script_line_no}p" "$FIXTURE_BODY" | grep -c '^```')"
  if [ $(( fences_before % 2 )) -eq 1 ]; then
    pass "fixture: a fenced code block contains a literal </script> line"
  else
    fail "fixture: a </script> line exists but is not inside an open fenced code block"
  fi
else
  fail "fixture: no fenced block contains a literal </script> line"
fi

# --- Clause: >= 1 inline @TAG: chip ------------------------------------------
if grep -qE '@(COMMENT|QUESTION|CONCERN|APPROVE|EVIDENCE):' "$FIXTURE_BODY"; then
  pass "fixture: at least one inline @TAG: chip"
else
  fail "fixture: no inline @TAG: chip found"
fi

# --- Summary -----------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'workgraph-render.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'workgraph-render.test.sh: all assertions passed\n'
