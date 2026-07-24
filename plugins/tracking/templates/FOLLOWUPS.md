<!--
Contract: B01 followups-template

Behavior:
  Template/reference for `.local/FOLLOWUPS.md` — the durable, structured home
  for conversation-surfaced follow-up work (items "worth filing later",
  deferred product changes, out-of-scope defects noticed in passing). Created
  LAZILY: the injected tracking rules (B02) instruct the agent to instantiate
  this template on FIRST capture; no hook auto-creates it, and most sessions
  never create it. Entries are appended in real time at the moment a
  follow-up is mentioned, and are dispositioned in place — never deleted,
  never renumbered.

Inputs: n/a (template file; placeholders in [brackets]).

Outputs (required document structure — tests assert these):
  - H1: `# Follow-ups`, followed by a short usage paragraph that states: one
    entry per follow-up, appended at mention time; entries are dispositioned
    (Status edited in place), never deleted; `dropped` requires a reason.
  - The entry format, documented once and shown as ONE bracketed example
    entry:
      ## F<NN> — [short title]
      - Status: open | filed [issue-ref] | resolved | dropped ([reason])
      - Captured: [YYYY-MM-DD]
      - Source: [provenance — where/how it surfaced, e.g. "verifying U15"]
      - Refs: [soft refs: blocks, plans, PRs, issues] | none
      - Statement: [the follow-up in one or two sentences]
    F<NN> is a zero-padded sequence number scoped to this file (F01, F02, …).

Errors: n/a (template content).

Invariants:
  - `- Status: open` (exactly, modulo trailing whitespace) is the machine-read
    OPEN marker — consumed by keep-working.sh's close-out gate (B03) and
    session-context.sh's surfacing (B02). The other Status values are
    dispositions and end the entry's open state.
  - Placeholders use [brackets] so an unfilled example is recognizable.
  - Soft references only in Refs: entries point at primary-work artifacts
    (blocks.md ids, plan paths, PR/issue numbers); nothing in the primary
    work graph is required to point back.

Edge cases:
  - Several items captured the same day → distinct F<NN>, same Captured date.
  - An item out of scope for ALL current work → valid; Refs: none.
  - File absent → zero captures so far; consumers treat absence as "nothing
    open" (valid, not an error).
-->

# Follow-ups

One entry per follow-up, appended at the moment it's mentioned. Entries are dispositioned in place — the Status line is edited, never deleted; a `dropped` disposition requires a reason.

## F01 — [short title]
- Status: open | filed [issue-ref] | resolved | dropped ([reason])
- Captured: [YYYY-MM-DD]
- Source: [provenance — where/how it surfaced, e.g. "verifying U15"]
- Refs: [soft refs: blocks, plans, PRs, issues] | none
- Statement: [the follow-up in one or two sentences]

F<NN> is a zero-padded sequence number scoped to this file (F01, F02, …).
