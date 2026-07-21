#!/bin/bash
# Structural/anchor test for skills/create/SKILL.md against the "Contract:
# B01 handover-plugin — skill" HTML-comment docblock in that file. This
# skill is a documentation/procedure block, not executable code, so the
# tests here are:
#   - frontmatter checks (name, non-placeholder description carrying the
#     model-invocation trigger terms, model invocation left enabled)
#   - anchor-term checks against the rendered body (HTML comment docblock
#     stripped, so the contract docblock's own prose can never satisfy a
#     check on its own): every Behavior/Inputs/Outputs/Errors/Invariants/
#     Edge-case clause must be addressed by the skill's own prose
#   - negative invariants: never "newcliptree", issue-tracker-agnostic
#     (no "Sub-Jira" / "CLIP-" / bare "Jira" as a hard dependency), no
#     machine-specific "/home/" paths
#
# The stub does not pre-scaffold section headings (unlike some sibling
# blocks) — its body is the literal placeholder "Not yet implemented." — so
# clause checks below are anchor-term based against the rendered body,
# never against a specific heading string, matching the contract's own
# vocabulary rather than an imagined heading scheme.
#
# These MUST fail against the current stub body and MUST pass once a real
# skill body satisfies the contract.
# Run: bash plugins/orchestrator-handover/scripts/b01-skill.test.sh
# (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/create/SKILL.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Case-insensitive extended-regex presence check. `--` guards patterns that
# start with a dash from being parsed as grep options.
has() { # content pattern
  if grep -qiE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Fixed-string (literal) presence check, case-sensitive.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi

RAW=$(cat "$SKILL")

# --- Frontmatter ---------------------------------------------------------
FRONTMATTER=$(awk '/^---$/{n++; next} n==1' "$SKILL")
NAME=$(printf '%s\n' "$FRONTMATTER" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
DESC=$(printf '%s\n' "$FRONTMATTER" | grep '^description:' | sed -E 's/^description:[[:space:]]*//')

FM_CLOSE_LINE=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$SKILL")
check "frontmatter parses (opens with a bare ---)" \
  "$([[ "$(sed -n '1p' "$SKILL")" == "---" ]] && echo yes || echo no)" "yes"
check "frontmatter parses (closes with a second bare ---)" \
  "$([[ -n "$FM_CLOSE_LINE" ]] && echo yes || echo no)" "yes"
check "frontmatter name is 'create'" "$NAME" "create"
check "description is non-empty" "$([[ -n "$DESC" ]] && echo yes || echo no)" "yes"
check "description is non-placeholder (no TODO/NotImplemented)" \
  "$(has "$DESC" 'TODO|NotImplemented')" "no"
check "description carries trigger term 'handover'" "$(has "$DESC" 'handover')" "yes"
check "description carries trigger term 'orchestrator'" "$(has "$DESC" 'orchestrator')" "yes"
check "description carries trigger term 'worktree'" "$(has "$DESC" 'worktree')" "yes"
check "skill name does not repeat the plugin name 'orchestrator-handover'" \
  "$(has "$NAME" 'orchestrator-handover')" "no"
check "model invocation stays enabled (no disable-model-invocation key)" \
  "$(has "$FRONTMATTER" 'disable-model-invocation')" "no"

# --- Rendered body (HTML comments / contract docblock stripped) ----------
# Anchor checks below must be satisfied by the skill's own prose, never by
# the contract comment, so strip any <!-- ... --> block(s) first. This also
# strips the docblock's own descriptive uses of "Jira", "CLIP", and
# "newcliptree" (which legitimately appear there as prose about what to
# avoid), so the issue-tracker-agnostic / no-newcliptree checks below can't
# pass vacuously off the docblock's own text.
BODY=$(sed '/<!--/,/-->/d' "$SKILL")

check "rendered body has moved past the 'Not yet implemented' placeholder" \
  "$(has "$BODY" 'not yet implemented')" "no"

# --- Behavior: four-step procedure ----------------------------------------
check "documents /orchestrator-handover:create as the invoked command" \
  "$(has_f "$BODY" '/orchestrator-handover:create')" "yes"

# Step 1: write handover doc to current worktree's .local/ using template.md
check "step 1: writes a handover doc under .local/" \
  "$(has "$BODY" '\.local/')" "yes"
check "step 1: references the companion template.md" \
  "$(has_f "$BODY" 'template.md')" "yes"

# Step 2: create recipient worktree via newtree; populate .local/ (handover
# copy, MODE=Build, empty .orchestrator marker)
check "step 2: uses newtree to create the recipient worktree" \
  "$(has_f "$BODY" 'newtree')" "yes"
MODE_MENTIONED=$(has "$BODY" 'MODE')
BUILD_MENTIONED=$(has "$BODY" 'Build')
check "step 2: sets MODE to Build in the recipient" \
  "$([[ "$MODE_MENTIONED" == yes && "$BUILD_MENTIONED" == yes ]] && echo yes || echo no)" "yes"
check "step 2: creates an empty .orchestrator marker" \
  "$(has_f "$BODY" '.orchestrator')" "yes"

# Step 3: write placeholder TODO.md in recipient's .local/ using the
# tracking plugin's template format
check "step 3: writes a TODO.md into the recipient's .local/" \
  "$(has_f "$BODY" 'TODO.md')" "yes"
check "step 3: references the tracking plugin's template format" \
  "$(has "$BODY" 'tracking')" "yes"

# Step 4: report the created path and hand off to the user
check "step 4: reports the created path to the user" \
  "$(has "$BODY" 'report')" "yes"
check "step 4: hands off to the user (never starts the session itself)" \
  "$(has "$BODY" 'hand.?off|hands off')" "yes"

# --- Inputs ----------------------------------------------------------------
check "inputs: requires an issue key or descriptive slug" \
  "$(has "$BODY" 'slug')" "yes"
check "inputs: requires enough session context for the handover sections" \
  "$(has "$BODY" 'context')" "yes"

# --- Outputs -----------------------------------------------------------------
check "outputs: provenance copy at .local/handover-{ISSUE-KEY}.md (or slug) in the current worktree" \
  "$(has "$BODY" '\.local/handover-')" "yes"
check "outputs: recipient worktree named orchestrate-{ISSUE-KEY}-{short-description}" \
  "$(has "$BODY" 'orchestrate-')" "yes"
check "outputs: recipient .local/ carries local artifacts referenced by the handover's source-of-truth section" \
  "$(has "$BODY" 'source.of.truth')" "yes"

# --- Errors ------------------------------------------------------------------
check "errors: worktree creation failure aborts immediately" \
  "$(has "$BODY" 'abort')" "yes"
check "errors: failure is surfaced to the user" \
  "$(has "$BODY" 'surface')" "yes"
check "errors: never leaves a half-populated directory behind" \
  "$(has "$BODY" 'half.populated')" "yes"

# --- Invariants --------------------------------------------------------------
check "invariant: never starts a session in the recipient worktree (human-start gate)" \
  "$(has "$BODY" 'never start')" "yes"
check "invariant: only the user runs clam / picks Build (human-start gate, phrased)" \
  "$(has "$BODY" 'user')" "yes"
check "invariant: never writes content into .orchestrator (empty marker only)" \
  "$(has "$BODY" 'empty')" "yes"
check "invariant: never pre-populates PLAN.md in the recipient" \
  "$(has_f "$BODY" 'PLAN.md')" "yes"
check "invariant: never pre-populates IMPLEMENTATION-PLAN.md in the recipient" \
  "$(has_f "$BODY" 'IMPLEMENTATION-PLAN.md')" "yes"
check "invariant: PLAN.md / IMPLEMENTATION-PLAN.md are never pre-populated (phrased as such)" \
  "$(has "$BODY" 'never pre-populat')" "yes"
check "invariant: never delegates any scaffolding step to a subagent" \
  "$(has "$BODY" 'subagent')" "yes"
check "invariant: never delegates (phrased as such, not merely mentioning subagent)" \
  "$(has "$BODY" 'never delegat')" "yes"
check "invariant: issue-tracker-agnostic (works with GitHub Issues, Linear, Jira, or none)" \
  "$(has "$BODY" 'issue-tracker-agnostic|tracker.agnostic')" "yes"
check "invariant: always uses newtree, never newcliptree" \
  "$(has_f "$BODY" 'newcliptree')" "no"
check "invariant: worktree creation runs in a subshell (cwd never drifts)" \
  "$(has "$BODY" 'subshell')" "yes"
check "invariant: step 2's bash commands run in a single shell invocation" \
  "$(has "$BODY" 'single shell invocation|single invocation|one shell')" "yes"

# --- Edge cases ----------------------------------------------------------
check "edge case: no issue tracker -> slug-based naming (orchestrate/{short-description})" \
  "$(has_f "$BODY" 'orchestrate/')" "yes"
check "edge case: tracking plugin not installed -> skill inlines essential TODO.md fields" \
  "$(has "$BODY" 'inline')" "yes"
check "edge case: session-modes plugin absent -> recipient first move documents manual pickup" \
  "$(has "$BODY" 'manual')" "yes"
check "edge case: recipient worktree dir already exists -> newtree warns and navigates (not a failure)" \
  "$(has "$BODY" 'already exists')" "yes"
check "edge case: cross-repo sub-effort is possible, default assumes same repo" \
  "$(has "$BODY" 'cross-repo|same repo')" "yes"

# --- Issue-tracker-agnostic language (negative checks) ---------------------
check "never uses the Jira-specific term 'Sub-Jira'" "$(has "$BODY" 'sub-jira')" "no"
check "never uses Jira-specific 'CLIP-' ticket-key style references" "$(has "$BODY" 'CLIP-[0-9]')" "no"

# --- References worktrees plugin for newtree mechanics ---------------------
check "references the worktrees plugin for newtree mechanics" \
  "$(has "$BODY" 'worktrees')" "yes"

# --- No machine-specific absolute paths -------------------------------------
check "no machine-specific /home/ or /Users/ absolute paths in the rendered body" \
  "$(has "$BODY" '/(home|Users)/[A-Za-z0-9_.-]+')" "no"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
