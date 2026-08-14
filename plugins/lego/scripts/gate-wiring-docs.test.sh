#!/bin/bash
# Structural/anchor test for the doc half of Contract: 001-B05 gate wiring &
# docs composition. B05's Step 2 half (scaffold/SKILL.md's blocks-lint rung 0)
# is covered in scaffold-skill.test.sh; this file covers the four documents
# the same block composes:
#   - README.md               contract-level docs for background-first
#                             dispatch scheduling, wave-check.sh,
#                             blocks-lint.sh, and the derived per-block ceiling
#   - templates/blocks.md      example entry carries the optional
#                             `Justification:` line
#   - .claude-plugin/plugin.json  version per the plan's landing strategy
#
# It also carries Contract: B10 docs-and-templates (plan
# 001-lego-config-redesign) — the closed-world gate over the config removal:
#   - docs/config-schema.md and templates/lego.json are ABSENT;
#   - README.md describes the blocks.md-fields interface (per-block
#     `Setup:`/`Test:` proved by execution at plan time, budget and delivery
#     mode as Landing-strategy plan facts, --budget/--test-cmd as the
#     mechanical override channel) and names NO config surface;
#   - templates/blocks.md's example entry carries `Setup:`/`Test:`;
#   - MIGRATION.md gains an entry for the removal and keeps its history.
#
# Prose-block discipline: every .md assertion here runs against the
# comment-STRIPPED view of the file (strip_comments), so a contract comment
# quoting itself can never satisfy a check and the suite survives the
# comment's deletion at acceptance. The one deliberate exception is
# templates/blocks.md's example entry, which LIVES inside an HTML comment
# ("delete once real blocks exist") and is the deliverable itself.
#
# One check goes beyond anchors:
#   - blocks-lint.sh is RUN against templates/blocks.md with a tiny budget,
#     proving the example entry's Justification actually satisfies the lint
#     it is an example of (the contract's "justified over-ceiling block:
#     lint exits 0" edge case, end to end).
# Prose quality is verified by the orchestrator at acceptance, not here.
# Run: bash plugins/lego/scripts/gate-wiring-docs.test.sh  (non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
README="$PLUGIN_DIR/README.md"
CONFIG_SCHEMA="$PLUGIN_DIR/docs/config-schema.md"      # B10: must NOT exist
CONFIG_TEMPLATE="$PLUGIN_DIR/templates/lego.json"      # B10: must NOT exist
BLOCKS_TEMPLATE="$PLUGIN_DIR/templates/blocks.md"
MIGRATION="$PLUGIN_DIR/../../MIGRATION.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
BLOCKS_LINT="$SCRIPT_DIR/blocks-lint.sh"

# Contract: B09 derived version expectation
# Behavior: the suite derives its version expectation instead of pinning a
#   literal. (1) plugin.json's .version must be well-formed plain semver
#   (MAJOR.MINOR.PATCH, numeric fields only, no pre-release/build suffix —
#   this repo's plugins use plain X.Y.Z). (2) When the repo-root README.md
#   exists (PLUGIN_DIR/../../README.md), the version in the root README's
#   lego marketplace-table row (the "✅ vX.Y.Z" cell) must equal
#   plugin.json's .version; when that file is absent (plugin installed
#   standalone, no repo checkout), the equality check is SKIPPED with a
#   printed note, never failed.
# Outputs: PASS/FAIL lines through this suite's existing check() helper;
#   failures name got-vs-expected. No EXPECTED_VERSION literal remains in
#   this file once implemented.
# Errors: missing/unreadable plugin.json version -> FAIL (existing
#   behavior); root README present but the lego row missing or carrying no
#   parseable vX.Y.Z -> FAIL naming what was searched for.
# Invariants: every other check in this suite is unchanged; the suite still
#   exits non-zero on any failure; no dependency beyond what the file
#   already uses (grep/sed and the jq-fallback version extraction).
# Edge cases: malformed semver in plugin.json (e.g. "0.14", "v0.14.2",
#   "0.14.2-rc1") -> FAIL the format check.

# The repo-root README, present only when the plugin lives in a checkout of
# its marketplace repo. Absent for a standalone install — see the version
# section at the bottom of this file, which skips rather than fails then.
ROOT_README="$PLUGIN_DIR/../../README.md"
LEGO_ROW_LINK='[lego](plugins/lego/)'

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

# CONTENT with every HTML comment removed, including multi-line ones and the
# text around a comment that opens or closes mid-line. Prose-block discipline:
# a contract comment must never be able to satisfy an assertion about the
# prose it specifies, and every check must keep passing once the comment is
# deleted at acceptance.
strip_comments() { # content
  awk '
    {
      line = $0; out = ""
      while (1) {
        if (incomment) {
          i = index(line, "-->")
          if (i == 0) { line = ""; break }
          incomment = 0
          line = substr(line, i + 3)
        } else {
          i = index(line, "<!--")
          if (i == 0) { out = out line; break }
          out = out substr(line, 1, i - 1)
          line = substr(line, i + 4)
          incomment = 1
        }
      }
      print out
    }
  ' <<<"$1"
}

# The neighborhood of a literal: every matching line plus <n> lines of
# context either side. Used where the contract fixes that two facts are
# stated TOGETHER (e.g. `Test:` and "required") without fixing the sentence.
near() { # content literal context_lines
  grep -F -B"$3" -A"$3" -- "$2" <<<"$1"
}

# The first "## " section of CONTENT whose body contains LITERAL (case
# insensitive), heading included. Empty when no section matches.
section_with_i() { # content literal
  local content="$1" lit="$2"
  local starts=() total i s e sec ln
  while IFS= read -r ln; do starts+=("$ln"); done < <(grep -n '^## ' <<<"$content" | cut -d: -f1)
  total=$(wc -l <<<"$content")
  for (( i = 0; i < ${#starts[@]}; i++ )); do
    s=${starts[i]}
    if (( i + 1 < ${#starts[@]} )); then e=$(( ${starts[i+1]} - 1 )); else e=$total; fi
    sec=$(sed -n "${s},${e}p" <<<"$content")
    if grep -qiF -- "$lit" <<<"$sec"; then printf '%s\n' "$sec"; return; fi
  done
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

for f in "$README" "$BLOCKS_TEMPLATE" "$PLUGIN_JSON"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL  required file not found: $f"
    exit 1
  fi
done

README_RAW=$(cat "$README")
TEMPLATE_RAW=$(cat "$BLOCKS_TEMPLATE")

# The comment-stripped views every prose assertion below runs against.
README_DOC=$(strip_comments "$README_RAW")

# ===========================================================================
# Contract: B10 — the config surface is DELETED
# ===========================================================================
# File absence, not "no longer referenced": the schema doc and the starter
# config template are gone from the shipped plugin.

check "B10: docs/config-schema.md is deleted ($CONFIG_SCHEMA)" \
  "$([[ -e "$CONFIG_SCHEMA" ]] && echo present || echo absent)" "absent"
check "B10: templates/lego.json is deleted ($CONFIG_TEMPLATE)" \
  "$([[ -e "$CONFIG_TEMPLATE" ]] && echo present || echo absent)" "absent"

# ===========================================================================
# README.md — the new mechanisms documented at contract level
# ===========================================================================

# --- Behavior: background-first dispatch scheduling ------------------------
check "README: dispatch scheduling is documented as background-first" \
  "$(has_any_i "$README_DOC" 'background')" "yes"

# --- Behavior: the two new scripts are documented under ### Scripts --------
# Scoped to the Scripts section rather than the whole file: a passing
# mention elsewhere is not "documented at contract level".
README_SCRIPTS=$(section_of "$README_DOC" '### Scripts')

check "README: ### Scripts section exists" \
  "$(has_f "$README_SCRIPTS" '### Scripts')" "yes"
check "README: wave-check.sh documented under ### Scripts" \
  "$(has_f "$README_SCRIPTS" 'wave-check.sh')" "yes"
check "README: blocks-lint.sh documented under ### Scripts" \
  "$(has_f "$README_SCRIPTS" 'blocks-lint.sh')" "yes"

# --- Behavior: the derived per-block ceiling ------------------------------
# B10 rewrite: the ceiling is still DERIVED and still documented, but it is
# derived from the plan's PR size budget, not from a config key. The old
# `prSizeBudget / 2` anchor pinned the deleted config surface and is replaced
# by a wording-tolerant derivation check plus the forbidden-vocabulary sweep
# below, which is what makes the replacement at least as tight.
check "README: the per-block ceiling is named" \
  "$(has_any_i "$README_DOC" 'ceiling')" "yes"
check "README: the ceiling is stated as half the PR size budget (derived, not configured)" \
  "$(has_any_i "$README_DOC" 'half the PR size budget' 'half of the PR size budget' 'half the budget' 'half of the budget' 'PR size budget / 2' 'PR size budget divided')" "yes"

# ===========================================================================
# Contract: B10 — README describes the blocks.md-fields interface
# ===========================================================================
# The interface that REPLACES the deleted config: per-block `Setup:`
# (optional) / `Test:` (required) recorded on the block map at plan time
# after proof by execution; budget and delivery mode as plan facts in the
# Landing strategy; --budget/--test-cmd as the mechanical override channel.

check "README: the block map's per-block Test: field is documented" \
  "$(has_f "$README_DOC" 'Test:')" "yes"
check "README: the block map's per-block Setup: field is documented" \
  "$(has_f "$README_DOC" 'Setup:')" "yes"
check "README: Test: is documented as required" \
  "$(has_any_i "$(near "$README_DOC" 'Test:' 3)" 'required' 'every block')" "yes"
check "README: Setup: is documented as optional" \
  "$(has_any_i "$(near "$README_DOC" 'Setup:' 3)" 'optional')" "yes"
check "README: the commands are documented as proved by execution" \
  "$(has_any_i "$README_DOC" 'proved by execution' 'proven by execution' 'proof by execution' 'proved by running' 'proven by running')" "yes"
check "README: the commands are documented as recorded at plan time" \
  "$(has_any_i "$README_DOC" 'at plan time' 'plan time')" "yes"

# Budget and delivery mode as plan facts in the Landing strategy: both facts
# must live in the Landing-strategy neighborhood, not merely somewhere in the
# file, so "recorded in the plan" is pinned rather than assumed.
README_LANDING=$(near "$README_DOC" 'Landing strategy' 6)
check "README: a Landing strategy is documented" \
  "$([[ -n "$README_LANDING" ]] && echo yes || echo no)" "yes"
check "README: the budget is a plan fact in the Landing strategy" \
  "$(has_any_i "$README_LANDING" 'budget')" "yes"
check "README: the delivery mode is a plan fact in the Landing strategy" \
  "$(has_any_i "$README_LANDING" 'delivery mode')" "yes"

# The mechanical override channel: flags, not files.
check "README: the --budget override flag is documented" \
  "$(has_f "$README_DOC" '--budget')" "yes"
check "README: the --test-cmd override flag is documented" \
  "$(has_f "$README_DOC" '--test-cmd')" "yes"

# ===========================================================================
# Contract: B10 — closed world over the deleted config surface
# ===========================================================================
# Invariant: no surviving doc describes a config file as part of lego's
# interface. Every literal below is vocabulary of the deleted surface; a
# single surviving mention in README.md or templates/blocks.md is a FAIL.
# Edge case: MIGRATION.md's historical entries are EXEMPT — history is
# preserved verbatim there, and MIGRATION.md is deliberately not swept here.
DEAD_CONFIG_REFS=(
  '.claude/lego.json' '.local/config.json' 'lego.json' 'config.json'
  'config-schema' 'effective config' 'layered config'
  'testPatterns' 'prSizeBudget'
  'models.testWriter' 'models.implementer'
  'delivery.mode' 'delivery.worktreeDir'
)
for ref in "${DEAD_CONFIG_REFS[@]}"; do
  check "README closed world: no reference to the deleted config surface '$ref'" \
    "$(has_any_i "$README_DOC" "$ref")" "no"
  check "templates/blocks.md closed world: no reference to the deleted config surface '$ref'" \
    "$(has_any_i "$TEMPLATE_RAW" "$ref")" "no"
done

# Any OTHER backticked `models.<key>` / `delivery.<key>` / `commands.<key>`
# config key, so a renamed or newly invented config key cannot slip past the
# literal list above.
check "README closed world: no backticked config key of the deleted surface survives" \
  "$(grep -qE '`(models|delivery|commands)\.[A-Za-z]' <<<"$README_DOC" && echo yes || echo no)" "no"
check "templates/blocks.md closed world: no backticked config key of the deleted surface survives" \
  "$(grep -qE '`(models|delivery|commands)\.[A-Za-z]' <<<"$TEMPLATE_RAW" && echo yes || echo no)" "no"

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

# --- Contract: B10 — the example entry gains Setup:/Test: -----------------
# Adjacent block-entry fields in the same example, so a fresh repo inherits
# the interface that replaced the config: `Test:` required, `Setup:`
# optional, both carrying a real command as their value.
check "templates/blocks.md: example entry carries a Test: line" \
  "$(grep -qE '^[[:space:]]*- Test:' <<<"$EXAMPLE_ENTRY" && echo yes || echo no)" "yes"
check "templates/blocks.md: the Test: line carries a non-empty command" \
  "$(grep -qE '^[[:space:]]*- Test:[[:space:]]*[^[:space:]]' <<<"$EXAMPLE_ENTRY" && echo yes || echo no)" "yes"
check "templates/blocks.md: example entry carries a Setup: line" \
  "$(grep -qE '^[[:space:]]*- Setup:' <<<"$EXAMPLE_ENTRY" && echo yes || echo no)" "yes"
check "templates/blocks.md: the Setup: line carries a non-empty command" \
  "$(grep -qE '^[[:space:]]*- Setup:[[:space:]]*[^[:space:]]' <<<"$EXAMPLE_ENTRY" && echo yes || echo no)" "yes"
check "templates/blocks.md: Test: is documented as required" \
  "$(has_any_i "$(near "$TEMPLATE_RAW" 'Test:' 3)" 'required' 'every block')" "yes"
check "templates/blocks.md: Setup: is documented as optional" \
  "$(has_any_i "$(near "$TEMPLATE_RAW" 'Setup:' 3)" 'optional')" "yes"

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

# --- Format: plain semver, numeric fields only -----------------------------
# The offending value goes in the label so the FAIL line names what was read
# as well as got-vs-expected. "0.14", "v0.14.2" and "0.14.2-rc1" all fail
# here, as does an empty VERSION (missing or unreadable .version).
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
check "plugin.json: .version '$VERSION' is plain semver (MAJOR.MINOR.PATCH)" \
  "$([[ "$VERSION" =~ $SEMVER_RE ]] && echo well-formed || echo malformed)" \
  "well-formed"

# --- Agreement: the root README's marketplace row states the same version ---
# Derived, never pinned: a version bump edits plugin.json and the root README
# row, and this check keeps the two honest without a literal here.
if [[ ! -f "$ROOT_README" ]]; then
  echo "SKIP  root README not found at $ROOT_README — standalone plugin install, version agreement not checked"
else
  # The marketplace table row for this plugin: a table line (leading '|')
  # carrying the row's own link. Field 3 of a leading-'|' row is the status
  # cell ("✅ vX.Y.Z"); field 1 is the empty string before the first pipe.
  ROOT_ROW=$(grep -F -- "$LEGO_ROW_LINK" "$ROOT_README" | grep -E '^[[:space:]]*\|' | head -1)

  check "root README: marketplace row found (searched for a table row containing '$LEGO_ROW_LINK' in $ROOT_README)" \
    "$([[ -n "$ROOT_ROW" ]] && echo found || echo missing)" "found"

  if [[ -n "$ROOT_ROW" ]]; then
    ROOT_STATUS=$(awk -F'|' '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3 }' <<<"$ROOT_ROW")
    ROOT_VERSION=$(sed -n 's/^✅[[:space:]]*v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' <<<"$ROOT_STATUS")

    check "root README: status cell of that row parses as '✅ vX.Y.Z' (searched status cell '$ROOT_STATUS')" \
      "$([[ -n "$ROOT_VERSION" ]] && echo parsed || echo unparseable)" "parsed"

    if [[ -n "$ROOT_VERSION" ]]; then
      check "root README: marketplace row version agrees with plugin.json" \
        "$ROOT_VERSION" "$VERSION"
    fi
  fi
fi

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

README_SANS_REL=$(without_h2_section "$README_DOC" '## Relationships to other plugins')

for ref in "${FOREIGN_REFS[@]}"; do
  check "README layering: no reference to '$ref' outside Relationships" \
    "$(has_f "$README_SANS_REL" "$ref")" "no"
  check "templates/blocks.md layering: no reference to '$ref'" \
    "$(has_f "$TEMPLATE_RAW" "$ref")" "no"
done

# ===========================================================================
# Contract: B10 — MIGRATION.md gains the config-removal entry
# ===========================================================================
# MIGRATION.md lives in the marketplace repo root, so it is present only in a
# checkout — a standalone plugin install SKIPs here rather than failing, the
# same rule the root-README version agreement uses above.
if [[ ! -f "$MIGRATION" ]]; then
  echo "SKIP  MIGRATION.md not found at $MIGRATION — standalone plugin install, migration entry not checked"
else
  MIGRATION_DOC=$(strip_comments "$(cat "$MIGRATION")")

  # The entry is located by its subject (the config removal at 0.20.x), not
  # by a fixed heading, so the wording stays the author's.
  CONFIG_ENTRY=$(section_with_i "$MIGRATION_DOC" '0.20')

  check "MIGRATION: an entry for the 0.20.x config removal exists" \
    "$([[ -n "$CONFIG_ENTRY" ]] && echo yes || echo no)" "yes"
  check "MIGRATION: the entry names the removal as its subject" \
    "$(has_any_i "$CONFIG_ENTRY" 'config')" "yes"

  # What was deleted.
  for gone in 'config-schema.md' 'lego.json' 'config.json'; do
    check "MIGRATION: the entry names '$gone' among what was deleted" \
      "$(has_any_i "$CONFIG_ENTRY" "$gone")" "yes"
  done

  # What replaces it: the blocks.md fields, the Landing-strategy plan facts,
  # and the flag override channel.
  check "MIGRATION: the entry names the blocks.md Test: field as the replacement" \
    "$(has_f "$CONFIG_ENTRY" 'Test:')" "yes"
  check "MIGRATION: the entry names the blocks.md Setup: field as the replacement" \
    "$(has_f "$CONFIG_ENTRY" 'Setup:')" "yes"
  check "MIGRATION: the entry names the Landing strategy as the home of budget and delivery mode" \
    "$(has_any_i "$CONFIG_ENTRY" 'Landing strategy')" "yes"
  check "MIGRATION: the entry names the flag override channel" \
    "$(has_any_i "$CONFIG_ENTRY" '--budget' '--test-cmd')" "yes"

  # --- Invariant: history is preserved verbatim, never edited -------------
  # Append-only: the pre-existing lego entry's own sentences — including its
  # historical mentions of the now-deleted config files, which the exemption
  # above deliberately allows — must survive unchanged.
  MIGRATION_LEGO=$(section_with_i "$MIGRATION_DOC" '## lego — ported (from clam-v2)')
  check "MIGRATION: the pre-existing lego entry survives" \
    "$([[ -n "$MIGRATION_LEGO" ]] && echo yes || echo no)" "yes"
  for kept in \
    '## lego — ported (from clam-v2)' \
    'Skills renamed to drop the redundant prefix' \
    'templates/lego.json` (renamed from clam-v2'"'"'s `config.json`)' \
    'The status stays **ported' \
    'superseded by this plugin.'
  do
    check "MIGRATION history preserved verbatim: '$kept'" \
      "$(has_f "$MIGRATION_DOC" "$kept")" "yes"
  done

  # The exemption itself is stated in prose where the closed-world sweep is
  # defined ("Edge case: MIGRATION.md's historical entries are EXEMPT ..."),
  # per the contract's edge case. It is deliberately not re-asserted by a
  # check here: a grep of this file for its own sentence would be satisfied
  # by the check line itself, which proves nothing.
fi

# ===========================================================================
# Contract: B03 handoff wiring + docs + version
# ===========================================================================
# B03 composes the same document family (README, the two skills either side
# of the plan->scaffold seam, and plugin.json), so its checks belong to this
# gate. They live in their own file because B03's contract fixes an exact
# version literal, which B09's contract forbids inside THIS file. Running it
# from here keeps one command for the whole doc gate.
B03_SUITE="$SCRIPT_DIR/b03-handoff-docs.test.sh"
if [[ ! -f "$B03_SUITE" ]]; then
  echo "FAIL  B03 suite not found at $B03_SUITE"
  FAILED=1
else
  echo "---- B03 handoff wiring + docs + version ----"
  bash "$B03_SUITE" || FAILED=1
  echo "---- end B03 ----"
fi

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
