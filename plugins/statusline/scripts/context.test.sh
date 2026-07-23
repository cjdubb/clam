#!/bin/bash
# Functional test for context.sh rendering: the model+effort line, the removal
# of the per-turn "Turn:" row, the ~-for-$HOME path shortening, the decluttered
# context line (no redundant "Total:" segment), and clean block termination (no
# trailing decorative "$" prompt, no dangling blank line). Also covers the
# tri-state Ctx-usage colour (green/orange/red by occupancy + idle staleness),
# the dimmed "(NN%)" suffix, the atomic .local/.ctx-status.json publish, and
# the clam-mode segment sourced from .local/MODE (mode-first ordering, teal
# colour, sanitization, and subset separator logic).
# Renders context.sh against synthetic statusLine JSON payloads (hermetic: temp
# cwd with no git/.local, temp ccost dirs) and asserts on the output (ANSI
# stripped for text, raw for colour-code checks).
# Run: bash general/statusline/context.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="$SCRIPT_DIR/context.sh"
source "$SCRIPT_DIR/../lib/platform.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# The rendered cwd is a plain temp dir: not a git repo (no branch / PR / State
# segments) and no .local (no cache-refresh fork), so the render is hermetic.
WD="$TMPROOT/wd"; mkdir -p "$WD"

# Never inherit the harness's own effort; each case sets it explicitly.
unset CLAUDE_EFFORT

ESC=$(printf '\033')
FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Render context.sh for a JSON payload, ANSI stripped. ccost dirs are pointed
# at empty temp dirs so the cost line is deterministic and inert.
render() { # json
  printf '%s' "$1" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        bash "$CONTEXT" 2>/dev/null \
    | sed -E "s/${ESC}\\[[0-9;]*m//g"
}

# Like render() but WITHOUT the ANSI strip, so colour-code assertions can match
# the raw 256-colour escape sequences (e.g. the Ctx-usage tier colour).
render_raw() { # json
  printf '%s' "$1" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        bash "$CONTEXT" 2>/dev/null
}

# Build a statusLine JSON payload for the Ctx-usage cases.
ctx_json() { # current_dir tokens transcript_path
  printf '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"%s"},"context_window":{"context_window_size":1000000,"total_input_tokens":%s},"transcript_path":"%s"}' \
    "$1" "$2" "$3"
}

# Set a file's mtime to N seconds in the past (BSD date -r / GNU date -d @), so
# the render sees a known idle age from the transcript mtime.
set_mtime_ago() { # file seconds_ago
  local f="$1" secs="$2" epoch stamp
  epoch=$(( $(date +%s) - secs ))
  stamp=$(date -r "$epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$epoch" +%Y%m%d%H%M.%S 2>/dev/null)
  touch -t "$stamp" "$f"
}

# Assert the Ctx-used numerator renders in an expected 256-colour code. Matches
# the raw escape immediately before the numerator's leading digits, pinning the
# Ctx segment specifically (colour + value prefix, thousands-separator agnostic).
ctx_color_is() { # json color digits label
  check "$4" \
    "$(render_raw "$1" | grep -qaF "${ESC}[38;5;$2m$3" && echo yes || echo no)" "yes"
}

ctx='"context_window":{"context_window_size":1000000,"total_input_tokens":145230}'

# 1. Effort from the JSON payload (.effort.level), model present.
json_json_effort="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"max\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\"}"
out=$(render "$json_json_effort")
check "effort from JSON renders 'Opus · max effort' on its own line" \
  "$(printf '%s\n' "$out" | grep -qxF 'Opus · max effort' && echo yes || echo no)" "yes"
check "Turn row removed" \
  "$(printf '%s\n' "$out" | grep -q 'Turn:' && echo present || echo absent)" "absent"
check "Ctx line renders the meter (Ctx used: <used> / <budget> (NN%))" \
  "$(printf '%s\n' "$out" | grep -qE '^Ctx used: [0-9,]+ / [0-9,]+ \([0-9]+%\)$' && echo yes || echo no)" "yes"
check "redundant Total: segment dropped from the Ctx line" \
  "$(printf '%s\n' "$out" | grep -q 'Total:' && echo present || echo absent)" "absent"

# 2. Effort falls back to $CLAUDE_EFFORT when .effort is absent from the JSON.
json_no_effort="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\"}"
out=$(CLAUDE_EFFORT=high render "$json_no_effort")
check "effort falls back to \$CLAUDE_EFFORT (Opus · high effort)" \
  "$(printf '%s\n' "$out" | grep -qxF 'Opus · high effort' && echo yes || echo no)" "yes"

# 3. Effort fully absent (no .effort, no env): model-only line, no 'effort' text.
out=$(render "$json_no_effort")
check "model-only line when effort fully absent" \
  "$(printf '%s\n' "$out" | grep -qxF 'Opus' && echo yes || echo no)" "yes"
check "no 'effort' text when effort fully absent" \
  "$(printf '%s\n' "$out" | grep -q 'effort' && echo present || echo absent)" "absent"

# 4. Model AND effort both absent: the whole line is omitted (no stray blank).
json_bare="{\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\"}"
out=$(render "$json_bare")
check "no 'Opus' when model absent" \
  "$(printf '%s\n' "$out" | grep -q 'Opus' && echo present || echo absent)" "absent"
check "no 'effort' when model+effort absent" \
  "$(printf '%s\n' "$out" | grep -q 'effort' && echo present || echo absent)" "absent"
check "Ctx line still the second output line when model line omitted" \
  "$(printf '%s\n' "$out" | sed -n '2p' | grep -q '^Ctx used:' && echo yes || echo no)" "yes"

# 5. Effort-only: model absent, effort present (via env) renders "<level> effort"
#    with no leading separator (the separator is gated on model_name).
out=$(CLAUDE_EFFORT=high render "$json_bare")
check "effort-only line when model absent (no leading separator)" \
  "$(printf '%s\n' "$out" | grep -qxF 'high effort' && echo yes || echo no)" "yes"

# 6. Precedence: JSON .effort.level wins over $CLAUDE_EFFORT when both are set.
out=$(CLAUDE_EFFORT=low render "$json_json_effort")
check "JSON .effort.level takes precedence over \$CLAUDE_EFFORT (max beats low)" \
  "$(printf '%s\n' "$out" | grep -qxF 'Opus · max effort' && echo yes || echo no)" "yes"

# 7. Path shortening: $HOME is collapsed to a literal ~, with the remainder of
#    the path preserved. Uses a controlled HOME with a cwd beneath it (the temp
#    WD above is outside $HOME, so it exercises only the pass-through case).
json_home="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"/fakehome/github/wt\"},$ctx,\"transcript_path\":\"\"}"
out=$(HOME=/fakehome render "$json_home")
check "path collapses \$HOME to ~ (home prefix, remainder preserved)" \
  "$(printf '%s\n' "$out" | sed -n '1p' | grep -qxF '~/github/wt' && echo yes || echo no)" "yes"

# 7b. Exact-$HOME match (the "$HOME" case-branch with no trailing subpath)
#     collapses to just "~".
json_home_exact="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"/fakehome\"},$ctx,\"transcript_path\":\"\"}"
out=$(HOME=/fakehome render "$json_home_exact")
check "path collapses an exact \$HOME to just ~" \
  "$(printf '%s\n' "$out" | sed -n '1p' | grep -qxF '~' && echo yes || echo no)" "yes"

# 8. Clean termination: the decorative "$" prompt line is gone, and the last
#    rendered line is the Cost line, so there is no trailing blank line either.
out=$(render "$json_json_effort")
check "no decorative \$ prompt line remains" \
  "$(printf '%s\n' "$out" | grep -qE '^[$] ?$' && echo present || echo absent)" "absent"
check "status block ends on the Cost line (no trailing blank line)" \
  "$(printf '%s\n' "$out" | tail -n1 | grep -q '^Cost:' && echo yes || echo no)" "yes"

# 9. Tri-state Ctx-usage colour by occupancy + idle staleness. Budget is 300000
#    (the render/render_raw env). Colours: 40 green (small, or big-but-warm),
#    208 orange (big & cooling >=30 min), 196 red (big & cold >=45 min, or over
#    budget). Idle is driven by a real transcript file's mtime.
TR="$TMPROOT/tr.jsonl"; echo '{}' > "$TR"

# 9a. Small (145,230/300,000 = 48% < 60% floor): green regardless of idle.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 145230 "$TR")" 40 145 \
  "Ctx green (40) when occupancy is small (pct<60)"

# 9b. Big but warm (200,000 = 66%, transcript fresh so idle ~0): still green —
#     staleness only escalates a big session once it starts cooling.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 200000 "$TR")" 40 200 \
  "Ctx green (40) when big but warm (pct>=60, idle<1800)"

# 9c. Big and cooling (66%, ~33 min idle): orange.
set_mtime_ago "$TR" 2000
ctx_color_is "$(ctx_json "$WD" 200000 "$TR")" 208 200 \
  "Ctx orange (208) when big and cooling (idle>=1800)"

# 9d. Big and cold (66%, ~50 min idle): red.
set_mtime_ago "$TR" 3000
ctx_color_is "$(ctx_json "$WD" 200000 "$TR")" 196 200 \
  "Ctx red (196) when big and cold (idle>=2700)"

# 9e. Over budget (350,000 > 300,000) with a FRESH transcript: red regardless of
#     idle — over-budget is always cold.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 350000 "$TR")" 196 350 \
  "Ctx red (196) when over budget (any idle)"

# 9f. Empty transcript ("") must NOT read as infinitely cold: a big session
#     (66%) with no transcript stays green (idle forced to 0), not red.
ctx_color_is "$(ctx_json "$WD" 200000 "")" 40 200 \
  "Ctx green (40) when big with an empty transcript (no false cold)"

# 9g. Missing transcript file (path set, file absent): same guard → green.
ctx_color_is "$(ctx_json "$WD" 200000 "$TMPROOT/does-not-exist.jsonl")" 40 200 \
  "Ctx green (40) when big with a missing transcript file (no false cold)"

# 9h. The dimmed "(NN%)" suffix carries the integer floor of 100*used/budget and
#     is NOT clamped at 100 (350,000/300,000 = 116%).
out=$(render "$(ctx_json "$WD" 350000 "$TR")")
check "Ctx percent suffix is the unclamped floor (116%) on overrun" \
  "$(printf '%s\n' "$out" | grep -qE '^Ctx used: .* \(116%\)$' && echo yes || echo no)" "yes"

# 9i. Exact-budget boundary (300,000 tokens == 300,000 budget, exactly 100%)
#     with a FRESH transcript: red. Contrasts with 9e's used > budget case and
#     pins the `-ge` comparison in context.sh — a regression to `-gt` would
#     leave this exact-equal case green instead of red.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 300000 "$TR")" 196 300 \
  "Ctx red (196) at the exact-budget boundary (used == budget)"

# 9j. Occupancy floor gates staleness: small occupancy (145,230/300,000 = 48%
#     < 60% floor) with an OLD transcript (~50 min idle, same age as 9d's red
#     case) stays green. Extends 9a's "regardless of idle" claim by actually
#     driving idle into the cold band, proving small sessions can't be pushed
#     into orange/red by staleness alone.
set_mtime_ago "$TR" 3000
ctx_color_is "$(ctx_json "$WD" 145230 "$TR")" 40 145 \
  "Ctx green (40) when occupancy is small despite an old/stale transcript"

# 10. Atomic .local/.ctx-status.json publish in a git worktree with a .local dir.
GWD="$TMPROOT/gitwd"; mkdir -p "$GWD/.local"; git -C "$GWD" init -q >/dev/null 2>&1
# Keep the render hermetic: a fresh (<120s) refresh lock makes the render-time
# fork guard skip, so no pr-status / git-sync refreshers spawn during the test.
touch "$GWD/.local/.pr-status-refresh.lock" "$GWD/.local/.git-sync-refresh.lock"
GTR="$GWD/transcript.jsonl"; echo '{}' > "$GTR"
set_mtime_ago "$GTR" 2000   # ~33 min idle → big (66%) & cooling → level "warn"
g_mtime=$(clam_mtime_epoch "$GTR")
render "$(ctx_json "$GWD" 200000 "$GTR")" >/dev/null 2>&1
CJ="$GWD/.local/.ctx-status.json"

check "ctx-status.json is published in a git worktree with .local" \
  "$([ -f "$CJ" ] && echo yes || echo no)" "yes"
check "ctx-status.json is valid JSON" \
  "$(jq -e . "$CJ" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "ctx-status.json context_tokens field" \
  "$(jq -r '.context_tokens' "$CJ" 2>/dev/null)" "200000"
check "ctx-status.json budget field" \
  "$(jq -r '.budget' "$CJ" 2>/dev/null)" "300000"
check "ctx-status.json used_percentage field" \
  "$(jq -r '.used_percentage' "$CJ" 2>/dev/null)" "66"
check "ctx-status.json level matches the rendered tier (warn)" \
  "$(jq -r '.level' "$CJ" 2>/dev/null)" "warn"
check "ctx-status.json last_activity_epoch = transcript mtime" \
  "$(jq -r '.last_activity_epoch' "$CJ" 2>/dev/null)" "$g_mtime"
check "ctx-status.json idle_seconds is in the cooling band [1800,2700)" \
  "$(idle=$(jq -r '.idle_seconds' "$CJ" 2>/dev/null); { [ "${idle:-0}" -ge 1800 ] && [ "${idle:-0}" -lt 2700 ]; } && echo yes || echo no)" "yes"
check "ctx-status.json fetched_at is RFC3339 UTC (…Z)" \
  "$(jq -r '.fetched_at' "$CJ" 2>/dev/null | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' && echo yes || echo no)" "yes"

# 11. No .ctx-status.json is written when the cwd has no .local (the plain temp
#     WD is not a git repo → $toplevel empty → the write is gated out).
check "no ctx-status.json written when cwd has no .local dir" \
  "$([ -e "$WD/.local/.ctx-status.json" ] && echo present || echo absent)" "absent"

# 12. Clam-mode segment from .local/MODE, rendered FIRST on the mode/model/
#     effort line. Fixture mirrors test 10: real git worktree with .local and
#     pre-touched refresh locks (hermetic, no background refreshers spawn), and
#     no .local/TODO.md so no State segment renders.
MWD="$TMPROOT/modewd"; mkdir -p "$MWD/.local"; git -C "$MWD" init -q >/dev/null 2>&1
touch "$MWD/.local/.pr-status-refresh.lock" "$MWD/.local/.git-sync-refresh.lock"
json_mode_full="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"max\"},\"workspace\":{\"current_dir\":\"$MWD\"},$ctx,\"transcript_path\":\"\"}"
json_mode_bare="{\"workspace\":{\"current_dir\":\"$MWD\"},$ctx,\"transcript_path\":\"\"}"

# 12a. MODE=Build (trailing newline, as /start writes it) + model + effort.
printf 'Build\n' > "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "mode renders first: 'Build · Opus · max effort'" \
  "$(printf '%s\n' "$out" | grep -qxF 'Build · Opus · max effort' && echo yes || echo no)" "yes"

# 12b. Internal space survives sanitization (only leading/trailing trimmed).
printf 'Go Commando\n' > "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "internal space kept: 'Go Commando · Opus · max effort'" \
  "$(printf '%s\n' "$out" | grep -qxF 'Go Commando · Opus · max effort' && echo yes || echo no)" "yes"

# 12c. Git worktree with .local but NO MODE file: line unchanged from today.
rm -f "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "no MODE file leaves 'Opus · max effort' unchanged" \
  "$(printf '%s\n' "$out" | grep -qxF 'Opus · max effort' && echo yes || echo no)" "yes"

# 12d. Whitespace-only MODE trims to empty: segment absent.
printf '   \n' > "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "whitespace-only MODE drops the segment ('Opus · max effort')" \
  "$(printf '%s\n' "$out" | grep -qxF 'Opus · max effort' && echo yes || echo no)" "yes"

# 12e. Mode-only payload (no model key, no effort key/env): bare mode on line 2
#      (line 1 is the path line) with no dangling separator.
printf 'Build\n' > "$MWD/.local/MODE"
out=$(render "$json_mode_bare")
check "mode-only payload renders exactly 'Build'" \
  "$(printf '%s\n' "$out" | grep -qxF 'Build' && echo yes || echo no)" "yes"
check "mode-only line carries no · separator" \
  "$(printf '%s\n' "$out" | sed -n '2p' | grep -qF '·' && echo present || echo absent)" "absent"

# 12f. Mode + effort (env fallback), no model: one separator between the two.
out=$(CLAUDE_EFFORT=high render "$json_mode_bare")
check "mode + effort (no model) renders 'Build · high effort'" \
  "$(printf '%s\n' "$out" | grep -qxF 'Build · high effort' && echo yes || echo no)" "yes"

# 12g. Mode colour: teal (256-colour 37), distinct from the model purple (93).
check "mode renders in teal (38;5;37)" \
  "$(render_raw "$json_mode_full" | grep -qaF "${ESC}[38;5;37mBuild" && echo yes || echo no)" "yes"

# 12h. Sanitization: an ESC byte inside the word is stripped before rendering
#      (no escape-sequence injection from a crafted MODE file), and an
#      oversized single-line value is capped at its first 24 characters.
printf 'Bu\033ild' > "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "ESC byte inside MODE is stripped ('Build · Opus · max effort')" \
  "$(printf '%s\n' "$out" | grep -qxF 'Build · Opus · max effort' && echo yes || echo no)" "yes"
printf 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234\n' > "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "oversized MODE is capped at its first 24 chars" \
  "$(printf '%s\n' "$out" | grep -qxF 'ABCDEFGHIJKLMNOPQRSTUVWX · Opus · max effort' && echo yes || echo no)" "yes"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
