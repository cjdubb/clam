#!/bin/bash
# Test for Block B03 (marketplace registration, plan 001-sleep-gate).
# Authoritative contract: B03's record in this unit's block map —
#
#   registration across all five repo surfaces a new plugin must appear on —
#   exactly one marketplace entry named `sleep-gate` (no version field),
#   exactly one root README table row carrying `✅ v<version>` matching
#   plugin.json, the plugin name in both
#   issue-template dropdowns in alphabetical position, and a MIGRATION.md
#   provenance section with the heading-count pins re-pinned
#
# The five surfaces asserted below:
#
#   (1) .claude-plugin/marketplace.json — exactly one plugins[] entry named
#       for this plugin, with a source that resolves to a real directory, a
#       non-empty category, no version field (plugin.json is the single
#       source of truth for version), and a real description.
#   (2) README.md (root) Plugins table — exactly one row linking
#       plugins/<name>/, carrying "✅ v<version>" with the version read from
#       plugin.json and a real description. Row position is not asserted:
#       the table carries no ordering rule of its own.
#   (3) .github/ISSUE_TEMPLATE/bug.yml — the plugin in the affected-plugin
#       dropdown, in alphabetical position.
#   (4) .github/ISSUE_TEMPLATE/feature.yml — the same.
#   (5) MIGRATION.md — a provenance section for the plugin, with the
#       heading-count pins in scripts/migration-audit-register.test.sh and
#       scripts/migration-audit-surfaces.test.sh agreeing with MIGRATION.md's
#       actual heading count.
#
# The plugin-local surfaces (plugin.json, hooks/hooks.json, the plugin
# README) are covered by structure.test.sh and readme.test.sh, not here.
#
# Everything is derived from the repo at runtime — the plugin name from this
# script's own directory, the version from plugin.json, the heading count
# from MIGRATION.md — so no assertion rots at the next version bump or
# section addition.
#
# README.md and MIGRATION.md checks read a comment-stripped copy
# (sed '/<!--/,/-->/d'), the same technique
# scripts/migration-audit-register.test.sh uses: contract docblocks in those
# files quote the very strings these checks look for, so without stripping a
# docblock's own prose could satisfy a check before the real content exists.
#
# Non-trivial derivation helpers carry discrimination self-tests (positive
# and negative) so a helper that silently matches nothing cannot be mistaken
# for a correctly-failing assertion.
#
# Hermetic: reads only this repo's tracked files, writes nothing, uses no
# network, and resolves every path from ${BASH_SOURCE[0]} so it is
# cwd-independent.
#
# Run: bash plugins/sleep-gate/scripts/registration.test.sh (non-zero exit on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"

# The plugin's own name, derived from its directory rather than hardcoded.
PLUGIN="$(basename "$PLUGIN_DIR")"

MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
README="$ROOT/README.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
BUG_YML="$ROOT/.github/ISSUE_TEMPLATE/bug.yml"
FEATURE_YML="$ROOT/.github/ISSUE_TEMPLATE/feature.yml"
MIGRATION="$ROOT/MIGRATION.md"
REGISTER_TEST="$ROOT/scripts/migration-audit-register.test.sh"
SURFACES_TEST="$ROOT/scripts/migration-audit-surfaces.test.sh"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# =====================================================================
# 0. Preconditions
# =====================================================================

check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "plugin name derived from the plugin directory is non-empty" \
  "$([ -n "$PLUGIN" ] && echo yes || echo no)" "yes"
check "plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "root README.md exists" \
  "$([ -f "$README" ] && echo yes || echo no)" "yes"
check ".github/ISSUE_TEMPLATE/bug.yml exists" \
  "$([ -f "$BUG_YML" ] && echo yes || echo no)" "yes"
check ".github/ISSUE_TEMPLATE/feature.yml exists" \
  "$([ -f "$FEATURE_YML" ] && echo yes || echo no)" "yes"
check "MIGRATION.md exists" \
  "$([ -f "$MIGRATION" ] && echo yes || echo no)" "yes"

# The version source of truth: read from plugin.json, never hardcoded.
VERSION="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"
check "plugin.json carries a version to compare the README row against" \
  "$([ -n "$VERSION" ] && echo yes || echo no)" "yes"

# The scaffold placeholder marker. A surface still carrying it has not been
# implemented, which is exactly what this suite must catch.
PLACEHOLDER='NotImplemented: B03'

# =====================================================================
# (1) .claude-plugin/marketplace.json
# =====================================================================

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

ENTRY_COUNT="$(jq --arg n "$PLUGIN" '[.plugins[]? | select(.name==$n)] | length' "$MARKETPLACE" 2>/dev/null)"
check "marketplace.json has exactly one plugins[] entry named '$PLUGIN'" \
  "$ENTRY_COUNT" "1"

ENTRY="$(jq -c --arg n "$PLUGIN" 'first(.plugins[]? | select(.name==$n)) // empty' "$MARKETPLACE" 2>/dev/null)"

ENTRY_SOURCE="$(jq -r '.source // empty' <<<"$ENTRY" 2>/dev/null)"
check "$PLUGIN entry has a source" \
  "$([ -n "$ENTRY_SOURCE" ] && echo yes || echo no)" "yes"
check "$PLUGIN entry source is './plugins/$PLUGIN'" \
  "$ENTRY_SOURCE" "./plugins/$PLUGIN"
check "$PLUGIN entry source resolves to a directory that exists in this repo" \
  "$([ -n "$ENTRY_SOURCE" ] && [ -d "$ROOT/${ENTRY_SOURCE#./}" ] && echo yes || echo no)" "yes"

ENTRY_CATEGORY="$(jq -r '.category // empty' <<<"$ENTRY" 2>/dev/null)"
check "$PLUGIN entry has a non-empty category" \
  "$([ -n "$ENTRY_CATEGORY" ] && echo yes || echo no)" "yes"

check "$PLUGIN entry has no version field (plugin.json is the source of truth)" \
  "$(jq -r 'has("version") | not' <<<"$ENTRY" 2>/dev/null)" "true"

ENTRY_DESC="$(jq -r '.description // empty' <<<"$ENTRY" 2>/dev/null)"
check "$PLUGIN entry description is non-empty" \
  "$([ -n "$ENTRY_DESC" ] && echo yes || echo no)" "yes"
check "$PLUGIN entry description is real, not the '$PLACEHOLDER' placeholder" \
  "$(grep -qF "$PLACEHOLDER" <<<"$ENTRY_DESC" && echo placeholder || echo real)" "real"

# The scaffold's own placeholder text states what replaces it: a description
# naming the Bash tool and the completion-wait misuse.
check "$PLUGIN entry description names the Bash tool" \
  "$(grep -qiF 'bash' <<<"$ENTRY_DESC" && echo yes || echo no)" "yes"
check "$PLUGIN entry description names the sleep misuse it gates" \
  "$(grep -qiF 'sleep' <<<"$ENTRY_DESC" && echo yes || echo no)" "yes"

check "no marketplace.json entry anywhere still carries the '$PLACEHOLDER' marker" \
  "$(grep -qF "$PLACEHOLDER" "$MARKETPLACE" && echo present || echo absent)" "absent"

# =====================================================================
# (2) README.md (root) Plugins table
# =====================================================================
# Read from $BODY: the README with its HTML-comment docblocks stripped, so
# a docblock's prose can never satisfy a check meant for real table content.

BODY="$(sed '/<!--/,/-->/d' "$README" 2>/dev/null)"

check "stripped README body is non-empty (stripping did not eat the file)" \
  "$([ -n "$BODY" ] && echo yes || echo no)" "yes"

ROW_LINK="[$PLUGIN](plugins/$PLUGIN/)"
ROW_COUNT="$(grep -cF "$ROW_LINK" <<<"$BODY" || true)"
check "stripped README has exactly one row linking plugins/$PLUGIN/" \
  "$ROW_COUNT" "1"

ROW="$(grep -F "$ROW_LINK" <<<"$BODY" | head -n1)"

check "$PLUGIN row shows the ✅ status marker" \
  "$(grep -qF '✅' <<<"$ROW" && echo yes || echo no)" "yes"
check "$PLUGIN row shows '✅ v$VERSION', the version from plugin.json" \
  "$(grep -qF "✅ v$VERSION" <<<"$ROW" && echo yes || echo no)" "yes"
check "$PLUGIN row is real, not the '$PLACEHOLDER' placeholder" \
  "$(grep -qF "$PLACEHOLDER" <<<"$ROW" && echo placeholder || echo real)" "real"
check "$PLUGIN row description names the Bash tool" \
  "$(grep -qiF 'bash' <<<"$ROW" && echo yes || echo no)" "yes"
check "$PLUGIN row description names the sleep misuse it gates" \
  "$(grep -qiF 'sleep' <<<"$ROW" && echo yes || echo no)" "yes"
check "no README row anywhere still carries the '$PLACEHOLDER' marker" \
  "$(grep -qF "$PLACEHOLDER" <<<"$BODY" && echo present || echo absent)" "absent"

# Row position is deliberately not asserted here. The Plugins table has no
# ordering rule of its own — it is neither alphabetical nor grouped by
# status — so where this row sits is not part of this plugin's contract.
# Whatever position constraints the table carries belong to whichever suite
# imposed them, and are enforced there.

# =====================================================================
# (3) & (4) Issue-template dropdowns
# =====================================================================

# Extracts the option values of the "plugin" dropdown from an issue-template
# YAML, in file order, one per line, unquoted. Line-oriented rather than a
# multi-line regex.
dropdown_options() { # yaml_file
  awk '
    /^[[:space:]]*-[[:space:]]*type:[[:space:]]*dropdown[[:space:]]*$/ { in_d = 1; is_plugin = 0; next }
    in_d && /^[[:space:]]*id:[[:space:]]*plugin[[:space:]]*$/ { is_plugin = 1; next }
    in_d && is_plugin && /^[[:space:]]*options:[[:space:]]*$/ { in_o = 1; next }
    in_o {
      if ($0 ~ /^[[:space:]]*-[[:space:]]/) {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        gsub(/"/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        print line
        next
      }
      exit
    }
  ' "$1"
}

# Discrimination self-tests for dropdown_options, against real repo content:
# a plugin that has been registered for many versions must be found, and a
# name that is not a plugin must not be.
BUG_OPTIONS="$(dropdown_options "$BUG_YML")"
FEATURE_OPTIONS="$(dropdown_options "$FEATURE_YML")"
check "dropdown_options helper: extracts several options from bug.yml (positive)" \
  "$([ "$(grep -c '.' <<<"$BUG_OPTIONS")" -gt 5 ] && echo yes || echo no)" "yes"
check "dropdown_options helper: finds a long-registered plugin, 'debugging' (positive)" \
  "$(grep -qxF 'debugging' <<<"$BUG_OPTIONS" && echo yes || echo no)" "yes"
check "dropdown_options helper: a name that is not an option is not found (negative)" \
  "$(grep -qxF 'not-a-plugin' <<<"$BUG_OPTIONS" && echo found || echo absent)" "absent"

# The catch-all first option is not a plugin name and is deliberately not in
# alphabetical order; the plugin names after it are what must be sorted.
plugin_names_only() { # options_text
  grep -v '^repo-wide / other$' <<<"$1" | grep '.'
}

check_dropdown() { # label options_text
  local label="$1" options="$2" names sorted
  names="$(plugin_names_only "$options")"
  check "$label lists '$PLUGIN'" \
    "$(grep -qxF "$PLUGIN" <<<"$names" && echo yes || echo no)" "yes"
  check "$label lists '$PLUGIN' exactly once" \
    "$(grep -cxF "$PLUGIN" <<<"$names" || true)" "1"
  sorted="$(LC_ALL=C sort <<<"$names")"
  check "$label plugin options are in alphabetical order (pins $PLUGIN's position)" \
    "$([ "$names" = "$sorted" ] && echo sorted || echo unsorted)" "sorted"
}

check_dropdown "bug.yml plugin dropdown" "$BUG_OPTIONS"
check_dropdown "feature.yml plugin dropdown" "$FEATURE_OPTIONS"

# Discrimination self-test for the alphabetical comparison itself, both
# directions, synthetic — so "sorted" can never be a vacuous verdict.
check "alphabetical comparison: a sorted list is reported sorted (positive, synthetic)" \
  "$(list="$(printf 'alpha\nbeta\ngamma\n')"; [ "$list" = "$(LC_ALL=C sort <<<"$list")" ] && echo sorted || echo unsorted)" "sorted"
check "alphabetical comparison: an unsorted list is reported unsorted (negative, synthetic)" \
  "$(list="$(printf 'gamma\nalpha\nbeta\n')"; [ "$list" = "$(LC_ALL=C sort <<<"$list")" ] && echo sorted || echo unsorted)" "unsorted"

# =====================================================================
# (5) MIGRATION.md provenance section and the re-pinned heading counts
# =====================================================================

MIG_BODY="$(sed '/<!--/,/-->/d' "$MIGRATION" 2>/dev/null)"

check "stripped MIGRATION.md body is non-empty (stripping did not eat the file)" \
  "$([ -n "$MIG_BODY" ] && echo yes || echo no)" "yes"

# The provenance section: a "## " heading naming this plugin.
MIG_HEADING_COUNT="$(grep -cE "^## $PLUGIN( |$)" <<<"$MIG_BODY" || true)"
check "stripped MIGRATION.md has exactly one '## $PLUGIN' provenance heading" \
  "$MIG_HEADING_COUNT" "1"

# Its body has substantive prose, not just a heading.
mig_section_body() { # exact_heading_prefix
  awk -v p="$1" '
    index($0, p) == 1 && $0 ~ /^## / { flag = 1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$MIG_BODY"
}

MIG_SECTION="$(mig_section_body "## $PLUGIN")"
check "'## $PLUGIN' provenance section has substantive content" \
  "$([ "$(grep -v '^[[:space:]]*$' <<<"$MIG_SECTION" | wc -c | tr -d ' ')" -gt 40 ] && echo yes || echo no)" "yes"
check "'## $PLUGIN' provenance section is real, not the '$PLACEHOLDER' placeholder" \
  "$(grep -qF "$PLACEHOLDER" <<<"$MIG_SECTION" && echo placeholder || echo real)" "real"

# Discrimination self-test for mig_section_body, both directions, against
# real file content: a heading that exists yields prose, one that does not
# yields nothing.
check "mig_section_body helper: a heading that does not exist yields nothing (negative)" \
  "$([ -z "$(mig_section_body '## no-such-section-heading-here')" ] && echo empty || echo nonempty)" "empty"

# The heading-count pins in the two migration-audit suites must agree with
# MIGRATION.md's actual heading count — that is what "re-pinned to match"
# means, and it is the property that keeps those suites green.
ACTUAL_HEADINGS="$(grep -cE '^## ' <<<"$MIG_BODY" || true)"

pinned_count() { # audit_test_file
  grep -A1 -F "total '## ' heading count in MIGRATION.md is unchanged" "$1" 2>/dev/null \
    | grep -oE '"[0-9]+"[[:space:]]*$' | head -n1 | tr -cd '0-9'
}

# Discrimination self-test for pinned_count: it must return a number from a
# real audit suite, and nothing from a file that carries no such pin.
check "pinned_count helper: reads a number from the register audit suite (positive)" \
  "$([ -n "$(pinned_count "$REGISTER_TEST")" ] && echo yes || echo no)" "yes"
check "pinned_count helper: a file with no pin yields nothing (negative)" \
  "$([ -z "$(pinned_count "$PLUGIN_JSON")" ] && echo empty || echo nonempty)" "empty"

check "scripts/migration-audit-register.test.sh heading pin matches MIGRATION.md's actual count" \
  "$(pinned_count "$REGISTER_TEST")" "$ACTUAL_HEADINGS"
check "scripts/migration-audit-surfaces.test.sh heading pin matches MIGRATION.md's actual count" \
  "$(pinned_count "$SURFACES_TEST")" "$ACTUAL_HEADINGS"

# The two audit suites must actually stay green — run them as subprocesses
# rather than re-deriving their assertions, the same call those suites make
# on each other.
for audit in "$REGISTER_TEST" "$SURFACES_TEST"; do
  audit_name="scripts/$(basename "$audit")"
  if [ -f "$audit" ]; then
    if bash "$audit" >/dev/null 2>&1; then
      check "$audit_name stays green" "yes" "yes"
    else
      check "$audit_name stays green" "no" "yes"
    fi
  else
    check "$audit_name exists to be run" "no" "yes"
  fi
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
