#!/usr/bin/env bash
# Contract: B05 issue-template-lint (plan 001-repo-issue-template)
# Behavior:
#   Verifies the GitHub issue templates stay valid and in sync with the
#   repo. Checks, in order:
#     1. .github/ISSUE_TEMPLATE/{feature.yml,bug.yml,config.yml} all exist.
#     2. YAML parse check: each file parses. Runs only when a parser is
#        available (python3 with the yaml module); when unavailable, prints
#        "SKIP yaml-parse (no parser)" to stderr and continues with the
#        structural checks below — never fails solely for lack of a parser.
#     3. feature.yml declares label `feature`; bug.yml declares label `bug`
#        (a `labels:` list containing exactly that one label).
#     4. In BOTH forms, the id=plugin dropdown's options are exactly
#        "repo-wide / other" followed by every plugins/* directory name in
#        alphabetical order — no missing, extra, duplicated, or misordered
#        entries.
#     5. config.yml sets blank_issues_enabled: false and has no
#        contact_links key.
# Inputs:
#   Runs from the repo root (no arguments). Reads .github/ISSUE_TEMPLATE/*
#   and the plugins/ directory listing (directories only; files such as
#   plugins/PLUGIN_README_TEMPLATE.md are ignored).
# Outputs:
#   Exit 0 when every check passes (prints "issue-template-lint: OK" to
#   stdout). On failure, one line per violation to stderr, exit 1.
# Errors:
#   Missing plugins/ or .github/ISSUE_TEMPLATE/ directory (not run from
#   repo root): message to stderr, exit 2.
# Invariants:
#   - Read-only: never modifies any file.
#   - No hard dependency beyond bash + coreutils; python3/yaml is an
#     opportunistic upgrade, not a requirement.
#   - Reports ALL violations found, not just the first.
# Edge cases:
#   - Empty plugins/ dir: expected options are just "repo-wide / other".
#   - Options listed under a different field id than `plugin`: violation
#     (stable ids are part of the form contracts B01/B02).
#   - Comment-only or empty template file: fails checks 3-5 (and 2 where a
#     parser is present and the file is invalid).

set -u

TEMPLATE_DIR=".github/ISSUE_TEMPLATE"
PLUGINS_DIR="plugins"

if [ ! -d "$PLUGINS_DIR" ]; then
  echo "issue-template-lint: '$PLUGINS_DIR' directory not found -- run this script from the repo root" >&2
  exit 2
fi
if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "issue-template-lint: '$TEMPLATE_DIR' directory not found -- run this script from the repo root" >&2
  exit 2
fi

FEATURE="$TEMPLATE_DIR/feature.yml"
BUG="$TEMPLATE_DIR/bug.yml"
CONFIG="$TEMPLATE_DIR/config.yml"

VIOLATIONS=()
add_violation() { VIOLATIONS+=("$1"); }

print_array() { # elements... (possibly zero) -> one per line, nothing if zero elements
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
  fi
}

# ---------------------------------------------------------------------------
# Expected dropdown options: "repo-wide / other" then every plugins/*
# directory name, alphabetical. Directories only -- stray files such as
# plugins/PLUGIN_README_TEMPLATE.md are ignored.
# ---------------------------------------------------------------------------
mapfile -t PLUGIN_DIRS < <(find "$PLUGINS_DIR" -mindepth 1 -maxdepth 1 -type d | sed 's|.*/||' | sort)
EXPECTED_OPTIONS=("repo-wide / other" "${PLUGIN_DIRS[@]}")

# ---------------------------------------------------------------------------
# Clause 1: existence.
# ---------------------------------------------------------------------------
have_feature=1; have_bug=1; have_config=1
[ -f "$FEATURE" ] || { add_violation "feature.yml: missing (expected at $FEATURE)"; have_feature=0; }
[ -f "$BUG" ] || { add_violation "bug.yml: missing (expected at $BUG)"; have_bug=0; }
[ -f "$CONFIG" ] || { add_violation "config.yml: missing (expected at $CONFIG)"; have_config=0; }

# ---------------------------------------------------------------------------
# Clause 2: opportunistic YAML parse check. python3+yaml is an upgrade, not
# a hard dependency -- probe the actual import, not just `command -v`.
# ---------------------------------------------------------------------------
HAVE_PARSER=0
if python3 -c "import yaml" >/dev/null 2>&1; then
  HAVE_PARSER=1
else
  echo "SKIP yaml-parse (no parser)" >&2
fi

yaml_parses() { # file -> exit 0 if valid YAML, exit 1 otherwise
  python3 -c '
import sys, yaml
try:
    with open(sys.argv[1]) as f:
        yaml.safe_load(f)
except Exception:
    sys.exit(1)
' "$1"
}

if [ "$HAVE_PARSER" -eq 1 ]; then
  if [ "$have_feature" -eq 1 ] && ! yaml_parses "$FEATURE"; then
    add_violation "feature.yml: invalid YAML"
  fi
  if [ "$have_bug" -eq 1 ] && ! yaml_parses "$BUG"; then
    add_violation "bug.yml: invalid YAML"
  fi
  if [ "$have_config" -eq 1 ] && ! yaml_parses "$CONFIG"; then
    add_violation "config.yml: invalid YAML"
  fi
fi

# ---------------------------------------------------------------------------
# Clause 3: labels. Extracts a top-level `labels:` block-list (or an inline
# `labels: []`) without requiring a YAML parser.
# ---------------------------------------------------------------------------
get_labels() { # file -> one label per line
  awk '
    /^labels:[[:space:]]*\[\][[:space:]]*$/ { exit }
    /^labels:[[:space:]]*$/ { in_list = 1; next }
    in_list {
      if ($0 ~ /^[[:space:]]+-[[:space:]]+/) {
        val = $0
        sub(/^[[:space:]]+-[[:space:]]+/, "", val)
        gsub(/^["'"'"']|["'"'"']$/, "", val)
        print val
        next
      } else {
        in_list = 0
      }
    }
  ' "$1"
}

check_labels() { # file expected_label report_name
  local file="$1" expected="$2" report_name="$3"
  local labels=()
  mapfile -t labels < <(get_labels "$file")
  if [ "${#labels[@]}" -ne 1 ] || [ "${labels[0]}" != "$expected" ]; then
    add_violation "$report_name: labels must be exactly [$expected] (got: $(print_array "${labels[@]}" | tr '\n' ',' | sed 's/,$//'))"
  fi
}

# ---------------------------------------------------------------------------
# Clause 4: dropdown sync. Extracts the `options:` list under the body item
# whose `id:` equals the given field id (must be inside a `type: dropdown`
# item), without requiring a YAML parser.
# ---------------------------------------------------------------------------
get_dropdown_options() { # file field_id -> one option per line
  awk -v target="$2" '
    /^  - type: dropdown/ { in_block = 1; block_id = ""; in_options = 0; next }
    /^  - / { in_block = 0; in_options = 0; next }
    in_block && /^    id: / {
      id = $0
      sub(/^    id: */, "", id)
      gsub(/^["'"'"']|["'"'"']$/, "", id)
      block_id = id
      next
    }
    in_block && block_id == target && /^      options:/ { in_options = 1; next }
    in_options {
      if ($0 ~ /^        - /) {
        val = $0
        sub(/^        - */, "", val)
        gsub(/^["'"'"']|["'"'"']$/, "", val)
        print val
        next
      } else {
        in_options = 0
      }
    }
  ' "$1"
}

check_dropdown() { # file report_name
  local file="$1" report_name="$2"
  local actual=()
  mapfile -t actual < <(get_dropdown_options "$file" "plugin")

  if [ "${#actual[@]}" -eq "${#EXPECTED_OPTIONS[@]}" ]; then
    local same=1 i
    for i in "${!EXPECTED_OPTIONS[@]}"; do
      if [ "${actual[$i]}" != "${EXPECTED_OPTIONS[$i]}" ]; then
        same=0
        break
      fi
    done
    if [ "$same" -eq 1 ]; then
      return
    fi
  fi

  local missing extra
  missing="$(comm -23 <(print_array "${EXPECTED_OPTIONS[@]}" | sort) <(print_array "${actual[@]}" | sort))"
  extra="$(comm -13 <(print_array "${EXPECTED_OPTIONS[@]}" | sort) <(print_array "${actual[@]}" | sort))"

  if [ -n "$missing" ] || [ -n "$extra" ]; then
    if [ -n "$missing" ]; then
      add_violation "$report_name: dropdown id=plugin missing option(s): $(printf '%s' "$missing" | tr '\n' ',' | sed 's/,$//')"
    fi
    if [ -n "$extra" ]; then
      add_violation "$report_name: dropdown id=plugin unexpected option(s): $(printf '%s' "$extra" | tr '\n' ',' | sed 's/,$//')"
    fi
  else
    add_violation "$report_name: dropdown id=plugin options out of order (expected \"repo-wide / other\" then plugins/* alphabetically)"
  fi
}

# ---------------------------------------------------------------------------
# Clause 5: config keys.
# ---------------------------------------------------------------------------
check_config() { # file
  local file="$1"
  if ! grep -qE '^blank_issues_enabled:[[:space:]]*false[[:space:]]*$' "$file"; then
    add_violation "config.yml: must set blank_issues_enabled: false"
  fi
  if grep -qE '^contact_links:' "$file"; then
    add_violation "config.yml: must not declare a contact_links key"
  fi
}

# ---------------------------------------------------------------------------
# Run clauses 3-5 against whichever files exist.
# ---------------------------------------------------------------------------
if [ "$have_feature" -eq 1 ]; then
  check_labels "$FEATURE" "feature" "feature.yml"
  check_dropdown "$FEATURE" "feature.yml"
fi
if [ "$have_bug" -eq 1 ]; then
  check_labels "$BUG" "bug" "bug.yml"
  check_dropdown "$BUG" "bug.yml"
fi
if [ "$have_config" -eq 1 ]; then
  check_config "$CONFIG"
fi

if [ "${#VIOLATIONS[@]}" -eq 0 ]; then
  echo "issue-template-lint: OK"
  exit 0
fi

for v in "${VIOLATIONS[@]}"; do
  echo "$v" >&2
done
exit 1
