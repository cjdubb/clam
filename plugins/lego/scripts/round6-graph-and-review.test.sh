#!/bin/bash
# Structural/anchor pins for the round-6 fix batch (F32, F36a, F37, F38):
#   - plan standing rules: decision files get gate nodes; the graph is the
#     primary presented surface, opened at the linking node, opened LAST.
#   - plan Step 6: deferral-trigger and value-provenance judgment checks.
#   - dispatch: phase nodes name their Worker; escalation parks take the
#     gate-node rule; test-wave checklist item 4 carries the provenance check.
# Token/anchor checks only — prose semantics are verified at acceptance.
# Run: bash plugins/lego/scripts/round6-graph-and-review.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="$SCRIPT_DIR/../skills/plan/SKILL.md"
DISPATCH="$SCRIPT_DIR/../skills/dispatch/SKILL.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Wrap-tolerant fixed-string presence: collapse newlines so 80-column prose
# wrapping cannot split a multi-word literal across source lines.
has_fn() { # file literal
  if tr '\n' ' ' <"$1" | tr -s ' ' | grep -qF -- "$2"; then echo yes; else echo no; fi
}

# F32: decision gate nodes are a standing rule of the whole engagement.
check "plan: decision-park gate-node standing rule exists" \
  "$(has_fn "$PLAN" 'A decision that parks the engagement gets a gate node')" "yes"
check "plan: the gate node is written in the same edit as the decision file" \
  "$(has_fn "$PLAN" 'the same edit that writes the decision file adds a gate node')" "yes"
check "plan: gate node links the decision file from Notes" \
  "$(has_fn "$PLAN" 'relative link to the decision file')" "yes"
check "plan: gate node resolves in the same edit as the resolution" \
  "$(has_fn "$PLAN" "flips to \`done\` in the same edit that records the resolution")" "yes"

# F32: graph-primary presentation, and the graph lands on top.
check "plan: the graph is the primary presented surface" \
  "$(has_fn "$PLAN" 'The graph is the primary surface')" "yes"
check "plan: a node-linked artifact presents the graph opened at that node" \
  "$(has_fn "$PLAN" 'present the *graph*, opened at that node')" "yes"
check "plan: bare-artifact open reserved for unlinked artifacts" \
  "$(has_fn "$PLAN" 'open the bare artifact only when no node links it')" "yes"
check "plan: graph opened LAST when both surfaces open" \
  "$(has_fn "$PLAN" 'open the graph LAST')" "yes"

# F37: deferral-trigger check at the scaffold gate.
check "plan: deferral triggers must not self-invalidate" \
  "$(has_fn "$PLAN" 'Deferral triggers must not self-invalidate')" "yes"
check "plan: trigger checked against the wave order" \
  "$(has_fn "$PLAN" 'check the named trigger against the wave order')" "yes"
check "plan: schema constraints read as claims about every writer" \
  "$(has_fn "$PLAN" 'a claim about every writer of that table')" "yes"

# F38: provenance check at the scaffold gate.
check "plan: every obliged value has a named source" \
  "$(has_fn "$PLAN" 'Every obliged value has a named source')" "yes"
check "plan: the named source's signature must carry the value" \
  "$(has_fn "$PLAN" "the named source's signature actually carries it")" "yes"

# F36a: dispatch phase nodes name their worker.
check "dispatch: phase-node Notes name the holder" \
  "$(has_fn "$DISPATCH" 'Notes also names the holder')" "yes"
check "dispatch: worker recorded at the dispatch that names the teammate" \
  "$(has_fn "$DISPATCH" 'written in the same edit as the dispatch that names the teammate')" "yes"
check "dispatch: worker line rewritten at release" \
  "$(has_fn "$DISPATCH" 'Worker: released')" "yes"

# F32: dispatch parks take the gate-node rule.
check "dispatch: escalation decision files take the standing gate-node rule" \
  "$(has_fn "$DISPATCH" 'standing gate-node rule')" "yes"
check "dispatch: the park is presented graph-first at the gate node" \
  "$(has_fn "$DISPATCH" 'presented graph-first at that node')" "yes"

# F38: provenance joins the consistency checklist item.
check "dispatch: item 4 names the provenance check" \
  "$(has_fn "$DISPATCH" 'Provenance is the third check of this kind')" "yes"
check "dispatch: provenance requires a reachable source" \
  "$(has_fn "$DISPATCH" 'a source the block can actually reach')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
