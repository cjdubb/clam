#!/bin/bash
# Structural/anchor test for skills/scaffold/SKILL.md against Contract:
# 001-B03 untestable-block-gate. Unlike other lego contracts, this one has
# no separate .local/contracts file — its docblock is embedded inline in
# SKILL.md itself, as an HTML comment directly under the "### Step 2a"
# heading it describes. This skill is a documentation block, not executable
# code, so the tests here are:
#   - "Heading presence and ordering": "### Step 2a" exists and sits inside
#     Step 2 (after "## Step 2:", before "## Step 3:").
#   - "Section tokens": each contract-required phrase must appear verbatim
#     (fixed-string grep) WITHIN the Step 2a section's own prose — not
#     merely anywhere in the file. HTML comments are stripped from the
#     whole file before the section is extracted (same technique as
#     dispatch-skill.test.sh's pipe-safety checks), so the contract
#     docblock's own vocabulary — which sits inside this same section —
#     can never satisfy these checks by matching itself; only prose written
#     to replace the NotImplemented placeholder counts.
#   - "Marker": the NotImplemented placeholder must be gone.
# These MUST fail against the current (pre-B03) SKILL.md: the Step 2a
# section is still "NotImplemented: 001-B03 — untestable-block-gate.", so
# every token/marker check below fails for the right reason (an assertion
# failure, not a syntax error). They MUST pass once a real edit replaces
# that placeholder with prose satisfying the contract's clauses.
# This file does not test prose semantics beyond tokens/headings/order —
# meaning is verified by the orchestrator at acceptance.
# Run: bash plugins/lego/scripts/scaffold-skill.test.sh   (exits non-zero on failure)

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

# Fixed-string (literal) presence check, case-sensitive. `--` guards literals
# that start with a dash from being parsed as grep options.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# First line number (1-indexed) at which a literal string appears at the
# start of a line, or empty if not found.
first_heading_line() { # literal
  grep -nF -- "$1" "$SKILL" | head -1 | cut -d: -f1
}

check_after() { # label line_a line_b -- assert a follows b
  if [[ -z "$2" || -z "$3" ]]; then
    echo "FAIL  $1 -> heading not found (line_a='$2' line_b='$3')"; FAILED=1
  elif (( $2 > $3 )); then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> line $2 does not follow line $3"; FAILED=1
  fi
}

check_before() { # label line_a line_b -- assert a precedes b
  if [[ -z "$2" || -z "$3" ]]; then
    echo "FAIL  $1 -> heading not found (line_a='$2' line_b='$3')"; FAILED=1
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

# --- Clause 1: heading exists, ordered inside Step 2 ----------------------
# (after "## Step 2:", before "## Step 3:")
check "heading exists: ### Step 2a: Blocks with no red/green cycle" \
  "$(has_f "$RAW" '### Step 2a: Blocks with no red/green cycle')" "yes"

STEP2_LINE=$(first_heading_line "## Step 2: Run the scaffold gate")
STEP2A_LINE=$(first_heading_line "### Step 2a: Blocks with no red/green cycle")
STEP3_LINE=$(first_heading_line "## Step 3: Update state and checkpoint")

check_after "Step 2a follows Step 2" "$STEP2A_LINE" "$STEP2_LINE"
check_before "Step 2a precedes Step 3" "$STEP2A_LINE" "$STEP3_LINE"

# --- Section scoping --------------------------------------------------------
# Strip HTML comments from the whole file first (removing the contract
# docblock's own text everywhere, including from the Step 2a section it
# sits inside), then extract the Step 2a section: from its heading up to,
# but not including, the next top-level "## " heading.
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")
SECTION_2A=$(awk '
  index($0, "### Step 2a: Blocks with no red/green cycle") == 1 { capture=1; print; next }
  capture && index($0, "## ") == 1 { exit }
  capture { print }
' <<<"$STRIPPED")

# --- Clause 2: acceptance gate = orchestrator verification against every
# contract clause AND explicit engineer acceptance (both required) --------
check "2a: acceptance gate names orchestrator verification against every contract clause" \
  "$(has_f "$SECTION_2A" 'against every contract clause')" "yes"
check "2a: engineer acceptance required in addition to orchestrator verification" \
  "$(has_f "$SECTION_2A" 'orchestrator verification alone does not accept')" "yes"

# --- Clause 3: a skipped test wave is always recorded with its reason,
# never silent ---------------------------------------------------------------
check "2a: skipped test wave is recorded with its reason" \
  "$(has_f "$SECTION_2A" 'recorded with its reason')" "yes"
check "2a: the skip is never silent" \
  "$(has_f "$SECTION_2A" 'never silent')" "yes"

# --- Clause 4: review-gating decided at scaffold time by the orchestrator,
# recorded on the block, never improvised at dispatch -----------------------
check "2a: review-gating decided at scaffold time" \
  "$(has_f "$SECTION_2A" 'decided at scaffold time')" "yes"
check "2a: review-gating recorded on the block" \
  "$(has_f "$SECTION_2A" 'recorded on the block')" "yes"
check "2a: review-gating is never a dispatch-time improvisation" \
  "$(has_f "$SECTION_2A" 'dispatch-time improvisation')" "yes"

# --- Clause 5: the bar is "no clause is executably assertable"; structural
# and anchor assertions count as executable, so a prose file with anchors
# is not review-gated --------------------------------------------------------
check "2a: bar is 'no clause is executably assertable'" \
  "$(has_f "$SECTION_2A" 'no clause is executably assertable')" "yes"
check "2a: structural/anchor assertions count as executable" \
  "$(has_f "$SECTION_2A" 'and anchor assertions count as executable')" "yes"
check "2a: prose file with structural anchors is not review-gated" \
  "$(has_f "$SECTION_2A" 'not review-gated')" "yes"

# --- Clause 6: a partially-testable block takes the normal test wave -------
check "2a: partial testability takes the normal test wave" \
  "$(has_f "$SECTION_2A" 'testability means the normal wave runs and covers what it can')" "yes"

# --- Edge case: engineer-owned review-gated block takes the SAME gate; the
# engineer cannot accept their own block unilaterally, the orchestrator
# still verifies ------------------------------------------------------------
check "2a: engineer-owned review-gated block is named" \
  "$(has_f "$SECTION_2A" 'engineer-owned')" "yes"
check "2a: engineer cannot accept their own review-gated block unilaterally" \
  "$(has_f "$SECTION_2A" 'cannot accept their own')" "yes"

# --- Edge case: README-style content with no assertable structure IS
# review-gated (the contrast to the "not review-gated" prose-with-anchors
# case pinned in Clause 5 above) ---------------------------------------------
check "2a: content with no assertable structure is review-gated" \
  "$(has_f "$SECTION_2A" 'no assertable structure')" "yes"

# --- Clause 7: no NotImplemented: 001-B03 marker survives ------------------
check "2a: NotImplemented: 001-B03 marker is gone" \
  "$(has_f "$RAW" 'NotImplemented: 001-B03')" "no"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
