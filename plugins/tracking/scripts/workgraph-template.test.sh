#!/bin/bash
# Structural/contract tests for B01 work-graph-protocol and B02
# workgraph-template: the "Contract: B01 work-graph-protocol" and
# "Contract: B02 workgraph-template" HTML-comment docblocks atop
# docs/protocols/work-graph.md and plugins/tracking/templates/WORKGRAPH.md
# respectively are the source of truth, plus a third block of tests
# checking the two files AGREE with each other (B02's Invariant "Marker
# spellings agree exactly with docs/protocols/work-graph.md").
#
# A fourth block at the bottom covers 003-B21 authoring-defaults-recorded,
# which extends both of those same two files; see its own section header for
# the contract and the scoping rationale.
#
# Comment-scoped assertions: every content-presence/absence check below
# reads only the file content strictly AFTER the leading contract
# comment's closing '-->' (or the whole file, once the comment is deleted
# at acceptance — same fallback followups-template.test.sh uses). This
# is not optional hygiene: both contracts' own prose already contains,
# inside the comment, several of the exact anchors this suite must find
# in the real body (the Focus/Status-open regexes stated "verbatim",
# heading names, the N<NN>/zero-padded/"scoped to this file" language).
# Checking the raw file unscoped would let those checks pass against the
# scaffolding comment alone, on the still-unimplemented stub, defeating
# the point of a red run for those specific clauses. This mirrors the
# technique followups-template.test.sh uses for its own self-referential
# "zero-padded" / "scoped to this file" checks.
#
# The "no plugin/hook/script named" invariant is handled differently per
# file, because the two files behave differently in practice:
#   - B01 (docs/protocols/work-graph.md) is a protocol/spec document.
#     Every existing sibling in docs/protocols/ (todo-format.md,
#     decision-file.md, session-states.md) states a near-identical
#     disclaimer sentence containing the bare word "plugin" ("owned by
#     the repository's architecture ... and names no plugin") — this
#     contract's own Behavior section requires the same sentence. A
#     blanket "the word plugin never appears" check would therefore FAIL
#     against correctly-implemented prose. So B01's checks allow the bare
#     disclaimer word but forbid: "hook"/"script" in any form (no sibling
#     protocol doc uses either, in any sense), a `plugins/` path fragment,
#     any other repo plugin directory name as a standalone word, and the
#     word "tracking" (which the contract legitimately uses generically —
#     "session tracking document", verified against todo-format.md's own
#     wording) directly paired with "plugin".
#   - B02 (plugins/tracking/templates/WORKGRAPH.md) is a TEMPLATE, not a
#     protocol doc, and templates don't carry that disclaimer: the sibling
#     FOLLOWUPS.md template contains zero occurrences of "plugin", "hook",
#     or "script" in any form. B02's checks are therefore a strict blanket
#     absence of all three words plus every repo plugin directory name
#     (including "tracking" itself, with no exception).
#
# Agreement block: rather than hardcoding the two marker regexes twice
# (once per file) and comparing each independently against its own
# hardcoded copy, the Focus and Status-open regexes are EXTRACTED from
# B01's own rendered body text and then applied, as real regexes, against
# B02's actual example lines. This catches drift between the two files
# that two independently-correct hardcoded literals would not.
#
# Not asserted here (documented per the brief's escalation guidance,
# rather than silently skipped):
#   - B01 Edge cases ("a Focus id naming a non-existent/non-open node is
#     a documented defect state, fail-open"; "an empty graph is valid")
#     describe RUNTIME behavior of an instantiated `.local/WORKGRAPH.md`
#     consumer, not a static property of the protocol document's own
#     text, and are not covered by a content-anchor test of this file.
#   - Inputs/Outputs/Errors sections of both contracts are "n/a (normative
#     prose)" / "n/a (template prose)" — nothing to assert.
#
# Hermetic: reads only the two files at their fixed repo locations
# (resolved from this script's own path), no mutation, no network.
#
# Run: bash plugins/tracking/scripts/workgraph-template.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

B01_FILE="$SCRIPT_DIR/../../../docs/protocols/work-graph.md"
B02_FILE="$PLUGIN_ROOT/templates/WORKGRAPH.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }

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

# assert_absent_re_i <label> <haystack> <ERE, case-insensitive>
# Inverse of assert_contains_re_i: passes when the pattern is NOT found.
assert_absent_re_i() {
  local flat
  flat=$(printf '%s' "$2" | tr '\n' ' ')
  if printf '%s' "$flat" | grep -qiE -- "$3"; then
    fail "$1" "matched forbidden pattern (case-insensitive): $3"
  else
    pass "$1"
  fi
}

# Line number of the first '-->' in $1 (end of a leading HTML contract
# comment), or empty if none is present (the fully-implemented state).
comment_end_line() { # file
  grep -n -- '-->' "$1" 2>/dev/null | head -n1 | cut -d: -f1
}

# First line number in $1, strictly AFTER $2 (comment end line; 0 means
# "from the top"), whose content is EXACTLY $3.
body_exact_line_no() { # file comment_end exact_text
  local file="$1" end="${2:-0}" text="$3"
  grep -nxF -- "$text" "$file" 2>/dev/null | awk -F: -v end="$end" '$1>end {print $1; exit}'
}

# Text of $1 strictly after $2 (comment end line; 0 = whole file).
body_after() { # file comment_end
  local file="$1" end="${2:-0}"
  sed -n "$((end + 1)),\$p" "$file"
}

for f in "$B01_FILE" "$B02_FILE"; do
  if [[ ! -f "$f" ]]; then
    fail "required file exists" "not found at $f"
    echo ""
    echo "Some tests FAILED."
    exit 1
  fi
done

check "docs/protocols/work-graph.md exists" "yes" "yes"
check "WORKGRAPH.md template exists" "yes" "yes"

B01_END=$(comment_end_line "$B01_FILE"); B01_END="${B01_END:-0}"
B02_END=$(comment_end_line "$B02_FILE"); B02_END="${B02_END:-0}"
B01_BODY=$(body_after "$B01_FILE" "$B01_END")
B02_BODY=$(body_after "$B02_FILE" "$B02_END")
FLAT_B01_BODY=$(printf '%s' "$B01_BODY" | tr '\n' ' ')
FLAT_B02_BODY=$(printf '%s' "$B02_BODY" | tr '\n' ' ')

# ===========================================================================
# B01 — docs/protocols/work-graph.md
# ===========================================================================

# H1 present (Behavior/Invariants: an H1 heads the document; B01, unlike
# B02, does not contract a specific spelling for its own H1).
b01_h1_count=$(printf '%s\n' "$B01_BODY" | grep -cE '^# ')
check "B01: an H1 is present in the rendered body" "$([[ "${b01_h1_count:-0}" -ge 1 ]] && echo yes || echo no)" "yes"

# Six H2 sections, contracted spellings, contracted order.
B01_H2_SECTIONS=(
  "## Purpose"
  "## Focus pointer"
  "## Node entries"
  "## Real-time discipline"
  "## Viewing"
  "## Relationship to other artifacts"
)

b01_h2_prev=0
b01_h2_order_ok=yes
b01_node_entries_line=""
b01_real_time_line=""
for h in "${B01_H2_SECTIONS[@]}"; do
  ln=$(body_exact_line_no "$B01_FILE" "$B01_END" "$h")
  check "B01: H2 '$h' present with contracted spelling" "$([[ -n "$ln" ]] && echo yes || echo no)" "yes"
  if [[ "$h" == "## Node entries" ]]; then b01_node_entries_line="$ln"; fi
  if [[ "$h" == "## Real-time discipline" ]]; then b01_real_time_line="$ln"; fi
  if [[ -z "$ln" ]] || [[ "$ln" -le "$b01_h2_prev" ]]; then
    b01_h2_order_ok=no
  else
    b01_h2_prev="$ln"
  fi
done
check "B01: the six H2 sections appear in the contracted order" "$b01_h2_order_ok" "yes"

# The two machine-read marker regexes, stated verbatim in the prose.
FOCUS_REGEX_LITERAL='^Focus: (N[0-9]+|none)[[:space:]]*$'
STATUS_REGEX_LITERAL='^- Status: open[[:space:]]*$'

if printf '%s' "$FLAT_B01_BODY" | grep -qF -- "$FOCUS_REGEX_LITERAL"; then
  pass "B01: states the Focus machine-read marker regex verbatim in the prose"
else
  fail "B01: states the Focus machine-read marker regex verbatim in the prose" \
    "did not find literal '$FOCUS_REGEX_LITERAL' in the rendered body"
fi

if printf '%s' "$FLAT_B01_BODY" | grep -qF -- "$STATUS_REGEX_LITERAL"; then
  pass "B01: states the Status-open machine-read marker regex verbatim in the prose"
else
  fail "B01: states the Status-open machine-read marker regex verbatim in the prose" \
    "did not find literal '$STATUS_REGEX_LITERAL' in the rendered body"
fi

# Field-order enumeration (Goal, Status, Parent, Deps, Notes), scoped to
# the "## Node entries" section so a stray later use of one of these
# common words elsewhere in the document can't skew the ordering check.
b01_field_order_ok=no
if [[ -n "$b01_node_entries_line" && -n "$b01_real_time_line" \
      && "$b01_node_entries_line" -lt "$b01_real_time_line" ]]; then
  zone=$(sed -n "$((b01_node_entries_line + 1)),$((b01_real_time_line - 1))p" "$B01_FILE")
  goal_ln=$(printf '%s\n' "$zone" | grep -nE '\bGoal\b' | head -n1 | cut -d: -f1)
  status_ln=$(printf '%s\n' "$zone" | grep -nE '\bStatus\b' | head -n1 | cut -d: -f1)
  parent_ln=$(printf '%s\n' "$zone" | grep -nE '\bParent\b' | head -n1 | cut -d: -f1)
  deps_ln=$(printf '%s\n' "$zone" | grep -nE '\bDeps\b' | head -n1 | cut -d: -f1)
  notes_ln=$(printf '%s\n' "$zone" | grep -nE '\bNotes\b' | head -n1 | cut -d: -f1)
  if [[ -n "$goal_ln" && -n "$status_ln" && -n "$parent_ln" && -n "$deps_ln" && -n "$notes_ln" ]] \
     && [[ "$goal_ln" -lt "$status_ln" && "$status_ln" -lt "$parent_ln" \
           && "$parent_ln" -lt "$deps_ln" && "$deps_ln" -lt "$notes_ln" ]]; then
    b01_field_order_ok=yes
  fi
fi
check "B01: Node entries section enumerates fields in order Goal, Status, Parent, Deps, Notes" \
  "$b01_field_order_ok" "yes"

# No plugin/hook/script named (see file header for the per-file rationale).
assert_absent_re_i "B01: does not contain the word 'hook' in any form" "$B01_BODY" 'hook'
assert_absent_re_i "B01: does not contain the word 'script' in any form" "$B01_BODY" 'script'
assert_absent_re_i "B01: does not reference a plugins/ filesystem path" "$B01_BODY" 'plugins/'
assert_absent_re_i "B01: does not pair 'tracking' directly with 'plugin' (naming the tracking plugin)" \
  "$B01_BODY" 'tracking[[:space:]]+plugin|plugin[[:space:]]+tracking'

PLUGIN_NAMES_EXCEPT_TRACKING=(ask-in-text attribution build debugging decision-log landing lego \
  notifications orchestrator-handover privacy render-doc session-data settings skill-tracker \
  statusline updates voice worktrees)
b01_names_ok=yes
b01_names_found=""
for name in "${PLUGIN_NAMES_EXCEPT_TRACKING[@]}"; do
  if printf '%s' "$FLAT_B01_BODY" | grep -qiE "\\b${name}\\b"; then
    b01_names_ok=no
    b01_names_found="$name"
    break
  fi
done
if [[ "$b01_names_ok" == "yes" ]]; then
  pass "B01: no other repo plugin directory name is named in the body"
else
  fail "B01: no other repo plugin directory name is named in the body" "found '$b01_names_found'"
fi

# Contract-comment and NotImplemented placeholder removed at acceptance
# (checked against the raw, unscoped file — this is a presence check on
# the scaffolding artifacts themselves, not on final content).
if grep -qF -- "Contract: B01" "$B01_FILE" 2>/dev/null; then
  fail "B01: the 'Contract: B01' scaffolding HTML comment has been removed" "still present"
else
  pass "B01: the 'Contract: B01' scaffolding HTML comment has been removed"
fi

if grep -qF -- "NotImplemented: B01" "$B01_FILE" 2>/dev/null; then
  fail "B01: the NotImplemented placeholder has been removed" "still present"
else
  pass "B01: the NotImplemented placeholder has been removed"
fi

# ===========================================================================
# B02 — plugins/tracking/templates/WORKGRAPH.md
# ===========================================================================

H1_TEXT_B02='# Work Graph'
b02_h1_line=$(body_exact_line_no "$B02_FILE" "$B02_END" "$H1_TEXT_B02")
check "B02: H1 is exactly '$H1_TEXT_B02'" "$([[ -n "$b02_h1_line" ]] && echo yes || echo no)" "yes"

b02_h1_count=$(printf '%s\n' "$B02_BODY" | grep -cE '^# ')
check "B02: H1 is the only top-level '# ' heading" "${b02_h1_count:-0}" "1"

# Exactly one line matching the Focus regex, with value 'none'.
b02_focus_match_count=$(printf '%s\n' "$B02_BODY" | grep -cE "$FOCUS_REGEX_LITERAL")
check "B02: exactly one line matches the Focus machine-read marker regex" \
  "${b02_focus_match_count:-0}" "1"

b02_focus_none_line=$(body_exact_line_no "$B02_FILE" "$B02_END" "Focus: none")
check "B02: the Focus line's value is exactly 'none'" \
  "$([[ -n "$b02_focus_none_line" ]] && echo yes || echo no)" "yes"

# Example entry: heading and five field lines, exact text, contracted order.
HEADING_TEXT_B02='## N01 — [short title]'
GOAL_TEXT_B02='- Goal: [what done looks like for this node]'
STATUS_TEXT_B02='- Status: open | done | dropped ([reason])'
PARENT_TEXT_B02='- Parent: none | N<NN>'
DEPS_TEXT_B02='- Deps: none | N<NN>[, N<NN>...]'
NOTES_TEXT_B02='- Notes: [optional context]'

b02_heading_line=$(body_exact_line_no "$B02_FILE" "$B02_END" "$HEADING_TEXT_B02")
b02_goal_line=$(body_exact_line_no "$B02_FILE" "$B02_END" "$GOAL_TEXT_B02")
b02_status_line=$(body_exact_line_no "$B02_FILE" "$B02_END" "$STATUS_TEXT_B02")
b02_parent_line=$(body_exact_line_no "$B02_FILE" "$B02_END" "$PARENT_TEXT_B02")
b02_deps_line=$(body_exact_line_no "$B02_FILE" "$B02_END" "$DEPS_TEXT_B02")
b02_notes_line=$(body_exact_line_no "$B02_FILE" "$B02_END" "$NOTES_TEXT_B02")

check "B02: example entry heading is exactly '$HEADING_TEXT_B02'" \
  "$([[ -n "$b02_heading_line" ]] && echo yes || echo no)" "yes"
check "B02: Goal field line is exactly '$GOAL_TEXT_B02'" \
  "$([[ -n "$b02_goal_line" ]] && echo yes || echo no)" "yes"
check "B02: Status field line is exactly '$STATUS_TEXT_B02'" \
  "$([[ -n "$b02_status_line" ]] && echo yes || echo no)" "yes"
check "B02: Parent field line is exactly '$PARENT_TEXT_B02'" \
  "$([[ -n "$b02_parent_line" ]] && echo yes || echo no)" "yes"
check "B02: Deps field line is exactly '$DEPS_TEXT_B02'" \
  "$([[ -n "$b02_deps_line" ]] && echo yes || echo no)" "yes"
check "B02: Notes field line is exactly '$NOTES_TEXT_B02'" \
  "$([[ -n "$b02_notes_line" ]] && echo yes || echo no)" "yes"

b02_order_ok=no
if [[ -n "$b02_heading_line" && -n "$b02_goal_line" && -n "$b02_status_line" \
      && -n "$b02_parent_line" && -n "$b02_deps_line" && -n "$b02_notes_line" ]] \
   && (( b02_goal_line == b02_heading_line + 1 \
         && b02_status_line == b02_goal_line + 1 \
         && b02_parent_line == b02_status_line + 1 \
         && b02_deps_line == b02_parent_line + 1 \
         && b02_notes_line == b02_deps_line + 1 )); then
  b02_order_ok=yes
fi
check "B02: example entry fields are contiguous and in order: heading, Goal, Status, Parent, Deps, Notes" \
  "$b02_order_ok" "yes"

# Edge case: the example Status line shows the vocabulary and must NOT
# itself match the open-marker regex.
if printf '%s\n' "$STATUS_TEXT_B02" | grep -qE -- "$STATUS_REGEX_LITERAL"; then
  fail "B02: example Status line does NOT itself match the open-marker regex" "unexpectedly matched"
else
  pass "B02: example Status line does NOT itself match the open-marker regex"
fi

# N<NN> sequence-number note.
assert_contains_re_i "B02: closing line documents N<NN> as a zero-padded sequence number" \
  "$B02_BODY" 'zero[- ]padded'
assert_contains_re_i "B02: closing line documents the sequence is scoped to this file" \
  "$B02_BODY" 'scoped to this file'
assert_contains_re_i "B02: closing line documents ids are never reused" \
  "$B02_BODY" 'never[[:space:]]+reused'
assert_contains_re_i "B02: closing line illustrates the sequence (N01, N02, ...)" \
  "$B02_BODY" 'N01.{0,15}N02'

# Machine-read marker warning.
assert_contains_re_i "B02: notes the '- Status: open' marker is machine-read" \
  "$B02_BODY" 'machine-read'
assert_contains_re_i "B02: notes the marker is matched literally, modulo trailing whitespace" \
  "$B02_BODY" 'modulo trailing whitespace'
assert_contains_re_i "B02: notes rewording breaks consumer detection of the marker" \
  "$B02_BODY" 'reword'

# Bracketed placeholders present.
assert_contains_re_i "B02: bracketed placeholder [short title] present" "$B02_BODY" '\[short title\]'
assert_contains_re_i "B02: bracketed placeholder [reason] present" "$B02_BODY" '\[reason\]'
assert_contains_re_i "B02: bracketed placeholder [what done looks like for this node] present" \
  "$B02_BODY" '\[what done looks like for this node\]'
assert_contains_re_i "B02: bracketed placeholder [optional context] present" "$B02_BODY" '\[optional context\]'

# Intro entry-lifecycle content (Behavior bullets 2-3).
assert_contains_re_i "B02: intro documents one node per problem/subproblem" \
  "$B02_BODY" 'one[[:space:]]+node[[:space:]]+per[[:space:]]+(problem|subproblem)'
assert_contains_re_i "B02: intro documents nodes added at the moment they surface" \
  "$B02_BODY" 'moment[[:space:]a-z]*surfaces?'
assert_contains_re_i "B02: intro documents Status edited in place" \
  "$B02_BODY" 'in[[:space:]]+place'
assert_contains_re_i "B02: intro documents entries are never deleted" \
  "$B02_BODY" 'never[[:space:]]+deleted'
assert_contains_re_i "B02: intro documents a dropped disposition requires a reason" \
  "$B02_BODY" 'dropped\b[^.]{0,60}\breason\b'
assert_contains_re_i "B02: intro documents Focus is edited in place as attention moves" \
  "$B02_BODY" 'attention[[:space:]]+moves'

# No plugin/hook/script named — strict blanket for a template (see file
# header rationale: the sibling FOLLOWUPS.md template has zero occurrences
# of any of these words, in any sense).
assert_absent_re_i "B02: does not contain the word 'plugin' in any form" "$B02_BODY" 'plugin'
assert_absent_re_i "B02: does not contain the word 'hook' in any form" "$B02_BODY" 'hook'
assert_absent_re_i "B02: does not contain the word 'script' in any form" "$B02_BODY" 'script'
assert_absent_re_i "B02: does not reference a plugins/ filesystem path" "$B02_BODY" 'plugins/'

PLUGIN_NAMES_ALL=(ask-in-text attribution build debugging decision-log landing lego notifications \
  orchestrator-handover privacy render-doc session-data settings skill-tracker statusline tracking \
  updates voice worktrees)
b02_names_ok=yes
b02_names_found=""
for name in "${PLUGIN_NAMES_ALL[@]}"; do
  if printf '%s' "$FLAT_B02_BODY" | grep -qiE "\\b${name}\\b"; then
    b02_names_ok=no
    b02_names_found="$name"
    break
  fi
done
if [[ "$b02_names_ok" == "yes" ]]; then
  pass "B02: no repo plugin directory name is named in the body"
else
  fail "B02: no repo plugin directory name is named in the body" "found '$b02_names_found'"
fi

# Contract-comment and NotImplemented placeholder removed at acceptance.
if grep -qF -- "Contract: B02" "$B02_FILE" 2>/dev/null; then
  fail "B02: the 'Contract: B02' scaffolding HTML comment has been removed" "still present"
else
  pass "B02: the 'Contract: B02' scaffolding HTML comment has been removed"
fi

if grep -qF -- "NotImplemented: B02" "$B02_FILE" 2>/dev/null; then
  fail "B02: the NotImplemented placeholder has been removed" "still present"
else
  pass "B02: the NotImplemented placeholder has been removed"
fi

# ===========================================================================
# Agreement: B02's marker spellings agree exactly with the regexes B01
# states. Extracted from B01's own rendered body and applied, as real
# regexes, against B02's actual content — not two independently hardcoded
# literals — so drift between the two files is what's being caught here,
# not just drift from this test's own assumptions about the spelling.
# ===========================================================================

focus_regex_extracted=$(printf '%s' "$FLAT_B01_BODY" | grep -oE '`\^Focus:[^`]*\$`' | head -n1)
focus_regex_extracted="${focus_regex_extracted#\`}"
focus_regex_extracted="${focus_regex_extracted%\`}"

status_regex_extracted=$(printf '%s' "$FLAT_B01_BODY" | grep -oE '`\^- Status: open[^`]*\$`' | head -n1)
status_regex_extracted="${status_regex_extracted#\`}"
status_regex_extracted="${status_regex_extracted%\`}"

if [[ -z "$focus_regex_extracted" ]]; then
  fail "Agreement: B01's stated Focus regex matches B02's example Focus line ('Focus: none')" \
    "could not extract the Focus regex from B01's rendered body"
elif printf '%s\n' "Focus: none" | grep -qE -- "$focus_regex_extracted"; then
  pass "Agreement: B01's stated Focus regex matches B02's example Focus line ('Focus: none')"
else
  fail "Agreement: B01's stated Focus regex matches B02's example Focus line ('Focus: none')" \
    "extracted regex '$focus_regex_extracted' did not match B02's Focus line"
fi

if [[ -z "$status_regex_extracted" ]]; then
  fail "Agreement: B01's stated Status-open regex does NOT match B02's example enum line" \
    "could not extract the Status-open regex from B01's rendered body"
elif printf '%s\n' "$STATUS_TEXT_B02" | grep -qE -- "$status_regex_extracted"; then
  fail "Agreement: B01's stated Status-open regex does NOT match B02's example enum line" \
    "extracted regex '$status_regex_extracted' unexpectedly matched B02's enum line"
else
  pass "Agreement: B01's stated Status-open regex does NOT match B02's example enum line"
fi

# ===========================================================================
# 003-B21 — authoring defaults recorded (plan 003-followup-fixes, issue #333)
#
# Source of truth: the "Contract: 003-B21 ... protocol half" HTML comment
# atop docs/protocols/work-graph.md, and the "Contract: 003-B21 ... tracking
# half" bash comment above the rules heredoc in
# plugins/tracking/scripts/session-context.sh. Three authoring defaults,
# stated by the protocol document (normative) and restated by the template
# it is instantiated from:
#   (1) node titles in plain language, embedding no foreign id scheme —
#       N<NN> is the only identifier a title needs, and ids from other
#       numbering systems live in `Notes:` or in the artifacts that own them;
#   (2) one node per ACTUAL work item — a problem worked as distinct phases
#       by distinct actors gets one node per phase, each with its own
#       dependency edge, so who is doing what right now reads from the
#       graph alone;
#   (3) a follow-up captured mid-effort gets a node AT CAPTURE, with its
#       disposition mirrored onto that node when the follow-up resolves.
#
# Scoped to $B01_BODY / $B02_BODY (everything after the leading contract
# comment's closing '-->'), exactly as every other clause in this suite is:
# both scaffold comments state these defaults in full, so an unscoped read
# would let each assertion pass against the COMMENT on the unimplemented
# stub. Both bodies were verified to match none of these patterns before
# the assertions were written.
#
# Wording is not contracted verbatim, so these are flexible token/proximity
# regexes on the load-bearing facts, the same style the rest of this suite
# and workgraph-docs.test.sh use.
#
# Two 003-B21 clauses add no assertions here, because assertions already in
# this file cover them over the whole body — new prose included:
#   - Outputs "no machine-read marker changes": the verbatim Focus and
#     Status-open regex checks, the Goal/Status/Parent/Deps/Notes field-order
#     check, and the Agreement block above all re-run against the extended
#     document.
#   - Invariants "names no plugin" / "every existing section's semantics are
#     unchanged, the guidance is additive": the B01 and B02 hook/script/
#     plugins-path/plugin-name absence scans and the six-H2 presence-and-
#     order check likewise cover the extended document. (Note for the
#     implementation wave: the B02 scan forbids the substring "script" in
#     any form, so "descriptive"/"prescriptive" would fail it.)
# ===========================================================================

B21_TITLES_RE='titles?[^.]{0,80}plain[ -]language|plain[ -]language[^.]{0,80}titles?'
B21_ONLYID_RE='only[[:space:]]+identifier'
B21_NUMBERING_RE='numbering[[:space:]]+systems?|(other|another|foreign)[^.]{0,40}(numbering|id scheme)'
B21_ONE_PER_RE='(one|a)[[:space:]]+node[[:space:]]+per[^.]{0,40}work[[:space:]]+item'
B21_PHASE_ACTOR_RE='phases?[^.]{0,140}actors?|actors?[^.]{0,140}phases?'
B21_OWN_NODE_RE='own[[:space:]]+node'
B21_OWN_DEP_RE='own[^.]{0,30}(dependency|dep\b|deps\b)'
B21_FU_CAPTURE_RE='follow-?up[^.]{0,160}captur|captur[^.]{0,160}follow-?up'
B21_AT_CAPTURE_RE='at[[:space:]]+captur|moment[^.]{0,40}captur|when[^.]{0,30}captur'

# --- Default 1: plain-language titles, no foreign id scheme (B01) ---

assert_contains_re_i "B21/B01: node titles are plain language" \
  "$B01_BODY" "$B21_TITLES_RE"
assert_contains_re_i "B21/B01: N<NN> is the only identifier a title needs" \
  "$B01_BODY" "$B21_ONLYID_RE"
assert_contains_re_i "B21/B01: ids from other numbering systems are excluded from titles" \
  "$B01_BODY" "$B21_NUMBERING_RE"
assert_contains_re_i "B21/B01: those ids belong in Notes: or the artifacts that own them" \
  "$B01_BODY" 'notes[^.]{0,140}(own|belong)|(own|belong)[^.]{0,140}notes'

# --- Default 2: one node per actual work item (B01) ---

assert_contains_re_i "B21/B01: one node per ACTUAL work item" \
  "$B01_BODY" "$B21_ONE_PER_RE"
assert_contains_re_i "B21/B01: distinct phases are worked by distinct actors" \
  "$B01_BODY" "$B21_PHASE_ACTOR_RE"
assert_contains_re_i "B21/B01: each such phase is its own node" \
  "$B01_BODY" "$B21_OWN_NODE_RE"
assert_contains_re_i "B21/B01: each such phase carries its own dependency edge" \
  "$B01_BODY" "$B21_OWN_DEP_RE"
assert_contains_re_i "B21/B01: who is doing what right now reads from the graph alone" \
  "$B01_BODY" 'graph[[:space:]]+alone'

# --- Default 3: a follow-up gets a node at capture, disposition mirrored (B01) ---

assert_contains_re_i "B21/B01: a follow-up captured mid-effort gets a node" \
  "$B01_BODY" "$B21_FU_CAPTURE_RE"
assert_contains_re_i "B21/B01: that node is added AT CAPTURE, not when the follow-up resolves" \
  "$B01_BODY" "$B21_AT_CAPTURE_RE"
assert_contains_re_i "B21/B01: the follow-up's disposition is mirrored onto that node" \
  "$B01_BODY" 'mirror'
assert_contains_re_i "B21/B01: the mirroring happens as/when the follow-up resolves" \
  "$B01_BODY" 'mirror[^.]{0,160}resolv|resolv[^.]{0,160}mirror'

# --- The WORKGRAPH template states the same three defaults (B02) ---

assert_contains_re_i "B21/B02: template states node titles are plain language" \
  "$B02_BODY" "$B21_TITLES_RE"
assert_contains_re_i "B21/B02: template states N<NN> is the only identifier a title needs" \
  "$B02_BODY" "$B21_ONLYID_RE"
assert_contains_re_i "B21/B02: template excludes other numbering systems from titles" \
  "$B02_BODY" "$B21_NUMBERING_RE"
assert_contains_re_i "B21/B02: template states one node per ACTUAL work item" \
  "$B02_BODY" "$B21_ONE_PER_RE"
assert_contains_re_i "B21/B02: template states distinct phases are worked by distinct actors" \
  "$B02_BODY" "$B21_PHASE_ACTOR_RE"
assert_contains_re_i "B21/B02: template states each such phase is its own node" \
  "$B02_BODY" "$B21_OWN_NODE_RE"
assert_contains_re_i "B21/B02: template states each such phase carries its own dependency edge" \
  "$B02_BODY" "$B21_OWN_DEP_RE"
assert_contains_re_i "B21/B02: template states a follow-up captured mid-effort gets a node" \
  "$B02_BODY" "$B21_FU_CAPTURE_RE"
assert_contains_re_i "B21/B02: template states the follow-up's disposition is mirrored onto that node" \
  "$B02_BODY" 'mirror'

# Acceptance: the 003-B21 protocol-half contract comment is removed (checked
# against the raw file, same as the B01/B02 checks above).
if grep -qF -- "Contract: 003-B21" "$B01_FILE" 2>/dev/null; then
  fail "B21: the 'Contract: 003-B21' scaffolding HTML comment has been removed from the protocol doc" "still present"
else
  pass "B21: the 'Contract: 003-B21' scaffolding HTML comment has been removed from the protocol doc"
fi

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$FAILED"
