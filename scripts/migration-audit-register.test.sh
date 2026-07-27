#!/bin/bash
# Test for Block B03 (audit-candidate-register). Authoritative contract: the
# HTML-comment docblock "Contract: B03 audit-candidate-register (plan
# 001-github-issue-13)" in MIGRATION.md, immediately above the one section it
# governs:
#
#   ## Migration candidate register
#
# B03 is a composition block: it invents no findings, it composes B01's and
# B02's already-accepted, already-merged sections into one register. Asserts
# directly on MIGRATION.md, the single file the contract names as B03's
# output. Follows the check()/PASS/FAIL/FAILED/exit shape of
# plugins/render-doc/scripts/migration.test.sh and
# scripts/migration-audit-surfaces.test.sh / scripts/migration-audit-
# reconcile.test.sh (B01's and B02's, both accepted and merged), and strips
# HTML comments before asserting for the same reason those precedents do:
# the B03 docblock itself quotes the exact heading, the column names, and
# the four recommendation values these checks look for, so without
# stripping, the docblock's own prose would satisfy a check before the real
# content exists.
#
# Hermetic by design: every assertion below reads only this repo's
# MIGRATION.md and (via subprocess) this repo's own migration.test.sh /
# migration-audit-surfaces.test.sh / migration-audit-reconcile.test.sh.
# Nothing here stats, greps, or invokes git against any source-repo
# worktree path — those paths were research inputs for B01/B02, not
# assertable by a test that must also pass in CI, where they do not exist.
#
# Discrimination self-tests: a regex or derivation helper whose target
# content does not exist ANYWHERE in the repo yet can fail red for the
# wrong reason — "always false" looks identical to "correctly false" in a
# single run (this plan's own U01 hit exactly this: two checks used a
# `\`[^\`]+\`` pattern with a stray backslash before an ordinary character,
# undefined in POSIX ERE, that matched nothing, ever). Below, each
# non-trivial helper is proven against content that satisfies its clause
# before being trusted, using real content elsewhere in the file where a
# positive case already exists (stronger than a fixture, and free), and a
# synthetic string otherwise.
#
# The empty register (zero migration candidates) is a legitimate, meaningful
# outcome per the contract's own Edge cases clause — issue #13 asks "what
# (if anything) should be brought over". This test must not assume the table
# is non-empty: every table-shape check below is gated on data rows actually
# being present, and a separate branch below covers the all-zero outcome.
#
# Run: bash scripts/migration-audit-register.test.sh (non-zero exit on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MIGRATION="$ROOT/MIGRATION.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "MIGRATION.md exists" \
  "$([ -f "$MIGRATION" ] && echo yes || echo no)" "yes"

# Every check below reads $BODY: MIGRATION.md with all contract docblocks
# stripped out, so a docblock's own prose (which necessarily quotes the
# strings this test looks for) can never satisfy a check meant for real
# content.
BODY="$(sed '/<!--/,/-->/d' "$MIGRATION" 2>/dev/null)"

# Section-body extractor: from a "## " heading matched by exact text, up to
# (not including) the next "## " heading or EOF. Mirrors migration.test.sh's
# rd_section() / the siblings' section_body().
section_body() { # exact_heading_text
  awk -v h="$1" '
    $0 == h { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$BODY"
}

section_nonempty() { # section_text
  local trimmed
  trimmed="$(grep -v '^[[:space:]]*$' <<<"$1")"
  [ -n "$trimmed" ] && [ "$(wc -c <<<"$trimmed")" -gt 20 ]
}

REGISTER="$(section_body '## Migration candidate register')"

# =====================================================================
# Behavior / Inputs
#   "Composes B01's and B02's findings ... invents no findings of its own."
#   "Writes ONLY MIGRATION.md." / "No source-repo access is required."
#   Hermeticity: this test file itself must never reference a source-repo
#   worktree path, so it stays runnable in CI, where those paths do not
#   exist. Same guard, same rationale, as B01's and B02's tests.
# =====================================================================

FORBIDDEN_PATH_RE='/github/clam-code(-generic)?-trees'
check "this test file itself never references a source-repo worktree path (hermeticity)" \
  "$(grep -qE "$FORBIDDEN_PATH_RE" "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" && echo present || echo absent)" "absent"

# "Writes ONLY MIGRATION.md" and "invents no findings of its own / every row
# traces to a section written by B01 or B02" are process properties of the
# implementation, not independently assertable as MIGRATION.md text — the
# same treatment the siblings give their own analogous clauses. Mechanically
# enforced by realm-check.sh restricting the implementation unit to
# MIGRATION.md alone; row-level traceability is a conclusion this test must
# not fake (per this unit's brief: "what you cannot test ... whether the
# register's rows are correct").

# =====================================================================
# Outputs — exactly one "## Migration candidate register" section
# =====================================================================

check "stripped MIGRATION.md has exactly one 'Migration candidate register' heading" \
  "$(grep -cE '^## Migration candidate register$' <<<"$BODY")" "1"
check "register section has substantive content" \
  "$(section_nonempty "$REGISTER" && echo yes || echo no)" "yes"

# =====================================================================
# Table shape helpers
# =====================================================================

# All "| ... |" lines within the register section, in order. Covers both
# plausible zero-candidate renderings: a header-only table (this is
# non-empty) and no table at all (this is empty) — neither is forbidden by
# the contract, which only pins the all-zero outcome's PROSE and COUNT
# requirements (exercised below), not whether an empty table is present.
table_lines() { # section_text
  grep -E '^\|' <<<"$1"
}

# A markdown table separator row: "| --- | --- | ... |" (dashes, optional
# colons for alignment, in any number of pipe-delimited cells).
is_separator_row() {
  grep -qE '^\|?[[:space:]]*:?-+:?[[:space:]]*(\|[[:space:]]*:?-+:?[[:space:]]*)+\|?$' <<<"$1"
}

# Normalizes a "| a | b | c |" row into "a|b|c" — trims leading/trailing
# pipes and per-cell whitespace so header/value comparisons don't depend on
# incidental column padding.
normalize_row() { # row_text
  local row="$1"
  row="${row#|}"; row="${row%|}"
  awk -F'|' '{
    out = "";
    for (i = 1; i <= NF; i++) {
      gsub(/^[ \t]+/, "", $i); gsub(/[ \t]+$/, "", $i);
      out = out (i > 1 ? "|" : "") $i
    }
    print out
  }' <<<"$row"
}

# Discrimination self-test for normalize_row, both directions, synthetic:
check "normalize_row helper: strips padding and outer pipes (positive, synthetic)" \
  "$(normalize_row '|  Element  | Source surface  |')" "Element|Source surface"
check "normalize_row helper: a differently-worded row does not collapse to the same string (negative, synthetic)" \
  "$([ "$(normalize_row '| Foo | Bar |')" = "Element|Source surface" ] && echo same || echo different)" "different"

TABLE_LINES="$(table_lines "$REGISTER")"
TABLE_LINE_COUNT="$(grep -c '.' <<<"$TABLE_LINES" 2>/dev/null || echo 0)"
[ -z "$TABLE_LINES" ] && TABLE_LINE_COUNT=0

HEADER_LINE=""
DATA_LINES=""
if [ "$TABLE_LINE_COUNT" -gt 0 ]; then
  HEADER_LINE="$(sed -n '1p' <<<"$TABLE_LINES")"
  REST_LINES="$(sed -n '2,$p' <<<"$TABLE_LINES")"
  if [ -n "$REST_LINES" ] && is_separator_row "$(sed -n '1p' <<<"$REST_LINES")"; then
    DATA_LINES="$(sed -n '2,$p' <<<"$REST_LINES")"
  else
    # No separator row present (malformed table) — treat everything after
    # the header as data so the header/column checks below still run and
    # fail for the right reason rather than silently skipping.
    DATA_LINES="$REST_LINES"
  fi
fi

# =====================================================================
# Outputs — the table's header, when a table is present at all, carries
# exactly the five contract-named columns in order. Gated on a table
# existing so a zero-candidate register that omits the table entirely is
# never penalized (see the file-level note on the empty-register edge case).
# =====================================================================

EXPECTED_HEADER="Element|Source surface|Current status|Recommendation|Rationale"
if [ -n "$HEADER_LINE" ]; then
  check "register table header matches the five contract-named columns, in order" \
    "$(normalize_row "$HEADER_LINE")" "$EXPECTED_HEADER"
else
  echo "PASS  register table header matches the five contract-named columns, in order -> no table present (n/a, sanctioned for a zero-candidate register)"
fi

# =====================================================================
# Outputs — recommendation vocabulary is closed: exactly port, drop,
# out of scope, needs decision. A fifth value is a contract violation ("the
# contract says never invent one"). Gated on data rows existing; vacuously
# true (0 bad out of 0 rows) when the register is empty, which is correct —
# an empty register cannot contain an invented value.
# =====================================================================

ALLOWED_RECS='^(port|drop|out of scope|needs decision)$'

row_field() { # normalized_row column_index(1-based)
  awk -F'|' -v i="$2" '{print $i}' <<<"$1"
}

# Discrimination self-test for row_field, both directions, synthetic:
check "row_field helper: extracts the 4th column of a synthetic row (positive, synthetic)" \
  "$(row_field 'a|b|c|port|e' 4)" "port"
check "row_field helper: a value from the wrong column does not match (negative, synthetic)" \
  "$([ "$(row_field 'a|b|c|port|e' 5)" = "port" ] && echo same || echo different)" "different"

BAD_RECS=0
RECS_IN_ORDER=""
ELEMENT_ROW_COUNT=0
BLANK_CELL_ROWS=0
NEEDS_DECISION_NO_QUESTION=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  norm="$(normalize_row "$line")"
  rec="$(row_field "$norm" 4)"
  ELEMENT_ROW_COUNT=$((ELEMENT_ROW_COUNT + 1))
  RECS_IN_ORDER="$RECS_IN_ORDER$rec"$'\n'
  if ! grep -qE "$ALLOWED_RECS" <<<"$rec"; then
    BAD_RECS=$((BAD_RECS + 1))
    echo "      row uses a recommendation value outside the closed vocabulary: '$rec'"
  fi
  for col in 1 2 3 4 5; do
    cell="$(row_field "$norm" "$col")"
    [ -n "$cell" ] || BLANK_CELL_ROWS=$((BLANK_CELL_ROWS + 1))
  done
  if [ "$rec" = "needs decision" ]; then
    rationale="$(row_field "$norm" 5)"
    grep -qF '?' <<<"$rationale" || NEEDS_DECISION_NO_QUESTION=$((NEEDS_DECISION_NO_QUESTION + 1))
  fi
done <<<"$DATA_LINES"

check "every data row's Recommendation is one of the four closed-vocabulary values (never a fifth)" \
  "$BAD_RECS" "0"
check "no data row has a blank cell in any of the five columns" \
  "$BLANK_CELL_ROWS" "0"
check "every 'needs decision' row's Rationale cell carries the question (a '?')" \
  "$NEEDS_DECISION_NO_QUESTION" "0"

# Discrimination self-test for the closed-vocabulary check, both directions,
# synthetic (no real register content exists yet to test against):
check "closed-vocabulary regex: an invented fifth value is rejected (negative, synthetic)" \
  "$(grep -qE "$ALLOWED_RECS" <<<"maybe" && echo yes || echo no)" "no"
check "closed-vocabulary regex: each of the four sanctioned values is accepted (positive, synthetic)" \
  "$(bad=0; for v in port drop 'out of scope' 'needs decision'; do grep -qE "$ALLOWED_RECS" <<<"$v" || bad=$((bad+1)); done; echo "$bad")" "0"

# =====================================================================
# Outputs — ordering: rows are ordered by recommendation, "port" first, so
# the actionable set reads at the top. Gated on data rows existing.
# =====================================================================

ordering_port_first() { # newline-separated recommendation values, in row order
  local list="$1" val seen_non_port=0
  while IFS= read -r val; do
    [ -n "$val" ] || continue
    if [ "$val" = "port" ]; then
      [ "$seen_non_port" = "1" ] && { echo no; return; }
    else
      seen_non_port=1
    fi
  done <<<"$list"
  echo yes
}

# Discrimination self-test, both directions, synthetic:
check "ordering helper: port-first list passes (positive, synthetic)" \
  "$(ordering_port_first "$(printf 'port\nport\ndrop\nneeds decision\n')")" "yes"
check "ordering helper: a port row after a non-port row fails (negative, synthetic)" \
  "$(ordering_port_first "$(printf 'drop\nport\nneeds decision\n')")" "no"

if [ "$ELEMENT_ROW_COUNT" -gt 0 ]; then
  check "data rows are ordered with all 'port' recommendations first" \
    "$(ordering_port_first "$RECS_IN_ORDER")" "yes"
else
  echo "PASS  data rows are ordered with all 'port' recommendations first -> no data rows (n/a, empty register)"
fi

# =====================================================================
# Outputs — the count line below the table: one count per recommendation
# value, and the counts must actually match the table's rows (not just be
# present in the right shape).
# =====================================================================

count_for() { # label section_text
  grep -oE "$1:[[:space:]]*[0-9]+" <<<"$2" | head -n1 | grep -oE '[0-9]+$'
}

# Discrimination self-test for count_for, both directions, synthetic:
check "count_for helper: extracts a labeled count from synthetic text (positive, synthetic)" \
  "$(count_for 'drop' 'port: 7 · drop: 3 · out of scope: 12 · needs decision: 2')" "3"
check "count_for helper: a label that is not present yields nothing (negative, synthetic)" \
  "$([ -z "$(count_for 'dropped' 'port: 7 · drop: 3')" ] && echo empty || echo nonempty)" "empty"

COUNT_LINE="$(grep -E 'port:.*drop:.*out of scope:.*needs decision:' <<<"$REGISTER" | head -n1)"
check "register has a count line naming all four recommendation values" \
  "$([ -n "$COUNT_LINE" ] && echo yes || echo no)" "yes"

if [ -n "$COUNT_LINE" ]; then
  PORT_COUNT="$(count_for 'port' "$COUNT_LINE")"
  DROP_COUNT="$(count_for 'drop' "$COUNT_LINE")"
  OOS_COUNT="$(count_for 'out of scope' "$COUNT_LINE")"
  ND_COUNT="$(count_for 'needs decision' "$COUNT_LINE")"

  ACTUAL_PORT="$(grep -cx 'port' <<<"$RECS_IN_ORDER" || true)"
  ACTUAL_DROP="$(grep -cx 'drop' <<<"$RECS_IN_ORDER" || true)"
  ACTUAL_OOS="$(grep -cx 'out of scope' <<<"$RECS_IN_ORDER" || true)"
  ACTUAL_ND="$(grep -cx 'needs decision' <<<"$RECS_IN_ORDER" || true)"

  check "count line's 'port' count matches the actual number of port rows" \
    "$PORT_COUNT" "$ACTUAL_PORT"
  check "count line's 'drop' count matches the actual number of drop rows" \
    "$DROP_COUNT" "$ACTUAL_DROP"
  check "count line's 'out of scope' count matches the actual number of out-of-scope rows" \
    "$OOS_COUNT" "$ACTUAL_OOS"
  check "count line's 'needs decision' count matches the actual number of needs-decision rows" \
    "$ND_COUNT" "$ACTUAL_ND"
fi

# =====================================================================
# Edge case — the empty register (zero migration candidates) is legitimate:
# the section states "no migration candidates" explicitly, and the count
# line reads all zeros. This branch is additive, not a replacement for the
# checks above (which already accommodate zero rows via their own gating);
# it only fires the explicit-statement + all-zero requirement when the
# register actually is empty.
# =====================================================================

if [ "$ELEMENT_ROW_COUNT" -eq 0 ]; then
  check "empty register states 'no migration candidates' explicitly" \
    "$(grep -qi 'no migration candidates' <<<"$REGISTER" && echo yes || echo no)" "yes"
  if [ -n "$COUNT_LINE" ]; then
    check "empty register's count line reads all zeros" \
      "$(count_for 'port' "$COUNT_LINE")|$(count_for 'drop' "$COUNT_LINE")|$(count_for 'out of scope' "$COUNT_LINE")|$(count_for 'needs decision' "$COUNT_LINE")" \
      "0|0|0|0"
  fi
else
  echo "PASS  empty register states 'no migration candidates' explicitly -> register is non-empty (n/a)"
fi

# =====================================================================
# Errors
#   "A finding that cannot be classified into one of the four recommendation
#   values: use 'needs decision' ... Never invent a fifth value." Exercised
#   above under Outputs (closed-vocabulary check).
#
#   "Contradictory statuses between B01's and B02's sections for the same
#   element: escalate to the orchestrator." A process rule for the
#   implementer at authoring time, not a MIGRATION.md text shape this test
#   can independently verify after the fact — same treatment the siblings
#   give their own analogous non-file-shape error clauses.
# =====================================================================

# =====================================================================
# Invariants
# =====================================================================

# "The scaffold marker is gone: after this block the string 'NotImplemented:
# B03' appears nowhere in MIGRATION.md outside a contract docblock."
check "'NotImplemented: B03' marker is gone from the stripped body" \
  "$(grep -qF 'NotImplemented: B03' <<<"$BODY" && echo present || echo absent)" "absent"

# "The recommendation column contains only the four permitted values."
# Exercised above under Outputs (closed-vocabulary check, applied to every
# data row).

# "No pre-existing section, and no B01/B02 section, is modified." Run the
# sibling tests as subprocesses rather than re-deriving their (considerably
# deeper) assertions on those sections' content — the same run-the-
# precedent-as-a-subprocess call this unit's brief and both siblings make.
# Any B03 corruption of B01's or B02's sections is very likely to also break
# their own heading/content checks.
B01_TEST="$ROOT/scripts/migration-audit-surfaces.test.sh"
if [ -f "$B01_TEST" ]; then
  if bash "$B01_TEST" >/dev/null 2>&1; then
    check "scripts/migration-audit-surfaces.test.sh (B01's) stays green (B01's sections untouched)" "yes" "yes"
  else
    check "scripts/migration-audit-surfaces.test.sh (B01's) stays green (B01's sections untouched)" "no" "yes"
  fi
else
  check "scripts/migration-audit-surfaces.test.sh (B01's) exists to be run" "no" "yes"
fi

B02_TEST="$ROOT/scripts/migration-audit-reconcile.test.sh"
if [ -f "$B02_TEST" ]; then
  if bash "$B02_TEST" >/dev/null 2>&1; then
    check "scripts/migration-audit-reconcile.test.sh (B02's) stays green (B02's sections untouched)" "yes" "yes"
  else
    check "scripts/migration-audit-reconcile.test.sh (B02's) stays green (B02's sections untouched)" "no" "yes"
  fi
else
  check "scripts/migration-audit-reconcile.test.sh (B02's) exists to be run" "no" "yes"
fi

# "plugins/render-doc/scripts/migration.test.sh stays green."
RENDER_DOC_TEST="$ROOT/plugins/render-doc/scripts/migration.test.sh"
if [ -f "$RENDER_DOC_TEST" ]; then
  if bash "$RENDER_DOC_TEST" >/dev/null 2>&1; then
    check "plugins/render-doc/scripts/migration.test.sh stays green" "yes" "yes"
  else
    check "plugins/render-doc/scripts/migration.test.sh stays green" "no" "yes"
  fi
else
  check "plugins/render-doc/scripts/migration.test.sh exists to be run" "no" "yes"
fi

# "No pre-existing section ... is modified." B03's own contract adds no new
# heading (the register heading is already scaffolded); it also must not
# add, remove, or rename any OTHER heading. Total '## ' heading count is a
# durable invariant for B03 specifically (unlike a sibling's in-progress
# scaffold state): B03 only fills prose under its own already-existing
# heading, so the total count observed today (after B01 and B02, both
# accepted and merged, neither of which added or removed a heading either)
# is what B03 must also preserve.
check "total '## ' heading count in MIGRATION.md is unchanged by B03" \
  "$(grep -cE '^## ' <<<"$BODY")" "32"

# "Every row traces to a B01 or B02 section; no row introduces a claim that
# appears nowhere else in the file" and "every element that B01 or B02
# marked as anything other than 'ported' or 'dropped' appears as a row" are
# both conclusions about the correctness/completeness of the audit's
# findings, not the register's shape — exactly what this unit's brief
# forbids asserting ("whether the register's rows are correct, or that
# every row traces to a real B01/B02 finding"). Not independently testable
# here; the row-shape and vocabulary checks above are the durable, shape-
# level proxy.

# =====================================================================
# Edge cases (remaining)
# =====================================================================

# "An element that is a candidate on one surface and out of scope on
# another (same name, different tree): one row per surface, not one merged
# row." and "A candidate that is really a cluster ... one row for the
# cluster, with the rationale naming it as a cluster." Neither is
# independently assertable: whether any such element or cluster actually
# exists among the real findings is itself a conclusion of the audit, which
# this hermetic, contract-shape test must not assume either way (same
# treatment B01's test gives its own analogous non-shape edge cases).

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
