#!/usr/bin/env bash
# realm.sh — single source of truth for the language-agnostic test-file family.
#
# Usage: realm.sh <path>
# Prints "test" or "impl" on stdout. Exit 2 on usage error.
#
# Test family (basename): *.spec.* | *.test.* | *_test.* | *_spec.* | test_*
# Test family (path):     any /__tests__/ segment
# Extension point:        "testPatterns" (basename or path globs) from the
#                         layered config (NEW, plan 001-lc): the UNION of
#                         .testPatterns in .claude/lego.json (committed
#                         base, read first) and .local/config.json (local
#                         override, read second), each file optional.
#                         Deliberate exception to the recursive-merge
#                         semantics used elsewhere: patterns are unioned,
#                         never replaced — the test-file family can only
#                         grow. Requires jq; silently skipped without it.
#                         $LEGO_CONFIG overrides the override file's
#                         location (default .local/config.json); the base
#                         path is fixed.
set -euo pipefail

path="${1:?usage: realm.sh <path>}"
base="$(basename -- "$path")"

case "/$path/" in
  */__tests__/*) echo test; exit 0 ;;
esac

case "$base" in
  *.spec.*|*.test.*|*_test.*|*_spec.*|test_*) echo test; exit 0 ;;
esac

config="${LEGO_CONFIG:-.local/config.json}"
if [ -f "$config" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$base" in $pat) echo test; exit 0 ;; esac
    case "$path" in $pat) echo test; exit 0 ;; esac
  done < <(jq -r '.testPatterns[]? // empty' "$config" 2>/dev/null)
fi

echo impl
