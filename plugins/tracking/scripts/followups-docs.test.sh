#!/bin/bash
# Tests for B05 followups-docs-and-version: README.md documents the
# follow-ups feature (the "Contract: B05 — followups-docs-and-version"
# HTML-comment docblock near the top of plugins/tracking/README.md is the
# source of truth), plugin.json is bumped to v0.6.0, make-progress's
# SKILL.md step-2 list gains an explicit FOLLOWUPS.md row, and readme-lint
# stays green.
#
# Content-presence tests, not exact-prose pins: wording is not contracted
# verbatim, so assertions are flexible token/proximity regexes on the
# load-bearing facts, matching followups-template.test.sh's approach.
#
# Comment-stripped inputs: README.md and SKILL.md are each read through a
# `sed '/<!--/,/-->/d'` pass (same technique plugins/render-doc/scripts/
# structure.test.sh uses) before any content check. Both files currently
# carry their own B05 contract docblock as an HTML comment mentioning
# "FOLLOWUPS.md" / "CLAM_FOLLOWUPS_GATE" — without stripping, every
# presence check below would trivially pass by matching the CONTRACT
# COMMENT rather than real prose, defeating the point of a red run.
#
# Explicitly OUT of scope (per the brief): no assertion on
# marketplace.json's description — it is byte-pinned elsewhere and B05
# must not change it.
#
# Hermetic: reads only files at fixed repo locations (resolved from this
# script's own path) into a mktemp scratch dir, plus one subshelled
# execution of scripts/readme-lint.sh from the repo root (read-only lint,
# no mutation). No network.
#
# Run: bash plugins/tracking/scripts/followups-docs.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

README="$PLUGIN_ROOT/README.md"
SKILL="$PLUGIN_ROOT/skills/make-progress/SKILL.md"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
README_LINT="$REPO_ROOT/scripts/readme-lint.sh"
ROOT_README="$REPO_ROOT/README.md"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }
check() { # label got expected
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got '$2', expected '$3'"; fi
}

for f in "$README" "$SKILL" "$PLUGIN_JSON" "$README_LINT" "$ROOT_README"; do
    if [ ! -f "$f" ]; then
        fail "required file exists" "not found at $f"
        echo ""
        echo "Some tests FAILED."
        exit 1
    fi
done

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Comment-stripped copies — see file header for why this matters.
STRIPPED_README="$TMPROOT/README.stripped.md"
STRIPPED_SKILL="$TMPROOT/SKILL.stripped.md"
sed '/<!--/,/-->/d' "$README" > "$STRIPPED_README"
sed '/<!--/,/-->/d' "$SKILL" > "$STRIPPED_SKILL"

# assert_contains_re_i <label> <haystack> <ERE, case-insensitive>
# Flattens embedded newlines to spaces first: grep matches per physical
# line by default, but hard-wrapped markdown prose often lands a
# proximity regex's two halves on different source lines.
assert_contains_re_i() {
    local flat
    flat=$(printf '%s' "$2" | tr '\n' ' ')
    if printf '%s' "$flat" | grep -qiE -- "$3"; then
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

# ===========================================================================
# Clause: README "What to expect" covers the FOLLOWUPS.md artifact (lazy
# creation, entry-per-follow-up with disposition Status), session-start
# surfacing of open entries, and the Complete-state close-out gate.
# ===========================================================================

wte_zone=$(zone_between "$STRIPPED_README" "## What to expect" '^## ')
check "'## What to expect' section is present" "$([ -n "$wte_zone" ] && echo yes || echo no)" "yes"

assert_contains_re_i "What to expect: names the .local/FOLLOWUPS.md artifact" "$wte_zone" \
    '\.local/FOLLOWUPS\.md'
assert_contains_re_i "What to expect: FOLLOWUPS.md is lazily created" "$wte_zone" \
    'lazy|lazily'
assert_contains_re_i "What to expect: one entry per follow-up" "$wte_zone" \
    '(entry|entries)[^.]{0,60}follow-?up|follow-?up[^.]{0,60}(entry|entries)'
assert_contains_re_i "What to expect: entries carry a disposition Status" "$wte_zone" \
    '\bstatus\b|\bdisposition\b'
assert_contains_re_i "What to expect: open entries are surfaced at session start" "$wte_zone" \
    '(session[ -]?start|sessionstart)[^.]{0,80}\bopen\b|\bopen\b[^.]{0,80}(session[ -]?start|sessionstart)'
assert_contains_re_i "What to expect: the close-out gate is tied to follow-ups, not just Complete generically" "$wte_zone" \
    'follow-?up[^.]{0,150}\bcomplete\b|\bcomplete\b[^.]{0,150}follow-?up'
assert_contains_re_i "What to expect: names it a close-out gate" "$wte_zone" \
    'close-?out|gate'

# ===========================================================================
# Clause: README "Common workflows" has a "### Capture and disposition
# follow-ups" walkthrough.
# ===========================================================================

CW_HEADING='## Common workflows'
CW_H3='### Capture and disposition follow-ups'
cw_start=$(grep -nxF -- "$CW_HEADING" "$STRIPPED_README" | head -n1 | cut -d: -f1)
cw_end=$(awk -v s="${cw_start:-0}" 'NR>s && /^## / {print NR; exit}' "$STRIPPED_README")
h3_line=$(grep -nxF -- "$CW_H3" "$STRIPPED_README" | head -n1 | cut -d: -f1)

if [ -n "$cw_start" ] && [ -n "$h3_line" ] && [ "$h3_line" -gt "$cw_start" ] \
    && { [ -z "$cw_end" ] || [ "$h3_line" -lt "$cw_end" ]; }; then
    pass "'$CW_H3' is a walkthrough inside '## Common workflows'"
else
    fail "'$CW_H3' is a walkthrough inside '## Common workflows'" \
        "heading not found in that section (h3_line='$h3_line', section=$cw_start..${cw_end:-EOF})"
fi

walkthrough_zone=$(zone_between "$STRIPPED_README" "$CW_H3" '^(## |### )')
assert_contains_re_i "walkthrough: mentions a follow-up mention/capture" "$walkthrough_zone" \
    'follow-?up'
assert_contains_re_i "walkthrough: mentions an entry being appended" "$walkthrough_zone" \
    'append'
assert_contains_re_i "walkthrough: mentions the close-out gate" "$walkthrough_zone" \
    'close-?out|gate'
assert_contains_re_i "walkthrough: mentions a disposition outcome (filed/resolved/dropped)" "$walkthrough_zone" \
    'filed|resolved|dropped'

# ===========================================================================
# Clause: README Commands -> Hooks: SessionStart and Stop rows name the
# new surfacing/gate behavior; templates enumeration includes FOLLOWUPS.md.
# ===========================================================================

sessionstart_bullet=$(bullet_zone "$STRIPPED_README" '^- \*\*SessionStart\*\* ')
check "Hooks: a '- **SessionStart** (...)' bullet exists" \
    "$([ -n "$sessionstart_bullet" ] && echo yes || echo no)" "yes"
assert_contains_re_i "SessionStart hook row: names follow-up surfacing" "$sessionstart_bullet" \
    'follow-?up'
assert_contains_re_i "SessionStart hook row: surfaces OPEN entries" "$sessionstart_bullet" \
    '\bopen\b[^.]{0,60}(entry|entries)|(entry|entries)[^.]{0,60}\bopen\b'

stop_bullet=$(bullet_zone "$STRIPPED_README" '^- \*\*Stop\*\* ')
check "Hooks: a '- **Stop** (...)' bullet exists" \
    "$([ -n "$stop_bullet" ] && echo yes || echo no)" "yes"
assert_contains_re_i "Stop hook row: names the follow-ups close-out gate" "$stop_bullet" \
    'follow-?up'
assert_contains_re_i "Stop hook row: ties the gate to the Complete state" "$stop_bullet" \
    '\bcomplete\b'
assert_contains_re_i "Stop hook row: names it a gate/close-out behavior" "$stop_bullet" \
    'close-?out|gate'

# The templates enumeration (Library files, mirroring the existing
# "templates/TODO.md" bullet) gains a FOLLOWUPS.md entry. Anchored on the
# path form used by the sibling TODO.md bullet, not exact prose.
if grep -qF 'templates/FOLLOWUPS.md' "$STRIPPED_README"; then
    pass "templates enumeration includes templates/FOLLOWUPS.md"
else
    fail "templates enumeration includes templates/FOLLOWUPS.md" "no 'templates/FOLLOWUPS.md' reference found"
fi

# ===========================================================================
# Clause: README Commands -> Env var summary has a CLAM_FOLLOWUPS_GATE row
# (default enabled; any other value disables the close-out gate).
# ===========================================================================

env_row=$(grep -E '^\| *`?CLAM_FOLLOWUPS_GATE`? *\|' "$STRIPPED_README" | head -n1)
check "Env var summary: a CLAM_FOLLOWUPS_GATE table row exists" \
    "$([ -n "$env_row" ] && echo yes || echo no)" "yes"
assert_contains_re_i "CLAM_FOLLOWUPS_GATE row: default is 'enabled'" "$env_row" \
    '\|[[:space:]]*`?enabled`?[[:space:]]*\|'
assert_contains_re_i "CLAM_FOLLOWUPS_GATE row: any other value disables the gate" "$env_row" \
    'disable'
assert_contains_re_i "CLAM_FOLLOWUPS_GATE row: names the close-out gate" "$env_row" \
    'close-?out|gate'

# ===========================================================================
# Clause: plugin.json version is bumped — non-empty and well-formed semver
# (X.Y.Z), not pinned to a literal value (see compaction-wiring.test.sh's
# equivalent check, which this mirrors).
# ===========================================================================

plugin_version=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json version is non-empty and well-formed semver (X.Y.Z)" \
    "$([[ "$plugin_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" "yes"

# ===========================================================================
# Clause: make-progress SKILL.md step-2 list has an explicit numbered
# .local/FOLLOWUPS.md row (open entries as dispatchable next actions),
# with sequential numbering intact.
# ===========================================================================

step2_zone=$(zone_between "$STRIPPED_SKILL" "### 2. Assess" '^### ')
check "SKILL.md: '### 2. Assess' step is present" "$([ -n "$step2_zone" ] && echo yes || echo no)" "yes"

step2_items=$(printf '%s\n' "$step2_zone" | grep -E '^[0-9]+\.')

followups_row=$(printf '%s\n' "$step2_items" | grep -F '.local/FOLLOWUPS.md')
check "step-2 list: has an explicit numbered .local/FOLLOWUPS.md row (not just a comment)" \
    "$([ -n "$followups_row" ] && echo yes || echo no)" "yes"
assert_contains_re_i "FOLLOWUPS.md row: open entries" "$followups_row" '\bopen\b'
assert_contains_re_i "FOLLOWUPS.md row: framed as a dispatchable next action" "$followups_row" \
    'dispatchable|next action'

# Sequential numbering: the leading integers of every top-level step-2 list
# item, in document order, must be exactly 1..N with no gaps or repeats —
# true both for today's 5-item list and the 6-item list B05 produces.
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
# B07 followups-snapshot-docs (plan 002-tracking-followups-snapshot-docs,
# cjdubb/clam#225): the SessionStart `compact` matcher and PreCompact
# `auto` matcher bullets omit FOLLOWUPS.md from their file lists even
# though the scripts they describe already carry it. Contract: the
# "Contract: B07 followups-snapshot-docs" HTML-comment docblock directly
# above the SessionStart `compact` matcher bullet in
# plugins/tracking/README.md. Four clauses / artifact states, assigned to
# this B05 suite per the contract's own Invariants section (which also
# amends workgraph-docs.test.sh's exact-0.7.0 plugin.json pin to 0.7.1 so
# the two suites never pin contradictory versions).
# ===========================================================================

# Clause 1: the SessionStart `compact` matcher bullet's re-injected file
# list gains FOLLOWUPS.md, inserted after TROUBLESHOOTING.md and before
# WORKGRAPH.md (the script's own order).
postcompact_bullet=$(bullet_zone "$STRIPPED_README" '^- \*\*SessionStart, `compact` matcher\*\* ')
check "Hooks: a '- **SessionStart, \`compact\` matcher** (...)' bullet exists" \
    "$([ -n "$postcompact_bullet" ] && echo yes || echo no)" "yes"
assert_contains_re_i "post-compact-recovery bullet: FOLLOWUPS.md joins the re-injection file list" \
    "$postcompact_bullet" 'FOLLOWUPS\.md'
assert_contains_re_i "post-compact-recovery bullet: FOLLOWUPS.md sits after TROUBLESHOOTING.md and before WORKGRAPH.md" \
    "$postcompact_bullet" 'TROUBLESHOOTING\.md.{0,80}FOLLOWUPS\.md.{0,80}WORKGRAPH\.md'

# Clause 2: the PreCompact `auto` matcher bullet's copied file list gains
# FOLLOWUPS.md at the same position; the trailing "any SUBAGENT-LOG-*.md"
# clause is unchanged (still trails WORKGRAPH.md). The two bullets' lists
# differ (this one also names SUBAGENT-LOG-*.md and the snapshot
# destination) — assert each bullet's own list only, never that the two
# read identically.
precompact_bullet=$(bullet_zone "$STRIPPED_README" '^- \*\*PreCompact, `auto` matcher\*\* ')
check "Hooks: a '- **PreCompact, \`auto\` matcher** (...)' bullet exists" \
    "$([ -n "$precompact_bullet" ] && echo yes || echo no)" "yes"
assert_contains_re_i "PreCompact bullet: FOLLOWUPS.md joins the snapshot file list" \
    "$precompact_bullet" 'FOLLOWUPS\.md'
assert_contains_re_i "PreCompact bullet: FOLLOWUPS.md sits after TROUBLESHOOTING.md and before WORKGRAPH.md" \
    "$precompact_bullet" 'TROUBLESHOOTING\.md.{0,80}FOLLOWUPS\.md.{0,80}WORKGRAPH\.md'
assert_contains_re_i "PreCompact bullet: the trailing 'any SUBAGENT-LOG-*.md' clause still trails WORKGRAPH.md" \
    "$precompact_bullet" 'WORKGRAPH\.md.{0,40}SUBAGENT-LOG-\*\.md'

# Clause 3: plugin.json version becomes exactly 0.7.1 (from 0.7.0);
# description is unchanged. The description is pinned byte-for-byte —
# unlike the flexible-semver check above (which predates B07 and stays as
# a loose "well-formed" check), B07's version target is a specific literal,
# same treatment workgraph-docs.test.sh gives its own exact-version clause.
# Retargeted to 0.7.2 by B06 (plan 001-speed-up-repo-ci), then to 0.7.3 by
# the README Update-section wave (same cause: that wave edits this plugin's
# README and version-bump-lint has no docs exemption); see the matching
# note in workgraph-docs.test.sh and .local/FOLLOWUPS.md F05. Retargeted
# again to 0.8.0 by B09 (plan 001-render-graph-always), in lockstep with
# workgraph-docs.test.sh's copy of the same pin. Retargeted again to 0.9.0
# by 003-B21 (plan 003-followup-fixes), whose contract states the
# 0.8.0 -> 0.9.0 bump, in lockstep with workgraph-docs.test.sh and
# workgraph-live-view.test.sh.
b07_plugin_version=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json version is exactly 0.16.0" "$b07_plugin_version" "0.16.0"

EXPECTED_B07_DESCRIPTION='Tracking-document workflow: .local/TODO.md as session state of record, 13-state lifecycle with Stop-hook enforcement, a built-in task-tools deny, absorbed stall-recovery (capture hook + /make-progress skill), resume-after-/clear via SessionStart injection, and a work graph (.local/WORKGRAPH.md) for recursive problem decomposition.'
b07_plugin_description=$(jq -r '.description' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json description is unchanged by the B07 version bump" \
    "$b07_plugin_description" "$EXPECTED_B07_DESCRIPTION"

# Clause 4: the repo-root README.md Plugins table's tracking row version
# cell becomes v0.7.1 (readme-lint's version-match rule pairs it with
# clause 3). Anchored on the tracking row's own leading cell
# ("[tracking](plugins/tracking/)"), never on a sibling plugin's row or a
# position derived from one — several other rows legitimately mention
# "tracking" in their own prose (statusline, notifications).
tracking_row=$(grep -E '^\| *\[tracking\]\(plugins/tracking/\) *\|' "$ROOT_README" | head -n1)
check "root README.md: the tracking row exists in the Plugins table" \
    "$([ -n "$tracking_row" ] && echo yes || echo no)" "yes"
assert_contains_re_i "root README.md: tracking row's version cell is v0.16.0" "$tracking_row" \
    '✅ *v0\.16\.0'

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
