#!/bin/bash
# Composition-level integration test for Block B05 worktrees-plugin. Source
# of truth: the HTML-comment docblock labeled "Contract: B05 worktrees-plugin
# (composition)" in plugins/worktrees/README.md. B05 has no stub file of its
# own — it is the assembled plugin formed by B01 (manifest), B02 (usage
# skill), B03 (per-worker skill), and B04 (marketplace/README/MIGRATION
# registration), all already Implemented and independently tested by
# b01-manifest.test.sh through b04-registration.test.sh. This file checks
# only composition-level structure — the shape you can only see once every
# child artifact exists together — and deliberately does NOT re-run the
# fine-grained per-section anchor checks those four files already own.
#
# Composition checks performed here:
#   - every directory under plugins/worktrees/skills/ contains a SKILL.md
#     (a skills subdir without one is a defect, per the contract's Edge
#     cases clause — it must FAIL, not be silently skipped)
#   - every SKILL.md's frontmatter parses (opens and closes with a bare
#     '---' line) and carries a non-empty `name` and a non-placeholder
#     `description` (no TODO/NotImplemented marker)
#   - skill `name`s are unique across the plugin, and none of them
#     repeats/contains the plugin name "worktrees" (repo convention)
#   - the marketplace.json worktrees entry has no version field (plugin.json
#     is the single source of truth for version), and that entry appears
#     exactly once
#   - no TODO(B0N) or NotImplemented marker survives anywhere under
#     plugins/worktrees/, outside HTML comment docblocks (which legitimately
#     document the convention) and outside *.test.sh files (which
#     legitimately reference the marker text as literals in their own
#     checks)
#   - plugins/worktrees/README.md exists
#
# Every check below iterates the real filesystem (skills/*/, a recursive
# find over plugins/worktrees/) rather than enumerating known skill names,
# so a future third skill — or a future skills/<dir>/ missing its SKILL.md —
# is picked up automatically without editing this file. All paths derive
# from the single $ROOT variable, computed from this script's own location,
# so the test is hermetic and cwd-independent; nothing here reads an
# environment variable at run time.
#
# NOT machine-checked here (both documented in the contract's Outputs/
# Behavior clauses, both deliberately out of scope for this file):
#   - /reload-plugins actually loading the plugin in a live Claude Code
#     session, and /worktrees:usage / /worktrees:per-worker resolving —
#     the contract itself calls this an engineer live-check at acceptance,
#     not machine-verifiable from bash, and this script agrees.
#   - "the repo test suite ... is green" as a self-check performed by this
#     file — b01–b04 already own verifying themselves, and this file living
#     under the same `find plugins -name '*.test.sh'` sweep the contract
#     describes means it would otherwise need to invoke itself. That
#     sweep — running every *.test.sh across the repo, this file included —
#     is how the "repo test suite is green" clause actually gets satisfied,
#     one directory up from here (the lego dispatch flow / CI), not by this
#     file re-asserting its own success.
#
# Run: bash plugins/worktrees/scripts/structure.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PLUGIN_ROOT="$ROOT/plugins/worktrees"
SKILLS_ROOT="$PLUGIN_ROOT/skills"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
README="$PLUGIN_ROOT/README.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
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

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugins/worktrees/ exists" \
  "$([ -d "$PLUGIN_ROOT" ] && echo yes || echo no)" "yes"
check "plugins/worktrees/skills/ exists" \
  "$([ -d "$SKILLS_ROOT" ] && echo yes || echo no)" "yes"
check "plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 1. Every skills/<dir>/ contains a SKILL.md with valid, non-placeholder
#    frontmatter. Iterated dynamically so a future skills/<dir>/ (added or
#    missing its SKILL.md) is picked up without touching this file.
# ---------------------------------------------------------------------------

shopt -s nullglob
skill_dirs=("$SKILLS_ROOT"/*/)
skill_names=()

check "skills/ contains at least one skill directory" \
  "$([ ${#skill_dirs[@]} -gt 0 ] && echo yes || echo no)" "yes"

for dir in "${skill_dirs[@]}"; do
  base="$(basename "$dir")"
  skill_md="${dir}SKILL.md"

  if [[ ! -f "$skill_md" ]]; then
    check "skills/$base/ contains SKILL.md" "no" "yes"
    continue
  fi
  check "skills/$base/ contains SKILL.md" "yes" "yes"

  fm_ok="$(frontmatter_ok "$skill_md")"
  check "skills/$base/SKILL.md frontmatter parses (opens/closes with a bare ---)" \
    "$fm_ok" "yes"
  if [[ "$fm_ok" != "yes" ]]; then
    continue
  fi

  name="$(frontmatter_field "$skill_md" name)"
  desc="$(frontmatter_field "$skill_md" description)"

  check "skills/$base/SKILL.md frontmatter has a non-empty name" \
    "$([ -n "$name" ] && echo yes || echo no)" "yes"
  check "skills/$base/SKILL.md frontmatter has a non-empty description" \
    "$([ -n "$desc" ] && echo yes || echo no)" "yes"
  check "skills/$base/SKILL.md description is not a TODO placeholder" \
    "$(grep -qi 'todo' <<<"$desc" && echo placeholder || echo ok)" "ok"
  check "skills/$base/SKILL.md description is not a NotImplemented placeholder" \
    "$(grep -qi 'notimplemented' <<<"$desc" && echo placeholder || echo ok)" "ok"

  if [[ -n "$name" ]]; then
    skill_names+=("$name")
    check "skills/$base/SKILL.md skill name does not repeat/contain the plugin name 'worktrees'" \
      "$(grep -qi 'worktrees' <<<"$name" && echo contains || echo ok)" "ok"
  fi
done

# ---------------------------------------------------------------------------
# 2. Skill names are unique across the plugin.
# ---------------------------------------------------------------------------

if [[ ${#skill_names[@]} -gt 0 ]]; then
  unique_count=$(printf '%s\n' "${skill_names[@]}" | sort -u | wc -l)
  check "skill names are unique across the plugin" \
    "$([ "$unique_count" -eq "${#skill_names[@]}" ] && echo yes || echo no)" "yes"
fi

# ---------------------------------------------------------------------------
# 3. marketplace.json worktrees entry has no version field (plugin.json is
#    the single source of truth); the entry appears exactly once.
# ---------------------------------------------------------------------------

plugin_version=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
entry_count=$(jq -r '[.plugins[]? | select(.name=="worktrees")] | length' "$MARKETPLACE" 2>/dev/null)
has_version=$(jq -r '.plugins[]? | select(.name=="worktrees") | has("version")' "$MARKETPLACE" 2>/dev/null)

check "plugin.json .version is non-empty" \
  "$([ -n "$plugin_version" ] && echo yes || echo no)" "yes"
check "marketplace.json lists the worktrees plugin exactly once" \
  "$entry_count" "1"
check "marketplace.json worktrees entry has no version field (plugin.json is source of truth)" \
  "$has_version" "false"

# ---------------------------------------------------------------------------
# 4. No leftover TODO(B0N) / NotImplemented markers anywhere under
#    plugins/worktrees/, outside HTML comment docblocks and *.test.sh files.
# ---------------------------------------------------------------------------

marker_failures=0
while IFS= read -r -d '' f; do
  case "$f" in
    *.test.sh) continue ;;
  esac
  stripped=$(sed '/<!--/,/-->/d' "$f" 2>/dev/null)
  rel="${f#"$ROOT"/}"
  if grep -qE 'TODO\(B0[0-9]+\)' <<<"$stripped"; then
    echo "FAIL  no leftover TODO(B0N) marker in $rel"
    FAILED=1
    marker_failures=$((marker_failures + 1))
  fi
  if grep -qi 'NotImplemented' <<<"$stripped"; then
    echo "FAIL  no leftover NotImplemented marker in $rel"
    FAILED=1
    marker_failures=$((marker_failures + 1))
  fi
done < <(find "$PLUGIN_ROOT" -type f -print0)

if [[ "$marker_failures" -eq 0 ]]; then
  echo "PASS  no leftover TODO(B0N)/NotImplemented markers outside docblocks and *.test.sh files"
fi

# ---------------------------------------------------------------------------
# 5. README.md exists.
# ---------------------------------------------------------------------------

check "plugins/worktrees/README.md exists" \
  "$([ -f "$README" ] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
