#!/bin/bash
# Test for Block B03 (assembly & registration). Authoritative contract: the
# HTML-comment docblock "Contract: B03 assembly & registration (ask-in-text)"
# in the root README.md, just under the Plugins table. Asserts directly on
# the two shared repo surfaces the contract names as B03's registration
# outputs:
#
#   (1) .claude-plugin/marketplace.json — exactly one plugins[] entry named
#       "ask-in-text": source "./plugins/ask-in-text", no version field
#       (plugin.json is the single source of truth for version), and a
#       non-empty description naming AskUserQuestion.
#   (2) README.md Plugins table — exactly one row linking
#       plugins/ask-in-text/, carrying the ✅ status marker, the plugin.json
#       version, and naming AskUserQuestion.
#
# The plugin-local surfaces (plugin.json, hooks/hooks.json) are covered by
# structure.test.sh, not here.
#
# The contract docblock itself quotes the exact README row text this test
# looks for, so every README content check below runs against a
# comment-stripped copy (sed '/<!--/,/-->/d') — render-doc's
# registration.test.sh uses this same technique. Without it, the docblock's
# own prose would satisfy a check before the real row exists.
#
# Run: bash plugins/ask-in-text/scripts/registration.test.sh (non-zero exit
# on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
README="$ROOT/README.md"
PLUGIN_JSON="$ROOT/plugins/ask-in-text/.claude-plugin/plugin.json"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# --- 0. Preconditions ---
check "plugin.json exists (structure dependency)" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "README.md exists" \
  "$([ -f "$README" ] && echo yes || echo no)" "yes"
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

# The version source of truth: read dynamically from plugin.json, never
# hardcoded (contract's "version agrees between plugin.json and the README
# row" invariant).
VERSION="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"

# =====================================================================
# (1) marketplace.json
# =====================================================================

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

AIT_COUNT="$(jq '[.plugins[]? | select(.name=="ask-in-text")] | length' "$MARKETPLACE" 2>/dev/null)"
check "marketplace.json has exactly one plugins[] entry named 'ask-in-text'" \
  "$AIT_COUNT" "1"

AIT_ENTRY="$(jq -c '.plugins[]? | select(.name=="ask-in-text")' "$MARKETPLACE" 2>/dev/null)"

check "ask-in-text entry source is './plugins/ask-in-text'" \
  "$(jq -r 'select(.name=="ask-in-text") | .source' <<<"$AIT_ENTRY" 2>/dev/null)" \
  "./plugins/ask-in-text"

check "ask-in-text entry has no version field (plugin.json is source of truth)" \
  "$(jq -r 'has("version") | not' <<<"$AIT_ENTRY" 2>/dev/null)" "true"

AIT_DESC="$(jq -r '.description // empty' <<<"$AIT_ENTRY" 2>/dev/null)"
check "ask-in-text entry description is non-empty" \
  "$([ -n "$AIT_DESC" ] && echo yes || echo no)" "yes"
check "ask-in-text entry description names AskUserQuestion" \
  "$(grep -qF 'AskUserQuestion' <<<"$AIT_DESC" && echo yes || echo no)" "yes"

# =====================================================================
# (2) README.md Plugins table
# =====================================================================
# Every check in this part reads $BODY: the README with its own contract
# docblock stripped out, so the docblock's prose (which quotes this exact
# row) can never satisfy a check meant for real README content.

BODY="$(sed '/<!--/,/-->/d' "$README" 2>/dev/null)"

AIT_ROW_COUNT="$(grep -cF '[ask-in-text](plugins/ask-in-text/)' <<<"$BODY" || true)"
check "stripped README has exactly one row linking plugins/ask-in-text/" \
  "$AIT_ROW_COUNT" "1"

AIT_ROW="$(grep -F '[ask-in-text](plugins/ask-in-text/)' <<<"$BODY" | head -n1)"
check "ask-in-text row shows the ✅ status marker" \
  "$(grep -qF '✅' <<<"$AIT_ROW" && echo yes || echo no)" "yes"
check "ask-in-text row shows the version from plugin.json (v$VERSION)" \
  "$(grep -qF "v$VERSION" <<<"$AIT_ROW" && echo yes || echo no)" "yes"
check "ask-in-text row names AskUserQuestion" \
  "$(grep -qF 'AskUserQuestion' <<<"$AIT_ROW" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
