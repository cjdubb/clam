#!/bin/bash
# Compute Claude Code costs from local JSONL transcripts using a pinned price table.
# Pricing comes from prices.json (sibling file). Update that table when Anthropic
# changes rates. Costs are list-price equivalents — useful as a counterfactual to
# the Max subscription, not what you actually paid.
#
# Modes:
#   ccost.sh session <transcript_path>   # cost for one session in USD
#   ccost.sh day                         # cost for today (00:00 AEST → now), 300s cache
#   ccost.sh week                        # cost for current week (Mon 00:00 AEST → now), 300s cache
#
# All modes print a single decimal number to stdout (e.g. "0.42"). Errors print "0".

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../lib/platform.sh"
PRICES_FILE="$SCRIPT_DIR/prices.json"
PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
CACHE_DIR="${CCOST_CACHE_DIR:-$HOME/.claude/.ccost-cache}"
CACHE_TTL_SECONDS=300
# A period recompute takes seconds, so a lock this old means its holder died;
# stealing it beats serving stale data forever.
LOCK_STALE_SECONDS=120

mkdir -p "$CACHE_DIR" 2>/dev/null || true

if ! command -v jq &>/dev/null; then
  echo "0"
  exit 0
fi

# Sum cost from JSONL on stdin. $cutoff (epoch seconds) is the lower bound on
# record timestamp; pass 0 to include everything.
sum_cost() {
  local cutoff="${1:-0}"
  # -R reads each line as a raw string so a single malformed line in any
  # transcript can't abort the run (Claude Code occasionally writes truncated
  # JSON when a tool result exceeds the line buffer). fromjson? drops them.
  jq -nrR --slurpfile prices "$PRICES_FILE" --argjson cutoff "$cutoff" '
    # Build prefix table sorted longest-first so "claude-opus-4-1"
    # matches "claude-opus-4-1" before it matches "claude-opus-4".
    ($prices[0]
      | to_entries
      | map(select(.key | startswith("_") | not))
      | sort_by(-(.key | length))) as $price_table |

    def lookup(model):
      (model // "") as $m |
      ($price_table | map(select(.key as $k | $m | startswith($k))) | first) as $entry |
      if $entry then $entry.value else null end;

    # Claude Code timestamps include fractional seconds (e.g. "2026-04-28T22:17:26.944Z")
    # which jq fromdateiso8601 rejects. Strip the milliseconds before parsing.
    [inputs
      | fromjson?
      | select(.type == "assistant"
               and (.message.usage // null) != null
               and (.timestamp // ""
                    | sub("\\.[0-9]+Z$"; "Z")
                    | try fromdateiso8601 catch 0) >= $cutoff)
    ]
    | unique_by((.requestId // "") + "/" + (.message.id // ""))
    | map(
        .message.usage as $u |
        lookup(.message.model) as $p |
        if $p == null then 0 else
          (($u.input_tokens // 0) * $p.input)
          + (($u.output_tokens // 0) * $p.output)
          + (($u.cache_read_input_tokens // 0) * $p.cache_read)
          + (($u.cache_creation.ephemeral_5m_input_tokens // 0) * $p.cache_5m)
          + (($u.cache_creation.ephemeral_1h_input_tokens // 0) * $p.cache_1h)
        end
      )
    | (add // 0) / 1000000
  ' 2>/dev/null || echo "0"
}

# Period start in Australia/Sydney (handles AEST/AEDT DST automatically),
# expressed as UTC epoch seconds. Period is "day" (today 00:00) or "week"
# (Monday 00:00). Falls back to 0 (= no filter) on python error.
aest_start_epoch() {
  local period="${1:-week}"
  command -v python3 > /dev/null 2>&1 || { echo "0"; return 0; }
  python3 -c "
import datetime, sys
period = sys.argv[1] if len(sys.argv) > 1 else 'week'
try:
    from zoneinfo import ZoneInfo
    tz = ZoneInfo('Australia/Sydney')
except ImportError:
    tz = None
now = datetime.datetime.now(tz) if tz else datetime.datetime.now()
if period == 'week':
    start = now - datetime.timedelta(days=now.weekday())
else:
    start = now
start = start.replace(hour=0, minute=0, second=0, microsecond=0)
print(int(start.timestamp()))
" "$period" 2>/dev/null || echo "0"
}

# True when the cache file exists and is younger than $CACHE_TTL_SECONDS.
# Shared by period_cost's entry check and its post-acquisition double-check so
# the two can never drift apart.
cache_is_fresh() {
  local cache_file="$1"
  [[ -f "$cache_file" ]] || return 1
  local now_epoch cache_epoch
  now_epoch=$(date +%s)
  cache_epoch=$(clam_mtime_epoch "$cache_file")
  (( now_epoch - cache_epoch < CACHE_TTL_SECONDS ))
}

# Sum cost for an open-ended period starting at the AEST midnight boundary.
# Cached at $CACHE_DIR/<period>.cache for $CACHE_TTL_SECONDS to avoid rescanning
# hundreds of MB of historical transcripts on every statusline render.
period_cost() {
  local period="$1"
  local cache_file="$CACHE_DIR/${period}.cache"
  if cache_is_fresh "$cache_file"; then
    cat "$cache_file"
    return 0
  fi

  if [[ ! -d "$PROJECTS_DIR" ]]; then
    echo "0"
    return 0
  fi

  # Single-flight the recompute: every live session's cache expires at the same
  # instant, so without a lock N sessions launch N identical full scans at once.
  # mkdir is the lock primitive because it is atomic on POSIX filesystems and
  # flock(1) is not stock on macOS.
  local lock_dir="$CACHE_DIR/${period}.lock"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    # A recompute takes seconds, so a lock older than LOCK_STALE_SECONDS means
    # its holder died: steal it (losing the steal race is the same as losing
    # the lock). A missing/unstatable lock counts as fresh — the holder just
    # finished, so the cache is about to be (or already is) current.
    local lock_now lock_epoch
    lock_now=$(date +%s)
    # clam_mtime_epoch falls back to 0 (not lock_now) on a stat failure; a
    # real lock dir's mtime is never epoch 0, so treat that sentinel as
    # "unstatable" and normalize it to lock_now to keep the fresh-fallback
    # semantics described above.
    lock_epoch=$(clam_mtime_epoch "$lock_dir")
    [[ "$lock_epoch" == "0" ]] && lock_epoch="$lock_now"
    if (( lock_now - lock_epoch < LOCK_STALE_SECONDS )) \
      || { rmdir "$lock_dir" 2>/dev/null || true; ! mkdir "$lock_dir" 2>/dev/null; }; then
      # Losers never wait: a stale figure beats a stalled statusline render.
      # No cache only happens on first-ever runs; 0 is the error contract.
      if [[ -f "$cache_file" ]]; then
        cat "$cache_file" 2>/dev/null || echo "0"
      else
        echo "0"
      fi
      return 0
    fi
  fi

  # Holding the lock: release it (and drop the cutoff temp file created below)
  # on every exit path — jq failure under set -e, a signal mid-scan — or the
  # lock outlives this process and every session serves stale data until the
  # staleness steal kicks in.
  trap 'rmdir "${lock_dir:-}" 2>/dev/null || true; rm -f "${cutoff_ref:-}" 2>/dev/null || true' EXIT
  trap 'exit 1' HUP INT TERM

  # Re-check freshness now that the lock is held: between the entry check and
  # acquisition another process may have finished the recompute (the steal
  # path's rmdir+mkdir even races the old holder's own release), and rescanning
  # then would recreate the very herd the lock exists to prevent.
  if cache_is_fresh "$cache_file"; then
    cat "$cache_file" 2>/dev/null || echo "0"
    rmdir "$lock_dir" 2>/dev/null || true
    trap - EXIT HUP INT TERM
    return 0
  fi

  local cutoff
  cutoff=$(aest_start_epoch "$period")

  # Skip files whose mtime is before the cutoff. Claude Code only appends to
  # JSONL transcripts, so a file untouched since before the period started
  # cannot contain post-cutoff records. This drops the cold-path time from
  # scanning hundreds of MB of historical transcripts to just the active set.
  local cutoff_ref result
  cutoff_ref=$(mktemp)
  touch -t "$(date -r "$cutoff" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$cutoff" +%Y%m%d%H%M.%S)" "$cutoff_ref"

  result=$(find "$PROJECTS_DIR" -name '*.jsonl' -type f -newer "$cutoff_ref" -print0 \
    | xargs -0 cat 2>/dev/null \
    | sum_cost "$cutoff")
  rm -f "$cutoff_ref"

  echo "$result" > "$cache_file" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
  trap - EXIT HUP INT TERM
  echo "$result"
}

mode="${1:-}"
case "$mode" in
  session)
    transcript_path="${2:-}"
    if [[ -z "$transcript_path" || ! -f "$transcript_path" ]]; then
      echo "0"
      exit 0
    fi
    # Cache keyed by transcript path, valid while the transcript is untouched
    # (Claude Code only appends, so any new record bumps the mtime). Idle
    # statusline heartbeats then cost a stat instead of a full-transcript scan.
    session_cache="$CACHE_DIR/session-$(printf '%s' "$transcript_path" | cksum | cut -d' ' -f1).cache"
    if [[ -f "$session_cache" && "$session_cache" -nt "$transcript_path" ]]; then
      cat "$session_cache"
      exit 0
    fi
    result=$(sum_cost 0 < "$transcript_path")
    echo "$result" > "$session_cache" 2>/dev/null || true
    echo "$result"
    ;;

  day|week)
    period_cost "$mode"
    ;;

  *)
    echo "Usage: $0 {session <transcript_path>|day|week}" >&2
    exit 1
    ;;
esac
