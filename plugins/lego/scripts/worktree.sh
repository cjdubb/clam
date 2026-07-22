#!/usr/bin/env bash
# worktree.sh — lego unit-worktree lifecycle helper.
#
# Contract: B01 layered-config-resolution (worktree.sh unit-worktree lifecycle)
#
# New/changed clauses in plan 001-layered-config are marked (NEW, plan 001-lc)
# or (CHANGED, plan 001-lc); every other clause is pre-existing behavior
# already covered by worktree_test.sh.
#
# Behavior:
#   Manages the git worktrees, branches, and delivery PRs for lego work
#   units. Run from the repo root of the integration worktree (the branch
#   lego was started on).
#
#   Config resolution (NEW, plan 001-lc):
#     The effective config is the jq recursive merge (.[0] * .[1]) of two
#     files at the repo root, both optional, override merged second:
#       .claude/lego.json   — committed base
#       .local/config.json  — gitignored local override (wins per key)
#     At least one must exist. commands.test in the effective config is
#     either a non-empty string (used verbatim as the test command) or an
#     object of named variants whose "default" field names the variant key
#     to use; that variant's value (a non-empty string) is the resolved
#     test command. delivery.worktreeDir is likewise read from the
#     effective config.
#
#   Subcommands:
#
#   add <plan-slug> <unit-id> <unit-slug>
#     Creates branch "lego/<plan-slug>/<unit-id>-<unit-slug>" at the current
#     HEAD plus a git worktree for it at
#     "<worktreeDir>/<repo-basename>-<unit-id>", where <worktreeDir> is
#     delivery.worktreeDir from the effective config (missing/empty → the
#     parent directory of the repo root; a relative value resolves against
#     the repo root) and <repo-basename> is the basename of the repo root.
#     Seeds the new worktree's .local/ directory:
#       - (CHANGED, plan 001-lc) .local/config.json copied verbatim only
#         when it exists in the integration worktree; its absence is not an
#         error (the committed base .claude/lego.json reaches the unit
#         worktree via git checkout)
#       - .local/unit.md: the single line "# Unit <unit-id>", then exactly
#         the "## B<NN> — ..." sections of the integration worktree's
#         .local/blocks.md whose "- Unit:" field equals <unit-id>, verbatim
#       - every .local/contracts/B<NN>-*.md whose B<NN> belongs to one of
#         those sections, copied to the same relative path (silently skipped
#         when no such file exists)
#       - .local/status.md: the unit status file, exactly
#         these lines in order —
#           "# Unit <unit-id> — status"
#           ""
#           "- Branch: <branch-name>"        (the branch created above)
#           "- Created from: <sha>"          (full 40-hex sha of the HEAD
#                                             the branch was created from)
#           "- Phase: Created"
#           ""
#           "## Blocks"
#           ""
#           one line per matched blocks.md section, in file order:
#           "- <heading minus the leading '## '>: <the section's '- Status:'
#           value, empty when that field is absent>"
#           ""
#           "## Timeline"
#           ""
#           "<!-- orchestrator appends one line per event -->"
#         ending with a trailing newline.
#       - .local/briefs/ and .local/reports/ created as
#         empty directories
#     (CHANGED, plan 001-lc) Then runs the resolved test command (per
#     "Config resolution" above) inside the new worktree
#     as a baseline check. On success prints the new worktree's absolute path
#     as the LAST line of stdout and exits 0.
#
#   merge <plan-slug> <unit-id> <unit-slug>
#     From the integration worktree: constructs the exact branch name
#     "lego/<plan-slug>/<unit-id>-<unit-slug>", verifies it exists, and
#     merges it into the current branch with --no-ff and commit message
#     "lego: merge <branch-name>". Refuses when the working tree has
#     uncommitted tracked changes.
#     After a successful merge, removes the unit's worktree as a best-effort
#     cleanup (via find_worktree_for_branch + git worktree remove). The unit
#     branch is NOT removed — deliver may still need it. If worktree removal
#     fails (dirty tree, already absent, etc.), prints a warning to stderr
#     and still exits 0: the merge succeeded and that is what matters.
#
#   deliver --manifest <path> <plan-slug> <base-branch> <unit-id> <unit-slug> [<unit-id> <unit-slug>...]
#     Builds a delivery branch from <base-branch> in a temporary worktree.
#
#     --manifest <path> is required. <path> must be a readable JSON file
#     (validated with jq). The manifest provides PR content and branch naming.
#     Required fields: "title" (non-empty), "branch" (non-empty), and for
#     each delivered unit-id, "commits.<unit-id>.impl" (non-empty). Optional
#     fields: "body" (falls back to blocks.md headings + contracts) and
#     "commits.<unit-id>.tests" (falls back to the default subject).
#
#     Manifest JSON schema:
#       {
#         "title":   "<PR title string>",           (required, non-empty)
#         "body":    "<PR body markdown>",           (optional)
#         "branch":  "<delivery branch name>",       (required, non-empty)
#         "commits": {
#           "<unit-id>": {
#             "tests": "<commit subject for tests>", (optional)
#             "impl":  "<commit subject for impl>"   (required, non-empty)
#           }
#         }
#       }
#
#     For each unit, in argument order:
#       - constructs the exact unit branch name
#         "lego/<plan-slug>/<unit-id>-<unit-slug>" and verifies it exists;
#         reads the unit's block paths: the comma-separated "- Code:" entries of
#         every blocks.md section whose "- Unit:" equals the unit id, each
#         path trimmed of surrounding spaces
#       - finds on the unit branch the newest commit with subject exactly
#         "lego(<unit-id>): tests" and the newest with subject exactly
#         "lego(<unit-id>): implementation"; the implementation commit is
#         required, the tests commit is optional (untested prose units)
#       - when the tests commit exists: restores the block paths from it and
#         commits with subject "lego(<unit-id>): contract + tests"; then
#         restores the block paths from the implementation commit and commits
#         with the impl subject (from the manifest, required). A restore that
#         produces no changes creates no commit.
#     Pushes the delivery branch to the "origin" remote and opens a PR
#     against <base-branch> with `gh pr create` using the title (from the
#     manifest, required) and body (from the manifest or default). Removes
#     the temporary worktree (the local delivery branch remains) and prints
#     the PR URL as the LAST line of stdout.
#     After a successful PR creation, removes each delivered unit's branch
#     and any remaining worktree as a best-effort cleanup. For each unit-id:
#     resolves the unit branch, finds its worktree (if any) and removes it
#     via git worktree remove, then deletes the branch with git branch -d.
#     Failures are warned on stderr but do not fail the deliver (the PR is
#     already open). The local delivery branch (lego/deliver/...) is left
#     intact.
#
#   remove <plan-slug> <unit-id> <unit-slug>
#     Constructs the exact branch name
#     "lego/<plan-slug>/<unit-id>-<unit-slug>", verifies it exists, then
#     removes the unit's worktree via `git worktree remove` (fails on a dirty
#     tree) and deletes its branch with `git branch -d` (fails when unmerged).
#
#   clean
#     Removes all fully-merged lego branches and their worktrees. Lists
#     every local branch matching "lego/*/*" or "lego/deliver/*/*" that is
#     merged into HEAD. For each: removes its worktree (if any) via
#     git worktree remove, then deletes the branch with git branch -d.
#     Also runs git worktree prune to clean up stale worktree entries.
#     Unmerged branches are skipped with a warning on stderr. Prints the
#     count of removed branches as the last stdout line. Takes no arguments.
#     Exits 0 always (best-effort). Exit 2 on unexpected arguments.
#
# Inputs:
#   Positional arguments as above. (CHANGED, plan 001-lc) The effective
#   config per "Config resolution": .claude/lego.json and/or
#   .local/config.json (jq-parsed and merged; commands.test required and
#   resolvable; delivery.worktreeDir optional). .local/blocks.md
#   with "- Unit:" and "- Code:" fields per block section. Must run inside a
#   git work tree, at the repo root.
#
# Outputs:
#   Human-readable progress on stderr only. Machine-consumable result — the
#   worktree path (add), PR URL (deliver), or count of removed branches
#   (clean) — as the last stdout line. Exit 0 on success.
#
# Errors:
#   exit 2 — usage error: unknown subcommand, wrong argument count, or an id/
#            slug containing characters outside [A-Za-z0-9._-]; prints usage
#            to stderr.
#   exit 3 — missing dependency or input: jq absent; gh absent (deliver
#            only); (CHANGED, plan 001-lc) no config file exists (neither
#            .claude/lego.json nor .local/config.json), a present config
#            file is not valid JSON, or commands.test is unresolvable in
#            the effective config (absent/empty; object without "default";
#            "default" naming an absent or empty variant);
#            .local/blocks.md missing; not inside a git work tree; --manifest
#            not provided (deliver); manifest file unreadable or not valid
#            JSON; manifest missing required field (title, branch, or
#            per-unit impl commit subject).
#   exit 4 — state error: unit-id matches no blocks.md section (add/deliver);
#            branch or worktree path already exists (add); constructed
#            unit branch does not exist (merge/deliver/remove); dirty working
#            tree (merge); baseline test failure (add); required
#            implementation commit missing (deliver); delivery branch already
#            exists (deliver); unmerged branch (remove); underlying git/gh
#            failure.
#   Every error prints exactly one line starting "ERROR: " to stderr.
#
# Invariants:
#   - Files in the invoking worktree are modified only by `merge`, and only
#     through `git merge` itself; no subcommand edits files there directly.
#   - `add` cleans up everything it created in the same invocation on any
#     failure: no half-created branch, worktree, or seed survives.
#   - Only creates or deletes branches under "lego/" and worktrees it created
#     itself; all other branches and worktrees are untouched.
#   - Deterministic: identical repo state and arguments produce identical
#     names and results.
#   - status.md content derives only from repository state
#     and arguments — never wall-clock time or randomness.
#   - (NEW, plan 001-lc) Config files are read-only inputs: no subcommand
#     ever writes .claude/lego.json or the integration worktree's
#     .local/config.json.
#   - `merge` may also remove the unit worktree as a best-effort side
#     effect; a removal failure never changes merge's exit code.
#   - `deliver` may also remove unit branches and worktrees as a best-effort
#     side effect; a removal failure never changes deliver's exit code.
#
# Edge cases:
#   - (NEW, plan 001-lc) Only one of the two config files exists: it alone
#     is the effective config; nothing is required of the absent file.
#   - (NEW, plan 001-lc) Merge semantics are jq's recursive merge (*):
#     nested objects merge per key with the override winning; arrays and
#     scalars are replaced whole by the override, never concatenated.
#   - (NEW, plan 001-lc) An object-form commands.test's variants are all
#     keys except "default"; "default" is a key reference, never itself a
#     command string.
#   - (NEW, plan 001-lc) A unit worktree seeded without .local/config.json
#     (no override present in the integration worktree) still resolves its
#     config from the checked-out .claude/lego.json.
#   - Multiple blocks sharing one unit: unit.md carries all their sections;
#     deliver restores the union of their Code paths;
#     status.md carries one "## Blocks" line per section, in file order.
#   - Code paths containing spaces are preserved verbatim (comma is the only
#     separator in a "- Code:" list).
#   - Repeated `add` or `deliver` for the same unit fails (exit 4); existing
#     artifacts are never silently reused.
#   - "body" and per-unit "commits.<id>.tests" remain individually optional,
#     falling back to their defaults when absent; "title", "branch", and
#     per-unit "commits.<id>.impl" are required (exit 3 when missing).
#   - A manifest "branch" that already exists as a local branch triggers
#     exit 4.
#   - A unit whose blocks have no "- Code:" paths cannot be delivered
#     (treated as unit-id matching no deliverable content, exit 4).
#   - merge cleanup failure (dirty unit worktree, already removed, etc.)
#     is warned on stderr and does not affect the merge exit code.
#   - deliver cleanup failure (unmerged branch, dirty worktree, etc.)
#     is warned on stderr and does not affect the deliver exit code.
#   - clean with no lego branches: exits 0 and prints "0".
set -uo pipefail

# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

USAGE_MSG="usage: worktree.sh add <plan-slug> <unit-id> <unit-slug> | worktree.sh merge <plan-slug> <unit-id> <unit-slug> | worktree.sh deliver --manifest <path> <plan-slug> <base-branch> <unit-id> <unit-slug> [<unit-id> <unit-slug>...] | worktree.sh remove <plan-slug> <unit-id> <unit-slug> | worktree.sh clean"

# err/die print the single mandated "ERROR: " stderr line. Only ever call
# these from a function invoked as a plain statement (never from inside a
# $(...) command substitution) -- exit inside a substitution's subshell would
# only kill that subshell, not the script.
err() { printf 'ERROR: %s\n' "$1" >&2; }
die() { err "$2"; exit "$1"; }
usage_die() { die 2 "$USAGE_MSG"; }

valid_token() {
  case "$1" in
    '') return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

REPO_ROOT=""
require_repo_root() {
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$REPO_ROOT" ]; then
    die 3 "must be run inside a git work tree"
  fi
}

require_jq() {
  command -v jq >/dev/null 2>&1 || die 3 "jq is required"
}

require_gh() {
  command -v gh >/dev/null 2>&1 || die 3 "gh is required"
}

# EFFECTIVE_CONFIG holds the resolved config as a JSON string (piped into
# jq via stdin by callers below, never written to disk). require_config_json
# computes the jq recursive merge (.[0] * .[1]) of the base
# (.claude/lego.json) and override (.local/config.json) layers, both
# optional, at least one required. A present-but-invalid-JSON file is exit 3.
EFFECTIVE_CONFIG=""
BASE_CONFIG_JSON=""
OVERRIDE_CONFIG_JSON=""
require_config_json() {
  BASE_CONFIG_JSON="$REPO_ROOT/.claude/lego.json"
  OVERRIDE_CONFIG_JSON="$REPO_ROOT/.local/config.json"

  local have_base=0 have_override=0
  [ -f "$BASE_CONFIG_JSON" ] && have_base=1
  [ -f "$OVERRIDE_CONFIG_JSON" ] && have_override=1

  if [ "$have_base" -eq 0 ] && [ "$have_override" -eq 0 ]; then
    die 3 "missing config: neither .claude/lego.json nor .local/config.json exists"
  fi

  if [ "$have_base" -eq 1 ] && ! jq -e . "$BASE_CONFIG_JSON" >/dev/null 2>&1; then
    die 3 "invalid JSON in .claude/lego.json"
  fi
  if [ "$have_override" -eq 1 ] && ! jq -e . "$OVERRIDE_CONFIG_JSON" >/dev/null 2>&1; then
    die 3 "invalid JSON in .local/config.json"
  fi

  if [ "$have_base" -eq 1 ] && [ "$have_override" -eq 1 ]; then
    EFFECTIVE_CONFIG="$(jq -s '.[0] * .[1]' "$BASE_CONFIG_JSON" "$OVERRIDE_CONFIG_JSON" 2>/dev/null)"
  elif [ "$have_base" -eq 1 ]; then
    EFFECTIVE_CONFIG="$(cat "$BASE_CONFIG_JSON")"
  else
    EFFECTIVE_CONFIG="$(cat "$OVERRIDE_CONFIG_JSON")"
  fi
}

TEST_CMD=""
require_test_cmd() {
  local raw_type
  raw_type="$(jq -r '.commands.test | type' <<<"$EFFECTIVE_CONFIG" 2>/dev/null)"

  case "$raw_type" in
    string)
      TEST_CMD="$(jq -r '.commands.test' <<<"$EFFECTIVE_CONFIG" 2>/dev/null)"
      [ -n "$TEST_CMD" ] || die 3 "commands.test is an empty string in the effective config"
      ;;
    object)
      local default_key
      default_key="$(jq -r '.commands.test.default // empty' <<<"$EFFECTIVE_CONFIG" 2>/dev/null)"
      [ -n "$default_key" ] || die 3 "commands.test is an object without a 'default' key in the effective config"
      TEST_CMD="$(jq -r --arg k "$default_key" '.commands.test[$k] // empty' <<<"$EFFECTIVE_CONFIG" 2>/dev/null)"
      [ -n "$TEST_CMD" ] || die 3 "commands.test.default names an absent or empty variant in the effective config"
      ;;
    *)
      die 3 "commands.test missing or empty in the effective config"
      ;;
  esac
}

BLOCKS_MD=""
require_blocks_md() {
  BLOCKS_MD="$REPO_ROOT/.local/blocks.md"
  [ -f "$BLOCKS_MD" ] || die 3 "missing .local/blocks.md"
}

# construct_unit_branch <plan-slug> <unit-id> <unit-slug> -- constructs the
# exact branch name "lego/<plan-slug>/<unit-id>-<unit-slug>" and verifies it
# exists as a local branch. Returns 0 and prints the branch name on stdout,
# or returns 1 if the branch does not exist. Never calls die/exit (safe to
# invoke via $(...)).
#
# Contract: B01 worktree-plan-scoping (construct_unit_branch)
# Behavior:   Constructs a deterministic branch name from the three
#             components and confirms it exists as a local ref.
# Inputs:     plan-slug, unit-id, unit-slug — all must be valid tokens
#             (validated by the caller, not by this function).
# Outputs:    On success (exit 0): prints the branch name
#             "lego/<plan-slug>/<unit-id>-<unit-slug>" on stdout.
#             On failure (exit 1): prints nothing.
# Errors:     exit 1 — branch does not exist.
# Invariants: Pure lookup; never creates, deletes, or modifies any ref.
#             Deterministic: same inputs always produce the same branch name.
# Edge cases: Does not validate token format (caller's responsibility).
#             Does not call die/exit — safe inside $(...) substitution.
construct_unit_branch() {
  local plan_slug="$1" unit_id="$2" unit_slug="$3"
  local branch="lego/$plan_slug/$unit_id-$unit_slug"
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    printf '%s\n' "$branch"
    return 0
  fi
  return 1
}

# find_worktree_for_branch <branch> -- prints the worktree path with that
# branch checked out, or nothing if none. Never calls die/exit.
find_worktree_for_branch() {
  local branch="$1"
  git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | awk -v want="refs/heads/$branch" '
    /^worktree / { wt = substr($0, 10) }
    /^branch /   { if (substr($0, 8) == want) { print wt; exit } }
  '
}

# newest_commit_with_subject <branch> <exact-subject> -- prints the sha of
# the newest commit on <branch> whose subject equals <exact-subject> exactly,
# or nothing if none. Never calls die/exit.
newest_commit_with_subject() {
  local branch="$1" subject="$2"
  local sha subj
  while IFS=$'\t' read -r sha subj; do
    if [ "$subj" = "$subject" ]; then
      printf '%s' "$sha"
      return 0
    fi
  done < <(git -C "$REPO_ROOT" log --format='%H%x09%s' "$branch" 2>/dev/null)
  return 0
}

# ---------------------------------------------------------------------------
# blocks.md parsing
# ---------------------------------------------------------------------------

# read_blocks_sections <blocks.md-path> <unit-id> -- populates globals for
# every "## B<NN> - ..." section whose "- Unit:" field equals <unit-id>, in
# file order:
#   MATCHED_SECTIONS  full verbatim section text (heading through the line
#                     before the next heading or EOF), one array item each
#   MATCHED_BLOCK_IDS "B<NN>" token from the heading
#   MATCHED_HEADINGS  the heading line itself
#   MATCHED_CODE      the raw "- Code:" value (may be empty)
#   MATCHED_CONTRACT  the full "- Contract:" line (may be empty)
#   MATCHED_STATUS    the raw "- Status:" value (may be empty)
read_blocks_sections() {
  local file="$1" unit_filter="$2"
  MATCHED_SECTIONS=(); MATCHED_BLOCK_IDS=(); MATCHED_HEADINGS=()
  MATCHED_CODE=(); MATCHED_CONTRACT=(); MATCHED_STATUS=()

  local cur_id="" cur_unit="" cur_text="" cur_heading="" cur_code="" cur_contract="" cur_status=""
  local in_section=0
  local line
  local -a lines=()
  mapfile -t lines < "$file"
  lines+=("## __END__")

  for line in "${lines[@]}"; do
    if [[ "$line" == "## "* ]]; then
      if [ "$in_section" -eq 1 ] && [ "$cur_unit" = "$unit_filter" ]; then
        MATCHED_SECTIONS+=("$cur_text")
        MATCHED_BLOCK_IDS+=("$cur_id")
        MATCHED_HEADINGS+=("$cur_heading")
        MATCHED_CODE+=("$cur_code")
        MATCHED_CONTRACT+=("$cur_contract")
        MATCHED_STATUS+=("$cur_status")
      fi
      cur_heading="$line"
      cur_id="${line#"## "}"
      cur_id="${cur_id%% *}"
      cur_unit=""
      cur_code=""
      cur_contract=""
      cur_status=""
      cur_text="$line"$'\n'
      in_section=1
      continue
    fi
    cur_text+="$line"$'\n'
    case "$line" in
      "- Unit: "*) cur_unit="${line#"- Unit: "}" ;;
      "- Code: "*) cur_code="${line#"- Code: "}" ;;
      "- Contract: "*) cur_contract="$line" ;;
      "- Status: "*) cur_status="${line#"- Status: "}" ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------

# seed_contracts <new-worktree> <block-id>... -- copies every
# .local/contracts/B<NN>-*.md for the given block ids into the new worktree;
# silently skips block ids with no such file. Returns 1 on a copy failure.
seed_contracts() {
  local new_wt="$1"; shift
  local block_id f have=0
  for block_id in "$@"; do
    for f in "$REPO_ROOT/.local/contracts/${block_id}-"*.md; do
      [ -e "$f" ] || continue
      if [ "$have" -eq 0 ]; then
        mkdir -p -- "$new_wt/.local/contracts" || return 1
        have=1
      fi
      cp -- "$f" "$new_wt/.local/contracts/$(basename -- "$f")" || return 1
    done
  done
  return 0
}

add_cleanup() {
  local wt="$1" branch="$2"
  if [ -n "$wt" ]; then
    git -C "$REPO_ROOT" worktree remove --force -- "$wt" >/dev/null 2>&1
    rm -rf -- "$wt" 2>/dev/null
  fi
  if [ -n "$branch" ]; then
    git -C "$REPO_ROOT" branch -D -- "$branch" >/dev/null 2>&1
  fi
}

cmd_add() {
  [ "$#" -eq 3 ] || usage_die
  local plan_slug="$1" unit_id="$2" unit_slug="$3"
  if ! valid_token "$plan_slug" || ! valid_token "$unit_id" || ! valid_token "$unit_slug"; then
    usage_die
  fi

  require_repo_root
  require_jq
  require_config_json
  require_test_cmd
  require_blocks_md

  local worktree_dir
  worktree_dir="$(jq -r '.delivery.worktreeDir // empty' <<<"$EFFECTIVE_CONFIG" 2>/dev/null)"

  local base_dir
  if [ -z "$worktree_dir" ]; then
    base_dir="$REPO_ROOT/.."
  else
    case "$worktree_dir" in
      /*) base_dir="$worktree_dir" ;;
      *) base_dir="$REPO_ROOT/$worktree_dir" ;;
    esac
  fi
  base_dir="$(realpath -m -- "$base_dir")"

  local new_wt branch
  new_wt="$base_dir/$(basename -- "$REPO_ROOT")-$unit_id"
  branch="lego/$plan_slug/$unit_id-$unit_slug"

  read_blocks_sections "$BLOCKS_MD" "$unit_id"
  if [ "${#MATCHED_SECTIONS[@]}" -eq 0 ]; then
    die 4 "no blocks.md section found for unit $unit_id"
  fi

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    die 4 "branch $branch already exists"
  fi

  if [ -e "$new_wt" ]; then
    die 4 "worktree path already exists: $new_wt"
  fi

  if ! git -C "$REPO_ROOT" worktree add -q -b "$branch" "$new_wt" HEAD >/dev/null 2>&1; then
    git -C "$REPO_ROOT" branch -D -- "$branch" >/dev/null 2>&1
    rm -rf -- "$new_wt" 2>/dev/null
    die 4 "failed to create worktree for unit $unit_id"
  fi

  local seed_ok=1
  mkdir -p -- "$new_wt/.local" 2>/dev/null || seed_ok=0
  if [ "$seed_ok" -eq 1 ] && [ -f "$OVERRIDE_CONFIG_JSON" ]; then
    cp -- "$OVERRIDE_CONFIG_JSON" "$new_wt/.local/config.json" 2>/dev/null || seed_ok=0
  fi
  if [ "$seed_ok" -eq 1 ]; then
    {
      printf '# Unit %s\n\n' "$unit_id"
      local s
      for s in "${MATCHED_SECTIONS[@]}"; do
        printf '%s' "$s"
      done
    } > "$new_wt/.local/unit.md" 2>/dev/null || seed_ok=0
  fi
  if [ "$seed_ok" -eq 1 ]; then
    seed_contracts "$new_wt" "${MATCHED_BLOCK_IDS[@]}" || seed_ok=0
  fi
  if [ "$seed_ok" -eq 1 ]; then
    local created_from
    created_from="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"
    if [ -z "$created_from" ]; then
      seed_ok=0
    fi
  fi
  if [ "$seed_ok" -eq 1 ]; then
    {
      printf '# Unit %s — status\n' "$unit_id"
      printf '\n'
      printf -- '- Branch: %s\n' "$branch"
      printf -- '- Created from: %s\n' "$created_from"
      printf -- '- Phase: Created\n'
      printf '\n'
      printf '## Blocks\n'
      printf '\n'
      local i heading_rest
      for i in "${!MATCHED_HEADINGS[@]}"; do
        heading_rest="${MATCHED_HEADINGS[$i]#"## "}"
        printf -- '- %s: %s\n' "$heading_rest" "${MATCHED_STATUS[$i]}"
      done
      printf '\n'
      printf '## Timeline\n'
      printf '\n'
      printf '%s\n' "<!-- orchestrator appends one line per event -->"
    } > "$new_wt/.local/status.md" 2>/dev/null || seed_ok=0
  fi
  if [ "$seed_ok" -eq 1 ]; then
    mkdir -p -- "$new_wt/.local/briefs" "$new_wt/.local/reports" 2>/dev/null || seed_ok=0
  fi

  if [ "$seed_ok" -ne 1 ]; then
    add_cleanup "$new_wt" "$branch"
    die 4 "failed to seed .local in new worktree for unit $unit_id"
  fi

  if ! ( cd "$new_wt" && eval "$TEST_CMD" ) >/dev/null 2>&1; then
    add_cleanup "$new_wt" "$branch"
    die 4 "baseline test command failed in new worktree"
  fi

  printf '%s\n' "$new_wt"
}

# ---------------------------------------------------------------------------
# merge
# ---------------------------------------------------------------------------

cmd_merge() {
  [ "$#" -eq 3 ] || usage_die
  local plan_slug="$1" unit_id="$2" unit_slug="$3"
  if ! valid_token "$plan_slug" || ! valid_token "$unit_id" || ! valid_token "$unit_slug"; then
    usage_die
  fi

  require_repo_root

  local branch rc
  branch="$(construct_unit_branch "$plan_slug" "$unit_id" "$unit_slug")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    die 4 "no branch found for unit $unit_id"
  fi

  local dirty
  dirty="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no 2>/dev/null)"
  if [ -n "$dirty" ]; then
    die 4 "working tree has uncommitted tracked changes"
  fi

  if ! git -C "$REPO_ROOT" merge --no-ff -m "lego: merge $branch" -- "$branch" >/dev/null 2>&1; then
    git -C "$REPO_ROOT" merge --abort >/dev/null 2>&1
    die 4 "merge of $branch failed"
  fi

  local wt_path
  wt_path="$(find_worktree_for_branch "$branch")"
  if [ -n "$wt_path" ]; then
    if ! git -C "$REPO_ROOT" worktree remove -- "$wt_path" >/dev/null 2>&1; then
      err "failed to remove worktree for unit $unit_id after merge (dirty?)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# deliver
# ---------------------------------------------------------------------------

# restore_and_commit <worktree> <sha> <subject> <path>... -- restores <path>s
# from <sha> and commits with <subject> if that produced a diff. Returns 1 on
# an underlying git failure, 0 otherwise (including the no-op case).
restore_and_commit() {
  local wt="$1" sha="$2" subject="$3"; shift 3
  local -a paths=("$@")
  [ "${#paths[@]}" -gt 0 ] || return 0

  if ! git -C "$wt" checkout -q "$sha" -- "${paths[@]}" >/dev/null 2>&1; then
    return 1
  fi
  if git -C "$wt" diff --cached --quiet -- "${paths[@]}" 2>/dev/null; then
    return 0
  fi
  if ! git -C "$wt" commit -q -m "$subject" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# manifest_field <manifest-path> <jq-filter> -- extracts a field from the
# manifest JSON. Prints the value (raw, no JSON quotes) to stdout. Prints
# nothing and returns 0 if the field is null/absent. Returns 0 always (the
# manifest was already validated at parse time).
#
# Contract (B01 deliver-manifest, plan 001):
#   Behavior: Reads a single field from a validated JSON manifest file using
#     the given jq filter. Returns the raw string value (jq -r). When the
#     field is null or absent, prints nothing. Caller uses the empty-string
#     result to decide whether to fall back to the default value.
#   Inputs: $1 = path to a valid JSON file; $2 = jq filter expression.
#   Outputs: The field value on stdout (raw), or empty string if null/absent.
#   Errors: None (manifest validity is checked before this is called).
#   Invariants: Pure read — never modifies the manifest file.
#   Edge cases: A field whose value is the empty string "" is returned as
#     empty, same as null — callers treat both as "not provided".
manifest_field() {
  local manifest="$1" filter="$2"
  local val
  val="$(jq -r "$filter // empty" "$manifest" 2>/dev/null)"
  printf '%s' "$val"
}

# Contract: B01 manifest-required (plan 001-require-deliver-manifest)
#   Behavior: Validates that a deliver manifest contains all required fields.
#     Dies exit 3 if any required field is missing or empty.
#   Inputs: $1 = manifest file path (must be readable, valid JSON — caller
#     validates this before calling). Remaining args = unit-ids to check
#     commits.<unit-id>.impl against.
#   Outputs: Returns 0 if all required fields are present and non-empty.
#   Errors: exit 3 with descriptive message naming the missing field when
#     any required field is absent or empty-string.
#   Invariants: The manifest file is never modified (read-only).
#     The "body" field remains optional (auto-generated fallback is acceptable).
#     Per-unit "tests" commit subject remains optional (untested prose units).
#   Edge cases: A field present but set to empty string ("") is treated as
#     absent (same as manifest_field's null/empty contract). A field set to
#     whitespace-only is treated as present (no trimming beyond what jq does).
validate_manifest_required_fields() {
  local manifest="$1"; shift

  local title
  title="$(manifest_field "$manifest" '.title')"
  [ -n "$title" ] || die 3 "manifest missing required field: title"

  local branch
  branch="$(manifest_field "$manifest" '.branch')"
  [ -n "$branch" ] || die 3 "manifest missing required field: branch"

  local uid impl
  for uid in "$@"; do
    impl="$(manifest_field "$manifest" ".commits[\"$uid\"].impl")"
    [ -n "$impl" ] || die 3 "manifest missing required field: commits.$uid.impl"
  done

  return 0
}

deliver_cleanup() {
  local tmp_wt="$1" tmp_parent="$2" branch="$3"
  if [ -n "$tmp_wt" ]; then
    git -C "$REPO_ROOT" worktree remove --force -- "$tmp_wt" >/dev/null 2>&1
  fi
  if [ -n "$tmp_parent" ]; then
    rm -rf -- "$tmp_parent" 2>/dev/null
  fi
  if [ -n "$branch" ]; then
    git -C "$REPO_ROOT" branch -D -- "$branch" >/dev/null 2>&1
  fi
}

cmd_deliver() {
  # ---- Parse required --manifest flag before positional args ----
  local manifest_path=""
  if [ "$#" -ge 2 ] && [ "$1" = "--manifest" ]; then
    manifest_path="$2"
    shift 2
  fi

  if [ -z "$manifest_path" ]; then
    die 3 "--manifest is required for deliver"
  fi

  [ "$#" -ge 4 ] || usage_die
  local plan_slug="$1" base_branch="$2"; shift 2
  # Remaining args are <unit-id> <unit-slug> pairs.
  [ $(( $# % 2 )) -eq 0 ] || usage_die

  if ! valid_token "$plan_slug" || ! valid_token "$base_branch"; then
    usage_die
  fi

  local -a unit_ids=() unit_slugs=()
  while [ "$#" -ge 2 ]; do
    if ! valid_token "$1" || ! valid_token "$2"; then
      usage_die
    fi
    unit_ids+=("$1")
    unit_slugs+=("$2")
    shift 2
  done

  require_repo_root
  require_jq
  require_config_json
  require_blocks_md
  require_gh

  # ---- Validate manifest ----
  if [ ! -r "$manifest_path" ]; then
    die 3 "manifest file not readable: $manifest_path"
  fi
  if ! jq empty "$manifest_path" >/dev/null 2>&1; then
    die 3 "manifest file is not valid JSON: $manifest_path"
  fi
  validate_manifest_required_fields "$manifest_path" "${unit_ids[@]}"

  # ---- Resolve delivery branch name (from the manifest) ----
  local delivery_branch u
  delivery_branch="$(manifest_field "$manifest_path" '.branch')"

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$delivery_branch"; then
    die 4 "delivery branch $delivery_branch already exists"
  fi

  # ---- Pass 1: resolve and validate everything, read-only ----
  local -a UNIT_TESTS_SHA=() UNIT_IMPL_SHA=() UNIT_PATHS_JOINED=()
  local -a ALL_HEADINGS=() ALL_CONTRACTS=()

  local idx_resolve=0
  for u in "${unit_ids[@]}"; do
    local branch rc
    branch="$(construct_unit_branch "$plan_slug" "$u" "${unit_slugs[$idx_resolve]}")"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      die 4 "no branch found for unit $u"
    fi

    read_blocks_sections "$BLOCKS_MD" "$u"
    if [ "${#MATCHED_SECTIONS[@]}" -eq 0 ]; then
      die 4 "no blocks.md section found for unit $u"
    fi

    local -a unit_paths=()
    local i code_val part
    for i in "${!MATCHED_CODE[@]}"; do
      ALL_HEADINGS+=("${MATCHED_HEADINGS[$i]}")
      ALL_CONTRACTS+=("${MATCHED_CONTRACT[$i]}")
      code_val="${MATCHED_CODE[$i]}"
      if [ -n "$code_val" ]; then
        local -a parts=()
        IFS=',' read -ra parts <<< "$code_val"
        for part in "${parts[@]}"; do
          unit_paths+=("$(trim "$part")")
        done
      fi
    done

    if [ "${#unit_paths[@]}" -eq 0 ]; then
      die 4 "unit $u has no Code paths to deliver"
    fi
    UNIT_PATHS_JOINED+=("$(printf '%s\n' "${unit_paths[@]}")")

    local tests_sha impl_sha
    tests_sha="$(newest_commit_with_subject "$branch" "lego($u): tests")"
    impl_sha="$(newest_commit_with_subject "$branch" "lego($u): implementation")"
    if [ -z "$impl_sha" ]; then
      die 4 "unit $u is missing the required implementation commit"
    fi
    UNIT_TESTS_SHA+=("$tests_sha")
    UNIT_IMPL_SHA+=("$impl_sha")
    idx_resolve=$((idx_resolve + 1))
  done

  # ---- Pass 2: build the delivery branch in a temporary worktree ----
  local tmp_parent tmp_wt
  tmp_parent="$(mktemp -d)"
  tmp_wt="$tmp_parent/wt"

  if ! git -C "$REPO_ROOT" worktree add -q -b "$delivery_branch" "$tmp_wt" "$base_branch" >/dev/null 2>&1; then
    deliver_cleanup "" "$tmp_parent" "$delivery_branch"
    die 4 "failed to create delivery branch from $base_branch"
  fi

  local idx=0 build_failed=0
  for u in "${unit_ids[@]}"; do
    local -a unit_paths=()
    mapfile -t unit_paths <<< "${UNIT_PATHS_JOINED[$idx]}"
    local tests_sha="${UNIT_TESTS_SHA[$idx]}"
    local impl_sha="${UNIT_IMPL_SHA[$idx]}"

    # Resolve commit subjects: the impl subject is required from the
    # manifest (validated non-empty); the tests subject remains optional,
    # falling back to the hardcoded default when the manifest omits it.
    local tests_subject="lego($u): contract + tests"
    local impl_subject=""
    local mt mi
    mt="$(manifest_field "$manifest_path" ".commits[\"$u\"].tests")"
    mi="$(manifest_field "$manifest_path" ".commits[\"$u\"].impl")"
    [ -n "$mt" ] && tests_subject="$mt"
    impl_subject="$mi"

    if [ -n "$tests_sha" ]; then
      restore_and_commit "$tmp_wt" "$tests_sha" "$tests_subject" "${unit_paths[@]}"
      if [ "$?" -ne 0 ]; then
        build_failed=1
        break
      fi
    fi

    restore_and_commit "$tmp_wt" "$impl_sha" "$impl_subject" "${unit_paths[@]}"
    if [ "$?" -ne 0 ]; then
      build_failed=1
      break
    fi

    idx=$((idx + 1))
  done

  if [ "$build_failed" -eq 1 ]; then
    deliver_cleanup "$tmp_wt" "$tmp_parent" "$delivery_branch"
    die 4 "failed to build delivery branch content"
  fi

  if ! git -C "$REPO_ROOT" push -q origin "$delivery_branch" >/dev/null 2>&1; then
    deliver_cleanup "$tmp_wt" "$tmp_parent" "$delivery_branch"
    die 4 "failed to push $delivery_branch to origin"
  fi

  # Resolve PR title (required, from the manifest) and body (optional,
  # falling back to the auto-generated headings+contracts default).
  local pr_title=""
  local pr_body=""
  local n
  for n in "${!ALL_HEADINGS[@]}"; do
    pr_body="${pr_body}${ALL_HEADINGS[$n]}"$'\n'
    if [ -n "${ALL_CONTRACTS[$n]}" ]; then
      pr_body="${pr_body}${ALL_CONTRACTS[$n]}"$'\n'
    fi
    pr_body="${pr_body}"$'\n'
  done

  local mtitle mbody
  mtitle="$(manifest_field "$manifest_path" '.title')"
  mbody="$(manifest_field "$manifest_path" '.body')"
  pr_title="$mtitle"
  [ -n "$mbody" ] && pr_body="$mbody"

  local pr_url
  pr_url="$(cd "$REPO_ROOT" && gh pr create --base "$base_branch" --head "$delivery_branch" --title "$pr_title" --body "$pr_body" 2>/dev/null)"
  local gh_rc=$?

  if [ "$gh_rc" -ne 0 ] || [ -z "$pr_url" ]; then
    deliver_cleanup "$tmp_wt" "$tmp_parent" "$delivery_branch"
    die 4 "gh pr create failed"
  fi

  git -C "$REPO_ROOT" worktree remove --force -- "$tmp_wt" >/dev/null 2>&1
  rm -rf -- "$tmp_parent" 2>/dev/null

  printf '%s\n' "$pr_url"

  local idx_cleanup=0
  for u in "${unit_ids[@]}"; do
    local ubranch urc
    ubranch="$(construct_unit_branch "$plan_slug" "$u" "${unit_slugs[$idx_cleanup]}")"
    urc=$?
    if [ "$urc" -ne 0 ]; then
      err "failed to resolve branch for unit $u during post-deliver cleanup"
      idx_cleanup=$((idx_cleanup + 1))
      continue
    fi

    local uwt
    uwt="$(find_worktree_for_branch "$ubranch")"
    if [ -n "$uwt" ]; then
      if ! git -C "$REPO_ROOT" worktree remove -- "$uwt" >/dev/null 2>&1; then
        err "failed to remove worktree for unit $u after deliver (dirty?)"
      fi
    fi

    if ! git -C "$REPO_ROOT" branch -d -- "$ubranch" >/dev/null 2>&1; then
      err "failed to delete branch $ubranch after deliver (unmerged?)"
    fi
    idx_cleanup=$((idx_cleanup + 1))
  done
}

# ---------------------------------------------------------------------------
# remove
# ---------------------------------------------------------------------------

cmd_remove() {
  [ "$#" -eq 3 ] || usage_die
  local plan_slug="$1" unit_id="$2" unit_slug="$3"
  if ! valid_token "$plan_slug" || ! valid_token "$unit_id" || ! valid_token "$unit_slug"; then
    usage_die
  fi

  require_repo_root

  local branch rc
  branch="$(construct_unit_branch "$plan_slug" "$unit_id" "$unit_slug")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    die 4 "no branch found for unit $unit_id"
  fi

  local wt_path
  wt_path="$(find_worktree_for_branch "$branch")"

  if [ -n "$wt_path" ]; then
    if ! git -C "$REPO_ROOT" worktree remove -- "$wt_path" >/dev/null 2>&1; then
      die 4 "failed to remove worktree for unit $unit_id (dirty?)"
    fi
  fi

  if ! git -C "$REPO_ROOT" branch -d -- "$branch" >/dev/null 2>&1; then
    die 4 "failed to delete branch $branch (unmerged?)"
  fi
}

# ---------------------------------------------------------------------------
# clean
# ---------------------------------------------------------------------------

cmd_clean() {
  [ "$#" -eq 0 ] || usage_die

  require_repo_root

  local -a candidates=()
  mapfile -t candidates < <(
    git -C "$REPO_ROOT" branch --list --format='%(refname:short)' \
      'lego/*/*' 'lego/deliver/*/*' 2>/dev/null | sort -u
  )

  local -a merged=()
  mapfile -t merged < <(
    git -C "$REPO_ROOT" branch --list --format='%(refname:short)' --merged HEAD 2>/dev/null
  )

  local count=0
  local b
  for b in "${candidates[@]}"; do
    [ -n "$b" ] || continue

    local is_merged=0
    local m
    for m in "${merged[@]}"; do
      if [ "$m" = "$b" ]; then
        is_merged=1
        break
      fi
    done
    if [ "$is_merged" -ne 1 ]; then
      err "skipping unmerged lego branch $b"
      continue
    fi

    local wt_path
    wt_path="$(find_worktree_for_branch "$b")"
    if [ -n "$wt_path" ]; then
      if ! git -C "$REPO_ROOT" worktree remove -- "$wt_path" >/dev/null 2>&1; then
        err "failed to remove worktree for branch $b (dirty?)"
        continue
      fi
    fi

    if ! git -C "$REPO_ROOT" branch -d -- "$b" >/dev/null 2>&1; then
      err "failed to delete branch $b"
      continue
    fi

    count=$((count + 1))
  done

  git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1

  printf '%d\n' "$count"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
  [ "$#" -ge 1 ] || usage_die
  local sub="$1"
  shift
  case "$sub" in
    add) cmd_add "$@" ;;
    merge) cmd_merge "$@" ;;
    deliver) cmd_deliver "$@" ;;
    remove) cmd_remove "$@" ;;
    clean) cmd_clean "$@" ;;
    *) usage_die ;;
  esac
}

main "$@"
