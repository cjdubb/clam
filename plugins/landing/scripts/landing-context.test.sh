#!/bin/bash
# Functional test for landing-context.sh: SessionStart injection of the
# repo's landing policy. Covers the with-profile render (parsed strategy /
# target / merged-by, inline-comment and whitespace stripping,
# frontmatter-only parsing with a body decoy, control-byte sanitization,
# the 40-char value cap, unset-key fallback), the no-profile /landing:init
# nudge, the fail-open paths (no jq on PATH, no cwd in the payload, file
# without frontmatter), and that every render is valid hookSpecificOutput
# JSON with a SessionStart event name.
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

# 1. Full profile: parsed keys render, inline comment stripped, /landing:land
#    referenced, output is valid SessionStart hook JSON. The body carries a
#    decoy 'landing-strategy:' line that must NOT be parsed (frontmatter only).
WD1="$TMPROOT/with-profile"; mkdir -p "$WD1/.claude"
cat > "$WD1/.claude/clam-profile.md" <<'EOF'
---
profile-version: 1
landing-strategy: github-pr   # github-pr | local-merge
landing-target:   master
landing-merged-by: user
---
# Workflow notes
landing-strategy: body-decoy
EOF
raw=$(run_hook "$(payload "$WD1")")
out=$(ctx "$(payload "$WD1")")
check "with-profile output is valid JSON" \
  "$(printf '%s' "$raw" | jq -e . >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "hookEventName is SessionStart" \
  "$(printf '%s' "$raw" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "SessionStart"
check "strategy parsed with inline comment stripped" "$(has "$out" 'strategy=github-pr,')" "yes"
check "target parsed with surrounding whitespace trimmed" "$(has "$out" 'target=master,')" "yes"
check "merged-by parsed" "$(has "$out" 'merged-by=user')" "yes"
check "context points at /landing:land" "$(has "$out" '/landing:land')" "yes"
check "body decoy value is not parsed (frontmatter only)" "$(has "$out" 'body-decoy')" "no"

# 2. Missing key renders as unset (no crash, no empty '=,' artifact).
WD2="$TMPROOT/partial"; mkdir -p "$WD2/.claude"
cat > "$WD2/.claude/clam-profile.md" <<'EOF'
---
landing-strategy: local-merge
landing-target: master
---
EOF
out=$(ctx "$(payload "$WD2")")
check "local-merge strategy renders" "$(has "$out" 'strategy=local-merge,')" "yes"
check "missing merged-by renders as unset" "$(has "$out" 'merged-by=unset')" "yes"

# 3. No profile: the /landing:init nudge renders (and not the policy line).
WD3="$TMPROOT/bare"; mkdir -p "$WD3"
out=$(ctx "$(payload "$WD3")")
check "no-profile nudge points at /landing:init" "$(has "$out" '/landing:init')" "yes"
check "no-profile render carries no strategy= line" "$(has "$out" 'strategy=')" "no"

# 4. Fail-open: payload without cwd -> no output, exit 0.
out=$(printf '{"hook_event_name":"SessionStart"}' | bash "$HOOK" 2>/dev/null); rc=$?
check "no-cwd payload exits 0" "$rc" "0"
check "no-cwd payload produces no output" "${#out}" "0"

# 5. Fail-open: no jq on PATH -> no output, exit 0. bash is resolved to an
#    absolute path FIRST — a bare `PATH=… bash` would apply the empty PATH to
#    the bash lookup itself and fail with 127 before the hook ever ran.
mkdir -p "$TMPROOT/emptybin"
BASH_BIN=$(command -v bash)
out=$(printf '%s' "$(payload "$WD1")" | PATH="$TMPROOT/emptybin" "$BASH_BIN" "$HOOK" 2>/dev/null); rc=$?
check "missing jq exits 0" "$rc" "0"
check "missing jq produces no output" "${#out}" "0"

# 6. File without a leading '---' has no frontmatter: keys all read as unset
#    (the file's key-shaped lines are body, not frontmatter).
WD4="$TMPROOT/no-frontmatter"; mkdir -p "$WD4/.claude"
cat > "$WD4/.claude/clam-profile.md" <<'EOF'
landing-strategy: github-pr
landing-target: master
EOF
out=$(ctx "$(payload "$WD4")")
check "file without frontmatter yields strategy=unset" "$(has "$out" 'strategy=unset')" "yes"

# 7. Sanitization: a control byte inside a value is dropped; an oversized
#    value is capped at its first 40 characters.
WD5="$TMPROOT/hostile"; mkdir -p "$WD5/.claude"
LONG=$(printf 'A%.0s' $(seq 1 50))
printf -- '---\nlanding-strategy: git\033hub-pr\nlanding-target: %s\nlanding-merged-by: user\n---\n' "$LONG" \
  > "$WD5/.claude/clam-profile.md"
out=$(ctx "$(payload "$WD5")")
check "control byte inside a value is stripped" "$(has "$out" 'strategy=github-pr,')" "yes"
check "oversized value is capped at 40 chars" \
  "$(has "$out" "target=$(printf 'A%.0s' $(seq 1 40)),")" "yes"
check "41st char of an oversized value is dropped" \
  "$(has "$out" "$(printf 'A%.0s' $(seq 1 41))")" "no"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
