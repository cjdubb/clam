
# debugging

Root-cause debugging guidance for orchestrator sessions: a single skill
sequences a bug from reported symptom to a confirmed root cause —
establishing a reliable reproduction, mining what changed, running a
differential diagnosis, isolating by binary search, and gathering log and
database evidence, handing the engineer exact queries to paste results back
whenever the orchestrator lacks direct access itself. Once a cause is
confirmed, the loop doesn't stop there: it generalizes the instance to its
defect class, sweeps for other latent members, and proposes a guardrail —
class-level recurrence prevention, not just the one fix — before wrap-up.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install debugging@clam
```

No configuration required. The plugin is skill-driven — installing it adds
the `/debugging:root-cause` skill and its supporting scripts; there is no
setup command, no config file, and no prerequisite.

## What to expect

Installing changes nothing on its own: there are no hooks, so nothing fires
and no context is injected into sessions just because the plugin is
present. The plugin is inert until the root-cause skill runs — invoked
directly with `/debugging:root-cause`, or picked up automatically, since the
skill is also model-invocable: a session that runs into a bug, a
regression, or any "why is this happening?" question mid-conversation can
start the loop without an explicit command.

Once a loop starts, `debug-session.sh start <slug>` creates
`.local/debug/NNN-<slug>/` (sequentially numbered) under the current working
directory's `.local/`, and each `debug-session.sh query` call adds a
`queries/NN-<name>/` directory beneath it — the only files this plugin
creates or reads. No settings are written.

## Common workflows

### Running a root-cause investigation

Phase by phase, the orchestrator experiences: intake (expected vs actual,
scope, first-seen, distilled into a one-line problem statement); session
setup (`debug-session.sh start <slug>` creates the session directory every
later phase journals into); reproduce (reach a reliable repro before deep
diagnosis); what changed (build the candidate-change timeline across every
change surface); differential diagnosis (a hypothesis table, weighed and
pruned probe by probe); isolate (binary-search whatever search space
survives); evidence gathering (logs and database, queried directly or handed
to the engineer via paste-back); a root-cause gate that accepts a cause only
once it explains every piece of recorded evidence; prevention (once the gate
passes, generalizing the confirmed cause to its defect class, sweeping for
other latent instances, and proposing a guardrail — declining one requires a
journaled cost/benefit rationale and engineer sign-off); and wrap-up, where
the journal gets its root-cause statement, fix direction, and a note that
the reproduction becomes the regression test.

### Handing evidence to the engineer via paste-back

Each investigation directory pairs `journal.md` (the running record the
orchestrator keeps current through every phase) with `queries/`, which holds
one `NN-<name>/` directory per piece of external evidence gathered, each
pairing the query file itself with a `results.md`.

When the orchestrator can't reach logs or the database directly from the
session, it writes the exact query into the query file and fills in
`results.md`'s header, then hands the engineer that file's path and asks
them to paste the raw output into its Results section. The orchestrator
writes the Interpretation only after those results arrive, feeding the
finding back into the journal's Hypotheses table.

## Commands

### Skills

- `/debugging:root-cause` — sequences the root-cause debugging loop
  described above, phase by phase, from symptom intake to a confirmed root
  cause and mandatory class-level prevention. Also model-invocable: a
  session that runs into a bug, a regression, or any "why is this
  happening?" question can start the loop without the explicit command.

### Scripts

- `scripts/debug-session.sh start <slug>` — creates the next-numbered
  session directory `.local/debug/NNN-<slug>/`, containing a fresh
  `journal.md` (copied verbatim from `templates/journal.md`) and an empty
  `queries/` subdirectory. Run from the repo/worktree root (`.local/` must
  already exist there).
- `scripts/debug-session.sh query <session-dir> <name> [ext]` — creates the
  next-numbered query directory `<session-dir>/queries/NN-<name>/`,
  containing an empty `query.<ext>` file (`ext` defaults to `txt`) and a
  `results.md` (copied verbatim from `templates/query-results.md`).

### Components

| Component | Role |
| --- | --- |
| `skills/root-cause/SKILL.md` | Sequences the root-cause debugging loop phase by phase; defers technique depth to `references/`. |
| `references/reproduce.md` | Technique reference for reaching a reliable, quantified reproduction. |
| `references/what-changed.md` | Technique reference for building the candidate-change timeline across every change surface. |
| `references/differential-diagnosis.md` | Technique reference for building and weighing the hypothesis table until one survivor explains all evidence. |
| `references/binary-search.md` | Technique reference for halving history, code path, data, configuration, or environment to isolate a cause. |
| `references/logs.md` | Technique reference for gathering log evidence, direct or via paste-back, across common log tools. |
| `references/database.md` | Technique reference for read-only database evidence gathering, direct or via paste-back. |
| `references/prevention.md` | Technique reference for generalizing a confirmed cause to its defect class, sweeping for latent instances, and choosing a guardrail. |
| `templates/journal.md` | Per-investigation journal template, copied verbatim into each new session directory. |
| `templates/query-results.md` | Paste-back results template, copied verbatim into each query directory. |
| `scripts/debug-session.sh` | CLI that creates the numbered session and query directories from the templates above. |

Editing the two templates: their section names, table headers, header keys
and paste marker are load-bearing, not cosmetic. `skills/root-cause/SKILL.md`,
`references/logs.md`, `references/database.md` and the structure tests all
refer to them by these exact names — rename one and the reference silently
stops matching. Placeholders stay in `[brackets]` so an unfilled journal is
recognizable as unfilled.

## Relationships to other plugins

None required. This plugin is fully standalone.

## Uninstalling

```
/plugin uninstall debugging@clam
```

Uninstalling removes the skill and scripts; it does not remove past
investigations. `.local/debug/NNN-<slug>/` directories created by
`debug-session.sh` are left in place (`.local/` is already gitignored, so
they were never committed) — delete them by hand if you want them gone.
