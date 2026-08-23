#!/bin/bash
# Anchor pins for the live-view link tag (F33): context.sh reads the optional
# "Live view:" field from .local/TODO.md (todo-format protocol) and, when it
# holds an http(s) URL, appends an OSC 8 hyperlink labelled "live" to the
# state segment. Non-URL values ("none", empty, prose) degrade silently.
# These are wrap-tolerant fixed-string pins on the source, the same style as
# the round-6 suites in lego/tracking/render-doc.
# Run: bash plugins/statusline/scripts/live-view.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="$SCRIPT_DIR/context.sh"
PROTOCOL="$SCRIPT_DIR/../../../docs/protocols/todo-format.md"

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# Wrap-tolerant fixed-string search: collapse all whitespace runs to single
# spaces in both the needle and the file, then fixed-string grep.
has_fn() { # needle file
  local needle file
  needle="$(tr '\n\t' '  ' <<<"$1" | sed -E 's/ +/ /g; s/^ //; s/ $//')"
  file="$(tr '\n\t' '  ' <"$2" | sed -E 's/ +/ /g')"
  case "$file" in *"$needle"*) echo yes ;; *) echo no ;; esac
}

SRC="$CONTEXT"

check "context.sh reads the Live view field via todo_field" \
  "$(has_fn 'todo_field "$toplevel/.local/TODO.md" "Live view"' "$SRC")" "yes"
check "only http/https values produce a tag" \
  "$(has_fn 'http://*|https://*' "$SRC")" "yes"
check "the value is truncated at the first whitespace" \
  "$(has_fn 'live_url="${live_url%%[[:space:]]*}"' "$SRC")" "yes"
check "the tag is an OSC 8 hyperlink appended to the state segment" \
  "$(has_fn 'state_segment="${state_segment}' "$SRC")" "yes"
check "the OSC 8 open sequence wraps the URL" \
  "$(has_fn ']8;;'\''"${live_url}"' "$SRC")" "yes"
check "the link label is the plain word live (no emoji)" \
  "$(has_fn '\\live' "$SRC")" "yes"
check "the comment records silent degradation for non-URL values" \
  "$(has_fn 'degrades silently' "$SRC")" "yes"

# The protocol side of the seam: todo-format.md defines the optional field
# this reader consumes, so the coupling is artifact-shaped, not plugin-shaped.
check "todo-format.md defines the optional Live view field" \
  "$(has_fn '`Live view:`' "$PROTOCOL")" "yes"
check "todo-format.md gives non-URL values the no-link reading" \
  "$(has_fn 'no link to show' "$PROTOCOL")" "yes"

exit $FAILED
