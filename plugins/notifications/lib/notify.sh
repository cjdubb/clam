#!/bin/bash
# Push notification function. Sourced by the plugin's push hook
# (scripts/push-notify.sh). Optionally source it into your interactive shell
# too: then the agent (and you) can call notify directly for an instant push
# instead of waiting for the 60s idle-event backstop.
#
# Usage:
#   notify <worktree-name> [worktree-dir]
#
# <worktree-name> is the worktree basename (the title shown on the push).
# [worktree-dir] is the worktree's directory; it defaults to $PWD (notify is
# normally called from inside the worktree). The worktree dir is where the
# .local/TODO.md that drives the body lives and where the push markers are
# dropped. Resolution order: the explicit [worktree-dir] (or $PWD) when it has
# a .local/, else the first match for <worktree-name> under $AGENT_DASH_ROOTS
# (colon-separated), else a /tmp fallback so no ghost .local is ever minted.
# A name passed as a path is reduced to its basename and doubles as the dir.
# There is no trees-dir env var: the worktree location is context-derived.
# Body content is auto-derived from the resolved worktree's .local/TODO.md when
# present (Blocked / Waiting For Decision / Awaiting User Review states get a
# richer body); otherwise the body is a generic "Needs your attention".
#
# Configuration (env vars):
#   CLAUDE_PUSH_NTFY_TOPIC      Required to enable. Topic name = password —
#                               must be unguessable.
#   CLAUDE_PUSH_NTFY_SERVER     Override (default: https://ntfy.sh).
#   CLAUDE_PUSH_DEBOUNCE_SECONDS Per-worktree cooldown (default: 120).
#   CLAUDE_PUSH_ACTIVITY_GATE_SECONDS  Skip push if the user submitted a prompt
#                               to any clam agent (in any worktree) within this
#                               window — they're presumably at the keyboard
#                               somewhere (default: 30; 0 disables).
#   CLAUDE_PUSH_DEDUP           Suppress a push whose body is byte-identical to
#                               the last one sent for this worktree, regardless
#                               of elapsed time (default: 1/on; 0 disables).
#                               Stops a recurring caller re-sending the same
#                               alert over and over.
#   CLAUDE_PUSH_BODY_MODE       "minimal" suppresses TODO state in the body.

# _clam_todo_field <todo-file> <label> -> trimmed value, tolerating a markdown-
# bold label (matches **State:** as well as the plain State:). Byte-identical
# twin of todo_field in ../lib/states.sh; notify.sh cannot source that lib
# because it is sourced into the interactive zsh shell, where the lib's
# BASH_SOURCE path resolution fails. Keep the two bodies in lockstep —
# notify.test.sh and the states suite both pin the bold/plain behavior. See #176.
_clam_todo_field() {
    grep -m1 -E "^[*]{0,2}$2:" "$1" 2>/dev/null \
        | sed -E "s/^[*]{0,2}$2:[*]{0,2}[[:space:]]*//; s/[[:space:]]*\$//"
}

notify() {
    local worktree="$1"
    local worktree_dir_arg="$2"

    if [[ -z "$worktree" ]]; then
        echo "notify: usage: notify <worktree-name> [worktree-dir]" >&2
        return 1
    fi
    if [[ -z "$CLAUDE_PUSH_NTFY_TOPIC" ]]; then
        return 0
    fi

    # A name passed as a path is reduced to its basename; the path doubles as
    # the worktree dir when the caller did not pass one explicitly.
    if [[ "$worktree" == */* ]]; then
        local wt_path="${worktree%/}"
        [[ -z "$worktree_dir_arg" ]] && worktree_dir_arg="$wt_path"
        worktree="${wt_path##*/}"
    fi

    # Resolve the worktree directory (holds .local/TODO.md and the push markers).
    # The worktree location is context-derived — there is no trees-dir env var.
    # Precedence: the explicit [worktree-dir] arg, defaulting to $PWD (notify is
    # normally called from inside the worktree); then the $AGENT_DASH_ROOTS scan
    # for a same-named worktree elsewhere (cross-worktree callers); then a /tmp
    # fallback so no ghost .local is ever minted. An adopted dir MUST already
    # contain .local/ — a plain dir that merely shares the name (a container, a
    # scratch checkout) must not be adopted, or the marker mkdir below would mint
    # a .local into it and agent-dash would render it as a row. A .local-less dir
    # arg / $PWD falls through to the roots scan so a real worktree elsewhere
    # still wins. The roots split is plain parameter expansion because this file
    # is sourced by both bash (hooks) and zsh (interactive shell).
    local worktree_dir=""
    local dir_candidate="${worktree_dir_arg:-$PWD}"
    dir_candidate="${dir_candidate%/}"
    if [[ -d "$dir_candidate/.local" && "${dir_candidate##*/}" == "$worktree" ]]; then
        worktree_dir="$dir_candidate"
    fi
    if [[ -z "$worktree_dir" ]]; then
        local root rest="${AGENT_DASH_ROOTS:-}"
        while [[ -n "$rest" ]]; do
            root="${rest%%:*}"
            if [[ "$rest" == *:* ]]; then rest="${rest#*:}"; else rest=""; fi
            if [[ -n "$root" && -d "$root/$worktree/.local" ]]; then
                worktree_dir="$root/$worktree"
                break
            fi
        done
    fi
    local marker_dir="/tmp/claude-push-markers/$worktree"
    [[ -n "$worktree_dir" ]] && marker_dir="$worktree_dir/.local"

    local body="Needs your attention"
    local priority="default"
    local tags="bell"

    # Blocked, Waiting For Decision, and Awaiting User Review are the summoning
    # states the agent calls notify for, and they get a rich body. Permission-
    # prompt Notification events also reach here (via push-notify.sh) and page
    # with the generic "Needs your attention" body below — an unattended session
    # wedged on a permission ask must summon regardless of TODO state. The idle
    # Notification path is state-gated upstream in push-notify.sh (it reaches
    # notify only in a summoning state), so a non-summoning idle fire no longer
    # leaks a generic push (clam-code#264 / P7). A stray direct call in some
    # other parked state still falls through to the generic body; the push-time
    # guards (debounce, dedup) keep that from becoming noise.
    local todo="$worktree_dir/.local/TODO.md"
    if [[ -n "$worktree_dir" && -f "$todo" ]]; then
        local state
        state=$(_clam_todo_field "$todo" State)
        case "$state" in
            "Blocked")
                local reason
                reason=$(_clam_todo_field "$todo" "Blocked Reason")
                body="Blocked: ${reason:-no reason given}"
                tags="warning"
                priority="high"
                ;;
            "Waiting For Decision")
                local decision
                decision=$(_clam_todo_field "$todo" "Decision Needed")
                body="Decision: ${decision:-not specified}"
                tags="question"
                priority="high"
                ;;
            "Awaiting User Review")
                local task
                task=$(_clam_todo_field "$todo" "Current Task")
                body="Awaiting your review: ${task:-draft PR ready for review}"
                tags="memo"
                priority="high"
                ;;
        esac
    fi

    # Append tmux session/window/pane so the user can jump straight back to
    # the right pane from the phone. Skipped silently when claude wasn't
    # launched inside tmux, or when body mode is minimal (stricter privacy).
    if [[ "$CLAUDE_PUSH_BODY_MODE" != "minimal" ]] \
        && [[ -n "$TMUX" ]] \
        && [[ -n "$TMUX_PANE" ]] \
        && command -v tmux &>/dev/null; then
        local tmux_session tmux_window tmux_pane
        tmux_session=$(tmux display-message -p -t "$TMUX_PANE" "#S" 2>/dev/null)
        tmux_window=$(tmux display-message -p -t "$TMUX_PANE" "#W" 2>/dev/null)
        tmux_pane=$(tmux display-message -p -t "$TMUX_PANE" "#P" 2>/dev/null)
        if [[ -n "$tmux_session" ]]; then
            body="${body}
tmux: ${tmux_session}:${tmux_window:-?}.${tmux_pane:-0}"
        fi
    fi

    if [[ "$CLAUDE_PUSH_BODY_MODE" == "minimal" ]]; then
        body="Needs you in $worktree"
    fi

    body="${body:0:256}"

    local now
    now=$(date +%s)

    # User activity gate: skip when the user submitted a prompt to any clam
    # agent within the threshold — typing into agent B should suppress agent
    # A's pushes too. Reads the cross-worktree timestamp written by
    # general/hooks/prompt-timestamp.sh.
    # Set CLAUDE_PUSH_ACTIVITY_GATE_SECONDS=0 to disable.
    local activity_gate="${CLAUDE_PUSH_ACTIVITY_GATE_SECONDS:-30}"
    if (( activity_gate > 0 )); then
        local stamp_file="/tmp/claude-prompt-timestamps/.global"
        if [[ -f "$stamp_file" ]]; then
            local prompt_time
            prompt_time=$(cat "$stamp_file" 2>/dev/null || echo 0)
            if (( now - prompt_time < activity_gate )); then
                return 0
            fi
        fi
    fi

    local debounce="${CLAUDE_PUSH_DEBOUNCE_SECONDS:-120}"
    local last_push_file="$marker_dir/.last-push"
    if [[ -f "$last_push_file" ]]; then
        local last
        last=$(cat "$last_push_file" 2>/dev/null || echo 0)
        if (( now - last < debounce )); then
            return 0
        fi
    fi

    # Content dedup: never send the same alert twice in a row. The debounce
    # above only guards a 120s window, so a recurring caller (e.g. a 15-min
    # watch cron babysitting a PR stuck awaiting a human merge) would otherwise
    # re-push a byte-identical "Blocked: merge X" body on every fire,
    # indefinitely. We remember the last body sent for this worktree and
    # suppress an identical repeat regardless of elapsed time. A blocker whose
    # text changed yields a different body and still pushes (that is new
    # information); a blocker that recurs after some *other* alert went out is
    # also not identical-to-last, so it pushes too. Set CLAUDE_PUSH_DEDUP=0 to
    # disable.
    local last_body_file="$marker_dir/.last-push-body"
    if [[ "${CLAUDE_PUSH_DEDUP:-1}" != "0" ]] && [[ -f "$last_body_file" ]]; then
        local last_body
        last_body=$(cat "$last_body_file" 2>/dev/null || true)
        if [[ "$body" == "$last_body" ]]; then
            return 0
        fi
    fi

    local server="${CLAUDE_PUSH_NTFY_SERVER:-https://ntfy.sh}"
    curl -fsS -m 5 \
        -H "Title: $worktree" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        -d "$body" \
        "$server/$CLAUDE_PUSH_NTFY_TOPIC" >/dev/null 2>&1 || true

    mkdir -p "$marker_dir" 2>/dev/null
    echo "$now" > "$last_push_file"
    printf '%s' "$body" > "$last_body_file"
}

# Make function visible to subshells (Claude Code's Bash tool, hook scripts, etc.).
# Guarded: zsh's `export -f` is `typeset -f` which prints the function body on
# source. Only bash needs (and supports) function export.
if [[ -n "$BASH_VERSION" ]]; then
    export -f notify
    export -f _clam_todo_field
fi
