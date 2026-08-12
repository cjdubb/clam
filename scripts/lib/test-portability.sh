#!/usr/bin/env bash
# Portable test helpers: BSD-first date handling and PATH shim farms.
# Sourced by test suites; never used by production scripts.

# Contract: B02 test-portability-helpers / tp_epoch_fmt
# Behavior:   formats an epoch-seconds value as a UTC date string, preferring
#             BSD `date -r <epoch>` and falling back to GNU `date -d @<epoch>`.
# Inputs:     $1 epoch seconds (non-negative integer); $2 strftime format
#             string (e.g. "+%Y-%m-%dT%H:%M:%SZ", leading + required).
# Outputs:    the formatted string on stdout, no trailing whitespace beyond
#             the newline; identical bytes on macOS and Linux for the same
#             inputs (TZ pinned to UTC internally).
# Errors:     returns non-zero with EMPTY stdout when $1 is not a
#             non-negative integer or no usable date binary exists; never
#             emits a partial or empty-string timestamp on success paths.
# Invariants: pure — no globals mutated, no files touched; TZ/LC_ALL of the
#             caller are not modified.
# Edge cases: epoch 0 formats as 1970-01-01; values > 2^31 accepted where
#             the platform date supports them; missing format defaults are
#             NOT provided — $2 is required.
tp_epoch_fmt() {
  local epoch="${1-}" fmt="${2-}"
  case "$epoch" in
    "" | *[!0-9]*) return 2 ;;
  esac
  [ -n "$fmt" ] || return 2
  case "$fmt" in
    +*) ;;
    *) return 2 ;;
  esac
  local out
  if out="$(TZ=UTC LC_ALL=C date -r "$epoch" "$fmt" 2>/dev/null)" \
    && [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  if out="$(TZ=UTC LC_ALL=C date -d "@$epoch" "$fmt" 2>/dev/null)" \
    && [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  return 1
}

# Contract: B02 test-portability-helpers / tp_parse_datetime
# Behavior:   parses a calendar datetime string as UTC into epoch seconds,
#             preferring BSD `date -j -f '%Y-%m-%d %H:%M:%S'` and falling
#             back to GNU `date -d`.
# Inputs:     $1 datetime in exactly '%Y-%m-%d %H:%M:%S' form, interpreted
#             as UTC.
# Outputs:    epoch seconds (integer) on stdout; identical on macOS and
#             Linux for the same input.
# Errors:     returns non-zero with EMPTY stdout on any malformed input;
#             never guesses a partial parse.
# Invariants: pure; caller TZ/LC_ALL untouched; round-trips with
#             tp_epoch_fmt (parse then format yields the input datetime).
# Edge cases: leap seconds not supported (rejected as malformed); dates
#             around DST boundaries are unaffected because parsing is
#             pinned to UTC.
tp_parse_datetime() {
  local dt="${1-}"
  local re='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
  [[ "$dt" =~ $re ]] || return 2
  local mo="${dt:5:2}" da="${dt:8:2}" ho="${dt:11:2}" mi="${dt:14:2}"
  local se="${dt:17:2}"
  # Strip leading zeros for numeric comparison (10# forces base 10).
  (( 10#$mo >= 1 && 10#$mo <= 12 )) || return 2
  (( 10#$da >= 1 && 10#$da <= 31 )) || return 2
  (( 10#$ho <= 23 )) || return 2
  (( 10#$mi <= 59 )) || return 2
  (( 10#$se <= 59 )) || return 2
  local epoch=""
  if ! epoch="$(TZ=UTC LC_ALL=C date -j -f '%Y-%m-%d %H:%M:%S' \
      "$dt" +%s 2>/dev/null)"; then
    epoch=""
  fi
  if [ -z "$epoch" ]; then
    epoch="$(TZ=UTC LC_ALL=C date -d "$dt UTC" +%s 2>/dev/null)" || return 1
  fi
  case "$epoch" in
    "" | *[!0-9-]*) return 1 ;;
  esac
  # Reject rolled-over dates (e.g. 2023-02-30) by requiring a round-trip.
  local back
  back="$(tp_epoch_fmt "$epoch" '+%Y-%m-%d %H:%M:%S')" || return 1
  [ "$back" = "$dt" ] || return 2
  printf '%s\n' "$epoch"
}

# Contract: B02 test-portability-helpers / tp_shim_path
# Behavior:   builds a symlink farm of every executable found in every
#             directory of the caller's real PATH (first occurrence wins,
#             mirroring PATH resolution), then deletes each name given via
#             --remove, producing a directory usable as a restricted PATH
#             that genuinely lacks those commands on any platform layout
#             (/usr/bin-only farms miss /bin/bash on macOS; this does not).
# Inputs:     $1 outdir (existing, writable, empty or disposable); zero or
#             more `--remove <name>` pairs after it.
# Outputs:    prints the farm directory (== $1) on stdout; the farm always
#             contains `bash` and `sh` unless explicitly removed.
# Errors:     returns non-zero with empty stdout if outdir is missing or
#             unwritable; --remove without a following name is an error.
# Invariants: caller PATH is never modified; the real filesystem outside
#             outdir is never touched; idempotent for the same outdir.
# Edge cases: a --remove name absent from the farm is a silent no-op; a
#             command present in several PATH dirs is linked once (first
#             wins); non-executable or dangling entries are skipped.
tp_shim_path() {
  local outdir="${1-}"
  [ -n "$outdir" ] || return 2
  shift
  local -a removals=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --remove)
        [ "$#" -ge 2 ] || return 2
        [ -n "$2" ] || return 2
        removals+=("$2")
        shift 2
        ;;
      *) return 2 ;;
    esac
  done
  [ -d "$outdir" ] || return 2
  [ -w "$outdir" ] || return 2

  local dir entry name
  local saved_ifs="$IFS"
  IFS=:
  # shellcheck disable=SC2086
  set -- $PATH
  IFS="$saved_ifs"
  for dir in "$@"; do
    [ -n "$dir" ] || continue
    [ -d "$dir" ] || continue
    for entry in "$dir"/*; do
      [ -e "$entry" ] || continue
      [ -f "$entry" ] || continue
      [ -x "$entry" ] || continue
      name="${entry##*/}"
      [ -e "$outdir/$name" ] && continue
      [ -L "$outdir/$name" ] && continue
      ln -s "$entry" "$outdir/$name" 2>/dev/null || true
    done
  done

  for name in ${removals+"${removals[@]}"}; do
    rm -f -- "$outdir/$name"
  done

  printf '%s\n' "$outdir"
}
