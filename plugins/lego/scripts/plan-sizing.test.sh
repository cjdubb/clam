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
#   - "No new config key": the set of `delivery.<key>` identifiers named in
#     the file is unchanged — the ceiling is DERIVED from the budget, so a
#     new key is a contract violation even if every other anchor passes.
# This file does not test prose semantics beyond tokens/order/adjacency —
# meaning is verified by the orchestrator at acceptance.
# Run: bash plugins/lego/scripts/plan-sizing.test.sh   (exits non-zero on failure)

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
  mapfile -t anchor_lines < <(grep -nE -- "$anchor" <<<"$content" | cut -d: -f1)
  local a o tok ok
  for a in "${anchor_lines[@]}"; do
    ok=yes
    for tok in "$@"; do
      mapfile -t other_lines < <(grep -nE -- "$tok" <<<"$content" | cut -d: -f1)
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

RAW=$(cat "$SKILL")
# Comment-stripped view — see the header note. Every section below is sliced
# out of THIS, never out of $RAW.
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")

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
# The one-concern part is the "and" test: an "and" doing load-bearing work
# in the name or summary means two concerns.
check "one-concern part tests for a load-bearing \"and\"" \
  "$(has_re "$STEP3_BODY" "[Ll]oad-bearing")" "yes"
# The one-worker-run part: one agent session implements it against its tests
# with no mid-flight re-briefing. "re-brief" matches re-brief/re-briefing.
check "one-worker-run part names mid-flight re-briefing as the failure" \
  "$(has_re "$STEP3_BODY" "[Rr]e-brief")" "yes"
# Failing the test means the block is not a leaf — the test is a gate on
# leaf status, not advice. Anchored on "a leaf" in the pass/fail sense
# ("stay a leaf" / "stays a leaf"), which no existing sentence contains.
check "the leaf test gates leaf status (pass it to stay a leaf)" \
  "$(has_re "$STEP3_BODY" "stays? a leaf")" "yes"

# --- 2. Behavior 2: the one-line contract summary has a content bar --------
check "content bar: the summary names the behavior" \
  "$(has_re "$STEP3_BODY" "[Bb]ehavior")" "yes"
# Several spellings of the input/output element are equally correct.
check "content bar: the summary names the input->output shape" \
  "$(has_re "$STEP3_BODY" "[Ii]nputs?.{0,12}[Oo]utputs?")" "yes"
check "content bar: the summary names the primary error mode" \
  "$(has_re "$STEP3_BODY" "[Ee]rror mode")" "yes"
check "content bar elements are stated together as one bar" \
  "$(near_all 6 "$STEP3_BODY" "[Ee]rror mode" "[Bb]ehavior")" "yes"
# A summary missing any of the three is not plan-complete.
check "a summary missing an element is not plan-complete" \
  "$(has_re "$STEP3_BODY" "[Pp]lan-complete")" "yes"
# Invariant: the full contract still lives at scaffold, not here.
check "invariant: the full contract is still written at scaffold" \
  "$(has_f "$STEP3_BODY" "at scaffold")" "yes"

# --- 3. Behavior 3: Step 3a's per-block ceiling is DERIVED from the budget -
check "Step 3a derives the ceiling from prSizeBudget (literal division)" \
  "$(has_re "$STEP3A_SECTION" "prSizeBudget[[:space:]]*/[[:space:]]*2")" "yes"
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
# approval. "defect" alone is pre-existing here; "Step 5" is what pins the
# consequence.
check "Step 3a: an unjustified over-ceiling block blocks Step 5 approval" \
  "$(has_f "$STEP3A_SECTION" "Step 5")" "yes"
check "Step 3a: the defect framing reaches the Step 5 gate" \
  "$(near_all 6 "$STEP3A_SECTION" "Step 5" "[Dd]efect")" "yes"

# --- 5. Behavior 3, cont.: invariant — the group-level budget rules stay
# alongside the new per-block ceiling (both numbers present, both named) ---
check "invariant: Step 3a still names delivery.prSizeBudget" \
  "$(has_f "$STEP3A_SECTION" "delivery.prSizeBudget")" "yes"
check "invariant: Step 3a still names the 500 budget default" \
  "$(has_f "$STEP3A_SECTION" "500")" "yes"
check "invariant: Step 3a still forms PR groups against the budget" \
  "$(has_f "$STEP3A_SECTION" "PR groups")" "yes"

# --- 6. Behavior 3, cont.: no new config key. The ceiling is derived, so
# the set of delivery.<key> identifiers the skill names must not grow ------
DELIVERY_KEYS="$(grep -oE 'delivery\.[A-Za-z]+' <<<"$STRIPPED" | sort -u | tr '\n' ' ')"
check "no new delivery.* config key is introduced" \
  "$DELIVERY_KEYS" "delivery.mode delivery.prSizeBudget delivery.worktreeDir "

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

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
