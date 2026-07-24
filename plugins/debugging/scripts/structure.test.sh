#!/usr/bin/env bash
# Composition-level integration test for Block B11 plugin-composition. Source
# of truth: the HTML-comment docblock titled "Contract: B11 plugin-
# composition" in plugins/debugging/README.md. B01-B10 are already
# implemented and independently tested by their own scripts/b0N-*.test.sh
# files; this file checks only:
#
#   (1) README structure — the document shape the contract requires of
#       plugins/debugging/README.md itself (H1, purpose paragraph, the exact
#       H2 set, and what each H2 section must name), and
#   (2) cross-file integrity — the composed shape that only exists once
#       every child artifact is present together: every references/*.md path
#       SKILL.md names resolves; every ${CLAUDE_PLUGIN_ROOT}/... path SKILL.md
#       or a reference names resolves to a real file in this plugin;
#       debug-session.sh's script-relative template paths exist; the
#       template headings the docs rely on match the templates exactly;
#       plugin.json / the root README version agree; marketplace.json has
#       no version field (plugin.json is the single source of truth); and
#       an end-to-end start+query smoke test produces the contracted tree
#       shape (fine-grained detail is B09's own suite's job, not this file's).
#
# README-structure checks are run against plugins/debugging/README.md with
# its own contract docblock stripped out first (sed '/<!--/,/-->/d'), so the
# docblock's prose can never satisfy a check meant for real README content.
# This is why these checks are expected to FAIL against the current
# `NotImplemented: B11` stub body and PASS once a real README satisfies the
# contract, while the cross-file checks below are expected to already PASS
# against the implemented B01-B10 children.
#
# Run: bash plugins/debugging/scripts/structure.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

README="$PLUGIN_ROOT/README.md"
SKILL="$PLUGIN_ROOT/skills/root-cause/SKILL.md"
REFS_DIR="$PLUGIN_ROOT/skills/root-cause/references"
TEMPLATES_DIR="$PLUGIN_ROOT/templates"
JOURNAL_TPL="$TEMPLATES_DIR/journal.md"
QUERY_TPL="$TEMPLATES_DIR/query-results.md"
DEBUG_SESSION_SH="$PLUGIN_ROOT/scripts/debug-session.sh"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
ROOT_README="$ROOT/README.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugins/debugging/README.md exists" "$([ -f "$README" ] && echo yes || echo no)" "yes"
check "SKILL.md exists" "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"
check "templates/journal.md exists" "$([ -f "$JOURNAL_TPL" ] && echo yes || echo no)" "yes"
check "templates/query-results.md exists" "$([ -f "$QUERY_TPL" ] && echo yes || echo no)" "yes"
check "scripts/debug-session.sh exists" "$([ -f "$DEBUG_SESSION_SH" ] && echo yes || echo no)" "yes"
check "plugin.json exists" "$([ -f "$PLUGIN_JSON" ] && echo yes || echo no)" "yes"
check "marketplace.json exists" "$([ -f "$MARKETPLACE" ] && echo yes || echo no)" "yes"
check "root README.md exists" "$([ -f "$ROOT_README" ] && echo yes || echo no)" "yes"
check "jq is available" "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ===========================================================================
# PART 1: README structure (plugins/debugging/README.md)
# ===========================================================================
# Every check in this part reads $BODY: the README with its own contract
# docblock stripped out, so the docblock's own prose can never satisfy a
# check meant for real content.

BODY="$(sed '/<!--/,/-->/d' "$README" 2>/dev/null)"

# --- H1 + purpose paragraph -------------------------------------------------

FIRST_CONTENT_LINE="$(sed '/^[[:space:]]*$/d' <<<"$BODY" | head -n1)"
check "README first content line (docblock stripped) is unindented H1 '# debugging'" \
  "$FIRST_CONTENT_LINE" "# debugging"

H1_LINE="$(grep -n '^# debugging$' <<<"$BODY" | head -n1 | cut -d: -f1)"
FIRST_H2_LINE="$(grep -n '^## ' <<<"$BODY" | head -n1 | cut -d: -f1)"
PURPOSE_HAS_TEXT="no"
if [[ -n "$H1_LINE" && -n "$FIRST_H2_LINE" && "$FIRST_H2_LINE" -gt "$((H1_LINE + 1))" ]]; then
  PURPOSE_BLOCK="$(sed -n "$((H1_LINE + 1)),$((FIRST_H2_LINE - 1))p" <<<"$BODY")"
  if grep -qE '[[:alnum:]]' <<<"$PURPOSE_BLOCK"; then
    PURPOSE_HAS_TEXT="yes"
  fi
fi
check "README has a non-empty purpose paragraph between the H1 and the first H2" \
  "$PURPOSE_HAS_TEXT" "yes"

# --- H2 structure matches the locked template -------------------------------
# Required, in exactly this order: Getting started, What to expect, Common
# workflows, Commands, Relationships to other plugins, Uninstalling. Any
# extra H2 (## Tests, plugin-specific sections) may appear only between
# Commands and Relationships to other plugins.

REQUIRED_H2S="Getting started
What to expect
Common workflows
Commands
Relationships to other plugins
Uninstalling"

ALL_H2S="$(grep '^## ' <<<"$BODY" | sed 's/^## //')"

REQUIRED_PRESENT="yes"
while IFS= read -r req; do
  grep -qxF "$req" <<<"$ALL_H2S" || REQUIRED_PRESENT="no"
done <<<"$REQUIRED_H2S"
check "README has all six required H2 sections (Getting started, What to expect, Common workflows, Commands, Relationships to other plugins, Uninstalling)" \
  "$REQUIRED_PRESENT" "yes"

# Order: filter the doc's H2 list down to only the required headings (extras
# dropped) and compare against the canonical template order verbatim.
REQUIRED_ONLY="$(grep -xFf <(echo "$REQUIRED_H2S") <<<"$ALL_H2S")"
check "the six required H2 sections appear in template order" \
  "$REQUIRED_ONLY" "$REQUIRED_H2S"

# Extras: any H2 outside the required set must sit strictly after Commands
# and strictly before Relationships to other plugins.
COMMANDS_LINE="$(grep -n '^## Commands$' <<<"$BODY" | head -n1 | cut -d: -f1)"
RELATIONSHIPS_LINE="$(grep -n '^## Relationships to other plugins$' <<<"$BODY" | head -n1 | cut -d: -f1)"

EXTRAS_OK="yes"
if [[ -n "$COMMANDS_LINE" && -n "$RELATIONSHIPS_LINE" ]]; then
  while IFS=: read -r lineno heading; do
    grep -qxF "$heading" <<<"$REQUIRED_H2S" && continue
    if (( lineno <= COMMANDS_LINE || lineno >= RELATIONSHIPS_LINE )); then
      EXTRAS_OK="no"
    fi
  done < <(grep -n '^## ' <<<"$BODY" | sed 's/^\([0-9]*\):## /\1:/')
else
  EXTRAS_OK="no"
fi
check "every non-required H2 section (if any) appears only between Commands and Relationships to other plugins" \
  "$EXTRAS_OK" "yes"

# --- Facts preserved from the old Usage/Artifacts/Components sections -----
# The old H2s (Usage, Artifacts, Components) don't exist under the new
# template — their content relocates into Common workflows / Commands, which
# heading exactly is the implementer's placement freedom within the contract
# — but every fact they carried must still appear somewhere in the README
# per the "nothing substantive is dropped" invariant. These checks are
# body-wide on purpose: they assert the fact exists, not which heading it
# sits under.

check "README names /debugging:root-cause" \
  "$(grep -qF '/debugging:root-cause' <<<"$BODY" && echo yes || echo no)" "yes"
check "README states the skill is also model-invocable" \
  "$(grep -qiE 'model-invo' <<<"$BODY" && echo yes || echo no)" "yes"

check "README names the .local/debug/ layout root" \
  "$(grep -qF '.local/debug/' <<<"$BODY" && echo yes || echo no)" "yes"
check "README mentions journal.md" \
  "$(grep -qF 'journal.md' <<<"$BODY" && echo yes || echo no)" "yes"
check "README mentions the queries/ subdirectory" \
  "$(grep -qF 'queries/' <<<"$BODY" && echo yes || echo no)" "yes"
check "README mentions results.md" \
  "$(grep -qF 'results.md' <<<"$BODY" && echo yes || echo no)" "yes"
check "README describes the paste-back flow" \
  "$(grep -qiF 'paste-back' <<<"$BODY" && echo yes || echo no)" "yes"

# --- Components table: a table with one row per contracted component ------

check "README contains a markdown table (pipe-delimited header)" \
  "$(grep -qE '^\|.*\|[[:space:]]*$' <<<"$BODY" && echo yes || echo no)" "yes"
check "README contains a markdown table separator row" \
  "$(grep -qE '^\|[[:space:]:|-]+\|[[:space:]]*$' <<<"$BODY" && echo yes || echo no)" "yes"

TABLE_LINES="$(grep -E '^\|' <<<"$BODY")"
TABLE_DATA_ROWS="$(grep -vE '^\|[[:space:]:|-]+\|[[:space:]]*$' <<<"$TABLE_LINES" | grep -c '^|' || true)"
# First remaining pipe-line is the header; the rest are data rows.
TABLE_DATA_ROW_COUNT=$(( TABLE_DATA_ROWS > 0 ? TABLE_DATA_ROWS - 1 : 0 ))
check "component table has exactly 11 data rows (skill + 7 references + 2 templates + debug-session.sh)" \
  "$TABLE_DATA_ROW_COUNT" "11"

for token in root-cause reproduce.md what-changed.md differential-diagnosis.md \
             binary-search.md logs.md database.md prevention.md journal.md \
             query-results.md debug-session.sh; do
  check "README mentions '$token'" \
    "$(grep -qF "$token" <<<"$BODY" && echo yes || echo no)" "yes"
done

# ===========================================================================
# PART 2: Cross-file integrity (expected to already pass against B01-B10)
# ===========================================================================

# --- 2a. Every references/<name>.md path named in SKILL.md's body exists ---

ref_paths="$(grep -ohE 'references/[A-Za-z0-9._-]+\.md' "$SKILL" | sort -u)"
check "SKILL.md names at least one references/*.md path" \
  "$([ -n "$ref_paths" ] && echo yes || echo no)" "yes"

missing_refs=0
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  name="${rel#references/}"
  if [[ ! -f "$REFS_DIR/$name" ]]; then
    echo "FAIL  SKILL.md-named $rel resolves to an existing file under skills/root-cause/references/"
    FAILED=1
    missing_refs=$((missing_refs + 1))
  fi
done <<<"$ref_paths"
if [[ "$missing_refs" -eq 0 ]]; then
  echo "PASS  every references/*.md path named in SKILL.md exists under skills/root-cause/references/"
fi

# The seven contracted references are each individually named (belt-and-braces
# on top of the dynamic sweep above, since the contract names them exactly).
for ref in reproduce.md what-changed.md differential-diagnosis.md \
           binary-search.md logs.md database.md prevention.md; do
  check "SKILL.md names references/$ref" \
    "$(grep -qF "references/$ref" <<<"$ref_paths" && echo yes || echo no)" "yes"
  check "skills/root-cause/references/$ref exists" \
    "$([ -f "$REFS_DIR/$ref" ] && echo yes || echo no)" "yes"
done

# --- 2b. Every ${CLAUDE_PLUGIN_ROOT}/... path in SKILL.md or the references
#     resolves to an existing file within plugins/debugging/ -------------

plugin_root_paths="$(grep -ohE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]+' "$SKILL" "$REFS_DIR"/*.md | sort -u)"
check "SKILL.md or a reference names at least one \${CLAUDE_PLUGIN_ROOT}/... path" \
  "$([ -n "$plugin_root_paths" ] && echo yes || echo no)" "yes"

missing_plugin_root=0
while IFS= read -r token; do
  [[ -n "$token" ]] || continue
  rel="${token#\$\{CLAUDE_PLUGIN_ROOT\}/}"
  if [[ ! -f "$PLUGIN_ROOT/$rel" ]]; then
    echo "FAIL  \${CLAUDE_PLUGIN_ROOT}/$rel resolves to an existing file within plugins/debugging/"
    FAILED=1
    missing_plugin_root=$((missing_plugin_root + 1))
  fi
done <<<"$plugin_root_paths"
if [[ "$missing_plugin_root" -eq 0 ]]; then
  echo "PASS  every \${CLAUDE_PLUGIN_ROOT}/... path named in SKILL.md or the references resolves within plugins/debugging/"
fi

# --- 2c. debug-session.sh's script-relative template paths exist ----------

check "debug-session.sh's script-relative journal template exists (templates/journal.md)" \
  "$([ -f "$JOURNAL_TPL" ] && echo yes || echo no)" "yes"
check "debug-session.sh's script-relative query-results template exists (templates/query-results.md)" \
  "$([ -f "$QUERY_TPL" ] && echo yes || echo no)" "yes"
check "debug-session.sh references ../templates/journal.md relative to its own location" \
  "$(grep -qF '$SCRIPT_DIR/../templates' "$DEBUG_SESSION_SH" && echo yes || echo no)" "yes"

# --- 2d. Template headings cited across the docs match the templates ------

journal_h2s="$(grep '^## ' "$JOURNAL_TPL" | sed 's/^## //')"
for name in Hypotheses "Probe Log" Queries Prevention; do
  check "templates/journal.md has an H2 named '$name'" \
    "$(grep -qxF "$name" <<<"$journal_h2s" && echo yes || echo no)" "yes"
done

check "templates/journal.md Hypotheses table header row matches exactly" \
  "$(grep -qxF '| # | Hypothesis | Evidence for | Evidence against | Status |' "$JOURNAL_TPL" && echo yes || echo no)" "yes"
check "templates/journal.md Probe Log table header row matches exactly" \
  "$(grep -qxF '| When | Probe | Expected | Observed |' "$JOURNAL_TPL" && echo yes || echo no)" "yes"

query_h2s="$(grep '^## ' "$QUERY_TPL" | sed 's/^## //')"
for name in Results Interpretation; do
  check "templates/query-results.md has an H2 named '$name'" \
    "$(grep -qxF "$name" <<<"$query_h2s" && echo yes || echo no)" "yes"
done

# --- 2e. plugin.json parses; name/version agree across surfaces -----------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "plugin.json name is 'debugging'" \
  "$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null)" "debugging"

PLUGIN_VERSION="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"

check "plugin.json .version is non-empty" \
  "$([ -n "$PLUGIN_VERSION" ] && echo yes || echo no)" "yes"

ROOT_README_ROW="$(grep -E '^\|.*\[debugging\]\(plugins/debugging/\).*\|' "$ROOT_README" | head -n1)"
ROOT_README_VERSION="$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' <<<"$ROOT_README_ROW" | head -n1 | sed 's/^v//')"

check "plugin.json .version agrees with the root README debugging row (single source of truth)" \
  "$PLUGIN_VERSION" "$ROOT_README_VERSION"
check "marketplace.json debugging entry has no version field (plugin.json is single source of truth)" \
  "$(jq -e '.plugins[]? | select(.name=="debugging") | .version' "$MARKETPLACE" >/dev/null 2>&1 && echo present || echo absent)" "absent"

check "root README.md has a debugging row" \
  "$([ -n "$ROOT_README_ROW" ] && echo yes || echo no)" "yes"
check "plugin.json version matches the root README debugging row's version" \
  "$PLUGIN_VERSION" "$ROOT_README_VERSION"

# ===========================================================================
# PART 3: End-to-end artifact smoke test (composed shape only; B09 owns
# per-flag/error/numbering detail).
# ===========================================================================

SMOKE_TMP="$(mktemp -d)"
trap 'rm -rf "$SMOKE_TMP"' EXIT
mkdir -p "$SMOKE_TMP/.local"

START_OUT="$(cd "$SMOKE_TMP" && bash "$DEBUG_SESSION_SH" start smoke-test 2>"$SMOKE_TMP/.start.err")"
START_RC=$?
check "smoke: start exits 0" "$START_RC" "0"

SESSION_DIR="$SMOKE_TMP/$START_OUT"
check "smoke: start created a session dir" \
  "$([ -d "$SESSION_DIR" ] && echo yes || echo no)" "yes"
check "smoke: session dir matches .local/debug/NNN-smoke-test shape" \
  "$(grep -qE '^\.local/debug/[0-9]{3}-smoke-test$' <<<"$START_OUT" && echo yes || echo no)" "yes"
check "smoke: session dir contains a journal.md copy" \
  "$([ -f "$SESSION_DIR/journal.md" ] && echo yes || echo no)" "yes"
check "smoke: session journal.md matches templates/journal.md byte-for-byte" \
  "$(cmp -s "$SESSION_DIR/journal.md" "$JOURNAL_TPL" && echo yes || echo no)" "yes"
check "smoke: session dir contains an empty queries/ subdir" \
  "$([ -d "$SESSION_DIR/queries" ] && [ -z "$(ls -A "$SESSION_DIR/queries" 2>/dev/null)" ] && echo yes || echo no)" "yes"

QUERY_OUT="$(cd "$SMOKE_TMP" && bash "$DEBUG_SESSION_SH" query "$START_OUT" first-query 2>"$SMOKE_TMP/.query.err")"
QUERY_RC=$?
check "smoke: query exits 0" "$QUERY_RC" "0"

QUERY_DIR="$SMOKE_TMP/$QUERY_OUT"
check "smoke: query dir matches queries/NN-first-query shape" \
  "$(grep -qE '/queries/[0-9]{2}-first-query$' <<<"$QUERY_OUT" && echo yes || echo no)" "yes"
check "smoke: query dir contains a query file" \
  "$(glob_match=$(compgen -G "$QUERY_DIR/query.*") ; [ -n "$glob_match" ] && echo yes || echo no)" "yes"
check "smoke: query dir contains results.md" \
  "$([ -f "$QUERY_DIR/results.md" ] && echo yes || echo no)" "yes"
check "smoke: query results.md matches templates/query-results.md byte-for-byte" \
  "$(cmp -s "$QUERY_DIR/results.md" "$QUERY_TPL" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
