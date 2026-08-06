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
# Under B18 (plan 003-statusline-meter-colour) the fourteen payload fields are
# joined and split on \x1f instead of \x01, because bash 3.2 reserves \x01 as its
# quoting sentinel and its `read` cannot split on it at all -- so on macOS, whose
# /bin/bash is 3.2.57, every field lands in window_size and the statusline
# renders empty. Under bash 5 the two bytes behave identically, so section 27
# does NOT re-check the rendered output: it decouples the two ends of the round
# trip and asserts each byte separately. Nothing else in this file can see the
# change, which is why nothing else in it moves.
#
# Under B16 (plan 003-statusline-meter-colour) every value on the burnrate line
# carries colour, and the line's SHAPE does not move at all: same four groups,
# same dim separators, same omission rules, same figures. The ONLY observable
# difference is which SGR bytes appear, which is why almost every check in this
# file is untouched -- they read the ANSI-STRIPPED line and cannot see the
# change. The three that CAN see it are retargeted, by the same rule as before:
# section 9's ctx-colour cases (the meter's colour now answers "how full", not
# "how stale" -- #306), 24a's ctx-label case (same clause, new colour source)
# and 24b's paren case (the parens are still outside the METER's colour and are
# now inside the countdown's own). Section 26 carries what B16 adds outright.
#
# Covers: the burnrate line's four groups, their vanishing separators and their
# degradation (section 23); the removal of the per-turn "Turn:" row; the
# ~-for-$HOME path shortening; clean block termination (no trailing decorative
# "$" prompt, no dangling blank line); the context meter's occupancy-driven
# colour (section 9) and the idle-aware tri-state that still publishes beside
# it; the atomic .local/.ctx-status.json publish; the clam-mode segment sourced
# from .local/MODE (line-1 placement, teal colour, sanitization); the
# emoji-free burnrate line and its parenthesised 5-hour countdown (section 24);
# line 1's text PR tags and glyph-free State segment (section 25); the
# fully-coloured line B16 wires up, byte for byte (section 26); and the payload
# delimiter B18 moves off bash 3.2's quoting sentinel, asserted at each end of
# the round trip independently (section 27).
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
#   - Exactly 497 PASS lines and a zero exit. A changed count is a defect,
#     whichever direction it moves. (Was 86 when this contract was written;
#     the burnrate uplift raised it to 277, B09/B10's sections 24 and 25
#     raised it to 381, B16's section 26 raised it to 459, and B18's section 27
#     raised it again. The rule is the frozen count, not the number, so the
#     number moves when a deliberate change to the suite lands and stays frozen
#     in between.)
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
# code.
#
# Under B09 the label is INSIDE the colour sequence, exactly where the 🧠 it
# replaced was, so the escape is matched immediately followed by "ctx " and the
# percentage -- no longer optionally. The old form tolerated the glyph falling
# either side of the escape because the contract did not say; B09's amendment
# does say ("Each label sits INSIDE its meter's colour sequence exactly where
# the emoji did ... so the colour still spans label and figure together"), so
# the tolerance goes and the position is pinned.
#
# Under B16 the CODE this is called with changes source: it is burn_ctx_color's
# band for the occupancy, not burn_ctx_state's tier for the idle age. The helper
# itself is unchanged -- what it asserts is still "label and figure together
# inside one 256-colour sequence" -- and section 9's callers below carry the
# retargeting.
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

# 9. The ctx group's on-screen colour, carried by the burnrate line and — since
#    B16 — sourced from B03's burn_ctx_color, a function of HOW FULL the context
#    is. Budget is 300000 (the render/render_raw env). Bands are burn_ctx_color's
#    and are boundary-inclusive: >=60 red 196, >=40 orange 208, >=20 yellow 214,
#    else green 40.
#
#    These cases used to assert the idle-aware TRI-STATE (green / orange as a
#    big session cools / red once the prompt cache is nearly lapsed), sourced
#    from burn_ctx_state. That clause is not deleted and the call that computes
#    it is not removed: burn_ctx_state still runs on every render and its LEVEL
#    is still what .local/.ctx-status.json publishes. What B16 changes is that
#    the tier stopped deciding the COLOUR — which is #306, a meter that read
#    green at every occupancy because it was answering "how stale is this
#    session" while appearing to answer "how full is this context".
#
#    So each case below keeps its idle fixture and its occupancy, and now
#    asserts the colour the OCCUPANCY implies; the staleness tier it used to
#    assert is re-pinned, on the same fixtures, against the published `level`
#    in section 26c. The pair 9b/9d is what makes this more than a relabelling:
#    same occupancy, idle 0 vs ~50 minutes, and under B16 the same colour.
TR="$TMPROOT/tr.jsonl"; echo '{}' > "$TR"

# 9a. 145,230/300,000 = 48%, transcript fresh: the 40..59 band, orange. Was
#     green under the staleness tier (small session, idle irrelevant).
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 145230 "$TR")" 208 48 \
  "ctx orange (208) at 48% occupancy (the >=40 band)"

# 9b. 200,000 = 66%, transcript fresh so idle ~0: red. THE #306 SHAPE — a
#     nearly-full context on a session that is actively being used is exactly
#     the render that read green before B16, because burn_ctx_state escalates
#     only once a big session starts COOLING. Section 26b states the regression
#     in full; this is the case that used to say the wrong thing.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 200000 "$TR")" 196 66 \
  "ctx red (196) at 66% occupancy on a freshly-active session (#306)"

# 9c. 66%, ~33 min idle: red, on occupancy alone. Was orange.
set_mtime_ago "$TR" 2000
ctx_color_is "$(ctx_json "$WD" 200000 "$TR")" 196 66 \
  "ctx red (196) at 66% occupancy, cooling (idle>=1800) — same band as 9b"

# 9d. 66%, ~50 min idle: red. The one case whose colour B16 does NOT move, and
#     the reason 9b is the sharp one: it and 9b now agree.
set_mtime_ago "$TR" 3000
ctx_color_is "$(ctx_json "$WD" 200000 "$TR")" 196 66 \
  "ctx red (196) at 66% occupancy, cold (idle>=2700) — same band as 9b"

# 9e. Over budget (350,000 > 300,000 = 116%) with a FRESH transcript: red, via
#     the same >=60 tier as any lesser overrun. Nothing clamps.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 350000 "$TR")" 196 116 \
  "ctx red (196) on an overrun (116%), via the same >=60 tier"

# 9f. Empty transcript (""): the idle guard that stops a missing transcript
#     reading as infinitely cold is untouched and still feeds the published
#     level (26c) — the colour simply no longer depends on it, so a 66% session
#     is red here exactly as it is in 9b.
ctx_color_is "$(ctx_json "$WD" 200000 "")" 196 66 \
  "ctx red (196) at 66% with an empty transcript (colour does not read idle)"

# 9g. Missing transcript file (path set, file absent): same.
ctx_color_is "$(ctx_json "$WD" 200000 "$TMPROOT/does-not-exist.jsonl")" 196 66 \
  "ctx red (196) at 66% with a missing transcript file (colour does not read idle)"

# 9h. The ctx percentage is the integer floor of 100*used/budget and is NOT
#     clamped at 100 (350,000/300,000 = 116%) — the entire reason this plugin
#     computes occupancy itself instead of using the payload's saturating
#     .context_window.used_percentage.
out=$(render "$(ctx_json "$WD" 350000 "$TR")")
check "ctx percentage is the unclamped floor (116%) on overrun" \
  "$(burn_of "$out" | grep -qE 'ctx 116%' && echo yes || echo no)" "yes"

# 9i. Exact-budget boundary (300,000 tokens == 300,000 budget, exactly 100%)
#     with a FRESH transcript: red, well inside the >=60 band. Under
#     burn_ctx_state this case pinned that tier's `used >= budget` comparison;
#     that comparison still runs and section 26c pins it on the published level,
#     where it now lives.
touch "$TR"
ctx_color_is "$(ctx_json "$WD" 300000 "$TR")" 196 100 \
  "ctx red (196) at the exact-budget boundary (used == budget)"

# 9j. The mirror of 9b, and the other half of "the colour tracks occupancy, not
#     idle": a SMALL session (48%) with an OLD transcript (~50 min idle, the
#     same age as 9d) is orange, not red — staleness cannot push a half-empty
#     context into the top band any more than freshness can keep a full one out
#     of it.
set_mtime_ago "$TR" 3000
ctx_color_is "$(ctx_json "$WD" 145230 "$TR")" 208 48 \
  "ctx orange (208) at 48% occupancy despite an old/stale transcript"

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
  # The subshell is the point: each call must be a hermetic, cold parse that
  # leaks no env into the next, so these exports are meant to stay local.
  # shellcheck disable=SC2030
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
# The ctx meter's label sits inside its colour on exactly the same terms as the
# two plan meters above. B16 moves only WHERE that colour comes from — B03's
# burn_ctx_color rather than burn_ctx_state's COLOR field — so the expectation
# is derived from the helper the renderer must now call, and the clause (label
# and figure together inside one sequence) is unchanged.
check "24a: the ctx label is inside the ctx meter's colour (145,230/300,000 = 48%)" \
  "$(printf '%s' "$b24_5h_raw" | grep -qaF "$(burn_ctx_color 48)ctx 48%" && echo yes || echo no)" "yes"

# A decimal used% colours off its integer part -- the ${r7%%.*} trim that feeds
# burn_plan_color is untouched by B09 -- and, per amendment 2 below, PRINTS
# that same integer, so the figure and the colour can never disagree.
b24_float_raw=$(burn_render_raw "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 62.7 "" "" "")")
check "24a: a decimal used% colours and prints the same integer part" \
  "$(printf '%s' "$b24_float_raw" | grep -qaF "$(burn_plan_color 62)wk 62%" && echo yes || echo no)" "yes"

# --- 24b. The countdown's parens are OUTSIDE the METER's colour -------------
# burn_reset_str returns plain text, so "outside any colour sequence it
# returns" resolves to: the group's closing reset comes FIRST, then " (", then
# the countdown, then ")". B16 then dims the whole parenthesised clause with
# burn_countdown_color, PARENS INCLUDED, so what follows the meter's reset is
# the countdown's own opener and then "(" -- the parens are still outside the
# 5-hour meter's colour run, which is what this clause is about and what the
# second check below rules out the opposite of. Bracketed over [t0,t1] for
# burn_reset_str's minute roll, exactly as 23a is.
b24_t0=$(date +%s)
b24_raw=$(burn_render_raw "$b5_full")
b24_t1=$(date +%s)
b24_paren_ok=no
b24_inside_ok=no
for (( _n = b24_t0; _n <= b24_t1; _n++ )); do
  _cd=$(burn_reset_str "$B5_R5_RESET" "$_n")
  printf '%s' "$b24_raw" | grep -qaF "$(printf '\033[0m') $(burn_countdown_color)($_cd)" && b24_paren_ok=yes
  # The failure this rules out is the mirror image: parens emitted INSIDE the
  # meter's colour run, which reads "<plan colour>5h 1% (4h54m)<reset>".
  printf '%s' "$b24_raw" | grep -qaF "$(burn_plan_color 1)5h 1% ($_cd)" && b24_inside_ok=yes
done
check "24b: the parens sit outside the meter's colour (its reset, then the dimmed '(countdown)')" \
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
  # The subshell is the point: each call must be a hermetic, cold parse that
  # leaks no env into the next, so these exports are meant to stay local and
  # never be read back by a later call.
  # shellcheck disable=SC2030,SC2031
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
  # The subshell is the point: each call must be a hermetic, cold parse that
  # leaks no env into the next, so these exports are meant to stay local and
  # never be read back by a later call.
  # shellcheck disable=SC2030,SC2031
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
# The \\ below is printf's escape for one literal backslash -- the ST
# terminator of an OSC-8 hyperlink under test -- not an unescaped quote.
# shellcheck disable=SC1003
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

# === 26. B16 burn-line-colour-wiring ========================================
# Contract: the B16 amendment to sl_render_burn_line's docblock, its four
# numbered bullets and the "last hand-typed escape" consequence beneath them,
# together with the B16-specific entries the Edge-cases list gained.
#
# B16 is a COMPOSITION block: the four colours it wires -- burn_trend_color,
# burn_ctx_color, burn_diff_color and burn_countdown_color -- are B03's, each
# with its own accepted suite in lib/burn-theme.test.sh. Nothing here re-tests a
# threshold. What is tested here is what only a rendered line can show: which
# helper the renderer ASKS for each value, where the sequence it returns opens
# and closes, and that the line's shape is otherwise untouched.
#
# That distinction is the whole reason #306's regression test lives in this
# section and nowhere else. burn_ctx_color maps occupancy to colour correctly in
# burn-theme.sh and always has; the defect was that the renderer asked
# burn_ctx_state -- the session-STALENESS tri-state -- for the ctx meter's
# colour, which is why the meter read green at every occupancy. No assertion
# inside burn-theme.sh can see that. 26b is the one that can.
#
# Expected values are DERIVED by calling B03's helpers rather than written out
# as escape codes, per this file's standing rule: the bands are burn-theme's
# clause, and what is under test is that context.sh routes each value through
# the right one of them.

B16_RST=$(printf '\033[0m')
B16_SEP=$(printf '\033[2m│\033[0m')

# b16_join(group...): assemble groups exactly as _sl_burn_group does -- an empty
# group contributes nothing at all, and the dim separator goes only BETWEEN
# present groups, with one space either side. Expected lines are built with this
# rather than written out, so a case states which GROUPS it expects and the join
# rule is applied once, in one place, the way the renderer applies it.
b16_join() { # group...
  local acc="" g
  for g in "$@"; do
    [ -z "$g" ] && continue
    [ -n "$acc" ] && acc="$acc $B16_SEP "
    acc="$acc$g"
  done
  printf '%s' "$acc"
}

# The RAW burnrate line (line 2, escapes intact) of a payload.
b16_raw_line() { # json [env...]
  line_of "$(burn_render_raw "$@")" 2
}

# b16_in_source(json, bash_code): source context.sh against a payload -- safe,
# for the reason section 22's parse_vars gives -- and run BASH_CODE in the same
# shell, so an assertion can read a variable the ctx computation leaves behind
# or a function body bash itself parsed. Run in a FRESH bash under `env` rather
# than in a subshell of this one, so nothing this harness has defined can be
# mistaken for something context.sh left, and the hermetic env is passed the
# same way every other render helper here passes it.
b16_in_source() { # json bash_code
  printf '%s' "$1" \
    | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/b16-src-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        bash -c '. "$1" >/dev/null 2>&1; eval "$2"' _ "$CONTEXT" "$2"
}

# --- 26a. The whole line, byte for byte -------------------------------------
# The strongest available statement of "the shape does not move and only SGR
# changes": an EQUALITY over every byte of the rendered line, against an
# expectation assembled from B03's own helpers. A grep for one colour code
# cannot tell a correctly-coloured line from one that also gained a stray reset,
# lost a space, coloured the separator, or wrapped the wrong span; this can.
#
# The fixture is deliberately free of every quantity that moves with the clock:
# no model name (so no rainbow, whose palette offset advances one frame per
# render) and no reset timestamp on either rate limit (so no pacing figures and
# no countdown). What is left is exactly reproducible. The two groups that do
# move are pinned byte for byte too, in 26d and 26f, bracketed over the render
# interval the way section 23 brackets them.
b16_static_json=$(burn_json "$B5_WD" 145230 "" "max" 1 "" 62 "" 503 16)
b16_static_raw=$(b16_raw_line "$b16_static_json")
b16_static_expected=$(b16_join \
  "$(burn_effort_color max)max$B16_RST" \
  "$(burn_plan_color 62)wk 62%$B16_RST" \
  "$(burn_ctx_color 48)ctx 48%$B16_RST $(burn_diff_color add)+503$B16_RST/$(burn_diff_color del)-16$B16_RST" \
  "$(burn_plan_color 1)5h 1%$B16_RST")
check "26a: the whole four-group line is byte-identical to the assembled expectation, SGR included" \
  "$b16_static_raw" "$b16_static_expected"

# The other half of "only SGR changes": the same render with the escapes taken
# out is the line this plugin already shipped, to the byte. Written as a literal
# rather than derived, because the point is that nothing about the TEXT is
# computed from anything B16 touches.
check "26a: and its ANSI-stripped text is exactly the line that shipped before B16" \
  "$(burn_of "$(burn_render "$b16_static_json")")" "max │ wk 62% │ ctx 48% +503/-16 │ 5h 1%"

# Without this, the equality above would pass just as happily against a renderer
# that still sourced the ctx colour from the staleness tier -- if the two
# happened to agree on this payload. At 48% occupancy and zero idle they do not.
check "26a: the occupancy band and the staleness tier genuinely disagree here, so that equality discriminates" \
  "$([ "$(burn_ctx_color 48)" \
      != "$(printf '\033[38;5;%sm' "$(burn_ctx_state 145230 300000 0 | awk '{print $2}')")" ] \
     && echo yes || echo no)" "yes"

# A session that has edited nothing: the +N/-M pair does not render, so
# burn_diff_color is never called and group 3 is `ctx` alone. Byte-exact, which
# is what makes "never called" assertable -- at a green occupancy
# burn_diff_color add returns the very sequence the ctx meter itself would, so
# an absence check on its bytes would be meaningless.
b16_nocounts_json=$(burn_json "$B5_WD" 145230 "" "max" 1 "" 62 "" 0 0)
check "26a: a session that has edited nothing renders group 3 as ctx alone, byte for byte" \
  "$(b16_raw_line "$b16_nocounts_json")" \
  "$(b16_join "$(burn_effort_color max)max$B16_RST" "$(burn_plan_color 62)wk 62%$B16_RST" \
      "$(burn_ctx_color 48)ctx 48%$B16_RST" "$(burn_plan_color 1)5h 1%$B16_RST")"

# --- 26b. THE #306 REGRESSION TEST ------------------------------------------
# The ctx meter warns as the context fills. This is the single case the plan
# cannot ship without: the defect is not in the mapping (burn-theme.sh has
# mapped occupancy to colour correctly since B13, with its own 93 assertions)
# but in WHICH question the renderer asks, and that is observable only through a
# rendered line.
B16TR="$TMPROOT/b16-tr.jsonl"; echo '{}' > "$B16TR"

# i. The regression itself. 285,000/300,000 = 95% of the compaction window on a
#    session whose transcript was appended to a moment ago -- the exact shape
#    that renders GREEN in the shipped plugin, because burn_ctx_state escalates
#    a big session only once it has been idle for half an hour. A user two
#    thousand tokens from compaction sees the same colour as one who has just
#    started.
touch "$B16TR"
ctx_color_is "$(ctx_json "$WD" 285000 "$B16TR")" 196 95 \
  "26b: #306 REGRESSION -- a nearly-full context on a freshly-active session renders RED"

# ii. The other end of the scale, so the case above cannot pass by the meter
#     having simply been painted red unconditionally.
ctx_color_is "$(ctx_json "$WD" 15000 "$B16TR")" 40 5 \
  "26b: a nearly-empty context (5%) renders GREEN"

# iii. The colour tracks OCCUPANCY, not idle time. Stated as two sweeps that
#      cross: idle varied across its whole meaningful range at one occupancy
#      answers the SAME, and occupancy varied at one idle answers DIFFERENTLY.
#      Either sweep alone is satisfiable by an implementation that still reads
#      the wrong input.
b16_idle_case() { # idle_seconds label
  if [ "$1" = "0" ]; then touch "$B16TR"; else set_mtime_ago "$B16TR" "$1"; fi
  ctx_color_is "$(ctx_json "$WD" 285000 "$B16TR")" 196 95 \
    "26b: 95% occupancy is red $2 -- idle does not move the meter"
}
b16_idle_case 0    "on a freshly-active session"
b16_idle_case 600  "after ten minutes idle"
b16_idle_case 2000 "after the tier's cooling threshold (~33 min)"
b16_idle_case 3000 "after the tier's cold threshold (~50 min)"

touch "$B16TR"
b16_occ_case() { # tokens pct color label
  ctx_color_is "$(ctx_json "$WD" "$1" "$B16TR")" "$3" "$2" \
    "26b: $2% occupancy on an equally-fresh session renders $4"
}
b16_occ_case 57000  19  40  "green (below the 20 band)"
b16_occ_case 60000  20  214 "yellow (the 20 boundary, inclusive)"
b16_occ_case 117000 39  214 "yellow (below the 40 band)"
b16_occ_case 120000 40  208 "orange (the 40 boundary, inclusive)"
b16_occ_case 177000 59  208 "orange (below the 60 band)"
b16_occ_case 180000 60  196 "red (the 60 boundary, inclusive)"

# iv. The defect named directly. burn_ctx_state's answer for the regression
#     fixture is still the green tier -- correctly, since it answers a different
#     question -- and the rendered meter must no longer carry it. The pair is
#     what distinguishes "the colour source moved" from "burn_ctx_state's
#     thresholds were quietly changed to fix the symptom", which would break the
#     published level for every consumer of .ctx-status.json.
touch "$B16TR"
check "26b: burn_ctx_state still answers the green tier for that fixture (its own clause is unchanged)" \
  "$(burn_ctx_state 285000 300000 0 | awk '{print $2}')" "40"
check "26b: and the rendered meter no longer carries that tier's sequence" \
  "$(render_raw "$(ctx_json "$WD" 285000 "$B16TR")" \
     | grep -qaF "$(printf '\033[38;5;40m')ctx 95%" && echo present || echo absent)" "absent"

# --- 26c. burn_ctx_state still runs, and its LEVEL still publishes ----------
# The call is not deleted with its colour: the tri-state is what
# .local/.ctx-status.json's `level` field carries, it has a consumer outside
# this plugin, and B16's whole framing is that the published tier and the
# on-screen colour now answer different questions ON PURPOSE -- "how stale" and
# "how full". Each case asserts both answers on ONE render, so the two cannot be
# collapsed back into one.
B16GWD="$TMPROOT/b16-gitwd"; mk_wt "$B16GWD"
B16GTR="$B16GWD/transcript.jsonl"; echo '{}' > "$B16GTR"
B16CJ="$B16GWD/.local/.ctx-status.json"

b16_publish_case() { # label tokens idle pct level
  local raw
  if [ "$3" = "0" ]; then touch "$B16GTR"; else set_mtime_ago "$B16GTR" "$3"; fi
  raw=$(render_raw "$(ctx_json "$B16GWD" "$2" "$B16GTR")")
  check "26c: $1 -> .ctx-status.json still publishes level '$5'" \
    "$(jq -r '.level' "$B16CJ" 2>/dev/null)" "$5"
  check "26c: $1 -> and the meter on screen is burn_ctx_color's band for $4%" \
    "$(printf '%s' "$raw" | grep -qaF "$(burn_ctx_color "$4")ctx $4%" && echo yes || echo no)" "yes"
}
b16_publish_case "66% occupancy, freshly active"        200000 0    66 "ok"
b16_publish_case "66% occupancy, cooling (~33 min)"     200000 2000 66 "warn"
b16_publish_case "66% occupancy, cold (~50 min)"        200000 3000 66 "cold"
b16_publish_case "48% occupancy, cold (~50 min)"        145230 3000 48 "ok"

# The last fixture above is the divergence stated on its own: a session the
# staleness tier calls fine, showing an orange meter because it is nearly half
# full. If the two ever agreed everywhere, the split would be pointless and
# every case above would pass vacuously.
check "26c: on that fixture the published tier and the on-screen colour genuinely differ" \
  "$([ "$(burn_ctx_color 48)" \
      != "$(printf '\033[38;5;%sm' "$(burn_ctx_state 145230 300000 3000 | awk '{print $2}')")" ] \
     && echo yes || echo no)" "yes"

# The ctx computation's own variables, which no rendered byte can show. Two
# clauses meet here:
#   - `level` is still SET, so burn_ctx_state is still called. Every colour
#     assertion above would pass just as well with the call deleted outright,
#     and .ctx-status.json would then ship the "ok" default forever.
#   - `ctx_color` is UNSET. The contract deletes the `ctx_color=40` default and
#     turns `read -r level ctx_color` into `read -r level _`, explicitly
#     "rather than left unread" -- and a variable left set behind an unused
#     read is the one form of this edit no render can distinguish.
set_mtime_ago "$B16GTR" 3000
check "26c: sourcing a render leaves burn_ctx_state's level set (cold here) and no ctx_color at all" \
  "$(b16_in_source "$(ctx_json "$B16GWD" 200000 "$B16GTR")" \
      'printf "level=%s ctx_color=%s\n" "${level-<unset>}" "${ctx_color+<set>}"')" \
  "level=cold ctx_color="
touch "$B16GTR"
check "26c: and the same on a freshly-active session (level ok, still no ctx_color)" \
  "$(b16_in_source "$(ctx_json "$B16GWD" 200000 "$B16GTR")" \
      'printf "level=%s ctx_color=%s\n" "${level-<unset>}" "${ctx_color+<set>}"')" \
  "level=ok ctx_color="

# --- 26d. Group 2's trend: B14's colour, the renderer's arrow ---------------
# The arrow STAYS. B14's +/-3 dead band is expressed as the green tier and the
# upstream's on-track glyph is deliberately not adopted (26g pins its absence),
# so `▲`/`▼` are still chosen here, by the same sign test, and only the colour
# around them is new.
#
# The fixtures are SOLVED, not guessed. burn_metrics' trend is `used% minus the
# ideal line's value at NOW`, and that line's value is
# 100 * awake(week_start, now) / awake(week_start, reset) -- computable from
# B01's own shared primitive. A used% set to that value plus TARGET plus a
# quarter point therefore produces exactly TARGET, with a quarter-point margin
# on both sides; the line moves about 0.0002 points per second, so the fixture
# holds for some twenty minutes and cannot flake on the seconds between this
# arithmetic and the render.
#
# Solving also reaches the one magnitude an INTEGER used% cannot: a trend of
# exactly 0, which the contract names as an edge case (`▲0`, green, inside the
# dead band). The ideal line sits at a fractional value, so the integers either
# side of it round to -0 and +1 rather than to 0.
b16_ws=$(( B5_R7_RESET - 604800 ))
b16_aw=$(burn_awake_seconds "$b16_ws" "$B5_R7_RESET" "$b5_ds2" 21600)
b16_ae=$(burn_awake_seconds "$b16_ws" "$B5_NOW" "$b5_ds2" 21600)
check "26d: the awake-seconds solve resolved (the trend fixtures are computable)" \
  "$([ "${b16_aw:-0}" -gt 0 ] && [ "${b16_ae:-0}" -gt 0 ] && echo yes || echo no)" "yes"

# b16_trend_used(target): the used% that puts the trend at exactly TARGET.
b16_trend_used() { # target
  awk -v ae="$b16_ae" -v aw="$b16_aw" -v t="$1" 'BEGIN{printf "%.4f", ae/aw*100 + t + 0.25}'
}

# b16_trend_case(label, target): render a weekly-only line -- no context tokens,
# no five-hour limit -- so the trend ENDS the line and its closing reset is the
# line's last byte. Asserted as a SUFFIX equality rather than a substring match,
# which is what makes "wrapped in burn_trend_color ... $rst" a real statement:
# an unclosed sequence, a second reset, or a colour that also swallowed the
# following separator all fail it.
b16_trend_case() { # label target
  local used raw frag arrow got
  used=$(b16_trend_used "$2")
  got=$(burn_metrics "$used" 0 "$B5_NOW" "$B5_R7_RESET" "$b5_ds2" 21600 | awk '{print $3}')
  check "26d: $1 -- the fixture really produces a trend of $2" "$got" "$2"
  case "$2" in -*) arrow='▼' ;; *) arrow='▲' ;; esac
  raw=$(b16_raw_line "$(burn_json "$B5_WD" "" "" "max" "" "" "$used" "$B5_R7_RESET" "" "")")
  frag="$(burn_trend_color "$2")$arrow$2$B16_RST"
  check "26d: $1 -- the line ends on '$arrow$2' wrapped in burn_trend_color's sequence" \
    "$([ "$raw" != "${raw%"$frag"}" ] && echo yes || echo no)" "yes"
}
b16_trend_case "a trend of exactly 0 (the dead band, and the arrow is still up)" 0
b16_trend_case "a trend of +5 (just past the dead band)"                         5
b16_trend_case "a trend of +10"                                                  10
b16_trend_case "a trend of +20 (far ahead of the even-burn line)"                20
b16_trend_case "a trend of -10 (behind the line, so the tier that says 'nothing to act on')" -10

# Five cases are worth running only if the five tiers are five different
# sequences; otherwise a renderer that always emitted green would pass most of
# them.
check "26d: those five trends really do select five distinct sequences" \
  "$(printf '%s\n' "$(burn_trend_color 0)" "$(burn_trend_color 5)" "$(burn_trend_color 10)" \
      "$(burn_trend_color 20)" "$(burn_trend_color -10)" | sort -u | grep -c '' | tr -d ' ')" "5"

# The whole weekly group, byte for byte: four figures, four colours, four
# resets, and the three spaces between them. %t is pinned exactly (it does not
# move with the render's clock -- see burn_expect_today); pace is bracketed over
# the interval the render's own clock provably fell inside, exactly as 23i
# brackets it. This is also where the trend's colour is pinned as part of a
# whole group rather than as a suffix, so a colour that leaked backwards over
# `%/d` fails here even though it would satisfy the suffix check above.
b16_g2_used=$(b16_trend_used 20)
b16_g2_today=$(burn_expect_today "$b16_g2_used" "$B5_R7_RESET" 2 6)
b16_g2_t0=$(date +%s)
b16_g2_raw=$(b16_raw_line "$(burn_json "$B5_WD" "" "" "max" "" "" "$b16_g2_used" "$B5_R7_RESET" "" "")")
b16_g2_t1=$(date +%s)
b16_g2_ok=no
for _p in $(burn_metric_candidates 2 "$b16_g2_used" "$B5_R7_RESET" "$b5_ds2" 21600 "$b16_g2_t0" "$b16_g2_t1"); do
  [ "$b16_g2_raw" = "$(b16_join "$(burn_effort_color max)max$B16_RST" \
      "$(burn_plan_color "${b16_g2_used%%.*}")wk ${b16_g2_used%%.*}%$B16_RST\
 $(burn_today_color "$b16_g2_today")${b16_g2_today}%t$B16_RST\
 $(burn_pace_color "$_p")${_p}%/d$B16_RST\
 $(burn_trend_color 20)▲20$B16_RST")" ] && b16_g2_ok=yes
done
check "26d: the whole weekly group renders byte for byte -- four figures, four colours, four resets" \
  "$b16_g2_ok" "yes"
# The same line with the escapes taken out is the weekly group this plugin
# already shipped, decimal used% truncated to its integer part and all.
check "26d: and its stripped text still carries all four figures in order, the used% truncated" \
  "$(burn_of "$(burn_render "$(burn_json "$B5_WD" "" "" "max" "" "" "$b16_g2_used" "$B5_R7_RESET" "" "")")" \
     | grep -qE "^max │ wk ${b16_g2_used%%.*}% -?[0-9]+%t [0-9.]+%/d ▲20$" && echo yes || echo no)" "yes"

# --- 26e. Group 3's counts: two colours, two resets, a bare slash -----------
# 26a already pins the segment byte for byte. Separated out here is the clause a
# byte-equality could satisfy for the wrong reason if the two halves shared one
# sequence: each half is closed with its OWN reset, so neither can bleed into
# the other, and the `/` between them carries no colour at all.
check "26e: the added count closes before the slash, and the slash is uncoloured" \
  "$(printf '%s' "$b16_static_raw" \
     | grep -qaF "$(burn_diff_color add)+503$B16_RST/$(burn_diff_color del)" && echo yes || echo no)" "yes"
check "26e: the removed count closes with its own reset" \
  "$(printf '%s' "$b16_static_raw" \
     | grep -qaF "$(burn_diff_color del)-16$B16_RST" && echo yes || echo no)" "yes"
check "26e: add and del are different colours, so neither check above is vacuous" \
  "$([ "$(burn_diff_color add)" != "$(burn_diff_color del)" ] && echo yes || echo no)" "yes"
# The pair is gated on at least one count being above zero, never on each half
# separately: a half at zero still renders, and still carries its colour.
check "26e: '+5/-0' -- the zero half is rendered and coloured like the other" \
  "$(b16_raw_line "$(burn_json "$B5_WD" 145230 "" "" "" "" "" "" 5 0)")" \
  "$(b16_join "$(burn_ctx_color 48)ctx 48%$B16_RST $(burn_diff_color add)+5$B16_RST/$(burn_diff_color del)-0$B16_RST")"
check "26e: '+0/-7' -- likewise in the other direction" \
  "$(b16_raw_line "$(burn_json "$B5_WD" 145230 "" "" "" "" "" "" 0 7)")" \
  "$(b16_join "$(burn_ctx_color 48)ctx 48%$B16_RST $(burn_diff_color add)+0$B16_RST/$(burn_diff_color del)-7$B16_RST")"

# --- 26f. Group 4's countdown dims WITH its parens --------------------------
# `($countdown)` entire, not `(` + dim + `)`: the whole subordinate clause dims
# together so the eye reaches `5h 20%` first. Bracketed over [t0,t1] for
# burn_reset_str's minute roll, as 23a and 24b are.
b16_cd_t0=$(date +%s)
b16_cd_raw=$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" 20 "$B5_R5_RESET" "" "" "" "")")
b16_cd_t1=$(date +%s)
b16_cd_ok=no
b16_cd_openparen=no
for (( _n = b16_cd_t0; _n <= b16_cd_t1; _n++ )); do
  _cd=$(burn_reset_str "$B5_R5_RESET" "$_n")
  [ "$b16_cd_raw" = "$(burn_plan_color 20)5h 20%$B16_RST $(burn_countdown_color)($_cd)$B16_RST" ] \
    && b16_cd_ok=yes
  printf '%s' "$b16_cd_raw" | grep -qaF "($(burn_countdown_color)$_cd" && b16_cd_openparen=yes
done
check "26f: the five-hour group renders byte for byte, the countdown dimmed WITH its parens" \
  "$b16_cd_ok" "yes"
check "26f: the opening paren is not left outside the dim sequence" "$b16_cd_openparen" "no"
# A missing reset drops the countdown and its parens together -- and now the
# colour that wrapped them too, since an opener left behind by a segment that
# did not render is exactly the leak the closing-reset convention exists to
# stop. Byte-exact on the whole line, so a leftover dim opener shows up.
check "26f: five_hour without its reset renders the meter alone, no leftover dim opener" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" 20 "" "" "" "" "")")" \
  "$(burn_plan_color 20)5h 20%$B16_RST"
# An UNPARSEABLE reset (a JSON string where an epoch belongs) takes the same
# path: burn_reset_str returns non-zero, so countdown, parens and colour drop
# together.
check "26f: an unparseable reset drops the countdown, its parens and its colour alike" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" 20 '"not-an-epoch"' "" "" "" "")")" \
  "$(burn_plan_color 20)5h 20%$B16_RST"

# --- 26g. No hand-typed 38;5; survives in sl_render_burn_line ---------------
# The contract states this outright as the consequence of the four wirings: with
# group 3's colour coming from burn_ctx_color, the last `${esc}[38;5;Nm` typed
# into this function goes, and any that reappears is a colour decision made in
# the renderer instead of in burn-theme.sh. It is the cheapest check in this
# section and the one that would catch a future regression soonest.
#
# Scanned against BASH'S OWN PARSE of the function rather than the file's text,
# so the docblock -- which quotes the sequence, legitimately, while explaining
# that it is gone -- is out of scope by construction rather than by pattern.
# The two escape shapes that remain, the dim separator and the reset, are not
# false positives: neither spells 38;5;.
b16_fn_body=$(b16_in_source "$b16_static_json" 'declare -f sl_render_burn_line')
check "26g: the scan really sees the function body (not vacuous)" \
  "$([ -n "$b16_fn_body" ] && echo yes || echo no)" "yes"
check "26g: no 38;5; sequence is typed anywhere inside sl_render_burn_line" \
  "$(printf '%s\n' "$b16_fn_body" | grep -c '38;5;' | tr -d ' ')" "0"
check "26g: the same pattern does fire elsewhere in context.sh, so that check is falsifiable" \
  "$([ "$(grep -c '38;5;' "$CONTEXT")" -gt 0 ] && echo yes || echo no)" "yes"
# B14 expresses the dead band as the green tier precisely so the upstream's
# on-track glyph need not be adopted; no new codepoint appears on this line.
check "26g: the upstream's on-track check mark appears nowhere in the function" \
  "$(printf '%s\n' "$b16_fn_body" | grep -qF '✓' && echo present || echo absent)" "absent"
check "26g: nor on a rendered line that carries a trend inside the dead band" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "max" "" "" "$(b16_trend_used 0)" "$B5_R7_RESET" "" "")" \
     | grep -qF '✓' && echo present || echo absent)" "absent"

# --- 26h. Degradation: lib/burn-theme.sh absent from the install ------------
# 23m-iii covers an install missing ALL THREE burnrate libraries, which leaves
# the line with no derived figures at all. B16's degradation clause is narrower
# and sharper: burn-math and burn-tick present, burn-theme absent, so every
# FIGURE still computes and only colour is gone. That is the install whose line
# must come out as today's uncoloured render -- no partial sequence, no colour
# picked locally as a fallback, nothing broken.
#
# It is also the case that pins the DELETED `ctx_color=40` default from the
# other side. Today that default is what makes the ctx meter the one group still
# emitting a 256-colour sequence on an install with no theme at all; once the
# default is gone and the call is guarded, not one survives.
B16NOTHEME="$TMPROOT/b16-notheme"; mkdir -p "$B16NOTHEME/scripts" "$B16NOTHEME/lib"
ln -s "$CONTEXT" "$B16NOTHEME/scripts/context.sh"
for _f in platform.sh states.sh states.tsv burn-math.sh burn-tick.sh; do
  ln -s "$SCRIPT_DIR/../lib/$_f" "$B16NOTHEME/lib/$_f"
done
unset _f

b16_deg_render() { # json outfile errfile cachedir [cwd_env...]
  printf '%s' "$1" \
    | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$4" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        bash "$B16NOTHEME/scripts/context.sh" > "$2" 2>"$3"
}
b16_strip() { printf '%s' "$1" | sed -E "s/${ESC}\\[[0-9;]*m//g"; }

b16_deg_out="$TMPROOT/b16-deg.out"; b16_deg_err="$TMPROOT/b16-deg.err"
b16_deg_render "$b16_static_json" "$b16_deg_out" "$b16_deg_err" "$TMPROOT/b16-deg-cache"
b16_deg_ec=$?
b16_deg_raw=$(line_of "$(<"$b16_deg_out")" 2)
check "26h: burn-theme absent -> the render still exits 0" "$b16_deg_ec" "0"
check "26h: burn-theme absent -> nothing is written to stderr" \
  "$(wc -c < "$b16_deg_err" | tr -d ' ')" "0"
check "26h: burn-theme absent -> no diagnostic text reaches stdout" \
  "$(grep -qiE 'command not found|no such file|syntax error' "$b16_deg_out" && echo present || echo absent)" "absent"
check "26h: burn-theme absent -> not one 256-colour sequence survives on the line" \
  "$(printf '%s' "$b16_deg_raw" | grep -c '38;5;' | tr -d ' ')" "0"
check "26h: burn-theme absent -> the line's TEXT is exactly the coloured render's" \
  "$(b16_strip "$b16_deg_raw")" "max │ wk 62% │ ctx 48% +503/-16 │ 5h 1%"
# "No partial sequence": every ESC on the line opens a complete SGR. Strip the
# complete ones and no ESC byte may be left standing -- a truncated `\033[38;5;`
# with no terminator would survive the strip and be caught here.
check "26h: burn-theme absent -> every escape on the line is a complete SGR sequence" \
  "$(b16_strip "$b16_deg_raw" | grep -c "$ESC" | tr -d ' ')" "0"
check "26h: burn-theme absent -> the line stays well-formed" \
  "$(burn_wellformed "$(b16_strip "$b16_deg_raw")")" "yes"
check "26h: burn-theme absent -> the line carries no emoji" \
  "$(burn_no_emoji "$(b16_strip "$b16_deg_raw")")" "yes"

# The same install with a payload carrying both resets, so the two figures the
# static fixture omits are in play. The trend is B01's, so it still renders and
# must render UNCOLOURED. The countdown is not: burn_reset_str lives in the
# missing file too, so it drops -- and the clause that matters is that it takes
# its parens with it exactly as an absent reset does, rather than leaving the
# empty `()` the contract forbids or a dim opener with nothing behind it.
b16_deg2_out="$TMPROOT/b16-deg2.out"
b16_deg_render "$(burn_json "$B5_WD" 145230 "" "max" 1 "$B5_R5_RESET" 62 "$B5_R7_RESET" 503 16)" \
  "$b16_deg2_out" "$b16_deg_err" "$TMPROOT/b16-deg2-cache"
b16_deg2_raw=$(line_of "$(<"$b16_deg2_out")" 2)
b16_deg2_line=$(b16_strip "$b16_deg2_raw")
check "26h: burn-theme absent -> the trend arrow and magnitude still render" \
  "$(printf '%s' "$b16_deg2_line" | grep -qE '(▲|▼)-?[0-9]+' && echo yes || echo no)" "yes"
check "26h: burn-theme absent -> the countdown drops with its parens, leaving no empty pair" \
  "$(printf '%s' "$b16_deg2_line" | grep -qE '[()]' && echo present || echo absent)" "absent"
check "26h: burn-theme absent -> and the five-hour meter itself still renders" \
  "$(printf '%s' "$b16_deg2_line" | grep -qE '5h 1%' && echo yes || echo no)" "yes"
check "26h: burn-theme absent -> still not one 256-colour sequence on that line" \
  "$(printf '%s' "$b16_deg2_raw" | grep -c '38;5;' | tr -d ' ')" "0"
check "26h: burn-theme absent -> that line stays well-formed too" \
  "$(burn_wellformed "$b16_deg2_line")" "yes"

# burn_ctx_state lives in the missing file, so `level` falls back to the safe
# tier -- and the publish must still happen. The .ctx-status.json consumer is
# not allowed to lose its file because a PRESENTATION library is absent, which
# is the same reason the thresholds are not restated in context.sh.
B16DEGWD="$TMPROOT/b16-deg-wd"; mk_wt "$B16DEGWD"
b16_deg_render "$(ctx_json "$B16DEGWD" 200000 "")" "$TMPROOT/b16-deg3.out" "$b16_deg_err" \
  "$TMPROOT/b16-deg3-cache"
check "26h: burn-theme absent -> .ctx-status.json is still published" \
  "$([ -f "$B16DEGWD/.local/.ctx-status.json" ] && echo yes || echo no)" "yes"
check "26h: burn-theme absent -> it publishes the safe tier rather than a private duplicate of the rules" \
  "$(jq -r '.level' "$B16DEGWD/.local/.ctx-status.json" 2>/dev/null)" "ok"
check "26h: burn-theme absent -> and the occupancy it publishes is unaffected" \
  "$(jq -r '.used_percentage' "$B16DEGWD/.local/.ctx-status.json" 2>/dev/null)" "66"

# --- 26i. The shape does not move -------------------------------------------
# Most of this clause is already pinned, uncoloured, in section 23: the group
# count and the vanishing separators (23a/23b), the omission rules (23b/23o),
# the integer truncation of r5 and r7 (24d), the one string with no trailing
# newline (23g), and the warm-render process budget (23l) -- which B16 cannot
# move, since every helper it adds is pure bash builtins and forks nothing. What
# is added here is the same statement made against the COLOURED line, where a
# sequence wrapped around the wrong span changes the shape without changing a
# byte of the stripped text.
check "26i: the fully-coloured line still carries exactly three dim separators" \
  "$(printf '%s' "$b16_static_raw" | grep -oaF "$B16_SEP" | wc -l | tr -d ' ')" "3"
check "26i: the fully-coloured line carries no emoji" \
  "$(burn_no_emoji "$(b16_strip "$b16_static_raw")")" "yes"
check "26i: and it stays well-formed" \
  "$(burn_wellformed "$(b16_strip "$b16_static_raw")")" "yes"
# An overrun renders above 100 rather than clamping -- the whole reason this
# plugin computes occupancy itself -- and takes the top band by the same >=60
# rule as any lesser overrun, with no special case for it in the renderer.
check "26i: an overrun (350,000/300,000 = 116%) renders in burn_ctx_color's top band" \
  "$(b16_raw_line "$(burn_json "$B5_WD" 350000 "" "" "" "" "" "" "" "")")" \
  "$(burn_ctx_color 116)ctx 116%$B16_RST"
check "26i: and that is the same band a 60% context takes -- nothing clamps, nothing special-cases" \
  "$([ "$(burn_ctx_color 116)" = "$(burn_ctx_color 60)" ] && echo yes || echo no)" "yes"

# === 27. B18 statusline-bash3-payload-delimiter =============================
# Contract: the `Contract: B18 statusline-bash3-payload-delimiter` docblock
# above sl_parse_input. One byte changes -- \x01 to \x1f -- at BOTH ends of the
# payload round trip: the `join` closing the jq filter and the `IFS=` prefix on
# the `read`. Nothing else about the function moves.
#
# THE PROBLEM THIS SECTION HAS TO SOLVE. Under bash 5 the two bytes behave
# identically, so a test that renders the statusline and compares output passes
# before and after the fix and proves nothing. The contract says so outright:
# "a regression test must distinguish the two BYTES rather than re-check today's
# rendered output, which is identical either way". And no bash 3.2 interpreter
# is available here, or in ci.sh's environment, to make the difference show
# itself the way it shows itself on macOS.
#
# The way out is that the bytes only look alike while BOTH ENDS USE THE SAME
# ONE. Decouple the ends and each becomes independently observable under bash 5:
#
#   - the READ end (27a/27b): shadow `jq` with a shell FUNCTION, so the test
#     chooses the exact bytes the `read` is handed. Feed it a 0x1f-joined
#     payload and today's `IFS=$'\x01' read` does not split it -- every field
#     lands in window_size and the other thirteen come back empty, which is
#     precisely the shape macOS renders, reproduced here on bash 5.
#   - the JQ end (27c): shadow `jq` with a function that CAPTURES the filter and
#     delegates to the real binary, then execute that captured filter and look
#     at the byte it actually put between the fields.
#
# So a fix at one end only is NAMED (27a or 27c goes red on its own) rather than
# merely failing somewhere. 27d pins the other half of that: with the ends
# disagreeing the render really is broken, so "both ends" is load-bearing and
# not a stylistic preference.
#
# Nothing here re-tests what sl_parse_input parses OUT of the JSON -- that is
# B04's clause and section 22 owns it. What is tested here is the byte between
# the fields, at each end, and that everything else stands still.

B18_SOH=$(printf '\001')      # 0x01: bash 3.2's CTLESC, the byte being retired
B18_US=$(printf '\037')       # 0x1f: ASCII US, the byte the contract names
B18_RS=$(printf '\036')       # 0x1e: a THIRD non-whitespace byte, for 27e
B18_DEL=$(printf '\177')      # 0x7f: bash 3.2's CTLNUL, unusable for the same reason
B18_TAB=$(printf '\t')

B18_WD="$TMPROOT/b18-wd"; mkdir -p "$B18_WD"
# Every b18 render and probe runs with its PROCESS cwd here: a plain temp dir,
# no git, no .local. The half-swapped renderers in 27d parse an EMPTY cwd out of
# their payload, and a renderer with no cwd falls back to wherever it happens to
# be standing -- which, run bare, is this repo. Standing it somewhere inert
# keeps that fallback hermetic instead of forking git against the real worktree.
B18_RUN="$TMPROOT/b18-run"; mkdir -p "$B18_RUN"

# The payload every probe pipes in at SOURCE time, so the top-level render that
# sourcing context.sh performs is as hermetic as every other helper's here.
B18_JSON="{\"workspace\":{\"current_dir\":\"$B18_WD\"},\"transcript_path\":\"\",$ctx}"

# The fourteen variables sl_parse_input's `read` names, in contract order.
B18_SHOW='printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" \
  "$window_size" "$total_input" "$transcript_path" "$cwd" "$model_name" "$effort" \
  "$r5" "$r5_reset" "$r7" "$r7_reset" "$lines_added" "$lines_removed" \
  "$total_cost_usd" "$session_id"'
B18_UNSET='unset window_size total_input transcript_path cwd model_name effort \
  r5 r5_reset r7 r7_reset lines_added lines_removed total_cost_usd session_id'
# "s" per name still ASSIGNED after the read. Paired with B18_UNSET above it is
# the difference between "fourteen empty fields" and "thirteen unset variables":
# `read` assigns every name it is given, so a name dropped from the read list
# stays unset here rather than merely reading empty.
B18_SETCHK='printf "%s%s%s%s%s%s%s%s%s%s%s%s%s%s" \
  "${window_size+s}" "${total_input+s}" "${transcript_path+s}" "${cwd+s}" \
  "${model_name+s}" "${effort+s}" "${r5+s}" "${r5_reset+s}" "${r7+s}" \
  "${r7_reset+s}" "${lines_added+s}" "${lines_removed+s}" \
  "${total_cost_usd+s}" "${session_id+s}"'

B18_JQ_LOG="$TMPROOT/b18-jq-calls"

# b18_read(jq_stdout, bash_code, [NAME=VALUE...]): source context.sh, REPLACE
# `jq` with a shell function emitting JQ_STDOUT verbatim, unset the fourteen
# names, call sl_parse_input, then run BASH_CODE in the same shell.
#
# A function shadows an external command for every unqualified call, so this
# hands the `read` an exact byte sequence of the test's choosing without
# touching context.sh -- the whole reason the two bytes stop looking alike. The
# function is defined AFTER the source, so the full render that sourcing
# performs still goes through the REAL jq and the call log below counts only
# sl_parse_input's own invocation. Fresh bash under `env`, like b16_in_source,
# so nothing this harness defines can be mistaken for something context.sh left.
b18_read() { # jq_stdout bash_code [env...]
  local out="$1" code="$2"; shift 2
  ( cd "$B18_RUN" || return 1
    printf '%s' "$B18_JSON" \
      | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
          CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
          CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/b18-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
          B18_JQ_OUT="$out" B18_JQ_LOG="$B18_JQ_LOG" "$@" \
          bash -c '
            . "$1" >/dev/null 2>&1
            jq() { printf "x" >> "$B18_JQ_LOG"; printf "%s" "$B18_JQ_OUT"; }
            : > "$B18_JQ_LOG"
            input="{}"
            eval "$3"
            sl_parse_input
            eval "$2"
          ' _ "$CONTEXT" "$code" "$B18_UNSET" )
}

# The candidate bytes sl_parse_input's `read` DOES treat as a field separator,
# as a comma-separated list of hex names. Two fields either side of each byte:
# split -> window_size is "A" alone, no split -> window_size is the whole
# string. So this is the read end's IFS membership OBSERVED rather than read off
# the source, and the assertion over it reads "got '01', expected '1f'" -- the
# diagnostic names the defect itself.
#
# All six candidates are probed inside ONE sourced shell, re-pointing the jq
# shadow between calls: sl_parse_input is a pure function of $input and what jq
# hands back, and B06 froze this file's COST as well as its assertions, so six
# whole renders to read six bytes would be five renders wasted.
b18_read_delims() {
  b18_read "" '
    _b18_out=""
    for _b18_h in 01 1e 1f 7f 09 20; do
      case "$_b18_h" in
        01) _b18_b=$(printf "\001") ;; 1e) _b18_b=$(printf "\036") ;;
        1f) _b18_b=$(printf "\037") ;; 7f) _b18_b=$(printf "\177") ;;
        09) _b18_b=$(printf "\011") ;;  *) _b18_b=" " ;;
      esac
      B18_JQ_OUT="A${_b18_b}B"
      sl_parse_input
      if [ "$window_size" = "A" ]; then
        [ -n "$_b18_out" ] && _b18_out="$_b18_out,"
        _b18_out="$_b18_out$_b18_h"
      fi
    done
    printf "%s" "$_b18_out"
  '
}

b18_byte_of() { # hex_name
  case "$1" in
    01) printf '%s' "$B18_SOH" ;; 1e) printf '%s' "$B18_RS" ;;
    1f) printf '%s' "$B18_US"  ;; 7f) printf '%s' "$B18_DEL" ;;
    09) printf '%s' "$B18_TAB" ;; 20) printf ' ' ;;
  esac
}

# Control bytes rendered legibly, so a failing check's "got ..." names the byte
# it found instead of printing it invisibly.
b18_visible() { # string
  local s="$1"
  s="${s//"$B18_SOH"/<01>}"; s="${s//"$B18_RS"/<1e>}"
  s="${s//"$B18_US"/<1f>}";  s="${s//"$B18_DEL"/<7f>}"
  s="${s//"$B18_TAB"/<09>}"
  printf '%s' "$s"
}

# Occurrences of BYTE in STRING, builtin-only (B06: no fork in a helper called
# per assertion).
b18_count_byte() { # string byte
  local s="$1" b="$2" n=0
  while [ -n "$s" ]; do
    case "$s" in
      *"$b"*) s="${s#*"$b"}"; n=$(( n + 1 )) ;;
      *) break ;;
    esac
  done
  printf '%s' "$n"
}

# --- 27a. The READ end: which byte does `read` actually split on? -----------
# Probed ONCE and reused here and in 27f: each b18_read call is a whole render
# (context.sh is a script, so sourcing it renders one), and B06 froze this
# file's cost alongside its assertions.
B18_READ_DELIMS=$(b18_read_delims)
b18_delims_have() { # hex_name
  case ",$B18_READ_DELIMS," in *",$1,"*) printf 'yes' ;; *) printf 'no' ;; esac
}
check "27a: control -- the probe observes an unsplit single field (the harness is not vacuous)" \
  "$(b18_read "A" 'printf "%s" "$window_size"')" "A"
check "27a: the read end splits on exactly one candidate byte, and it is 0x1f" \
  "$B18_READ_DELIMS" "1f"
# The two halves of that, stated separately, so a fix applied at one end only is
# NAMED. This is the pair that goes red on a jq-end-only fix.
check "27a: a 0x1f-joined payload splits -- the new byte is the read's IFS" \
  "$(b18_delims_have 1f)" "yes"
check "27a: a 0x01-joined payload does NOT -- the retired byte is no longer the read's IFS" \
  "$(b18_delims_have 01)" "no"
# The macOS failure shape, reproduced on bash 5: hand the read a payload joined
# on the byte the FIXED jq end emits and, unfixed, all fourteen fields land in
# window_size with the other thirteen empty. Exit 0, nothing on stderr, a
# statusline with an empty cwd -- exactly what the Why clause describes.
b18_head="A${B18_US}B${B18_US}C"
check "27a: three 0x1f-separated fields do not all collapse into window_size" \
  "$(b18_visible "$(b18_read "$b18_head" 'printf "%s/%s/%s" "$window_size" "$total_input" "$transcript_path"')")" \
  "A/B/C"

# --- 27b. The READ end: fourteen fields, in order, empties preserved --------
# Field ORDER gets its own assertion because a fourteen-name positional read is
# exactly the kind of thing a careless edit reorders, and every value here is
# distinct so a transposition cannot hide.
b18_ordered="f01"
for _i in 02 03 04 05 06 07 08 09 10 11 12 13 14; do
  b18_ordered="$b18_ordered${B18_US}f$_i"
done
unset _i
check "27b: fourteen 0x1f-separated fields land one per variable, in contract order" \
  "$(b18_visible "$(b18_read "$b18_ordered" "$B18_SHOW")")" \
  "f01|f02|f03|f04|f05|f06|f07|f08|f09|f10|f11|f12|f13|f14"
check "27b: and the read still assigns all fourteen names (none dropped from its list)" \
  "$(b18_read "$b18_ordered" "$B18_SETCHK")" "ssssssssssssss"

# The invariant \x01 was chosen over @tsv's tab for, restated on the new byte:
# an absent transcript_path (field 3) must parse EMPTY and shift nothing after
# it. With a whitespace delimiter the run of two collapses and every later field
# moves up one column.
b18_gap="1000000${B18_US}145230${B18_US}${B18_US}/cwd${B18_US}Opus${B18_US}high${B18_US}42${B18_US}1700000000${B18_US}17${B18_US}1700500000${B18_US}503${B18_US}16${B18_US}12.34${B18_US}sess-gap"
check "27b: an empty middle field parses empty and shifts nothing after it" \
  "$(b18_visible "$(b18_read "$b18_gap" "$B18_SHOW")")" \
  "1000000|145230||/cwd|Opus|high|42|1700000000|17|1700500000|503|16|12.34|sess-gap"

# Edge case: every optional field absent. jq joins fourteen empty strings, so
# what reaches the read is thirteen delimiters and nothing else. Fourteen empty
# fields -- not one field holding thirteen bytes and thirteen empties, which is
# what today's read makes of it.
b18_allempty=""
for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do b18_allempty="$b18_allempty$B18_US"; done
unset _i
check "27b: a payload with every field absent parses as fourteen empty fields" \
  "$(b18_visible "$(b18_read "$b18_allempty" "$B18_SHOW")")" "|||||||||||||"

# The `effort` fallback to CLAUDE_EFFORT is "same fallbacks" in the Behavior
# clause: it applies AFTER the split, so it must neither stop firing nor start
# overriding. model_name rides both assertions so neither can pass on the
# unsplit string (where effort is empty and the fallback fires for the wrong
# reason).
b18_eff_empty="1000000${B18_US}145230${B18_US}${B18_US}/cwd${B18_US}Opus${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}"
check "27b: the CLAUDE_EFFORT fallback still fires after the split when the field is empty" \
  "$(b18_visible "$(b18_read "$b18_eff_empty" 'printf "%s/%s" "$model_name" "$effort"' CLAUDE_EFFORT=medium)")" \
  "Opus/medium"
b18_eff_set="1000000${B18_US}145230${B18_US}${B18_US}/cwd${B18_US}Opus${B18_US}high${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}"
check "27b: and still does not override an effort the payload carried" \
  "$(b18_visible "$(b18_read "$b18_eff_set" 'printf "%s/%s" "$model_name" "$effort"' CLAUDE_EFFORT=medium)")" \
  "Opus/high"

# --- 27c. The JQ end: which byte does the filter actually emit? -------------
# Capture the filter sl_parse_input hands to jq, then EXECUTE it with the real
# binary and look at what came out. Structural in how it gets hold of the
# filter, behavioural in what it asserts: not "the source says \u001f" but "the
# filter this function runs puts 0x1f between the fields".
B18_FILTER="$TMPROOT/b18-filter.jq"
( cd "$B18_RUN" || exit 1
  printf '%s' "$B18_JSON" \
    | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/b18-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        B18_FILTER_OUT="$B18_FILTER" \
        bash -c '
          . "$1" >/dev/null 2>&1
          jq() { printf "%s" "${@: -1}" > "$B18_FILTER_OUT"; command jq "$@"; }
          input="$2"
          sl_parse_input
        ' _ "$CONTEXT" "$B18_JSON" ) >/dev/null 2>&1

check "27c: control -- the captured filter really is sl_parse_input's own (not an empty file)" \
  "$( { [ -s "$B18_FILTER" ] && grep -q 'context_window_size' "$B18_FILTER" \
        && grep -q 'join(' "$B18_FILTER"; } && echo yes || echo no)" "yes"

# Fourteen distinguishable values, field 1 a known seven characters wide so the
# separator is the byte at offset 7 -- read positionally rather than by scanning
# for "the non-printable one", so a delimiter that IS printable is caught too.
b18_pay="{\"context_window\":{\"context_window_size\":1000000,\"total_input_tokens\":145230},\"transcript_path\":\"/tp\",\"workspace\":{\"current_dir\":\"/cw\"},\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"},\"session_id\":\"sess-abc\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":1700000000},\"seven_day\":{\"used_percentage\":17,\"resets_at\":1700500000}},\"cost\":{\"total_lines_added\":503,\"total_lines_removed\":16,\"total_cost_usd\":12.34}}"
b18_joined=$(printf '%s' "$b18_pay" | jq -r "$(<"$B18_FILTER")")
check "27c: the filter's own output separates the fields with 0x1f" \
  "$(b18_visible "${b18_joined:7:1}")" "<1f>"
check "27c: thirteen of them -- one per gap between the fourteen fields" \
  "$(b18_count_byte "$b18_joined" "$B18_US")" "13"
check "27c: and not one 0x01 byte survives in what jq emits" \
  "$(b18_count_byte "$b18_joined" "$B18_SOH")" "0"
# Order and count at the JQ end, independently of the read end: the same
# fourteen fields, the same order, on the new byte.
check "27c: the fourteen fields come out in the contract's order, on the new byte" \
  "$(b18_visible "$b18_joined")" \
  "1000000<1f>145230<1f>/tp<1f>/cw<1f>Opus<1f>high<1f>42<1f>1700000000<1f>17<1f>1700500000<1f>503<1f>16<1f>12.34<1f>sess-abc"
# "Same single jq invocation." Section 22i owns the per-RENDER budget through
# the PATH-shim harness; this is the narrower statement the delimiter clause
# needs -- one jq inside sl_parse_input itself -- counted by the same function
# shadow the rest of 27a/27b uses, so it duplicates nothing.
b18_read "$b18_allempty" 'true' >/dev/null
check "27c: sl_parse_input spends exactly one jq invocation" \
  "$(b18_count_byte "$(<"$B18_JQ_LOG")" x)" "1"

# --- 27d. Both ends, or neither: the half-fix renders the defect ------------
# Copies of context.sh with the delimiter rewritten at ONE end only. The seds
# match \x<any two hex> / \u00<any two hex> rather than \x01 specifically, so
# they stay half-swaps in both directions -- before the fix and after it. Each
# is then a live demonstration that the ends must agree, and the control that
# stops all of 27a/27c from being a statement about a byte nothing depends on.
b18_shadow() { # name sed_arg...
  local name="$1"; shift
  local d="$TMPROOT/b18-$name" f
  mkdir -p "$d/scripts" "$d/lib"
  sed "$@" "$CONTEXT" > "$d/scripts/context.sh"
  for f in platform.sh states.sh states.tsv burn-math.sh burn-tick.sh burn-theme.sh; do
    ln -s "$SCRIPT_DIR/../lib/$f" "$d/lib/$f"
  done
  printf '%s' "$d/scripts/context.sh"
}
B18_SED_READ='/IFS=\$/ s/\\x[0-9a-fA-F]{2}/\\x1e/'
B18_SED_JQ='s/join\("\\u00[0-9a-fA-F]{2}"\)/join("\\u001e")/'
B18_HALF_READ=$(b18_shadow half-read -E -e "$B18_SED_READ")
B18_HALF_JQ=$(b18_shadow half-jq -E -e "$B18_SED_JQ")
B18_BOTH=$(b18_shadow both -E -e "$B18_SED_READ" -e "$B18_SED_JQ")

b18_render() { # script cache_dir json
  ( cd "$B18_RUN" || return 1
    printf '%s' "$3" \
      | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
          CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
          CLAM_STATUSLINE_CACHE_DIR="$2" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
          bash "$1" 2>/dev/null )
}
# No model name (no rainbow, whose palette offset advances one frame per render)
# and no reset on either limit (no countdown), for 26a's reason: what is left is
# exactly reproducible across two renders.
B18_RENDER_JSON=$(burn_json "$B18_WD" 145230 "" "max" 1 "" 62 "" 503 16)
b18_carries_cwd() { # script cache_dir
  if b18_render "$1" "$2" "$B18_RENDER_JSON" | grep -qF "$B18_WD"; then
    printf 'yes'
  else
    printf 'no'
  fi
}
# Exactly ONE line moved in each half-swap and exactly TWO in the both-swap,
# which is only possible if the two seds hit DIFFERENT lines -- i.e. these
# really are the two ends, and neither sed silently caught a third site.
b18_changed_lines() { # file
  diff "$CONTEXT" "$1" | grep -c '^< '
}
check "27d: control -- each half-swap rewrote exactly one end, and a different one" \
  "$(b18_changed_lines "$B18_HALF_READ")/$(b18_changed_lines "$B18_HALF_JQ")/$(b18_changed_lines "$B18_BOTH")" \
  "1/1/2"
check "27d: the real renderer parses the payload's cwd and renders it" \
  "$(b18_carries_cwd "$CONTEXT" "$TMPROOT/b18-c-real")" "yes"
check "27d: swapping ONLY the read end renders the defect -- an empty cwd" \
  "$(b18_carries_cwd "$B18_HALF_READ" "$TMPROOT/b18-c-hr")" "no"
check "27d: swapping ONLY the jq end renders the defect too -- the ends must agree" \
  "$(b18_carries_cwd "$B18_HALF_JQ" "$TMPROOT/b18-c-hj")" "no"

# --- 27e. Outputs: byte-identical under bash 5 ------------------------------
# The Outputs clause is an INVARIANCE clause, so its check is green before the
# change and green after -- that is what it means. It is not vacuous: the
# comparison is against a renderer joined and split on a THIRD byte (0x1e), so
# what it pins is "the rendered line does not depend on which non-whitespace
# byte carries the payload", which stays a real statement once \x1f lands. A
# fix that also reordered a field, dropped one, or moved a fallback breaks it.
check "27e: control -- the 0x1e renderer really carries neither candidate byte at either end" \
  "$(grep -vE '^[[:space:]]*#' "$B18_BOTH" | grep -cE '\\x01|\\u0001|\\x1f|\\u001f')" "0"
check "27e: a renderer carrying the payload on 0x1e instead renders byte-identical output" \
  "$([ "$(b18_render "$CONTEXT" "$TMPROOT/b18-p-real" "$B18_RENDER_JSON")" \
     = "$(b18_render "$B18_BOTH" "$TMPROOT/b18-p-both" "$B18_RENDER_JSON")" ] && echo yes || echo no)" "yes"

# --- 27f. The negative: a whitespace delimiter is not substitutable ---------
# The reason the delimiter is a control byte at all. bash treats tab and space
# as "IFS whitespace" even when IFS is set to only one of them, so runs of the
# delimiter collapse -- an absent field between two present ones swallows the
# next column and misaligns everything after it. The first check applies the
# byte DERIVED in 27a, so it is a statement about the delimiter the code uses,
# not about a byte named here; the other two are the negative it is measured
# against.
b18_split_shape() { # byte
  local a b c d
  IFS="$1" read -r a b c d <<< "A$1$1C$1D"
  printf '[%s][%s][%s][%s]' "$a" "$b" "$c" "$d"
}
B18_DELIM=$(b18_byte_of "$B18_READ_DELIMS")
check "27f: the byte sl_parse_input's read splits on preserves an empty middle field" \
  "$(b18_split_shape "$B18_DELIM")" "[A][][C][D]"
check "27f: a tab does not -- the run collapses and the next column is swallowed" \
  "$(b18_split_shape "$B18_TAB")" "[A][C][D][]"
check "27f: nor does a space, for the same reason" \
  "$(b18_split_shape " ")" "[A][C][D][]"

# --- 27g. The in-function comment explains BOTH reasons ---------------------
# A structural assertion over the source text, and deliberately so: `declare -f`
# drops comments, so bash's own parse cannot see this clause. The contract makes
# the comment load-bearing -- a reader who knows only the tab reason will
# "simplify" \x1f back to \x01, since \x01 answers the tab problem just as well.
# Only the comment lines INSIDE the function are read, so the docblock above it
# (which legitimately spells both bytes while explaining them) is out of scope.
b18_fn_comment=$(sed -n '/^sl_parse_input() {$/,/^  IFS=/p' "$CONTEXT" \
  | grep -E '^[[:space:]]*#')
check "27g: control -- there is an in-function comment to read at all" \
  "$([ "$(printf '%s\n' "$b18_fn_comment" | grep -c '#')" -ge 3 ] && echo yes || echo no)" "yes"
check "27g: it names the byte actually in use (0x1f)" \
  "$(printf '%s\n' "$b18_fn_comment" | grep -qiE '\\x1f|\\u001f|0x1f|001f' && echo yes || echo no)" "yes"
check "27g: it explains the bash 3.2 reason, by version" \
  "$(printf '%s\n' "$b18_fn_comment" | grep -qE 'bash 3|3\.2' && echo yes || echo no)" "yes"
check "27g: and says what 3.2 does with the byte (sentinel / CTLESC)" \
  "$(printf '%s\n' "$b18_fn_comment" | grep -qiE 'sentinel|ctlesc|quoting' && echo yes || echo no)" "yes"
check "27g: while still explaining the ORIGINAL tab/whitespace reason" \
  "$(printf '%s\n' "$b18_fn_comment" | grep -qiE 'whitespace|tab' && echo yes || echo no)" "yes"

# --- 27h. Neither byte appears anywhere else in the plugin ------------------
# Two scans, because the byte can arrive two ways. The first is over ESCAPE
# SPELLINGS on non-comment lines of the plugin's non-test shell sources: prose
# explaining \x01 is exactly what the contract asks for and must not trip it,
# and the test file legitimately builds both bytes as fixture data, which is why
# neither is scanned. That leaves executable use, which is what the invariant is
# about. The second is over LITERAL bytes and covers every file including this
# one -- this suite constructs its control bytes with printf at runtime and so
# contains none.
B18_PLUGIN="$SCRIPT_DIR/.."
B18_ESCAPES='\\x01|\\u0001|\\x7[fF]|\\u007[fF]|\\001|\\177'
b18_code_hits() {
  local f n=0 c
  for f in "$B18_PLUGIN"/lib/*.sh "$B18_PLUGIN"/scripts/*.sh; do
    case "$f" in *.test.sh) continue ;; esac
    [ -f "$f" ] || continue
    c=$(grep -vE '^[[:space:]]*#' "$f" | grep -cE "$B18_ESCAPES")
    n=$(( n + c ))
  done
  printf '%s' "$n"
}
check "27h: no executable line of any non-test plugin script spells 0x01 or 0x7f" \
  "$(b18_code_hits)" "0"
check "27h: control -- that pattern does match where the bytes are legitimately spelled, so it is falsifiable" \
  "$([ "$(grep -cE "$B18_ESCAPES" "$SCRIPT_DIR/context.test.sh")" -gt 0 ] && echo yes || echo no)" "yes"
check "27h: and no plugin file carries a literal 0x01 or 0x7f byte, this suite included" \
  "$(LC_ALL=C grep -rl "[$B18_SOH$B18_DEL]" "$B18_PLUGIN" 2>/dev/null | grep -c . | tr -d ' ')" "0"
B18_PLANT="$TMPROOT/b18-planted-byte"
printf 'before%safter\n' "$B18_SOH" > "$B18_PLANT"
check "27h: control -- that byte scan does find a planted 0x01, so it is falsifiable too" \
  "$(LC_ALL=C grep -rl "[$B18_SOH$B18_DEL]" "$B18_PLANT" 2>/dev/null | grep -c . | tr -d ' ')" "1"

# --- 27i. Edge case: a field whose VALUE contains the delimiter -------------
# The contract calls this "the same theoretical hazard the old byte carried and
# no more likely", so these pin today's behaviour rather than demanding escaping
# the contract does not ask for. Both run end to end through the REAL jq, and
# the pair moves together: the hazard transfers from one byte to the other, it
# does not appear or disappear. A \x1f inside a model name splits it (as a \x01
# inside one splits it today); a \x01 inside one becomes harmless.
b18_parse() { # json bash_code
  ( cd "$B18_RUN" || return 1
    printf '%s' "$B18_JSON" \
      | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
          CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
          CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/b18-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
          bash -c '
            . "$1" >/dev/null 2>&1
            input="$2"
            sl_parse_input
            eval "$3"
          ' _ "$CONTEXT" "$1" "$2" )
}
b18_val_us="{\"workspace\":{\"current_dir\":\"$B18_WD\"},\"transcript_path\":\"\",$ctx,\"model\":{\"display_name\":\"Op\\u001fus\"},\"effort\":{\"level\":\"high\"}}"
check "27i: a 0x1f inside a field value misparses -- the hazard the new byte inherits" \
  "$(b18_visible "$(b18_parse "$b18_val_us" 'printf "%s/%s" "$model_name" "$effort"')")" "Op/us"
b18_val_soh="{\"workspace\":{\"current_dir\":\"$B18_WD\"},\"transcript_path\":\"\",$ctx,\"model\":{\"display_name\":\"Op\\u0001us\"},\"effort\":{\"level\":\"high\"}}"
check "27i: while a 0x01 inside one is now harmless, where today it splits the field" \
  "$(b18_visible "$(b18_parse "$b18_val_soh" 'printf "%s/%s" "$model_name" "$effort"')")" "Op<01>us/high"
# And the same round trip with nothing unusual in it: real jq, real read, every
# optional field absent. Green either side of the change by construction -- both
# bytes split correctly on bash 5 -- and there to catch a fix that dropped or
# reordered a field while it was in the neighbourhood.
check "27i: a fully-absent payload still round-trips through real jq as fourteen empty fields" \
  "$(b18_visible "$(b18_parse '{}' "$B18_SHOW")")" "|||||||||||||"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
