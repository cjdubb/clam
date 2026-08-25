#!/bin/bash
# Contract tests for sleep-gate.sh (B01 sleep-gate hook script).
#
# Source of truth: the "Contract: B01 sleep-gate hook script" docblock atop
# sleep-gate.sh. Black-box only: every test runs the script as a real
# subprocess through its public interface (hook JSON on stdin -> stdout,
# stderr, exit code) and asserts on the observable result. The suite never
# greps the script's source and never assumes HOW the command string is
# parsed — only what the decision is for a given input.
#
# Sections mirror the docblock's clause groups (Behavior/Rule L, Behavior/
# Rule B, Outputs, Inputs, Errors, Invariants, Edge cases).
#
# Hermetic: reads only this repo's own sleep-gate.sh, writes only inside one
# mktemp -d scratch directory (removed on exit), no network, cwd-independent
# (paths resolve from ${BASH_SOURCE[0]}).
#
# Run: bash plugins/sleep-gate/scripts/sleep-gate.test.sh  (non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/sleep-gate.sh"
BASH_BIN="$(command -v bash)"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

yn() { # exit-status-of-preceding-test-expression as yes/no
  if [[ "$1" == "0" ]]; then echo yes; else echo no; fi
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "sleep-gate.sh exists" \
  "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"
check "bash interpreter resolved" \
  "$([ -n "$BASH_BIN" ] && echo yes || echo no)" "yes"
check "jq available to the harness (deny JSON is parsed, never grepped)" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

TIMEOUT_CMD=""
for _t in timeout gtimeout; do
  command -v "$_t" >/dev/null 2>&1 && TIMEOUT_CMD="$_t" && break
done

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

# capture <shell-command-line> -- runs the line via `bash -c`, populating
# RUN_OUT / RUN_ERR / RUN_EXIT / RUN_OUT_LINES. Callers build the line so
# they can vary stdin source, env prefix, cwd, and interpreter freely.
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0
RUN_OUT_LINES=0
capture() {
  local cmd="$1"
  local outfile errfile
  outfile="$SCRATCH/out.$$"
  errfile="$SCRATCH/err.$$"
  bash -c "$cmd" >"$outfile" 2>"$errfile"
  RUN_EXIT=$?
  RUN_OUT="$(cat "$outfile")"
  RUN_ERR="$(cat "$errfile")"
  # Count lines of the captured stdout with a trailing newline normalised in,
  # so an implementation using printf (no trailing newline) and one using
  # echo (trailing newline) both read as "one line".
  if [[ -z "$RUN_OUT" ]]; then
    RUN_OUT_LINES=0
  else
    RUN_OUT_LINES="$(wc -l <<<"$RUN_OUT" | tr -d ' ')"
  fi
  rm -f "$outfile" "$errfile"
}

# payload_for <command> -- writes a realistic PreToolUse hook payload for the
# Bash tool into the scratch dir and echoes its path. jq --arg does the JSON
# escaping, so command strings containing quotes, backslashes and newlines
# survive verbatim.
payload_for() {
  local f="$SCRATCH/payload.json"
  jq -n --arg cmd "$1" \
    '{session_id:"test",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}' \
    >"$f"
  printf '%s' "$f"
}

# run_cmd <command> [env-prefix] [interpreter]
run_cmd() {
  local pf interp
  pf="$(payload_for "$1")"
  interp="${3:-$BASH_BIN}"
  capture "${2:-} '$interp' '$SCRIPT' < '$pf'"
}

# run_raw <raw-stdin-string> -- bypasses payload_for for malformed input.
run_raw() {
  local f="$SCRATCH/raw.txt"
  printf '%s' "$1" >"$f"
  capture "'$BASH_BIN' '$SCRIPT' < '$f'"
}

json_field() { # json path
  jq -r "$2 // \"\"" <<<"$1" 2>/dev/null
}

reason_of() { # json -> lowercased permissionDecisionReason
  json_field "$1" '.hookSpecificOutput.permissionDecisionReason' \
    | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'
}

any_in() { # content pattern...
  local content="$1"; shift
  local p
  for p in "$@"; do
    if grep -qF -- "$p" <<<"$content"; then echo yes; return; fi
  done
  echo no
}

# lists_alternatives <lowercased-reason> -- yes only when the reason carries
# all four alternatives the Outputs clause requires. Substance, not prose:
# each alternative is matched by any of several reasonable phrasings.
lists_alternatives() {
  local r="$1"
  [[ "$(any_in "$r" "timeout")" == "yes" ]] || { echo no; return; }
  [[ "$(any_in "$r" "run_in_background" "run in background")" == "yes" ]] || { echo no; return; }
  [[ "$(any_in "$r" "wait")" == "yes" ]] || { echo no; return; }
  [[ "$(any_in "$r" "poll" "kill -0" "marker" "real condition")" == "yes" ]] || { echo no; return; }
  echo yes
}

# assert_deny <command> <rule-token...> -- the full deny contract for one
# command. The variadic tail is the set of acceptable phrasings for "names
# WHICH rule matched"; wording is the implementer's, substance is not.
DENY_RULE_L=("rule l" "leading" "first statement" "bare sleep")
DENY_RULE_B=("rule b" "background")
assert_deny() { # command rule-label pattern...
  local cmd="$1" label="$2"; shift 2
  run_cmd "$cmd"
  check "deny [$label] '$cmd': exit 0" "$RUN_EXIT" "0"
  check "deny [$label] '$cmd': stderr empty" "$RUN_ERR" ""
  check "deny [$label] '$cmd': stdout is a single line" "$RUN_OUT_LINES" "1"
  check "deny [$label] '$cmd': stdout is well-formed JSON" \
    "$(jq -e . >/dev/null 2>&1 <<<"$RUN_OUT"; yn "$?")" "yes"
  check "deny [$label] '$cmd': hookSpecificOutput.hookEventName is PreToolUse" \
    "$(json_field "$RUN_OUT" '.hookSpecificOutput.hookEventName')" "PreToolUse"
  check "deny [$label] '$cmd': hookSpecificOutput.permissionDecision is deny" \
    "$(json_field "$RUN_OUT" '.hookSpecificOutput.permissionDecision')" "deny"
  check "deny [$label] '$cmd': permissionDecisionReason is non-empty" \
    "$([ -n "$(json_field "$RUN_OUT" '.hookSpecificOutput.permissionDecisionReason')" ] && echo yes || echo no)" "yes"
  local reason; reason="$(reason_of "$RUN_OUT")"
  check "deny [$label] '$cmd': reason names the matched rule" \
    "$(any_in "$reason" "$@")" "yes"
  check "deny [$label] '$cmd': reason states a fixed sleep is not a completion signal" \
    "$(any_in "$reason" "completion signal" "not a completion" "does not signal" "is not a signal")" "yes"
  check "deny [$label] '$cmd': reason lists all four alternatives" \
    "$(lists_alternatives "$reason")" "yes"
}

assert_allow() { # command label
  run_cmd "$1"
  check "allow [$2] '$1': exit 0" "$RUN_EXIT" "0"
  check "allow [$2] '$1': no output at all" "$RUN_OUT" ""
  check "allow [$2] '$1': stderr empty" "$RUN_ERR" ""
}

# ---------------------------------------------------------------------------
# 1. Behavior / Rule L -- a leading bare sleep of 2 seconds or longer
# ---------------------------------------------------------------------------

assert_deny "sleep 45" "L" "${DENY_RULE_L[@]}"
assert_deny "sleep 2m" "L" "${DENY_RULE_L[@]}"
assert_deny "sleep 30 && cat /tmp/build.log" "L" "${DENY_RULE_L[@]}"

# The 2-second floor, both sides. `sleep 2` is the first denied value.
assert_deny "sleep 2" "L-floor" "${DENY_RULE_L[@]}"
assert_allow "sleep 1" "L-floor"
assert_allow "sleep 0.25" "L-floor"
assert_allow "sleep 1.5" "L-floor"

# Suffix conversions: s=1, m=60, h=3600, d=86400.
assert_deny "sleep 2s" "L-suffix-s" "${DENY_RULE_L[@]}"
assert_allow "sleep 1s" "L-suffix-s"
assert_deny "sleep 1m" "L-suffix-m" "${DENY_RULE_L[@]}"
assert_deny "sleep 1h" "L-suffix-h" "${DENY_RULE_L[@]}"
assert_deny "sleep 1d" "L-suffix-d" "${DENY_RULE_L[@]}"
assert_deny "sleep 120s" "L-suffix-s" "${DENY_RULE_L[@]}"

# First-statement delimiters: `;`, `&&`, `||`, `|`, newline. In each of these
# the leading `sleep 30` IS the first statement.
assert_deny "sleep 30; echo done" "L-delim-semicolon" "${DENY_RULE_L[@]}"
assert_deny "sleep 30 || true" "L-delim-oror" "${DENY_RULE_L[@]}"
assert_deny "sleep 30 | cat" "L-delim-pipe" "${DENY_RULE_L[@]}"
assert_deny "$(printf 'sleep 30\necho done')" "L-delim-newline" "${DENY_RULE_L[@]}"
# ...and trimmed, so surrounding whitespace does not save it.
assert_deny "   sleep 30   " "L-trimmed" "${DENY_RULE_L[@]}"

# A sleep that is NOT the first statement is not Rule L (and, with no
# background `&`, not Rule B either).
assert_allow "echo hi && sleep 30" "L-not-first"
assert_allow "cd /tmp; sleep 30" "L-not-first"
assert_allow "make | tee log; sleep 300" "L-not-first"
assert_allow "$(printf 'echo start\nsleep 30')" "L-not-first"

# Operand shape: exactly one operand, and it must be a number.
assert_allow "sleep 5 10" "L-multi-operand"
assert_allow "sleep abc" "L-non-numeric"
assert_allow "sleep" "L-no-operand"

# Not a bare sleep at all.
assert_allow "sleeper 30" "L-not-sleep"
assert_allow "echo sleep 30" "L-not-sleep"

# ---------------------------------------------------------------------------
# 2. Behavior / Rule B -- background launch followed by a sleep
# ---------------------------------------------------------------------------

assert_deny "./build.sh & sleep 30" "B" "${DENY_RULE_B[@]}"
assert_deny "npm run dev & sleep 5; curl -sf localhost:3000" "B" "${DENY_RULE_B[@]}"
assert_deny "$(printf './server.py &\nsleep 10\ncurl -sf localhost:8000')" "B-newline" "${DENY_RULE_B[@]}"
# Rule B carries no duration floor of its own: any sleep after the first
# background `&` matches, including a sub-2s one.
assert_deny "./build.sh & sleep 1" "B-no-floor" "${DENY_RULE_B[@]}"

# Clause 2: a sleep appearing BEFORE the first background `&` does not match.
assert_allow "echo start; sleep 30; ./run.sh &" "B-sleep-before-amp"

# Clause 3, the carve-out: each of the six words individually rescues a
# command Rule B would otherwise deny. The base command is the denied
# `./build.sh & sleep 30` above; only the added word differs.
for kw in while until for break wait trap; do
  assert_allow "./build.sh & sleep 30 # $kw" "B-carveout-$kw"
done

# ...and the same carve-out in realistic shapes.
assert_allow "./srv & until curl -sf http://localhost:3000/health; do sleep 0.25; done" "B-carveout-until"
assert_allow "./srv & while ! nc -z localhost 3000; do sleep 1; done" "B-carveout-while"
assert_allow "./srv & pid=\$!; sleep 5; wait \"\$pid\"" "B-carveout-wait"
assert_allow "trap 'kill \$pid' EXIT; ./srv & pid=\$!; sleep 5" "B-carveout-trap"
assert_allow "for i in 1 2 3; do ./srv & sleep 1; done" "B-carveout-for"

# Clause 1: every non-background `&` form. None of these is a background
# launch, so a following sleep is not Rule B.
assert_allow "echo a && sleep 30" "B-amp-andand"
assert_allow "make 2>&1 | tee build.log; sleep 30" "B-amp-2>&1"
assert_allow "make &> build.log; sleep 30" "B-amp-&>"
assert_allow "make >& build.log; sleep 30" "B-amp->&"
assert_allow "cat <&3; sleep 30" "B-amp-<&"
assert_allow 'echo a\& ; sleep 30' "B-amp-escaped"

# ---------------------------------------------------------------------------
# 3. Outputs -- deny object shape and reason content, in detail
# ---------------------------------------------------------------------------

# One representative deny per rule gets the full, itemised Outputs treatment.
for rep in "sleep 45" "./build.sh & sleep 30"; do
  run_cmd "$rep"
  REP_REASON="$(reason_of "$RUN_OUT")"
  check "outputs '$rep': the only top-level key is hookSpecificOutput" \
    "$(jq -r 'keys | join(",")' <<<"$RUN_OUT" 2>/dev/null)" "hookSpecificOutput"
  check "outputs '$rep': hookSpecificOutput keys are exactly the three named" \
    "$(jq -r '.hookSpecificOutput | keys | sort | join(",")' <<<"$RUN_OUT" 2>/dev/null)" \
    "hookEventName,permissionDecision,permissionDecisionReason"
  check "outputs '$rep': permissionDecisionReason is a JSON string" \
    "$(jq -r '.hookSpecificOutput.permissionDecisionReason | type' <<<"$RUN_OUT" 2>/dev/null)" "string"
  check "outputs '$rep': alternative 1 -- foreground plus the Bash tool's timeout parameter" \
    "$(any_in "$REP_REASON" "timeout")" "yes"
  check "outputs '$rep': alternative 2 -- run_in_background" \
    "$(any_in "$REP_REASON" "run_in_background" "run in background")" "yes"
  check "outputs '$rep': alternative 3 -- wait on the pid" \
    "$(any_in "$REP_REASON" "wait")" "yes"
  check "outputs '$rep': alternative 4 -- poll the real condition" \
    "$(any_in "$REP_REASON" "poll" "kill -0" "marker" "real condition")" "yes"
done

# The two rules are distinguishable: a Rule L deny and a Rule B deny do not
# produce the same reason, so "which rule matched" is genuinely reported.
run_cmd "sleep 45"; L_REASON="$(reason_of "$RUN_OUT")"
run_cmd "./build.sh & sleep 30"; B_REASON="$(reason_of "$RUN_OUT")"
check "outputs: Rule L and Rule B denials carry different reasons" \
  "$([ "$L_REASON" != "$B_REASON" ] && echo differ || echo same)" "differ"

# ---------------------------------------------------------------------------
# 4. Inputs -- stdin only; the JQ variable is the sole env var consulted
# ---------------------------------------------------------------------------

# JQ explicitly pointed at the real jq behaves exactly as the default does.
JQ_PATH="$(command -v jq)"
run_cmd "sleep 45" "JQ='$JQ_PATH'"
check "inputs: JQ pointed at the real jq still denies" \
  "$(json_field "$RUN_OUT" '.hookSpecificOutput.permissionDecision')" "deny"
check "inputs: JQ pointed at the real jq exits 0" "$RUN_EXIT" "0"

# No arguments are parsed.
PF="$(payload_for "sleep 45")"
capture "'$BASH_BIN' '$SCRIPT' extra --flag=value < '$PF'"
check "inputs: extraneous argv is ignored (still denies)" \
  "$(json_field "$RUN_OUT" '.hookSpecificOutput.permissionDecision')" "deny"
check "inputs: extraneous argv exits 0" "$RUN_EXIT" "0"

# ---------------------------------------------------------------------------
# 5. Errors -- every failure allows the call (fail-open), exit 0, no output
# ---------------------------------------------------------------------------

assert_fail_open_raw() { # label raw-stdin
  run_raw "$2"
  check "fail-open [$1]: exit 0" "$RUN_EXIT" "0"
  check "fail-open [$1]: no output" "$RUN_OUT" ""
  check "fail-open [$1]: stderr empty" "$RUN_ERR" ""
}

assert_fail_open_raw "empty stdin" ""
assert_fail_open_raw "non-JSON stdin" "this is not json at all"
assert_fail_open_raw "truncated JSON" '{"hook_event_name":"PreToolUse","tool_input":'
assert_fail_open_raw "JSON with no tool_input" \
  '{"hook_event_name":"PreToolUse","tool_name":"Bash"}'
assert_fail_open_raw "tool_input with no command" \
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}'
assert_fail_open_raw "command is JSON null" \
  '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":null}}'
assert_fail_open_raw "JSON array at top level" '[1,2,3]'

# Empty command string.
assert_allow "" "empty-command"

# Absent jq: the JQ variable exists for exactly this. A command that would
# otherwise be denied must be allowed instead.
run_cmd "sleep 45" "JQ=/nonexistent/definitely-not-jq"
check "fail-open [absent jq]: exit 0" "$RUN_EXIT" "0"
check "fail-open [absent jq]: no output" "$RUN_OUT" ""
check "fail-open [absent jq]: stderr empty" "$RUN_ERR" ""

run_cmd "./build.sh & sleep 30" "JQ=/nonexistent/definitely-not-jq"
check "fail-open [absent jq, Rule B input]: exit 0" "$RUN_EXIT" "0"
check "fail-open [absent jq, Rule B input]: no output" "$RUN_OUT" ""

# Closed stdin.
capture "'$BASH_BIN' '$SCRIPT' 0<&-"
check "fail-open [closed stdin]: exit 0" "$RUN_EXIT" "0"
check "fail-open [closed stdin]: no output" "$RUN_OUT" ""
check "fail-open [closed stdin]: stderr empty" "$RUN_ERR" ""

# Oversized stdin: allow, and do not hang.
HUGE="$SCRATCH/huge.txt"
head -c 5000000 /dev/zero 2>/dev/null | tr '\0' 'x' >"$HUGE"
if [ -n "$TIMEOUT_CMD" ]; then
  capture "$TIMEOUT_CMD 10 '$BASH_BIN' '$SCRIPT' < '$HUGE'"
  check "fail-open [oversized stdin]: does not hang" \
    "$([ "$RUN_EXIT" != "124" ] && echo yes || echo no)" "yes"
else
  capture "'$BASH_BIN' '$SCRIPT' < '$HUGE'"
  check "fail-open [oversized stdin]: hang guard SKIPPED (no timeout command)" "skip" "skip"
fi
check "fail-open [oversized stdin]: exit 0" "$RUN_EXIT" "0"
check "fail-open [oversized stdin]: no output" "$RUN_OUT" ""
check "fail-open [oversized stdin]: stderr empty" "$RUN_ERR" ""

# ---------------------------------------------------------------------------
# 6. Invariants
# ---------------------------------------------------------------------------

# Always exits 0 and never writes stderr -- asserted per case above; here the
# whole corpus is swept once more in a single pass so the invariant is pinned
# independently of any one rule's outcome.
INV_EXITS=""
INV_ERRS=""
for c in "sleep 45" "sleep 1" "./build.sh & sleep 30" "./build.sh & sleep 30 # wait" \
         "echo a && sleep 30" "sleep 5 10" "" "sleep abc" "make >& log; sleep 30"; do
  run_cmd "$c"
  INV_EXITS="$INV_EXITS$RUN_EXIT"
  INV_ERRS="$INV_ERRS$RUN_ERR"
done
check "invariant: exit code is 0 on every path (9 varied commands)" "$INV_EXITS" "000000000"
check "invariant: stderr is empty on every path (9 varied commands)" "$INV_ERRS" ""

# Read-only: an empty scratch cwd stays empty across a deny and an allow.
RO_DIR="$(mktemp -d)"
RO_PF="$(payload_for "sleep 45")"
capture "cd '$RO_DIR' && '$BASH_BIN' '$SCRIPT' < '$RO_PF'"
RO_PF="$(payload_for "sleep 1")"
capture "cd '$RO_DIR' && '$BASH_BIN' '$SCRIPT' < '$RO_PF'"
check "invariant: read-only -- writes no file (empty cwd stays empty)" \
  "$(find "$RO_DIR" -mindepth 1 | wc -l | tr -d ' ')" "0"

# Read-only / no config surface: invoked from a cwd with no .claude or .local
# anywhere in it, the decision is unchanged.
RO_PF="$(payload_for "sleep 45")"
capture "cd '$RO_DIR' && '$BASH_BIN' '$SCRIPT' < '$RO_PF'"
check "invariant: reads no config -- same deny from an unrelated empty cwd" \
  "$(json_field "$RUN_OUT" '.hookSpecificOutput.permissionDecision')" "deny"
rmdir "$RO_DIR" 2>/dev/null

# Determinism: the same command string yields byte-identical output twice.
run_cmd "./build.sh & sleep 30"; DET1="$RUN_OUT"; DET1_RC="$RUN_EXIT"
run_cmd "./build.sh & sleep 30"; DET2="$RUN_OUT"; DET2_RC="$RUN_EXIT"
check "invariant: determinism -- identical stdout across two runs" "$DET2" "$DET1"
check "invariant: determinism -- identical exit code across two runs" "$DET2_RC" "$DET1_RC"

# No environment escape hatch: plausible disable variables have no effect.
run_cmd "sleep 45" "CLAM_SLEEP_GATE=disabled DISABLE_SLEEP_GATE=1 SLEEP_GATE=off"
check "invariant: no escape hatch -- plausible disable env vars still deny" \
  "$(json_field "$RUN_OUT" '.hookSpecificOutput.permissionDecision')" "deny"

# Keys on the SHAPE of the wait, never on the word `sleep`: representative
# legitimate sleeps all pass untouched.
assert_allow "until [ -f done.marker ]; do sleep 1; done" "shape-poll-loop"
assert_allow "kill -TERM \$pid; sleep 2; kill -KILL \$pid; trap - EXIT" "shape-kill-grace"
assert_allow "touch a; sleep 1; touch b; test a -ot b" "shape-mtime-granularity"
assert_allow "bash -c 'sleep 5' & echo backgrounded; wait" "shape-test-double"

# bash 3.2 compatibility: if a 3.x bash is on this machine, the script must
# behave identically under it. Behavioral proxy only -- the suite never reads
# the script's source to look for 4.x constructs.
BASH32=""
for candidate in /bin/bash /usr/bin/bash; do
  if [ -x "$candidate" ] && "$candidate" -c 'exit 0' 2>/dev/null; then
    # shellcheck disable=SC2016  # the expansion must happen in the probed shell
    if [[ "$("$candidate" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)" == "3" ]]; then
      BASH32="$candidate"; break
    fi
  fi
done
if [ -n "$BASH32" ]; then
  run_cmd "sleep 45" "" "$BASH32"
  check "invariant: bash 3.2 -- Rule L deny is identical under bash 3.x" \
    "$(json_field "$RUN_OUT" '.hookSpecificOutput.permissionDecision')" "deny"
  check "invariant: bash 3.2 -- exit 0 under bash 3.x" "$RUN_EXIT" "0"
  check "invariant: bash 3.2 -- stderr empty under bash 3.x" "$RUN_ERR" ""
  run_cmd "sleep 1" "" "$BASH32"
  check "invariant: bash 3.2 -- allow is identical under bash 3.x" "$RUN_OUT" ""
else
  check "invariant: bash 3.2 -- SKIPPED (no bash 3.x on this machine)" "skip" "skip"
fi

# ---------------------------------------------------------------------------
# 7. Edge cases not already covered above
# ---------------------------------------------------------------------------

# A quoted mention of `sleep` cannot be the first statement, so Rule L cannot
# false-positive on it (and with no background `&`, Rule B does not either).
assert_allow "echo 'sleep 30 is a bad idea'" "quoted-mention"
assert_allow "grep -r \"sleep 45\" ." "quoted-mention"

# Heredoc mention, same reasoning.
assert_allow "$(printf 'cat <<EOF\nsleep 300\nEOF')" "heredoc-mention"

# Invoked outside a hook context: a bare, minimal payload with no hook
# metadata at all still yields the same decision.
capture "printf '%s' '{\"tool_input\":{\"command\":\"sleep 45\"}}' | '$BASH_BIN' '$SCRIPT'"
check "edge: minimal payload with no hook metadata still denies" \
  "$(json_field "$RUN_OUT" '.hookSpecificOutput.permissionDecision')" "deny"
check "edge: minimal payload exits 0" "$RUN_EXIT" "0"

# Subagent tool calls: PreToolUse fires for these too and the gate applies
# identically.
SUB_PF="$SCRATCH/subagent.json"
jq -n '{hook_event_name:"PreToolUse",tool_name:"Bash",agent_type:"lego-implementer",tool_input:{command:"sleep 45"}}' >"$SUB_PF"
capture "'$BASH_BIN' '$SCRIPT' < '$SUB_PF'"
check "edge: subagent-shaped payload denies identically" \
  "$(json_field "$RUN_OUT" '.hookSpecificOutput.permissionDecision')" "deny"
check "edge: subagent-shaped payload exits 0" "$RUN_EXIT" "0"
check "edge: subagent-shaped payload writes no stderr" "$RUN_ERR" ""

# A tool call that is not Bash-shaped at all (no command key) fails open --
# already covered under Errors; here with extra sibling keys present.
assert_fail_open_raw "tool_input holding unrelated keys" \
  '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/sleep 45"}}'

# ---------------------------------------------------------------------------
if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
