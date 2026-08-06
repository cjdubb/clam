#!/bin/bash

# Contract: B01 context-cheap-render
# Behavior:
#   context.sh renders the statusline from the statusLine JSON on stdin.
#   Rendering splits into a LIVE path computed on every invocation and an
#   EXPENSIVE segment bundle served from a per-session cache with a short
#   TTL. Live on every render: the cwd path (from stdin), the model+effort
#   portion of the mode line, the Ctx-usage line (stdin token counts +
#   transcript idle age + compaction budget), and the atomic
#   .local/.ctx-status.json publish. Cached as ONE bundle, rebuilt at most
#   once per TTL: git branch, PR badge, git-sync segment, TODO State
#   segment, and clam mode. The background refresh-engine
#   kicks (pr-status / git-sync staleness checks) are evaluated only when
#   the bundle is rebuilt, never on the warm path.
# Inputs:
#   stdin: statusLine JSON (context_window, transcript_path, workspace,
#     model, effort) — parsed with EXACTLY ONE jq invocation per render.
#   CLAM_STATUSLINE_CACHE_DIR: segment-cache directory (default
#     ~/.claude/.statusline-cache; created on demand).
#   CLAM_STATUSLINE_SEGMENT_TTL_SECONDS: bundle TTL in integer seconds
#     (default 5). Values <= 0 disable cache serving (every render
#     rebuilds); a non-integer value falls back to the default.
#   Cache key: derived from transcript_path (fallback: cwd) so two
#     sessions never share a bundle, even in the same worktree.
# Outputs:
#   Identical statusline text semantics and segment order as the
#   pre-cache renderer: for the same inputs, a cold render is
#   byte-identical to the legacy output; a warm render differs from the
#   bundle-write-time output at most in the live parts reflecting newer
#   stdin values. .local/.ctx-status.json keeps its schema and is
#   atomically replaced on every render inside a git worktree with .local/.
# Errors:
#   Cache dir uncreatable or unwritable: fall back to a full (cold)
#   render every time; the statusline never breaks and never prints cache
#   errors to stdout. A corrupt or partially-written bundle is treated as
#   absent; bundle writes are atomic (temp file + rename) so a reader
#   never sees a partial bundle.
# Invariants:
#   A WARM render (bundle younger than TTL):
#     - invokes at most 10 external commands in total, children included
#       (bash builtins are free; every non-builtin process counts);
#     - runs exactly one jq over the stdin payload, plus at most one jq
#       for the settings.json compaction-budget fallback;
#     - does not invoke ccost.sh, does not invoke git, and opens no file
#       under CLAUDE_PROJECTS_DIR (~/.claude/projects).
#   A COLD render does at most the legacy renderer's work plus one atomic
#   bundle write, and leaves the bundle fresh so an immediately following
#   render is warm. Cache entries are only ever replaced whole.
# Edge cases:
#   Missing/empty transcript_path: key falls back to cwd; the bundle is
#     still cached. TTL boundary: age < TTL is
#     fresh, age >= TTL is stale; a negative age (future-dated bundle
#     after a clock step) reads fresh. No git worktree / no .local/:
#     segments degrade exactly as today and the ctx-status publish is
#     skipped as today. First-ever render: cold, creates dir + bundle.

# --- B01 scaffold surface --------------------------------------------------
# Public env knobs of the cheap-render path.
SL_CACHE_DIR="${CLAM_STATUSLINE_CACHE_DIR:-$HOME/.claude/.statusline-cache}"
SL_SEGMENT_TTL_SECONDS="${CLAM_STATUSLINE_SEGMENT_TTL_SECONDS:-5}"

# sl_parse_input: parse the ENTIRE stdin payload (window size, total input
# tokens, transcript path, cwd, model display name, effort level) with one
# single jq invocation, populating the same variables the legacy per-field
# jq calls populate today.
#
# Contract: B18 statusline-bash3-payload-delimiter
#             (plan 003-statusline-meter-colour)
#
# Behavior:   The fourteen payload fields are joined in jq and split in bash
#             on ONE non-whitespace delimiter byte. That byte changes from
#             \x01 to \x1f (ASCII US, the unit separator), at BOTH ends: the
#             `join` at the end of the jq filter and the `IFS=` prefix on the
#             `read`. Nothing else about this function changes — same fourteen
#             fields, same order, same single jq invocation, same fallbacks,
#             same `effort` fallback to CLAUDE_EFFORT afterwards.
#
# Why:        bash 3.2 reserves \x01 as its internal quoting sentinel (CTLESC;
#             \x7f is CTLNUL) and its `read` builtin cannot split on either
#             byte. Measured under a bash built from the 3.2.57 tarball,
#             splitting a three-field string on \x01 gives x=[ABC] y=[] z=[],
#             while \x02, \x1e, \x1f, tab and colon all split correctly.
#             The consequence in the shipped plugin is total, silent and
#             user-facing: every field lands in `window_size`, the other
#             thirteen come back empty, and the statusline renders an empty
#             cwd with no burnrate line at all — exit 0, nothing on stderr.
#             macOS ships /bin/bash 3.2.57, so this is live breakage there,
#             not a hypothetical.
#
# Inputs:     unchanged — `$input`, the statusLine JSON read from stdin.
#
# Outputs:    unchanged under bash 4 and above; the rendered line is
#             byte-identical before and after. Under bash 3.2 the render goes
#             from producing nothing to producing what bash 5 produces.
#
# Errors:     unchanged. An absent or malformed field still parses empty
#             rather than swallowing its neighbour.
#
# Invariants:
#   - **Empty fields between delimiters are still preserved.** This is the
#     property \x01 was chosen over @tsv's tab for in the first place, and the
#     comment below records why: bash treats tab as IFS whitespace even when
#     IFS is set to only a tab, so runs of it collapse and an absent
#     transcript_path silently swallows the next column. \x1f is not IFS
#     whitespace and preserves empty fields; verified under 3.2.57.
#   - The comment inside this function must explain BOTH reasons and name the
#     byte actually in use. Today it explains only the tab problem. A future
#     reader who knows only that reason will "simplify" the delimiter straight
#     back into the bash 3.2 defect, because \x01 looks like a strictly better
#     answer to the tab problem alone.
#   - Exactly one jq invocation per render. The warm-render process budget
#     (12 externals, measured by the PATH-shim harness in context.test.sh)
#     does not move.
#   - Neither \x01 nor \x7f is introduced anywhere else in the plugin.
#
# Edge cases:
#   - A payload field whose own VALUE contains \x1f would misparse. That is
#     the same theoretical hazard the old byte carried and no more likely; a
#     field containing \x01 is now harmless where it previously was not.
#   - A payload with every optional field absent still parses fourteen empty
#     fields, not one field and thirteen unset variables.
#   - A user on bash 5 sees no observable change whatsoever. This is why a
#     regression test must distinguish the two BYTES rather than re-check
#     today's rendered output, which is identical either way.
sl_parse_input() {
  # Joined and split on \x1f (ASCII US) rather than \x01. \x01 answers the
  # tab problem below just as well, but bash 3.2 reserves \x01 as its own
  # internal quoting sentinel (CTLESC) and `read` cannot split on it at all
  # -- every field lands in window_size and the rest come back empty. macOS
  # ships bash 3.2, so this is live breakage there, not a hypothetical.
  #
  # Not @tsv's tab either: bash's `read` treats tab as "IFS whitespace" even
  # when IFS is set to only a tab, so runs of the delimiter collapse and an
  # empty field (e.g. an absent transcript_path) silently swallows the next
  # column, misaligning every field after it. \x1f is not whitespace, so
  # empty fields between delimiters are preserved.
  #
  # The eight burnrate fields (B04) ride this SAME jq invocation rather than
  # a second one -- see the B04 payload-parse contract above
  # sl_parse_burn_fields. five_hour/seven_day are each gated on their own
  # used_percentage key: a payload using the ISO-8601 utilization/resets_at
  # shape (a different internal surface) has no used_percentage, so both its
  # percentage and its resets_at parse empty rather than picking up the
  # wrong-shaped value.
  IFS=$'\x1f' read -r window_size total_input transcript_path cwd model_name effort \
    r5 r5_reset r7 r7_reset lines_added lines_removed total_cost_usd session_id <<< "$(
    printf '%s' "$input" | jq -r '
        . as $p
        | ($p.rate_limits.five_hour.used_percentage) as $u5
        | ($p.rate_limits.seven_day.used_percentage) as $u7
        | [
            ($p.context_window.context_window_size // ""),
            ($p.context_window.total_input_tokens // ""),
            ($p.transcript_path // ""),
            ($p.workspace.current_dir // $p.cwd // ""),
            ($p.model.display_name // ""),
            ($p.effort.level // ""),
            (if $u5 == null then "" else $u5 end),
            (if $u5 == null then "" else ($p.rate_limits.five_hour.resets_at // "") end),
            (if $u7 == null then "" else $u7 end),
            (if $u7 == null then "" else ($p.rate_limits.seven_day.resets_at // "") end),
            ($p.cost.total_lines_added // ""),
            ($p.cost.total_lines_removed // ""),
            ($p.cost.total_cost_usd // ""),
            ($p.session_id // "")
          ]
        | join("\u001f")
      '
  )"
  [ -z "$effort" ] && effort="${CLAUDE_EFFORT:-}"
}

# sl_bundle_read: emit the cached expensive-segment bundle for the current
# session key iff it is fresh (age < SL_SEGMENT_TTL_SECONDS); non-zero exit
# when stale, absent, corrupt, or caching is disabled (TTL <= 0).
#
# Reads its cache key from transcript_path/cwd (populated by sl_parse_input)
# and the shared "now" epoch ($_sl_now) so it never forks its own `date`.
# On success it populates branch, pr_badge, git_sync_segment, state_segment,
# clam_mode from the bundle. The bundle is a plain key=value-per-line file
# (no JSON) so a warm read never spends the render's one jq invocation on
# cache bookkeeping. A line whose value happens to contain "=" is still read
# correctly (only the FIRST "=" on the line separates key from value); a
# bundle missing any of the five expected keys — e.g. corrupted content that
# matches none of them — is treated as absent. An old six-key bundle from
# the pre-B04 plugin version still carries a cost_line= line; it is simply
# ignored (matches no case arm below, contributes no bit) rather than
# treated as corrupt — the migration path for every already-installed user.
sl_bundle_read() {
  local ttl key_src key file mtime age line got
  ttl="$SL_SEGMENT_TTL_SECONDS"
  [[ "$ttl" =~ ^-?[0-9]+$ ]] || ttl=5
  [ "$ttl" -le 0 ] && return 1

  key_src="$transcript_path"
  [ -z "$key_src" ] && key_src="$cwd"
  key="${key_src//\//_}"
  file="$SL_CACHE_DIR/$key.bundle"
  [ -f "$file" ] || return 1

  mtime=$(_sl_mtime_epoch "$file")
  age=$(( _sl_now - mtime ))
  [ "$age" -ge "$ttl" ] && return 1

  got=0
  branch=""; pr_badge=""; git_sync_segment=""; state_segment=""; clam_mode=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      branch=*)    branch="${line#branch=}";            got=$((got | 1)) ;;
      pr_badge=*)  pr_badge="${line#pr_badge=}";         got=$((got | 2)) ;;
      git_sync=*)  git_sync_segment="${line#git_sync=}"; got=$((got | 4)) ;;
      state_seg=*) state_segment="${line#state_seg=}";   got=$((got | 8)) ;;
      clam_mode=*) clam_mode="${line#clam_mode=}";       got=$((got | 16)) ;;
      # cost_line=* deliberately unmatched -- see the comment above.
    esac
  done < "$file"
  [ "$got" -eq 31 ] || return 1
}

# sl_bundle_write: atomically (temp + rename) persist the freshly rendered
# expensive-segment bundle for the current session key; best-effort — a
# write failure leaves rendering unaffected.
sl_bundle_write() {
  local key_src key tmp
  key_src="$transcript_path"
  [ -z "$key_src" ] && key_src="$cwd"
  key="${key_src//\//_}"
  mkdir -p "$SL_CACHE_DIR" 2>/dev/null || return 0
  tmp=$(mktemp "$SL_CACHE_DIR/.bundle.XXXXXX" 2>/dev/null) || return 0
  {
    printf 'branch=%s\n' "$branch"
    printf 'pr_badge=%s\n' "$pr_badge"
    printf 'git_sync=%s\n' "$git_sync_segment"
    printf 'state_seg=%s\n' "$state_segment"
    printf 'clam_mode=%s\n' "$clam_mode"
  } > "$tmp" 2>/dev/null
  mv -f "$tmp" "$SL_CACHE_DIR/$key.bundle" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}
# ------------------------------------------------------------------------

# --- Burnrate line ---------------------------------------------------------

# Contract: B04 payload-parse (plan 001-statusline-burnrate-uplift)
#
# Behavior:
#   Extends the render's single-jq stdin parse to the fields the burnrate
#   line needs, and retires the Cost line's inputs. Three changes, one
#   block:
#     1. sl_parse_input additionally populates the eight burnrate variables
#        below, from the SAME single jq invocation that already yields the
#        window size, token count, transcript path, cwd, model and effort.
#        Adding a second jq is a contract violation, not an optimisation
#        target.
#     2. The cached expensive-segment bundle drops its cost_line key: six
#        keys become five and sl_bundle_read's completeness mask goes from
#        63 to 31. A bundle written by the previous version still has six
#        keys; the extra one is ignored, not treated as corrupt.
#     3. context.sh stops invoking ccost.sh entirely. The script itself
#        stays in the plugin as a standalone CLI (bash ccost.sh day), and
#        prices.json with it — only the render's dependency on it goes.
#
# Inputs:
#   The statusLine JSON on stdin, additionally read for:
#     .rate_limits.five_hour.used_percentage   -> r5          (0..100)
#     .rate_limits.five_hour.resets_at         -> r5_reset    (epoch seconds)
#     .rate_limits.seven_day.used_percentage   -> r7          (0..100)
#     .rate_limits.seven_day.resets_at         -> r7_reset    (epoch seconds)
#     .cost.total_lines_added                  -> lines_added
#     .cost.total_lines_removed                -> lines_removed
#     .cost.total_cost_usd                     -> total_cost_usd
#     .session_id                              -> session_id
#   Field names verified against Claude Code 2.1.220's own embedded
#   statusline documentation: used_percentage is 0..100 and resets_at is
#   Unix epoch SECONDS. (An ISO-8601 `utilization`/`resets_at` shape also
#   exists in the binary; it belongs to a different internal surface and
#   must NOT be parsed here.)
#
# Outputs:
#   The eight variables above, set in the caller's scope. Each is the empty
#   string when its payload field is absent — never 0, which would render a
#   real "0%" meter for a session that has no quota data at all.
#
# Errors:
#   None surfaced. A payload without rate_limits parses cleanly to empty
#   strings; the segments that consume them are simply omitted downstream.
#
# Invariants:
#   - EXACTLY ONE jq invocation over the stdin payload per render, unchanged
#     from today. The settings.json compaction-budget fallback remains the
#     only other permitted jq, and only when the env var is unset.
#   - Fields are joined on \x1f, never tab and never \x01. Not tab, because
#     bash `read` collapses runs of IFS whitespace, so an absent field
#     between two present ones would swallow the next column and misalign
#     everything after it; with eight frequently-absent fields added, that is
#     load-bearing rather than defensive. Not \x01, because bash 3.2 reserves
#     it as an internal quoting sentinel and cannot split on it at all, which
#     renders the whole statusline empty on macOS — see the B18 contract
#     above sl_parse_input.
#   - The warm render still opens nothing under CLAUDE_PROJECTS_DIR and
#     still invokes no git. It now also invokes no ccost.sh by construction
#     rather than by cache freshness.
#
# Edge cases:
#   - rate_limits absent entirely (API-key, Bedrock, Vertex, or Claude Code
#     older than 2.1): all four rate-limit variables empty; every other
#     field still parses correctly despite the four-column gap.
#   - five_hour present but seven_day absent (or the reverse): only the
#     absent pair is empty.
#   - used_percentage arriving as a float (23.5): preserved as given; the
#     rounding decision belongs to the renderer, not the parser.
#   - A pre-existing six-key bundle from the previous plugin version: read
#     as valid, its cost_line ignored.
#   - total_lines_added/removed absent: empty, distinguishable from a real 0
#     (a session that has genuinely changed nothing renders no +/- segment
#     either way, but the parser must not invent the zero).
sl_parse_burn_fields() {
  # Superseded: sl_parse_input's single jq invocation now parses these eight
  # fields directly (Behavior clause 1 above), so this function is no longer
  # called from there. Left as a harmless no-op -- not re-assigning the
  # variables to "" here matters, since a caller invoking this by name after
  # sl_parse_input would otherwise wipe out already-parsed real values.
  return 0
}

# Contract: B05 burnrate-line (plan 001-statusline-burnrate-uplift),
#           amended by B09 burn-line-labels (plan 002-statusline-emoji-removal),
#           amended by B16 burn-line-colour-wiring (plan 003-statusline-meter-colour)
#
# Behavior:
#   Assembles the entire burnrate line and echoes it as one string with no
#   trailing newline. Replaces what were three separate rendered lines (the
#   mode/model/effort line, the Ctx-usage line, and the Cost line) with the
#   single line the plugin now shows beneath the path line:
#
#     Fable 5 high │ wk 32% 72%t 17%/d ▼-11 │ ctx 10% +503/-16 │ 5h 1% (4h54m)
#
#   FOUR groups joined by a dim │ separator:
#     1. model    the model name in its drifting rainbow, and the effort
#                 tier in its own colour. NO mascot prefix.
#     2. weekly   `wk` used%, today's remaining share (%t), sustainable pace
#                 (%/d), and the trend arrow vs the awake even-burn line
#     3. session  `ctx` context occupancy, and lines added/removed this session
#     4. 5-hour   `5h` used%, and the countdown to its reset IN PARENS
#
# B09 amendment — this line emits no emoji:
#   - The three meter emoji become bare ASCII labels: 🎯 -> `wk`, 🧠 -> `ctx`,
#     🔥 -> `5h`. Each label sits INSIDE its meter's colour sequence exactly
#     where the emoji did, so the colour still spans label and figure
#     together and no group gains or loses a reset.
#   - Group 1 drops the `$BURN_MASCOT ` prefix. The rainbow, the model-name
#     trim at " (", and the effort colour are untouched.
#   - Group 5 (the pet) is deleted outright, along with the stress-scan loop
#     that fed it. `_sl_burn_group` already omits an absent group's
#     separator, so the line simply ends after the 5-hour group — it must
#     never end with a dangling │.
#   - The 5-hour countdown is wrapped in parens: `5h 1% (4h54m)`. Without
#     them `5h 1% 4h54m` reads as two durations rather than a meter and its
#     reset. The parens are OUTSIDE any colour sequence burn_reset_str
#     returns, and appear only when a countdown is actually rendered — a
#     missing or unparseable reset drops the countdown and its parens
#     together, never leaving an empty `()`.
#   - Ambiguous-width non-emoji symbols are DELIBERATELY unchanged: the dim
#     │ separator and the ▲/▼ trend arrows stay exactly as they are.
#
# B09 amendment 2 — the weekly and 5-hour figures render as INTEGERS:
#   Both meters currently take the integer part for the COLOUR and then print
#   the value exactly as the payload sent it:
#     weekly  `$(burn_plan_color "${r7%%.*}")🎯 ${r7}%$rst`
#     5-hour  `$(burn_plan_color "${r5%%.*}")🔥 ${r5}%$rst`
#   B04's parse contract preserves a float used_percentage as given (see its
#   docblock), which is correct there — the payload is the source of truth. But
#   the payload delivers IEEE-754 noise, and the render shows it verbatim:
#   `5h 14.000000000000002%` is a real observed render, not a hypothetical.
#
#   Both figures therefore print the INTEGER PART, the same value the colour
#   already uses. Requirements:
#     - The printed number and the colour threshold read the SAME value, so
#       they can never disagree at a boundary. This is why the rule is
#       truncation and not rounding: rounding 49.7 to 50 while colouring it as
#       49 would put a figure in the wrong colour band.
#     - A sub-1% value renders `0`, never an empty figure: `0.5` renders
#       `5h 0%`. (`${r5%%.*}` of `0.5` is already `0`; only a leading-dot
#       `.5` expands EMPTY. JSON number syntax requires a digit before the
#       point, so that form is unreachable from a payload and a guard against
#       it is defensive rather than required. Corrected from this amendment's
#       first wording, which named `0.5` as the empty case.)
#     - An integer-valued payload is unaffected: `14` renders `14`, and no
#       trailing `.` or `.0` may appear.
#     - This changes presentation ONLY. No threshold, no colour, no parse
#       behaviour, and no other group moves. The `ctx` meter is NOT touched:
#       its `pct` is bash integer arithmetic and cannot carry a fraction.
#
#   Composes B01 (burn_metrics), B02 (burn_tick_frac), and B03 (all
#   presentation) over B04's parsed fields. It performs no arithmetic and no
#   colour selection of its own — every number comes from B01/B02 and every
#   colour from B03.
#
# B16 amendment — every value on this line carries colour:
#   Three values render with NO SGR at all today (#307), and the ctx meter
#   renders green at every occupancy (#306). B16 closes both by sourcing four
#   more colours from B03. The line's SHAPE does not move: same four groups,
#   same dim │ separators, same omission rules, same integer truncation of r5
#   and r7, one string on stdout with no trailing newline. The ONLY observable
#   difference is which bytes of SGR appear.
#
#   - Group 2's trend. The arrow and its magnitude are wrapped in
#     `burn_trend_color "$m_trend"` ... `$rst`. The ARROW STAYS: `▲`/`▼` are
#     chosen in this function, exactly as today, and B14's +/-3 dead band is
#     expressed as the green tier — the upstream's on-track ✓ is deliberately
#     NOT adopted, so no new codepoint appears anywhere on this line.
#   - Group 3's ctx meter. Its colour moves from burn_ctx_state's COLOR field
#     to `burn_ctx_color "$pct"`, so the meter finally warns as the context
#     fills. burn_ctx_state itself is untouched and still runs: its LEVEL
#     feeds .local/.ctx-status.json, and the published tier and the on-screen
#     colour now answer different questions on purpose — "how stale" and "how
#     full". At the ctx computation further down this file that means
#     `read -r level ctx_color <<< ...` becomes `read -r level _ <<< ...`, and
#     the `ctx_color=40` default is deleted rather than left unread.
#   - Group 3's line counts. `+N` takes `burn_diff_color add` and `-M` takes
#     `burn_diff_color del`, each closed with its own $rst so the two halves
#     never bleed into one another. The `/` between them is uncoloured. The
#     rule that the pair appears only once a count is above zero is UNCHANGED.
#   - Group 4's countdown. `($countdown)` is wrapped in
#     `burn_countdown_color` ... `$rst`, PARENS INCLUDED, so the whole
#     subordinate clause dims together and the eye reaches `5h 20%` first. The
#     rule that a missing or unparseable reset drops the countdown and its
#     parens together — never leaving an empty `()` — is unchanged.
#
#   Consequence worth stating, because it is a contract the next reader will
#   check: this removes the LAST hand-typed ${esc}[38;5;Nm from this function.
#   The "three escape shapes" note at the top of the body becomes two —
#   $_sl_burn_sep and $rst — and any 38;5; sequence reappearing here is a bug
#   by the same standard as before.
#
#   The SEPARATING SPACE between a value and the one before it sits OUTSIDE
#   the colour opener, in all four cases above: `"$g $(burn_diff_color add)+$n$rst"`,
#   never `"$g$(burn_diff_color add) +$n$rst"`. This is the minimal diff from
#   today's `g="$g +N/-M"` and it is what "the ONLY observable difference is
#   which bytes of SGR appear" requires — a space moved inside an opener is a
#   different byte sequence for the same glyph. The tests pin all four
#   byte-exactly, so this is not a matter of taste at implementation time.
#
#   Degradation is stated as an OUTCOME, not a mechanism: an install missing
#   lib/burn-theme.sh renders exactly today's uncoloured line — exit 0, nothing
#   on stderr, no partial sequence, no leaked or locally-invented colour. It
#   does NOT prescribe a `declare -f` guard, because this function does not use
#   one for colour helpers: burn_rainbow, burn_effort_color, burn_plan_color,
#   burn_today_color and burn_pace_color are all called BARE today, and their
#   "command not found" cannot reach the user because the single call site
#   drops this function's stderr by design (`burn_line=$(sl_render_burn_line
#   2>/dev/null)`, with its own note explaining why). Measured, not assumed: a
#   bare-call build of all four new calls, run against an install with
#   burn-theme.sh absent, exits 0 with 0 bytes on stderr and not one 38;5;
#   sequence on the line. Guard them or don't; the clause is the outcome.
#   No threshold is decided here; all four live in B03.
#
# Inputs:
#   Reads the variables B04 populates (r5, r5_reset, r7, r7_reset,
#   lines_added, lines_removed, total_cost_usd, session_id, model_name,
#   effort), plus used_tokens, ctx_budget and idle_seconds from the live Ctx
#   computation, the shared $_sl_now, and the local time-of-day seconds used
#   to derive the day-start anchor.
#
#   Two environment knobs, both consumed here and passed down to B01. They
#   carry the plugin's PUBLIC env prefix, as every user-settable knob here
#   does; the bare SL_* spellings are internal locals seeded from them, the
#   same split CLAM_STATUSLINE_CACHE_DIR -> SL_CACHE_DIR already uses:
#     CLAM_STATUSLINE_DAY_START     hour the user's day flips, 0..23 (default 2)
#     CLAM_STATUSLINE_SLEEP_HOURS   hours after that counted as sleep (default 6)
#   A non-integer or out-of-range value for either falls back to its
#   default rather than erroring. Zero-padded values are read as DECIMAL:
#   "08" is a user writing an hour correctly, not octal.
#
# Outputs:
#   One line of text on stdout, no trailing newline, ANSI-coloured.
#
#   Each group is omitted ENTIRELY, along with its separator, when its data
#   is unavailable — so the line never shows a dangling │, a stray label
#   with no number, or a leading/trailing separator. A session with no
#   rate_limits at all renders groups 1 and 3 only.
#
#   The +N/-M sub-segment appears only once at least one of the two counts
#   is above zero; a session that has edited nothing shows no counts rather
#   than "+0/-0".
#
# Errors:
#   Never fails the render. Any component returning non-zero — B01 unable to
#   compute, B02's state file unwritable, a missing reset timestamp — drops
#   that figure or its whole group and the rest of the line still renders.
#   Nothing is ever written to stdout except the line itself.
#
# Invariants:
#   - The ctx meter keeps this plugin's occupancy math
#     (total_input_tokens / CLAUDE_CODE_AUTO_COMPACT_WINDOW, non-saturating)
#     rather than the upstream's .context_window.used_percentage. Decided in
#     .local/decisions/002-context-meter-source.md: that field saturates at
#     100 and tracks the model's full window, and the token math runs
#     regardless to feed .local/.ctx-status.json — displaying the payload
#     field would publish one number and show another.
#     B16 amends only where the meter's COLOUR comes from, never the number:
#     the numerator, the budget resolution and the non-saturating division are
#     untouched, and the idle-aware tier survives intact as the published
#     `level`. What changed is that the tier stopped deciding the colour —
#     which is #306, a meter that never warned because it was answering a
#     different question from the one it appeared to answer.
#   - The clam mode does NOT appear on this line. It renders on the path
#     line beside the State segment, per
#     .local/decisions/001-clam-mode-placement.md, so the burnrate line is
#     exactly the four groups above.
#   - Warm-render process budget, raised from 10 to 12 external commands and
#     measured by the PATH-shim harness in context.test.sh: the pre-uplift
#     warm render measured 8, and this line adds at most three — two awk
#     (one in B01, one in B02) and one date (local time-of-day for the
#     day-start anchor, alongside the existing shared UTC date). Within
#     that: exactly one jq, at most two date, at most two awk, and still no
#     git, no ccost.sh, and nothing opened under CLAUDE_PROJECTS_DIR.
#   - Rate-limit figures are LIVE on every render, never cached — they are
#     server-side quota state and a stale one is worse than none.
#
# Edge cases:
#   - No rate_limits in the payload: groups 2 and 4 vanish with their
#     separators; groups 1 and 3 render normally.
#   - Weekly data present but its reset timestamp absent: `wk` used% still
#     renders; %t, %/d and the trend do not (all three need the reset).
#   - B01 returning NA for today's share (a degenerate slice): the %t
#     sub-segment is omitted while pace and trend still render.
#   - Context occupancy over 100% (an overrun): renders above 100 rather
#     than clamping — the whole reason this plugin computes it itself. Under
#     B16 it renders red, via the same >=60 tier as any lesser overrun.
#   - Model name carrying a parenthesised suffix ("Opus 5 (1M context)"):
#     trimmed at " (" before colouring, so the line stays short.
#   - Every group empty (a payload with nothing but a cwd): echoes the empty
#     string, and the caller prints no line at all rather than a bare
#     newline.
#   - A session that has edited nothing: the +N/-M pair is absent, so
#     burn_diff_color is never called and group 3 is `ctx` alone. B16 adds no
#     colour to a segment that does not render.
#   - A trend of exactly 0 (`▲0`, which this line does print): green, inside
#     B14's dead band. The arrow is still `▲` — the sign test that picks it is
#     untouched.
#     CORRECTION (orchestrator, mid-dispatch): an earlier draft of this clause
#     claimed "a zero trend has never printed `▼`". That is FALSE, and the
#     correction is measured rather than reasoned. B01's burn_metrics signs its
#     output, so a trend landing in [-0.5, 0) prints `-0`, not `0`; sweeping
#     every integer used% from 0 to 100 through burn_metrics produces `-0` at
#     one of them and a bare `0` at none. The arrow test below matches on the
#     leading `-` (`case "$m_trend" in -*)`), so that session renders `▼-0` on
#     screen today and still will after B16. The COLOUR clause is unaffected:
#     burn_trend_color "-0" takes the |T| <= 3 dead band and returns green 40,
#     the same answer it gives `0`. Nothing in B16 changes because of this; the
#     prose was simply wrong and the next reader would have trusted it.
#   - lib/burn-theme.sh absent from an install: all four new colours are
#     skipped and the line renders exactly as it does today, uncoloured in
#     those four places, with no partial sequence and no stray reset.
sl_render_burn_line() {
  # Every COLOUR on this line is B03's choice; no threshold or palette is
  # decided here. Two escape shapes are still typed out below, neither of
  # them a colour decision:
  #   $_sl_burn_sep -- the dim group separator, which B03 offers no helper
  #     for. "Dim" in the Outputs clause above is SGR 2.
  #   $rst -- the closing half of B03's sequences. burn_plan_color and its
  #     siblings each echo a bare SGR OPENER, so closing it is the caller's
  #     job.
  # Anything beyond those two is a bug: it means a colour was picked here
  # instead of in burn-theme.sh.
  local rst=$'\033[0m'
  local _sl_burn_acc="" g frame

  # One animation frame per render, shared by the rainbow and the pet. The
  # frame file sits in the segment-cache dir, which the bundle write already
  # created, so the warm path spends no `mkdir` of its own on it. An
  # unwritable path freezes the animation rather than failing (B03).
  frame=1
  if declare -f burn_frame_advance >/dev/null 2>&1; then
    frame=$(burn_frame_advance "$SL_CACHE_DIR/.burn-frame")
  fi

  # --- group 1: model name, effort tier --------------------------------------
  g=""
  if [ -n "$model_name" ] && declare -f burn_model_style >/dev/null 2>&1; then
    # BARE call, never $(burn_model_style ...): it sets BURN_HUES as a global
    # and echoes nothing, so a subshell capture would discard exactly what the
    # line below reads.
    burn_model_style "$model_name"
    # "Opus 5 (1M context)" is trimmed at " (": the suffix costs a third of
    # the line's width and says nothing the meters do not.
    g="$(burn_rainbow "${model_name%% (*}" "$frame")"
  fi
  if [ -n "$effort" ]; then
    [ -n "$g" ] && g="$g "
    g="$g$(burn_effort_color "$effort")$effort$rst"
  fi
  _sl_burn_group "$g"

  # --- group 2: weekly limit (wk used%, %t, %/d, trend) ----------------------
  g=""
  if [ -n "$r7" ]; then
    g="$(burn_plan_color "${r7%%.*}")wk ${r7%%.*}%$rst"
    if [ -n "$r7_reset" ]; then
      local hour slp ds frac metrics m_today m_pace m_trend arrow
      # The awake-hours knobs, both passed straight down to B01. A
      # non-integer (the leading "-" of a negative included) or out-of-range
      # value falls back to its default rather than erroring. The 10# is not
      # decoration: a perfectly reasonable "08" is OCTAL to bash arithmetic,
      # and an unforced one aborts the multiplication below -- silently
      # dropping %t, %/d and the trend for a value the user wrote correctly.
      hour="${CLAM_STATUSLINE_DAY_START:-2}"
      case "$hour" in ''|*[!0-9]*) hour=2 ;; *) hour=$(( 10#$hour )) ;; esac
      [ "$hour" -gt 23 ] && hour=2
      slp="${CLAM_STATUSLINE_SLEEP_HOURS:-6}"
      case "$slp" in ''|*[!0-9]*) slp=6 ;; *) slp=$(( 10#$slp )) ;; esac
      [ "$slp" -gt 23 ] && slp=6

      ds=$(_sl_burn_day_start "$hour")
      if [ -n "$ds" ]; then
        # The sub-tick fraction refines %t only, and only when the payload
        # carries the session cost it is estimated from; without one B02 has
        # nothing to measure, so skip the call rather than let it re-anchor
        # (and re-write its state file) on every render.
        frac=0
        if [ -n "$total_cost_usd" ] && declare -f burn_tick_frac >/dev/null 2>&1; then
          frac=$(burn_tick_frac "$r7" "$session_id" "$total_cost_usd" "$_sl_burn_tick_file")
          [ -n "$frac" ] || frac=0
        fi
        # burn_metrics echoes "TODAY PACE TREND" or, when it cannot compute
        # (a reset already past, a degenerate week), nothing at all -- in
        # which case all three derived figures drop and 🎯 used% stays.
        metrics=$(burn_metrics "$r7" "$frac" "$_sl_now" "$r7_reset" "$ds" "$(( slp * 3600 ))")
        if [ -n "$metrics" ]; then
          read -r m_today m_pace m_trend <<< "$metrics"
          # NA is B01 saying today's slice is degenerate, not a figure to
          # render; pace and trend survive it.
          [ "$m_today" != "NA" ] \
            && g="$g $(burn_today_color "$m_today")${m_today}%t$rst"
          g="$g $(burn_pace_color "$m_pace")${m_pace}%/d$rst"
          # Ahead of the even-burn line points up. The magnitude is printed as
          # B01 signs it, so a negative trend reads "▼-11".
          case "$m_trend" in -*) arrow='▼' ;; *) arrow='▲' ;; esac
          g="$g $(burn_trend_color "$m_trend")$arrow$m_trend$rst"
        fi
      fi
    fi
  fi
  _sl_burn_group "$g"

  # --- group 3: session (ctx occupancy, lines touched) -----------------------
  g=""
  if [ -n "$pct" ]; then
    g="$(burn_ctx_color "$pct")ctx ${pct}%$rst"
    # Only once at least one count is above zero: a session that has edited
    # nothing shows nothing, not "+0/-0". Each half closes with its OWN
    # reset so neither bleeds into the other; the "/" between them is
    # deliberately uncoloured.
    if [ "${lines_added:-0}" -gt 0 ] 2>/dev/null \
      || [ "${lines_removed:-0}" -gt 0 ] 2>/dev/null; then
      g="$g $(burn_diff_color add)+${lines_added:-0}$rst/$(burn_diff_color del)-${lines_removed:-0}$rst"
    fi
  fi
  _sl_burn_group "$g"

  # --- group 4: 5-hour limit (5h used%, countdown) ---------------------------
  g=""
  if [ -n "$r5" ]; then
    g="$(burn_plan_color "${r5%%.*}")5h ${r5%%.*}%$rst"
    # A missing reset drops the countdown ONLY -- the used% is live quota
    # state, exactly as the weekly group keeps its wk figure without one.
    if [ -n "$r5_reset" ]; then
      local countdown
      countdown=$(burn_reset_str "$r5_reset" "$_sl_now") \
        && [ -n "$countdown" ] \
        && g="$g $(burn_countdown_color)($countdown)$rst"
    fi
  fi
  _sl_burn_group "$g"

  printf '%s' "$_sl_burn_acc"
}

# The dim group separator, and the accumulator helper that places it. The
# separator goes only BETWEEN present groups, so a group that vanishes takes
# its separator with it and the line never shows a dangling │.
_sl_burn_sep=$'\033[2m│\033[0m'

# _sl_burn_group GROUP -- append GROUP to the line under assembly. The
# accumulator is sl_render_burn_line's own $_sl_burn_acc local, visible here
# through bash's dynamic scoping; this exists only to keep that function's
# five group blocks free of the same four lines of join bookkeeping.
_sl_burn_group() { # group
  [ -z "$1" ] && return 0
  [ -n "$_sl_burn_acc" ] && _sl_burn_acc="$_sl_burn_acc $_sl_burn_sep "
  _sl_burn_acc="$_sl_burn_acc$1"
  return 0
}

# _sl_burn_day_start HOUR -> epoch of the current day's start, or nothing when
# the clock cannot be read. Spends the render's SECOND and last `date` on the
# seconds-into-the-LOCAL-day figure B01 needs: one `date` invocation carries
# one timezone, and the shared $_sl_now has to be UTC because
# .ctx-status.json's fetched_at is. Called only from the weekly group, so a
# payload with no weekly data never pays for it.
_sl_burn_day_start() { # hour
  local h m s
  read -r h m s <<< "$(date +'%H %M %S')"
  case "$h$m$s" in ''|*[!0-9]*) return 1 ;; esac
  burn_day_start_epoch "$_sl_now" "$(( 10#$h * 3600 + 10#$m * 60 + 10#$s ))" "$1"
}
# ------------------------------------------------------------------------

# Read JSON input from stdin. `read -d ''` (bash 3.2-safe) slurps the whole
# payload into $input via the builtin instead of forking `cat` for it: NUL is
# the delimiter, and none appears in a JSON payload, so read runs to EOF and
# returns non-zero -- expected here, not an error -- while $input still gets
# the full payload, including a final line with no trailing newline.
IFS= read -r -d '' input || true

# Portable dirname via parameter expansion (dirname forks a process; the
# $(...) below is a subshell, not an exec, so it's free per the budget).
# Mirrors dirname(1) for our one use case (a BASH_SOURCE path): strip the
# last path component; a slash-free path (e.g. invoked as `bash context.sh`
# from its own directory) has nothing to strip, so ${var%/*} would leave it
# unchanged -- guard that case to "." like dirname does.
_sl_dirname() {
  local p="$1" d="${1%/*}"
  [ "$d" = "$p" ] && d="."
  printf '%s' "$d"
}

# Shared lib dir: session-State metadata plus the cache-refresh engines.
_LIB_DIR="$(cd "$(_sl_dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)"
_STATES_LIB="$_LIB_DIR/states.sh"
[ -f "$_STATES_LIB" ] && . "$_STATES_LIB"

# Burnrate line libraries (B01 pacing math, B02 sub-tick interpolation, B03
# presentation). `.` is a builtin, so sourcing three more files costs the
# warm-render process budget nothing. Each is optional at load time: a
# missing file leaves its functions undefined and sl_render_burn_line omits
# the groups that need them, exactly as it does for absent payload data.
for _burn_lib in burn-math.sh burn-tick.sh burn-theme.sh; do
  [ -f "$_LIB_DIR/$_burn_lib" ] && . "$_LIB_DIR/$_burn_lib"
done
unset _burn_lib

SCRIPT_DIR="$(cd "$(_sl_dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/platform.sh"

# Resolve the OS ONCE for the whole render (clam_os forks `uname`); the two
# warm-path mtime reads below (bundle freshness in sl_bundle_read, transcript
# idle age further down) reuse $_sl_os via _sl_mtime_epoch instead of each
# re-deriving it through clam_mtime_epoch's own clam_os call. Cold-path-only
# mtime reads (file_age, used solely by the refresh-engine kicks) keep
# calling clam_mtime_epoch/platform.sh directly -- that path isn't in the
# warm-render budget.
_sl_os="$(clam_os)"

# Call-site-local mtime reader for the two warm-path reads: same semantics as
# platform.sh's clam_mtime_epoch (missing/unstatable -> 0, silent) but
# branches on the already-memoized $_sl_os instead of re-forking `uname` per
# call. Pre-branched, never a chained `stat -f ... || stat -c ...`, for the
# same reason clam_mtime_epoch is: on GNU coreutils `-f` means "filesystem
# status" (df-like), not a format flag, so a BSD-style `stat -f` call there
# doesn't just fail, it prints a filesystem dump that would corrupt anything
# capturing the combined output before the `||` fallback fires.
_sl_mtime_epoch() {
  if [ "$_sl_os" = "darwin" ]; then
    stat -f %m "$1" 2>/dev/null || echo 0
  else
    stat -c %Y "$1" 2>/dev/null || echo 0
  fi
}

sl_parse_input

# B02's sub-tick anchor file, keyed exactly as the segment bundle is (the
# transcript path, falling back to the cwd) so two sessions never share an
# anchor. It lives in the segment-cache dir the bundle write already creates,
# which is what keeps the burnrate line's scratch state off the warm render's
# process budget: no `mkdir` of its own, and an unwritable path just degrades
# the interpolation to a zero fraction.
_sl_burn_tick_key="$transcript_path"
[ -z "$_sl_burn_tick_key" ] && _sl_burn_tick_key="$cwd"
_sl_burn_tick_file="$SL_CACHE_DIR/${_sl_burn_tick_key//\//_}.tick"

# Age of a file in seconds (missing file reads as very old). Only used by
# the refresh-engine kicks below, which are cold-path-only; the live parts
# of the render (idle age, bundle freshness) share $_sl_now instead so they
# never fork their own `date`.
file_age() {
  local m
  m=$(clam_mtime_epoch "$1")
  echo $(( $(date +%s) - m ))
}

# Contract: B10 line1-text-tags (plan 002-statusline-emoji-removal)
#
# Classify a PR into its statusline TAG. Same rules as the /pr-status skill.
# Renamed from classify_pr_emoji; the bucket logic below is unchanged
# byte-for-byte, only what each bucket echoes changes. Callers must be
# updated with it — no compatibility alias is kept, because a stale caller
# comparing against an emoji would silently fall through to the actionable
# branch and badge every PR.
#
# Args: $1=state $2=reviews $3=ci $4=comments
# Echoes exactly one of: merged | queued | ejected | todo | wip | ok
#   merged   was ✅   collapsed to a count
#   queued   was 🚂   collapsed to a count
#   ok       was 🟢   collapsed to a count
#   todo     was 🔴   rendered per-PR, needs the user
#   wip      was 🟡   rendered per-PR, parked but fine
#   ejected  was 🚫   rendered per-PR, queue ejected it
#
# The three collapsed buckets render as "N ok", "N queued", "N merged"; the
# three per-PR buckets render as "todo #123", "wip #123", "ejected #123",
# keeping the OSC-8 hyperlink on the "#123" so the number stays clickable.
# Colours are unchanged — the tag carries the same SGR the emoji did.
#
# SCAFFOLD STATE: the definition below still carries the OLD name and still
# echoes emoji. That gap — contract renamed and re-specified above, code
# unchanged beneath — is what the test wave goes red against. Renaming the
# definition here would break the caller at once and produce a broken render
# rather than a clean red.
classify_pr_tag() {
  local state="$1" reviews="$2" ci="$3" comments="$4"
  if [ "$state" = "Merged" ]; then
    echo "merged"
  elif [ "$state" = "Queue Failed" ]; then
    # Queue ejected the PR; needs author attention before re-enqueue.
    echo "ejected"
  elif [ "$state" = "In Queue" ]; then
    # Passive wait while queue CI runs against the queue head.
    echo "queued"
  elif [ "$ci" = "Fail" ] \
    || [ "$reviews" = "Changes Requested" ] \
    || [ "$reviews" = "Commented" ] \
    || [ "$reviews" = "Not Requested" ] \
    || [ "${comments:-0}" -gt 0 ] \
    || { [ "$reviews" = "Approved" ] && [ "$ci" = "Pass" ]; }; then
    echo "todo"
  elif [ "$state" = "Draft" ] \
    || [ "$reviews" = "Approved (stale)" ] \
    || { [ "$reviews" = "Approved" ] && [ "$ci" = "Running" ]; }; then
    echo "wip"
  else
    echo "ok"
  fi
}

# Wrap text in an OSC 8 hyperlink so terminals (Alacritty 0.7+, iTerm2,
# WezTerm) make it Ctrl+Clickable. tmux 3.4+ passes the sequence through.
# In terminals that ignore OSC 8, the visible text is unchanged.
# Args: $1=url $2=text
osc8_link() {
  local url="$1" text="$2"
  if [ -z "$url" ]; then
    printf '%s' "$text"
  else
    printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$url" "$text"
  fi
}

# Single shared "now" (epoch + RFC3339 UTC), from ONE `date` call for the
# whole render: the bundle-freshness check below, the Ctx line's idle-age
# calc, and the .ctx-status.json fetched_at field all read off the same
# instant instead of each forking their own `date` — part of what keeps a
# warm render's process count inside the ≤10-command budget.
_sl_now_pair=$(date -u +'%s %Y-%m-%dT%H:%M:%SZ')
_sl_now="${_sl_now_pair%% *}"
_sl_now_iso="${_sl_now_pair#* }"
unset _sl_now_pair

# Resolve the git worktree root by walking up from $cwd looking for a .git
# entry (a directory in a normal clone, a file in a worktree) instead of
# shelling out to `git rev-parse --show-toplevel`. The LIVE .ctx-status.json
# publish below needs to know, on EVERY render including warm ones, whether
# $cwd sits in a worktree with .local — and the warm path may not invoke
# git — so this walk stays pure bash (builtins only, no fork).
toplevel=""
if [ -n "$cwd" ]; then
  _sl_dir="$cwd"
  while [ -n "$_sl_dir" ]; do
    if [ -e "$_sl_dir/.git" ]; then
      toplevel="$_sl_dir"
      break
    fi
    [ "$_sl_dir" = "/" ] && break
    _sl_dir="${_sl_dir%/*}"
    [ -z "$_sl_dir" ] && _sl_dir="/"
  done
  unset _sl_dir
fi

# --- LIVE vs CACHED split ---------------------------------------------------
# Populates branch, pr_badge, git_sync_segment, state_segment, clam_mode. On
# a WARM render (sl_bundle_read succeeds) these come straight from the
# last-built bundle: no git, no ccost.sh, nothing under
# CLAUDE_PROJECTS_DIR touched. On a COLD render they're computed exactly as
# the pre-cache renderer did, then persisted for the next render — including
# the background refresh-engine kicks, which per contract only ever fire
# here, never on the warm path.
if ! sl_bundle_read; then
  # Get git branch
  branch=$(cd "$cwd" && git branch --show-current 2>/dev/null)

  # Resolve the PR status file at the worktree root, if any.
  pr_status_file=""
  if [ -n "$toplevel" ] && [ -f "$toplevel/.local/.pr-status.json" ]; then
    pr_status_file="$toplevel/.local/.pr-status.json"
  fi

  # Keep the .local caches warm. The Stop hooks only refresh at turn end, so a
  # parked session's badges would freeze; this render-time trigger kicks the
  # shared engines in a fully detached background process whenever a cache is
  # stale (or missing) and renders whatever is on disk now. Claude Code re-runs
  # this script on conversation events and on the settings.json statusLine
  # refreshInterval heartbeat, so the next render picks up the result. All fds
  # are detached from the spawn so the render never waits on it. Only reached
  # on a bundle rebuild (see contract Invariants): a warm render never gets
  # here, so these staleness checks never run on the warm path.
  # A young engine lock means a refresh is already in flight, so skip the fork;
  # the 120s cutoff mirrors the engines' stale-break threshold so a crashed
  # refresher's leftover lock cannot suppress spawns for good.
  if [ -n "$toplevel" ] && [ -d "$toplevel/.local" ] && [ -n "$_LIB_DIR" ]; then
    if [ -x "$_LIB_DIR/pr-status-refresh.sh" ] \
      && [ "$(file_age "$toplevel/.local/.pr-status.json")" -ge 300 ] \
      && [ "$(file_age "$toplevel/.local/.pr-status-refresh.lock")" -ge 120 ]; then
      ( nohup "$_LIB_DIR/pr-status-refresh.sh" "$toplevel" 300 </dev/null >/dev/null 2>&1 & ) 2>/dev/null
    fi
    if [ -x "$_LIB_DIR/git-sync-refresh.sh" ] \
      && [ "$(file_age "$toplevel/.local/.git-sync.json")" -ge 600 ] \
      && [ "$(file_age "$toplevel/.local/.git-sync-refresh.lock")" -ge 120 ]; then
      ( nohup "$_LIB_DIR/git-sync-refresh.sh" "$toplevel" 600 </dev/null >/dev/null 2>&1 & ) 2>/dev/null
    fi
  fi

  # Compute the PR badge per the /pr-status skill's color rules.
  # Every worktree emits a `prs` array (0, 1, or N entries) via pr-status-refresh.
  #
  # Contract: B10 line1-text-tags (plan 002-statusline-emoji-removal).
  # Render actionable PRs individually as `todo #N` / `wip #N` / `ejected #N`,
  # and collapse the rest to labelled counts `N ok` / `N queued` / `N merged`.
  # The case arms below dispatch on classify_pr_emoji's return value, so they
  # move to the tag strings in lockstep with the rename — an arm still
  # matching an emoji would fall through to the actionable branch and badge
  # every PR individually. CLOSED PRs remain skipped entirely, and the OSC-8
  # hyperlink stays on the "#N" so the number is still clickable.
  pr_badge=""
  if [ -n "$pr_status_file" ]; then
    prs_count=$(jq -r '(.prs // []) | length' "$pr_status_file" 2>/dev/null)
    if [ "${prs_count:-0}" -gt 0 ] 2>/dev/null; then
      green_count=0
      queued_count=0
      merged_count=0
      actionable=""
      while IFS=$'\t' read -r number state reviews ci comments url; do
        [ -z "$number" ] && continue
        # CLOSED PRs are abandoned, not actionable — skip entirely so they
        # neither badge nor count toward the totals.
        [ "$state" = "CLOSED" ] && continue
        tag=$(classify_pr_tag "$state" "$reviews" "$ci" "$comments")
        case "$tag" in
          merged) merged_count=$((merged_count + 1)) ;;
          queued) queued_count=$((queued_count + 1)) ;;
          ok)     green_count=$((green_count + 1)) ;;
          *)      actionable="$actionable $tag $(osc8_link "$url" "#$number")" ;;
        esac
      done < <(jq -r '.prs[] | [.number, .state, .reviews, .ci, (.comments // 0), (.url // "")] | @tsv' "$pr_status_file" 2>/dev/null)

      pr_badge="$actionable"
      [ "$green_count" -gt 0 ]  && pr_badge="$pr_badge $green_count ok"
      [ "$queued_count" -gt 0 ] && pr_badge="$pr_badge $queued_count queued"
      [ "$merged_count" -gt 0 ] && pr_badge="$pr_badge $merged_count merged"
    fi
  fi

  # Compute the git-sync segment (↓N ↑M) per PLAN-git-sync.md colour rules.
  git_sync_file=""
  if [ -n "$toplevel" ] && [ -f "$toplevel/.local/.git-sync.json" ]; then
    git_sync_file="$toplevel/.local/.git-sync.json"
  fi

  git_sync_segment=""
  if [ -n "$git_sync_file" ]; then
    behind=$(jq -r '.behind_count // 0' "$git_sync_file" 2>/dev/null)
    ahead=$(jq -r '.ahead_count // 0' "$git_sync_file" 2>/dev/null)
    # jq's `//` treats `false` as falsey, so we can't use `.fetch_ok // true` —
    # an explicit fetch_ok=false would be coerced to true. Check for null/missing
    # explicitly so a real `false` survives.
    fetch_ok=$(jq -r 'if .fetch_ok == null then "true" else .fetch_ok | tostring end' "$git_sync_file" 2>/dev/null)

    parts=""
    color=""
    if [ "${behind:-0}" -gt 0 ]; then
      parts="↓$behind"
      if [ "$behind" -ge 6 ]; then
        color=$'\033[38;5;196m'  # red
      else
        color=$'\033[38;5;214m'  # yellow
      fi
    fi
    if [ "${ahead:-0}" -gt 0 ]; then
      if [ -n "$parts" ]; then
        parts="$parts ↑$ahead"
      else
        parts="↑$ahead"
        color=$'\033[38;5;245m'  # dim — ahead-only is not actionable
      fi
    fi
    if [ -n "$parts" ]; then
      suffix=""
      if [ "$fetch_ok" != "true" ]; then
        suffix="?"
      fi
      git_sync_segment=" ${color}${parts}${suffix}"$'\033[0m'
    fi
  fi

  # Compute the worktree State segment from .local/TODO.md. The State: field is
  # the single axis the clam workflow uses to decide whether a session needs the
  # user, so surfacing it makes the current state glanceable from the statusline.
  # Colour mirrors the urgency classes in system-prompt.md (red 196: summons the
  # user; yellow 214: parked but fine; green 40/34: active or done; dim 245:
  # neutral). Same $toplevel resolution as the PR-status and git-sync segments.
  # Contract: B10 line1-text-tags (plan 002-statusline-emoji-removal).
  # The State glyph is REMOVED — the State's own name follows it and already
  # carries state_color's urgency colour, so the emoji labelled nothing the
  # text beside it did not. Two consequences the implementation must honour:
  #   - The `command -v` GATE moves from state_emoji to state_color. Today
  #     the whole segment hangs off state_emoji being defined; leaving that
  #     gate while dropping the call would keep an unnecessary dependency on
  #     a function with no remaining caller.
  #   - lib/states.tsv and lib/states.sh are NOT touched, in this plugin or
  #     any other. state_emoji() simply keeps no caller; it stays as a
  #     documented function of the shared States library. That is what keeps
  #     this a one-plugin change rather than a coordinated edit across the
  #     three byte-identical copies.
  # Spacing: the segment keeps its two-space lead-in, so removing the glyph
  # must not leave a double space before the State name.
  state_segment=""
  if [ -n "$toplevel" ] && [ -f "$toplevel/.local/TODO.md" ]; then
    state=$(todo_field "$toplevel/.local/TODO.md" State)
    if [ -n "$state" ] && command -v state_color >/dev/null 2>&1; then
      color_seq=$(printf '\033[38;5;%sm' "$(state_color "$state")")
      state_segment="  ${color_seq}${state}"$'\033[0m'
    fi
  fi

  # Clam session mode from .local/MODE (written once per worktree by /start).
  # Rendered without a whitelist: /start owns the mode roster, so new modes need
  # no lockstep edit here, and a corrupted file fails visible (odd text on the
  # line) rather than silent (vanished segment). Sanitization is defensive, not
  # semantic — first line only, non-printables stripped, capped at 24 chars — so
  # a crafted MODE file in a cloned repo cannot inject terminal escapes or flood
  # the line. [:print:] keeps spaces ("Go Commando" needs its internal one); the
  # trim then drops only leading/trailing whitespace. Same $toplevel gating as
  # the segments above.
  clam_mode=""
  if [ -n "$toplevel" ] && [ -f "$toplevel/.local/MODE" ]; then
    clam_mode=$(head -n 1 "$toplevel/.local/MODE" 2>/dev/null | tr -cd '[:print:]')
    clam_mode="${clam_mode#"${clam_mode%%[![:space:]]*}"}"
    clam_mode="${clam_mode%"${clam_mode##*[![:space:]]}"}"
    clam_mode="${clam_mode:0:24}"
  fi

  sl_bundle_write
fi
# ------------------------------------------------------------------------

# Live context computation. Shows real occupancy (total_input_tokens, the figure
# /context reports) against the operational budget: the auto-compaction window, which
# is where compaction actually fires. Two deliberate choices:
#   - Numerator is total_input_tokens, NOT used_percentage. used_percentage saturates
#     at 100, so it can never render an overrun (it read 100% while /context showed
#     253%).
#   - Denominator is CLAUDE_CODE_AUTO_COMPACT_WINDOW, NOT context_window_size. Once
#     that env var is set, the JSON's used_percentage/context_window_size track the
#     model's FULL window (1M on Opus 4.8), not the compaction budget — so source the
#     budget from the env var (then settings.json, then the reported window) to keep
#     the meter aligned with where compaction actually fires.
# Prints nothing itself: it feeds the burnrate line's 🧠 group below and the
# .local/.ctx-status.json publish, which is why it now runs AHEAD of the
# rendered lines rather than as a line of its own. $pct stays empty when
# occupancy cannot be computed, and that is what makes the 🧠 group vanish.
ctx_budget="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
if [ -z "$ctx_budget" ]; then
  ctx_budget=$(jq -r '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW // empty' "$HOME/.claude/settings.json" 2>/dev/null)
fi
ctx_budget="${ctx_budget:-$window_size}"
pct=""
used_tokens=""
idle_seconds=0
if [ -n "$total_input" ] && [ -n "$ctx_budget" ] && [ "$ctx_budget" -gt 0 ] 2>/dev/null; then
  used_tokens="$total_input"
  # Integer occupancy percent (floor). Deliberately NOT clamped at 100 — an
  # overrun reads >100, mirroring the numerator's non-saturating behaviour.
  pct=$(( 100 * used_tokens / ctx_budget ))

  # Idle seconds = time since the transcript's last append. Claude Code only
  # appends to the transcript, so its mtime marks the last real turn. Guard the
  # empty/missing case explicitly: file_age() would return a huge now-minus-0
  # value for a missing path and read as "infinitely cold", so only measure a
  # transcript that actually exists. Reuses the render's shared $_sl_now
  # rather than forking its own `date`, and $_sl_os (via _sl_mtime_epoch)
  # rather than forking its own `uname`.
  last_activity_epoch=0
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    last_activity_epoch=$(_sl_mtime_epoch "$transcript_path")
    idle_seconds=$(( _sl_now - last_activity_epoch ))
    # Clamp a negative idle (possible after an NTP backward step) to 0 so the
    # published idle_seconds is never negative for the agent-dash consumer.
    [ "$idle_seconds" -lt 0 ] && idle_seconds=0
  fi

  # The tri-state staleness tier — a big session turning orange as it cools and
  # red once the prompt cache is nearly lapsed — is B03's burn_ctx_state, which
  # yields "LEVEL COLOR". Both the 🧠 group's colour and the level published
  # below read off that single call, so the number on screen and the number in
  # .ctx-status.json cannot disagree. The thresholds are NOT restated here on
  # purpose: a second copy is exactly the drift that invariant exists to stop,
  # so an install missing lib/burn-theme.sh publishes the safe tier rather than
  # a private duplicate of the rules.
  level="ok"
  if declare -f burn_ctx_state >/dev/null 2>&1; then
    read -r level _ <<< "$(burn_ctx_state "$used_tokens" "$ctx_budget" "$idle_seconds")"
  fi

  # Publish the machine-readable context status for agent-dash (separate repo,
  # later chunk) to read across sessions. Inline + best-effort: gated on a git
  # worktree with a .local dir, written atomically (mktemp in-dir -> mv), and it
  # never errors the statusline on failure. printf only (no jq) — every value is
  # an integer or a fixed enum/ISO string, so there is nothing to escape.
  # An orphaned .ctx-status.json.XXXXXX temp (only possible if this process is
  # SIGKILLed between mktemp and mv) is harmless, gitignored clutter under
  # .local/ — same convention as the mktemp temps in git-sync-refresh.sh /
  # pr-status-refresh.sh, neither of which sweeps stale temps either.
  if [ -n "$toplevel" ] && [ -d "$toplevel/.local" ]; then
    _ctx_tmp=$(mktemp "$toplevel/.local/.ctx-status.json.XXXXXX" 2>/dev/null)
    if [ -n "$_ctx_tmp" ]; then
      if printf '{"context_tokens":%s,"budget":%s,"used_percentage":%s,"last_activity_epoch":%s,"idle_seconds":%s,"level":"%s","fetched_at":"%s"}\n' \
           "$used_tokens" "$ctx_budget" "$pct" "$last_activity_epoch" "$idle_seconds" "$level" "$_sl_now_iso" > "$_ctx_tmp" 2>/dev/null; then
        mv -f "$_ctx_tmp" "$toplevel/.local/.ctx-status.json" 2>/dev/null || rm -f "$_ctx_tmp" 2>/dev/null
      else
        rm -f "$_ctx_tmp" 2>/dev/null
      fi
    fi
  fi
fi

# Format the status line. Render $HOME as ~ so the path segment stays short
# (~ is kept literal; when $HOME is empty or $cwd is outside it, the full path
# shows unchanged). $cwd itself is left intact — it is still used for the git
# detection above.
cwd_display="$cwd"
if [ -n "$HOME" ]; then
  case "$cwd" in
    "$HOME"|"$HOME"/*) cwd_display="~${cwd#"$HOME"}" ;;
  esac
fi
printf '\033[38;5;39m%s\033[0m' "$cwd_display"

if [ -n "$branch" ]; then
  printf ' \033[38;5;245m(\033[0m%s\033[38;5;245m)\033[0m' "$branch"
fi

if [ -n "$pr_badge" ]; then
  printf '%s' "$pr_badge"
fi

if [ -n "$git_sync_segment" ]; then
  printf '%s' "$git_sync_segment"
fi

# Clam session mode, in teal, beside the State segment (decision
# 001-clam-mode-placement). It used to lead the mode/model/effort line, which
# the burnrate line replaces; line 1 is where it costs nothing, since the mode
# and the State segment come from the same cache bundle on the same TTL and so
# can never disagree about age. An empty mode prints nothing at all — not a
# stray separator or space.
if [ -n "$clam_mode" ]; then
  printf '  \033[38;5;37m%s\033[0m' "$clam_mode"
fi

if [ -n "$state_segment" ]; then
  printf '%s' "$state_segment"
fi

# The burnrate line (B05): the whole of what used to be three rendered lines
# (mode/model/effort, Ctx usage, Cost). It PREPENDS its newline rather than
# trailing one, so the status block ends on its last rendered line with no
# dangling blank line — which is why the path line above prints no trailing
# newline either. An empty result means every group vanished, and then no line
# is printed at all rather than a bare newline. stderr is dropped here because
# this script's stdout is the user's statusline and its stderr should not
# become a second channel; a component that cannot compute drops its figure.
burn_line=$(sl_render_burn_line 2>/dev/null)
if [ -n "$burn_line" ]; then
  printf '\n%s' "$burn_line"
fi

