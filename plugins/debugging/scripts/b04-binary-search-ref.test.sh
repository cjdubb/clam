#!/usr/bin/env bash
# Structural/content test for references/binary-search.md against
# Contract: B04 ref-binary-search (see the HTML-comment docblock in that
# file).
#
# This reference doc is pure guidance markdown (no frontmatter), so the tests
# here are:
#   - H1 title present, followed by a "When to use" line before the first H2,
#     restating the trigger (large search space + a reliable discriminator)
#   - the exact required H2 section set, with no extra/missing sections
#   - per-section anchor checks: each section's body must contain the stable
#     terms a faithful implementation of that section could not avoid using
#   - invariants: git bisect as the primary history-dimension tool with the
#     exact start/good/bad/run/reset command sequence; one-variable-per-probe
#     discipline (never two variables in one probe)
#   - edge cases: non-monotonic space falls back to differential diagnosis
#     instead of forcing a bisect; a search space of one skips bisection
#
# All anchor/section checks run against the body with the contract's own
# HTML-comment docblock stripped (sed '/<!--/,/-->/d'), so the docblock's own
# prose can never satisfy a check meant for the real implementation.
#
# These MUST fail against the current NotImplemented(B04) stub and MUST pass
# once a real doc satisfies the contract.
# Run: bash plugins/debugging/scripts/b04-binary-search-ref.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="$SCRIPT_DIR/../skills/root-cause/references/binary-search.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "binary-search.md exists at the contract's Code path" \
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
# Outputs: H1 title, "When to use" line, exact H2 section set.
# ===========================================================================

check "H1 title present" \
  "$(grep -qE '^# [^#]' <<<"$BODY" && echo yes || echo no)" "yes"

check "'When to use' line present before the first H2" \
  "$(has "$FPREAMBLE" 'when to use')" "yes"
check "'When to use' line restates trigger: large search space" \
  "$(has "$FPREAMBLE" 'large search space')" "yes"
check "'When to use' line restates trigger: a reliable discriminator" \
  "$(has "$FPREAMBLE" 'reliable discriminator')" "yes"

REQUIRED_HEADINGS=("## Prerequisite" "## Dimensions" "## Discipline" \
  "## Pitfalls" "## Journal")

for h in "${REQUIRED_HEADINGS[@]}"; do
  check "required section exists: $h" "$(has_f "$BODY" "$h")" "yes"
done

# "Exactly this set": the sorted list of H2 headings in the doc must equal
# the sorted list of required headings, no extras.
ACTUAL_H2S=$(grep -E '^## ' <<<"$BODY" | sort)
EXPECTED_H2S=$(printf '%s\n' "${REQUIRED_HEADINGS[@]}" | sort)
check "H2 section set is exactly the contracted set (no extras/missing)" \
  "$ACTUAL_H2S" "$EXPECTED_H2S"

PREREQ=$(section "## Prerequisite")
DIMENSIONS=$(section "## Dimensions")
DISCIPLINE=$(section "## Discipline")
PITFALLS=$(section "## Pitfalls")
JOURNAL=$(section "## Journal")

FPREREQ=$(flat "$PREREQ")
FDIMENSIONS=$(flat "$DIMENSIONS")
FDISCIPLINE=$(flat "$DISCIPLINE")
FPITFALLS=$(flat "$PITFALLS")
FJOURNAL=$(flat "$JOURNAL")

for pair in "Prerequisite:$PREREQ" "Dimensions:$DIMENSIONS" \
            "Discipline:$DISCIPLINE" "Pitfalls:$PITFALLS" "Journal:$JOURNAL"; do
  label="${pair%%:*}"; content="${pair#*:}"
  check "$label section is non-empty" \
    "$(grep -qv '^[[:space:]]*$' <<<"$content" && echo yes || echo no)" "yes"
done

# --- Prerequisite: reliable discriminator; flaky signal corrupts search ---
check "prerequisite: reliable discriminator" \
  "$(has "$FPREREQ" 'reliable discriminator')" "yes"
check "prerequisite: usually the repro from phase 3" \
  "$(has "$FPREREQ" 'repro')" "yes"
check "prerequisite: flaky signal corrupts the search" \
  "$([[ "$(has "$FPREREQ" 'flaky')" == "yes" && "$(has "$FPREREQ" 'corrupt')" == "yes" ]] && echo yes || echo no)" "yes"

# --- Dimensions: history/code path/data/configuration/environment ---------
check "dimensions: history (git bisect)" "$(has "$FDIMENSIONS" 'history')" "yes"
check "dimensions: git bisect named" "$(has_f "$FDIMENSIONS" 'git bisect')" "yes"
check "dimensions: git bisect run automation" \
  "$(has_f "$FDIMENSIONS" 'git bisect run')" "yes"
check "dimensions: code path (instrumentation, early returns)" \
  "$([[ "$(has "$FDIMENSIONS" 'code path')" == "yes" && "$(has "$FDIMENSIONS" 'instrumentation')" == "yes" ]] && echo yes || echo no)" "yes"
check "dimensions: early returns" "$(has "$FDIMENSIONS" 'early return')" "yes"
check "dimensions: data (input halving)" \
  "$([[ "$(has "$FDIMENSIONS" '\bdata\b')" == "yes" && "$(has "$FDIMENSIONS" 'input')" == "yes" ]] && echo yes || echo no)" "yes"
check "dimensions: configuration (toggle halves)" \
  "$([[ "$(has "$FDIMENSIONS" 'configuration')" == "yes" && "$(has "$FDIMENSIONS" 'toggle')" == "yes" ]] && echo yes || echo no)" "yes"
check "dimensions: environment (diff and swap halves)" \
  "$([[ "$(has "$FDIMENSIONS" 'environment')" == "yes" && "$(has "$FDIMENSIONS" 'swap')" == "yes" ]] && echo yes || echo no)" "yes"

# --- Discipline: one variable per probe; log hypothesis/probe/expected/observed
check "discipline: one variable per probe" \
  "$(has "$FDISCIPLINE" 'one variable')" "yes"
check "discipline: records hypothesis" "$(has "$FDISCIPLINE" 'hypothesis')" "yes"
check "discipline: records probe" "$(has "$FDISCIPLINE" 'probe')" "yes"
check "discipline: records expected" "$(has "$FDISCIPLINE" 'expected')" "yes"
check "discipline: records observed" "$(has "$FDISCIPLINE" 'observed')" "yes"
check "discipline: stop when culprit is minimal" \
  "$([[ "$(has "$FDISCIPLINE" 'minimal')" == "yes" && "$(has "$FDISCIPLINE" 'culprit')" == "yes" ]] && echo yes || echo no)" "yes"
check "discipline: minimal examples (one commit/one input/one flag)" \
  "$([[ "$(has "$FDISCIPLINE" 'one commit')" == "yes" && "$(has "$FDISCIPLINE" 'one input')" == "yes" && "$(has "$FDISCIPLINE" 'one flag')" == "yes" ]] && echo yes || echo no)" "yes"

# --- Pitfalls: flaky discriminator, unbuildable commits, non-monotonic, fix-masking
check "pitfalls: flaky discriminator" "$(has "$FPITFALLS" 'flaky')" "yes"
check "pitfalls: unbuildable commits / git bisect skip" \
  "$([[ "$(has "$FPITFALLS" 'unbuildable')" == "yes" && "$(has_f "$FPITFALLS" 'git bisect skip')" == "yes" ]] && echo yes || echo no)" "yes"
check "pitfalls: non-monotonic spaces invalidate halving" \
  "$(has "$FPITFALLS" 'non-monotonic')" "yes"
check "pitfalls: fix-masking interactions" "$(has "$FPITFALLS" 'fix-masking|fix masking')" "yes"

# --- Journal: every probe becomes a Probe Log row --------------------------
check "journal: Probe Log row per probe" "$(has_f "$FJOURNAL" 'Probe Log')" "yes"

# ===========================================================================
# Invariants.
# ===========================================================================

# git bisect presented as the primary tool for history, with the exact
# start/good/bad/run/reset command sequence.
check "invariant: git bisect start" "$(has_f "$FDIMENSIONS" 'git bisect start')" "yes"
check "invariant: git bisect good" "$(has_f "$FDIMENSIONS" 'git bisect good')" "yes"
check "invariant: git bisect bad" "$(has_f "$FDIMENSIONS" 'git bisect bad')" "yes"
check "invariant: git bisect run" "$(has_f "$FDIMENSIONS" 'git bisect run')" "yes"
check "invariant: git bisect reset" "$(has_f "$FDIMENSIONS" 'git bisect reset')" "yes"

# Never suggests changing two variables in one probe.
check "invariant: never recommends changing two variables in one probe" \
  "$([[ "$(has "$FBODY" 'change (two|multiple) variables (in|per|at) (one|a single|the same) probe')" == "yes" ]] && echo present || echo absent)" "absent"

# ===========================================================================
# Edge cases.
# ===========================================================================

# Non-monotonic space (intermittent regressions): fall back to differential
# diagnosis instead of forcing a bisect.
check "edge case: non-monotonic space named" "$(has "$FBODY" 'non-monotonic')" "yes"
check "edge case: intermittent regressions" "$(has "$FBODY" 'intermittent')" "yes"
check "edge case: falls back to differential diagnosis" \
  "$(has "$FBODY" 'differential diagnosis')" "yes"

# Search space of one (single candidate change): skip bisection, verify
# directly.
check "edge case: search space of one / single candidate" \
  "$(has "$FBODY" 'search space of one|single candidate')" "yes"
check "edge case: skip bisection, verify directly" \
  "$([[ "$(has "$FBODY" 'skip')" == "yes" && "$(has "$FBODY" 'verify directly|directly verify')" == "yes" ]] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
