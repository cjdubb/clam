#!/bin/bash
# Content test for the B01 build-skill /build:build skill
# (plugins/build/skills/build/SKILL.md), the lifecycle front door that
# routes a session to resume in-flight work or start new work via the
# appropriate companion skill. The skill body is prose, not executable
# code, so this test checks for the presence of the contract's required
# clauses (resume path, new-work path, companion detection, invariants,
# edge cases), not exact wording.
#
# All content checks (except the frontmatter and the global
# NotImplemented check) run against the file with its HTML comment block
# (the contract docblock) AND its YAML frontmatter stripped out first.
# Both already state every required clause verbatim — the docblock as
# the contract itself, the frontmatter description as a summary of it —
# so a check against the raw file could pass on the unimplemented stub
# for the wrong reason. Stripping ensures every clause check can only be
# satisfied by the real skill body that replaces the "NotImplemented:
# B01" marker. Same discipline as
# plugins/build/scripts/b09-context-skill.test.sh.
#
# Run: bash plugins/build/scripts/build-skill.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
SKILL="$PLUGIN_ROOT/skills/build/SKILL.md"

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
  # contract vocabulary ("detect companion plugins", "resume", "route"),
  # so leaving it in would make those checks pass on the unimplemented
  # stub for the wrong reason.
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

# Strip the "**NotImplemented: B01**" marker paragraph too, so the
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

# GATE_BODY keeps the NotImplemented marker paragraph so the gate check
# below can actually detect its presence on the stub and its absence once
# the real body replaces it — stripping it here would make that check
# vacuously pass regardless of implementation state.
GATE_BODY="$(strip_frontmatter "$SKILL" | strip_comments_stdin)"
GATE_FLAT_BODY="$(printf '%s' "$GATE_BODY" | tr '\n' ' ' | tr -s ' ')"

# BODY additionally strips the NotImplemented marker paragraph: the
# marker's own prose must never satisfy a content-clause check.
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

check "frontmatter name is build" \
  "$(grep -m1 '^name:' "$SKILL" 2>/dev/null | sed 's/^name: *//')" "build"

fm_description=$(awk '
  NR==1 && $0=="---" {infm=1; next}
  infm && $0=="---" {exit}
  infm && /^description:/ {sub(/^description: */,""); print; found=1}
  infm && found && /^  / {print}
' "$SKILL" 2>/dev/null)
check "frontmatter description is present and non-empty" \
  "$([[ -n "$(printf '%s' "$fm_description" | tr -d '[:space:]' | tr -d '>-')" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 1. Red/green gate: no NotImplemented marker in the rendered skill body
#    (docblock- and frontmatter-stripped; the marker itself is stripped
#    separately above so its own text can't satisfy other checks).
# ---------------------------------------------------------------------------

check "no NotImplemented marker in skill body" \
  "$(printf '%s' "$GATE_FLAT_BODY" | grep -qiE -- 'NotImplemented' && echo yes || echo no)" "no"

# ---------------------------------------------------------------------------
# 2. Behavior clause 1 -- resume path: detect .local/ in-flight state,
#    direct the session to read it and resume, without parsing
#    companion-specific artifact formats or status vocabularies.
# ---------------------------------------------------------------------------

check "resume: detects .local/TODO.md in-flight state" \
  "$(has_literal '.local/TODO.md')" "yes"
check "resume: detects .local/plans/ entries" \
  "$(has_literal '.local/plans')" "yes"
check "resume: directs the session to read state and resume" \
  "$(has_pattern_ci 'resume')" "yes"
check "resume: reads the recorded state rather than restarting" \
  "$(has_pattern_ci 'read (those|the|its) (files|state)|read the recorded state')" "yes"
check "resume: does not parse companion-specific artifact formats" \
  "$(has_pattern_ci 'does not parse|never parse|without parsing')" "yes"
check "resume: does not interpret companion status vocabularies" \
  "$(has_pattern_ci 'status vocabular|companion.specific (artifact )?(format|status)')" "yes"

# ---------------------------------------------------------------------------
# 3. Behavior clause 2 -- new-work path: ask the user, then route by
#    which companions are present.
# ---------------------------------------------------------------------------

check "new work: asks the user what they want to build" \
  "$(has_pattern_ci 'ask the user what|what they want to build|what you want to build')" "yes"
check "new work: lego present routes to /lego:plan" \
  "$(has_literal '/lego:plan')" "yes"
check "new work: lego absent + landing present routes to /landing:land" \
  "$(has_literal '/landing:land')" "yes"
check "new work: no companions -> conceptual framing / direct implementation" \
  "$(has_pattern_ci 'conceptual')" "yes"
check "new work: no companions -> proceed with direct implementation" \
  "$(has_pattern_ci 'direct implementation')" "yes"

# ---------------------------------------------------------------------------
# 4. Companion detection -- by skill-catalog presence, all three
#    companions, never sourcing or importing companion code.
# ---------------------------------------------------------------------------

check "detection: landing detected via landing:land catalog entry" \
  "$(has_literal 'landing:land')" "yes"
check "detection: lego detected via lego:plan catalog entry" \
  "$(has_literal 'lego:plan')" "yes"
check "detection: tracking detected via its session-start instructions" \
  "$(has_pattern_ci 'tracking.{0,60}session.start|session.start.{0,60}tracking')" "yes"
check "detection: catalog-based only" \
  "$(has_pattern_ci 'catalog.based|skill catalog')" "yes"
check "detection: never sources/imports/executes companion code" \
  "$(has_pattern_ci 'never (source|import|execut)|not (source|import|execut)ed|without (sourcing|importing|executing)')" "yes"

# ---------------------------------------------------------------------------
# 5. Outputs -- conversational routing only; no files written.
# ---------------------------------------------------------------------------

check "outputs: conversational routing only, no files written" \
  "$(has_pattern_ci 'no files (are )?written|writes no files|does not write')" "yes"

# ---------------------------------------------------------------------------
# 6. Invariants.
# ---------------------------------------------------------------------------

check "invariant: on-demand only, never fires automatically" \
  "$(has_pattern_ci 'on.demand')" "yes"
check "invariant: build plugin registers no hooks" \
  "$(has_pattern_ci 'no hooks|registers no hooks|without (any )?hooks')" "yes"
check "invariant: detect-and-degrade, every companion optional" \
  "$(has_pattern_ci 'degrade|optional')" "yes"
check "invariant: works with any subset of companions, including none" \
  "$(has_pattern_ci 'any subset|including none|none present')" "yes"
check "invariant: no companion artifact parsing (existence only)" \
  "$(has_pattern_ci 'existence|never reads the content|does not read the content')" "yes"
check "invariant: references point downward only" \
  "$(has_pattern_ci 'downward')" "yes"
check "invariant: companions never reference build" \
  "$(has_pattern_ci 'never reference build|companions never reference')" "yes"
check "invariant: refers to itself as 'build'" \
  "$(has_literal 'build')" "yes"
check "invariant: no 'deliver' reference in user-visible text" \
  "$(printf '%s' "$FLAT_BODY" | grep -qiE '\bdeliver\b' && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# 7. Edge cases.
# ---------------------------------------------------------------------------

check "edge case: no catalog entries treated as no companions present" \
  "$(has_pattern_ci 'none of those catalog entries|no (companion )?catalog entries')" "yes"
check "edge case: no .local/ directory -> no in-flight state, new-work path" \
  "$(has_pattern_ci 'no \.local/? director|\.local/? (is )?(missing|absent)')" "yes"
check "edge case: .local/ exists but no TODO.md -> new-work path" \
  "$(has_pattern_ci 'only system files|no TODO\.md|without (a )?TODO\.md')" "yes"
check "edge case: TODO.md present but plans/ empty -> resume path" \
  "$(has_pattern_ci 'plans/? (is )?empty|empty plans')" "yes"
check "edge case: broken-plugin handling owned by the plugin system" \
  "$(has_pattern_ci 'plugin system owns|broken.plugin handling')" "yes"
check "edge case: mid-session invocation re-routes without discarding work" \
  "$(has_pattern_ci 'mid.session|does not restart|never discard|without (restarting|discarding)')" "yes"
check "edge case: both lego and landing present -> lego first for new work" \
  "$(has_pattern_ci 'both lego and landing|lego (governs|first)')" "yes"
check "edge case: tracking present alongside lego, no duplication of its state reading" \
  "$(has_pattern_ci 'tracking.{0,80}(hook|state lifecycle)|not duplicat|without duplicating')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
