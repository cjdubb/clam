#!/bin/bash
# Functional test for activity.sh: shared conversation-activity readers
# (Contract: B01 activity-lib, docblock in activity.sh).
# Run: bash plugins/tracking/lib/activity.test.sh   (exits non-zero on failure)
#
# The lib is SOURCED (never executed as a script) and its two functions are
# called directly, matching how the freshness Stop gate (B02) and the
# resume-freshness SessionStart check (B04) consume it.
#
# Every case asserts BOTH the stdout content AND the exit code, since "never
# returns nonzero" is a blanket invariant for both functions — this also
# guarantees every case below runs red against the unimplemented stub, which
# always returns 90.
#
# Hermetic: everything lives under $TMPROOT (removed on exit). No network.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/activity.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../../scripts/lib/test-portability.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }
check() { # label got expected
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 -> got '$2', expected '$3'"; fi
}

# A stub PATH with common coreutils (including bash) symlinked in, but
# deliberately excluding jq, so "jq not available" can be exercised without
# touching the real system PATH. Mirrors flush-nudge.test.sh's NOJQ_BIN.
NOJQ_BIN="$TMPROOT/no-jq-bin"
mkdir -p "$NOJQ_BIN"
for tool in bash sh cat rm tr mkdir printf sed grep basename dirname wc head tail cp mv touch date ls sort mktemp readlink realpath env find stat cut; do
  src=$(command -v "$tool" 2>/dev/null) || continue
  ln -sf "$src" "$NOJQ_BIN/$tool" 2>/dev/null
done

# Proves the running user isn't root — chmod-000 unreadability cases are
# meaningless (and would false-pass) under a uid that ignores permission
# bits entirely.
IS_ROOT=0
[[ "$(id -u)" == "0" ]] && IS_ROOT=1

# shellcheck source=./activity.sh
source "$LIB"

echo "=== activity_prompts_since ==="

REF_EPOCH=1780000000
EQUAL_TS=$(tp_epoch_fmt "$REF_EPOCH" +"%Y-%m-%dT%H:%M:%SZ")
BEFORE_TS=$(tp_epoch_fmt "$((REF_EPOCH - 1))" +"%Y-%m-%dT%H:%M:%SZ")
AFTER_TS=$(tp_epoch_fmt "$((REF_EPOCH + 1))" +"%Y-%m-%dT%H:%M:%SZ")
AFTER_TS_MS="${AFTER_TS%Z}.720Z"
FAR_FUTURE_EPOCH=$((REF_EPOCH + 1000000000))

T="$TMPROOT/transcript.jsonl"

write_t() { printf '%s\n' "$@" > "$T"; }  # writes given JSON lines to $T

PS_OUT=""; PS_RC=0
run_ps() { # ref_epoch transcript_path
  PS_OUT=$(activity_prompts_since "$1" "$2" 2>"$TMPROOT/ps_stderr")
  PS_RC=$?
}
assert_ps() { # label expected_count
  check "$1 (count)" "$PS_OUT" "$2"
  check "$1 (exit 0)" "$PS_RC" "0"
}

# --- Behavior: counts a qualifying human prompt strictly newer than ref ------

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello, this is a human prompt\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "human prompt after ref_epoch: counted" 1

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$BEFORE_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "human prompt before ref_epoch: not counted" 0

# Strictly greater, not >=: a timestamp exactly at ref_epoch does not count.
write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$EQUAL_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "human prompt exactly at ref_epoch: not counted (strictly greater required)" 0

# Multiple qualifying prompts, mixed with disqualified lines, to prove an
# accurate count rather than a boolean any/none check.
write_t \
  "{\"type\":\"user\",\"message\":{\"content\":\"first\"},\"timestamp\":\"$AFTER_TS\"}" \
  "{\"type\":\"user\",\"message\":{\"content\":\"<command-name>x</command-name>\"},\"timestamp\":\"$AFTER_TS\"}" \
  "{\"type\":\"user\",\"message\":{\"content\":\"second\"},\"timestamp\":\"$AFTER_TS\"}" \
  "{\"type\":\"user\",\"message\":{\"content\":\"third\"},\"timestamp\":\"$BEFORE_TS\"}" \
  "{\"type\":\"user\",\"message\":{\"content\":\"fourth\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "3 qualifying prompts among 5 lines: exact count" 3

# --- Behavior: .message.content must be a STRING; array content is a tool result ---

write_t "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"looks like plain text\"}]},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "array-content user entry (tool result): not counted" 0

# --- Behavior: .isMeta must be absent or false -------------------------------

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"isMeta\":true,\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "isMeta:true entry: not counted" 0

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"isMeta\":false,\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "isMeta:false entry: counted" 1

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "isMeta absent entirely: counted" 1

# --- Behavior: .type must be "user" -------------------------------------------

write_t "{\"type\":\"assistant\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "type=assistant with string content: not counted" 0

# --- Behavior: machine-generated content prefixes are excluded ---------------

write_t "{\"type\":\"user\",\"message\":{\"content\":\"<command-name>foo</command-name>\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "content starting with '<' (command echo): not counted" 0

write_t "{\"type\":\"user\",\"message\":{\"content\":\"<system-reminder>note</system-reminder>\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "content starting with '<' (system-reminder): not counted" 0

write_t "{\"type\":\"user\",\"message\":{\"content\":\"Stop hook feedback: try again\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "content starting with 'Stop hook feedback:': not counted" 0

write_t "{\"type\":\"user\",\"message\":{\"content\":\"Another Claude session sent a message\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "content starting with 'Another Claude session sent': not counted" 0

write_t "{\"type\":\"user\",\"message\":{\"content\":\"[Request interrupted by user]\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "content starting with '[Request interrupted': not counted" 0

write_t "{\"type\":\"user\",\"message\":{\"content\":\"Shell cwd was reset to /home\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "content starting with 'Shell cwd was reset': not counted" 0

write_t "{\"type\":\"user\",\"message\":{\"content\":\"Caveat: the messages below were generated\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "content starting with 'Caveat: the messages below': not counted" 0

# Optional leading whitespace before the machine-generated marker still excludes.
write_t "{\"type\":\"user\",\"message\":{\"content\":\"   <command-name>x</command-name>\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "leading whitespace then '<' marker: still not counted" 0

# Leading whitespace before ordinary text (not matching any marker) must NOT
# cause a false exclusion.
write_t "{\"type\":\"user\",\"message\":{\"content\":\"   hello, just an indented prompt\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "leading whitespace then ordinary text: still counted" 1

# --- Errors: malformed JSON lines are skipped, never fatal -------------------

write_t \
  "{\"type\": this is not valid json" \
  "{\"type\":\"user\",\"message\":{\"content\":\"good one\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "malformed JSON line skipped; valid line after it still counted" 1

# --- Edge cases: timestamp parsing -------------------------------------------

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$AFTER_TS_MS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "timestamp WITH milliseconds after ref: counted" 1

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "timestamp WITHOUT milliseconds after ref: counted" 1

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"not-a-timestamp\"}"
run_ps "$REF_EPOCH" "$T"
assert_ps "unparseable timestamp format: skipped, not counted" 0

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"}}"
run_ps "$REF_EPOCH" "$T"
assert_ps "entry missing .timestamp entirely: skipped, not counted" 0

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "$FAR_FUTURE_EPOCH" "$T"
assert_ps "ref_epoch far in the future: 0 even with an otherwise-qualifying prompt" 0

# --- Inputs: ref_epoch validation --------------------------------------------

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$AFTER_TS\"}"
run_ps "not-an-integer" "$T"
assert_ps "ref_epoch non-integer: fail-open to 0" 0

run_ps "" "$T"
assert_ps "ref_epoch empty: fail-open to 0" 0

# --- Inputs: transcript_path validation --------------------------------------

run_ps "$REF_EPOCH" "$TMPROOT/does-not-exist.jsonl"
assert_ps "transcript_path missing: fail-open to 0" 0

: > "$T"
run_ps "$REF_EPOCH" "$T"
assert_ps "transcript_path empty file: fail-open to 0" 0

run_ps "$REF_EPOCH" "$TMPROOT"
assert_ps "transcript_path is a directory: fail-open to 0" 0

if [[ "$IS_ROOT" == "0" ]]; then
  write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$AFTER_TS\"}"
  chmod 000 "$T"
  run_ps "$REF_EPOCH" "$T"
  assert_ps "transcript_path unreadable (chmod 000): fail-open to 0" 0
  chmod 644 "$T"
else
  echo "SKIP  transcript_path unreadable case: running as root, permission bits ignored"
fi

# --- Errors: no jq on PATH -> fail-open to 0 ---------------------------------

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$AFTER_TS\"}"
PS_OUT=$(PATH="$NOJQ_BIN" activity_prompts_since "$REF_EPOCH" "$T" 2>"$TMPROOT/ps_stderr")
PS_RC=$?
assert_ps "jq absent from PATH: fail-open to 0, even with an otherwise-qualifying prompt" 0

# --- Outputs: exactly one line on every path, including failure paths -------

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$AFTER_TS\"}"
activity_prompts_since "$REF_EPOCH" "$T" > "$TMPROOT/ps_lines_ok" 2>/dev/null
check "happy path: exactly one line of stdout" "$(wc -l < "$TMPROOT/ps_lines_ok" | tr -d ' ')" "1"

activity_prompts_since "$REF_EPOCH" "$TMPROOT/does-not-exist.jsonl" > "$TMPROOT/ps_lines_fail" 2>/dev/null
check "failure path (missing transcript): exactly one line of stdout" "$(wc -l < "$TMPROOT/ps_lines_fail" | tr -d ' ')" "1"

# --- Invariants: pure read, never writes to the transcript -------------------

write_t "{\"type\":\"user\",\"message\":{\"content\":\"hello\"},\"timestamp\":\"$AFTER_TS\"}"
DIGEST_BEFORE=$(md5sum "$T")
run_ps "$REF_EPOCH" "$T"
DIGEST_AFTER=$(md5sum "$T")
check "transcript file unchanged after call (read-only)" "$DIGEST_AFTER" "$DIGEST_BEFORE"
check "transcript file unchanged after call (exit 0)" "$PS_RC" "0"

# --- Invariants: idempotent ---------------------------------------------------

run_ps "$REF_EPOCH" "$T"
FIRST_OUT="$PS_OUT"; FIRST_RC="$PS_RC"
check "idempotent: first call (exit 0)" "$FIRST_RC" "0"
run_ps "$REF_EPOCH" "$T"
check "idempotent: repeated call, same output" "$PS_OUT" "$FIRST_OUT"
check "idempotent: repeated call, same exit code" "$PS_RC" "$FIRST_RC"
check "idempotent: repeated call (exit 0)" "$PS_RC" "0"

# --- Invariants: no globals mutated beyond its own locals --------------------
# Calls the function directly (not via $(...), which would hide leaks inside
# its own subshell) so any variable left behind without `local` is visible.

compgen -v | sort > "$TMPROOT/ps_vars_before"
activity_prompts_since "$REF_EPOCH" "$T" > "$TMPROOT/ps_leak_out" 2>/dev/null
echo $? > "$TMPROOT/ps_leak_rc"
compgen -v | sort > "$TMPROOT/ps_vars_after"
check "no global variables leak into the caller's shell" \
  "$(cat "$TMPROOT/ps_vars_after")" "$(cat "$TMPROOT/ps_vars_before")"
check "no global variables leak into the caller's shell (exit 0)" "$(cat "$TMPROOT/ps_leak_rc")" "0"

# --- Invariant: single-pass / bounded-time over a larger transcript ----------
# Not independently observable as a pass count through the public interface;
# this instead sanity-checks that a ~2000-line file both completes promptly
# and is counted exactly right (a red-flag double-count or infinite loop
# would show up as a wrong count or a timeout kill).

LARGE_T="$TMPROOT/large.jsonl"
: > "$LARGE_T"
for _ in $(seq 1 2000); do
  printf '{"type":"user","message":{"content":"hello"},"timestamp":"%s"}\n' "$AFTER_TS" >> "$LARGE_T"
done
printf 'not json at all\n' >> "$LARGE_T"
LARGE_OUT=$(timeout 10 bash -c 'source "$1"; activity_prompts_since "$2" "$3"' _ "$LIB" "$REF_EPOCH" "$LARGE_T")
LARGE_RC=$?
check "~2000-line transcript: exact count, completes within timeout" "$LARGE_OUT" "2000"
check "~2000-line transcript: exit 0" "$LARGE_RC" "0"

echo ""
echo "=== activity_prior_transcripts ==="

# sanitize <path> -> the contract's "/" -> "-" project-directory encoding.
sanitize() { printf '%s' "$1" | sed 's#/#-#g'; }

PT_OUT="$TMPROOT/pt_out"
PT_ERR="$TMPROOT/pt_err"
PT_RC=0
run_pt() { # cwd [exclude_path]
  activity_prior_transcripts "$@" > "$PT_OUT" 2>"$PT_ERR"
  PT_RC=$?
}
assert_pt_lines() { # label expected-line...
  local label="$1"; shift
  local expected=("$@")
  local got=()
  if [[ -s "$PT_OUT" ]]; then mapfile -t got < "$PT_OUT"; fi
  if [[ "${#got[@]}" -eq "${#expected[@]}" ]]; then
    local ok=1 i
    for ((i = 0; i < ${#expected[@]}; i++)); do
      [[ "${got[$i]}" == "${expected[$i]}" ]] || ok=0
    done
    if [[ "$ok" -eq 1 ]]; then pass "$label"; else fail "$label -> got: ${got[*]}; expected: ${expected[*]}"; fi
  else
    fail "$label -> got ${#got[@]} line(s) [${got[*]}]; expected ${#expected[@]} [${expected[*]}]"
  fi
  check "$label (exit 0)" "$PT_RC" "0"
}
assert_pt_empty() { # label
  local label="$1"
  if [[ ! -s "$PT_OUT" ]]; then pass "$label: no output at all"; else fail "$label: expected no output, got: $(cat "$PT_OUT")"; fi
  check "$label (exit 0)" "$PT_RC" "0"
}

HOME_A="$TMPROOT/home-a"
mkdir -p "$HOME_A"
CWD_A="/home/user/proj"
PROJ_DIR_A="$HOME_A/.claude/projects/$(sanitize "$CWD_A")"
mkdir -p "$PROJ_DIR_A"

# --- Behavior: project dir derivation ($HOME/.claude/projects/<cwd, / -> ->) --

check "encoding: sanitize helper sanity check" "$(sanitize "$CWD_A")" "-home-user-proj"

# Newest-first mtime ordering: filenames deliberately in the OPPOSITE order
# of their mtimes, so a name-based or creation-order sort would be caught.
touch -t 202601010000 "$PROJ_DIR_A/zzz-oldest.jsonl"
touch -t 202601020000 "$PROJ_DIR_A/mmm-middle.jsonl"
touch -t 202601030000 "$PROJ_DIR_A/aaa-newest.jsonl"

HOME="$HOME_A" run_pt "$CWD_A"
assert_pt_lines "newest-first mtime ordering (3 files)" \
  "$PROJ_DIR_A/aaa-newest.jsonl" "$PROJ_DIR_A/mmm-middle.jsonl" "$PROJ_DIR_A/zzz-oldest.jsonl"

# --- Inputs: exclude_path omits the named transcript -------------------------

HOME="$HOME_A" run_pt "$CWD_A" "$PROJ_DIR_A/mmm-middle.jsonl"
assert_pt_lines "exclude_path omits the matching file, order preserved" \
  "$PROJ_DIR_A/aaa-newest.jsonl" "$PROJ_DIR_A/zzz-oldest.jsonl"

# exclude_path naming a file that isn't in the listing -> unchanged.
HOME="$HOME_A" run_pt "$CWD_A" "$PROJ_DIR_A/does-not-exist.jsonl"
assert_pt_lines "exclude_path names a file not present: listing unchanged" \
  "$PROJ_DIR_A/aaa-newest.jsonl" "$PROJ_DIR_A/mmm-middle.jsonl" "$PROJ_DIR_A/zzz-oldest.jsonl"

# Project dir exists but only the excluded transcript is present -> no output.
HOME_ONLY="$TMPROOT/home-only-excluded"
CWD_ONLY="/only/excluded"
PROJ_DIR_ONLY="$HOME_ONLY/.claude/projects/$(sanitize "$CWD_ONLY")"
mkdir -p "$PROJ_DIR_ONLY"
touch "$PROJ_DIR_ONLY/sole.jsonl"
HOME="$HOME_ONLY" run_pt "$CWD_ONLY" "$PROJ_DIR_ONLY/sole.jsonl"
assert_pt_empty "only the excluded transcript present"

# --- Behavior: only regular *.jsonl files DIRECTLY in the dir (no recursion) -

HOME_R="$TMPROOT/home-recursion"
CWD_R="/recursion/proj"
PROJ_DIR_R="$HOME_R/.claude/projects/$(sanitize "$CWD_R")"
mkdir -p "$PROJ_DIR_R/some-session-id/subagents"
touch "$PROJ_DIR_R/top-level.jsonl"
touch "$PROJ_DIR_R/some-session-id/subagents/nested.jsonl"
touch "$PROJ_DIR_R/not-jsonl.json"
touch "$PROJ_DIR_R/not-jsonl.txt"
mkdir -p "$PROJ_DIR_R/looks-like-a-transcript.jsonl"  # a directory, not a regular file

HOME="$HOME_R" run_pt "$CWD_R"
assert_pt_lines "only direct *.jsonl regular files: nested/non-.jsonl/dir-named-.jsonl all excluded" \
  "$PROJ_DIR_R/top-level.jsonl"

# --- Edge cases: absent project dir / empty cwd -------------------------------

HOME_MISSING="$TMPROOT/home-missing-projdir"
mkdir -p "$HOME_MISSING"
HOME="$HOME_MISSING" run_pt "/some/cwd/with/no/project/dir"
assert_pt_empty "project directory does not exist"

HOME="$HOME_A" run_pt ""
assert_pt_empty "cwd is empty"

# --- Errors: unreadable project directory -------------------------------------

if [[ "$IS_ROOT" == "0" ]]; then
  HOME_UNREAD="$TMPROOT/home-unreadable"
  CWD_UNREAD="/unreadable/proj"
  PROJ_DIR_UNREAD="$HOME_UNREAD/.claude/projects/$(sanitize "$CWD_UNREAD")"
  mkdir -p "$PROJ_DIR_UNREAD"
  touch "$PROJ_DIR_UNREAD/one.jsonl"
  chmod 000 "$PROJ_DIR_UNREAD"
  HOME="$HOME_UNREAD" run_pt "$CWD_UNREAD"
  assert_pt_empty "unreadable project directory"
  chmod 755 "$PROJ_DIR_UNREAD"
else
  echo "SKIP  unreadable project directory case: running as root, permission bits ignored"
fi

# --- Edge case: cwd containing "-" collides losslessly with another cwd -----
# "/home/a-b/proj" and "/home/a/b-proj" both sanitize to "-home-a-b-proj".
# The contract requires no special collision handling — both must simply
# resolve to (and find) the same directory without erroring.

HOME_COLLIDE="$TMPROOT/home-collide"
CWD_DASH1="/home/a-b/proj"
CWD_DASH2="/home/a/b-proj"
check "collision precondition: both cwds sanitize identically" \
  "$(sanitize "$CWD_DASH1")" "$(sanitize "$CWD_DASH2")"
PROJ_DIR_COLLIDE="$HOME_COLLIDE/.claude/projects/$(sanitize "$CWD_DASH1")"
mkdir -p "$PROJ_DIR_COLLIDE"
touch "$PROJ_DIR_COLLIDE/shared.jsonl"

HOME="$HOME_COLLIDE" run_pt "$CWD_DASH1"
assert_pt_lines "dash-collision cwd #1 resolves to the shared dir" "$PROJ_DIR_COLLIDE/shared.jsonl"
HOME="$HOME_COLLIDE" run_pt "$CWD_DASH2"
assert_pt_lines "dash-collision cwd #2 resolves to the same shared dir, no error" "$PROJ_DIR_COLLIDE/shared.jsonl"

# --- Invariant: the ONLY inputs are the two arguments and $HOME --------------
# Neither CLAUDE_CODE_SESSION_ID nor jq's presence on PATH is $HOME or an
# argument, so output must be identical whether or not they're set/available.

HOME="$HOME_A" CLAUDE_CODE_SESSION_ID="" run_pt "$CWD_A"
BASELINE_OUT=$(cat "$PT_OUT")
check "baseline call for invariance checks (exit 0)" "$PT_RC" "0"
HOME="$HOME_A" CLAUDE_CODE_SESSION_ID="11111111-aaaa-bbbb-cccc-222222222222" run_pt "$CWD_A"
check "output unaffected by CLAUDE_CODE_SESSION_ID being set" "$(cat "$PT_OUT")" "$BASELINE_OUT"
check "output unaffected by CLAUDE_CODE_SESSION_ID being set (exit 0)" "$PT_RC" "0"

PT_JQLESS_OUT=$(PATH="$NOJQ_BIN" HOME="$HOME_A" activity_prior_transcripts "$CWD_A" 2>/dev/null)
PT_JQLESS_RC=$?
check "output unaffected by jq being absent from PATH" "$PT_JQLESS_OUT" "$BASELINE_OUT"
check "output unaffected by jq being absent from PATH (exit 0)" "$PT_JQLESS_RC" "0"

# --- Invariant: pure read, never writes anything ------------------------------

tree_digest() { find "$1" -type f -exec md5sum {} \; 2>/dev/null | sed "s#$1#<ROOT>#" | sort; }
DIGEST_BEFORE=$(tree_digest "$HOME_A")
HOME="$HOME_A" run_pt "$CWD_A"
DIGEST_AFTER=$(tree_digest "$HOME_A")
check "fake \$HOME tree unchanged after call (read-only)" "$DIGEST_AFTER" "$DIGEST_BEFORE"
check "fake \$HOME tree unchanged after call (exit 0)" "$PT_RC" "0"

# --- Invariant: deterministic given a fixed filesystem state -----------------

HOME="$HOME_A" run_pt "$CWD_A"
RERUN_OUT=$(cat "$PT_OUT")
check "deterministic check, first call (exit 0)" "$PT_RC" "0"
HOME="$HOME_A" run_pt "$CWD_A"
check "deterministic: repeated call on unchanged filesystem, same output" "$(cat "$PT_OUT")" "$RERUN_OUT"
check "deterministic: repeated call on unchanged filesystem (exit 0)" "$PT_RC" "0"

# Ties on identical mtimes: at minimum, both files must appear and repeated
# calls must agree with each other (stable within/across calls), even though
# the contract allows either relative order between the tied pair.
HOME_TIE="$TMPROOT/home-tie"
CWD_TIE="/tie/proj"
PROJ_DIR_TIE="$HOME_TIE/.claude/projects/$(sanitize "$CWD_TIE")"
mkdir -p "$PROJ_DIR_TIE"
touch -t 202601010000 "$PROJ_DIR_TIE/one.jsonl"
touch -t 202601010000 "$PROJ_DIR_TIE/two.jsonl"
HOME="$HOME_TIE" run_pt "$CWD_TIE"
TIE_FIRST=$(cat "$PT_OUT")
TIE_COUNT=$(wc -l < "$PT_OUT" | tr -d ' ')
check "tied mtimes: both files present" "$TIE_COUNT" "2"
HOME="$HOME_TIE" run_pt "$CWD_TIE"
check "tied mtimes: order stable across repeated calls" "$(cat "$PT_OUT")" "$TIE_FIRST"

# --- Invariant: no globals mutated beyond its own locals ---------------------

compgen -v | sort > "$TMPROOT/pt_vars_before"
HOME="$HOME_A" activity_prior_transcripts "$CWD_A" > "$TMPROOT/pt_leak_out" 2>/dev/null
echo $? > "$TMPROOT/pt_leak_rc"
compgen -v | sort > "$TMPROOT/pt_vars_after"
check "no global variables leak into the caller's shell (activity_prior_transcripts)" \
  "$(cat "$TMPROOT/pt_vars_after")" "$(cat "$TMPROOT/pt_vars_before")"
check "no global variables leak into the caller's shell (activity_prior_transcripts, exit 0)" "$(cat "$TMPROOT/pt_leak_rc")" "0"

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit $FAILED
