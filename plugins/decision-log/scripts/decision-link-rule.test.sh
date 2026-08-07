#!/usr/bin/env bash
# Test for Block B23 decision templates require links (plan 003-followup-
# fixes). Source of truth: the HTML-comment docblock titled "Contract:
# 003-B23 decision templates require links" at the end of
# plugins/decision-log/skills/create/SKILL.md.
#
# Behavior under contract: the create skill's guidance, its template.md, and
# the rundown skill's SKILL.md require every artifact a decision document
# references — the thing under decision, sibling decisions, plans, protocols
# — to be carried as a RELATIVE markdown link resolvable from the decision
# file's own directory, never a bare path or name. template.md demonstrates
# the form in its own example fields; the guidance states the rule and its
# reason (a served or previewed decision must let the reader reach what it
# asks them to judge in one click).
#
# FALSE-GREEN GUARD. The rule text currently exists ONLY inside the 003-B23
# contract comment at the end of create/SKILL.md, and that comment is deleted
# at acceptance. Every content check against create/SKILL.md and
# rundown/SKILL.md therefore runs on a comment-stripped copy
# (sed '/<!--/,/-->/d'), exactly as the sibling rundown-render-seam suite
# does, so the contract's own prose can never satisfy a check meant for real
# guidance. Check 0.4 asserts the strip actually worked. template.md carries
# no comment, so its anchors are plain.
#
# Prose checks run against a whitespace-normalized blob (newlines squashed to
# spaces) so a rule sentence that wraps across lines still matches. Three
# phrases already in the shipped prose are near-misses that the regexes below
# deliberately dodge, and normalizing makes each one reachable, so the
# dodging is load-bearing rather than incidental:
#   - "never a bare key" (create, ticket refs) and "a bare \"go\" reply"
#     (rundown): the bare-form regex matches only bare path / name /
#     filename / reference / string / slug.
#   - "Create ... directory if it doesn't exist" (create Phase 5) and
#     "Create the directory if it does not exist" (rundown): those are about
#     directories, not artifacts, so the not-yet-exists check requires the
#     linking clause within the SAME sentence ([^.] windows). Both shipped
#     lines are followed immediately by a period, so neither can reach a
#     "link" token.
#
# The behavior checks are expected to FAIL against the current
# NotImplemented: 003-B23 state and PASS once the real prose lands. The
# invariant checks (template field set and ordering, no-plugin-named, B04
# non-regression) pass today by construction and guard against the
# implementation wave restructuring the template or reintroducing a
# cross-plugin reference while adding the link rule.
#
# Run: bash plugins/decision-log/scripts/decision-link-rule.test.sh (exits
# non-zero on failure)

# Byte semantics. These files are UTF-8 (em-dashes throughout) and the prose
# checks below run against long single-line blobs; under a UTF-8 locale, a
# case-insensitive bounded-repeat grep over such a line can take minutes.
# Every pattern here is ASCII, so C is both faster and sufficient.
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CREATE="$PLUGIN_ROOT/skills/create/SKILL.md"
TEMPLATE="$PLUGIN_ROOT/skills/create/template.md"
RUNDOWN="$PLUGIN_ROOT/skills/rundown/SKILL.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# 0. Preconditions and the false-green guard
# ---------------------------------------------------------------------------

check "skills/create/SKILL.md exists" "$([ -f "$CREATE" ] && echo yes || echo no)" "yes"
check "skills/create/template.md exists" "$([ -f "$TEMPLATE" ] && echo yes || echo no)" "yes"
check "skills/rundown/SKILL.md exists" "$([ -f "$RUNDOWN" ] && echo yes || echo no)" "yes"

# Comment-stripped copies: contract-docblock prose can never satisfy a
# content check below.
CREATE_BODY="$(sed '/<!--/,/-->/d' "$CREATE" 2>/dev/null)"
RUNDOWN_BODY="$(sed '/<!--/,/-->/d' "$RUNDOWN" 2>/dev/null)"
TEMPLATE_BODY="$(sed '/<!--/,/-->/d' "$TEMPLATE" 2>/dev/null)"

check "the 003-B23 contract comment is stripped from the create body (guard: strip is effective)" \
  "$(grep -qF '003-B23' <<<"$CREATE_BODY" && echo leaked || echo stripped)" "stripped"

# Whitespace-normalized blobs, so a sentence wrapped across lines matches.
flatten() { tr '\n' ' ' | tr -s ' '; }
CREATE_FLAT="$(flatten <<<"$CREATE_BODY")"
RUNDOWN_FLAT="$(flatten <<<"$RUNDOWN_BODY")"
GUIDANCE_FLAT="$CREATE_FLAT $RUNDOWN_FLAT"
ALL_FLAT="$GUIDANCE_FLAT $(flatten <<<"$TEMPLATE_BODY")"

# --- Contract vocabulary ----------------------------------------------------

# "carried as a RELATIVE markdown link": relative and link in one clause. The
# character class excludes '|' and '.' so a match cannot span table cells or
# sentences.
RULE_RE='relative[[:alnum:][:space:],_-]{0,30}link|link[[:alnum:][:space:],_-]{0,30}relative'
# "never a bare path or name" — must NOT match the shipped "bare key" or
# "bare \"go\" reply".
BARE_RE='bare[[:space:]]+(path|name|filename|reference|string|slug)|plain[[:space:]]+(path|name)|backticked?[[:space:]]+path'
# "every artifact a decision document references"
SCOPE_RE='every artifact|each artifact|any artifact|artifacts?[^.]{0,40}referenc|referenc[^.]{0,40}artifact'
# "resolvable from the decision file's own directory"
ANCHOR_RE='resolvable|relative to (the |its )?(decision|document|file|own directory)|from the decision file'
# "let the reader reach what they are asked to judge in one click"
REASON_RE='one click|single click|clickable|click through|click straight|reach (it|them|the artifact|what)'

# ===========================================================================
# PART 1: create/SKILL.md guidance (stripped) — states the rule
# ===========================================================================

check "create/SKILL.md states the relative-markdown-link rule" \
  "$(grep -qiE "$RULE_RE" <<<"$CREATE_FLAT" && echo yes || echo no)" "yes"

check "create/SKILL.md scopes the rule to every artifact the decision references" \
  "$(grep -qiE "$SCOPE_RE" <<<"$CREATE_FLAT" && echo yes || echo no)" "yes"

check "create/SKILL.md forbids the bare path/name form" \
  "$(grep -qiE "$BARE_RE" <<<"$CREATE_FLAT" && echo yes || echo no)" "yes"

check "create/SKILL.md or rundown/SKILL.md anchors relativity to the decision file's own directory" \
  "$(grep -qiE "$ANCHOR_RE" <<<"$GUIDANCE_FLAT" && echo yes || echo no)" "yes"

check "create/SKILL.md or rundown/SKILL.md gives the reason (reader reaches the artifact in one click)" \
  "$(grep -qiE "$REASON_RE" <<<"$GUIDANCE_FLAT" && echo yes || echo no)" "yes"

# ===========================================================================
# PART 2: create/template.md — demonstrates the form
# ===========================================================================

# Inline-link targets, split into relative vs. scheme-qualified/root-absolute.
TEMPLATE_LINKS="$(grep -oE '\]\([^)]+\)' "$TEMPLATE" 2>/dev/null | sed 's/^](//; s/)$//')"
TEMPLATE_REL_LINKS="$(grep -vE '^([a-zA-Z][a-zA-Z0-9+.-]*:|/|#)' <<<"$TEMPLATE_LINKS" | grep -vE '^[[:space:]]*$')"

check "template.md demonstrates the form with a real markdown link, not prose about links" \
  "$([ -n "$TEMPLATE_LINKS" ] && echo yes || echo no)" "yes"

check "template.md's demonstrated link is RELATIVE (not a URL or root-absolute path)" \
  "$([ -n "$TEMPLATE_REL_LINKS" ] && echo yes || echo no)" "yes"

# The example belongs in the field that carries referenced artifacts.
TEMPLATE_RELATED="$(sed -n '/^## Related/,$p' "$TEMPLATE")"

check "template.md's '## Related' field carries the link example" \
  "$(grep -qE '\]\([^)]+\)' <<<"$TEMPLATE_RELATED" && echo yes || echo no)" "yes"

# ===========================================================================
# PART 3: rundown/SKILL.md (stripped) — states the rule
# ===========================================================================

check "rundown/SKILL.md states the relative-markdown-link rule" \
  "$(grep -qiE "$RULE_RE" <<<"$RUNDOWN_FLAT" && echo yes || echo no)" "yes"

check "rundown/SKILL.md forbids the bare path/name form" \
  "$(grep -qiE "$BARE_RE" <<<"$RUNDOWN_FLAT" && echo yes || echo no)" "yes"

# ===========================================================================
# PART 4: edge cases
# ===========================================================================

check "guidance covers the already-a-URL artifact (an absolute URL is already a link)" \
  "$(grep -qiE '\burls?\b|absolute (link|url|address)|external (link|url|resource|artifact)' <<<"$GUIDANCE_FLAT" && echo yes || echo no)" "yes"

# Same-sentence windows: the shipped "Create the directory if it does not
# exist." lines are terminated by a period before any "link" token, so they
# cannot satisfy this.
check "guidance covers the not-yet-existing artifact (linked anyway)" \
  "$(grep -qiE "(does ?n[o']t|does not|has ?n[o']t|is not|not) (yet )?exist[^.]{0,80}(link|anyway)|link[^.]{0,80}(does ?n[o']t|does not|not) (yet )?exist" <<<"$GUIDANCE_FLAT" && echo yes || echo no)" "yes"

# ===========================================================================
# PART 5: invariant — template field set and ordering unchanged
# ===========================================================================

EXPECTED_HEADINGS=(
  "# Decision Log Template"
  "# {YYYY-MM-DD} - DL - {What it's about}"
  "## Context / Problem Statement"
  "### Background"
  "### The Problem"
  "### Impact"
  "## Options Considered"
  "### Option 1: Do Nothing"
  "### Option 2: {Name}"
  "### Option 3: {Name}"
  "## Decision"
  "## Consequences"
  "## Related"
)

EXPECTED_FIELDS=(
  '**Date:**'
  '**Pros:**'
  '**Cons:**'
  '**Estimated effort:**'
  '**Chosen option:**'
  '**Rationale:**'
  '**Trade-offs accepted:**'
  '**Positive:**'
  '**Negative:**'
  '**Risks:**'
)

MISSING_HEADINGS=""
for h in "${EXPECTED_HEADINGS[@]}"; do
  grep -qxF "$h" "$TEMPLATE" || MISSING_HEADINGS="${MISSING_HEADINGS}[$h]"
done
check "template.md retains every existing heading (the link rule is additive)" \
  "${MISSING_HEADINGS:-none}" "none"

MISSING_FIELDS=""
for f in "${EXPECTED_FIELDS[@]}"; do
  grep -qF "$f" "$TEMPLATE" || MISSING_FIELDS="${MISSING_FIELDS}[$f]"
done
check "template.md retains every existing field label" \
  "${MISSING_FIELDS:-none}" "none"

# Filter the actual heading sequence down to the expected set, then compare
# order. Catches reordering and removal; tolerates an added heading.
ACTUAL_SEQ=""
while IFS= read -r line; do
  for h in "${EXPECTED_HEADINGS[@]}"; do
    if [[ "$line" == "$h" ]]; then ACTUAL_SEQ="$ACTUAL_SEQ$line|"; break; fi
  done
done < <(grep -E '^#{1,6} ' "$TEMPLATE")
EXPECTED_SEQ="$(printf '%s|' "${EXPECTED_HEADINGS[@]}")"
check "template.md heading order unchanged" "$ACTUAL_SEQ" "$EXPECTED_SEQ"

check "template.md's last section is still '## Related'" \
  "$(grep -E '^#{1,6} ' "$TEMPLATE" | tail -1)" "## Related"

check "template.md still wraps the template in exactly one fenced block" \
  "$(grep -cE '^```' "$TEMPLATE")" "2"

# ===========================================================================
# PART 6: invariant — no plugin is named
# ===========================================================================

check "no marketplace id (@clam) in create/SKILL.md, template.md or rundown/SKILL.md" \
  "$(grep -qF '@clam' <<<"$ALL_FLAT" && echo yes || echo no)" "no"

check "no cross-plugin filesystem path (plugins/<name>/) in create/SKILL.md, template.md or rundown/SKILL.md" \
  "$(grep -qE 'plugins/[a-z]' <<<"$ALL_FLAT" && echo yes || echo no)" "no"

# Forward guard: whatever sentence states the link rule must not name a
# sibling plugin. Vacuous until the rule prose lands, real thereafter.
# `tracking`, `landing` and `build` are excluded from the name list — they
# are domain words in this prose, not plugin references.
#
# Sentence-split rather than a bounded-context window: splitting on '.' is
# linear and cannot blow up on a long line the way `grep -o '.{0,140}...'`
# does. Splitting inside `foo.md` only fragments further, which tightens the
# guard rather than loosening it.
RULE_SENTENCES="$(tr '.' '\n' <<<"$ALL_FLAT" | grep -iE "$RULE_RE")"
check "the link-rule prose names no sibling plugin" \
  "$(grep -qiE 'render-doc|\blego\b|forge-github|forge-gitlab|session-modes|team-review|pr-workflow' <<<"$RULE_SENTENCES" && echo yes || echo no)" "no"

# ===========================================================================
# PART 7: invariant — B04 render seam not regressed by this block's edits
# ===========================================================================
# rundown/SKILL.md is an edit target of B23; these two lines are the ones the
# sibling rundown-render-seam suite is most likely to lose. Duplicated here
# deliberately so a B23 regression fails B23's own suite.

check "rundown/SKILL.md still consumes render-doc by skill name" \
  "$(grep -qF 'render-doc:render' <<<"$RUNDOWN_FLAT" && echo yes || echo no)" "yes"

# The leading `~/` of the clam-code-era path is omitted deliberately: matching
# `.claude/skills/render-doc` catches it either way, and keeps the pattern
# free of a tilde that reads as an unexpanded home reference.
check "rundown/SKILL.md still has no filesystem path into another plugin" \
  "$(grep -qE '\.claude/skills/render-doc|render-doc/scripts' <<<"$RUNDOWN_FLAT" && echo yes || echo no)" "no"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
