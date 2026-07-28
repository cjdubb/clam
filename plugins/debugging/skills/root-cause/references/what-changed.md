
# What Changed

When to use: once you have a repro (or a flagged flaky one), whenever the issue looks like a regression — something that used to work and now doesn't. This builds the candidate-change timeline that differential diagnosis tests against.

## Establish the window

Anchor two timestamps before you look at anything else: last-known-good (the last confirmed-working state) and first-seen (the earliest confirmed occurrence of the symptom). Everything between them is your search window — every change surface below only matters if it falls inside it.

Narrow both ends as tightly as the evidence allows: check monitoring/alerting history for first-seen, and check deploy or release history plus user reports for last-known-good. A wider window means more noise to sift through later, so spend real effort tightening it before moving to Change surfaces.

Edge case — never worked: if the issue never worked, there is no last-known-good state to anchor, and this technique's window narrowing doesn't apply. Reframe from regression-hunting to first-principles diagnosis: analyze the intended design and behavior directly instead of hunting for a change that broke it.

## Change surfaces

Walk every one of these surfaces exhaustively — this is a checklist, not a menu to sample from. Skipping a surface because it seems unlikely is exactly how root causes hide:

- [ ] **Code commits** — application and library code changed in the window.
- [ ] **Deploys and releases** — what was actually deployed/released, and when, independent of when it was merged.
- [ ] **Config and feature flags** — config file changes, environment variable changes, feature flag toggles.
- [ ] **Dependencies and base images** — package/library version bumps, transitive dependency updates, container base image updates.
- [ ] **Schema and data migrations** — database schema changes, data backfills and migrations.
- [ ] **Infrastructure and platform** — cloud provider changes, platform version upgrades, networking/DNS/load-balancer changes.
- [ ] **External services** — third-party API changes, upstream provider incidents, vendor deprecations.
- [ ] **Data drift** — the shape or volume of data itself changed (new customer segment, seasonal spike, upstream format shift) with no code change at all.
- [ ] **Time-triggered changes** — nothing "changed" in the traditional sense but a clock-driven condition fired: cert expiry, quota reset or exhaustion, daylight saving time (DST) transitions, license/contract expiry.

Every unchecked box is an open question, not an assumption you get to skip.

## Enumerate changes per surface

For each surface above, list what actually changed inside the window — use the authoritative source, not memory:

- **Code commits** — `git log --since=<last-known-good> --until=<first-seen>` and `git diff` between the two revisions.
- **Deploys and releases** — deploy history from the CI/CD system or release dashboard.
- **Config and feature flags** — flag audit logs from the flag platform; config-repo commit history if config is version-controlled.
- **Dependencies** — diff the dependency lockfiles (package-lock.json, poetry.lock, go.sum, etc.) between the two points.
- **Schema and data migrations** — the migration table the migration tool maintains (e.g. schema_migrations), plus migration file history.
- **Infrastructure, external services, data drift, time-triggered** — provider changelogs, status pages, monitoring dashboards, and quota/cert-expiry dates.

When the records for a surface aren't reachable from where you're sitting (no access to the deploy system, no visibility into the flag audit log), ask the engineer where they live — never guess at what changed. A guessed timeline is worse than an incomplete one, because it looks confident.

## Correlate

Line up every candidate change from the previous section against the symptom's onset — the first-seen timestamp anchored in Establish the window. A change that lands right before onset is worth investigating first; a change from days earlier or later is a weaker candidate but not automatically eliminated (deploy trains can spread related changes across a window — see Output).

Correlation is not causation: near-coincidence in time produces a hypothesis, not a verdict. Every candidate still needs confirmation by an independent mechanism — a code read that explains the symptom, a discriminating probe, or a direct test — before you call it the cause.

## Output

Produce a candidate-change list: every change surviving Correlate, each with its timestamp, source (commit SHA, deploy ID, flag name, lockfile diff, etc.), and a one-line note on why it's a candidate. Hand this list to differential diagnosis as the seed set of hypotheses to test against the evidence — this technique narrows the field, it doesn't crown a winner.

Edge case — deploy trains: multiple simultaneous changes released together do not collapse into one candidate. Keep each as a separate hypothesis in the candidate-change list rather than lumping them together as "the deploy." A deploy train that bundles five changes gives you five hypotheses, not one, and differential diagnosis needs them separate to discriminate between them.

## Journal

Record in the session journal:

- **Window** — last-known-good and first-seen timestamps.
- **Surfaces checked** — which of the surfaces above you walked, and what you found (or confirmed unchanged) for each.
- **Candidates** — the candidate-change list from Output, carried forward into the Hypotheses table.
