# Feature: [FEATURE NAME]
Ticket: [TICKET-KEY] <!-- omit this line under issue provider `none` (see the issue-tracker skill) -->
Branch: [branch-name]
Started: [YYYY-MM-DD]
Last Updated: [YYYY-MM-DD HH:MM]

## Status
<!-- State: Not Started | In Progress | Awaiting Agent | Awaiting CI | Awaiting Independent Agent Review | Awaiting User Review | Awaiting Bot Review | Awaiting Reviewer Assignment | Awaiting Human Review | Awaiting Merge Queue | Waiting For Decision | Blocked | Complete.
     Blocked, Waiting For Decision, and Awaiting User Review summon the user (bell, dashboard flag, push). Awaiting User Review summons once on entry, then parks; the other Awaiting * states are parked-but-fine: stop allowed, stays silent.
     Decision Needed format: question; recommended option; .local/decisions/ file path. -->
State: Not Started
Current Task:
Last Updated: [YYYY-MM-DD HH:MM]
Blocked Reason:
Decision Needed:

## Tasks
- [ ] Analyze requirements and existing code
- [ ] Design solution approach
- [ ] Implement core functionality
- [ ] Add error handling and boundary validation

## Testing
- [ ] Write unit tests
- [ ] Write integration tests
- [ ] Verify all tests pass

## Pre-PR
- [ ] Format code
- [ ] Lint passes
- [ ] Unit tests pass
- [ ] Integration tests pass

## Implementation Log
{When you complete a task that involved a choice, note what you chose and why.}

-

## Blockers/Notes
-

<!-- Contract: B06 — todo-open-questions
Behavior:
  The template gains a "## Open Questions" section (directly below this
  comment, above Discovered Tasks) giving unresolved conversation threads a
  durable, structured home that survives /clear and compaction — e.g. a
  question the engineer asked that was never answered, or a naming/design
  thread left hanging ("Knobs vs Options?"). Each entry is one bullet:
  the question, enough context to resume it cold, and who owes the answer.
  Entries are REMOVED (not struck through) once answered, with the answer
  recorded where it belongs (Implementation Log, PLAN.md Changelog, or a
  decisions/ file).
Inputs:  n/a (template content).
Outputs: the section header plus a one-line placeholder hint bullet in the
  same style as the sections above ("{...}" guidance line, then "-").
Errors:  n/a.
Invariants:
  - Section order: ...Implementation Log, Blockers/Notes, Open Questions,
    Discovered Tasks.
  - The companion rule line ships in session-context.sh's injected rules
    heredoc (same work unit U04): one sentence instructing agents to park
    unresolved threads in TODO.md's Open Questions section in real time and
    to clear entries when resolved.
Edge cases:
  - Existing worktrees' TODO.md files are NOT migrated; the section applies
    to newly instantiated templates (auto-create and manual copies).
-->

## Open Questions
{Unresolved threads: the question, enough context to resume it cold, and who owes the answer. Remove the entry once answered — record the answer in the Implementation Log, PLAN.md's Changelog, or a decisions/ file.}

-

## Discovered Tasks
-
