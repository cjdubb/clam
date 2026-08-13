#!/bin/bash
# Functional test for capture.sh — the /make-progress capture hook contract
# (Contract: B01 — Capture hook). Run: bash plugins/make-progress/scripts/capture.test.sh
# (exits non-zero on failure)
#
# Feeds synthetic UserPromptSubmit stdin JSON to the hook and asserts on the
# capture dir contents, the exit code, and — CRITICAL — that stdout is empty
# on EVERY path (UserPromptSubmit stdout is injected into conversation
# context). MAKE_PROGRESS_CAPTURE_ROOT points captures at a temp dir so the
# real ~/.claude/make-progress-captures is untouched. A PATH shim pins `date`
# to a fixed timestamp so the collision case is deterministic. No network
# calls are made by this test harness itself except a deliberately-unreachable
# proxy used to prove the hook doesn't either.
#
# This version of the hook GENERALIZES state-file capture: instead of a
# hardcoded list of filenames (TODO.md, PLAN.md, ...), it must capture ALL
# regular files at depth 1 in <cwd>/.local/, and instead of a single
# hardcoded CHUNK-SIGNALS/ directory, it must list ALL subdirectories of
# .local/ as <dirname>-listing.txt. The fixtures below deliberately use
# non-standard file/directory names to prove the hook isn't special-casing
# a fixed list.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/capture.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck disable=SC1091  # sourced at runtime from the repo root
. "$REPO_ROOT/scripts/lib/test-portability.sh"

# Absolute bash: a shim PATH may not contain the platform's bash directory
# (bash lives in /bin on macOS), so a bare `bash` there would exit 127.
BASH_BIN="${BASH:-/bin/bash}"

# Real `date`, resolved BEFORE any PATH override: /usr/bin/date does not
# exist on macOS (the real one is /bin/date), so nothing may hardcode it.
REAL_DATE="$(command -v date)"

TMPROOT=$(mktemp -d)
ROOT="$TMPROOT/captures"
export MAKE_PROGRESS_CAPTURE_ROOT="$ROOT"

# --- date shim: fixed UTC timestamp so capture dir names are predictable ----
FIXED_TS="20260710T120000Z"
BIN="$TMPROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/date" <<EOF
#!/bin/bash
case "\$*" in
  *"+%Y%m%dT%H%M%SZ"*) echo "$FIXED_TS" ;;
  *) exec "$REAL_DATE" "\$@" ;;
esac
EOF
chmod +x "$BIN/date"
export PATH="$BIN:$PATH"

# --- helper: build a PATH dir that has everything EXCEPT one named command --
# Farms the whole real PATH (not just /usr/bin — bash lives in /bin on macOS
# and jq typically under Homebrew), drops $1, then re-points `date` at our
# fixed shim so timestamp determinism survives the substitution. Used to
# simulate "jq not on PATH" and "stat unavailable" without touching real
# permissions.
build_path_without() { # cmd -> prints new PATH dir
  local cmd="$1"
  local out="$TMPROOT/bin-no-$cmd"
  mkdir -p "$out"
  tp_shim_path "$out" --remove "$cmd" > /dev/null
  ln -sf "$BIN/date" "$out/date"
  echo "$out"
}
NOJQBIN=$(build_path_without jq)
NOSTATBIN=$(build_path_without stat)

# --- fixture worktree with generalized .local/ state, git repo, transcript --
WT="$TMPROOT/wt"
mkdir -p "$WT/.local/plans" "$WT/.local/scratch-notes" "$WT/.claude"

# Depth-1 regular files with deliberately NON-standard names (not TODO.md /
# PLAN.md / MODE / IMPLEMENTATION-PLAN.md / INDEPENDENCE) to prove the hook
# copies ALL regular files, not a hardcoded list.
printf 'State: In Progress\n' > "$WT/.local/TODO.md"
printf 'arbitrary notes, not on any legacy hardcoded list\n' > "$WT/.local/zzz-arbitrary-note.txt"
printf 'snapshot-blob\n' > "$WT/.local/config.snapshot"

# Two differently-named subdirectories (neither called CHUNK-SIGNALS) — both
# must produce their own <dirname>-listing.txt, proving the listing is
# generic, not hardcoded to one directory name. Contents must NOT be
# recursively copied to the capture dir root.
printf '# plan A\n' > "$WT/.local/plans/plan-a.md"
printf 'draft\n' > "$WT/.local/scratch-notes/draft.txt"

printf '{"tasks":[{"prompt":"watch PR #7"}]}\n' > "$WT/.claude/scheduled_tasks.json"

# Git repo: 4 commits (so "last 3" excludes the 1st) + an untracked marker +
# enough untracked filler files to prove the porcelain status is bounded to
# the first 100 lines.
git -C "$WT" init -q --initial-branch=main
git -C "$WT" config user.email test@example.com
git -C "$WT" config user.name "Test User"
git -C "$WT" config commit.gpgsign false
for i in 1 2 3 4; do
  printf 'commit %s\n' "$i" > "$WT/file$i.txt"
  git -C "$WT" add "file$i.txt"
  git -C "$WT" commit -q -m "commit $i"
done
printf 'untracked\n' > "$WT/untracked-marker.txt"
for i in $(seq 1 150); do
  printf 'x\n' > "$WT/junk-$(printf '%03d' "$i").txt"
done

# Transcript: 25 assistant messages interleaved with user messages and one
# malformed line — the tail must contain exactly the LAST 20 assistant rows,
# and the malformed line must never surface.
TRANSCRIPT="$TMPROOT/transcript.jsonl"
: > "$TRANSCRIPT"
for i in $(seq 1 25); do
  printf '{"type":"user","message":{"content":"u%s"}}\n' "$i" >> "$TRANSCRIPT"
  printf '{"type":"assistant","message":{"content":"a%s"}}\n' "$i" >> "$TRANSCRIPT"
done
echo 'not json {{{' >> "$TRANSCRIPT"

# Worktree with no .local/ at all
WT_BARE="$TMPROOT/wt-bare"
mkdir -p "$WT_BARE"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

STDOUT="$TMPROOT/stdout"

# run_hook <prompt> <cwd> <transcript|__none__> [session_id]
#   -> $RC set, stdout in $STDOUT. session_id defaults to "test-session";
#   pass an explicit "" for the empty-session cases.
run_hook() {
  local sid="${4-test-session}"
  local json
  if [[ "$3" == "__none__" ]]; then
    json=$(jq -n --arg p "$1" --arg cwd "$2" --arg s "$sid" \
      '{prompt: $p, cwd: $cwd, session_id: $s}')
  else
    json=$(jq -n --arg p "$1" --arg cwd "$2" --arg t "$3" --arg s "$sid" \
      '{prompt: $p, cwd: $cwd, session_id: $s, transcript_path: $t}')
  fi
  printf '%s' "$json" | bash "$HOOK" > "$STDOUT" 2>/dev/null
  RC=$?
}

assert_stdout_empty() { # label
  check "$1: stdout empty" "$(wc -c < "$STDOUT" | tr -d ' ')" 0
}

# --- non-matching prompt: exit 0, no dir, no stdout --------------------------
run_hook "please continue the refactor" "$WT" "$TRANSCRIPT"
check "non-matching prompt exits 0" "$RC" 0
check "non-matching prompt creates no capture root" "$([[ -e "$ROOT" ]] && echo yes || echo no)" no
assert_stdout_empty "non-matching prompt"

# --- jq not on PATH (hook mode): exit 0, no writes, no stdout ----------------
rm -rf "$ROOT"
json=$(jq -n --arg p "/make-progress" --arg cwd "$WT" --arg s "test-session" \
  '{prompt: $p, cwd: $cwd, session_id: $s}')
printf '%s' "$json" | PATH="$NOJQBIN" "$BASH_BIN" "$HOOK" > "$STDOUT" 2>/dev/null
RC=$?
check "missing jq exits 0" "$RC" 0
check "missing jq creates no capture root" "$([[ -e "$ROOT" ]] && echo yes || echo no)" no
assert_stdout_empty "missing jq"

# --- matching prompt: full capture -------------------------------------------
rm -rf "$ROOT"
run_hook "/make-progress" "$WT" "$TRANSCRIPT"
DIR="$ROOT/$FIXED_TS-wt"
check "matching prompt exits 0" "$RC" 0
check "capture dir created" "$([[ -d "$DIR" ]] && echo yes)" yes
assert_stdout_empty "matching prompt"
check "meta.txt written" "$([[ -f "$DIR/meta.txt" ]] && echo yes)" yes
grep -q "timestamp: $FIXED_TS" "$DIR/meta.txt";      check "meta records timestamp" "$?" 0
grep -q "cwd: $WT" "$DIR/meta.txt";                 check "meta records cwd" "$?" 0
grep -q "session_id: test-session" "$DIR/meta.txt"; check "meta records session_id" "$?" 0
grep -q "worktree: wt" "$DIR/meta.txt";             check "meta records worktree" "$?" 0
grep -q "mode: hook" "$DIR/meta.txt";               check "meta records hook mode" "$?" 0

check "transcript tail has exactly 20 lines" "$(wc -l < "$DIR/transcript-tail.jsonl" | tr -d ' ')" 20
check "tail is assistant-only" \
  "$(jq -r 'select(.type != "assistant") | .type' "$DIR/transcript-tail.jsonl" | wc -l | tr -d ' ')" 0
check "tail keeps the newest assistant message" \
  "$(tail -1 "$DIR/transcript-tail.jsonl" | jq -r '.message.content')" "a25"
check "tail starts at the 6th-from-last assistant batch" \
  "$(head -1 "$DIR/transcript-tail.jsonl" | jq -r '.message.content')" "a6"
BAD_LINES=0
while IFS= read -r line; do
  echo "$line" | jq -e . >/dev/null 2>&1 || BAD_LINES=$((BAD_LINES + 1))
done < "$DIR/transcript-tail.jsonl"
check "malformed transcript line never surfaces in tail (all lines valid JSON)" "$BAD_LINES" 0

# generalized state-file capture: arbitrary basenames, not a hardcoded list
check "TODO.md copied" "$(cat "$DIR/TODO.md")" "State: In Progress"
check "arbitrary-named state file copied" "$(cat "$DIR/zzz-arbitrary-note.txt")" \
  "arbitrary notes, not on any legacy hardcoded list"
check "non-markdown-named state file copied" "$(cat "$DIR/config.snapshot")" "snapshot-blob"
check "absent legacy hardcoded name skipped" \
  "$([[ -e "$DIR/IMPLEMENTATION-PLAN.md" ]] && echo yes || echo no)" no

# generalized subdirectory listing: EVERY subdir gets its own listing, and
# none are recursively copied.
grep -q "plan-a.md" "$DIR/plans-listing.txt";                check "plans/ subdir listed generically" "$?" 0
grep -q "draft.txt" "$DIR/scratch-notes-listing.txt";        check "scratch-notes/ subdir listed generically" "$?" 0
check "plans/ not recursively copied as a dir" "$([[ -d "$DIR/plans" ]] && echo yes || echo no)" no
check "plans/ contents not copied to capture root" \
  "$([[ -e "$DIR/plan-a.md" ]] && echo yes || echo no)" no
check "scratch-notes/ contents not copied to capture root" \
  "$([[ -e "$DIR/draft.txt" ]] && echo yes || echo no)" no

# git-state.txt: branch, bounded status, last 3 commits
grep -q "branch: main" "$DIR/git-state.txt";  check "git-state records branch" "$?" 0
grep -q "commit 4" "$DIR/git-state.txt";      check "git-state last-3 includes newest commit" "$?" 0
grep -q "commit 3" "$DIR/git-state.txt";      check "git-state last-3 includes 2nd commit" "$?" 0
grep -q "commit 2" "$DIR/git-state.txt";      check "git-state last-3 includes 3rd commit" "$?" 0
if grep -q "commit 1" "$DIR/git-state.txt"; then FOUND_C1=yes; else FOUND_C1=no; fi
check "git-state excludes the 4th-from-last commit" "$FOUND_C1" no
check "git-state status bounded to first 100 lines" \
  "$(grep -c '^?? ' "$DIR/git-state.txt")" 100

grep -q "watch PR #7" "$DIR/crons.txt"; check "scheduled tasks copied" "$?" 0
check "prompt.txt written verbatim" "$(cat "$DIR/prompt.txt")" "/make-progress"

# --- dedupe: same-session re-fire inside the window is SKIPPED -----------------
run_hook "/make-progress" "$WT" "$TRANSCRIPT"
check "same-session re-fire exits 0" "$RC" 0
check "same-session re-fire creates no -2 dir" "$([[ -e "$DIR-2" ]] && echo yes || echo no)" no
check "same-session re-fire leaves exactly one dir" "$(ls -d "$ROOT"/* 2>/dev/null | wc -l | tr -d ' ')" 1
assert_stdout_empty "same-session re-fire"

# --- the hook does not special-case DECISION.md: a previous capture that
# already has DECISION.md (e.g. deduped-into by an earlier invocation) still
# dedupes a same-session re-fire exactly as if DECISION.md were absent.
printf -- '---\nrow_matched: none\n---\n' > "$DIR/DECISION.md"
run_hook "/make-progress" "$WT" "$TRANSCRIPT"
check "same-session re-fire still deduped when newest dir has DECISION.md" "$RC" 0
check "DECISION.md present does not trigger a fresh capture" \
  "$([[ -e "$DIR-2" ]] && echo yes || echo no)" no
assert_stdout_empty "re-fire with DECISION.md present"

# --- collision: same second, DIFFERENT session → -2 suffix (no dedupe) ---------
run_hook "/make-progress" "$WT" "$TRANSCRIPT" "other-session"
check "different-session collision exits 0" "$RC" 0
check "different-session collision gets -2 suffix" "$([[ -d "$DIR-2" ]] && echo yes)" yes
assert_stdout_empty "different-session collision"

# --- dedupe window expiry: MAKE_PROGRESS_DEDUPE_SECS=0 → capture again ---------
# Newest dir is now $DIR-2 (session other-session); with a zero window the
# same-session re-fire is no longer inside it and must capture (-3 suffix).
printf '%s' "$(jq -n --arg p "/make-progress" --arg cwd "$WT" --arg t "$TRANSCRIPT" \
  '{prompt:$p, cwd:$cwd, session_id:"other-session", transcript_path:$t}')" \
  | MAKE_PROGRESS_DEDUPE_SECS=0 bash "$HOOK" > "$STDOUT" 2>/dev/null
check "expired-window re-fire exits 0" "$?" 0
check "expired-window re-fire captures again (-3 suffix)" "$([[ -d "$DIR-3" ]] && echo yes)" yes
assert_stdout_empty "expired window"

# --- stat unavailable (simulated failure): dedupe falls back to "capture
# anyway" rather than skipping or erroring. Newest dir is $DIR-3
# (session other-session, just created above); a same-session re-fire for
# "other-session" would normally dedupe, but with `stat` removed from PATH
# neither birth time nor mtime can be read, so age is unknown and the hook
# must capture rather than risk losing data.
printf '%s' "$(jq -n --arg p "/make-progress" --arg cwd "$WT" --arg t "$TRANSCRIPT" \
  '{prompt:$p, cwd:$cwd, session_id:"other-session", transcript_path:$t}')" \
  | PATH="$NOSTATBIN" "$BASH_BIN" "$HOOK" > "$STDOUT" 2>/dev/null
check "stat-unavailable re-fire exits 0" "$?" 0
check "stat-unavailable re-fire captures anyway (-4 suffix)" "$([[ -d "$DIR-4" ]] && echo yes)" yes
assert_stdout_empty "stat unavailable"

# --- empty session_id never dedupes --------------------------------------------
rm -rf "$ROOT"
run_hook "/make-progress" "$WT" "$TRANSCRIPT" ""
check "empty-session first fire creates dir" "$([[ -d "$DIR" ]] && echo yes)" yes
run_hook "/make-progress" "$WT" "$TRANSCRIPT" ""
check "empty-session re-fire exits 0" "$RC" 0
check "empty-session re-fire still captures (-2 suffix)" "$([[ -d "$DIR-2" ]] && echo yes)" yes
assert_stdout_empty "empty-session re-fire"

# --- dedupe is anchored per-worktree: a wt-bare dir never dedupes wt ------------
rm -rf "$ROOT"
run_hook "/make-progress" "$WT_BARE" "__none__"
check "substring-sibling worktree dir created" "$([[ -d "$ROOT/$FIXED_TS-wt-bare" ]] && echo yes)" yes
run_hook "/make-progress" "$WT" "$TRANSCRIPT"
check "wt fire not deduped by wt-bare dir" "$([[ -d "$DIR" ]] && echo yes)" yes
assert_stdout_empty "cross-worktree dedupe"

# --- prompt merely mentioning /make-progress fires too (accepted false positive)
rm -rf "$ROOT"
run_hook "what does /make-progress do?" "$WT" "$TRANSCRIPT"
check "prose mention still captures" "$([[ -d "$DIR" ]] && echo yes)" yes
assert_stdout_empty "prose mention"

# --- missing transcript_path: dir created without tail ------------------------
rm -rf "$ROOT"
run_hook "/make-progress" "$WT" "__none__"
check "missing transcript exits 0" "$RC" 0
check "dir created without transcript_path" "$([[ -d "$DIR" ]] && echo yes)" yes
check "no tail without transcript_path" "$([[ -e "$DIR/transcript-tail.jsonl" ]] && echo yes || echo no)" no
check "state still copied without transcript" "$([[ -f "$DIR/TODO.md" ]] && echo yes)" yes
assert_stdout_empty "missing transcript"

# --- unreadable/nonexistent transcript: same as missing -----------------------
rm -rf "$ROOT"
run_hook "/make-progress" "$WT" "$TMPROOT/does-not-exist.jsonl"
check "nonexistent transcript exits 0" "$RC" 0
check "dir created despite bad transcript" "$([[ -d "$DIR" ]] && echo yes)" yes
check "no tail from bad transcript" "$([[ -e "$DIR/transcript-tail.jsonl" ]] && echo yes || echo no)" no
assert_stdout_empty "nonexistent transcript"

# --- empty/zero-byte transcript: no misleading zero-byte tail file ------------
rm -rf "$ROOT"
EMPTY_TRANSCRIPT="$TMPROOT/empty-transcript.jsonl"
: > "$EMPTY_TRANSCRIPT"
run_hook "/make-progress" "$WT" "$EMPTY_TRANSCRIPT"
check "empty transcript exits 0" "$RC" 0
check "dir created for empty transcript" "$([[ -d "$DIR" ]] && echo yes)" yes
check "no tail file for empty transcript" "$([[ -e "$DIR/transcript-tail.jsonl" ]] && echo yes || echo no)" no
assert_stdout_empty "empty transcript"

# --- cwd with no .local/: meta only, exit 0 -----------------------------------
rm -rf "$ROOT"
run_hook "/make-progress" "$WT_BARE" "__none__"
BARE_DIR="$ROOT/$FIXED_TS-wt-bare"
check "no-.local cwd exits 0" "$RC" 0
check "no-.local dir created" "$([[ -d "$BARE_DIR" ]] && echo yes)" yes
check "no-.local meta written" "$([[ -f "$BARE_DIR/meta.txt" ]] && echo yes)" yes
check "no-.local copies nothing" "$([[ -e "$BARE_DIR/TODO.md" ]] && echo yes || echo no)" no
assert_stdout_empty "no .local"

# --- size cap: oldest lines dropped first, newest kept ------------------------
rm -rf "$ROOT"
BIGT="$TMPROOT/big-transcript.jsonl"
: > "$BIGT"
for i in $(seq 1 5); do
  jq -nc --arg i "$i" '{type:"assistant", message:{content:("x" * 200), seq:$i}}' >> "$BIGT"
done
run_hook "/make-progress" "$WT" "$BIGT" # default cap: no truncation expected
check "under-cap tail keeps all 5 lines" "$(wc -l < "$DIR/transcript-tail.jsonl" | tr -d ' ')" 5
rm -rf "$ROOT"
# Cap sized to fit exactly 2 of the 5 (equal-length) lines.
LINE_BYTES=$(head -1 "$BIGT" | wc -c | tr -d ' ')
printf '%s' "$(jq -n --arg p "/make-progress" --arg cwd "$WT" --arg t "$BIGT" \
  '{prompt:$p, cwd:$cwd, session_id:"test-session", transcript_path:$t}')" \
  | MAKE_PROGRESS_TAIL_MAX_BYTES=$((2 * LINE_BYTES + 5)) bash "$HOOK" > "$STDOUT" 2>/dev/null
check "capped tail exits 0" "$?" 0
check "capped tail dropped oldest lines" "$(wc -l < "$DIR/transcript-tail.jsonl" | tr -d ' ')" 2
check "capped tail keeps the newest line" \
  "$(tail -1 "$DIR/transcript-tail.jsonl" | jq -r '.message.seq')" 5
assert_stdout_empty "capped tail"

# --- prompt.txt cap: oversized prompt truncated, capture otherwise intact ------
rm -rf "$ROOT"
PAD=$(head -c 70000 /dev/zero | tr '\0' x)
run_hook "/make-progress $PAD" "$WT" "$TRANSCRIPT"
check "oversized prompt exits 0" "$RC" 0
check "prompt.txt capped at default 64KB" "$(wc -c < "$DIR/prompt.txt" | tr -d ' ')" 65536
check "oversized prompt still captures state" "$([[ -f "$DIR/TODO.md" ]] && echo yes)" yes
assert_stdout_empty "oversized prompt"
rm -rf "$ROOT"
# Override cap sized to exactly the trigger phrase (14 bytes): the tail of the
# prompt must be cut, the head kept.
printf '%s' "$(jq -n --arg p "/make-progress plus trailing paste" --arg cwd "$WT" \
  '{prompt:$p, cwd:$cwd, session_id:"test-session"}')" \
  | MAKE_PROGRESS_PROMPT_MAX_BYTES=14 bash "$HOOK" > "$STDOUT" 2>/dev/null
check "small-cap prompt exits 0" "$?" 0
check "prompt.txt truncated to override cap" "$(cat "$DIR/prompt.txt")" "/make-progress"
assert_stdout_empty "small-cap prompt"

# --- --fallback mode: no stdin, cwd from $PWD, no transcript tail --------------
rm -rf "$ROOT"
(cd "$WT" && bash "$HOOK" --fallback > "$STDOUT" 2>/dev/null)
check "--fallback exits 0" "$?" 0
check "--fallback dir created" "$([[ -d "$DIR" ]] && echo yes)" yes
assert_stdout_empty "--fallback"
grep -q "mode: fallback" "$DIR/meta.txt"; check "--fallback meta records mode" "$?" 0
check "--fallback has no transcript tail" "$([[ -e "$DIR/transcript-tail.jsonl" ]] && echo yes || echo no)" no
check "--fallback writes no prompt.txt" "$([[ -e "$DIR/prompt.txt" ]] && echo yes || echo no)" no
check "--fallback copies .local state (generalized)" "$(cat "$DIR/zzz-arbitrary-note.txt")" \
  "arbitrary notes, not on any legacy hardcoded list"
grep -q "plan-a.md" "$DIR/plans-listing.txt"; check "--fallback lists subdirs generically" "$?" 0
grep -q "watch PR #7" "$DIR/crons.txt"; check "--fallback copies scheduled tasks" "$?" 0
grep -q "branch: main" "$DIR/git-state.txt"; check "--fallback captures git state" "$?" 0

# --- --fallback mode does not require jq (jq is a hook-mode-only input) --------
rm -rf "$ROOT"
(cd "$WT" && PATH="$NOJQBIN" "$BASH_BIN" "$HOOK" --fallback > "$STDOUT" 2>/dev/null)
check "--fallback without jq exits 0" "$?" 0
check "--fallback without jq still captures" "$([[ -d "$DIR" ]] && echo yes)" yes
assert_stdout_empty "--fallback without jq"

# --- default capture root respects $HOME when MAKE_PROGRESS_CAPTURE_ROOT is
# unset — exercised against a FAKE $HOME so the real ~/.claude is never
# touched.
FAKE_HOME="$TMPROOT/fakehome"
mkdir -p "$FAKE_HOME"
json=$(jq -n --arg p "/make-progress" --arg cwd "$WT" --arg s "test-session" \
  '{prompt: $p, cwd: $cwd, session_id: $s}')
printf '%s' "$json" | env -u MAKE_PROGRESS_CAPTURE_ROOT HOME="$FAKE_HOME" bash "$HOOK" \
  > "$STDOUT" 2>/dev/null
check "default capture root exits 0" "$?" 0
check "default capture root resolves under \$HOME/.claude" \
  "$([[ -d "$FAKE_HOME/.claude/make-progress-captures/$FIXED_TS-wt" ]] && echo yes)" yes
assert_stdout_empty "default capture root"

# --- no network calls / finishes well under the 5s hook timeout ---------------
# A deliberately-unreachable proxy is set on every proxy-respecting env var; a
# hook that made any network call through it would hang or error out slowly.
# Wrapping in `timeout` proves completion is fast regardless.
rm -rf "$ROOT"
json=$(jq -n --arg p "/make-progress" --arg cwd "$WT" --arg s "test-session" \
  '{prompt: $p, cwd: $cwd, session_id: $s}')
printf '%s' "$json" \
  | http_proxy="http://127.0.0.1:9/" https_proxy="http://127.0.0.1:9/" \
    ALL_PROXY="http://127.0.0.1:9/" timeout 4 bash "$HOOK" > "$STDOUT" 2>/dev/null
RC=$?
check "no-network fast completion: exits 0 (not a timeout)" "$RC" 0
check "no-network fast completion: capture dir created" "$([[ -d "$DIR" ]] && echo yes)" yes
assert_stdout_empty "no-network fast completion"

echo ""
if [[ "$FAILED" == "0" ]]; then
  rm -rf "$TMPROOT"
  echo "ALL PASS"
else
  # Preserve artifacts (captures, fixtures, stdout) for debugging failures.
  echo "FAILURES — test artifacts preserved at $TMPROOT"
fi
exit $FAILED
