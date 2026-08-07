#!/bin/bash
# Runs shellcheck over the repo's shell sources and tests, gated by a
# shrink-only baseline of pre-existing violations.
#
# Run: bash scripts/shellcheck-lint.sh (exits non-zero on any new or stale finding)

# <!--
# Contract: B07 shellcheck-lint (plan 001-speed-up-repo-ci)
#
# Behavior:
#   Scans every git-tracked *.sh file in the repo — sources AND tests alike —
#   with shellcheck, and compares the findings against a shrink-only baseline
#   at scripts/shellcheck-baseline.txt. Reports each finding and exits nonzero
#   unless it is excused by the baseline.
#
#   Baseline semantics mirror architecture-lint.sh deliberately, so the two
#   gates behave identically for a reader who has learned either one:
#     - A finding present in the baseline is counted, not failed.
#     - A baseline entry with ZERO current findings is STALE and fails the
#       run: the baseline can only shrink or hold, never silently rot.
#     - Both failure kinds can be reported in a single run.
#
#   Entries are line-number-free so that edits which move code do not churn
#   the baseline.
#
# Inputs:
#   - The working tree (git ls-files '*.sh'); requires git and bash.
#     The shellcheck binary itself is OPTIONAL — see Invariants.
#   - scripts/shellcheck-baseline.txt — one entry per line:
#     `<path>\t<shellcheck-code>` (e.g. `scripts/ci.sh\tSC2086`). Duplicate
#     findings of the same (path, code) pair are covered by one entry.
#     `#`-comment lines and blank lines are ignored. Missing file = empty
#     baseline.
#   - No environment variables, no config files beyond the baseline. Reads
#     NOTHING from .claude/ or .local/.
#
# Outputs:
#   - Per new finding: `NEW  <path>:<line>: <code> <message>`
#   - Per stale row:   `STALE  baseline entry has no matches: <path> <code>`
#   - Summary line with counts (new / stale / baselined).
#   - Skip notice when shellcheck is absent: `WARN  shellcheck skipped
#     (shellcheck not found)` — exit 0.
#   - Exit 0: no new findings, no stale entries (or shellcheck absent).
#     Exit 1: any new finding or stale entry. Exit 2: usage or environment
#     error (not a git repo, malformed baseline row).
#
# Errors:
#   - Not inside a git repository: diagnostic on stderr, exit 2.
#   - A baseline row that is not a `#` comment, blank, or a well-formed
#     2-field pair: diagnostic naming the row, exit 2.
#   - Unknown flag: usage line on stderr, exit 2.
#
# Invariants:
#   - Read-only; never modifies the tree or the baseline.
#   - cwd-independent: resolves the repo root via git rev-parse and scans
#     from there; all reported paths are repo-relative.
#   - shellcheck's ABSENCE degrades to a WARN and exit 0, never a failure —
#     matching how ci.sh treats the claude and gh CLIs. Its PRESENCE gates.
#     This is what keeps ci.sh's "requires only bash+git+jq" promise true
#     while still enforcing the lint wherever shellcheck is installed.
#   - Scope is tracked *.sh files ONLY, with NO directory exclusions: the
#     scan is `git ls-files '*.sh'` over the whole repo, so tracked shell
#     under `.claude/` is IN scope like any other. The Inputs clause below
#     ("Reads NOTHING from .claude/ or .local/") constrains where this gate
#     takes CONFIGURATION from, not which files it scans — which is why it
#     names `.local/` too, a tree that is gitignored and therefore can never
#     be scanned in the first place. Ruled 2026-08-04 on U07-test-01's
#     escalation. This repo currently tracks no `*.sh` under any `.claude/`
#     directory, so the ruling does not change the baseline the
#     implementation wave generates; it is written down so a future one is
#     not silently wrong.
#   - Test files are in scope: they are
#     38,363 of the repo's shell lines and the class of bug shellcheck finds
#     (unquoted expansions, `local` masking exit codes) is exactly the class
#     that makes a test silently vacuous.
#   - Deterministic output: findings sorted by path then line; stale entries
#     in baseline order.
#   - Invoking shellcheck once over the full file list, not once per file:
#     this gate must not reintroduce the fork-per-file cost that plan 001
#     exists to remove.
#   - SC2317 and SC2329 are excluded at the invocation rather than baselined.
#     All instances in this repo are false positives from the test-harness
#     idiom (`run_test "$name" <fn>` dispatching through `"$@"`, `cleanup`
#     running from a `trap`), and baselining them would fail every new test
#     file for no real defect. No other code is excluded: suppression belongs
#     in the baseline, where it is visible and shrink-only.
#
# Edge cases:
#   - Repo with no tracked *.sh files: clean pass, exit 0, "no files to
#     check".
#   - Baseline entry for a file that no longer exists: STALE, exit 1.
#   - A file with multiple findings of the same code: covered by one baseline
#     entry; each occurrence is reported individually when not baselined.
#   - shellcheck present but erroring on its own (bad install, unreadable
#     file): treated as an environment error, exit 2 — never a silent pass.
# -->

set -uo pipefail

err() { printf 'ERROR: %s\n' "$1" >&2; }
usage() { echo "Usage: shellcheck-lint.sh" >&2; }

# No flags are accepted at all: any argument is an unknown flag.
if [ "$#" -gt 0 ]; then
  err "unknown flag: $1"
  usage
  exit 2
fi

command -v git >/dev/null 2>&1 || { err "git is required"; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT" ] || { err "not inside a git repository"; exit 2; }

BASELINE_FILE="$ROOT/scripts/shellcheck-baseline.txt"

# Scope: every git-tracked *.sh file, sources and tests alike, at any depth,
# with NO directory exclusions (tracked *.sh under .claude/ is in scope --
# see the Invariants amendment above). git's basename-style glob matching
# means this reaches nested files without **, and paths come back already
# repo-relative because git -C runs the query from ROOT regardless of cwd.
mapfile -t FILES < <(git -C "$ROOT" ls-files -- '*.sh')

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "no files to check"
  exit 0
fi

# ---------------------------------------------------------------------------
# Parse the baseline: line-number-free (path, code) pairs, one per line.
# Missing file = empty baseline. `#`-comments and blank lines are ignored.
# Anything else must be a well-formed 2-field pair. Mirrors
# architecture-lint.sh's baseline parsing deliberately.
# ---------------------------------------------------------------------------
BASE_PATHS=()
BASE_CODES=()
declare -A BASELINE_SET=()

if [ -f "$BASELINE_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    nf="$(awk -F'\t' '{print NF}' <<< "$line")"
    if [ "$nf" -ne 2 ]; then
      err "malformed baseline row (expected 2 tab-separated fields): $line"
      exit 2
    fi
    IFS=$'\t' read -r bpath bcode <<< "$line"
    if [ -z "$bpath" ] || [ -z "$bcode" ]; then
      err "malformed baseline row (empty field): $line"
      exit 2
    fi

    BASE_PATHS+=("$bpath")
    BASE_CODES+=("$bcode")
    BASELINE_SET["${bpath}"$'\x1f'"${bcode}"]=1
  done < "$BASELINE_FILE"
fi

# ---------------------------------------------------------------------------
# The shellcheck binary is OPTIONAL: absence degrades to a WARN and exit 0,
# exactly like ci.sh's treatment of the claude and gh CLIs. Presence gates.
# ---------------------------------------------------------------------------
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "WARN  shellcheck skipped (shellcheck not found)"
  exit 0
fi

# ---------------------------------------------------------------------------
# ONE invocation over the full file list -- never one per file. gcc format
# emits exactly one line per finding, colon-delimited with the code trailing
# in brackets: `path:line:col: level: message [SCxxxx]`. Running from ROOT
# with repo-relative argv paths means shellcheck echoes back repo-relative
# paths too, satisfying the cwd-independence invariant for free.
#
# SC2317 ("Command appears to be unreachable") and SC2329 ("This function is
# never invoked") are excluded at the invocation, not baselined. Every instance
# in this repo is a false positive from the test-harness idiom: `run_test
# "$name" <fn>` invokes each test function through `"$@"` and `cleanup` runs
# from a `trap`, neither of which the tool's reachability analysis can follow.
# Baselining them instead would make every new test file fail this check for no
# real defect, and the baseline's own rule forbids adding rows to fix that.
# ---------------------------------------------------------------------------
OUT_FILE="$(mktemp)"
ERR_FILE="$(mktemp)"
trap 'rm -f "$OUT_FILE" "$ERR_FILE"' EXIT

( cd "$ROOT" && shellcheck -f gcc --exclude=SC2317,SC2329 -- "${FILES[@]}" >"$OUT_FILE" 2>"$ERR_FILE" )
SC_EXIT=$?

# The tool's own exit codes: 0 clean, 1 findings reported. Anything else
# (bad install, unreadable file, its own usage error) is an environment
# error -- never a silent pass.
if [ "$SC_EXIT" -ne 0 ] && [ "$SC_EXIT" -ne 1 ]; then
  err "shellcheck exited with status $SC_EXIT (environment error)"
  [ -s "$ERR_FILE" ] && cat "$ERR_FILE" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Parse findings out of the gcc-format output.
# ---------------------------------------------------------------------------
GCC_RE='^(.+):([0-9]+):([0-9]+): (error|warning|note|info|style): (.*) \[(SC[0-9]+)\]$'
F_PATH=()
F_LINE=()
F_CODE=()
F_MSG=()

while IFS= read -r outline || [ -n "$outline" ]; do
  [ -n "$outline" ] || continue
  if [[ "$outline" =~ $GCC_RE ]]; then
    F_PATH+=("${BASH_REMATCH[1]}")
    F_LINE+=("${BASH_REMATCH[2]}")
    F_CODE+=("${BASH_REMATCH[6]}")
    F_MSG+=("${BASH_REMATCH[5]}")
  fi
done < "$OUT_FILE"

# ---------------------------------------------------------------------------
# Sort findings by path then line (deterministic output).
# ---------------------------------------------------------------------------
ORDER=()
if [ "${#F_PATH[@]}" -gt 0 ]; then
  mapfile -t ORDER < <(
    for i in "${!F_PATH[@]}"; do
      printf '%s\t%s\t%s\n' "${F_PATH[$i]}" "${F_LINE[$i]}" "$i"
    done | sort -t "$(printf '\t')" -k1,1 -k2,2n | cut -f3
  )
fi

declare -A REACHED=()
NEW_LINES=()
NEW_COUNT=0
BASELINED_COUNT=0

for i in "${ORDER[@]+"${ORDER[@]}"}"; do
  p="${F_PATH[$i]}"
  l="${F_LINE[$i]}"
  c="${F_CODE[$i]}"
  m="${F_MSG[$i]}"
  key="${p}"$'\x1f'"${c}"
  REACHED["$key"]=1

  if [ -n "${BASELINE_SET[$key]+x}" ]; then
    BASELINED_COUNT=$((BASELINED_COUNT + 1))
    continue
  fi

  NEW_COUNT=$((NEW_COUNT + 1))
  NEW_LINES+=("$(printf 'NEW  %s:%s: %s %s' "$p" "$l" "$c" "$m")")
done

# ---------------------------------------------------------------------------
# Stale baseline rows: entries with zero matching findings, in baseline
# order. The baseline can only shrink or hold, never silently rot.
# ---------------------------------------------------------------------------
STALE_LINES=()
STALE_COUNT=0
for i in "${!BASE_PATHS[@]}"; do
  bpath="${BASE_PATHS[$i]}"
  bcode="${BASE_CODES[$i]}"
  key="${bpath}"$'\x1f'"${bcode}"
  if [ -z "${REACHED[$key]+x}" ]; then
    STALE_COUNT=$((STALE_COUNT + 1))
    STALE_LINES+=("$(printf 'STALE  baseline entry has no matches: %s %s' "$bpath" "$bcode")")
  fi
done

for l in "${NEW_LINES[@]+"${NEW_LINES[@]}"}"; do
  printf '%s\n' "$l"
done
for l in "${STALE_LINES[@]+"${STALE_LINES[@]}"}"; do
  printf '%s\n' "$l"
done

printf 'Summary: %d new, %d stale, %d baselined\n' "$NEW_COUNT" "$STALE_COUNT" "$BASELINED_COUNT"

if [ "$NEW_COUNT" -gt 0 ] || [ "$STALE_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
