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
#     version "0.1.0"; author { name "Cam Williamson",
#     email "camwilliamson@pm.me" }.
#   Outputs 2: .claude-plugin/marketplace.json — one entry appended to the
#     plugins array: name "debugging", source "./plugins/debugging",
#     a non-empty description, version "0.1.0"; file remains valid JSON;
#     existing entries byte-for-byte untouched.
#   Outputs 3: root README.md Plugins table — one row appended as the LAST
#     table row: | [debugging](plugins/debugging/) | ✅ v0.1.0 | <desc> |,
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

check "plugin.json version is '0.1.0'" \
  "$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)" "0.1.0"

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

check "debugging entry version equals plugin.json's version" \
  "$(jq -r '.version // empty' <<<"$DBG_ENTRY" 2>/dev/null)" "$VERSION"
check "debugging entry version is '0.1.0'" \
  "$(jq -r '.version // empty' <<<"$DBG_ENTRY" 2>/dev/null)" "0.1.0"

MKT_DESC=$(jq -r '.description // empty' <<<"$DBG_ENTRY" 2>/dev/null)
check "debugging entry description is non-empty" \
  "$([ -n "$MKT_DESC" ] && echo yes || echo no)" "yes"
check "debugging entry description contains no 'NotImplemented' placeholder" \
  "$(grep -qi 'notimplemented' <<<"$MKT_DESC" && echo placeholder || echo ok)" "ok"

# Invariant: existing entries are byte-for-byte untouched. Pinned against
# the known-stable baseline captured from the repo before B10 registration.
declare -A BASELINE_ENTRIES=(
  [lego]='{"name":"lego","source":"./plugins/lego","description":"Technology-agnostic lego workflow: contract-first planning, scaffolded stubs, realm-restricted test and implementation agent waves.","version":"0.4.0"}'
  [decision-log]='{"name":"decision-log","source":"./plugins/decision-log","description":"Record technical decisions: one-shot DL drafting, section-by-section collaborative authoring, and pending-decision rundowns.","version":"0.1.0"}'
  [tracking]='{"name":"tracking","source":"./plugins/tracking","description":"Tracking-document workflow: .local/TODO.md as session state of record, 13-state lifecycle with Stop-hook enforcement, a built-in task-tools deny, and resume-after-/clear via SessionStart injection.","version":"0.2.0"}'
  [statusline]='{"name":"statusline","source":"./plugins/statusline","description":"Statusline with context usage, session cost, effort, and tracking State. Wired explicitly via /statusline:setup.","version":"0.1.0"}'
  [worktrees]='{"name":"worktrees","source":"./plugins/worktrees","description":"Git worktree workflow on top of the git-helpers utilities (newtree, rmtree, copyenv, cloneBareRepo), including a worktree-per-worker pattern for parallel agents.","version":"0.1.0"}'
  [notifications]='{"name":"notifications","source":"./plugins/notifications","description":"Summoning stack: terminal bell, desktop notification, tmux highlight, and ntfy phone push on the transition into summoning states; silent for parked sessions.","version":"0.1.0"}'
  [landing]='{"name":"landing","source":"./plugins/landing","description":"The landing seam: /landing:land lands finished work per the repo'"'"'s committed policy in .claude/clam-profile.md (github-pr or local-merge); /landing:init detects and records the policy; SessionStart injection keeps every session aware of it.","version":"0.1.0"}'
)
for name in lego decision-log tracking statusline worktrees notifications landing; do
  actual=$(jq -c --arg n "$name" '.plugins[]? | select(.name==$n)' "$MARKETPLACE" 2>/dev/null)
  check "marketplace.json '$name' entry is byte-for-byte untouched" \
    "$actual" "${BASELINE_ENTRIES[$name]}"
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
check "debugging row shows version v0.1.0" \
  "$(grep -qF 'v0.1.0' <<<"$LAST_ROW" && echo yes || echo no)" "yes"

ROW_DESC="$(awk -F'|' '{print $4}' <<<"$LAST_ROW" | sed -E 's/^ +| +$//g')"
check "debugging row has a non-empty description cell" \
  "$([ -n "$ROW_DESC" ] && echo yes || echo no)" "yes"
check "debugging row description contains no 'NotImplemented' placeholder" \
  "$(grep -qi 'notimplemented' <<<"$ROW_DESC" && echo placeholder || echo ok)" "ok"

# Invariant: no other row is modified — spot-check every pre-existing row
# (both already-✅ rows and still-planned rows) against its exact,
# pre-registration text.
mapfile -t EXPECTED_ROWS <<'EOF'
| Plugin | Status | What it does |
|--------|--------|--------------|
| [lego](plugins/lego/) | ✅ v0.4.0 | Contract-first planning, scaffolded stubs, realm-restricted test and implementation agent waves. Ported from clam-v2. |
| pr-workflow | planned | PR lifecycle: create, review, address feedback, author checklist, pre-PR verify, doc-sync gate, retrospective, reviewer agent, issue-tracker seam. |
| session-modes | planned | Session workflow modes (`/start`, orient, sitrep, make-progress, …) plus the session-lifecycle hooks and the SessionStart workflow-rules injection that replaces the old `clam` alias. |
| [decision-log](plugins/decision-log/) | ✅ v0.1.0 | Decision Logs: `/decision-log:create`, `/decision-log:interactive`, `/decision-log:rundown`. Ported from clam-code. |
| [tracking](plugins/tracking/) | ✅ v0.1.0 | Tracking documents: `.local/TODO.md` as session state of record, 13-state lifecycle with Stop-hook enforcement, resume after `/clear` via SessionStart injection. Powers agent-dash and the statusline State segment. |
| [statusline](plugins/statusline/) | ✅ v0.1.0 | Statusline: context usage, session/day/week cost, effort, tracking State. One explicit global write via `/statusline:setup`. |
| [landing](plugins/landing/) | ✅ v0.1.0 | The landing seam: `/landing:land` lands finished work per the repo's committed policy in `.claude/clam-profile.md` (github-pr or local-merge); `/landing:init` detects and records it. |
| team-review | planned | Multi-agent review and exploration: team code review, council, independent review, subagent orchestration; Explore and browser agents. |
| [worktrees](plugins/worktrees/) | ✅ v0.1.0 | Git worktree workflow on top of git-helpers (`newtree`, `rmtree`, `copyenv`, `cloneBareRepo`), plus the worktree-per-worker pattern for parallel agents. |
| guards | planned | Safety hooks: git guard, cron guard, permission audit, notifications. |
| agent-dash | planned | Hooks integrating sessions with [clam-agent-dashboard](https://github.com/cjdubb/clam-agent-dashboard). |
EOF

for row in "${EXPECTED_ROWS[@]}"; do
  label="${row:0:60}"
  check "pre-existing row unchanged: $label..." \
    "$(grep -qxF "$row" "$README" && echo yes || echo no)" "yes"
done

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
