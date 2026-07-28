#!/bin/bash
# Structural/content tests for B03 updates-plugin-manifest.
#
# Source of truth: the HTML-comment docblock "Contract: B03
# updates-plugin-manifest" at the top of plugins/updates/README.md.
#
# Covers plugins/updates/.claude-plugin/plugin.json:
#   - valid JSON; .name "updates"; .version well-formed semver and >= 0.1.0
#     (a floor, not a pin: version-bump-lint requires a bump for ANY content
#     change to the plugin, so an exact pin here would fail every such change)
#   - .description non-empty, names /updates:run, and is a single sentence
#     (exactly one period, trailing)
#   - .author byte-identical (jq -Sc) to marketplace.json's .owner (single
#     source of truth, not a hardcoded copy)
#
# Covers plugins/updates/README.md against the locked template
# (plugins/PLUGIN_README_TEMPLATE.md):
#   - readme-lint (scripts/readme-lint.sh) reports PASS for this plugin
#     specifically
#   - no "NotImplemented" placeholder marker anywhere in the file
#   - a non-empty intro paragraph before "## Getting started"
#   - Getting started: both install commands, and an inert-until-
#     /updates:run statement
#   - What to expect: no hooks fire; nothing changes at install
#   - Commands: documents /updates:run (incl. its "check" mode and that it
#     is not model-invocable), scripts/check-versions.sh usage, and a
#     pointer to docs/setup-stamps.md
#   - Relationships to other plugins: names the five setup-stamp plugins
#     (attribution, privacy, settings, statusline, landing) as soft
#     integrations, and states the plugin degrades gracefully without them
#   - Uninstalling: the uninstall command, and a note that
#     ~/.claude/clam-setup-stamps.json is not removed
#
# RED/GREEN at birth (scaffold state, see brief 01-test-B03.md):
#   - All plugin.json checks are GREEN already: the manifest landed at
#     scaffold with its full contracted content (for marketplace-lint
#     parity), so these assert an existing invariant rather than driving
#     new work.
#   - The "readme-lint PASS" check is ALSO green already: readme-lint only
#     enforces heading presence/order/placement, which the scaffolded
#     placeholder README already satisfies (all six required H2s, correct
#     order, no extras). It stays in this suite because it is a real
#     contract invariant, not because it drives implementation.
#   - Every other README check is RED against the current placeholder:
#     the body under each heading is only an HTML "NotImplemented: B03"
#     comment, so no section states its required facts yet.
#
# Content checks are scoped to each README section's rendered text (HTML
# comments stripped first) rather than matching anywhere in the file. This
# matters here specifically: unlike a bare `sed '/<!--/,/-->/d'` (which
# mishandles a same-line "<!-- ... -->" comment by continuing to hunt for
# the NEXT "-->" instead of closing on the same line — verified empirically
# to silently swallow real headings when several such comments appear in
# sequence, exactly the placeholder's shape), strip_comments() below is a
# small per-line state machine that closes same-line comments correctly.
# This also guards against a vacuous pass: the top Contract docblock
# itself narrates most of the facts this suite checks for (it has to, to
# specify them) — scoring against raw text would let the docblock's own
# prose satisfy a check with no real content written. Only the
# NotImplemented-anywhere check intentionally reads the raw file, since
# that invariant is "anywhere in the file" by contract, comments included.
#
# Tests only the public artifacts (JSON fields, rendered README prose) —
# never implementation-internal structure. Hermetic: reads only the repo's
# own committed files, no network, no mutation, cwd-independent (all paths
# resolved from this script's own location).
#
# Run: bash plugins/updates/scripts/manifest.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."
REPO_ROOT="$SCRIPT_DIR/../../.."
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
README="$PLUGIN_ROOT/README.md"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

nonblank() { # string -> "yes"/"no"
  if [[ -n "$(printf '%s' "$1" | tr -d '[:space:]')" ]]; then echo yes; else echo no; fi
}

# Removes HTML comments from a file's content, line by line, correctly
# closing a comment that opens and closes on the same line (unlike a naive
# `sed '/<!--/,/-->/d'` range, which keeps hunting for the next "-->" and
# can swallow real content between successive same-line comments). Blank
# lines are left in comments' place so line-based extraction downstream is
# unaffected by comment removal.
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

# Extracts the body of a level-2 markdown section from already-stripped
# content: everything after a line matching $2 exactly, up to (not
# including) the next "## " heading or end of content.
section_body() { # stripped_content heading_line_exact
  awk -v heading="$2" '
    $0 == heading {found=1; next}
    found && /^## / {exit}
    found {print}
  ' <<< "$1"
}

# ---------------------------------------------------------------------------
# plugin.json
# ---------------------------------------------------------------------------

check "plugin.json is valid JSON" \
  "$(jq -e . "$PLUGIN_JSON" >/dev/null 2>&1 && echo yes || echo no)" "yes"

name=$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .name is 'updates'" "$name" "updates"

version=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
# A floor, not a pin — version-bump-lint requires a bump for any content
# change to plugins/updates/, so a bump for unrelated reasons must not make
# this clause regress. Same idiom as render-budget.test.sh's clause4.
check "plugin.json .version is well-formed semver and >= 0.1.0" \
  "$([[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
     && [[ "$(printf '0.1.0\n%s\n' "$version" | sort -V | head -n1)" == "0.1.0" ]] \
     && echo yes || echo no)" "yes"

description=$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is non-empty" \
  "$([[ -n "$description" ]] && echo yes || echo no)" "yes"

check "plugin.json .description names /updates:run" \
  "$(grep -qF '/updates:run' <<< "$description" && echo yes || echo no)" "yes"

desc_sans_trailing_period="${description%.}"
check "plugin.json .description is one sentence (single trailing period, no others)" \
  "$([[ "$description" == *"." && "$desc_sans_trailing_period" != *"."* ]] && echo yes || echo no)" "yes"

plugin_author=$(jq -Sc '.author' "$PLUGIN_JSON" 2>/dev/null)
marketplace_owner=$(jq -Sc '.owner' "$MARKETPLACE" 2>/dev/null)
check "plugin.json .author is byte-identical (jq -Sc) to marketplace.json .owner" \
  "$([[ -n "$plugin_author" && "$plugin_author" == "$marketplace_owner" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# README.md — whole-file invariants (raw content)
# ---------------------------------------------------------------------------

readme_raw=$(cat "$README" 2>/dev/null)

check "README has no NotImplemented placeholder marker anywhere (docblock included)" \
  "$(grep -qi 'NotImplemented' <<< "$readme_raw" && echo present || echo absent)" "absent"

readme_lint_output=$(cd "$REPO_ROOT" && bash scripts/readme-lint.sh 2>/dev/null)
check "readme-lint reports PASS for the updates plugin" \
  "$(grep -qx 'PASS  updates' <<< "$readme_lint_output" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# README.md — sections, on comment-stripped content
# ---------------------------------------------------------------------------

readme_stripped=$(strip_comments "$README")

intro=$(awk '
  $0 == "# updates" {found=1; next}
  found && /^## / {exit}
  found {print}
' <<< "$readme_stripped")
check "README has a non-empty intro paragraph before '## Getting started'" \
  "$(nonblank "$intro")" "yes"

getting_started=$(section_body "$readme_stripped" "## Getting started")
check "Getting started documents the marketplace add command" \
  "$(grep -qF '/plugin marketplace add cjdubb/clam' <<< "$getting_started" && echo yes || echo no)" "yes"
check "Getting started documents the install command" \
  "$(grep -qF '/plugin install updates@clam' <<< "$getting_started" && echo yes || echo no)" "yes"
check "Getting started states the plugin is inert until /updates:run" \
  "$(grep -qi 'inert' <<< "$getting_started" && grep -qF '/updates:run' <<< "$getting_started" && echo yes || echo no)" "yes"

what_to_expect=$(section_body "$readme_stripped" "## What to expect")
check "What to expect states no hooks fire" \
  "$(grep -qiE 'no hooks|hooks.{0,15}(never|don.t) fire' <<< "$what_to_expect" && echo yes || echo no)" "yes"
check "What to expect states nothing changes at install" \
  "$(grep -qiE 'nothing changes|changes nothing' <<< "$what_to_expect" && echo yes || echo no)" "yes"

commands=$(section_body "$readme_stripped" "## Commands")
check "Commands documents /updates:run" \
  "$(grep -qF '/updates:run' <<< "$commands" && echo yes || echo no)" "yes"
check "Commands documents /updates:run's 'check' mode" \
  "$(grep -qiE '/updates:run check|\`check\`|"check"|check mode|check-only' <<< "$commands" && echo yes || echo no)" "yes"
check "Commands states /updates:run is not model-invocable" \
  "$(grep -qiE 'not model-invocable|model.invocable.{0,10}(no|false)|disable-model-invocation|never invoked by (the )?model|cannot be invoked by (the )?model' <<< "$commands" && echo yes || echo no)" "yes"
check "Commands documents scripts/check-versions.sh usage" \
  "$(grep -qF 'check-versions.sh' <<< "$commands" && echo yes || echo no)" "yes"
check "Commands points to docs/setup-stamps.md" \
  "$(grep -qF 'setup-stamps.md' <<< "$commands" && echo yes || echo no)" "yes"

relationships=$(section_body "$readme_stripped" "## Relationships to other plugins")
check "Relationships names the 'attribution' setup-stamp plugin" \
  "$(grep -qiw 'attribution' <<< "$relationships" && echo yes || echo no)" "yes"
check "Relationships names the 'privacy' setup-stamp plugin" \
  "$(grep -qiw 'privacy' <<< "$relationships" && echo yes || echo no)" "yes"
check "Relationships names the 'settings' setup-stamp plugin" \
  "$(grep -qiw 'settings' <<< "$relationships" && echo yes || echo no)" "yes"
check "Relationships names the 'statusline' setup-stamp plugin" \
  "$(grep -qiw 'statusline' <<< "$relationships" && echo yes || echo no)" "yes"
check "Relationships names the 'landing' setup-stamp plugin" \
  "$(grep -qiw 'landing' <<< "$relationships" && echo yes || echo no)" "yes"
check "Relationships describes these as soft integrations" \
  "$(grep -qi 'soft' <<< "$relationships" && echo yes || echo no)" "yes"
check "Relationships states the plugin degrades gracefully without them" \
  "$(grep -qi 'degrad' <<< "$relationships" && echo yes || echo no)" "yes"

uninstalling=$(section_body "$readme_stripped" "## Uninstalling")
check "Uninstalling documents the uninstall command" \
  "$(grep -qF '/plugin uninstall updates@clam' <<< "$uninstalling" && echo yes || echo no)" "yes"
check "Uninstalling names the clam-setup-stamps.json stamp file" \
  "$(grep -qF 'clam-setup-stamps.json' <<< "$uninstalling" && echo yes || echo no)" "yes"
check "Uninstalling notes the stamp file is not removed" \
  "$(grep -qiE 'not removed|is not deleted|remains|persists|left (in place|untouched)' <<< "$uninstalling" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
