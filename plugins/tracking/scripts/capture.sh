#!/bin/bash
# Contract: B02 — Capture hook (migrated from make-progress plugin)
#
# Behavior:
#   UserPromptSubmit hook that snapshots the session's state when the user's
#   prompt contains "/make-progress". Each snapshot becomes a labeled training
#   example: (stall state) → (correct next move, recorded later as DECISION.md
#   by the make-progress skill). Two modes: hook (default, called by Claude Code
#   on UserPromptSubmit with JSON on stdin) and fallback (--fallback, called by
#   the skill when the hook did not fire).
#
# Inputs:
#   Hook mode (default):
#     stdin — JSON with keys: prompt (string), transcript_path (string),
#             cwd (string), session_id (string). All optional; missing keys
#             treated as empty strings.
#     Requires: jq on PATH for JSON parsing; exits 0 immediately if absent.
#   Fallback mode (--fallback):
#     No stdin. cwd comes from $PWD. Transcript tail is unavailable and
#     skipped. prompt.txt is NOT written (the skill writes it instead).
#
# Outputs:
#   Creates a capture directory at:
#     <CAPTURE_ROOT>/<UTC %Y%m%dT%H%M%SZ>-<worktree-basename>/
#   with collision suffixes (-2, -3, ...) when the base name already exists.
#
#   Files written to the capture directory:
#     meta.txt              — timestamp, mode, cwd, session_id, worktree basename
#     prompt.txt            — verbatim triggering prompt (hook mode only),
#                             capped at PROMPT_MAX_BYTES (default 65536)
#     transcript-tail.jsonl — last 20 assistant messages from transcript_path,
#                             size-capped at TAIL_MAX_BYTES (default 204800),
#                             oldest lines dropped first (hook mode only,
#                             requires readable transcript_path)
#     <state files>         — copies of all regular files at depth 1 in
#                             <cwd>/.local/ (preserving basenames); plus an
#                             ls listing of each subdirectory of .local/ as
#                             <dirname>-listing.txt
#     git-state.txt         — branch name, bounded porcelain status (first 100
#                             lines), last 3 commits
#     crons.txt             — copy of <cwd>/.claude/scheduled_tasks.json if
#                             present
#
# Errors:
#   NEVER fails. Exit 0 on every path including: missing jq, unreadable
#   transcript, missing .local/, stat failures, mkdir failures, date failures.
#   Capture what exists, skip the rest.
#   stdout stays empty on every path (UserPromptSubmit stdout is injected into
#   conversation context). All diagnostics go to stderr.
#   No network calls (must finish well under 5s hook timeout).
#
# Invariants:
#   - stdout is always empty (enforced by exec >&2 at top of script)
#   - exit code is always 0
#   - no network calls, no subshells that call network
#   - captures are machine-local, never committed
#   - in hook mode, non-matching prompts (no "/make-progress" substring) exit
#     immediately after one jq parse + one string match — no filesystem writes
#   - collision suffixes ensure no data loss on same-second invocations
#
# Edge cases:
#   - Prompt does not contain /make-progress: fast-path exit 0, no writes
#   - jq not on PATH (hook mode): exit 0, no writes
#   - Duplicate hook fire: same non-empty session_id within DEDUPE_SECS
#     (default 60) of the newest capture for this worktree → exit 0, no writes.
#     Age is from directory birth time (clam_birth_epoch); falls back to mtime
#     if birth is 0/unavailable; any stat failure means "capture anyway".
#     Fallback mode and empty session_id never dedupe.
#   - Capture dir for this worktree already has DECISION.md (belongs to a
#     previous invocation the hook deduped into): treated as no match by the
#     skill, not by this hook (the hook does not check DECISION.md).
#   - .local/ does not exist: state-file capture silently skipped
#   - .local/ contains subdirectories: their contents listed in
#     <dirname>-listing.txt (not recursively copied)
#   - Empty or zero-byte transcript: transcript-tail.jsonl not created
#   - Malformed JSON lines in transcript: silently dropped (jq fromjson?)
#   - $PWD contains spaces: all paths quoted
#   - Worktree basename collision (e.g. "wt" vs "wt-bare"): anchored glob
#     patterns prevent cross-matching
#
# Overrides (for tests):
#   MAKE_PROGRESS_CAPTURE_ROOT     — capture root (default ~/.claude/make-progress-captures)
#   MAKE_PROGRESS_TAIL_MAX_BYTES   — transcript-tail size cap (default 204800)
#   MAKE_PROGRESS_PROMPT_MAX_BYTES — prompt.txt size cap (default 65536)
#   MAKE_PROGRESS_DEDUPE_SECS      — duplicate-fire dedupe window (default 60)

# Nothing may reach stdout in either mode (hook stdout becomes conversation
# context; the fallback path keeps the same contract for symmetry — the skill
# locates the capture dir as the oldest in the recent window, not by parsing
# output).
exec >&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/platform.sh"

CAPTURE_ROOT="${MAKE_PROGRESS_CAPTURE_ROOT:-$HOME/.claude/make-progress-captures}"
TAIL_MAX_BYTES="${MAKE_PROGRESS_TAIL_MAX_BYTES:-204800}"
PROMPT_MAX_BYTES="${MAKE_PROGRESS_PROMPT_MAX_BYTES:-65536}"
DEDUPE_SECS="${MAKE_PROGRESS_DEDUPE_SECS:-60}"

mode="hook"
cwd=""
session_id=""
transcript=""
prompt=""

if [[ "${1:-}" == "--fallback" ]]; then
    mode="fallback"
    cwd="$PWD"
else
    command -v jq &>/dev/null || exit 0
    input=$(cat)
    prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
    # Fast path: this hook runs on EVERY prompt. Non-matching prompts must
    # cost one jq + one string match, no filesystem writes. A prompt that
    # merely MENTIONS /make-progress in prose fires anyway — an acceptable
    # false positive (capture is cheap, local, side-effect-free); no intent
    # detection.
    case "$prompt" in
        *"/make-progress"*) ;;
        *) exit 0 ;;
    esac
    cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
    session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
    transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
    [[ -n "$cwd" ]] || cwd="$PWD"
fi

worktree=$(basename "$cwd" 2>/dev/null) || worktree="unknown"
ts=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null) || exit 0

# --- duplicate-fire dedupe (hook mode only) -----------------------------------
# A re-fire for the same session inside the window is a duplicate submission,
# not a new stall: skip it so the first (pristine) snapshot stays the one the
# skill labels. An empty session_id can't be confirmed as the same session, so
# it never dedupes; any stat failure below means "capture anyway".
if [[ "$mode" == "hook" && -n "$session_id" ]]; then
    newest=""
    # Anchored globs: exact worktree name plus -N collision suffixes, so a
    # worktree named "wt" never matches dirs captured for "wt-bare".
    for d in "$CAPTURE_ROOT"/*-"$worktree" "$CAPTURE_ROOT"/*-"$worktree"-[0-9]*; do
        # Unmatched glob leaves the literal pattern; -d filters it out. Names
        # are timestamp-prefixed, so the lexicographic max is the newest.
        [[ -d "$d" && "$d" > "$newest" ]] && newest="$d"
    done
    if [[ -n "$newest" && -f "$newest/meta.txt" ]]; then
        prev_session=$(sed -n 's/^session_id: //p' "$newest/meta.txt" 2>/dev/null | head -1)
        if [[ -n "$prev_session" && "$prev_session" == "$session_id" ]]; then
            born=$(clam_birth_epoch "$newest")
            [[ "$born" =~ ^[1-9][0-9]*$ ]] || born=$(clam_mtime_epoch "$newest")
            now=$(date +%s 2>/dev/null)
            if [[ "$born" =~ ^[1-9][0-9]*$ && "$now" =~ ^[1-9][0-9]*$ ]] \
                && (( now - born < DEDUPE_SECS )); then
                exit 0
            fi
        fi
    fi
fi

# Capture dir, -2/-3... suffix on collision (two invocations, same second,
# same worktree).
base="$CAPTURE_ROOT/$ts-$worktree"
dir="$base"
n=2
while [[ -e "$dir" ]]; do
    dir="$base-$n"
    n=$((n + 1))
done
mkdir -p "$dir" 2>/dev/null || exit 0

# --- meta.txt ---------------------------------------------------------------
{
    printf 'timestamp: %s\n' "$ts"
    printf 'mode: %s\n' "$mode"
    printf 'cwd: %s\n' "$cwd"
    printf 'session_id: %s\n' "$session_id"
    printf 'worktree: %s\n' "$worktree"
} > "$dir/meta.txt" 2>/dev/null

# --- prompt.txt (hook mode only) ---------------------------------------------
# The verbatim triggering prompt, capped to bound pathological pastes. In
# fallback mode the hook never saw the prompt; the skill writes it instead.
if [[ "$mode" == "hook" ]]; then
    printf '%s' "$prompt" | head -c "$PROMPT_MAX_BYTES" > "$dir/prompt.txt" 2>/dev/null
fi

# --- transcript-tail.jsonl (hook mode only) ---------------------------------
# Last 20 assistant messages. `fromjson?` drops malformed lines (Claude Code
# occasionally truncates JSON when a tool result exceeds the line buffer).
# Size-capped: drop oldest lines first until under TAIL_MAX_BYTES, always
# keeping at least the newest line.
if [[ -n "$transcript" && -f "$transcript" && -r "$transcript" ]]; then
    tail_file="$dir/transcript-tail.jsonl"
    jq -cR 'fromjson? | select(.type == "assistant")' < "$transcript" 2>/dev/null \
        | tail -20 > "$tail_file" 2>/dev/null
    if [[ -s "$tail_file" ]]; then
        while [[ $(wc -c < "$tail_file" 2>/dev/null || echo 0) -gt "$TAIL_MAX_BYTES" \
                 && $(wc -l < "$tail_file" 2>/dev/null || echo 0) -gt 1 ]]; do
            tail -n +2 "$tail_file" > "$tail_file.tmp" 2>/dev/null && mv "$tail_file.tmp" "$tail_file"
        done
    else
        # Empty or failed extraction: leave no misleading zero-byte artifact.
        rm -f "$tail_file" 2>/dev/null
    fi
fi

# --- .local/ state files -------------------------------------------------------
# Generalized: copy every regular file at depth 1 (whatever basenames exist,
# not a fixed list) and list every subdirectory's contents (without
# recursively copying them) as <dirname>-listing.txt.
if [[ -d "$cwd/.local" ]]; then
    for f in "$cwd/.local"/*; do
        [[ -f "$f" ]] || continue
        cp "$f" "$dir/$(basename "$f")" 2>/dev/null
    done
    for sub in "$cwd/.local"/*/; do
        [[ -d "$sub" ]] || continue
        dname=$(basename "$sub")
        ls -la "$sub" > "$dir/$dname-listing.txt" 2>/dev/null
    done
fi

# --- git state ----------------------------------------------------------------
if git -C "$cwd" rev-parse --git-dir &>/dev/null; then
    {
        printf 'branch: %s\n' "$(git -C "$cwd" branch --show-current 2>/dev/null)"
        printf '\nstatus (first 100 lines):\n'
        git -C "$cwd" status --porcelain 2>/dev/null | head -100
        printf '\nlast 3 commits:\n'
        git -C "$cwd" log --oneline -3 2>/dev/null
    } > "$dir/git-state.txt" 2>/dev/null
fi

# --- active durable crons -----------------------------------------------------
if [[ -f "$cwd/.claude/scheduled_tasks.json" ]]; then
    cp "$cwd/.claude/scheduled_tasks.json" "$dir/crons.txt" 2>/dev/null
fi

exit 0
