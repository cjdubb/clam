#!/bin/bash
# Tests for the B02 capture-hook migration: capture.sh, capture.test.sh, and
# platform.sh must move from the make-progress plugin into the tracking
# plugin, with capture.sh's real implementation (not the scaffold stub) and
# its full test suite both present and passing from the new location.
#
# Run: bash plugins/tracking/scripts/capture-migration.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_SH="$SCRIPT_DIR/capture.sh"
PLATFORM_SH="$SCRIPT_DIR/../lib/platform.sh"
CAPTURE_TEST_SH="$SCRIPT_DIR/capture.test.sh"

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

# --- Test 1: capture.sh exists and is executable ---
if [ -f "$CAPTURE_SH" ]; then
    pass "capture.sh exists at plugins/tracking/scripts/capture.sh"
else
    fail "capture.sh exists at plugins/tracking/scripts/capture.sh" "not found at $CAPTURE_SH"
fi

if [ -x "$CAPTURE_SH" ]; then
    pass "capture.sh is executable"
else
    fail "capture.sh is executable" "missing execute permission on $CAPTURE_SH"
fi

# --- Test 2: platform.sh exists ---
if [ -f "$PLATFORM_SH" ]; then
    pass "platform.sh exists at plugins/tracking/lib/platform.sh"
else
    fail "platform.sh exists at plugins/tracking/lib/platform.sh" "not found at $PLATFORM_SH"
fi

# --- Test 3: capture.sh sources platform.sh via the relative scripts->lib path ---
if [ -f "$CAPTURE_SH" ] && grep -q '\.\./lib/platform\.sh' "$CAPTURE_SH"; then
    pass "capture.sh sources ../lib/platform.sh"
else
    fail "capture.sh sources ../lib/platform.sh" "no matching source line found"
fi

# --- Test 4: capture.sh is the real implementation, not the scaffold stub ---
if [ -f "$CAPTURE_SH" ] && grep -q "NotImplemented" "$CAPTURE_SH"; then
    fail "capture.sh is not a stub" "still contains NotImplemented"
else
    pass "capture.sh is not a stub"
fi

# --- Test 5: capture.test.sh exists (full suite migrated from make-progress) ---
if [ -f "$CAPTURE_TEST_SH" ]; then
    pass "capture.test.sh exists at plugins/tracking/scripts/capture.test.sh"
else
    fail "capture.test.sh exists at plugins/tracking/scripts/capture.test.sh" "not found at $CAPTURE_TEST_SH"
fi

# --- Test 6: capture.test.sh passes from the new location ---
if [ -f "$CAPTURE_TEST_SH" ]; then
    if bash "$CAPTURE_TEST_SH" >/tmp/capture-migration-test-output.$$ 2>&1; then
        pass "capture.test.sh passes from plugins/tracking/scripts/"
    else
        fail "capture.test.sh passes from plugins/tracking/scripts/" \
            "exited non-zero; see /tmp/capture-migration-test-output.$$"
    fi
    rm -f "/tmp/capture-migration-test-output.$$"
else
    fail "capture.test.sh passes from plugins/tracking/scripts/" "capture.test.sh not found, cannot run"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
