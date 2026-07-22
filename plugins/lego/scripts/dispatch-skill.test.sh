#!/bin/bash
# Structural/anchor test for skills/dispatch/SKILL.md against Contract: B02
# dispatch-skill-file-protocol (see
# .local/contracts/B02-dispatch-skill-file-protocol.md). This skill is a
# documentation block, not executable code, so the tests here are:
#   - "Required literal tokens": each token from the contract's list must
#     appear verbatim (fixed-string grep) in the target file.
#   - "Invariants": each heading the contract requires to survive the edit
#     must still exist.
#   - Frontmatter: `name: dispatch` is unchanged.
# These MUST fail against the current (pre-B02) SKILL.md for the token
# checks, and MUST pass once a real edit satisfies the contract's Behavior
# clauses. This file does not test prose semantics beyond tokens/headings —
# meaning is verified by the orchestrator at acceptance.
# Run: bash plugins/lego/scripts/dispatch-skill.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/dispatch/SKILL.md"

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

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi

RAW=$(cat "$SKILL")

# --- Frontmatter ---------------------------------------------------------
# Lines strictly between the first two '---' delimiters.
FRONTMATTER=$(awk '/^---$/{n++; next} n==1' "$SKILL")
NAME=$(printf '%s\n' "$FRONTMATTER" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')

check "frontmatter name is 'dispatch'" "$NAME" "dispatch"

# --- Required literal tokens (contract: "Required literal tokens") -------
# Each token below must appear verbatim in the target file. One assertion
# per token, fixed-string (non-regex) match, so no token's own regex
# metacharacters (e.g. '<', '>') need escaping.
check "token: ## Worker briefs" \
  "$(has_f "$RAW" '## Worker briefs')" "yes"
check "token: ## Unit status file" \
  "$(has_f "$RAW" '## Unit status file')" "yes"
check "token: .local/briefs/NN-<wave>-<blocks>.md" \
  "$(has_f "$RAW" '.local/briefs/NN-<wave>-<blocks>.md')" "yes"
check "token: .local/reports/NN-<wave>-<blocks>.md" \
  "$(has_f "$RAW" '.local/reports/NN-<wave>-<blocks>.md')" "yes"
check "token: .local/status.md" \
  "$(has_f "$RAW" '.local/status.md')" "yes"
check "token: read the brief file first" \
  "$(has_f "$RAW" 'read the brief file first')" "yes"
check "token: orchestrator-owned" \
  "$(has_f "$RAW" 'orchestrator-owned')" "yes"
check "token: a stale status file is a defect" \
  "$(has_f "$RAW" 'a stale status file is a defect')" "yes"

# --- Invariants (contract: "Invariants" heading list) ---------------------
# These headings must survive the edit unchanged.
for h in "## The per-unit pipeline" "### 1. Create the worktree" \
         "### 2. Test wave" "### 3. Implementation wave" \
         "### 4. Local merge" "### 5. Delivery" "## Escalation loop" \
         "## Engineer-owned blocks" "## Done"; do
  check "invariant heading survives: $h" "$(has_f "$RAW" "$h")" "yes"
done

# --- Manifest delivery content (contract: B01 dispatch-delivery-instructions)
# Anchors the Step 5 sub-sections (5a compose, 5b write manifest + deliver)
# and their required content, so a future edit that clobbers this section
# fails the test suite instead of silently regressing.
check "token: #### 5a. Compose PR content" \
  "$(has_f "$RAW" '#### 5a. Compose PR content')" "yes"
check "token: #### 5b. Write manifest and deliver" \
  "$(has_f "$RAW" '#### 5b. Write manifest and deliver')" "yes"
check "token: --manifest .local/pr-manifest.json" \
  "$(has_f "$RAW" '--manifest .local/pr-manifest.json')" "yes"
check "token: pr-body-template.md" \
  "$(has_f "$RAW" 'pr-body-template.md')" "yes"
check "token: merge master into the integration branch before delivery" \
  "$(has_f "$RAW" 'merge master into the integration branch before delivery')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
