#!/bin/bash
# SessionStart hook for the tracking plugin. Four jobs:
#
# 1. Inject the Work Management rules (ported from clam-code's system-prompt
#    Work Management section) as additionalContext, so tracking-doc discipline
#    holds without the clam alias / --append-system-prompt-file mechanism.
# 2. Auto-create TODO.md: when $cwd/.local/ exists as a directory but
#    $cwd/.local/TODO.md does not, copy the template from
#    $PLUGIN_ROOT/templates/TODO.md, substitute [branch-name] with the git
#    branch and [YYYY-MM-DD] / [YYYY-MM-DD HH:MM] with the current date/time,
#    and write the result. Fail-open: missing template or write failure must
#    not break session start. Must run BEFORE the resume check (job 3) so a
#    freshly auto-created TODO.md triggers resume injection.
# 3. Resume support: when the cwd already has .local/TODO.md, surface its
#    State and Current Task and instruct the session to read the tracking docs
#    before doing anything else — this is what makes /clear + fresh
#    orchestrator pickup work.
# 4. Clear the once-per-session-epoch markers (.decision-nudge-fired,
#    .no-todo-nudge-fired) that scripts/keep-working.sh sets, on every
#    SessionStart event (startup, resume, clear, compact) — the same epoch
#    semantics clam-code implemented across session-track.sh and
#    post-compact.sh.
#
# Fail-open: any error exits 0 with no output rather than breaking session start.

set -u

command -v jq >/dev/null 2>&1 || exit 0

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
STATES_LIB="$PLUGIN_ROOT/lib/states.sh"
# shellcheck source=/dev/null
[ -f "$STATES_LIB" ] && . "$STATES_LIB"

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

# Epoch markers reset on every session boundary.
[ -n "$cwd" ] && rm -f "$cwd/.local/.decision-nudge-fired" "$cwd/.local/.no-todo-nudge-fired" "$cwd/.local/.flush-nudge-fired" "$cwd/.local/.freshness-nudge-fired" "$cwd/.local/.followups-nudge-fired" "$cwd/.local/.workgraph-nudge-fired" "$cwd/.local/.workgraph-create-nudge-fired" 2>/dev/null

# --- Auto-create TODO.md (B01: auto-create-todo) ---
#
# Behavior: when $cwd/.local/ exists as a directory but $cwd/.local/TODO.md
#   does not, copy $PLUGIN_ROOT/templates/TODO.md into $cwd/.local/TODO.md
#   with placeholder substitution.
# Inputs: $cwd (from hook JSON), $PLUGIN_ROOT (resolved above).
# Outputs: $cwd/.local/TODO.md on disk (or nothing on failure).
# Substitutions:
#   - [branch-name] → current git branch (empty string if not in a git repo)
#   - [YYYY-MM-DD HH:MM] → current date+time (local timezone)
#   - [YYYY-MM-DD] → current date (local timezone, only standalone occurrences
#     not already covered by the HH:MM substitution)
# Errors: fail-open — missing template, unwritable directory, or any error
#   must exit 0 with no output, never breaking session start.
# Invariants:
#   - NEVER overwrites an existing TODO.md.
#   - Runs BEFORE the resume-context check below so a freshly created TODO.md
#     triggers resume injection on the same SessionStart event.
#   - bash 3.2 safe (no associative arrays, no bash 4+ features).
# Edge cases:
#   - $cwd/.local/ does not exist → no-op.
#   - Template file missing → no-op.
#   - git not available or not in a repo → [branch-name] substituted with "".
#   - Write fails (read-only fs, permissions) → no-op, no error output.
_auto_create_todo() {
    [ -d "$cwd/.local" ] || return 0
    [ ! -f "$cwd/.local/TODO.md" ] || return 0
    local tmpl="$PLUGIN_ROOT/templates/TODO.md"
    [ -f "$tmpl" ] || return 0
    local branch
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null || true)
    local datetime
    datetime=$(date '+%Y-%m-%d %H:%M')
    local today
    today=$(date '+%Y-%m-%d')
    sed -e "s/\[branch-name\]/${branch:-}/g" \
        -e "s/\[YYYY-MM-DD HH:MM\]/${datetime}/g" \
        -e "s/\[YYYY-MM-DD\]/${today}/g" \
        "$tmpl" > "$cwd/.local/TODO.md" 2>/dev/null || rm -f "$cwd/.local/TODO.md" 2>/dev/null
}
[ -n "$cwd" ] && _auto_create_todo

IFS= read -r -d '' rules <<EOF || true
# Tracking (clam tracking plugin)

All work tracking uses \`.local/\` files in the current worktree as the single
source of truth. Do NOT use the built-in TaskCreate/TaskUpdate/TaskList/TaskGet
tools; they write to ~/.claude/tasks/, which is not visible or discoverable.

Update \`.local/TODO.md\` in real time — write state as you go, not at session
end. Compaction can happen at any time; state that lives only in conversation
is lost. Create it from the template at \`$PLUGIN_ROOT/templates/TODO.md\` when
starting tracked work. Persist immediately: decisions and plan changes to
\`.local/PLAN.md\` (append to its Changelog after creation), task changes to
\`TODO.md\`, failed fix attempts to \`.local/TROUBLESHOOTING.md\` before trying
the next approach.

Park unresolved conversation threads (a question asked but never answered, a naming/design thread left hanging) in \`TODO.md\`'s Open Questions section in real time, and clear each entry once it is resolved, recording the answer where it belongs (Implementation Log, PLAN.md's Changelog, or a decisions/ file).

Capture every follow-up or deferred-work item surfaced in conversation —
"worth filing later", a separate decision, "X should grow Y", a defect
noticed but not fixed here — in \`.local/FOLLOWUPS.md\` in real time, at the
moment it is mentioned. On first capture, create the file from the template
at \`$PLUGIN_ROOT/templates/FOLLOWUPS.md\` (lazy creation — do not create it
ahead of need). Append one entry per item, in the template's entry format,
and mark each entry's outcome in place as it is addressed — filed <ref>,
resolved, or dropped (<reason>) — rather than deleting it.

When a problem genuinely decomposes into subproblems, capture that
decomposition in \`.local/WORKGRAPH.md\`, created lazily from the template at
\`$PLUGIN_ROOT/templates/WORKGRAPH.md\` — never ahead of need — the moment it
first happens. That moment is observable, not a judgement call: writing any
artifact that enumerates two or more work items — a plan, a block or unit
table, a task breakdown — IS the decomposition, whichever workflow produced
it, and the graph exists before the turn that wrote such an artifact ends.
Those artifacts do not substitute for the graph; they are what the graph
mirrors. Add one node per subproblem at the moment it surfaces, each
with a Goal, a Parent decomposition edge, and Deps ordering edges. Move the
file-level Focus pointer in real time as attention shifts between nodes, and
cite the Focus node's id in TODO.md's Current Task field. Mark each node
done or dropped (<reason>) in place — rather than delete them; entries are
never removed. When asked to show the work graph, render it as an indented
ASCII tree: children nested under their parents, \`[needs: N<NN>]\` dependency
annotations, a status glyph per node, and an arrow marking the Focus node.

Four defaults govern how graph nodes are written. Node titles are plain
language — \`N<NN>\` is the only identifier a title needs, and ids from other
numbering systems belong in \`Notes:\` or in the artifacts that own them. Add
one node per actual work item rather than one per topic: when a problem is
worked as distinct phases by distinct actors, each phase is its own node
carrying its own dependency edge, so who is doing what right now reads from
the graph alone. And a follow-up captured mid-effort gets its graph node at
capture, not once it is acted on — mirror the follow-up's outcome onto that
node as the entry resolves. And the graph is a tree with ordering edges,
not a flat list: exactly one node is a root per deliverable, and every
other node carries a Parent edge to the node it decomposes. A graph created
late — after work has already started — is still authored this way, top-down
with per-phase nodes and Parent edges, never transcribed as a flat summary
of a unit table.

The moment \`.local/WORKGRAPH.md\` is created, check the skill catalog for a
skill that can serve a markdown document as a live, self-updating HTML view
without opening a browser; when one is available, serve
\`.local/WORKGRAPH.md\` through it and tell the engineer the resulting URL
once, in conversation. When no such skill is available, skip silently — no
error, no mention of the missing capability — and the graph itself is never
blocked on it.

State lifecycle (\`State:\` field in TODO.md). Three states summon the user
(bell, dashboard flag, push — once on the transition in, not on every turn):

- **Needs the user (stopped):** \`Blocked\` (a human must act; populate
  \`Blocked Reason:\`) and \`Waiting For Decision\` (user must choose between
  approaches; first write the analysis to \`.local/decisions/NNN-<slug>.md\`
  per the /decision-log:rundown template — options, evidence, recommendation,
  if-deferred path — then populate \`Decision Needed:\` with the question, the
  recommended option, and the file path). Every artifact a decision document
  references — a plan, a graph, another decision, a piece of code — is carried
  as a relative markdown link resolvable from that decision file's own
  directory, never as a bare path in backticks. The moment the decision file
  is written, check the skill catalog for a skill that renders a markdown
  document to an HTML view opened in the engineer's browser; when one is
  available, open the decision file through it before ending the turn.
  Opening is the point — registering a document on a background server
  without opening it does not present it, and does not satisfy this rule.
- **Parked, summons once then waits:** \`Awaiting User Review\` (draft PR up,
  user reviewing at their own pace).
- **Parked, resumes on its own, stays silent:** \`Awaiting Agent\`,
  \`Awaiting CI\`, \`Awaiting Independent Agent Review\`, \`Awaiting Bot
  Review\`, \`Awaiting Reviewer Assignment\`, \`Awaiting Human Review\`,
  \`Awaiting Merge Queue\`. Put what is in flight in \`Current Task:\`.
- **Active/terminal:** \`Not Started\`, \`In Progress\` (do not end a turn
  here unless genuinely still going — the Stop hook nudges), \`Complete\`
  (only when no actionable work remains in this session's scope).

Never park on \`Blocked\`/\`Waiting For Decision\` when no user action is
required; summon only when the user must act, so that every summons is
actionable. On the
transition into a summoning state, run \`notify <worktree-basename>\` if that
helper is installed (\`command -v notify\`; skip silently otherwise).

A turn ending in a summoning state must END with a user-facing message that
restates the blocker or decision in plain terms — what is needed, from whom,
what actions to take — mirrored into \`Blocked Reason:\`/\`Decision Needed:\`.
The screen-bottom line is what the user sees first; do not assume they scroll
up. For decisions, make each option decidable at a glance: plain-terms
meaning, one-line trade-off, recommendation and why, the default on a bare
"go", and the decision-file path (~10 lines for a 2-3 option decision).
EOF
rules=${rules%$'\n'}

# Contract: B02 — followups-capture-and-surfacing
#
# Behavior:
#   Three coupled obligations, all in this script:
#   (1) Capture rule: the rules heredoc above gains an instruction (placed
#       directly after the Open Questions rule) requiring agents to record
#       EVERY follow-up or deferred-work item surfaced in conversation —
#       "worth filing later", "separate decision", "X should grow Y", a
#       defect noticed but not fixed here — into `.local/FOLLOWUPS.md`
#       IN REAL TIME at mention: create the file from
#       $PLUGIN_ROOT/templates/FOLLOWUPS.md on first capture (lazy creation),
#       append one entry per item in the template's entry format, and
#       disposition entries (filed <ref> / resolved / dropped (<reason>))
#       rather than delete them.
#   (2) Surfacing: _followups_surfacing prints an "Open follow-ups" block
#       for injection whenever $cwd/.local/FOLLOWUPS.md exists and contains
#       at least one open entry. Wiring: the final assembly becomes
#       printf '%s%s%s' "$rules" "$resume" "<this output>" (wiring the third
#       operand is part of this block's implementation).
#   (3) Epoch marker: `.local/.followups-nudge-fired` joins the marker-clear
#       rm -f list at the top of this script, same session-boundary scheme
#       as the other nudge markers.
# Inputs: $cwd; $cwd/.local/FOLLOWUPS.md (may be absent). An entry is OPEN
#   iff it contains a line matching ^- Status: open[[:space:]]*$.
# Outputs (stdout of _followups_surfacing): empty when $cwd is empty, the
#   file is absent/unreadable, or no entry is open. Otherwise:
#     - header line: `# Open follow-ups (N)` (N = count of open entries);
#     - one line per open entry: its `## F<NN> — <title>` heading text with
#       the leading `## ` stripped, or `(untitled)` if the Status line has
#       no preceding F-heading;
#     - one closing line instructing that each must be dispositioned
#       (filed / resolved / dropped with reason) before work closes out.
# Errors: fail-open — any failure prints nothing and returns 0; SessionStart
#   is never broken by this feature.
# Invariants:
#   - Read-only: never creates or modifies FOLLOWUPS.md.
#   - Existing rules text, auto-create, resume behavior, and all
#     pre-existing session-context tests remain unchanged/green.
#   - bash 3.2 safe (no associative arrays, no bash 4+ features).
# Edge cases:
#   - FOLLOWUPS.md exists, all entries dispositioned → empty output.
#   - Zero-byte or malformed file → empty output, no error.
#   - Open entry count N counts Status lines, not headings.
_followups_surfacing() {
    [ -n "$cwd" ] || return 0
    local file="$cwd/.local/FOLLOWUPS.md"
    [ -f "$file" ] && [ -r "$file" ] || return 0

    local entries
    entries=$(awk '
        /^## / { heading = substr($0, 4); next }
        /^- Status: open[ \t]*$/ {
            if (heading == "") print "(untitled)"
            else print heading
            next
        }
    ' "$file" 2>/dev/null)
    [ -n "$entries" ] || return 0

    local count
    count=$(printf '%s\n' "$entries" | wc -l | tr -d '[:space:]')

    printf '\n\n# Open follow-ups (%s)\n' "$count"
    printf '%s\n' "$entries"
    printf '\nEach open follow-up above must be dispositioned — filed <ref>, resolved, or dropped (<reason>) — before this work closes out.\n'
}

# Contract: B03 — workgraph-rules-and-surfacing (plan 001-tracking-work-graph)
#
# Behavior:
#   Three coupled obligations, all in this script, mirroring the follow-ups
#   block above (the work graph is the sibling artifact for recursive
#   problem decomposition; format: docs/protocols/work-graph.md):
#   (1) Capture rule: the rules heredoc above gains a work-graph paragraph,
#       placed directly after the FOLLOWUPS capture paragraph, requiring
#       agents to: create `.local/WORKGRAPH.md` from
#       $PLUGIN_ROOT/templates/WORKGRAPH.md the moment a problem genuinely
#       decomposes into subproblems (lazy creation — never ahead of need);
#       add one node per problem/subproblem AT the moment it surfaces, each
#       with a Goal: stating what done looks like, a Parent: decomposition
#       edge, and Deps: ordering edges; keep the file-level `Focus:` pointer
#       on the node being worked and move it in real time as attention
#       moves; cite the Focus node id in TODO.md's `Current Task:`;
#       disposition nodes in place (done / dropped (<reason>)) rather than
#       delete them; and render the graph as an indented ASCII tree
#       (children under parents, [needs: N<NN>] dep annotations, status
#       glyphs, an arrow at the Focus node) whenever the engineer asks to
#       see it.
#   (2) Surfacing: _workgraph_surfacing prints a "Work graph" block for
#       injection whenever $cwd/.local/WORKGRAPH.md exists and contains at
#       least one open node. Wiring: the final assembly becomes
#       printf '%s%s%s%s' "$rules" "$resume" "$followups_block"
#       "$workgraph_block" (wiring the fourth operand is part of this
#       block's implementation; the work-graph block renders after the
#       open-follow-ups block).
#   (3) Epoch marker: `.local/.workgraph-nudge-fired` joins the
#       marker-clear rm -f list at the top of this script, same
#       session-boundary scheme as the other nudge markers (the marker
#       itself is set by keep-working.sh's close-out gate, B04).
# Inputs: $cwd; $cwd/.local/WORKGRAPH.md (may be absent). A node is OPEN
#   iff it contains a line matching ^- Status: open[[:space:]]*$; the Focus
#   pointer is the line matching ^Focus: (N[0-9]+|none)[[:space:]]*$; node
#   headings match ^## N[0-9]+ — <title> (heading text = the line with the
#   leading "## " stripped).
# Outputs (stdout of _workgraph_surfacing): empty when $cwd is empty, the
#   file is absent/unreadable, or no node is open. Otherwise:
#     - header line: `# Work graph (N open node(s); Focus: <id|none>)`
#       (N = count of open nodes; <id|none> = the Focus line's value, or
#       `none` when the Focus line is absent/malformed);
#     - when the Focus value names a node entry present in the file: one
#       line `Focus: <heading text>` and one line `  Goal: <that node's
#       Goal field value>` (both omitted when Focus is none, dangling, or
#       the node has no Goal line — fail-open, never an error);
#     - one line per open node: its heading text, or `(untitled)` if an
#       open Status line has no preceding node heading;
#     - one closing line instructing that the Focus pointer and node
#       Statuses be kept current in real time, nodes dispositioned (done /
#       dropped (<reason>)) rather than deleted, and the graph rendered as
#       an ASCII tree on request.
# Errors: fail-open — any failure prints nothing and returns 0; SessionStart
#   is never broken by this feature.
# Invariants:
#   - Read-only: never creates or modifies WORKGRAPH.md.
#   - Existing rules text, auto-create, resume behavior, follow-ups
#     surfacing, and all pre-existing session-context tests remain
#     unchanged/green.
#   - bash 3.2 safe (no associative arrays, no bash 4+ features).
# Edge cases:
#   - WORKGRAPH.md exists, every node done/dropped → empty output (a
#     finished graph is not resurfaced).
#   - Zero-byte or malformed file → empty output, no error.
#   - Freshly instantiated template (Focus: none, no real nodes) → empty
#     output.
#   - Open-node count N counts open Status lines, not headings.
_workgraph_surfacing() {
    [ -n "$cwd" ] || return 0
    local file="$cwd/.local/WORKGRAPH.md"
    [ -f "$file" ] && [ -r "$file" ] || return 0

    local entries
    entries=$(awk '
        /^## / { heading = substr($0, 4); next }
        /^- Status: open[ \t]*$/ {
            if (heading == "") print "(untitled)"
            else print heading
            next
        }
    ' "$file" 2>/dev/null)
    [ -n "$entries" ] || return 0

    local count
    count=$(printf '%s\n' "$entries" | wc -l | tr -d '[:space:]')

    local focus_line focus_id
    focus_line=$(grep -m1 -E '^Focus: (N[0-9]+|none)[[:space:]]*$' "$file" 2>/dev/null)
    if [ -n "$focus_line" ]; then
        focus_id=$(printf '%s\n' "$focus_line" | sed -E 's/^Focus: ([^[:space:]]+).*/\1/')
    else
        focus_id="none"
    fi

    # Focus/Goal detail lines: find the node heading whose leading token (the
    # N<NN> id, up to the first space) equals focus_id, then capture its Goal
    # field. Split on the first space rather than the em-dash separator to
    # stay encoding-agnostic. Emits nothing when Focus is none/dangling, or
    # the matched node has no Goal line — fail-open by construction.
    local focus_detail
    focus_detail=$(awk -v want="$focus_id" '
        /^## / {
            heading = substr($0, 4)
            idpart = heading
            sp = index(heading, " ")
            if (sp > 0) idpart = substr(heading, 1, sp - 1)
            matched = (idpart == want)
            if (matched) { mheading = heading; mgoal = "" }
            next
        }
        matched && /^- Goal: / {
            mgoal = substr($0, 9)
            next
        }
        END {
            if (mheading != "" && mgoal != "") {
                printf "Focus: %s\n  Goal: %s\n", mheading, mgoal
            }
        }
    ' "$file" 2>/dev/null)

    printf '\n\n# Work graph (%s open node(s); Focus: %s)\n' "$count" "$focus_id"
    [ -n "$focus_detail" ] && printf '%s\n' "$focus_detail"
    printf '%s\n' "$entries"
    printf '\nKeep the Focus pointer and node Status entries current in real time; disposition nodes (done or dropped (<reason>)) rather than deleting them; render the graph as an indented ASCII tree when asked to see it.\n'
}

# Contract: B04 — resume-freshness
#
# Behavior:
#   Reader-side staleness net for the resume injection below. Before telling
#   a fresh session to trust the tracking docs, cross-check the docs' age
#   against actual conversation activity recorded on disk:
#     ref      = mtime(.local/TODO.md)
#     prior    = activity_prior_transcripts($cwd, $transcript_path)   [B01]
#     count    = sum over the NEWEST 5 prior transcripts of
#                activity_prompts_since(ref, transcript)              [B01]
#   When count >= CLAM_TRACKING_RESUME_STALE_THRESHOLD (default 1), the docs
#   demonstrably lag the last conversation: print (stdout) a STALE-variant
#   resume block that REPLACES the trust-the-docs text. It must contain, in
#   plain terms:
#     - a warning that .local/TODO.md may be STALE: it was last updated at
#       <ISO-8601 local time of ref> but ~<count> human prompt(s) arrived
#       after that (most recent conversation activity: <ISO-8601 local mtime
#       of the newest prior transcript>);
#     - the newest prior transcript's absolute path, with the instruction to
#       read its TAIL (the last ~30 entries) to recover pivots, decisions,
#       and open questions the docs missed, BEFORE trusting recorded state;
#     - the instruction to still read .local/TODO.md, .local/PLAN.md, and
#       .local/decisions/, then reconcile: update the docs with anything the
#       transcript tail shows the docs missed, before resuming work;
#     - the current recorded State and Current Task (same fields the fresh
#       variant surfaces).
#   When count < threshold, or on ANY failure/uncertainty: print nothing —
#   the caller falls back to the existing trust-the-docs resume block.
#
# Inputs:
#   $cwd, $transcript_path — outer scope (transcript_path is the CURRENT
#     session's transcript, passed as the exclusion to
#     activity_prior_transcripts so a resumed session never reads itself as
#     "prior" activity; empty is fine — nothing to exclude).
#   $cwd/.local/TODO.md — must exist (caller only invokes when it does).
#   lib/activity.sh, lib/platform.sh (clam_mtime_epoch) — sourced lazily;
#     absent → fail-open (no output).
#   CLAM_TRACKING_RESUME_STALE_GATE — "disabled" turns the check off
#     (default enabled).
#   CLAM_TRACKING_RESUME_STALE_THRESHOLD — integer >= 1, default 1 (one
#     unreflected human prompt at recap time is worth a warning); invalid → 1.
#
# Outputs:
#   stdout: the complete stale-variant resume block, or nothing. Never
#   partial output. Return 0 on both paths (90 NotImplemented sentinel until
#   implemented; caller treats any output-less path identically).
#
# Errors:
#   Fail-open everywhere: no jq, no libs, unreadable TODO mtime, no project
#   dir, count non-numeric → no output (fresh-variant behavior).
#
# Invariants:
#   - Pure read; no markers, no writes.
#   - Bounded work: at most 5 transcripts scanned, single pass each, within
#     the hook's 10s timeout.
#   - The stale variant must NOT say "trust the tracking docs" — the two
#     variants are mutually exclusive by construction.
#
# Edge cases:
#   - Post-compaction SessionStart: the continuing session's own transcript
#     is excluded via $transcript_path; other prior transcripts still count.
#   - Brand-new worktree, no project dir yet → fresh variant.
#   - TODO.md auto-created moments ago by _auto_create_todo (mtime ~now) →
#     count vs a just-now ref is 0 → fresh variant (correct: nothing recorded
#     to be stale yet — the transcripts predate the tracking, not the
#     reverse; acceptable known limit of the mtime reference).
_resume_freshness() {
    [ "${CLAM_TRACKING_RESUME_STALE_GATE:-}" = "disabled" ] && return 0
    [ -n "$cwd" ] && [ -f "$cwd/.local/TODO.md" ] || return 0

    local activity_lib platform_lib
    activity_lib="$PLUGIN_ROOT/lib/activity.sh"
    platform_lib="$PLUGIN_ROOT/lib/platform.sh"
    [ -f "$activity_lib" ] && [ -f "$platform_lib" ] || return 0
    # shellcheck source=/dev/null
    . "$activity_lib"
    # shellcheck source=/dev/null
    . "$platform_lib"
    command -v activity_prior_transcripts >/dev/null 2>&1 || return 0
    command -v activity_prompts_since >/dev/null 2>&1 || return 0
    command -v clam_mtime_epoch >/dev/null 2>&1 || return 0

    local threshold="${CLAM_TRACKING_RESUME_STALE_THRESHOLD:-}"
    case "$threshold" in
        ''|*[!0-9]*|0) threshold=1 ;;
    esac

    local ref_epoch
    ref_epoch=$(clam_mtime_epoch "$cwd/.local/TODO.md" 2>/dev/null)
    case "$ref_epoch" in ''|*[!0-9]*|0) return 0 ;; esac

    local prior
    prior=$(activity_prior_transcripts "$cwd" "$transcript_path" 2>/dev/null)
    [ -n "$prior" ] || return 0

    # Sum activity_prompts_since over the newest 5 prior transcripts only
    # (already mtime-descending from activity_prior_transcripts); track the
    # first (newest) one for the report below.
    local newest="" total=0 n=0 line count
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        n=$((n + 1))
        [ "$n" -gt 5 ] && break
        [ -z "$newest" ] && newest="$line"
        count=$(activity_prompts_since "$ref_epoch" "$line" 2>/dev/null)
        case "$count" in ''|*[!0-9]*) count=0 ;; esac
        total=$((total + count))
    done <<PRIOR_EOF
$prior
PRIOR_EOF

    [ -n "$newest" ] || return 0
    [ "$total" -ge "$threshold" ] || return 0

    local newest_mtime
    newest_mtime=$(clam_mtime_epoch "$newest" 2>/dev/null)
    case "$newest_mtime" in ''|*[!0-9]*) newest_mtime=0 ;; esac

    # Portable epoch->local-ISO-8601: BSD `date -r <epoch>` first (fails fast
    # on GNU, no such file), then GNU `date -d "@<epoch>"`.
    local ref_iso newest_iso
    ref_iso=$(date -r "$ref_epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -d "@$ref_epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)
    newest_iso=$(date -r "$newest_mtime" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -d "@$newest_mtime" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)
    [ -n "$ref_iso" ] && [ -n "$newest_iso" ] || return 0

    cat <<STALE_EOF
# Tracking document may be STALE — verify before resuming

\`.local/TODO.md\` was last updated at ${ref_iso}, but ~${total} human prompt(s) arrived in this worktree's conversation after that (most recent conversation activity: ${newest_iso}).

Before trusting recorded state: read the TAIL (the last ~30 entries) of the most recent prior transcript to recover pivots, decisions, and open questions the docs may have missed:
${newest}

Then still read \`.local/TODO.md\`, \`.local/PLAN.md\`, and any \`.local/decisions/\` files, and reconcile — update the docs with anything the transcript tail shows they missed, before resuming work.

Recorded State: ${state:-unknown}
Recorded Current Task: ${task:-unset}
STALE_EOF
}

resume=""
if [ -n "$cwd" ] && [ -f "$cwd/.local/TODO.md" ]; then
    state=""
    task=""
    if command -v todo_field >/dev/null 2>&1; then
        state=$(todo_field "$cwd/.local/TODO.md" State)
        task=$(todo_field "$cwd/.local/TODO.md" "Current Task")
    fi
    # B04: the stale-variant block replaces the trust-the-docs text when the
    # docs demonstrably lag recorded conversation activity. Empty output (or
    # the NotImplemented sentinel) falls through to the fresh variant.
    stale_block=$(_resume_freshness 2>/dev/null) || stale_block=""
    if [ -n "$stale_block" ]; then
        resume=$(printf '\n\n%s' "$stale_block")
    else
    IFS= read -r -d '' resume <<EOF || true


# Tracking document present — resume from it

This worktree already has \`.local/TODO.md\` (State: ${state:-unknown};
Current Task: ${task:-unset}). Before doing anything else, read
\`.local/TODO.md\` — plus \`.local/PLAN.md\` and any \`.local/decisions/\`
files if present — and continue from the recorded state. Do not restart
completed work; trust the tracking docs over assumptions about a fresh start.
EOF
    resume=${resume%$'\n'}
    fi
fi

followups_block=$(_followups_surfacing 2>/dev/null) || followups_block=""

workgraph_block=$(_workgraph_surfacing 2>/dev/null) || workgraph_block=""

printf '%s%s%s%s' "$rules" "$resume" "$followups_block" "$workgraph_block" | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
