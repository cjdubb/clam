#!/bin/bash
# Tests for the merge-manifest / delete-make-progress contract (B05 + B06):
#
#   B05 — merge-manifest: removes the make-progress entry from the
#   marketplace manifest; bumps tracking's version and description in
#   plugins/tracking/.claude-plugin/plugin.json (the single source of
#   truth for version — marketplace.json carries no version field) to
#   reflect the absorbed make-progress functionality; updates README.md
#   and MIGRATION.md references; updates the debugging plugin's
#   b10-registration.test.sh fixture (it embeds a byte-for-byte snapshot
#   of the marketplace tracking entry, which the description bump would
#   otherwise break).
#
#   B06 — delete-make-progress: removes the now-empty plugins/make-progress/
#   directory entirely.
#
# Run: bash plugins/tracking/scripts/merge-manifest.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
PLUGIN_JSON="$ROOT/plugins/tracking/.claude-plugin/plugin.json"
README="$ROOT/README.md"
MIGRATION="$ROOT/MIGRATION.md"
MAKE_PROGRESS_DIR="$ROOT/plugins/make-progress"
B10_TEST="$ROOT/plugins/debugging/scripts/b10-registration.test.sh"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }

check() { # label got expected
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1" "got '$2', expected '$3'"
    fi
}

if [ ! -f "$MARKETPLACE" ]; then
    fail "marketplace.json exists" "not found at $MARKETPLACE"
    echo ""
    echo "Some tests FAILED."
    exit 1
fi

# ============================================================
# B05 — marketplace.json
# ============================================================

check "marketplace.json parses as valid JSON" \
    "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

# --- Test 1: no make-progress entry ---
MP_COUNT=$(jq '[.plugins[]? | select(.name=="make-progress")] | length' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json has no 'make-progress' plugins[] entry" "$MP_COUNT" "0"

# --- Test 2: tracking entry present ---
TRACKING_COUNT=$(jq '[.plugins[]? | select(.name=="tracking")] | length' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json has exactly one 'tracking' plugins[] entry" "$TRACKING_COUNT" "1"

# --- Test 3: marketplace tracking entry has no version field ---
check "marketplace.json tracking entry has no version field (plugin.json is single source of truth)" \
    "$(jq -e '.plugins[]? | select(.name=="tracking") | .version' "$MARKETPLACE" >/dev/null 2>&1 && echo present || echo absent)" "absent"

# --- Test 4: plugin.json version bumped past 0.2.0 ---
if [ -f "$PLUGIN_JSON" ]; then
    PJ_VERSION=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
    if [ "$PJ_VERSION" != "0.2.0" ] && [ -n "$PJ_VERSION" ]; then
        pass "plugin.json tracking version is bumped past '0.2.0' (got '$PJ_VERSION')"
    else
        fail "plugin.json tracking version is bumped past '0.2.0'" \
            "got '$PJ_VERSION'"
    fi
else
    fail "plugin.json tracking version is bumped past '0.2.0'" \
        "plugin.json not found at $PLUGIN_JSON"
fi

# ============================================================
# B05 — README.md
# ============================================================

if [ -f "$README" ]; then
    # --- Test 5: no standalone make-progress row in the Plugins table ---
    if grep -qF '| make-progress |' "$README"; then
        fail "README.md has no standalone '| make-progress |' table row" \
            "found a '| make-progress |' cell"
    else
        pass "README.md has no standalone '| make-progress |' table row"
    fi
else
    fail "README.md exists" "not found at $README"
fi

# ============================================================
# B05 — MIGRATION.md
# ============================================================

if [ -f "$MIGRATION" ]; then
    # Extracts the body of the "## tracking" section, up to the next
    # top-level "## " heading.
    TRACKING_SECTION=$(awk '
        /^## tracking/ { flag=1; next }
        /^## / { flag=0 }
        flag { print }
    ' "$MIGRATION")

    # --- Test 6a: make-progress mentioned within the tracking section ---
    if echo "$TRACKING_SECTION" | grep -qi 'make-progress'; then
        pass "MIGRATION.md's tracking section mentions make-progress (absorbed functionality)"
    else
        fail "MIGRATION.md's tracking section mentions make-progress (absorbed functionality)" \
            "no 'make-progress' mention found between '## tracking' and the next '## ' heading"
    fi

    # --- Test 6b: make-progress is not given its own standalone section ---
    if grep -qE '^## make-progress( |$)' "$MIGRATION"; then
        fail "MIGRATION.md has no standalone '## make-progress' section" \
            "found a standalone '## make-progress' heading"
    else
        pass "MIGRATION.md has no standalone '## make-progress' section"
    fi
else
    fail "MIGRATION.md exists" "not found at $MIGRATION"
fi

# ============================================================
# B06 — plugins/make-progress/ deletion
# ============================================================

# --- Test 7: plugin directory gone ---
if [ -d "$MAKE_PROGRESS_DIR" ]; then
    fail "plugins/make-progress/ does not exist as a directory" "directory still present"
else
    pass "plugins/make-progress/ does not exist as a directory"
fi

# --- Test 8: no files remain under plugins/make-progress ---
REMAINING=$(find "$MAKE_PROGRESS_DIR" 2>/dev/null)
if [ -z "$REMAINING" ]; then
    pass "no files remain under plugins/make-progress"
else
    fail "no files remain under plugins/make-progress" \
        "find returned: $(echo "$REMAINING" | tr '\n' ' ')"
fi

# ============================================================
# B05 — debugging plugin's b10-registration.test.sh fixture stays in sync
#
# That test embeds a byte-for-byte snapshot of the marketplace.json
# 'tracking' entry (BASELINE_ENTRIES) to guard other entries against
# accidental edits. B05 deliberately changes the tracking entry's version
# and description, so the fixture's snapshot must be updated in the same
# change or this suite starts failing.
# ============================================================

if [ -f "$B10_TEST" ]; then
    B10_OUTPUT=$(bash "$B10_TEST" 2>&1)
    B10_STATUS=$?
    if [ "$B10_STATUS" -eq 0 ]; then
        pass "debugging plugin's b10-registration.test.sh still passes after the merge"
    else
        fail "debugging plugin's b10-registration.test.sh still passes after the merge" \
            "exited $B10_STATUS; output: $(echo "$B10_OUTPUT" | grep -F FAIL | tr '\n' ' ')"
    fi
else
    fail "debugging plugin's b10-registration.test.sh still passes after the merge" \
        "not found at $B10_TEST"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
