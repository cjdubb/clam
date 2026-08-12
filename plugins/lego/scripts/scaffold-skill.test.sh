#!/bin/bash
# Structural/anchor test for the materialization half of skills/plan/SKILL.md against Contract:
# 001-B03 untestable-block-gate. Unlike other lego contracts, this one has
# no separate .local/contracts file — its docblock is embedded inline in
# SKILL.md itself, as an HTML comment directly under the "### Step 2a"
# heading it describes. This skill is a documentation block, not executable
# code, so the tests here are:
#   - "Heading presence and ordering": "### Step 2a" exists and sits inside
#     Step 2 (after "## Step 2:", before "## Step 3:").
#   - "Section tokens": each contract-required phrase must appear verbatim
#     (fixed-string grep) WITHIN the Step 2a section's own prose — not
#     merely anywhere in the file. HTML comments are stripped from the
#     whole file before the section is extracted (same technique as
#     dispatch-skill.test.sh's pipe-safety checks), so the contract
#     docblock's own vocabulary — which sits inside this same section —
#     can never satisfy these checks by matching itself; only prose written
#     to replace the NotImplemented placeholder counts.
#   - "Marker": the NotImplemented placeholder must be gone.
# These MUST fail against the current (pre-B03) SKILL.md: the Step 2a
# section is still "NotImplemented: 001-B03 — untestable-block-gate.", so
# every token/marker check below fails for the right reason (an assertion
# failure, not a syntax error). They MUST pass once a real edit replaces
# that placeholder with prose satisfying the contract's clauses.
# This file does not test prose semantics beyond tokens/headings/order —
# meaning is verified by the orchestrator at acceptance.
#
# A second contract is covered further down: 001-B05 gate wiring & docs
# composition, whose Step 2 half (the blocks-lint rung 0) belongs to this
# same document. Its section carries its own note on the false-green trap
# its inline contract comment sets.
# Run: bash plugins/lego/scripts/scaffold-skill.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/plan/SKILL.md"

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

# Case-insensitive fixed-string presence: yes when ANY of the given literals
# appears. Used for phrasings where the contract fixes the fact but not the
# wording ("exit 1" vs "exits 1"), never to weaken a clause.
has_any_i() { # content literal...
  local content="$1"; shift
  local lit
  for lit in "$@"; do
    if grep -qiF -- "$lit" <<<"$content"; then echo yes; return; fi
  done
  echo no
}

# First line number (1-indexed) of a literal within a CONTENT string (as
# opposed to first_heading_line, which reads the file on disk). Ordering
# checks run over the comment-stripped content so the contract docblock's
# own vocabulary can never supply the ordering being asserted.
first_line_in() { # content literal
  grep -nF -- "$2" <<<"$1" | head -1 | cut -d: -f1
}

# Extracts Step 2's own gate prose from CONTENT: the "## Step 2" heading
# through to Step 2a (a separate contract, tested above) or Step 3,
# whichever comes first. Any subsection the gate wiring adds between the two
# is therefore in scope, while Step 2a's prose is not — placement inside
# that span is pinned by the ordering checks, not by this boundary.
step2_body_of() { # content
  awk '
    index($0, "## Step 6: Run the scaffold gate") == 1 && !seen {
      seen=1; capture=1; print; next
    }
    capture && (index($0, "### Step 6a") == 1 || index($0, "## ") == 1) { exit }
    capture { print }
  ' <<<"$1"
}

# First line number (1-indexed) at which a literal string appears at the
# start of a line, or empty if not found.
first_heading_line() { # literal
  grep -nF -- "$1" "$SKILL" | head -1 | cut -d: -f1
}

check_after() { # label line_a line_b -- assert a follows b
  if [[ -z "$2" || -z "$3" ]]; then
    echo "FAIL  $1 -> heading not found (line_a='$2' line_b='$3')"; FAILED=1
  elif (( $2 > $3 )); then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> line $2 does not follow line $3"; FAILED=1
  fi
}

check_before() { # label line_a line_b -- assert a precedes b
  if [[ -z "$2" || -z "$3" ]]; then
    echo "FAIL  $1 -> heading not found (line_a='$2' line_b='$3')"; FAILED=1
  elif (( $2 < $3 )); then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> line $2 does not precede line $3"; FAILED=1
  fi
}

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi

RAW=$(cat "$SKILL")

# --- Clause 1: heading exists, ordered inside Step 2 ----------------------
# (after "## Step 2:", before "## Step 3:")
check "heading exists: ### Step 6a: Blocks with no red/green cycle" \
  "$(has_f "$RAW" '### Step 6a: Blocks with no red/green cycle')" "yes"

STEP2_LINE=$(first_heading_line "## Step 6: Run the scaffold gate")
STEP2A_LINE=$(first_heading_line "### Step 6a: Blocks with no red/green cycle")
STEP3_LINE=$(first_heading_line "## Step 8: Update state and checkpoint")

check_after "Step 6a follows Step 6" "$STEP2A_LINE" "$STEP2_LINE"
check_before "Step 6a precedes Step 8" "$STEP2A_LINE" "$STEP3_LINE"

# --- Section scoping --------------------------------------------------------
# Strip HTML comments from the whole file first (removing the contract
# docblock's own text everywhere, including from the Step 2a section it
# sits inside), then extract the Step 2a section: from its heading up to,
# but not including, the next top-level "## " heading.
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")
SECTION_2A=$(awk '
  index($0, "### Step 6a: Blocks with no red/green cycle") == 1 { capture=1; print; next }
  capture && index($0, "## ") == 1 { exit }
  capture { print }
' <<<"$STRIPPED")

# --- Clause 2: acceptance gate = orchestrator verification against every
# contract clause AND explicit engineer acceptance (both required) --------
check "2a: acceptance gate names orchestrator verification against every contract clause" \
  "$(has_f "$SECTION_2A" 'against every contract clause')" "yes"
check "2a: engineer acceptance required in addition to orchestrator verification" \
  "$(has_f "$SECTION_2A" 'orchestrator verification alone does not accept')" "yes"

# --- Clause 3: a skipped test wave is always recorded with its reason,
# never silent ---------------------------------------------------------------
check "2a: skipped test wave is recorded with its reason" \
  "$(has_f "$SECTION_2A" 'recorded with its reason')" "yes"
check "2a: the skip is never silent" \
  "$(has_f "$SECTION_2A" 'never silent')" "yes"

# --- Clause 4: review-gating decided at scaffold time by the orchestrator,
# recorded on the block, never improvised at dispatch -----------------------
check "2a: review-gating decided at scaffold time" \
  "$(has_f "$SECTION_2A" 'decided at scaffold time')" "yes"
check "2a: review-gating recorded on the block" \
  "$(has_f "$SECTION_2A" 'recorded on the block')" "yes"
check "2a: review-gating is never a dispatch-time improvisation" \
  "$(has_f "$SECTION_2A" 'dispatch-time improvisation')" "yes"

# --- Clause 5: the bar is "no clause is executably assertable"; structural
# and anchor assertions count as executable, so a prose file with anchors
# is not review-gated --------------------------------------------------------
check "2a: bar is 'no clause is executably assertable'" \
  "$(has_f "$SECTION_2A" 'no clause is executably assertable')" "yes"
check "2a: structural/anchor assertions count as executable" \
  "$(has_f "$SECTION_2A" 'and anchor assertions count as executable')" "yes"
check "2a: prose file with structural anchors is not review-gated" \
  "$(has_f "$SECTION_2A" 'not review-gated')" "yes"

# --- Clause 6: a partially-testable block takes the normal test wave -------
check "2a: partial testability takes the normal test wave" \
  "$(has_f "$SECTION_2A" 'testability means the normal wave runs and covers what it can')" "yes"

# --- Edge case: engineer-owned review-gated block takes the SAME gate; the
# engineer cannot accept their own block unilaterally, the orchestrator
# still verifies ------------------------------------------------------------
check "2a: engineer-owned review-gated block is named" \
  "$(has_f "$SECTION_2A" 'engineer-owned')" "yes"
check "2a: engineer cannot accept their own review-gated block unilaterally" \
  "$(has_f "$SECTION_2A" 'cannot accept their own')" "yes"

# --- Edge case: README-style content with no assertable structure IS
# review-gated (the contrast to the "not review-gated" prose-with-anchors
# case pinned in Clause 5 above) ---------------------------------------------
check "2a: content with no assertable structure is review-gated" \
  "$(has_f "$SECTION_2A" 'no assertable structure')" "yes"

# --- Clause 7: no NotImplemented: 001-B03 marker survives ------------------
check "2a: NotImplemented: 001-B03 marker is gone" \
  "$(has_f "$RAW" 'NotImplemented: 001-B03')" "no"

# ===========================================================================
# Contract: 001-B05 gate wiring & docs composition — Step 2's rung 0
# ===========================================================================
# B05 wires the plan-time size lint into this skill's scaffold gate. Its
# contract lives in an HTML comment at the top of SKILL.md marked
# "(remove at acceptance)", and that comment QUOTES every anchor asserted
# below ("blocks-lint.sh", "rung 0", ".local/blocks.md", "/lego:plan").
# A whole-file grep would therefore be satisfied by the contract quoting
# itself — a false green before a word of prose is written. So every check
# below runs against $STEP2_BODY, extracted from the comment-STRIPPED file,
# and the last check asserts the contract comment is gone (prose blocks
# delete it at acceptance, per Step 1's own rule).
# The doc-file half of B05 (README, config-schema, templates, plugin.json)
# lives in gate-wiring-docs.test.sh.

# Step 2's own body: the gate prose, up to but excluding "### Step 2a".
STEP2_BODY=$(step2_body_of "$STRIPPED")

# --- Behavior: blocks-lint.sh is named in Step 2, before the rung list -----
check "step2: blocks-lint.sh is named in the Step 2 gate prose" \
  "$(has_f "$STEP2_BODY" 'blocks-lint.sh')" "yes"

STEP2_L=$(first_line_in "$STRIPPED" '## Step 6: Run the scaffold gate')
LINT_L=$(first_line_in "$STRIPPED" 'blocks-lint.sh')
RUNG1_L=$(first_line_in "$STRIPPED" '1. `typecheck`')

check_after "step2: blocks-lint.sh appears after the Step 2 heading" \
  "$LINT_L" "$STEP2_L"
check_before "step2: blocks-lint.sh precedes the typecheck rung list" \
  "$LINT_L" "$RUNG1_L"

check "step2: the lint is introduced as rung 0 (runs first)" \
  "$(has_any_i "$STEP2_BODY" 'rung 0' 'rung zero')" "yes"
check "step2: the lint runs against .local/blocks.md" \
  "$(has_f "$STEP2_BODY" '.local/blocks.md')" "yes"

# --- Behavior: the three exit codes and what each one means ----------------
check "step2: exit 1 (findings) is named" \
  "$(has_any_i "$STEP2_BODY" 'exit 1' 'exits 1' 'exit code 1')" "yes"
check "step2: exit-1 findings send the plan back to Step 3" \
  "$(has_f "$STEP2_BODY" 'back to Step 3')" "yes"
check "step2: findings are never patched silently at scaffold time" \
  "$(has_any_i "$STEP2_BODY" 'silently' 'silent')" "yes"
check "step2: exit 2 (environment/usage) is named" \
  "$(has_any_i "$STEP2_BODY" 'exit 2' 'exits 2' 'exit code 2')" "yes"
check "step2: only exit 0 proceeds to the existing rungs" \
  "$(has_any_i "$STEP2_BODY" 'exit 0' 'exits 0' 'exit code 0')" "yes"

# --- Edge case: blocks-lint.sh absent -> rung skipped with a loud warning --
check "step2 edge: an absent blocks-lint.sh is addressed" \
  "$(has_any_i "$STEP2_BODY" 'absent' 'not present' 'missing')" "yes"
check "step2 edge: the skipped rung warns explicitly, never silently" \
  "$(has_any_i "$STEP2_BODY" 'warn')" "yes"

# --- Edge case: a justified over-ceiling block is not re-argued here -------
check "step2 edge: justification is addressed at the gate" \
  "$(has_any_i "$STEP2_BODY" 'justif')" "yes"
check "step2 edge: the per-block ceiling is named" \
  "$(has_any_i "$STEP2_BODY" 'ceiling')" "yes"

# --- Invariant: the removable B05 contract comment is deleted --------------
check "B05 contract comment is gone from SKILL.md" \
  "$(has_f "$RAW" 'Contract: B05 gate wiring & docs composition')" "no"
check "B05 'remove at acceptance' marker is gone from SKILL.md" \
  "$(has_f "$RAW" 'B05 gate wiring & docs composition (remove at acceptance)')" "no"

# --- Invariant: the new gate prose names no other plugin ------------------
# Layering rule: lego is a leaf. Bare words are deliberately NOT in this
# list — "landing strategy" is lego's own vocabulary and `build` is a
# config command name; only unambiguous cross-plugin forms are checked.
# The "<name> plugin" phrasings are COMPOSED rather than written out:
# spelling them literally would make this file itself a cross-plugin
# English reference in the repo's architecture lint, which is exactly the
# thing being asserted absent.
FOREIGN_NAMES=(landing tracking worktrees build)
FOREIGN_REFS=(
  '/landing:' '/tracking:' '/build:'
  'landing@' 'tracking@' 'build@' 'worktrees@'
  'plugins/landing' 'plugins/tracking' 'plugins/build' 'plugins/worktrees'
  'newtree' 'rmtree'
)
for name in "${FOREIGN_NAMES[@]}"; do
  FOREIGN_REFS+=("$name plugin")
done
for ref in "${FOREIGN_REFS[@]}"; do
  check "step2 layering: no reference to '$ref'" \
    "$(has_f "$STEP2_BODY" "$ref")" "no"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
