#!/bin/bash
# Structural test for the per-worker skill (B03 skill-per-worker).
#
# Validates plugins/worktrees/skills/per-worker/SKILL.md against its own
# contract docblock:
#   - frontmatter: name "per-worker", a non-placeholder description carrying
#     the trigger context (parallel workers/subagents doing git writes;
#     handing a branch to another session), and model invocation left
#     enabled (no disable-model-invocation: true)
#   - body: the four required sections (Why isolation / When to use it /
#     Lifecycle / Hand-off examples), each with real content, plus the
#     semantic anchors the contract's Outputs clause calls out: the
#     one-branch-per-checkout rationale, the .bare/sequential-fallback
#     decision rule, the create -> record absolute path -> hand off ->
#     integrate -> clean up lifecycle (newtree/rmtree, --force only to
#     discard), at least two hand-off examples, a cross-reference to the
#     `usage` skill, and the two documented edge cases (dirty-worktree
#     refusal, directory-name-vs-branch-name at cleanup)
#   - the UNOPINIONATED invariant: no mandated orchestration framework/tool
#
# Anchor/section checks run against the body with the contract's own
# HTML-comment docblock stripped out (sed '/<!--/,/-->/d'), so the docblock
# text itself can never satisfy a check meant for the real prose.
#
# Run: bash plugins/worktrees/scripts/b03-per-worker-skill.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/per-worker/SKILL.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "SKILL.md exists at the contract's Code path" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

if [[ ! -f "$SKILL" ]]; then
  echo "FAILURES (skill file missing, cannot continue)"
  exit 1
fi

# --- fixtures -------------------------------------------------------------

# Frontmatter: the YAML block between the first two '---' lines.
FRONTMATTER=$(awk 'BEGIN{n=0} /^---$/{n++; next} n==1{print} n>=2{exit}' "$SKILL")

# Body: everything after the closing '---' of frontmatter.
BODY=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$SKILL")

# Anchor body: body with the contract's HTML-comment docblock stripped, so
# the docblock's own prose can never satisfy an anchor/section assertion —
# only real implementation content can.
ANCHOR_BODY=$(printf '%s\n' "$BODY" | sed '/<!--/,/-->/d')

# Extract a single "## <heading>" section's body from ANCHOR_BODY (text up
# to, but not including, the next "## " heading).
section() { # heading
  printf '%s\n' "$ANCHOR_BODY" | awk -v h="$1" '
    BEGIN{f=0}
    $0 ~ "^## " h "[[:space:]]*$" {f=1; next}
    /^## / {f=0}
    f {print}
  '
}

WHY=$(section "Why isolation")
WHEN=$(section "When to use it")
LIFECYCLE=$(section "Lifecycle")
HANDOFF=$(section "Hand-off examples")

# Collapse newlines (and repeated whitespace) to single spaces, so multi-word
# phrase checks below match regardless of where the prose happens to wrap —
# line-wrapping is a formatting choice the contract does not constrain.
flat() { printf '%s' "$1" | tr '\n' ' ' | tr -s '[:space:]' ' '; }

FWHY=$(flat "$WHY")
FWHEN=$(flat "$WHEN")
FLIFECYCLE=$(flat "$LIFECYCLE")
FHANDOFF=$(flat "$HANDOFF")
FANCHOR_BODY=$(flat "$ANCHOR_BODY")

# ===========================================================================
# Inputs: frontmatter carries the trigger context; model invocation enabled.
# ===========================================================================

NAME=$(printf '%s\n' "$FRONTMATTER" | grep -E '^name:' | head -1 | sed -E 's/^name:[[:space:]]*//; s/^"//; s/"$//')
check "frontmatter name is 'per-worker'" "$NAME" "per-worker"

DESC=$(printf '%s\n' "$FRONTMATTER" | grep -E '^description:' | head -1 | sed -E 's/^description:[[:space:]]*//; s/^"//; s/"$//')
FDESC=$(flat "$DESC")

check "description is not the TODO(B03) placeholder" \
  "$([[ "$DESC" == *'TODO(B03)'* ]] && echo placeholder || echo ok)" "ok"
check "description is non-empty" \
  "$([[ -n "$DESC" ]] && echo yes || echo no)" "yes"
check "description mentions parallel workers/subagents (trigger context)" \
  "$(printf '%s' "$FDESC" | grep -qiE 'parallel' && printf '%s' "$FDESC" | grep -qiE 'worker|subagent' && echo yes || echo no)" "yes"
check "description mentions git write actions (commit/branch/PR)" \
  "$(printf '%s' "$FDESC" | grep -qiE 'commit|branch|pull request|\bPR\b' && echo yes || echo no)" "yes"
check "description mentions handing off/handover to another session" \
  "$(printf '%s' "$FDESC" | grep -qiE 'hand(ing|s)?[-]?off|handover|another session' && echo yes || echo no)" "yes"

check "model invocation left enabled (no disable-model-invocation: true)" \
  "$(printf '%s\n' "$FRONTMATTER" | grep -qiE '^disable-model-invocation:[[:space:]]*true[[:space:]]*$' && echo disabled || echo enabled)" "enabled"

# ===========================================================================
# Outputs: required sections present, with real (non-placeholder) content.
# ===========================================================================

check "section 'Why isolation' present" \
  "$(printf '%s\n' "$ANCHOR_BODY" | grep -qE '^## Why isolation[[:space:]]*$' && echo yes || echo no)" "yes"
check "section 'When to use it' present" \
  "$(printf '%s\n' "$ANCHOR_BODY" | grep -qE '^## When to use it[[:space:]]*$' && echo yes || echo no)" "yes"
check "section 'Lifecycle' present" \
  "$(printf '%s\n' "$ANCHOR_BODY" | grep -qE '^## Lifecycle[[:space:]]*$' && echo yes || echo no)" "yes"
check "section 'Hand-off examples' present" \
  "$(printf '%s\n' "$ANCHOR_BODY" | grep -qE '^## Hand-off examples[[:space:]]*$' && echo yes || echo no)" "yes"

check "no leftover TODO(B03) placeholder text anywhere in the body" \
  "$(printf '%s\n' "$ANCHOR_BODY" | grep -q 'TODO(B03)' && echo present || echo absent)" "absent"

check "'Why isolation' section is non-empty (sanity check; content itself is verified below)" \
  "$(printf '%s\n' "$WHY" | grep -qv '^[[:space:]]*$' && echo yes || echo no)" "yes"
check "'When to use it' section is non-empty (sanity check; content itself is verified below)" \
  "$(printf '%s\n' "$WHEN" | grep -qv '^[[:space:]]*$' && echo yes || echo no)" "yes"
check "'Lifecycle' section is non-empty (sanity check; content itself is verified below)" \
  "$(printf '%s\n' "$LIFECYCLE" | grep -qv '^[[:space:]]*$' && echo yes || echo no)" "yes"
check "'Hand-off examples' section is non-empty (sanity check; content itself is verified below)" \
  "$(printf '%s\n' "$HANDOFF" | grep -qv '^[[:space:]]*$' && echo yes || echo no)" "yes"

# --- Why isolation: one-branch-per-checkout rationale ----------------------

check "'Why isolation' states a checkout has exactly one branch" \
  "$(printf '%s' "$FWHY" | grep -qiE 'one branch|single branch|exactly one' && echo yes || echo no)" "yes"
check "'Why isolation' names the race (wrong-branch commits / overwritten files)" \
  "$(printf '%s' "$FWHY" | grep -qiE 'race' && printf '%s' "$FWHY" | grep -qiE 'wrong[- ]branch' && printf '%s' "$FWHY" | grep -qiE 'overwrit' && echo yes || echo no)" "yes"
check "'Why isolation' notes read-only parallel work needs none of this" \
  "$(printf '%s' "$FWHY" | grep -qiE 'read[- ]only' && echo yes || echo no)" "yes"

# --- When to use it: .bare layout vs sequential fallback -------------------

check "'When to use it' ties worktree-root/.bare layout to one worktree per writing worker" \
  "$(printf '%s' "$FWHEN" | grep -qiE '\.bare' && printf '%s' "$FWHEN" | grep -qiE 'one worktree per' && echo yes || echo no)" "yes"
check "'When to use it' states the sequential fallback for non-worktree repos" \
  "$(printf '%s' "$FWHEN" | grep -qiE 'sequential' && echo yes || echo no)" "yes"

# --- Lifecycle: create / absolute path / hand off / integrate / clean up ---

check "'Lifecycle' documents create via newtree from the root" \
  "$(printf '%s' "$FLIFECYCLE" | grep -qiE 'newtree' && echo yes || echo no)" "yes"
check "'Lifecycle' requires recording the worktree's ABSOLUTE path" \
  "$(printf '%s' "$FLIFECYCLE" | grep -qiE 'absolute path' && echo yes || echo no)" "yes"
check "'Lifecycle' hand-off step gives the worker the branch name" \
  "$(printf '%s' "$FLIFECYCLE" | grep -qiE 'branch name' && echo yes || echo no)" "yes"
check "'Lifecycle' integrate step covers commit/push/PR from inside the worktree" \
  "$(printf '%s' "$FLIFECYCLE" | grep -qiE 'commit' && printf '%s' "$FLIFECYCLE" | grep -qiE 'push' && printf '%s' "$FLIFECYCLE" | grep -qiE 'pull request|\bPR\b' && echo yes || echo no)" "yes"
check "'Lifecycle' cleanup step uses rmtree" \
  "$(printf '%s' "$FLIFECYCLE" | grep -qiE 'rmtree' && echo yes || echo no)" "yes"
check "'Lifecycle' cleanup step restricts --force to intentional discards" \
  "$(printf '%s' "$FLIFECYCLE" | grep -qiE -- '--force' && printf '%s' "$FLIFECYCLE" | grep -qiE 'discard' && echo yes || echo no)" "yes"

# --- Hand-off examples: at least two, distinct styles -----------------------

check "hand-off examples include a subagent with an explicit working directory" \
  "$(printf '%s' "$FHANDOFF" | grep -qiE 'subagent' && printf '%s' "$FHANDOFF" | grep -qiE 'working directory|cwd' && echo yes || echo no)" "yes"
check "hand-off examples include a handover to a separate session/human" \
  "$(printf '%s' "$FHANDOFF" | grep -qiE 'session|human' && echo yes || echo no)" "yes"

# ===========================================================================
# Edge cases: dirty worktree at cleanup; dir-name vs branch-name confusion.
# ===========================================================================

check "documents rmtree refusing a dirty worktree" \
  "$(printf '%s' "$FANCHOR_BODY" | grep -qiE 'dirty' && printf '%s' "$FANCHOR_BODY" | grep -qiE 'refus' && echo yes || echo no)" "yes"
check "documents rmtree taking the dashed DIRECTORY name, not the branch name" \
  "$(printf '%s' "$FANCHOR_BODY" | grep -qiE 'directory name' && printf '%s' "$FANCHOR_BODY" | grep -qiE 'branch name' && echo yes || echo no)" "yes"

# ===========================================================================
# Invariants: cross-references `usage`; unopinionated about orchestration.
# ===========================================================================

check "cross-references the 'usage' skill for helper mechanics" \
  "$(printf '%s' "$FANCHOR_BODY" | grep -qiE '`usage`|usage skill' && echo yes || echo no)" "yes"

check "body does not reference the lego plugin's dispatch flow" \
  "$(printf '%s' "$FANCHOR_BODY" | grep -qiE 'lego|dispatch flow' && echo present || echo absent)" "absent"

check "body does not mandate a single hand-off style as the only valid one" \
  "$(printf '%s' "$FANCHOR_BODY" | grep -qiE 'must (always )?use (a )?subagent|only valid (way|approach)|the only way' && echo mandates || echo neutral)" "neutral"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
