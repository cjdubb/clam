#!/usr/bin/env bash
# realm-check.sh — verify a change-set stays within an expected realm.
#
# Usage: realm-check.sh <expected-realm: test|impl> [<diff-range>]
#   No diff-range: checks all uncommitted changes (staged, unstaged, untracked).
#   With a diff-range (e.g. HEAD~1..HEAD): checks files changed in that range.
#
# expected-realm=test: every changed file must be in the test family.
# expected-realm=impl: no changed file may be in the test family.
#
# Exit 0 when clean; exit 1 with one violation per line on stdout;
# exit 2 on usage error.
set -euo pipefail

expected="${1:?usage: realm-check.sh <test|impl> [diff-range]}"
range="${2:-}"
case "$expected" in
  test|impl) ;;
  *) echo "expected-realm must be 'test' or 'impl'" >&2; exit 2 ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

collect_files() {
  if [ -n "$range" ]; then
    git diff --name-only "$range"
  else
    { git diff --name-only HEAD 2>/dev/null || git diff --name-only --cached
      git ls-files --others --exclude-standard
    } | sort -u
  fi
}

violations=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  realm="$("$here/realm.sh" "$f")"
  if [ "$expected" = "test" ] && [ "$realm" != "test" ]; then
    echo "VIOLATION: non-test-family file changed in a test-realm change-set: $f"
    violations=$((violations + 1))
  elif [ "$expected" = "impl" ] && [ "$realm" = "test" ]; then
    echo "VIOLATION: test-family file changed in an impl-realm change-set: $f"
    violations=$((violations + 1))
  fi
done < <(collect_files)

if [ "$violations" -gt 0 ]; then
  echo "realm-check: $violations violation(s) against expected realm '$expected'"
  exit 1
fi
