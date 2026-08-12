#!/usr/bin/env bash
# structure.test.sh — composition test for B05 (issue-8 composition).
# Verifies repo-level integrity of the render-doc port once B01-B04 are
# implemented. Contract docblock lives in plugins/render-doc/README.md,
# "Contract: B05".
#
# It also carries a second, later composition contract: "Contract: B06 port
# composition" (plan 001-render-doc-fixed-port-server), whose docblock is in
# this file, below the B05 clauses. Every assertion belonging to it is
# labelled "B06 clause N", so a failure says which contract it belongs to.

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
stale_refs="$(
  cd "$REPO_ROOT" || exit 0
  git ls-files -z | xargs -0 -I{} sh -c 'sed "/<!--/,/-->/d" "$1" | grep -q "~/.claude/skills/render-doc" && echo "$1"' _ {} 2>/dev/null | grep -v 'MIGRATION.md' | grep -v '\.test\.sh$' || true
)"
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

# Contract: B06 port composition
#   (plan 001-render-doc-fixed-port-server)
#
# IMPLEMENTED — the checks described below live immediately after this
# docblock, above the Summary section. Test-family file: a test-writer
# owns it and there is NO implementation phase. Dispatched only after B01,
# B02, B03 and B05 are accepted, because it asserts across all of them.
#
# Behavior — plugin-wide integrity once the fixed-port server has landed.
# This is the composition block: each clause spans files that no single
# leaf block owns, which is exactly why it cannot live in one of them.
#   1. The retired design is gone from EVERY file in the plugin — scripts,
#      assets, skills, and README alike. No occurrence anywhere of
#      "/tmp/render-doc-serve.json", "POST /register", "/register",
#      "/d/<id>" or "/d/{id}", or a 30-minute idle shutdown, except where a
#      line is plainly describing what was removed. Search the whole plugin
#      directory, not a listed subset: the point is to catch the file
#      nobody remembered to update.
#   2. The replacement is coherent across files: serve.py and render.sh
#      agree on the port default (27183) and the RENDER_DOC_PORT override
#      name, and on the /doc route prefix and /health app marker. A
#      mismatch here is the failure mode that splitting the pair across two
#      blocks risks, so assert it rather than trusting review.
#   3. All four fixtures (plan, decision, design-questions, work-graph)
#      still render, and the work-graph render still produces its tree —
#      the Work Graph transform (#227) is this repo's own and is NOT in the
#      upstream source being ported, so it is the thing most likely to be
#      lost to a careless whole-file copy.
#   4. plugins/render-doc/.claude-plugin/plugin.json carries version 0.3.0
#      or higher.
#
# Outputs:
#   pass/fail lines in this file's existing harness style, counted into
#   FAILURES so the Summary below reports them.
#
# Errors:
#   None of its own; a failure here means a leaf block landed incomplete.
#
# Invariants:
#   - Starts no server and opens no browser (that is open.test.sh's realm).
#   - Renders into a temp dir; the repo tree stays clean.
#   - Asserts on committed repo state, never on a running process.
#
# Edge cases:
#   - A retired-design string surviving only inside an HTML comment or a
#     docblock still counts as a residue and must fail.
#   - The port default appearing in one file but not the other.

# =============================================================================
# B06 — port composition. The four clauses of the docblock above.
# =============================================================================

PLUGIN_ROOT="$(cd "$PLUGIN_DIR" && pwd)"
SERVE_PY="$PLUGIN_ROOT/scripts/serve.py"

# --- B06 clause 1: the retired design is gone from EVERY file ----------------
# The sweep is the whole of this clause's evidence, so prove it looked at the
# files that matter before trusting a green: a root that failed to resolve
# would otherwise sweep nothing and pass vacuously.
#
# *.test.sh files are excluded, and only they: a suite that BANS these
# literals has to spell them out, which is why the B05 clause-2 sweep above
# already filters the same way. Nothing else is excluded as a class — see the
# retirement-prose note below.
mapfile -t B06_SWEEP < <(find "$PLUGIN_ROOT" -type f ! -name '*.test.sh' | sort)

# Contract: 003-B12 sweep check de-piped (plan 003-followup-fixes)
#
# Behavior: the sweep-coverage check asserts each expected file's
#   membership in B06_SWEEP without a writer-side pipeline into a -q
#   grep (herestring, temp file, or a pure-bash membership loop).
# Inputs: B06_SWEEP and the expected relative paths (unchanged).
# Outputs: identical pass/fail lines for identical sweep contents.
# Errors: none new.
# Invariants: SIGPIPE-immune under pipefail; the token scan later in
#   this suite that reuses B06_SWEEP is untouched (closes #336).
# Edge cases: an expected file missing from the sweep (still fails);
#   an empty sweep (the outer guard below is unchanged).

# Whole-string equality over the array itself, which is what `grep -qxF` was
# asked for here. The pipeline it replaces had a writer — printf, feeding every
# swept path — on the other side of a reader that exits at its first hit: under
# `set -o pipefail` that SIGPIPE (141) becomes the pipeline's status and a
# COVERED file reports as uncovered, the more likely the larger the sweep grows.
in_sweep() { # <absolute path>
  local f
  for f in ${B06_SWEEP[@]+"${B06_SWEEP[@]}"}; do
    [ "$f" = "$1" ] && return 0
  done
  return 1
}

if [ "${#B06_SWEEP[@]}" -gt 0 ]; then
  pass "B06 clause 1: sweep visited ${#B06_SWEEP[@]} non-test file(s) under the plugin"
  for expected in README.md skills/render/SKILL.md assets/template.html \
    assets/marked.min.js scripts/serve.py scripts/render.sh \
    .claude-plugin/plugin.json; do
    if in_sweep "$PLUGIN_ROOT/$expected"; then
      pass "B06 clause 1: sweep covers $expected"
    else
      fail "B06 clause 1: sweep does not cover $expected — residue there would go unseen"
    fi
  done
else
  fail "B06 clause 1: sweep visited no files — the plugin root did not resolve ($PLUGIN_ROOT)"
fi

# Retired-design tokens, each spelled as the concrete artifact the contract
# names rather than a paraphrase of it. Two boundaries are load-bearing:
#   - the .json suffix, so the LIVE pidfile /tmp/render-doc-serve-<port>.pid
#     is not mistaken for the retired state file;
#   - the non-alphanumeric after /register, so the path
#     scripts/registration.test.sh — which README's Tests list names, and
#     which is about marketplace registration, not the retired route — is not
#     mistaken for it.
B06_RETIRED=(
  '/tmp/render-doc-serve\.json'
  '/register([^[:alnum:]]|$)'
  '/d/'
  '30[[:space:]-]*min'
)

# The contract's exception is "a line plainly describing what was removed";
# its edge case is that a comment or a docblock is NOT exempt as such. The
# discriminator is therefore the SENTENCE the token sits in, not the lines
# around it: a hit is exempt only where the retirement is stated in that same
# sentence. Asking whether the keyword appears anywhere in a line window is
# defeated by an ordinary neighbouring sentence — live retired-design prose
# followed by "You must not skip this step." would be exempted silently, and
# this sweep is the whole of clause 1's evidence. Every exemption prints its
# own file and line, so it stays reviewable rather than silent.
#
# Comment prose hard-wraps — render.sh:178-179 splits one sentence over two
# lines — so the window is still the matched line plus the next one. What
# changed is that the window is JOINED into a single string first and the
# keyword must then fall inside the token's own sentence. The preceding line
# is no longer read: nothing before the token can be part of the sentence
# tail scanned below, and including it would let a retired-design mention one
# line up exempt a live one here.
#
# The scan runs FORWARD from the end of the match, never backward. Backward
# is where the tokens' own punctuation bites: /tmp/render-doc-serve.json
# carries a dot, as do serve.py, 127.0.0.1 and every version string, so a
# boundary measured back from a match would terminate inside the match
# itself. Forward is also the exact shape of the contract's exception —
# prose that names the residue and then says it is gone.
#
# A sentence ends at a period followed by whitespace (or at the end of the
# window), not at any period at all: "serve.py" or "0.3.0" standing between
# the token and the keyword must not end the sentence early and report live
# retirement prose as residue.
B06_RETIREMENT_PROSE='retired|removed|no longer|must not|belongs to the (old|previous)|is gone|was replaced'
B06_SENTENCE_GAP='([^.]|\.[^[:space:]])'

# Cut the token and the remainder of ITS sentence out of the joined window,
# then ask that span alone for the retirement keyword. Two greps rather than
# one combined pattern so neither borrows the other's case sensitivity: the
# tokens are matched case-sensitively, as B06_RETIRED spells them, and the
# prose case-insensitively, as comment prose capitalises.
b06_same_sentence() { # <file> <line-no> <token-pattern>
  sed -n "$2,$(($2 + 1))p" "$1" | tr '\n' ' ' \
    | grep -oE -- "($3)${B06_SENTENCE_GAP}{0,80}" \
    | grep -qiE -- "$B06_RETIREMENT_PROSE"
}

b06_residue=0
b06_exempt=0
for f in ${B06_SWEEP[@]+"${B06_SWEEP[@]}"}; do
  rel="${f#"$PLUGIN_ROOT"/}"
  for pat in "${B06_RETIRED[@]}"; do
    while IFS= read -r n; do
      case "$n" in '' | *[!0-9]*) continue ;; esac # skip "Binary file ... matches"
      if b06_same_sentence "$f" "$n" "$pat"; then
        b06_exempt=$((b06_exempt + 1))
        pass "B06 clause 1: $rel:$n names the retired design only to say it is gone"
      else
        b06_residue=$((b06_residue + 1))
        fail "B06 clause 1: retired-design residue in $rel:$n (matches '$pat')"
      fi
    done < <(grep -nE -- "$pat" "$f" 2> /dev/null | cut -d: -f1)
  done
done

if [ "$b06_residue" -eq 0 ]; then
  pass "B06 clause 1: no retired-design residue in the plugin ($b06_exempt exempt as retirement prose)"
fi

# --- B06 clause 2: serve.py and render.sh agree on the replacement ----------
# Each fact is EXTRACTED from both files and the two values compared against
# each other, rather than both files being grepped for the same literal
# written here: the failure this clause exists to catch is one file changing
# without the other, and a comparison says so in the failure message.
b06_pair() { # <label> <value-from-serve.py> <value-from-render.sh>
  if [ -z "$2" ] || [ -z "$3" ]; then
    fail "B06 clause 2: $1 — extraction came back empty (serve.py='$2', render.sh='$3'); an anchor moved"
  elif [ "$2" = "$3" ]; then
    pass "B06 clause 2: $1 — serve.py and render.sh agree ($2)"
  else
    fail "B06 clause 2: $1 — serve.py says '$2', render.sh says '$3'"
  fi
}

# The variable name is matched as the shape an environment variable really
# has ([A-Z_][A-Z0-9_]*), not [A-Z_]+: a renamed-with-a-digit override would
# otherwise fall out of the extraction and be reported as a moved anchor
# rather than as the disagreement it is.
py_port_env="$(grep -oP "os\.environ\.get\(\s*'\K[A-Z_][A-Z0-9_]*" "$SERVE_PY" | head -1)"
py_port_default="$(grep -oP "os\.environ\.get\(\s*'[A-Z_][A-Z0-9_]*'\s*,\s*'\K[0-9]+" "$SERVE_PY" | head -1)"
sh_port_env="$(grep -oP '\$\{\K[A-Z_][A-Z0-9_]*(?=:-[0-9]+\})' "$RENDER" | head -1)"
sh_port_default="$(grep -oP '\$\{[A-Z_][A-Z0-9_]*:-\K[0-9]+(?=\})' "$RENDER" | head -1)"

b06_pair "the port override variable" "$py_port_env" "$sh_port_env"
b06_pair "the port default" "$py_port_default" "$sh_port_default"

# The contract names both values outright, so agreement alone is not enough:
# the pair could agree on the wrong port.
if [ "$py_port_env" = "RENDER_DOC_PORT" ]; then
  pass "B06 clause 2: the override variable is the contract's RENDER_DOC_PORT"
else
  fail "B06 clause 2: the override variable is '${py_port_env:-not found}', not RENDER_DOC_PORT"
fi
if [ "$py_port_default" = "27183" ]; then
  pass "B06 clause 2: the port default is the contract's 27183"
else
  fail "B06 clause 2: the port default is '${py_port_default:-not found}', not 27183"
fi

# Routes are read from serve.py, which owns them, and each must be one of the
# $BASE-relative paths render.sh actually builds its URLs from.
py_doc_route="$(grep -oP "startswith\('\K/[A-Za-z0-9_-]+" "$SERVE_PY" | head -1)"
py_health_route="$(grep -oP "raw == '\K/[A-Za-z0-9_-]+" "$SERVE_PY" | head -1)"
sh_routes="$(grep -oP '\$BASE\K/[A-Za-z0-9_-]+' "$RENDER" | sort -u)"

b06_route() { # <label> <route-from-serve.py>
  if [ -z "$2" ]; then
    fail "B06 clause 2: $1 — could not read the route out of serve.py; an anchor moved"
  elif printf '%s\n' "$sh_routes" | grep -qxF -- "$2"; then
    pass "B06 clause 2: $1 — render.sh builds its URL on serve.py's own $2"
  else
    fail "B06 clause 2: $1 — serve.py serves '$2', but render.sh's \$BASE routes are: $(printf '%s' "$sh_routes" | tr '\n' ' ')"
  fi
}

b06_route "the /doc route prefix" "$py_doc_route"
b06_route "the /health route" "$py_health_route"

if [ "$py_doc_route" = "/doc" ]; then
  pass "B06 clause 2: the document route prefix is the contract's /doc"
else
  fail "B06 clause 2: the document route prefix is '${py_doc_route:-not found}', not /doc"
fi

py_app="$(grep -oP '"app":\s*"\K[^"]+' "$SERVE_PY" | head -1)"
sh_app="$(grep -oP '\$APP"[[:space:]]*[!=]=[[:space:]]*"\K[^"]+' "$RENDER" | head -1)"
b06_pair "the /health app marker" "$py_app" "$sh_app"

# --- B06 clause 3: all four fixtures still render, tree included -------------
# Deliberately NOT a second copy of render.test.sh's per-fixture depth
# (base64 round-trip, </script> counts, external-URL ban) or of
# workgraph-render.test.sh's reading of template.html's source. The
# composition claim is narrower and belongs to no leaf block: all four
# fixtures survive the port TOGETHER, and the Work Graph transform — this
# repo's own, absent from the upstream that was ported — is still in the
# artifact a render produces, not merely in the template it was spliced from.
compose="$WORK/compose"
mkdir -p "$compose"
b06_rendered=0
for fx in plan decision design-questions work-graph; do
  fx_src="$PLUGIN_ROOT/fixtures/$fx.md"
  fx_md="$compose/$fx.md"
  fx_out="$compose/$fx.html"
  if [ ! -f "$fx_src" ]; then
    fail "B06 clause 3: fixture $fx.md is missing from the plugin"
    continue
  fi
  cp "$fx_src" "$fx_md"
  if ! "$RENDER" "$fx_md" > /dev/null 2> "$compose/$fx.stderr"; then
    fail "B06 clause 3: $fx.md no longer renders (render.sh exited non-zero)"
    continue
  fi
  if [ -s "$fx_out" ]; then
    b06_rendered=$((b06_rendered + 1))
    pass "B06 clause 3: $fx.md renders to a non-empty $fx.html"
  else
    fail "B06 clause 3: $fx.md rendered but wrote nothing to $fx.html"
  fi
done

if [ "$b06_rendered" -eq 4 ]; then
  pass "B06 clause 3: all four fixtures still render after the port"
else
  fail "B06 clause 3: only $b06_rendered of the 4 fixtures render after the port"
fi

wg_out="$compose/work-graph.html"
if [ -s "$wg_out" ]; then
  for marker in 'transformWorkGraph' '"work-graph"' 'wg-tree' 'wg-node'; do
    if grep -qF -- "$marker" "$wg_out"; then
      pass "B06 clause 3: the work-graph render still carries $marker"
    else
      fail "B06 clause 3: the work-graph render lost $marker — the Work Graph transform did not survive the port"
    fi
  done
fi

# --- B06 clause 4: the plugin version is at or above the floor ---------------
# A floor, never equality: a later bump must not turn this red.
B06_VERSION_FLOOR='0.3.0'
if [ -z "$pj_version" ] || [ "$pj_version" = "null" ]; then
  fail "B06 clause 4: plugin.json carries no .version"
elif [ "$(printf '%s\n%s\n' "$B06_VERSION_FLOOR" "$pj_version" | sort -V | head -1)" = "$B06_VERSION_FLOOR" ]; then
  pass "B06 clause 4: plugin.json version $pj_version is at or above the $B06_VERSION_FLOOR floor"
else
  fail "B06 clause 4: plugin.json version $pj_version is below the $B06_VERSION_FLOOR floor"
fi

# =============================================================================
# Contract: 003-B17 stale scaffold notes gone (plan 003-followup-fixes)
#
# Ten notes left by earlier plans' scaffolds still say DELIBERATELY
# UNIMPLEMENTED above code that has long since been implemented — eight in
# serve.py, two in render.sh. They are deleted; everything else in those
# docblocks stays byte-for-byte.
#
# This lands in the composition suite because the claim spans serve.py and
# render.sh together and belongs to neither's behaviour: it is source hygiene,
# the same species as B06 clause 1's retired-design sweep just above, and no
# behavioural suite owns it.
#
# TWO scoping traps, and both are why this section greps exactly two named files
# and never the plugin, the tree, or B06_SWEEP:
#
#   1. assets/template.html carries plan-003's OWN scaffold notes for blocks
#      that have not been implemented yet. They are legitimately there, and a
#      plugin-wide sweep for the phrase would fail on content this very plan is
#      keeping until a later block lands.
#   2. The phrase appears inside the plan-003 contract comments themselves —
#      including this block's, which quotes it to say what must go. Those
#      comments are present until acceptance, so every absence check below runs
#      against a copy with the plan-003 contract blocks removed. Without that,
#      the checks would be red forever and go green only at acceptance, which
#      tests nothing about the implementation.
#
# The five legitimate references in test files are a third exclusion, handled
# by naming the two source files rather than by filtering.
# =============================================================================

B17_NOTE='DELIBERATELY UNIMPLEMENTED'

# A copy of a source file with every plan-003 contract comment block removed: a
# "# Contract: 003-B<NN>" line and the consecutive comment lines beneath it.
b17_strip_003() { # <file> <output file>
  python3 - "$1" << 'PY' > "$2" 2> /dev/null
import re
import sys

out = []
skipping = False
with open(sys.argv[1], encoding='utf-8') as fh:
    for line in fh:
        if re.match(r'\s*#\s*Contract:\s*003-B[0-9]+', line):
            skipping = True
            continue
        if skipping:
            if re.match(r'\s*#', line):
                continue
            skipping = False
        out.append(line)
sys.stdout.write(''.join(out))
PY
}

B17_RENDER_SH="$PLUGIN_ROOT/scripts/render.sh"
B17_FILES=("$SERVE_PY" "$B17_RENDER_SH")
for f in "${B17_FILES[@]}"; do
  rel="${f#"$PLUGIN_ROOT"/}"
  stripped="$WORK/b17-$(basename "$f").stripped"
  b17_strip_003 "$f" "$stripped"

  if [ ! -s "$stripped" ]; then
    fail "B17: the plan-003 strip of $rel produced nothing — no note check can be trusted"
    continue
  fi

  # The strip has to be proven, not assumed: a broken stripper that deleted
  # nothing would let the plan-003 comments' own use of the phrase fail every
  # check below, and one that deleted everything would pass them vacuously.
  if ! grep -qE 'Contract: 003-B[0-9]+' "$f"; then
    pass "B17: no plan-003 contract comment remains in $rel to prove the strip against"
  elif grep -qE 'Contract: 003-B[0-9]+' "$stripped"; then
    fail "B17: a plan-003 contract comment survived the strip of $rel — the note checks below are unreliable"
  else
    pass "B17: plan-003 contract comments are stripped from the $rel copy"
  fi

  n_notes="$(grep -cF -- "$B17_NOTE" "$stripped" 2> /dev/null)"
  : "${n_notes:=0}"
  if [ "$n_notes" -eq 0 ]; then
    pass "B17: no stale scaffold note remains in $rel"
  else
    fail "B17: $rel still carries $n_notes stale '$B17_NOTE' note(s): $(grep -nF -- "$B17_NOTE" "$stripped" | head -3 | tr '\n' ' ')"
  fi
done

# Preservation, the other half of the contract: only the status sentences go.
# Each docblock is represented by its Contract: marker, one clause line, and the
# signature the docblock sits above — all byte-for-byte. The clause lines are
# chosen from clauses no OTHER block of this unit rewrites: B15 rewrites the
# marker sentences in the index_doc_entries and 002-B04 docblocks and B16
# rewrites B03's clause 6, so a line from any of those would fail here for a
# reason that has nothing to do with B17.
B17_SERVE_KEEP=(
  '# Contract: B02 served-doc registry (plan 001-render-graph-always)'
  '#   The server remembers which documents it has served, so the index page'
  'def registry_record(md_real):'
  'def registry_entries():'
  'def worktree_siblings(root):'
  'Contract: 002-B01 discovery scan — worktree_siblings'
  '    Behavior: Return the worktree root realpaths of every worktree of the'
  'def discover_docs(root):'
  'Contract: 002-B01 discovery scan — discover_docs'
  '    Inputs: root — an absolute worktree root realpath.'
  'def index_doc_entries():'
  'Contract: 002-B02 index discovery integration'
  '    Behavior: The document set for GET / — the registry united with'
  '# Contract: B01 raw-doc route (plan 001-render-graph-always)'
  '    #   GET /raw/<abs-md-path> serves the CURRENT bytes of the source'
  'def _serve_raw(self, md_path):'
  '    # Contract: B02 served-doc registry — /docs.json handler; see the'
  '    # module-level B02 contract above registry_record for the full spec.'
  'def _serve_docs_json(self):'
  '    # Contract: B03 project index (plan 001-render-graph-always)'
  '    #   1. Source of truth: registry_entries() (B02) — already scope-pruned'
  'def _serve_index(self):'
  '    # Contract: 002-B04 worktree landing page (plan 002-discovery-landing-dns)'
  '    #   GET /project/<abs worktree root> responds 200 text/html;'
  'def _serve_project(self, root_path):'
)
# Presence alone would pass a rewrite that kept every clause but shuffled them,
# and the contract's edge case holds the surrounding clauses to their exact order
# as well as their exact text. Both KEEP arrays are written in file order, so the
# first match of each literal must come out strictly increasing. This runs only
# once every literal is present, or a lost line would be reported twice.
b17_in_order() { # <file> <label> <literal>...
  local file="$1" label="$2"
  shift 2
  local prev=0 n line
  for line in "$@"; do
    n="$(grep -nF -m1 -- "$line" "$file" 2> /dev/null | cut -d: -f1)"
    if [ "${n:-0}" -le "$prev" ]; then
      fail "B17: $label keeps the preserved clauses but reorders them (\"$line\" at line ${n:-?}, after line $prev)"
      return 1
    fi
    prev="$n"
  done
  pass "B17: the preserved clauses of $label keep their contract order"
}

b17_kept=0
for line in "${B17_SERVE_KEEP[@]}"; do
  if grep -qF -- "$line" "$SERVE_PY"; then
    b17_kept=$((b17_kept + 1))
  else
    fail "B17: serve.py lost a line the contract preserves byte-for-byte: $line"
  fi
done
if [ "$b17_kept" -eq "${#B17_SERVE_KEEP[@]}" ]; then
  pass "B17: every Contract: marker, sampled clause and signature line survives in serve.py ($b17_kept lines)"
  b17_in_order "$SERVE_PY" "serve.py" "${B17_SERVE_KEEP[@]}"
fi

B17_RENDER_KEEP=(
  '# Contract: B02 --open server client (plan 001-render-doc-fixed-port-server)'
  '#   Point a browser at the document, served by the shared server described'
  'if [ "$OPEN" -eq 1 ]; then'
  '# Contract: B08 --serve registration mode (plan 001-render-graph-always)'
  '#   render.sh <doc.md> --serve makes the document available (and'
  'if [ "$SERVE_MODE" -eq 1 ]; then'
)
b17_kept=0
for line in "${B17_RENDER_KEEP[@]}"; do
  if grep -qF -- "$line" "$B17_RENDER_SH"; then
    b17_kept=$((b17_kept + 1))
  else
    fail "B17: render.sh lost a line the contract preserves byte-for-byte: $line"
  fi
done
if [ "$b17_kept" -eq "${#B17_RENDER_KEEP[@]}" ]; then
  pass "B17: every Contract: marker, sampled clause and signature line survives in render.sh ($b17_kept lines)"
  b17_in_order "$B17_RENDER_SH" "render.sh" "${B17_RENDER_KEEP[@]}"
fi

# The legitimate references live in test files, where a suite asserting its own
# block's note was removed has to spell the phrase out. Those are not this
# block's targets and must come through untouched.
b17_refs=0
for t in live-update graph-default topbar-nav; do
  tf="$PLUGIN_ROOT/scripts/$t.test.sh"
  if [ ! -f "$tf" ]; then
    fail "B17: the suite carrying a legitimate reference is missing: scripts/$t.test.sh"
  elif grep -qF -- "$B17_NOTE" "$tf"; then
    b17_refs=$((b17_refs + 1))
  else
    fail "B17: scripts/$t.test.sh lost its legitimate reference to the phrase"
  fi
done
if [ "$b17_refs" -eq 3 ]; then
  pass "B17: the legitimate references in test files are untouched (3 suites)"
fi

# --- Summary ------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'structure.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'structure.test.sh: all assertions passed\n'
