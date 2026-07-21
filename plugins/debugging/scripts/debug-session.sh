#!/usr/bin/env bash
# Contract: B09 debug-session-script
#
# Behavior:
#   CLI managing the .local/debug/ artifact tree for a debugging session.
#   Two subcommands:
#     debug-session.sh start <slug>
#       Creates the next-numbered session dir .local/debug/NNN-<slug>/
#       containing journal.md (copied VERBATIM from this plugin's
#       templates/journal.md) and an empty queries/ subdir.
#     debug-session.sh query <session-dir> <name> [ext]
#       Creates the next-numbered query dir <session-dir>/queries/NN-<name>/
#       containing an empty query file query.<ext> (ext defaults to txt) and
#       results.md (copied VERBATIM from templates/query-results.md).
#
# Inputs:
#   <slug>, <name>: must match ^[a-z0-9][a-z0-9-]*$ (lowercase kebab).
#   <session-dir>:  path to an existing session dir that contains journal.md.
#   [ext]:          must match ^[a-z0-9]+$ (e.g. txt, sql, logql); default txt.
#   CWD:            `start` resolves .local/ relative to the current working
#                   directory; .local/ itself must already exist (it marks the
#                   repo/worktree root). Templates are resolved relative to
#                   THIS SCRIPT's location (../templates), never the CWD.
#
# Outputs:
#   stdout on success: exactly one line — the path of the directory created
#   (as resolvable from the CWD: .local/debug/NNN-<slug> for start;
#   <session-dir>/queries/NN-<name> for query). Exit 0.
#
# Numbering:
#   NNN: three-digit zero-padded, starts at 001; next = highest existing
#   NNN-* dir under .local/debug/ + 1, regardless of slug; non-matching
#   entries are ignored. NN: two-digit zero-padded, starts at 01, same rule
#   over <session-dir>/queries/. Numbering never reuses or fills gaps.
#
# Errors (every failure: exactly ONE `ERROR: <message>` line on stderr,
# exit 1, nothing on stdout, no partial artifacts left behind):
#   - unknown or missing subcommand; wrong arg count for the subcommand
#   - invalid slug / name / ext (pattern above)
#   - `start` when ./.local does not exist
#   - `query` when <session-dir> does not exist or lacks journal.md
#   - template file missing at the script-relative location
#
# Invariants:
#   - Never overwrites or modifies existing files or dirs; each call creates
#     exactly one new numbered dir plus its contracted contents.
#   - Writes only within .local/debug/ (start) or the given session dir's
#     queries/ (query).
#   - No network, no git commands; plain filesystem only.
#
# Edge cases:
#   - Numbering overflow past 999/99 is an error, not a wraparound.
#   - A .local/debug entry that is a file (not dir) is ignored for numbering.
#   - Spaces in CWD paths are handled (quote-safe throughout).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/../templates"
JOURNAL_TPL="$TEMPLATES_DIR/journal.md"
QUERY_TPL="$TEMPLATES_DIR/query-results.md"

USAGE_MSG="usage: debug-session.sh start <slug> | debug-session.sh query <session-dir> <name> [ext]"

err() { printf 'ERROR: %s\n' "$1" >&2; }
die() { err "$1"; exit 1; }

# valid_kebab <token> -- true iff <token> matches ^[a-z0-9][a-z0-9-]*$
valid_kebab() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

# valid_ext <token> -- true iff <token> matches ^[a-z0-9]+$
valid_ext() {
  [[ "$1" =~ ^[a-z0-9]+$ ]]
}

# next_number <dir> <digits> -- prints, on stdout, the zero-padded (to
# <digits> digits) next number for entries directly under <dir> whose
# basename matches ^[0-9]{digits}-.*  and which are directories (non-dirs
# and non-matching names are ignored). Starts at 1 when <dir> does not exist
# or has no matching entries. Prints nothing and returns 1 if the next
# number would exceed what <digits> digits can hold (overflow).
next_number() {
  local dir="$1" digits="$2"
  local max=0 entry base num limit re
  limit=$((10 ** digits - 1))
  re="^([0-9]{$digits})-"
  if [ -d "$dir" ]; then
    for entry in "$dir"/*; do
      [ -e "$entry" ] || continue
      [ -d "$entry" ] || continue
      base="$(basename -- "$entry")"
      if [[ "$base" =~ $re ]]; then
        num=$((10#${BASH_REMATCH[1]}))
        if (( num > max )); then
          max=$num
        fi
      fi
    done
  fi
  local next=$((max + 1))
  if (( next > limit )); then
    return 1
  fi
  printf '%0'"${digits}"'d' "$next"
  return 0
}

cmd_start() {
  [ "$#" -eq 1 ] || die "start requires exactly one argument: <slug>"
  local slug="$1"

  valid_kebab "$slug" || die "invalid slug: $slug"
  [ -d ".local" ] || die "./.local does not exist (run from the repo/worktree root)"
  [ -f "$JOURNAL_TPL" ] || die "template file missing: $JOURNAL_TPL"

  local debug_dir=".local/debug"
  local nnn
  nnn="$(next_number "$debug_dir" 3)" || die "session numbering overflow: no room past 999"

  local session_dir="$debug_dir/$nnn-$slug"

  mkdir -p -- "$debug_dir" || die "failed to create $debug_dir"
  mkdir -- "$session_dir" || die "failed to create $session_dir"
  if ! cp -- "$JOURNAL_TPL" "$session_dir/journal.md"; then
    rm -rf -- "$session_dir"
    die "failed to copy journal template into $session_dir"
  fi
  if ! mkdir -- "$session_dir/queries"; then
    rm -rf -- "$session_dir"
    die "failed to create $session_dir/queries"
  fi

  printf '%s\n' "$session_dir"
}

cmd_query() {
  { [ "$#" -eq 2 ] || [ "$#" -eq 3 ]; } || die "query requires <session-dir> <name> [ext]"
  local session_dir="$1" name="$2"
  local ext="${3-txt}"

  valid_kebab "$name" || die "invalid name: $name"
  valid_ext "$ext" || die "invalid ext: $ext"
  [ -d "$session_dir" ] || die "session dir does not exist: $session_dir"
  [ -f "$session_dir/journal.md" ] || die "session dir lacks journal.md: $session_dir"
  [ -f "$QUERY_TPL" ] || die "template file missing: $QUERY_TPL"

  local queries_dir="$session_dir/queries"
  local nn
  nn="$(next_number "$queries_dir" 2)" || die "query numbering overflow: no room past 99"

  local query_dir="$queries_dir/$nn-$name"

  mkdir -p -- "$queries_dir" || die "failed to create $queries_dir"
  mkdir -- "$query_dir" || die "failed to create $query_dir"
  if ! : > "$query_dir/query.$ext"; then
    rm -rf -- "$query_dir"
    die "failed to create $query_dir/query.$ext"
  fi
  if ! cp -- "$QUERY_TPL" "$query_dir/results.md"; then
    rm -rf -- "$query_dir"
    die "failed to copy query-results template into $query_dir"
  fi

  printf '%s\n' "$query_dir"
}

main() {
  [ "$#" -ge 1 ] || die "$USAGE_MSG"
  local sub="$1"
  shift
  case "$sub" in
    start) cmd_start "$@" ;;
    query) cmd_query "$@" ;;
    *) die "unknown subcommand: $sub ($USAGE_MSG)" ;;
  esac
}

main "$@"
