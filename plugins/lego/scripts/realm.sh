#!/usr/bin/env bash
# realm.sh — single source of truth for the language-agnostic test-file family.
#
# Usage: realm.sh <path>
# Prints "test" or "impl" on stdout. Exit 2 on usage error.
#
# Test family (basename): *.spec.* | *.test.* | *_test.* | *_spec.* | test_*
# Test family (path):     any /__tests__/ segment
# Extension point:        .local/config.json "testPatterns" (basename or path
#                         globs; requires jq, silently skipped without it).
#                         Override config location with $LEGO_CONFIG.
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
