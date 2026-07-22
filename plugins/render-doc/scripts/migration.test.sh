#!/bin/bash
# Test for Block B03 (MIGRATION.md bookkeeping). Authoritative contract: the
# HTML-comment docblock "Contract: B03 MIGRATION.md bookkeeping" in
# MIGRATION.md, just above the "Unassigned" section. Asserts directly on
# MIGRATION.md, the single shared file the contract names as B03's output:
#
#   (1) exactly one heading matching "## render-doc — ported"; that section
#       mentions ${CLAUDE_PLUGIN_ROOT}/scripts/render.sh, /decision-log:rundown,
#       render.test.sh, and CLAM_RENDER_DOC.
#   (2) the "Unassigned" section's writing-cluster line no longer contains
#       render-doc but still contains writing-markdown and rtfm.
#   (3) the stale decision-log note ("re-point it when render-doc gets a
#       plugin home") is gone.
#
# The contract docblock itself quotes the exact heading and writing-cluster
# line text this test looks for, so every check below runs against a
# comment-stripped copy (sed '/<!--/,/-->/d') — the debugging plugin's
# structure.test.sh uses this same technique. Without it, the docblock's own
# prose would satisfy a check before the real section exists.
#
# Run: bash plugins/render-doc/scripts/migration.test.sh (non-zero exit on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MIGRATION="$ROOT/MIGRATION.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "MIGRATION.md exists" \
  "$([ -f "$MIGRATION" ] && echo yes || echo no)" "yes"

# Every check below reads $BODY: MIGRATION.md with its own contract docblock
# stripped out, so the docblock's prose can never satisfy a check meant for
# real content.
BODY="$(sed '/<!--/,/-->/d' "$MIGRATION" 2>/dev/null)"

# =====================================================================
# (1) "## render-doc — ported" heading, exactly one
# =====================================================================

HEADING_COUNT="$(grep -cE '^## render-doc — ported' <<<"$BODY" || true)"
check "stripped MIGRATION.md has exactly one '## render-doc — ported' heading" \
  "$HEADING_COUNT" "1"

# Section body: from the heading up to (not including) the next "## "
# heading or EOF.
rd_section() {
  awk '
    /^## render-doc — ported/ { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$BODY"
}

RD_SECTION="$(rd_section)"
check "render-doc section is non-empty" \
  "$([ -n "$RD_SECTION" ] && echo yes || echo no)" "yes"

check "render-doc section mentions \${CLAUDE_PLUGIN_ROOT}/scripts/render.sh" \
  "$(grep -qF '${CLAUDE_PLUGIN_ROOT}/scripts/render.sh' <<<"$RD_SECTION" && echo yes || echo no)" "yes"
check "render-doc section mentions /decision-log:rundown" \
  "$(grep -qF '/decision-log:rundown' <<<"$RD_SECTION" && echo yes || echo no)" "yes"
check "render-doc section mentions render.test.sh" \
  "$(grep -qF 'render.test.sh' <<<"$RD_SECTION" && echo yes || echo no)" "yes"
check "render-doc section mentions CLAM_RENDER_DOC" \
  "$(grep -qF 'CLAM_RENDER_DOC' <<<"$RD_SECTION" && echo yes || echo no)" "yes"

# =====================================================================
# (2) Unassigned section's writing-cluster line
# =====================================================================

WRITING_LINE="$(grep -F '(writing cluster)' <<<"$BODY" | head -n1)"
check "Unassigned section has a writing-cluster line" \
  "$([ -n "$WRITING_LINE" ] && echo yes || echo no)" "yes"
check "writing-cluster line no longer contains render-doc" \
  "$(grep -qF 'render-doc' <<<"$WRITING_LINE" && echo present || echo absent)" "absent"
check "writing-cluster line still contains writing-markdown" \
  "$(grep -qF 'writing-markdown' <<<"$WRITING_LINE" && echo yes || echo no)" "yes"
check "writing-cluster line still contains rtfm" \
  "$(grep -qF 'rtfm' <<<"$WRITING_LINE" && echo yes || echo no)" "yes"

# =====================================================================
# (3) Stale decision-log re-point note is resolved (gone)
# =====================================================================
# Prose in MIGRATION.md is hard-wrapped, so this phrase can legitimately
# span a line break in the source (e.g. "...gets a plugin\n  home.") without
# that being a meaningful difference. Flatten whitespace before the literal
# match so reflow can't hide the phrase from this check.
FLAT_BODY="$(tr '\n' ' ' <<<"$BODY" | tr -s ' ')"

check "stale 're-point it when render-doc gets a plugin home' phrase is gone" \
  "$(grep -qF 're-point it when render-doc gets a plugin home' <<<"$FLAT_BODY" && echo present || echo absent)" "absent"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
