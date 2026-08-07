#!/bin/bash
# Structural test for the forge-github address-pr-feedback skill
# (plugins/forge-github/skills/address-pr-feedback/SKILL.md) and its
# comment-fetching helper (plugins/forge-github/scripts/pr-comments.sh).
# The skill body is prose instructions, not executable code, so this test
# checks for the presence of the workflow's load-bearing clauses (the
# approval gate, the existing-vs-new-reviewer distinction, the CI-green
# precondition, the presentation-only triage step), not exact wording.
#
# Content checks run against the file with its YAML frontmatter stripped,
# same rationale as sync-pr.test.sh: the frontmatter description already
# contains some required words, so leaving it in could satisfy a check for
# the wrong reason.
# Run: bash plugins/forge-github/scripts/address-pr-feedback.test.sh (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$PLUGIN_DIR/skills/address-pr-feedback/SKILL.md"
FETCHER="$PLUGIN_DIR/scripts/pr-comments.sh"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

strip_frontmatter() { # file -> body with the leading YAML frontmatter removed
  awk '
    NR==1 && $0=="---" {infm=1; next}
    infm && $0=="---" {infm=0; next}
    infm {next}
    {print}
  ' "$1" 2>/dev/null
}

flatten() { printf '%s' "$1" | tr '\n' ' ' | tr -s ' '; }
has_pattern_ci() { # body extended-regex
  printf '%s' "$(flatten "$1")" | grep -qiE -- "$2" && echo yes || echo no
}

# ---------------------------------------------------------------------------
# SKILL.md -- frontmatter
# ---------------------------------------------------------------------------

check "SKILL.md exists" "$([[ -f "$SKILL" ]] && echo yes || echo no)" "yes"
check "frontmatter name is address-pr-feedback" \
  "$(awk '/^name:/{print $2; exit}' "$SKILL" 2>/dev/null)" "address-pr-feedback"
check "frontmatter has a non-empty description" \
  "$(awk '/^description:/{found=1} END{print (found ? "yes" : "no")}' "$SKILL" 2>/dev/null)" "yes"

BODY="$(strip_frontmatter "$SKILL")"

# ---------------------------------------------------------------------------
# SKILL.md -- workflow clauses
# ---------------------------------------------------------------------------

check "invokes the pr-comments.sh helper via CLAUDE_PLUGIN_ROOT" \
  "$(has_pattern_ci "$BODY" 'CLAUDE_PLUGIN_ROOT.*pr-comments\.sh')" "yes"
check "triages by the script's severity field" \
  "$(has_pattern_ci "$BODY" 'severity')" "yes"
check "triage step is presentation only (no changes yet)" \
  "$(has_pattern_ci "$BODY" 'presentation only')" "yes"
check "has the approval hard stop" \
  "$(has_pattern_ci "$BODY" 'hard stop')" "yes"
check "gate promises no changes or comments before approval" \
  "$(has_pattern_ci "$BODY" 'NOT make any code changes or post any PR comments until you approve')" "yes"
check "executes only approved changes" \
  "$(has_pattern_ci "$BODY" 'only what the user approved')" "yes"
check "documents offline-discussion recording on the PR" \
  "$(has_pattern_ci "$BODY" 'outside the PR|offline')" "yes"
check "delegates description sync to the sibling sync-pr skill" \
  "$(has_pattern_ci "$BODY" '/forge-github:sync-pr')" "yes"
check "distinguishes existing-reviewer re-request from new-reviewer assignment" \
  "$(has_pattern_ci "$BODY" 'requested_reviewers')" "yes"
check "new-reviewer assignment is user-gated" \
  "$(has_pattern_ci "$BODY" 'add-reviewer')" "yes"
check "has the CI-green precondition" \
  "$(has_pattern_ci "$BODY" 'CI.green')" "yes"
check "records the on-green action in .local/TODO.md" \
  "$(has_pattern_ci "$BODY" 'On CI green:')" "yes"

# ---------------------------------------------------------------------------
# SKILL.md -- layering invariants (leaf: no sibling/composite references)
# ---------------------------------------------------------------------------

# The forbidden names are spelled with a bracketed first letter so this
# test file itself contains no english reference to any sibling plugin
# (the architecture lint greps for the literal names).
FORBIDDEN='[l]anding plugin|[l]ego plugin|[t]racking plugin|[b]uild plugin|[w]orktrees plugin|/[l]anding:|/[l]ego:|/[t]racking:|/[w]orktrees:|@[c]lam'
check "no sibling or composite plugin named" \
  "$(printf '%s' "$BODY" | grep -qiE "$FORBIDDEN" && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# pr-comments.sh -- helper script sanity
# ---------------------------------------------------------------------------

check "pr-comments.sh exists" "$([[ -f "$FETCHER" ]] && echo yes || echo no)" "yes"
check "pr-comments.sh is executable" "$([[ -x "$FETCHER" ]] && echo yes || echo no)" "yes"
check "pr-comments.sh passes bash -n" \
  "$(bash -n "$FETCHER" 2>/dev/null && echo yes || echo no)" "yes"

usage_out="$("$FETCHER" 2>&1)"
usage_rc=$?
check "pr-comments.sh with no args exits non-zero" \
  "$([[ "$usage_rc" -ne 0 ]] && echo yes || echo no)" "yes"
check "pr-comments.sh with no args prints usage" \
  "$(printf '%s' "$usage_out" | grep -q 'Usage:' && echo yes || echo no)" "yes"

unknown_out="$("$FETCHER" --bogus 2>&1)"
unknown_rc=$?
check "pr-comments.sh rejects unknown flags" \
  "$([[ "$unknown_rc" -ne 0 ]] && echo yes || echo no)" "yes"
check "pr-comments.sh names the unknown flag" \
  "$(printf '%s' "$unknown_out" | grep -q 'Unknown flag: --bogus' && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
