#!/usr/bin/env bash
# serve-mode-docs.test.sh — the prose and version half of B08 (--serve
# registration mode, plan 001-render-graph-always).
#
# B08's contract docblock lives in scripts/render.sh and covers the runtime
# behaviour (serve-mode.test.sh asserts that). The docs and version obligations
# live in the block-map entry instead of a docblock, so this file is where they
# are pinned:
#   - plugins/render-doc/README.md and skills/render/SKILL.md describe --serve:
#     it registers the document on the shared server, prints the URL, opens
#     nothing, and a non-zero exit means callers skip;
#   - .claude-plugin/plugin.json reaches 0.7.0, and the root README's Plugins
#     table render-doc row carries the same version (readme-lint pairs the two,
#     so both legs and their equality are asserted).
#
# Prose is asserted by presence/proximity anchors drawn from the obligation's
# own vocabulary, never by exact sentences — the wording is the implementer's
# choice. That is the convention workgraph-docs.test.sh established and
# graph-always-docs.test.sh continued for this plugin's docs blocks, including
# its discovered-from-the-tree sibling-plugin check.
#
# The scoping that matters here is the --serve WINDOW. Both files already say
# things this block also has to say — the README's "Render without opening a
# browser" section already explains that a non-zero exit means "fall back to
# the plain-markdown flow", and the Annotation server section already describes
# the shared server at length. A section-scoped grep for those facts would
# therefore pass on prose that never mentions --serve at all. So every fact
# below is asserted inside the text immediately surrounding a literal --serve
# mention, which is empty until the flag is documented and cannot be satisfied
# by a neighbouring paragraph about something else.
#
# Not asserted here, because another suite already owns it: the README "## Tests"
# list naming this file and serve-mode.test.sh (server-docs.test.sh derives that
# list from the tree), and README template conformance (readme-lint).

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
README="$PLUGIN_DIR/README.md"
SKILL_MD="$PLUGIN_DIR/skills/render/SKILL.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
ROOT_README="$REPO_ROOT/README.md"

# The version this block bumps to, asserted as a FLOOR rather than an equality:
# later blocks and later plans keep bumping this plugin, and a test about
# --serve docs must not go red the day an unrelated block bumps past it.
# Repo precedent: workgraph-docs.test.sh's own de-pinned floor (#120).
VERSION_FLOOR='0.7.0'

# How much text either side of a "--serve" mention counts as documenting it.
# Wide enough for a paragraph that states all four facts, narrow enough that an
# unrelated neighbouring paragraph cannot satisfy a clause on its own.
# Capped at 250 because it is spliced into an ERE bound below: BSD/POSIX
# regex allows at most 255 repetitions, and a larger bound makes grep error
# out (empty window, every windowed clause failing) rather than match wider.
WINDOW=250

FAILURES=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'PASS  %s\n' "$*"
}

# Contract prose quotes the very strings these checks look for, so every prose
# check runs against a copy with HTML comments removed — otherwise a docblock
# would satisfy the checks while the reader-facing prose said nothing.
strip_docblocks() { sed '/<!--/,/-->/d' "$1"; }

# Both files are hard-wrapped, and every check below is a proximity check, so
# each region is flattened to one line first. A two-word pattern must not miss
# because the author's line broke between the words.
flatten() { tr '\n' ' ' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'; }

# Not `grep -q`: under `set -o pipefail` an early-exiting grep -q closes the
# pipe under a still-writing printf and the SIGPIPE becomes the pipeline's
# status. Cheap to avoid, invisible when it bites. (graph-always-docs.test.sh
# documents the same trap.)
matches() { # <haystack> <ERE>
  printf '%s\n' "$1" | grep -iE -- "$2" > /dev/null 2>&1
}
matches_f() { # <haystack> <literal>
  printf '%s\n' "$1" | grep -iF -- "$2" > /dev/null 2>&1
}
has() { # <haystack> <ERE> <label>
  if matches "$1" "$2"; then pass "$3"; else fail "$3"; fi
}
has_f() { # <haystack> <literal> <label>
  if matches_f "$1" "$2"; then pass "$3"; else fail "$3"; fi
}

section() { # <file> <heading-ere> <stop-ere>
  awk -v pat="$2" -v stop="$3" '
    /^(```|~~~)/ { fence = !fence; if (p) print; next }
    !p { if (!fence && $0 ~ pat) p = 1; next }
    p && !fence && $0 ~ stop { exit }
    p
  ' "$1"
}

# The text around every literal "--serve" mention in <region>. Empty when the
# flag is not documented at all, which is what keeps every fact check below
# honest: no mention, no window, no accidental pass from a neighbour.
serve_window() { # <flattened region>
  printf '%s\n' "$1" | grep -oE ".{0,$WINDOW}--serve.{0,$WINDOW}" 2> /dev/null | tr '\n' ' '
}

# Sibling plugin directory names, discovered from the tree rather than
# hardcoded — a literal "<name> plugin"/"/<name>:"/"<name>@clam"/"plugins/
# <name>/" string in this file's own source would itself be a cross-plugin
# reference and get flagged by architecture-lint. Copied from
# workgraph-docs.test.sh, which explains the reasoning at length.
sibling_plugins() {
  find "$REPO_ROOT/plugins" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2> /dev/null \
    | grep -vFx "$(basename "$PLUGIN_DIR")" | sort
}

assert_no_sibling_reference() { # <haystack> <label>
  local haystack="$1" label="$2"
  local hit="" p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if matches "$haystack" "/${p}:|${p}@clam|plugins/${p}/|${p}[[:space:]]plugin"; then
      hit="$p"
      break
    fi
  done < <(sibling_plugins)
  if [ -n "$hit" ]; then
    fail "$label: names a sibling plugin (reference form found — see CLAUDE.md's layering rule)"
  else
    pass "$label: names no sibling plugin"
  fi
}

# --- Vocabulary ---------------------------------------------------------------
# Each fact as an alternation, so a faithful rewrite is not forced into one
# word. $WS spells a gap that survives a hard wrap flattened to one space.
WS='[[:space:]]+'

# "registers it on the shared server". The contract's own verb, plus the two
# artifacts that ARE the registration as far as a reader is concerned.
REGISTERS="regist|/docs\\.json|(listed|appears|shows${WS}up)${WS}(on|in)${WS}the${WS}index"
SHARED_SERVER="shared|annotation${WS}server|the${WS}server"
# "prints the URL".
PRINTS_URL="serving:|print[^.]{0,60}url|url[^.]{0,60}(print|stdout)|writes[^.]{0,40}url[^.]{0,40}stdout"
# "opens nothing".
OPENS_NOTHING="no${WS}browser|nothing${WS}is${WS}opened|opens${WS}nothing|without${WS}opening|never${WS}opens|does${WS}not${WS}open|doesn't${WS}open|no${WS}window|opening${WS}nothing"
# "non-zero exit = callers skip".
NONZERO="non-?zero|exit(s|ed|${WS}code)?${WS}3"
SKIP="skip|falls?${WS}back|fallback"

# --- Regions ------------------------------------------------------------------
# README: the two places render.sh's own flags are documented — the
# browserless-render workflow and the "## Commands" chapter that carries the
# Skills and Scripts entries. Deliberately NOT the whole file: "## Relationships
# to other plugins" legitimately names a consumer and is untouched by this block.
readme_workflow="$(section "$README" '^### Render without opening a browser$' '^#' \
  | strip_docblocks /dev/stdin | flatten)"
readme_commands="$(section "$README" '^## Commands$' '^## ' \
  | strip_docblocks /dev/stdin | flatten)"
readme_scripts="$(section "$README" '^### Scripts$' '^### ' \
  | strip_docblocks /dev/stdin | flatten)"
readme_region="$readme_workflow $readme_commands"

# SKILL.md: the Usage bullet list is where --open is documented today, and the
# Annotation server section is the other legitimate home.
skill_usage="$(section "$SKILL_MD" '^## Usage$' '^## ' \
  | strip_docblocks /dev/stdin | flatten)"
skill_server="$(section "$SKILL_MD" '^## Annotation server$' '^## ' \
  | strip_docblocks /dev/stdin | flatten)"
skill_region="$skill_usage $skill_server"

# =============================================================================
# Clause: both files document --serve, and describe what it does
# =============================================================================

check_serve_prose() { # <region> <label>
  local region="$1" what="$2" window

  if [ -z "$region" ]; then
    fail "$what: the region could not be located — no --serve clause can be checked"
    return
  fi

  if ! matches_f "$region" '--serve'; then
    fail "$what: --serve is never mentioned"
    fail "$what: says --serve registers the document on the shared server"
    fail "$what: says --serve prints the URL"
    fail "$what: says --serve opens nothing"
    fail "$what: says a non-zero exit means callers skip"
    return
  fi
  pass "$what: --serve is documented"

  window="$(serve_window "$region")"
  if [ -z "$window" ]; then
    fail "$what: no text could be extracted around the --serve mention"
    return
  fi

  if matches "$window" "$REGISTERS" && matches "$window" "$SHARED_SERVER"; then
    pass "$what: says --serve registers the document on the shared server"
  else
    fail "$what: says --serve registers the document on the shared server"
  fi
  has "$window" "$PRINTS_URL" "$what: says --serve prints the URL"
  has "$window" "$OPENS_NOTHING" "$what: says --serve opens nothing"
  if matches "$window" "$NONZERO" && matches "$window" "$SKIP"; then
    pass "$what: says a non-zero exit means callers skip"
  else
    fail "$what: says a non-zero exit means callers skip"
  fi

  assert_no_sibling_reference "$window" "$what --serve prose"
}

check_serve_prose "$readme_region" "README"
check_serve_prose "$skill_region" "SKILL.md"

# The usage signature a reader copies. --open is spelled out in both; --serve
# has to join it, or the flag is documented in prose the invocation contradicts.
if [ -z "$readme_scripts" ]; then
  fail "README: the '### Scripts' section could not be located — the render.sh signature cannot be checked"
elif matches "$readme_scripts" 'render\.sh.{0,60}--serve'; then
  pass "README Scripts: the render.sh signature names --serve"
else
  fail "README Scripts: the render.sh signature still lists only --open"
fi

if [ -z "$skill_usage" ]; then
  fail "SKILL.md: the '## Usage' section could not be located — the render.sh signature cannot be checked"
elif matches "$skill_usage" 'render\.sh.{0,60}--serve'; then
  pass "SKILL Usage: the render.sh signature names --serve"
else
  fail "SKILL Usage: the render.sh signature still lists only --open"
fi

# =============================================================================
# Invariant: what these files already say about --open survives untouched.
# --serve is an addition, not a rewrite; the block that added the fixed-port
# server owns this prose and nothing here may quietly restate it.
# =============================================================================

# The pinned claims carry literal markdown backticks; nothing should expand.
# shellcheck disable=SC2016
for lit in \
  'Falls back to a plain `file://` open when python3 is unavailable' \
  'the first `--open` call binds it, every later call on the machine reuses it'; do
  if matches_f "$skill_usage" "$lit"; then
    pass "SKILL Usage: existing --open claim intact — $lit"
  else
    fail "SKILL Usage: existing --open claim changed or lost — $lit"
  fi
done

if matches "$readme_scripts" '27183' && matches "$readme_scripts" 'RENDER_DOC_PORT'; then
  pass "README Scripts: the fixed port and its override are still documented"
else
  fail "README Scripts: the fixed port or RENDER_DOC_PORT override was lost"
fi

# =============================================================================
# Clause: the version legs
# =============================================================================

if ! command -v jq > /dev/null 2>&1; then
  fail "jq not found — the version legs cannot be checked"
else
  pj_version="$(jq -r '.version' "$PLUGIN_JSON" 2> /dev/null)"
  if [ -z "$pj_version" ] || [ "$pj_version" = "null" ]; then
    fail "plugin.json: version missing or unparseable"
  elif [ "$(printf '%s\n%s\n' "$VERSION_FLOOR" "$pj_version" | sort -V | head -1)" = "$VERSION_FLOOR" ]; then
    pass "plugin.json: version is $pj_version (>= $VERSION_FLOOR)"
  else
    fail "plugin.json: version is '$pj_version', expected $VERSION_FLOOR or later"
  fi

  # Byte-exact description, pinned as of the pre-B08 tree: this block bumps the
  # version, it does not restate what the plugin is.
  EXPECTED_DESC='Render a planning or decision markdown file into a single self-contained dark-theme HTML view, with an annotation server whose in-page composer writes @TAG: feedback lines back into the source markdown.'
  pj_desc="$(jq -r '.description' "$PLUGIN_JSON" 2> /dev/null)"
  if [ "$pj_desc" = "$EXPECTED_DESC" ]; then
    pass "plugin.json: description byte-unchanged"
  else
    fail "plugin.json: description changed (expected byte-unchanged)"
  fi

  # Anchored on the render-doc row so a sibling plugin's row can never satisfy
  # it. readme-lint pairs this cell with plugin.json, so both legs are pinned:
  # the floor (this block's bump actually happened) and the agreement (the two
  # never drift apart).
  root_row="$(grep -E '^\| *\[render-doc\]\(plugins/render-doc/\) *\|' "$ROOT_README" || true)"
  if [ -z "$root_row" ]; then
    fail "root README: render-doc plugins-table row not found — the version cell cannot be checked"
  else
    pass "root README: render-doc plugins-table row found"
    root_row_version="$(printf '%s' "$root_row" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -z "$root_row_version" ]; then
      fail "root README: render-doc row has no vX.Y.Z version cell"
    elif [ "$(printf '%s\n%s\n' "$VERSION_FLOOR" "${root_row_version#v}" | sort -V | head -1)" = "$VERSION_FLOOR" ]; then
      pass "root README: render-doc row version is $root_row_version (>= v$VERSION_FLOOR)"
    else
      fail "root README: render-doc row version is '$root_row_version', expected v$VERSION_FLOOR or later"
    fi
    if [ "$root_row_version" = "v$pj_version" ]; then
      pass "root README: render-doc row version $root_row_version matches plugin.json"
    else
      fail "root README: render-doc row version is '${root_row_version:-missing}', expected v$pj_version to match plugin.json"
    fi
    if matches_f "$root_row" '✅'; then
      pass "root README: render-doc row keeps the ✅ status marker"
    else
      fail "root README: render-doc row lost the ✅ status marker"
    fi
  fi
fi

# =============================================================================
# Left to acceptance review
# =============================================================================
# Whether the new prose is ACCURATE — that --serve really registers, really
# prints that URL, and really opens nothing — is serve-mode.test.sh's job
# against the shipped script; these anchors prove the claims are present and in
# the right place, not that they are true. Two judgement calls also stay with
# the orchestrator: whether the README "### Failure modes" table should gain a
# --serve row (the block map does not require one), and whether the mutual
# exclusion of --open and --serve is worth stating for readers.

# --- Summary ------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'serve-mode-docs.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'serve-mode-docs.test.sh: all assertions passed\n'
