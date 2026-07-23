#!/usr/bin/env bash
# Contract: B01 readme-conformance-lint (plan 002-readme-conformance)
# Behavior:
#   Verifies every plugins/*/README.md conforms to the locked template
#   (plugins/PLUGIN_README_TEMPLATE.md): the 6 required H2 headings are
#   present with exact names in exact order —
#     ## Getting started
#     ## What to expect
#     ## Common workflows
#     ## Commands
#     ## Relationships to other plugins
#     ## Uninstalling
#   — and any extra H2 sections (## Tests or plugin-specific) appear ONLY
#   between "## Commands" and "## Relationships to other plugins".
#   Prints one PASS/FAIL line per plugin README (FAIL lines name the first
#   violation: which heading is missing, out of order, or misplaced).
# Inputs:
#   Runs from the repo root (no arguments). Reads plugins/*/README.md.
#   A plugin directory without a README.md is a FAIL (every plugin must
#   have one). plugins/PLUGIN_README_TEMPLATE.md itself is exempt.
# Outputs:
#   Exit 0 when every plugin README passes; exit 1 when any fails.
#   Report lines go to stdout; one line per plugin, FAILs list the reason.
# Errors:
#   Missing plugins/ directory (not run from repo root): message to stderr,
#   exit 2.
# Invariants:
#   - Read-only: never modifies any file.
#   - Only lines starting with exactly "## " count as H2s; H2-looking text
#     inside fenced code blocks or HTML comments must not count.
#   - Deterministic: same tree -> same output and exit code.
# Edge cases:
#   - README with no H2s at all: FAIL (all required missing).
#   - Required headings present but in wrong order: FAIL naming the first
#     out-of-order heading.
#   - Duplicate required heading: FAIL.
#   - Extra H2 before "## Commands" or after "## Relationships to other
#     plugins": FAIL naming the misplaced section.
#   - Trailing whitespace or case variation in a required heading: FAIL
#     (exact match required).
set -euo pipefail

echo "NotImplemented: B01 readme-conformance-lint" >&2
exit 1
