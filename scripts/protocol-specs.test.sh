#!/usr/bin/env bash
# protocol-specs.test.sh — contract tests for the four protocol-spec docs
# (plan 001-ensure-agents-understand-architecture):
#   - B04 protocol-spec-session-states (docs/protocols/session-states.md)
#   - B05 protocol-spec-decision-file  (docs/protocols/decision-file.md)
#   - B06 protocol-spec-setup-stamp    (docs/protocols/setup-stamp.md)
#   - B07 protocol-spec-todo-format    (docs/protocols/todo-format.md)
#
# Black-box, content-assertion tests against the committed doc files
# themselves (there is no script under test here). Each doc's HTML
# "<!-- Contract: B0N ... -->" comment restates every clause the doc must
# end up stating, so a naive grep against the raw file could pass for the
# wrong reason (matching the CONTRACT, not the delivered prose). Every
# clause assertion below therefore runs against a stripped copy with the
# contract comment removed; two separate hygiene checks run against the
# untouched raw file (and the stripped copy) to confirm the contract
# comment and the "STUB — NotImplemented" marker are both gone once the
# implementation wave lands.
#
# Phrase/keyword checks run against a "flat" copy of the stripped doc
# (newlines collapsed to single spaces) so the repo's prose-wrapping can
# never split a checked phrase across a line boundary. The one exception is
# B04's 13 state-table triples: those run against the unflattened,
# per-line stripped text, because AND-ing three short tokens against the
# whole flattened document would happily match across three DIFFERENT
# table rows instead of confirming they share one row.
#
#
# ---------------------------------------------------------------------------
# B02 setup-stamp-measured-at (plan 001-issues-317-318, issue #318)
#
# Adds clauses to the B06 setup-stamp section below: `at` is a value read
# from the clock, not just a value shape. Source of truth is the
# "Contract: B02 setup-stamp-measured-at" docblock at the top of
# docs/protocols/setup-stamp.md.
#
# Two vacuity guards these clauses need and the suite did not already have:
#   - B02's contract docblock opens with a bare "<!--" and carries
#     "Contract: B02" on the NEXT line, so the per-doc sed ranges above —
#     which key on "<!-- Contract: B0N" appearing on the OPENING line — do
#     not strip it, and sp_doc/sp_flat still contain it verbatim. Left in,
#     the docblock restates every clause below (the literal date command
#     included) and would satisfy them all with no delivered prose written.
#     strip_comment_block() removes it.
#   - The scaffold's STUB sentence paraphrases the very requirement it
#     stands in for ("this bullet must say the value is measured when the
#     stamp is written, and name the command that produces it"), so a phrase
#     check would likewise pass on the stub's own words. drop_stub_blocks()
#     removes the marker line through the end of its markdown block.
# Both helpers are no-ops once the scaffold is gone, so they can only make
# these clauses stricter at birth, never weaker at acceptance.
#
# RED/GREEN at birth for the added clauses — all four are RED:
#   - "B02 contract comment removed from source": the docblock is in the
#     file today.
#   - "names the command that produces 'at'" (doc-level) and "the Shape
#     section's 'at' bullet is where that command is named"
#     (bullet-scoped): `date -u +%Y-%m-%dT%H:%M:%SZ` occurs only inside the
#     B02 docblock today, which is stripped.
#   - "'at' is measured when the stamp is written": with the stub bullet
#     dropped, the `at` bullet is empty, so no measurement phrase survives.
#   - "'at' is never invented, guessed, or copied": no such clause exists.
# The two existing setup-stamp hygiene clauses ("contract comment removed
# from source", "STUB marker removed") are deliberately NOT re-added. Their
# current state, for the record: the STUB check is RED (the scaffold's
# marker sits in the `at` bullet); the "Contract: B06" check is GREEN, but
# vacuously — B06's docblock was removed when B06 landed and that check
# keys on B06's marker, not B02's. That is why a B02-specific hygiene
# clause is added below rather than folded into the existing one.
#
# Run: bash scripts/protocol-specs.test.sh   (exits non-zero on any failure)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# Assertion helpers.
# ---------------------------------------------------------------------------
contains() { # text needle -> yes/no (plain substring; needle is quoted so
             # glob metacharacters in it are never interpreted)
  case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac
}

contains_any() { # text needle... -> yes if any needle is present
  local text="$1"; shift
  local n
  for n in "$@"; do
    case "$text" in *"$n"*) echo yes; return ;; esac
  done
  echo no
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

contains_ci() { # text needle -> yes/no (case-insensitive substring)
  case "$(lower "$1")" in *"$(lower "$2")"*) echo yes ;; *) echo no ;; esac
}

word_present() { # text word -> yes/no (word-boundary match, so e.g.
                  # "active" doesn't fire on "interactive", and "no" doesn't
                  # fire inside "Not"/"known"/etc.)
  if printf '%s' "$1" | grep -qw -- "$2"; then echo yes; else echo no; fi
}

field_present() { # text field -> yes/no: field wrapped in backticks or in
                   # JSON double-quotes. Used for short/generic field names
                   # (notably "at") where a bare substring or word check
                   # would false-PASS on ordinary prose.
  local text="$1" field="$2" bt='`'
  case "$text" in *"${bt}${field}${bt}"*) echo yes; return ;; esac
  case "$text" in *"\"${field}\""*) echo yes; return ;; esac
  echo no
}

# yes if some single line of $1 contains every one of the remaining needles
# (plain substring match per needle; mirrors scripts/readme-lint.test.sh's
# line_has_all). Used only for B04's table rows, which the contract
# guarantees render as one GFM row per line.
line_has_all() { # text needle...
  local text="$1"; shift
  local line ok n
  while IFS= read -r line; do
    ok=1
    for n in "$@"; do
      case "$line" in *"$n"*) ;; *) ok=0; break ;; esac
    done
    [ "$ok" -eq 1 ] && { echo yes; return; }
  done <<< "$text"
  echo no
}

flatten() { # text -> newlines collapsed to single spaces, runs of
            # whitespace squeezed to one space each
  printf '%s' "$1" | tr '\n' ' ' | tr -s '[:space:]' ' '
}

# Drops the whole HTML comment block whose text contains $2 (fixed string),
# opening "<!--" line through the closing "-->". Unlike the per-doc sed
# ranges below, the marker need not sit on the opening line. Other comment
# blocks are passed through untouched. Deliberate simplification, safe for
# this repo's docblock convention: a block comment is assumed to own the
# lines it spans, so a line carrying both real content and a "<!--" would
# be dropped whole.
strip_comment_block() { # text marker -> stdout
  awk -v marker="$2" '
    function flush() { if (!hit) printf "%s", buf; buf = ""; hit = 0; inc = 0 }
    !inc && index($0, "<!--") {
      inc = 1; buf = $0 "\n"; hit = (index($0, marker) > 0)
      if (index($0, "-->") > 0) flush()
      next
    }
    inc {
      buf = buf $0 "\n"
      if (index($0, marker) > 0) hit = 1
      if (index($0, "-->") > 0) flush()
      next
    }
    { print }
    END { if (inc) flush() }
  ' <<< "$1"
}

# Drops each "STUB — NotImplemented" marker line through the end of its
# markdown block (up to, not including, the next blank line). A no-op once
# the markers are gone. See the B02 note in the header for why the marker
# line alone is not enough.
drop_stub_blocks() { # text -> stdout
  awk '
    /STUB — NotImplemented/ { skipping = 1 }
    skipping && /^[[:space:]]*$/ { skipping = 0 }
    !skipping { print }
  ' <<< "$1"
}

# The Shape section's `at` bullet: its first line through the end of its
# markdown block (next top-level bullet, next heading, or blank line).
# Empty when no such bullet exists. Used to scope the field's semantics to
# the bullet that defines it, so the `version` bullet — which legitimately
# already says "at the time the stamp was written" — cannot satisfy them.
at_bullet() { # text (unflattened) -> stdout
  awk '
    /^- `at`/ { found = 1; print; next }
    found && (/^- / || /^#/ || /^[[:space:]]*$/) { exit }
    found { print }
  ' <<< "$1"
}

# Byte offset of the first occurrence of a literal needle in text, or -1 if
# absent. Needles used below never contain */?/[ so treating them as a
# glob pattern in the parameter expansion is safe (quoting the expansion
# suppresses glob interpretation of its content regardless).
first_offset() { # text needle -> offset
  local text="$1" needle="$2" prefix
  case "$text" in
    *"$needle"*) ;;
    *) echo -1; return ;;
  esac
  prefix="${text%%"$needle"*}"
  echo "${#prefix}"
}

in_order() { # text needle... -> yes if every needle is present and each
             # appears strictly after the previous one (left to right)
  local text="$1"; shift
  local prev=-1 cur n
  for n in "$@"; do
    cur="$(first_offset "$text" "$n")"
    if [ "$cur" -lt 0 ] || [ "$cur" -le "$prev" ]; then echo no; return; fi
    prev="$cur"
  done
  echo yes
}

# ---------------------------------------------------------------------------
# Plugin names, derived dynamically from the repo (never hardcoded) so the
# "no plugin named" checks track additions/removals automatically.
#
# A bare occurrence of a plugin's name is NOT a reference per
# ARCHITECTURE.md / CLAUDE.md's own word-sense rule (e.g. "settings scope",
# "the session tracking document", "notification channels" name no plugin).
# Matching on bare word-boundary alone would enforce something STRONGER than
# the contracts actually require and would false-fail the very prose the
# docs need to write. Instead, a name only counts as "named" when it appears
# in one of the repo's four reference forms:
#   1. skill invocation — /<name>:                (e.g. "/tracking:")
#   2. marketplace id   — <name>@clam             (e.g. "tracking@clam")
#   3. English naming   — the exact word <name> immediately followed by the
#                          word plugin/plugin's/plugins, word-bounded (the
#                          "plugin" word is matched case-insensitively; the
#                          name itself stays exact-case)
#   4. filesystem path  — plugins/<name>/         (e.g. "plugins/tracking/")
# ---------------------------------------------------------------------------
mapfile -t PLUGIN_NAMES < <(find "$REPO_ROOT/plugins" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

first_plugin_named() { # text -> plugin name found (via one of the four
                        # reference forms above), or empty
  local text="$1" name
  for name in "${PLUGIN_NAMES[@]}"; do
    if printf '%s' "$text" | grep -qF -- "/${name}:"; then
      printf '%s' "$name"; return
    fi
    if printf '%s' "$text" | grep -qF -- "${name}@clam"; then
      printf '%s' "$name"; return
    fi
    # Portable ERE (no PCRE): explicit non-word-character boundaries stand in
    # for \b, and an inline [Pp] class for the PCRE's (?i:...) group — BSD grep
    # has no -P and exits 2 on it, which would silently pass this check.
    if printf '%s' "$text" \
      | grep -qE -- "(^|[^[:alnum:]_])${name}[[:space:]]+[Pp]lugin('s|s)?([^[:alnum:]_]|$)"; then
      printf '%s' "$name"; return
    fi
    if printf '%s' "$text" | grep -qF -- "plugins/${name}/"; then
      printf '%s' "$name"; return
    fi
  done
}

# ---------------------------------------------------------------------------
# Load the four docs. Fatal (harness) error, not a test failure, if a file
# is simply missing — that's not what this suite is for.
# ---------------------------------------------------------------------------
SS_FILE="$REPO_ROOT/docs/protocols/session-states.md"
DF_FILE="$REPO_ROOT/docs/protocols/decision-file.md"
SP_FILE="$REPO_ROOT/docs/protocols/setup-stamp.md"
TF_FILE="$REPO_ROOT/docs/protocols/todo-format.md"

for f in "$SS_FILE" "$DF_FILE" "$SP_FILE" "$TF_FILE"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: protocol doc not found at $f" >&2
    exit 1
  fi
done

ss_raw="$(cat "$SS_FILE")"
df_raw="$(cat "$DF_FILE")"
sp_raw="$(cat "$SP_FILE")"
tf_raw="$(cat "$TF_FILE")"

# Strip each file's own contract comment before asserting anything about
# its content (correct both now and after acceptance, when the comment is
# already gone and the strip is a no-op).
ss_doc="$(sed '/<!-- Contract: B04/,/^-->$/d' "$SS_FILE")"
df_doc="$(sed '/<!-- Contract: B05/,/^-->$/d' "$DF_FILE")"
sp_doc="$(sed '/<!-- Contract: B06/,/^-->$/d' "$SP_FILE")"
tf_doc="$(sed '/<!-- Contract: B07/,/^-->$/d' "$TF_FILE")"

ss_flat="$(flatten "$ss_doc")"
df_flat="$(flatten "$df_doc")"
sp_flat="$(flatten "$sp_doc")"
tf_flat="$(flatten "$tf_doc")"

# ===========================================================================
# B04 — session-states.md
# ===========================================================================

# --- Hygiene: contract comment and STUB marker both gone at acceptance ---
check "session-states: contract comment removed from source" \
  "$(contains "$ss_raw" "Contract: B04")" "no"
check "session-states: STUB marker removed" \
  "$(contains "$ss_doc" "STUB — NotImplemented")" "no"

# --- 1. Runtime artifact ---
check "session-states: runtime artifact is .local/TODO.md" \
  "$(contains "$ss_flat" ".local/TODO.md")" "yes"
check "session-states: artifact is the State: field" \
  "$(contains "$ss_flat" "State:")" "yes"
check "session-states: cross-references todo-format.md for the field format" \
  "$(contains "$ss_flat" "todo-format.md")" "yes"

# --- 2. Three attributes; presentation explicitly excluded ---
check "session-states: exactly three attributes per state" \
  "$(contains_ci "$ss_flat" "three attributes")" "yes"
check "session-states: emoji mentioned as a presentation attribute" \
  "$(word_present "$ss_flat" "emoji")" "yes"
check "session-states: colour/color mentioned as a presentation attribute" \
  "$(contains_any "$ss_flat" "colour" "color")" "yes"
check "session-states: presentation attributes explicitly not part of the protocol" \
  "$(contains_ci "$ss_flat" "not part of the protocol")" "yes"

# --- 3. Category vocabulary and semantics ---
check "session-states: category 'active' defined" \
  "$(word_present "$ss_flat" "active")" "yes"
check "session-states: category 'parked' defined" \
  "$(word_present "$ss_flat" "parked")" "yes"
check "session-states: category 'needs_user' defined" \
  "$(word_present "$ss_flat" "needs_user")" "yes"
check "session-states: category 'terminal' defined" \
  "$(word_present "$ss_flat" "terminal")" "yes"
check "session-states: active semantics (work is in flight)" \
  "$(contains_ci "$ss_flat" "work is in flight")" "yes"
check "session-states: parked semantics (stopping is allowed)" \
  "$(contains_ci "$ss_flat" "stopping is allowed")" "yes"
check "session-states: needs_user semantics (a human must act)" \
  "$(contains_ci "$ss_flat" "human must act")" "yes"
check "session-states: terminal semantics (no actionable work remains)" \
  "$(contains_ci "$ss_flat" "no actionable work remains")" "yes"

# --- 4. Summons semantics ---
check "session-states: summons alerts once on transition, never every turn" \
  "$(contains_ci "$ss_flat" "never on every turn")" "yes"
check "session-states: Blocked and Waiting For Decision stop the session" \
  "$(contains_ci "$ss_flat" "stop the session")" "yes"

# --- 5. The complete state table: all 13 (name, category, summons) triples ---
SS_TRIPLES=(
  "Not Started|active|no"
  "In Progress|active|no"
  "Awaiting Agent|parked|no"
  "Awaiting CI|parked|no"
  "Awaiting Independent Agent Review|parked|no"
  "Awaiting User Review|parked|yes"
  "Awaiting Bot Review|parked|no"
  "Awaiting Reviewer Assignment|parked|no"
  "Awaiting Human Review|parked|no"
  "Awaiting Merge Queue|parked|no"
  "Waiting For Decision|needs_user|yes"
  "Blocked|needs_user|yes"
  "Complete|terminal|no"
)
for t in "${SS_TRIPLES[@]}"; do
  IFS='|' read -r nm cat summ <<< "$t"
  check "session-states: triple ($nm / $cat / summons=$summ) on one row" \
    "$(line_has_all "$ss_doc" "$nm" "$cat" "$summ")" "yes"
done
# 13 triples above double as the "2 active / 8 parked / 2 needs_user / 1
# terminal, exactly 3 summons=yes" invariant: it holds iff every one of the
# 13 individual triples above holds.

# --- 6. Conformance clause ---
check "session-states: conformance clause present" \
  "$(word_present "$ss_flat" "conformance")" "yes"
check "session-states: drift on the triple is a conformance defect" \
  "$(contains_ci "$ss_flat" "conformance defect")" "yes"
check "session-states: additions/removals happen here first, copies follow" \
  "$(contains_ci "$ss_flat" "happen here first")" "yes"

# --- Edge case: a State value outside the table is a protocol violation ---
check "session-states: an out-of-table State value is a protocol violation, not an extension point" \
  "$(contains_ci "$ss_flat" "protocol violation")" "yes"

# --- No plugin named ---
check "session-states: no plugin named anywhere in the doc" \
  "$(first_plugin_named "$ss_flat")" ""

# ===========================================================================
# B05 — decision-file.md
# ===========================================================================

# --- Hygiene ---
check "decision-file: contract comment removed from source" \
  "$(contains "$df_raw" "Contract: B05")" "no"
check "decision-file: STUB marker removed" \
  "$(contains "$df_doc" "STUB — NotImplemented")" "no"

# --- 1. Location and naming ---
check "decision-file: location/naming pattern .local/decisions/NNN-<slug>.md" \
  "$(contains "$df_flat" ".local/decisions/NNN-<slug>.md")" "yes"
check "decision-file: NNN is the next free zero-padded three-digit number" \
  "$(contains_ci "$df_flat" "zero-padded")" "yes"
check "decision-file: slug is kebab-case from the question" \
  "$(contains_ci "$df_flat" "kebab-case")" "yes"
check "decision-file: .local/ is gitignored (session-local, not tracked)" \
  "$(contains_ci "$df_flat" "gitignored")" "yes"

# --- 2. Header form ---
check "decision-file: H1 form '# Decision:'" \
  "$(contains "$df_flat" "# Decision:")" "yes"
check "decision-file: Status: line" \
  "$(contains "$df_flat" "Status:")" "yes"
check "decision-file: optional Refs: line" \
  "$(contains "$df_flat" "Refs:")" "yes"

# --- 3. Status lifecycle ---
check "decision-file: Status: Open while undecided" \
  "$(contains "$df_flat" "Status: Open")" "yes"
check "decision-file: Status: Resolved ( pattern" \
  "$(contains "$df_flat" "Resolved (")" "yes"
check "decision-file: resolution recorded by editing the Status line" \
  "$(contains_ci "$df_flat" "editing the Status line")" "yes"
check "decision-file: post-decision detail appended, never rewritten over analysis" \
  "$(word_present "$df_flat" "appended")" "yes"

# --- 4. Four required sections, in order ---
DF_SECTIONS=("## Context" "## Options" "## Recommendation" "## If Deferred")
for s in "${DF_SECTIONS[@]}"; do
  check "decision-file: section '$s' present" \
    "$(contains "$df_flat" "$s")" "yes"
done
check "decision-file: four required sections in order" \
  "$(in_order "$df_flat" "${DF_SECTIONS[@]}")" "yes"

# --- 5. Cross-references to the other two protocol docs ---
check "decision-file: cross-references session-states.md" \
  "$(contains "$df_flat" "session-states.md")" "yes"
check "decision-file: mentions the Waiting For Decision state" \
  "$(contains "$df_flat" "Waiting For Decision")" "yes"
check "decision-file: cross-references todo-format.md" \
  "$(contains "$df_flat" "todo-format.md")" "yes"
check "decision-file: mentions the Decision Needed: field" \
  "$(contains "$df_flat" "Decision Needed:")" "yes"

# --- Edge cases: multiple open decisions are separate files; a
#     self-resolving decision still gets its Status line updated ---
check "decision-file: multiple open decisions are separate files, never one file with multiple questions" \
  "$(contains_ci "$df_flat" "separate files")" "yes"
check "decision-file: a self-resolving decision still gets its Status line updated, not deleted" \
  "$(contains_ci "$df_flat" "overtaken by events")" "yes"

# --- No plugin named ---
check "decision-file: no plugin named anywhere in the doc" \
  "$(first_plugin_named "$df_flat")" ""

# ===========================================================================
# B06 — setup-stamp.md
# ===========================================================================

# --- Hygiene ---
check "setup-stamp: contract comment removed from source" \
  "$(contains "$sp_raw" "Contract: B06")" "no"
check "setup-stamp: STUB marker removed" \
  "$(contains "$sp_doc" "STUB — NotImplemented")" "no"

# --- 1. Location: verbatim path expression + filename ---
check "setup-stamp: verbatim path expression \${CLAUDE_CONFIG_DIR:-\$HOME/.claude}" \
  "$(contains "$sp_flat" '${CLAUDE_CONFIG_DIR:-$HOME/.claude}')" "yes"
check "setup-stamp: filename clam-setup-stamps.json" \
  "$(contains "$sp_flat" "clam-setup-stamps.json")" "yes"
check "setup-stamp: shared by all stamping plugins" \
  "$(word_present "$sp_flat" "shared")" "yes"

# --- 2. The five stamp fields (backtick or JSON-quoted; avoids a false
#        PASS on generic prose words, notably "at") ---
check "setup-stamp: field 'plugin'" "$(field_present "$sp_flat" "plugin")" "yes"
check "setup-stamp: field 'version'" "$(field_present "$sp_flat" "version")" "yes"
check "setup-stamp: field 'scope'" "$(field_present "$sp_flat" "scope")" "yes"
check "setup-stamp: field 'target'" "$(field_present "$sp_flat" "target")" "yes"
check "setup-stamp: field 'at'" "$(field_present "$sp_flat" "at")" "yes"

# --- 3. Key: (plugin, target) ---
check "setup-stamp: key is (plugin, target)" \
  "$(contains "$sp_flat" "(plugin, target)")" "yes"
check "setup-stamp: re-running setup overwrites the existing stamp" \
  "$(word_present "$sp_flat" "overwrites")" "yes"
check "setup-stamp: remove/teardown deletes the stamp" \
  "$(word_present "$sp_flat" "teardown")" "yes"

# --- 4. Write discipline: atomic (jq + mv); stamp failure never fails setup ---
check "setup-stamp: builds the new document with jq" \
  "$(word_present "$sp_flat" "jq")" "yes"
check "setup-stamp: then mv over the original" \
  "$(word_present "$sp_flat" "mv")" "yes"
check "setup-stamp: write is atomic" \
  "$(word_present "$sp_flat" "atomic")" "yes"
check "setup-stamp: stamp-write failure never fails the triggering setup" \
  "$(contains_ci "$sp_flat" "never fails the setup")" "yes"
check "setup-stamp: stamps are advisory" \
  "$(word_present "$sp_flat" "advisory")" "yes"

# --- 5. Corruption handling ---
check "setup-stamp: corrupt file moved aside to a .corrupt-<date> sidestep" \
  "$(contains "$sp_flat" ".corrupt-")" "yes"
check "setup-stamp: corrupt file treated as empty" \
  "$(contains_ci "$sp_flat" "treated as empty")" "yes"

# --- 6. Absence semantics and staleness ---
check "setup-stamp: absence means setup state unknown" \
  "$(contains_ci "$sp_flat" "setup state unknown")" "yes"
check "setup-stamp: absence is never presented as needing setup" \
  "$(contains_ci "$sp_flat" "needs setup")" "yes"
check "setup-stamp: an older stamped version means setup may be stale" \
  "$(contains_ci "$sp_flat" "may be stale")" "yes"

# --- Edge cases: concurrent stamping is last-writer-wins; unknown extra
#     fields in a stamp entry are tolerated by readers ---
check "setup-stamp: concurrent stamping is last-writer-wins (acceptable for advisory data)" \
  "$(contains_ci "$sp_flat" "last-writer-wins")" "yes"
check "setup-stamp: unknown extra fields in a stamp entry are tolerated by readers" \
  "$(word_present "$sp_flat" "tolerated")" "yes"

# --- No plugin named; must not cite any plugins/<name>/ path ---
check "setup-stamp: no plugin named anywhere in the doc" \
  "$(first_plugin_named "$sp_flat")" ""
check "setup-stamp: does not cite any plugins/<name>/ path" \
  "$(contains "$sp_flat" "plugins/")" "no"

# --- 7. 'at' is measured when the stamp is written (B02) -------------------
# These read sp_body — sp_doc with B02's contract docblock and the scaffold's
# STUB bullet removed — not sp_doc/sp_flat. See the B02 note in the header:
# either one left in place would satisfy every clause here on its own words.
sp_body="$(drop_stub_blocks "$(strip_comment_block "$sp_doc" "Contract: B02")")"
sp_body_flat="$(flatten "$sp_body")"
sp_at_flat="$(flatten "$(at_bullet "$sp_body")")"

# --- Hygiene: B02's contract comment gone at acceptance ---
check "setup-stamp: B02 contract comment removed from source" \
  "$(contains "$sp_raw" "Contract: B02")" "no"

check "setup-stamp: names the command that produces 'at' (date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(contains "$sp_body_flat" 'date -u +%Y-%m-%dT%H:%M:%SZ')" "yes"
check "setup-stamp: the Shape section's 'at' bullet is where that command is named" \
  "$(contains "$sp_at_flat" 'date -u +%Y-%m-%dT%H:%M:%SZ')" "yes"
check "setup-stamp: 'at' is measured when the stamp is written, not merely a value shape" \
  "$(contains_any "$(lower "$sp_at_flat")" \
      "measured when the stamp is written" \
      "measured when the stamp was written" \
      "measured at the time the stamp is written" \
      "measured at the moment the stamp is written" \
      "records when the stamp is written" \
      "records when the stamp was written" \
      "recorded when the stamp is written" \
      "read the clock" "reads the clock" "from the clock")" "yes"
check "setup-stamp: 'at' is never invented, guessed, or copied from another record" \
  "$(contains_any "$(lower "$sp_body_flat")" \
      "never invented" "not invented" \
      "never guessed" "not guessed" \
      "never copied" "not copied")" "yes"

# ===========================================================================
# B07 — todo-format.md
# ===========================================================================

# --- Hygiene ---
check "todo-format: contract comment removed from source" \
  "$(contains "$tf_raw" "Contract: B07")" "no"
check "todo-format: STUB marker removed" \
  "$(contains "$tf_doc" "STUB — NotImplemented")" "no"

# --- 1. Location ---
check "todo-format: location .local/TODO.md at the worktree root" \
  "$(contains "$tf_flat" ".local/TODO.md")" "yes"
check "todo-format: gitignored, per-worktree session state" \
  "$(contains_ci "$tf_flat" "gitignored")" "yes"

# --- 2. Header lines ---
check "todo-format: header Branch: line" \
  "$(contains "$tf_flat" "Branch:")" "yes"
check "todo-format: header Started: line" \
  "$(contains "$tf_flat" "Started:")" "yes"
check "todo-format: header Last Updated: line" \
  "$(contains "$tf_flat" "Last Updated:")" "yes"

# --- 3. ## Status section fields ---
check "todo-format: State: field (vocabulary by reference)" \
  "$(contains "$tf_flat" "State:")" "yes"
check "todo-format: Current Task: field" \
  "$(contains "$tf_flat" "Current Task:")" "yes"
check "todo-format: Blocked Reason: field (populated iff State is Blocked)" \
  "$(contains "$tf_flat" "Blocked Reason:")" "yes"
check "todo-format: Decision Needed: field (populated iff Waiting For Decision)" \
  "$(contains "$tf_flat" "Decision Needed:")" "yes"

# --- 4. Eight required sections, in order ---
TF_SECTIONS=(
  "## Status" "## Tasks" "## Testing" "## Pre-PR" "## Implementation Log"
  "## Blockers/Notes" "## Open Questions" "## Discovered Tasks"
)
for s in "${TF_SECTIONS[@]}"; do
  check "todo-format: section '$s' present" \
    "$(contains "$tf_flat" "$s")" "yes"
done
check "todo-format: eight required sections in order" \
  "$(in_order "$tf_flat" "${TF_SECTIONS[@]}")" "yes"

# --- 5. State vocabulary by reference only, never restated ---
check "todo-format: references session-states.md for the state vocabulary" \
  "$(contains "$tf_flat" "session-states.md")" "yes"
check "todo-format: does not restate the full state table ('Awaiting Merge Queue' absent)" \
  "$(contains "$tf_flat" "Awaiting Merge Queue")" "no"

# --- 6. Decision Needed cross-reference ---
check "todo-format: Decision Needed: cross-references decision-file.md" \
  "$(contains "$tf_flat" "decision-file.md")" "yes"

# --- 7. Real-time discipline ---
check "todo-format: state written as it changes, not at session end" \
  "$(contains_ci "$tf_flat" "not at session end")" "yes"
check "todo-format: document survives compaction and session restarts" \
  "$(word_present "$tf_flat" "compaction")" "yes"
check "todo-format: single source of truth, resumable from the file alone" \
  "$(contains_ci "$tf_flat" "single source of truth")" "yes"

# --- Edge cases: empty-valued fields stay present, never deleted; extra
#     repo-specific sections may follow the required eight but never
#     reorder/replace them ---
check "todo-format: empty-valued fields (e.g. Blocked Reason: with nothing after the colon) stay present, never deleted" \
  "$(contains_ci "$tf_flat" "never deleted")" "yes"
check "todo-format: extra repo-specific sections may follow the required eight, never reorder/replace them" \
  "$(word_present "$tf_flat" "reorder")" "yes"

# --- No plugin named ---
check "todo-format: no plugin named anywhere in the doc" \
  "$(first_plugin_named "$tf_flat")" ""

# ===========================================================================
echo "----"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "FAILURES"
fi
exit "$FAILED"
