#!/bin/bash
# Structural/anchor test for Contract: B03 handoff wiring + docs + version.
#
# B03 is a composition block: it asserts that the two skills either side of
# the plan->scaffold seam, and the README paragraph that summarises that
# seam, describe the SAME handoff — plan hands over per-block approved
# interface drafts; scaffold materializes those drafts into stubs — and that
# plugin.json carries the version bump the plan's landing strategy assigns
# to this unit's PR group.
#
#   - skills/plan/SKILL.md      the plan produces per-block interface drafts
#                               (signature + six drafted contract clauses)
#                               and carries them to disk in the plan
#                               document's "Interface drafts" section
#   - skills/scaffold/SKILL.md  scaffold materializes those approved drafts,
#                               transcribing rather than designing, with
#                               deviation legitimate only via the plan
#                               document's Changelog (return-to-plan)
#   - README.md                 the workflow summary describes the same
#                               handoff in the same terms
#   - .claude-plugin/plugin.json  version bumped for installed users
#
# This file is deliberately SEPARATE from gate-wiring-docs.test.sh, which
# carries B09's standing invariant that no literal version expectation
# remains in that file: B03's contract fixes an exact version, so the
# literal lives here instead. gate-wiring-docs.test.sh runs this file at its
# end and folds the result into its own exit status, so the anchor suite
# remains the single command to run.
#
# The README carries B03's own contract as an HTML comment ("remove at
# acceptance"). Comments are STRIPPED from every markdown file before any
# slicing or matching here, so a contract quoting itself can never satisfy
# an anchor.
#
# Prose quality is verified by the orchestrator at acceptance, not here.
# Run: bash plugins/lego/scripts/b03-handoff-docs.test.sh  (non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
README="$PLUGIN_DIR/README.md"
PLAN_SKILL="$PLUGIN_DIR/skills/plan/SKILL.md"
SCAFFOLD_SKILL="$PLUGIN_DIR/skills/plan/SKILL.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"

# Contract: "version bumps 0.16.x so installed users receive the change
# (exact bump per the PR group landing it)". This unit lands in PR group G02
# per the plan's landing strategy, which assigns 0.16.2. Later bumps move
# this anchor with them; currently 0.24.0 (work-graph nodes written at plan time and
# empty-frontier approval gate).
EXPECTED_VERSION='0.24.0'

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

has_any_i() { # content literal...
  local content="$1"; shift
  local lit
  for lit in "$@"; do
    if grep -qiF -- "$lit" <<<"$content"; then echo yes; return; fi
  done
  echo no
}

# Presence of a phrase that may be broken across lines by markdown wrapping:
# all whitespace runs collapse to single spaces before matching, so an
# assertion pins the wording, never the line breaks.
has_any_i_wrapped() { # content literal...
  local content="$1"; shift
  local flat
  flat=$(tr '\n' ' ' <<<"$content" | tr -s '[:space:]' ' ')
  has_any_i "$flat" "$@"
}

# Drops every HTML comment, including multi-line ones. B03's own contract
# comment at the top of the README is a comment, so no anchor below can be
# satisfied by the contract restating itself.
strip_comments() { # content
  awk '
    { line = $0 }
    {
      while (1) {
        if (inc) {
          i = index(line, "-->")
          if (i == 0) { line = ""; break }
          line = substr(line, i + 3); inc = 0
        } else {
          i = index(line, "<!--")
          if (i == 0) break
          out = out substr(line, 1, i - 1)
          line = substr(line, i + 4); inc = 1
        }
      }
      if (!inc) { print out line; out = "" }
    }
  ' <<<"$1"
}

# Section from CONTENT: the line matching <start> at column 1, through to
# (not including) the next markdown heading of any level.
section_of() { # content start_literal
  awk -v start="$2" '
    index($0, start) == 1 && !seen { seen=1; capture=1; print; next }
    capture && $0 ~ /^#+ / { exit }
    capture { print }
  ' <<<"$1"
}

# CONTENT with one "## " section removed (heading through the line before
# the next same-or-higher-level heading).
without_h2_section() { # content start_literal
  awk -v start="$2" '
    index($0, start) == 1 { skipping=1; next }
    skipping && index($0, "## ") == 1 { skipping=0 }
    !skipping { print }
  ' <<<"$1"
}

for f in "$README" "$PLAN_SKILL" "$SCAFFOLD_SKILL" "$PLUGIN_JSON"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL  required file not found: $f"
    exit 1
  fi
done

README_MD=$(strip_comments "$(cat "$README")")
PLAN_MD=$(strip_comments "$(cat "$PLAN_SKILL")")
SCAFFOLD_MD=$(strip_comments "$(cat "$SCAFFOLD_SKILL")")

# ===========================================================================
# Handoff, plan side: the plan hands over per-block interface drafts
# ===========================================================================
# These anchors already exist in plan/SKILL.md; pinning the ones that carry
# the handoff makes the seam a regression-protected fact rather than a
# coincidence of two files that happen to agree today.

check "plan: the per-block draft is named an interface draft" \
  "$(has_any_i "$PLAN_MD" 'interface draft')" "yes"
check "plan: the draft is stated as the content bar every block clears" \
  "$(has_any_i_wrapped "$PLAN_MD" 'content bar')" "yes"
check "plan: the draft carries a signature" \
  "$(has_any_i "$PLAN_MD" 'signature')" "yes"
check "plan: the draft carries all six contract clauses" \
  "$(has_any_i_wrapped "$PLAN_MD" 'all six contract clauses' 'six contract clauses' 'six clauses')" "yes"

# The six clause names, each of which the draft must carry a line or two of.
for clause in Behavior Inputs Outputs Errors Invariants 'Edge cases'; do
  check "plan: the six-clause bar names '$clause'" \
    "$(has_f "$PLAN_MD" "$clause")" "yes"
done

# The handover artifact itself: the plan document's Interface drafts
# section is where scaffold reads the design from.
check "plan: the plan document carries an Interface drafts section" \
  "$(has_f "$PLAN_MD" 'Interface drafts')" "yes"
check "plan: that section is named as where the scaffold reads the design from" \
  "$(has_any_i_wrapped "$PLAN_MD" 'where the scaffold reads the design from')" "yes"
check "plan: a block with no draft is called out as not plan-complete" \
  "$(has_any_i_wrapped "$PLAN_MD" 'not plan-complete')" "yes"

# ===========================================================================
# Handoff, scaffold side: scaffold materializes the approved drafts
# ===========================================================================

SCAFFOLD_INTRO=$(section_of "$SCAFFOLD_MD" '## Materialization')

check "scaffold: the intro states materialization transcribes agreed interfaces" \
  "$(has_any_i "$SCAFFOLD_INTRO" 'materializes')" "yes"
check "scaffold: the intro names the plan's Interface drafts section as the source" \
  "$(has_f "$SCAFFOLD_INTRO" 'Interface drafts')" "yes"

SCAFFOLD_STEP1=$(section_of "$SCAFFOLD_MD" '## Step 5: Write the stubs')

check "scaffold: the stubs step exists" \
  "$(has_f "$SCAFFOLD_STEP1" '## Step 5: Write the stubs')" "yes"
check "scaffold: the stubs step says to transcribe the agreed draft" \
  "$(has_any_i_wrapped "$SCAFFOLD_STEP1" 'transcribe its agreed draft')" "yes"
check "scaffold: Step 1 names the plan's Interface drafts section as the source" \
  "$(has_f "$SCAFFOLD_STEP1" 'Interface drafts')" "yes"
check "scaffold: Step 1 forbids new design at scaffold time" \
  "$(has_any_i_wrapped "$SCAFFOLD_STEP1" 'New design is not written at scaffold time')" "yes"

# The return-to-plan event, named, with the Changelog as its record. This is
# the seam's escape hatch: without it "materializes, never designs" has no
# legitimate path for a discovery that invalidates an approved draft.
check "scaffold: the return-to-design event is named" \
  "$(has_any_i "$SCAFFOLD_STEP1" 'return-to-design')" "yes"
check "scaffold: the return-to-plan event records in the plan document's Changelog" \
  "$(has_any_i_wrapped "$SCAFFOLD_STEP1" "plan document's Changelog")" "yes"
check "scaffold: deviating from an agreed draft with no Changelog entry is a defect" \
  "$(has_any_i "$SCAFFOLD_STEP1" 'scaffold defect')" "yes"

# ===========================================================================
# README workflow summary: the same handoff, in the same terms
# ===========================================================================
# Scoped to the workflow paragraph, not the whole file: a matching phrase
# elsewhere in a 400-line README is not "the workflow summary describes the
# handoff".

README_WORKFLOW=$(section_of "$README_MD" '### Plan and scaffold a deliverable')

check "README: the plan-and-scaffold workflow section exists" \
  "$(has_f "$README_WORKFLOW" '### Plan and scaffold a deliverable')" "yes"
check "README workflow: plan is described as producing interface drafts" \
  "$(has_any_i "$README_WORKFLOW" 'interface draft')" "yes"
check "README workflow: those drafts are described as agreed with the engineer" \
  "$(has_any_i_wrapped "$README_WORKFLOW" 'agreed interface draft' 'agreed draft' 'interface drafts agreed with the engineer' 'drafts agreed with the engineer')" "yes"
check "README workflow: scaffold is described as materializing those drafts" \
  "$(has_any_i "$README_WORKFLOW" 'materializ')" "yes"
check "README workflow: what scaffold materializes them into is stubs" \
  "$(has_any_i "$README_WORKFLOW" 'stub')" "yes"

# ===========================================================================
# Version: bumped so installed users receive the change
# ===========================================================================

if command -v jq >/dev/null 2>&1; then
  VERSION=$(jq -r '.version // ""' "$PLUGIN_JSON" 2>/dev/null)
else
  VERSION=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_JSON" \
    | head -1 | sed 's/.*"\(.*\)"$/\1/')
fi

check "plugin.json: .version is the bump this unit's PR group lands" \
  "$VERSION" "$EXPECTED_VERSION"

# ===========================================================================
# Invariant: none of the three files names a sibling or composite plugin
# ===========================================================================
# The "<name> plugin" English phrasings are COMPOSED rather than spelled
# out, so this file does not itself become the cross-plugin reference it
# asserts absent.
#
# Two allowances, both narrow:
#   - the README's "## Relationships to other plugins" section, which the
#     repo's README template requires and whose entire purpose is naming
#     siblings;
#   - lego's own `lego@clam` install line in Getting started, which is the
#     plugin naming itself, not a sibling.

FOREIGN_NAMES=(landing tracking worktrees build forge-github forge-gitlab)
FOREIGN_REFS=(
  '/landing:' '/tracking:' '/build:'
  'landing:' 'tracking:'
  'landing@' 'tracking@' 'build@' 'worktrees@'
  'forge-github' 'forge-gitlab'
  'plugins/landing' 'plugins/tracking' 'plugins/build' 'plugins/worktrees'
  'newtree' 'rmtree'
)
for name in "${FOREIGN_NAMES[@]}"; do
  FOREIGN_REFS+=("$name plugin")
done

README_SANS_REL=$(without_h2_section "$README_MD" '## Relationships to other plugins')

for ref in "${FOREIGN_REFS[@]}"; do
  check "README layering: no reference to '$ref' outside Relationships" \
    "$(has_f "$README_SANS_REL" "$ref")" "no"
  check "plan layering: no reference to '$ref'" \
    "$(has_f "$PLAN_MD" "$ref")" "no"
  check "scaffold layering: no reference to '$ref'" \
    "$(has_f "$SCAFFOLD_MD" "$ref")" "no"
done

# --- Marketplace ids: only lego's own -------------------------------------
# Every `<name>@clam` id appearing in the three files, deduplicated. lego's
# own install line is the sole legitimate one; any other id is a sibling
# reference regardless of section.
MARKET_IDS=$(grep -ohE '[a-z][a-z0-9-]*@clam' "$README" "$PLAN_SKILL" "$SCAFFOLD_SKILL" \
  | sort -u | grep -v '^lego@clam$' | paste -sd, -)

check "layering: no marketplace id other than lego's own is named" \
  "$MARKET_IDS" ""

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS  (B03)"; else echo "FAILURES  (B03)"; fi
exit $FAILED
