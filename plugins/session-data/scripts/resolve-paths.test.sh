#!/bin/bash
# Functional test for resolve-paths.sh (Contract: B01 resolve-paths, docblock
# in resolve-paths.sh). Run: bash plugins/session-data/scripts/resolve-paths.test.sh
# (exits non-zero on failure)
#
# Builds a fake $HOME/.claude/ tree matching the REAL on-disk conventions of
# Claude Code (verified by inspecting a live ~/.claude/ during test
# authoring, since the plan doc was not available in this worktree):
#   - Project dir:        $HOME/.claude/projects/<PWD with / -> ->
#   - Main transcript:     <project-dir>/<session-id>.jsonl
#   - Subagent transcripts: <project-dir>/<session-id>/subagents/*.jsonl
#   - File-history:        $HOME/.claude/file-history/<session-id>/*
#   - Session metadata:    $HOME/.claude/sessions/<CLAUDE_PID>.json
#   - Never-surface files: $HOME/.claude/daemon/roster.json,
#                           $HOME/.claude/.credentials.json
#
# Runs the real script against controlled env vars and a real (but
# temporary) cwd via `cd`, so both $PWD and `pwd` agree. Never touches the
# invoking user's real $HOME.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/resolve-paths.sh"

TMPROOT=$(mktemp -d)
STDOUT="$TMPROOT/stdout"
STDERR="$TMPROOT/stderr"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}
check_true() { # label condition-result(yes/no)
  check "$1" "$2" "yes"
}

# sanitize <path> -> path with every "/" replaced by "-" (the contract's
# project-directory derivation rule)
sanitize() { printf '%s' "$1" | sed 's#/#-#g'; }

# run_script <cwd> <home|__unset__> <session_id|__unset__> <pid|__unset__>
# Runs the script with a real `cd` into <cwd> (so both $PWD and `pwd` see
# it) and exactly the requested env vars present/absent. Sets $RC; stdout
# and stderr land in $STDOUT / $STDERR.
run_script() {
  local cwd="$1" home="$2" sid="$3" pid="$4"
  local unset_flags=() assign=()
  if [[ "$home" == "__unset__" ]]; then unset_flags+=(-u HOME); else assign+=("HOME=$home"); fi
  if [[ "$sid" == "__unset__" ]]; then unset_flags+=(-u CLAUDE_CODE_SESSION_ID); else assign+=("CLAUDE_CODE_SESSION_ID=$sid"); fi
  if [[ "$pid" == "__unset__" ]]; then unset_flags+=(-u CLAUDE_PID); else assign+=("CLAUDE_PID=$pid"); fi
  (cd "$cwd" && env "${unset_flags[@]}" "${assign[@]}" bash "$SCRIPT" >"$STDOUT" 2>"$STDERR")
  RC=$?
}

# tree_digest <dir> -> a stable content+path fingerprint of every file under
# <dir>, used to prove read-only behavior (before/after must be identical).
tree_digest() {
  find "$1" -type f -exec md5sum {} \; 2>/dev/null | sed "s#$1#<ROOT>#" | sort
}

# ============================================================================
# Fixture A: full "happy path" — every category present, plus the two
# never-surface files that must never leak into output regardless.
# ============================================================================

HOME_A="$TMPROOT/home-a"
CWD_A="$TMPROOT/cwd-a/some/project"
mkdir -p "$CWD_A"
SID_A="11111111-1111-1111-1111-111111111111"
PID_A="424242"

PROJ_DIR_A="$HOME_A/.claude/projects/$(sanitize "$CWD_A")"
mkdir -p "$PROJ_DIR_A"
printf '{"type":"user","message":{"content":"hi"}}\n' > "$PROJ_DIR_A/$SID_A.jsonl"

SUBAGENTS_A="$PROJ_DIR_A/$SID_A/subagents"
mkdir -p "$SUBAGENTS_A"
printf '{"type":"assistant"}\n' > "$SUBAGENTS_A/agent-aaa.jsonl"
printf '{"type":"assistant"}\n' > "$SUBAGENTS_A/agent-bbb.jsonl"
printf '{"type":"assistant"}\n' > "$SUBAGENTS_A/agent-ccc.jsonl"
printf '{}' > "$SUBAGENTS_A/agent-aaa.meta.json"  # must NOT count toward the .jsonl count

FILEHIST_A="$HOME_A/.claude/file-history/$SID_A"
mkdir -p "$FILEHIST_A"
printf 'v1-snapshot' > "$FILEHIST_A/abc123@v1"
printf 'v2-snapshot' > "$FILEHIST_A/abc123@v2"

mkdir -p "$HOME_A/.claude/sessions"
printf '{"pid":%s,"sessionId":"%s"}' "$PID_A" "$SID_A" > "$HOME_A/.claude/sessions/$PID_A.json"

mkdir -p "$HOME_A/.claude/daemon"
printf '{"secret":"do-not-leak"}' > "$HOME_A/.claude/daemon/roster.json"
printf '{"token":"do-not-leak"}' > "$HOME_A/.claude/.credentials.json"

DIGEST_BEFORE=$(tree_digest "$HOME_A")

run_script "$CWD_A" "$HOME_A" "$SID_A" "$PID_A"
OUT_A=$(cat "$STDOUT")
ERR_A=$(cat "$STDERR")
SANITIZED_A=$(sanitize "$CWD_A")

echo "--- Fixture A: full happy path ---"
check "happy path exits 0" "$RC" 0

# --- Behavior: derives project dir from $PWD (/ -> -) -----------------------
check_true "output contains session id" \
  "$(grep -qF -- "$SID_A" <<<"$OUT_A" && echo yes || echo no)"
check_true "output contains derived project directory ($SANITIZED_A)" \
  "$(grep -qF -- "$SANITIZED_A" <<<"$OUT_A" && echo yes || echo no)"
check_true "no doubled leading dash in derived project dir (prepend-dash bug)" \
  "$(grep -qF -- "-$SANITIZED_A" <<<"$OUT_A" && echo no || echo yes)"

# --- Behavior: locates + reports the main transcript JSONL -------------------
check_true "output contains absolute main-transcript path" \
  "$(grep -qF -- "$PROJ_DIR_A/$SID_A.jsonl" <<<"$OUT_A" && echo yes || echo no)"

# --- Behavior: discovers subagent transcripts, with accurate .jsonl count ---
check_true "output contains absolute subagents dir path" \
  "$(grep -qF -- "$SUBAGENTS_A" <<<"$OUT_A" && echo yes || echo no)"
SUBAGENT_LINES=$(grep -i 'subagent' <<<"$OUT_A")
check_true "subagent .jsonl count reported as 3 (meta.json excluded)" \
  "$(grep -qE '(^|[^0-9])3([^0-9]|$)' <<<"$SUBAGENT_LINES" && echo yes || echo no)"
check_true "subagent count does not count the .meta.json file (not 4)" \
  "$(grep -qE '(^|[^0-9])4([^0-9]|$)' <<<"$SUBAGENT_LINES" && echo no || echo yes)"

# --- Behavior: discovers file-history, with accurate file count -------------
check_true "output contains absolute file-history dir path" \
  "$(grep -qF -- "$FILEHIST_A" <<<"$OUT_A" && echo yes || echo no)"
FILEHIST_LINES=$(grep -i 'file.history' <<<"$OUT_A")
check_true "file-history count reported as 2" \
  "$(grep -qE '(^|[^0-9])2([^0-9]|$)' <<<"$FILEHIST_LINES" && echo yes || echo no)"

# --- Behavior: discovers session metadata via CLAUDE_PID ---------------------
check_true "output contains absolute session-metadata path" \
  "$(grep -qF -- "$HOME_A/.claude/sessions/$PID_A.json" <<<"$OUT_A" && echo yes || echo no)"

# --- Behavior: reports existence (none of the present categories say
# "[not found]" since everything in fixture A exists) ------------------------
check "no '[not found]' anywhere when every category exists" \
  "$(grep -c -- '\[not found\]' <<<"$OUT_A")" 0

# --- Invariant: sensitivity annotation present per applicable category
# (transcript, subagent transcripts, file-history = 3 categories) ------------
SENSIT_COUNT=$(grep -oi 'sensit[a-z]*' <<<"$OUT_A" | wc -l | tr -d ' ')
check_true "sensitivity annotation appears at least 3 times (one per applicable category)" \
  "$([[ "$SENSIT_COUNT" -ge 3 ]] && echo yes || echo no)"

# --- Invariant: known-bad paths never surface, even though they exist -------
check_true "roster.json never appears in output" \
  "$(grep -qi -- 'roster.json' <<<"$OUT_A" && echo no || echo yes)"
check_true "'daemon' path never appears in output" \
  "$(grep -qF -- "$HOME_A/.claude/daemon" <<<"$OUT_A" && echo no || echo yes)"
check_true ".credentials.json never appears in output" \
  "$(grep -qi -- '.credentials.json' <<<"$OUT_A" && echo no || echo yes)"

# --- Invariant: all paths absolute (no bare ~/ shorthand) --------------------
check_true "no '~/' shorthand paths in output" \
  "$(grep -qF -- '~/' <<<"$OUT_A" && echo no || echo yes)"

# --- Invariant: read-only — never creates/modifies/deletes any file ---------
DIGEST_AFTER=$(tree_digest "$HOME_A")
check "fake \$HOME tree unchanged after running (read-only)" "$DIGEST_AFTER" "$DIGEST_BEFORE"

# --- Invariant: deterministic output for identical env/filesystem state -----
run_script "$CWD_A" "$HOME_A" "$SID_A" "$PID_A"
OUT_A_RERUN=$(cat "$STDOUT")
check "output is deterministic across repeated runs" "$OUT_A_RERUN" "$OUT_A"

echo ""
echo "--- Fixture B: nothing exists yet (session id set, PID unset) ---"
# ============================================================================
# Fixture B: CLAUDE_CODE_SESSION_ID set but nothing on disk matches it yet,
# and CLAUDE_PID is unset. Covers:
#   - missing paths -> "[not found]", exit 0 (not an error)
#   - no subagent transcripts (dir absent)
#   - no file-history (dir absent)
#   - CLAUDE_PID unset -> session-metadata section skipped, not an error
# ============================================================================

HOME_B="$TMPROOT/home-b"
CWD_B="$TMPROOT/cwd-b/proj"
mkdir -p "$HOME_B/.claude" "$CWD_B"
SID_B="22222222-2222-2222-2222-222222222222"

run_script "$CWD_B" "$HOME_B" "$SID_B" "__unset__"
OUT_B=$(cat "$STDOUT")

check "all-missing + no PID still exits 0 (not an error)" "$RC" 0
NOTFOUND_COUNT=$(grep -c -- '\[not found\]' <<<"$OUT_B")
check_true "at least 3 '[not found]' entries (transcript, subagents, file-history)" \
  "$([[ "$NOTFOUND_COUNT" -ge 3 ]] && echo yes || echo no)"
check_true "no malformed session-metadata path when CLAUDE_PID is unset (no 'sessions/.json')" \
  "$(grep -qF -- 'sessions/.json' <<<"$OUT_B" && echo no || echo yes)"

echo ""
echo "--- Fixture C: everything present EXCEPT the main transcript JSONL ---"
# ============================================================================
# Fixture C: isolates "CLAUDE_CODE_SESSION_ID is set but the JSONL doesn't
# exist yet" from wholesale absence — subagents, file-history, and session
# metadata all exist and must still be correctly reported as found while
# only the main transcript is "[not found]".
# ============================================================================

HOME_C="$TMPROOT/home-c"
CWD_C="$TMPROOT/cwd-c/proj"
mkdir -p "$CWD_C"
SID_C="33333333-3333-3333-3333-333333333333"
PID_C="777"

PROJ_DIR_C="$HOME_C/.claude/projects/$(sanitize "$CWD_C")"
mkdir -p "$PROJ_DIR_C/$SID_C/subagents"
printf 'x' > "$PROJ_DIR_C/$SID_C/subagents/agent-only.jsonl"
mkdir -p "$HOME_C/.claude/file-history/$SID_C"
printf 'x' > "$HOME_C/.claude/file-history/$SID_C/snap@v1"
mkdir -p "$HOME_C/.claude/sessions"
printf '{}' > "$HOME_C/.claude/sessions/$PID_C.json"
# Deliberately no $PROJ_DIR_C/$SID_C.jsonl

run_script "$CWD_C" "$HOME_C" "$SID_C" "$PID_C"
OUT_C=$(cat "$STDOUT")

check "session id set but jsonl missing still exits 0" "$RC" 0
check_true "main transcript reported '[not found]' specifically" \
  "$(grep -qF -- "$PROJ_DIR_C/$SID_C.jsonl" <<<"$OUT_C" && grep -q -- '\[not found\]' <<<"$OUT_C" && echo yes || echo no)"
check_true "subagents dir still reported present despite missing main transcript" \
  "$(grep -qF -- "$PROJ_DIR_C/$SID_C/subagents" <<<"$OUT_C" && echo yes || echo no)"
check_true "file-history still reported present despite missing main transcript" \
  "$(grep -qF -- "$HOME_C/.claude/file-history/$SID_C" <<<"$OUT_C" && echo yes || echo no)"
check_true "session metadata still reported present despite missing main transcript" \
  "$(grep -qF -- "$HOME_C/.claude/sessions/$PID_C.json" <<<"$OUT_C" && echo yes || echo no)"

echo ""
echo "--- Fixture D: CLAUDE_CODE_SESSION_ID not set -----------------------------"
# ============================================================================
# Error: CLAUDE_CODE_SESSION_ID not set -> stderr diagnostic, exit 1
# ============================================================================

HOME_D="$TMPROOT/home-d"
CWD_D="$TMPROOT/cwd-d/proj"
mkdir -p "$HOME_D/.claude" "$CWD_D"

run_script "$CWD_D" "$HOME_D" "__unset__" "__unset__"
ERR_D=$(cat "$STDERR")

check "missing CLAUDE_CODE_SESSION_ID exits 1" "$RC" 1
check_true "missing CLAUDE_CODE_SESSION_ID writes a stderr diagnostic" \
  "$([[ -n "$ERR_D" ]] && echo yes || echo no)"
check_true "diagnostic names the missing var (CLAUDE_CODE_SESSION_ID)" \
  "$(grep -qF -- 'CLAUDE_CODE_SESSION_ID' <<<"$ERR_D" && echo yes || echo no)"

echo ""
echo "--- Fixture E: HOME not set -------------------------------------------"
# ============================================================================
# Error: HOME not set -> stderr diagnostic, exit 1
# ============================================================================

CWD_E="$TMPROOT/cwd-e/proj"
mkdir -p "$CWD_E"
SID_E="44444444-4444-4444-4444-444444444444"

run_script "$CWD_E" "__unset__" "$SID_E" "__unset__"
ERR_E=$(cat "$STDERR")

check "missing HOME exits 1" "$RC" 1
check_true "missing HOME writes a stderr diagnostic" \
  "$([[ -n "$ERR_E" ]] && echo yes || echo no)"
check_true "diagnostic names the missing var (HOME)" \
  "$(grep -qF -- 'HOME' <<<"$ERR_E" && echo yes || echo no)"

echo ""
echo "--- Fixture F: PWD with spaces -----------------------------------------"
# ============================================================================
# Edge case: PWD contains spaces — paths must not break.
# ============================================================================

HOME_F="$TMPROOT/home-f"
CWD_F="$TMPROOT/cwd f/my project"
mkdir -p "$HOME_F/.claude" "$CWD_F"
SID_F="55555555-5555-5555-5555-555555555555"

run_script "$CWD_F" "$HOME_F" "$SID_F" "__unset__"
OUT_F=$(cat "$STDOUT")

check "PWD with spaces exits 0" "$RC" 0
check_true "PWD with spaces preserved (not word-split/truncated) in derived dir" \
  "$(grep -qF -- 'cwd f-my project' <<<"$OUT_F" && echo yes || echo no)"

echo ""
if [[ "$FAILED" == "0" ]]; then
  rm -rf "$TMPROOT"
  echo "ALL PASS"
else
  echo "FAILURES — test artifacts preserved at $TMPROOT"
fi
exit $FAILED
