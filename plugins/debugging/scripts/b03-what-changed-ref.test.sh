#!/usr/bin/env bash
# Structural/content test for references/what-changed.md against
# Contract: B03 ref-what-changed (see the HTML-comment docblock in that file).
#
# This reference doc is pure guidance markdown (no frontmatter), so the tests
# here are:
#   - H1 title present, followed by a "When to use" line before the first H2
#   - the exact required H2 section set, with no extra/missing sections
#   - per-section anchor checks: each section's body must contain the stable
#     terms a faithful implementation of that section could not avoid using,
#     including the full enumerated change-surface checklist
#   - invariants: the surface list is presented as an exhaustive checklist,
#     not a menu; the correlation-is-not-causation caveat sits with Correlate
#   - edge cases: no last-known-good (never worked) reframes to first-
#     principles diagnosis; multiple simultaneous changes stay separate
#     hypotheses rather than being lumped together
#
# All anchor/section checks run against the body with the contract's own
# HTML-comment docblock stripped (sed '/<!--/,/-->/d'), so the docblock's own
# prose can never satisfy a check meant for the real implementation.
#
# These MUST fail against the current NotImplemented(B03) stub and MUST pass
# once a real doc satisfies the contract.
# Run: bash plugins/debugging/scripts/b03-what-changed-ref.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="$SCRIPT_DIR/../skills/root-cause/references/what-changed.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "what-changed.md exists at the contract's Code path" \
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

# ===========================================================================
# Outputs: H1 title, "When to use" line, exact H2 section set.
# ===========================================================================

check "H1 title present" \
  "$(grep -qE '^# [^#]' <<<"$BODY" && echo yes || echo no)" "yes"

check "'When to use' line present before the first H2" \
  "$(has "$(flat "$PREAMBLE")" 'when to use')" "yes"

REQUIRED_HEADINGS=("## Establish the window" "## Change surfaces" \
  "## Enumerate changes per surface" "## Correlate" "## Output" "## Journal")

for h in "${REQUIRED_HEADINGS[@]}"; do
  check "required section exists: $h" "$(has_f "$BODY" "$h")" "yes"
done

# "Exactly this set": the sorted list of H2 headings in the doc must equal
# the sorted list of required headings, no extras.
ACTUAL_H2S=$(grep -E '^## ' <<<"$BODY" | sort)
EXPECTED_H2S=$(printf '%s\n' "${REQUIRED_HEADINGS[@]}" | sort)
check "H2 section set is exactly the contracted set (no extras/missing)" \
  "$ACTUAL_H2S" "$EXPECTED_H2S"

WINDOW=$(section "## Establish the window")
SURFACES=$(section "## Change surfaces")
ENUMERATE=$(section "## Enumerate changes per surface")
CORRELATE=$(section "## Correlate")
OUTPUT=$(section "## Output")
JOURNAL=$(section "## Journal")

FWINDOW=$(flat "$WINDOW")
FSURFACES=$(flat "$SURFACES")
FENUMERATE=$(flat "$ENUMERATE")
FCORRELATE=$(flat "$CORRELATE")
FOUTPUT=$(flat "$OUTPUT")
FJOURNAL=$(flat "$JOURNAL")

for pair in "Establish the window:$WINDOW" "Change surfaces:$SURFACES" \
            "Enumerate changes per surface:$ENUMERATE" "Correlate:$CORRELATE" \
            "Output:$OUTPUT" "Journal:$JOURNAL"; do
  label="${pair%%:*}"; content="${pair#*:}"
  check "$label section is non-empty" \
    "$(grep -qv '^[[:space:]]*$' <<<"$content" && echo yes || echo no)" "yes"
done

# --- Establish the window: first-seen / last-known-good bound the window --
check "window: first-seen" "$(has "$FWINDOW" 'first[- ]seen')" "yes"
check "window: last-known-good" "$(has "$FWINDOW" 'last[- ]known[- ]good')" "yes"
check "window: bounds the search window" "$(has "$FWINDOW" 'window')" "yes"

# --- Change surfaces: the full enumerated checklist, every item present ---
check "surfaces: code commits" "$(has "$FSURFACES" 'commit')" "yes"
check "surfaces: deploys and releases" "$(has "$FSURFACES" 'deploy')" "yes"
check "surfaces: config and feature flags" "$(has "$FSURFACES" 'config')" "yes"
check "surfaces: feature flags named" "$(has "$FSURFACES" 'feature flag')" "yes"
check "surfaces: dependencies" "$(has "$FSURFACES" 'dependenc')" "yes"
check "surfaces: base images" "$(has "$FSURFACES" 'base image')" "yes"
check "surfaces: schema migrations" "$(has "$FSURFACES" 'schema')" "yes"
check "surfaces: data migrations" "$(has "$FSURFACES" 'migrat')" "yes"
check "surfaces: infrastructure and platform" \
  "$(has "$FSURFACES" 'infrastructure|platform')" "yes"
check "surfaces: external services" "$(has "$FSURFACES" 'external service')" "yes"
check "surfaces: data drift" "$(has "$FSURFACES" 'data drift')" "yes"
check "surfaces: time-triggered changes named" \
  "$(has "$FSURFACES" 'time[- ]trigger')" "yes"
check "surfaces: cert expiry example" "$(has "$FSURFACES" 'cert')" "yes"
check "surfaces: quotas example" "$(has "$FSURFACES" 'quota')" "yes"
check "surfaces: DST example" "$(has "$FSURFACES" 'DST')" "yes"

# --- Enumerate changes per surface: sources + never-guess rule ------------
check "enumerate: git log/diff" "$(has "$FENUMERATE" 'git log|git diff')" "yes"
check "enumerate: deploy history" "$(has "$FENUMERATE" 'deploy history')" "yes"
check "enumerate: flag audit logs" "$(has "$FENUMERATE" 'flag audit')" "yes"
check "enumerate: dependency lockfiles" "$(has "$FENUMERATE" 'lockfile')" "yes"
check "enumerate: migration tables" "$(has "$FENUMERATE" 'migration table')" "yes"
check "enumerate: ask the engineer when records unreachable" \
  "$(has "$FENUMERATE" 'ask the engineer')" "yes"
check "enumerate: never guess" "$(has "$FENUMERATE" 'never guess')" "yes"

# --- Correlate: line up against symptom onset; hypothesis not verdict -----
check "correlate: symptom onset" "$(has "$FCORRELATE" 'onset')" "yes"
check "correlate: near-coincidence is a hypothesis" \
  "$(has "$FCORRELATE" 'hypothesis')" "yes"
check "correlate: not a verdict" "$(has "$FCORRELATE" 'verdict')" "yes"

# --- Output: candidate-change list feeding the differential diagnosis -----
check "output: candidate-change list" "$(has "$FOUTPUT" 'candidate')" "yes"
check "output: feeds the differential-diagnosis table" \
  "$(has "$FOUTPUT" 'differential[- ]diagnosis')" "yes"

# --- Journal: window, surfaces checked, candidates -------------------------
check "journal: records window" "$(has "$FJOURNAL" 'window')" "yes"
check "journal: records surfaces checked" "$(has "$FJOURNAL" 'surfaces')" "yes"
check "journal: records candidates" "$(has "$FJOURNAL" 'candidate')" "yes"

# ===========================================================================
# Invariants.
# ===========================================================================

# The surface list is the minimum, presented as an exhaustive checklist to
# walk, not a menu to sample from.
check "surfaces presented as a checklist (checkbox markers or numbered list)" \
  "$(grep -qE '^[[:space:]]*[-*][[:space:]]*\[[ xX]\]|^[[:space:]]*[0-9]+\.' <<<"$SURFACES" && echo yes || echo no)" "yes"
check "surfaces section calls for exhaustive walking, not sampling a menu" \
  "$(has "$FSURFACES" 'exhaustive|walk (all|every|each)|every surface|all of the following')" "yes"

# Correlation-is-not-causation caveat appears with the Correlate guidance.
check "correlate: correlation-is-not-causation caveat" \
  "$([[ "$(has "$FCORRELATE" 'correlation')" == "yes" && "$(has "$FCORRELATE" 'causation')" == "yes" ]] && echo yes || echo no)" "yes"

# ===========================================================================
# Edge cases.
# ===========================================================================

# No last-known-good exists (never worked): reframe to first-principles
# diagnosis, skip window narrowing.
check "edge case: never worked / no last-known-good" \
  "$(has "$FBODY" 'never worked')" "yes"
check "edge case: reframes to first-principles diagnosis" \
  "$(has "$FBODY" 'first[- ]principles')" "yes"

# Multiple simultaneous changes (deploy trains): candidates stay separate
# hypotheses, not lumped.
check "edge case: deploy trains / multiple simultaneous changes" \
  "$(has "$FBODY" 'deploy train|multiple simultaneous change')" "yes"
check "edge case: candidates stay separate, not lumped together" \
  "$([[ "$(has "$FBODY" 'separate')" == "yes" && "$(has "$FBODY" 'lump')" == "yes" ]] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
