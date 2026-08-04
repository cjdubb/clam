#!/bin/bash
# Test for Block B06 (docs-attribution). Authoritative contract: the
# HTML-comment docblock at the top of plugins/statusline/README.md. Covers
# the clauses that are mechanically assertable from this file and its
# siblings alone (prose-quality clauses — whether the burnrate figures are
# explained "in the terms a reader needs to act on it" — are deferred to
# orchestrator verification at acceptance):
#
#   (1) Change 1: "What to expect" describes TWO rendered lines, not four —
#       the old four-line render's bullets (Mode / model / effort, Context
#       usage, Cost) are gone, the clam mode is still described, and the
#       burnrate line's vocabulary (%t, %/d, the trend arrow, the awake-hours
#       pacing, the weekly / 5-hour / pet groups) is present.
#   (2) Change 2: the Cost line is gone from the render description (no Cost
#       bullet, no "Cost line" bundle key, no CCOST_SESSION_TTL_SECONDS
#       interaction anywhere under "## What to expect"), WHILE ccost.sh keeps
#       its "## Commands" and "## Common workflows" entries — it survives as
#       a standalone CLI. Both halves are asserted; the second is what stops
#       an over-eager deletion.
#   (3) Change 3 + the "every env var the scripts read appears in the table,
#       and every row names a var some script reads" invariant: the env-var
#       table's row set is compared against the set DERIVED from the plugin's
#       own non-test sources (see the derivation note below), and the two new
#       knobs carry their documented defaults (2 and 6).
#   (4) Change 4: the attribution names the upstream, its author, its MIT
#       licence and its URL — the first three DERIVED from the normative
#       per-file copyright headers in lib/burn-*.sh rather than
#       hand-transcribed here, so this stays a cross-file consistency check
#       with a single oracle.
#   (5) The B06 contract comment itself is gone from the raw file (marked
#       remove-at-acceptance).
#   (6) plugin.json is at 0.5.0 (its PR group's version) and the root
#       README.md Plugins-table row agrees with it. version-bump-lint and
#       readme-lint both gate this; checking it here fails it in the inner
#       loop instead of in CI.
#   (7) The contract's edge case that agent-dash and the tracking plugin keep # architecture-lint: allow naming them is the assertion the check below verifies, not a cross-plugin dependency
#       their existing "Relationships to other plugins" entries.
#
# Heading presence/order/placement (the 6 required H2s plus extras confined
# between Commands and Relationships) is already enforced repo-wide by
# scripts/readme-lint.sh and is not re-checked here — the same division of
# labour applied elsewhere in this repo's per-plugin README tests.
#
# COMMENT STRIPPING. The contract docblock quotes many of the exact strings
# this test looks for (SL_*, CLAM_STATUSLINE_DAY_START, "Gui-Gou", "MIT",
# "claude-statusline-burnrate", "the Cost line"), and it sits in the very
# file under test — so a naive grep would find them in the contract and pass
# before a word of the real prose exists. Every content check below therefore
# runs against $BODY, the README with its own HTML comments stripped
# (sed '/<!--/,/-->/d'), the technique voice's readme.test.sh and
# ask-in-text's registration.test.sh both use. The ONE exception is the
# "contract comment is gone" check, which reads the raw file on purpose.
#
# ENV-VAR DERIVATION. The expected knob set is derived from the plugin's own
# non-test scripts/*.sh and lib/*.sh: comment lines are stripped (the same
# reason as above — context.sh's docblocks name knobs that its code may not
# read yet), then every $VAR / ${VAR...} read carrying one of the plugin's
# public prefixes (CLAUDE_/CCOST_/CLAM_) is collected. Deriving rather than
# hard-coding keeps this check alive as the plugin changes. It is unioned
# with CLAM_STATUSLINE_DAY_START and CLAM_STATUSLINE_SLEEP_HOURS: B07 renames
# context.sh's internal SL_DAY_START/SL_SLEEP_HOURS locals to be seeded from
# those public names, and until it lands the derivation cannot see them. They
# are the decided public interface either way
# (.local/decisions/003-burn-knob-env-prefix.md), so the union is the one
# deliberate place this test's expectation leads the code rather than
# following it. The bare SL_* spellings are internal locals: a separate check
# asserts they are NOT documented.
#
# Run: bash plugins/statusline/scripts/readme.test.sh (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
PLUGIN_README="$PLUGIN_DIR/README.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
ROOT_README="$REPO_ROOT/README.md"
BURN_MATH="$PLUGIN_DIR/lib/burn-math.sh"

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

has_re()    { grep -qiE "$1" <<<"$2" && echo yes || echo no; }   # case-insensitive ERE
has_fixed() { grep -qF  "$1" <<<"$2" && echo yes || echo no; }   # literal substring
one_line()  { tr '\n' ' ' <<<"$1" | sed -e 's/  *$//'; }         # for readable FAIL messages

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugins/statusline/README.md exists" \
  "$([ -f "$PLUGIN_README" ] && echo yes || echo no)" "yes"
check "plugins/statusline/.claude-plugin/plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "lib/burn-math.sh exists (attribution oracle)" \
  "$([ -f "$BURN_MATH" ] && echo yes || echo no)" "yes"

# Every content check below reads $BODY: the plugin README with its own
# HTML comments (the B06 contract docblock) stripped out.
BODY="$(sed '/<!--/,/-->/d' "$PLUGIN_README" 2>/dev/null)"

section() { # $1 = exact "## Heading" line, reads $BODY
  awk -v heading="$1" '
    $0 == heading { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$BODY"
}

# ---------------------------------------------------------------------------
# 1. Contract comment gone from the RAW file (remove-at-acceptance)
# ---------------------------------------------------------------------------

check "B06 contract comment marker is gone from the raw plugin README" \
  "$(grep -qF 'Contract: B06 docs-attribution' "$PLUGIN_README" && echo present || echo absent)" \
  "absent"

# ---------------------------------------------------------------------------
# 2. Env-var table == the set the plugin's own scripts actually read
# ---------------------------------------------------------------------------

# Documented: first cell of every backticked-identifier table row in $BODY.
grep -E '^\|[[:space:]]*`[A-Z][A-Z0-9_]*`[[:space:]]*\|' <<<"$BODY" \
  | sed -E 's/^\|[[:space:]]*`([A-Z][A-Z0-9_]*)`.*/\1/' | sort -u > "$TMP/documented"

# Derived: public-prefixed env reads in the non-test sources, comments
# stripped, plus the two decided knobs B07 has not wired up yet (see header).
for f in "$PLUGIN_DIR"/scripts/*.sh "$PLUGIN_DIR"/lib/*.sh; do
  case "$f" in *.test.sh) continue ;; esac
  [ -f "$f" ] || continue
  sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#[[:space:]].*$//' "$f"
done | grep -oE '\$\{?(CLAUDE|CCOST|CLAM)_[A-Z0-9_]+' | sed -E 's/^\$\{?//' > "$TMP/derived.src"
cat "$TMP/derived.src" > "$TMP/derived.raw"
printf '%s\n%s\n' CLAM_STATUSLINE_DAY_START CLAM_STATUSLINE_SLEEP_HOURS >> "$TMP/derived.raw"
sort -u "$TMP/derived.raw" > "$TMP/derived"

check "env-var table is present (backticked rows found)" \
  "$([ -s "$TMP/documented" ] && echo yes || echo no)" "yes"
# Guards the derivation itself: if the source scan finds nothing (wrong
# paths, prefixes changed), the table checks below would compare against the
# two unioned names alone and pass vacuously. $TMP/derived.src excludes the
# union on purpose so this check can actually fail.
check "derivation found env reads in the plugin's own sources (oracle is not empty)" \
  "$([ -s "$TMP/derived.src" ] && echo yes || echo no)" "yes"

check "every env var the scripts read appears in the table" \
  "$(one_line "$(comm -23 "$TMP/derived" "$TMP/documented")")" ""
check "every table row names an env var some script reads" \
  "$(one_line "$(comm -13 "$TMP/derived" "$TMP/documented")")" ""

table_default_for() { # $1 = env var name; prints its Default cell, de-ticked
  grep -E "^\|[[:space:]]*\`$1\`[[:space:]]*\|" <<<"$BODY" | head -1 \
    | awk -F'|' '{ print $3 }' | sed -e 's/[[:space:]]//g' -e 's/`//g'
}

check "CLAM_STATUSLINE_DAY_START is documented with default 2" \
  "$(table_default_for CLAM_STATUSLINE_DAY_START)" "2"
check "CLAM_STATUSLINE_SLEEP_HOURS is documented with default 6" \
  "$(table_default_for CLAM_STATUSLINE_SLEEP_HOURS)" "6"

# The bare SL_* spellings are internal locals, never the documented interface.
check "the bare SL_DAY_START / SL_SLEEP_HOURS spellings are not documented" \
  "$(grep -cE '(^|[^A-Za-z0-9_])SL_(DAY_START|SLEEP_HOURS)' <<<"$BODY")" "0"

# ---------------------------------------------------------------------------
# 3. "What to expect": two lines, not four; no Cost line
# ---------------------------------------------------------------------------

WTE="$(section '## What to expect')"
check "'What to expect' section is non-empty" \
  "$([ -n "$WTE" ] && echo yes || echo no)" "yes"

check "'What to expect' describes TWO rendered lines" \
  "$(has_re '(^|[^a-z0-9])(two|2) lines' "$WTE")" "yes"
check "'What to expect' no longer describes four rendered lines" \
  "$(has_re '(^|[^a-z0-9])(four|4) lines' "$WTE")" "no"

check "the old 'Mode / model / effort' line bullet is gone" \
  "$(has_re '^- \*\*Mode / model / effort' "$WTE")" "no"
check "the old 'Context usage' line bullet is gone" \
  "$(has_re '^- \*\*Context usage' "$WTE")" "no"
check "the old 'Cost' line bullet is gone" \
  "$(has_re '^- \*\*Cost' "$WTE")" "no"

check "no 'Cost line' remains in the render/caching description" \
  "$(has_re 'cost line' "$WTE")" "no"
check "the CCOST_SESSION_TTL_SECONDS caching interaction is gone from the render description" \
  "$(has_fixed 'CCOST_SESSION_TTL_SECONDS' "$WTE")" "no"

# The clam mode survives the uplift — it moves onto the path line, it is not
# dropped (contract change 1).
check "'What to expect' still describes the clam mode" \
  "$(has_re 'clam( session)? mode' "$WTE")" "yes"

# The burnrate line's figures are explained in actionable terms.
check "'What to expect' explains the today's-share figure (%t)" \
  "$(has_fixed '%t' "$WTE")" "yes"
check "'What to expect' explains the sustainable-pace figure (%/d)" \
  "$(has_fixed '%/d' "$WTE")" "yes"
check "'What to expect' explains the trend arrow" \
  "$(has_re 'trend' "$WTE")" "yes"
check "'What to expect' states the pacing counts awake hours only" \
  "$(has_re 'awake' "$WTE")" "yes"
check "'What to expect' describes the weekly-limit group" \
  "$(has_re 'weekly' "$WTE")" "yes"
check "'What to expect' describes the 5-hour-limit group" \
  "$(has_re '5.hour' "$WTE")" "yes"
check "'What to expect' describes the pet group" \
  "$(has_re '(^|[^a-z])pet([^a-z]|$)' "$WTE")" "yes"

# ---------------------------------------------------------------------------
# 4. ccost.sh survives as a standalone CLI (the other half of change 2)
# ---------------------------------------------------------------------------

COMMANDS="$(section '## Commands')"
check "'Commands' section is non-empty" \
  "$([ -n "$COMMANDS" ] && echo yes || echo no)" "yes"
check "'Commands' still documents scripts/ccost.sh" \
  "$(has_fixed 'scripts/ccost.sh' "$COMMANDS")" "yes"

WORKFLOWS="$(section '## Common workflows')"
check "'Common workflows' section is non-empty" \
  "$([ -n "$WORKFLOWS" ] && echo yes || echo no)" "yes"
check "'Common workflows' still documents running ccost.sh from the shell" \
  "$(has_fixed 'ccost.sh' "$WORKFLOWS")" "yes"

# ---------------------------------------------------------------------------
# 5. Attribution — oracle is the normative header in lib/burn-math.sh
# ---------------------------------------------------------------------------

UPSTREAM_URL="$(grep -oE 'https://github\.com/[A-Za-z0-9._/-]+' "$BURN_MATH" 2>/dev/null | head -1)"
UPSTREAM_NAME="${UPSTREAM_URL##*/}"
UPSTREAM_AUTHOR="$(sed -nE 's/^#.*MIT © (.+)$/\1/p' "$BURN_MATH" 2>/dev/null | head -1)"

check "upstream URL derived from lib/burn-math.sh's copyright header" \
  "$([ -n "$UPSTREAM_URL" ] && echo yes || echo no)" "yes"
check "upstream author derived from lib/burn-math.sh's copyright header" \
  "$([ -n "$UPSTREAM_AUTHOR" ] && echo yes || echo no)" "yes"

check "attribution names the upstream project ($UPSTREAM_NAME)" \
  "$(has_fixed "$UPSTREAM_NAME" "$BODY")" "yes"
check "attribution names the upstream author ($UPSTREAM_AUTHOR)" \
  "$(has_fixed "$UPSTREAM_AUTHOR" "$BODY")" "yes"
check "attribution names the upstream URL ($UPSTREAM_URL)" \
  "$(has_fixed "$UPSTREAM_URL" "$BODY")" "yes"
check "attribution names the MIT licence" \
  "$(has_re '(^|[^A-Za-z])MIT([^A-Za-z]|$)' "$BODY")" "yes"

# ---------------------------------------------------------------------------
# 6. Version: plugin.json at 0.5.0, root README Plugins table agreeing
# ---------------------------------------------------------------------------

PLUGIN_VERSION="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$PLUGIN_JSON" 2>/dev/null | head -1)"
check "plugin.json version is 0.5.0 (this block's PR group)" \
  "$PLUGIN_VERSION" "0.5.0"

ROOT_ROW_STATUS="$(grep -E '^\|[[:space:]]*\[?statusline[](]' "$ROOT_README" 2>/dev/null | head -1 \
  | awk -F'|' '{ print $3 }' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
check "root README Plugins-table row for statusline agrees with plugin.json" \
  "$ROOT_ROW_STATUS" "✅ v$PLUGIN_VERSION"

# ---------------------------------------------------------------------------
# 7. Relationships entries survive the rewrite (contract edge case)
# ---------------------------------------------------------------------------

RELATIONSHIPS="$(section '## Relationships to other plugins')"
check "'Relationships to other plugins' section is non-empty" \
  "$([ -n "$RELATIONSHIPS" ] && echo yes || echo no)" "yes"
check "Relationships keeps the tracking-plugin entry" \
  "$(has_re 'tracking' "$RELATIONSHIPS")" "yes"
check "Relationships keeps the agent-dash entry" \
  "$(has_fixed 'agent-dash' "$RELATIONSHIPS")" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
