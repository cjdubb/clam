---
name: make-progress
description: "NotImplemented: B03 — USER-INVOKED ONLY — never auto-triggered, never invoked from crons or other skills. The user types /make-progress when the session stopped but should have kept going. Assess the session's work state, take the next action within the approved plan's scope, and record the stall for later analysis of automatic-trigger design."
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash(gh:*, git:*, bash:*, ls:*, cat:*, date:*), CronCreate, CronList, Agent, Skill
---

# Make Progress

NotImplemented: B03 — merge-skill (migrated from make-progress plugin)

Contract: B03 — make-progress skill
Behavior:
  User-invoked stall recovery. When the session stopped but should have kept
  going, assess work state from .local/ artifacts and PR state, match against
  an attended decision table, record the stall as a labeled training example
  (DECISION.md), then execute the matched action within plan scope.
Inputs:
  Invoked by the user typing /make-progress. Reads .local/TODO.md, PLAN.md,
  plans/, blocks.md (any present), PR state via gh, cron state via CronList
  and .claude/scheduled_tasks.json.
Outputs:
  DECISION.md + pr-state.json written to the capture directory (from the
  capture hook or fallback). State transitions in .local/TODO.md. Whatever
  action the matched decision-table row prescribes.
Errors:
  Never invents work outside the approved plan. Never merges PRs, assigns
  reviewers, promotes drafts, or bypasses approval gates.
Invariants:
  - Scope is strictly the approved plan
  - DECISION.md is written BEFORE acting (the act phase can compact or fail)
  - Outcome section is appended to DECISION.md after acting
  - Every invocation produces a record, including "no action" and "stop was
    correct" decisions
Edge cases:
  - No capture dir from hook (fallback mode captures without transcript tail)
  - No .local/ files at all (assess from PR state and crons only)
  - Capture dir already has DECISION.md from a previous invocation
  - Multiple dispatchable lego blocks (dispatch all unblocked units)
