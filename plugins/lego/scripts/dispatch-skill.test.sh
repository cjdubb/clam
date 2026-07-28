#!/bin/bash
# Structural/anchor test for skills/dispatch/SKILL.md against Contract: B02
# dispatch-skill-file-protocol (see
# .local/contracts/B02-dispatch-skill-file-protocol.md). This skill is a
# documentation block, not executable code, so the tests here are:
#   - "Required literal tokens": each token from the contract's list must
#     appear verbatim (fixed-string grep) in the target file.
#   - "Invariants": each heading the contract requires to survive the edit
#     must still exist.
#   - Frontmatter: `name: dispatch` is unchanged.
# These MUST fail against the current (pre-B02) SKILL.md for the token
# checks, and MUST pass once a real edit satisfies the contract's Behavior
# clauses. This file does not test prose semantics beyond tokens/headings —
# meaning is verified by the orchestrator at acceptance.
# Run: bash plugins/lego/scripts/dispatch-skill.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/dispatch/SKILL.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Fixed-string (literal) presence check, case-sensitive. `--` guards literals
# that start with a dash from being parsed as grep options.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi

RAW=$(cat "$SKILL")

# --- Frontmatter ---------------------------------------------------------
# Lines strictly between the first two '---' delimiters.
FRONTMATTER=$(awk '/^---$/{n++; next} n==1' "$SKILL")
NAME=$(printf '%s\n' "$FRONTMATTER" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')

check "frontmatter name is 'dispatch'" "$NAME" "dispatch"

# --- Required literal tokens (contract: "Required literal tokens") -------
# Each token below must appear verbatim in the target file. One assertion
# per token, fixed-string (non-regex) match, so no token's own regex
# metacharacters (e.g. '<', '>') need escaping.
check "token: ## Worker briefs" \
  "$(has_f "$RAW" '## Worker briefs')" "yes"
check "token: ## Unit status file" \
  "$(has_f "$RAW" '## Unit status file')" "yes"
check "token: .local/briefs/NN-<wave>-<blocks>.md" \
  "$(has_f "$RAW" '.local/briefs/NN-<wave>-<blocks>.md')" "yes"
check "token: .local/reports/NN-<wave>-<blocks>.md" \
  "$(has_f "$RAW" '.local/reports/NN-<wave>-<blocks>.md')" "yes"
check "token: .local/status.md" \
  "$(has_f "$RAW" '.local/status.md')" "yes"
check "token: read the brief file first" \
  "$(has_f "$RAW" 'read the brief file first')" "yes"
check "token: orchestrator-owned" \
  "$(has_f "$RAW" 'orchestrator-owned')" "yes"
check "token: a stale status file is a defect" \
  "$(has_f "$RAW" 'a stale status file is a defect')" "yes"

# --- Invariants (contract: "Invariants" heading list) ---------------------
# These headings must survive the edit unchanged.
for h in "## The per-unit pipeline" "### 1. Create the worktree" \
         "### 2. Test wave" "### 3. Implementation wave" \
         "### 4. Local merge" "### 5. Delivery" "## Escalation loop" \
         "## Engineer-owned blocks" "## Done"; do
  check "invariant heading survives: $h" "$(has_f "$RAW" "$h")" "yes"
done

# --- Manifest delivery content (contract: B01 dispatch-delivery-instructions)
# Anchors the Step 5 sub-sections (5a compose, 5b write manifest + deliver)
# and their required content, so a future edit that clobbers this section
# fails the test suite instead of silently regressing.
check "token: #### 5a. Compose PR content" \
  "$(has_f "$RAW" '#### 5a. Compose PR content')" "yes"
check "token: #### 5b. Write manifest and deliver" \
  "$(has_f "$RAW" '#### 5b. Write manifest and deliver')" "yes"
check "token: --manifest .local/pr-manifest.json" \
  "$(has_f "$RAW" '--manifest .local/pr-manifest.json')" "yes"
check "token: pr-body-template.md" \
  "$(has_f "$RAW" 'pr-body-template.md')" "yes"
check "token: merge master into the integration branch before delivery" \
  "$(has_f "$RAW" 'merge master into the integration branch before delivery')" "yes"

# --- Pipe-safety guidance content (contract: B01 exit-code-pipe-safety) --
# The contract's own scaffold docblocks are embedded as HTML comments at
# both insertion points (search SKILL.md for "Contract: B01"); they
# describe what the guidance must say, but are not the guidance itself.
# Strip HTML comments before matching so a comment's vocabulary can never
# satisfy these checks — only real prose counts. Then scope each check to
# its own step's section (via the same headings the "Invariants" loop above
# already guarantees survive) so "coverage at both 2.3 and 3.1" is verified
# per-location, not just once anywhere in the file.
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")
SECTION_2_3=$(awk '/^### 2\. Test wave$/{flag=1; next} /^### 3\. Implementation wave$/{flag=0} flag' <<<"$STRIPPED")
SECTION_3_1=$(awk '/^### 3\. Implementation wave$/{flag=1; next} /^### 4\. Local merge$/{flag=0} flag' <<<"$STRIPPED")

# Step 2.3 (red run): the warning must name `$?` and explain that piping
# replaces it with the pipe tail's exit code, not the test command's.
check "2.3: warning names \$? and the piping hazard" \
  "$(has_f "$SECTION_2_3" 'replaces `$?`')" "yes"
check "2.3: warning identifies which exit code wins" \
  "$(has_f "$SECTION_2_3" 'exit code of the last pipeline stage')" "yes"

# Step 2.3: canonical snippet invariant — never a pipe when the exit code
# matters (semicolons/separate commands instead). Anchored without a
# leading "no"/"never" so a sentence-initial capital on that word doesn't
# break the case-sensitive match.
check "2.3: canonical snippet states no pipe when exit code matters" \
  "$(has_f "$SECTION_2_3" 'pipe when the exit code matters')" "yes"

# Step 2.3 edge case: output redirection is safe and must not be
# prohibited — only piping affects `$?`, redirection does not. Anchored
# without the leading "does"/"Does" for the same case-sensitivity reason.
check "2.3: redirection explicitly not prohibited" \
  "$(has_f "$SECTION_2_3" 'not affect `$?`')" "yes"

# Step 2.3 invariant: pipefail must not be relied on as the fix (not
# guaranteed in the orchestrator's ad-hoc commands). Anchored on "not rely
# on `pipefail`" rather than "do not ..." so a sentence-initial "Do not" (or
# "must not", "does not") still matches — case-sensitive grep would miss a
# capitalized sentence opener otherwise.
check "2.3: pipefail not relied on as the fix" \
  "$(has_f "$SECTION_2_3" 'not rely on `pipefail`')" "yes"

# Step 3.1 (green run): the contract allows the same warning inline OR a
# cross-reference to step 2.3 — either satisfies it, so accept the labeled
# term or a full restatement of the core warning. The green run masking a
# false acceptance is the higher-stakes case, so this location must not be
# skipped.
STEP_3_1_COVERED="no"
if grep -qF -- "pipe-safety" <<<"$SECTION_3_1" || \
   grep -qF -- 'replaces `$?`' <<<"$SECTION_3_1"; then
  STEP_3_1_COVERED="yes"
fi
check "3.1: pipe-safety warning present inline or by cross-reference" \
  "$STEP_3_1_COVERED" "yes"

# Edge case: PIPESTATUS, if mentioned anywhere in the new guidance, must be
# flagged bash-specific and not the preferred pattern. Vacuously satisfied
# if the implementer never brings PIPESTATUS up at all — the contract does
# not require mentioning it, only conditions what must accompany it.
PIPESTATUS_OK="yes"
if grep -qF -- "PIPESTATUS" <<<"$SECTION_2_3$SECTION_3_1"; then
  PIPESTATUS_OK="$(has_f "$SECTION_2_3$SECTION_3_1" 'bash-specific')"
fi
check "PIPESTATUS, if mentioned, flagged bash-specific" "$PIPESTATUS_OK" "yes"


# --- Teammate teardown content (contract: B01 dispatch-teammate-teardown) --
# The contract's own scaffold docblock is embedded as an HTML comment at four
# insertion points (search SKILL.md for "Contract: B01 dispatch-teammate-
# teardown"); it describes what the new prose must say, but is not the prose
# itself. Reuse $STRIPPED (built above for the pipe-safety checks) so the
# comment's own vocabulary — "TaskStop", "teammate", "best-effort",
# "disposable" — can never satisfy these checks; only real prose counts.
#
# Scope each check to the specific section the contract places it in — the
# naming rule in "## Worker briefs" (insertion point 1), the test-writer
# release at the end of "### 2. Test wave" on the accepted path (insertion
# point 2), the implementer release in "### 4. Local merge" (insertion point
# 3), and the Timeline addition in "## Unit status file" (insertion point
# 4) — same technique as the pipe-safety "coverage at both 2.3 and 3.1"
# checks above, so a file-wide token can't be satisfied by only one of the
# two release points the contract actually requires.
#
# Some contract clauses are about meaning, not tokens (which text a wrong
# implementation could still contain and read as satisfying); those are left
# to the orchestrator's read at acceptance rather than given a check here
# that would pass regardless of whether the meaning is right. See this
# wave's report for which clauses those are.
#
# has_f is newline-sensitive: this file's prose wraps at ~80 columns, so a
# multi-word literal (e.g. "accepted path") can have its own words land on
# opposite sides of a source line break, and a plain fixed-string match
# against the unwrapped section text would then miss prose that reads
# correctly to a human. has_fn (fixed-string, wrap-tolerant) collapses
# whitespace runs — including newlines — to a single space first. Used only
# for this block's new checks below; existing checks above are untouched.
has_fn() { # content literal
  local flat; flat=$(tr '\n' ' ' <<<"$1" | tr -s ' ')
  if grep -qF -- "$2" <<<"$flat"; then echo yes; else echo no; fi
}

WORKER_BRIEFS=$(awk '/^## Worker briefs$/{flag=1; next} /^## Unit status file$/{flag=0} flag' <<<"$STRIPPED")
SECTION_4=$(awk '/^### 4\. Local merge$/{flag=1; next} /^### 5\. Delivery$/{flag=0} flag' <<<"$STRIPPED")
UNIT_STATUS=$(awk '/^## Unit status file$/{flag=1; next} /^## Dispatch order$/{flag=0} flag' <<<"$STRIPPED")

# -- Worker briefs: the naming rule (clause a) --
check "Worker briefs: teammate name shape stated literally" \
  "$(has_fn "$WORKER_BRIEFS" '<unit-id>-<wave>-<NN>')" "yes"
check "Worker briefs: teammate name example given" \
  "$(has_fn "$WORKER_BRIEFS" 'U04-test-03')" "yes"
check "Worker briefs: every dispatch passes a teammate name" \
  "$(has_fn "$WORKER_BRIEFS" 'teammate name')" "yes"
check "Worker briefs: NN ties a release to its brief/report pair" \
  "$(has_fn "$WORKER_BRIEFS" 'traceable')" "yes"

# -- Test wave, accepted path: release the test-writer(s) (clauses b, d-g) --
check "2. Test wave: test-writer teammate(s) released" \
  "$(has_fn "$SECTION_2_3" 'test-writer teammate')" "yes"
check "2. Test wave: release covers teammate(s), not just one" \
  "$(has_fn "$SECTION_2_3" 'teammate(s)')" "yes"
check "2. Test wave: release scoped to the accepted path" \
  "$(has_fn "$SECTION_2_3" 'accepted path')" "yes"
check "2. Test wave: TaskStop is the named mechanism" \
  "$(has_fn "$SECTION_2_3" 'TaskStop')" "yes"
check "2. Test wave: teammate name passed as task_id" \
  "$(has_fn "$SECTION_2_3" 'task_id')" "yes"
check "2. Test wave: why release waits - worker stays available for rework" \
  "$(has_fn "$SECTION_2_3" 'stays available')" "yes"
check "2. Test wave: why release is safe - worker identity is disposable" \
  "$(has_fn "$SECTION_2_3" 'disposable')" "yes"
check "2. Test wave: release is best-effort" \
  "$(has_fn "$SECTION_2_3" 'best-effort')" "yes"

# -- Local merge: release the implementer(s) (clauses c, d, f-g) --
check "4. Local merge: implementer teammate(s) released" \
  "$(has_fn "$SECTION_4" 'implementer teammate')" "yes"
check "4. Local merge: release covers teammate(s), not just one" \
  "$(has_fn "$SECTION_4" 'teammate(s)')" "yes"
check "4. Local merge: TaskStop is the named mechanism" \
  "$(has_fn "$SECTION_4" 'TaskStop')" "yes"
check "4. Local merge: teammate name passed as task_id" \
  "$(has_fn "$SECTION_4" 'task_id')" "yes"
check "4. Local merge: release never turns into a unit failure" \
  "$(has_fn "$SECTION_4" "never changes the unit's outcome")" "yes"
check "4. Local merge: engineer-owned block edge case addressed" \
  "$(has_fn "$SECTION_4" 'engineer-owned')" "yes"

# -- Unit status file: Timeline gains the release entry (clause h) --
check "Unit status file: Timeline records each teammate release" \
  "$(has_fn "$UNIT_STATUS" 'teammate release')" "yes"

# -- Invariants: no new H2/H3 heading introduced by this block ------------
# Hardcoded against the file's current heading set (12 H2, 5 H3); this block
# is prose-only and may add sentences to existing sections, never a heading.
check "invariant: H2 heading count unchanged (12, no new H2 added)" \
  "$(grep -c '^## ' "$SKILL")" "12"
check "invariant: H3 heading count unchanged (5, no new H3 added)" \
  "$(grep -c '^### ' "$SKILL")" "5"

# -- Invariants: existing content in the touched sections is not clobbered -
check "Worker briefs: parallel-dispatch guidance still present" \
  "$(has_fn "$WORKER_BRIEFS" "dispatch a wave's agents in a single message")" "yes"
check "4. Local merge: worktree-removal prose still present" \
  "$(has_fn "$SECTION_4" 'automatically removes the unit worktree as a best-effort side effect')" "yes"
check "Unit status file: phase-commit Timeline entry still present" \
  "$(has_fn "$UNIT_STATUS" 'each phase commit')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
