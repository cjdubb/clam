#!/usr/bin/env bash
# Structural/anchor test for references/database.md against Contract: B06
# ref-database (see the HTML-comment docblock in that file). This reference
# is a documentation block (technique reference on inspecting database state
# as evidence), not executable code, so the tests here are:
#   - H1 title + a "When to use" preamble line before the first H2
#   - the exact H2 section set the contract names, no more, no fewer
#   - per-section anchor checks: each required section's rendered body (HTML
#     comments stripped, so the contract docblock's own prose can never
#     satisfy a check) must contain the stable terms/literals a faithful
#     implementation of that section could not avoid using
#   - the READ-ONLY rule and LIMIT guidance in "Safety first"
#   - the paste-back protocol's reference to debug-session.sh query ... sql
#     and query-results.md
#   - the invariant that no fenced example contains a state-mutating SQL
#     statement (INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE)
#   - the documented edge cases
# These MUST fail against the current NotImplemented(B06) stub and MUST pass
# once a real reference doc satisfies the contract.
# Run: bash plugins/debugging/scripts/b06-database-ref.test.sh  (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="$SCRIPT_DIR/../skills/root-cause/references/database.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "database.md exists at the contract's Code path" \
  "$([ -f "$DOC" ] && echo yes || echo no)" "yes"

if [[ ! -f "$DOC" ]]; then
  echo "FAILURES (doc missing, cannot continue)"
  exit 1
fi

# --- fixtures ---------------------------------------------------------

# Strip the contract's own HTML-comment docblock so none of the checks below
# can be satisfied by the contract's own prose — only real document content.
BODY=$(sed '/<!--/,/-->/d' "$DOC")

has() { # content pattern (case-insensitive extended regex)
  if grep -qiE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

has_f() { # content literal (case-sensitive fixed string)
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

flat() { printf '%s' "$1" | tr '\n' ' ' | tr -s '[:space:]' ' '; }

preamble() {
  awk '/^## /{exit} {print}' <<<"$BODY"
}

first_nonblank() {
  awk 'NF{print; exit}' <<<"$1"
}

section() { # heading
  awk -v h="$1" '
    $0 ~ "^"h"[[:space:]]*$" {f=1; next}
    /^## / {f=0}
    f {print}
  ' <<<"$BODY"
}

# All fenced code-block bodies (content strictly between ``` markers),
# concatenated. Used for the never-mutates invariant below.
fenced_bodies() {
  awk '
    /^```/ { infence = !infence; next }
    infence { print }
  ' <<<"$BODY"
}

PREAMBLE=$(preamble)
FPREAMBLE=$(flat "$PREAMBLE")

# ===========================================================================
# Outputs: H1 title, then a "When to use" line.
# ===========================================================================

FIRST_LINE=$(first_nonblank "$PREAMBLE")
check "document opens with an H1 title" \
  "$(printf '%s' "$FIRST_LINE" | grep -qE '^# [^#]' && echo yes || echo no)" "yes"
check "preamble carries a 'When to use' line before the first H2" \
  "$(has "$FPREAMBLE" 'when to use')" "yes"

# ===========================================================================
# Outputs: H2 sections, exactly this set.
# ===========================================================================

EXPECTED_H2=$(printf '%s\n' \
  "## Safety first" \
  "## Access first" \
  "## Query patterns" \
  "## Paste-back protocol" \
  "## Journal" | sort)

for h in "## Safety first" "## Access first" "## Query patterns" \
         "## Paste-back protocol" "## Journal"; do
  check "required section exists: $h" \
    "$(has_f "$BODY" "$h")" "yes"
done

ACTUAL_H2=$(grep -E '^## ' <<<"$BODY" | sed -E 's/[[:space:]]+$//' | sort)
check "H2 section set matches the contract exactly (no extras, no omissions)" \
  "$ACTUAL_H2" "$EXPECTED_H2"

SAFETY=$(section "## Safety first")
ACCESS=$(section "## Access first")
PATTERNS=$(section "## Query patterns")
PASTEBACK=$(section "## Paste-back protocol")
JOURNAL=$(section "## Journal")

FSAFETY=$(flat "$SAFETY")
FACCESS=$(flat "$ACCESS")
FPATTERNS=$(flat "$PATTERNS")
FPASTEBACK=$(flat "$PASTEBACK")
FJOURNAL=$(flat "$JOURNAL")

# --- Safety first: READ-ONLY rule and LIMIT guidance --------------------

check "'Safety first' states the READ-ONLY rule" \
  "$(has "$FSAFETY" 'read-only')" "yes"
check "'Safety first' allows SELECT/EXPLAIN only" \
  "$(has "$FSAFETY" '\bSELECT\b')" "yes"
check "'Safety first' names EXPLAIN as permitted" \
  "$(has "$FSAFETY" '\bEXPLAIN\b')" "yes"
check "'Safety first' prefers a replica" \
  "$(has "$FSAFETY" 'replica')" "yes"
check "'Safety first' requires bounding every result with LIMIT" \
  "$(has "$FSAFETY" '\bLIMIT\b')" "yes"
check "'Safety first' keeps PII out of the journal unless the engineer okays it" \
  "$(has "$FSAFETY" 'PII')" "yes"

# --- Access first ---------------------------------------------------------

check "'Access first' determines whether the session can query directly" \
  "$(has "$FACCESS" 'session')" "yes"
check "'Access first' routes to the paste-back protocol when access is missing" \
  "$(has "$FACCESS" 'paste-back')" "yes"
check "'Access first' asks the engineer when access is missing" \
  "$(has "$FACCESS" 'ask the engineer')" "yes"
check "'Access first' states the expected result shape accompanies the query" \
  "$(has "$FACCESS" 'expected.*(result )?shape')" "yes"

# --- Query patterns ---------------------------------------------------------

check "'Query patterns' covers the affected entity's current row(s)" \
  "$(has "$FPATTERNS" 'current row')" "yes"
check "'Query patterns' covers recent mutations via created_at windows" \
  "$(has_f "$FPATTERNS" 'created_at')" "yes"
check "'Query patterns' covers recent mutations via updated_at windows" \
  "$(has_f "$FPATTERNS" 'updated_at')" "yes"
check "'Query patterns' covers aggregate sanity counts" \
  "$(has "$FPATTERNS" 'aggregate')" "yes"
check "'Query patterns' covers per-status distribution" \
  "$(has "$FPATTERNS" 'distribution')" "yes"
check "'Query patterns' covers orphan checks between related tables" \
  "$(has "$FPATTERNS" 'orphan')" "yes"
check "'Query patterns' covers referential checks between related tables" \
  "$(has "$FPATTERNS" 'referential')" "yes"
check "'Query patterns' covers schema/migration state (applied-migrations table)" \
  "$(has "$FPATTERNS" 'migration')" "yes"

# Edge case: unknown schema -> ask/derive table shapes first.
check "'Query patterns' covers the unknown-schema edge case (information_schema or ask)" \
  "$(has "$FPATTERNS" 'information_schema')" "yes"

# Edge case: very large tables -> indexed-column filters + LIMIT; warn about
# full scans on production.
check "'Query patterns' warns large tables lead with indexed-column filters" \
  "$(has "$FPATTERNS" 'index')" "yes"
check "'Query patterns' warns about full scans on production" \
  "$(has "$FPATTERNS" 'full (table )?scan')" "yes"

# --- Paste-back protocol ---------------------------------------------------

check "'Paste-back protocol' references debug-session.sh query ... with sql" \
  "$(has "$FPASTEBACK" 'debug-session\.sh query.*sql')" "yes"
check "'Paste-back protocol' writes the exact SQL into query.sql" \
  "$(has_f "$FPASTEBACK" 'query.sql')" "yes"
check "'Paste-back protocol' fills the query-results.md header" \
  "$(has_f "$FPASTEBACK" 'query-results.md')" "yes"
check "'Paste-back protocol' header covers purpose" \
  "$(has "$FPASTEBACK" 'purpose')" "yes"
check "'Paste-back protocol' header covers tool" \
  "$(has "$FPASTEBACK" '\btool\b')" "yes"
check "'Paste-back protocol' header covers how to run" \
  "$(has "$FPASTEBACK" 'how to run')" "yes"
check "'Paste-back protocol' asks the engineer to run it and paste output into Results" \
  "$(has "$FPASTEBACK" 'paste')" "yes"
check "'Paste-back protocol' interprets only after results arrive" \
  "$(has "$FPASTEBACK" 'interpret')" "yes"

# --- Journal ----------------------------------------------------------------

check "'Journal' indexes queries in the journal's Queries section" \
  "$(has "$FJOURNAL" 'queries')" "yes"
check "'Journal' records interpretation next to the pasted results" \
  "$(has "$FJOURNAL" 'interpretation')" "yes"
check "'Journal' feeds interpretation into the hypothesis table" \
  "$(has "$FJOURNAL" 'hypothesis')" "yes"

# ===========================================================================
# Invariants
# ===========================================================================

FENCED=$(fenced_bodies)
check "no fenced example contains a state-mutating SQL statement (INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE)" \
  "$(printf '%s' "$FENCED" | grep -qiE '\b(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE)\b' && echo present || echo absent)" "absent"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
