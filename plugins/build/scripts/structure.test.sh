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
#   - sync-pr skill does NOT exist (B06 build-cleanup: removed, moved to
#     forge-github)
#   - No references to the removed .claude/clam-profile.md path in the
#     repo (cross-plugin coherence check)
#   - .claude/clam-profile.jsonc exists and is valid JSON (after comment
#     stripping)
#   - build plugin is registered in .claude-plugin/marketplace.json
#
# Contract: B06 build-cleanup
#
# Behavior:
#   The sync-pr skill directory is deleted at implementation. Check 5
#   below asserts ABSENCE of both paths.
#
# Contract: B09 build-skill-conversion
#
# Behavior:
#   The SessionStart hook is removed entirely: hooks/hooks.json and
#   scripts/build-context.sh no longer exist, and the plugin registers no
#   hooks at all. In its place, plugins/build/skills/context/SKILL.md
#   exists (skills/ is reintroduced, superseding B06's incidental
#   "skills/ itself is gone" observation — B06's actual contract, sync-pr
#   absence, remains asserted below).
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
SYNC_PR_DIR="$PLUGIN_ROOT/skills/sync-pr"
CONTEXT_SKILL="$PLUGIN_ROOT/skills/context/SKILL.md"
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
# 3. hooks removed entirely (B09): the plugin registers no hooks at all
# ---------------------------------------------------------------------------

check "hooks/hooks.json does not exist (B09: hook removed, no replacement hook)" \
  "$([ -f "$HOOKS_JSON" ] && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# 4. build-context.sh does not exist (B09: hook script removed with the hook)
# ---------------------------------------------------------------------------

check "build-context.sh does not exist (B09: hook removed, no replacement script)" \
  "$([ -f "$HOOK_SCRIPT" ] && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# 5. sync-pr skill removed (B06 build-cleanup): moved to forge-github.
#    skills/context/SKILL.md exists (B09: on-demand replacement for the
#    removed hook).
# ---------------------------------------------------------------------------

check "skills/sync-pr/SKILL.md does not exist (B06: skill removed)" \
  "$([ -f "$SYNC_PR_SKILL" ] && echo present || echo absent)" "absent"
check "skills/sync-pr/ directory does not exist (B06: skill removed)" \
  "$([ -d "$SYNC_PR_DIR" ] && echo present || echo absent)" "absent"
check "skills/context/SKILL.md exists (B09: on-demand hook replacement)" \
  "$([ -f "$CONTEXT_SKILL" ] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 6. no references to the removed .claude/clam-profile.md path, scoped to
#    plugins/landing/, plugins/build/, and .claude/
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
# 8. build plugin is registered in .claude-plugin/marketplace.json
# ---------------------------------------------------------------------------

check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

build_entry_count=$(jq -r '[.plugins[]? | select(.name=="build")] | length' "$MARKETPLACE" 2>/dev/null)
check "marketplace.json has exactly one plugins[] entry named 'build'" \
  "$build_entry_count" "1"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
