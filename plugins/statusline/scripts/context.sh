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
  #
  # total_cost_usd is parsed but not read by anything in this file today: B05
  # retired the sub-tick interpolator that consumed it, and the contract keeps
  # the field rather than dropping a column a later block might need back.
  # session_id is read by B08's cache key and project_dir by B07's path
  # segment; project_dir is APPENDED LAST to both ends, which is what lets it
  # join the parse without moving any field before it.
  # shellcheck disable=SC2034  # parsed per contract; consumers live elsewhere
  IFS=$'\x1f' read -r window_size total_input transcript_path cwd model_name effort \
    r5 r5_reset r7 r7_reset total_cost_usd session_id project_dir <<< "$(
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
            ($p.cost.total_cost_usd // ""),
            ($p.session_id // ""),
            ($p.workspace.project_dir // "")
          ]
        | join("\u001f")
      '
  )"
  [ -z "$effort" ] && effort="${CLAUDE_EFFORT:-}"
}

# Contract: B08 cache-session-key (plan 001-statusline-glance-uplift)
#
# Behavior:
#   sl_cache_key derives the expensive-segment bundle's filename stem. It keys
#   on session_id — already parsed above, and documented by Claude Code as
#   "stable for the lifetime of a session and unique per session", which is
#   exactly what a cache key needs — instead of transcript_path, falling back
#   to the current directory when session_id is absent. Path separators are
#   flattened so the stem is a single filename component.
#
#   sl_cache_sweep bounds the cache directory, which today grows without
#   limit: it removes bundle and tick files whose mtime is older than
#   MAX_AGE_SECONDS. It runs on the COLD path only.
#
#   sl_bundle_read and sl_bundle_write are rewired onto sl_cache_key by this
#   block; neither their format, their atomic temp-plus-rename write, nor
#   their TTL semantics change.
#
# Inputs:
#   sl_cache_key SESSION_ID CWD
#     SESSION_ID  the payload's session_id, possibly empty
#     CWD         the current directory, used only as the fallback key source
#   sl_cache_sweep DIR MAX_AGE_SECONDS
#     DIR              the cache directory (CLAM_STATUSLINE_CACHE_DIR)
#     MAX_AGE_SECONDS  positive integer; 86400 (one day) at the call site
#
# Outputs:
#   sl_cache_key    echoes one filename stem, no slashes, never empty.
#   sl_cache_sweep  echoes nothing. Its effect is on the filesystem.
#   Neither changes any rendered text. The cache FILE's name changes; nothing
#   the user sees does.
#
# Errors:
#   Unchanged from today: an uncreatable or unwritable cache dir degrades to a
#   full cold render every time. A sweep failure is SILENT and never fails the
#   render — a statusline that cannot tidy its own cache still has a line to
#   draw.
#
# Invariants:
#   - The sweep runs on the COLD path only. The warm-render budget has no room
#     for it, and a warm render must still open nothing it did not open
#     before.
#   - Two different sessions never share a bundle.
#   - A corrupt or partially written bundle is still treated as absent.
#   - bash 3.2 compatible.
#
# Edge cases:
#   - An absent or empty session_id: falls back to the cwd key, and the bundle
#     is still cached rather than disabled.
#   - Bundles left behind under the old transcript_path key: aged out by the
#     same sweep rather than migrated. There is nothing in them worth keeping.
#   - A clock step making a bundle future-dated: still reads fresh, unchanged
#     from today.
#   - TTL <= 0 disables cache serving, unchanged.
#
# sl_cache_key SESSION_ID CWD
sl_cache_key() {
  # session_id first: it is stable for the session's lifetime and unique per
  # session, so two sessions in one worktree get two bundles and one session
  # moving between worktrees keeps its own. The cwd is only the fallback, and
  # the literal below only the fallback's fallback -- the stem is never empty,
  # because an empty stem would name the cache dir itself.
  local src="$1"
  [ -z "$src" ] && src="$2"
  [ -z "$src" ] && src="default"
  # Flattened to ONE filename component. A session_id has no slashes in
  # practice and a cwd is nothing but slashes; both go through the same
  # substitution so neither can escape the cache dir.
  printf '%s' "${src//\//_}"
}

# sl_cache_sweep DIR MAX_AGE_SECONDS
sl_cache_sweep() {
  # Bundle and tick files only, by name: a cache dir is a directory like any
  # other and something else's file in it is not this function's to delete.
  # Ages are compared in whole seconds against the render's shared $_sl_now,
  # so the sweep forks no `date` of its own; the per-file `stat` is
  # _sl_mtime_epoch's and this runs on the COLD path only, where the warm
  # budget does not apply. One `rm` for the whole batch, and every failure
  # silent -- a statusline that cannot tidy its cache still has a line to draw.
  local dir="$1" max="$2" f mtime cutoff
  local -a stale
  [ -d "$dir" ] || return 0
  case "$max" in ''|*[!0-9]*) return 0 ;; esac
  cutoff=$(( _sl_now - max ))
  stale=()
  for f in "$dir"/*.bundle "$dir"/*.tick; do
    [ -f "$f" ] || continue
    mtime=$(_sl_mtime_epoch "$f")
    [ "$mtime" -lt "$cutoff" ] || continue
    stale[${#stale[@]}]="$f"
  done
  [ "${#stale[@]}" -gt 0 ] && rm -f "${stale[@]}" 2>/dev/null
  return 0
}

# sl_bundle_read: emit the cached expensive-segment bundle for the current
# session key iff it is fresh (age < SL_SEGMENT_TTL_SECONDS); non-zero exit
# when stale, absent, corrupt, or caching is disabled (TTL <= 0).
#
# Reads its cache key from sl_cache_key (session_id, falling back to cwd; both
# populated by sl_parse_input) and the shared "now" epoch ($_sl_now) so it
# never forks its own `date`.
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
  local ttl key file mtime age line got
  ttl="$SL_SEGMENT_TTL_SECONDS"
  [[ "$ttl" =~ ^-?[0-9]+$ ]] || ttl=5
  [ "$ttl" -le 0 ] && return 1

  key=$(sl_cache_key "$session_id" "$cwd")
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
  local key tmp
  key=$(sl_cache_key "$session_id" "$cwd")
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

# Contract: B05 line2-groups (plan 001-statusline-glance-uplift)
#
# This is the COMPOSITION block for line 2: its contract is about how B01-B04
# compose into a rendered line, not about any figure in isolation. It
# supersedes the previous B05 burnrate-line contract (plan
# 001-statusline-burnrate-uplift, amended by plans 002 and 003) entirely.
#
# Behavior:
#   Assembles line 2 and echoes it as one string with no trailing newline.
#   FOUR groups joined by the existing dim │ separator:
#
#     Fable 5 high │ ctx 10% │ 5h 1% ▼-1 (4h54m) │ wk 32% ▼-25 (2d4h)
#
#     1. model    the model name in B03's FLAT per-model colour, and the
#                 effort tier in its own colour. Glance-items 1 and 2.
#     2. context  `ctx` occupancy. Glance-item 5.
#     3. 5-hour   `5h` used%, trend, countdown. Glance-item 6.
#     4. weekly   `wk` used%, trend, countdown. Glance-item 7.
#
#   Each limit group is the SAME three figures — used% · trend · countdown —
#   so the reader learns one reading rather than two. The trend comes from
#   B02 (burn_linear_trend for the 5-hour window, burn_week_trend for the
#   weekly one) and is coloured by the existing burn_trend_color; the
#   countdown comes from B04, wrapped in dimmed parens.
#
#   RETIRES, in this same change — everything that serves none of the seven
#   glance-items: the +added/-removed segment, the %t figure, the %/d figure,
#   the lines_added/lines_removed fields of the jq parse, the whole of
#   lib/burn-tick.sh and its test, and the now-uncalled burn_metrics,
#   burn_awake_seconds, burn_day_start_epoch, burn_rainbow, burn_model_style,
#   burn_frame_advance and burn_diff_color.
#
# Inputs:
#   The parsed payload variables (r5, r5_reset, r7, r7_reset, model_name,
#   effort, pct), the shared $_sl_now, and ONE plain `date` call — machine
#   local time — yielding seconds-into-day AND ISO weekday together, which is
#   what B01's anchor pair is derived from.
#
#   Three schedule knobs, all documented in the README's env table:
#     CLAM_STATUSLINE_WORK_DAYS  default "1-5"  ISO weekdays worked
#     CLAM_STATUSLINE_DAY_START  default 8      hour the working day starts
#     CLAM_STATUSLINE_DAY_END    default 18     hour the working day ends
#
#   A non-integer, out-of-range, or otherwise unusable value for any of them
#   falls back to ITS OWN default rather than erroring. Zero-padded values are
#   read as decimal — "08" is a correctly written hour, not octal, and the 10#
#   forcing that guarantees it is load-bearing, not decoration. A DAY_END at
#   or below DAY_START falls back to the default pair rather than yielding a
#   negative window.
#
#   ALL schedule arithmetic runs in the machine's local timezone. There is
#   deliberately no timezone knob (engineer's decision): a machine whose clock
#   is set to a zone other than the user's working zone shifts every working
#   window by the offset between them. Accepted, and documented as a
#   limitation rather than worked around.
#
# Outputs:
#   One line on stdout, no trailing newline, ANSI-coloured. A group with no
#   data is omitted WITH ITS SEPARATOR, so the line never shows a dangling │,
#   a label with no number, or a leading/trailing separator. Every group empty
#   echoes the empty string and the caller prints no line at all.
#
# Errors:
#   Never fails the render. Any component returning non-zero drops that figure
#   or its whole group; the rest of the line still renders. Nothing reaches
#   stdout but the line itself.
#
# Invariants:
#   - The warm-render process budget does NOT move: exactly one jq over stdin,
#     at most two date, at most two awk, no git, no ccost.sh, nothing opened
#     under CLAUDE_PROJECTS_DIR. Retiring the sub-tick interpolator frees one
#     awk, which the 5-hour trend does not spend — burn_linear_trend is pure
#     bash.
#   - Rate-limit figures stay LIVE on every render, never cached. They are
#     server-side quota state and a stale one is worse than none.
#   - Every colour comes from lib/burn-theme.sh. A hand-typed `38;5;` sequence
#     in this function is a bug — the same standard the previous contract set.
#     The two exceptions remain the dim group separator and the closing reset.
#   - The ctx meter keeps this plugin's non-saturating occupancy math and its
#     .local/.ctx-status.json publish unchanged (decision 002-context-meter-source).
#
# Edge cases:
#   - No rate_limits in the payload (API-key, Bedrock, Vertex auth): groups 3
#     and 4 vanish with their separators; groups 1 and 2 render.
#   - A window with used_percentage present but resets_at absent: the used
#     figure renders, the trend AND countdown both drop — both need the reset.
#   - A float used_percentage such as 14.000000000000002: prints its integer
#     part, the same value the colour threshold reads, so the two can never
#     disagree at a boundary.
#   - Context occupancy over 100%: renders above 100 rather than clamping.
#   - A model name with a parenthesised suffix: trimmed at " (" before
#     colouring.
#   - An install missing lib/burn-theme.sh or lib/burn-math.sh: renders the
#     groups that do not need it, exit 0, nothing on stderr, no partial escape
#     sequence.
sl_render_burn_line() {
  # Every COLOUR on this line is burn-theme.sh's choice; no threshold or
  # palette is decided here. Two escape shapes are still typed out below,
  # neither of them a colour decision:
  #   $_sl_burn_sep -- the dim group separator, which burn-theme.sh offers no
  #     helper for. "Dim" in the Outputs clause above is SGR 2.
  #   $rst -- the closing half of burn-theme.sh's sequences. Every
  #     burn_*_color function echoes a bare SGR OPENER, so closing it is the
  #     caller's job.
  # Anything beyond those two is a bug: it means a colour was picked here
  # instead of in burn-theme.sh.
  local rst=$'\033[0m'
  local _sl_burn_acc="" g name t cd arrow

  # --- group 1: model name, effort tier (glance-items 1 and 2) --------------
  g=""
  if [ -n "$model_name" ]; then
    # "Opus 5 (1M context)" is trimmed at " (": the suffix costs a third of
    # the line's width and says nothing the meters do not. The trim happens
    # BEFORE the colour lookup, so the family is chosen from the short name.
    name="${model_name%% (*}"
    g="$(_sl_burn_color burn_model_color "$name")$name$rst"
  fi
  if [ -n "$effort" ]; then
    [ -n "$g" ] && g="$g "
    g="$g$(_sl_burn_color burn_effort_color "$effort")$effort$rst"
  fi
  _sl_burn_group "$g"

  # --- group 2: context occupancy (glance-item 5) --------------------------
  # $pct is the plugin's own non-saturating occupancy against the compaction
  # budget, computed below this function; an overrun renders above 100 rather
  # than clamping, and the same integer feeds the colour band so the number on
  # screen and the band it takes can never disagree.
  g=""
  if [ -n "$pct" ]; then
    g="$(_sl_burn_color burn_ctx_color "$pct")ctx ${pct}%$rst"
  fi
  _sl_burn_group "$g"

  # Contract: B17 plain-used-percent (plan 003-angry-pace-colours)
  # Behavior:  the used% tokens in groups 3 and 4 render PLAIN — no colour
  #            opener, no reset — `5h N%` / `wk N%` in the default
  #            foreground. burn_plan_color no longer exists (B16); its call
  #            sites go, not just its output.
  # Inputs:    r5/r7 percentages exactly as today.
  # Outputs:   the line is byte-identical to today's except the two used%
  #            tokens carry no SGR sequences. The trend arrows (via
  #            burn_trend_color, which now emits nothing at <= 0) and the
  #            dim countdowns are wired exactly as they are.
  # Errors:    none new; nothing here may fail louder than today.
  # Invariants: no colour decision lives inline in this file; group and
  #            separator logic untouched; the two-awk fork budget holds;
  #            an arrow whose colour function emitted nothing still gets
  #            its reset, which is a no-op by design.
  # Edge cases: missing r5/r7 still drop their whole group; decimal
  #            percentages still truncate via ${r5%%.*}/${r7%%.*}.
  # --- group 3: the 5-hour limit (glance-item 6) ---------------------------
  # used% , trend, countdown -- the same three figures, in the same order, as
  # the weekly group below, so the reader learns one reading rather than two.
  # The trend is burn_linear_trend's: over a five-hour window "which days do
  # you work" cannot apply, so it is plain wall clock over 18000 seconds.
  g=""
  if [ -n "$r5" ]; then
    g="5h ${r5%%.*}%"
    # A missing or unusable reset drops the trend AND the countdown -- both
    # need it -- while the used figure stays: it is live quota state.
    if [ -n "$r5_reset" ]; then
      if declare -f burn_linear_trend >/dev/null 2>&1; then
        t=$(burn_linear_trend "$r5" "$_sl_now" "$r5_reset" 18000 2>/dev/null) \
          && [ -n "$t" ] \
          && { case "$t" in -*) arrow='▼' ;; *) arrow='▲' ;; esac
               g="$g $(_sl_burn_color burn_trend_color "$t")$arrow$t$rst"; }
      fi
      g="$g$(_sl_burn_countdown "$r5_reset")"
    fi
  fi
  _sl_burn_group "$g"

  # --- group 4: the weekly limit (glance-item 7) ---------------------------
  # Same three figures as group 3, but the trend is burn_week_trend's: a
  # weekly window whose reset lands mid-week must not count the hours the user
  # does not work as burnable.
  g=""
  if [ -n "$r7" ]; then
    g="wk ${r7%%.*}%"
    if [ -n "$r7_reset" ]; then
      t=$(_sl_burn_week_trend) \
        && [ -n "$t" ] \
        && { case "$t" in -*) arrow='▼' ;; *) arrow='▲' ;; esac
             g="$g $(_sl_burn_color burn_trend_color "$t")$arrow$t$rst"; }
      g="$g$(_sl_burn_countdown "$r7_reset")"
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
# four group blocks free of the same four lines of join bookkeeping.
_sl_burn_group() { # group
  [ -z "$1" ] && return 0
  [ -n "$_sl_burn_acc" ] && _sl_burn_acc="$_sl_burn_acc $_sl_burn_sep "
  _sl_burn_acc="$_sl_burn_acc$1"
  return 0
}

# _sl_burn_color FUNC [ARG...] -- the colour opener FUNC yields, or NOTHING at
# all when the install has no lib/burn-theme.sh. Every colour on line 2 goes
# through here, which is what lets an install missing the presentation library
# render the same TEXT with no colour rather than a partial escape sequence or
# a locally-invented fallback: no colour decision lives in this file.
_sl_burn_color() { # func [arg...]
  local fn="$1"; shift
  declare -f "$fn" >/dev/null 2>&1 || return 0
  "$fn" "$@" 2>/dev/null
  return 0
}

# _sl_burn_countdown RESET -- the dimmed, parenthesised countdown to RESET,
# with its leading space, or the empty string when it cannot be computed. The
# parens sit INSIDE the dim sequence so the whole subordinate clause dims
# together, and they drop WITH the figure so the line never shows an empty
# "()".
_sl_burn_countdown() { # reset
  local cd
  declare -f burn_reset_str >/dev/null 2>&1 || return 0
  cd=$(burn_reset_str "$1" "$_sl_now" 2>/dev/null) || return 0
  [ -n "$cd" ] || return 0
  printf ' %s(%s)%s' "$(_sl_burn_color burn_countdown_color)" "$cd" $'\033[0m'
  return 0
}

# _sl_burn_week_trend -- the weekly trend, or nothing (non-zero) when it
# cannot be computed. Spends the render's SECOND and last `date` on the one
# LOCAL reading the working-week model needs: seconds-into-the-local-day and
# the ISO weekday TOGETHER, from a single invocation, because one `date` call
# carries one timezone and the shared $_sl_now has to be UTC ('.ctx-status.json's
# fetched_at is). Called only from the weekly group, so a payload with no
# weekly data never pays for it.
#
# All schedule arithmetic is therefore in the machine's LOCAL timezone, and
# there is deliberately no timezone knob: a machine whose clock is set to a
# zone other than the user's working one shifts every window by the offset
# between them. Accepted and documented, not worked around.
_sl_burn_week_trend() {
  declare -f burn_week_trend >/dev/null 2>&1 || return 1
  declare -f burn_work_parse >/dev/null 2>&1 || return 1

  # The three schedule knobs. Each unusable value falls back to ITS OWN
  # default rather than to a whole default set, so the two good knobs still
  # take effect alongside the rejected one. The 10# is not decoration: a
  # perfectly reasonable "08" is OCTAL to bash arithmetic, and an unforced one
  # aborts the comparison below -- silently dropping the trend for a value the
  # user wrote correctly.
  local days st en sched mask ss es h m s wd am
  days="${CLAM_STATUSLINE_WORK_DAYS:-1-5}"
  st="${CLAM_STATUSLINE_DAY_START:-8}"
  en="${CLAM_STATUSLINE_DAY_END:-18}"
  case "$st" in ''|*[!0-9]*) st=8 ;; *) st=$(( 10#$st )) ;; esac
  [ "$st" -gt 23 ] && st=8
  case "$en" in ''|*[!0-9]*) en=18 ;; *) en=$(( 10#$en )) ;; esac
  { [ "$en" -lt 1 ] || [ "$en" -gt 24 ]; } && en=18
  # A day that ends at or before it starts is not a shorter window, it is no
  # window at all, so this one fallback is to the default PAIR.
  if [ "$en" -le "$st" ]; then st=8; en=18; fi

  read -r h m s wd <<< "$(date +'%H %M %S %u')"
  case "$h$m$s$wd" in ''|*[!0-9]*) return 1 ;; esac
  am=$(( _sl_now - (10#$h * 3600 + 10#$m * 60 + 10#$s) ))

  # An unparseable weekday SET falls back to the default week; the hours have
  # already fallen back on their own above.
  sched=$(burn_work_parse "$days" "$st" "$en" 2>/dev/null) \
    || sched=$(burn_work_parse "1-5" "$st" "$en" 2>/dev/null) \
    || return 1
  read -r mask ss es <<< "$sched"

  burn_week_trend "$r7" "$_sl_now" "$r7_reset" "$am" "$(( 10#$wd ))" \
    "$mask" "$ss" "$es" 2>/dev/null
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

# Burnrate line libraries (B01/B02 working-week pacing math, B03/B04
# presentation). `.` is a builtin, so sourcing two more files costs the
# warm-render process budget nothing. Each is optional at load time: a
# missing file leaves its functions undefined and sl_render_burn_line omits
# the figures that need them, exactly as it does for absent payload data.
for _burn_lib in burn-math.sh burn-theme.sh; do
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

# Contract: B07 line1-paths (plan 001-statusline-glance-uplift)
#
# Behavior:
#   sl_render_path_segment renders glance-items 3 and 4 — the project
#   directory the orchestrator started in, and the directory the agent is
#   working in now — as the head of line 1.
#
#   When PROJECT_DIR and CURRENT_DIR are the same path (the normal case) it
#   renders ONE segment showing the project dir, with $HOME collapsed to "~".
#   When they differ it renders the project dir, then "›", then the current
#   dir expressed RELATIVE to the project dir — falling back to the absolute
#   current dir when the current dir is not underneath it.
#
#   The whole segment is wrapped in an OSC 8 file:// hyperlink. As part of
#   this block, osc8_link's terminator changes from ST (\033\\) to BEL (\a),
#   matching the form the Claude Code statusline docs use.
#
# Inputs:
#   sl_render_path_segment PROJECT_DIR CURRENT_DIR
#     PROJECT_DIR  workspace.project_dir, ADDED to the single-jq parse by this
#                  block; possibly empty
#     CURRENT_DIR  workspace.current_dir, already parsed today
#   $HOME, read from the environment for the "~" collapse.
#
# Outputs:
#   One coloured, hyperlinked path segment, no trailing newline, followed by
#   the existing branch, PR, git-sync, mode and State segments UNCHANGED — no
#   segment past the path gains or loses a leading space.
#
# Errors:
#   Never fails the render. An absent PROJECT_DIR falls back to rendering the
#   current dir alone, exactly as today. A terminal that ignores OSC 8 shows
#   the visible text unchanged, which is the whole reason the sequence is safe
#   to emit unconditionally.
#
# Invariants:
#   - Still EXACTLY ONE jq over the stdin payload. project_dir rides the
#     existing invocation; it does not buy a second one.
#   - The path segment stays live on every render, never served from the cache
#     bundle.
#   - The URL is percent-encoded enough that a path containing a space or "#"
#     does not break the sequence.
#   - bash 3.2 compatible.
#
# Edge cases:
#   - PROJECT_DIR and CURRENT_DIR identical: one segment, no "›".
#   - CURRENT_DIR outside PROJECT_DIR: absolute path after the "›".
#   - $HOME unset, or the path outside it: no "~" collapse.
#   - A path containing the OSC 8 terminator byte cannot arise from a real
#     filesystem path, but the encoding must not emit a raw BEL from user data
#     regardless — the sequence's framing must never be decidable by its
#     content.
#
# sl_render_path_segment PROJECT_DIR CURRENT_DIR
sl_render_path_segment() {
  local proj="$1" cur="$2" link text tail
  local blue=$'\033[38;5;39m' dim=$'\033[38;5;245m' rst=$'\033[0m'

  # Nothing to show and nothing to link to: print nothing at all rather than a
  # bare pair of colour sequences.
  [ -z "$proj" ] && [ -z "$cur" ] && return 0

  # Where a Ctrl+Click lands: the directory the agent is working in now, which
  # is the one a reader following the link wants open. With no current dir the
  # project dir is both what shows and what opens.
  link="$cur"
  [ -z "$link" ] && link="$proj"

  if [ -z "$proj" ] || [ -z "$cur" ] || [ "$proj" = "$cur" ]; then
    # The normal case, and the two degenerate ones: ONE dir, no "›" to
    # introduce a second with.
    text="$blue$(_sl_path_display "${proj:-$cur}")$rst"
  else
    # Two dirs. The tail is expressed relative to the project dir when it sits
    # underneath it -- which is the whole point of showing both, since the
    # shared prefix carries no information the head has not already given --
    # and absolute when it does not.
    case "$cur" in
      "$proj"/*) tail="$(_sl_path_clean "${cur#"$proj"/}")" ;;
      *)         tail="$(_sl_path_display "$cur")" ;;
    esac
    # Braces around the expansion abutting the "›": unbraced, the separator's
    # first byte is swallowed into the parameter name and both the colour and
    # the glyph come out mangled.
    text="$blue$(_sl_path_display "$proj")$rst ${dim}›$rst $blue$tail$rst"
  fi

  osc8_link "file://$(_sl_url_encode "$link")" "$text"
}

# _sl_path_display PATH -- PATH as the statusline shows it: $HOME collapsed to
# a literal "~" (unchanged from the pre-B07 renderer, and skipped when $HOME is
# empty or the path lies outside it) and control bytes dropped.
_sl_path_display() { # path
  local p="$1"
  if [ -n "$HOME" ]; then
    case "$p" in
      "$HOME"|"$HOME"/*) p="~${p#"$HOME"}" ;;
    esac
  fi
  _sl_path_clean "$p"
}

# _sl_path_clean TEXT -- TEXT with every control byte removed. A real
# filesystem path holds none, but the OSC 8 framing must never be decidable by
# what it wraps: a BEL arriving inside the visible text would close the
# hyperlink early and leave the rest of the line inside a sequence no terminal
# is expecting. Dropped rather than escaped, because the byte has no visible
# form to preserve.
_sl_path_clean() { # text
  local LC_ALL=C
  local s="$1" out="" i c
  i=0
  while [ "$i" -lt "${#s}" ]; do
    c="${s:$i:1}"
    i=$(( i + 1 ))
    case "$c" in
      [[:cntrl:]]) continue ;;
      *) out="$out$c" ;;
    esac
  done
  printf '%s' "$out"
}

# _sl_url_encode PATH -- PATH percent-encoded for the file:// URL. Everything
# outside the unreserved set plus "/" is encoded, which covers the two bytes
# that would otherwise break the sequence for real users -- a space, and a "#"
# truncating the URL at what a terminal reads as a fragment -- as well as the
# terminator byte itself. LC_ALL=C is load-bearing: it makes the loop walk
# BYTES, so a path with non-ASCII characters is encoded as the UTF-8 octets a
# file:// URL is made of rather than as codepoints. Builtins only; the
# command substitutions are subshells, not execs, so this costs the render's
# process budget nothing.
_sl_url_encode() { # path
  local LC_ALL=C
  local s="$1" out="" i c n hex
  local safe='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~/'
  i=0
  while [ "$i" -lt "${#s}" ]; do
    c="${s:$i:1}"
    i=$(( i + 1 ))
    case "$safe" in
      *"$c"*) out="$out$c" ;;
      *)
        # The mask is load-bearing on bash 3.2: it reads a byte above 0x7f as a
        # SIGNED char, so an unmasked %02X of "é" prints FFFFFFFFFFFFFFC3
        # rather than C3 and the URL comes out unusable.
        printf -v n '%d' "'$c"
        printf -v hex '%%%02X' "$(( n & 255 ))"
        out="$out$hex"
        ;;
    esac
  done
  printf '%s' "$out"
}

# Wrap text in an OSC 8 hyperlink so terminals (Alacritty 0.7+, iTerm2,
# WezTerm) make it Ctrl+Clickable. tmux 3.4+ passes the sequence through.
# In terminals that ignore OSC 8, the visible text is unchanged.
# The terminator is BEL (\a), matching the Claude Code statusline docs (B07).
# Args: $1=url $2=text
osc8_link() {
  local url="$1" text="$2"
  if [ -z "$url" ]; then
    printf '%s' "$text"
  else
    printf '\033]8;;%s\a%s\033]8;;\a' "$url" "$text"
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

  # Bound the cache directory (B08). COLD path only, and deliberately before
  # the write rather than after it: the bundle this render is about to leave
  # behind is by definition fresh, so sweeping first spares it a stat. One day
  # is long enough that a session parked overnight still finds its own bundle
  # and short enough that a machine's worth of dead sessions does not
  # accumulate. Bundles written under the pre-B08 transcript_path key age out
  # through this same call rather than being migrated.
  sl_cache_sweep "$SL_CACHE_DIR" 86400

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

# Format the status line. The head is B07's path segment: the project dir and,
# when it differs, the dir the agent is working in now, $HOME collapsed to "~"
# and the whole thing hyperlinked. Live on every render, never cached. $cwd and
# $project_dir themselves are left intact — $cwd is still what the git
# detection above walks up from.
sl_render_path_segment "$project_dir" "$cwd"

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

