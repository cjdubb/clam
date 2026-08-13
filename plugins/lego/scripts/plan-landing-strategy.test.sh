#!/bin/bash
# Structural/anchor test for skills/plan/SKILL.md and templates/blocks.md
# against Contract: B02 — plan-landing-strategy (two docblocks: "sizing and
# grouping" at Step 3a, "artifacts" at Step 4). This is a documentation/
# template block, not executable code, so the tests here are:
#   - "Heading presence": the Step 3a heading exists.
#   - "Ordering": Step 3a follows Step 3's heading and precedes Step 4's
#     heading (verified by comparing first-occurrence line numbers).
#   - "Section tokens": each contract-required literal token must appear
#     verbatim (fixed-string grep) WITHIN the relevant section's own text
#     (from its heading up to, but not including, the next top-level "## "
#     heading) — not merely anywhere in the file.
#   - Token style: identifiers the contract fixes (`delivery.prSizeBudget`,
#     `500`, `- Est:`, field-label names, "Landing strategy") are asserted
#     verbatim; clauses that describe a concept are asserted on the shortest
#     distinguishing word a correctly-written guidance would contain in its
#     own words, not a sentence transcribed out of the contract docblock.
#   - HTML comments (the contract docblocks themselves) are stripped before
#     any section is sliced, so a docblock's own vocabulary can never
#     satisfy a token check — only real guidance prose counts. Without this,
#     every token below would already read verbatim out of the docblock and
#     the red run would be a false green.
#   - "Cross-file agreement": templates/blocks.md's example entry carries
#     the same field-label set as SKILL.md's block-map entry format — with
#     one carve-out for `Justification:`, which the entry format documents
#     as OPTIONAL (it is required only of a block over the per-block size
#     ceiling), so a template example that omits it is correct, not stale.
#     Every other divergence in either direction is still a failure.
#   - "Isolation": neither new section references TODO.md or PLAN.md (lego
#     never touches tracking's files).
#   - "Invariants": the original Step 0-5 headings all survive unchanged.
# This file does not test prose semantics beyond tokens/headings/order —
# meaning is verified by the orchestrator at acceptance.
# Run: bash plugins/lego/scripts/plan-landing-strategy.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/plan/SKILL.md"
TEMPLATE="$SCRIPT_DIR/../templates/blocks.md"

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

# First line number (1-indexed) at which a literal string appears, within
# the given content (not the raw file — see the comment-stripping note
# above). Empty if not found.
first_heading_line() { # content literal
  grep -nF -- "$2" <<<"$1" | head -1 | cut -d: -f1
}

# Text of one top-level section: from the line starting with the given
# literal heading prefix, up to (not including) the next line starting with
# "## " (or end of content). Literal (non-regex) match via awk's index().
section_text() { # content heading_prefix
  awk -v pat="$2" '
    index($0, pat) == 1 { capture=1; print; next }
    capture && index($0, "## ") == 1 { exit }
    capture { print }
  ' <<<"$1"
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

# Field labels ("- Label:" bullets, any indent) in a block-map-style entry,
# sorted unique — used to compare SKILL.md's entry format against
# templates/blocks.md's example entry.
field_labels() { # content
  grep -oE '^[[:space:]]*- [A-Za-z ]+:' <<<"$1" \
    | sed -E 's/^[[:space:]]*- //; s/:$//' | sort -u
}

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi
if [[ ! -f "$TEMPLATE" ]]; then
  echo "FAIL  templates/blocks.md not found at $TEMPLATE"
  exit 1
fi

RAW=$(cat "$SKILL")
TEMPLATE_RAW=$(cat "$TEMPLATE")
# Comment-stripped view: the "Contract: B02" docblocks live inline inside
# the very sections they describe, so leaving them in would let a docblock's
# own words satisfy a check meant to verify real guidance prose exists.
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")

# --- 1. Heading presence ----------------------------------------------------
check "## Step 3a heading exists" "$(has_f "$RAW" '## Step 3a')" "yes"

# --- 2. Ordering: Step 3 < Step 3a < Step 4 ---------------------------------
STEP3_LINE=$(first_heading_line "$STRIPPED" '## Step 3:')
STEP3A_LINE=$(first_heading_line "$STRIPPED" '## Step 3a:')
STEP4_LINE=$(first_heading_line "$STRIPPED" '## Step 4:')

check_after "Step 3a follows Step 3's heading" "$STEP3A_LINE" "$STEP3_LINE"
check_before "Step 3a precedes Step 4's heading" "$STEP3A_LINE" "$STEP4_LINE"

STEP3A_SECTION="$(section_text "$STRIPPED" '## Step 3a')"
STEP4_SECTION="$(section_text "$STRIPPED" '## Step 4')"

# --- 3. Step 3a: the three ordered activities (estimate / split / group) ---
# "split" anchors the remedy, not "returning to Step 3": the section's own
# heading ("## Step 3a") already contains the substring "Step 3", which
# would make a literal "Step 3" token check trivially, untestably true.
check "Step 3a names estimating size in changed lines" \
  "$(has_f "$STEP3A_SECTION" "changed lines")" "yes"
check "Step 3a names splitting an over-budget block back into Step 3" \
  "$(has_f "$STEP3A_SECTION" "split")" "yes"
check "Step 3a names forming PR groups" \
  "$(has_f "$STEP3A_SECTION" "PR groups")" "yes"

# --- 4. Step 3a: the budget is named explicitly, with its default ----------
check "Step 3a names delivery.prSizeBudget" \
  "$(has_f "$STEP3A_SECTION" "delivery.prSizeBudget")" "yes"
check "Step 3a names the 500 default" \
  "$(has_f "$STEP3A_SECTION" "500")" "yes"

# --- 5. Step 3a: per-group landing details are all named (Outputs-fixed
# field names, verbatim) -----------------------------------------------------
for tok in "branch name" "PR title" "member units" "estimated changed lines" \
           "commit sequence"; do
  check "Step 3a per-group detail named: $tok" \
    "$(has_f "$STEP3A_SECTION" "$tok")" "yes"
done

# --- 6. Step 3a: over-budget justification is required, not optional -------
check "Step 3a requires a justification for an over-budget group" \
  "$(has_f "$STEP3A_SECTION" "justification")" "yes"
check "Step 3a: an absent justification is a defect, not permission" \
  "$(has_f "$STEP3A_SECTION" "defect")" "yes"

# --- 7. Step 3a: splitting is the first remedy, not an oversized PR by
# default. "oversized" is the contract's own word for the concept -----------
check "Step 3a: splitting is the first remedy, not an oversized PR by default" \
  "$(has_f "$STEP3A_SECTION" "oversized")" "yes"

# --- 8. Step 3a: invariants and edge cases. "mechanical check" is kept
# verbatim as an established repo term (see dispatch's "mechanical realm
# checks"); "intended grouping" is already minimal — "intended" alone risks
# matching unrelated prose elsewhere in the section ---------------------------
check "Step 3a: commit subjects decided at plan time, not delivery time" \
  "$(has_f "$STEP3A_SECTION" "improvised")" "yes"
check "Step 3a: PR groups ordered so dependencies land first" \
  "$(has_f "$STEP3A_SECTION" "dependencies")" "yes"
check "Step 3a: estimates decide grouping, not acceptance" \
  "$(has_f "$STEP3A_SECTION" "mechanical check")" "yes"
check "Step 3a: local-only delivery still records intended grouping" \
  "$(has_f "$STEP3A_SECTION" "intended grouping")" "yes"

# --- 9. Step 3a: Errors clause — an unresolvable, unjustified over-budget
# block is escalated to the engineer, not decided by the orchestrator alone.
# "escalat" matches escalate/escalates/escalation, the repo's own term for
# this (Escalated status, Escalation loop) -----------------------------------
check "Step 3a: unresolved over-budget block is escalated to the engineer" \
  "$(has_f "$STEP3A_SECTION" "escalat")" "yes"

# --- 10. Step 3a: edge case — small deliverable still gets the section -----
check "Step 3a: a small deliverable still gets the section, with one group" \
  "$(has_f "$STEP3A_SECTION" "one group")" "yes"

# --- 11. Step 3a: edge case — shared paths (lockfile) force sequential
# delivery and are called out with the group ---------------------------------
check "Step 3a: shared paths forcing sequential delivery are called out" \
  "$(has_f "$STEP3A_SECTION" "lockfile")" "yes"

# --- 12. Step 4: Landing strategy section, incl. the budget it was sized
# against (Behavior 1) -------------------------------------------------------
check "Step 4 requires a Landing strategy section" \
  "$(has_f "$STEP4_SECTION" "Landing strategy")" "yes"
check "Step 4 Landing strategy carries the budget it was sized against" \
  "$(has_f "$STEP4_SECTION" "budget")" "yes"
for tok in "branch name" "PR title" "member units" "estimated changed lines" \
           "commit sequence" "justification"; do
  check "Step 4 Landing strategy carries: $tok" \
    "$(has_f "$STEP4_SECTION" "$tok")" "yes"
done

# --- 13. Step 4: the block-map entry format gains Est: ----------------------
check "Step 4 block-map entry format shows an Est: field" \
  "$(has_f "$STEP4_SECTION" "- Est:")" "yes"

# --- 14. Step 4: pre-existing artifact requirements survive (additive) -----
check "Step 4: Plan document artifact still required" \
  "$(has_f "$STEP4_SECTION" "**Plan document**")" "yes"
check "Step 4: Block map entries artifact still required" \
  "$(has_f "$STEP4_SECTION" "**Block map entries**")" "yes"
check "Step 4: Status lifecycle line still present" \
  "$(has_f "$STEP4_SECTION" "Status lifecycle:")" "yes"
check "Step 4: block-map entry format still shows a Code: field" \
  "$(has_f "$STEP4_SECTION" "- Code: <intended path(s)>")" "yes"

# --- 15. Step 4: invariant — branch names and titles are final, not
# placeholders, for a reader with no access to the planning conversation ----
check "Step 4: branch names and titles are final, not placeholders" \
  "$(has_f "$STEP4_SECTION" "placeholder")" "yes"

# --- 16. Step 4: edge case — inestimable block still gets a rough Est: -----
check "Step 4: an inestimable block still gets a rough Est: figure" \
  "$(has_f "$STEP4_SECTION" "rough")" "yes"

# --- 17. Step 4: edge case — mid-dispatch re-plan updates the section and
# appends the Changelog. Anchored on "mid-dispatch", not bare "Changelog":
# the Plan document artifact bullet above already names "Changelog" for an
# unrelated, pre-existing reason, so that word alone would be a false green -
check "Step 4: mid-dispatch re-planning updates the section and Changelog" \
  "$(has_f "$STEP4_SECTION" "mid-dispatch")" "yes"

# --- 18. Cross-file: templates/blocks.md's example entry gains Est: --------
check "templates/blocks.md example entry has an Est: field" \
  "$(has_f "$TEMPLATE_RAW" "- Est:")" "yes"

# --- 19. Cross-file agreement: the block-map field list and the template's
# example entry name the same fields (nothing added to one without the
# other), except the optional `Justification:` field — see the header note.
# The example entry shows a block that needs no justification, so carrying
# the field there would misrepresent it as routine; the exception is that
# one field name and nothing else, in that one direction ---------------------
SKILL_FIELDS="$(field_labels "$STEP4_SECTION")"
TEMPLATE_FIELDS="$(field_labels "$TEMPLATE_RAW")"
TEMPLATE_ONLY="$(grep -vxF -f <(printf '%s\n' "$SKILL_FIELDS") \
  <(printf '%s\n' "$TEMPLATE_FIELDS"))"
SKILL_ONLY="$(grep -vxF -f <(printf '%s\n' "$TEMPLATE_FIELDS") \
  <(printf '%s\n' "$SKILL_FIELDS"))"
check "every templates/blocks.md field appears in the block-map field list" \
  "$TEMPLATE_ONLY" ""
if [[ -z "$SKILL_ONLY" || "$SKILL_ONLY" == "Justification" ]]; then
  SKILL_ONLY_VERDICT="only the optional Justification, if anything"
else
  SKILL_ONLY_VERDICT="$SKILL_ONLY"
fi
check "block-map fields absent from the template are limited to Justification" \
  "$SKILL_ONLY_VERDICT" "only the optional Justification, if anything"

# --- 20. Isolation: neither new section references tracking's files -------
check "Step 3a section has no TODO.md reference" \
  "$(has_f "$STEP3A_SECTION" "TODO.md")" "no"
check "Step 3a section has no PLAN.md reference" \
  "$(has_f "$STEP3A_SECTION" "PLAN.md")" "no"
check "Step 4 section has no TODO.md reference" \
  "$(has_f "$STEP4_SECTION" "TODO.md")" "no"
check "Step 4 section has no PLAN.md reference" \
  "$(has_f "$STEP4_SECTION" "PLAN.md")" "no"

# --- 21. Invariant: original Step 0-5 headings survive unchanged -----------
for h in "## Step 0: Establish the deliverable — a hard gate" \
         "## Step 1: Ensure the repo interface exists" \
         "## Step 2: Brownfield discovery (skip only in an empty repo)" \
         "## Step 3: Decompose with the engineer" \
         "## Step 4: Write the artifacts" \
         "## Step 7: Approval gate"; do
  check "original heading survives: $h" "$(has_f "$RAW" "$h")" "yes"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
