#!/bin/bash
# Tests for the two prose contracts of plan 001-render-graph-always that
# live in this plugin's realm:
#
#   B09 workgraph-live-serve rule — the "Contract: B09 workgraph-live-serve
#       rule" docblock above the B03 block in session-context.sh (the
#       runtime surface) plus the "Contract: B09 workgraph-live-serve rule
#       — README section" HTML comment in plugins/tracking/README.md, and
#       the 0.7.2 -> 0.8.0 plugin.json bump they land with.
#   B10 protocol-viewing-note — the leading "Contract: B10
#       protocol-viewing-note" HTML comment atop docs/protocols/work-graph.md.
#
# Those docblocks are the source of truth; this file verifies them, it does
# not restate them.
#
# ---------------------------------------------------------------------------
# Why the haystacks are scoped the way they are
# ---------------------------------------------------------------------------
# All three contract docblocks contain, verbatim, most of the phrases these
# tests must find in the real body — "live-updating HTML view", "without
# opening a browser", "URL", "skipped silently", "an installed rendering
# capability", "0.8.0". An unscoped grep would therefore pass against the
# SCAFFOLDING COMMENT on the still-unimplemented stub and destroy the red
# run. Each of the three surfaces is scoped differently, because each sits
# differently relative to its comment:
#
#   - session-context.sh (B09 runtime): assertions read the hook's STDOUT —
#     the decoded SessionStart additionalContext — never the script source.
#     Shell comments cannot reach stdout, so this surface is scope-safe by
#     construction. It is narrowed further to the WORK-GRAPH PARAGRAPH ZONE
#     (the text from "When a problem genuinely decomposes into subproblems"
#     up to, but excluding, "State lifecycle"), because the surrounding
#     rules already contain several of the shared vocabulary words and,
#     more importantly, a legitimate decision-log skill invocation (in the
#     Waiting-For-Decision rule) that the capability-phrasing negative
#     checks below must not see.
#
#   - plugins/tracking/README.md (B09 docs): read through a
#     `sed '/<!--/,/-->/d'` comment-stripping pass, the technique
#     workgraph-docs.test.sh and followups-docs.test.sh already use for
#     this exact file. NOT the "content strictly after the leading
#     comment's first -->" technique workgraph-template.test.sh uses for
#     the protocol/template documents: the B09 comment is MID-FILE and sits
#     BELOW the `.local/WORKGRAPH.md` bullet it describes, so a
#     scope-past-the-comment read would exclude the very bullet under test.
#     Comment-stripping achieves the same goal (the scaffolding comment
#     cannot satisfy any assertion) while keeping the target bullet in the
#     haystack. This file is the only HTML comment in that README today, so
#     the pass is exact both before and after acceptance.
#
#   - docs/protocols/work-graph.md (B10): B10's comment IS leading, so this
#     surface uses workgraph-template.test.sh's own technique verbatim —
#     content strictly after the leading comment's first '-->', falling back
#     to the whole file once the comment is deleted at acceptance.
#
# ---------------------------------------------------------------------------
# Non-vacuous anchors
# ---------------------------------------------------------------------------
# Several phrases the contracts require are ALREADY present in the
# unimplemented bodies and would pass vacuously on their own:
#   - the work-graph rules paragraph already says "created", "moment",
#     "real time", "render", "Focus", "Goal/Parent/Deps";
#   - work-graph.md's "## Viewing" paragraph already says "document of
#     record" and "derived and disposable" of the ASCII tree.
# Every assertion below that involves one of those words pairs it with a
# token that is genuinely absent from the stub ("serve", "live", "HTML",
# "browser", "URL", "catalog", "silent", "updat", "installed",
# "capability"), so it can only go green on real implemented prose.
#
# ---------------------------------------------------------------------------
# Capability phrasing: what counts as naming a plugin
# ---------------------------------------------------------------------------
# Both contracts forbid naming a plugin. This file uses the repository's own
# definition of a reference (CLAUDE.md's table, and the four forms
# scripts/architecture-lint.sh actually matches): skill invocation,
# marketplace id, English "<name> plugin", and a `plugins/<name>/` path.
# Those four are checked for EVERY plugin directory name.
#
# On top of that, names with no ordinary-English sense (render-doc, lego,
# statusline, ...) are banned as BARE WORDS too — in a sentence about
# serving a document, a bare "render-doc" is a naming however it is
# punctuated. Names that collide with ordinary vocabulary (build, landing,
# management, settings, tracking, worktrees — CLAUDE.md warns about exactly
# this) are checked in the four reference forms ONLY, so correct prose that
# happens to say "the build" or "this worktree's" cannot fail.
#
# The forbidden patterns are COMPOSED AT RUNTIME from the bare name array
# rather than written out literally, so that this file does not itself
# contain a `plugins/<other>/` path or a `/<other>:<verb>` invocation and
# grow a new architecture-lint baseline entry.
#
# The zone is read with $PLUGIN_ROOT substituted out before any absence
# check: the rules paragraph legitimately interpolates an absolute path to
# this plugin's template, which would otherwise register as a
# `plugins/tracking/` self-reference and, worse, drag the checkout's own
# directory name into the haystack.
#
# ---------------------------------------------------------------------------
# Explicitly NOT asserted here (documented rather than silently skipped)
# ---------------------------------------------------------------------------
#   - B09 Invariant "Existing session-context tests remain green" is a
#     cross-suite property, verified by session-context.test.sh,
#     workgraph-capture.test.sh, workgraph-gate.test.sh and
#     workgraph-lifecycle.test.sh running in the same `bash scripts/ci.sh
#     --test` sweep. Re-running them from inside this file would duplicate
#     several seconds of work for no new signal.
#   - B09 Invariant "the repo-wide architecture lint stays green" is
#     `scripts/architecture-lint.sh`'s job in `ci.sh --lint`; it takes ~27s
#     on this repo, so embedding it in a test file would be a serious
#     runtime regression against plan 001-speed-up-repo-ci's targets.
#     Instead, the cheap and precise half of that invariant is asserted
#     directly: the SET of plugin-reference forms present in
#     session-context.sh must stay exactly what it is today (one baselined
#     `decision-log` skill invocation in the Waiting-For-Decision rule,
#     architecture-lint-baseline.txt line 114). Any reference B09's addition
#     introduces changes that set and goes red here, immediately, without
#     waiting for the lint.
#   - B10 has no Inputs/Outputs/Errors and its Edge cases section is
#     "none — static prose"; there is nothing to assert for those.
#
# Hermetic: creates temp worktree fixtures under a mktemp root, feeds
# synthetic SessionStart hook JSON to session-context.sh, and otherwise
# reads three files at fixed repo locations (resolved from this script's own
# path). No mutation of tracked files, no network.
#
# Run: bash plugins/tracking/scripts/workgraph-live-view.test.sh
#      (exits non-zero on failure)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

HOOK="$SCRIPT_DIR/session-context.sh"
TRACKING_README="$PLUGIN_ROOT/README.md"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
ROOT_README="$REPO_ROOT/README.md"
PROTOCOL="$REPO_ROOT/docs/protocols/work-graph.md"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }
check() { # label got expected
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got '$2', expected '$3'"; fi
}

for f in "$HOOK" "$TRACKING_README" "$PLUGIN_JSON" "$ROOT_README" "$PROTOCOL"; do
    if [ ! -f "$f" ]; then
        fail "required file exists" "not found at $f"
        echo ""
        echo "FAILURES"
        exit 1
    fi
done

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# ---------------------------------------------------------------------------
# Assertion helpers
#
# LC_ALL=C throughout: glibc's regex engine takes a dramatically slower
# multibyte path for bounded-repetition EREs (the '.{0,150}' proximity
# patterns below) as soon as the haystack holds a multibyte character, and
# both the rules paragraph and the protocol document are full of em dashes.
# Every pattern here is plain ASCII, so byte-wise matching is equivalent.
# ---------------------------------------------------------------------------

# flat <text> -> the text with newlines folded to spaces, so a proximity
# regex whose halves land on different hard-wrapped source lines still
# matches (grep is per-physical-line by default).
flat() { printf '%s' "$1" | tr '\n' ' '; }

assert_contains_re_i() { # label haystack ERE
    if flat "$2" | LC_ALL=C grep -qiE -- "$3"; then
        pass "$1"
    else
        fail "$1" "did not match regex (case-insensitive): $3"
    fi
}

assert_absent_re_i() { # label haystack ERE
    if flat "$2" | LC_ALL=C grep -qiE -- "$3"; then
        fail "$1" "matched forbidden pattern (case-insensitive): $3"
    else
        pass "$1"
    fi
}

assert_contains_f() { # label haystack literal-needle
    if printf '%s' "$2" | LC_ALL=C grep -qF -- "$3"; then
        pass "$1"
    else
        fail "$1" "did not contain: $3"
    fi
}

# ---------------------------------------------------------------------------
# Plugin-name vocabulary and the four reference forms
# ---------------------------------------------------------------------------

# No ordinary-English sense: a bare occurrence is itself a naming.
STRICT_PLUGIN_NAMES=(ask-in-text attribution debugging decision-log lego \
    notifications orchestrator-handover privacy render-doc session-data \
    skill-tracker statusline voice)

# Word-sense collisions with ordinary vocabulary: checked in the four
# reference forms only (see the file header).
AMBIGUOUS_PLUGIN_NAMES=(build landing management settings tracking worktrees)

ALL_PLUGIN_NAMES=("${STRICT_PLUGIN_NAMES[@]}" "${AMBIGUOUS_PLUGIN_NAMES[@]}")

# plugin_ref_forms <haystack> [<self-name-to-skip>]
# Prints one "form:name" line per distinct plugin reference found, sorted
# and de-duplicated. The four forms mirror scripts/architecture-lint.sh:
# skill invocation, marketplace id, English "<name> plugin", and a
# plugins/<name>/ path. Patterns are composed from the name array so this
# file never contains a literal cross-plugin reference of its own.
#
# One combined grep per name gates the four labelled greps, which then run
# only for the (rare) name that actually hit. The haystacks here include a
# whole 28KB script, so the naive 4-greps-per-name shape would spawn ~80
# processes per call for a result that is almost always empty.
plugin_ref_forms() { # haystack [self]
    local hay self name
    hay=$(flat "$1")
    self="${2:-}"
    {
        for name in "${ALL_PLUGIN_NAMES[@]}"; do
            [ "$name" = "$self" ] && continue
            printf '%s' "$hay" | LC_ALL=C grep -qiE -- \
                "/${name}:[A-Za-z0-9_-]+|(^|[^A-Za-z0-9-])${name}(@clam|[[:space:]]+plugin)|plugins/${name}([^A-Za-z0-9-]|$)" \
                || continue
            printf '%s' "$hay" | LC_ALL=C grep -qiE -- "/${name}:[A-Za-z0-9_-]+" \
                && echo "skill-invocation:$name"
            printf '%s' "$hay" | LC_ALL=C grep -qiE -- "(^|[^A-Za-z0-9-])${name}@clam" \
                && echo "marketplace-id:$name"
            printf '%s' "$hay" | LC_ALL=C grep -qiE -- "(^|[^A-Za-z0-9-])${name}[[:space:]]+plugin" \
                && echo "english:$name"
            printf '%s' "$hay" | LC_ALL=C grep -qiE -- "plugins/${name}([^A-Za-z0-9-]|$)" \
                && echo "path:$name"
        done
    } | sort -u
}

# plugin_bare_names <haystack> -> the strict-list names present as bare
# words, sorted and de-duplicated. One grep over the whole alternation, with
# the guard characters stripped back off each match.
STRICT_NAME_ALT=$(IFS='|'; printf '%s' "${STRICT_PLUGIN_NAMES[*]}")
plugin_bare_names() { # haystack
    flat "$1" \
        | LC_ALL=C grep -oiE -- "(^|[^A-Za-z0-9-])(${STRICT_NAME_ALT})([^A-Za-z0-9-]|$)" \
        | LC_ALL=C sed -E 's/^[^A-Za-z0-9]//; s/[^A-Za-z0-9]$//' \
        | sort -u
}

# assert_names_no_plugin <label-prefix> <haystack>
# Both halves of the capability-phrasing invariant, as two checks.
assert_names_no_plugin() { # label-prefix haystack
    local bare forms
    bare=$(plugin_bare_names "$2")
    if [ -z "$bare" ]; then
        pass "$1: names no plugin as a bare word"
    else
        fail "$1: names no plugin as a bare word" "found: $(flat "$bare")"
    fi
    forms=$(plugin_ref_forms "$2")
    if [ -z "$forms" ]; then
        pass "$1: contains no plugin reference in any of the four reference forms"
    else
        fail "$1: contains no plugin reference in any of the four reference forms" \
            "found: $(flat "$forms")"
    fi
}

# assert_no_implementation_details <label-prefix> <haystack>
# The remaining three bans the contracts state alongside "no plugin": no
# skill id, no fixed port, no URL shape. The skill-id pattern is generic
# (any `/<word>:<word>`), which is the real invariant — a skill id from
# outside the current plugin vocabulary would be just as much of a naming.
assert_no_implementation_details() { # label-prefix haystack
    assert_absent_re_i "$1: names no skill id" "$2" \
        '(^|[^A-Za-z0-9_-])/[a-z][a-z0-9-]*:[a-z][a-z0-9-]+'
    assert_absent_re_i "$1: names no fixed port (27183)" "$2" '27183'
    assert_absent_re_i "$1: names no host:port shape" "$2" ':[0-9]{2,5}([^0-9]|$)'
    assert_absent_re_i "$1: names no bare port-like number" "$2" '(^|[^0-9])[0-9]{4,5}([^0-9]|$)'
    assert_absent_re_i "$1: names no URL scheme" "$2" 'https?://'
    assert_absent_re_i "$1: names no loopback host" "$2" 'localhost|127\.0\.0\.1|0\.0\.0\.0'
}

# ===========================================================================
# B09 — runtime surface: the injected work-graph rules paragraph
# ===========================================================================

hook_json() { # cwd
    printf '{"cwd":"%s","hook_event_name":"SessionStart","session_id":"test-sid"}' "$1"
}

ctx_for() { # cwd -> decoded additionalContext
    printf '%s' "$(hook_json "$1")" | bash "$HOOK" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null
}

# workgraph_zone <ctx> -> the work-graph paragraph, from its contracted
# opening line up to (excluding) the "State lifecycle" paragraph that
# follows it. Everything B09 adds belongs inside this span; nothing outside
# it is B09's business.
# shellcheck disable=SC2016
ZONE_START_ANCHOR='Create `.local/WORKGRAPH.md` from the template at'
workgraph_zone() { # ctx
    printf '%s\n' "$1" | awk -v start="$ZONE_START_ANCHOR" \
        'index($0, start) == 1 { f = 1 } f && /^State lifecycle/ { exit } f'
}

# Three fixtures covering the Inputs clause ("none new — static text"): no
# .local/ at all, a .local/ without a work graph, and a .local/ with one.
WD_BARE="$TMPROOT/b09-bare"
WD_LOCAL="$TMPROOT/b09-local"
WD_GRAPH="$TMPROOT/b09-graph"
mkdir -p "$WD_BARE" "$WD_LOCAL/.local" "$WD_GRAPH/.local"
cat > "$WD_GRAPH/.local/WORKGRAPH.md" <<'EOF'
# Work Graph

Focus: N01

## N01 — An open node
- Goal: exists so the surfacing block renders
- Status: open
- Parent: none
- Deps: none
EOF

CTX_BARE=$(ctx_for "$WD_BARE")
CTX_LOCAL=$(ctx_for "$WD_LOCAL")
CTX_GRAPH=$(ctx_for "$WD_GRAPH")

ZONE=$(workgraph_zone "$CTX_BARE")

check "B09: the work-graph rules paragraph is present in the injected context" \
    "$([ -n "$ZONE" ] && echo yes || echo no)" "yes"

if [ -z "$ZONE" ]; then
    fail "B09: rules-paragraph assertions can run" \
        "the '$ZONE_START_ANCHOR' anchor is gone — B03's paragraph was rewritten, which B09's Invariants forbid"
    echo ""
    echo "FAILURES"
    exit 1
fi

# The absolute template path is substituted out before any absence check —
# see the file header. ZONE_TEXT keeps it for the presence checks.
ZONE_TEXT="$ZONE"
ZONE_SCAN=${ZONE//"$PLUGIN_ROOT"/<PLUGIN_ROOT>}

# --- Behavior: the serve-at-creation instruction --------------------------

assert_contains_re_i "B09 Behavior: the trigger is WORKGRAPH.md's creation, tied to serving it" \
    "$ZONE_TEXT" 'creat.{0,160}(serv|live view|html)|(serv|live view|html).{0,160}creat'
assert_contains_re_i "B09 Behavior: what is consulted is the skill catalog" \
    "$ZONE_TEXT" 'catalog'
assert_contains_re_i "B09 Behavior: what is looked for in it is a skill" \
    "$ZONE_TEXT" '(^|[^a-z])skills?([^a-z]|$)'
assert_contains_re_i "B09 Behavior: the capability sought is serving the document" \
    "$ZONE_TEXT" 'serv.{0,140}(WORKGRAPH\.md|markdown|document)|(WORKGRAPH\.md|markdown|document).{0,140}serv'
assert_contains_re_i "B09 Behavior: the served view is HTML" \
    "$ZONE_TEXT" '(^|[^a-z])html([^a-z]|$)'
assert_contains_re_i "B09 Behavior: the view is live and self-updating" \
    "$ZONE_TEXT" 'live.{0,60}updat|updat.{0,60}live'
assert_contains_re_i "B09 Behavior: no browser is opened" \
    "$ZONE_TEXT" '(without|not|no|never).{0,60}browser|browser.{0,60}(without|not|no|never)'
assert_contains_re_i "B09 Behavior: it is .local/WORKGRAPH.md that gets served" \
    "$ZONE_TEXT" 'serv.{0,120}WORKGRAPH\.md|WORKGRAPH\.md.{0,120}serv'
assert_contains_re_i "B09 Behavior: the resulting URL is told to the engineer" \
    "$ZONE_TEXT" '(^|[^a-z])urls?([^a-z]|$)'
assert_contains_re_i "B09 Behavior: the URL is surfaced once, not repeatedly" \
    "$ZONE_TEXT" 'url.{0,100}once|once.{0,100}url'
assert_contains_re_i "B09 Behavior: the served URL is recorded in TODO.md as a Live view line" \
    "$ZONE_TEXT" 'Live view:.{0,40}url|Live view: <url>'
assert_contains_re_i "B09 Behavior: when nothing offers the capability, Live view: none is recorded and work moves on" \
    "$ZONE_TEXT" 'Live view: none'
assert_contains_re_i "B09 Behavior: the absence is never surfaced as an error or complaint" \
    "$ZONE_TEXT" 'no error|no.{0,40}mention'

# --- Edge cases -----------------------------------------------------------

assert_contains_re_i "B09 Edge case: the catalog is consulted at creation time, against whatever it then offers" \
    "$ZONE_TEXT" 'catalog.{0,200}creat|creat.{0,200}catalog'
assert_contains_re_i "B09 Edge case: a failed serve never blocks the graph itself" \
    "$ZONE_TEXT" '(never|not|no).{0,80}block|block.{0,80}(never|not|no)'

# --- Invariants: capability phrasing --------------------------------------

assert_names_no_plugin "B09 Invariant: the rules paragraph" "$ZONE_SCAN"
assert_no_implementation_details "B09 Invariant: the rules paragraph" "$ZONE_SCAN"

# --- Invariants: every existing B03 rule survives the edit ----------------

assert_contains_f "B09 Invariant: B03's .local/WORKGRAPH.md file name survives" \
    "$ZONE_TEXT" '.local/WORKGRAPH.md'
assert_contains_f "B09 Invariant: B03's template path survives" \
    "$ZONE_TEXT" "$PLUGIN_ROOT/templates/WORKGRAPH.md"
assert_contains_re_i "B09 Invariant: B03's eager-creation rule survives" \
    "$ZONE_TEXT" 'start of tracked work|eagerly'
assert_contains_re_i "B09 Invariant: B03's node-in-the-same-turn rule survives" \
    "$ZONE_TEXT" 'graph node.{0,200}same turn|same turn.{0,200}graph node'
assert_contains_re_i "B09 Invariant: B03's per-node Goal/Parent/Deps fields survive" \
    "$ZONE_TEXT" 'goal.{0,120}parent.{0,120}deps'
assert_contains_re_i "B09 Invariant: B03's real-time Focus discipline survives" \
    "$ZONE_TEXT" 'focus.{0,120}real[- ]time|real[- ]time.{0,120}focus'
assert_contains_re_i "B09 Invariant: B03's Current Task citation survives" \
    "$ZONE_TEXT" 'focus.{0,160}current task|current task.{0,160}focus'
assert_contains_re_i "B09 Invariant: B03's disposition-not-delete rule survives" \
    "$ZONE_TEXT" 'dropped.{0,200}(rather than|never|not).{0,40}delet'
assert_contains_re_i "B09 Invariant: B03's ASCII-tree render-on-request clause survives" \
    "$ZONE_TEXT" 'ascii.{0,40}tree'
assert_contains_f "B09 Invariant: B03's [needs: N<NN>] dep annotation survives" \
    "$ZONE_TEXT" '[needs:'
assert_contains_re_i "B09 Invariant: B03's status glyph and Focus arrow survive" \
    "$ZONE_TEXT" 'glyph.{0,120}arrow|arrow.{0,120}glyph'

# --- Invariant: no plugin reference anywhere in session-context.sh --------
#
# The file must carry zero plugin references. The former decision-log skill
# invocation in the Waiting-For-Decision rule was removed (#403).
sc_refs=$(plugin_ref_forms "$(cat "$HOOK")" "tracking")
check "B09 Invariant: session-context.sh carries no plugin references" \
    "$(flat "$sc_refs")" ""

# --- Inputs / Outputs / Errors --------------------------------------------
#
# Inputs: "none new — the addition is static text inside the existing rules
# heredoc". So the paragraph must be byte-identical across a worktree with
# no .local/, one with an empty .local/, and one with a work graph already
# on disk.

ZONE_LOCAL=$(workgraph_zone "$CTX_LOCAL")
ZONE_GRAPH=$(workgraph_zone "$CTX_GRAPH")
check "B09 Inputs: the paragraph is identical with no .local/ and with an empty .local/" \
    "$([ "$ZONE_TEXT" = "$ZONE_LOCAL" ] && echo same || echo different)" "same"
check "B09 Inputs: the paragraph is identical whether or not a work graph exists on disk" \
    "$([ "$ZONE_TEXT" = "$ZONE_GRAPH" ] && echo same || echo different)" "same"

# Errors: "none — static text; the script's fail-open posture is untouched."
printf '%s' "$(hook_json "$WD_BARE")" | bash "$HOOK" >/dev/null 2>&1
check "B09 Errors: the hook still exits 0 on a worktree with no .local/" "$?" "0"

raw_out=$(printf '%s' "$(hook_json "$WD_GRAPH")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$raw_out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    pass "B09 Errors: the hook still emits well-formed hook JSON"
else
    fail "B09 Errors: the hook still emits well-formed hook JSON" "output was: $raw_out"
fi

# Edge case: "no WORKGRAPH.md ever created (the instruction never fires)" —
# the rule is injected regardless, and the hook still never creates the file.
assert_contains_re_i "B09 Edge case: the instruction is injected even where no work graph exists" \
    "$ZONE_LOCAL" 'serv'
check "B09 Edge case: the hook still creates no WORKGRAPH.md of its own" \
    "$([ -f "$WD_LOCAL/.local/WORKGRAPH.md" ] && echo created || echo absent)" "absent"

# ===========================================================================
# B09 — documentation surface: the .local/WORKGRAPH.md README bullet
# ===========================================================================

STRIPPED_README="$TMPROOT/tracking-README.stripped.md"
sed '/<!--/,/-->/d' "$TRACKING_README" > "$STRIPPED_README"

# bullet_zone <file> <ERE anchoring the bullet's own line> — one top-level
# "- **Foo**..." bullet, from its own line through the line before the next
# top-level bullet or heading. Same helper workgraph-docs.test.sh uses; a
# whole-section scan would be unsafe here because sibling bullets in "## What
# to expect" already use words this contract's new sentences also use.
bullet_zone() { # file start_re
    local file="$1" start_re="$2" start next
    start=$(LC_ALL=C grep -nE -- "$start_re" "$file" | head -n1 | cut -d: -f1)
    [ -z "$start" ] && return 1
    next=$(awk -v s="$start" 'NR>s && ($0 ~ /^- / || $0 ~ /^## / || $0 ~ /^### /) {print NR; exit}' "$file")
    if [ -z "$next" ]; then
        sed -n "${start},\$p" "$file"
    else
        sed -n "${start},$((next - 1))p" "$file"
    fi
}

# The regex matches literal markdown backticks; nothing should expand.
# shellcheck disable=SC2016
WG_BULLET_RE='^- \*\*`\.local/WORKGRAPH\.md`\*\*'
wg_bullet=$(bullet_zone "$STRIPPED_README" "$WG_BULLET_RE")
check "B09 README: the .local/WORKGRAPH.md bullet exists in '## What to expect'" \
    "$([ -n "$wg_bullet" ] && echo yes || echo no)" "yes"

assert_contains_re_i "B09 README: the bullet describes serving the graph as a view" \
    "$wg_bullet" 'serv'
assert_contains_re_i "B09 README: the served view is HTML" \
    "$wg_bullet" '(^|[^a-z])html([^a-z]|$)'
assert_contains_re_i "B09 README: the view is live and self-updating" \
    "$wg_bullet" 'live.{0,60}updat|updat.{0,60}live'
assert_contains_re_i "B09 README: no browser is opened" \
    "$wg_bullet" '(without|not|no|never).{0,60}browser|browser.{0,60}(without|not|no|never)'
assert_contains_re_i "B09 README: serving happens at creation" \
    "$wg_bullet" 'creat.{0,160}(serv|live|html)|(serv|live|html).{0,160}creat'
assert_contains_re_i "B09 README: the capability comes from the skill catalog" \
    "$wg_bullet" 'catalog'
assert_contains_re_i "B09 README: the engineer is told the URL once" \
    "$wg_bullet" 'url.{0,100}once|once.{0,100}url'
assert_contains_re_i "B09 README: with no such skill installed it is skipped silently" \
    "$wg_bullet" 'silent'

# Invariant: "the bullet's existing claims (lazy creation, protocol
# reference, gates) stand".
assert_contains_re_i "B09 README Invariant: the bullet says creation at the start of tracked work" \
    "$wg_bullet" 'start of tracked work|eager'
assert_contains_re_i "B09 README Invariant: the bullet still names the protocol document" \
    "$wg_bullet" 'docs/protocols/work-graph\.md'
assert_contains_re_i "B09 README Invariant: the bullet still names templates/WORKGRAPH.md" \
    "$wg_bullet" 'templates/WORKGRAPH\.md'
assert_contains_re_i "B09 README Invariant: the bullet still says no hook creates it" \
    "$wg_bullet" '(never|not|no).{0,60}hook|hook.{0,60}(never|not|no)'
assert_contains_re_i "B09 README Invariant: the bullet still names the CLAM_WORKGRAPH_GATE escape hatch" \
    "$wg_bullet" 'CLAM_WORKGRAPH_GATE'
assert_contains_re_i "B09 README Invariant: the bullet still names the Focus pointer and node fields" \
    "$wg_bullet" 'focus.{0,200}(goal|status|parent|deps)|(goal|status|parent|deps).{0,200}focus'

# Invariant: "this README names no other plugin, no port, no URL shape",
# scoped to the bullet B09 edits. The README as a whole legitimately names
# siblings elsewhere (three such lines are baselined for it), which is why
# this is bullet-scoped rather than file-scoped.
assert_names_no_plugin "B09 README Invariant: the WORKGRAPH.md bullet" "$wg_bullet"
assert_no_implementation_details "B09 README Invariant: the WORKGRAPH.md bullet" "$wg_bullet"

# Acceptance: the scaffolding comment is gone (checked on the RAW file).
if LC_ALL=C grep -qF -- "Contract: B09" "$TRACKING_README" 2>/dev/null; then
    fail "B09 acceptance: the 'Contract: B09' scaffolding HTML comment has been removed" "still present"
else
    pass "B09 acceptance: the 'Contract: B09' scaffolding HTML comment has been removed"
fi

if LC_ALL=C grep -qF -- "Contract: B09" "$HOOK" 2>/dev/null; then
    fail "B09 acceptance: the 'Contract: B09' scaffolding docblock has been removed from session-context.sh" "still present"
else
    pass "B09 acceptance: the 'Contract: B09' scaffolding docblock has been removed from session-context.sh"
fi

# session-context.sh is deliberately excluded from this loop: it already
# contains the word "NotImplemented" twice, in B04's own docblock and an
# inline comment describing that block's exit-90 sentinel (plan
# 001-tracking-resume-freshness). Neither is a B09 scaffolding placeholder —
# B09's stub marks itself "DELIBERATELY UNIMPLEMENTED" in prose and plants no
# sentinel — so a blanket check on that file would be red forever through no
# fault of this contract.
for f in "$TRACKING_README" "$PLUGIN_JSON"; do
    label="B09 acceptance: no NotImplemented placeholder remains in $(basename "$f")"
    if LC_ALL=C grep -qF -- "NotImplemented" "$f" 2>/dev/null; then
        fail "$label" "still present in $f"
    else
        pass "$label"
    fi
done

# ===========================================================================
# B09 — version surface
#
# The bump is 0.7.2 -> 0.8.0. readme-lint's root-readme-version-lint pairs
# plugin.json's version with the root README Plugins-table cell, so the two
# move together or the lint (and workgraph-docs.test.sh's assertion that it
# passes) breaks. workgraph-docs.test.sh and followups-docs.test.sh carry
# the same two pins and are retargeted in lockstep — see their own notes.
#
# Both pins retargeted to 0.9.0 by 003-B21 (plan 003-followup-fixes), whose
# contract states the 0.8.0 -> 0.9.0 bump. The pins track the CURRENT
# version, so every legitimate bump retargets them; nothing about B09's own
# assertions changes.
# ===========================================================================

plugin_version=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
check "B09 version: tracking plugin.json is exactly 0.14.0" "$plugin_version" "0.14.0"

tracking_row=$(LC_ALL=C grep -E '^\| *\[tracking\]\(plugins/tracking/\) *\|' "$ROOT_README" | head -n1)
check "B09 version: the root README.md tracking row exists in the Plugins table" \
    "$([ -n "$tracking_row" ] && echo yes || echo no)" "yes"
assert_contains_re_i "B09 version: the root README.md tracking row's version cell is v0.14.0" \
    "$tracking_row" 'v0\.14\.0'

# ===========================================================================
# B10 — docs/protocols/work-graph.md "## Viewing"
# ===========================================================================

# Line number of the first '-->' (end of the leading contract comment), or
# empty once the comment is deleted at acceptance — the whole-file fallback
# workgraph-template.test.sh and followups-template.test.sh both use.
b10_comment_end=$(LC_ALL=C grep -n -- '-->' "$PROTOCOL" 2>/dev/null | head -n1 | cut -d: -f1)
b10_comment_end="${b10_comment_end:-0}"
B10_BODY=$(sed -n "$((b10_comment_end + 1)),\$p" "$PROTOCOL")

VIEWING=$(printf '%s\n' "$B10_BODY" | awk '/^## Viewing[[:space:]]*$/ { f = 1; next } f && /^## / { exit } f')
check "B10: the '## Viewing' section is present in the document body" \
    "$([ -n "$VIEWING" ] && echo yes || echo no)" "yes"

# "gains ONE short paragraph, placed after its existing ASCII-tree
# paragraph": the section holds exactly one paragraph today, so exactly two
# once B10 lands.
viewing_paras=$(printf '%s\n' "$VIEWING" | awk 'NF { if (!inp) { c++; inp = 1 } } !NF { inp = 0 } END { print c + 0 }')
check "B10 Behavior: the Viewing section gains exactly one paragraph (1 -> 2)" \
    "$viewing_paras" "2"

ascii_ln=$(printf '%s\n' "$VIEWING" | LC_ALL=C grep -niE 'ascii' | head -n1 | cut -d: -f1)
html_ln=$(printf '%s\n' "$VIEWING" | LC_ALL=C grep -niE '(^|[^a-z])html([^a-z]|$)' | head -n1 | cut -d: -f1)
if [ -n "$ascii_ln" ] && [ -n "$html_ln" ] && [ "$html_ln" -gt "$ascii_ln" ]; then
    pass "B10 Behavior: the new paragraph is placed after the existing ASCII-tree paragraph"
else
    fail "B10 Behavior: the new paragraph is placed after the existing ASCII-tree paragraph" \
        "ascii_ln='$ascii_ln', html_ln='$html_ln'"
fi

assert_contains_re_i "B10 Behavior: the new view is offered in addition to the on-request ASCII tree" \
    "$VIEWING" 'in addition|as well as|alongside|besides|on top of'
assert_contains_re_i "B10 Behavior: the provider is phrased as an installed capability" \
    "$VIEWING" 'installed.{0,80}(capabilit|render)|(capabilit|render).{0,80}installed'
assert_contains_re_i "B10 Behavior: that capability may serve the view" \
    "$VIEWING" 'serv'
assert_contains_re_i "B10 Behavior: the served view is HTML" \
    "$VIEWING" '(^|[^a-z])html([^a-z]|$)'
assert_contains_re_i "B10 Behavior: the view is live" \
    "$VIEWING" '(^|[^a-z])live([^a-z]|$)'
assert_contains_re_i "B10 Behavior: the view updates automatically" \
    "$VIEWING" 'automatic.{0,30}updat|updat.{0,30}automatic|auto-updating'
assert_contains_re_i "B10 Behavior: the view is of this document" \
    "$VIEWING" '(serv|html).{0,120}(this document|the markdown|this file)|(this document|the markdown|this file).{0,120}(serv|html)'

# The next two clauses are the ones the stub can already satisfy: the
# existing ASCII-tree paragraph ends with "The markdown file remains the
# document of record; rendered views are derived and disposable." Both
# assertions are therefore anchored on "serv", which is absent from the
# stub, so neither can pass vacuously.
assert_contains_re_i "B10 Behavior: the markdown stays the document of record even when a view is served" \
    "$VIEWING" 'serv.{0,250}document of record|document of record.{0,250}serv'
assert_contains_re_i "B10 Behavior: every served view stays derived and disposable" \
    "$VIEWING" 'serv.{0,250}dispos|dispos.{0,250}serv'

# --- Invariants -----------------------------------------------------------

assert_contains_re_i "B10 Invariant: the ASCII-tree convention is unchanged (rendered on request)" \
    "$VIEWING" 'on request'
assert_contains_re_i "B10 Invariant: the ASCII-tree convention is unchanged (indented ASCII tree)" \
    "$VIEWING" 'ascii.{0,40}tree'
assert_contains_re_i "B10 Invariant: the ASCII-tree convention is unchanged (children under parents)" \
    "$VIEWING" 'child.{0,80}parent|parent.{0,80}child'
assert_contains_f "B10 Invariant: the ASCII-tree convention is unchanged ([needs: N<NN>] annotations)" \
    "$VIEWING" '[needs: N<NN>]'
assert_contains_re_i "B10 Invariant: the ASCII-tree convention is unchanged (status glyph, Focus arrow)" \
    "$VIEWING" 'glyph.{0,120}arrow|arrow.{0,120}glyph'

# "the machine-read markers are untouched" — both regexes, still stated
# verbatim in the body (workgraph-template.test.sh pins these too; kept here
# so B10's own Invariants section has direct coverage in its own suite).
assert_contains_f "B10 Invariant: the Focus machine-read marker regex is stated verbatim" \
    "$(flat "$B10_BODY")" '^Focus: (N[0-9]+|none)[[:space:]]*$'
assert_contains_f "B10 Invariant: the Status-live machine-read marker regex is stated verbatim" \
    "$(flat "$B10_BODY")" '^- Status: (open|in progress)[[:space:]]*$'

# "this file continues to name no plugin ... the paragraph speaks of 'an
# installed rendering capability', never a name". Scoped to the Viewing
# section: the document-level disclaimer sentence elsewhere in the body
# legitimately contains the bare word "plugin" ("names no plugin"), which is
# workgraph-template.test.sh's B01 block's business, not this one's.
assert_names_no_plugin "B10 Invariant: the Viewing section" "$VIEWING"
assert_no_implementation_details "B10 Invariant: the Viewing section" "$VIEWING"

# Acceptance.
if LC_ALL=C grep -qF -- "Contract: B10" "$PROTOCOL" 2>/dev/null; then
    fail "B10 acceptance: the 'Contract: B10' scaffolding HTML comment has been removed" "still present"
else
    pass "B10 acceptance: the 'Contract: B10' scaffolding HTML comment has been removed"
fi

if LC_ALL=C grep -qF -- "NotImplemented" "$PROTOCOL" 2>/dev/null; then
    fail "B10 acceptance: no NotImplemented placeholder remains in work-graph.md" "still present"
else
    pass "B10 acceptance: no NotImplemented placeholder remains in work-graph.md"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES"
fi
exit "$FAILED"
