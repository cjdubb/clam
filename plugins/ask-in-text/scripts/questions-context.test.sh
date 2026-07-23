#!/bin/bash
# Test for Block B02 (questions-context). Authoritative contract: the
# HTML-comment docblock "Contract: B02 questions-context" atop
# plugins/ask-in-text/scripts/questions-context.sh.
#
# The script is a SessionStart hook: a pure heredoc-to-stdout emitter (no
# args, no env, no stdin/file reads, no external commands) that must always
# exit 0 and print a compact, deterministic markdown block restating the
# standing question-asking convention. Every check below exercises the
# script strictly through its public interface — invoked as a subprocess,
# asserting on exit code, stdout, and stderr — never by inspecting its
# source (the one file read, in section 6, is copied and executed, never
# grepped). Clauses that describe an absence (no stdin read, no env
# consulted, no file reads, no config surface) are verified via behavioral
# proxies: run the script under varied stdin/args/env/cwd and assert the
# output is unaffected, per the orchestrator's clarifications.
#
# Run: bash plugins/ask-in-text/scripts/questions-context.test.sh
# (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/questions-context.sh"
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

# A line present in file $1 containing both "bare" and case-insensitive
# "go" — the clarified proxy for the bare-"go"-acceptance-semantics marker.
has_bare_go_marker() {
  grep -i 'bare' "$1" 2>/dev/null | grep -qi 'go'
}

bytesize() { wc -c < "$1" | tr -d ' '; }

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "questions-context.sh exists" \
  "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 1. Baseline invocation: exit code, stderr, and every required stdout
#    marker (Behavior clauses 1-6, Outputs, Exit)
# ---------------------------------------------------------------------------

BASE_OUT="$TMP/base.out"
BASE_ERR="$TMP/base.err"
"$BASH_BIN" "$SCRIPT" </dev/null >"$BASE_OUT" 2>"$BASE_ERR"
BASE_EC=$?

check "exit code is always 0 (SessionStart hook must never block)" "$BASE_EC" "0"
check "stderr is empty" "$(bytesize "$BASE_ERR")" "0"
check "stdout is non-empty" "$([ -s "$BASE_OUT" ] && echo yes || echo no)" "yes"

check "stdout contains at least one markdown heading line (^#)" \
  "$(grep -qE '^#' "$BASE_OUT" && echo yes || echo no)" "yes"

check "stdout names the literal tool 'AskUserQuestion' (clause 1: never call it)" \
  "$(grep -qF 'AskUserQuestion' "$BASE_OUT" && echo yes || echo no)" "yes"

check "stdout uses the word 'numbered' (clause 3: number the questions)" \
  "$(grep -qi 'numbered' "$BASE_OUT" && echo yes || echo no)" "yes"

check "stdout states bare-\"go\" acceptance semantics (clause 5; edge case: consistent with tracking's decision-format convention)" \
  "$(has_bare_go_marker "$BASE_OUT" && echo yes || echo no)" "yes"

check "stdout mentions a recommended default (clause 4; edge case: consistent with tracking's decision-format convention)" \
  "$(grep -qi 'default' "$BASE_OUT" && echo yes || echo no)" "yes"

check "stdout stays compact (Invariant: <= 4000 bytes)" \
  "$([ "$(bytesize "$BASE_OUT")" -le 4000 ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 2. Determinism (Outputs: byte-identical on every run)
# ---------------------------------------------------------------------------

RUN2_OUT="$TMP/run2.out"
"$BASH_BIN" "$SCRIPT" </dev/null >"$RUN2_OUT" 2>/dev/null
RUN2_EC=$?

check "second run has the same exit code as the first" "$RUN2_EC" "$BASE_EC"
check "second run's stdout is byte-identical to the first" \
  "$(cmp -s "$BASE_OUT" "$RUN2_OUT" && echo identical || echo different)" "identical"

# ---------------------------------------------------------------------------
# 3. Inputs: stdin deliberately never read (behavioral proxies: closed vs.
#    empty vs. hook-shaped stdin)
# ---------------------------------------------------------------------------

CLOSED_OUT="$TMP/closed.out"
"$BASH_BIN" "$SCRIPT" 0<&- >"$CLOSED_OUT" 2>/dev/null
CLOSED_EC=$?

check "closed-stdin run exits 0" "$CLOSED_EC" "0"
check "closed-stdin run's stdout matches the empty-stdin baseline (stdin never read)" \
  "$(cmp -s "$BASE_OUT" "$CLOSED_OUT" && echo identical || echo different)" "identical"

HOOKJSON_OUT="$TMP/hookjson.out"
echo '{"session_id":"abc","hook_event_name":"SessionStart"}' | "$BASH_BIN" "$SCRIPT" >"$HOOKJSON_OUT" 2>/dev/null
HOOKJSON_EC=$?

check "hook-JSON-on-stdin run exits 0" "$HOOKJSON_EC" "0"
check "hook-JSON-on-stdin run's stdout matches the empty-stdin baseline (stdin never read; edge case: hook invocation)" \
  "$(cmp -s "$BASE_OUT" "$HOOKJSON_OUT" && echo identical || echo different)" "identical"

# ---------------------------------------------------------------------------
# 4. Inputs: no arguments consulted
# ---------------------------------------------------------------------------

ARGS_OUT="$TMP/args.out"
"$BASH_BIN" "$SCRIPT" --some-flag unexpected positional args </dev/null >"$ARGS_OUT" 2>/dev/null
ARGS_EC=$?

check "run with unexpected arguments exits 0" "$ARGS_EC" "0"
check "run with unexpected arguments matches the no-argument baseline (no arguments consulted)" \
  "$(cmp -s "$BASE_OUT" "$ARGS_OUT" && echo identical || echo different)" "identical"

# ---------------------------------------------------------------------------
# 5. Inputs: no environment variables consulted; Invariant: no config
#    surface / no env escape hatch (unconditional while installed, per
#    engineer decision 2026-07-23)
# ---------------------------------------------------------------------------

ENVI_OUT="$TMP/envi.out"
env -i "$BASH_BIN" "$SCRIPT" </dev/null >"$ENVI_OUT" 2>/dev/null
ENVI_EC=$?

check "run under a stripped environment (env -i) exits 0 (cannot fail for environmental reasons)" "$ENVI_EC" "0"
check "run under a stripped environment matches the baseline (no env vars consulted)" \
  "$(cmp -s "$BASE_OUT" "$ENVI_OUT" && echo identical || echo different)" "identical"

ESCAPE_OUT="$TMP/escape.out"
QUESTIONS_CONTEXT_DISABLE=1 CLAM_ASK_IN_TEXT_DISABLE=1 NO_QUESTIONS_CONTEXT=1 \
  "$BASH_BIN" "$SCRIPT" </dev/null >"$ESCAPE_OUT" 2>/dev/null
ESCAPE_EC=$?

check "run with plausible escape-hatch env vars set still exits 0" "$ESCAPE_EC" "0"
check "run with plausible escape-hatch env vars set matches the baseline (no env escape hatch, unconditional while installed)" \
  "$(cmp -s "$BASE_OUT" "$ESCAPE_OUT" && echo identical || echo different)" "identical"

# ---------------------------------------------------------------------------
# 6. Invariants: no side effects, nothing read from disk. Errors: none,
#    cannot fail for environmental reasons. Proxy: relocate a standalone
#    copy of the script into an isolated tmp dir (no sibling repo files at
#    all) and run it from an unrelated cwd.
# ---------------------------------------------------------------------------

ISOLATED_DIR="$TMP/isolated"
mkdir -p "$ISOLATED_DIR"
cp "$SCRIPT" "$ISOLATED_DIR/questions-context.sh"
ISO_OUT="$TMP/iso.out"
( cd "$ISOLATED_DIR" && "$BASH_BIN" ./questions-context.sh </dev/null >"$ISO_OUT" 2>/dev/null )
ISO_EC=$?

check "run in isolation (no sibling repo files, unrelated cwd) exits 0" "$ISO_EC" "0"
check "run in isolation matches the baseline (no side effects; nothing read from disk)" \
  "$(cmp -s "$BASE_OUT" "$ISO_OUT" && echo identical || echo different)" "identical"

# ---------------------------------------------------------------------------
# 7. Edge case: invoked outside a hook context (manually, or by a test) —
#    every invocation above already is exactly this; assert it explicitly.
# ---------------------------------------------------------------------------

check "manual (non-hook) invocation exits 0 with the standard markers intact" \
  "$([ "$BASE_EC" == "0" ] && grep -qF 'AskUserQuestion' "$BASE_OUT" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
