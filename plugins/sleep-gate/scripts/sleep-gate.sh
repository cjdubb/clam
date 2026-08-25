#!/usr/bin/env bash
# sleep-gate.sh — PreToolUse hook denying `sleep` used as a completion-wait
# for a backgrounded script. Wired via hooks/hooks.json with matcher "Bash".
#
# <!--
# Contract: B01 sleep-gate hook script (plan 001-sleep-gate)
#
# Behavior:
#   Reads the PreToolUse hook JSON from stdin and extracts
#   .tool_input.command. Applies two rules to that command string; either
#   one matching denies the tool call.
#
#   Rule L — a leading bare sleep. The command's FIRST STATEMENT is
#     `sleep <duration>` and the duration is 2 seconds or longer. The first
#     statement is the command text up to the first `;`, `&&`, `||`, `|`, or
#     newline, trimmed. Exactly one operand, optionally suffixed `s`, `m`,
#     `h`, or `d`, converted to seconds (m=60, h=3600, d=86400). Matches:
#     `sleep 45`, `sleep 2m`, `sleep 30 && cat /tmp/build.log`. Does not
#     match: `sleep 0.25`, `sleep 1`, or any sleep that is not the first
#     statement. This is the rule that catches the separate-turn shape —
#     the agent backgrounds a script in one tool call and sleeps in the
#     next — without the hook holding any state between calls.
#
#   Rule B — a background launch followed by a sleep. All three hold:
#     (1) the command contains a BACKGROUND `&`: an `&` that is not part of
#         `&&`, `>&`, `&>`, `<&`, or an escaped `\&`;
#     (2) a `sleep` appears AFTER the first background `&`;
#     (3) the command contains NONE of the words `while`, `until`, `for`,
#         `break`, `wait`, or `trap` anywhere in it.
#     Clause 3 is the carve-out that keeps the rule honest: a poll loop
#     (`srv & until curl -sf "$u/health"; do sleep 0.25; done`) already
#     waits on the real event, and a kill-grace sleep sits beside a `trap`.
#     It errs toward allowing — a missed misuse costs nothing, whereas a
#     wrong denial interrupts a session that was doing the right thing.
#
#   On a match, write ONE single-line JSON object to stdout:
#     {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#      "permissionDecision":"deny","permissionDecisionReason":"<reason>"}}
#   and exit 0. On no match, write nothing and exit 0.
#
# Inputs:
#   Hook JSON on stdin. No arguments. No config files, no reads from
#   .claude/ or .local/. The only environment variable consulted is JQ
#   (defaulting to `jq`), which exists so tests can point at a stub or an
#   absent binary; it is not a user-facing configuration surface.
#
# Outputs:
#   stdout: the deny object above, or nothing at all. The
#   permissionDecisionReason must name WHICH rule matched, state that a
#   fixed sleep is not a completion signal, and list all four alternatives:
#     - run the command in the foreground and let the Bash tool's own
#       `timeout` parameter bound it;
#     - pass run_in_background: true and let the harness re-invoke on exit;
#     - `wait "$pid"` when the process is a child of this shell;
#     - poll the real condition (`until [ -f done.marker ]; do sleep 1; done`,
#       or `kill -0 "$pid"`).
#   stderr: nothing, ever.
#
# Errors:
#   None reachable. Every failure allows the call: absent jq, unparseable
#   JSON, absent .tool_input.command, an empty command, a duration that is
#   not a number, a multi-operand `sleep 5 10`.
#
# Invariants:
#   - ALWAYS exits 0. A nonzero exit from a PreToolUse hook is itself a
#     denial, so the entire fail-open promise rests on this. There is no
#     code path that exits nonzero.
#   - Fail-open everywhere: when in doubt, allow. A gate on the Bash tool
#     that failed closed would wedge every session it is installed in.
#   - Read-only: never writes a file, never reads one.
#   - Never writes to stderr.
#   - Deterministic: the same command string always yields the same
#     decision.
#   - No configuration surface and no environment escape hatch;
#     uninstalling the plugin is the opt-out.
#   - Uses only constructs available in bash 3.2, so it behaves identically
#     under stock macOS bash. No associative arrays, no `wait -n`, no
#     `${var,,}`.
#   - Keys on the SHAPE of the wait, never on the word `sleep`. Poll
#     intervals inside condition loops, SIGTERM/SIGKILL grace periods,
#     clock- and mtime-granularity waits, and `sleep` used as a test double
#     for a slow process all pass untouched.
#
# Edge cases:
#   - `sleep 0.25`, `sleep 1`: allow (below the 2s floor).
#   - `sleep` inside a while/until/for body, or alongside wait/break/trap:
#     allow, under Rule B clause 3.
#   - `&&`, `2>&1`, `&>`, `>&`, `<&`, `\&`: none counts as a background
#     launch.
#   - A `sleep` appearing BEFORE the first background `&`: allow.
#   - Multi-operand `sleep 5 10`: allow (no match).
#   - A quoted or heredoc mention of `sleep` cannot be the first statement,
#     so Rule L cannot false-positive on it; Rule B may, and a denial there
#     is harmless because the reason names the alternative.
#   - Empty, closed, or oversized stdin: allow.
#   - Invoked outside a hook context (manually, or by a test): identical
#     behavior.
#   - Subagent tool calls: PreToolUse hooks fire for these too; the gate
#     applies identically.
# -->

set -u
: "${JQ:=jq}"

NL='
'

# --- helpers ---------------------------------------------------------------

# trim <string> -- strip leading and trailing whitespace.
trim() {
  local s="$1"
  while [ -n "$s" ]; do
    case "$s" in
      [[:space:]]*) s="${s#?}" ;;
      *) break ;;
    esac
  done
  while [ -n "$s" ]; do
    case "$s" in
      *[[:space:]]) s="${s%?}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$s"
}

# is_word_char <char> -- 0 when the character continues a shell word.
is_word_char() {
  case "$1" in
    [A-Za-z0-9_]) return 0 ;;
    *) return 1 ;;
  esac
}

# contains_word <word> <haystack> -- 0 when <word> appears as a whole word.
contains_word() {
  local w="$1" rest="$2" pre after prev next
  while :; do
    case "$rest" in
      *"$w"*) ;;
      *) return 1 ;;
    esac
    pre="${rest%%"$w"*}"
    after="${rest#*"$w"}"
    prev=""
    [ -n "$pre" ] && prev="${pre:${#pre}-1:1}"
    next=""
    [ -n "$after" ] && next="${after:0:1}"
    if ! is_word_char "$prev" && ! is_word_char "$next"; then
      return 0
    fi
    rest="$after"
  done
}

# strip_zeros <digits> -- drop leading zeros, keeping at least one digit, so
# the result is never read as octal by bash arithmetic.
strip_zeros() {
  local x="$1"
  while [ "${#x}" -gt 1 ]; do
    case "$x" in
      0*) x="${x#0}" ;;
      *) break ;;
    esac
  done
  [ -n "$x" ] || x=0
  printf '%s' "$x"
}

# duration_ge_2s <operand> -- 0 when the operand is a single number, with an
# optional s/m/h/d suffix, worth two seconds or more. Anything unparseable
# returns nonzero (allow).
duration_ge_2s() {
  local op="$1" num mult intp frac total
  case "$op" in
    *s) num="${op%s}"; mult=1 ;;
    *m) num="${op%m}"; mult=60 ;;
    *h) num="${op%h}"; mult=3600 ;;
    *d) num="${op%d}"; mult=86400 ;;
    *) num="$op"; mult=1 ;;
  esac
  [ -n "$num" ] || return 1

  case "$num" in
    *.*) intp="${num%%.*}"; frac="${num#*.}" ;;
    *) intp="$num"; frac="" ;;
  esac
  case "$frac" in
    *.*) return 1 ;;
  esac
  case "$intp" in
    *[!0-9]*) return 1 ;;
  esac
  case "$frac" in
    *[!0-9]*) return 1 ;;
  esac
  [ -n "$intp" ] || [ -n "$frac" ] || return 1

  # A whole-second count this large is unambiguously past the floor, and
  # skipping the arithmetic keeps it away from integer overflow.
  [ "${#intp}" -gt 9 ] && return 0

  frac="${frac}000"
  frac="${frac:0:3}"
  intp="$(strip_zeros "${intp:-0}")"
  frac="$(strip_zeros "$frac")"

  total=$(( (intp * 1000 + frac) * mult ))
  [ "$total" -ge 2000 ]
}

# first_statement <command> -- the command text up to the first `;`, `&&`,
# `||`, `|` or newline, trimmed.
first_statement() {
  local cmd="$1" first="$1" d cand
  for d in ';' '&&' '||' '|' "$NL"; do
    cand="${cmd%%"$d"*}"
    if [ "${#cand}" -lt "${#first}" ]; then
      first="$cand"
    fi
  done
  trim "$first"
}

# background_amp_pos <command> -- index of the first background `&`, or -1.
# An `&` belonging to `&&`, `>&`, `&>`, `<&` or `\&` is not a background
# launch.
background_amp_pos() {
  local cmd="$1" n i ch prev next
  n="${#cmd}"
  i=0
  while [ "$i" -lt "$n" ]; do
    ch="${cmd:i:1}"
    if [ "$ch" = "&" ]; then
      prev=""
      [ "$i" -gt 0 ] && prev="${cmd:i-1:1}"
      next=""
      [ "$((i + 1))" -lt "$n" ] && next="${cmd:i+1:1}"
      if [ "$next" = "&" ]; then
        i=$((i + 2)); continue
      fi
      if [ "$prev" = "&" ] || [ "$prev" = ">" ] || [ "$prev" = "<" ] ||
         [ "$prev" = "\\" ]; then
        i=$((i + 1)); continue
      fi
      if [ "$next" = ">" ]; then
        i=$((i + 1)); continue
      fi
      printf '%s' "$i"
      return 0
    fi
    i=$((i + 1))
  done
  printf '%s' "-1"
}

deny() { # reason
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

ALTERNATIVES="Instead: run it in the foreground and let the Bash tool's own timeout parameter bound it; or pass run_in_background: true and let the harness re-invoke you when the process exits; or wait for the child pid with wait; or poll the real condition (until [ -f done.marker ]; do sleep 1; done, or kill -0 on the pid)."

# --- input -----------------------------------------------------------------

# Every failure below allows the call: absent jq, unreadable stdin,
# unparseable JSON, or an absent command all leave the gate silent.
command -v "$JQ" >/dev/null 2>&1 || exit 0

# A closed stdin has to be detected before reading: with fd 0 closed, the
# command substitution below would hand `cat` its own pipe and block forever.
# Where neither /dev/fd nor /proc is present the check is skipped rather than
# guessed at.
if [ -d /dev/fd ] || [ -d /proc/self/fd ]; then
  if [ ! -e /dev/fd/0 ] && [ ! -e /proc/self/fd/0 ]; then
    exit 0
  fi
fi

input="$(cat 2>/dev/null)" || exit 0
[ -n "$input" ] || exit 0

if ! command_str="$(printf '%s' "$input" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)"; then
  exit 0
fi
[ -n "$command_str" ] || exit 0

# --- Rule L: a leading bare sleep of two seconds or longer -----------------

stmt="$(first_statement "$command_str")"
head_word="${stmt%%[[:space:]]*}"
if [ "$head_word" = "sleep" ]; then
  operand="$(trim "${stmt#sleep}")"
  tail_words="${operand#"${operand%%[[:space:]]*}"}"
  tail_words="$(trim "$tail_words")"
  operand="${operand%%[[:space:]]*}"
  if [ -n "$operand" ] && [ -z "$tail_words" ] && duration_ge_2s "$operand"; then
    deny "Rule L (leading bare sleep): this command's first statement is 'sleep $operand', a fixed wait for work that is not being watched. A fixed sleep is not a completion signal - it guesses at a duration instead of observing the thing finish. $ALTERNATIVES"
  fi
fi

# --- Rule B: a background launch followed by a sleep -----------------------

amp_pos="$(background_amp_pos "$command_str")"
if [ "$amp_pos" -ge 0 ]; then
  after_amp="${command_str:amp_pos+1}"
  case "$after_amp" in
    *sleep*)
      # Clause 3 carve-out: a poll loop, a `wait`, or a trap-side grace
      # period is already waiting on the real event, so leave it alone.
      for kw in while until for break wait trap; do
        if contains_word "$kw" "$command_str"; then
          exit 0
        fi
      done
      deny "Rule B (background launch then sleep): this command starts something in the background with & and then sleeps to wait for it. A fixed sleep is not a completion signal - the process may exit far sooner, or still be running when the sleep ends. $ALTERNATIVES"
      ;;
  esac
fi

exit 0
