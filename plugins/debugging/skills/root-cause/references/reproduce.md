
# Reliable Reproduction

When to use: before diving into deep diagnosis (differential diagnosis, binary search, log/database evidence) — root-causing a bug you can't reliably reproduce means every later finding might just be noise. Reach a reliable repro first; this reference covers how.

## Goal

Reliable means: the same steps produce the same failure every time, quantified as a ratio, not a feeling. "Usually happens" is not reliable; "5/5 runs" or "N/N over the last 20 attempts" is. Define your target ratio before you start minimizing or automating — you're not done until you hit it (or you've deliberately accepted a flaky repro, see below).

## Capture

Freeze the exact failing input, environment, dependency and runtime versions, and any relevant data — before touching anything else, save state that could otherwise change or vanish:

- Copy the failing input/request/payload verbatim.
- Record the environment: OS, container image, feature-flag state, environment variables.
- Pin versions: application build/commit, language runtime, library versions, OS packages.
- Snapshot any data involved (DB rows, cache contents, file state) if it's mutable and might drift before you get back to it.

Do this before you retry, restart, redeploy, or "just try one thing" — those actions are exactly what destroys the reproducible state you're trying to capture.

## Minimize

Shrink the input and the steps while the failure still happens. Remove one variable at a time — inputs, config, code paths, data — and re-check after each cut; back out a cut the moment the failure stops. The smallest repro wins: fewer moving parts means fewer places the root cause can hide, and it makes every later technique (differential diagnosis, binary search) faster to run.

## Automate

Turn the repro into something that runs without you: a script, or — better — a failing test in the repo's own test runner. Prefer a failing test over a manual script or a recording of steps: it runs in CI, it can't drift from the real repro steps, and it becomes the regression test that proves the eventual fix. If a failing test isn't reachable yet (missing harness, no test infra for this path), automate with a script first and convert it to a test as soon as you can.

## Flaky and intermittent

Estimate frequency first: run the repro N times and record the ratio (e.g. 3/10). That number is data — it tells you how much weight to put on any later "it didn't reproduce" result.

Force the conditions that intermittency usually hides in:

- **Timing** — add delays, run under a debugger, or remove artificial waits to shift race windows.
- **Concurrency** — increase parallel load; run multiple workers/threads/requests at once instead of one.
- **Load** — push CPU, memory, disk, or network closer to the levels seen when it failed.
- **Data variance** — vary input size, shape, and edge-value content instead of reusing one fixed sample.
- **Environment** — try the specific failing environment (staging vs. prod, specific OS/container, specific hardware) rather than assuming any environment is equivalent.

Decide when to proceed with a flaky repro: if frequency is low but nonzero and you can't push it higher, move forward but flag it explicitly — a flaky repro weakens every later inference. A "fix" that appears to work against a 1/10 repro needs far more confirming runs than one that works against a 10/10 repro before you trust it.

If you cannot reproduce it at all (frequency effectively zero despite forcing every condition above), stop trying to force a local repro and widen to evidence gathering instead: pull logs and database state from the time of the failure, and treat the repro gap itself as diagnostic information — an issue that won't reproduce outside production is telling you something about what's different there (see logs.md and database.md).

For production-only failures, capture safely: prefer read-only inspection (logs, database queries, metrics, request replay against a copy) over any destructive probing — never run an experiment in production that could damage data, trigger side effects, or take the system down while you're still trying to understand why it's already broken.

## Journal

Record in the session journal:

- **Repro status** — none → flaky → reliable. Start at none, move to flaky once it reproduces at all, move to reliable once it hits a consistent ratio (e.g. 5/5) on the same steps.
- **Steps** — the exact minimized steps that trigger it.
- **Rate** — the observed ratio (e.g. 4/5, 10/10).

Update repro status every time it changes — the ladder position tells every later phase how much to trust the current findings.
