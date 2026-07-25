#!/bin/bash
# Structural/content tests for B05 setup-version-stamps.
#
# Source of truth: the HTML-comment docblock "Contract: B05
# setup-version-stamp — <plugin>" near the top of each of the five setup
# SKILL.md files, plus the shared format contract
# plugins/updates/docs/setup-stamps.md (read-only reference for this
# suite; not itself under test — B05 does not touch it).
#
# Covers, for each of the five setup skills:
#   plugins/attribution/skills/setup/SKILL.md
#   plugins/privacy/skills/setup/SKILL.md
#   plugins/settings/skills/setup/SKILL.md
#   plugins/statusline/skills/setup/SKILL.md
#   plugins/landing/skills/init/SKILL.md
# and each of the five plugins' plugin.json manifests.
#
# SKILL.md files are model-executed instructions, not code: the "behavior"
# under test is the rendered instruction text a model would read and act
# on, not any internal implementation. So every content check below reads
# the file with HTML comments stripped first — the B05 contract docblock
# itself narrates every fact this suite checks for (it has to, to specify
# them), so scoring against the raw file would let the docblock's own
# prose satisfy a check with no instruction text actually written. Only
# genuinely structural absence checks (e.g. "no remove heading exists")
# read the raw file, since heading structure is unaffected by comments.
#
# strip_comments() below is the same per-line state machine used in
# manifest.test.sh — NOT a naive `sed '/<!--/,/-->/d'`, which mishandles a
# same-line "<!-- ... -->" comment by continuing to hunt for the next
# "-->" instead of closing on the same line, and so silently swallows real
# content when several such comments appear in sequence (exactly this
# repo's docblock convention, and exactly these five files' shape: a B05
# docblock immediately followed by an older per-plugin contract docblock).
#
# Field-name and phrase checks (stamp record fields, atomicity, corruption
# handling, etc.) are scoped to a "stamp block": the stripped text from the
# first case-insensitive "stamp" mention through the next "## " heading (or
# EOF). This avoids two failure modes: (a) vacuous pass — words like
# "scope", "target", or "version" already appear in these files today for
# unrelated reasons (installation scope, settings target file, plugin
# version), so an unscoped search could pass before any stamping text
# exists; and (b) picking up unrelated later sections (e.g. "## Notes")
# that reuse common words. Bounding to the block starting at the first
# "stamp" mention means today — with no stamping text anywhere in the
# instructions — every block is empty, so every block-scoped check is
# correctly RED. NOTE (documented limitation, not a bug): once any
# stamping prose exists, the lone-word "at" field check is weak — "at" is
# a common preposition likely to appear near any prose about a timestamp
# regardless of whether the "at" field itself is named — so it is
# tightened to look for a quoted/coded "at" or an "at"-near-"timestamp"
# pattern rather than the bare word.
#
# RED/GREEN at birth (scaffold state, see brief 01-test-B05.md):
#   - All stamping-content checks (per-plugin instructions, field names,
#     version sourcing, failure handling, corruption handling, atomicity,
#     absent-file handling) are RED today: none of the five SKILL.md files
#     mention stamping anywhere outside their B05 contract docblock (which
#     is stripped), so every stamp_block() is empty.
#   - All five plugin.json version checks are RED today (0.1.0, expect
#     0.2.0 — except statusline, which expects 0.3.0: upstream PR #123
#     already consumed 0.2.0 for statusline's plugin.json, so B05's stamp
#     bump for statusline lands as 0.3.0 instead).
#   - The "does not reference the updates plugin as a prerequisite" check
#     is a negative invariant: true today (no such reference exists) and
#     expected to remain true after implementation. It is GREEN at birth,
#     same as the "plugin.json .author byte-identical" check in
#     manifest.test.sh — asserting an existing invariant, not driving new
#     work.
#   - Landing's "no remove subcommand" check is likewise a GREEN-at-birth
#     structural invariant expected to hold both before and after B05.
#
# Tests only the public artifact (rendered SKILL.md instruction prose) and
# plugin.json fields — never implementation-internal structure. Hermetic:
# reads only the repo's own committed files, no network, no mutation,
# cwd-independent (all paths resolved from this script's own location).
#
# Run: bash plugins/updates/scripts/stamp-conformance.test.sh
# (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

yesno() { [[ "$1" == "1" ]] && echo yes || echo no; } # 1/0 -> yes/no

# Removes HTML comments from a file's content, line by line, correctly
# closing a comment that opens and closes on the same line. See header.
strip_comments() { # file -> stdout
  awk '
    {
      line = $0
      out = ""
      while (length(line) > 0) {
        if (in_comment) {
          idx = index(line, "-->")
          if (idx > 0) { line = substr(line, idx + 3); in_comment = 0 }
          else { line = "" }
        } else {
          idx = index(line, "<!--")
          if (idx > 0) { out = out substr(line, 1, idx - 1); line = substr(line, idx + 4); in_comment = 1 }
          else { out = out line; line = "" }
        }
      }
      print out
    }
  ' "$1"
}

# Everything after a line matching $2 exactly, up to (not including) the
# next "## " heading or end of content.
section_from() { # content heading_line_exact
  awk -v heading="$2" '
    $0 == heading { found=1; next }
    found && /^## / { exit }
    found { print }
  ' <<< "$1"
}

# From the first case-insensitive "stamp" mention through the next "## "
# heading (or EOF). Empty when no "stamp" mention exists at all. See
# header for why this bound is load-bearing, not incidental.
stamp_block() { # content -> stdout
  awk '
    found && /^## / { exit }
    tolower($0) ~ /stamp/ { found=1 }
    found { print }
  ' <<< "$1"
}

# Line number (in $1) of the first line containing $2 (fixed string,
# case-insensitive), or empty if absent.
line_of() { # content needle
  grep -n -i -F -- "$2" <<< "$1" | head -1 | cut -d: -f1
}

# ---------------------------------------------------------------------------
# Per-plugin data-driven loop
# ---------------------------------------------------------------------------

PLUGINS=(attribution privacy settings statusline landing)

for name in "${PLUGINS[@]}"; do
  case "$name" in
    attribution) SKILL="$REPO_ROOT/plugins/attribution/skills/setup/SKILL.md"
                 ANCHOR='**Verify.**'
                 REMOVE_HEADING='## `/attribution:setup remove`'
                 ;;
    privacy)     SKILL="$REPO_ROOT/plugins/privacy/skills/setup/SKILL.md"
                 ANCHOR='**Verify.**'
                 REMOVE_HEADING='## `/privacy:setup remove`'
                 ;;
    settings)    SKILL="$REPO_ROOT/plugins/settings/skills/setup/SKILL.md"
                 ANCHOR='**Verify.**'
                 REMOVE_HEADING='## `/settings:setup remove`'
                 ;;
    statusline)  SKILL="$REPO_ROOT/plugins/statusline/skills/setup/SKILL.md"
                 ANCHOR='**Verify.**'
                 REMOVE_HEADING='## `/statusline:setup remove`'
                 ;;
    landing)     SKILL="$REPO_ROOT/plugins/landing/skills/init/SKILL.md"
                 ANCHOR='## Step 4 — write'
                 REMOVE_HEADING=''
                 ;;
  esac
  PLUGIN_JSON="$REPO_ROOT/plugins/$name/.claude-plugin/plugin.json"

  raw=$(cat "$SKILL" 2>/dev/null)
  stripped=$(strip_comments "$SKILL")
  block=$(stamp_block "$stripped")

  # -- generic: names the stamp file and/or the format doc ------------------
  check "$name: names clam-setup-stamps.json or setup-stamps.md as the format authority" \
    "$(grep -qiE 'clam-setup-stamps\.json|setup-stamps\.md' <<< "$stripped" && echo yes || echo no)" "yes"

  # -- generic: stamp write happens after the successful write/verify step --
  anchor_line=$(line_of "$stripped" "$ANCHOR")
  stamp_line=$(line_of "$stripped" "stamp")
  positioned="no"
  if [[ -n "$anchor_line" && -n "$stamp_line" && "$stamp_line" -gt "$anchor_line" ]]; then
    positioned="yes"
  fi
  check "$name: stamp write is conditioned on the successful write/verify step (appears after it, not before)" \
    "$positioned" "yes"

  # -- generic: stamp record fields ------------------------------------------
  check "$name: stamping instructions name the 'plugin' field" \
    "$(grep -qiw 'plugin' <<< "$block" && echo yes || echo no)" "yes"
  check "$name: stamping instructions name the 'version' field" \
    "$(grep -qiw 'version' <<< "$block" && echo yes || echo no)" "yes"
  check "$name: stamping instructions name the 'scope' field" \
    "$(grep -qiw 'scope' <<< "$block" && echo yes || echo no)" "yes"
  check "$name: stamping instructions name the 'target' field" \
    "$(grep -qiw 'target' <<< "$block" && echo yes || echo no)" "yes"
  check "$name: stamping instructions name the 'at' field (timestamp)" \
    "$(grep -qiE '\`at\`|\"at\"|\bat\b.{0,25}(timestamp|iso.?8601)|(timestamp|iso.?8601).{0,25}\bat\b' <<< "$block" && echo yes || echo no)" "yes"

  # -- generic: version sourced from installPath's plugin.json, not the -----
  # -- installed_plugins.json entry's version field -------------------------
  sourced_correctly="no"
  if grep -qi 'installpath' <<< "$block" && grep -qF 'plugin.json' <<< "$block"; then
    if grep -qiE 'never.{0,60}(installed_plugins\.json)?.{0,10}version field|not.{0,10}(the )?(installed_plugins\.json )?entry.{0,15}version|version field.{0,40}(never|not)|(installed_plugins\.json).{0,60}(never|not).{0,40}version|never from|not from' <<< "$block"; then
      sourced_correctly="yes"
    fi
  fi
  check "$name: stamped version is sourced from installPath's plugin.json, not the installed_plugins.json entry's version field" \
    "$sourced_correctly" "yes"

  # -- generic: stamp write failure reported but never fails setup ----------
  check "$name: a stamp write failure is reported but never fails the setup" \
    "$(grep -qiE 'stamp.{0,80}(fail|failure)' <<< "$block" \
        && grep -qi 'report' <<< "$block" \
        && grep -qiE 'never fail|does not fail|won.t fail|still succeed|not fail the (setup|install)' <<< "$block" \
        && echo yes || echo no)" "yes"

  # -- generic: corrupt stamp file moved aside and recreated ----------------
  check "$name: a corrupt stamp file is moved aside (.corrupt-<date>) and recreated" \
    "$(grep -qi 'corrupt' <<< "$block" \
        && grep -qF '.corrupt-' <<< "$block" \
        && grep -qiE 'recreat|start fresh|fresh (file|start)|creates? (a )?new' <<< "$block" \
        && echo yes || echo no)" "yes"

  # -- generic: atomic write (temp file + mv) --------------------------------
  check "$name: stamp writes are atomic (temp file + mv)" \
    "$(grep -qiE 'temp ?file|tmpfile|temporary file' <<< "$block" \
        && grep -qw 'mv' <<< "$block" \
        && echo yes || echo no)" "yes"

  # -- generic: absent stamp file created with the documented empty shape ---
  check "$name: an absent stamp file is created (documented empty shape)" \
    "$(grep -qiE 'absent|does not exist|missing|not (yet )?exist' <<< "$block" \
        && grep -qi 'creat' <<< "$block" \
        && echo yes || echo no)" "yes"

  # -- generic (GREEN at birth): no updates-plugin prerequisite --------------
  check "$name: setup does not reference the updates plugin as a prerequisite (behaves identically without it)" \
    "$(grep -qiE 'requires? (the )?updates plugin|updates plugin (is |must be )?required|needs? (the )?updates plugin( installed)?|depends on (the )?updates plugin|updates plugin.{0,10}(must|has to) be installed' <<< "$stripped" && echo no || echo yes)" "yes"

  # -- generic: manifest version bump ----------------------------------------
  # Floors, not pins: B05's stamp behavior shipped at 0.2.0 (statusline at
  # 0.3.0 — upstream PR #123 had already consumed 0.2.0 for its caching
  # work). Later unrelated bumps must not regress this clause, so assert a
  # well-formed semver no lower than the shipped floor, mirroring
  # render-budget.test.sh's clause 4.
  floor="0.2.0"
  [[ "$name" == "statusline" ]] && floor="0.3.0"
  mversion=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
  check "$name: plugin.json .version is a semver >= $floor (stamp bump landed)" \
    "$([[ "$mversion" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
       && [[ "$(printf '%s\n%s\n' "$floor" "$mversion" | sort -V | head -n1)" == "$floor" ]] \
       && echo yes || echo no)" "yes"

  # -- per-plugin specifics ---------------------------------------------------
  case "$name" in
    attribution|privacy|settings)
      remove_body=$(section_from "$stripped" "$REMOVE_HEADING")
      check "$name: remove subcommand deletes this plugin's stamp for the same target" \
        "$(grep -qi 'stamp' <<< "$remove_body" \
            && grep -qiE 'delet|remov' <<< "$remove_body" \
            && echo yes || echo no)" "yes"
      ;;
    statusline)
      remove_body=$(section_from "$stripped" "$REMOVE_HEADING")
      check "$name: remove subcommand deletes this plugin's stamp for the same target" \
        "$(grep -qi 'stamp' <<< "$remove_body" \
            && grep -qiE 'delet|remov' <<< "$remove_body" \
            && echo yes || echo no)" "yes"
      check "$name: stamp scope is always 'user'" \
        "$(grep -qiE '"user"|\buser\b.{0,10}scope|scope.{0,10}\buser\b|always.{0,10}\buser\b' <<< "$block" && echo yes || echo no)" "yes"
      check "$name: stamp target is ~/.claude/settings.json" \
        "$(grep -qF '~/.claude/settings.json' <<< "$block" && echo yes || echo no)" "yes"
      ;;
    landing)
      check "$name: stamp scope is 'project'" \
        "$(grep -qiE '"project"|\bproject\b.{0,10}scope|scope.{0,10}\bproject\b' <<< "$block" && echo yes || echo no)" "yes"
      check "$name: stamp target is the repo's .claude/clam-profile.jsonc" \
        "$(grep -qF 'clam-profile.jsonc' <<< "$block" && echo yes || echo no)" "yes"
      check "$name: has no remove subcommand (stale stamps for deleted profiles are documented as acceptable)" \
        "$(grep -qi '/landing:init remove' <<< "$raw" && echo no || echo yes)" "yes"
      check "$name: stale stamps for deleted/removed profiles are documented as acceptable/harmless" \
        "$(grep -qiE 'stale' <<< "$block" && grep -qiE 'accept|harmless|no.op|not (a )?problem|fine' <<< "$block" && echo yes || echo no)" "yes"
      ;;
  esac
done

echo ""
if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
