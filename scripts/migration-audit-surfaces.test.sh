#!/bin/bash
# Test for Block B01 (audit-unmapped-surfaces). Authoritative contract: the
# HTML-comment docblock "Contract: B01 audit-unmapped-surfaces (plan
# 001-github-issue-13)" in MIGRATION.md, immediately above the three
# sections it governs:
#
#   ## Audit: clam-generic divergence
#   ## Audit: repos/clipboard overlay
#   ## Audit: unmerged clam-code branches
#
# Asserts directly on MIGRATION.md, the single file the contract names as
# B01's output. Follows the check()/PASS/FAIL/FAILED/exit shape of
# plugins/render-doc/scripts/migration.test.sh, the repo's existing
# contract-docblock test, and strips HTML comments before asserting for the
# same reason that precedent does: the B01 docblock itself quotes the exact
# heading text and marker strings ("NotImplemented: B01" among them) these
# checks look for, so without stripping, the docblock's own prose would
# satisfy a check before the real content exists.
#
# Hermetic by design: every assertion below reads only this repo's
# MIGRATION.md and (via a subprocess) this repo's own
# plugins/render-doc/scripts/migration.test.sh. Nothing here stats, greps,
# or invokes git against any source-repo worktree path — those paths are
# research inputs for the implementer, not assertable by a test that must
# also pass in CI, where they do not exist.
#
# Run: bash scripts/migration-audit-surfaces.test.sh (non-zero exit on
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

# Status vocabulary this map uses throughout (see MIGRATION.md's own
# header): the four map statuses plus the contract's explicit "unassigned"
# marker for an element that doesn't fit one of the four.
STATUS_RE='\bported\b|\bplanned\b|\bout of scope\b|\bdropped\b|\bunassigned\b'

# Section-body extractor: from the named "## " heading (exact text) up to
# (not including) the next "## " heading or EOF. Mirrors migration.test.sh's
# rd_section().
section_body() { # heading_text
  awk -v h="$1" '
    $0 == h { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$BODY"
}

section_nonempty() { # section_text
  local trimmed
  trimmed="$(grep -v '^[[:space:]]*$' <<<"$1")"
  [ -n "$trimmed" ] && [ "$(wc -c <<<"$trimmed")" -gt 20 ]
}

is_unauditable() { # section_text
  grep -qiE 'unauditable[[:space:]]*—' <<<"$1"
}

DIVERGENCE="$(section_body '## Audit: clam-generic divergence')"
CLIPBOARD="$(section_body '## Audit: repos/clipboard overlay')"
UNMERGED="$(section_body '## Audit: unmerged clam-code branches')"

# =====================================================================
# Behavior
#   "Catalog the three source surfaces ... as three new sections ... every
#   element ... carries a status. ... It records what EXISTS and what its
#   status IS; it does not recommend action (that is B03) and it does not
#   touch any pre-existing section (that is B02)."
# =====================================================================

# The three-sections-exist half of Behavior is exercised under Outputs
# below (heading-exists-exactly-once, per section). The pre-existing-
# section-untouched half is exercised under Invariants below. Here: the
# "does not recommend action (that is B03)" half — B03's own contract adds
# a literal "Recommendation" column later; B01 must not pre-empt it with
# recommending language of its own.
for pair in "divergence:$DIVERGENCE" "clipboard:$CLIPBOARD" "unmerged:$UNMERGED"; do
  name="${pair%%:*}"
  text="${pair#*:}"
  check "$name section does not recommend action (that is B03's job)" \
    "$(grep -qi 'recommend' <<<"$text" && echo present || echo absent)" "absent"
done

# =====================================================================
# Inputs
#   All four inputs are read-only absolute source-repo paths (or this
#   repo's plugins/ dir, used only to judge "ported" status — exercised
#   under Edge cases below). The paths themselves must never be touched by
#   this test suite: it must stay hermetic in CI, where none of those
#   worktrees exist. Guard the test file itself against regressing that,
#   described here without the literal path so this check can't
#   self-trigger.
# =====================================================================

FORBIDDEN_PATH_RE='/github/clam-code(-generic)?-trees'
check "this test file itself never references a source-repo worktree path (hermeticity)" \
  "$(grep -qE "$FORBIDDEN_PATH_RE" "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" && echo present || echo absent)" "absent"

# =====================================================================
# Outputs (1) — "## Audit: clam-generic divergence"
# =====================================================================

check "stripped MIGRATION.md has exactly one clam-generic divergence heading" \
  "$(grep -cE '^## Audit: clam-generic divergence$' <<<"$BODY")" "1"
check "divergence section has substantive content" \
  "$(section_nonempty "$DIVERGENCE" && echo yes || echo no)" "yes"

if is_unauditable "$DIVERGENCE"; then
  echo "PASS  divergence section content checks -> sanctioned unauditable path, content checks skipped"
else
  check "divergence section states a preferred migration source" \
    "$(grep -qi 'prefer' <<<"$DIVERGENCE" && echo yes || echo no)" "yes"
  check "divergence section names both clam-code and clam-generic" \
    "$([ "$(grep -qi 'clam-code' <<<"$DIVERGENCE" && echo 1)" = "1" ] && [ "$(grep -qi 'clam-generic' <<<"$DIVERGENCE" && echo 1)" = "1" ] && echo yes || echo no)" "yes"
  check "divergence section splits generic-only from clam-code-only" \
    "$([ "$(grep -qiE 'generic[- ]only' <<<"$DIVERGENCE" && echo 1)" = "1" ] && [ "$(grep -qiE 'clam-code[- ]only' <<<"$DIVERGENCE" && echo 1)" = "1" ] && echo yes || echo no)" "yes"
  # "plus a count of files that exist in both but differ" — the plan-time
  # figure (79) is an unverified hint, not a value to assert; only that
  # some count accompanies the word "differ".
  check "divergence section gives a count of files that differ" \
    "$([ "$(grep -q '[0-9]' <<<"$DIVERGENCE" && echo 1)" = "1" ] && [ "$(grep -qi 'differ' <<<"$DIVERGENCE" && echo 1)" = "1" ] && echo yes || echo no)" "yes"
  # Enumeration floor: "names, at minimum, every element present in one and
  # absent from the other" requires actually listing elements, not just
  # describing the delta in prose — the words "generic-only" and
  # "clam-code-only" alone satisfy the split check above without a single
  # element named. Known at plan time (an unverified hint, not a count to
  # pin): 3 generic-only elements (issue-tracker, pre-pr-verify,
  # agent-dash-permission.test.sh) and 5 clam-code-only elements
  # (absorb-package, create-jira-ticket, clipboard-helpers.*, trees-dir.*,
  # worktree-helpers.*). A floor of 4 distinct backticked elements is below
  # either known side alone, so a genuine but differently-shaped catalog
  # still passes, while a prose-only section (zero enumerated elements)
  # does not.
  DIVERGENCE_ELEMENT_COUNT="$(grep -oE '`[^`]+`' <<<"$DIVERGENCE" | sort -u | wc -l)"
  check "divergence section enumerates a minimum number of individually named elements" \
    "$([ "$DIVERGENCE_ELEMENT_COUNT" -ge 4 ] && echo yes || echo no)" "yes"
fi

# =====================================================================
# Outputs (2) — "## Audit: repos/clipboard overlay"
# =====================================================================

check "stripped MIGRATION.md has exactly one repos/clipboard overlay heading" \
  "$(grep -cE '^## Audit: repos/clipboard overlay$' <<<"$BODY")" "1"
check "clipboard section has substantive content" \
  "$(section_nonempty "$CLIPBOARD" && echo yes || echo no)" "yes"

if is_unauditable "$CLIPBOARD"; then
  echo "PASS  clipboard section content checks -> sanctioned unauditable path, content checks skipped"
else
  # Must disambiguate the two distinct things named pre-pr-verify: this
  # overlay's copy, and clam-generic's general/skills/pre-pr-verify (the
  # one the pr-workflow section above already maps). Two mentions plus a
  # reference to the other repo is the testable shape of "disambiguate".
  check "clipboard section mentions pre-pr-verify more than once (disambiguating the two)" \
    "$([ "$(grep -oi 'pre-pr-verify' <<<"$CLIPBOARD" | wc -l)" -ge 2 ] && echo yes || echo no)" "yes"
  check "clipboard section's pre-pr-verify mentions are disambiguated against clam-generic" \
    "$(grep -qi 'clam-generic' <<<"$CLIPBOARD" && echo yes || echo no)" "yes"
  check "clipboard section states repo-specific-by-nature or portable" \
    "$(grep -qiE 'repo-specific|portable' <<<"$CLIPBOARD" && echo yes || echo no)" "yes"
  # Enumeration floor: "names its skills ... verify the list" requires an
  # actual catalog, not a section that only discusses pre-pr-verify (the
  # disambiguation checks above pass on that alone). Known at plan time (an
  # unverified hint, not a count to pin): 7 skills (angular-dev, database,
  # database-migrations, monorepo-consolidation, pre-pr-verify, stricten,
  # strictening) plus rules/, git-hooks/, and lib/. A floor of 5 distinct
  # backticked elements is below the 7-skill list alone, so a genuine but
  # differently-shaped catalog still passes, while prose that names only one
  # or two things does not.
  CLIPBOARD_ELEMENT_COUNT="$(grep -oE '`[^`]+`' <<<"$CLIPBOARD" | sort -u | wc -l)"
  check "clipboard section enumerates a minimum number of individually named elements" \
    "$([ "$CLIPBOARD_ELEMENT_COUNT" -ge 5 ] && echo yes || echo no)" "yes"
  # "plus its rules/, git-hooks/, and lib/ contents" — the contract names
  # these three by name as required content. "Mentioned" is the right bar:
  # a catalog that finds one of them missing at the source still has to say
  # so, so this does not require a status on the same line the way named
  # skills/elements do.
  check "clipboard section mentions rules/" \
    "$(grep -qF 'rules/' <<<"$CLIPBOARD" && echo yes || echo no)" "yes"
  check "clipboard section mentions git-hooks/" \
    "$(grep -qF 'git-hooks/' <<<"$CLIPBOARD" && echo yes || echo no)" "yes"
  check "clipboard section mentions lib/" \
    "$(grep -qF 'lib/' <<<"$CLIPBOARD" && echo yes || echo no)" "yes"
fi

# =====================================================================
# Outputs (3) — "## Audit: unmerged clam-code branches"
# =====================================================================

check "stripped MIGRATION.md has exactly one unmerged clam-code branches heading" \
  "$(grep -cE '^## Audit: unmerged clam-code branches$' <<<"$BODY")" "1"
check "unmerged-branches section has substantive content" \
  "$(section_nonempty "$UNMERGED" && echo yes || echo no)" "yes"

if is_unauditable "$UNMERGED"; then
  echo "PASS  unmerged-branches section content checks -> sanctioned unauditable path, content checks skipped"
else
  # Edge case: a branch 0 commits ahead is still listed, verbatim as "no
  # unmerged work", so the audit is provably exhaustive over the
  # worktrees — the contract quotes this exact phrase.
  check "unmerged-branches section accounts for a 0-ahead branch as 'no unmerged work'" \
    "$(grep -qF 'no unmerged work' <<<"$UNMERGED" && echo yes || echo no)" "yes"
  check "unmerged-branches section judges branches redundant vs. distinct work" \
    "$(grep -qiE 'redundant|distinct' <<<"$UNMERGED" && echo yes || echo no)" "yes"
  # Loose exhaustiveness proxy: more than one branch entry. The real
  # worktree count is a source-repo fact this test must not assume or
  # pin (it could change), so this only checks the section enumerates
  # more than a single item rather than covering just one branch.
  check "unmerged-branches section enumerates more than one branch" \
    "$([ "$(grep -cE '^([-*]|\|)' <<<"$UNMERGED")" -ge 2 ] && echo yes || echo no)" "yes"
fi

# =====================================================================
# Errors
#   "A source path that does not exist ... record the surface as
#   'unauditable — <reason>' ... rather than omitting the section."
#   "Evidence that contradicts a plan-time claim ... record what was
#   actually observed." (the differ-count check above is deliberately
#   loose for this reason: it accepts any observed count, never the
#   plan-time 79).
# =====================================================================

check_unauditable_reason() { # label section_text
  local label="$1" section="$2" line reason
  line="$(grep -iE 'unauditable[[:space:]]*—' <<<"$section" | head -n1)"
  if [ -z "$line" ]; then
    echo "PASS  $label -> section is not in the unauditable state (n/a)"
    return
  fi
  reason="$(sed -E 's/.*unauditable[[:space:]]*—[[:space:]]*//I' <<<"$line")"
  check "$label" "$([ "${#reason}" -gt 3 ] && echo yes || echo no)" "yes"
}

check_unauditable_reason "divergence section's unauditable marker (if used) carries a reason" "$DIVERGENCE"
check_unauditable_reason "clipboard section's unauditable marker (if used) carries a reason" "$CLIPBOARD"
check_unauditable_reason "unmerged-branches section's unauditable marker (if used) carries a reason" "$UNMERGED"

# =====================================================================
# Invariants
# =====================================================================

# "The scaffold marker is gone: after this block the string
# 'NotImplemented: B01' appears nowhere in MIGRATION.md outside a contract
# docblock."
check "'NotImplemented: B01' marker is gone from the stripped body" \
  "$(grep -qF 'NotImplemented: B01' <<<"$BODY" && echo present || echo absent)" "absent"

# "plugins/render-doc/scripts/migration.test.sh stays green." Run the
# actual precedent test rather than re-deriving its assertions — it is
# this repo's own regression test for the render-doc heading and the
# Unassigned writing-cluster line, both pre-existing content B01 must
# leave alone.
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

# "No section that existed before this block runs is modified. B01 appends
# only." (`git diff` on MIGRATION.md shows insertions in this block's three
# sections and nothing else.) Spot-check anchors captured from the
# pre-B01-implementation state: total heading count is unchanged (B01's
# three headings already exist as scaffolded stubs, so implementing B01
# adds no new headings), and representative pre-existing content survives
# byte-for-byte.
#
# Deliberately NOT pinned here: the B02 stub sections' NotImplemented
# marker, the B03 register stub's NotImplemented marker, and the
# Unassigned section's phantom entries. Those are sibling blocks' scaffold
# state, which those blocks are contractually required to change — pinning
# it here would make this standing suite fail the moment the plan's own
# later work does its job. (Plan 001-github-issue-13 Amendment 1: a
# block's test must never assert a sibling block's scaffold state.) The
# no-clobber claim those checks used to stand in for was already verified
# directly at B01's acceptance gate via a diff-scope check and a docblock
# md5 comparison; the durable replacement for the phantom-entries half now
# lives as B02's own Outputs (3) assertion in
# scripts/migration-audit-reconcile.test.sh.
# Re-pinned 32 → 33 when the voice port section was added (plan
# 001-the-voice): the pin tracks the current legitimate section inventory,
# so a deliberate addition moves it and an accidental one still fails.
# Re-pinned 33 → 34 when the forge-github section was added (plan
# 001-fix-pr-line-lengths): same protocol, deliberate inventory move.
check "total '## ' heading count in MIGRATION.md is unchanged by B01" \
  "$(grep -cE '^## ' <<<"$BODY")" "34"
UNASSIGNED="$(section_body '## Unassigned — decide at port time')"
check "pre-existing Unassigned writing-cluster line is unchanged by B01" \
  "$([ "$(grep -qF 'writing-markdown' <<<"$UNASSIGNED" && echo 1)" = "1" ] && [ "$(grep -qF 'rtfm' <<<"$UNASSIGNED" && echo 1)" = "1" ] && echo yes || echo no)" "yes"
GUARD_SECTION="$(section_body '## Guard inventory')"
check "pre-existing Guard inventory table row count is unchanged by B01" \
  "$(grep -c '^|' <<<"$GUARD_SECTION")" "12"

# "Every element named in the three sections carries a status." Sections
# (1) and (2) enumerate many same-shaped elements against the map's
# ported/planned/out of scope/dropped/unassigned vocabulary; check every
# line that names a backticked element also carries one of those words on
# the same line (grouped elements sharing one trailing status on their
# line are fine — the check is per LINE, not per element). Skipped for a
# section in the sanctioned unauditable state (Errors clause), and skipped
# for section (3), whose per-branch "status" is the redundant-vs-distinct
# call already checked under Outputs (3) above, not this vocabulary.
check_elements_have_status() { # label section_text
  local label="$1" section="$2" line bad=0
  if is_unauditable "$section"; then
    echo "PASS  $label -> sanctioned unauditable path, element-status check skipped"
    return
  fi
  while IFS= read -r line; do
    [[ "$line" == *'`'*'`'* ]] || continue
    if ! grep -qiE "$STATUS_RE" <<<"$line"; then
      bad=$((bad + 1))
      echo "      element line names something but carries no status: $line"
    fi
  done <<<"$section"
  check "$label" "$bad" "0"
}

check_elements_have_status "every named element in the divergence section carries a status" "$DIVERGENCE"
check_elements_have_status "every named element in the clipboard section carries a status" "$CLIPBOARD"

# =====================================================================
# Edge cases
# =====================================================================

# "An element ... present in clam-code, clam-generic AND repos/clipboard
# under the same name: name it in each section it appears in, and
# disambiguate." The contract's own example of this is pre-pr-verify,
# already exercised under Outputs (2) above.

# "A branch 0 commits ahead ... still list it, as 'no unmerged work'" —
# exercised under Outputs (3) above.

# "A surface element already fully ported into this repo's plugins/:
# status is 'ported', with the destination plugin named." Loose
# correlation: if a section claims "ported" for something, it should also
# reference this repo's plugins/ tree somewhere as the destination.
for pair in "divergence:$DIVERGENCE" "clipboard:$CLIPBOARD"; do
  name="${pair%%:*}"
  text="${pair#*:}"
  if is_unauditable "$text"; then
    echo "PASS  $name section 'ported' names a destination plugin -> sanctioned unauditable path, skipped"
  elif grep -qiE '\bported\b' <<<"$text"; then
    check "$name section: an element marked 'ported' names a destination under plugins/" \
      "$(grep -qi 'plugins/' <<<"$text" && echo yes || echo no)" "yes"
  else
    echo "PASS  $name section 'ported' names a destination plugin -> no 'ported' element present, skipped"
  fi
done

# "Binary or generated files in a source tree: group them rather than
# enumerating, and say so." Not independently asserted: whether binaries
# exist in a given source tree is itself a source-repo fact this hermetic
# test must not depend on. By construction, the element-status check above
# only fires on lines that name an individually backticked element, so a
# grouped "N binary files (see note)" summary line without per-file
# backticks is never forced to carry a per-file status — this test does
# not forbid the grouped form.

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
