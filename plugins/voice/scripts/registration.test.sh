#!/bin/bash
# Test for Block B02 (assembly-and-registration), shared repo surfaces.
# Authoritative contract: the HTML-comment docblock "Contract: B02
# assembly-and-registration (voice)" in the root README.md, just under the
# Plugins table. Asserts directly on the four shared repo surfaces the
# contract names as B02's registration outputs:
#
#   (1) .claude-plugin/marketplace.json — exactly one plugins[] entry named
#       "voice": source "./plugins/voice", NO version field (plugin.json
#       is the single source of truth for version), final description.
#   (2) README.md Plugins table — exactly one row linking plugins/voice/,
#       status cell exactly "✅ v0.1.0", final description, not the
#       table's last plugin row (last-row invariant).
#   (3) MIGRATION.md — a "## voice — ported (from clam-code)" section
#       recording the port (source, what came over, what stays behind, the
#       canonical-home decision), free of STUB markers, placed before
#       "## Unassigned".
#   (4) .github/ISSUE_TEMPLATE/feature.yml and bug.yml — the id=plugin
#       dropdown lists "voice" in alphabetical position (between updates
#       and worktrees).
#
# Also asserts the B02 contract comment itself is gone from the raw
# README.md (it is marked remove-at-acceptance).
#
# The plugin-local surfaces (plugin.json, hooks/hooks.json) are covered by
# structure.test.sh, not here.
#
# The contract docblock quotes the exact README row, MIGRATION.md section,
# and dropdown text this test looks for, so every content check against
# README.md or MIGRATION.md below runs against a comment-stripped copy
# (sed '/<!--/,/-->/d') — ask-in-text's registration.test.sh and
# render-doc's migration.test.sh use this same technique. Without it, the
# docblock's own prose could satisfy a check before the real content
# exists. The one exception is the "contract comment is gone" check, which
# reads the raw file on purpose.
#
# Run: bash plugins/voice/scripts/registration.test.sh (non-zero exit on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
README="$ROOT/README.md"
MIGRATION="$ROOT/MIGRATION.md"
FEATURE_YML="$ROOT/.github/ISSUE_TEMPLATE/feature.yml"
BUG_YML="$ROOT/.github/ISSUE_TEMPLATE/bug.yml"
PLUGIN_JSON="$ROOT/plugins/voice/.claude-plugin/plugin.json"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

count_lines() { # helper: wc -l on a possibly-empty string, no phantom "1"
  if [[ -z "$1" ]]; then echo 0; else wc -l <<<"$1" | tr -d ' '; fi
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugin.json exists (structure dependency)" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "README.md exists" \
  "$([ -f "$README" ] && echo yes || echo no)" "yes"
check "MIGRATION.md exists" \
  "$([ -f "$MIGRATION" ] && echo yes || echo no)" "yes"
check "feature.yml exists" \
  "$([ -f "$FEATURE_YML" ] && echo yes || echo no)" "yes"
check "bug.yml exists" \
  "$([ -f "$BUG_YML" ] && echo yes || echo no)" "yes"
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

VERSION="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"

# =====================================================================
# (1) marketplace.json
# =====================================================================

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

VOICE_COUNT="$(jq '[.plugins[]? | select(.name=="voice")] | length' "$MARKETPLACE" 2>/dev/null)"
check "marketplace.json has exactly one plugins[] entry named 'voice'" \
  "$VOICE_COUNT" "1"

VOICE_ENTRY="$(jq -c '.plugins[]? | select(.name=="voice")' "$MARKETPLACE" 2>/dev/null)"

check "voice entry source is './plugins/voice'" \
  "$(jq -r 'select(.name=="voice") | .source' <<<"$VOICE_ENTRY" 2>/dev/null)" \
  "./plugins/voice"

check "voice entry has no version field (plugin.json is source of truth)" \
  "$(jq -r 'has("version") | not' <<<"$VOICE_ENTRY" 2>/dev/null)" "true"

MP_DESC="$(jq -r '.description // empty' <<<"$VOICE_ENTRY" 2>/dev/null)"
check "voice entry description is non-empty" \
  "$([ -n "$MP_DESC" ] && echo yes || echo no)" "yes"
check "voice entry description names the Voice spec" \
  "$(grep -qi 'voice' <<<"$MP_DESC" && echo yes || echo no)" "yes"
check "voice entry description names SessionStart" \
  "$(grep -qF 'SessionStart' <<<"$MP_DESC" && echo yes || echo no)" "yes"
check "voice entry description is not a STUB/TODO/NotImplemented placeholder" \
  "$(grep -qiE 'TODO|NotImplemented|\bstub\b' <<<"$MP_DESC" && echo placeholder || echo ok)" "ok"

# =====================================================================
# (2) README.md Plugins table
# =====================================================================
# Every check in this part reads $README_BODY: README.md with its own
# contract docblock stripped out, so the docblock's prose (which quotes
# this exact row) can never satisfy a check meant for real content.

README_BODY="$(sed '/<!--/,/-->/d' "$README" 2>/dev/null)"

VOICE_ROW_COUNT="$(grep -cF '[voice](plugins/voice/)' <<<"$README_BODY" || true)"
check "stripped README has exactly one row linking plugins/voice/" \
  "$VOICE_ROW_COUNT" "1"

VOICE_ROW="$(grep -F '[voice](plugins/voice/)' <<<"$README_BODY" | head -n1)"
STATUS_CELL="$(awk -F'|' '{print $3}' <<<"$VOICE_ROW" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
DESC_CELL="$(awk -F'|' '{print $4}' <<<"$VOICE_ROW" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

check "voice row status cell is exactly '✅ v0.1.0'" "$STATUS_CELL" "✅ v0.1.0"
check "voice row status cell version matches plugin.json (v$VERSION)" \
  "$(grep -qF "v$VERSION" <<<"$STATUS_CELL" && echo yes || echo no)" "yes"
check "voice row description is non-empty" \
  "$([ -n "$DESC_CELL" ] && echo yes || echo no)" "yes"
check "voice row description is not a STUB/TODO/NotImplemented placeholder" \
  "$(grep -qiE 'TODO|NotImplemented|\bstub\b' <<<"$DESC_CELL" && echo placeholder || echo ok)" "ok"

VOICE_LINE="$(grep -nF '[voice](plugins/voice/)' <<<"$README_BODY" | head -n1 | cut -d: -f1)"
LAST_PLUGIN_ROW_LINE="$(grep -nE '^\| \[[^]]+\]\(plugins/[^)]+/\)' <<<"$README_BODY" | tail -n1 | cut -d: -f1)"
check "voice row is not the table's last plugin row (last-row invariant)" \
  "$([[ -n "$VOICE_LINE" && -n "$LAST_PLUGIN_ROW_LINE" && "$VOICE_LINE" -lt "$LAST_PLUGIN_ROW_LINE" ]] && echo yes || echo no)" \
  "yes"

# =====================================================================
# (3) MIGRATION.md "## voice — ported (from clam-code)" section
# =====================================================================

MIGRATION_BODY="$(sed '/<!--/,/-->/d' "$MIGRATION" 2>/dev/null)"

HEADING="## voice — ported (from clam-code)"
HEADING_COUNT="$(grep -cF "$HEADING" <<<"$MIGRATION_BODY" || true)"
check "stripped MIGRATION.md has exactly one voice-ported heading" \
  "$HEADING_COUNT" "1"

voice_section() {
  awk -v heading="$HEADING" '
    $0 == heading { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$MIGRATION_BODY"
}
VOICE_SECTION="$(voice_section)"

check "voice section is non-empty" \
  "$([ -n "$VOICE_SECTION" ] && echo yes || echo no)" "yes"

# --- source: clam-code general/system-prompt.md Voice section, PRs #357/#361, merged 2026-07-31
check "voice section names general/system-prompt.md" \
  "$(grep -qF 'general/system-prompt.md' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section names the Voice section of the source file" \
  "$(grep -qi 'Voice section' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section cites PR #357" \
  "$(grep -qF '#357' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section cites PR #361" \
  "$(grep -qF '#361' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section cites the 2026-07-31 merge date" \
  "$(grep -qF '2026-07-31' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"

# --- what came over: the spec text verbatim, minus the clause tying it to the source's Communication section
check "voice section states the spec text came over verbatim" \
  "$(grep -qi 'verbatim' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section names the source's Communication section" \
  "$(grep -qi 'Communication section' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section states that clause was dropped" \
  "$(grep -qi 'dropped' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"

# --- what stays behind: dev-docs/voice campaign record and Phase 6 toolkit, org-private
check "voice section names dev-docs/voice" \
  "$(grep -qF 'dev-docs/voice' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section names the Phase 6 toolkit" \
  "$(grep -qF 'Phase 6' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section states the retained material is org-private" \
  "$(grep -qi 'org-private' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section mentions transcript excerpts" \
  "$(grep -qi 'transcript excerpts' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section mentions captured system prompts" \
  "$(grep -qi 'captured system prompts' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section states this repo is public" \
  "$(grep -qi 'public' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"

# --- canonical-home decision: this plugin is canonical, source repo's copy is a consumer until retired
check "voice section states this plugin is canonical" \
  "$(grep -qi 'canonical' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section states the source repo's copy is a consumer" \
  "$(grep -qi 'consumer' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"
check "voice section states the source copy lasts until retired" \
  "$(grep -qi 'retired' <<<"$VOICE_SECTION" && echo yes || echo no)" "yes"

check "voice section is not a STUB placeholder" \
  "$(grep -qiE 'STUB|TODO|NotImplemented' <<<"$VOICE_SECTION" && echo placeholder || echo ok)" "ok"

VOICE_HEADING_LINE="$(grep -nF "$HEADING" <<<"$MIGRATION_BODY" | head -n1 | cut -d: -f1)"
UNASSIGNED_LINE="$(grep -nE '^## Unassigned' <<<"$MIGRATION_BODY" | head -n1 | cut -d: -f1)"
check "voice section is placed before the Unassigned section" \
  "$([[ -n "$VOICE_HEADING_LINE" && -n "$UNASSIGNED_LINE" && "$VOICE_HEADING_LINE" -lt "$UNASSIGNED_LINE" ]] && echo yes || echo no)" \
  "yes"

# =====================================================================
# (4) Issue-template dropdowns: feature.yml and bug.yml
# =====================================================================

plugin_dropdown() { # $1 = file
  awk '
    /^[[:space:]]*id: plugin$/ { flag=1 }
    flag && /^[[:space:]]*validations:/ { exit }
    flag { print }
  ' "$1"
}

for pair in "feature.yml:$FEATURE_YML" "bug.yml:$BUG_YML"; do
  label="${pair%%:*}"
  file="${pair#*:}"
  dropdown="$(plugin_dropdown "$file")"

  check "$label plugin dropdown lists voice" \
    "$(grep -qE '^[[:space:]]*- voice[[:space:]]*$' <<<"$dropdown" && echo yes || echo no)" "yes"

  updates_line="$(grep -nE '^[[:space:]]*- updates[[:space:]]*$' <<<"$dropdown" | head -n1 | cut -d: -f1)"
  voice_line="$(grep -nE '^[[:space:]]*- voice[[:space:]]*$' <<<"$dropdown" | head -n1 | cut -d: -f1)"
  worktrees_line="$(grep -nE '^[[:space:]]*- worktrees[[:space:]]*$' <<<"$dropdown" | head -n1 | cut -d: -f1)"

  check "$label dropdown: voice sits between updates and worktrees" \
    "$([[ -n "$updates_line" && -n "$voice_line" && -n "$worktrees_line" \
        && "$updates_line" -lt "$voice_line" && "$voice_line" -lt "$worktrees_line" ]] \
        && echo yes || echo no)" \
    "yes"
done

# =====================================================================
# B02 contract comment gone from the raw README.md (remove-at-acceptance)
# =====================================================================

check "B02 contract comment marker is gone from the raw README.md" \
  "$(grep -qF 'Contract: B02 assembly-and-registration (voice)' "$README" && echo present || echo absent)" \
  "absent"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
