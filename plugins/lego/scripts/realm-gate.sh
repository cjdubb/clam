#!/usr/bin/env bash
# realm-gate.sh — PreToolUse hook: mechanical realm enforcement for lego workers.
#
# Contract: B04 realm-gate-local-readonly
#
# New clauses in plan 001 are marked (NEW, plan 001); every other clause is
# pre-existing behavior.
#
# Behavior:
#   Reads the hook input JSON on stdin. When the running agent is a lego
#   worker (agent_type ends in lego-test-writer or lego-implementer), denies
#   Edit/Write/NotebookEdit calls whose target file is outside the agent's
#   realm:
#     lego-test-writer  → may ONLY touch test-family files
#     lego-implementer  → may NEVER touch test-family files
#   (NEW, plan 001) Additionally denies, for BOTH worker roles and evaluated
#   before the realm-family rules above, any call whose target path contains
#   a path segment exactly ".local": the unit worktree's .local/
#   (config.json, unit.md, contracts/, status.md, briefs/) is
#   orchestrator-owned and read-only for workers. This deny fires even for
#   paths the realm rules would allow (e.g. a lego-test-writer targeting
#   .local/__tests__/x.test.js, or a lego-implementer targeting
#   .local/status.md).
#   (#184) One carve-out precedes the .local deny and every realm-family
#   rule: a path containing the consecutive segment pair ".local/reports/"
#   followed by at least one further segment is ALLOWED, for both roles.
#   That file is the worker's own final report, which it writes itself; the
#   exemption from the realm-family rules is what lets a lego-test-writer
#   write its report at all (a report is a .md, which the test family would
#   otherwise deny it).
#   All other agents (including the main session) pass through untouched.
#
# Inputs:
#   Hook JSON on stdin: .agent_type, .tool_input.file_path or
#   .tool_input.notebook_path. Missing/empty agent_type or file path →
#   pass through.
#
# Outputs:
#   On deny: one line of JSON — hookSpecificOutput with permissionDecision
#   "deny" and a permissionDecisionReason naming the violated rule and
#   directing the worker to STOP and return an ESCALATION report.
#   (NEW, plan 001) The .local deny reason states that .local/ is
#   orchestrator-owned and read-only for workers. (#184) It also names
#   .local/reports/ as the one path under .local/ the worker may write, so a
#   denied worker is pointed at its report file rather than left guessing.
#   On allow: no output. Always exit 0.
#
# Errors:
#   Never blocks on its own failure: without jq, falls back to sed-based
#   field extraction; unparseable input passes through (exit 0, no output).
#
# Invariants:
#   - Only lego worker agent types are ever denied; any other agent_type
#     (including none) always passes through.
#   - Read-only: inspects stdin only; writes nothing to disk.
#   - DEPENDENCY SEAM (B04, plan 001-speed-up-repo-ci): the jq dependency is
#     reached through `: "${JQ:=jq}"` and invoked as "$JQ", never as a bare
#     `jq`. Absence is detected with `command -v "$JQ"`. This is the public
#     seam tests use to exercise the jq-absent path — they set
#     JQ=/nonexistent instead of constructing a PATH without jq. Observable
#     CLI behaviour is UNCHANGED by this: same stdin contract, same stdout,
#     same exit codes, including when jq is genuinely missing from PATH.
#   - SOURCEABILITY (B05, plan 001-speed-up-repo-ci): the script guards its
#     entry point with `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` so a test can
#     source it and call its public function in-process rather than forking.
#     The contract boundary is unchanged — the public function IS the
#     interface; tests still never reach into internals.
#   - (#184) A worker's report file under .local/reports/ is the single
#     writable path inside .local/, for both roles; every other path under
#     .local/ is denied exactly as before.
#
# Edge cases:
#   - (NEW, plan 001) ".local" must match a whole path segment: "a/.local/b"
#     and ".local/b" are denied (as is a path whose final segment is
#     ".local"); "my.local/b", "xlocal/b", and "a/local/b" are not denied by
#     this rule. Both relative and absolute paths match — the test is on the
#     path string, not the filesystem.
#   - (#184) The carve-out's segments are matched exactly too, and only as a
#     consecutive pair: ".local/reports/x" and ".local/reports/a/b" are
#     allowed; ".local/reports" and ".local/reports/" are denied (no further
#     segment, so they name the directory, not a report);
#     ".local/reportsx/y" is denied (it is under .local/, and "reportsx" is
#     not "reports"); "my.local/reports/x" has no ".local" segment at all, so
#     neither this rule nor the .local deny applies and the realm-family
#     rules decide it.
#   - (#184) A "." or ".." path segment anywhere in the path disqualifies
#     the carve-out, and the path falls through to the rules above — so
#     ".local/reports/../status.md" is denied by the .local rule rather than
#     allowed as a report. The check is on the path string, never the
#     filesystem, so it cannot resolve traversal; refusing it is the only
#     safe reading. ".local/reports/./x.md" and ".local/reports/a/../b.md"
#     are denied on the same rule even though they resolve harmlessly: the
#     worker always has the clean literal path its brief names. "Segment"
#     is exact, so dots inside a name — ".local/reports/01-test-B01.md",
#     ".local/reports/..stray/x.md" — are not dot segments and stay allowed.
#
# This gate covers file tools only; Bash-based writes are caught post-hoc by
# realm-check.sh, which the orchestrator runs at each wave boundary.
set -euo pipefail
: "${JQ:=jq}"

input="$(cat)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v "$JQ" >/dev/null 2>&1; then
  if ! agent_type="$(printf '%s' "$input" | "$JQ" -r '.agent_type // empty' 2>/dev/null)"; then
    exit 0
  fi
  if ! file_path="$(printf '%s' "$input" | "$JQ" -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"; then
    exit 0
  fi
else
  # Best-effort fallback without jq: extract simple string fields.
  agent_type="$(printf '%s' "$input" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  file_path="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [ -z "$file_path" ]; then
    file_path="$(printf '%s' "$input" | sed -n 's/.*"notebook_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  fi
fi

case "$agent_type" in
  *lego-test-writer) role="test" ;;
  *lego-implementer) role="impl" ;;
  *) exit 0 ;;
esac

[ -n "$file_path" ] || exit 0

reason=""

# (#184) Carve-out, evaluated before BOTH the .local deny and the
# realm-family rules: a worker writes its own final report to
# .local/reports/NN-<wave>-<blocks>.md. Requires the consecutive segment pair
# ".local/reports/" plus at least one further segment, so the directory
# itself (".local/reports", ".local/reports/") stays denied. The remainder is
# taken after the LAST such pair and must be a real segment — neither empty
# nor slash-led — which is what distinguishes a report file from the
# directory that holds them.
#
# A "." or ".." path segment ANYWHERE in the path disqualifies the carve-out
# outright, before the remainder is even considered: ".local/reports/../
# status.md" reads as a report file but resolves to ".local/status.md", so
# without this the carve-out would be a hole straight through the .local
# deny it sits in front of. Disqualified paths simply fall through to the
# rules below, where the .local deny catches them. Only whole segments
# count, so dots inside a name (01-test-B01.md) are untouched.
case "$file_path" in
  .local/reports/*|*/.local/reports/*)
    case "$file_path" in
      .|..|./*|../*|*/.|*/..|*/./*|*/../*) : ;;
      *)
        case "${file_path##*.local/reports/}" in
          ""|/*) : ;;
          *) exit 0 ;;
        esac
        ;;
    esac
    ;;
esac

# (NEW, plan 001) .local/ is orchestrator-owned and read-only for workers.
# Evaluated before the realm-family rules below; matches a whole path
# segment exactly ".local" (first, middle, or final; relative or absolute).
# Substring lookalikes (my.local/b, xlocal/b, a/local/b) must not match.
case "$file_path" in
  .local|.local/*|*/.local|*/.local/*)
    reason=".local/ is orchestrator-owned and read-only for workers, with one exception: your own report file under .local/reports/, which the brief names and you write yourself. $file_path is under .local/ and is not that file. STOP and return an ESCALATION report to the orchestrator instead."
    ;;
esac

if [ -z "$reason" ]; then
  realm="$("$here/realm.sh" "$file_path")"

  if [ "$role" = "test" ] && [ "$realm" != "test" ]; then
    reason="lego-test-writer is realm-restricted to test-family files (*.spec.*, *.test.*, *_test.*, *_spec.*, test_*, __tests__/). $file_path is outside that family. If this file genuinely must change, STOP and return an ESCALATION report to the orchestrator instead."
  elif [ "$role" = "impl" ] && [ "$realm" = "test" ]; then
    reason="lego-implementer may not modify test-family files. $file_path is in the test family. If a test seems wrong, STOP and return an ESCALATION report to the orchestrator; never adjust tests to fit the implementation."
  fi
fi

if [ -n "$reason" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
exit 0
