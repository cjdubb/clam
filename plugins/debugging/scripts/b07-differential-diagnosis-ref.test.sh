#!/usr/bin/env bash
# Structural/anchor test for references/differential-diagnosis.md against
# Contract: B07 ref-differential-diagnosis (see the HTML-comment docblock in
# that file). This reference is a documentation block (the reasoning engine
# the other techniques feed), not executable code, so the tests here are:
#   - H1 title + a "When to use" preamble line before the first H2
#   - the exact H2 section set the contract names, no more, no fewer
#   - per-section anchor checks: each required section's rendered body (HTML
#     comments stripped, so the contract docblock's own prose can never
#     satisfy a check) must contain the stable terms/literals a faithful
#     implementation of that section could not avoid using
#   - the status vocabulary (open | refuted | confirmed)
#   - the explains-ALL-evidence convergence rule
#   - the optional (never mandatory) delegation marking
#   - the documented invariants and edge cases
# These MUST fail against the current NotImplemented(B07) stub and MUST pass
# once a real reference doc satisfies the contract.
# Run: bash plugins/debugging/scripts/b07-differential-diagnosis-ref.test.sh
#      (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="$SCRIPT_DIR/../skills/root-cause/references/differential-diagnosis.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "differential-diagnosis.md exists at the contract's Code path" \
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

PREAMBLE=$(preamble)
FPREAMBLE=$(flat "$PREAMBLE")
FBODY=$(flat "$BODY")

# ===========================================================================
# Outputs: H1 title, then a "When to use" line (more than one plausible cause).
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
  "## Generate hypotheses" \
  "## Build the table" \
  "## Weigh evidence" \
  "## Discriminating probes" \
  "## Update loop" \
  "## Convergence rule" | sort)

for h in "## Generate hypotheses" "## Build the table" "## Weigh evidence" \
         "## Discriminating probes" "## Update loop" "## Convergence rule"; do
  check "required section exists: $h" \
    "$(has_f "$BODY" "$h")" "yes"
done

ACTUAL_H2=$(grep -E '^## ' <<<"$BODY" | sed -E 's/[[:space:]]+$//' | sort)
check "H2 section set matches the contract exactly (no extras, no omissions)" \
  "$ACTUAL_H2" "$EXPECTED_H2"

GENERATE=$(section "## Generate hypotheses")
TABLE=$(section "## Build the table")
WEIGH=$(section "## Weigh evidence")
PROBES=$(section "## Discriminating probes")
LOOP=$(section "## Update loop")
CONVERGENCE=$(section "## Convergence rule")

FGENERATE=$(flat "$GENERATE")
FTABLE=$(flat "$TABLE")
FWEIGH=$(flat "$WEIGH")
FPROBES=$(flat "$PROBES")
FLOOP=$(flat "$LOOP")
FCONVERGENCE=$(flat "$CONVERGENCE")

# --- Generate hypotheses ----------------------------------------------

check "'Generate hypotheses' says to enumerate broadly before judging" \
  "$(has "$FGENERATE" 'enumerate')" "yes"
check "'Generate hypotheses' seeds from the what-changed candidate list" \
  "$(has "$FGENERATE" 'what-changed|what changed')" "yes"
check "'Generate hypotheses' standing category: code change" \
  "$(has "$FGENERATE" 'code change')" "yes"
check "'Generate hypotheses' standing category: config/flag" \
  "$(has "$FGENERATE" 'config')" "yes"
check "'Generate hypotheses' standing category: data" \
  "$(has "$FGENERATE" '\bdata\b')" "yes"
check "'Generate hypotheses' standing category: dependency" \
  "$(has "$FGENERATE" 'dependency')" "yes"
check "'Generate hypotheses' standing category: environment/infra" \
  "$(has "$FGENERATE" 'environment|infra')" "yes"
check "'Generate hypotheses' standing category: load/timing/concurrency" \
  "$(has "$FGENERATE" 'load|timing|concurrency')" "yes"
check "'Generate hypotheses' standing category: external service" \
  "$(has "$FGENERATE" 'external service')" "yes"

# --- Build the table: journal's Hypotheses table + status vocabulary ---

check "'Build the table' targets the journal's Hypotheses table" \
  "$(has "$FTABLE" 'hypotheses')" "yes"
check "'Build the table' is one row per hypothesis" \
  "$(has "$FTABLE" 'one row per hypothesis|row per hypothesis')" "yes"
check "'Build the table' columns include evidence for" \
  "$(has "$FTABLE" 'evidence for')" "yes"
check "'Build the table' columns include evidence against" \
  "$(has "$FTABLE" 'evidence against')" "yes"
check "'Build the table' status vocabulary includes open" \
  "$(has "$FTABLE" '\bopen\b')" "yes"
check "'Build the table' status vocabulary includes refuted" \
  "$(has "$FTABLE" '\brefuted\b')" "yes"
check "'Build the table' status vocabulary includes confirmed" \
  "$(has "$FTABLE" '\bconfirmed\b')" "yes"

# --- Weigh evidence -------------------------------------------------------

check "'Weigh evidence' scores each hypothesis against ALL evidence gathered" \
  "$(has "$FWEIGH" 'all evidence')" "yes"
check "'Weigh evidence' states evidence fitting every hypothesis discriminates nothing" \
  "$(has "$FWEIGH" 'discriminat')" "yes"

# --- Discriminating probes: cheapest split + OPTIONAL delegation -------

check "'Discriminating probes' designs the cheapest probe that splits survivors" \
  "$(has "$FPROBES" 'cheapest')" "yes"
check "'Discriminating probes' splits the surviving hypotheses best" \
  "$(has "$FPROBES" 'split')" "yes"
check "'Discriminating probes' marks delegation as OPTIONAL" \
  "$(has "$FPROBES" 'optional')" "yes"
check "'Discriminating probes' allows independent hypotheses via parallel subagents" \
  "$(has "$FPROBES" 'parallel subagent')" "yes"
check "'Discriminating probes' never makes delegation mandatory" \
  "$(has "$FPROBES" 'never.*mandator|not mandatory')" "yes"

# --- Update loop ------------------------------------------------------------

check "'Update loop' updates rows after each probe" \
  "$(has "$FLOOP" 'update')" "yes"
check "'Update loop' refutes what the evidence kills" \
  "$(has "$FLOOP" 'refut')" "yes"
check "'Update loop' repeats until one survivor" \
  "$(has "$FLOOP" 'survivor')" "yes"

# --- Convergence rule: explains-ALL-evidence -------------------------------

check "'Convergence rule' accepts the survivor as root cause" \
  "$(has "$FCONVERGENCE" 'root cause')" "yes"
check "'Convergence rule' requires explaining ALL recorded evidence" \
  "$(has "$FCONVERGENCE" 'explains all|all.*evidence')" "yes"
check "'Convergence rule' reopens generation on unexplained evidence" \
  "$(has "$FCONVERGENCE" 'unexplained')" "yes"
check "'Convergence rule' reopening returns to hypothesis generation" \
  "$(has "$FCONVERGENCE" 'reopen')" "yes"

# ===========================================================================
# Invariants
# ===========================================================================

check "a hypothesis is never deleted, only refuted with the evidence that refuted it" \
  "$(has "$FBODY" 'never (be )?delet|not delet')" "yes"
check "the doc never lets a 'likely' hypothesis skip the convergence rule" \
  "$(has "$FBODY" 'likely.*(skip|bypass)|(skip|bypass).*likely')" "yes"

# ===========================================================================
# Edge cases
# ===========================================================================

check "two hypotheses current evidence can't split: design a new discriminating probe" \
  "$(has "$FBODY" 'new discriminating probe|design a new probe')" "yes"
check "un-splittable survivors are not resolved by plausibility" \
  "$(has "$FBODY" 'plausibility')" "yes"
check "compound causes (two interacting changes) get their own hypothesis row" \
  "$(has "$FBODY" 'compound')" "yes"
check "compound causes are framed as an interacting combination" \
  "$(has "$FBODY" 'interact')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
