#!/usr/bin/env bash
# structure.test.sh — composition test for B05 (issue-8 composition).
# Verifies repo-level integrity of the render-doc port once B01-B04 are
# implemented. Contract docblock lives in plugins/render-doc/README.md,
# "Contract: B05".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
SKILL_MD="$PLUGIN_DIR/skills/render/SKILL.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
ROOT_README="$REPO_ROOT/README.md"
RENDER="$PLUGIN_DIR/scripts/render.sh"
TEMPLATE="$PLUGIN_DIR/assets/template.html"
RUNDOWN_SKILL="$REPO_ROOT/plugins/decision-log/skills/rundown/SKILL.md"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

FAILURES=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'PASS  %s\n' "$*"
}

# --- Clause 1: SKILL.md-named paths resolve ----------------------------------
# Extract ${CLAUDE_PLUGIN_ROOT}/... paths from SKILL.md and verify each exists
# relative to the plugin dir.
while IFS= read -r rel; do
  target="$PLUGIN_DIR/$rel"
  if [ -e "$target" ]; then
    pass "SKILL.md path resolves: \${CLAUDE_PLUGIN_ROOT}/$rel"
  else
    fail "SKILL.md path does not resolve: \${CLAUDE_PLUGIN_ROOT}/$rel -> $target"
  fi
done < <(grep -oP '\$\{CLAUDE_PLUGIN_ROOT\}/\K[^ `"'"'"']+' "$SKILL_MD" | sort -u)

# --- Clause 2: no stale ~/.claude/skills/render-doc refs ----------------------
# Strip HTML comments before checking — contract docblocks quote the very
# string being checked for, but those are metadata, not live references.
stale_refs="$(cd "$REPO_ROOT" && git ls-files -z | xargs -0 -I{} sh -c 'sed "/<!--/,/-->/d" "$1" | grep -q "~/.claude/skills/render-doc" && echo "$1"' _ {} 2>/dev/null | grep -v 'MIGRATION.md' | grep -v '\.test\.sh$' || true)"
if [ -z "$stale_refs" ]; then
  pass "no stale ~/.claude/skills/render-doc refs outside MIGRATION.md and test files"
else
  for f in $stale_refs; do
    fail "stale ~/.claude/skills/render-doc reference in: $f"
  done
fi

# --- Clause 3: version agreement ---------------------------------------------
pj_version="$(jq -r '.version' "$PLUGIN_JSON")"

# marketplace.json must NOT carry a version field (plugin.json is the single
# source of truth; duplicating it causes drift).
mp_has_version="$(jq '.plugins[] | select(.name == "render-doc") | has("version")' "$MARKETPLACE")"
if [ "$mp_has_version" = "false" ]; then
  pass "marketplace entry has no version field (plugin.json is source of truth)"
else
  fail "marketplace entry still carries a version field — remove it; plugin.json is source of truth"
fi

# Root README: extract version from the render-doc row (e.g., "✅ v0.1.0")
strip_docblocks() { sed '/<!--/,/-->/d' "$1"; }
readme_version="$(strip_docblocks "$ROOT_README" | grep -oP 'render-doc.*?v\K[0-9]+\.[0-9]+\.[0-9]+')"

if [ "$pj_version" = "$readme_version" ]; then
  pass "plugin.json version ($pj_version) == root README version ($readme_version)"
else
  fail "plugin.json version ($pj_version) != root README version (${readme_version:-not found})"
fi

# --- Clause 4: decision-log consumer seam holds -------------------------------
if [ -f "$RUNDOWN_SKILL" ]; then
  if grep -qF 'render-doc:render' "$RUNDOWN_SKILL"; then
    pass "rundown SKILL.md references render-doc:render"
  else
    fail "rundown SKILL.md does not reference render-doc:render"
  fi
else
  fail "rundown SKILL.md not found at $RUNDOWN_SKILL"
fi

# --- Clause 5: end-to-end render green ----------------------------------------
fixture="$PLUGIN_DIR/fixtures/plan.md"
e2e_md="$WORK/plan.md"
e2e_out="$WORK/plan.html"
cp "$fixture" "$e2e_md"

if "$RENDER" "$e2e_md" > /dev/null 2>"$WORK/e2e.stderr"; then
  pass "end-to-end: render.sh exits 0"
else
  fail "end-to-end: render.sh exits non-zero"
fi

if [ -s "$e2e_out" ]; then
  pass "end-to-end: output HTML exists and is non-empty"
else
  fail "end-to-end: output HTML missing or empty"
fi

if [ -s "$e2e_out" ] && grep -q 'marked v18.0.6' "$e2e_out"; then
  pass "end-to-end: vendored parser present"
else
  fail "end-to-end: vendored parser not found in output"
fi

if [ -s "$e2e_out" ] && ! grep -q '__MARKED_SPLICE__\|__DOC_B64_SPLICE__\|__SOURCE_PATH_SPLICE__' "$e2e_out"; then
  pass "end-to-end: no leftover slot markers"
else
  fail "end-to-end: leftover slot markers remain"
fi

template_closes="$(grep -c '</script>' "$TEMPLATE" 2>/dev/null)"
: "${template_closes:=0}"
if [ -s "$e2e_out" ]; then
  output_closes="$(grep -c '</script>' "$e2e_out" 2>/dev/null)"
  : "${output_closes:=0}"
  if [ "$output_closes" -eq "$template_closes" ]; then
    pass "end-to-end: </script> count matches template ($output_closes)"
  else
    fail "end-to-end: expected $template_closes </script> tags, found $output_closes"
  fi
fi

# --- Summary ------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'structure.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'structure.test.sh: all assertions passed\n'
