#!/bin/bash
# Structural test for the B04 default PR body template
# (plugins/landing/templates/pr-body-template.md): the forge-agnostic
# default body, filled at PR-composition time by the built-in path or
# passed to a forge plugin as the invoker-provided template.
#
# All content checks run against the file with HTML comment blocks (the
# contract docblock) stripped out first -- the docblock already names
# every required heading and the NotImplemented marker it describes, so
# a raw-file check could pass on the unimplemented stub for the wrong
# reason. Stripping ensures every check can only be satisfied by the
# actual template body that replaces the marker.
# Run: bash plugins/landing/scripts/pr-body-template.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$PLUGIN_DIR/templates/pr-body-template.md"

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

BODY="$(strip_comments "$TEMPLATE")"

has_pattern_ci() { # extended-regex
  printf '%s' "$BODY" | grep -qiE -- "$1" && echo yes || echo no
}

check "template file exists" "$([[ -f "$TEMPLATE" ]] && echo yes || echo no)" "yes"

# 1. No NotImplemented marker in the rendered template body.
check "no NotImplemented marker in template body" \
  "$(has_pattern_ci 'NotImplemented')" "no"

# 2. The six required section headings, present and in the contract's
#    order: Summary; Why; Why this approach; Changes; Verification;
#    Related work.
REQUIRED_HEADINGS=(Summary Why "Why this approach" Changes Verification "Related work")

for h in "${REQUIRED_HEADINGS[@]}"; do
  found="$(printf '%s\n' "$BODY" | grep -E "^#+[[:space:]]+${h}[[:space:]]*\$")"
  check "heading '$h' present" "$([[ -n "$found" ]] && echo yes || echo no)" "yes"
done

ACTUAL_ORDER="$(printf '%s\n' "$BODY" | grep -E '^#+[[:space:]]+(Summary|Why|Why this approach|Changes|Verification|Related work)[[:space:]]*$' | sed -E 's/^#+[[:space:]]+//; s/[[:space:]]*$//')"
EXPECTED_ORDER=$'Summary\nWhy\nWhy this approach\nChanges\nVerification\nRelated work'
check "headings appear in the contract's order" "$ACTUAL_ORDER" "$EXPECTED_ORDER"

# 3. Each heading carries a bracketed ONE-LINE hint of what belongs
#    there (checked within the heading's own line plus the two lines
#    after it, so either an inline "## Heading [hint]" layout or a
#    heading-then-hint layout passes -- the contract fixes the content,
#    not the exact line placement). The bracket's open and close must
#    fall on the SAME line: matching '[' and ']' independently anywhere
#    in the window would also pass a hint split across lines by a hard
#    line break, which is exactly what "one-line hint" and "the hints
#    must not model hard-wrapped text" forbid.
heading_line_no() { # heading
  printf '%s\n' "$BODY" | grep -nE "^#+[[:space:]]+$1[[:space:]]*\$" | head -1 | cut -d: -f1
}

for h in "${REQUIRED_HEADINGS[@]}"; do
  ln="$(heading_line_no "$h")"
  has_brackets="no"
  if [[ -n "$ln" ]]; then
    window="$(printf '%s\n' "$BODY" | sed -n "${ln},$((ln + 2))p")"
    printf '%s\n' "$window" | grep -qE '\[[^][]*\]' && has_brackets="yes"
  fi
  check "'$h' section has a one-line bracketed hint" "$has_brackets" "yes"
done

# 4. Invariant: forge-agnostic -- no GitHub- or GitLab-specific wording.
check "template does not mention GitHub" "$(has_pattern_ci '\bgithub\b')" "no"
check "template does not mention GitLab" "$(has_pattern_ci '\bgitlab\b')" "no"

# 5. Invariant: no references to other plugins or internal workflow
#    terminology.
check "template does not reference the lego plugin" "$(has_pattern_ci '\blego\b')" "no"
check "template does not reference the build plugin" "$(has_pattern_ci '\bbuild\b')" "no"
check "template does not reference the tracking plugin" "$(has_pattern_ci '\btracking\b')" "no"
check "template does not reference internal .local/ paths" \
  "$(has_pattern_ci '\.local/')" "no"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
