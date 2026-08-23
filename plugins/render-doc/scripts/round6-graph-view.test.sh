#!/bin/bash
# Anchor pins for the round-6 fix batch (F34, F35, F36b) in the graph view:
#   - F35: cluster-aware layout — sibling containment boxes laid out as hard
#     disjoint constraints, with the flat positions kept as the degrade path.
#   - F34: park banner — sibling tracking document's Status block read over
#     /raw, shown only for summoning states, fail-silent.
#   - F36b: worker badge — in-progress nodes whose Notes carry
#     "Worker: <name>" label the holder; the released marker shows nothing.
# Token checks only; the rendered behavior is verified by screenshot at
# acceptance. Run: bash plugins/render-doc/scripts/round6-graph-view.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../assets/template.html"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}
has_fn() { # literal (wrap-tolerant)
  if tr '\n' ' ' <"$TEMPLATE" | tr -s ' ' | grep -qF -- "$1"; then echo yes; else echo no; fi
}

# F35: cluster-aware layout.
check "F35: cluster layout function exists" "$(has_fn 'function layoutSiblings(ids)')" "yes"
check "F35: dep edges aggregate to the sibling level" "$(has_fn 'descOwner')" "yes"
check "F35: both rank directions tried for aspect" "$(has_fn 'var tb = runDir("TB")')" "yes"
check "F35: flat positions kept as the degrade path" "$(has_fn 'flat positions remain')" "yes"
check "F35: recursive sizing bottoms out on measured leaf dims" "$(has_fn 'function computeSize(id)')" "yes"

# F34: park banner.
check "F34: banner element present" "$(has_fn 'id="wg-park-banner"')" "yes"
check "F34: banner reads the sibling tracking document" "$(has_fn '"/TODO.md"')" "yes"
check "F34: banner gated to summoning states" "$(has_fn '^(Blocked|Waiting For Decision)$')" "yes"
check "F34: banner gated to work-graph documents" "$(has_fn 'docType !== "work-graph"')" "yes"
check "F34: fetch failure hides the banner" "$(has_fn 'el.classList.remove("show")')" "yes"

# F36b: worker badge.
check "F36b: worker helper exists" "$(has_fn 'function wgNodeWorker(node)')" "yes"
check "F36b: released marker suppresses the badge" "$(has_fn '/^released$/i')" "yes"
check "F36b: badge only on in-progress nodes" "$(has_fn 'node.statusKind !== "in-progress"')" "yes"
check "F36b: badge joins the node label" "$(has_fn '"\n⚙ " + worker')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
