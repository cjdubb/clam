#!/bin/bash
# Contract tests for block-question.sh (B01 question-gate).
#
# Source of truth: the "Contract: B01 question-gate" docblock atop
# block-question.sh. Black-box only: every test runs the script as a real
# subprocess through its public interface (stdin -> stdout/stderr/exit code)
# and asserts on the observable result. Never greps the script's source —
# behavior only, per the contract's own "no internals" rule.
#
# Sections below mirror the docblock's own clause groups (Behavior, Inputs,
# Outputs, Errors, Exit, Invariants, Edge cases). A shared `capture()` helper
# (mktemp-backed, mirroring realm-gate.test.sh's run_gate() and
# push-notify.test.sh's run_notify()) runs an arbitrary shell command line
# through `bash -c` so each test can freely vary stdin source, argv, env
# vars, cwd, and a timeout wrapper without touching the interpreter used to
# invoke the script itself.
#
# The script under test is invoked via an absolute path to the bash
# interpreter (`$BASH_BIN`, resolved once via `command -v bash`) rather than
# the bare word "bash", so that tests exercising an emptied PATH (Errors:
# "no external commands" proxy) still manage to launch the subprocess — an
# empty PATH only starves the SCRIPT's own environment, never this harness's
# ability to invoke it.
#
# Orchestrator's binding clarifications followed here:
#   - "stderr: exactly one line" -> asserted as exactly one newline in the
#     captured stderr file, plus non-empty content.
#   - "stdin never read" -> behavioral proxies only (closed stdin via
#     `0<&-`, empty stdin via `</dev/null`, oversized stdin via a 5MB file);
#     no fifo/hang-detection tests.
#   - Determinism -> two consecutive runs, captured back-to-back, compared
#     for byte-identical stderr and equal exit code.
#
# Hermetic: reads only this repo's own committed block-question.sh, writes
# only to mktemp paths (all cleaned up), no network.
#
# Run: bash plugins/ask-in-text/scripts/block-question.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/block-question.sh"
BASH_BIN="$(command -v bash)"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# capture <shell-command-line> -- runs the command line via `bash -c`,
# populating RUN_OUT / RUN_ERR / RUN_EXIT / RUN_ERR_LINES. Callers build the
# command line themselves (stdin redirection, env prefixes, cd, timeout
# wrapper, extra argv) since bash -c accepts an arbitrary shell snippet.
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
RUN_ERR_LINES=0
capture() {
  local cmd="$1"
  local outfile errfile
  outfile="$(mktemp)"
  errfile="$(mktemp)"
  bash -c "$cmd" >"$outfile" 2>"$errfile"
  RUN_EXIT=$?
  RUN_OUT="$(cat "$outfile")"
  RUN_ERR="$(cat "$errfile")"
  RUN_ERR_LINES="$(wc -l < "$errfile" | tr -d ' ')"
  rm -f "$outfile" "$errfile"
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "block-question.sh exists" \
  "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"
check "bash interpreter resolved" \
  "$([ -n "$BASH_BIN" ] && echo yes || echo no)" "yes"
check "timeout command available (used by completes-instantly tests)" \
  "$(command -v timeout >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# Baseline run: default invocation, empty stdin. Reused as the reference
# point for every stdin-invariance / argv-invariance / env-invariance test
# below (Inputs, Invariants, Edge cases all compare against this).
# ---------------------------------------------------------------------------

capture "'$BASH_BIN' '$SCRIPT' </dev/null"
BASELINE_OUT="$RUN_OUT"
BASELINE_ERR="$RUN_ERR"
BASELINE_EXIT="$RUN_EXIT"
BASELINE_ERR_LINES="$RUN_ERR_LINES"

# ---------------------------------------------------------------------------
# 1. Exit (X-1: always 2) and core Behavior (B-3: unconditional deny)
# ---------------------------------------------------------------------------

check "exit code is always 2" "$BASELINE_EXIT" "2"
check "stdout is empty (Outputs O-7: stdout nothing, ever)" "$BASELINE_OUT" ""

# ---------------------------------------------------------------------------
# 2. Outputs (O-1..O-7): stderr shape and required content
# ---------------------------------------------------------------------------

check "stderr has exactly one line" "$BASELINE_ERR_LINES" "1"
check "stderr line is non-empty" \
  "$([ -n "$BASELINE_ERR" ] && echo yes || echo no)" "yes"
check "stderr names the blocked tool AskUserQuestion" \
  "$(grep -qF 'AskUserQuestion' <<<"$BASELINE_ERR" && echo yes || echo no)" "yes"
check "stderr names the ask-in-text plugin as the source of the block" \
  "$(grep -qF 'ask-in-text' <<<"$BASELINE_ERR" && echo yes || echo no)" "yes"
check "stderr contains the literal word 'numbered'" \
  "$(grep -qiw 'numbered' <<<"$BASELINE_ERR" && echo yes || echo no)" "yes"
check "stderr contains the literal phrase 'plain text'" \
  "$(grep -qiF 'plain text' <<<"$BASELINE_ERR" && echo yes || echo no)" "yes"
check "stderr mentions a recommended default per question" \
  "$(grep -qiw 'default' <<<"$BASELINE_ERR" && echo yes || echo no)" "yes"
check "stderr states bare go/confirmed acceptance semantics" \
  "$(grep -qiE '\bgo\b|\bconfirmed\b' <<<"$BASELINE_ERR" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 3. Inputs (I-1: stdin never read; I-2: no arguments; I-3: no env vars)
# ---------------------------------------------------------------------------

# I-1: closed stdin -- behaves identically to baseline.
capture "'$BASH_BIN' '$SCRIPT' 0<&-"
check "closed stdin (0<&-): same exit code as baseline" "$RUN_EXIT" "$BASELINE_EXIT"
check "closed stdin (0<&-): same stderr as baseline" "$RUN_ERR" "$BASELINE_ERR"
check "closed stdin (0<&-): same stdout as baseline" "$RUN_OUT" "$BASELINE_OUT"
CLOSED_ERR="$RUN_ERR"

# I-1: empty stdin -- a second, independently-captured run, compared against
# the closed-stdin run above (not just re-using the baseline capture) so
# this clause has its own dedicated evidence.
capture "'$BASH_BIN' '$SCRIPT' </dev/null"
check "empty stdin (</dev/null): exit code 2" "$RUN_EXIT" "2"
check "empty stdin (</dev/null): matches closed-stdin stderr (stdin-invariant)" \
  "$RUN_ERR" "$CLOSED_ERR"

# I-1 / Invariant V-3 / Edge case G-1: oversized stdin (5MB) -- must not
# hang and must behave identically to baseline. `timeout` guards against a
# hang rather than waiting on it.
HUGE_FILE="$(mktemp)"
head -c 5000000 /dev/zero > "$HUGE_FILE" 2>/dev/null
capture "timeout 5 '$BASH_BIN' '$SCRIPT' < '$HUGE_FILE'"
check "oversized stdin (5MB): does not hang (completes within timeout)" \
  "$([ "$RUN_EXIT" != "124" ] && echo yes || echo no)" "yes"
check "oversized stdin (5MB): same stderr as baseline (stdin content ignored)" \
  "$RUN_ERR" "$BASELINE_ERR"
rm -f "$HUGE_FILE"

# I-2: extraneous arguments are ignored (no argv parsing).
capture "'$BASH_BIN' '$SCRIPT' extra --flag=value ignored-arg </dev/null"
check "extraneous args: same stderr as baseline (no argv parsing)" "$RUN_ERR" "$BASELINE_ERR"
check "extraneous args: same exit code as baseline" "$RUN_EXIT" "$BASELINE_EXIT"

# I-3 / Invariant V-1: no environment variables consulted, no config surface,
# no escape hatch -- plausible gate-style env vars (mirroring
# block-task-tools.sh's CLAM_* gate, which this script deliberately diverges
# from) have zero effect.
capture "CLAM_ASK_IN_TEXT_GATE=disabled CLAM_ASK_IN_TEXT_QUESTION_GATE=disabled DISABLE_ASK_IN_TEXT=1 '$BASH_BIN' '$SCRIPT' </dev/null"
check "plausible gate env vars set: still denies (no escape hatch, no config surface)" \
  "$RUN_EXIT" "2"
check "plausible gate env vars set: stderr unchanged from baseline" "$RUN_ERR" "$BASELINE_ERR"

# ---------------------------------------------------------------------------
# 4. Errors (E-1: none -- cannot fail for environmental reasons)
# ---------------------------------------------------------------------------

# Empty PATH: if the script depended on any external command it would fail
# to resolve it here. Same behavior proves independence from external
# commands / file access (it uses only the echo and exit builtins).
capture "PATH= '$BASH_BIN' '$SCRIPT' </dev/null"
check "empty PATH: still denies (no external-command dependency)" "$RUN_EXIT" "2"
check "empty PATH: stderr unchanged from baseline" "$RUN_ERR" "$BASELINE_ERR"

# ---------------------------------------------------------------------------
# 5. Invariants (V-1 covered above; V-2: no side effects; V-3 covered above;
#    V-4: completes instantly; plus determinism)
# ---------------------------------------------------------------------------

# V-2: no side effects -- an empty scratch cwd stays empty.
SCRATCH_DIR="$(mktemp -d)"
BEFORE_LISTING="$(ls -A "$SCRATCH_DIR" 2>/dev/null)"
capture "cd '$SCRATCH_DIR' && '$BASH_BIN' '$SCRIPT' </dev/null"
AFTER_LISTING="$(ls -A "$SCRATCH_DIR" 2>/dev/null)"
check "no files/directories created as a side effect (empty cwd stays empty)" \
  "$AFTER_LISTING" "$BEFORE_LISTING"
rm -rf "$SCRATCH_DIR"

# V-4: completes well under the 10s hooks.json timeout.
capture "timeout 5 '$BASH_BIN' '$SCRIPT' </dev/null"
check "completes within 5s (comfortably under the 10s hook timeout)" \
  "$([ "$RUN_EXIT" != "124" ] && echo yes || echo no)" "yes"

# Determinism (binding clarification): two consecutive runs, captured
# back-to-back, produce byte-identical stderr and the same exit code.
capture "'$BASH_BIN' '$SCRIPT' </dev/null"
DET_RUN1_ERR="$RUN_ERR"
DET_RUN1_EXIT="$RUN_EXIT"
capture "'$BASH_BIN' '$SCRIPT' </dev/null"
DET_RUN2_ERR="$RUN_ERR"
DET_RUN2_EXIT="$RUN_EXIT"
check "determinism: two consecutive runs produce identical stderr" "$DET_RUN2_ERR" "$DET_RUN1_ERR"
check "determinism: two consecutive runs produce the same exit code" "$DET_RUN2_EXIT" "$DET_RUN1_EXIT"

# ---------------------------------------------------------------------------
# 6. Edge cases (G-1 covered above via stdin variants; G-2: invoked outside a
#    hook context; G-3: subagent tool calls denied identically)
# ---------------------------------------------------------------------------

# G-2: manual invocation from an unrelated cwd behaves identically to a
# hook-context invocation.
capture "cd /tmp && '$BASH_BIN' '$SCRIPT' </dev/null"
check "manual invocation from an unrelated cwd (/tmp): same stderr as baseline" \
  "$RUN_ERR" "$BASELINE_ERR"
check "manual invocation from an unrelated cwd (/tmp): same exit code as baseline" \
  "$RUN_EXIT" "$BASELINE_EXIT"

# G-3: PreToolUse fires identically for subagent tool calls. The script
# never parses stdin at all, so a representative subagent-shaped PreToolUse
# payload (as the framework would send for a subagent's AskUserQuestion
# call) is the best available proxy: identical output proves the deny does
# not vary by caller context.
SUBAGENT_JSON_FILE="$(mktemp)"
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","agent_type":"some-subagent","tool_input":{"questions":[{"question":"Pick one"}]}}' > "$SUBAGENT_JSON_FILE"
capture "'$BASH_BIN' '$SCRIPT' < '$SUBAGENT_JSON_FILE'"
check "subagent-shaped PreToolUse payload on stdin: same stderr as baseline" \
  "$RUN_ERR" "$BASELINE_ERR"
check "subagent-shaped PreToolUse payload on stdin: exit code 2" "$RUN_EXIT" "2"
rm -f "$SUBAGENT_JSON_FILE"

# ---------------------------------------------------------------------------
if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
