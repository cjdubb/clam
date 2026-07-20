#!/bin/bash
# Functional test for push-notify.sh — the Notification-event push gate.
# Run: bash plugins/notifications/scripts/push-notify.test.sh   (exits non-zero on failure)
#
# Feeds the hook synthetic Notification stdin JSON and asserts whether it pushes,
# by counting invocations of a stubbed curl (PATH shim — the hook runs the real
# script as a subprocess, so a shell-function stub would not reach it). Pins the
# P7 contract (clam-code#264): an idle Notification pushes ONLY in a summoning
# TODO State (Blocked / Waiting For Decision / Awaiting User Review); a parked,
# non-summoning State suppresses it; a permission prompt ALWAYS pushes, bypassing
# the silent-stop stack and the state gate. No network.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/push-notify.sh"

TMPROOT=$(mktemp -d)

# PATH shim: stub curl so notify() records a push instead of hitting the network.
# Real jq/date/basename/cat still resolve (shim is prepended, not a replacement).
BIN="$TMPROOT/bin"
mkdir -p "$BIN"
CURL_LOG="$TMPROOT/curl.log"
: > "$CURL_LOG"
cat > "$BIN/curl" <<EOF
#!/bin/bash
echo PUSH >> "$CURL_LOG"
exit 0
EOF
chmod +x "$BIN/curl"
export PATH="$BIN:$PATH"

# Enable the push path but neutralise notify()'s internal gates so each allowed
# call yields exactly one curl line. The plugin gate is pinned enabled so an
# ambient CLAM_NOTIFICATIONS_GATE=disabled cannot skew the suite.
export CLAM_NOTIFICATIONS_GATE=enabled
export CLAUDE_PUSH_NTFY_TOPIC="dummy-topic"
export CLAUDE_PUSH_ACTIVITY_GATE_SECONDS=0
export CLAUDE_PUSH_DEBOUNCE_SECONDS=0
export CLAUDE_PUSH_DEDUP=0
export CLAUDE_PUSH_SILENT_STOP_WINDOW_SECONDS=90
export TMUX="" TMUX_PANE="" CLAUDE_PUSH_BODY_MODE=""

# push-notify passes the session cwd as the worktree dir, so notify()'s body read
# resolves it directly (no trees-dir env var). WT_PATH has a real .local/ so it is
# adopted; state read and body read point at the same TODO.md.
WT_PATH="$TMPROOT/wt"
mkdir -p "$WT_PATH/.local"
TODO="$WT_PATH/.local/TODO.md"

FAILED=0
count() { wc -l < "$CURL_LOG" | tr -d ' '; }
PREV=0
expect() { # label expected-delta(0|1)
  local now; now=$(count)
  if (( now - PREV == $2 )); then echo "PASS  $1"; else echo "FAIL  $1 -> delta $((now - PREV)), expected $2"; FAILED=1; fi
  PREV="$now"
}

# run_notify <state|__none__> <notification_type|""> <message|"">  -> runs the hook
run_notify() {
  if [[ "$1" == "__none__" ]]; then rm -f "$TODO"; else printf 'State: %s\n' "$1" > "$TODO"; fi
  local json
  json=$(jq -n --arg cwd "$WT_PATH" --arg nt "$2" --arg m "$3" '
    {cwd: $cwd}
    + (if $nt == "" then {} else {notification_type: $nt} end)
    + (if $m  == "" then {} else {message: $m} end)')
  printf '%s' "$json" | bash "$HOOK" 2>/dev/null
}

IDLE_MSG="Claude is waiting for your input"
PERM_MSG="Claude needs your permission to use Bash"

# --- Idle event: gated on summoning-ness of the TODO State -------------------
run_notify "Awaiting CI"            idle_prompt "$IDLE_MSG"; expect "idle + Awaiting CI (parked non-summoning) suppressed" 0
run_notify "Awaiting Bot Review"    idle_prompt "$IDLE_MSG"; expect "idle + Awaiting Bot Review suppressed" 0
run_notify "Awaiting Reviewer Assignment" idle_prompt "$IDLE_MSG"; expect "idle + Awaiting Reviewer Assignment suppressed" 0
run_notify "Awaiting Human Review"  idle_prompt "$IDLE_MSG"; expect "idle + Awaiting Human Review suppressed" 0
run_notify "Awaiting Merge Queue"   idle_prompt "$IDLE_MSG"; expect "idle + Awaiting Merge Queue suppressed" 0
run_notify "Blocked"                idle_prompt "$IDLE_MSG"; expect "idle + Blocked (summoning) pushes" 1
run_notify "Waiting For Decision"   idle_prompt "$IDLE_MSG"; expect "idle + Waiting For Decision (summoning) pushes" 1
run_notify "Awaiting User Review"   idle_prompt "$IDLE_MSG"; expect "idle + Awaiting User Review (parked summoning) pushes" 1

# Fail-open: non-parked / unknown / no-TODO idle still pushes (a wedged
# non-parked session must summon; the leak is specifically parked non-summoning).
run_notify "In Progress"            idle_prompt "$IDLE_MSG"; expect "idle + In Progress (active) pushes (fail-open)" 1
run_notify "garbage-xyz"            idle_prompt "$IDLE_MSG"; expect "idle + unknown State pushes (fail-open)" 1
run_notify "__none__"               idle_prompt "$IDLE_MSG"; expect "idle + no TODO (Go Commando) pushes (fail-open)" 1

# --- Permission event: ALWAYS pushes, regardless of State -------------------
run_notify "Awaiting CI"            permission_prompt "$PERM_MSG"; expect "permission + Awaiting CI pushes (bypasses state gate)" 1
run_notify "Awaiting Human Review"  permission_prompt "$PERM_MSG"; expect "permission + Awaiting Human Review pushes" 1

# --- notification_type absent: fall back to message-text classification ------
run_notify "Awaiting CI"            "" "$PERM_MSG"; expect "permission via message fallback pushes (no notification_type)" 1
run_notify "Awaiting CI"            "" "$IDLE_MSG"; expect "idle via message fallback suppressed in parked non-summoning" 0

# --- .silent-stop: suppresses idle, NOT permission --------------------------
touch "$WT_PATH/.local/.silent-stop"
run_notify "Blocked"                idle_prompt      "$IDLE_MSG"; expect "idle + .silent-stop suppressed (even summoning)" 0
run_notify "Blocked"                permission_prompt "$PERM_MSG"; expect "permission bypasses .silent-stop" 1
rm -f "$WT_PATH/.local/.silent-stop"

# --- .last-silent-stop window: suppresses idle, NOT permission --------------
printf '%s' "$(date +%s)" > "$WT_PATH/.local/.last-silent-stop"
run_notify "Blocked"                idle_prompt      "$IDLE_MSG"; expect "idle within silent-stop window suppressed" 0
run_notify "Blocked"                permission_prompt "$PERM_MSG"; expect "permission bypasses silent-stop window" 1
rm -f "$WT_PATH/.local/.last-silent-stop"

# --- Plan mode: suppresses everything (unchanged) ---------------------------
printf 'plan' > "$WT_PATH/.local/.permission-mode"
run_notify "Blocked"                permission_prompt "$PERM_MSG"; expect "plan mode suppresses even permission" 0
run_notify "Blocked"                idle_prompt       "$IDLE_MSG"; expect "plan mode suppresses idle" 0
rm -f "$WT_PATH/.local/.permission-mode"

# --- Env guard: topic unset -> no push --------------------------------------
printf 'State: Blocked\n' > "$TODO"
printf '%s' "$(jq -n --arg cwd "$WT_PATH" '{cwd:$cwd, notification_type:"idle_prompt", message:"x"}')" \
  | CLAUDE_PUSH_NTFY_TOPIC="" bash "$HOOK" 2>/dev/null
expect "topic unset -> no push (env guard)" 0

# --- Plugin gate: CLAM_NOTIFICATIONS_GATE=disabled -> no push, even for a
# permission prompt (the gate sits above every other check) ------------------
printf '%s' "$(jq -n --arg cwd "$WT_PATH" '{cwd:$cwd, notification_type:"permission_prompt", message:"x"}')" \
  | CLAM_NOTIFICATIONS_GATE=disabled bash "$HOOK" 2>/dev/null
expect "plugin gate disabled -> no push (even permission)" 0

rm -rf "$TMPROOT"
echo ""
if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
