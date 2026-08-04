#!/bin/bash
# Behavioral test for burn-tick.sh's sub-tick interpolator (burn_tick_frac):
# an EMA-calibrated dollars-per-weekly-point rate against a persistent anchor
# state file, re-anchored on any of {no prior state, USED change in either
# direction, SESSION_ID change}, with calibration strictly guarded to
# same-session +1 ticks whose cost delta lands strictly inside (0.5, 40).
# Covers the anchor/calibration/read invariants, the rate seed/clamp-on-read
# rule, the [0, 0.95] fraction clamp, the weekly-reset and malformed-state
# edge cases, the "no write on non-anchor / no write on invalid USED"
# side-effect rules, the awk-fork budget, and a concurrency smoke test.
#
# Contract: B02 burn-tick (plan 001-statusline-burnrate-uplift), docblock in
# burn-tick.sh.
#
# Run: bash plugins/statusline/lib/burn-tick.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BURN_TICK="$SCRIPT_DIR/burn-tick.sh"
. "$BURN_TICK"

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

# Numeric-tolerant check for decimal outputs (fraction / cost / rate fields):
# the contract fixes the VALUE, never a print format (%.2f vs %.4f vs bare),
# so an exact string match would pin an unstated formatting choice.
check_num() { # label got expected [epsilon]
  local label="$1" got="$2" expected="$3" eps="${4:-0.0001}"
  if awk -v g="$got" -v e="$expected" -v eps="$eps" \
      'BEGIN{ if (g !~ /^-?[0-9]*\.?[0-9]+$/) exit 1; d=g-e; if(d<0)d=-d; exit !(d<=eps) }' \
      2>/dev/null; then
    echo "PASS  $label"
  else
    echo "FAIL  $label -> got '$got', expected '$expected' (+/-$eps)"; FAILED=1
  fi
}

# field(file, idx): the idx'th space-separated field of the state file's
# first (only) record. Uses awk NR==1 rather than `read`/`wc -l` so a file
# with no trailing newline -- a perfectly valid "one line" -- still parses.
field() { # file idx
  awk -v i="$2" 'NR==1{print $i; exit}' "$1" 2>/dev/null
}

check_field() { # label file idx expected
  check "$1" "$(field "$2" "$3")" "$4"
}

check_field_num() { # label file idx expected [epsilon]
  check_num "$1" "$(field "$2" "$3")" "$4" "${5:-0.0001}"
}

# record_count(file): number of records, robust to a missing trailing newline
# (wc -l would undercount a final unterminated line).
record_count() { awk 'END{print NR}' "$1" 2>/dev/null; }

# field_count(file): NF of the first record.
field_count() { awk 'NR==1{print NF; exit}' "$1" 2>/dev/null; }

# call(used, session, cost, state_file): invokes the function under test,
# capturing stdout in $OUT, the return code in $RC, and stderr in $ERR.
call() { # used session cost state_file
  local errfile="$TMPROOT/.err-$$-$RANDOM"
  OUT=$(burn_tick_frac "$1" "$2" "$3" "$4" 2>"$errfile")
  RC=$?
  ERR=$(cat "$errfile" 2>/dev/null)
  rm -f "$errfile"
}

# === 1. Anchor condition: no prior state. Outputs: echoes 0 on every anchor.
#     Side effect: the state file is written whole with the new four-field
#     line; the rate is seeded at 4.5 (nothing prior to read). ==============
ST="$TMPROOT/s1-first-run"
call 10 sessA 2.00 "$ST"
check "first run: returns rc 0" "$RC" "0"
check_num "first run: echoes 0" "$OUT" "0"
check "first run: state file created" "$([ -f "$ST" ] && echo yes || echo no)" "yes"
check "first run: exactly one record written" "$(record_count "$ST")" "1"
check "first run: exactly four fields written" "$(field_count "$ST")" "4"
check_field     "first run: anchored_used field = USED" "$ST" 1 "10"
check_field     "first run: session field = SESSION_ID" "$ST" 2 "sessA"
check_field_num "first run: anchored_cost field = COST_USD" "$ST" 3 "2.00"
check_field_num "first run: rate seeded at 4.5 (no prior rate to read)" "$ST" 4 "4.5"

# === 2. Non-anchor call: same USED, same SESSION_ID -- reads the fraction as
#     (COST_USD - anchored_cost) / rate; the file is NOT written at all =====
ST="$TMPROOT/s2-nonanchor"
printf '10 sessA 2.00 5.0' > "$ST"
before=$(cat "$ST")
call 10 sessA 4.00 "$ST"
after=$(cat "$ST")
check "non-anchor: returns rc 0" "$RC" "0"
check_num "non-anchor: fraction = delta/rate (2.00/5.0 = 0.4)" "$OUT" "0.4"
check "non-anchor: state file byte-identical before/after (no write at all)" "$after" "$before"

# === 3. Anchor condition: USED differs (a jump other than +1) -- anchors;
#     calibration guard fails on the jump size, so the rate carries forward
#     unchanged =============================================================
ST="$TMPROOT/s3-jump"
printf '10 sessA 2.00 5.0' > "$ST"
call 13 sessA 6.00 "$ST"
check "USED jump (+3): returns rc 0" "$RC" "0"
check_num "USED jump (+3): echoes 0 (anchor, no estimate)" "$OUT" "0"
check_field     "USED jump (+3): anchored_used updates to new USED" "$ST" 1 "13"
check_field     "USED jump (+3): session unchanged" "$ST" 2 "sessA"
check_field_num "USED jump (+3): anchored_cost becomes the new baseline" "$ST" 3 "6.00"
check_field_num "USED jump (+3): rate NOT recalibrated (guard: not a +1 tick)" "$ST" 4 "5.0"

# === 4. Anchor condition: USED differs in the OTHER direction (a small
#     decrease, distinct from the full weekly-reset case below) -- still
#     anchors, in a set alongside "no prior state" and "session differs" ====
ST="$TMPROOT/s4-decrease"
printf '10 sessA 2.00 5.0' > "$ST"
call 9 sessA 2.50 "$ST"
check "USED decrease (10->9): returns rc 0" "$RC" "0"
check_num "USED decrease (10->9): echoes 0" "$OUT" "0"
check_field     "USED decrease: anchored_used updates down" "$ST" 1 "9"
check_field_num "USED decrease: rate NOT recalibrated (guard: not a +1 tick)" "$ST" 4 "5.0"

# === 5. Anchor condition: SESSION_ID differs (same USED) -- anchors against
#     the NEW session's cost baseline; the OLD session's rate is retained ===
ST="$TMPROOT/s5-session-switch"
printf '10 sessA 2.00 5.0' > "$ST"
call 10 sessB 999.00 "$ST"
check "session switch: returns rc 0" "$RC" "0"
check_num "session switch: echoes 0" "$OUT" "0"
check_field     "session switch: anchored_used unchanged (10)" "$ST" 1 "10"
check_field     "session switch: session field updates to new SESSION_ID" "$ST" 2 "sessB"
check_field_num "session switch: anchored_cost = new session's raw cost baseline (not a delta)" "$ST" 3 "999.00"
check_field_num "session switch: previous session's rate is retained" "$ST" 4 "5.0"

# === 6. Calibration guard: same-session requirement, isolated from the other
#     two guards -- USED IS exactly +1 and the cost delta IS in (0.5, 40),
#     but SESSION_ID differs -- must still anchor without calibrating =======
ST="$TMPROOT/s6-diffsession-plus1"
printf '10 sessA 2.00 5.0' > "$ST"
call 11 sessB 10.00 "$ST"
check_num "diff session (+1, in-range delta): echoes 0" "$OUT" "0"
check_field_num "diff session (+1, in-range delta): rate NOT recalibrated (guard: session differs)" "$ST" 4 "5.0"

# === 7. Calibration success: same session, USED exactly +1, delta strictly
#     inside (0.5, 40) -- rate updates via the equally-weighted EMA =========
ST="$TMPROOT/s7-calibrate"
printf '10 sessA 2.00 5.0' > "$ST"
call 11 sessA 10.00 "$ST"   # delta = 8.00, in (0.5, 40)
check_num "calibration: echoes 0 (anchor)" "$OUT" "0"
check_field     "calibration: anchored_used = 11" "$ST" 1 "11"
check_field_num "calibration: anchored_cost = 10.00" "$ST" 3 "10.00"
check_field_num "calibration: rate = EMA(5.0, 8.00) = 0.5*5.0+0.5*8.00 = 6.5" "$ST" 4 "6.5"

# === 8. Calibration guard: cost delta too small (0.4 < 0.5) -- fails
#     independently of the other two guards ==================================
ST="$TMPROOT/s8-delta-small"
printf '10 sessA 2.00 5.0' > "$ST"
call 11 sessA 2.40 "$ST"   # delta = 0.40
check_field_num "delta too small (0.4): rate NOT recalibrated" "$ST" 4 "5.0"
check_field_num "delta too small (0.4): anchored_cost still updates to 2.40" "$ST" 3 "2.40"

# 8b. Exact lower boundary: the interval is OPEN, so delta == 0.5 must NOT
#     calibrate either.
ST="$TMPROOT/s8b-delta-boundary-low"
printf '10 sessA 2.00 5.0' > "$ST"
call 11 sessA 2.50 "$ST"   # delta = exactly 0.5
check_field_num "delta at exact lower boundary (0.5, open interval): rate NOT recalibrated" "$ST" 4 "5.0"

# === 9. Calibration guard: cost delta too large (41 > 40) ====================
ST="$TMPROOT/s9-delta-large"
printf '10 sessA 2.00 5.0' > "$ST"
call 11 sessA 43.00 "$ST"   # delta = 41.00
check_field_num "delta too large (41): rate NOT recalibrated" "$ST" 4 "5.0"

# 9b. Exact upper boundary: delta == 40 must NOT calibrate either.
ST="$TMPROOT/s9b-delta-boundary-high"
printf '10 sessA 2.00 5.0' > "$ST"
call 11 sessA 42.00 "$ST"   # delta = exactly 40
check_field_num "delta at exact upper boundary (40, open interval): rate NOT recalibrated" "$ST" 4 "5.0"

# === 10. Edge case (highest-value in the block): weekly reset -- USED drops
#     sharply (e.g. 87 -> 0). Anchors, guard fails (not a +1 tick), returns
#     0 -- never a huge negative, never clamps to 0.95 ========================
ST="$TMPROOT/s10-weekly-reset"
printf '87 sessA 50.00 6.0' > "$ST"
call 0 sessA 51.00 "$ST"
check "weekly reset: returns rc 0" "$RC" "0"
check_num "weekly reset: echoes exactly 0 (not negative, not 0.95)" "$OUT" "0"
check_field     "weekly reset: anchored_used resets to 0" "$ST" 1 "0"
check_field_num "weekly reset: rate NOT recalibrated (guard: not a +1 tick)" "$ST" 4 "6.0"

# 10b. Same reset, but the PRIOR rate was itself out of the [1,20] range:
#      the guard still blocks calibration, and what carries forward is the
#      effective (seeded) read value, not the raw corrupt one -- see #17.
ST="$TMPROOT/s10b-weekly-reset-badrate"
printf '87 sessA 50.00 999' > "$ST"
call 0 sessA 51.00 "$ST"
check_num "weekly reset (corrupt prior rate): echoes 0" "$OUT" "0"
check_field_num "weekly reset (corrupt prior rate): carried-forward rate reads as the seeded 4.5, not the raw 999" "$ST" 4 "4.5"

# === 11. Edge case: COST_USD goes backwards within a session -- fraction
#     floors at 0, never negative; non-anchor, so no write ==================
ST="$TMPROOT/s11-cost-backward"
printf '10 sessA 5.00 5.0' > "$ST"
before=$(cat "$ST")
call 10 sessA 3.00 "$ST"   # delta = -2.00
after=$(cat "$ST")
check_num "cost goes backwards: fraction floors at 0" "$OUT" "0"
check "cost goes backwards: state file untouched (non-anchor)" "$after" "$before"

# === 12. Edge case: cost delta exceeding the rate clamps at 0.95, never 1.0
ST="$TMPROOT/s12-clamp-high"
printf '10 sessA 2.00 5.0' > "$ST"
call 10 sessA 1000.00 "$ST"   # delta = 998.00, far past the rate
check_num "delta far exceeds rate: fraction clamps at 0.95" "$OUT" "0.95"

# 12b. Boundary: delta == rate exactly (unclamped fraction would be exactly
#      1.0) -- still clamps to 0.95, never asserts a full tick.
ST="$TMPROOT/s12b-clamp-exact"
printf '10 sessA 2.00 5.0' > "$ST"
call 10 sessA 7.00 "$ST"   # delta = 5.00 = rate -> unclamped frac would be 1.0
check_num "delta exactly equals rate (unclamped frac = 1.0): still clamps to 0.95" "$OUT" "0.95"

# === 13. Edge case: malformed state file treated as ABSENT -- wrong field
#     count (never a partial parse) ==========================================
ST="$TMPROOT/s13-wrong-count"
printf '10 sessA 2.00' > "$ST"   # 3 fields, missing rate
call 10 sessA 2.00 "$ST"          # USED/SESSION/COST happen to match the file's face values
check_num "malformed (wrong field count): still echoes 0" "$OUT" "0"
check "malformed (wrong field count): stderr stays empty" "$ERR" ""
check "malformed (wrong field count): treated as absent -> ANCHORS (file is rewritten to 4 fields)" \
  "$(field_count "$ST")" "4"
check_field_num "malformed (wrong field count): rate reseeded to 4.5 (prior rate unreadable)" "$ST" 4 "4.5"

# === 14. Edge case: malformed state file -- non-numeric anchored_used field.
#     Guards against a naive numeric comparison erroring to stderr instead of
#     safely treating the record as absent. ==================================
ST="$TMPROOT/s14-nonnumeric-used"
printf 'notanumber sessA 2.00 5.0' > "$ST"
call 10 sessA 2.00 "$ST"
check_num "malformed (non-numeric anchored_used): still echoes 0" "$OUT" "0"
check "malformed (non-numeric anchored_used): stderr stays empty (no arithmetic error leaks)" "$ERR" ""
check_field "malformed (non-numeric anchored_used): treated as absent -> anchors with the new USED" "$ST" 1 "10"

# === 15. Edge case: malformed state file -- non-numeric RATE field, while
#     anchored_used AND session happen to match the current call's USED/
#     SESSION_ID exactly. A partial parser would misread this as a NON-anchor
#     call (same used, same session) and compute a fraction off the garbage
#     rate; the contract requires the whole record be treated as absent, so
#     this must still ANCHOR (write) and return 0. This is the malformed
#     case a partial parser is most likely to get wrong. =====================
ST="$TMPROOT/s15-nonnumeric-rate-matching"
printf '10 sessA 2.00 notanumber' > "$ST"
call 10 sessA 2.00 "$ST"
check_num "malformed (non-numeric rate, used/session match): echoes 0, not a garbage fraction" "$OUT" "0"
check "malformed (non-numeric rate, used/session match): stderr stays empty" "$ERR" ""
check "malformed (non-numeric rate, used/session match): record IS rewritten (proves it anchored, not passed through)" \
  "$(field_count "$ST")" "4"
check_field_num "malformed (non-numeric rate, used/session match): rate reseeded to 4.5" "$ST" 4 "4.5"

# === 16. Edge case: USED empty or non-numeric -- returns 0 and writes
#     NOTHING (distinct from every anchor case above, which always writes) ==
ST="$TMPROOT/s16-used-empty-nofile"
call "" sessA 2.00 "$ST"
check_num "USED empty, no prior file: echoes 0" "$OUT" "0"
check "USED empty, no prior file: state file NOT created" "$([ -e "$ST" ] && echo present || echo absent)" "absent"

ST="$TMPROOT/s16b-used-nonnumeric-existing"
printf '10 sessA 2.00 5.0' > "$ST"
before=$(cat "$ST")
call "abc" sessA 2.00 "$ST"
after=$(cat "$ST")
check_num "USED non-numeric, prior file exists: echoes 0" "$OUT" "0"
check "USED non-numeric, prior file exists: file byte-identical (untouched, not even rewritten)" "$after" "$before"

# === 17. Invariant: the rate is clamped into [1, 20] on read, seeded at 4.5
#     when absent OR out of range. A well-formed 4-field, all-numeric record
#     whose rate is wildly out of range (999) is not "absent" under the
#     malformed rule (every field IS numeric, count IS 4) -- but the
#     effective rate used for the fraction is the 4.5 seed: 0.90/4.5 = 0.2,
#     distinct from both a raw-999 read (0.90/999 ~= 0.0009) and a
#     clamp-to-boundary read (0.90/20 = 0.045). ==============================
ST="$TMPROOT/s17-rate-out-of-range"
printf '10 sessA 2.00 999' > "$ST"
call 10 sessA 2.90 "$ST"   # delta = 0.90
check_num "rate out of range (999) on read: fraction computed against the seeded 4.5 (0.90/4.5=0.2)" "$OUT" "0.2"

# === 18. Errors: nothing on stdout but the number; nothing on stderr in
#     normal operation ========================================================
ST="$TMPROOT/s18-clean-io"
printf '10 sessA 2.00 5.0' > "$ST"
call 11 sessA 10.00 "$ST"
check "clean I/O: stdout is exactly one bare decimal, nothing else" \
  "$([[ "$OUT" =~ ^[0-9]+(\.[0-9]+)?$ ]] && echo yes || echo no)" "yes"
check "clean I/O: stderr is empty in normal operation" "$ERR" ""

# === 19. Errors: an unwritable state file is not an error -- the write
#     fails silently, the estimate still degrades to 0, rendering continues,
#     and nothing leaks to stderr =============================================
ST="$TMPROOT/no-such-dir/unwritable-state"   # parent dir deliberately absent
call 10 sessA 2.00 "$ST"
check "unwritable state file: returns rc 0 (write failure is not a function error)" "$RC" "0"
check_num "unwritable state file: still echoes 0 (first-run anchor)" "$OUT" "0"
check "unwritable state file: no crash/error text leaks to stderr" "$ERR" ""
check "unwritable state file: no file materializes (parent dir absent)" "$([ -e "$ST" ] && echo present || echo absent)" "absent"

# Subsequent call at the same (still-unwritable) path: rendering continues,
# degrading to 0 again rather than erroring out.
call 10 sessA 2.00 "$ST"
check "unwritable state file: subsequent call also degrades cleanly to 0" "$OUT" "0"
check "unwritable state file: subsequent call also returns rc 0" "$RC" "0"

# === 20. Invariant: the state file is written WHOLE, never appended to or
#     edited in place -- a long prior line is fully replaced by a short new
#     one, with no leftover trailing bytes ====================================
ST="$TMPROOT/s20-written-whole"
pad=$(printf 'X%.0s' $(seq 1 200))
printf '10 sess-%s 222222222222.00 5.0' "$pad" > "$ST"
call 10 s2 3.00 "$ST"   # session switch -> anchor; new line is far shorter than the old one
check "written whole: exactly one record after the rewrite (no leftover appended line)" "$(record_count "$ST")" "1"
check_field "written whole: new (short) session value, no trace of the old long one" "$ST" 2 "s2"
newlen=$(wc -c < "$ST" 2>/dev/null | tr -d ' ')
check "written whole: file length matches a fresh short line, not old+new (no leftover bytes)" \
  "$([ "${newlen:-999}" -lt 40 ] && echo yes || echo no)" "yes"

# === 21. Invariant: forks awk at most once per call; never forks date, cat,
#     or a subshell pipeline (PATH-shim harness, mirroring context.test.sh's
#     external-process-count pattern in its own house style) ================
SHIM_DIR="$TMPROOT/fork-shim"; mkdir -p "$SHIM_DIR"
for _tool in awk date cat; do
  _real=$(command -v "$_tool" 2>/dev/null) || continue
  printf '#!/bin/bash\necho "%s" >> "${FORK_LOG:-/dev/null}"\nexec "%s" "$@"\n' \
    "$_tool" "$_real" > "$SHIM_DIR/$_tool"
  chmod +x "$SHIM_DIR/$_tool"
done

# run_forkcheck(used, session, cost, state_file): sources burn-tick.sh fresh
# in a subshell with the shim tools first on PATH, calls the function once,
# and echoes the path of the fork log for the caller to inspect.
run_forkcheck() { # used session cost state_file
  local log="$TMPROOT/fork-$$-$RANDOM.log"
  : > "$log"
  PATH="$SHIM_DIR:$PATH" FORK_LOG="$log" \
    bash -c '. "$1"; burn_tick_frac "$2" "$3" "$4" "$5"' _ \
    "$BURN_TICK" "$1" "$2" "$3" "$4" >/dev/null 2>&1
  echo "$log"
}

# 21a. Read-only fraction path (the most frequently exercised call: once per
#      statusline render, on every non-tick refresh).
ST="$TMPROOT/s21a-fork-readonly"
printf '10 sessA 2.00 5.0' > "$ST"
log=$(run_forkcheck 10 sessA 4.00 "$ST")
check "read-only path: forks awk at most once" \
  "$([ "$(grep -cxF awk "$log")" -le 1 ] && echo yes || echo no)" "yes"
check "read-only path: never forks date" "$(grep -cxF date "$log")" "0"
check "read-only path: never forks cat" "$(grep -cxF cat "$log")" "0"

# 21b. Anchor + calibrate path (the busiest arithmetic: delta, EMA, clamp).
ST="$TMPROOT/s21b-fork-calibrate"
printf '10 sessA 2.00 5.0' > "$ST"
log=$(run_forkcheck 11 sessA 10.00 "$ST")
check "calibration path: forks awk at most once" \
  "$([ "$(grep -cxF awk "$log")" -le 1 ] && echo yes || echo no)" "yes"
check "calibration path: never forks date" "$(grep -cxF date "$log")" "0"
check "calibration path: never forks cat" "$(grep -cxF cat "$log")" "0"

# === 22. Edge case: concurrent sessions racing on one state file -- last
#     writer wins, no locking needed; smoke-test that every racer still
#     returns valid output and the file is never left structurally corrupt =
ST="$TMPROOT/s22-concurrency"
OUT_DIR="$TMPROOT/s22-out"; mkdir -p "$OUT_DIR"
for i in $(seq 1 8); do
  ( r=$(burn_tick_frac 5 "sess$i" "$i.00" "$ST" 2>/dev/null); printf '%s' "$r" > "$OUT_DIR/$i" ) &
done
wait
bad=0
for f in "$OUT_DIR"/*; do
  v=$(cat "$f")
  [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] || bad=$((bad+1))
done
check "concurrency smoke: every concurrent racer returns valid decimal output (no crash/garbage)" "$bad" "0"
check "concurrency smoke: state file remains exactly one record after concurrent writes" "$(record_count "$ST")" "1"
check "concurrency smoke: state file remains exactly four fields after concurrent writes" "$(field_count "$ST")" "4"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
