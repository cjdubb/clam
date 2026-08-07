#!/usr/bin/env bash
# Contract: B01 readme-conformance-lint (plan 002-readme-conformance)
# Behavior:
#   Verifies every plugins/*/README.md conforms to the locked template
#   (plugins/PLUGIN_README_TEMPLATE.md): the 6 required H2 headings are
#   present with exact names in exact order —
#     ## Getting started
#     ## What to expect
#     ## Common workflows
#     ## Commands
#     ## Relationships to other plugins
#     ## Uninstalling
#   — and any extra H2 sections (## Tests or plugin-specific) appear ONLY
#   between "## Commands" and "## Relationships to other plugins".
#   Prints one PASS/FAIL line per plugin README (FAIL lines name the first
#   violation: which heading is missing, out of order, or misplaced).
# Inputs:
#   Runs from the repo root (no arguments). Reads plugins/*/README.md.
#   A plugin directory without a README.md is a FAIL (every plugin must
#   have one). plugins/PLUGIN_README_TEMPLATE.md itself is exempt.
# Outputs:
#   Exit 0 when every plugin README passes; exit 1 when any fails.
#   Report lines go to stdout; one line per plugin, FAILs list the reason.
# Errors:
#   Missing plugins/ directory (not run from repo root): message to stderr,
#   exit 2.
# Invariants:
#   - Read-only: never modifies any file.
#   - Only lines starting with exactly "## " count as H2s; H2-looking text
#     inside fenced code blocks or HTML comments must not count.
#   - Deterministic: same tree -> same output and exit code.
# Edge cases:
#   - README with no H2s at all: FAIL (all required missing).
#   - Required headings present but in wrong order: FAIL naming the first
#     out-of-order heading.
#   - Duplicate required heading: FAIL.
#   - Extra H2 before "## Commands" or after "## Relationships to other
#     plugins": FAIL naming the misplaced section.
#   - Trailing whitespace or case variation in a required heading: FAIL
#     (exact match required).
#
# Contract: B06 root-readme-version-lint (plan 001-update-flow-for-users)
# Behavior (extension, to be added after the per-plugin README checks):
#   Verify the root README.md Plugins table against
#   .claude-plugin/marketplace.json and each plugins/<name>/.claude-plugin/
#   plugin.json: every marketplace plugin has exactly one table row, and
#   that row's status cell is exactly "✅ vX.Y.Z" where X.Y.Z equals the
#   plugin's plugin.json version. Rows whose status cell is "planned" are
#   exempt and need not exist in the marketplace. A non-planned row whose
#   plugin is absent from the marketplace is a FAIL (stale row). Prints one
#   "PASS  root-table <plugin>"/"FAIL  root-table <plugin> -> <reason>"
#   line per marketplace plugin (reasons: missing row, duplicate row,
#   malformed status cell, version mismatch expected-vs-found) plus one
#   line per stale row.
# Inputs:
#   Same invocation (repo root, no arguments). Additionally reads
#   README.md, .claude-plugin/marketplace.json, and each
#   plugins/*/.claude-plugin/plugin.json. Requires jq: missing jq is a
#   stderr message and exit 2 (consistent with the not-repo-root error).
# Outputs:
#   Report lines on stdout alongside the per-plugin README lines; exit 0
#   only when every check (existing and new) passes, exit 1 otherwise.
# Invariants:
#   - Read-only; deterministic.
#   - Only the FIRST GFM table in README.md is inspected; rows are
#     identified by the plugin name in the first cell (linked or bare).
#   - Existing per-plugin README checks are unchanged — same lines, same
#     order, new root-table lines appended after them.
# Config note (same block): .claude/lego.json's commands.test glob gains
#   scripts/*.test.sh so scripts/readme-lint.test.sh runs under the
#   standard test command (today it exists but never runs).
# Edge cases:
#   - Table cell whitespace-padded: trim before matching.
#   - Version prefix must be exactly "v" ("✅ 0.1.0" is malformed).
#   - Multiple tables in README.md: only the first counts.
#   - Marketplace plugin whose directory lacks plugin.json: FAIL for that
#     plugin (unreadable expected version).
set -euo pipefail

REQUIRED_HEADINGS=(
  "## Getting started"
  "## What to expect"
  "## Common workflows"
  "## Commands"
  "## Relationships to other plugins"
  "## Uninstalling"
)
COMMANDS_IDX=3
RELATIONSHIPS_IDX=4

if [ ! -d plugins ]; then
  echo "readme-lint: plugins/ directory not found -- run this script from the repo root" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "readme-lint: jq is required for the root-readme-version-lint check" >&2
  exit 2
fi

# Prints the real H2 heading lines of a markdown file, one per output line,
# in document order. Excludes lines inside fenced code blocks (``` or ~~~)
# and inside HTML comments (<!-- ... -->), including multi-line comments.
extract_headings() {
  local file="$1"
  local line in_fence=0 in_comment=0

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_comment" -eq 1 ]; then
      case "$line" in
        *'-->'*) in_comment=0 ;;
      esac
      continue
    fi

    if [ "$in_fence" -eq 1 ]; then
      case "$line" in
        '```'*|'~~~'*) in_fence=0 ;;
      esac
      continue
    fi

    case "$line" in
      '```'*|'~~~'*)
        in_fence=1
        continue
        ;;
    esac

    case "$line" in
      *'<!--'*)
        case "$line" in
          *'-->'*) : ;;
          *) in_comment=1 ;;
        esac
        continue
        ;;
    esac

    case "$line" in
      '## '*) printf '%s\n' "$line" ;;
    esac
  done < "$file"
}

# Trims leading/trailing whitespace from its argument, prints the result.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# True if the line looks like a GFM table row: starts and ends with "|"
# (ignoring surrounding whitespace).
is_table_row() {
  [[ "$1" =~ ^[[:space:]]*\|.*\|[[:space:]]*$ ]]
}

# True if the line is a GFM header separator row: made up only of
# whitespace, "|", ":" and "-", with at least one "-".
is_separator_row() {
  [[ "$1" =~ ^[[:space:]|:-]+$ ]] && [[ "$1" == *-* ]]
}

# Prints the header row followed by each data row (verbatim, separator row
# excluded) of the FIRST GFM table in the given file, one per output line.
# Prints nothing if the file has no GFM table.
extract_first_table() {
  local file="$1"
  local -a lines
  mapfile -t lines < "$file"
  local n=${#lines[@]} i j
  for ((i = 0; i < n; i++)); do
    if is_table_row "${lines[$i]}" && (( i + 1 < n )) && is_separator_row "${lines[$((i + 1))]}"; then
      printf '%s\n' "${lines[$i]}"
      j=$((i + 2))
      while (( j < n )) && is_table_row "${lines[$j]}"; do
        printf '%s\n' "${lines[$j]}"
        j=$((j + 1))
      done
      return
    fi
  done
}

# Prints the trimmed cells of one GFM table row line, one per output line.
row_cells() {
  local row
  row="$(trim "$1")"
  [[ "$row" == \|* ]] && row="${row#|}"
  [[ "$row" == *\| ]] && row="${row%|}"
  local IFS='|'
  local -a cells
  read -ra cells <<< "$row"
  local c
  for c in ${cells[@]+"${cells[@]}"}; do
    trim "$c"
    printf '\n'
  done
}

# Unwraps a markdown link cell ("[name](url)") to its display text; a bare
# cell is returned as-is.
extract_name() {
  local cell="$1"
  if [[ "$cell" =~ ^\[([^]]+)\] ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$cell"
  fi
}

# Prints the status cell of the first row_names[] entry matching $1 (the
# arrays are populated by the root-table section below).
row_status_for() {
  local target="$1" i
  for i in "${!row_names[@]}"; do
    if [ "${row_names[$i]}" = "$target" ]; then
      printf '%s' "${row_statuses[$i]}"
      return
    fi
  done
}

FAILED=0

mapfile -t plugin_names < <(find plugins -mindepth 1 -maxdepth 1 -type d | sed 's|.*/||' | sort)

for name in "${plugin_names[@]}"; do
  readme="plugins/$name/README.md"

  if [ ! -f "$readme" ]; then
    echo "FAIL  $name -> missing README.md"
    FAILED=1
    continue
  fi

  mapfile -t headings < <(extract_headings "$readme")

  # 1. every required heading must appear at least once
  missing=""
  for req in "${REQUIRED_HEADINGS[@]}"; do
    count=0
    for h in ${headings[@]+"${headings[@]}"}; do
      if [ "$h" = "$req" ]; then
        count=$((count + 1))
      fi
    done
    if [ "$count" -eq 0 ]; then
      missing="$req"
      break
    fi
  done
  if [ -n "$missing" ]; then
    echo "FAIL  $name -> missing required heading '$missing'"
    FAILED=1
    continue
  fi

  # 2. no required heading may appear more than once
  dup=""
  for req in "${REQUIRED_HEADINGS[@]}"; do
    count=0
    for h in ${headings[@]+"${headings[@]}"}; do
      if [ "$h" = "$req" ]; then
        count=$((count + 1))
      fi
    done
    if [ "$count" -gt 1 ]; then
      dup="$req"
      break
    fi
  done
  if [ -n "$dup" ]; then
    echo "FAIL  $name -> duplicate required heading '$dup'"
    FAILED=1
    continue
  fi

  # 3. required headings must appear in the locked order (extras aside)
  ordered_required=()
  for h in ${headings[@]+"${headings[@]}"}; do
    for req in "${REQUIRED_HEADINGS[@]}"; do
      if [ "$h" = "$req" ]; then
        ordered_required+=("$h")
        break
      fi
    done
  done

  order_violation=""
  expected_violation=""
  for i in "${!REQUIRED_HEADINGS[@]}"; do
    if [ "${ordered_required[$i]}" != "${REQUIRED_HEADINGS[$i]}" ]; then
      order_violation="${ordered_required[$i]}"
      expected_violation="${REQUIRED_HEADINGS[$i]}"
      break
    fi
  done
  if [ -n "$order_violation" ]; then
    echo "FAIL  $name -> heading '$order_violation' out of order (expected '$expected_violation' here)"
    FAILED=1
    continue
  fi

  # 4. extra H2s are only allowed between "## Commands" and
  #    "## Relationships to other plugins"
  commands_pos=-1
  relationships_pos=-1
  for i in "${!headings[@]}"; do
    if [ "${headings[$i]}" = "${REQUIRED_HEADINGS[$COMMANDS_IDX]}" ]; then
      commands_pos=$i
    fi
    if [ "${headings[$i]}" = "${REQUIRED_HEADINGS[$RELATIONSHIPS_IDX]}" ]; then
      relationships_pos=$i
    fi
  done

  misplaced=""
  for i in "${!headings[@]}"; do
    h="${headings[$i]}"
    is_required=0
    for req in "${REQUIRED_HEADINGS[@]}"; do
      if [ "$h" = "$req" ]; then
        is_required=1
        break
      fi
    done
    if [ "$is_required" -eq 1 ]; then
      continue
    fi
    if [ "$i" -le "$commands_pos" ] || [ "$i" -ge "$relationships_pos" ]; then
      misplaced="$h"
      break
    fi
  done
  if [ -n "$misplaced" ]; then
    echo "FAIL  $name -> unexpected heading '$misplaced' outside the allowed section"
    FAILED=1
    continue
  fi

  echo "PASS  $name"
done

# ---------------------------------------------------------------------------
# B06 root-readme-version-lint: the root README.md Plugins table (first GFM
# table only) vs .claude-plugin/marketplace.json vs each plugin's
# plugins/<name>/.claude-plugin/plugin.json.
# ---------------------------------------------------------------------------

mapfile -t marketplace_names < <(jq -r '.plugins[].name' .claude-plugin/marketplace.json)

mapfile -t table_lines < <(extract_first_table README.md)

row_names=()
row_statuses=()
if [ "${#table_lines[@]}" -gt 1 ]; then
  for ((i = 1; i < ${#table_lines[@]}; i++)); do
    mapfile -t cells < <(row_cells "${table_lines[$i]}")
    row_names+=("$(extract_name "${cells[0]:-}")")
    row_statuses+=("${cells[1]:-}")
  done
fi

declare -A row_count=()
for name in ${row_names[@]+"${row_names[@]}"}; do
  row_count["$name"]=$(( ${row_count["$name"]:-0} + 1 ))
done

declare -A in_marketplace=()
for name in ${marketplace_names[@]+"${marketplace_names[@]}"}; do
  in_marketplace["$name"]=1
done

# 1. every marketplace plugin must have exactly one root-table row whose
#    status cell agrees with its plugin.json version.
for name in ${marketplace_names[@]+"${marketplace_names[@]}"}; do
  count="${row_count[$name]:-0}"

  if [ "$count" -eq 0 ]; then
    echo "FAIL  root-table $name -> missing row"
    FAILED=1
    continue
  fi

  if [ "$count" -gt 1 ]; then
    echo "FAIL  root-table $name -> duplicate row"
    FAILED=1
    continue
  fi

  plugin_json="plugins/$name/.claude-plugin/plugin.json"
  if [ ! -f "$plugin_json" ]; then
    echo "FAIL  root-table $name -> plugin.json missing, cannot read expected version"
    FAILED=1
    continue
  fi
  expected_version="$(jq -r '.version' "$plugin_json")"

  status="$(row_status_for "$name")"
  if [[ "$status" =~ ^✅\ v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    found_version="${BASH_REMATCH[1]}"
  else
    echo "FAIL  root-table $name -> malformed status cell '$status'"
    FAILED=1
    continue
  fi

  if [ "$found_version" != "$expected_version" ]; then
    echo "FAIL  root-table $name -> version mismatch: expected $expected_version, found $found_version"
    FAILED=1
    continue
  fi

  echo "PASS  root-table $name"
done

# 2. a non-planned row for a plugin absent from the marketplace is stale.
for i in "${!row_names[@]}"; do
  name="${row_names[$i]}"
  status="${row_statuses[$i]}"
  if [ -z "${in_marketplace[$name]:-}" ] && [ "$status" != "planned" ]; then
    echo "FAIL  root-table $name -> stale row: plugin not in marketplace.json"
    FAILED=1
  fi
done

exit "$FAILED"
