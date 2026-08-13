#!/bin/bash
# Test for Block B03 (plugin-readme). Covers the clauses that are
# mechanically assertable from this file alone (prose quality clauses are
# deferred to orchestrator verification at acceptance):
#
#   (1) The "What to expect" section quotes the canonical Voice block as a
#       markdown blockquote; stripping the blockquote prefixes ("> " per
#       line, a blank canonical line as ">") must reproduce, byte-for-byte,
#       the body of output-styles/voice.md (frontmatter and its trailing
#       blank line removed). The style file is the single canonical source;
#       quoted-block drift is a defect.
#   (2) The "## Tests" section lists exactly the three real test files
#       under plugins/voice/scripts/, and nothing else.
#   (3) The "## Relationships to other plugins" section contains, verbatim,
#       "None required. This plugin is fully standalone."
#   (4) The B03 contract comment is gone from the raw file (it was marked
#       remove-at-acceptance).
#
# Heading presence/order/placement (the 6 required H2s plus extra sections
# between Commands and Relationships) is already enforced repo-wide by
# scripts/readme-lint.sh and is not re-checked here.
#
# Every content check against plugins/voice/README.md runs against a
# comment-stripped copy (sed '/<!--/,/-->/d') so no docblock prose can
# satisfy a check meant for real content. The one exception is the
# "contract comment is gone" check, which reads the raw file on purpose.
# For (1), the referent is the actual committed style body, not a second
# hand-transcribed copy of the canonical text — that keeps this a genuine
# cross-file consistency check rather than a duplicate oracle.
#
# Run: bash plugins/voice/scripts/readme.test.sh (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
PLUGIN_README="$PLUGIN_DIR/README.md"
STYLE_KEEP="$PLUGIN_DIR/output-styles/voice.md"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

count_lines() { # helper: wc -l on a possibly-empty string, no phantom "1"
  if [[ -z "$1" ]]; then echo 0; else wc -l <<<"$1" | tr -d ' '; fi
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugins/voice/README.md exists" \
  "$([ -f "$PLUGIN_README" ] && echo yes || echo no)" "yes"
check "output-styles/voice.md exists" \
  "$([ -f "$STYLE_KEEP" ] && echo yes || echo no)" "yes"

# Every content check below reads $BODY: the plugin README with its own
# contract docblock stripped out.
BODY="$(sed '/<!--/,/-->/d' "$PLUGIN_README" 2>/dev/null)"

section() { # $1 = exact "## Heading" line, reads $BODY
  awk -v heading="$1" '
    $0 == heading { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$BODY"
}

# ---------------------------------------------------------------------------
# 1. "What to expect" blockquote reproduces the canonical style body
# ---------------------------------------------------------------------------

WTE_SECTION="$(section '## What to expect')"
check "'What to expect' section is non-empty" \
  "$([ -n "$WTE_SECTION" ] && echo yes || echo no)" "yes"

BLOCKQUOTE_RAW="$(grep -E '^>' <<<"$WTE_SECTION")"
check "'What to expect' section contains a blockquote (lines starting with >)" \
  "$([ -n "$BLOCKQUOTE_RAW" ] && echo yes || echo no)" "yes"

BLOCKQUOTE_STRIPPED="$(awk '{ if ($0 == ">") print ""; else print substr($0,3) }' <<<"$BLOCKQUOTE_RAW")"
printf '%s\n' "$BLOCKQUOTE_STRIPPED" > "$TMP/blockquote.txt"

# Canonical referent: voice.md's body — everything after the closing
# frontmatter fence, minus the single blank separator line that follows it.
awk 'NR==1 && $0=="---" {flag=1; next} flag==1 && $0=="---" {flag=2; next} flag==2 {print}' \
  "$STYLE_KEEP" | sed '1{/^$/d;}' > "$TMP/style-body.txt"

check "blockquote line count matches the style body line count" \
  "$(wc -l < "$TMP/blockquote.txt" | tr -d ' ')" \
  "$(wc -l < "$TMP/style-body.txt" | tr -d ' ')"

check "blockquote (prefix-stripped) is byte-identical to the style body" \
  "$(cmp -s "$TMP/blockquote.txt" "$TMP/style-body.txt" && echo identical || echo different)" \
  "identical"

# ---------------------------------------------------------------------------
# 2. "## Tests" section lists exactly the three real test files
# ---------------------------------------------------------------------------

TESTS_SECTION="$(section '## Tests')"
check "'Tests' section is non-empty" \
  "$([ -n "$TESTS_SECTION" ] && echo yes || echo no)" "yes"

for name in structure registration readme; do
  check "Tests section references plugins/voice/scripts/${name}.test.sh" \
    "$(grep -qF "plugins/voice/scripts/${name}.test.sh" <<<"$TESTS_SECTION" && echo yes || echo no)" \
    "yes"
done

ALL_TEST_REFS="$(grep -oE 'plugins/voice/scripts/[A-Za-z0-9_-]+\.test\.sh' <<<"$TESTS_SECTION" | sort -u)"
check "Tests section references exactly 3 distinct test files (nothing else)" \
  "$(count_lines "$ALL_TEST_REFS")" "3"

# ---------------------------------------------------------------------------
# 3. Standalone sentence in Relationships to other plugins
# ---------------------------------------------------------------------------

RELATIONSHIPS_SECTION="$(section '## Relationships to other plugins')"
check "'Relationships to other plugins' section is non-empty" \
  "$([ -n "$RELATIONSHIPS_SECTION" ] && echo yes || echo no)" "yes"
check "Relationships section states the standalone sentence verbatim" \
  "$(grep -qF 'None required. This plugin is fully standalone.' <<<"$RELATIONSHIPS_SECTION" && echo yes || echo no)" \
  "yes"

# ---------------------------------------------------------------------------
# 4. B03 contract comment gone from the raw file (remove-at-acceptance)
# ---------------------------------------------------------------------------

check "B03 contract comment marker is gone from the raw plugin README" \
  "$(grep -qF 'Contract: B03 plugin-readme' "$PLUGIN_README" && echo present || echo absent)" \
  "absent"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
