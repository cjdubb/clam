#!/bin/bash
# Tests for plugins/tracking/skills/pr-status/SKILL.md — the reporting-only
# PR status table.
#
#   The skill renders the PR-status cache specified in
#   docs/protocols/pr-status-cache.md. It never fetches: refreshing the
#   cache is a separate concern with its own TTL, lock, and atomic-write
#   discipline, owned by whichever refresh engine is installed. It also
#   never acts on a PR — reporting and driving are separate concerns, and
#   this skill owns only the first.
#
# Run: bash plugins/tracking/scripts/pr-status-skill.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../skills/pr-status/SKILL.md"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }

frontmatter() {
    awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1{print} n>=2{exit}' "$1"
}

if [ ! -f "$SKILL_MD" ]; then
    fail "SKILL.md exists at plugins/tracking/skills/pr-status/SKILL.md" \
        "not found at $SKILL_MD"
    echo ""
    echo "Some tests FAILED."
    exit 1
fi
pass "SKILL.md exists at plugins/tracking/skills/pr-status/SKILL.md"

FM=$(frontmatter "$SKILL_MD")
BODY_FLAT=$(tr '\n' ' ' < "$SKILL_MD" | tr -s ' ')

# --- Test 2: frontmatter name field ---
if echo "$FM" | grep -qE '^name:[[:space:]]*pr-status[[:space:]]*$'; then
    pass "frontmatter name: is pr-status"
else
    fail "frontmatter name: is pr-status" "no matching 'name: pr-status' line"
fi

# --- Test 3: reads the cache, by its protocol-specified path ---
if grep -qF '.local/.pr-status.json' "$SKILL_MD"; then
    pass "reads .local/.pr-status.json"
else
    fail "reads .local/.pr-status.json" "cache path not referenced"
fi

# --- Test 4: cites the owning protocol rather than re-specifying it ---
if grep -qF 'docs/protocols/pr-status-cache.md' "$SKILL_MD"; then
    pass "cites docs/protocols/pr-status-cache.md as the field spec"
else
    fail "cites docs/protocols/pr-status-cache.md as the field spec" \
        "protocol not cited"
fi

# --- Test 5: never fetches ---
# A `gh` invocation here would duplicate the refresh engine's job and make a
# glanceable report block on the network.
if grep -qE '(^|[^a-zA-Z-])gh (pr|api|search) ' "$SKILL_MD"; then
    fail "skill issues no gh commands" "found a gh invocation"
else
    pass "skill issues no gh commands"
fi

if echo "$BODY_FLAT" | grep -qF "do not fetch"; then
    pass "states explicitly that it does not fetch"
else
    fail "states explicitly that it does not fetch" "no such statement"
fi

# --- Test 6: resolves the worktree root before reading ---
if grep -qF 'git rev-parse --show-toplevel' "$SKILL_MD"; then
    pass "resolves the worktree root before reading the cache"
else
    fail "resolves the worktree root before reading the cache" \
        "no 'git rev-parse --show-toplevel'"
fi

# --- Test 7: absence is reported, not treated as an error ---
if echo "$BODY_FLAT" | grep -qF "No PR-status cache in this worktree"; then
    pass "absent cache has a plain-language report"
else
    fail "absent cache has a plain-language report" "no absence message"
fi

# --- Test 8: reads prs, not the deprecated mirror ---
if echo "$BODY_FLAT" | grep -qF 'not the deprecated'; then
    pass "reads prs[] rather than the deprecated pr mirror"
else
    fail "reads prs[] rather than the deprecated pr mirror" \
        "no instruction to prefer prs"
fi

# --- Test 9: the 7-column contract ---
if grep -qE 'exactly these 7 columns in this order: Title, PR, State, Reviews, Requested, CI, Notes' "$SKILL_MD"; then
    pass "7-column contract stated"
else
    fail "7-column contract stated" "column rule missing or reworded"
fi

# --- Test 10: tier sort ---
if grep -qE 'Sort rows by .tier. descending' "$SKILL_MD"; then
    pass "rows sort by tier descending"
else
    fail "rows sort by tier descending" "sort rule missing"
fi

# --- Test 11: uses pre-computed tiers rather than deriving readiness ---
if echo "$BODY_FLAT" | grep -qF "Do not recompute a tier"; then
    pass "tiers are consumed, never recomputed"
else
    fail "tiers are consumed, never recomputed" "no such instruction"
fi

# --- Test 12: MERGEABLE is not treated as ready ---
if echo "$BODY_FLAT" | grep -qF "never call a PR ready on the strength of that field"; then
    pass "MERGEABLE is not read as merge-readiness"
else
    fail "MERGEABLE is not read as merge-readiness" "caveat missing"
fi

# --- Test 13: report-only boundary ---
if echo "$BODY_FLAT" | grep -qF "Report only."; then
    pass "report-only rule present"
else
    fail "report-only rule present" "no 'Report only.' rule"
fi

for verb in merge enqueue close approve; do
    if echo "$BODY_FLAT" | grep -qE "Never $verb|Never merge, enqueue"; then
        pass "report-only rule forbids '$verb'"
    else
        fail "report-only rule forbids '$verb'" "verb not named in the prohibition"
    fi
done

# --- Test 14: names no sibling plugin ---
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
