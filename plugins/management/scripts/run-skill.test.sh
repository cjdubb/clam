#!/bin/bash
# Structural/content tests for skills/update/SKILL.md against three contracts,
# each stated as an HTML-comment docblock in that file (or, once accepted,
# removed from it — see "Contract docblocks are not permanent" below):
#   - Contract: B02 updates-run-skill (plan 001-update-flow-for-users) —
#     sections 1-17 below, all GREEN: B02 is implemented and merged.
#   - Contract: B03 prune-wiring (plan 001-stamp-staleness-actionable,
#     issue #239) — section 18 below, all GREEN: implemented and merged.
#   - Contract: B02 scope-wiring (plan 001-update-install-scope, issue #276)
#     — section 19 below, plus 18b's column enumeration which that contract
#     supersedes, the wave this suite is being extended for.
#
# A SKILL.md is model-executed instructions, not code, so this is a
# structure/content suite:
#   - frontmatter checks (name, disable-model-invocation, description states
#     the "explicit user action, never implicit" invariant)
#   - body-content checks: every contracted behavior must be stated in the
#     skill's OWN prose. The contract docblock itself narrates every behavior
#     under test (it has to, to specify them), so scoring against raw text
#     would let the docblock's own comment satisfy a check with nothing
#     written in the real body. All body checks therefore run against
#     comment-stripped text (strip_comments() below, reused from
#     manifest.test.sh's approach) applied to the content AFTER the
#     frontmatter's closing '---'.
#
# strip_comments() is a per-line awk state machine (not a bare
# `sed '/<!--/,/-->/d'` range): a naive range delete mishandles a same-line
# "<!-- ... -->" comment by continuing to hunt for the NEXT "-->" instead of
# closing on the same line, which silently swallows real content when
# several such comments appear in sequence. This file's contract docblock is
# exactly that shape (one big multi-line comment, but the technique matters
# generally and is kept consistent with manifest.test.sh).
#
# Contract docblocks are not permanent: for a prose block the prose IS the
# implementation, so each contract comment carries "(remove at acceptance)"
# and is deleted once its block is accepted. No check in this file may
# therefore depend on a docblock being present — every one reads the
# comment-stripped body, which is what the reader actually sees, and is
# unaffected by the comment's later removal.
#
# RED/GREEN at birth (B02 wave, scaffold state, see brief 01-test-B02.md):
#   - Frontmatter checks were GREEN already: name/disable-model-invocation/
#     description landed at scaffold with their full contracted content.
#   - Every body-content check was RED against the B02 stub: the body was
#     only a "NotImplemented: B02" placeholder line (plus the stripped
#     contract comment), so none of the contracted facts were stated in the
#     skill's own prose yet. All of them are GREEN now — B02 is implemented,
#     accepted and merged — and stand as regression guards for section 18's
#     edits, which must not disturb any of them.
#
# Body checks are whole-body fact greps (grep for the required fact, not
# exact phrasing), not per-section extraction: the contract does not mandate
# specific section headers for the flow body, unlike e.g. the worktrees
# usage skill. Proximity-bounded regexes (`.{0,N}`) and compound `&&` grep
# chains are used to reduce (never fully eliminate) vacuous-pass risk when a
# bullet names two co-occurring facts; some looseness is inherent to
# content-testing free-form prose and is accepted per the brief.
#
# Hermetic: reads only this repo's own committed SKILL.md, no network, no
# mutation, cwd-independent (path resolved from this script's own location).
#
# Run: bash plugins/management/scripts/run-skill.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/update/SKILL.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Case-insensitive extended-regex presence check over a blob of text.
has() { # content pattern
  if grep -qiE -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Fixed-string (literal) presence check, case-sensitive.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

nonblank() { # string -> "yes"/"no"
  if [[ -n "$(printf '%s' "$1" | tr -d '[:space:]')" ]]; then echo yes; else echo no; fi
}

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL  SKILL.md not found at $SKILL"
  exit 1
fi

# Removes HTML comments from stdin content, line by line, correctly closing
# a comment that opens and closes on the same line. Blank lines are left in
# comments' place so line-based extraction downstream is unaffected.
strip_comments() { # stdin -> stdout
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
  '
}

# --- Frontmatter -------------------------------------------------------
# Lines strictly between the first two '---' delimiters (never affected by
# HTML-comment stripping, so read directly from the raw file).
FRONTMATTER=$(awk '/^---$/{n++; next} n==1' "$SKILL")
NAME=$(printf '%s\n' "$FRONTMATTER" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
DMI=$(printf '%s\n' "$FRONTMATTER" | grep '^disable-model-invocation:' | sed -E 's/^disable-model-invocation:[[:space:]]*//')
DESC=$(printf '%s\n' "$FRONTMATTER" | grep '^description:' | sed -E 's/^description:[[:space:]]*//')

check "frontmatter name is 'update'" "$NAME" "update"
check "frontmatter disable-model-invocation is 'true'" "$DMI" "true"
check "description is non-empty" "$(nonblank "$DESC")" "yes"
check "description states explicit user action" "$(has "$DESC" 'explicit')" "yes"
check "description states it never runs implicitly" \
  "$(has "$DESC" 'never runs? implicitly|not.{0,10}implicit|never.{0,10}implicit')" "yes"

# --- Body (HTML comments stripped, frontmatter excluded) ----------------
# Comment-stripped whole file, then everything after the frontmatter's
# closing '---' delimiter.
STRIPPED=$(strip_comments <"$SKILL")
BODY=$(awk '/^---$/{n++; next} n>=2' <<<"$STRIPPED")

# Newline-flattened variant of BODY, used for every proximity-bounded regex
# below (patterns using `.{0,N}` to require two facts near each other).
# Markdown prose is commonly hard-wrapped at ~80 columns, so two words that
# read as adjacent to a person can land on different raw lines; grep matches
# per line by default, so an un-flattened multi-line proximity pattern would
# spuriously fail on a perfectly correct, merely line-wrapped implementation.
# Flattening loses no literal-substring matches (has_f / plain has_f-style
# checks stay correct here too), so it is used for all body checks below.
BODY_FLAT=$(tr '\n' ' ' <<<"$BODY")

# --- 1. Refresh-catalog step ---------------------------------------------
check "refresh-catalog step names the marketplace-update command for clam" \
  "$(has "$BODY_FLAT" 'marketplace.{0,20}update.{0,20}clam|clam.{0,20}marketplace.{0,20}update')" "yes"

# --- 2. Runs check-versions.sh; presents report before changing anything --
check "runs check-versions.sh to build the version report" \
  "$(has_f "$BODY_FLAT" 'check-versions.sh')" "yes"
check "presents the report before anything is changed" \
  "$(has "$BODY_FLAT" 'before.{0,20}(chang|updat)|nothing.{0,20}(has been |is )?chang.{0,20}yet')" "yes"

# --- 3. Nothing-stale case: say so and stop ------------------------------
check "nothing-stale case: states nothing is stale" \
  "$(has "$BODY_FLAT" 'nothing.{0,10}(is |are )?stale|no plugins?.{0,10}(are |is )?stale|zero.{0,10}stale')" "yes"
check "nothing-stale / stopping language present in the body" \
  "$(grep -qiE 'stale' <<<"$BODY_FLAT" && grep -qiE '\bstop' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"

# --- 4. ONE batch confirmation; subset reply honored ---------------------
check "batch confirmation covers the whole stale set (not per-plugin)" \
  "$(has "$BODY_FLAT" 'batch|whole set|entire set')" "yes"
check "an explicit subset reply is honored" \
  "$(has "$BODY_FLAT" 'subset')" "yes"

# --- 5. Per-plugin update via claude plugin update, @clam addressing -----
check "per-plugin update via 'claude plugin update' with @clam addressing" \
  "$(grep -qF 'claude plugin update' <<<"$BODY_FLAT" && grep -qF '@clam' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"

# --- 6. Failure isolation; failures collected/reported --------------------
check "a single plugin failure does not abort the rest" \
  "$(has "$BODY_FLAT" 'does not abort|doesn.t abort|without aborting|continu.{0,20}(rest|others|remaining)')" "yes"
check "failures are collected and reported at the end" \
  "$(has "$BODY_FLAT" 'collect.{0,30}fail|fail.{0,30}collect|list.{0,15}fail')" "yes"

# --- 7. Post-update re-check (before/after) -------------------------------
check "post-update re-check shows before/after state" \
  "$(grep -qiE '\bbefore\b' <<<"$BODY_FLAT" && grep -qiE '\bafter\b' <<<"$BODY_FLAT" && grep -qiE 're-?run|re-?check' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"

# --- 8. The five setup-command mappings -----------------------------------
check "names /attribution:setup" "$(has_f "$BODY_FLAT" '/attribution:setup')" "yes"
check "names /privacy:setup" "$(has_f "$BODY_FLAT" '/privacy:setup')" "yes"
check "names /settings:setup" "$(has_f "$BODY_FLAT" '/settings:setup')" "yes"
check "names /statusline:setup" "$(has_f "$BODY_FLAT" '/statusline:setup')" "yes"
check "names /landing:init" "$(has_f "$BODY_FLAT" '/landing:init')" "yes"

# --- 9. unstamped -> "setup state unknown", never "needs setup" ----------
check "unstamped is presented as 'setup state unknown'" \
  "$(grep -qF 'unstamped' <<<"$BODY_FLAT" && grep -qi 'setup state unknown' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"
check "never phrases (un)stamped plugins as 'needs setup'" \
  "$(has_f "$BODY_FLAT" 'needs setup')" "no"

# --- 10. Setups OFFERED, never invoked by the skill -----------------------
check "setup skills are offered as commands" "$(has "$BODY_FLAT" 'offer')" "yes"
check "setup skills are never invoked/run by the skill itself" \
  "$(has "$BODY_FLAT" 'never (run|invok|execut)')" "yes"

# --- 11. Reload guidance ----------------------------------------------------
check "reload guidance names /reload-plugins" "$(has_f "$BODY_FLAT" '/reload-plugins')" "yes"
check "reload guidance mentions restarting the session" "$(has "$BODY_FLAT" 'restart')" "yes"

# --- 12. "check" argument: stop after report, read-only -------------------
check "'check' argument stops after the report" \
  "$(grep -qiE '"?check"?' <<<"$BODY_FLAT" && grep -qiE 'argument' <<<"$BODY_FLAT" && grep -qiE '\bstop' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"
check "'check' argument mode is read-only" \
  "$(has "$BODY_FLAT" 'read.only')" "yes"

# --- 13. claude CLI absent -> fallback via interactive /plugin flow -------
check "claude CLI absent: falls back to the interactive /plugin flow" \
  "$(grep -qiE 'claude.{0,15}(cli|command).{0,25}(not|absent|missing)|not (on|in|found on) (the )?PATH' <<<"$BODY_FLAT" && grep -qF '/plugin' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"

# --- 14. check-versions.sh exit codes: 3 vs 2/4 ----------------------------
check "check-versions.sh exit 3: surfaces the script's message and stops" \
  "$(has_f "$BODY_FLAT" 'exit 3')" "yes"
check "check-versions.sh exit 2/4: surfaces stderr verbatim and stops" \
  "$(grep -qiE 'exit 2' <<<"$BODY_FLAT" && grep -qiE 'exit 4' <<<"$BODY_FLAT" && grep -qi 'stderr' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"

# --- 15. Absent stamps never block updates --------------------------------
check "absent setup stamps never block or gate updates" \
  "$(has "$BODY_FLAT" 'never block|does not block|doesn.t block|never gate|do(es)? not gate')" "yes"

# --- 16. Self-update case ---------------------------------------------------
check "self-update case: new version applies next session/reload" \
  "$(grep -qiE 'management.{0,20}(itself|plugin).{0,70}(next session|reload)|itself.{0,40}(next session|reload)' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"

# --- 17. Zero clam plugins installed ---------------------------------------
check "zero clam plugins installed: reports and stops" \
  "$(grep -qiE 'no (clam )?plugins?.{0,15}installed|zero.{0,15}plugins?.{0,15}installed' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"

# ===========================================================================
# 18. Contract: B03 prune-wiring (plan 001-stamp-staleness-actionable, #239)
# ===========================================================================
# The second contract this file is scored against. It adds no computation to
# the skill: it makes the two capabilities B01 and B02 landed (the seventh
# `stale_targets` column, and prune-stamp.sh) visible and offerable in the
# skill's instructions.
#
# Same rules as sections 1-17: every fact must be stated in the skill's OWN
# rendered prose, so every check reads BODY / BODY_WS (comment-stripped),
# never the raw file. The B03 docblock narrates every fact below — scoring
# against raw text would let the comment satisfy the check with nothing
# written, and would then break outright when the docblock is removed at
# acceptance.
#
# Three checks are scoped to a numbered step rather than the whole body,
# because the contract specifies the change per step ("Step 2's column list
# gains stale_targets"; "Step 3 (and step 7's after-state view) prints the
# stale_targets value"). Whole-body greps cannot distinguish "the column is
# named once, somewhere" from "the report actually shows it, in both views",
# which is the whole point of those two clauses. The three structural guards
# immediately below exist so that a step-scoped check failing always means
# "the fact is missing", never "the step extraction silently returned
# nothing".
#
# Not asserted here, deliberately: prune-stamp.sh's own exit codes and
# argument handling. Those are the script's contract (B02) and are covered by
# prune-stamp.test.sh; this skill never runs the script, so it never handles
# them — see the negative check at the end of this section.
#
# RED/GREEN at birth (this wave):
#   - RED, and red because the fact is absent from the skill's rendered
#     prose: everything about `stale_targets`, the prune offer, the
#     one-offer-per-target rule, the "-" edge case, the unstamped edge case,
#     and the engineer's-judgement invariant. Neither "stale_targets" nor
#     "prune-stamp" appears anywhere in the body today; both occur only
#     inside the stripped B03 docblock.
#   - GREEN by design, labelled inline: the three step-extraction guards,
#     the "a stale stamp still never blocks or gates an update" survival
#     check (the contract requires that existing statement to remain true
#     and stated), and the negative exit-code check.

# Extracts one numbered step from the flow: the line starting "<n>." plus
# its continuation lines, up to the next numbered item, the next heading, or
# end of body.
step_body() { # body step_number
  awk -v n="$2" '
    $0 ~ ("^" n "\\. ") {found=1; print; next}
    found && (/^[0-9]+\. / || /^#/) {exit}
    found {print}
  ' <<<"$1"
}

# Flattened per the same reasoning as BODY_FLAT, plus a `tr -s` squeeze of the
# whitespace run a join leaves behind (the newline plus the continuation
# line's three-space indent). Without the squeeze a two-word phrase matches or
# not depending purely on where the author's ~72-column wrap fell — verified
# empirically on a draft where "does not clear itself" wrapped after "clear"
# and failed a `clear itself` pattern that the identical unwrapped sentence
# passed. BODY_FLAT itself is deliberately left as it is: it is section 1-17's
# input and those checks are not this wave's to change.
BODY_WS=$(tr -s '[:space:]' ' ' <<<"$BODY")
STEP2=$(tr -s '[:space:]' ' ' <<<"$(step_body "$BODY" 2)")
STEP3=$(tr -s '[:space:]' ' ' <<<"$(step_body "$BODY" 3)")
STEP7=$(tr -s '[:space:]' ' ' <<<"$(step_body "$BODY" 7)")

# --- 18a. Guards for the step-scoped checks (GREEN at birth) --------------
check "step 2 is extractable and is the check-versions.sh step" \
  "$(has_f "$STEP2" 'check-versions.sh')" "yes"
check "step 3 is extractable and non-empty (the pre-change report)" \
  "$(nonblank "$STEP3")" "yes"
check "step 7 is extractable and non-empty (the after-state re-check)" \
  "$(nonblank "$STEP7")" "yes"

# --- 18b. Step 2 parses the full column list, stale_targets among them ----
check "step 2's column list names the stale_targets column" \
  "$(has_f "$STEP2" 'stale_targets')" "yes"
# Amended by section 19's contract (B02 scope-wiring, #276), which adds an
# EIGHTH column, `scope`, last. The seven-column form this check required is
# exactly what that contract supersedes, so the enumeration is updated in
# place rather than duplicated below — leaving a seven-column assertion here
# would make the suite contradict itself. stale_targets' own clause (its
# position, sixth-to-last no longer being last) is unchanged and still
# covered, since the pattern is ordered.
check "step 2's column list enumerates all eight columns, in check-versions.sh order" \
  "$(has "$STEP2" 'columns?.{0,40}plugin.{0,60}installed.{0,60}latest.{0,60}update.{0,60}stamp.{0,60}setup.{0,60}stale_targets.{0,60}scope')" "yes"

# --- 18c. The stale_targets value is shown, in both report views ----------
check "the report shows the stale_targets value rather than only naming the column" \
  "$(has "$BODY_WS" '(show|print|display|surfac|list|name|report)[a-z]*.{0,140}stale_targets|stale_targets.{0,140}(shown|printed|displayed|listed|surfaced|named|reported)')" "yes"
check "step 3's pre-change report shows the stale targets" \
  "$(has "$STEP3" 'stale_targets|stale targets?')" "yes"
check "step 7's after-state view shows the stale targets too" \
  "$(has "$STEP7" 'stale_targets|stale targets?')" "yes"

# --- 18d. The prune offer --------------------------------------------------
check "the skill names prune-stamp.sh" \
  "$(has_f "$BODY_WS" 'prune-stamp.sh')" "yes"
check "the prune offer uses the CLAUDE_PLUGIN_ROOT-rooted script path" \
  "$(has_f "$BODY_WS" '${CLAUDE_PLUGIN_ROOT}/scripts/prune-stamp.sh')" "yes"
check "the prune offer is a full command carrying both the plugin and the target" \
  "$(has "$BODY_WS" 'prune-stamp\.sh [^ ]+ [^ ]+')" "yes"
check "the prune command is OFFERED" \
  "$(has "$BODY_WS" 'offer.{0,200}prune-stamp|prune-stamp.{0,200}offer')" "yes"
check "the skill states it never runs prune-stamp.sh itself" \
  "$(has "$BODY_WS" 'prune-stamp.{0,240}never (run|invok|execut)|never (run|invok|execut).{0,240}prune-stamp')" "yes"
# The never-runs-it rule is what makes offering a deletion safe at all, so the
# contract requires it to hold under a blanket instruction too, not just by
# default.
check "the never-run rule is stated to hold even under a 'fix everything' instruction" \
  "$(has "$BODY_WS" 'fix everything|fix (them |it )?all|do everything')" "yes"

# --- 18e. One offer per target, each a full command -----------------------
check "one offer per stale target, not one command covering several" \
  "$(has "$BODY_WS" '(one|a separate|its own|each).{0,60}(offer|command|line).{0,40}(per|for each)|per target|for each target|each target')" "yes"
check "each offer carries a real target, never a placeholder command" \
  "$(has "$BODY_WS" 'placeholder|(real|actual|literal|full) (target|path|command)')" "yes"

# --- 18f. Edge case: stale_targets of "-" ---------------------------------
# Loose by necessity (the two facts are one sentence apart in any faithful
# phrasing, but the phrasing itself is free); the binding that keeps it from
# passing vacuously is that "stale_targets" must appear at all, which it does
# not today.
check "stale_targets of '-': nothing is offered and nothing is said about pruning" \
  "$(has "$BODY_WS" 'stale_targets.{0,260}((offers?|says?) nothing|nothing (is )?(offered|said)|no (prune )?(offer|command)|nothing to (offer|prune))')" "yes"

# --- 18g. Edge case: an unstamped row is not a prune candidate ------------
check "an unstamped row is explicitly NOT a prune candidate" \
  "$(has "$BODY_WS" 'unstamped.{0,240}(not a prune|never a prune|not.{0,25}prune candidate|no (stamp )?record to (remove|prune)|nothing to (remove|prune))|((not|never) a prune candidate|no (stamp )?record to (remove|prune)).{0,240}unstamped')" "yes"

# --- 18h. Invariants ------------------------------------------------------
# GREEN at birth: the contract requires this existing statement to survive the
# B03 edit, so this is a regression guard, not a driver of new prose.
check "a stale setup stamp still never blocks or gates an update" \
  "$(has "$BODY_WS" 'stale.{0,200}(neither|never|not|no).{0,40}(block|gate)|(neither|never|does not|do not|doesn.t).{0,40}(block|gate).{0,200}stale')" "yes"
# Two conjuncts because word order here is genuinely free ("the judgement is
# the engineer's" and "the engineer judges" are the same fact). The first
# conjunct carries the weight: it is the one that is false today, and it binds
# the decision language to pruning rather than to step 8's existing setup
# offers, which already satisfy the second conjunct on their own.
check "the skill states no opinion on whether a stamp should be pruned — the judgement is the engineer's" \
  "$(grep -qiE '(prune|prunin|deletion|removal).{0,240}(engineer|you)|(engineer|you).{0,240}(prune|prunin|deletion|removal)' <<<"$BODY_WS" \
     && grep -qiE 'no opinion|(judg|decision|decide|choice|choos)[a-z]*.{0,80}(engineer|you)|(engineer|you).{0,80}(judg|decision|decide|choice|choos)' <<<"$BODY_WS" \
     && echo yes || echo no)" "yes"

# GREEN at birth, negative invariant: prune-stamp.sh's exit codes are the
# script's contract, not this skill's. The skill never runs it, so it must
# never grow error handling for it — unlike check-versions.sh, whose exit
# codes section 14 above requires the skill to handle.
check "the skill does not document prune-stamp.sh's own exit codes" \
  "$(has "$BODY_WS" 'prune-stamp.{0,140}exit [0-9]|exit [0-9].{0,140}prune-stamp')" "no"

# ===========================================================================
# 19. Contract: B02 scope-wiring (plan 001-update-install-scope, #276)
# ===========================================================================
# The third contract this file is scored against, and — like B03 above — one
# that adds no computation to the skill. `claude plugin update` takes the
# CLI's default `--scope user`, so the unflagged command step 6 prescribes
# today fails outright for every plugin installed at local scope, and step 6's
# own per-plugin failure handling then carries that failure through the whole
# batch. B01 of this plan added an eighth `scope` column to check-versions.sh;
# this block makes the skill read that column, pass `-s <scope>`, and state
# the failure well enough to be diagnosed from the skill alone.
#
# Same rules as every section above: each fact must be stated in the skill's
# OWN rendered prose, so every check below reads a comment-stripped, flattened
# extract of the body, never the raw file. The B02 docblock narrates every
# fact under test, so scoring against raw text would let the comment satisfy
# the check with nothing written, and would then break outright when the
# docblock is removed at acceptance.
#
# Most checks here are scoped to step 6 or to the `Errors` section rather than
# run over the whole body, because the contract specifies WHERE each change
# lands ("Step 2's column list becomes eight columns"; "Step 6 runs ..."; "The
# Errors section gains a branch"). A whole-body grep for `-s <scope>` cannot
# tell "step 6 passes the scope" from "the word scope appears somewhere in the
# file", which is the entire clause. The extraction guards in 19a exist so
# that a scoped check failing always means the fact is missing, never that the
# extraction silently returned nothing.
#
# RED/GREEN at birth (this wave):
#   - RED, and red because the fact is absent from the skill's rendered prose:
#     every check naming `scope` — the eighth column in step 2 (18b above),
#     the `-s` flag and its per-row derivation, the ";"-separated multi-scope
#     run, the "-" edge case, and the three Errors-branch checks. The body
#     says "seven-column" today, and the word "scope" does not occur in it at
#     all outside the stripped docblock.
#   - GREEN by design, labelled inline: the 19a extraction guards, the
#     no-hardcoded-literal negative (there is no `-s` in the body yet to
#     hardcode), the blind-retry negative, and all of 19g — those assert that
#     statements true today survive this block's edits, which is what the
#     contract's invariant list asks of them.

# Extracts one "## <heading>" section's content: everything after the heading
# line, up to the next heading of any level or end of body. Same shape as
# step_body, for the clause this contract states per-SECTION rather than
# per-step.
section_body() { # body heading
  awk -v h="$2" '
    $0 ~ ("^#+[[:space:]]+" h "[[:space:]]*$") {found=1; next}
    found && /^#+[[:space:]]/ {exit}
    found {print}
  ' <<<"$1"
}

# Flattened and whitespace-squeezed per BODY_WS's reasoning above.
STEP5=$(tr -s '[:space:]' ' ' <<<"$(step_body "$BODY" 5)")
STEP6=$(tr -s '[:space:]' ' ' <<<"$(step_body "$BODY" 6)")
STEP8=$(tr -s '[:space:]' ' ' <<<"$(step_body "$BODY" 8)")
ERRORS=$(tr -s '[:space:]' ' ' <<<"$(section_body "$BODY" "Errors")")

# --- 19a. Guards for the scoped checks (GREEN at birth) -------------------
check "step 5 is extractable and is the confirmation step" \
  "$(has "$STEP5" 'confirm')" "yes"
check "step 6 is extractable and is the update-command step" \
  "$(has_f "$STEP6" 'claude plugin update')" "yes"
check "step 8 is extractable and is the setup/prune offer step" \
  "$(has_f "$STEP8" 'prune-stamp.sh')" "yes"
check "the Errors section is extractable and non-empty" \
  "$(nonblank "$ERRORS")" "yes"

# --- 19b. Step 2 parses EIGHT columns, scope last -------------------------
# The ordered enumeration itself lives in 18b, updated in place; these two add
# what that check cannot say on its own: that the column is named at all (so a
# failure there is attributable), and that no stale count contradicts it.
check "step 2's column list names the scope column" \
  "$(has_f "$STEP2" 'scope')" "yes"
check "the report is no longer described as seven-column anywhere in the body" \
  "$(has "$BODY_WS" 'seven.{0,3}column|7.column')" "no"

# --- 19c. Step 6 passes the scope, derived per plugin ---------------------
# The derivation is the point of the fix, so it is asserted three ways: the
# flag reaches the command, its argument is a placeholder rather than a fixed
# word, and the prose says where that value comes from. A check satisfied by a
# hardcoded `-s local` would not have tested this contract at all.
check "step 6 passes the scope to claude plugin update via -s/--scope" \
  "$(has "$STEP6" 'claude plugin update.{0,60}(-s|--scope)\b')" "yes"
check "step 6's scope argument is a placeholder, not a fixed value" \
  "$(has "$STEP6" 'claude plugin update.{0,60}(-s|--scope) +[<${]')" "yes"
check "step 6 states the scope is taken from that plugin's row in the report" \
  "$(has "$STEP6" 'scope.{0,120}(column|row|report)|(column|row|report).{0,120}scope')" "yes"
# Negative, GREEN at birth (there is no `-s` in the body yet). Scoped to the
# command template rather than the whole step, so an illustrative aside is not
# caught — only a command that would send every plugin to one fixed scope.
check "step 6's update command never hardcodes a scope literal" \
  "$(has "$STEP6" 'claude plugin update.{0,60}(-s|--scope) +(user|local|project|dynamic|global)\b')" "no"

# --- 19d. A multi-scope row: one run per scope, each its own result -------
check "step 6 covers a scope value carrying several ';'-separated scopes" \
  "$(has "$STEP6" '(;|semicolon).{0,60}separat|separat.{0,60}(;|semicolon)|(several|multiple|more than one) scopes')" "yes"
check "step 6 runs the update command once per scope for such a row" \
  "$(has "$STEP6" '(per|for each|for every) scope')" "yes"
# Looser than the two above by necessity: step 6 already carries reporting
# language for the per-plugin case ("Report each result as it completes"), so
# the binding here is the per-scope phrase, which does not exist today.
check "each per-scope run is reported as its own result" \
  "$(has "$STEP6" '(per|for each|for every|each) scopes?.{0,140}(result|report|separately|independent)|(result|report|separately|independent)[a-z]*.{0,140}(per|for each|for every|each) scopes?')" "yes"

# --- 19e. Edge case: a scope of "-" ---------------------------------------
# Deliberately NOT written as a negative grep for the literal `-s -`: a
# faithful implementation is likely to state the prohibition ("never construct
# `-s -`"), and that sentence would fail a naive absence check while being
# exactly the prose the contract asks for. Asserted positively instead —
# either the literal flag-plus-dash form is named, or the `-` scope is
# described together with a statement that nothing is run for it.
check "step 6 covers a scope of '-': no update command is constructed for such a row" \
  "$(has "$STEP6" '(-s|--scope) +-|(scope[^.]{0,110}`-`|`-`[^.]{0,110}scope)[^.]{0,180}(never|no |not |skip)|(never|no |not |skip)[^.]{0,180}(scope[^.]{0,110}`-`|`-`[^.]{0,110}scope)')" "yes"

# --- 19f. The Errors section's scope-mismatch branch ----------------------
check "the Errors section has a branch for the scope-mismatch failure" \
  "$(has "$ERRORS" 'not installed at scope|scope.{0,40}mismatch|wrong scope')" "yes"
# Two conjuncts so that quoting the CLI's own message is not enough on its
# own: the branch has to say that the scope the skill USED is not where the
# plugin lives, which is what makes the failure diagnosable.
check "the scope-mismatch branch states the cause (the scope used is not where the plugin is installed)" \
  "$(grep -qiE -- '(scope|-s)[^.]{0,80}(used|passed|given|tried|sent|default)|(used|passed|given|tried|sent|default)[a-z]*[^.]{0,80}(scope|-s)\b' <<<"$ERRORS" \
     && grep -qiE -- '(not|isn.t|does ?n.t|never|differ|wrong|other than)[^.]{0,80}(install|where|scope)' <<<"$ERRORS" \
     && echo yes || echo no)" "yes"
check "the scope-mismatch branch states the recovery: re-read that row's scope column and re-run with the flag" \
  "$(grep -qiE -- '(re-?read|read|consult|check|look at|take)[^.]{0,60}(`?scope`?|that row)' <<<"$ERRORS" \
     && grep -qiE -- 're-?run|run .{0,15}again|retry|try again' <<<"$ERRORS" \
     && grep -qE -- '(-s|--scope)\b' <<<"$ERRORS" \
     && echo yes || echo no)" "yes"
# Negative, GREEN at birth. Same trap as 19e: the contract's own wording ("it
# must not instruct a blind retry across every scope in turn") is the natural
# thing for the branch to say, so a plain absence grep would fail a correct
# implementation. Sentences that prescribe an exhaustive retry are collected
# first, then those that forbid it are filtered out; what is left is a
# prescription, and there must be none.
#
# What makes a retry "blind" is exhausting scopes the row never named, so the
# signature is retry language plus an in-turn/until-it-works marker — NOT the
# words "each scope", which the correct recovery itself needs: a row listing
# two scopes is legitimately re-run for each of the two it names. An earlier
# draft keyed on "(every|each) scope" and failed exactly that sentence.
RETRY_ALL=$(tr '.' '\n' <<<"$ERRORS" \
  | grep -iE '(retry|re-?run|try)[^.]{0,120}(in turn|one by one|one after another|until (one|it|the|something)|try them all|every possible scope|all (three|the) scopes)|(in turn|one by one|until (one|it) (succeed|work))[^.]{0,120}(retry|re-?run|try)')
BLIND_RETRY=$(grep -ivE 'do not|don.t|never|avoid|rather than|instead of|without|no need' <<<"$RETRY_ALL")
check "the scope-mismatch branch does not prescribe a blind retry across every scope" \
  "$(nonblank "$BLIND_RETRY")" "no"

# --- 19g. Invariants (all GREEN at birth) ---------------------------------
# Sections 1-17 and 18h already carry most of this contract's invariant list:
# the single batch confirmation (§4), check mode staying read-only (§12),
# failure isolation and collection (§6), setup and prune-stamp.sh being
# offered and never run (§10, 18d), and a stale or absent stamp never blocking
# an update (§15, 18h). The guards below cover what those do not — that the
# statements living INSIDE the two regions this block edits survived the edit,
# and that the step numbering is untouched.
# The sequence, not the count: this block edits steps 2 and 6 and renumbers
# nothing, and a count alone cannot see a step 9 relabelled 10 — it stays nine
# lines either way. Verified against a probe that did exactly that.
STEP_NUMBERS=$(grep -oE '^[0-9]+\.' <<<"$BODY" | tr -d '.' | tr '\n' ' ' | sed -E 's/ +$//')
check "the flow's steps are still numbered 1-9 in order (nothing renumbered)" \
  "$STEP_NUMBERS" "1 2 3 4 5 6 7 8 9"
check "nothing is updated before the step 5 confirmation" \
  "$(has "$BODY_WS" 'nothing.{0,25}updated.{0,40}(until|before|without)')" "yes"
check "step 5 still asks a single question covering the whole batch" \
  "$(has "$STEP5" '(single|one) question|whole batch|entire batch|never nag')" "yes"
check "step 6 still addresses the plugin as <plugin>@clam" \
  "$(has_f "$STEP6" '@clam')" "yes"
check "step 6 still states a failure on one plugin does not abort the rest" \
  "$(has "$STEP6" 'does not abort|doesn.t abort|without aborting|keep going|continu.{0,20}(rest|others|remaining)')" "yes"
check "step 6 still collects every failure to report at the end" \
  "$(has "$STEP6" 'collect.{0,40}fail|fail.{0,40}collect|report.{0,40}at the end')" "yes"
check "the Errors section still carries its four pre-existing branches" \
  "$(grep -qiE 'not (found|available)' <<<"$ERRORS" \
     && grep -qF 'exit 3' <<<"$ERRORS" \
     && grep -qF 'exit 2' <<<"$ERRORS" \
     && grep -qF 'exit 4' <<<"$ERRORS" \
     && grep -qiE 'does not abort|keep going|per step 6' <<<"$ERRORS" \
     && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
