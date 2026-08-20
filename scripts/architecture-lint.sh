#!/bin/bash
# Architecture lint: flags cross-plugin references inside plugins/*/ so the
# sibling-blindness rule (ARCHITECTURE.md) is mechanically enforced.
#
# Run: bash scripts/architecture-lint.sh
#      (exits non-zero on any new reference or stale baseline entry)

# <!--
# Contract: B08 architecture-lint (plan 001-ensure-agents-understand-architecture)
#
# Behavior:
#   Scans every git-tracked text file under plugins/*/ for references from
#   the containing plugin P to any other plugin Q (P != Q), in exactly four
#   forms. Reports each hit and exits nonzero unless the hit is excused by
#   the allowlist, an allow-pragma, or the baseline. The plugin-name
#   vocabulary is discovered from the tree (the directory names under
#   plugins/), never hardcoded — except the fixed allowlist below.
#
#   The four reference forms (form-based matching ONLY — a bare plugin name
#   in prose is never a hit, so word-sense collisions like "landing
#   strategy" or a `build` command name cannot flag):
#     1. skill-invocation — `/<q>:<token>` (e.g. /tracking:make-progress)
#     2. marketplace-id   — `<q>@clam`
#     3. english          — `<q> plugin` with a word boundary before <q>
#                           (case-insensitive on the word "plugin")
#     4. path             — `plugins/<q>/`
#
#   Excusals, checked in this order per hit:
#     a. allowlist — P is `build` and Q is one of: landing, lego, tracking,
#        forge-github, forge-gitlab. Allowlisted hits are silent: not
#        reported, not required in the baseline.
#     b. pragma — the hit's own line contains `architecture-lint: allow`
#        followed by a non-empty reason (any comment syntax; the marker is
#        matched as a substring of the line). A pragma with an EMPTY reason
#        does not excuse and is itself reported as a defect.
#     c. baseline — scripts/architecture-lint-baseline.txt contains the
#        hit's triple (see Inputs). Baselined hits are counted but not
#        failed.
#
#   Shrink-only baseline: after scanning, every baseline triple with ZERO
#   current hits is reported as STALE and fails the run — the baseline can
#   only shrink or hold, never silently rot. New hits (no excusal) also
#   fail. Both failure kinds can be reported in one run.
#
# Inputs:
#   - The working tree (git ls-files under plugins/); requires git, bash,
#     grep. Run from anywhere inside the repo.
#   - scripts/architecture-lint-baseline.txt — line-number-free entries,
#     one per line: `<path>\t<form>\t<target-plugin>` where <path> is
#     repo-relative, <form> is one of skill-invocation|marketplace-id|
#     english|path, <target> is the referenced plugin. Duplicate hits of
#     the same triple in one file are covered by the one entry (that is
#     what line-number-free buys: edits that move lines never churn it).
#     `#`-comment lines and blank lines are ignored. Missing file = empty
#     baseline.
#
# Outputs:
#   - Per new hit:   `NEW  <path>:<line>: <form> reference to '<q>': <text>`
#   - Per stale row: `STALE  baseline entry has no matches: <path> <form> <q>`
#   - Per bad pragma: reported as a new hit with a note that the pragma
#     reason is empty.
#   - Summary line with counts (new / stale / baselined / pragma-excused).
#   - Exit 0: no new hits, no stale entries. Exit 1: any new hit or stale
#     entry. Exit 2: usage or environment error (not a git repo, missing
#     dependency, malformed baseline row).
#
# Errors:
#   - Not inside a git repository, or git/grep missing: diagnostic on
#     stderr, exit 2.
#   - A baseline row that is not a `#` comment, blank, or a well-formed
#     3-field triple: diagnostic naming the row, exit 2.
#
# Invariants:
#   - Read-only; never modifies the tree or the baseline.
#   - PERFORMANCE (B01, plan 001-speed-up-repo-ci): the four per-name regex
#     patterns depend ONLY on the plugin name — never on the file or the
#     line — so each is computed once per name and reused for the whole
#     scan. No subprocess may be spawned from inside the per-file or
#     per-line loops. Acceptance is mechanical and twofold: output must be
#     BYTE-IDENTICAL to the pre-change run (`0 new, 0 stale, 160 baselined`
#     on today's tree), and the full scan must spawn ZERO `sed` processes
#     (pre-change baseline: >20,000). Wall-clock is a consequence, not the
#     assertion: 66.5s before, 4.4s in the verified prototype.
#   - cwd-independent: resolves the repo root via git rev-parse and scans
#     from there; all reported paths are repo-relative.
#   - Scan scope is EXACTLY tracked files under plugins/*/ — repo-root
#     docs (ARCHITECTURE.md, CLAUDE.md, docs/, scripts/) are never
#     scanned and may name plugins freely. Untracked files under
#     plugins/ are not scanned but produce a WARN listing them.
#   - Self-references (P referencing P) are never hits in any form.
#   - Plugin names are matched with word boundaries: a plugin whose name
#     is a substring of another's never matches the longer name's text.
#   - Deterministic output: hits sorted by path then line; stale entries
#     in baseline order.
#
# Edge cases:
#   - Binary files (as judged by grep) are skipped silently.
#   - References inside code fences and HTML comments still count — an
#     example is still a reference; excuse deliberate ones via pragma.
#   - A hit line matching multiple forms yields one hit per form (each
#     form needs its own excusal).
#   - Empty plugins/ dir or no tracked files: clean pass, exit 0.
#   - Baseline entry for a file that no longer exists: STALE, exit 1.
# -->

set -uo pipefail

err() { printf 'ERROR: %s\n' "$1" >&2; }

command -v git >/dev/null 2>&1 || { err "git is required"; exit 2; }
command -v grep >/dev/null 2>&1 || { err "grep is required"; exit 2; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || { err "not inside a git repository"; exit 2; }

BASELINE_FILE="$REPO_ROOT/scripts/architecture-lint-baseline.txt"

ALLOWLIST_TARGETS_FOR_BUILD="landing lego tracking forge-github forge-gitlab"

# ---------------------------------------------------------------------------
# ERE-escape a literal string for embedding in a regex. Fork-free: bash
# parameter expansion only (no subprocess), so this can run in a hot loop.
# Escapes backslash first so escapes introduced for the other characters are
# never themselves re-escaped.
# ---------------------------------------------------------------------------
escape_re() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//./\\.}"
  s="${s//\[/\\[}"
  s="${s//\*/\\*}"
  s="${s//^/\\^}"
  s="${s//\$/\\\$}"
  s="${s//(/\\(}"
  s="${s//)/\\)}"
  s="${s//+/\\+}"
  s="${s//\?/\\?}"
  s="${s//\{/\\\{}"
  s="${s//\}/\\\}}"
  s="${s//|/\\|}"
  printf '%s' "$s"
}

BOUNDARY_BEFORE='(^|[^A-Za-z0-9_-])'
BOUNDARY_AFTER='([^A-Za-z0-9_-]|$)'
PLUGIN_WORD='[Pp][Ll][Uu][Gg][Ii][Nn]'
PLUGIN_SUFFIX="${PLUGIN_WORD}('[Ss]|[Ss])?"

skill_pat_for() { printf '/%s:[A-Za-z0-9_-]+' "$1"; }
mkt_pat_for()   { printf '%s%s@clam' "$BOUNDARY_BEFORE" "$1"; }
eng_pat_for()   { printf '%s%s[[:space:]]+%s%s' "$BOUNDARY_BEFORE" "$1" "$PLUGIN_SUFFIX" "$BOUNDARY_AFTER"; }
path_pat_for()  { printf 'plugins/%s/' "$1"; }

# ---------------------------------------------------------------------------
# PERFORMANCE (B01): the four per-name patterns depend only on the plugin
# name, never on the file or line, so each is computed exactly once per
# name here and reused for the whole scan -- nothing in the per-file or
# per-line loops below recomputes a pattern or forks a subprocess for it.
# Populated per-name lazily below, right after the vocabulary is known.
# ---------------------------------------------------------------------------
declare -A ESC_OF PAT_skill PAT_mkt PAT_eng PAT_path

# ---------------------------------------------------------------------------
# Discover scan scope (tracked files under plugins/<name>/...) and the
# plugin-name vocabulary (the <name> segment of those paths).
# ---------------------------------------------------------------------------
mapfile -t ALL_TRACKED < <(git -C "$REPO_ROOT" ls-files)

SCAN_FILES=()
for f in "${ALL_TRACKED[@]}"; do
  case "$f" in
    plugins/*/*) SCAN_FILES+=("$f") ;;
  esac
done

mapfile -t UNTRACKED_PLUGIN_FILES < <(git -C "$REPO_ROOT" ls-files --others --exclude-standard -- 'plugins/*' 2>/dev/null)
if [ "${#UNTRACKED_PLUGIN_FILES[@]}" -gt 0 ]; then
  printf 'WARN  %d untracked file(s) under plugins/ not scanned (stage them to include):\n' "${#UNTRACKED_PLUGIN_FILES[@]}"
  for uf in "${UNTRACKED_PLUGIN_FILES[@]}"; do
    printf '       %s\n' "$uf"
  done
fi

declare -A VOCAB_SET=()
for f in "${SCAN_FILES[@]}"; do
  rest="${f#plugins/}"
  name="${rest%%/*}"
  VOCAB_SET["$name"]=1
done
VOCAB=("${!VOCAB_SET[@]}")

# Compute each name's escape and four patterns exactly once, up front.
for q in "${VOCAB[@]}"; do
  esc="$(escape_re "$q")"
  ESC_OF["$q"]="$esc"
  PAT_skill["$q"]="$(skill_pat_for "$esc")"
  PAT_mkt["$q"]="$(mkt_pat_for "$esc")"
  PAT_eng["$q"]="$(eng_pat_for "$esc")"
  PAT_path["$q"]="$(path_pat_for "$esc")"
done

# ---------------------------------------------------------------------------
# Parse the baseline (line-number-free triples), preserving file order for
# stale reporting. Missing file = empty baseline. `#`-comments and blank
# lines are ignored. Anything else must be a well-formed 3-field triple.
# ---------------------------------------------------------------------------
BASE_PATHS=()
BASE_FORMS=()
BASE_TARGETS=()
declare -A BASELINE_SET=()

if [ -f "$BASELINE_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    nf="$(awk -F'\t' '{print NF}' <<< "$line")"
    if [ "$nf" -ne 3 ]; then
      err "malformed baseline row (expected 3 tab-separated fields): $line"
      exit 2
    fi
    parsed="$(awk -F'\t' '{print $1 "\x1f" $2 "\x1f" $3}' <<< "$line")"
    IFS=$'\x1f' read -r bpath bform btarget <<< "$parsed"
    if [ -z "$bpath" ] || [ -z "$bform" ] || [ -z "$btarget" ]; then
      err "malformed baseline row (empty field): $line"
      exit 2
    fi

    BASE_PATHS+=("$bpath")
    BASE_FORMS+=("$bform")
    BASE_TARGETS+=("$btarget")
    BASELINE_SET["${bpath}"$'\x1f'"${bform}"$'\x1f'"${btarget}"]=1
  done < "$BASELINE_FILE"
fi

# ---------------------------------------------------------------------------
# Pragma detection: a hit's own line containing `architecture-lint: allow`
# is excused only if followed by a non-empty (non-whitespace-only) reason.
# ---------------------------------------------------------------------------
PRAGMA_MARKER='architecture-lint: allow'
pragma_status() { # sets PRAGMA_PRESENT / PRAGMA_EXCUSES
  local text="$1"
  case "$text" in
    *"$PRAGMA_MARKER"*)
      PRAGMA_PRESENT=1
      local after="${text#*$PRAGMA_MARKER}"
      while [[ "$after" == [[:space:]]* ]]; do after="${after:1}"; done
      if [ -n "$after" ]; then
        PRAGMA_EXCUSES=1
      else
        PRAGMA_EXCUSES=0
      fi
      ;;
    *)
      PRAGMA_PRESENT=0
      PRAGMA_EXCUSES=0
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Scan. For each file, build the candidate-target alternation (vocabulary
# minus self, minus allowlisted targets when the owner is `build`), find
# candidate lines per form with one grep pass, then confirm the precise
# target(s) per candidate line with bash's regex engine (no further
# subprocesses) so multi-target lines are attributed correctly.
# ---------------------------------------------------------------------------
NEW_LINES=()
declare -A REACHED_BASELINE_STAGE=()
NEW_COUNT=0
BASELINED_COUNT=0
PRAGMA_COUNT=0

FORM_NAMES=(skill-invocation marketplace-id english path)

for path in "${SCAN_FILES[@]}"; do
  rest="${path#plugins/}"
  P="${rest%%/*}"

  names=()
  for q in "${VOCAB[@]}"; do
    [ "$q" = "$P" ] && continue
    if [ "$P" = "build" ]; then
      skip=0
      for a in $ALLOWLIST_TARGETS_FOR_BUILD; do
        [ "$q" = "$a" ] && { skip=1; break; }
      done
      [ "$skip" -eq 1 ] && continue
    fi
    names+=("$q")
  done
  [ "${#names[@]}" -eq 0 ] && continue

  esc_names=()
  for q in "${names[@]}"; do esc_names+=("${ESC_OF[$q]}"); done
  alt="$(IFS='|'; echo "${esc_names[*]}")"

  skill_alt="/(${alt}):[A-Za-z0-9_-]+"
  mkt_alt="${BOUNDARY_BEFORE}(${alt})@clam"
  eng_alt="${BOUNDARY_BEFORE}(${alt})[[:space:]]+${PLUGIN_SUFFIX}${BOUNDARY_AFTER}"
  path_alt="plugins/(${alt})/"

  abs="$REPO_ROOT/$path"

  declare -A CAND_LINES=()
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && CAND_LINES["$ln"]=1
  done < <(grep -n -I -E "$skill_alt" -- "$abs" 2>/dev/null)
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && CAND_LINES["$ln"]=1
  done < <(grep -n -I -E "$mkt_alt" -- "$abs" 2>/dev/null)
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && CAND_LINES["$ln"]=1
  done < <(grep -n -I -E "$eng_alt" -- "$abs" 2>/dev/null)
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && CAND_LINES["$ln"]=1
  done < <(grep -n -I -E "$path_alt" -- "$abs" 2>/dev/null)

  [ "${#CAND_LINES[@]}" -eq 0 ] && { unset CAND_LINES; continue; }

  mapfile -t FILE_LINES < "$abs"

  cand_sorted=("${!CAND_LINES[@]}")
  IFS=$'\n' cand_sorted=($(sort -n <<< "${cand_sorted[*]}")); unset IFS

  for ln in "${cand_sorted[@]}"; do
    text="${FILE_LINES[$((ln - 1))]:-}"

    pragma_status "$text"

    for q in "${names[@]}"; do
      for form in "${FORM_NAMES[@]}"; do
        case "$form" in
          skill-invocation) pat="${PAT_skill[$q]}" ;;
          marketplace-id)   pat="${PAT_mkt[$q]}" ;;
          english)          pat="${PAT_eng[$q]}" ;;
          path)             pat="${PAT_path[$q]}" ;;
        esac

        if [[ "$text" =~ $pat ]]; then
          if [ "$PRAGMA_PRESENT" -eq 1 ] && [ "$PRAGMA_EXCUSES" -eq 1 ]; then
            PRAGMA_COUNT=$((PRAGMA_COUNT + 1))
            continue
          fi

          key="${path}"$'\x1f'"${form}"$'\x1f'"${q}"
          REACHED_BASELINE_STAGE["$key"]=1

          if [ -n "${BASELINE_SET[$key]+x}" ]; then
            BASELINED_COUNT=$((BASELINED_COUNT + 1))
            continue
          fi

          NEW_COUNT=$((NEW_COUNT + 1))
          if [ "$PRAGMA_PRESENT" -eq 1 ] && [ "$PRAGMA_EXCUSES" -eq 0 ]; then
            NEW_LINES+=("$(printf "NEW  %s:%s: %s reference to '%s': %s (architecture-lint: allow pragma present but its reason is empty — does not excuse)" "$path" "$ln" "$form" "$q" "$text")")
          else
            NEW_LINES+=("$(printf "NEW  %s:%s: %s reference to '%s': %s" "$path" "$ln" "$form" "$q" "$text")")
          fi
        fi
      done
    done
  done

  unset CAND_LINES
done

# ---------------------------------------------------------------------------
# Stale baseline rows: any triple never reached during scanning (baseline
# order preserved).
# ---------------------------------------------------------------------------
STALE_LINES=()
STALE_COUNT=0
for i in "${!BASE_PATHS[@]}"; do
  bpath="${BASE_PATHS[$i]}"
  bform="${BASE_FORMS[$i]}"
  btarget="${BASE_TARGETS[$i]}"
  key="${bpath}"$'\x1f'"${bform}"$'\x1f'"${btarget}"
  if [ -z "${REACHED_BASELINE_STAGE[$key]+x}" ]; then
    STALE_COUNT=$((STALE_COUNT + 1))
    STALE_LINES+=("$(printf 'STALE  baseline entry has no matches: %s %s %s' "$bpath" "$bform" "$btarget")")
  fi
done

# ---------------------------------------------------------------------------
# Report.
# ---------------------------------------------------------------------------
for l in "${NEW_LINES[@]+"${NEW_LINES[@]}"}"; do
  printf '%s\n' "$l"
done
for l in "${STALE_LINES[@]+"${STALE_LINES[@]}"}"; do
  printf '%s\n' "$l"
done

printf 'Summary: %d new, %d stale, %d baselined, %d pragma-excused\n' \
  "$NEW_COUNT" "$STALE_COUNT" "$BASELINED_COUNT" "$PRAGMA_COUNT"

if [ "$NEW_COUNT" -gt 0 ] || [ "$STALE_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
