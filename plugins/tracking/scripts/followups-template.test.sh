#!/bin/bash
# Structural/contract tests for B01 followups-template: the "Contract: B01
# followups-template" HTML-comment docblock at the top of
# plugins/tracking/templates/FOLLOWUPS.md is the source of truth.
#
# Scoped to the "Outputs (required document structure — tests assert
# these)" section, plus the Invariants and Edge cases sections named in the
# brief. The Behavior/Inputs/Errors sections describe how OTHER blocks
# (B02 followups-capture-and-surfacing, B03 followups-closeout-gate — both
# still NotImplemented stubs elsewhere) consume a *filled* FOLLOWUPS.md at
# runtime; this suite only checks the static template document B01 itself
# is responsible for, and does not exercise those other scripts.
#
# Two contract-described facts are deliberately NOT asserted here, same
# spirit as b08-templates.test.sh's exclusions:
#   - Invariant "nothing in the primary work graph is required to point
#     back" describes a property of files OTHER than FOLLOWUPS.md (blocks.md,
#     plans, PRs) — there is nothing in FOLLOWUPS.md's own text to assert.
#   - Edge case "File absent -> zero captures, consumers treat absence as
#     'nothing open' (valid, not an error)" describes B02/B03 consumer
#     behavior when the file doesn't exist; it is not a property of the
#     template's content and is covered by those blocks' own test suites.
#
# The one example entry's number is asserted as exactly "F01": the contract
# both shows a single example and explains the numbering scheme starting
# "(F01, F02, ...)", so the natural (and only deterministic) choice for the
# lone example is F01.
#
# Hermetic: reads only the template file at its fixed repo location
# (resolved from this script's own path), no mutation, no network.
#
# Run: bash plugins/tracking/scripts/followups-template.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$PLUGIN_ROOT/templates/FOLLOWUPS.md"

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

# Line number of the first line matching fixed string $2 exactly, or "".
# The `--` guards against field-line patterns like "- Status: ..." that
# begin with '-' and would otherwise be misparsed as grep options.
exact_line_no() { # file exact_text
  grep -nxF -- "$2" "$1" 2>/dev/null | head -n1 | cut -d: -f1
}

# assert_contains_re_i <label> <haystack> <ERE, case-insensitive>
# Flattens embedded newlines to spaces first: grep matches per physical
# line by default, but the haystack is often hard-wrapped markdown prose
# where a proximity regex's two halves may land on different source lines.
assert_contains_re_i() {
  local flat
  flat=$(printf '%s' "$2" | tr '\n' ' ')
  if printf '%s' "$flat" | grep -qiE -- "$3"; then
    pass "$1"
  else
    fail "$1" "did not match regex (case-insensitive): $3"
  fi
}

check "FOLLOWUPS.md template file exists" "$([[ -f "$TEMPLATE" ]] && echo yes || echo no)" "yes"

# ===========================================================================
# H1
# ===========================================================================

H1_TEXT='# Follow-ups'
h1_line=$(exact_line_no "$TEMPLATE" "$H1_TEXT")
check "H1 is exactly '$H1_TEXT'" "$([[ -n "$h1_line" ]] && echo yes || echo no)" "yes"

h1_count=$(grep -cE '^# ' "$TEMPLATE" 2>/dev/null)
check "H1 is the only top-level '# ' heading" "${h1_count:-0}" "1"

# ===========================================================================
# Entry format: locate the single example heading first, since the usage
# paragraph is defined as the zone between H1 and this heading.
# ===========================================================================

heading_line=$(grep -nE '^## F[0-9]{2} — ' "$TEMPLATE" 2>/dev/null | head -n1 | cut -d: -f1)
heading_count=$(grep -cE '^## F[0-9]+ ' "$TEMPLATE" 2>/dev/null)
check "exactly one example entry heading ('## F<NN> — ...') is present" "${heading_count:-0}" "1"

HEADING_TEXT='## F01 — [short title]'
check "the example heading is exactly '$HEADING_TEXT'" \
  "$([[ -n "$heading_line" && "$(sed -n "${heading_line}p" "$TEMPLATE" 2>/dev/null)" == "$HEADING_TEXT" ]] && echo yes || echo no)" \
  "yes"

# ===========================================================================
# Usage paragraph (Outputs bullet 1): the zone strictly between H1 and the
# example heading. Wording is not contracted verbatim, so these are
# flexible token/proximity regexes on the load-bearing facts the contract
# names, not exact-prose matches.
# ===========================================================================

usage_zone=""
if [[ -n "$h1_line" && -n "$heading_line" && "$h1_line" -lt "$heading_line" ]]; then
  usage_zone=$(sed -n "$((h1_line + 1)),$((heading_line - 1))p" "$TEMPLATE")
fi

assert_contains_re_i "usage paragraph: one entry per follow-up" "$usage_zone" \
  'one[[:space:]]+entry[[:space:]]+per[[:space:]]+follow-?up'
assert_contains_re_i "usage paragraph: entries appended at mention time" "$usage_zone" \
  'appended'
assert_contains_re_i "usage paragraph: appended AT MENTION TIME (not batched later)" "$usage_zone" \
  'mention'
assert_contains_re_i "usage paragraph: entries are dispositioned (Status edited) in place" "$usage_zone" \
  'disposition'
assert_contains_re_i "usage paragraph: dispositioned IN PLACE" "$usage_zone" \
  'in[[:space:]]+place'
assert_contains_re_i "usage paragraph: entries are never deleted" "$usage_zone" \
  'never[[:space:]]+deleted'
assert_contains_re_i "usage paragraph: dropped requires a reason" "$usage_zone" \
  'dropped\b[^.]{0,60}\breason\b'

# ===========================================================================
# Entry format (Outputs bullet 2): the exact field lines, contiguous and in
# order directly under the one example heading.
# ===========================================================================

STATUS_TEXT='- Status: open | filed [issue-ref] | resolved | dropped ([reason])'
CAPTURED_TEXT='- Captured: [YYYY-MM-DD]'
SOURCE_TEXT='- Source: [provenance — where/how it surfaced, e.g. "verifying U15"]'
REFS_TEXT='- Refs: [soft refs: blocks, plans, PRs, issues] | none'
STATEMENT_TEXT='- Statement: [the follow-up in one or two sentences]'

status_line=$(exact_line_no "$TEMPLATE" "$STATUS_TEXT")
captured_line=$(exact_line_no "$TEMPLATE" "$CAPTURED_TEXT")
source_line=$(exact_line_no "$TEMPLATE" "$SOURCE_TEXT")
refs_line=$(exact_line_no "$TEMPLATE" "$REFS_TEXT")
statement_line=$(exact_line_no "$TEMPLATE" "$STATEMENT_TEXT")

check "Status field line is exactly '$STATUS_TEXT' (the exact Status enum)" \
  "$([[ -n "$status_line" ]] && echo yes || echo no)" "yes"
check "Captured field line is exactly '$CAPTURED_TEXT'" \
  "$([[ -n "$captured_line" ]] && echo yes || echo no)" "yes"
check "Source field line is exactly '$SOURCE_TEXT'" \
  "$([[ -n "$source_line" ]] && echo yes || echo no)" "yes"
check "Refs field line is exactly '$REFS_TEXT' (soft-refs vocabulary + 'none' alt for out-of-scope items)" \
  "$([[ -n "$refs_line" ]] && echo yes || echo no)" "yes"
check "Statement field line is exactly '$STATEMENT_TEXT'" \
  "$([[ -n "$statement_line" ]] && echo yes || echo no)" "yes"

# Contiguous order: heading, Status, Captured, Source, Refs, Statement, each
# directly below the previous line (the contract shows ONE tight block, no
# blank lines between fields).
order_ok=no
if [[ -n "$heading_line" && -n "$status_line" && -n "$captured_line" \
      && -n "$source_line" && -n "$refs_line" && -n "$statement_line" ]] \
   && (( status_line == heading_line + 1 \
         && captured_line == status_line + 1 \
         && source_line == captured_line + 1 \
         && refs_line == source_line + 1 \
         && statement_line == refs_line + 1 )); then
  order_ok=yes
fi
check "entry format fields are contiguous and in order: heading, Status, Captured, Source, Refs, Statement" \
  "$order_ok" "yes"

# ===========================================================================
# Machine-read open marker (Invariant): the Status line's "open" alternative
# must be spelled/spaced so that a real entry reading just "- Status: open"
# (nothing else on the line) is an exact prefix match — this is the literal
# marker consumed by keep-working.sh's close-out gate (B03) and
# session-context.sh's surfacing (B02).
# ===========================================================================

open_marker_ok=no
if [[ -n "$status_line" ]] && sed -n "${status_line}p" "$TEMPLATE" | grep -qE '^- Status: open( |$)'; then
  open_marker_ok=yes
fi
check "Status line's 'open' alternative is the exact machine-read marker prefix ('- Status: open')" \
  "$open_marker_ok" "yes"

# ===========================================================================
# Bracketed placeholders (Invariant): every documented placeholder value
# uses [brackets] so an unfilled example is recognizable. The exact-line
# checks above already require this for the field values verbatim; these
# assert the invariant directly against the [issue-ref] / [reason] tokens
# nested inside the Status enum's non-open alternatives.
# ===========================================================================

status_text=$([[ -n "$status_line" ]] && sed -n "${status_line}p" "$TEMPLATE" || echo "")
assert_contains_re_i "Status enum's 'filed' alternative placeholder uses [brackets] ('[issue-ref]')" \
  "$status_text" '\[issue-ref\]'
assert_contains_re_i "Status enum's 'dropped' alternative placeholder uses [brackets] ('([reason])')" \
  "$status_text" '\(\[reason\]\)'

# ===========================================================================
# Edge case: several items captured the same day get distinct F<NN>, same
# Captured date — enabled by F<NN> being a zero-padded sequence number
# scoped to this file (not reset per day). This numbering rule must be
# documented in the rendered document BODY (not merely inherited from the
# leading contract comment, which is scaffolding documentation, not the
# document this block's Outputs promises) for a reader to number entry #2
# correctly. Scope the check to strictly after the comment's closing '-->'
# so it can't pass against the stub on the strength of the comment alone.
#
# Once the block has landed the scaffolding comment is removed outright (the
# prose-block rule in lego's scaffold skill), leaving no '-->' at all. That
# is the fully-implemented state, not an empty document: with no leading
# comment the whole file IS the rendered body.
# ===========================================================================

comment_end_line=$(grep -n -- '-->' "$TEMPLATE" 2>/dev/null | head -n1 | cut -d: -f1)
if [[ -n "$comment_end_line" ]]; then
  body_text=$(sed -n "$((comment_end_line + 1)),\$p" "$TEMPLATE")
else
  body_text=$(cat "$TEMPLATE")
fi

assert_contains_re_i "rendered body documents F<NN> as a zero-padded sequence number" "$body_text" \
  'zero[- ]padded'
assert_contains_re_i "rendered body documents the sequence is scoped to this file (not per-day, not global)" "$body_text" \
  'scoped to this file'

# ===========================================================================
# NotImplemented placeholder is gone once implemented (mirrors the sibling
# B06 check in session-context.test.sh for plugins/tracking/templates/TODO.md).
# ===========================================================================

if grep -q 'NotImplemented: B01' "$TEMPLATE" 2>/dev/null; then
  fail "NotImplemented placeholder comment removed once implemented" "placeholder still present"
else
  pass "NotImplemented placeholder comment removed once implemented"
fi

# ===========================================================================
# 003-B21 — authoring defaults recorded (plan 003-followup-fixes, issue #333)
#
# Source of truth: the "Contract: 003-B21 ... tracking half" bash comment
# above the rules heredoc in plugins/tracking/scripts/session-context.sh,
# which requires "the templates it points at (templates/WORKGRAPH.md and
# templates/FOLLOWUPS.md)" to state the authoring defaults recorded in
# docs/protocols/work-graph.md.
#
# Two of the three defaults have a meaning in THIS template and are asserted
# here:
#   - plain-language titles embedding no foreign id scheme: this template's
#     own entry heading carries a `[short title]`, so the rule applies to it
#     directly;
#   - a follow-up captured mid-effort gets a work-graph node AT CAPTURE, with
#     its disposition mirrored onto that node as the entry resolves — the one
#     default that is specifically about follow-ups.
# The third ("one node per ACTUAL work item — distinct phases by distinct
# actors get distinct nodes") is a graph-structure rule about nodes this
# document does not own; it is asserted against docs/protocols/work-graph.md
# and templates/WORKGRAPH.md in workgraph-template.test.sh instead of being
# forced into a follow-ups list. Flagged rather than silently skipped: if the
# orchestrator reads the contract as requiring all three verbatim in both
# templates, this is the assertion to add.
#
# Scoped to $body_text (the comment-scoped body established above) for the
# same reason the F<NN> numbering clauses are: this template carries no
# scaffold comment today, so $body_text is the whole file, but the scoping
# survives one being added. Verified against the current template: none of
# these patterns match today.
# ===========================================================================

assert_contains_re_i "B21: entry titles are plain language" "$body_text" \
  'titles?[^.]{0,80}plain[ -]language|plain[ -]language[^.]{0,80}titles?'
assert_contains_re_i "B21: a follow-up captured mid-effort also gets a work-graph node" "$body_text" \
  'node[^.]{0,160}captur|captur[^.]{0,160}node'
assert_contains_re_i "B21: that node is added AT CAPTURE, not when the entry resolves" "$body_text" \
  'at[[:space:]]+captur|moment[^.]{0,40}captur|when[^.]{0,30}captur'
assert_contains_re_i "B21: the entry's disposition is mirrored onto that node" "$body_text" \
  'mirror[^.]{0,140}node|node[^.]{0,140}mirror'

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$FAILED"
