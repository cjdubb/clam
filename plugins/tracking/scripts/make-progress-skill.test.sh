#!/bin/bash
# Tests for plugins/tracking/skills/make-progress/SKILL.md — the merge-skill
# (B03) and assessor-honesty (B04) contracts:
#
#   B03 moves the make-progress skill's SKILL.md into tracking's skills/
#   directory (same behavior, new location; contract preserved: frontmatter,
#   capture-verification step, the attended decision table, the DECISION.md
#   template, and all six workflow-step headings).
#
#   B04 revises the Assess step so disk-absence is phrased honestly ("no
#   artifacts found", never a historical claim like "no workflow existed"),
#   and generalizes the lego-specific `.local/blocks.md` line to reference
#   `.local/` state files generically instead of assuming the lego plugin.
#
# Run: bash plugins/tracking/scripts/make-progress-skill.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../skills/make-progress/SKILL.md"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }

# Extracts the frontmatter block (between the first two '---' lines).
frontmatter() {
    awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1{print} n>=2{exit}' "$1"
}

# Extracts the body of the "### 2. Assess" step, up to the next numbered
# "### N." heading.
assess_section() {
    awk '
        /^### 2\. Assess/ { flag=1; next }
        /^### [0-9]+\./ { flag=0 }
        flag { print }
    ' "$1"
}

if [ ! -f "$SKILL_MD" ]; then
    fail "SKILL.md exists at plugins/tracking/skills/make-progress/SKILL.md" \
        "not found at $SKILL_MD"
    echo ""
    echo "Some tests FAILED."
    exit 1
fi

FM=$(frontmatter "$SKILL_MD")
ASSESS=$(assess_section "$SKILL_MD")
# Flattened (newlines -> spaces) so multi-word phrases aren't missed just
# because markdown line-wrapped them across two lines.
ASSESS_FLAT=$(echo "$ASSESS" | tr '\n' ' ' | tr -s ' ')

# ============================================================
# B03 — merge-skill
# ============================================================

# --- Test 1: skill file exists (already checked above; record it) ---
pass "SKILL.md exists at plugins/tracking/skills/make-progress/SKILL.md"

# --- Test 2: not a stub ---
if grep -q "NotImplemented" "$SKILL_MD"; then
    fail "SKILL.md is not a stub" "still contains NotImplemented"
else
    pass "SKILL.md is not a stub"
fi

# --- Test 3: frontmatter name field is make-progress ---
name_line=$(echo "$FM" | grep -E '^name:[[:space:]]*make-progress[[:space:]]*$')
if [ -n "$name_line" ]; then
    pass "frontmatter name: is make-progress"
else
    fail "frontmatter name: is make-progress" "no matching 'name: make-progress' line in frontmatter"
fi

# --- Test 4: user-invoked only ---
if echo "$FM" | grep -qE '^disable-model-invocation:[[:space:]]*true[[:space:]]*$'; then
    pass "frontmatter has disable-model-invocation: true"
else
    fail "frontmatter has disable-model-invocation: true" "not found in frontmatter"
fi

# --- Test 5: decision table present ---
if grep -qE '\|[[:space:]]*Observed state[[:space:]]*\|[[:space:]]*Decision[[:space:]]*\|' "$SKILL_MD"; then
    pass "decision table present with 'Observed state' / 'Decision' headers"
else
    fail "decision table present with 'Observed state' / 'Decision' headers" "no matching table header row"
fi

# --- Test 6: capture reference ---
if grep -q "capture\.sh" "$SKILL_MD"; then
    pass "references capture.sh"
else
    fail "references capture.sh" "no reference to capture.sh found"
fi

# --- Test 7: DECISION.md YAML frontmatter template ---
decision_template_ok=1
for field in invoked_with row_matched stop_was_correct action_class; do
    if ! grep -q "$field" "$SKILL_MD"; then
        decision_template_ok=0
        fail "DECISION.md template includes '$field'" "not found"
    fi
done
if [ "$decision_template_ok" -eq 1 ]; then
    pass "DECISION.md template includes invoked_with, row_matched, stop_was_correct, action_class"
fi

# --- Test 8: six workflow step headings ---
declare -A steps=(
    [1]="Verify capture"
    [2]="Assess"
    [3]="Decide"
    [4]="Record"
    [5]="Act"
    [6]="Append the outcome"
)
for n in 1 2 3 4 5 6; do
    label="${steps[$n]}"
    if grep -qE "^### ${n}\. ${label}" "$SKILL_MD"; then
        pass "step ${n} heading present: '${label}'"
    else
        fail "step ${n} heading present: '${label}'" "no matching '### ${n}. ${label}' heading"
    fi
done

# ============================================================
# B04 — assessor-honesty
# ============================================================

if [ -z "$ASSESS" ]; then
    fail "Assess step section is extractable (### 2. Assess ... next ### N.)" \
        "could not locate the Assess step section — B04 checks below cannot run meaningfully"
fi

# --- Test 9: no dishonest historical claim about disk-absence ---
if echo "$ASSESS_FLAT" | grep -qiE 'no workflow existed|no lego workflow'; then
    fail "Assess step avoids 'no workflow existed' / 'no lego workflow'" \
        "found a banned historical-claim phrase"
else
    pass "Assess step avoids 'no workflow existed' / 'no lego workflow'"
fi

# --- Test 10: honest absence phrasing is present. Wording may vary, so this
# accepts a family of phrasings that describe an OBSERVATION ("we looked and
# found nothing") rather than a historical CLAIM ("it never existed") —
# consistent with the brief's instruction to test for the absence of
# overclaiming, not one hardcoded replacement string.
honest_absence_pattern='no artifacts found|nothing found|no .?local/? (state )?(artifacts|files) found|not found on disk|no matching (artifacts|files|state)'
if echo "$ASSESS_FLAT" | grep -qiE "$honest_absence_pattern"; then
    pass "Assess step uses honest disk-absence phrasing (e.g. 'no artifacts found')"
else
    fail "Assess step uses honest disk-absence phrasing (e.g. 'no artifacts found')" \
        "no observation-style absence phrasing found"
fi

# --- Test 11: no lego-specific blocks.md reference. A bare mention of
# blocks.md would be fine (e.g. as one example among generic .local/ state
# files); what's banned is pairing it with a lego-specific qualifier nearby
# (e.g. "lego block map", "if the lego plugin is active"). Use a bounded
# proximity window on the flattened text rather than same-physical-line,
# since markdown may wrap the phrase across lines.
if echo "$ASSESS_FLAT" | grep -qiE 'blocks\.md.{0,80}lego|lego.{0,80}blocks\.md'; then
    fail "Assess step does not reference blocks.md with a lego-specific qualifier" \
        "found 'blocks.md' and 'lego' near each other"
else
    pass "Assess step does not reference blocks.md with a lego-specific qualifier"
fi

# --- Test 12: generic .local/ state-file reading ---
generic_local_pattern='any other.{0,10}\.local/?.{0,10}state files|\.local/.{0,10}state files|state files.*\.local/|\.local/.{0,10}(directory )?contents|list(ing)? \.local/'
if echo "$ASSESS_FLAT" | grep -qiE "$generic_local_pattern"; then
    pass "Assess step references .local/ state files generically"
else
    fail "Assess step references .local/ state files generically" \
        "no generic .local/ state-files phrasing found"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
