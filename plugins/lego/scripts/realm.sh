#!/usr/bin/env bash
# realm.sh — single source of truth for the language-agnostic test-file family.
#
# <!--
# Contract: B03 realm-builtins-only (plan 001-lego-config-redesign)
# Behavior:   classification uses ONLY the built-in test-file family below;
#             the testPatterns config union is deleted.
# Inputs:     a file path (existing CLI shape unchanged).
# Outputs:    existing classification result, unchanged.
# Errors:     none new; exit 2 on usage error as today.
# Invariants: the built-in family never shrinks; no file reads, no jq, no
#             config, pure bash.
# Edge cases: paths that only matched via former testPatterns now classify
#             impl-family by design — orchestrator judgment covers them at
#             verification.
# -->
#
# Usage: realm.sh <path>
# Prints "test" or "impl" on stdout. Exit 2 on usage error.
#
# Test family (basename): *.spec.* | *.test.* | *_test.* | *_spec.* | test_*
# Test family (path):     any /__tests__/ segment
# No extension point:     the family is exactly the two rules above. No
#                         config file is read, no jq is invoked, and
#                         $LEGO_CONFIG is inert (B03 realm-builtins-only).
set -euo pipefail

path="${1:?usage: realm.sh <path>}"
base="$(basename -- "$path")"

case "/$path/" in
  */__tests__/*) echo test; exit 0 ;;
esac

case "$base" in
  *.spec.*|*.test.*|*_test.*|*_spec.*|test_*) echo test; exit 0 ;;
esac

echo impl
