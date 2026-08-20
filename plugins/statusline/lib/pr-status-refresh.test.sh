#!/bin/bash
# Functional test for pr-status-refresh.sh — pins the three resolution paths
# (branch PR / doc-scrape fallback / coordination), the `prs[]` wrapper and
# the deprecated `pr` mirror (single entry when exactly one PR, else null)
# across all of them, the TTL guard, the lock, and the preserve-on-failure
# semantics, per docs/protocols/pr-status-cache.md.
# Run: bash plugins/statusline/lib/pr-status-refresh.test.sh
#
# No network: `gh` is replaced by a mode-file-driven shim on PATH, and the
# fetch helper the engine resolves next to itself is replaced by a stub — the
# engine is copied into a temp dir with the stub alongside, so the shipped
# helper never runs. Worktrees are throwaway git repos under $TMPROOT.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# --- engine copy with a stub helper beside it: canned PR JSON for $1 ---
mkdir -p "$TMPROOT/engine"
cp "$SCRIPT_DIR/pr-status-refresh.sh" "$TMPROOT/engine/pr-status-refresh.sh"
ENGINE="$TMPROOT/engine/pr-status-refresh.sh"
cat > "$TMPROOT/engine/pr-status.sh" <<EOF
#!/bin/bash
[[ -f "$TMPROOT/helper-fail" ]] && exit 0
n=\$(printf '%s' "\$1" | grep -oE '[0-9]+\$')
[[ -n "\$n" ]] || exit 0
printf '{"number":%s,"title":"Stub PR %s","url":"https://github.com/test/repo/pull/%s","size":"S","state":"Open","reviews":"Approved","ci":"Pass","comments":0,"requested":""}\n' "\$n" "\$n" "\$n"
EOF
chmod +x "$TMPROOT/engine/pr-status.sh"

# --- gh shim: mode file drives `gh pr list` behavior ---
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/gh" <<SHIM
#!/bin/bash
mode=\$(cat "$TMPROOT/gh-mode" 2>/dev/null)
case "\$mode" in
  num)   printf '42' ;;
  empty) ;;
  fail)  exit 1 ;;
esac
SHIM
chmod +x "$TMPROOT/bin/gh"
gh_mode() { printf '%s' "$1" > "$TMPROOT/gh-mode"; }

new_wt() { # dir — throwaway worktree on a non-default branch, with .local
  mkdir -p "$1"
  git -C "$1" init -q -b master
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$1" checkout -q -b test/branch
  mkdir -p "$1/.local"
}

run_engine() { # wt [ttl]
  PATH="$TMPROOT/bin:$PATH" bash "$ENGINE" "$1" "${2:-60}"
}

# --- path 1 (single): branch has its own PR -> prs:[one entry], pr mirrors it ---
WT="$TMPROOT/s1"; new_wt "$WT"; gh_mode num
run_engine "$WT"
check "branch PR prs count"      "$(jq -r '.prs | length' "$WT/.local/.pr-status.json" 2>/dev/null)" "1"
check "branch PR prs[0].number"  "$(jq -r '.prs[0].number' "$WT/.local/.pr-status.json" 2>/dev/null)" "42"
check "branch PR mirrors pr"     "$(jq -r '.pr.number' "$WT/.local/.pr-status.json" 2>/dev/null)" "42"
check "MD written for branch PR" "$(grep -c 'PR #42' "$WT/.local/PR-STATUS.md")" "1"

# --- TTL guard: fresh cache untouched ---
printf '%s' '{"marker":true}' > "$WT/.local/.pr-status.json"
run_engine "$WT" 300
check "TTL guard skips fresh cache" "$(jq -r '.marker' "$WT/.local/.pr-status.json")" "true"

# --- preserve-on-failure: gh failure must not clobber the cache ---
touch -t 202601010000 "$WT/.local/.pr-status.json"
gh_mode fail
run_engine "$WT"
check "gh failure preserves cache" "$(jq -r '.marker' "$WT/.local/.pr-status.json")" "true"

# --- path 2: no branch PR -> doc-scrape fallback from TODO.md ---
WT="$TMPROOT/s4"; new_wt "$WT"; gh_mode empty
printf 'Shepherding https://github.com/test/repo/pull/777 here\n' > "$WT/.local/TODO.md"
run_engine "$WT"
check "fallback writes prs[]"     "$(jq -r '.prs | length' "$WT/.local/.pr-status.json" 2>/dev/null)" "1"
check "fallback PR number"        "$(jq -r '.prs[0].number' "$WT/.local/.pr-status.json" 2>/dev/null)" "777"
check "fallback mirrors lone pr"  "$(jq -r '.pr.number' "$WT/.local/.pr-status.json" 2>/dev/null)" "777"
check "fallback MD notes provenance" "$(grep -c 'referenced in' "$WT/.local/PR-STATUS.md")" "1"

# --- preserve-on-failure: URLs present but every fetch fails ---
printf '%s' '{"marker":"old"}' > "$WT/.local/.pr-status.json"
touch -t 202601010000 "$WT/.local/.pr-status.json"
touch "$TMPROOT/helper-fail"
run_engine "$WT"
check "all-fetch-fail preserves cache" "$(jq -r '.marker' "$WT/.local/.pr-status.json")" "old"
rm -f "$TMPROOT/helper-fail"

# --- genuine absence (none): no PR, no doc URLs -> prs:[], pr:null ---
WT="$TMPROOT/s6"; new_wt "$WT"; gh_mode empty
run_engine "$WT"
check "genuine no-PR empty prs"      "$(jq -r '.prs | length' "$WT/.local/.pr-status.json" 2>/dev/null)" "0"
check "genuine no-PR has prs key"    "$(jq -r 'has("prs")' "$WT/.local/.pr-status.json" 2>/dev/null)" "true"
check "genuine no-PR writes pr:null" "$(jq -r '.pr' "$WT/.local/.pr-status.json" 2>/dev/null)" "null"
check "genuine no-PR MD sentinel"    "$(grep -c 'No PRs to display' "$WT/.local/PR-STATUS.md")" "1"

# --- path 3: coordination (non-empty marker) prefers structured **PR:** field over TODO.md ---
WT="$TMPROOT/s7"; new_wt "$WT"; gh_mode empty
echo "TEST-1" > "$WT/.local/.orchestrator"
printf -- '- **PR:** https://github.com/test/repo/pull/888\n' > "$WT/.local/PLAN.md"
printf 'unrelated https://github.com/test/repo/pull/999\n' > "$WT/.local/TODO.md"
run_engine "$WT"
check "coordination prs count"     "$(jq -r '.prs | length' "$WT/.local/.pr-status.json" 2>/dev/null)" "1"
check "coordination uses **PR:** field" "$(jq -r '.prs[0].number' "$WT/.local/.pr-status.json" 2>/dev/null)" "888"
check "coordination mirrors lone pr" "$(jq -r '.pr.number' "$WT/.local/.pr-status.json" 2>/dev/null)" "888"

# --- coordination: plans/*.md **PR:** fields are scraped too ---
WT="$TMPROOT/s7b"; new_wt "$WT"; gh_mode empty
echo "TEST-1" > "$WT/.local/.orchestrator"
mkdir -p "$WT/.local/plans"
printf -- '- **PR:** https://github.com/test/repo/pull/321\n' > "$WT/.local/plans/001-x.md"
run_engine "$WT"
check "plans dir **PR:** field scraped" "$(jq -r '.prs[0].number' "$WT/.local/.pr-status.json" 2>/dev/null)" "321"

# --- coordination (non-empty marker) with no URLs anywhere -> empty prs[] ---
WT="$TMPROOT/s8"; new_wt "$WT"
echo "TEST-1" > "$WT/.local/.orchestrator"
run_engine "$WT"
check "coordination no-URLs empty prs" "$(jq -r '.prs | length' "$WT/.local/.pr-status.json" 2>/dev/null)" "0"
check "coordination no-URLs pr null"   "$(jq -r '.pr' "$WT/.local/.pr-status.json" 2>/dev/null)" "null"

# --- empty .orchestrator marker: topology only, no active effort ---
# It must NOT take the coordination path (which would scrape 888 from the plan
# into prs[]); it falls through to the standalone path and resolves the
# branch's own PR via gh (42). Proves the shape decision keys on marker CONTENT.
WT="$TMPROOT/s8b"; new_wt "$WT"; gh_mode num
touch "$WT/.local/.orchestrator"
printf -- '- **PR:** https://github.com/test/repo/pull/888\n' > "$WT/.local/PLAN.md"
run_engine "$WT"
check "empty marker resolves branch PR, not doc scrape" "$(jq -r '.prs[0].number' "$WT/.local/.pr-status.json" 2>/dev/null)" "42"
check "empty marker mirrors branch PR into pr"          "$(jq -r '.pr.number' "$WT/.local/.pr-status.json" 2>/dev/null)" "42"

# --- no-PR fallback reaches WORKGRAPH.md when TODO.md and PLAN.md are silent ---
WT="$TMPROOT/s8c"; new_wt "$WT"; gh_mode empty
printf 'no urls here\n' > "$WT/.local/TODO.md"
printf -- '- Notes: lands as https://github.com/test/repo/pull/654\n' > "$WT/.local/WORKGRAPH.md"
run_engine "$WT"
check "WORKGRAPH.md scraped as last fallback" "$(jq -r '.prs[0].number' "$WT/.local/.pr-status.json" 2>/dev/null)" "654"

# --- lock: fresh lock blocks, stale (>120s) lock is broken and cleaned ---
# Real engine locks carry a pid file, so the stale one must too: breaking it
# exercises rm -rf on a non-empty dir, and the second run's own pid must win.
WT="$TMPROOT/s9"; new_wt "$WT"; gh_mode num
mkdir "$WT/.local/.pr-status-refresh.lock"
printf '99999' > "$WT/.local/.pr-status-refresh.lock/pid"
run_engine "$WT"
check "fresh lock blocks refresh" "$([[ -f "$WT/.local/.pr-status.json" ]] && echo written || echo skipped)" "skipped"
touch -t 202601010000 "$WT/.local/.pr-status-refresh.lock"
run_engine "$WT"
check "stale lock broken, refresh runs" "$(jq -r '.pr.number' "$WT/.local/.pr-status.json" 2>/dev/null)" "42"
check "lock cleaned up after run" "$([[ -d "$WT/.local/.pr-status-refresh.lock" ]] && echo present || echo gone)" "gone"

# --- fallback with multiple URLs: array order pinned to sorted URL order ---
# Fetches run in parallel, so completion order varies; the emitted prs[] must
# not (consumer positions would swap between refreshes).
WT="$TMPROOT/s12"; new_wt "$WT"; gh_mode empty
printf 'see https://github.com/test/repo/pull/777 and https://github.com/test/repo/pull/555\n' > "$WT/.local/TODO.md"
run_engine "$WT"
check "multi-PR prs count"  "$(jq -r '.prs | length' "$WT/.local/.pr-status.json" 2>/dev/null)" "2"
check "multi-PR order pinned to sorted URLs" "$(jq -r '[.prs[].number | tostring] | join(",")' "$WT/.local/.pr-status.json" 2>/dev/null)" "555,777"
check "multi-PR pr null (N>1)" "$(jq -r '.pr' "$WT/.local/.pr-status.json" 2>/dev/null)" "null"

# --- subdir caller normalises to the worktree root ---
WT="$TMPROOT/s10"; new_wt "$WT"; gh_mode num
mkdir -p "$WT/deep/sub"
run_engine "$WT/deep/sub"
check "subdir caller writes at toplevel" "$(jq -r '.pr.number' "$WT/.local/.pr-status.json" 2>/dev/null)" "42"

# --- default branches bail ---
WT="$TMPROOT/s11"; new_wt "$WT"; git -C "$WT" checkout -q master; gh_mode num
run_engine "$WT"
check "master branch bails" "$([[ -f "$WT/.local/.pr-status.json" ]] && echo written || echo skipped)" "skipped"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
