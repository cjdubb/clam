#!/usr/bin/env bash
# render.test.sh — verifies the docblock "Contract: B01 render-doc plugin
# core" in plugins/render-doc/README.md, clause by clause.
#
# Adapted from the ported source's own verification suite
# (clam-code/general/skills/render-doc/scripts/smoke.sh); smoke.sh itself is
# not kept. Preserved techniques: renders happen in a temp dir (mktemp) so
# the repo tree stays clean; macOS/GNU base64 -d/-D divergence is handled;
# fail/pass counters with non-zero exit on any failure, without dying on the
# first failed check; </script>-count comparison against the template.
#
# Out of scope here (verified by the orchestrator at acceptance instead):
# byte-identity of assets/fixtures against the clam-code source; --open /
# annotation-server runtime behavior (this file never starts a server or
# opens a browser).

set -uo pipefail  # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER="$PLUGIN_DIR/scripts/render.sh"
TEMPLATE="$PLUGIN_DIR/assets/template.html"
FIXTURES_DIR="$PLUGIN_DIR/fixtures"
SKILL_MD="$PLUGIN_DIR/skills/render/SKILL.md"
README_MD="$PLUGIN_DIR/README.md"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

FAILURES=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'ok: %s\n' "$*"
}

# macOS and GNU disagree on the base64 decode flag.
if printf 'aGkK' | base64 -d > /dev/null 2>&1; then
  B64_DECODE="-d"
else
  B64_DECODE="-D"
fi

# The template closes this many script elements; a rendered file must close
# exactly the same number, or document content leaked out of its data block.
TEMPLATE_SCRIPT_CLOSES="$(grep -c '</script>' "$TEMPLATE" 2>/dev/null)"
: "${TEMPLATE_SCRIPT_CLOSES:=0}"

# --- Render-pipeline clauses (Behavior/Inputs/Outputs/Errors) ---------------

check_render() {
  name="$1"
  src="$FIXTURES_DIR/$name.md"
  md="$WORK/$name.md"
  out="$WORK/$name.html"

  cp "$src" "$md"

  if ! "$RENDER" "$md" > /dev/null 2>"$WORK/$name.stderr"; then
    fail "$name: render.sh exited non-zero on a valid fixture (expected exit 0)"
    return
  fi
  pass "$name: render.sh exits 0 on a valid fixture"

  if [ -s "$out" ]; then
    pass "$name: sibling .html created ($name.md -> $name.html)"
  else
    fail "$name: sibling .html missing or empty"
    return
  fi

  # Parser was spliced in, version-pinned.
  if grep -q 'marked v18.0.6' "$out"; then
    pass "$name: vendored parser present (marked v18.0.6)"
  else
    fail "$name: vendored parser not found in output"
  fi

  # No slot markers left behind.
  if grep -q '__MARKED_SPLICE__\|__DOC_B64_SPLICE__\|__SOURCE_PATH_SPLICE__' "$out"; then
    fail "$name: unreplaced slot marker(s) remain in output"
  else
    pass "$name: no leftover slot markers"
  fi

  # Source path spliced into an inert text/plain block, per contract.
  if grep -q 'type="text/plain"' "$out" && grep -qF "$md" "$out"; then
    pass "$name: source path spliced into a text/plain block"
  else
    fail "$name: source path not found in a text/plain block"
  fi

  # The fixture's </script> must not have leaked into page structure: the
  # rendered file closes exactly as many script elements as the template.
  closes="$(grep -c '</script>' "$out" 2>/dev/null)"
  : "${closes:=0}"
  if [ "$closes" -eq "$TEMPLATE_SCRIPT_CLOSES" ]; then
    pass "$name: </script> count matches template ($closes)"
  else
    fail "$name: expected $TEMPLATE_SCRIPT_CLOSES closing script tags (template), found $closes"
  fi

  # Embedded document round-trips byte-for-byte through base64. This is the
  # </script>-in-markdown proof: the fixture may contain a closing script
  # tag, yet the embedded payload must decode to the exact original bytes.
  # Each stage (extract, decode, compare) fails with its own message.
  payload="$(awk '/id="doc-b64"/ { grab = 1; next } grab && /<\/script>/ { exit } grab { print }' "$out" | tr -d '[:space:]')"
  if [ -z "$payload" ]; then
    fail "$name: could not extract the base64 data block from output"
  elif ! printf '%s' "$payload" | base64 "$B64_DECODE" > "$WORK/$name.roundtrip.md" 2>/dev/null; then
    fail "$name: base64 data block is not valid base64"
  elif [ ! -s "$WORK/$name.roundtrip.md" ]; then
    fail "$name: base64 data block decoded to an empty document"
  elif cmp -s "$md" "$WORK/$name.roundtrip.md"; then
    pass "$name: embedded document round-trips byte-for-byte"
  else
    fail "$name: embedded document does not match the source markdown"
  fi

  # Self-contained: nothing fetched from the network at view time.
  if grep -E '<link[^>]+href="https?:|src="https?:|src='"'"'https?:|url\(https?:|@import|fonts\.googleapis' "$out" > /dev/null; then
    fail "$name: output references external URLs/CDNs"
  else
    pass "$name: no external URL/CDN references"
  fi
}

check_render plan
check_render decision
check_render design-questions

# --- Failure modes: Errors clause -------------------------------------------
# Errors: missing input, missing template -> exit non-zero, message on
# stderr, NO output written. (Missing-parser and splice-failure paths are
# acceptance-verified per brief 01: reliably forcing them from outside would
# require assuming render.sh's own splice mechanism, which does not exist
# yet at scaffold time.)

# missing input
missing_out="$WORK/does-not-exist.html"
if "$RENDER" "$WORK/does-not-exist.md" > /dev/null 2>"$WORK/missing-input.stderr"; then
  fail "missing input: render.sh exited 0 for a nonexistent input file"
else
  pass "missing input: render.sh exits non-zero"
fi
if [ -s "$WORK/missing-input.stderr" ]; then
  pass "missing input: message present on stderr"
else
  fail "missing input: no message on stderr"
fi
if [ -e "$missing_out" ]; then
  fail "missing input: output was written despite the error"
else
  pass "missing input: no output written"
fi

# missing template: copy the whole plugin dir so render.sh's own SCRIPT_DIR
# resolution finds a sibling assets/ dir, then remove template.html from the
# COPY only. The real repo asset is never touched.
plugin_copy="$WORK/plugin-no-template"
cp -r "$PLUGIN_DIR" "$plugin_copy"
rm -f "$plugin_copy/assets/template.html"
copy_render="$plugin_copy/scripts/render.sh"
copy_md="$WORK/no-template-input.md"
cp "$FIXTURES_DIR/plan.md" "$copy_md"
copy_out="$WORK/no-template-input.html"

if "$copy_render" "$copy_md" > /dev/null 2>"$WORK/missing-template.stderr"; then
  fail "missing template: render.sh exited 0 with no assets/template.html"
else
  pass "missing template: render.sh exits non-zero"
fi
if [ -s "$WORK/missing-template.stderr" ]; then
  pass "missing template: message present on stderr"
else
  fail "missing template: no message on stderr"
fi
if [ -e "$copy_out" ]; then
  fail "missing template: output was written despite the error"
else
  pass "missing template: no output written"
fi

# --- Docs clauses (Docs contract sections of the docblock) ------------------
# Strip HTML-comment docblocks first so docblock prose (which quotes the very
# strings being checked for) can never satisfy a check meant for real content.
strip_docblocks() { sed '/<!--/,/-->/d' "$1"; }

skill_body="$WORK/SKILL.stripped.md"
readme_body="$WORK/README.stripped.md"
strip_docblocks "$SKILL_MD" > "$skill_body"
strip_docblocks "$README_MD" > "$readme_body"

# SKILL.md
if grep -qE '^name:[[:space:]]*render[[:space:]]*$' "$skill_body"; then
  pass "SKILL.md: frontmatter name: render"
else
  fail "SKILL.md: frontmatter name: render missing"
fi

if grep -qF '${CLAUDE_PLUGIN_ROOT}/scripts/render.sh' "$skill_body"; then
  pass "SKILL.md: usage references \${CLAUDE_PLUGIN_ROOT}/scripts/render.sh"
else
  fail "SKILL.md: no usage reference to \${CLAUDE_PLUGIN_ROOT}/scripts/render.sh"
fi

for tag in '@COMMENT:' '@QUESTION:' '@CONCERN:' '@APPROVE:' '@EVIDENCE:'; do
  if grep -qF "$tag" "$skill_body"; then
    pass "SKILL.md: documents annotation tag $tag"
  else
    fail "SKILL.md: missing annotation tag $tag"
  fi
done

if grep -qE '~/\.claude/skills/|clam-code/|/clam-code' "$skill_body"; then
  fail "SKILL.md: references a clam-code-era path"
else
  pass "SKILL.md: no clam-code-era path references"
fi

# README.md visible body
if grep -qF 'python3' "$readme_body"; then
  pass "README.md: documents the python3 soft requirement"
else
  fail "README.md: no mention of python3"
fi

if grep -qF 'file://' "$readme_body"; then
  pass "README.md: documents the file:// degradation"
else
  fail "README.md: no mention of file://"
fi

# Attribution must name clam-code (bare word) without a path form; the path
# ban below is a separate, independent check, so this one only needs to
# confirm the word is present.
if grep -qF 'clam-code' "$readme_body"; then
  pass "README.md: ported-from-clam-code attribution present"
else
  fail "README.md: no ported-from-clam-code attribution"
fi

if grep -qE '~/\.claude/skills/|clam-code/|/clam-code' "$readme_body"; then
  fail "README.md: references a clam-code-era path"
else
  pass "README.md: no clam-code-era path references"
fi

# --- Summary -----------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'render.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'render.test.sh: all assertions passed\n'
