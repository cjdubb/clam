#!/bin/bash
# issue-template-lint.test.sh — contract tests for scripts/issue-template-lint.sh
# (B05 issue-template-lint, plan 001-repo-issue-template).
#
# Black-box only: builds fixture trees under mktemp -d (a fake plugins/ with
# a few plugin dirs, a fake .github/ISSUE_TEMPLATE/ with template files),
# cd's into the fixture, and invokes scripts/issue-template-lint.sh by
# absolute path — never against this worktree's real .github/ or plugins/,
# except for one read-only integration check against the real repo root
# (see the bottom of this file).
#
# Message-content assertions look for filenames/identifiers that must
# plausibly appear in a useful violation report, without pinning down exact
# wording the contract doesn't specify. The two contract-guaranteed exact
# strings ("issue-template-lint: OK" and "SKIP yaml-parse (no parser)") are
# matched verbatim.
#
# Run: bash scripts/issue-template-lint.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/issue-template-lint.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# ---------------------------------------------------------------------------
# Fixture builders. Default plugin set is alpha/beta/gamma (already
# alphabetical), self-contained and independent of the real repo's plugin
# list.
# ---------------------------------------------------------------------------
new_fixture() { # -> fixture root with plugins/{alpha,beta,gamma} + .github/ISSUE_TEMPLATE/ (empty)
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  mkdir -p "$d/plugins/alpha" "$d/plugins/beta" "$d/plugins/gamma"
  mkdir -p "$d/.github/ISSUE_TEMPLATE"
  printf '%s' "$d"
}

new_fixture_with_stray_file() { # -> like new_fixture, plus a non-directory entry under plugins/
  local d
  d="$(new_fixture)"
  printf 'not a plugin\n' > "$d/plugins/zzz-not-a-plugin.md"
  printf '%s' "$d"
}

new_fixture_empty_plugins() { # -> plugins/ exists but has no entries
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  mkdir -p "$d/plugins"
  mkdir -p "$d/.github/ISSUE_TEMPLATE"
  printf '%s' "$d"
}

new_fixture_no_plugins_dir() { # -> no plugins/ at all
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  mkdir -p "$d/.github/ISSUE_TEMPLATE"
  printf '%s' "$d"
}

new_fixture_no_issue_template_dir() { # -> no .github/ISSUE_TEMPLATE at all
  local d
  d="$(mktemp -d)"
  track_tmp "$d"
  mkdir -p "$d/plugins/alpha" "$d/plugins/beta" "$d/plugins/gamma"
  printf '%s' "$d"
}

gen_options_block() { # plugin-names... -> yaml "options:" list items (8-space indent), "repo-wide / other" first
  printf '        - "repo-wide / other"\n'
  local p
  for p in "$@"; do
    printf '        - %s\n' "$p"
  done
}

DEFAULT_OPTIONS="$(gen_options_block alpha beta gamma)"
EMPTY_OPTIONS="$(gen_options_block)"
MISSING_ONE_OPTIONS="$(gen_options_block alpha gamma)"
EXTRA_OPTIONS="$(gen_options_block alpha beta gamma delta)"
DUPLICATE_OPTIONS="$(gen_options_block alpha alpha beta gamma)"
MISORDERED_OPTIONS="$(gen_options_block beta alpha gamma)"
NO_REPO_WIDE_OPTIONS=$'        - alpha\n        - beta\n        - gamma\n'

DEFAULT_LABELS_FEATURE=$'labels:\n  - feature\n'
DEFAULT_LABELS_BUG=$'labels:\n  - bug\n'

write_feature() { # <root> <labels_section> <field_id> <options_block> [name_line]
  local root="$1" labels_section="$2" field_id="$3" options_block="$4"
  local name_line="${5:-name: \"Feature request\"}"
  cat > "$root/.github/ISSUE_TEMPLATE/feature.yml" <<EOF
$name_line
description: "Propose a new feature or enhancement for clam."
title: "feat: "
$labels_section
body:
  - type: dropdown
    id: $field_id
    attributes:
      label: "Affected plugin"
      options:
$options_block
    validations:
      required: true
  - type: textarea
    id: problem
    attributes:
      label: "Problem / motivation"
    validations:
      required: true
  - type: textarea
    id: proposal
    attributes:
      label: "Proposed behavior"
    validations:
      required: true
  - type: textarea
    id: alternatives
    attributes:
      label: "Alternatives considered"
    validations:
      required: false
EOF
}

write_bug() { # <root> <labels_section> <field_id> <options_block>
  local root="$1" labels_section="$2" field_id="$3" options_block="$4"
  cat > "$root/.github/ISSUE_TEMPLATE/bug.yml" <<EOF
name: "Bug report"
description: "Report a bug in clam."
title: "fix: "
$labels_section
body:
  - type: dropdown
    id: $field_id
    attributes:
      label: "Affected plugin"
      options:
$options_block
    validations:
      required: true
  - type: textarea
    id: repro
    attributes:
      label: "Steps to reproduce"
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: "Expected behavior"
    validations:
      required: true
  - type: textarea
    id: actual
    attributes:
      label: "Actual behavior"
    validations:
      required: true
  - type: input
    id: version
    attributes:
      label: "Plugin version"
    validations:
      required: false
  - type: textarea
    id: environment
    attributes:
      label: "Environment"
    validations:
      required: false
EOF
}

write_config() { # <root> <content>
  printf '%s' "$2" > "$1/.github/ISSUE_TEMPLATE/config.yml"
}

DEFAULT_CONFIG=$'blank_issues_enabled: false\n'

write_all_valid() { # <root> [options_block override, applied to BOTH forms]
  local root="$1" options="${2:-$DEFAULT_OPTIONS}"
  write_feature "$root" "$DEFAULT_LABELS_FEATURE" "plugin" "$options"
  write_bug "$root" "$DEFAULT_LABELS_BUG" "plugin" "$options"
  write_config "$root" "$DEFAULT_CONFIG"
}

# ---------------------------------------------------------------------------
# Invocation helpers.
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

# Forces the "no parser available" branch by shadowing python3 on PATH with
# a stub that always fails, regardless of what's really installed. This
# makes the SKIP-branch coverage independent of the host running these
# tests.
run_lint_no_parser() { # <fixture_root>
  local fixture="$1"
  local stubdir out err
  stubdir="$(mktemp -d)"; track_tmp "$stubdir"
  cat > "$stubdir/python3" <<'STUB'
#!/bin/bash
exit 1
STUB
  chmod +x "$stubdir/python3"
  out="$(mktemp)"; err="$(mktemp)"
  ( cd "$fixture" && PATH="$stubdir:$PATH" bash "$SCRIPT" >"$out" 2>"$err" )
  RUN_EXIT=$?
  RUN_OUT="$(cat "$out")"
  RUN_ERR="$(cat "$err")"
  rm -f "$out" "$err"
}

contains() { # text needle -> yes/no
  case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac
}

line_count() { # text -> number of non-empty lines (0 for empty string)
  [ -z "$1" ] && { echo 0; return; }
  printf '%s\n' "$1" | grep -c ''
}

tree_snapshot() { # root -> sorted "relpath  sha256" lines
  local root="$1"
  ( cd "$root" && find . -type f -exec sha256sum {} + ) | sort
}

HAVE_PARSER="$(python3 -c "import yaml" >/dev/null 2>&1 && echo yes || echo no)"

# ===========================================================================
# 1. Baseline conformant fixture: exit 0, exact success string on stdout.
#    (Also implicitly exercises "directories only" via new_fixture using
#    plain plugin dirs with no stray files — see case 21 for the explicit
#    stray-file variant.)
# ===========================================================================
f="$(new_fixture)"; write_all_valid "$f"
run_lint "$f"
check "baseline conformant: exit 0" "$RUN_EXIT" "0"
check "baseline conformant: prints success string" \
  "$(contains "$RUN_OUT" "issue-template-lint: OK")" "yes"

# ===========================================================================
# 2-4. Existence check (clause 1): each of the three required files missing.
# ===========================================================================
f="$(new_fixture)"
write_bug "$f" "$DEFAULT_LABELS_BUG" "plugin" "$DEFAULT_OPTIONS"
write_config "$f" "$DEFAULT_CONFIG"
run_lint "$f"
check "missing feature.yml: exit 1" "$RUN_EXIT" "1"
check "missing feature.yml: names it" "$(contains "$RUN_ERR" "feature.yml")" "yes"

f="$(new_fixture)"
write_feature "$f" "$DEFAULT_LABELS_FEATURE" "plugin" "$DEFAULT_OPTIONS"
write_config "$f" "$DEFAULT_CONFIG"
run_lint "$f"
check "missing bug.yml: exit 1" "$RUN_EXIT" "1"
check "missing bug.yml: names it" "$(contains "$RUN_ERR" "bug.yml")" "yes"

f="$(new_fixture)"
write_feature "$f" "$DEFAULT_LABELS_FEATURE" "plugin" "$DEFAULT_OPTIONS"
write_bug "$f" "$DEFAULT_LABELS_BUG" "plugin" "$DEFAULT_OPTIONS"
run_lint "$f"
check "missing config.yml: exit 1" "$RUN_EXIT" "1"
check "missing config.yml: names it" "$(contains "$RUN_ERR" "config.yml")" "yes"

# ===========================================================================
# 5-6. YAML parse check (clause 2), gated on real parser availability so the
#      "parser present" assertions only run where they can be meaningful.
#      The corruption (unterminated quoted scalar in the name: line) is
#      invalid YAML syntax while every grep-visible structural marker
#      (labels, dropdown id, options) stays intact, isolating the parse
#      failure from the structural checks.
# ===========================================================================
if [ "$HAVE_PARSER" = "yes" ]; then
  f="$(new_fixture)"; write_all_valid "$f"
  write_feature "$f" "$DEFAULT_LABELS_FEATURE" "plugin" "$DEFAULT_OPTIONS" 'name: "Feature request'
  run_lint "$f"
  check "invalid YAML (parser present): exit 1" "$RUN_EXIT" "1"
  check "invalid YAML (parser present): names feature.yml" \
    "$(contains "$RUN_ERR" "feature.yml")" "yes"
else
  echo "NOTE: python3+yaml unavailable in this environment; skipping parser-present assertions for clause 2 (still covered by the forced-no-parser branch below)."
fi

# ===========================================================================
# 7. YAML parse check, parser forced unavailable (via PATH-shadowed stub
#    python3): must SKIP with the exact contract string, not fail solely
#    for lack of a parser, and still validate structurally.
# ===========================================================================
f="$(new_fixture)"; write_all_valid "$f"
run_lint_no_parser "$f"
check "no-parser branch: exit 0 on an otherwise-conformant fixture" "$RUN_EXIT" "0"
check "no-parser branch: prints exact SKIP string" \
  "$(contains "$RUN_ERR" "SKIP yaml-parse (no parser)")" "yes"
check "no-parser branch: still prints success string" \
  "$(contains "$RUN_OUT" "issue-template-lint: OK")" "yes"

# ===========================================================================
# 8-10. Labels check (clause 3): missing, wrong, and extra label, for both
#       feature.yml and bug.yml independently.
# ===========================================================================
f="$(new_fixture)"; write_all_valid "$f"
write_feature "$f" $'labels:\n  - wrong-label\n' "plugin" "$DEFAULT_OPTIONS"
run_lint "$f"
check "feature.yml wrong label: exit 1" "$RUN_EXIT" "1"
check "feature.yml wrong label: names feature.yml" "$(contains "$RUN_ERR" "feature.yml")" "yes"

f="$(new_fixture)"; write_all_valid "$f"
write_feature "$f" $'labels: []\n' "plugin" "$DEFAULT_OPTIONS"
run_lint "$f"
check "feature.yml empty labels: exit 1" "$RUN_EXIT" "1"
check "feature.yml empty labels: names feature.yml" "$(contains "$RUN_ERR" "feature.yml")" "yes"

f="$(new_fixture)"; write_all_valid "$f"
write_feature "$f" $'labels:\n  - feature\n  - extra\n' "plugin" "$DEFAULT_OPTIONS"
run_lint "$f"
check "feature.yml extra label: exit 1" "$RUN_EXIT" "1"
check "feature.yml extra label: names feature.yml" "$(contains "$RUN_ERR" "feature.yml")" "yes"

f="$(new_fixture)"; write_all_valid "$f"
write_bug "$f" $'labels:\n  - wrong-label\n' "plugin" "$DEFAULT_OPTIONS"
run_lint "$f"
check "bug.yml wrong label: exit 1" "$RUN_EXIT" "1"
check "bug.yml wrong label: names bug.yml" "$(contains "$RUN_ERR" "bug.yml")" "yes"

# ===========================================================================
# 11-16. Dropdown sync (clause 4): missing / extra / duplicate / misordered
#        entries, missing "repo-wide / other", and checked independently on
#        both forms.
# ===========================================================================
f="$(new_fixture)"; write_all_valid "$f"
write_feature "$f" "$DEFAULT_LABELS_FEATURE" "plugin" "$MISSING_ONE_OPTIONS"
run_lint "$f"
check "dropdown missing entry: exit 1" "$RUN_EXIT" "1"
check "dropdown missing entry: names feature.yml" "$(contains "$RUN_ERR" "feature.yml")" "yes"
check "dropdown missing entry: names the missing plugin (beta)" "$(contains "$RUN_ERR" "beta")" "yes"

f="$(new_fixture)"; write_all_valid "$f"
write_feature "$f" "$DEFAULT_LABELS_FEATURE" "plugin" "$EXTRA_OPTIONS"
run_lint "$f"
check "dropdown extra entry: exit 1" "$RUN_EXIT" "1"
check "dropdown extra entry: names the extra plugin (delta)" "$(contains "$RUN_ERR" "delta")" "yes"

f="$(new_fixture)"; write_all_valid "$f"
write_feature "$f" "$DEFAULT_LABELS_FEATURE" "plugin" "$DUPLICATE_OPTIONS"
run_lint "$f"
check "dropdown duplicate entry: exit 1" "$RUN_EXIT" "1"
check "dropdown duplicate entry: names the duplicated plugin (alpha)" "$(contains "$RUN_ERR" "alpha")" "yes"

f="$(new_fixture)"; write_all_valid "$f"
write_feature "$f" "$DEFAULT_LABELS_FEATURE" "plugin" "$MISORDERED_OPTIONS"
run_lint "$f"
check "dropdown misordered: exit 1" "$RUN_EXIT" "1"
check "dropdown misordered: names feature.yml" "$(contains "$RUN_ERR" "feature.yml")" "yes"

f="$(new_fixture)"; write_all_valid "$f"
write_feature "$f" "$DEFAULT_LABELS_FEATURE" "plugin" "$NO_REPO_WIDE_OPTIONS"
run_lint "$f"
check "dropdown missing repo-wide/other: exit 1" "$RUN_EXIT" "1"
check "dropdown missing repo-wide/other: names feature.yml" "$(contains "$RUN_ERR" "feature.yml")" "yes"

f="$(new_fixture)"; write_all_valid "$f"
write_bug "$f" "$DEFAULT_LABELS_BUG" "plugin" "$MISSING_ONE_OPTIONS"
run_lint "$f"
check "bug.yml dropdown out of sync (feature.yml unaffected): exit 1" "$RUN_EXIT" "1"
check "bug.yml dropdown out of sync: names bug.yml" "$(contains "$RUN_ERR" "bug.yml")" "yes"

# ===========================================================================
# 17. Edge case: dropdown options present but under a different field id
#     than "plugin" -> violation, even though the option list itself is
#     correct.
# ===========================================================================
f="$(new_fixture)"; write_all_valid "$f"
write_feature "$f" "$DEFAULT_LABELS_FEATURE" "affected_plugin" "$DEFAULT_OPTIONS"
run_lint "$f"
check "options under wrong field id: exit 1" "$RUN_EXIT" "1"
check "options under wrong field id: names feature.yml" "$(contains "$RUN_ERR" "feature.yml")" "yes"

# ===========================================================================
# 18. Edge case: empty plugins/ dir -> expected options are just
#     "repo-wide / other" (PASS case and a mismatched-options FAIL case).
# ===========================================================================
f="$(new_fixture_empty_plugins)"; write_all_valid "$f" "$EMPTY_OPTIONS"
run_lint "$f"
check "empty plugins/: conformant options -> exit 0" "$RUN_EXIT" "0"
check "empty plugins/: prints success string" "$(contains "$RUN_OUT" "issue-template-lint: OK")" "yes"

f="$(new_fixture_empty_plugins)"; write_all_valid "$f" "$DEFAULT_OPTIONS"
run_lint "$f"
check "empty plugins/: stale options (alpha/beta/gamma) -> exit 1" "$RUN_EXIT" "1"

# ===========================================================================
# 19-20. Config keys check (clause 5): blank_issues_enabled true/missing,
#        and contact_links present.
# ===========================================================================
f="$(new_fixture)"; write_all_valid "$f"
write_config "$f" $'blank_issues_enabled: true\n'
run_lint "$f"
check "config blank_issues_enabled: true -> exit 1" "$RUN_EXIT" "1"
check "config blank_issues_enabled: true -> names config.yml" "$(contains "$RUN_ERR" "config.yml")" "yes"

f="$(new_fixture)"; write_all_valid "$f"
write_config "$f" $'blank_issues_enabled: false\ncontact_links:\n  - name: "Foo"\n    url: "https://example.com"\n    about: "About"\n'
run_lint "$f"
check "config contact_links present -> exit 1" "$RUN_EXIT" "1"
check "config contact_links present -> names config.yml" "$(contains "$RUN_ERR" "config.yml")" "yes"

# ===========================================================================
# 21. Edge case: non-directory entries under plugins/ (e.g. a stray .md
#     file) are ignored, not treated as plugin names.
# ===========================================================================
f="$(new_fixture_with_stray_file)"; write_all_valid "$f" "$DEFAULT_OPTIONS"
run_lint "$f"
check "stray file under plugins/ ignored: exit 0" "$RUN_EXIT" "0"
check "stray file under plugins/ ignored: not treated as a plugin name" \
  "$(contains "$RUN_ERR" "zzz-not-a-plugin")" "no"

# ===========================================================================
# 22-23. Edge cases: comment-only and empty template files fail checks 3-5.
# ===========================================================================
f="$(new_fixture)"; write_all_valid "$f"
printf '# just a comment\n# nothing else here\n' > "$f/.github/ISSUE_TEMPLATE/feature.yml"
run_lint "$f"
check "comment-only feature.yml: exit 1" "$RUN_EXIT" "1"
check "comment-only feature.yml: names feature.yml" "$(contains "$RUN_ERR" "feature.yml")" "yes"

f="$(new_fixture)"; write_all_valid "$f"
: > "$f/.github/ISSUE_TEMPLATE/feature.yml"
run_lint "$f"
check "empty feature.yml: exit 1" "$RUN_EXIT" "1"
check "empty feature.yml: names feature.yml" "$(contains "$RUN_ERR" "feature.yml")" "yes"

# ===========================================================================
# 24-25. Exit code 2: not run from repo root (missing plugins/, or missing
#        .github/ISSUE_TEMPLATE), message to stderr.
# ===========================================================================
f="$(new_fixture_no_plugins_dir)"; write_all_valid "$f"
run_lint "$f"
check "missing plugins/ dir: exit 2" "$RUN_EXIT" "2"
check "missing plugins/ dir: stderr non-empty" "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

f="$(new_fixture_no_issue_template_dir)"
run_lint "$f"
check "missing .github/ISSUE_TEMPLATE dir: exit 2" "$RUN_EXIT" "2"
check "missing .github/ISSUE_TEMPLATE dir: stderr non-empty" "$([ -n "$RUN_ERR" ] && echo yes || echo no)" "yes"

# ===========================================================================
# 26. "Reports ALL violations" invariant: three unrelated violations across
#     three different files/checks all show up, not just the first found.
# ===========================================================================
f="$(new_fixture)"
write_feature "$f" $'labels:\n  - wrong-label\n' "plugin" "$DEFAULT_OPTIONS"
write_bug "$f" "$DEFAULT_LABELS_BUG" "plugin" "$MISSING_ONE_OPTIONS"
write_config "$f" $'blank_issues_enabled: false\ncontact_links:\n  - name: "Foo"\n    url: "https://example.com"\n    about: "About"\n'
run_lint "$f"
check "multi-violation fixture: exit 1" "$RUN_EXIT" "1"
check "multi-violation fixture: at least 3 violation lines" \
  "$([ "$(line_count "$RUN_ERR")" -ge 3 ] && echo yes || echo no)" "yes"
check "multi-violation fixture: reports feature.yml label violation" "$(contains "$RUN_ERR" "feature.yml")" "yes"
check "multi-violation fixture: reports bug.yml dropdown violation" "$(contains "$RUN_ERR" "bug.yml")" "yes"
check "multi-violation fixture: reports config.yml violation" "$(contains "$RUN_ERR" "config.yml")" "yes"

# ===========================================================================
# 27. Read-only invariant: fixture tree is byte-identical before/after,
#     across both a passing and a failing run.
# ===========================================================================
f="$(new_fixture)"; write_all_valid "$f"
write_feature "$f" $'labels:\n  - wrong-label\n' "plugin" "$MISSING_ONE_OPTIONS"
before="$(tree_snapshot "$f")"
run_lint "$f"
after="$(tree_snapshot "$f")"
check "read-only invariant (failing run): fixture tree unchanged" "$after" "$before"

f="$(new_fixture)"; write_all_valid "$f"
before="$(tree_snapshot "$f")"
run_lint "$f"
after="$(tree_snapshot "$f")"
check "read-only invariant (passing run): fixture tree unchanged" "$after" "$before"

# ===========================================================================
# 28. Integration check (encouraged exception to the fixture-only rule):
#     run the real script, read-only, from the real repo root, and assert
#     it exits 0 there — the repo's actual issue templates are expected to
#     be contract-conformant.
# ===========================================================================
out="$(mktemp)"; err="$(mktemp)"
( cd "$REPO_ROOT" && bash "$SCRIPT" >"$out" 2>"$err" )
real_exit=$?
real_out="$(cat "$out")"
rm -f "$out" "$err"
check "real repo root: exit 0" "$real_exit" "0"
check "real repo root: prints success string" "$(contains "$real_out" "issue-template-lint: OK")" "yes"

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
