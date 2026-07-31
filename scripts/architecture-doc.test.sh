#!/bin/bash
# Contract tests for B01 architecture-md-amendment (plan
# 001-ensure-agents-understand-architecture): the "Contract: B01
# architecture-md-amendment" HTML-comment docblock near the top of
# ARCHITECTURE.md is the source of truth. This suite asserts the AMENDED
# document's content and structure; the amendment itself (rewriting the
# prose) is a different block's job (the implementation wave).
#
# CRITICAL: the contract comment quotes several of the very phrases this
# suite must assert (e.g. "capabilities, not plugins", "detect-and-degrade").
# A naive grep over the raw file goes green against the unimplemented stub
# on the strength of the comment alone — a wrong-reason pass. Every
# assertion below (other than the one that checks the comment itself is
# gone) runs against $DOC, the file content with the whole
# "<!-- Contract: B01 ... -->" block deleted first. This stays correct
# after acceptance too: the comment will be gone, so the sed range deletes
# nothing and $DOC equals the file.
#
# Hermetic: reads only ARCHITECTURE.md at its fixed repo-root location
# (resolved from this script's own path), no mutation, no network.
#
# Run: bash scripts/architecture-doc.test.sh (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOC_PATH="$REPO_ROOT/ARCHITECTURE.md"

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

# assert_contains_re_i <label> <haystack> <ERE, case-insensitive>
# Flattens embedded newlines to spaces first: grep matches per physical
# line by default, but the haystack is hard-wrapped markdown prose where a
# proximity regex's two halves may land on different source lines.
assert_contains_re_i() {
  local flat
  flat=$(printf '%s' "$2" | tr '\n' ' ')
  if printf '%s' "$flat" | grep -qiE -- "$3"; then
    pass "$1"
  else
    fail "$1" "did not match regex (case-insensitive): $3"
  fi
}

# assert_not_contains_re_i <label> <haystack> <ERE, case-insensitive>
assert_not_contains_re_i() {
  local flat
  flat=$(printf '%s' "$2" | tr '\n' ' ')
  if printf '%s' "$flat" | grep -qiE -- "$3"; then
    fail "$1" "matched regex it must NOT match: $3"
  else
    pass "$1"
  fi
}

# assert_contains_f <label> <haystack> <fixed string>
# Case-sensitive fixed-string match, for the handful of phrases the
# contract quotes verbatim.
assert_contains_f() {
  if printf '%s' "$2" | grep -qF -- "$3"; then
    pass "$1"
  else
    fail "$1" "did not contain fixed string: $3"
  fi
}

# extract_zone <doc> <start ERE> <end ERE>
# Returns the lines from the first line matching <start ERE> up to (but not
# including) the next line matching <end ERE>, or end-of-document if none.
# Used to scope a batch of checks to the one new section they describe, so a
# generic word (e.g. "path", "English", "command") can't be satisfied by an
# unrelated coincidence elsewhere in this 300-line document. Empty output
# (start heading absent) makes every check scoped to the zone fail, which is
# the correct red-now behavior.
extract_zone() {
  local d="$1" start_re="$2" end_re="$3" start_line end_line total
  start_line=$(printf '%s\n' "$d" | grep -niE "$start_re" | head -n1 | cut -d: -f1)
  [[ -z "$start_line" ]] && return
  total=$(printf '%s\n' "$d" | wc -l)
  end_line=$(printf '%s\n' "$d" | tail -n +"$((start_line + 1))" | grep -niE "$end_re" | head -n1 | cut -d: -f1)
  if [[ -n "$end_line" ]]; then
    end_line=$((start_line + end_line - 1))
  else
    end_line="$total"
  fi
  printf '%s\n' "$d" | sed -n "${start_line},${end_line}p"
}

check "ARCHITECTURE.md exists" "$([[ -f "$DOC_PATH" ]] && echo yes || echo no)" "yes"

# ===========================================================================
# Acceptance clause: the scaffolding contract comment is removed. Runs
# against the RAW file deliberately — this is the one check that must NOT
# use the stripped $DOC, since stripping the comment would make this check
# vacuously pass even against the unimplemented stub.
# ===========================================================================

contract_count=$(grep -c 'Contract: B01' "$DOC_PATH" 2>/dev/null)
check "scaffolding contract comment removed at acceptance" "${contract_count:-0}" "0"

# From here on, work against $DOC: the file with the whole B01 contract
# comment block deleted (matches the brief's suggested strip; a no-op once
# the comment is actually gone).
DOC="$(sed '/<!-- Contract: B01/,/^-->$/d' "$DOC_PATH" 2>/dev/null)"

# ===========================================================================
# Behavior 1 — Rule 3 is universal, not just previously-named pairs, with
# its rationale stated and attributed as a consequence of rule 2.
# ===========================================================================

assert_contains_re_i "rule 3 states UNIVERSAL scope (every plugin pair, not just named ones)" "$DOC" \
  'universal(ly)?|every[[:space:]]+plugin[[:space:]]+pair|all[[:space:]]+plugin[[:space:]]+pairs'

assert_contains_re_i "rationale: naming an uninstalled plugin misleads the agent about what exists" "$DOC" \
  'mislead[a-z]*[^.]{0,150}(install|exist)'

assert_contains_re_i "rule 3 stated as a consequence of rule 2 (leaf isolation)" "$DOC" \
  '(consequence[^.]{0,150}(rule[[:space:]]*2|leaf))|((rule[[:space:]]*2|leaf)[^.]{0,150}consequence)'

# ===========================================================================
# Behavior 2 — the capability principle: goal stated, baseline
# implementation with standard tools, catalog-driven enhancement, providers
# never named; graceful degradation named as a property; the worktree
# example (newtree / git worktree).
# ===========================================================================

assert_contains_f "exact phrase 'capabilities, not plugins'" "$DOC" "capabilities, not plugins"

assert_contains_re_i "baseline implementation using standard tools" "$DOC" \
  'baseline[[:space:]]+implementation'

assert_contains_re_i "executor enhances via whatever the skill catalog advertises; providers never named" "$DOC" \
  '(enhance[a-z]*[^.]{0,120}catalog)|(catalog[^.]{0,120}enhance[a-z]*)|(provider[a-z]*[^.]{0,120}never[[:space:]]+named)'

assert_contains_re_i "graceful degradation named explicitly as a property" "$DOC" \
  'graceful[[:space:]]+degradation'

assert_contains_f "worktree example names 'newtree'" "$DOC" "newtree"
assert_contains_f "worktree example names 'git worktree' (the raw-tool fallback)" "$DOC" "git worktree"

# ===========================================================================
# Behavior 3 — build is the ONLY composite: downward, detect-and-degrade,
# never required (absence means silence, not failure).
# ===========================================================================

assert_contains_re_i "build stated as THE ONLY composite (unhedged)" "$DOC" \
  'only[[:space:]]+composite'

assert_contains_f "exact phrase 'detect-and-degrade'" "$DOC" "detect-and-degrade"

assert_contains_re_i "composite references never required: absence means silence, not failure" "$DOC" \
  '(never[[:space:]]+required)|(silence[^.]{0,100}failure)'

# ===========================================================================
# Behavior 4 — the protocol model: shared artifact convention, spec owned
# by the architecture at repo level, the four named protocols with their
# spec paths, and the shell-script boundary (protocols + vendored copies).
# ===========================================================================

assert_contains_re_i "protocol defined as a shared artifact convention" "$DOC" \
  'shared[[:space:]]+artifact[[:space:]]+convention'

assert_contains_re_i "protocol spec owned by the architecture, not any plugin" "$DOC" \
  '(no[[:space:]]+plugin[[:space:]]+owns)|(not[[:space:]]+owned[[:space:]]+by[[:space:]]+(any[[:space:]]+)?plugin)'

assert_contains_f "protocol path: docs/protocols/session-states.md" "$DOC" "docs/protocols/session-states.md"
assert_contains_f "protocol path: docs/protocols/decision-file.md" "$DOC" "docs/protocols/decision-file.md"
assert_contains_f "protocol path: docs/protocols/setup-stamp.md" "$DOC" "docs/protocols/setup-stamp.md"
assert_contains_f "protocol path: docs/protocols/todo-format.md" "$DOC" "docs/protocols/todo-format.md"

assert_contains_re_i "boundary: shell scripts can't consult the skill catalog, so they use protocols + vendored copies" "$DOC" \
  'vendor[a-z]*[^.]{0,150}(skill[[:space:]]+catalog|catalog)'

# ===========================================================================
# Behavior 5 — updates is marketplace-meta: catalog as data, may enumerate
# installed plugins from marketplace/catalog/stamp data, never hardcodes
# plugin names in its own docs or skills.
# ===========================================================================

updates_heading_present=$(printf '%s\n' "$DOC" | grep -ciE '^###[[:space:]]+updates\b')
check "'updates' gets its own responsibility heading (like build/landing/lego/tracking)" \
  "$([[ "${updates_heading_present:-0}" -ge 1 ]] && echo yes || echo no)" "yes"

# Scoped to the updates subsection itself (start at its own heading, end at
# the next heading of any level) so generic words like "catalog" or
# "plugin" can't be satisfied by unrelated prose elsewhere in the document.
UPDATES_ZONE="$(extract_zone "$DOC" '^###[[:space:]]+updates\b' '^##')"

assert_contains_re_i "updates named as marketplace-meta" "$UPDATES_ZONE" \
  'marketplace-meta|marketplace[[:space:]]+meta'

assert_contains_re_i "updates' domain is the catalog AS DATA" "$UPDATES_ZONE" \
  'catalog[^.]{0,60}data'

assert_contains_re_i "updates may not hardcode plugin names in its docs/skills" "$UPDATES_ZONE" \
  'hardcod[a-z]*[^.]{0,80}plugin'

# ===========================================================================
# Behavior 6 — "Current state" section replaced: per-violation rows give
# way to the mechanical-inventory pointer plus the still-open backlog refs.
# ===========================================================================

check "'## Current state' heading still present" \
  "$(printf '%s\n' "$DOC" | grep -cxE '## Current state')" "1"

assert_not_contains_re_i "old per-violation 'Rule | State' table is gone (prose/pointer replaces it)" "$DOC" \
  '\|[[:space:]]*rule[[:space:]]*\|[[:space:]]*state[[:space:]]*\|'

assert_contains_f "pointer to the mechanical inventory: scripts/architecture-lint-baseline.txt" "$DOC" \
  "scripts/architecture-lint-baseline.txt"

assert_contains_f "backlog reference #147 present" "$DOC" "#147"
assert_contains_f "backlog reference #148 present" "$DOC" "#148"
assert_contains_f "backlog reference #149 present" "$DOC" "#149"
assert_contains_f "backlog reference #179 present" "$DOC" "#179"

# ===========================================================================
# Behavior 7 — "What counts as a reference" forms recorded (with the
# word-sense caution), and the scope statement: architecture-lint.sh
# enforces these forms inside plugins/*/; this document is out of scan
# scope and may name plugins freely.
# ===========================================================================

check "'What counts as a reference' section present" \
  "$(printf '%s\n' "$DOC" | grep -icE '^##+[[:space:]]+What counts as a reference')" "1"

# Scoped to that section (start at its own heading, end at the next
# level-2 heading) — "skill invocation" in particular would otherwise
# false-match the unrelated existing rule-3 wording "no skill invocations,
# no imports"; "English", "path", "command" are generic enough to risk
# similar coincidences elsewhere in a 300-line document.
REFFORMS_ZONE="$(extract_zone "$DOC" '^##+[[:space:]]+What counts as a reference' '^##[[:space:]]')"

assert_contains_re_i "reference form: skill invocation" "$REFFORMS_ZONE" 'skill[[:space:]]+invocation'
assert_contains_re_i "reference form: marketplace id" "$REFFORMS_ZONE" 'marketplace[[:space:]]+id'
assert_contains_re_i "reference form: English naming" "$REFFORMS_ZONE" 'english[[:space:]]+naming'
assert_contains_re_i "reference form: filesystem path" "$REFFORMS_ZONE" 'filesystem[[:space:]]+path'
assert_contains_re_i "marketplace-id form example uses the '@clam' shape" "$REFFORMS_ZONE" '[a-z0-9-]+@clam'

assert_contains_f "word-sense caution example: 'landing strategy'" "$REFFORMS_ZONE" "landing strategy"
assert_contains_re_i "word-sense caution example: the \`build\` command" "$REFFORMS_ZONE" \
  'build[^.]{0,40}command'

assert_contains_re_i "scope: architecture-lint.sh enforces these forms inside plugins/*/" "$REFFORMS_ZONE" \
  'architecture-lint\.sh[^.]{0,150}plugins/\*/'

assert_contains_re_i "scope: this document is out of scan scope and may name plugins freely" "$REFFORMS_ZONE" \
  '(out[[:space:]]+of[[:space:]]+scan[[:space:]]+scope)|(freely[^.]{0,60}(name|plugin))'

# ===========================================================================
# Outputs — flowing prose (no hard-wrapped tables where prose serves,
# already covered by the Current-state table removal above); existing
# sections revised in place, not appended as a changelog.
# ===========================================================================

# Line-anchored, so this checks each ORIGINAL line's start, not
# assert_contains_re_i's flattened single-line text (where "^" would only
# ever match position 0 of the whole document and the check would be dead).
changelog_heading_count=$(printf '%s\n' "$DOC" | grep -ciE '^##+[[:space:]]+(changelog|amendment history|2026-07-31)')
check "amendment folded into existing sections, not appended as a dated changelog heading" \
  "${changelog_heading_count:-0}" "0"

# ===========================================================================
# Invariants — normative scope is ALL plugins in the marketplace (the old
# closed four-name enumeration is gone).
# ===========================================================================

assert_contains_re_i "normative scope stated as ALL plugins in the marketplace" "$DOC" \
  '(all|every)[[:space:]]+plugins?[[:space:]]+in[[:space:]]+(this|the)[[:space:]]+marketplace'

assert_not_contains_re_i "old closed four-plugin enumeration ('normative for build, landing, lego, and tracking') is gone" "$DOC" \
  'normative for `build`, `landing`, `lego`, and `tracking`'

# ===========================================================================
# Edge case — forge-github/forge-gitlab don't exist yet; the diagram may
# keep them as planned components, but the document must not claim they
# exist.
# ===========================================================================

# "must not claim they exist" is a negative over arbitrary phrasing (an
# absence-of-false-claim check is unbounded and not reliably mechanical) —
# left to orchestrator judgement at acceptance rather than asserted here.
# The presence half (kept as planned components) is testable and asserted:
assert_contains_f "forge-github still named (planned component, diagram/prose)" "$DOC" "forge-github"
assert_contains_f "forge-gitlab still named (planned component, diagram/prose)" "$DOC" "forge-gitlab"

# ===========================================================================
# Self-containment — the amendment records the ruling directly rather than
# pointing at a gitignored .local/ decision file; the doc is a committed,
# always-present artifact, so nothing in it (old or new) may cite a
# .local/ path.
# ===========================================================================

local_path_count=$(printf '%s\n' "$DOC" | grep -c '\.local/')
check "no .local/ paths cited anywhere in the document" "${local_path_count:-0}" "0"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$FAILED"
