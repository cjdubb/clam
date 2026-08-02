#!/bin/bash
# Tests for keep-working.sh's turn-end block-reason text (B01 —
# turn-end-state-guidance): the "Contract: B01 — turn-end-state-guidance
# (plan 001)" docblock above the `reason=` assignment (~line 704), governing
# that assignment and the `state_parked_list` call feeding it.
#
# Today the reason hardcodes every parked State into a single "resumes on
# its own with no user action" line — including Awaiting User Review, which
# the manifest (lib/states.tsv) actually marks summons=yes — and its
# Complete line still carries forge vocabulary ("an open PR still needs a
# monitoring cron"). B01 makes the summoning/non-summoning split DERIVE from
# state_summons rather than a literal name, and drops the forge vocabulary.
#
# Black-box: drives the WHOLE Stop hook via stdin JSON ({"cwd":...,
# "session_id":...,"stop_hook_active":...}), matching freshness-gate.test.sh
# and no-todo-nudge.test.sh's style for this same script. Asserts on stdout
# (empty = allow; {"decision":"block","reason":...} = block), exit code, and
# the $CLAUDE_STOP_LOG disposition.
#
# Manifest substitution: clauses that must be proven DERIVED rather than
# hardcoded (the summons split, both empty-partition edges) drive the hook
# through a SHADOW tree — scripts/keep-working.sh and lib/states.sh
# symlinked unchanged, lib/states.tsv replaced with a real substituted file
# living entirely under $TMPROOT — mirroring the shadow-tree technique
# already used elsewhere for this same lib/states.sh. The committed
# lib/states.tsv is never touched. A second
# shadow (build_shadow_no_summons) pairs the REAL committed manifest with a
# lib/states.sh that never defines state_summons at all, for the fail-safe
# Errors clause.
#
# Hermetic: mktemp worktrees with a baseline commit (belt-and-braces,
# matching the sibling keep-working.sh tests — every fixture also writes
# .local/TODO.md directly, which is what actually short-circuits the
# no-todo nudge). No .local/PLAN.md is ever created, so the plan gate stays
# quiet. No network: every case below drives the block-with-reason path
# directly (State In Progress / Not Started, or an unrecognised/empty
# State), which never reaches the PR-cron or independent-review backstops.
#
# Run: bash plugins/tracking/scripts/keep-working.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/keep-working.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$PLUGIN_ROOT/lib/states.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

FAILED=0
OUT=""
EXIT=0
LOG=""
LOG_SEQ=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }

# --- Worktree / fixture builders --------------------------------------------

# A fresh worktree with one baseline commit and a .local/ dir.
make_wt() { # -> echoes path
    local wt
    wt=$(mktemp -d "$TMPROOT/wt-XXXXXX")
    mkdir -p "$wt/.local"
    git init -q "$wt" >/dev/null 2>&1
    git -C "$wt" config user.email test@example.com
    git -C "$wt" config user.name test
    printf 'baseline\n' > "$wt/baseline.txt"
    git -C "$wt" -c commit.gpgsign=false add -A >/dev/null 2>&1
    git -C "$wt" -c commit.gpgsign=false commit -q -m init >/dev/null 2>&1
    printf '%s' "$wt"
}

write_todo() { # wt state
    printf 'State: %s\nCurrent Task: doing the thing\nLast Updated: 2026-01-01 00:00\n' "$2" > "$1/.local/TODO.md"
}

# --- Shadow-tree manifest substitution --------------------------------------

# build_shadow_manifest(tsv_body) -> echoes a shadow copy of keep-working.sh
# wired to a SUBSTITUTED lib/states.tsv (a real file under $TMPROOT, not the
# committed manifest) so state_summons / state_parked_list resolve against
# it. keep-working.sh and lib/states.sh are symlinked unchanged; only the
# manifest data differs. Never touches the committed lib/states.tsv.
build_shadow_manifest() { # tsv_body -> echoes hook path
    local dir
    dir=$(mktemp -d "$TMPROOT/shadow-manifest-XXXXXX")
    mkdir -p "$dir/scripts" "$dir/lib"
    ln -s "$HOOK" "$dir/scripts/keep-working.sh"
    ln -s "$PLUGIN_ROOT/lib/states.sh" "$dir/lib/states.sh"
    printf '%s' "$1" > "$dir/lib/states.tsv"
    printf '%s/scripts/keep-working.sh' "$dir"
}

# build_shadow_no_summons() -> echoes a shadow copy of keep-working.sh paired
# with the REAL, symlinked committed lib/states.tsv but a lib/states.sh that
# never defines state_summons at all — simulating "state_summons is
# unavailable" for the contract's fail-safe Errors clause.
build_shadow_no_summons() { # -> echoes hook path
    local dir
    dir=$(mktemp -d "$TMPROOT/shadow-no-summons-XXXXXX")
    mkdir -p "$dir/scripts" "$dir/lib"
    ln -s "$HOOK" "$dir/scripts/keep-working.sh"
    ln -s "$PLUGIN_ROOT/lib/states.tsv" "$dir/lib/states.tsv"
    cat > "$dir/lib/states.sh" <<'EOF'
#!/bin/bash
_CLAM_STATES_TSV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/states.tsv"
todo_field() {
    grep -m1 -E "^[*]{0,2}$2:" "$1" 2>/dev/null \
        | sed -E "s/^[*]{0,2}$2:[*]{0,2}[[:space:]]*//; s/[[:space:]]*\$//"
}
state_category() {
    awk -F'\t' -v s="$1" '/^#/ {next} $1 == s {print $2; exit}' "$_CLAM_STATES_TSV"
}
state_is_parked() {
    [ "$(state_category "$1")" = "parked" ]
}
state_parked_list() {
    awk -F'\t' '/^#/ {next} $2 == "parked" {print $1}' "$_CLAM_STATES_TSV"
}
state_names() {
    awk -F'\t' '/^#/ {next} NF {print $1}' "$_CLAM_STATES_TSV"
}
EOF
    printf '%s/scripts/keep-working.sh' "$dir"
}

# --- Hook driver --------------------------------------------------------------

# Runs the hook with a clean env (the freshness/PR/independent-review/
# followups tunables are unset first so nothing leaks in from the
# surrounding session) and a fresh per-call $CLAUDE_STOP_LOG so this run's
# log disposition can be read back unambiguously.
run_raw() { # json hook_path [env assignments...]
    local json="$1" hook="$2"; shift 2
    LOG="$TMPROOT/logs/log-$((LOG_SEQ++)).jsonl"
    mkdir -p "$(dirname "$LOG")"
    OUT=$(printf '%s' "$json" | env \
        -u CLAM_TRACKING_STOP_GATE \
        -u CLAM_TRACKING_FRESHNESS_GATE \
        -u CLAM_TRACKING_FRESHNESS_THRESHOLD \
        -u CLAM_PR_CRONS \
        -u CLAM_INDEPENDENT_REVIEW \
        -u CLAM_FOLLOWUPS_GATE \
        CLAUDE_STOP_LOG="$LOG" \
        "$@" bash "$hook" 2>"$TMPROOT/stderr-last")
    EXIT=$?
}
run() { # wt hook [env assignments...]
    local wt="$1" hook="$2"; shift 2
    run_raw "$(jq -n --arg cwd "$wt" '{cwd:$cwd, session_id:"s1", stop_hook_active:false}')" "$hook" "$@"
}

# --- Assertions ---------------------------------------------------------------

assert_allow() { # label
    if [[ -z "$OUT" ]]; then pass "$1"; else fail "$1: expected allow (empty stdout), got: $OUT"; fi
}
assert_block() { # label
    if [[ -n "$OUT" ]] && printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass "$1"
    else
        fail "$1: expected block decision JSON, got: $OUT"
    fi
}
reason_of() { printf '%s' "$OUT" | jq -r '.reason // empty' 2>/dev/null; }
assert_reason_matches() { # label regex(extended, case-insensitive)
    if printf '%s' "$(reason_of)" | grep -qiE "$2"; then
        pass "$1"
    else
        fail "$1: reason missing pattern '$2' (got: $(reason_of))"
    fi
}
assert_reason_not_matches() { # label regex(extended, case-insensitive)
    if printf '%s' "$(reason_of)" | grep -qiE "$2"; then
        fail "$1: reason unexpectedly matches '$2' (got: $(reason_of))"
    else
        pass "$1"
    fi
}
# Byte-exact (case-sensitive) literal substring checks — the message itself
# claims State names "must match EXACTLY", so these must not fold case.
assert_reason_contains() { # label literal-substring
    if [[ "$(reason_of)" == *"$2"* ]]; then
        pass "$1"
    else
        fail "$1: reason missing literal '$2' (got: $(reason_of))"
    fi
}
assert_reason_not_contains() { # label literal-substring
    if [[ "$(reason_of)" == *"$2"* ]]; then
        fail "$1: reason unexpectedly contains literal '$2' (got: $(reason_of))"
    else
        pass "$1"
    fi
}
# First physical line of the reason containing $1 (empty if none) — used to
# prove a State name lands in the RIGHT partition, not merely somewhere.
line_with() { printf '%s\n' "$(reason_of)" | grep -F "$1" | head -1; }
assert_line_contains() { # label outer_substr inner_substr
    local line
    line=$(line_with "$2")
    if [[ -n "$line" && "$line" == *"$3"* ]]; then
        pass "$1"
    else
        fail "$1: line containing '$2' missing '$3' (line: '$line')"
    fi
}
assert_line_not_contains() { # label outer_substr inner_substr
    local line
    line=$(line_with "$2")
    if [[ -z "$line" || "$line" != *"$3"* ]]; then
        pass "$1"
    else
        fail "$1: line containing '$2' unexpectedly has '$3' (line: '$line')"
    fi
}
# Regex (extended, case-insensitive) sibling of assert_line_contains, for
# asserting a SEMANTIC cue on the line naming a State rather than a literal
# substring — used where the contract leaves the exact wording to the
# implementer and only the meaning is fixed.
assert_line_matches() { # label outer_substr regex(extended, case-insensitive)
    local line
    line=$(line_with "$2")
    if [[ -n "$line" ]] && printf '%s' "$line" | grep -qiE "$3"; then
        pass "$1"
    else
        fail "$1: line containing '$2' missing pattern '$3' (line: '$line')"
    fi
}
# Case-insensitive, whole-word match for forge vocabulary, so "PR" inside
# another word (e.g. a hypothetical "APRIL") can't produce a false failure.
assert_no_forge_vocab() { # label
    local r
    r=$(reason_of)
    if printf '%s' "$r" | grep -qiE '\bPR\b|\bpull request\b|\bmerge request\b|\bdraft\b|\bgh\b'; then
        fail "$1 (got: $r)"
    else
        pass "$1"
    fi
}
# Guards against a label rendered with an empty list — e.g. "  - Parked,
# summons the user once on entry:" with nothing after the colon — no matter
# what the implementer calls that label. Anchored on the bullet-item shape
# ("  - ...:") so header lines that legitimately end in a bare colon (e.g.
# "States that END the turn (these must match EXACTLY):") are not mistaken
# for it.
assert_no_empty_list_line() { # label
    local hit
    hit=$(printf '%s\n' "$(reason_of)" | grep -E '^[[:space:]]*-.*:[[:space:]]*$')
    if [[ -n "$hit" ]]; then
        fail "$1: found a label with an empty list: '$hit'"
    else
        pass "$1"
    fi
}
assert_exit0() { if [[ "$EXIT" -eq 0 ]]; then pass "$1"; else fail "$1: exit code $EXIT"; fi; }
# Reads the LAST log line's "decision" field (the disposition string
# log_stop was called with) out of $1 and compares to $2.
assert_log_disposition() { # log expected_disposition label
    local log="$1" expected="$2" label="$3" got=""
    [[ -f "$log" ]] && got=$(jq -rs 'map(.decision) | last // empty' "$log" 2>/dev/null)
    if [[ "$got" == "$expected" ]]; then pass "$label"; else fail "$label: expected disposition '$expected', got '$got' (log: $log)"; fi
}
# Mirrors the script's own label scheme (case "Awaiting Agent" -> tr 'A-Z '
# 'a-z_') so expectations can't silently drift from the code under test.
expected_allow_label() { printf 'allow_state_%s' "$(printf '%s' "$1" | tr 'A-Z ' 'a-z_')"; }

echo "--- Invariant: the ALLOW/BLOCK decision is unchanged, one State per category ---"

# active: still blocks (both active States, since In Progress and Not
# Started share the same "falls through to the reason block" path).
wt=$(make_wt)
write_todo "$wt" "In Progress"
run "$wt" "$HOOK"
assert_block "active State (In Progress): still BLOCKS"
assert_exit0 "active State (In Progress): exit 0"
assert_log_disposition "$LOG" "block" "active State (In Progress): log disposition is the generic 'block'"

wt=$(make_wt)
write_todo "$wt" "Not Started"
run "$wt" "$HOOK"
assert_block "active State (Not Started): still BLOCKS"

# parked, summons=yes: the flagship state this whole block is about. It must
# still permit ending the turn — that path runs through state_is_parked well
# above the B01 region and must not be touched by the message rewrite.
wt=$(make_wt)
write_todo "$wt" "Awaiting User Review"
run "$wt" "$HOOK"
assert_allow "the flagship summoning parked State (Awaiting User Review) still PERMITS ending the turn"
assert_exit0 "Awaiting User Review: exit 0"
assert_log_disposition "$LOG" "$(expected_allow_label "Awaiting User Review")" "Awaiting User Review: log disposition unchanged"

# parked, summons=no: a representative non-summoning parked State.
wt=$(make_wt)
write_todo "$wt" "Awaiting Agent"
run "$wt" "$HOOK"
assert_allow "a non-summoning parked State (Awaiting Agent) still permits ending the turn"
assert_log_disposition "$LOG" "$(expected_allow_label "Awaiting Agent")" "Awaiting Agent: log disposition unchanged"

# needs_user: unaffected regression coverage.
wt=$(make_wt)
write_todo "$wt" "Blocked"
run "$wt" "$HOOK"
assert_allow "needs_user State (Blocked) still permits ending the turn"
assert_log_disposition "$LOG" "allow_state_blocked" "Blocked: log disposition unchanged"

# terminal: unaffected regression coverage (no PR configured -> no-op backstops).
wt=$(make_wt)
write_todo "$wt" "Complete"
run "$wt" "$HOOK"
assert_allow "terminal State (Complete, no PR configured) still permits ending the turn"
assert_log_disposition "$LOG" "allow_state_complete" "Complete: log disposition unchanged"

echo "--- No forge vocabulary in the emitted reason ---"

# The current stub's Complete line reads "an open PR still needs a
# monitoring cron" — a whole-word "PR" — so this is expected to fail red
# until the Complete line is rewritten.
wt=$(make_wt)
write_todo "$wt" "In Progress"
run "$wt" "$HOOK"
assert_block "In Progress: blocks (baseline for the forge-vocab check)"
assert_no_forge_vocab "reason has no forge vocabulary (PR / pull request / merge request / draft / gh) as whole words"

echo "--- The defect (#38): Awaiting User Review's guidance against the REAL manifest ---"

# lib/states.tsv line 13 is the only parked row marked summons=yes
# (Awaiting User Review). This drives the REAL, committed manifest — not a
# substituted one — through the full-render path, so issue #38's defect is
# encoded directly rather than only inferred from the synthetic
# mixed-manifest case below.
wt=$(make_wt)
write_todo "$wt" "In Progress"
run "$wt" "$HOOK"
assert_block "real manifest: In Progress still blocks (baseline for the #38 checks below)"
assert_line_not_contains "real manifest: Awaiting User Review is NOT on the 'resumes on its own' line (#38)" "Awaiting User Review" "resumes on its own"
assert_line_matches "real manifest: Awaiting User Review's guidance states the entry condition (waiting on the user's review), forge-neutral" "Awaiting User Review" 'wait(ing|s)? (on|for) the user|user (is|to|must|needs to) review|before (it|the (session|turn)) can (proceed|continue)|pending (the )?users? review'

echo "--- Unrecognised / empty State: full render, near-miss self-correction ---"

# A typo/renamed State and a genuinely empty State field both land on this
# same block-with-reason path (the near-miss self-correction case). The
# message must still render in FULL: every parked State from the real
# manifest listed byte-for-byte, and both other ending-State categories
# still named.
wt=$(make_wt)
write_todo "$wt" "Awaiting Reviewwww"
run "$wt" "$HOOK"
assert_block "unrecognised State (typo): blocks"
assert_reason_matches "unrecognised State: reason still names Complete as a valid ending State" "Complete"
assert_reason_matches "unrecognised State: reason still names Blocked as a valid ending State" "Blocked"
while IFS= read -r pstate; do
    [[ -n "$pstate" ]] || continue
    assert_reason_contains "unrecognised State: '$pstate' still rendered byte-exact" "$pstate"
done < <(state_parked_list)
assert_no_forge_vocab "unrecognised State: reason still has no forge vocabulary"

wt=$(make_wt)
write_todo "$wt" ""
run "$wt" "$HOOK"
assert_block "empty State: blocks"
while IFS= read -r pstate; do
    [[ -n "$pstate" ]] || continue
    assert_reason_contains "empty State: '$pstate' still rendered byte-exact" "$pstate"
done < <(state_parked_list)

echo "--- Fail-safe: state_summons unavailable still lists every parked State (regression) ---"

# A lib/states.sh missing state_summons entirely, paired with the REAL
# committed lib/states.tsv (symlinked, untouched). The contract's Errors
# clause requires the message to still list every parked State in this case
# — degrading to today's single-line form is acceptable. Today's stub never
# calls state_summons at all, so this already passes: regression coverage,
# not new B01 behavior (see report).
shadow_hook=$(build_shadow_no_summons)
wt=$(make_wt)
write_todo "$wt" "In Progress"
run "$wt" "$shadow_hook"
assert_block "state_summons unavailable: In Progress still blocks"
while IFS= read -r pstate; do
    [[ -n "$pstate" ]] || continue
    assert_reason_contains "state_summons unavailable: '$pstate' still listed byte-exact" "$pstate"
done < <(state_parked_list)

echo "--- Derived, not hardcoded: the summoning split follows the manifest ---"

# "Zzz Custom Summoner" (parked, summons=yes) and "Aaa Custom Resumer"
# (parked, summons=no) share nothing with "Awaiting User Review" or any name
# the current stub could have hardcoded. A hardcoded check for the literal
# "Awaiting User Review" string would treat BOTH as non-summoning here and
# print them on the SAME "resumes on its own" line — only a derivation from
# state_summons over this substituted manifest can tell them apart.
mixed_tsv=$(printf 'Zzz Custom Summoner\tparked\tZ\t1\tyes\nAaa Custom Resumer\tparked\tA\t1\tno\n')
shadow_hook=$(build_shadow_manifest "$mixed_tsv")
wt=$(make_wt)
write_todo "$wt" "In Progress"
run "$wt" "$shadow_hook"
assert_block "mixed substituted manifest: In Progress still blocks"
assert_reason_contains "mixed manifest: summoning custom name appears byte-exact" "Zzz Custom Summoner"
assert_reason_contains "mixed manifest: non-summoning custom name appears byte-exact" "Aaa Custom Resumer"
assert_line_contains "mixed manifest: non-summoning name is on the 'resumes on its own' line" "Aaa Custom Resumer" "resumes on its own"
assert_line_not_contains "mixed manifest: summoning name is NOT on the 'resumes on its own' line (derived, not hardcoded)" "Zzz Custom Summoner" "resumes on its own"

echo "--- Both empty-partition edge cases ---"

# Every parked State summons: the "resumes on its own" framing (quoted
# verbatim in the contract) must be omitted ENTIRELY, not printed empty.
all_summon_tsv=$(printf 'Alpha One\tparked\tx\t1\tyes\nAlpha Two\tparked\tx\t1\tyes\n')
shadow_hook=$(build_shadow_manifest "$all_summon_tsv")
wt=$(make_wt)
write_todo "$wt" "In Progress"
run "$wt" "$shadow_hook"
assert_block "all-summon manifest: In Progress still blocks"
assert_reason_contains "all-summon manifest: 'Alpha One' still listed byte-exact" "Alpha One"
assert_reason_contains "all-summon manifest: 'Alpha Two' still listed byte-exact" "Alpha Two"
assert_reason_not_contains "all-summon manifest: 'resumes on its own' framing is omitted entirely (no parked State qualifies)" "resumes on its own"
# Second guard (symmetric with the all-no-summon fixture below): the names
# must land somewhere, not on a summoning label printed with an empty list.
assert_no_empty_list_line "all-summon manifest: no label renders with an empty list (guard)"

# No parked State summons: every parked name still renders, all under the
# (sole remaining) "resumes on its own" framing. This is the shape today's
# stub already produces for this degenerate case, so it is regression
# coverage rather than a new red assertion (see report) — the general,
# non-degenerate split is proven red by the mixed-manifest case above.
all_no_summon_tsv=$(printf 'Beta One\tparked\tx\t1\tno\nBeta Two\tparked\tx\t1\tno\n')
shadow_hook=$(build_shadow_manifest "$all_no_summon_tsv")
wt=$(make_wt)
write_todo "$wt" "In Progress"
run "$wt" "$shadow_hook"
assert_block "all-no-summon manifest: In Progress still blocks"
assert_line_contains "all-no-summon manifest: 'Beta One' is on the 'resumes on its own' line" "Beta One" "resumes on its own"
assert_line_contains "all-no-summon manifest: 'Beta Two' is on the 'resumes on its own' line" "Beta Two" "resumes on its own"
# The edge case this fixture is actually meant to prove: the summoning label
# is omitted ENTIRELY when no parked State qualifies, not printed with an
# empty list. There's no contract-quoted phrase to assert absence of (unlike
# "resumes on its own" above), so this checks the shape directly: no label
# line ends in a bare colon with nothing after it, whatever the implementer
# calls that label. Passes today (today's stub never emits a second label at
# all here) — a guard for a specific bad implementation, not defect evidence.
assert_no_empty_list_line "all-no-summon manifest: the summoning label is omitted entirely rather than printed with an empty list"

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "ALL PASS"
else
    echo "FAILURES"
fi
exit "$FAILED"
