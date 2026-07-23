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

FAILED=0

mapfile -t plugin_names < <(find plugins -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

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

exit "$FAILED"
