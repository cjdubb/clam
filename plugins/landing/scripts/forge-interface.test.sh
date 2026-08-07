#!/bin/bash
# Structural test for the B04 forge-interface specification
# (plugins/landing/docs/forge-interface.md). This document IS the
# deliverable -- a spec, not code -- so this test checks for the
# presence of its required clauses (naming convention, both forge
# operations, formatting conventions, delegation, standalone guarantee,
# dependency direction, and the no-other-plugin-references invariant),
# not exact prose.
#
# All content checks run against the file with HTML comment blocks (the
# contract docblock) stripped out first. The docblock already describes
# every required clause in detail -- including the forbidden words
# lego/build/tracking, named as an example of what NOT to reference --
# so a check against the raw file (docblock included) could pass on the
# unimplemented stub for the wrong reason, or never be able to fail for
# the invariant checks. Stripping ensures every check can only be
# satisfied (or violated) by the actual spec content that replaces the
# NotImplemented marker.
# Run: bash plugins/landing/scripts/forge-interface.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC="$PLUGIN_DIR/docs/forge-interface.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

strip_comments() { # file
  awk '/<!--/{c=1} !c{print} /-->/{c=0}' "$1" 2>/dev/null
}

BODY="$(strip_comments "$SPEC")"

has_literal() { # needle
  printf '%s' "$BODY" | grep -qF -- "$1" && echo yes || echo no
}

has_pattern_ci() { # extended-regex
  printf '%s' "$BODY" | grep -qiE -- "$1" && echo yes || echo no
}

check "spec file exists" "$([[ -f "$SPEC" ]] && echo yes || echo no)" "yes"

# 1. No NotImplemented marker in the rendered spec body.
check "no NotImplemented marker in spec body" \
  "$(has_pattern_ci 'NotImplemented')" "no"

# 2. Naming convention: forge-<forge>, identified from the origin
#    remote, with forge-github and forge-gitlab as named examples.
check "naming convention: forge-github example" "$(has_literal 'forge-github')" "yes"
check "naming convention: forge-gitlab example" "$(has_literal 'forge-gitlab')" "yes"
check "naming convention: identified from the origin remote" \
  "$(has_pattern_ci 'origin remote')" "yes"

# 3. Required operations: create-pr and sync-pr, each a forge-plugin
#    skill.
check "create-pr operation documented" "$(has_literal 'create-pr')" "yes"
check "sync-pr operation documented" "$(has_literal 'sync-pr')" "yes"
check "operations described as skills" "$(has_pattern_ci '\bskill')" "yes"

# 4. Formatting conventions binding every forge implementation's
#    composed output.
check "flowing-paragraph convention" "$(has_pattern_ci 'flowing')" "yes"
check "never-hard-wrapped convention" "$(has_pattern_ci 'hard-wrap')" "yes"
check "structural-boundary line-break convention" \
  "$(has_pattern_ci 'structural boundar')" "yes"
check "imperative one-line title convention" "$(has_pattern_ci 'imperative')" "yes"
check "reviewer-facing description convention" "$(has_pattern_ci 'reviewer')" "yes"
check "no internal workflow terminology convention" \
  "$(has_pattern_ci 'workflow terminology')" "yes"

# 5. Delegation: /landing:land selects and invokes the forge plugin
#    matching the repo's remote, passing the base branch, the default
#    body template, and content context; falls back to the built-in
#    path when none is installed.
check "delegation names /landing:land" "$(has_literal '/landing:land')" "yes"
check "delegation passes the base branch via merge.target" \
  "$(has_literal 'merge.target')" "yes"
check "delegation passes the default body template" \
  "$(has_pattern_ci 'pr-body-template')" "yes"
check "delegation passes the content context" \
  "$(has_pattern_ci 'content context')" "yes"
check "delegation names the built-in fallback" "$(has_pattern_ci 'built-in')" "yes"

# 6. Standalone guarantee: forge plugins never require landing (or any
#    other plugin) to be installed.
check "standalone guarantee documented" "$(has_pattern_ci 'standalone')" "yes"
check "forge plugins never require landing" \
  "$(has_pattern_ci 'never require')" "yes"

# 7. Invariant: dependency direction is landing -> forge plugin; a forge
#    plugin never invokes landing.
check "forge plugin never invokes landing" \
  "$(has_pattern_ci 'never invoke')" "yes"

# 8. Invariant: the spec never references lego, build, tracking, or any
#    other non-forge plugin. Checked against the stripped body only --
#    the contract docblock names these words explicitly as forbidden,
#    so this can only be a meaningful check with the docblock removed.
check "spec does not reference the lego plugin" "$(has_pattern_ci '\blego\b')" "no"
check "spec does not reference the build plugin" "$(has_pattern_ci '\bbuild\b')" "no"
check "spec does not reference the tracking plugin" "$(has_pattern_ci '\btracking\b')" "no"

# 9. Edge cases: no forge plugin installed -> the built-in path applies
#    the same formatting conventions itself; multiple forge plugins
#    installed -> the one matching the origin remote wins, no match
#    falls back to the built-in path.
check "edge case: no forge plugin installed is addressed" \
  "$(has_pattern_ci 'no forge plugin')" "yes"
check "edge case: multiple forge plugins is addressed" \
  "$(has_pattern_ci 'multiple forge plugin')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
