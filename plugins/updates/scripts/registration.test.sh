#!/bin/bash
# Structural/content tests for Block B04 (registration & root-README
# integrity, plan 001-update-flow-for-users).
#
# Source of truth: this file. The block's contract docblock sat in the root
# README.md below the Plugins table and was removed once the block landed
# (plan 001-update-flow-for-users; recoverable from git history). The clauses
# it specified are the assertions below, on the two shared repo surfaces it
# named as this block's outputs:
#
#   (1) .claude-plugin/marketplace.json — exactly one plugins[] entry named
#       "updates": source "./plugins/updates", no version field
#       (plugin.json is the single source of truth for version), and a
#       non-empty description naming /updates:run. This landed at scaffold
#       (marketplace-lint requires directory/entry parity from the moment
#       the plugin directory exists), so this part of the suite is GREEN
#       today — it pins an existing invariant rather than driving new work.
#   (2) README.md Plugins table — a sweep restoring the whole table to
#       agreement with plugin.json versions (the single source of truth):
#       four new rows (updates, notifications, skill-tracker, session-data)
#       inserted before the debugging row (which stays last), and seven
#       drifted rows corrected (lego, tracking, and the five B05-bumped
#       setup-stamp plugins: attribution, privacy, settings, statusline,
#       landing). This part is RED today: the four rows are missing and the
#       seven versions are drifted; everything else in the table already
#       agrees with plugin.json.
#
# Explicitly out of scope (per the orchestrator's brief): the contract's
# conditional clause about the README "Update" section prose. No assertion
# here touches that section; it is verified manually at acceptance.
#
# The B04 contract docblock quotes literal sample rows for the four new
# plugins (e.g. "| [updates](plugins/updates/) | ✅ v0.1.0 | ... |") as part
# of narrating its own Outputs — sitting in the README just below the real
# table. A raw-text search for those exact strings would find the docblock's
# own prose and pass vacuously before any real row is added. Every table
# check below therefore runs against a comment-stripped copy of the README,
# using the same per-line state machine as plugins/updates/scripts/
# manifest.test.sh (strip_comments): unlike a bare `sed '/<!--/,/-->/d'`,
# which keeps hunting for the next "-->" and can swallow real content
# between consecutive same-line comments, this closes a same-line comment
# on the same line it opens. The five still-"planned" rows are checked
# against the raw file instead: they live in the real table (not inside any
# comment), have no plugin.json, and per the contract must stay byte-for-
# byte untouched, so they are pinned as literal baselines captured from the
# current README rather than derived.
#
# Every marketplace-driven check reads its expected version dynamically
# from plugins/<name>/.claude-plugin/plugin.json — never a hardcoded version
# literal — so the suite tracks whatever B01/B05/etc. land rather than
# pinning numbers twice (contract: "plugin.json is the single source of
# truth").
#
# Hermetic: reads only the repo's own committed files, no network, no
# mutation, cwd-independent (all paths resolved from this script's own
# location).
#
# Run: bash plugins/updates/scripts/registration.test.sh (non-zero exit on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
README="$ROOT/README.md"
UPDATES_PLUGIN_JSON="$ROOT/plugins/updates/.claude-plugin/plugin.json"

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
# plugins/updates/scripts/manifest.test.sh's strip_comments verbatim.
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

# --- 0. Preconditions ---
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "README.md exists" \
  "$([ -f "$README" ] && echo yes || echo no)" "yes"
check "updates plugin.json exists" \
  "$([ -f "$UPDATES_PLUGIN_JSON" ] && echo yes || echo no)" "yes"

# =====================================================================
# (1) marketplace.json — the "updates" entry (expected GREEN: landed at
#     scaffold)
# =====================================================================

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

check "marketplace.json has no duplicate plugin names" \
  "$(jq '(.plugins | length) == (.plugins | map(.name) | unique | length)' "$MARKETPLACE" 2>/dev/null)" "true"

UPDATES_COUNT="$(jq '[.plugins[]? | select(.name=="updates")] | length' "$MARKETPLACE" 2>/dev/null)"
check "marketplace.json has exactly one plugins[] entry named 'updates'" \
  "$UPDATES_COUNT" "1"

UPDATES_ENTRY="$(jq -c '.plugins[]? | select(.name=="updates")' "$MARKETPLACE" 2>/dev/null)"

check "updates entry source is './plugins/updates'" \
  "$(jq -r '.source' <<<"$UPDATES_ENTRY" 2>/dev/null)" \
  "./plugins/updates"

check "updates entry has no version field (plugin.json is source of truth)" \
  "$(jq -r 'has("version")' <<<"$UPDATES_ENTRY" 2>/dev/null)" "false"

UPDATES_MP_DESC="$(jq -r '.description // empty' <<<"$UPDATES_ENTRY" 2>/dev/null)"
check "updates entry description is non-empty" \
  "$([ -n "$UPDATES_MP_DESC" ] && echo yes || echo no)" "yes"
check "updates entry description names /updates:run" \
  "$(grep -qF '/updates:run' <<<"$UPDATES_MP_DESC" && echo yes || echo no)" "yes"

# =====================================================================
# (2) README.md Plugins table
# =====================================================================
# All checks below run against $DATA_ROWS: the "## Plugins" section body
# with HTML comments stripped (so the contract docblock's own sample rows
# can never satisfy a check), filtered down to real table rows (header and
# separator excluded).

readme_stripped="$(strip_comments "$README")"
plugins_section="$(section_body "$readme_stripped" "## Plugins")"
DATA_ROWS="$(grep -E '^\| ' <<< "$plugins_section" | grep -v '^| Plugin ' | grep -v '^|-')"

check "found the Plugins table (at least one data row after stripping comments)" \
  "$([ -n "$DATA_ROWS" ] && echo yes || echo no)" "yes"

# --- 2a. Every marketplace-listed plugin has exactly one row, version
#         agreeing with its own plugin.json (dynamically read). This single
#         loop covers both the four missing rows and the seven drifted
#         rows (RED today) as well as the rows already in agreement
#         (GREEN today). ---

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

# --- 2b. The four new rows: content and shape. ---

updates_row="$(grep -F '[updates](plugins/updates/)' <<< "$DATA_ROWS" | head -n1)"
check "updates row names /updates:run" \
  "$(grep -qF '/updates:run' <<< "$updates_row" && echo yes || echo no)" "yes"
check "updates row matches the standard row shape" \
  "$([[ "$updates_row" =~ ^\|\ \[updates\]\(plugins/updates/\)\ \|\ ✅\ v[0-9]+\.[0-9]+\.[0-9]+\ \|\ .+\ \|$ ]] && echo yes || echo no)" "yes"

notifications_row="$(grep -F '[notifications](plugins/notifications/)' <<< "$DATA_ROWS" | head -n1)"
check "notifications row describes the summoning stack (per its marketplace description)" \
  "$(grep -qi 'summoning' <<< "$notifications_row" && echo yes || echo no)" "yes"
check "notifications row matches the standard row shape" \
  "$([[ "$notifications_row" =~ ^\|\ \[notifications\]\(plugins/notifications/\)\ \|\ ✅\ v[0-9]+\.[0-9]+\.[0-9]+\ \|\ .+\ \|$ ]] && echo yes || echo no)" "yes"

skill_tracker_row="$(grep -F '[skill-tracker](plugins/skill-tracker/)' <<< "$DATA_ROWS" | head -n1)"
check "skill-tracker row names /skill-tracker:stats" \
  "$(grep -qF '/skill-tracker:stats' <<< "$skill_tracker_row" && echo yes || echo no)" "yes"
check "skill-tracker row matches the standard row shape" \
  "$([[ "$skill_tracker_row" =~ ^\|\ \[skill-tracker\]\(plugins/skill-tracker/\)\ \|\ ✅\ v[0-9]+\.[0-9]+\.[0-9]+\ \|\ .+\ \|$ ]] && echo yes || echo no)" "yes"

session_data_row="$(grep -F '[session-data](plugins/session-data/)' <<< "$DATA_ROWS" | head -n1)"
check "session-data row names /session-data:paths" \
  "$(grep -qF '/session-data:paths' <<< "$session_data_row" && echo yes || echo no)" "yes"
check "session-data row matches the standard row shape" \
  "$([[ "$session_data_row" =~ ^\|\ \[session-data\]\(plugins/session-data/\)\ \|\ ✅\ v[0-9]+\.[0-9]+\.[0-9]+\ \|\ .+\ \|$ ]] && echo yes || echo no)" "yes"

# --- 2c. Positional invariant: debugging stays the last row. Since the
#         contract's only ordering rule is "before debugging", and
#         debugging is checked here to be last, any row present in the
#         table is automatically before it. ---

last_row="$(tail -n1 <<< "$DATA_ROWS")"
check "debugging remains the last row of the Plugins table" \
  "$(grep -qF '[debugging](plugins/debugging/)' <<< "$last_row" && echo yes || echo no)" "yes"

# --- 2d. No duplicate rows, and no stray rows under an unrecognized key
#         (guards against a duplicate landing under a different name). ---

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

# --- 2e. Planned rows are exempt from version/marketplace checks and must
#         remain present and byte-for-byte untouched. Pinned as literal
#         baselines (not derived — these rows have no plugin.json) captured
#         from the current README. ---

check "pr-workflow row untouched" \
  "$(grep -qxF '| pr-workflow | planned | PR lifecycle: create, review, address feedback, author checklist, pre-PR verify, doc-sync gate, retrospective, reviewer agent, issue-tracker seam. |' "$README" && echo yes || echo no)" "yes"
check "session-modes row untouched" \
  "$(grep -qxF '| session-modes | planned | Session workflow modes (`/start`, orient, sitrep, make-progress, …) plus the session-lifecycle hooks and the SessionStart workflow-rules injection that replaces the old `clam` alias. |' "$README" && echo yes || echo no)" "yes"
check "team-review row untouched" \
  "$(grep -qxF '| team-review | planned | Multi-agent review and exploration: team code review, council, independent review, subagent orchestration; Explore and browser agents. |' "$README" && echo yes || echo no)" "yes"
check "guards row untouched" \
  "$(grep -qxF '| guards | planned | Safety hooks: git guard, cron guard, permission audit, notifications. |' "$README" && echo yes || echo no)" "yes"
check "agent-dash row untouched" \
  "$(grep -qxF '| agent-dash | planned | Hooks integrating sessions with [clam-agent-dashboard](https://github.com/cjdubb/clam-agent-dashboard). |' "$README" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
