#!/bin/bash
# Test for Block B03 (plugin-readme). Authoritative contract: the
# HTML-comment docblock at the top of plugins/voice/README.md. Covers the
# clauses that are mechanically assertable from this file alone (prose
# quality clauses the contract itself defers to orchestrator verification
# at acceptance):
#
#   (1) The "What to expect" section quotes the injected block as a
#       markdown blockquote; stripping the blockquote prefixes ("> " per
#       line, a blank canonical line as ">") must reproduce, byte-for-byte,
#       the same text voice-context.sh actually emits (the B01 canonical
#       text). Quoted-block drift is a defect per the contract.
#   (2) The "## Tests" section lists exactly the four real test files
#       under plugins/voice/scripts/, and nothing else.
#   (3) The "## Relationships to other plugins" section contains, verbatim,
#       "None required. This plugin is fully standalone."
#   (4) The B03 contract comment itself is gone from the raw file (marked
#       remove-at-acceptance).
#
# Heading presence/order/placement (the 6 required H2s plus Tests between
# Commands and Relationships) is already enforced repo-wide by
# scripts/readme-lint.sh and is not re-checked here.
#
# The contract docblock quotes some of the exact strings this test looks
# for (the standalone sentence, the Tests section shape), so every content
# check against plugins/voice/README.md below runs against a
# comment-stripped copy (sed '/<!--/,/-->/d') — ask-in-text's
# registration.test.sh uses this same technique. Without it, the
# docblock's own prose could satisfy a check before the real content
# exists. The one exception is the "contract comment is gone" check, which
# reads the raw file on purpose. For (1), the referent is B01's actual
# emitted stdout (a real subprocess run of voice-context.sh), not a second
# hand-transcribed copy of the canonical text — that keeps this a genuine
# cross-file consistency check rather than a duplicate oracle.
#
# Run: bash plugins/voice/scripts/readme.test.sh (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
PLUGIN_README="$PLUGIN_DIR/README.md"
VOICE_CONTEXT_SH="$SCRIPT_DIR/voice-context.sh"
BASH_BIN="$(command -v bash)"

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
check "voice-context.sh exists" \
  "$([ -f "$VOICE_CONTEXT_SH" ] && echo yes || echo no)" "yes"

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
# 1. "What to expect" blockquote reproduces B01's actual emitted text
# ---------------------------------------------------------------------------

WTE_SECTION="$(section '## What to expect')"
check "'What to expect' section is non-empty" \
  "$([ -n "$WTE_SECTION" ] && echo yes || echo no)" "yes"

BLOCKQUOTE_RAW="$(grep -E '^>' <<<"$WTE_SECTION")"
check "'What to expect' section contains a blockquote (lines starting with >)" \
  "$([ -n "$BLOCKQUOTE_RAW" ] && echo yes || echo no)" "yes"

BLOCKQUOTE_STRIPPED="$(awk '{ if ($0 == ">") print ""; else print substr($0,3) }' <<<"$BLOCKQUOTE_RAW")"
printf '%s\n' "$BLOCKQUOTE_STRIPPED" > "$TMP/blockquote.txt"

B01_OUT="$TMP/b01.out"
"$BASH_BIN" "$VOICE_CONTEXT_SH" </dev/null >"$B01_OUT" 2>/dev/null

check "blockquote line count matches B01's actual output line count" \
  "$(wc -l < "$TMP/blockquote.txt" | tr -d ' ')" \
  "$(wc -l < "$B01_OUT" | tr -d ' ')"

check "blockquote (prefix-stripped) is byte-identical to B01's actual stdout" \
  "$(cmp -s "$TMP/blockquote.txt" "$B01_OUT" && echo identical || echo different)" \
  "identical"

# ---------------------------------------------------------------------------
# 2. "## Tests" section lists exactly the four real test files
# ---------------------------------------------------------------------------

TESTS_SECTION="$(section '## Tests')"
check "'Tests' section is non-empty" \
  "$([ -n "$TESTS_SECTION" ] && echo yes || echo no)" "yes"

for name in voice-context structure registration readme; do
  check "Tests section references plugins/voice/scripts/${name}.test.sh" \
    "$(grep -qF "plugins/voice/scripts/${name}.test.sh" <<<"$TESTS_SECTION" && echo yes || echo no)" \
    "yes"
done

ALL_TEST_REFS="$(grep -oE 'plugins/voice/scripts/[A-Za-z0-9_-]+\.test\.sh' <<<"$TESTS_SECTION" | sort -u)"
check "Tests section references exactly 4 distinct test files (nothing else)" \
  "$(count_lines "$ALL_TEST_REFS")" "4"

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
