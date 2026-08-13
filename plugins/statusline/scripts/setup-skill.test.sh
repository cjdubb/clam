#!/bin/bash
# Test for Block B11 (setup-wiring), plan 001-statusline-glance-uplift.
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

BODY="$(cat "$SKILL_MD" 2>/dev/null)"

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
STEP3="$(step 3)"

check "setup step 1 (resolve the plugin root) is present and non-empty" \
  "$(nonempty "$STEP1")" "yes"
check "setup step 2 (show the change before making it) is present and non-empty" \
  "$(nonempty "$STEP2")" "yes"
check "setup step 3 (merge, don't overwrite) is present and non-empty" \
  "$(nonempty "$STEP3")" "yes"

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
# 3. Step 3: ONE jq merges all three keys, preserving every other setting
# ---------------------------------------------------------------------------

N_BASH="$(fences "$STEP3" bash "$TMP/s3f")"
check "step 3 contains a bash fence (the write command)" \
  "$([ "${N_BASH:-0}" -ge 1 ] && echo yes || echo no)" "yes"
S3CMD="$(cat "$TMP"/s3f* 2>/dev/null)"
check "step 3's bash fence is non-empty" "$(nonempty "$S3CMD")" "yes"

check "step 3 invokes jq exactly once" \
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
check "step 3 states that every other setting is preserved" \
  "$(has_re 'preserv' "$STEP3")" "yes"

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

exit $FAILED
