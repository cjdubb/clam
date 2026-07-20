#!/bin/bash
# Functional test for desktop_notify() — feature-detected desktop notification
# helper (lib/desktop-notify.sh).
# Run: bash plugins/notifications/lib/desktop-notify.test.sh   (exits non-zero on failure)
#
# Sources the lib directly (not via a hook) and shims osascript/notify-send/
# paplay via PATH-directory swaps so no real notification or sound ever
# fires — each shim appends its invocation (argc + every arg) to a log file
# instead of doing anything. Which shim directories are on PATH for a given
# call determines which tool(s) desktop_notify "sees" as installed, letting
# each of the four cases below isolate exactly one code path. PATH is scoped
# per-call via the `VAR=val command` prefix form so it never leaks to the
# rest of the test or to jq/mktemp/etc. used by the harness itself.
#
# The Linux sound-file existence check is indirected through
# _desktop_notify_sound_file() (see desktop-notify.sh) purely so this test can
# point it at a temp file: the real path (/usr/share/sounds/...) is root-owned
# and SIP-protected, so a test cannot create it there. No network involved.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/desktop-notify.sh"

# Isolate from the ambient shell: a dev/CI environment may already export
# CLAUDE_NOTIFY_SOUND (it's a normal user setting), which would make the
# "default" sound-name assertions below flaky. Cases that specifically test
# CLAUDE_NOTIFY_SOUND override it explicitly per-call.
unset CLAUDE_NOTIFY_SOUND

TMPROOT=$(mktemp -d)
CALL_LOG="$TMPROOT/calls.log"
: > "$CALL_LOG"
export CALL_LOG

# write_shim <name> <dir> — writes a fake <name> binary into <dir> that logs
# its own name plus every argument (one line per arg) to $CALL_LOG and exits
# 0. $CALL_LOG is read from the environment at run time (inherited from the
# exporting parent shell), not baked in, so the heredoc body needs no
# generation-time substitution beyond the literal shim name.
write_shim() {
    local name="$1" dir="$2"
    mkdir -p "$dir"
    cat > "$dir/$name" <<SHIM
#!/bin/bash
{
  printf '$name ARGC=%d\n' "\$#"
  i=0
  for a in "\$@"; do
    i=\$((i+1))
    printf '$name ARG%d=%s\n' "\$i" "\$a"
  done
} >> "\$CALL_LOG"
exit 0
SHIM
    chmod +x "$dir/$name"
}

BIN_OSA="$TMPROOT/bin-osa"
BIN_NS="$TMPROOT/bin-ns"
BIN_PA="$TMPROOT/bin-pa"
BIN_EMPTY="$TMPROOT/bin-empty"
mkdir -p "$BIN_EMPTY"
write_shim osascript "$BIN_OSA"
write_shim notify-send "$BIN_NS"
write_shim paplay "$BIN_PA"

# shellcheck source=./desktop-notify.sh
source "$LIB"

# Test seam: point the sound-file check at a temp file we control instead of
# the real fixed system path.
FAKE_SOUND="$TMPROOT/fake-sound.oga"
_desktop_notify_sound_file() { printf '%s' "$FAKE_SOUND"; }

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }

reset_log() { : > "$CALL_LOG"; }
log_has() { grep -qF "$1" "$CALL_LOG"; }        # exact substring
log_lacks() { ! grep -qF "$1" "$CALL_LOG"; }

# =====================================================================
# (a) osascript present -> invoked with correctly-escaped args, incl.
#     quotes in title/body. macOS output must be byte-identical to the
#     pre-helper command line for the same inputs.
# =====================================================================
reset_log
TITLE='wt "one"'
BODY='needs "attention" now'
PATH="$BIN_OSA" desktop_notify "$TITLE" "$BODY"
RC=$?
[[ "$RC" == "0" ]] && pass "(a) exit 0" || fail "(a) exit 0 -> got $RC"
log_has "osascript ARGC=2" && pass "(a) osascript invoked with 2 args" || fail "(a) osascript ARGC=2 not found in log"

esc_title="${TITLE//\"/\\\"}"
esc_body="${BODY//\"/\\\"}"
expected_script="display notification \"$esc_body\" with title \"$esc_title\" sound name \"default\""
log_has "osascript ARG2=$expected_script" \
    && pass "(a) osascript script arg is escaped exactly as before" \
    || fail "(a) expected escaped script line not found: '$expected_script'"

log_lacks "notify-send" && pass "(a) notify-send not invoked" || fail "(a) notify-send unexpectedly invoked"
log_lacks "paplay" && pass "(a) paplay not invoked" || fail "(a) paplay unexpectedly invoked"

# CLAUDE_NOTIFY_SOUND is honored unchanged (parity check on the sound clause).
reset_log
CLAUDE_NOTIFY_SOUND="Glass" PATH="$BIN_OSA" desktop_notify "wt" "hello"
log_has 'sound name "Glass"' \
    && pass "(a) CLAUDE_NOTIFY_SOUND overrides the sound clause" \
    || fail "(a) custom CLAUDE_NOTIFY_SOUND not reflected in osascript arg"

# =====================================================================
# (b) osascript absent, notify-send+paplay present (+ sound file present)
#     -> both invoked; notify-send gets the RAW (unescaped) args.
# =====================================================================
reset_log
touch "$FAKE_SOUND"
TITLE='wt "two"'
BODY='needs "attention" badly'
PATH="$BIN_NS:$BIN_PA" desktop_notify "$TITLE" "$BODY"
RC=$?
wait  # paplay is backgrounded; let its shim finish writing to the log
[[ "$RC" == "0" ]] && pass "(b) exit 0" || fail "(b) exit 0 -> got $RC"
log_has "notify-send ARG1=$TITLE" && pass "(b) notify-send gets raw (unescaped) title" || fail "(b) notify-send title not raw/unescaped"
log_has "notify-send ARG2=$BODY" && pass "(b) notify-send gets raw (unescaped) body" || fail "(b) notify-send body not raw/unescaped"
log_has "paplay ARG1=$FAKE_SOUND" && pass "(b) paplay invoked with the sound file" || fail "(b) paplay not invoked with sound file"
log_lacks "osascript" && pass "(b) osascript not invoked" || fail "(b) osascript unexpectedly invoked"

# =====================================================================
# (c) neither osascript nor notify-send present -> silent no-op, exit 0.
# =====================================================================
reset_log
PATH="$BIN_EMPTY" desktop_notify "wt" "hello"
RC=$?
[[ "$RC" == "0" ]] && pass "(c) exit 0 with nothing on PATH" || fail "(c) exit 0 -> got $RC"
[[ ! -s "$CALL_LOG" ]] && pass "(c) nothing invoked" || fail "(c) unexpected invocation: $(cat "$CALL_LOG")"

# =====================================================================
# (d) notify-send present, paplay absent OR sound file missing ->
#     toast only, still exit 0.
# =====================================================================
# (d1) paplay entirely absent from PATH.
reset_log
PATH="$BIN_NS" desktop_notify "wt" "hello"
RC=$?
[[ "$RC" == "0" ]] && pass "(d1) exit 0, paplay absent" || fail "(d1) exit 0 -> got $RC"
log_has "notify-send ARG1=wt" && pass "(d1) notify-send still invoked" || fail "(d1) notify-send not invoked"
log_lacks "paplay" && pass "(d1) paplay not invoked (absent from PATH)" || fail "(d1) paplay unexpectedly invoked"

# (d2) paplay present but the sound file is missing.
reset_log
rm -f "$FAKE_SOUND"
PATH="$BIN_NS:$BIN_PA" desktop_notify "wt" "hello"
RC=$?
[[ "$RC" == "0" ]] && pass "(d2) exit 0, sound file missing" || fail "(d2) exit 0 -> got $RC"
log_has "notify-send ARG1=wt" && pass "(d2) notify-send still invoked" || fail "(d2) notify-send not invoked"
log_lacks "paplay" && pass "(d2) paplay not invoked (sound file missing)" || fail "(d2) paplay unexpectedly invoked"

rm -rf "$TMPROOT"
echo ""
if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
