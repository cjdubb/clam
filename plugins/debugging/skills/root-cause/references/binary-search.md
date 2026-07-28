
# Binary Search

When to use: you have a large search space of candidates and a reliable discriminator — a repro or check that reliably says good or bad. Without a reliable discriminator, get one first (see reproduce.md); bisecting on a flaky signal wastes probes and misleads instead of narrowing anything.

## Prerequisite

Binary search needs one thing before it can start: a reliable discriminator, usually the repro established in phase 3. The discriminator is the yes/no test you run at each probe — it must return the same answer every time for the same state, or the halving logic breaks.

A flaky discriminator corrupts the search: a "good" result you get by luck looks identical to a "good" result you get because the fix is really there. Every wrong answer throws away half the search space based on noise, not signal. If the only discriminator available is flaky, spend the effort to make it reliable first (repeat runs, force the flake's triggering conditions, or fall back to a sturdier signal) before bisecting. Confirm both endpoints first — verify the "bad" end genuinely fails and the "good" end genuinely passes, using the discriminator, before you halve anything.

## Dimensions

Binary search halves whatever search space you're in. Five dimensions come up in practice:

- **History** — commits between last-known-good and first-seen. `git bisect` is the primary tool:

  ```
  git bisect start
  git bisect bad HEAD
  git bisect good <last-known-good-sha>
  # git checks out the midpoint; run the discriminator, then report:
  git bisect good   # or: git bisect bad
  # repeat until git reports the first bad commit
  git bisect reset
  ```

  When the discriminator can run as a script that exits 0 for good and nonzero for bad, automate the whole walk with `git bisect run <script>` instead of stepping by hand.
- **Code path** — halve within a single commit or a single request's execution. Add instrumentation (logging, a debugger breakpoint) at the midpoint of the call path, or insert an early return that short-circuits the second half; whichever half still reproduces contains the fault.
- **Data** — halve the input. If a batch of 10,000 records triggers the bug, split it and run each half; keep bisecting the half that still fails until you reach the smallest failing input.
- **Configuration** — halve the set of enabled flags/settings. Toggle half of the suspect configuration off, rerun the discriminator, and recurse into whichever half still fails.
- **Environment** — diff two environments (versions, env vars, resource limits) and swap halves of the difference between them, rerunning the discriminator after each swap, until only the causal difference remains.

## Discipline

One variable per probe. A probe is: hold everything else fixed, change exactly one thing, run the discriminator, record the result.

Before every probe, write down in the journal:

- **Hypothesis** — what you expect to find and why (e.g. "if the bug is in commits after X, this midpoint should fail").
- **Probe** — the exact commit/input/flag/config you're about to test.
- **Expected** — the outcome that would confirm the hypothesis.
- **Observed** — what actually happened, filled in after running it.

Stop when the culprit is minimal: one commit, one input, one flag. That is the terminal state of a binary search — further halving isn't possible or useful once you're down to a single unit of change.

Edge case — search space of one: if the surviving search space is already a single candidate change, skip bisection altogether and verify directly instead of manufacturing halves that don't exist.

## Pitfalls

- **Flaky discriminator** — the single biggest risk; see Prerequisite. If results stop being reproducible mid-search, stop and re-stabilize the discriminator before trusting any further probe.
- **Unbuildable commits** — some midpoint commits won't build or won't run (broken CI checkpoints, WIP commits). Use `git bisect skip` to exclude them without breaking the halving.
- **Non-monotonic spaces** — bisection assumes bad/good is monotonic across the ordering being halved. Intermittent regressions often violate this: a commit or config can pass and fail unpredictably regardless of position in the range, so halving gives meaningless results. When you suspect a non-monotonic space, stop bisecting and fall back to differential diagnosis instead of forcing further probes.
- **Fix-masking interactions** — a later, unrelated commit can hide or paper over the real bug (e.g. a retry loop added afterward masks a race). A bisect can point at the masking commit instead of the true cause; when the "culprit" doesn't causally explain the symptom, keep digging past it.

## Journal

Every probe becomes a Probe Log row in the session journal: When, Probe, Expected, Observed. Fill in Expected before running the probe, not after — that is what keeps the discipline honest and lets you notice when your model of the bug is wrong as you go.
