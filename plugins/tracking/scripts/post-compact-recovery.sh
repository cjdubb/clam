#!/bin/bash
# Contract: B04 post-compact-recovery
# Behavior: SessionStart hook (matcher=compact; fires only after auto or manual
#   compaction). Re-injects .local/ tracking files as fresh context so the agent
#   can resume from recorded state instead of the lossy compaction summary.
#   Also drops the flush-nudge skip-next marker for stale-read protection.
# Inputs:
#   - stdin: JSON with .cwd (working directory)
# Outputs:
#   - stdout: JSON envelope { hookSpecificOutput: { hookEventName:
#     "SessionStart", additionalContext: <recovery text> } } containing a
#     POST-COMPACTION RECOVERY block with the full contents of each .local/
#     tracking file and resume instructions.
#   - side effect: creates .local/.flush-nudge-skip-next marker so the
#     flush-nudge hook skips the first post-compaction prompt (stale-read
#     protection — no post-compaction assistant usage block exists yet, so the
#     transcript fill read would return the stale pre-compaction total).
# Errors: fail-open — any error exits 0 with no output. A recovery failure must
#   never break session start.
# Invariants:
#   - Always exits 0.
#   - Gated on .local/ directory existing — if there is no tracking state, there
#     is nothing to recover.
#   - Files dumped: TODO.md, PLAN.md, IMPLEMENTATION-PLAN.md,
#     TROUBLESHOOTING.md from .local/. Each file is preceded by a
#     "--- .local/<filename> ---" separator.
#   - Recovery text includes the working directory and current git branch (if
#     in a git repo) for re-grounding.
#   - Resume instructions tell the agent to: (1) review the state files,
#     (2) find the in-progress task in TODO.md, (3) continue from there,
#     (4) not re-ask already-answered questions (check PLAN.md).
#   - Runs alongside session-context.sh (which fires on all SessionStart events
#     and handles rules injection + resume pointer). This hook adds the FULL
#     file contents specifically for compaction recovery; session-context.sh
#     provides the rules and the State/Current Task summary.
#   - Output uses hookSpecificOutput JSON so additionalContext is injected into
#     the session context.
#   - Requires jq for input parsing and output formatting; skips silently
#     without it.
# Edge cases:
#   - .local/ directory does not exist → exit 0 with no output
#   - .local/ exists but no tracking files present → output recovery header
#     with "No .local/ state directory found" message and ask-user instructions
#   - cwd missing from input JSON → skip
#   - Not in a git repo → omit the git branch line
#   - TODO.md is the only file present → dump only that file
#   - jq not available → skip
#   - .flush-nudge-skip-next creation fails (read-only fs) → continue without
#     it; worst case is a false nudge on the next prompt, which is harmless

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || exit 0

STATE_DIR="$cwd/.local"
[ -d "$STATE_DIR" ] || exit 0

: > "$STATE_DIR/.flush-nudge-skip-next" 2>/dev/null || true

recovery_text=$(
    echo "=== POST-COMPACTION RECOVERY ==="
    echo ""
    echo "Context was just compacted. Critical state may have been lost from the conversation."
    echo ""
    echo "Working directory: $cwd"
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        echo "Git branch: $branch"
    fi
    echo ""

    has_files=false
    for file in TODO.md PLAN.md IMPLEMENTATION-PLAN.md TROUBLESHOOTING.md; do
        if [ -f "$STATE_DIR/$file" ]; then
            has_files=true
            echo "--- .local/$file ---"
            cat "$STATE_DIR/$file"
            echo ""
        fi
    done

    if [ "$has_files" = "true" ]; then
        echo ""
        echo "INSTRUCTIONS: Resume work now."
        echo "1. Review the state files above to re-establish context."
        echo "2. Find the task marked [IN PROGRESS] in TODO.md and continue from there."
        echo "3. If no task is in progress, report current status to the user and ask what to pick up next."
        echo "4. Do NOT re-ask questions that were already answered (check PLAN.md for prior decisions)."
    else
        echo "No .local/ state directory found."
        echo ""
        echo "INSTRUCTIONS: Context was compacted. Ask the user what to continue working on."
    fi

    echo ""
    echo "=== END POST-COMPACTION RECOVERY ==="
)

printf '%s' "$recovery_text" | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
exit 0
