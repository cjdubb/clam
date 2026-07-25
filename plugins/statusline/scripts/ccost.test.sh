#!/bin/bash
# Functional test for ccost.sh caching — pins that an untouched transcript is
# served from the session cache and that any append invalidates it once the
# B02 session-window has expired (the cache is mtime-keyed, which is what
# makes the statusline refreshInterval heartbeat cheap while a session is
# idle); that the B02 session-window (CCOST_SESSION_TTL_SECONDS) serves the
# cache untouched — without opening the transcript or spawning jq — while the
# cache is younger than the window, regardless of transcript mtime, and only
# falls back to the legacy mtime comparison once the window has elapsed; and
# that the day/week recompute is single-flighted behind a stale-serving lock
# (one scan per TTL cycle, no thundering herd across live sessions).
# Run: bash general/statusline/ccost.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCOST="$SCRIPT_DIR/ccost.sh"
source "$SCRIPT_DIR/../lib/platform.sh"

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

backdate() { # path seconds_ago
  local when=$(( $(date +%s) - $2 ))
  touch -t "$(date -r "$when" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$when" +%Y%m%d%H%M.%S)" "$1"
}

# Symmetric to backdate: pushes a path's mtime into the future. Used to make
# a transcript (or cache file) unambiguously "newer" than another file without
# a real sleep, and to simulate the future-dated-cache clock-step edge case.
futuredate() { # path seconds_ahead
  local when=$(( $(date +%s) + $2 ))
  touch -t "$(date -r "$when" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$when" +%Y%m%d%H%M.%S)" "$1"
}

# Mirrors ccost.sh's own session-cache filename hashing so tests can seed or
# inspect a specific transcript's cache file directly.
session_cache_path() { # transcript_path -> predicted cache file path
  local hash
  hash=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  echo "$TMPROOT/cache/session-$hash.cache"
}

# jq-call counter: a PATH-shimmed jq that logs an invocation then execs the
# real jq, so tests can assert "zero jq processes spawned" by diffing the
# counter across a call instead of guessing at process-table state. Wired in
# per-call (not into run_ccost) so it never touches tests that don't need it.
JQBIN="$TMPROOT/jqbin"
mkdir -p "$JQBIN"
REAL_JQ="$(command -v jq)"
JQCALLS="$TMPROOT/jqcalls"
: > "$JQCALLS"
cat > "$JQBIN/jq" <<SHIM
#!/bin/bash
n=\$(( \$(cat "$JQCALLS" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "$JQCALLS"
exec "$REAL_JQ" "\$@"
SHIM
chmod +x "$JQBIN/jq"
jq_call_count() { cat "$JQCALLS" 2>/dev/null || echo 0; }

transcript="$TMPROOT/transcript.jsonl"
record r1 1000000 > "$transcript"

c1=$(run_ccost session "$transcript")
check "first run computes non-zero cost" "$([[ "$c1" != "0" && -n "$c1" ]] && echo nonzero || echo zero)" "nonzero"
check "cache file created" "$(find "$TMPROOT/cache" -name 'session-*.cache' 2>/dev/null | wc -l | tr -d ' ')" "1"

c2=$(run_ccost session "$transcript")
check "second run served identical result" "$c2" "$c1"

# Missing transcript still prints 0 (unaffected by B02: this guard runs
# before any cache/window logic is ever consulted).
check "missing transcript prints 0" "$(run_ccost session "$TMPROOT/nope.jsonl")" "0"

# Transcript deleted while its cache is warm: the -f guard fires before the
# window is ever consulted, so this must print "0", not the warm cached
# value, regardless of how young the cache is.
transcript_deleted="$TMPROOT/transcript-deleted.jsonl"
record del1 1000000 > "$transcript_deleted"
run_ccost session "$transcript_deleted" >/dev/null
rm -f "$transcript_deleted"
check "transcript deleted while cache warm: prints 0, not the warm cache" "$(run_ccost session "$transcript_deleted")" "0"

# NOTE (escalated to orchestrator, see test-wave report): the B02 contract
# also claims an *unreadable* (permission-denied, but existing) transcript
# prints "0" "exactly as today." Empirically it does not: ccost.sh's
# `[[ ! -f "$transcript_path" ]]` guard only tests file type/existence, not
# readability, so a chmod-000 existing transcript falls through to
# `sum_cost 0 < "$transcript_path"`, whose failed open aborts the script
# under `set -e` instead of printing "0". That contradicts the contract text
# for observed current behavior, so it is intentionally left untested here
# pending a decision rather than guessed at.

# --- B02 ccost-session-window ------------------------------------------

# Window holds (default TTL=30s): the just-written cache must be served
# verbatim even though the transcript is appended to and made unambiguously
# newer, and no jq process may be spawned to do it. Kept as its own call
# (transcript stays readable) so a crash from the *next* check's chmod 000
# can never masquerade as "zero jq calls" — a script that dies trying to
# open the transcript would also show zero jq invocations for the wrong
# reason, which would silently pass this assertion no matter what.
record r2 1000000 >> "$transcript"
futuredate "$transcript" 120
before_jq=$(jq_call_count)
out=$(PATH="$JQBIN:$PATH" CCOST_CACHE_DIR="$TMPROOT/cache" CLAUDE_PROJECTS_DIR="$TMPROOT/projects" bash "$CCOST" session "$transcript")
after_jq=$(jq_call_count)
check "warm window: stale cache served despite append + newer mtime" "$out" "$c1"
check "warm window: zero jq invocations while window holds" "$(( after_jq - before_jq ))" "0"

# Same guarantee, proven a second, independent way: make the transcript
# unreadable. If the window fails to hold, the code path that would consult
# the transcript (`sum_cost 0 < "$transcript_path"`) fails to open it and the
# script aborts — a clearly distinguishable failure from "window held".
chmod 000 "$transcript"
out_unreadable=$(run_ccost session "$transcript" 2>/dev/null)
rc=$?
chmod 644 "$transcript"
check "warm window: cache served even though transcript is chmod 000" "$out_unreadable" "$c1"
check "warm window: exit 0 despite transcript being unreadable" "$rc" "0"

# Future-dated cache after a clock step: cache is dated further into the
# future than "now" (so age is negative, well inside the window) but the
# transcript is dated even further ahead still (so a raw mtime comparison
# would call the transcript "newer" and legacy logic would recompute). The
# window must win: no recompute, no jq, even though real new content (a
# second record) was appended.
transcript_fc="$TMPROOT/transcript-futurecache.jsonl"
record fc1 1000000 > "$transcript_fc"
c_fc=$(run_ccost session "$transcript_fc")
record fc2 1000000 >> "$transcript_fc"
cache_fc="$(session_cache_path "$transcript_fc")"
futuredate "$cache_fc" 7200
futuredate "$transcript_fc" 10800
before_jq=$(jq_call_count)
out_fc=$(PATH="$JQBIN:$PATH" CCOST_CACHE_DIR="$TMPROOT/cache" CLAUDE_PROJECTS_DIR="$TMPROOT/projects" bash "$CCOST" session "$transcript_fc")
after_jq=$(jq_call_count)
check "future-dated cache: negative age reads fresh despite 'newer' transcript" "$out_fc" "$c_fc"
check "future-dated cache: zero jq invocations" "$(( after_jq - before_jq ))" "0"

# Past-TTL + transcript newer: once the cache is at least TTL old, legacy
# freshness logic resumes and an actually-newer transcript forces a
# recompute (the window cannot hide staleness forever). The cache is seeded
# with an obviously-wrong sentinel so a served-cache-unchanged bug is
# distinguishable from a genuine recompute.
transcript_recompute="$TMPROOT/transcript-recompute.jsonl"
record q1 1000000 > "$transcript_recompute"
cache_recompute="$(session_cache_path "$transcript_recompute")"
echo "999.99" > "$cache_recompute"
backdate "$cache_recompute" 40
out_recompute=$(run_ccost session "$transcript_recompute")
check "past-TTL + transcript newer: recompute happens (legacy resumes)" "$out_recompute" "5"
check "past-TTL + transcript newer: cache rewritten with fresh value" "$(cat "$cache_recompute")" "5"
now_rc=$(date +%s)
cache_mtime_rc=$(clam_mtime_epoch "$cache_recompute")
check "past-TTL + transcript newer: rewrite restarts the TTL window (fresh mtime)" "$(( now_rc - cache_mtime_rc < 5 ))" "1"

# Past-TTL but cache still newer than an even-older transcript: the legacy
# mtime comparison (not the window) is what's serving the cache here, so
# this may already pass against the unimplemented script — it's a
# regression anchor for the "legacy logic applies past the window" clause,
# not a proof of new behavior.
transcript_legacy_past="$TMPROOT/transcript-legacypast.jsonl"
record p1 1000000 > "$transcript_legacy_past"
backdate "$transcript_legacy_past" 100
cache_legacy_past="$(session_cache_path "$transcript_legacy_past")"
echo "999.99" > "$cache_legacy_past"
backdate "$cache_legacy_past" 40
out_legacy_past=$(run_ccost session "$transcript_legacy_past")
check "past-TTL, cache still newer than transcript: legacy fast path serves cache" "$out_legacy_past" "999.99"
check "past-TTL, cache still newer than transcript: cache left untouched" "$(cat "$cache_legacy_past")" "999.99"

# Non-integer TTL falls back to the 30s default (not to disabled, not to a
# crash): a fresh cache must still survive an append+newer-mtime exactly
# like the default-TTL case above.
transcript_ni="$TMPROOT/transcript-noninteger.jsonl"
record ni1 1000000 > "$transcript_ni"
c_ni=$(run_ccost session "$transcript_ni")
record ni2 1000000 >> "$transcript_ni"
futuredate "$transcript_ni" 120
before_jq=$(jq_call_count)
out_ni=$(CCOST_SESSION_TTL_SECONDS="not-a-number" PATH="$JQBIN:$PATH" CCOST_CACHE_DIR="$TMPROOT/cache" CLAUDE_PROJECTS_DIR="$TMPROOT/projects" bash "$CCOST" session "$transcript_ni" 2>/dev/null)
after_jq=$(jq_call_count)
check "non-integer TTL falls back to default: cache served despite append" "$out_ni" "$c_ni"
check "non-integer TTL falls back to default: zero jq invocations" "$(( after_jq - before_jq ))" "0"

# TTL<=0 is the escape hatch back to pure legacy behavior: with the window
# disabled, an append must invalidate the cache immediately, with no grace
# window at all. CCOST_SESSION_TTL_SECONDS=0 is the brief's prescribed way to
# keep this legacy-path clause meaningful now that the default 30s window
# supersedes plain append-invalidation.
transcript_ttl0="$TMPROOT/transcript-ttl0.jsonl"
record z1 1000000 > "$transcript_ttl0"
c_ttl0=$(run_ccost session "$transcript_ttl0")
record z2 1000000 >> "$transcript_ttl0"
futuredate "$transcript_ttl0" 120
out_ttl0=$(CCOST_SESSION_TTL_SECONDS=0 CCOST_CACHE_DIR="$TMPROOT/cache" CLAUDE_PROJECTS_DIR="$TMPROOT/projects" bash "$CCOST" session "$transcript_ttl0")
check "TTL=0 disables window: append triggers immediate recompute" "$([[ "$out_ttl0" != "$c_ttl0" ]] && echo recomputed || echo stale)" "recomputed"

transcript_ttlneg="$TMPROOT/transcript-ttlneg.jsonl"
record g1 1000000 > "$transcript_ttlneg"
c_ttlneg=$(run_ccost session "$transcript_ttlneg")
record g2 1000000 >> "$transcript_ttlneg"
futuredate "$transcript_ttlneg" 120
out_ttlneg=$(CCOST_SESSION_TTL_SECONDS=-5 CCOST_CACHE_DIR="$TMPROOT/cache" CLAUDE_PROJECTS_DIR="$TMPROOT/projects" bash "$CCOST" session "$transcript_ttlneg")
check "negative TTL disables window: append triggers immediate recompute" "$([[ "$out_ttlneg" != "$c_ttlneg" ]] && echo recomputed || echo stale)" "recomputed"

# Unwritable cache: prints the freshly computed result without caching it.
# The cache dir (not the specific cache file, to avoid conflating "unwritable"
# with the unrelated file-vs-directory type question) is made read-only so
# the write fails purely on permissions, exactly like the Errors clause
# describes. This is unchanged/legacy behavior — expected to already pass.
transcript_unwritable="$TMPROOT/transcript-unwritable.jsonl"
record w1 2000000 > "$transcript_unwritable"
cache_unwritable="$(session_cache_path "$transcript_unwritable")"
chmod 555 "$TMPROOT/cache"
out_unwritable=$(run_ccost session "$transcript_unwritable" 2>/dev/null)
check "unwritable cache dir: no cache file created" "$([[ -f "$cache_unwritable" ]] && echo present || echo absent)" "absent"
chmod 755 "$TMPROOT/cache"
expected_unwritable=$(run_ccost session "$transcript_unwritable")
check "unwritable cache dir: still returns the freshly computed value" "$out_unwritable" "$expected_unwritable"

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

# The B02 session-window knob must not leak into day/week mode: day.cache is
# still fresh from the smoke test above, so a malformed session TTL value
# must have zero effect on it.
check "session TTL env has no effect on day mode" "$(CCOST_SESSION_TTL_SECONDS=not-a-number run_ccost day)" "5"

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
