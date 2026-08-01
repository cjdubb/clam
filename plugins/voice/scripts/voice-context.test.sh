#!/bin/bash
# Contract tests for B01 voice-context-hook.
#
# Source of truth: the docblock atop voice-context.sh, specifically its
# BEGIN/END CANONICAL TEXT marker block and reconstruction rule (strip the
# leading "# " from each line between the markers; a line that is exactly
# "#" is an empty line; hard line breaks are preserved exactly, no
# rewrapping). Byte-exactness is contractual: the emitted block must equal
# the canonical text byte-for-byte with a single trailing newline.
#
# This suite carries its OWN verbatim copy of the raw marker block
# (RAW_BLOCK below — the exact "# "-prefixed lines as they appear between
# the docblock's BEGIN/END markers) rather than reading voice-context.sh's
# comments at runtime. That keeps this suite an independent check rather
# than a self-consistency check against the same file it is testing,
# consistent with this repo's "never grep the script's own source for the
# oracle" convention (see ask-in-text's block-question.test.sh). The
# reconstruction rule itself is applied programmatically via awk (never
# hand-flattened) to remove transcription risk from stripping 16 lines of
# dense prose by hand.
#
# Black-box only: exercises voice-context.sh as a real subprocess through
# its public interface (stdin -> stdout/stderr/exit code). Hermetic,
# cwd-independent (all paths resolved from this script's own location), no
# network, no mutation.
#
# Run: bash plugins/voice/scripts/voice-context.test.sh (non-zero exit on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/voice-context.sh"
BASH_BIN="$(command -v bash)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "voice-context.sh exists" \
  "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"
check "bash interpreter resolved" \
  "$([ -n "$BASH_BIN" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# Expected bytes: reconstruct the canonical text from this suite's own copy
# of the raw marker block, per the contract's reconstruction rule.
# ---------------------------------------------------------------------------

RAW_BLOCK="$(cat <<'RAW_BLOCK_EOF'
# # Voice (voice plugin)
#
# These rules supersede any built-in per-model tone or communication guidance, including guidance that prefers fuller, more readable prose over concision. Engineer every reply for a reader with limited working memory: what comes first and how points are delineated matter as much as the words.
#
# - Lead with the conclusion. State the recommendation or main claim first (bold it in a long reply), then the reasoning. Caveats, conditions, and open questions come before or beside the commitment, never after it; once committed, never soften, widen, or re-open it.
# - Open each section of a longer reply with one sentence stating the point it argues, so the reader can object before reading on.
# - Rule out losing options first, each with its reason in one line, before analyzing the contenders.
# - Ask the questions that gate your answer up front, numbered with bracketed assumed defaults ("[assuming: batch]"), then analyze under those assumptions. Never trail the analysis with "what would change my mind".
# - Render distinct points, steps, costs, or trade-offs as bullets with a short bold label each ("**Ordering risk:** ..."), one or two short lines per item; keep prose paragraphs for connected reasoning, never for enumerations.
# - Collect everything you need from the user in one numbered place; never strew asks or action items through the reply.
# - When you mention an option again, re-anchor it in a few words ("option 2, the Fargate proxy"); never a bare label.
# - Plain established words only: no metaphorical jargon ("the cost axis", "a sentinel object", "load-bearing"), no "honestly" or framing of your own candor, no epigrams or dramatic "not X, but Y" reveals. Support claims with concrete numbers and names, grouped together rather than scattered.
# - Size the reply from substance: cut ceremony and re-narration, never findings; a simple ack is one line.
# - If it is in a file the user will read, summarize in a line and point to the file; do not restate it in chat.
# - Report failures mechanism-first: cause, fix, next step, in a few sentences.
# - Narrate actions in plain first person ("I'll check X."), never subject-less gerund fragments ("Checking X now.").
RAW_BLOCK_EOF
)"

EXPECTED="$(awk '{ if ($0 == "#") print ""; else print substr($0,3) }' <<<"$RAW_BLOCK")"
printf '%s\n' "$EXPECTED" > "$TMP/expected.txt"

check "reconstructed canonical text is 16 lines" \
  "$(wc -l < "$TMP/expected.txt" | tr -d ' ')" "16"

# ---------------------------------------------------------------------------
# Baseline run
# ---------------------------------------------------------------------------

BASE_OUT="$TMP/base.out"
BASE_ERR="$TMP/base.err"
"$BASH_BIN" "$SCRIPT" </dev/null >"$BASE_OUT" 2>"$BASE_ERR"
BASE_EC=$?

# ---------------------------------------------------------------------------
# 1. Outputs: byte-identical stdout vs canonical text (Behavior, Outputs)
# ---------------------------------------------------------------------------

check "expected byte count matches actual stdout byte count" \
  "$(wc -c < "$TMP/expected.txt" | tr -d ' ')" \
  "$(wc -c < "$BASE_OUT" | tr -d ' ')"

check "stdout is byte-identical to the canonical text (cmp)" \
  "$(cmp -s "$TMP/expected.txt" "$BASE_OUT" && echo identical || echo different)" \
  "identical"

# ---------------------------------------------------------------------------
# 2. Exit (always 0) and Outputs (stderr: nothing, ever)
# ---------------------------------------------------------------------------

check "exit code is always 0 (SessionStart hook must never block)" "$BASE_EC" "0"
check "stderr is empty" "$(wc -c < "$BASE_ERR" | tr -d ' ')" "0"

# ---------------------------------------------------------------------------
# 3. Determinism: two runs are byte-identical (Outputs)
# ---------------------------------------------------------------------------

RUN2_OUT="$TMP/run2.out"
"$BASH_BIN" "$SCRIPT" </dev/null >"$RUN2_OUT" 2>/dev/null
check "two runs are byte-identical (determinism)" \
  "$(cmp -s "$BASE_OUT" "$RUN2_OUT" && echo identical || echo different)" "identical"

# ---------------------------------------------------------------------------
# 4. Inputs: stdin never read (Inputs, Edge cases)
# ---------------------------------------------------------------------------

CLOSED_OUT="$TMP/closed.out"
CLOSED_ERR="$TMP/closed.err"
"$BASH_BIN" "$SCRIPT" 0<&- >"$CLOSED_OUT" 2>"$CLOSED_ERR"
CLOSED_EC=$?
check "closed stdin (0<&-): exit code still 0" "$CLOSED_EC" "0"
check "closed stdin (0<&-): stdout unchanged from baseline" \
  "$(cmp -s "$BASE_OUT" "$CLOSED_OUT" && echo identical || echo different)" "identical"
check "closed stdin (0<&-): stderr still empty" \
  "$(wc -c < "$CLOSED_ERR" | tr -d ' ')" "0"

HUGE_FILE="$TMP/huge.in"
head -c 5000000 /dev/zero > "$HUGE_FILE" 2>/dev/null
HUGE_OUT="$TMP/huge.out"
timeout 5 "$BASH_BIN" "$SCRIPT" < "$HUGE_FILE" >"$HUGE_OUT" 2>/dev/null
HUGE_EC=$?
check "oversized stdin (5MB): does not hang (completes within timeout)" \
  "$([ "$HUGE_EC" != "124" ] && echo yes || echo no)" "yes"
check "oversized stdin (5MB): stdout unchanged from baseline" \
  "$(cmp -s "$BASE_OUT" "$HUGE_OUT" && echo identical || echo different)" "identical"

# ---------------------------------------------------------------------------
# 5. Inputs: arguments ignored (Inputs, Edge cases)
# ---------------------------------------------------------------------------

ARGS_OUT="$TMP/args.out"
ARGS_ERR="$TMP/args.err"
"$BASH_BIN" "$SCRIPT" --foo "bar baz" positional </dev/null >"$ARGS_OUT" 2>"$ARGS_ERR"
ARGS_EC=$?
check "unexpected arguments: exit code still 0" "$ARGS_EC" "0"
check "unexpected arguments: stdout unchanged from baseline" \
  "$(cmp -s "$BASE_OUT" "$ARGS_OUT" && echo identical || echo different)" "identical"
check "unexpected arguments: stderr still empty" \
  "$(wc -c < "$ARGS_ERR" | tr -d ' ')" "0"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
