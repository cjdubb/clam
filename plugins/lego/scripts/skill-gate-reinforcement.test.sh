#!/bin/bash
# Structural/anchor test for Contract: B02 skill-gate-reinforcement, which
# inserts one reinforcement paragraph/sentence at each of 4 locations across
# 3 skill files (plan/SKILL.md Step 0 and Step 3, scaffold/SKILL.md Step 3,
# dispatch/SKILL.md's escalation loop), each replacing a
# "NotImplemented: B02 ..." placeholder that currently sits directly after
# that location's own "<!-- Contract: B02 ... -->" docblock.
#
# These are documentation files, not executable code, so the tests here are:
#   - "Marker gone": each location's exact NotImplemented placeholder string
#     no longer appears anywhere in its file; no "NotImplemented: B02" token
#     survives in any of the 3 files (cross-cutting).
#   - "Zone content": a `zone` helper isolates exactly the text inserted at
#     each location — everything after that location's own docblock (the
#     "-->" line that closes the "Contract: B02 ..." comment unique to that
#     location) up to (not including) the next stable anchor line/phrase
#     that must survive the edit unchanged. This deliberately excludes the
#     docblock's own prose, which already contains much of the contract's
#     vocabulary, so a check against the docblock itself can never make a
#     zone check pass by accident.
#   - "Required tokens": literal (fixed-string) tokens that a genuine
#     reinforcement satisfying the contract's Invariants must contain,
#     checked only within the relevant zone.
#   - "Invariants": pre-existing headings/frontmatter survive unchanged.
# This file does not test prose semantics beyond tokens/zones/headings —
# meaning (e.g. "references rather than restates") is verified by the
# orchestrator at acceptance.
#
# These tests MUST fail against the current stubs (which have NotImplemented
# markers and therefore empty zones). They should pass once the implementer
# replaces each placeholder with a reinforcement that covers its contract.
#
# Run: bash plugins/lego/scripts/skill-gate-reinforcement.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="$SCRIPT_DIR/../skills/plan/SKILL.md"
SCAFFOLD="$SCRIPT_DIR/../skills/scaffold/SKILL.md"
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

# Isolates the text inserted at one reinforcement location: everything
# strictly after the "-->" line that closes the "<!-- Contract: B02 ... -->"
# docblock uniquely identified by `start` (a literal substring found on the
# docblock's opening line), up to (not including) the first later line
# containing the literal substring `end` (a stable anchor that must survive
# the edit unchanged). Excludes the docblock itself, so the docblock's own
# prose can never satisfy a zone token check.
zone() { # file start end
  awk -v s="$2" -v e="$3" '
    seen == 0 { if (index($0, s) > 0) seen = 1; next }
    seen == 1 && past == 0 { if ($0 == "-->") { past = 1 }; next }
    past == 1 { if (index($0, e) > 0) exit; print; next }
  ' "$1"
}

for f in "$PLAN" "$SCAFFOLD" "$DISPATCH"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL  SKILL.md not found at $f"
    exit 1
  fi
done

PLAN_RAW=$(cat "$PLAN")
SCAFFOLD_RAW=$(cat "$SCAFFOLD")
DISPATCH_RAW=$(cat "$DISPATCH")

# --- Zone isolation --------------------------------------------------------
PLAN_STEP0_ZONE="$(zone "$PLAN" \
  'Contract: B02 skill-gate-reinforcement (plan Step 0)' \
  "This gate is an instance of the workflow's central rule")"
PLAN_STEP3_ZONE="$(zone "$PLAN" \
  'Contract: B02 skill-gate-reinforcement (plan Step 3)' \
  'Decomposition happens HERE and only here.')"
SCAFFOLD_STEP3_ZONE="$(zone "$SCAFFOLD" \
  'Contract: B02 skill-gate-reinforcement (scaffold Step 3)' \
  "Commit the scaffold (with the engineer's consent) as a phase boundary.")"
DISPATCH_ESCALATION_ZONE="$(zone "$DISPATCH" \
  'Contract: B02 skill-gate-reinforcement (dispatch escalation)' \
  '**A test is wrong**')"

# --- 1/2/3. plan/SKILL.md Step 0 ------------------------------------------
check "plan Step 0 placeholder is gone" \
  "$(has_f "$PLAN_RAW" '**NotImplemented: B02 — skill-gate-reinforcement (plan Step 0).**')" \
  "no"
check "plan Step 0 zone is non-empty (reinforcement text present)" \
  "$([[ -n "$(tr -d '[:space:]' <<<"$PLAN_STEP0_ZONE")" ]] && echo yes || echo no)" \
  "yes"
check "plan Step 0 zone references the standing rule" \
  "$(has_f "$PLAN_STEP0_ZONE" 'standing rule')" "yes"
check "plan Step 0 zone names a prohibited behavior (exploration/discovery)" \
  "$(has_any "$PLAN_STEP0_ZONE" 'exploration' 'discovery')" "yes"

# --- 4/5. plan/SKILL.md Step 3 ---------------------------------------------
check "plan Step 3 placeholder is gone" \
  "$(has_f "$PLAN_RAW" '**NotImplemented: B02 — skill-gate-reinforcement (plan Step 3).**')" \
  "no"
check "plan Step 3 zone is non-empty (reinforcement text present)" \
  "$([[ -n "$(tr -d '[:space:]' <<<"$PLAN_STEP3_ZONE")" ]] && echo yes || echo no)" \
  "yes"
check "plan Step 3 zone references the standing rule" \
  "$(has_f "$PLAN_STEP3_ZONE" 'standing rule')" "yes"
check "plan Step 3 zone covers all decomposition questions answered before Step 4" \
  "$(has_any "$PLAN_STEP3_ZONE" 'Step 4' 'answered' 'answers')" "yes"

# --- 6/7. scaffold/SKILL.md Step 3 -----------------------------------------
check "scaffold Step 3 placeholder is gone" \
  "$(has_f "$SCAFFOLD_RAW" '**NotImplemented: B02 — skill-gate-reinforcement (scaffold Step 3).**')" \
  "no"
check "scaffold Step 3 zone is non-empty (reinforcement text present)" \
  "$([[ -n "$(tr -d '[:space:]' <<<"$SCAFFOLD_STEP3_ZONE")" ]] && echo yes || echo no)" \
  "yes"
check "scaffold Step 3 zone references the standing rule" \
  "$(has_f "$SCAFFOLD_STEP3_ZONE" 'standing rule')" "yes"
check "scaffold Step 3 zone covers questions resolved with the engineer before committing" \
  "$(has_any "$SCAFFOLD_STEP3_ZONE" 'resolved' 'engineer')" "yes"

# --- 8/9. dispatch/SKILL.md escalation loop --------------------------------
check "dispatch escalation placeholder is gone" \
  "$(has_f "$DISPATCH_RAW" '**NotImplemented: B02 — skill-gate-reinforcement (dispatch escalation).**')" \
  "no"
check "dispatch escalation zone is non-empty (reinforcement text present)" \
  "$([[ -n "$(tr -d '[:space:]' <<<"$DISPATCH_ESCALATION_ZONE")" ]] && echo yes || echo no)" \
  "yes"
check "dispatch escalation zone references the standing rule" \
  "$(has_f "$DISPATCH_ESCALATION_ZONE" 'standing rule')" "yes"
check "dispatch escalation zone covers waiting for the engineer's full decision" \
  "$(has_any "$DISPATCH_ESCALATION_ZONE" 'decision' 're-dispatch' 're-scaffold')" "yes"

# --- 10. Cross-cutting: no NotImplemented: B02 marker survives anywhere ----
check "no 'NotImplemented: B02' marker remains in plan/SKILL.md" \
  "$(has_f "$PLAN_RAW" 'NotImplemented: B02')" "no"
check "no 'NotImplemented: B02' marker remains in scaffold/SKILL.md" \
  "$(has_f "$SCAFFOLD_RAW" 'NotImplemented: B02')" "no"
check "no 'NotImplemented: B02' marker remains in dispatch/SKILL.md" \
  "$(has_f "$DISPATCH_RAW" 'NotImplemented: B02')" "no"

# --- 11. Invariants: existing headings/frontmatter survive unchanged ------
plan_frontmatter=$(awk '/^---$/{n++; next} n==1' "$PLAN")
plan_name=$(printf '%s\n' "$plan_frontmatter" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
check "plan frontmatter name is 'plan'" "$plan_name" "plan"

scaffold_frontmatter=$(awk '/^---$/{n++; next} n==1' "$SCAFFOLD")
scaffold_name=$(printf '%s\n' "$scaffold_frontmatter" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
check "scaffold frontmatter name is 'scaffold'" "$scaffold_name" "scaffold"

dispatch_frontmatter=$(awk '/^---$/{n++; next} n==1' "$DISPATCH")
dispatch_name=$(printf '%s\n' "$dispatch_frontmatter" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
check "dispatch frontmatter name is 'dispatch'" "$dispatch_name" "dispatch"

for h in "## Step 0: Establish the deliverable — a hard gate" \
         "## Step 1: Ensure the repo interface exists" \
         "## Step 2: Brownfield discovery (skip only in an empty repo)" \
         "## Step 3: Decompose with the engineer" \
         "## Step 4: Write the artifacts" \
         "## Step 5: Approval gate"; do
  check "plan heading survives: $h" "$(has_f "$PLAN_RAW" "$h")" "yes"
done

for h in "## Step 1: Write the stubs" \
         "## Step 2: Run the scaffold gate" \
         "## Step 3: Update state and checkpoint"; do
  check "scaffold heading survives: $h" "$(has_f "$SCAFFOLD_RAW" "$h")" "yes"
done

for h in "## Vocabulary" "## Preconditions" "## The per-unit pipeline" \
         "## Escalation loop" "## Done"; do
  check "dispatch heading survives: $h" "$(has_f "$DISPATCH_RAW" "$h")" "yes"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
