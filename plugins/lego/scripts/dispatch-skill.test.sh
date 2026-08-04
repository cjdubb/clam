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

# --- Delivery freshness and the post-deliver gate ------------------------
# Scoped per step, the same way the pipe-safety checks below are, so
# "step 5 says fetch" and "step 5b states the gate" are verified where they
# belong rather than anywhere in the file. Step 5 runs from its heading to
# 5a's; step 5b from its heading to the next top-level section.
SECTION_5=$(awk '/^### 5\. Delivery$/{flag=1; next} /^#### 5a\. Compose PR content$/{flag=0} flag' "$SKILL")
SECTION_5B=$(awk '/^#### 5b\. Write manifest and deliver$/{flag=1; next} /^## Composition blocks$/{flag=0} flag' "$SKILL")

# Step 5: the pre-delivery master merge must start with a fetch (a merge
# against a stale ref is a no-op that invalidates every base-relative
# check), and the LOCAL base checkout deliver builds from must be
# fast-forwarded before deliver runs.
check "5: pre-delivery merge fetches origin first" \
  "$(has_f "$SECTION_5" 'git fetch origin')" "yes"
check "5: local base checkout is fast-forwarded before deliver" \
  "$(has_f "$SECTION_5" 'merge --ff-only origin/master')" "yes"

# Step 5b: the post-deliver comparison is a gate, stated as one, and
# deliver enforces it mechanically rather than leaving it to diligence.
check "5b: delivery must match the integration branch on delivered paths" \
  "$(has_f "$SECTION_5B" 'must match the integration branch exactly on the paths it')" "yes"
check "5b: stated as a gate, not a suggestion" \
  "$(has_f "$SECTION_5B" 'This is a gate, not a suggestion')" "yes"
check "5b: deliver refuses to push on divergence" \
  "$(has_f "$SECTION_5B" 'refuses to push on any divergence')" "yes"
check "5b: an unverified delivery is not handed over" \
  "$(has_f "$SECTION_5B" 'An unverified delivery is not handed over')" "yes"

# --- Comment-stripped, step-scoped views (used by everything below) ------
# The scaffold docblocks embedded in SKILL.md as HTML comments describe what
# the finished prose must say, but are not the prose itself. Strip HTML
# comments before matching so a comment's vocabulary can never satisfy a
# check — only real prose counts. Then scope each check to its own step's
# section (via the same headings the "Invariants" loop above already
# guarantees survive) so a rule the contract ties to both steps is verified
# per-location, not just once anywhere in the file.
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")
SECTION_2_3=$(awk '/^### 2\. Test wave$/{flag=1; next} /^### 3\. Implementation wave$/{flag=0} flag' <<<"$STRIPPED")
SECTION_3_1=$(awk '/^### 3\. Implementation wave$/{flag=1; next} /^### 4\. Local merge$/{flag=0} flag' <<<"$STRIPPED")

# SUPERSEDED by "Contract: B01 dispatch background scheduler": the
# pipe-safety guidance that used to be pinned here (step 2.3's `$?` warning,
# the canonical capture snippet, the redirection-is-safe carve-out, the
# pipefail caveat, the PIPESTATUS condition, and step 3.1's inline-or-
# cross-reference coverage) is a mechanical checklist item, and B01 collapses
# every mechanical item in steps 2 and 3 into one invocation of
# scripts/wave-check.sh — whose own contract makes pipe-safe capture an
# invariant of the script rather than a procedure the orchestrator performs
# by hand. Those checks are therefore removed rather than weakened: the
# behaviour still exists, it just moved out of this document. What replaces
# them lives in dispatch-scheduling.test.sh ("Behavior 7"), which pins
# wave-check.sh per step AND asserts the hand-run recipe is gone from both.

# --- B02 archive documentation (contract: B02 dispatch-archive-docs, plan
# 001-brief-report-archive) ------------------------------------------------
# The contract's own HTML comment (search SKILL.md for "Contract: B02")
# quotes nearly every phrase the finished prose needs, so matching against
# $RAW would pass today for the wrong reason — the words are sitting in the
# comment, not in real prose. Everything below matches $STRIPPED (defined
# above, HTML comments already removed) instead, and is section-scoped so
# "documented once, somewhere in the file" cannot satisfy a check the
# contract ties to one specific location.

SECTION_4_MERGE=$(awk '/^### 4\. Local merge$/{flag=1; next} /^### 5\. Delivery$/{flag=0} flag' <<<"$STRIPPED")
SECTION_WORKER_BRIEFS=$(awk '/^## Worker briefs$/{flag=1; next} /^## Unit status file$/{flag=0} flag' <<<"$STRIPPED")
SECTION_ESCALATION=$(awk '/^## Escalation loop$/{flag=1; next} /^## Done$/{flag=0} flag' <<<"$STRIPPED")
SECTION_ENGINEER_OWNED=$(awk '/^## Engineer-owned blocks$/{flag=1; next} /^## Conflicts$/{flag=0} flag' <<<"$STRIPPED")

# Step 4 (Local merge): archive path, the three archived components, and
# that a failed archive leaves the worktree in place instead of removing it.
check "4: archive path .local/units/<plan-slug>/<unit-id>/ named" \
  "$(has_f "$SECTION_4_MERGE" '.local/units/<plan-slug>/<unit-id>/')" "yes"
check "4: archived component briefs/ named" \
  "$(has_f "$SECTION_4_MERGE" 'briefs/')" "yes"
check "4: archived component reports/ named" \
  "$(has_f "$SECTION_4_MERGE" 'reports/')" "yes"
check "4: archived component status.md named" \
  "$(has_f "$SECTION_4_MERGE" 'status.md')" "yes"
check "4: failed archive leaves the worktree in place" \
  "$(has_f "$SECTION_4_MERGE" 'leaves the worktree in place')" "yes"

# Ordering: the archive must be described as happening before the worktree
# is removed. Checked by character offset rather than line number, because
# this file hard-wraps prose paragraphs across physical lines — a
# line-based comparison could put two clauses of the same sentence on
# either side of a wrap and report a false order that has nothing to do
# with what the sentence actually says.
offset_of() { # content literal -> byte offset of first match, or -1
  local content="$1" needle="$2"
  if [[ "$content" != *"$needle"* ]]; then echo -1; return; fi
  local before="${content%%"$needle"*}"
  echo "${#before}"
}
ARCHIVE_POS=$(offset_of "$SECTION_4_MERGE" '.local/units/<plan-slug>/<unit-id>/')
REMOVE_POS=$(offset_of "$SECTION_4_MERGE" 'removes the unit worktree')
ARCHIVE_BEFORE_REMOVE="no"
if [[ "$ARCHIVE_POS" != "-1" && "$REMOVE_POS" != "-1" && "$ARCHIVE_POS" -lt "$REMOVE_POS" ]]; then
  ARCHIVE_BEFORE_REMOVE="yes"
fi
check "4: archive described before worktree removal (textual order)" \
  "$ARCHIVE_BEFORE_REMOVE" "yes"

# Correction, not supplementation: the pre-B02 sentence describes removal
# as an unconditional best-effort side effect ("automatically removes the
# unit worktree..."). A document that keeps this sentence AND adds the new
# conditional description contradicts itself, so the old phrasing must be
# gone, not merely added-to.
check "4: old unconditional-removal phrasing is gone" \
  "$(has_f "$SECTION_4_MERGE" 'automatically removes the unit worktree')" "no"

# Worker briefs: the reader who writes a brief learns it is not lost at
# merge — the archive path, scoped to this section specifically.
check "Worker briefs: names the archive as where briefs/reports end up" \
  "$(has_f "$SECTION_WORKER_BRIEFS" '.local/units/<plan-slug>/<unit-id>/')" "yes"

# Escalation loop: "the rejected wave's brief and report files stay put"
# points at the archive as the durable location that makes it true after
# merge — scoped to this section specifically.
check "Escalation loop: points at the archive as the durable location" \
  "$(has_f "$SECTION_ESCALATION" '.local/units/<plan-slug>/<unit-id>/')" "yes"

# Engineer-owned blocks: must NOT be rewritten to point at the archive —
# the worktree still exists at hand-off time, so the existing "read the
# brief from the unit worktree" instruction stays correct as-is. Vacuously
# true today; this guards against a future edit contaminating this section.
check "Engineer-owned blocks: NOT rewritten to point at the archive" \
  "$(has_f "$SECTION_ENGINEER_OWNED" '.local/units/<plan-slug>/<unit-id>/')" "no"

# --- plugins/lego/README.md (contract clause 2) ---------------------------
# Same suite (this is the plugin's doc-anchor test), read the same way
# $RAW reads SKILL.md above.
README="$SCRIPT_DIR/../README.md"
if [[ ! -f "$README" ]]; then
  echo "FAIL  README.md not found at $README"
  exit 1
fi
README_RAW=$(cat "$README")

# Bullet-scoped extraction: from a bullet's own start marker up to the next
# bullet's start marker, matched by substring (not regex) so none of the
# bullets' backticks or angle brackets need escaping.
readme_section() { # content start_literal stop_literal
  awk -v start="$2" -v stop="$3" '
    index($0, start) { flag=1 }
    flag && stop != "" && index($0, stop) { exit }
    flag { print }
  ' <<<"$1"
}

MERGE_BULLET=$(readme_section "$README_RAW" '- `merge <plan-slug>' '- `deliver --manifest')
DELIVER_BULLET=$(readme_section "$README_RAW" '- `deliver --manifest' '- `remove <plan-slug>')
REMOVE_BULLET=$(readme_section "$README_RAW" '- `remove <plan-slug>' '- `clean`')
CLEAN_BULLET=$(readme_section "$README_RAW" '- `clean`' '**`scripts/realm.sh')
WORKER_BRIEFS_BULLET=$(readme_section "$README_RAW" '- Worker briefs are always written to' '- Escalations (')

check "README merge bullet: names the archive path" \
  "$(has_f "$MERGE_BULLET" '.local/units/<plan-slug>/<unit-id>/')" "yes"
check "README merge bullet: failed archive skips removal" \
  "$(has_f "$MERGE_BULLET" 'skips removal')" "yes"

check "README deliver bullet: names the archive path" \
  "$(has_f "$DELIVER_BULLET" '.local/units/<plan-slug>/<unit-id>/')" "yes"
check "README deliver bullet: failed archive skips removal" \
  "$(has_f "$DELIVER_BULLET" 'skips removal')" "yes"

check "README remove bullet: names the archive path" \
  "$(has_f "$REMOVE_BULLET" '.local/units/<plan-slug>/<unit-id>/')" "yes"
check "README remove bullet: failed archive exits nonzero" \
  "$(has_f "$REMOVE_BULLET" 'exits nonzero')" "yes"

check "README worker-briefs bullet: names where briefs/reports survive to" \
  "$(has_f "$WORKER_BRIEFS_BULLET" '.local/units/<plan-slug>/<unit-id>/')" "yes"

check "README clean bullet: still does not claim to archive" \
  "$(has_f "$CLEAN_BULLET" '.local/units/')" "no"

# Deliberately not tested here (owned mechanically by other linters):
#   - plugins/lego/.claude-plugin/plugin.json version bump: enforced by
#     scripts/version-bump-lint.sh.
#   - README.md (repo root) version cell matching plugin.json: enforced by
#     scripts/readme-lint.sh's root-table check.

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

# -- Invariants: heading set is fixed, and grows only where a contract says
# Hardcoded against the file's heading set. 12 H2 became 13 under "Contract:
# B01 dispatch background scheduler", whose Anchors list requires exactly one
# new section, "## Scheduling" — that suite pins the heading's existence and
# that it appears exactly once; this count is what stops a second, unasked-
# for section arriving alongside it. H3 stays at 5: no contract has asked
# for a new one, and the prose blocks that edit this file add sentences to
# existing sections.
check "invariant: H2 heading count is 13 (12 pre-B01 + ## Scheduling)" \
  "$(grep -c '^## ' "$SKILL")" "13"
check "invariant: H3 heading count unchanged (5, no new H3 added)" \
  "$(grep -c '^### ' "$SKILL")" "5"

# -- Invariants: existing content in the touched sections is not clobbered -
# The batching sentence's LOCATION is superseded by "Contract: B01 dispatch
# background scheduler": it survives "only as the explicit degrade path for
# harnesses without background dispatch", which may well be stated in the
# new Scheduling section rather than here. What this check still owns is
# that the sentence was not simply deleted; that it appears only in
# degrade-path context is asserted in dispatch-scheduling.test.sh.
check "parallel-dispatch guidance still present (location no longer pinned)" \
  "$(has_fn "$STRIPPED" "dispatch a wave's agents in a single message")" "yes"
check "4. Local merge: worktree-removal prose still present (post-archive phrasing)" \
  "$(has_fn "$SECTION_4" 'removes the unit worktree')" "yes"
check "Unit status file: phase-commit Timeline entry still present" \
  "$(has_fn "$UNIT_STATUS" 'each phase commit')" "yes"

# --- Filesystem report channel (#184) -------------------------------------
# The report channel moves from "a message the orchestrator receives" to "a
# file the worker writes". Matched against $STRIPPED and section-scoped, the
# same way the B02 archive checks above are, so the rule has to live in the
# section that actually governs the behavior.

# Worker briefs: the brief names the report path, the receipt signal is the
# file appearing, and a message-only report is archived by the orchestrator.
check "Worker briefs: brief names the report file the worker writes" \
  "$(has_fn "$WORKER_BRIEFS" 'the report file the worker writes')" "yes"
check "Worker briefs: report path stated literally" \
  "$(has_fn "$WORKER_BRIEFS" '.local/reports/NN-<wave>-<blocks>.md')" "yes"
check "Worker briefs: receipt signal is the file appearing, not a message" \
  "$(has_fn "$WORKER_BRIEFS" 'receipt signal is the file appearing')" "yes"
check "Worker briefs: a message-only report is archived to the same path" \
  "$(has_fn "$WORKER_BRIEFS" 'archive that message verbatim to the same path')" "yes"
check "Worker briefs: the orchestrator's archive carries a note" \
  "$(has_fn "$WORKER_BRIEFS" 'with a note')" "yes"

# Correction, not supplementation: the pre-#184 sentence gated the archive on
# a message the orchestrator may never get ("on receiving a worker's final
# report, archive it verbatim to ..."), and declared the whole of `.local/`
# unwritable by workers ("they read it, they never write to it"). A document
# that keeps either sentence AND adds the new flow contradicts itself, so
# both must be gone.
check "Worker briefs: message-gated archive phrasing is gone" \
  "$(has_fn "$WORKER_BRIEFS" "on receiving a worker's final report")" "no"
check "Worker briefs: blanket never-write phrasing is gone" \
  "$(has_fn "$WORKER_BRIEFS" 'they read it, they never write to it')" "no"

# Transcript recovery: the documented last resort for a worker that finished
# but wrote nothing. Path pinned literally — it is the whole value of the
# clause.
check "Worker briefs: transcript recovery named as the last resort" \
  "$(has_fn "$WORKER_BRIEFS" 'last resort')" "yes"
check "Worker briefs: transcript path stated literally" \
  "$(has_fn "$WORKER_BRIEFS" '~/.claude/projects/<project>/<session>/subagents/agent-a<name>-<hash>.jsonl')" "yes"

# Steps 2 and 3: verification reads the report off disk, and an absent FILE
# (not an absent message) is the chase/escalate trigger. Checked per step —
# both waves have a report and both have gone silent in practice.
for pair in "2. Test wave|$SECTION_2_3" "3. Implementation wave|$SECTION_3_1"; do
  label="${pair%%|*}"
  body="${pair#*|}"
  check "$label: verification reads the report from its file" \
    "$(has_fn "$body" '.local/reports/NN-<wave>-<blocks>.md')" "yes"
  check "$label: an absent report FILE is the trigger" \
    "$(has_fn "$body" 'absent report file')" "yes"
  check "$label: the trigger is to chase, then escalate" \
    "$(has_fn "$body" 'to chase, then escalate')" "yes"
  check "$label: an absent message is explicitly not the trigger" \
    "$(has_fn "$body" 'not an absent message')" "yes"
done

# --- Acceptance hardening against unreliable reports (#156) ---------------
# Three failure modes have each cost real time: reports that arrive late or
# never, a pinged worker resuming and corrupting shared state under the
# orchestrator's own verification run, and reported counts that were simply
# wrong. Each rule belongs in BOTH verification checklists — the test wave
# and the implementation wave have each hit all three — so every check below
# runs against both sections. Concept anchors, not full sentences: the
# wording may be tuned, the rule may not go missing.
for pair in "2. Test wave|$SECTION_2_3" "3. Implementation wave|$SECTION_3_1"; do
  label="${pair%%|*}"
  body="${pair#*|}"

  # Rule 1: never block on a report — accept or reject on your own evidence,
  # and archive a late one with a timing note.
  check "$label: rule - never block on a report" \
    "$(has_fn "$body" 'Never block on a report')" "yes"
  check "$label: rule 1 - accept or reject on your own evidence" \
    "$(has_fn "$body" 'your own evidence')" "yes"
  check "$label: rule 1 - a late report is archived with a timing note" \
    "$(has_fn "$body" 'timing note')" "yes"

  # Rule 2: never verify concurrently with a resumed worker — a ping resumes
  # it, and the instruction that makes a ping safe is quoted exactly.
  check "$label: rule 2 - pinging an idle worker resumes it" \
    "$(has_fn "$body" 'resumes it')" "yes"
  check "$label: rule 2 - the safe-ping instruction is stated verbatim" \
    "$(has_fn "$body" 'report from memory, touch nothing')" "yes"
  check "$label: rule 2 - verification runs sequentially, not concurrently" \
    "$(has_fn "$body" 'sequentially')" "yes"

  # Rule 3 (re-run every count, and the trailing-FAILURES counting trap) is
  # SUPERSEDED by "Contract: B01 dispatch background scheduler", which names
  # count re-runs as one of the mechanical items collapsed into
  # scripts/wave-check.sh: the script runs the suite itself, so there is no
  # reported number left for the orchestrator to take on trust. Rules 1 and
  # 2 above are untouched — neither is in B01's collapsed set, and B01's own
  # Behavior clause restates rule 2 as continuing to bind within a unit.
done

# --- B03 dispatch-chase-and-malformed-report (contract: B03) --------------
# The contract's own HTML comment (search SKILL.md for "Contract: B03") is
# embedded right inside the "Reports mirror briefs the other way" paragraph,
# quoting nearly the exact clauses the real prose needs — matching against
# $RAW (or even $WORKER_BRIEFS before comment-stripping) would pass today
# against the comment's own vocabulary, before any real edit exists. These
# checks read $WORKER_BRIEFS (defined above, already comment-stripped and
# scoped to "## Worker briefs" — the section this paragraph lives in), so
# only real prose in that section can satisfy them.
#
# Concept anchors, not literal quotes, mirroring the contract's own OR-style
# tolerance for wording (see the 3.1 pipe-safety check above): the rule must
# be stated, not stated in one exact phrasing.

# Clause 1a: the chase is capped at one attempt.
CHASE_CAP_STATED="no"
if [[ "$(has_fn "$WORKER_BRIEFS" "a single time")" == "yes" || \
      "$(has_fn "$WORKER_BRIEFS" "at most once")" == "yes" || \
      "$(has_fn "$WORKER_BRIEFS" "only once")" == "yes" || \
      "$(has_fn "$WORKER_BRIEFS" "one chase")" == "yes" || \
      "$(has_fn "$WORKER_BRIEFS" "single chase")" == "yes" ]]; then
  CHASE_CAP_STATED="yes"
fi
check "Worker briefs: chase capped at one attempt" "$CHASE_CAP_STATED" "yes"

# Clause 1b, reason 1: a resend can vanish exactly as the first send did, so
# a second chase proves nothing.
CHASE_REASON1_STATED="no"
if [[ "$(has_fn "$WORKER_BRIEFS" "resend")" == "yes" || \
      "$(has_fn "$WORKER_BRIEFS" "vanish")" == "yes" || \
      "$(has_fn "$WORKER_BRIEFS" "second chase")" == "yes" || \
      "$(has_fn "$WORKER_BRIEFS" "proves nothing")" == "yes" ]]; then
  CHASE_REASON1_STATED="yes"
fi
check "Worker briefs: reason - a resend can vanish like the first send" \
  "$CHASE_REASON1_STATED" "yes"

# Clause 1b, reason 2: chasing a merely-idle worker resumes it, which costs
# something rather than being free.
CHASE_REASON2_STATED="no"
if [[ "$(has_fn "$WORKER_BRIEFS" "resumes it")" == "yes" || \
      "$(has_fn "$WORKER_BRIEFS" "resumes the worker")" == "yes" || \
      "$(has_fn "$WORKER_BRIEFS" "resuming it")" == "yes" ]]; then
  CHASE_REASON2_STATED="yes"
fi
check "Worker briefs: reason - chasing a merely-idle worker resumes it" \
  "$CHASE_REASON2_STATED" "yes"

# The existing "never verify concurrently with a resumed worker" rule is
# referenced here (per the contract's Invariants), not restated in full.
check "Worker briefs: references the existing resumed-worker rule (not restated)" \
  "$(has_fn "$WORKER_BRIEFS" "verify concurrently with a resumed worker")" "yes"

# Clause 2: a present-but-malformed report file is an ordinary rejection at
# a fresh `NN` — the same path as any other rejected wave, not a third
# handling path beside "absent" and "arrived only as a message".
check "Worker briefs: malformed report addressed as its own case" \
  "$(has_fn "$WORKER_BRIEFS" "malformed")" "yes"

MALFORMED_REJECTION_STATED="no"
if [[ "$(has_fn "$WORKER_BRIEFS" "ordinary rejection")" == "yes" || \
      "$(has_fn "$WORKER_BRIEFS" "same path as any other rejected")" == "yes" ]]; then
  MALFORMED_REJECTION_STATED="yes"
fi
check "Worker briefs: malformed report is an ordinary rejection (same path as any other)" \
  "$MALFORMED_REJECTION_STATED" "yes"

check "Worker briefs: malformed rejection happens at a fresh NN" \
  "$(has_fn "$WORKER_BRIEFS" "fresh \`NN\`")" "yes"

# Note: the contract's other named invariant — SKILL.md heading counts stay
# at 12 H2 / 5 H3, no new H2/H3 section — is already asserted above ("H2
# heading count unchanged" / "H3 heading count unchanged"), so it is not
# duplicated here.

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
