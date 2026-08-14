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
#   - THE TREND SCALE (reworked by B18). burn_trend_color has no dead band and
#     no floor colour since B16: its body is three over-pace bands and nothing
#     else. The derivation reads those three off the comparison lines, sorts
#     them ascending so the file IS the warming order, and derives the two
#     retired tiers (green 40, grey 245) as an ABSENCE — codes the body no
#     longer emits. The prose is then asked for the word "warm" against ▲, the
#     three colour words in warming order, the hottest one tied to the gap
#     growing, an explicit "no colour" on the on-track/behind side, and no
#     mention of either retired tier. The thresholds themselves are
#     deliberately NOT required in the prose: a number the README never names
#     cannot drift, and demanding it would be this file inventing a clause.
#   - THE DIFFSTAT PAIR. burn_diff_color's two arms give the colours "add" and
#     "del" take, and the prose has to pair each with the right half of
#     `+added/-removed`.
#
# Three guards stop those derivations from passing vacuously. Each parse
# asserts HOW MANY arms it found, so an empty parse (function renamed, the
# `(( pct >= N ))` shape rewritten) is a red test rather than a green one that
# compares nothing. Every colour code the source emits must resolve to a name
# this file can look for, so a recoloured band fails here by code rather than
# dropping silently out of the comparison. And every trend band must really be
# a warm colour, since "warm colours" is the claim the prose is made to carry.
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
# --- B06 line2-docs (plan 001-statusline-glance-uplift) ---------------------
# B06 brings this README and plugin.json into agreement with B05's new line 2
# and its new configuration surface. Its contract is NOT a docblock in the
# README — scripts/readme.test.sh forbids a surviving `<!-- Contract:` block in
# a shipped plugin README (section 8), so it lives in .local/ instead. The
# sections it owns: `## What to expect`, `### Reading the burnrate figures`,
# `### Match the pacing to the hours you actually work`, the env-var table,
# `## Attribution`, and plugin.json's `version` and `description`.
#
# What this wave changed in THIS file, and why:
#
#   - THE TWO HARDCODED KNOBS MOVED. Sections 2 used to pin
#     CLAM_STATUSLINE_DAY_START default `2` and CLAM_STATUSLINE_SLEEP_HOURS
#     default `6`, and to UNION both names into the derivation oracle by hand.
#     B05 replaces that surface with three working-week knobs —
#     CLAM_STATUSLINE_WORK_DAYS (`1-5`), CLAM_STATUSLINE_DAY_START (`8`, same
#     name, changed meaning AND changed default) and CLAM_STATUSLINE_DAY_END
#     (`18`) — and deletes CLAM_STATUSLINE_SLEEP_HOURS outright. The contract's
#     edge case says explicitly that this move happens in the TEST wave, since
#     B06 must not edit a test-family file. The hand-union is GONE with it: it
#     existed only because B07 had not yet wired those names into the code, and
#     B05 reads all three directly, so the derivation can go back to purely
#     following the sources. What stays untouched is the BIDIRECTIONALITY —
#     `comm -23` and `comm -13` both asserted empty. That is the contract's
#     stated invariant (no documented row without a source read, no source read
#     without a row), and dropping either direction is exactly the vacuity that
#     lets a stale row or an undocumented knob ship.
#   - THE RETIRED FIGURES flipped polarity. `%t`, `%/d`, the awake-hours
#     passage, the `+added/-removed` pair and the drifting model rainbow all
#     used to be REQUIRED here; B05 retires every one of them, so the same
#     clauses now assert their absence. The trend keeps its coverage — its
#     meaning, its sign convention and its dead band all stay, in both limit
#     groups, which is the one reading the contract asks the section to teach.
#   - THE EXAMPLE BLOCK stays a real character-for-character check against a
#     live scripts/context.sh render (section 12, skeleton comparison — see the
#     B11 note above for why a skeleton is the only faithful form of "character
#     for character" for a line carrying live digits). B05's render does not
#     exist yet, so this is a genuine red for this wave, and loosening it to a
#     shape check would forfeit exactly the assertion the contract's Outputs
#     clause names.
#   - THE ATTRIBUTED LIBRARY LIST is now DERIVED. It used to be the literal
#     triple burn-math/burn-tick/burn-theme; B05 deletes lib/burn-tick.sh, so
#     the list is read off whichever lib/burn-*.sh files actually carry the
#     upstream MIT header. Gui-Gou, the URL and the MIT notice stay required —
#     the port is still a port even where its model changed.
#   - NEW SECTIONS 24, 25 AND 26 cover the three passages the contract gained
#     after this block's first test wave surfaced them: the plugin README's
#     opening blurb, the lib/burn-tick.sh references in `## Commands` and
#     `## Tests`, and the repo-root README's Plugins-table row. The rule the
#     contract gives for all three is that a passage stating something B05 makes
#     false belongs to this block wherever it sits. Section 25 is DERIVED — every
#     plugin path either section names must exist on disk — rather than pinned to
#     burn-tick by name, so the next deletion needs no edit here. The root row's
#     VERSION cell is deliberately not re-asserted: section 6 already gates that
#     equality and fails when section 23's bump lands without the row moving.
#     Every absence check in the three is paired with a positive one that its
#     target section still exists and still carries the claim the absence is
#     about, because an absence check aimed at nothing passes for free.
#   - NEW SECTIONS 22 AND 23 cover the three clauses nothing else reached: the
#     working-week section rewritten around the three knobs and stating that
#     every figure is computed in machine local time, the UPGRADE NOTE (a
#     changed default AND a changed meaning for a knob users already set is a
#     behaviour change on upgrade), and plugin.json's mandatory version bump
#     plus a description that no longer promises the figures B05 removed.
#
# --- B09 line1-cache-docs (sections 27-31) ----------------------------------
# B09 brings this README into agreement with B07 (the project dir at the head
# of line 1, an OSC 8 file:// hyperlink, the `›` form when the current dir
# differs) and B08 (the segment bundle keyed on session_id, and a one-day sweep
# that bounds the cache dir). Its contract is a file rather than a docblock in
# the README, for the reason section 8 pins: a shipped plugin README may carry
# no surviving `<!-- Contract:` block. The sections it owns: the line-1
# description and the example block under `## What to expect`, `### Caching and
# staleness`, the cache-clutter paragraph under `## Uninstalling`, and the
# `scripts/context.sh` entry under `### Scripts`.
#
# What is DERIVED here, and what each derivation buys:
#
#   - THE SEPARATOR. b09_render_line1() renders line 1 from a payload whose
#     project_dir and current_dir DIFFER, hermetically (a plain temp dir, not a
#     git repo, so no branch, no badge and no background refresher), strips the
#     hyperlink and colour framing, and reads the separator off it as the one
#     non-ASCII run in the result. The README's line-1 prose and its example
#     block are then required to carry THAT character. A separator changed in
#     the renderer fails the prose by character rather than leaving the README
#     quietly describing a form nothing emits. Two guards keep it honest: the
#     derived separator must be flanked by real path text on both sides, and it
#     must be the `›` strip_allowed exempts — otherwise the alphabet check in
#     section 9 would either reject correct prose or hold a hole.
#   - THE HYPERLINK. The same render is asked, unstripped, whether it really
#     emits an `OSC 8 file://` sequence around the path. Only then is the prose
#     required to call the segment clickable. The claim the README makes about
#     the render is pinned to the render, not to this file's memory of it.
#
# Two shapes this file deliberately does NOT reach for:
#
#   1. A whole-line comparison of the example's line 1 against a live render,
#     the way section 12 compares line 2. Line 1's branch, badge files, MODE and
#     State come from a worktree the example is free to invent, so no hermetic
#     fixture can produce it. What IS comparable is the vocabulary the render
#     contributes — the separator — and that is what is compared.
#   2. A file-wide "the README no longer says transcript" check. `ccost.sh
#     session` still takes a transcript path and still documents it, so the
#     absence is scoped to the SENTENCES of the caching section and of the
#     `scripts/context.sh` entry that make a cache claim. Every absence check in
#     these sections is paired with a positive one that its target section still
#     exists and still carries the claim the absence is about — an absence check
#     aimed at a section someone deleted passes for free.
#
# The `## Uninstalling` clause rides on the same sentence scoping. The cache
# paragraph names BOTH cache dirs, and only one of them gains a sweep: ccost's
# cache is untouched by this unit and may legitimately still be described as
# the reader's to delete. So what is asserted is that no sentence naming
# `.statusline-cache` still claims nothing removes anything there, while the
# paragraph goes on naming both directories.
#
# --- B12 subagent-docs (sections 32-35) ------------------------------------
# B12 brings this README and plugin.json into agreement with B10 (the
# `scripts/subagent.sh` agent-panel row renderer) and B11 (a setup skill that
# writes three settings keys instead of one). Its contract is a file rather
# than a docblock in the README, for the reason section 8 pins. The sections it
# owns: a subagent-rows subsection under `## What to expect`, the
# `scripts/subagent.sh` entry under `### Scripts`, the `/statusline:setup` and
# `/statusline:setup remove` entries under `### Skills`, the `## Uninstalling`
# section, and plugin.json's version and description.
#
# Two scoping oracles carry these sections, both of them structural rather than
# textual, so no wording is pinned that the contract does not pin:
#
#   - THE SUBAGENT SUBSECTION is located by MEANING, not by title: the first H3
#     inside `## What to expect` whose heading names subagents or the agent
#     panel. The contract fixes what the subsection must say and not what it is
#     called, so requiring one title would be this file inventing a clause, and
#     hard-coding the title the implementer happens to choose is impossible
#     before they choose it. Its emptiness is checked first, so every content
#     check below is aimed at prose that is really there.
#   - THE SCRIPT ENTRY reuses paragraph_in() against `## Commands`, exactly the
#     way section 30 scopes the `scripts/context.sh` entry. Section 25 already
#     asserts that every `scripts/…` path named in that section exists on disk,
#     so a fabricated entry for a script that does not ship fails there without
#     a second check here.
#
# THE EFFORT-ABSENT CLAUSE is the one the contract singles out, and it is
# asserted at SENTENCE scope rather than over the subsection. A subsection-wide
# proximity check between "effort" and "inherit" would pass on a subsection that
# names effort in the row inventory and inheritance in an unrelated sentence,
# which is precisely the pair of statements that leaves the reader thinking a
# blank effort is a bug. What is required is one sentence carrying all three: the
# effort field, the case where it is not shown, and inheritance as the reason.
#
# The `## Commands` and `## Uninstalling` clauses are key-set checks. All three
# keys are required by name in the setup entry, the remove entry and the
# uninstall section, each paired with a non-vacuity check that the entry still
# describes the operation the keys belong to — an entry deleted outright would
# otherwise satisfy nothing and fail nothing. `statusLine` is not a substring of
# `subagentStatusLine` (the capital S differs), so the three literal checks are
# genuinely independent.
#
# NOT re-asserted here, deliberately: the root README's Plugins-table VERSION
# cell. Section 6 already holds it equal to plugin.json and therefore goes red
# the moment section 35's bump lands without the row moving — the same division
# of labour section 26 states for the same row. What section 35 adds is the
# floor: strictly above the version this block starts from, which section 23's
# older baseline no longer has teeth for.
#
# --- B15 setup-schedule-docs (section 36) -----------------------------------
# B15 brings the `## Commands` skill entries, the "Turn the statusline off
# without uninstalling" section and both version surfaces into agreement with
# B14, which adds a schedule-disclosure step to the setup skill. Its contract is
# a file rather than a docblock in the README, for the reason section 8 pins: a
# shipped plugin README may carry no surviving `<!-- Contract:` block. The
# passages it owns: the `/statusline:setup` entry, the `/statusline:setup
# remove` entry, `### Turn the statusline off without uninstalling`,
# plugin.json's version, and the root README row's version CELL.
#
# What is derived, and what each derivation buys:
#
#   - THE THREE SCHEDULE KNOB NAMES are read out of the env-var table's own row
#     set ($TMP/documented, section 2) rather than spelled out here. Section 2
#     already holds that set equal in BOTH directions to the names the plugin's
#     scripts really read, so a knob renamed in the code renames it here too,
#     and the setup entry is then required to name whatever the code and the
#     table agree on. The extraction asserts it found exactly three, so a
#     renamed or dropped knob fails by count instead of silently shrinking the
#     list of names the prose has to carry.
#   - THE FROZEN ROOT ROW. The contract's invariant is that the root README
#     row's WORDING is byte-identical across this block while its VERSION cell
#     moves. Both halves are asserted separately: the version cell by exact
#     equality against 0.10.0, and the rest of the row by masking field 3 out
#     of the live row (awk rebuilds every other byte unchanged) and comparing
#     the result against the literal frozen row. A wording edit fails by diff;
#     a version bump does not. Section 26's semantic checks on the description
#     cell stay as they are — this adds the byte-level guard they cannot give,
#     and weakening either would leave the invariant unpinned.
#
# THE VERSION IS PINNED EXACTLY here, not as a floor. Sections 6, 23 and 35 all
# take floors, for the reason those sections state: an exact pin turns a later
# unrelated bump into a failure. The contract for this block names 0.10.0 as
# the version, and the root row's cell has to carry that same string, so the
# equality is the clause — the two floors above stay untouched and keep doing
# their own job.
#
# SCOPING. The two skill entries are scoped with b15_entry() rather than
# paragraph_in(): the schedule step is new prose, and an implementer may
# legitimately write it as a second paragraph of the same entry, which
# paragraph_in() would cut off mid-clause. b15_entry() runs from the entry's
# `**`/statusline:setup`**` line to the next entry or heading, so a
# multi-paragraph entry is read whole. Every content check below is paired with
# a non-vacuity check that its target passage is identifiable and still
# describes the operation the schedule clause hangs off — section 34 already
# holds the three statusline keys in both entries, so an entry rewritten around
# the schedule alone fails there.
#
# NOT re-asserted here, deliberately: the env table's three schedule rows and
# their defaults (section 2), and the working-week section (section 22). The
# contract lists both as invariants, and both already have checks that go red
# if they move; a second copy would be noise. What IS added is one guard that
# the derivation feeding this section is not empty.
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
# stripped. B06 drops the hand-union the old surface needed (see header): B05
# reads all three working-week knobs directly, so the oracle follows the code
# with nothing led by hand.
for f in "$PLUGIN_DIR"/scripts/*.sh "$PLUGIN_DIR"/lib/*.sh; do
  case "$f" in *.test.sh) continue ;; esac
  [ -f "$f" ] || continue
  sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#[[:space:]].*$//' "$f"
done | grep -oE '\$\{?(CLAUDE|CCOST|CLAM)_[A-Z0-9_]+' | sed -E 's/^\$\{?//' > "$TMP/derived.src"
sort -u "$TMP/derived.src" > "$TMP/derived"

check "env-var table is present (backticked rows found)" \
  "$([ -s "$TMP/documented" ] && echo yes || echo no)" "yes"
# Guards the derivation itself: if the source scan finds nothing (wrong
# paths, prefixes changed), both comparisons below would run against an empty
# oracle and the "every table row names a var some script reads" direction
# would report the WHOLE table as undocumented reads — loud, but for the wrong
# reason. This names the real cause first.
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

# The three working-week knobs B05 ships, each with the default the renderer's
# contract gives it. DAY_START keeps its name and changes BOTH its meaning and
# its default (2 -> 8), which is why the default is pinned by value here and
# why section 22 additionally requires an upgrade note for it.
check "CLAM_STATUSLINE_WORK_DAYS is documented with default 1-5" \
  "$(table_default_for CLAM_STATUSLINE_WORK_DAYS)" "1-5"
check "CLAM_STATUSLINE_DAY_START is documented with default 8" \
  "$(table_default_for CLAM_STATUSLINE_DAY_START)" "8"
check "CLAM_STATUSLINE_DAY_END is documented with default 18" \
  "$(table_default_for CLAM_STATUSLINE_DAY_END)" "18"

# CLAM_STATUSLINE_SLEEP_HOURS is deleted outright, not renamed. The table is
# the documented interface, so what is asserted is that it has no ROW — prose
# elsewhere may still legitimately tell an upgrading reader the knob is gone.
check "CLAM_STATUSLINE_SLEEP_HOURS has no row in the env-var table any more" \
  "$(grep -c '^CLAM_STATUSLINE_SLEEP_HOURS$' "$TMP/documented")" "0"

# The bare SL_* spellings are internal locals, never the documented interface.
check "the bare SL_DAY_START / SL_DAY_END / SL_WORK_DAYS spellings are not documented" \
  "$(grep -cE '(^|[^A-Za-z0-9_])SL_(DAY_START|DAY_END|WORK_DAYS|SLEEP_HOURS)' <<<"$BODY")" "0"

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

# The burnrate line's figures are explained in actionable terms. B05's line 2
# is four groups — model, context, 5-hour, weekly — and the two limit groups
# carry the SAME three figures (used%, trend, countdown), which is the whole
# point of the rewrite: one reading, learned once, applied twice.
check "'What to expect' describes the model group" \
  "$(has_re '(^|[^a-z])model' "$WTE")" "yes"
check "'What to expect' describes the context group" \
  "$(has_re '(^|[^a-z])(context|ctx)' "$WTE")" "yes"
check "'What to expect' describes the 5-hour-limit group" \
  "$(has_re '5.hour' "$WTE")" "yes"
check "'What to expect' describes the weekly-limit group" \
  "$(has_re 'weekly' "$WTE")" "yes"
check "'What to expect' explains the trend arrow both limit groups carry" \
  "$(has_re 'trend' "$WTE")" "yes"
check "'What to expect' explains the reset countdown both limit groups carry" \
  "$(has_re 'countdown' "$WTE")" "yes"

# The retired figures, from the other side. Each of these WAS required here
# before this wave; B05 removes the figure, so describing it is now the defect.
check "'What to expect' no longer explains the retired today's-share figure (%t)" \
  "$(has_fixed '%t' "$WTE")" "no"
check "'What to expect' no longer explains the retired sustainable-pace figure (%/d)" \
  "$(has_fixed '%/d' "$WTE")" "no"
check "'What to expect' no longer claims the pacing counts awake hours" \
  "$(has_re 'awake' "$WTE")" "no"
check "'What to expect' no longer describes the retired +added/-removed pair" \
  "$(has_re '[+]added/-removed' "$WTE")" "no"
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
# Section 23 carries B06's own, stricter clause: the version must be strictly
# ABOVE the one this plan started from. This floor stays as the historical one
# so an unrelated later bump never fails here.
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

# The non-ASCII characters this README may legitimately hold: the six
# ambiguous-width symbols the render still emits — which the contract requires
# to STAY — plus ordinary typography. Anything else non-ASCII is an emoji.
# LC_ALL=C so the byte range means bytes rather than whatever the ambient
# locale collates into it.
# The sixth is B09's `›`, the separator B07 puts between the project dir and
# the current dir on line 1. It is exempt for exactly the reason the other five
# are — the render emits it, so the prose has to be able to name it — and the
# exemption is guarded twice in section 28: the prose must really carry it, and
# the character the RENDERER emits must really be this one.
strip_allowed() { # text
  local t="$1"
  t="${t//│/}"; t="${t//▲/}"; t="${t//▼/}"; t="${t//↑/}"; t="${t//↓/}"; t="${t//›/}"
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
# B05's group ORDER is model · context · 5-hour · weekly, and each label is
# read off the live render at the position that group occupies, so a reordered
# or relabelled group fails the example by name rather than sliding through
# the skeleton's digit normalisation (`9h` and `5h` both reduce to `Nh`).
CTX_LABEL="$(group_label "$B11_LINE2" 2)"
FIVE_LABEL="$(group_label "$B11_LINE2" 3)"
WK_LABEL="$(group_label "$B11_LINE2" 4)"
check "the render's three meter labels are readable (oracle is not empty)" \
  "$([ -n "$WK_LABEL" ] && [ -n "$CTX_LABEL" ] && [ -n "$FIVE_LABEL" ] && echo yes || echo no)" "yes"
check "the example's context group leads with the label the render emits" \
  "$(group_label "$EX_L2" 2)" "$CTX_LABEL"
check "the example's 5-hour group leads with the label the render emits" \
  "$(group_label "$EX_L2" 3)" "$FIVE_LABEL"
check "the example's weekly group leads with the label the render emits" \
  "$(group_label "$EX_L2" 4)" "$WK_LABEL"

# The +added/-removed pair is retired with the rest of the diffstat segment, in
# the render and therefore in the example. Both halves are asserted so a pair
# that survived in one place alone still fails.
check "the render no longer prints a +added/-removed pair" \
  "$(has_re '\+[0-9]+/-[0-9]+' "$B11_LINE2")" "no"
check "the example carries no +added/-removed pair either" \
  "$(has_re '\+[0-9]+/-[0-9]+' "$EX_L2")" "no"

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
# The drifting rainbow goes the way the mascots went before it: B05 retires
# burn_rainbow and burn_model_style, so a bullet still promising a colour that
# drifts between renders describes a render that no longer exists.
check "the Model bullet no longer promises a drifting rainbow" \
  "$(has_re 'rainbow|drifting' "$MODEL_B")" "no"

# The two limit groups carry the SAME three figures, which is the reading the
# rewrite exists to teach. Each bullet is asked for its own trend and its own
# countdown, so a bullet that describes only one of the pair fails by name.
check "the 5-hour bullet names the trend it now carries" \
  "$(has_re 'trend' "$FIVE_B")" "yes"
check "the 5-hour bullet names its reset countdown" \
  "$(has_re 'countdown|reset' "$FIVE_B")" "yes"
check "the Weekly bullet names the trend it carries" \
  "$(has_re 'trend' "$WEEK_B")" "yes"
check "the Weekly bullet names its reset countdown" \
  "$(has_re 'countdown|reset' "$WEEK_B")" "yes"

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

# Scoped on burn-math rather than burn-theme (B12 retarget): paragraph_in takes
# the FIRST paragraph naming its needle, and B10's `scripts/subagent.sh` entry
# legitimately names lib/burn-theme.sh too — it sources the same theme so a
# subagent row and line 2 cannot disagree about a model's colour. With the old
# needle this oracle silently moved to that entry and the three checks below
# then failed against a correct README. burn-math is named by the libraries
# paragraph alone, and section 25's loop still asserts that this paragraph names
# EVERY surviving lib/burn-*.sh, so the scoping cannot drift unnoticed.
LIBS_P="$(paragraph_in "$COMMANDS" 'lib/burn-math.sh')"
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
# Both halves of that claim, with the LIST now DERIVED rather than the literal
# triple it used to be: B05 deletes lib/burn-tick.sh with the interpolator, so
# the libraries the prose must name are whichever lib/burn-*.sh files actually
# carry the upstream MIT header. A file deleted stops being required here; a
# file that keeps the notice stays required, in both directions.
: > "$TMP/notice-libs"
for _f in "$PLUGIN_DIR"/lib/burn-*.sh; do
  case "$_f" in *.test.sh) continue ;; esac
  [ -f "$_f" ] || continue
  [ "$(lib_upstream_author "$_f")" = "$UPSTREAM_AUTHOR" ] || continue
  basename "$_f" >> "$TMP/notice-libs"
done
# Non-vacuity: an empty list would make the loop below assert nothing at all.
check "at least one surviving lib/burn-*.sh carries the upstream notice (oracle is not empty)" \
  "$([ -s "$TMP/notice-libs" ] && echo yes || echo no)" "yes"
while read -r _lib; do
  [ -n "$_lib" ] || continue
  check "the attribution names lib/$_lib among the libraries carrying the notice" \
    "$(has_fixed "lib/$_lib" "$ATTRIB")" "yes"
done < "$TMP/notice-libs"
# The other direction: a library the attribution names must still exist. The
# deleted interpolator is exactly the stale credit this catches.
grep -oE 'lib/burn-[a-z-]+\.sh' <<<"$ATTRIB" | sort -u > "$TMP/attrib-libs"
while read -r _named; do
  [ -n "$_named" ] || continue
  check "the attribution's '$_named' still exists in the plugin" \
    "$([ -f "$PLUGIN_DIR/$_named" ] && echo yes || echo no)" "yes"
done < "$TMP/attrib-libs"

# The two upstream ideas B05 retires: the awake-hours pacing model and the
# sub-tick interpolator. The credit for them goes with them; the credit to
# Gui-Gou, the URL and the MIT notice above do not.
check "the attribution no longer credits the retired awake-hours pacing model" \
  "$(has_re 'awake' "$ATTRIB")" "no"
check "the attribution no longer credits the retired sub-tick interpolator" \
  "$(has_re 'interpolat' "$ATTRIB")" "no"
check "the attribution still names Gui-Gou as the upstream author" \
  "$(has_fixed "$UPSTREAM_AUTHOR" "$ATTRIB")" "yes"

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

# --- the trend scale (reworked by B18 for the dead-band-free body) ---------
# B16 leaves burn_trend_color with three over-pace bands and NOTHING else: the
# `abs <= N` dead band and the behind-the-line floor colour B14 had are both
# gone, and the calm side falls off the end of the function emitting the empty
# string. So the derivation reads the bands off the comparison lines exactly as
# the ctx one does, and everything the old scale had is pinned by ABSENCE —
# the README's claims stay checked against the delivered body rather than
# against constants restated here.

B17_TREND_BODY="$(b17_fn_body burn_trend_color)"
check "burn_trend_color's body is readable (the trend oracle is not empty)" \
  "$([ -n "$B17_TREND_BODY" ] && echo yes || echo no)" "yes"

# Each band is one source line carrying its threshold and its colour:
#   if (( trend >= 6 )); then printf '\033[38;5;208m'; return 0; fi
# Both `>` and `>=` are read, because the top band is strict (> 10) while the
# two below it are inclusive. Sorted ascending, so the file is the scale in
# WARMING order — smallest coloured magnitude first, which is the order the
# prose walks it in as the gap grows.
printf '%s\n' "$B17_TREND_BODY" \
  | sed -nE 's/.*trend (>|>=) ([0-9]+).*38;5;([0-9]+)m.*/\2 \3/p' \
  | sort -n > "$TMP/trend-ahead"

# What the old scale had, read the same way so its absence is a derived fact:
# a dead band (any `abs <= N` arm) and a floor colour (any colour-emitting arm
# with no trend comparison on it — the tier every value below the lowest
# threshold used to fall through to).
B18_TREND_DEAD="$(printf '%s\n' "$B17_TREND_BODY" \
  | sed -nE 's/.*abs <= ([0-9]+).*/\1/p' | head -1)"
B18_TREND_FLOOR="$(printf '%s\n' "$B17_TREND_BODY" | grep -vE 'trend (>=|>|<)' \
  | sed -nE 's/.*38;5;([0-9]+)m.*/\1/p' | head -1)"

check "the trend derivation found all three over-pace bands" \
  "$(wc -l < "$TMP/trend-ahead" | tr -d ' ')" "3"
check "burn_trend_color has no dead band left in its body (found ${B18_TREND_DEAD:-none})" \
  "$B18_TREND_DEAD" ""
check "burn_trend_color has no floor colour: the calm side emits nothing (found code ${B18_TREND_FLOOR:-none})" \
  "$B18_TREND_FLOOR" ""

# The prose is made to claim WARM colours for every ▲. That claim is only true
# while every band really is warm, so it is pinned to the source rather than
# taken on trust: a future band in grey or blue fails here by code and sends
# someone back to the paragraph. The same walk builds the warming sequence and
# the lookup file the figures-section checks read.
B17_COLD_AHEAD=""
B18_TREND_UNMAPPED=""
B18_TREND_WARMING=""
: > "$TMP/trend-colours"
while read -r _trend _code; do
  [ -n "$_code" ] || continue
  _name="$(b17_colour_name "$_code")"
  [ -n "$_name" ] || B18_TREND_UNMAPPED="$B18_TREND_UNMAPPED $_code"
  case "$_name" in
    red|orange|yellow) ;;
    *) B17_COLD_AHEAD="$B17_COLD_AHEAD $_code" ;;
  esac
  B18_TREND_WARMING="$B18_TREND_WARMING $_name"
  printf '%s\n' "$_name" >> "$TMP/trend-colours"
done < "$TMP/trend-ahead"
B18_TREND_WARMING="$(trim "$B18_TREND_WARMING")"
B18_TREND_TOP_NAME="$(b17_colour_name "$(awk 'END { print $2 }' "$TMP/trend-ahead")")"

check "every colour code burn_trend_color emits has a name this test can look for" \
  "$(trim "$B18_TREND_UNMAPPED")" ""
check "every trend band really is a warm colour" \
  "$(trim "$B17_COLD_AHEAD")" ""

# The two tiers B14 had and B16 retired, as codes: no arm of the function may
# emit green 40 or grey 245 any more. This is what makes the prose checks below
# able to say "this colour word is gone from the paragraph" and mean it.
: > "$TMP/trend-absent"
for _code in 40 245; do
  if ! printf '%s\n' "$B17_TREND_BODY" | grep -qF "38;5;${_code}m"; then
    b17_colour_name "$_code" >> "$TMP/trend-absent"; printf '\n' >> "$TMP/trend-absent"
  fi
done
check "burn_trend_color emits neither the retired green nor the retired grey" \
  "$(wc -l < "$TMP/trend-absent" | tr -d ' ')" "2"

# --- the diffstat pair, retired --------------------------------------------
# B05 retires burn_diff_color along with the +added/-removed segment it
# coloured, so the derivation that used to feed section 19's diffstat prose is
# gone with it. What replaces it is the reverse assertion: no prose may still
# document a colour scale the source no longer has.

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

# B18: the reading the paragraph now teaches. Every ▲ carries a warm colour,
# and it warms with the gap — asserted as the SEQUENCE of colour words against
# the scale derived above, so a paragraph that names the three out of order,
# or names one the function no longer emits, fails by name.
check "the figures section says any ▲ carries a warm colour" \
  "$(b17_near "$FIGURES" '(^|[^A-Za-z])warm' '▲|ahead|above' 120)" "yes"
check "the figures section walks the trend's colours in warming order ($B18_TREND_WARMING)" \
  "$(b17_ordered "$FIGURES" "$TMP/trend-colours")" "$B18_TREND_WARMING"
check "the figures section ties the hottest trend colour ($B18_TREND_TOP_NAME) to the gap growing" \
  "$(b17_near "$FIGURES" "$(b17_word "$B18_TREND_TOP_NAME")" \
     '(gap|further|wider|widen|grows|growing|deeper)' 160)" "yes"

# The other side of the same rule, and the half the old prose got wrong: on the
# line or behind it, nothing is coloured at all. Scoped to the SENTENCES making
# that claim, because the neighbouring prose legitimately keeps explaining what
# ▼ MEANS without saying anything about colour.
B18_CALM_CLAIM="$(b17_claims "$FIGURES" '(▼|(^|[^A-Za-z])behind|on[- ]track|zero)')"
check "the figures section makes a claim about the on-track / behind side (scoping oracle is not empty)" \
  "$([ -n "$B18_CALM_CLAIM" ] && echo yes || echo no)" "yes"
check "and that claim says the calm side carries no colour at all" \
  "$(has_re '(no colou?r|colourless|colorless|uncolou?red|not colou?red|never colou?red|without colou?r)' \
     "$B18_CALM_CLAIM")" "yes"

# The two retired tiers, by name: the function emits neither green nor grey any
# more (pinned above), so the paragraph may not still promise either. The words
# come from the derivation, not from a list typed here.
while read -r _gone; do
  [ -n "$_gone" ] || continue
  check "the figures section no longer promises the retired $_gone trend tier" \
    "$(has_re "$(b17_word "$_gone")" "$FIGURES")" "no"
done < "$TMP/trend-absent"

# B18: the used percentages are deliberately plain (B17 renders both tokens
# with no SGR), and the paragraph has to say so rather than leave a reader to
# infer a missing colour is a bug.
B18_USED_CLAIM="$(b17_claims "$FIGURES" '(used percentages?|percentages?)')"
check "the figures section makes a claim about the used percentages (scoping oracle is not empty)" \
  "$([ -n "$B18_USED_CLAIM" ] && echo yes || echo no)" "yes"
check "and says they carry no colour" \
  "$(has_re '(uncolou?red|colourless|colorless|no colou?r|not colou?red|never colou?red|plain)' \
     "$B18_USED_CLAIM")" "yes"
check "and says that is deliberate rather than an omission" \
  "$(has_re '(deliberate|on purpose|intentional)' "$B18_USED_CLAIM")" "yes"
check "the figures section says a high used figure is information rather than an alarm" \
  "$(b17_near "$FIGURES" '(^|[^A-Za-z])information' '(^|[^A-Za-z])alarm' 160)" "yes"

# The figures this section is REPLACED to stop explaining: %t, %/d, the
# awake-hours passage and the diffstat pair all describe a render B05 no
# longer produces.
check "the figures section no longer explains the retired %t figure" \
  "$(has_fixed '%t' "$FIGURES")" "no"
check "the figures section no longer explains the retired %/d figure" \
  "$(has_fixed '%/d' "$FIGURES")" "no"
check "the figures section no longer carries the awake-hours passage" \
  "$(has_re 'awake' "$FIGURES")" "no"
check "the figures section no longer explains the retired +added/-removed pair" \
  "$(has_re '[+]added/-removed' "$FIGURES")" "no"
check "nor the diffstat convention that pair took" \
  "$(has_re '(^|[^A-Za-z])diffstat' "$FIGURES")" "no"

# What STAYS: the trend's meaning and its sign convention, in the section that
# teaches the one reading both limit groups share.
check "the figures section keeps the trend's ▲ arrow" \
  "$(has_fixed '▲' "$FIGURES")" "yes"
check "the figures section keeps the trend's ▼ arrow" \
  "$(has_fixed '▼' "$FIGURES")" "yes"
check "the figures section keeps the sign convention for ▲ (above/ahead of the line)" \
  "$(b17_near "$FIGURES" '▲' 'above|ahead' 120)" "yes"
check "the figures section keeps the sign convention for ▼ (below/behind the line)" \
  "$(b17_near "$FIGURES" '▼' 'below|behind' 120)" "yes"

# plan 003 constraint 2: the upstream's on-track ✓ glyph is deliberately NOT
# adopted — since B16 the on-track state emits nothing at all, which is what
# stands in for it, and glyph coverage stays unassumable. Section 9 already fails
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

# ===========================================================================
# B06 line2-docs
# ===========================================================================

# ---------------------------------------------------------------------------
# 22. The working-week section, and the upgrade note it has to carry
# ---------------------------------------------------------------------------
# The section keeps its heading and loses its subject: the awake-hours model is
# replaced by a working WEEK. Section 2 already pins the three knobs' names and
# defaults in the table; what is asserted here is that the prose a reader
# actually configures from was rewritten around the same three, that it says
# which clock the arithmetic runs on, and that a user who already set
# CLAM_STATUSLINE_DAY_START is told their setting now means something else.

PACING="$(b17_subsection '### Match the pacing to the hours you actually work')"
check "the working-hours workflow section survives and is identifiable" \
  "$([ -n "$PACING" ] && echo yes || echo no)" "yes"

for _knob in CLAM_STATUSLINE_WORK_DAYS CLAM_STATUSLINE_DAY_START CLAM_STATUSLINE_DAY_END; do
  check "the working-hours section is written around $_knob" \
    "$(has_fixed "$_knob" "$PACING")" "yes"
done
check "the working-hours section no longer configures the deleted CLAM_STATUSLINE_SLEEP_HOURS" \
  "$(has_fixed 'CLAM_STATUSLINE_SLEEP_HOURS' "$PACING")" "no"
check "the working-hours section no longer describes the retired awake-hours model" \
  "$(has_re 'awake|sleep' "$PACING")" "no"

# "Every figure is computed in machine local time" — the contract's own words,
# and the limitation the engineer's no-timezone-knob decision documents rather
# than works around.
check "the working-hours section states the arithmetic runs in machine local time" \
  "$(b17_near "$PACING" '(^|[^A-Za-z])local' '(^|[^A-Za-z])(time|timezone|time zone|clock|machine)' 60)" "yes"

# The upgrade note. Scoped to the SENTENCES making an upgrade claim, so the
# surrounding configuration prose — which legitimately describes the knob as it
# is now — cannot satisfy the clause by accident.
UPGRADE="$(b17_claims "$PACING" 'upgrad|chang|used to|previously')"
check "the working-hours section carries an upgrade note at all" \
  "$([ -n "$UPGRADE" ] && echo yes || echo no)" "yes"
check "the upgrade note names the knob whose behaviour changed" \
  "$(has_fixed 'CLAM_STATUSLINE_DAY_START' "$UPGRADE")" "yes"
check "the upgrade note names the old default (2)" \
  "$(has_re "$(b17_num 2)" "$UPGRADE")" "yes"
check "the upgrade note names the new default (8)" \
  "$(has_re "$(b17_num 8)" "$UPGRADE")" "yes"
check "the upgrade note says the default changed" \
  "$(has_re '(^|[^A-Za-z])defaults?([^A-Za-z]|$)' "$UPGRADE")" "yes"
check "the upgrade note says the MEANING changed too, not just the number" \
  "$(has_re '(^|[^A-Za-z])(meaning|means|meant)([^A-Za-z]|$)' "$UPGRADE")" "yes"

# ---------------------------------------------------------------------------
# 23. plugin.json: the mandatory bump, and a description that stops promising
#     figures the render no longer has
# ---------------------------------------------------------------------------
# version-bump-lint reads COMMITTED state, so a plugin edit without a bump is
# invisible to installed users — the contract calls the bump mandatory for
# exactly that reason. Section 6's floor is historical and a bump above it
# happened three versions ago; this is the clause with teeth: strictly above
# the version this plan started from. That baseline is the one literal here,
# and it cannot be derived from git without going vacuous the moment the
# implementer commits the bump.

VERSION_BASE="0.6.0"
check "plugin.json version ($PLUGIN_VERSION) is strictly above the $VERSION_BASE this plan started from" \
  "$([ -n "$PLUGIN_VERSION" ] && [ "$PLUGIN_VERSION" != "$VERSION_BASE" ] \
      && [ "$(printf '%s\n%s\n' "$VERSION_BASE" "$PLUGIN_VERSION" | sort -V | head -1)" = "$VERSION_BASE" ] \
      && echo yes || echo no)" "yes"

# The description is the plugin's one-line promise, and it currently promises
# two things B05 removes: pacing against awake hours, and the figures derived
# from it. Asserted by name, in the same polarity the README checks use.
check "plugin.json's description no longer promises awake-hours pacing" \
  "$(has_re 'awake' "$PLUGIN_DESC")" "no"
check "plugin.json's description no longer promises the retired %t figure" \
  "$(has_fixed '%t' "$PLUGIN_DESC")" "no"
check "plugin.json's description no longer promises the retired %/d figure" \
  "$(has_fixed '%/d' "$PLUGIN_DESC")" "no"
# Non-vacuity for the three above: a description emptied of everything would
# pass them all. It still has to describe the two plan meters it does render.
check "plugin.json's description still names the weekly and 5-hour plan limits" \
  "$(b17_near "$PLUGIN_DESC" '(^|[^A-Za-z])weekly' '5.hour' 80)" "yes"

# ---------------------------------------------------------------------------
# 24. The opening blurb's pacing promise
# ---------------------------------------------------------------------------
# The blurb currently promises the plan limits are "paced against the hours you
# are actually awake". B05 retires the awake-hours model, so that promise is
# false documentation the moment it lands. Section 11 already asserts the blurb
# is identifiable and reads as a sentence; what is added here is the subject.
# The positive half is DERIVED-STYLE rather than an exact sentence: what the
# clause requires is that the blurb name the working-week pacing, not that it
# use one wording, so the check is a proximity check between the pacing verb
# and the working-week vocabulary, the shape section 19 uses on the colours.

check "the opening blurb no longer promises pacing against awake hours" \
  "$(has_re 'awake' "$BLURB")" "no"
check "the opening blurb no longer promises the retired sleep-hours exclusion" \
  "$(has_re '(^|[^A-Za-z])sleep' "$BLURB")" "no"
check "the opening blurb paces the limits against the working week instead" \
  "$(b17_near "$BLURB" '(^|[^A-Za-z])(pace|paced|paces|pacing)' \
     '(^|[^A-Za-z])(work(ing)?[- ](week|day|days|hours)|hours you( actually)? work)' 80)" "yes"
# Non-vacuity for both absence checks above: an absence check passes trivially
# against a blurb that no longer promises anything at all, so the promise the
# pacing attaches to has to still be there.
check "the opening blurb still names the two plan limits it paces" \
  "$(b17_near "$BLURB" '(^|[^A-Za-z])weekly' '5.hour' 80)" "yes"

# ---------------------------------------------------------------------------
# 25. No section of the README names a file that does not exist
# ---------------------------------------------------------------------------
# `## Commands` names lib/burn-tick.sh among the libraries context.sh sources,
# and `## Tests` lists lib/burn-tick.test.sh in the run block. B05 deletes both
# files. The check is DERIVED — every plugin-relative path either section names
# must exist on disk — rather than hard-coded to that one name, so the next
# deletion is covered without anyone remembering to come back here.

grep -oE '(lib|scripts)/[A-Za-z0-9._-]+\.(sh|json|tsv)' <<<"$COMMANDS" \
  | sort -u > "$TMP/commands-paths"
# Non-vacuity: an empty extraction (section renamed, section() cutting early)
# would assert nothing at all and read as a clean pass.
check "the Commands section names plugin files at all (path oracle is not empty)" \
  "$([ -s "$TMP/commands-paths" ] && echo yes || echo no)" "yes"
check "the Commands section still documents the renderer entry point it describes" \
  "$(grep -c '^scripts/context\.sh$' "$TMP/commands-paths")" "1"
while read -r _p; do
  [ -n "$_p" ] || continue
  check "the Commands section's '$_p' still exists in the plugin" \
    "$([ -e "$PLUGIN_DIR/$_p" ] && echo yes || echo no)" "yes"
done < "$TMP/commands-paths"

# The libraries paragraph's own descriptions of what it names. `lib/burn-tick.sh
# (the sub-tick interpolator behind %t)` and `lib/burn-math.sh (the awake-hours
# pacing model)` both state something B05 makes false, which is the rule the
# amended contract gives for what belongs to this block wherever it sits.
check "the libraries paragraph no longer credits the retired sub-tick interpolator" \
  "$(has_re 'interpolat' "$LIBS_P")" "no"
check "the libraries paragraph no longer explains the retired %t figure" \
  "$(has_fixed '%t' "$LIBS_P")" "no"
check "the libraries paragraph no longer describes the retired awake-hours model" \
  "$(has_re 'awake|sleep' "$LIBS_P")" "no"
# Non-vacuity for those three: the paragraph must still name every burnrate
# library that survives, so deleting the paragraph outright fails here. Derived
# from the same lib/burn-*.sh scan section 15 uses.
for _f in "$PLUGIN_DIR"/lib/burn-*.sh; do
  case "$_f" in *.test.sh) continue ;; esac
  [ -f "$_f" ] || continue
  _b="$(basename "$_f")"
  check "the libraries paragraph still names the surviving lib/$_b" \
    "$(has_fixed "lib/$_b" "$LIBS_P")" "yes"
done

TESTS="$(section '## Tests')"
check "the Tests section is non-empty" \
  "$([ -n "$TESTS" ] && echo yes || echo no)" "yes"
grep -oE 'plugins/[A-Za-z0-9._-]+/(lib|scripts)/[A-Za-z0-9._-]+\.(sh|json|tsv)' <<<"$TESTS" \
  | sort -u > "$TMP/tests-paths"
check "the Tests section lists runnable test paths (path oracle is not empty)" \
  "$([ -s "$TMP/tests-paths" ] && echo yes || echo no)" "yes"
# Non-vacuity of the right SECTION, not merely a non-empty one: the run block
# has to still list this suite. A Tests section emptied of its burnrate entries
# would otherwise satisfy every existence check below.
check "the Tests section still lists this suite" \
  "$(grep -c '/scripts/readme\.test\.sh$' "$TMP/tests-paths")" "1"
while read -r _p; do
  [ -n "$_p" ] || continue
  check "the Tests section's '$_p' still exists in the repo" \
    "$([ -e "$REPO_ROOT/$_p" ] && echo yes || echo no)" "yes"
done < "$TMP/tests-paths"

# ---------------------------------------------------------------------------
# 26. The root README's Plugins-table row for statusline
# ---------------------------------------------------------------------------
# The row's DESCRIPTION carries the same "paced to your awake hours" promise the
# blurb does, and is stale for the same reason. Its VERSION cell is deliberately
# NOT re-asserted here: section 6 already compares it against plugin.json and
# fails the moment section 23's mandatory bump lands without the row moving, and
# readme-lint gates the same equality repo-wide. A second copy would be noise.

ROOT_ROW="$(grep -E '^\|[[:space:]]*\[?statusline[](]' "$ROOT_README" 2>/dev/null | head -1)"
check "the root README's Plugins-table row for statusline is identifiable" \
  "$([ -n "$ROOT_ROW" ] && echo yes || echo no)" "yes"
ROOT_ROW_DESC="$(trim "$(awk -F'|' '{ print $4 }' <<<"$ROOT_ROW")")"
check "the root README row's description cell is readable (scoping oracle is not empty)" \
  "$([ -n "$ROOT_ROW_DESC" ] && echo yes || echo no)" "yes"

check "the root README row no longer paces the limits to your awake hours" \
  "$(has_re 'awake' "$ROOT_ROW_DESC")" "no"
check "the root README row paces them against the working week instead" \
  "$(b17_near "$ROOT_ROW_DESC" '(^|[^A-Za-z])(pace|paced|paces|pacing)' \
     '(^|[^A-Za-z])(work(ing)?[- ](week|day|days|hours)|hours you( actually)? work)' 80)" "yes"
# Non-vacuity: the row must still describe the two plan limits it paces, so a
# description gutted of the whole clause fails rather than passing the absence
# check for free.
check "the root README row still names the two plan limits it paces" \
  "$(b17_near "$ROOT_ROW_DESC" '(^|[^A-Za-z])weekly' '5.hour' 80)" "yes"

# ===========================================================================
# B09 line1-cache-docs
# ===========================================================================

# ---------------------------------------------------------------------------
# 27. The line-1 render oracle: the separator and the hyperlink, derived
# ---------------------------------------------------------------------------

B09_WD="$TMP/b09-wd"; mkdir -p "$B09_WD/sub"

BEL="$(printf '\007')"

# b09_strip_links(): drops OSC 8 hyperlink framing (either terminator — B07
# moves osc8_link from ST to BEL, and this has to read both) and then SGR
# colour, leaving the visible text. Order matters: with the BEL already gone
# there is nothing left to say where a url stops and its text starts.
b09_strip_links() { # reads stdin
  sed -E -e "s/${ESC}\]8;;[^${ESC}${BEL}]*(${BEL}|${ESC}\\\\)//g" \
         -e "s/${ESC}\[[0-9;]*m//g"
}

# b09_render_line1(): scripts/context.sh's line 1 for a payload whose
# project_dir and current_dir DIFFER, hermetic the same way b11_render is —
# a plain temp cwd (not a git repo, no .local, so no branch, no badge, no
# background refresher), temp cache dirs, caching disabled. Returned RAW so
# the hyperlink check below can see the sequence; b09_strip_links strips it
# for the text checks.
b09_render_line1() {
  local json
  json="{\"workspace\":{\"current_dir\":\"$B09_WD/sub\",\"project_dir\":\"$B09_WD\"}"
  json="$json,\"transcript_path\":\"\",\"session_id\":\"b09-fixture-session\""
  json="$json,\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"}"
  json="$json,\"context_window\":{\"context_window_size\":1000000,\"total_input_tokens\":30000}}"
  printf '%s' "$json" \
    | env CLAUDE_PROJECTS_DIR="$TMP/b09-projects" CCOST_CACHE_DIR="$TMP/b09-ccost" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$TMP/b09-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        bash "$CONTEXT_SH" 2>/dev/null \
    | sed -n '1p'
}

B09_L1_RAW="$(b09_render_line1)"
B09_L1="$(printf '%s' "$B09_L1_RAW" | b09_strip_links)"
check "the fixture render produced a line 1 (oracle is not empty)" \
  "$([ -n "$B09_L1" ] && echo yes || echo no)" "yes"

# The separator is the one non-ASCII run in a line 1 whose every other token is
# an ASCII temp path. LC_ALL=C so the run comes back as whole bytes.
B09_SEP="$(printf '%s' "$B09_L1" | LC_ALL=C grep -oE '[^ -~]+' | head -1)"
check "the render separates the project dir from the current dir with a character the prose can name" \
  "$([ -n "$B09_SEP" ] && echo yes || echo no)" "yes"
# Guards the derivation: a separator with nothing on one side of it would be a
# render that dropped one of the two directories, and every check below would
# then be pinning the prose to a broken form.
B09_SEP_LEFT=""; B09_SEP_RIGHT=""
if [ -n "$B09_SEP" ]; then
  B09_SEP_LEFT="$(trim "${B09_L1%%"$B09_SEP"*}")"
  B09_SEP_RIGHT="$(trim "${B09_L1#*"$B09_SEP"}")"
fi
check "the derived separator really sits between two path components" \
  "$([ -n "$B09_SEP_LEFT" ] && [ -n "$B09_SEP_RIGHT" ] && echo yes || echo no)" "yes"
# And it is the character section 9's alphabet exempts. Without this the
# exemption is a hole: a renderer emitting some other symbol would leave the
# README free to carry a character no check ever looks at.
check "the separator the renderer emits is the one the alphabet check exempts" \
  "$B09_SEP" "›"

# A sentinel, so the "the prose names the separator" checks below cannot pass
# for free on an empty needle (grep -F '' matches every line).
B09_SEP_PAT="${B09_SEP:-__no-separator-derived__}"

check "the render hyperlinks the path segment as an OSC 8 file:// link" \
  "$(printf '%s' "$B09_L1_RAW" | grep -qF "${ESC}]8;;file://" && echo yes || echo no)" "yes"

# b09_pos(text ere): the byte offset of the first match of ERE in TEXT
# flattened to one line, or "" when it does not appear. Offsets are how the
# order of two claims in one paragraph is compared without asserting the
# wording between them.
b09_pos() { # text ere
  one_line "$1" | grep -boiE "$2" | head -1 | cut -d: -f1
}

# ---------------------------------------------------------------------------
# 28. The line-1 prose: the project dir at the head, and the `›` form
# ---------------------------------------------------------------------------
# LINE1_P (section 13) is the paragraph under `## What to expect` describing
# line 1 in the order it renders. B07 puts the project directory at its head,
# so the paragraph that enumerates that order is where the change lands.

check "the 'Line 1' paragraph is still identifiable (scoping oracle is not empty)" \
  "$([ -n "$LINE1_P" ] && echo yes || echo no)" "yes"
check "the 'Line 1' paragraph names the project directory the render now leads with" \
  "$(has_re '(^|[^a-z])project dir(ectory)?' "$LINE1_P")" "yes"

B09_POS_PROJECT="$(b09_pos "$LINE1_P" 'project dir')"
B09_POS_CURRENT="$(b09_pos "$LINE1_P" 'current dir')"
B09_POS_BRANCH="$(b09_pos "$LINE1_P" 'git branch')"
check "the 'Line 1' paragraph still enumerates the branch after the path (order oracle is not empty)" \
  "$([ -n "$B09_POS_BRANCH" ] && echo yes || echo no)" "yes"
check "the 'Line 1' paragraph puts the project dir before the current dir, as the render does" \
  "$([ -n "$B09_POS_PROJECT" ] && [ -n "$B09_POS_CURRENT" ] \
      && [ "$B09_POS_PROJECT" -lt "$B09_POS_CURRENT" ] && echo yes || echo no)" "yes"
check "the 'Line 1' paragraph puts both of them before the branch, as the render does" \
  "$([ -n "$B09_POS_PROJECT" ] && [ -n "$B09_POS_BRANCH" ] \
      && [ "$B09_POS_PROJECT" -lt "$B09_POS_BRANCH" ] && echo yes || echo no)" "yes"

check "the 'Line 1' paragraph names the separator the render emits between the two dirs" \
  "$(has_fixed "$B09_SEP_PAT" "$LINE1_P")" "yes"
check "the 'Line 1' paragraph says what follows that separator is relative to the project dir" \
  "$(b17_near "$LINE1_P" "$B09_SEP_PAT" '(^|[^A-Za-z])(relative|inside|under|beneath|within)' 160)" "yes"
check "the 'Line 1' paragraph describes the same-path case as a single segment" \
  "$(b17_near "$LINE1_P" '(^|[^A-Za-z])(same|identical|matches|equal)' \
     '(^|[^A-Za-z])(one|single|just|only)([^A-Za-z]|$)' 120)" "yes"
check "the 'Line 1' paragraph keeps the ~ collapse for \$HOME" \
  "$(has_fixed 'HOME' "$LINE1_P")" "yes"

# The hyperlink, scoped to the sentences making a claim about the path segment
# itself. The paragraph already calls the PR badge clickable, and both a
# paragraph-wide check and one scoped to "current dir" would be satisfied by
# that existing sentence alone — the enumeration naming the current directory
# is the same sentence the badge's `#N` sits in.
B09_PATH_CLAIM="$(b17_claims "$LINE1_P" '(project dir|path segment)')"
check "the 'Line 1' paragraph makes a claim about the path segment at all (scoping oracle is not empty)" \
  "$([ -n "$B09_PATH_CLAIM" ] && echo yes || echo no)" "yes"
check "that claim says the path segment is a clickable link, which the render makes it" \
  "$(has_re 'clickable|hyperlink|link' "$B09_PATH_CLAIM")" "yes"

# Non-vacuity for strip_allowed's sixth exemption, the shape sections 9 uses on
# the other five: the character is exempt because the prose has to carry it.
check "the $B09_SEP_PAT path separator is kept in the prose" \
  "$(has_fixed "$B09_SEP_PAT" "$BODY")" "yes"

# ---------------------------------------------------------------------------
# 29. The example block is regenerated for the new line 1
# ---------------------------------------------------------------------------
# Section 12 pins the example's line 2 against a live render and its line 1's
# alphabet. What line 1 gains here is the form: an example still showing a bare
# single path documents a render that no longer exists whenever the two dirs
# differ, which is the case the prose above spends its sentences on.

check "the example's line 1 is still identifiable (scoping oracle is not empty)" \
  "$([ -n "$EX_L1" ] && echo yes || echo no)" "yes"
check "the example's line 1 shows the project-dir form with the render's own separator" \
  "$(has_fixed "$B09_SEP_PAT" "$EX_L1")" "yes"
check "the example's line 1 still shows the segments past the path (it is a full render)" \
  "$(b17_near "$EX_L1" "$B09_SEP_PAT" '(^|[^A-Za-z])(Build|In Progress|#[0-9])' 200)" "yes"

# ---------------------------------------------------------------------------
# 30. "Caching and staleness": the session_id key and the one-day sweep
# ---------------------------------------------------------------------------

CACHING="$(b17_subsection '### Caching and staleness')"
check "the 'Caching and staleness' section survives and is identifiable" \
  "$([ -n "$CACHING" ] && echo yes || echo no)" "yes"
# Anchors: the section still documents the surface it always did, so every
# absence check below is aimed at prose that is really there.
check "the caching section still names the cache directory knob" \
  "$(has_fixed 'CLAM_STATUSLINE_CACHE_DIR' "$CACHING")" "yes"
check "the caching section still names the TTL knob" \
  "$(has_fixed 'CLAM_STATUSLINE_SEGMENT_TTL_SECONDS' "$CACHING")" "yes"
check "the caching section still says a cache failure degrades to a full render" \
  "$(has_re 'degrade|freshly computed|never a broken' "$CACHING")" "yes"
check "the caching section still says the path segment renders live, never from the bundle" \
  "$(b17_near "$CACHING" '(^|[^A-Za-z])path' '(^|[^A-Za-z])live' 120)" "yes"

# The key itself. B08 keys the bundle on session_id — the field Claude Code
# documents as stable for a session's lifetime and unique per session.
check "the caching section names session_id as what the bundle is keyed on" \
  "$(has_fixed 'session_id' "$CACHING")" "yes"
check "the caching section ties session_id to the keying, not just to the wording 'per-session'" \
  "$(b17_near "$CACHING" 'session_id' '(^|[^A-Za-z])(key|keyed|keys|per.session|scope|scoped)' 140)" "yes"
# The transcript path is no longer the key. Scoped to the SENTENCES of this
# section, because ccost.sh's transcript argument is documented elsewhere in
# the file and is untouched by this unit.
check "no sentence of the caching section still keys the bundle on the transcript path" \
  "$(one_line "$(b17_claims "$CACHING" '(^|[^A-Za-z])transcript')")" ""

# The sweep. What the reader needs is the age bound and the fact that something
# is removed at it; the cold-path-only detail is a render-budget invariant, not
# a documented promise, and is deliberately not required of the prose.
check "the caching section names the one-day age bound the sweep applies" \
  "$(has_re '(^|[^A-Za-z])(one day|a day|24 hours|day old|daily)' "$CACHING")" "yes"
check "the caching section says files older than that are removed" \
  "$(b17_near "$CACHING" '(^|[^A-Za-z])(day|24 hours)' \
     'remov|delet|sweep|swept|prun|clean|tidie|tidy|discard|age[sd]? out' 180)" "yes"
# The caveat the sweep now handles belongs to nobody once the sweep exists —
# section 31 pins its removal where it is actually written.
check "the caching section does not tell the reader to delete the cache by hand" \
  "$(has_fixed 'safe to delete by hand' "$CACHING")" "no"

# The `scripts/context.sh` entry under `### Scripts` says the same things in
# miniature, and has to agree with the section it cross-references.
CTX_ENTRY="$(paragraph_in "$COMMANDS" '**`scripts/context.sh`**')"
check "the scripts/context.sh entry is identifiable (scoping oracle is not empty)" \
  "$([ -n "$CTX_ENTRY" ] && echo yes || echo no)" "yes"
check "the scripts/context.sh entry still cross-references the caching section" \
  "$(has_fixed 'Caching and staleness' "$CTX_ENTRY")" "yes"
check "the scripts/context.sh entry still says the bundle is cached per session" \
  "$(has_re '(^|[^A-Za-z])per.session|session' "$CTX_ENTRY")" "yes"
check "no cache claim in the scripts/context.sh entry names the transcript path" \
  "$(one_line "$(b17_claims "$CTX_ENTRY" '(^|[^A-Za-z])transcript' | grep -iE 'cach|bundle|key')")" ""

# ---------------------------------------------------------------------------
# 31. "Uninstalling": the cache-clutter paragraph the sweep makes false
# ---------------------------------------------------------------------------
# The paragraph currently tells the reader NEITHER cache is removed
# automatically and both are safe to delete by hand. B08's sweep makes the
# first half false for the statusline cache. ccost's cache is untouched by this
# unit, so the assertions are scoped to the sentences naming the statusline one
# and the paragraph is required to go on naming both.

UNINSTALL="$(section '## Uninstalling')"
check "the 'Uninstalling' section is non-empty" \
  "$([ -n "$UNINSTALL" ] && echo yes || echo no)" "yes"
CLUTTER_P="$(paragraph_in "$UNINSTALL" '.statusline-cache')"
check "the cache-clutter paragraph is identifiable (scoping oracle is not empty)" \
  "$([ -n "$CLUTTER_P" ] && echo yes || echo no)" "yes"
check "the cache-clutter paragraph still names the statusline cache directory" \
  "$(has_fixed '.statusline-cache' "$CLUTTER_P")" "yes"
check "the cache-clutter paragraph still names the ccost cache directory this unit does not touch" \
  "$(has_fixed '.ccost-cache' "$CLUTTER_P")" "yes"

B09_CLUTTER_CLAIM="$(b17_claims "$CLUTTER_P" 'statusline-cache')"
check "the paragraph makes a claim about the statusline cache (scoping oracle is not empty)" \
  "$([ -n "$B09_CLUTTER_CLAIM" ] && echo yes || echo no)" "yes"
check "that claim no longer says nothing removes anything from the statusline cache" \
  "$(has_re '(^|[^A-Za-z])(neither|not removed|never removed|nothing removes)' "$B09_CLUTTER_CLAIM")" "no"
check "nor calls the statusline cache safe to delete by hand, which the sweep now handles" \
  "$(has_fixed 'safe to delete by hand' "$B09_CLUTTER_CLAIM")" "no"
# The positive half: an absence check on a paragraph gutted of its subject
# passes for free, so the claim has to say what DOES happen to that cache now.
check "that claim says the statusline cache bounds itself instead" \
  "$(has_re 'sweep|swept|prun|tidie|tidy|bound|older than|one day|a day|itself' \
     "$B09_CLUTTER_CLAIM")" "yes"

# ===========================================================================
# B12 subagent-docs
# ===========================================================================

# ---------------------------------------------------------------------------
# 32. The subagent-rows subsection under `## What to expect`
# ---------------------------------------------------------------------------
# Located by meaning rather than by title (see the header): the first H3 inside
# `## What to expect` whose heading names subagents or the agent panel.

b12_named_subsection() { # ere, matched case-insensitively against the H3 line
  awk -v pat="$1" '
    !inb && /^###[[:space:]]/ { h = tolower($0); if (h ~ pat) { inb = 1 } ; next }
    inb && /^#+[[:space:]]/ { exit }
    inb { print }
  ' <<<"$WTE"
}

check "'What to expect' is still identifiable (scoping oracle is not empty)" \
  "$([ -n "$WTE" ] && echo yes || echo no)" "yes"

B12_SUB="$(b12_named_subsection 'subagent|agent panel|agent-panel|agent rows')"
check "'What to expect' gains a subsection about the agent-panel rows" \
  "$([ -n "$B12_SUB" ] && echo yes || echo no)" "yes"

# The row inventory: what scripts/subagent.sh puts in a row, one check per
# field the B10 contract names.
check "the subagent subsection says a row carries the task's name" \
  "$(b17_near "$B12_SUB" '(^|[^A-Za-z])name([^A-Za-z]|$)' \
     '(^|[^A-Za-z])(task|agent|subagent)' 120)" "yes"
check "the subagent subsection says a row carries the model" \
  "$(has_re '(^|[^A-Za-z])model' "$B12_SUB")" "yes"
check "the subagent subsection says a row carries the reasoning effort" \
  "$(has_re '(^|[^A-Za-z])effort' "$B12_SUB")" "yes"
check "the subagent subsection says a row carries the directory the task runs in" \
  "$(has_re '(^|[^A-Za-z])(cwd|director(y|ies)|folder)' "$B12_SUB")" "yes"
# The directory is the BASENAME of the task's cwd, not the whole path — a row
# is a few columns wide and the prose has to say which part the reader sees.
check "the subagent subsection says the directory is shown as its basename, not a full path" \
  "$(b17_near "$B12_SUB" '(^|[^A-Za-z])(cwd|director(y|ies)|folder)' \
     '(basename|base name|last (path )?(component|segment)|final segment|leaf|directory name|name of (the|its) (working )?director)' 160)" "yes"
check "the subagent subsection says a row carries the context percentage" \
  "$(b17_near "$B12_SUB" '(^|[^A-Za-z])context' '(%|percent)' 120)" "yes"

# Provenance: every figure on a row is that subagent's own, which is the whole
# reason B10 exists as a separate renderer. A subsection describing the fields
# without saying whose they are documents a row the `statusLine` script could
# already have rendered.
check "the subagent subsection says the figures are the subagent's own, not the session's" \
  "$(b17_near "$B12_SUB" '(^|[^A-Za-z])(its own|their own|that (task|agent|subagent).s own|per.(task|agent|subagent)|the (task|agent|subagent).s own)' \
     '(^|[^A-Za-z])(main session|orchestrator|coordinator|session.s|top.level|parent)' 220)" "yes"

# The effort-absent case, at SENTENCE scope (see the header for why).
B12_EFFORT_CLAIMS="$(b17_claims "$B12_SUB" '(^|[^A-Za-z])effort')"
check "the subagent subsection makes a claim about effort at all (scoping oracle is not empty)" \
  "$([ -n "$B12_EFFORT_CLAIMS" ] && echo yes || echo no)" "yes"
B12_INHERIT_CLAIM="$(printf '%s\n' "$B12_EFFORT_CLAIMS" | grep -iE 'inherit')"
check "one effort sentence explains the absent case as inheritance" \
  "$([ -n "$B12_INHERIT_CLAIM" ] && echo yes || echo no)" "yes"
# Non-vacuity for the sentence above: "the effort is inherited" alone still
# leaves a reader staring at a blank column. The same sentence has to say that
# nothing is rendered in that case.
check "that sentence says what the reader actually sees when the effort is inherited" \
  "$(has_re '(no effort|nothing|blank|empty|omitted|omits|absent|missing|not (shown|rendered|printed|displayed)|without an effort|no reasoning.effort)' \
     "$B12_INHERIT_CLAIM")" "yes"

# ---------------------------------------------------------------------------
# 33. The `scripts/subagent.sh` entry under `### Scripts`
# ---------------------------------------------------------------------------
# Scoped with paragraph_in against `## Commands`, the way section 30 scopes the
# scripts/context.sh entry. Section 25 separately asserts that every scripts/
# path this section names exists on disk, so this entry cannot document a file
# that does not ship.

B12_SCRIPT_ENTRY="$(paragraph_in "$COMMANDS" '**`scripts/subagent.sh`**')"
check "the scripts/subagent.sh entry is identifiable (scoping oracle is not empty)" \
  "$([ -n "$B12_SCRIPT_ENTRY" ] && echo yes || echo no)" "yes"
check "the scripts/subagent.sh entry names the settings key it is wired to" \
  "$(has_fixed 'subagentStatusLine' "$B12_SCRIPT_ENTRY")" "yes"
check "the scripts/subagent.sh entry says what it renders" \
  "$(has_re '(agent panel|agent-panel|subagent row|row per|one row|per.(task|subagent) row)' \
     "$B12_SCRIPT_ENTRY")" "yes"

# The process budget, in the same terms the scripts/context.sh entry uses for
# its own: one jq, and no git.
check "the scripts/subagent.sh entry states its one-jq budget" \
  "$(has_re '(^|[^A-Za-z])one[[:space:]]+.?jq' "$B12_SCRIPT_ENTRY")" "yes"
check "the scripts/subagent.sh entry states that it runs no git" \
  "$(has_re '(^|[^A-Za-z])no[[:space:]]+.?git' "$B12_SCRIPT_ENTRY")" "yes"

# Never-loud errors: a status line that fails visibly is worse than one that
# fails invisibly, so the failure sentence has to say the rows simply keep
# their default rendering.
B12_ERR_CLAIM="$(b17_claims "$B12_SCRIPT_ENTRY" '(malformed|invalid|bad (input|payload)|error|fails?|failure|missing jq|jq is (missing|absent)|without jq)')"
check "the scripts/subagent.sh entry makes a failure claim at all (scoping oracle is not empty)" \
  "$([ -n "$B12_ERR_CLAIM" ] && echo yes || echo no)" "yes"
check "that failure claim says a bad payload leaves the rows at their default rendering" \
  "$(has_re '(default|silent|silently|invisibl|no lines|nothing|unchanged|never (writes|exits|fails))' \
     "$B12_ERR_CLAIM")" "yes"

# ---------------------------------------------------------------------------
# 34. `## Commands` and `## Uninstalling`: setup writes three keys, remove
#     reverses three
# ---------------------------------------------------------------------------
# B11 turns a one-key setup into a three-key one. Every passage describing what
# setup writes, or what uninstalling leaves behind, states a key set — and a key
# set that names one of three is false documentation, not merely incomplete.

B12_SKILLS="$(b17_subsection '### Skills')"
check "the Skills subsection is identifiable (scoping oracle is not empty)" \
  "$([ -n "$B12_SKILLS" ] && echo yes || echo no)" "yes"

B12_SETUP_ENTRY="$(paragraph_in "$B12_SKILLS" '**`/statusline:setup`**')"
check "the /statusline:setup entry is identifiable (scoping oracle is not empty)" \
  "$([ -n "$B12_SETUP_ENTRY" ] && echo yes || echo no)" "yes"
# Non-vacuity for the three key checks below: the entry must still describe the
# merge it performs, so an entry gutted of its subject fails here rather than
# quietly satisfying nothing.
check "the /statusline:setup entry still describes the settings merge" \
  "$(b17_near "$B12_SETUP_ENTRY" '(^|[^A-Za-z])(merge[sd]?|writes?|adds?)' \
     'settings\.json' 200)" "yes"
check "the /statusline:setup entry says it writes statusLine" \
  "$(has_fixed 'statusLine' "$B12_SETUP_ENTRY")" "yes"
check "the /statusline:setup entry says it writes subagentStatusLine" \
  "$(has_fixed 'subagentStatusLine' "$B12_SETUP_ENTRY")" "yes"
check "the /statusline:setup entry says it writes refreshInterval" \
  "$(has_fixed 'refreshInterval' "$B12_SETUP_ENTRY")" "yes"

B12_REMOVE_ENTRY="$(paragraph_in "$B12_SKILLS" '**`/statusline:setup remove`**')"
check "the /statusline:setup remove entry is identifiable (scoping oracle is not empty)" \
  "$([ -n "$B12_REMOVE_ENTRY" ] && echo yes || echo no)" "yes"
check "the remove entry still describes deleting the keys or restoring the backup" \
  "$(has_re '(delete[sd]?|remove[sd]?|restore[sd]?)' "$B12_REMOVE_ENTRY")" "yes"
check "the remove entry says it reverses statusLine" \
  "$(has_fixed 'statusLine' "$B12_REMOVE_ENTRY")" "yes"
check "the remove entry says it reverses subagentStatusLine" \
  "$(has_fixed 'subagentStatusLine' "$B12_REMOVE_ENTRY")" "yes"
check "the remove entry says it reverses refreshInterval" \
  "$(has_fixed 'refreshInterval' "$B12_REMOVE_ENTRY")" "yes"

# `## Uninstalling` carries the same key set from the other end: the section
# tells the reader to run remove so settings.json stops pointing at paths that
# no longer exist, and there are now two such paths and a third key beside them.
check "the 'Uninstalling' section still tells the reader to run the remove command" \
  "$(has_fixed '/statusline:setup remove' "$UNINSTALL")" "yes"
check "the 'Uninstalling' section names statusLine among the keys remove reverses" \
  "$(has_fixed 'statusLine' "$UNINSTALL")" "yes"
check "the 'Uninstalling' section names subagentStatusLine among them" \
  "$(has_fixed 'subagentStatusLine' "$UNINSTALL")" "yes"
check "the 'Uninstalling' section names refreshInterval among them" \
  "$(has_fixed 'refreshInterval' "$UNINSTALL")" "yes"

# ---------------------------------------------------------------------------
# 35. plugin.json: the bump this block's edits require, and a description that
#     mentions the rows they add
# ---------------------------------------------------------------------------
# Same reasoning as section 23, one plan step later: version-bump-lint reads
# COMMITTED state, so a README and skill change without a bump is invisible to
# installed users. The baseline is the version this block starts from and is the
# one literal here — derived from git it would go vacuous the moment the
# implementer commits.

B12_VERSION_BASE="0.8.0"
check "plugin.json version ($PLUGIN_VERSION) is strictly above the $B12_VERSION_BASE this block starts from" \
  "$([ -n "$PLUGIN_VERSION" ] && [ "$PLUGIN_VERSION" != "$B12_VERSION_BASE" ] \
      && [ "$(printf '%s\n%s\n' "$B12_VERSION_BASE" "$PLUGIN_VERSION" | sort -V | head -1)" = "$B12_VERSION_BASE" ] \
      && echo yes || echo no)" "yes"

# The description is the plugin's one-line promise, and the agent panel is now
# part of what it renders.
check "plugin.json's description mentions the subagent rows the plugin now renders" \
  "$(has_re '(subagent|agent panel|agent-panel)' "$PLUGIN_DESC")" "yes"
# Non-vacuity: a description rewritten around the new rows alone would drop the
# two lines the plugin has always been about. Section 23 holds the plan meters;
# this holds the statusline itself.
check "plugin.json's description still describes the two statusline lines" \
  "$(b17_near "$PLUGIN_DESC" '(^|[^A-Za-z])(two lines|statusline|status line)' \
     '(^|[^A-Za-z])(model|context|branch|path)' 200)" "yes"

# ===========================================================================
# B15 setup-schedule-docs
# ===========================================================================

# ---------------------------------------------------------------------------
# 36. The schedule step in the two skill entries, the off-switch section, and
#     the two version surfaces
# ---------------------------------------------------------------------------

# b15_entry(text needle): one `**`…`**` entry of a Commands subsection, from the
# line holding the fixed string NEEDLE to the next entry or heading — blank
# lines included, so a two-paragraph entry is read whole (see the header).
b15_entry() { # text needle
  awk -v needle="$2" '
    !inb { if (index($0, needle)) { inb = 1; print } ; next }
    /^#+[[:space:]]/ { exit }
    index($0, "**`") == 1 { exit }
    { print }
  ' <<<"$1"
}

# The knob names, read off the env-var table's row set (section 2's oracle,
# which is held equal in both directions to the names the scripts read).
grep -E '^CLAM_STATUSLINE_(WORK_DAYS|DAY_START|DAY_END)$' "$TMP/documented" \
  | sort > "$TMP/b15-knobs"
check "the three schedule knobs are derivable from the env-var table (oracle is not empty)" \
  "$(wc -l < "$TMP/b15-knobs" | tr -d ' ')" "3"
# And the same three are really read by the plugin's own sources, so the names
# the prose is made to carry are not table-only fictions.
check "the three schedule knobs are read by the plugin's own scripts" \
  "$(one_line "$(comm -23 "$TMP/b15-knobs" "$TMP/derived")")" ""

# --- the /statusline:setup entry -------------------------------------------

B15_SETUP="$(b15_entry "$B12_SKILLS" '**`/statusline:setup`**')"
check "the /statusline:setup entry is identifiable whole (scoping oracle is not empty)" \
  "$([ -n "$B15_SETUP" ] && echo yes || echo no)" "yes"

while read -r _k; do
  [ -n "$_k" ] || continue
  check "the /statusline:setup entry names $_k among the schedule keys" \
    "$(has_fixed "$_k" "$B15_SETUP")" "yes"
done < "$TMP/b15-knobs"

check "the /statusline:setup entry says setup shows the effective working week" \
  "$(b17_near "$B15_SETUP" '(^|[^A-Za-z])(shows?|discloses?|displays?|reports?|prints?)' \
     '(working week|work week|schedule|working days|working hours|hours you)' 200)" "yes"
check "the /statusline:setup entry says setup asks about that schedule" \
  "$(b17_near "$B15_SETUP" '(^|[^A-Za-z])(asks?|asking|prompts?|confirms?)' \
     '(working week|work week|schedule|working days|working hours|hours you)' 200)" "yes"
check "the /statusline:setup entry says the schedule keys are written only when the schedule changes" \
  "$(b17_near "$B15_SETUP" '(^|[^A-Za-z])(only|unless)([^A-Za-z]|$)' \
     '(^|[^A-Za-z])(writes?|written|write)' 220)" "yes"
# The other half of the same clause, and the one a reader acts on: accepting the
# schedule as shown leaves the settings file alone.
check "the /statusline:setup entry says accepting the shown schedule writes nothing" \
  "$(b17_near "$B15_SETUP" '(accepts?|accepting|keeps?|keeping|unchanged|as shown|agrees?|the default schedule)' \
     '(writes nothing|nothing is written|writes no|no .{0,30}(keys?|values?|settings?) (are|is) written|not written|leaves? .{0,40}(untouched|unchanged|alone)|without writing)' 200)" "yes"
# One jq pass, still: the schedule keys join the merge the entry already
# describes rather than adding a second write to the settings file.
check "the /statusline:setup entry says the schedule keys join the same single jq merge" \
  "$(b17_near "$B15_SETUP" '(^|[^A-Za-z])(same|one|single)([^A-Za-z]|$)' \
     '(^|[^A-Za-z])jq([^A-Za-z]|$)' 160)" "yes"
# Non-vacuity beyond section 34's: the entry still describes the write it is an
# entry about, so an entry rewritten around the schedule alone fails here.
check "the /statusline:setup entry still names the settings file it writes" \
  "$(has_fixed 'settings.json' "$B15_SETUP")" "yes"

# --- the /statusline:setup remove entry ------------------------------------

B15_REMOVE="$(b15_entry "$B12_SKILLS" '**`/statusline:setup remove`**')"
check "the /statusline:setup remove entry is identifiable whole (scoping oracle is not empty)" \
  "$([ -n "$B15_REMOVE" ] && echo yes || echo no)" "yes"

while read -r _k; do
  [ -n "$_k" ] || continue
  check "the remove entry names $_k among the keys it cleans up" \
    "$(has_fixed "$_k" "$B15_REMOVE")" "yes"
done < "$TMP/b15-knobs"

# Scoped to the SENTENCES making a schedule-key claim: the entry's surrounding
# prose legitimately describes deleting the three statusline keys, and that
# sentence must not be what satisfies the schedule clause.
B15_RM_CLAIM="$(b17_claims "$B15_REMOVE" 'CLAM_STATUSLINE_')"
check "the remove entry makes a claim about the schedule keys at all (scoping oracle is not empty)" \
  "$([ -n "$B15_RM_CLAIM" ] && echo yes || echo no)" "yes"
check "that claim says the schedule keys are deleted too" \
  "$(has_re '(delete[sd]?|remove[sd]?|clear[sd]?|drop(s|ped)?|strip(s|ped)?)' "$B15_RM_CLAIM")" "yes"

# --- the off-switch section ------------------------------------------------

B15_OFF="$(b17_subsection '### Turn the statusline off without uninstalling')"
check "the 'Turn the statusline off without uninstalling' section is identifiable" \
  "$([ -n "$B15_OFF" ] && echo yes || echo no)" "yes"
while read -r _k; do
  [ -n "$_k" ] || continue
  check "the off-switch section names $_k among what remove takes back" \
    "$(has_fixed "$_k" "$B15_OFF")" "yes"
done < "$TMP/b15-knobs"
check "the off-switch section says the schedule keys are removed or restored" \
  "$(has_re '(delete[sd]?|remove[sd]?|restore[sd]?|clear[sd]?|drop(s|ped)?)' "$B15_OFF")" "yes"
# Non-vacuity: the section still tells the reader the command to run and still
# covers the statusline keys it has always covered.
check "the off-switch section still names the remove command" \
  "$(has_fixed '/statusline:setup remove' "$B15_OFF")" "yes"
check "the off-switch section still covers the statusLine key" \
  "$(has_fixed 'statusLine' "$B15_OFF")" "yes"

# --- the two version surfaces ----------------------------------------------

# B18 bumps both surfaces together, 0.10.0 -> 0.11.0: the docs change what an
# installed user reads about the pace colours, and version-bump-lint reads
# committed state, so an edit without the bump is invisible to them.
B18_VERSION="0.11.0"
check "plugin.json version is exactly $B18_VERSION" \
  "$PLUGIN_VERSION" "$B18_VERSION"
check "the root README row's version cell is exactly v$B18_VERSION" \
  "$ROOT_ROW_STATUS" "✅ v$B18_VERSION"

# The wording invariant, byte-for-byte and version-agnostic: field 3 (the
# version cell) is masked out of the live row and every other byte compared
# against the frozen row.
B15_ROW_MASKED="$(awk -F'|' 'BEGIN { OFS = "|" } { $3 = " <version> "; print }' <<<"$ROOT_ROW")"
check "the root README statusline row's wording is unchanged outside the version cell" \
  "$B15_ROW_MASKED" \
  "| [statusline](plugins/statusline/) | <version> | Statusline: path, branch, tracking State, model and effort, weekly and 5-hour plan limits paced to the hours you actually work, context usage. One explicit global write via \`/statusline:setup\`. |"

# ===========================================================================
# B18 pace-colour-docs
# ===========================================================================

# ---------------------------------------------------------------------------
# 37. The plan colour is retired, and the line-2 bullets agree with the
#     figures section about used% and the trend colours
# ---------------------------------------------------------------------------

# burn_plan_color goes the way burn_pet went: deleted outright, nothing in its
# place. Read off the SOURCE with comment lines blanked, because the file
# header legitimately keeps a paragraph recording the removal — that is
# documentation, not a live reference.
B18_PLAN_HITS="$(sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#[[:space:]].*$//' \
  "$BURN_THEME" | grep -c 'burn_plan_color' | tr -d ' ')"
check "burn_plan_color is gone from lib/burn-theme.sh (non-comment lines)" \
  "$B18_PLAN_HITS" "0"
# And no prose may still document the scale it had: a README naming a function
# the source no longer defines is a promise nothing keeps.
check "the plugin README documents no burn_plan_color scale any more" \
  "$(has_fixed 'burn_plan_color' "$BODY")" "no"

# The two limit bullets are where a reader meets `5h used%` and `wk used%`
# first, so they may not attach a colour to either figure — the figures section
# says both are deliberately plain, and the bullets have to agree.
check "the 5-hour bullet claims no colour for its used percentage" \
  "$(b17_near "$FIVE_B" '(^|[^A-Za-z])used' 'colou?r' 100)" "no"
check "the Weekly bullet claims no colour for its used percentage" \
  "$(b17_near "$WEEK_B" '(^|[^A-Za-z])used' 'colou?r' 100)" "no"

# And neither bullet may still name a trend tier the function retired. The
# words come from the derivation in section 17, so this follows the source.
while read -r _gone; do
  [ -n "$_gone" ] || continue
  check "the 5-hour bullet no longer names the retired $_gone trend tier" \
    "$(has_re "$(b17_word "$_gone")" "$FIVE_B")" "no"
  check "the Weekly bullet no longer names the retired $_gone trend tier" \
    "$(has_re "$(b17_word "$_gone")" "$WEEK_B")" "no"
done < "$TMP/trend-absent"

# Non-vacuity for the pair above: the Context bullet KEEPS its green, because
# burn_ctx_color still emits it. If this ever goes red, the two checks above
# have started reading a README that dropped the ctx bands with the trend's.
check "the Context bullet keeps documenting the ctx meter's green band" \
  "$(has_re "$(b17_word green)" "$CTX_B")" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
