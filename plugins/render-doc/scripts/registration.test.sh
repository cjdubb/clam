#!/bin/bash
# Test for Block B02 (registration). Authoritative contract: this file. The
# block's contract docblock sat in the root README.md just under the Plugins
# table and was removed once the block landed (recoverable from git history).
# Asserts directly on the two shared repo files the contract named as B02's
# outputs:
#
#   (1) .claude-plugin/marketplace.json — exactly one plugins[] entry named
#       "render-doc": source "./plugins/render-doc", no version field
#       (plugin.json is the single source of truth for version), and a
#       non-empty description covering both rendering and annotation.
#   (2) README.md Plugins table — exactly one row linking
#       plugins/render-doc/, carrying the ✅ status marker, the plugin.json
#       version, and naming /render-doc:render.
#
# The contract docblock itself quotes the exact README row text this test
# looks for (and marketplace-shaped prose), so every README content check
# below runs against a comment-stripped copy (sed '/<!--/,/-->/d') — the
# debugging plugin's structure.test.sh uses this same technique. Without
# it, the docblock's own prose would satisfy a check before the real row
# exists.
#
# Run: bash plugins/render-doc/scripts/registration.test.sh (non-zero exit
# on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
README="$ROOT/README.md"
PLUGIN_JSON="$ROOT/plugins/render-doc/.claude-plugin/plugin.json"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# --- 0. Preconditions ---
check "plugin.json exists (B01 dependency)" \
  "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "README.md exists" \
  "$([ -f "$README" ] && echo yes || echo no)" "yes"
check "jq is available" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

# The version source of truth: read dynamically from plugin.json, never
# hardcoded (contract's "version agrees with plugin.json" invariant).
VERSION="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"

# =====================================================================
# (1) marketplace.json
# =====================================================================

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

RD_COUNT="$(jq '[.plugins[]? | select(.name=="render-doc")] | length' "$MARKETPLACE" 2>/dev/null)"
check "marketplace.json has exactly one plugins[] entry named 'render-doc'" \
  "$RD_COUNT" "1"

RD_ENTRY="$(jq -c '.plugins[]? | select(.name=="render-doc")' "$MARKETPLACE" 2>/dev/null)"

check "render-doc entry source is './plugins/render-doc'" \
  "$(jq -r 'select(.name=="render-doc") | .source' <<<"$RD_ENTRY" 2>/dev/null)" \
  "./plugins/render-doc"

check "render-doc entry has no version field (plugin.json is source of truth)" \
  "$(jq -r 'has("version") | not' <<<"$RD_ENTRY" 2>/dev/null)" "true"

RD_DESC="$(jq -r '.description // empty' <<<"$RD_ENTRY" 2>/dev/null)"
check "render-doc entry description is non-empty" \
  "$([ -n "$RD_DESC" ] && echo yes || echo no)" "yes"
check "render-doc entry description mentions rendering" \
  "$(grep -qiE 'render' <<<"$RD_DESC" && echo yes || echo no)" "yes"
check "render-doc entry description mentions annotation" \
  "$(grep -qiE 'annotat' <<<"$RD_DESC" && echo yes || echo no)" "yes"

# =====================================================================
# (2) README.md Plugins table
# =====================================================================
# Every check in this part reads $BODY: the README with its own contract
# docblock stripped out, so the docblock's prose (which quotes this exact
# row) can never satisfy a check meant for real README content.

BODY="$(sed '/<!--/,/-->/d' "$README" 2>/dev/null)"

RD_ROW_COUNT="$(grep -cF '[render-doc](plugins/render-doc/)' <<<"$BODY" || true)"
check "stripped README has exactly one row linking plugins/render-doc/" \
  "$RD_ROW_COUNT" "1"

RD_ROW="$(grep -F '[render-doc](plugins/render-doc/)' <<<"$BODY" | head -n1)"
check "render-doc row shows the ✅ status marker" \
  "$(grep -qF '✅' <<<"$RD_ROW" && echo yes || echo no)" "yes"
check "render-doc row shows the version from plugin.json" \
  "$(grep -qF "v$VERSION" <<<"$RD_ROW" && echo yes || echo no)" "yes"
check "render-doc row names /render-doc:render" \
  "$(grep -qF '/render-doc:render' <<<"$RD_ROW" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
