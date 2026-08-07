#!/bin/bash
# Validates marketplace.json against plugin directories.
#
# Checks:
#   1. Every plugin directory has a marketplace entry (and vice-versa)
#   2. Marketplace source paths resolve to real directories
#   3. Every entry carries a nonempty "category" string (the value itself is
#      data, not code: no taxonomy list is enforced here)
#   4. Every renames target is a valid marketplace plugin (or null)
#
# Run: bash scripts/marketplace-lint.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"

FAILED=0
check() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

check "marketplace.json exists" \
  "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "marketplace.json is valid JSON" \
  "$(jq -e . "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

mapfile -t marketplace_names < <(jq -r '.plugins[].name' "$MARKETPLACE" 2>/dev/null | sort)
mapfile -t dir_names < <(find "$ROOT/plugins" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | xargs -n1 basename | sort)

for name in "${dir_names[@]}"; do
  if ! printf '%s\n' "${marketplace_names[@]}" | grep -qx "$name"; then
    echo "FAIL  plugin directory '$name' has no marketplace entry"; FAILED=1
  fi
done

for name in "${marketplace_names[@]}"; do
  if ! printf '%s\n' "${dir_names[@]}" | grep -qx "$name"; then
    echo "FAIL  marketplace entry '$name' has no plugin directory"; FAILED=1
  fi
done

for name in "${marketplace_names[@]}"; do
  plugin_json="$ROOT/plugins/$name/.claude-plugin/plugin.json"
  check "$name: plugin.json exists" \
    "$([ -f "$plugin_json" ] && echo yes || echo no)" "yes"

  mp_source=$(jq -r --arg n "$name" '.plugins[] | select(.name == $n) | .source' "$MARKETPLACE")
  check "$name: marketplace source resolves" \
    "$([ -d "$ROOT/${mp_source#./}" ] && echo yes || echo no)" "yes"

  # Presence only: a missing key, null, "", or a non-string all fail. Which
  # categories exist is catalog data, so no allowed-value list lives here.
  check "$name: category is a nonempty string" \
    "$(jq -e --arg n "$name" \
        '.plugins[] | select(.name == $n) | (.category | type == "string" and length > 0)' \
        "$MARKETPLACE" >/dev/null 2>&1 && echo yes || echo no)" "yes"

  if jq -e --arg n "$name" '.plugins[] | select(.name == $n) | has("version")' "$MARKETPLACE" >/dev/null 2>&1; then
    echo "WARN  $name: version in marketplace.json is redundant (plugin.json is the source of truth)"
  fi
done

renames=$(jq -r '.renames // {} | to_entries[] | "\(.key)\t\(.value)"' "$MARKETPLACE" 2>/dev/null)
if [ -n "$renames" ]; then
  while IFS=$'\t' read -r old_name new_name; do
    if [ "$new_name" = "null" ]; then
      echo "PASS  rename '$old_name' -> removed (null)"
    elif printf '%s\n' "${marketplace_names[@]}" | grep -qx "$new_name"; then
      echo "PASS  rename '$old_name' -> '$new_name' (valid target)"
    else
      echo "FAIL  rename '$old_name' -> '$new_name' (target not in marketplace)"; FAILED=1
    fi
    if printf '%s\n' "${marketplace_names[@]}" | grep -qx "$old_name"; then
      echo "FAIL  rename '$old_name' still exists as a marketplace plugin (should be removed)"; FAILED=1
    fi
  done <<< "$renames"
fi

echo ""
if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES — fix before merging"; fi
exit $FAILED
