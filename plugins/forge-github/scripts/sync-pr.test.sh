#!/bin/bash
# Structural test for the B05 forge-github sync-pr skill
# (plugins/forge-github/skills/sync-pr/SKILL.md). The skill body is prose
# instructions, not executable code, so this test checks for the presence
# of the contract's required clauses (the seven steps, formatting
# conventions, errors, invariants, edge cases), not exact wording.
#
# All content checks (except the frontmatter and the global
# NotImplemented check) run against the file with its HTML comment block
# (the contract docblock) stripped out first, for the same reason as
# create-pr.test.sh: the docblock already states every required clause
# verbatim, so an unstripped check could pass on the unimplemented stub
# for the wrong reason.
# Run: bash plugins/forge-github/scripts/sync-pr.test.sh (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$PLUGIN_DIR/skills/sync-pr/SKILL.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

strip_frontmatter() { # file -> body with the leading YAML frontmatter block
  # removed. The frontmatter's own "description:" line already contains
  # some of the same words the contract requires in the real skill body
  # (e.g. "flowing-prose formatting conventions", "current state"), so
  # leaving it in would make those checks pass on the unimplemented stub
  # for the wrong reason.
  awk '
    NR==1 && $0=="---" {infm=1; next}
    infm && $0=="---" {infm=0; next}
    infm {next}
    {print}
  ' "$1" 2>/dev/null
}

strip_comments_stdin() {
  awk '/<!--/{c=1} !c{print} /-->/{c=0}'
}

BODY="$(strip_frontmatter "$SKILL" | strip_comments_stdin)"

# Flattened to a single line (internal newlines collapsed to spaces) so a
# multi-word check isn't defeated by the source markdown's own 80-column
# hard-wrapping -- that source-level wrapping is unrelated to the
# contract, which is about the flowing-vs-hard-wrapped shape of *composed
# PR descriptions*, not of this documentation file.
FLAT_BODY="$(printf '%s' "$BODY" | tr '\n' ' ' | tr -s ' ')"

has_literal() { # needle (checked against FLAT_BODY)
  printf '%s' "$FLAT_BODY" | grep -qF -- "$1" && echo yes || echo no
}

has_pattern_ci() { # extended-regex (checked against FLAT_BODY)
  printf '%s' "$FLAT_BODY" | grep -qiE -- "$1" && echo yes || echo no
}

has_root_path() { # bare-filename-regex, checked against FLAT_BODY, only
  # matching when NOT immediately preceded by '/'. This discriminates a
  # root-level path reference (e.g. "PULL_REQUEST_TEMPLATE.md") from the
  # same filename appearing as the tail of a subpath (".github/..." or
  # "docs/..."), which would otherwise satisfy the check as a substring
  # for the wrong reason. (Same discipline as create-pr.test.sh.) Portable
  # ERE rather than a PCRE lookbehind ("grep -P" is unavailable on
  # BSD/macOS grep): require either start-of-line or a single non-'/'
  # character before the filename.
  printf '%s' "$FLAT_BODY" | grep -qE -- "(^|[^/])$1" && echo yes || echo no
}

check "skill file exists" "$([[ -f "$SKILL" ]] && echo yes || echo no)" "yes"

# 0. Frontmatter shape (stable metadata, unaffected by implementation).
check "frontmatter name is sync-pr" \
  "$(grep -m1 '^name:' "$SKILL" 2>/dev/null | sed 's/^name: *//')" "sync-pr"

# 1. No NotImplemented marker in the rendered skill body (docblock-stripped,
#    marker included). This is the red/green gate: fails until the marker
#    is replaced by the real skill body.
check "no NotImplemented marker in skill body" \
  "$(has_pattern_ci 'NotImplemented')" "no"

# 2. Step 1 -- detect: gh pr list for the current branch; no open PR is an
#    expected outcome, not an error; more than one -> use the most recent.
check "detect step: gh pr list documented" \
  "$(has_literal 'gh pr list')" "yes"
check "detect step: no-open-PR is an expected non-error outcome" \
  "$(has_pattern_ci 'no open pr')" "yes"
check "detect step: more-than-one-PR uses the most recent" \
  "$(has_pattern_ci 'most recent')" "yes"

# 3. Step 2 -- read: gh pr view; base may have moved, diffs use current base.
check "read step: gh pr view documented" \
  "$(has_literal 'gh pr view')" "yes"
check "read step: diffs use the CURRENT base" \
  "$(has_pattern_ci 'current base')" "yes"

# 4. Step 3 -- gather context: diff, plan docs, verification records,
#    commit log; absence of optional context is normal.
check "gather step: reads .local/PLAN.md as repo context" \
  "$(has_literal '.local/PLAN.md')" "yes"
check "gather step: reads .local/TODO.md as repo context" \
  "$(has_literal 'TODO.md')" "yes"
check "gather step: uses the commit log (git log)" \
  "$(has_literal 'git log')" "yes"
check "gather step: uses the diff (git diff)" \
  "$(has_literal 'git diff')" "yes"

# 5. Step 4 -- template resolution: same paths and order as create-pr,
#    falling back to the same default structure. Brought up to parity
#    with create-pr.test.sh's coverage of the identical clause: all five
#    paths, the same-as-create-pr order reference, and the full default
#    structure.
check "template resolution: .github/PULL_REQUEST_TEMPLATE.md path documented" \
  "$(has_literal '.github/PULL_REQUEST_TEMPLATE.md')" "yes"
check "template resolution: .github/pull_request_template.md path documented" \
  "$(has_literal '.github/pull_request_template.md')" "yes"
check "template resolution: docs/pull_request_template.md path documented" \
  "$(has_literal 'docs/pull_request_template.md')" "yes"
check "template resolution: root PULL_REQUEST_TEMPLATE.md path documented (discriminating from .github/ and docs/ subpaths)" \
  "$(has_root_path 'PULL_REQUEST_TEMPLATE\.md')" "yes"
check "template resolution: root-level pull_request_template.md path documented (discriminating from .github/ and docs/ subpaths)" \
  "$(has_root_path 'pull_request_template\.md')" "yes"
check "template resolution: same paths and order as create-pr documented" \
  "$(has_pattern_ci 'same.{0,15}(paths|order).{0,20}create-pr')" "yes"
check "template resolution: default structure includes ## Summary" \
  "$(has_literal '## Summary')" "yes"
check "template resolution: default structure includes ## Why" \
  "$(has_literal '## Why')" "yes"
check "template resolution: default structure includes ## Changes" \
  "$(has_literal '## Changes')" "yes"
check "template resolution: default structure includes ## Verification" \
  "$(has_literal '## Verification')" "yes"

# 6. Step 5 -- compose the updated description reflecting the CURRENT
#    branch state.
check "compose step: reflects the branch's current state" \
  "$(has_pattern_ci 'current state')" "yes"

# 7. Step 6 -- apply: gh pr edit.
check "apply step: gh pr edit documented" \
  "$(has_literal 'gh pr edit')" "yes"

# 8. Step 7 -- report which sections were added, updated, or unchanged.
check "report step: added/updated/unchanged summary documented" \
  "$(has_pattern_ci 'added.{0,15}updated.{0,15}unchanged')" "yes"

# 9. Formatting conventions (identical to create-pr's).
check "formatting: flowing-paragraph convention" \
  "$(has_pattern_ci 'flowing')" "yes"
check "formatting: never-hard-wrapped convention" \
  "$(has_pattern_ci 'hard-wrap')" "yes"
check "formatting: reviewer-facing description convention" \
  "$(has_pattern_ci 'reviewer')" "yes"
check "formatting: no internal workflow terminology convention" \
  "$(has_pattern_ci 'workflow terminology')" "yes"

# 10. Errors.
check "error: no open PR is reported and treated as non-error" \
  "$(has_pattern_ci 'no open pr')" "yes"
check "error: gh missing/unauthenticated remediation (gh auth login)" \
  "$(has_pattern_ci 'gh auth login')" "yes"
check "error: gh pr edit failure is reported without retry" \
  "$(has_pattern_ci 'do not retry')" "yes"
check "error: not-a-git-repository failure documented" \
  "$(has_pattern_ci 'not a git repository')" "yes"

# 11. Invariants: never creates a PR, never modifies the title, idempotent,
#     reflects current state (not creation-time state), works standalone.
check "invariant: never creates a PR" \
  "$(has_pattern_ci 'never creates')" "yes"
check "invariant: never modifies the PR title" \
  "$(has_pattern_ci 'never modifies.{0,20}title')" "yes"
check "invariant: idempotent on repeated runs with no new commits" \
  "$(has_pattern_ci 'idempotent')" "yes"
check "invariant: reflects current state, not PR-creation-time state" \
  "$(has_pattern_ci 'creation time')" "yes"
check "invariant: works standalone" \
  "$(has_pattern_ci 'standalone')" "yes"
check "invariant: formatting conventions apply to every composed description regardless of content source" \
  "$(has_pattern_ci 'apply to every composed description|regardless of (the )?(content )?source|whatever the content source')" "yes"
check "invariant: no hard runtime dependency on another plugin" \
  "$(printf '%s' "$BODY" | grep -qiE 'requires (the )?(landing|lego|tracking|build) plugin|(landing|lego|tracking|build) plugin is required' && echo present || echo absent)" "absent"

# 12. Edge cases.
check "edge case: manual PR with no .local/ context uses diff + commit log alone" \
  "$(has_pattern_ci 'commit log alone')" "yes"
check "edge case: very large diff is summarized" \
  "$(has_pattern_ci 'large diff')" "yes"
check "edge case: generated description is authoritative over manual edits" \
  "$(has_pattern_ci 'authoritative')" "yes"
check "edge case: hard-wrapped existing description is reflowed" \
  "$(has_pattern_ci 'reflow')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
