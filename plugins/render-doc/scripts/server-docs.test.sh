#!/usr/bin/env bash
# server-docs.test.sh — verifies the "Contract: B05 server docs and version"
# comment in plugins/render-doc/README.md, plus the clauses of that block that
# land in skills/render/SKILL.md, clause by clause.
#
# This block's deliverable is prose, so every assertion here is a TOKEN or an
# ANCHOR, never a sentence: the retired-design tokens must be absent, the
# fixed-port facts must be present as tokens, and each fact must appear under
# the heading that owns it. Wording, ordering and paragraph shape are the
# implementer's to choose. Where a clause is really about meaning rather than
# tokens (the Uninstalling instruction, the "no user action needed" claim in
# the serve.py entry), only the mechanical half is asserted and the remainder
# is named in the test report as left to review.
#
# Section scoping is deliberate. A token found somewhere in a 270-line README
# is weak evidence; the same token under "### Scripts" or "## Uninstalling" is
# the claim the contract actually makes. Sections are extracted into $WORK and
# asserted individually; a section that cannot be found fails once, with its
# own message, instead of cascading into a dozen confusing failures.
#
# The comment trap: BOTH contract comments quote the retired-design tokens
# verbatim (they are telling the implementer what to delete), so a naive scan
# of either file would go green the moment the comment is deleted even if the
# body prose still described the retired server. Every content assertion below
# therefore runs against a comment-stripped copy — the render.test.sh /
# workgraph-docs.test.sh precedent, sed '/<!--/,/-->/d' — and the one check
# that reads the RAW file is the "Contract: B05 marker is gone" pair, which is
# this block's acceptance signal and is only meaningful unstripped.
#
# Deliberately NOT asserted here, because another suite already gates it:
#   render.test.sh          — SKILL.md frontmatter `name: render`, the
#                             ${CLAUDE_PLUGIN_ROOT}/scripts/render.sh usage
#                             reference, "no clam-code-era path" in either
#                             visible body, README's python3 and file://
#                             mentions.
#   readme-lint.sh, plugin-readme-template.test.sh — README template
#                             conformance (headings, their order and place).
#   workgraph-docs.test.sh  — the plugin version floor and the root README
#                             table agreeing with plugin.json. The version
#                             bump named in the B05 contract text landed in
#                             the scaffold commit (version-bump-lint reads
#                             committed state), so a version assertion here
#                             would be vacuously green from the first run.
#
# Not asserted for a different reason — over-specification: the state file is
# banned only as its literal path, not as the phrase "state file", because a
# faithful rewrite may legitimately say there is no longer one; likewise no
# idle-timeout wording is banned beyond the "30 minutes" interval itself,
# since "no automatic shutdown" is a fact the contract requires to be STATED.

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
README="$PLUGIN_DIR/README.md"
SKILL_MD="$PLUGIN_DIR/skills/render/SKILL.md"

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
summary() {
  if [ "$FAILURES" -gt 0 ]; then
    printf 'server-docs.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
    exit 1
  fi
  printf 'server-docs.test.sh: all assertions passed\n'
  exit 0
}

# --- Helpers -----------------------------------------------------------------

strip_docblocks() { sed '/<!--/,/-->/d' "$1"; }

# section <file> <heading-ere> [<stop-ere>] — print the lines below the first
# heading matching <heading-ere>, up to (not including) the next line matching
# <stop-ere> (default: any markdown heading). Headings inside fenced code
# blocks are ignored in both roles, so a `# comment` line in an example block
# cannot truncate a section.
section() {
  awk -v pat="$2" -v stop="${3:-^#}" '
    /^(```|~~~)/ { fence = !fence }
    !p { if (!fence && $0 ~ pat) p = 1; next }
    p && !fence && $0 ~ stop { exit }
    p
  ' "$1"
}

# Both files are hard-wrapped prose, so a two-word pattern would miss simply
# because the author's line broke between the words — and an implementer would
# get a red with no defensible reason. Every whole-text scan below therefore
# runs over a newline-flattened copy (the plugin-readme-template.test.sh
# precedent). Flattening only ever makes a negative assertion stricter: for a
# banned pattern to trip falsely, its two halves would have to sit adjacent
# across the wrap, which is the occurrence the ban is meant to catch anyway.
flatten() { tr '\n' ' ' < "$1"; }

# Anchor lines for window_has. The anchor is matched case-insensitively unless
# the caller asks for "case-exact", which exists for one reason: an anchor that
# is an HTTP header name, not an English word.
wh_anchor_lines() { # <file> <anchor-ere> <mode>
  if [ "$3" = "case-exact" ]; then
    grep -nE "$2" "$1"
  else
    grep -niE "$2" "$1"
  fi
}

# window_has <file> <anchor-ere> <needle-ere> <radius> [case-exact] — true when
# some line matching <anchor-ere> has <needle-ere> within +/- <radius> lines,
# the window flattened before matching. Keeps the "these two facts belong
# together" checks from pinning one line layout, and stops a token from
# satisfying a clause it has nothing to do with (README's retired registration
# prose says "deterministic" about an ID, not about a URL).
#
# The needle is always case-insensitive. So is the anchor, unless the fifth
# argument is the literal "case-exact" — which the Host-pinning pair passes,
# because a case-insensitive `Host` matches the "host" inside "localhost" and
# inside ordinary prose like "on this host". Combined with $HOST_HEADER's word
# boundaries that is what stops "binds 127.0.0.1 (localhost)" — the single most
# natural sentence in this section — from green-lighting a section that never
# documents Host pinning at all.
window_has() {
  wh_file="$1"
  wh_anchor="$2"
  wh_needle="$3"
  wh_radius="$4"
  wh_mode="${5:-}"
  while IFS= read -r wh_n; do
    [ -n "$wh_n" ] || continue
    wh_lo=$((wh_n - wh_radius))
    [ "$wh_lo" -lt 1 ] && wh_lo=1
    wh_hi=$((wh_n + wh_radius))
    if sed -n "${wh_lo},${wh_hi}p" "$wh_file" | tr '\n' ' ' | grep -qiE "$wh_needle"; then
      return 0
    fi
  done < <(wh_anchor_lines "$wh_file" "$wh_anchor" "$wh_mode" | cut -d: -f1)
  return 1
}

has() { # <file> <ere> <label>
  if flatten "$1" | grep -qiE -- "$2"; then pass "$3"; else fail "$3"; fi
}

has_exact() { # <file> <ere> <label> — case-sensitive
  if flatten "$1" | grep -qE -- "$2"; then pass "$3"; else fail "$3"; fi
}

not_has() { # <file> <ere> <label>
  if flatten "$1" | grep -qiE -- "$2"; then fail "$3"; else pass "$3"; fi
}

near() { # <file> <anchor-ere> <needle-ere> <radius> <label> [case-exact]
  if window_has "$1" "$2" "$3" "$4" "${6:-}"; then pass "$5"; else fail "$5"; fi
}

non_empty() { # <file> <label>
  if [ -s "$1" ]; then
    pass "$2"
    return 0
  fi
  fail "$2"
  return 1
}

# Sibling plugin directory names, discovered from the tree rather than
# hardcoded — the workgraph-docs.test.sh precedent. A literal sibling name in
# this file's own source would itself be a reference and would be flagged by
# architecture-lint, so the vocabulary is a runtime value from `find`.
sibling_plugins() {
  find "$REPO_ROOT/plugins" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2> /dev/null \
    | grep -vFx "$(basename "$PLUGIN_DIR")" | sort
}

# Fails when <file> contains a genuine reference (any of the four forms
# ARCHITECTURE.md defines) to a sibling plugin. Scoped to the regions THIS
# block rewrites, never whole files: README's "## Relationships to other
# plugins" section legitimately names a consumer and is untouched here.
no_sibling_reference() { # <file> <label>
  local hit="" p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if grep -qiE "/${p}:|${p}@clam|plugins/${p}/|${p}[[:space:]]plugin" "$1"; then
      hit="$p"
      break
    fi
  done < <(sibling_plugins)
  if [ -n "$hit" ]; then
    fail "$2: names a sibling plugin (reference form found — see CLAUDE.md's layering rule)"
  else
    pass "$2: names no sibling plugin"
  fi
}

# --- Vocabulary --------------------------------------------------------------
# Retired-design tokens. Each is the concrete artifact the contract names, not
# a paraphrase of it, so a sentence that merely mentions the retired concept in
# order to say it is gone cannot trip them.
RETIRED_STATE_FILE='render-doc-serve\.json' # the state file, in any role
RETIRED_REGISTER='/register'                # POST /register + the registration gate
RETIRED_DOC_URL='/d/'                       # /d/<id> document URLs
RETIRED_IDLE='30[[:space:]-]*min'           # "auto-shuts down after 30 minutes"
RETIRED_SERVE_ARG='serve\.py[[:space:]]+[<[]' # serve.py taking a state-file argument

# Fixed-port facts, each as an alternation so a faithful rewrite is not forced
# into one word. These are the contract's own vocabulary plus the synonyms a
# reasonable technical writer would reach for. Multi-word alternatives spell
# their gap as $WS rather than a literal space, so they survive both a hard
# wrap (flattened to one space) and an indented continuation line.
WS='[[:space:]]+'
LOCK="lock|singleton|wins|exclusiv|eaddrinuse|only${WS}one|exactly${WS}one|already${WS}bound|never${WS}fight"
DETERMINISTIC="determinist|stable|restart|survive|unchanged|same${WS}url"
RERENDER="re-?render|regenerat|stale|newer|out${WS}of${WS}date|up[-[:space:]]to[-[:space:]]date"
HOME_SCOPE="\\\$HOME|home${WS}director"
WORKTREE_SCOPE="worktree|git${WS}repo"
REALPATH_SCOPE="realpath|real${WS}path|resolv|symlink|canonical"
FOREIGN_PROCESS="(another|other|foreign|unrelated|different)${WS}(process|program|service|application|app)"

# The HTTP header name as a standalone word, never the "host" inside
# "localhost" or "on this host". The boundary groups are the repo's own idiom
# (scripts/architecture-lint.sh's BOUNDARY_BEFORE/AFTER) and stay POSIX ERE, so
# no \b portability question arises. Always passed with "case-exact".
HOST_HEADER='(^|[^[:alnum:]])Host([^[:alnum:]]|$)'

# "nothing stops the server for you; it runs until you stop it." Three tiers:
#   - words with no other referent in this domain, allowed to stand alone:
#     reboot, indefinitely, forever;
#   - phrases that already carry the whole claim: keeps/stays running, nothing
#     stops, never shuts, does not stop, no automatic/idle shutdown-or-timeout;
#   - words that are ordinary English on their own and are therefore admitted
#     ONLY beside a stop verb, within one sentence ([^.] cannot cross a full
#     stop): until, manual, explicit, by hand. Each of these has a live and
#     unrelated referent in the very sections this is asserted over — "wait
#     until the render finishes", "remove the rendered .html files manually",
#     "an explicit /render-doc:render invocation", "set RENDER_DOC_PORT
#     explicitly" — so unbound they would pass on prose saying nothing about
#     the server's lifetime at all.
STOP_VERB='kill|stop|shut|terminat'
NO_AUTO_STOP="reboot|indefinitely|forever|keeps${WS}running|stays${WS}running|nothing${WS}stops|never${WS}(shuts|stops)|does${WS}not${WS}(shut|stop)|no${WS}(automatic|idle)[[:alnum:] -]{0,20}(shut|stop|timeout)|(until|manual|explicit|by${WS}hand)[^.]{0,60}(${STOP_VERB})|(${STOP_VERB})[^.]{0,60}(until|manual|explicit|by${WS}hand)"

# --- Stripped copies ---------------------------------------------------------

README_BODY="$WORK/README.stripped.md"
SKILL_BODY="$WORK/SKILL.stripped.md"
strip_docblocks "$README" > "$README_BODY"
strip_docblocks "$SKILL_MD" > "$SKILL_BODY"

if [ ! -s "$README_BODY" ] || [ ! -s "$SKILL_BODY" ]; then
  fail "setup: a stripped copy of README.md or SKILL.md came out empty — no clause could be checked"
  summary
fi
pass "setup: both files stripped of their HTML comments"

# The strip is what makes every negative assertion below meaningful. Prove it
# worked rather than assuming it: pre-implementation the contract comments are
# present in the raw files and must be absent from the stripped copies.
if grep -qF 'Contract: B05' "$README_BODY" || grep -qF 'Contract: B05' "$SKILL_BODY"; then
  fail "sanity: the contract comment survived the strip — the sed range needs adjusting"
else
  pass "sanity: contract comments stripped from both bodies"
fi

# =============================================================================
# Acceptance signal: the contract comments themselves are gone. Read RAW, on
# purpose — this is the one assertion the strip would defeat.
# =============================================================================

if grep -qF 'Contract: B05' "$README"; then
  fail "README.md: 'Contract: B05' comment still present (deleting it is part of the work)"
else
  pass "README.md: 'Contract: B05' comment removed"
fi
if grep -qF 'Contract: B05' "$SKILL_MD"; then
  fail "SKILL.md: 'Contract: B05' comment still present (deleting it is part of the work)"
else
  pass "SKILL.md: 'Contract: B05' comment removed"
fi

# =============================================================================
# Clause: the retired design is GONE from both visible bodies
# =============================================================================

not_has "$README_BODY" "$RETIRED_STATE_FILE" "README.md: no /tmp state file"
not_has "$README_BODY" "$RETIRED_REGISTER" "README.md: no /register route or registration gate"
not_has "$README_BODY" "$RETIRED_DOC_URL" "README.md: no /d/<id> document URL"
not_has "$README_BODY" "$RETIRED_IDLE" "README.md: no 30-minute idle-shutdown promise"
not_has "$README_BODY" "$RETIRED_SERVE_ARG" "README.md: serve.py documented with no state-file argument"

not_has "$SKILL_BODY" "$RETIRED_STATE_FILE" "SKILL.md: no /tmp state file"
not_has "$SKILL_BODY" "$RETIRED_REGISTER" "SKILL.md: no /register route or registration gate"
not_has "$SKILL_BODY" "$RETIRED_DOC_URL" "SKILL.md: no /d/<id> document URL"
not_has "$SKILL_BODY" "$RETIRED_IDLE" "SKILL.md: no 30-minute idle-shutdown promise"
not_has "$SKILL_BODY" "$RETIRED_SERVE_ARG" "SKILL.md: serve.py documented with no state-file argument"

# =============================================================================
# Clause: README's script reference describes the fixed-port server
# The serve.py entry lives under "### Scripts"; that is where a reader looks
# for what the script is and how it behaves, and where the retired prose sits
# today. Facts about degradation are checked one level up (see below), because
# the Failure modes table is an equally good home for them.
# =============================================================================

RM_SCRIPTS="$WORK/readme.scripts"
section "$README_BODY" '^### Scripts$' > "$RM_SCRIPTS"

if non_empty "$RM_SCRIPTS" "README.md: '### Scripts' section found"; then
  has "$RM_SCRIPTS" '27183' "README Scripts: names the fixed port 27183"
  has_exact "$RM_SCRIPTS" 'RENDER_DOC_PORT' "README Scripts: names the RENDER_DOC_PORT override"
  has "$RM_SCRIPTS" '/doc/' "README Scripts: names the /doc/ route"
  near "$RM_SCRIPTS" 'bind' "$LOCK" 4 \
    "README Scripts: the bind itself is stated as the singleton lock"
  near "$RM_SCRIPTS" '/doc' "$DETERMINISTIC" 4 \
    "README Scripts: the /doc URL is stated to be deterministic / to survive restarts"
  near "$RM_SCRIPTS" '/doc' "$RERENDER" 4 \
    "README Scripts: a stale sibling .html is stated to be re-rendered on demand"
  has "$RM_SCRIPTS" "$HOME_SCOPE" "README Scripts: scope rule — under \$HOME"
  has "$RM_SCRIPTS" "$WORKTREE_SCOPE" "README Scripts: scope rule — inside a git worktree"
  has "$RM_SCRIPTS" "$REALPATH_SCOPE" "README Scripts: scope rule — checked on the realpath"
  near "$RM_SCRIPTS" "$HOST_HEADER" '127\.0\.0\.1' 2 \
    "README Scripts: Host pinned to 127.0.0.1:<port>" case-exact
  no_sibling_reference "$RM_SCRIPTS" "README Scripts"
fi

# The degradation paths: file:// everywhere the server cannot be reached or
# trusted, including a foreign process sitting on the port. Scoped to the whole
# "## Commands" chapter, since the serve.py entry and the Failure modes table
# are both legitimate homes for them.
RM_COMMANDS="$WORK/readme.commands"
section "$README_BODY" '^## Commands$' '^## ' > "$RM_COMMANDS"

if non_empty "$RM_COMMANDS" "README.md: '## Commands' section found"; then
  has "$RM_COMMANDS" 'file://' "README Commands: the file:// degradation path is documented"
  has "$RM_COMMANDS" "$FOREIGN_PROCESS" \
    "README Commands: a foreign process holding the port is documented as a degradation path"
fi

# =============================================================================
# Clause: Uninstalling says how the server is stopped, now that nothing stops
# it automatically. The mechanical half is asserted here — the retired tokens
# are absent, the section still talks about the server, and it names both a
# stop action and the fact that stopping is the reader's job. Whether the
# instruction it gives actually works is left to review.
# =============================================================================

RM_UNINSTALL="$WORK/readme.uninstalling"
section "$README_BODY" '^## Uninstalling$' > "$RM_UNINSTALL"

if non_empty "$RM_UNINSTALL" "README.md: '## Uninstalling' section found"; then
  not_has "$RM_UNINSTALL" "$RETIRED_STATE_FILE" \
    "README Uninstalling: no longer points the reader at the state file"
  not_has "$RM_UNINSTALL" "$RETIRED_IDLE" \
    "README Uninstalling: no longer promises a 30-minute self-shutdown"
  has "$RM_UNINSTALL" 'server' "README Uninstalling: still addresses the annotation server"
  has "$RM_UNINSTALL" 'kill|pkill' "README Uninstalling: names how to stop the server"
  near "$RM_UNINSTALL" 'server' "$NO_AUTO_STOP" 4 \
    "README Uninstalling: states that the server runs until it is stopped (no automatic shutdown)"
  no_sibling_reference "$RM_UNINSTALL" "README Uninstalling"
fi

# =============================================================================
# Clause: Maintenance and Tests list every test file the plugin now ships.
# The expected list is discovered from the tree, not hardcoded: the point of
# the clause is that the list cannot rot, and a hardcoded list here would rot
# in exactly the same way. ci.sh discovers scripts/ and lib/, so this does too.
#
# The completeness half is pinned to "## Tests", not to Maintenance-or-Tests:
# "## Tests" is the runnable list a reader copies, so a suite missing from it
# is a suite that never gets run, and a union check would let a passing mention
# in Maintenance's prose hide exactly that. Maintenance is prose about keeping
# the plugin healthy, so it is only required to point at some suite at all;
# whether it describes the right ones well is a review question.
# =============================================================================

RM_TESTS="$WORK/readme.tests"
RM_MAINT="$WORK/readme.maintenance"
section "$README_BODY" '^## Tests$' > "$RM_TESTS"
section "$README_BODY" '^### Maintenance$' > "$RM_MAINT"

mapfile -t SHIPPED_TESTS < <(
  find "$PLUGIN_DIR/scripts" "$PLUGIN_DIR/lib" -maxdepth 1 -type f -name '*.test.sh' \
    -printf '%f\n' 2> /dev/null | sort
)

if [ "${#SHIPPED_TESTS[@]}" -eq 0 ]; then
  fail "setup: no *.test.sh files discovered under the plugin — the Tests-section check cannot run"
elif non_empty "$RM_TESTS" "README.md: '## Tests' section found"; then
  for t in "${SHIPPED_TESTS[@]}"; do
    if grep -qF -- "$t" "$RM_TESTS"; then
      pass "README Tests: names $t"
    else
      fail "README Tests: does not name the shipped test file $t"
    fi
  done
  no_sibling_reference "$RM_TESTS" "README Tests"
fi

if non_empty "$RM_MAINT" "README.md: '### Maintenance' section found"; then
  has "$RM_MAINT" '\.test\.sh' "README Maintenance: still points a maintainer at a test suite"
  no_sibling_reference "$RM_MAINT" "README Maintenance"
fi

# =============================================================================
# Clause: SKILL.md's --open bullet describes the fixed-port URL
# =============================================================================

SK_USAGE="$WORK/skill.usage"
section "$SKILL_BODY" '^## Usage$' > "$SK_USAGE"

if non_empty "$SK_USAGE" "SKILL.md: '## Usage' section found"; then
  has "$SK_USAGE" '/doc/' "SKILL Usage: the --open URL is the /doc/ route"
  has "$SK_USAGE" '27183|RENDER_DOC_PORT' "SKILL Usage: names the fixed port or its override"
  has "$SK_USAGE" 'file://' "SKILL Usage: keeps the file:// fallback"
  no_sibling_reference "$SK_USAGE" "SKILL Usage"
fi

# =============================================================================
# Clause: SKILL.md's server section carries the whole fixed-port design —
# port and override, the bind as lock, deterministic re-rendering /doc/ URLs,
# realpath scope rules and Host pinning in place of registration, and no
# automatic shutdown.
# =============================================================================

SK_SERVER="$WORK/skill.server"
section "$SKILL_BODY" '^## .*[Ss]erver' > "$SK_SERVER"

if non_empty "$SK_SERVER" "SKILL.md: server section found"; then
  has "$SK_SERVER" '27183' "SKILL server: names the fixed port 27183"
  has_exact "$SK_SERVER" 'RENDER_DOC_PORT' "SKILL server: names the RENDER_DOC_PORT override"
  has "$SK_SERVER" '/doc/' "SKILL server: names the /doc/ route"
  near "$SK_SERVER" 'bind' "$LOCK" 4 \
    "SKILL server: the bind itself is stated as the singleton lock"
  near "$SK_SERVER" '/doc' "$RERENDER" 4 \
    "SKILL server: the /doc URL is stated to re-render on demand when stale"
  has "$SK_SERVER" "$HOME_SCOPE" "SKILL server: scope rule — under \$HOME"
  has "$SK_SERVER" "$WORKTREE_SCOPE" "SKILL server: scope rule — inside a git worktree"
  has "$SK_SERVER" "$REALPATH_SCOPE" "SKILL server: scope rule — checked on the realpath"
  near "$SK_SERVER" "$HOST_HEADER" '127\.0\.0\.1' 2 \
    "SKILL server: Host pinned to 127.0.0.1:<port>" case-exact
  has "$SK_SERVER" "$NO_AUTO_STOP" \
    "SKILL server: states that there is no automatic shutdown"
  no_sibling_reference "$SK_SERVER" "SKILL server section"
fi

# =============================================================================
# Invariants: this repo's genericizations survive the rewrite. Upstream's prose
# gates checkpoint rendering on an environment flag; this repo gates it on
# plugin presence, and an implementer reading upstream is the realistic way the
# flag comes back. (The skill name and the ${CLAUDE_PLUGIN_ROOT} paths are the
# other two genericizations; render.test.sh already gates both.)
# =============================================================================

not_has "$SKILL_BODY" 'CLAM_RENDER_DOC|RENDER_DOC_ENABLED|=[[:space:]]*enabled' \
  "SKILL.md: checkpoint rendering is not gated on an environment flag"

SK_CHECKPOINT="$WORK/skill.checkpoint"
section "$SKILL_BODY" '^## Checkpoint integration$' > "$SK_CHECKPOINT"

if non_empty "$SK_CHECKPOINT" "SKILL.md: '## Checkpoint integration' section found"; then
  has "$SK_CHECKPOINT" 'render-doc:render' "SKILL Checkpoint: still gates on the skill by name"
  has "$SK_CHECKPOINT" 'available|presence|installed' \
    "SKILL Checkpoint: still gates on plugin presence"
fi

# --- Summary -----------------------------------------------------------------
summary
