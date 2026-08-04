#!/bin/bash
# Structural/anchor test for the doc half of Contract: 001-B05 gate wiring &
# docs composition. B05's Step 2 half (scaffold/SKILL.md's blocks-lint rung 0)
# is covered in scaffold-skill.test.sh; this file covers the four documents
# the same block composes:
#   - README.md               contract-level docs for background-first
#                             dispatch scheduling, wave-check.sh,
#                             blocks-lint.sh, and the derived per-block ceiling
#   - docs/config-schema.md    prSizeBudget row documents the DERIVED ceiling,
#                             introducing no new config key
#   - templates/blocks.md      example entry carries the optional
#                             `Justification:` line
#   - .claude-plugin/plugin.json  version per the plan's landing strategy
#
# None of these four files carries a removable contract comment, so plain
# whole-file anchors here cannot be satisfied by a contract quoting itself
# (the trap scaffold-skill.test.sh has to work around). Two checks go beyond
# anchors:
#   - the field-name list of config-schema's schema table is pinned, so
#     "introduces no new config key" is mechanically enforced rather than
#     assumed;
#   - blocks-lint.sh is RUN against templates/blocks.md with a tiny budget,
#     proving the example entry's Justification actually satisfies the lint
#     it is an example of (the contract's "justified over-ceiling block:
#     lint exits 0" edge case, end to end).
# Prose quality is verified by the orchestrator at acceptance, not here.
# Run: bash plugins/lego/scripts/gate-wiring-docs.test.sh  (non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
README="$PLUGIN_DIR/README.md"
CONFIG_SCHEMA="$PLUGIN_DIR/docs/config-schema.md"
BLOCKS_TEMPLATE="$PLUGIN_DIR/templates/blocks.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
BLOCKS_LINT="$SCRIPT_DIR/blocks-lint.sh"

EXPECTED_VERSION="0.14.2"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Fixed-string presence, case-sensitive. `--` guards leading-dash literals.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Case-insensitive presence: yes when ANY literal appears. Used where the
# contract fixes the fact but not the wording, never to weaken a clause.
has_any_i() { # content literal...
  local content="$1"; shift
  local lit
  for lit in "$@"; do
    if grep -qiF -- "$lit" <<<"$content"; then echo yes; return; fi
  done
  echo no
}

# Extracts a section from CONTENT: the line matching <start> at column 1,
# through to (not including) the next markdown heading of any level.
section_of() { # content start_literal
  awk -v start="$2" '
    index($0, start) == 1 && !seen { seen=1; capture=1; print; next }
    capture && $0 ~ /^#+ / { exit }
    capture { print }
  ' <<<"$1"
}

# CONTENT with one section removed (start heading through the line before
# the next heading of the same-or-higher level, i.e. the next "## ").
without_h2_section() { # content start_literal
  awk -v start="$2" '
    index($0, start) == 1 { skipping=1; next }
    skipping && index($0, "## ") == 1 { skipping=0 }
    !skipping { print }
  ' <<<"$1"
}

for f in "$README" "$CONFIG_SCHEMA" "$BLOCKS_TEMPLATE" "$PLUGIN_JSON"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL  required file not found: $f"
    exit 1
  fi
done

README_RAW=$(cat "$README")
SCHEMA_RAW=$(cat "$CONFIG_SCHEMA")
TEMPLATE_RAW=$(cat "$BLOCKS_TEMPLATE")

# ===========================================================================
# README.md — the new mechanisms documented at contract level
# ===========================================================================

# --- Behavior: background-first dispatch scheduling ------------------------
check "README: dispatch scheduling is documented as background-first" \
  "$(has_any_i "$README_RAW" 'background')" "yes"

# --- Behavior: the two new scripts are documented under ### Scripts --------
# Scoped to the Scripts section rather than the whole file: a passing
# mention elsewhere is not "documented at contract level".
README_SCRIPTS=$(section_of "$README_RAW" '### Scripts')

check "README: ### Scripts section exists" \
  "$(has_f "$README_SCRIPTS" '### Scripts')" "yes"
check "README: wave-check.sh documented under ### Scripts" \
  "$(has_f "$README_SCRIPTS" 'wave-check.sh')" "yes"
check "README: blocks-lint.sh documented under ### Scripts" \
  "$(has_f "$README_SCRIPTS" 'blocks-lint.sh')" "yes"

# --- Behavior: the derived per-block ceiling ------------------------------
check "README: the per-block ceiling is named" \
  "$(has_any_i "$README_RAW" 'ceiling')" "yes"
check "README: the ceiling is stated as derived from prSizeBudget" \
  "$(has_f "$README_RAW" 'prSizeBudget / 2')" "yes"

# ===========================================================================
# docs/config-schema.md — the prSizeBudget row, and no new key
# ===========================================================================

# The schema's field table row for delivery.prSizeBudget, matched on the
# row's first cell so the assertion lands on the row itself, not the file.
BUDGET_ROW=$(grep -F -- '| `delivery.prSizeBudget`' "$CONFIG_SCHEMA")

check "config-schema: delivery.prSizeBudget row exists" \
  "$([[ -n "$BUDGET_ROW" ]] && echo yes || echo no)" "yes"
check "config-schema: the prSizeBudget row documents the per-block ceiling" \
  "$(has_any_i "$BUDGET_ROW" 'ceiling')" "yes"
check "config-schema: the prSizeBudget row shows the derivation prSizeBudget / 2" \
  "$(has_f "$BUDGET_ROW" 'prSizeBudget / 2')" "yes"

# --- Invariant: the ceiling introduces NO new config key ------------------
# The schema table's first column, in order. A row added or removed here is
# a config-surface change, which this block's contract forbids: the ceiling
# is derived, never configured.
SCHEMA_FIELDS=$(grep -oE '^\| `[^`]+`' "$CONFIG_SCHEMA" | sed 's/^| //' | tr -d '`' | paste -sd, -)
EXPECTED_FIELDS='commands.test,commands.typecheck,commands.build,commands.lint,models.testWriter,models.implementer,testPatterns,delivery.mode,delivery.worktreeDir,delivery.prSizeBudget'

check "config-schema: config keys unchanged (no new key for the ceiling)" \
  "$SCHEMA_FIELDS" "$EXPECTED_FIELDS"

# ===========================================================================
# templates/blocks.md — the example entry's optional Justification line
# ===========================================================================

# The example entry lives INSIDE an HTML comment ("delete once real blocks
# exist"), so comments are deliberately NOT stripped for this file — the
# example is the deliverable.
EXAMPLE_ENTRY=$(awk '
  index($0, "<!-- Example entry") == 1 { capture=1 }
  capture { print }
  capture && $0 ~ /-->/ && index($0, "<!-- Example entry") != 1 { exit }
' "$BLOCKS_TEMPLATE")

check "templates/blocks.md: example entry block is present" \
  "$(has_f "$EXAMPLE_ENTRY" '## B01')" "yes"
check "templates/blocks.md: example entry carries a Justification: line" \
  "$(grep -qE '^[[:space:]]*- Justification:' <<<"$EXAMPLE_ENTRY" && echo yes || echo no)" "yes"
check "templates/blocks.md: the Justification line carries a non-empty value" \
  "$(grep -qE '^[[:space:]]*- Justification:[[:space:]]*[^[:space:]]' <<<"$EXAMPLE_ENTRY" && echo yes || echo no)" "yes"
check "templates/blocks.md: the field is documented as optional" \
  "$(has_any_i "$TEMPLATE_RAW" 'optional')" "yes"

# --- Edge case (end to end): a justified over-ceiling block passes lint ----
# Budget 2 gives ceiling 1, so the example's Est is over ceiling whatever it
# is set to; the run therefore isolates the Justification. Exit 0 proves the
# example satisfies the very lint it is an example for; exit 1 means the
# Justification is missing or empty.
if [[ ! -x "$BLOCKS_LINT" && ! -f "$BLOCKS_LINT" ]]; then
  echo "FAIL  templates/blocks.md: blocks-lint.sh not found at $BLOCKS_LINT"
  FAILED=1
else
  LINT_OUT=$(bash "$BLOCKS_LINT" --budget 2 "$BLOCKS_TEMPLATE" 2>&1)
  LINT_RC=$?
  check "templates/blocks.md: over-ceiling example passes blocks-lint (justified)" \
    "$LINT_RC" "0"
  if [[ "$LINT_RC" != "0" ]]; then
    # Indented so the lint's own verdict line can never be misread as one
    # of this suite's PASS/FAIL lines.
    printf '%s\n' "      blocks-lint said:"
    printf '%s\n' "$LINT_OUT" | sed 's/^/        | /'
  fi
fi

# ===========================================================================
# .claude-plugin/plugin.json — version per the plan's landing strategy
# ===========================================================================

if command -v jq >/dev/null 2>&1; then
  check "plugin.json: parses as JSON" \
    "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"
  VERSION=$(jq -r '.version // ""' "$PLUGIN_JSON" 2>/dev/null)
else
  VERSION=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_JSON" \
    | head -1 | sed 's/.*"\(.*\)"$/\1/')
fi

check "plugin.json: version is $EXPECTED_VERSION" "$VERSION" "$EXPECTED_VERSION"

# ===========================================================================
# Invariant: the composed docs name no other plugin (layering rule)
# ===========================================================================
# Bare words are deliberately absent from this list: "landing strategy" is
# lego's own vocabulary and `build` is a config command name. Only
# unambiguous cross-plugin forms are checked.
#
# README's "## Relationships to other plugins" section is excluded — the
# repo's README template requires that section, and naming siblings is its
# entire purpose. Every OTHER section of the README is in scope.
#
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

README_SANS_REL=$(without_h2_section "$README_RAW" '## Relationships to other plugins')

for ref in "${FOREIGN_REFS[@]}"; do
  check "README layering: no reference to '$ref' outside Relationships" \
    "$(has_f "$README_SANS_REL" "$ref")" "no"
  check "config-schema layering: no reference to '$ref'" \
    "$(has_f "$SCHEMA_RAW" "$ref")" "no"
  check "templates/blocks.md layering: no reference to '$ref'" \
    "$(has_f "$TEMPLATE_RAW" "$ref")" "no"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
