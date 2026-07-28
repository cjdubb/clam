#!/bin/bash
# Measures a git diff range against the configured PR size budget.
#
# Run: bash plugins/lego/scripts/pr-size-check.sh [--budget <n>] [--justified] <diff-range> [-- <pathspec>...]
#      (exit 0 within budget, 1 over budget, 2 usage/environment error)

# <!--
# Contract: B01 pr-size-budget-check (plan 001-lego-pr-sizing-landing-strategy)
#
# Behavior:
#   Resolves a PR size budget, measures the total changed lines in a git diff
#   range, and reports whether the range fits the budget. This is the
#   mechanical counterpart to the size estimates /lego:plan records at plan
#   time: estimates decide the grouping, this decides whether the grouping
#   held.
#
#   Steps, in order:
#     1. Resolve the repo root via git rev-parse --show-toplevel and run
#        every git command from there.
#     2. Resolve the budget, first match wins:
#          a. --budget <n> (config is then never read, and jq is not needed)
#          b. .delivery.prSizeBudget in the effective config — the jq
#             recursive merge (.[0] * .[1]) of the base .claude/lego.json and
#             the override $LEGO_CONFIG (default .local/config.json); both
#             files optional
#          c. 500
#     3. Measure: git diff --numstat <diff-range> [-- <pathspec>...], summing
#        added + deleted over all text rows. Binary rows (numstat "-" "-")
#        contribute 0.
#     4. Compare the total against the budget and report (see Outputs).
#
# Inputs:
#   - Exactly one positional argument: <diff-range>, an opaque string passed
#     VERBATIM to git diff --numstat. Anything git accepts works —
#     "master...HEAD", "A..B", a single ref, a sha.
#   - Optional "--" followed by one or more pathspecs, forwarded verbatim to
#     git diff after its own "--". This is what lets a caller measure the
#     exact diff a PR group will produce before the PR exists: the group's
#     Code paths across the range. Everything after "--" is a pathspec; no
#     flag parsing happens there.
#   - Optional --budget <n>: positive integer, overrides the config value.
#   - Optional --justified: the plan records a written justification for this
#     group being over budget; an over-budget result is then reported as WARN
#     and exits 0 instead of failing.
#   - Flags may appear before or after the positional argument, but never
#     after "--".
#   - Requires: git, bash. jq is required only when the budget must come from
#     config (no --budget) AND at least one config file exists.
#   - $LEGO_CONFIG redirects the override config file's path (default
#     .local/config.json) — the same test-fixture seam scripts/realm.sh uses,
#     not something an engineer sets by hand.
#
# Outputs:
#   - Exactly one summary line on stdout, always:
#       PASS  <total> lines changed (budget <budget>)
#       FAIL  <total> lines changed, over budget <budget> by <delta>
#       WARN  <total> lines changed, over budget <budget> by <delta> — justified
#   - When over budget (FAIL or WARN alike), a per-file breakdown follows the
#     summary so the reader can see where to split: changed-line count and
#     path, two leading spaces, sorted by count descending with ties broken by
#     path ascending, at most 10 entries, then "  ... and <n> more files" when
#     more files changed than were listed.
#   - Binary files, when the range contains any, appear in the breakdown
#     section as "  binary  <path>" and are excluded from <total>.
#   - Exit codes: 0 within budget (or over but --justified), 1 over budget,
#     2 usage or environment error.
#
# Errors:
#   - No positional argument, more than one, an unknown flag, --budget with no
#     value, or --budget with a non-integer or non-positive value: usage line
#     on stderr, exit 2.
#   - Not inside a git repository: diagnostic on stderr, exit 2.
#   - git diff --numstat fails for the given range (bad revision, ambiguous
#     argument): diagnostic naming the range on stderr, exit 2.
#   - A config file that exists but is not valid JSON: diagnostic naming the
#     file on stderr, exit 2.
#   - .delivery.prSizeBudget present but not a positive integer: diagnostic on
#     stderr, exit 2.
#   - jq needed (config-sourced budget) but not installed: diagnostic on
#     stderr, exit 2.
#
# Invariants:
#   - Read-only: never writes a file, never touches the index, working tree,
#     or any ref.
#   - cwd-independent: resolves the repo root and runs git from there, so the
#     same range measures the same from any subdirectory.
#   - Exit status is only ever 0, 1, or 2.
#   - <total> is additions + deletions over text files — the same quantity
#     GitHub reports as a pull request's changed lines — so "500" means the
#     same thing to this script and to a reviewer looking at the PR.
#   - --justified changes only the exit code and the summary label; the
#     measured total and the breakdown are byte-identical with and without it.
#   - The diff range and any pathspecs are never parsed or rewritten; git's
#     own error text is what surfaces when either is bad.
#   - A pathspec-scoped run measures exactly the files matched — the same
#     total the caller would get from git diff with the same arguments.
#   - Deterministic: the same repo state and range produce the same output and
#     the same exit code.
#
# Edge cases:
#   - Range with no changes: "PASS  0 lines changed (budget <n>)", exit 0.
#   - Total exactly equal to the budget: within budget, PASS — the budget is
#     inclusive.
#   - Deletion-heavy range: deletions count toward the total, so a large pure
#     deletion can exceed the budget. Deliberate — --justified and --budget
#     are the escape hatches, and an unreviewed 900-line deletion is still
#     worth a second look.
#   - Binary-only change: 0 counted lines, PASS, with the binary files listed.
#   - Pure rename with no content change: contributes 0 lines.
#   - --budget 0: usage error; a zero budget would fail every non-empty range.
#   - --budget given alongside a config value: --budget wins and no config
#     file is read (so a repo with no config, or no jq, still works).
#   - Neither config file exists and no --budget: the 500 default applies
#     without error and without needing jq.
#   - --justified on a within-budget range: plain PASS; the flag is inert.
#   - More than 10 changed files while over budget: the 10 largest are listed
#     and the remainder is summarized, never silently dropped.
#   - "--" given with no pathspecs after it: usage error, exit 2 — an empty
#     pathspec list is far more likely a caller bug than an intent to match
#     everything.
#   - A pathspec matching nothing in the range: 0 lines, PASS — matching
#     nothing is not an error, the same way git treats it.
# -->

set -uo pipefail

USAGE_MSG="usage: pr-size-check.sh [--budget <n>] [--justified] <diff-range> [-- <pathspec>...]"

err() { printf 'ERROR: %s\n' "$1" >&2; }
usage() { err "$USAGE_MSG"; exit 2; }

# ---------------------------------------------------------------------------
# Parse arguments. Flags may appear before or after the positional; nothing
# after "--" is ever parsed as a flag.
# ---------------------------------------------------------------------------
budget_flag=""
justified=0
positional=""
have_positional=0
have_dashdash=0
pathspecs=()

args=("$@")
argc=${#args[@]}
i=0
while [ "$i" -lt "$argc" ]; do
  a="${args[$i]}"
  if [ "$have_dashdash" -eq 1 ]; then
    pathspecs+=("$a")
    i=$((i + 1))
    continue
  fi
  case "$a" in
    --)
      have_dashdash=1
      i=$((i + 1))
      ;;
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
    --justified)
      justified=1
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

[ "$have_positional" -eq 1 ] || usage
if [ "$have_dashdash" -eq 1 ] && [ "${#pathspecs[@]}" -eq 0 ]; then
  usage
fi

# ---------------------------------------------------------------------------
# Resolve the repo root; every git command below runs from there so the
# result is cwd-independent.
# ---------------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { err "not inside a git repository"; exit 2; }

# ---------------------------------------------------------------------------
# Resolve the budget: --budget wins (config is never read, jq never
# invoked); otherwise .delivery.prSizeBudget from the effective config
# (jq recursive merge of the committed base and the gitignored override,
# both optional); otherwise the 500 default.
# ---------------------------------------------------------------------------
BUDGET=500
if [ -n "$budget_flag" ]; then
  BUDGET="$budget_flag"
else
  base_config="$REPO_ROOT/.claude/lego.json"
  override_rel="${LEGO_CONFIG:-.local/config.json}"
  case "$override_rel" in
    /*) override_config="$override_rel" ;;
    *) override_config="$REPO_ROOT/$override_rel" ;;
  esac

  have_base=0
  have_override=0
  [ -f "$base_config" ] && have_base=1
  [ -f "$override_config" ] && have_override=1

  if [ "$have_base" -eq 1 ] || [ "$have_override" -eq 1 ]; then
    if ! command -v jq >/dev/null 2>&1; then
      err "jq is required to read delivery.prSizeBudget from config ($base_config and/or $override_config present); pass --budget to skip config entirely"
      exit 2
    fi

    if [ "$have_base" -eq 1 ] && ! jq -e . "$base_config" >/dev/null 2>&1; then
      err "invalid JSON in config file: $base_config"
      exit 2
    fi
    if [ "$have_override" -eq 1 ] && ! jq -e . "$override_config" >/dev/null 2>&1; then
      err "invalid JSON in config file: $override_config"
      exit 2
    fi

    if [ "$have_base" -eq 1 ] && [ "$have_override" -eq 1 ]; then
      effective_config="$(jq -s '.[0] * .[1]' "$base_config" "$override_config" 2>/dev/null)"
    elif [ "$have_base" -eq 1 ]; then
      effective_config="$(cat "$base_config")"
    else
      effective_config="$(cat "$override_config")"
    fi

    resolved="$(jq -r '
      (.delivery.prSizeBudget) as $b
      | if $b == null then "absent"
        elif ($b | type) == "number" and $b > 0 and ($b == ($b | floor)) then "valid:\($b | floor)"
        else "invalid"
        end
    ' <<<"$effective_config" 2>/dev/null)"

    case "$resolved" in
      absent) BUDGET=500 ;;
      valid:*) BUDGET="${resolved#valid:}" ;;
      *)
        err "delivery.prSizeBudget in the effective config is not a positive integer"
        exit 2
        ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
# Measure: git diff --numstat over the range, scoped to any pathspecs given
# after "--". git's own stderr surfaces verbatim on failure, never rewritten.
# ---------------------------------------------------------------------------
diff_args=("$positional")
if [ "$have_dashdash" -eq 1 ]; then
  diff_args+=(--)
  diff_args+=("${pathspecs[@]}")
fi

err_file="$(mktemp)"
diff_out="$(git -C "$REPO_ROOT" diff --numstat "${diff_args[@]}" 2>"$err_file")"
diff_status=$?
diff_err="$(cat "$err_file")"
rm -f "$err_file"

if [ "$diff_status" -ne 0 ]; then
  {
    printf 'ERROR: git diff --numstat failed for range %s\n' "$positional"
    printf '%s\n' "$diff_err"
  } >&2
  exit 2
fi

# Classify each numstat row: binary ("-"/"-") contributes 0 and is tracked
# separately; text rows sum into the total. Emits "F\t<count>\t<path>",
# "B\t<path>", and a final "TOTAL\t<n>" line.
parsed="$(printf '%s\n' "$diff_out" | awk -F'\t' '
  NF < 2 { next }
  $1 == "-" || $2 == "-" { print "B\t" $3; next }
  { total += $1 + $2; print "F\t" ($1 + $2) "\t" $3 }
  END { print "TOTAL\t" total + 0 }
')"

TOTAL=0
file_lines=()
binary_lines=()
while IFS=$'\t' read -r kind a b; do
  case "$kind" in
    TOTAL) TOTAL="$a" ;;
    B) binary_lines+=("$a") ;;
    F) file_lines+=("$a"$'\t'"$b") ;;
  esac
done <<< "$parsed"

# ---------------------------------------------------------------------------
# Compare and report.
# ---------------------------------------------------------------------------
over_budget=0
[ "$TOTAL" -gt "$BUDGET" ] && over_budget=1

status="PASS"
delta=0
if [ "$over_budget" -eq 1 ]; then
  delta=$((TOTAL - BUDGET))
  if [ "$justified" -eq 1 ]; then
    status="WARN"
  else
    status="FAIL"
  fi
fi

case "$status" in
  PASS) printf 'PASS  %s lines changed (budget %s)\n' "$TOTAL" "$BUDGET" ;;
  FAIL) printf 'FAIL  %s lines changed, over budget %s by %s\n' "$TOTAL" "$BUDGET" "$delta" ;;
  WARN) printf 'WARN  %s lines changed, over budget %s by %s — justified\n' "$TOTAL" "$BUDGET" "$delta" ;;
esac

if [ "$over_budget" -eq 1 ] && [ "${#file_lines[@]}" -gt 0 ]; then
  sorted_files="$(printf '%s\n' "${file_lines[@]}" | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2)"
  total_files=${#file_lines[@]}
  shown=0
  while IFS=$'\t' read -r count path; do
    shown=$((shown + 1))
    [ "$shown" -le 10 ] || continue
    printf '  %s  %s\n' "$count" "$path"
  done <<< "$sorted_files"
  if [ "$total_files" -gt 10 ]; then
    printf '  ... and %s more files\n' "$((total_files - 10))"
  fi
fi

if [ "${#binary_lines[@]}" -gt 0 ]; then
  sorted_binaries="$(printf '%s\n' "${binary_lines[@]}" | LC_ALL=C sort)"
  while IFS= read -r path; do
    printf '  binary  %s\n' "$path"
  done <<< "$sorted_binaries"
fi

if [ "$over_budget" -eq 1 ] && [ "$justified" -eq 0 ]; then
  exit 1
fi
exit 0
