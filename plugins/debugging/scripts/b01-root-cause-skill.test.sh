#!/usr/bin/env bash
# Structural test for the root-cause skill (B01 root-cause-skill).
#
# Validates plugins/debugging/skills/root-cause/SKILL.md against its own
# contract docblock (see the HTML comment in that file). This is a guidance
# document, not executable code, so every check here is a document-shape /
# anchor-text assertion (never prose quality):
#
#   - frontmatter: fenced by '---', exactly the two keys `name` and
#     `description`, name is literally "root-cause", description non-empty
#   - body: the nine H2 phase headings, present IN ORDER, with the exact
#     contracted numbers/names
#   - phase 2 (Session setup) names the exact start command and the journal
#     artifact location
#   - each phase that loads a reference names that reference's relative path
#     together with a one-line load-when trigger (all six references:
#     reproduce, what-changed, differential-diagnosis, binary-search, logs,
#     database)
#   - phase 7 (Evidence) carries the paste-back protocol and the
#     ask-the-engineer-rather-than-guess access rule
#   - phase 8 (Root cause gate) states the explains-ALL-evidence gate and the
#     reopen-phase-5 consequence for unexplained evidence
#   - every phase says to journal before moving on
#   - delegation is marked optional at its two contracted minimum points
#     (repro attempts in phase 3; parallel hypothesis investigation in phase
#     5) and is never worded as mandatory anywhere in the body
#   - the evidence-contradicts-the-engineer edge case is surfaced somewhere
#   - altitude cap: body (contract docblock excluded) stays under 300 lines
#
# Anchor checks run against the body with the contract's own HTML-comment
# docblock stripped out (sed '/<!--/,/-->/d'), so the docblock text itself can
# never satisfy a check meant for the real prose.
#
# These MUST fail against the current `NotImplemented: B01` stub body and
# MUST pass once a real skill body satisfies the contract.
# Run: bash plugins/debugging/scripts/b01-root-cause-skill.test.sh
#      (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/root-cause/SKILL.md"

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

# Collapse newlines/whitespace to single spaces so multi-word phrase checks
# match regardless of where the prose happens to wrap.
flat() { printf '%s' "$1" | tr '\n' ' ' | tr -s '[:space:]' ' '; }

check "SKILL.md exists at the contract's Code path" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

if [[ ! -f "$SKILL" ]]; then
  echo "FAILURES (skill file missing, cannot continue)"
  exit 1
fi

# --- fixtures ---------------------------------------------------------------

FIRST_LINE=$(head -n1 "$SKILL")
DASH_LINE_COUNT=$(grep -cE '^---[[:space:]]*$' "$SKILL")

# Frontmatter: the YAML block between the first two '---' lines.
FRONTMATTER=$(awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1{print} n>=2{exit}' "$SKILL")

# Body: everything after the closing '---' of frontmatter.
BODY=$(awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n>=2{print}' "$SKILL")

# Anchor body: body with the contract's HTML-comment docblock stripped, so
# the docblock's own prose can never satisfy an anchor/section assertion —
# only real implementation content can.
ANCHOR_BODY=$(printf '%s\n' "$BODY" | sed '/<!--/,/-->/d')
FANCHOR_BODY=$(flat "$ANCHOR_BODY")

# Extract a single "## <heading>" section's body from ANCHOR_BODY (text up
# to, but not including, the next "## " heading). Heading match is exact
# (trailing whitespace ignored) so numbering/naming must be precise.
section() { # exact heading text, without the leading "## "
  printf '%s\n' "$ANCHOR_BODY" | awk -v h="$1" '
    { line = $0; sub(/[ \t]+$/, "", line) }
    line == "## " h {f=1; next}
    /^## / {f=0}
    f {print}
  '
}

# ===========================================================================
# Frontmatter (Outputs clause): fenced by ---, exactly two keys, name value,
# non-empty description. (Also covers the Inputs clause: "no frontmatter
# inputs" beyond name/description.)
# ===========================================================================

check "file opens with a '---' frontmatter fence" "$FIRST_LINE" "---"
check "at least two '---' fence lines delimit frontmatter" \
  "$([[ "$DASH_LINE_COUNT" -ge 2 ]] && echo yes || echo no)" "yes"

FM_KEYS=$(printf '%s\n' "$FRONTMATTER" | grep -oE '^[A-Za-z_][A-Za-z0-9_-]*:' | sed 's/:$//' | sort -u)
check "frontmatter has exactly the two keys: description, name" \
  "$FM_KEYS" "$(printf 'description\nname')"

NAME=$(printf '%s\n' "$FRONTMATTER" | grep -E '^name:' | head -1 | sed -E 's/^name:[[:space:]]*//; s/^"//; s/"$//')
check "frontmatter name is 'root-cause'" "$NAME" "root-cause"

DESC=$(printf '%s\n' "$FRONTMATTER" | grep -E '^description:' | head -1 | sed -E 's/^description:[[:space:]]*//; s/^"//; s/"$//')
check "description is non-empty" "$([[ -n "$DESC" ]] && echo yes || echo no)" "yes"

# ===========================================================================
# Outputs: the nine H2 phases, present IN ORDER with contracted names/numbers.
# ===========================================================================

EXPECTED_HEADINGS='## 1. Intake
## 2. Session setup
## 3. Reproduce
## 4. What changed
## 5. Differential diagnosis
## 6. Isolate
## 7. Evidence: logs and database
## 8. Root cause gate
## 9. Wrap-up'

for h in "1. Intake" "2. Session setup" "3. Reproduce" "4. What changed" \
         "5. Differential diagnosis" "6. Isolate" \
         "7. Evidence: logs and database" "8. Root cause gate" "9. Wrap-up"; do
  check "phase heading present: ## $h" \
    "$(printf '%s\n' "$ANCHOR_BODY" | awk -v h="## $h" '{l=$0; sub(/[ \t]+$/,"",l); if (l==h) f=1} END{print (f?"yes":"no")}')" "yes"
done

ACTUAL_HEADINGS=$(printf '%s\n' "$ANCHOR_BODY" | awk '{l=$0; sub(/[ \t]+$/,"",l); if (l ~ /^## /) print l}')
check "the nine phase headings appear in the contracted order" "$ACTUAL_HEADINGS" "$EXPECTED_HEADINGS"

# --- per-phase sections ------------------------------------------------------

PHASE1=$(section "1. Intake");                             FP1=$(flat "$PHASE1")
PHASE2=$(section "2. Session setup");                       FP2=$(flat "$PHASE2")
PHASE3=$(section "3. Reproduce");                           FP3=$(flat "$PHASE3")
PHASE4=$(section "4. What changed");                        FP4=$(flat "$PHASE4")
PHASE5=$(section "5. Differential diagnosis");              FP5=$(flat "$PHASE5")
PHASE6=$(section "6. Isolate");                             FP6=$(flat "$PHASE6")
PHASE7=$(section "7. Evidence: logs and database");         FP7=$(flat "$PHASE7")
PHASE8=$(section "8. Root cause gate");                     FP8=$(flat "$PHASE8")
PHASE9=$(section "9. Wrap-up");                              FP9=$(flat "$PHASE9")

# ===========================================================================
# Phase 1 (Intake): expected vs actual, scope, first-seen, problem statement.
# ===========================================================================

check "phase 1 captures expected vs actual behavior" \
  "$(has "$FP1" 'expected')$(has "$FP1" 'actual')" "yesyes"
check "phase 1 captures scope" "$(has "$FP1" 'scope')" "yes"
check "phase 1 captures first-seen" "$(has "$FP1" 'first[- ]seen')" "yes"
check "phase 1 produces a one-line problem statement" \
  "$(has "$FP1" 'problem statement')" "yes"

# ===========================================================================
# Phase 2 (Session setup): exact start command; journal artifact location.
# ===========================================================================

check "phase 2 runs the exact debug-session.sh start command" \
  "$(has_f "$PHASE2" '${CLAUDE_PLUGIN_ROOT}/scripts/debug-session.sh start')" "yes"
check "phase 2 names the .local/debug/ journal artifact tree" \
  "$(has_f "$FP2" '.local/debug/')" "yes"
check "phase 2 names journal.md as the journaling target" \
  "$(has_f "$FP2" 'journal.md')" "yes"

# ===========================================================================
# Phases 3-7: reach the surviving reference/*.md, each named with a one-line
# "load ... when ..." trigger on the same line as the path.
# ===========================================================================

# Checks that `ref` appears in the (already newline-flattened) flattened
# section text, together with a "load ... when ..." trigger in the same
# neighborhood (a window around the match) — not necessarily the same
# *source* line, since word-wrapping of prose is a formatting choice the
# contract does not constrain.
ref_trigger() { # flattened_section_content ref_path
  awk -v c="$1" -v r="$2" '
    BEGIN {
      idx = index(c, r)
      if (idx == 0) { print "missing"; exit }
      start = idx - 80; if (start < 1) start = 1
      win = tolower(substr(c, start, length(r) + 160))
      has_load = index(win, "load") > 0
      has_when = index(win, "when") > 0
      print (has_load && has_when) ? "present-with-trigger" : "present-no-trigger"
    }'
}

check "phase 3 loads references/reproduce.md with a load-when trigger" \
  "$(ref_trigger "$FP3" 'references/reproduce.md')" "present-with-trigger"
check "phase 4 loads references/what-changed.md with a load-when trigger" \
  "$(ref_trigger "$FP4" 'references/what-changed.md')" "present-with-trigger"
check "phase 5 loads references/differential-diagnosis.md with a load-when trigger" \
  "$(ref_trigger "$FP5" 'references/differential-diagnosis.md')" "present-with-trigger"
check "phase 6 loads references/binary-search.md with a load-when trigger" \
  "$(ref_trigger "$FP6" 'references/binary-search.md')" "present-with-trigger"
check "phase 7 loads references/logs.md with a load-when trigger" \
  "$(ref_trigger "$FP7" 'references/logs.md')" "present-with-trigger"
check "phase 7 loads references/database.md with a load-when trigger" \
  "$(ref_trigger "$FP7" 'references/database.md')" "present-with-trigger"

# ===========================================================================
# Phase 3 (Reproduce): reach a reliable repro.
# ===========================================================================

check "phase 3 aims for a reliable repro" \
  "$(has "$FP3" 'reliable')$(has "$FP3" 'repro')" "yesyes"

# ===========================================================================
# Phase 4 (What changed): candidate-change timeline.
# ===========================================================================

check "phase 4 builds a candidate-change timeline" \
  "$(has "$FP4" 'candidate')$(has "$FP4" 'timeline')" "yesyes"

# ===========================================================================
# Phase 5 (Differential diagnosis): hypothesis table, evidence, probes.
# ===========================================================================

check "phase 5 uses a hypothesis table with evidence and discriminating probes" \
  "$(has "$FP5" 'hypothesis')$(has "$FP5" 'evidence')$(has "$FP5" 'probe')" "yesyesyes"

# ===========================================================================
# Phase 6 (Isolate): binary-search the surviving search space.
# ===========================================================================

check "phase 6 binary-searches the search space" \
  "$(has "$FP6" 'binary')$(has "$FP6" 'search')" "yesyes"

# ===========================================================================
# Phase 7 (Evidence: logs and database): paste-back protocol + ask-the-
# engineer-rather-than-guess access rule.
# ===========================================================================

check "phase 7 uses the debug-session.sh query paste-back protocol" \
  "$(has_f "$FP7" 'debug-session.sh query')" "yes"
check "phase 7 instructs pasting results back" "$(has "$FP7" 'paste')" "yes"
check "phase 7 instructs asking the engineer when access is lacking" \
  "$(has "$FP7" 'ask')$(has "$FP7" 'engineer')" "yesyes"
check "phase 7 frames this as asking rather than guessing" "$(has "$FP7" 'guess')" "yes"

# ===========================================================================
# Phase 8 (Root cause gate): explains-ALL-evidence gate; reopens phase 5.
# ===========================================================================

check "phase 8 gates acceptance on explaining ALL evidence" \
  "$(has "$FP8" 'explain')$(has "$FP8" 'all')$(has "$FP8" 'evidence')" "yesyesyes"
check "phase 8 reopens phase 5 / differential diagnosis on unexplained evidence" \
  "$(has "$FP8" 'reopen')$(has "$FP8" 'phase 5|differential diagnos')" "yesyes"

# ===========================================================================
# Phase 9 (Wrap-up): root cause statement, fix direction, regression-test note.
# ===========================================================================

check "phase 9 records a root cause statement" "$(has "$FP9" 'root cause statement')" "yes"
check "phase 9 records a fix direction" "$(has "$FP9" 'fix direction')" "yes"
check "phase 9 records a repro-as-regression-test note" \
  "$(has "$FP9" 'regression test')" "yes"

# ===========================================================================
# Invariant: every phase says what to record in the journal.
# ===========================================================================

PHASE_LABELS=("1. Intake" "2. Session setup" "3. Reproduce" "4. What changed" \
              "5. Differential diagnosis" "6. Isolate" \
              "7. Evidence: logs and database" "8. Root cause gate" "9. Wrap-up")
PHASE_CONTENTS=("$FP1" "$FP2" "$FP3" "$FP4" "$FP5" "$FP6" "$FP7" "$FP8" "$FP9")

for i in "${!PHASE_LABELS[@]}"; do
  check "phase mentions journaling: ${PHASE_LABELS[$i]}" \
    "$(has "${PHASE_CONTENTS[$i]}" 'journal')" "yes"
done

# ===========================================================================
# Invariant: delegation optional at its two contracted minimum points, never
# worded as mandatory anywhere.
# ===========================================================================

check "delegation is marked optional somewhere in the body" \
  "$(has "$FANCHOR_BODY" 'delegat')$(has "$FANCHOR_BODY" 'option')" "yesyes"
check "phase 3 marks delegating repro attempts as a delegation point" \
  "$(has "$FP3" 'delegat')" "yes"
check "phase 5 marks parallel hypothesis investigation as a delegation point" \
  "$(has "$FP5" 'delegat')$(has "$FP5" 'parallel')" "yesyes"
check "delegation is never worded as mandatory" \
  "$(has "$FANCHOR_BODY" 'must (delegate|use a subagent|dispatch)|always delegate|mandatory delegation|requires? delegation')" "no"

# ===========================================================================
# Edge case: evidence contradicting the engineer's description is surfaced
# to the engineer, not silently resolved.
# ===========================================================================

check "contradictory evidence is surfaced to the engineer" \
  "$(has "$FANCHOR_BODY" 'contradict')$(has "$FANCHOR_BODY" 'engineer')" "yesyes"

# ===========================================================================
# Altitude cap: body (docblock excluded) stays under 300 lines.
# ===========================================================================

ANCHOR_LINE_COUNT=$(printf '%s\n' "$ANCHOR_BODY" | wc -l)
check "body stays under 300 lines" \
  "$([[ "$ANCHOR_LINE_COUNT" -lt 300 ]] && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
