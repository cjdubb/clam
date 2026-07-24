#!/bin/bash
# Canonical pseudo-CI runner: lints, tests, and manifest validation in one gate.
#
# Run: bash scripts/ci.sh [--lint | --test] [--post-status]
#      (exits non-zero on any check failure)

# <!--
# Contract: B02 ci-runner (plan 001-pseudo-ci)
#
# Behavior:
#   Runs the repo's full check suite in three stages, in order:
#     1. lint     — bash scripts/marketplace-lint.sh, bash
#                   scripts/executable-lint.sh, bash scripts/readme-lint.sh,
#                   bash scripts/version-bump-lint.sh (each invoked from the
#                   repo root; readme-lint requires root cwd).
#     2. test     — every repo-level scripts/*.test.sh, then every
#                   plugins/*/scripts/*.test.sh and plugins/*/lib/*.test.sh,
#                   each via bash.
#     3. validate — claude plugin validate .claude-plugin/marketplace.json,
#                   then claude plugin validate plugins/<name> for every
#                   plugin directory.
#   Fail-fast: the first failing check stops the run (later checks and
#   stages do not execute) and the runner exits 1. With --post-status, a
#   GitHub commit status is posted for HEAD when the run concludes (pass or
#   fail alike).
#
# Inputs:
#   - Optional stage flag: --lint or --test runs ONLY that stage (at most
#     one stage flag; --lint and --test together is a usage error). No
#     stage flag runs all three stages. (validate has no solo flag; it runs
#     only as part of the full suite.)
#   - Optional flag: --post-status — after the run, POST the outcome to
#     GitHub as a commit status on HEAD's sha: context "pseudo-ci", state
#     "success" or "failure", via gh api, repo derived from the origin
#     remote URL.
#   - Requires: git, bash, jq. Optional: claude (validate stage), gh
#     (--post-status).
#   - No environment variables, no config files — the runner reads NOTHING
#     from .claude/ or .local/; it is the standalone source of truth that
#     plugin-workflow configs delegate to, never the reverse.
#
# Outputs:
#   - A "== <stage> ==" header line per stage as it starts; each check's
#     own output passes through beneath it, prefixed by a "-- <check>" line.
#   - Skip notices: "WARN  validate skipped (claude CLI not found)" when
#     claude is absent; "WARN  status not posted (<reason>)" when
#     --post-status cannot complete (gh absent, unauthenticated, no origin
#     remote, network failure). Skips never affect the exit code.
#   - A stage with nothing to run (e.g. no test files) prints "no <stage>
#     checks to run" and counts as a pass.
#   - Final line: "CI PASS" or "CI FAIL: <stage>/<check>".
#   - Exit codes: 0 all executed checks passed (skips allowed), 1 a check
#     failed, 2 usage/environment error.
#
# Errors:
#   - Unknown flag, or both --lint and --test: usage line on stderr, exit 2.
#   - Not inside a git repository: diagnostic on stderr, exit 2.
#   - A lint/test script that exits 2 (its own environment error, e.g.
#     missing jq) is reported as that check's failure: CI FAIL, exit 1.
#
# Invariants:
#   - Read-only with respect to the repo; the only side effect is the
#     optional gh status POST (never attempted without --post-status).
#   - cwd-independent: resolves the repo root via git rev-parse and runs
#     every check from there.
#   - Stage order is fixed (lint, test, validate); check order within a
#     stage is fixed (lints as listed; tests sorted lexicographically,
#     repo-level before plugins).
#   - The status POST (when requested) reflects the true outcome: success
#     only when the run would exit 0; a fail-fast run still posts failure
#     before exiting.
#   - Requires only bash+git+jq for the gate itself: claude and gh are
#     optional enhancers whose absence degrades to WARN, never to a
#     failure or a silent skip.
#
# Edge cases:
#   - Repo with no plugins/ dir or no test files anywhere: each empty
#     stage vacuously passes with its notice; CI PASS.
#   - claude present but a validate check fails: CI FAIL, exit 1 (absence
#     WARN-skips; presence gates).
#   - --post-status on a sha that does not exist on the remote yet: the
#     POST still succeeds (GitHub accepts statuses for unknown shas and
#     attaches them when the sha arrives) — no special handling.
#   - --post-status with a non-GitHub origin remote: WARN, no POST, exit
#     code unaffected.
#   - Interrupted run (signal): no status is posted; partial output stands.
# -->

echo "NotImplemented: B02 ci-runner" >&2
exit 99
