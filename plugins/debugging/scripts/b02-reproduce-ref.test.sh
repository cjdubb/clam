#!/usr/bin/env bash
# Structural/content test for references/reproduce.md against
# Contract: B02 ref-reproduce (see the HTML-comment docblock in that file).
#
# This reference doc is pure guidance markdown (no frontmatter), so the tests
# here are:
#   - H1 title present, followed by a "When to use" line before the first H2
#   - the exact required H2 section set (any order, per the contract's own
#     "any order unless noted" qualifier), with no extra/missing sections
#   - per-section anchor checks: each section's body must contain the stable
#     terms a faithful implementation of that section could not avoid using
#   - invariants: the none -> flaky -> reliable repro-status ladder; repro-
#     as-regression-test stated as the preferred end state
#   - edge cases: cannot-reproduce-at-all widens to logs/DB evidence and
#     treats the gap itself as diagnostic; production-only failures get safe
#     (non-destructive) capture guidance
#
# All anchor/section checks run against the body with the contract's own
# HTML-comment docblock stripped (sed '/<!--/,/-->/d'), so the docblock's own
# prose can never satisfy a check meant for the real implementation.
#
# These MUST fail against the current NotImplemented(B02) stub and MUST pass
# once a real doc satisfies the contract.
# Run: bash plugins/debugging/scripts/b02-reproduce-ref.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="$SCRIPT_DIR/../skills/root-cause/references/reproduce.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "reproduce.md exists at the contract's Code path" \
  "$([ -f "$DOC" ] && echo yes || echo no)" "yes"

if [[ ! -f "$DOC" ]]; then
  echo "FAILURES (doc missing, cannot continue)"
  exit 1
fi

RAW=$(cat "$DOC")

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

# ===========================================================================
# Outputs: H1 title, "When to use" line, exact H2 section set.
# ===========================================================================

check "H1 title present" \
  "$(grep -qE '^# [^#]' <<<"$BODY" && echo yes || echo no)" "yes"

check "'When to use' line present before the first H2" \
  "$(has "$(flat "$PREAMBLE")" 'when to use')" "yes"

REQUIRED_HEADINGS=("## Goal" "## Capture" "## Minimize" "## Automate" \
  "## Flaky and intermittent" "## Journal")

for h in "${REQUIRED_HEADINGS[@]}"; do
  check "required section exists: $h" "$(has_f "$BODY" "$h")" "yes"
done

# "Exactly this set": the sorted list of H2 headings in the doc must equal
# the sorted list of required headings, no extras.
ACTUAL_H2S=$(grep -E '^## ' <<<"$BODY" | sort)
EXPECTED_H2S=$(printf '%s\n' "${REQUIRED_HEADINGS[@]}" | sort)
check "H2 section set is exactly the contracted set (no extras/missing)" \
  "$ACTUAL_H2S" "$EXPECTED_H2S"

GOAL=$(section "## Goal")
CAPTURE=$(section "## Capture")
MINIMIZE=$(section "## Minimize")
AUTOMATE=$(section "## Automate")
FLAKY=$(section "## Flaky and intermittent")
JOURNAL=$(section "## Journal")

FGOAL=$(flat "$GOAL")
FCAPTURE=$(flat "$CAPTURE")
FMINIMIZE=$(flat "$MINIMIZE")
FAUTOMATE=$(flat "$AUTOMATE")
FFLAKY=$(flat "$FLAKY")
FJOURNAL=$(flat "$JOURNAL")

for pair in "Goal:$GOAL" "Capture:$CAPTURE" "Minimize:$MINIMIZE" \
            "Automate:$AUTOMATE" "Flaky and intermittent:$FLAKY" \
            "Journal:$JOURNAL"; do
  label="${pair%%:*}"; content="${pair#*:}"
  check "$label section is non-empty" \
    "$(grep -qv '^[[:space:]]*$' <<<"$content" && echo yes || echo no)" "yes"
done

# --- Goal: reliability defined, quantified -------------------------------
check "Goal: same steps" "$(has "$FGOAL" 'same steps')" "yes"
check "Goal: same failure" "$(has "$FGOAL" 'same failure')" "yes"
check "Goal: quantified (N/N-style ratio)" \
  "$(has "$FGOAL" 'N/N|[0-9]+/[0-9]+')" "yes"

# --- Capture: freeze exact failing input/env/versions/data ---------------
check "Capture: freeze" "$(has "$FCAPTURE" 'freeze')" "yes"
check "Capture: environment" "$(has "$FCAPTURE" 'environment')" "yes"
check "Capture: version" "$(has "$FCAPTURE" 'version')" "yes"
check "Capture: data" "$(has "$FCAPTURE" 'data')" "yes"
check "Capture: before touching anything" \
  "$(has "$FCAPTURE" 'before.*touch')" "yes"

# --- Minimize: shrink while failure persists, smallest wins ----------------
check "Minimize: shrink" "$(has "$FMINIMIZE" 'shrink')" "yes"
check "Minimize: smallest repro wins" "$(has "$FMINIMIZE" 'smallest')" "yes"

# --- Automate: script or failing test, prefer repo's own runner -----------
check "Automate: failing test" "$(has "$FAUTOMATE" 'failing test')" "yes"
check "Automate: prefer" "$(has "$FAUTOMATE" 'prefer')" "yes"

# --- Flaky and intermittent: frequency, forced conditions, weakened inference
check "Flaky: frequency" "$(has "$FFLAKY" 'frequency')" "yes"
check "Flaky: timing" "$(has "$FFLAKY" 'timing')" "yes"
check "Flaky: concurrency" "$(has "$FFLAKY" 'concurrency')" "yes"
check "Flaky: load" "$(has "$FFLAKY" 'load')" "yes"
check "Flaky: data variance" "$(has "$FFLAKY" 'variance')" "yes"
check "Flaky: environment" "$(has "$FFLAKY" 'environment')" "yes"
check "Flaky: weakens later inference" "$(has "$FFLAKY" 'weak')" "yes"

# --- Journal: repro status ladder, steps, rate -----------------------------
check "Journal: mentions steps" "$(has "$FJOURNAL" 'steps')" "yes"
check "Journal: mentions rate" "$(has "$FJOURNAL" 'rate')" "yes"

# ===========================================================================
# Invariants.
# ===========================================================================

# The none -> flaky -> reliable ladder: all three terms present in the
# Journal section, in that left-to-right order.
check "Journal: ladder term 'none' present" "$(has "$FJOURNAL" 'none')" "yes"
check "Journal: ladder term 'flaky' present" "$(has "$FJOURNAL" 'flaky')" "yes"
check "Journal: ladder term 'reliable' present" "$(has "$FJOURNAL" 'reliable')" "yes"

NONE_POS=$(grep -aiobF 'none' <<<"$FJOURNAL" | head -1 | cut -d: -f1)
FLAKY_POS=$(grep -aiobF 'flaky' <<<"$FJOURNAL" | head -1 | cut -d: -f1)
RELIABLE_POS=$(grep -aiobF 'reliable' <<<"$FJOURNAL" | head -1 | cut -d: -f1)
check "Journal: ladder order is none -> flaky -> reliable" \
  "$([[ -n "$NONE_POS" && -n "$FLAKY_POS" && -n "$RELIABLE_POS" \
        && "$NONE_POS" -lt "$FLAKY_POS" && "$FLAKY_POS" -lt "$RELIABLE_POS" ]] \
     && echo yes || echo no)" "yes"

# Repro-as-regression-test stated as the preferred end state (Automate).
check "Automate states failing test as the preferred end state" \
  "$([[ "$(has "$FAUTOMATE" 'prefer')" == "yes" && "$(has "$FAUTOMATE" 'failing test')" == "yes" ]] && echo yes || echo no)" "yes"

# Never duplicates the SKILL.md phase loop: no numbered phase headings.
check "does not duplicate the numbered phase loop from SKILL.md" \
  "$(grep -qE '^## [0-9]+\.' <<<"$BODY" && echo present || echo absent)" "absent"

# ===========================================================================
# Edge cases.
# ===========================================================================

FBODY=$(flat "$BODY")

# Cannot reproduce at all: widen evidence gathering (logs/DB); repro gap
# itself treated as diagnostic information.
check "edge case: cannot reproduce widens to logs" "$(has "$FBODY" 'log')" "yes"
check "edge case: cannot reproduce widens to database evidence" \
  "$(has "$FBODY" 'database|\bDB\b')" "yes"
check "edge case: repro gap itself is diagnostic information" \
  "$(has "$FBODY" 'diagnostic')" "yes"

# Production-only failures: safe (non-destructive) capture guidance.
check "edge case: production-only failures addressed" \
  "$(has "$FBODY" 'production')" "yes"
check "edge case: no destructive probing in production" \
  "$(has "$FBODY" 'destructive')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
