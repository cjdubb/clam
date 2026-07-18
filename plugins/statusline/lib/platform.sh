#!/bin/bash

# Shared platform-detection helpers for clam-code setup-time scripts.
# Source this file at the top of any script that needs an OS-aware path or
# install hint (setup.sh, claude-rules.sh, managed-settings-setup.sh,
# cleanup.sh, cleanup-legacy.sh). Bash 3.2-safe: no associative arrays, no
# `${var,,}`, no `mapfile`.
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/platform.sh"

# clam_os -> "darwin" or "linux".
# Reads `uname -s` at CALL time (not cached at source time) so tests can
# PATH-shim `uname` and exercise both branches from one process. Anything
# that isn't Darwin (including an unrecognized uname, e.g. a BSD variant)
# falls through to "linux" — there is no third code path in any caller, so a
# crash-on-unknown-platform would be strictly worse than the closest-fit
# fallback.
clam_os() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "darwin"
    else
        echo "linux"
    fi
}

# clam_mtime_epoch <path> -> last-modified time, in epoch seconds (0 if the
# path is missing or unstatable). Picks ONE stat invocation for the current
# platform instead of chaining `stat -f ... || stat -c ...`: on GNU coreutils
# `-f` means "filesystem status" (df-like, not a format flag), so a BSD-style
# `stat -f %m FILE` fails on GNU but still prints a multi-line filesystem dump
# for FILE to stdout before the `||` fallback fires, corrupting anything that
# captures the combined output.
clam_mtime_epoch() {
    if [[ "$(clam_os)" == "darwin" ]]; then
        stat -f %m "$1" 2>/dev/null || echo 0
    else
        stat -c %Y "$1" 2>/dev/null || echo 0
    fi
}

# clam_birth_epoch <path> -> creation time, in epoch seconds (0 if missing,
# unstatable, or the filesystem doesn't track birth time). Same GNU/BSD `-f`
# collision as clam_mtime_epoch, so it gets the same single-invocation fix.
clam_birth_epoch() {
    if [[ "$(clam_os)" == "darwin" ]]; then
        stat -f %B "$1" 2>/dev/null || echo 0
    else
        stat -c %W "$1" 2>/dev/null || echo 0
    fi
}

# clam_managed_settings_path -> the OS-level managed-settings.json path for
# the current platform. These are the ONLY paths where Claude Code honors
# requiredMinimumVersion / requiredMaximumVersion (see decision-logs/
# SETTINGS-DECISIONS.md).
clam_managed_settings_path() {
    if [[ "$(clam_os)" == "darwin" ]]; then
        echo "/Library/Application Support/ClaudeCode/managed-settings.json"
    else
        echo "/etc/claude-code/managed-settings.json"
    fi
}

# clam_pkg_hint <pkg> -> a platform-appropriate install command for <pkg>,
# for use in print_warning/print_info hint lines (e.g. "jq is not installed").
clam_pkg_hint() {
    local pkg="$1"
    if [[ "$(clam_os)" == "darwin" ]]; then
        echo "brew install $pkg"
    else
        echo "sudo apt install $pkg"
    fi
}
