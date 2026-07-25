#!/bin/bash
# Structural/content tests for skills/run/SKILL.md against Contract: B02
# updates-run-skill (see the HTML-comment docblock in that file).
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
# RED/GREEN at birth (scaffold state, see brief 01-test-B02.md):
#   - Frontmatter checks are GREEN already: name/disable-model-invocation/
#     description landed at scaffold with their full contracted content.
#   - Every body-content check is RED against the current stub: the body is
#     only a "NotImplemented: B02" placeholder line (plus the stripped
#     contract comment), so none of the contracted facts are stated in the
#     skill's own prose yet.
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
# Run: bash plugins/updates/scripts/run-skill.test.sh (exits non-zero on
# failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/run/SKILL.md"

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

check "frontmatter name is 'run'" "$NAME" "run"
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
  "$(grep -qiE 'updates.{0,20}(itself|plugin).{0,70}(next session|reload)|itself.{0,40}(next session|reload)' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"

# --- 17. Zero clam plugins installed ---------------------------------------
check "zero clam plugins installed: reports and stops" \
  "$(grep -qiE 'no (clam )?plugins?.{0,15}installed|zero.{0,15}plugins?.{0,15}installed' <<<"$BODY_FLAT" && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
