#!/bin/bash
# Functional test for ccost.sh caching — pins that an untouched transcript is
# served from the session cache and that any append invalidates it (the cache
# is mtime-keyed, which is what makes the statusline refreshInterval heartbeat
# cheap while a session is idle), and that the day/week recompute is
# single-flighted behind a stale-serving lock (one scan per TTL cycle, no
# thundering herd across live sessions).
# Run: bash general/statusline/ccost.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCOST="$SCRIPT_DIR/ccost.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

run_ccost() { CCOST_CACHE_DIR="$TMPROOT/cache" CLAUDE_PROJECTS_DIR="$TMPROOT/projects" bash "$CCOST" "$@"; }

# Model must exist in prices.json for a non-zero cost.
record() { # request_id input_tokens
  printf '{"type":"assistant","timestamp":"2026-07-09T00:00:01.000Z","requestId":"%s","message":{"id":"%s","model":"claude-opus-4-8","usage":{"input_tokens":%s,"output_tokens":0}}}\n' "$1" "$1" "$2"
}

transcript="$TMPROOT/transcript.jsonl"
record r1 1000000 > "$transcript"

c1=$(run_ccost session "$transcript")
check "first run computes non-zero cost" "$([[ "$c1" != "0" && -n "$c1" ]] && echo nonzero || echo zero)" "nonzero"
check "cache file created" "$(find "$TMPROOT/cache" -name 'session-*.cache' 2>/dev/null | wc -l | tr -d ' ')" "1"

c2=$(run_ccost session "$transcript")
check "second run served identical result" "$c2" "$c1"

# Ensure the append lands with a strictly newer mtime than the cache file.
sleep 1
record r2 1000000 >> "$transcript"
c3=$(run_ccost session "$transcript")
check "append invalidates cache" "$([[ "$c3" != "$c1" ]] && echo recomputed || echo stale)" "recomputed"

# Missing transcript still prints 0.
check "missing transcript prints 0" "$(run_ccost session "$TMPROOT/nope.jsonl")" "0"

# --- Single-flight locking (day period) ---

cache="$TMPROOT/cache"
proj="$TMPROOT/projects/proj"
mkdir -p "$cache" "$proj"

# Day-period records need an in-period timestamp or the cutoff filters them
# out; "now" in UTC is always inside the current AEST day.
day_record() { # request_id input_tokens
  printf '{"type":"assistant","timestamp":"%s","requestId":"%s","message":{"id":"%s","model":"claude-opus-4-8","usage":{"input_tokens":%s,"output_tokens":0}}}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" "$1" "$1" "$2"
}
day_record d1 1000000 > "$proj/day.jsonl" # 1M input tokens at $5/MTok -> "5"

backdate() { # path seconds_ago
  local when=$(( $(date +%s) - $2 ))
  touch -t "$(date -r "$when" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$when" +%Y%m%d%H%M.%S)" "$1"
}

# A live lock held by another process: serve the stale value instantly (the
# statusline must never wait on a recompute) and leave the foreign lock alone.
echo "9.99" > "$cache/day.cache"
backdate "$cache/day.cache" 600
mkdir "$cache/day.lock"
check "held lock: stale cache served" "$(run_ccost day)" "9.99"
check "held lock: foreign lock left in place" "$([[ -d "$cache/day.lock" ]] && echo present || echo gone)" "present"
check "held lock: stale cache not rewritten" "$(cat "$cache/day.cache")" "9.99"

# A lock past LOCK_STALE_SECONDS means its holder died: steal it, recompute,
# release.
backdate "$cache/day.lock" 700
check "stale lock: stolen and recomputed" "$(run_ccost day)" "5"
check "stale lock: cache rewritten with fresh value" "$(cat "$cache/day.cache")" "5"
check "stale lock: lock released" "$([[ -d "$cache/day.lock" ]] && echo present || echo gone)" "gone"

# Double-check after acquisition: a cache that went fresh between the entry
# check and winning the lock must be served without a rescan. That window is
# sub-millisecond, so make it deterministic with a stat(1) shim on PATH that
# reports the cache stale on the first call (entry check) and fresh on the
# second (post-acquisition re-check). A rescan would print "5" and rewrite the
# cache; the double-check serves the sentinel and leaves it untouched.
# COUPLING: the shim's call counter assumes its 1st and 2nd invocations are
# exactly the two cache_is_fresh calls on this code path (entry check, then
# post-acquisition re-check) with no other stat call in between — a stat added
# to ccost.sh before the double-check would skew the counter and this test.
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/stat" <<SHIM
#!/bin/bash
count_file="$TMPROOT/statcalls"
n=\$(( \$(cat "\$count_file" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "\$count_file"
if (( n == 1 )); then
  echo \$(( \$(date +%s) - 600 ))
else
  date +%s
fi
SHIM
chmod +x "$TMPROOT/bin/stat"
rm -f "$TMPROOT/statcalls"
echo "9.99" > "$cache/day.cache"
dc_out=$(PATH="$TMPROOT/bin:$PATH" CCOST_CACHE_DIR="$cache" CLAUDE_PROJECTS_DIR="$TMPROOT/projects" bash "$CCOST" day)
check "double-check: fresh-after-acquisition cache served without rescan" "$dc_out" "9.99"
check "double-check: cache not rewritten" "$(cat "$cache/day.cache")" "9.99"
check "double-check: lock released" "$([[ -d "$cache/day.lock" ]] && echo present || echo gone)" "gone"

# Concurrency smoke: against an expired cache every simultaneous caller must
# print a valid value and the system must converge. The winner may finish
# before late losers even start (they then legitimately serve the fresh
# value), so assert membership in {sentinel, fresh}, not an exact split.
echo "9.99" > "$cache/day.cache"
backdate "$cache/day.cache" 600
smoke="$TMPROOT/smoke"
mkdir -p "$smoke"
for i in $(seq 1 10); do
  run_ccost day > "$smoke/$i" &
done
wait
check "smoke: every caller produced output" "$(cat "$smoke"/* | wc -l | tr -d ' ')" "10"
# grep -c exits 1 on zero matches (the healthy case), which would abort the
# suite under a future set -e without the || true.
bad=$(cat "$smoke"/* | grep -cvE '^(9\.99|5)$' || true)
check "smoke: all 10 concurrent outputs are sentinel or fresh value" "$bad" "0"
check "smoke: cache converged on fresh value" "$(cat "$cache/day.cache")" "5"
check "smoke: lock released" "$([[ -d "$cache/day.lock" ]] && echo present || echo gone)" "gone"

# --- no-python3 degrade (aest_start_epoch guard) ----------------------------
# day/week mode calls aest_start_epoch, which shells out to python3 for the
# AEST period boundary. Prove the `command -v python3` guard degrades quietly
# to "0" when python3 is absent, regardless of whether this host has it. PATH
# is replaced (not prepended) with a directory holding only symlinks to the
# handful of real binaries the day/week path needs before/around the guard
# (bash itself, since a temporary PATH= prefix is also used to resolve the
# command word; mkdir/dirname/jq for ccost.sh's own preamble) — no python3.
NOPY_BIN="$TMPROOT/nopy-bin"
mkdir -p "$NOPY_BIN"
nopy_ready=1
for tool in bash mkdir jq dirname; do
  tool_path=$(command -v "$tool" 2>/dev/null) || { nopy_ready=0; break; }
  ln -s "$tool_path" "$NOPY_BIN/$tool"
done

if [[ "$nopy_ready" == "1" ]]; then
  nopy_err="$TMPROOT/nopy.err"
  nopy_out=$(CCOST_CACHE_DIR="$TMPROOT/nopy-cache" CLAUDE_PROJECTS_DIR="$TMPROOT/nopy-projects" \
    PATH="$NOPY_BIN" bash "$CCOST" day 2>"$nopy_err")
  nopy_exit=$?
  check "no-python3 degrade prints 0" "$nopy_out" "0"
  check "no-python3 degrade exits 0" "$nopy_exit" "0"
  check "no-python3 degrade is silent on stderr" "$(cat "$nopy_err")" ""
else
  echo "SKIP  no-python3 degrade test: could not resolve bash/mkdir/jq/dirname to shim"
fi

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
