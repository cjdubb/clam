#!/bin/bash
# Fails when plugin content changed without a plugin.json version bump.
#
# Run: bash scripts/version-bump-lint.sh [--base <ref>] (exits non-zero on failure)

# <!--
# Contract: B01 version-bump-lint (plan 001-pseudo-ci)
#
# Behavior:
#   Computes the commit range merge-base(<base>, HEAD)..HEAD and lists every
#   committed change (added, modified, deleted, renamed) under plugins/. For
#   each plugin directory plugins/<name>/ with at least one changed file,
#   requires that the "version" value in plugins/<name>/.claude-plugin/
#   plugin.json at HEAD differs from its value at the merge-base. There are
#   NO exemptions: README, docs, and test changes all count — installed
#   copies are whole-directory snapshots keyed by version, so any content
#   change that ships without a bump silently never reaches installs.
#
# Inputs:
#   - Optional flag: --base <ref> — the comparison base. Default: origin/master
#     if it exists, else master. Anything else (including a missing value
#     after --base, or an unknown flag) is a usage error.
#   - The git repository containing the cwd (root found via
#     git rev-parse --show-toplevel); the COMMITTED range only — uncommitted
#     and staged changes are ignored.
#   - Requires: git, jq, bash. No environment variables, no config files.
#
# Outputs:
#   - One line per plugin with changes in the range:
#       PASS  <name> (version <old> -> <new>)
#       FAIL  <name> -> files changed but version unchanged (<version>)
#   - Plugins with no changes in the range produce no line.
#   - No plugin changes at all: "no plugin changes to check" and exit 0
#     (vacuous pass).
#   - Blank line, then "ALL PASS" (exit 0) or "FAILURES — fix before merging"
#     plus a remediation hint naming each offending plugins/<name>/
#     .claude-plugin/plugin.json (exit 1).
#
# Errors:
#   - Not inside a git repository: diagnostic on stderr, exit 2.
#   - Neither the given --base ref nor the defaults (origin/master, master)
#     resolve to a commit: diagnostic on stderr, exit 2.
#   - jq not available: diagnostic on stderr, exit 2.
#   - plugin.json at HEAD missing or unparseable for a plugin whose files
#     changed (and which still exists at HEAD): FAIL line for that plugin,
#     exit 1 — a changed plugin must always carry a readable version.
#   - Usage errors (unknown flag, --base without a value): usage line on
#     stderr, exit 2.
#
# Invariants:
#   - Read-only: never modifies files, the index, or git state.
#   - cwd-independent: resolves the repo root and evaluates from there.
#   - Exit codes: 0 pass (including vacuous), 1 lint failure, 2
#     usage/environment error — never anything else.
#   - "Version changed" means the JSON string values differ; no semver
#     ordering is enforced (a decrease still counts as changed).
#   - Only plugins/<name>/** participates; changes elsewhere (scripts/,
#     README.md, .claude-plugin/marketplace.json) are ignored.
#
# Edge cases:
#   - New plugin (no plugin.json at merge-base): PASS provided plugin.json
#     exists at HEAD with a non-empty "version" string.
#   - Plugin deleted entirely at HEAD (no files remain): skipped — entry
#     consistency is marketplace-lint's territory.
#   - Change is plugin.json alone with only the version differing: PASS
#     (the bump itself is a change and satisfies the rule).
#   - plugin.json changed (e.g. description) but version value identical:
#     FAIL.
#   - File renamed across plugin dirs: counts as a change for BOTH source
#     and destination plugins.
#   - HEAD equals the merge-base (branch even with base): vacuous pass.
#   - Files directly under plugins/ not inside any <name>/ dir (e.g.
#     plugins/PLUGIN_README_TEMPLATE.md): ignored — they belong to no
#     plugin and have no version to bump.
# -->

echo "NotImplemented: B01 version-bump-lint" >&2
exit 99
