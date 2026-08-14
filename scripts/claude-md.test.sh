#!/bin/bash
# Contract tests for B02 claude-md-rework (plan
# 001-ensure-agents-understand-architecture): the "Contract: B02
# claude-md-rework" HTML-comment docblock near the top of CLAUDE.md is the
# source of truth. The deliverable under test is CLAUDE.md itself, a prose
# block — the implementation wave writes the reworked prose and deletes the
# contract comment.
#
# CRITICAL: the contract comment contains the very phrases these tests must
# assert, including the two-sentence rule verbatim, so a naive grep against
# the raw file would go green against the unimplemented stub for the wrong
# reason. Every content assertion below strips the comment block first (via
# the same sed range the brief specifies) and asserts against the stripped
# document only. The lone exception is the "contract comment is gone" check,
# which by definition must read the raw file. The strip range deletes
# nothing once the comment is actually gone (post-acceptance), so it is
# correct against both the stub and the finished file.
#
# Two contract facts are deliberately NOT asserted here, same spirit as
# followups-template.test.sh's exclusions:
#   - Invariant "no rule stated here that ARCHITECTURE.md does not state
#     normatively" is a cross-document authorship judgement (this suite
#     reads only CLAUDE.md) — not a property this file's own text can prove
#     or disprove by itself. Left to orchestrator/reviewer judgement.
#   - Behavior clause 6's "every other plugin is a leaf" is checked only as
#     bare keyword presence, not proximity to the diagram: "leaf" is
#     virtually certain to appear (it is also the layering rule's own term),
#     and a tighter proximity regex would risk failing on a reasonable
#     rephrasing for no real gain in coverage.
#
# Hermetic: reads only CLAUDE.md at the repo root (resolved from this
# script's own path), no mutation, no network.
#
# Run: bash scripts/claude-md.test.sh (exits non-zero on any failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

if [ ! -f "$CLAUDE_MD" ]; then
  echo "FATAL: CLAUDE.md not found at $CLAUDE_MD" >&2
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

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }

# assert_re <label> <haystack> <ERE, case-insensitive>
# Flattens embedded newlines to single spaces first: grep matches per
# physical line by default, but CLAUDE.md is hard-wrapped prose where a
# phrase (including the verbatim two-sentence rule) may cross a line break
# in the source without crossing it in the rendered/logical text.
assert_re() {
  local flat
  flat=$(printf '%s' "$2" | tr '\n' ' ' | tr -s ' ')
  if printf '%s' "$flat" | grep -qiE -- "$3"; then
    pass "$1"
  else
    fail "$1" "did not match regex (case-insensitive): $3"
  fi
}

# assert_lit <label> <flattened-haystack> <literal>
assert_lit() {
  if printf '%s' "$2" | grep -qF -- "$3"; then
    pass "$1"
  else
    fail "$1" "did not contain literal: $3"
  fi
}

# ===========================================================================
# Acceptance marker: contract comment gone from the FINAL document. This is
# the one check that must read the raw file — everything else below reads
# the stripped one.
# ===========================================================================
contract_count=$(grep -c 'Contract: B02' "$CLAUDE_MD" 2>/dev/null || true)
check "contract comment absent from final document" "${contract_count:-0}" "0"

DOC="$(sed '/<!-- Contract: B02/,/^-->$/d' "$CLAUDE_MD")"
DOC_FLAT="$(printf '%s' "$DOC" | tr '\n' ' ' | tr -s ' ')"

# ===========================================================================
# Behavior 1 — the two-sentence rule, verbatim.
# ===========================================================================
TWO_SENTENCE='Plugins require capabilities and artifacts, never plugins; only build may name components — downward, detect-and-degrade, never required.'
assert_lit "two-sentence rule present verbatim" "$DOC_FLAT" "$TWO_SENTENCE"

# ===========================================================================
# Behavior 2 — capability example (create a worktree -> newtree when
# offered, raw git worktree otherwise) with graceful degradation named as
# the property.
# ===========================================================================
assert_re "capability example frames creating a worktree as the capability goal" "$DOC" 'worktree'
assert_re "capability example names newtree as the enhancing skill" "$DOC" 'newtree'
assert_re "capability example names raw git worktree as the baseline fallback" "$DOC" 'git worktree'
assert_re "graceful degradation is named as the property" "$DOC" 'graceful[[:space:]]+degrad'

# ===========================================================================
# Behavior 3 — the four reference forms table, unchanged from current.
# Whitespace-tolerant (table cell padding is not contract-mandated), but
# each Form/Example pairing must still appear as a table row.
# ===========================================================================
assert_re "reference-forms table: Skill invocation -> /landing:land" "$DOC" \
  '\|[[:space:]]*Skill invocation[[:space:]]*\|[[:space:]]*`/landing:land`[[:space:]]*\|'
assert_re "reference-forms table: Marketplace id -> lego@clam" "$DOC" \
  '\|[[:space:]]*Marketplace id[[:space:]]*\|[[:space:]]*`lego@clam`[[:space:]]*\|'
assert_re "reference-forms table: English naming -> \"the tracking plugin\"" "$DOC" \
  '\|[[:space:]]*English naming[[:space:]]*\|[[:space:]]*"the tracking plugin"[[:space:]]*\|'
assert_re "reference-forms table: Filesystem path -> plugins/tracking/lib/…" "$DOC" \
  '\|[[:space:]]*Filesystem path[[:space:]]*\|[[:space:]]*`plugins/tracking/lib/…`[[:space:]]*\|'

# ===========================================================================
# Behavior 4 — the word-sense caution, post-B11-migration wording. B11
# deletes this repo's own .claude/lego.json and rewrites the caveat to
# reference blocks.md's command-field context (Setup:/Test: command lines
# on block-map entries) instead of the now-deleted config file; CLAUDE.md
# must not mention lego.json anywhere once that migration lands.
#
# The $DOC strip above only removes a "Contract: B02" comment, which no
# longer exists in this file (B02 was accepted and its comment removed long
# ago), so $DOC here is effectively the raw file — including THIS unit's
# own "Contract: B11" comment at the top, which narrates "lego.json" and
# "blocks.md" as part of describing the migration itself. Testing the two
# assertions below against $DOC would go green against the unmodified stub
# for the wrong reason (matching the contract comment's narration, not the
# rewritten body prose), and the negative assertion would go green forever
# just from the contract comment mentioning lego.json descriptively even
# after the real migration lands. So both strip the B11 contract comment
# first, the same way the B02 strip above does for its own comment.
# ===========================================================================
DOC_NO_B11_CONTRACT="$(sed '/<!-- Contract: B11/,/^-->$/d' "$CLAUDE_MD")"

assert_re "word-sense caution: 'landing strategy' is lego's own vocabulary" "$DOC" 'landing strategy'
assert_re "word-sense caution: 'build' in blocks.md's command-field context is a command, not a reference" \
  "$DOC_NO_B11_CONTRACT" 'blocks\.md'
assert_re "word-sense caution states neither is a plugin reference" "$DOC" 'neither is a plugin reference'

lego_json_mentions=$(printf '%s' "$DOC_NO_B11_CONTRACT" | grep -c 'lego\.json' || true)
check "CLAUDE.md no longer mentions lego.json anywhere (contract comment excluded)" "${lego_json_mentions:-0}" "0"

# ===========================================================================
# Behavior 5 — pointers to ARCHITECTURE.md (normative, read before
# boundary-crossing edits) and docs/protocols/ (shared artifact
# conventions). docs/protocols/ is new content, not present pre-rework.
# ===========================================================================
assert_re "points to ARCHITECTURE.md as normative before boundary-crossing edits" "$DOC" \
  'ARCHITECTURE\.md.{0,80}normative'
assert_re "points to docs/protocols/ for shared artifact conventions" "$DOC" 'docs/protocols/'

# ===========================================================================
# Behavior 6 — layering diagram annotated: build is the sole composite,
# every other plugin is a leaf, protocols connect leaves through artifacts.
# ===========================================================================
assert_re "diagram still orders build/landing/forge-github/forge-gitlab/lego/tracking" "$DOC" \
  'build.{0,200}landing.{0,200}forge-github.{0,200}forge-gitlab.{0,200}lego.{0,200}tracking'
assert_re "diagram annotated: build is the sole/only composite" "$DOC" \
  '\b(sole|only)\b[^a-zA-Z]{0,3}composite|composite\b[^a-zA-Z]{0,20}\b(sole|only)\b'
assert_re "diagram vocabulary: every other plugin is a leaf (bare presence — see file header)" "$DOC" '\bleaf\b'
assert_re "diagram annotated: protocols connect leaves through artifacts" "$DOC" \
  'protocol[a-z]*.{0,80}artifact|artifact[a-z]*.{0,80}protocol'

# ===========================================================================
# Behavior 7 — the ci.sh + version-bump-lint note, unchanged from current.
# ===========================================================================
assert_lit "ci.sh note: bash scripts/ci.sh is the full gate" "$DOC_FLAT" '`bash scripts/ci.sh`'
assert_re "ci.sh note: version-bump-lint reads committed state" "$DOC" \
  'version-bump-lint.{0,60}committed.{0,20}state'
assert_re "ci.sh note: a plugin.json version bump is invisible to installed users" "$DOC" \
  'plugin\.json.{0,40}version bump.{0,80}invisible'
assert_re "ci.sh note: running ci.sh before committing the bump is a vacuous pass" "$DOC" 'vacuous pass'

# ===========================================================================
# Outputs — materially shorter than or equal to the current file. Today's
# stub-carrying file's exact line count is not a fair baseline (the
# contract comment alone adds lines that vanish at acceptance), so this
# checks a generous structural cap instead of comparing to today's wc -l.
# ===========================================================================
total_lines=$(wc -l < "$CLAUDE_MD")
cap_ok=no
if (( total_lines <= 120 )); then cap_ok=yes; fi
check "reworked CLAUDE.md stays under a generous length cap (120 lines)" "$cap_ok" "yes"

# ===========================================================================
# Invariants — summary only, no .local/ citations (decision files and other
# .local/ state are gitignored; CLAUDE.md must be self-contained).
# ===========================================================================
local_cites=$(printf '%s' "$DOC" | grep -c '\.local/' || true)
check "no .local/ citations in the summary" "${local_cites:-0}" "0"

# ===========================================================================
# Edge case — the "siblings never know each other" rule's UNIVERSAL reach
# (every plugin pair, not just the pairs this file names) must read as
# ARCHITECTURE.md's ruling, not as this file's own independent extension.
# A bare co-occurrence of "universal" and "ARCHITECTURE.md" is not enough
# to test this — the CURRENT pre-ruling wording already has both nearby
# ("Universally — not just the pairs `ARCHITECTURE.md` names") and reads
# as CLAUDE.md's own extension, which is exactly the bug this edge case
# rules out. So this checks two things instead: the old narrow-attribution
# phrasing is gone, and a stating verb ties ARCHITECTURE.md to the claim.
# ===========================================================================
old_attribution=$(printf '%s' "$DOC_FLAT" | grep -c 'not just the pairs `ARCHITECTURE.md` names' || true)
check "old 'not just the pairs ARCHITECTURE.md names' phrasing is gone" "${old_attribution:-0}" "0"
assert_re "sibling rule's universal reach is framed as ARCHITECTURE.md's own ruling (stating verb nearby)" "$DOC" \
  'ARCHITECTURE\.md[^.]{0,60}\b(states?|holds?|rules?|says?|is explicit)\b|\b(states?|holds?|rules?|says?|is explicit)\b[^.]{0,60}ARCHITECTURE\.md'

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$FAILED"
