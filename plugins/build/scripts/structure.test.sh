#!/bin/bash
# Composition test for the build plugin. Verifies structural integrity
# and cross-plugin coherence.
#
# Contract: B05 registration-integration
#
# Behavior:
#   Verifies the build plugin's structure is complete and coherent:
#   - plugin.json is valid JSON with required fields (name, description, version)
#   - README.md exists and is non-empty
#   - hooks.json wires a SessionStart hook
#   - build-context.sh exists and is executable
#   - sync-pr skill exists (SKILL.md present)
#   - No references to the removed .claude/clam-profile.md path in the
#     repo (cross-plugin coherence check)
#   - .claude/clam-profile.jsonc exists and is valid JSON (after comment
#     stripping)
#   - build plugin is registered in .claude-plugin/marketplace.json
#
# The "no legacy references" check is scoped to plugins/landing/,
# plugins/build/, and .claude/ (the surfaces the .claude/clam-profile.md
# -> .claude/clam-profile.jsonc migration touched), excluding *.test.sh
# fixtures (which legitimately reference the legacy path for legacy-support
# testing), .git/, .local/, and binary files. It flags the exact contiguous
# substring ".claude/clam-profile.md" only — prose that documents the
# migration by naming "clam-profile.md" and ".claude/" separately (not
# contiguously) is fine and is exactly how the migrated docs phrase it.
#
# Run: bash plugins/build/scripts/structure.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."

PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
README="$PLUGIN_ROOT/README.md"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
HOOK_SCRIPT="$PLUGIN_ROOT/scripts/build-context.sh"
SYNC_PR_SKILL="$PLUGIN_ROOT/skills/sync-pr/SKILL.md"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
CLAM_PROFILE_JSONC="$REPO_ROOT/.claude/clam-profile.jsonc"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# 1. plugin.json is valid JSON with required fields
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

check "plugin.json has a non-empty .name" \
  "$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null | grep -q . && echo yes || echo no)" "yes"
check "plugin.json has a non-empty .description" \
  "$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null | grep -q . && echo yes || echo no)" "yes"
check "plugin.json has a non-empty .version" \
  "$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null | grep -q . && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 2. README.md exists and is non-empty
# ---------------------------------------------------------------------------

check "README.md exists" "$([ -f "$README" ] && echo yes || echo no)" "yes"
check "README.md is non-empty" \
  "$([ -s "$README" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 3. hooks.json wires a SessionStart hook
# ---------------------------------------------------------------------------

check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

session_start_count=$(jq -r '[.hooks.SessionStart[]?.hooks[]?] | length' "$HOOKS_JSON" 2>/dev/null)
check "hooks.json wires at least one SessionStart hook" \
  "$([[ "$session_start_count" =~ ^[0-9]+$ ]] && [[ "$session_start_count" -gt 0 ]] && echo yes || echo no)" "yes"

session_start_command=$(jq -r '.hooks.SessionStart[0].hooks[0].command // empty' "$HOOKS_JSON" 2>/dev/null)
check "SessionStart hook command references build-context.sh" \
  "$(grep -qF 'build-context.sh' <<<"$session_start_command" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 4. deliver-context.sh exists and is executable
# ---------------------------------------------------------------------------

check "build-context.sh exists" "$([ -f "$HOOK_SCRIPT" ] && echo yes || echo no)" "yes"
check "build-context.sh is executable" "$([ -x "$HOOK_SCRIPT" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 5. sync-pr skill exists
# ---------------------------------------------------------------------------

check "skills/sync-pr/SKILL.md exists" \
  "$([ -f "$SYNC_PR_SKILL" ] && echo yes || echo no)" "yes"
check "skills/sync-pr/SKILL.md is non-empty" \
  "$([ -s "$SYNC_PR_SKILL" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 6. no references to the removed .claude/clam-profile.md path, scoped to
#    plugins/landing/, plugins/deliver/, and .claude/
# ---------------------------------------------------------------------------

LEGACY_REFS=$(grep -rIlF \
  --exclude='*.test.sh' \
  --exclude-dir='.git' \
  --exclude-dir='.local' \
  -- '.claude/clam-profile.md' \
  "$REPO_ROOT/plugins/landing" "$REPO_ROOT/plugins/build" "$REPO_ROOT/.claude" 2>/dev/null)

check "no non-test files under plugins/landing/, plugins/build/, .claude/ reference the exact path .claude/clam-profile.md" \
  "$([ -z "$LEGACY_REFS" ] && echo yes || echo no)" "yes"
if [[ -n "$LEGACY_REFS" ]]; then
  echo "  offending files:" >&2
  sed 's/^/    /' <<<"$LEGACY_REFS" >&2
fi

# ---------------------------------------------------------------------------
# 7. .claude/clam-profile.jsonc exists and is valid JSON after stripping //
#    comments
# ---------------------------------------------------------------------------

check ".claude/clam-profile.jsonc exists" \
  "$([ -f "$CLAM_PROFILE_JSONC" ] && echo yes || echo no)" "yes"
check ".claude/clam-profile.jsonc is valid JSON after stripping // comments" \
  "$(sed 's#//.*##' "$CLAM_PROFILE_JSONC" 2>/dev/null | jq -e . >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 8. deliver plugin is registered in .claude-plugin/marketplace.json
# ---------------------------------------------------------------------------

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

build_entry_count=$(jq -r '[.plugins[]? | select(.name=="build")] | length' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json has exactly one plugins[] entry named 'build'" \
  "$build_entry_count" "1"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
