#!/bin/bash
# Functional test for build-context.sh: SessionStart injection of delivery
# framework context, adapting to which companion plugins (landing, lego,
# tracking) are present under <cwd>/plugins/. Covers: all-companions-present
# (all three per-companion markers + the standing sync-pr instruction),
# no-companions (minimal context, standing instruction still present, no
# per-companion markers), two partial combinations (only lego; only landing+
# tracking) proving independent per-companion detection, an empty-but-
# existing companion directory (still "present" per the contract's edge
# case), the never-sources-companion-scripts invariant (a companion script
# that would leave a side-effect marker if executed/sourced must never run),
# and the fail-open paths (no jq, no cwd, malformed JSON input).
# Hermetic: each case renders against a fresh temp cwd.
# Run: bash plugins/build/scripts/b03-build-context.test.sh (exits
# non-zero on failure)
#
# Contract: B02 test-rename
#
# Behavior:
#   All test assertions reference "/build:sync-pr" (the renamed skill
#   namespace) and "build-context.sh" (the renamed script). The HOOK
#   variable points to build-context.sh. Test labels use the new names.
#   Test logic and coverage are unchanged from the deliver-context.test.sh
#   original — this is a rename of references, not a test rewrite.
#
# Invariants:
#   - No remaining references to "deliver" as a plugin name, script name,
#     or skill namespace in test labels or assertions
#   - All existing test cases preserved (no coverage regression)
#   - The HOOK variable points at build-context.sh, not deliver-context.sh

# NotImplemented: B02 — update HOOK variable to point at build-context.sh,
# update all assertion strings from "/deliver:sync-pr" to "/build:sync-pr",
# and update test labels from "deliver" to "build" references.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/build-context.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

payload() { # cwd
  printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$1"
}

run_hook() { # json
  printf '%s' "$1" | bash "$HOOK" 2>/dev/null
}

ctx() { # json -> the additionalContext string
  run_hook "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

has() { # haystack needle (case-insensitive fixed-string)
  printf '%s' "$1" | grep -qiF -- "$2" && echo yes || echo no
}

# ---------------------------------------------------------------------------
# 1. All companions present: all three per-companion markers plus the
#    standing PR-description-sync instruction; valid SessionStart hook JSON.
# ---------------------------------------------------------------------------
WD1="$TMPROOT/all"
mkdir -p "$WD1/plugins/landing" "$WD1/plugins/lego" "$WD1/plugins/tracking"
raw=$(run_hook "$(payload "$WD1")")
out=$(ctx "$(payload "$WD1")")

check "all-companions output is valid JSON" \
  "$(printf '%s' "$raw" | jq -e . >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "all-companions hookEventName is SessionStart" \
  "$(printf '%s' "$raw" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "SessionStart"
check "all-companions context includes the landing merge-policy marker" \
  "$(has "$out" 'merge policy')" "yes"
check "all-companions context includes the landing PR-creation marker" \
  "$(has "$out" 'PR creation')" "yes"
check "all-companions context includes the lego dispatch marker" \
  "$(has "$out" 'dispatch')" "yes"
check "all-companions context includes the tracking state-lifecycle marker" \
  "$(has "$out" 'state lifecycle')" "yes"
check "all-companions context includes the /deliver:sync-pr standing instruction" \
  "$(has "$out" '/deliver:sync-pr')" "yes"

# ---------------------------------------------------------------------------
# 2. No companions: plugins/ absent entirely (contract edge case: "repo with
#    no plugins/ directory"). Standing instruction still present (always
#    injected); none of the per-companion markers appear.
# ---------------------------------------------------------------------------
WD2="$TMPROOT/none"
mkdir -p "$WD2"
out=$(ctx "$(payload "$WD2")")

check "no-companions context still includes the /deliver:sync-pr standing instruction" \
  "$(has "$out" '/deliver:sync-pr')" "yes"
check "no-companions context has no landing merge-policy marker" \
  "$(has "$out" 'merge policy')" "no"
check "no-companions context has no lego dispatch marker" \
  "$(has "$out" 'dispatch')" "no"
check "no-companions context has no tracking state-lifecycle marker" \
  "$(has "$out" 'state lifecycle')" "no"
check "no-companions context is non-empty (minimal purpose/suggestion context)" \
  "$([[ -n "$out" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 3. Partial: only lego present.
# ---------------------------------------------------------------------------
WD3="$TMPROOT/only-lego"
mkdir -p "$WD3/plugins/lego"
out=$(ctx "$(payload "$WD3")")

check "only-lego context includes the dispatch marker" \
  "$(has "$out" 'dispatch')" "yes"
check "only-lego context has no landing merge-policy marker" \
  "$(has "$out" 'merge policy')" "no"
check "only-lego context has no tracking state-lifecycle marker" \
  "$(has "$out" 'state lifecycle')" "no"

# ---------------------------------------------------------------------------
# 4. Partial: only landing + tracking present (lego absent).
# ---------------------------------------------------------------------------
WD4="$TMPROOT/landing-tracking"
mkdir -p "$WD4/plugins/landing" "$WD4/plugins/tracking"
out=$(ctx "$(payload "$WD4")")

check "landing+tracking context includes the landing merge-policy marker" \
  "$(has "$out" 'merge policy')" "yes"
check "landing+tracking context includes the tracking state-lifecycle marker" \
  "$(has "$out" 'state lifecycle')" "yes"
check "landing+tracking context has no lego dispatch marker" \
  "$(has "$out" 'dispatch')" "no"

# ---------------------------------------------------------------------------
# 5. Edge case: companion directory exists but is empty -> still "present".
# ---------------------------------------------------------------------------
WD5="$TMPROOT/empty-landing"
mkdir -p "$WD5/plugins/landing"
out=$(ctx "$(payload "$WD5")")

check "empty-but-existing landing dir is still treated as present" \
  "$(has "$out" 'merge policy')" "yes"

# ---------------------------------------------------------------------------
# 6. Invariant: companion detection is directory-based, never sources or
#    executes companion scripts. A companion script that would leave a
#    side-effect marker if run must never fire.
# ---------------------------------------------------------------------------
WD6="$TMPROOT/no-source"
mkdir -p "$WD6/plugins/landing/scripts"
MARKER="$WD6/sourced-marker"
cat > "$WD6/plugins/landing/scripts/evil.sh" <<EOF
#!/bin/bash
touch "$MARKER"
EOF
chmod +x "$WD6/plugins/landing/scripts/evil.sh"
out=$(ctx "$(payload "$WD6")")

check "companion presence still detected without sourcing its scripts" \
  "$(has "$out" 'merge policy')" "yes"
check "companion script is never sourced/executed (no side-effect marker left)" \
  "$([ -f "$MARKER" ] && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# 7. Fail-open: payload without cwd -> no output, exit 0.
# ---------------------------------------------------------------------------
out=$(printf '{"hook_event_name":"SessionStart"}' | bash "$HOOK" 2>/dev/null); rc=$?
check "no-cwd payload exits 0" "$rc" "0"
check "no-cwd payload produces no output" "${#out}" "0"

# ---------------------------------------------------------------------------
# 8. Fail-open: malformed (non-JSON) input -> no output, exit 0.
# ---------------------------------------------------------------------------
out=$(printf 'not valid json' | bash "$HOOK" 2>/dev/null); rc=$?
check "malformed-json payload exits 0" "$rc" "0"
check "malformed-json payload produces no output" "${#out}" "0"

# ---------------------------------------------------------------------------
# 9. Fail-open: no jq on PATH -> no output, exit 0. bash is resolved to an
#    absolute path FIRST — a bare `PATH=… bash` would apply the empty PATH to
#    the bash lookup itself and fail with 127 before the hook ever ran.
# ---------------------------------------------------------------------------
mkdir -p "$TMPROOT/emptybin"
BASH_BIN=$(command -v bash)
out=$(printf '%s' "$(payload "$WD1")" | PATH="$TMPROOT/emptybin" "$BASH_BIN" "$HOOK" 2>/dev/null); rc=$?
check "missing jq exits 0" "$rc" "0"
check "missing jq produces no output" "${#out}" "0"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
