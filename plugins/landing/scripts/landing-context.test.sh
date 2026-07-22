#!/bin/bash
# Functional test for landing-context.sh: SessionStart injection of the
# repo's landing policy, now read from the JSONC profile
# (.claude/clam-profile.jsonc, profile-version 2, merge/deploy sections).
# Covers the with-profile render (parsed merge.strategy / merge.target /
# merge.merged-by, comment stripping with a decoy value, unknown/extra keys
# ignored, no-merge-section and partial-merge unset rendering, special
# characters inside values), the no-profile /landing:init nudge, the
# legacy-.md-is-never-consulted invariant, and the fail-open paths (no jq
# on PATH, no cwd in the payload, empty/whitespace-only cwd, unreadable
# profile, invalid JSON left after comment stripping).
# Hermetic: each case renders against a fresh temp cwd.
# Run: bash plugins/landing/scripts/landing-context.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/landing-context.sh"

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

has() { # haystack needle
  printf '%s' "$1" | grep -qF "$2" && echo yes || echo no
}

# 1. Full profile: merge.strategy/target/merged-by parsed, a full-line
#    decoy comment claiming a different strategy is stripped and never
#    parsed, /landing:land referenced, output is valid SessionStart hook
#    JSON.
WD1="$TMPROOT/with-profile"; mkdir -p "$WD1/.claude"
cat > "$WD1/.claude/clam-profile.jsonc" <<'EOF'
{
  "profile-version": 2,

  // strategy: local-merge (decoy comment value, must not be parsed)
  "merge": {
    "strategy": "github-pr",
    "target": "master",
    "merged-by": "user"
  }
}
EOF
raw=$(run_hook "$(payload "$WD1")")
out=$(ctx "$(payload "$WD1")")
check "with-profile output is valid JSON" \
  "$(printf '%s' "$raw" | jq -e . >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "hookEventName is SessionStart" \
  "$(printf '%s' "$raw" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "SessionStart"
check "strategy parsed from merge.strategy" "$(has "$out" 'strategy=github-pr,')" "yes"
check "target parsed from merge.target" "$(has "$out" 'target=master,')" "yes"
check "merged-by parsed from merge.merged-by" "$(has "$out" 'merged-by=user')" "yes"
check "context points at /landing:land" "$(has "$out" '/landing:land')" "yes"
check "decoy comment value is not parsed (comments stripped)" "$(has "$out" 'local-merge')" "no"

# 2. A second concrete strategy/values combination renders correctly too
#    (not just a single hardcoded case).
WD2="$TMPROOT/local-merge-profile"; mkdir -p "$WD2/.claude"
cat > "$WD2/.claude/clam-profile.jsonc" <<'EOF'
{
  "profile-version": 2,
  "merge": {
    "strategy": "local-merge",
    "target": "master",
    "merged-by": "orchestrator"
  }
}
EOF
out=$(ctx "$(payload "$WD2")")
check "local-merge strategy renders" "$(has "$out" 'strategy=local-merge,')" "yes"
check "orchestrator merged-by renders" "$(has "$out" 'merged-by=orchestrator')" "yes"

# 3. Profile with no merge section at all: all three values render as
#    "unset" (no crash, no empty '=,' artifact).
WD3="$TMPROOT/no-merge-section"; mkdir -p "$WD3/.claude"
cat > "$WD3/.claude/clam-profile.jsonc" <<'EOF'
{
  "profile-version": 2
}
EOF
out=$(ctx "$(payload "$WD3")")
check "no merge section: strategy unset" "$(has "$out" 'strategy=unset')" "yes"
check "no merge section: target unset" "$(has "$out" 'target=unset')" "yes"
check "no merge section: merged-by unset" "$(has "$out" 'merged-by=unset')" "yes"

# 4. Merge section present but missing merged-by: that key alone renders
#    unset while the present keys still render.
WD4="$TMPROOT/partial-merge"; mkdir -p "$WD4/.claude"
cat > "$WD4/.claude/clam-profile.jsonc" <<'EOF'
{
  "profile-version": 2,
  "merge": {
    "strategy": "github-pr",
    "target": "master"
  }
}
EOF
out=$(ctx "$(payload "$WD4")")
check "partial merge: strategy still renders" "$(has "$out" 'strategy=github-pr,')" "yes"
check "partial merge: missing merged-by renders unset" "$(has "$out" 'merged-by=unset')" "yes"

# 5. Extra/unknown keys (top-level and nested inside merge, plus a whole
#    unrelated deploy section) are ignored, not fatal.
WD5="$TMPROOT/extra-keys"; mkdir -p "$WD5/.claude"
cat > "$WD5/.claude/clam-profile.jsonc" <<'EOF'
{
  "profile-version": 2,
  "future-seam": { "some-key": "some-value" },
  "merge": {
    "strategy": "github-pr",
    "target": "master",
    "merged-by": "user",
    "unknown-nested-key": "ignored"
  },
  "deploy": {
    "trigger": "manual"
  }
}
EOF
out=$(ctx "$(payload "$WD5")")
check "extra top-level and nested keys don't break parsing" "$(has "$out" 'strategy=github-pr,')" "yes"
check "extra keys: merged-by still renders" "$(has "$out" 'merged-by=user')" "yes"

# 6. No profile at all: the /landing:init nudge renders (and not the
#    policy line).
WD6="$TMPROOT/bare"; mkdir -p "$WD6"
out=$(ctx "$(payload "$WD6")")
check "no-profile nudge points at /landing:init" "$(has "$out" '/landing:init')" "yes"
check "no-profile render carries no strategy= line" "$(has "$out" 'strategy=')" "no"

# 7. Invariant: only .claude/clam-profile.jsonc is read. A repo with only
#    the legacy .md profile (valid v1 content) must be treated as having
#    no profile at all -- the legacy path is never consulted.
WD7="$TMPROOT/legacy-md-only"; mkdir -p "$WD7/.claude"
cat > "$WD7/.claude/clam-profile.md" <<'EOF'
---
profile-version: 1
landing-strategy: github-pr
landing-target: master
landing-merged-by: user
---
# Workflow notes
EOF
out=$(ctx "$(payload "$WD7")")
check "legacy .md-only repo gets the /landing:init nudge" "$(has "$out" '/landing:init')" "yes"
check "legacy .md is never parsed for policy values" "$(has "$out" 'strategy=')" "no"

# 8. Values containing special characters: jq handles escaping. An
#    apostrophe and an escaped double-quote inside JSON string values must
#    render intact and must not produce broken JSON output.
WD8="$TMPROOT/special-chars"; mkdir -p "$WD8/.claude"
cat > "$WD8/.claude/clam-profile.jsonc" <<'EOF'
{
  "profile-version": 2,
  "merge": {
    "strategy": "github-pr",
    "target": "o'brien-branch",
    "merged-by": "ann\"e"
  }
}
EOF
raw=$(run_hook "$(payload "$WD8")")
out=$(ctx "$(payload "$WD8")")
check "special-chars output is still valid JSON" \
  "$(printf '%s' "$raw" | jq -e . >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "apostrophe in value renders intact" "$(has "$out" "target=o'brien-branch,")" "yes"
check "escaped quote in value renders intact" "$(has "$out" 'merged-by=ann"e')" "yes"

# 9. Fail-open: payload without cwd -> no output, exit 0.
out=$(printf '{"hook_event_name":"SessionStart"}' | bash "$HOOK" 2>/dev/null); rc=$?
check "no-cwd payload exits 0" "$rc" "0"
check "no-cwd payload produces no output" "${#out}" "0"

# 10. Edge case: empty-string cwd is treated as missing -> fail-open.
out=$(printf '%s' "$(payload "")" | bash "$HOOK" 2>/dev/null); rc=$?
check "empty-string cwd exits 0" "$rc" "0"
check "empty-string cwd produces no output" "${#out}" "0"

# 11. Edge case: whitespace-only cwd is treated as missing -> fail-open.
out=$(printf '%s' "$(payload "   ")" | bash "$HOOK" 2>/dev/null); rc=$?
check "whitespace-only cwd exits 0" "$rc" "0"
check "whitespace-only cwd produces no output" "${#out}" "0"

# 12. Fail-open: no jq on PATH -> no output, exit 0. bash is resolved to an
#    absolute path FIRST -- a bare `PATH=… bash` would apply the empty PATH
#    to the bash lookup itself and fail with 127 before the hook ever ran.
mkdir -p "$TMPROOT/emptybin"
BASH_BIN=$(command -v bash)
out=$(printf '%s' "$(payload "$WD1")" | PATH="$TMPROOT/emptybin" "$BASH_BIN" "$HOOK" 2>/dev/null); rc=$?
check "missing jq exits 0" "$rc" "0"
check "missing jq produces no output" "${#out}" "0"

# 13. Fail-open: unreadable profile -> no output, exit 0. Skipped when
#     running as root, since root ignores file permission bits.
if [[ "$(id -u)" != "0" ]]; then
  WD13="$TMPROOT/unreadable"; mkdir -p "$WD13/.claude"
  cat > "$WD13/.claude/clam-profile.jsonc" <<'EOF'
{
  "profile-version": 2,
  "merge": { "strategy": "github-pr", "target": "master", "merged-by": "user" }
}
EOF
  chmod 000 "$WD13/.claude/clam-profile.jsonc"
  out=$(printf '%s' "$(payload "$WD13")" | bash "$HOOK" 2>/dev/null); rc=$?
  chmod 644 "$WD13/.claude/clam-profile.jsonc"
  check "unreadable profile exits 0" "$rc" "0"
  check "unreadable profile produces no output" "${#out}" "0"
else
  echo "SKIP  unreadable-profile case (running as root)"
fi

# 14. Fail-open: invalid JSON left over after comment stripping (a
#     trailing comma, which is JSONC-invalid and not tolerated by jq's
#     strict JSON parser) -> no output, exit 0.
WD14="$TMPROOT/invalid-json"; mkdir -p "$WD14/.claude"
cat > "$WD14/.claude/clam-profile.jsonc" <<'EOF'
{
  "profile-version": 2,
  "merge": {
    "strategy": "github-pr",
    "target": "master",
  }
}
EOF
out=$(printf '%s' "$(payload "$WD14")" | bash "$HOOK" 2>/dev/null); rc=$?
check "invalid JSON after comment strip exits 0" "$rc" "0"
check "invalid JSON after comment strip produces no output" "${#out}" "0"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
