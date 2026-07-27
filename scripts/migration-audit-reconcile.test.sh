#!/bin/bash
# Test for Block B02 (audit-reconcile-claims). Authoritative contract: the
# HTML-comment docblock "Contract: B02 audit-reconcile-claims (plan
# 001-github-issue-13)" in MIGRATION.md, immediately above its four
# scaffolded placeholder sections:
#
#   ## ask-in-text — TBD
#   ## debugging — TBD
#   ## session-data — TBD
#   ## updates — TBD
#
# but whose Outputs (1) and (4) reach back over every section that predates
# plan 001 — everything from "## lego" through "## agent-dash", plus
# "## attribution" / "## settings" / "## privacy" below the B02 stubs, plus
# the file's opening header paragraph. B01's three "## Audit:" sections and
# B03's "## Migration candidate register" stub are explicitly NOT B02's to
# touch (contract Invariants).
#
# Follows the check()/PASS/FAIL/FAILED/exit shape of
# plugins/render-doc/scripts/migration.test.sh and
# scripts/migration-audit-surfaces.test.sh (B01's, accepted and merged), and
# strips HTML comments before asserting for the same reason both precedents
# do: the B02 docblock itself quotes the exact heading text, plugin names,
# and marker strings ("NotImplemented: B02" among them) these checks look
# for, so without stripping, the docblock's own prose would satisfy a check
# before the real content exists.
#
# Hermetic by design: every assertion below reads only this repo's
# MIGRATION.md, this repo's plugins/ directory listing, and (via subprocess)
# this repo's own migration.test.sh / migration-audit-surfaces.test.sh.
# Nothing here stats, greps, or invokes git against any source-repo worktree
# path — those paths are research inputs for the implementer, not
# assertable by a test that must also pass in CI, where they do not exist.
#
# Discrimination self-tests: a regex or derivation helper whose target
# content does not exist ANYWHERE in the repo yet can fail red for the
# wrong reason — "always false" looks identical to "correctly false" in a
# single run (this plan's own U01 hit exactly this: two checks used a
# pattern that matched nothing, ever). Below, each such helper is proven
# against content that satisfies its clause before being trusted:
#   - Where the pattern's positive case already exists somewhere ELSE in
#     today's real file (e.g. other sections already use the "ported
#     (from X)" / "new (not a port)" status vocabulary; other prose already
#     carries a YYYY-MM-DD date), it is proven against that real content —
#     stronger evidence than a fixture, and free.
#   - Where no real positive case exists yet (e.g. "unverified — <reason>",
#     which nothing in today's file uses), it is proven against a synthetic
#     string, never by modifying anything outside this test file's realm.
#   - For plain fixed-string presence/absence checks (grep -qF), today's red
#     run itself is the positive-match proof: e.g. "support-fix" genuinely
#     exists in the file right now, so this run's FAIL — reporting it
#     "present" — demonstrates the pattern can detect a true positive; it is
#     not silently reporting "absent" no matter what.
#
# Run: bash scripts/migration-audit-reconcile.test.sh (non-zero exit on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# Every check below reads $BODY: MIGRATION.md with all contract docblocks
# stripped out, so a docblock's own prose (which necessarily quotes the
# strings this test looks for) can never satisfy a check meant for real
# content.
BODY="$(sed '/<!--/,/-->/d' "$MIGRATION" 2>/dev/null)"

# Section-body extractor: from a "## " heading matched by exact text, up to
# (not including) the next "## " heading or EOF. Mirrors migration.test.sh's
# rd_section() / migration-audit-surfaces.test.sh's section_body().
section_body() { # exact_heading_text
  awk -v h="$1" '
    $0 == h { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$BODY"
}

# Variant keyed on just the plugin NAME, tolerant of whatever status text
# follows "## <name> — " (that text is exactly what B02 rewrites, so the
# four new sections cannot be located by exact heading text the way
# section_body() locates stable, already-worded headings).
section_body_by_name() { # plugin_name
  awk -v pat="^## $1 — " '
    $0 ~ pat { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$BODY"
}

section_nonempty() { # section_text
  local trimmed
  trimmed="$(grep -v '^[[:space:]]*$' <<<"$1")"
  [ -n "$trimmed" ] && [ "$(wc -c <<<"$trimmed")" -gt 20 ]
}

# =====================================================================
# Behavior / Inputs
#   "Read-only against the sources, exactly as B01. Writes ONLY
#   MIGRATION.md." / "The same read-only source paths B01 uses."
#   Hermeticity: this test file itself must never reference a source-repo
#   worktree path, so it stays runnable in CI, where those paths do not
#   exist. Same guard, same rationale, as B01's test.
# =====================================================================

FORBIDDEN_PATH_RE='/github/clam-code(-generic)?-trees'
check "this test file itself never references a source-repo worktree path (hermeticity)" \
  "$(grep -qE "$FORBIDDEN_PATH_RE" "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" && echo present || echo absent)" "absent"

# "This repo: plugins/*, .claude-plugin/marketplace.json." — the two
# in-repo inputs B02 also reads from, alongside MIGRATION.md itself.
check "plugins/ directory exists and is readable" \
  "$([ -d "$ROOT/plugins" ] && echo yes || echo no)" "yes"
check ".claude-plugin/marketplace.json exists and is readable" \
  "$([ -f "$ROOT/.claude-plugin/marketplace.json" ] && echo yes || echo no)" "yes"

# =====================================================================
# Outputs (2) — every plugins/ directory has exactly one "## <name> — "
# section. The most mechanically checkable clause in the block. The plugin
# list is derived from the filesystem at runtime (never hardcoded) so this
# keeps working as plugins are added; plugins/ also holds a stray
# PLUGIN_README_TEMPLATE.md file (not a plugin), which the "-type d" filter
# below must exclude.
# =====================================================================

plugin_dirs_under() { # root_plugins_dir
  find "$1" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

# Discrimination self-test for the derivation helper itself, using a
# synthetic /tmp tree (never touching this repo's plugins/): two real
# directories must be found, and a stray file sitting alongside them must
# not be mistaken for one.
TMP_PLUGDIR="$(mktemp -d)"
mkdir -p "$TMP_PLUGDIR/alpha" "$TMP_PLUGDIR/beta"
: > "$TMP_PLUGDIR/STRAY_FILE.md"
SYN_PLUGIN_DIRS="$(plugin_dirs_under "$TMP_PLUGDIR")"
check "plugin_dirs_under helper: finds synthetic directories (positive, synthetic)" \
  "$([ "$(grep -qx 'alpha' <<<"$SYN_PLUGIN_DIRS" && echo 1)" = "1" ] && [ "$(grep -qx 'beta' <<<"$SYN_PLUGIN_DIRS" && echo 1)" = "1" ] && echo yes || echo no)" "yes"
check "plugin_dirs_under helper: excludes a stray file sitting in the same dir (negative, synthetic)" \
  "$(grep -qx 'STRAY_FILE.md' <<<"$SYN_PLUGIN_DIRS" && echo present || echo absent)" "absent"
rm -rf "$TMP_PLUGDIR"

PLUGIN_DIRS="$(plugin_dirs_under "$ROOT/plugins")"
check "real plugins/ listing excludes PLUGIN_README_TEMPLATE.md (the stray file, not a plugin)" \
  "$(grep -qx 'PLUGIN_README_TEMPLATE.md' <<<"$PLUGIN_DIRS" && echo present || echo absent)" "absent"
check "real plugins/ listing is non-empty" \
  "$([ -n "$PLUGIN_DIRS" ] && echo yes || echo no)" "yes"

# Count a name's *real* sections: a "## <name> — TBD" heading is a
# scaffolded placeholder, not a completed section, so it must NOT count as
# one. A naive "^## <name> — " prefix match would count it anyway (TBD text
# follows the same "— "), which would make the missing-section check below
# silently pass today, before B02 has done anything — exactly the
# always-true-independent-of-content failure mode this unit was warned
# about. Subtracting the TBD count is what makes this discriminate.
real_section_count() { # plugin_name body_text
  local name="$1" body="$2" total tbd
  total="$(grep -cE "^## ${name} — " <<<"$body")"
  tbd="$(grep -cE "^## ${name} — TBD$" <<<"$body")"
  echo $((total - tbd))
}

# Discrimination self-test for real_section_count, both directions, both
# synthetic. The negative direction used to read today's live "## ask-in-
# text — TBD" heading out of $BODY, but that pins state B02 is
# contractually required to change (this block's own Outputs (2) removes
# the TBD marker), which breaks the moment B02 does its job — the same
# sibling/self-scaffold-state trap named in plan 001-github-issue-13
# Amendment 1. A synthetic TBD string proves the same subtraction fires
# without depending on live content:
#   negative — a TBD heading (synthetic) must count as zero real sections
#     (proves the TBD-subtraction actually fires).
#   positive — a completed heading (synthetic, since no plugin has one yet)
#     must count as one.
check "real_section_count self-test: a TBD heading counts as zero real sections (negative, synthetic)" \
  "$(real_section_count "ask-in-text" '## ask-in-text — TBD')" "0"
check "real_section_count self-test: a completed heading counts as one real section (positive, synthetic)" \
  "$(real_section_count "ask-in-text" '## ask-in-text — ported (from clam-code)')" "1"

MISSING=0; DUP=0
MISSING_LIST=""; DUP_LIST=""
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  cnt="$(real_section_count "$dir" "$BODY")"
  if [ "$cnt" -eq 0 ]; then
    MISSING=$((MISSING + 1)); MISSING_LIST="$MISSING_LIST $dir"
  elif [ "$cnt" -gt 1 ]; then
    DUP=$((DUP + 1)); DUP_LIST="$DUP_LIST $dir"
  fi
done <<<"$PLUGIN_DIRS"

check "every plugins/ directory has at least one completed '## <name> — ' section" "$MISSING" "0"
[ "$MISSING" -gt 0 ] && echo "      missing (still TBD or absent):$MISSING_LIST"
check "no plugins/ directory has more than one '## <name> — ' section" "$DUP" "0"
[ "$DUP" -gt 0 ] && echo "      duplicated:$DUP_LIST"

# =====================================================================
# Outputs (2) edge case — the four new sections' status must use the
# sanctioned vocabulary: "ported (from X)" (a source ancestor exists) or
# "new (not a port)" (born in this repo) — the contract's own two examples,
# and the exact two outcomes its Edge cases clause names. This tests the
# SHAPE the audit's conclusion must take, not which of the two is correct
# for any given plugin (that is the implementer's research, not this
# test's to assert).
# =====================================================================

STATUS_VOCAB_RE='ported \(from [A-Za-z0-9_./ -]+\)|new \(not a port\)'
status_matches_vocab() { # heading_line
  grep -qE "^## [A-Za-z0-9_-]+ — (${STATUS_VOCAB_RE})" <<<"$1"
}

# Discrimination self-test using REAL content that already exists elsewhere
# in the file today (stronger evidence than a fixture): other sections
# already use both forms of the vocabulary, and today's TBD headings must
# not match either.
REAL_PORTED_FROM_HEADING="$(grep -E '^## tracking — ported \(from' <<<"$BODY" | head -n1)"
REAL_NEW_NOT_A_PORT_HEADING="$(grep -E '^## landing — new \(not a port\)$' <<<"$BODY" | head -n1)"
check "status-vocab self-test: found a real 'ported (from X)' heading to test against (tracking)" \
  "$([ -n "$REAL_PORTED_FROM_HEADING" ] && echo yes || echo no)" "yes"
check "status-vocab self-test: found a real 'new (not a port)' heading to test against (landing)" \
  "$([ -n "$REAL_NEW_NOT_A_PORT_HEADING" ] && echo yes || echo no)" "yes"
check "status-vocab helper: real 'ported (from X)' heading matches (positive, real content)" \
  "$(status_matches_vocab "$REAL_PORTED_FROM_HEADING" && echo yes || echo no)" "yes"
check "status-vocab helper: real 'new (not a port)' heading matches (positive, real content)" \
  "$(status_matches_vocab "$REAL_NEW_NOT_A_PORT_HEADING" && echo yes || echo no)" "yes"
check "status-vocab helper: today's TBD heading does not match (negative, real content)" \
  "$(status_matches_vocab '## ask-in-text — TBD' && echo yes || echo no)" "no"

for name in ask-in-text debugging session-data updates; do
  heading_line="$(grep -E "^## ${name} — " <<<"$BODY" | head -n1)"
  check "$name section heading uses the sanctioned status vocabulary (ported (from X) or new (not a port))" \
    "$(status_matches_vocab "$heading_line" && echo yes || echo no)" "yes"
  check "$name section has substantive content" \
    "$(section_nonempty "$(section_body_by_name "$name")" && echo yes || echo no)" "yes"
done

# =====================================================================
# Outputs (1) — verified statuses, shape-level.
#   "For every element the map claims is ported ... planned ... dropped or
#   out of scope, confirm ... Correct any status that does not survive
#   checking." This test cannot know which conclusions are correct (that is
#   the implementer's research); it can assert that no pre-existing
#   status-bearing section is deleted or emptied out by the reconciliation.
#   Covers the sections that predate plan 001 and are NOT plugin
#   directories yet (still "planned", so Outputs (2) above never checks
#   them): pr-workflow, session-modes, team-review, permissions, git-guard,
#   cron-guard, agent-dash.
# =====================================================================

for name in pr-workflow session-modes team-review permissions git-guard cron-guard agent-dash; do
  check "pre-existing '$name' section heading survives (still exactly one)" \
    "$(real_section_count "$name" "$BODY")" "1"
done

# The Guard inventory table: "it is a claim set like any other and is in
# scope for verification" (Edge cases). B02 may correct a row's Status
# column but is not licensed to add or remove guard rows — that is a
# structural fact independent of the audit's findings. Row count (header +
# separator + one per guard) is the assertable floor; the Status values
# themselves are the audit's conclusions and not pinned here.
GUARD_SECTION="$(section_body '## Guard inventory')"
check "Guard inventory table row count is unchanged by B02 (verification corrects statuses, not row count)" \
  "$(grep -c '^|' <<<"$GUARD_SECTION")" "12"

# =====================================================================
# Outputs (3) — the phantom entries "support-fix" and "support-triage" are
# removed everywhere outside a contract docblock. Plain fixed-string
# checks: today's red run itself (both strings genuinely present today, so
# each check reports "present" -> FAIL, exactly as expected pre-B02) is the
# positive-match proof these patterns are not silently always-absent.
# =====================================================================

check "'support-fix' string is gone from stripped MIGRATION.md" \
  "$(grep -qF 'support-fix' <<<"$BODY" && echo present || echo absent)" "absent"
check "'support-triage' string is gone from stripped MIGRATION.md" \
  "$(grep -qF 'support-triage' <<<"$BODY" && echo present || echo absent)" "absent"

# =====================================================================
# Outputs (4) — an honest header: the opening paragraph's "best-effort"
# hook-assignment disclaimer is rewritten once assignments are verified,
# now mentions clam-generic as a source surface, and carries the audit
# date.
# =====================================================================

HEADER="$(awk '/^## /{exit} {print}' <<<"$BODY")"
check "header paragraph is non-empty" \
  "$([ -n "$HEADER" ] && echo yes || echo no)" "yes"
check "header no longer disclaims hook assignments as 'best-effort'" \
  "$(grep -qi 'best-effort' <<<"$HEADER" && echo present || echo absent)" "absent"
check "header names clam-generic as a source surface" \
  "$(grep -qi 'clam-generic' <<<"$HEADER" && echo yes || echo no)" "yes"
check "header carries an audit date (YYYY-MM-DD)" \
  "$(grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$HEADER" && echo yes || echo no)" "yes"

# Discrimination self-test for the date regex, using real dated prose that
# already exists elsewhere in today's file (the landing section's "born
# 2026-07-20") rather than a fixture. The negative direction is already
# demonstrated above: today's header genuinely carries no date yet, and the
# check above genuinely reports "no" (FAIL, right-reason red) for it.
REAL_DATED_LINE="$(grep -F 'born 2026-07-20' <<<"$BODY")"
check "date-regex self-test: found real dated prose to test against (landing section)" \
  "$([ -n "$REAL_DATED_LINE" ] && echo yes || echo no)" "yes"
check "date-regex helper: matches real dated prose elsewhere in the file (positive, real content)" \
  "$(grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$REAL_DATED_LINE" && echo yes || echo no)" "yes"

# =====================================================================
# Errors
#   "A claim that cannot be checked ... mark the element 'unverified —
#   <reason>' rather than silently leaving a status that has not been
#   earned." This is a contract-sanctioned outcome, not a forbidden one:
#   the test below does not fail merely because "unverified" appears; it
#   only requires that, if used, a real reason follows. Nothing in today's
#   file uses this marker yet, so both directions are proven with synthetic
#   strings.
#
#   ("A claim wrong in a way that suggests the plan's decomposition is
#   wrong ... escalate to the orchestrator" is a process rule for the
#   implementer, not a file-content assertion — not independently
#   testable here, same treatment B01's test gives the analogous half of
#   its own Behavior clause.)
# =====================================================================

check_unverified_reason() { # section_text
  local section="$1" line reason
  line="$(grep -iE 'unverified[[:space:]]*—' <<<"$section" | head -n1)"
  if [ -z "$line" ]; then
    echo "n/a"
    return
  fi
  reason="$(sed -E 's/.*unverified[[:space:]]*—[[:space:]]*//I' <<<"$line")"
  [ "${#reason}" -gt 3 ] && echo "yes" || echo "no"
}

# Discrimination self-test, both directions, synthetic (no real analog
# exists yet):
check "check_unverified_reason self-test: a real reason after the marker passes (positive, synthetic)" \
  "$(check_unverified_reason 'some-skill — unverified — source repo no longer exists')" "yes"
check "check_unverified_reason self-test: an empty reason after the marker fails (negative, synthetic)" \
  "$(check_unverified_reason 'some-skill — unverified —')" "no"
check "check_unverified_reason self-test: no marker at all is not-applicable, not a failure (synthetic)" \
  "$(check_unverified_reason 'some-skill — ported (from clam-code)')" "n/a"

UNVERIFIED_RESULT="$(check_unverified_reason "$BODY")"
if [ "$UNVERIFIED_RESULT" = "n/a" ]; then
  echo "PASS  MIGRATION.md's 'unverified' marker (if used) carries a real reason -> not used, n/a"
else
  check "MIGRATION.md's 'unverified' marker (if used) carries a real reason" "$UNVERIFIED_RESULT" "yes"
fi

# =====================================================================
# Invariants
# =====================================================================

# "plugins/render-doc/scripts/migration.test.sh stays green." Run the
# actual precedent test rather than re-deriving its assertions, exactly as
# B01's test does.
RENDER_DOC_TEST="$ROOT/plugins/render-doc/scripts/migration.test.sh"
if [ -f "$RENDER_DOC_TEST" ]; then
  if bash "$RENDER_DOC_TEST" >/dev/null 2>&1; then
    check "plugins/render-doc/scripts/migration.test.sh stays green" "yes" "yes"
  else
    check "plugins/render-doc/scripts/migration.test.sh stays green" "no" "yes"
  fi
else
  check "plugins/render-doc/scripts/migration.test.sh exists to be run" "no" "yes"
fi

# "B01's three 'Audit:' sections are not modified by this block." Run B01's
# own test as a subprocess rather than re-deriving its (considerably
# deeper) assertions on those three sections' content — the same
# run-the-precedent-as-a-subprocess call the brief for this unit points at.
# Any B02 corruption of the three Audit sections is very likely to also
# break B01's own heading/content/disambiguation checks.
B01_TEST="$ROOT/scripts/migration-audit-surfaces.test.sh"
if [ -f "$B01_TEST" ]; then
  if bash "$B01_TEST" >/dev/null 2>&1; then
    check "scripts/migration-audit-surfaces.test.sh (B01's) stays green (B01's sections untouched)" "yes" "yes"
  else
    check "scripts/migration-audit-surfaces.test.sh (B01's) stays green (B01's sections untouched)" "no" "yes"
  fi
else
  check "scripts/migration-audit-surfaces.test.sh (B01's) exists to be run" "no" "yes"
fi

# "The scaffold markers are gone: after this block no '## ' heading ends in
# '— TBD', and the string 'NotImplemented: B02' appears nowhere in
# MIGRATION.md outside a contract docblock."
TBD_COUNT="$(grep -cE '^## .*— TBD$' <<<"$BODY")"
check "no '## ' heading ends in '— TBD'" "$TBD_COUNT" "0"

check "'NotImplemented: B02' marker is gone from the stripped body" \
  "$(grep -qF 'NotImplemented: B02' <<<"$BODY" && echo present || echo absent)" "absent"

# B03's register stub is not B02's to touch. Only the heading is pinned
# here: B03's contract fills the section's content but does not rename the
# heading, so "exists exactly once" is a stable invariant. Its
# NotImplemented marker and its still-empty table are NOT pinned — those
# are B03's own scaffold state, which B03 is contractually required to
# change (add the candidate table, remove the marker), so asserting they
# stay put here would be the same sibling-scaffold-state trap this unit's
# own self-test above was just fixed for (plan 001-github-issue-13
# Amendment 1).
check "B03's 'Migration candidate register' heading still exists exactly once (untouched by B02)" \
  "$(grep -cE '^## Migration candidate register$' <<<"$BODY")" "1"

# "No writes anywhere outside this repo." Not independently assertable by
# a content check (it is a process property of the implementation, not of
# MIGRATION.md's text); the closest testable proxy is this test file's own
# hermeticity guard above, and mechanically, realm-check.sh restricting
# this unit to test-family files and the implementation unit to
# MIGRATION.md alone.

# =====================================================================
# Edge cases
# =====================================================================

# "A plugin here with no source ancestor at all: the correct status is
# 'new (not a port)', following the landing and deliver sections'
# precedent — not 'ported'." Exercised above: the four-section vocabulary
# check requires each new section's status to be exactly "ported (from X)"
# or "new (not a port)" — it cannot pass with a bare "ported" (no source
# named) for a plugin with no ancestor, because the vocabulary regex
# requires the parenthetical in both branches.

# "An element the map lists once but which exists in both source repos in
# differing form: keep one row, and cross-reference B01's divergence
# section rather than duplicating its detail." Not independently
# assertable: whether any such element actually exists is itself a finding
# of the audit (this test must not assume one does, per the "test the
# contract's clauses, not the audit's conclusions" instruction), and the
# resolution ("cross-reference" vs. "duplicate") is a prose judgment call
# with no fixed shape to grep for.

# "A section whose every claim already checks out: leave it byte-identical
# ... rewriting correct prose is churn." Also not independently assertable
# a priori — this test cannot know in advance which sections will turn out
# fully correct, so it cannot pin any specific section's bytes as the
# "should be unchanged" baseline without assuming the audit's conclusion
# for that section. (Contrast with B01's three Audit sections above,
# pinned via the subprocess call to B01's own test, and B03's register
# heading above, pinned as present — though not its content, which is
# B03's own scaffold state to change, not B02's to freeze — because their
# being untouched by B02 is itself the contract's Invariant, not a finding
# B02 might legitimately reach either way.)

# "The Guard inventory table: it is a claim set like any other and is in
# scope for verification." Exercised under Outputs (1) above (row-count
# floor, statuses left unpinned).

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
