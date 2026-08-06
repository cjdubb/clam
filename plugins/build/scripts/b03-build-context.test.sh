#!/bin/bash
# Functional test for build-context.sh: SessionStart injection of delivery
# framework context, adapting to which companion plugins (landing, lego,
# tracking) are PRESENT FOR THE PAYLOAD'S cwd.
#
# Contract: B01 companion-detection (plan 001-issues-317-318, issue #317),
# as revised by decision 002 (engineer, 2026-08-06) — TWO signals, plugin
# CLI then config files, and the repository's own file tree is not a signal
# at all. The contract docblock at the top of build-context.sh is the source
# of truth; every case below names the clause it exercises.
#
# The defect under repair is a hook that read presence off
# `[ -d "$cwd/plugins/<name>" ]`, so this suite's centre of gravity is the
# pair of claims that replaced it: presence is a property of the session
# (cases 1-15), and a `plugins/<name>/` directory changes nothing, whatever
# the other signals say (cases 6, 9, 14, 15, 16).
#
# Covers:
#   0.  Harness self-checks (the hermeticity guarantees the rest rely on)
#   1.  Signal 1 resolves all three; exactly ONE CLI invocation; the CLI is
#       run with the payload's cwd as its working directory; `projectPath`
#       pointing elsewhere does not make a plugin absent
#   2.  Signal 1 is marketplace-agnostic (landing@someothermarket counts)
#       and per-companion independent
#   3.  Installed but not enabled here -> absent; negative-branch wording
#   4.  Several rows for one plugin, only one enabled -> present
#   5.  Enabled in settings but installed nowhere -> absent
#   6.  ORDERING 1 > 2, and the file tree is not consulted: the CLI says
#       enabled:false while the config files say present and a
#       plugins/landing/ directory exists -> absent
#   7.  ORDERING 1 -> 2: `claude` not on PATH, config files decide
#   8.  Signal 1 non-zero exit demotes only that signal; still at most one
#       CLI invocation
#   9.  Signal 1 output that is not a JSON array demotes only that signal
#   10. Settings precedence: a later file's explicit false overrides an
#       earlier true -> absent
#   11. Settings precedence: a later file's true overrides an earlier
#       false -> present
#   12. An unparseable settings file contributes nothing rather than
#       disabling
#   13. Signal 2 is marketplace-agnostic
#   14. A signal 2 that resolves negative is an answer, not a fall-through
#   15. Malformed installed_plugins.json: no signal left -> absent, exit 0,
#       well-formed envelope
#   16. NO signal evaluable at all (no `claude`, no installed_plugins.json)
#       with all three companion directories on disk -> absent. This is the
#       case that pins "the file tree is not a signal" on its own, with no
#       other signal's answer to hide behind
#   17. Invariant: detection never sources or executes a companion's own
#       scripts
#   18. Invariant: detection is read-only (writes no file under cwd or the
#       config dir)
#   19. Invariant: the /build:sync-pr standing instruction appears in every
#       branch; no user-visible text says "/deliver"
#   20. Fail-open: no jq, no cwd, malformed payload, nonexistent cwd
#   21. Fail-open when NEITHER CLAUDE_CONFIG_DIR NOR HOME is set — the one
#       environment the other cases cannot reach, because setting HOME is
#       what makes them hermetic
#
# HERMETIC BY CONSTRUCTION. This machine has landing@clam, lego@clam and
# tracking@clam really installed, so a suite that consulted real state would
# pass for reasons that have nothing to do with the code under test. Every
# hook run therefore goes through `env -i` with:
#   - PATH rooted at a temp bin holding a FAKE `claude` executable (or, for
#     the "CLI unavailable" cases, a PATH with every directory containing a
#     real `claude` filtered out);
#   - CLAUDE_CONFIG_DIR pointed at a per-case fixture tree;
#   - HOME pointed at an empty temp dir, so a `$HOME/.claude` fallback
#     cannot reach the developer's real settings either.
# Case 21 is the deliberate exception: it omits both variables, which is the
# only way to exercise the unset-HOME path. It stays hermetic because with
# HOME unset there is no `$HOME/.claude` for the hook to find in the first
# place, and `claude` is off its PATH.
# The fake `claude` records each invocation (count + working directory) to
# files outside the fixture trees, which is what makes both the
# at-most-one-invocation clause and the "run with cwd as its working
# directory" clause testable at all. Case 0 asserts these guarantees hold
# before anything depends on them.
#
# The no-jq case resolves `bash` to an absolute path FIRST: a bare
# `PATH= bash` applies the empty PATH to the bash lookup itself and fails
# with 127 before the hook ever runs. That technique is load-bearing and is
# kept from the previous revision of this suite.
#
# RED/GREEN at birth (against the B01 stub, which reports every companion
# absent regardless of input):
#   RED — every assertion that expects a companion marker to appear
#     (cases 1, 2, 4, 7, 8, 9, 11, 12, 13, 17's first check), every
#     CLI-invocation-count assertion expecting 1 (cases 1, 2, 8: the stub
#     never runs the CLI, so the counter is 0), and the CLI working-
#     directory assertion in case 1 (no invocation, so no logged cwd).
#     These are the assertions that drive the implementation.
#   GREEN for reasons unrelated to detection — the stub already emits a
#     well-formed envelope and already carries the rewritten negative
#     branch, so: the valid-JSON and hookEventName checks (case 1), every
#     assertion that expects a marker to be ABSENT (cases 2, 3, 5, 6, 9,
#     10, 14, 15, 16 — the stub says absent unconditionally, so these pass
#     today without detection existing), the negative-branch wording checks
#     (cases 3, 16), the standing-instruction and no-"/deliver" checks
#     (case 19), the never-sourced marker check (case 17), the read-only
#     invariant (case 18), and all four fail-open cases (case 20). They are
#     asserted anyway: they are contract invariants that must survive the
#     implementation, and several of them are exactly what a wrong
#     implementation would break first.
#   Note what this means for the file-tree cases in particular. Cases 6, 14
#     and 16 are GREEN at birth and stay GREEN through a correct
#     implementation — they are the ones a REGRESSION to directory-based
#     detection turns red, which is precisely their job. They only bite in
#     combination with the RED presence checks: until case 1 proves the
#     hook can say "present" at all, "absent" here is right for the wrong
#     reason. That is stated here rather than worked around; the pairing is
#     what encodes the rule.
#
# Case 21 has a different birthday and is called out separately for that
# reason: it was added AFTER the implementation landed (c13318b), against
# which cases 0-20 are green. All three of its assertions are RED against
# that implementation — `config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`
# under `set -u` aborts with "HOME: unbound variable", so the hook exits 1,
# writes a diagnostic to stderr, and emits no envelope. It is a defect
# report in test form, not a regression guard.
#
# NOT TESTED, deliberately: the contract's `timeout 5` bound on the CLI.
# Exercising it needs a CLI that hangs and a wall-clock assertion, i.e. a
# multi-second sleep in a suite that must stay fast. Flagged rather than
# faked.
#
# Tests the public artifact only — the hook's stdout JSON and its exit
# status, plus externally observable process effects (whether the CLI ran,
# how many times, where, and whether any file was written). No assertion
# references an internal function name or implementation structure.
#
# Run: bash plugins/build/scripts/b03-build-context.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/build-context.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

BASH_BIN=$(command -v bash)          # absolute, resolved before any PATH games
FAKEHOME="$TMPROOT/home"; mkdir -p "$FAKEHOME"
SHIMBIN="$TMPROOT/bin"; mkdir -p "$SHIMBIN"
FAKE_OUT="$TMPROOT/claude-stdout"
COUNTER="$TMPROOT/claude-calls"
PWDLOG="$TMPROOT/claude-cwds"
: > "$FAKE_OUT"; : > "$COUNTER"; : > "$PWDLOG"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# Fake `claude` CLI. Uses only bash builtins, so it works under a PATH that
# has been stripped down to nothing. Records the invocation, then replays a
# canned `plugin list --json` response.
# ---------------------------------------------------------------------------
cat > "$SHIMBIN/claude" <<'SHIM'
#!/bin/bash
printf 'call %s\n' "$*" >> "$FAKE_CLAUDE_COUNTER"
pwd -P >> "$FAKE_CLAUDE_PWDLOG"
[ -s "${FAKE_CLAUDE_OUT:-}" ] && printf '%s\n' "$(<"$FAKE_CLAUDE_OUT")"
exit "${FAKE_CLAUDE_RC:-0}"
SHIM
chmod +x "$SHIMBIN/claude"

# A PATH with every directory that holds a real `claude` removed, for the
# "CLI unavailable" cases. Filtering the directories out is safer than
# hand-building a bin dir: the hook may reach for jq, timeout or any other
# ordinary utility, and those keep working.
NOCLI_PATH=""
IFS=: read -r -a _path_dirs <<< "$PATH"
for _d in "${_path_dirs[@]}"; do
  [[ -n "$_d" ]] || continue
  [[ -x "$_d/claude" ]] && continue
  NOCLI_PATH="${NOCLI_PATH:+$NOCLI_PATH:}$_d"
done

# Per-case knobs, reset by new_case.
CASE_PATH="$SHIMBIN:$PATH"
CASE_CFG="$TMPROOT/empty-cfg"
CASE_WD="$TMPROOT/empty-wd"
FAKE_RC=0

new_case() { # name -> CASE_WD, CASE_CFG under $TMPROOT/<name>/
  CASE_WD="$TMPROOT/$1/wd"
  CASE_CFG="$TMPROOT/$1/cfg"
  mkdir -p "$CASE_WD" "$CASE_CFG"
  CASE_PATH="$SHIMBIN:$PATH"
  FAKE_RC=0
  : > "$FAKE_OUT"; : > "$COUNTER"; : > "$PWDLOG"
}

no_cli() { CASE_PATH="$NOCLI_PATH"; }              # `claude` not on PATH
cli_says() { printf '%s' "$1" > "$FAKE_OUT"; }     # canned plugin-list output
cli_exits() { FAKE_RC="$1"; }                      # non-zero CLI exit

rec() { # id enabled -> one install record, projectPath deliberately elsewhere
  printf '{"id":"%s","version":"1.0.0","scope":"user","enabled":%s,' "$1" "$2"
  printf '"installPath":"/fake/cache/%s","installedAt":"2026-01-01T00:00:00.000Z",' "$1"
  printf '"lastUpdated":"2026-01-01T00:00:00.000Z","projectPath":"/some/other/repo"}'
}
arr() { local IFS=,; printf '[%s]' "$*"; }

installed() { # key... -> installed_plugins.json in CASE_CFG
  mkdir -p "$CASE_CFG/plugins"
  local entries="" k
  for k in "$@"; do
    entries="${entries:+$entries,}\"$k\":[{\"scope\":\"user\",\"version\":\"1.0.0\",\"installPath\":\"/fake/cache/$k\"}]"
  done
  printf '{"plugins":{%s}}' "$entries" > "$CASE_CFG/plugins/installed_plugins.json"
}

settings() { # file key=bool ... -> an enabledPlugins settings file
  local f="$1"; shift
  mkdir -p "$(dirname "$f")"
  local entries="" kv
  for kv in "$@"; do
    entries="${entries:+$entries,}\"${kv%=*}\":${kv#*=}"
  done
  printf '{"enabledPlugins":{%s}}' "$entries" > "$f"
}

payload() { # cwd
  printf '{"session_id":"test","hook_event_name":"SessionStart","cwd":"%s"}' "$1"
}

run_hook() { # payload-json -> hook stdout (exit status preserved)
  printf '%s' "$1" | env -i \
    PATH="$CASE_PATH" HOME="$FAKEHOME" CLAUDE_CONFIG_DIR="$CASE_CFG" \
    FAKE_CLAUDE_OUT="$FAKE_OUT" FAKE_CLAUDE_RC="$FAKE_RC" \
    FAKE_CLAUDE_COUNTER="$COUNTER" FAKE_CLAUDE_PWDLOG="$PWDLOG" \
    "$BASH_BIN" "$HOOK" 2>/dev/null
}

ctx() { # raw hook stdout -> the additionalContext string
  printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

has() { # haystack needle (case-insensitive fixed-string)
  printf '%s' "$1" | grep -qiF -- "$2" && echo yes || echo no
}

calls() { local n; n=$(wc -l < "$COUNTER"); printf '%s' "$((n))"; }

snapshot() { # dir -> stable digest of every file under it
  find "$1" -type f -exec cksum {} \; 2>/dev/null | sort
}

# ---------------------------------------------------------------------------
# 0. Harness self-checks. Everything below assumes the suite cannot see this
#    machine's real plugin installs; assert that before relying on it.
# ---------------------------------------------------------------------------
check "harness: the fake claude shadows any real one on the case PATH" \
  "$(PATH="$SHIMBIN:$PATH" command -v claude)" "$SHIMBIN/claude"
check "harness: the CLI-unavailable PATH resolves no claude" \
  "$(PATH="$NOCLI_PATH" command -v claude >/dev/null 2>&1 && echo found || echo none)" "none"
check "harness: the CLI-unavailable PATH still resolves jq" \
  "$(PATH="$NOCLI_PATH" command -v jq >/dev/null 2>&1 && echo found || echo none)" "found"

# ---------------------------------------------------------------------------
# 1. Signal 1 resolves all three companions. Consumer-repo shape: no
#    plugins/ directory and no config files at all, so only the CLI can
#    answer. Also pins the two clauses that only an out-of-process
#    observation can check: AT MOST ONE invocation per hook run, and the
#    invocation happens with the payload's cwd as its working directory.
#    Every record's projectPath points at an unrelated repo (provenance,
#    never a scope boundary) and must not make the plugin absent.
# ---------------------------------------------------------------------------
new_case all-via-cli
cli_says "$(arr "$(rec landing@clam true)" "$(rec lego@clam true)" "$(rec tracking@clam true)")"
raw=$(run_hook "$(payload "$CASE_WD")")
OUT_ALL=$(ctx "$raw")

check "1 all-via-cli output is valid JSON" \
  "$(printf '%s' "$raw" | jq -e . >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "1 all-via-cli hookEventName is SessionStart" \
  "$(printf '%s' "$raw" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "SessionStart"
check "1 all-via-cli includes the landing merge-policy marker" \
  "$(has "$OUT_ALL" 'merge policy')" "yes"
check "1 all-via-cli includes the landing PR-creation marker" \
  "$(has "$OUT_ALL" 'PR creation')" "yes"
check "1 all-via-cli includes the lego dispatch marker" \
  "$(has "$OUT_ALL" 'dispatch')" "yes"
check "1 all-via-cli includes the tracking state-lifecycle marker" \
  "$(has "$OUT_ALL" 'state lifecycle')" "yes"
check "1 all-via-cli invokes the plugin CLI exactly once for all three" \
  "$(calls)" "1"
check "1 all-via-cli invokes the CLI with the payload cwd as working directory" \
  "$(head -n1 "$PWDLOG")" "$(cd "$CASE_WD" && pwd -P)"

# ---------------------------------------------------------------------------
# 2. Marketplace-agnostic matching (a leading "<name>@", never a hardcoded
#    marketplace) and per-companion independence: landing under a different
#    marketplace is present, lego is present, tracking has no row at all and
#    is absent. Still one CLI invocation.
# ---------------------------------------------------------------------------
new_case other-marketplace
cli_says "$(arr "$(rec landing@someothermarket true)" "$(rec lego@clam true)" "$(rec unrelated@clam true)")"
OUT_PARTIAL=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "2 landing@someothermarket counts as landing present" \
  "$(has "$OUT_PARTIAL" 'merge policy')" "yes"
check "2 lego@clam is present alongside it" \
  "$(has "$OUT_PARTIAL" 'dispatch')" "yes"
check "2 tracking, absent from the listing, is absent" \
  "$(has "$OUT_PARTIAL" 'state lifecycle')" "no"
check "2 mixed resolution still costs exactly one CLI invocation" \
  "$(calls)" "1"

# ---------------------------------------------------------------------------
# 3. Installed on the machine but not enabled for this cwd -> absent (all
#    three rows enabled:false). Pins the negative branch's wording: it
#    describes the marketplace and enabling for the repo, and never tells
#    the user to place plugins under a `plugins/` directory — a layout no
#    consumer repo has, and, since decision 002, one detection does not
#    look at either.
# ---------------------------------------------------------------------------
new_case installed-not-enabled
cli_says "$(arr "$(rec landing@clam false)" "$(rec lego@clam false)" "$(rec tracking@clam false)")"
OUT_NONE=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "3 installed-but-not-enabled landing is absent" \
  "$(has "$OUT_NONE" 'merge policy')" "no"
check "3 installed-but-not-enabled lego is absent" \
  "$(has "$OUT_NONE" 'dispatch')" "no"
check "3 installed-but-not-enabled tracking is absent" \
  "$(has "$OUT_NONE" 'state lifecycle')" "no"
check "3 negative branch is non-empty" \
  "$([[ -n "$OUT_NONE" ]] && echo yes || echo no)" "yes"
check "3 negative branch points at the marketplace" \
  "$(has "$OUT_NONE" 'marketplace')" "yes"
check "3 negative branch mentions enabling them" \
  "$(has "$OUT_NONE" 'enabl')" "yes"
check "3 negative branch never says to install under plugins/" \
  "$(has "$OUT_NONE" 'plugins/')" "no"
check "3 negative branch never mentions a plugins directory" \
  "$(has "$OUT_NONE" 'plugins directory')" "no"

# ---------------------------------------------------------------------------
# 4. One companion listed several times (one row per install record): present
#    if ANY row is enabled, whatever order the rows arrive in.
# ---------------------------------------------------------------------------
new_case several-rows
cli_says "$(arr "$(rec tracking@clam false)" "$(rec tracking@otherplace false)" "$(rec tracking@clam true)")"
out=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "4 several rows, one enabled -> present" \
  "$(has "$out" 'state lifecycle')" "yes"
check "4 several rows do not resurrect the other companions" \
  "$(has "$out" 'merge policy')" "no"

# ---------------------------------------------------------------------------
# 5. Enabled here but installed nowhere -> absent. The CLI resolves (a valid
#    array) and lists no companion; the settings that enable landing are
#    irrelevant because enablement alone is not presence.
# ---------------------------------------------------------------------------
new_case enabled-nowhere-installed
cli_says "$(arr "$(rec unrelated@clam true)")"
settings "$CASE_CFG/settings.json" "landing@clam=true"
out=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "5 enabled in settings but installed nowhere -> absent" \
  "$(has "$out" 'merge policy')" "no"
check "5 that run still produced context (negative branch)" \
  "$([[ -n "$out" ]] && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 6. Signal 1 resolves negative while everything below it says otherwise:
#    the config files record landing installed and enabled, and a
#    plugins/landing/ directory sits in the cwd. Signal 1 decided, so
#    signal 2 is never reached — and the directory is not a signal at any
#    point, so it cannot rescue the answer either.
#    (A real ordering test only together with case 1: until the CLI is
#    consulted at all, "absent" here is right for the wrong reason.)
# ---------------------------------------------------------------------------
new_case cli-decides-negative
mkdir -p "$CASE_WD/plugins/landing"
installed "landing@clam"
settings "$CASE_CFG/settings.json" "landing@clam=true"
cli_says "$(arr "$(rec landing@clam false)")"
out=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "6 CLI enabled:false beats config files saying enabled" \
  "$(has "$out" 'merge policy')" "no"
check "6 a plugins/landing directory does not override the CLI's answer" \
  "$(has "$out" 'PR creation')" "no"

# ---------------------------------------------------------------------------
# 7. Signal 1 unavailable (no `claude` on PATH — a hook launched from an IDE
#    or desktop app with a restricted PATH) -> signal 2 answers.
# ---------------------------------------------------------------------------
new_case no-cli-config-answers
no_cli
installed "landing@clam" "tracking@clam"
settings "$CASE_CFG/settings.json" "landing@clam=true" "tracking@clam=true" "lego@clam=true"
out=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "7 no CLI: config files make landing present" \
  "$(has "$out" 'merge policy')" "yes"
check "7 no CLI: config files make tracking present" \
  "$(has "$out" 'state lifecycle')" "yes"
check "7 no CLI: lego enabled but not installed stays absent" \
  "$(has "$out" 'dispatch')" "no"
check "7 no CLI: the CLI was genuinely never invoked" "$(calls)" "0"

# ---------------------------------------------------------------------------
# 8. Signal 1 present but failing (non-zero exit) demotes that signal only,
#    never the hook — and the at-most-once budget still holds: one failed
#    call is not retried per companion.
# ---------------------------------------------------------------------------
new_case cli-nonzero
cli_exits 1
installed "lego@clam"
settings "$CASE_CFG/settings.json" "lego@clam=true"
raw=$(run_hook "$(payload "$CASE_WD")"); rc=$?
out=$(ctx "$raw")

check "8 CLI non-zero exit: hook still exits 0" "$rc" "0"
check "8 CLI non-zero exit: signal 2 answers, lego present" \
  "$(has "$out" 'dispatch')" "yes"
check "8 CLI non-zero exit: still at most one CLI invocation" "$(calls)" "1"

# ---------------------------------------------------------------------------
# 9. Signal 1 output that is not a JSON array (an error object) does not
#    resolve, so signal 2 answers. A plugins/landing/ directory sits in the
#    cwd throughout and landing is enabled nowhere: it stays absent while
#    tracking, which the config files vouch for, is present.
# ---------------------------------------------------------------------------
new_case cli-garbage
cli_says '{"error":"not an array"}'
mkdir -p "$CASE_WD/plugins/landing"
installed "tracking@clam"
settings "$CASE_CFG/settings.json" "tracking@clam=true"
out=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "9 non-array CLI output demotes signal 1, and signal 2 answers" \
  "$(has "$out" 'state lifecycle')" "yes"
check "9 the plugins/landing directory still does not make landing present" \
  "$(has "$out" 'merge policy')" "no"

# ---------------------------------------------------------------------------
# 10. Signal 2 settings precedence: user settings enable landing, the cwd's
#     settings.local.json explicitly disables it. Later file wins and an
#     explicit false disables -> absent.
# ---------------------------------------------------------------------------
new_case settings-later-false
no_cli
installed "landing@clam"
settings "$CASE_CFG/settings.json" "landing@clam=true"
settings "$CASE_WD/.claude/settings.local.json" "landing@clam=false"
out=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "10 explicit false in a later settings file disables" \
  "$(has "$out" 'merge policy')" "no"

# ---------------------------------------------------------------------------
# 11. The same precedence in the other direction: user settings disable lego,
#     the cwd's settings.json enables it -> present. Proves precedence is
#     resolved by order, not by "any false anywhere wins".
# ---------------------------------------------------------------------------
new_case settings-later-true
no_cli
installed "lego@clam"
settings "$CASE_CFG/settings.json" "lego@clam=false"
settings "$CASE_WD/.claude/settings.json" "lego@clam=true"
out=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "11 a later settings file's true overrides an earlier false" \
  "$(has "$out" 'dispatch')" "yes"

# ---------------------------------------------------------------------------
# 12. An unparseable settings file contributes nothing rather than
#     disabling: tracking stays present on the strength of the earlier file.
# ---------------------------------------------------------------------------
new_case settings-unparseable
no_cli
installed "tracking@clam"
settings "$CASE_CFG/settings.json" "tracking@clam=true"
mkdir -p "$CASE_WD/.claude"
printf '{ this is not json' > "$CASE_WD/.claude/settings.local.json"
raw=$(run_hook "$(payload "$CASE_WD")"); rc=$?
out=$(ctx "$raw")

check "12 unparseable settings file: hook still exits 0" "$rc" "0"
check "12 unparseable settings file contributes nothing, does not disable" \
  "$(has "$out" 'state lifecycle')" "yes"

# ---------------------------------------------------------------------------
# 13. Signal 2 matches on plugin NAME, not marketplace, in both the install
#     record key and the enabledPlugins key.
# ---------------------------------------------------------------------------
new_case settings-other-marketplace
no_cli
installed "landing@someothermarket"
settings "$CASE_CFG/settings.json" "landing@someothermarket=true"
out=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "13 config-file detection is marketplace-agnostic" \
  "$(has "$out" 'merge policy')" "yes"

# ---------------------------------------------------------------------------
# 14. A signal 2 that evaluates to false HAS resolved: a readable
#     installed_plugins.json plus settings that disable landing is an
#     answer, not a fall-through. The plugins/landing/ directory in the cwd
#     is there to prove the answer is not revisited — under decision 002
#     there is nothing left to fall through TO, and the file tree was never
#     eligible to answer in the first place.
# ---------------------------------------------------------------------------
new_case config-resolves-negative
no_cli
mkdir -p "$CASE_WD/plugins/landing"
installed "landing@clam"
settings "$CASE_CFG/settings.json" "landing@clam=false"
out=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "14 a signal 2 that resolves false is an answer, not a fall-through" \
  "$(has "$out" 'merge policy')" "no"

# ---------------------------------------------------------------------------
# 15. A malformed installed_plugins.json means signal 2 could not be
#     evaluated. With no `claude` either, no signal resolves — so every
#     companion is absent and the hook still exits 0 with a well-formed
#     envelope. Unevaluable is exhaustion, not an error, and a
#     plugins/lego/ directory does not fill the gap.
# ---------------------------------------------------------------------------
new_case installed-plugins-malformed
no_cli
mkdir -p "$CASE_CFG/plugins" "$CASE_WD/plugins/lego"
printf 'not json at all' > "$CASE_CFG/plugins/installed_plugins.json"
raw=$(run_hook "$(payload "$CASE_WD")"); rc=$?
out=$(ctx "$raw")

check "15 malformed installed_plugins.json: hook still exits 0" "$rc" "0"
check "15 malformed installed_plugins.json: well-formed envelope" \
  "$(printf '%s' "$raw" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "SessionStart"
check "15 no signal left: lego absent despite plugins/lego/ on disk" \
  "$(has "$out" 'dispatch')" "no"

# ---------------------------------------------------------------------------
# 16. THE file-tree case, standing on its own. A checkout of the plugin repo
#     itself: all three companion source directories present, `claude` not
#     on PATH, no installed_plugins.json at all — so neither signal can even
#     be evaluated, and there is no other signal's answer for the file tree
#     to hide behind. Every companion is absent, and the negative branch's
#     marketplace advice is the accurate thing to say in that state. This is
#     issue #317 with its sign flipped, and the reason the source-directory
#     arm was dropped: claiming "The landing plugin is installed" here would
#     point the reader at skills the session cannot resolve.
#     Settings enable all three, to show that enablement without a readable
#     install record is not presence either.
# ---------------------------------------------------------------------------
new_case file-tree-is-not-a-signal
no_cli
mkdir -p "$CASE_WD/plugins/landing/skills" "$CASE_WD/plugins/lego/skills" \
         "$CASE_WD/plugins/tracking/skills"
settings "$CASE_CFG/settings.json" "landing@clam=true" "lego@clam=true" "tracking@clam=true"
raw=$(run_hook "$(payload "$CASE_WD")"); rc=$?
OUT_NOSIG=$(ctx "$raw")

check "16 no signal evaluable: hook exits 0" "$rc" "0"
check "16 no signal evaluable: well-formed envelope" \
  "$(printf '%s' "$raw" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "SessionStart"
check "16 a plugins/landing directory alone does not make landing present" \
  "$(has "$OUT_NOSIG" 'merge policy')" "no"
check "16 a plugins/lego directory alone does not make lego present" \
  "$(has "$OUT_NOSIG" 'dispatch')" "no"
check "16 a plugins/tracking directory alone does not make tracking present" \
  "$(has "$OUT_NOSIG" 'state lifecycle')" "no"
check "16 the negative branch is emitted, pointing at the marketplace" \
  "$(has "$OUT_NOSIG" 'marketplace')" "yes"

# ---------------------------------------------------------------------------
# 17. Invariant: detection never sources, imports or executes a companion's
#     own scripts. Presence is established through the CLI, while a
#     companion script that would leave a side-effect marker if it ever ran
#     sits in the cwd throughout. The marker must not appear.
# ---------------------------------------------------------------------------
new_case never-sourced
cli_says "$(arr "$(rec landing@clam true)")"
mkdir -p "$CASE_WD/plugins/landing/scripts"
MARKER="$TMPROOT/never-sourced/marker"
cat > "$CASE_WD/plugins/landing/scripts/evil.sh" <<EOF
#!/bin/bash
touch "$MARKER"
EOF
chmod +x "$CASE_WD/plugins/landing/scripts/evil.sh"
out=$(ctx "$(run_hook "$(payload "$CASE_WD")")")

check "17 presence is detected without running the companion's scripts" \
  "$(has "$out" 'merge policy')" "yes"
check "17 no companion script was sourced or executed (no marker)" \
  "$([ -f "$MARKER" ] && echo present || echo absent)" "absent"

# ---------------------------------------------------------------------------
# 18. Invariant: detection is read-only. Nothing under the config dir or the
#     working directory changes across a run that exercises both signals.
# ---------------------------------------------------------------------------
new_case read-only
mkdir -p "$CASE_WD/plugins/lego"
installed "landing@clam" "lego@clam"
settings "$CASE_CFG/settings.json" "landing@clam=true"
settings "$CASE_WD/.claude/settings.local.json" "lego@clam=true"
cli_says '{"error":"unresolvable"}'
before_cfg=$(snapshot "$CASE_CFG"); before_wd=$(snapshot "$CASE_WD")
run_hook "$(payload "$CASE_WD")" >/dev/null
after_cfg=$(snapshot "$CASE_CFG"); after_wd=$(snapshot "$CASE_WD")

check "18 detection writes nothing under the config dir" \
  "$([[ "$before_cfg" == "$after_cfg" ]] && echo unchanged || echo mutated)" "unchanged"
check "18 detection writes nothing under the working directory" \
  "$([[ "$before_wd" == "$after_wd" ]] && echo unchanged || echo mutated)" "unchanged"

# ---------------------------------------------------------------------------
# 19. Invariants across every branch, using the outputs captured above: the
#     /build:sync-pr standing instruction is always injected, and no
#     user-visible text refers to the old "deliver" namespace.
# ---------------------------------------------------------------------------
check "19 all-companions branch carries the /build:sync-pr instruction" \
  "$(has "$OUT_ALL" '/build:sync-pr')" "yes"
check "19 partial branch carries the /build:sync-pr instruction" \
  "$(has "$OUT_PARTIAL" '/build:sync-pr')" "yes"
check "19 no-companions branch carries the /build:sync-pr instruction" \
  "$(has "$OUT_NONE" '/build:sync-pr')" "yes"
check "19 no-signal branch carries the /build:sync-pr instruction" \
  "$(has "$OUT_NOSIG" '/build:sync-pr')" "yes"
check "19 all-companions branch never says /deliver" \
  "$(has "$OUT_ALL" '/deliver')" "no"
check "19 no-companions branch never says /deliver" \
  "$(has "$OUT_NONE" '/deliver')" "no"

# ---------------------------------------------------------------------------
# 20. Fail-open. Every one of these exits 0; the first three produce no
#     output at all, and a cwd that does not exist on disk still yields
#     well-formed context rather than breaking session start.
# ---------------------------------------------------------------------------
new_case fail-open

out=$(printf '{"hook_event_name":"SessionStart"}' | env -i PATH="$CASE_PATH" \
  HOME="$FAKEHOME" CLAUDE_CONFIG_DIR="$CASE_CFG" "$BASH_BIN" "$HOOK" 2>/dev/null); rc=$?
check "20 no-cwd payload exits 0" "$rc" "0"
check "20 no-cwd payload produces no output" "${#out}" "0"

out=$(printf 'not valid json' | env -i PATH="$CASE_PATH" \
  HOME="$FAKEHOME" CLAUDE_CONFIG_DIR="$CASE_CFG" "$BASH_BIN" "$HOOK" 2>/dev/null); rc=$?
check "20 malformed-json payload exits 0" "$rc" "0"
check "20 malformed-json payload produces no output" "${#out}" "0"

# `bash` is resolved to an absolute path FIRST: a bare `PATH= bash` would
# apply the empty PATH to the bash lookup itself and fail with 127 before
# the hook ever ran. Load-bearing — see the header.
out=$(printf '%s' "$(payload "$CASE_WD")" | env -i PATH="" HOME="$FAKEHOME" \
  CLAUDE_CONFIG_DIR="$CASE_CFG" "$BASH_BIN" "$HOOK" 2>/dev/null); rc=$?
check "20 missing jq exits 0" "$rc" "0"
check "20 missing jq produces no output" "${#out}" "0"

raw=$(run_hook "$(payload "$TMPROOT/fail-open/no-such-directory")"); rc=$?
check "20 nonexistent cwd exits 0" "$rc" "0"
check "20 nonexistent cwd still emits valid hook JSON" \
  "$(printf '%s' "$raw" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "SessionStart"

# ---------------------------------------------------------------------------
# 21. Neither CLAUDE_CONFIG_DIR nor HOME is set. The contract resolves the
#     config root as "${CLAUDE_CONFIG_DIR:-$HOME/.claude}", so with both
#     unset there is no config root to read — under `set -u` that is an
#     unbound-variable abort unless the hook guards it.
#
#     What the contract requires here, and why this case asserts the
#     ENVELOPE rather than merely exit 0. The Errors section names exactly
#     three triggers for the silent form of fail-open ("exit 0, no output"):
#     jq not on PATH, no cwd in payload, malformed payload. An unresolvable
#     config root is none of them. It is a detection failure, and the very
#     next sentence rules on those: "Every detection failure is narrower
#     than that: it demotes one signal, never the hook." So an unset HOME
#     demotes signal 2, exactly as a missing installed_plugins.json does in
#     case 15 — and with `claude` also off PATH, no signal resolves, every
#     companion is absent, and the negative branch is emitted. Reading it as
#     the silent form would make an unset HOME the only detection failure
#     that costs the user their session context, which is the opposite of
#     what "narrower" means. Exit 0 alone would pass on a hook that fails
#     open by accident; this asserts it fails open by design.
#
#     stderr is asserted empty because the diagnostic is part of the defect,
#     not a side note: a SessionStart hook writing to stderr surfaces to the
#     user as a broken session start even when the exit status is 0.
#
#     PATH keeps jq and drops `claude` (the same construction as every other
#     CLI-unavailable case); only HOME and CLAUDE_CONFIG_DIR are omitted.
#
#     Four of the five checks below are RED against c13318b. The fifth
#     ("landing absent") is green there for a degenerate reason — the hook
#     produces no output at all, so no marker can appear — and only becomes
#     load-bearing once the envelope check passes. Recorded rather than
#     dropped: it is what stops a later fix from failing open into a
#     FALSE-POSITIVE context block instead of the negative branch.
# ---------------------------------------------------------------------------
new_case no-home-no-config-dir
ERRLOG="$TMPROOT/no-home-no-config-dir/stderr"
raw=$(printf '%s' "$(payload "$CASE_WD")" | env -i PATH="$NOCLI_PATH" \
  "$BASH_BIN" "$HOOK" 2>"$ERRLOG"); rc=$?
out=$(ctx "$raw")

check "21 unset CLAUDE_CONFIG_DIR and HOME: hook exits 0" "$rc" "0"
check "21 unset CLAUDE_CONFIG_DIR and HOME: nothing written to stderr" \
  "$([[ -s "$ERRLOG" ]] && echo "wrote: $(head -n1 "$ERRLOG")" || echo silent)" "silent"
check "21 unset CLAUDE_CONFIG_DIR and HOME: well-formed envelope" \
  "$(printf '%s' "$raw" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "SessionStart"
check "21 unset CLAUDE_CONFIG_DIR and HOME: no signal resolves, landing absent" \
  "$(has "$out" 'merge policy')" "no"
check "21 unset CLAUDE_CONFIG_DIR and HOME: negative branch is emitted" \
  "$(has "$out" 'marketplace')" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
