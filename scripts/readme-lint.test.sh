#!/usr/bin/env bash
# readme-lint.test.sh — contract tests for scripts/readme-lint.sh (B01
# readme-conformance-lint, plan 002-readme-conformance).
#
# Black-box only: builds fixture trees under mktemp -d (plugins/<name>/
# README.md) and invokes scripts/readme-lint.sh by absolute path with the
# fixture directory as cwd, asserting on exit code and stdout/stderr —
# never on the script's internals. Report-line assertions look for the
# plugin name plus PASS/FAIL plus (for FAIL) the violated heading's plain
# text co-occurring on one line, without pinning down the exact sentence,
# since the contract specifies content, not wording.
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
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
