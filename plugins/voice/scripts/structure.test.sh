#!/bin/bash
# Structural/contract tests for B02 assembly-and-registration (voice).
#
# Covers the plugin-local surfaces:
# plugins/voice/.claude-plugin/plugin.json and the two output styles under
# plugins/voice/output-styles/. The shared repo surfaces (marketplace
# entry, README row, MIGRATION.md section, issue-template dropdowns) are
# covered by registration.test.sh.
#
# Covers plugin.json:
#   - valid JSON; name "voice"; version "0.3.2" exactly; non-empty
#     description naming both the Voice communication spec and its
#     output-style delivery, free of STUB/TODO/NotImplemented markers;
#     .author byte-identical (jq -Sc) to marketplace.json's .owner (single
#     source of truth, never a hand-maintained copy)
#
# Covers output-styles/:
#   - exactly two files: voice.md and voice-no-coding.md
#   - each has YAML frontmatter with name, description, and
#     keep-coding-instructions (true in voice.md, false in
#     voice-no-coding.md); the names differ
#   - the bodies after the frontmatter are byte-identical between the two
#     files (one canonical text, two delivery configurations) and open
#     with the "# Voice (voice plugin)" heading
#
# Also covers the styles-only-plugin invariant (no hooks/ or skills/
# directory) and that every *.test.sh file in this directory is
# executable on disk.
#
# Tests only the public artifacts (JSON fields, file presence/mode,
# frontmatter fields) — never how the implementation produces them.
# Hermetic: reads only the repo's own committed files, no network, no
# mutation, cwd-independent (all paths resolved from this script's own
# location).
#
# Run: bash plugins/voice/scripts/structure.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
STYLES_DIR="$PLUGIN_DIR/output-styles"
STYLE_KEEP="$STYLES_DIR/voice.md"
STYLE_NOCODE="$STYLES_DIR/voice-no-coding.md"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
HOOKS_DIR="$PLUGIN_DIR/hooks"
SKILLS_DIR="$PLUGIN_DIR/skills"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

frontmatter() { # $1 = style file; prints the lines between the two --- fences
  awk 'NR==1 && $0=="---" {flag=1; next} flag && $0=="---" {exit} flag {print}' "$1"
}

body() { # $1 = style file; prints everything after the closing --- fence
  awk 'NR==1 && $0=="---" {flag=1; next} flag==1 && $0=="---" {flag=2; next} flag==2 {print}' "$1"
}

fm_value() { # $1 = style file, $2 = key; prints the value, trimmed
  frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n1 | sed -E 's/[[:space:]]+$//'
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "output-styles/voice.md exists" \
  "$([ -f "$STYLE_KEEP" ] && echo yes || echo no)" "yes"
check "output-styles/voice-no-coding.md exists" \
  "$([ -f "$STYLE_NOCODE" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 1. plugin.json validity and content
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

pj_name=$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .name is 'voice'" "$pj_name" "voice"

# The pin tracks the CURRENT version, so every legitimate bump retargets it.
# Retargeted 0.3.1 -> 0.3.2 by the echo-clause addition.
pj_version=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .version is exactly '0.3.2'" "$pj_version" "0.3.2"

pj_description=$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is non-empty" \
  "$([ -n "$pj_description" ] && echo yes || echo no)" "yes"
check "plugin.json .description names the Voice spec" \
  "$(grep -qi 'voice' <<<"$pj_description" && echo yes || echo no)" "yes"
check "plugin.json .description names output styles" \
  "$(grep -qi 'output style' <<<"$pj_description" && echo yes || echo no)" "yes"
check "plugin.json .description is not a STUB/TODO/NotImplemented placeholder" \
  "$(grep -qiE 'TODO|NotImplemented|\bstub\b' <<<"$pj_description" && echo placeholder || echo ok)" "ok"

pj_author=$(jq -Sc '.author' "$PLUGIN_JSON" 2>/dev/null)
mp_owner=$(jq -Sc '.owner' "$MARKETPLACE" 2>/dev/null)
check "plugin.json .author is byte-identical (jq -Sc) to marketplace.json .owner" \
  "$([[ -n "$pj_author" && "$pj_author" == "$mp_owner" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 2. output-styles/ contains exactly the two style files
# ---------------------------------------------------------------------------

style_files=$(find "$STYLES_DIR" -maxdepth 1 -type f | sed 's|.*/||' | LC_ALL=C sort | tr '\n' ' ' | sed -E 's/ $//')
check "output-styles/ contains exactly voice-no-coding.md and voice.md" \
  "$style_files" "voice-no-coding.md voice.md"

# ---------------------------------------------------------------------------
# 3. Frontmatter: name, description, keep-coding-instructions
# ---------------------------------------------------------------------------

check "voice.md starts with a frontmatter fence" \
  "$(head -n1 "$STYLE_KEEP")" "---"
check "voice-no-coding.md starts with a frontmatter fence" \
  "$(head -n1 "$STYLE_NOCODE")" "---"

keep_name=$(fm_value "$STYLE_KEEP" name)
nocode_name=$(fm_value "$STYLE_NOCODE" name)
check "voice.md frontmatter name is 'Voice'" "$keep_name" "Voice"
check "voice-no-coding.md frontmatter name is 'Voice (no coding instructions)'" \
  "$nocode_name" "Voice (no coding instructions)"
check "the two style names differ" \
  "$([[ "$keep_name" != "$nocode_name" ]] && echo yes || echo no)" "yes"

check "voice.md frontmatter description is non-empty" \
  "$([ -n "$(fm_value "$STYLE_KEEP" description)" ] && echo yes || echo no)" "yes"
check "voice-no-coding.md frontmatter description is non-empty" \
  "$([ -n "$(fm_value "$STYLE_NOCODE" description)" ] && echo yes || echo no)" "yes"

check "voice.md sets keep-coding-instructions: true" \
  "$(fm_value "$STYLE_KEEP" keep-coding-instructions)" "true"
check "voice-no-coding.md sets keep-coding-instructions: false" \
  "$(fm_value "$STYLE_NOCODE" keep-coding-instructions)" "false"

# ---------------------------------------------------------------------------
# 4. Bodies: byte-identical canonical text, opening with the Voice heading
# ---------------------------------------------------------------------------

body "$STYLE_KEEP" > "$TMP/keep.body"
body "$STYLE_NOCODE" > "$TMP/nocode.body"

check "style bodies are byte-identical (one canonical text)" \
  "$(cmp -s "$TMP/keep.body" "$TMP/nocode.body" && echo identical || echo different)" \
  "identical"

first_body_line=$(grep -m1 -v '^[[:space:]]*$' "$TMP/keep.body")
check "canonical body opens with the '# Voice (voice plugin)' heading" \
  "$first_body_line" "# Voice (voice plugin)"

# ---------------------------------------------------------------------------
# 5. Styles-only plugin: no hooks/ or skills/ directory
# ---------------------------------------------------------------------------

check "plugins/voice/hooks/ does not exist (styles-only plugin)" \
  "$([ -d "$HOOKS_DIR" ] && echo exists || echo absent)" "absent"
check "plugins/voice/skills/ does not exist (styles-only plugin)" \
  "$([ -d "$SKILLS_DIR" ] && echo exists || echo absent)" "absent"

# ---------------------------------------------------------------------------
# 6. Executability on disk
# ---------------------------------------------------------------------------

mapfile -t TEST_FILES < <(find "$SCRIPT_DIR" -maxdepth 1 -name '*.test.sh' | sort)
check "at least one *.test.sh file found in plugins/voice/scripts/" \
  "$([ "${#TEST_FILES[@]}" -gt 0 ] && echo yes || echo no)" "yes"

ALL_TESTS_EXEC=yes
for f in "${TEST_FILES[@]}"; do
  if [[ ! -x "$f" ]]; then
    ALL_TESTS_EXEC=no
    echo "      (not executable: $f)"
  fi
done
check "every *.test.sh file under plugins/voice/scripts/ is executable" \
  "$ALL_TESTS_EXEC" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
