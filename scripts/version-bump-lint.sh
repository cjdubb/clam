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
#       WARN  <name> -> plugin.json description changed but marketplace.json did not (or vice versa)
#   - Plugins with no changes in the range produce no line.
#   - No plugin changes at all: "no plugin changes to check" and exit 0
#     (vacuous pass).
#   - Blank line, then "ALL PASS" (exit 0) or "FAILURES — fix before merging"
#     plus a remediation hint naming each offending plugins/<name>/
#     .claude-plugin/plugin.json (exit 1). Description WARNs do not fail
#     the run.
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
#   - Only plugins/<name>/** participates in the version check; changes
#     elsewhere (scripts/, README.md) are ignored. The description
#     cross-check also reads .claude-plugin/marketplace.json at both
#     endpoints to detect one-sided description changes.
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

usage() {
  echo "usage: version-bump-lint.sh [--base <ref>]" >&2
}

BASE=""
BASE_GIVEN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      BASE="$2"
      BASE_GIVEN=1
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>&1)" || { echo "$ROOT" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || {
  echo "version-bump-lint: jq is required but was not found in PATH" >&2
  exit 2
}

if [ "$BASE_GIVEN" -eq 1 ]; then
  BASE_SHA="$(git -C "$ROOT" rev-parse --verify --quiet "${BASE}^{commit}" 2>/dev/null)"
  if [ -z "$BASE_SHA" ]; then
    echo "version-bump-lint: --base '$BASE' does not resolve to a commit" >&2
    exit 2
  fi
else
  BASE_SHA="$(git -C "$ROOT" rev-parse --verify --quiet "origin/master^{commit}" 2>/dev/null)"
  if [ -z "$BASE_SHA" ]; then
    BASE_SHA="$(git -C "$ROOT" rev-parse --verify --quiet "master^{commit}" 2>/dev/null)"
  fi
  if [ -z "$BASE_SHA" ]; then
    echo "version-bump-lint: neither origin/master nor master resolves to a commit; pass --base <ref>" >&2
    exit 2
  fi
fi

HEAD_SHA="$(git -C "$ROOT" rev-parse --verify --quiet HEAD 2>/dev/null)"
if [ -z "$HEAD_SHA" ]; then
  echo "version-bump-lint: HEAD does not resolve to a commit" >&2
  exit 2
fi

MB="$(git -C "$ROOT" merge-base "$BASE_SHA" "$HEAD_SHA" 2>/dev/null)"
if [ -z "$MB" ]; then
  echo "version-bump-lint: no common ancestor between '$BASE_SHA' and HEAD" >&2
  exit 2
fi

FAILED=0
VERDICTS=0
FAIL_PATHS=()

declare -A SEEN=()
PLUGIN_ORDER=()

add_plugin() { # path -> records the owning plugin name, once, in order seen
  local path="$1" rest name
  case "$path" in
    plugins/*/*) ;;
    *) return ;;
  esac
  rest="${path#plugins/}"
  name="${rest%%/*}"
  [ -n "$name" ] || return
  if [ -z "${SEEN[$name]:-}" ]; then
    SEEN[$name]=1
    PLUGIN_ORDER+=("$name")
  fi
}

while IFS=$'\t' read -r status p1 p2; do
  [ -n "$status" ] || continue
  case "$status" in
    R*)
      add_plugin "$p1"
      add_plugin "$p2"
      ;;
    *)
      add_plugin "$p1"
      ;;
  esac
done < <(git -C "$ROOT" diff --name-status -M "$MB" "$HEAD_SHA" -- plugins)

for name in "${PLUGIN_ORDER[@]}"; do
  if [ -z "$(git -C "$ROOT" ls-tree -r --name-only "$HEAD_SHA" -- "plugins/$name" 2>/dev/null)" ]; then
    # Plugin deleted entirely at HEAD: skipped, no verdict line.
    continue
  fi

  head_content="$(git -C "$ROOT" show "$HEAD_SHA:plugins/$name/.claude-plugin/plugin.json" 2>/dev/null)"
  head_version=""
  if [ -n "$head_content" ]; then
    head_version="$(printf '%s' "$head_content" | jq -r '.version // empty' 2>/dev/null)"
    [ $? -eq 0 ] || head_version=""
  fi

  VERDICTS=$((VERDICTS + 1))

  if [ -z "$head_version" ]; then
    echo "FAIL  $name -> plugin.json missing or unreadable at HEAD; a changed plugin must carry a readable version"
    FAIL_PATHS+=("plugins/$name/.claude-plugin/plugin.json")
    FAILED=1
    continue
  fi

  base_content="$(git -C "$ROOT" show "$MB:plugins/$name/.claude-plugin/plugin.json" 2>/dev/null)"
  base_version=""
  if [ -n "$base_content" ]; then
    base_version="$(printf '%s' "$base_content" | jq -r '.version // empty' 2>/dev/null)"
    [ $? -eq 0 ] || base_version=""
  fi

  if [ "$base_version" = "$head_version" ]; then
    echo "FAIL  $name -> files changed but version unchanged ($head_version)"
    FAIL_PATHS+=("plugins/$name/.claude-plugin/plugin.json")
    FAILED=1
  elif [ -z "$base_version" ]; then
    echo "PASS  $name (version (new) -> $head_version)"
  else
    echo "PASS  $name (version $base_version -> $head_version)"
  fi
done

# ---------------------------------------------------------------------------
# Description cross-check: when a plugin's plugin.json description changed,
# marketplace.json's entry for that plugin should also change (and vice
# versa). A WARN, not a FAIL — descriptions are deliberately different
# across surfaces, but forgetting to update one is the common mistake.
# ---------------------------------------------------------------------------
MKT_FILE=".claude-plugin/marketplace.json"
head_mkt="$(git -C "$ROOT" show "$HEAD_SHA:$MKT_FILE" 2>/dev/null || true)"
base_mkt="$(git -C "$ROOT" show "$MB:$MKT_FILE" 2>/dev/null || true)"
DESC_WARN_COUNT=0

for name in "${PLUGIN_ORDER[@]}"; do
  head_pj_desc=""
  base_pj_desc=""
  head_mkt_desc=""
  base_mkt_desc=""

  hc="$(git -C "$ROOT" show "$HEAD_SHA:plugins/$name/.claude-plugin/plugin.json" 2>/dev/null || true)"
  bc="$(git -C "$ROOT" show "$MB:plugins/$name/.claude-plugin/plugin.json" 2>/dev/null || true)"
  [ -n "$hc" ] && head_pj_desc="$(printf '%s' "$hc" | jq -r '.description // empty' 2>/dev/null)"
  [ -n "$bc" ] && base_pj_desc="$(printf '%s' "$bc" | jq -r '.description // empty' 2>/dev/null)"

  [ -n "$head_mkt" ] && head_mkt_desc="$(printf '%s' "$head_mkt" | jq -r --arg n "$name" '.plugins[] | select(.name==$n) | .description // empty' 2>/dev/null)"
  [ -n "$base_mkt" ] && base_mkt_desc="$(printf '%s' "$base_mkt" | jq -r --arg n "$name" '.plugins[] | select(.name==$n) | .description // empty' 2>/dev/null)"

  pj_changed=0; mkt_changed=0
  [ "$head_pj_desc" != "$base_pj_desc" ] && pj_changed=1
  [ "$head_mkt_desc" != "$base_mkt_desc" ] && mkt_changed=1

  if [ "$pj_changed" -eq 1 ] && [ "$mkt_changed" -eq 0 ] && [ -n "$head_mkt_desc" ]; then
    echo "WARN  $name -> plugin.json description changed but marketplace.json did not"
    DESC_WARN_COUNT=$((DESC_WARN_COUNT + 1))
  fi
  if [ "$mkt_changed" -eq 1 ] && [ "$pj_changed" -eq 0 ] && [ -n "$head_pj_desc" ]; then
    echo "WARN  $name -> marketplace.json description changed but plugin.json did not"
    DESC_WARN_COUNT=$((DESC_WARN_COUNT + 1))
  fi
done

if [ "$VERDICTS" -eq 0 ]; then
  echo "no plugin changes to check"
  exit 0
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES — fix before merging"
  echo "  bump the version in: ${FAIL_PATHS[*]}"
fi
if [ "$DESC_WARN_COUNT" -gt 0 ]; then
  echo "  ($DESC_WARN_COUNT description-sync warning(s) above — update marketplace.json or plugin.json to match)"
fi
exit "$FAILED"
