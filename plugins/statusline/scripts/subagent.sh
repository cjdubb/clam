#!/bin/bash
#
# Agent-panel row renderer for the `subagentStatusLine` settings key.
#
# Contract: B10 subagent-line (plan 001-statusline-glance-uplift)
#
# Behavior:
#   Renders the agent-panel row body for each visible subagent from THAT
#   SUBAGENT'S OWN fields — never the orchestrator's. That distinction is the
#   entire reason this file exists: the `statusLine` payload has no subagent
#   notion at all, so a script wired there can only ever show the main
#   session's model, effort and directory no matter which row is selected.
#   `subagentStatusLine` is the documented surface that carries per-task
#   state, and this is the script for it.
#
#   Per row: the task's name, its `model` in B03's flat colour
#   (burn_model_color), its `effort`, the basename of its `cwd`, and its
#   context percentage from `tokenCount` over `contextWindowSize`, coloured by
#   the existing burn_ctx_color.
#
#   Emits one JSON line per row:
#     {"id": "<task id>", "content": "<row body>"}
#
# Inputs:
#   One JSON object on stdin containing the base hook fields, `columns` (the
#   usable row width), and a `tasks` array. Per task: id, name, type, status,
#   description, label, startTime, model, effort, contextWindowSize,
#   tokenCount, tokenSamples, cwd.
#
# Outputs:
#   One JSON line per row on stdout, in the documented shape. `content` is
#   rendered as-is by Claude Code, including ANSI and OSC 8. A row this script
#   chooses NOT to override is omitted entirely, which keeps that row's
#   default rendering rather than blanking it.
#
# Errors:
#   Never writes to stderr and never exits non-zero on bad input. A malformed
#   payload emits no lines, which leaves every row at its default rendering.
#   Missing jq does the same. A status line that fails loudly is worse than
#   one that fails invisibly.
#
# Invariants:
#   - Runs once per refresh tick with EVERY visible row in one payload, so it
#     stays cheap: one jq over the payload, no git, no per-row forks.
#   - Reuses lib/burn-theme.sh, so a subagent row and line 2 can never
#     disagree about a model's colour.
#   - bash 3.2 compatible (macOS ships /bin/bash 3.2.57).
#   - Output respects `columns` rather than assuming a width.
#
# Edge cases:
#   - `effort` absent — the DOCUMENTED case where the subagent inherits the
#     session's effort level: render NO effort rather than the session's
#     value. Showing the inherited value here would reintroduce exactly the
#     defect this block fixes.
#   - `model` or `contextWindowSize` absent, which the docs state happens
#     before the task's model resolves: omit the affected figure, keep the
#     rest of the row.
#   - An empty `tasks` array: emit nothing.
#   - A `cwd` equal to the orchestrator's: still rendered from the task's own
#     field. Correctness here is about provenance, not about difference.
#   - A row body longer than `columns`: truncated rather than wrapped.

# Everything below is silent by construction: no diagnostic is ever written,
# and every exit is 0. A status line that fails loudly is worse than one that
# fails invisibly.

_sl_sub_dir="${BASH_SOURCE[0]%/*}"
[ "$_sl_sub_dir" = "${BASH_SOURCE[0]}" ] && _sl_sub_dir="."

# The palette is burn-theme.sh's, never this file's. Without it there is no
# colour decision to make, so the rows stay at their default rendering.
# shellcheck source=../lib/burn-theme.sh
# shellcheck disable=SC1091  # path is resolved at runtime, relative to this file
. "$_sl_sub_dir/../lib/burn-theme.sh" 2>/dev/null || exit 0

# jq is the ONE external command this renderer spends. Absent, it degrades
# exactly as a malformed payload does.
command -v jq >/dev/null 2>&1 || exit 0

# Two lookup tables, both built by CALLING the theme's own functions, so a
# threshold or code change there moves this renderer with it. Each table is
# built in a single subshell: burn_* functions fork nothing, and the render
# budget has no room for a fork per lookup.
#
#   _sl_sub_mcolors  five openers, in burn_model_color's documented match
#                    order: haiku, sonnet, opus, fable, then the fallback.
#   _sl_sub_ccolors  101 openers, one per whole percent 0..100; jq indexes it
#                    with the row's own occupancy, clamped at both ends (the
#                    bands are flat outside that range, so clamping cannot
#                    change a colour).
_sl_sub_mcolors=$(
  burn_model_color haiku; printf ' '
  burn_model_color sonnet; printf ' '
  burn_model_color opus; printf ' '
  burn_model_color fable; printf ' '
  burn_model_color ''
)
_sl_sub_ccolors=$(
  _i=0
  while [ "$_i" -le 100 ]; do
    burn_ctx_color "$_i"
    [ "$_i" -lt 100 ] && printf ' '
    _i=$((_i + 1))
  done
)

# One jq over the whole payload renders every row: the per-row work is a jq
# loop, not a shell loop, so five rows cost exactly what one does. Output is
# captured rather than streamed so a jq that dies mid-parse cannot leave a
# half-written line on stdout.
#
# Row body: NAME  MODEL  EFFORT  DIR  PCT%, each field from the TASK's own
# object and omitted entirely when its source field is absent. Truncation is
# by VISIBLE width: the fold below spends the column budget on text only, and
# each coloured piece carries its own reset, so a clipped row never leaks
# colour.
# shellcheck disable=SC2016
_sl_sub_out=$(jq -c \
  --arg mcolors "$_sl_sub_mcolors" \
  --arg ccolors "$_sl_sub_ccolors" '
  def clip($limit):
    reduce .[] as $p ({rem: $limit, out: ""};
      if .rem <= 0 then .
      else ($p.t[0:.rem]) as $piece
        | .out += (if $p.c == "" then $piece else $p.c + $piece + "\u001b[0m" end)
        | .rem -= ($piece | length)
      end)
    | .out;
  def str($v): if ($v | type) == "string" and ($v | length) > 0 then $v else null end;
  ($mcolors | split(" ")) as $MC
  | ($ccolors | split(" ")) as $CC
  | (if (.columns | type) == "number" and .columns >= 4
     then (.columns | floor) else 120 end) as $W
  | (if (.tasks | type) == "array" then .tasks else [] end)
  | .[]
  | select(type == "object")
  | . as $t
  | select(($t.id | type) == "string" and ($t.id | length) > 0)
  | str($t.name) as $name
  | str($t.model) as $model
  | str($t.effort) as $effort
  | (str($t.cwd) | if . == null then null
       else (split("/") | map(select(length > 0)) | last) end) as $dir
  | (if ($t.contextWindowSize | type) == "number" and $t.contextWindowSize > 0
        and ($t.tokenCount | type) == "number"
     then (($t.tokenCount * 100 / $t.contextWindowSize) | floor)
     else null end) as $pct
  | (if $model == null then null
     else ($model | ascii_downcase) as $m
       | if ($m | index("haiku")) then $MC[0]
         elif ($m | index("sonnet")) then $MC[1]
         elif ($m | index("opus")) then $MC[2]
         elif ($m | index("fable")) then $MC[3]
         else $MC[4] end
     end) as $mcolor
  | (if $pct == null then null
     else $CC[if $pct < 0 then 0 elif $pct > 100 then 100 else $pct end]
     end) as $ccolor
  | [ (if $name != null then {t: $name, c: ""} else empty end),
      (if $model != null then {t: $model, c: $mcolor} else empty end),
      (if $effort != null then {t: $effort, c: ""} else empty end),
      (if $dir != null then {t: $dir, c: ""} else empty end),
      (if $pct != null then {t: "\($pct)%", c: $ccolor} else empty end) ]
  | (to_entries
     | map(if .key == 0 then [.value] else [{t: "  ", c: ""}, .value] end)
     | add // []) as $parts
  | ($parts | clip($W)) as $content
  | select(($content | length) > 0)
  | {id: $t.id, content: $content}
' 2>/dev/null) || exit 0

[ -n "$_sl_sub_out" ] && printf '%s\n' "$_sl_sub_out"
exit 0
