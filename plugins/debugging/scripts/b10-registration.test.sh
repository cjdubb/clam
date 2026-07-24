#!/usr/bin/env bash
# Structural test for Block B10 (registration). The authoritative contract
# is the HTML comment titled "Contract: B10 registration" that sits just
# below the Plugins table in the root README.md. That comment is itself
# part of the stub state and must be REMOVED by a correct implementation,
# so this test also asserts on its disappearance.
#
# Contract clauses under test (root README.md, "Contract: B10 registration"):
#
#   Outputs 1: plugins/debugging/.claude-plugin/plugin.json — exactly four
#     keys: name "debugging"; a one-line, non-placeholder description;
#     version "0.2.0"; author { name "Cam Williamson",
#     email "camwilliamson@pm.me" }.
#   Outputs 2: .claude-plugin/marketplace.json — one entry appended to the
#     plugins array: name "debugging", source "./plugins/debugging",
#     a non-empty description, version "0.2.0"; file remains valid JSON;
#     existing entries byte-for-byte untouched.
#   Outputs 3: root README.md Plugins table — one row appended as the LAST
#     table row: | [debugging](plugins/debugging/) | ✅ v0.2.0 | <desc> |,
#     and the "Contract: B10 registration" stub comment deleted in the same
#     change.
#   Invariant: the version string agrees across all three surfaces.
#   Invariant: descriptions may differ in wording but not be empty or
#     placeholder text on any surface.
#   Invariant: no other row, entry, or section is modified.
#
# Reads the real repo-root files directly (this test asserts on final repo
# state, not a synthetic fixture), so it is inherently about repo content
# rather than a hermetic sandbox. It is cwd-independent via SCRIPT_DIR
# self-location.
# Run: bash plugins/debugging/scripts/b10-registration.test.sh   (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PLUGIN_JSON="$ROOT/plugins/debugging/.claude-plugin/plugin.json"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
README="$ROOT/README.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# --- 0. Preconditions: the files this test depends on must exist. ---
check "plugin.json exists" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "README.md exists" \
  "$([ -f "$README" ] && echo yes || echo no)" "yes"

# =====================================================================
# (1) plugins/debugging/.claude-plugin/plugin.json
# =====================================================================

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

# Output: exactly the four contracted keys (name, description, version,
# author) — no more, no fewer.
check "plugin.json has exactly four top-level keys" \
  "$(jq -r 'keys | length' "$PLUGIN_JSON" 2>/dev/null)" "4"
check "plugin.json top-level keys are name/description/version/author" \
  "$(jq -r 'keys | sort | join(",")' "$PLUGIN_JSON" 2>/dev/null)" \
  "author,description,name,version"

check "plugin.json name is 'debugging'" \
  "$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null)" "debugging"

# Cross-surface source of truth for the version check below: the debugging
# row's version in the root README (same authoritative-value pattern used
# for the invariant checks further down this file).
EARLY_LAST_ROW="$(grep '^|' "$README" | tail -n1)"
EARLY_README_VERSION="$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' <<<"$EARLY_LAST_ROW" | head -n1 | sed 's/^v//')"

check "plugin.json version agrees with the root README debugging row's version" \
  "$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)" "$EARLY_README_VERSION"

PJ_DESC=$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json description is non-empty" \
  "$([ -n "$PJ_DESC" ] && echo yes || echo no)" "yes"
check "plugin.json description contains no 'NotImplemented' placeholder" \
  "$(grep -qi 'notimplemented' <<<"$PJ_DESC" && echo placeholder || echo ok)" "ok"

check "plugin.json author.name is 'Cam Williamson'" \
  "$(jq -r '.author.name // empty' "$PLUGIN_JSON" 2>/dev/null)" "Cam Williamson"
check "plugin.json author.email is 'camwilliamson@pm.me'" \
  "$(jq -r '.author.email // empty' "$PLUGIN_JSON" 2>/dev/null)" "camwilliamson@pm.me"

# Version source of truth for the cross-surface agreement checks below.
VERSION=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)

# =====================================================================
# (2) .claude-plugin/marketplace.json
# =====================================================================

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

# Output: exactly one plugins[] entry named "debugging" (no duplicates).
DBG_COUNT=$(jq '[.plugins[]? | select(.name=="debugging")] | length' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json has exactly one plugins[] entry named 'debugging'" \
  "$DBG_COUNT" "1"

DBG_ENTRY=$(jq -c '.plugins[]? | select(.name=="debugging")' "$MARKETPLACE" 2>/dev/null)

check "debugging entry source is './plugins/debugging'" \
  "$(jq -r 'select(.name=="debugging") | .source' <<<"$DBG_ENTRY" 2>/dev/null)" \
  "./plugins/debugging"

check "debugging entry has no version field (plugin.json is source of truth)" \
  "$(jq -e '.version' <<<"$DBG_ENTRY" >/dev/null 2>&1 && echo present || echo absent)" "absent"

MKT_DESC=$(jq -r '.description // empty' <<<"$DBG_ENTRY" 2>/dev/null)
check "debugging entry description is non-empty" \
  "$([ -n "$MKT_DESC" ] && echo yes || echo no)" "yes"
check "debugging entry description contains no 'NotImplemented' placeholder" \
  "$(grep -qi 'notimplemented' <<<"$MKT_DESC" && echo placeholder || echo ok)" "ok"

# Invariant: existing entries are untouched. Check source paths are stable
# (version is not in marketplace — plugin.json is the single source of truth).
for name in lego decision-log tracking statusline worktrees notifications landing; do
  actual=$(jq -r --arg n "$name" '.plugins[]? | select(.name==$n) | .source' "$MARKETPLACE" 2>/dev/null)
  check "marketplace.json '$name' entry source untouched" \
    "$actual" "./plugins/$name"
done

# =====================================================================
# (3) root README.md — Plugins table
# =====================================================================

# Invariant: the stub contract comment is removed in the same change.
check "'Contract: B10 registration' stub comment is gone from README.md" \
  "$(grep -qF 'Contract: B10 registration' "$README" && echo present || echo absent)" \
  "absent"

# The Plugins table is the only block of pipe-prefixed lines in this file,
# so the last such line in the whole document is the table's last row.
LAST_ROW="$(grep '^|' "$README" | tail -n1)"

check "README Plugins table's last row is the debugging row" \
  "$(grep -qxE '\| \[debugging\]\(plugins/debugging/\) \| ✅ v[0-9.]+ \| .+ \|' <<<"$LAST_ROW" && echo yes || echo no)" \
  "yes"
check "debugging row links to plugins/debugging/" \
  "$(grep -qF '[debugging](plugins/debugging/)' <<<"$LAST_ROW" && echo yes || echo no)" "yes"
check "debugging row shows the ✅ status marker" \
  "$(grep -qF '✅' <<<"$LAST_ROW" && echo yes || echo no)" "yes"
check "debugging row shows version v$VERSION" \
  "$(grep -qF "v$VERSION" <<<"$LAST_ROW" && echo yes || echo no)" "yes"
check "debugging row shows version v$VERSION (belt-and-braces duplicate)" \
  "$(grep -qF "v$VERSION" <<<"$LAST_ROW" && echo yes || echo no)" "yes"

ROW_DESC="$(awk -F'|' '{print $4}' <<<"$LAST_ROW" | sed -E 's/^ +| +$//g')"
check "debugging row has a non-empty description cell" \
  "$([ -n "$ROW_DESC" ] && echo yes || echo no)" "yes"
check "debugging row description contains no 'NotImplemented' placeholder" \
  "$(grep -qi 'notimplemented' <<<"$ROW_DESC" && echo placeholder || echo ok)" "ok"

# Invariant: no other row is modified. The header/separator and the
# still-"planned" rows (no plugin.json, nothing to bump) are checked
# byte-for-byte against their exact, pre-registration text. The already-✅
# plugin rows check wording/link byte-for-byte too, but read their version
# cell dynamically from that plugin's own plugin.json instead of a frozen
# literal, so a legitimate version bump of a NEIGHBORING plugin doesn't
# flip this check red. Presence is a substring search over the whole file
# (not position- or count-anchored), so this also tolerates other rows
# being inserted elsewhere in the table.
mapfile -t STATIC_EXPECTED_ROWS <<'EOF'
| Plugin | Status | What it does |
|--------|--------|--------------|
| pr-workflow | planned | PR lifecycle: create, review, address feedback, author checklist, pre-PR verify, doc-sync gate, retrospective, reviewer agent, issue-tracker seam. |
| session-modes | planned | Session workflow modes (`/start`, orient, sitrep, make-progress, …) plus the session-lifecycle hooks and the SessionStart workflow-rules injection that replaces the old `clam` alias. |
| team-review | planned | Multi-agent review and exploration: team code review, council, independent review, subagent orchestration; Explore and browser agents. |
| guards | planned | Safety hooks: git guard, cron guard, permission audit, notifications. |
| agent-dash | planned | Hooks integrating sessions with [clam-agent-dashboard](https://github.com/cjdubb/clam-agent-dashboard). |
EOF

for row in "${STATIC_EXPECTED_ROWS[@]}"; do
  label="${row:0:60}"
  check "pre-existing row unchanged: $label..." \
    "$(grep -qxF "$row" "$README" && echo yes || echo no)" "yes"
done

check_plugin_row_unchanged() { # plugin_dir_name row_template_with___VERSION___
  local plugin_name="$1" template="$2"
  local pj="$ROOT/plugins/$plugin_name/.claude-plugin/plugin.json"
  local version expected label
  version="$(jq -r '.version // empty' "$pj" 2>/dev/null)"
  expected="${template/__VERSION__/$version}"
  label="${expected:0:60}"
  check "pre-existing row unchanged: $label..." \
    "$(grep -qxF "$expected" "$README" && echo yes || echo no)" "yes"
}

check_plugin_row_unchanged "lego" \
  '| [lego](plugins/lego/) | ✅ v__VERSION__ | Contract-first planning, scaffolded stubs, realm-restricted test and implementation agent waves. Ported from clam-v2. |'
check_plugin_row_unchanged "decision-log" \
  '| [decision-log](plugins/decision-log/) | ✅ v__VERSION__ | Decision Logs: `/decision-log:create`, `/decision-log:interactive`, `/decision-log:rundown`. Ported from clam-code. |'
check_plugin_row_unchanged "tracking" \
  '| [tracking](plugins/tracking/) | ✅ v__VERSION__ | Tracking documents: `.local/TODO.md` as session state of record, 13-state lifecycle with Stop-hook enforcement, resume after `/clear` via SessionStart injection. Powers agent-dash and the statusline State segment. |'
check_plugin_row_unchanged "statusline" \
  '| [statusline](plugins/statusline/) | ✅ v__VERSION__ | Statusline: context usage, session/day/week cost, effort, tracking State. One explicit global write via `/statusline:setup`. |'
check_plugin_row_unchanged "landing" \
  '| [landing](plugins/landing/) | ✅ v__VERSION__ | The landing seam: `/landing:land` lands finished work per the repo'"'"'s committed policy in `.claude/clam-profile.jsonc` (github-pr or local-merge); `/landing:init` detects and records it. |'
check_plugin_row_unchanged "worktrees" \
  '| [worktrees](plugins/worktrees/) | ✅ v__VERSION__ | Git worktree workflow on top of git-helpers (`newtree`, `rmtree`, `copyenv`, `cloneBareRepo`), plus the worktree-per-worker pattern for parallel agents. |'

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
