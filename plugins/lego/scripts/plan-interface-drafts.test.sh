#!/bin/bash
# Structural/anchor test for skills/plan/SKILL.md against Contract: B01 —
# plan content bar: Step 3's per-block agreement replaces the one-line-summary
# content bar with an INTERFACE DRAFT (a sketched signature in the repo's
# language — name, typed inputs/outputs, primary error mode — plus all six
# contract clauses drafted), prose/doc blocks carry a heading/anchor outline
# in place of a signature, and Step 4's plan-document spec gains an
# "Interface drafts" section holding one subsection per block.
#
# Method (same as plan-sizing.test.sh, whose harness this mirrors):
#   - HTML comments are stripped before any section is sliced, so the B01
#     contract docblock — which sits directly above "## Step 3" and quotes
#     nearly every anchor below verbatim — can never satisfy a check. Without
#     stripping the red run would be a false green today and would stay green
#     after the docblock is removed at acceptance with no prose ever written.
#   - Tokens the contract fixes are asserted verbatim (fixed-string grep);
#     concepts with several equally-correct spellings use a regex.
#   - Placement is part of the contract: the draft bar must read in Step 3's
#     decomposition body (not in the always-blocks subsection, not in
#     Step 3a), and the Interface drafts section must be listed in Step 4's
#     plan-document item.
#   - "Adjacency": the signature's three elements must be stated together as
#     one bar, and the six clauses as one list, rather than scattered — a
#     line-window check, not independent presence checks.
# Prose semantics beyond tokens/order/adjacency are verified by the
# orchestrator at acceptance.
# Run: bash plugins/lego/scripts/plan-interface-drafts.test.sh  (exits non-zero on failure)

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

has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

has_re() { # content regex
  if grep -qE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

section_text() { # heading_prefix boundary_prefix < text
  awk -v pat="$1" -v stop="$2" '
    index($0, pat) == 1 { capture=1; print; next }
    capture && index($0, stop) == 1 { exit }
    capture { print }
  '
}

# "yes" when some occurrence of the anchor pattern has an occurrence of
# EVERY other pattern within +/- window lines of it.
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

STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")

# Step 3's decomposition body (leaf definition + per-block agreement
# bullets), sliced short of the always-blocks subsection — the contract
# places the interface-draft bar HERE, so a correct bar landing in the
# subsection or in Step 3a is a placement failure, not a pass.
STEP3_BODY="$(section_text '## Step 3: ' '### Every deliverable' <<<"$STRIPPED")"
STEP3_FULL="$(section_text '## Step 3: ' '## Step 3a' <<<"$STRIPPED")"
ALWAYS_BLOCKS="$(section_text '### Every deliverable yields' '## Step 3a' <<<"$STRIPPED")"
STEP3A_SECTION="$(section_text '## Step 3a' '## ' <<<"$STRIPPED")"
STEP4_SECTION="$(section_text '## Step 4' '## ' <<<"$STRIPPED")"

# --- 0. Section slices are non-empty --------------------------------------
for pair in "Step 3 body:$STEP3_BODY" "Step 3a:$STEP3A_SECTION" \
            "Step 4:$STEP4_SECTION" "always-blocks:$ALWAYS_BLOCKS"; do
  label="${pair%%:*}"; body="${pair#*:}"
  check "section slice is non-empty: $label" \
    "$([[ -n "$(tr -d '[:space:]' <<<"$body")" ]] && echo yes || echo no)" "yes"
done

# --- 1. Behavior: Step 3's bar IS an interface draft ----------------------
check "Step 3 names the bar an interface draft" \
  "$(has_re "$STEP3_BODY" "[Ii]nterface draft")" "yes"
# The old bar's framing is gone: the per-block agreement no longer asks for a
# one-line contract summary as the thing that clears the bar.
check "Step 3's agreement bullet no longer asks for a one-line summary" \
  "$(has_f "$STEP3_BODY" "Name and one-line contract summary")" "no"

# --- 2. Behavior: the draft is a SKETCHED SIGNATURE in the repo's language -
check "the draft sketches a signature" \
  "$(has_re "$STEP3_BODY" "[Ss]ignature")" "yes"
# "in the repo's language" — the sketch is written in the target language,
# not in an abstract notation. Several spellings are correct prose.
check "the signature is sketched in the repo's own language" \
  "$(has_re "$STEP3_BODY" "(repo'?s|repository'?s|project'?s|target) language")" "yes"
# The three signature elements the contract fixes.
check "signature element: name" \
  "$(has_re "$STEP3_BODY" "[Nn]ame")" "yes"
check "signature element: typed inputs and outputs" \
  "$(has_re "$STEP3_BODY" "[Tt]yped")" "yes"
check "signature element: inputs/outputs" \
  "$(has_re "$STEP3_BODY" "[Ii]nputs?.{0,12}[Oo]utputs?")" "yes"
check "signature element: primary error mode" \
  "$(has_re "$STEP3_BODY" "[Pp]rimary error mode")" "yes"
check "the signature's elements are stated together as one bar" \
  "$(near_all 6 "$STEP3_BODY" "[Ss]ignature" "[Tt]yped" "[Pp]rimary error mode")" "yes"

# --- 3. Behavior: ALL SIX contract clauses are drafted --------------------
# The clause names are the scaffold docblock's own field names, so they are
# asserted verbatim (case-tolerant on the initial letter only).
for clause in Behavior Inputs Outputs Errors Invariants "Edge cases"; do
  first="${clause:0:1}"; rest="${clause:1}"
  check "draft carries contract clause: $clause" \
    "$(has_re "$STEP3_BODY" "[${first}$(tr '[:upper:]' '[:lower:]' <<<"$first")]${rest}")" "yes"
done
# The count is part of the contract — all six, not a subset.
check "Step 3 states that all six clauses are drafted" \
  "$(has_re "$STEP3_BODY" "(six|SIX|Six|6) (contract )?clauses")" "yes"
check "the six clauses are stated together as one list" \
  "$(near_all 6 "$STEP3_BODY" "[Ii]nvariants" "[Ee]dge cases" "[Ee]rrors" "[Oo]utputs")" "yes"

# --- 4. Behavior: prose/doc blocks carry an outline instead of a signature -
check "prose/doc blocks are named as a variant" \
  "$(has_re "$STEP3_BODY" "[Pp]rose")" "yes"
check "prose blocks carry a heading/anchor outline" \
  "$(has_re "$STEP3_BODY" "[Oo]utline")" "yes"
check "the outline is a heading/anchor outline" \
  "$(has_re "$STEP3_BODY" "([Hh]eading|[Aa]nchor)")" "yes"
# Same six clauses apply to the prose variant — the outline replaces only the
# signature, never the clauses.
check "the prose variant carries the same six clauses" \
  "$(near_all 6 "$STEP3_BODY" "[Oo]utline" "(six|SIX|Six|6) (contract )?clauses")" "yes"
check "the outline stands in place of a signature" \
  "$(near_all 4 "$STEP3_BODY" "[Oo]utline" "[Ss]ignature")" "yes"

# --- 5. Inputs: Step 2's brownfield discovery feeds the sketches ----------
# The contract names Step 2's recorded existing interfaces as the raw
# material for the draft; the bar must point at them rather than inviting a
# from-scratch invention.
check "the draft bar points back at Step 2's discovery as raw material" \
  "$(has_re "$STEP3_BODY" "Step 2")" "yes"
check "existing interfaces are named as the material for the sketch" \
  "$(has_re "$STEP3_BODY" "existing interfaces?")" "yes"

# --- 6. Outputs: Step 4's plan document gains an Interface drafts section --
check "Step 4's plan document lists an Interface drafts section" \
  "$(has_f "$STEP4_SECTION" "Interface drafts")" "yes"
# One subsection per block holds that block's draft.
check "the Interface drafts section holds one subsection per block" \
  "$(near_all 6 "$STEP4_SECTION" "Interface drafts" "(subsection|one per block|per block)")" "yes"
# Placement: it belongs to the plan-document item (item 1), not to the
# block-map entry item.
STEP4_ITEM1="$(section_text '1. **Plan document**' '2. **Block map' <<<"$STEP4_SECTION")"
check "section slice is non-empty: Step 4 item 1" \
  "$([[ -n "$(tr -d '[:space:]' <<<"$STEP4_ITEM1")" ]] && echo yes || echo no)" "yes"
check "the Interface drafts section is specified in the plan-document item" \
  "$(has_f "$STEP4_ITEM1" "Interface drafts")" "yes"

# --- 7. Outputs: the block-map entry format is UNCHANGED ------------------
# The .local/blocks.md entry keeps its one-line Contract: summary as an
# index — the contract asks for this to be stated explicitly, and asks that
# no draft field be added to the entry format.
STEP4_ENTRY="$(section_text '2. **Block map entries**' '## ' <<<"$STEP4_SECTION")"
check "section slice is non-empty: Step 4 block-map entry item" \
  "$([[ -n "$(tr -d '[:space:]' <<<"$STEP4_ENTRY")" ]] && echo yes || echo no)" "yes"
check "invariant: the entry still carries the one-line Contract: summary" \
  "$(has_f "$STEP4_ENTRY" "- Contract: <one-line summary")" "yes"
for f in "- Status: Planned" "- Owner: agent | engineer" \
         "- Kind: leaf | composition" "- Deps: B<NN>, ... | none" \
         "- Unit: U<NN>" "- PR group: G<NN>" \
         "- Est: <estimated changed lines>" "- Code: <intended path(s)>" \
         "- Plan: plans/NNN-<slug>.md"; do
  check "invariant: entry-format field survives: $f" \
    "$(has_f "$STEP4_ENTRY" "$f")" "yes"
done
# No interface-draft field is smuggled into the entry format.
check "no Interface draft field is added to the block-map entry format" \
  "$(has_re "$STEP4_ENTRY" "^- (Interface|Draft|Signature)")" "no"
# The unchanged-ness is stated explicitly, and the summary's role is named
# as an index into the drafts rather than the draft itself.
check "the entry format's one-line summary is explicitly kept as an index" \
  "$(has_re "$STEP4_SECTION" "index")" "yes"

# --- 8. Errors: a draftless block is not plan-complete and blocks Step 5 ---
check "a block without a draft is not plan-complete" \
  "$(has_f "$STEP3_BODY" "plan-complete")" "yes"
check "a prose block without an outline is likewise not plan-complete" \
  "$(near_all 6 "$STEP3_BODY" "plan-complete" "[Oo]utline")" "yes"
check "the defect blocks Step 5 approval" \
  "$(has_f "$STEP3_BODY" "Step 5")" "yes"
# The same defect language the sizing rules use.
check "the failure is framed as a plan defect" \
  "$(has_re "$STEP3_BODY" "[Dd]efect")" "yes"
check "the defect framing reaches the Step 5 gate" \
  "$(near_all 6 "$STEP3_BODY" "Step 5" "[Dd]efect")" "yes"

# --- 9. Invariants: the draft is a DRAFT; the stub docblock is authoritative
check "the plan's draft is explicitly labeled a draft" \
  "$(has_re "$STEP3_BODY" "[Dd]raft")" "yes"
check "the stub docblock remains the authoritative contract" \
  "$(has_re "$STEP3_BODY" "[Aa]uthoritative")" "yes"
check "scaffold is named as what finalizes the draft" \
  "$(has_re "$STEP3_BODY" "(scaffold|Scaffold)")" "yes"
check "draft-vs-authoritative is stated as one rule" \
  "$(near_all 6 "$STEP3_BODY" "[Aa]uthoritative" "[Dd]raft" "(scaffold|Scaffold)")" "yes"
# The pre-existing invariants the edit must not disturb.
check "invariant: the leaf test survives in Step 3" \
  "$(has_re "$STEP3_BODY" "[Ll]eaf test")" "yes"
check "invariant: Step 3 still agrees Deps, Kind, Owner, paths, unit, PR group" \
  "$(has_f "$STEP3_BODY" "Owner: agent or engineer")" "yes"
check "invariant: PR grouping bullet survives" \
  "$(has_f "$STEP3_BODY" "PR group")" "yes"
check "invariant: Step 3a sizing still owns the ceiling" \
  "$(has_re "$STEP3A_SECTION" "[Cc]eiling")" "yes"
check "invariant: Step 3's decomposition question gate survives" \
  "$(has_f "$STEP3_FULL" "every decomposition question")" "yes"
check "invariant: Step 3 zone end anchor survives" \
  "$(has_f "$STEP3_FULL" "Decomposition happens HERE and only here.")" "yes"

# --- 10. Edge case: engineer-owned blocks get the same bar, no exemption ---
check "engineer-owned blocks are named in the draft rule" \
  "$(has_re "$STEP3_BODY" "[Ee]ngineer-owned")" "yes"
check "engineer-owned blocks get the same bar with no exemption" \
  "$(near_all 6 "$STEP3_BODY" "[Ee]ngineer-owned" "(exemption|exempt|same bar|no exception)")" "yes"

# --- 11. Edge case: mid-dispatch re-plans re-pass the bar -----------------
check "a mid-dispatch re-plan updates the draft" \
  "$(has_re "$STEP3_BODY" "re-plan")" "yes"
check "an updated draft re-passes the bar before re-scaffold" \
  "$(near_all 6 "$STEP3_BODY" "re-plan" "re-scaffold")" "yes"

# --- 12. Placement: the draft bar does not leak into neighbouring sections -
check "the interface-draft bar is not introduced in the always-blocks subsection" \
  "$(has_re "$ALWAYS_BLOCKS" "[Ii]nterface draft")" "no"
check "the interface-draft bar is not introduced in Step 3a" \
  "$(has_re "$STEP3A_SECTION" "[Ii]nterface draft")" "no"

# --- 13. Isolation: the new prose references no sibling plugin's files ----
for pair in "Step 3 body:$STEP3_BODY" "Step 4:$STEP4_SECTION"; do
  label="${pair%%:*}"; body="${pair#*:}"
  check "$label has no TODO.md reference" "$(has_f "$body" "TODO.md")" "no"
  check "$label has no PLAN.md reference" "$(has_f "$body" "PLAN.md")" "no"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
