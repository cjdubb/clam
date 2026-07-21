#!/usr/bin/env bash
# Structural/anchor test for references/logs.md against Contract: B05
# ref-logs (see the HTML-comment docblock in that file). This reference is a
# documentation block (technique reference on gathering log evidence), not
# executable code, so the tests here are:
#   - H1 title + a "When to use" preamble line before the first H2
#   - the exact H2 section set the contract names, no more, no fewer
#   - per-section anchor checks: each required section's rendered body (HTML
#     comments stripped, so the contract docblock's own prose can never
#     satisfy a check) must contain the stable terms/literals a faithful
#     implementation of that section could not avoid using
#   - the six required tool names in "Tool guidance"
#   - the paste-back protocol's reference to debug-session.sh query and
#     query-results.md
#   - the documented invariants and edge cases
# These MUST fail against the current NotImplemented(B05) stub and MUST pass
# once a real reference doc satisfies the contract.
# Run: bash plugins/debugging/scripts/b05-logs-ref.test.sh  (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="$SCRIPT_DIR/../skills/root-cause/references/logs.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "logs.md exists at the contract's Code path" \
  "$([ -f "$DOC" ] && echo yes || echo no)" "yes"

if [[ ! -f "$DOC" ]]; then
  echo "FAILURES (doc missing, cannot continue)"
  exit 1
fi

# --- fixtures ---------------------------------------------------------

# Strip the contract's own HTML-comment docblock so none of the checks below
# can be satisfied by the contract's own prose — only real document content.
BODY=$(sed '/<!--/,/-->/d' "$DOC")

# Case-insensitive extended-regex presence check over a blob of text.
has() { # content pattern
  if grep -qiE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Fixed-string (literal) presence check, case-sensitive.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Collapse newlines/whitespace to single spaces so multi-line phrase checks
# match regardless of prose line-wrapping.
flat() { printf '%s' "$1" | tr '\n' ' ' | tr -s '[:space:]' ' '; }

# Everything from the start of BODY up to (not including) the first H2.
preamble() {
  awk '/^## /{exit} {print}' <<<"$BODY"
}

# First non-blank line of a string.
first_nonblank() {
  awk 'NF{print; exit}' <<<"$1"
}

# Exact "## Heading" section body (up to the next "## " heading or EOF).
section() { # heading
  awk -v h="$1" '
    $0 ~ "^"h"[[:space:]]*$" {f=1; next}
    /^## / {f=0}
    f {print}
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
  "## Access first" \
  "## What to look for" \
  "## Tool guidance" \
  "## Paste-back protocol" \
  "## Journal" | sort)

for h in "## Access first" "## What to look for" "## Tool guidance" \
         "## Paste-back protocol" "## Journal"; do
  check "required section exists: $h" \
    "$(has_f "$BODY" "$h")" "yes"
done

ACTUAL_H2=$(grep -E '^## ' <<<"$BODY" | sed -E 's/[[:space:]]+$//' | sort)
check "H2 section set matches the contract exactly (no extras, no omissions)" \
  "$ACTUAL_H2" "$EXPECTED_H2"

ACCESS=$(section "## Access first")
LOOKFOR=$(section "## What to look for")
TOOLS=$(section "## Tool guidance")
PASTEBACK=$(section "## Paste-back protocol")
JOURNAL=$(section "## Journal")

FACCESS=$(flat "$ACCESS")
FLOOKFOR=$(flat "$LOOKFOR")
FTOOLS=$(flat "$TOOLS")
FPASTEBACK=$(flat "$PASTEBACK")
FJOURNAL=$(flat "$JOURNAL")

# --- Access first -----------------------------------------------------

check "'Access first' names in-session access channels (CLI, MCP, or local files)" \
  "$(has "$FACCESS" 'CLI|MCP|local files')" "yes"
check "'Access first' says to query directly when access exists" \
  "$(has "$FACCESS" 'directly')" "yes"
check "'Access first' says not to guess when access is missing" \
  "$(has "$FACCESS" 'do not guess|never guess|do.?nt guess')" "yes"
check "'Access first' says to ask the engineer which tool they use" \
  "$(has "$FACCESS" 'ask the engineer')" "yes"
check "'Access first' routes to the paste-back protocol" \
  "$(has "$FACCESS" 'paste-back')" "yes"

# --- What to look for ---------------------------------------------------

check "'What to look for' covers error onset time" \
  "$(has "$FLOOKFOR" 'onset')" "yes"
check "'What to look for' covers first occurrence vs steady state" \
  "$(has "$FLOOKFOR" 'steady state')" "yes"
check "'What to look for' covers frequency changes at deploy boundaries" \
  "$(has "$FLOOKFOR" 'deploy')" "yes"
check "'What to look for' covers correlation/request ids to pivot on" \
  "$(has "$FLOOKFOR" 'correlation|request id')" "yes"
check "'What to look for' covers adjacent warnings before the first error" \
  "$(has "$FLOOKFOR" 'warning')" "yes"

# --- Tool guidance: all six required tool names -------------------------

check "'Tool guidance' names Datadog" "$(has "$FTOOLS" 'Datadog')" "yes"
check "'Tool guidance' names CloudWatch Logs Insights" \
  "$(has "$FTOOLS" 'CloudWatch')" "yes"
check "'Tool guidance' names Splunk" "$(has "$FTOOLS" 'Splunk')" "yes"
check "'Tool guidance' names Loki" "$(has "$FTOOLS" 'Loki')" "yes"
check "'Tool guidance' names Kibana/Elasticsearch" \
  "$(has "$FTOOLS" 'Kibana|Elasticsearch')" "yes"
check "'Tool guidance' names plain files / kubectl logs with grep" \
  "$(has "$FTOOLS" 'kubectl')" "yes"

# Invariant: examples are patterns, not environment-specific facts; confirm
# index/source names with the engineer.
check "'Tool guidance' tells the reader to confirm index/source names with the engineer" \
  "$(has "$FTOOLS" 'confirm')" "yes"

# Edge case: engineer's tool not in the table.
check "'Tool guidance' covers the tool-not-in-table edge case (ask for a sample query, adapt)" \
  "$(has "$FTOOLS" 'sample query')" "yes"

# --- Paste-back protocol -------------------------------------------------

FLAT_PASTEBACK_ONELINE=$(flat "$PASTEBACK")
check "'Paste-back protocol' references debug-session.sh query" \
  "$(has_f "$FLAT_PASTEBACK_ONELINE" 'debug-session.sh query')" "yes"
check "'Paste-back protocol' fills the query-results.md header" \
  "$(has_f "$FPASTEBACK" 'query-results.md')" "yes"
check "'Paste-back protocol' header covers purpose" \
  "$(has "$FPASTEBACK" 'purpose')" "yes"
check "'Paste-back protocol' header covers tool" \
  "$(has "$FPASTEBACK" '\btool\b')" "yes"
check "'Paste-back protocol' header covers how to run" \
  "$(has "$FPASTEBACK" 'how to run')" "yes"
check "'Paste-back protocol' hands the engineer the file path and asks for paste-in" \
  "$(has "$FPASTEBACK" 'paste')" "yes"
check "'Paste-back protocol' says results land in the Results section" \
  "$(has "$FPASTEBACK" 'results')" "yes"
check "'Paste-back protocol' interprets only after results arrive" \
  "$(has "$FPASTEBACK" 'interpret')" "yes"

# --- Journal --------------------------------------------------------------

check "'Journal' indexes every query in the journal's Queries section" \
  "$(has "$FJOURNAL" 'queries')" "yes"
check "'Journal' feeds findings into hypothesis evidence" \
  "$(has "$FJOURNAL" 'hypothesis')" "yes"

# ===========================================================================
# Invariants
# ===========================================================================

check "never fabricates/extrapolates log content (invariant stated)" \
  "$(has "$(flat "$BODY")" 'fabricat|extrapolat')" "yes"

# ===========================================================================
# Edge cases
# ===========================================================================

check "logs rotated/expired for the incident window treated as an evidence gap" \
  "$(has "$(flat "$BODY")" 'rotat|expir')" "yes"
check "rotated/expired logs: note the evidence gap rather than substituting guesses" \
  "$(has "$(flat "$BODY")" 'evidence gap')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
