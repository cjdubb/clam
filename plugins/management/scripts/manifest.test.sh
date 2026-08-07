#!/bin/bash
# Structural/content tests for the management plugin's manifest and its
# reader-facing documentation.
#
# Three source-of-truth contracts, from three different plans. NOTE the
# block-id collision: all three are called B03, and they are unrelated.
#   1. "Contract: B03 updates-plugin-manifest" (plan 001-update-flow-for-
#      users) — plugin.json plus the README's six template sections.
#      Implemented and merged; every check for it is GREEN and stands as a
#      regression guard.
#   2. "Contract: B03 prune-wiring — README" and "Contract: B03 prune-wiring
#      — stamps doc" (plan 001-stamp-staleness-actionable, issue #239) — the
#      two middle blocks below. This suite owns the stamps-doc checks as well
#      as the README's because it is the suite that already owns
#      rendered-prose content checks for this plugin.
#   3. "Contract: B03 scope-docs" (plan 001-update-install-scope, issue #276)
#      — the check-versions.sh paragraph grows an eighth column, scope, and
#      plugin.json goes 0.4.0 -> 0.5.0. One contract docblock covers both
#      artifacts, because plugin.json is JSON and cannot carry a comment of
#      its own. Merged; its checks are now regression guards.
#   4. Repo-scoped report (issues #324 and #325) — the LAST section in this
#      file: the same paragraph grows a NINTH column, stale_installs, states
#      that the report is scoped to the repo it runs in, and states that
#      installed is the LOWEST of that repo's versions rather than the
#      highest. plugin.json goes 0.6.0 -> 0.6.1.
#
# Covers plugins/management/.claude-plugin/plugin.json:
#   - valid JSON; .name "management"; .version well-formed semver and >= 0.1.0
#     (a floor, not a pin: version-bump-lint requires a bump for ANY content
#     change to the plugin, so an exact pin here would fail every such change)
#   - .version is exactly 0.6.1 — a pin that deliberately coexists with the
#     floor above; see the repo-scoped-report block at the end for why both
#     are here
#   - .description non-empty, names /management:update, and is a single sentence
#     (exactly one period, trailing)
#   - .author byte-identical (jq -Sc) to marketplace.json's .owner (single
#     source of truth, not a hardcoded copy)
#
# Covers plugins/management/README.md against the locked template
# (plugins/PLUGIN_README_TEMPLATE.md):
#   - readme-lint (scripts/readme-lint.sh) reports PASS for this plugin
#     specifically
#   - no "NotImplemented" placeholder marker anywhere in the file
#   - a non-empty intro paragraph before "## Getting started"
#   - Getting started: both install commands, and an inert-until-
#     /management:update statement
#   - What to expect: no hooks fire; nothing changes at install
#   - Commands: documents /management:update (incl. its "check" mode and that it
#     is not model-invocable), scripts/check-versions.sh usage, and a
#     pointer to docs/setup-stamps.md
#   - Relationships to other plugins: names the five setup-stamp plugins
#     (attribution, privacy, settings, statusline, landing) as soft
#     integrations, and states the plugin degrades gracefully without them
#   - Uninstalling: the uninstall command, and a note that
#     ~/.claude/clam-setup-stamps.json is not removed
#
# Contract docblocks are not permanent: for a prose block the prose IS the
# implementation, so each contract comment carries "(remove at acceptance)"
# and is deleted once its block is accepted. No check in this file may
# therefore depend on a docblock being present. Every content check reads
# comment-stripped text, and the "no NotImplemented marker anywhere" check
# (which deliberately reads the raw file) keeps passing once the comments are
# gone.
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
# Run: bash plugins/management/scripts/manifest.test.sh (exits non-zero on
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
check "plugin.json .name is 'management'" "$name" "management"

version=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
# A floor, not a pin — version-bump-lint requires a bump for any content
# change to plugins/management/, so a bump for unrelated reasons must not make
# this clause regress. Same idiom as render-budget.test.sh's clause4.
check "plugin.json .version is well-formed semver and >= 0.1.0" \
  "$([[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
     && [[ "$(printf '0.1.0\n%s\n' "$version" | sort -V | head -n1)" == "0.1.0" ]] \
     && echo yes || echo no)" "yes"

description=$(jq -r '.description // empty' "$PLUGIN_JSON" 2>/dev/null)
check "plugin.json .description is non-empty" \
  "$([[ -n "$description" ]] && echo yes || echo no)" "yes"

check "plugin.json .description names /management:update" \
  "$(grep -qF '/management:update' <<< "$description" && echo yes || echo no)" "yes"

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
check "readme-lint reports PASS for the management plugin" \
  "$(grep -qx 'PASS  management' <<< "$readme_lint_output" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# README.md — sections, on comment-stripped content
# ---------------------------------------------------------------------------

readme_stripped=$(strip_comments "$README")

intro=$(awk '
  $0 == "# management" {found=1; next}
  found && /^## / {exit}
  found {print}
' <<< "$readme_stripped")
check "README has a non-empty intro paragraph before '## Getting started'" \
  "$(nonblank "$intro")" "yes"

getting_started=$(section_body "$readme_stripped" "## Getting started")
check "Getting started documents the marketplace add command" \
  "$(grep -qF '/plugin marketplace add cjdubb/clam' <<< "$getting_started" && echo yes || echo no)" "yes"
check "Getting started documents the install command" \
  "$(grep -qF '/plugin install management@clam' <<< "$getting_started" && echo yes || echo no)" "yes"
check "Getting started states the plugin is inert until /management:update" \
  "$(grep -qi 'inert' <<< "$getting_started" && grep -qF '/management:update' <<< "$getting_started" && echo yes || echo no)" "yes"

what_to_expect=$(section_body "$readme_stripped" "## What to expect")
check "What to expect states no hooks fire" \
  "$(grep -qiE 'no hooks|hooks.{0,15}(never|don.t) fire' <<< "$what_to_expect" && echo yes || echo no)" "yes"
check "What to expect states nothing changes at install" \
  "$(grep -qiE 'nothing changes|changes nothing' <<< "$what_to_expect" && echo yes || echo no)" "yes"

commands=$(section_body "$readme_stripped" "## Commands")
check "Commands documents /management:update" \
  "$(grep -qF '/management:update' <<< "$commands" && echo yes || echo no)" "yes"
check "Commands documents /management:update's 'check' mode" \
  "$(grep -qiE '/management:update check|\`check\`|"check"|check mode|check-only' <<< "$commands" && echo yes || echo no)" "yes"
check "Commands states /management:update is not model-invocable" \
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
  "$(grep -qF '/plugin uninstall management@clam' <<< "$uninstalling" && echo yes || echo no)" "yes"
check "Uninstalling names the clam-setup-stamps.json stamp file" \
  "$(grep -qF 'clam-setup-stamps.json' <<< "$uninstalling" && echo yes || echo no)" "yes"
check "Uninstalling notes the stamp file is not removed" \
  "$(grep -qiE 'not removed|is not deleted|remains|persists|left (in place|untouched)' <<< "$uninstalling" && echo yes || echo no)" "yes"

# ===========================================================================
# Contract: B03 prune-wiring — README (plan 001-stamp-staleness-actionable)
# ===========================================================================
# Three edits to the README, all inside sections that already exist (the
# plugin README template governs heading order, so nothing is added at
# heading level): the check-versions.sh TSV column list grows to seven
# columns, a scripts/prune-stamp.sh entry joins the Scripts subsection in the
# same shape as the existing entry, and prune-stamp.test.sh joins the Tests
# block.
#
# Scoped, like every other content check here, to the rendered text of the
# section that must carry the fact — the contract docblock narrates all of it
# and would otherwise satisfy these checks with no README written.
#
# Prose proximity patterns run against a whitespace-flattened copy of the
# section: this README is hard-wrapped at ~76 columns, so two words that read
# as adjacent routinely land on different raw lines, and grep matches per
# line. Same idiom as run-skill.test.sh's BODY_FLAT, with one addition —
# `tr -s` squeezes the run of whitespace a join leaves behind (newline plus
# the continuation line's indent), so a two-word phrase matches the same
# whether or not the author's wrap happens to fall between its words.
# Verified empirically: without the squeeze, "does not clear itself" wrapped
# after "clear" failed a `clear itself` pattern that a one-line phrasing
# passed, i.e. the suite scored the line-wrapping rather than the prose.

commands_flat=$(tr -s '[:space:]' ' ' <<< "$commands")

# Extracts one script entry from the Commands section: the bold entry-lead
# line naming $2, through the line before the next bold lead or heading.
# Entry-scoping is what stops a prune-stamp.sh clause (exit codes, the
# CLAUDE_CONFIG_DIR note) from being satisfied by the neighbouring
# check-versions.sh entry, which documents both of those for itself.
entry_body() { # section_text marker
  awk -v m="$2" '
    !found && /^\*\*/ && index($0, m) {found=1; print; next}
    found && (/^\*\*/ || /^#/) {exit}
    found {print}
  ' <<< "$1"
}

prune_entry=$(tr -s '[:space:]' ' ' <<< "$(entry_body "$commands" 'prune-stamp.sh')")

# --- The seven-column TSV description --------------------------------------
check "Commands names the stale_targets TSV column" \
  "$(grep -qF 'stale_targets' <<< "$commands" && echo yes || echo no)" "yes"
check "Commands' TSV column list enumerates all seven columns, in check-versions.sh order" \
  "$(grep -qiE 'TSV.{0,60}plugin.{0,60}installed.{0,60}latest.{0,60}update.{0,60}stamp.{0,60}setup.{0,60}stale_targets' <<< "$commands_flat" && echo yes || echo no)" "yes"
# [^_] bounds the window so it cannot run from one "stale_targets" occurrence
# to another (the identifier contains the word "targets", so an unbounded
# window would let the column list satisfy this on its own).
check "Commands says what the stale_targets column carries" \
  "$(grep -qiE 'stale_targets[^_]{0,220}(path|behind|differ|out of date|stale stamp)' <<< "$commands_flat" && echo yes || echo no)" "yes"
check "Commands states the stamp column reports the lowest (driving) stamp version" \
  "$(grep -qiE 'stamp.{0,140}(lowest|driving)|(lowest|driving).{0,140}stamp' <<< "$commands_flat" && echo yes || echo no)" "yes"

# --- The scripts/prune-stamp.sh entry --------------------------------------
# Discoverable by literal script name, exactly as the existing
# check-versions.sh check above requires.
check "Commands documents scripts/prune-stamp.sh" \
  "$(grep -qF 'prune-stamp.sh' <<< "$commands" && echo yes || echo no)" "yes"
# Anchors every entry-scoped check below: if this is red they are red for the
# same single reason (no bold entry lead), not for four independent ones.
check "the prune-stamp.sh entry has a bold entry lead, in the same shape as check-versions.sh" \
  "$(nonblank "$prune_entry")" "yes"
check "the prune-stamp.sh entry gives a runnable example carrying both arguments" \
  "$(grep -qiE 'bash .{0,80}prune-stamp\.sh [^ ]+ [^ ]+' <<< "$prune_entry" && echo yes || echo no)" "yes"
check "the prune-stamp.sh entry documents its exit codes" \
  "$(grep -qiE 'exit.{0,60}[0-9]' <<< "$prune_entry" && echo yes || echo no)" "yes"
check "the prune-stamp.sh entry carries the CLAUDE_CONFIG_DIR note" \
  "$(grep -qF 'CLAUDE_CONFIG_DIR' <<< "$prune_entry" && echo yes || echo no)" "yes"
check "the prune-stamp.sh entry describes deleting a stamp record the engineer names" \
  "$(grep -qiE '(delet|remov)[a-z]*.{0,80}(record|stamp)|(record|stamp).{0,80}(delet|remov)' <<< "$prune_entry" \
     && grep -qiE 'engineer|you name|you give|name(s|d)?|specif' <<< "$prune_entry" && echo yes || echo no)" "yes"
check "the prune-stamp.sh entry states the update skill offers this command" \
  "$(grep -qi 'offer' <<< "$prune_entry" && echo yes || echo no)" "yes"
check "the prune-stamp.sh entry states the skill never runs it" \
  "$(grep -qiE 'never runs?|does not run|doesn.t run' <<< "$prune_entry" && echo yes || echo no)" "yes"
# Negative invariant. The script deletes exactly what it is told to delete and
# makes no liveness judgement of its own; describing it as cleanup or garbage
# collection would advertise a judgement it deliberately does not have.
# GREEN at birth (the entry does not exist yet) — a guard on the next wave.
check "the prune-stamp.sh entry does not describe the script as cleanup or garbage collection" \
  "$(grep -qiE 'clean-?up|cleans? up|garbage.{0,3}collect|sweep|reap' <<< "$prune_entry" && echo present || echo absent)" "absent"
# GREEN at birth, edge-case guard: the stamp record format has exactly one
# source of truth (docs/setup-stamps.md, which the existing "Commands points
# to docs/setup-stamps.md" check requires this section to link).
check "Commands does not restate the stamp file's record format" \
  "$(grep -qE 'stamps\[\]|"scope":|"target":|"at":' <<< "$commands" && echo present || echo absent)" "absent"

# --- The Tests block --------------------------------------------------------
tests_block=$(section_body "$readme_stripped" "## Tests")
check "Tests block lists prune-stamp.test.sh" \
  "$(grep -qF 'prune-stamp.test.sh' <<< "$tests_block" && echo yes || echo no)" "yes"
# GREEN at birth: the new entry is added to the block, not swapped in.
check "Tests block still lists the existing manifest and check-versions suites" \
  "$(grep -qF 'manifest.test.sh' <<< "$tests_block" \
     && grep -qF 'check-versions.test.sh' <<< "$tests_block" && echo yes || echo no)" "yes"

# ===========================================================================
# Contract: B03 prune-wiring — stamps doc (plan 001-stamp-staleness-actionable)
# ===========================================================================
# docs/setup-stamps.md is a binding format contract: five separate setup
# skills write the file it specifies, and stamp-conformance.test.sh scores
# their docblocks against it. The addition under test is ONE semantic — that
# records are never auto-pruned and removal is always explicit.
#
# Its central invariant, that the addition imposes NO new obligation on those
# five skills, is deliberately NOT asserted here. The proof of it is that
# stamp-conformance.test.sh keeps passing without being edited; duplicating
# its checks here would create a second scorer of the same five docblocks and
# a second thing to update when they change.
#
# RED at birth for the four semantics checks (the section says nothing about
# automatic pruning, explicit removal, or self-clearing today); GREEN by
# design for the two verbatim-survival checks and the two negative guards.

SETUP_STAMPS_DOC="$PLUGIN_ROOT/docs/setup-stamps.md"
stamps_stripped=$(strip_comments "$SETUP_STAMPS_DOC")
semantics=$(section_body "$stamps_stripped" "## Semantics")
semantics_flat=$(tr -s '[:space:]' ' ' <<< "$semantics")

# Anchors the checks below, as the entry-lead check does for the README.
check "docs/setup-stamps.md has a non-empty Semantics section" \
  "$(nonblank "$semantics")" "yes"

check "Semantics states stamp records are never pruned automatically" \
  "$(grep -qiE '(never|not|no).{0,50}auto[a-z-]*.{0,50}(prune|pruned|removed|cleared|deleted)|(prune|pruned|removed|cleared|deleted).{0,50}auto[a-z-]*' <<< "$semantics_flat" && echo yes || echo no)" "yes"
check "Semantics states removal is always explicit" \
  "$(grep -qiE 'always explicit|explicit(ly)?.{0,40}(removal|remove|deletion|delete)|(removal|removing|deletion).{0,40}explicit' <<< "$semantics_flat" && echo yes || echo no)" "yes"
check "Semantics names both removal routes: a setup's remove subcommand and prune-stamp.sh" \
  "$(grep -qF 'prune-stamp.sh' <<< "$semantics_flat" \
     && grep -qiE 'remove.{0,300}prune-stamp|prune-stamp.{0,300}remove' <<< "$semantics_flat" && echo yes || echo no)" "yes"
check "Semantics gives prune-stamp.sh as the route for a target a setup cannot resolve" \
  "$(grep -qiE 'prune-stamp.{0,300}(cannot|can.t|unable|no longer)|(cannot|can.t|unable|no longer).{0,300}prune-stamp' <<< "$semantics_flat" && echo yes || echo no)" "yes"
# The surprise that produced issue #239: a record whose target has gone away
# stays put. Two conjuncts, since "does not self-clear" has many faithful
# phrasings and only the negation is load-bearing.
check "Semantics states a record whose target no longer corresponds to an installation does not self-clear" \
  "$(grep -qiE 'no longer' <<< "$semantics_flat" \
     && grep -qiE '(does not|doesn.t|never|is not|are not|not).{0,60}(self.?clear|clear (itself|on its own)|disappear|go(es)? away|vanish|remove (itself|on its own))' <<< "$semantics_flat" && echo yes || echo no)" "yes"

# GREEN at birth, verbatim-survival guards: the addition sits ALONGSIDE these
# two existing rules; it does not restate or amend either.
check "the existing 'Key: (plugin, target)' rule survives verbatim" \
  "$(grep -qF -- '**Key: `(plugin, target)`.**' <<< "$semantics" \
     && grep -qF -- 'replaces that record' <<< "$semantics_flat" && echo yes || echo no)" "yes"
check "the existing remove-is-silent-success rule survives verbatim" \
  "$(grep -qF -- 'no record present is silent success' <<< "$semantics_flat" && echo yes || echo no)" "yes"

# GREEN at birth, edge-case guard: prune-stamp.sh's interface belongs to the
# script's own docblock and the README. This document specifies the FORMAT
# contract only; duplicating the interface would create a second source of
# truth to drift.
check "the stamps doc does not document prune-stamp.sh's flags, exit codes, or usage" \
  "$(grep -qiE 'exit (code|status|[0-9])|usage:|^ *usage' <<< "$stamps_stripped" && echo present || echo absent)" "absent"
# GREEN at birth, invariant guard: reader-facing prose, not a changelog.
check "the stamps doc body carries no issue archaeology" \
  "$(grep -qE '#[0-9]+' <<< "$stamps_stripped" && echo present || echo absent)" "absent"

# ===========================================================================
# Contract: B03 scope-docs (plan 001-update-install-scope, issue #276)
# ===========================================================================
# Two artifacts, one block: the reader-facing description of
# check-versions.sh's output gains an eighth column, scope, and plugin.json
# records the version that makes the change visible to installed users. The
# script's own header docblock stays authoritative for the column's semantics
# — the README restates it for a reader, so these checks assert that the FACTS
# are stated, never the wording that states them.
#
# Every prose check here is scoped to the check-versions.sh ENTRY rather than
# the whole Commands section, reusing the entry_body helper above. That
# matters more here than it did for prune-stamp.sh: "scope" is also the
# ordinary English word the /management:install entry uses three paragraphs
# up ("asks once for the install scope (`local`, `user`, or `project`)"), and
# a section-scoped pattern would happily score that prose instead of the
# column description.
#
# RED at birth: the paragraph documents seven columns and says nothing about
# scope, and plugin.json is at 0.4.0. GREEN at birth for the entry-lead anchor
# and the two survival guards — this block ADDS to the paragraph, it does not
# rewrite it.

cv_entry=$(tr -s '[:space:]' ' ' <<< "$(entry_body "$commands" 'check-versions.sh')")

# Anchors every entry-scoped check below, exactly as the prune-stamp.sh
# entry-lead check does: if this is red, they are all red for that one reason
# rather than for seven independent ones.
check "the check-versions.sh entry has a bold entry lead" \
  "$(nonblank "$cv_entry")" "yes"

# --- The eight-column TSV description ---------------------------------------
# The first seven gaps use the same {0,60} windows as the seven-column check
# above, which stays untouched as the prior contract's regression guard. The
# final gap is tighter on purpose: "scope" is a word the sentence AFTER the
# list is certain to use, and a 60-char window would let that following prose
# satisfy "the list ends with scope" while the list itself still had seven.
#
# This is now a regression guard for the scope column's PRESENCE and position,
# not for the list's length: the pattern is unanchored at its right-hand end,
# so a ninth column appended after scope still satisfies it. The nine-column
# check in the repo-scoped-report section below is what pins the current
# length; both are kept, because this one would still catch scope being
# dropped or reordered if that check were ever re-pointed again.
check "the check-versions.sh entry's TSV column list enumerates all eight columns, in check-versions.sh order, scope last" \
  "$(grep -qiE 'TSV.{0,60}plugin.{0,60}installed.{0,60}latest.{0,60}update.{0,60}stamp.{0,60}setup.{0,60}stale_targets.{0,25}scope' <<< "$cv_entry" && echo yes || echo no)" "yes"

# What the column carries, per the script's Outputs docblock: the DISTINCT
# scopes of the plugin's installation entries, ";"-joined, "-" when not
# installed. Three facts, three checks, so a partial restatement fails
# specifically rather than as one opaque "no".
check "the check-versions.sh entry says the scope column carries the distinct scopes, not one per entry" \
  "$(grep -qiE 'scope.{0,120}(distinct|unique|dedup)|(distinct|unique|dedup)[a-z-]*.{0,120}scope' <<< "$cv_entry" && echo yes || echo no)" "yes"
check "the check-versions.sh entry says the scope values are ';'-joined" \
  "$(grep -qiE '(`;`|";"|semicolon).{0,80}(join|separat|delimit)|(join|separat|delimit)[a-z]*.{0,80}(`;`|";"|semicolon)' <<< "$cv_entry" && echo yes || echo no)" "yes"
check "the check-versions.sh entry says scope is '-' when the plugin is not installed" \
  "$(grep -qiE '(`-`|"-").{0,80}(not installed|isn.t installed|no install)|(not installed|isn.t installed|no install).{0,80}(`-`|"-")' <<< "$cv_entry" && echo yes || echo no)" "yes"

# What the column is FOR. Two conjuncts because the flag alone doesn't say
# why it beats doing nothing: the point is that the CLI's own default is
# `user`, which is wrong for a local-scope install.
check "the check-versions.sh entry says scope is what lets the update pass -s <scope> instead of the CLI's 'user' default" \
  "$(grep -qE '(-s[ `]|--scope)' <<< "$cv_entry" \
     && grep -qiE '(default|assum)[a-z]*.{0,60}user|user.{0,60}(default|assum)' <<< "$cv_entry" && echo yes || echo no)" "yes"

# GREEN at birth, survival guards. The two descriptions already in this
# paragraph must survive the edit, and survive INSIDE this entry — which is
# more than the section-scoped prune-wiring checks above can tell, since they
# would still pass if the text migrated to a neighbouring entry.
check "the check-versions.sh entry still describes stamp as the lowest (driving) stamp version" \
  "$(grep -qiE 'stamp.{0,140}(lowest|driving)|(lowest|driving).{0,140}stamp' <<< "$cv_entry" && echo yes || echo no)" "yes"
check "the check-versions.sh entry still describes stale_targets as the targets that are behind" \
  "$(grep -qiE 'stale_targets[^_]{0,220}(path|behind|differ|out of date|stale stamp)' <<< "$cv_entry" && echo yes || echo no)" "yes"

# ===========================================================================
# Repo-scoped version report (issues #324 and #325)
# ===========================================================================
# The same two artifacts as the scope-docs block above, one change further on.
# check-versions.sh now attributes each install record to a repository and
# ignores the ones belonging elsewhere, which changes three reader-facing
# facts: the report is about THIS repo, `installed` is the LOWEST of this
# repo's versions rather than the highest across the machine, and a ninth
# column, stale_installs, names the project paths still behind.
#
# Scoped to the check-versions.sh entry for the same reason the block above
# is: "scope" and "repo" are both ordinary words the surrounding entries use
# for unrelated things, and a section-wide pattern would score that prose
# instead of the column description.
#
# RED against the pre-change README: it documents eight columns, says nothing
# about which repo the report describes, and describes no version-collapse
# rule at all (the highest-wins behaviour was never written down, which is
# part of why it survived).

# --- The nine-column TSV description ----------------------------------------
# Extends the eight-column pattern above by one column, with the same tight
# final gap and for the same reason: "stale_installs" is a word the prose
# after the list uses, so a wide window would let that prose stand in for the
# list itself.
check "the check-versions.sh entry's TSV column list enumerates all nine columns, in check-versions.sh order, stale_installs last" \
  "$(grep -qiE 'TSV.{0,60}plugin.{0,60}installed.{0,60}latest.{0,60}update.{0,60}stamp.{0,60}setup.{0,60}stale_targets.{0,25}scope.{0,25}stale_installs' <<< "$cv_entry" && echo yes || echo no)" "yes"

# --- Repo scoping -----------------------------------------------------------
# Two checks, not one: that the report is about a particular repo, and that
# entries from other repos are excluded. A reader given only the first could
# still assume the machine-wide records are all this repo's.
check "the check-versions.sh entry says the report describes the repo it is run in" \
  "$(grep -qiE '(report|it) describes.{0,40}repo|(scoped|specific) to (this|the current) repo' <<< "$cv_entry" && echo yes || echo no)" "yes"
check "the check-versions.sh entry says entries belonging to other repositories are excluded" \
  "$(grep -qiE '(other|another|different) repositor[a-z]*.{0,60}(exclud|ignor|omit|not count)|(exclud|ignor|omit)[a-z]*.{0,60}(other|another|different) repositor' <<< "$cv_entry" && echo yes || echo no)" "yes"

# --- installed is the lowest ------------------------------------------------
# The rule a reader needs to make sense of a row that stays stale after a
# successful update. It was never documented before this change, in either
# direction.
check "the check-versions.sh entry says installed is the lowest of this repo's versions" \
  "$(grep -qiE 'installed.{0,40}(lowest|minimum)|(lowest|minimum).{0,40}installed' <<< "$cv_entry" && echo yes || echo no)" "yes"

# --- What stale_installs carries --------------------------------------------
# Same [^_] bounding as the stale_targets checks above, and for the same
# reason: the identifier contains a word the description also uses, so an
# unbounded window would let the column list satisfy the check on its own.
check "the check-versions.sh entry says what the stale_installs column carries" \
  "$(grep -qiE 'stale_installs[^_]{0,220}(path|behind|out of date)' <<< "$cv_entry" && echo yes || echo no)" "yes"
check "the check-versions.sh entry says stale_installs is '-' when the row needs no update" \
  "$(grep -qiE 'stale_installs[^_]{0,240}(`-`|"-")' <<< "$cv_entry" && echo yes || echo no)" "yes"

# --- The stamp columns are deliberately NOT repo-scoped ---------------------
# A stated non-goal rather than an oversight: a stamp records a target
# settings file, not a project root, so it cannot be attributed the same way.
# Documented because the alternative is a reader treating a foreign path in
# stale_targets as a bug in the scoping this same paragraph just described.
check "the check-versions.sh entry says the stamp columns are not repo-filtered" \
  "$(grep -qiE 'stamp[a-z]*.{0,40}not.{0,20}repo.?[- ]?filter|repo.?[- ]?filter[a-z]*.{0,60}stamp' <<< "$cv_entry" && echo yes || echo no)" "yes"

# --- The manifest version ---------------------------------------------------
# An exact pin, and deliberately unlike the ">= 0.1.0 floor" near the top of
# this file. The floor cannot tell 0.6.1 from a wrong bump to 0.5.1 or 1.0.0,
# and WHICH bump this is is itself the contract clause: MINOR, because the
# report gains a column — a backwards-compatible addition to a public
# contract. The repo scoping that comes with it changes what existing columns
# REPORT without changing their shape, which is a behavioural fix, not a
# contract break: a caller parsing the first eight columns still parses them.
# The floor stays as-is and keeps absorbing unrelated future bumps; this pin
# is the one assertion that has to be re-pointed the next time management's
# version moves.
check "plugin.json .version is exactly 0.6.1" "$version" "0.6.1"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
