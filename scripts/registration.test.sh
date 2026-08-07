#!/bin/bash
# Structural/content tests for Block B08 (registration, plan
# 001-fix-pr-line-lengths).
#
# Source of truth: the HTML-comment docblock "Contract: B08 registration
# (plan 001-fix-pr-line-lengths)" near the bottom of the root README.md.
# Asserts on the four surfaces the contract names as this block's outputs:
#
#   (1) .claude-plugin/marketplace.json — exactly one forge-github entry
#       (source "./plugins/forge-github", no version field, description
#       naming both skills) — landed at scaffold for directory/entry
#       parity, so GREEN today. The build entry's description must drop
#       its PR-description-sync claim — RED today (still present).
#   (2) README.md Plugins table — exactly one forge-github row before the
#       debugging row (landed at scaffold, GREEN), every marketplace
#       plugin's row version agreeing with its plugin.json (dynamic, no
#       hardcoded versions), and the build row no longer mentioning
#       /build:sync-pr — RED today (still present).
#   (3) .github/ISSUE_TEMPLATE/{bug,feature}.yml — forge-github present in
#       both id=plugin dropdowns, alphabetical order (landed at scaffold,
#       GREEN; regression guard here).
#   (4) .claude/settings.local.json — CONDITIONAL per orchestrator ruling:
#       untracked/machine-local, absent in this worktree and in CI. If
#       present, forge-github@clam must be enabled; if absent, the check
#       passes with a note. Never required to exist.
#
# Anti-vacuous discipline: the B08 contract text lives INSIDE README.md
# itself as an HTML comment block, quoting the very strings this suite
# checks for (e.g. "/build:sync-pr", "forge-github"). A raw-text search
# would find the docblock's own prose and pass vacuously. Every README
# check below therefore runs against a comment-stripped copy (strip_
# comments: an awk state machine that correctly closes a same-line
# comment, unlike a bare `sed '/<!--/,/-->/d'` which would swallow real
# content between two same-line comments). marketplace.json and the YAML
# templates are read structurally (jq / awk field extraction), never via
# bare grep over the raw file.
#
# Hermetic: reads only the repo's own committed files (plus the untracked,
# conditionally-present settings.local.json), no network, no mutation,
# cwd-independent (all paths resolved from this script's own location).
#
# Run: bash scripts/registration.test.sh (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
README="$ROOT/README.md"
BUG_TEMPLATE="$ROOT/.github/ISSUE_TEMPLATE/bug.yml"
FEATURE_TEMPLATE="$ROOT/.github/ISSUE_TEMPLATE/feature.yml"
SETTINGS_LOCAL="$ROOT/.claude/settings.local.json"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Removes HTML comments from a file's content, line by line, correctly
# closing a comment that opens and closes on the same line. Mirrors
# plugins/updates/scripts/registration.test.sh's strip_comments verbatim.
strip_comments() { # file -> stdout
  awk '
    {
      line = $0
      out = ""
      while (length(line) > 0) {
        if (in_comment) {
          idx = index(line, "-->")
          if (idx > 0) { line = substr(line, idx + 3); in_comment = 0 }
          else { line = "" }
        } else {
          idx = index(line, "<!--")
          if (idx > 0) { out = out substr(line, 1, idx - 1); line = substr(line, idx + 4); in_comment = 1 }
          else { out = out line; line = "" }
        }
      }
      print out
    }
  ' "$1"
}

# Extracts the body of a level-2 markdown section from already-stripped
# content: everything after a line matching $2 exactly, up to (not
# including) the next "## " heading or end of content.
section_body() { # stripped_content heading_line_exact
  awk -v heading="$2" '
    $0 == heading {found=1; next}
    found && /^## / {exit}
    found {print}
  ' <<< "$1"
}

# Extracts a table row's plugin-name key: the linked form
# "| [name](plugins/..." or the bare "planned" form "| name | ...". Prints
# nothing if the row matches neither shape.
row_key() { # row_line -> stdout
  local row="$1"
  if [[ "$row" =~ ^\|\ \[([A-Za-z0-9_-]+)\]\(plugins/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "$row" =~ ^\|\ ([A-Za-z0-9_-]+)\ \| ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# Extracts the `options:` list under the dropdown body item whose `id:`
# equals the given field id. Mirrors scripts/issue-template-lint.sh's
# get_dropdown_options verbatim (structured YAML-shape read, not a bare
# grep) so this suite doesn't drift from B05's parsing behavior.
get_dropdown_options() { # file field_id -> one option per line
  awk -v target="$2" '
    /^  - type: dropdown/ { in_block = 1; block_id = ""; in_options = 0; next }
    /^  - / { in_block = 0; in_options = 0; next }
    in_block && /^    id: / {
      id = $0
      sub(/^    id: */, "", id)
      gsub(/^["'"'"']|["'"'"']$/, "", id)
      block_id = id
      next
    }
    in_block && block_id == target && /^      options:/ { in_options = 1; next }
    in_options {
      if ($0 ~ /^        - /) {
        val = $0
        sub(/^        - */, "", val)
        gsub(/^["'"'"']|["'"'"']$/, "", val)
        print val
        next
      } else {
        in_options = 0
      }
    }
  ' "$1"
}

# --- 0. Preconditions ---
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "README.md exists" \
  "$([ -f "$README" ] && echo yes || echo no)" "yes"
check "bug.yml exists" \
  "$([ -f "$BUG_TEMPLATE" ] && echo yes || echo no)" "yes"
check "feature.yml exists" \
  "$([ -f "$FEATURE_TEMPLATE" ] && echo yes || echo no)" "yes"

# =====================================================================
# (1) marketplace.json
# =====================================================================

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

check "marketplace.json has no duplicate plugin names" \
  "$(jq '(.plugins | length) == (.plugins | map(.name) | unique | length)' "$MARKETPLACE" 2>/dev/null)" "true"

# --- 1a. forge-github entry: presence, shape, content (GREEN: landed at
#         scaffold for directory/entry parity). ---

FORGE_COUNT="$(jq '[.plugins[]? | select(.name=="forge-github")] | length' "$MARKETPLACE" 2>/dev/null)"
check "marketplace.json has exactly one plugins[] entry named 'forge-github'" \
  "$FORGE_COUNT" "1"

FORGE_ENTRY="$(jq -c '.plugins[]? | select(.name=="forge-github")' "$MARKETPLACE" 2>/dev/null)"

check "forge-github entry source is './plugins/forge-github'" \
  "$(jq -r '.source' <<<"$FORGE_ENTRY" 2>/dev/null)" \
  "./plugins/forge-github"

check "forge-github entry has no version field (plugin.json is source of truth)" \
  "$(jq -r 'has("version")' <<<"$FORGE_ENTRY" 2>/dev/null)" "false"

FORGE_MP_DESC="$(jq -r '.description // empty' <<<"$FORGE_ENTRY" 2>/dev/null)"
check "forge-github entry description is non-empty" \
  "$([ -n "$FORGE_MP_DESC" ] && echo yes || echo no)" "yes"
check "forge-github entry description names /forge-github:create-pr" \
  "$(grep -qF '/forge-github:create-pr' <<<"$FORGE_MP_DESC" && echo yes || echo no)" "yes"
check "forge-github entry description names /forge-github:sync-pr" \
  "$(grep -qF '/forge-github:sync-pr' <<<"$FORGE_MP_DESC" && echo yes || echo no)" "yes"

# --- 1b. build entry description must drop its PR-description-sync claim
#         (RED today: the claim is still present). ---

BUILD_MP_ENTRY="$(jq -c '.plugins[]? | select(.name=="build")' "$MARKETPLACE" 2>/dev/null)"
BUILD_MP_DESC="$(jq -r '.description // empty' <<<"$BUILD_MP_ENTRY" 2>/dev/null)"
check "build entry description no longer claims PR description sync" \
  "$(grep -qi 'pr description sync' <<<"$BUILD_MP_DESC" && echo present || echo absent)" \
  "absent"
check "build entry description no longer mentions sync-pr" \
  "$(grep -qi 'sync-pr' <<<"$BUILD_MP_DESC" && echo present || echo absent)" \
  "absent"

# --- 1c. landing and lego descriptions must not contradict the
#         post-refactor behavior (only updated if they do; regression
#         guard that they don't claim PR-sync ownership either). ---

for name in landing lego; do
  entry_desc="$(jq -r --arg n "$name" '.plugins[]? | select(.name==$n) | .description // empty' "$MARKETPLACE" 2>/dev/null)"
  check "$name entry description does not claim /build:sync-pr" \
    "$(grep -qF '/build:sync-pr' <<<"$entry_desc" && echo present || echo absent)" \
    "absent"
done

# =====================================================================
# (2) README.md Plugins table
# =====================================================================
# All checks below run against $DATA_ROWS: the "## Plugins" section body
# with HTML comments stripped (so the contract docblock's own quoted
# strings can never satisfy a check), filtered down to real table rows
# (header and separator excluded).

readme_stripped="$(strip_comments "$README")"
plugins_section="$(section_body "$readme_stripped" "## Plugins")"
DATA_ROWS="$(grep -E '^\| ' <<< "$plugins_section" | grep -v '^| Plugin ' | grep -v '^|-')"

check "found the Plugins table (at least one data row after stripping comments)" \
  "$([ -n "$DATA_ROWS" ] && echo yes || echo no)" "yes"

# --- 2a. forge-github row: presence and shape (GREEN: landed at
#         scaffold). ---

FORGE_ROW_COUNT="$(grep -cF '[forge-github](plugins/forge-github/)' <<< "$DATA_ROWS" || true)"
check "forge-github: table has exactly one row" "$FORGE_ROW_COUNT" "1"

forge_row="$(grep -F '[forge-github](plugins/forge-github/)' <<< "$DATA_ROWS" | head -n1)"
check "forge-github row names /forge-github:create-pr" \
  "$(grep -qF '/forge-github:create-pr' <<< "$forge_row" && echo yes || echo no)" "yes"
check "forge-github row names /forge-github:sync-pr" \
  "$(grep -qF '/forge-github:sync-pr' <<< "$forge_row" && echo yes || echo no)" "yes"

# --- 2b. Every marketplace-listed plugin has exactly one row, version
#         agreeing with its own plugin.json (dynamically read, never
#         hardcoded). This loop covers the invariant "every marketplace
#         plugin has exactly one table row whose version agrees with its
#         plugin.json" across all plugins, forge-github included. ---

mapfile -t MP_NAMES < <(jq -r '.plugins[].name' "$MARKETPLACE" 2>/dev/null | sort)

for name in "${MP_NAMES[@]}"; do
  plugin_json="$ROOT/plugins/$name/.claude-plugin/plugin.json"
  expected_version="$(jq -r '.version // empty' "$plugin_json" 2>/dev/null)"

  row_count="$(grep -cF "[$name](plugins/$name/)" <<< "$DATA_ROWS" || true)"
  check "$name: table has exactly one row" "$row_count" "1"

  row="$(grep -F "[$name](plugins/$name/)" <<< "$DATA_ROWS" | head -n1)"
  if [[ -z "$expected_version" ]]; then
    check "$name: row version agrees with plugin.json" "no-version-in-plugin.json" "yes"
  else
    check "$name: row version agrees with plugin.json (v$expected_version)" \
      "$(grep -qF "✅ v$expected_version" <<< "$row" && echo yes || echo no)" "yes"
  fi
done

# --- 2c. build row must no longer mention /build:sync-pr (RED today:
#         still present). ---

build_row="$(grep -F '[build](plugins/build/)' <<< "$DATA_ROWS" | head -n1)"
check "build row no longer mentions /build:sync-pr" \
  "$(grep -qF '/build:sync-pr' <<< "$build_row" && echo present || echo absent)" \
  "absent"

# --- 2d. Positional invariant: debugging stays the last row (standing
#         invariant; forge-github's insertion must respect it). ---

last_row="$(tail -n1 <<< "$DATA_ROWS")"
check "debugging remains the last row of the Plugins table" \
  "$(grep -qF '[debugging](plugins/debugging/)' <<< "$last_row" && echo yes || echo no)" "yes"

# --- 2e. No duplicate rows, and no stray rows under an unrecognized key
#         (guards against forge-github landing twice or under a
#         different name). ---

PLANNED_NAMES=(pr-workflow session-modes team-review guards agent-dash)

mapfile -t ALL_ROWS <<< "$DATA_ROWS"
KEYS=()
for row in "${ALL_ROWS[@]}"; do
  KEYS+=("$(row_key "$row")")
done

DUP_KEYS="$(printf '%s\n' "${KEYS[@]}" | sort | uniq -d | tr '\n' ' ' | sed -E 's/ +$//')"
check "no duplicate rows in the Plugins table" \
  "$([[ -z "$DUP_KEYS" ]] && echo none || echo "$DUP_KEYS")" "none"

UNKNOWN_KEYS=""
for k in "${KEYS[@]}"; do
  if [[ -z "$k" ]]; then
    UNKNOWN_KEYS="$UNKNOWN_KEYS<unparsed-row> "
    continue
  fi
  if printf '%s\n' "${MP_NAMES[@]}" | grep -qx "$k"; then continue; fi
  if printf '%s\n' "${PLANNED_NAMES[@]}" | grep -qx "$k"; then continue; fi
  UNKNOWN_KEYS="$UNKNOWN_KEYS$k "
done
UNKNOWN_KEYS="$(sed -E 's/ +$//' <<< "$UNKNOWN_KEYS")"
check "every table row corresponds to a marketplace plugin or a known planned entry" \
  "$([[ -z "$UNKNOWN_KEYS" ]] && echo none || echo "$UNKNOWN_KEYS")" "none"

# --- 2f. Planned rows are exempt from version/marketplace checks and
#         must remain present and byte-for-byte untouched (contract
#         invariant: "planned rows untouched"). Pinned as literal
#         baselines (not derived — these rows have no plugin.json)
#         captured from the current README. ---

check "pr-workflow row untouched" \
  "$(grep -qxF '| pr-workflow | planned | PR lifecycle: create, review, address feedback, author checklist, pre-PR verify, doc-sync gate, retrospective, reviewer agent, issue-tracker seam. |' "$README" && echo yes || echo no)" "yes"
# literal README row with backticks, no expansion intended
# shellcheck disable=SC2016
check "session-modes row untouched" \
  "$(grep -qxF '| session-modes | planned | Session workflow modes (`/start`, orient, sitrep, make-progress, …) plus the session-lifecycle hooks and the SessionStart workflow-rules injection that replaces the old `clam` alias. |' "$README" && echo yes || echo no)" "yes"
check "team-review row untouched" \
  "$(grep -qxF '| team-review | planned | Multi-agent review and exploration: team code review, council, independent review, subagent orchestration; Explore and browser agents. |' "$README" && echo yes || echo no)" "yes"
check "guards row untouched" \
  "$(grep -qxF '| guards | planned | Safety hooks: git guard, cron guard, permission audit, notifications. |' "$README" && echo yes || echo no)" "yes"
check "agent-dash row untouched" \
  "$(grep -qxF '| agent-dash | planned | Hooks integrating sessions with [clam-agent-dashboard](https://github.com/cjdubb/clam-agent-dashboard). |' "$README" && echo yes || echo no)" "yes"

# =====================================================================
# (3) Issue-template dropdowns (GREEN: landed at scaffold; regression
#     guards here)
# =====================================================================

for tmpl_path in "$BUG_TEMPLATE" "$FEATURE_TEMPLATE"; do
  tmpl_name="$(basename "$tmpl_path")"
  mapfile -t opts < <(get_dropdown_options "$tmpl_path" "plugin")

  check "$tmpl_name: id=plugin dropdown includes forge-github" \
    "$(printf '%s\n' "${opts[@]}" | grep -qxF 'forge-github' && echo yes || echo no)" "yes"

  mapfile -t sorted_opts < <(printf '%s\n' "${opts[@]:1}" | sort)
  actual_after_first="$(printf '%s\n' "${opts[@]:1}")"
  expected_sorted="$(printf '%s\n' "${sorted_opts[@]}")"
  check "$tmpl_name: id=plugin dropdown plugin options are alphabetical" \
    "$([[ "$actual_after_first" == "$expected_sorted" ]] && echo yes || echo no)" "yes"
done

# =====================================================================
# (4) .claude/settings.local.json — CONDITIONAL (absent -> pass; never
#     required to exist, per orchestrator ruling)
# =====================================================================

if [ -f "$SETTINGS_LOCAL" ]; then
  check "settings.local.json is valid JSON" \
    "$(jq -e . "$SETTINGS_LOCAL" >/dev/null 2>&1 && echo yes || echo no)" "yes"
  check "settings.local.json enables forge-github@clam" \
    "$(jq -r '.enabledPlugins["forge-github@clam"] // false' "$SETTINGS_LOCAL" 2>/dev/null)" "true"
else
  echo "PASS  settings.local.json absent (machine-local, provisioned by copyenv; not required)"
fi

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
