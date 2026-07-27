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

# Pinned for render()/render_raw() below: a cache dir under $TMPROOT (never
# the real $HOME/.claude/.statusline-cache) with caching disabled (TTL 0), so
# the pre-existing suite exercises fresh/live-equivalent behavior unaffected
# by the B01 cache layer. See the B01 helpers comment further down for why.
LEGACY_CACHE_DIR="$TMPROOT/legacy-cache"

# Render context.sh for a JSON payload, ANSI stripped. ccost dirs are pointed
# at empty temp dirs so the cost line is deterministic and inert.
render() { # json
  printf '%s' "$1" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$LEGACY_CACHE_DIR" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        bash "$CONTEXT" 2>/dev/null \
    | sed -E "s/${ESC}\\[[0-9;]*m//g"
}

# Like render() but WITHOUT the ANSI strip, so colour-code assertions can match
# the raw 256-colour escape sequences (e.g. the Ctx-usage tier colour).
render_raw() { # json
  printf '%s' "$1" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$LEGACY_CACHE_DIR" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
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

# --- B01 cache/TTL/process-count helpers ------------------------------------
# The B01 contract adds two knobs (CLAM_STATUSLINE_CACHE_DIR,
# CLAM_STATUSLINE_SEGMENT_TTL_SECONDS) and a per-session expensive-segment
# cache. render()/render_raw() above always pin these to a disabled state
# (temp cache dir, TTL 0) so every pre-existing test keeps exercising
# fresh/live-equivalent behavior unaffected by the new cache layer. The
# helpers below are for tests that specifically exercise caching.

# mk_wt(dir): a git worktree with .local and pre-touched refresh locks
# (hermetic: no pr-status/git-sync background refresh spawns during a test).
mk_wt() { # dir
  mkdir -p "$1/.local"
  git -C "$1" init -q >/dev/null 2>&1
  touch "$1/.local/.pr-status-refresh.lock" "$1/.local/.git-sync-refresh.lock"
}

# Block until the wall clock has just ticked over into a new second.
#
# Both sides of every freshness comparison are whole seconds: backdate_all
# stamps an mtime via `touch -t` (one-second granularity) and the renderer
# reads its own clock with `date +%s`, going stale at age >= TTL. Those two
# reads happen a few tens of milliseconds apart, so if the clock crosses an
# integer-second boundary in between, the computed age lands one second
# higher than the test asked for -- turning a deliberately-just-fresh bundle
# (age TTL-1) stale and failing the assertion. Starting each backdate at the
# top of a second leaves ~1s of headroom before that can happen. Only the
# "still warm" direction is at risk: an extra second can never make an
# already-stale bundle (age TTL) look fresh, since clocks do not run backward.
settle_to_second() {
  local t0
  t0=$(date +%s)
  while [ "$(date +%s)" = "$t0" ]; do
    sleep 0.02
  done
}

# Backdate (or, with a negative seconds_ago, future-date) every regular file
# under a directory. Used to age a cache bundle without sleeping out the full
# age in wall-clock time and without needing to know the bundle's internal
# filename. Waits for a second boundary first -- see settle_to_second.
backdate_all() { # dir seconds_ago
  local dir="$1" secs="$2" epoch stamp
  settle_to_second
  epoch=$(( $(date +%s) - secs ))
  stamp=$(date -r "$epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$epoch" +%Y%m%d%H%M.%S 2>/dev/null)
  find "$dir" -type f -exec touch -t "$stamp" {} + 2>/dev/null
}

# render_cached(json, cache_dir, ttl): like render(), but with the two new
# knobs as explicit positional arguments (never inherited/omitted) so a
# cache/TTL test can never accidentally fall through to the real ~/.claude
# cache.
render_cached() { # json cache_dir ttl
  printf '%s' "$1" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$2" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS="$3" \
        bash "$CONTEXT" 2>/dev/null \
    | sed -E "s/${ESC}\\[[0-9;]*m//g"
}

# --- PATH-shim harness: counts external processes context.sh spawns --------
# One logging wrapper per external binary the renderer may legitimately use
# (per the B01 brief), each appending its own name to $SHIM_LOG then exec-ing
# the REAL binary (resolved once, below, from the harness's own PATH).
# dirname/awk/grep are added beyond the brief's illustrative list because the
# CURRENT scaffold already calls them (platform.sh/states.sh/context.sh); a
# few common coreutils are added defensively for whatever the eventual
# implementation needs. A tool missing on this host is simply skipped.
SHIM_BIN="$TMPROOT/shim-bin"; mkdir -p "$SHIM_BIN"
for _tool in jq git date stat uname mktemp mv cat head tr sed cksum mkdir \
             touch nohup find xargs rm rmdir python3 bash dirname awk grep \
             basename wc cut sort; do
  _real=$(command -v "$_tool" 2>/dev/null) || continue
  printf '#!/bin/bash\necho "%s" >> "${SHIM_LOG:-/dev/null}"\nexec "%s" "$@"\n' \
    "$_tool" "$_real" > "$SHIM_BIN/$_tool"
  chmod +x "$SHIM_BIN/$_tool"
done
REAL_BASH=$(command -v bash)

# Shadow script tree: a symlinked context.sh + lib (so SCRIPT_DIR/_LIB_DIR
# resolution is untouched) alongside a FAKE ccost.sh that just logs its args
# to $CCOST_LOG and prints "0". This is the only way to observe "ccost.sh was
# invoked" from outside: ccost_script is resolved from $(dirname "$0"), a
# path, not a bare name, so a PATH shim alone can't intercept it.
SHADOW="$TMPROOT/shadow"; mkdir -p "$SHADOW/scripts" "$SHADOW/lib"
ln -s "$CONTEXT" "$SHADOW/scripts/context.sh"
ln -s "$SCRIPT_DIR/../lib/platform.sh" "$SHADOW/lib/platform.sh"
ln -s "$SCRIPT_DIR/../lib/states.sh" "$SHADOW/lib/states.sh"
ln -s "$SCRIPT_DIR/../lib/states.tsv" "$SHADOW/lib/states.tsv"
cat > "$SHADOW/scripts/ccost.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "${CCOST_LOG:-/dev/null}"
echo "0"
EOF
chmod +x "$SHADOW/scripts/ccost.sh"

SHIM_LOG="$TMPROOT/shim.log"
CCOST_LOG_FILE="$TMPROOT/ccost-invocations.log"
SENTINEL_PROJECTS_DIR="$TMPROOT/sentinel-projects"; mkdir -p "$SENTINEL_PROJECTS_DIR"

# render_shim(json, cache_dir, ttl, [extra "NAME=VALUE" env pairs...]): render
# through the shadow tree with the PATH shim active. Clears and repopulates
# $SHIM_LOG / $CCOST_LOG_FILE each call; discards the rendered text (these
# tests only care what got spawned, not the output bytes).
render_shim() { # json cache_dir ttl [extra_env...]
  local json="$1" cdir="$2" ttl="$3"; shift 3
  : > "$SHIM_LOG"; : > "$CCOST_LOG_FILE"
  printf '%s' "$json" \
    | env CLAUDE_PROJECTS_DIR="$SENTINEL_PROJECTS_DIR" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$cdir" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS="$ttl" \
        SHIM_LOG="$SHIM_LOG" CCOST_LOG="$CCOST_LOG_FILE" \
        PATH="$SHIM_BIN" \
        "$@" \
        "$REAL_BASH" "$SHADOW/scripts/context.sh" >/dev/null 2>&1
}

# shim_count(log_file, [tool]): total logged invocations, or just $tool's.
shim_count() { # log_file [tool]
  if [ -n "${2:-}" ]; then
    grep -cxF "$2" "$1" 2>/dev/null
  else
    wc -l < "$1" 2>/dev/null | tr -d ' '
  fi
}
# ------------------------------------------------------------------------

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

# === 13. Cache dir + TTL knobs =============================================
# Contract inputs: CLAM_STATUSLINE_CACHE_DIR (default $HOME/.claude/.statusline-cache,
# created on demand), CLAM_STATUSLINE_SEGMENT_TTL_SECONDS (default 5; <=0 disables
# cache serving; non-integer falls back to 5).

# 13a. Default cache dir path, when the knob is unset. FAKE_HOME keeps this
#      off the real ~/.claude even though the knob itself is deliberately
#      left unset (that's the point of the test).
FAKE_HOME="$TMPROOT/fakehome-cache"; mkdir -p "$FAKE_HOME"
DEFWD="$TMPROOT/def-cache-wd"; mkdir -p "$DEFWD"
defjson="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$DEFWD\"},$ctx,\"transcript_path\":\"\"}"
printf '%s' "$defjson" \
  | HOME="$FAKE_HOME" CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
      bash "$CONTEXT" >/dev/null 2>&1
check "default CLAM_STATUSLINE_CACHE_DIR is \$HOME/.claude/.statusline-cache (created on demand)" \
  "$([ -d "$FAKE_HOME/.claude/.statusline-cache" ] && echo yes || echo no)" "yes"

# 13b. Default TTL is 5s: a 4s-old bundle is still warm, a 5s-old bundle is
#      stale. Driven by whether a MODE-file change (a CACHED segment) shows.
DEFTTL_DIR="$TMPROOT/def-ttl-cache"
DEFTTL_WD="$TMPROOT/def-ttl-wd"; mk_wt "$DEFTTL_WD"
printf 'Build\n' > "$DEFTTL_WD/.local/MODE"
ttljson="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$DEFTTL_WD\"},$ctx,\"transcript_path\":\"\"}"
render_default_ttl() { # json  (CLAM_STATUSLINE_SEGMENT_TTL_SECONDS deliberately unset -> real default)
  printf '%s' "$1" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 CLAM_STATUSLINE_CACHE_DIR="$DEFTTL_DIR" \
        bash "$CONTEXT" 2>/dev/null \
    | sed -E "s/${ESC}\\[[0-9;]*m//g"
}
render_default_ttl "$ttljson" >/dev/null   # cold: bundle written with MODE=Build
printf 'Debug\n' > "$DEFTTL_WD/.local/MODE"
backdate_all "$DEFTTL_DIR" 4
out=$(render_default_ttl "$ttljson")
check "default TTL (5s): a 4s-old bundle is still warm ('Build' cached value kept)" \
  "$(printf '%s\n' "$out" | grep -qF 'Build · Opus' && echo yes || echo no)" "yes"
backdate_all "$DEFTTL_DIR" 5
out=$(render_default_ttl "$ttljson")
check "default TTL (5s): a 5s-old bundle is stale ('Debug' change now reflected)" \
  "$(printf '%s\n' "$out" | grep -qF 'Debug · Opus' && echo yes || echo no)" "yes"

# 13c. Explicit TTL override (2s): same boundary logic at the overridden value.
OVR_DIR="$TMPROOT/ovr-ttl-cache"
OVR_WD="$TMPROOT/ovr-ttl-wd"; mk_wt "$OVR_WD"
printf 'Build\n' > "$OVR_WD/.local/MODE"
ovrjson="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$OVR_WD\"},$ctx,\"transcript_path\":\"\"}"
render_cached "$ovrjson" "$OVR_DIR" 2 >/dev/null
printf 'Debug\n' > "$OVR_WD/.local/MODE"
backdate_all "$OVR_DIR" 1
out=$(render_cached "$ovrjson" "$OVR_DIR" 2)
check "overridden TTL=2s: a 1s-old bundle is still warm ('Build' kept)" \
  "$(printf '%s\n' "$out" | grep -qF 'Build · Opus' && echo yes || echo no)" "yes"
backdate_all "$OVR_DIR" 2
out=$(render_cached "$ovrjson" "$OVR_DIR" 2)
check "overridden TTL=2s: a 2s-old bundle is stale ('Debug' reflected)" \
  "$(printf '%s\n' "$out" | grep -qF 'Debug · Opus' && echo yes || echo no)" "yes"

# 13d. TTL <= 0 disables cache serving entirely: every render rebuilds, so a
#      MODE change is reflected on the VERY NEXT render with no aging needed.
ZERO_DIR="$TMPROOT/zero-ttl-cache"
ZERO_WD="$TMPROOT/zero-ttl-wd"; mk_wt "$ZERO_WD"
printf 'Build\n' > "$ZERO_WD/.local/MODE"
zerojson="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$ZERO_WD\"},$ctx,\"transcript_path\":\"\"}"
render_cached "$zerojson" "$ZERO_DIR" 0 >/dev/null
printf 'Debug\n' > "$ZERO_WD/.local/MODE"
out=$(render_cached "$zerojson" "$ZERO_DIR" 0)
check "TTL<=0 disables caching: an un-aged bundle is still rebuilt ('Debug' reflected immediately)" \
  "$(printf '%s\n' "$out" | grep -qF 'Debug · Opus' && echo yes || echo no)" "yes"

# 13e. Non-integer TTL falls back to the 5s default (not "always cold", not
#      "never expires") -- same 4s-warm/5s-stale boundary as 13b, reached via
#      an explicit garbage value instead of an unset variable.
BAD_DIR="$TMPROOT/bad-ttl-cache"
BAD_WD="$TMPROOT/bad-ttl-wd"; mk_wt "$BAD_WD"
printf 'Build\n' > "$BAD_WD/.local/MODE"
badjson="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$BAD_WD\"},$ctx,\"transcript_path\":\"\"}"
render_cached "$badjson" "$BAD_DIR" "not-a-number" >/dev/null
printf 'Debug\n' > "$BAD_WD/.local/MODE"
backdate_all "$BAD_DIR" 4
out=$(render_cached "$badjson" "$BAD_DIR" "not-a-number")
check "non-integer TTL falls back to 5s: a 4s-old bundle is still warm ('Build' kept)" \
  "$(printf '%s\n' "$out" | grep -qF 'Build · Opus' && echo yes || echo no)" "yes"
backdate_all "$BAD_DIR" 5
out=$(render_cached "$badjson" "$BAD_DIR" "not-a-number")
check "non-integer TTL falls back to 5s: a 5s-old bundle is stale ('Debug' reflected)" \
  "$(printf '%s\n' "$out" | grep -qF 'Debug · Opus' && echo yes || echo no)" "yes"

# === 14. Cache key derivation (transcript_path, fallback: cwd) =============

# 14a. Same cwd, different transcript_path -> independent bundles (a session
#      is never handed another session's cached segments just because they
#      share a worktree).
KEY_WD="$TMPROOT/key-wd"; mk_wt "$KEY_WD"
KEY_DIR="$TMPROOT/key-cache"
KEY_TR_A="$TMPROOT/key-a.jsonl"; echo '{}' > "$KEY_TR_A"
KEY_TR_B="$TMPROOT/key-b.jsonl"; echo '{}' > "$KEY_TR_B"
printf 'Build\n' > "$KEY_WD/.local/MODE"
keyA="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$KEY_WD\"},$ctx,\"transcript_path\":\"$KEY_TR_A\"}"
keyB="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$KEY_WD\"},$ctx,\"transcript_path\":\"$KEY_TR_B\"}"
render_cached "$keyA" "$KEY_DIR" 5 >/dev/null
printf 'Debug\n' > "$KEY_WD/.local/MODE"
outA=$(render_cached "$keyA" "$KEY_DIR" 5)
outB=$(render_cached "$keyB" "$KEY_DIR" 5)
check "same cwd, different transcript_path: session A stays warm on its own bundle ('Build')" \
  "$(printf '%s\n' "$outA" | grep -qF 'Build · Opus' && echo yes || echo no)" "yes"
check "same cwd, different transcript_path: session B gets its own (cold) bundle, not A's ('Debug')" \
  "$(printf '%s\n' "$outB" | grep -qF 'Debug · Opus' && echo yes || echo no)" "yes"

# 14b. Missing transcript_path falls back to cwd as the key: two DIFFERENT
#      cwds with an empty transcript_path get independently-cached bundles
#      (not one shared "no transcript" bucket), and a repeated render at the
#      SAME cwd stays warm on its own bundle.
KEY2_WD_A="$TMPROOT/key2-wd-a"; mk_wt "$KEY2_WD_A"
KEY2_WD_B="$TMPROOT/key2-wd-b"; mk_wt "$KEY2_WD_B"
KEY2_DIR="$TMPROOT/key2-cache"
printf 'Alpha\n' > "$KEY2_WD_A/.local/MODE"
printf 'Bravo\n' > "$KEY2_WD_B/.local/MODE"
key2A="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$KEY2_WD_A\"},$ctx,\"transcript_path\":\"\"}"
key2B="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$KEY2_WD_B\"},$ctx,\"transcript_path\":\"\"}"
render_cached "$key2A" "$KEY2_DIR" 5 >/dev/null
render_cached "$key2B" "$KEY2_DIR" 5 >/dev/null
printf 'ChangedA\n' > "$KEY2_WD_A/.local/MODE"
printf 'ChangedB\n' > "$KEY2_WD_B/.local/MODE"
outA=$(render_cached "$key2A" "$KEY2_DIR" 5)
outB=$(render_cached "$key2B" "$KEY2_DIR" 5)
check "empty transcript_path falls back to cwd as key: worktree A independently warm ('Alpha')" \
  "$(printf '%s\n' "$outA" | grep -qF 'Alpha · Opus' && echo yes || echo no)" "yes"
check "empty transcript_path falls back to cwd as key: worktree B independently warm ('Bravo')" \
  "$(printf '%s\n' "$outB" | grep -qF 'Bravo · Opus' && echo yes || echo no)" "yes"

# 14c. transcript_path (when present) is the WHOLE key -- cwd is not also
#      mixed in. Same transcript_path, two different cwds (different git
#      branches) share one cached bundle: the branch segment stays pinned to
#      whichever cwd was rendered first, even once the render moves to the
#      second cwd.
CWDLIVE_DIR="$TMPROOT/cwdlive-cache"
CWDLIVE_TR="$TMPROOT/cwdlive-tr.jsonl"; echo '{}' > "$CWDLIVE_TR"
CWDLIVE_1="$TMPROOT/cwdlive-1"; mk_wt "$CWDLIVE_1"; git -C "$CWDLIVE_1" checkout -q -b feature-one >/dev/null 2>&1
CWDLIVE_2="$TMPROOT/cwdlive-2"; mk_wt "$CWDLIVE_2"; git -C "$CWDLIVE_2" checkout -q -b feature-two >/dev/null 2>&1
cwd1json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$CWDLIVE_1\"},$ctx,\"transcript_path\":\"$CWDLIVE_TR\"}"
cwd2json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$CWDLIVE_2\"},$ctx,\"transcript_path\":\"$CWDLIVE_TR\"}"
render_cached "$cwd1json" "$CWDLIVE_DIR" 5 >/dev/null
out=$(render_cached "$cwd2json" "$CWDLIVE_DIR" 5)
check "cache key is transcript_path alone: same transcript across cwds shares one bundle (branch pinned to 'feature-one')" \
  "$(printf '%s\n' "$out" | grep -qF '(feature-one)' && echo yes || echo no)" "yes"
check "cwd path segment stays LIVE even when the bundle is shared: path line reflects the NEW cwd" \
  "$(printf '%s\n' "$out" | sed -n '1p' | grep -qF "$CWDLIVE_2" && echo yes || echo no)" "yes"

# === 15. LIVE vs CACHED segments ============================================
# The core of the cheap-render split: cwd, model+effort, and the Ctx-usage
# line are recomputed on EVERY render; branch/PR/git-sync/State/mode/Cost are
# served from the bundle and only recomputed when it is rebuilt.

LIVE_DIR="$TMPROOT/live-cache"
LIVE_WD="$TMPROOT/live-wd"; mk_wt "$LIVE_WD"
LIVE_TR="$TMPROOT/live-tr.jsonl"; echo '{}' > "$LIVE_TR"
live1="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$LIVE_WD\"},\"context_window\":{\"context_window_size\":1000000,\"total_input_tokens\":10000},\"transcript_path\":\"$LIVE_TR\"}"
live2="{\"model\":{\"display_name\":\"Sonnet\"},\"effort\":{\"level\":\"low\"},\"workspace\":{\"current_dir\":\"$LIVE_WD\"},\"context_window\":{\"context_window_size\":1000000,\"total_input_tokens\":99999},\"transcript_path\":\"$LIVE_TR\"}"
render_cached "$live1" "$LIVE_DIR" 5 >/dev/null
out=$(render_cached "$live2" "$LIVE_DIR" 5)
check "Ctx-usage line is LIVE: a warm render reflects the NEW total_input_tokens (99,999)" \
  "$(printf '%s\n' "$out" | grep -qE '^Ctx used: 99,999' && echo yes || echo no)" "yes"
check "model+effort portion is LIVE: a warm render reflects the NEW model/effort ('Sonnet · low effort')" \
  "$(printf '%s\n' "$out" | grep -qF 'Sonnet · low effort' && echo yes || echo no)" "yes"
check "warm render's mode/model/effort line has no stray leading separator when mode is absent" \
  "$(printf '%s\n' "$out" | sed -n '2p' | grep -qxF 'Sonnet · low effort' && echo yes || echo no)" "yes"

# ctx-status.json is republished (LIVE) on every render, including warm ones.
CJ="$LIVE_WD/.local/.ctx-status.json"
check "ctx-status.json context_tokens reflects the warm render's LIVE value (99999)" \
  "$(jq -r '.context_tokens' "$CJ" 2>/dev/null)" "99999"

# === 16. WARM render invariants (external process counts) ==================
INV_DIR="$TMPROOT/inv-cache"
INV_WD="$TMPROOT/inv-wd"; mk_wt "$INV_WD"
printf 'Build\n' > "$INV_WD/.local/MODE"
inv_json="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"},\"workspace\":{\"current_dir\":\"$INV_WD\"},$ctx,\"transcript_path\":\"\"}"

render_shim "$inv_json" "$INV_DIR" 5              # cold: seeds the bundle
cold_git=$(shim_count "$SHIM_LOG" git)
cold_ccost=$(shim_count "$CCOST_LOG_FILE")
check "cold render (bundle rebuild) invokes git for the branch lookup" \
  "$([ "${cold_git:-0}" -gt 0 ] && echo yes || echo no)" "yes"
check "cold render (bundle rebuild) invokes ccost.sh for the Cost line" \
  "$([ "${cold_ccost:-0}" -gt 0 ] && echo yes || echo no)" "yes"

render_shim "$inv_json" "$INV_DIR" 5              # warm: same key, within TTL
warm_total=$(shim_count "$SHIM_LOG")
warm_git=$(shim_count "$SHIM_LOG" git)
warm_jq=$(shim_count "$SHIM_LOG" jq)
warm_ccost=$(shim_count "$CCOST_LOG_FILE")
check "warm render invokes at most 10 external commands in total" \
  "$([ "${warm_total:-99}" -le 10 ] && echo yes || echo no)" "yes"
check "warm render does not invoke git" \
  "$([ "${warm_git:-1}" -eq 0 ] && echo yes || echo no)" "yes"
check "warm render does not invoke ccost.sh (also proves it opens nothing under CLAUDE_PROJECTS_DIR -- ccost.sh is the only transcript reader on the cost path)" \
  "$([ "${warm_ccost:-1}" -eq 0 ] && echo yes || echo no)" "yes"
check "warm render runs exactly one jq (single stdin parse; compaction-budget env var is set, so no settings.json fallback)" \
  "$([ "${warm_jq:-99}" -eq 1 ] && echo yes || echo no)" "yes"

# Without CLAUDE_CODE_AUTO_COMPACT_WINDOW, the settings.json fallback jq may
# fire -- still bounded at one EXTRA jq (two total), never more.
FALLBACK_DIR="$TMPROOT/inv-fallback-cache"
FALLBACK_HOME="$TMPROOT/inv-fallback-home"; mkdir -p "$FALLBACK_HOME"
render_shim "$inv_json" "$FALLBACK_DIR" 5 "CLAUDE_CODE_AUTO_COMPACT_WINDOW=" "HOME=$FALLBACK_HOME"   # cold
render_shim "$inv_json" "$FALLBACK_DIR" 5 "CLAUDE_CODE_AUTO_COMPACT_WINDOW=" "HOME=$FALLBACK_HOME"   # warm
warm_jq_fallback=$(shim_count "$SHIM_LOG" jq)
check "warm render without the compaction-budget env var runs at most 2 jq (stdin parse + settings.json fallback)" \
  "$([ "${warm_jq_fallback:-99}" -le 2 ] && echo yes || echo no)" "yes"

# === 17. COLD render invariants =============================================

# 17a. First-ever render: cache dir absent beforehand, cold render creates it
#      plus at least one bundle file.
FIRST_DIR="$TMPROOT/first-cache"
check "cache dir does not exist before the first-ever render" \
  "$([ -e "$FIRST_DIR" ] && echo present || echo absent)" "absent"
FIRST_WD="$TMPROOT/first-wd"; mk_wt "$FIRST_WD"
first_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$FIRST_WD\"},$ctx,\"transcript_path\":\"\"}"
render_cached "$first_json" "$FIRST_DIR" 5 >/dev/null
check "first-ever render creates the cache dir" \
  "$([ -d "$FIRST_DIR" ] && echo yes || echo no)" "yes"
check "first-ever render leaves at least one bundle file in the cache dir" \
  "$([ "$(find "$FIRST_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && echo yes || echo no)" "yes"

# 17b. Cold leaves the bundle fresh, so an immediately-following render is
#      warm (reusing the shim counts already proven in section 16: git fired
#      on the cold call, then did not on the very next call at the same key).
check "cold render leaves the bundle fresh enough for the immediately-following render to be warm (section 16's cold->warm git transition)" \
  "$([ "${cold_git:-0}" -gt 0 ] && [ "${warm_git:-1}" -eq 0 ] && echo yes || echo no)" "yes"

# === 18. Output parity: cold render == legacy (cache-disabled) render ======
PARITY_WD="$TMPROOT/parity-wd"; mk_wt "$PARITY_WD"
printf 'Build\n' > "$PARITY_WD/.local/MODE"
parity_json="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"},\"workspace\":{\"current_dir\":\"$PARITY_WD\"},$ctx,\"transcript_path\":\"\"}"
legacy_out=$(render "$parity_json")
cold_out=$(render_cached "$parity_json" "$TMPROOT/parity-cache" 5)
check "cold render is byte-identical to the legacy (cache-disabled) renderer for the same inputs" \
  "$([ "$cold_out" == "$legacy_out" ] && echo yes || echo no)" "yes"

# === 19. Error handling: uncreatable cache dir, corrupt bundle =============

# 19a. A FILE occupies the path where the cache dir should be -> mkdir fails.
#      Render must still fully succeed: full (cold) render every time, no
#      cache-error text on stdout, exit 0.
BLOCKED_PARENT="$TMPROOT/blocked-parent"; mkdir -p "$BLOCKED_PARENT"
BLOCKED="$BLOCKED_PARENT/blocked-cache"
: > "$BLOCKED"
BLOCKED_WD="$TMPROOT/blocked-wd"; mkdir -p "$BLOCKED_WD"
blocked_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$BLOCKED_WD\"},$ctx,\"transcript_path\":\"\"}"
out=$(render_cached "$blocked_json" "$BLOCKED" 5)
check "uncreatable cache dir: render still produces the Ctx-usage line" \
  "$(printf '%s\n' "$out" | grep -qE '^Ctx used:' && echo yes || echo no)" "yes"
check "uncreatable cache dir: no cache/error text leaks onto stdout" \
  "$(printf '%s\n' "$out" | grep -qiE 'cache|no such file|cannot create|error' && echo present || echo absent)" "absent"
ec=$(printf '%s' "$blocked_json" \
  | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
      CLAM_STATUSLINE_CACHE_DIR="$BLOCKED" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=5 \
      bash "$CONTEXT" >/dev/null 2>/dev/null; echo $?)
check "uncreatable cache dir: render exits 0" "$ec" "0"

# 19b. A corrupt/partially-written bundle is treated as absent (cold rebuild),
#      not a crash. Corrupt EVERY file the first cold render created, without
#      needing to know the bundle's internal filename.
CORRUPT_DIR="$TMPROOT/corrupt-cache"
CORRUPT_WD="$TMPROOT/corrupt-wd"; mk_wt "$CORRUPT_WD"
corrupt_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$CORRUPT_WD\"},$ctx,\"transcript_path\":\"\"}"
render_cached "$corrupt_json" "$CORRUPT_DIR" 5 >/dev/null
find "$CORRUPT_DIR" -type f -exec sh -c 'printf "\xffnot-json-garbage{{{" > "$1"' _ {} \; 2>/dev/null
out=$(render_cached "$corrupt_json" "$CORRUPT_DIR" 5)
check "corrupt bundle: render still produces a valid Ctx-usage line (treated as absent, not a crash)" \
  "$(printf '%s\n' "$out" | grep -qE '^Ctx used:' && echo yes || echo no)" "yes"

# === 20. Edge cases =========================================================

# 20a. Future-dated bundle (negative age after a clock step) reads as FRESH.
FUTURE_DIR="$TMPROOT/future-cache"
FUTURE_WD="$TMPROOT/future-wd"; mk_wt "$FUTURE_WD"
printf 'Build\n' > "$FUTURE_WD/.local/MODE"
future_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$FUTURE_WD\"},$ctx,\"transcript_path\":\"\"}"
render_cached "$future_json" "$FUTURE_DIR" 5 >/dev/null
printf 'Debug\n' > "$FUTURE_WD/.local/MODE"
backdate_all "$FUTURE_DIR" -600   # 10 minutes in the future
out=$(render_cached "$future_json" "$FUTURE_DIR" 5)
check "future-dated bundle (negative age) reads as fresh -- still warm ('Build' kept)" \
  "$(printf '%s\n' "$out" | grep -qF 'Build · Opus' && echo yes || echo no)" "yes"

# 20b. No git worktree / no .local: degrades exactly as legacy, both cold and
#      warm, and stays within the process-count budget (WD is the plain,
#      non-git temp dir already used throughout this file).
render_shim "$json_json_effort" "$TMPROOT/plain-cache" 5    # cold
render_shim "$json_json_effort" "$TMPROOT/plain-cache" 5    # warm
plain_jq=$(shim_count "$SHIM_LOG" jq)
plain_git=$(shim_count "$SHIM_LOG" git)
plain_total=$(shim_count "$SHIM_LOG")
check "no git worktree / no .local: warm render still runs exactly one jq" \
  "$([ "${plain_jq:-99}" -eq 1 ] && echo yes || echo no)" "yes"
check "no git worktree / no .local: warm render does not invoke git (branch segment still cached/empty)" \
  "$([ "${plain_git:-1}" -eq 0 ] && echo yes || echo no)" "yes"
check "no git worktree / no .local: warm render stays within the 10-command budget" \
  "$([ "${plain_total:-99}" -le 10 ] && echo yes || echo no)" "yes"
check "no ctx-status.json written when cwd has no .local dir (still gated exactly as legacy, cache layer notwithstanding)" \
  "$([ -e "$WD/.local/.ctx-status.json" ] && echo present || echo absent)" "absent"

# === 21. Concurrency smoke: no reader ever sees a partial/corrupt bundle ===
SMOKE_DIR="$TMPROOT/smoke-cache"
SMOKE_WD="$TMPROOT/smoke-wd"; mk_wt "$SMOKE_WD"
printf 'Build\n' > "$SMOKE_WD/.local/MODE"
smoke_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$SMOKE_WD\"},$ctx,\"transcript_path\":\"\"}"
SMOKE_OUT="$TMPROOT/smoke-out"; mkdir -p "$SMOKE_OUT"
for i in $(seq 1 12); do
  ( render_cached "$smoke_json" "$SMOKE_DIR" 0 > "$SMOKE_OUT/$i" 2>&1 ) &   # ttl=0: max rebuild contention
done
wait
bad=0
for f in "$SMOKE_OUT"/*; do
  grep -qE '^Ctx used: [0-9,]+ / [0-9,]+ \([0-9]+%\)$' "$f" || bad=$((bad+1))
done
check "concurrency smoke: every concurrent render (ttl=0, max write contention) still produced valid output" "$bad" "0"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
