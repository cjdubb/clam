#!/bin/bash
# Structural/anchor test for skills/create/template.md against the
# "Contract: B01 handover-plugin — template" HTML-comment docblock in that
# file. The template is documentation (markdown for a human/agent to fill
# in), not executable code, so the tests here are anchor-term checks against
# the rendered body (HTML comment docblock stripped, so the contract
# docblock's own prose — which legitimately names "Jira", "Sub-Jira", "CLIP"
# as terms to avoid — can never satisfy a check on its own).
#
# The stub does not pre-scaffold section headings — its body is the literal
# placeholder "Not yet implemented." under a title line — so the "all 7
# sections present" check below looks for markdown "## " headings whose text
# matches the contract's own vocabulary for each section topic, not a
# specific heading string a future implementer hasn't chosen yet.
#
# These MUST fail against the current stub body and MUST pass once a real
# template body satisfies the contract.
# Run: bash plugins/orchestrator-handover/scripts/b01-template.test.sh
# (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../skills/create/template.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

has() { # content pattern (case-insensitive extended regex)
  if grep -qiE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

has_f() { # content literal (case-sensitive fixed string)
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

if [[ ! -f "$TEMPLATE" ]]; then
  echo "FAIL  template.md not found at $TEMPLATE"
  exit 1
fi

# Rendered body: HTML comment docblock stripped so no check can pass
# vacuously off the contract's own descriptive prose.
BODY=$(sed '/<!--/,/-->/d' "$TEMPLATE")

check "rendered body has moved past the 'Not yet implemented' placeholder" \
  "$(has "$BODY" 'not yet implemented')" "no"

# --- Behavior ----------------------------------------------------------------
check "title line carries the {ISSUE-KEY} placeholder token" \
  "$(has_f "$BODY" '{ISSUE-KEY}')" "yes"

# --- Invariant: all 7 sections present ------------------------------------
HEADINGS=$(grep -E '^## ' <<<"$BODY")
HEADING_COUNT=$(printf '%s\n' "$HEADINGS" | grep -cE '^## ' || true)
check "at least 7 '## ' sections are present" \
  "$([[ "$HEADING_COUNT" -ge 7 ]] && echo yes || echo no)" "yes"

check "section 1: source-of-truth artifacts" \
  "$(has "$HEADINGS" 'source.of.truth|artifact')" "yes"
check "section 2: what is done" \
  "$(has "$HEADINGS" 'what is done|^## done')" "yes"
check "section 3: what is open" \
  "$(has "$HEADINGS" 'what is open|^## open')" "yes"
check "section 4: decisions pending" \
  "$(has "$HEADINGS" 'decision')" "yes"
check "section 5: proposed work breakdown" \
  "$(has "$HEADINGS" 'work breakdown|breakdown')" "yes"
check "section 6: cross-unit compatibility notes" \
  "$(has "$HEADINGS" 'compatib|cross-unit')" "yes"
check "section 7: recipient's first move" \
  "$(has "$HEADINGS" 'first move')" "yes"

# Extract the body text of one section: everything after a heading matching
# $2 (case-insensitive regex) up to the next "## " heading or EOF.
section_body() { # rendered_body heading_pattern
  awk -v pat="$2" '
    BEGIN{IGNORECASE=1}
    $0 ~ /^## / {
      if (found) exit
      if ($0 ~ pat) { found=1; next }
      next
    }
    found {print}
  ' <<<"$1"
}

DECISIONS_SECTION=$(section_body "$BODY" 'decision')
COMPAT_SECTION=$(section_body "$BODY" 'compatib|cross-unit')
FIRST_MOVE_SECTION=$(section_body "$BODY" 'first move')

# --- Edge case: no pending decisions -> section 4 carries a "None" marker --
check "decisions-pending section documents a 'None' marker for the no-decisions edge case" \
  "$(has "$DECISIONS_SECTION" 'none')" "yes"

# --- Edge case: no shared interfaces -> section 6 carries a "None" marker --
check "cross-unit compatibility section documents a 'None' marker for the no-shared-interfaces edge case" \
  "$(has "$COMPAT_SECTION" 'none')" "yes"

# --- Invariant: recipient's first move does not hard-depend on /start ------
check "recipient's first move section does not phrase /start as a hard requirement" \
  "$(has "$FIRST_MOVE_SECTION" 'must (run|use) /start|requires /start|depends on /start')" "no"

# --- Inputs: issue-tracker-agnostic placeholder tokens ----------------------
check "uses the {short-description} placeholder token" \
  "$(has_f "$BODY" '{short-description}')" "yes"
check "uses the {parent-issue} placeholder token" \
  "$(has_f "$BODY" '{parent-issue}')" "yes"

# --- Invariant: issue-tracker-agnostic (generic terms, not provider-specific) --
check "uses the generic term 'issue' (not provider-specific)" \
  "$(has "$BODY" '\bissue\b')" "yes"
check "never uses the Jira-specific term 'Sub-Jira'" "$(has "$BODY" 'sub-jira')" "no"
check "never uses Jira-specific 'CLIP-' ticket-key references" "$(has "$BODY" 'CLIP-[0-9]')" "no"
check "never names Jira as a hard dependency" "$(has "$BODY" '\bjira\b')" "no"

# --- Edge case: no issue tracker -> {ISSUE-KEY} may be replaced with a slug --
check "documents the no-issue-tracker slug fallback for {ISSUE-KEY}" \
  "$(has "$BODY" 'slug')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
