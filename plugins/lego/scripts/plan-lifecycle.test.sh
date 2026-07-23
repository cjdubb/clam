#!/bin/bash
# Structural/anchor test for skills/plan/SKILL.md against Contract: B07
# lego-plan-lifecycle. This skill is a documentation block, not executable
# code, so the tests here are:
#   - "Heading presence": Step 0a and Step 5a headings exist.
#   - "Ordering": Step 0a precedes Step 0; Step 5a follows Step 5 (verified
#     by comparing the line numbers of their first occurrences).
#   - "Section tokens": each contract-required literal token must appear
#     verbatim (fixed-string grep) WITHIN the relevant section's own text
#     (from its heading up to, but not including, the next top-level "## "
#     heading) — not merely anywhere in the file.
#   - "Isolation": neither new section references TODO.md (lego never
#     touches tracking's files).
#   - "Invariants": the original Step 0-5 headings all survive unchanged.
# This file does not test prose semantics beyond tokens/headings/order —
# meaning is verified by the orchestrator at acceptance.
# Run: bash plugins/lego/scripts/plan-lifecycle.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/plan/SKILL.md"

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

# Text of one top-level section: from the line starting with the given
# literal heading prefix, up to (not including) the next line starting with
# "## " (or end of file). Literal (non-regex) match via awk's index().
section_text() { # heading_prefix
  awk -v pat="$1" '
    index($0, pat) == 1 { capture=1; print; next }
    capture && index($0, "## ") == 1 { exit }
    capture { print }
  ' "$SKILL"
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

check_after() { # label line_a line_b -- assert a follows b
  if [[ -z "$2" || -z "$3" ]]; then
    echo "FAIL  $1 -> heading not found (line_a='$2' line_b='$3')"; FAILED=1
  elif (( $2 > $3 )); then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> line $2 does not follow line $3"; FAILED=1
  fi
}

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi

RAW=$(cat "$SKILL")

# --- 1/4. Section headings exist -----------------------------------------
check "## Step 0a heading exists" "$(has_f "$RAW" '## Step 0a')" "yes"
check "## Step 5a heading exists" "$(has_f "$RAW" '## Step 5a')" "yes"

# --- 2/5. Ordering ----------------------------------------------------------
STEP0A_LINE=$(first_heading_line '## Step 0a')
STEP0_LINE=$(first_heading_line '## Step 0:')
STEP5_LINE=$(first_heading_line '## Step 5:')
STEP5A_LINE=$(first_heading_line '## Step 5a')

check_before "Step 0a precedes Step 0" "$STEP0A_LINE" "$STEP0_LINE"
check_after "Step 5a follows Step 5" "$STEP5A_LINE" "$STEP5_LINE"

# --- 3. Entry record tokens (within the Step 0a section only) -------------
STEP0A_SECTION="$(section_text '## Step 0a')"
for tok in "Status: Planning" ".local/plans/" "BEFORE" "deliverable"; do
  check "Step 0a section token: $tok" \
    "$(has_f "$STEP0A_SECTION" "$tok")" "yes"
done

# --- 6. Off-ramp tokens (within the Step 5a section only) ------------------
STEP5A_SECTION="$(section_text '## Step 5a')"
for tok in "Concluded" "rationale" "engineer" "confirm"; do
  check "Step 5a section token: $tok" \
    "$(has_f "$STEP5A_SECTION" "$tok")" "yes"
done

# --- 7. No TODO.md reference in either new section --------------------------
check "Step 0a section has no TODO.md reference" \
  "$(has_f "$STEP0A_SECTION" "TODO.md")" "no"
check "Step 5a section has no TODO.md reference" \
  "$(has_f "$STEP5A_SECTION" "TODO.md")" "no"

# --- 8. Original steps preserved (headings intact) --------------------------
for h in "## Step 0: Establish the deliverable — a hard gate" \
         "## Step 1: Ensure the repo interface exists" \
         "## Step 2: Brownfield discovery (skip only in an empty repo)" \
         "## Step 3: Decompose with the engineer" \
         "## Step 4: Write the artifacts" \
         "## Step 5: Approval gate"; do
  check "original heading survives: $h" "$(has_f "$RAW" "$h")" "yes"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
