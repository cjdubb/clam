#!/bin/bash
# Tests for post-compact-recovery.sh (B04): the PostCompact SessionStart hook
# that re-injects .local/ tracking files as fresh context after compaction,
# and drops the flush-nudge skip-next marker for stale-read protection.
#
# Hermetic: builds synthetic worktrees under a temp dir with .local/ tracking
# files (and, where needed, a real git repo), feeds the hook JSON on stdin,
# and asserts on the resulting hookSpecificOutput JSON envelope and any side
# effect marker files.
#
# Run: bash plugins/tracking/scripts/post-compact-recovery.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/post-compact-recovery.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }

check() { # label got expected
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1" "got '$2', expected '$3'"
    fi
}

# Build a minimal PostCompact/SessionStart hook JSON payload.
hook_json() { # cwd
    printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$1"
}

# Run the hook and capture stdout (the JSON output). Exit status is
# propagated to the caller via $?.
run_hook() { # cwd
    printf '%s' "$(hook_json "$1")" | bash "$HOOK" 2>/dev/null
}

# Extract .hookSpecificOutput.additionalContext from a hook run.
get_context() { # cwd
    run_hook "$1" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null
}

# Builds a worktree with a bare .local/ directory (no tracking files yet).
make_local_wd() { # name -> echoes path
    local wd="$TMPROOT/$1"
    mkdir -p "$wd/.local"
    printf '%s' "$wd"
}

# Runs the hook with a fake `jq` shadowing PATH that always fails as if the
# binary did not exist (exit 127) — the closest hermetic proxy for "jq not
# on PATH" without stripping every other tool the hook might need.
run_hook_no_jq() { # cwd
    local fakebin="$TMPROOT/fakebin-nojq"
    if [ ! -d "$fakebin" ]; then
        mkdir -p "$fakebin"
        cat > "$fakebin/jq" <<'EOF'
#!/bin/bash
exit 127
EOF
        chmod +x "$fakebin/jq"
    fi
    printf '%s' "$(hook_json "$1")" | PATH="$fakebin:$PATH" bash "$HOOK" 2>/dev/null
}

# --- Gate tests ---

# .local/ directory does not exist -> exit 0, no output.
test_gate_no_local_dir() {
    local wd="$TMPROOT/no-local-gate"
    mkdir -p "$wd"
    local output rc
    output=$(run_hook "$wd")
    rc=$?
    check "no .local/ dir -> exit 0" "$rc" "0"
    check "no .local/ dir -> no output" "$output" ""
}

# cwd missing from input JSON -> exit 0, no output.
test_gate_missing_cwd() {
    local output rc
    output=$(printf '{}' | bash "$HOOK" 2>/dev/null)
    rc=$?
    check "missing cwd -> exit 0" "$rc" "0"
    check "missing cwd -> no output" "$output" ""
}

# jq not available -> fails open, exit 0 (contract: skip silently without
# it; simulated here since jq is a hard dependency of the whole harness).
test_gate_no_jq() {
    local wd
    wd=$(make_local_wd "no-jq")
    printf 'State: Not Started\n' > "$wd/.local/TODO.md"
    local rc
    run_hook_no_jq "$wd" >/dev/null
    rc=$?
    check "jq unavailable -> exit 0 (fail-open)" "$rc" "0"
}

# --- Recovery output structure tests ---

test_output_valid_json() {
    local wd output
    wd=$(make_local_wd "valid-json")
    printf 'State: Not Started\n' > "$wd/.local/TODO.md"
    output=$(run_hook "$wd")
    if printf '%s' "$output" | jq -e . >/dev/null 2>&1; then
        pass "stdout is valid JSON"
    else
        fail "stdout is valid JSON" "got '$output'"
    fi
}

test_output_envelope_structure() {
    local wd output event_name ctx_is_string
    wd=$(make_local_wd "envelope")
    printf 'State: Not Started\n' > "$wd/.local/TODO.md"
    output=$(run_hook "$wd")
    event_name=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
    check "hookSpecificOutput.hookEventName is SessionStart" "$event_name" "SessionStart"
    ctx_is_string=$(printf '%s' "$output" | jq -e '(.hookSpecificOutput.additionalContext | type) == "string"' 2>/dev/null)
    check "hookSpecificOutput.additionalContext is a string" "$ctx_is_string" "true"
}

test_includes_recovery_header() {
    local wd ctx
    wd=$(make_local_wd "recovery-header")
    printf 'x\n' > "$wd/.local/TODO.md"
    ctx=$(get_context "$wd")
    if printf '%s' "$ctx" | grep -qi "POST-COMPACTION RECOVERY"; then
        pass "additionalContext includes a POST-COMPACTION RECOVERY header"
    else
        fail "additionalContext includes a POST-COMPACTION RECOVERY header" "header not found in '$ctx'"
    fi
}

# --- File content tests ---

test_contains_todo_content() {
    local wd ctx
    wd=$(make_local_wd "todo-content")
    printf 'State: In Progress\nCurrent Task: [IN PROGRESS] build the widget\n' > "$wd/.local/TODO.md"
    ctx=$(get_context "$wd")
    if printf '%s' "$ctx" | grep -qF "[IN PROGRESS] build the widget"; then
        pass "additionalContext contains TODO.md content"
    else
        fail "additionalContext contains TODO.md content" "content not found in '$ctx'"
    fi
}

test_contains_plan_content() {
    local wd ctx
    wd=$(make_local_wd "plan-content")
    printf 'x\n' > "$wd/.local/TODO.md"
    printf 'Decision: use approach B because of constraint X\n' > "$wd/.local/PLAN.md"
    ctx=$(get_context "$wd")
    if printf '%s' "$ctx" | grep -qF "Decision: use approach B because of constraint X"; then
        pass "additionalContext contains PLAN.md content"
    else
        fail "additionalContext contains PLAN.md content" "content not found in '$ctx'"
    fi
}

test_contains_implementation_plan_content() {
    local wd ctx
    wd=$(make_local_wd "impl-plan-content")
    printf 'x\n' > "$wd/.local/TODO.md"
    printf 'Step 3: wire up the adapter layer\n' > "$wd/.local/IMPLEMENTATION-PLAN.md"
    ctx=$(get_context "$wd")
    if printf '%s' "$ctx" | grep -qF "Step 3: wire up the adapter layer"; then
        pass "additionalContext contains IMPLEMENTATION-PLAN.md content"
    else
        fail "additionalContext contains IMPLEMENTATION-PLAN.md content" "content not found in '$ctx'"
    fi
}

test_contains_troubleshooting_content() {
    local wd ctx
    wd=$(make_local_wd "troubleshooting-content")
    printf 'x\n' > "$wd/.local/TODO.md"
    printf 'Known issue: flaky retry on timeout, worked around by backoff\n' > "$wd/.local/TROUBLESHOOTING.md"
    ctx=$(get_context "$wd")
    if printf '%s' "$ctx" | grep -qF "Known issue: flaky retry on timeout, worked around by backoff"; then
        pass "additionalContext contains TROUBLESHOOTING.md content"
    else
        fail "additionalContext contains TROUBLESHOOTING.md content" "content not found in '$ctx'"
    fi
}

test_file_separators() {
    local wd ctx ok
    wd=$(make_local_wd "separators")
    printf 'todo body\n' > "$wd/.local/TODO.md"
    printf 'plan body\n' > "$wd/.local/PLAN.md"
    ctx=$(get_context "$wd")
    ok=yes
    printf '%s' "$ctx" | grep -qF -- "--- .local/TODO.md ---" || ok=no
    printf '%s' "$ctx" | grep -qF -- "--- .local/PLAN.md ---" || ok=no
    check "each file preceded by '--- .local/<filename> ---' separator" "$ok" "yes"
}

# --- Re-grounding tests ---

test_includes_cwd() {
    local wd ctx
    wd=$(make_local_wd "cwd-included")
    printf 'x\n' > "$wd/.local/TODO.md"
    ctx=$(get_context "$wd")
    if printf '%s' "$ctx" | grep -qF "$wd"; then
        pass "additionalContext includes the working directory"
    else
        fail "additionalContext includes the working directory" "'$wd' not found in '$ctx'"
    fi
}

test_includes_git_branch() {
    local wd ctx
    wd=$(make_local_wd "git-branch")
    printf 'x\n' > "$wd/.local/TODO.md"
    git init -q "$wd"
    git -C "$wd" config user.email test@example.com
    git -C "$wd" config user.name test
    git -C "$wd" checkout -q -b feature-xyz
    git -C "$wd" commit -q --allow-empty -m init
    ctx=$(get_context "$wd")
    if printf '%s' "$ctx" | grep -q "feature-xyz"; then
        pass "additionalContext includes the current git branch"
    else
        fail "additionalContext includes the current git branch" "'feature-xyz' not found in '$ctx'"
    fi
}

test_no_git_branch_line() {
    local wd ctx
    wd=$(make_local_wd "no-git")
    printf 'x\n' > "$wd/.local/TODO.md"
    ctx=$(get_context "$wd")
    if printf '%s' "$ctx" | grep -qi "branch:"; then
        fail "git branch line omitted when not in a repo" "a branch line was found unexpectedly in '$ctx'"
    else
        pass "git branch line omitted when not in a repo"
    fi
}

test_resume_instructions() {
    local wd ctx ok
    wd=$(make_local_wd "resume-instructions")
    printf 'State: In Progress\nCurrent Task: [IN PROGRESS] foo\n' > "$wd/.local/TODO.md"
    ctx=$(get_context "$wd")
    ok=yes
    printf '%s' "$ctx" | grep -qi "review" || ok=no
    printf '%s' "$ctx" | grep -qiF "TODO.md" || ok=no
    printf '%s' "$ctx" | grep -qiF "PLAN.md" || ok=no
    check "resume instructions mention reviewing state, TODO.md, and PLAN.md" "$ok" "yes"
}

# --- Edge cases ---

test_no_tracking_files() {
    local wd ctx ok
    wd=$(make_local_wd "no-tracking-files")
    # .local/ exists but is otherwise empty.
    ctx=$(get_context "$wd")
    ok=yes
    printf '%s' "$ctx" | grep -qF "No .local/ state directory found" || ok=no
    check "no tracking files -> 'No .local/ state directory found' message" "$ok" "yes"
    ok=yes
    printf '%s' "$ctx" | grep -qi "ask" || ok=no
    check "no tracking files -> ask-user instructions present" "$ok" "yes"
}

test_only_todo_present() {
    local wd ctx ok
    wd=$(make_local_wd "only-todo")
    printf 'State: Not Started\n' > "$wd/.local/TODO.md"
    ctx=$(get_context "$wd")
    ok=yes
    printf '%s' "$ctx" | grep -qF -- "--- .local/TODO.md ---" || ok=no
    printf '%s' "$ctx" | grep -qF "State: Not Started" || ok=no
    printf '%s' "$ctx" | grep -qF -- "--- .local/PLAN.md ---" && ok=no
    check "works with only TODO.md present" "$ok" "yes"
}

# --- Side effect tests ---

test_skip_next_marker_created() {
    local wd
    wd=$(make_local_wd "skip-next-marker")
    printf 'x\n' > "$wd/.local/TODO.md"
    run_hook "$wd" >/dev/null
    if [ -f "$wd/.local/.flush-nudge-skip-next" ]; then
        pass "creates .local/.flush-nudge-skip-next marker"
    else
        fail "creates .local/.flush-nudge-skip-next marker" "marker not found"
    fi
}

# Marker creation failure (e.g. read-only .local/) must not break the
# recovery output. Simulated via chmod; if the process runs as root the
# permission block may not actually take, so we only hard-assert on output
# resilience and note the limitation rather than failing spuriously.
test_marker_failure_still_outputs() {
    local wd output rc marker_blocked
    wd=$(make_local_wd "marker-failure")
    printf 'x\n' > "$wd/.local/TODO.md"
    chmod 555 "$wd/.local"
    output=$(run_hook "$wd")
    rc=$?
    marker_blocked=yes
    [ -f "$wd/.local/.flush-nudge-skip-next" ] && marker_blocked=no
    chmod 755 "$wd/.local"
    check "exits 0 even if marker creation fails" "$rc" "0"
    if printf '%s' "$output" | jq -e '(.hookSpecificOutput.additionalContext | length) > 0' >/dev/null 2>&1; then
        pass "still outputs recovery text even if marker creation fails"
    else
        fail "still outputs recovery text even if marker creation fails" "no/empty additionalContext, got '$output'"
    fi
    if [ "$marker_blocked" = "no" ]; then
        echo "NOTE  marker-creation block not effective (likely running as root) — output-resilience assertion above still stands"
    fi
}

# --- Invariant: always exits 0 ---

test_always_exits_zero() {
    local ok wd
    ok=yes

    wd="$TMPROOT/exit0-no-local"
    mkdir -p "$wd"
    run_hook "$wd" >/dev/null
    [ "$?" = "0" ] || ok=no

    printf '{}' | bash "$HOOK" >/dev/null 2>&1
    [ "$?" = "0" ] || ok=no

    wd="$TMPROOT/exit0-normal"
    mkdir -p "$wd/.local"
    printf 'x\n' > "$wd/.local/TODO.md"
    run_hook "$wd" >/dev/null
    [ "$?" = "0" ] || ok=no

    wd="$TMPROOT/exit0-empty-local"
    mkdir -p "$wd/.local"
    run_hook "$wd" >/dev/null
    [ "$?" = "0" ] || ok=no

    check "always exits 0 across gate, normal, and edge-case paths" "$ok" "yes"
}

# --- Run all tests ---
test_gate_no_local_dir
test_gate_missing_cwd
test_gate_no_jq
test_output_valid_json
test_output_envelope_structure
test_includes_recovery_header
test_contains_todo_content
test_contains_plan_content
test_contains_implementation_plan_content
test_contains_troubleshooting_content
test_file_separators
test_includes_cwd
test_includes_git_branch
test_no_git_branch_line
test_resume_instructions
test_no_tracking_files
test_only_todo_present
test_skip_next_marker_created
test_marker_failure_still_outputs
test_always_exits_zero

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
