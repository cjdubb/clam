#!/bin/bash
# Contract tests for the repo-local skill .claude/skills/dispatch-issues/SKILL.md.
#
# The skill automates picking an issue off this repo's GitHub backlog and
# dispatching it to its own orchestrator worktree. Its value is not the
# mechanics (the orchestrator-handover plugin owns those) but the repo-specific
# judgement it encodes: verify the defect is still live, resolve drifted line
# numbers, detect collisions between issues, and report a pickup instruction
# that actually works here.
#
# WHY THIS SUITE EXISTS: every assertion below guards a failure this repo has
# already had. The pickup instruction is the sharpest case — the handover
# plugin's own "run clam, pick Build" text survived a documented decision to
# drop the clam alias (MIGRATION.md:568) and was relayed to the engineer
# verbatim before anyone noticed (#288). A prose skill with no test rots the
# same way. These checks are deliberately about the presence of load-bearing
# instructions, not about phrasing, so a reasonable rewrite stays green.
#
# Two properties are deliberately NOT asserted, in the same spirit as
# claude-md.test.sh's exclusions:
#   - "The triage step is actually performed" is behavioural — a skill file can
#     only be checked for instructing it, not for the agent obeying.
#   - "The collision check catches every real collision" depends on the issue
#     set, not on this file's text.
#
# Hermetic: reads only the SKILL.md at the repo root (resolved from this
# script's own path), no mutation, no network.
#
# Run: bash scripts/dispatch-issues-skill.test.sh (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/.claude/skills/dispatch-issues/SKILL.md"

if [ ! -f "$SKILL" ]; then
  echo "FATAL: dispatch-issues SKILL.md not found at $SKILL" >&2
  exit 1
fi

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

BODY="$(cat "$SKILL")"
# Flatten: the skill is hard-wrapped prose, so a phrase may cross a line break
# in the source without crossing it in the logical text.
FLAT="$(printf '%s' "$BODY" | tr '\n' ' ' | tr -s ' ')"

# assert_re <label> <ERE, case-insensitive>
assert_re() {
  if printf '%s' "$FLAT" | grep -qiE -- "$2"; then pass "$1"
  else fail "$1" "did not match regex (case-insensitive): $2"; fi
}

# refute_re <label> <ERE, case-insensitive>
refute_re() {
  if printf '%s' "$FLAT" | grep -qiE -- "$2"; then
    fail "$1" "matched a regex it must not: $2"
  else pass "$1"; fi
}

# ===========================================================================
# Frontmatter — the description is what the model matches on when deciding to
# invoke the skill, so an empty or missing one makes the skill undiscoverable.
# ===========================================================================
check "frontmatter opens the file" "$(head -n 1 "$SKILL")" "---"
check "name field is the directory name" \
  "$(grep -m1 '^name:' "$SKILL")" "name: dispatch-issues"
desc_len=$(grep -m1 '^description:' "$SKILL" | wc -c)
if [ "${desc_len:-0}" -gt 80 ]; then pass "description is substantive (>80 chars)"
else fail "description is substantive (>80 chars)" "got $desc_len chars"; fi
assert_re "description names the triggering intent (backlog / issues)" \
  '^-{3}.*description:.*(backlog|issue)'

# ===========================================================================
# Repo-local placement — the skill must justify why it is NOT a plugin, or the
# next person to tidy up will "promote" it into plugins/ and trip
# architecture-lint (or worse, pass lint while violating the layering rule).
# ===========================================================================
assert_re "states it is repo-local on purpose" 'repo-local'
assert_re "explains the layering reason it cannot be a plugin" \
  '(layering|CLAUDE\.md|architecture-lint)'
assert_re "warns against promoting it into a plugin" \
  '(not promote|do not promote|never.{0,20}promote)'

# ===========================================================================
# Step 0 — scope gate. Dispatching an unbounded batch creates worktrees the
# engineer will never open; the count is theirs to set.
# ===========================================================================
assert_re "asks the engineer for a batch size before dispatching" \
  '(how many|batch size)'
assert_re "offers a bare-go default (ask-in-text convention)" \
  '(bare .go.|accepts all)'

# ===========================================================================
# Step 2 — staleness triage. THE load-bearing step: a handover for an
# already-fixed bug costs a whole session to discover nothing is wrong.
# Three of roughly a dozen checked on 2026-08-05 were already fixed.
# ===========================================================================
assert_re "makes the still-live check mandatory" \
  '(never dispatch.{0,60}without|mandatory)'
assert_re "cites the observed stale-issue rate or examples" '#77|#99|#121'
assert_re "warns that cited line numbers drift" \
  '(line numbers?.{0,40}drift|drift.{0,40}line)'
assert_re "tells the recipient handover to carry the corrected line" \
  'current line'
assert_re "routes triage findings into FOLLOWUPS.md" 'FOLLOWUPS\.md'
assert_re "checks for duplicates" 'duplicate'
assert_re "checks for mislabelled feature requests" \
  '(feature request|mislabel)'

# ===========================================================================
# Step 3 — collision detection. #268 and #219 were shipped as parallel
# worktrees while both rewrote the same deliver function.
# ===========================================================================
assert_re "detects collisions before scaffolding" \
  'collision'
assert_re "cites the #268/#219 collision precedent" '#268|#219'
assert_re "offers sequence-or-fold as the resolution" \
  '(sequence|fold)'
assert_re "requires the collision be named in BOTH handovers" 'both'

# ===========================================================================
# Step 4 — the repo's branch-naming override. The handover plugin defaults to
# orchestrate/{ISSUE-KEY}-..., which is not what this repo uses.
# ===========================================================================
assert_re "specifies the repo's branch-name format" \
  'orchestrate/github-issue-'
assert_re "flags that this overrides the handover skill's default" 'override'
assert_re "requires a version-bump line in every handover" 'version-bump-lint'
assert_re "explains the committed-state trap that makes bumps vacuous" \
  '(committed|vacuous)'

# ===========================================================================
# Step 5 — newtree is a shell function, not a PATH binary. Every worktree
# creation fails with "command not found" if this is not carried.
# ===========================================================================
assert_re "warns newtree is not on PATH" \
  'newtree.{0,40}not.{0,20}(on )?PATH|not on PATH'
assert_re "says to source the helpers from the bashrc managed block" \
  'GIT-HELPERS|worktree-helpers'
assert_re "verifies the recipient .local/ has all four artifacts" \
  'MODE.*orchestrator|orchestrator.*MODE'

# ===========================================================================
# Step 6 — the pickup instruction. This is the #288 regression guard: the
# skill must NOT tell the engineer to run `clam`, because no such command
# exists in this repo.
# ===========================================================================
# The skill legitimately MENTIONS `clam` — it has to, in order to warn against
# it. So a blanket refute is wrong: it fires on the warning itself. Instead,
# require every sentence mentioning clam-the-command to carry a negation or
# warning marker. An instruction to actually run it would have none, and fails.
# `clam-code`, `@clam`, `clam-profile`, `clam-setup-stamps` are different tokens
# (the upstream repo, the marketplace id, and two filenames) and are not matched.
mapfile -t CLAM_SENTENCES < <(
  printf '%s' "$FLAT" | sed 's/\. /.\n/g' \
    | grep -iE '(^|[^-a-z@])`?clam`?([^-a-z]|$)'
)
NEGATED='not|never|no such|nonexistent|wrong|dropped|filed as|instead of'
unguarded=0
for s in "${CLAM_SENTENCES[@]}"; do
  printf '%s' "$s" | grep -qiE -- "$NEGATED" || { unguarded=$((unguarded + 1)); echo "    unguarded: $s"; }
done
check "every mention of the clam command sits in a warning context" "$unguarded" "0"
# And the warning must exist at all — a skill that simply never says the word
# would pass the loop above vacuously.
if [ "${#CLAM_SENTENCES[@]}" -gt 0 ]; then pass "the clam pitfall is called out explicitly"
else fail "the clam pitfall is called out explicitly" "no mention found; the #288 trap is undocumented"; fi
assert_re "names #288 so the reason is traceable" '#288'
assert_re "gives the working pickup instruction instead" \
  'cd <?worktree>? && claude|&& claude'
assert_re "points the new session at .local/TODO.md" 'TODO\.md'
assert_re "requires reporting what was NOT dispatched" \
  '(not dispatch|deliberately did not|stale issues, mislabels)'

# ===========================================================================
# Inherited invariant — the handover skill forbids delegating its scaffolding
# to a subagent; this skill wraps it and must carry the same rule.
# ===========================================================================
assert_re "forbids delegating steps to a subagent" \
  '(not delegate|no subagent|never delegate)'

echo
if [ "$FAILED" -ne 0 ]; then
  echo "dispatch-issues-skill.test.sh: FAILURES"
  exit 1
fi
echo "dispatch-issues-skill.test.sh: all checks passed"
