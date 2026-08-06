#!/bin/bash
# Test for Blocks B06 (docs-attribution) and B11 (docs-render-refresh).
# Authoritative contract in both cases: the HTML-comment docblock at the top of
# plugins/statusline/README.md. B06's docblock is long gone (section 1 pins
# that); B11's is the one currently there, and section 8 pins that it goes too.
#
# --- B06 (the pre-existing sections 0-7) ------------------------------------
# Covers
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
#   (6) plugin.json is at or above 0.5.3 (the version this block's work
#       shipped at) and the root README.md Plugins-table row agrees with
#       whatever the manifest currently says. A floor, not an exact pin: an
#       exact pin makes every later unrelated bump of this plugin a failure
#       here, and version-bump-lint already gates that a bump happens at all.
#       version-bump-lint and readme-lint both gate this; checking it here
#       fails it in the inner loop instead of in CI.
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
# --- B11 docs-render-refresh (sections 8-16) --------------------------------
# B11 brings this README (and plugin.json's description) into agreement with
# the emoji-free render B09/B10 already ship. Prose IS the implementation for
# that block, so every assertion below is structural or textual over the file
# — but wherever the clause is "the prose agrees with the render", the
# expectation is DERIVED from a real scripts/context.sh render rather than
# transcribed. B09 and B10 are merged into this branch, so the renderer really
# does emit the emoji-free line these checks read off it.
#
# The three derivations, and what each one buys:
#
#   - THE EXAMPLE BLOCK. The contract requires the README's two-line example to
#     match "character for character, what scripts/context.sh actually
#     produces". A literal equality is impossible: %t, %/d, the trend arrow and
#     the countdown are all functions of the wall-clock instant the render
#     happens at, so no fixed example can equal a live render's digits. What IS
#     invariant is everything else, so the two are compared as SKELETONS (see
#     skeleton() below) — numbers, trend direction and countdown replaced by
#     placeholders, and the labels, group order, separators, punctuation and
#     alphabet left standing. Those are exactly the parts B11 changes. The
#     fixture takes its model name and effort tier from the example's own model
#     group, so the check is about the render's contribution and not about
#     which model the example happens to show.
#   - THE PR TAG VOCABULARY. classify_pr_tag is called directly (context.sh
#     sourced in a subshell, the way context.test.sh section 25a does it) and
#     the six tags it emits are then REQUIRED in the PR-badge paragraph. A tag
#     renamed in the renderer therefore fails the prose by name.
#   - THE METER LABELS AND THE GROUP COUNT. Both read off the same live render:
#     the label leading each of groups 2/3/4 must be the label its bullet
#     names, and the number of groups the "Line 2" preamble claims must be the
#     number the renderer actually joins.
#
# Three traps this file deliberately does NOT fall into:
#
#   1. "No non-ASCII anywhere" is the WRONG emoji check. │, ▲, ▼, ↑ and ↓ stay
#      in the prose because they stay in the render, and the contract says so
#      explicitly. emoji_hits() strips those (plus ordinary typography) and
#      flags whatever non-ASCII is left, and a companion check asserts each of
#      the five is still present so the strip cannot pass vacuously.
#   2. The env-var table assertions stay DERIVED (section 2, untouched). B11
#      changes no knob, so section 16 adds only a row-count equality on top.
#   3. lib/burn-theme.sh's CONTENTS are not asserted about. The contract asks
#      the prose to describe what that library CONTRIBUTES to the render, and
#      the deletion of its dead mascot/pet code is a different block's clause.
#
# Section 3's "describes the pet group" check has been RETARGETED rather than
# deleted, per the same convention context.test.sh follows: the clause it
# carried (the render's group inventory is described accurately) still exists,
# and what changed is that the pet is no longer one of the groups.
#
# --- B17 docs-colour-refresh (sections 17-21) -------------------------------
# B17 brings three passages of this README into agreement with the colours
# B13-B16 now render: the Context bullet, the "Reading the burnrate figures"
# section, and the upstream-attribution paragraph. Prose is the implementation
# again, so the assertions are textual over the file — but every NUMBER in
# them is DERIVED from lib/burn-theme.sh. That is the clause this block exists
# for: the failure it prevents is a README naming a threshold the source does
# not have, and a hard-coded 60 in this file would be that same defect wearing
# a test's clothes.
#
# The three derivations, and what each buys:
#
#   - THE CTX BANDS. burn_ctx_color's body is read out of lib/burn-theme.sh,
#     its `(( pct >= N ))` arms parsed into (threshold, colour code) pairs and
#     its fallthrough arm read as the floor colour. The Context bullet's own
#     colour words and percentages are then extracted IN ORDER OF APPEARANCE
#     and compared against that scale as SEQUENCES. Sequences rather than
#     per-band proximity, because a band list is a dense comma list in which
#     every number sits within a few characters of two different colour words:
#     "yellow at 20%, orange at 40%" would satisfy a proximity check for
#     (20, orange) as readily as for (20, yellow). Order is what actually
#     distinguishes a correct list from a shuffled one, and it survives any
#     phrasing that walks the scale monotonically. A band moved from 60 to 55
#     fails by name, in both directions of the comparison.
#   - THE TREND SCALE. burn_trend_color yields the dead-band magnitude and its
#     colour, the bands above it, and the one below the line. The prose is
#     asked for the dead band's number paired with its colour, the word "warm"
#     for the bands above, and the below-the-line colour tied to running
#     behind — which is what the contract asks that section to gain, and no
#     more. 8 and 15 are deliberately NOT required in the prose: a threshold
#     the README never names cannot drift, and demanding it would be this
#     file inventing a clause.
#   - THE DIFFSTAT PAIR. burn_diff_color's two arms give the colours "add" and
#     "del" take, and the prose has to pair each with the right half of
#     `+added/-removed`.
#
# Three guards stop those derivations from passing vacuously. Each parse
# asserts HOW MANY arms it found, so an empty parse (function renamed, the
# `(( pct >= N ))` shape rewritten) is a red test rather than a green one that
# compares nothing. Every colour code the source emits must resolve to a name
# this file can look for, so a recoloured band fails here by code rather than
# dropping silently out of the comparison. And every band above the trend's
# dead band must really be a warm colour, since "warm colours" is the claim
# the prose is made to carry.
#
# The one thing NOT derived is the code -> English name map (40 -> green, and
# so on): no amount of parsing turns 208 into the word a reader sees. It is
# not a threshold, and it is guarded — an unmapped code fails by name.
#
# NOT asserted, deliberately: that every percentage the Context bullet names
# is one of the thresholds — the reverse direction of the check above, which
# is the shape section 2 uses on the env-var table. The bullet may
# legitimately name 100% as the point compaction fires, which is not a band
# boundary, so the reverse direction would fail on correct prose. The forward
# direction is what the contract's Errors clause asks for.
#
# The edge case rides on SENTENCE scoping. "Idle time" has to stay in the
# README in its non-colour sense (the published `level`, the .ctx-status.json
# schema), so a blanket "the README no longer says idle" would be wrong and
# would force the implementer to delete true documentation. What is asserted
# instead is that no sentence making a COLOUR claim names idle, while a
# sentence naming `level` still does.
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
# RETARGETED by B11. The clause is "the render's group inventory is described
# accurately"; B09 deleted the pet group, so describing it is now the defect.
# The whole-file version of the same clause is in section 11.
check "'What to expect' no longer describes a pet group (B09 deleted it)" \
  "$(has_re '(^|[^a-z])pet([^a-z]|$)' "$WTE")" "no"

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
# 6. Version: plugin.json at or above 0.5.3, root README Plugins table agreeing
# ---------------------------------------------------------------------------

# A floor, never equality, in the repo's usual `sort -V` idiom. An exact pin
# turns every later unrelated bump of this plugin into a failure here, and
# that a bump happens at all is already gated by version-bump-lint; what is
# worth asserting is the floor this block's work shipped at, plus the root
# README agreeing with whatever the manifest currently says.
VERSION_FLOOR="0.5.3"
PLUGIN_VERSION="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$PLUGIN_JSON" 2>/dev/null | head -1)"
check "plugin.json version $PLUGIN_VERSION is at or above the $VERSION_FLOOR floor" \
  "$([ -n "$PLUGIN_VERSION" ] \
      && [ "$(printf '%s\n%s\n' "$VERSION_FLOOR" "$PLUGIN_VERSION" | sort -V | head -1)" = "$VERSION_FLOOR" ] \
      && echo yes || echo no)" "yes"

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

# ===========================================================================
# B11 docs-render-refresh
# ===========================================================================

# ---------------------------------------------------------------------------
# 8. B11 helpers, and the contract comment's own removal
# ---------------------------------------------------------------------------

CONTEXT_SH="$PLUGIN_DIR/scripts/context.sh"
ESC=$(printf '\033')

check "scripts/context.sh exists (the render oracle for every derived check)" \
  "$([ -f "$CONTEXT_SH" ] && echo yes || echo no)" "yes"

# plugin.json's description, de-quoted. sed rather than jq for the same reason
# the version read above uses sed: this file has no jq dependency of its own.
PLUGIN_DESC="$(sed -nE 's/^[[:space:]]*"description"[[:space:]]*:[[:space:]]*"(.*)",[[:space:]]*$/\1/p' \
  "$PLUGIN_JSON" 2>/dev/null | head -1)"
check "plugin.json's description is readable (oracle is not empty)" \
  "$([ -n "$PLUGIN_DESC" ] && echo yes || echo no)" "yes"

trim() { # text
  local t="$1"
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  printf '%s' "$t"
}

# paragraph_in(text needle): the blank-line-delimited paragraph of TEXT holding
# the first occurrence of the fixed string NEEDLE. Paragraphs rather than
# whole sections, because several B11 clauses are about ONE paragraph and the
# neighbouring prose legitimately keeps words the clause forbids in its own.
paragraph_in() { # text needle
  awk -v needle="$2" '
    /^[[:space:]]*$/ { if (hit) { for (i = 0; i < n; i++) print buf[i]; exit } n = 0; next }
    { buf[n++] = $0; if (index($0, needle)) hit = 1 }
    END { if (hit) for (i = 0; i < n; i++) print buf[i] }
  ' <<<"$1"
}

# bullet_in(text pat): one "- **Name** ..." list item, from the line matching
# the ERE PAT through its continuation lines, stopping at the next item or a
# blank line. PAT must avoid backslash escapes: awk processes them in a -v
# assignment, so `\*` would arrive as a bare `*` quantifier. Use [*] instead.
bullet_in() { # text pat
  awk -v pat="$2" '
    !inb && $0 ~ pat { inb = 1; print; next }
    inb && (/^- / || /^[[:space:]]*$/) { exit }
    inb { print }
  ' <<<"$1"
}

# first_paragraph(text): the opening blurb — the first paragraph after the H1.
first_paragraph() { # text
  awk '
    /^# / { seen = 1; next }
    !seen { next }
    /^[[:space:]]*$/ { if (started) exit; next }
    { started = 1; print }
  ' <<<"$1"
}

# first_fence(text): the contents of the first ``` fenced block in TEXT.
first_fence() { # text
  awk '
    /^```/ { if (inf) exit; inf = 1; next }
    inf { print }
  ' <<<"$1"
}

# nth_group(line n) / group_label(line n): the Nth │-separated group of a
# burnrate line, trimmed, and its leading token. Parameter expansion rather
# than `awk -F'│'`: a multibyte field separator is not portable across awks.
nth_group() { # line n
  local l="$1" n="$2" g
  while [ "$n" -gt 1 ]; do l="${l#*│}"; n=$(( n - 1 )); done
  g="${l%%│*}"
  trim "$g"
}
group_label() { # line n
  local g; g="$(nth_group "$1" "$2")"; printf '%s' "${g%% *}"
}
sep_count() { # line
  printf '%s' "$1" | grep -o '│' | wc -l | tr -d ' '
}

# The non-ASCII characters this README may legitimately hold: the five
# ambiguous-width symbols the render still emits — which the contract requires
# to STAY — plus ordinary typography. Anything else non-ASCII is an emoji.
# LC_ALL=C so the byte range means bytes rather than whatever the ambient
# locale collates into it.
strip_allowed() { # text
  local t="$1"
  t="${t//│/}"; t="${t//▲/}"; t="${t//▼/}"; t="${t//↑/}"; t="${t//↓/}"
  t="${t//—/}"; t="${t//→/}"; t="${t//·/}"
  printf '%s\n' "$t"
}
# emoji_hits(text): the first offending lines, or "" when the text is clean.
# Reports the line rather than a yes/no so a failure names what to delete.
emoji_hits() { # text
  one_line "$(strip_allowed "$1" | LC_ALL=C grep -n '[^ -~]' | head -2)"
}

B11_WD="$TMP/b11-wd"; mkdir -p "$B11_WD"

# b11_render(model effort): scripts/context.sh's two lines for a synthetic
# payload, ANSI stripped. Hermetic the same way context.test.sh's harness is:
# a plain temp cwd (not a git repo, no .local, so line 1 is the bare path and
# no background refresher forks), temp ccost/cache dirs, and caching disabled.
# Every group is fed so the full four-group line renders: a fixture that let a
# group vanish would compare the example against a shorter line than the one
# the README is describing.
b11_render() { # model effort
  local now r5 r7 json
  now=$(date +%s); r5=$(( now + 17670 )); r7=$(( now + 3 * 86400 ))
  json="{\"workspace\":{\"current_dir\":\"$B11_WD\"},\"transcript_path\":\"\""
  json="$json,\"model\":{\"display_name\":\"$1\"},\"effort\":{\"level\":\"$2\"}"
  json="$json,\"context_window\":{\"context_window_size\":1000000,\"total_input_tokens\":30000}"
  json="$json,\"rate_limits\":{\"five_hour\":{\"used_percentage\":1,\"resets_at\":$r5}"
  json="$json,\"seven_day\":{\"used_percentage\":32,\"resets_at\":$r7}}"
  json="$json,\"cost\":{\"total_lines_added\":503,\"total_lines_removed\":16}}"
  printf '%s' "$json" \
    | env CLAUDE_PROJECTS_DIR="$TMP/b11-projects" CCOST_CACHE_DIR="$TMP/b11-ccost" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$TMP/b11-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        bash "$CONTEXT_SH" 2>/dev/null \
    | sed -E "s/${ESC}\[[0-9;]*m//g"
}

# skeleton(line): LINE with every figure the render computes from live data
# replaced by a placeholder — signed/decimal numbers by N, the ▲/▼ trend
# DIRECTION by T, and the reset countdown (NhNm, or Nm under the hour) by CD.
# Those four are the only things that cannot be equal between a printed example
# and a live render: the pacing figures move with the wall clock, the trend
# direction flips with the data, and the countdown shape changes on the hour.
# Everything the block actually changes — the labels, the group order, the
# separators, the parens, the alphabet — survives the normalisation and is
# therefore compared exactly.
skeleton() { # line
  printf '%s' "$1" \
    | sed -e 's/▲/T/g' -e 's/▼/T/g' \
    | sed -E -e 's/[-+]?[0-9]+(\.[0-9]+)?/N/g' -e 's/NhNm/CD/g' -e 's/[(]Nm[)]/(CD)/g'
}

# b11_tag_set(): the tags classify_pr_tag emits, one per line, deduplicated.
# One input tuple per bucket, transcribed from context.test.sh section 25a —
# the CLASSIFICATION is B10's clause with its own coverage there, and what is
# derived here is only the output VOCABULARY the prose has to name. context.sh
# is sourced in a subshell exactly as that section does it (no `exit`, no
# `set -e`, its own dir resolved from BASH_SOURCE[0], stdin fed a payload so
# the render at source time has something to consume).
b11_min_json="{\"workspace\":{\"current_dir\":\"$B11_WD\"},\"transcript_path\":\"\"}"
b11_tag_set() {
  printf '%s' "$b11_min_json" | (
    export CLAUDE_PROJECTS_DIR="$TMP/b11-projects" CCOST_CACHE_DIR="$TMP/b11-ccost"
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000
    export CLAM_STATUSLINE_CACHE_DIR="$TMP/b11-tag-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0
    # This invocation runs shellcheck without -x, so even a real path hint
    # can't be followed (that trades SC1090 for SC1091); source=/dev/null
    # tells it there is nothing to follow and fully silences both.
    # shellcheck source=/dev/null
    . "$CONTEXT_SH" >/dev/null 2>&1
    printf '%s\n' "$(classify_pr_tag "Open" "Changes Requested" "Pass" 0)"
    printf '%s\n' "$(classify_pr_tag "Draft" "None" "Running" 0)"
    printf '%s\n' "$(classify_pr_tag "Queue Failed" "Approved" "Pass" 0)"
    printf '%s\n' "$(classify_pr_tag "Open" "None" "Running" 0)"
    printf '%s\n' "$(classify_pr_tag "In Queue" "Approved" "Pass" 0)"
    printf '%s\n' "$(classify_pr_tag "Merged" "Approved" "Pass" 0)"
  ) 2>/dev/null | grep -v '^$' | sort -u
}

# lib_upstream_author(file): the author named in a burn-* library's own MIT
# header, read with the same expression section 5 uses on burn-math.sh.
lib_upstream_author() { # file
  sed -nE 's/^#.*MIT © (.+)$/\1/p' "$1" 2>/dev/null | head -1
}

# The prose-block rule: a remove-at-acceptance contract that survives ships as
# a duplicate spec every future reader pays for. Asserted against the RAW file
# and on the MARKER rather than on B11's title, so the next prose block's
# contract is covered by this same check without anyone remembering to add one.
check "no '<!-- Contract:' block survives in the raw plugin README" \
  "$(grep -qF '<!-- Contract:' "$PLUGIN_README" && echo present || echo absent)" \
  "absent"

# ---------------------------------------------------------------------------
# 9. The file's alphabet: no emoji, and the render's own symbols kept
# ---------------------------------------------------------------------------

check "no emoji anywhere in the plugin README's prose" \
  "$(emoji_hits "$BODY")" ""
check "no emoji in plugin.json's description either" \
  "$(emoji_hits "$PLUGIN_DESC")" ""

# Non-vacuity for the two checks above: strip_allowed exempts five symbols, and
# they are exactly the five the contract requires to STAY because the render
# still emits them. Without these a README that had deleted │ and the arrows
# along with the emoji would sail through the alphabet check.
check "the dim │ separator is kept in the prose" "$(has_fixed '│' "$BODY")" "yes"
check "the ▲ trend arrow is kept in the prose"   "$(has_fixed '▲' "$BODY")" "yes"
check "the ▼ trend arrow is kept in the prose"   "$(has_fixed '▼' "$BODY")" "yes"
check "the ↑ git-sync arrow is kept in the prose" "$(has_fixed '↑' "$BODY")" "yes"
check "the ↓ git-sync arrow is kept in the prose" "$(has_fixed '↓' "$BODY")" "yes"

# ---------------------------------------------------------------------------
# 10. The pet, its moods and the per-model mascots are gone
# ---------------------------------------------------------------------------
# "Removed, not reworded. Nothing replaces it." Word-bounded so a substring
# match inside an unrelated word cannot fail the file.

check "no reference to the pet survives in the plugin README" \
  "$(has_re '(^|[^A-Za-z])pets?([^A-Za-z]|$)' "$BODY")" "no"
check "nor to its moods" \
  "$(has_re '(^|[^A-Za-z])moods?([^A-Za-z]|$)' "$BODY")" "no"
check "nor to the per-model mascots" \
  "$(has_re '(^|[^A-Za-z])mascots?([^A-Za-z]|$)' "$BODY")" "no"
check "plugin.json's description drops the pet clause too" \
  "$(has_re '(^|[^A-Za-z])pets?([^A-Za-z]|$)' "$PLUGIN_DESC")" "no"
check "and the mood it tracked" \
  "$(has_re '(^|[^A-Za-z])moods?([^A-Za-z]|$)' "$PLUGIN_DESC")" "no"

# ---------------------------------------------------------------------------
# 11. The opening blurb still reads as a sentence
# ---------------------------------------------------------------------------
# Whether it reads NATURALLY is a prose-quality clause deferred to acceptance;
# what is mechanical is that the deletion left no wreckage behind it.

BLURB="$(one_line "$(first_paragraph "$BODY")")"
check "the opening blurb is identifiable" \
  "$([ -n "$BLURB" ] && echo yes || echo no)" "yes"
check "the opening blurb still names the meter it now ends on" \
  "$(has_fixed 'context-window occupancy' "$BLURB")" "yes"
check "the opening blurb has no dangling connector where the pet clause was" \
  "$(has_re '(,|and)[[:space:]]*\.' "$BLURB")" "no"
check "the opening blurb has no orphaned space before a full stop" \
  "$(has_re '[[:space:]]+\.' "$BLURB")" "no"

# ---------------------------------------------------------------------------
# 12. The example block IS a render (the contract's character-for-character
#     clause, compared as skeletons — see the header for why)
# ---------------------------------------------------------------------------

WTE_FENCE="$(first_fence "$WTE")"
check "'What to expect' still shows an example render block" \
  "$([ -n "$WTE_FENCE" ] && echo yes || echo no)" "yes"
check "the example block is exactly the two lines the render emits" \
  "$(printf '%s\n' "$WTE_FENCE" | wc -l | tr -d ' ')" "2"

EX_L1="$(trim "$(printf '%s\n' "$WTE_FENCE" | sed -n '1p')")"
EX_L2="$(trim "$(printf '%s\n' "$WTE_FENCE" | sed -n '2p')")"

# The fixture mirrors the example's OWN model group. Feeding those two tokens
# back into the renderer is deliberate: they are free text the render echoes
# verbatim, so they carry no clause, and holding them equal is what lets every
# token that DOES carry a clause be compared exactly. Their alphabet is covered
# by section 9, which is what stops a surviving mascot from riding along.
EX_G1="$(nth_group "$EX_L2" 1)"
EX_MODEL="${EX_G1% *}"
EX_EFFORT="${EX_G1##* }"
check "the example's model group is readable (fixture oracle is not empty)" \
  "$([ -n "$EX_MODEL" ] && [ -n "$EX_EFFORT" ] && echo yes || echo no)" "yes"

B11_OUT="$(b11_render "$EX_MODEL" "$EX_EFFORT")"
B11_LINE2="$(printf '%s\n' "$B11_OUT" | sed -n '2p')"
check "the fixture render produced a burnrate line (oracle is not empty)" \
  "$([ -n "$B11_LINE2" ] && echo yes || echo no)" "yes"
# Non-vacuity for the comparison below, read off a render whose model name is
# this file's own ASCII literal rather than the example's: agreeing with the
# renderer only means "clean" if the renderer is itself clean, and asking the
# example-seeded render that question would just be asking about the example.
check "the renderer's own burnrate line is emoji-free, so agreeing with it means clean" \
  "$(emoji_hits "$(printf '%s\n' "$(b11_render Opus max)" | sed -n '2p')")" ""

check "the example's line 2 is what scripts/context.sh actually renders" \
  "$(skeleton "$EX_L2")" "$(skeleton "$B11_LINE2")"

# The skeleton normalises digits, which would let a mislabelled group through
# (`9h` and `5h` both reduce to `Nh`). These pin the labels themselves, derived
# from the same live render.
WK_LABEL="$(group_label "$B11_LINE2" 2)"
CTX_LABEL="$(group_label "$B11_LINE2" 3)"
FIVE_LABEL="$(group_label "$B11_LINE2" 4)"
check "the render's three meter labels are readable (oracle is not empty)" \
  "$([ -n "$WK_LABEL" ] && [ -n "$CTX_LABEL" ] && [ -n "$FIVE_LABEL" ] && echo yes || echo no)" "yes"
check "the example's weekly group leads with the label the render emits" \
  "$(group_label "$EX_L2" 2)" "$WK_LABEL"
check "the example's session group leads with the label the render emits" \
  "$(group_label "$EX_L2" 3)" "$CTX_LABEL"
check "the example's 5-hour group leads with the label the render emits" \
  "$(group_label "$EX_L2" 4)" "$FIVE_LABEL"

# The signs in +added/-removed survive the skeleton as bare N/N, so they are
# pinned separately — with a guard proving the render really prints them.
check "the render prints the +added/-removed pair (guard for the next check)" \
  "$(has_re '\+[0-9]+/-[0-9]+' "$B11_LINE2")" "yes"
check "the example keeps that +added/-removed pair verbatim" \
  "$(has_re '\+[0-9]+/-[0-9]+' "$EX_L2")" "yes"

# Line 1 is not compared whole — its path, branch, badge files, MODE and State
# all come from a worktree the example is free to invent — but its alphabet is
# the block's clause and a PR badge is now a word.
check "the example's line 1 is emoji-free" "$(emoji_hits "$EX_L1")" ""

B11_TAGS="$(b11_tag_set)"
check "the PR tag vocabulary is derivable from context.sh (oracle is not empty)" \
  "$([ -n "$B11_TAGS" ] && echo yes || echo no)" "yes"
# Guards the derivation: six input tuples that must map to six DISTINCT tags.
# A bucket chain collapsed to one arm would still be "not empty" without this.
check "the six buckets really produce six distinct tags" \
  "$(printf '%s\n' "$B11_TAGS" | wc -l | tr -d ' ')" "6"
b11_tag_named=no
for _tag in $B11_TAGS; do
  [ "$(has_re '(^|[^A-Za-z])'"$_tag"'([^A-Za-z]|$)' "$EX_L1")" = yes ] && b11_tag_named=yes
done
check "the example's line 1 shows the PR badge as one of the render's text tags" \
  "$b11_tag_named" "yes"

# ---------------------------------------------------------------------------
# 13. The "Line 1" and "Line 2" prose
# ---------------------------------------------------------------------------

LINE1_P="$(paragraph_in "$WTE" '.pr-status.json')"
check "the 'Line 1' paragraph is identifiable" \
  "$([ -n "$LINE1_P" ] && echo yes || echo no)" "yes"
check "the 'Line 1' paragraph no longer calls the State segment 'emoji + colour'" \
  "$(has_fixed 'emoji + colour' "$LINE1_P")" "no"
check "the 'Line 1' paragraph sources the State colour from the shared manifest" \
  "$(has_re 'colour from the shared states manifest' "$LINE1_P")" "yes"
# "The PR badge description names the text tags" — every tag, derived, so a tag
# renamed in classify_pr_tag fails the prose by name.
for _tag in $B11_TAGS; do
  check "the PR-badge description names the '$_tag' tag the render emits" \
    "$(has_re '(^|[^A-Za-z])'"$_tag"'([^A-Za-z]|$)' "$LINE1_P")" "yes"
done

LINE2_P="$(paragraph_in "$WTE" '**Line 2')"
check "the 'Line 2' preamble is identifiable" \
  "$([ -n "$LINE2_P" ] && echo yes || echo no)" "yes"
B11_GROUPS=$(( $(sep_count "$B11_LINE2") + 1 ))
case "$B11_GROUPS" in
  1) B11_GROUPS_WORD=one ;;  2) B11_GROUPS_WORD=two ;;   3) B11_GROUPS_WORD=three ;;
  4) B11_GROUPS_WORD=four ;; 5) B11_GROUPS_WORD=five ;;  *) B11_GROUPS_WORD="" ;;
esac
check "the render's group count is nameable (oracle is not empty)" \
  "$([ -n "$B11_GROUPS_WORD" ] && echo yes || echo no)" "yes"
check "the 'Line 2' preamble names the group count the render produces ($B11_GROUPS_WORD)" \
  "$(has_re '(^|[^a-z])'"$B11_GROUPS_WORD"' groups' "$LINE2_P")" "yes"
check "the 'Line 2' preamble no longer claims five groups" \
  "$(has_re '(^|[^a-z])five groups' "$LINE2_P")" "no"
check "the 'Line 2' preamble no longer promises an emoji with no number" \
  "$(has_re 'emoji with no number' "$LINE2_P")" "no"
check "the 'Line 2' preamble makes that promise about a label instead" \
  "$(has_re '(^|[^A-Za-z])labels?([^A-Za-z]|$)' "$LINE2_P")" "yes"

MODEL_B="$(bullet_in "$WTE" '^- [*][*]Model[*][*]')"
WEEK_B="$(bullet_in "$WTE" '^- [*][*]Weekly')"
CTX_B="$(bullet_in "$WTE" '^- [*][*]Context[*][*]')"
FIVE_B="$(bullet_in "$WTE" '^- [*][*]5-hour')"
check "all four 'Line 2' segment bullets are identifiable" \
  "$([ -n "$MODEL_B" ] && [ -n "$WEEK_B" ] && [ -n "$CTX_B" ] && [ -n "$FIVE_B" ] \
     && echo yes || echo no)" "yes"
check "the Weekly bullet names the label the render emits ($WK_LABEL)" \
  "$(has_fixed "$WK_LABEL" "$WEEK_B")" "yes"
check "the Context bullet names the label the render emits ($CTX_LABEL)" \
  "$(has_fixed "$CTX_LABEL" "$CTX_B")" "yes"
check "the 5-hour bullet names the label the render emits ($FIVE_LABEL)" \
  "$(has_fixed "$FIVE_LABEL" "$FIVE_B")" "yes"
# The mascot LIST goes; the hue families it was attached to stay, because the
# model name still drifts through them.
check "the Model bullet keeps the drifting hue families" \
  "$(has_re 'rainbow|hue|drift' "$MODEL_B")" "yes"

# ---------------------------------------------------------------------------
# 14. The states-manifest and libraries paragraphs describe what RENDERS
# ---------------------------------------------------------------------------

STATES_P="$(paragraph_in "$COMMANDS" 'session-states.md')"
check "the states-manifest paragraph is identifiable" \
  "$([ -n "$STATES_P" ] && echo yes || echo no)" "yes"
# lib/states.tsv KEEPS its emoji column — this is a claim about what renders,
# not about what the file contains, so nothing here reads states.tsv.
check "the states-manifest paragraph no longer calls the emoji this renderer's mapping" \
  "$(has_fixed 'emoji and colour' "$STATES_P")" "no"
check "the states-manifest paragraph still names the colour it does render" \
  "$(has_re 'colour' "$STATES_P")" "yes"
check "the states-manifest paragraph still says the protocol leaves that mapping private" \
  "$(has_re 'private|own mapping' "$STATES_P")" "yes"

LIBS_P="$(paragraph_in "$COMMANDS" 'lib/burn-theme.sh')"
check "the libraries paragraph is identifiable" \
  "$([ -n "$LIBS_P" ] && echo yes || echo no)" "yes"
# What burn-theme CONTRIBUTES, not what the file holds: its dead mascot and pet
# code is a different block's clause and is deliberately not asserted about.
check "the libraries paragraph no longer lists a pet frame among what renders" \
  "$(has_re 'pet frame' "$LIBS_P")" "no"
check "the libraries paragraph keeps burn-theme's colour scales" \
  "$(has_re 'colour scale' "$LIBS_P")" "yes"
check "the libraries paragraph keeps burn-theme's countdowns" \
  "$(has_re 'countdown' "$LIBS_P")" "yes"

# ---------------------------------------------------------------------------
# 15. Provenance and the two baselined references survive the rewrite
# ---------------------------------------------------------------------------
# "The port is still a port; dropping its decorations does not drop its
# credit." The ONE permitted change is the enumeration of ported ideas, which
# loses the pet along with the feature — covered by section 10.

ATTRIB="$(section '## Attribution')"
check "'Attribution' section is non-empty" \
  "$([ -n "$ATTRIB" ] && echo yes || echo no)" "yes"
check "the attribution keeps the upstream URL" \
  "$(has_fixed "$UPSTREAM_URL" "$ATTRIB")" "yes"
check "the attribution keeps the MIT licence" \
  "$(has_re '(^|[^A-Za-z])MIT([^A-Za-z]|$)' "$ATTRIB")" "yes"
check "the attribution still states the notice is carried in full" \
  "$(has_re 'copyright notice in full' "$ATTRIB")" "yes"
# Both halves of that claim: the prose names all three libraries, and all three
# really do carry the same upstream notice burn-math.sh's header carries.
for _lib in burn-math.sh burn-tick.sh burn-theme.sh; do
  check "the attribution names lib/$_lib among the three carrying the notice" \
    "$(has_fixed "lib/$_lib" "$ATTRIB")" "yes"
  check "and lib/$_lib really carries it (same author burn-math.sh's header names)" \
    "$(lib_upstream_author "$PLUGIN_DIR/lib/$_lib")" "$UPSTREAM_AUTHOR"
done

# scripts/architecture-lint-baseline.txt baselines an `english` reference in
# BOTH files this block edits, and architecture-lint exits 1 on a STALE
# baseline entry exactly as it does on a new hit. Deleting either mention while
# tidying emoji out turns the lint red for a reason that looks nothing like the
# edit that caused it, so both are pinned here, in the inner loop.
check "the Relationships entry the baseline covers is kept verbatim" \
  "$(has_fixed 'canonical source of the session-States manifest' "$RELATIONSHIPS")" "yes"
check "plugin.json's description keeps the reference the baseline covers" \
  "$(has_fixed "the tracking plugin's session State" "$PLUGIN_DESC")" "yes"   # architecture-lint: allow this assertion pins that the baselined reference survives B11's description edit

# ---------------------------------------------------------------------------
# 16. B11 adds, removes and renames no env knob
# ---------------------------------------------------------------------------
# Section 2 already compares the table against the derivation as SETS. This
# adds the count, which is what makes "changes no knob" a statement about size
# as well as membership, and keeps the derived-not-literal property intact.

check "the env-var table's row count still equals the derivation's" \
  "$(wc -l < "$TMP/documented" | tr -d ' ')" "$(wc -l < "$TMP/derived" | tr -d ' ')"

# ===========================================================================
# B17 docs-colour-refresh
# ===========================================================================

# ---------------------------------------------------------------------------
# 17. Helpers, and the colour scales derived from lib/burn-theme.sh
# ---------------------------------------------------------------------------

BURN_THEME="$PLUGIN_DIR/lib/burn-theme.sh"
check "lib/burn-theme.sh exists (the colour oracle for sections 18-20)" \
  "$([ -f "$BURN_THEME" ] && echo yes || echo no)" "yes"

# b17_fn_body(name): one function's body from lib/burn-theme.sh, from its
# `name() {` line to the closing brace in column 1. Reading the SOURCE rather
# than sourcing the file and calling the function is deliberate: the
# thresholds are what this section is about, and a function only ever hands
# back the colour for the value you already chose to ask about.
b17_fn_body() { # name
  awk -v fn="$1" '
    $0 == fn "() {" { inb = 1; next }
    inb && /^\}/ { exit }
    inb { print }
  ' "$BURN_THEME"
}

# b17_colour_name(code): the English word this README is expected to use for a
# 256-colour code. The only hard-coded map here, and not a threshold — a
# number cannot yield a colour word. Unmapped codes print nothing, which the
# guards below turn into a named failure rather than a silent skip.
b17_colour_name() { # code
  case "$1" in
    40)  printf 'green'  ;;
    214) printf 'yellow' ;;
    208) printf 'orange' ;;
    196) printf 'red'    ;;
    245) printf 'grey'   ;;
    *)   printf ''       ;;
  esac
}

# b17_word(word): an ERE matching WORD on its own, so `red` is not found
# inside `coloured`; `grey` also answers to the American spelling.
b17_word() { # word
  case "$1" in
    grey) printf '(^|[^A-Za-z])gre[ay]([^A-Za-z]|$)' ;;
    *)    printf '(^|[^A-Za-z])%s([^A-Za-z]|$)' "$1" ;;
  esac
}

# b17_num(n): an ERE matching the integer N with no digit either side, so a
# threshold of 60 is not found inside 160.
b17_num() { printf '(^|[^0-9])%s([^0-9]|$)' "$1"; }

# b17_near(text a b gap): yes when EREs A and B occur within GAP characters of
# each other, either order, on TEXT flattened to one line. Flattened because
# the README wraps at 76 columns and every real claim spans a line break.
b17_near() { # text a b gap
  local flat; flat="$(one_line "$1")"
  if grep -qiE "($2).{0,$4}($3)|($3).{0,$4}($2)" <<<"$flat"; then echo yes; else echo no; fi
}

# b17_sentences(text): TEXT flattened and split into sentences on ". ". The
# README's dotted identifiers (`.local/.ctx-status.json`, `.effort.level`)
# carry no space after the dot, so they survive the split intact.
b17_sentences() { # text
  one_line "$1" | awk '{ n = split($0, s, /\. /); for (i = 1; i <= n; i++) print s[i] }'
}
# b17_claims(text ere): just the sentences of TEXT matching ERE — the unit a
# claim is made in, and the scope the colour/idle edge case needs.
b17_claims() { # text ere
  b17_sentences "$1" | grep -iE "$2"
}

# b17_ordered(text listfile): the whole words and whole digit runs of TEXT that
# appear in LISTFILE, in order of appearance, lowercased, consecutive repeats
# collapsed. Whole tokens only, so `red` is not found inside `coloured` and 60
# is not found inside 160; consecutive repeats collapsed so "green below 20%,
# yellow at 20%" reads as one boundary rather than two.
b17_ordered() { # text listfile
  one_line "$1" | grep -oE '[A-Za-z]+|[0-9]+' | tr '[:upper:]' '[:lower:]' \
    | grep -xF -f "$2" \
    | awk '$0 != prev { print } { prev = $0 }' \
    | tr '\n' ' ' | sed -e 's/  *$//'
}

# b17_item(text pat): one top-level "- ..." list item, from the line matching
# ERE PAT to the next item, heading or fence. bullet_in() above stops at a
# blank line as well; this one does not, because B17's Context bullet has to
# carry two claims and a second paragraph inside the item is legitimate
# markdown that would otherwise be silently cut off mid-assertion.
b17_item() { # text pat
  awk -v pat="$2" '
    !inb && $0 ~ pat { inb = 1; print; next }
    inb && (/^- / || /^#/ || /^```/) { exit }
    inb { print }
  ' <<<"$1"
}

# b17_subsection(heading): the body of an H3 up to the next heading of any
# level. section() above only cuts on "## ", and "Reading the burnrate
# figures" is an H3 inside "## What to expect".
b17_subsection() { # exact "### Heading" line
  awk -v heading="$1" '
    $0 == heading { flag = 1; next }
    flag && /^#+[[:space:]]/ { exit }
    flag { print }
  ' <<<"$BODY"
}

# --- the ctx scale ---------------------------------------------------------
# Each band is one source line carrying both halves:
#   if (( pct >= 60 )); then printf '\033[38;5;196m'; return 0; fi
# and the floor colour is the first arm with no comparison on it — the one
# every value below the lowest threshold falls through to.

B17_CTX_BODY="$(b17_fn_body burn_ctx_color)"
check "burn_ctx_color's body is readable (the ctx threshold oracle is not empty)" \
  "$([ -n "$B17_CTX_BODY" ] && echo yes || echo no)" "yes"

printf '%s\n' "$B17_CTX_BODY" \
  | sed -nE 's/.*pct >= ([0-9]+).*38;5;([0-9]+)m.*/\1 \2/p' > "$TMP/ctx-bands"
B17_CTX_FLOOR="$(printf '%s\n' "$B17_CTX_BODY" | grep -v 'pct >=' \
  | sed -nE 's/.*38;5;([0-9]+)m.*/\1/p' | head -1)"

# Non-vacuity for every ctx check below: a parse that finds nothing would
# compare an empty sequence against an empty expectation and pass silently.
check "the ctx derivation found all three of burn_ctx_color's bands" \
  "$(wc -l < "$TMP/ctx-bands" | tr -d ' ')" "3"
check "the ctx derivation found burn_ctx_color's floor colour (code ${B17_CTX_FLOOR:-none})" \
  "$([ -n "$B17_CTX_FLOOR" ] && echo yes || echo no)" "yes"

# Both directions of the scale. The source lists bands hot-to-cold, and prose
# may walk the scale either way; the sequence checks normalise on that.
B17_CTX_HOT_COL=""; B17_CTX_HOT_NUM=""
B17_CTX_COLD_COL=""; B17_CTX_COLD_NUM=""
B17_CTX_UNMAPPED=""
: > "$TMP/ctx-thresh"; : > "$TMP/ctx-colours"
while read -r _pct _code; do
  [ -n "$_pct" ] || continue
  _name="$(b17_colour_name "$_code")"
  [ -n "$_name" ] || B17_CTX_UNMAPPED="$B17_CTX_UNMAPPED $_code"
  B17_CTX_HOT_COL="$B17_CTX_HOT_COL $_name"; B17_CTX_COLD_COL="$_name $B17_CTX_COLD_COL"
  B17_CTX_HOT_NUM="$B17_CTX_HOT_NUM $_pct";  B17_CTX_COLD_NUM="$_pct $B17_CTX_COLD_NUM"
  printf '%s\n' "$_pct" >> "$TMP/ctx-thresh"
  printf '%s\n' "$_name" >> "$TMP/ctx-colours"
done < "$TMP/ctx-bands"
B17_CTX_FLOOR_NAME="$(b17_colour_name "$B17_CTX_FLOOR")"
if [ -n "$B17_CTX_FLOOR_NAME" ]; then
  printf '%s\n' "$B17_CTX_FLOOR_NAME" >> "$TMP/ctx-colours"
else
  B17_CTX_UNMAPPED="$B17_CTX_UNMAPPED $B17_CTX_FLOOR"
fi
B17_CTX_HOT_COL="$(trim "$B17_CTX_HOT_COL $B17_CTX_FLOOR_NAME")"
B17_CTX_COLD_COL="$(trim "$B17_CTX_FLOOR_NAME $B17_CTX_COLD_COL")"
B17_CTX_HOT_NUM="$(trim "$B17_CTX_HOT_NUM")"
B17_CTX_COLD_NUM="$(trim "$B17_CTX_COLD_NUM")"

check "every colour code burn_ctx_color emits has a name this test can look for" \
  "$(trim "$B17_CTX_UNMAPPED")" ""

# --- the trend scale -------------------------------------------------------

B17_TREND_BODY="$(b17_fn_body burn_trend_color)"
check "burn_trend_color's body is readable (the trend oracle is not empty)" \
  "$([ -n "$B17_TREND_BODY" ] && echo yes || echo no)" "yes"

B17_DEAD="$(printf '%s\n' "$B17_TREND_BODY" | sed -nE 's/.*abs <= ([0-9]+).*/\1/p' | head -1)"
B17_DEAD_CODE="$(printf '%s\n' "$B17_TREND_BODY" \
  | sed -nE 's/.*abs <= [0-9]+.*38;5;([0-9]+)m.*/\1/p' | head -1)"
printf '%s\n' "$B17_TREND_BODY" \
  | sed -nE 's/.*trend >=? ([0-9]+).*38;5;([0-9]+)m.*/\1 \2/p' > "$TMP/trend-ahead"
B17_BEHIND_CODE="$(printf '%s\n' "$B17_TREND_BODY" | grep -vE 'trend (>=|>|<)|abs <=' \
  | sed -nE 's/.*38;5;([0-9]+)m.*/\1/p' | head -1)"
B17_DEAD_NAME="$(b17_colour_name "$B17_DEAD_CODE")"
B17_BEHIND_NAME="$(b17_colour_name "$B17_BEHIND_CODE")"

check "the trend derivation found the dead band (${B17_DEAD:-none}) and its colour (code ${B17_DEAD_CODE:-none})" \
  "$([ -n "$B17_DEAD" ] && [ -n "$B17_DEAD_NAME" ] && echo yes || echo no)" "yes"
check "the trend derivation found all three bands above the dead band" \
  "$(wc -l < "$TMP/trend-ahead" | tr -d ' ')" "3"
check "the trend derivation found the behind-the-line colour (code ${B17_BEHIND_CODE:-none})" \
  "$([ -n "$B17_BEHIND_NAME" ] && echo yes || echo no)" "yes"

# The prose is made to claim WARM colours above the dead band. That claim is
# only true while every band up there really is warm, so it is pinned to the
# source rather than taken on trust: a future band in grey or blue fails here
# by code and sends someone back to the paragraph.
B17_COLD_AHEAD=""
while read -r _trend _code; do
  [ -n "$_code" ] || continue
  case "$(b17_colour_name "$_code")" in
    red|orange|yellow) ;;
    *) B17_COLD_AHEAD="$B17_COLD_AHEAD $_code" ;;
  esac
done < "$TMP/trend-ahead"
check "every trend band above the dead band really is a warm colour" \
  "$(trim "$B17_COLD_AHEAD")" ""

# --- the diffstat pair -----------------------------------------------------

B17_DIFF_BODY="$(b17_fn_body burn_diff_color)"
B17_ADD_CODE="$(printf '%s\n' "$B17_DIFF_BODY" \
  | sed -nE 's/^[[:space:]]*add\).*38;5;([0-9]+)m.*/\1/p' | head -1)"
B17_DEL_CODE="$(printf '%s\n' "$B17_DIFF_BODY" \
  | sed -nE 's/^[[:space:]]*del\).*38;5;([0-9]+)m.*/\1/p' | head -1)"
B17_ADD_NAME="$(b17_colour_name "$B17_ADD_CODE")"
B17_DEL_NAME="$(b17_colour_name "$B17_DEL_CODE")"
B17_DIFF_UNMAPPED=""
[ -n "$B17_ADD_NAME" ] || B17_DIFF_UNMAPPED="$B17_DIFF_UNMAPPED add=${B17_ADD_CODE:-none}"
[ -n "$B17_DEL_NAME" ] || B17_DIFF_UNMAPPED="$B17_DIFF_UNMAPPED del=${B17_DEL_CODE:-none}"
check "burn_diff_color's two arms are readable and named (add=$B17_ADD_NAME del=$B17_DEL_NAME)" \
  "$(trim "$B17_DIFF_UNMAPPED")" ""

# ---------------------------------------------------------------------------
# 18. The Context bullet: colour by occupancy alone, `level` still idle-aware
# ---------------------------------------------------------------------------

B17_CTX_B="$(b17_item "$WTE" '^- [*][*]Context[*][*]')"
check "the Context bullet is identifiable" \
  "$([ -n "$B17_CTX_B" ] && echo yes || echo no)" "yes"

# Half one: the colour claim. Scoped to the SENTENCES that make one, which is
# what lets the bullet go on to say — correctly — that the published `level`
# is still the idle-aware tier.
B17_CTX_COLOUR_CLAIM="$(b17_claims "$B17_CTX_B" 'colou?r')"
check "the Context bullet still makes a colour claim (scoping oracle is not empty)" \
  "$([ -n "$B17_CTX_COLOUR_CLAIM" ] && echo yes || echo no)" "yes"
check "the Context bullet's colour claim no longer names idle time" \
  "$(has_re '(^|[^A-Za-z])idle' "$B17_CTX_COLOUR_CLAIM")" "no"
check "the Context bullet's colour claim names occupancy as what drives it" \
  "$(has_re '(^|[^A-Za-z])occupancy' "$B17_CTX_COLOUR_CLAIM")" "yes"

# The bands themselves, as sequences against the derived scale.
B17_CTX_COL_SEQ="$(b17_ordered "$B17_CTX_B" "$TMP/ctx-colours")"
B17_CTX_NUM_SEQ="$(b17_ordered "$B17_CTX_B" "$TMP/ctx-thresh")"
B17_CTX_COL_DIR=cold-to-hot
B17_CTX_NUM_DIR=cold-to-hot
if [ "$B17_CTX_COL_SEQ" = "$B17_CTX_HOT_COL" ]; then
  B17_CTX_COL_SEQ="$B17_CTX_COLD_COL"; B17_CTX_COL_DIR=hot-to-cold
fi
if [ "$B17_CTX_NUM_SEQ" = "$B17_CTX_HOT_NUM" ]; then
  B17_CTX_NUM_SEQ="$B17_CTX_COLD_NUM"; B17_CTX_NUM_DIR=hot-to-cold
fi

check "the Context bullet names every colour burn_ctx_color emits, in the scale's order" \
  "$B17_CTX_COL_SEQ" "$B17_CTX_COLD_COL"
check "the Context bullet names every threshold burn_ctx_color has, in the same order" \
  "$B17_CTX_NUM_SEQ" "$B17_CTX_COLD_NUM"
check "the bullet's colours and its thresholds run the same way (each band with its own colour)" \
  "$B17_CTX_COL_DIR" "$B17_CTX_NUM_DIR"

# Half two: the idle-aware tier survives as the published `level`, and the
# bullet is where a reader of that JSON is told so.
check "the Context bullet names the file the idle-aware tier survives in" \
  "$(has_fixed '.ctx-status.json' "$B17_CTX_B")" "yes"
B17_CTX_LEVEL_CLAIM="$(b17_claims "$B17_CTX_B" '(^|[^A-Za-z])level([^A-Za-z]|$)')"
check "the Context bullet names that surviving field as level" \
  "$([ -n "$B17_CTX_LEVEL_CLAIM" ] && echo yes || echo no)" "yes"
check "and still describes level as the idle-aware / staleness tier" \
  "$(has_re '(^|[^A-Za-z])(idle|stale)' "$B17_CTX_LEVEL_CLAIM")" "yes"

# The contract's edge case, from the other side: "idle" keeps its non-colour
# home in the file. A blanket "the README no longer says idle time" would have
# forced the implementer to delete this, which is true documentation. Read
# flattened, because the phrase falls across a line break where it is written.
B17_JSON_P="$(paragraph_in "$COMMANDS" '.ctx-status.json')"
check "the .ctx-status.json paragraph is identifiable (scoping oracle is not empty)" \
  "$([ -n "$B17_JSON_P" ] && echo yes || echo no)" "yes"
check "the README keeps documenting the idle fields .ctx-status.json publishes" \
  "$(has_re 'idle[[:space:]]+seconds' "$(one_line "$B17_JSON_P")")" "yes"
check "and keeps the staleness level among them" \
  "$(has_re 'staleness[[:space:]]+level' "$(one_line "$B17_JSON_P")")" "yes"

# ---------------------------------------------------------------------------
# 19. "Reading the burnrate figures" gains what each colour means
# ---------------------------------------------------------------------------

FIGURES="$(b17_subsection '### Reading the burnrate figures')"
check "the 'Reading the burnrate figures' section survives and is identifiable" \
  "$([ -n "$FIGURES" ] && echo yes || echo no)" "yes"
check "the figures section says what the colours mean at all" \
  "$(has_re 'colou?r' "$FIGURES")" "yes"

check "the figures section names burn_trend_color's dead-band magnitude ($B17_DEAD)" \
  "$(has_re "$(b17_num "$B17_DEAD")" "$FIGURES")" "yes"
check "the figures section pairs that dead band with the colour it takes ($B17_DEAD_NAME)" \
  "$(b17_near "$FIGURES" "$(b17_word "$B17_DEAD_NAME")" "$(b17_num "$B17_DEAD")" 80)" "yes"
check "the figures section says the dead band reads as on track" \
  "$(has_re 'on[- ]track' "$FIGURES")" "yes"
check "the figures section calls the bands above it warm" \
  "$(b17_near "$FIGURES" '(^|[^A-Za-z])warm' 'ahead|above' 80)" "yes"

check "the figures section names the colour for running behind the line ($B17_BEHIND_NAME)" \
  "$(has_re "$(b17_word "$B17_BEHIND_NAME")" "$FIGURES")" "yes"
check "the figures section ties that colour to being behind the line" \
  "$(b17_near "$FIGURES" "$(b17_word "$B17_BEHIND_NAME")" 'behind|below' 80)" "yes"
check "the figures section says the allowance going unused there is not a hazard" \
  "$(b17_near "$FIGURES" "$(b17_word "$B17_BEHIND_NAME")" 'hazard|unused|nothing to act on' 140)" "yes"

check "the figures section explains the +added/-removed pair" \
  "$(has_re '[+]added/-removed' "$FIGURES")" "yes"
check "the figures section names the diffstat convention it takes" \
  "$(has_re '(^|[^A-Za-z])diffstat' "$FIGURES")" "yes"
check "the figures section gives added burn_diff_color's colour for it ($B17_ADD_NAME)" \
  "$(b17_near "$FIGURES" '(^|[^A-Za-z])added' "$(b17_word "$B17_ADD_NAME")" 60)" "yes"
check "the figures section gives removed burn_diff_color's colour for it ($B17_DEL_NAME)" \
  "$(b17_near "$FIGURES" '(^|[^A-Za-z])removed' "$(b17_word "$B17_DEL_NAME")" 60)" "yes"

# plan 003 constraint 2: the upstream's on-track ✓ glyph is deliberately NOT
# adopted — the dead-band colour is what replaced it. Section 9 already fails
# any new non-ASCII in $BODY; this names the one glyph the new prose about an
# on-track trend is most likely to reach for.
check "the figures section does not adopt the upstream's on-track glyph" \
  "$(has_fixed '✓' "$FIGURES")" "no"

# ---------------------------------------------------------------------------
# 20. The attribution says which half of the ctx meter is whose
# ---------------------------------------------------------------------------

check "the attribution no longer claims the whole context meter in place of the upstream's" \
  "$(has_re '(context|ctx) meter in place of the upstream' "$ATTRIB")" "no"
check "the attribution says the ctx colour bands are the upstream's" \
  "$(b17_near "$ATTRIB" '(^|[^A-Za-z])(bands?|tiers?)([^A-Za-z]|$)' '(^|[^A-Za-z])upstream' 100)" "yes"
check "the attribution keeps the ctx numerator on this plugin's side" \
  "$(has_re '(^|[^A-Za-z])numerator' "$ATTRIB")" "yes"
check "the attribution keeps the non-saturating division on this plugin's side" \
  "$(has_re 'saturat' "$ATTRIB")" "yes"
check "and attributes those two to this plugin rather than to the upstream" \
  "$(has_re "this plugin|our own|(^|[^A-Za-z])ours([^A-Za-z]|$)" \
     "$(b17_claims "$ATTRIB" 'numerator')")" "yes"

# The contract's edge case: only the ctx BANDS may carry a matching claim. A
# sentence that says this port matches the upstream without naming them is the
# general claim the paragraph must not be rewritten into.
check "no sentence claims the port matches the upstream generally" \
  "$(one_line "$(b17_claims "$ATTRIB" 'match|identical|same as the upstream' \
     | grep -viE 'band|tier|ctx|context|colou?r')")" ""

B17_DIVERGE_CLAIM="$(b17_claims "$ATTRIB" 'differs|divergen|deliberate')"
check "the attribution still lists the port's deliberate divergences" \
  "$([ -n "$B17_DIVERGE_CLAIM" ] && echo yes || echo no)" "yes"
check "and the 256-colour divergence stays in that same sentence" \
  "$(has_re '256.colou?r' "$B17_DIVERGE_CLAIM")" "yes"

# ---------------------------------------------------------------------------
# 21. The invariant across all three passages: a description, not a changelog
# ---------------------------------------------------------------------------
# "The file keeps describing the render as it IS after this plan lands, never
# as a changelog of what moved." Mechanically: none of the three rewritten
# passages may reach for the tense that only makes sense to a reader who saw
# the old render. Emoji are covered file-wide by section 9, which reads $BODY
# and therefore covers every word this block adds.

B17_CHANGELOG='(^|[^A-Za-z])(used to|formerly|previously|no longer|instead of what|has changed|changed from)'
check "the Context bullet describes the render as it is, not as a changelog" \
  "$(has_re "$B17_CHANGELOG" "$B17_CTX_B")" "no"
check "the figures section describes the render as it is, not as a changelog" \
  "$(has_re "$B17_CHANGELOG" "$FIGURES")" "no"
check "the attribution describes the port as it is, not as a changelog" \
  "$(has_re "$B17_CHANGELOG" "$ATTRIB")" "no"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
