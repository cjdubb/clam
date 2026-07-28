#!/bin/bash
# Structural/anchor test for skills/dispatch/SKILL.md against Contract: B03 —
# dispatch-landing-consumption (two docblocks: "read the recorded strategy"
# at #### 5a. Compose PR content, "the size gate" at #### 5b. Write manifest
# and deliver). This is a documentation block, not executable code, so the
# tests here are:
#   - "Section tokens": each contract-required literal token or short concept
#     anchor must appear verbatim (fixed-string grep) WITHIN the relevant
#     section's own text — from its own "#### " heading up to the next
#     "#### "/"## " heading — not merely anywhere in the file.
#   - "Absence": tokens the contract requires REMOVED (the old branch/title
#     derivation instructions) must NOT appear, and new-gate tokens (§5b) must
#     not be satisfiable by anything already in the file.
#   - "Ordering": within §5b, the size-check token must appear before the
#     `deliver` invocation token (verified by comparing first-occurrence line
#     numbers within the section), operationalizing "before deliver, never
#     after the PR is open".
#   - HTML comments (the contract docblocks themselves) are stripped before
#     any section is sliced — both docblocks sit inside the very sections
#     they describe, so without stripping, every token below would already
#     read verbatim out of the docblock's own vocabulary and the red run
#     would be a false green.
#   - Token style: identifiers the contract fixes verbatim (`pr-size-check.sh`,
#     `--justified`, `Landing strategy`, `delivery.prSizeBudget`, exit-code
#     numbers, `master/main`, file paths) are asserted verbatim; clauses that
#     describe a concept are asserted on the shortest distinguishing word or
#     phrase a correctly-written guidance would naturally contain, not a
#     sentence transcribed out of the contract docblock.
#   - "Invariants": the §5a/§5b headings and surrounding step structure
#     survive; neither section references TODO.md or PLAN.md.
# This file does not test prose semantics beyond tokens/order — meaning is
# verified by the orchestrator at acceptance.
# Run: bash plugins/lego/scripts/dispatch-landing.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/dispatch/SKILL.md"

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

# First line number (1-indexed) at which a literal string first appears,
# within the given content. Empty if not found.
first_line() { # content literal
  grep -nF -- "$2" <<<"$1" | head -1 | cut -d: -f1
}

check_before() { # label line_a line_b -- assert a precedes b
  if [[ -z "$2" || -z "$3" ]]; then
    echo "FAIL  $1 -> token not found (line_a='$2' line_b='$3')"; FAILED=1
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
# Comment-stripped view: the "Contract: B03" docblocks live inline inside the
# very sections they describe, so leaving them in would let a docblock's own
# words satisfy a check meant to verify real guidance prose exists.
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")

# Section slices (comment-stripped). §5a runs from its own heading to §5b's
# heading; §5b runs from its own heading to the next top-level heading
# ("## Composition blocks"), the end of step 5 (Delivery). SECTION_5AB is the
# union, used only for the two invariants whose realized text may legitimately
# live in either subsection (see the Invariants block below).
SECTION_5A=$(awk '/^#### 5a\. Compose PR content$/{flag=1; next} /^#### 5b\. Write manifest and deliver$/{flag=0} flag' <<<"$STRIPPED")
SECTION_5B=$(awk '/^#### 5b\. Write manifest and deliver$/{flag=1; next} /^## Composition blocks$/{flag=0} flag' <<<"$STRIPPED")
SECTION_5AB="$SECTION_5A"$'\n'"$SECTION_5B"

# ==========================================================================
# §5a — read the recorded strategy
# ==========================================================================

# --- Behavior: content is READ from the plan's Landing strategy, not
# re-derived at delivery time ------------------------------------------------
check "5a: sources branch/title/commits from the plan's Landing strategy" \
  "$(has_f "$SECTION_5A" "Landing strategy")" "yes"

# --- Behavior: the old "derive from the plan's goal" instructions for title
# and branch are gone. Checked on a whitespace-normalized copy of the section
# so a fix that merely re-wraps the surrounding paragraph can't dodge the
# check by accident (the current branch-name instruction already splits
# "Derive from the" and "plan's goal" across a line-wrap boundary) -----------
NORM_5A=$(tr '\n' ' ' <<<"$SECTION_5A" | tr -s ' ')
check "5a: old title-derivation instruction is gone" \
  "$(has_f "$NORM_5A" "Derive the title from the plan's goal")" "no"
check "5a: old branch-derivation instruction is gone" \
  "$(has_f "$NORM_5A" "Derive from the plan's goal")" "no"

# --- Behavior/Edge case: no Landing strategy section on the plan -> compose
# as before AND write the result back into the plan document. "compose as
# before" is the pre-existing behavior (nothing new to anchor); the only
# newly-required, testable half of this clause is the write-back action ----
check "5a: fallback with no Landing strategy section writes the result back into the plan" \
  "$(has_f "$SECTION_5A" "back into")" "yes"

# --- Inputs: the group's Landing strategy row fields are all named. Two of
# these ("branch name", "PR title") already appear in this section today for
# unrelated reasons (the jargon-prohibition sentence and the "**PR title.**"
# heading) and so legitimately PASS before this block's guidance is written;
# the other four are new and must currently FAIL ----------------------------
for tok in "branch name" "PR title" "member units" "estimated changed lines" \
           "commit sequence" "justification"; do
  check "5a: Inputs names the group's row field: $tok" \
    "$(has_f "$SECTION_5A" "$tok")" "yes"
done

# --- Errors: a bad Landing strategy row (existing branch, malformed title)
# is a plan defect, fixed in the plan document with a Changelog entry, never
# silently substituted here --------------------------------------------------
check "5a: a bad Landing strategy row is classified as a plan defect" \
  "$(has_f "$SECTION_5A" "plan defect")" "yes"
check "5a: the defect is fixed in the plan document's Changelog" \
  "$(has_f "$SECTION_5A" "Changelog")" "yes"
check "5a: a bad row is never silently substituted" \
  "$(has_f "$SECTION_5A" "substitut")" "yes"

# --- Invariants local to §5a: pre-existing guidance that must survive
# unchanged — both already PASS today ----------------------------------------
check "5a: workflow-jargon prohibition survives" \
  "$(has_f "$SECTION_5A" "workflow terminology")" "yes"
check "5a: PR body template resolution order survives" \
  "$(has_f "$SECTION_5A" "Template resolution order")" "yes"

# --- Edge case: a Landing strategy row predating a mid-dispatch re-plan —
# the re-plan's Changelog entry wins (same anchor word the plan skill's
# sibling block uses for the same concept) -----------------------------------
check "5a: a mid-dispatch re-plan's Changelog entry wins over a stale row" \
  "$(has_f "$SECTION_5A" "mid-dispatch")" "yes"

# --- Edge case: local-only mode — nothing is opened, and the recorded
# strategy is simply what the engineer delivers by hand. Scoped strictly to
# §5a (not the 5a+5b union): §5b already mentions "local-only" today for an
# unrelated reason (skipping PR creation), which would make this check a
# false green if it weren't isolated to the section that's actually new -----
check "5a: local-only mode edge case is called out" \
  "$(has_f "$SECTION_5A" "local-only")" "yes"

# ==========================================================================
# §5b — the size gate
# ==========================================================================

# --- Behavior: pr-size-check.sh runs before deliver, never after the PR is
# open — checked both for presence and for order relative to the `deliver`
# invocation already in this section -----------------------------------------
check "5b: pr-size-check.sh is invoked" \
  "$(has_f "$SECTION_5B" "pr-size-check.sh")" "yes"
SIZE_CHECK_LINE=$(first_line "$SECTION_5B" "pr-size-check.sh")
DELIVER_CALL_LINE=$(first_line "$SECTION_5B" "worktree.sh deliver")
check_before "5b: pr-size-check.sh runs before the deliver call" \
  "$SIZE_CHECK_LINE" "$DELIVER_CALL_LINE"

# --- Behavior: what is measured — base branch against the integration
# branch, scoped to the group's Code: paths -----------------------------------
check "5b: measures against the integration branch" \
  "$(has_f "$SECTION_5B" "integration branch")" "yes"
check "5b: scopes the measurement to the group's Code: paths" \
  "$(has_f "$SECTION_5B" "Code:")" "yes"

# --- Behavior: all three exit-code outcomes are specified ------------------
check "5b: exit 0 (within budget) proceeds" \
  "$(has_f "$SECTION_5B" "exit 0")" "yes"
check "5b: exit 1 (over budget) is handled" \
  "$(has_f "$SECTION_5B" "exit 1")" "yes"
check "5b: exit 2 (usage/environment error) is handled" \
  "$(has_f "$SECTION_5B" "exit 2")" "yes"
check "5b: over-budget re-run uses --justified when a justification is recorded" \
  "$(has_f "$SECTION_5B" "--justified")" "yes"
check "5b: unjustified over-budget escalates with a splitting recommendation" \
  "$(has_f "$SECTION_5B" "splitting")" "yes"
check "5b: escalation carries a per-file breakdown" \
  "$(has_f "$SECTION_5B" "breakdown")" "yes"
check "5b: an unmeasured group is not delivered" \
  "$(has_f "$SECTION_5B" "unmeasured")" "yes"

# --- Invariant: the orchestrator never waives the budget on its own
# authority -------------------------------------------------------------------
check "5b: the orchestrator never waives the budget itself" \
  "$(has_f "$SECTION_5B" "waive")" "yes"

# --- Inputs: the budget comes from delivery.prSizeBudget, resolved by the
# script ------------------------------------------------------------------
check "5b: the budget is delivery.prSizeBudget" \
  "$(has_f "$SECTION_5B" "delivery.prSizeBudget")" "yes"

# --- Errors/Outputs: escalation is a defined outcome, not a pipeline
# failure, and is recorded in the plan Changelog and the unit status file's
# Timeline ----------------------------------------------------------------
check "5b: escalation is a defined outcome, recorded appropriately" \
  "$(has_f "$SECTION_5B" "escalat")" "yes"
check "5b: escalation is recorded in the plan Changelog" \
  "$(has_f "$SECTION_5B" "Changelog")" "yes"
check "5b: escalation is recorded in the unit status file's Timeline" \
  "$(has_f "$SECTION_5B" "Timeline")" "yes"

# --- Invariant: the manifest schema and the deliver invocation are
# unchanged — already present and must still be, within this section -------
check "5b: the --manifest .local/pr-manifest.json invocation survives" \
  "$(has_f "$SECTION_5B" "--manifest .local/pr-manifest.json")" "yes"

# --- Edge cases -------------------------------------------------------------
# master moved between the check and deliver: anchored on "moved between",
# not bare "moved" — the existing sentence "worktrees were already removed"
# contains "moved" as a substring of "removed" and would otherwise be a false
# green.
check "5b: master moving between check and deliver is addressed" \
  "$(has_f "$SECTION_5B" "moved between")" "yes"
# A single inherently oversized block: the justification is decided at plan
# time, not here (same anchor phrase the plan skill's sibling block uses for
# the analogous "decided at plan time" concept).
check "5b: a single oversized block's justification is decided at plan time" \
  "$(has_f "$SECTION_5B" "plan time")" "yes"
# local-only: the gate does not apply. This token already appears in §5b
# today (the pre-existing "skip PR creation" paragraph), so this check
# legitimately PASSES now — a short anchor that discriminates "the gate
# specifically does not apply" from that pre-existing, differently-reasoned
# mention isn't available without transcribing the contract's own sentence;
# meaning here is left to orchestrator acceptance.
check "5b: local-only mode means the gate does not apply" \
  "$(has_f "$SECTION_5B" "local-only")" "yes"
# pr-size-check.sh absent (older plugin checkout): treat as exit 2.
check "5b: a missing pr-size-check.sh is treated as exit 2" \
  "$(has_f "$SECTION_5B" "absent")" "yes"

# ==========================================================================
# Invariants shared by both docblocks (contract: PRs target master/main
# only; the plan and the opened PR agree on branch and title). Both may
# legitimately land in either subsection's prose, so both are checked
# against the 5a+5b union rather than pinned to one side ---------------------
# ==========================================================================
check "5a/5b: PRs still target master/main only" \
  "$(has_f "$SECTION_5AB" "master/main")" "yes"
check "5a/5b: the plan document and the opened PR agree on branch and title" \
  "$(has_f "$SECTION_5AB" "agree")" "yes"

# --- Isolation: neither section references tracking's files (lego never
# touches TODO.md/PLAN.md) ---------------------------------------------------
check "5a section has no TODO.md reference" \
  "$(has_f "$SECTION_5A" "TODO.md")" "no"
check "5a section has no PLAN.md reference" \
  "$(has_f "$SECTION_5A" "PLAN.md")" "no"
check "5b section has no TODO.md reference" \
  "$(has_f "$SECTION_5B" "TODO.md")" "no"
check "5b section has no PLAN.md reference" \
  "$(has_f "$SECTION_5B" "PLAN.md")" "no"

# --- Invariant: the §5a/§5b headings and the surrounding step structure
# survive the edit -----------------------------------------------------------
for h in "### 4. Local merge" "### 5. Delivery" \
         "#### 5a. Compose PR content" "#### 5b. Write manifest and deliver" \
         "## Composition blocks"; do
  check "structure survives: $h" "$(has_f "$RAW" "$h")" "yes"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
