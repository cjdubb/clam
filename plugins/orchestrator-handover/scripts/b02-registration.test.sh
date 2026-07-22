#!/bin/bash
# Structural test for Block B02 (registration). B02 has no stub file by
# design: it edits three shared root-level files rather than any file that
# could carry an HTML-comment docblock. Its authoritative contract is the
# orchestrator's dispatch-brief checklist for B02, cross-checked against the
# unit.md block-map summary ("registers the orchestrator-handover plugin in
# the marketplace manifest, adds a row to the README plugin table, and
# updates MIGRATION.md to track orchestrator-handover as its own ported
# plugin (moved out of the session-modes bucket)") and this repo's
# established registration convention — see
# plugins/worktrees/scripts/b04-registration.test.sh for the sibling
# pattern this test mirrors.
#
#   (1) .claude-plugin/marketplace.json — an orchestrator-handover entry:
#       source "./plugins/orchestrator-handover", no version field
#       (plugin.json is the single source of truth), non-placeholder
#       description; other plugin entries (lego, decision-log, tracking,
#       statusline, worktrees, notifications, landing) untouched.
#   (2) README.md — a new orchestrator-handover Plugins-table row showing
#       "✅ v<version>" (version from plugin.json) with a link to
#       plugins/orchestrator-handover/, a non-empty description, and no
#       "planned" marker; other rows untouched; the session-modes row
#       (which never named the skill explicitly) still doesn't name it.
#   (3) MIGRATION.md — a new "## orchestrator-handover" section marked
#       ported/done (not planned), noting the move out of session-modes;
#       the "## session-modes" section's skill list no longer carries
#       orchestrator-handover as a bare planned skill (dropped, or kept
#       with an explicit "moved" note, matching the repo's convention for
#       skills reassigned out of session-modes elsewhere in that section).
#
# Reads the real repo-root files directly (this block IS those files' final
# state, not a runtime script with synthetic fixtures), so the test is
# inherently about repo content rather than a hermetic sandbox. It is
# cwd-independent via SCRIPT_DIR self-location.
# Run: bash plugins/orchestrator-handover/scripts/b02-registration.test.sh   (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
README="$ROOT/README.md"
MIGRATION="$ROOT/MIGRATION.md"
PLUGIN_JSON="$ROOT/plugins/orchestrator-handover/.claude-plugin/plugin.json"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# --- 0. Preconditions: the files/paths this test depends on must exist. ---
check "plugin.json exists (B01 dependency)" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "README.md exists" \
  "$([ -f "$README" ] && echo yes || echo no)" "yes"
check "MIGRATION.md exists" \
  "$([ -f "$MIGRATION" ] && echo yes || echo no)" "yes"

# The version source of truth: read dynamically from plugin.json, never
# hardcoded, so this test tracks whatever B01 landed (contract Inputs
# clause: "version matching plugin.json").
VERSION=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json has a non-empty version" \
  "$([ -n "$VERSION" ] && echo yes || echo no)" "yes"

# =====================================================================
# (1) marketplace.json
# =====================================================================

# Invariant: marketplace.json stays valid JSON.
check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

# Output: a plugins[] entry with name "orchestrator-handover".
OH_ENTRY=$(jq -c '.plugins[]? | select(.name=="orchestrator-handover")' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json has a plugins[] entry named 'orchestrator-handover'" \
  "$([ -n "$OH_ENTRY" ] && echo yes || echo no)" "yes"

# Output: source is "./plugins/orchestrator-handover".
check "orchestrator-handover entry source is './plugins/orchestrator-handover'" \
  "$(jq -r 'select(.name=="orchestrator-handover") | .source' <<<"$OH_ENTRY" 2>/dev/null)" \
  "./plugins/orchestrator-handover"

# Output: no version field in the marketplace entry (plugin.json is the
# single source of truth for version — marketplace.json must not duplicate it).
check "orchestrator-handover entry has no version field (plugin.json is single source of truth)" \
  "$(jq -e '.version' <<<"$OH_ENTRY" >/dev/null 2>&1 && echo present || echo absent)" "absent"

# Output: a non-placeholder, non-empty description.
OH_DESC=$(jq -r '.description // empty' <<<"$OH_ENTRY" 2>/dev/null)
check "orchestrator-handover entry description is non-empty" \
  "$([ -n "$OH_DESC" ] && echo yes || echo no)" "yes"
check "orchestrator-handover entry description is not a TODO placeholder" \
  "$(grep -qi 'todo' <<<"$OH_DESC" && echo placeholder || echo ok)" "ok"
check "orchestrator-handover entry description is not a NotImplemented placeholder" \
  "$(grep -qi 'notimplemented' <<<"$OH_DESC" && echo placeholder || echo ok)" "ok"

# Invariant: no other plugin's marketplace entries were disturbed. Check
# source paths are stable (version is not in marketplace — plugin.json is
# the single source of truth).
check "lego entry untouched (source)" \
  "$(jq -r '.plugins[]? | select(.name=="lego") | .source' "$MARKETPLACE")" \
  './plugins/lego'
check "decision-log entry untouched (source)" \
  "$(jq -r '.plugins[]? | select(.name=="decision-log") | .source' "$MARKETPLACE")" \
  './plugins/decision-log'
check "tracking entry untouched (source)" \
  "$(jq -r '.plugins[]? | select(.name=="tracking") | .source' "$MARKETPLACE")" \
  './plugins/tracking'
check "statusline entry untouched (source)" \
  "$(jq -r '.plugins[]? | select(.name=="statusline") | .source' "$MARKETPLACE")" \
  './plugins/statusline'
check "worktrees entry untouched (source)" \
  "$(jq -r '.plugins[]? | select(.name=="worktrees") | .source' "$MARKETPLACE")" \
  './plugins/worktrees'
check "notifications entry untouched (source)" \
  "$(jq -r '.plugins[]? | select(.name=="notifications") | .source' "$MARKETPLACE")" \
  './plugins/notifications'
check "landing entry untouched (source)" \
  "$(jq -r '.plugins[]? | select(.name=="landing") | .source' "$MARKETPLACE")" \
  './plugins/landing'

# =====================================================================
# (2) README.md — Plugins table
# =====================================================================

# Extract the single Plugins-table row for the orchestrator-handover plugin
# (matches either a bare-text row or a linked row; both start the row cell
# with "orchestrator-handover").
oh_row() {
  grep -E '^\| \[?orchestrator-handover\]?' "$README" | head -n1
}

OH_ROW="$(oh_row)"
check "README has a Plugins-table row for orchestrator-handover" \
  "$([ -n "$OH_ROW" ] && echo yes || echo no)" "yes"

# Output: row links to plugins/orchestrator-handover/.
check "orchestrator-handover row links to plugins/orchestrator-handover/" \
  "$(grep -qF '[orchestrator-handover](plugins/orchestrator-handover/)' <<<"$OH_ROW" && echo yes || echo no)" "yes"

# Output: row shows the ✅ status marker and the plugin.json version, and no
# longer says "planned".
check "orchestrator-handover row shows the ✅ status marker" \
  "$(grep -qF '✅' <<<"$OH_ROW" && echo yes || echo no)" "yes"
check "orchestrator-handover row shows the version from plugin.json" \
  "$(grep -qF "v$VERSION" <<<"$OH_ROW" && echo yes || echo no)" "yes"
check "orchestrator-handover row no longer says 'planned'" \
  "$(grep -qi 'planned' <<<"$OH_ROW" && echo present || echo absent)" "absent"

# Output: row carries a non-empty description cell (3 pipe-delimited
# columns: link/status cell | status | description).
OH_ROW_DESC="$(awk -F'|' '{print $4}' <<<"$OH_ROW" | sed -E 's/^ +| +$//g')"
check "orchestrator-handover row has a non-empty description cell" \
  "$([ -n "$OH_ROW_DESC" ] && echo yes || echo no)" "yes"

# Invariant: other rows untouched — the already-✅ rows keep their exact
# status cells, and the still-planned rows keep saying "planned".
check "lego row still ✅ v0.4.0" \
  "$(grep -E '^\| \[lego\]' "$README" | grep -qF '✅ v0.4.0' && echo yes || echo no)" "yes"
check "decision-log row still ✅ v0.1.0" \
  "$(grep -E '^\| \[decision-log\]' "$README" | grep -qF '✅ v0.1.0' && echo yes || echo no)" "yes"
check "tracking row still ✅ v0.1.0" \
  "$(grep -E '^\| \[tracking\]' "$README" | grep -qF '✅ v0.1.0' && echo yes || echo no)" "yes"
check "statusline row still ✅ v0.1.0" \
  "$(grep -E '^\| \[statusline\]' "$README" | grep -qF '✅ v0.1.0' && echo yes || echo no)" "yes"
check "worktrees row still ✅ v0.1.0" \
  "$(grep -E '^\| \[worktrees\]' "$README" | grep -qF '✅ v0.1.0' && echo yes || echo no)" "yes"
check "pr-workflow row still 'planned' (unrelated row untouched)" \
  "$(grep -E '^\| pr-workflow' "$README" | grep -qi 'planned' && echo yes || echo no)" "yes"
check "team-review row still 'planned' (unrelated row untouched)" \
  "$(grep -E '^\| team-review' "$README" | grep -qi 'planned' && echo yes || echo no)" "yes"

# Invariant: the session-modes row never named orchestrator-handover
# explicitly (it's a generic "(`/start`, orient, sitrep, ...)" summary), so
# B02 has nothing to remove there — assert it still doesn't name it, i.e.
# B02 did not introduce a stray/duplicate mention in that row.
check "session-modes row does not name orchestrator-handover explicitly" \
  "$(grep -E '^\| session-modes' "$README" | grep -qF 'orchestrator-handover' && echo present || echo absent)" \
  "absent"

# =====================================================================
# (3) MIGRATION.md
# =====================================================================

# Extract the orchestrator-handover section: from its "## orchestrator-
# handover" heading up to (not including) the next "## " heading.
oh_section() {
  awk '
    /^## orchestrator-handover/ { flag=1 }
    flag && /^## / && !/^## orchestrator-handover/ { exit }
    flag { print }
  ' "$MIGRATION"
}

OH_SECTION="$(oh_section)"
check "MIGRATION.md has an orchestrator-handover section" \
  "$([ -n "$OH_SECTION" ] && echo yes || echo no)" "yes"

# Output: heading indicates ported/done status (not planned).
OH_HEADING="$(grep -E '^## orchestrator-handover' "$MIGRATION" | head -n1)"
check "orchestrator-handover section heading no longer says 'planned'" \
  "$(grep -qi 'planned' <<<"$OH_HEADING" && echo present || echo absent)" "absent"
check "orchestrator-handover section heading indicates ported/done status" \
  "$(grep -qiE 'ported|done' <<<"$OH_HEADING" && echo yes || echo no)" "yes"

# Output: notes the plugin was moved out of the session-modes bucket into
# its own plugin.
check "orchestrator-handover section mentions session-modes (the bucket it moved out of)" \
  "$(grep -qi 'session-modes' <<<"$OH_SECTION" && echo yes || echo no)" "yes"
check "orchestrator-handover section notes it was moved (not simply invented fresh)" \
  "$(grep -qi 'moved' <<<"$OH_SECTION" && echo yes || echo no)" "yes"

# --- session-modes section: no longer carries orchestrator-handover as a
# bare planned skill. ---

sm_section() {
  awk '
    /^## session-modes/ { flag=1 }
    flag && /^## / && !/^## session-modes/ { exit }
    flag { print }
  ' "$MIGRATION"
}

SM_SECTION="$(sm_section)"
check "MIGRATION.md still has a session-modes section" \
  "$([ -n "$SM_SECTION" ] && echo yes || echo no)" "yes"

# Contract: "the session-modes section no longer lists orchestrator-handover
# as one of its planned skills (or notes the move)". Matches the repo's own
# convention for skills reassigned out of session-modes elsewhere in this
# same section (e.g. "`keep-working.sh` and `awaiting-user.sh` moved to
# **tracking**") — either the name is dropped entirely, or it is kept only
# alongside an explicit "moved" note nearby. Scoped to a small context
# window (2 lines either side of any orchestrator-handover mention) rather
# than the whole section, since the section already contains unrelated
# "moved to **tracking**"/"moved to **notifications**" notes for other
# skills — a whole-section check would pass trivially without B02 ever
# touching the orchestrator-handover line.
OH_CONTEXT="$(grep -A2 -B2 -F 'orchestrator-handover' <<<"$SM_SECTION")"
if [[ -n "$OH_CONTEXT" ]]; then
  SM_RESULT="$(grep -qi 'moved' <<<"$OH_CONTEXT" && echo yes || echo no)"
else
  SM_RESULT="yes"
fi
check "session-modes section drops orchestrator-handover from its skill list, or notes the move" \
  "$SM_RESULT" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
