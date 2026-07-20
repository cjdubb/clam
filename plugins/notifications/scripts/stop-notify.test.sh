#!/bin/bash
# Functional test for stop-notify.sh — summons-driven, transition-only ringing.
# Run: bash plugins/notifications/scripts/stop-notify.test.sh   (exits non-zero on failure)
#
# Feeds the hook crafted Stop stdin JSON ({"cwd": <tmpdir>}) and asserts the
# stdout (terminalSequence => rang the bell), the transition marker
# .local/.last-stop-state, and the .local/.last-silent-stop timestamp that
# push-notify.sh reads. osascript is stubbed via a PATH shim so no desktop
# notification fires; TMUX is left unset so the tmux-border branch is inert. The
# real ../lib/states.sh (the vendored states manifest) is sourced by the hook
# (this is an integration test of the summons gate, not a stub of it). No network.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/stop-notify.sh"

TMPROOT=$(mktemp -d)

# PATH shim: swallow osascript so the macOS toast never actually fires. Real
# jq/date/basename/md5 still resolve (shim is prepended, not a replacement).
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/osascript" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMPROOT/bin/osascript"
export PATH="$TMPROOT/bin:$PATH"
unset TMUX TMUX_PANE
# Pin the plugin gate enabled so an ambient disable cannot skew the suite.
export CLAM_NOTIFICATIONS_GATE=enabled

WT="$TMPROOT/wt"
mkdir -p "$WT/.local"
marker="$WT/.local/.last-stop-state"
silent_stamp="$WT/.local/.last-silent-stop"
silent_flag="$WT/.local/.silent-stop"

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }

# --- Harness ---------------------------------------------------------------
run_stop() { # cwd -> sets OUT (stdout)
  local json
  json=$(jq -n --arg cwd "$1" '{cwd: $cwd}')
  OUT=$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)
}
set_state() { # state ("" -> remove TODO.md entirely)
  if [[ -n "$1" ]]; then
    printf 'State: %s\n' "$1" > "$WT/.local/TODO.md"
  else
    rm -f "$WT/.local/TODO.md"
  fi
}
clear_silent_stamp() { rm -f "$silent_stamp"; }

assert_rings()  { case "$OUT" in *terminalSequence*) pass "$1 (rings)";; *) fail "$1 -> expected terminalSequence, got '$OUT'";; esac; }
assert_silent() { if [[ -z "$OUT" ]]; then pass "$1 (silent)"; else fail "$1 -> expected empty stdout, got '$OUT'"; fi; }
assert_marker()    { local g=""; [[ -f "$marker" ]] && g=$(cat "$marker"); if [[ "$g" == "$2" ]]; then pass "$1 (marker='$2')"; else fail "$1 -> marker '$g', expected '$2'"; fi; }
assert_no_marker() { if [[ ! -f "$marker" ]]; then pass "$1 (no marker)"; else fail "$1 -> marker present: '$(cat "$marker")'"; fi; }
assert_silent_stamped()     { if [[ -f "$silent_stamp" ]]; then pass "$1 (.last-silent-stop written)"; else fail "$1 -> .last-silent-stop missing"; fi; }
assert_not_silent_stamped() { if [[ ! -f "$silent_stamp" ]]; then pass "$1 (.last-silent-stop absent)"; else fail "$1 -> .last-silent-stop written on ring path"; fi; }

# --- (a) Transition into each summoning State rings, records the marker, and
#         (ring path) does NOT write .last-silent-stop -----------------------
for s in "Blocked" "Waiting For Decision" "Awaiting User Review"; do
  rm -f "$marker"           # no prior epoch -> a clean transition
  set_state "$s"
  clear_silent_stamp
  run_stop "$WT"
  assert_rings "transition into '$s'"
  assert_marker "'$s' recorded as marker" "$s"
  assert_not_silent_stamped "ring into '$s' leaves .last-silent-stop absent"
done

# --- (b) Second stop in the same summoning State is silent + writes the stamp
# (state + marker are both "Awaiting User Review" from the last (a) iteration)
clear_silent_stamp
run_stop "$WT"
assert_silent "re-stop in same summoning State"
assert_silent_stamped "same-state re-stop writes .last-silent-stop"
assert_marker "marker unchanged on re-stop" "Awaiting User Review"

# --- (c) Deleting the marker (a user prompt) re-arms the same State ---------
rm -f "$marker"             # prompt-timestamp.sh clears the epoch
clear_silent_stamp
run_stop "$WT"
assert_rings "same State rings again after marker cleared"
assert_marker "marker re-recorded" "Awaiting User Review"
assert_not_silent_stamped "re-armed ring leaves .last-silent-stop absent"

# --- (d) Parked non-summoning State: silent, records marker, writes stamp ---
set_state "Awaiting CI"
clear_silent_stamp
run_stop "$WT"
assert_silent "parked non-summoning State (Awaiting CI)"
assert_marker "non-summoning State still recorded" "Awaiting CI"
assert_silent_stamped "non-summoning stop writes .last-silent-stop"

# --- (e) Summoning State after a non-summoning marker rings (re-entry) ------
set_state "Blocked"
clear_silent_stamp
run_stop "$WT"
assert_rings "Blocked after an Awaiting CI marker (re-entry)"
assert_marker "re-entry records Blocked" "Blocked"
assert_not_silent_stamped "re-entry ring leaves .last-silent-stop absent"

# --- (f) .silent-stop wins: silent, flag consumed, marker NOT updated -------
# Marker is "Blocked" going in; the escape hatch exits before the State read.
set_state "Awaiting User Review"
touch "$silent_flag"
clear_silent_stamp
run_stop "$WT"
assert_silent ".silent-stop forces silence"
assert_marker ".silent-stop leaves the marker untouched" "Blocked"
if [[ ! -f "$silent_flag" ]]; then pass ".silent-stop flag consumed"; else fail ".silent-stop flag not consumed"; fi
assert_silent_stamped ".silent-stop path writes .last-silent-stop"

# --- (g) No TODO.md: silent, marker removed --------------------------------
printf 'Blocked' > "$marker"   # establish a known marker to prove removal
set_state ""                   # remove TODO.md
clear_silent_stamp
run_stop "$WT"
assert_silent "no TODO.md"
assert_no_marker "no TODO.md removes the marker"
assert_silent_stamped "no-TODO stop writes .last-silent-stop"

# --- (h) Empty or unknown State: silent, marker removed --------------------
printf 'Blocked' > "$marker"
printf 'Current Task: something\n' > "$WT/.local/TODO.md"   # State field absent
clear_silent_stamp
run_stop "$WT"
assert_silent "empty State (no State field)"
assert_no_marker "empty State removes the marker"
assert_silent_stamped "empty-State stop writes .last-silent-stop"

printf 'Blocked' > "$marker"
set_state "Bogus State"        # name not in the manifest
clear_silent_stamp
run_stop "$WT"
assert_silent "unknown State"
assert_no_marker "unknown State removes the marker"
assert_silent_stamped "unknown-State stop writes .last-silent-stop"

# --- (i) Plugin gate: CLAM_NOTIFICATIONS_GATE=disabled -> instant silent exit;
#         marker and silent stamp are left completely untouched ---------------
printf 'Blocked' > "$marker"
set_state "Waiting For Decision"   # a fresh transition that would ring if the gate were open
clear_silent_stamp
OUT=$(jq -n --arg cwd "$WT" '{cwd: $cwd}' | CLAM_NOTIFICATIONS_GATE=disabled bash "$HOOK" 2>/dev/null)
assert_silent "gate disabled"
assert_marker "gate disabled leaves the marker untouched" "Blocked"
assert_not_silent_stamped "gate disabled writes no .last-silent-stop"

rm -rf "$TMPROOT"
echo ""
if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
