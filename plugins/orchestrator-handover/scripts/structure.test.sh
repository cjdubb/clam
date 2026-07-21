#!/bin/bash
# Composition-level structural test for the orchestrator-handover plugin
# (Block B01, the whole plugin). Checks the shape you can only see once
# every artifact (plugin.json, README.md, skills/create/SKILL.md,
# skills/create/template.md) exists together, and deliberately does NOT
# re-run the fine-grained per-file anchor checks that b01-manifest.test.sh,
# b01-skill.test.sh, and b01-template.test.sh already own.
#
# Composition checks performed here:
#   - every directory under plugins/orchestrator-handover/skills/ contains a
#     SKILL.md (a skills subdir without one is a defect, must FAIL not be
#     silently skipped)
#   - every SKILL.md's frontmatter parses (opens/closes with a bare '---')
#     and carries a non-empty `name` and a non-placeholder `description`
#   - skill `name`s are unique across the plugin, and none of them
#     repeats/contains the plugin name "orchestrator-handover" (repo
#     convention)
#   - plugins/orchestrator-handover/README.md exists
#   - no leftover "NotImplemented" / "Not yet implemented" scaffold marker
#     survives anywhere under plugins/orchestrator-handover/, outside HTML
#     comment docblocks (which legitimately document the scaffolding
#     convention) and outside *.test.sh files (which legitimately reference
#     the marker text as literals in their own checks). Deliberately does
#     NOT sweep for bare "TODO" — "TODO.md" is a real, contractually
#     required output filename referenced throughout SKILL.md, not a
#     placeholder marker.
#
# Every check below iterates the real filesystem (skills/*/, a recursive
# find over plugins/orchestrator-handover/) rather than enumerating known
# skill names, so a future skills/<dir>/ missing its SKILL.md is picked up
# automatically without editing this file. All paths derive from the single
# $ROOT variable, computed from this script's own location, so the test is
# hermetic and cwd-independent.
#
# NOT machine-checked here (engineer live-check at acceptance, not
# machine-verifiable from bash): /reload-plugins actually loading the
# plugin in a live Claude Code session, and /orchestrator-handover:create
# resolving.
#
# Run: bash plugins/orchestrator-handover/scripts/structure.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PLUGIN_ROOT="$ROOT/plugins/orchestrator-handover"
SKILLS_ROOT="$PLUGIN_ROOT/skills"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
README="$PLUGIN_ROOT/README.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

frontmatter_ok() { # file -> "yes"/"no"
  local file="$1"
  [[ -f "$file" ]] || { echo no; return; }
  [[ "$(sed -n '1p' "$file")" == "---" ]] || { echo no; return; }
  local close_line
  close_line=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$file")
  [[ -n "$close_line" ]] && echo yes || echo no
}

frontmatter_body() { # file -> lines strictly between the first two '---'
  local file="$1"
  local close_line
  close_line=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$file")
  [[ -n "$close_line" && "$close_line" -gt 2 ]] || return 0
  sed -n "2,$((close_line - 1))p" "$file"
}

frontmatter_field() { # file field -> value, first match, quotes stripped
  local file="$1" field="$2"
  frontmatter_body "$file" \
    | sed -n "s/^${field}: *//p" \
    | head -n1 \
    | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugins/orchestrator-handover/ exists" \
  "$([ -d "$PLUGIN_ROOT" ] && echo yes || echo no)" "yes"
check "plugins/orchestrator-handover/skills/ exists" \
  "$([ -d "$SKILLS_ROOT" ] && echo yes || echo no)" "yes"
check "plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 1. Every skills/<dir>/ contains a SKILL.md with valid, non-placeholder
#    frontmatter. Iterated dynamically.
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
    check "skills/$base/SKILL.md skill name does not repeat/contain the plugin name 'orchestrator-handover'" \
      "$(grep -qi 'orchestrator-handover' <<<"$name" && echo contains || echo ok)" "ok"
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
# 3. No leftover NotImplemented / "Not yet implemented" scaffold marker
#    anywhere under plugins/orchestrator-handover/, outside HTML comment
#    docblocks and *.test.sh files. Deliberately excludes bare "TODO" —
#    "TODO.md" is a real required output filename, not a placeholder.
# ---------------------------------------------------------------------------

marker_failures=0
while IFS= read -r -d '' f; do
  case "$f" in
    *.test.sh) continue ;;
  esac
  stripped=$(sed '/<!--/,/-->/d' "$f" 2>/dev/null)
  rel="${f#"$ROOT"/}"
  if grep -qiE 'NotImplemented|not yet implemented' <<<"$stripped"; then
    echo "FAIL  no leftover NotImplemented/'not yet implemented' marker in $rel"
    FAILED=1
    marker_failures=$((marker_failures + 1))
  fi
done < <(find "$PLUGIN_ROOT" -type f -print0)

if [[ "$marker_failures" -eq 0 ]]; then
  echo "PASS  no leftover NotImplemented/'not yet implemented' markers outside docblocks and *.test.sh files"
fi

# ---------------------------------------------------------------------------
# 4. README.md exists.
# ---------------------------------------------------------------------------

check "plugins/orchestrator-handover/README.md exists" \
  "$([ -f "$README" ] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
