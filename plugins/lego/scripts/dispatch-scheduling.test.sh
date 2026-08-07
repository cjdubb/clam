#!/bin/bash
# Structural/anchor test for skills/dispatch/SKILL.md against Contract: B01
# dispatch background scheduler (the HTML comment near the top of that file,
# "Contract: B01 dispatch background scheduler (remove at acceptance)").
#
# This is a PROSE block: the document itself is the deliverable, so the tests
# here pin the operative sentences the contract requires — tokens, headings,
# section scoping, and textual ordering — never prose semantics. Meaning is
# verified by the orchestrator at acceptance.
#
# Two rules govern every check below.
#
#   1. Match against the COMMENT-STRIPPED file. The contract docblock quotes
#      nearly every phrase the finished prose needs ("background",
#      "Scheduling", "wave-check.sh", "Awaiting Agent", "actionable"), so a
#      check run against the raw file would pass today against the comment's
#      own vocabulary, before any real edit exists. $STRIPPED removes HTML
#      comments first; only real prose can satisfy a check. (At acceptance
#      the docblock is deleted outright — the prose-block rule in step 3.4 —
#      so stripping is also what makes these checks stable across that
#      deletion.)
#
#   2. Scope each check to the section the contract places it in. A rule the
#      contract ties to stage 2 AND stage 3 is checked in both, so "stated
#      once, somewhere in the file" cannot satisfy it.
#
# Wording tolerance: clauses the contract states as ideas rather than quotes
# are checked as concept anchors — an OR over the plausible phrasings — in
# the same register as the existing suites' chase/malformed-report checks.
# The rule must be stated; it need not be stated in one exact phrasing.
#
# Companion suite: plugins/lego/scripts/dispatch-skill.test.sh holds the
# pre-B01 anchors for this file (file protocol, teammate teardown, delivery,
# archive). Where B01's contract supersedes one of those, it was adjusted
# there, not duplicated here.
#
# Run: bash plugins/lego/scripts/dispatch-scheduling.test.sh
#      (exits non-zero on failure)

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

# Fixed-string presence, wrap-tolerant: this document hard-wraps prose at ~76
# columns, so a multi-word literal ("actionable stage") routinely has its own
# words land on opposite sides of a source line break. Collapse every
# whitespace run — newlines included — to a single space before matching.
has_fn() { # content literal
  local flat; flat=$(tr '\n' ' ' <<<"$1" | tr -s ' ')
  if grep -qF -- "$2" <<<"$flat"; then echo yes; else echo no; fi
}

# Concept anchor: yes when ANY of the given literals is present.
has_any_fn() { # content literal...
  local content="$1"; shift
  local lit
  for lit in "$@"; do
    if [[ "$(has_fn "$content" "$lit")" == "yes" ]]; then echo yes; return; fi
  done
  echo no
}

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi

# Rule 1 above: every check reads this, never the raw file.
STRIPPED=$(perl -0777 -pe 's/<!--.*?-->//gs' "$SKILL")

# --- Section extraction ---------------------------------------------------
# "## Scheduling" stops at the next H2 rather than a named one, because the
# contract requires the section to exist without pinning where in the
# document it sits.
SCHEDULING=$(awk '/^## Scheduling$/{flag=1; next} flag && /^## /{flag=0} flag' <<<"$STRIPPED")
SECTION_2=$(awk '/^### 2\. Test wave$/{flag=1; next} /^### 3\. Implementation wave$/{flag=0} flag' <<<"$STRIPPED")
SECTION_3=$(awk '/^### 3\. Implementation wave$/{flag=1; next} /^### 4\. Local merge$/{flag=0} flag' <<<"$STRIPPED")
WORKER_BRIEFS=$(awk '/^## Worker briefs$/{flag=1; next} /^## Unit status file$/{flag=0} flag' <<<"$STRIPPED")
DISPATCH_ORDER=$(awk '/^## Dispatch order$/{flag=1; next} /^## The per-unit pipeline$/{flag=0} flag' <<<"$STRIPPED")
ENGINEER_OWNED=$(awk '/^## Engineer-owned blocks$/{flag=1; next} /^## Conflicts$/{flag=0} flag' <<<"$STRIPPED")
ESCALATION=$(awk '/^## Escalation loop$/{flag=1; next} /^## Done$/{flag=0} flag' <<<"$STRIPPED")

# Several clauses name a rule without fixing which section states it — the
# scheduling loop and the escalation loop are both defensible homes for the
# engineer-question and escalated-unit clauses. Those checks read this
# union, so the contract is enforced without the test inventing a placement
# the contract never required.
SCHED_OR_ESCALATION="$SCHEDULING
$ESCALATION"

# ==========================================================================
# Behavior 1 — every wave dispatch explicitly requests background execution
# ==========================================================================
# Contract: "Every wave dispatch explicitly requests background execution
# (run_in_background true / the harness's background-agent mechanism) — never
# left to a harness default. The orchestrator never waits synchronously on
# one wave while any other unit has an actionable stage."
#
# The contract's own Anchors list calls for "the word 'background' in the
# wave-dispatch instruction". There are two wave-dispatch instructions — the
# test wave (stage 2) and the implementation wave (stage 3) — so both are
# checked; a background model stated for only one of the two waves is half a
# model.
check "2. Test wave: dispatch is explicitly background" \
  "$(has_fn "$SECTION_2" 'background')" "yes"
check "3. Implementation wave: dispatch is explicitly background" \
  "$(has_fn "$SECTION_3" 'background')" "yes"

# The mechanism is named concretely, not gestured at: the harness parameter
# itself, or the background-agent mechanism by name. Checked document-wide —
# stating it once where dispatch is described is enough.
check "the background mechanism is named concretely" \
  "$(has_any_fn "$STRIPPED" 'run_in_background' 'background-agent' 'background agent' 'background execution')" "yes"

# ... and it is requested explicitly rather than inherited from whatever the
# harness happens to default to.
check "background is requested explicitly, never left to a harness default" \
  "$(has_any_fn "$STRIPPED" 'harness default' 'never left to' 'default it' "the harness's default" 'explicitly request')" "yes"

# The negative half of the same clause: no synchronous wait on one wave while
# another unit could be moved forward.
check "Scheduling: no synchronous wait while another unit is actionable" \
  "$(has_any_fn "$SCHEDULING" 'synchronously' 'synchronous')" "yes"
check "Scheduling: 'actionable' is the term for a unit that can be moved" \
  "$(has_fn "$SCHEDULING" 'actionable')" "yes"

# ==========================================================================
# Behavior 2 — completion signal, and what a completion advances
# ==========================================================================
# Contract: "A wave's completion signal is its task notification plus the
# report file on disk; on each completion, the orchestrator advances THAT
# unit's pipeline (verify, next wave, merge) while other units' workers run
# on."
check "Scheduling: completion signal includes the task notification" \
  "$(has_any_fn "$SCHEDULING" 'notification' 'notifies' 'notified')" "yes"
check "Scheduling: completion signal includes the report file on disk" \
  "$(has_any_fn "$SCHEDULING" 'report file' 'report on disk')" "yes"
check "Scheduling: a completion advances that unit's own pipeline" \
  "$(has_any_fn "$SCHEDULING" "that unit's pipeline" "that unit's own pipeline" "advances that unit")" "yes"
check "Scheduling: other units' workers keep running meanwhile" \
  "$(has_any_fn "$SCHEDULING" "other units' workers" 'other units' 'sibling units')" "yes"

# ==========================================================================
# Behavior 3 — the "## Scheduling" section and its loop invariant
# ==========================================================================
# Contract Anchors: 'a "## Scheduling" heading'. Counted, not merely found,
# so a duplicated section (two homes for one invariant, which is how they
# drift) fails here rather than at the next reader.
check "## Scheduling heading exists exactly once" \
  "$(grep -c '^## Scheduling$' <<<"$STRIPPED")" "1"

# The section is non-empty — a heading with nothing under it satisfies a
# grep and nothing else.
SCHEDULING_NONEMPTY="no"
if [[ -n "$(tr -d '[:space:]' <<<"$SCHEDULING")" ]]; then SCHEDULING_NONEMPTY="yes"; fi
check "## Scheduling section is non-empty" "$SCHEDULING_NONEMPTY" "yes"

# The loop invariant's three parts: what counts as runnable, what a runnable
# unit must have, and where the exception is recorded.
check "Scheduling: 'runnable' is the term for a schedulable unit" \
  "$(has_any_fn "$SCHEDULING" 'runnable')" "yes"
check "Scheduling: runnable is defined by deps being locally merged" \
  "$(has_any_fn "$SCHEDULING" 'locally merged' 'Deps' 'dependencies merged')" "yes"
check "Scheduling: a runnable unit has its worktree created" \
  "$(has_any_fn "$SCHEDULING" 'worktree created' 'its worktree' 'a worktree')" "yes"
check "Scheduling: ... and its next wave in flight" \
  "$(has_any_fn "$SCHEDULING" 'in flight' 'in-flight')" "yes"
check "Scheduling: ... or a recorded reason in the status file" \
  "$(has_any_fn "$SCHEDULING" 'recorded reason' 'reason recorded' 'reason in its status file' 'reason in the status file')" "yes"
check "Scheduling: the recorded reason lives in the unit status file" \
  "$(has_any_fn "$SCHEDULING" 'status file' '.local/status.md')" "yes"

# The invariant has teeth: an idle runnable unit is a defect, not a style
# preference.
check "Scheduling: an idle runnable unit is named a scheduling defect" \
  "$(has_any_fn "$SCHEDULING" 'scheduling defect' 'is a defect')" "yes"

# ==========================================================================
# Behavior 4 — orchestrator ceremony overlaps other units' workers
# ==========================================================================
# Contract: "Orchestrator ceremony for one unit — brief-writing, wave
# verification, merges, map/status updates — explicitly proceeds while other
# units' workers run. This cross-unit overlap is explicitly distinguished
# from the per-unit 'never verify concurrently with a resumed worker' rule,
# which continues to bind unchanged WITHIN a unit."
check "Scheduling: ceremony proceeds while other units' workers run" \
  "$(has_any_fn "$SCHEDULING" 'while other units' 'while another unit' "other units' workers run")" "yes"
check "Scheduling: brief-writing named as overlappable ceremony" \
  "$(has_any_fn "$SCHEDULING" 'brief-writing' 'brief writing' 'writing a brief' 'brief')" "yes"
check "Scheduling: verification named as overlappable ceremony" \
  "$(has_any_fn "$SCHEDULING" 'verification' 'verifying' 'verify')" "yes"
check "Scheduling: merges named as overlappable ceremony" \
  "$(has_any_fn "$SCHEDULING" 'merges' 'merge')" "yes"

# The distinction is the load-bearing half: the per-unit rule is referenced
# by name and explicitly scoped to within a unit, so a reader cannot take
# cross-unit overlap as permission to verify over a resumed worker in the
# same unit.
check "Scheduling: the per-unit resumed-worker rule is referenced by name" \
  "$(has_fn "$SCHEDULING" 'verify concurrently with a resumed worker')" "yes"
check "Scheduling: that rule is explicitly scoped to within a unit" \
  "$(has_any_fn "$SCHEDULING" 'within a unit' 'within the unit' 'within one unit' 'inside a unit' 'per-unit')" "yes"

# ... and the rule it is distinguished from still stands where it always
# stood. Both verification checklists keep it (the existing suite pins its
# full wording; this pins that B01 did not delete it).
check "2. Test wave: resumed-worker rule survives B01" \
  "$(has_fn "$SECTION_2" 'resumed worker')" "yes"
check "3. Implementation wave: resumed-worker rule survives B01" \
  "$(has_fn "$SECTION_3" 'resumed worker')" "yes"

# ==========================================================================
# Behavior 5 — when the orchestrator may park
# ==========================================================================
# Contract: "The orchestrator ends its turn parking on Awaiting Agent only
# when no unit has an actionable stage and at least one background wave is
# outstanding." Both halves are conditions, so both are pinned: parking with
# work still schedulable is the failure this clause exists to prevent.
check "Scheduling: parking state named (Awaiting Agent)" \
  "$(has_fn "$SCHEDULING" 'Awaiting Agent')" "yes"
check "Scheduling: parking is conditional, not the default end of turn" \
  "$(has_any_fn "$SCHEDULING" 'only when' 'only if' 'only once')" "yes"
check "Scheduling: condition 1 - no unit has an actionable stage" \
  "$(has_any_fn "$SCHEDULING" 'no unit has an actionable' 'nothing is actionable' 'no actionable')" "yes"
check "Scheduling: condition 2 - a background wave is outstanding" \
  "$(has_any_fn "$SCHEDULING" 'outstanding' 'still in flight' 'still running')" "yes"

# ==========================================================================
# Behavior 6 — same-wave batching survives only as the degrade path
# ==========================================================================
# Contract: "The former same-wave batching instruction ('dispatch a wave's
# agents in a single message') survives only as the explicit degrade path
# for harnesses without background dispatch; background is the default
# model." Contract Anchors: "the single-message batching sentence present
# only in degrade-path context."
#
# Checked as a context window rather than a section, because the contract
# fixes the sentence's CONTEXT, not its location: every occurrence of the
# batching instruction must sit inside prose that marks it as the fallback.
# The window is taken on the whitespace-flattened document so a hard wrap
# cannot push the qualifying words out of range.
FLAT=$(tr '\n' ' ' <<<"$STRIPPED" | tr -s ' ')
BATCH_NEEDLE='in a single message'
BATCH_COUNT=0
BATCH_UNQUALIFIED=0
BATCH_REST="$FLAT"
while [[ "$BATCH_REST" == *"$BATCH_NEEDLE"* ]]; do
  BATCH_BEFORE="${BATCH_REST%%"$BATCH_NEEDLE"*}"
  BATCH_AFTER="${BATCH_REST#*"$BATCH_NEEDLE"}"
  BATCH_WINDOW="${BATCH_BEFORE: -450}$BATCH_NEEDLE${BATCH_AFTER:0:300}"
  BATCH_COUNT=$((BATCH_COUNT + 1))
  if ! grep -qiE 'degrade|degradation|fall ?back|without background|no background|does not support|do not support|lacks background|unsupported|cannot dispatch in the background' <<<"$BATCH_WINDOW"; then
    BATCH_UNQUALIFIED=$((BATCH_UNQUALIFIED + 1))
  fi
  BATCH_REST="$BATCH_AFTER"
done

check "batching instruction survives somewhere in the document" \
  "$([[ "$BATCH_COUNT" -ge 1 ]] && echo yes || echo no)" "yes"
check "every batching occurrence sits in degrade-path context" \
  "$BATCH_UNQUALIFIED" "0"

# The degrade path is named as such — a fallback for harnesses that cannot
# dispatch in the background — and background is stated as the default.
check "the degrade path names the harness limitation it exists for" \
  "$(has_any_fn "$STRIPPED" 'without background dispatch' 'no background dispatch' 'cannot dispatch in the background' 'does not support background')" "yes"
check "background is stated as the default model" \
  "$(has_any_fn "$STRIPPED" 'background is the default' 'background-first' 'the default model' 'by default, in the background')" "yes"

# ==========================================================================
# Behavior 7 — stages 2 and 3 collapse their mechanical items into
#              one wave-check.sh invocation
# ==========================================================================
# Contract: "Stages 2 and 3: the mechanical checklist items (test-command
# run, pipe-safety, realm check, contracts-unchanged diff, count re-runs)
# are collapsed into one invocation of scripts/wave-check.sh per its contract
# docblock; the judgment items (clause coverage, contract-not-internals
# spot-read, diff spot-review) remain, stated as the orchestrator's own
# non-delegable work."
check "2. Test wave: wave-check.sh named" \
  "$(has_fn "$SECTION_2" 'wave-check.sh')" "yes"
check "3. Implementation wave: wave-check.sh named" \
  "$(has_fn "$SECTION_3" 'wave-check.sh')" "yes"

# Each stage invokes its own mode — the script's two modes are not
# interchangeable, and naming the wrong one in a checklist is a silent
# no-op gate.
check "2. Test wave: invoked in test mode" \
  "$(has_any_fn "$SECTION_2" 'wave-check.sh test' 'wave-check.sh` test' 'wave-check.sh in test mode')" "yes"
check "3. Implementation wave: invoked in impl mode" \
  "$(has_any_fn "$SECTION_3" 'wave-check.sh impl' 'wave-check.sh` impl' 'wave-check.sh in impl mode')" "yes"

# The judgment half stays, per stage, and stays the orchestrator's own work.
check "2. Test wave: clause coverage remains a judgment item" \
  "$(has_any_fn "$SECTION_2" 'Clause coverage' 'clause coverage')" "yes"
check "2. Test wave: contract-not-internals spot-read remains" \
  "$(has_any_fn "$SECTION_2" 'not internals' 'Spot-read' 'spot-read')" "yes"
check "3. Implementation wave: diff spot-review remains" \
  "$(has_any_fn "$SECTION_3" 'Spot-review' 'spot-review')" "yes"
# Deliberately narrow: a bare "your own" already appears in both stages
# ("accept or reject on your own evidence") and would pass this check
# without anyone having stated who owns the judgment items. The phrasings
# accepted here are all about delegability specifically.
check "2. Test wave: judgment items stated as the orchestrator's own non-delegable work" \
  "$(has_any_fn "$SECTION_2" 'non-delegable' 'not delegable' 'cannot be delegated' 'never delegated' "the orchestrator's own work" "the orchestrator's own judgment")" "yes"
check "3. Implementation wave: judgment items stated as the orchestrator's own non-delegable work" \
  "$(has_any_fn "$SECTION_3" 'non-delegable' 'not delegable' 'cannot be delegated' 'never delegated' "the orchestrator's own work" "the orchestrator's own judgment")" "yes"

# Collapsed means collapsed, not duplicated: the two mechanical procedures
# the pre-B01 text spelled out by hand — a separate realm-check.sh
# invocation, and the manual pipe-safe capture recipe — must be gone from
# both stages, or the checklist still carries the work wave-check.sh now
# owns. Fingerprints chosen to be unambiguous instructions to run the thing
# by hand: a prose aside that merely mentions realm-check.sh (e.g. noting
# that wave-check delegates to it) does not match.
for pair in "2. Test wave|$SECTION_2" "3. Implementation wave|$SECTION_3"; do
  label="${pair%%|*}"
  body="${pair#*|}"
  check "$label: no separate realm-check.sh invocation remains" \
    "$(has_fn "$body" '${CLAUDE_PLUGIN_ROOT}/scripts/realm-check.sh')" "no"
  check "$label: manual pipe-safe capture recipe is gone" \
    "$(has_fn "$body" 'status=$?')" "no"
  check "$label: manual pipefail caveat is gone" \
    "$(has_fn "$body" 'not rely on `pipefail`')" "no"
done

# ==========================================================================
# Invariants
# ==========================================================================
# Contract: "Stage 5 delivery text, the escalation loop, the brief/report
# file protocol, realm rules, teammate naming and TaskStop lifecycle, and all
# engineer question gates are preserved; anchors relied on by
# dispatch-landing.test.sh and skill-gate-reinforcement.test.sh survive
# verbatim."
#
# Those two suites run in the same CI stage and are the real enforcement for
# their own anchors — duplicating them here would just create two places to
# update. What is pinned here is the coarse survival of each named area, so
# a scheduling rewrite that swallows one of them fails in the suite that
# introduced the risk.
check "invariant: stage 5 delivery text survives" \
  "$(has_fn "$STRIPPED" '#### 5b. Write manifest and assemble')" "yes"
check "invariant: escalation loop survives" \
  "$(has_fn "$STRIPPED" '## Escalation loop')" "yes"
check "invariant: brief/report file protocol survives" \
  "$(has_fn "$WORKER_BRIEFS" '.local/reports/NN-<wave>-<blocks>.md')" "yes"
check "invariant: teammate naming survives" \
  "$(has_fn "$WORKER_BRIEFS" '<unit-id>-<wave>-<NN>')" "yes"
check "invariant: TaskStop lifecycle survives (test wave)" \
  "$(has_fn "$SECTION_2" 'TaskStop')" "yes"
check "invariant: realm rules survive (realm purity still required)" \
  "$(has_any_fn "$STRIPPED" 'realm')" "yes"

# The standing question rule: an open engineer question pauses NEW dispatches
# and NEW verifications, while background workers already in flight run to
# completion and their results wait unverified. Under a background model this
# is the clause most easily lost — "everything keeps running" is exactly the
# wrong generalisation — so it is pinned wherever the scheduling loop or the
# escalation loop states it.
check "question gate: an open engineer question pauses new work" \
  "$(has_any_fn "$SCHED_OR_ESCALATION" 'engineer question' 'open question' 'unanswered question')" "yes"
check "question gate: what pauses is NEW dispatches and NEW verifications" \
  "$(has_any_fn "$SCHED_OR_ESCALATION" 'new dispatches' 'New dispatches' 'new dispatch' 'further dispatches')" "yes"
check "question gate: in-flight workers still run to completion" \
  "$(has_any_fn "$SCHED_OR_ESCALATION" 'run to completion' 'already in flight' 'already dispatched')" "yes"
check "question gate: their results wait unverified until questions are answered" \
  "$(has_any_fn "$SCHED_OR_ESCALATION" 'unverified' 'wait until every question' 'until every question is answered')" "yes"

# ==========================================================================
# Edge cases
# ==========================================================================
# "Single-unit plan: the loop degenerates to the sequential flow with no
# extra ceremony." The scheduling loop must say so itself — a reader with one
# unit should not have to infer that none of this applies to them.
check "edge: single-unit plan addressed" \
  "$(has_any_fn "$SCHEDULING" 'single-unit' 'single unit' 'one unit' 'a plan with one unit')" "yes"
check "edge: single-unit plan degenerates to the sequential flow" \
  "$(has_any_fn "$SCHEDULING" 'degenerates' 'sequential' 'no extra ceremony')" "yes"

# "Engineer-owned unit: its implementation phase is an outstanding wave that
# never blocks sibling scheduling." Checked in the section that owns
# engineer-owned blocks, or in the scheduling loop — the contract does not
# fix which.
ENGINEER_OWNED_EDGE="$SCHEDULING
$ENGINEER_OWNED"
check "edge: an engineer-owned unit's implementation counts as an outstanding wave" \
  "$(has_any_fn "$ENGINEER_OWNED_EDGE" 'outstanding wave' 'outstanding' 'an in-flight wave')" "yes"
check "edge: an engineer-owned unit never blocks sibling scheduling" \
  "$(has_any_fn "$ENGINEER_OWNED_EDGE" 'never blocks' 'does not block' 'never block sibling' 'keeps scheduling')" "yes"

# "Escalated unit: parks; sibling units keep scheduling unless the escalation
# opens an engineer question (then the invariant above rules)."
# Anchored on the unit parking, not on "park" as a word: the Awaiting Agent
# clause above already puts "parking" in the same haystack, and a check that
# clause could satisfy would say nothing about this edge case.
check "edge: an escalated unit parks" \
  "$(has_any_fn "$SCHED_OR_ESCALATION" 'unit parks' 'unit is parked' 'escalated unit')" "yes"
check "edge: siblings keep scheduling through another unit's escalation" \
  "$(has_any_fn "$SCHED_OR_ESCALATION" 'keep scheduling' 'continue scheduling' 'sibling units keep' 'other units keep')" "yes"
check "edge: unless the escalation opens an engineer question" \
  "$(has_any_fn "$SCHED_OR_ESCALATION" 'unless the escalation' 'unless it opens' 'unless that escalation')" "yes"

# --- Dispatch order: concurrency statement is not weakened ----------------
# The pre-B01 text already promises that independent units run concurrently.
# B01 makes that promise operative rather than replacing it, so it must
# still be there for the Scheduling section to be the mechanism OF something.
check "Dispatch order: independent units still stated to run concurrently" \
  "$(has_any_fn "$DISPATCH_ORDER" 'concurrently' 'in parallel')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
