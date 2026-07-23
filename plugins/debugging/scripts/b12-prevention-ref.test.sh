#!/usr/bin/env bash
# Structural/content test for references/prevention.md against
# Contract: B12 ref-prevention (see the HTML-comment docblock in that file).
#
# This reference doc is pure guidance markdown (no frontmatter), so the tests
# here are:
#   - H1 title present, followed by a "When to use" line before the first H2
#   - the exact required H2 section set AND order (Name the defect class ->
#     Sweep for latent instances -> Choose a guardrail layer -> Decide and
#     record -> Journal), with no extra/missing/reordered sections
#   - per-section anchor checks: each section's body must contain the stable
#     terms a faithful implementation of that section could not avoid using,
#     including the instance-vs-class distinction, the sweep's method/scope/
#     results with "0 found" as a valid outcome and the paste-back access
#     rule, the guardrail ladder rungs in strongest-first order, propose-by-
#     default with decline requiring a cost/benefit rationale plus engineer
#     sign-off, and journaling into the Prevention section
#   - invariants: building the guardrail is never worded as unconditionally
#     mandatory; the ritual-guardrail warning is present; the engineer (not
#     the orchestrator) decides build/decline; guardrail work is scoped
#     outside the current fix unless the engineer folds it in
#   - edge cases: one-off causes still get the analysis with a justified "no
#     guardrail warranted"; out-of-scope sweep findings are surfaced, never
#     silently folded in; an already-existing guardrail is verified against
#     "would it have caught this instance?"
#
# All anchor/section checks run against the body with the contract's own
# HTML-comment docblock stripped (sed '/<!--/,/-->/d'), so the docblock's own
# prose can never satisfy a check meant for the real implementation.
#
# These MUST fail against the current NotImplemented(B12) stub and MUST pass
# once a real doc satisfies the contract.
# Run: bash plugins/debugging/scripts/b12-prevention-ref.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="$SCRIPT_DIR/../skills/root-cause/references/prevention.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "prevention.md exists at the contract's Code path" \
  "$([ -f "$DOC" ] && echo yes || echo no)" "yes"

if [[ ! -f "$DOC" ]]; then
  echo "FAILURES (doc missing, cannot continue)"
  exit 1
fi

# Case-insensitive extended-regex presence check over a blob of text.
has() { # content pattern
  if grep -qiE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Fixed-string (literal) presence check, case-sensitive.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Rendered body with the contract's HTML-comment docblock stripped, so
# anchor checks can only be satisfied by real implementation prose.
BODY=$(sed '/<!--/,/-->/d' "$DOC")

# Extract the text of one '## Exact Heading' section (up to the next '## '
# header or EOF) from BODY.
section() { # exact_header
  awk -v h="$1" '
    $0 == h {found=1; next}
    /^## / {if (found) exit}
    found {print}
  ' <<<"$BODY"
}

# Preamble: everything before the first H2 heading (H1 title + "When to use"
# line live here).
PREAMBLE=$(awk '/^## /{exit} {print}' <<<"$BODY")

# Collapse newlines/repeated whitespace to single spaces, so multi-word
# phrase checks match regardless of where the prose happens to line-wrap —
# wrapping is a formatting choice the contract does not constrain.
flat() { printf '%s' "$1" | tr '\n' ' ' | tr -s '[:space:]' ' '; }

FBODY=$(flat "$BODY")
FPREAMBLE=$(flat "$PREAMBLE")

# ===========================================================================
# Outputs: H1 title, "When to use" line, exact H2 section set AND order.
# ===========================================================================

check "H1 title present" \
  "$(grep -qE '^# [^#]' <<<"$BODY" && echo yes || echo no)" "yes"

check "'When to use' line present before the first H2" \
  "$(has "$FPREAMBLE" 'when to use')" "yes"

for h in "## Name the defect class" "## Sweep for latent instances" \
         "## Choose a guardrail layer" "## Decide and record" "## Journal"; do
  check "required section exists: $h" "$(has_f "$BODY" "$h")" "yes"
done

# "Exactly this set and order": the doc's H2 headings, in file order, must
# equal the contracted headings, in contracted order.
EXPECTED_HEADINGS='## Name the defect class
## Sweep for latent instances
## Choose a guardrail layer
## Decide and record
## Journal'

ACTUAL_HEADINGS=$(grep -E '^## ' <<<"$BODY")
check "H2 sections are exactly the contracted set, in the contracted order" \
  "$ACTUAL_HEADINGS" "$EXPECTED_HEADINGS"

NAME_CLASS=$(section "## Name the defect class")
SWEEP=$(section "## Sweep for latent instances")
GUARDRAIL=$(section "## Choose a guardrail layer")
DECIDE=$(section "## Decide and record")
JOURNAL=$(section "## Journal")

FNAME_CLASS=$(flat "$NAME_CLASS")
FSWEEP=$(flat "$SWEEP")
FGUARDRAIL=$(flat "$GUARDRAIL")
FDECIDE=$(flat "$DECIDE")
FJOURNAL=$(flat "$JOURNAL")

for pair in "Name the defect class:$NAME_CLASS" "Sweep for latent instances:$SWEEP" \
            "Choose a guardrail layer:$GUARDRAIL" "Decide and record:$DECIDE" \
            "Journal:$JOURNAL"; do
  label="${pair%%:*}"; content="${pair#*:}"
  check "$label section is non-empty" \
    "$(grep -qv '^[[:space:]]*$' <<<"$content" && echo yes || echo no)" "yes"
done

# --- Name the defect class: instance vs class distinction, mechanically ----
# --- checkable class membership --------------------------------------------
check "name-class: generalizes to a property of the system" \
  "$([[ "$(has "$FNAME_CLASS" 'class')" == "yes" && "$(has "$FNAME_CLASS" 'property')" == "yes" ]] && echo yes || echo no)" "yes"
check "name-class: class membership is mechanically checkable" \
  "$(has "$FNAME_CLASS" 'mechanically checkable')" "yes"
check "name-class: distinguishes instance-level prevention" \
  "$(has "$FNAME_CLASS" 'instance[- ]level')" "yes"
check "name-class: distinguishes class-level prevention" \
  "$(has "$FNAME_CLASS" 'class[- ]level')" "yes"
check "name-class: instance-level prevention is the regression test from wrap-up" \
  "$([[ "$(has "$FNAME_CLASS" 'regression test')" == "yes" && "$(has "$FNAME_CLASS" 'wrap-up')" == "yes" ]] && echo yes || echo no)" "yes"

# --- Sweep for latent instances: method/scope/results, "0 found" valid, ----
# --- paste-back access rule -------------------------------------------------
check "sweep: records method (exact commands/queries)" \
  "$([[ "$(has "$FSWEEP" 'method')" == "yes" && "$(has "$FSWEEP" 'command|quer')" == "yes" ]] && echo yes || echo no)" "yes"
check "sweep: records scope" "$(has "$FSWEEP" 'scope')" "yes"
check "sweep: records results" "$(has "$FSWEEP" 'result')" "yes"
check "sweep: '0 found' is an explicit valid outcome" \
  "$(has_f "$FSWEEP" '0 found')" "yes"
check "sweep: scales depth to class breadth" \
  "$([[ "$(has "$FSWEEP" 'scale')" == "yes" && "$(has "$FSWEEP" 'breadth')" == "yes" ]] && echo yes || echo no)" "yes"
check "sweep: paste-back access rule when orchestrator lacks access" \
  "$([[ "$(has "$FSWEEP" 'paste[- ]back')" == "yes" && "$(has "$FSWEEP" 'engineer')" == "yes" ]] && echo yes || echo no)" "yes"

# --- Choose a guardrail layer: ladder rungs in strongest-first order -------
check "guardrail: rung - make the defect impossible" \
  "$(has "$FGUARDRAIL" 'impossible')" "yes"
check "guardrail: rung - static check / lint" \
  "$(has "$FGUARDRAIL" 'lint')" "yes"
check "guardrail: rung - test" \
  "$(has "$FGUARDRAIL" '\btest')" "yes"
check "guardrail: rung - CI gate" \
  "$(has_f "$FGUARDRAIL" 'CI gate')" "yes"
check "guardrail: rung - runtime check" \
  "$(has_f "$FGUARDRAIL" 'runtime check')" "yes"
check "guardrail: rung - process or documentation" \
  "$(has "$FGUARDRAIL" 'process|documentation')" "yes"

IMPOSSIBLE_POS=$(grep -aiobF 'impossible' <<<"$FGUARDRAIL" | head -1 | cut -d: -f1)
LINT_POS=$(grep -aiobF 'lint' <<<"$FGUARDRAIL" | head -1 | cut -d: -f1)
TEST_POS=$(grep -aiobF 'test' <<<"$FGUARDRAIL" | head -1 | cut -d: -f1)
CI_POS=$(grep -aiobF 'CI gate' <<<"$FGUARDRAIL" | head -1 | cut -d: -f1)
RUNTIME_POS=$(grep -aiobF 'runtime check' <<<"$FGUARDRAIL" | head -1 | cut -d: -f1)
DOC_POS=$(grep -aiobE 'process|documentation' <<<"$FGUARDRAIL" | head -1 | cut -d: -f1)
check "guardrail: ladder rungs appear strongest-first (impossible < lint < test < CI gate < runtime check < process/documentation)" \
  "$([[ -n "$IMPOSSIBLE_POS" && -n "$LINT_POS" && -n "$TEST_POS" && -n "$CI_POS" \
        && -n "$RUNTIME_POS" && -n "$DOC_POS" \
        && "$IMPOSSIBLE_POS" -lt "$LINT_POS" && "$LINT_POS" -lt "$TEST_POS" \
        && "$TEST_POS" -lt "$CI_POS" && "$CI_POS" -lt "$RUNTIME_POS" \
        && "$RUNTIME_POS" -lt "$DOC_POS" ]] && echo yes || echo no)" "yes"

check "guardrail: prefers the highest rung whose cost fits the class" \
  "$([[ "$(has "$FGUARDRAIL" 'prefer')" == "yes" && "$(has "$FGUARDRAIL" 'cost')" == "yes" ]] && echo yes || echo no)" "yes"
check "guardrail: instance regression test is the floor, never the class guardrail" \
  "$([[ "$(has "$FGUARDRAIL" 'regression test')" == "yes" && "$(has "$FGUARDRAIL" 'floor')" == "yes" ]] && echo yes || echo no)" "yes"

# --- Decide and record: propose-by-default, decline needs cost/benefit -----
# --- rationale + engineer sign-off ------------------------------------------
check "decide: proposes a concrete guardrail when the sweep found members" \
  "$([[ "$(has "$FDECIDE" 'propose')" == "yes" && "$(has "$FDECIDE" 'found')" == "yes" ]] && echo yes || echo no)" "yes"
check "decide: proposes when the class plausibly regrows" \
  "$(has "$FDECIDE" 'regrow')" "yes"
check "decide: declining requires a journaled cost/benefit rationale" \
  "$([[ "$(has "$FDECIDE" 'cost')" == "yes" && "$(has "$FDECIDE" 'benefit')" == "yes" && "$(has "$FDECIDE" 'journal')" == "yes" ]] && echo yes || echo no)" "yes"
check "decide: declining requires explicit engineer sign-off" \
  "$(has "$FDECIDE" 'sign[- ]off')" "yes"
check "decide: 'no guardrail warranted' is legitimate only with the analysis recorded" \
  "$(has_f "$FDECIDE" 'no guardrail warranted')" "yes"

# --- Journal: class statement, sweep method/scope/results, guardrail -------
# --- decision+status, into the Prevention section ---------------------------
check "journal: records the class statement" "$(has "$FJOURNAL" 'class')" "yes"
check "journal: records sweep method/scope/results" \
  "$([[ "$(has "$FJOURNAL" 'method')" == "yes" && "$(has "$FJOURNAL" 'scope')" == "yes" && "$(has "$FJOURNAL" 'result')" == "yes" ]] && echo yes || echo no)" "yes"
check "journal: records the guardrail decision and its status" \
  "$([[ "$(has "$FJOURNAL" 'decision')" == "yes" && "$(has "$FJOURNAL" 'status')" == "yes" ]] && echo yes || echo no)" "yes"
check "journal: targets the journal's Prevention section" \
  "$(has_f "$FJOURNAL" 'Prevention')" "yes"

# ===========================================================================
# Invariants.
# ===========================================================================

# Evidence-gated mandate: the analysis is always required; building the
# guardrail is never worded as unconditionally mandatory.
check "invariant: never words building the guardrail as unconditionally mandatory" \
  "$([[ "$(has "$FBODY" 'guardrail (is|must be) (mandatory|required)|must build (a|the) guardrail|building (the|a) guardrail is (mandatory|required)')" == "yes" ]] && echo present || echo absent)" "absent"

# Ritual-guardrail warning: explicitly warns against token guardrails built
# just to satisfy the phase.
check "invariant: ritual-guardrail warning present" \
  "$(has "$FBODY" 'ritual|token guardrail')" "yes"

# The engineer decides build/decline; the orchestrator proposes and records.
check "invariant: the engineer decides whether to build or decline" \
  "$([[ "$(has "$FBODY" 'engineer')" == "yes" && "$(has "$FBODY" 'decide')" == "yes" ]] && echo yes || echo no)" "yes"
check "invariant: the orchestrator proposes and records, not decides" \
  "$(has "$FBODY" 'propose')" "yes"

# Guardrail work is scoped outside the current fix unless the engineer folds
# it in.
check "invariant: guardrail work is scoped outside the current fix" \
  "$(has "$FBODY" 'outside the current fix|out of scope of the (current )?fix')" "yes"
check "invariant: engineer may fold guardrail work into the current fix" \
  "$(has "$FBODY" 'fold')" "yes"

# ===========================================================================
# Edge cases.
# ===========================================================================

# One-off causes still get the analysis; recorded outcome is a justified
# "no guardrail warranted".
check "edge case: transient external outage example" \
  "$(has "$FBODY" 'transient')" "yes"
check "edge case: code slated for deletion example" \
  "$(has "$FBODY" 'slated for deletion')" "yes"
check "edge case: one-time migration script example" \
  "$(has "$FBODY" 'one-time migration|one time migration')" "yes"
check "edge case: one-off outcome is a justified 'no guardrail warranted'" \
  "$([[ "$(has "$FBODY" 'no guardrail warranted')" == "yes" && "$(has "$FBODY" 'justif')" == "yes" ]] && echo yes || echo no)" "yes"

# Sweep finds members beyond the current deliverable's scope: recorded and
# surfaced to the engineer, never silently folded/expanded into the fix.
check "edge case: out-of-scope sweep findings are recorded and surfaced to the engineer" \
  "$([[ "$(has "$FBODY" 'beyond')" == "yes" && "$(has "$FBODY" 'scope')" == "yes" && "$(has "$FBODY" 'surface')" == "yes" ]] && echo yes || echo no)" "yes"
check "edge case: out-of-scope findings never silently expand the fix" \
  "$([[ "$(has "$FBODY" 'silently')" == "yes" && "$(has "$FBODY" 'expand')" == "yes" ]] && echo yes || echo no)" "yes"

# An already-existing guardrail is verified against "would it have caught
# this instance?".
check "edge case: existing guardrail is checked against 'would it have caught this instance'" \
  "$([[ "$(has "$FBODY" 'already exist|existing guardrail|adequate guardrail')" == "yes" && "$(has "$FBODY" 'would (it )?have caught|caught this instance')" == "yes" ]] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
