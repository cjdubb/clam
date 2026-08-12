#!/bin/bash
# Tests for B06 workgraph-docs: README.md documents the work-graph feature
# wherever the sibling follow-ups feature is documented (the "Contract: B06
# workgraph-docs" HTML-comment docblock near the top of
# plugins/tracking/README.md is the source of truth), plugin.json is bumped
# 0.6.3 -> 0.7.0 with a description update, and make-progress's SKILL.md
# step-2 list gains an explicit WORKGRAPH.md row after the FOLLOWUPS.md one.
#
# Content-presence tests, not exact-prose pins: wording is not contracted
# verbatim (only the plugin.json version number and a couple of literal
# machine-read markers are), so assertions are flexible token/proximity
# regexes on the load-bearing facts — mirroring
# plugins/tracking/scripts/followups-docs.test.sh's approach for the
# analogous B05 follow-ups-docs-and-version contract.
#
# Comment-stripped inputs: README.md is read through a
# `sed '/<!--/,/-->/d'` pass before any content check, same technique the
# followups-docs precedent uses — the B06 contract comment itself contains
# most of the load-bearing tokens ("CLAM_WORKGRAPH_GATE", "Focus:",
# "docs/protocols/work-graph.md", "Goal/Status/Parent/Deps", ...), so an
# unstripped read would let every check pass against the CONTRACT COMMENT
# alone on the still-unimplemented stub, defeating the point of a red run.
# SKILL.md carries no such comment today, so it is read raw.
#
# Explicitly OUT of scope (documented rather than silently skipped):
#   - A blanket "no other plugin is named" invariant check (the contract's
#     own Invariants section states this) is NOT implemented as a general
#     scan over the edited README sections. Unlike B01/B02's protocol/
#     template documents (docs/protocols/work-graph.md,
#     templates/WORKGRAPH.md — see workgraph-template.test.sh), which are
#     genuinely clean of other-plugin references, the "## What to expect",
#     "### Library files", and "## Uninstalling" sections of THIS README
#     already legitimately contain "statusline", "notifications", and
#     "settings" (both a real sibling-plugin integration and, separately,
#     ordinary English words like "a settings file" / "worktrees") before
#     B06 touches them at all — a blanket scan over those sections would
#     fail against content this contract explicitly leaves unchanged,
#     which is the opposite of what the invariant is for. The narrower,
#     safely-isolatable pieces of this invariant ARE checked directly:
#     the new templates/WORKGRAPH.md library-files bullet and the new
#     plugin.json description text are each checked for the literal
#     tracking-only vocabulary the contract specifies, and nothing in
#     either assertion set below accepts a competing plugin name as a
#     substitute match.
#   - The "list orders" and "gate semantics" agreement invariant (README
#     must agree with B01/B02/B03/B04/B05) is covered indirectly: the
#     marker strings and env var default/disable semantics asserted below
#     are the same literal strings docs/protocols/work-graph.md,
#     keep-working.sh (check_workgraph_closeout), and session-context.sh
#     (_workgraph_surfacing) actually use, extracted by reading those
#     files during test authorship rather than re-derived here at runtime
#     (a runtime cross-file diff, as workgraph-template.test.sh's
#     "Agreement block" does for B01 vs B02, was judged unnecessary
#     complexity for a docs-only contract with no second machine-read
#     artifact to diff against).
#
# Hermetic: reads only files at fixed repo locations (resolved from this
# script's own path) into a mktemp scratch dir, plus one subshelled
# execution of scripts/readme-lint.sh from the repo root (read-only lint,
# no mutation). No network.
#
# Run: bash plugins/tracking/scripts/workgraph-docs.test.sh
#      (exits non-zero on failure)

# <!--
# Contract: B06 mid-tier-test-defork (plan 001-speed-up-repo-ci)
#
# Behavior:
#   This file's ASSERTIONS are frozen; only its cost may change. It is the
#   ODD ONE OUT among the slow tests: 11.1s from only 219 process spawns,
#   against 22,787 read syscalls and 544 clones. Its cost is bash userspace
#   and repeated document reads, NOT fork overhead, so the de-forking
#   technique that fixes the lego giants does not apply here. Read each
#   document once into a variable and reuse it; do not re-read or re-parse
#   the same file per assertion.
#
# Inputs:  unchanged.
# Outputs: unchanged — 75 PASS lines, then "All tests passed."
#
# Invariants:
#   - Exactly 75 PASS lines and a zero exit. A changed count is a defect,
#     whichever direction it moves.
#   - No assertion may be weakened, skipped, merged, or deleted.
#   - Runtime target: under 3s (from 11.1s). This is an ACCEPTANCE target
#     verified by the orchestrator, NOT a wall-clock assertion inside the
#     test — a stopwatch threshold in a test file flakes on slower machines
#     and is forbidden throughout plan 001.
#
# Edge cases:
#   - Fixtures that genuinely need a fresh read per test must keep it; the
#     invariant is "no redundant reads", not "one read".
# -->
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

README="$PLUGIN_ROOT/README.md"
SKILL="$PLUGIN_ROOT/skills/make-progress/SKILL.md"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
README_LINT="$REPO_ROOT/scripts/readme-lint.sh"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }
check() { # label got expected
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got '$2', expected '$3'"; fi
}

for f in "$README" "$SKILL" "$PLUGIN_JSON" "$README_LINT"; do
    if [ ! -f "$f" ]; then
        fail "required file exists" "not found at $f"
        echo ""
        echo "Some tests FAILED."
        exit 1
    fi
done

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Comment-stripped copy — see file header for why this matters.
STRIPPED_README="$TMPROOT/README.stripped.md"
sed '/<!--/,/-->/d' "$README" > "$STRIPPED_README"

# assert_contains_re_i <label> <haystack> <ERE, case-insensitive>
# Flattens embedded newlines to spaces first: grep matches per physical
# line by default, but hard-wrapped markdown prose often lands a
# proximity regex's two halves on different source lines.
assert_contains_re_i() {
    local flat
    flat=$(printf '%s' "$2" | tr '\n' ' ')
    # LC_ALL=C: glibc's regex engine takes a dramatically slower multibyte
    # code path for bounded-repetition EREs (the '.{0,600}'-style proximity
    # patterns below) once the haystack contains any multibyte character —
    # this README's em dashes are enough to trigger it under a UTF-8 locale,
    # turning a sub-millisecond match into several seconds. Every pattern
    # matched here is plain ASCII, so byte-wise (C-locale) matching is
    # exactly equivalent, just without the multibyte code path's cost.
    if printf '%s' "$flat" | LC_ALL=C grep -qiE -- "$3"; then
        pass "$1"
    else
        fail "$1" "did not match regex (case-insensitive): $3"
    fi
}

# zone_between <file> <exact start heading line> <boundary ERE>
# Echoes the text strictly between the start heading (exclusive) and the
# next line matching boundary_re (exclusive), or through EOF if none.
zone_between() {
    local file="$1" start_text="$2" boundary_re="$3" start next
    start=$(grep -nxF -- "$start_text" "$file" | head -n1 | cut -d: -f1)
    [ -z "$start" ] && return 1
    next=$(awk -v s="$start" -v re="$boundary_re" 'NR>s && $0 ~ re {print NR; exit}' "$file")
    if [ -z "$next" ]; then
        sed -n "$((start+1)),\$p" "$file"
    else
        sed -n "$((start+1)),$((next-1))p" "$file"
    fi
}

# bullet_zone <file> <ERE anchoring the bullet's own line>
# Echoes one top-level "- **Foo**..." bullet's full text, from its own
# line through the line before the next top-level "- " bullet or the next
# heading (## / ###), whichever comes first.
bullet_zone() {
    local file="$1" start_re="$2" start next
    start=$(grep -nE -- "$start_re" "$file" | head -n1 | cut -d: -f1)
    [ -z "$start" ] && return 1
    next=$(awk -v s="$start" 'NR>s && ($0 ~ /^- / || $0 ~ /^## / || $0 ~ /^### /) {print NR; exit}' "$file")
    if [ -z "$next" ]; then
        sed -n "${start},\$p" "$file"
    else
        sed -n "${start},$((next-1))p" "$file"
    fi
}

# bullet_containing <file> <zone_start_line> <zone_end_line-or-empty> <needle>
# Locates the first line strictly between zone_start_line (exclusive) and
# zone_end_line (exclusive; empty means "through EOF") containing the
# literal <needle>, walks backward to the nearest enclosing top-level "- "
# bullet start, and echoes that whole bullet's text through the line
# before the next top-level bullet/heading — same boundary rule as
# bullet_zone. Unlike a whole-section scan, this isolates ONE bullet, so a
# content check against the result cannot accidentally match unrelated
# prose from a sibling bullet earlier in the same section (the "## What to
# expect" section already has other bullets — follow-ups, auto-compaction
# — that legitimately contain generic words like "open", "epoch",
# "marker", "flush", "snapshot" this contract's own new bullet also uses;
# a section-wide scan would give those clauses a false PASS even on the
# unimplemented stub).
bullet_containing() {
    local file="$1" zstart="$2" zend="$3" needle="$4" needle_line bullet_start next
    if [ -z "$zend" ]; then
        zend=$(($(wc -l < "$file") + 1))
    fi
    needle_line=$(awk -v s="$zstart" -v e="$zend" -v needle="$needle" \
        'NR>s && NR<e && index($0, needle) { print NR; exit }' "$file")
    [ -z "$needle_line" ] && return 1
    bullet_start=$(awk -v s="$zstart" -v n="$needle_line" \
        'NR>s && NR<=n && /^- / { line=NR } END { print line }' "$file")
    [ -z "$bullet_start" ] && bullet_start="$needle_line"
    next=$(awk -v s="$bullet_start" 'NR>s && ($0 ~ /^- / || $0 ~ /^## / || $0 ~ /^### /) {print NR; exit}' "$file")
    if [ -z "$next" ]; then
        sed -n "${bullet_start},\$p" "$file"
    else
        sed -n "${bullet_start},$((next-1))p" "$file"
    fi
}

# ===========================================================================
# Clause: README "What to expect" gains a bullet documenting .local/
# WORKGRAPH.md — lazily created, format per docs/protocols/work-graph.md
# (Goal/Status/Parent/Deps fields, file-level Focus: pointer), created from
# templates/WORKGRAPH.md on first decomposition (never by a hook), open
# nodes + the Focus node surfaced at every SessionStart, a Stop-hook
# close-out gate (once per epoch, marker scheme, CLAM_WORKGRAPH_GATE escape
# hatch), and carried through the flush nudge / pre-compact snapshot /
# post-compaction recovery.
# ===========================================================================

wte_heading_line=$(grep -nxF -- "## What to expect" "$STRIPPED_README" | head -n1 | cut -d: -f1)
wte_end_line=$(awk -v s="${wte_heading_line:-0}" 'NR>s && /^## / {print NR; exit}' "$STRIPPED_README")
check "'## What to expect' section is present" "$([ -n "$wte_heading_line" ] && echo yes || echo no)" "yes"

# Scoped to the ONE bullet containing the new artifact path — see
# bullet_containing's own comment for why a whole-section scan would be
# unsafe here (sibling bullets already use several of the same words).
wte_wg_bullet=$(bullet_containing "$STRIPPED_README" "$wte_heading_line" "$wte_end_line" '.local/WORKGRAPH.md')
check "'## What to expect' names a .local/WORKGRAPH.md bullet" \
    "$([ -n "$wte_wg_bullet" ] && echo yes || echo no)" "yes"

assert_contains_re_i "What to expect bullet: WORKGRAPH.md is lazily created" "$wte_wg_bullet" \
    'lazy|lazily'
assert_contains_re_i "What to expect bullet: it is a work graph for recursive problem decomposition" "$wte_wg_bullet" \
    'recursive[^.]{0,40}decompos|decompos[^.]{0,40}recursive'
assert_contains_re_i "What to expect bullet: names the work-graph protocol document" "$wte_wg_bullet" \
    'docs/protocols/work-graph\.md'
assert_contains_re_i "What to expect bullet: node fields include Goal" "$wte_wg_bullet" '\bGoal\b'
assert_contains_re_i "What to expect bullet: node fields include Status" "$wte_wg_bullet" '\bStatus\b'
assert_contains_re_i "What to expect bullet: node fields include Parent" "$wte_wg_bullet" '\bParent\b'
assert_contains_re_i "What to expect bullet: node fields include Deps" "$wte_wg_bullet" '\bDeps\b'
assert_contains_re_i "What to expect bullet: names the file-level Focus pointer" "$wte_wg_bullet" '\bFocus\b'
assert_contains_re_i "What to expect bullet: created from templates/WORKGRAPH.md" "$wte_wg_bullet" \
    'templates/WORKGRAPH\.md'
assert_contains_re_i "What to expect bullet: never created by a hook" "$wte_wg_bullet" \
    'never[^.]{0,60}\bhook\b|not[^.]{0,60}\bhook\b'
assert_contains_re_i "What to expect bullet: open nodes surfaced at every SessionStart" "$wte_wg_bullet" \
    '\bopen\b[^.]{0,80}session[ -]?start|session[ -]?start[^.]{0,80}\bopen\b'
assert_contains_re_i "What to expect bullet: the Focus node is surfaced too" "$wte_wg_bullet" \
    '\bfocus\b[^.]{0,120}session[ -]?start|session[ -]?start[^.]{0,120}\bfocus\b'
assert_contains_re_i "What to expect bullet: a Stop-hook close-out gate blocks Complete while nodes are open" "$wte_wg_bullet" \
    '(close-?out|gate)[^.]{0,150}\bcomplete\b|\bcomplete\b[^.]{0,150}(close-?out|gate)'
assert_contains_re_i "What to expect bullet: once-per-epoch marker scheme" "$wte_wg_bullet" \
    'epoch|marker'
assert_contains_re_i "What to expect bullet: names the CLAM_WORKGRAPH_GATE escape hatch" "$wte_wg_bullet" \
    'CLAM_WORKGRAPH_GATE'
assert_contains_re_i "What to expect bullet: carried through the flush nudge" "$wte_wg_bullet" \
    'flush'
assert_contains_re_i "What to expect bullet: carried through the pre-compact snapshot" "$wte_wg_bullet" \
    'snapshot'
assert_contains_re_i "What to expect bullet: carried through post-compaction recovery" "$wte_wg_bullet" \
    'recover|compaction'

# ===========================================================================
# Clause: README "Common workflows" has a "### Track a problem
# decomposition" subsection, positioned after "### Capture and disposition
# follow-ups": when to instantiate, node/Focus discipline,
# disposition-in-place, ASCII-tree render on request, and the machine-read
# marker warning mirroring the follow-ups one (`- Status: open` and
# `Focus:` matched literally; rewording breaks the hooks).
# ===========================================================================

CW_HEADING='## Common workflows'
CW_H3_FOLLOWUPS='### Capture and disposition follow-ups'
CW_H3='### Track a problem decomposition'
cw_start=$(grep -nxF -- "$CW_HEADING" "$STRIPPED_README" | head -n1 | cut -d: -f1)
cw_end=$(awk -v s="${cw_start:-0}" 'NR>s && /^## / {print NR; exit}' "$STRIPPED_README")
followups_h3_line=$(grep -nxF -- "$CW_H3_FOLLOWUPS" "$STRIPPED_README" | head -n1 | cut -d: -f1)
h3_line=$(grep -nxF -- "$CW_H3" "$STRIPPED_README" | head -n1 | cut -d: -f1)

if [ -n "$cw_start" ] && [ -n "$h3_line" ] && [ "$h3_line" -gt "$cw_start" ] \
    && { [ -z "$cw_end" ] || [ "$h3_line" -lt "$cw_end" ]; }; then
    pass "'$CW_H3' is a walkthrough inside '## Common workflows'"
else
    fail "'$CW_H3' is a walkthrough inside '## Common workflows'" \
        "heading not found in that section (h3_line='$h3_line', section=$cw_start..${cw_end:-EOF})"
fi

if [ -n "$followups_h3_line" ] && [ -n "$h3_line" ] && [ "$h3_line" -gt "$followups_h3_line" ]; then
    pass "'$CW_H3' comes after '$CW_H3_FOLLOWUPS'"
else
    fail "'$CW_H3' comes after '$CW_H3_FOLLOWUPS'" \
        "followups_h3_line='$followups_h3_line', h3_line='$h3_line'"
fi

walkthrough_zone=$(zone_between "$STRIPPED_README" "$CW_H3" '^(## |### )')
assert_contains_re_i "walkthrough: mentions decomposing a problem" "$walkthrough_zone" \
    'decompos'
assert_contains_re_i "walkthrough: mentions moving the Focus pointer in real time" "$walkthrough_zone" \
    '\bFocus\b[^.]{0,80}real[ -]?time|real[ -]?time[^.]{0,80}\bFocus\b'
assert_contains_re_i "walkthrough: dispositions are made in place, never deleted" "$walkthrough_zone" \
    'in place'
assert_contains_re_i "walkthrough: mentions the done/dropped dispositions" "$walkthrough_zone" \
    '\bdone\b'
assert_contains_re_i "walkthrough: mentions dropped (<reason>)" "$walkthrough_zone" \
    'dropped'
assert_contains_re_i "walkthrough: entries are never deleted" "$walkthrough_zone" \
    'never[^.]{0,40}delet|not[^.]{0,40}delet'
assert_contains_re_i "walkthrough: an ASCII-tree render is available on request" "$walkthrough_zone" \
    'ascii'
assert_contains_re_i "walkthrough: the render is a tree" "$walkthrough_zone" \
    '\btree\b'
assert_contains_re_i "walkthrough: names the literal '- Status: open' marker" "$walkthrough_zone" \
    '- Status: open'
assert_contains_re_i "walkthrough: names the literal 'Focus:' marker" "$walkthrough_zone" \
    'Focus:'
assert_contains_re_i "walkthrough: warns rewording the markers breaks the hooks" "$walkthrough_zone" \
    'reword[^.]{0,80}hook|hook[^.]{0,80}reword'

# ===========================================================================
# Clause: README Commands -> Hooks: SessionStart surfaces the work graph
# after open follow-ups; Stop's Complete branch gains a work-graph
# close-out gate between the follow-ups gate and the two further
# backstops; PreCompact / post-compact-recovery / flush-nudge each gain
# WORKGRAPH.md in their file lists.
# ===========================================================================

SS_START_RE='^- \*\*SessionStart\*\* '
STOP_START_RE='^- \*\*Stop\*\* '
PRECOMPACT_START_RE='^- \*\*PreCompact, `auto` matcher\*\* '
POSTCOMPACT_START_RE='^- \*\*SessionStart, `compact` matcher\*\* '
FLUSHNUDGE_START_RE='^- \*\*UserPromptSubmit\*\* \(`scripts/flush-nudge\.sh`\)'

sessionstart_bullet=$(bullet_zone "$STRIPPED_README" "$SS_START_RE")
check "Hooks: a '- **SessionStart** (...)' bullet exists" \
    "$([ -n "$sessionstart_bullet" ] && echo yes || echo no)" "yes"
assert_contains_re_i "SessionStart bullet: names work-graph surfacing" "$sessionstart_bullet" \
    'work[ -]?graph'
assert_contains_re_i "SessionStart bullet: work-graph surfacing comes after the open-follow-ups block" \
    "$sessionstart_bullet" 'follow-?up.{0,600}work[ -]?graph'

stop_bullet=$(bullet_zone "$STRIPPED_README" "$STOP_START_RE")
check "Hooks: a '- **Stop** (...)' bullet exists" \
    "$([ -n "$stop_bullet" ] && echo yes || echo no)" "yes"

followups_gate_line=$(grep -nF -- "A follow-ups close-out gate runs first" "$STRIPPED_README" | head -n1 | cut -d: -f1)
backstops_line=$(grep -nF -- "Two further backstops compose on top of the state check:" "$STRIPPED_README" | head -n1 | cut -d: -f1)
workgraph_gate_line=""
if [ -n "$followups_gate_line" ] && [ -n "$backstops_line" ]; then
    workgraph_gate_line=$(awk -v s="$followups_gate_line" -v e="$backstops_line" \
        'NR>s && NR<e && /CLAM_WORKGRAPH_GATE/ {print NR; exit}' "$STRIPPED_README")
fi
check "Stop: a work-graph close-out gate paragraph sits between the follow-ups gate and the two further backstops" \
    "$([ -n "$workgraph_gate_line" ] && echo yes || echo no)" "yes"

workgraph_gate_zone=""
if [ -n "$workgraph_gate_line" ] && [ -n "$backstops_line" ]; then
    workgraph_gate_zone=$(sed -n "${workgraph_gate_line},$((backstops_line - 1))p" "$STRIPPED_README")
fi
assert_contains_re_i "Stop: work-graph gate paragraph ties the block to State: Complete" "$workgraph_gate_zone" \
    '\bComplete\b'
assert_contains_re_i "Stop: work-graph gate paragraph names it a close-out/gate" "$workgraph_gate_zone" \
    'close-?out|gate'
assert_contains_re_i "Stop: work-graph gate paragraph is once-per-epoch with a marker" "$workgraph_gate_zone" \
    'epoch|marker'
assert_contains_re_i "Stop: work-graph gate paragraph names the CLAM_WORKGRAPH_GATE escape hatch" \
    "$workgraph_gate_zone" 'CLAM_WORKGRAPH_GATE'

precompact_bullet=$(bullet_zone "$STRIPPED_README" "$PRECOMPACT_START_RE")
check "Hooks: a '- **PreCompact, \`auto\` matcher** (...)' bullet exists" \
    "$([ -n "$precompact_bullet" ] && echo yes || echo no)" "yes"
assert_contains_re_i "PreCompact bullet: WORKGRAPH.md joins the snapshot file list" "$precompact_bullet" \
    'WORKGRAPH\.md'

postcompact_bullet=$(bullet_zone "$STRIPPED_README" "$POSTCOMPACT_START_RE")
check "Hooks: a '- **SessionStart, \`compact\` matcher** (...)' bullet exists" \
    "$([ -n "$postcompact_bullet" ] && echo yes || echo no)" "yes"
assert_contains_re_i "post-compact-recovery bullet: WORKGRAPH.md joins the re-injection file list" \
    "$postcompact_bullet" 'WORKGRAPH\.md'

flushnudge_bullet=$(bullet_zone "$STRIPPED_README" "$FLUSHNUDGE_START_RE")
check "Hooks: a '- **UserPromptSubmit** (\`scripts/flush-nudge.sh\`)' bullet exists" \
    "$([ -n "$flushnudge_bullet" ] && echo yes || echo no)" "yes"
assert_contains_re_i "flush-nudge bullet: WORKGRAPH.md joins the docs-to-flush list" \
    "$flushnudge_bullet" 'WORKGRAPH\.md'

# ===========================================================================
# Clause: README Commands -> Env var summary has a CLAM_WORKGRAPH_GATE row
# (default enabled; any other value disables the close-out gate).
# ===========================================================================

env_row=$(grep -E '^\| *`?CLAM_WORKGRAPH_GATE`? *\|' "$STRIPPED_README" | head -n1)
check "Env var summary: a CLAM_WORKGRAPH_GATE table row exists" \
    "$([ -n "$env_row" ] && echo yes || echo no)" "yes"
assert_contains_re_i "CLAM_WORKGRAPH_GATE row: default is 'enabled'" "$env_row" \
    '\|[[:space:]]*`?enabled`?[[:space:]]*\|'
assert_contains_re_i "CLAM_WORKGRAPH_GATE row: any other value disables the gate" "$env_row" \
    'disable'
assert_contains_re_i "CLAM_WORKGRAPH_GATE row: names the close-out gate" "$env_row" \
    'close-?out|gate'

# ===========================================================================
# Clause: README Library files section has a templates/WORKGRAPH.md entry
# naming the protocol document and the two machine-read markers.
# ===========================================================================

WG_LIB_START_RE='^- \*\*`templates/WORKGRAPH\.md`\*\*'
wg_lib_bullet=$(bullet_zone "$STRIPPED_README" "$WG_LIB_START_RE")
check "Library files: a '- **\`templates/WORKGRAPH.md\`**...' bullet exists" \
    "$([ -n "$wg_lib_bullet" ] && echo yes || echo no)" "yes"
assert_contains_re_i "templates/WORKGRAPH.md bullet: names the protocol document" "$wg_lib_bullet" \
    'docs/protocols/work-graph\.md'
assert_contains_re_i "templates/WORKGRAPH.md bullet: names the Focus marker" "$wg_lib_bullet" \
    'Focus:'
assert_contains_re_i "templates/WORKGRAPH.md bullet: names the Status-open marker" "$wg_lib_bullet" \
    '- Status: open'

# ===========================================================================
# Clause: README Uninstalling section — .local/WORKGRAPH.md joins the
# not-removed list.
# ===========================================================================

uninstalling_zone=$(zone_between "$STRIPPED_README" "## Uninstalling" '^## ')
check "'## Uninstalling' section is present" "$([ -n "$uninstalling_zone" ] && echo yes || echo no)" "yes"
if printf '%s' "$uninstalling_zone" | grep -qF '.local/WORKGRAPH.md'; then
    pass "Uninstalling: .local/WORKGRAPH.md is named"
else
    fail "Uninstalling: .local/WORKGRAPH.md is named" "no '.local/WORKGRAPH.md' reference found"
fi
assert_contains_re_i "Uninstalling: .local/WORKGRAPH.md is in the not-removed list" "$uninstalling_zone" \
    '\.local/WORKGRAPH\.md[^.]{0,300}not removed|not removed[^.]{0,300}\.local/WORKGRAPH\.md'

# ===========================================================================
# Clause: plugin.json version is bumped exactly 0.6.3 -> 0.7.0 (a specific
# target, unlike B05's flexible-semver bump), and the description field
# gains the work-graph feature in its enumeration.
#
# Amended by B07 followups-snapshot-docs (cjdubb/clam#225): B07 bumps this
# plugin.json version again, 0.7.0 -> 0.7.1 (see plugins/tracking/README.md's
# "Contract: B07 followups-snapshot-docs" comment, invariant 3, and
# followups-docs.test.sh's own plugin.json version check) — kept in
# lockstep here so the two suites never pin contradictory versions.
# ===========================================================================

# Retargeted to 0.7.2 by B06 (plan 001-speed-up-repo-ci): that plan's
# scaffold edits this file, and version-bump-lint has no docs/tests
# exemption, so the plugin necessarily moves 0.7.1 -> 0.7.2. Retargeted
# to 0.7.3 by the README Update-section wave, for the same reason. The pin
# tracks the CURRENT version, so every legitimate bump retargets it — see
# .local/FOLLOWUPS.md F05 for why that coupling is worth removing.
# Retargeted again to 0.8.0 by B09 (plan 001-render-graph-always), whose own
# contract states the 0.7.2 -> 0.8.0 bump. followups-docs.test.sh carries the
# same pin and moves in lockstep, so the two suites never disagree; this is a
# literal retarget only — no assertion added, removed, or weakened, and the
# PASS count this file's own B06 contract freezes is unchanged.
# Retargeted again to 0.9.0 by 003-B21 (plan 003-followup-fixes), whose own
# contract states the 0.8.0 -> 0.9.0 bump. followups-docs.test.sh and
# workgraph-live-view.test.sh carry the same pin and move in lockstep. Again
# a literal retarget only — no assertion added, removed, or weakened, and the
# frozen PASS count is unchanged.
plugin_version=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json version is exactly 0.9.2" "$plugin_version" "0.9.2"

plugin_description=$(jq -r '.description' "$PLUGIN_JSON" 2>/dev/null)
assert_contains_re_i "plugin.json description: gains the work-graph feature" "$plugin_description" \
    'work[ -]?graph'

# ===========================================================================
# Clause: make-progress SKILL.md step-2 list has an explicit numbered
# .local/WORKGRAPH.md row immediately after the .local/FOLLOWUPS.md row
# (open nodes and the Focus pointer are assessment inputs, the Focus
# node's goal is a candidate next action), sequential numbering intact.
# ===========================================================================

step2_zone=$(zone_between "$SKILL" "### 2. Assess" '^### ')
check "SKILL.md: '### 2. Assess' step is present" "$([ -n "$step2_zone" ] && echo yes || echo no)" "yes"

step2_items=$(printf '%s\n' "$step2_zone" | grep -E '^[0-9]+\.')

followups_row=$(printf '%s\n' "$step2_items" | grep -F '.local/FOLLOWUPS.md')
check "step-2 list: the existing .local/FOLLOWUPS.md row is still present" \
    "$([ -n "$followups_row" ] && echo yes || echo no)" "yes"

workgraph_row=$(printf '%s\n' "$step2_items" | grep -F '.local/WORKGRAPH.md')
check "step-2 list: has an explicit numbered .local/WORKGRAPH.md row (not just a comment)" \
    "$([ -n "$workgraph_row" ] && echo yes || echo no)" "yes"
assert_contains_re_i "WORKGRAPH.md row: open nodes are an assessment input" "$workgraph_row" \
    '\bopen\b[^.]{0,60}\bnode|\bnode[^.]{0,60}\bopen\b'
assert_contains_re_i "WORKGRAPH.md row: the Focus pointer is an assessment input" "$workgraph_row" \
    '\bFocus\b'
assert_contains_re_i "WORKGRAPH.md row: the Focus node's goal is a candidate next action" "$workgraph_row" \
    'next action'

followups_num=$(printf '%s' "$followups_row" | sed -E 's/^([0-9]+)\..*/\1/')
workgraph_num=$(printf '%s' "$workgraph_row" | sed -E 's/^([0-9]+)\..*/\1/')
if [ -n "$followups_num" ] && [ -n "$workgraph_num" ] && [ "$workgraph_num" -eq $((followups_num + 1)) ]; then
    pass "step-2 list: the WORKGRAPH.md row is immediately after the FOLLOWUPS.md row"
else
    fail "step-2 list: the WORKGRAPH.md row is immediately after the FOLLOWUPS.md row" \
        "followups_num='$followups_num', workgraph_num='$workgraph_num'"
fi

# Sequential numbering: the leading integers of every top-level step-2 list
# item, in document order, must be exactly 1..N with no gaps or repeats —
# true both for today's 6-item list and the 7-item list B06 produces.
numbers=$(printf '%s\n' "$step2_items" | sed -E 's/^([0-9]+)\..*/\1/')
expected_seq=""
n=0
for num in $numbers; do
    n=$((n + 1))
    expected_seq="$expected_seq $n"
done
got_seq=$(printf '%s' "$numbers" | tr '\n' ' ')
expected_seq=$(printf '%s' "${expected_seq# }")
check "step-2 list numbering is sequential (1..N, no gaps/repeats)" \
    "$(printf '%s' "$got_seq" | sed -E 's/[[:space:]]+/ /g; s/ $//')" \
    "$(printf '%s' "$expected_seq" | sed -E 's/[[:space:]]+/ /g; s/ $//')"

# ===========================================================================
# Acceptance clauses on the RAW (unstripped) files: the B06 scaffolding
# contract comment is gone from README.md, and no NotImplemented
# placeholder remains in any of the three B06 target files.
# ===========================================================================

if grep -qF -- "Contract: B06" "$README" 2>/dev/null; then
    fail "README.md: the 'Contract: B06' scaffolding HTML comment has been removed" "still present"
else
    pass "README.md: the 'Contract: B06' scaffolding HTML comment has been removed"
fi

for f in "$README" "$SKILL" "$PLUGIN_JSON"; do
    label="$(basename "$f"): no NotImplemented placeholder remains"
    if grep -qF -- "NotImplemented" "$f" 2>/dev/null; then
        fail "$label" "still present in $f"
    else
        pass "$label"
    fi
done

# ===========================================================================
# Clause: `bash scripts/readme-lint.sh` (repo root) still passes for
# tracking.
# ===========================================================================

lint_out=$(cd "$REPO_ROOT" && bash scripts/readme-lint.sh 2>&1)
lint_rc=$?
check "readme-lint.sh exits 0" "$lint_rc" "0"
if printf '%s' "$lint_out" | grep -qxF "PASS  tracking"; then
    pass "readme-lint.sh reports 'PASS  tracking'"
else
    fail "readme-lint.sh reports 'PASS  tracking'" "not found in output: $lint_out"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
