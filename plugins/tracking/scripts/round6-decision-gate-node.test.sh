#!/bin/bash
# Anchor pins for the round-6 fix (F32, tracking share): a Waiting For
# Decision park writes a gate node for the decision file in the same edit,
# and summons presentation is graph-first — the graph opened at the linking
# node, and opened last when a stop opens more than one surface.
# Token checks over the emitted session context, not prose semantics.
# Run: bash plugins/tracking/scripts/round6-decision-gate-node.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="$(bash "$SCRIPT_DIR/session-context.sh" 2>/dev/null)"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}
# Wrap-tolerant fixed-string presence over the emitted context. The context
# arrives as a JSON string whose line breaks are literal \n escape
# sequences, so both real newlines and the two-character \n are collapsed
# to spaces before matching.
has_fn() { # literal
  if tr '\n' ' ' <<<"${CONTEXT//\\n/ }" | tr -s ' ' | grep -qF -- "$1"; then echo yes; else echo no; fi
}

check "decision file gains a gate node in the same edit" \
  "$(has_fn 'the same edit that writes the decision file adds a gate node')" "yes"
check "gate node parents under the Focus node" \
  "$(has_fn 'the current Focus node')" "yes"
check "gate node links the decision file from Notes" \
  "$(has_fn 'relative link to the decision file')" "yes"
check "gate node resolves with the decision" \
  "$(has_fn 'in the same edit that records the resolution')" "yes"
check "missing graph is tolerated" \
  "$(has_fn 'no graph, no gate node, no error')" "yes"
check "park presentation opens the graph at the gate node" \
  "$(has_fn 'open the *graph* at that node')" "yes"
check "summons presentation is graph-first for node-linked documents" \
  "$(has_fn 'present the graph opened at that node instead of the bare document')" "yes"
check "graph opens last when a stop opens both surfaces" \
  "$(has_fn 'open the graph last')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
