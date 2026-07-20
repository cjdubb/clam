#!/bin/bash
# Cross-platform desktop notification helper. Sourced by the attention-grab
# hooks (scripts/notify.sh, scripts/stop-notify.sh) so there is one
# source of truth for "pop a local toast + sound" across macOS and Linux.
#
# Usage:
#   desktop_notify <title> <body>
#
# Feature-detects the platform's notifier, in this order:
#   1. osascript (macOS) — invoked exactly as the hooks did before this helper
#      existed: same AppleScript double-quote escaping, same
#      CLAUDE_NOTIFY_SOUND sound-name clause, output discarded. macOS behavior
#      is byte-identical to the pre-helper code.
#   2. notify-send (Linux) — toast with the RAW title/body (argv-passed, no
#      shell re-interpretation, no escaping). Followed by a backgrounded
#      paplay of the freedesktop "complete" sound when paplay and the sound
#      file both exist. Sound playback is backgrounded so the hook never
#      blocks on it (hooks run under a 5s timeout).
#   3. Neither present (e.g. SSH session with no DISPLAY/DBUS) — silent no-op.
#
# Every failure mode is silent, matching the pre-existing osascript behavior
# (stderr discarded), so callers always continue past this function. No new
# env vars: CLAUDE_NOTIFY_SOUND keeps its existing macOS-only meaning; the
# Linux sound file is a fixed path, not configurable.
#
# bash 3.2 safe (macOS /bin/bash is 3.2): no associative arrays, no bash-4+
# string ops.

# _desktop_notify_sound_file -> the Linux notification sound file path.
# Indirected through a function (rather than inlined in desktop_notify)
# purely so tests can override it to point at a temp file: the real path is
# root-owned and SIP-protected on macOS, so a test cannot create it there to
# exercise the "sound file present" branch. Not configurable by callers or
# env vars — this is an internal test seam, not part of the public interface.
_desktop_notify_sound_file() {
    printf '%s' "/usr/share/sounds/freedesktop/stereo/complete.oga"
}

desktop_notify() {
    local title="$1"
    local body="$2"

    if command -v osascript >/dev/null 2>&1; then
        # Escape double quotes for AppleScript strings — byte-identical to
        # the pre-helper behavior in notify.sh/stop-notify.sh.
        local esc_title="${title//\"/\\\"}"
        local esc_body="${body//\"/\\\"}"
        osascript -e "display notification \"$esc_body\" with title \"$esc_title\" sound name \"${CLAUDE_NOTIFY_SOUND:-default}\"" >/dev/null 2>&1
        return 0
    fi

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$body" 2>/dev/null || true
        local sound_file
        sound_file="$(_desktop_notify_sound_file)"
        if command -v paplay >/dev/null 2>&1 && [[ -f "$sound_file" ]]; then
            # Backgrounded: never block the hook on sound playback.
            paplay "$sound_file" 2>/dev/null &
        fi
        return 0
    fi

    return 0
}
