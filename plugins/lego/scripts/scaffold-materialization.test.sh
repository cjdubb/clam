#!/bin/bash
# Structural/anchor test for skills/scaffold/SKILL.md against
# "Contract: B02 scaffold materialization", whose docblock lives inline in
# SKILL.md as an HTML comment directly above "## Step 1".
#
# B02 reframes the skill intro and Step 1 as MATERIALIZATION of interfaces
# already approved at plan time: stubs are transcribed from the plan's
# Interface drafts section, docblocks are finalized (not designed) from the
# approved drafts, and a discovery that invalidates an approved signature is
# a named return-to-plan event rather than a silent scaffold-time redesign.
#
# As in scaffold-skill.test.sh, HTML comments are stripped from the whole
# file BEFORE any section is extracted, so the B02 contract comment — which
# quotes nearly every anchor asserted below — can never satisfy a check by
# matching itself. Only prose written into the intro/Step 1 counts.
#
# These MUST fail against the pre-B02 SKILL.md (old Step 1 prose + the
# still-present contract comment) and pass once the reframe is written.
# Semantics beyond tokens/ordering are verified by the orchestrator at
# acceptance.
# Run: bash plugins/lego/scripts/scaffold-materialization.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/scaffold/SKILL.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Case-insensitive fixed-string presence: yes when ANY literal appears.
# Used where the contract fixes the fact but not the wording, never to
# weaken a clause.
has_any_i() { # content literal...
  local content="$1"; shift
  local lit
  for lit in "$@"; do
    if grep -qiF -- "$lit" <<<"$content"; then echo yes; return; fi
  done
  echo no
}

first_line_in() { # content literal
  grep -nF -- "$2" <<<"$1" | head -1 | cut -d: -f1
}

check_before() { # label line_a line_b
  if [[ -z "$2" || -z "$3" ]]; then
    echo "FAIL  $1 -> anchor not found (line_a='$2' line_b='$3')"; FAILED=1
  elif (( $2 < $3 )); then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> line $2 does not precede line $3"; FAILED=1
  fi
}

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi

RAW=$(cat "$SKILL")
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")

# Intro: everything from the "# Lego Scaffolding" title up to "## Step 1".
INTRO=$(awk '
  index($0, "# Lego Scaffolding") == 1 { capture=1; print; next }
  capture && index($0, "## Step 1") == 1 { exit }
  capture { print }
' <<<"$STRIPPED")

# Step 1 body: its heading up to the next top-level "## " heading.
STEP1=$(awk '
  index($0, "## Step 1") == 1 { capture=1; print; next }
  capture && index($0, "## ") == 1 { exit }
  capture { print }
' <<<"$STRIPPED")

# The reframe may land in the intro or in Step 1; several clauses are
# satisfied by either, so check the two together where the contract does
# not pin the location.
INTRO_STEP1="$INTRO
$STEP1"

# --- Behavior: Step 1 transcribes the plan's approved Interface drafts ----
check "step1: the plan's Interface drafts section is named" \
  "$(has_f "$STEP1" 'Interface drafts')" "yes"
check "step1: stubs are transcribed from the approved drafts" \
  "$(has_any_i "$STEP1" 'transcrib')" "yes"
check "step1: the drafts are the APPROVED ones (plan-time approval)" \
  "$(has_any_i "$STEP1" 'approved draft' 'approved interface' 'the approved')" "yes"
check "intro: the skill is framed as materializing approved interfaces" \
  "$(has_any_i "$INTRO_STEP1" 'materializ' 'materialis')" "yes"

# --- Behavior: docblocks are FINALIZED from the drafts; precision added,
# new design not -------------------------------------------------------------
check "step1: docblocks are finalized from the approved draft" \
  "$(has_any_i "$STEP1" 'finaliz' 'finalis')" "yes"
check "step1: precision may be added" \
  "$(has_any_i "$STEP1" 'precision')" "yes"
check "step1: new design may not be added here" \
  "$(has_any_i "$STEP1" 'new design' 'not design' 'no new design')" "yes"

# --- Behavior: a signature-invalidating discovery is a named
# return-to-plan event, recorded in the plan Changelog, never silent -------
check "step1: a discovery that invalidates an approved signature is addressed" \
  "$(has_any_i "$STEP1" 'invalidat')" "yes"
check "step1: the response is a return to the planning skill" \
  "$(has_f "$STEP1" '/lego:plan')" "yes"
check "step1: the return-to-plan event is recorded in the plan Changelog" \
  "$(has_f "$STEP1" 'Changelog')" "yes"
check "step1: it is never silently redesigned at scaffold time" \
  "$(has_any_i "$STEP1" 'silently' 'silent')" "yes"

# --- Inputs: an approved plan carrying one draft per block; blocks at
# Status: Planned -------------------------------------------------------------
check "inputs: one draft per block is stated" \
  "$(has_any_i "$INTRO_STEP1" 'one draft per block' 'a draft per block' 'one per block')" "yes"
check "inputs: the Status: Planned precondition survives" \
  "$(has_f "$INTRO_STEP1" 'Status: Planned')" "yes"

# --- Errors: deviating from an approved draft with no Changelog entry is a
# scaffold defect ------------------------------------------------------------
check "errors: deviation from the approved draft is named" \
  "$(has_any_i "$STEP1" 'deviat')" "yes"
check "errors: an undocumented deviation is a scaffold defect" \
  "$(has_any_i "$STEP1" 'scaffold defect')" "yes"

# --- Edge case: a plan with no Interface drafts section (older plan) ------
check "edge: the no-drafts-section fallback is addressed" \
  "$(has_any_i "$STEP1" 'fall back' 'fallback' 'falls back')" "yes"
check "edge: the fallback authors docblocks fresh" \
  "$(has_any_i "$STEP1" 'fresh')" "yes"
check "edge: the fallback is itself noted in the plan Changelog" \
  "$(has_any_i "$STEP1" 'noting the fallback' 'note the fallback' 'noted in the plan Changelog' 'fallback in the plan Changelog')" "yes"

# --- Edge case: prose blocks transcribe the approved outline as the
# document skeleton ----------------------------------------------------------
check "edge: prose blocks are addressed in the materialization prose" \
  "$(has_any_i "$STEP1" 'prose block')" "yes"
check "edge: the approved outline is named for prose blocks" \
  "$(has_any_i "$STEP1" 'outline')" "yes"
check "edge: the outline becomes the document skeleton" \
  "$(has_any_i "$STEP1" 'skeleton')" "yes"

# --- Invariant: docblock authority is unchanged ---------------------------
check "invariant: the docblock remains the authoritative contract" \
  "$(has_any_i "$STEP1" 'authoritative contract')" "yes"
check "invariant: a-type-alone-is-not-a-contract principle survives Step 1" \
  "$(has_f "$STEP1" 'a type signature alone does not specify behavior')" "yes"
check "invariant: runtime-present, deliberately unimplemented stubs survive" \
  "$(has_f "$STEP1" 'Runtime-present, deliberately unimplemented')" "yes"

# --- Invariant: the downstream gate structure is present and unchanged ----
check "invariant: Step 2 gate heading present" \
  "$(has_f "$STRIPPED" '## Step 2: Run the scaffold gate')" "yes"
check "invariant: Step 2a review-gating heading present" \
  "$(has_f "$STRIPPED" '### Step 2a: Blocks with no red/green cycle')" "yes"
check "invariant: Step 3 phase-boundary commit heading present" \
  "$(has_f "$STRIPPED" '## Step 3: Update state and checkpoint')" "yes"
check "invariant: rung 0 sizing lint still opens the gate" \
  "$(has_any_i "$STRIPPED" 'rung 0' 'rung zero')" "yes"

S1_L=$(first_line_in "$STRIPPED" '## Step 1')
S2_L=$(first_line_in "$STRIPPED" '## Step 2: Run the scaffold gate')
RUNG0_L=$(first_line_in "$STRIPPED" 'blocks-lint.sh')
RUNG1_L=$(first_line_in "$STRIPPED" '1. `typecheck`')
S2A_L=$(first_line_in "$STRIPPED" '### Step 2a: Blocks with no red/green cycle')
S3_L=$(first_line_in "$STRIPPED" '## Step 3: Update state and checkpoint')

check_before "invariant: Step 1 precedes Step 2" "$S1_L" "$S2_L"
check_before "invariant: rung 0 precedes the typecheck rung list" "$RUNG0_L" "$RUNG1_L"
check_before "invariant: the rung list precedes Step 2a" "$RUNG1_L" "$S2A_L"
check_before "invariant: Step 2a precedes Step 3" "$S2A_L" "$S3_L"

# --- Invariant: the removable B02 contract comment is deleted -------------
check "B02 contract comment is gone from SKILL.md" \
  "$(has_f "$RAW" 'Contract: B02 scaffold materialization')" "no"
check "B02 'remove at acceptance' marker is gone from SKILL.md" \
  "$(has_f "$RAW" 'B02 scaffold materialization (remove at acceptance)')" "no"

# --- Invariant: the new prose names no other plugin (lego is a leaf) ------
# Bare words are deliberately excluded: "landing strategy" is lego's own
# vocabulary and `build` is a config command name. The "<name> plugin"
# phrasings are COMPOSED rather than spelled out, so this file does not
# itself become a cross-plugin English reference.
FOREIGN_NAMES=(landing tracking worktrees build)
FOREIGN_REFS=(
  '/landing:' '/tracking:' '/build:'
  'landing@' 'tracking@' 'build@' 'worktrees@'
  'plugins/landing' 'plugins/tracking' 'plugins/build' 'plugins/worktrees'
  'newtree' 'rmtree'
)
for name in "${FOREIGN_NAMES[@]}"; do
  FOREIGN_REFS+=("$name plugin")
done
for ref in "${FOREIGN_REFS[@]}"; do
  check "step1 layering: no reference to '$ref'" \
    "$(has_f "$INTRO_STEP1" "$ref")" "no"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
