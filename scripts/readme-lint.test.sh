#!/usr/bin/env bash
# readme-lint.test.sh — contract tests for scripts/readme-lint.sh:
#   - B01 readme-conformance-lint (plan 002-readme-conformance)
#   - B06 root-readme-version-lint (plan 001-update-flow-for-users), the
#     root README.md Plugins-table-vs-marketplace-vs-plugin.json check
#     appended after the B01 checks.
#
# Black-box only: builds fixture trees under mktemp -d (plugins/<name>/
# README.md, plus for B06: root README.md, .claude-plugin/marketplace.json,
# plugins/<name>/.claude-plugin/plugin.json) and invokes
# scripts/readme-lint.sh by absolute path with the fixture directory as cwd,
# asserting on exit code and stdout/stderr — never on the script's
# internals. Report-line assertions look for the plugin name plus PASS/FAIL
# plus (for FAIL) the violated heading's plain text co-occurring on one
# line, without pinning down the exact sentence, since the contract
# specifies content, not wording.
#
# Mirrors the PASS/FAIL harness style of
# plugins/landing/scripts/landing-docs.test.sh.
#
# Run: bash scripts/readme-lint.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/readme-lint.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: script under test not found at $SCRIPT" >&2
  exit 1
fi

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# Cleanup registry for mktemp fixture trees (command substitution forks a
# subshell, so a file-based manifest is needed to survive it).
# ---------------------------------------------------------------------------
CLEANUP_MANIFEST="$(mktemp)"
track_tmp() { printf '%s\n' "$1" >> "$CLEANUP_MANIFEST"; }
cleanup() {
  if [ -f "$CLEANUP_MANIFEST" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] && [ -e "$d" ] && rm -rf -- "$d"
    done < "$CLEANUP_MANIFEST"
    rm -f -- "$CLEANUP_MANIFEST"
  fi
}
trap cleanup EXIT

new_fixture() { # -> prints fixture root path, with plugins/ pre-created
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  mkdir -p "$d/plugins"
  printf '%s' "$d"
}

new_fixture_no_plugins_dir() { # -> prints fixture root path, WITHOUT plugins/
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  printf '%s' "$d"
}

write_readme() { # <fixture_root> <plugin_name> <content>
  local root="$1" name="$2" content="$3"
  mkdir -p "$root/plugins/$name"
  printf '%s' "$content" > "$root/plugins/$name/README.md"
}

# ---------------------------------------------------------------------------
# Invocation helper.
# ---------------------------------------------------------------------------
RUN_OUT=""
RUN_ERR=""
RUN_EXIT=0

run_lint() { # <fixture_root>
  local fixture="$1"
  local out err
  out="$(mktemp)"; err="$(mktemp)"
  ( cd "$fixture" && bash "$SCRIPT" >"$out" 2>"$err" )
  RUN_EXIT=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  rm -f "$out" "$err"
}

# ---------------------------------------------------------------------------
# Assertion helpers over RUN_OUT / RUN_ERR text blobs.
# ---------------------------------------------------------------------------
line_count() { # text -> number of non-empty-file lines (0 for empty string)
  [ -z "$1" ] && { echo 0; return; }
  printf '%s\n' "$1" | grep -c ''
}

# yes if some single line of $1 contains every one of the remaining needles
line_has_all() { # text needle...
  local text="$1"; shift
  local line ok n
  while IFS= read -r line; do
    ok=1
    for n in "$@"; do
      case "$line" in *"$n"*) ;; *) ok=0; break ;; esac
    done
    [ "$ok" -eq 1 ] && { echo yes; return; }
  done <<< "$text"
  echo no
}

# yes if some single line contains $2 (status) and at least one of the
# remaining needles — used where the exact violation phrasing is ambiguous
# but the contract guarantees SOME identifying heading name is present.
line_has_status_and_any() { # text status needle...
  local text="$1" status="$2"; shift 2
  local line n
  while IFS= read -r line; do
    case "$line" in *"$status"*) ;; *) continue ;; esac
    for n in "$@"; do
      case "$line" in *"$n"*) echo yes; return ;; esac
    done
  done <<< "$text"
  echo no
}

contains() { # text needle -> yes/no
  case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac
}

tree_snapshot() { # root -> sorted "relpath  sha256" lines
  local root="$1"
  ( cd "$root" && find . -type f -exec sha256sum {} + ) | sort
}

# ---------------------------------------------------------------------------
# Template README content: the 6 required headings, exact text, exact
# order, per the locked template (plugins/PLUGIN_README_TEMPLATE.md).
# ---------------------------------------------------------------------------
H_START="## Getting started"
H_EXPECT="## What to expect"
H_WORKFLOWS="## Common workflows"
H_COMMANDS="## Commands"
H_RELATIONSHIPS="## Relationships to other plugins"
H_UNINSTALL="## Uninstalling"
REQUIRED=("$H_START" "$H_EXPECT" "$H_WORKFLOWS" "$H_COMMANDS" "$H_RELATIONSHIPS" "$H_UNINSTALL")
REQUIRED_LABELS=("Getting started" "What to expect" "Common workflows" "Commands" "Relationships to other plugins" "Uninstalling")

gen_readme() { # heading-lines... -> doc text on stdout
  local h
  for h in "$@"; do
    printf '%s\n\nBody text.\n\n' "$h"
  done
}

VALID_README="$(gen_readme "${REQUIRED[@]}")"

# ===========================================================================
# 1. Fully conformant README: PASS, exit 0.
# ===========================================================================
f="$(new_fixture)"
write_readme "$f" "alpha" "$VALID_README"
run_lint "$f"
check "conformant README: exit 0" "$RUN_EXIT" "0"
check "conformant README: reports PASS for alpha" \
  "$(line_has_all "$RUN_OUT" "alpha" "PASS")" "yes"

# ===========================================================================
# 2-7. Each required heading missing, one at a time: FAIL naming it.
# ===========================================================================
for i in "${!REQUIRED[@]}"; do
  subset=()
  for j in "${!REQUIRED[@]}"; do
    [ "$j" -eq "$i" ] && continue
    subset+=("${REQUIRED[$j]}")
  done
  content="$(gen_readme "${subset[@]}")"
  f="$(new_fixture)"
  write_readme "$f" "missing$i" "$content"
  run_lint "$f"
  check "missing '${REQUIRED_LABELS[$i]}': exit 1" "$RUN_EXIT" "1"
  check "missing '${REQUIRED_LABELS[$i]}': FAIL names it" \
    "$(line_has_all "$RUN_OUT" "missing$i" "FAIL" "${REQUIRED_LABELS[$i]}")" "yes"
done

# ===========================================================================
# 8. Required headings present but in wrong order: FAIL naming the first
#    out-of-order heading. (First two headings swapped; exact algorithm for
#    "which one gets named" is not specified by the contract, so this
#    accepts either of the two involved headings.)
# ===========================================================================
content="$(gen_readme "${REQUIRED[1]}" "${REQUIRED[0]}" "${REQUIRED[2]}" "${REQUIRED[3]}" "${REQUIRED[4]}" "${REQUIRED[5]}")"
f="$(new_fixture)"
write_readme "$f" "wrongorder" "$content"
run_lint "$f"
check "wrong order: exit 1" "$RUN_EXIT" "1"
check "wrong order: FAIL for wrongorder" \
  "$(line_has_all "$RUN_OUT" "wrongorder" "FAIL")" "yes"
check "wrong order: names one of the swapped headings" \
  "$(line_has_status_and_any "$RUN_OUT" "FAIL" "Getting started" "What to expect")" "yes"

# ===========================================================================
# 9. Duplicate required heading: FAIL.
# ===========================================================================
content="$(gen_readme "${REQUIRED[0]}" "${REQUIRED[@]}")"
f="$(new_fixture)"
write_readme "$f" "dupheading" "$content"
run_lint "$f"
check "duplicate heading: exit 1" "$RUN_EXIT" "1"
check "duplicate heading: FAIL names 'Getting started'" \
  "$(line_has_all "$RUN_OUT" "dupheading" "FAIL" "Getting started")" "yes"

# ===========================================================================
# 10. Case variation in a required heading: FAIL (exact match required).
# ===========================================================================
content="$(gen_readme "## Getting Started" "${REQUIRED[1]}" "${REQUIRED[2]}" "${REQUIRED[3]}" "${REQUIRED[4]}" "${REQUIRED[5]}")"
f="$(new_fixture)"
write_readme "$f" "casevariant" "$content"
run_lint "$f"
check "case-variant heading: exit 1" "$RUN_EXIT" "1"
check "case-variant heading: FAIL for casevariant" \
  "$(line_has_all "$RUN_OUT" "casevariant" "FAIL")" "yes"

# ===========================================================================
# 11. Trailing whitespace in a required heading: FAIL (exact match
#     required). Built via concatenation (not a literal trailing space at
#     end of a source line) so the fixture text is unambiguous.
# ===========================================================================
H_START_TRAILING="${REQUIRED[0]} "
content="$(gen_readme "$H_START_TRAILING" "${REQUIRED[1]}" "${REQUIRED[2]}" "${REQUIRED[3]}" "${REQUIRED[4]}" "${REQUIRED[5]}")"
f="$(new_fixture)"
write_readme "$f" "trailingws" "$content"
run_lint "$f"
check "trailing-whitespace heading: exit 1" "$RUN_EXIT" "1"
check "trailing-whitespace heading: FAIL for trailingws" \
  "$(line_has_all "$RUN_OUT" "trailingws" "FAIL")" "yes"

# ===========================================================================
# 12. Extra H2 before "## Commands": FAIL naming the misplaced section.
# ===========================================================================
content="$(gen_readme "${REQUIRED[0]}" "## Bonus Section" "${REQUIRED[1]}" "${REQUIRED[2]}" "${REQUIRED[3]}" "${REQUIRED[4]}" "${REQUIRED[5]}")"
f="$(new_fixture)"
write_readme "$f" "extrabefore" "$content"
run_lint "$f"
check "extra H2 before Commands: exit 1" "$RUN_EXIT" "1"
check "extra H2 before Commands: FAIL names 'Bonus Section'" \
  "$(line_has_all "$RUN_OUT" "extrabefore" "FAIL" "Bonus Section")" "yes"

# ===========================================================================
# 13. Extra H2 between "## Commands" and "## Relationships to other
#     plugins": allowed -> PASS.
# ===========================================================================
content="$(gen_readme "${REQUIRED[0]}" "${REQUIRED[1]}" "${REQUIRED[2]}" "${REQUIRED[3]}" "## Extra Notes" "${REQUIRED[4]}" "${REQUIRED[5]}")"
f="$(new_fixture)"
write_readme "$f" "extraallowed" "$content"
run_lint "$f"
check "extra H2 between Commands/Relationships: exit 0" "$RUN_EXIT" "0"
check "extra H2 between Commands/Relationships: PASS for extraallowed" \
  "$(line_has_all "$RUN_OUT" "extraallowed" "PASS")" "yes"

# ===========================================================================
# 14. Extra H2 after "## Relationships to other plugins": FAIL naming the
#     misplaced section.
# ===========================================================================
content="$(gen_readme "${REQUIRED[0]}" "${REQUIRED[1]}" "${REQUIRED[2]}" "${REQUIRED[3]}" "${REQUIRED[4]}" "## Trailing Extra" "${REQUIRED[5]}")"
f="$(new_fixture)"
write_readme "$f" "extraafter" "$content"
run_lint "$f"
check "extra H2 after Relationships: exit 1" "$RUN_EXIT" "1"
check "extra H2 after Relationships: FAIL names 'Trailing Extra'" \
  "$(line_has_all "$RUN_OUT" "extraafter" "FAIL" "Trailing Extra")" "yes"

# ===========================================================================
# 15. "## Tests" in the allowed slot (between Commands and Relationships):
#     PASS.
# ===========================================================================
content="$(gen_readme "${REQUIRED[0]}" "${REQUIRED[1]}" "${REQUIRED[2]}" "${REQUIRED[3]}" "## Tests" "${REQUIRED[4]}" "${REQUIRED[5]}")"
f="$(new_fixture)"
write_readme "$f" "testsslot" "$content"
run_lint "$f"
check "## Tests in allowed slot: exit 0" "$RUN_EXIT" "0"
check "## Tests in allowed slot: PASS for testsslot" \
  "$(line_has_all "$RUN_OUT" "testsslot" "PASS")" "yes"

# ===========================================================================
# 16. H2-lookalikes inside a fenced code block and inside a multi-line HTML
#     comment must NOT count as real H2s. Both decoys are placed so that,
#     if wrongly counted, they would break conformance (comment decoy
#     duplicates "Getting started" before the real heading; fenced decoy
#     inserts an extra H2 in a disallowed slot) — so a PASS here is a
#     meaningful confirmation of the exclusion, not a vacuous one.
# ===========================================================================
lookalike_content=$'<!--\n## Getting started\n-->\n\n## Getting started\n\n```bash\n## Fake Command Heading\necho hi\n```\n\nBody text.\n\n## What to expect\n\nBody text.\n\n## Common workflows\n\nBody text.\n\n## Commands\n\nBody text.\n\n## Relationships to other plugins\n\nBody text.\n\n## Uninstalling\n\nBody text.\n'
f="$(new_fixture)"
write_readme "$f" "lookalikes" "$lookalike_content"
run_lint "$f"
check "H2-lookalikes in fence/comment ignored: exit 0" "$RUN_EXIT" "0"
check "H2-lookalikes in fence/comment ignored: PASS for lookalikes" \
  "$(line_has_all "$RUN_OUT" "lookalikes" "PASS")" "yes"

# ===========================================================================
# 17. README with no H2s at all: FAIL (all required headings missing).
# ===========================================================================
noh2_content=$'This plugin has no structured headings at all.\n\nJust prose describing what it does, with no ## lines anywhere in the body.\n'
f="$(new_fixture)"
write_readme "$f" "noheadings" "$noh2_content"
run_lint "$f"
check "README with no H2s: exit 1" "$RUN_EXIT" "1"
check "README with no H2s: FAIL for noheadings" \
  "$(line_has_all "$RUN_OUT" "noheadings" "FAIL")" "yes"
check "README with no H2s: names first missing 'Getting started'" \
  "$(line_has_all "$RUN_OUT" "noheadings" "FAIL" "Getting started")" "yes"

# ===========================================================================
# 18. Plugin directory without a README.md: FAIL.
# ===========================================================================
f="$(new_fixture)"
mkdir -p "$f/plugins/noreadme"
printf 'not a readme\n' > "$f/plugins/noreadme/NOTES.txt"
run_lint "$f"
check "plugin dir without README.md: exit 1" "$RUN_EXIT" "1"
check "plugin dir without README.md: FAIL for noreadme" \
  "$(line_has_all "$RUN_OUT" "noreadme" "FAIL")" "yes"

# ===========================================================================
# 19. Missing plugins/ directory entirely: exit 2, message to stderr.
# ===========================================================================
f="$(new_fixture_no_plugins_dir)"
run_lint "$f"
check "missing plugins/ dir: exit 2" "$RUN_EXIT" "2"
check "missing plugins/ dir: stderr non-empty" \
  "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 20. plugins/PLUGIN_README_TEMPLATE.md is exempt from linting, regardless
#     of its own content (deliberately non-conformant here to prove it is
#     never linted, not merely accidentally conformant).
# ===========================================================================
f="$(new_fixture)"
printf '# {plugin-name}\n\nPlaceholder template body, not a real plugin.\n' > "$f/plugins/PLUGIN_README_TEMPLATE.md"
write_readme "$f" "beta" "$VALID_README"
run_lint "$f"
check "template file exempt: exit 0" "$RUN_EXIT" "0"
check "template file exempt: PASS for beta" \
  "$(line_has_all "$RUN_OUT" "beta" "PASS")" "yes"
check "template file exempt: not mentioned in report" \
  "$(contains "$RUN_OUT" "TEMPLATE")" "no"
check "template file exempt: exactly one report line" \
  "$(line_count "$RUN_OUT")" "1"

# ===========================================================================
# 21. Report shape: exactly one PASS/FAIL line per plugin.
# ===========================================================================
f="$(new_fixture)"
write_readme "$f" "one" "$VALID_README"
write_readme "$f" "two" "$VALID_README"
missing_commands=()
for j in "${!REQUIRED[@]}"; do
  [ "$j" -eq 3 ] && continue
  missing_commands+=("${REQUIRED[$j]}")
done
write_readme "$f" "three" "$(gen_readme "${missing_commands[@]}")"
run_lint "$f"
check "multi-plugin report: exit 1 (one plugin fails)" "$RUN_EXIT" "1"
check "multi-plugin report: three lines total" "$(line_count "$RUN_OUT")" "3"
check "multi-plugin report: 'one' reported PASS" \
  "$(line_has_all "$RUN_OUT" "one" "PASS")" "yes"
check "multi-plugin report: 'two' reported PASS" \
  "$(line_has_all "$RUN_OUT" "two" "PASS")" "yes"
check "multi-plugin report: 'three' reported FAIL" \
  "$(line_has_all "$RUN_OUT" "three" "FAIL")" "yes"

# ===========================================================================
# 22. Read-only invariant: the fixture tree is byte-identical before/after.
# ===========================================================================
f="$(new_fixture)"
write_readme "$f" "ro1" "$VALID_README"
write_readme "$f" "ro2" "$(gen_readme "${REQUIRED[0]}")"
before="$(tree_snapshot "$f")"
run_lint "$f"
after="$(tree_snapshot "$f")"
check "read-only invariant: fixture tree unchanged" "$after" "$before"

# ===========================================================================
# 23. Determinism: two runs over the same tree produce identical output and
#     exit code.
# ===========================================================================
f="$(new_fixture)"
write_readme "$f" "det1" "$VALID_README"
write_readme "$f" "det2" "$(gen_readme "${REQUIRED[0]}" "${REQUIRED[1]}")"
run_lint "$f"; out1="$RUN_OUT"; exit1="$RUN_EXIT"
run_lint "$f"; out2="$RUN_OUT"; exit2="$RUN_EXIT"
check "determinism: same exit code across runs" "$exit2" "$exit1"
check "determinism: same stdout across runs" "$out2" "$out1"

# ===========================================================================
# B06 root-readme-version-lint (plan 001-update-flow-for-users): extension
# fixtures and helpers. Every marketplace plugin must have exactly one root
# README.md table row with status "✅ vX.Y.Z" matching that plugin's
# plugin.json version; "planned" rows are exempt; a non-planned row for a
# plugin absent from the marketplace is a stale-row FAIL. Report lines:
# "PASS  root-table <plugin>" / "FAIL  root-table <plugin> -> <reason>",
# appended after the existing per-plugin README lines above.
# ===========================================================================

write_marketplace() { # <fixture_root> <plugin_name>... -> writes
                       # .claude-plugin/marketplace.json listing each name
  local root="$1"; shift
  mkdir -p "$root/.claude-plugin"
  {
    printf '{\n'
    printf '  "name": "test",\n'
    printf '  "description": "test marketplace",\n'
    printf '  "owner": {"name": "Test", "email": "test@example.com"},\n'
    printf '  "plugins": [\n'
    local first=1 name
    for name in "$@"; do
      if [ "$first" -eq 1 ]; then first=0; else printf ',\n'; fi
      printf '    {"name": "%s", "source": "./plugins/%s", "description": "test plugin"}' "$name" "$name"
    done
    printf '\n  ]\n'
    printf '}\n'
  } > "$root/.claude-plugin/marketplace.json"
}

write_plugin_json() { # <fixture_root> <name> <version>
  local root="$1" name="$2" version="$3"
  mkdir -p "$root/plugins/$name/.claude-plugin"
  {
    printf '{\n'
    printf '  "name": "%s",\n' "$name"
    printf '  "description": "test plugin",\n'
    printf '  "version": "%s",\n' "$version"
    printf '  "author": {"name": "Test", "email": "test@example.com"}\n'
    printf '}\n'
  } > "$root/plugins/$name/.claude-plugin/plugin.json"
}

write_root_readme() { # <fixture_root> <rows_text> -> single-table README.md
  local root="$1" rows="$2"
  {
    printf '# Test Marketplace\n\n## Plugins\n\n'
    printf '| Plugin | Status | What it does |\n'
    printf '|--------|--------|--------------|\n'
    printf '%s\n' "$rows"
  } > "$root/README.md"
}

gen_table_row() { # <name> <status> -> one linked-name row line
  printf '| [%s](plugins/%s/) | %s | test plugin |\n' "$1" "$1" "$2"
}

gen_table_row_bare() { # <name> <status> -> one bare-name row line
  printf '| %s | %s | test plugin |\n' "$1" "$2"
}

write_plugin_readme_conformant() { # <fixture_root> <name> -> keeps the
                                    # existing per-plugin check green so
                                    # root-table assertions aren't confounded
  write_readme "$1" "$2" "$VALID_README"
}

first_line_index() { # text needle... -> 1-based index of first line
                      # containing every needle, or 0 if none does
  local text="$1"; shift
  local i=0 line ok n
  while IFS= read -r line; do
    i=$((i + 1))
    ok=1
    for n in "$@"; do
      case "$line" in *"$n"*) ;; *) ok=0; break ;; esac
    done
    [ "$ok" -eq 1 ] && { echo "$i"; return; }
  done <<< "$text"
  echo 0
}

root_table_trailing() { # text -> yes/no: at least one "root-table" line
                         # exists, preceded by >=1 non-"root-table" line, and
                         # every line from the first "root-table" line to the
                         # end also contains "root-table" (contiguous tail)
  local text="$1" first_rt i=0 line
  first_rt="$(first_line_index "$text" "root-table")"
  if [ "$first_rt" -le 1 ]; then echo no; return; fi
  while IFS= read -r line; do
    i=$((i + 1))
    if [ "$i" -ge "$first_rt" ]; then
      case "$line" in *"root-table"*) ;; *) echo no; return ;; esac
    fi
  done <<< "$text"
  echo yes
}

# ===========================================================================
# 24. All plugins agree (root table, marketplace, plugin.json all in sync):
#     exit 0, one PASS root-table line per plugin, appended after the
#     existing per-plugin PASS lines.
# ===========================================================================
f="$(new_fixture)"
write_plugin_readme_conformant "$f" "alpha1"
write_plugin_readme_conformant "$f" "alpha2"
write_plugin_readme_conformant "$f" "alpha3"
write_plugin_json "$f" "alpha1" "1.0.0"
write_plugin_json "$f" "alpha2" "2.3.4"
write_plugin_json "$f" "alpha3" "0.0.1"
write_marketplace "$f" "alpha1" "alpha2" "alpha3"
rows="$(gen_table_row "alpha1" "✅ v1.0.0"
gen_table_row "alpha2" "✅ v2.3.4"
gen_table_row "alpha3" "✅ v0.0.1")"
write_root_readme "$f" "$rows"
run_lint "$f"
check "root-table all-agreeing: exit 0" "$RUN_EXIT" "0"
check "root-table all-agreeing: PASS root-table alpha1" \
  "$(line_has_all "$RUN_OUT" "root-table" "alpha1" "PASS")" "yes"
check "root-table all-agreeing: PASS root-table alpha2" \
  "$(line_has_all "$RUN_OUT" "root-table" "alpha2" "PASS")" "yes"
check "root-table all-agreeing: PASS root-table alpha3" \
  "$(line_has_all "$RUN_OUT" "root-table" "alpha3" "PASS")" "yes"
check "root-table all-agreeing: root-table lines appended after per-plugin lines" \
  "$(root_table_trailing "$RUN_OUT")" "yes"

# ===========================================================================
# 25. Marketplace plugin missing its root table row entirely: FAIL naming it
#     (other agreeing plugins still PASS).
# ===========================================================================
f="$(new_fixture)"
write_plugin_readme_conformant "$f" "beta1"
write_plugin_readme_conformant "$f" "beta2"
write_plugin_json "$f" "beta1" "1.0.0"
write_plugin_json "$f" "beta2" "1.0.0"
write_marketplace "$f" "beta1" "beta2"
rows="$(gen_table_row "beta1" "✅ v1.0.0")"
write_root_readme "$f" "$rows"
run_lint "$f"
check "root-table missing row: exit 1" "$RUN_EXIT" "1"
check "root-table missing row: FAIL root-table beta2" \
  "$(line_has_all "$RUN_OUT" "root-table" "beta2" "FAIL")" "yes"
check "root-table missing row: beta1 still PASS root-table" \
  "$(line_has_all "$RUN_OUT" "root-table" "beta1" "PASS")" "yes"

# ===========================================================================
# 26. Duplicate root table row for the same plugin: FAIL.
# ===========================================================================
f="$(new_fixture)"
write_plugin_readme_conformant "$f" "gamma1"
write_plugin_json "$f" "gamma1" "1.0.0"
write_marketplace "$f" "gamma1"
rows="$(gen_table_row "gamma1" "✅ v1.0.0"
gen_table_row "gamma1" "✅ v1.0.0")"
write_root_readme "$f" "$rows"
run_lint "$f"
check "root-table duplicate row: exit 1" "$RUN_EXIT" "1"
check "root-table duplicate row: FAIL root-table gamma1" \
  "$(line_has_all "$RUN_OUT" "root-table" "gamma1" "FAIL")" "yes"

# ===========================================================================
# 27. Version mismatch between plugin.json and the row's status cell: FAIL
#     naming both the expected and found versions.
# ===========================================================================
f="$(new_fixture)"
write_plugin_readme_conformant "$f" "delta1"
write_plugin_json "$f" "delta1" "1.2.3"
write_marketplace "$f" "delta1"
rows="$(gen_table_row "delta1" "✅ v1.2.4")"
write_root_readme "$f" "$rows"
run_lint "$f"
check "root-table version mismatch: exit 1" "$RUN_EXIT" "1"
check "root-table version mismatch: FAIL root-table delta1" \
  "$(line_has_all "$RUN_OUT" "root-table" "delta1" "FAIL")" "yes"
check "root-table version mismatch: names expected version 1.2.3" \
  "$(line_has_all "$RUN_OUT" "root-table" "delta1" "1.2.3")" "yes"
check "root-table version mismatch: names found version 1.2.4" \
  "$(line_has_all "$RUN_OUT" "root-table" "delta1" "1.2.4")" "yes"

# ===========================================================================
# 28. Malformed status cell (missing the "v" prefix): FAIL.
# ===========================================================================
f="$(new_fixture)"
write_plugin_readme_conformant "$f" "zeta1"
write_plugin_json "$f" "zeta1" "0.1.0"
write_marketplace "$f" "zeta1"
rows="$(gen_table_row "zeta1" "✅ 0.1.0")"
write_root_readme "$f" "$rows"
run_lint "$f"
check "root-table malformed status cell: exit 1" "$RUN_EXIT" "1"
check "root-table malformed status cell: FAIL root-table zeta1" \
  "$(line_has_all "$RUN_OUT" "root-table" "zeta1" "FAIL")" "yes"

# ===========================================================================
# 29. Whitespace-padded status cell still passes once trimmed.
# ===========================================================================
f="$(new_fixture)"
write_plugin_readme_conformant "$f" "eta1"
write_plugin_json "$f" "eta1" "1.0.0"
write_marketplace "$f" "eta1"
rows="$(gen_table_row "eta1" "   ✅ v1.0.0   ")"
write_root_readme "$f" "$rows"
run_lint "$f"
check "root-table whitespace-padded cell: exit 0" "$RUN_EXIT" "0"
check "root-table whitespace-padded cell: PASS root-table eta1" \
  "$(line_has_all "$RUN_OUT" "root-table" "eta1" "PASS")" "yes"

# ===========================================================================
# 30. "planned" row for a plugin absent from the marketplace is exempt: no
#     FAIL for it, and the agreeing marketplace plugin still PASSes.
# ===========================================================================
f="$(new_fixture)"
write_plugin_readme_conformant "$f" "iota1"
write_plugin_json "$f" "iota1" "1.0.0"
write_marketplace "$f" "iota1"
rows="$(gen_table_row "iota1" "✅ v1.0.0"
gen_table_row_bare "planned-only-plugin" "planned")"
write_root_readme "$f" "$rows"
run_lint "$f"
check "root-table planned row exempt: exit 0" "$RUN_EXIT" "0"
check "root-table planned row exempt: no FAIL for planned-only-plugin" \
  "$(line_has_all "$RUN_OUT" "planned-only-plugin" "FAIL")" "no"
check "root-table planned row exempt: iota1 PASS root-table" \
  "$(line_has_all "$RUN_OUT" "root-table" "iota1" "PASS")" "yes"

# ===========================================================================
# 31. Stale row: a non-planned row names a plugin absent from the
#     marketplace -> FAIL for it (agreeing marketplace plugin still PASSes).
# ===========================================================================
f="$(new_fixture)"
write_plugin_readme_conformant "$f" "kappa1"
write_plugin_json "$f" "kappa1" "1.0.0"
write_marketplace "$f" "kappa1"
rows="$(gen_table_row "kappa1" "✅ v1.0.0"
gen_table_row "stalezap" "✅ v1.0.0")"
write_root_readme "$f" "$rows"
run_lint "$f"
check "root-table stale row: exit 1" "$RUN_EXIT" "1"
check "root-table stale row: FAIL for stalezap" \
  "$(line_has_all "$RUN_OUT" "stalezap" "FAIL")" "yes"
check "root-table stale row: kappa1 still PASS root-table" \
  "$(line_has_all "$RUN_OUT" "root-table" "kappa1" "PASS")" "yes"

# ===========================================================================
# 32. A second GFM table further down the README is ignored: a row that
#     exists only in the second table does not rescue a plugin missing from
#     the first (and only inspected) table.
# ===========================================================================
f="$(new_fixture)"
write_plugin_readme_conformant "$f" "lambda1"
write_plugin_json "$f" "lambda1" "1.0.0"
write_marketplace "$f" "lambda1"
{
  printf '# Test\n\n## Plugins\n\n'
  printf '| Plugin | Status | What it does |\n'
  printf '|--------|--------|--------------|\n'
  printf '| other-planned | planned | x |\n'
  printf '\n## Second Table (must be ignored)\n\n'
  printf '| Plugin | Status | What it does |\n'
  printf '|--------|--------|--------------|\n'
  gen_table_row "lambda1" "✅ v1.0.0"
} > "$f/README.md"
run_lint "$f"
check "root-table second table ignored: exit 1" "$RUN_EXIT" "1"
check "root-table second table ignored: FAIL root-table lambda1" \
  "$(line_has_all "$RUN_OUT" "root-table" "lambda1" "FAIL")" "yes"

# ===========================================================================
# 33. Marketplace plugin whose directory lacks plugin.json: FAIL (unreadable
#     expected version), independent of what the row's status cell says.
# ===========================================================================
f="$(new_fixture)"
write_plugin_readme_conformant "$f" "mu1"
write_marketplace "$f" "mu1"
rows="$(gen_table_row "mu1" "✅ v9.9.9")"
write_root_readme "$f" "$rows"
run_lint "$f"
check "root-table missing plugin.json: exit 1" "$RUN_EXIT" "1"
check "root-table missing plugin.json: FAIL root-table mu1" \
  "$(line_has_all "$RUN_OUT" "root-table" "mu1" "FAIL")" "yes"

# ===========================================================================
# 34. Real-repo smoke check: running readme-lint.sh against the actual repo
#     root must, once the extension exists, report a PASS root-table line
#     for every real marketplace plugin (read live via jq, not hardcoded)
#     and keep exiting 0, with the root-table block appended after the
#     existing per-plugin lines. Today, before the extension is
#     implemented, the script prints no root-table lines at all, so every
#     "PASS root-table <plugin>" and the trailing-block check below are RED
#     — the extension simply doesn't exist yet, not a repo-data problem.
# ===========================================================================
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
run_lint "$REPO_ROOT"
check "root-table real repo: exit 0" "$RUN_EXIT" "0"
mapfile -t real_plugin_names < <(jq -r '.plugins[].name' "$REPO_ROOT/.claude-plugin/marketplace.json" | sort)
for name in "${real_plugin_names[@]}"; do
  check "root-table real repo: PASS root-table $name" \
    "$(line_has_all "$RUN_OUT" "root-table" "$name" "PASS")" "yes"
done
check "root-table real repo: root-table lines appended after per-plugin lines" \
  "$(root_table_trailing "$RUN_OUT")" "yes"

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
