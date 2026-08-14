#!/bin/bash
# Structural/anchor test for skills/plan/SKILL.md against Contract: B03 —
# plan sizing & contract rules (the leaf test and contract-summary content
# bar in Step 3, the derived per-block size ceiling and Justification path
# in Step 3a, the optional Justification: field in Step 4's entry format).
# This is a prose block, not executable code, so the tests here are:
#   - "Section tokens": each contract-required literal token must appear
#     verbatim (fixed-string grep) WITHIN the relevant section's own text —
#     not merely anywhere in the file. Which section a rule lands in is
#     itself part of the contract (leaf test in Step 3, ceiling in Step 3a),
#     so a token found in the wrong section is a failure, not a pass.
#   - Token style: identifiers the contract fixes (`prSizeBudget`, `250`,
#     `Justification:`, the three-part leaf-test phrasing) are asserted
#     verbatim; clauses that describe a concept are asserted on the shortest
#     distinguishing word a correctly-written guidance would contain in its
#     own words. A regex is used only where several spellings are all
#     correct (`input→output` / `inputs and outputs` / `input/output`).
#   - "Adjacency": the three leaf-test parts must be stated TOGETHER as one
#     test, not scattered across the step — asserted with a line-window
#     check rather than three independent presence checks.
#   - HTML comments (the contract docblock itself) are stripped before any
#     section is sliced, so the docblock's own vocabulary can never satisfy
#     a token check — only real guidance prose counts. Without this, nearly
#     every token below would already read verbatim out of the docblock and
#     the red run would be a false green. The docblock's presence or
#     absence is therefore never asserted: it is removed at acceptance,
#     after these tests are green, and stripping makes them agree either
#     way.
#   - "Invariants": the sections the contract holds fixed (Step 0's and
#     Step 3's question gates, the always-blocks subsection, the group-level
#     budget rules, the pre-existing entry-format fields, the zone
#     boundaries other suites slice on) still read as they did.
#   - "No config key": the set of `delivery.<key>` identifiers named in the
#     file is EMPTY (Contract: B07 — the budget is a plan fact recorded in the
#     Landing strategy, and the ceiling is DERIVED from it), so any key at all
#     is a contract violation even if every other anchor passes.
# This file does not test prose semantics beyond tokens/order/adjacency —
# meaning is verified by the orchestrator at acceptance.
#
# Sections 13-15 extend the same approach to Contract: B08 —
# Est-includes-tests prose (Step 3a item 1 states that the block's own tests
# count toward Est and that test volume typically dominates the total, 2-4x
# observed). Two notes specific to that contract:
#   - Its anchors are sliced out of Step 3a's ITEM 1, not out of Step 3a as a
#     whole: the contract fixes which item the sentence lands in, so a
#     correct sentence in item 2 is a failure, not a pass.
#   - The docblock for B08 sits inside item 1 and quotes its own mandated
#     anchor ("typically dominates") verbatim. Slicing from $STRIPPED is what
#     keeps the red run red; a check written against $RAW would pass today
#     off the comment and keep passing after the comment is removed with no
#     prose ever written.
#
# Sections 16-onward extend the same approach to Contract: B14 —
# plan-skill-split-estimates: Step 3a item 1 gains an Est-impl:/Est-tests:
# pair per block (Est-tests defaulting to 3x Est-impl unless overridden per
# block with a stated reason), with Est: recorded as their bare-integer sum;
# Step 4's block-entry template and templates/blocks.md's example entry both
# carry the pair above Est:. Two notes specific to this contract:
#   - The docblock for B14 sits directly under the "## Step 3a" heading, so
#     it is excluded from every $STRIPPED slice the same way B03/B08's
#     docblocks are — a check written against $RAW would false-green off the
#     comment's own vocabulary.
#   - templates/blocks.md carries no contract docblock of its own (its
#     "Example entry; delete once real blocks exist" comment is a permanent
#     template device, not a contract docblock removed at acceptance), so
#     its checks below read the file's raw content directly, and the
#     Est-equals-sum check is arithmetic, not a token match.
# Run: bash plugins/lego/scripts/plan-sizing.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/plan/SKILL.md"
BLOCKS_TEMPLATE="$SCRIPT_DIR/../templates/blocks.md"

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

# Extended-regex presence check. Used ONLY where the contract fixes a
# concept whose correct spellings genuinely vary; everything else is has_f.
has_re() { # content regex
  if grep -qE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Text of one section: from the line starting with the given literal heading
# prefix, up to (not including) the next line starting with the given
# boundary prefix (or end of input). Literal (non-regex) match via awk's
# index(). A "### " boundary lets a "## " section be sliced short of its
# first subsection.
section_text() { # heading_prefix boundary_prefix < text
  awk -v pat="$1" -v stop="$2" '
    index($0, pat) == 1 { capture=1; print; next }
    capture && index($0, stop) == 1 { exit }
    capture { print }
  '
}

# "yes" when some occurrence of the anchor pattern has an occurrence of
# EVERY other pattern within +/- window lines of it — i.e. the parts are
# stated together as one rule rather than scattered across the section.
# Patterns are extended regexes, matching has_re.
near_all() { # window content anchor other...
  local window="$1" content="$2" anchor="$3"
  shift 3
  local -a anchor_lines other_lines
  anchor_lines=(); while IFS= read -r __ln; do anchor_lines+=(""); done < <(grep -nE -- "$anchor" <<<"$content" | cut -d: -f1)
  local a o tok ok
  for a in "${anchor_lines[@]}"; do
    ok=yes
    for tok in "$@"; do
      other_lines=(); while IFS= read -r __ln; do other_lines+=(""); done < <(grep -nE -- "$tok" <<<"$content" | cut -d: -f1)
      local hit=no
      for o in "${other_lines[@]}"; do
        if (( o - a <= window && a - o <= window )); then hit=yes; break; fi
      done
      [[ "$hit" == "yes" ]] || { ok=no; break; }
    done
    [[ "$ok" == "yes" ]] && { echo yes; return; }
  done
  echo no
}

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi
if [[ ! -f "$BLOCKS_TEMPLATE" ]]; then
  echo "FAIL  templates/blocks.md not found at $BLOCKS_TEMPLATE"
  exit 1
fi

RAW=$(cat "$SKILL")
# Comment-stripped view — see the header note. Every section below is sliced
# out of THIS, never out of $RAW.
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")
# templates/blocks.md carries no contract docblock (see header note) — read
# raw, with no stripping.
TEMPLATE_RAW=$(cat "$BLOCKS_TEMPLATE")

# Step 3's decomposition body: the leaf definition and the per-block
# agreement bullets, sliced short of the "### Every deliverable yields..."
# subsection. The contract places the leaf test and the contract-summary
# content bar in the leaf definition, and holds the always-blocks
# subsection unchanged, so new prose landing in the subsection instead of
# the body is a contract violation these checks must catch. The boundary is
# that subsection's own heading, not any "### " — a new subsection ABOVE it
# (say, one that names the leaf test) is a legitimate way to write this and
# must not truncate the slice.
STEP3_BODY="$(section_text '## Step 3: ' '### Every deliverable' <<<"$STRIPPED")"
# The whole of Step 3, subsection and closing gate included — used only for
# the invariants that live past the subsection heading.
STEP3_FULL="$(section_text '## Step 3: ' '## Step 3a' <<<"$STRIPPED")"
ALWAYS_BLOCKS="$(section_text '### Every deliverable yields' '## Step 3a' <<<"$STRIPPED")"
STEP3A_SECTION="$(section_text '## Step 3a' '## ' <<<"$STRIPPED")"
STEP4_SECTION="$(section_text '## Step 4' '## ' <<<"$STRIPPED")"
STEP0_SECTION="$(section_text '## Step 0: ' '## ' <<<"$STRIPPED")"

# --- 0. Sections slice non-empty (a slice that silently came back empty
# would make every token check below fail for the wrong reason) ------------
for pair in "Step 3 body:$STEP3_BODY" "Step 3a:$STEP3A_SECTION" \
            "Step 4:$STEP4_SECTION" "always-blocks:$ALWAYS_BLOCKS" \
            "Step 0:$STEP0_SECTION"; do
  label="${pair%%:*}"; body="${pair#*:}"
  check "section slice is non-empty: $label" \
    "$([[ -n "$(tr -d '[:space:]' <<<"$body")" ]] && echo yes || echo no)" "yes"
done

# --- 1. Behavior 1: Step 3's leaf definition carries a three-part leaf
# test a block must pass to stay a leaf -------------------------------------
# Case tolerance: the three parts read as naturally in a capitalised bullet
# list ("**One concern** — ...") or in the docblock's emphatic ONE as they
# do mid-sentence, and all three spellings are correct prose. The wording is
# pinned; the capitalisation is not.
ONE_CONTRACT='(one|One|ONE) contract'
ONE_CONCERN='(one|One|ONE) concern'
ONE_WORKER_RUN='(one|One|ONE) worker run'

check "Step 3 names a leaf test by name" \
  "$(has_re "$STEP3_BODY" "[Ll]eaf test")" "yes"
# NOTE: "one contract" alone is NOT distinguishing — the pre-existing leaf
# sentence ("a block one agent can implement against one contract") already
# contains it. It is asserted anyway so the clause traces to a test, and the
# adjacency check below is what actually pins it as PART OF the leaf test.
check "leaf test part 1: one contract" \
  "$(has_re "$STEP3_BODY" "$ONE_CONTRACT")" "yes"
check "leaf test part 2: one concern" \
  "$(has_re "$STEP3_BODY" "$ONE_CONCERN")" "yes"
check "leaf test part 3: one worker run" \
  "$(has_re "$STEP3_BODY" "$ONE_WORKER_RUN")" "yes"
check "the three leaf-test parts are stated together as one test" \
  "$(near_all 8 "$STEP3_BODY" "$ONE_CONCERN" "$ONE_CONTRACT" "$ONE_WORKER_RUN")" "yes"
# The one-concern part is the "and" test: an "and" joining two separable
# concerns in the name or summary means two concerns.
check "one-concern part tests for an \"and\" joining separable concerns" \
  "$(has_re "$STEP3_BODY" "separable concerns")" "yes"
# The one-worker-run part: one agent session implements it against its tests
# with no mid-flight re-briefing. "re-brief" matches re-brief/re-briefing.
check "one-worker-run part names mid-flight re-briefing as the failure" \
  "$(has_re "$STEP3_BODY" "[Rr]e-brief")" "yes"
# Failing the test means the block is not a leaf — the test is a gate on
# leaf status, not advice. Anchored on "a leaf" in the pass/fail sense
# ("stay a leaf" / "stays a leaf"), which no existing sentence contains.
check "the leaf test gates leaf status (pass it to stay a leaf)" \
  "$(has_re "$STEP3_BODY" "stays? a leaf")" "yes"

# --- 2. Behavior 2: Step 3's per-block content bar ------------------------
# Superseded by Contract: B01 — the bar is no longer a one-line summary but
# an INTERFACE DRAFT (a sketched signature plus all six contract clauses).
# The three elements below are what B01 keeps from the old bar, now carried
# by the signature; the draft-specific clauses (six clauses, prose-block
# outline, Step 4's Interface drafts section, draft-is-draft labeling,
# unchanged block-map entry) are owned by plan-interface-drafts.test.sh.
check "content bar: the draft names the behavior" \
  "$(has_re "$STEP3_BODY" "[Bb]ehavior")" "yes"
# Several spellings of the input/output element are equally correct.
check "content bar: the draft names typed inputs/outputs" \
  "$(has_re "$STEP3_BODY" "[Ii]nputs?.{0,12}[Oo]utputs?")" "yes"
check "content bar: the draft names the primary error mode" \
  "$(has_re "$STEP3_BODY" "[Ee]rror mode")" "yes"
check "content bar: the bar is an interface draft" \
  "$(has_re "$STEP3_BODY" "[Ii]nterface draft")" "yes"
check "content bar: the draft sketches a signature" \
  "$(has_re "$STEP3_BODY" "[Ss]ignature")" "yes"
check "content bar elements are stated together as one bar" \
  "$(near_all 8 "$STEP3_BODY" "[Ee]rror mode" "[Bb]ehavior" "[Ss]ignature")" "yes"
# A block presented without a draft is not plan-complete.
check "a block without a draft is not plan-complete" \
  "$(has_re "$STEP3_BODY" "[Pp]lan-complete")" "yes"
# Invariant: the full contract still lives at materialization, not here.
check "invariant: the full contract is still written at materialization" \
  "$(has_f "$STEP3_BODY" "materialized")" "yes"

# --- 3. Behavior 3: Step 3a's per-block ceiling is DERIVED from the budget -
# The divisor is what the contract fixes, not the budget's spelling: B07
# removes the `delivery.prSizeBudget` config key and makes the budget a plan
# fact, so the derivation now reads off the plain word.
check "Step 3a derives the ceiling from the budget (literal division)" \
  "$(has_re "$STEP3A_SECTION" "[Bb]udget[[:space:]]*/[[:space:]]*2")" "yes"
check "Step 3a names 250 as the default ceiling" \
  "$(has_f "$STEP3A_SECTION" "250")" "yes"
check "Step 3a calls it a ceiling" \
  "$(has_re "$STEP3A_SECTION" "[Cc]eiling")" "yes"
check "Step 3a marks the ceiling as per-block (distinct from the group budget)" \
  "$(has_re "$STEP3A_SECTION" "[Pp]er-block")" "yes"
check "the derivation and the default ceiling are stated together" \
  "$(near_all 4 "$STEP3A_SECTION" "250" "[Cc]eiling")" "yes"

# --- 4. Behavior 3, cont.: the Justification path -------------------------
# The justification is recorded as a `Justification:` FIELD in the block-map
# entry — the capitalised, colon-suffixed field name, not the bare word
# ("justification" already appears in the pre-existing group-level rule).
check "Step 3a records the justification as a Justification: field" \
  "$(has_f "$STEP3A_SECTION" "Justification:")" "yes"
# An over-ceiling block with no justification is a plan defect that blocks
# approval. "defect" alone is pre-existing here; "Step 7" is what pins the
# consequence.
check "Step 3a: an unjustified over-ceiling block blocks Step 7 approval" \
  "$(has_f "$STEP3A_SECTION" "Step 7")" "yes"
check "Step 3a: the defect framing reaches the Step 7 gate" \
  "$(near_all 6 "$STEP3A_SECTION" "Step 7" "[Dd]efect")" "yes"

# --- 5. Behavior 3, cont.: the group-level budget rules stay alongside the
# per-block ceiling (both numbers present, both named). REWRITTEN for
# Contract: B07 — the budget is no longer a config key read from an effective
# config; it is a PLAN FACT recorded in the Landing strategy. The default and
# the group rules are unchanged, so those checks stand as they were ---------
check "Step 3a no longer names a delivery.prSizeBudget config key" \
  "$(has_f "$STEP3A_SECTION" "delivery.prSizeBudget")" "no"
check "Step 3a names the budget as a plan fact" \
  "$(has_re "$STEP3A_SECTION" "(plan fact|recorded in the plan|the plan records|plan-recorded|recorded at plan time)")" "yes"
check "the budget and its 500 default are stated as one plan fact" \
  "$(near_all 4 "$STEP3A_SECTION" "(plan fact|recorded in the plan|the plan records|plan-recorded|recorded at plan time)" "500")" "yes"
check "invariant: Step 3a still names the 500 budget default" \
  "$(has_f "$STEP3A_SECTION" "500")" "yes"
check "invariant: Step 3a still forms PR groups against the budget" \
  "$(has_f "$STEP3A_SECTION" "PR groups")" "yes"

# --- 6. Behavior 3, cont.: no config key at all. The ceiling was always
# DERIVED from the budget; under Contract: B07 the budget itself stops being
# configuration, so the closed world here is now EMPTY — every
# `delivery.<key>` identifier is gone from the document, and reintroducing
# one (including the ceiling as a key of its own) is a contract violation
# even if every other anchor passes -----------------------------------------
DELIVERY_KEYS="$(grep -oE 'delivery\.[A-Za-z]+' <<<"$STRIPPED" | sort -u | tr '\n' ' ')"
check "no delivery.* config key survives anywhere in the skill" \
  "$DELIVERY_KEYS" ""

# --- 7. Edge cases (one bullet = one check) -------------------------------
# Est exactly at the ceiling needs no justification: only strictly greater
# triggers.
check "edge case: only a strictly-over-ceiling Est triggers the requirement" \
  "$(has_re "$STEP3A_SECTION" "[Ss]trictly")" "yes"
# A rough Est (prose/config block) is still subject to the ceiling.
check "edge case: a rough Est is not an exemption from the ceiling" \
  "$(has_re "$STEP3A_SECTION" "[Ee]xemption")" "yes"
# A re-planned block re-passes the leaf test and the ceiling before it is
# scaffolded again.
check "edge case: a re-planned block re-passes the ceiling before re-scaffold" \
  "$(has_re "$STEP3A_SECTION" "[Rr]e-scaffold")" "yes"

# --- 8. Behavior 4: Step 4's block-map entry format documents the optional
# Justification: field ------------------------------------------------------
check "Step 4 entry format shows a Justification: field" \
  "$(has_f "$STEP4_SECTION" "- Justification:")" "yes"
check "Step 4 documents the Justification: field as optional" \
  "$(has_re "$STEP4_SECTION" "[Oo]ptional")" "yes"
# Invariant: the pre-existing entry-format fields are untouched (the new
# field is additive).
for f in "- Status: Planned" "- Owner: agent | engineer" \
         "- Kind: leaf | composition" "- Unit: U<NN>" "- PR group: G<NN>" \
         "- Est: <estimated changed lines>" "- Code: <intended path(s)>"; do
  check "invariant: entry-format field survives: $f" \
    "$(has_f "$STEP4_SECTION" "$f")" "yes"
done

# --- 9. Invariant: the always-blocks subsection is unchanged --------------
# Depth here belongs to plan-lifecycle.test.sh; these are the load-bearing
# sentences an edit to Step 3 is most likely to disturb in passing.
for tok in "at least one block" "exactly two terminal states" \
           "NEVER grounds for" "legitimate, complete plan"; do
  check "invariant: always-blocks token survives: $tok" \
    "$(has_f "$ALWAYS_BLOCKS" "$tok")" "yes"
done
# The new sizing prose belongs in the leaf definition and Step 3a, not
# inside the always-blocks subsection.
check "the ceiling is not introduced inside the always-blocks subsection" \
  "$(has_re "$ALWAYS_BLOCKS" "[Cc]eiling")" "no"

# --- 10. Invariant: question/clarification behavior is untouched ----------
check "invariant: Step 0's question gate survives" \
  "$(has_f "$STEP0_SECTION" "has received an explicit answer")" "yes"
check "invariant: Step 3's decomposition question gate survives" \
  "$(has_f "$STEP3_FULL" "every decomposition question")" "yes"

# --- 11. Invariant: the zone boundaries other suites slice Step 3 on
# survive verbatim. These two sentences bound the reinforcement zone
# skill-gate-reinforcement.test.sh checks; rewording either turns that
# suite's zone empty, so an edit here fails there first with a far less
# obvious message ------------------------------------------------------------
check "invariant: Step 3 zone start anchor survives" \
  "$(has_f "$STEP3_FULL" "may be grouped to share one PR to master/main.")" "yes"
check "invariant: Step 3 zone end anchor survives" \
  "$(has_f "$STEP3_FULL" "Decomposition happens HERE and only here.")" "yes"

# --- 12. Isolation: the new prose does not reference tracking's files -----
for pair in "Step 3 body:$STEP3_BODY" "Step 3a:$STEP3A_SECTION"; do
  label="${pair%%:*}"; body="${pair#*:}"
  check "$label has no TODO.md reference" "$(has_f "$body" "TODO.md")" "no"
  check "$label has no PLAN.md reference" "$(has_f "$body" "PLAN.md")" "no"
done

# === Contract: B08 — Est-includes-tests prose ==============================
# Step 3a's items, sliced individually out of the comment-stripped section.
# The contract appends sentences to item 1 only, so item 1 is where the new
# anchors must read and items 2-3 are held as they are.
STEP3A_ITEM1="$(section_text '1. **Estimate each block' '2. **Feed' <<<"$STEP3A_SECTION")"
STEP3A_ITEM2="$(section_text '2. **Feed' '3. **Form' <<<"$STEP3A_SECTION")"

for pair in "Step 3a item 1:$STEP3A_ITEM1" "Step 3a item 2:$STEP3A_ITEM2"; do
  label="${pair%%:*}"; body="${pair#*:}"
  check "section slice is non-empty: $label" \
    "$([[ -n "$(tr -d '[:space:]' <<<"$body")" ]] && echo yes || echo no)" "yes"
done

# The observed multiple. The contract fixes the observation (2-4x), not its
# typography, so an en dash, a spelled-out range, and "times" for "x" are all
# correct. Written as alternation rather than a bracket class so the "×"
# spelling matches under a C locale too.
TEST_MULTIPLE_RE='(2[^0-9]{1,6}4[[:space:]]*(x|X|×|times)|[Tt]wo[^0-9]{1,8}four[[:space:]]+times)'

# --- 13. Behavior: item 1 states that tests count toward Est and that test
# volume typically dominates -----------------------------------------------
# NOTE: the counting clause is NOT distinguishing on its own — item 1's
# pre-existing opening ("implementation plus its own tests") already states
# it, so these two checks are green before the block is implemented. They are
# asserted anyway so the clause traces to a test AND so that appending the
# new sentences cannot quietly drop the clause they build on.
check "item 1 still counts implementation alongside the block's own tests" \
  "$(has_re "$STEP3A_ITEM1" "[Ii]mplementation plus")" "yes"
check "item 1 still names the block's own tests as part of the estimate" \
  "$(has_re "$STEP3A_ITEM1" "own tests")" "yes"
# The contract's named structural anchor. Case-tolerant only for a
# sentence-initial spelling; the phrase itself is fixed.
check "item 1 carries the \"typically dominates\" anchor" \
  "$(has_re "$STEP3A_ITEM1" "[Tt]ypically dominates")" "yes"
check "item 1 records the observed 2-4x multiple" \
  "$(has_re "$STEP3A_ITEM1" "$TEST_MULTIPLE_RE")" "yes"
# The dominance claim, the multiple, and the tests it is about must read as
# one statement, not as three facts scattered through the item.
check "the dominance claim, the multiple, and tests are stated together" \
  "$(near_all 3 "$STEP3A_ITEM1" "[Tt]ypically dominates" "$TEST_MULTIPLE_RE" "[Tt]ests?")" "yes"
# The consequence the contract asks for: estimates weight tests accordingly
# instead of treating them as a rounding error on the implementation. Both
# framings are correct prose, so either satisfies the check; which one reads
# better is the orchestrator's call at acceptance.
check "item 1 draws the consequence for how estimates weight tests" \
  "$(has_re "$STEP3A_ITEM1" "([Ww]eigh|[Rr]ounding error)")" "yes"

# --- 14. Placement: the new prose lands in Step 3a item 1 ------------------
# Sizing guidance belongs to Step 3a; decomposition (Step 3) is not where the
# estimate rule is stated.
check "the dominance anchor is not introduced in Step 3" \
  "$(has_re "$STEP3_BODY" "[Tt]ypically dominates")" "no"
# Item 2 is the grouping/ceiling item — a correct sentence landing there
# instead of item 1 is a placement failure.
check "the dominance anchor is not introduced in Step 3a item 2" \
  "$(has_re "$STEP3A_ITEM2" "[Tt]ypically dominates")" "no"
# "no new step": Step 3a still holds exactly the three numbered items it
# holds today. Scoped to this section rather than the file's heading list, so
# an unrelated step added elsewhere doesn't fail this contract's suite.
check "Step 3a still has exactly three numbered items" \
  "$(grep -cE '^[0-9]+\. ' <<<"$STEP3A_SECTION")" "3"

# --- 15. Invariants the appended prose must not disturb -------------------
# Item 1's own pre-existing content: the numbers stay rough, and the
# mechanical delivery-time gate is still the thing that actually holds.
check "invariant: item 1 still calls the estimates rough" \
  "$(has_re "$STEP3A_ITEM1" "[Rr]ough")" "yes"
check "invariant: item 1 still points at the mechanical gate at delivery time" \
  "$(has_f "$STEP3A_ITEM1" "pr-size-check.sh")" "yes"
# Est stays an estimate in changed lines — no new unit, no split field.
check "invariant: item 1 still estimates in changed lines" \
  "$(has_f "$STEP3A_ITEM1" "changed lines")" "yes"
# The ceiling and justification rules stay BELOW item 1, unchanged and where
# they are. Their content is pinned by sections 3-4 and 7 above; these two
# checks pin that the edit did not relocate them into item 1's territory.
check "invariant: the per-block ceiling rules still live in item 2" \
  "$(has_re "$STEP3A_ITEM2" "[Cc]eiling")" "yes"
check "invariant: the Justification: path still lives in item 2" \
  "$(has_f "$STEP3A_ITEM2" "Justification:")" "yes"

# === Contract: B14 — plan-skill-split-estimates ============================
# Line number of the first occurrence of a literal string within CONTENT
# (1-indexed), empty when absent. Used for "field X sits above field Y"
# ordering checks the existing near_all/has_f helpers don't express.
field_line() { # content literal
  grep -nF -- "$2" <<<"$1" | head -1 | cut -d: -f1
}

# The observed default multiple (3x). Several spellings are equally correct
# prose, matching the style of B08's TEST_MULTIPLE_RE above.
DEFAULT_MULTIPLE_RE='(3[^0-9]{1,6}(x|X|×|times)|[Tt]hree[^0-9]{1,8}times)'

# --- 16. Behavior: item 1 directs recording an Est-impl:/Est-tests: pair,
# with Est-tests defaulting to 3x Est-impl -----------------------------------
check "item 1 names an Est-impl: field" \
  "$(has_f "$STEP3A_ITEM1" "Est-impl:")" "yes"
check "item 1 names an Est-tests: field" \
  "$(has_f "$STEP3A_ITEM1" "Est-tests:")" "yes"
check "item 1 states the 3x default multiple" \
  "$(has_re "$STEP3A_ITEM1" "$DEFAULT_MULTIPLE_RE")" "yes"
check "item 1 states the default in terms of Est-impl/Est-tests" \
  "$(near_all 6 "$STEP3A_ITEM1" "$DEFAULT_MULTIPLE_RE" "Est-impl:" "Est-tests:")" "yes"

# --- 17. Behavior, cont.: the default is overridable per block with a
# stated reason --------------------------------------------------------------
check "item 1 allows overriding the default" \
  "$(has_re "$STEP3A_ITEM1" "[Oo]verrid")" "yes"
check "item 1 requires a stated reason for an override" \
  "$(has_re "$STEP3A_ITEM1" "[Rr]eason")" "yes"
check "the override and its stated reason are stated together" \
  "$(near_all 6 "$STEP3A_ITEM1" "[Oo]verrid" "[Rr]eason")" "yes"
check "the override is recorded per block, in the entry" \
  "$(near_all 8 "$STEP3A_ITEM1" "[Oo]verrid" "[Ee]ntry")" "yes"

# --- 18. Behavior, cont.: Est: is recorded as the pair's sum, still a bare
# integer — no new unit, no split field --------------------------------------
check "item 1 records Est: as the sum of the pair" \
  "$(has_re "$STEP3A_ITEM1" "[Ss]um")" "yes"
check "item 1 keeps Est: a single, bare integer" \
  "$(has_re "$STEP3A_ITEM1" "([Bb]are integer|single integer|still an integer)")" "yes"
check "the sum and the bare-integer statement are stated together" \
  "$(near_all 8 "$STEP3A_ITEM1" "[Ss]um" "([Bb]are integer|single integer|still an integer)")" "yes"

# --- 19. Edge case: a prose/config block may argue Est-tests down to 0 with
# a stated reason -------------------------------------------------------------
check "item 1 allows arguing Est-tests down to 0" \
  "$(has_re "$STEP3A_ITEM1" "down to 0")" "yes"
check "the down-to-0 edge case carries a stated reason" \
  "$(near_all 8 "$STEP3A_ITEM1" "down to 0" "[Rr]eason")" "yes"

# --- 20. Edge case: an entry without the pair stays valid — Est: alone is
# still a complete estimate ---------------------------------------------------
check "item 1 allows a pair-less entry to stay valid" \
  "$(has_re "$STEP3A_ITEM1" "([Ww]ithout the pair|no pair|pair-less)")" "yes"
check "a pair-less entry's Est: alone is still a complete estimate" \
  "$(near_all 8 "$STEP3A_ITEM1" "([Ww]ithout the pair|no pair|pair-less)" "([Vv]alid|complete)")" "yes"

# --- 21. Invariants: item 1's pre-existing content survives (the suite
# already pins these in section 15 for B08 — repeated here only as an
# explicit B14 trace point, not weakened) -------------------------------------
check "invariant (B14 trace): item 1 still calls the estimates rough" \
  "$(has_re "$STEP3A_ITEM1" "[Rr]ough")" "yes"
check "invariant (B14 trace): item 1 still estimates in changed lines" \
  "$(has_f "$STEP3A_ITEM1" "changed lines")" "yes"
check "invariant (B14 trace): item 1 still points at pr-size-check.sh" \
  "$(has_f "$STEP3A_ITEM1" "pr-size-check.sh")" "yes"
check "invariant (B14 trace): the ceiling rule still lives in item 2" \
  "$(has_re "$STEP3A_ITEM2" "[Cc]eiling")" "yes"
check "invariant (B14 trace): the Justification: path still lives in item 2" \
  "$(has_f "$STEP3A_ITEM2" "Justification:")" "yes"

# --- 22. Placement: the new field pair is introduced in item 1, not item 2 -
check "Est-impl: is not introduced in item 2" \
  "$(has_f "$STEP3A_ITEM2" "Est-impl:")" "no"
check "Est-tests: is not introduced in item 2" \
  "$(has_f "$STEP3A_ITEM2" "Est-tests:")" "no"

# --- 23. Output: Step 4's block-entry template carries the two new field
# lines above Est: -------------------------------------------------------
check "Step 4 template shows an Est-impl: field" \
  "$(has_f "$STEP4_SECTION" "- Est-impl:")" "yes"
check "Step 4 template shows an Est-tests: field" \
  "$(has_f "$STEP4_SECTION" "- Est-tests:")" "yes"

STEP4_ESTIMPL_LINE="$(field_line "$STEP4_SECTION" "- Est-impl:")"
STEP4_ESTTESTS_LINE="$(field_line "$STEP4_SECTION" "- Est-tests:")"
STEP4_EST_LINE="$(field_line "$STEP4_SECTION" "- Est: <estimated changed lines>")"

check "Step 4 template: Est-impl: sits above Est:" \
  "$([[ -n "$STEP4_ESTIMPL_LINE" && -n "$STEP4_EST_LINE" && "$STEP4_ESTIMPL_LINE" -lt "$STEP4_EST_LINE" ]] && echo yes || echo no)" "yes"
check "Step 4 template: Est-tests: sits above Est:" \
  "$([[ -n "$STEP4_ESTTESTS_LINE" && -n "$STEP4_EST_LINE" && "$STEP4_ESTTESTS_LINE" -lt "$STEP4_EST_LINE" ]] && echo yes || echo no)" "yes"
check "Step 4 template: Est-impl: sits above Est-tests:" \
  "$([[ -n "$STEP4_ESTIMPL_LINE" && -n "$STEP4_ESTTESTS_LINE" && "$STEP4_ESTIMPL_LINE" -lt "$STEP4_ESTTESTS_LINE" ]] && echo yes || echo no)" "yes"
check "the pair sits together, immediately above Est:" \
  "$(near_all 2 "$STEP4_SECTION" "^[[:space:]]*- Est-impl:" "^[[:space:]]*- Est-tests:" "^[[:space:]]*- Est: <estimated changed lines>")" "yes"

# --- 24. Cross-file: templates/blocks.md's example entry shows the pair,
# and its Est: equals the pair's sum ------------------------------------------
check "templates/blocks.md example entry shows an Est-impl: field" \
  "$(has_f "$TEMPLATE_RAW" "- Est-impl:")" "yes"
check "templates/blocks.md example entry shows an Est-tests: field" \
  "$(has_f "$TEMPLATE_RAW" "- Est-tests:")" "yes"

TEMPLATE_EST_IMPL_VAL="$(grep -oE -- '- Est-impl:[[:space:]]*[0-9]+' <<<"$TEMPLATE_RAW" | grep -oE '[0-9]+$' | head -1)"
TEMPLATE_EST_TESTS_VAL="$(grep -oE -- '- Est-tests:[[:space:]]*[0-9]+' <<<"$TEMPLATE_RAW" | grep -oE '[0-9]+$' | head -1)"
TEMPLATE_EST_VAL="$(grep -oE -- '- Est:[[:space:]]*[0-9]+' <<<"$TEMPLATE_RAW" | grep -oE '[0-9]+$' | head -1)"

check "templates/blocks.md example: Est-impl: carries a numeric value" \
  "$([[ -n "$TEMPLATE_EST_IMPL_VAL" ]] && echo yes || echo no)" "yes"
check "templates/blocks.md example: Est-tests: carries a numeric value" \
  "$([[ -n "$TEMPLATE_EST_TESTS_VAL" ]] && echo yes || echo no)" "yes"
check "templates/blocks.md example: Est: equals Est-impl: + Est-tests:" \
  "$(( ${TEMPLATE_EST_IMPL_VAL:-0} + ${TEMPLATE_EST_TESTS_VAL:-0} ))" \
  "${TEMPLATE_EST_VAL:-__missing_Est__}"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
