#!/bin/bash
# Tests for plugins/tracking/skills/sitrep/SKILL.md — the ported situation
# report.
#
#   The skill is a read-only orientation report over the session's own
#   .local/ documents. It is ported from clam-code, with three deliberate
#   changes: the work graph is a first-class source (it did not exist in
#   clam-code), clam-code's chunk vocabulary is gone, and PR rendering is
#   delegated to the pr-status skill in this same plugin rather than having
#   its column list restated here.
#
# Run: bash plugins/tracking/scripts/sitrep-skill.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../skills/sitrep/SKILL.md"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }

# Extracts the frontmatter block (between the first two '---' lines).
frontmatter() {
    awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1{print} n>=2{exit}' "$1"
}

if [ ! -f "$SKILL_MD" ]; then
    fail "SKILL.md exists at plugins/tracking/skills/sitrep/SKILL.md" \
        "not found at $SKILL_MD"
    echo ""
    echo "Some tests FAILED."
    exit 1
fi
pass "SKILL.md exists at plugins/tracking/skills/sitrep/SKILL.md"

FM=$(frontmatter "$SKILL_MD")
BODY_FLAT=$(tr '\n' ' ' < "$SKILL_MD" | tr -s ' ')

# --- Test 2: frontmatter name field ---
if echo "$FM" | grep -qE '^name:[[:space:]]*sitrep[[:space:]]*$'; then
    pass "frontmatter name: is sitrep"
else
    fail "frontmatter name: is sitrep" "no matching 'name: sitrep' line"
fi

# --- Test 3: user-invoked only (orientation is asked for, never volunteered) ---
if echo "$FM" | grep -qE '^disable-model-invocation:[[:space:]]*true[[:space:]]*$'; then
    pass "frontmatter has disable-model-invocation: true"
else
    fail "frontmatter has disable-model-invocation: true" "not found in frontmatter"
fi

# --- Test 4: the four report sections, in order ---
sections=$(grep -E '^### (Goal|PRs|Progress|Next)[[:space:]]*$' "$SKILL_MD" | tr -d '#' | tr -d ' ' | paste -sd, -)
if [ "$sections" = "Goal,PRs,Progress,Next" ]; then
    pass "report sections are Goal, PRs, Progress, Next in that order"
else
    fail "report sections are Goal, PRs, Progress, Next in that order" \
        "found: ${sections:-none}"
fi

# --- Test 5: the work graph is a source, and is read first ---
if grep -qE '^1\.[[:space:]].*\.local/WORKGRAPH\.md' "$SKILL_MD"; then
    pass "work graph is the first information source"
else
    fail "work graph is the first information source" \
        "no numbered '1.' entry naming .local/WORKGRAPH.md in the sources list"
fi

# --- Test 6: every .local source the plugin recognises is covered ---
for doc in WORKGRAPH.md TODO.md PLAN.md TROUBLESHOOTING.md FOLLOWUPS.md; do
    if grep -qF ".local/$doc" "$SKILL_MD"; then
        pass "sources include .local/$doc"
    else
        fail "sources include .local/$doc" "not referenced in the skill"
    fi
done

# --- Test 7: read-only, stated as a rule ---
if grep -qE '^\-[[:space:]]+\*\*Read-only\.\*\*' "$SKILL_MD"; then
    pass "read-only rule present"
else
    fail "read-only rule present" "no '- **Read-only.**' rule"
fi

# --- Test 8: no bare PR references ---
if echo "$BODY_FLAT" | grep -qF "No bare PR references."; then
    pass "no-bare-PR-references rule present"
else
    fail "no-bare-PR-references rule present" "rule not found"
fi

# --- Test 9: no-work sessions handled ---
if echo "$BODY_FLAT" | grep -qF "No-work sessions."; then
    pass "no-work-sessions rule present"
else
    fail "no-work-sessions rule present" "rule not found"
fi

# --- Test 10: PR rendering is delegated, not restated ---
# The column list belongs to the pr-status skill alone. sitrep must point at
# it rather than carrying a second copy that can drift.
if echo "$BODY_FLAT" | grep -qF "pr-status"; then
    pass "PRs section delegates to the pr-status skill"
else
    fail "PRs section delegates to the pr-status skill" "pr-status not referenced"
fi

if grep -qE 'Title, PR, State, Reviews, Requested, CI, Notes' "$SKILL_MD"; then
    fail "sitrep does not restate the pr-status column list" \
        "found a verbatim column list, which duplicates pr-status's contract"
else
    pass "sitrep does not restate the pr-status column list"
fi

# --- Test 11: clam-code's chunk vocabulary is gone ---
for legacy in "Chunk" "chunk-of" "Jira"; do
    if grep -qF "$legacy" "$SKILL_MD"; then
        fail "clam-code legacy vocabulary '$legacy' is gone" \
            "still present; this repo has no such artifact"
    else
        pass "clam-code legacy vocabulary '$legacy' is gone"
    fi
done

# --- Test 12: names no sibling plugin ---
for sibling in forge-github landing lego build statusline; do
    if grep -qF "$sibling" "$SKILL_MD"; then
        fail "no reference to the $sibling plugin" "found '$sibling' in the skill"
    else
        pass "no reference to the $sibling plugin"
    fi
done

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests PASSED."
    exit 0
else
    echo "Some tests FAILED."
    exit 1
fi
