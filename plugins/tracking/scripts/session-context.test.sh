#!/bin/bash
# Tests for session-context.sh: the SessionStart hook's auto-create-TODO.md
# behavior (B01), resume injection, and epoch marker clearing.
#
# Hermetic: creates a temp directory tree simulating a worktree with .local/,
# feeds synthetic hook JSON to session-context.sh, and asserts on the resulting
# TODO.md (or absence thereof) and the hook's JSON output.
#
# Run: bash plugins/tracking/scripts/session-context.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-context.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../../scripts/lib/test-portability.sh"

# Local-time epoch->string (BSD `date -r` first, GNU `date -d @` fallback).
# tp_epoch_fmt is UTC-pinned by contract; these call sites must stay in the
# caller's LOCAL zone, because they feed `touch -t` (local by definition) and
# are compared against session-context.sh's own local-ISO rendering.
local_epoch_fmt() { # epoch fmt
    date -r "$1" "$2" 2>/dev/null || date -d "@$1" "$2" 2>/dev/null
}

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

# Build a minimal SessionStart hook JSON payload.
hook_json() { # cwd
    printf '{"cwd":"%s","hook_event_name":"SessionStart","session_id":"test-sid"}' "$1"
}

# Run the hook and capture stdout (the JSON output).
run_hook() { # cwd
    printf '%s' "$(hook_json "$1")" | bash "$HOOK" 2>/dev/null
}

# --- B04/B06 shared helpers ---
#
# B04 (resume-freshness) fixtures need a hermetic $HOME with a fake
# ~/.claude/projects/<sanitized-cwd>/ directory holding prior-transcript
# .jsonl files, precise TODO.md / transcript mtimes (touch -t), and the
# ability to invoke the hook with both an overridden $HOME and an extra
# env var or two (the stale-gate / threshold knobs). None of this is needed
# by the pre-existing tests above, which is why it lives down here rather
# than folded into hook_json()/run_hook().

# sanitize_cwd <cwd> -> the project-dir encoding used by activity.sh's
# activity_prior_transcripts ("/" -> "-", per its Contract: B01 docblock).
sanitize_cwd() { printf '%s' "$1" | sed 's#/#-#g'; }

# touch_epoch <path> <epoch> -> sets path's mtime to the given epoch seconds,
# via local-time touch -t (mirrors the pattern in ccost.sh).
touch_epoch() { # path epoch
    touch -t "$(local_epoch_fmt "$2" +%Y%m%d%H%M.%S)" "$1"
}

# write_prompt_line <transcript-path> <iso-timestamp> -> appends one
# qualifying human-prompt transcript line (per activity.sh's B01 contract:
# type=user, string content, no isMeta, non-machine-generated content).
write_prompt_line() {
    printf '{"type":"user","message":{"content":"plain text"},"timestamp":"%s"}\n' "$2" >> "$1"
}

# run_hook_ctx <cwd> <home> <transcript_path> [ENV=val ...] -> runs the hook
# with HOME overridden to a fake project tree and the given transcript_path
# (the "current session" transcript activity_prior_transcripts must exclude),
# returns the decoded hookSpecificOutput.additionalContext string.
run_hook_ctx() {
    local cwd="$1" home="$2" tpath="$3"
    shift 3
    printf '{"cwd":"%s","transcript_path":"%s"}' "$cwd" "$tpath" \
        | env "$@" HOME="$home" bash "$HOOK" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null
}

# assert_contains <label> <haystack> <literal-needle>
assert_contains() {
    if printf '%s' "$2" | grep -qF -- "$3"; then
        pass "$1"
    else
        fail "$1" "context did not contain: $3"
    fi
}

# assert_not_contains <label> <haystack> <literal-needle>
assert_not_contains() {
    if printf '%s' "$2" | grep -qF -- "$3"; then
        fail "$1" "context unexpectedly contained: $3"
    else
        pass "$1"
    fi
}

# assert_contains_re <label> <haystack> <ERE> (case-sensitive)
assert_contains_re() {
    if printf '%s' "$2" | grep -qE -- "$3"; then
        pass "$1"
    else
        fail "$1" "context did not match regex: $3"
    fi
}

# assert_contains_re_i <label> <haystack> <ERE> (case-insensitive)
assert_contains_re_i() {
    if printf '%s' "$2" | grep -qiE -- "$3"; then
        pass "$1"
    else
        fail "$1" "context did not match regex (case-insensitive): $3"
    fi
}

# --- Auto-create TODO.md tests (B01 contract) ---

# Test: auto-creates TODO.md when .local/ exists without TODO.md
test_auto_create_when_local_exists() {
    local wd="$TMPROOT/auto-create"
    mkdir -p "$wd/.local"
    run_hook "$wd" >/dev/null
    if [ -f "$wd/.local/TODO.md" ]; then
        pass "auto-creates TODO.md when .local/ exists"
    else
        fail "auto-creates TODO.md when .local/ exists" "TODO.md not created"
    fi
}

# Test: auto-created TODO.md has State: Not Started
test_auto_create_has_state() {
    local wd="$TMPROOT/auto-state"
    mkdir -p "$wd/.local"
    run_hook "$wd" >/dev/null
    local state
    state=$(grep -m1 '^State:' "$wd/.local/TODO.md" 2>/dev/null | sed 's/^State:[[:space:]]*//')
    check "auto-created TODO.md has State: Not Started" "$state" "Not Started"
}

# Test: does NOT overwrite existing TODO.md
test_no_overwrite() {
    local wd="$TMPROOT/no-overwrite"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\nCurrent Task: doing stuff\n' > "$wd/.local/TODO.md"
    run_hook "$wd" >/dev/null
    local state
    state=$(grep -m1 '^State:' "$wd/.local/TODO.md" 2>/dev/null | sed 's/^State:[[:space:]]*//')
    check "does not overwrite existing TODO.md" "$state" "In Progress"
}

# Test: no-op when .local/ does not exist
test_noop_without_local() {
    local wd="$TMPROOT/no-local"
    mkdir -p "$wd"
    run_hook "$wd" >/dev/null
    if [ ! -f "$wd/.local/TODO.md" ]; then
        pass "no-op when .local/ does not exist"
    else
        fail "no-op when .local/ does not exist" "TODO.md was created"
    fi
}

# Test: no-op when template is missing
test_noop_without_template() {
    local wd="$TMPROOT/no-template"
    mkdir -p "$wd/.local"
    local real_template="$PLUGIN_ROOT/templates/TODO.md"
    local backup="$TMPROOT/TODO.md.bak"
    # Temporarily move the template away
    if [ -f "$real_template" ]; then
        mv "$real_template" "$backup"
    fi
    run_hook "$wd" >/dev/null
    local created=no
    [ -f "$wd/.local/TODO.md" ] && created=yes
    # Restore template
    if [ -f "$backup" ]; then
        mv "$backup" "$real_template"
    fi
    check "no-op when template is missing" "$created" "no"
}

# Test: substitutes [YYYY-MM-DD] with current date
test_date_substitution() {
    local wd="$TMPROOT/date-sub"
    mkdir -p "$wd/.local"
    run_hook "$wd" >/dev/null
    local today
    today=$(date +%Y-%m-%d)
    if grep -q "$today" "$wd/.local/TODO.md" 2>/dev/null; then
        pass "substitutes [YYYY-MM-DD] with current date"
    else
        fail "substitutes [YYYY-MM-DD] with current date" "date $today not found in TODO.md"
    fi
}

# Test: substitutes [branch-name] with git branch (when in a git repo)
test_branch_substitution() {
    local wd="$TMPROOT/branch-sub"
    mkdir -p "$wd/.local"
    # Init a git repo so there's a branch to detect
    git init -q "$wd" 2>/dev/null
    git -C "$wd" checkout -q -b test-branch 2>/dev/null
    # Need at least one commit for branch to exist
    git -C "$wd" commit -q --allow-empty -m "init" 2>/dev/null
    run_hook "$wd" >/dev/null
    if grep -q "test-branch" "$wd/.local/TODO.md" 2>/dev/null; then
        pass "substitutes [branch-name] with git branch"
    else
        fail "substitutes [branch-name] with git branch" "branch name not found in TODO.md"
    fi
}

# --- Resume injection tests ---

# Test: freshly auto-created TODO.md triggers resume context
test_auto_create_triggers_resume() {
    local wd="$TMPROOT/resume-trigger"
    mkdir -p "$wd/.local"
    local output
    output=$(run_hook "$wd")
    if printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q "Tracking document present"; then
        pass "auto-created TODO.md triggers resume context"
    else
        fail "auto-created TODO.md triggers resume context" "resume context not in output"
    fi
}

# Test: existing TODO.md produces resume context with correct state
test_resume_existing_todo() {
    local wd="$TMPROOT/resume-existing"
    mkdir -p "$wd/.local"
    printf 'State: Blocked\nCurrent Task: waiting for deploy\n' > "$wd/.local/TODO.md"
    local output
    output=$(run_hook "$wd")
    local ctx
    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
    if printf '%s' "$ctx" | grep -q "State: Blocked"; then
        pass "resume context shows correct state"
    else
        fail "resume context shows correct state" "State: Blocked not in resume context"
    fi
}

# --- Epoch marker tests ---

# Test: clears .decision-nudge-fired on SessionStart
test_clears_epoch_markers() {
    local wd="$TMPROOT/epoch"
    mkdir -p "$wd/.local"
    touch "$wd/.local/.decision-nudge-fired"
    run_hook "$wd" >/dev/null
    if [ ! -f "$wd/.local/.decision-nudge-fired" ]; then
        pass "clears .decision-nudge-fired on SessionStart"
    else
        fail "clears .decision-nudge-fired on SessionStart" "marker still exists"
    fi
}

# --- B04: resume-freshness tests ---
#
# Contract: B04 docblock above _resume_freshness in session-context.sh (plus
# the call-site: stale block REPLACES the trust-the-docs resume text).
# Dependency lib/activity.sh (B01) is real in this worktree.
#
# _resume_freshness is currently a NotImplemented stub (echo to stderr,
# return 90, no stdout) — every STALE-variant assertion below is expected to
# FAIL until B04 is implemented. FRESH-variant cases pass already, since
# empty/NotImplemented stdout falls through to the existing trust-the-docs
# resume block (fail-open by construction).

# _b04_one_prompt_fixture <tag> -> builds a worktree + fake $HOME with
# exactly one prior transcript holding exactly one qualifying human prompt
# one hour after TODO.md's mtime (so activity_prompts_since counts 1 against
# the default/threshold-1 gate). Populates B04_WD, B04_HOME, B04_TRANSCRIPT,
# B04_CURPATH (a "current session" transcript path guaranteed not to match
# anything on disk, so activity_prior_transcripts excludes nothing), and the
# reference epochs, so callers can derive expected ISO strings.
_b04_one_prompt_fixture() {
    local tag="$1"
    B04_WD="$TMPROOT/b04-$tag"
    B04_HOME="$TMPROOT/b04-$tag-home"
    mkdir -p "$B04_WD/.local"
    printf 'State: Awaiting Agent\nCurrent Task: reticulate the splines for the frobnicator\n' > "$B04_WD/.local/TODO.md"
    B04_TODO_EPOCH=$(tp_parse_datetime "2026-01-01 09:00:00")
    touch_epoch "$B04_WD/.local/TODO.md" "$B04_TODO_EPOCH"
    local proj_dir="$B04_HOME/.claude/projects/$(sanitize_cwd "$B04_WD")"
    mkdir -p "$proj_dir"
    B04_TRANSCRIPT="$proj_dir/prior-session.jsonl"
    B04_PROMPT_EPOCH=$((B04_TODO_EPOCH + 3600))
    write_prompt_line "$B04_TRANSCRIPT" "$(tp_epoch_fmt "$B04_PROMPT_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"
    B04_TRANSCRIPT_MTIME_EPOCH=$((B04_TODO_EPOCH + 7200))
    touch_epoch "$B04_TRANSCRIPT" "$B04_TRANSCRIPT_MTIME_EPOCH"
    B04_CURPATH="$TMPROOT/b04-$tag-current.jsonl"
}

# Test: STALE variant — every clause in the B04 contract's required content.
test_b04_stale_variant() {
    _b04_one_prompt_fixture stale
    local ctx
    ctx=$(run_hook_ctx "$B04_WD" "$B04_HOME" "$B04_CURPATH")

    local ref_date ref_hm newest_date newest_hm
    ref_date=$(local_epoch_fmt "$B04_TODO_EPOCH" +%Y-%m-%d)
    ref_hm=$(local_epoch_fmt "$B04_TODO_EPOCH" +%H:%M)
    newest_date=$(local_epoch_fmt "$B04_TRANSCRIPT_MTIME_EPOCH" +%Y-%m-%d)
    newest_hm=$(local_epoch_fmt "$B04_TRANSCRIPT_MTIME_EPOCH" +%H:%M)

    assert_contains_re "B04 stale (a): TODO.md's last-updated time (ISO-8601 local)" "$ctx" "${ref_date}[T ]${ref_hm}"
    assert_contains_re "B04 stale (b): prompt count (~1)" "$ctx" "~?1[^0-9]{0,20}human prompt"
    assert_contains_re "B04 stale (c): newest prior transcript's mtime (ISO-8601 local)" "$ctx" "${newest_date}[T ]${newest_hm}"
    assert_contains "B04 stale (d): newest prior transcript's absolute path" "$ctx" "$B04_TRANSCRIPT"
    assert_contains_re_i "B04 stale (e): instruction to read the tail" "$ctx" "\btail\b"
    assert_contains_re "B04 stale (e): tail instruction names ~30 entries" "$ctx" "\b30\b"
    assert_contains_re_i "B04 stale (f): reconcile instruction" "$ctx" "\breconcil"
    assert_contains "B04 stale (f): still-read TODO.md instruction" "$ctx" ".local/TODO.md"
    assert_contains "B04 stale (f): still-read PLAN.md instruction" "$ctx" ".local/PLAN.md"
    assert_contains "B04 stale (f): still-read decisions/ instruction" "$ctx" ".local/decisions/"
    assert_contains "B04 stale (g): recorded State surfaced" "$ctx" "Awaiting Agent"
    assert_contains "B04 stale (g): recorded Current Task surfaced" "$ctx" "reticulate the splines for the frobnicator"
    assert_not_contains "B04 stale: mutually exclusive with the trust-the-docs text" "$ctx" "trust the tracking docs"
}

# Test: FRESH — TODO.md touched after all prior prompts.
test_b04_fresh_todo_touched_after_prompts() {
    local wd="$TMPROOT/b04-fresh-after"
    local home="$TMPROOT/b04-fresh-after-home"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\nCurrent Task: wire up the frobnicator\n' > "$wd/.local/TODO.md"
    local prompt_epoch todo_epoch
    prompt_epoch=$(tp_parse_datetime "2026-01-01 08:00:00")
    todo_epoch=$((prompt_epoch + 3600))
    touch_epoch "$wd/.local/TODO.md" "$todo_epoch"
    local proj_dir="$home/.claude/projects/$(sanitize_cwd "$wd")"
    mkdir -p "$proj_dir"
    local transcript="$proj_dir/prior-session.jsonl"
    write_prompt_line "$transcript" "$(tp_epoch_fmt "$prompt_epoch" +%Y-%m-%dT%H:%M:%SZ)"
    touch_epoch "$transcript" "$prompt_epoch"
    local ctx
    ctx=$(run_hook_ctx "$wd" "$home" "$TMPROOT/b04-fresh-after-current.jsonl")
    assert_contains "B04 fresh: TODO.md touched after all prior prompts -> trust-the-docs text" "$ctx" "trust the tracking docs"
}

# Test: FRESH — the current session's own transcript is excluded, so a
# project dir containing ONLY that file (even with a newer prompt) is fresh.
test_b04_fresh_current_session_excluded() {
    local wd="$TMPROOT/b04-excl-self"
    local home="$TMPROOT/b04-excl-self-home"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\nCurrent Task: excludeme\n' > "$wd/.local/TODO.md"
    local todo_epoch
    todo_epoch=$(tp_parse_datetime "2026-01-01 09:00:00")
    touch_epoch "$wd/.local/TODO.md" "$todo_epoch"
    local proj_dir="$home/.claude/projects/$(sanitize_cwd "$wd")"
    mkdir -p "$proj_dir"
    local self_transcript="$proj_dir/current-session.jsonl"
    write_prompt_line "$self_transcript" "$(tp_epoch_fmt "$((todo_epoch + 3600))" +%Y-%m-%dT%H:%M:%SZ)"
    touch_epoch "$self_transcript" "$((todo_epoch + 3600))"
    local ctx
    ctx=$(run_hook_ctx "$wd" "$home" "$self_transcript")
    assert_contains "B04 fresh: project dir contains only the current session's own transcript -> excluded, fresh" "$ctx" "trust the tracking docs"
}

# Test: CLAM_TRACKING_RESUME_STALE_GATE=disabled forces fresh even though
# the same fixture is STALE by default (test_b04_stale_variant above).
test_b04_fresh_gate_disabled() {
    _b04_one_prompt_fixture gate-disabled
    local ctx
    ctx=$(run_hook_ctx "$B04_WD" "$B04_HOME" "$B04_CURPATH" CLAM_TRACKING_RESUME_STALE_GATE=disabled)
    assert_contains "B04 fresh: CLAM_TRACKING_RESUME_STALE_GATE=disabled overrides an otherwise-stale fixture" "$ctx" "trust the tracking docs"
}

# Test: CLAM_TRACKING_RESUME_STALE_THRESHOLD=2 with exactly 1 newer prompt
# stays under threshold -> fresh (pairs with test_b04_stale_variant, which
# is this same fixture shape at the default threshold of 1 -> stale).
test_b04_fresh_threshold_raised() {
    _b04_one_prompt_fixture threshold2
    local ctx
    ctx=$(run_hook_ctx "$B04_WD" "$B04_HOME" "$B04_CURPATH" CLAM_TRACKING_RESUME_STALE_THRESHOLD=2)
    assert_contains "B04 fresh: CLAM_TRACKING_RESUME_STALE_THRESHOLD=2 with exactly 1 newer prompt stays under threshold" "$ctx" "trust the tracking docs"
}

# Test: bounded work — 6 prior transcripts, only the oldest (6th by mtime)
# has newer prompts; the newest 5 (which the contract bounds the scan to)
# have none, so the sum is 0 -> fresh.
test_b04_fresh_bounded_to_newest_five() {
    local wd="$TMPROOT/b04-bounded"
    local home="$TMPROOT/b04-bounded-home"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\nCurrent Task: boundedtest\n' > "$wd/.local/TODO.md"
    local todo_epoch
    todo_epoch=$(tp_parse_datetime "2026-01-01 09:00:00")
    touch_epoch "$wd/.local/TODO.md" "$todo_epoch"
    local proj_dir="$home/.claude/projects/$(sanitize_cwd "$wd")"
    mkdir -p "$proj_dir"
    local i
    for i in 1 2 3 4 5; do
        : > "$proj_dir/newest-$i.jsonl"
        touch_epoch "$proj_dir/newest-$i.jsonl" "$((todo_epoch + 600 - i * 10))"
    done
    local oldest="$proj_dir/oldest-6th.jsonl"
    write_prompt_line "$oldest" "$(tp_epoch_fmt "$((todo_epoch + 3600))" +%Y-%m-%dT%H:%M:%SZ)"
    touch_epoch "$oldest" "$((todo_epoch - 5000))"
    local ctx
    ctx=$(run_hook_ctx "$wd" "$home" "$TMPROOT/b04-bounded-current.jsonl")
    assert_contains "B04 fresh: only the oldest (6th by mtime) of 6 prior transcripts has newer prompts -> bounded to newest 5" "$ctx" "trust the tracking docs"
}

# Test: FRESH — no project dir at all for this cwd (fail-open).
test_b04_fresh_no_project_dir() {
    local wd="$TMPROOT/b04-noprojdir"
    local home="$TMPROOT/b04-noprojdir-home"
    mkdir -p "$wd/.local" "$home"
    printf 'State: In Progress\nCurrent Task: noprojdirtest\n' > "$wd/.local/TODO.md"
    local ctx
    ctx=$(run_hook_ctx "$wd" "$home" "")
    assert_contains "B04 fresh: no project dir for cwd -> fail-open, fresh" "$ctx" "trust the tracking docs"
}

# Test: no TODO.md at all — auto-create (existing behavior) still fires, and
# the freshly-created TODO (mtime ~now) reads as fresh, surfacing its own
# (brand-new) State.
test_b04_fresh_auto_created_todo() {
    local wd="$TMPROOT/b04-autocreate"
    local home="$TMPROOT/b04-autocreate-home"
    mkdir -p "$wd/.local" "$home"
    local ctx
    ctx=$(run_hook_ctx "$wd" "$home" "")
    assert_contains "B04 fresh: auto-created TODO.md does not break auto-create -> fresh" "$ctx" "trust the tracking docs"
    assert_contains "B04 fresh: auto-created TODO.md surfaces its own fresh State" "$ctx" "State: Not Started"
}

# Test: epoch marker clearing — .local/.freshness-nudge-fired is removed on
# every SessionStart, alongside the existing markers (already covered above
# by test_clears_epoch_markers).
test_b04_clears_freshness_marker() {
    local wd="$TMPROOT/b04-marker"
    mkdir -p "$wd/.local"
    printf 'State: In Progress\nCurrent Task: markertest\n' > "$wd/.local/TODO.md"
    touch "$wd/.local/.freshness-nudge-fired"
    run_hook "$wd" >/dev/null
    if [ ! -f "$wd/.local/.freshness-nudge-fired" ]; then
        pass "B04: clears .local/.freshness-nudge-fired on SessionStart"
    else
        fail "B04: clears .local/.freshness-nudge-fired on SessionStart" "marker still exists"
    fi
}

# --- B06: todo-open-questions tests ---
#
# Contract: the "Contract: B06" HTML comment inside
# plugins/tracking/templates/TODO.md (section content + the companion rule
# line in session-context.sh's injected rules heredoc).

# Test: template gains a '## Open Questions' header.
test_b06_template_has_open_questions_header() {
    if grep -q '^## Open Questions$' "$PLUGIN_ROOT/templates/TODO.md"; then
        pass "B06: template contains a '## Open Questions' header"
    else
        fail "B06: template contains a '## Open Questions' header" "header not found"
    fi
}

# Test: Open Questions sits after Blockers/Notes and before Discovered Tasks.
test_b06_open_questions_ordering() {
    local tmpl="$PLUGIN_ROOT/templates/TODO.md"
    local blockers_line open_q_line discovered_line
    blockers_line=$(grep -n '^## Blockers/Notes$' "$tmpl" | head -1 | cut -d: -f1)
    open_q_line=$(grep -n '^## Open Questions$' "$tmpl" | head -1 | cut -d: -f1)
    discovered_line=$(grep -n '^## Discovered Tasks$' "$tmpl" | head -1 | cut -d: -f1)
    if [ -n "$blockers_line" ] && [ -n "$open_q_line" ] && [ -n "$discovered_line" ] \
        && [ "$blockers_line" -lt "$open_q_line" ] && [ "$open_q_line" -lt "$discovered_line" ]; then
        pass "B06: Open Questions positioned after Blockers/Notes and before Discovered Tasks"
    else
        fail "B06: Open Questions positioned after Blockers/Notes and before Discovered Tasks" \
            "line numbers: blockers=$blockers_line open_q=$open_q_line discovered=$discovered_line"
    fi
}

# Test: Open Questions carries a '{...}' guidance hint and a '-' bullet, the
# same style as sibling sections (e.g. Implementation Log).
test_b06_open_questions_hint_and_bullet_style() {
    local tmpl="$PLUGIN_ROOT/templates/TODO.md"
    local section
    section=$(sed -n '/^## Open Questions$/,/^## Discovered Tasks$/p' "$tmpl")
    local hint_ok=no bullet_ok=no
    printf '%s\n' "$section" | grep -qE '^\{.*\}$' && hint_ok=yes
    printf '%s\n' "$section" | grep -qE '^-[[:space:]]*$' && bullet_ok=yes
    if [ "$hint_ok" = yes ] && [ "$bullet_ok" = yes ]; then
        pass "B06: Open Questions has a {...} guidance hint line and a '-' bullet"
    else
        fail "B06: Open Questions has a {...} guidance hint line and a '-' bullet" \
            "hint_ok=$hint_ok bullet_ok=$bullet_ok"
    fi
}

# Test: the NotImplemented placeholder comment is gone once implemented.
test_b06_notimplemented_placeholder_gone() {
    if grep -q 'NotImplemented: B06' "$PLUGIN_ROOT/templates/TODO.md"; then
        fail "B06: NotImplemented placeholder comment removed once implemented" "placeholder still present"
    else
        pass "B06: NotImplemented placeholder comment removed once implemented"
    fi
}

# Test: the injected rules text instructs agents to park unresolved threads
# in Open Questions in real time and clear entries once resolved. Uses a wd
# with no .local/ dir at all, since the rules heredoc is unconditional (fires
# on any SessionStart, independent of TODO.md/auto-create/resume state).
test_b06_rules_mention_open_questions() {
    local wd="$TMPROOT/b06-rules"
    mkdir -p "$wd"
    local output ctx
    output=$(run_hook "$wd")
    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
    local ok=no
    if printf '%s' "$ctx" | grep -qi 'open questions' \
        && printf '%s' "$ctx" | grep -qiE 'real[- ]time' \
        && printf '%s' "$ctx" | grep -qiE 'clear.{0,60}resolved|resolved.{0,60}clear'; then
        ok=yes
    fi
    if [ "$ok" = yes ]; then
        pass "B06: injected rules instruct parking unresolved threads in Open Questions and clearing on resolution"
    else
        fail "B06: injected rules instruct parking unresolved threads in Open Questions and clearing on resolution" \
            "context: $ctx"
    fi
}

# --- 003-B21: work-graph authoring defaults + the linked-artifact rule ---
#
# Contract: the "Contract: 003-B21 authoring defaults recorded — tracking
# half" bash comment above the rules heredoc in session-context.sh (plan
# 003-followup-fixes, issue #333). The injected prose must state the three
# authoring defaults recorded in docs/protocols/work-graph.md — plain-
# language node titles embedding no foreign id scheme; one node per ACTUAL
# work item, so distinct phases worked by distinct actors get distinct nodes
# with their own dependency edges; a follow-up captured mid-effort gets a
# graph node AT CAPTURE with its disposition mirrored onto that node — and
# the injected decision-file instruction must additionally require every
# artifact a decision document references to be carried as a RELATIVE
# markdown link, never a bare path.
#
# Asserted against the hook's OUTPUT, not against session-context.sh's text.
# The 003-B21 contract comment restates every clause below almost verbatim,
# so a grep over the script would pass against the comment alone on the
# unimplemented stub; comments are never emitted, so an output assertion is
# immune to that by construction. Every pattern below was checked against
# today's injected context first — none of them match.
#
# The rules heredoc is unconditional (it fires on any SessionStart, with or
# without .local/), so these fixtures use a bare directory, mirroring
# test_b06_rules_mention_open_questions.
#
# Three 003-B21 clauses are covered by assertions that already exist
# elsewhere rather than duplicated here:
#   - Outputs "the FOLLOWUPS machine-read injection contract further down
#     this file is unchanged": followups-capture.test.sh pins the exact
#     '# Open follow-ups (N)' header, the per-entry lines, and the
#     empty-output cases.
#   - Invariants "the injection structure and ordering are unchanged":
#     workgraph-capture.test.sh's test_b03_wiring_order_all_four_blocks pins
#     the rules -> resume -> follow-ups -> work-graph assembly order.
#   - "plugin.json 0.8.0 -> 0.9.0 with the root README tracking version cell
#     in step": version-bump-lint and readme-lint enforce that pairing
#     mechanically. No new assertion pins the literal here; the three
#     pre-existing pins elsewhere in the tracking suites are retargeted to
#     0.9.0 in lockstep, as every prior tracking bump has done.

# Runs the hook in a bare directory and echoes the injected context flattened
# to one line. The prose is hard-wrapped, so a proximity regex's two halves
# routinely land on different source lines; grep matches per physical line.
b21_flat_context() { # fixture-name
    local wd="$TMPROOT/$1"
    mkdir -p "$wd"
    run_hook "$wd" \
        | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null \
        | tr '\n' ' '
}

# Test: the injected rules state the three work-graph authoring defaults.
test_b21_rules_state_authoring_defaults() {
    local ctx
    ctx=$(b21_flat_context b21-defaults)

    # Default 1 — plain-language titles, no foreign id scheme.
    assert_contains_re_i "B21: injected rules state node titles are plain language" "$ctx" \
        'titles?[^.]{0,80}plain[ -]language|plain[ -]language[^.]{0,80}titles?'
    assert_contains_re_i "B21: injected rules state N<NN> is the only identifier a title needs" "$ctx" \
        'only[[:space:]]+identifier'
    assert_contains_re_i "B21: injected rules exclude other numbering systems from titles" "$ctx" \
        'numbering[[:space:]]+systems?|(other|another|foreign)[^.]{0,40}(numbering|id scheme)'
    assert_contains_re_i "B21: injected rules put those ids in Notes: or the artifacts that own them" "$ctx" \
        'notes[^.]{0,140}(own|belong)|(own|belong)[^.]{0,140}notes'

    # Default 2 — one node per ACTUAL work item.
    assert_contains_re_i "B21: injected rules state one node per ACTUAL work item" "$ctx" \
        '(one|a)[[:space:]]+node[[:space:]]+per[^.]{0,40}work[[:space:]]+item'
    assert_contains_re_i "B21: injected rules state distinct phases are worked by distinct actors" "$ctx" \
        'phases?[^.]{0,140}actors?|actors?[^.]{0,140}phases?'
    assert_contains_re_i "B21: injected rules give each such phase its own node" "$ctx" \
        'own[[:space:]]+node'
    assert_contains_re_i "B21: injected rules give each such phase its own dependency edge" "$ctx" \
        'own[^.]{0,30}(dependency|dep\b|deps\b)'

    # Default 3 — a follow-up gets a graph node at capture, mirrored on resolve.
    assert_contains_re_i "B21: injected rules give a mid-effort follow-up a graph node" "$ctx" \
        'node[^.]{0,120}follow-?up|follow-?up[^.]{0,120}node'
    assert_contains_re_i "B21: injected rules add that node AT CAPTURE" "$ctx" \
        'at[[:space:]]+captur|moment[^.]{0,40}captur|when[^.]{0,30}captur'
    assert_contains_re_i "B21: injected rules mirror the follow-up's disposition onto that node" "$ctx" \
        'mirror[^.]{0,140}node|node[^.]{0,140}mirror'
}

# Test: the injected decision-file instruction requires a relative markdown
# link to every artifact the decision document references (the F08 authoring
# half of this contract).
test_b21_rules_require_relative_artifact_links() {
    local ctx
    ctx=$(b21_flat_context b21-links)

    assert_contains_re_i "B21/F08: injected rules require a relative markdown link" "$ctx" \
        'relative[^.]{0,40}link|markdown[[:space:]]+link[^.]{0,40}relative'
    assert_contains_re_i "B21/F08: the link resolves from the decision file's own directory" "$ctx" \
        'resolvable|decision[^.]{0,30}director'
    assert_contains_re_i "B21/F08: a bare path is not acceptable" "$ctx" \
        'bare[[:space:]]+path'
    assert_contains_re_i "B21/F08: the rule covers every artifact the decision document references" "$ctx" \
        'artifact|referenced[[:space:]]+(document|file|path)'
}

# Test (invariant): the new prose stays capability-phrased — it names no
# plugin.
#
# This cannot be a blanket "no plugin is named" scan. The injected context
# necessarily carries real `plugins/tracking/templates/...` paths (the hook
# points agents at template files that genuinely live there), the rules
# header reads "# Tracking (clam tracking plugin)", and the decision-file
# instruction already cites a skill id — all pre-existing, none in this
# contract's scope. What IS checkable, and is the leak this contract invites
# — "ids from other numbering systems" is exactly where a block/unit id
# scheme would get named after its plugin — is that no OTHER plugin id
# appears. The list is restricted to ids with no ordinary-English sense, so
# a match is necessarily a plugin reference and never innocent prose.
# Green at birth by design: it is a regression guard on the new prose, not a
# red-until-implemented behavior assertion.
#
# The scan must be path-independent: the hook embeds absolute template paths
# under this checkout's own root, so a checkout whose directory name contains
# a plugin id (a `lego/...` unit worktree, an `orchestrate-statusline-*`
# branch checkout) would otherwise leak that id into the scanned text and
# fail on prose that never named any plugin. Scrub the checkout root before
# scanning; the ids being guarded against can only appear in the injected
# PROSE, which the scrub never touches.
test_b21_rules_name_no_other_plugin() {
    local ctx name found="" repo_root
    repo_root="$(cd "$PLUGIN_ROOT/../.." && pwd)"
    ctx=$(b21_flat_context b21-noplugin)
    ctx=${ctx//"$repo_root"/[repo-root]}
    for name in lego render-doc ask-in-text orchestrator-handover session-data \
        skill-tracker statusline worktrees; do
        if printf '%s' "$ctx" | grep -qiE -- "\\b${name}\\b"; then
            found="$name"
            break
        fi
    done
    if [ -z "$found" ]; then
        pass "B21: the injected rules name no other plugin"
    else
        fail "B21: the injected rules name no other plugin" "found '$found' in the injected context"
    fi
}

# Test (acceptance): the 003-B21 scaffolding contract comment is gone from
# session-context.sh once the block lands.
test_b21_contract_comment_removed() {
    if grep -qF -- "Contract: 003-B21" "$HOOK" 2>/dev/null; then
        fail "B21: the 'Contract: 003-B21' scaffolding comment has been removed from session-context.sh" \
            "still present"
    else
        pass "B21: the 'Contract: 003-B21' scaffolding comment has been removed from session-context.sh"
    fi
}

# --- Run all tests ---
test_auto_create_when_local_exists
test_auto_create_has_state
test_no_overwrite
test_noop_without_local
test_noop_without_template
test_date_substitution
test_branch_substitution
test_auto_create_triggers_resume
test_resume_existing_todo
test_clears_epoch_markers

# B04
test_b04_stale_variant
test_b04_fresh_todo_touched_after_prompts
test_b04_fresh_current_session_excluded
test_b04_fresh_gate_disabled
test_b04_fresh_threshold_raised
test_b04_fresh_bounded_to_newest_five
test_b04_fresh_no_project_dir
test_b04_fresh_auto_created_todo
test_b04_clears_freshness_marker

# B06
test_b06_template_has_open_questions_header
test_b06_open_questions_ordering
test_b06_open_questions_hint_and_bullet_style
test_b06_notimplemented_placeholder_gone
test_b06_rules_mention_open_questions

# 003-B21
test_b21_rules_state_authoring_defaults
test_b21_rules_require_relative_artifact_links
test_b21_rules_name_no_other_plugin
test_b21_contract_comment_removed

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
