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

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
