#!/bin/bash
# Structural test for the B05 forge-github create-pr skill
# (plugins/forge-github/skills/create-pr/SKILL.md). The skill body is
# prose instructions, not executable code, so this test checks for the
# presence of the contract's required clauses (the seven steps,
# formatting conventions, errors, invariants, edge cases), not exact
# wording.
#
# All content checks (except the frontmatter and the global
# NotImplemented check) run against the file with its HTML comment block
# (the contract docblock) stripped out first. The docblock already
# states every required clause verbatim, so a check against the raw file
# could pass on the unimplemented stub for the wrong reason -- it would
# be satisfied by the docblock's own description of what to write, never
# by the actual skill body. Stripping ensures every clause check can only
# be satisfied by the real skill content that replaces the
# "NotImplemented: B05" marker.
# Run: bash plugins/forge-github/scripts/create-pr.test.sh (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$PLUGIN_DIR/skills/create-pr/SKILL.md"

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
  # (e.g. "flowing-prose formatting conventions"), so leaving it in would
  # make those checks pass on the unimplemented stub for the wrong reason.
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
  # for the wrong reason. Portable ERE rather than a PCRE lookbehind
  # ("grep -P" is unavailable on BSD/macOS grep): require either
  # start-of-line or a single non-'/' character before the filename.
  printf '%s' "$FLAT_BODY" | grep -qE -- "(^|[^/])$1" && echo yes || echo no
}

check "skill file exists" "$([[ -f "$SKILL" ]] && echo yes || echo no)" "yes"

# 0. Frontmatter shape (stable metadata, unaffected by implementation).
check "frontmatter name is create-pr" \
  "$(grep -m1 '^name:' "$SKILL" 2>/dev/null | sed 's/^name: *//')" "create-pr"

# 1. No NotImplemented marker in the rendered skill body (docblock-stripped,
#    marker included). This is the red/green gate: fails until the marker
#    is replaced by the real skill body.
check "no NotImplemented marker in skill body" \
  "$(has_pattern_ci 'NotImplemented')" "no"

# 2. Step 1 -- preflight: gh available/authenticated, origin resolves to a
#    GitHub remote; either failing reports remediation and stops.
check "preflight: gh auth status check documented" \
  "$(has_pattern_ci 'gh auth status')" "yes"
check "preflight: origin-not-a-GitHub-remote failure documented" \
  "$(has_pattern_ci 'not a github remote')" "yes"
check "preflight: remediation example (gh auth login) documented" \
  "$(has_pattern_ci 'gh auth login')" "yes"

# 3. Step 2 -- duplicate check: existing open PR is reported, sync-pr
#    suggested, no duplicate created.
check "duplicate check: existing-open-PR handling documented" \
  "$(has_pattern_ci 'duplicate')" "yes"
check "duplicate check: points at the sync-pr skill" \
  "$(has_literal 'sync-pr')" "yes"
check "duplicate check: detection via gh pr list --head <branch> --state open documented" \
  "$(has_literal 'gh pr list')" "yes"

# 4. Step 3 -- push.
check "push step: git push -u origin documented" \
  "$(has_literal 'git push -u origin')" "yes"

# 5. Step 4 -- template resolution: invoker template wins; else repo
#    templates checked case-sensitively in the specified order; else the
#    default structure.
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
check "template resolution: repo templates checked case-sensitively documented" \
  "$(has_pattern_ci 'case.sensitiv')" "yes"
check "template resolution: repo templates checked in the specified order documented" \
  "$(has_pattern_ci '\bin order\b')" "yes"
check "template resolution: default structure includes ## Summary" \
  "$(has_literal '## Summary')" "yes"
check "template resolution: default structure includes ## Why" \
  "$(has_literal '## Why')" "yes"
check "template resolution: default structure includes ## Changes" \
  "$(has_literal '## Changes')" "yes"
check "template resolution: default structure includes ## Verification" \
  "$(has_literal '## Verification')" "yes"

# 6. Step 5 -- compose title/body from invoker content or repo context
#    (plan docs, verification records, commit log, diff).
check "compose: reads .local/PLAN.md as repo context" \
  "$(has_literal '.local/PLAN.md')" "yes"
check "compose: reads .local/TODO.md as repo context" \
  "$(has_literal 'TODO.md')" "yes"
check "compose: uses the commit log (git log)" \
  "$(has_literal 'git log')" "yes"
check "compose: uses the diff (git diff)" \
  "$(has_literal 'git diff')" "yes"
check "compose: explicit invoker title/body/base arguments win over repo context" \
  "$(has_pattern_ci 'explicit.{0,60}(argument|title|body|base).{0,60}(win|take precedence|override|take priority)')" "yes"
check "compose: absence of optional repo context is normal, not an error" \
  "$(has_pattern_ci 'absence of optional.{0,30}context.{0,20}(normal|not an error)')" "yes"

# 7. Step 6 -- create: gh pr create, base branch resolution.
check "create step: gh pr create documented" \
  "$(has_literal 'gh pr create')" "yes"
check "create step: default-branch base resolution documented" \
  "$(has_pattern_ci 'default branch')" "yes"

# 8. Step 7 -- report the PR URL.
check "report step: PR URL reported" \
  "$(has_pattern_ci 'PR URL')" "yes"

# 9. Formatting conventions (own the fix for hard-wrapped PR prose).
check "formatting: flowing-paragraph convention" \
  "$(has_pattern_ci 'flowing')" "yes"
check "formatting: never-hard-wrapped convention" \
  "$(has_pattern_ci 'hard-wrap')" "yes"
check "formatting: structural-boundary line-break convention" \
  "$(has_pattern_ci 'structural boundar')" "yes"
check "formatting: imperative one-line title convention" \
  "$(has_pattern_ci 'imperative')" "yes"
check "formatting: no-trailing-period title convention" \
  "$(has_pattern_ci 'trailing period')" "yes"
check "formatting: reviewer-facing description convention" \
  "$(has_pattern_ci 'reviewer')" "yes"
check "formatting: no internal workflow terminology convention" \
  "$(has_pattern_ci 'workflow terminology')" "yes"

# 10. Errors.
check "error: no commits ahead of the base" \
  "$(has_pattern_ci 'no commits ahead')" "yes"
check "error: gh pr create failure is reported without retry" \
  "$(has_pattern_ci 'do not retry')" "yes"

# 11. Invariants.
check "invariant: never merges the PR" \
  "$(has_pattern_ci 'never merges')" "yes"
check "invariant: never force-pushes" \
  "$(has_pattern_ci 'force-push')" "yes"
check "invariant: never modifies the branch" \
  "$(has_pattern_ci 'never modifies.{0,20}branch')" "yes"
check "invariant: works standalone" \
  "$(has_pattern_ci 'standalone')" "yes"
check "invariant: formatting conventions apply to every composed description regardless of content source" \
  "$(has_pattern_ci 'apply to every composed description|regardless of (the )?(content )?source|whatever the content source')" "yes"
check "invariant: no hard runtime dependency on another plugin" \
  "$(printf '%s' "$BODY" | grep -qiE 'requires (the )?(landing|lego|tracking|build) plugin|(landing|lego|tracking|build) plugin is required' && echo present || echo absent)" "absent"

# 12. Edge cases.
check "edge case: detached HEAD / on the default branch itself" \
  "$(has_pattern_ci 'detached head')" "yes"
check "edge case: very large diff is summarized, not pasted in full" \
  "$(has_pattern_ci 'large diff')" "yes"
check "edge case: hard-wrapped invoker body is reflowed" \
  "$(has_pattern_ci 'reflow')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
