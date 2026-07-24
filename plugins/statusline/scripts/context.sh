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
#   segment, clam mode, and the Cost line. The background refresh-engine
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
#   Missing/empty transcript_path: key falls back to cwd; cost renders as
#     today; the bundle is still cached. TTL boundary: age < TTL is
#     fresh, age >= TTL is stale; a negative age (future-dated bundle
#     after a clock step) reads fresh. No git worktree / no .local/:
#     segments degrade exactly as today and the ctx-status publish is
#     skipped as today. First-ever render: cold, creates dir + bundle.

# --- B01 scaffold surface (deliberately unimplemented) -------------------
# Public env knobs of the cheap-render path. Declared here so the
# interface is fixed; unused until the block is implemented.
SL_CACHE_DIR="${CLAM_STATUSLINE_CACHE_DIR:-$HOME/.claude/.statusline-cache}"
SL_SEGMENT_TTL_SECONDS="${CLAM_STATUSLINE_SEGMENT_TTL_SECONDS:-5}"

_sl_not_implemented() {
  echo "NotImplemented: B01 context-cheap-render" >&2
  exit 1
}

# sl_parse_input: parse the ENTIRE stdin payload (window size, total input
# tokens, transcript path, cwd, model display name, effort level) with one
# single jq invocation, populating the same variables the legacy per-field
# jq calls populate today.
sl_parse_input() { _sl_not_implemented; }

# sl_bundle_read: emit the cached expensive-segment bundle for the current
# session key iff it is fresh (age < SL_SEGMENT_TTL_SECONDS); non-zero exit
# when stale, absent, corrupt, or caching is disabled (TTL <= 0).
sl_bundle_read() { _sl_not_implemented; }

# sl_bundle_write: atomically (temp + rename) persist the freshly rendered
# expensive-segment bundle for the current session key; best-effort — a
# write failure leaves rendering unaffected.
sl_bundle_write() { _sl_not_implemented; }
# ------------------------------------------------------------------------

# Read JSON input from stdin
input=$(cat)

# Shared lib dir: session-State metadata plus the cache-refresh engines.
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)"
_STATES_LIB="$_LIB_DIR/states.sh"
[ -f "$_STATES_LIB" ] && . "$_STATES_LIB"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/platform.sh"

# Extract context window data
window_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')

# Path to the transcript JSONL for the current session, used by ccost.sh.
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Format number with commas
fmt() { printf "%'d" "$1" 2>/dev/null || echo "$1"; }

# Age of a file in seconds (missing file reads as very old).
file_age() {
  local m
  m=$(clam_mtime_epoch "$1")
  echo $(( $(date +%s) - m ))
}

# Format USD amount: 2 decimals, thousands separators (e.g. "1,234.56").
fmt_usd() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" = "0" ]; then
    echo "0.00"
    return
  fi
  printf "%'.2f" "$n" 2>/dev/null || printf "%.2f" "$n"
}

# Extract other data
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model_name=$(echo "$input" | jq -r '.model.display_name // empty')

# Reasoning effort level. Primary source is the live statusLine JSON field
# (.effort.level reflects mid-session /effort changes); fall back to the
# launch-time CLAUDE_EFFORT env var; empty when neither is present (e.g. plain
# `claude` on a model without effort support), which drops the segment.
effort=$(echo "$input" | jq -r '.effort.level // empty')
[ -z "$effort" ] && effort="${CLAUDE_EFFORT:-}"

# Get git branch
branch=$(cd "$cwd" && git branch --show-current 2>/dev/null)

# Resolve the PR status file at the worktree root, if any.
pr_status_file=""
toplevel=$(cd "$cwd" && git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$toplevel" ] && [ -f "$toplevel/.local/.pr-status.json" ]; then
  pr_status_file="$toplevel/.local/.pr-status.json"
fi

# Keep the .local caches warm. The Stop hooks only refresh at turn end, so a
# parked session's badges would freeze; this render-time trigger kicks the
# shared engines in a fully detached background process whenever a cache is
# stale (or missing) and renders whatever is on disk now. Claude Code re-runs
# this script on conversation events and on the settings.json statusLine
# refreshInterval heartbeat, so the next render picks up the result. All fds
# are detached from the spawn so the render never waits on it.
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

# Classify a PR into its statusline emoji. Same rules as the /pr-status skill.
# Args: $1=state $2=reviews $3=ci $4=comments
# Echoes: ✅ | 🚂 | 🚫 | 🔴 | 🟡 | 🟢
classify_pr_emoji() {
  local state="$1" reviews="$2" ci="$3" comments="$4"
  if [ "$state" = "Merged" ]; then
    echo "✅"
  elif [ "$state" = "Queue Failed" ]; then
    # Queue ejected the PR; needs author attention before re-enqueue.
    echo "🚫"
  elif [ "$state" = "In Queue" ]; then
    # Passive wait while queue CI runs against the queue head.
    echo "🚂"
  elif [ "$ci" = "Fail" ] \
    || [ "$reviews" = "Changes Requested" ] \
    || [ "$reviews" = "Commented" ] \
    || [ "$reviews" = "Not Requested" ] \
    || [ "${comments:-0}" -gt 0 ] \
    || { [ "$reviews" = "Approved" ] && [ "$ci" = "Pass" ]; }; then
    echo "🔴"
  elif [ "$state" = "Draft" ] \
    || [ "$reviews" = "Approved (stale)" ] \
    || { [ "$reviews" = "Approved" ] && [ "$ci" = "Running" ]; }; then
    echo "🟡"
  else
    echo "🟢"
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

# Compute the PR badge per the /pr-status skill's color rules.
# Every worktree emits a `prs` array (0, 1, or N entries) via pr-status-refresh.
# Render actionable PRs (🔴/🟡) individually and collapse green/merged to counts.
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
      emoji=$(classify_pr_emoji "$state" "$reviews" "$ci" "$comments")
      case "$emoji" in
        "✅") merged_count=$((merged_count + 1)) ;;
        "🚂") queued_count=$((queued_count + 1)) ;;
        "🟢") green_count=$((green_count + 1)) ;;
        *)    actionable="$actionable $emoji $(osc8_link "$url" "#$number")" ;;
      esac
    done < <(jq -r '.prs[] | [.number, .state, .reviews, .ci, (.comments // 0), (.url // "")] | @tsv' "$pr_status_file" 2>/dev/null)

    pr_badge="$actionable"
    [ "$green_count" -gt 0 ]  && pr_badge="$pr_badge 🟢$green_count"
    [ "$queued_count" -gt 0 ] && pr_badge="$pr_badge 🚂$queued_count"
    [ "$merged_count" -gt 0 ] && pr_badge="$pr_badge ✅$merged_count"
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
state_segment=""
if [ -n "$toplevel" ] && [ -f "$toplevel/.local/TODO.md" ]; then
  state=$(todo_field "$toplevel/.local/TODO.md" State)
  if [ -n "$state" ] && command -v state_emoji >/dev/null 2>&1; then
    glyph=$(state_emoji "$state")
    color_seq=$(printf '\033[38;5;%sm' "$(state_color "$state")")
    state_segment="  ${glyph} ${color_seq}${state}"$'\033[0m'
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

if [ -n "$state_segment" ]; then
  printf '%s' "$state_segment"
fi

# Mode + model + effort line (its own line so the path line above stays
# short). The clam session mode (sanitized from .local/MODE above) leads in
# teal, the model in purple, the effort dimmed so it reads as secondary.
# Renders e.g. "Build · Opus · max effort"; any subset degrades gracefully —
# sep_needed puts the dim · only BETWEEN present segments — and the line is
# omitted when all three are empty.
# This and the blocks below each PREPEND their newline (rather than trailing
# one) so the status block ends on its last rendered line with no dangling
# blank line — which is why the path line above prints no trailing newline.
if [ -n "$clam_mode" ] || [ -n "$model_name" ] || [ -n "$effort" ]; then
  printf '\n'
  sep_needed=false
  if [ -n "$clam_mode" ]; then
    printf '\033[38;5;37m%s\033[0m' "$clam_mode"
    sep_needed=true
  fi
  if [ -n "$model_name" ]; then
    [ "$sep_needed" = "true" ] && printf ' \033[38;5;245m·\033[0m '
    printf '\033[38;5;93m%s\033[0m' "$model_name"
    sep_needed=true
  fi
  if [ -n "$effort" ]; then
    [ "$sep_needed" = "true" ] && printf ' \033[38;5;245m·\033[0m '
    printf '\033[38;5;245m%s effort\033[0m' "$effort"
  fi
fi

# Context usage summary line. Shows real occupancy (total_input_tokens, the figure
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
ctx_budget="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
if [ -z "$ctx_budget" ]; then
  ctx_budget=$(jq -r '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW // empty' "$HOME/.claude/settings.json" 2>/dev/null)
fi
ctx_budget="${ctx_budget:-$window_size}"
if [ -n "$total_input" ] && [ -n "$ctx_budget" ] && [ "$ctx_budget" -gt 0 ] 2>/dev/null; then
  printf '\n'
  used_tokens="$total_input"
  # Integer occupancy percent (floor). Deliberately NOT clamped at 100 — an
  # overrun reads >100, mirroring the numerator's non-saturating behaviour.
  pct=$(( 100 * used_tokens / ctx_budget ))

  # Idle seconds = time since the transcript's last append. Claude Code only
  # appends to the transcript, so its mtime marks the last real turn. Guard the
  # empty/missing case explicitly: file_age() would return a huge now-minus-0
  # value for a missing path and read as "infinitely cold", so only measure a
  # transcript that actually exists. Same stat helper as file_age() above.
  last_activity_epoch=0
  idle_seconds=0
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    last_activity_epoch=$(clam_mtime_epoch "$transcript_path")
    idle_seconds=$(( $(date +%s) - last_activity_epoch ))
    # Clamp a negative idle (possible after an NTP backward step) to 0 so the
    # published idle_seconds is never negative for the agent-dash consumer.
    [ "$idle_seconds" -lt 0 ] && idle_seconds=0
  fi

  # Tri-state staleness: a big session (>=60%) turns orange once it starts
  # cooling (>=30 min idle) and red at >=45 min — 15 min before the ~1h
  # prompt-cache TTL lapses, so it says "compact now, still time" not "too late".
  # Over-budget is always red. Thresholds are locked (not env-configurable).
  if [ "$used_tokens" -ge "$ctx_budget" ] 2>/dev/null \
     || { [ "$pct" -ge 60 ] && [ "$idle_seconds" -ge 2700 ]; }; then
    level="cold"; ctx_color='196'  # red
  elif [ "$pct" -ge 60 ] && [ "$idle_seconds" -ge 1800 ]; then
    level="warn"; ctx_color='208'  # orange
  else
    level="ok"; ctx_color='40'     # green
  fi

  printf '\033[38;5;245mCtx used:\033[0m '
  printf '\033[38;5;%sm%s\033[0m / \033[38;5;33m%s\033[0m \033[38;5;245m(%s%%)\033[0m' \
    "$ctx_color" "$(fmt "$used_tokens")" "$(fmt "$ctx_budget")" "$pct"

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
           "$used_tokens" "$ctx_budget" "$pct" "$last_activity_epoch" "$idle_seconds" "$level" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_ctx_tmp" 2>/dev/null; then
        mv -f "$_ctx_tmp" "$toplevel/.local/.ctx-status.json" 2>/dev/null || rm -f "$_ctx_tmp" 2>/dev/null
      else
        rm -f "$_ctx_tmp" 2>/dev/null
      fi
    fi
  fi
fi

# Cost summary line — list-price equivalent (counterfactual to the Max plan).
# Computed by sibling ccost.sh against ~/.claude/projects JSONL transcripts.
ccost_script="$(dirname "$0")/ccost.sh"
if [ -x "$ccost_script" ]; then
  session_cost=""
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    session_cost=$("$ccost_script" session "$transcript_path" 2>/dev/null)
  fi
  day_cost=$("$ccost_script" day 2>/dev/null)
  week_cost=$("$ccost_script" week 2>/dev/null)

  if [ -n "$session_cost" ] || [ -n "$day_cost" ] || [ -n "$week_cost" ]; then
    printf '\n'
    printf '\033[38;5;245mCost:\033[0m '
    need_sep=false
    if [ -n "$session_cost" ]; then
      printf 'Session: \033[38;5;220m$%s\033[0m' "$(fmt_usd "$session_cost")"
      need_sep=true
    fi
    if [ -n "$day_cost" ]; then
      if [ "$need_sep" = "true" ]; then printf ' \033[38;5;245m|\033[0m '; fi
      printf 'Today (AEST): \033[38;5;220m$%s\033[0m' "$(fmt_usd "$day_cost")"
      need_sep=true
    fi
    if [ -n "$week_cost" ]; then
      if [ "$need_sep" = "true" ]; then printf ' \033[38;5;245m|\033[0m '; fi
      printf 'Week (AEST): \033[38;5;220m$%s\033[0m' "$(fmt_usd "$week_cost")"
    fi
  fi
fi
