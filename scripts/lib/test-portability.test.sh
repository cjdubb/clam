#!/usr/bin/env bash
# test-portability.test.sh — contract tests for scripts/lib/test-portability.sh
# (B02 test-portability-helpers, plan 001-macos-test-portability).
#
# Black-box only: sources the library and calls tp_epoch_fmt,
# tp_parse_datetime and tp_shim_path through their public interfaces,
# asserting stdout bytes, exit codes and observable side effects (farm
# directory contents). No internal state is inspected.
#
# Portability: this suite itself must run identically on macOS/BSD and
# GNU/Linux, so it uses NO GNU-only constructs (`date -d`, `find -printf`,
# `grep -P`, in-place `sed -i` without a suffix). Expected timestamps are
# hard-coded literals rather than computed with the platform `date`, which
# is exactly what makes "identical bytes on both platforms" checkable.
#
# Mirrors the PASS/FAIL harness style of scripts/setup-hooks.test.sh.
#
# Run: bash scripts/lib/test-portability.test.sh  (exits non-zero on failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/test-portability.sh"

if [ ! -f "$LIB" ]; then
  echo "FATAL: library under test not found at $LIB" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$LIB"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}
check_ne() { # label got not-expected
  if [[ "$2" != "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected anything but '$3'"; FAILED=1
  fi
}

CLEANUP_MANIFEST="$(mktemp)"
track_tmp() { printf '%s\n' "$1" >> "$CLEANUP_MANIFEST"; }
cleanup() {
  if [ -f "$CLEANUP_MANIFEST" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] && [ -e "$d" ] && chmod u+rwx "$d" 2>/dev/null
      [ -n "$d" ] && [ -e "$d" ] && rm -rf -- "$d"
    done < "$CLEANUP_MANIFEST"
    rm -f -- "$CLEANUP_MANIFEST"
  fi
}
trap cleanup EXIT

# Capture stdout and rc of a call, stderr discarded (stubs print a
# NotImplemented banner there; that is not part of the contract).
OUT=""; RC=0
run() { OUT="$("$@" 2>/dev/null)"; RC=$?; return 0; }

FMT='+%Y-%m-%dT%H:%M:%SZ'

# ===========================================================================
# tp_epoch_fmt — Behavior / Outputs / Edge cases
# ===========================================================================
run tp_epoch_fmt 0 "$FMT"
check "01. epoch 0 rc" "$RC" "0"
check "01. epoch 0 formats as 1970-01-01" "$OUT" "1970-01-01T00:00:00Z"

run tp_epoch_fmt 1700000000 "$FMT"
check "02. normal epoch rc" "$RC" "0"
check "02. normal epoch fixed expected string" "$OUT" "2023-11-14T22:13:20Z"

run tp_epoch_fmt 1700000000 '+%Y-%m-%d'
check '03. format string is honoured (arg 2 required, used verbatim)' \
  "$OUT" "2023-11-14"

run tp_epoch_fmt 2147483648 "$FMT"
check "04. epoch > 2^31 rc" "$RC" "0"
check "04. epoch > 2^31 value" "$OUT" "2038-01-19T03:14:08Z"

# No trailing whitespace beyond the newline that $( ) strips.
run tp_epoch_fmt 1700000000 "$FMT"
check "05. no stray trailing whitespace" "$OUT" "${OUT% }"
check "05. no stray leading whitespace" "$OUT" "${OUT# }"

# ---- Errors -----------------------------------------------------------
run tp_epoch_fmt abc "$FMT"
check_ne "06. non-integer epoch is non-zero" "$RC" "0"
check "06. non-integer epoch has EMPTY stdout" "$OUT" ""

run tp_epoch_fmt -5 "$FMT"
check_ne "07. negative epoch is non-zero" "$RC" "0"
check "07. negative epoch has EMPTY stdout" "$OUT" ""

run tp_epoch_fmt "" "$FMT"
check_ne "08. empty epoch is non-zero" "$RC" "0"
check "08. empty epoch has EMPTY stdout" "$OUT" ""

run tp_epoch_fmt 1700000000
check_ne "09. missing format is non-zero (no default provided)" "$RC" "0"
check "09. missing format has EMPTY stdout" "$OUT" ""

# ---- Invariants: purity ----------------------------------------------
TZ_BEFORE="${TZ-<unset>}"; LC_BEFORE="${LC_ALL-<unset>}"
PWD_BEFORE="$PWD"
run tp_epoch_fmt 1700000000 "$FMT"
check "10. caller TZ untouched by tp_epoch_fmt" "${TZ-<unset>}" "$TZ_BEFORE"
check "10. caller LC_ALL untouched by tp_epoch_fmt" \
  "${LC_ALL-<unset>}" "$LC_BEFORE"
check "10. no directory side effect" "$PWD" "$PWD_BEFORE"

# TZ pinned internally: the same input under a non-UTC caller TZ still
# yields the same UTC bytes.
run env TZ=America/Los_Angeles bash -c \
  ". '$LIB'; tp_epoch_fmt 1700000000 '$FMT'"
check "11. output is TZ-independent (pinned to UTC)" \
  "$OUT" "2023-11-14T22:13:20Z"

# ===========================================================================
# tp_parse_datetime — Behavior / Outputs / Edge cases / Errors
# ===========================================================================
run tp_parse_datetime "1970-01-01 00:00:00"
check "12. parse epoch 0 rc" "$RC" "0"
check "12. parse epoch 0 value" "$OUT" "0"

run tp_parse_datetime "2023-11-14 22:13:20"
check "13. parse normal datetime rc" "$RC" "0"
check "13. parse normal datetime value (fixed expected)" "$OUT" "1700000000"

run tp_parse_datetime "2038-01-19 03:14:08"
check "14. parse > 2^31 datetime value" "$OUT" "2147483648"

# DST boundary in US/Pacific: parsing is UTC-pinned, so unaffected.
run tp_parse_datetime "2023-03-12 10:00:00"
check "15. DST-boundary datetime parses as UTC" "$OUT" "1678615200"

run env TZ=America/Los_Angeles bash -c \
  ". '$LIB'; tp_parse_datetime '2023-11-14 22:13:20'"
check "16. parse is TZ-independent (pinned to UTC)" "$OUT" "1700000000"

# ---- Errors -----------------------------------------------------------
for bad in "not a date" "2023-13-45 99:99:99" "2023-11-14" "" \
           "2023/11/14 22:13:20" "2016-12-31 23:59:60"; do
  run tp_parse_datetime "$bad"
  check_ne "17. malformed '$bad' is non-zero" "$RC" "0"
  check "17. malformed '$bad' has EMPTY stdout" "$OUT" ""
done

# ---- Invariants: purity + round-trip ----------------------------------
TZ_BEFORE="${TZ-<unset>}"; LC_BEFORE="${LC_ALL-<unset>}"
run tp_parse_datetime "2023-11-14 22:13:20"
check "18. caller TZ untouched by tp_parse_datetime" \
  "${TZ-<unset>}" "$TZ_BEFORE"
check "18. caller LC_ALL untouched by tp_parse_datetime" \
  "${LC_ALL-<unset>}" "$LC_BEFORE"

for dt in "1970-01-01 00:00:00" "2023-11-14 22:13:20" "2038-01-19 03:14:08"; do
  run bash -c \
    ". '$LIB'; e=\$(tp_parse_datetime '$dt') || exit 1; \
     tp_epoch_fmt \"\$e\" '+%Y-%m-%d %H:%M:%S'"
  check "19. round-trip parse->format for '$dt'" "$OUT" "$dt"
done

# ===========================================================================
# tp_shim_path — Behavior / Outputs / Errors / Invariants / Edge cases
# ===========================================================================
farm() { d="$(mktemp -d)"; track_tmp "$d"; printf '%s\n' "$d"; }

FARM1="$(farm)"
PATH_BEFORE="$PATH"
run tp_shim_path "$FARM1"
check "20. shim rc 0" "$RC" "0"
check "20. prints the farm dir (== \$1)" "$OUT" "$FARM1"
check "21. farm contains bash" \
  "$([ -e "$FARM1/bash" ] && echo yes || echo no)" "yes"
check "21. farm contains sh" \
  "$([ -e "$FARM1/sh" ] && echo yes || echo no)" "yes"
check "22. caller PATH never modified" "$PATH" "$PATH_BEFORE"

# Entries are usable as a restricted PATH.
run env PATH="$FARM1" bash -c 'echo alive'
check "23. farm is usable as a PATH (bash resolves)" "$OUT" "alive"

# Every farm entry is executable / non-dangling (skipped entries clause).
DANGLING=0
for e in "$FARM1"/*; do
  [ -e "$e" ] || { DANGLING=1; break; }
  [ -x "$e" ] || { DANGLING=1; break; }
done
check "24. no dangling or non-executable farm entries" "$DANGLING" "0"

# --- --remove of a command present in BOTH /bin and /usr/bin (and in a
# Homebrew dir when present): must be genuinely absent from the farm.
DUAL=""
for cand in bash sh echo pwd test kill ln cp; do
  if [ -x "/bin/$cand" ] && [ -x "/usr/bin/$cand" ]; then DUAL="$cand"; break; fi
done
if [ -z "$DUAL" ]; then
  # Fall back to any name resolvable in two distinct PATH dirs.
  DUAL="bash"
fi
FARM2="$(farm)"
run tp_shim_path "$FARM2" --remove "$DUAL"
check "25. --remove rc 0 (name '$DUAL')" "$RC" "0"
check "25. --remove hides dual-location '$DUAL' from the farm" \
  "$([ -e "$FARM2/$DUAL" ] && echo present || echo absent)" "absent"
check "25. --remove really unresolvable under farm PATH" \
  "$(PATH="$FARM2" command -v "$DUAL" >/dev/null 2>&1 && echo found || echo gone)" \
  "gone"
# Homebrew layouts: if the name also lives in a brew dir, it is still gone.
for brew in /opt/homebrew/bin /usr/local/bin; do
  if [ -x "$brew/$DUAL" ]; then
    check "26. --remove covers Homebrew copy at $brew/$DUAL" \
      "$([ -e "$FARM2/$DUAL" ] && echo present || echo absent)" "absent"
  fi
done

FARM3="$(farm)"
run tp_shim_path "$FARM3" --remove "definitely-not-a-real-command-xyz"
check "27. --remove of an absent name rc 0 (silent no-op)" "$RC" "0"
check "27. --remove of an absent name leaves bash in place" \
  "$([ -e "$FARM3/bash" ] && echo yes || echo no)" "yes"

# --- first-occurrence-wins: one link per name -------------------------
COUNT_BASH="$(find "$FARM1" -maxdepth 1 -name bash | wc -l | tr -d ' ')"
check "28. a multi-dir command is linked exactly once" "$COUNT_BASH" "1"
FIRST_BASH="$(PATH="$PATH_BEFORE" command -v bash 2>/dev/null)"
RESOLVED="$(cd "$FARM1" 2>/dev/null && readlink bash 2>/dev/null)"
check "29. first PATH occurrence wins for bash" "$RESOLVED" "$FIRST_BASH"

# --- idempotence -------------------------------------------------------
BEFORE_LIST="$(ls "$FARM1" 2>/dev/null)"
run tp_shim_path "$FARM1"
check "30. idempotent: rc 0 on re-run" "$RC" "0"
check "30. idempotent: same farm contents" "$(ls "$FARM1" 2>/dev/null)" \
  "$BEFORE_LIST"

# --- errors ------------------------------------------------------------
MISSING="$(farm)/nope-does-not-exist"
run tp_shim_path "$MISSING"
check_ne "31. missing outdir is non-zero" "$RC" "0"
check "31. missing outdir has EMPTY stdout" "$OUT" ""

run tp_shim_path
check_ne "32. no outdir argument is non-zero" "$RC" "0"
check "32. no outdir argument has EMPTY stdout" "$OUT" ""

if [ "$(id -u)" != "0" ]; then
  UNWRIT="$(farm)"
  chmod a-w "$UNWRIT"
  run tp_shim_path "$UNWRIT"
  check_ne "33. unwritable outdir is non-zero" "$RC" "0"
  check "33. unwritable outdir has EMPTY stdout" "$OUT" ""
  chmod u+w "$UNWRIT"
fi

FARM4="$(farm)"
run tp_shim_path "$FARM4" --remove
check_ne "34. --remove without a name is an error" "$RC" "0"
check "34. --remove without a name has EMPTY stdout" "$OUT" ""

# --- invariant: filesystem outside outdir untouched --------------------
OUTSIDE="$(farm)"
: > "$OUTSIDE/sentinel"
FARM5="$(farm)"
OUTSIDE_BEFORE="$(ls "$OUTSIDE")"
PATH_BEFORE2="$PATH"
run tp_shim_path "$FARM5" --remove bash
check "35. filesystem outside outdir untouched" "$(ls "$OUTSIDE")" \
  "$OUTSIDE_BEFORE"
check "35. real /bin/bash still present after --remove bash" \
  "$([ -x /bin/bash ] && echo yes || echo no)" "yes"
check "35. caller PATH still unmodified after --remove" \
  "$PATH" "$PATH_BEFORE2"

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
