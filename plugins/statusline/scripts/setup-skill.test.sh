#!/bin/bash
# Test for Block B11 (setup-wiring), plan 001-statusline-glance-uplift, and
# Block B14 (setup-schedule-step), plan 002-setup-schedule-disclosure.
#
# The implementation of this block is prose: `/statusline:setup` is a skill
# document executed by an LLM, at plugins/statusline/skills/setup/SKILL.md.
# So every assertion here is structural or textual over that file, the same
# style scripts/readme.test.sh uses against the README.
#
# Authoritative contract: .local/contracts/B11-setup-wiring.md (orchestrator
# owned, not shipped). The clauses, and where each is checked:
#
#   Behavior   - setup writes `subagentStatusLine` (pointing at
#                scripts/subagent.sh) and `refreshInterval: 5` alongside the
#                existing `statusLine`; remove deletes all three.  Sections
#                2, 3, 4, 6, 7.
#   Inputs     - the resolved plugin root; the current ~/.claude/settings.json.
#                Section 1.
#   Outputs    - all three keys merged with every other setting preserved, a
#                timestamped backup taken first, a setup stamp per the shared
#                protocol.  Sections 3, 5, 8.
#   Errors     - `jq empty` after writing; a failed stamp write is reported
#                but never fails setup.  Section 8.
#   Invariants - merge, never overwrite; ask before replacing a different
#                statusline already configured, now for EITHER key; remove
#                restores the pre-setup state for all three.  Sections 3, 6, 7.
#   Edge cases - a backup predating the new keys / a key that was never
#                written; a user's own foreign `refreshInterval`.  Sections
#                6, 7.
#
# B14's contract lives in an HTML comment in SKILL.md while the block is in
# flight. Its clauses, and where each is checked (all of section 10):
#
#   Behavior   - setup always discloses the effective working week and asks
#                once; it writes the three schedule env keys only on a
#                non-default answer, in the SAME jq merge as the statusline
#                keys; remove deletes them.  Sections 10c, 10d, 10e, 10i.
#   Inputs     - the `env` block of ~/.claude/settings.json (absent file or
#                block = the Mon-Fri 08:00-18:00 defaults); an answer
#                constrained to the documented knob domains.  Sections 10b,
#                10f.
#   Outputs    - the new step is numbered 3 and the old 3-5 became 4-6; it
#                renders days and hours with each value marked default or
#                set, states the trend-arrow pacing line, points at the
#                README section, asks keep-or-change; keep writes nothing,
#                change joins step 4's single jq as .env.CLAM_STATUSLINE_*
#                string values.  Sections 10a, 10c, 10d, 10e.
#   Errors     - an out-of-domain answer is re-asked and never written; an
#                end at or before the start is rejected as a pair; no new
#                failure mode on the settings read/write path.  Section 10f
#                (and the no-jq/no-mv pair at the end of 10e).
#   Invariants - setup stays ONE jq pass (section 3's exactly-once check),
#                remove stays one del() pass, other env keys survive, the
#                keep path leaves the schedule keys as they were.  Sections
#                3, 10d, 10i.
#   Edge cases - some but not all three keys set; the 0.9.0 note whenever
#                DAY_START is already set; remove with no env block or no
#                schedule keys; remove that empties the env block.  Sections
#                10g, 10h, 10i.
#
# THE PLUGIN-ROOT PLACEHOLDER IS DERIVED, NOT TRANSCRIBED. The document writes
# the context.sh command as `<plugin-root>/scripts/context.sh`. Section 4 reads
# that placeholder off the document itself and then requires the SAME
# placeholder in front of `/scripts/subagent.sh`, so the two commands cannot
# drift apart and a renamed placeholder needs no edit here.
#
# THE STEP-2 SNIPPET IS PARSED, NOT GREPPED. Every ```json fence in step 2 is
# run through jq: it must be valid JSON, and the union of the fences' top-level
# keys must carry all three settings. `refreshInterval`'s value and
# `subagentStatusLine`'s command are then read out of the parsed object rather
# than matched as text, so a snippet that merely mentions the words does not
# pass.
#
# NON-VACUITY. Every absence or content check below is paired with a guard that
# the text it scans exists: the two H2 sections, steps 2 and 3, the extracted
# fences, the ask-sentences, and the refresh-rationale prose are each asserted
# non-empty before anything is asserted about their contents. An anchor aimed
# at an empty string passes for free, which is the failure mode these guards
# exist to catch.
#
# DELIBERATELY NOT COVERED. Whether the rationale prose is *persuasive*, and
# whether the LLM executing this document actually produces a correct
# settings.json, are not mechanically assertable from the file; both are
# deferred to orchestrator verification at acceptance. The stamp-file protocol
# details (corrupt-file handling, `at` from `date -u`) are pre-existing prose
# this block does not own and are checked only to the extent the contract's
# Errors clause names them ("unchanged").
#
# Run: bash plugins/statusline/scripts/setup-skill.test.sh (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$PLUGIN_DIR/skills/setup/SKILL.md"
SUBAGENT_SH="$PLUGIN_DIR/scripts/subagent.sh"
CONTEXT_SH="$PLUGIN_DIR/scripts/context.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

has_re()    { grep -qiE "$1" <<<"$2" && echo yes || echo no; }   # case-insensitive ERE
has_cs()    { grep -qE  "$1" <<<"$2" && echo yes || echo no; }   # case-SENSITIVE ERE
has_fixed() { grep -qF  "$1" <<<"$2" && echo yes || echo no; }   # literal substring
one_line()  { tr '\n' ' ' <<<"$1" | sed -e 's/  *$//'; }
# Prose wraps and is indented, so a phrase that reads as "never fail the setup"
# in the rendered document is "the\n     setup" in the file. Every check that
# looks for a multi-word phrase reads flat(): newlines to spaces, runs of
# whitespace squeezed to one.
flat()      { tr '\n' ' ' <<<"$1" | tr -s '[:space:]' ' '; }
nonempty()  { [ -n "$(tr -d '[:space:]' <<<"$1")" ] && echo yes || echo no; }

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "skills/setup/SKILL.md exists" \
  "$([ -f "$SKILL_MD" ] && echo yes || echo no)" "yes"
check "scripts/subagent.sh exists (the command subagentStatusLine points at)" \
  "$([ -f "$SUBAGENT_SH" ] && echo yes || echo no)" "yes"
check "scripts/context.sh exists (the command statusLine points at)" \
  "$([ -f "$CONTEXT_SH" ] && echo yes || echo no)" "yes"
check "jq is available (this suite parses the document's JSON snippets)" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" "yes"

# HTML COMMENTS ARE STRIPPED BEFORE ANY CONTENT CHECK. An orchestrator-owned
# contract comment lives in this document while a block is in flight, and it
# quotes the very prose the checks below look for. Reading the document with
# those comment blocks removed means the contract can never satisfy a check
# about the shipped prose -- only the shipped prose can.
BODY="$(sed -e '/<!--/,/-->/d' "$SKILL_MD" 2>/dev/null)"

section() { # $1 = exact "## Heading" line, reads $BODY
  awk -v heading="$1" '
    $0 == heading { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$BODY"
}

# shellcheck disable=SC2016  # a literal markdown heading; the backticks are text
SETUP="$(section '## `/statusline:setup`')"
# shellcheck disable=SC2016  # a literal markdown heading; the backticks are text
REMOVE="$(section '## `/statusline:setup remove`')"
NOTES="$(section '## Notes')"

check "the '/statusline:setup' section is present and non-empty" \
  "$(nonempty "$SETUP")" "yes"
check "the '/statusline:setup remove' section is present and non-empty" \
  "$(nonempty "$REMOVE")" "yes"
check "the 'Notes' section is present and non-empty" \
  "$(nonempty "$NOTES")" "yes"

step() { # $1 = step number, reads $SETUP
  awk -v n="$1" '
    $0 ~ ("^" n "\\. ") { flag=1; print; next }
    flag && /^[0-9]+\. / { exit }
    flag { print }
  ' <<<"$SETUP"
}

STEP1="$(step 1)"
STEP2="$(step 2)"
# B14 renumbers the setup steps: the schedule-disclosure step becomes step 3
# and the old steps 3-5 (merge / verify / stamp) become 4-6. Every check below
# anchors on the post-renumbering layout.
STEP3="$(step 3)"
STEP4="$(step 4)"
STEP5="$(step 5)"
STEP6="$(step 6)"
STEP7="$(step 7)"

check "setup step 1 (resolve the plugin root) is present and non-empty" \
  "$(nonempty "$STEP1")" "yes"
check "setup step 2 (show the change before making it) is present and non-empty" \
  "$(nonempty "$STEP2")" "yes"
check "setup step 3 (disclose the working week) is present and non-empty" \
  "$(nonempty "$STEP3")" "yes"
check "setup step 4 (merge, don't overwrite) is present and non-empty" \
  "$(nonempty "$STEP4")" "yes"

fences() { # $1 = text, $2 = fence tag, $3 = output prefix; prints how many it wrote
  awk -v tag="$2" -v out="$3" '
    /^[[:space:]]*```/ {
      if (inb) { inb = 0; next }
      if (index($0, "```" tag) > 0) { inb = 1; n++ }
      next
    }
    inb { print > (out n) }
    END { }
  ' <<<"$1"
  # shellcheck disable=SC2012  # only the count is used, over awk-written names
  # of the form <prefix><n> in a private temp dir -- no odd characters possible
  ls "$3"* 2>/dev/null | wc -l | tr -d ' '
}

# ---------------------------------------------------------------------------
# 1. Inputs: the resolved plugin root, and the current settings.json
# ---------------------------------------------------------------------------

check "step 1 resolves the plugin root" \
  "$(has_re 'plugin root' "$STEP1")" "yes"
# shellcheck disable=SC2088  # a literal string searched for in the document, not a path
check "step 2 reads ~/.claude/settings.json" \
  "$(has_fixed '~/.claude/settings.json' "$STEP2")" "yes"
check "step 2 treats a missing settings file as an empty object" \
  "$(has_re 'missing file as .\{0,3\}\{\}|treat a missing' "$STEP2")" "yes"

# ---------------------------------------------------------------------------
# 2. Step 2 shows BOTH keys (all three settings) before anything is written
# ---------------------------------------------------------------------------

check "step 2 names statusLine" \
  "$(has_cs 'statusLine' "$STEP2")" "yes"
check "step 2 names subagentStatusLine" \
  "$(has_cs 'subagentStatusLine' "$STEP2")" "yes"
check "step 2 names refreshInterval" \
  "$(has_cs 'refreshInterval' "$STEP2")" "yes"
check "step 2 reports the CURRENT value(s) before writing" \
  "$(has_re 'current' "$STEP2")" "yes"

# The snippet step 2 shows the user is parsed, not grepped.
N_FENCES="$(fences "$STEP2" json "$TMP/s2f")"
check "step 2 contains at least one json fence (the entry it is about to write)" \
  "$([ "${N_FENCES:-0}" -ge 1 ] && echo yes || echo no)" "yes"

: > "$TMP/s2keys"
: > "$TMP/s2bad"
S2_REFRESH=""
S2_SUBCMD=""
S2_STATUSCMD=""
for f in "$TMP"/s2f*; do
  [ -f "$f" ] || continue
  if jq empty "$f" >/dev/null 2>&1; then
    jq -r 'keys[]' "$f" >> "$TMP/s2keys" 2>/dev/null
    v="$(jq -r '.refreshInterval? // empty' "$f" 2>/dev/null)"
    [ -n "$v" ] && S2_REFRESH="$v"
    v="$(jq -r '.subagentStatusLine?.command? // empty' "$f" 2>/dev/null)"
    [ -n "$v" ] && S2_SUBCMD="$v"
    v="$(jq -r '.statusLine?.command? // empty' "$f" 2>/dev/null)"
    [ -n "$v" ] && S2_STATUSCMD="$v"
  else
    basename "$f" >> "$TMP/s2bad"
  fi
done
sort -u "$TMP/s2keys" -o "$TMP/s2keys" 2>/dev/null

check "every json fence in step 2 is valid JSON" \
  "$(one_line "$(cat "$TMP/s2bad")")" ""
check "step 2's json snippet(s) show the statusLine entry" \
  "$(grep -qx 'statusLine' "$TMP/s2keys" && echo yes || echo no)" "yes"
check "step 2's json snippet(s) show the subagentStatusLine entry" \
  "$(grep -qx 'subagentStatusLine' "$TMP/s2keys" && echo yes || echo no)" "yes"
check "step 2's json snippet(s) show the refreshInterval entry" \
  "$(grep -qx 'refreshInterval' "$TMP/s2keys" && echo yes || echo no)" "yes"
check "step 2's snippet sets refreshInterval to 5" "$S2_REFRESH" "5"
check "step 2's snippet points statusLine at scripts/context.sh" \
  "$(case "$S2_STATUSCMD" in (*/scripts/context.sh) echo yes ;; (*) echo "no ($S2_STATUSCMD)" ;; esac)" "yes"
check "step 2's snippet points subagentStatusLine at scripts/subagent.sh" \
  "$(case "$S2_SUBCMD" in (*/scripts/subagent.sh) echo yes ;; (*) echo "no ($S2_SUBCMD)" ;; esac)" "yes"

# ---------------------------------------------------------------------------
# 3. Step 4 (the merge step): ONE jq merges all three keys, preserving every
#    other setting
# ---------------------------------------------------------------------------

N_BASH="$(fences "$STEP4" bash "$TMP/s3f")"
check "step 4 contains a bash fence (the write command)" \
  "$([ "${N_BASH:-0}" -ge 1 ] && echo yes || echo no)" "yes"
S3CMD="$(cat "$TMP"/s3f* 2>/dev/null)"
check "step 4's bash fence is non-empty" "$(nonempty "$S3CMD")" "yes"

check "step 4 invokes jq exactly once" \
  "$(grep -coE '(^|[|&;]|[[:space:]])jq[[:space:]]' <<<"$S3CMD" | tr -d ' ')" "1"
check "that one jq sets statusLine" \
  "$(has_cs '\.statusLine' "$S3CMD")" "yes"
check "that one jq sets subagentStatusLine" \
  "$(has_cs '\.subagentStatusLine' "$S3CMD")" "yes"
check "that one jq sets refreshInterval" \
  "$(has_cs '\.refreshInterval' "$S3CMD")" "yes"
check "that one jq sets refreshInterval to 5" \
  "$(has_cs '\.refreshInterval[[:space:]]*=[[:space:]]*5([^0-9]|$)' "$S3CMD")" "yes"
check "that one jq names scripts/subagent.sh" \
  "$(has_fixed 'scripts/subagent.sh' "$S3CMD")" "yes"
check "that one jq names scripts/context.sh" \
  "$(has_fixed 'scripts/context.sh' "$S3CMD")" "yes"

# Merge, never overwrite: the existing settings file is the jq INPUT (so
# untouched keys survive), and the write is atomic via a temp file + mv.
# shellcheck disable=SC2088  # a literal string searched for in the document, not a path
check "the jq reads the existing ~/.claude/settings.json as its input" \
  "$(has_fixed '~/.claude/settings.json' "$S3CMD")" "yes"
check "the jq does not build a fresh document with -n (that would drop other settings)" \
  "$(has_cs 'jq[^\n]*[[:space:]]-n([[:space:]]|$)' "$S3CMD")" "no"
check "the write goes through a temp file and mv" \
  "$(has_cs 'mv[[:space:]]' "$S3CMD")" "yes"
check "step 4 states that every other setting is preserved" \
  "$(has_re 'preserv' "$STEP4")" "yes"

# ---------------------------------------------------------------------------
# 4. subagentStatusLine's command sits under the SAME resolved plugin root as
#    statusLine's — the placeholder is derived from the document, not typed in
# ---------------------------------------------------------------------------

ROOT_PLACEHOLDER="$(grep -oE '[^"[:space:]`]*/scripts/context\.sh' <<<"$BODY" | head -1 | sed -e 's#/scripts/context\.sh$##')"
check "a plugin-root placeholder was derived from the document" \
  "$(nonempty "$ROOT_PLACEHOLDER")" "yes"
check "the document names <root>/scripts/subagent.sh with that same placeholder" \
  "$(has_fixed "$ROOT_PLACEHOLDER/scripts/subagent.sh" "$BODY")" "yes"

# ---------------------------------------------------------------------------
# 5. Outputs: a timestamped backup is taken first
# ---------------------------------------------------------------------------

check "setup backs the original settings file up first" \
  "$(has_re 'back (it |the .*)?up|back up the original|backup' "$SETUP")" "yes"
check "the backup name carries a timestamp" \
  "$(has_re 'settings\.json\.bak-|bak-<date>' "$SETUP")" "yes"

# ---------------------------------------------------------------------------
# 6. Merge, never overwrite: ask before replacing EITHER key, and before
#    changing a foreign refreshInterval
# ---------------------------------------------------------------------------

# Split on sentence-final punctuation followed by a SPACE. Not on every
# period: `context.sh` and `settings.json` are full of periods that are not
# sentence ends, and splitting there would let a clause be scored against the
# wrong sentence.
sentences() { flat "$1" | sed -e 's/\([.!?]\) /\1\
/g'; }

ASK="$(sentences "$SETUP" | grep -i 'ask')"
check "the setup section has an ask-before-replacing rule" \
  "$(nonempty "$ASK")" "yes"
check "the ask rule covers an already-configured statusLine" \
  "$(has_cs 'statusLine' "$ASK")" "yes"
check "the ask rule covers an already-configured subagentStatusLine" \
  "$(has_cs 'subagentStatusLine' "$ASK")" "yes"
check "the ask rule covers a user's own refreshInterval" \
  "$(has_cs 'refreshInterval' "$ASK")" "yes"
check "the ask rule is about replacing/changing what is already there" \
  "$(has_re 'replac|chang|overwrit' "$ASK")" "yes"

# ---------------------------------------------------------------------------
# 7. The remove path reverses all three keys, and survives a backup that
#    predates the new ones
# ---------------------------------------------------------------------------

check "remove names statusLine" \
  "$(has_cs 'statusLine' "$REMOVE")" "yes"
check "remove names subagentStatusLine" \
  "$(has_cs 'subagentStatusLine' "$REMOVE")" "yes"
check "remove names refreshInterval" \
  "$(has_cs 'refreshInterval' "$REMOVE")" "yes"
check "remove deletes the keys it names" \
  "$(has_re 'delete|remove' "$REMOVE")" "yes"
check "remove preserves all other settings" \
  "$(has_re 'preserv|all other settings' "$REMOVE")" "yes"

# The edge case: a user of the previous version has only `statusLine`, and a
# backup that predates the other two keys. Scoped to the SENTENCE so that a
# stray "absent" elsewhere in the section cannot satisfy it.
REMOVE_ABSENT="$(sentences "$REMOVE" | grep -iE 'absent|missing|not (present|there|set)|never (written|set|configured)|was not|predat|older|earlier|previous version|only .*statusLine')"
check "remove has a sentence about a key that may not be there" \
  "$(nonempty "$REMOVE_ABSENT")" "yes"
check "that sentence is about one of the two new keys" \
  "$(has_cs 'subagentStatusLine|refreshInterval|both new|new keys' "$REMOVE_ABSENT")" "yes"
check "that sentence says an absent key is not an error" \
  "$(has_re 'already fine|nothing to do|no error|not an error|harmless|skip' "$REMOVE_ABSENT")" "yes"
check "remove still clears this plugin's setup stamp record" \
  "$(has_re 'stamp' "$REMOVE")" "yes"

# ---------------------------------------------------------------------------
# 8. Errors clause, unchanged: verify with jq empty; a failed stamp write is
#    reported but never fails the setup
# ---------------------------------------------------------------------------

check "setup verifies the written file with jq empty" \
  "$(has_fixed 'jq empty ~/.claude/settings.json' "$SETUP")" "yes"
check "setup records a stamp per the shared protocol" \
  "$(has_fixed 'docs/protocols/setup-stamp.md' "$SETUP")" "yes"
# Prose wraps, so this reads the section with its newlines collapsed.
check "a failed stamp write is reported but never fails the setup" \
  "$(has_re 'never fail the setup' "$(flat "$SETUP")")" "yes"

# ---------------------------------------------------------------------------
# 9. refreshInterval is 5, and the prose says WHY
# ---------------------------------------------------------------------------

# Every refreshInterval value the document names is 5 (guarded: at least one
# value must have been found, or this compares nothing).
# shellcheck disable=SC2016  # a literal regex; the backticks are markdown to match
grep -oE '`?refreshInterval`?[^0-9]{0,16}[0-9]+' <<<"$BODY" \
  | grep -oE '[0-9]+$' | sort -u > "$TMP/refresh-values"
check "the document names at least one refreshInterval value" \
  "$([ -s "$TMP/refresh-values" ] && echo yes || echo no)" "yes"
check "every refreshInterval value the document names is 5" \
  "$(one_line "$(cat "$TMP/refresh-values")")" "5"

# The rationale: the paragraphs that talk about the refresh interval.
# Newlines collapsed: the wording below can and does wrap mid-phrase.
RATIONALE="$(flat "$(awk 'BEGIN { RS = "" } tolower($0) ~ /refresh/ { print; print "" }' <<<"$BODY")")"
check "the document has prose about the refresh interval" \
  "$(nonempty "$RATIONALE")" "yes"
check "the rationale names the event-driven triggers" \
  "$(has_re 'event.driven|event-based|trigger' "$RATIONALE")" "yes"
check "the rationale says those triggers go quiet / stop firing" \
  "$(has_re 'go quiet|goes quiet|quiet|stop firing|do not fire|don.t fire|no events' "$RATIONALE")" "yes"
check "the rationale ties that to waiting on background subagents" \
  "$(has_re 'subagent' "$RATIONALE")" "yes"
check "the rationale says the wait is on background work" \
  "$(has_re 'background|waiting|waits on|while .*wait' "$RATIONALE")" "yes"
check "the rationale names what would freeze on screen (the countdown and/or the trends)" \
  "$(has_re 'countdown|5-hour|five-hour|trend' "$RATIONALE")" "yes"
check "the rationale says those figures would freeze/go stale" \
  "$(has_re 'freeze|frozen|stale|stuck|not update|never update' "$RATIONALE")" "yes"

# ---------------------------------------------------------------------------
# 10. Block B14 (setup-schedule-step): setup discloses the effective working
#     week, asks keep-or-change, folds a changed answer into the SAME jq
#     merge, and remove deletes the three schedule env keys.
#
# Every check here runs over the comment-stripped $BODY (see the strip at the
# top), so the in-flight contract comment cannot satisfy any of them.
#
# WORD BOUNDARIES ARE SPELLED OUT, NOT `\b`. This suite runs under both BSD
# and GNU grep; `\b` is not portable across them, so boundary-sensitive
# patterns use explicit ( |^|`) style alternations over flat() text.
# ---------------------------------------------------------------------------

SCHED="$(step 3)"
SCHED_FLAT="$(flat "$SCHED")"
STEP4_FLAT="$(flat "$STEP4")"
REMOVE_FLAT="$(flat "$REMOVE")"
README_MD="$PLUGIN_DIR/README.md"

# --- 10a. The renumbering: schedule step is 3, old 3-5 became 4-6 -----------

check "step 3 is the schedule-disclosure step (names the working week)" \
  "$(has_re 'working week|work(ing)? days|schedule' "$SCHED")" "yes"
check "step 4 is the merge step (merge, don't overwrite)" \
  "$(has_re 'merge' "$STEP4")" "yes"
check "step 5 is the verify step" \
  "$(has_re 'verif' "$STEP5")" "yes"
check "step 5 is the one that runs jq empty over the settings file" \
  "$(has_fixed 'jq empty ~/.claude/settings.json' "$STEP5")" "yes"
check "step 6 is the setup-stamp step" \
  "$(has_re 'stamp' "$STEP6")" "yes"
check "the setup section stops at step 6 (no step 7 was introduced)" \
  "$(nonempty "$STEP7")" "no"

# --- 10b. Inputs: the env block, and the documented defaults ----------------

check "step 3 reads the settings file's env block" \
  "$(has_re 'env block|env.{1,2}block' "$SCHED_FLAT")" "yes"
check "step 3 names all three schedule knobs: WORK_DAYS" \
  "$(has_cs 'CLAM_STATUSLINE_WORK_DAYS' "$SCHED")" "yes"
check "step 3 names all three schedule knobs: DAY_START" \
  "$(has_cs 'CLAM_STATUSLINE_DAY_START' "$SCHED")" "yes"
check "step 3 names all three schedule knobs: DAY_END" \
  "$(has_cs 'CLAM_STATUSLINE_DAY_END' "$SCHED")" "yes"
check "step 3 gives the Mon-Fri default days" \
  "$(has_re 'mon(day)?[^a-z]{0,14}fri(day)?|1-5' "$SCHED_FLAT")" "yes"
check "step 3 gives the 08:00-18:00 default hours" \
  "$(has_re '(08:00|08|8)[^0-9]{1,14}(18:00|18)' "$SCHED_FLAT")" "yes"
SCHED_ABSENT="$(sentences "$SCHED" | grep -iE 'absent|missing|no env|not set|unset|never set')"
check "step 3 has a sentence about the settings file or env block not being there" \
  "$(nonempty "$SCHED_ABSENT")" "yes"
check "that sentence says the absent case means the defaults" \
  "$(has_re 'default' "$SCHED_ABSENT")" "yes"

# --- 10c. Outputs: the disclosure itself ------------------------------------

check "step 3 renders the schedule in plain words (which days)" \
  "$(has_re 'day' "$SCHED_FLAT")" "yes"
check "step 3 renders the start and end hours" \
  "$(has_re 'hour|start.{0,12}end|from .{0,8} to ' "$SCHED_FLAT")" "yes"
check "step 3 marks each value as a default" \
  "$(has_re '(^| |\()default( |,|\)|\"|.$)' "$SCHED_FLAT")" "yes"
check "step 3 marks a configured value as set" \
  "$(has_re '(^| |\()set( |,|\)|\"|.$)' "$SCHED_FLAT")" "yes"
MARKED="$(sentences "$SCHED" | grep -iE 'default' | grep -iE '(^| |\()set( |,|\)|\"|.$)')"
check "one sentence carries the default-or-set marking rule" \
  "$(nonempty "$MARKED")" "yes"

# The pacing rationale: the trend arrow moves with the schedule, the raw
# weekly percentage and the reset countdown do not.
PACING="$(sentences "$SCHED" | grep -iE 'trend')"
check "step 3 has a sentence about the weekly trend arrow" \
  "$(nonempty "$PACING")" "yes"
check "that sentence says the trend arrow paces against this schedule" \
  "$(has_re 'pace|paced|paces|moves with|follows|against this schedule' "$PACING")" "yes"
check "step 3 names the raw wk used% figure as not moving with the schedule" \
  "$(has_re 'wk used|weekly (used )?percent|used%' "$SCHED_FLAT")" "yes"
check "step 3 names the reset countdown as not moving with the schedule" \
  "$(has_re 'countdown|reset' "$SCHED_FLAT")" "yes"
check "step 3 states the negation for those two figures" \
  "$(has_re 'do not|does not|don.t|doesn.t|never|unaffected|not paced|independent' "$SCHED_FLAT")" "yes"

# The README pointer, with a cross-file guard: the section it points at must
# actually exist, or this check would anchor on a heading nobody wrote.
check "the README has the 'Match the pacing...' section this step points at" \
  "$(has_fixed 'Match the pacing to the hours you actually work' "$(cat "$README_MD" 2>/dev/null)")" "yes"
check "step 3 points at the README" \
  "$(has_re 'README' "$SCHED")" "yes"
check "step 3 names the README section by title" \
  "$(has_fixed 'Match the pacing to the hours you actually work' "$SCHED_FLAT")" "yes"

# --- 10d. The keep-or-change ask -------------------------------------------

check "step 3 asks the user" \
  "$(has_re 'ask' "$SCHED")" "yes"
check "the ask offers keeping the current schedule" \
  "$(has_re 'keep' "$SCHED_FLAT")" "yes"
check "the ask offers changing it" \
  "$(has_re 'chang' "$SCHED_FLAT")" "yes"
KEEPS="$(sentences "$SCHED" | grep -iE 'keep')"
check "step 3 has a sentence describing the keep path" \
  "$(nonempty "$KEEPS")" "yes"
check "the keep path writes nothing / leaves the settings untouched" \
  "$(has_re 'nothing is written|writes nothing|no env key|no key is written|not written|untouched|unchanged' "$KEEPS")" "yes"
check "the keep path is about the env block / settings file" \
  "$(has_re 'env|settings' "$KEEPS")" "yes"

# --- 10e. The change path folds into the SAME single jq merge --------------
# (that the merge is ONE jq invocation is asserted in section 3 above)

check "the merge step sets .env.CLAM_STATUSLINE_WORK_DAYS" \
  "$(has_cs '\.env\.CLAM_STATUSLINE_WORK_DAYS' "$STEP4_FLAT")" "yes"
check "the merge step sets .env.CLAM_STATUSLINE_DAY_START" \
  "$(has_cs '\.env\.CLAM_STATUSLINE_DAY_START' "$STEP4_FLAT")" "yes"
check "the merge step sets .env.CLAM_STATUSLINE_DAY_END" \
  "$(has_cs '\.env\.CLAM_STATUSLINE_DAY_END' "$STEP4_FLAT")" "yes"
ENVSTR="$(sentences "$STEP4" | grep -iE 'env')"
check "the merge step has prose about the env keys" \
  "$(nonempty "$ENVSTR")" "yes"
check "the merge step says the env values are written as strings" \
  "$(has_re 'string' "$ENVSTR")" "yes"
check "the schedule keys are written only when the user changed the answer" \
  "$(has_re 'only (if|when)|if the user (chose|asked|changed)|when .{0,24}chang' "$STEP4_FLAT")" "yes"

# No new failure mode on the settings read/write path: the disclosure step
# itself neither runs jq nor moves a file into place -- the one write stays
# in the merge step.
check "step 3 runs no jq of its own" \
  "$(has_cs '(^|[|&;]|[[:space:]])jq([[:space:]]|$)' "$SCHED")" "no"
check "step 3 writes no file of its own (no mv into place)" \
  "$(has_cs '(^|[|&;]|[[:space:]])mv[[:space:]]' "$SCHED")" "no"

# --- 10f. Domain validation and re-ask -------------------------------------

check "step 3 documents the WORK_DAYS domain as ISO weekday numbers 1-7" \
  "$(has_re 'ISO' "$SCHED_FLAT")" "yes"
check "step 3 documents the WORK_DAYS domain bounds (1-7)" \
  "$(has_re '1-7|1 to 7|1\.\.7' "$SCHED_FLAT")" "yes"
# "comma" alone would match "command", which the jq snippets are full of.
check "step 3 documents commas for WORK_DAYS" \
  "$(has_re 'commas|comma-separated|comma and|comma or' "$SCHED_FLAT")" "yes"
check "step 3 documents ranges for WORK_DAYS" \
  "$(has_re 'range' "$SCHED_FLAT")" "yes"
check "step 3 documents the DAY_START domain 0..23" \
  "$(has_re '0\.\.23|0-23|0 to 23' "$SCHED_FLAT")" "yes"
check "step 3 documents the DAY_END domain 1..24" \
  "$(has_re '1\.\.24|1-24|1 to 24' "$SCHED_FLAT")" "yes"
check "step 3 requires DAY_END strictly greater than DAY_START" \
  "$(has_re 'strictly greater|greater than|later than|after the start' "$SCHED_FLAT")" "yes"
INVALID="$(sentences "$SCHED" | grep -iE 're-?ask|ask again|outside|invalid|reject')"
check "step 3 has a sentence about an answer outside the documented domains" \
  "$(nonempty "$INVALID")" "yes"
check "an out-of-domain answer is re-asked" \
  "$(has_re 're-?ask|ask again|ask .{0,20}again' "$SCHED_FLAT")" "yes"
check "an out-of-domain answer is never written" \
  "$(has_re 'never written|not written|nothing is written|without writing|never write' "$SCHED_FLAT")" "yes"
PAIR="$(sentences "$SCHED" | grep -iE 'pair|together|both')"
check "step 3 has a sentence about the start/end pair" \
  "$(nonempty "$PAIR")" "yes"
check "an end at or before the start is rejected as a pair" \
  "$(has_re 'reject|re-?ask|ask again|not accept' "$PAIR")" "yes"
check "step 3 ties the pair rule to the render's own fallback rule" \
  "$(has_re 'fall(s)? back|fallback|same rule|render' "$SCHED_FLAT")" "yes"

# --- 10g. Edge case: some but not all three keys already set ---------------

MIX="$(sentences "$SCHED" | grep -iE 'some|mix|partial|whichever|each')"
check "step 3 has a sentence about only some of the three keys being set" \
  "$(nonempty "$MIX")" "yes"
check "that sentence discloses the mix as it stands (set vs default)" \
  "$(has_re 'set|default|as-is|as it is' "$MIX")" "yes"

# --- 10h. Edge case: the 0.9.0 note whenever DAY_START is already set ------

NOTE="$(flat "$(awk 'BEGIN { RS = "" } /0\.9\.0/ { print; print "" }' <<<"$SCHED")")"
check "step 3 carries a 0.9.0 note" \
  "$(nonempty "$NOTE")" "yes"
check "the 0.9.0 note is about CLAM_STATUSLINE_DAY_START" \
  "$(has_cs 'CLAM_STATUSLINE_DAY_START' "$NOTE")" "yes"
check "the 0.9.0 note fires when that key is already set" \
  "$(has_re 'already set|is set|was set|has a value' "$NOTE")" "yes"
check "the note says the knob kept its name" \
  "$(has_re 'same name|kept its name|keeps its name|name .{0,20}unchanged' "$NOTE")" "yes"
check "the note says the meaning changed" \
  "$(has_re 'mean' "$NOTE")" "yes"
check "the note names the old meaning (the pacing-day flip hour)" \
  "$(has_re 'flip|pacing.day|day .{0,12}flip|rollover' "$NOTE")" "yes"
check "the note names the new meaning (the working-day start hour)" \
  "$(has_re 'working.day start|start of (the |your )?working day|hour .{0,20}day (starts|begins)' "$NOTE")" "yes"
check "the note names the default change from 2 to 8" \
  "$(has_re '2 (->|to|→|-->) .{0,3}8|from .{0,3}2.{0,3} to .{0,3}8|default[^.]{0,40}2[^0-9][^.]{0,24}8' "$NOTE")" "yes"
check "the note discloses the current value as it stands under the new meaning" \
  "$(has_re 'current value|as-is|as it is|value you have|existing value' "$NOTE")" "yes"
check "the note leaves the decision to the user" \
  "$(has_re 'you decide|user decide|up to you|your call|decide|choose' "$NOTE")" "yes"

# --- 10i. Remove: one del() pass, the three env keys, other env keys kept ---

check "remove names CLAM_STATUSLINE_WORK_DAYS" \
  "$(has_cs 'CLAM_STATUSLINE_WORK_DAYS' "$REMOVE")" "yes"
check "remove names CLAM_STATUSLINE_DAY_START" \
  "$(has_cs 'CLAM_STATUSLINE_DAY_START' "$REMOVE")" "yes"
check "remove names CLAM_STATUSLINE_DAY_END" \
  "$(has_cs 'CLAM_STATUSLINE_DAY_END' "$REMOVE")" "yes"

# ONE del() pass: the section shows exactly one del(...), and all six keys are
# inside that one call -- a second del() would be a second pass.
check "the remove section shows exactly one del() call" \
  "$(grep -oE 'del\(' <<<"$REMOVE_FLAT" | grep -c 'del' | tr -d ' ')" "1"
DELPASS="$(grep -oE 'del\([^)]*\)' <<<"$REMOVE_FLAT" | head -1)"
check "that del() call was extracted non-empty" \
  "$(nonempty "$DELPASS")" "yes"
check "the one del() drops statusLine" \
  "$(has_cs '\.statusLine' "$DELPASS")" "yes"
check "the one del() drops subagentStatusLine" \
  "$(has_cs '\.subagentStatusLine' "$DELPASS")" "yes"
check "the one del() drops refreshInterval" \
  "$(has_cs '\.refreshInterval' "$DELPASS")" "yes"
check "the one del() drops .env.CLAM_STATUSLINE_WORK_DAYS" \
  "$(has_cs '\.env\.CLAM_STATUSLINE_WORK_DAYS' "$DELPASS")" "yes"
check "the one del() drops .env.CLAM_STATUSLINE_DAY_START" \
  "$(has_cs '\.env\.CLAM_STATUSLINE_DAY_START' "$DELPASS")" "yes"
check "the one del() drops .env.CLAM_STATUSLINE_DAY_END" \
  "$(has_cs '\.env\.CLAM_STATUSLINE_DAY_END' "$DELPASS")" "yes"

ENV_KEPT="$(sentences "$REMOVE" | grep -iE 'env')"
check "the remove section has prose about the env block" \
  "$(nonempty "$ENV_KEPT")" "yes"
check "remove preserves every other env key" \
  "$(has_re 'other env|every other|rest of|any other|remaining' "$ENV_KEPT")" "yes"

NOOP="$(sentences "$REMOVE" | grep -iE 'env|schedule' | grep -iE 'absent|missing|no env|not (present|there|set)|none')"
check "remove has a sentence about an absent env block or absent schedule key" \
  "$(nonempty "$NOOP")" "yes"
check "that absent case is a no-op, not an error" \
  "$(has_re 'nothing to do|not an error|already fine|no-?op|harmless|skip' "$NOOP")" "yes"

EMPTYENV="$(sentences "$REMOVE" | grep -iE 'empt')"
check "remove has a sentence about the env block being left empty" \
  "$(nonempty "$EMPTYENV")" "yes"
check "that sentence is about the env block" \
  "$(has_re 'env' "$EMPTYENV")" "yes"
check "an emptied env block is dropped rather than left behind" \
  "$(has_re 'drop|delete|remove|discard' "$EMPTYENV")" "yes"

ONLY_S="$(sentences "$REMOVE" | grep -iE 'CLAM_STATUSLINE|schedule' | grep -iE '(^| )only( |,)')"
check "remove has a sentence qualifying when it reports the schedule keys" \
  "$(nonempty "$ONLY_S")" "yes"
check "it says they were removed only when they were present" \
  "$(has_re 'present|there|were set|was set|had been set' "$ONLY_S")" "yes"

exit $FAILED
