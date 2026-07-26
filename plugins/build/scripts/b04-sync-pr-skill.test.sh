#!/bin/bash
# Structural test for the sync-pr skill (B04 pr-description-sync-skill).
#
# Validates plugins/deliver/skills/sync-pr/SKILL.md against its own contract
# docblock (see the HTML comment in that file). This is a guidance document,
# not executable code, so every check here is a document-shape / anchor-text
# assertion (never prose quality):
#
#   - frontmatter: fenced by '---', has 'name' and 'description' keys, name
#     is literally "sync-pr", description non-empty
#   - references the three forge operations: gh pr list, gh pr view,
#     gh pr edit
#   - documents the six steps: detect the PR, read its current state,
#     gather context (diff/plan/verification/commit log), resolve the body
#     template, compose the updated description, apply the update
#   - never references internal workflow terminology (lego, unit IDs, block
#     IDs, plan slugs, block-map syntax) anywhere in the rendered body —
#     checked with the contract's own HTML-comment docblock stripped out
#     first, since the docblock itself names these terms to state the
#     invariant and must never be what satisfies (or defeats) this check
#   - documents error handling: no open PR is a stop-and-report (not an
#     error), gh CLI unavailable/unauthenticated points at remediation
#   - documents the invariants: never creates a PR, never modifies the PR
#     title, idempotent (running twice with no changes yields the same
#     description)
#
# Phrase checks run against a flattened (newline-collapsed) copy of the body
# so multi-word phrases can't be missed purely because prose happens to wrap
# across lines.
#
# These MUST fail against the current `NotImplemented: B04` stub body and
# MUST pass once a real skill body satisfies the contract.
# Run: bash plugins/deliver/scripts/b04-sync-pr-skill.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/sync-pr/SKILL.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Case-insensitive extended-regex presence check over a blob of text.
has() { # content pattern
  if grep -qiE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Fixed-string (literal) presence check, case-insensitive.
has_f() { # content literal
  if grep -qiF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Collapse newlines/whitespace to single spaces so multi-word phrase checks
# match regardless of where the prose happens to wrap.
flat() { printf '%s' "$1" | tr '\n' ' ' | tr -s '[:space:]' ' '; }

check "SKILL.md exists at the contract's Code path" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

if [[ ! -f "$SKILL" ]]; then
  echo "FAILURES (skill file missing, cannot continue)"
  exit 1
fi

# --- fixtures ---------------------------------------------------------------

FIRST_LINE=$(head -n1 "$SKILL")
DASH_LINE_COUNT=$(grep -cE '^---[[:space:]]*$' "$SKILL")

# Frontmatter: the YAML block between the first two '---' lines.
FRONTMATTER=$(awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1{print} n>=2{exit}' "$SKILL")

# Body: everything after the closing '---' of frontmatter.
BODY=$(awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n>=2{print}' "$SKILL")

# Anchor body: body with the contract's HTML-comment docblock stripped, so
# the docblock's own prose (which *names* the banned internal-terminology
# words in order to state the invariant) can never satisfy or defeat an
# anchor assertion — only real implementation content can.
ANCHOR_BODY=$(printf '%s\n' "$BODY" | sed '/<!--/,/-->/d')
FANCHOR_BODY=$(flat "$ANCHOR_BODY")

# ===========================================================================
# Frontmatter: fenced by ---, name + description keys present.
# ===========================================================================

check "file opens with a '---' frontmatter fence" "$FIRST_LINE" "---"
check "at least two '---' fence lines delimit frontmatter" \
  "$([[ "$DASH_LINE_COUNT" -ge 2 ]] && echo yes || echo no)" "yes"

FM_KEYS=$(printf '%s\n' "$FRONTMATTER" | grep -oE '^[A-Za-z_][A-Za-z0-9_-]*:' | sed 's/:$//' | sort -u)
check "frontmatter includes a 'name' key" \
  "$(printf '%s\n' "$FM_KEYS" | grep -qx 'name' && echo yes || echo no)" "yes"
check "frontmatter includes a 'description' key" \
  "$(printf '%s\n' "$FM_KEYS" | grep -qx 'description' && echo yes || echo no)" "yes"

NAME=$(printf '%s\n' "$FRONTMATTER" | grep -E '^name:' | head -1 | sed -E 's/^name:[[:space:]]*//; s/^"//; s/"$//')
check "frontmatter name is 'sync-pr'" "$NAME" "sync-pr"

DESC=$(printf '%s\n' "$FRONTMATTER" | grep -E '^description:' | head -1 | sed -E 's/^description:[[:space:]]*//')
check "description is non-empty" "$([[ -n "$DESC" ]] && echo yes || echo no)" "yes"

# ===========================================================================
# Forge operations: gh pr list, gh pr view, gh pr edit.
# ===========================================================================

check "references 'gh pr list' (detecting the open PR)" \
  "$(has_f "$FANCHOR_BODY" 'gh pr list')" "yes"
check "references 'gh pr view' (reading current PR state)" \
  "$(has_f "$FANCHOR_BODY" 'gh pr view')" "yes"
check "references 'gh pr edit' (applying the updated description)" \
  "$(has_f "$FANCHOR_BODY" 'gh pr edit')" "yes"

# ===========================================================================
# The six documented steps.
# ===========================================================================

check "documents detecting the current branch's open PR" \
  "$(has "$FANCHOR_BODY" 'open pr')" "yes"
check "documents reading the PR's current/existing description state" \
  "$(has "$FANCHOR_BODY" 'current (state|description)|existing description')" "yes"
check "documents gathering the diff against the merge target" \
  "$(has "$FANCHOR_BODY" 'diff')" "yes"
check "documents gathering plan context (.local/PLAN.md or .local/plans/)" \
  "$(has_f "$FANCHOR_BODY" 'PLAN.md')" "yes"
check "documents gathering verification results" \
  "$(has "$FANCHOR_BODY" 'verif')" "yes"
check "documents gathering the commit log/history" \
  "$(has "$FANCHOR_BODY" 'commit (log|history)')" "yes"
check "documents resolving a PR body template (standard path or default fallback)" \
  "$(has "$FANCHOR_BODY" 'template')" "yes"
check "documents composing the updated description" \
  "$(has "$FANCHOR_BODY" 'compose')" "yes"
check "documents applying the update to the PR" \
  "$(has "$FANCHOR_BODY" 'apply')" "yes"

# ===========================================================================
# Invariant: never references internal workflow terminology anywhere in the
# rendered (docblock-stripped) body.
# ===========================================================================

check "body never mentions 'lego'" \
  "$(has "$FANCHOR_BODY" 'lego')" "no"
check "body never mentions 'block-map'" \
  "$(has "$FANCHOR_BODY" 'block-map')" "no"
check "body never mentions 'plan slug'" \
  "$(has "$FANCHOR_BODY" 'plan slug')" "no"
check "body never mentions a bare lego-style unit/block ID token (e.g. U01, B04)" \
  "$(has "$FANCHOR_BODY" '\b[UB][0-9]{2}\b')" "no"

# ===========================================================================
# Error handling: no open PR (not an error), gh CLI unavailable/unauthed.
# ===========================================================================

check "documents no-open-PR as a stop-and-report, non-error condition" \
  "$(has "$FANCHOR_BODY" 'no open pr')$(has "$FANCHOR_BODY" 'not an error')" "yesyes"
check "documents gh CLI unavailable/unauthenticated with remediation guidance" \
  "$(has "$FANCHOR_BODY" 'gh auth login')" "yes"

# ===========================================================================
# Invariants: never creates a PR, never modifies the title, idempotent.
# ===========================================================================

check "documents the never-creates-a-PR invariant" \
  "$(has "$FANCHOR_BODY" 'never creat(e|es) (a )?pr')" "yes"
check "documents the never-modifies-the-title invariant" \
  "$(has "$FANCHOR_BODY" 'never modif(y|ies) (the )?(pr )?title')" "yes"
check "documents the idempotent invariant" \
  "$(has "$FANCHOR_BODY" 'idempotent')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
