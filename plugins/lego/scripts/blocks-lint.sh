#!/bin/bash
# Lints a lego block map for plan-time sizing discipline.
#
# <!--
# Contract: B05 blocks-lint-budget-flag (plan 001-lego-config-redesign)
# Behavior:   budget = --budget when given, else the constant 500; the
#             layered-config resolution block is deleted.
# Inputs:     existing CLI shape; --budget validation retained.
# Outputs:    unchanged findings/summary.
# Errors:     config-error paths removed; usage errors unchanged (exit 2).
# Invariants: per-block ceiling stays floor(budget/2); $LEGO_CONFIG and any
#             config file on disk are ignored; jq only where still used.
# Edge cases: omitted --budget on a repo with a stray lego.json -> 500, the
#             file is not read.
# -->
#
# Run: bash plugins/lego/scripts/blocks-lint.sh [--budget <n>] [path/to/blocks.md]
#
# <!--
# Contract: B04 blocks-lint
#
# Behavior:
#   Parses a lego block map (default .local/blocks.md) and mechanically
#   enforces the plan-time sizing rules:
#   - Every block entry — a "## B<NN> — <name>" heading — must carry an
#     `Est:` field whose value is a non-negative integer (bare digits; no
#     commas, units, or ranges).
#   - Every entry whose Est is STRICTLY GREATER than the ceiling must carry
#     a non-empty `Justification:` field. Ceiling = floor(budget / 2).
#     Budget resolution order: --budget flag, else delivery.prSizeBudget
#     from the layered config (.claude/lego.json deep-merged with
#     .local/config.json; $LEGO_CONFIG overrides the override-file path as
#     in realm.sh), else 500.
#   - Duplicate block ids (two headings with the same B<NN>) are a finding.
#
# Inputs:
#   - --budget <positive integer>: overrides config/default budget.
#   - Optional positional path to the block map; default .local/blocks.md
#     relative to the cwd. Exactly one positional argument is accepted.
#
# Outputs:
#   - stdout: one line per finding, format "LINT B<NN>: <problem>" (or
#     "LINT <file>: <problem>" for file-level findings), then a blank line
#     and either "ALL PASS (<n> blocks, ceiling <c>)" or
#     "FAILURES: <count> — fix the block map before scaffolding".
#
# Errors:
#   - Missing/unreadable block-map file, a file containing zero block
#     entries, non-integer or non-positive --budget, --budget without a
#     value, unknown flag, more than one positional argument: diagnostic on
#     stderr, exit 2.
#   - jq unavailable when config resolution is required (no --budget
#     given and a config file exists): diagnostic on stderr, exit 2; with
#     --budget given, jq is never needed.
#   - One or more findings: exit 1.
#
# Invariants:
#   - Read-only: never modifies the block map, the repo, or git state.
#   - Exit codes: 0 (clean), 1 (findings), 2 (usage/environment) — never
#     anything else.
#   - Every entry is linted regardless of Status: (Dropped and Accepted
#     blocks still require valid Est fields — history stays parseable).
#   - Parsing tolerates CRLF line endings, leading/trailing whitespace on
#     field lines, and fields in any order within an entry.
#   - A `Justification:` field satisfies the requirement only when its
#     value (same line after the colon, or the immediately following
#     indented continuation lines) contains at least one non-whitespace
#     character.
#
# Edge cases:
#   - Est: 0 is valid and never requires justification.
#   - Est exactly equal to the ceiling: no justification required.
#   - Justified block at or under the ceiling: the stray Justification is
#     harmless, not a finding.
#   - Odd budget: ceiling is the floor (budget 501 → ceiling 250).
#   - Entries after a "## " heading that is not a block id (e.g. a prose
#     section) are ignored, not findings.
# -->

set -uo pipefail

USAGE_MSG="usage: blocks-lint.sh [--budget <n>] [path/to/blocks.md]"
err() { printf 'ERROR: %s\n' "$1" >&2; }
usage() { err "$USAGE_MSG"; exit 2; }

# trim <string> — strip leading/trailing whitespace.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# Parse arguments: optional --budget <n>, at most one positional path.
# ---------------------------------------------------------------------------
budget_flag=""
positional=""
have_positional=0

args=("$@")
argc=${#args[@]}
i=0
while [ "$i" -lt "$argc" ]; do
  a="${args[$i]}"
  case "$a" in
    --budget)
      i=$((i + 1))
      [ "$i" -lt "$argc" ] || usage
      budget_flag="${args[$i]}"
      case "$budget_flag" in
        ''|*[!0-9]*) usage ;;
      esac
      budget_flag="$((10#$budget_flag))"
      [ "$budget_flag" -ne 0 ] || usage
      i=$((i + 1))
      ;;
    --*)
      usage
      ;;
    *)
      [ "$have_positional" -eq 0 ] || usage
      positional="$a"
      have_positional=1
      i=$((i + 1))
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve the block map path. cwd-relative by design, same as realm.sh — no
# repo-root resolution.
# ---------------------------------------------------------------------------
MAP_PATH="${positional:-.local/blocks.md}"

if [ ! -f "$MAP_PATH" ] || [ ! -r "$MAP_PATH" ]; then
  err "block map not found or not readable: $MAP_PATH"
  exit 2
fi

# ---------------------------------------------------------------------------
# Resolve the budget: --budget when given, else the constant 500. No config
# file is consulted — not .claude/lego.json, not .local/config.json, not
# $LEGO_CONFIG — so no config error exists and jq is never needed.
# ---------------------------------------------------------------------------
BUDGET=500
if [ -n "$budget_flag" ]; then
  BUDGET="$budget_flag"
fi

CEILING=$((BUDGET / 2))

# ---------------------------------------------------------------------------
# Parse the block map: strip CRLF, walk line by line. A "## B<NN> ..."
# heading opens a block entry; any other "## " heading is a prose section,
# skipped without being counted or linted.
# ---------------------------------------------------------------------------
mapfile -t LINES < <(tr -d '\r' < "$MAP_PATH")
N="${#LINES[@]}"

FINDINGS=()
declare -A SEEN_IDS
BLOCK_COUNT=0

# Group headroom (B15): Est sums per PR group:, dropped blocks excluded.
declare -A GROUP_SUM
GROUP_ORDER=()
THRESHOLD=$((BUDGET * 7 / 10))

i=0
while [ "$i" -lt "$N" ]; do
  line="${LINES[$i]}"

  if [[ "$line" != "## "* ]]; then
    i=$((i + 1))
    continue
  fi

  rest="${line#"## "}"
  id_candidate="${rest%%[[:space:]]*}"
  if [[ ! "$id_candidate" =~ ^B[0-9]+$ ]]; then
    i=$((i + 1))
    continue
  fi

  id="$id_candidate"
  BLOCK_COUNT=$((BLOCK_COUNT + 1))
  prior="${SEEN_IDS[$id]:-0}"
  SEEN_IDS[$id]=$((prior + 1))
  if [ "$prior" -ge 1 ]; then
    FINDINGS+=("LINT $id: duplicate block id, $id appears more than once (repeat heading) in the block map")
  fi

  i=$((i + 1))

  est_present=0
  est_raw=""
  just_satisfied=0
  status_val=""
  group_val=""
  have_group=0
  estimpl_present=0
  estimpl_raw=""
  esttests_present=0
  esttests_raw=""

  while [ "$i" -lt "$N" ]; do
    eline="${LINES[$i]}"

    if [[ "$eline" == "## "* ]]; then
      break
    fi

    trimmed="$(trim "$eline")"

    if [[ "$trimmed" != "- "* ]]; then
      i=$((i + 1))
      continue
    fi

    field_body="${trimmed#- }"
    field_name="$(trim "${field_body%%:*}")"
    case "$field_body" in
      *:*) field_value="$(trim "${field_body#*:}")" ;;
      *) field_value="" ;;
    esac

    case "$field_name" in
      Status)
        status_val="$field_value"
        i=$((i + 1))
        ;;
      "PR group")
        group_val="$field_value"
        have_group=1
        i=$((i + 1))
        ;;
      Est)
        est_present=1
        est_raw="$field_value"
        i=$((i + 1))
        ;;
      Est-impl)
        estimpl_present=1
        estimpl_raw="$field_value"
        i=$((i + 1))
        ;;
      Est-tests)
        esttests_present=1
        esttests_raw="$field_value"
        i=$((i + 1))
        ;;
      Justification)
        i=$((i + 1))
        if [ -n "$field_value" ]; then
          just_satisfied=1
        else
          while [ "$i" -lt "$N" ]; do
            cline="${LINES[$i]}"
            ctrimmed="$(trim "$cline")"
            if [ -z "$ctrimmed" ]; then
              break
            fi
            if [[ "$ctrimmed" == "- "* ]] || [[ "$cline" == "## "* ]]; then
              break
            fi
            if [[ "$cline" != "$ctrimmed" ]]; then
              just_satisfied=1
            fi
            i=$((i + 1))
          done
        fi
        ;;
      *)
        i=$((i + 1))
        ;;
    esac
  done

  if [ "$est_present" -eq 0 ]; then
    FINDINGS+=("LINT $id: missing Est field (must be a bare non-negative integer)")
  elif [[ "$est_raw" =~ ^[0-9]+$ ]]; then
    est_num="$((10#$est_raw))"
    if [ "$est_num" -gt "$CEILING" ] && [ "$just_satisfied" -ne 1 ]; then
      FINDINGS+=("LINT $id: Est $est_num is over ceiling $CEILING and needs a non-empty Justification")
    fi
  else
    FINDINGS+=("LINT $id: Est value '$est_raw' is not a bare non-negative integer")
  fi

  # -------------------------------------------------------------------------
  # B15: Est-impl:/Est-tests: pair — both present and summing to Est, or
  # both absent. A lone field, or a present pair that disagrees with Est, is
  # a finding.
  # -------------------------------------------------------------------------
  if [ "$estimpl_present" -eq 1 ] && [ "$esttests_present" -eq 1 ]; then
    if [[ "$estimpl_raw" =~ ^[0-9]+$ ]] && [[ "$esttests_raw" =~ ^[0-9]+$ ]]; then
      pair_sum="$((10#$estimpl_raw + 10#$esttests_raw))"
      if [ "$est_present" -eq 1 ] && [[ "$est_raw" =~ ^[0-9]+$ ]]; then
        if [ "$pair_sum" -ne "$((10#$est_raw))" ]; then
          FINDINGS+=("LINT $id: Est-impl ($estimpl_raw) + Est-tests ($esttests_raw) = $pair_sum, which does not match Est ($est_raw)")
        fi
      fi
    else
      FINDINGS+=("LINT $id: Est-impl and Est-tests must each be a bare non-negative integer")
    fi
  elif [ "$estimpl_present" -eq 1 ] || [ "$esttests_present" -eq 1 ]; then
    FINDINGS+=("LINT $id: Est-impl and Est-tests must both be present or both absent (only one is set)")
  fi

  # -------------------------------------------------------------------------
  # B15: accumulate this entry's Est into its PR group: sum, unless the
  # entry is Dropped or carries no PR group: field.
  # -------------------------------------------------------------------------
  if [ "$have_group" -eq 1 ] && [ "$status_val" != "Dropped" ] && [ "$est_present" -eq 1 ] && [[ "$est_raw" =~ ^[0-9]+$ ]]; then
    if [ -z "${GROUP_SUM[$group_val]+set}" ]; then
      GROUP_SUM[$group_val]=0
      GROUP_ORDER+=("$group_val")
    fi
    GROUP_SUM[$group_val]=$((GROUP_SUM[$group_val] + 10#$est_raw))
  fi
done

# ---------------------------------------------------------------------------
# B15: one WARN line per PR group: whose Est sum strictly exceeds the
# headroom threshold floor(budget * 7 / 10). Never affects the exit code or
# the FAILURES count.
# ---------------------------------------------------------------------------
WARNINGS=()
for group_val in "${GROUP_ORDER[@]}"; do
  if [ "${GROUP_SUM[$group_val]}" -gt "$THRESHOLD" ]; then
    WARNINGS+=("WARN: PR group $group_val sums to ${GROUP_SUM[$group_val]}, over the headroom threshold $THRESHOLD (budget $BUDGET)")
  fi
done

if [ "$BLOCK_COUNT" -eq 0 ]; then
  err "no block entries found in $MAP_PATH"
  exit 2
fi

# ---------------------------------------------------------------------------
# Report: one finding per line, then an unconditional blank separator, then
# the summary verdict.
# ---------------------------------------------------------------------------
for f in "${FINDINGS[@]}"; do
  printf '%s\n' "$f"
done

for w in "${WARNINGS[@]}"; do
  printf '%s\n' "$w"
done

printf '\n'

if [ "${#FINDINGS[@]}" -eq 0 ]; then
  printf 'ALL PASS (%s blocks, ceiling %s)\n' "$BLOCK_COUNT" "$CEILING"
  exit 0
fi

printf 'FAILURES: %s — fix the block map before scaffolding\n' "${#FINDINGS[@]}"
exit 1
