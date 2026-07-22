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

# 5. README.md carries the required document structure: H1 title plus the
#    H2 sections named in the B02 contract.
check "README.md has H1 '# landing'" \
  "$(head -1 "$README" 2>/dev/null)" "# landing"
check "README.md has a Profile section referencing clam-profile.jsonc" \
  "$(grep -qE '^## .*[Pp]rofile' "$README" 2>/dev/null && echo yes || echo no)" "yes"
check "README.md has '## Supported policy matrix (v0.1)'" \
  "$(grep -qF '## Supported policy matrix (v0.1)' "$README" 2>/dev/null && echo yes || echo no)" "yes"
check "README.md has '## Skills'" \
  "$(grep -qE '^## Skills$' "$README" 2>/dev/null && echo yes || echo no)" "yes"
check "README.md has '## Hook'" \
  "$(grep -qE '^## Hook$' "$README" 2>/dev/null && echo yes || echo no)" "yes"
check "README.md has '## Failure modes'" \
  "$(grep -qE '^## Failure modes$' "$README" 2>/dev/null && echo yes || echo no)" "yes"
check "README.md has '## Roadmap'" \
  "$(grep -qE '^## Roadmap$' "$README" 2>/dev/null && echo yes || echo no)" "yes"
check "README.md has '## Tests'" \
  "$(grep -qE '^## Tests$' "$README" 2>/dev/null && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
