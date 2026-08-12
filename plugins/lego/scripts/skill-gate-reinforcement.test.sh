#!/bin/bash
# Verifies per-gate reinforcement paragraphs in the plan and
# dispatch skill files — each transition point requires confirming all
# questions are answered before proceeding.
#
# Run: bash plugins/lego/scripts/skill-gate-reinforcement.test.sh
#      (exits non-zero on failure)

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

# Fixed-string (literal) presence check, case-sensitive. `--` guards literals
# that start with a dash from being parsed as grep options.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# True (yes) if ANY of the given literals is present in content.
has_any() { # content literal...
  local content="$1"; shift
  local lit
  for lit in "$@"; do
    if grep -qF -- "$lit" <<<"$content"; then echo yes; return; fi
  done
  echo no
}

# Isolates text between two stable anchors: everything strictly after the
# first line containing `start` up to (not including) the first later line
# containing `end`. Both anchors are pre-existing text that must survive
# the edit unchanged.
zone() { # file start end
  awk -v s="$2" -v e="$3" '
    past == 0 { if (index($0, s) > 0) { past = 1 }; next }
    past == 1 { if (index($0, e) > 0) exit; print }
  ' "$1"
}

for f in "$PLAN" "$DISPATCH"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL  SKILL.md not found at $f"
    exit 1
  fi
done

PLAN_RAW=$(cat "$PLAN")
DISPATCH_RAW=$(cat "$DISPATCH")

# --- Zone isolation --------------------------------------------------------
# Each zone is bounded by the stable text immediately before and after the
# reinforcement paragraph. Start anchors are the last line of the preceding
# block; end anchors are the first line of the following block.
PLAN_STEP0_ZONE="$(zone "$PLAN" \
  'document opens with.' \
  "This gate is an instance of the workflow's central rule")"
PLAN_STEP3_ZONE="$(zone "$PLAN" \
  'may be grouped to share one PR to master/main.' \
  'Decomposition happens HERE and only here.')"
SCAFFOLD_STEP3_ZONE="$(zone "$PLAN" \
  'as a decomposition defect rather than being resolved silently here.' \
  "Commit the scaffold (with the engineer's consent) as a phase boundary.")"
DISPATCH_ESCALATION_ZONE="$(zone "$DISPATCH" \
  're-verified.' \
  '**A test is wrong**')"

# --- 1/2/3. plan/SKILL.md Step 0 ------------------------------------------
check "plan Step 0 placeholder is gone" \
  "$(has_f "$PLAN_RAW" '**NotImplemented: B02 — skill-gate-reinforcement (plan Step 0).**')" \
  "no"
check "plan Step 0 zone is non-empty (reinforcement text present)" \
  "$([[ -n "$(tr -d '[:space:]' <<<"$PLAN_STEP0_ZONE")" ]] && echo yes || echo no)" \
  "yes"
check "plan Step 0 zone requires verifying questions answered" \
  "$(has_any "$PLAN_STEP0_ZONE" 'verify' 'every question')" "yes"
check "plan Step 0 zone names a prohibited behavior (exploration/discovery)" \
  "$(has_any "$PLAN_STEP0_ZONE" 'exploration' 'discovery')" "yes"

# --- 4/5. plan/SKILL.md Step 3 ---------------------------------------------
check "plan Step 3 placeholder is gone" \
  "$(has_f "$PLAN_RAW" '**NotImplemented: B02 — skill-gate-reinforcement (plan Step 3).**')" \
  "no"
check "plan Step 3 zone is non-empty (reinforcement text present)" \
  "$([[ -n "$(tr -d '[:space:]' <<<"$PLAN_STEP3_ZONE")" ]] && echo yes || echo no)" \
  "yes"
check "plan Step 3 zone requires confirming questions answered" \
  "$(has_any "$PLAN_STEP3_ZONE" 'confirm' 'answered')" "yes"
check "plan Step 3 zone covers all decomposition questions answered before Step 4" \
  "$(has_any "$PLAN_STEP3_ZONE" 'Step 4' 'answered' 'answers')" "yes"

# --- 6/7. plan/SKILL.md checkpoint (Step 8) --------------------------------
check "checkpoint placeholder is gone" \
  "$(has_f "$PLAN_RAW" '**NotImplemented: B02 — skill-gate-reinforcement (scaffold Step 3).**')" \
  "no"
check "checkpoint zone is non-empty (reinforcement text present)" \
  "$([[ -n "$(tr -d '[:space:]' <<<"$SCAFFOLD_STEP3_ZONE")" ]] && echo yes || echo no)" \
  "yes"
check "checkpoint zone requires verifying questions resolved" \
  "$(has_any "$SCAFFOLD_STEP3_ZONE" 'verify' 'resolved')" "yes"
check "checkpoint zone covers questions resolved with the engineer before committing" \
  "$(has_any "$SCAFFOLD_STEP3_ZONE" 'resolved' 'engineer')" "yes"

# --- 8/9. dispatch/SKILL.md escalation loop --------------------------------
check "dispatch escalation placeholder is gone" \
  "$(has_f "$DISPATCH_RAW" '**NotImplemented: B02 — skill-gate-reinforcement (dispatch escalation).**')" \
  "no"
check "dispatch escalation zone is non-empty (reinforcement text present)" \
  "$([[ -n "$(tr -d '[:space:]' <<<"$DISPATCH_ESCALATION_ZONE")" ]] && echo yes || echo no)" \
  "yes"
check "dispatch escalation zone requires waiting for full decision" \
  "$(has_any "$DISPATCH_ESCALATION_ZONE" 'Wait' 'decision')" "yes"
check "dispatch escalation zone covers waiting for the engineer's full decision" \
  "$(has_any "$DISPATCH_ESCALATION_ZONE" 'decision' 're-dispatch' 're-scaffold')" "yes"

# --- 10. Cross-cutting: no NotImplemented: B02 marker survives anywhere ----
check "no 'NotImplemented: B02' marker remains in plan/SKILL.md" \
  "$(has_f "$PLAN_RAW" 'NotImplemented: B02')" "no"
check "no 'NotImplemented: B02' marker remains in dispatch/SKILL.md" \
  "$(has_f "$DISPATCH_RAW" 'NotImplemented: B02')" "no"

# --- 11. Invariants: existing headings/frontmatter survive unchanged ------
plan_frontmatter=$(awk '/^---$/{n++; next} n==1' "$PLAN")
plan_name=$(printf '%s\n' "$plan_frontmatter" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
check "plan frontmatter name is 'plan'" "$plan_name" "plan"

dispatch_frontmatter=$(awk '/^---$/{n++; next} n==1' "$DISPATCH")
dispatch_name=$(printf '%s\n' "$dispatch_frontmatter" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
check "dispatch frontmatter name is 'dispatch'" "$dispatch_name" "dispatch"

for h in "## Step 0: Establish the deliverable — a hard gate" \
         "## Step 1: Ensure the repo interface exists" \
         "## Step 2: Brownfield discovery (skip only in an empty repo)" \
         "## Step 3: Decompose with the engineer" \
         "## Step 4: Write the artifacts" \
         "## Step 7: Approval gate"; do
  check "plan heading survives: $h" "$(has_f "$PLAN_RAW" "$h")" "yes"
done

for h in "## Step 5: Write the stubs" \
         "## Step 6: Run the scaffold gate" \
         "## Step 8: Update state and checkpoint"; do
  check "materialization heading survives: $h" "$(has_f "$PLAN_RAW" "$h")" "yes"
done

for h in "## Vocabulary" "## Preconditions" "## The per-unit pipeline" \
         "## Escalation loop" "## Done"; do
  check "dispatch heading survives: $h" "$(has_f "$DISPATCH_RAW" "$h")" "yes"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
