#!/bin/bash
# Structural/anchor test for the two lego agent definitions against
# Contract: B03 agent-defs-brief-file (see
# .local/contracts/B03-agent-defs-brief-file.md). Both agent definitions are
# prose (documentation) blocks, not executable code, so the tests here are:
#   - required-literal-token checks: each token the contract lists under
#     "Required literal tokens" must appear, verbatim, in BOTH target files
#     (fixed-string grep per token per file)
#   - frontmatter invariants: `name:` matches each file's agent name and
#     `model: sonnet` is present in both, unchanged
#   - report-format invariants: the `## Report format` heading and the
#     literal `STATUS: COMPLETE | ESCALATION` block are present in both
# Per the brief, prose semantics beyond tokens/headings are NOT tested here;
# the orchestrator verifies meaning at acceptance.
# These MUST fail (on the required-literal-token checks) against the current
# agent definitions, which do not yet carry the brief-file protocol, and MUST
# pass once both files are edited to satisfy the contract.
# Run: bash plugins/lego/scripts/agent-defs.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TW="$SCRIPT_DIR/../agents/lego-test-writer.md"
IMPL="$SCRIPT_DIR/../agents/lego-implementer.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Fixed-string (literal) presence check, case-sensitive. `--` guards literals
# that start with a dash from being parsed as grep options.
has_f() { # content literal
  if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi
}

# Wrap-tolerant variant of has_f (same technique as dispatch-skill.test.sh).
# grep is line-oriented and these agent definitions hard-wrap prose at ~80
# columns, so a multi-word literal can have its own words land on opposite
# sides of a source line break. Collapse every whitespace run — newlines
# included — to a single space before matching, so a token that reads
# correctly to a human matches regardless of where the wrap falls.
has_fn() { # content literal
  local flat; flat=$(tr '\n' ' ' <<<"$1" | tr -s ' ')
  if grep -qF -- "$2" <<<"$flat"; then echo yes; else echo no; fi
}

for f in "$TW" "$IMPL"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL  target agent definition not found: $f"
    exit 1
  fi
done

TW_RAW=$(cat "$TW")
IMPL_RAW=$(cat "$IMPL")

# --- Required literal tokens (contract: "Required literal tokens") --------
# Each token MUST appear verbatim in BOTH target files.
REQUIRED_TOKENS=(
  ".local/briefs/"
  "read the brief file first"
  "orchestrator-owned"
  "read-only"
)

for tok in "${REQUIRED_TOKENS[@]}"; do
  check "lego-test-writer.md contains required literal token: $tok" \
    "$(has_f "$TW_RAW" "$tok")" "yes"
  check "lego-implementer.md contains required literal token: $tok" \
    "$(has_f "$IMPL_RAW" "$tok")" "yes"
done

# --- Frontmatter invariants (contract: Invariants, "Frontmatter ... unchanged") ---
# Lines strictly between the first two '---' delimiters of each file.
frontmatter() { awk '/^---$/{n++; next} n==1' "$1"; }

TW_FM=$(frontmatter "$TW")
IMPL_FM=$(frontmatter "$IMPL")

TW_NAME=$(printf '%s\n' "$TW_FM" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
IMPL_NAME=$(printf '%s\n' "$IMPL_FM" | grep '^name:' | sed -E 's/^name:[[:space:]]*//')
TW_MODEL=$(printf '%s\n' "$TW_FM" | grep '^model:' | sed -E 's/^model:[[:space:]]*//')
IMPL_MODEL=$(printf '%s\n' "$IMPL_FM" | grep '^model:' | sed -E 's/^model:[[:space:]]*//')

check "lego-test-writer.md frontmatter name is 'lego-test-writer'" "$TW_NAME" "lego-test-writer"
check "lego-implementer.md frontmatter name is 'lego-implementer'" "$IMPL_NAME" "lego-implementer"
# B12 moves both worker defs off the sonnet tier: model opus, effort low.
TW_EFFORT=$(printf '%s\n' "$TW_FM" | grep '^effort:' | sed -E 's/^effort:[[:space:]]*//')
IMPL_EFFORT=$(printf '%s\n' "$IMPL_FM" | grep '^effort:' | sed -E 's/^effort:[[:space:]]*//')

check "lego-test-writer.md frontmatter model is 'opus' (B12 tier)" "$TW_MODEL" "opus"
check "lego-implementer.md frontmatter model is 'opus' (B12 tier)" "$IMPL_MODEL" "opus"
check "lego-test-writer.md frontmatter effort is 'low' (B12 tier)" "$TW_EFFORT" "low"
check "lego-implementer.md frontmatter effort is 'low' (B12 tier)" "$IMPL_EFFORT" "low"

# --- Report-format invariants (contract: Invariants, "Report format ... unchanged") ---
check "lego-test-writer.md has '## Report format' heading" \
  "$(has_f "$TW_RAW" "## Report format")" "yes"
check "lego-implementer.md has '## Report format' heading" \
  "$(has_f "$IMPL_RAW" "## Report format")" "yes"
check "lego-test-writer.md has literal 'STATUS: COMPLETE | ESCALATION'" \
  "$(has_f "$TW_RAW" "STATUS: COMPLETE | ESCALATION")" "yes"
check "lego-implementer.md has literal 'STATUS: COMPLETE | ESCALATION'" \
  "$(has_f "$IMPL_RAW" "STATUS: COMPLETE | ESCALATION")" "yes"

# --- Report channel (#184) ------------------------------------------------
# Both definitions previously specified the report's FORMAT and never its
# CHANNEL, which is what let two workers independently guess SendMessage and
# lose their reports silently. These tokens pin the three clauses that close
# that gap, in BOTH files, wrap-tolerantly:
#   1. the report is a FILE, at the path the brief names under .local/reports/
#   2. the message is a one-line notification, never the report body
#   3. that file is the single carved-out write surface under .local/
CHANNEL_TOKENS=(
  ".local/reports/NN-<wave>-<blocks>.md"
  "one-line notification naming that path"
  "never the report body"
  "the one path under \`.local/\` you may write"
)

for tok in "${CHANNEL_TOKENS[@]}"; do
  check "lego-test-writer.md contains report-channel token: $tok" \
    "$(has_fn "$TW_RAW" "$tok")" "yes"
  check "lego-implementer.md contains report-channel token: $tok" \
    "$(has_fn "$IMPL_RAW" "$tok")" "yes"
done

# The pre-#184 prose declared the whole of `.local/` — `reports/` explicitly
# included — read-only for workers. Keeping that sentence alongside the new
# carve-out would leave each definition contradicting itself, so the old
# enumeration must be GONE, not merely added to.
check "lego-test-writer.md no longer lists reports/ among the read-only tree" \
  "$(has_fn "$TW_RAW" "\`status.md\`, \`briefs/\`, and \`reports/\` — is orchestrator-owned and read-only")" "no"
check "lego-implementer.md no longer lists reports/ among the read-only tree" \
  "$(has_fn "$IMPL_RAW" "\`status.md\`, \`briefs/\`, and \`reports/\` — is orchestrator-owned and read-only")" "no"

# --- B04 worker-report-escalation-and-legacy-brief (contract: B04) --------
# The contract's own HTML comment (search each file for "Contract: B04") is
# embedded directly inside "## Report format", quoting nearly the exact
# clauses the real prose needs — matching $TW_RAW/$IMPL_RAW directly would
# pass today against the comment alone, before any real edit exists. Strip
# HTML comments first (same technique as dispatch-skill.test.sh), then scope
# to "## Report format" — the last section in both files, so no closing
# anchor is needed — so only real prose in the section the contract governs
# can satisfy these checks.
strip_comments() { perl -0777 -pe 's/<!--.*?-->//gs' "$1"; }
report_section() { awk '/^## Report format$/{flag=1} flag' <<<"$1"; }

TW_STRIPPED=$(strip_comments "$TW")
IMPL_STRIPPED=$(strip_comments "$IMPL")
TW_REPORT=$(report_section "$TW_STRIPPED")
IMPL_REPORT=$(report_section "$IMPL_STRIPPED")

# OR-match helper (same wrap-tolerant flattening as has_fn): passes if ANY of
# several reasonable phrasings is present. Used where the contract fixes the
# concept but leaves each file's exact wording to its own voice — the rule
# must be stated, not stated in one exact phrasing.
any_fn() { # content phrase1 [phrase2 ...]
  local content="$1"; shift
  local flat; flat=$(tr '\n' ' ' <<<"$content" | tr -s ' ')
  for p in "$@"; do
    if grep -qF -- "$p" <<<"$flat"; then echo yes; return; fi
  done
  echo no
}

# Clause 1: an ESCALATION still writes the report file, exactly as a
# COMPLETE does — escalating is not an exemption from the file protocol.
check "lego-test-writer.md: an ESCALATION still writes the report file (not exempt)" \
  "$(any_fn "$TW_REPORT" "still writes" "not an exemption" "exemption from the file protocol" "same as a COMPLETE" "as a COMPLETE does")" "yes"
check "lego-implementer.md: an ESCALATION still writes the report file (not exempt)" \
  "$(any_fn "$IMPL_REPORT" "still writes" "not an exemption" "exemption from the file protocol" "same as a COMPLETE" "as a COMPLETE does")" "yes"

# Clause 2: a brief that names no report path (an old-style brief) is still
# answered with a file, under .local/reports/ at the brief's own NN.
check "lego-test-writer.md: old-style brief (no report path) still gets a file" \
  "$(any_fn "$TW_REPORT" "old-style brief" "no report path" "names no path" "names no report path")" "yes"
check "lego-implementer.md: old-style brief (no report path) still gets a file" \
  "$(any_fn "$IMPL_REPORT" "old-style brief" "no report path" "names no path" "names no report path")" "yes"

# Clause 2b: that fallback is flagged in the report, not applied silently.
check "lego-test-writer.md: fallback is flagged in the report" \
  "$(has_fn "$TW_REPORT" "flag")" "yes"
check "lego-implementer.md: fallback is flagged in the report" \
  "$(has_fn "$IMPL_REPORT" "flag")" "yes"

# Note: the contract's other named invariant — the fenced STATUS block
# untouched — is already asserted above ("has literal 'STATUS: COMPLETE |
# ESCALATION'" for both files), so it is not duplicated here.

# =========================================================================
# B09 agent-defs-worker-boundaries (plan 001-lego-config-redesign)
# =========================================================================
# Contract: the HTML-comment blocks marked `Contract: B09 ...` in BOTH
# agent definitions. Every assertion below runs against the comment-STRIPPED
# view ($TW_STRIPPED / $IMPL_STRIPPED, built above), so the contract comment
# can never satisfy its own check and the suite survives the comment's
# deletion at acceptance.
#
# Case-insensitive, wrap-tolerant OR-match. The contract fixes the RULE, not
# each file's exact phrasing or capitalisation ("Never git push" at the head
# of a bullet vs "never git push" mid-sentence), so patterns are given in
# lowercase and the content is lowercased before matching.
any_fi() { # content lower_phrase1 [lower_phrase2 ...]
  local content="$1"; shift
  local flat
  flat=$(tr '\n' ' ' <<<"$content" | tr -s ' ' | tr '[:upper:]' '[:lower:]')
  for p in "$@"; do
    if grep -qF -- "$p" <<<"$flat"; then echo yes; return; fi
  done
  echo no
}

# The brief-inputs section of each file: everything from the "## Inputs ..."
# heading to the "## Rules" heading. Scoping the command-resolution clauses
# here keeps generic words ("escalate") in the Rules section from satisfying
# them.
inputs_section() { awk '/^## Inputs/{flag=1; next} /^## Rules/{flag=0} flag' <<<"$1"; }

TW_INPUTS=$(inputs_section "$TW_STRIPPED")
IMPL_INPUTS=$(inputs_section "$IMPL_STRIPPED")

# --- B09 Behavior: config prose replaced by brief-named commands ----------
check "lego-test-writer.md: runs exactly the commands the brief names" \
  "$(any_fi "$TW_INPUTS" "exactly the commands your brief names" "exactly the commands the brief names" "the commands your brief names" "run exactly the command")" "yes"
check "lego-implementer.md: runs exactly the commands the brief names" \
  "$(any_fi "$IMPL_INPUTS" "exactly the commands your brief names" "exactly the commands the brief names" "the commands your brief names" "run exactly the command")" "yes"

# --- B09 Behavior: the single fallback is .local/unit.md's `Test:` field ---
check "lego-test-writer.md: names unit.md as the only fallback source" \
  "$(any_fi "$TW_INPUTS" "unit.md")" "yes"
check "lego-implementer.md: names unit.md as the only fallback source" \
  "$(any_fi "$IMPL_INPUTS" "unit.md")" "yes"
check "lego-test-writer.md: names unit.md's 'Test:' field" \
  "$(has_fn "$TW_INPUTS" "Test:")" "yes"
check "lego-implementer.md: names unit.md's 'Test:' field" \
  "$(has_fn "$IMPL_INPUTS" "Test:")" "yes"

# --- B09 Behavior: neither resolves -> escalate; never derive/read config --
check "lego-test-writer.md: unresolved command is an escalation to the orchestrator" \
  "$(any_fi "$TW_INPUTS" "escalate to the orchestrator")" "yes"
check "lego-implementer.md: unresolved command is an escalation to the orchestrator" \
  "$(any_fi "$IMPL_INPUTS" "escalate to the orchestrator")" "yes"
check "lego-test-writer.md: never derives commands or reads configuration itself" \
  "$(any_fi "$TW_INPUTS" "never derive" "do not derive" "never read configuration" "never work it out yourself")" "yes"
check "lego-implementer.md: never derives commands or reads configuration itself" \
  "$(any_fi "$IMPL_INPUTS" "never derive" "do not derive" "never read configuration" "never work it out yourself")" "yes"

# --- B09 Behavior: no config vocabulary survives --------------------------
# The layered-config fallback is gone outright, so its vocabulary must be
# absent from the real prose of BOTH files — not merely supplemented.
for tok in "lego.json" "config.json" "effective config" "layered repo config"; do
  check "lego-test-writer.md: config vocabulary gone: $tok" \
    "$(any_fi "$TW_STRIPPED" "$tok")" "no"
  check "lego-implementer.md: config vocabulary gone: $tok" \
    "$(any_fi "$IMPL_STRIPPED" "$tok")" "no"
done

# --- B09 Behavior: the "Hard boundaries" rule block -----------------------
check "lego-test-writer.md has a 'Hard boundaries' rule block" \
  "$(any_fi "$TW_STRIPPED" "hard boundaries")" "yes"
check "lego-implementer.md has a 'Hard boundaries' rule block" \
  "$(any_fi "$IMPL_STRIPPED" "hard boundaries")" "yes"

# Each prohibition of the block, pinned separately so a partial rewrite
# cannot pass: push, branch creation, merge, PR, commit.
check "lego-test-writer.md: never git push" \
  "$(any_fi "$TW_STRIPPED" "never git push" "never push")" "yes"
check "lego-implementer.md: never git push" \
  "$(any_fi "$IMPL_STRIPPED" "never git push" "never push")" "yes"
check "lego-test-writer.md: never create branches" \
  "$(any_fi "$TW_STRIPPED" "never create branches" "never create a branch" "never branch")" "yes"
check "lego-implementer.md: never create branches" \
  "$(any_fi "$IMPL_STRIPPED" "never create branches" "never create a branch" "never branch")" "yes"
check "lego-test-writer.md: never merge" \
  "$(any_fi "$TW_STRIPPED" "never merge")" "yes"
check "lego-implementer.md: never merge" \
  "$(any_fi "$IMPL_STRIPPED" "never merge")" "yes"
check "lego-test-writer.md: never open PRs" \
  "$(any_fi "$TW_STRIPPED" "never open prs" "never open a pr" "never open pull requests")" "yes"
check "lego-implementer.md: never open PRs" \
  "$(any_fi "$IMPL_STRIPPED" "never open prs" "never open a pr" "never open pull requests")" "yes"
check "lego-test-writer.md: never git commit" \
  "$(any_fi "$TW_STRIPPED" "never git commit" "never commit")" "yes"
check "lego-implementer.md: never git commit" \
  "$(any_fi "$IMPL_STRIPPED" "never git commit" "never commit")" "yes"

# --- B09 Behavior: git bounded to status/diff/log + own-work stash --------
check "lego-test-writer.md: git bounded to status/diff/log" \
  "$(any_fi "$TW_STRIPPED" "status/diff/log" "status, diff, log" "status, diff and log")" "yes"
check "lego-implementer.md: git bounded to status/diff/log" \
  "$(any_fi "$IMPL_STRIPPED" "status/diff/log" "status, diff, log" "status, diff and log")" "yes"
# The stash allowance is what keeps red-run discipline (stash-based revert of
# shared files) legal under the git bound — Invariants clause.
check "lego-test-writer.md: stash of your own uncommitted work stays legal" \
  "$(any_fi "$TW_STRIPPED" "stash")" "yes"
check "lego-implementer.md: stash of your own uncommitted work stays legal" \
  "$(any_fi "$IMPL_STRIPPED" "stash")" "yes"
check "lego-test-writer.md: git bound is scoped to your own unit worktree" \
  "$(any_fi "$TW_STRIPPED" "your own unit worktree" "own unit worktree")" "yes"
check "lego-implementer.md: git bound is scoped to your own unit worktree" \
  "$(any_fi "$IMPL_STRIPPED" "your own unit worktree" "own unit worktree")" "yes"
check "lego-test-writer.md: never run git against another checkout (git -C)" \
  "$(any_fi "$TW_STRIPPED" "git -c")" "yes"
check "lego-implementer.md: never run git against another checkout (git -C)" \
  "$(any_fi "$IMPL_STRIPPED" "git -c")" "yes"
check "lego-test-writer.md: never run git worktree" \
  "$(any_fi "$TW_STRIPPED" "git worktree")" "yes"
check "lego-implementer.md: never run git worktree" \
  "$(any_fi "$IMPL_STRIPPED" "git worktree")" "yes"

# --- B09 Behavior + Edge case: delivery facts are ignored, not acted on ---
# A brief that names budgets, PR groups, or delivery modes by mistake -> the
# worker ignores them and continues.
check "lego-test-writer.md: delivery facts are orchestrator business" \
  "$(any_fi "$TW_STRIPPED" "budgets, pr groups, and delivery modes" "budgets, pr groups and delivery modes" "orchestrator business")" "yes"
check "lego-implementer.md: delivery facts are orchestrator business" \
  "$(any_fi "$IMPL_STRIPPED" "budgets, pr groups, and delivery modes" "budgets, pr groups and delivery modes" "orchestrator business")" "yes"
check "lego-test-writer.md: an encountered delivery fact is ignored, and work continues" \
  "$(any_fi "$TW_STRIPPED" "ignore it and continue" "ignore them and continue" "ignore it and proceed")" "yes"
check "lego-implementer.md: an encountered delivery fact is ignored, and work continues" \
  "$(any_fi "$IMPL_STRIPPED" "ignore it and continue" "ignore them and continue" "ignore it and proceed")" "yes"

# --- B09 Behavior: no subagents; escalate to the orchestrator only --------
check "lego-test-writer.md: never spawn subagents" \
  "$(any_fi "$TW_STRIPPED" "never spawn subagents" "never spawn a subagent" "no subagents")" "yes"
check "lego-implementer.md: never spawn subagents" \
  "$(any_fi "$IMPL_STRIPPED" "never spawn subagents" "never spawn a subagent" "no subagents")" "yes"
check "lego-test-writer.md: never message the engineer directly" \
  "$(any_fi "$TW_STRIPPED" "never message the engineer" "not the engineer" "never contact the engineer")" "yes"
check "lego-implementer.md: never message the engineer directly" \
  "$(any_fi "$IMPL_STRIPPED" "never message the engineer" "not the engineer" "never contact the engineer")" "yes"

# --- B09 Behavior: implementer's prose-contract deletion exception REMOVED -
# The orchestrator deletes the HTML-comment contract at acceptance, so Rule
# 3's carve-out must be GONE from lego-implementer.md's real prose.
check "lego-implementer.md: Rule 3 prose-block deletion exception is removed" \
  "$(any_fi "$IMPL_STRIPPED" "sole exception is a **prose block**" "sole exception is a prose block")" "no"
check "lego-implementer.md: no instruction to delete the contract comment" \
  "$(any_fi "$IMPL_STRIPPED" "delete that comment" "(remove at acceptance)")" "no"
# The exception never existed in lego-test-writer.md; pin that it stays absent.
check "lego-test-writer.md: carries no prose-contract deletion exception" \
  "$(any_fi "$TW_STRIPPED" "delete that comment" "sole exception is a prose block")" "no"

# --- B09 Invariants: realm and escalation rules unchanged ----------------
check "lego-test-writer.md: realm restriction rule survives" \
  "$(any_fi "$TW_STRIPPED" "realm restriction")" "yes"
check "lego-implementer.md: test-family prohibition survives" \
  "$(any_fi "$IMPL_STRIPPED" "never touch the test family")" "yes"
check "lego-test-writer.md: red discipline rule survives" \
  "$(any_fi "$TW_STRIPPED" "red discipline")" "yes"

# =========================================================================
# B12 worker-bash-gate-and-tier (plan 001-lego-config-redesign)
# =========================================================================
# Contract: the docblock in plugins/lego/scripts/bash-gate.sh. The tier
# clause (model: opus / effort: low) is asserted with the other frontmatter
# invariants above; what follows is the hook's behaviour, its wiring, and
# the removal of the repo-local shadow copies.

GATE="$SCRIPT_DIR/bash-gate.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

check "bash-gate.sh exists at plugins/lego/scripts/bash-gate.sh" \
  "$([[ -f "$GATE" ]] && echo yes || echo no)" "yes"

# Black-box invocation through the script's only interface: hook JSON on
# stdin -> stdout + exit code. Never reaches into internals.
gate_payload() { # command
  printf '{"agent_type":"lego-test-writer","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"
}

GATE_OUT=""
GATE_RC=0
run_gate() { # raw_stdin
  GATE_OUT=$(printf '%s' "$1" | bash "$GATE" 2>/dev/null)
  GATE_RC=$?
}

# Deny: the hook-protocol deny response (exit 0 + decision JSON on stdout,
# same protocol as realm-gate.sh), a reason naming the matched rule, and the
# instruction to escalate to the orchestrator.
assert_deny() { # command rule_token
  run_gate "$(gate_payload "$1")"
  local flat lower
  flat=$(tr -d ' \n' <<<"$GATE_OUT")
  lower=$(tr '[:upper:]' '[:lower:]' <<<"$GATE_OUT")
  check "bash-gate: '$1' -> exit 0 (hook protocol)" "$GATE_RC" "0"
  check "bash-gate: '$1' -> permissionDecision deny" \
    "$(has_f "$flat" '"permissionDecision":"deny"')" "yes"
  check "bash-gate: '$1' -> reason names the matched rule ($2)" \
    "$(has_f "$lower" "$2")" "yes"
  check "bash-gate: '$1' -> reason says escalate to the orchestrator" \
    "$(has_f "$lower" "escalate")" "yes"
  check "bash-gate: '$1' -> reason names the orchestrator" \
    "$(has_f "$lower" "orchestrator")" "yes"
}

# Allow: exit 0 and NO output at all (an empty stdout is what makes the hook
# a pass-through).
assert_allow() { # command
  run_gate "$(gate_payload "$1")"
  check "bash-gate allows '$1' -> exit 0" "$GATE_RC" "0"
  check "bash-gate allows '$1' -> no output" "$GATE_OUT" ""
}

# --- B12 Behavior: the prohibited family is denied -----------------------
assert_deny "git push" "push"
assert_deny "git push --force-with-lease origin HEAD" "push"
assert_deny "git merge lego/001/U07" "merge"
assert_deny "git branch lego/001/U07" "branch"
assert_deny "git checkout -b lego/001/U07" "checkout -b"
assert_deny "git switch -c lego/001/U07" "switch -c"
assert_deny "git worktree add ../wt master" "worktree"
assert_deny "git commit -m wip" "commit"
assert_deny "gh pr create --fill" "pr"
assert_deny "gh api repos/o/r/pulls" "api"

# --- B12 Behavior: matched anywhere in the string, compounds included ----
assert_deny "bash plugins/lego/scripts/agent-defs.test.sh && git push" "push"
assert_deny "cd /tmp; git commit -am wip" "commit"

# --- B12 Invariants: read-only git and all non-git commands pass ---------
assert_allow "git status"
assert_allow "git status --porcelain"
assert_allow "git diff"
assert_allow "git log --oneline -5"
assert_allow "git stash"
assert_allow "git stash pop"
assert_allow "bash plugins/lego/scripts/agent-defs.test.sh"
assert_allow "npm test"
assert_allow "ls -la plugins/lego/scripts"

# --- B12 Errors: malformed/absent input fails OPEN -----------------------
assert_fail_open() { # label raw_stdin
  run_gate "$2"
  check "bash-gate fails open on $1 -> exit 0" "$GATE_RC" "0"
  check "bash-gate fails open on $1 -> no deny output" "$GATE_OUT" ""
}

assert_fail_open "empty stdin" ""
assert_fail_open "non-JSON stdin" "this is not json at all"
assert_fail_open "truncated JSON" '{"agent_type":"lego-test-writer","tool_input":'
assert_fail_open "JSON with no command field" \
  '{"agent_type":"lego-test-writer","tool_name":"Bash","tool_input":{}}'

# --- B12 Invariants: read-only — the hook never touches the filesystem ----
GATE_TMP="$(mktemp -d)"
(cd "$GATE_TMP" && printf '%s' "$(gate_payload "git push")" | bash "$GATE" >/dev/null 2>&1)
GATE_TMP_ENTRIES=$(find "$GATE_TMP" -mindepth 1 | wc -l | tr -d ' ')
check "bash-gate writes nothing to disk (deny path leaves cwd untouched)" \
  "$GATE_TMP_ENTRIES" "0"
rm -rf "$GATE_TMP"

# --- B12: the hook is wired via a Bash matcher in BOTH worker defs -------
# Frontmatter only ($TW_FM/$IMPL_FM) — a mention in prose is not wiring.
bash_matcher() { # frontmatter
  if grep -qE '^[[:space:]]*-?[[:space:]]*matcher:.*Bash' <<<"$1"; then echo yes; else echo no; fi
}

check "lego-test-writer.md frontmatter has a Bash matcher" \
  "$(bash_matcher "$TW_FM")" "yes"
check "lego-implementer.md frontmatter has a Bash matcher" \
  "$(bash_matcher "$IMPL_FM")" "yes"
check "lego-test-writer.md frontmatter wires bash-gate.sh" \
  "$(has_f "$TW_FM" "bash-gate.sh")" "yes"
check "lego-implementer.md frontmatter wires bash-gate.sh" \
  "$(has_f "$IMPL_FM" "bash-gate.sh")" "yes"
# Invariant: bash-gate.sh sits ALONGSIDE realm-gate.sh; the existing
# Edit|Write|NotebookEdit wiring is not replaced.
check "lego-test-writer.md frontmatter still wires realm-gate.sh" \
  "$(has_f "$TW_FM" "realm-gate.sh")" "yes"
check "lego-implementer.md frontmatter still wires realm-gate.sh" \
  "$(has_f "$IMPL_FM" "realm-gate.sh")" "yes"

# --- B12 Invariants: worker defs only, never orchestrator context --------
# The gate is registered in the two worker agent definitions; it must not be
# wired repo-wide via a hooks.json, which would put it in orchestrator (main
# session) context.
check "bash-gate.sh is not wired repo-wide via a hooks.json" \
  "$(grep -rlF "bash-gate.sh" "$REPO_ROOT/plugins" --include="hooks*.json" 2>/dev/null | head -1)" ""

# --- B12: no repo-local shadow copies of the worker defs remain ----------
# The drifted .claude/agents/lego-*.md copies are deleted outright: the
# plugin definitions are the single source.
check "no repo-local .claude/agents/lego-test-writer.md remains" \
  "$([[ -e "$REPO_ROOT/.claude/agents/lego-test-writer.md" ]] && echo present || echo absent)" "absent"
check "no repo-local .claude/agents/lego-implementer.md remains" \
  "$([[ -e "$REPO_ROOT/.claude/agents/lego-implementer.md" ]] && echo present || echo absent)" "absent"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
