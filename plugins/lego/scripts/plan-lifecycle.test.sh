#!/bin/bash
# Structural/anchor test for skills/plan/SKILL.md against Contract: B07
# lego-plan-lifecycle, Contract: 001-B02 premise-invalid-closure, and
# Contract: 001-B01 plan-always-blocks.
#
# Sections 9-14 extend the same approach to Contract: B07 —
# plan-skill-discover-and-prove (plan 001-lego-config-redesign): Step 1 stops
# creating a config interface and becomes "Discover and prove the repo's
# commands" (autodetect, agree, EXECUTE once, then record); the Standing
# rules state the orchestrator-only delivery-knowledge invariant; Step 5's
# prose-contract note names the ORCHESTRATOR as the deleter at acceptance;
# Step 6's rung ladder reads plan-recorded commands; and no config-file
# identifier survives anywhere in the document. Note that B07 renames the
# Step 1 heading, so section 8's surviving-heading loop pins the NEW heading —
# a checkout still carrying "Ensure the repo interface exists" fails there as
# well as in section 9.
#
# This skill is a documentation block,
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
#   - "Links rule" (Contract: 003-B24): Step 4's plan-document specification
#     requires every artifact the plan references to be carried as a relative
#     markdown link. Located as well as present — inside Step 4's item 1 (the
#     plan document) rather than item 2 (the block map), and stated in no
#     other step.
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

# Extended-regex presence check. Used ONLY where the contract fixes a concept
# whose correct spellings genuinely vary; everything else is has_f.
has_re() { # content regex
  if grep -qE -- "$2" <<<"$1"; then echo yes; else echo no; fi
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

# Text of a section bounded by an EXPLICIT stop prefix rather than the next
# "## " heading — lets a "## " section be sliced short of its own "### "
# subsection (Step 6 short of Step 6a, Standing rules short of Step 0a).
section_between() { # heading_prefix stop_prefix < text
  awk -v pat="$1" -v stop="$2" '
    index($0, pat) == 1 { capture=1; print; next }
    capture && index($0, stop) == 1 { exit }
    capture { print }
  '
}

# "yes" when some occurrence of the anchor pattern has an occurrence of EVERY
# other pattern within +/- window lines of it — i.e. the parts are stated
# together as one rule rather than scattered across the section. Patterns are
# extended regexes, matching has_re.
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

# Outputs: >=1 block presented at the approval gate (Step 7), trivial blocks marked not omitted.
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

# --- 7b. Contract: 003-B24 plan-skill links rule (within Step 4 only) ------
# One group per docblock clause. Stripped text, for the same reason as every
# other section-token group here: 003-B24's own docblock states the rule it
# requires, so matching against the raw file would pass while Step 4's prose
# still says nothing about links.
STEP4_SECTION="$(section_text '## Step 4: Write the artifacts' <<<"$STRIPPED")"

# Behavior: every referenced artifact is carried as a relative markdown link,
# never a bare path, so a served or previewed plan reaches it in one click.
for tok in "relative markdown link" "bare path" "one click"; do
  check "Step 4 links-rule Behavior token: $tok" \
    "$(has_f "$STEP4_SECTION" "$tok")" "yes"
done

# Behavior: the three kinds of referenced artifact the rule names. "decision
# file" and not bare "decision" — Step 4 already says "sizing decisions", so
# the shorter token would pass without a word of the rule being written.
for tok in "decision file" "protocol" "sibling plan"; do
  check "Step 4 links-rule artifact kind: $tok" \
    "$(has_f "$STEP4_SECTION" "$tok")" "yes"
done

# Outputs: "an added requirement inside Step 4's plan-document
# specification" — item 1, which specifies the plan document, and not item 2,
# which specifies the block map: a different artifact, in a different file,
# whose entries are a fixed field list rather than prose.
PLANDOC_LINE=$(first_heading_line '1. **Plan document**')
BLOCKMAP_LINE=$(first_heading_line '2. **Block map entries**')
LINKRULE_LINE=$(first_heading_line 'relative markdown link')
check_after "links rule sits inside Step 4's plan-document item" \
  "$LINKRULE_LINE" "$PLANDOC_LINE"
check_before "links rule precedes the block-map item" \
  "$LINKRULE_LINE" "$BLOCKMAP_LINE"

# Invariants: "no other step's guidance changes; the rule is stated once, in
# Step 4, where the plan document's contents are specified." Step 4 is
# covered by the token checks above; every other top-level section must be
# free of it, so the rule cannot end up restated at the point of use.
for h in '## Step 0a' '## Step 0:' '## Step 1:' '## Step 2:' '## Step 3:' '## Step 5:' '## Step 6:' '## Step 7:' '## Step 8:'; do
  check "links rule is not restated in $h" \
    "$(has_f "$(section_text "$h" <<<"$STRIPPED")" "relative markdown link")" "no"
done

# Edge case: an artifact that does not exist yet when the plan is written is
# linked when it is first referenced, not left as a bare name until later.
check "Step 4 links-rule Edge case: linked when first referenced" \
  "$(has_f "$STEP4_SECTION" "first referenced")" "yes"

# Edge case: a reference outside the plan file's own worktree is still
# written as a link wherever a resolvable relative path exists.
check "Step 4 links-rule Edge case: a reference outside the plan's worktree" \
  "$(has_f "$STEP4_SECTION" "outside the plan")" "yes"

# === Contract: B07 — plan-skill-discover-and-prove =========================
# Every slice below comes from $STRIPPED for the reason stated in the file
# header: B07's own docblock sits at the top of the file and quotes nearly
# every anchor here verbatim ("EXECUTED", "scratch worktree",
# "Setup:"/"Test:", "orchestrator-only"), so a check written against $RAW
# would pass today off the comment and keep passing after the comment is
# removed at acceptance with no prose ever written. The two heading checks
# are the exception: a heading is not comment text, so they read $RAW.

STANDING_RULES="$(section_between '## Standing rules' '## Step 0a' <<<"$STRIPPED")"
STEP1_SECTION="$(section_text '## Step 1' <<<"$STRIPPED")"
STEP5_SECTION="$(section_text '## Step 5' <<<"$STRIPPED")"
STEP6_BODY="$(section_between '## Step 6' '### Step 6a' <<<"$STRIPPED")"
STEP6A_SECTION="$(section_text '### Step 6a' <<<"$STRIPPED")"

# --- 9. Section slices are non-empty (an empty slice would fail every token
# check below for the wrong reason) -----------------------------------------
for pair in "Standing rules:$STANDING_RULES" "Step 1:$STEP1_SECTION" \
            "Step 5:$STEP5_SECTION" "Step 6 body:$STEP6_BODY" \
            "Step 6a:$STEP6A_SECTION"; do
  label="${pair%%:*}"; body="${pair#*:}"
  check "section slice is non-empty: $label" \
    "$([[ -n "$(tr -d '[:space:]' <<<"$body")" ]] && echo yes || echo no)" "yes"
done

# --- 10. Behavior 1: Step 1 IS the discover-and-prove step -----------------
check "Step 1 is the discover-and-prove step" \
  "$(has_f "$RAW" '## Step 1: Discover and prove')" "yes"
check "the old repo-interface Step 1 heading is gone" \
  "$(has_f "$RAW" 'Ensure the repo interface exists')" "no"
# Step 1's own sequence: autodetect candidates -> agree with the engineer ->
# EXECUTE each agreed command once -> only then record it.
check "Step 1 still autodetects candidate commands" \
  "$(has_re "$STEP1_SECTION" "[Aa]utodetect")" "yes"
check "Step 1 still agrees the candidates with the engineer" \
  "$(has_re "$STEP1_SECTION" "engineer")" "yes"
check "Step 1 executes each agreed command" \
  "$(has_re "$STEP1_SECTION" "[Ee]xecut")" "yes"
check "Step 1 frames the execution as proof" \
  "$(has_re "$STEP1_SECTION" "([Pp]rove|[Pp]roof|[Pp]roven|[Pp]roving)")" "yes"
check "Step 1 runs the command once" \
  "$(has_re "$STEP1_SECTION" "once")" "yes"
check "Step 1 names the scratch worktree as where proving happens when feasible" \
  "$(has_re "$STEP1_SECTION" "scratch worktree")" "yes"
check "Step 1 names the Setup command" \
  "$(has_re "$STEP1_SECTION" "[Ss]etup")" "yes"
check "Step 1 names the Test command" \
  "$(has_re "$STEP1_SECTION" "[Tt]est")" "yes"

# Invariant 2: proof by execution PRECEDES recording — the two must read as
# one ordered rule, not as two unrelated sentences.
check "Step 1 states that recording follows execution" \
  "$(near_all 6 "$STEP1_SECTION" "[Ee]xecut" "[Rr]ecord" "before")" "yes"
# The commands are recorded per block, in the block map, at Step 4 — Step 1
# proves them and points at where they land.
check "Step 1 points at blocks.md as where the commands are recorded" \
  "$(has_f "$STEP1_SECTION" "blocks.md")" "yes"
check "Step 1 points at Step 4 as when the commands are recorded" \
  "$(has_f "$STEP1_SECTION" "Step 4")" "yes"

# Behavior 1, cont.: no interface files are created or committed here. The
# global absence checks in section 13 cover the identifiers file-wide; these
# pin the flow's disappearance from the step that used to carry it.
check "Step 1 no longer creates a committed config file" \
  "$(has_f "$STEP1_SECTION" "lego.json")" "no"
check "Step 1 no longer offers a local config override" \
  "$(has_f "$STEP1_SECTION" "config.json")" "no"
# The delivery mode is a plan fact recorded at Step 3a / in the Landing
# strategy (pinned by plan-landing-strategy.test.sh), so Step 1 does not ask
# for it any more.
check "Step 1 no longer asks the engineer for the delivery mode" \
  "$(has_re "$STEP1_SECTION" "[Dd]elivery mode")" "no"

# Invariant 3: Step 1's non-config semantics are unchanged. Step 0a defers
# its plan-doc write "until immediately after Step 1 creates `.local/plans/`",
# so these three are load-bearing for other steps, not incidental.
for tok in ".git/info/exclude" ".local/blocks.md" ".local/plans/" \
           "templates/blocks.md"; do
  check "invariant: Step 1 still does its non-config work: $tok" \
    "$(has_f "$STEP1_SECTION" "$tok")" "yes"
done

# Edge case: a repo where proving needs infrastructure proves the cheapest
# honest tier and records the caveat in the plan document.
check "Step 1 edge case: proving that needs infrastructure is named" \
  "$(has_re "$STEP1_SECTION" "infrastructure")" "yes"
check "Step 1 edge case: prove the cheapest honest tier" \
  "$(has_re "$STEP1_SECTION" "cheapest")" "yes"
check "Step 1 edge case: the caveat is recorded in the plan document" \
  "$(has_re "$STEP1_SECTION" "caveat")" "yes"
check "the cheapest-tier fallback and its recorded caveat are one rule" \
  "$(near_all 4 "$STEP1_SECTION" "cheapest" "caveat")" "yes"

check "Step 1 section has no TODO.md reference" \
  "$(has_f "$STEP1_SECTION" "TODO.md")" "no"

# --- 11. Behavior: the Standing rules state the orchestrator-only
# delivery-knowledge invariant ----------------------------------------------
check "Standing rules name delivery knowledge" \
  "$(has_re "$STANDING_RULES" "[Dd]elivery")" "yes"
check "Standing rules make delivery knowledge orchestrator-only" \
  "$(has_re "$STANDING_RULES" "(orchestrator-only|only the orchestrator|orchestrator business|never a worker)")" "yes"
# What "delivery knowledge" covers, and who it is withheld from, must read as
# one rule rather than as words scattered through the section.
check "the invariant names the budget/mode/grouping facts and the worker together" \
  "$(near_all 6 "$STANDING_RULES" "[Dd]elivery" "(budget|mode|PR group)" "[Ww]orker")" "yes"
# Invariant 3: the pre-existing standing rules survive.
for tok in "Clarify and verify; never guess." "Workers NEVER design" \
           "Owner: engineer" "explicitly answered before proceeding"; do
  check "invariant: standing rule survives: $tok" \
    "$(has_f "$STANDING_RULES" "$tok")" "yes"
done

# --- 12. Behavior: Step 5's prose-contract note names the ORCHESTRATOR as
# the deleter, at acceptance (decisions/003 ruling 2) ------------------------
check "Step 5 says the orchestrator deletes the prose contract" \
  "$(has_re "$STEP5_SECTION" "[Oo]rchestrator deletes")" "yes"
check "the deletion is placed at acceptance" \
  "$(near_all 4 "$STEP5_SECTION" "[Oo]rchestrator deletes" "acceptance")" "yes"
check "the implementation wave is no longer the deleter" \
  "$(has_f "$STEP5_SECTION" "The implementation wave deletes the comment")" "no"
# Invariant: everything else about the prose-block exception is unchanged.
for tok in "Prose blocks are the exception" \
           "Runtime-present" "authoritative contract" \
           "moved into the"; do
  check "invariant: Step 5 token survives: $tok" \
    "$(has_f "$STEP5_SECTION" "$tok")" "yes"
done
# The `(remove at acceptance)` marker Step 5 tells the orchestrator to write
# lives inside an EXAMPLE HTML comment, which $STRIPPED removes along with
# the real docblocks — so this one invariant reads the raw section. It is an
# invariant, not a B07 anchor: the marker's wording is unchanged, only who
# acts on it is.
STEP5_SECTION_RAW="$(section_text '## Step 5' <<<"$RAW")"
check "invariant: Step 5 still writes the (remove at acceptance) marker" \
  "$(has_f "$STEP5_SECTION_RAW" "(remove at acceptance)")" "yes"

# --- 13. Behavior: Step 6's rung ladder reads plan-recorded commands -------
check "Step 6 reads the commands the plan recorded" \
  "$(has_re "$STEP6_BODY" "(plan-recorded|recorded in the plan|the plan records|plan's recorded|recorded at plan time)")" "yes"
check "Step 6 no longer resolves commands from an effective config" \
  "$(has_f "$STEP6_BODY" "effective config")" "no"
# Invariant: the ladder itself — rung 0 and the four composition rungs — is
# unchanged; only where the commands come from moves.
for tok in "Rung 0" "blocks-lint.sh" "typecheck" "build" "lint" \
           "Record which rung ran"; do
  check "invariant: Step 6 rung ladder token survives: $tok" \
    "$(has_f "$STEP6_BODY" "$tok")" "yes"
done
# Invariant: Step 6a's review-gated semantics are untouched by B07.
for tok in "review-gated" "Decide by clause, not by convenience." \
           "configuration whose only" "engineer-owned"; do
  check "invariant: Step 6a token survives: $tok" \
    "$(has_f "$STEP6A_SECTION" "$tok")" "yes"
done

# --- 14. Invariant 1: no instruction anywhere to create, commit, or read a
# config file. Global over the comment-stripped document: an identifier that
# survives in any step is a contract violation even if every anchor above
# passes. "config"/"configuration" as ordinary English is NOT banned — Step
# 3a's "a rough Est on a prose or config block" and Step 6a's "configuration
# whose only assertion is its own literal content" are pre-existing, correct
# prose about a KIND OF BLOCK, and Invariant 3 requires them to survive ------
for tok in "lego.json" "config.json" "config-schema" "testPatterns" \
           "models.testWriter" "models.implementer" "commands.test" \
           "effective config"; do
  check "no config-interface reference survives: $tok" \
    "$(has_f "$STRIPPED" "$tok")" "no"
done
check "no delivery.<key> config identifier survives" \
  "$(has_re "$STRIPPED" "delivery\.[A-Za-z]")" "no"
check "invariant 3: Step 6a's config-block prose is untouched by the purge" \
  "$(has_f "$STEP6A_SECTION" "configuration whose only")" "yes"

# --- 15. Original steps preserved (headings intact). Step 1's heading is
# B07's new one — see the file header ----------------------------------------
for h in "## Step 0: Establish the deliverable — a hard gate" \
         "## Step 1: Discover and prove" \
         "## Step 2: Brownfield discovery (skip only in an empty repo)" \
         "## Step 3: Decompose with the engineer" \
         "## Step 4: Write the artifacts" \
         "## Step 7: Approval gate"; do
  check "original heading survives: $h" "$(has_f "$RAW" "$h")" "yes"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
