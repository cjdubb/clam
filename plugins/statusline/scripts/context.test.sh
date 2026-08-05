#!/bin/bash
# Functional test for context.sh rendering.
#
# Under B05 the three lines this suite used to assert on -- the mode/model/
# effort line, the "Ctx used:" line and the Cost line -- are replaced by ONE
# dense burnrate line beneath the path line, and the clam mode moves up onto
# the path line beside the State segment. Line 1 (path, branch, PR badges,
# git-sync, State) and the atomic .local/.ctx-status.json publish are invariant
# across that change and are still covered here unchanged; every check that
# named the old shape has been retargeted at the group that now carries the
# same clause, never deleted.
#
# Under B09/B10 (plan 002-statusline-emoji-removal) the render emits no emoji at
# all. Every meter emoji that LABELLED a number becomes a short text label
# in the same place and inside the same colour sequence (🎯 -> `wk`, 🧠 ->
# `ctx`, 🔥 -> `5h`); every emoji that sat beside text already naming the same
# thing -- the model mascot, the PR-badge glyphs, the State glyph -- simply
# goes; and the pet, whose whole content was a restatement of the worst meter,
# is deleted with its group. So the burnrate line is FOUR groups, not five, and
# line 1's badges are words. The same retargeting rule as B05 applies: a check
# that named the old glyph now names the label or the absence that replaced it,
# never deleted.
#
# Covers: the burnrate line's four groups, their vanishing separators and their
# degradation (section 23); the removal of the per-turn "Turn:" row; the
# ~-for-$HOME path shortening; clean block termination (no trailing decorative
# "$" prompt, no dangling blank line); the tri-state context colour
# (green/orange/red by occupancy + idle staleness) now carried by the ctx group;
# the atomic .local/.ctx-status.json publish; the clam-mode segment sourced
# from .local/MODE (line-1 placement, teal colour, sanitization); the
# emoji-free burnrate line and its parenthesised 5-hour countdown (section 24);
# and line 1's text PR tags and glyph-free State segment (section 25).
# Renders context.sh against synthetic statusLine JSON payloads (hermetic: temp
# cwd with no git/.local, temp ccost dirs) and asserts on the output (ANSI
# stripped for text, raw for colour-code checks).
# Run: bash general/statusline/context.test.sh   (exits non-zero on failure)

# <!--
# Contract: B06 mid-tier-test-defork (plan 001-speed-up-repo-ci)
#
# Behavior:
#   This file's ASSERTIONS are frozen; only its cost may change. 9.7s across
#   2,317 process spawns — mixed fork overhead and real work, so it needs
#   per-hot-path judgement rather than one mechanical substitution. Prefer
#   bash builtins over sed/awk/grep/cut in loops; keep them where they do
#   genuine text processing on multi-line input.
#
# Inputs:  unchanged — the same synthetic statusLine JSON payloads.
# Outputs: unchanged — one PASS line per assertion, then "ALL PASS".
#
# Invariants:
#   - Exactly 381 PASS lines and a zero exit. A changed count is a defect,
#     whichever direction it moves. (Was 86 when this contract was written;
#     the burnrate uplift raised it to 277, and B09/B10's sections 24 and 25
#     raised it again. The rule is the frozen count, not the number, so the
#     number moves when a deliberate change to the suite lands and stays
#     frozen in between.)
#   - No assertion may be weakened, skipped, merged, or deleted.
#   - Hermeticity is NOT negotiable for speed: the temp cwd with no
#     git/.local and the temp ccost dirs stay. B03 runs this file
#     concurrently with 112 others, so any leak into a shared path becomes a
#     race.
#   - The "concurrency smoke" test — every concurrent render under maximum
#     write contention still producing valid output — is the single most
#     load-bearing assertion in this file once B03 lands. It must not be
#     weakened or made cheaper.
#   - Runtime target: under 3s (from 9.7s). An ACCEPTANCE target verified by
#     the orchestrator, never a wall-clock assertion inside the test.
#
# Edge cases:
#   - Colour-code assertions read raw (un-stripped) output; any refactor of
#     the ANSI handling must keep both the stripped and raw paths intact.
# -->


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="$SCRIPT_DIR/context.sh"
source "$SCRIPT_DIR/../lib/platform.sh"

# The burnrate libraries are REAL here (B01/B02/B03 are merged), so expected
# values are DERIVED by calling them rather than hard-coded: the pacing figures
# depend on the wall-clock instant the suite runs at, and a literal would be
# wrong on any other day. This does not test their internals -- each has its
# own accepted suite -- it only pins that context.sh composes them correctly.
source "$SCRIPT_DIR/../lib/burn-math.sh"
source "$SCRIPT_DIR/../lib/burn-theme.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# The rendered cwd is a plain temp dir: not a git repo (no branch / PR / State
# segments) and no .local (no cache-refresh fork), so the render is hermetic.
WD="$TMPROOT/wd"; mkdir -p "$WD"

# Never inherit the harness's own effort or day-shape knobs; each case sets
# them explicitly. CLAM_STATUSLINE_DAY_START/CLAM_STATUSLINE_SLEEP_HOURS steer B01's awake-hours model
# via B05, so a value leaking in from the developer's shell would move every
# derived pacing figure.
unset CLAUDE_EFFORT CLAM_STATUSLINE_DAY_START CLAM_STATUSLINE_SLEEP_HOURS

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

# Set a file's mtime to N seconds in the past, so the render sees a known
# idle age from the transcript mtime. Uses bash's own strftime builtin
# (printf '%(fmt)T') instead of forking `date` twice per call (once for
# "now", once — BSD/GNU-fallback-style — to format the target epoch): same
# localtime-based formatting, one process fewer, and no BSD-vs-GNU branch
# needed since it isn't shelling out to either.
set_mtime_ago() { # file seconds_ago
  local f="$1" secs="$2" now epoch stamp
  printf -v now '%(%s)T' -1
  epoch=$(( now - secs ))
  printf -v stamp '%(%Y%m%d%H%M.%S)T' "$epoch"
  touch -t "$stamp" "$f"
}

# Assert the ctx session group's occupancy renders in an expected 256-colour
# code. Same clause the retired "Ctx used:" line carried (tri-state by
# occupancy + idle staleness), now sourced from B03's burn_ctx_state and
# expressed as a percentage rather than a token count.
#
# Under B09 the label is INSIDE the colour sequence, exactly where the 🧠 it
# replaced was, so the escape is matched immediately followed by "ctx " and the
# percentage -- no longer optionally. The old form tolerated the glyph falling
# either side of the escape because the contract did not say; B09's amendment
# does say ("Each label sits INSIDE its meter's colour sequence exactly where
# the emoji did ... so the colour still spans label and figure together"), so
# the tolerance goes and the position is pinned.
ctx_color_is() { # json color pct label
  check "$4" \
    "$(render_raw "$1" | grep -qaE "${ESC}\\[38;5;$2mctx $3%" && echo yes || echo no)" "yes"
}

# --- burnrate-line helpers (B05) -------------------------------------------
# The render is two lines: line 1 is the invariant path/branch/badges/State/
# mode line, line 2 is the burnrate line. Both are addressed by index rather
# than by content so a check can distinguish "on the wrong line" from "absent".
line_of() { # out n
  printf '%s\n' "$1" | sed -n "$2p"
}

# The burnrate line of an ANSI-stripped render (empty when no line 2 exists,
# i.e. when every group vanished).
burn_of() { # out
  line_of "$1" 2
}

# The warm-vs-cold probe used throughout sections 13/14/20: the clam mode is a
# CACHED bundle segment, so a render still showing the pre-change MODE value
# was served warm, and one showing the new value rebuilt.
#
# Deliberately placement-AGNOSTIC. What these sections assert is the caching
# mechanism -- TTL boundaries, key derivation, staleness -- which B05 does not
# touch; WHERE the mode segment prints is section 12's clause, checked there
# against line 1 by index. Pinning placement here too would make every cache
# check fail for a reason that has nothing to do with caching. Pre-B05 this
# read "<mode> · Opus" off the mode/model/effort line, which is exactly the
# coupling being removed. Echoes yes/no.
mode_cached_value() { # out mode
  printf '%s\n' "$1" | grep -qF "$2" && echo yes || echo no
}

# Structural well-formedness of an assembled burnrate line, independent of
# which groups are present: no leading separator, no trailing separator, no
# doubled separator (a group that vanished but left its │ behind), no group
# marker left standing without its number (a label whose figure dropped out),
# and no empty parens (a countdown that dropped but left its brackets).
# Echoes yes/no.
#
# The three markers are now B09's text labels rather than the meter emoji. The
# rule they enforce is unchanged, and so is its reach: `wk`, `ctx` and `5h`
# each lead their group exactly where 🎯/🧠/🔥 did. `5h` cannot collide with a
# countdown reading e.g. "5h12m", because the pattern requires NO digit between
# the marker and the separator and a countdown's own digits follow immediately.
burn_wellformed() { # line
  local l="$1"
  case "$l" in
    *"││"*) echo no; return 0 ;;
    *"()"*) echo no; return 0 ;;
  esac
  if printf '%s' "$l" | grep -qE '^[[:space:]]*│|│[[:space:]]*$|│[[:space:]]*│'; then
    echo no; return 0
  fi
  # [^0-9]* cannot cross a digit, so this matches only when the marker really
  # reaches the next separator (or the end of the line) with no figure.
  if printf '%s' "$l" | grep -qE '(wk|ctx|5h)[^0-9]*(│|$)'; then
    echo no; return 0
  fi
  echo yes
}

# yes iff LINE carries no emoji. B09's amendment is "this line emits no emoji",
# and the three ambiguous-width symbols it DELIBERATELY keeps -- the dim │
# separator and the ▲/▼ trend arrows -- are the only non-ASCII characters left
# once it holds. So: strip those three, and anything non-ASCII still standing
# is an emoji that should have gone. Deliberately a whole-alphabet check rather
# than a list of the specific glyphs removed: it also catches a NEW emoji
# arriving later, which an enumeration never would. LC_ALL=C so the byte range
# means bytes, not whatever the ambient locale collates into it.
#
# Every fixture this is applied to uses an ASCII model name and tier, so a
# non-ASCII byte can only have come from the renderer.
burn_no_emoji() { # line
  local l="$1"
  l="${l//│/}"; l="${l//▲/}"; l="${l//▼/}"
  printf '%s' "$l" | LC_ALL=C grep -q '[^ -~]' && echo no || echo yes
}

# yes iff every character of TEXT appears in RAW coloured from the CURRENT
# BURN_HUES palette at ONE consistent offset -- i.e. the model name went
# through B03's burn_rainbow with the palette its family selects. The offset is
# searched rather than pinned because burn_frame_advance moves it every render.
# BURN_HUES must already be set by a BARE `burn_model_style <model>` call (it
# sets globals and echoes nothing, so capturing it in $( ) would discard them).
rainbow_ok() { # raw text
  local raw="$1" text="$2" f i ok needle
  for (( f = 0; f < 8; f++ )); do
    ok=1
    for (( i = 0; i < ${#text}; i++ )); do
      needle=$(printf '\033[38;5;%sm%s' "${BURN_HUES[(i + f) % 8]}" "${text:i:1}")
      case "$raw" in *"$needle"*) ;; *) ok=0; break ;; esac
    done
    (( ok )) && { echo yes; return 0; }
  done
  echo no
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
  local t0 tnow
  printf -v t0 '%(%s)T' -1
  printf -v tnow '%(%s)T' -1
  while [ "$tnow" = "$t0" ]; do
    sleep 0.02
    printf -v tnow '%(%s)T' -1
  done
}

# Backdate (or, with a negative seconds_ago, future-date) every regular file
# under a directory. Used to age a cache bundle without sleeping out the full
# age in wall-clock time and without needing to know the bundle's internal
# filename. Waits for a second boundary first -- see settle_to_second.
backdate_all() { # dir seconds_ago
  local dir="$1" secs="$2" now epoch stamp
  settle_to_second
  printf -v now '%(%s)T' -1
  epoch=$(( now - secs ))
  printf -v stamp '%(%Y%m%d%H%M.%S)T' "$epoch"
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
# The burnrate libraries too: context.sh sources each only when the file is
# present, so a shadow tree missing them would silently render a DEGRADED line
# and every budget measurement taken through it would be counting a render that
# never ran B01's or B02's awk. Section 23m builds a separate shadow tree that
# deliberately omits them, which is what makes that degradation case meaningful.
ln -s "$SCRIPT_DIR/../lib/burn-math.sh" "$SHADOW/lib/burn-math.sh"
ln -s "$SCRIPT_DIR/../lib/burn-tick.sh" "$SHADOW/lib/burn-tick.sh"
ln -s "$SCRIPT_DIR/../lib/burn-theme.sh" "$SHADOW/lib/burn-theme.sh"
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
    # Every line the shim appends is `echo "$tool" >> "$SHIM_LOG"`, always
    # newline-terminated, so a builtin `mapfile` line count is exactly `wc
    # -l`'s count here — without forking wc AND tr (tr only existed to strip
    # the leading padding `wc -l < file` prints). Missing file -> empty
    # output, same as before (wc's failed redirection produced nothing for
    # tr to strip either).
    [ -f "$1" ] || return 0
    local -a _lines
    mapfile -t _lines < "$1"
    printf '%s' "${#_lines[@]}"
  fi
}
# ------------------------------------------------------------------------

ctx='"context_window":{"context_window_size":1000000,"total_input_tokens":145230}'

# 1. Effort from the JSON payload (.effort.level), model present.
#    B05 folds the retired mode/model/effort and "Ctx used:" lines into the
#    burnrate line's model group (rainbow model name + coloured effort tier, no
#    literal "effort" word) and ctx session group. The clauses are the same;
#    only their expression moved. B09 then drops the group's mascot prefix, so
#    the model name now LEADS the line.
json_json_effort="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"max\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\"}"
out=$(render "$json_json_effort")
check "effort from JSON renders in the burnrate line's model group ('Opus max')" \
  "$(burn_of "$out" | grep -qE '^Opus max( │|$)' && echo yes || echo no)" "yes"
check "the retired 'Opus · max effort' line is gone" \
  "$(printf '%s\n' "$out" | grep -qF 'Opus · max effort' && echo present || echo absent)" "absent"
check "Turn row removed" \
  "$(printf '%s\n' "$out" | grep -q 'Turn:' && echo present || echo absent)" "absent"
check "session group renders the context meter (ctx NN%)" \
  "$(burn_of "$out" | grep -qE 'ctx [0-9]+%' && echo yes || echo no)" "yes"
check "the retired 'Ctx used: <used> / <budget> (NN%)' line is gone" \
  "$(printf '%s\n' "$out" | grep -q 'Ctx used:' && echo present || echo absent)" "absent"
check "redundant Total: segment dropped from the context meter" \
  "$(printf '%s\n' "$out" | grep -q 'Total:' && echo present || echo absent)" "absent"

# 2. Effort falls back to $CLAUDE_EFFORT when .effort is absent from the JSON.
#    The fallback lives in sl_parse_input and is unchanged by B05; only the
#    tier's rendered form moved into the model group.
json_no_effort="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\"}"
out=$(CLAUDE_EFFORT=high render "$json_no_effort")
check "effort falls back to \$CLAUDE_EFFORT (model group shows the high tier)" \
  "$(burn_of "$out" | grep -qE '^Opus high( │|$)' && echo yes || echo no)" "yes"

# 3. Effort fully absent (no .effort, no env): the model group carries the model
#    name only, and the word "effort" appears nowhere (the burnrate line names
#    the tier bare, so a literal "effort" is now always a regression).
out=$(render "$json_no_effort")
check "model-only group when effort fully absent ('Opus', nothing trailing)" \
  "$(burn_of "$out" | grep -qE '^Opus( │|$)' && echo yes || echo no)" "yes"
check "no 'effort' text when effort fully absent" \
  "$(printf '%s\n' "$out" | grep -q 'effort' && echo present || echo absent)" "absent"

# 4. Model AND effort both absent: the model GROUP vanishes with its separator,
#    so the burnrate line now opens on the ctx session group. (Pre-B05 this was
#    "the whole mode line is omitted and the Ctx line moves up to line 2" --
#    same omission rule, same line index, one line further in.)
json_bare="{\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\"}"
out=$(render "$json_bare")
check "no 'Opus' when model absent" \
  "$(printf '%s\n' "$out" | grep -q 'Opus' && echo present || echo absent)" "absent"
check "no 'effort' when model+effort absent" \
  "$(printf '%s\n' "$out" | grep -q 'effort' && echo present || echo absent)" "absent"
check "model group vanishes cleanly: the burnrate line opens on ctx, no leading separator" \
  "$(burn_of "$out" | grep -qE '^ctx [0-9]+%' && echo yes || echo no)" "yes"
check "burnrate line is still the second output line when the model group vanishes" \
  "$(burn_of "$out" | grep -q '[^[:space:]]' && echo yes || echo no)" "yes"

# 5. Effort-only: model absent, effort present (via env). The tier still
#    renders and the line stays well-formed -- no dangling separator and no
#    marker left without its figure. Pre-B09 this deliberately left open whether
#    the mascot survived a missing model name; B09 settles it by deleting the
#    mascot outright, and 23p pins the resulting shape.
out=$(CLAUDE_EFFORT=high render "$json_bare")
check "effort-only: the tier still renders when the model name is absent" \
  "$(burn_of "$out" | grep -qF 'high' && echo yes || echo no)" "yes"
check "effort-only: burnrate line stays well-formed (no dangling separator)" \
  "$(burn_wellformed "$(burn_of "$out")")" "yes"

# 6. Precedence: JSON .effort.level wins over $CLAUDE_EFFORT when both are set.
out=$(CLAUDE_EFFORT=low render "$json_json_effort")
check "JSON .effort.level takes precedence over \$CLAUDE_EFFORT (max beats low)" \
  "$(burn_of "$out" | grep -qE '^Opus max( │|$)' && echo yes || echo no)" "yes"
check "the losing \$CLAUDE_EFFORT tier ('low') appears nowhere in the render" \
  "$(printf '%s\n' "$out" | grep -qF 'low' && echo present || echo absent)" "absent"

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
#    rendered line is non-empty, so there is no trailing blank line either.
#    Under B05 the block's last line is the burnrate line (B04 already dropped
#    the Cost line; B05 drops the mode/model/effort and "Ctx used:" lines into
#    it), so the third check below pins WHICH line ends the block, not just
#    that some line does.
#
#    The middle check stays at `grep -q '[^[:space:]]'` on the last line
#    deliberately: `out=$(render ...)` strips ALL trailing newlines, so no
#    assertion made on $out can distinguish "ends on a real line" from "ends on
#    a blank one". That is the strongest form that survives capture. The
#    byte-level version of the same clause, which has to bypass command
#    substitution entirely, is in section 23g. (cjdubb/clam#231.)
out=$(render "$json_json_effort")
check "no decorative \$ prompt line remains" \
  "$(printf '%s\n' "$out" | grep -qE '^[$] ?$' && echo present || echo absent)" "absent"
check "status block ends on a real line (no trailing blank line)" \
  "$(printf '%s\n' "$out" | tail -n1 | grep -q '[^[:space:]]' && echo yes || echo no)" "yes"
check "the line the block ends on is the burnrate line" \
  "$(printf '%s\n' "$out" | tail -n1 | grep -qE '^Opus max' && echo yes || echo no)" "yes"

# 9. Tri-state context colour by occupancy + idle staleness, now carried by the
#    burnrate line's ctx group and sourced from B03's burn_ctx_state. Budget is
#    300000 (the render/render_raw env). Colours: 40 green (small, or
#    big-but-warm), 208 orange (big & cooling >=30 min), 196 red (big & cold
#    >=45 min, or over budget). Idle is driven by a real transcript file's
#    mtime. The thresholds and their boundary-inclusiveness are unchanged from
#    the retired "Ctx used:" line -- the whole point of routing this through
#    burn_ctx_state is that the tier and the .ctx-status.json `level` field
#    cannot disagree (section 10 pins the published side).
TR="$TMPROOT/tr.jsonl"; echo '{}' > "$TR"

# 9a. Small (145,230/300,000 = 48% < 60% floor): green regardless of idle.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 145230 "$TR")" 40 48 \
  "ctx green (40) when occupancy is small (pct<60)"

# 9b. Big but warm (200,000 = 66%, transcript fresh so idle ~0): still green —
#     staleness only escalates a big session once it starts cooling.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 200000 "$TR")" 40 66 \
  "ctx green (40) when big but warm (pct>=60, idle<1800)"

# 9c. Big and cooling (66%, ~33 min idle): orange.
set_mtime_ago "$TR" 2000
ctx_color_is "$(ctx_json "$WD" 200000 "$TR")" 208 66 \
  "ctx orange (208) when big and cooling (idle>=1800)"

# 9d. Big and cold (66%, ~50 min idle): red.
set_mtime_ago "$TR" 3000
ctx_color_is "$(ctx_json "$WD" 200000 "$TR")" 196 66 \
  "ctx red (196) when big and cold (idle>=2700)"

# 9e. Over budget (350,000 > 300,000) with a FRESH transcript: red regardless of
#     idle — over-budget is always cold.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 350000 "$TR")" 196 116 \
  "ctx red (196) when over budget (any idle)"

# 9f. Empty transcript ("") must NOT read as infinitely cold: a big session
#     (66%) with no transcript stays green (idle forced to 0), not red.
ctx_color_is "$(ctx_json "$WD" 200000 "")" 40 66 \
  "ctx green (40) when big with an empty transcript (no false cold)"

# 9g. Missing transcript file (path set, file absent): same guard → green.
ctx_color_is "$(ctx_json "$WD" 200000 "$TMPROOT/does-not-exist.jsonl")" 40 66 \
  "ctx green (40) when big with a missing transcript file (no false cold)"

# 9h. The ctx percentage is the integer floor of 100*used/budget and is NOT
#     clamped at 100 (350,000/300,000 = 116%) — the entire reason this plugin
#     computes occupancy itself instead of using the payload's saturating
#     .context_window.used_percentage.
out=$(render "$(ctx_json "$WD" 350000 "$TR")")
check "ctx percentage is the unclamped floor (116%) on overrun" \
  "$(burn_of "$out" | grep -qE 'ctx 116%' && echo yes || echo no)" "yes"

# 9i. Exact-budget boundary (300,000 tokens == 300,000 budget, exactly 100%)
#     with a FRESH transcript: red. Contrasts with 9e's used > budget case and
#     pins the `>=` comparison in burn_ctx_state — a regression to `>` would
#     leave this exact-equal case green instead of red.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 300000 "$TR")" 196 100 \
  "ctx red (196) at the exact-budget boundary (used == budget)"

# 9j. Occupancy floor gates staleness: small occupancy (145,230/300,000 = 48%
#     < 60% floor) with an OLD transcript (~50 min idle, same age as 9d's red
#     case) stays green. Extends 9a's "regardless of idle" claim by actually
#     driving idle into the cold band, proving small sessions can't be pushed
#     into orange/red by staleness alone.
set_mtime_ago "$TR" 3000
ctx_color_is "$(ctx_json "$WD" 145230 "$TR")" 40 48 \
  "ctx green (40) when occupancy is small despite an old/stale transcript"

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

# 12. Clam-mode segment from .local/MODE. B05 retires the mode/model/effort
#     line the mode used to lead, and the mode moves up onto the PATH line
#     beside the State segment (decision 001-clam-mode-placement); the burnrate
#     line is exactly the four groups and carries no mode. Every clause the old
#     cases covered -- sourcing, sanitization, the 24-char cap, the teal
#     colour, absence when the file is missing or blank -- still holds and is
#     re-pinned below against line 1. The one clause that genuinely stops
#     existing is "mode is FIRST on the mode/model/effort line": that line is
#     gone, and the decision replaces the ordering rather than restating it.
#     Fixture mirrors test 10: real git worktree with .local and pre-touched
#     refresh locks (hermetic, no background refreshers spawn), and no
#     .local/TODO.md so no State segment renders (12i adds one deliberately).
MWD="$TMPROOT/modewd"; mkdir -p "$MWD/.local"; git -C "$MWD" init -q >/dev/null 2>&1
touch "$MWD/.local/.pr-status-refresh.lock" "$MWD/.local/.git-sync-refresh.lock"
json_mode_full="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"max\"},\"workspace\":{\"current_dir\":\"$MWD\"},$ctx,\"transcript_path\":\"\"}"
json_mode_bare="{\"workspace\":{\"current_dir\":\"$MWD\"},$ctx,\"transcript_path\":\"\"}"

# 12a. MODE=Build (trailing newline, as /start writes it) + model + effort.
#      The mode lands on line 1; the burnrate line is untouched by it.
printf 'Build\n' > "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "mode renders on the path line (line 1)" \
  "$(line_of "$out" 1 | grep -qF 'Build' && echo yes || echo no)" "yes"
check "mode does NOT appear on the burnrate line (contract invariant)" \
  "$(burn_of "$out" | grep -qF 'Build' && echo present || echo absent)" "absent"
check "burnrate line is unaffected by the mode segment ('Opus max')" \
  "$(burn_of "$out" | grep -qE '^Opus max( │|$)' && echo yes || echo no)" "yes"

# 12b. Internal space survives sanitization (only leading/trailing trimmed).
printf 'Go Commando\n' > "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "internal space kept: 'Go Commando' on the path line" \
  "$(line_of "$out" 1 | grep -qF 'Go Commando' && echo yes || echo no)" "yes"

# 12c. Git worktree with .local but NO MODE file: path line carries no mode
#      segment at all. Captured here as the reference line 1 that 12d must
#      reproduce exactly.
rm -f "$MWD/.local/MODE"
out=$(render "$json_mode_full")
mode_absent_line1=$(line_of "$out" 1)
check "no MODE file leaves no mode text on the path line" \
  "$(printf '%s' "$mode_absent_line1" | grep -qF 'Build' && echo present || echo absent)" "absent"
check "no MODE file leaves the burnrate line unchanged ('Opus max')" \
  "$(burn_of "$out" | grep -qE '^Opus max( │|$)' && echo yes || echo no)" "yes"

# 12d. Whitespace-only MODE trims to empty: segment absent. Compared against
#      12c's captured line byte-for-byte, so a stray separator or a lone space
#      left behind by an empty mode fails rather than passing a "no 'Build'
#      here" check vacuously.
printf '   \n' > "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "whitespace-only MODE renders a path line identical to the no-MODE one" \
  "$(line_of "$out" 1)" "$mode_absent_line1"

# 12e. Mode-only payload (no model key, no effort key/env): the mode is on the
#      path line and the retired '·' separator no longer joins anything to it.
#      Matched adjacent to the mode rather than anywhere in the render, which
#      is the clause itself: the '·' joined the mode to the model, so what is
#      gone is that JOIN. (Pre-B09 the adjacency was also forced by the pet's
#      alert-tier effect characters, one of which is '·'. B09 deletes the pet,
#      so that second reason has lapsed; the first has not.)
printf 'Build\n' > "$MWD/.local/MODE"
out=$(render "$json_mode_bare")
check "mode-only payload puts 'Build' on the path line" \
  "$(line_of "$out" 1 | grep -qF 'Build' && echo yes || echo no)" "yes"
check "no retired '·' separator is joined to the mode" \
  "$(printf '%s\n' "$out" | grep -qE 'Build[[:space:]]*·|·[[:space:]]*Build' && echo present || echo absent)" "absent"

# 12f. Mode + effort (env fallback), no model: the two now live on DIFFERENT
#      lines — mode on the path line, tier in the burnrate line's model group.
out=$(CLAUDE_EFFORT=high render "$json_mode_bare")
check "mode + effort (no model): mode on the path line" \
  "$(line_of "$out" 1 | grep -qF 'Build' && echo yes || echo no)" "yes"
check "mode + effort (no model): the tier renders in the burnrate line, not beside the mode" \
  "$(burn_of "$out" | grep -qF 'high' && echo yes || echo no)" "yes"
check "mode + effort (no model): the tier does not leak onto the path line" \
  "$(line_of "$out" 1 | grep -qF 'high' && echo present || echo absent)" "absent"

# 12g. Mode colour: teal (256-colour 37), unchanged by the move.
check "mode renders in teal (38;5;37)" \
  "$(render_raw "$json_mode_full" | grep -qaF "${ESC}[38;5;37mBuild" && echo yes || echo no)" "yes"

# 12h. Sanitization: an ESC byte inside the word is stripped before rendering
#      (no escape-sequence injection from a crafted MODE file), and an
#      oversized single-line value is capped at its first 24 characters.
printf 'Bu\033ild' > "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "ESC byte inside MODE is stripped ('Build' on the path line)" \
  "$(line_of "$out" 1 | grep -qF 'Build' && echo yes || echo no)" "yes"
printf 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234\n' > "$MWD/.local/MODE"
out=$(render "$json_mode_full")
check "oversized MODE is capped at its first 24 chars" \
  "$(line_of "$out" 1 | grep -qF 'ABCDEFGHIJKLMNOPQRSTUVWX' && echo yes || echo no)" "yes"
check "oversized MODE's 25th character onward is dropped" \
  "$(line_of "$out" 1 | grep -qF 'ABCDEFGHIJKLMNOPQRSTUVWXY' && echo present || echo absent)" "absent"

# 12i. Mode and the State segment coexist on the path line — the placement
#      decision puts the mode beside State, so a worktree with both must show
#      both, on line 1, and still leave the burnrate line to its four groups.
printf 'Build\n' > "$MWD/.local/MODE"
printf 'State: In Progress\n' > "$MWD/.local/TODO.md"
out=$(render "$json_mode_full")
check "mode and State segment both render on the path line" \
  "$(line_of "$out" 1 | grep -qF 'Build' && line_of "$out" 1 | grep -qF 'In Progress' && echo yes || echo no)" "yes"
check "neither mode nor State leaks onto the burnrate line" \
  "$(burn_of "$out" | grep -qE 'Build|In Progress' && echo present || echo absent)" "absent"
rm -f "$MWD/.local/TODO.md"

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
  "$(mode_cached_value "$out" 'Build')" "yes"
backdate_all "$DEFTTL_DIR" 5
out=$(render_default_ttl "$ttljson")
check "default TTL (5s): a 5s-old bundle is stale ('Debug' change now reflected)" \
  "$(mode_cached_value "$out" 'Debug')" "yes"

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
  "$(mode_cached_value "$out" 'Build')" "yes"
backdate_all "$OVR_DIR" 2
out=$(render_cached "$ovrjson" "$OVR_DIR" 2)
check "overridden TTL=2s: a 2s-old bundle is stale ('Debug' reflected)" \
  "$(mode_cached_value "$out" 'Debug')" "yes"

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
  "$(mode_cached_value "$out" 'Debug')" "yes"

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
  "$(mode_cached_value "$out" 'Build')" "yes"
backdate_all "$BAD_DIR" 5
out=$(render_cached "$badjson" "$BAD_DIR" "not-a-number")
check "non-integer TTL falls back to 5s: a 5s-old bundle is stale ('Debug' reflected)" \
  "$(mode_cached_value "$out" 'Debug')" "yes"

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
  "$(mode_cached_value "$outA" 'Build')" "yes"
check "same cwd, different transcript_path: session B gets its own (cold) bundle, not A's ('Debug')" \
  "$(mode_cached_value "$outB" 'Debug')" "yes"

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
  "$(mode_cached_value "$outA" 'Alpha')" "yes"
check "empty transcript_path falls back to cwd as key: worktree B independently warm ('Bravo')" \
  "$(mode_cached_value "$outB" 'Bravo')" "yes"

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
# The core of the cheap-render split: cwd, model+effort and the context meter
# are recomputed on EVERY render; branch/PR/git-sync/State/mode are served from
# the bundle and only recomputed when it is rebuilt. Under B05 the live parts
# are groups 1 and 3 of the burnrate line rather than two standalone lines, and
# the rate-limit figures join them as live-on-every-render (section 23k pins
# that half, which has no pre-B05 analogue).

LIVE_DIR="$TMPROOT/live-cache"
LIVE_WD="$TMPROOT/live-wd"; mk_wt "$LIVE_WD"
LIVE_TR="$TMPROOT/live-tr.jsonl"; echo '{}' > "$LIVE_TR"
live1="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$LIVE_WD\"},\"context_window\":{\"context_window_size\":1000000,\"total_input_tokens\":10000},\"transcript_path\":\"$LIVE_TR\"}"
live2="{\"model\":{\"display_name\":\"Sonnet\"},\"effort\":{\"level\":\"low\"},\"workspace\":{\"current_dir\":\"$LIVE_WD\"},\"context_window\":{\"context_window_size\":1000000,\"total_input_tokens\":99999},\"transcript_path\":\"$LIVE_TR\"}"
render_cached "$live1" "$LIVE_DIR" 5 >/dev/null
out=$(render_cached "$live2" "$LIVE_DIR" 5)
check "ctx group is LIVE: a warm render reflects the NEW total_input_tokens (99,999/300,000 = 33%)" \
  "$(burn_of "$out" | grep -qE 'ctx 33%' && echo yes || echo no)" "yes"
check "model group is LIVE: a warm render reflects the NEW model/effort ('Sonnet low')" \
  "$(burn_of "$out" | grep -qE '^Sonnet low( │|$)' && echo yes || echo no)" "yes"
check "warm render's burnrate line has no stray leading separator when the mode is absent" \
  "$(burn_wellformed "$(burn_of "$out")")" "yes"

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
check "cold render (bundle rebuild) does not invoke ccost.sh (B04: context.sh no longer depends on it at all, cold or warm)" \
  "$([ "${cold_ccost:-1}" -eq 0 ] && echo yes || echo no)" "yes"

render_shim "$inv_json" "$INV_DIR" 5              # warm: same key, within TTL
warm_total=$(shim_count "$SHIM_LOG")
warm_git=$(shim_count "$SHIM_LOG" git)
warm_jq=$(shim_count "$SHIM_LOG" jq)
warm_ccost=$(shim_count "$CCOST_LOG_FILE")
# The warm-render budget was raised from 10 to 12 in the approved plan and is
# stated in the B05 contract's Invariants: the pre-uplift warm render measured
# 8, and the burnrate line adds at most three -- two awk (one in B01's
# burn_metrics, one in B02's burn_tick_frac) and one `date` for the local
# time-of-day day-start anchor, alongside the shared UTC `date` already there.
# 12 was decided in advance; it is NOT the number this scenario happens to
# measure (this payload carries no rate_limits, so it exercises neither awk and
# should sit well under the cap). Section 23l measures a payload that does, and
# pins the per-tool sub-limits inside the 12.
check "warm render invokes at most 12 external commands in total" \
  "$([ "${warm_total:-99}" -le 12 ] && echo yes || echo no)" "yes"
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
# B01's Outputs clause: for the same inputs, a cold render is byte-identical to
# the legacy output. B05 puts a per-render ANIMATION into that output -- the
# rainbow palette offset and the pet frame both advance once per render -- so
# two renders of the same payload are no longer byte-identical to each other,
# whatever the implementation does with the frame counter, and the two renders
# compared here deliberately use different cache dirs. The clause is therefore
# split into the two halves that remain observable:
#   - line 1 (path, branch, PR badges, git-sync, State, mode) carries no
#     animation, so it stays byte-identical RAW, escapes included. That is the
#     line the cached bundle actually feeds, so it is also the half the parity
#     clause was about.
#   - the burnrate line is compared with ANSI stripped: the rainbow only varies
#     the COLOUR codes, never the characters, so stripping escapes removes the
#     frame's entire influence on the text.
#
# Pre-B09 that second half had to drop the final group as well, because the pet
# glyph was frame-dependent in its characters rather than only its colour --
# the one thing an ANSI strip could not neutralise. B09 deletes the pet, so the
# whole stripped line is now comparable and the trim goes: what was
# "everything up to the last separator" is now the line itself.
PARITY_WD="$TMPROOT/parity-wd"; mk_wt "$PARITY_WD"
printf 'Build\n' > "$PARITY_WD/.local/MODE"
parity_json="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"},\"workspace\":{\"current_dir\":\"$PARITY_WD\"},$ctx,\"transcript_path\":\"\"}"
legacy_out=$(render "$parity_json")
cold_out=$(render_cached "$parity_json" "$TMPROOT/parity-cache" 5)
legacy_raw=$(render_raw "$parity_json")
cold_raw=$(printf '%s' "$parity_json" \
  | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
      CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/parity-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=5 \
      bash "$CONTEXT" 2>/dev/null)
check "cold render's path line is byte-identical (raw, escapes included) to the legacy renderer's" \
  "$(line_of "$cold_raw" 1)" "$(line_of "$legacy_raw" 1)"
check "cold render's burnrate line matches the legacy renderer's in full (the animation frame varies only colour)" \
  "$(burn_of "$cold_out")" "$(burn_of "$legacy_out")"
check "cold and legacy renders produce the same number of lines" \
  "$(printf '%s\n' "$cold_out" | wc -l | tr -d ' ')" \
  "$(printf '%s\n' "$legacy_out" | wc -l | tr -d ' ')"

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
check "uncreatable cache dir: render still produces the burnrate line's ctx group" \
  "$(burn_of "$out" | grep -qE 'ctx [0-9]+%' && echo yes || echo no)" "yes"
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
check "corrupt bundle: render still produces a valid burnrate line (treated as absent, not a crash)" \
  "$(burn_of "$out" | grep -qE 'ctx [0-9]+%' && echo yes || echo no)" "yes"

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
  "$(mode_cached_value "$out" 'Build')" "yes"

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
check "no git worktree / no .local: warm render stays within the 12-command budget" \
  "$([ "${plain_total:-99}" -le 12 ] && echo yes || echo no)" "yes"
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
  # A well-formed burnrate line as the render's SECOND line: model group, then
  # the ctx group with a percentage. Pre-B05 this looked for the "Ctx used:"
  # line; same purpose (a complete, uncorrupted render), same line index.
  sed -n '2p' "$f" | grep -qE '^Opus .*ctx [0-9]+%' || bad=$((bad+1))
done
check "concurrency smoke: every concurrent render (ttl=0, max write contention) still produced valid output" "$bad" "0"

# === 22. B04 payload-parse ==================================================
# Contract: sl_parse_input additionally parses eight burnrate fields (r5,
# r5_reset, r7, r7_reset, lines_added, lines_removed, total_cost_usd,
# session_id) from the SAME single jq invocation, the cached bundle drops its
# cost_line key (six keys -> five, mask 63 -> 31), and context.sh stops
# invoking ccost.sh entirely. The renderer that consumes these fields (B05)
# is still an unimplemented stub in this unit, so every case here observes
# the variables directly by sourcing context.sh rather than reading them out
# of the rendered text.

B04_CACHE_DIR="$TMPROOT/b04-cache"

# parse_vars(json): source context.sh (safe -- no `exit`, no `set -e`, its own
# dir resolved via BASH_SOURCE[0]) against a synthetic payload on stdin, and
# echo `declare -p` for the eight contract variables so the caller can eval
# them into its own scope. Hermetic env mirrors render()'s: sandboxed
# CLAUDE_PROJECTS_DIR/CCOST_CACHE_DIR, compaction window pinned so the
# settings.json jq fallback never fires, and caching disabled (TTL 0) so
# every call is a fresh cold parse independent of any prior call's bundle.
parse_vars() { # json
  printf '%s' "$1" | (
    export CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache"
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000
    export CLAM_STATUSLINE_CACHE_DIR="$B04_CACHE_DIR" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0
    . "$CONTEXT" >/dev/null 2>&1
    declare -p r5 r5_reset r7 r7_reset lines_added lines_removed total_cost_usd session_id 2>/dev/null
  )
}

# 22a. Full payload: all eight fields present and parsed correctly, alongside
#      the pre-existing fields the same jq already produced (model_name,
#      effort survive downstream in the render) -- proving the burnrate
#      fields ride the SAME single jq rather than a parallel one.
b04_full="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\",\"session_id\":\"sess-abc123\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":1700000000},\"seven_day\":{\"used_percentage\":17,\"resets_at\":1700500000}},\"cost\":{\"total_lines_added\":503,\"total_lines_removed\":16,\"total_cost_usd\":12.34}}"
eval "$(parse_vars "$b04_full")"
check "full payload: r5 (five_hour used_percentage)" "$r5" "42"
check "full payload: r5_reset (five_hour resets_at)" "$r5_reset" "1700000000"
check "full payload: r7 (seven_day used_percentage)" "$r7" "17"
check "full payload: r7_reset (seven_day resets_at)" "$r7_reset" "1700500000"
check "full payload: lines_added" "$lines_added" "503"
check "full payload: lines_removed" "$lines_removed" "16"
check "full payload: total_cost_usd" "$total_cost_usd" "12.34"
check "full payload: session_id" "$session_id" "sess-abc123"

# 22a2. The Inputs clause explicitly warns off a DIFFERENT internal shape
#       (ISO-8601 utilization/resets_at) that also exists in the Claude Code
#       binary. A payload using those field names (not used_percentage/
#       resets_at) must parse as if rate_limits were absent, not silently
#       pick up "utilization" as if it were used_percentage.
b04_wrongshape="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\",\"rate_limits\":{\"five_hour\":{\"utilization\":42,\"resets_at\":\"2026-01-01T00:00:00Z\"}}}"
eval "$(parse_vars "$b04_wrongshape")"
check "ISO/utilization shape is not parsed: r5 empty (not the utilization value)" "$r5" ""
check "ISO/utilization shape is not parsed: r5_reset empty (not the ISO string)" "$r5_reset" ""

# 22b. rate_limits absent entirely (API-key, Bedrock, Vertex, or Claude Code
#      older than 2.1): all four rate-limit variables empty at once, while
#      cost and session_id -- unrelated fields from the SAME jq -- still
#      parse correctly.
b04_norl="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\",\"session_id\":\"sess-xyz\",\"cost\":{\"total_lines_added\":9,\"total_lines_removed\":2,\"total_cost_usd\":1.5}}"
eval "$(parse_vars "$b04_norl")"
check "rate_limits absent: r5 empty" "$r5" ""
check "rate_limits absent: r5_reset empty" "$r5_reset" ""
check "rate_limits absent: r7 empty" "$r7" ""
check "rate_limits absent: r7_reset empty" "$r7_reset" ""
check "rate_limits absent: cost/session_id still parse (lines_added)" "$lines_added" "9"
check "rate_limits absent: cost/session_id still parse (session_id)" "$session_id" "sess-xyz"

# 22c. Gap in the middle: five_hour present, seven_day ABSENT, cost present.
#      The highest-value case in this block -- proves the \x01 join keeps
#      every later field in its own column despite the missing pair between
#      them, rather than silently swallowing lines_added/lines_removed/
#      total_cost_usd/session_id into the gap.
b04_gap_mid="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\",\"session_id\":\"sess-gap1\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":55,\"resets_at\":1700111111}},\"cost\":{\"total_lines_added\":7,\"total_lines_removed\":3,\"total_cost_usd\":0.42}}"
eval "$(parse_vars "$b04_gap_mid")"
check "gap in middle (seven_day absent): r5 present" "$r5" "55"
check "gap in middle (seven_day absent): r5_reset present" "$r5_reset" "1700111111"
check "gap in middle (seven_day absent): r7 empty" "$r7" ""
check "gap in middle (seven_day absent): r7_reset empty" "$r7_reset" ""
check "gap in middle (seven_day absent): lines_added still lands correctly" "$lines_added" "7"
check "gap in middle (seven_day absent): lines_removed still lands correctly" "$lines_removed" "3"
check "gap in middle (seven_day absent): total_cost_usd still lands correctly" "$total_cost_usd" "0.42"
check "gap in middle (seven_day absent): session_id still lands correctly" "$session_id" "sess-gap1"

# 22d. Reverse pairing: five_hour ABSENT, seven_day present, cost present.
b04_gap_rev="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\",\"session_id\":\"sess-gap2\",\"rate_limits\":{\"seven_day\":{\"used_percentage\":88,\"resets_at\":1700222222}},\"cost\":{\"total_lines_added\":11,\"total_lines_removed\":4,\"total_cost_usd\":2.75}}"
eval "$(parse_vars "$b04_gap_rev")"
check "gap in middle (five_hour absent): r5 empty" "$r5" ""
check "gap in middle (five_hour absent): r5_reset empty" "$r5_reset" ""
check "gap in middle (five_hour absent): r7 present" "$r7" "88"
check "gap in middle (five_hour absent): r7_reset present" "$r7_reset" "1700222222"
check "gap in middle (five_hour absent): lines_added still lands correctly" "$lines_added" "11"
check "gap in middle (five_hour absent): lines_removed still lands correctly" "$lines_removed" "4"
check "gap in middle (five_hour absent): total_cost_usd still lands correctly" "$total_cost_usd" "2.75"
check "gap in middle (five_hour absent): session_id still lands correctly" "$session_id" "sess-gap2"

# 22e. Float used_percentage preserved exactly (23.5) -- not rounded, not
#      truncated; rounding is the renderer's job, not the parser's.
b04_float="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":23.5,\"resets_at\":1700333333}}}"
eval "$(parse_vars "$b04_float")"
check "float used_percentage (23.5) preserved as given" "$r5" "23.5"

# 22f. Empty is not zero, both directions. A GENUINE zero (session with truly
#      no rate-limit usage yet, or truly no line changes) parses to "0", not
#      "" -- a "" would be indistinguishable from an absent field and a "0"
#      would render a real meter for a session with no quota data at all.
b04_zero="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":0,\"resets_at\":0}},\"cost\":{\"total_lines_added\":0,\"total_lines_removed\":0,\"total_cost_usd\":0}}"
eval "$(parse_vars "$b04_zero")"
check "genuine zero used_percentage parses to \"0\", not empty" "$r5" "0"
check "genuine zero resets_at parses to \"0\", not empty" "$r5_reset" "0"
check "genuine zero total_lines_added parses to \"0\", not empty" "$lines_added" "0"
check "genuine zero total_lines_removed parses to \"0\", not empty" "$lines_removed" "0"
check "genuine zero total_cost_usd parses to \"0\", not empty" "$total_cost_usd" "0"

# 22g. cost object entirely absent: lines_added/lines_removed/total_cost_usd
#      all empty -- distinguishable from the genuine-zero case above. Also
#      confirms session_id is empty, not just skipped, when absent.
b04_nocost="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\"}"
eval "$(parse_vars "$b04_nocost")"
check "cost object absent: lines_added empty" "$lines_added" ""
check "cost object absent: lines_removed empty" "$lines_removed" ""
check "cost object absent: total_cost_usd empty" "$total_cost_usd" ""
check "cost object absent: session_id empty" "$session_id" ""

# 22h. Cached bundle: five required keys (mask 31), the OLD six-key bundle
#      still valid (migration path), and a bundle missing a required key
#      still treated as corrupt/absent. Detected the same way sections 13/14
#      detect warm-vs-cold: a hand-written bundle carries a branch= value the
#      real git branch would never produce, so if the render shows it, the
#      bundle was served warm (mask accepted it); if the render shows the
#      REAL branch instead, sl_bundle_read rejected the file as incomplete.
BUNDLE_DIR="$TMPROOT/bundle-mask-cache"; mkdir -p "$BUNDLE_DIR"
BUNDLE_WD="$TMPROOT/bundle-mask-wd"; mk_wt "$BUNDLE_WD"
git -C "$BUNDLE_WD" checkout -q -b real-branch >/dev/null 2>&1
bundle_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$BUNDLE_WD\"},$ctx,\"transcript_path\":\"\"}"
BUNDLE_FILE=$(printf '%s' "$BUNDLE_WD" | sed 's#/#_#g')

# 22h-i. Five-key bundle (new format, no cost_line line): valid.
{
  printf 'branch=five-key-sentinel\n'
  printf 'pr_badge=\n'
  printf 'git_sync=\n'
  printf 'state_seg=\n'
  printf 'clam_mode=\n'
} > "$BUNDLE_DIR/$BUNDLE_FILE.bundle"
out=$(render_cached "$bundle_json" "$BUNDLE_DIR" 5)
check "five-key bundle (no cost_line) is valid: mask 31 serves it warm" \
  "$(printf '%s\n' "$out" | grep -qF '(five-key-sentinel)' && echo yes || echo no)" "yes"

# 22h-ii. Old six-key bundle (previous version's format, extra cost_line=
#         line): still valid -- the migration path for every already-
#         installed user. The extra key is ignored, not treated as corrupt.
{
  printf 'branch=six-key-sentinel\n'
  printf 'pr_badge=\n'
  printf 'git_sync=\n'
  printf 'state_seg=\n'
  printf 'clam_mode=\n'
  printf 'cost_line=Session: $1.23\n'
} > "$BUNDLE_DIR/$BUNDLE_FILE.bundle"
out=$(render_cached "$bundle_json" "$BUNDLE_DIR" 5)
check "old six-key bundle (with cost_line) still reads as valid, extra key ignored" \
  "$(printf '%s\n' "$out" | grep -qF '(six-key-sentinel)' && echo yes || echo no)" "yes"

# 22h-iii. Bundle missing a required key (only 4 of the 5): treated as
#          absent -- the mask enforces completeness, not "any subset".
{
  printf 'branch=incomplete-sentinel\n'
  printf 'pr_badge=\n'
  printf 'git_sync=\n'
  printf 'state_seg=\n'
} > "$BUNDLE_DIR/$BUNDLE_FILE.bundle"
out=$(render_cached "$bundle_json" "$BUNDLE_DIR" 5)
check "bundle missing a required key (4 of 5) is treated as absent, not served warm" \
  "$(printf '%s\n' "$out" | grep -qF '(incomplete-sentinel)' && echo present || echo absent)" "absent"

# 22h-iv. Write side: a fresh cold-render bundle contains no cost_line= line
#         and carries all five remaining keys.
WRITE_DIR="$TMPROOT/bundle-write-cache"
WRITE_WD="$TMPROOT/bundle-write-wd"; mk_wt "$WRITE_WD"
write_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WRITE_WD\"},$ctx,\"transcript_path\":\"\"}"
render_cached "$write_json" "$WRITE_DIR" 5 >/dev/null
WRITE_FILE=$(printf '%s' "$WRITE_WD" | sed 's#/#_#g')
WRITE_BUNDLE="$WRITE_DIR/$WRITE_FILE.bundle"
check "freshly-written bundle exists after a cold render" \
  "$([ -f "$WRITE_BUNDLE" ] && echo yes || echo no)" "yes"
check "freshly-written bundle has no cost_line= key" \
  "$(grep -qE '^cost_line=' "$WRITE_BUNDLE" 2>/dev/null && echo present || echo absent)" "absent"
check "freshly-written bundle carries all five remaining keys" \
  "$(for k in branch pr_badge git_sync state_seg clam_mode; do grep -qE "^${k}=" "$WRITE_BUNDLE" 2>/dev/null || { echo no; exit; }; done; echo yes)" "yes"

# 22i. Exactly one jq per render, cold and warm alike, even with all eight
#      burnrate fields folded into the payload -- adding fields is not
#      grounds for a second jq. Also re-confirms ccost.sh is never invoked,
#      this time with a payload that actually carries cost data (so a
#      regression that re-adds the ccost.sh call would have real inputs to
#      act on, not just absent ones).
B04INV_DIR="$TMPROOT/b04-inv-cache"
B04INV_WD="$TMPROOT/b04-inv-wd"; mk_wt "$B04INV_WD"
b04inv_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$B04INV_WD\"},$ctx,\"transcript_path\":\"\",\"session_id\":\"sess-inv\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":10,\"resets_at\":1700444444},\"seven_day\":{\"used_percentage\":5,\"resets_at\":1700555555}},\"cost\":{\"total_lines_added\":1,\"total_lines_removed\":1,\"total_cost_usd\":0.01}}"

render_shim "$b04inv_json" "$B04INV_DIR" 5             # cold: seeds the bundle
b04_cold_jq=$(shim_count "$SHIM_LOG" jq)
b04_cold_ccost=$(shim_count "$CCOST_LOG_FILE")
check "B04 payload, cold render: exactly one jq" \
  "$([ "${b04_cold_jq:-99}" -eq 1 ] && echo yes || echo no)" "yes"
check "B04 payload, cold render: ccost.sh never invoked" \
  "$([ "${b04_cold_ccost:-1}" -eq 0 ] && echo yes || echo no)" "yes"

render_shim "$b04inv_json" "$B04INV_DIR" 5             # warm: same key, within TTL
b04_warm_jq=$(shim_count "$SHIM_LOG" jq)
b04_warm_ccost=$(shim_count "$CCOST_LOG_FILE")
check "B04 payload, warm render: exactly one jq" \
  "$([ "${b04_warm_jq:-99}" -eq 1 ] && echo yes || echo no)" "yes"
check "B04 payload, warm render: ccost.sh never invoked" \
  "$([ "${b04_warm_ccost:-1}" -eq 0 ] && echo yes || echo no)" "yes"

# === 23. B05 burnrate line, as amended by B09 ===============================
# Contract: sl_render_burn_line assembles the entire line and echoes it as one
# string with no trailing newline -- FOUR groups joined by a dim │ separator:
#   1 model    the model name in its drifting rainbow, and the effort tier in
#              its own colour. No mascot prefix (B09).
#   2 weekly   wk used%, today's remaining share (%t), sustainable pace (%/d),
#              and the trend arrow vs the awake even-burn line
#   3 session  ctx context occupancy, and lines added/removed this session
#   4 5-hour   5h used%, and the countdown to its reset IN PARENS (B09)
# -- composing B01 (burn_metrics), B02 (burn_tick_frac) and B03 (all
# presentation) over B04's parsed fields, performing no arithmetic and no
# colour selection of its own.
#
# B05's fifth group, the pet, is deleted by B09 along with the stress scan that
# fed it. Every case below that was expressed through the pet has been
# retargeted at the clause it was really testing rather than dropped: the
# stress-maximum cases become 23h's absence cases (a group that must vanish for
# every meter combination that used to produce a mood), and the "last group"
# extractions now land on the 5-hour group.
#
# Sections 1-12 above already re-pin the clauses that predate B05 and survive
# it in a new form (the $CLAUDE_EFFORT fallback and its precedence, the
# absent-data omission rule, the idle-aware context colour, the clam-mode
# segment). This section covers what is new: group assembly, the vanishing
# separator, the derived pacing figures, degradation, and the two env knobs.
# Section 24 covers what B09 adds on top: the labels' colour placement, the
# parenthesised countdown, and the line's emoji-freeness as an alphabet.
#
# Expected values are DERIVED by calling the real B01/B03 functions rather than
# hard-coded. Every pacing figure depends on the wall-clock instant the suite
# runs at, so a literal would be right today and wrong tomorrow.

# The render's own "now" and its local time-of-day. B05 derives the day-start
# anchor from exactly these two quantities, so an anchor derived here is the
# anchor the render builds a fraction of a second later.
B5_NOW=$(date +%s)
read -r _b5h _b5m _b5s <<< "$(date +'%H %M %S')"
B5_SECS=$(( 10#$_b5h * 3600 + 10#$_b5m * 60 + 10#$_b5s ))
B5_R5_RESET=$(( B5_NOW + 17670 ))       # 4h54m30s out: 30s clear of a minute flip
B5_R7_RESET=$(( B5_NOW + 3 * 86400 ))

B5_WD="$TMPROOT/b5-wd"; mkdir -p "$B5_WD"
B5_CACHE="$TMPROOT/b5-cache"

# burn_json(cwd tokens model effort r5 r5_reset r7 r7_reset added removed):
# a statusLine payload in which every field is independently PRESENT or ABSENT.
# "" omits the key from the JSON entirely; "0" emits a real zero. That
# distinction is the whole of the "empty is not zero" clause, so the fixture
# builder has to be able to express both.
#
# cost.total_cost_usd and session_id are deliberately never emitted. Without a
# cost figure B02's burn_tick_frac returns 0 on every path it can take (anchor,
# session switch, and the read path where the delta is zero or negative all
# floor at 0), so the sub-tick fraction folded into %t is a known 0 and the
# figures derived below are reproducible without this suite having to know
# where the implementation keeps B02's state file. Case 23l uses a payload that
# does carry cost, where the interpolator is genuinely exercised.
burn_json() { # cwd tokens model effort r5 r5_reset r7 r7_reset added removed
  local cwd="$1" tokens="$2" model="$3" effort="$4" r5="$5" r5r="$6" r7="$7" r7r="$8" la="$9" lr="${10}"
  local j rl="" cost=""
  j="{\"workspace\":{\"current_dir\":\"$cwd\"},\"transcript_path\":\"\""
  [ -n "$model" ]  && j="$j,\"model\":{\"display_name\":\"$model\"}"
  [ -n "$effort" ] && j="$j,\"effort\":{\"level\":\"$effort\"}"
  [ -n "$tokens" ] && j="$j,\"context_window\":{\"context_window_size\":1000000,\"total_input_tokens\":$tokens}"
  if [ -n "$r5" ]; then
    rl="\"five_hour\":{\"used_percentage\":$r5"
    [ -n "$r5r" ] && rl="$rl,\"resets_at\":$r5r"
    rl="$rl}"
  fi
  if [ -n "$r7" ]; then
    [ -n "$rl" ] && rl="$rl,"
    rl="$rl\"seven_day\":{\"used_percentage\":$r7"
    [ -n "$r7r" ] && rl="$rl,\"resets_at\":$r7r"
    rl="$rl}"
  fi
  [ -n "$rl" ] && j="$j,\"rate_limits\":{$rl}"
  [ -n "$la" ] && cost="\"total_lines_added\":$la"
  if [ -n "$lr" ]; then
    [ -n "$cost" ] && cost="$cost,"
    cost="$cost\"total_lines_removed\":$lr"
  fi
  [ -n "$cost" ] && j="$j,\"cost\":{$cost}"
  printf '%s}' "$j"
}

# burn_render(json, [NAME=VALUE ...]): a hermetic always-cold render (TTL 0)
# with the ANSI stripped. Extra env pairs go straight to `env`, so a case can
# set CLAM_STATUSLINE_DAY_START / CLAM_STATUSLINE_SLEEP_HOURS without leaking the value into any other.
burn_render() { # json [env...]
  local json="$1"; shift
  printf '%s' "$json" \
    | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$B5_CACHE" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        "$@" bash "$CONTEXT" 2>/dev/null \
    | sed -E "s/${ESC}\\[[0-9;]*m//g"
}

# Like burn_render but WITHOUT the ANSI strip, for the colour assertions.
burn_render_raw() { # json [env...]
  local json="$1"; shift
  printf '%s' "$json" \
    | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$B5_CACHE" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        "$@" bash "$CONTEXT" 2>/dev/null
}

# The burnrate line alone, ANSI stripped.
burn_only() { # json [env...]
  burn_of "$(burn_render "$@")"
}

# The final group of a burnrate line (everything past the last separator),
# whitespace-trimmed. A line with no separator yields the whole line.
last_group() { # line
  local g="${1##*│}"
  g="${g#"${g%%[![:space:]]*}"}"
  g="${g%"${g##*[![:space:]]}"}"
  printf '%s' "$g"
}

# burn_expect_today(used reset day_start_hour sleep_hours): B01's %t figure for
# those inputs. This is the one derived figure the suite pins EXACTLY: unlike
# pace and trend it does not depend on `now` at all -- it reads off the current
# day's slice of the ideal line, fixed by the day-start anchor and the reset --
# so a value computed here cannot drift from the value the render computes an
# instant later.
burn_expect_today() { # used reset day_start_hour sleep_hours
  local ds
  ds=$(burn_day_start_epoch "$B5_NOW" "$B5_SECS" "$3") || return 1
  burn_metrics "$1" 0 "$B5_NOW" "$2" "$ds" "$(( $4 * 3600 ))" | awk '{print $1}'
}

# burn_metric_candidates(field used reset ds slp t0 t1): B01's FIELD (1=%t,
# 2=pace, 3=trend) at each whole second in [t0,t1] -- the interval the render's
# own clock provably fell inside, bracketed by a `date` either side of the
# render. Pace and trend both vary continuously with `now` and are then rounded
# for display, so pinning them to a single instant would be a rounding-boundary
# coin flip; bracketing keeps the assertion exact without the flake.
burn_metric_candidates() { # field used reset ds slp t0 t1
  local n
  for (( n = $6; n <= $7; n++ )); do
    burn_metrics "$2" 0 "$n" "$3" "$4" "$5" 2>/dev/null | awk -v f="$1" '{print $f}'
  done
}

# The NN%t token's number, or empty when the sub-segment is not rendered.
today_token() { # line
  printf '%s' "$1" | grep -oE '\-?[0-9]+%t' | head -n1 | sed 's/%t$//'
}

# --- 23a. The whole line: four groups, in order ------------------------------
b5_full=$(burn_json "$B5_WD" 145230 "Opus" "max" 1 "$B5_R5_RESET" 62 "$B5_R7_RESET" 503 16)
b5_t0=$(date +%s)
b5_out=$(burn_render "$b5_full")
b5_t1=$(date +%s)
b5_line=$(burn_of "$b5_out")

check "23a: four groups joined by exactly three │ separators" \
  "$(printf '%s' "$b5_line" | grep -o '│' | wc -l | tr -d ' ')" "3"
check "23a: group 1 (model) leads with the model name and effort tier, no mascot prefix" \
  "$(printf '%s' "$b5_line" | grep -qE '^Opus max │' && echo yes || echo no)" "yes"
check "23a: group 2 (weekly) carries the wk used percentage" \
  "$(printf '%s' "$b5_line" | grep -qE '│ wk 62%' && echo yes || echo no)" "yes"
check "23a: group 3 (session) carries the ctx occupancy (145,230/300,000 = 48%)" \
  "$(printf '%s' "$b5_line" | grep -qE '│ ctx 48%' && echo yes || echo no)" "yes"
check "23a: group 3 carries the +added/-removed counts" \
  "$(printf '%s' "$b5_line" | grep -qF '+503/-16' && echo yes || echo no)" "yes"
check "23a: group 4 (5-hour) carries the 5h used percentage" \
  "$(printf '%s' "$b5_line" | grep -qE '│ 5h 1%' && echo yes || echo no)" "yes"
# The countdown is bracketed the same way the pacing figures are: burn_reset_str
# rolls a minute at a time, and the render's clock is somewhere in [t0,t1]. B09
# wraps it in parens, so the parens are matched WITH it -- a bare countdown and
# a parenthesised one are different renders and only one of them is the clause.
b5_countdown_ok=no
for (( _n = b5_t0; _n <= b5_t1; _n++ )); do
  printf '%s' "$b5_line" | grep -qF "($(burn_reset_str "$B5_R5_RESET" "$_n"))" && b5_countdown_ok=yes
done
check "23a: group 4 carries B03's countdown to the 5-hour reset, in parens" "$b5_countdown_ok" "yes"
# B09 deletes the pet, so the 5-hour group is now the last group and the line
# ends on it. Asserted as an EQUALITY on the final group rather than as an
# absence of pet glyphs: a pet that survived would fail this, and so would a
# 5-hour group that lost its countdown or gained a trailing separator, which a
# "no cat faces" check would both wave through.
b5_tail_ok=no
for (( _n = b5_t0; _n <= b5_t1; _n++ )); do
  [ "$(last_group "$b5_line")" = "5h 1% ($(burn_reset_str "$B5_R5_RESET" "$_n"))" ] && b5_tail_ok=yes
done
check "23a: the 5-hour group closes the line (the pet group is gone, not merely empty)" \
  "$b5_tail_ok" "yes"
check "23a: the whole line carries no emoji at all" \
  "$(burn_no_emoji "$b5_line")" "yes"
check "23a: the render is exactly two lines (path line + burnrate line)" \
  "$(printf '%s\n' "$b5_out" | wc -l | tr -d ' ')" "2"
check "23a: the assembled line is structurally well-formed" \
  "$(burn_wellformed "$b5_line")" "yes"
check "23a: none of the three retired lines survives (Ctx used: / Cost: / Session: \$)" \
  "$(printf '%s\n' "$b5_out" | grep -qE 'Ctx used:|Cost:|Session: \$' && echo present || echo absent)" "absent"

# --- 23b. The vanishing-separator rule --------------------------------------
# Each group is omitted ENTIRELY, along with its separator, when its data is
# unavailable: never a dangling │, never a marker with no number, never a
# leading or trailing separator.

# 23b-i. No rate_limits at all (an API-key, Bedrock or Vertex session, or a
#        Claude Code older than 2.1): groups 2 AND 4 vanish together.
#        Post-B09 that leaves groups 1 and 3 alone -- one separator, and the
#        session group ENDS the line. Matched as an anchored whole line
#        (grep -x) rather than a prefix: the pet used to follow, and the
#        strongest statement of "the pet is gone and took its separator with
#        it" is that there is nothing after the counts at all.
b5_norl=$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" "" "" 503 16)
b5_norl_line=$(burn_only "$b5_norl")
check "23b: no rate_limits → two groups, one separator" \
  "$(printf '%s' "$b5_norl_line" | grep -o '│' | wc -l | tr -d ' ')" "1"
check "23b: no rate_limits → no wk weekly group" \
  "$(printf '%s' "$b5_norl_line" | grep -qE 'wk [0-9]' && echo present || echo absent)" "absent"
check "23b: no rate_limits → no 5h 5-hour group" \
  "$(printf '%s' "$b5_norl_line" | grep -qE '5h [0-9]' && echo present || echo absent)" "absent"
check "23b: no rate_limits → groups 1 and 3 render, in order, and nothing follows" \
  "$(printf '%s' "$b5_norl_line" | grep -qxE 'Opus max │ ctx 48% \+503/-16' && echo yes || echo no)" "yes"
check "23b: no rate_limits → line stays well-formed" \
  "$(burn_wellformed "$b5_norl_line")" "yes"

# 23b-ii. Weekly present, its reset timestamp absent: wk used% still renders;
#         %t, %/d and the trend all need the reset and do not.
b5_wknores=$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 62 "" "" "")
b5_wknores_line=$(burn_only "$b5_wknores")
check "23b: weekly without its reset → wk 62% still renders" \
  "$(printf '%s' "$b5_wknores_line" | grep -qE 'wk 62%' && echo yes || echo no)" "yes"
check "23b: weekly without its reset → no %t sub-segment" \
  "$(printf '%s' "$b5_wknores_line" | grep -qF '%t' && echo present || echo absent)" "absent"
check "23b: weekly without its reset → no %/d sub-segment" \
  "$(printf '%s' "$b5_wknores_line" | grep -qF '%/d' && echo present || echo absent)" "absent"
check "23b: weekly without its reset → no trend arrow" \
  "$(printf '%s' "$b5_wknores_line" | grep -qE '▲|▼' && echo present || echo absent)" "absent"
check "23b: weekly without its reset → line stays well-formed" \
  "$(burn_wellformed "$b5_wknores_line")" "yes"

# 23b-iii/iv. One rate-limit pair present, the other absent, both directions.
b5_only5=$(burn_json "$B5_WD" 145230 "Opus" "max" 42 "$B5_R5_RESET" "" "" "" "")
b5_only5_line=$(burn_only "$b5_only5")
check "23b: five_hour present, seven_day absent → 5h renders, wk vanishes" \
  "$(printf '%s' "$b5_only5_line" | grep -qE '5h 42%' \
     && ! printf '%s' "$b5_only5_line" | grep -qE 'wk [0-9]' && echo yes || echo no)" "yes"
check "23b: five_hour present, seven_day absent → three groups, two separators" \
  "$(printf '%s' "$b5_only5_line" | grep -o '│' | wc -l | tr -d ' ')" "2"
check "23b: five_hour present, seven_day absent → line stays well-formed" \
  "$(burn_wellformed "$b5_only5_line")" "yes"

b5_only7=$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 42 "$B5_R7_RESET" "" "")
b5_only7_line=$(burn_only "$b5_only7")
check "23b: seven_day present, five_hour absent → wk renders, 5h vanishes" \
  "$(printf '%s' "$b5_only7_line" | grep -qE 'wk 42%' \
     && ! printf '%s' "$b5_only7_line" | grep -qE '5h [0-9]' && echo yes || echo no)" "yes"
check "23b: seven_day present, five_hour absent → three groups, two separators" \
  "$(printf '%s' "$b5_only7_line" | grep -o '│' | wc -l | tr -d ' ')" "2"
check "23b: seven_day present, five_hour absent → line stays well-formed" \
  "$(burn_wellformed "$b5_only7_line")" "yes"

# 23b-v. Every group empty (a payload carrying nothing but a cwd): the line is
#        the empty string and the caller prints NO line at all.
b5_empty=$(burn_json "$B5_WD" "" "" "" "" "" "" "" "" "")
b5_empty_out=$(burn_render "$b5_empty")
check "23b: every group empty → the render is exactly one line (the path line)" \
  "$(printf '%s\n' "$b5_empty_out" | wc -l | tr -d ' ')" "1"
check "23b: every group empty → no burnrate line at all" \
  "$(burn_of "$b5_empty_out")" ""

# --- 23c. "Empty is not zero" -----------------------------------------------
# B04 sets each rate-limit variable to the empty string when its payload field
# is absent, never 0, because a 0 would render a real "0%" meter for a session
# that has no quota data at all. Each pair below fails if the two are ever
# conflated -- in either direction, since an absent field and a genuine zero
# have OPPOSITE expected renders rather than merely different ones.
b5_zero5_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" 0 "$B5_R5_RESET" "" "" "" "")")
check "23c: a GENUINE zero five_hour renders a real 5h 0% meter" \
  "$(printf '%s' "$b5_zero5_line" | grep -qE '5h 0%' && echo yes || echo no)" "yes"
check "23c: an ABSENT five_hour renders no 5h group at all" \
  "$(printf '%s' "$b5_wknores_line" | grep -qE '5h [0-9]' && echo present || echo absent)" "absent"
b5_zero7_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 0 "$B5_R7_RESET" "" "")")
check "23c: a GENUINE zero seven_day renders a real wk 0% meter" \
  "$(printf '%s' "$b5_zero7_line" | grep -qE 'wk 0%' && echo yes || echo no)" "yes"
check "23c: an ABSENT seven_day renders no wk group at all" \
  "$(printf '%s' "$b5_only5_line" | grep -qE 'wk [0-9]' && echo present || echo absent)" "absent"

# --- 23d. The +N/-M sub-segment ---------------------------------------------
# Appears only once at least one of the two counts is above zero: a session
# that has edited nothing shows no counts rather than "+0/-0". The two-byte
# sequence "/-" occurs nowhere else on the line (the pace reads "%/d", and B01
# never emits a negative pace), so its absence is the exact test for "no counts
# rendered" without having to enumerate what else might be there.
b5_bothzero_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" "" "" 0 0)")
check "23d: both counts zero → no counts sub-segment" \
  "$(printf '%s' "$b5_bothzero_line" | grep -qF '/-' && echo present || echo absent)" "absent"
check "23d: both counts zero → the literal '+0/-0' is nowhere on the line" \
  "$(printf '%s' "$b5_bothzero_line" | grep -qF '+0/-0' && echo present || echo absent)" "absent"
b5_nocost_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" "" "" "" "")")
check "23d: both counts absent → no counts sub-segment" \
  "$(printf '%s' "$b5_nocost_line" | grep -qF '/-' && echo present || echo absent)" "absent"
check "23d: both counts absent → the ctx group still renders its occupancy" \
  "$(printf '%s' "$b5_nocost_line" | grep -qE 'ctx 48%' && echo yes || echo no)" "yes"
b5_addonly_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" "" "" 5 0)")
check "23d: added above zero, removed zero → the sub-segment appears ('+5/-0')" \
  "$(printf '%s' "$b5_addonly_line" | grep -qF '+5/-0' && echo yes || echo no)" "yes"
b5_removeonly_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" "" "" 0 7)")
check "23d: removed above zero, added zero → the sub-segment appears ('+0/-7')" \
  "$(printf '%s' "$b5_removeonly_line" | grep -qF '+0/-7' && echo yes || echo no)" "yes"

# --- 23e. Context occupancy is not clamped ----------------------------------
# The whole reason the plugin computes occupancy itself rather than reading the
# payload's .context_window.used_percentage: that field saturates at 100.
b5_over_line=$(burn_only "$(burn_json "$B5_WD" 350000 "Opus" "max" "" "" "" "" "" "")")
check "23e: occupancy over 100% renders above 100 (350,000/300,000 = 116%)" \
  "$(printf '%s' "$b5_over_line" | grep -qE 'ctx 116%' && echo yes || echo no)" "yes"
check "23e: occupancy over 100% is not clamped to 100" \
  "$(printf '%s' "$b5_over_line" | grep -qE 'ctx 100%' && echo present || echo absent)" "absent"

# --- 23f. The model group ---------------------------------------------------
# B09 drops the mascot prefix, so every model family now leads its group with
# the NAME. The per-family case is still worth running across the whole roster
# rather than once: the mascot was the one thing that differed between families
# here, so a change that dropped it for the families it recognised and left the
# fallback in place for the one it did not would pass a single-model check.
#
# The mascot glyphs are named as LITERALS rather than read back out of
# $BURN_MASCOT. B08 stops burn_model_style setting that global at all, so an
# expectation sourced from it would quietly become "no mascot must not appear",
# which every render satisfies. The literals are the five B03 ever emitted.
B5_MASCOTS='🎭|🪶|🦄|🌸|🤖'
for _m in "Opus" "Sonnet" "Fable 5" "Haiku 4.5" "Gemini 3"; do
  _line=$(burn_only "$(burn_json "$B5_WD" 145230 "$_m" "high" "" "" "" "" "" "")")
  check "23f: model '$_m' leads its group with the name, no mascot" \
    "$(printf '%s' "$_line" | grep -qE "^$_m high( │|\$)" && echo yes || echo no)" "yes"
  check "23f: model '$_m' renders no mascot glyph anywhere on the line" \
    "$(printf '%s' "$_line" | grep -qE "$B5_MASCOTS" && echo present || echo absent)" "absent"
done

burn_model_style "Opus"
b5_raw=$(burn_render_raw "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" "" "" "" "")")
check "23f: the model name is coloured from its family's palette at one consistent frame offset" \
  "$(rainbow_ok "$b5_raw" "Opus")" "yes"
check "23f: the effort tier carries burn_effort_color's sequence for its level" \
  "$(printf '%s' "$b5_raw" | grep -qaF "$(burn_effort_color max)max" && echo yes || echo no)" "yes"
check "23f: a different tier gets its own colour (low is not max's red)" \
  "$(printf '%s' "$(burn_render_raw "$(burn_json "$B5_WD" 145230 "Opus" "low" "" "" "" "" "" "")")" \
     | grep -qaF "$(burn_effort_color low)low" && echo yes || echo no)" "yes"

# A model name carrying a parenthesised suffix is trimmed at " (" before
# colouring, so the line stays short.
b5_paren_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus 5 (1M context)" "max" "" "" "" "" "" "")")
check "23f: a parenthesised model suffix is trimmed at ' (' ('Opus 5', not 'Opus 5 (1M context)')" \
  "$(printf '%s' "$b5_paren_line" | grep -qE '^Opus 5 max( │|$)' && echo yes || echo no)" "yes"
check "23f: the trimmed suffix appears nowhere on the line" \
  "$(printf '%s' "$b5_paren_line" | grep -qF '1M context' && echo present || echo absent)" "absent"

# --- 23g. Clean termination, at the byte level ------------------------------
# The byte-level twin of section 8's check. `out=$(render ...)` strips ALL
# trailing newlines, so no assertion made on a captured string can distinguish
# "ends on a real line" from "ends on a blank one"; these write the render to a
# FILE and read its last byte, which can. (cjdubb/clam#231.)
#
# The assertion is exactly the clause -- the last byte is not a newline -- and
# nothing more. Pinning the actual byte would pin whether the line happens to
# end in an SGR reset, which the contract does not say either way.
#
# `od -An -c` renders a newline as the two characters \n, any printable byte as
# itself, and a non-ASCII byte as its octal value; comparing against the
# literal \n is therefore exact and never ambiguous.
last_byte_is_newline() { # file
  [ "$(tail -c1 "$1" | od -An -c | tr -d ' \n')" = '\n' ] && echo newline || echo not-newline
}
b5_bytes="$TMPROOT/b5-bytes.out"
printf '%s' "$b5_full" \
  | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
      CLAM_STATUSLINE_CACHE_DIR="$B5_CACHE" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
      bash "$CONTEXT" > "$b5_bytes" 2>/dev/null
check "23g: a render ending on the burnrate line emits no trailing newline" \
  "$(last_byte_is_newline "$b5_bytes")" "not-newline"
printf '%s' "$b5_empty" \
  | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
      CLAM_STATUSLINE_CACHE_DIR="$B5_CACHE" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
      bash "$CONTEXT" > "$b5_bytes" 2>/dev/null
check "23g: every group empty → the caller prints no line at all, not a bare newline" \
  "$(last_byte_is_newline "$b5_bytes")" "not-newline"
check "23g: every group empty → the render is one newline-free path line" \
  "$(grep -c '' "$b5_bytes" | tr -d ' ')" "1"

# --- 23h. The pet, and the stress scan that fed it, are GONE ----------------
# B09 deletes group 5 outright. What was a table of stress tiers is now a table
# of the same fixtures asserting the group's absence, because each of them used
# to produce a DIFFERENT mood: a stress scan left half-deleted, or a pet
# emitted from one branch and not another, shows up as one of these five and
# not the others. A single "no pet" case against one payload would not.
#
# Each case pins two things. The pet's own alphabet must be absent (all four
# tiers' faces and effects at once, so no frame of any mood can slip through),
# AND the line must end on the last DATA group with no trailing separator --
# `_sl_burn_group` drops an absent group's separator, so a pet deleted without
# its separator would leave a dangling │ that the absence check alone would
# miss.
B5_PET_GLYPHS='😾|🙀|😿|😼|🐱|😽|😺|😸|😹|😻|🔥|💢|💥|💦|°|∘|·|‥|…|♪|♫|♬'
b5_nopet_case() { # label json expected_last_group
  local line
  line=$(burn_only "$2")
  check "23h: $1 → no pet glyph of any tier or frame" \
    "$(printf '%s' "$line" | grep -qE "$B5_PET_GLYPHS" && echo present || echo absent)" "absent"
  check "23h: $1 → the line ends on '$3', no dangling separator" \
    "$(last_group "$line")" "$3"
  check "23h: $1 → line stays well-formed" "$(burn_wellformed "$line")" "yes"
}
# Context 10%, 5-hour 75%, weekly 1%: the max was 75 -> the panic tier. The
# 5-hour group is last, so the line must end on it.
b5_nopet_case "worst meter 75 (ctx 10%, 5h 75%, wk 1%)" \
  "$(burn_json "$B5_WD" 30000 "Opus" "max" 75 "" 1 "" "" "")" \
  "5h 75%"
# Context 116%, no rate limits at all: the max was 116, also panic, and the
# context meter was the only contributor. Here group 3 ends the line.
b5_nopet_case "worst meter 116, context only (ctx 116%, no rate limits)" \
  "$(burn_json "$B5_WD" 350000 "Opus" "max" "" "" "" "" "" "")" \
  "ctx 116%"
# Context 10%, 5-hour ABSENT, weekly 55%: the max over the meters that existed
# was 55 -> the nervous tier.
b5_nopet_case "worst meter 55, one meter absent (ctx 10%, 5h absent, wk 55%)" \
  "$(burn_json "$B5_WD" 30000 "Opus" "max" "" "" 55 "" "" "")" \
  "ctx 10%"
# Context 10%, 5-hour 35%, weekly 1%: the max was 35 -> the alert tier, whose
# effect characters ('·', '‥', '…') are the ones a bare "no emoji" check would
# not have caught, since none of them is an emoji.
b5_nopet_case "worst meter 35 (ctx 10%, 5h 35%, wk 1%)" \
  "$(burn_json "$B5_WD" 30000 "Opus" "max" 35 "" 1 "" "" "")" \
  "5h 35%"
# All three meters low: the max was 10 -> the happy tier.
b5_nopet_case "all meters low (ctx 10%, 5h 1%, wk 1%)" \
  "$(burn_json "$B5_WD" 30000 "Opus" "max" 1 "" 1 "" "" "")" \
  "5h 1%"
# No meter at all: pre-B09 this was the one payload that rendered no pet, so it
# is the case that could pass either way. It still pins that the model group
# renders alone with no separator.
b5_nometer_line=$(burn_only "$(burn_json "$B5_WD" "" "Opus" "max" "" "" "" "" "" "")")
check "23h: no meter of any kind → no pet glyph" \
  "$(printf '%s' "$b5_nometer_line" | grep -qE "$B5_PET_GLYPHS" && echo present || echo absent)" "absent"
check "23h: no meter of any kind → the model group renders alone, no separator" \
  "$(printf '%s' "$b5_nometer_line" | grep -qxE 'Opus max' && echo yes || echo no)" "yes"

# --- 23i. The derived weekly figures (%t, %/d, trend) -----------------------
# used=85 against a reset three days out sits well ahead of the awake even-burn
# line, so the trend is unambiguously positive and its arrow direction is a
# real assertion rather than a coin flip on a near-zero value.
b5_pace_json=$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 85 "$B5_R7_RESET" "" "")
b5_ds2=$(burn_day_start_epoch "$B5_NOW" "$B5_SECS" 2)
b5_t0=$(date +%s)
b5_pace_line=$(burn_only "$b5_pace_json")
b5_t1=$(date +%s)

check "23i: today's remaining share renders as B01 computes it (%t)" \
  "$(today_token "$b5_pace_line")" "$(burn_expect_today 85 "$B5_R7_RESET" 2 6)"

b5_pace_ok=no
for _p in $(burn_metric_candidates 2 85 "$B5_R7_RESET" "$b5_ds2" 21600 "$b5_t0" "$b5_t1"); do
  printf '%s' "$b5_pace_line" | grep -qF "${_p}%/d" && b5_pace_ok=yes
done
check "23i: sustainable pace renders as B01 computes it (%/d)" "$b5_pace_ok" "yes"

b5_trend_ok=no
for _d in $(burn_metric_candidates 3 85 "$B5_R7_RESET" "$b5_ds2" 21600 "$b5_t0" "$b5_t1"); do
  if [ "${_d#-}" = "$_d" ]; then _arrow='▲'; else _arrow='▼'; fi
  printf '%s' "$b5_pace_line" | grep -qE "${_arrow}[+-]?${_d#-}([^0-9]|\$)" && b5_trend_ok=yes
done
check "23i: the trend renders with B01's magnitude and the arrow its sign implies" \
  "$b5_trend_ok" "yes"
check "23i: ahead of the even-burn line points up, never down" \
  "$(printf '%s' "$b5_pace_line" | grep -qF '▼' && echo present || echo absent)" "absent"
check "23i: the weekly group carries all four figures at once, in order" \
  "$(printf '%s' "$b5_pace_line" | grep -qE 'wk 85%.*%t.*%/d.*▲' && echo yes || echo no)" "yes"

# --- 23j. B01 returning NA for today's share --------------------------------
# A degenerate slice: the day starts at the current hour and the next three
# hours count as sleep, so every second between the day-start and a reset
# fifteen minutes out is asleep. B01 answers NA for %t while still producing a
# pace and a trend -- so %t alone drops out and the other two still render.
b5_na_hour=$(( 10#$_b5h ))
b5_na_reset=$(( B5_NOW + 900 ))
b5_na_json=$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 32 "$b5_na_reset" "" "")
b5_na_ds=$(burn_day_start_epoch "$B5_NOW" "$B5_SECS" "$b5_na_hour")
check "23j: the fixture really is degenerate (B01 answers NA for today's share)" \
  "$(burn_metrics 32 0 "$B5_NOW" "$b5_na_reset" "$b5_na_ds" 10800 | awk '{print $1}')" "NA"
b5_na_line=$(burn_only "$b5_na_json" "CLAM_STATUSLINE_DAY_START=$b5_na_hour" "CLAM_STATUSLINE_SLEEP_HOURS=3")
check "23j: NA today's share → the %t sub-segment is omitted" \
  "$(printf '%s' "$b5_na_line" | grep -qF '%t' && echo present || echo absent)" "absent"
check "23j: NA today's share → the literal 'NA' is never rendered" \
  "$(printf '%s' "$b5_na_line" | grep -qF 'NA' && echo present || echo absent)" "absent"
check "23j: NA today's share → pace still renders" \
  "$(printf '%s' "$b5_na_line" | grep -qE '[0-9]%/d' && echo yes || echo no)" "yes"
check "23j: NA today's share → the trend still renders" \
  "$(printf '%s' "$b5_na_line" | grep -qE '(▲|▼)[+-]?[0-9]+' && echo yes || echo no)" "yes"
check "23j: NA today's share → wk used% still renders" \
  "$(printf '%s' "$b5_na_line" | grep -qE 'wk 32%' && echo yes || echo no)" "yes"
check "23j: NA today's share → line stays well-formed" \
  "$(burn_wellformed "$b5_na_line")" "yes"

# --- 23k. Rate-limit figures are LIVE, never cached -------------------------
# Server-side quota state: a stale figure is worse than none, so these never
# enter the segment bundle. Seeded cold at 10%, then re-rendered WARM (same
# cache key, well inside the TTL) with the payload now reporting 80%.
B5LIVE_WD="$TMPROOT/b5-live-wd"; mk_wt "$B5LIVE_WD"
B5LIVE_DIR="$TMPROOT/b5-live-cache"
b5_live_a=$(burn_json "$B5LIVE_WD" 145230 "Opus" "max" 10 "$B5_R5_RESET" "" "" "" "")
b5_live_b=$(burn_json "$B5LIVE_WD" 145230 "Opus" "max" 80 "$B5_R5_RESET" "" "" "" "")
render_cached "$b5_live_a" "$B5LIVE_DIR" 5 >/dev/null      # cold: seeds the bundle
b5_live_out=$(render_cached "$b5_live_b" "$B5LIVE_DIR" 5)  # warm: same key, within TTL
check "23k: a warm render shows the payload's NEW 5-hour percentage (80%)" \
  "$(burn_of "$b5_live_out" | grep -qE '5h 80%' && echo yes || echo no)" "yes"
check "23k: the superseded 10% figure does not survive into the warm render" \
  "$(burn_of "$b5_live_out" | grep -qE '5h 10%' && echo present || echo absent)" "absent"

# --- 23l. Warm-render process budget, with the burnrate line exercised ------
# The contract's Invariants clause, measured by the PATH-shim harness. This
# payload carries rate_limits AND a cost figure, so B01's awk and B02's awk are
# both genuinely on the warm path -- unlike section 16's payload, which has no
# rate limits and so exercises neither.
#
# The cap is 12: the pre-uplift warm render measured 8, and the line adds at
# most three (B01's awk, B02's awk, and one `date` for the local time-of-day
# day-start anchor, alongside the existing shared UTC `date`). 12 was fixed in
# advance and is not a figure to retune to whatever the implementation happens
# to measure.
B5INV_DIR="$TMPROOT/b5-inv-cache"
B5INV_WD="$TMPROOT/b5-inv-wd"; mk_wt "$B5INV_WD"
b5inv_json="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"},\"workspace\":{\"current_dir\":\"$B5INV_WD\"},$ctx,\"transcript_path\":\"\",\"session_id\":\"sess-b5\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":$B5_R5_RESET},\"seven_day\":{\"used_percentage\":62,\"resets_at\":$B5_R7_RESET}},\"cost\":{\"total_lines_added\":503,\"total_lines_removed\":16,\"total_cost_usd\":12.34}}"

b5_sentinel_before=$(find "$SENTINEL_PROJECTS_DIR" | sort)
render_shim "$b5inv_json" "$B5INV_DIR" 5          # cold: seeds bundle + tick anchor
render_shim "$b5inv_json" "$B5INV_DIR" 5          # warm: same key, within TTL
b5_warm_total=$(shim_count "$SHIM_LOG")
b5_warm_jq=$(shim_count "$SHIM_LOG" jq)
b5_warm_date=$(shim_count "$SHIM_LOG" date)
b5_warm_awk=$(shim_count "$SHIM_LOG" awk)
b5_warm_git=$(shim_count "$SHIM_LOG" git)
b5_warm_ccost=$(shim_count "$CCOST_LOG_FILE")
b5_sentinel_after=$(find "$SENTINEL_PROJECTS_DIR" | sort)

check "23l: warm render with a full burnrate payload invokes at most 12 external commands" \
  "$([ "${b5_warm_total:-99}" -le 12 ] && echo yes || echo no)" "yes"
check "23l: warm render runs exactly one jq (the burnrate fields ride the same stdin parse)" \
  "$([ "${b5_warm_jq:-99}" -eq 1 ] && echo yes || echo no)" "yes"
check "23l: warm render runs at most two date (shared UTC + local time-of-day anchor)" \
  "$([ "${b5_warm_date:-99}" -le 2 ] && echo yes || echo no)" "yes"
check "23l: warm render runs at most two awk (one in B01, one in B02)" \
  "$([ "${b5_warm_awk:-99}" -le 2 ] && echo yes || echo no)" "yes"
check "23l: warm render still does not invoke git" \
  "$([ "${b5_warm_git:-1}" -eq 0 ] && echo yes || echo no)" "yes"
check "23l: warm render still does not invoke ccost.sh" \
  "$([ "${b5_warm_ccost:-1}" -eq 0 ] && echo yes || echo no)" "yes"
check "23l: warm render still opens nothing under CLAUDE_PROJECTS_DIR" \
  "$b5_sentinel_after" "$b5_sentinel_before"

# --- 23m. Degradation never fails the render --------------------------------
# Any component returning non-zero drops that figure or its whole group, and
# the rest of the line still renders. Nothing but the line itself ever reaches
# stdout.

# 23m-i. B01 cannot compute: a weekly reset already in the past. burn_metrics
#        returns non-zero, so %t, %/d and the trend all drop -- and wk used%,
#        every other group, and the render itself survive.
b5_pastreset_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" 42 "$B5_R5_RESET" 62 "$(( B5_NOW - 3600 ))" "" "")")
check "23m: weekly reset already past → wk 62% still renders" \
  "$(printf '%s' "$b5_pastreset_line" | grep -qE 'wk 62%' && echo yes || echo no)" "yes"
check "23m: weekly reset already past → the three derived figures all drop" \
  "$(printf '%s' "$b5_pastreset_line" | grep -qE '%t|%/d|▲|▼' && echo present || echo absent)" "absent"
check "23m: weekly reset already past → every other group still renders" \
  "$(printf '%s' "$b5_pastreset_line" | grep -qE '^Opus max │' \
     && printf '%s' "$b5_pastreset_line" | grep -qE 'ctx 48%' \
     && printf '%s' "$b5_pastreset_line" | grep -qE '5h 42%' && echo yes || echo no)" "yes"
check "23m: weekly reset already past → line stays well-formed" \
  "$(burn_wellformed "$b5_pastreset_line")" "yes"

# 23m-ii. Scratch state unwritable. Neither B03's animation frame file nor
#         B02's tick state file has a contract-fixed location, so this blocks
#         every location the implementation could reasonably have chosen at
#         once: a regular FILE occupies the segment-cache path (so mkdir on it
#         fails), and $HOME points inside a directory that does not exist.
#         Whichever it picked, the write fails -- and the whole line must still
#         render, because B03 freezes the animation and burn_tick_frac degrades
#         to a zero fraction rather than either of them failing.
B5BLOCK_PARENT="$TMPROOT/b5-blocked-parent"; mkdir -p "$B5BLOCK_PARENT"
B5BLOCK="$B5BLOCK_PARENT/blocked-cache"; : > "$B5BLOCK"
b5_blocked_out=$(printf '%s' "$b5_full" \
  | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 HOME="$TMPROOT/b5-no-such-parent/home" \
      CLAM_STATUSLINE_CACHE_DIR="$B5BLOCK" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=5 \
      bash "$CONTEXT" 2>/dev/null \
  | sed -E "s/${ESC}\\[[0-9;]*m//g")
b5_blocked_line=$(burn_of "$b5_blocked_out")
check "23m: unwritable scratch → all four groups still render" \
  "$(printf '%s' "$b5_blocked_line" | grep -o '│' | wc -l | tr -d ' ')" "3"
check "23m: unwritable scratch → the data groups keep their figures" \
  "$(printf '%s' "$b5_blocked_line" | grep -qE '^Opus max │ wk 62%' \
     && printf '%s' "$b5_blocked_line" | grep -qE 'ctx 48%' \
     && printf '%s' "$b5_blocked_line" | grep -qE '5h 1%' && echo yes || echo no)" "yes"
check "23m: unwritable scratch → line stays well-formed" \
  "$(burn_wellformed "$b5_blocked_line")" "yes"
check "23m: unwritable scratch → no scratch/error text leaks onto stdout" \
  "$(printf '%s\n' "$b5_blocked_out" | grep -qiE 'no such file|cannot create|permission|not writable|error' && echo present || echo absent)" "absent"

# 23m-iii. The burnrate libraries are missing entirely. context.sh sources each
#          of the three only when the file exists, so an install that shipped
#          without them leaves their functions undefined; the groups needing
#          them are omitted and the render still succeeds. Same shadow-tree
#          trick sections 16-20 use, minus the burn-*.sh symlinks.
B5NOLIB="$TMPROOT/b5-nolib"; mkdir -p "$B5NOLIB/scripts" "$B5NOLIB/lib"
ln -s "$CONTEXT" "$B5NOLIB/scripts/context.sh"
ln -s "$SCRIPT_DIR/../lib/platform.sh" "$B5NOLIB/lib/platform.sh"
ln -s "$SCRIPT_DIR/../lib/states.sh" "$B5NOLIB/lib/states.sh"
ln -s "$SCRIPT_DIR/../lib/states.tsv" "$B5NOLIB/lib/states.tsv"
b5_nolib_out="$TMPROOT/b5-nolib.out"
printf '%s' "$b5_full" \
  | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
      CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/b5-nolib-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
      bash "$B5NOLIB/scripts/context.sh" > "$b5_nolib_out" 2>/dev/null
b5_nolib_ec=$?
check "23m: burnrate libraries absent → the render still exits 0" "$b5_nolib_ec" "0"
check "23m: burnrate libraries absent → the path line still renders" \
  "$(sed -E "s/${ESC}\\[[0-9;]*m//g" "$b5_nolib_out" | sed -n '1p' | grep -qF "$(basename "$B5_WD")" && echo yes || echo no)" "yes"
check "23m: burnrate libraries absent → no diagnostic text reaches stdout" \
  "$(grep -qiE 'command not found|NotImplemented|no such file|syntax error|awk:' "$b5_nolib_out" && echo present || echo absent)" "absent"

# 23m-iv. Nothing but the line itself ever reaches stdout, and no component
#         writes to stderr in normal operation -- this feeds a statusline, so a
#         stray diagnostic lands in the user's terminal either way.
b5_ok_out="$TMPROOT/b5-ok.out"
b5_ok_err="$TMPROOT/b5-ok.err"
printf '%s' "$b5_full" \
  | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
      CLAM_STATUSLINE_CACHE_DIR="$B5_CACHE" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
      bash "$CONTEXT" > "$b5_ok_out" 2>"$b5_ok_err"
b5_ok_ec=$?
check "23m: a normal burnrate render exits 0" "$b5_ok_ec" "0"
check "23m: a normal burnrate render writes nothing to stderr" \
  "$(wc -c < "$b5_ok_err" | tr -d ' ')" "0"
check "23m: a normal burnrate render writes exactly two lines to stdout, nothing else" \
  "$(sed -E "s/${ESC}\\[[0-9;]*m//g" "$b5_ok_out" | grep -c '' | tr -d ' ')" "2"

# --- 23n. The two environment knobs -----------------------------------------
# CLAM_STATUSLINE_DAY_START (0..23, default 2) and CLAM_STATUSLINE_SLEEP_HOURS (default 6), both consumed
# here and passed down to B01. A non-integer or out-of-range value falls back
# to its default rather than erroring.
#
# Pinned through %t -- the one derived figure that does not move with the
# render's `now`, only with the day-start anchor it shares with this suite --
# against B01's output for the anchor each knob value SHOULD produce. A
# fallback case therefore fails both when the bad value is honoured and when a
# good value is ignored: those two have different expected numbers, not a
# shared "it didn't crash".
#
# That reasoning only holds while the settings land on DIFFERENT figures, and
# what decides whether they do is the fixture: its reset instant and its used%.
# The two do quite different jobs, and only one of them is a lever at all.
#
#   The RESET'S PHASE is what separates the sleep settings, and nothing else
#   is. %t reads today's slice off the week [reset-7d, reset) as a ratio of
#   awake seconds; when that week BEGINS INSIDE A SLEEP WINDOW, B01's awake
#   walk trims the same remainder-of-the-sleep from the numerator and the
#   denominator alike, the sleep length cancels out of the ratio, and (2,0),
#   (2,6) and (2,12) collapse onto one figure. A reset a whole number of days
#   out from `now` starts the week at the CURRENT time of day, so which
#   settings collapsed depended on the hour the suite happened to run at --
#   02:00-08:00 local made (2,6) and (2,12) equal, and four of the ten checks
#   below vacuous. Anchoring the reset to the DAY-START instead of to `now`
#   fixes that phase once and for all: 3d17h30m past the default day-start
#   begins the week 17.5h into a day, past the longest sleep window under test
#   (12h) and short of the day's end, so every sleep length trims a different
#   amount at every hour of the clock. Only the whole-day COUNT still moves
#   with the clock, and that shifts every setting by the same 100 points.
#
#   The half hour is not decoration. %t is printed through awk's "%.0f", and a
#   round 3d18h works out to exactly n+0.5 for the eight-hour sleep setting
#   23r reuses, at every integer used%. Both this suite and the render derive
#   the day-start anchor from TWO `date` calls -- an epoch, then a local H:M:S
#   -- so either can read its midnight a second early and the two anchors can
#   differ by a second. A second is worth ~0.002 of a point here: invisible,
#   except exactly on the boundary, where it decides the printed integer and
#   the check becomes a coin flip. b5_knob_figure asserts that margin rather
#   than trusting the arithmetic to keep it.
#
#   The USED% cannot separate anything. All these settings measure one awake
#   day out of the same seven, so used% shifts all their figures by the same
#   amount -- it moves the whole set, never the gaps within it. What it does
#   decide is whether they land in the band where B01 reports %t faithfully:
#   above it %t saturates at B01's cap of 100, below it goes negative, and at
#   either end two settings can agree for a reason that has nothing to do with
#   the knobs. So it is SCANNED at runtime for the first value putting every
#   setting this fixture is rendered against -- the four here, plus the two
#   23r reuses -- strictly inside 1..99, rather than fixed at a literal that
#   is only in band for part of the day.
B5_KNOB_RESET=$(( $(burn_day_start_epoch "$B5_NOW" "$B5_SECS" 2) + 3 * 86400 + 63000 ))

# b5_knob_figure(used day_start sleep_hours): B01's %t for that setting, but
# only when nudging the day-start anchor two seconds either way leaves the
# printed integer alone -- otherwise the word "unstable", which no candidate
# below is allowed to carry. Two seconds is more than the one the two clocks
# can disagree by, so a figure that survives it is one the render cannot
# disagree with this suite about.
b5_knob_figure() { # used day_start sleep_hours
  local ds v0 vlo vhi
  ds=$(burn_day_start_epoch "$B5_NOW" "$B5_SECS" "$2") || return 1
  v0=$(burn_metrics "$1" 0 "$B5_NOW" "$B5_KNOB_RESET" "$ds" "$(( $3 * 3600 ))" | awk '{print $1}')
  vlo=$(burn_metrics "$1" 0 "$B5_NOW" "$B5_KNOB_RESET" "$(( ds - 2 ))" "$(( $3 * 3600 ))" | awk '{print $1}')
  vhi=$(burn_metrics "$1" 0 "$B5_NOW" "$B5_KNOB_RESET" "$(( ds + 2 ))" "$(( $3 * 3600 ))" | awk '{print $1}')
  if [ "$v0" = "$vlo" ] && [ "$v0" = "$vhi" ]; then printf '%s\n' "$v0"; else printf 'unstable\n'; fi
}
# Every (day_start, sleep_hours) setting the knob fixture is rendered against,
# as that figure for a candidate used%, one per line.
b5_knob_figures() { # used
  b5_knob_figure "$1" 2 6      # 23n: both knobs defaulted
  b5_knob_figure "$1" 14 6     # 23n: day start moved
  b5_knob_figure "$1" 2 0      # 23n: sleep off
  b5_knob_figure "$1" 2 12     # 23n: sleep doubled
  b5_knob_figure "$1" 8 6      # 23r: day start "08"
  b5_knob_figure "$1" 2 8      # 23r: sleep "08"
}
B5_KNOB_USED=""
for (( _b5u = 45; _b5u <= 75; _b5u++ )); do
  _b5figs=$(b5_knob_figures "$_b5u")
  [ "$(printf '%s\n' "$_b5figs" | sort -u | wc -l | tr -d ' ')" = "6" ] || continue
  printf '%s\n' "$_b5figs" | grep -qvE '^([1-9]|[1-9][0-9])$' && continue
  B5_KNOB_USED="$_b5u"; break
done
check "23n: some used% in 45..75 puts all six settings on a distinct in-band figure" \
  "$([ -n "$B5_KNOB_USED" ] && echo found || echo none)" "found"
# Only so the payload below stays well-formed when the scan came up empty: the
# checks then fail on their own figures rather than on a malformed render.
B5_KNOB_USED="${B5_KNOB_USED:-60}"
b5_knob=$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" "$B5_KNOB_USED" "$B5_KNOB_RESET" "" "")
check "23n: CLAM_STATUSLINE_DAY_START unset → B01's default 02:00 day start" \
  "$(today_token "$(burn_only "$b5_knob")")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 6)"
check "23n: CLAM_STATUSLINE_DAY_START=14 is consumed (the day-start anchor moves with it)" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_DAY_START=14")")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 14 6)"
check "23n: CLAM_STATUSLINE_DAY_START out of range (99) falls back to 2" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_DAY_START=99")")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 6)"
check "23n: CLAM_STATUSLINE_DAY_START negative (-1) falls back to 2" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_DAY_START=-1")")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 6)"
check "23n: CLAM_STATUSLINE_DAY_START non-integer ('half-past') falls back to 2" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_DAY_START=half-past")")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 6)"
check "23n: CLAM_STATUSLINE_SLEEP_HOURS unset → B01's default six sleep hours" \
  "$(today_token "$(burn_only "$b5_knob")")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 6)"
check "23n: CLAM_STATUSLINE_SLEEP_HOURS=0 is consumed (degenerates to plain calendar time)" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_SLEEP_HOURS=0")")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 0)"
check "23n: CLAM_STATUSLINE_SLEEP_HOURS=12 is consumed" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_SLEEP_HOURS=12")")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 12)"
check "23n: CLAM_STATUSLINE_SLEEP_HOURS negative (-1) falls back to 6" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_SLEEP_HOURS=-1")")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 6)"
check "23n: CLAM_STATUSLINE_SLEEP_HOURS non-integer ('six') falls back to 6" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_SLEEP_HOURS=six")")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 6)"
check "23n: a rejected knob value never breaks the render" \
  "$(burn_wellformed "$(burn_only "$b5_knob" "CLAM_STATUSLINE_DAY_START=half-past" "CLAM_STATUSLINE_SLEEP_HOURS=six")")" "yes"
# The fixture really does discriminate: if two of the four settings landed on
# one figure the ten checks above would agree no matter what the knobs did.
# Re-derived from B5_KNOB_USED -- the value the ten actually rendered against
# -- by four direct calls rather than through b5_knob_figures, so a scan that
# tested one thing and published another is caught rather than echoed back.
b5_knob_four=$(printf '%s\n' \
  "$(b5_knob_figure "$B5_KNOB_USED" 2 6)" \
  "$(b5_knob_figure "$B5_KNOB_USED" 14 6)" \
  "$(b5_knob_figure "$B5_KNOB_USED" 2 0)" \
  "$(b5_knob_figure "$B5_KNOB_USED" 2 12)")
check "23n: the knob fixture separates the settings (four distinct %t figures)" \
  "$(printf '%s\n' "$b5_knob_four" | sort -u | wc -l | tr -d ' ')" "4"
# Distinctness alone is not enough. At B01's cap, below zero, or on a rounding
# boundary two settings can agree -- or a figure can differ from the render's
# -- for a reason that has nothing to do with the knobs, and a fixture drifting
# towards any of those would lose its teeth one check at a time without the
# count above ever changing. So each of the four must also be a plain 1..99,
# which "unstable" and B01's own 100 and negatives are all excluded from.
check "23n: and all four are in band (1..99) and unmoved by a two-second anchor nudge" \
  "$(printf '%s\n' "$b5_knob_four" | grep -cE '^([1-9]|[1-9][0-9])$' | tr -d ' ')" "4"

# --- 23o. A 5h group whose reset timestamp is absent -------------------------
# The Errors clause permits dropping "that figure OR its whole group", and the
# Edge-cases clause already settles the identical case for the weekly group
# ("Weekly data present but its reset timestamp absent: wk used% still renders;
# %t, %/d and the trend do not"), so the five-hour group follows by symmetry:
# the countdown drops, the used% stays.
#
# Worth pinning separately from 23b-ii because of the asymmetry between the two
# groups: the weekly reset feeds three figures out of four, so reading it as
# "drop the group" is visibly wrong but only partly so, while the countdown is
# the ONLY thing the five-hour reset feeds -- there the same misreading silently
# deletes a live quota meter and leaves a line that still looks plausible.
b5_5hnores_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" 42 "" "" "" "" "")")
check "23o: five_hour without its reset → 5h 42% still renders" \
  "$(printf '%s' "$b5_5hnores_line" | grep -qE '5h 42%' && echo yes || echo no)" "yes"
# What the group carries is asserted as an EQUALITY on the group's own text
# (everything from 5h up to the next separator, trailing space trimmed) rather
# than as an "absent" match on the line. All three wrong outcomes then fail with
# a distinguishable value: a surviving countdown reads "5h 42% (4h54m)", a
# dropped group and an unrendered line both read "". An absence check would
# instead pass vacuously on the two latter.
#
# B09 adds a fourth wrong outcome this equality already covers and an absence
# check never could: parens emitted around a countdown that dropped, leaving
# "5h 42% ()". The contract forbids that explicitly -- the parens "appear only
# when a countdown is actually rendered ... never leaving an empty ()" -- so it
# is also pinned on its own below, against the whole line rather than the group,
# since an empty pair anywhere is the defect.
check "23o: five_hour without its reset → the 5h group is the used% and nothing else (no countdown)" \
  "$(printf '%s' "$b5_5hnores_line" | grep -oE '5h[^│]*' | head -n1 | sed 's/[[:space:]]*$//')" \
  "5h 42%"
check "23o: five_hour without its reset → no empty parens are left behind" \
  "$(printf '%s' "$b5_5hnores_line" | grep -qF '()' && echo present || echo absent)" "absent"
check "23o: five_hour without its reset → no stray paren of either hand survives" \
  "$(printf '%s' "$b5_5hnores_line" | grep -qE '[()]' && echo present || echo absent)" "absent"
check "23o: five_hour without its reset → line stays well-formed" \
  "$(burn_wellformed "$b5_5hnores_line")" "yes"

# --- 23p. An absent model vs an unrecognised one ----------------------------
# Pre-B09 this pair was told apart by the mascot: B03 mapped an UNKNOWN model to
# 🤖 while an ABSENT model rendered none, the same "empty is not zero"
# distinction B04's contract draws for the rate-limit fields. B09 deletes the
# mascot, so the distinction now shows in the NAME -- an unrecognised model
# still renders its name, an absent one renders nothing but the tier -- and the
# pair keeps its teeth for the same reason it had them before: the absent case
# alone says nothing about what an unknown name does, and vice versa.
#
# Both halves also pin that NEITHER emits a mascot. That is what stops a
# half-applied B09 -- the prefix dropped on the recognised path and left on the
# fallback path, or the reverse -- from passing.
b5_nomodel_line=$(burn_only "$(burn_json "$B5_WD" 145230 "" "high" "" "" "" "" "" "")")
check "23p: model absent, effort present → group 1 is the bare tier (no mascot of any kind, no leading separator)" \
  "$(printf '%s' "$b5_nomodel_line" | grep -qE '^high( │|$)' \
     && ! printf '%s' "$b5_nomodel_line" | grep -qE "$B5_MASCOTS" && echo yes || echo no)" "yes"
b5_unknownmodel_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Gemini" "high" "" "" "" "" "" "")")
check "23p: model present but unrecognised → group 1 leads with the NAME, not B03's fallback mascot" \
  "$(printf '%s' "$b5_unknownmodel_line" | grep -qE '^Gemini high( │|$)' \
     && ! printf '%s' "$b5_unknownmodel_line" | grep -qE "$B5_MASCOTS" && echo yes || echo no)" "yes"

# --- 23q. The group separator is a DIM │ ------------------------------------
# "Dim" in the Outputs clause is SGR 2. 23a counts │ glyphs on the ANSI-STRIPPED
# line, which by construction cannot see the escape around them, so the styling
# is currently assumed rather than verified; this pins the byte sequence itself
# against the RAW render.
#
# Counted rather than merely found, so a line whose separators are dim in one
# place and unstyled in another cannot pass. (Pre-B09 the pet's dimmed effect
# character was the near-miss this had to rule out; B09 deletes the pet, and
# the sequence pinned here has the │ glyph between the two escapes regardless.)
b5_sep=$(printf '\033[2m│\033[0m')
b5_sep_raw=$(burn_render_raw "$b5_full")
check "23q: all three separators of a four-group line are the exact dim sequence ESC[2m│ESC[0m" \
  "$(printf '%s' "$b5_sep_raw" | grep -oaF "$b5_sep" | wc -l | tr -d ' ')" "3"

# --- 23r. Zero-padded knob values are DECIMAL, not octal --------------------
# CLAM_STATUSLINE_DAY_START=08 and CLAM_STATUSLINE_SLEEP_HOURS=08 are values a user has written perfectly
# correctly -- a zero-padded hour is how clocks are written. Bash arithmetic
# reads a leading-zero numeric string as OCTAL, in which 08 and 09 are not
# merely the wrong number but a hard error ("value too great for base"), and an
# expansion error in a non-interactive shell exits it -- so what vanishes is
# the whole burnrate line, not just the figures the knob feeds.
#
# The range check the knobs already carry is no guard against this: `[ 08 -gt
# 23 ]` compares decimal 8 and passes straight over exactly the value the
# arithmetic beneath it cannot evaluate. Only the arithmetic path is affected,
# which is why the case survives every check in 23n.
#
# Pinned through %t on 23n's fixture, and for 23n's reason: it is the one
# derived figure that does not drift with the render's clock, and it separates
# one anchor from another rather than merely proving the render survived. Each
# padded value is pinned BOTH to the figure its anchor should produce and to
# the unpadded spelling's own render, so "dropped for both" fails the first
# check even where the two anchors' figures happen to coincide.
b5_pad_ds_line=$(burn_only "$b5_knob" "CLAM_STATUSLINE_DAY_START=08")
check "23r: CLAM_STATUSLINE_DAY_START=08 anchors the day at 08:00 (decimal 8, not an octal error)" \
  "$(today_token "$b5_pad_ds_line")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 8 6)"
check "23r: CLAM_STATUSLINE_DAY_START=08 renders the same %t as the unpadded 8" \
  "$(today_token "$b5_pad_ds_line")" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_DAY_START=8")")"
check "23r: CLAM_STATUSLINE_DAY_START=08 → the weekly group still carries all four figures" \
  "$(printf '%s' "$b5_pad_ds_line" | grep -qE "wk $B5_KNOB_USED%.*%t.*%/d.*(▲|▼)" && echo yes || echo no)" "yes"

b5_pad_slp_line=$(burn_only "$b5_knob" "CLAM_STATUSLINE_SLEEP_HOURS=08")
check "23r: CLAM_STATUSLINE_SLEEP_HOURS=08 is eight sleep hours (decimal 8, not an octal error)" \
  "$(today_token "$b5_pad_slp_line")" "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 8)"
check "23r: CLAM_STATUSLINE_SLEEP_HOURS=08 renders the same %t as the unpadded 8" \
  "$(today_token "$b5_pad_slp_line")" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_SLEEP_HOURS=8")")"

# Forcing base 10 must not become forcing the value through: the fallbacks 23n
# pins still hold, and a padded value that is STILL out of range once read as
# decimal falls back exactly as its unpadded twin does. CLAM_STATUSLINE_SLEEP_HOURS=99 is
# the one out-of-range case 23n does not cover, and 099 is the pair of the two.
check "23r: CLAM_STATUSLINE_SLEEP_HOURS out of range (99) still falls back to 6" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_SLEEP_HOURS=99")")" \
  "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 6)"
check "23r: CLAM_STATUSLINE_DAY_START=099 reads as 99, is still out of range, still falls back to 2" \
  "$(today_token "$(burn_only "$b5_knob" "CLAM_STATUSLINE_DAY_START=099")")" \
  "$(burn_expect_today "$B5_KNOB_USED" "$B5_KNOB_RESET" 2 6)"

# === 24. B09 burn-line-labels ===============================================
# Contract: the B09 amendment to sl_render_burn_line's docblock. Section 23
# already carries every clause B09 only RESHAPES -- group counts, separators,
# the vanished pet, the label spellings. This section carries the four it adds
# outright, the first three of which are invisible on an ANSI-stripped line:
#   a. each label sits INSIDE its meter's colour sequence, exactly where the
#      emoji did, so the colour still spans label and figure together;
#   b. the 5-hour countdown's parens sit OUTSIDE any colour sequence;
#   c. the line's ALPHABET is emoji-free, while the ambiguous-width non-emoji
#      symbols (│ ▲ ▼) are deliberately kept;
#   d. amendment 2 -- the weekly and 5-hour figures print as integers.

# --- 24a. Labels inside the colour, at every meter tier ---------------------
# Expected sequences are DERIVED from B03's burn_plan_color, per this file's
# standing rule: the thresholds are burn-theme's own clause with its own suite,
# and what is under test here is that context.sh still routes the meter through
# it and now wraps LABEL AND FIGURE TOGETHER in what it returns. A label left
# outside would render "wk \033[38;5;196m70%" and fail every case below.
#
# Run across all four tiers rather than once: the weekly and 5-hour groups take
# their colour from the same helper but are assembled by separate code, and a
# label moved outside the sequence in one of them is exactly the half-applied
# edit this catches.
b24_meter_case() { # label used expected_group_text
  local raw
  raw=$(burn_render_raw "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" "$2" "" "" "")")
  check "24a: weekly meter at $2% ($1) wraps '$3' in burn_plan_color's sequence" \
    "$(printf '%s' "$raw" | grep -qaF "$(burn_plan_color "$2")$3" && echo yes || echo no)" "yes"
}
b24_meter_case "red tier"    70 "wk 70%"
b24_meter_case "orange tier" 50 "wk 50%"
b24_meter_case "yellow tier" 30 "wk 30%"
b24_meter_case "green tier"  29 "wk 29%"

b24_5h_raw=$(burn_render_raw "$(burn_json "$B5_WD" 145230 "Opus" "max" 88 "" "" "" "" "")")
check "24a: the 5-hour meter wraps '5h 88%' in burn_plan_color's sequence too" \
  "$(printf '%s' "$b24_5h_raw" | grep -qaF "$(burn_plan_color 88)5h 88%" && echo yes || echo no)" "yes"
check "24a: the ctx label is inside burn_ctx_state's colour (145,230/300,000 = 48%, green 40)" \
  "$(printf '%s' "$b24_5h_raw" | grep -qaF "$(printf '\033[38;5;40m')ctx 48%" && echo yes || echo no)" "yes"

# A decimal used% colours off its integer part -- the ${r7%%.*} trim that feeds
# burn_plan_color is untouched by B09 -- and, per amendment 2 below, PRINTS
# that same integer, so the figure and the colour can never disagree.
b24_float_raw=$(burn_render_raw "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 62.7 "" "" "")")
check "24a: a decimal used% colours and prints the same integer part" \
  "$(printf '%s' "$b24_float_raw" | grep -qaF "$(burn_plan_color 62)wk 62%" && echo yes || echo no)" "yes"

# --- 24b. The countdown's parens are OUTSIDE the colour ---------------------
# burn_reset_str returns plain text, so "outside any colour sequence it
# returns" resolves to: the group's closing reset comes FIRST, then " (", then
# the countdown, then ")" -- with no escape anywhere between the brackets.
# Bracketed over [t0,t1] for burn_reset_str's minute roll, exactly as 23a is.
b24_t0=$(date +%s)
b24_raw=$(burn_render_raw "$b5_full")
b24_t1=$(date +%s)
b24_paren_ok=no
b24_inside_ok=no
for (( _n = b24_t0; _n <= b24_t1; _n++ )); do
  _cd=$(burn_reset_str "$B5_R5_RESET" "$_n")
  printf '%s' "$b24_raw" | grep -qaF "$(printf '\033[0m') ($_cd)" && b24_paren_ok=yes
  # The failure this rules out is the mirror image: parens emitted INSIDE the
  # meter's colour run, which reads "<plan colour>5h 1% (4h54m)<reset>".
  printf '%s' "$b24_raw" | grep -qaF "$(burn_plan_color 1)5h 1% ($_cd)" && b24_inside_ok=yes
done
check "24b: the parens sit outside the group's colour (reset, then ' (countdown)')" \
  "$b24_paren_ok" "yes"
check "24b: the parens are NOT inside the meter's colour run" "$b24_inside_ok" "no"
check "24b: exactly one pair of parens on the whole line" \
  "$(printf '%s' "$b5_line" | grep -o '[()]' | wc -l | tr -d ' ')" "2"

# --- 24c. The line's alphabet -----------------------------------------------
# "This line emits no emoji" as a property of the whole render rather than of
# the specific glyphs removed, so a NEW emoji arriving later fails too. Applied
# to the payloads that between them reach every group and every sub-segment.
check "24c: the four-group line carries no emoji" "$(burn_no_emoji "$b5_line")" "yes"
check "24c: a weekly group with all four figures carries no emoji" \
  "$(burn_no_emoji "$b5_pace_line")" "yes"
check "24c: a two-group line (no rate limits) carries no emoji" \
  "$(burn_no_emoji "$b5_norl_line")" "yes"
check "24c: an effort-only group (absent model) carries no emoji" \
  "$(burn_no_emoji "$b5_nomodel_line")" "yes"
check "24c: an unrecognised model carries no emoji (no 🤖 fallback)" \
  "$(burn_no_emoji "$b5_unknownmodel_line")" "yes"
# The helper is not vacuous: the three symbols it exempts are the three the
# contract DELIBERATELY keeps, and they are still on the line. Without this a
# render that had dropped │ and the arrows along with the emoji would sail
# through every check above.
check "24c: the dim │ separator is deliberately kept" \
  "$(printf '%s' "$b5_line" | grep -qF '│' && echo yes || echo no)" "yes"
check "24c: the ▲/▼ trend arrows are deliberately kept" \
  "$(printf '%s' "$b5_pace_line" | grep -qE '▲|▼' && echo yes || echo no)" "yes"

# --- 24d. The weekly and 5-hour figures render as INTEGERS ------------------
# B09 amendment 2. The payload delivers IEEE-754 noise and the render showed it
# verbatim -- `5h 14.000000000000002%` is an observed render, not a
# hypothetical. Both meters now print the INTEGER PART, which is the value
# burn_plan_color already thresholds on, so figure and colour cannot disagree.
#
# Asserted on the extracted GROUP rather than on the whole line, because the
# line legitimately carries decimals elsewhere: B01's sustainable pace renders
# as e.g. "5.0%/d", and a model name may carry one ("Haiku 4.5"). A blanket
# "no dot on the line" check would be wrong, not merely blunt.
b24_group() { # line label
  printf '%s' "$1" | grep -oE "$2 [^│]*" | head -n1 | sed 's/[[:space:]]*$//'
}
b24_five() { # r5
  b24_group "$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "$1" "" "" "" "" "")")" '5h'
}
b24_week() { # r7
  b24_group "$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" "$1" "" "" "")")" 'wk'
}

# i. The observed defect, exactly as reported.
check "24d: an IEEE-754-noisy 5-hour figure renders as '5h 14%'" \
  "$(b24_five 14.000000000000002)" "5h 14%"
check "24d: the same noise in the weekly figure renders as 'wk 14%'" \
  "$(b24_week 14.000000000000002)" "wk 14%"

# ii. TRUNCATION, not rounding -- the contract's stated reason being that
#     rounding 49.7 up to 50 while colouring it as 49 would put the figure in
#     the wrong colour band. Both halves are asserted: the digits printed, and
#     the colour they are printed in.
check "24d: 49.7 truncates to 49, it does not round to 50" "$(b24_five 49.7)" "5h 49%"
check "24d: 69.9 truncates to 69, it does not round to 70" "$(b24_week 69.9)" "wk 69%"
b24_trunc_raw=$(burn_render_raw "$(burn_json "$B5_WD" 145230 "Opus" "max" 49.7 "" "" "" "" "")")
check "24d: 49.7 is printed in burn_plan_color 49's band, not 50's" \
  "$(printf '%s' "$b24_trunc_raw" | grep -qaF "$(burn_plan_color 49)5h 49%" && echo yes || echo no)" "yes"
check "24d: the two bands really are different, so that check discriminates" \
  "$([ "$(burn_plan_color 49)" != "$(burn_plan_color 50)" ] && echo yes || echo no)" "yes"

# iii. A bare fraction must not render an EMPTY figure. `${r5%%.*}` of "0.5" is
#      the empty string, which would render "5h %" -- the specific way a
#      one-line truncation gets this wrong.
check "24d: a bare-fraction 5-hour value renders '5h 0%', never '5h %'" \
  "$(b24_five 0.5)" "5h 0%"
check "24d: a bare-fraction weekly value renders 'wk 0%', never 'wk %'" \
  "$(b24_week 0.5)" "wk 0%"

# iv. An integer payload is unaffected -- no trailing "." and no ".0".
check "24d: an integer 5-hour value renders unchanged" "$(b24_five 14)" "5h 14%"
check "24d: an integer weekly value renders unchanged" "$(b24_week 62)" "wk 62%"
# A genuine integer zero is section 23c's clause and stays there; what is new
# here is only the BARE-FRACTION zero above, which is a different failure.

# v. The ctx meter is NOT touched, and is deliberately NOT asserted here. Its
#    pct is `$(( 100 * used_tokens / ctx_budget ))` -- bash integer arithmetic,
#    which cannot carry a fraction -- so there is no truncation clause to cover,
#    and a test asserting one would assert something the contract does not say.
#    That the group still renders its occupancy unchanged is section 23a's
#    clause and stays there.
#
# vi. Presentation ONLY. B01 still receives the value the payload sent, so the
#     DERIVED figures are computed from the full float and not from the printed
#     integer. Pinned on %t, the one derived figure this suite can pin exactly
#     (see burn_expect_today), with a guard proving the two inputs genuinely
#     produce different answers -- otherwise the assertion would pass whichever
#     value the render fed B01.
b24_prec_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 62.7 "$B5_R7_RESET" "" "")")
check "24d: truncation is presentation only -- %t is B01's answer for 62.7" \
  "$(today_token "$b24_prec_line")" "$(burn_expect_today 62.7 "$B5_R7_RESET" 2 6)"
check "24d: and B01's answer for 62.7 differs from its answer for 62, so that discriminates" \
  "$([ "$(burn_expect_today 62.7 "$B5_R7_RESET" 2 6)" != "$(burn_expect_today 62 "$B5_R7_RESET" 2 6)" ] \
     && echo yes || echo no)" "yes"
check "24d: the printed figure is still the truncated integer on that same line" \
  "$(printf '%s' "$b24_prec_line" | grep -qE 'wk 62% ' && echo yes || echo no)" "yes"
check "24d: and no '62.7' survives in the render" \
  "$(printf '%s' "$b24_prec_line" | grep -qF '62.7' && echo present || echo absent)" "absent"

# === 25. B10 line1-text-tags ================================================
# Contract: the classify_pr_emoji docblock, the PR-badge assembly comment and
# the State-segment comment, all in context.sh. Line 1 had NO coverage in this
# file before B10 -- it matched zero PR badges and zero State glyphs -- so this
# section is new coverage rather than retargeted assertions.

# --- 25a. classify_pr_tag: the rename, and the six tags ---------------------
# Called DIRECTLY rather than through a render, the same way section 22 reads
# B04's parsed variables: the bucket logic is "byte-for-byte unchanged, only
# what each bucket echoes changes", and a per-bucket assertion is the only way
# to say that. Sourcing context.sh is safe for the reason parse_vars gives (no
# `exit`, no `set -e`, its own dir resolved via BASH_SOURCE[0]).
B10_CACHE_DIR="$TMPROOT/b10-cache"
b10_min_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\"}"
pr_tag() { # state reviews ci comments
  printf '%s' "$b10_min_json" | (
    export CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache"
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000
    export CLAM_STATUSLINE_CACHE_DIR="$B10_CACHE_DIR" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0
    . "$CONTEXT" >/dev/null 2>&1
    classify_pr_tag "$1" "$2" "$3" "$4" 2>/dev/null
  )
}
# fn_defined(name): whether sourcing context.sh leaves NAME defined.
b10_fn_defined() { # name
  printf '%s' "$b10_min_json" | (
    export CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache"
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000
    export CLAM_STATUSLINE_CACHE_DIR="$B10_CACHE_DIR" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0
    . "$CONTEXT" >/dev/null 2>&1
    declare -f "$1" >/dev/null 2>&1 && echo yes || echo no
  )
}
check "25a: classify_pr_tag exists under its new name" \
  "$(b10_fn_defined classify_pr_tag)" "yes"
# No compatibility alias: the docblock's stated reason is that a stale caller
# comparing against an emoji would silently fall through to the actionable
# branch and badge every PR, so the old name surviving is the defect itself,
# not a harmless leftover.
check "25a: classify_pr_emoji is gone (no compatibility alias)" \
  "$(b10_fn_defined classify_pr_emoji)" "no"

# One case per branch of the bucket chain, in the order the chain tests them.
check "25a: Merged → merged" "$(pr_tag "Merged" "Approved" "Pass" 0)" "merged"
check "25a: Queue Failed → ejected" "$(pr_tag "Queue Failed" "Approved" "Pass" 0)" "ejected"
check "25a: In Queue → queued" "$(pr_tag "In Queue" "Approved" "Pass" 0)" "queued"
check "25a: CI failing → todo" "$(pr_tag "Open" "None" "Fail" 0)" "todo"
check "25a: changes requested → todo" "$(pr_tag "Open" "Changes Requested" "Running" 0)" "todo"
check "25a: commented → todo" "$(pr_tag "Open" "Commented" "Running" 0)" "todo"
check "25a: review not requested → todo" "$(pr_tag "Open" "Not Requested" "Running" 0)" "todo"
check "25a: unread comments → todo" "$(pr_tag "Open" "None" "Running" 3)" "todo"
check "25a: approved and green → todo (it is ready to land)" \
  "$(pr_tag "Open" "Approved" "Pass" 0)" "todo"
check "25a: draft → wip" "$(pr_tag "Draft" "None" "Running" 0)" "wip"
check "25a: stale approval → wip" "$(pr_tag "Open" "Approved (stale)" "Running" 0)" "wip"
check "25a: approved but still running → wip" "$(pr_tag "Open" "Approved" "Running" 0)" "wip"
check "25a: nothing to act on → ok" "$(pr_tag "Open" "None" "Running" 0)" "ok"
# Precedence is part of "byte-for-byte unchanged": the state arms are tested
# BEFORE the review/CI arms, so a merged PR with a failing CI is still merged.
check "25a: state beats CI (Merged with a failing CI is still merged)" \
  "$(pr_tag "Merged" "Changes Requested" "Fail" 9)" "merged"
check "25a: an empty comments field is read as zero, not an error" \
  "$(pr_tag "Open" "None" "Running" "")" "ok"

# --- 25b/c/d. Badge assembly ------------------------------------------------
# A real worktree with a .pr-status.json, rendered cold. The refresh locks are
# pre-touched for the reason mk_wt gives (no background refresher spawns), and
# the branch is pinned so the badge run can be addressed by position rather
# than by content.
PRWD="$TMPROOT/pr-wd"; mk_wt "$PRWD"
git -C "$PRWD" checkout -q -b b10-pr >/dev/null 2>&1
pr_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$PRWD\"},$ctx,\"transcript_path\":\"\"}"
# render()'s ANSI strip only removes CSI colour sequences; the badge numbers
# are wrapped in an OSC 8 hyperlink, whose opening sequence sits BETWEEN the
# tag and the "#123" it labels. Strip those too, so the badge run can be read
# as the plain text a terminal displays.
osc8_strip() { # text
  printf '%s' "$1" | sed -E "s/${ESC}\\]8;;[^${ESC}]*${ESC}\\\\//g"
}
# pr_line1(prs_json_array): write the PR-status file and return the BADGE RUN
# of a cold render -- line 1 with the path/branch prefix removed, ANSI and
# OSC-8 stripped. The prefix goes because a mktemp path carries arbitrary
# digits, and an absence check like "no PR number survives" would otherwise
# match the temp dir's own name. TTL 0 so each call rebuilds rather than
# serving the previous case's badge out of the bundle.
pr_line1() { # prs_array
  printf '{"prs":%s}' "$1" > "$PRWD/.local/.pr-status.json"
  osc8_strip "$(line_of "$(render_cached "$pr_json" "$TMPROOT/pr-cache" 0)" 1)" \
    | sed 's/^.*(b10-pr)//'
}
# Same, un-stripped, for the OSC-8 assertions.
pr_line1_raw() { # prs_array
  printf '{"prs":%s}' "$1" > "$PRWD/.local/.pr-status.json"
  printf '%s' "$pr_json" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/pr-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        bash "$CONTEXT" 2>/dev/null \
    | sed -n '1p'
}
pr_entry() { # number state reviews ci comments url
  printf '{"number":%s,"state":"%s","reviews":"%s","ci":"%s","comments":%s,"url":"%s"}' \
    "$1" "$2" "$3" "$4" "$5" "$6"
}

# 25b. The three ACTIONABLE tags render per-PR, as "<tag> #<number>".
b10_actionable="[$(pr_entry 101 Open "Changes Requested" Pass 0 https://x.test/101),\
$(pr_entry 102 Draft None Running 0 https://x.test/102),\
$(pr_entry 103 "Queue Failed" Approved Pass 0 https://x.test/103)]"
b10_act_line=$(pr_line1 "$b10_actionable")
check "25b: an actionable PR needing the user renders 'todo #101'" \
  "$(printf '%s' "$b10_act_line" | grep -qF 'todo #101' && echo yes || echo no)" "yes"
check "25b: a parked-but-fine PR renders 'wip #102'" \
  "$(printf '%s' "$b10_act_line" | grep -qF 'wip #102' && echo yes || echo no)" "yes"
check "25b: a queue-ejected PR renders 'ejected #103'" \
  "$(printf '%s' "$b10_act_line" | grep -qF 'ejected #103' && echo yes || echo no)" "yes"
# The whole run as an equality, which the three greps above cannot give: it
# pins the ORDER (payload order), the single spaces, and the absence of any
# fourth badge the assembly might leave behind.
check "25b: the badge run reads exactly ' todo #101 wip #102 ejected #103'" \
  "$b10_act_line" " todo #101 wip #102 ejected #103"
check "25b: the badges carry no emoji (the six glyphs they replaced are gone)" \
  "$(printf '%s' "$b10_act_line" | grep -qE '🔴|🟡|🚫|🟢|🚂|✅' && echo present || echo absent)" "absent"
# The hyperlink stays on the NUMBER, not on the tag: OSC 8 opens immediately
# before "#101" and closes immediately after it. Read on the RAW line, since
# pr_line1 strips exactly the sequences under test here.
b10_act_raw=$(pr_line1_raw "$b10_actionable")
check "25b: the OSC-8 hyperlink still wraps the number alone" \
  "$(printf '%s' "$b10_act_raw" \
     | grep -qaF "$(printf '\033]8;;https://x.test/101\033\\#101\033]8;;\033\\')" \
     && echo yes || echo no)" "yes"
check "25b: the tag itself is outside the hyperlink" \
  "$(printf '%s' "$b10_act_raw" | grep -qaF "$(printf 'todo \033]8;;')" && echo yes || echo no)" "yes"
# "Colours are unchanged -- the tag carries the same SGR the emoji did", and
# what the emoji carried was NOTHING: the glyph WAS the colour, so the badge
# run has never emitted an SGR sequence. Asserted by counting the line's colour
# sequences against the same worktree rendering no badges at all, which pins
# the clause without coupling to the shape of the path/branch escapes.
csi_count() { # text
  printf '%s' "$1" | grep -o "${ESC}\\[[0-9;]*m" | wc -l | tr -d ' '
}
b10_nobadge_raw=$(pr_line1_raw "[]")
check "25b: the actionable badges add no colour sequence of their own" \
  "$(csi_count "$b10_act_raw")" "$(csi_count "$b10_nobadge_raw")"
# Not a comparison of two zeroes: the path and branch are coloured, so the
# baseline is non-empty and a badge that gained an SGR would move the count.
check "25b: the badge-free baseline really carries colour sequences" \
  "$([ "$(csi_count "$b10_nobadge_raw")" -gt 0 ] && echo yes || echo no)" "yes"
# A PR with no url still badges; osc8_link falls through to the bare text, so
# the tag/number pair must survive un-hyperlinked rather than vanish.
check "25b: an actionable PR with no url still renders its badge, unlinked" \
  "$(pr_line1 "[$(pr_entry 104 Open "Changes Requested" Pass 0 '')]")" " todo #104"

# 25c. The three COLLAPSED tags render as counts, never per-PR. This is the
#      quiet failure the contract calls out by name: a `case` arm still
#      matching an emoji matches nothing classify_pr_tag now echoes, so every
#      PR falls through to the actionable branch and is badged individually.
#      The payload is deliberately ALL-collapsed, so that failure shows up as
#      six per-PR badges where there should be three counts -- and as a "#"
#      appearing on a line that should carry none.
b10_collapsed="[$(pr_entry 201 Open None Running 0 ''),\
$(pr_entry 202 Open None Running 0 ''),\
$(pr_entry 203 Open None Running 0 ''),\
$(pr_entry 204 "In Queue" Approved Pass 0 ''),\
$(pr_entry 205 "In Queue" Approved Pass 0 ''),\
$(pr_entry 206 Merged Approved Pass 0 '')]"
b10_coll_line=$(pr_line1 "$b10_collapsed")
check "25c: three green PRs collapse to '3 ok'" \
  "$(printf '%s' "$b10_coll_line" | grep -qF '3 ok' && echo yes || echo no)" "yes"
check "25c: two queued PRs collapse to '2 queued'" \
  "$(printf '%s' "$b10_coll_line" | grep -qF '2 queued' && echo yes || echo no)" "yes"
check "25c: one merged PR collapses to '1 merged'" \
  "$(printf '%s' "$b10_coll_line" | grep -qF '1 merged' && echo yes || echo no)" "yes"
check "25c: the collapsed run reads exactly ' 3 ok 2 queued 1 merged'" \
  "$b10_coll_line" " 3 ok 2 queued 1 merged"
check "25c: a case arm still matching an emoji would badge each PR: no '#' survives" \
  "$(printf '%s' "$b10_coll_line" | grep -qF '#' && echo present || echo absent)" "absent"
check "25c: nor does any individual PR number" \
  "$(printf '%s' "$b10_coll_line" | grep -qE '20[1-6]' && echo present || echo absent)" "absent"
check "25c: the collapsed counts add no colour sequence of their own either" \
  "$(csi_count "$(pr_line1_raw "$b10_collapsed")")" "$(csi_count "$b10_nobadge_raw")"

# 25d. CLOSED PRs are skipped entirely -- neither badged nor counted. Pinned
#      with a payload whose ONLY other PR is a green one, so a CLOSED PR
#      wrongly counted would read "2 ok" rather than "1 ok".
b10_closed="[$(pr_entry 301 CLOSED None None 0 ''),$(pr_entry 302 Open None Running 0 '')]"
b10_closed_line=$(pr_line1 "$b10_closed")
check "25d: a CLOSED PR is neither counted nor badged (the run is just ' 1 ok')" \
  "$b10_closed_line" " 1 ok"
check "25d: a CLOSED PR is not badged individually either" \
  "$(printf '%s' "$b10_closed_line" | grep -qF '#301' && echo present || echo absent)" "absent"

# 25e. Actionable and collapsed together: the actionable badges lead, the
#      counts follow. Both halves on one line is the shape a real worktree
#      actually renders, and the ordering is what the assembly fixes.
b10_mixed="[$(pr_entry 401 Open "Changes Requested" Pass 0 https://x.test/401),\
$(pr_entry 402 Open None Running 0 ''),\
$(pr_entry 403 Merged Approved Pass 0 '')]"
b10_mixed_line=$(pr_line1 "$b10_mixed")
check "25e: actionable badges lead and the collapsed counts follow" \
  "$b10_mixed_line" " todo #401 1 ok 1 merged"

# An empty prs array badges nothing at all -- not a stray "0 ok", and not a
# lone separator space either.
b10_none_line=$(pr_line1 "[]")
check "25e: an empty prs array renders no badge at all" "$b10_none_line" ""
# A count is emitted only when its bucket is non-empty: one merged PR and
# nothing else must not drag "0 ok 0 queued" along with it.
check "25e: empty buckets emit no zero counts" \
  "$(pr_line1 "[$(pr_entry 501 Merged Approved Pass 0 '')]")" " 1 merged"
rm -f "$PRWD/.local/.pr-status.json"

# --- 25f. The State segment loses its glyph, keeps its colour ---------------
# The glyph goes because the State's own name follows it and already carries
# state_color's urgency colour. Two consequences the contract names: the
# two-space lead-in survives (so removing the glyph must not leave a DOUBLE
# space before the name), and the colour is still state_color's.
STWD="$TMPROOT/state-wd"; mk_wt "$STWD"
git -C "$STWD" checkout -q -b b10-state >/dev/null 2>&1
st_json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$STWD\"},$ctx,\"transcript_path\":\"\"}"
# The State segment is the whole tail of line 1 here: no .pr-status.json, no
# .git-sync.json and no MODE in this worktree, so everything after the pinned
# branch belongs to it and can be asserted as an equality.
st_line1() { # state
  printf 'State: %s\n' "$1" > "$STWD/.local/TODO.md"
  line_of "$(render_cached "$st_json" "$TMPROOT/state-cache" 0)" 1 | sed 's/^.*(b10-state)//'
}
# state_color is not sourced into the harness (this file sources only
# platform/burn-*); call it in a subshell off the real library, so the
# expected colour stays DERIVED rather than transcribed from states.tsv.
st_color() { # state
  ( . "$SCRIPT_DIR/../lib/states.sh" 2>/dev/null; state_color "$1" )
}
st_line1_raw() { # state
  printf 'State: %s\n' "$1" > "$STWD/.local/TODO.md"
  printf '%s' "$st_json" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/state-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        bash "$CONTEXT" 2>/dev/null \
    | sed -n '1p'
}
b10_state_line=$(st_line1 "In Progress")
check "25f: the State name still renders" \
  "$(printf '%s' "$b10_state_line" | grep -qF 'In Progress' && echo yes || echo no)" "yes"
# Asserted as an equality on the whole segment, which is the only form that
# catches all three wrong outcomes at once: a surviving glyph, a doubled space
# where it used to be, and a lead-in trimmed to one space along with it.
check "25f: the segment is exactly two spaces then the name (no glyph, no double space)" \
  "$b10_state_line" "  In Progress"
check "25f: no States-manifest glyph survives on the line" \
  "$(printf '%s' "$b10_state_line" | grep -qE '⚪|⚡|🤖|🧪|🔬|📝|🐰|📋|👀|🚂|🙋|🛑|✅|•' && echo present || echo absent)" "absent"
# A multi-word State and one whose glyph column differs are both just names
# now; a per-State glyph lookup surviving anywhere would show up here.
check "25f: a needs-user State renders as its bare name too" \
  "$(st_line1 "Waiting For Decision")" "  Waiting For Decision"
check "25f: a State absent from the manifest renders its bare name, no fallback bullet" \
  "$(st_line1 "Not A Real State")" "  Not A Real State"
# No TODO.md at all still means no segment: dropping the glyph must not turn
# the segment unconditional.
rm -f "$STWD/.local/TODO.md"
check "25f: no TODO.md means no State segment at all" \
  "$(line_of "$(render_cached "$st_json" "$TMPROOT/state-cache" 0)" 1 | sed 's/^.*(b10-state)//')" ""
# The colour is unchanged and still state_color's, and it now opens on the
# NAME rather than after the glyph. Derived from state_color rather than
# transcribed, so the manifest stays its own suite's business. Covers all
# three urgency classes plus the dim 245 unknown-State fallback.
b10_state_color_case() { # state
  check "25f: State '$1' keeps state_color's sequence, now leading the name" \
    "$(printf '%s' "$(st_line1_raw "$1")" \
       | grep -qaF "$(printf '  \033[38;5;%sm%s' "$(st_color "$1")" "$1")" && echo yes || echo no)" "yes"
}
b10_state_color_case "In Progress"
b10_state_color_case "Blocked"
b10_state_color_case "Complete"
b10_state_color_case "Not A Real State"

# 25g. The `command -v` gate moved from state_emoji to state_color. A States
#      library defining state_color but NOT state_emoji must still render the
#      segment -- under the old gate the whole segment hung off state_emoji
#      being defined, so it would vanish. This is the one observable that
#      separates "the call was deleted" from "the call AND its gate were left
#      hanging off the wrong function".
B10GATE="$TMPROOT/b10-gate"; mkdir -p "$B10GATE/scripts" "$B10GATE/lib"
ln -s "$CONTEXT" "$B10GATE/scripts/context.sh"
ln -s "$SCRIPT_DIR/../lib/platform.sh" "$B10GATE/lib/platform.sh"
ln -s "$SCRIPT_DIR/../lib/burn-math.sh" "$B10GATE/lib/burn-math.sh"
ln -s "$SCRIPT_DIR/../lib/burn-tick.sh" "$B10GATE/lib/burn-tick.sh"
ln -s "$SCRIPT_DIR/../lib/burn-theme.sh" "$B10GATE/lib/burn-theme.sh"
# todo_field and state_color only. Bodies copied in miniature rather than
# sourced from the real lib, which is the point: state_emoji must be genuinely
# undefined here.
cat > "$B10GATE/lib/states.sh" <<'EOF'
#!/bin/bash
todo_field() {
    grep -m1 -E "^[*]{0,2}$2:" "$1" 2>/dev/null \
        | sed -E "s/^[*]{0,2}$2:[*]{0,2}[[:space:]]*//; s/[[:space:]]*\$//"
}
state_color() { printf '%s' "40"; }
EOF
printf 'State: In Progress\n' > "$STWD/.local/TODO.md"
b10_gate_line=$(printf '%s' "$st_json" \
  | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
      CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/b10-gate-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
      bash "$B10GATE/scripts/context.sh" 2>/dev/null \
  | sed -E "s/${ESC}\\[[0-9;]*m//g" | sed -n '1p')
check "25g: a States library with state_color but no state_emoji still renders the segment" \
  "$(printf '%s' "$b10_gate_line" | grep -qF 'In Progress' && echo yes || echo no)" "yes"
check "25g: and it renders with no glyph, exactly as the full library does" \
  "$(printf '%s' "$b10_gate_line" | sed 's/^.*(b10-state)//')" "  In Progress"

# The mirror image, which is what makes the pair a GATE test rather than a
# "the segment still renders" test: with state_color absent the segment must
# vanish, because the colour is the one library call the segment still makes.
# todo_field stays defined, so the State is readable and only the gate can be
# what suppresses it.
B10NOCOLOR="$TMPROOT/b10-nocolor"; mkdir -p "$B10NOCOLOR/scripts" "$B10NOCOLOR/lib"
ln -s "$CONTEXT" "$B10NOCOLOR/scripts/context.sh"
ln -s "$SCRIPT_DIR/../lib/platform.sh" "$B10NOCOLOR/lib/platform.sh"
ln -s "$SCRIPT_DIR/../lib/burn-math.sh" "$B10NOCOLOR/lib/burn-math.sh"
ln -s "$SCRIPT_DIR/../lib/burn-tick.sh" "$B10NOCOLOR/lib/burn-tick.sh"
ln -s "$SCRIPT_DIR/../lib/burn-theme.sh" "$B10NOCOLOR/lib/burn-theme.sh"
cat > "$B10NOCOLOR/lib/states.sh" <<'EOF'
#!/bin/bash
todo_field() {
    grep -m1 -E "^[*]{0,2}$2:" "$1" 2>/dev/null \
        | sed -E "s/^[*]{0,2}$2:[*]{0,2}[[:space:]]*//; s/[[:space:]]*\$//"
}
state_emoji() { printf '%s' "⚡"; }
EOF
b10_nocolor_line=$(printf '%s' "$st_json" \
  | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
      CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/b10-nocolor-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
      bash "$B10NOCOLOR/scripts/context.sh" 2>/dev/null \
  | sed -E "s/${ESC}\\[[0-9;]*m//g" | sed -n '1p')
check "25g: a States library with state_emoji but no state_color renders no segment" \
  "$(printf '%s' "$b10_nocolor_line" | sed 's/^.*(b10-state)//')" ""

# 25h. lib/states.tsv and lib/states.sh are NOT touched, in this plugin or any
#      other: state_emoji simply keeps no caller. It is a documented function
#      of a library VENDORED byte-identically into three plugins, so deleting
#      it here would be a coordinated cross-plugin edit -- exactly what B10 is
#      scoped to avoid. Sourced from the real lib (not the miniature above).
( . "$SCRIPT_DIR/../lib/states.sh" 2>/dev/null
  declare -f state_emoji >/dev/null 2>&1 && echo yes || echo no ) > "$TMPROOT/b10-emoji-fn"
check "25h: state_emoji still exists in the States library, caller or no caller" \
  "$(cat "$TMPROOT/b10-emoji-fn")" "yes"
check "25h: and still answers from the manifest's emoji column" \
  "$(. "$SCRIPT_DIR/../lib/states.sh" 2>/dev/null; state_emoji "In Progress")" "⚡"
check "25h: and keeps its unknown-State fallback" \
  "$(. "$SCRIPT_DIR/../lib/states.sh" 2>/dev/null; state_emoji "Not A Real State")" "•"
rm -f "$STWD/.local/TODO.md"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
