#!/bin/bash
# Composition test for the deliver plugin. Verifies structural integrity
# and cross-plugin coherence.
#
# Contract: B05 registration-integration
#
# Behavior:
#   Verifies the deliver plugin's structure is complete and coherent:
#   - plugin.json is valid JSON with required fields (name, description, version)
#   - README.md exists and is non-empty
#   - hooks.json wires a SessionStart hook
#   - deliver-context.sh exists and is executable
#   - sync-pr skill exists (SKILL.md present)
#   - No references to the removed .claude/clam-profile.md path in the
#     repo (cross-plugin coherence check)
#   - .claude/clam-profile.jsonc exists and is valid JSON (after comment
#     stripping)
#   - deliver plugin is registered in .claude-plugin/marketplace.json
#
# Run: bash plugins/deliver/scripts/structure.test.sh

echo "NotImplemented: B05" >&2; exit 1
