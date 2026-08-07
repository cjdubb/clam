#!/bin/bash
# Structural test for the B02 documentation surfaces of the landing plugin
# (init/SKILL.md, land/SKILL.md, plugin.json, README.md). These are
# markdown instructions and metadata, not executable code, so this test
# checks structural properties rather than behavior: each file references
# the new .claude/clam-profile.jsonc format, none references the legacy
# .claude/clam-profile.md path, README.md documents JSONC (not YAML
# frontmatter), and README.md carries the required section headings.
# Run: bash plugins/landing/scripts/landing-docs.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

INIT_SKILL="$PLUGIN_DIR/skills/init/SKILL.md"
LAND_SKILL="$PLUGIN_DIR/skills/land/SKILL.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
README="$PLUGIN_DIR/README.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

has_literal() { # file needle
  grep -qF -- "$2" "$1" 2>/dev/null && echo yes || echo no
}

has_pattern_ci() { # file extended-regex
  grep -qiE -- "$2" "$1" 2>/dev/null && echo yes || echo no
}

# 1. init/SKILL.md references the new JSONC profile path, not the legacy one.
check "init/SKILL.md references clam-profile.jsonc" \
  "$(has_literal "$INIT_SKILL" '.claude/clam-profile.jsonc')" "yes"
check "init/SKILL.md does not reference legacy clam-profile.md" \
  "$(has_literal "$INIT_SKILL" '.claude/clam-profile.md')" "no"

# 2. land/SKILL.md references the new JSONC profile path, not the legacy one.
check "land/SKILL.md references clam-profile.jsonc" \
  "$(has_literal "$LAND_SKILL" '.claude/clam-profile.jsonc')" "yes"
check "land/SKILL.md does not reference legacy clam-profile.md" \
  "$(has_literal "$LAND_SKILL" '.claude/clam-profile.md')" "no"

# 3. plugin.json's description references the JSONC format and is valid JSON.
check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "plugin.json description references .jsonc" \
  "$(has_literal "$PLUGIN_JSON" '.jsonc')" "yes"
check "plugin.json does not reference legacy clam-profile.md" \
  "$(has_literal "$PLUGIN_JSON" '.claude/clam-profile.md')" "no"

# 4. README.md documents the JSONC format, not YAML frontmatter, and does
#    not reference the legacy profile path.
check "README.md references .jsonc format" \
  "$(has_literal "$README" '.jsonc')" "yes"
check "README.md does not mention YAML frontmatter" \
  "$(has_pattern_ci "$README" 'frontmatter|\byaml\b')" "no"
check "README.md does not reference legacy clam-profile.md" \
  "$(has_literal "$README" '.claude/clam-profile.md')" "no"

# 5. README.md carries the required document structure: H1 title, the six
#    required H2 sections from the B09 template (in order), and the
#    preserved plugin-specific sections positioned in the optional slot
#    between '## Commands' and '## Relationships to other plugins'.
line_of_exact() { # file exact-line-text
  grep -nxF -- "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1
}

check "README.md has H1 '# landing'" \
  "$(head -1 "$README" 2>/dev/null)" "# landing"
check "README.md documents the clam-profile.jsonc format" \
  "$(has_literal "$README" '.claude/clam-profile.jsonc')" "yes"

REQUIRED_H2_ORDER=$'Getting started\nWhat to expect\nCommon workflows\nCommands\nRelationships to other plugins\nUninstalling'
ACTUAL_H2_ORDER="$(grep -E '^## (Getting started|What to expect|Common workflows|Commands|Relationships to other plugins|Uninstalling)$' "$README" 2>/dev/null | sed 's/^## //')"
check "README.md has the required H2 sections, in order" \
  "$ACTUAL_H2_ORDER" "$REQUIRED_H2_ORDER"

COMMANDS_LINE="$(line_of_exact "$README" '## Commands')"
RELATIONSHIPS_LINE="$(line_of_exact "$README" '## Relationships to other plugins')"

between_commands_and_relationships() { # heading-exact-line-text
  local h="$(line_of_exact "$README" "$1")"
  if [[ -n "$h" && -n "$COMMANDS_LINE" && -n "$RELATIONSHIPS_LINE" \
        && "$h" -gt "$COMMANDS_LINE" && "$h" -lt "$RELATIONSHIPS_LINE" ]]; then
    echo yes
  else
    echo no
  fi
}

check "README.md has '## Supported policy matrix (v0.1)' between Commands and Relationships" \
  "$(between_commands_and_relationships '## Supported policy matrix (v0.1)')" "yes"
check "README.md has '## Failure modes' between Commands and Relationships" \
  "$(between_commands_and_relationships '## Failure modes')" "yes"
check "README.md has '## Roadmap' between Commands and Relationships" \
  "$(between_commands_and_relationships '## Roadmap')" "yes"
check "README.md has '## Tests' between Commands and Relationships" \
  "$(between_commands_and_relationships '## Tests')" "yes"

# 6. B04: landing becomes a higher-order plugin over forge plugins.
#    land/SKILL.md and README.md content checks below run against the
#    files with HTML comment blocks (the contract docblocks) stripped
#    out first. The B04 docblocks already describe every required
#    change in detail -- including the build-plugin phrases being
#    removed and the forge-plugin phrases being added -- so a raw-file
#    check could pass on the unimplemented stub for the wrong reason
#    (the docblock already says it), or never be able to fail for the
#    "old text is gone" checks (the docblock's own explanatory prose
#    keeps referencing "the build plugin" as part of describing what to
#    remove, even once removal is done). Stripping ensures every check
#    is answered by the actual skill instructions / README prose, never
#    by the docblock commentary describing them. Note: unlike the
#    forge-interface spec, land/SKILL.md and README.md do NOT ban the
#    word "tracking" -- landing's cooperative, non-delegating
#    relationship with the tracking plugin (.local/TODO.md state
#    updates) is unrelated to B04 and stays; only the build
#    delegation-seam content is in scope here.
strip_comments() { # file
  awk '/<!--/{c=1} !c{print} /-->/{c=0}' "$1" 2>/dev/null
}

LAND_BODY="$(strip_comments "$LAND_SKILL")"
README_BODY="$(strip_comments "$README")"

body_has_literal() { # body needle
  printf '%s' "$1" | grep -qF -- "$2" && echo yes || echo no
}
body_has_pattern_ci() { # body extended-regex
  printf '%s' "$1" | grep -qiE -- "$2" && echo yes || echo no
}

# near_pattern: true only when "needle" appears within +/- window lines of
# the first line matching "anchor". Plain literal/pattern presence checks
# for merge.target, .local/PLAN.md, and "built-in" are USELESS here on
# their own -- all three strings already appear in the pre-B04 prose for
# unrelated reasons (the profile-key table, the old build-delegation
# step's own body-sourcing note, the old build-delegation step's own
# fallback clause), so a bare presence check would pass on the
# unimplemented file today and could never go red for missing B04 work.
# Anchoring each to proximity of "forge plugin" -- a phrase absent from
# both files until the forge-delegation content is actually written --
# makes the check answer the real question: is this string part of the
# NEW forge-delegation description, not just present somewhere else in
# the document.
near_pattern() { # body anchor-pattern needle-pattern window
  local body="$1" anchor="$2" needle="$3" window="${4:-10}"
  local line total start end window_text
  line="$(printf '%s\n' "$body" | grep -niE -- "$anchor" | head -1 | cut -d: -f1)"
  [[ -z "$line" ]] && { echo no; return; }
  total="$(printf '%s\n' "$body" | wc -l)"
  start=$(( line - window )); [[ $start -lt 1 ]] && start=1
  end=$(( line + window )); [[ $end -gt $total ]] && end=$total
  window_text="$(printf '%s\n' "$body" | sed -n "${start},${end}p")"
  printf '%s' "$window_text" | grep -qiE -- "$needle" && echo yes || echo no
}

check "land/SKILL.md: old build-delegation text is gone" \
  "$(body_has_literal "$LAND_BODY" 'providing a create-pr skill')" "no"
check "land/SKILL.md: no stray reference to the build plugin" \
  "$(body_has_pattern_ci "$LAND_BODY" '\bbuild\b')" "no"
check "land/SKILL.md: forge plugin delegation is documented" \
  "$(body_has_pattern_ci "$LAND_BODY" 'forge plugin')" "yes"
check "land/SKILL.md: forge delegation passes the base branch via merge.target" \
  "$(near_pattern "$LAND_BODY" 'forge plugin' 'merge\.target' 15)" "yes"
check "land/SKILL.md: passes the default body template" \
  "$(body_has_pattern_ci "$LAND_BODY" 'pr-body-template')" "yes"
check "land/SKILL.md: forge delegation content context includes PLAN.md and TODO.md" \
  "$(near_pattern "$LAND_BODY" 'forge plugin' '\.local/PLAN\.md' 15)" "yes"
check "land/SKILL.md: built-in path kept as the no-forge-plugin fallback" \
  "$(near_pattern "$LAND_BODY" 'forge plugin' 'built-in' 15)" "yes"
check "land/SKILL.md: fallback covers an unavailable forge skill" \
  "$(body_has_pattern_ci "$LAND_BODY" 'unavailable')" "yes"
check "land/SKILL.md: built-in path uses flowing-paragraph formatting" \
  "$(body_has_pattern_ci "$LAND_BODY" 'flowing')" "yes"
check "land/SKILL.md: built-in path is never hard-wrapped" \
  "$(body_has_pattern_ci "$LAND_BODY" 'hard-wrap')" "yes"

# 7. B04 (README leg): the workflow walkthrough documents forge
#    delegation with the built-in path as fallback, the Roadmap item
#    proposing build delegation is removed, the Relationships build
#    bullet loses its delegation-seam sentence, and a forge-plugins
#    bullet plus pointers to the spec/template are added.
check "README.md: old build-delegation text is gone" \
  "$(body_has_literal "$README_BODY" 'providing a create-pr skill')" "no"
check "README.md: Roadmap no longer proposes build plugin delegation" \
  "$(body_has_pattern_ci "$README_BODY" 'build plugin delegation')" "no"
check "README.md: Relationships no longer documents a build delegation seam" \
  "$(body_has_pattern_ci "$README_BODY" 'delegation seam to a')" "no"
check "README.md: documents forge plugin delegation" \
  "$(body_has_pattern_ci "$README_BODY" 'forge plugin')" "yes"
check "README.md: points at docs/forge-interface.md" \
  "$(body_has_literal "$README_BODY" 'docs/forge-interface.md')" "yes"
check "README.md: points at templates/pr-body-template.md" \
  "$(body_has_pattern_ci "$README_BODY" 'pr-body-template')" "yes"
check "README.md: github-pr path names the flowing-paragraph convention" \
  "$(body_has_pattern_ci "$README_BODY" 'flowing')" "yes"
check "README.md: github-pr path names the built-in path as the forge-delegation fallback" \
  "$(near_pattern "$README_BODY" 'forge plugin' 'built-in' 10)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
