
# Follow-ups

One entry per follow-up, appended at the moment it's mentioned. Entries are dispositioned in place — the Status line is edited, never deleted; a `dropped` disposition requires a reason.

## F01 — [short title]
- Status: open | filed [issue-ref] | resolved | dropped ([reason])
- Captured: [YYYY-MM-DD]
- Source: [provenance — where/how it surfaced, e.g. "verifying U15"]
- Refs: [soft refs: blocks, plans, PRs, issues] | none
- Statement: [the follow-up in one or two sentences]

F<NN> is a zero-padded sequence number scoped to this file (F01, F02, …).

Entry titles are plain language — the follow-up as a reader would say it out loud, with no borrowed id in the title; ids from other numbering systems belong in `Refs:`.

A follow-up captured mid-effort also gets a work-graph node at capture, not once it is acted on, so the work it implies is visible wherever work is read. Mirror the entry's disposition onto that node as the entry resolves.

A follow-up deferred to a future effort stays `open` — in this file and on its node. `dropped` means nobody should ever pick it up, and its reason must say why the work is not wanted; "nowhere to file it" is never that reason, because this file is where it is filed.
