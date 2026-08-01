#!/usr/bin/env bash
# plugin-readme-template.test.sh — contract tests for the "Relationships to
# other plugins" guidance comment in plugins/PLUGIN_README_TEMPLATE.md:
#   B03 template-relationships-guidance (plan
#   001-ensure-agents-understand-architecture).
#
# Black-box, content-only: no fixtures, no invocation — reads the template
# file as committed and asserts on its prose. plugins/PLUGIN_README_TEMPLATE.md
# is not a plugin directory (no version-bump concerns).
#
# Contract-comment gotcha: until acceptance, the file carries an HTML
# "Contract: B03" docblock ABOVE the guidance comment, and that docblock's
# own prose quotes the banned/required vocabulary as description (e.g. it
# says the phrase "Hard dependencies" must disappear — so the word
# "Hard dependencies" appears in the contract block itself). A naive grep
# over the whole file would misfire in both directions. So the clause
# assertions below run against $SECTION, built in two steps: first strip
# the contract block —
#
#   DOC="$(sed '/<!-- Contract: B03/,/^-->$/d' "$TEMPLATE")"
#
# — then keep only the lines between the "## Relationships to other
# plugins" heading and the next "## Uninstalling" heading, so unrelated
# sections of the template (e.g. the Commands section, which legitimately
# says "component" and "protocol" in its own unrelated context) can never
# false-positive a keyword search. This is stable across both states of
# the file: today the strip is a no-op past the contract's own end and
# $SECTION is the OLD guidance comment (still holding the banned
# vocabulary, which is why the negative assertions are correctly red);
# after acceptance the contract text no longer exists, the sed range
# matches nothing (no-op), and $SECTION is simply the rewritten guidance
# comment.
#
# The one exception is the "Contract: B03 is gone" check, which reads the
# RAW file on purpose — that assertion is only meaningful unstripped, and
# is expected to fail (red) until the implementation wave deletes the
# contract block for real.
#
# Report-line style: per the contract's own Behavior clause, "capabilities
# consumed", "protocols implemented", "architecture-lint warning" and the
# "build exception" are specified as CONTENT the guidance must teach, not
# as exact sentences — so those clauses are asserted via case-insensitive
# keyword anchors drawn from the contract's own vocabulary, mirroring
# scripts/readme-lint.test.sh's "look for content co-occurring, not the
# exact sentence" approach — a couple of the softer clauses (the
# architecture-lint "defect" framing, the build "exception" framing) use
# contains_any_ci with a short synonym list so a correct rewrite phrased
# in the template's own voice isn't penalized for not echoing the
# contract's exact word choice. Only vocabulary the contract marks
# verbatim (the standalone-default sentence) or that names a literal
# path/script (docs/protocols/, scripts/architecture-lint.sh) is asserted
# exactly.
#
# Run: bash scripts/plugin-readme-template.test.sh
#      (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_ROOT/plugins/PLUGIN_README_TEMPLATE.md"

if [ ! -f "$TEMPLATE" ]; then
  echo "FATAL: template not found at $TEMPLATE" >&2
  exit 1
fi

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# Assertion helpers. Both flatten newlines to spaces first so a phrase that
# happens to fall across this template's manual line-wrap boundary still
# matches as one substring.
# ---------------------------------------------------------------------------
contains() { # haystack needle -> yes/no (case-sensitive)
  local hay
  hay="$(printf '%s' "$1" | tr '\n' ' ')"
  case "$hay" in *"$2"*) echo yes ;; *) echo no ;; esac
}

contains_ci() { # haystack needle -> yes/no (case-insensitive)
  local hay lc_hay lc_needle
  hay="$(printf '%s' "$1" | tr '\n' ' ')"
  lc_hay="$(printf '%s' "$hay" | tr '[:upper:]' '[:lower:]')"
  lc_needle="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  case "$lc_hay" in *"$lc_needle"*) echo yes ;; *) echo no ;; esac
}

contains_any_ci() { # haystack needle... -> yes/no (case-insensitive OR)
  local hay="$1"; shift
  local n
  for n in "$@"; do
    [ "$(contains_ci "$hay" "$n")" = "yes" ] && { echo yes; return; }
  done
  echo no
}

RAW="$(cat "$TEMPLATE")"
DOC="$(sed '/<!-- Contract: B03/,/^-->$/d' "$TEMPLATE")"

# The clause assertions (2 through 7 below) must look ONLY at the
# Relationships-section content, not the whole template — other sections
# legitimately use words like "component" and "protocol" in unrelated
# contexts (e.g. the Commands section's "Document every user-facing
# component the plugin provides"), which would otherwise false-positive a
# whole-file keyword search regardless of what the guidance comment says.
SECTION="$(printf '%s\n' "$DOC" | awk '
  /^## Relationships to other plugins$/ { flag=1; next }
  /^## Uninstalling$/ { flag=0 }
  flag
')"

# ===========================================================================
# 0. Contract docblock itself is gone from the committed file (checked
#    against the RAW file, deliberately not $DOC — this is only meaningful
#    unstripped). Contract: this is the acceptance marker, not a clause of
#    the contract's Behavior/Invariants; expected RED today.
# ===========================================================================
check "0. contract docblock removed from file" \
  "$(contains "$RAW" "Contract: B03")" "no"

# ===========================================================================
# 1. Structural: the H2 heading above the guidance comment is unchanged —
#    readme-lint.sh mandates the exact heading set (scripts/readme-lint.sh,
#    scripts/readme-lint.test.sh H_RELATIONSHIPS). Contract: Outputs ("the
#    H2 heading above is UNCHANGED").
# ===========================================================================
check "1. heading survives verbatim" \
  "$(grep -qxF '## Relationships to other plugins' "$TEMPLATE" && echo yes || echo no)" "yes"

# ===========================================================================
# 2. Capabilities-consumed guidance: teaches describing what the plugin
#    needs done, with a standard-tools baseline so graceful degradation is
#    visible. Contract: Behavior clause 1 (CAPABILITIES CONSUMED).
# ===========================================================================
check "2. capabilities-consumed: topic present" \
  "$(contains_ci "$SECTION" "capabilit")" "yes"
check "2. capabilities-consumed: standard-tools baseline present" \
  "$(contains_any_ci "$SECTION" "standard" "baseline")" "yes"

# ===========================================================================
# 3. Protocols-implemented guidance: cites shared artifact conventions by
#    spec path under docs/protocols/. Contract: Behavior clause 2
#    (PROTOCOLS IMPLEMENTED).
# ===========================================================================
check "3. protocols-implemented: topic present" \
  "$(contains_ci "$SECTION" "protocol")" "yes"
check "3. protocols-implemented: cites docs/protocols/" \
  "$(contains "$SECTION" "docs/protocols/")" "yes"

# ===========================================================================
# 4. Standalone default: the existing sentence kept VERBATIM. Contract:
#    Behavior clause 3.
# ===========================================================================
check "4. standalone default sentence verbatim" \
  "$(contains "$SECTION" "None required. This plugin is fully standalone.")" "yes"

# ===========================================================================
# 5. architecture-lint warning: naming another plugin here is a defect
#    flagged by scripts/architecture-lint.sh. Contract: Behavior ("a defect
#    flagged by scripts/architecture-lint.sh").
# ===========================================================================
check "5. architecture-lint: script path cited" \
  "$(contains "$SECTION" "scripts/architecture-lint.sh")" "yes"
check "5. architecture-lint: framed as a defect/violation" \
  "$(contains_any_ci "$SECTION" "defect" "violation" "flagged")" "yes"

# ===========================================================================
# 6. build-only exception: build (the sole composite) lists its
#    components — downward, detect-and-degrade, never required. Contract:
#    Behavior ("one exception: build ... lists its components"), Edge
#    cases (carve out the exception without weakening the default).
# ===========================================================================
check "6. build exception: names build" \
  "$(contains_ci "$SECTION" "build")" "yes"
check "6. build exception: mentions components" \
  "$(contains_ci "$SECTION" "component")" "yes"
check "6. build exception: framed as an exception" \
  "$(contains_any_ci "$SECTION" "exception" "exempt")" "yes"

# ===========================================================================
# 7. Negative: banned vocabulary is GONE after rewrite. Contract:
#    Invariants ("the following vocabulary is GONE after rewrite").
#    Each of these is present in the OLD guidance comment today, so these
#    four checks are expected to fail RED until the rewrite lands.
# ===========================================================================
check "7. banned vocabulary: 'Hard dependencies' absent" \
  "$(contains "$SECTION" "Hard dependencies")" "no"
check "7. banned vocabulary: 'Soft integrations' absent" \
  "$(contains "$SECTION" "Soft integrations")" "no"
check "7. banned vocabulary: 'Requires / Provides / Consumes' absent" \
  "$(contains "$SECTION" "Requires / Provides / Consumes")" "no"
check "7. banned vocabulary: 'worktrees and orchestrator-handover' citation absent" \
  "$(contains "$SECTION" "worktrees and orchestrator-handover")" "no"

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
