#!/usr/bin/env bash
# Structural/contract tests for B08 session-templates: journal.md and
# query-results.md. Source of truth: the HTML-comment contract docblocks at
# the top of each template file (plugins/debugging/templates/journal.md,
# plugins/debugging/templates/query-results.md).
#
# Scoped strictly to the "Outputs (required document structure — tests
# assert these)" clauses of each contract, plus the [bracket]-placeholder
# invariant: exact H1 form, metadata/header line labels and order, exact H2
# section names and order, the two verbatim table header rows in
# journal.md, and the exact paste-marker line in query-results.md.
# Descriptive/example prose embedded in each Outputs bullet (e.g. "status
# ladder (none | flaky | reliable)", the illustrative tool list, "Status
# values: open | refuted | confirmed") describes what the ORCHESTRATOR later
# writes into a FILLED journal/results file — it is not literal text
# required in the blank template — and is deliberately not asserted here.
#
# Hermetic: reads only the two template files at their fixed repo location
# (resolved from this script's own path), no mutation, no network.
#
# Run: bash plugins/debugging/scripts/b08-templates.test.sh (exits non-zero
# on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOURNAL="$SCRIPT_DIR/../templates/journal.md"
QUERY_RESULTS="$SCRIPT_DIR/../templates/query-results.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Line number of the first line matching fixed string $2 exactly, or "".
exact_line_no() { # file exact_text
  grep -nxF "$2" "$1" 2>/dev/null | head -n1 | cut -d: -f1
}

# Line number of the first line matching ERE $2 (anchored by caller), or "".
label_line_no() { # file ere_pattern
  grep -nE "$2" "$1" 2>/dev/null | head -n1 | cut -d: -f1
}

# Trimmed remainder of line $2 of $1 after stripping ERE prefix $3, or "" if
# $2 is empty (line not found).
value_after_label() { # file line_no label_ere_prefix
  local file="$1" line_no="$2" label="$3"
  [[ -n "$line_no" ]] || { echo ""; return; }
  sed -n "${line_no}p" "$file" | sed -E "s/^${label}//" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# "yes" if $1 (a line number, possibly empty) is strictly between $2 and $3
# (both possibly empty); "no" (never crashes) otherwise.
between() { # x a b
  local x="$1" a="$2" b="$3"
  [[ -n "$x" && -n "$a" && -n "$b" ]] || { echo no; return; }
  if (( x > a && x < b )); then echo yes; else echo no; fi
}

# Asserts $1's H2 headings (lines matching literal '## ') are exactly the
# ordered list of remaining args. Leaves the matched line numbers, in order,
# in the global array H2_LINENOS (index i corresponds to expected[i]; a
# missing heading leaves that slot unset).
H2_LINENOS=()
assert_h2_sequence() { # file label_prefix expected...
  local file="$1" label_prefix="$2"; shift 2
  local -a expected=("$@")
  local -a actual_text=() actual_lineno=()
  local raw
  while IFS= read -r raw; do
    [[ -n "$raw" ]] || continue
    actual_lineno+=("${raw%%:*}")
    actual_text+=("${raw#*:}")
  done < <(grep -n '^## ' "$file" 2>/dev/null)

  check "$label_prefix: H2 section count is ${#expected[@]}" "${#actual_text[@]}" "${#expected[@]}"

  local i
  for i in "${!expected[@]}"; do
    check "$label_prefix: H2 #$((i+1)) is exactly '${expected[$i]}'" \
      "${actual_text[$i]:-<missing>}" "${expected[$i]}"
  done
  H2_LINENOS=("${actual_lineno[@]}")
}

# ===========================================================================
# journal.md
# ===========================================================================

check "journal.md template file exists" "$([[ -f "$JOURNAL" ]] && echo yes || echo no)" "yes"

# --- H1 form ---------------------------------------------------------------
J_H1_TEXT='# Debug Journal: [issue title]'
j_h1_line=$(exact_line_no "$JOURNAL" "$J_H1_TEXT")
check "journal.md: H1 is exactly '$J_H1_TEXT'" "$([[ -n "$j_h1_line" ]] && echo yes || echo no)" "yes"

# --- metadata lines: labels, bracket placeholders, order --------------------
j_started_line=$(label_line_no "$JOURNAL" '^Started:')
j_status_line=$(label_line_no "$JOURNAL" '^Status:')
j_sessiondir_line=$(label_line_no "$JOURNAL" '^Session dir:')

check "journal.md: 'Started:' metadata line present" "$([[ -n "$j_started_line" ]] && echo yes || echo no)" "yes"
check "journal.md: 'Status:' metadata line present" "$([[ -n "$j_status_line" ]] && echo yes || echo no)" "yes"
check "journal.md: 'Session dir:' metadata line present" "$([[ -n "$j_sessiondir_line" ]] && echo yes || echo no)" "yes"

j_started_val=$(value_after_label "$JOURNAL" "$j_started_line" '^Started:')
j_status_val=$(value_after_label "$JOURNAL" "$j_status_line" '^Status:')
j_sessiondir_val=$(value_after_label "$JOURNAL" "$j_sessiondir_line" '^Session dir:')

check "journal.md: 'Started:' value uses a [bracket] placeholder" \
  "$([[ "$j_started_val" == *"["*"]"* ]] && echo yes || echo no)" "yes"
check "journal.md: 'Status:' value uses a [bracket] placeholder" \
  "$([[ "$j_status_val" == *"["*"]"* ]] && echo yes || echo no)" "yes"
check "journal.md: 'Session dir:' value uses a [bracket] placeholder" \
  "$([[ "$j_sessiondir_val" == *"["*"]"* ]] && echo yes || echo no)" "yes"

# --- H2 sections: exact set and order ---------------------------------------
assert_h2_sequence "$JOURNAL" "journal.md" \
  "## Symptom" "## Reproduction" "## What Changed" "## Hypotheses" \
  "## Probe Log" "## Queries" "## Root Cause"
J_H2_LINENOS=("${H2_LINENOS[@]}")

# --- order: H1, then metadata lines, then the first H2 section -------------
if [[ -n "$j_h1_line" && -n "$j_started_line" && -n "$j_status_line" && -n "$j_sessiondir_line" && -n "${J_H2_LINENOS[0]:-}" ]] \
   && (( j_h1_line < j_started_line && j_started_line < j_status_line && j_status_line < j_sessiondir_line && j_sessiondir_line < J_H2_LINENOS[0] )); then
  j_order_ok=yes
else
  j_order_ok=no
fi
check "journal.md: H1 is followed by Started/Status/Session dir metadata, then the first H2 section" \
  "$j_order_ok" "yes"

# --- Hypotheses table header: exact row, within the Hypotheses section -----
J_HYP_HEADER='| # | Hypothesis | Evidence for | Evidence against | Status |'
j_hyp_header_line=$(exact_line_no "$JOURNAL" "$J_HYP_HEADER")
check "journal.md: Hypotheses table header row is exactly '$J_HYP_HEADER'" \
  "$([[ -n "$j_hyp_header_line" ]] && echo yes || echo no)" "yes"
check "journal.md: Hypotheses table header appears within the '## Hypotheses' section" \
  "$(between "$j_hyp_header_line" "${J_H2_LINENOS[3]:-}" "${J_H2_LINENOS[4]:-}")" "yes"

# --- Probe Log table header: exact row, within the Probe Log section -------
J_PROBE_HEADER='| When | Probe | Expected | Observed |'
j_probe_header_line=$(exact_line_no "$JOURNAL" "$J_PROBE_HEADER")
check "journal.md: Probe Log table header row is exactly '$J_PROBE_HEADER'" \
  "$([[ -n "$j_probe_header_line" ]] && echo yes || echo no)" "yes"
check "journal.md: Probe Log table header appears within the '## Probe Log' section" \
  "$(between "$j_probe_header_line" "${J_H2_LINENOS[4]:-}" "${J_H2_LINENOS[5]:-}")" "yes"

# ===========================================================================
# query-results.md
# ===========================================================================

check "query-results.md template file exists" "$([[ -f "$QUERY_RESULTS" ]] && echo yes || echo no)" "yes"

# --- H1 form ---------------------------------------------------------------
Q_H1_TEXT='# Query: [name]'
q_h1_line=$(exact_line_no "$QUERY_RESULTS" "$Q_H1_TEXT")
check "query-results.md: H1 is exactly '$Q_H1_TEXT'" "$([[ -n "$q_h1_line" ]] && echo yes || echo no)" "yes"

# --- header lines: labels, non-empty values, order --------------------------
q_purpose_line=$(label_line_no "$QUERY_RESULTS" '^Purpose:')
q_tool_line=$(label_line_no "$QUERY_RESULTS" '^Tool:')
q_queryfile_line=$(label_line_no "$QUERY_RESULTS" '^Query file:')
q_howtorun_line=$(label_line_no "$QUERY_RESULTS" '^How to run:')

check "query-results.md: 'Purpose:' header line present" "$([[ -n "$q_purpose_line" ]] && echo yes || echo no)" "yes"
check "query-results.md: 'Tool:' header line present" "$([[ -n "$q_tool_line" ]] && echo yes || echo no)" "yes"
check "query-results.md: 'Query file:' header line present" "$([[ -n "$q_queryfile_line" ]] && echo yes || echo no)" "yes"
check "query-results.md: 'How to run:' header line present" "$([[ -n "$q_howtorun_line" ]] && echo yes || echo no)" "yes"

q_purpose_val=$(value_after_label "$QUERY_RESULTS" "$q_purpose_line" '^Purpose:')
q_tool_val=$(value_after_label "$QUERY_RESULTS" "$q_tool_line" '^Tool:')
q_queryfile_val=$(value_after_label "$QUERY_RESULTS" "$q_queryfile_line" '^Query file:')
q_howtorun_val=$(value_after_label "$QUERY_RESULTS" "$q_howtorun_line" '^How to run:')

check "query-results.md: 'Purpose:' has a non-empty value" "$([[ -n "$q_purpose_val" ]] && echo yes || echo no)" "yes"
check "query-results.md: 'Tool:' has a non-empty value" "$([[ -n "$q_tool_val" ]] && echo yes || echo no)" "yes"
check "query-results.md: 'Query file:' has a non-empty value" "$([[ -n "$q_queryfile_val" ]] && echo yes || echo no)" "yes"
check "query-results.md: 'How to run:' has a non-empty value" "$([[ -n "$q_howtorun_val" ]] && echo yes || echo no)" "yes"

# --- H2 sections: exact set and order ---------------------------------------
assert_h2_sequence "$QUERY_RESULTS" "query-results.md" "## Results" "## Interpretation"
QR_H2_LINENOS=("${H2_LINENOS[@]}")

# --- order: H1, then the four header lines in the contracted order, then
#     the first H2 section ---------------------------------------------------
if [[ -n "$q_h1_line" && -n "$q_purpose_line" && -n "$q_tool_line" && -n "$q_queryfile_line" && -n "$q_howtorun_line" && -n "${QR_H2_LINENOS[0]:-}" ]] \
   && (( q_h1_line < q_purpose_line && q_purpose_line < q_tool_line && q_tool_line < q_queryfile_line && q_queryfile_line < q_howtorun_line && q_howtorun_line < QR_H2_LINENOS[0] )); then
  q_order_ok=yes
else
  q_order_ok=no
fi
check "query-results.md: H1 is followed by Purpose/Tool/Query file/How to run headers (in that order), then the first H2 section" \
  "$q_order_ok" "yes"

# --- paste marker: exact text, first non-blank line of ## Results -----------
first_nonblank_after() { # file line_no -> first non-blank line's exact text strictly after line_no, or ""
  local file="$1" line_no="$2"
  [[ -n "$line_no" ]] || { echo ""; return; }
  awk -v start="$line_no" 'NR>start { if ($0 ~ /[^[:space:]]/) { print; exit } }' "$file"
}
Q_MARKER='<!-- paste tool output below this line -->'
q_marker_actual=$(first_nonblank_after "$QUERY_RESULTS" "${QR_H2_LINENOS[0]:-}")
check "query-results.md: '## Results' section starts with the exact paste-marker line" \
  "$q_marker_actual" "$Q_MARKER"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
