#!/usr/bin/env bash
# Contract: B05 issue-template-lint (plan 001-repo-issue-template)
# Behavior:
#   Verifies the GitHub issue templates stay valid and in sync with the
#   repo. Checks, in order:
#     1. .github/ISSUE_TEMPLATE/{feature.yml,bug.yml,config.yml} all exist.
#     2. YAML parse check: each file parses. Runs only when a parser is
#        available (python3 with the yaml module); when unavailable, prints
#        "SKIP yaml-parse (no parser)" to stderr and continues with the
#        structural checks below — never fails solely for lack of a parser.
#     3. feature.yml declares label `feature`; bug.yml declares label `bug`
#        (a `labels:` list containing exactly that one label).
#     4. In BOTH forms, the id=plugin dropdown's options are exactly
#        "repo-wide / other" followed by every plugins/* directory name in
#        alphabetical order — no missing, extra, duplicated, or misordered
#        entries.
#     5. config.yml sets blank_issues_enabled: false and has no
#        contact_links key.
# Inputs:
#   Runs from the repo root (no arguments). Reads .github/ISSUE_TEMPLATE/*
#   and the plugins/ directory listing (directories only; files such as
#   plugins/PLUGIN_README_TEMPLATE.md are ignored).
# Outputs:
#   Exit 0 when every check passes (prints "issue-template-lint: OK" to
#   stdout). On failure, one line per violation to stderr, exit 1.
# Errors:
#   Missing plugins/ or .github/ISSUE_TEMPLATE/ directory (not run from
#   repo root): message to stderr, exit 2.
# Invariants:
#   - Read-only: never modifies any file.
#   - No hard dependency beyond bash + coreutils; python3/yaml is an
#     opportunistic upgrade, not a requirement.
#   - Reports ALL violations found, not just the first.
# Edge cases:
#   - Empty plugins/ dir: expected options are just "repo-wide / other".
#   - Options listed under a different field id than `plugin`: violation
#     (stable ids are part of the form contracts B01/B02).
#   - Comment-only or empty template file: fails checks 3-5 (and 2 where a
#     parser is present and the file is invalid).

echo "NotImplemented: B05 issue-template-lint — stub; implementation lands via lego dispatch U02." >&2
exit 1
