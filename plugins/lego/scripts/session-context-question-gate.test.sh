#!/bin/bash
# Tests for Contract: B01 standing-rule-question-gate (the docblock
# immediately above the "NotImplemented: B01" placeholder line inside
# session-context.sh's heredoc). Verifies the hook's stdout gains a new
# standing rule requiring every orchestrator question to be explicitly
# answered before proceeding, covering all 4 invariant sub-points and both
# contract edge cases, without disturbing the existing standing rules.
#
# Hermetic: runs the hook with CLAUDE_PROJECT_DIR pointed at an empty temp
# dir (no .local/blocks.md), so stdout is exactly the static heredoc
# content — no block-map section is appended.
#
# Token checks use word-boundary regex stems (not the contract's exact
# phrasing) since the contract text itself is, pre-implementation, embedded
# verbatim in the stub's heredoc output — matching it verbatim would pass
# against the stub and could reject a correctly-worded but differently
# phrased implementation. The "NotImplemented" removal check is what MUST
# (and does) fail against the current stub.
#
# Run: bash plugins/lego/scripts/session-context-question-gate.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-context.sh"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Fixed-string (literal) presence check, case-sensitive.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Case-insensitive extended-regex presence check (word-stem matching, e.g.
# "\brestat" catches restate/restated/restating).
has_re() { # content ere
  if grep -qiE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

if [[ ! -f "$HOOK" ]]; then
  echo "FAIL  session-context.sh not found at $HOOK"
  exit 1
fi

TMPDIR_HOOK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_HOOK"' EXIT

RAW=$(CLAUDE_PROJECT_DIR="$TMPDIR_HOOK" bash "$HOOK")

if [[ -z "$RAW" ]]; then
  echo "FAIL  hook produced no output"
  exit 1
fi

# Text of the "## Standing rules" section: from that heading to the next
# top-level "## " heading, or end of output if none follows (same pattern as
# plugins/lego/scripts/plan-lifecycle.test.sh's section_text).
standing_rules_section() { # content
  awk '
    index($0, "## Standing rules") == 1 { capture=1; print; next }
    capture && index($0, "## ") == 1 { exit }
    capture { print }
  ' <<<"$1"
}

SECTION="$(standing_rules_section "$RAW")"

check "## Standing rules heading found in hook output" \
  "$([[ -n "$SECTION" ]] && echo yes || echo no)" "yes"

# --- 1. NotImplemented placeholder replaced -------------------------------
check "NotImplemented: B01 placeholder removed" \
  "$(has_f "$RAW" 'NotImplemented: B01')" "no"

# --- 2/3. Required semantic tokens, within the Standing rules section -----
# Sub-point (1): all questions must be answered.
check "Standing rules section token: question(s)" \
  "$(has_re "$SECTION" '\bquestions?\b')" "yes"
check "Standing rules section token: answer(ed)" \
  "$(has_re "$SECTION" '\banswer(ed|s)?\b')" "yes"

# Sub-point (2): partial answers are insufficient.
check "Standing rules section token: partial" \
  "$(has_re "$SECTION" '\bpartial\b')" "yes"
check "Standing rules section token: insufficient/not enough/don't count" \
  "$(has_re "$SECTION" 'insufficient|not (count|enough|sufficient)|(don.t|does.?n.t) count')" "yes"

# Sub-point (3): unanswered questions must be restated.
check "Standing rules section token: restate(d)" \
  "$(has_re "$SECTION" '\brestat')" "yes"

# Sub-point (4): no background work or next-step progression while
# questions remain open.
check "Standing rules section token: background" \
  "$(has_re "$SECTION" '\bbackground\b')" "yes"

# --- 4. Edge cases ----------------------------------------------------------
# Skip/decline counts as answered.
check "Standing rules section token: skip/decline (counts as answered)" \
  "$(has_re "$SECTION" '\b(skip|declin)')" "yes"

# A bare "go" accepting defaults counts as answering all questions.
check "Standing rules section token: go (accepting defaults)" \
  "$(has_re "$SECTION" '"go"|`go`|\bgo\b.{0,40}default|default.{0,40}\bgo\b')" "yes"

# --- 5. Existing standing rules survive unchanged --------------------------
check "existing rule survives: Clarify and verify; never guess" \
  "$(has_f "$SECTION" 'Clarify and verify; never guess')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
