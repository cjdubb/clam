#!/bin/bash
# Structural/anchor test for the two lego agent definitions against
# Contract: B03 agent-defs-brief-file (see
# .local/contracts/B03-agent-defs-brief-file.md). Both agent definitions are
# prose (documentation) blocks, not executable code, so the tests here are:
#   - required-literal-token checks: each token the contract lists under
#     "Required literal tokens" must appear, verbatim, in BOTH target files
#     (fixed-string grep per token per file)
#   - frontmatter invariants: `name:` matches each file's agent name and
#     `model: sonnet` is present in both, unchanged
#   - report-format invariants: the `## Report format` heading and the
#     literal `STATUS: COMPLETE | ESCALATION` block are present in both
# Per the brief, prose semantics beyond tokens/headings are NOT tested here;
# the orchestrator verifies meaning at acceptance.
# These MUST fail (on the required-literal-token checks) against the current
# agent definitions, which do not yet carry the brief-file protocol, and MUST
# pass once both files are edited to satisfy the contract.
# Run: bash plugins/lego/scripts/agent-defs.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TW="$SCRIPT_DIR/../agents/lego-test-writer.md"
IMPL="$SCRIPT_DIR/../agents/lego-implementer.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Fixed-string (literal) presence check, case-sensitive. `--` guards literals
# that start with a dash from being parsed as grep options.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Wrap-tolerant variant of has_f (same technique as dispatch-skill.test.sh).
# grep is line-oriented and these agent definitions hard-wrap prose at ~80
# columns, so a multi-word literal can have its own words land on opposite
# sides of a source line break. Collapse every whitespace run — newlines
# included — to a single space before matching, so a token that reads
# correctly to a human matches regardless of where the wrap falls.
has_fn() { # content literal
  local flat; flat=$(tr '\n' ' ' <<<"$1" | tr -s ' ')
  if grep -qF -- "$2" <<<"$flat"; then echo yes; else echo no; fi
}

for f in "$TW" "$IMPL"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL  target agent definition not found: $f"
    exit 1
  fi
done

TW_RAW=$(cat "$TW")
IMPL_RAW=$(cat "$IMPL")

# --- Required literal tokens (contract: "Required literal tokens") --------
# Each token MUST appear verbatim in BOTH target files.
REQUIRED_TOKENS=(
  ".local/briefs/"
  "read the brief file first"
  "orchestrator-owned"
  "read-only"
)

for tok in "${REQUIRED_TOKENS[@]}"; do
  check "lego-test-writer.md contains required literal token: $tok" \
    "$(has_f "$TW_RAW" "$tok")" "yes"
  check "lego-implementer.md contains required literal token: $tok" \
    "$(has_f "$IMPL_RAW" "$tok")" "yes"
done

# --- Frontmatter invariants (contract: Invariants, "Frontmatter ... unchanged") ---
# Lines strictly between the first two '---' delimiters of each file.
frontmatter() { awk '/^---$/{n++; next} n==1' "$1"; }

TW_FM=$(frontmatter "$TW")
IMPL_FM=$(frontmatter "$IMPL")

TW_NAME=$(printf '%s\n' "$TW_FM" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
IMPL_NAME=$(printf '%s\n' "$IMPL_FM" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
TW_MODEL=$(printf '%s\n' "$TW_FM" | grep '^model:' | sed -E 's/^model:[[:space:]]*//')
IMPL_MODEL=$(printf '%s\n' "$IMPL_FM" | grep '^model:' | sed -E 's/^model:[[:space:]]*//')

check "lego-test-writer.md frontmatter name is 'lego-test-writer'" "$TW_NAME" "lego-test-writer"
check "lego-implementer.md frontmatter name is 'lego-implementer'" "$IMPL_NAME" "lego-implementer"
check "lego-test-writer.md frontmatter model is 'sonnet'" "$TW_MODEL" "sonnet"
check "lego-implementer.md frontmatter model is 'sonnet'" "$IMPL_MODEL" "sonnet"

# --- Report-format invariants (contract: Invariants, "Report format ... unchanged") ---
check "lego-test-writer.md has '## Report format' heading" \
  "$(has_f "$TW_RAW" "## Report format")" "yes"
check "lego-implementer.md has '## Report format' heading" \
  "$(has_f "$IMPL_RAW" "## Report format")" "yes"
check "lego-test-writer.md has literal 'STATUS: COMPLETE | ESCALATION'" \
  "$(has_f "$TW_RAW" "STATUS: COMPLETE | ESCALATION")" "yes"
check "lego-implementer.md has literal 'STATUS: COMPLETE | ESCALATION'" \
  "$(has_f "$IMPL_RAW" "STATUS: COMPLETE | ESCALATION")" "yes"

# --- Report channel (#184) ------------------------------------------------
# Both definitions previously specified the report's FORMAT and never its
# CHANNEL, which is what let two workers independently guess SendMessage and
# lose their reports silently. These tokens pin the three clauses that close
# that gap, in BOTH files, wrap-tolerantly:
#   1. the report is a FILE, at the path the brief names under .local/reports/
#   2. the message is a one-line notification, never the report body
#   3. that file is the single carved-out write surface under .local/
CHANNEL_TOKENS=(
  ".local/reports/NN-<wave>-<blocks>.md"
  "one-line notification naming that path"
  "never the report body"
  "the one path under \`.local/\` you may write"
)

for tok in "${CHANNEL_TOKENS[@]}"; do
  check "lego-test-writer.md contains report-channel token: $tok" \
    "$(has_fn "$TW_RAW" "$tok")" "yes"
  check "lego-implementer.md contains report-channel token: $tok" \
    "$(has_fn "$IMPL_RAW" "$tok")" "yes"
done

# The pre-#184 prose declared the whole of `.local/` — `reports/` explicitly
# included — read-only for workers. Keeping that sentence alongside the new
# carve-out would leave each definition contradicting itself, so the old
# enumeration must be GONE, not merely added to.
check "lego-test-writer.md no longer lists reports/ among the read-only tree" \
  "$(has_fn "$TW_RAW" "\`status.md\`, \`briefs/\`, and \`reports/\` — is orchestrator-owned and read-only")" "no"
check "lego-implementer.md no longer lists reports/ among the read-only tree" \
  "$(has_fn "$IMPL_RAW" "\`status.md\`, \`briefs/\`, and \`reports/\` — is orchestrator-owned and read-only")" "no"

# --- B04 worker-report-escalation-and-legacy-brief (contract: B04) --------
# The contract's own HTML comment (search each file for "Contract: B04") is
# embedded directly inside "## Report format", quoting nearly the exact
# clauses the real prose needs — matching $TW_RAW/$IMPL_RAW directly would
# pass today against the comment alone, before any real edit exists. Strip
# HTML comments first (same technique as dispatch-skill.test.sh), then scope
# to "## Report format" — the last section in both files, so no closing
# anchor is needed — so only real prose in the section the contract governs
# can satisfy these checks.
strip_comments() { perl -0777 -pe 's/<!--.*?-->//gs' "$1"; }
report_section() { awk '/^## Report format$/{flag=1} flag' <<<"$1"; }

TW_STRIPPED=$(strip_comments "$TW")
IMPL_STRIPPED=$(strip_comments "$IMPL")
TW_REPORT=$(report_section "$TW_STRIPPED")
IMPL_REPORT=$(report_section "$IMPL_STRIPPED")

# OR-match helper (same wrap-tolerant flattening as has_fn): passes if ANY of
# several reasonable phrasings is present. Used where the contract fixes the
# concept but leaves each file's exact wording to its own voice — the rule
# must be stated, not stated in one exact phrasing.
any_fn() { # content phrase1 [phrase2 ...]
  local content="$1"; shift
  local flat; flat=$(tr '\n' ' ' <<<"$content" | tr -s ' ')
  for p in "$@"; do
    if grep -qF -- "$p" <<<"$flat"; then echo yes; return; fi
  done
  echo no
}

# Clause 1: an ESCALATION still writes the report file, exactly as a
# COMPLETE does — escalating is not an exemption from the file protocol.
check "lego-test-writer.md: an ESCALATION still writes the report file (not exempt)" \
  "$(any_fn "$TW_REPORT" "still writes" "not an exemption" "exemption from the file protocol" "same as a COMPLETE" "as a COMPLETE does")" "yes"
check "lego-implementer.md: an ESCALATION still writes the report file (not exempt)" \
  "$(any_fn "$IMPL_REPORT" "still writes" "not an exemption" "exemption from the file protocol" "same as a COMPLETE" "as a COMPLETE does")" "yes"

# Clause 2: a brief that names no report path (an old-style brief) is still
# answered with a file, under .local/reports/ at the brief's own NN.
check "lego-test-writer.md: old-style brief (no report path) still gets a file" \
  "$(any_fn "$TW_REPORT" "old-style brief" "no report path" "names no path" "names no report path")" "yes"
check "lego-implementer.md: old-style brief (no report path) still gets a file" \
  "$(any_fn "$IMPL_REPORT" "old-style brief" "no report path" "names no path" "names no report path")" "yes"

# Clause 2b: that fallback is flagged in the report, not applied silently.
check "lego-test-writer.md: fallback is flagged in the report" \
  "$(has_fn "$TW_REPORT" "flag")" "yes"
check "lego-implementer.md: fallback is flagged in the report" \
  "$(has_fn "$IMPL_REPORT" "flag")" "yes"

# Note: the contract's other named invariant — the fenced STATUS block
# untouched — is already asserted above ("has literal 'STATUS: COMPLETE |
# ESCALATION'" for both files), so it is not duplicated here.

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
