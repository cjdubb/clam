#!/bin/bash
# Structural/anchor test for skills/usage/SKILL.md against Contract: B02
# skill-usage (see the HTML-comment docblock in that file). This skill is a
# documentation block, not executable code, so the tests here are:
#   - frontmatter checks (name, non-placeholder description carrying the
#     model-invocation trigger terms, model invocation left enabled)
#   - per-section anchor checks: each required section's rendered body (HTML
#     comments stripped, so the contract docblock's own prose can never
#     satisfy a check) must contain the stable terms/literals a faithful
#     implementation of that section could not avoid using
#   - negative invariants: no "./newtree" anywhere, no machine-specific
#     "/home/" paths in the rendered body
# These MUST fail against the current TODO(B02) stub and MUST pass once a
# real skill body satisfies the contract.
# Run: bash plugins/worktrees/scripts/b02-usage-skill.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/usage/SKILL.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Case-insensitive extended-regex presence check over a blob of text.
# `--` guards patterns that start with a dash (e.g. leading '-') from being
# parsed as grep options.
has() { # content pattern
  if grep -qiE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Fixed-string (literal) presence check, case-sensitive. `--` guards literals
# that start with a dash (e.g. '--force', '--configure') from being parsed
# as grep options.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi

RAW=$(cat "$SKILL")

# --- Frontmatter -------------------------------------------------------
# Lines strictly between the first two '---' delimiters.
FRONTMATTER=$(awk '/^---$/{n++; next} n==1' "$SKILL")
NAME=$(printf '%s\n' "$FRONTMATTER" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
DESC=$(printf '%s\n' "$FRONTMATTER" | grep '^description:' | sed -E 's/^description:[[:space:]]*//')

check "frontmatter name is 'usage'" "$NAME" "usage"
check "description is non-placeholder (no TODO)" "$(has "$DESC" 'TODO')" "no"
check "description carries trigger term 'newtree'" "$(has "$DESC" 'newtree')" "yes"
check "description carries trigger term 'worktree'" "$(has "$DESC" 'worktree')" "yes"
check "model invocation stays enabled (no disable-model-invocation key)" \
  "$(has "$FRONTMATTER" 'disable-model-invocation')" "no"

# --- Rendered body (HTML comments / contract docblock stripped) --------
# Anchor checks below must be satisfied by the skill's own prose, never by
# the contract comment, so strip any <!-- ... --> block(s) first.
BODY=$(sed '/<!--/,/-->/d' "$SKILL")

# Extract the text of one '## Exact Header' section (up to the next '## '
# header or EOF) from the rendered body.
section() { # exact_header
  awk -v h="$1" '
    $0 == h {found=1; next}
    /^## / {if (found) exit}
    found {print}
  ' <<<"$BODY"
}

# Required sections exist (headers already present in the stub; still a
# contract requirement, and the per-section extraction below depends on it).
for h in "## The worktree root" "## newtree" "## rmtree" "## copyenv" \
         "## cloneBareRepo" "## If the helpers are not available"; do
  check "required section exists: $h" "$(has_f "$BODY" "$h")" "yes"
done

ROOT_SECTION=$(section "## The worktree root")
NEWTREE_SECTION=$(section "## newtree")
RMTREE_SECTION=$(section "## rmtree")
COPYENV_SECTION=$(section "## copyenv")
CLONE_SECTION=$(section "## cloneBareRepo")
FALLBACK_SECTION=$(section "## If the helpers are not available")

# Also require every section body to have moved past the scaffold's literal
# TODO placeholder (belt-and-braces on top of the anchor checks below).
for pair in "worktree root:$ROOT_SECTION" "newtree:$NEWTREE_SECTION" \
            "rmtree:$RMTREE_SECTION" "copyenv:$COPYENV_SECTION" \
            "cloneBareRepo:$CLONE_SECTION" "fallback:$FALLBACK_SECTION"; do
  label="${pair%%:*}"; content="${pair#*:}"
  check "$label section body is not the TODO(B02) placeholder" \
    "$(has_f "$content" 'TODO(B02)')" "no"
done

# --- The worktree root --------------------------------------------------
check "root section mentions the .bare layout" "$(has_f "$ROOT_SECTION" '.bare')" "yes"
check "root section describes working from inside worktrees (not root-only)" \
  "$(has "$ROOT_SECTION" 'inside')" "yes"
check "root section explains root resolution (resolve/common git dir)" \
  "$(has "$ROOT_SECTION" 'resolv')" "yes"

# --- newtree -------------------------------------------------------------
check "newtree section: branch name keeps slashes" "$(has "$NEWTREE_SECTION" 'slash')" "yes"
check "newtree section: directory name uses dashes" "$(has "$NEWTREE_SECTION" 'dash')" "yes"
check "newtree section: existing origin/<branch> checked out with upstream set" \
  "$(has "$NEWTREE_SECTION" 'upstream')" "yes"
check "newtree section: default-branch fallback references origin/HEAD" \
  "$(has_f "$NEWTREE_SECTION" 'origin/HEAD')" "yes"
check "newtree section: default-branch fallback references git remote set-head" \
  "$(has "$NEWTREE_SECTION" 'set-head')" "yes"
check "newtree section: default-branch fallback references origin/master" \
  "$(has_f "$NEWTREE_SECTION" 'origin/master')" "yes"
check "newtree section: default-branch fallback warns" "$(has "$NEWTREE_SECTION" 'warn')" "yes"
check "newtree section: runs git fetch origin" "$(has_f "$NEWTREE_SECTION" 'git fetch origin')" "yes"
check "newtree section: origin remote is required" "$(has "$NEWTREE_SECTION" 'origin')" "yes"
check "newtree section: single-call composition cd <root> && newtree ..." \
  "$(has "$NEWTREE_SECTION" 'cd[^&]*&&[^&]*newtree')" "yes"
check "newtree section: teaches capturing the absolute path via pwd" \
  "$(has "$NEWTREE_SECTION" 'pwd')" "yes"
check "newtree section: existing worktree dir does not fail (warns instead)" \
  "$(has "$NEWTREE_SECTION" 'exist')" "yes"
check "newtree section: auto-runs copyenv when configured" \
  "$(has "$NEWTREE_SECTION" 'copyenv')" "yes"
check "newtree section: failed copyenv leaves the worktree KEPT" \
  "$(has "$NEWTREE_SECTION" 'kept')" "yes"
check "newtree section: covers the offline edge case" "$(has "$NEWTREE_SECTION" 'offline')" "yes"
check "newtree section: repo without copyenv config behaves as plain newtree" \
  "$(has "$NEWTREE_SECTION" 'plain')" "yes"

# --- rmtree ---------------------------------------------------------------
check "rmtree section: removal is by directory name" "$(has "$RMTREE_SECTION" 'director')" "yes"
check "rmtree section: contrasts directory name with branch name" \
  "$(has "$RMTREE_SECTION" 'branch')" "yes"
check "rmtree section: bare rmtree from inside a worktree removes that one" \
  "$(has "$RMTREE_SECTION" 'inside')" "yes"
check "rmtree section: leaves the shell at the root afterward" \
  "$(has "$RMTREE_SECTION" 'root')" "yes"
check "rmtree section: refuses dirty worktrees" "$(has "$RMTREE_SECTION" 'dirty')" "yes"
check "rmtree section: extra flags pass through to git worktree remove (--force)" \
  "$(has_f "$RMTREE_SECTION" '--force')" "yes"

# --- copyenv ---------------------------------------------------------------
check "copyenv section: --configure <source-dir> flag documented" \
  "$(has_f "$COPYENV_SECTION" '--configure')" "yes"
check "copyenv section: config stored in the shared .bare config" \
  "$(has_f "$COPYENV_SECTION" '.bare')" "yes"
check "copyenv section: paths are relative to both source dir and worktree" \
  "$(has "$COPYENV_SECTION" 'relative')" "yes"
check "copyenv section: 'both' locations called out for relative paths" \
  "$(has "$COPYENV_SECTION" 'both')" "yes"
check "copyenv section: existing files skipped unless --force" \
  "$(has "$COPYENV_SECTION" 'skip')" "yes"
check "copyenv section: --force flag documented" "$(has_f "$COPYENV_SECTION" '--force')" "yes"
check "copyenv section: --list flag documented (previews)" \
  "$(has_f "$COPYENV_SECTION" '--list')" "yes"
check "copyenv section: env files are secrets" "$(has "$COPYENV_SECTION" 'secret')" "yes"
check "copyenv section: destination must be gitignored" \
  "$(has "$COPYENV_SECTION" 'gitignor')" "yes"

# --- cloneBareRepo -----------------------------------------------------
check "cloneBareRepo section: one-time repo-to-worktree-root conversion" \
  "$(has "$CLONE_SECTION" 'convert')" "yes"
check "cloneBareRepo section: setup-git-repo-with-trees.sh named as the script equivalent" \
  "$(has_f "$CLONE_SECTION" 'setup-git-repo-with-trees.sh')" "yes"

# --- If the helpers are not available -----------------------------------
check "fallback section: try newtree directly first" "$(has "$FALLBACK_SECTION" 'directly')" "yes"
check "fallback section: locates the '# BEGIN GIT-HELPERS' managed block" \
  "$(has_f "$FALLBACK_SECTION" '# BEGIN GIT-HELPERS')" "yes"
check "fallback section: points at worktree-helpers.sh" \
  "$(has_f "$FALLBACK_SECTION" 'worktree-helpers.sh')" "yes"
check "fallback section: mentions shell rc files (.bashrc/.zshrc)" \
  "$(has "$FALLBACK_SECTION" '\.bashrc|\.zshrc')" "yes"
check "fallback section: never hardcodes paths / falls back to raw git worktree" \
  "$(has "$FALLBACK_SECTION" 'hardcod')" "yes"

# --- Invariants -----------------------------------------------------------
check "cross-references the per-worker skill (unopinionated about orchestration)" \
  "$(has_f "$BODY" 'per-worker')" "yes"
check "never recommends the literal './newtree'" "$(has_f "$BODY" './newtree')" "no"
check "no machine-specific /home/ absolute paths in the rendered body" \
  "$(has_f "$BODY" '/home/')" "no"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
