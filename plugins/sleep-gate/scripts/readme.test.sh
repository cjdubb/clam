#!/bin/bash
# Contract tests for B04 plugin README (plan 001-sleep-gate).
#
# Source of truth: the HTML-comment docblock "Contract: B04 plugin README"
# in plugins/sleep-gate/README.md. This file covers the plugin-specific
# CONTENT claims that contract makes, section by section.
#
# NOT covered here, deliberately: the six required H2 headings, their exact
# names, their order, and the confinement of extra H2s to the window between
# "## Commands" and "## Relationships to other plugins". scripts/readme-lint.sh
# already gates all of that repo-wide, and duplicating it here would mean two
# places to edit when the template moves.
#
# COMMENT AND FENCE STRIPPING. The contract docblock sits in the very file
# under test and quotes most of the strings these checks look for
# ("run_in_background", "PreToolUse", "fail open", the carve-out words), so a
# naive grep would find them in the contract and pass before a word of real
# prose exists. Every content check therefore runs against $BODY — the README
# with its own HTML comments stripped — the technique scripts/readme-lint.sh
# uses for the same reason. Checks about PROSE additionally run against
# $PROSE, which is $BODY with fenced code blocks removed, so a claim the
# contract requires the prose to STATE cannot be satisfied by an example
# command that merely contains the word. Checks about EXAMPLES read the
# fenced content on purpose. The "the contract comment is gone" check reads
# the raw file, also on purpose.
#
# THE OTHER-PLUGIN CHECK IS FORM-BASED, and the plugin vocabulary is derived
# from plugins/ at runtime rather than hardcoded, so adding a plugin to the
# repo needs no edit here. It looks for the same four reference forms
# ARCHITECTURE.md and scripts/architecture-lint.sh define — skill invocation
# `/<q>:<token>`, marketplace id `<q>@clam`, English `<q> plugin`, and path
# `plugins/<q>/` — and never for a bare plugin name in prose. That narrowing
# is required, not a convenience: this marketplace holds plugins named
# `build`, `settings`, `tracking`, `landing`, `voice`, `management`,
# `notifications` and `debugging`, every one of which is an ordinary English
# word a correct sleep-gate README may legitimately use (the gate's own
# denial reason talks about notifications, and a worked example may name a
# build log). A bare-name check would fail correct prose; the four forms
# cannot collide with ordinary usage.
#
# Assertions are on SUBSTANCE, not on exact wording: each claim is matched
# against a small set of reasonable phrasings, because the prose is the
# implementer's to write.
#
# Hermetic: reads only this repo's own files, writes only under a mktemp
# scratch dir, no network, cwd-independent (paths resolved from
# ${BASH_SOURCE[0]}).
#
# Run: bash plugins/sleep-gate/scripts/readme.test.sh (non-zero exit on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
PLUGIN_README="$PLUGIN_DIR/README.md"
PLUGIN_NAME="$(basename "$PLUGIN_DIR")"

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
has_fixed() { grep -qF  "$1" <<<"$2" && echo yes || echo no; }   # literal substring
one_line()  { tr '\n' ' ' <<<"$1" | sed -e 's/  *$//'; }         # readable FAIL messages

# strip_fences(text): TEXT with every ``` / ~~~ fenced block (fence lines
# included) removed. The contract's edge case names this as the technique
# this file must use; section 12 tests the helper itself.
strip_fences() {
  awk '
    /^[[:space:]]*(```|~~~)/ { infence = !infence; next }
    !infence { print }
  ' <<<"$1"
}

# fences_of(text): only the CONTENTS of the fenced blocks in TEXT.
fences_of() {
  awk '
    /^[[:space:]]*(```|~~~)/ { infence = !infence; next }
    infence { print }
  ' <<<"$1"
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "plugins/sleep-gate/README.md exists" \
  "$([ -f "$PLUGIN_README" ] && echo yes || echo no)" "yes"
check "the plugin directory is named sleep-gate (self/other derivation)" \
  "$PLUGIN_NAME" "sleep-gate"
check "plugins/ directory is readable (other-plugin vocabulary oracle)" \
  "$([ -d "$REPO_ROOT/plugins" ] && echo yes || echo no)" "yes"

RAW="$(cat "$PLUGIN_README" 2>/dev/null)"
BODY="$(sed '/<!--/,/-->/d' "$PLUGIN_README" 2>/dev/null)"
PROSE="$(strip_fences "$BODY")"

section() {   # $1 = exact "## Heading" line; reads $BODY (fences kept)
  awk -v heading="$1" '
    $0 == heading { flag=1; next }
    flag && /^## / { exit }
    flag { print }
  ' <<<"$BODY"
}

GETTING="$(section '## Getting started')"
EXPECT="$(section '## What to expect')"
WORKFLOWS="$(section '## Common workflows')"
COMMANDS="$(section '## Commands')"
TESTS="$(section '## Tests')"
UPDATE="$(section '## Update')"
RELATIONSHIPS="$(section '## Relationships to other plugins')"
UNINSTALL="$(section '## Uninstalling')"

EXPECT_PROSE="$(strip_fences "$EXPECT")"
EXPECT_FENCE="$(fences_of "$EXPECT")"
WORKFLOWS_PROSE="$(strip_fences "$WORKFLOWS")"
COMMANDS_PROSE="$(strip_fences "$COMMANDS")"
RELATIONSHIPS_PROSE="$(strip_fences "$RELATIONSHIPS")"
UNINSTALL_PROSE="$(strip_fences "$UNINSTALL")"

# ---------------------------------------------------------------------------
# 1. Acceptance hygiene: the contract comment is gone, nothing is a placeholder
# ---------------------------------------------------------------------------

# Raw file on purpose: this is the one check the stripping would defeat.
check "the B04 contract comment marker is gone from the raw README" \
  "$(grep -qF 'Contract: B04' "$PLUGIN_README" && echo present || echo absent)" "absent"
check "no '<!-- Contract:' block survives in the raw README" \
  "$(grep -qF '<!-- Contract:' "$PLUGIN_README" && echo present || echo absent)" "absent"
# Every other shipped plugin README in this repo carries zero HTML comments;
# the template's guidance comments are instructions to the author, not text to
# copy through.
check "no HTML comment of any kind survives in the raw README" \
  "$(grep -qF '<!--' "$PLUGIN_README" && echo present || echo absent)" "absent"

check "no TODO/NotImplemented/TBD/FIXME/placeholder text anywhere in the README" \
  "$(one_line "$(grep -inE 'TODO|NotImplemented|\bTBD\b|FIXME|\bXXX\b|placeholder|coming soon|\{plugin-name\}' <<<"$BODY" | head -2)")" ""

# ---------------------------------------------------------------------------
# 2. Every heading carries real prose, and the file opens with a blurb
# ---------------------------------------------------------------------------

# first_paragraph: the opening blurb between the H1 and the first H2.
BLURB="$(awk '
  /^# / { seen = 1; next }
  !seen { next }
  /^## / { exit }
  { print }
' <<<"$PROSE" | tr -d '[:space:]')"
check "the README opens with a one-paragraph blurb before the first H2" \
  "$([ "${#BLURB}" -ge 40 ] && echo yes || echo no)" "yes"

# Derived rather than listed: whatever H2s the README ships (readme-lint
# gates WHICH ones ship), each must have real prose under it.
while IFS= read -r h; do
  [ -n "$h" ] || continue
  body_chars="$(section "$h" | tr -d '[:space:]')"
  check "section '$h' has real prose under it (not an empty heading)" \
    "$([ "${#body_chars}" -ge 40 ] && echo yes || echo no)" "yes"
done < <(grep -E '^## ' <<<"$PROSE")

# ---------------------------------------------------------------------------
# 3. Getting started: install commands, and no configuration step
# ---------------------------------------------------------------------------

check "'Getting started' gives the marketplace add command" \
  "$(has_fixed '/plugin marketplace add cjdubb/clam' "$GETTING")" "yes"
check "'Getting started' gives the install command for this plugin" \
  "$(has_fixed "/plugin install $PLUGIN_NAME@clam" "$GETTING")" "yes"
check "'Getting started' states that no configuration is required" \
  "$(has_re 'no configuration( is)? (required|needed)|nothing to configure|no config(uration)? step|requires no configuration' \
     "$(strip_fences "$GETTING")")" "yes"
check "'Getting started' states the plugin is hooks-only and active on install" \
  "$(has_re 'hooks.only|only a hook|active (from|on) install|activ(e|ates|ated) (on|as soon as|the moment)|takes effect (on|as soon as|immediately)|starts (working|gating|firing) (on|as soon as|immediately)' \
     "$(strip_fences "$GETTING")")" "yes"

# ---------------------------------------------------------------------------
# 4. What to expect: the hook, both rules, the 2s floor, the carve-out words
# ---------------------------------------------------------------------------

check "'What to expect' names the PreToolUse hook" \
  "$(has_fixed 'PreToolUse' "$EXPECT_PROSE")" "yes"
check "'What to expect' says the hook fires on every Bash tool call" \
  "$(has_re 'every Bash|each Bash|all Bash|every .{0,20}Bash tool call' "$EXPECT_PROSE")" "yes"
check "'What to expect' says subagent tool calls are gated too" \
  "$(has_re 'subagent|sub-agent' "$EXPECT_PROSE")" "yes"

# Rule L, in substance: a LEADING bare sleep, denied at a floor of 2 seconds.
check "'What to expect' states the leading-sleep rule (first statement is a bare sleep)" \
  "$(has_re '(first statement|leading|starts with|begins with|opens with|first thing)' "$EXPECT_PROSE")" "yes"
check "'What to expect' names the 2-second floor as a number" \
  "$(has_re '(^|[^0-9.])2([[:space:]]|-)*(s\b|sec|second)|two[[:space:]-]*second' "$EXPECT_PROSE")" "yes"
check "'What to expect' gives a worked example of a denied leading sleep (>= 2s)" \
  "$(has_re '(^|[^a-z])sleep[[:space:]]+([2-9]|[0-9]{2,})' "$EXPECT")" "yes"

# Rule B, in substance: a background launch, then a sleep.
check "'What to expect' states the background-then-sleep rule" \
  "$(has_re 'background' "$EXPECT_PROSE")" "yes"
check "'What to expect' ties the background launch to a following sleep" \
  "$(has_re 'background.*sleep|sleep.*background' "$(one_line "$EXPECT_PROSE")")" "yes"
check "'What to expect' gives a worked example of a denied background-then-sleep" \
  "$(grep -qE '&' <<<"$(grep -E 'sleep' <<<"$EXPECT")" && echo yes || echo no)" "yes"

# The six carve-out words an engineer hitting an unexpected denial has to be
# able to read off this section. Matched as backticked shell words, or as
# whole words inside a fenced example — never as bare English, because `for`
# and `wait` are ordinary words this section will use anyway.
for kw in while until for break wait trap; do
  in_ticks="$(has_fixed "\`$kw\`" "$EXPECT")"
  in_fence="$(has_re "(^|[^A-Za-z0-9_-])$kw([^A-Za-z0-9_-]|$)" "$EXPECT_FENCE")"
  listed=no
  if [ "$in_ticks" = yes ] || [ "$in_fence" = yes ]; then listed=yes; fi
  check "'What to expect' lists the Rule B carve-out word '$kw'" "$listed" "yes"
done

check "'What to expect' states that no files are created or read and no settings written" \
  "$(has_re 'no files? (are|is)? ?(created|read|written)|(creates?|reads?|writes?|touch(es)?) no (files?|settings?)|never (creates|reads|writes|touches) (a |any )?(file|setting)|writes no settings|no settings are written' \
     "$EXPECT_PROSE")" "yes"

# ---------------------------------------------------------------------------
# 5. What the gate deliberately ALLOWS (the shapes that pass untouched)
# ---------------------------------------------------------------------------

check "the README states that poll loops pass untouched" \
  "$(has_re 'poll(ing)? loop|until .*done|while .*done|condition loop' "$PROSE")" "yes"
check "the README states that kill/SIGTERM grace periods pass untouched" \
  "$(has_re 'grace period|kill.grace|SIGTERM|SIGKILL' "$PROSE")" "yes"
check "the README states that clock- or mtime-granularity waits pass untouched" \
  "$(has_re 'mtime|clock|granularity|timestamp' "$PROSE")" "yes"
check "the README states that sleep used as a test double passes untouched" \
  "$(has_re 'test double|stand.in|fixture|stub(bing)? a slow|simulat(e|ing) a slow|fake (a )?slow|in a test' "$PROSE")" "yes"

# ---------------------------------------------------------------------------
# 6. Common workflows: all four alternatives, each with an example
# ---------------------------------------------------------------------------

check "'Common workflows' offers alternative 1: foreground, bounded by the Bash tool's timeout" \
  "$(has_re 'foreground' "$WORKFLOWS_PROSE")" "yes"
check "'Common workflows' names the Bash tool's timeout parameter for alternative 1" \
  "$(has_re 'timeout' "$WORKFLOWS")" "yes"
check "'Common workflows' offers alternative 2: run_in_background: true" \
  "$(has_fixed 'run_in_background' "$WORKFLOWS")" "yes"
check "'Common workflows' explains the completion notification for alternative 2" \
  "$(has_re 'notif|re.invoke|tells you when|when it (exits|finishes|completes)|on exit' "$WORKFLOWS_PROSE")" "yes"
check "'Common workflows' offers alternative 3: waiting on a child pid" \
  "$(has_re 'wait[[:space:]]+"?\$\{?pid|wait[[:space:]]+"?\$!|\bwait\b.*\bpid\b|\bpid\b.*\bwait\b' \
     "$(one_line "$WORKFLOWS")")" "yes"
check "'Common workflows' offers alternative 4: polling the real condition" \
  "$(has_re 'poll' "$WORKFLOWS_PROSE")" "yes"
check "'Common workflows' gives a condition-poll example" \
  "$(has_re 'until |while |kill -0' "$WORKFLOWS")" "yes"

# "How to get the sleep back": uninstalling is the only opt-out. Both halves
# are asserted, because "uninstall to remove it" alone leaves a reader hunting
# for the env var that does not exist.
check "'Common workflows' says uninstalling is how to get the unrestricted sleep back" \
  "$(has_re 'uninstall' "$WORKFLOWS_PROSE")" "yes"
check "the README states there is no configuration surface and no environment escape hatch" \
  "$(has_re 'no configuration surface|no (env|environment)[- ]?(var(iable)?s?)? ?(escape|opt.out|override)|no escape hatch|nothing to configure|no way to (disable|turn (it )?off) (short of|other than|but)|cannot be (disabled|turned off|configured)' \
     "$PROSE")" "yes"
# Deliberately spans a sentence boundary (`.{0,160}` rather than `[^.]{0,160}`):
# the natural way to write this claim is two sentences — "Uninstall the plugin.
# That is the only opt-out." — and a same-sentence window would fail correct
# prose. Both orders are accepted, and the "only" side must carry opt-out
# vocabulary so a stray "only" elsewhere cannot satisfy it.
check "the README states that uninstalling is the only opt-out" \
  "$(has_re 'uninstall[a-z]*.{0,160}(only (way|opt.?out|escape|thing)|is the only)|(only (way|opt.?out|escape|thing)|is the only).{0,160}uninstall' \
     "$(one_line "$PROSE")")" "yes"

# ---------------------------------------------------------------------------
# 7. Commands: the one hook, and its fail-open behaviour
# ---------------------------------------------------------------------------

check "'Commands' documents the sleep-gate.sh hook script" \
  "$(has_fixed 'sleep-gate.sh' "$COMMANDS")" "yes"
check "'Commands' names the PreToolUse event" \
  "$(has_fixed 'PreToolUse' "$COMMANDS")" "yes"
check "'Commands' names the Bash matcher" \
  "$(has_re 'matcher[^.]*Bash|Bash[^.]*matcher' "$(one_line "$COMMANDS")")" "yes"
check "'Commands' says what the hook reads (the hook JSON on stdin)" \
  "$(has_re 'stdin|hook (json|payload)|tool_input' "$COMMANDS")" "yes"
check "'Commands' says what the hook writes (a deny decision, or nothing)" \
  "$(has_re 'stdout|deny|permissionDecision|writes nothing|prints nothing' "$COMMANDS")" "yes"
check "'Commands' states the hook always exits 0" \
  "$(has_re 'always exits? (with )?(0|zero)|exits? (0|zero) (always|every time|on every path)|never exits? non.?zero' \
     "$(one_line "$COMMANDS_PROSE")")" "yes"
check "'Commands' states that every failure path allows the call" \
  "$(has_re 'every failure|any failure|all failure|failure.{0,40}allow|allow.{0,40}failure|when in doubt.{0,20}allow' \
     "$(one_line "$COMMANDS_PROSE")")" "yes"

# ---------------------------------------------------------------------------
# 8. The fail-open posture, stated explicitly rather than implied
# ---------------------------------------------------------------------------

check "the README states the fail-open posture explicitly" \
  "$(has_re 'fail(s|ing)?[- ]open' "$PROSE")" "yes"
check "the README states that a parse failure allows the call" \
  "$(has_re '(parse|unparse|malformed|unreadable|missing jq|absent jq|cannot read|can.t read)[^.]{0,80}(allow|pass|let)|(allow|pass)[^.]{0,80}(parse|unparse|malformed)' \
     "$(one_line "$PROSE")")" "yes"
check "the README states the gate never blocks a session by crashing" \
  "$(has_re 'never (block|wedge|break|stop)[^.]{0,60}(crash|fail|error|session)|cannot (block|wedge|break)[^.]{0,60}session|(crash|error)[^.]{0,60}(never|cannot) (block|deny)' \
     "$(one_line "$PROSE")")" "yes"

# ---------------------------------------------------------------------------
# 9. Tests and Update sections
# ---------------------------------------------------------------------------

check "'Tests' gives a bash invocation under this plugin's scripts directory" \
  "$(has_fixed "bash plugins/$PLUGIN_NAME/scripts/" "$TESTS")" "yes"
# Derived from disk: every suite this plugin actually ships must be listed.
for t in "$SCRIPT_DIR"/*.test.sh; do
  [ -f "$t" ] || continue
  check "'Tests' lists the $(basename "$t") suite" \
    "$(has_fixed "$(basename "$t")" "$TESTS")" "yes"
done

check "'Update' gives the marketplace update command" \
  "$(has_fixed '/plugin marketplace update clam' "$UPDATE")" "yes"
check "'Update' gives the plugin update command for this plugin" \
  "$(has_fixed "claude plugin update $PLUGIN_NAME@clam" "$UPDATE")" "yes"

# ---------------------------------------------------------------------------
# 10. Relationships and Uninstalling
# ---------------------------------------------------------------------------

check "'Relationships to other plugins' states the plugin is fully standalone" \
  "$(has_re 'standalone|none required|no other plugin|nothing else (is )?(required|needed)' "$RELATIONSHIPS_PROSE")" "yes"

check "'Uninstalling' gives the uninstall command for this plugin" \
  "$(has_fixed "/plugin uninstall $PLUGIN_NAME@clam" "$UNINSTALL")" "yes"
check "'Uninstalling' states that nothing is left behind" \
  "$(has_re 'nothing (is )?left behind|leaves nothing|no (files|state|settings)[^.]{0,40}(left|behind|remain)|nothing (else )?to (clean|remove|revert)|that is all|removes everything' \
     "$(one_line "$UNINSTALL_PROSE")")" "yes"

# ---------------------------------------------------------------------------
# 11. Invariant: the README names NO other plugin, in any of the four forms
# ---------------------------------------------------------------------------

# Vocabulary derived from the tree, so a new plugin is covered without an edit.
find "$REPO_ROOT/plugins" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
  | sed 's|.*/||' | grep -v "^$PLUGIN_NAME\$" | sort > "$TMP/others"

check "other-plugin vocabulary derived from plugins/ is non-empty (oracle guard)" \
  "$([ -s "$TMP/others" ] && echo yes || echo no)" "yes"

# The raw file, not $BODY: the invariant covers comments too.
hits=""
while IFS= read -r q; do
  [ -n "$q" ] || continue
  qe="$(sed 's/[][\.*^$/+?(){}|]/\\&/g' <<<"$q")"
  if grep -qE "/$qe:[A-Za-z0-9_-]" <<<"$RAW"; then hits="$hits skill-invocation:$q"; fi
  if grep -qF "$q@clam" <<<"$RAW"; then hits="$hits marketplace-id:$q"; fi
  if grep -qiE "(^|[^A-Za-z0-9_-])$qe plugin" <<<"$RAW"; then hits="$hits english:$q"; fi
  if grep -qF "plugins/$q/" <<<"$RAW"; then hits="$hits path:$q"; fi
done < "$TMP/others"

check "the README names no other plugin (skill invocation, marketplace id, English, or path)" \
  "$(one_line "$hits")" ""

# ---------------------------------------------------------------------------
# 12. The stripping helpers themselves (contract edge case)
# ---------------------------------------------------------------------------

# The contract's edge case says this suite must strip fenced code blocks
# before asserting on prose, precisely so a `sleep` example cannot satisfy a
# claim the prose is required to make. A helper that silently stopped
# stripping would turn many checks above green for the wrong reason, so the
# helper is tested against a fixture of its own.
cat > "$TMP/fixture.md" <<'FIXTURE'
prose before

```bash
sleep 45 && echo fenced
```

prose after
FIXTURE
FIXTURE_TEXT="$(cat "$TMP/fixture.md")"

check "strip_fences removes fenced content" \
  "$(has_fixed 'fenced' "$(strip_fences "$FIXTURE_TEXT")")" "no"
check "strip_fences keeps prose before the fence" \
  "$(has_fixed 'prose before' "$(strip_fences "$FIXTURE_TEXT")")" "yes"
check "strip_fences keeps prose after the fence" \
  "$(has_fixed 'prose after' "$(strip_fences "$FIXTURE_TEXT")")" "yes"
check "fences_of returns the fenced content" \
  "$(has_fixed 'fenced' "$(fences_of "$FIXTURE_TEXT")")" "yes"
check "fences_of drops the surrounding prose" \
  "$(has_fixed 'prose before' "$(fences_of "$FIXTURE_TEXT")")" "no"

# Non-vacuity for the comment strip: $BODY must be shorter than the raw file
# only while a comment exists, so what is asserted instead is that the
# stripper works on a fixture — the README's own comment is required absent
# by section 1.
cat > "$TMP/comment.md" <<'CFIXTURE'
kept line
<!-- hidden
still hidden -->
kept tail
CFIXTURE
check "HTML-comment stripping removes multi-line comments" \
  "$(has_fixed 'hidden' "$(sed '/<!--/,/-->/d' "$TMP/comment.md")")" "no"
check "HTML-comment stripping keeps surrounding lines" \
  "$(has_fixed 'kept tail' "$(sed '/<!--/,/-->/d' "$TMP/comment.md")")" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
