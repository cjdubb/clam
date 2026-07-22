#!/bin/bash
# Structural test for Block B04 (registration). B04 has no stub file by
# design: the authoritative contract lives in the fenced block under
# "## B04 contract (authoritative — no stub file, see Changelog)" in
# .local/plans/001-worktrees-plugin.md. This test asserts directly on the
# three shared repo files the contract names as B04's outputs:
#
#   (1) .claude-plugin/marketplace.json — a worktrees entry: source
#       "./plugins/worktrees", version identical to plugin.json (read
#       dynamically, never hardcoded), non-placeholder description; other
#       plugin entries (lego, decision-log, tracking, statusline) untouched.
#   (2) README.md — the worktrees Plugins-table row flipped from "planned"
#       to "✅ v<version>" with a link to plugins/worktrees/; other rows
#       (both the already-✅ ones and the still-planned ones) untouched.
#   (3) MIGRATION.md — the "## worktrees — planned" section updated off
#       "planned", noting the skills were fresh-written against current
#       git-helpers (not ported), and that general/todo-worktree.sh was
#       deliberately NOT ported (depends on clam-code session tooling;
#       revisit alongside the tracking plugin).
#
# Reads the real repo-root files directly (this block IS those files' final
# state, not a runtime script with synthetic fixtures), so the test is
# inherently about repo content rather than a hermetic sandbox. It is
# cwd-independent via SCRIPT_DIR self-location.
# Run: bash plugins/worktrees/scripts/b04-registration.test.sh   (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
README="$ROOT/README.md"
MIGRATION="$ROOT/MIGRATION.md"
PLUGIN_JSON="$ROOT/plugins/worktrees/.claude-plugin/plugin.json"

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
# hardcoded, so this test tracks whatever B01 lands rather than pinning
# "0.1.0" twice (contract Inputs clause).
VERSION=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)

# =====================================================================
# (1) marketplace.json
# =====================================================================

# Invariant: marketplace.json stays valid JSON.
check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

# Output: a plugins[] entry with name "worktrees".
WT_ENTRY=$(jq -c '.plugins[]? | select(.name=="worktrees")' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json has a plugins[] entry named 'worktrees'" \
  "$([ -n "$WT_ENTRY" ] && echo yes || echo no)" "yes"

# Output: source is "./plugins/worktrees".
check "worktrees entry source is './plugins/worktrees'" \
  "$(jq -r 'select(.name=="worktrees") | .source' <<<"$WT_ENTRY" 2>/dev/null)" \
  "./plugins/worktrees"

# Output: version identical to plugin.json's version (dynamic comparison,
# not a hardcoded literal — this is the "version source of truth" clause).
check "worktrees entry version matches plugin.json's version" \
  "$(jq -r '.version' <<<"$WT_ENTRY" 2>/dev/null)" "$VERSION"

# Output: a non-placeholder, non-empty one-line description.
WT_DESC=$(jq -r '.description // empty' <<<"$WT_ENTRY" 2>/dev/null)
check "worktrees entry description is non-empty" \
  "$([ -n "$WT_DESC" ] && echo yes || echo no)" "yes"
check "worktrees entry description is not a TODO placeholder" \
  "$(grep -qi 'todo' <<<"$WT_DESC" && echo placeholder || echo ok)" "ok"
check "worktrees entry description is not a NotImplemented placeholder" \
  "$(grep -qi 'notimplemented' <<<"$WT_DESC" && echo placeholder || echo ok)" "ok"

# Invariant: no other plugin's marketplace entries were disturbed. Pinned
# against the known-stable baseline for the four pre-existing entries.
check "lego entry untouched (source/version)" \
  "$(jq -c '.plugins[]? | select(.name=="lego") | {source,version}' "$MARKETPLACE")" \
  '{"source":"./plugins/lego","version":"0.4.0"}'
check "decision-log entry untouched (source/version)" \
  "$(jq -c '.plugins[]? | select(.name=="decision-log") | {source,version}' "$MARKETPLACE")" \
  '{"source":"./plugins/decision-log","version":"0.1.0"}'
check "tracking entry untouched (source/version)" \
  "$(jq -c '.plugins[]? | select(.name=="tracking") | {source,version}' "$MARKETPLACE")" \
  '{"source":"./plugins/tracking","version":"0.3.0"}'
check "statusline entry untouched (source/version)" \
  "$(jq -c '.plugins[]? | select(.name=="statusline") | {source,version}' "$MARKETPLACE")" \
  '{"source":"./plugins/statusline","version":"0.1.0"}'

# =====================================================================
# (2) README.md — Plugins table
# =====================================================================

# Extract the single Plugins-table row for the worktrees plugin (matches
# either the pre-registration bare-text row or the post-registration linked
# row; both start the row cell with "worktrees").
wt_row() {
  grep -E '^\| \[?worktrees\]?' "$README" | head -n1
}

WT_ROW="$(wt_row)"
check "README has a Plugins-table row for worktrees" \
  "$([ -n "$WT_ROW" ] && echo yes || echo no)" "yes"

# Output: row links to plugins/worktrees/.
check "worktrees row links to plugins/worktrees/" \
  "$(grep -qF '[worktrees](plugins/worktrees/)' <<<"$WT_ROW" && echo yes || echo no)" "yes"

# Output: row is flipped to ✅ with the plugin.json version, and no longer
# says "planned".
check "worktrees row shows the ✅ status marker" \
  "$(grep -qF '✅' <<<"$WT_ROW" && echo yes || echo no)" "yes"
check "worktrees row shows the version from plugin.json" \
  "$(grep -qF "v$VERSION" <<<"$WT_ROW" && echo yes || echo no)" "yes"
check "worktrees row no longer says 'planned'" \
  "$(grep -qi 'planned' <<<"$WT_ROW" && echo present || echo absent)" "absent"

# Output: row still carries a non-empty description cell (3 pipe-delimited
# columns: link/status cell | status | description).
WT_ROW_DESC="$(awk -F'|' '{print $4}' <<<"$WT_ROW" | sed -E 's/^ +| +$//g')"
check "worktrees row has a non-empty description cell" \
  "$([ -n "$WT_ROW_DESC" ] && echo yes || echo no)" "yes"

# Invariant: other rows untouched — the already-✅ rows keep their exact
# status cells, and the still-planned rows (other than worktrees) still say
# "planned".
check "lego row still ✅ v0.4.0" \
  "$(grep -E '^\| \[lego\]' "$README" | grep -qF '✅ v0.4.0' && echo yes || echo no)" "yes"
check "decision-log row still ✅ v0.1.0" \
  "$(grep -E '^\| \[decision-log\]' "$README" | grep -qF '✅ v0.1.0' && echo yes || echo no)" "yes"
check "tracking row still ✅ v0.1.0" \
  "$(grep -E '^\| \[tracking\]' "$README" | grep -qF '✅ v0.1.0' && echo yes || echo no)" "yes"
check "statusline row still ✅ v0.1.0" \
  "$(grep -E '^\| \[statusline\]' "$README" | grep -qF '✅ v0.1.0' && echo yes || echo no)" "yes"
check "pr-workflow row still 'planned' (unrelated row untouched)" \
  "$(grep -E '^\| pr-workflow' "$README" | grep -qi 'planned' && echo yes || echo no)" "yes"
check "guards row still 'planned' (unrelated row untouched)" \
  "$(grep -E '^\| guards' "$README" | grep -qi 'planned' && echo yes || echo no)" "yes"

# =====================================================================
# (3) MIGRATION.md — worktrees section
# =====================================================================

# Extract the worktrees section: from the "## worktrees" heading up to (not
# including) the next "## " heading.
wt_section() {
  awk '
    /^## worktrees/ { flag=1 }
    flag && /^## / && !/^## worktrees/ { exit }
    flag { print }
  ' "$MIGRATION"
}

WT_SECTION="$(wt_section)"
check "MIGRATION.md has a worktrees section" \
  "$([ -n "$WT_SECTION" ] && echo yes || echo no)" "yes"

# Output: heading no longer says "planned" (updated to ported/done).
WT_HEADING="$(grep -E '^## worktrees' "$MIGRATION" | head -n1)"
check "worktrees section heading no longer says 'planned'" \
  "$(grep -qi 'planned' <<<"$WT_HEADING" && echo present || echo absent)" "absent"
check "worktrees section heading indicates ported/done status" \
  "$(grep -qiE 'ported|done' <<<"$WT_HEADING" && echo yes || echo no)" "yes"

# Output: notes the skills were fresh-written against current git-helpers,
# rather than ported.
check "worktrees section notes skills were fresh-written against git-helpers" \
  "$(grep -qi 'fresh' <<<"$WT_SECTION" && grep -qi 'git-helpers' <<<"$WT_SECTION" && echo yes || echo no)" "yes"

# Output: records that general/todo-worktree.sh was deliberately NOT
# ported, with the reason (depends on clam-code session tooling) and the
# revisit note (alongside the tracking plugin).
check "worktrees section mentions general/todo-worktree.sh" \
  "$(grep -qF 'todo-worktree.sh' <<<"$WT_SECTION" && echo yes || echo no)" "yes"
check "worktrees section says todo-worktree.sh was NOT ported" \
  "$(grep -qiE 'not (be )?ported|deliberately not' <<<"$WT_SECTION" && echo yes || echo no)" "yes"
check "worktrees section notes the revisit-alongside-tracking-plugin plan" \
  "$(grep -qi 'tracking' <<<"$WT_SECTION" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
