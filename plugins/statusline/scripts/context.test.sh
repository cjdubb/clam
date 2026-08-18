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
# Under B18 (plan 003-statusline-meter-colour) the payload fields are
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
# Under B07/B08 (plan 001-statusline-glance-uplift) line 1 gains the project
# directory beside the working directory, wrapped in an OSC 8 file:// hyperlink
# whose terminator moves from ST to BEL, and the expensive-segment cache moves
# off transcript_path onto session_id with a cold-path sweep bounding the cache
# directory. Both blocks are SCAFFOLDED but not wired at the time sections 28
# and 29 were written, so each clause is stated in whichever of the two shapes
# says it honestly: a direct call on the new helper, or a full render whose old
# path still runs. Neither block retires a FIGURE, so nothing earlier in this
# file is deleted; but B07 does move two bytes earlier sections had pinned, and
# three of them are retargeted onto the same clause rather than weakened:
# section 27b/27c's field count (project_dir is APPENDED LAST to the one jq, so
# the round trip is thirteen fields and twelve delimiters, and the twelve before
# it do not move), 25b's one OSC-8 literal (ST -> BEL; the clause is "the
# hyperlink wraps the number alone", not "the terminator is ST"), and the two
# strippers -- render() and osc8_strip now share ONE expression that accepts
# EITHER terminator, so both keep reading the text a terminal DISPLAYS, which
# is what sections 7/7b and the badge runs assert and what B07's Errors clause
# promises. Those retargets go red before B07 is wired and green after it, in
# the same way sections 28 and 29 do; render_raw() still strips nothing.
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
# the round trip independently (section 27); the project-dir/current-dir head of
# line 1 and its OSC 8 hyperlink (section 28); and the session-keyed segment
# cache with its cold-path sweep (section 29).
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
#   - Exactly 515 PASS lines and a zero exit. A changed count is a defect,
#     whichever direction it moves. (Was 86 when this contract was written;
#     the burnrate uplift raised it to 277, B09/B10's sections 24 and 25
#     raised it to 381, B16's section 26 raised it to 459, B18's section 27
#     raised it to 497, and B05 line2-groups -- plan
#     001-statusline-glance-uplift -- moved it again when it replaced sections
#     23/24 with one section and retired the figures section 26 coloured; the
#     relocation of lib/burn-tick.test.sh's two retirement assertions into
#     section 26j, plus their non-vacuity guard, raised it by three to 419;
#     B07 line1-paths and B08 cache-session-key -- same plan -- then added
#     sections 28 and 29 outright, 96 assertions between them, for 515. The
#     rule is the frozen count, not the number, so the number moves when a
#     deliberate change to the suite lands and stays frozen in between.
#     Count it as `grep -cE '^(PASS|FAIL)  '` over a full run: this file ends
#     with a bare "FAILURES" epilogue on a red run, and a `grep -c '^FAIL'`
#     that catches that line reports one assertion too many. Both of B05's test
#     waves derived the number that way and landed on 420; the measured total
#     is 419.)
#   - No assertion may be weakened, skipped, merged, or deleted. B05 is the
#     kind of deliberate change the clause above allows for: it DELETES the
#     assertions for figures its contract retires -- the +added/-removed
#     segment, %t, %/d -- because a test for a figure that no longer renders
#     cannot be kept honestly. Every clause those assertions covered that
#     SURVIVES B05 is re-pinned in the new section 23, and nothing surviving
#     was weakened or merged to make room.
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

# Never inherit the harness's own effort or schedule knobs; each case sets them
# explicitly. B05's three schedule knobs steer B01's working-week model, so a
# value leaking in from the developer's shell would move every weekly trend.
# CLAM_STATUSLINE_SLEEP_HOURS is unset too although B05 retires it: a stale
# value in a developer's shell must not be able to matter either way.
unset CLAUDE_EFFORT CLAM_STATUSLINE_WORK_DAYS CLAM_STATUSLINE_DAY_START \
      CLAM_STATUSLINE_DAY_END CLAM_STATUSLINE_SLEEP_HOURS

ESC=$(printf '\033')
BEL=$(printf '\a')
FAILED=0

# ONE OSC-8 stripping expression, shared by render() below and by osc8_strip in
# section 25, so the two cannot drift apart. It matches an OSC 8 introducer, its
# URL, and EITHER terminator -- the ST (ESC \) that osc8_link emitted before B07
# and the BEL that it emits after -- because what every caller wants is "the
# text a terminal DISPLAYS", which is the same text either way. Section 28's
# b07_visible states the same expression against B07's own path segment.
OSC8_RE="s/${ESC}\\]8;;[^${ESC}${BEL}]*(${ESC}\\\\|${BEL})//g"

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
#
# "ANSI stripped" is BOTH families: the CSI colour sequences, and the OSC 8
# hyperlink framing (either terminator, via OSC8_RE above). What is left is the
# text a terminal DISPLAYS, which is exactly what every caller of render()
# asserts on -- including the whole-line `grep -qxF` matches in sections 7 and
# 7b, which under B07 have hyperlink bytes on either side of line 1's path.
# B07's own Errors clause is that a terminal ignoring OSC 8 shows the visible
# text unchanged, so reading through the framing keeps those assertions saying
# precisely what they said before it. render_raw() below deliberately strips
# NEITHER family.
render() { # json
  printf '%s' "$1" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$LEGACY_CACHE_DIR" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        bash "$CONTEXT" 2>/dev/null \
    | sed -E "$OSC8_RE" \
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
# idle age from the transcript mtime. Uses `date` for bash 3.2 portability,
# with a BSD/GNU fallback for epoch formatting.
set_mtime_ago() { # file seconds_ago
  local f="$1" secs="$2" now epoch stamp
  now=$(date +%s)
  epoch=$(( now - secs ))
  stamp=$(date -r "$epoch" +%Y%m%d%H%M.%S 2>/dev/null) \
    || stamp=$(date -d "@$epoch" +%Y%m%d%H%M.%S 2>/dev/null)
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
  t0=$(date +%s)
  tnow=$(date +%s)
  while [ "$tnow" = "$t0" ]; do
    sleep 0.02
    tnow=$(date +%s)
  done
}

# Backdate (or, with a negative seconds_ago, future-date) every regular file
# under a directory. Used to age a cache bundle without sleeping out the full
# age in wall-clock time and without needing to know the bundle's internal
# filename. Waits for a second boundary first -- see settle_to_second.
backdate_all() { # dir seconds_ago
  local dir="$1" secs="$2" now epoch stamp
  settle_to_second
  now=$(date +%s)
  epoch=$(( now - secs ))
  stamp=$(date -r "$epoch" +%Y%m%d%H%M.%S 2>/dev/null) \
    || stamp=$(date -d "@$epoch" +%Y%m%d%H%M.%S 2>/dev/null)
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
# never ran B02's awk. Section 23l builds a separate shadow tree that
# deliberately omits them, which is what makes that degradation case meaningful.
# lib/burn-tick.sh is NOT linked: B05 retires the file outright, so a link to it
# would break this harness the moment the implementation lands.
ln -s "$SCRIPT_DIR/../lib/burn-math.sh" "$SHADOW/lib/burn-math.sh"
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
    # newline-terminated, so a line count matches `wc -l` here. Uses a
    # while-read loop for bash 3.2 portability.
    [ -f "$1" ] || return 0
    local _n=0
    while IFS= read -r _; do
      _n=$(( _n + 1 ))
    done < "$1"
    printf '%s' "$_n"
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

# 13b. Default TTL is 5s: a 2s-old bundle is still warm, a 5s-old bundle is
#      stale. Driven by whether a MODE-file change (a CACHED segment) shows.
#      The warm check uses 2s (not 4s) for a 3s margin, since wall-clock slack
#      under load can cross a 1s margin and flake the assertion.
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
backdate_all "$DEFTTL_DIR" 2
out=$(render_default_ttl "$ttljson")
check "default TTL (5s): a 2s-old bundle is still warm ('Build' cached value kept)" \
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
#      "never expires") -- same 2s-warm/5s-stale boundary as 13b, reached via
#      an explicit garbage value instead of an unset variable.
BAD_DIR="$TMPROOT/bad-ttl-cache"
BAD_WD="$TMPROOT/bad-ttl-wd"; mk_wt "$BAD_WD"
printf 'Build\n' > "$BAD_WD/.local/MODE"
badjson="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$BAD_WD\"},$ctx,\"transcript_path\":\"\"}"
render_cached "$badjson" "$BAD_DIR" "not-a-number" >/dev/null
printf 'Debug\n' > "$BAD_WD/.local/MODE"
backdate_all "$BAD_DIR" 2
out=$(render_cached "$badjson" "$BAD_DIR" "not-a-number")
check "non-integer TTL falls back to 5s: a 2s-old bundle is still warm ('Build' kept)" \
  "$(mode_cached_value "$out" 'Build')" "yes"
backdate_all "$BAD_DIR" 5
out=$(render_cached "$badjson" "$BAD_DIR" "not-a-number")
check "non-integer TTL falls back to 5s: a 5s-old bundle is stale ('Debug' reflected)" \
  "$(mode_cached_value "$out" 'Debug')" "yes"

# === 14. Cache key derivation (session_id, fallback: cwd) ==================

# 14a. Same cwd, different session_id -> independent bundles (a session is
#      never handed another session's cached segments just because they
#      share a worktree).
KEY_WD="$TMPROOT/key-wd"; mk_wt "$KEY_WD"
KEY_DIR="$TMPROOT/key-cache"
KEY_TR_A="$TMPROOT/key-a.jsonl"; echo '{}' > "$KEY_TR_A"
KEY_TR_B="$TMPROOT/key-b.jsonl"; echo '{}' > "$KEY_TR_B"
printf 'Build\n' > "$KEY_WD/.local/MODE"
keyA="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$KEY_WD\"},$ctx,\"transcript_path\":\"$KEY_TR_A\",\"session_id\":\"key-sess-a\"}"
keyB="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$KEY_WD\"},$ctx,\"transcript_path\":\"$KEY_TR_B\",\"session_id\":\"key-sess-b\"}"
render_cached "$keyA" "$KEY_DIR" 5 >/dev/null
printf 'Debug\n' > "$KEY_WD/.local/MODE"
outA=$(render_cached "$keyA" "$KEY_DIR" 5)
outB=$(render_cached "$keyB" "$KEY_DIR" 5)
check "same cwd, different session_id: session A stays warm on its own bundle ('Build')" \
  "$(mode_cached_value "$outA" 'Build')" "yes"
check "same cwd, different session_id: session B gets its own (cold) bundle, not A's ('Debug')" \
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

# 14c. session_id (when present) is the WHOLE key -- cwd is not also mixed
#      in. Same session_id, two different cwds (different git branches)
#      share one cached bundle: the branch segment stays pinned to whichever
#      cwd was rendered first, even once the render moves to the second cwd.
CWDLIVE_DIR="$TMPROOT/cwdlive-cache"
CWDLIVE_TR="$TMPROOT/cwdlive-tr.jsonl"; echo '{}' > "$CWDLIVE_TR"
CWDLIVE_1="$TMPROOT/cwdlive-1"; mk_wt "$CWDLIVE_1"; git -C "$CWDLIVE_1" checkout -q -b feature-one >/dev/null 2>&1
CWDLIVE_2="$TMPROOT/cwdlive-2"; mk_wt "$CWDLIVE_2"; git -C "$CWDLIVE_2" checkout -q -b feature-two >/dev/null 2>&1
cwd1json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$CWDLIVE_1\"},$ctx,\"transcript_path\":\"$CWDLIVE_TR\",\"session_id\":\"cwdlive-sess\"}"
cwd2json="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$CWDLIVE_2\"},$ctx,\"transcript_path\":\"$CWDLIVE_TR\",\"session_id\":\"cwdlive-sess\"}"
render_cached "$cwd1json" "$CWDLIVE_DIR" 5 >/dev/null
out=$(render_cached "$cwd2json" "$CWDLIVE_DIR" 5)
check "cache key is the session alone: same session_id across cwds shares one bundle (branch pinned to 'feature-one')" \
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

# 20c. A cwd that is a slash-less relative path (e.g. "max") must not loop
#      forever in the git-root walk. The %/* strip is a no-op on such a string,
#      so without a no-progress guard the loop never advances. The 3-second
#      timeout ensures a regression fails rather than hangs.
SLASHLESS_JSON="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"max\"},$ctx,\"transcript_path\":\"\"}"
SLASHLESS_TIMEOUT_CMD=""
for _t_cmd in timeout gtimeout; do
  command -v "$_t_cmd" >/dev/null 2>&1 && SLASHLESS_TIMEOUT_CMD="$_t_cmd" && break
done
if [ -n "$SLASHLESS_TIMEOUT_CMD" ]; then
  "$SLASHLESS_TIMEOUT_CMD" 3 bash -c 'printf "%s" "$1" | CLAUDE_PROJECTS_DIR="'"$TMPROOT"'/projects" CCOST_CACHE_DIR="'"$TMPROOT"'/cache" CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 CLAM_STATUSLINE_CACHE_DIR="'"$TMPROOT"'/slashless-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 bash "'"$CONTEXT"'" 2>/dev/null' _ "$SLASHLESS_JSON" >/dev/null
  slashless_rc=$?
  check "slash-less relative cwd terminates (rc=0, not rc=124 timeout)" \
    "$([ "$slashless_rc" -eq 0 ] && echo yes || echo no)" "yes"
else
  check "slash-less relative cwd (SKIPPED: no timeout command)" "skip" "skip"
fi

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
# Contract: sl_parse_input parses the burnrate fields from the SAME single jq
# invocation, the cached bundle drops its cost_line key (six keys -> five, mask
# 63 -> 31), and context.sh stops invoking ccost.sh entirely. Every case here
# observes the variables directly by sourcing context.sh rather than reading
# them out of the rendered text.
#
# B05 line2-groups (plan 001-statusline-glance-uplift) narrows the field list
# from eight to SIX: it retires the +added/-removed segment, so lines_added and
# lines_removed are removed from the jq filter and from the `read` that
# consumes it. The cases that pinned their VALUES are retargeted rather than
# deleted -- they now pin that the two names are not assigned at all, which is
# the sharper statement and the one a half-done retirement fails. The clause
# they were really carrying, "a gap in the middle does not swallow the fields
# after it", is kept by asserting it on total_cost_usd and session_id, which
# are exactly the fields that used to sit behind the two now-missing columns.

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
    declare -p r5 r5_reset r7 r7_reset total_cost_usd session_id 2>/dev/null
    # Reported separately, and deliberately NOT through declare -p: an unset
    # name prints nothing there, which is indistinguishable from a name the
    # eval simply did not carry. This makes the absence assertable.
    printf 'B05_RETIRED_FIELDS=%s%s\n' "${lines_added+set}" "${lines_removed+set}"
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
check "full payload: lines_added is not parsed at all (B05 retires the field)" \
  "$B05_RETIRED_FIELDS" ""
check "full payload: nor lines_removed, though the payload carries both" \
  "$(printf '%s' "$b04_full" | grep -qF 'total_lines_added' && echo carried || echo missing)" "carried"
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
check "rate_limits absent: cost/session_id still parse (total_cost_usd)" "$total_cost_usd" "1.5"
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
check "gap in middle (seven_day absent): the retired line-count names stay unset" \
  "$B05_RETIRED_FIELDS" ""
check "gap in middle (seven_day absent): total_cost_usd still lands correctly" "$total_cost_usd" "0.42"
check "gap in middle (seven_day absent): session_id still lands correctly" "$session_id" "sess-gap1"

# 22d. Reverse pairing: five_hour ABSENT, seven_day present, cost present.
b04_gap_rev="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\",\"session_id\":\"sess-gap2\",\"rate_limits\":{\"seven_day\":{\"used_percentage\":88,\"resets_at\":1700222222}},\"cost\":{\"total_lines_added\":11,\"total_lines_removed\":4,\"total_cost_usd\":2.75}}"
eval "$(parse_vars "$b04_gap_rev")"
check "gap in middle (five_hour absent): r5 empty" "$r5" ""
check "gap in middle (five_hour absent): r5_reset empty" "$r5_reset" ""
check "gap in middle (five_hour absent): r7 present" "$r7" "88"
check "gap in middle (five_hour absent): r7_reset present" "$r7_reset" "1700222222"
check "gap in middle (five_hour absent): the retired line-count names stay unset" \
  "$B05_RETIRED_FIELDS" ""
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
check "a genuine zero line count is not parsed either -- the field is gone, not zeroed" \
  "$B05_RETIRED_FIELDS" ""
check "genuine zero total_cost_usd parses to \"0\", not empty" "$total_cost_usd" "0"

# 22g. cost object entirely absent: total_cost_usd empty -- distinguishable
#      from the genuine-zero case above. Also confirms session_id is empty, not
#      just skipped, when absent.
b04_nocost="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$WD\"},$ctx,\"transcript_path\":\"\"}"
eval "$(parse_vars "$b04_nocost")"
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

# === 23. B05 line2-groups ===================================================
# Contract: the `Contract: B05 line2-groups (plan 001-statusline-glance-uplift)`
# docblock above sl_render_burn_line. It SUPERSEDES the previous B05 burnrate-
# line contract (plan 001-statusline-burnrate-uplift, amended by plans 002 and
# 003) entirely, so this section is a replacement for the old sections 23 and
# 24 rather than an amendment to them.
#
# Line 2 is now FOUR groups joined by the existing dim separator:
#
#   Fable 5 high | ctx 10% | 5h 1% v-1 (4h54m) | wk 32% v-25 (2d4h)
#
#   1 model    the model name in B03's FLAT per-model colour, and the effort
#              tier in its own colour.                    Glance-items 1 and 2.
#   2 context  `ctx` occupancy.                                 Glance-item 5.
#   3 5-hour   `5h` used%, trend, countdown.                    Glance-item 6.
#   4 weekly   `wk` used%, trend, countdown.                    Glance-item 7.
#
# The two limit groups carry the SAME three figures in the same order, which is
# why several cases below assert them as a pair: "the reader learns one reading
# rather than two" is a property of the line, not of either group.
#
# What this block RETIRES is asserted as sharply as what it renders, because a
# retirement that half-happens is the failure mode: the +added/-removed
# segment, the %t figure, the %/d figure, and the lines_added/lines_removed jq
# fields all go. Section 22 covers the parse end of that; 23d covers the render
# end. The library-level retirements (burn_metrics, burn_awake_seconds,
# burn_day_start_epoch, burn_rainbow, burn_model_style, burn_frame_advance,
# burn_diff_color, and the whole of lib/burn-tick.sh) are asserted in
# lib/burn-math.test.sh and lib/burn-theme.test.sh, which pin each file's
# surviving function roster as an exact equality.
#
# Expected values are DERIVED by calling the real B01/B02/B03/B04 functions
# rather than hard-coded. Every trend and countdown depends on the wall-clock
# instant the suite runs at, so a literal would be right today and wrong
# tomorrow. Where a figure varies continuously with `now` it is bracketed over
# [t0, t1] -- a `date` either side of the render -- rather than pinned at a
# single instant, which would be a rounding-boundary coin flip.

# The render's own "now", its local seconds-into-day, and its local ISO
# weekday. The contract's Inputs clause names exactly these: ONE plain `date`
# yielding seconds-into-day AND ISO weekday together, from which B01's anchor
# pair (midnight epoch, weekday) is derived. Derived here the same way, so an
# anchor computed here is the anchor the render builds a fraction of a second
# later.
B5_NOW=$(date +%s)
read -r _b5h _b5m _b5s _b5u <<< "$(date +'%H %M %S %u')"
B5_SECS=$(( 10#$_b5h * 3600 + 10#$_b5m * 60 + 10#$_b5s ))
B5_MIDNIGHT=$(( B5_NOW - B5_SECS ))
B5_WDAY=$_b5u
B5_R5_RESET=$(( B5_NOW + 17670 ))       # 4h54m30s out: 30s clear of a minute flip
B5_R7_RESET=$(( B5_NOW + 3 * 86400 ))

B5_WD="$TMPROOT/b5-wd"; mkdir -p "$B5_WD"
B5_CACHE="$TMPROOT/b5-cache"

# The default schedule, normalized by B01 itself rather than restated here:
# "1-5" 8 18, which the contract names as the default for each of the three
# knobs.
read -r B5_MASK B5_SS B5_ES <<< "$(burn_work_parse "1-5" 8 18)"

# burn_json(cwd tokens model effort r5 r5_reset r7 r7_reset added removed):
# a statusLine payload in which every field is independently PRESENT or ABSENT.
# "" omits the key from the JSON entirely; "0" emits a real zero. That
# distinction is the whole of the "empty is not zero" clause, so the fixture
# builder has to be able to express both.
#
# The two line-count arguments are KEPT even though B05 retires the figures
# they fed: a payload that carries them is exactly the payload on which "the
# counts no longer render" has to be asserted (23d). Claude Code still sends
# them; what changes is that this plugin stops reading them.
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
# set one schedule knob without leaking the value into any other.
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

# b5_trend_token(trend): the rendered form of a trend value -- the arrow chosen
# by SIGN, then B02's own signed number, with no space between them. Negative
# reads "▼-25", exactly as the contract's example line shows; positive takes
# the up arrow and B02's unsigned digits. Empty in, empty out, so a group
# builder can concatenate it unconditionally.
b5_trend_token() { # trend
  [ -n "$1" ] || return 0
  case "$1" in
    -*) printf '▼%s' "$1" ;;
    *)  printf '▲%s' "$1" ;;
  esac
}

# b5_five_group(used reset now) / b5_week_group(used reset now days start end):
# the ANSI-stripped text of a limit group as the contract composes it --
# label + integer used% , then the trend if its window can be computed, then
# B04's countdown in parens. Both are built from the REAL B02/B04 functions at
# a given `now`, which is what lets the assertions bracket the clock instead of
# guessing at it. Either figure failing drops that figure alone, never the
# group and never the used%.
b5_five_group() { # used reset now
  local g t cd
  g="5h ${1%%.*}%"
  t=$(burn_linear_trend "$1" "$3" "$2" 18000 2>/dev/null) && g="$g $(b5_trend_token "$t")"
  cd=$(burn_reset_str "$2" "$3" 2>/dev/null) && g="$g ($cd)"
  printf '%s' "$g"
}
b5_week_group() { # used reset now [days start end]
  local g t cd m s e
  read -r m s e <<< "$(burn_work_parse "${4:-1-5}" "${5:-8}" "${6:-18}")"
  g="wk ${1%%.*}%"
  t=$(burn_week_trend "$1" "$3" "$2" "$B5_MIDNIGHT" "$B5_WDAY" "$m" "$s" "$e" 2>/dev/null) \
    && g="$g $(b5_trend_token "$t")"
  cd=$(burn_reset_str "$2" "$3" 2>/dev/null) && g="$g ($cd)"
  printf '%s' "$g"
}

# b5_join(group...): assemble groups exactly as the contract's Outputs clause
# describes -- an empty group contributes NOTHING AT ALL, and the separator
# goes only BETWEEN present groups, one space either side. Expected lines are
# built with this rather than written out, so a case states which GROUPS it
# expects and the vanishing-separator rule is applied once, in one place.
b5_join() { # group...
  local acc="" g
  for g in "$@"; do
    [ -z "$g" ] && continue
    [ -n "$acc" ] && acc="$acc │ "
    acc="$acc$g"
  done
  printf '%s' "$acc"
}

# --- 23a. The whole line: four groups, in contract order ---------------------
# An EQUALITY over the whole ANSI-stripped line, bracketed over the interval
# the render's own clock provably fell inside. A grep for one group cannot tell
# a correct line from one that also gained a stray separator, lost a space, or
# put the groups in the wrong order; this can.
b5_full=$(burn_json "$B5_WD" 145230 "Opus" "max" 1 "$B5_R5_RESET" 62 "$B5_R7_RESET" 503 16)
b5_t0=$(date +%s)
b5_out=$(burn_render "$b5_full")
b5_t1=$(date +%s)
b5_line=$(burn_of "$b5_out")

b5_full_ok=no
for (( _n = b5_t0; _n <= b5_t1; _n++ )); do
  [ "$b5_line" = "$(b5_join "Opus max" "ctx 48%" \
      "$(b5_five_group 1 "$B5_R5_RESET" "$_n")" \
      "$(b5_week_group 62 "$B5_R7_RESET" "$_n")")" ] && b5_full_ok=yes
done
check "23a: the whole line is exactly model │ ctx │ 5h │ wk, every figure derived" \
  "$b5_full_ok" "yes"
check "23a: four groups joined by exactly three │ separators" \
  "$(printf '%s' "$b5_line" | grep -o '│' | wc -l | tr -d ' ')" "3"
check "23a: group 1 leads the line with the model name and effort tier" \
  "$(printf '%s' "$b5_line" | grep -qE '^Opus max │' && echo yes || echo no)" "yes"
check "23a: group 2 is the ctx occupancy (145,230/300,000 = 48%)" \
  "$(printf '%s' "$b5_line" | grep -qE '│ ctx 48% │' && echo yes || echo no)" "yes"
check "23a: group 3 is the 5-hour limit, not the weekly one" \
  "$(printf '%s' "$b5_line" | grep -qE '│ 5h 1%' && echo yes || echo no)" "yes"
check "23a: group 4 is the weekly limit, and it closes the line" \
  "$(printf '%s' "$(last_group "$b5_line")" | grep -qE '^wk 62%' && echo yes || echo no)" "yes"
# The two limit groups carry the SAME three figures in the same order. Asserted
# as a shape shared between them rather than twice in isolation, because "one
# reading, not two" is the clause.
check "23a: both limit groups read used% then trend then parenthesised countdown" \
  "$(printf '%s' "$b5_line" | grep -cE '(5h|wk) [0-9]+% (▲|▼)-?[0-9]+ \([0-9]+[a-z][0-9]+[a-z]\)')" "1"
check "23a: the render is exactly two lines (path line + line 2)" \
  "$(printf '%s\n' "$b5_out" | wc -l | tr -d ' ')" "2"
check "23a: the assembled line is structurally well-formed" \
  "$(burn_wellformed "$b5_line")" "yes"
check "23a: the whole line carries no emoji at all" \
  "$(burn_no_emoji "$b5_line")" "yes"
check "23a: none of the retired standalone lines survives (Ctx used: / Cost: / Session: \$)" \
  "$(printf '%s\n' "$b5_out" | grep -qE 'Ctx used:|Cost:|Session: \$' && echo present || echo absent)" "absent"

# --- 23b. The vanishing-separator rule --------------------------------------
# The Outputs clause: a group with no data is omitted WITH ITS SEPARATOR, so
# the line never shows a dangling │, a label with no number, or a leading or
# trailing separator. The two payload shapes the contract's Edge cases name by
# hand get their own cases first.

# 23b-i. No rate_limits at all -- an API-key, Bedrock or Vertex session, or a
#        Claude Code older than 2.1. Groups 3 AND 4 vanish together; 1 and 2
#        render. Anchored as a whole line (grep -x), because the strongest
#        statement of "they took their separators with them" is that there is
#        nothing after the ctx figure at all.
b5_norl=$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" "" "" 503 16)
b5_norl_line=$(burn_only "$b5_norl")
check "23b: no rate_limits → exactly the model and ctx groups, one separator, nothing after" \
  "$b5_norl_line" "$(b5_join "Opus max" "ctx 48%")"
check "23b: no rate_limits → no 5h group" \
  "$(printf '%s' "$b5_norl_line" | grep -qE '5h [0-9]' && echo present || echo absent)" "absent"
check "23b: no rate_limits → no wk group" \
  "$(printf '%s' "$b5_norl_line" | grep -qE 'wk [0-9]' && echo present || echo absent)" "absent"
check "23b: no rate_limits → line stays well-formed" \
  "$(burn_wellformed "$b5_norl_line")" "yes"

# 23b-ii. used_percentage present, resets_at absent. The contract is explicit
#         that the used figure renders and the trend AND countdown BOTH drop:
#         each needs the reset. Asserted on both windows, byte-exact, so a
#         leftover space or empty paren pair fails.
b5_5nores_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" 20 "" "" "" "" "")")
check "23b: five_hour without its reset → the used figure alone, no trend, no countdown" \
  "$b5_5nores_line" "$(b5_join "Opus max" "ctx 48%" "5h 20%")"
b5_7nores_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 62 "" "" "")")
check "23b: seven_day without its reset → the used figure alone, no trend, no countdown" \
  "$b5_7nores_line" "$(b5_join "Opus max" "ctx 48%" "wk 62%")"
check "23b: a window without its reset leaves no empty paren pair behind" \
  "$(printf '%s%s' "$b5_5nores_line" "$b5_7nores_line" | grep -qE '[()]' && echo present || echo absent)" "absent"
check "23b: a window without its reset leaves no trend arrow behind" \
  "$(printf '%s%s' "$b5_5nores_line" "$b5_7nores_line" | grep -qE '▲|▼' && echo present || echo absent)" "absent"

# 23b-iii/iv. One limit present, the other absent, both directions: three
#             groups, two separators, and the surviving limit keeps all three
#             of its figures.
b5_only5_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" 42 "$B5_R5_RESET" "" "" "" "")")
check "23b: five_hour present, seven_day absent → 5h renders, wk vanishes" \
  "$(printf '%s' "$b5_only5_line" | grep -qE '5h 42%' \
     && ! printf '%s' "$b5_only5_line" | grep -qE 'wk [0-9]' && echo yes || echo no)" "yes"
check "23b: five_hour present, seven_day absent → three groups, two separators" \
  "$(printf '%s' "$b5_only5_line" | grep -o '│' | wc -l | tr -d ' ')" "2"
check "23b: five_hour present, seven_day absent → line stays well-formed" \
  "$(burn_wellformed "$b5_only5_line")" "yes"

b5_only7_line=$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 42 "$B5_R7_RESET" "" "")")
check "23b: seven_day present, five_hour absent → wk renders, 5h vanishes" \
  "$(printf '%s' "$b5_only7_line" | grep -qE 'wk 42%' \
     && ! printf '%s' "$b5_only7_line" | grep -qE '5h [0-9]' && echo yes || echo no)" "yes"
check "23b: seven_day present, five_hour absent → three groups, two separators" \
  "$(printf '%s' "$b5_only7_line" | grep -o '│' | wc -l | tr -d ' ')" "2"
check "23b: seven_day present, five_hour absent → line stays well-formed" \
  "$(burn_wellformed "$b5_only7_line")" "yes"

# 23b-v. The LEADING separator, which only a vanished FIRST group can produce.
#        A payload with no model and no effort drops group 1, so the line must
#        begin at `ctx` with no separator in front of it.
b5_nomodel_line=$(burn_only "$(burn_json "$B5_WD" 145230 "" "" 42 "$B5_R5_RESET" "" "" "" "")")
check "23b: the model group vanishing leaves no leading separator" \
  "$(printf '%s' "$b5_nomodel_line" | grep -qE '^ctx 48% │ 5h 42%' && echo yes || echo no)" "yes"
check "23b: and that line is well-formed too" "$(burn_wellformed "$b5_nomodel_line")" "yes"

# 23b-vi. The TRAILING separator, which only a vanished LAST group can produce.
#         Group 4 absent leaves the line ending on the 5-hour countdown.
check "23b: the weekly group vanishing leaves no trailing separator" \
  "$(printf '%s' "$b5_only5_line" | grep -qE '│[[:space:]]*$' && echo present || echo absent)" "absent"

# 23b-vii. Every group empty: the function echoes the empty string and the
#          caller prints no line at all.
b5_empty_out=$(burn_render "$(burn_json "$B5_WD" "" "" "" "" "" "" "" "" "")")
check "23b: every group empty → the render is exactly one line (the path line)" \
  "$(printf '%s\n' "$b5_empty_out" | wc -l | tr -d ' ')" "1"
check "23b: every group empty → no line 2 at all" "$(burn_of "$b5_empty_out")" ""

# --- 23c. "Empty is not zero" -----------------------------------------------
# B04 sets each rate-limit variable to the empty string when its payload field
# is absent, never 0, because a 0 would render a real "0%" meter for a session
# that has no quota data at all. Each pair fails if the two are ever conflated,
# in either direction: an absent field and a genuine zero have OPPOSITE
# expected renders rather than merely different ones.
check "23c: a GENUINE zero five_hour renders a real 5h 0% meter" \
  "$(printf '%s' "$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" 0 "$B5_R5_RESET" "" "" "" "")")" \
     | grep -qE '5h 0%' && echo yes || echo no)" "yes"
check "23c: an ABSENT five_hour renders no 5h group at all" \
  "$(printf '%s' "$b5_only7_line" | grep -qE '5h [0-9]' && echo present || echo absent)" "absent"
check "23c: a GENUINE zero seven_day renders a real wk 0% meter" \
  "$(printf '%s' "$(burn_only "$(burn_json "$B5_WD" 145230 "Opus" "max" "" "" 0 "$B5_R7_RESET" "" "")")" \
     | grep -qE 'wk 0%' && echo yes || echo no)" "yes"
check "23c: an ABSENT seven_day renders no wk group at all" \
  "$(printf '%s' "$b5_only5_line" | grep -qE 'wk [0-9]' && echo present || echo absent)" "absent"

# --- 23d. The retirements, asserted on a payload that still carries them ----
# The +added/-removed segment, the %t figure and the %/d figure answer none of
# the seven glance-items and are cut. The fixture below is the one that can see
# it: a payload carrying real, non-zero line counts and both resets, so every
# retired figure has the data it used to render from. Absence here is a
# deletion; absence on an empty payload would prove nothing.
b5_retire_line="$b5_line"
check "23d: no +added/-removed segment, though the payload carries 503 and 16" \
  "$(printf '%s' "$b5_retire_line" | grep -qE '\+[0-9]+/-[0-9]+' && echo present || echo absent)" "absent"
check "23d: the literal counts from the payload appear nowhere on the line" \
  "$(printf '%s' "$b5_retire_line" | grep -qE '(\+503|-16)' && echo present || echo absent)" "absent"
check "23d: no %t figure survives" \
  "$(printf '%s' "$b5_retire_line" | grep -qF '%t' && echo present || echo absent)" "absent"
check "23d: no %/d figure survives" \
  "$(printf '%s' "$b5_retire_line" | grep -qF '%/d' && echo present || echo absent)" "absent"
# The only `%` signs left are the three the contract's example line shows: one
# per meter. Counted rather than pattern-matched, so a retired figure that came
# back in a new spelling still fails.
check "23d: exactly three % signs on the line -- ctx, 5h and wk, and nothing else" \
  "$(printf '%s' "$b5_retire_line" | grep -o '%' | wc -l | tr -d ' ')" "3"
# The counts are gone from the RENDER even on a payload where they are the only
# thing present besides the model, which is the shape that used to produce a
# counts-only session group.
check "23d: a payload with nothing but line counts renders no session-counts group" \
  "$(burn_only "$(burn_json "$B5_WD" "" "Opus" "" "" "" "" "" 503 16)")" "Opus"

# --- 23e. Context occupancy is not clamped ----------------------------------
# The Edge case: over 100% renders above 100 rather than clamping. This is the
# whole reason the plugin computes occupancy itself instead of reading a
# clamped figure from the payload.
check "23e: 350,000 tokens against a 300,000 window renders ctx 116%, not 100%" \
  "$(burn_only "$(burn_json "$B5_WD" 350000 "" "" "" "" "" "" "" "")")" "ctx 116%"

# --- 23f. The model group ----------------------------------------------------
# Glance-items 1 and 2 in one group: the name and the tier, in that order,
# separated by a single space and NOT by a separator -- they are one group, not
# two.
check "23f: model and effort are one group, space-separated, in that order" \
  "$(burn_only "$(burn_json "$B5_WD" "" "Fable 5" "high" "" "" "" "" "" "")")" "Fable 5 high"
check "23f: a model with no effort renders the name alone" \
  "$(burn_only "$(burn_json "$B5_WD" "" "Opus" "" "" "" "" "" "" "")")" "Opus"
# The Edge case: a parenthesised suffix is trimmed at " (" BEFORE colouring, so
# the group carries the short name and no stray parens.
check "23f: a parenthesised suffix is trimmed at ' (' -- 'Opus 5 (1M context)' → 'Opus 5'" \
  "$(burn_only "$(burn_json "$B5_WD" "" "Opus 5 (1M context)" "high" "" "" "" "" "" "")")" "Opus 5 high"
check "23f: no model and no effort → the group vanishes entirely" \
  "$(burn_only "$(burn_json "$B5_WD" 145230 "" "" "" "" "" "" "" "")")" "ctx 48%"

# --- 23g. Clean termination, at the byte level ------------------------------
# "echoes it as one string with no trailing newline": the line ends at its last
# visible byte, with the closing reset and nothing after it. Checked on the RAW
# render, since a stripped one cannot show a dangling opener.
b5_raw_full=$(burn_render_raw "$b5_full")
check "23g: the raw render ends in a reset, not in a colour opener" \
  "$(printf '%s' "$b5_raw_full" | grep -qa "$(printf '\033')\\[0m$" && echo yes || echo no)" "yes"
check "23g: every escape on line 2 is a complete SGR sequence (no truncated opener)" \
  "$(line_of "$b5_raw_full" 2 | sed -E "s/${ESC}\\[[0-9;]*m//g" | grep -c "$ESC" | tr -d ' ')" "0"

# --- 23h. The trends: B02's two functions, one per window -------------------
# The composition clause: burn_linear_trend for the 5-hour window,
# burn_week_trend for the weekly one. Both are bracketed over [t0, t1].
#
# Which function feeds which window is asserted by DISCRIMINATION, not by
# matching a number that both might produce: the fixture is checked first for
# the two functions genuinely disagreeing on it, so a renderer that used the
# linear trend for both windows -- the plausible simplification -- fails.
b5_tr_t0=$(date +%s)
b5_tr_line=$(burn_only "$(burn_json "$B5_WD" "" "" "" 40 "$B5_R5_RESET" 40 "$B5_R7_RESET" "" "")")
b5_tr_t1=$(date +%s)
b5_tr_ok=no
for (( _n = b5_tr_t0; _n <= b5_tr_t1; _n++ )); do
  [ "$b5_tr_line" = "$(b5_join "$(b5_five_group 40 "$B5_R5_RESET" "$_n")" \
                               "$(b5_week_group 40 "$B5_R7_RESET" "$_n")")" ] && b5_tr_ok=yes
done
check "23h: both limit groups render their own window's trend, byte for byte" "$b5_tr_ok" "yes"
check "23h: and the two functions genuinely disagree on this fixture, so that discriminates" \
  "$([ "$(burn_linear_trend 40 "$b5_tr_t0" "$B5_R7_RESET" 18000 2>/dev/null)" \
      != "$(burn_week_trend 40 "$b5_tr_t0" "$B5_R7_RESET" "$B5_MIDNIGHT" "$B5_WDAY" \
            "$B5_MASK" "$B5_SS" "$B5_ES" 2>/dev/null)" ] && echo yes || echo no)" "yes"
# The arrow is chosen by SIGN and carries B02's own signed number. A trend the
# helper reports as negative must render with ▼ and keep its minus, exactly as
# the contract's example line ("▼-25") shows.
b5_neg=$(burn_week_trend 5 "$B5_NOW" "$B5_R7_RESET" "$B5_MIDNIGHT" "$B5_WDAY" "$B5_MASK" "$B5_SS" "$B5_ES")
check "23h: the fixture for the sign test really is negative (not vacuous)" \
  "$(case "$b5_neg" in -*) echo yes ;; *) echo no ;; esac)" "yes"
check "23h: a negative trend renders as ▼ followed by the signed number" \
  "$(printf '%s' "$(burn_only "$(burn_json "$B5_WD" "" "" "" "" "" 5 "$B5_R7_RESET" "" "")")" \
     | grep -qF "▼$b5_neg" && echo yes || echo no)" "yes"
check "23h: and no ▲ appears on that line" \
  "$(printf '%s' "$(burn_only "$(burn_json "$B5_WD" "" "" "" "" "" 5 "$B5_R7_RESET" "" "")")" \
     | grep -qF '▲' && echo present || echo absent)" "absent"
# A used% far above the even-burn line takes the up arrow, so the sign test is
# pinned in both directions rather than only the one the example shows.
check "23h: a positive trend renders as ▲ followed by B02's unsigned number" \
  "$(printf '%s' "$(burn_only "$(burn_json "$B5_WD" "" "" "" "" "" 99 "$B5_R7_RESET" "" "")")" \
     | grep -qE '▲[0-9]+' && echo yes || echo no)" "yes"
# A trend that cannot be computed drops the trend ALONE: the Errors clause is
# that a component returning non-zero drops that figure, not its group. An
# unparseable reset is the shape that produces it while leaving the used% and
# the countdown's own input intact.
check "23h: an unparseable reset drops trend and countdown, never the used figure" \
  "$(burn_only "$(burn_json "$B5_WD" "" "" "" 20 '"not-an-epoch"' "" "" "" "")")" "5h 20%"

# --- 23i. The countdown ------------------------------------------------------
# B04's burn_reset_str, wrapped in parens, closing each limit group. Bracketed
# over [t0, t1] because burn_reset_str rolls a minute at a time.
b5_cd_t0=$(date +%s)
b5_cd_line=$(burn_only "$(burn_json "$B5_WD" "" "" "" 20 "$B5_R5_RESET" 30 "$B5_R7_RESET" "" "")")
b5_cd_t1=$(date +%s)
b5_cd5=no; b5_cd7=no
for (( _n = b5_cd_t0; _n <= b5_cd_t1; _n++ )); do
  printf '%s' "$b5_cd_line" | grep -qF "($(burn_reset_str "$B5_R5_RESET" "$_n"))" && b5_cd5=yes
  printf '%s' "$b5_cd_line" | grep -qF "($(burn_reset_str "$B5_R7_RESET" "$_n"))" && b5_cd7=yes
done
check "23i: the 5-hour group closes with B04's countdown in parens" "$b5_cd5" "yes"
check "23i: the weekly group closes with B04's countdown in parens" "$b5_cd7" "yes"
# A weekly reset three days out is exactly the shape B04's day band exists for,
# and the contract's example line shows it rendering as `2d4h`. Pinned as the
# band's SHAPE, since the hour part moves with the clock.
check "23i: a multi-day weekly countdown takes B04's day band (NdNh, no minutes)" \
  "$(printf '%s' "$b5_cd_line" | grep -qE '\([0-9]+d[0-9]+h\)' && echo yes || echo no)" "yes"
check "23i: each countdown is parenthesised exactly once, never doubled" \
  "$(printf '%s' "$b5_cd_line" | grep -o '(' | wc -l | tr -d ' ')" "2"

# --- 23j. Rate-limit figures are LIVE, never cached -------------------------
# The Invariants clause states this outright: they are server-side quota state
# and a stale one is worse than none. Two renders at the SAME cache key inside
# the TTL, differing only in their rate-limit figures -- the second must show
# its OWN numbers, while a segment that IS cached (the clam mode) still shows
# the first render's value, proving the bundle really was warm.
B5LIVE_WD="$TMPROOT/b5-live-wd"; mk_wt "$B5LIVE_WD"
printf 'Build\n' > "$B5LIVE_WD/.local/MODE"
B5LIVE_CACHE="$TMPROOT/b5-live-cache"
b5_live_render() { # json
  printf '%s' "$1" \
    | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$B5LIVE_CACHE" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=300 \
        bash "$CONTEXT" 2>/dev/null | sed -E "s/${ESC}\\[[0-9;]*m//g"
}
b5_live_render "$(burn_json "$B5LIVE_WD" 145230 "Opus" "max" 11 "$B5_R5_RESET" 21 "$B5_R7_RESET" "" "")" >/dev/null
printf 'Ship\n' > "$B5LIVE_WD/.local/MODE"
b5_live2=$(b5_live_render "$(burn_json "$B5LIVE_WD" 145230 "Opus" "max" 77 "$B5_R5_RESET" 88 "$B5_R7_RESET" "" "")")
check "23j: the second render really was served warm (the cached mode still reads Build)" \
  "$(mode_cached_value "$b5_live2" "Build")" "yes"
check "23j: yet the 5-hour figure is the warm render's OWN, not the cached one" \
  "$(printf '%s' "$(burn_of "$b5_live2")" | grep -qE '5h 77%' && echo yes || echo no)" "yes"
check "23j: and so is the weekly figure" \
  "$(printf '%s' "$(burn_of "$b5_live2")" | grep -qE 'wk 88%' && echo yes || echo no)" "yes"
check "23j: neither of the first render's figures survives anywhere on the warm line" \
  "$(printf '%s' "$(burn_of "$b5_live2")" | grep -qE '(5h 11%|wk 21%)' && echo present || echo absent)" "absent"

# --- 23k. The warm-render process budget does not move ----------------------
# The Invariants clause, measured through the PATH-shim harness on a payload
# that exercises BOTH limit groups -- the only payload on which the budget is
# meaningful, since a payload with no rate_limits runs neither trend.
#
# Each sub-limit is asserted separately as well as the total: a renderer that
# spent a spare `date` and saved an `awk` would sit under 12 in total while
# breaking the clause that names them individually. burn_linear_trend forks
# NOTHING (B02's own invariant), so the 5-hour trend is not one of the two awk.
B5BUD_DIR="$TMPROOT/b5-budget-cache"
B5BUD_WD="$TMPROOT/b5-budget-wd"; mk_wt "$B5BUD_WD"
printf 'Build\n' > "$B5BUD_WD/.local/MODE"
b5bud_json=$(burn_json "$B5BUD_WD" 145230 "Opus" "max" 42 "$B5_R5_RESET" 62 "$B5_R7_RESET" 503 16)
render_shim "$b5bud_json" "$B5BUD_DIR" 300     # cold: seeds the bundle
render_shim "$b5bud_json" "$B5BUD_DIR" 300     # warm: same key, inside the TTL
b5bud_total=$(shim_count "$SHIM_LOG")
check "23k: the warm render still invokes at most 12 external commands in total" \
  "$([ "${b5bud_total:-99}" -le 12 ] && echo yes || echo no)" "yes"
check "23k: exactly one jq, over stdin" \
  "$(shim_count "$SHIM_LOG" jq)" "1"
check "23k: at most two date" \
  "$([ "$(shim_count "$SHIM_LOG" date)" -le 2 ] && echo yes || echo no)" "yes"
check "23k: at most two awk" \
  "$([ "$(shim_count "$SHIM_LOG" awk)" -le 2 ] && echo yes || echo no)" "yes"
check "23k: no git" "$(shim_count "$SHIM_LOG" git)" "0"
check "23k: no ccost.sh -- which is also the only transcript reader, so nothing under CLAUDE_PROJECTS_DIR is opened" \
  "$(shim_count "$CCOST_LOG_FILE")" "0"
check "23k: and the sentinel CLAUDE_PROJECTS_DIR is still empty after the warm render" \
  "$(find "$SENTINEL_PROJECTS_DIR" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" "0"
# Non-vacuity: the measurement really observed a render that produced the full
# four-group line, so a budget met by rendering nothing would not pass.
check "23k: the budget was measured on a render that really produced all four groups" \
  "$(printf '%s' "$(burn_only "$b5bud_json")" | grep -o '│' | wc -l | tr -d ' ')" "3"

# --- 23l. Degradation never fails the render --------------------------------
# The Errors clause and the last Edge case: an install missing a burnrate
# library renders the groups that do not need it, exits 0, writes nothing to
# stderr, and leaves no partial escape sequence.
B5DEG="$TMPROOT/b5-degraded"; mkdir -p "$B5DEG/scripts" "$B5DEG/lib"
ln -s "$CONTEXT" "$B5DEG/scripts/context.sh"
for _f in platform.sh states.sh states.tsv; do
  ln -s "$SCRIPT_DIR/../lib/$_f" "$B5DEG/lib/$_f"
done
unset _f
b5_deg_out="$TMPROOT/b5-deg.out"; b5_deg_err="$TMPROOT/b5-deg.err"
printf '%s' "$b5_full" \
  | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
      CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/b5-deg-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
      bash "$B5DEG/scripts/context.sh" > "$b5_deg_out" 2>"$b5_deg_err"
b5_deg_ec=$?
b5_deg_line=$(printf '%s' "$(line_of "$(<"$b5_deg_out")" 2)" | sed -E "s/${ESC}\\[[0-9;]*m//g")
check "23l: no burnrate libraries → the render still exits 0" "$b5_deg_ec" "0"
check "23l: no burnrate libraries → nothing is written to stderr" \
  "$(wc -c < "$b5_deg_err" | tr -d ' ')" "0"
check "23l: no burnrate libraries → no diagnostic text reaches stdout" \
  "$(grep -qiE 'command not found|no such file|syntax error' "$b5_deg_out" && echo present || echo absent)" "absent"
check "23l: no burnrate libraries → the groups that need no library still render" \
  "$(printf '%s' "$b5_deg_line" | grep -qE 'Opus max' && printf '%s' "$b5_deg_line" | grep -qE 'ctx 48%' \
     && echo yes || echo no)" "yes"
check "23l: no burnrate libraries → the used figures still render (they need no library)" \
  "$(printf '%s' "$b5_deg_line" | grep -qE '5h 1%' && printf '%s' "$b5_deg_line" | grep -qE 'wk 62%' \
     && echo yes || echo no)" "yes"
check "23l: no burnrate libraries → no trend arrow, since B02 is absent" \
  "$(printf '%s' "$b5_deg_line" | grep -qE '▲|▼' && echo present || echo absent)" "absent"
check "23l: no burnrate libraries → the countdown drops WITH its parens, leaving no empty pair" \
  "$(printf '%s' "$b5_deg_line" | grep -qE '[()]' && echo present || echo absent)" "absent"
check "23l: no burnrate libraries → the line stays well-formed" \
  "$(burn_wellformed "$b5_deg_line")" "yes"
check "23l: no burnrate libraries → not one 256-colour sequence survives" \
  "$(line_of "$(<"$b5_deg_out")" 2 | grep -c '38;5;' | tr -d ' ')" "0"

# --- 23m. The three schedule knobs ------------------------------------------
# CLAM_STATUSLINE_WORK_DAYS / _DAY_START / _DAY_END, all consumed by the WEEKLY
# trend and only by it -- the 5-hour window has no working-week notion, which
# is the contract's own reasoning for burn_linear_trend.
#
# Expectations are derived through burn_work_parse, which owns the fallback
# rules, rather than restated here. What is under test is that the renderer
# passes the knob's value through to it at all.
B5_KNOB_USED=55
b5_knob=$(burn_json "$B5_WD" "" "" "" "" "" "$B5_KNOB_USED" "$B5_R7_RESET" "" "")

# The knobs must MATTER: a 24/7 schedule and the default working week produce
# different expected trends on this fixture, so every case below discriminates.
b5_knob_t0=$(date +%s)
check "23m: the default schedule and a 24/7 one really differ here, so these cases discriminate" \
  "$([ "$(b5_week_group "$B5_KNOB_USED" "$B5_R7_RESET" "$b5_knob_t0")" \
      != "$(b5_week_group "$B5_KNOB_USED" "$B5_R7_RESET" "$b5_knob_t0" "1-7" 0 24)" ] \
     && echo yes || echo no)" "yes"

# b5_knob_case(label, expected_days, expected_start, expected_end, env...):
# render with the given env and compare the weekly group against the group
# burn_work_parse's own normalization of the EXPECTED schedule produces,
# bracketed over the render interval.
b5_knob_case() { # label days start end env...
  local label="$1" d="$2" s="$3" e="$4"; shift 4
  local t0 t1 line ok=no _n
  t0=$(date +%s)
  line=$(burn_only "$b5_knob" "$@")
  t1=$(date +%s)
  for (( _n = t0; _n <= t1; _n++ )); do
    [ "$line" = "$(b5_week_group "$B5_KNOB_USED" "$B5_R7_RESET" "$_n" "$d" "$s" "$e")" ] && ok=yes
  done
  check "23m: $label" "$ok" "yes"
}

b5_knob_case "no knobs set → the default 1-5 / 8 / 18 working week" "1-5" 8 18
b5_knob_case "CLAM_STATUSLINE_WORK_DAYS=1-7 is consumed" "1-7" 8 18 "CLAM_STATUSLINE_WORK_DAYS=1-7"
b5_knob_case "CLAM_STATUSLINE_DAY_START=6 is consumed" "1-5" 6 18 "CLAM_STATUSLINE_DAY_START=6"
b5_knob_case "CLAM_STATUSLINE_DAY_END=22 is consumed" "1-5" 8 22 "CLAM_STATUSLINE_DAY_END=22"
b5_knob_case "all three together are consumed" "1-7" 0 24 \
  "CLAM_STATUSLINE_WORK_DAYS=1-7" "CLAM_STATUSLINE_DAY_START=0" "CLAM_STATUSLINE_DAY_END=24"

# Each bad value falls back to ITS OWN default, not to a whole default set: the
# two surviving knobs still take effect alongside the rejected one.
b5_knob_case "a non-integer DAY_START falls back to 8, and the OTHER knobs still apply" "1-5" 8 22 \
  "CLAM_STATUSLINE_DAY_START=half-past" "CLAM_STATUSLINE_DAY_END=22"
b5_knob_case "an out-of-range DAY_START (99) falls back to 8" "1-5" 8 18 \
  "CLAM_STATUSLINE_DAY_START=99"
b5_knob_case "an unusable WORK_DAYS ('weekdays') falls back to 1-5" "1-5" 6 18 \
  "CLAM_STATUSLINE_WORK_DAYS=weekdays" "CLAM_STATUSLINE_DAY_START=6"
# DAY_END at or below DAY_START falls back to the DEFAULT PAIR rather than
# yielding a negative window -- the contract names this case specifically, and
# it is the one fallback that is not per-knob.
b5_knob_case "DAY_END below DAY_START falls back to the default 8/18 PAIR" "1-5" 8 18 \
  "CLAM_STATUSLINE_DAY_START=18" "CLAM_STATUSLINE_DAY_END=9"
b5_knob_case "DAY_END equal to DAY_START falls back to the default 8/18 PAIR" "1-5" 8 18 \
  "CLAM_STATUSLINE_DAY_START=10" "CLAM_STATUSLINE_DAY_END=10"
# Zero-padded values are DECIMAL. "08" is a correctly written hour, and the 10#
# forcing that guarantees it is load-bearing: without it bash reads 08 as an
# invalid octal literal and the arithmetic fails outright.
b5_knob_case "a zero-padded DAY_START ('08') is decimal 8, not an octal error" "1-5" 8 18 \
  "CLAM_STATUSLINE_DAY_START=08"
b5_knob_case "a zero-padded DAY_END ('09') is decimal 9, not an octal error" "1-5" 8 9 \
  "CLAM_STATUSLINE_DAY_START=08" "CLAM_STATUSLINE_DAY_END=09"
# Every knob unusable at once: the line still renders and stays well-formed,
# which is the Errors clause ("never fails the render") applied to the knobs.
check "23m: every knob unusable at once still renders a well-formed line" \
  "$(burn_wellformed "$(burn_only "$b5_knob" "CLAM_STATUSLINE_WORK_DAYS=all" \
      "CLAM_STATUSLINE_DAY_START=dawn" "CLAM_STATUSLINE_DAY_END=dusk")")" "yes"
# The 5-hour window is untouched by all three: its trend is plain wall clock.
b5_5only=$(burn_json "$B5_WD" "" "" "" 42 "$B5_R5_RESET" "" "" "" "")
check "23m: the schedule knobs do not move the 5-hour group at all" \
  "$([ "$(burn_only "$b5_5only" "CLAM_STATUSLINE_WORK_DAYS=1-7" "CLAM_STATUSLINE_DAY_START=0" \
          "CLAM_STATUSLINE_DAY_END=24")" = "$(burn_only "$b5_5only")" ] && echo yes || echo no)" "yes"

# --- 23n. The group separator is a DIM │ ------------------------------------
# The one escape the contract still allows to be typed in the renderer, and the
# exact bytes it must be: SGR 2, the box-drawing bar, then a reset.
b5_sep_raw=$(line_of "$(burn_render_raw "$b5_full")" 2)
check "23n: the separator is exactly \\033[2m│\\033[0m, three times over" \
  "$(printf '%s' "$b5_sep_raw" | grep -oaF "$(printf '\033[2m│\033[0m')" | wc -l | tr -d ' ')" "3"
check "23n: no separator is left undimmed" \
  "$(printf '%s' "$b5_sep_raw" | grep -oaF '│' | wc -l | tr -d ' ')" "3"

# --- 23o. Integer figures, and the float that must not disagree -------------
# The Edge case: a float used_percentage prints its INTEGER PART -- the same
# value the colour threshold reads, so the two can never disagree at a
# boundary. Truncation, not rounding: 14.9 renders 14 and takes 14's band.
check "23o: a float five_hour (14.000000000000002) renders as 14%" \
  "$(printf '%s' "$(burn_only "$(burn_json "$B5_WD" "" "" "" 14.000000000000002 "" "" "" "" "")")" \
     | grep -qE '^5h 14%$' && echo yes || echo no)" "yes"
check "23o: a float weekly (23.5) renders as 23%, truncated rather than rounded up" \
  "$(burn_only "$(burn_json "$B5_WD" "" "" "" "" "" 23.5 "" "" "")")" "wk 23%"
check "23o: no fractional part reaches the line" \
  "$(printf '%s' "$(burn_only "$(burn_json "$B5_WD" "" "" "" 14.9 "" 23.5 "" "" "")")" \
     | grep -qE '[0-9]\.[0-9]' && echo present || echo absent)" "absent"

# --- 23p. The line's alphabet -----------------------------------------------
# No emoji anywhere, on any payload shape. The three ambiguous-width symbols
# the line DOES keep -- the separator and the two trend arrows -- are the only
# non-ASCII characters left once that holds, which is what makes this a
# whole-alphabet check rather than a list of the glyphs that were removed.
for b5_alpha in "$b5_line" "$b5_norl_line" "$b5_only5_line" "$b5_only7_line" "$b5_cd_line"; do
  check "23p: no emoji on the line '$b5_alpha'" "$(burn_no_emoji "$b5_alpha")" "yes"
done
unset b5_alpha


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
# The badge numbers are wrapped in an OSC 8 hyperlink, whose opening sequence
# sits BETWEEN the tag and the "#123" it labels. Strip those, so the badge run
# can be read as the plain text a terminal displays. EITHER terminator, via the
# shared OSC8_RE near the top of this file: the clause these badge assertions
# state is "the hyperlink wraps the number alone", never "the terminator is
# ST", so B07 moving osc8_link from ST to BEL must not be able to make this
# helper silently strip nothing.
osc8_strip() { # text
  printf '%s' "$1" | sed -E "$OSC8_RE"
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
# The \a below is the BEL terminator B07 moves osc8_link onto, replacing the ST
# (ESC backslash) this literal carried before it. Same clause, same shape: the
# sequence opens immediately before "#101" and closes immediately after it, with
# nothing else inside the link.
check "25b: the OSC-8 hyperlink still wraps the number alone" \
  "$(printf '%s' "$b10_act_raw" \
     | grep -qaF "$(printf '\033]8;;https://x.test/101\a#101\033]8;;\a')" \
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

# === 26. Colour wiring: which helper the renderer asks for each value =======
# Contract: B05's Invariants clause -- "every colour comes from
# lib/burn-theme.sh; a hand-typed 38;5; sequence in this function is a bug; the
# two exceptions remain the dim group separator and the closing reset" -- and
# the ctx-meter clause it inherits verbatim from B16 (plan
# 003-statusline-meter-colour): the meter keeps this plugin's non-saturating
# occupancy math and its .ctx-status.json publish unchanged.
#
# Nothing here re-tests a threshold: every band is burn-theme.sh's clause, with
# its own accepted suite. What is tested here is what only a rendered line can
# show -- which helper the renderer ASKS for each value, where the sequence it
# returns opens and closes, and that the line's shape is otherwise untouched.
#
# That distinction is why #306's regression test lives in this section and
# nowhere else. burn_ctx_color maps occupancy to colour correctly in
# burn-theme.sh and always has; the defect was that the renderer asked
# burn_ctx_state -- the session-STALENESS tri-state -- for the ctx meter's
# colour, so the meter read green at every occupancy. No assertion inside
# burn-theme.sh can see that. 26b is the one that can.
#
# B05 changes WHICH wirings exist, not the standard they are held to: the
# +added/-removed pair and burn_diff_color are retired outright (26e is deleted
# with them), the trend appears in BOTH limit groups rather than only the
# weekly one, and the countdown likewise. Expected values are still DERIVED by
# calling B03's helpers rather than written out as escape codes.
#
# B17 plain-used-percent (plan 003) narrows that last sentence in one place and
# one only: the `5h N%` and `wk N%` tokens are no longer coloured, so their
# expectations are written out as PLAIN TEXT. There is no helper left to derive
# them from -- B16 deletes burn_plan_color outright -- and an expectation that
# still called it would stop this whole suite at collection the moment that
# deletion lands. Every other expectation here keeps deriving its colour from
# the theme library, burn_trend_color included: B16 rescales that function, and
# its bands are B16's suite's clause, not this one's. What this section owns is
# the WIRING -- which helper the renderer asks for each value, where the
# sequence it returns opens and closes, and that the two used% tokens ask for
# nothing at all.

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
# neither rate limit carries a reset, so there is no trend and no countdown.
# What is left is exactly reproducible. The two figures that do move are pinned
# byte for byte too, in 26d and 26f, bracketed over the render interval the way
# section 23 brackets them.
#
# B05 makes the MODEL group part of this equality for the first time: B03's
# burn_model_color is flat, so a model name no longer moves between renders and
# no longer has to be excluded from a byte-exact expectation.
b16_static_json=$(burn_json "$B5_WD" 145230 "Opus" "max" 1 "" 62 "" 503 16)
b16_static_raw=$(b16_raw_line "$b16_static_json")
b16_static_expected=$(b16_join \
  "$(burn_model_color Opus)Opus$B16_RST $(burn_effort_color max)max$B16_RST" \
  "$(burn_ctx_color 48)ctx 48%$B16_RST" \
  "5h 1%" \
  "wk 62%")
check "26a: the whole four-group line is byte-identical to the assembled expectation, SGR included" \
  "$b16_static_raw" "$b16_static_expected"
check "26a: and its ANSI-stripped text is exactly the four groups in contract order" \
  "$(burn_of "$(burn_render "$b16_static_json")")" "Opus max │ ctx 48% │ 5h 1% │ wk 62%"

# Without this, the equality above would pass just as happily against a renderer
# that still sourced the ctx colour from the staleness tier -- if the two
# happened to agree on this payload. At 48% occupancy and zero idle they do not.
check "26a: the occupancy band and the staleness tier genuinely disagree here, so that equality discriminates" \
  "$([ "$(burn_ctx_color 48)" \
      != "$(printf '\033[38;5;%sm' "$(burn_ctx_state 145230 300000 0 | awk '{print $2}')")" ] \
     && echo yes || echo no)" "yes"

# The model group is TWO colours, not one: B03's flat family colour for the
# name and burn_effort_color for the tier, each closed before the next opens.
# Byte-exact on that group alone, since a single sequence spanning both would
# still produce the right stripped text.
check "26a: the model name and the effort tier carry their own colours, each closed" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "Fable 5" "high" "" "" "" "" "" "")")" \
  "$(burn_model_color "Fable 5")Fable 5$B16_RST $(burn_effort_color high)high$B16_RST"
# And the family colour is asked for with the TRIMMED name: the parenthesised
# suffix is cut before colouring, not after.
check "26a: the family colour is chosen from the trimmed name, not the raw display name" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "Opus 5 (1M context)" "" "" "" "" "" "" "")")" \
  "$(burn_model_color "Opus 5")Opus 5$B16_RST"
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

# --- 26d. Both limit groups' trends: B14's colour, the renderer's arrow -----
# The arrow STAYS. B14's +/-3 dead band is expressed as the green tier and the
# upstream's on-track glyph is deliberately not adopted (26g pins its absence),
# so `▲`/`▼` are still chosen here, by the same sign test, and the colour comes
# from burn_trend_color.
#
# B05 puts a trend in BOTH limit groups, from two different B02 functions, so
# the wiring is asserted on both -- a renderer that coloured only the weekly one
# would have passed the pre-B05 version of this case.
b16_tr_t0=$(date +%s)
b16_tr_raw=$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" 40 "$B5_R5_RESET" 40 "$B5_R7_RESET" "" "")")
b16_tr_t1=$(date +%s)

# b16_group_raw(kind used reset now): the raw bytes of a limit group, built from
# B02/B03/B04 exactly as the contract composes them -- the PLAIN label and
# figure (B17: no opener, no reset), then burn_trend_color over arrow and
# number, then the dimmed countdown with its parens INSIDE the dim sequence.
#
# The used% token is the one part of this builder written out as literal text
# rather than derived: after B16 there is no function to derive it from, and
# that is the point of B17 rather than an approximation of it.
b16_group_raw() { # kind used reset now
  local g t cd
  g="$1 ${2%%.*}%"
  if [ "$1" = "5h" ]; then
    t=$(burn_linear_trend "$2" "$4" "$3" 18000 2>/dev/null)
  else
    t=$(burn_week_trend "$2" "$4" "$3" "$B5_MIDNIGHT" "$B5_WDAY" "$B5_MASK" "$B5_SS" "$B5_ES" 2>/dev/null)
  fi
  [ -n "$t" ] && g="$g $(burn_trend_color "$t")$(b5_trend_token "$t")$B16_RST"
  cd=$(burn_reset_str "$3" "$4" 2>/dev/null) && g="$g $(burn_countdown_color)($cd)$B16_RST"
  printf '%s' "$g"
}

b16_tr_ok=no
for (( _n = b16_tr_t0; _n <= b16_tr_t1; _n++ )); do
  [ "$b16_tr_raw" = "$(b16_join "$(b16_group_raw 5h 40 "$B5_R5_RESET" "$_n")" \
                                "$(b16_group_raw wk 40 "$B5_R7_RESET" "$_n")")" ] && b16_tr_ok=yes
done
check "26d: both limit groups render byte for byte -- plain used%, trend colour, dimmed countdown" \
  "$b16_tr_ok" "yes"
# The trend IS coloured while the used% beside it is not. Asserted on a fixture
# where the trend's opener is genuinely non-empty, so the equality above cannot
# pass by every sequence on the group having gone missing together.
b16_tr_val=$(burn_linear_trend 40 "$b16_tr_t0" "$B5_R5_RESET" 18000)
check "26d: the trend fixture really is computable (not vacuous)" \
  "$([ -n "$b16_tr_val" ] && echo yes || echo no)" "yes"
check "26d: and this trend really does carry a colour, so the equality discriminates" \
  "$([ -n "$(burn_trend_color "$b16_tr_val")" ] && echo yes || echo no)" "yes"
# The other half of the same statement: the used% token on that very line opens
# the group with no sequence at all in front of it.
check "26d: the five-hour group opens on a plain used% token, no opener before the label" \
  "$(case "$b16_tr_raw" in "5h 40% "*) echo yes ;; *) echo no ;; esac)" "yes"

# --- 26f. The countdown dims WITH its parens --------------------------------
# `($countdown)` entire, not `(` + dim + `)`: the whole subordinate clause dims
# together so the eye reaches `5h 20%` first. Bracketed over [t0,t1] for
# burn_reset_str's minute roll, as 23i is.
b16_cd_t0=$(date +%s)
b16_cd_raw=$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" 20 "$B5_R5_RESET" "" "" "" "")")
b16_cd_t1=$(date +%s)
b16_cd_ok=no
b16_cd_openparen=no
for (( _n = b16_cd_t0; _n <= b16_cd_t1; _n++ )); do
  _cd=$(burn_reset_str "$B5_R5_RESET" "$_n")
  [ "$b16_cd_raw" = "$(b16_group_raw 5h 20 "$B5_R5_RESET" "$_n")" ] && b16_cd_ok=yes
  printf '%s' "$b16_cd_raw" | grep -qaF "($(burn_countdown_color)$_cd" && b16_cd_openparen=yes
done
check "26f: the five-hour group renders byte for byte, the countdown dimmed WITH its parens" \
  "$b16_cd_ok" "yes"
check "26f: the opening paren is not left outside the dim sequence" "$b16_cd_openparen" "no"
# A missing reset drops the countdown and its parens together -- and now the
# colour that wrapped them too, since an opener left behind by a segment that
# did not render is exactly the leak the closing-reset convention exists to
# stop. Byte-exact on the whole line, so a leftover dim opener shows up.
# Under B17 that leaves a line of PURE TEXT: the used% token carries no
# sequence of its own, so a single stray escape byte anywhere on it fails this.
check "26f: five_hour without its reset renders the meter alone, no leftover dim opener" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" 20 "" "" "" "" "")")" \
  "5h 20%"
# An UNPARSEABLE reset (a JSON string where an epoch belongs) takes the same
# path: trend, countdown, parens and colour all drop together.
check "26f: an unparseable reset drops the countdown, its parens and its colour alike" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" 20 '"not-an-epoch"' "" "" "" "")")" \
  "5h 20%"
# --- 26g. No hand-typed 38;5; survives in sl_render_burn_line ---------------
# The contract states this outright in its Invariants: every colour comes from
# lib/burn-theme.sh, the two exceptions being the dim separator and the closing
# reset. Any `${esc}[38;5;Nm` typed into this function is a colour decision made
# in the renderer instead of in burn-theme.sh. It is the cheapest check in this
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
# The retired helpers are not called from here either. A call left behind would
# fail at run time once the function is deleted from burn-theme.sh, and this is
# the assertion that names the retirement rather than waiting for the crash.
for b16_retired in burn_rainbow burn_model_style burn_frame_advance burn_diff_color \
                   burn_metrics burn_awake_seconds burn_day_start_epoch burn_tick_frac; do
  check "26g: sl_render_burn_line no longer calls $b16_retired" \
    "$(printf '%s\n' "$b16_fn_body" | grep -qF "$b16_retired" && echo present || echo absent)" "absent"
done
unset b16_retired
# --- 26h. Degradation: lib/burn-theme.sh absent from the install ------------
# 23l covers an install missing ALL the burnrate libraries, which leaves the
# line with no derived figures at all. This clause is narrower and sharper:
# burn-math present, burn-theme absent, so every FIGURE still computes and only
# colour is gone. That is the install whose line must come out as an uncoloured
# render -- no partial sequence, no colour picked locally as a fallback,
# nothing broken.
B16NOTHEME="$TMPROOT/b16-notheme"; mkdir -p "$B16NOTHEME/scripts" "$B16NOTHEME/lib"
ln -s "$CONTEXT" "$B16NOTHEME/scripts/context.sh"
for _f in platform.sh states.sh states.tsv burn-math.sh; do
  ln -s "$SCRIPT_DIR/../lib/$_f" "$B16NOTHEME/lib/$_f"
done
unset _f

b16_deg_render() { # json outfile errfile cachedir
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
  "$(b16_strip "$b16_deg_raw")" "Opus max │ ctx 48% │ 5h 1% │ wk 62%"
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
# static fixture omits are in play. Both trends are B01/B02's, so they still
# render and must render UNCOLOURED. The countdown is not: burn_reset_str lives
# in the missing file too, so it drops -- and the clause that matters is that it
# takes its parens with it exactly as an absent reset does, rather than leaving
# the empty `()` the contract forbids or a dim opener with nothing behind it.
b16_deg2_out="$TMPROOT/b16-deg2.out"
b16_deg_render "$(burn_json "$B5_WD" 145230 "Opus" "max" 1 "$B5_R5_RESET" 62 "$B5_R7_RESET" 503 16)" \
  "$b16_deg2_out" "$b16_deg_err" "$TMPROOT/b16-deg2-cache"
b16_deg2_raw=$(line_of "$(<"$b16_deg2_out")" 2)
b16_deg2_line=$(b16_strip "$b16_deg2_raw")
check "26h: burn-theme absent -> both trend arrows and magnitudes still render" \
  "$(printf '%s' "$b16_deg2_line" | grep -cE '(▲|▼)-?[0-9]+')" "1"
check "26h: burn-theme absent -> the countdown drops with its parens, leaving no empty pair" \
  "$(printf '%s' "$b16_deg2_line" | grep -qE '[()]' && echo present || echo absent)" "absent"
check "26h: burn-theme absent -> and both meters themselves still render" \
  "$(printf '%s' "$b16_deg2_line" | grep -qE '5h 1%' \
     && printf '%s' "$b16_deg2_line" | grep -qE 'wk 62%' && echo yes || echo no)" "yes"
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
# count and the vanishing separators (23a/23b), the omission rules (23b), the
# integer truncation of r5 and r7 (23o), the one string with no trailing
# newline (23g), and the warm-render process budget (23k) -- which no colour
# helper can move, since every one of them is pure bash builtins and forks
# nothing. What is added here is the same statement made against the COLOURED
# line, where a sequence wrapped around the wrong span changes the shape
# without changing a byte of the stripped text.
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

# --- 26j. lib/burn-tick.sh is retired outright ------------------------------
# B05 line2-groups (plan 001-statusline-glance-uplift) RETIRES lib/burn-tick.sh
# "and its test". The sub-tick interpolator existed to smooth the %t figure
# between renders; B05 deletes %t, so the interpolator has no consumer and the
# whole file goes with it. Its own assertions -- the state file, the
# anchor/calibration/read paths, the clamps, the awk-fork budget -- are not
# relaxed and not moved: a test for a deleted function cannot be kept honestly.
# What is left that can still be true or false about that file is its ABSENCE,
# and these checks live here, beside 26g, which already asserts that
# sl_render_burn_line no longer calls burn_tick_frac.
b16_tick_root="$SCRIPT_DIR/.."
check "26j: lib/burn-tick.sh is retired and no longer present" \
  "$([ -e "$b16_tick_root/lib/burn-tick.sh" ] && echo present || echo absent)" "absent"
# The retirement is not a rename: no shipped CODE may source the file or call
# burn_tick_frac, or deleting it would break the render rather than simplify
# it. Scoped to the plugin's shell sources, with two exclusions that are about
# what the check MEANS rather than about making it pass:
#   - comment lines, for the same reason burn-theme's scans exclude them --
#     several docblocks NAME the retired file in order to record that it is
#     gone, and a check that fired on the prose describing a deletion would be
#     a check on the wrong text;
#   - *.test.sh, because a test that asserts the retirement has to be able to
#     spell the retired name (26g enumerates exactly these names to assert the
#     renderer no longer calls them).
b16_tick_scanned=0
b16_tick_refs=""
for b16_tick_f in "$b16_tick_root"/lib/*.sh "$b16_tick_root"/scripts/*.sh; do
  case "$b16_tick_f" in *.test.sh) continue ;; esac
  [ "$b16_tick_f" = "$b16_tick_root/lib/burn-tick.sh" ] && continue
  [ -f "$b16_tick_f" ] || continue
  b16_tick_scanned=$((b16_tick_scanned + 1))
  grep -vE '^[[:space:]]*#' "$b16_tick_f" 2>/dev/null \
    | grep -qE 'burn-tick\.sh|burn_tick_frac' \
    && b16_tick_refs="$b16_tick_refs ${b16_tick_f##*/}"
done
# An absence check over an empty file list passes for free, so pin that the
# scan really walked the plugin's shell sources.
check "26j: the retirement scan really sees the plugin's shell sources (not vacuous)" \
  "$([ "$b16_tick_scanned" -gt 0 ] && echo yes || echo no)" "yes"
check "26j: no shipped file in the plugin still sources burn-tick.sh or calls burn_tick_frac" \
  "${b16_tick_refs# }" ""
unset b16_tick_root b16_tick_scanned b16_tick_refs b16_tick_f

# --- 26k. B17 plain-used-percent (plan 003-angry-pace-colours) --------------
# Contract: the `Contract: B17 plain-used-percent` docblock above group 3 in
# sl_render_burn_line. `5h N%` and `wk N%` render PLAIN -- no colour opener and
# no reset -- in BOTH limit groups, because a high used figure late in a window
# is information, not an alarm. Everything else on those two groups is wired
# exactly as it is today: the arrows still take burn_trend_color's opener and
# the caller's reset, the countdowns still dim.
#
# 26a, 26d and 26f already state this byte for byte as part of whole-line
# equalities. What this clause adds is the same statement made in the form that
# NAMES it, so a regression here reads "the used% token got a colour back"
# rather than "the line moved". Each case below is deliberately narrow enough
# that only that one token can fail it.

# i. The plain token, in both groups, on the static four-group fixture. Grepped
#    for as a LITERAL run of bytes running separator-to-separator, so any
#    sequence introduced on either side of the figure breaks the match -- an
#    opener before `5h`, a reset after `1%`, or a colour wrapped round the
#    label alone.
check "26k: the five-hour used% sits between its separators with no sequence on either side" \
  "$(printf '%s' "$b16_static_raw" | grep -qaF "$B16_SEP 5h 1% $B16_SEP" && echo yes || echo no)" "yes"
check "26k: the weekly used% likewise, and it closes the line with no trailing reset" \
  "$(case "$b16_static_raw" in *"$B16_SEP wk 62%") echo yes ;; *) echo no ;; esac)" "yes"
# And said the other way round, so a renderer that merely moved the sequence
# elsewhere on the group cannot pass: no escape byte at all falls inside the
# span the two figures occupy.
b17_used5=${b16_static_raw#*"$B16_SEP 5h"}; b17_used5=${b17_used5%%"$B16_SEP"*}
b17_used7=${b16_static_raw##*"$B16_SEP wk"}
check "26k: not one escape byte falls inside the five-hour group's used% span" \
  "$(printf '%s' "$b17_used5" | grep -c "$ESC" | tr -d ' ')" "0"
check "26k: nor inside the weekly group's" \
  "$(printf '%s' "$b17_used7" | grep -c "$ESC" | tr -d ' ')" "0"
unset b17_used5 b17_used7

# ii. The call site is gone, not merely its output. burn_plan_color is deleted
#     by B16, so a reference left behind in this function would fail at run
#     time; 26g makes exactly this statement about the helpers B05 retired, and
#     this is the same statement for the helper plan 003 retires.
check "26k: sl_render_burn_line no longer calls burn_plan_color" \
  "$(printf '%s\n' "$b16_fn_body" | grep -qF 'burn_plan_color' && echo present || echo absent)" "absent"
# Not vacuous: the scan does see a body, and that body still names the colour
# helpers the renderer legitimately keeps.
check "26k: that scan still sees a body naming the helpers the renderer does keep" \
  "$(printf '%s\n' "$b16_fn_body" | grep -qF 'burn_trend_color' && echo yes || echo no)" "yes"

# iii. The plainness is the RENDERER's, not an artefact of one figure. Swept
#      across the range, including the values every retired band boundary sat
#      on (30, 50, 70), since a surviving threshold would show itself at
#      exactly those.
for b17_pct in 0 29 30 49 50 69 70 100; do
  check "26k: five_hour at $b17_pct% renders plain" \
    "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" "$b17_pct" "" "" "" "" "")")" \
    "5h $b17_pct%"
  check "26k: weekly at $b17_pct% renders plain" \
    "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" "" "" "$b17_pct" "" "" "")")" \
    "wk $b17_pct%"
done
unset b17_pct

# iv. Edge case: a decimal still truncates, and the truncated figure is still
#     plain. 23o pins the truncation on the stripped line; this pins that the
#     token reaching the terminal is the truncated one AND carries no sequence
#     -- the pair the retired helper used to couple.
check "26k: a float five_hour truncates and the plain token is the truncated one" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" 14.000000000000002 "" "" "" "" "")")" \
  "5h 14%"
check "26k: a float weekly likewise (23.5 -> 23, truncated not rounded)" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" "" "" 23.5 "" "" "")")" \
  "wk 23%"

# v. Edge case: a missing figure still drops its WHOLE group, separator and
#    all. Stated on the raw line, where a group reduced to a bare opener would
#    survive the stripped-text version of this check in section 23.
check "26k: no five_hour -> that group and its separator vanish, leaving the weekly one alone" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" "" "" 62 "" "" "")")" \
  "wk 62%"
check "26k: no weekly -> likewise" \
  "$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" 1 "" "" "" "" "")")" \
  "5h 1%"
check "26k: neither figure -> the burnrate line carries no limit group at all" \
  "$(b16_raw_line "$(burn_json "$B5_WD" 145230 "" "" "" "" "" "" "" "")")" \
  "$(burn_ctx_color 48)ctx 48%$B16_RST"

# vi. The arrow keeps its reset even when its opener is EMPTY. B16 makes
#     burn_trend_color emit nothing at or below zero, and the contract calls
#     the reset that follows "a no-op by design" -- so the wiring must not
#     start conditionalising it. The fixture is a barely-started window against
#     0% used, which is behind the even-burn line by construction, so the trend
#     is non-positive whatever the clock did around the render.
b17_neg_t0=$(date +%s)
b17_neg_raw=$(b16_raw_line "$(burn_json "$B5_WD" "" "" "" 0 "$B5_R5_RESET" "" "" "" "")")
b17_neg_t1=$(date +%s)
b17_neg_ok=no
b17_neg_closed=no
b17_neg_signed=no
for (( _n = b17_neg_t0; _n <= b17_neg_t1; _n++ )); do
  _t=$(burn_linear_trend 0 "$_n" "$B5_R5_RESET" 18000 2>/dev/null) || continue
  [ -n "$_t" ] || continue
  [ "$_t" -le 0 ] && b17_neg_signed=yes
  [ "$b17_neg_raw" = "$(b16_group_raw 5h 0 "$B5_R5_RESET" "$_n")" ] && b17_neg_ok=yes
  printf '%s' "$b17_neg_raw" | grep -qaF "$(b5_trend_token "$_t")$B16_RST" && b17_neg_closed=yes
done
check "26k: the non-positive-trend fixture really computes a trend, and it really is <= 0" \
  "$b17_neg_signed" "yes"
check "26k: that group renders byte for byte -- plain used%, the arrow, its reset, the countdown" \
  "$b17_neg_ok" "yes"
check "26k: the arrow is closed by its reset even when its colour opener is empty" \
  "$b17_neg_closed" "yes"
# The used% beside a non-positive trend is plain too: the group opens on text.
check "26k: and that group still opens on a plain used% token" \
  "$(case "$b17_neg_raw" in "5h 0% "*) echo yes ;; *) echo no ;; esac)" "yes"
unset b17_neg_t0 b17_neg_t1 b17_neg_raw b17_neg_ok b17_neg_closed b17_neg_signed _t

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
#     lands in window_size and the other eleven come back empty, which is
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

# The thirteen variables sl_parse_input's `read` names, in contract order. B05
# line2-groups retired lines_added and lines_removed from both ends of the round
# trip -- the jq filter no longer emits them and the read no longer names them --
# taking the list from fourteen to twelve; B07 line1-paths then ADDS
# workspace.project_dir to the same single jq, APPENDED LAST, taking it to
# thirteen. Last is the position the field order settles on here: a thirteenth
# field with only twelve names would not merely go unread, it would be swallowed
# by the LAST name (`read` gives the final variable the whole remainder), so
# session_id would come back as "sess-abc<1f>/pd". Nothing else about the
# function moves: same byte, same order for the first twelve, same
# empties-preserved rule.
B18_SHOW='printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" \
  "$window_size" "$total_input" "$transcript_path" "$cwd" "$model_name" "$effort" \
  "$r5" "$r5_reset" "$r7" "$r7_reset" \
  "$total_cost_usd" "$session_id" "$project_dir"'
B18_UNSET='unset window_size total_input transcript_path cwd model_name effort \
  r5 r5_reset r7 r7_reset total_cost_usd session_id project_dir'
# "s" per name still ASSIGNED after the read. Paired with B18_UNSET above it is
# the difference between "thirteen empty fields" and "twelve unset variables":
# `read` assigns every name it is given, so a name dropped from the read list
# stays unset here rather than merely reading empty.
B18_SETCHK='printf "%s%s%s%s%s%s%s%s%s%s%s%s%s" \
  "${window_size+s}" "${total_input+s}" "${transcript_path+s}" "${cwd+s}" \
  "${model_name+s}" "${effort+s}" "${r5+s}" "${r5_reset+s}" "${r7+s}" \
  "${r7_reset+s}" \
  "${total_cost_usd+s}" "${session_id+s}" "${project_dir+s}"'

B18_JQ_LOG="$TMPROOT/b18-jq-calls"

# b18_read(jq_stdout, bash_code, [NAME=VALUE...]): source context.sh, REPLACE
# `jq` with a shell function emitting JQ_STDOUT verbatim, unset the twelve
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
# on the byte the FIXED jq end emits and, unfixed, all twelve fields land in
# window_size with the other eleven empty. Exit 0, nothing on stderr, a
# statusline with an empty cwd -- exactly what the Why clause describes.
b18_head="A${B18_US}B${B18_US}C"
check "27a: three 0x1f-separated fields do not all collapse into window_size" \
  "$(b18_visible "$(b18_read "$b18_head" 'printf "%s/%s/%s" "$window_size" "$total_input" "$transcript_path"')")" \
  "A/B/C"

# --- 27b. The READ end: thirteen fields, in order, empties preserved --------
# Field ORDER gets its own assertion because a thirteen-name positional read is
# exactly the kind of thing a careless edit reorders, and every value here is
# distinct so a transposition cannot hide. Twelve, not fourteen, since B05
# retires the two line-count fields from both ends of the round trip; the two
# columns are removed, not blanked, so every field after them moves up. Thirteen
# since B07 appends project_dir LAST -- appended, so none of the twelve move.
b18_ordered="f01"
for _i in 02 03 04 05 06 07 08 09 10 11 12 13; do
  b18_ordered="$b18_ordered${B18_US}f$_i"
done
unset _i
check "27b: thirteen 0x1f-separated fields land one per variable, in contract order" \
  "$(b18_visible "$(b18_read "$b18_ordered" "$B18_SHOW")")" \
  "f01|f02|f03|f04|f05|f06|f07|f08|f09|f10|f11|f12|f13"
check "27b: and the read still assigns all thirteen names (none dropped from its list)" \
  "$(b18_read "$b18_ordered" "$B18_SETCHK")" "sssssssssssss"

# The invariant \x01 was chosen over @tsv's tab for, restated on the new byte:
# an absent transcript_path (field 3) must parse EMPTY and shift nothing after
# it. With a whitespace delimiter the run of two collapses and every later field
# moves up one column.
b18_gap="1000000${B18_US}145230${B18_US}${B18_US}/cwd${B18_US}Opus${B18_US}high${B18_US}42${B18_US}1700000000${B18_US}17${B18_US}1700500000${B18_US}12.34${B18_US}sess-gap${B18_US}/pdir"
check "27b: an empty middle field parses empty and shifts nothing after it" \
  "$(b18_visible "$(b18_read "$b18_gap" "$B18_SHOW")")" \
  "1000000|145230||/cwd|Opus|high|42|1700000000|17|1700500000|12.34|sess-gap|/pdir"

# Edge case: every optional field absent. jq joins thirteen empty strings, so
# what reaches the read is twelve delimiters and nothing else. Thirteen empty
# fields -- not one field holding twelve bytes and twelve empties, which is
# what today's read makes of it.
b18_allempty=""
for _i in 1 2 3 4 5 6 7 8 9 10 11 12; do b18_allempty="$b18_allempty$B18_US"; done
unset _i
check "27b: a payload with every field absent parses as thirteen empty fields" \
  "$(b18_visible "$(b18_read "$b18_allempty" "$B18_SHOW")")" "||||||||||||"

# The `effort` fallback to CLAUDE_EFFORT is "same fallbacks" in the Behavior
# clause: it applies AFTER the split, so it must neither stop firing nor start
# overriding. model_name rides both assertions so neither can pass on the
# unsplit string (where effort is empty and the fallback fires for the wrong
# reason).
b18_eff_empty="1000000${B18_US}145230${B18_US}${B18_US}/cwd${B18_US}Opus${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}"
check "27b: the CLAUDE_EFFORT fallback still fires after the split when the field is empty" \
  "$(b18_visible "$(b18_read "$b18_eff_empty" 'printf "%s/%s" "$model_name" "$effort"' CLAUDE_EFFORT=medium)")" \
  "Opus/medium"
b18_eff_set="1000000${B18_US}145230${B18_US}${B18_US}/cwd${B18_US}Opus${B18_US}high${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}${B18_US}"
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

# Thirteen distinguishable values, field 1 a known seven characters wide so the
# separator is the byte at offset 7 -- read positionally rather than by scanning
# for "the non-printable one", so a delimiter that IS printable is caught too.
b18_pay="{\"context_window\":{\"context_window_size\":1000000,\"total_input_tokens\":145230},\"transcript_path\":\"/tp\",\"workspace\":{\"current_dir\":\"/cw\",\"project_dir\":\"/pd\"},\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"},\"session_id\":\"sess-abc\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":1700000000},\"seven_day\":{\"used_percentage\":17,\"resets_at\":1700500000}},\"cost\":{\"total_lines_added\":503,\"total_lines_removed\":16,\"total_cost_usd\":12.34}}"
b18_joined=$(printf '%s' "$b18_pay" | jq -r "$(<"$B18_FILTER")")
check "27c: the filter's own output separates the fields with 0x1f" \
  "$(b18_visible "${b18_joined:7:1}")" "<1f>"
check "27c: twelve of them -- one per gap between the thirteen fields" \
  "$(b18_count_byte "$b18_joined" "$B18_US")" "12"
check "27c: and not one 0x01 byte survives in what jq emits" \
  "$(b18_count_byte "$b18_joined" "$B18_SOH")" "0"
# Order and count at the JQ end, independently of the read end: the same
# thirteen fields, the same order, on the new byte -- and the payload still
# CARRIES the two retired line counts, so this is where a filter that kept
# emitting them shows up. project_dir is LAST, which is the position the field
# order settles on: B07 ADDS it to this one filter (its Invariants clause is
# that it buys no second jq), and appending leaves all twelve fields before it
# exactly where they were.
check "27c: the thirteen fields come out in the contract's order, on the new byte" \
  "$(b18_visible "$b18_joined")" \
  "1000000<1f>145230<1f>/tp<1f>/cw<1f>Opus<1f>high<1f>42<1f>1700000000<1f>17<1f>1700500000<1f>12.34<1f>sess-abc<1f>/pd"
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
  for f in platform.sh states.sh states.tsv burn-math.sh burn-theme.sh; do
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

# The same four substrings must also appear in sl_parse_burn_fields's docblock:
# it names the delimiter too, and a stale docblock actively misleads.
b18_bf_docblock=$(sed -n '/^# Contract: B04 payload-parse/,/^sl_parse_burn_fields() {$/p' "$CONTEXT" \
  | grep -E '^#')
check "27g: sl_parse_burn_fields docblock names the byte actually in use (0x1f)" \
  "$(printf '%s\n' "$b18_bf_docblock" | grep -qiE '\\x1f|\\u001f|0x1f|001f' && echo yes || echo no)" "yes"
check "27g: sl_parse_burn_fields docblock explains the bash 3.2 reason" \
  "$(printf '%s\n' "$b18_bf_docblock" | grep -qE 'bash 3|3\.2' && echo yes || echo no)" "yes"
check "27g: sl_parse_burn_fields docblock names sentinel/CTLESC" \
  "$(printf '%s\n' "$b18_bf_docblock" | grep -qiE 'sentinel|ctlesc|quoting' && echo yes || echo no)" "yes"
check "27g: sl_parse_burn_fields docblock explains the tab/whitespace reason" \
  "$(printf '%s\n' "$b18_bf_docblock" | grep -qiE 'whitespace|tab' && echo yes || echo no)" "yes"

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
check "27i: a fully-absent payload still round-trips through real jq as thirteen empty fields" \
  "$(b18_visible "$(b18_parse '{}' "$B18_SHOW")")" "||||||||||||"

# === 28. B07 line1-paths ====================================================
# Contract: the `Contract: B07 line1-paths (plan 001-statusline-glance-uplift)`
# docblock above sl_render_path_segment. Glance-items 3 and 4 -- the project
# directory the orchestrator started in, and the directory the agent works in
# now -- become the head of line 1, wrapped in an OSC 8 file:// hyperlink whose
# terminator moves from ST to BEL.
#
# The block is SCAFFOLDED, not wired: sl_render_path_segment exists and returns
# non-zero, and line 1 still prints the bare cwd. So the cases below come in two
# shapes, and both are honest statements of the same contract:
#   - direct calls on the helper, which today hit the stub;
#   - full renders, which today run the old path.
# Nothing here re-tests what line 1's LATER segments do -- sections 12 and 25
# own those -- except the one clause B07 adds about them: that they do not move.

B07_BEL=$(printf '\a')
B07_ST="${ESC}\\"

# A real directory tree, not synthetic strings: nothing in the contract says the
# helper may not stat what it is given, and a test that assumed otherwise would
# be pinning an implementation choice rather than a clause.
B07_HOME="$TMPROOT/b07-home"
B07_PROJ="$B07_HOME/proj"
B07_SUB="$B07_PROJ/sub/dir"
B07_OUT="$TMPROOT/b07-elsewhere"
mkdir -p "$B07_SUB" "$B07_OUT"

# The process cwd for every sourced probe, and the payload each pipes in at
# source time: sourcing context.sh performs a whole render, so both are pinned
# somewhere inert for the reason section 27 gives.
B0708_RUN="$TMPROOT/b0708-run"; mkdir -p "$B0708_RUN"
B0708_SRC_CACHE="$TMPROOT/b0708-src-cache"
B0708_JSON="{\"workspace\":{\"current_dir\":\"$B0708_RUN\"},\"transcript_path\":\"\",$ctx}"

# b0708_run(bash_code, [NAME=VALUE...]): source context.sh and run BASH_CODE in
# the same shell, with the extra NAME=VALUE pairs in its environment. The
# helpers under test in both blocks are FUNCTIONS with no rendered output of
# their own, so calling them directly is the only way to state their Inputs and
# Outputs clauses at all; the render-level cases further down state the clauses
# about what the render does with them.
b0708_run() { # bash_code [NAME=VALUE...]
  local code="$1"; shift
  ( cd "$B0708_RUN" || return 1
    printf '%s' "$B0708_JSON" \
      | env CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
          CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
          CLAM_STATUSLINE_CACHE_DIR="$B0708_SRC_CACHE" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
          "$@" \
          bash -c '. "$1" >/dev/null 2>&1; eval "$2"' _ "$CONTEXT" "$code" )
}

# b07_seg(project_dir, current_dir, [NAME=VALUE...]): the RAW bytes
# sl_render_path_segment echoes for that pair. HOME is passed explicitly by
# every caller so the "~" clause is never at the mercy of the developer's own.
b07_seg() { # project_dir current_dir [NAME=VALUE...]
  local p="$1" c="$2"; shift 2
  b0708_run 'sl_render_path_segment "$B07_P" "$B07_C"' "B07_P=$p" "B07_C=$c" "$@"
}

# The text a terminal DISPLAYS: colour sequences and OSC 8 framing removed,
# under either terminator, so the visible-text clause can be read the same way
# before and after the ST->BEL change.
b07_visible() { # raw
  printf '%s' "$1" \
    | sed -E "s/${ESC}\\]8;;[^${ESC}${B07_BEL}]*(${ESC}\\\\|${B07_BEL})//g" \
    | sed -E "s/${ESC}\\[[0-9;]*m//g"
}

# The URL of the FIRST OSC 8 sequence in a raw segment: everything between the
# opener and whichever terminator arrives first, so a segment still framed with
# ST yields its URL here too rather than the whole string.
b07_url() { # raw
  local u="$1"
  u="${u#*"$ESC"]8;;}"
  u="${u%%"$B07_BEL"*}"
  u="${u%%"$ESC"*}"
  printf '%s' "$u"
}

b07_has() { # haystack needle
  case "$1" in *"$2"*) printf 'yes' ;; *) printf 'no' ;; esac
}

# --- 28a. The two dirs, and what the segment shows ---------------------------
# The Behavior clause's three shapes, read as the visible text: same path ->
# one segment; different -> project dir, "›", the current dir RELATIVE to it;
# not underneath -> the absolute current dir after the "›". Deliberately no
# assertion on the SPACING around the "›": the contract names the separator and
# the order, not the padding, and inventing padding here would be inventing
# contract.
b07_same=$(b07_seg "$B07_PROJ" "$B07_PROJ" "HOME=$B07_HOME")
check "28a: identical project and current dir render ONE segment, \$HOME collapsed to ~" \
  "$(b07_visible "$b07_same")" "~/proj"
check "28a: and no '›' at all, since there is no second dir to introduce" \
  "$(b07_has "$(b07_visible "$b07_same")" '›')" "no"

b07_under=$(b07_seg "$B07_PROJ" "$B07_SUB" "HOME=$B07_HOME")
b07_under_vis=$(b07_visible "$b07_under")
check "28a: a current dir under the project dir keeps the project dir as the head" \
  "$(b07_has "$b07_under_vis" '~/proj')" "yes"
check "28a: separated from what follows by the '›'" \
  "$(b07_has "$b07_under_vis" '›')" "yes"
check "28a: and what follows is the current dir RELATIVE to the project dir" \
  "$(b07_has "$b07_under_vis" 'sub/dir')" "yes"
check "28a: relative, not absolute -- the project prefix is not repeated after the '›'" \
  "$(b07_has "$b07_under_vis" '~/proj/sub')" "no"
check "28a: nor is the absolute current dir printed in full" \
  "$(b07_has "$b07_under_vis" "$B07_SUB")" "no"

b07_outside=$(b07_seg "$B07_PROJ" "$B07_OUT" "HOME=$B07_HOME")
b07_outside_vis=$(b07_visible "$b07_outside")
check "28a: a current dir NOT underneath the project dir still gets its '›'" \
  "$(b07_has "$b07_outside_vis" '›')" "yes"
check "28a: and falls back to the ABSOLUTE current dir after it" \
  "$(b07_has "$b07_outside_vis" "$B07_OUT")" "yes"
check "28a: the project dir still leads, so the fallback replaces only the tail" \
  "$(b07_has "$b07_outside_vis" '~/proj')" "yes"

# --- 28b. Absent PROJECT_DIR, and the "~" collapse ---------------------------
# The Errors clause ("an absent PROJECT_DIR falls back to rendering the current
# dir alone, exactly as today") and the two Edge cases about $HOME.
b07_noproj=$(b07_seg "" "$B07_SUB" "HOME=$B07_HOME")
check "28b: an absent project dir renders the current dir alone, exactly as today" \
  "$(b07_visible "$b07_noproj")" "~/proj/sub/dir"
check "28b: with no '›', since there is only one dir to show" \
  "$(b07_has "$(b07_visible "$b07_noproj")" '›')" "no"
check "28b: an empty \$HOME collapses nothing -- the absolute path shows unchanged" \
  "$(b07_visible "$(b07_seg "$B07_PROJ" "$B07_PROJ" "HOME=")")" "$B07_PROJ"
check "28b: nor does a path OUTSIDE \$HOME collapse" \
  "$(b07_visible "$(b07_seg "$B07_OUT" "$B07_OUT" "HOME=$B07_HOME")")" "$B07_OUT"
check "28b: and a path outside \$HOME carries no stray ~" \
  "$(b07_has "$(b07_visible "$(b07_seg "$B07_OUT" "$B07_OUT" "HOME=$B07_HOME")")" '~')" "no"

# --- 28c. The OSC 8 wrapper, and the ST -> BEL terminator --------------------
# "The whole segment is wrapped in an OSC 8 file:// hyperlink" -- the WHOLE
# segment, so the sequence opens before the first visible byte and closes after
# the last. The terminator is BEL, which is the half of this clause osc8_link
# carries and every other hyperlink in the render moves with.
check "28c: the segment opens with an OSC 8 hyperlink" \
  "$(case "$b07_same" in "$ESC"']8;;'*) echo yes ;; *) echo no ;; esac)" "yes"
check "28c: whose URL is a file:// URL" \
  "$(case "$(b07_url "$b07_same")" in 'file://'*) echo yes ;; *) echo no ;; esac)" "yes"
check "28c: and it closes with the empty-URL closer, BEL-terminated" \
  "$(case "$b07_same" in *"$ESC"']8;;'"$B07_BEL") echo yes ;; *) echo no ;; esac)" "yes"
check "28c: exactly two BEL bytes in the whole segment -- the two terminators, no more" \
  "$(b18_count_byte "$b07_same" "$B07_BEL")" "2"
check "28c: and no ST terminator survives anywhere in it" \
  "$(b18_count_byte "$b07_same" "$B07_ST")" "0"
# osc8_link itself, called directly: the terminator change is stated here as an
# equality so a half-done change (opener moved, closer not) is named rather than
# merely failing somewhere downstream.
check "28c: osc8_link frames its text with BEL terminators at both ends" \
  "$(b0708_run 'osc8_link "file:///tmp/x" "T"')" \
  "$(printf '\033]8;;file:///tmp/x\aT\033]8;;\a')"
check "28c: osc8_link with no url still falls through to the bare text (unchanged)" \
  "$(b0708_run 'osc8_link "" "T"')" "T"

# --- 28d. The encoding invariant --------------------------------------------
# "The URL is percent-encoded enough that a path containing a space or '#' does
# not break the sequence", and the Edge case behind it: the sequence's framing
# must never be decidable by its content. Asserted on the BYTES -- a path whose
# characters can terminate or truncate the sequence must not be able to.
B07_ODD="$TMPROOT/b07 odd#dir"
mkdir -p "$B07_ODD"
b07_odd=$(b07_seg "$B07_ODD" "$B07_ODD" "HOME=$B07_HOME")
b07_odd_url=$(b07_url "$b07_odd")
check "28d: a path containing a space still produces a well-formed sequence (two BEL)" \
  "$(b18_count_byte "$b07_odd" "$B07_BEL")" "2"
check "28d: the URL carries no raw space" \
  "$(b07_has "$b07_odd_url" ' ')" "no"
check "28d: it percent-encodes the space instead" \
  "$(b07_has "$b07_odd_url" '%20')" "yes"
check "28d: the URL carries no raw '#' -- which would truncate it at the fragment" \
  "$(b07_has "$b07_odd_url" '#')" "no"
check "28d: it percent-encodes the '#' instead" \
  "$(b07_has "$b07_odd_url" '%23')" "yes"
check "28d: while the VISIBLE text still shows the real path, unencoded" \
  "$(b07_has "$(b07_visible "$b07_odd")" 'b07 odd#dir')" "yes"
# The terminator byte itself, arriving as data. It cannot come from a real
# filesystem path, and the contract says the encoding must handle it anyway --
# because "the framing is decidable by its content" is the property being
# denied, not "this particular byte is likely".
B07_BELDIR="$TMPROOT/b07-bel${B07_BEL}dir"
mkdir -p "$B07_BELDIR" 2>/dev/null
b07_bel=$(b07_seg "$B07_BELDIR" "$B07_BELDIR" "HOME=$B07_HOME")
check "28d: a path carrying the terminator byte still yields exactly two BEL -- the framing's own" \
  "$(b18_count_byte "$b07_bel" "$B07_BEL")" "2"
check "28d: and the segment is still non-empty, so the render did not simply drop it" \
  "$([ -n "$b07_bel" ] && echo yes || echo no)" "yes"

# --- 28e. Wired into line 1 --------------------------------------------------
# The Outputs clause: the segment is the HEAD of line 1. These render end to
# end, so they also carry the Inputs clause -- workspace.project_dir reaching
# the renderer at all -- without naming the variable it lands in.
b07_json() { # project_dir current_dir [session_id] [transcript_path]
  local p="$1" c="$2" s="$3" t="$4" j
  j="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$c\""
  [ -n "$p" ] && j="$j,\"project_dir\":\"$p\""
  j="$j},$ctx,\"transcript_path\":\"$t\""
  [ -n "$s" ] && j="$j,\"session_id\":\"$s\""
  printf '%s}' "$j"
}
b07_raw() { # json cache_dir ttl
  printf '%s' "$1" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 HOME="$B07_HOME" \
        CLAM_STATUSLINE_CACHE_DIR="$2" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS="$3" \
        bash "$CONTEXT" 2>/dev/null
}
b07_line1_vis() { # json cache_dir ttl
  b07_visible "$(line_of "$(b07_raw "$1" "$2" "$3")" 1)"
}

b07_wired_diff=$(b07_line1_vis "$(b07_json "$B07_PROJ" "$B07_SUB")" "$TMPROOT/b07-wired-cache" 0)
check "28e: a payload whose project_dir and current_dir differ renders both, joined by '›'" \
  "$(b07_has "$b07_wired_diff" '›')" "yes"
check "28e: line 1 opens on the project dir, \$HOME collapsed" \
  "$(case "$b07_wired_diff" in '~/proj'*) echo yes ;; *) echo no ;; esac)" "yes"
check "28e: and the current dir rides it relative, not absolute" \
  "$([ "$(b07_has "$b07_wired_diff" 'sub/dir')" = yes ] \
     && [ "$(b07_has "$b07_wired_diff" "$B07_SUB")" = no ] && echo yes || echo no)" "yes"
b07_wired_same=$(b07_line1_vis "$(b07_json "$B07_PROJ" "$B07_PROJ")" "$TMPROOT/b07-wired-cache2" 0)
check "28e: a payload whose two dirs agree renders one segment and no '›'" \
  "$(b07_has "$b07_wired_same" '›')" "no"
check "28e: no project_dir in the payload degrades to the current dir alone, exactly as today" \
  "$(b07_line1_vis "$(b07_json "" "$B07_SUB")" "$TMPROOT/b07-wired-cache3" 0)" "~/proj/sub/dir"
check "28e: the render still exits 0 with a project_dir carrying a space and a '#'" \
  "$(printf '%s' "$(b07_json "$B07_ODD" "$B07_ODD")" \
      | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
          CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 HOME="$B07_HOME" \
          CLAM_STATUSLINE_CACHE_DIR="$TMPROOT/b07-odd-cache" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
          bash "$CONTEXT" >/dev/null 2>/dev/null; echo $?)" "0"

# --- 28f. The path segment stays LIVE ---------------------------------------
# The Invariant: it is never served from the cache bundle. Cold-render one pair
# of dirs, then render a DIFFERENT pair inside the TTL: the warm render must
# show the new pair, not the bundled one.
#
# Both renders carry the SAME session_id AND the same transcript_path, so they
# land on one bundle whichever of the two the key is derived from -- the clause
# under test is about the path segment, not about B08's key, and a fixture that
# went cold on the second render would prove neither.
B07_LIVE_DIR="$TMPROOT/b07-live-cache"
B07_LIVE_TR="$TMPROOT/b07-live-tr.jsonl"; echo '{}' > "$B07_LIVE_TR"
b07_raw "$(b07_json "$B07_PROJ" "$B07_PROJ" sess-b07-live "$B07_LIVE_TR")" "$B07_LIVE_DIR" 300 >/dev/null
b07_live=$(b07_line1_vis "$(b07_json "$B07_PROJ" "$B07_SUB" sess-b07-live "$B07_LIVE_TR")" "$B07_LIVE_DIR" 300)
check "28f: a WARM render shows the new dir pair -- the path segment is never cached" \
  "$(b07_has "$b07_live" '›')" "yes"
check "28f: and the relative tail is the new current dir, not the bundled one" \
  "$(b07_has "$b07_live" 'sub/dir')" "yes"

# --- 28g. The no-drift clause -----------------------------------------------
# "followed by the existing branch, PR, git-sync, mode and State segments
# UNCHANGED -- no segment past the path gains or loses a leading space." Read as
# an equality between two renders of the same worktree, one carrying a
# project_dir and one not: everything from the branch segment onward must be
# byte-identical, escapes included, and must still be there.
B07_TAIL_WD="$TMPROOT/b07-tail-wd"; mk_wt "$B07_TAIL_WD"
git -C "$B07_TAIL_WD" checkout -q -b b07-branch >/dev/null 2>&1
printf 'Build\n' > "$B07_TAIL_WD/.local/MODE"
printf 'State: In Progress\n' > "$B07_TAIL_WD/.local/TODO.md"
# The tail begins at the branch segment's own leading space, so a lost or
# doubled space at that seam moves the tail rather than hiding inside it.
b07_tail() { # line1
  local l="$1" sep head
  sep=" ${ESC}[38;5;245m("
  head="${l%%"$sep"*}"
  printf '%s' "${l#"$head"}"
}
b07_tail_with=$(b07_tail "$(line_of "$(b07_raw "$(b07_json "$B07_TAIL_WD" "$B07_TAIL_WD")" "$TMPROOT/b07-tail-a" 0)" 1)")
b07_tail_without=$(b07_tail "$(line_of "$(b07_raw "$(b07_json "" "$B07_TAIL_WD")" "$TMPROOT/b07-tail-b" 0)" 1)")
check "28g: control -- the tail really carries the branch, mode and State segments" \
  "$([ "$(b07_has "$b07_tail_without" 'b07-branch')" = yes ] \
     && [ "$(b07_has "$b07_tail_without" 'Build')" = yes ] \
     && [ "$(b07_has "$b07_tail_without" 'In Progress')" = yes ] && echo yes || echo no)" "yes"
check "28g: every segment past the path is byte-identical with and without a project_dir" \
  "$b07_tail_with" "$b07_tail_without"
check "28g: and the branch segment still carries exactly one leading space" \
  "$(case "$b07_tail_with" in "  "*) echo no ;; " ${ESC}["*) echo yes ;; *) echo no ;; esac)" "yes"
check "28g: the block still ends on the burnrate line, not on the path line" \
  "$(printf '%s\n' "$(b07_raw "$(b07_json "$B07_PROJ" "$B07_SUB")" "$TMPROOT/b07-tail-c" 0)" \
     | sed -E "s/${ESC}\\[[0-9;]*m//g" | tail -n1 | grep -qE '^Opus' && echo yes || echo no)" "yes"

# --- 28h. Still exactly ONE jq ----------------------------------------------
# "project_dir rides the existing invocation; it does not buy a second one."
# Measured through the PATH-shim harness on a payload that actually carries a
# project_dir, cold and warm, so a second jq added for the new field shows up
# on whichever path it was added to.
B07_JQ_DIR="$TMPROOT/b07-jq-cache"
B07_JQ_WD="$TMPROOT/b07-jq-wd"; mk_wt "$B07_JQ_WD"
b07_jq_json=$(b07_json "$B07_JQ_WD" "$B07_JQ_WD")
render_shim "$b07_jq_json" "$B07_JQ_DIR" 300     # cold
check "28h: a project_dir-carrying payload still spends exactly one jq on a cold render" \
  "$(shim_count "$SHIM_LOG" jq)" "1"
render_shim "$b07_jq_json" "$B07_JQ_DIR" 300     # warm
check "28h: and exactly one on a warm render" \
  "$(shim_count "$SHIM_LOG" jq)" "1"
check "28h: the warm render still sits inside the 12-command budget" \
  "$([ "$(shim_count "$SHIM_LOG")" -le 12 ] && echo yes || echo no)" "yes"

# === 29. B08 cache-session-key ==============================================
# Contract: the `Contract: B08 cache-session-key (plan 001-statusline-glance-uplift)`
# docblock above sl_cache_key. The bundle key moves from transcript_path to
# session_id -- "stable for the lifetime of a session and unique per session",
# which is what a cache key needs -- with the cwd as the fallback; a sweep
# bounds a cache directory that today grows without limit; and
# sl_bundle_read/sl_bundle_write are rewired onto the new key with their format,
# their atomic write and their TTL semantics untouched.
#
# Sections 13/14/19/20/21 own those unchanged semantics under the OLD key and
# are not restated here. What is restated is the narrow set of clauses B08
# makes about them: that they still hold once the key is the session's.

b08_json() { # cwd session_id transcript_path
  local j="{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$1\"},$ctx,\"transcript_path\":\"$3\""
  [ -n "$2" ] && j="$j,\"session_id\":\"$2\""
  printf '%s}' "$j"
}

# --- 29a. sl_cache_key: the stem it derives ---------------------------------
# The Inputs and Outputs clauses, probed inside ONE sourced shell: sl_cache_key
# is a pure function of its two arguments, and B06 froze this file's COST as
# well as its assertions, so nine renders to read nine keys would be eight
# renders wasted.
B08_KEYS=$(b0708_run 'printf "%s|%s|%s|%s|%s|%s|%s|%s" \
  "$(sl_cache_key "sess-abc" "/tmp/b08-one")" \
  "$(sl_cache_key "sess-abc" "/tmp/b08-two")" \
  "$(sl_cache_key "sess-xyz" "/tmp/b08-one")" \
  "$(sl_cache_key "" "/tmp/b08-one")" \
  "$(sl_cache_key "" "/tmp/b08-two")" \
  "$(sl_cache_key "" "/tmp/b08-one")" \
  "$(sl_cache_key "" "")" \
  "$(sl_cache_key "a/b/c" "/tmp/b08-one")"' 2>/dev/null)
b08_key() { # n
  printf '%s' "$B08_KEYS" | cut -d'|' -f"$1"
}
B08_K_A1=$(b08_key 1); B08_K_A2=$(b08_key 2); B08_K_X=$(b08_key 3)
B08_K_C1=$(b08_key 4); B08_K_C2=$(b08_key 5); B08_K_C1B=$(b08_key 6)
B08_K_NONE=$(b08_key 7); B08_K_SLASH=$(b08_key 8)
check "29a: a session_id yields a non-empty stem" \
  "$([ -n "$B08_K_A1" ] && echo yes || echo no)" "yes"
check "29a: with no slash in it -- one filename component, not a path" \
  "$(b07_has "$B08_K_A1" '/')" "no"
check "29a: the same session in a different cwd gets the SAME stem (session_id is the key)" \
  "$([ "$B08_K_A1" = "$B08_K_A2" ] && echo yes || echo no)" "yes"
check "29a: a different session in the same cwd gets a DIFFERENT one -- two sessions never share a bundle" \
  "$([ "$B08_K_A1" != "$B08_K_X" ] && echo yes || echo no)" "yes"
check "29a: an empty session_id falls back to the cwd -- non-empty stem, still no slash" \
  "$([ -n "$B08_K_C1" ] && [ "$(b07_has "$B08_K_C1" '/')" = no ] && echo yes || echo no)" "yes"
check "29a: and two different cwds fall back to two different stems" \
  "$([ "$B08_K_C1" != "$B08_K_C2" ] && echo yes || echo no)" "yes"
check "29a: the fallback is deterministic -- the same cwd twice yields the same stem" \
  "$([ "$B08_K_C1" = "$B08_K_C1B" ] && echo yes || echo no)" "yes"
check "29a: never empty, even when both inputs are" \
  "$([ -n "$B08_K_NONE" ] && echo yes || echo no)" "yes"
check "29a: path separators are flattened -- a session_id carrying slashes still yields one component" \
  "$([ -n "$B08_K_SLASH" ] && [ "$(b07_has "$B08_K_SLASH" '/')" = no ] && echo yes || echo no)" "yes"

# --- 29b. sl_cache_sweep: what it removes, and what it leaves ---------------
# The Behavior clause ("removes bundle and tick files whose mtime is older than
# MAX_AGE_SECONDS") stated at the boundary, plus the Outputs clause (it echoes
# nothing) and the Errors clause (a sweep failure is SILENT).
B08_SWEEP="$TMPROOT/b08-sweep"; mkdir -p "$B08_SWEEP"
: > "$B08_SWEEP/old.bundle";        set_mtime_ago "$B08_SWEEP/old.bundle" 172800
: > "$B08_SWEEP/old.tick";          set_mtime_ago "$B08_SWEEP/old.tick" 172800
: > "$B08_SWEEP/just-old.bundle";   set_mtime_ago "$B08_SWEEP/just-old.bundle" 86460
: > "$B08_SWEEP/just-fresh.bundle"; set_mtime_ago "$B08_SWEEP/just-fresh.bundle" 86340
: > "$B08_SWEEP/fresh.bundle"
: > "$B08_SWEEP/fresh.tick"
: > "$B08_SWEEP/old-foreign.txt";   set_mtime_ago "$B08_SWEEP/old-foreign.txt" 172800
B08_SWEEP_OUT=$(b0708_run 'sl_cache_sweep "$B08_DIR" 86400' "B08_DIR=$B08_SWEEP" 2>&1)
b08_gone() { # file
  [ -e "$B08_SWEEP/$1" ] && printf 'present' || printf 'gone'
}
check "29b: a two-day-old bundle is swept" "$(b08_gone old.bundle)" "gone"
check "29b: a two-day-old tick file is swept too" "$(b08_gone old.tick)" "gone"
check "29b: a bundle just past MAX_AGE_SECONDS is swept" "$(b08_gone just-old.bundle)" "gone"
check "29b: a bundle just inside it is kept -- the age is a boundary, not 'anything not mine'" \
  "$(b08_gone just-fresh.bundle)" "present"
check "29b: a fresh bundle is kept" "$(b08_gone fresh.bundle)" "present"
check "29b: a fresh tick file is kept" "$(b08_gone fresh.tick)" "present"
check "29b: an old file that is neither a bundle nor a tick is left alone" \
  "$(b08_gone old-foreign.txt)" "present"
check "29b: the sweep echoes nothing at all, on stdout or stderr" "$B08_SWEEP_OUT" ""
check "29b: a sweep of a directory that does not exist is silent too -- it never fails the render" \
  "$(b0708_run 'sl_cache_sweep "$B08_DIR" 86400' "B08_DIR=$TMPROOT/b08-no-such-dir" 2>&1)" ""

# --- 29c. Session isolation, end to end -------------------------------------
# The Invariant "two different sessions never share a bundle", stated where it
# bites: the SAME worktree, the same (absent) transcript_path, two session_ids.
# Detected the way sections 13/14 detect warm-vs-cold -- a MODE change is a
# CACHED segment, so a render still showing the old value was served warm.
B08_ISO_DIR="$TMPROOT/b08-iso-cache"
B08_ISO_WD="$TMPROOT/b08-iso-wd"; mk_wt "$B08_ISO_WD"
printf 'Build\n' > "$B08_ISO_WD/.local/MODE"
b08_iso_a=$(b08_json "$B08_ISO_WD" "sess-iso-a" "")
b08_iso_b=$(b08_json "$B08_ISO_WD" "sess-iso-b" "")
render_cached "$b08_iso_a" "$B08_ISO_DIR" 300 >/dev/null
printf 'Debug\n' > "$B08_ISO_WD/.local/MODE"
b08_iso_out_a=$(render_cached "$b08_iso_a" "$B08_ISO_DIR" 300)
b08_iso_out_b=$(render_cached "$b08_iso_b" "$B08_ISO_DIR" 300)
check "29c: session A stays warm on its own bundle ('Build' kept)" \
  "$(mode_cached_value "$b08_iso_out_a" 'Build')" "yes"
check "29c: session B in the SAME worktree gets its own cold bundle, never A's ('Debug')" \
  "$(mode_cached_value "$b08_iso_out_b" 'Debug')" "yes"

# --- 29d. transcript_path no longer keys anything ---------------------------
# The other half of "keys on session_id ... instead of transcript_path": one
# session whose transcript_path differs between renders is still ONE session and
# still one bundle. Read off the branch, which is a cached segment, across two
# worktrees on different branches.
B08_TR_DIR="$TMPROOT/b08-tr-cache"
B08_TR_1="$TMPROOT/b08-tr-1"; mk_wt "$B08_TR_1"; git -C "$B08_TR_1" checkout -q -b b08-one >/dev/null 2>&1
B08_TR_2="$TMPROOT/b08-tr-2"; mk_wt "$B08_TR_2"; git -C "$B08_TR_2" checkout -q -b b08-two >/dev/null 2>&1
B08_TRA="$TMPROOT/b08-tr-a.jsonl"; echo '{}' > "$B08_TRA"
B08_TRB="$TMPROOT/b08-tr-b.jsonl"; echo '{}' > "$B08_TRB"
render_cached "$(b08_json "$B08_TR_1" "sess-same" "$B08_TRA")" "$B08_TR_DIR" 300 >/dev/null
b08_tr_out=$(render_cached "$(b08_json "$B08_TR_2" "sess-same" "$B08_TRB")" "$B08_TR_DIR" 300)
check "29d: one session with two transcript_paths still shares ONE bundle (branch pinned to 'b08-one')" \
  "$(printf '%s\n' "$b08_tr_out" | grep -qF '(b08-one)' && echo yes || echo no)" "yes"
check "29d: the cwd path segment stays LIVE across that shared bundle" \
  "$(printf '%s\n' "$b08_tr_out" | sed -n '1p' | grep -qF "$B08_TR_2" && echo yes || echo no)" "yes"

# --- 29e. The fallback: an absent session_id still CACHES --------------------
# The Edge case: "falls back to the cwd key, and the bundle is still cached
# rather than disabled". Both worktrees deliberately share ONE transcript_path,
# which is exactly the pair the old key could not tell apart.
B08_FB_DIR="$TMPROOT/b08-fb-cache"
B08_FB_A="$TMPROOT/b08-fb-a"; mk_wt "$B08_FB_A"
B08_FB_B="$TMPROOT/b08-fb-b"; mk_wt "$B08_FB_B"
B08_FB_TR="$TMPROOT/b08-fb-tr.jsonl"; echo '{}' > "$B08_FB_TR"
printf 'Alpha\n' > "$B08_FB_A/.local/MODE"
printf 'Bravo\n' > "$B08_FB_B/.local/MODE"
b08_fb_a=$(b08_json "$B08_FB_A" "" "$B08_FB_TR")
b08_fb_b=$(b08_json "$B08_FB_B" "" "$B08_FB_TR")
render_cached "$b08_fb_a" "$B08_FB_DIR" 300 >/dev/null
render_cached "$b08_fb_b" "$B08_FB_DIR" 300 >/dev/null
printf 'ChangedA\n' > "$B08_FB_A/.local/MODE"
printf 'ChangedB\n' > "$B08_FB_B/.local/MODE"
check "29e: no session_id, shared transcript_path: worktree A is warm on its OWN cwd-keyed bundle ('Alpha')" \
  "$(mode_cached_value "$(render_cached "$b08_fb_a" "$B08_FB_DIR" 300)" 'Alpha')" "yes"
check "29e: and worktree B on its own ('Bravo') -- the fallback is per-cwd, not one shared bucket" \
  "$(mode_cached_value "$(render_cached "$b08_fb_b" "$B08_FB_DIR" 300)" 'Bravo')" "yes"
check "29e: caching is not DISABLED by the missing session_id -- a bundle was written" \
  "$([ "$(find "$B08_FB_DIR" -name '*.bundle' -type f 2>/dev/null | wc -l | tr -d ' ')" -ge 2 ] && echo yes || echo no)" "yes"

# --- 29f. sl_bundle_read/write really are rewired onto sl_cache_key ---------
# The third Behavior clause. The bundle a cold render leaves behind is named by
# the stem sl_cache_key derives for that payload -- which is the only externally
# observable statement of "rewired", and the one a half-done rewiring (key
# function present, callers still deriving their own) fails.
B08_WIRE_DIR="$TMPROOT/b08-wire-cache"
B08_WIRE_WD="$TMPROOT/b08-wire-wd"; mk_wt "$B08_WIRE_WD"
render_cached "$(b08_json "$B08_WIRE_WD" "sess-wired" "$B08_TRA")" "$B08_WIRE_DIR" 300 >/dev/null
B08_WIRE_KEY=$(b0708_run 'sl_cache_key "sess-wired" "$B08_WD"' "B08_WD=$B08_WIRE_WD" 2>/dev/null)
check "29f: the cold render's bundle is named by sl_cache_key's stem" \
  "$([ -n "$B08_WIRE_KEY" ] && [ -f "$B08_WIRE_DIR/$B08_WIRE_KEY.bundle" ] && echo yes || echo no)" "yes"
check "29f: and it is the ONLY bundle that render wrote" \
  "$(find "$B08_WIRE_DIR" -name '*.bundle' -type f 2>/dev/null | wc -l | tr -d ' ')" "1"
check "29f: its FORMAT is unchanged -- the same five keys" \
  "$(for k in branch pr_badge git_sync state_seg clam_mode; do \
       grep -qE "^${k}=" "$B08_WIRE_DIR/$B08_WIRE_KEY.bundle" 2>/dev/null || { echo no; exit; }; done; echo yes)" "yes"
check "29f: and no sixth" \
  "$(grep -cE '^cost_line=' "$B08_WIRE_DIR/$B08_WIRE_KEY.bundle" 2>/dev/null | tr -d ' ')" "0"

# --- 29g. The sweep runs on the COLD path only ------------------------------
# The Invariant, and with it the Edge case about bundles left behind under the
# old transcript_path key: aged out by the same sweep rather than migrated. The
# planted files are named the way today's key names them, so the "not migrated"
# half is a statement about a file the renderer could have adopted and did not.
B08_SWP_DIR="$TMPROOT/b08-cold-sweep"; mkdir -p "$B08_SWP_DIR"
B08_SWP_WD="$TMPROOT/b08-cold-sweep-wd"; mk_wt "$B08_SWP_WD"
git -C "$B08_SWP_WD" checkout -q -b b08-sweep >/dev/null 2>&1
B08_LEGACY_KEY=$(printf '%s' "$B08_SWP_WD" | sed 's#/#_#g')
{ printf 'branch=legacy-sentinel\n'; printf 'pr_badge=\n'; printf 'git_sync=\n'
  printf 'state_seg=\n'; printf 'clam_mode=\n'; } > "$B08_SWP_DIR/$B08_LEGACY_KEY.bundle"
set_mtime_ago "$B08_SWP_DIR/$B08_LEGACY_KEY.bundle" 172800
: > "$B08_SWP_DIR/half-day.bundle"; set_mtime_ago "$B08_SWP_DIR/half-day.bundle" 43200
b08_swp_out=$(render_cached "$(b08_json "$B08_SWP_WD" "sess-sweep" "")" "$B08_SWP_DIR" 300)
check "29g: the stale old-key bundle is not adopted -- its sentinel branch never renders" \
  "$(printf '%s\n' "$b08_swp_out" | grep -qF 'legacy-sentinel' && echo present || echo absent)" "absent"
check "29g: a COLD render sweeps it away rather than migrating it" \
  "$([ -e "$B08_SWP_DIR/$B08_LEGACY_KEY.bundle" ] && echo present || echo gone)" "gone"
check "29g: while a half-day-old bundle survives -- the call site's MAX_AGE_SECONDS is one day, not 'everything else'" \
  "$([ -e "$B08_SWP_DIR/half-day.bundle" ] && echo present || echo gone)" "present"
# The warm half. A file planted AFTER the cold render is still there once a warm
# render has run, because the warm path never sweeps.
: > "$B08_SWP_DIR/planted-old.bundle"; set_mtime_ago "$B08_SWP_DIR/planted-old.bundle" 172800
render_cached "$(b08_json "$B08_SWP_WD" "sess-sweep" "")" "$B08_SWP_DIR" 300 >/dev/null
check "29g: a WARM render does not sweep -- an ancient bundle planted after the cold render survives it" \
  "$([ -e "$B08_SWP_DIR/planted-old.bundle" ] && echo present || echo gone)" "present"

# --- 29h. The warm render still opens nothing it did not open before --------
# The other half of "cold path only", measured rather than reasoned: the
# PATH-shim harness sees no file-removal or directory-walk process on the warm
# path, and the warm budget does not move.
B08_BUD_DIR="$TMPROOT/b08-budget-cache"
B08_BUD_WD="$TMPROOT/b08-budget-wd"; mk_wt "$B08_BUD_WD"
printf 'Build\n' > "$B08_BUD_WD/.local/MODE"
b08_bud_json=$(b08_json "$B08_BUD_WD" "sess-budget" "")
render_shim "$b08_bud_json" "$B08_BUD_DIR" 300     # cold: seeds the bundle and sweeps
render_shim "$b08_bud_json" "$B08_BUD_DIR" 300     # warm
check "29h: the warm render still invokes at most 12 external commands in total" \
  "$([ "$(shim_count "$SHIM_LOG")" -le 12 ] && echo yes || echo no)" "yes"
check "29h: it spawns no rm -- the sweep is not on this path" \
  "$(shim_count "$SHIM_LOG" rm)" "0"
check "29h: nor find" "$(shim_count "$SHIM_LOG" find)" "0"
check "29h: still exactly one jq" "$(shim_count "$SHIM_LOG" jq)" "1"
check "29h: still no git" "$(shim_count "$SHIM_LOG" git)" "0"
check "29h: and the sentinel CLAUDE_PROJECTS_DIR is still untouched" \
  "$(find "$SENTINEL_PROJECTS_DIR" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" "0"

# --- 29i. Everything else about the cache is unchanged ----------------------
# The clauses B08 explicitly does NOT move, re-pinned under the new key: the TTL
# boundary and its <=0 disable, the corrupt bundle, the future-dated bundle, the
# uncreatable cache dir, and the atomic write under concurrency. Each is stated
# once, on a session-keyed payload; sections 13/19/20/21 keep the fuller
# treatment under the old key.
B08_TTL_DIR="$TMPROOT/b08-ttl-cache"
B08_TTL_WD="$TMPROOT/b08-ttl-wd"; mk_wt "$B08_TTL_WD"
printf 'Build\n' > "$B08_TTL_WD/.local/MODE"
b08_ttl_json=$(b08_json "$B08_TTL_WD" "sess-ttl" "")
render_cached "$b08_ttl_json" "$B08_TTL_DIR" 2 >/dev/null
printf 'Debug\n' > "$B08_TTL_WD/.local/MODE"
backdate_all "$B08_TTL_DIR" 1
check "29i: TTL semantics unchanged under the new key -- a 1s-old bundle at TTL 2 is warm ('Build')" \
  "$(mode_cached_value "$(render_cached "$b08_ttl_json" "$B08_TTL_DIR" 2)" 'Build')" "yes"
backdate_all "$B08_TTL_DIR" 2
check "29i: and a 2s-old one is stale ('Debug')" \
  "$(mode_cached_value "$(render_cached "$b08_ttl_json" "$B08_TTL_DIR" 2)" 'Debug')" "yes"
check "29i: TTL <= 0 still disables cache serving outright" \
  "$(printf 'Rebuilt\n' > "$B08_TTL_WD/.local/MODE"; \
     mode_cached_value "$(render_cached "$b08_ttl_json" "$B08_TTL_DIR" 0)" 'Rebuilt')" "yes"
backdate_all "$B08_TTL_DIR" -600
printf 'Future\n' > "$B08_TTL_WD/.local/MODE"
b08_future_out=$(render_cached "$b08_ttl_json" "$B08_TTL_DIR" 300)
check "29i: a future-dated bundle still reads as fresh -- the bundled value is kept ('Rebuilt')" \
  "$(mode_cached_value "$b08_future_out" 'Rebuilt')" "yes"
check "29i: so the newer on-disk MODE is deliberately NOT picked up" \
  "$(mode_cached_value "$b08_future_out" 'Future')" "no"
B08_CORRUPT_DIR="$TMPROOT/b08-corrupt-cache"
B08_CORRUPT_WD="$TMPROOT/b08-corrupt-wd"; mk_wt "$B08_CORRUPT_WD"
b08_corrupt_json=$(b08_json "$B08_CORRUPT_WD" "sess-corrupt" "")
render_cached "$b08_corrupt_json" "$B08_CORRUPT_DIR" 300 >/dev/null
find "$B08_CORRUPT_DIR" -type f -exec sh -c 'printf "not-a-bundle{{{" > "$1"' _ {} \; 2>/dev/null
check "29i: a corrupt bundle under the new key is still treated as absent, not a crash" \
  "$(burn_of "$(render_cached "$b08_corrupt_json" "$B08_CORRUPT_DIR" 300)" | grep -qE 'ctx [0-9]+%' && echo yes || echo no)" "yes"
B08_BLOCKED_PARENT="$TMPROOT/b08-blocked"; mkdir -p "$B08_BLOCKED_PARENT"
B08_BLOCKED="$B08_BLOCKED_PARENT/cache"; : > "$B08_BLOCKED"
b08_blocked_json=$(b08_json "$WD" "sess-blocked" "")
check "29i: an uncreatable cache dir still renders (cold every time), sweep failure and all" \
  "$(burn_of "$(render_cached "$b08_blocked_json" "$B08_BLOCKED" 300)" | grep -qE 'ctx [0-9]+%' && echo yes || echo no)" "yes"
check "29i: and leaks no cache or sweep error onto stdout" \
  "$(render_cached "$b08_blocked_json" "$B08_BLOCKED" 300 | grep -qiE 'cache|sweep|no such file|cannot create|error' && echo present || echo absent)" "absent"
check "29i: exiting 0" \
  "$(printf '%s' "$b08_blocked_json" \
      | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
          CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
          CLAM_STATUSLINE_CACHE_DIR="$B08_BLOCKED" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=300 \
          bash "$CONTEXT" >/dev/null 2>/dev/null; echo $?)" "0"
# The atomic temp-plus-rename write, under the same maximum contention section
# 21 uses: every concurrent render at one session key still produces a complete
# line, so no reader ever sees a partial bundle.
B08_SMOKE_DIR="$TMPROOT/b08-smoke-cache"
B08_SMOKE_WD="$TMPROOT/b08-smoke-wd"; mk_wt "$B08_SMOKE_WD"
printf 'Build\n' > "$B08_SMOKE_WD/.local/MODE"
b08_smoke_json=$(b08_json "$B08_SMOKE_WD" "sess-smoke" "")
B08_SMOKE_OUT="$TMPROOT/b08-smoke-out"; mkdir -p "$B08_SMOKE_OUT"
for i in $(seq 1 8); do
  ( render_cached "$b08_smoke_json" "$B08_SMOKE_DIR" 0 > "$B08_SMOKE_OUT/$i" 2>&1 ) &
done
wait
b08_bad=0
for f in "$B08_SMOKE_OUT"/*; do
  sed -n '2p' "$f" | grep -qE '^Opus .*ctx [0-9]+%' || b08_bad=$((b08_bad+1))
done
check "29i: concurrency at one session key (ttl=0, max write contention): every render still complete" \
  "$b08_bad" "0"

# --- 29j. The cache file's name changes; nothing the user sees does ---------
# The Outputs clause. Two renders of the same worktree, one carrying a
# session_id and one not, must be byte-identical on the line the bundle feeds --
# escapes included.
B08_TXT_WD="$TMPROOT/b08-text-wd"; mk_wt "$B08_TXT_WD"
git -C "$B08_TXT_WD" checkout -q -b b08-text >/dev/null 2>&1
printf 'Build\n' > "$B08_TXT_WD/.local/MODE"
b08_raw_line1() { # json cache_dir
  printf '%s' "$1" \
    | CLAUDE_PROJECTS_DIR="$TMPROOT/projects" CCOST_CACHE_DIR="$TMPROOT/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
        CLAM_STATUSLINE_CACHE_DIR="$2" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS=0 \
        bash "$CONTEXT" 2>/dev/null | sed -n '1p'
}
b08_with=$(b08_raw_line1 "$(b08_json "$B08_TXT_WD" "sess-text" "")" "$TMPROOT/b08-text-a")
b08_without=$(b08_raw_line1 "$(b08_json "$B08_TXT_WD" "" "")" "$TMPROOT/b08-text-b")
check "29j: control -- the compared line really carries the cached segments" \
  "$([ "$(b07_has "$b08_without" 'b08-text')" = yes ] \
     && [ "$(b07_has "$b08_without" 'Build')" = yes ] && echo yes || echo no)" "yes"
check "29j: a session_id in the payload changes nothing the user sees on line 1" \
  "$b08_with" "$b08_without"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
