#!/bin/bash
# Meta-test for B04 structure-tests.
#
# Source of truth: the HTML-comment docblock labeled "Contract: B04
# structure-tests" in plugins/session-data/scripts/structure.test.sh.
#
# structure.test.sh is itself a test script — so this file doesn't invoke
# it, it scans its content to verify it actually implements the checks
# its contract promises: plugin.json validity (name, description,
# version, author), SKILL.md frontmatter, marketplace.json alignment,
# resolve-paths.sh existence, the shared check()/FAILED/exit pattern, and
# that it stays hermetic (no network tools).
#
# Checks 4-7 (the behavioral content checks) are scoped to the target's
# code_body — every line stripped of full-line comments and blanks. This
# matters for red discipline: the target's own contract docblock is
# comment prose that already names "plugin.json", "SKILL.md frontmatter",
# "marketplace.json alignment", and "resolve-paths.sh" (it's the spec
# describing what to build), so scanning the raw file including comments
# would pass those checks vacuously against the unimplemented stub. Only
# scanning non-comment code means these checks pass once an implementer
# writes real logic, not merely describes it.
#
# Against the current stub (which just echoes a SKIP line and exits 0):
# checks 1 (exists), 2 (executable), and 8 (hermetic) pass; checks 3-7
# (check()/FAILED/exit pattern, plugin.json/SKILL.md/marketplace.json/
# resolve-paths.sh content checks) fail red, since the stub's code_body
# has no such logic yet.
#
# Hermetic: reads only the repo's own committed files, no network, no
# mutation, cwd-independent (all paths resolved from this script's own
# location).
#
# Run: bash plugins/session-data/scripts/structure-meta.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/structure.test.sh"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# The target's executable code with full-line comments (including any
# HTML-style contract docblock, which is embedded as bash comments) and
# blank lines stripped out. "" if the target doesn't exist.
code_body() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$file"
}

# ---------------------------------------------------------------------------
# 1. structure.test.sh exists
# ---------------------------------------------------------------------------

check "structure.test.sh exists" \
  "$([ -f "$TARGET" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 2. structure.test.sh is executable
# ---------------------------------------------------------------------------

check "structure.test.sh is executable" \
  "$([ -x "$TARGET" ] && echo yes || echo no)" "yes"

raw="$([ -f "$TARGET" ] && cat "$TARGET" || echo "")"
code="$(code_body "$TARGET")"

# ---------------------------------------------------------------------------
# 3. Uses the check()/FAILED/exit pattern shared by other structure tests
# ---------------------------------------------------------------------------

check "code defines a check() function" \
  "$(grep -qE '^check\(\)' <<<"$code" && echo yes || echo no)" "yes"

check "code uses a FAILED accumulator variable" \
  "$(grep -qE '(^|[^A-Za-z_])FAILED=' <<<"$code" && echo yes || echo no)" "yes"

check "code exits with the FAILED status" \
  "$(grep -qE 'exit \$FAILED' <<<"$code" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 4. Checks plugin.json validity (name, description, version, author)
# ---------------------------------------------------------------------------

check "code references plugin.json" \
  "$(grep -qF 'plugin.json' <<<"$code" && echo yes || echo no)" "yes"

check "code checks plugin.json .name field" \
  "$(grep -qF 'plugin.json' <<<"$code" && grep -qiE '\bname\b' <<<"$code" && echo yes || echo no)" "yes"

check "code checks plugin.json .description field" \
  "$(grep -qF 'plugin.json' <<<"$code" && grep -qiE '\bdescription\b' <<<"$code" && echo yes || echo no)" "yes"

check "code checks plugin.json .version field" \
  "$(grep -qF 'plugin.json' <<<"$code" && grep -qiE '\bversion\b' <<<"$code" && echo yes || echo no)" "yes"

check "code checks plugin.json .author field" \
  "$(grep -qF 'plugin.json' <<<"$code" && grep -qiE '\bauthor\b' <<<"$code" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 5. Checks SKILL.md frontmatter (name, description fields)
# ---------------------------------------------------------------------------

check "code references SKILL.md" \
  "$(grep -qF 'SKILL.md' <<<"$code" && echo yes || echo no)" "yes"

check "code checks SKILL.md frontmatter" \
  "$(grep -qF 'SKILL.md' <<<"$code" && grep -qiE 'frontmatter' <<<"$code" && echo yes || echo no)" "yes"

check "code checks SKILL.md frontmatter name field" \
  "$(grep -qiE 'frontmatter' <<<"$code" && grep -qiE '\bname\b' <<<"$code" && echo yes || echo no)" "yes"

check "code checks SKILL.md frontmatter description field" \
  "$(grep -qiE 'frontmatter' <<<"$code" && grep -qiE '\bdescription\b' <<<"$code" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 6. Checks marketplace.json alignment
# ---------------------------------------------------------------------------

check "code references marketplace.json" \
  "$(grep -qF 'marketplace.json' <<<"$code" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 7. Checks resolve-paths.sh existence
# ---------------------------------------------------------------------------

check "code references resolve-paths.sh" \
  "$(grep -qF 'resolve-paths.sh' <<<"$code" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 8. Hermetic: no network tools anywhere in the file
# ---------------------------------------------------------------------------

check "does not use curl" \
  "$(grep -qE '(^|[^A-Za-z0-9_])curl\b' <<<"$raw" && echo used || echo ok)" "ok"

check "does not use wget" \
  "$(grep -qE '(^|[^A-Za-z0-9_])wget\b' <<<"$raw" && echo used || echo ok)" "ok"

check "does not use nc/netcat" \
  "$(grep -qE '(^|[^A-Za-z0-9_])(nc|netcat)\b' <<<"$raw" && echo used || echo ok)" "ok"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
