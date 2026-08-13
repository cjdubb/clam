#!/bin/bash
# Functional test for B10 subagent-line: scripts/subagent.sh, the agent-panel
# row renderer wired to Claude Code's `subagentStatusLine` settings key.
#
# Every assertion below traces to a clause of that script's header contract.
# The shape of a row body (field order, separators, labels) is deliberately NOT
# pinned: the contract names the FIGURES a row carries -- the task's name, its
# model in B03's flat colour, its effort, its cwd basename, its context
# percentage in burn_ctx_color's colour -- and not their spelling, so every
# check here is a presence/absence check over the row's text and its SGR
# openers rather than an exact-string match.
#
# Expected colours are computed by CALLING lib/burn-theme.sh's real
# burn_model_color / burn_ctx_color rather than by hardcoding SGR codes, which
# is the "reuses lib/burn-theme.sh, so a subagent row and line 2 can never
# disagree" invariant expressed as a test: a threshold change in that file must
# move this suite's expectations with it, never leave them behind.
#
# Run: bash plugins/statusline/scripts/subagent.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBAGENT="$SCRIPT_DIR/subagent.sh"
# shellcheck disable=SC1091  # path is resolved at runtime, relative to this file
source "$SCRIPT_DIR/../lib/burn-theme.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

ESC=$(printf '\033')
strip_ansi() { sed -E "s/${ESC}\[[0-9;]*m//g; s/${ESC}\]8;;[^${ESC}]*${ESC}\\\\//g"; }

OUT="$TMPROOT/out"
ERR="$TMPROOT/err"
RC=0

# run_sub(payload): render the payload through subagent.sh, capturing stdout,
# stderr and the exit code separately -- all three are contracted surfaces.
run_sub() { # payload
  printf '%s' "$1" | bash "$SUBAGENT" >"$OUT" 2>"$ERR"
  RC=$?
}

# Counts a trailing unterminated line too, which `wc -l` would silently drop --
# "no output at all" and "one line without a newline" are different verdicts
# under the Errors clause.
count_lines() { local n; n=$(grep -c '' "$OUT" 2>/dev/null); echo "${n:-0}"; }

# content_for(id): the `content` string of the emitted row whose `id` is $1,
# with its escapes decoded (jq -r), or empty if no such row was emitted.
content_for() { # id
  jq -r --arg id "$1" 'select(.id == $id) | .content' "$OUT" 2>/dev/null
}

# Case-insensitive plain-substring presence over a row's VISIBLE text.
has_text() { # haystack needle
  printf '%s' "$1" | strip_ansi | grep -qiF -- "$2" && echo yes || echo no
}
# Plain-substring presence over the RAW row, escapes included -- for SGR openers.
has_raw() { # haystack needle
  printf '%s' "$1" | grep -qF -- "$2" && echo yes || echo no
}

# ============================================================================
# Fixtures
#
# Every payload below sets the ORCHESTRATOR's own model, effort and cwd to
# values that differ from every task's, and to values chosen so they cannot
# collide with a task's text. That is not incidental: the Behavior clause says
# each row is rendered from THAT SUBAGENT'S OWN fields "never the
# orchestrator's", and the only way to observe the difference is to make the
# two disagree in every field at once.
# ============================================================================

# The session (orchestrator) side of every payload: Haiku / max / a distinctly
# named cwd. Haiku's flat colour (117) is distinct from Opus's (33) and
# Sonnet's (75), so a row that leaked the session model is visible as a colour
# as well as a name.
SESSION_FIELDS='"model":{"display_name":"Haiku"},"effort":{"level":"max"},"workspace":{"current_dir":"/tmp/orchestrator-home"},"session_id":"sess-b10"'

# task(id,name,model,effort,ctxsize,tokens,cwd): one element of `tasks`. A
# field whose value is the literal string OMIT is left out of the object
# entirely, which is how the pre-resolution and inherited-effort edge cases are
# expressed -- an ABSENT key, not a null and not an empty string.
task() { # id name model effort ctxsize tokens cwd
  printf '{"id":"%s","name":"%s","type":"general-purpose","status":"running","description":"a task","label":"%s","startTime":1770000000000' "$1" "$2" "$2"
  [ "$3" != "OMIT" ] && printf ',"model":"%s"' "$3"
  [ "$4" != "OMIT" ] && printf ',"effort":"%s"' "$4"
  [ "$5" != "OMIT" ] && printf ',"contextWindowSize":%s' "$5"
  [ "$6" != "OMIT" ] && printf ',"tokenCount":%s' "$6"
  printf ',"tokenSamples":[]'
  [ "$7" != "OMIT" ] && printf ',"cwd":"%s"' "$7"
  printf '}'
}

# payload(columns, task_json...): the full subagentStatusLine object.
payload() { # columns task_json...
  local cols="$1"; shift
  printf '{%s,"columns":%s,"tasks":[' "$SESSION_FIELDS" "$cols"
  local first=1 t
  for t in "$@"; do
    [ "$first" = "1" ] || printf ','
    first=0
    printf '%s' "$t"
  done
  printf ']}'
}

# Expected colours, taken from the real theme functions.
OPUS_COLOR="$(burn_model_color Opus)"
SONNET_COLOR="$(burn_model_color Sonnet)"
HAIKU_COLOR="$(burn_model_color Haiku)"
CTX_75_COLOR="$(burn_ctx_color 75)"    # >=60 -> red 196
CTX_20_COLOR="$(burn_ctx_color 20)"    # boundary -> yellow 214
CTX_5_COLOR="$(burn_ctx_color 5)"      # <20 -> green 40

# ============================================================================
# Behavior / Outputs: one JSON line per task, ids matching, documented shape
# ============================================================================
T_ALPHA="$(task ta-1 explorer Opus high 200000 150000 /tmp/wt/agent-alpha)"
T_BETA="$(task tb-2 reviewer Sonnet low 200000 40000 /tmp/wt/agent-beta)"
run_sub "$(payload 200 "$T_ALPHA" "$T_BETA")"

check "two tasks emit exactly two lines" "$(count_lines)" "2"
check "good payload exits 0" "$RC" "0"
check "good payload writes nothing to stderr" "$(cat "$ERR")" ""
check "every emitted line is valid JSON" \
  "$(while IFS= read -r l; do printf '%s' "$l" | jq -e . >/dev/null 2>&1 || { echo no; break; }; done < "$OUT" | head -n1)" ""
check "emitted ids are exactly the payload's task ids" \
  "$(jq -r '.id' "$OUT" 2>/dev/null | sort | tr '\n' ' ')" "ta-1 tb-2 "
check "each line carries exactly the documented id/content keys" \
  "$(jq -c -S 'keys' "$OUT" 2>/dev/null | sort -u | tr '\n' ' ')" '["content","id"] '

ALPHA="$(content_for ta-1)"
BETA="$(content_for tb-2)"

check "row carries its task's name" "$(has_text "$ALPHA" explorer)" "yes"
check "second row carries its own task's name" "$(has_text "$BETA" reviewer)" "yes"
check "row does not carry the other task's name" "$(has_text "$ALPHA" reviewer)" "no"
check "row names its task's model" "$(has_text "$ALPHA" opus)" "yes"
check "row colours the model with burn_model_color" "$(has_raw "$ALPHA" "$OPUS_COLOR")" "yes"
check "second row colours its own model with burn_model_color" "$(has_raw "$BETA" "$SONNET_COLOR")" "yes"
check "row carries its task's effort" "$(has_text "$ALPHA" high)" "yes"
check "second row carries its own effort" "$(has_text "$BETA" low)" "yes"
check "row carries the basename of its task's cwd" "$(has_text "$ALPHA" agent-alpha)" "yes"
check "row carries the cwd BASENAME, not the full path" \
  "$(has_text "$ALPHA" /tmp/wt/agent-alpha)" "no"
check "row carries the context percentage (150000/200000 = 75%)" \
  "$(has_text "$ALPHA" '75%')" "yes"
check "row colours the context percentage with burn_ctx_color" \
  "$(has_raw "$ALPHA" "$CTX_75_COLOR")" "yes"
check "second row computes its own context percentage (40000/200000 = 20%)" \
  "$(has_text "$BETA" '20%')" "yes"
check "second row takes burn_ctx_color's tier for its own percentage" \
  "$(has_raw "$BETA" "$CTX_20_COLOR")" "yes"
check "no row renders a literal 'null' for any field" \
  "$(grep -qF 'null' "$OUT" && echo yes || echo no)" "no"

# --- provenance: the whole reason the block exists ---------------------------
# The session's model, effort and cwd are all present in the same payload and
# all differ from the task's. A row built from the statusLine-shaped session
# fields instead of the task's own would show them.
check "provenance: row does not show the session's model name" "$(has_text "$ALPHA" haiku)" "no"
check "provenance: row does not show the session's model colour" \
  "$(has_raw "$ALPHA" "$HAIKU_COLOR")" "no"
check "provenance: row does not show the session's effort" "$(has_text "$ALPHA" max)" "no"
check "provenance: row does not show the session's cwd" \
  "$(has_text "$ALPHA" orchestrator-home)" "no"

# --- provenance edge case: a task sharing the orchestrator's cwd -------------
# "Correctness here is about provenance, not about difference": the row is
# still rendered from the task's own cwd when that cwd happens to equal the
# session's, so the basename appears rather than being suppressed as redundant.
run_sub "$(payload 200 "$(task ts-1 twin Opus high 200000 150000 /tmp/orchestrator-home)")"
check "task cwd equal to the orchestrator's still renders its basename" \
  "$(has_text "$(content_for ts-1)" orchestrator-home)" "yes"

# ============================================================================
# Edge case: `effort` ABSENT -- the documented inheritance case
#
# The contract is explicit that this is the defect the block exists to fix:
# render NO effort rather than the session's value. The payload's session
# effort is "max", so a leaked inherited value is directly observable; the
# check below additionally rejects EVERY effort word, so an implementation
# that invented a default ("medium") fails too.
# ============================================================================
run_sub "$(payload 200 "$(task te-1 inheritor Opus OMIT 200000 150000 /tmp/wt/agent-eff)")"
EFF="$(content_for te-1)"
check "effort absent: the row is still emitted" "$(count_lines)" "1"
check "effort absent: the session's effort is NOT shown" "$(has_text "$EFF" max)" "no"
check "effort absent: no effort tier of any kind is shown" \
  "$(for w in low medium high xhigh max; do
       [ "$(has_text "$EFF" "$w")" = "yes" ] && { echo leaked; break; }
     done | head -n1)" ""
check "effort absent: the rest of the row survives (name)" "$(has_text "$EFF" inheritor)" "yes"
check "effort absent: the rest of the row survives (model)" "$(has_text "$EFF" opus)" "yes"
check "effort absent: the rest of the row survives (cwd basename)" "$(has_text "$EFF" agent-eff)" "yes"
check "effort absent: the rest of the row survives (context percentage)" "$(has_text "$EFF" '75%')" "yes"

# ============================================================================
# Edge case: `model` absent before the task's model resolves
# ============================================================================
run_sub "$(payload 200 "$(task tm-1 premodel OMIT high 200000 150000 /tmp/wt/agent-mdl)")"
MDL="$(content_for tm-1)"
check "model absent: the row is still emitted" "$(count_lines)" "1"
check "model absent: the session's model does not stand in" "$(has_text "$MDL" haiku)" "no"
check "model absent: the session's model colour does not stand in" \
  "$(has_raw "$MDL" "$HAIKU_COLOR")" "no"
check "model absent: name survives" "$(has_text "$MDL" premodel)" "yes"
check "model absent: effort survives" "$(has_text "$MDL" high)" "yes"
check "model absent: cwd basename survives" "$(has_text "$MDL" agent-mdl)" "yes"
check "model absent: context percentage survives" "$(has_text "$MDL" '75%')" "yes"
check "model absent: exits 0, silent" "$RC$(cat "$ERR")" "0"

# ============================================================================
# Edge case: `contextWindowSize` absent before the task's model resolves
#
# The percentage is the affected figure and is omitted; everything else stays.
# "No percentage" is asserted as no percent sign at all, since the figure has
# no other spelling to check for.
# ============================================================================
run_sub "$(payload 200 "$(task tc-1 prectx Opus high OMIT 150000 /tmp/wt/agent-ctx)")"
CTXROW="$(content_for tc-1)"
check "contextWindowSize absent: the row is still emitted" "$(count_lines)" "1"
check "contextWindowSize absent: no percentage figure is rendered" \
  "$(has_text "$CTXROW" '%')" "no"
check "contextWindowSize absent: name survives" "$(has_text "$CTXROW" prectx)" "yes"
check "contextWindowSize absent: model survives" "$(has_text "$CTXROW" opus)" "yes"
check "contextWindowSize absent: effort survives" "$(has_text "$CTXROW" high)" "yes"
check "contextWindowSize absent: cwd basename survives" "$(has_text "$CTXROW" agent-ctx)" "yes"
check "contextWindowSize absent: exits 0, silent" "$RC$(cat "$ERR")" "0"

# tokenCount is the other half of the same division; absent, the percentage is
# equally underivable and the same omit-the-figure rule applies.
run_sub "$(payload 200 "$(task tk-1 pretok Opus high 200000 OMIT /tmp/wt/agent-tok)")"
TOKROW="$(content_for tk-1)"
check "tokenCount absent: no percentage figure is rendered" "$(has_text "$TOKROW" '%')" "no"
check "tokenCount absent: the rest of the row survives" \
  "$(has_text "$TOKROW" pretok)$(has_text "$TOKROW" agent-tok)" "yesyes"

# A small occupancy takes burn_ctx_color's green tier, which proves the colour
# tracks the figure rather than being a constant lifted from one scenario.
run_sub "$(payload 200 "$(task tl-1 lowctx Opus high 200000 10000 /tmp/wt/agent-low)")"
LOWROW="$(content_for tl-1)"
check "low occupancy: percentage computed from the task's own figures (5%)" \
  "$(has_text "$LOWROW" '5%')" "yes"
check "low occupancy: takes burn_ctx_color's low tier, not the high one" \
  "$(has_raw "$LOWROW" "$CTX_5_COLOR")$(has_raw "$LOWROW" "$CTX_75_COLOR")" "yesno"

# ============================================================================
# Edge case: an empty `tasks` array emits nothing
# ============================================================================
run_sub "$(payload 200)"
check "empty tasks: no output" "$(count_lines)" "0"
check "empty tasks: exits 0" "$RC" "0"
check "empty tasks: silent on stderr" "$(cat "$ERR")" ""

# ============================================================================
# Errors: never loud. Malformed input emits no lines, no stderr, exit 0.
# ============================================================================
malformed_case() { # label payload
  run_sub "$2"
  check "$1: no lines" "$(count_lines)" "0"
  check "$1: exits 0" "$RC" "0"
  check "$1: silent on stderr" "$(cat "$ERR")" ""
}
malformed_case "malformed payload (not JSON)" 'this is not json at all'
malformed_case "malformed payload (truncated JSON)" '{"columns":200,"tasks":[{"id":"x"'
malformed_case "empty stdin" ''
malformed_case "JSON without a tasks key" '{"columns":200}'
malformed_case "tasks of the wrong type" '{"columns":200,"tasks":"nope"}'

# --- missing jq degrades exactly the same way -------------------------------
# PATH is REPLACED with a directory holding symlinks to the ordinary tools a
# renderer might reach for, minus jq, so the only thing missing is jq itself
# and the degrade cannot be attributed to a bare environment.
NOJQ_BIN="$TMPROOT/nojq-bin"; mkdir -p "$NOJQ_BIN"
nojq_ready=1
for tool in bash sed awk grep cat tr cut head basename dirname printf wc; do
  tool_path=$(type -P "$tool" 2>/dev/null) || continue
  ln -s "$tool_path" "$NOJQ_BIN/$tool"
done
[ -x "$NOJQ_BIN/bash" ] || nojq_ready=0
if [ "$nojq_ready" = "1" ]; then
  printf '%s' "$(payload 200 "$T_ALPHA")" \
    | env -i PATH="$NOJQ_BIN" HOME="$TMPROOT" bash "$SUBAGENT" >"$OUT" 2>"$ERR"
  RC=$?
  check "missing jq: no lines" "$(count_lines)" "0"
  check "missing jq: exits 0" "$RC" "0"
  check "missing jq: silent on stderr" "$(cat "$ERR")" ""
else
  echo "SKIP  missing-jq degrade: could not resolve bash to symlink"
fi

# ============================================================================
# Invariant: output respects `columns` -- a long row is TRUNCATED, not wrapped
# ============================================================================
LONGCWD="/tmp/wt/a-very-long-worktree-directory-name-for-truncation"
LONGTASK="$(task tt-1 an-extremely-long-subagent-task-name-for-truncation Opus high 200000 150000 "$LONGCWD")"

run_sub "$(payload 200 "$LONGTASK")"
WIDE="$(content_for tt-1)"
WIDE_VIS="$(printf '%s' "$WIDE" | strip_ansi)"
wide_vis_len=${#WIDE_VIS}
# Wrapping would show up as a content string carrying an embedded newline just
# as much as it would as two output lines, so both are checked.
check "truncation: a row's content carries no embedded newline" \
  "$(content_for tt-1 | grep -c '')" "1"

run_sub "$(payload 28 "$LONGTASK")"
NARROW="$(content_for tt-1)"
NARROW_VIS="$(printf '%s' "$NARROW" | strip_ansi)"
narrow_vis_len=${#NARROW_VIS}

check "truncation: the wide render really is longer than the narrow columns (non-vacuity)" \
  "$([ "$wide_vis_len" -gt 28 ] && echo yes || echo no)" "yes"
check "truncation: a narrow render still emits exactly one line per task (not wrapped)" \
  "$(count_lines)" "1"
check "truncation: the narrow row's visible width is within columns" \
  "$([ "$narrow_vis_len" -le 28 ] && echo yes || echo no)" "yes"
check "truncation: the narrow row is not empty" \
  "$([ "$narrow_vis_len" -gt 0 ] && echo yes || echo no)" "yes"
check "truncation: the narrow row is shorter than the wide one" \
  "$([ "$narrow_vis_len" -lt "$wide_vis_len" ] && echo yes || echo no)" "yes"
check "truncation: a wide render is not truncated (it fits)" \
  "$([ "$wide_vis_len" -le 200 ] && echo yes || echo no)" "yes"

# Every row of a multi-task narrow render is bounded, not just the first.
run_sub "$(payload 30 "$LONGTASK" "$T_ALPHA" "$T_BETA")"
check "truncation: three tasks at 30 columns emit three lines, each within columns" \
  "$(over=0
     for id in tt-1 ta-1 tb-2; do
       v="$(content_for "$id" | strip_ansi)"
       [ "${#v}" -gt 30 ] && over=1
     done
     printf '%s:%s' "$(count_lines)" "$over")" "3:0"

# ============================================================================
# Invariant: process budget -- one jq over the payload, no git, no per-row forks
#
# Measured with the PATH-shim harness render-budget.test.sh uses: one logging
# wrapper per external binary, each appending its name to $SHIM_LOG then
# exec-ing the real one. `type -P` (not `command -v`) for the reason that suite
# documents: a shell FUNCTION named grep would otherwise make the shim exec
# itself in a fork loop.
# ============================================================================
SHIM_BIN="$TMPROOT/shim-bin"; mkdir -p "$SHIM_BIN"
for _tool in jq git awk sed grep cat head tail tr cut wc basename dirname \
             printf date stat mktemp sort uniq expr fold; do
  _real=$(type -P "$_tool" 2>/dev/null) || continue
  # shellcheck disable=SC2016  # the shim's own $@ and $SHIM_LOG must stay literal
  printf '#!/bin/bash\necho "%s" >> "${SHIM_LOG:-/dev/null}"\nexec "%s" "$@"\n' \
    "$_tool" "$_real" > "$SHIM_BIN/$_tool"
  chmod +x "$SHIM_BIN/$_tool"
done
REAL_BASH=$(type -P bash)
SHIM_LOG="$TMPROOT/shim.log"

budget_run() { # payload
  : > "$SHIM_LOG"
  printf '%s' "$1" \
    | env -i PATH="$SHIM_BIN" HOME="$TMPROOT" SHIM_LOG="$SHIM_LOG" \
        "$REAL_BASH" "$SUBAGENT" >"$OUT" 2>"$ERR"
  RC=$?
}
shim_count() { # [tool]
  # `grep -c` prints 0 AND exits 1 on no match, so the fallback would append a
  # second 0; head -n1 keeps the first (and only real) count either way.
  if [ -n "${1:-}" ]; then { grep -cxF "$1" "$SHIM_LOG" 2>/dev/null || echo 0; } | head -n1
  else wc -l < "$SHIM_LOG" 2>/dev/null | tr -d ' '; fi
}

FIVE_TASKS=(
  "$(task tp-1 rowone Opus high 200000 150000 /tmp/wt/agent-one)"
  "$(task tp-2 rowtwo Sonnet low 200000 40000 /tmp/wt/agent-two)"
  "$(task tp-3 rowthree Haiku medium 200000 90000 /tmp/wt/agent-three)"
  "$(task tp-4 rowfour Opus xhigh 200000 20000 /tmp/wt/agent-four)"
  "$(task tp-5 rowfive Sonnet high 200000 180000 /tmp/wt/agent-five)"
)

budget_run "$(payload 200 "${FIVE_TASKS[@]}")"
five_total=$(shim_count)
five_jq=$(shim_count jq)
five_git=$(shim_count git)
# Non-vacuity: a budget met by rendering nothing is not evidence.
check "budget: the measured render really emitted all five rows" "$(count_lines)" "5"
check "budget: exactly one jq over the payload" "${five_jq:-99}" "1"
check "budget: no git" "${five_git:-99}" "0"

budget_run "$(payload 200 "$(task tp-1 rowone Opus high 200000 150000 /tmp/wt/agent-one)")"
one_total=$(shim_count)
check "budget: the one-row comparison render really emitted its row" "$(count_lines)" "1"
check "budget: five rows cost no more external commands than one (no per-row forks)" \
  "${five_total:-99}" "${one_total:-0}"
check "budget: the whole render stays within a generous 6-command bound" \
  "$([ "${five_total:-99}" -le 6 ] && echo yes || echo no)" "yes"

# ============================================================================
# Invariants: bash 3.2 compatibility, checked mechanically over the file
# ============================================================================
check "bash 3.2: the script parses" \
  "$(bash -n "$SUBAGENT" 2>/dev/null && echo ok || echo no)" "ok"
check "bash 3.2: no associative arrays" \
  "$(grep -qE 'declare[[:space:]]+-[A-Za-z]*A' "$SUBAGENT" && echo yes || echo no)" "no"
check "bash 3.2: no case-modification expansions" \
  "$(grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(\^\^|,,)' "$SUBAGENT" && echo yes || echo no)" "no"
check "bash 3.2: no mapfile/readarray" \
  "$(grep -qE '\b(mapfile|readarray)\b' "$SUBAGENT" && echo yes || echo no)" "no"
check "POSIX awk only: no gawk-only functions" \
  "$(grep -qE '\b(gensub|asorti?|strtonum|systime)\(' "$SUBAGENT" && echo yes || echo no)" "no"
check "the renderer is an executable script" \
  "$([ -x "$SUBAGENT" ] && echo yes || echo no)" "yes"
# The "reuses lib/burn-theme.sh" invariant is asserted BEHAVIOURALLY, by the
# colour checks above: every expected opener in this suite is produced by
# calling that file's own burn_model_color / burn_ctx_color, so a renderer
# carrying its own copy of the palette passes only for as long as the two agree
# -- and fails the moment a threshold moves. A grep for the source line would
# be an internals check and would pass on the stub, which only mentions the
# file in its docblock.

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
