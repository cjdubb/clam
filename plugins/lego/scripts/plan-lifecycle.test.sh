#!/bin/bash
# Structural/anchor test for skills/plan/SKILL.md against Contract: B07
# lego-plan-lifecycle, Contract: 001-B02 premise-invalid-closure, and
# Contract: 001-B01 plan-always-blocks. This skill is a documentation block,
# not executable code, so the tests here are:
#   - "Heading presence": Step 0a, Step 2a, and the always-blocks headings exist; the
#     Step 5a off-ramp heading is ABSENT (001-B02/001-B01 replace it: a
#     premise-invalid closure inside Step 2, and the every-deliverable-yields-
#     a-block rule inside Step 3 — there is no longer a no-blocks off-ramp
#     reachable from sizing/triviality).
#   - "Ordering": Step 0a precedes Step 0; Step 2a sits inside Step 2 (after
#     "## Step 2:", before "## Step 3:"); always-blocks sits inside Step 3 (after
#     "## Step 3:", before "## Step 4:") — verified by comparing the line
#     numbers of their first occurrences.
#   - "Section tokens": each contract-required literal token must appear
#     verbatim (fixed-string grep) WITHIN the relevant section's own text
#     (from its heading up to, but not including, the next top-level "## "
#     heading) — not merely anywhere in the file. Section tokens are checked
#     against the HTML-comment-STRIPPED text: Step 2a's and always-blocks'
#     contract docblocks (`<!-- Contract: ... -->`) restate their own
#     required tokens as documentation, so matching against the raw text
#     would let a
#     token check pass off the docblock alone even with a NotImplemented
#     stub still in place. Stripping comments first forces every section
#     token check to hit real, written prose. EXCEPTION: the "Step 0a no
#     longer references Step 5a" check inspects Step 0a's docblock on
#     purpose — the stale "(Step 5a)" pointer being cleaned up lives only in
#     that comment, so this one check stays on the raw (unstripped) section;
#     stripping it would make it vacuously pass either way.
#   - "Isolation": new/changed sections don't reference TODO.md (lego never
#     touches tracking's files).
#   - "Global absence": the deleted off-ramp's sizing trigger phrase
#     ("better served by a single direct change") no longer appears anywhere,
#     and neither NotImplemented marker (001-B01, 001-B02) survives.
#   - "Owner rationale": Step 3's owner bullet says WHY engineer ownership
#     exists (design authorship), so orchestrators offer it as a first-class
#     choice at plan time rather than an edge case.
#   - "Invariants": the original Step 0-5 headings all survive unchanged, and
#     Step 0a's own invariant text no longer points at the removed Step 5a.
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

# Text of one top-level section, read from stdin: from the line starting
# with the given literal heading prefix, up to (not including) the next line
# starting with "## " (or end of input). Literal (non-regex) match via awk's
# index(). This also correctly isolates a "### " subsection nested inside a
# "## " section, since a "### " line never matches the "## " boundary
# prefix. Callers pipe in either $STRIPPED (comment-stripped; the default
# for section-token checks) or $RAW (only for the one check that
# deliberately needs to see docblock text) — see the file header comment.
section_text() { # heading_prefix < text
  awk -v pat="$1" '
    index($0, pat) == 1 { capture=1; print; next }
    capture && index($0, "## ") == 1 { exit }
    capture { print }
  '
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

# Comment-stripped text: contract docblocks (<!-- Contract: ... --> HTML
# comments) removed. Section-token checks scope against THIS, not $RAW, so
# a token that only appears inside a docblock's own contract prose does not
# vacuously satisfy a check for prose that hasn't been written yet.
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")

# --- 1. Section headings exist / are absent --------------------------------
check "## Step 0a heading exists" "$(has_f "$RAW" '## Step 0a')" "yes"
check "### Step 2a heading exists" "$(has_f "$RAW" '### Step 2a')" "yes"
check "always-blocks heading exists" "$(has_f "$RAW" '### Every deliverable yields')" "yes"
check "## Step 5a heading is absent (off-ramp removed)" \
  "$(has_f "$RAW" '## Step 5a')" "no"

# --- 2. Ordering -------------------------------------------------------------
STEP0A_LINE=$(first_heading_line '## Step 0a')
STEP0_LINE=$(first_heading_line '## Step 0:')
STEP2_LINE=$(first_heading_line '## Step 2:')
STEP2A_LINE=$(first_heading_line '### Step 2a')
STEP3_LINE=$(first_heading_line '## Step 3:')
STEP3A_LINE=$(first_heading_line '### Every deliverable yields')
STEP4_LINE=$(first_heading_line '## Step 4:')

check_before "Step 0a precedes Step 0" "$STEP0A_LINE" "$STEP0_LINE"
check_after "Step 2a follows Step 2" "$STEP2A_LINE" "$STEP2_LINE"
check_before "Step 2a precedes Step 3" "$STEP2A_LINE" "$STEP3_LINE"
check_after "always-blocks section follows Step 3" "$STEP3A_LINE" "$STEP3_LINE"
check_before "always-blocks section precedes Step 4" "$STEP3A_LINE" "$STEP4_LINE"

# --- 3. Entry record tokens (within the Step 0a section only) -------------
# Stripped text: Step 0a is already-implemented prose, so these tokens must
# be found in the real body, not merely restated by its own docblock.
STEP0A_SECTION="$(section_text '## Step 0a' <<<"$STRIPPED")"
for tok in "Status: Planning" ".local/plans/" "BEFORE" "deliverable"; do
  check "Step 0a section token: $tok" \
    "$(has_f "$STEP0A_SECTION" "$tok")" "yes"
done

# Step 0a's own invariant no longer points at the removed Step 5a off-ramp.
# Deliberately RAW, not stripped: the stale "(Step 5a)" pointer being
# cleaned up lives only inside Step 0a's docblock, so stripping comments
# here would blind this check to the exact place the fix has to land,
# making it pass vacuously regardless of whether the reference was removed.
STEP0A_SECTION_RAW="$(section_text '## Step 0a' <<<"$RAW")"
check "Step 0a section no longer references Step 5a" \
  "$(has_f "$STEP0A_SECTION_RAW" "Step 5a")" "no"

# --- 4. Contract: 001-B02 premise-invalid-closure (within Step 2a only) ---
# One group per docblock clause, so every clause traces to a test. Stripped
# text: the contract docblock restates these same tokens as documentation,
# so matching against it would pass even while "NotImplemented: 001-B02"
# still stands in for the actual prose.
STEP2A_SECTION="$(section_text '### Step 2a' <<<"$STRIPPED")"

# Behavior: factual closure, and the ONLY exit that produces no blocks.
for tok in "Closed (deliverable does not exist)" "ONLY exit from planning"; do
  check "Step 2a Behavior token: $tok" "$(has_f "$STEP2A_SECTION" "$tok")" "yes"
done

# Inputs: the Step 0a plan doc, and evidence must be citable.
check "Step 2a Inputs token: must be citable" \
  "$(has_f "$STEP2A_SECTION" "must be citable")" "yes"

# Outputs: Status/Outcome/Evidence fields, blocks.md note, engineer confirms.
for tok in "Closed (deliverable does not exist)" "Evidence" "engineer" "confirm"; do
  check "Step 2a Outputs token: $tok" "$(has_f "$STEP2A_SECTION" "$tok")" "yes"
done

# Errors: missing plan doc is a recovery path; weak evidence does NOT apply.
for tok in "recovery path" "does NOT apply"; do
  check "Step 2a Errors token: $tok" "$(has_f "$STEP2A_SECTION" "$tok")" "yes"
done

# Invariants (one bullet = one clause).
check "Step 2a Invariant: factual, never a preference" \
  "$(has_f "$STEP2A_SECTION" "never a preference")" "yes"
check "Step 2a Invariant: engineer confirms, orchestrator proposes and stops" \
  "$(has_f "$STEP2A_SECTION" "orchestrator proposes and stops")" "yes"
check "Step 2a Invariant: plan doc Status field reflects the closure" \
  "$(has_f "$STEP2A_SECTION" "Status field reflects the closure")" "yes"
check "Step 2a Invariant: reachable only from Step 0/Step 2 evidence, never later" \
  "$(has_f "$STEP2A_SECTION" "never later")" "yes"

# Edge cases (one bullet = one clause).
check "Step 2a Edge case: collapses during Step 0, before discovery runs" \
  "$(has_f "$STEP2A_SECTION" "before discovery runs")" "yes"
check "Step 2a Edge case: merged under a different design -> follow-up" \
  "$(has_f "$STEP2A_SECTION" "design delta as a follow-up")" "yes"
check "Step 2a Edge case: only PART done -> decompose the remainder" \
  "$(has_f "$STEP2A_SECTION" "decompose the remainder")" "yes"

check "Step 2a section has no TODO.md reference" \
  "$(has_f "$STEP2A_SECTION" "TODO.md")" "no"

# --- 5. Contract: 001-B01 plan-always-blocks (always-blocks section only) -
# One group per docblock clause, so every clause traces to a test. Stripped
# text: same reasoning as Step 2a above — the docblock must not be able to
# satisfy its own checks in place of the actual prose.
STEP3A_SECTION="$(section_text '### Every deliverable yields' <<<"$STRIPPED")"

# Behavior: always >=1 block, no size threshold, no "worth it" question,
# trivial change is still a block, direct-change lives inside the workflow,
# and planning has exactly two terminal states (this / Step 2a).
for tok in "at least one block" "threshold below which the workflow is skipped" \
           '"worth" block decomposition' "is still a block" \
           "lives INSIDE the workflow" "exactly two terminal states"; do
  check "always-blocks Behavior token: $tok" "$(has_f "$STEP3A_SECTION" "$tok")" "yes"
done

# Inputs: a confirmed deliverable that Step 2a did not close.
check "always-blocks Inputs token: Step 2a did not close" \
  "$(has_f "$STEP3A_SECTION" "Step 2a did not close")" "yes"

# Outputs: >=1 block presented at Step 5, trivial blocks marked not omitted.
for tok in ">= 1 block" "Owner: engineer" "rather than omitted"; do
  check "always-blocks Outputs token: $tok" "$(has_f "$STEP3A_SECTION" "$tok")" "yes"
done

# Errors: zero blocks is never an exit; unevidenced no-blocks plan is a defect.
for tok in "neither is an exit" "is a defect"; do
  check "always-blocks Errors token: $tok" "$(has_f "$STEP3A_SECTION" "$tok")" "yes"
done

# Invariants (one bullet = one clause).
check "always-blocks Invariant: never concludes with zero blocks except via Step 2a" \
  "$(has_f "$STEP3A_SECTION" "except via Step 2a")" "yes"
check "always-blocks Invariant: size/triviality/fit are NEVER grounds to skip" \
  "$(has_f "$STEP3A_SECTION" "NEVER grounds for")" "yes"
check "always-blocks Invariant: Owner: engineer does not bypass contract/tests/gate" \
  "$(has_f "$STEP3A_SECTION" "is the direct-change path")" "yes"
check "always-blocks Invariant: one block is a legitimate, complete plan" \
  "$(has_f "$STEP3A_SECTION" "legitimate, complete plan")" "yes"

# Edge cases (one bullet = one clause).
check "always-blocks Edge case: single-file/single-line change, often Owner: engineer" \
  "$(has_f "$STEP3A_SECTION" "Single-file, single-line changes")" "yes"
check "always-blocks Edge case: documentation-only deliverables still blocks" \
  "$(has_f "$STEP3A_SECTION" "Documentation-only deliverables: still blocks")" "yes"
check "always-blocks Edge case: partly-done deliverable -> decompose remainder only" \
  "$(has_f "$STEP3A_SECTION" "decompose the remainder only")" "yes"

check "always-blocks section has no TODO.md reference" \
  "$(has_f "$STEP3A_SECTION" "TODO.md")" "no"

# --- 6. Off-ramp removal is global, not just heading-deep -------------------
# NOTE: matched as "served by a single direct change" (dropping the leading
# "better") because the source line-wraps "better" onto the prior line;
# has_f/grep -F matches within a single line, so the wrapped word would
# never match regardless of whether the phrase is present.
check "sizing trigger phrase absent: 'served by a single direct change'" \
  "$(has_f "$RAW" "served by a single direct change")" "no"
check "no NotImplemented: 001-B01 marker remains" \
  "$(has_f "$RAW" "NotImplemented: 001-B01")" "no"
check "no NotImplemented: 001-B02 marker remains" \
  "$(has_f "$RAW" "NotImplemented: 001-B02")" "no"

# --- 7. No TODO.md reference in Step 0a --------------------------------------
check "Step 0a section has no TODO.md reference" \
  "$(has_f "$STEP0A_SECTION" "TODO.md")" "no"

# --- 7a. Owner bullet rationale (within the Step 3 section only) -----------
# "authorship" is the shortest word that distinguishes the reason engineer
# ownership exists from the mechanical parity ("same contract, same tests")
# the bullet already states; "first-class" pins the framing orchestrators
# must use when offering the choice.
STEP3_SECTION="$(section_text '## Step 3: Decompose with the engineer' <<<"$STRIPPED")"
for tok in "Owner: agent or engineer" "authorship" "first-class"; do
  check "Step 3 section token: $tok" \
    "$(has_f "$STEP3_SECTION" "$tok")" "yes"
done

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
