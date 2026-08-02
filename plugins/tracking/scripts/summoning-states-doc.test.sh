#!/bin/bash
# Tests for B03 state-doc-consistency: plugins/tracking/README.md's
# notifications-plugin bullet must name all three states that summon the
# user (per lib/states.tsv's summons column and docs/protocols/
# session-states.md), not just two. The "Contract: B03 state-doc-consistency
# (remove at acceptance)" HTML comment above that bullet in README.md is the
# source of truth.
#
# Comment-stripped inputs: README.md is read through a `sed '/<!--/,/-->/d'`
# pass (the technique followups-docs.test.sh uses, and this file's own
# house pattern to follow per the brief) before any content check. The
# contract comment itself restates every clause the prose must deliver
# ("Blocked", "Waiting For Decision", "Awaiting User Review" all appear
# inside it) — without stripping, every assertion below would trivially
# match the CONTRACT COMMENT rather than the delivered prose, passing for
# the wrong reason.
#
# Hermetic: reads only files at fixed repo locations (resolved from this
# script's own path) into a mktemp scratch dir. No network, no gh.
#
# Run: bash plugins/tracking/scripts/summoning-states-doc.test.sh
#      (exits non-zero on failure)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

README="$PLUGIN_ROOT/README.md"
STATES_TSV="$PLUGIN_ROOT/lib/states.tsv"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1 — $2"; FAILED=1; }
check() { # label got expected
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got '$2', expected '$3'"; fi
}

for f in "$README" "$STATES_TSV"; do
    if [ ! -f "$f" ]; then
        fail "required file exists" "not found at $f"
        echo ""
        echo "Some tests FAILED."
        exit 1
    fi
done

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Comment-stripped copy — see file header for why this matters.
STRIPPED_README="$TMPROOT/README.stripped.md"
sed '/<!--/,/-->/d' "$README" > "$STRIPPED_README"
README_CONTENT=$(cat "$STRIPPED_README")

# assert_contains <label> <haystack> <literal-needle>
assert_contains() {
    if printf '%s' "$2" | grep -qF -- "$3"; then
        pass "$1"
    else
        fail "$1" "did not contain: $3"
    fi
}

# assert_not_contains_re_i <label> <haystack> <ERE> (case-insensitive)
assert_not_contains_re_i() {
    if printf '%s' "$2" | grep -qiE -- "$3"; then
        fail "$1" "unexpectedly matched regex (case-insensitive): $3"
    else
        pass "$1"
    fi
}

# bullet_zone <file> <ERE anchoring the bullet's own line>
# Echoes one top-level "- **Foo**..." bullet's full text, from its own
# line through the line before the next top-level "- " bullet or the next
# heading (## / ###), whichever comes first. Same technique as
# followups-docs.test.sh's bullet_zone().
bullet_zone() {
    local file="$1" start_re="$2" start next
    start=$(grep -nE -- "$start_re" "$file" | head -n1 | cut -d: -f1)
    [ -z "$start" ] && return 1
    next=$(awk -v s="$start" 'NR>s && ($0 ~ /^- / || $0 ~ /^## / || $0 ~ /^### /) {print NR; exit}' "$file")
    if [ -z "$next" ]; then
        sed -n "${start},\$p" "$file"
    else
        sed -n "${start},$((next-1))p" "$file"
    fi
}

# ===========================================================================
# Clause: the notifications bullet names all three summoning states.
# Derived from lib/states.tsv's summons column rather than hardcoded, so the
# two stop drifting apart — kept to a plain containment check per file, not
# a full parser, per the brief's steer.
# ===========================================================================

notifications_bullet=$(bullet_zone "$STRIPPED_README" '^- \*\*notifications plugin\*\* ')  # architecture-lint: allow guards the shrink-only baseline entry for this english reference in README.md; the literal wording is what this test locates
check "'- **notifications plugin**' bullet is present" "$([ -n "$notifications_bullet" ] && echo yes || echo no)" "yes"  # architecture-lint: allow guards the shrink-only baseline entry for this english reference in README.md; removing the wording here would defeat the guard

# Flattened/whitespace-collapsed: the bullet hard-wraps some multi-word
# state names across a line break (e.g. "Waiting For\n  Decision"), which a
# literal single-space match would otherwise false-fail on.
notifications_bullet_flat=$(printf '%s' "$notifications_bullet" | tr '\n' ' ' | tr -s '[:space:]' ' ')

summoning_states=$(awk -F'\t' '$0 !~ /^#/ && NF >= 5 && $NF == "yes" {print $1}' "$STATES_TSV")
summoning_count=$(printf '%s\n' "$summoning_states" | grep -c .)
check "lib/states.tsv marks exactly 3 states summons=yes" "$summoning_count" "3"

while IFS= read -r state; do
    [ -n "$state" ] || continue
    assert_contains "notifications bullet names summoning state '$state' (derived from lib/states.tsv)" \
        "$notifications_bullet_flat" "$state"
done <<STATES_EOF
$summoning_states
STATES_EOF

# ===========================================================================
# Clause: the words "notifications plugin" remain (architecture-lint: allow guards the shrink-only baseline entry for this english reference in README.md), and the
# other cross-plugin references this file's architecture-lint baseline
# covers (decision-log, notifications, statusline) are left alone — that
# baseline is shrink-only.
# ===========================================================================

assert_contains "'notifications plugin' wording remains" "$README_CONTENT" "notifications plugin"  # architecture-lint: allow guards the shrink-only baseline entry for this english reference in README.md; removing the wording here would defeat the guard
assert_contains "'decision-log' cross-plugin reference remains" "$README_CONTENT" "decision-log"
assert_contains "'statusline' cross-plugin reference remains" "$README_CONTENT" "statusline"

# ===========================================================================
# Clause: no forge vocabulary introduced. Scoped to the notifications
# bullet itself (not the whole file) — README.md legitimately mentions PRs
# elsewhere (the pr-workflow/independent-review integration bullets further
# down), and this clause is about not introducing NEW forge vocabulary into
# the bullet being corrected, not scrubbing the whole document.
# ===========================================================================

assert_not_contains_re_i "notifications bullet: no 'pull request' introduced" "$notifications_bullet_flat" '\bpull request\b'
assert_not_contains_re_i "notifications bullet: no 'merge request' introduced" "$notifications_bullet_flat" '\bmerge request\b'
assert_not_contains_re_i "notifications bullet: no 'draft' introduced" "$notifications_bullet_flat" '\bdraft\b'
assert_not_contains_re_i "notifications bullet: no 'gh' (whole word) introduced" "$notifications_bullet_flat" '\bgh\b'

# ===========================================================================
# Clause (acceptance hygiene): the "Contract: B03" marker is absent from the
# RAW (unstripped) file. This FAILS now — the comment is still present — and
# is expected to start passing only once the implementation wave deletes it.
# ===========================================================================

if grep -qF "Contract: B03" "$README"; then
    fail "acceptance hygiene: 'Contract: B03' comment removed from README.md" "still present (expected until acceptance)"
else
    pass "acceptance hygiene: 'Contract: B03' comment removed from README.md"
fi

# Note: README.md's earlier mention of "Awaiting User Review" as an example
# parked state (in the "What to expect" section) is correct as it stands and
# is not this block's subject — deliberately no assertion on it here, so
# this test suite can never force it to change.

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit "$FAILED"
