#!/bin/bash
# Functional test for notify() — content dedup contract.
# Run: bash plugins/notifications/lib/notify.test.sh   (exits non-zero on failure)
#
# Isolates content-dedup by disabling the activity gate and the time debounce,
# and stubbing curl so nothing hits the network. Verifies that a byte-identical
# alert is sent once and suppressed thereafter, that a changed body pushes
# again, and that CLAUDE_PUSH_DEDUP=0 restores the old always-send behaviour.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export CLAUDE_PUSH_NTFY_TOPIC="dummy-topic"
export CLAUDE_PUSH_ACTIVITY_GATE_SECONDS=0
export CLAUDE_PUSH_DEBOUNCE_SECONDS=0
export TMUX="" TMUX_PANE="" CLAUDE_PUSH_BODY_MODE=""

TMPROOT=$(mktemp -d)
# Hermetic: there is no trees-dir env var any more; notify resolves a bare
# worktree name via $PWD, an explicit dir arg, or the $AGENT_DASH_ROOTS scan.
# Point $AGENT_DASH_ROOTS at this test's root so bare-name resolution is
# deterministic and never sees the developer machine's real roots.
export AGENT_DASH_ROOTS="$TMPROOT"
WT="testwt"
mkdir -p "$TMPROOT/$WT/.local"
CURL_LOG="$TMPROOT/curl.log"
: > "$CURL_LOG"

# Stub curl: record each invocation instead of sending, and capture the -d
# <body> payload plus the Priority/Tags headers so body-content and per-state
# metadata assertions (the #176 bold case, the #235 Awaiting User Review case)
# can read them.
LAST_BODY=""
LAST_PRIORITY=""
LAST_TAGS=""
curl() {
  echo "PUSH" >> "$CURL_LOG"
  while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then LAST_BODY="$2"; shift 2; continue; fi
    if [ "$1" = "-H" ]; then
      case "$2" in
        "Priority: "*) LAST_PRIORITY="${2#Priority: }" ;;
        "Tags: "*)     LAST_TAGS="${2#Tags: }" ;;
      esac
      shift 2; continue
    fi
    shift
  done
  return 0
}

# shellcheck source=./notify.sh
source "$SCRIPT_DIR/notify.sh"

write_todo() {
  printf 'State: Blocked\nBlocked Reason: %s\n' "$1" > "$TMPROOT/$WT/.local/TODO.md"
}
count() { wc -l < "$CURL_LOG" | tr -d ' '; }
FAILED=0
check() { # label expected
  local got; got=$(count)
  if [[ "$got" == "$2" ]]; then
    echo "PASS  $1 -> $got"
  else
    echo "FAIL  $1 -> got $got, expected $2"; FAILED=1
  fi
}

write_todo "merge PR #4519"
notify "$WT"; check "1st push (new)" 1
notify "$WT"; check "2nd identical (suppressed)" 1
notify "$WT"; check "3rd identical (suppressed)" 1

write_todo "rebase needed before enqueue"
notify "$WT"; check "changed blocker (push)" 2

write_todo "merge PR #4519"
notify "$WT"; check "recurs, differs from last (push)" 3

CLAUDE_PUSH_DEDUP=0 notify "$WT"; check "dedup disabled (push)" 4
CLAUDE_PUSH_DEDUP=0 notify "$WT"; check "dedup disabled identical (push)" 5

# --- Bold metadata: notify reads State + Blocked Reason from a **bold** TODO.md
# (#176). If the bold label were missed, State would be empty, no case arm would
# match, and the body would fall back to the generic "Needs your attention".
# Asserting the rich "Blocked: <reason>" body proves both fields parsed.
write_todo_bold() {
  printf '**State:** Blocked\n**Blocked Reason:** %s\n' "$1" > "$TMPROOT/$WT/.local/TODO.md"
}
body_has() { # label needle
  case "$LAST_BODY" in
    *"$2"*) echo "PASS  $1" ;;
    *) echo "FAIL  $1 -> body '$LAST_BODY' lacks '$2'"; FAILED=1 ;;
  esac
}
LAST_BODY=""
write_todo_bold "bold reason 42"
CLAUDE_PUSH_DEDUP=0 notify "$WT"
body_has "bold **State**/**Blocked Reason** -> rich body" "Blocked: bold reason 42"

# --- Worktree resolution (ghost-dir fix): a bare name must resolve to $PWD or
# an $AGENT_DASH_ROOTS match — never blind-mkdir under the trees root; a full
# path (or an explicit dir arg) is used directly; an unresolvable name falls
# back to /tmp markers. Rich-body assertions read the .last-push-body marker,
# which pins the marker location and the TODO.md resolution in one check.
file_has() { # label file needle
  if grep -q "$3" "$2" 2>/dev/null; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> $2 missing or lacks '$3'"; FAILED=1
  fi
}
no_ghost() { # label path
  if [[ -e "$2" ]]; then
    echo "FAIL  $1 -> ghost $2 exists"; FAILED=1
  else
    echo "PASS  $1"
  fi
}

OTHER_ROOT="$TMPROOT/other-root"

# Bare name, worktree outside the roots root, called from inside it ($PWD wins).
mkdir -p "$OTHER_ROOT/wt-pwd/.local"
printf 'State: Blocked\nBlocked Reason: pwd-resolved\n' > "$OTHER_ROOT/wt-pwd/.local/TODO.md"
( cd "$OTHER_ROOT/wt-pwd" && notify "wt-pwd" )
check "pwd-resolved bare name (push)" 7
file_has "pwd resolution: rich body + markers in worktree" \
  "$OTHER_ROOT/wt-pwd/.local/.last-push-body" "Blocked: pwd-resolved"
no_ghost "pwd resolution: no ghost under the trees root" "$TMPROOT/wt-pwd"

# Explicit name + dir args (the new signature the push-notify hook passes:
# notify <basename cwd> <cwd>).
mkdir -p "$OTHER_ROOT/wt-namedir/.local"
printf 'State: Blocked\nBlocked Reason: namedir-resolved\n' > "$OTHER_ROOT/wt-namedir/.local/TODO.md"
notify "wt-namedir" "$OTHER_ROOT/wt-namedir"
check "name + dir args (push)" 8
file_has "name+dir resolution: rich body + markers in worktree" \
  "$OTHER_ROOT/wt-namedir/.local/.last-push-body" "Blocked: namedir-resolved"
no_ghost "name+dir resolution: no ghost under the trees root" "$TMPROOT/wt-namedir"

# Full path as a single argument (back-compat: name derived from the path).
mkdir -p "$OTHER_ROOT/wt-path/.local"
printf 'State: Blocked\nBlocked Reason: path-resolved\n' > "$OTHER_ROOT/wt-path/.local/TODO.md"
notify "$OTHER_ROOT/wt-path"
check "full-path arg (push)" 9
file_has "path resolution: rich body + markers in worktree" \
  "$OTHER_ROOT/wt-path/.local/.last-push-body" "Blocked: path-resolved"
no_ghost "path resolution: no ghost under the trees root" "$TMPROOT/wt-path"

# Bare name resolving via the AGENT_DASH_ROOTS scan (first root misses).
mkdir -p "$OTHER_ROOT/rootB/wt-roots/.local"
printf 'State: Blocked\nBlocked Reason: roots-resolved\n' > "$OTHER_ROOT/rootB/wt-roots/.local/TODO.md"
AGENT_DASH_ROOTS="$OTHER_ROOT/rootA:$OTHER_ROOT/rootB" notify "wt-roots"
check "roots-scan bare name (push)" 10
file_has "roots resolution: rich body + markers in matched root" \
  "$OTHER_ROOT/rootB/wt-roots/.local/.last-push-body" "Blocked: roots-resolved"
no_ghost "roots resolution: no ghost under the trees root" "$TMPROOT/wt-roots"

# Unresolvable name: still pushes, markers land in /tmp, no ghost anywhere.
rm -rf "/tmp/claude-push-markers/wt-nowhere"
notify "wt-nowhere"
check "unresolvable name (push, generic body)" 11
file_has "unresolvable: markers in /tmp fallback" \
  "/tmp/claude-push-markers/wt-nowhere/.last-push-body" "Needs your attention"
no_ghost "unresolvable: no ghost under the trees root" "$TMPROOT/wt-nowhere"
rm -rf "/tmp/claude-push-markers/wt-nowhere"

# Existing dir WITHOUT .local: must not be adopted — a plain dir that merely
# shares the name (container, scratch checkout) would otherwise get a .local
# minted into it by the marker mkdir, and agent-dash would render it as a row
# (the 2026-07-10 ghost re-mint path). Markers fall back to /tmp instead.
mkdir -p "$TMPROOT/wt-plain"
rm -rf "/tmp/claude-push-markers/wt-plain"
notify "wt-plain"
check "plain dir bare name (push, generic body)" 12
file_has "plain dir: markers in /tmp fallback" \
  "/tmp/claude-push-markers/wt-plain/.last-push-body" "Needs your attention"
no_ghost "plain dir: no .local minted" "$TMPROOT/wt-plain/.local"
rm -rf "/tmp/claude-push-markers/wt-plain"

# Same for a full-path argument pointing at a .local-less dir.
mkdir -p "$OTHER_ROOT/wt-plainpath"
rm -rf "/tmp/claude-push-markers/wt-plainpath"
notify "$OTHER_ROOT/wt-plainpath"
check "plain dir full path (push, generic body)" 13
file_has "plain path: markers in /tmp fallback" \
  "/tmp/claude-push-markers/wt-plainpath/.last-push-body" "Needs your attention"
no_ghost "plain path: no .local minted" "$OTHER_ROOT/wt-plainpath/.local"
rm -rf "/tmp/claude-push-markers/wt-plainpath"

# A .local-less PWD basename match falls through to the roots scan, so the
# real worktree elsewhere still gets the rich body and the markers.
mkdir -p "$OTHER_ROOT/decoy/wt-shadow"
mkdir -p "$TMPROOT/wt-shadow/.local"
printf 'State: Blocked\nBlocked Reason: shadow-resolved\n' > "$TMPROOT/wt-shadow/.local/TODO.md"
( cd "$OTHER_ROOT/decoy/wt-shadow" && notify "wt-shadow" )
check "pwd without .local falls through to roots (push)" 14
file_has "shadow: rich body lands in the real worktree" \
  "$TMPROOT/wt-shadow/.local/.last-push-body" "Blocked: shadow-resolved"
no_ghost "shadow: no .local minted in decoy pwd" "$OTHER_ROOT/decoy/wt-shadow/.local"

# --- Awaiting User Review: rich body from Current Task, priority high, tag memo
# Parking at Awaiting User Review pages the user (#235). notify() builds the body
# from the Current Task field, falls back to a generic draft-ready line when that
# field is empty, and tags the push memo/high (mirroring the warning/high and
# question/high the other summoning states get).
field_eq() { # label expected actual
  if [[ "$3" == "$2" ]]; then echo "PASS  $1"; else echo "FAIL  $1 -> got '$3', expected '$2'"; FAILED=1; fi
}
write_todo_review() { # current-task ("" -> omit the field entirely)
  if [[ -n "$1" ]]; then
    printf 'State: Awaiting User Review\nCurrent Task: %s\n' "$1" > "$TMPROOT/$WT/.local/TODO.md"
  else
    printf 'State: Awaiting User Review\n' > "$TMPROOT/$WT/.local/TODO.md"
  fi
}

LAST_BODY=""; LAST_PRIORITY=""; LAST_TAGS=""
write_todo_review "polish the changelog wording"
CLAUDE_PUSH_DEDUP=0 notify "$WT"
body_has  "AUR body carries Current Task" "Awaiting your review: polish the changelog wording"
field_eq  "AUR priority high"  "high" "$LAST_PRIORITY"
field_eq  "AUR tag memo"       "memo" "$LAST_TAGS"

LAST_BODY=""
write_todo_review ""
CLAUDE_PUSH_DEDUP=0 notify "$WT"
body_has  "AUR body falls back when Current Task empty" "Awaiting your review: draft PR ready for review"

rm -rf "$TMPROOT"
if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
