<!--
Contract: B04 default PR body template

Behavior:
  The forge-agnostic default PR/MR body template. Used when the repo has
  no PR template of its own: /landing:land's built-in path fills it
  directly, and the delegation step passes it to the forge plugin as the
  invoker-provided template. Implementation replaces the NotImplemented
  marker with section headings only (no prose): Summary; Why; Why this
  approach; Changes; Verification; Related work — each with a bracketed
  one-line hint of what belongs there, written so filled-in content is
  naturally flowing prose (the hints must not model hard-wrapped text).
Inputs: n/a (template file).
Outputs: the template structure, filled at PR-composition time.
Errors: n/a.
Invariants: forge-agnostic — no GitHub- or GitLab-specific wording; no
  references to other plugins or internal workflow terminology.
Edge cases: sections that don't apply to a given change are omitted by
  the composer, not left as empty headings.
-->

## Summary
[What changed, in one or two sentences, for a reviewer who has only the diff.]

## Why
[The problem this addresses or the capability it adds.]

## Why this approach
[What made this the right approach, if it isn't obvious from the diff alone.]

## Changes
[The main changes, grouped by area when the diff spans more than one concern.]

## Verification
[How this was verified — what was run or checked, and the results.]

## Related work
[Links to related issues, discussions, or follow-up, if any exist.]
