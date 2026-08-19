#!/bin/bash
# Content test for the B09 build-skill-conversion /build:context skill
# (plugins/build/skills/context/SKILL.md), the on-demand replacement for
# the removed SessionStart hook. The skill body is prose, not executable
# code, so this test checks for the presence of the contract's required
# clauses (companion detection, adaptive framing, conceptual-only
# invariant, no-source invariant, build-not-deliver naming, no-hooks
# invariant), not exact wording.
#
# All content checks (except the frontmatter and the global
# NotImplemented check) run against the file with its HTML comment block
# (the contract docblock) AND its YAML frontmatter stripped out first.
# Both already state every required clause verbatim — the docblock as
# the contract itself, the frontmatter description as a summary of it —
# so a check against the raw file could pass on the unimplemented stub
# for the wrong reason. Stripping ensures every clause check can only be
# satisfied by the real skill body that replaces the "NotImplemented:
# B09" marker. Same discipline as
# plugins/forge-github/scripts/create-pr.test.sh.
#
# Run: bash plugins/build/scripts/b09-context-skill.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
SKILL="$PLUGIN_ROOT/skills/context/SKILL.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

strip_frontmatter() { # file -> body with the leading YAML frontmatter block
  # removed. The frontmatter's own "description:" line already contains
  # contract vocabulary ("landing", "lego", "tracking", "delivery
  # framework", "conceptual"), so leaving it in would make those checks
  # pass on the unimplemented stub for the wrong reason.
  awk '
    NR==1 && $0=="---" {infm=1; next}
    infm && $0=="---" {infm=0; next}
    infm {next}
    {print}
  ' "$1" 2>/dev/null
}

strip_comments_stdin() {
  awk '/<!--/{c=1} !c{print} /-->/{c=0}'
}

# Strip the "**NotImplemented: B09**" marker paragraph too, so the
# marker's own prose (which restates that the docblock above is the
# contract) can never satisfy a content check.
strip_notimplemented_stdin() {
  awk '
    /^\*\*NotImplemented:/ {skip=1}
    skip && /^$/ {skip=0; next}
    skip {next}
    {print}
  '
}

# GATE_BODY keeps the NotImplemented marker paragraph so check 1 below can
# actually detect its presence on the stub and its absence once the real
# body replaces it — stripping it here would make that check vacuously
# pass regardless of implementation state.
GATE_BODY="$(strip_frontmatter "$SKILL" | strip_comments_stdin)"
GATE_FLAT_BODY="$(printf '%s' "$GATE_BODY" | tr '\n' ' ' | tr -s ' ')"

# BODY additionally strips the NotImplemented marker paragraph, per the
# brief: the marker's own prose must never satisfy a content-clause check.
BODY="$(printf '%s' "$GATE_BODY" | strip_notimplemented_stdin)"

FLAT_BODY="$(printf '%s' "$BODY" | tr '\n' ' ' | tr -s ' ')"

has_literal() { # needle (checked against FLAT_BODY, case-insensitive)
  printf '%s' "$FLAT_BODY" | grep -qiF -- "$1" && echo yes || echo no
}

has_pattern_ci() { # extended-regex (checked against FLAT_BODY)
  printf '%s' "$FLAT_BODY" | grep -qiE -- "$1" && echo yes || echo no
}

check "skill file exists" "$([[ -f "$SKILL" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 0. Frontmatter shape (stable metadata, unaffected by implementation).
# ---------------------------------------------------------------------------

check "frontmatter name is context" \
  "$(grep -m1 '^name:' "$SKILL" 2>/dev/null | sed 's/^name: *//')" "context"

fm_description=$(awk '
  NR==1 && $0=="---" {infm=1; next}
  infm && $0=="---" {exit}
  infm && /^description:/ {sub(/^description: */,""); print; found=1}
' "$SKILL" 2>/dev/null)
check "frontmatter description is present and non-empty" \
  "$([[ -n "$(printf '%s' "$fm_description" | tr -d '[:space:]')" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 1. No NotImplemented marker in the rendered skill body (docblock- and
#    frontmatter-stripped, marker itself stripped separately above so its
#    own text can't satisfy this check by accident). This is the
#    red/green gate: fails until the marker is replaced by the real body.
# ---------------------------------------------------------------------------

check "no NotImplemented marker in skill body" \
  "$(printf '%s' "$GATE_FLAT_BODY" | grep -qiE -- 'NotImplemented' && echo yes || echo no)" "no"

# ---------------------------------------------------------------------------
# 2. Behavior clause 1 -- companion detection by skill-catalog presence,
#    for all three companion plugins, never sourcing/importing companion
#    code.
# ---------------------------------------------------------------------------

check "detection: landing detected via landing:land catalog entry" \
  "$(has_literal 'landing:land')" "yes"
check "detection: lego detected via lego:plan catalog entry" \
  "$(has_literal 'lego:plan')" "yes"
check "detection: tracking detected via its session-start instructions" \
  "$(has_pattern_ci 'tracking.{0,60}session.start|session.start.{0,60}tracking')" "yes"
check "detection: catalog-based, never sources/imports companion code" \
  "$(has_pattern_ci 'never (source|import)|not (source|import)ed|without (sourcing|importing)')" "yes"
check "detection: catalog-based only" \
  "$(has_pattern_ci 'catalog.based|skill catalog')" "yes"

# ---------------------------------------------------------------------------
# 3. Behavior clause 2 -- adaptive framing per companion, including the
#    none-present case.
# ---------------------------------------------------------------------------

check "framing: landing governs merge policy / how work lands" \
  "$(has_pattern_ci 'merge policy')" "yes"
check "framing: landing governs local-merge-vs-PR-creation distinction" \
  "$(has_pattern_ci 'local merge|PR creation')" "yes"
check "framing: lego provides plan/scaffold/dispatch workflow" \
  "$(has_pattern_ci 'plan.{0,20}scaffold.{0,20}dispatch|scaffold.{0,20}dispatch')" "yes"
check "framing: lego decomposes/delivers work in units" \
  "$(has_pattern_ci 'units of work|verified units')" "yes"
check "framing: tracking manages state lifecycle via .local/ docs" \
  "$(has_literal '.local/')" "yes"
check "framing: tracking survives compaction and session restarts" \
  "$(has_pattern_ci 'compaction')" "yes"
check "framing: none-present case explains build's composite purpose" \
  "$(has_pattern_ci 'composite purpose|planned and built|delivery lifecycle')" "yes"
check "framing: none-present case suggests the companion plugins" \
  "$(has_pattern_ci 'suggest')" "yes"

# ---------------------------------------------------------------------------
# 4. Behavior clause 3 / Invariants -- conceptual-only, no standing
#    instructions, no mapping to specific companion skills.
# ---------------------------------------------------------------------------

check "invariant: conceptual framing, not standing instructions" \
  "$(has_pattern_ci 'conceptual')" "yes"
check "invariant: no standing instructions injected" \
  "$(has_pattern_ci 'no standing instruction|never issues? standing instruction|not.{0,15}standing instruction')" "yes"
check "invariant: never maps states to specific companion skills" \
  "$(has_pattern_ci 'never maps|not map(ped)?.{0,30}(specific )?(companion )?skills?')" "yes"

# ---------------------------------------------------------------------------
# 5. Invariant -- never sources or executes companion code (distinct
#    phrasing check from the detection clause above, since the invariant
#    is a standalone contract line, not just a detection-method aside).
# ---------------------------------------------------------------------------

check "invariant: companion code is never executed" \
  "$(has_pattern_ci 'never (execut|source|import)|not (execut|source|import)ed')" "yes"

# ---------------------------------------------------------------------------
# 6. Invariant -- "build" never "deliver" in user-visible text.
# ---------------------------------------------------------------------------

check "invariant: refers to itself as 'build', not 'deliver'" \
  "$(has_literal 'build')" "yes"
check "invariant: no 'deliver' plugin-name reference in user-visible text" \
  "$(printf '%s' "$FLAT_BODY" | grep -qiE '\bdeliver\b' && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# 7. Invariant -- no hooks registered; purely on-demand.
# ---------------------------------------------------------------------------

check "invariant: build plugin registers no hooks" \
  "$(has_pattern_ci 'no hooks|registers no hooks|without (any )?hooks')" "yes"
check "invariant: purely on-demand, nothing fires automatically at session start" \
  "$(has_pattern_ci 'on.demand')" "yes"

# ---------------------------------------------------------------------------
# 8. Outputs / Errors -- conversational only, degrades gracefully.
# ---------------------------------------------------------------------------

check "outputs: no files written / no settings changed" \
  "$(has_pattern_ci 'no files written|writes no files')" "yes"

# ---------------------------------------------------------------------------
# 9. Edge cases.
# ---------------------------------------------------------------------------

check "edge case: no catalog entries treated as no companions present" \
  "$(has_pattern_ci 'none of those catalog entries|no (companion )?catalog entries')" "yes"
check "edge case: listed-but-broken companion still treated as present" \
  "$(has_pattern_ci 'listed but broken|broken.{0,40}still treated as present|never inspects or executes')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
