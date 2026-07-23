#!/bin/bash
# Structural/contract tests for B02 paths-skill.
#
# Source of truth: the HTML-comment docblock labeled "Contract: B02
# paths-skill" in plugins/session-data/skills/paths/SKILL.md. This SKILL.md
# is instructional prose Claude follows at runtime, not executable code — so
# this file checks structure and content, never runtime invocation.
#
# Covers plugins/session-data/skills/paths/SKILL.md:
#   - exists; frontmatter parses (opens/closes with a bare '---' line);
#     frontmatter `name` is "paths"; frontmatter `description` is non-empty
#   - skill name "paths" does not repeat/contain the plugin name
#     "session-data" (repo convention, matches plugins/attribution's rule)
#   - no leftover NotImplemented marker anywhere in the raw file EXCEPT the
#     one deliberately-stub `<!-- NotImplemented: B02` line
#   - the actual instructions (the file with its HTML-comment contract
#     docblock stripped out, and further scoped to the content AFTER the
#     first H1 heading — i.e. what Claude actually reads as guidance, not
#     the contract prose describing it) mention every element the contract
#     requires an implementer to surface:
#       * running resolve-paths.sh
#       * the script reference via ${CLAUDE_PLUGIN_ROOT}
#       * a sensitivity warning/caution
#       * that discovered files may contain secrets (e.g. in tool output)
#       * not reading/opening/displaying file contents
#       * requiring the user to explicitly ask first
#       * offering to hand paths off to a fresh agent
#       * handling a non-zero script exit (failure)
#
# Scoping content checks to "after the first H1, docblock stripped" (rather
# than the whole file) matters for red discipline: the contract docblock
# itself already contains most of these terms (it's the spec), so a
# whole-file search would pass vacuously against the unimplemented stub.
# Scoping to what's left after stripping the docblock and heading means
# these checks only pass once an implementer actually writes the
# instructions body — currently that body is just a NotImplemented comment,
# so they correctly fail.
#
# Tests only the public artifacts (frontmatter, instruction prose) — never
# implementation-internal structure, and never runtime invocation of the
# skill (which is instructions for Claude, not a script). Hermetic: reads
# only the repo's own committed files, no network, no mutation,
# cwd-independent (all paths resolved from this script's own location).
#
# Run: bash plugins/session-data/scripts/paths-skill.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
SKILL_MD="$PLUGIN_ROOT/skills/paths/SKILL.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

nonblank() { # string -> "yes"/"no"
  if [[ -n "$(printf '%s' "$1" | tr -d '[:space:]')" ]]; then echo yes; else echo no; fi
}

# Whether $1 (a SKILL.md path) opens with a bare '---' line on line 1 and
# closes the frontmatter block with a second bare '---' line somewhere after
# it. "yes"/"no".
frontmatter_ok() {
  local file="$1"
  [[ -f "$file" ]] || { echo no; return; }
  [[ "$(sed -n '1p' "$file")" == "---" ]] || { echo no; return; }
  local close_line
  close_line=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$file")
  [[ -n "$close_line" ]] && echo yes || echo no
}

# The lines strictly between the first two '---' delimiters of $1.
frontmatter_body() {
  local file="$1"
  local close_line
  close_line=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$file")
  [[ -n "$close_line" && "$close_line" -gt 2 ]] || return 0
  sed -n "2,$((close_line - 1))p" "$file"
}

# frontmatter_field <file> <field> -> the field's value, first match, with
# a wrapping pair of single or double quotes stripped.
frontmatter_field() {
  local file="$1" field="$2"
  frontmatter_body "$file" \
    | sed -n "s/^${field}: *//p" \
    | head -n1 \
    | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
}

# The SKILL.md content Claude actually reads as guidance: the HTML-comment
# contract docblock stripped out, then scoped to everything after the first
# H1 heading (the docblock itself is prose ABOUT the contract, not the
# instructions; the frontmatter and heading aren't instructions either).
skill_instructions_body() {
  local file="$1"
  local stripped
  stripped=$(sed '/<!--/,/-->/d' "$file")
  awk '
    /^# / {found=1; next}
    found {print}
  ' <<<"$stripped"
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "skills/paths/SKILL.md exists" \
  "$([ -f "$SKILL_MD" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 1. SKILL.md frontmatter structure
# ---------------------------------------------------------------------------

fm_ok="$(frontmatter_ok "$SKILL_MD")"
check "SKILL.md frontmatter parses (opens/closes with a bare ---)" "$fm_ok" "yes"

fm_name="$(frontmatter_field "$SKILL_MD" name)"
check "SKILL.md frontmatter name is 'paths'" "$fm_name" "paths"

fm_desc="$(frontmatter_field "$SKILL_MD" description)"
check "SKILL.md frontmatter description is non-empty" \
  "$(nonblank "$fm_desc")" "yes"

# ---------------------------------------------------------------------------
# 2. Skill name convention: "paths", not "session-data-paths"
# ---------------------------------------------------------------------------

check "SKILL.md skill name does not repeat/contain the plugin name 'session-data'" \
  "$(grep -qi 'session-data' <<<"$fm_name" && echo contains || echo ok)" "ok"

# ---------------------------------------------------------------------------
# 3. No leftover NotImplemented marker outside the deliberate stub line
# ---------------------------------------------------------------------------

stray_markers=$(grep -n 'NotImplemented' "$SKILL_MD" 2>/dev/null | grep -v 'NotImplemented: B02')
check "no NotImplemented markers outside the expected '<!-- NotImplemented: B02' stub line" \
  "$([ -z "$stray_markers" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 4. Contract content: the instructions body (docblock stripped, content
#    after the first H1 heading) covers every element the contract requires.
# ---------------------------------------------------------------------------

instructions="$(skill_instructions_body "$SKILL_MD")"

check "instructions mention running resolve-paths.sh" \
  "$(grep -qiF 'resolve-paths.sh' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention the script reference via \${CLAUDE_PLUGIN_ROOT}" \
  "$(grep -qiF 'CLAUDE_PLUGIN_ROOT' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions include a sensitivity warning/caution" \
  "$(grep -qiE 'sensitiv' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention discovered files may contain secrets" \
  "$(grep -qiE 'secret' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions mention not reading/opening/displaying file contents" \
  "$(grep -qiE 'file contents|contents of.*file' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions require the user to explicitly ask before reading a file" \
  "$(grep -qiE 'unless.{0,40}ask|without.{0,40}ask|explicit(ly)?.{0,20}ask|asks?.{0,20}first' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions offer to hand paths off to a fresh agent" \
  "$(grep -qiE 'fresh agent|hand.{0,20}(off.{0,20})?agent' <<<"$instructions" && echo yes || echo no)" "yes"

check "instructions handle a non-zero script exit (failure)" \
  "$(grep -qiE 'non-zero|nonzero|exit.{0,10}(code|status).{0,10}[1-9]' <<<"$instructions" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
